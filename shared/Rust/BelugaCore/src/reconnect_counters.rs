//! Stateless reconnect-counter proposals over copied values.
//!
//! Native code retains active-pair, identity and request authentication, builds
//! the original initiator/responder, and commits the exact proposed counters only
//! after that constructor returns. A proposal is not a stored ledger or success.
#![forbid(unsafe_code)]

pub const ABI_VERSION: u32 = 1;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawState {
    pub abi_version: u32,
    pub reserved: u32,
    pub next_outbound: u64,
    pub highest_accepted: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawEvent {
    pub opcode: u32,
    pub reserved: u32,
    pub request_sequence: u64,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Decision {
    Proposed = 0,
    SequenceExhausted = 1,
    StaleSequence = 2,
    InvalidInput = 3,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub candidate_state: RawState,
    pub decision: u32,
    pub reserved: u32,
}

#[derive(Clone, Copy)]
struct OutboundSequence(u64);

#[derive(Clone, Copy)]
struct AcceptedPeerSequence(u64);

#[derive(Clone, Copy)]
struct IncomingRequestSequence(u64);

#[derive(Clone, Copy)]
enum Operation {
    ReserveOutbound,
    AdmitInbound(IncomingRequestSequence),
}

impl Operation {
    fn decode(raw: RawEvent) -> Option<Self> {
        if raw.reserved != 0 { return None; }
        match raw.opcode {
            0 if raw.request_sequence == 0 => Some(Self::ReserveOutbound),
            1 => Some(Self::AdmitInbound(IncomingRequestSequence(raw.request_sequence))),
            _ => None,
        }
    }
}

#[derive(Clone, Copy)]
struct Counters {
    outbound: OutboundSequence,
    highest: AcceptedPeerSequence,
}

impl Counters {
    fn decode(raw: RawState) -> Option<Self> {
        if raw.abi_version != ABI_VERSION || raw.reserved != 0 { return None; }
        Some(Self {
            outbound: OutboundSequence(raw.next_outbound),
            highest: AcceptedPeerSequence(raw.highest_accepted),
        })
    }

    fn raw(self) -> RawState {
        RawState {
            abi_version: ABI_VERSION,
            reserved: 0,
            next_outbound: self.outbound.0,
            highest_accepted: self.highest.0,
        }
    }

    fn apply(self, operation: Operation) -> (Self, Decision) {
        match operation {
            Operation::ReserveOutbound => {
                // Zero reaches the original native constructor; only MAX is
                // numeric exhaustion. The caller has not committed this value.
                if self.outbound.0 == u64::MAX {
                    return (self, Decision::SequenceExhausted);
                }
                (
                    Self {
                        outbound: OutboundSequence(self.outbound.0 + 1),
                        highest: self.highest,
                    },
                    Decision::Proposed,
                )
            }
            Operation::AdmitInbound(incoming) => {
                if incoming.0 <= self.highest.0 {
                    return (self, Decision::StaleSequence);
                }
                (
                    Self {
                        outbound: self.outbound,
                        highest: AcceptedPeerSequence(incoming.0),
                    },
                    Decision::Proposed,
                )
            }
        }
    }
}

#[must_use]
pub fn step(abi_version: u32, before: RawState, event: RawEvent) -> RawResult {
    let refused = || RawResult {
        candidate_state: before,
        decision: Decision::InvalidInput as u32,
        reserved: 0,
    };
    if abi_version != ABI_VERSION { return refused(); }
    let Some(counters) = Counters::decode(before) else { return refused(); };
    let Some(operation) = Operation::decode(event) else { return refused(); };
    let (candidate, decision) = counters.apply(operation);
    RawResult { candidate_state: candidate.raw(), decision: decision as u32, reserved: 0 }
}
