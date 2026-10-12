//! Catalog-checkpoint attempt admission and terminal revocation.
//!
//! A returned candidate is not installed state and is never persistence evidence.
//! Native code must validate it before the synchronous store effect, then commit
//! that exact candidate only after the actual catalog call successfully returns.
#![forbid(unsafe_code)]

pub const ABI_VERSION: u32 = 1;
pub const BOUND: u32 = 1;
pub const REVOKED: u32 = 2;
pub const KNOWN_FLAGS: u32 = BOUND | REVOKED;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawState {
    pub abi_version: u32,
    pub flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawEvent {
    pub opcode: u32,
    pub owner_valid: u32,
    pub binding_matches: u32,
    pub snapshot_matches: u32,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Decision {
    Allowed = 0,
    StaleAttempt = 1,
    InvalidInput = 3,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub candidate_state: RawState,
    pub decision: u32,
}

#[derive(Clone, Copy)]
enum Binding { Empty, Present }

#[derive(Clone, Copy)]
enum Retirement { Open, Revoked }

// Distinct domains prevent a binding-match fact from substituting for snapshot
// equality or native process-owner validity inside a policy helper.
#[derive(Clone, Copy)]
enum OwnerValidity { Invalid, Valid }

#[derive(Clone, Copy)]
enum BindingMatch { Different, Exact }

#[derive(Clone, Copy)]
enum SnapshotMatch { Different, Exact }

#[derive(Clone, Copy)]
enum Operation {
    Add { owner: OwnerValidity },
    Update { owner: OwnerValidity, binding: BindingMatch },
    Revoke,
    Readback { snapshot: SnapshotMatch },
}

impl Operation {
    fn decode(raw: RawEvent) -> Option<Self> {
        // Even unused fact fields belong to the declared Boolean ABI domain.
        // Valid 0/1 unused fields are ignored, not a new authorization condition.
        let owner = match raw.owner_valid {
            0 => OwnerValidity::Invalid,
            1 => OwnerValidity::Valid,
            _ => return None,
        };
        let binding = match raw.binding_matches {
            0 => BindingMatch::Different,
            1 => BindingMatch::Exact,
            _ => return None,
        };
        let snapshot = match raw.snapshot_matches {
            0 => SnapshotMatch::Different,
            1 => SnapshotMatch::Exact,
            _ => return None,
        };
        match raw.opcode {
            0 => Some(Self::Add { owner }),
            1 => Some(Self::Update { owner, binding }),
            2 => Some(Self::Revoke),
            3 => Some(Self::Readback { snapshot }),
            _ => None,
        }
    }
}

#[derive(Clone, Copy)]
struct Cursor {
    binding: Binding,
    retirement: Retirement,
}

impl Cursor {
    fn decode(raw: RawState) -> Option<Self> {
        if raw.abi_version != ABI_VERSION || raw.flags & !KNOWN_FLAGS != 0 {
            return None;
        }
        Some(Self {
            binding: if raw.flags & BOUND == 0 { Binding::Empty } else { Binding::Present },
            retirement: if raw.flags & REVOKED == 0 { Retirement::Open } else { Retirement::Revoked },
        })
    }

    fn raw(self) -> RawState {
        RawState {
            abi_version: ABI_VERSION,
            flags: match self.binding { Binding::Empty => 0, Binding::Present => BOUND }
                | match self.retirement { Retirement::Open => 0, Retirement::Revoked => REVOKED },
        }
    }

    fn apply(self, operation: Operation) -> (Self, Decision) {
        match operation {
            Operation::Add { owner } => {
                if matches!(self.retirement, Retirement::Revoked)
                    || matches!(owner, OwnerValidity::Invalid)
                    || matches!(self.binding, Binding::Present) {
                    return (self, Decision::StaleAttempt);
                }
                (Self { binding: Binding::Present, ..self }, Decision::Allowed)
            }
            Operation::Update { owner, binding } => {
                if matches!(self.retirement, Retirement::Revoked)
                    || matches!(owner, OwnerValidity::Invalid)
                    || matches!(self.binding, Binding::Empty)
                    || matches!(binding, BindingMatch::Different) {
                    return (self, Decision::StaleAttempt);
                }
                (self, Decision::Allowed)
            }
            Operation::Revoke => (
                Self { retirement: Retirement::Revoked, ..self }, Decision::Allowed,
            ),
            Operation::Readback { snapshot } => {
                // Readback intentionally ignores revocation, owner and binding.
                // Fresh native storage must have been loaded before this fact.
                if matches!(snapshot, SnapshotMatch::Different) {
                    (self, Decision::StaleAttempt)
                } else {
                    (self, Decision::Allowed)
                }
            }
        }
    }
}

#[must_use]
pub fn initial() -> RawState {
    RawState { abi_version: ABI_VERSION, flags: 0 }
}

#[must_use]
pub fn step(abi_version: u32, before: RawState, event: RawEvent) -> RawResult {
    let refused = || RawResult { candidate_state: before, decision: Decision::InvalidInput as u32 };
    if abi_version != ABI_VERSION { return refused(); }
    let Some(cursor) = Cursor::decode(before) else { return refused(); };
    let Some(operation) = Operation::decode(event) else { return refused(); };
    let (candidate, decision) = cursor.apply(operation);
    RawResult { candidate_state: candidate.raw(), decision: decision as u32 }
}
