//! Bounded handoff ledger. Native adapters bind exact receipts and immutable
//! envelopes to opaque tokens, and consume revocation/completion effects.
use core::num::NonZeroU64;
use crate::ABI_VERSION;
use crate::host_lifecycle::TransitionStatus;

pub const REVOKE_HOST: u32 = 1;
pub const RETURN_HOST_REPLY: u32 = 2;
pub const EMIT_VIEWER_COMPLETION: u32 = 4;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct HandoffTransactionsState {
    pub abi_version: u32,
    pub host_phase: u32,
    pub host_receipt: u64,
    pub host_envelope: u64,
    pub host_result: u32,
    pub reserved: u32,
    pub viewer_envelope: u64,
    pub viewer_offer: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct HandoffTransactionsEvent {
    pub opcode: u32,
    pub argument: u32,
    pub receipt_token: u64,
    pub envelope_token: u64,
    pub offer_token: u64,
    pub result: u32,
    pub reserved: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct HandoffTransactionsResult {
    pub state: HandoffTransactionsState,
    pub status: u32,
    pub effects: u32,
    pub revoked_receipt: u64,
    pub completed_offer: u64,
    pub completed_result: u32,
    pub reserved: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Token(NonZeroU64);
impl Token {
    const fn parse(value: u64) -> Option<Self> {
        match NonZeroU64::new(value) { Some(value) => Some(Self(value)), None => None }
    }
    const fn raw(self) -> u64 { self.0.get() }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
enum Completion { MacPaused = 1, NotApplied = 2, Unknown = 3 }
impl Completion {
    const fn parse(value: u32) -> Option<Self> {
        match value { 1 => Some(Self::MacPaused), 2 => Some(Self::NotApplied), 3 => Some(Self::Unknown), _ => None }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Host {
    Empty,
    Admitted { receipt: Token, envelope: Token },
    Replied { receipt: Token, envelope: Token, result: Completion },
}
impl Host {
    const fn receipt(self) -> Option<Token> {
        match self { Self::Empty => None, Self::Admitted { receipt, .. } | Self::Replied { receipt, .. } => Some(receipt) }
    }
    const fn is_busy(self) -> bool { matches!(self, Self::Admitted { .. }) }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Viewer { envelope: Token, offer: Token }
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Ledger { host: Host, viewer: Option<Viewer> }

enum Event {
    Admit { receipt: Token, envelope: Token },
    Finish { receipt: Token, envelope: Token, result: Completion },
    Begin { envelope: Token, offer: Token, valid: bool },
    Complete { envelope: Token, result: Completion },
    Expire { offer: Token },
    Clear,
    Unknown,
}
impl Event {
    fn parse(event: HandoffTransactionsEvent) -> Option<Self> {
        if event.reserved != 0 { return None; }
        Some(match event.opcode {
            0 => Self::Admit { receipt: Token::parse(event.receipt_token)?, envelope: Token::parse(event.envelope_token)? },
            1 => Self::Finish { receipt: Token::parse(event.receipt_token)?, envelope: Token::parse(event.envelope_token)?, result: Completion::parse(event.result)? },
            2 => Self::Begin { envelope: Token::parse(event.envelope_token)?, offer: Token::parse(event.offer_token)?, valid: match event.argument { 0 => false, 1 => true, _ => return None } },
            3 => Self::Complete { envelope: Token::parse(event.envelope_token)?, result: Completion::parse(event.result)? },
            4 => Self::Expire { offer: Token::parse(event.offer_token)? },
            5 => Self::Clear,
            _ => Self::Unknown,
        })
    }
}

impl Ledger {
    const EMPTY: Self = Self { host: Host::Empty, viewer: None };

    fn parse(state: HandoffTransactionsState) -> Option<Self> {
        if state.abi_version != ABI_VERSION || state.reserved != 0 { return None; }
        let host = match state.host_phase {
            0 if state.host_receipt == 0 && state.host_envelope == 0 && state.host_result == 0 => Host::Empty,
            1 if state.host_result == 0 => Host::Admitted { receipt: Token::parse(state.host_receipt)?, envelope: Token::parse(state.host_envelope)? },
            2 => Host::Replied { receipt: Token::parse(state.host_receipt)?, envelope: Token::parse(state.host_envelope)?, result: Completion::parse(state.host_result)? },
            _ => return None,
        };
        let viewer = match (Token::parse(state.viewer_envelope), Token::parse(state.viewer_offer)) {
            (None, None) => None,
            (Some(envelope), Some(offer)) => Some(Viewer { envelope, offer }),
            _ => return None,
        };
        Some(Self { host, viewer })
    }

    const fn wire(self) -> HandoffTransactionsState {
        let (host_phase, host_receipt, host_envelope, host_result) = match self.host {
            Host::Empty => (0, 0, 0, 0),
            Host::Admitted { receipt, envelope } => (1, receipt.raw(), envelope.raw(), 0),
            Host::Replied { receipt, envelope, result } => (2, receipt.raw(), envelope.raw(), result as u32),
        };
        let (viewer_envelope, viewer_offer) = match self.viewer {
            Some(viewer) => (viewer.envelope.raw(), viewer.offer.raw()), None => (0, 0),
        };
        HandoffTransactionsState { abi_version: ABI_VERSION, host_phase, host_receipt, host_envelope, host_result, reserved: 0, viewer_envelope, viewer_offer }
    }

    fn apply(mut self, event: Event) -> HandoffTransactionsResult {
        use TransitionStatus::{Applied, NoChange, Rejected};
        let mut output = outcome(self, Rejected);
        match event {
            Event::Admit { receipt, envelope } => {
                if self.host.is_busy() { return output; }
                revoke(&mut output, self.host.receipt());
                self.host = Host::Admitted { receipt, envelope };
                output.status = Applied as u32;
            }
            Event::Finish { receipt, envelope, result } => {
                match self.host {
                    Host::Admitted { receipt: owned_receipt, envelope: owned_envelope }
                        if owned_receipt == receipt && owned_envelope == envelope => {
                            revoke(&mut output, Some(receipt));
                            self.host = Host::Replied { receipt, envelope, result };
                            output.status = Applied as u32;
                        }
                    Host::Replied { receipt: owned_receipt, envelope: owned_envelope, result: cached }
                        if owned_receipt == receipt && owned_envelope == envelope && cached == result => {
                            output.status = NoChange as u32;
                        }
                    _ => return output,
                }
                output.effects |= RETURN_HOST_REPLY;
            }
            Event::Begin { envelope, offer, valid } => {
                if self.viewer.is_some() || !valid { return output; }
                self.viewer = Some(Viewer { envelope, offer });
                output.status = Applied as u32;
            }
            Event::Complete { envelope, result } => {
                let Some(viewer) = self.viewer.filter(|viewer| viewer.envelope == envelope) else { return output; };
                emit(&mut output, viewer.offer, result);
                self.viewer = None;
                output.status = Applied as u32;
            }
            Event::Expire { offer } => {
                let Some(viewer) = self.viewer.filter(|viewer| viewer.offer == offer) else { return output; };
                emit(&mut output, viewer.offer, Completion::Unknown);
                self.viewer = None;
                output.status = Applied as u32;
            }
            Event::Clear => {
                revoke(&mut output, self.host.receipt());
                if let Some(viewer) = self.viewer { emit(&mut output, viewer.offer, Completion::Unknown); }
                output.status = if self == Self::EMPTY { NoChange } else { Applied } as u32;
                self = Self::EMPTY;
            }
            Event::Unknown => return output,
        }
        output.state = self.wire();
        output
    }
}

const fn outcome(ledger: Ledger, status: TransitionStatus) -> HandoffTransactionsResult {
    HandoffTransactionsResult { state: ledger.wire(), status: status as u32, effects: 0, revoked_receipt: 0, completed_offer: 0, completed_result: 0, reserved: 0 }
}
fn revoke(output: &mut HandoffTransactionsResult, receipt: Option<Token>) {
    if let Some(receipt) = receipt { output.effects |= REVOKE_HOST; output.revoked_receipt = receipt.raw(); }
}
fn emit(output: &mut HandoffTransactionsResult, offer: Token, result: Completion) {
    output.effects |= EMIT_VIEWER_COMPLETION;
    output.completed_offer = offer.raw();
    output.completed_result = result as u32;
}

#[must_use]
pub const fn initial() -> HandoffTransactionsState { Ledger::EMPTY.wire() }

/// Invalid state/ABI clears authority and returns only exact-token revocation
/// and unknown completion effects. Malformed events cannot change valid state.
#[must_use]
pub fn step(abi_version: u32, state: HandoffTransactionsState, event: HandoffTransactionsEvent) -> HandoffTransactionsResult {
    let Some(ledger) = Ledger::parse(state).filter(|_| abi_version == ABI_VERSION) else {
        let mut output = outcome(Ledger::EMPTY, TransitionStatus::InvalidInput);
        revoke(&mut output, Token::parse(state.host_receipt));
        if state.viewer_envelope != 0 {
            if let Some(offer) = Token::parse(state.viewer_offer) { emit(&mut output, offer, Completion::Unknown); }
        }
        return output;
    };
    match Event::parse(event) {
        Some(event) => ledger.apply(event),
        None => outcome(ledger, TransitionStatus::InvalidInput),
    }
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_handoff_transactions_initial() -> HandoffTransactionsState { initial() }

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_handoff_transactions_step(
    abi_version: u32, state: HandoffTransactionsState, event: HandoffTransactionsEvent,
) -> HandoffTransactionsResult { step(abi_version, state, event) }
