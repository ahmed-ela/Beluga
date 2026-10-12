//! Bounded host control-plane lifecycle. Swift bridges String identity to opaque
//! nonzero tokens; Rust owns transition admission and independent owner slots.
use core::num::NonZeroU64;
use crate::ABI_VERSION;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct HostLifecycleState {
    pub abi_version: u32,
    pub run_state: u32,
    pub active_token: u64,
    pub media_token: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct HostLifecycleEvent {
    pub opcode: u32,
    pub argument: u32,
    pub exchange_token: u64,
    pub original_utf8_length: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct HostLifecycleResult {
    pub state: HostLifecycleState,
    pub status: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum TransitionStatus {
    Applied = 0,
    Rejected = 1,
    NoChange = 2,
    InvalidInput = 3,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct ExchangeToken(NonZeroU64);

impl ExchangeToken {
    const fn new(raw: u64) -> Option<Self> {
        match NonZeroU64::new(raw) {
            Some(value) => Some(Self(value)),
            None => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Lifecycle {
    Idle,
    Inviting,
    Paired { active: Option<ExchangeToken>, media: Option<ExchangeToken> },
    Stopped,
}

impl Lifecycle {
    const fn parse(state: HostLifecycleState) -> Option<Self> {
        if state.abi_version != ABI_VERSION {
            return None;
        }
        if state.run_state == 2 {
            return Some(Self::Paired {
                active: ExchangeToken::new(state.active_token),
                media: ExchangeToken::new(state.media_token),
            });
        }
        if state.active_token != 0 || state.media_token != 0 {
            return None;
        }
        match state.run_state {
            0 => Some(Self::Idle),
            1 => Some(Self::Inviting),
            3 => Some(Self::Stopped),
            _ => None,
        }
    }

    const fn wire(self) -> HostLifecycleState {
        let (run_state, active_token, media_token) = match self {
            Self::Idle => (0, 0, 0),
            Self::Inviting => (1, 0, 0),
            Self::Paired { active, media } => (2, token_value(active), token_value(media)),
            Self::Stopped => (3, 0, 0),
        };
        HostLifecycleState { abi_version: ABI_VERSION, run_state, active_token, media_token }
    }

    fn apply(self, event: HostLifecycleEvent) -> (Self, TransitionStatus) {
        use TransitionStatus::{Applied, NoChange, Rejected};
        match event.opcode {
            0 => match (self, event.argument) {
                (Self::Idle, 0) => (Self::Inviting, Applied),
                (Self::Idle, 1) => (Self::Paired { active: None, media: None }, Applied),
                _ => (self, Rejected),
            },
            1 => match self {
                Self::Inviting => (Self::Paired { active: None, media: None }, Applied),
                _ => (self, Rejected),
            },
            2 => match (self, ExchangeToken::new(event.exchange_token)) {
                (Self::Paired { active: None, media }, Some(token))
                    if (1..=64).contains(&event.original_utf8_length) =>
                        (Self::Paired { active: Some(token), media }, Applied),
                _ => (self, Rejected),
            },
            3 => match (self, ExchangeToken::new(event.exchange_token)) {
                (Self::Paired { active: Some(active), media: None }, Some(token)) if active == token =>
                    (Self::Paired { active: Some(active), media: Some(token) }, Applied),
                _ => (self, Rejected),
            },
            4 => match (self, ExchangeToken::new(event.exchange_token)) {
                (Self::Paired { active: Some(active), media }, Some(token)) if active == token =>
                    (Self::Paired { active: None, media }, Applied),
                _ => (self, NoChange),
            },
            5 => match (self, ExchangeToken::new(event.exchange_token)) {
                (Self::Paired { active, media: Some(media) }, Some(token)) if media == token =>
                    (Self::Paired { active, media: None }, Applied),
                _ => (self, NoChange),
            },
            6 => if self == Self::Stopped { (self, NoChange) } else { (Self::Stopped, Applied) },
            _ => (self, Rejected),
        }
    }
}

const fn token_value(token: Option<ExchangeToken>) -> u64 {
    match token { Some(value) => value.0.get(), None => 0 }
}

#[must_use]
pub const fn initial() -> HostLifecycleState {
    Lifecycle::Idle.wire()
}

/// Malformed state/ABI terminally fails closed; a rejected valid transition is
/// byte-for-byte unchanged. Only admission to availability checks original size.
#[must_use]
pub fn step(abi_version: u32, state: HostLifecycleState, event: HostLifecycleEvent) -> HostLifecycleResult {
    let Some(lifecycle) = Lifecycle::parse(state).filter(|_| abi_version == ABI_VERSION) else {
        return HostLifecycleResult { state: Lifecycle::Stopped.wire(), status: TransitionStatus::InvalidInput as u32 };
    };
    let (next, status) = lifecycle.apply(event);
    HostLifecycleResult { state: next.wire(), status: status as u32 }
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_host_lifecycle_initial() -> HostLifecycleState {
    initial()
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_host_lifecycle_step(
    abi_version: u32, state: HostLifecycleState, event: HostLifecycleEvent,
) -> HostLifecycleResult {
    step(abi_version, state, event)
}
