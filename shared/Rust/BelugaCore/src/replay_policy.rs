#![forbid(unsafe_code)]

use std::num::NonZeroU64;

pub const ABI_VERSION: u32 = 1;
pub const WINDOW_SIZE: u64 = 64;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawState {
    pub abi_version: u32,
    pub has_highest: u32,
    pub highest: u64,
    pub bitmap: u64,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Decision {
    Accepted = 0,
    Duplicate = 1,
    OutsideWindow = 2,
    InvalidInput = 3,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub state: RawState,
    pub decision: u32,
    pub reserved: u32,
}

/// Sequence zero is a legitimate first or reordered input, not a missing token.
#[derive(Clone, Copy)]
struct Sequence(u64);

#[derive(Clone, Copy)]
struct ReceivedWindow(NonZeroU64);

#[derive(Clone, Copy)]
enum ReplayState {
    Empty,
    Populated { highest: Sequence, received: ReceivedWindow },
}

impl ReplayState {
    fn from_raw(raw: RawState) -> Option<Self> {
        if raw.abi_version != ABI_VERSION {
            return None;
        }
        match raw.has_highest {
            0 if raw.highest == 0 && raw.bitmap == 0 => Some(Self::Empty),
            1 if raw.bitmap & 1 == 1 => {
                // A bit for a negative UInt64 sequence can never be produced.
                if raw.highest < 63 {
                    let representable = (1_u64 << (raw.highest + 1)) - 1;
                    if raw.bitmap & !representable != 0 {
                        return None;
                    }
                }
                Some(Self::Populated {
                    highest: Sequence(raw.highest),
                    received: ReceivedWindow(NonZeroU64::new(raw.bitmap)?),
                })
            }
            _ => None,
        }
    }

    fn raw(self) -> RawState {
        match self {
            Self::Empty => initial(),
            Self::Populated { highest, received } => RawState {
                abi_version: ABI_VERSION,
                has_highest: 1,
                highest: highest.0,
                bitmap: received.0.get(),
            },
        }
    }

    fn admit(self, input: Sequence) -> (Self, Decision) {
        match self {
            Self::Empty => (Self::Populated {
                highest: input,
                received: ReceivedWindow(NonZeroU64::new(1).expect("one is nonzero")),
            }, Decision::Accepted),
            Self::Populated { highest, received } if input.0 > highest.0 => {
                // Strict ordering makes subtraction overflow impossible.
                let distance = input.0 - highest.0;
                let bits = if distance >= WINDOW_SIZE {
                    1
                } else {
                    // This branch admits only shifts 1...63, never shift 64.
                    (received.0.get() << distance) | 1
                };
                (Self::Populated {
                    highest: input,
                    received: ReceivedWindow(NonZeroU64::new(bits).expect("new highest sets bit zero")),
                }, Decision::Accepted)
            }
            Self::Populated { highest, received } => {
                let age = highest.0 - input.0;
                if age >= WINDOW_SIZE {
                    return (self, Decision::OutsideWindow);
                }
                let mask = 1_u64 << age;
                if received.0.get() & mask != 0 {
                    return (self, Decision::Duplicate);
                }
                (Self::Populated {
                    highest,
                    received: ReceivedWindow(NonZeroU64::new(received.0.get() | mask)
                        .expect("existing bit zero remains set")),
                }, Decision::Accepted)
            }
        }
    }
}

/// Creates a value only. The native authenticated peer/exchange owner decides
/// when a replacement peer is entitled to a fresh value.
pub fn initial() -> RawState {
    RawState { abi_version: ABI_VERSION, has_highest: 0, highest: 0, bitmap: 0 }
}

/// Pointer-free private proposal; no native authentication, callbacks or reset.
/// Malformed copied input and every replay refusal preserve input bytes/fields.
pub fn step(abi_version: u32, before: RawState, sequence: u64) -> RawResult {
    if abi_version != ABI_VERSION {
        return RawResult { state: before, decision: Decision::InvalidInput as u32, reserved: 0 };
    }
    let Some(state) = ReplayState::from_raw(before) else {
        return RawResult { state: before, decision: Decision::InvalidInput as u32, reserved: 0 };
    };
    let (after, decision) = state.admit(Sequence(sequence));
    RawResult { state: after.raw(), decision: decision as u32, reserved: 0 }
}
