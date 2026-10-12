//! Pure copied-scalar policy for the original native media-command gate.
//! Native locking, String/Set membership, object identity and execution remain outside Rust.
//! Preserve original UInt64 wrapping exactly; zero is a legal wrapped counter value.

pub const ABI_VERSION: u32 = 1;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawState {
    pub abi_version: u32,
    pub is_open: u32,
    pub lifecycle: u64,
    pub command_epoch: u64,
}

impl RawState {
    pub const fn initial() -> Self {
        Self { abi_version: ABI_VERSION, is_open: 0, lifecycle: 0, command_epoch: 0 }
    }

    fn is_valid(self) -> bool { self.abi_version == ABI_VERSION && self.is_open <= 1 }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawEvent {
    pub opcode: u32,
    pub context_is_current: u32,
    pub reserved0: u32,
    pub reserved1: u32,
    pub candidate_lifecycle: u64,
    pub candidate_command_epoch: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawResult {
    pub abi_version: u32,
    pub status: u32,
    pub allowed: u32,
    pub reserved: u32,
    pub state: RawState,
}

impl RawResult {
    /// Refusal representation only; a native owner must never publish this as a reset.
    pub const fn rejected() -> Self {
        Self { abi_version: ABI_VERSION, status: 0, allowed: 0, reserved: 0,
            state: RawState::initial() }
    }
}

#[derive(Clone, Copy)]
enum Operation { Open, Close, Invalidate, Lifecycle, Capture, Admit }

fn operation(event: RawEvent) -> Option<Operation> {
    if event.context_is_current > 1 || event.reserved0 != 0 || event.reserved1 != 0 {
        return None;
    }
    match event.opcode {
        0..=2 if event.context_is_current == 0 && event.candidate_lifecycle == 0
            && event.candidate_command_epoch == 0 => match event.opcode {
                0 => Some(Operation::Open),
                1 => Some(Operation::Close),
                _ => Some(Operation::Invalidate),
            },
        3 if event.context_is_current == 0 && event.candidate_command_epoch == 0 =>
            Some(Operation::Lifecycle),
        4 if event.candidate_lifecycle == 0 && event.candidate_command_epoch == 0 =>
            Some(Operation::Capture),
        5 => Some(Operation::Admit),
        _ => None,
    }
}

#[must_use]
pub fn transition(mut state: RawState, event: RawEvent) -> RawResult {
    if !state.is_valid() { return RawResult::rejected(); }
    let Some(operation) = operation(event) else { return RawResult::rejected(); };
    let allowed = match operation {
        Operation::Open => {
            state.lifecycle = state.lifecycle.wrapping_add(1);
            state.command_epoch = state.command_epoch.wrapping_add(1);
            state.is_open = 1;
            false
        }
        Operation::Close => {
            state.lifecycle = state.lifecycle.wrapping_add(1);
            state.command_epoch = state.command_epoch.wrapping_add(1);
            state.is_open = 0;
            false
        }
        Operation::Invalidate => {
            state.command_epoch = state.command_epoch.wrapping_add(1);
            false
        }
        Operation::Lifecycle => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle,
        Operation::Capture => state.is_open == 1 && event.context_is_current == 1,
        Operation::Admit => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle
            && state.command_epoch == event.candidate_command_epoch && event.context_is_current == 1,
    };
    RawResult { abi_version: ABI_VERSION, status: 1, allowed: u32::from(allowed), reserved: 0, state }
}

/// Recompute every field. Accepted ordinary refusal is valid; malformed-input denial is not.
#[must_use]
pub fn result_is_valid(state: RawState, event: RawEvent, result: RawResult) -> u32 {
    let expected = transition(state, event);
    u32::from(expected.status == 1 && expected == result)
}
