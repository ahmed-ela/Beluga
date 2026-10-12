//! Runtime catalog admission; no native custody crosses this ABI.
//! Historical approved contract: 419829a330c03550c1d6948d291699293cca95120adf98da5a9ddfd7f9dc125e.
//! Every call is one ordered native cut, not permission to skip earlier cuts.

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawRuntimeCatalogState {
    pub abi_version: u32,
    pub phase: u32,
    pub operation: u32,
    pub eligible: u32,
    pub intent: u32,
    pub first_grant: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawRuntimeCatalogEvent {
    pub opcode: u32,
    pub operation: u32,
    pub facts: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawRuntimeCatalogResult {
    pub state: RawRuntimeCatalogState,
    pub status: u32,
    pub decision: u32,
    pub effect: u32,
    pub value: u32,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum Phase { Idle, Draining, Drained, Revoked }
#[derive(Clone, Copy, Eq, PartialEq)]
enum Operation { None, Select, Forget, Pair }
#[derive(Clone, Copy)]
enum Stage {
    StartupGuard, StartupInstalled, Preflight, QuietStructural, Owner,
    Authorization, CatalogPresence, CatalogFresh, Begin, RetirementEnter,
    RetirementDrained, RetirementFinish, Revalidate, End, RecoveryStructural,
    RecoveryOwner, RecoveryPresence, RecoveryFresh, ResumeBeforeOwner, ResumeOwner,
    PairIdentity, InstallIntent, ClearIntent, TakeIntent, BootstrapStartBeforeOwner,
    BootstrapStartAfterOwner, CommitBeforeOwner, CommitAfterOwner, CommitStoppedBeforeOwner,
    CommitStoppedAfterOwner, RecordReadback, ActivationAuthority, ActivationIntent,
    BootstrapEndBeforeOwner, BootstrapEndAfterOwner, BootstrapEndStoppedBeforeOwner,
    BootstrapEndStoppedAfterOwner, AvailabilityStartBeforeOwner, AvailabilityStartAfterOwner,
    GenerationBeforeOwner, GenerationAfterOwner, CurrentClientPresence, CurrentClientExact,
    PersistSelected, MediaTargetBeforeOwner, MediaTargetAfterOwner, PreparedBeforeOwner,
    PreparedAfterOwner, Revoke, PairCatchBeforeOwner, PairCatchAfterOwner,
    InvitationChanged, AvailabilityEnded, AvailabilityEndedTerminal, MediaMove,
    PreparedRetire, PreparedLifecyclePrefix, MediaMovePrefix,
}

#[repr(u32)]
#[derive(Clone, Copy)]
enum Decision {
    Admit = 0, Ignore = 1, InvalidLifecycle = 2, UnknownPhone = 3, Capacity = 4,
    NotQuiet = 5, OwnerNotAuthorized = 6, StaleSelection = 7, Cancelled = 8,
    StaleAttempt = 9,
}
#[repr(u32)]
#[derive(Clone, Copy)]
enum Effect {
    None = 0, InstallStartup = 1, Begin = 2, Drained = 3, End = 4,
    InstallIntent = 5, ClearIntent = 6, TakeIntent = 7, Revoke = 8,
}

fn operation(raw: u32) -> Option<Operation> {
    match raw {
        0 => Some(Operation::None), 1 => Some(Operation::Select),
        2 => Some(Operation::Forget), 3 => Some(Operation::Pair), _ => None,
    }
}

fn state_phase(s: RawRuntimeCatalogState) -> Option<Phase> {
    if s.abi_version != 1 || s.eligible > 1 || s.intent > 1 || s.first_grant > 1 {
        return None;
    }
    let op = operation(s.operation)?;
    let phase = match s.phase {
        0 if op == Operation::None => Phase::Idle,
        1 if op != Operation::None && s.intent == 0 => Phase::Draining,
        2 if op != Operation::None => Phase::Drained,
        3 if op == Operation::None && s.eligible == 0 && s.intent == 0 && s.first_grant == 0 => Phase::Revoked,
        _ => return None,
    };
    if s.eligible == 1 && (phase != Phase::Idle || s.intent != 0) { return None; }
    if s.first_grant == 1 && !((phase == Phase::Draining || phase == Phase::Drained)
        && op == Operation::Pair && s.intent == 0) { return None; }
    Some(phase)
}

fn stage(raw: u32) -> Option<Stage> {
    Some(match raw {
        0 => Stage::StartupGuard, 1 => Stage::StartupInstalled, 2 => Stage::Preflight,
        3 => Stage::QuietStructural, 4 => Stage::Owner, 5 => Stage::Authorization,
        6 => Stage::CatalogPresence, 7 => Stage::CatalogFresh, 8 => Stage::Begin,
        9 => Stage::RetirementEnter, 10 => Stage::RetirementDrained,
        11 => Stage::RetirementFinish, 12 => Stage::Revalidate, 13 => Stage::End,
        14 => Stage::RecoveryStructural, 15 => Stage::RecoveryOwner,
        16 => Stage::RecoveryPresence, 17 => Stage::RecoveryFresh,
        18 => Stage::ResumeBeforeOwner, 19 => Stage::ResumeOwner, 20 => Stage::PairIdentity,
        21 => Stage::InstallIntent, 22 => Stage::ClearIntent, 23 => Stage::TakeIntent,
        24 => Stage::BootstrapStartBeforeOwner, 25 => Stage::BootstrapStartAfterOwner,
        26 => Stage::CommitBeforeOwner, 27 => Stage::CommitAfterOwner,
        28 => Stage::CommitStoppedBeforeOwner, 29 => Stage::CommitStoppedAfterOwner,
        30 => Stage::RecordReadback, 31 => Stage::ActivationAuthority,
        32 => Stage::ActivationIntent, 33 => Stage::BootstrapEndBeforeOwner,
        34 => Stage::BootstrapEndAfterOwner, 35 => Stage::BootstrapEndStoppedBeforeOwner,
        36 => Stage::BootstrapEndStoppedAfterOwner, 37 => Stage::AvailabilityStartBeforeOwner,
        38 => Stage::AvailabilityStartAfterOwner, 39 => Stage::GenerationBeforeOwner,
        40 => Stage::GenerationAfterOwner, 41 => Stage::CurrentClientPresence,
        42 => Stage::CurrentClientExact, 43 => Stage::PersistSelected,
        44 => Stage::MediaTargetBeforeOwner, 45 => Stage::MediaTargetAfterOwner,
        46 => Stage::PreparedBeforeOwner, 47 => Stage::PreparedAfterOwner,
        48 => Stage::Revoke, 49 => Stage::PairCatchBeforeOwner,
        50 => Stage::PairCatchAfterOwner, 51 => Stage::InvitationChanged,
        52 => Stage::AvailabilityEnded, 53 => Stage::AvailabilityEndedTerminal,
        54 => Stage::MediaMove, 55 => Stage::PreparedRetire,
        56 => Stage::PreparedLifecyclePrefix, 57 => Stage::MediaMovePrefix,
        _ => return None,
    })
}

fn mask(stage: Stage, op: Operation) -> u32 {
    match stage {
        Stage::Preflight => match op {
            Operation::Select => 3, Operation::Forget => 2, Operation::Pair => 28,
            Operation::None => 0,
        },
        Stage::StartupInstalled | Stage::PreparedBeforeOwner => 31,
        Stage::QuietStructural | Stage::ActivationIntent => 2047,
        Stage::Revalidate => 127,
        Stage::GenerationAfterOwner | Stage::MediaTargetAfterOwner => 1023,
        Stage::PersistSelected => 63,
        Stage::PreparedAfterOwner => 15,
        Stage::RecoveryStructural | Stage::BootstrapStartBeforeOwner | Stage::CommitAfterOwner
        | Stage::BootstrapEndAfterOwner | Stage::AvailabilityStartAfterOwner
        | Stage::PreparedRetire | Stage::PreparedLifecyclePrefix => 7,
        Stage::StartupGuard | Stage::CatalogPresence | Stage::Begin | Stage::RetirementEnter
        | Stage::RetirementFinish | Stage::End | Stage::RecoveryPresence
        | Stage::BootstrapStartAfterOwner | Stage::CommitStoppedBeforeOwner
        | Stage::CommitStoppedAfterOwner | Stage::ActivationAuthority
        | Stage::BootstrapEndStoppedAfterOwner | Stage::AvailabilityStartBeforeOwner
        | Stage::CurrentClientPresence | Stage::MediaTargetBeforeOwner
        | Stage::PairCatchBeforeOwner | Stage::InvitationChanged
        | Stage::AvailabilityEndedTerminal | Stage::MediaMove => 3,
        Stage::ClearIntent | Stage::Revoke => 0,
        _ => 1,
    }
}

fn malformed(state: RawRuntimeCatalogState) -> RawRuntimeCatalogResult {
    RawRuntimeCatalogResult { state, status: 0, decision: 0, effect: 0, value: 0 }
}
fn result(state: RawRuntimeCatalogState, decision: Decision, effect: Effect, value: u32)
    -> RawRuntimeCatalogResult {
    RawRuntimeCatalogResult { state, status: 1, decision: decision as u32, effect: effect as u32, value }
}
fn query(state: RawRuntimeCatalogState, passes: bool, denied: Decision) -> RawRuntimeCatalogResult {
    result(state, if passes { Decision::Admit } else { denied }, Effect::None, 0)
}

/// One copied-policy cut. Native custody, exact identities, async work, and writes remain native.
#[must_use]
pub fn step(state: RawRuntimeCatalogState, event: RawRuntimeCatalogEvent) -> RawRuntimeCatalogResult {
    let Some(phase) = state_phase(state) else { return malformed(state); };
    let Some(stage) = stage(event.opcode) else { return malformed(state); };
    let Some(op) = operation(event.operation) else { return malformed(state); };
    let wants_operation = matches!(stage, Stage::Preflight | Stage::Begin);
    if event.reserved != 0 || (wants_operation && op == Operation::None)
        || (!wants_operation && op != Operation::None) {
        return malformed(state);
    }
    let allowed = mask(stage, op);
    if event.facts & !allowed != 0 { return malformed(state); }
    let all = event.facts == allowed;
    let live = phase != Phase::Revoked;
    match stage {
        Stage::StartupGuard => query(state, live && event.facts == 0, Decision::InvalidLifecycle),
        Stage::StartupInstalled => {
            if phase != Phase::Idle || state.intent != 0 || state.first_grant != 0 { return malformed(state); }
            let next = RawRuntimeCatalogState { eligible: u32::from(all), ..state };
            result(next, Decision::Admit, Effect::InstallStartup, 0)
        }
        Stage::Preflight => {
            let decision = match op {
                Operation::Select if event.facts & 1 != 0 && event.facts & 2 == 0 => Decision::UnknownPhone,
                Operation::Forget if event.facts & 2 == 0 => Decision::UnknownPhone,
                Operation::Pair if event.facts & 4 != 0 => Decision::Cancelled,
                Operation::Pair if event.facts & 24 != 24 => Decision::Capacity,
                _ => Decision::Admit,
            };
            result(state, decision, Effect::None, 0)
        }
        Stage::QuietStructural => query(state, phase == Phase::Idle && all, Decision::NotQuiet),
        Stage::Owner | Stage::Authorization => query(state, live && all, Decision::OwnerNotAuthorized),
        Stage::CatalogPresence => query(state, all, Decision::InvalidLifecycle),
        Stage::CatalogFresh => query(state, all, Decision::StaleSelection),
        Stage::Begin => {
            if phase != Phase::Idle { return query(state, false, Decision::StaleSelection); }
            if state.intent != 0 || state.first_grant != 0 { return malformed(state); }
            if !all { return query(state, false, Decision::StaleSelection); }
            let grant = if op == Operation::Pair { state.eligible } else { 0 };
            let next = RawRuntimeCatalogState { phase: 1, operation: event.operation,
                eligible: 0, first_grant: grant, ..state };
            result(next, Decision::Admit, Effect::Begin, grant)
        }
        Stage::RetirementEnter => query(state,
            (phase == Phase::Draining || phase == Phase::Revoked) && all, Decision::StaleSelection),
        Stage::RetirementDrained => {
            if !all { return query(state, false, Decision::Ignore); }
            match phase {
                Phase::Draining => result(RawRuntimeCatalogState { phase: 2, ..state },
                    Decision::Admit, Effect::Drained, 1),
                Phase::Revoked => result(state, Decision::Admit, Effect::None, 1),
                _ => malformed(state),
            }
        }
        Stage::RetirementFinish => query(state, phase == Phase::Drained && all, Decision::Cancelled),
        Stage::Revalidate => query(state, phase == Phase::Drained && all, Decision::StaleSelection),
        Stage::End => {
            if event.facts & 1 == 0 { return query(state, false, Decision::Ignore); }
            if phase != Phase::Drained { return malformed(state); }
            let next = RawRuntimeCatalogState { phase: 0, operation: 0, first_grant: 0, ..state };
            result(next, Decision::Admit, Effect::End, (event.facts >> 1) & 1)
        }
        Stage::RecoveryStructural => query(state, phase == Phase::Drained && all, Decision::Ignore),
        Stage::PairIdentity => query(state, live && all, Decision::NotQuiet),
        Stage::InstallIntent => {
            if phase != Phase::Drained || state.operation != 3 || state.intent != 0
                || event.facts != state.first_grant { return malformed(state); }
            let next = RawRuntimeCatalogState { intent: state.first_grant, first_grant: 0, ..state };
            result(next, Decision::Admit, Effect::InstallIntent, state.first_grant)
        }
        Stage::ClearIntent => result(RawRuntimeCatalogState { intent: 0, ..state },
            Decision::Admit, Effect::ClearIntent, 0),
        Stage::TakeIntent => {
            if event.facts != state.intent { return malformed(state); }
            result(RawRuntimeCatalogState { intent: 0, ..state }, Decision::Admit,
                Effect::TakeIntent, state.intent)
        }
        Stage::BootstrapStartBeforeOwner => query(state,
            phase == Phase::Drained && state.operation == 3 && all, Decision::Cancelled),
        Stage::BootstrapStartAfterOwner | Stage::PreparedBeforeOwner
        | Stage::PreparedAfterOwner | Stage::PreparedLifecyclePrefix =>
            query(state, live && all, Decision::Cancelled),
        Stage::RecordReadback | Stage::ActivationAuthority | Stage::ActivationIntent =>
            query(state, live && all, Decision::StaleAttempt),
        Stage::PersistSelected | Stage::MediaMove | Stage::MediaMovePrefix =>
            query(state, live && all, Decision::StaleSelection),
        Stage::Revoke => result(RawRuntimeCatalogState { abi_version: 1, phase: 3,
            operation: 0, eligible: 0, intent: 0, first_grant: 0 },
            Decision::Admit, Effect::Revoke, 0),
        Stage::PreparedRetire => query(state, all, Decision::Ignore),
        Stage::RecoveryOwner | Stage::RecoveryPresence | Stage::RecoveryFresh
        | Stage::ResumeBeforeOwner | Stage::ResumeOwner | Stage::CommitBeforeOwner
        | Stage::CommitAfterOwner | Stage::CommitStoppedBeforeOwner | Stage::CommitStoppedAfterOwner
        | Stage::BootstrapEndBeforeOwner | Stage::BootstrapEndAfterOwner
        | Stage::BootstrapEndStoppedBeforeOwner | Stage::BootstrapEndStoppedAfterOwner
        | Stage::AvailabilityStartBeforeOwner | Stage::AvailabilityStartAfterOwner
        | Stage::GenerationBeforeOwner | Stage::GenerationAfterOwner | Stage::CurrentClientPresence
        | Stage::CurrentClientExact | Stage::MediaTargetBeforeOwner | Stage::MediaTargetAfterOwner
        | Stage::PairCatchBeforeOwner | Stage::PairCatchAfterOwner | Stage::InvitationChanged
        | Stage::AvailabilityEnded | Stage::AvailabilityEndedTerminal =>
            query(state, live && all, Decision::Ignore),
    }
}

/// Reject malformed inputs and any altered output, including status, echoed state and unused fields.
#[must_use]
pub fn result_is_valid(state: RawRuntimeCatalogState, event: RawRuntimeCatalogEvent,
    supplied: RawRuntimeCatalogResult) -> u32 {
    if supplied.status != 1 { return 0; }
    let expected = step(state, event);
    u32::from(expected.status == 1 && supplied == expected)
}
