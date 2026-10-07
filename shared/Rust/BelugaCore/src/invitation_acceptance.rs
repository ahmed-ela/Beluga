//! Scalar-only invitation acceptance policy preserving the frozen native method order.
//! Frozen native source SHA: ed62b5fdee54b2676a45e6d98038cd4b971f377d0835f675e7399a261005759e.
//! Native UUID equality, callbacks, exact record values and persistence remain native.
//! Prepared callbacks are synchronous, stack-local, one-use native custody records.

#![forbid(unsafe_code)]

pub const ABI_VERSION: u32 = 1;
pub const ARMED: u32 = 1;
pub const ADMISSION_CALLBACK: u32 = 2;
pub const COMPLETION_CALLBACK: u32 = 4;
pub const ADMISSION_CONSUMED: u32 = 8;
const KNOWN_FLAGS: u32 = 15;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct RawState {
    pub abi_version: u32,
    pub flags: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct RawEvent {
    pub opcode: u32,
    pub generation_matches: u32,
    pub phase: u32,
    pub admission_callback_present: u32,
    pub prepared_kind: u32,
    pub prepared_flags: u32,
    pub owner_matches: u32,
    pub callback_outcome: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct RawOutput {
    pub state: RawState,
    pub callback_success_state: RawState,
    pub status: u32,
    pub completion_succeeded: u32,
    pub callback_kind: u32,
    pub prepared_flags: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum Opcode {
    Arm = 0,
    PrepareAdmission = 1,
    PrepareCompletion = 2,
    AcknowledgeCallback = 3,
    Cancel = 4,
}

impl Opcode {
    fn decode(value: u32) -> Option<Self> {
        match value {
            0 => Some(Self::Arm),
            1 => Some(Self::PrepareAdmission),
            2 => Some(Self::PrepareCompletion),
            3 => Some(Self::AcknowledgeCallback),
            4 => Some(Self::Cancel),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum Status {
    Applied = 0,
    Ignored = 1,
    NeedsCallback = 2,
    NotRecoverable = 3,
    NotActive = 4,
    CallbackFailed = 5,
    StalePreparedPlan = 6,
    InvalidInput = 7,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum CallbackKind {
    None = 0,
    Admission = 1,
    Completion = 2,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum Phase {
    Other = 0,
    AcceptedIssued = 1,
    Active = 2,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum State {
    Idle,
    Armed {
        has_admission_callback: bool,
        admission_consumed: bool,
    },
}

impl State {
    fn decode(raw: RawState) -> Option<Self> {
        if raw.abi_version != ABI_VERSION || raw.flags & !KNOWN_FLAGS != 0 {
            return None;
        }
        if raw.flags == 0 {
            return Some(Self::Idle);
        }
        // Original arm always receives a nonoptional completion callback.
        if raw.flags & (ARMED | COMPLETION_CALLBACK) != (ARMED | COMPLETION_CALLBACK) {
            return None;
        }
        Some(Self::Armed {
            has_admission_callback: raw.flags & ADMISSION_CALLBACK != 0,
            admission_consumed: raw.flags & ADMISSION_CONSUMED != 0,
        })
    }

    fn raw(self) -> RawState {
        let flags = match self {
            Self::Idle => 0,
            Self::Armed { has_admission_callback, admission_consumed } => {
                ARMED | COMPLETION_CALLBACK
                    | if has_admission_callback { ADMISSION_CALLBACK } else { 0 }
                    | if admission_consumed { ADMISSION_CONSUMED } else { 0 }
            }
        };
        RawState { abi_version: ABI_VERSION, flags }
    }

}

fn flag(value: u32) -> Option<bool> {
    match value {
        0 => Some(false),
        1 => Some(true),
        _ => None,
    }
}

fn phase(value: u32) -> Option<Phase> {
    match value {
        0 => Some(Phase::Other),
        1 => Some(Phase::AcceptedIssued),
        2 => Some(Phase::Active),
        _ => None,
    }
}

fn output(raw: RawState, status: Status) -> RawOutput {
    RawOutput {
        state: raw,
        callback_success_state: raw,
        status: status as u32,
        completion_succeeded: 0,
        callback_kind: CallbackKind::None as u32,
        prepared_flags: 0,
    }
}

fn changed(state: State, completed: bool) -> RawOutput {
    let mut result = output(state.raw(), Status::Applied);
    result.completion_succeeded = completed as u32;
    result
}

fn prepared(state: State, kind: CallbackKind, success: State) -> RawOutput {
    let mut result = output(state.raw(), Status::NeedsCallback);
    result.callback_success_state = success.raw();
    result.callback_kind = kind as u32;
    result.prepared_flags = state.raw().flags;
    result
}

fn admission(state: State, raw: RawState, event: RawEvent) -> RawOutput {
    let Some(matches) = flag(event.generation_matches) else {
        return output(raw, Status::InvalidInput);
    };
    let State::Armed { has_admission_callback, admission_consumed } = state else {
        return output(raw, Status::Ignored);
    };
    // Guard order is intentional: phase is not consulted on foreign or consumed calls.
    // MUTATION_ANCHOR: admission_guard_before_phase
    if !matches || admission_consumed {
        return output(raw, Status::Ignored);
    }
    match phase(event.phase) {
        None => output(raw, Status::InvalidInput),
        Some(Phase::Other | Phase::Active) => output(raw, Status::NotRecoverable),
        Some(Phase::AcceptedIssued) => {
            let success = State::Armed { has_admission_callback, admission_consumed: true };
            if has_admission_callback {
                prepared(state, CallbackKind::Admission, success)
            } else {
                // A nil native callback is still a successful consume-once call.
                // MUTATION_ANCHOR: nil_admission_consumes
                changed(success, false)
            }
        }
    }
}

fn completion(state: State, raw: RawState, event: RawEvent) -> RawOutput {
    let Some(matches) = flag(event.generation_matches) else {
        return output(raw, Status::InvalidInput);
    };
    if state == State::Idle || !matches {
        return output(raw, Status::Ignored);
    }
    match phase(event.phase) {
        None => output(raw, Status::InvalidInput),
        Some(Phase::Other | Phase::AcceptedIssued) => output(raw, Status::NotActive),
        Some(Phase::Active) => {
            // Recovery may complete an active pair without an earlier admission call.
            // MUTATION_ANCHOR: completion_without_admission
            prepared(state, CallbackKind::Completion, State::Idle)
        }
    }
}

fn acknowledge(state: State, raw: RawState, event: RawEvent) -> RawOutput {
    let Some(owner_matches) = flag(event.owner_matches) else {
        return output(raw, Status::InvalidInput);
    };
    // This projection comes only from the exact one-use native prepared record.
    // It distinguishes same-generation rearm even if the scalar flags match.
    if !owner_matches {
        return output(raw, Status::StalePreparedPlan);
    }
    let Some(before) = State::decode(RawState { abi_version: ABI_VERSION, flags: event.prepared_flags }) else {
        return output(raw, Status::InvalidInput);
    };
    if before != state {
        return output(raw, Status::StalePreparedPlan);
    }
    let success = match (event.prepared_kind, state) {
        (1, State::Armed { has_admission_callback: true, admission_consumed: false }) => {
            State::Armed { has_admission_callback: true, admission_consumed: true }
        }
        (2, State::Armed { .. }) => State::Idle,
        _ => return output(raw, Status::InvalidInput),
    };
    match event.callback_outcome {
        1 => {
            // MUTATION_ANCHOR: callback_success_commits
            changed(success, event.prepared_kind == CallbackKind::Completion as u32)
        }
        2 => {
            // Actual native thrown error is propagated by the native adapter.
            // MUTATION_ANCHOR: callback_failure_preserves
            output(raw, Status::CallbackFailed)
        }
        _ => output(raw, Status::InvalidInput),
    }
}

/// Copied-value transition only. This function never invokes, owns, or retries a callback.
/// Unused event fields are outside that opcode's projection domain.
#[must_use]
pub fn step(abi_version: u32, raw: RawState, event: RawEvent) -> RawOutput {
    if abi_version != ABI_VERSION {
        return output(raw, Status::InvalidInput);
    }
    let Some(state) = State::decode(raw) else {
        return output(raw, Status::InvalidInput);
    };
    let Some(opcode) = Opcode::decode(event.opcode) else {
        return output(raw, Status::InvalidInput);
    };
    match opcode {
        Opcode::Arm => match flag(event.admission_callback_present) {
            None => output(raw, Status::InvalidInput),
            Some(present) => {
                // Native arm replaces generation and BOTH callbacks even when flags are unchanged.
                // MUTATION_ANCHOR: arm_resets_admission
                changed(State::Armed { has_admission_callback: present, admission_consumed: false }, false)
            }
        },
        Opcode::PrepareAdmission => admission(state, raw, event),
        Opcode::PrepareCompletion => completion(state, raw, event),
        Opcode::AcknowledgeCallback => acknowledge(state, raw, event),
        Opcode::Cancel => match flag(event.generation_matches) {
            None => output(raw, Status::InvalidInput),
            Some(true) if state != State::Idle => changed(State::Idle, false),
            Some(_) => output(raw, Status::Ignored),
        },
    }
}

/// Canonical copied state; no native generation, closure or credential is owned here.
#[must_use]
pub fn initial() -> RawState {
    State::Idle.raw()
}
