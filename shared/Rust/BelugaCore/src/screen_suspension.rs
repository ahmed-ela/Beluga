//! Complete copied-scalar suspension transcript, with native protocol payload custody outside Rust.
//! Preserve the frozen native owner's value semantics and dormant entrypoints. No wire rewrite.
pub const ABI_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
enum Phase {
    Idle = 0, Active = 1, Suspending = 2, Suspended = 3, AwaitingMarker = 4,
    AwaitingMarkerPresentation = 5, AwaitingRealFrame = 6,
    AwaitingRealPresentation = 7, AwaitingFinalization = 8,
}
impl Phase {
    fn decode(raw: u32) -> Option<Self> {
        match raw {
            0 => Some(Self::Idle), 1 => Some(Self::Active), 2 => Some(Self::Suspending),
            3 => Some(Self::Suspended), 4 => Some(Self::AwaitingMarker),
            5 => Some(Self::AwaitingMarkerPresentation), 6 => Some(Self::AwaitingRealFrame),
            7 => Some(Self::AwaitingRealPresentation), 8 => Some(Self::AwaitingFinalization),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
enum Opcode {
    Project = 0, Activate = 1, Retire = 2, Abort = 3, Begin = 4, Cover = 5,
    Inactive = 6, BeginResume = 7, MarkerReady = 8, MarkerPresentation = 9,
    ResumeReady = 10, ResumeRequest = 11, Commit = 12, Rollback = 13,
    Cancel = 14, Owns = 15, Authorize = 16, BindingValid = 17,
}
impl Opcode {
    fn decode(raw: u32) -> Option<Self> {
        match raw {
            0 => Some(Self::Project), 1 => Some(Self::Activate), 2 => Some(Self::Retire),
            3 => Some(Self::Abort), 4 => Some(Self::Begin), 5 => Some(Self::Cover),
            6 => Some(Self::Inactive), 7 => Some(Self::BeginResume), 8 => Some(Self::MarkerReady),
            9 => Some(Self::MarkerPresentation), 10 => Some(Self::ResumeReady),
            11 => Some(Self::ResumeRequest), 12 => Some(Self::Commit), 13 => Some(Self::Rollback),
            14 => Some(Self::Cancel), 15 => Some(Self::Owns), 16 => Some(Self::Authorize),
            17 => Some(Self::BindingValid), _ => None,
        }
    }

    fn masks(self) -> (u32, u32, bool, bool, bool) {
        // flags, native facts, standalone screen, binding, input notice pair
        match self {
            Self::Project | Self::Retire => (0, 0, false, false, false),
            Self::Activate => (0, 0, true, true, false),
            Self::Abort | Self::Owns | Self::BindingValid => (0, 0, false, true, false),
            Self::Begin | Self::Cancel => (1, 0, false, true, false),
            Self::Cover => (0, 1 << 1, false, true, true),
            Self::Inactive => (0, 1 << 0, false, true, true),
            Self::BeginResume => (0, 1 << 2, false, true, false),
            Self::MarkerReady => (0, (1 << 3) | (1 << 4), false, true, true),
            Self::MarkerPresentation => (0, 1 << 5, false, true, true),
            Self::ResumeReady => (0, (1 << 3) | (1 << 6) | (1 << 7), false, true, true),
            Self::ResumeRequest => (0, (1 << 3) | (1 << 8) | (1 << 9), false, true, true),
            Self::Commit => (0, 1 << 10, false, true, true),
            Self::Rollback => (0, (1 << 0) | (1 << 11), false, true, true),
            Self::Authorize => (0, (1 << 3) | (1 << 10), false, true, true),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
enum CustodyAction {
    None = 0, Activated = 1, Retired = 2, BeganSuspension = 3, Aborted = 4,
    JoinCompleted = 5, BeganResume = 6, MarkerReady = 7, MarkerPresentation = 8,
    ResumeReady = 9, ResumeRequest = 10, Finalized = 11,
    CancelledToSuspended = 12, CancelledToIdle = 13, RolledBack = 14,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawScreenSuspensionState {
    pub abi_version: u32,
    pub phase: u32,
    pub next_generation: u64,
    pub screen_request_id: u64,
    pub suspension_generation: u64,
    pub peer_generation: u64,
    pub visibility_epoch: u64,
    pub recovery_epoch: u64,
    pub prior_screen_request_id: u64,
    pub prior_suspension_generation: u64,
    pub cover_confirmed: u32,
    pub inactive_confirmed: u32,
    pub custody_mask: u32,
    pub reserved: u32,
}

impl RawScreenSuspensionState {
    pub const fn initial() -> Self {
        Self {
            abi_version: ABI_VERSION, phase: 0, next_generation: 1,
            screen_request_id: 0, suspension_generation: 0, peer_generation: 0,
            visibility_epoch: 0, recovery_epoch: 0, prior_screen_request_id: 0,
            prior_suspension_generation: 0, cover_confirmed: 0, inactive_confirmed: 0,
            custody_mask: 0, reserved: 0,
        }
    }

    fn is_valid(self) -> bool {
        let Some(phase) = Phase::decode(self.phase) else { return false; };
        if self.abi_version != ABI_VERSION || self.next_generation == 0 || self.reserved != 0
            || self.cover_confirmed > 1 || self.inactive_confirmed > 1 { return false; }
        if phase == Phase::Idle {
            let mut empty = Self::initial();
            empty.next_generation = self.next_generation;
            return self == empty;
        }
        if self.screen_request_id == 0 || self.peer_generation == 0 || self.visibility_epoch == 0 {
            return false;
        }
        if phase != Phase::Suspending && (self.prior_screen_request_id != 0
            || self.prior_suspension_generation != 0 || self.cover_confirmed != 0
            || self.inactive_confirmed != 0) { return false; }
        match phase {
            Phase::Idle => false,
            Phase::Active => if self.suspension_generation == 0 { self.custody_mask == 0 }
                else { self.custody_mask == 1 },
            Phase::Suspending => {
                if self.suspension_generation == 0
                    || self.cover_confirmed + self.inactive_confirmed > 1 { return false; }
                match self.custody_mask {
                    1 => self.prior_screen_request_id == 0 && self.prior_suspension_generation == 0,
                    3 => self.prior_screen_request_id == self.screen_request_id
                        && self.prior_suspension_generation != 0,
                    _ => false,
                }
            },
            Phase::Suspended => self.suspension_generation != 0 && self.custody_mask == 1,
            Phase::AwaitingMarker => self.suspension_generation != 0 && self.custody_mask == 5,
            Phase::AwaitingMarkerPresentation => self.suspension_generation != 0 && self.custody_mask == 13,
            Phase::AwaitingRealFrame => self.suspension_generation != 0 && self.custody_mask == 21,
            Phase::AwaitingRealPresentation => self.suspension_generation != 0 && self.custody_mask == 37,
            Phase::AwaitingFinalization => self.suspension_generation != 0 && self.custody_mask == 69,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawScreenSuspensionEvent {
    pub opcode: u32,
    pub flags: u32,
    pub native_facts: u32,
    pub reserved: u32,
    pub screen_request_id: u64,
    pub peer_generation: u64,
    pub visibility_epoch: u64,
    pub recovery_epoch: u64,
    pub notice_screen_request_id: u64,
    pub notice_generation: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawScreenSuspensionResult {
    pub abi_version: u32,
    pub status: u32,
    pub accepted: u32,
    pub custody_action: u32,
    pub state: RawScreenSuspensionState,
    pub query_flags: u32,
    pub reserved: u32,
    pub produced_notice_screen_request_id: u64,
    pub produced_notice_generation: u64,
}

impl RawScreenSuspensionResult {
    /// Canonical denial is evidence, never a successor/reset that the native owner may adopt.
    pub const fn rejected() -> Self {
        Self {
            abi_version: ABI_VERSION, status: 0, accepted: 0, custody_action: 0,
            state: RawScreenSuspensionState::initial(), query_flags: 0, reserved: 0,
            produced_notice_screen_request_id: 0, produced_notice_generation: 0,
        }
    }
}

fn event_operation(event: RawScreenSuspensionEvent) -> Option<Opcode> {
    let operation = Opcode::decode(event.opcode)?;
    let (flags, facts, screen, binding, notice) = operation.masks();
    if event.reserved != 0 || event.flags & !flags != 0 || event.native_facts & !facts != 0 {
        return None;
    }
    if !screen && event.screen_request_id != 0 { return None; }
    if !binding && (event.peer_generation != 0 || event.visibility_epoch != 0
        || event.recovery_epoch != 0) { return None; }
    if !notice && (event.notice_screen_request_id != 0 || event.notice_generation != 0) {
        return None;
    }
    Some(operation)
}

fn binding_matches(state: RawScreenSuspensionState, event: RawScreenSuspensionEvent) -> bool {
    state.peer_generation == event.peer_generation
        && state.visibility_epoch == event.visibility_epoch
        && state.recovery_epoch == event.recovery_epoch
}

fn notice_matches(state: RawScreenSuspensionState, event: RawScreenSuspensionEvent) -> bool {
    state.screen_request_id == event.notice_screen_request_id
        && state.suspension_generation == event.notice_generation
}

fn facts(event: RawScreenSuspensionEvent, required: u32) -> bool {
    event.native_facts & required == required
}

fn clear_join(state: &mut RawScreenSuspensionState) {
    state.prior_screen_request_id = 0;
    state.prior_suspension_generation = 0;
    state.cover_confirmed = 0;
    state.inactive_confirmed = 0;
}

fn enter(state: &mut RawScreenSuspensionState, phase: Phase, mask: u32) {
    clear_join(state);
    state.phase = phase as u32;
    state.custody_mask = mask;
}

fn initial_with_counter(counter: u64) -> RawScreenSuspensionState {
    let mut state = RawScreenSuspensionState::initial();
    state.next_generation = counter;
    state
}

fn projection(state: RawScreenSuspensionState, phase: Phase) -> u32 {
    // All healthy projections are exhaustive on the typed phase; no native admission fallback.
    match phase {
        Phase::Idle => 0,
        Phase::Active if state.custody_mask == 0 => 72,
        Phase::Active => 248,
        Phase::Suspending => 250,
        Phase::Suspended => 249,
        Phase::AwaitingMarker | Phase::AwaitingMarkerPresentation | Phase::AwaitingRealFrame
        | Phase::AwaitingRealPresentation | Phase::AwaitingFinalization => 253,
    }
}

/// Whole scalar transcript. Native facts are copied from unchanged typed payload predicates.
#[must_use]
pub fn transition(mut state: RawScreenSuspensionState, event: RawScreenSuspensionEvent)
    -> RawScreenSuspensionResult
{
    if !state.is_valid() { return RawScreenSuspensionResult::rejected(); }
    let Some(operation) = event_operation(event) else { return RawScreenSuspensionResult::rejected(); };
    let Some(phase) = Phase::decode(state.phase) else { return RawScreenSuspensionResult::rejected(); };
    let mut accepted = false;
    let mut action = CustodyAction::None;
    let mut produced_screen = 0;
    let mut produced_generation = 0;
    match operation {
        Opcode::Project => { accepted = true; },
        Opcode::Activate => {
            if event.screen_request_id > 0 && event.peer_generation > 0 && event.visibility_epoch > 0 {
                state = initial_with_counter(state.next_generation);
                state.phase = Phase::Active as u32;
                state.screen_request_id = event.screen_request_id;
                state.peer_generation = event.peer_generation;
                state.visibility_epoch = event.visibility_epoch;
                state.recovery_epoch = event.recovery_epoch;
                accepted = true; action = CustodyAction::Activated;
            }
        },
        Opcode::Retire => {
            state = initial_with_counter(state.next_generation);
            accepted = true; action = CustodyAction::Retired;
        },
        Opcode::Abort => {
            if phase == Phase::Suspending && binding_matches(state, event) && state.inactive_confirmed == 0 {
                state.suspension_generation = state.prior_suspension_generation;
                let mask = if state.prior_suspension_generation == 0 { 0 } else { 1 };
                enter(&mut state, Phase::Active, mask);
                accepted = true; action = CustodyAction::Aborted;
            }
        },
        Opcode::Begin => {
            if event.flags == 1 && event.peer_generation > 0 && event.visibility_epoch > 0
                && phase == Phase::Active && binding_matches(state, event) {
                let prior = state.suspension_generation;
                state.prior_screen_request_id = if prior == 0 { 0 } else { state.screen_request_id };
                state.prior_suspension_generation = prior;
                state.suspension_generation = state.next_generation;
                state.next_generation = state.next_generation.wrapping_add(1);
                if state.next_generation == 0 { state.next_generation = 1; }
                state.phase = Phase::Suspending as u32;
                state.cover_confirmed = 0; state.inactive_confirmed = 0;
                state.custody_mask = if prior == 0 { 1 } else { 3 };
                accepted = true; action = CustodyAction::BeganSuspension;
                produced_screen = state.screen_request_id;
                produced_generation = state.suspension_generation;
            }
        },
        Opcode::Cover => {
            if phase == Phase::Suspending && binding_matches(state, event) && notice_matches(state, event)
                && facts(event, 1 << 1) && state.cover_confirmed == 0 {
                state.cover_confirmed = 1;
                if state.inactive_confirmed == 1 {
                    enter(&mut state, Phase::Suspended, 1); action = CustodyAction::JoinCompleted;
                }
                accepted = true;
            }
        },
        Opcode::Inactive => {
            if phase == Phase::Suspending && state.peer_generation == event.peer_generation
                && state.recovery_epoch == event.recovery_epoch
                && event.visibility_epoch >= state.visibility_epoch
                && notice_matches(state, event) && facts(event, 1 << 0) && state.inactive_confirmed == 0 {
                state.visibility_epoch = event.visibility_epoch;
                state.inactive_confirmed = 1;
                if state.cover_confirmed == 1 {
                    enter(&mut state, Phase::Suspended, 1); action = CustodyAction::JoinCompleted;
                }
                accepted = true;
            }
        },
        Opcode::BeginResume => {
            if phase == Phase::Suspended && binding_matches(state, event) && facts(event, 1 << 2) {
                enter(&mut state, Phase::AwaitingMarker, 5);
                accepted = true; action = CustodyAction::BeganResume;
            }
        },
        Opcode::MarkerReady => {
            if phase == Phase::AwaitingMarker && binding_matches(state, event) && notice_matches(state, event)
                && facts(event, (1 << 3) | (1 << 4)) {
                enter(&mut state, Phase::AwaitingMarkerPresentation, 13);
                accepted = true; action = CustodyAction::MarkerReady;
            }
        },
        Opcode::MarkerPresentation => {
            if phase == Phase::AwaitingMarkerPresentation && binding_matches(state, event)
                && notice_matches(state, event) && facts(event, 1 << 5) {
                enter(&mut state, Phase::AwaitingRealFrame, 21);
                accepted = true; action = CustodyAction::MarkerPresentation;
            }
        },
        Opcode::ResumeReady => {
            if phase == Phase::AwaitingRealFrame && binding_matches(state, event) && notice_matches(state, event)
                && facts(event, (1 << 3) | (1 << 6) | (1 << 7)) {
                enter(&mut state, Phase::AwaitingRealPresentation, 37);
                accepted = true; action = CustodyAction::ResumeReady;
            }
        },
        Opcode::ResumeRequest => {
            if phase == Phase::AwaitingRealPresentation && binding_matches(state, event)
                && notice_matches(state, event) && facts(event, (1 << 3) | (1 << 8) | (1 << 9)) {
                enter(&mut state, Phase::AwaitingFinalization, 69);
                accepted = true; action = CustodyAction::ResumeRequest;
            }
        },
        Opcode::Commit => {
            if phase == Phase::AwaitingFinalization && binding_matches(state, event)
                && notice_matches(state, event) && facts(event, 1 << 10) {
                enter(&mut state, Phase::Active, 1);
                accepted = true; action = CustodyAction::Finalized;
            }
        },
        Opcode::Rollback => {
            if phase == Phase::Active && state.custody_mask == 1 && binding_matches(state, event)
                && notice_matches(state, event) && facts(event, (1 << 0) | (1 << 11)) {
                enter(&mut state, Phase::Suspended, 1);
                accepted = true; action = CustodyAction::RolledBack;
            }
        },
        Opcode::Cancel => {
            if state.custody_mask & 1 != 0 && binding_matches(state, event) {
                if event.flags == 1 {
                    enter(&mut state, Phase::Suspended, 1); action = CustodyAction::CancelledToSuspended;
                } else {
                    state = initial_with_counter(state.next_generation); action = CustodyAction::CancelledToIdle;
                }
                accepted = true;
            }
        },
        Opcode::Owns => { accepted = phase != Phase::Idle && binding_matches(state, event); },
        Opcode::Authorize => {
            accepted = phase == Phase::AwaitingFinalization && binding_matches(state, event)
                && notice_matches(state, event) && facts(event, (1 << 3) | (1 << 10));
        },
        Opcode::BindingValid => { accepted = event.peer_generation > 0 && event.visibility_epoch > 0; },
    }
    // A producer defect cannot emit a canonical grant with an impossible successor.
    if !state.is_valid() { return RawScreenSuspensionResult::rejected(); }
    let Some(successor_phase) = Phase::decode(state.phase) else { return RawScreenSuspensionResult::rejected(); };
    RawScreenSuspensionResult {
        abi_version: ABI_VERSION, status: 1, accepted: u32::from(accepted), custody_action: action as u32,
        state, query_flags: projection(state, successor_phase), reserved: 0,
        produced_notice_screen_request_id: produced_screen,
        produced_notice_generation: produced_generation,
    }
}

/// The actual verifier recomputes the complete result. No canonical denial can become reset authority.
#[must_use]
pub fn result_is_valid(state: RawScreenSuspensionState, event: RawScreenSuspensionEvent,
    result: RawScreenSuspensionResult) -> u32
{
    let expected = transition(state, event);
    u32::from(expected.status == 1 && expected == result)
}
