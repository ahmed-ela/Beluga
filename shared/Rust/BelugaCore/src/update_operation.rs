//! Copied updater-operation policy only. Native code owns exact Foundation values,
//! canonical record encoding, durable writes, signing, IPC, locks and SDK effects.
//!
//! Readiness uses a preflight before native encoding and a separate bounded-encoding
//! commit. A candidate projection is not proof of installation or fence clearance.
#![forbid(unsafe_code)]

pub const ABI_VERSION: u32 = 1;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawState {
    pub abi_version: u32,
    pub reserved: u32,
    pub stage: u32,
    pub broker_present: u32,
    pub candidate_present: u32,
    pub recorded_readiness_present: u32,
    pub installed_fresh: u32,
    pub readiness_fresh: u32,
    pub challenge_present: u32,
    pub reserved_tail: u32,
}

/// Every fact is exactly 0/1. Per-opcode unused facts must be exactly zero.
/// See the integration plan for the independent native equality/validity inputs.
#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawEvent {
    pub opcode: u32,
    pub reserved: u32,
    pub fact0: u32,
    pub fact1: u32,
    pub fact2: u32,
    pub fact3: u32,
    pub fact4: u32,
    pub fact5: u32,
    pub fact6: u32,
    pub reserved_tail: u32,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Decision { Accepted = 0, Denied = 1, InvalidInput = 2 }

/// Native symbolic assignments, never filesystem/IPC/SDK authorization.
#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Action {
    None = 0,
    PublishBroker = 1,
    PublishCandidate = 2,
    MarkPossiblyArmed = 3,
    AcceptInstalledCompletion = 4,
    PublishChallenge = 5,
    PrepareReadinessEncoding = 6,
    AcceptReadiness = 7,
    InvalidateFreshness = 8,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub candidate_state: RawState,
    pub decision: u32,
    pub action: u32,
    pub predicate: u32,
    pub reserved: u32,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Stage { Prepared = 0, PossiblyArmed = 1, InstalledVerified = 2, ReadyToRelease = 3 }
#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Presence { Absent = 0, Present = 1 }
#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Freshness { NotFresh = 0, Fresh = 1 }
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum BindingMatch { Different, Exact }
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum NativeValidity { Invalid, Valid }
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum NativeEquality { Different, Equal }
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum NativeDifference { Same, Different }
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum BuildProgress { NotNewer, Newer }
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum NativeBound { Rejected, WithinBound }

#[derive(Clone, Copy)]
struct NativeReadiness {
    ready: bool,
    operation: NativeEquality,
    target: NativeEquality,
    candidate: NativeEquality,
    menu: NativeEquality,
    nonce: NativeEquality,
}

#[derive(Clone, Copy)]
enum Operation {
    BindBroker { binding: BindingMatch, valid: NativeValidity,
        version: NativeEquality, build: NativeEquality },
    BindCandidate { binding: BindingMatch, valid: NativeValidity,
        build: BuildProgress, executable: NativeDifference },
    MarkPossiblyArmed(BindingMatch),
    AcceptInstalledCompletion { binding: BindingMatch, candidate: NativeEquality },
    IssueChallenge { menu_valid: NativeValidity, nonce_valid: NativeValidity,
        new_menu: NativeDifference, nonce_operation: NativeDifference,
        nonce_predecessor: NativeDifference, nonce_recorded: NativeDifference },
    PrepareReadinessEncoding(NativeReadiness),
    AcceptReadiness { native: NativeReadiness, encoding: NativeBound },
    ObserveIdle,
    ObserveCancelled,
    ObserveUpdaterFailed,
    ObserveBrokerExited,
    QueryInstallerMayRemainArmed,
    QueryPermitsFenceRelease,
    QueryPermitsRuntimeActivation,
}

impl Operation {
    fn decode(raw: RawEvent) -> Option<Self> {
        if raw.reserved != 0 || raw.reserved_tail != 0 { return None; } // UO-M01
        let facts = [raw.fact0, raw.fact1, raw.fact2, raw.fact3, raw.fact4, raw.fact5, raw.fact6];
        if facts.iter().any(|value| *value > 1) { return None; } // UO-M02
        let used = match raw.opcode {
            0 | 1 => 4,
            2 => 1,
            3 => 2,
            4 | 5 => 6,
            6 => 7,
            7..=13 => 0,
            _ => return None, // UO-M03
        };
        if facts[used..].iter().any(|value| *value != 0) { return None; } // UO-M04
        let binding = if raw.fact0 == 1 { BindingMatch::Exact } else { BindingMatch::Different };
        let valid1 = if raw.fact1 == 1 { NativeValidity::Valid } else { NativeValidity::Invalid };
        let equal = |value| if value == 1 { NativeEquality::Equal } else { NativeEquality::Different };
        let different = |value| if value == 1 { NativeDifference::Different } else { NativeDifference::Same };
        let validity = |value| if value == 1 { NativeValidity::Valid } else { NativeValidity::Invalid };
        let readiness = NativeReadiness { ready: raw.fact0 == 1, operation: equal(raw.fact1),
            target: equal(raw.fact2), candidate: equal(raw.fact3), menu: equal(raw.fact4), nonce: equal(raw.fact5) };
        Some(match raw.opcode {
            0 => Self::BindBroker { binding, valid: valid1, version: equal(raw.fact2), build: equal(raw.fact3) },
            1 => Self::BindCandidate { binding, valid: valid1,
                build: if raw.fact2 == 1 { BuildProgress::Newer } else { BuildProgress::NotNewer },
                executable: different(raw.fact3) },
            2 => Self::MarkPossiblyArmed(binding),
            3 => Self::AcceptInstalledCompletion { binding, candidate: equal(raw.fact1) },
            4 => Self::IssueChallenge { menu_valid: validity(raw.fact0), nonce_valid: validity(raw.fact1),
                new_menu: different(raw.fact2), nonce_operation: different(raw.fact3),
                nonce_predecessor: different(raw.fact4), nonce_recorded: different(raw.fact5) },
            5 => Self::PrepareReadinessEncoding(readiness),
            6 => Self::AcceptReadiness { native: readiness,
                encoding: if raw.fact6 == 1 { NativeBound::WithinBound } else { NativeBound::Rejected } },
            7 => Self::ObserveIdle,
            8 => Self::ObserveCancelled,
            9 => Self::ObserveUpdaterFailed,
            10 => Self::ObserveBrokerExited,
            11 => Self::QueryInstallerMayRemainArmed,
            12 => Self::QueryPermitsFenceRelease,
            13 => Self::QueryPermitsRuntimeActivation,
            _ => return None,
        })
    }
}

#[derive(Clone, Copy)]
struct Projection {
    stage: Stage,
    broker: Presence,
    candidate: Presence,
    recorded_readiness: Presence,
    installed: Freshness,
    readiness: Freshness,
    challenge: Presence,
}

impl Projection {
    fn decode(raw: RawState) -> Option<Self> {
        if raw.abi_version != ABI_VERSION || raw.reserved != 0 || raw.reserved_tail != 0 { return None; } // UO-M05
        let stage = match raw.stage {
            0 => Stage::Prepared, 1 => Stage::PossiblyArmed,
            2 => Stage::InstalledVerified, 3 => Stage::ReadyToRelease,
            _ => return None, // UO-M07
        };
        let presence = |value| match value { 0 => Some(Presence::Absent), 1 => Some(Presence::Present), _ => None }; // UO-M08
        let freshness = |value| match value { 0 => Some(Freshness::NotFresh), 1 => Some(Freshness::Fresh), _ => None }; // UO-M09
        // Decode only the copied closed domains, not a new global record invariant.
        // Native canonical-record validation remains exact and independently enforced.
        Some(Self { stage, broker: presence(raw.broker_present)?, candidate: presence(raw.candidate_present)?,
            recorded_readiness: presence(raw.recorded_readiness_present)?, installed: freshness(raw.installed_fresh)?,
            readiness: freshness(raw.readiness_fresh)?, challenge: presence(raw.challenge_present)? })
    }

    fn raw(self) -> RawState {
        RawState { abi_version: ABI_VERSION, reserved: 0, stage: self.stage as u32,
            broker_present: self.broker as u32, candidate_present: self.candidate as u32,
            recorded_readiness_present: self.recorded_readiness as u32, installed_fresh: self.installed as u32,
            readiness_fresh: self.readiness as u32, challenge_present: self.challenge as u32, reserved_tail: 0 }
    }

    fn accepted(self, action: Action, predicate: bool) -> RawResult {
        RawResult { candidate_state: self.raw(), decision: Decision::Accepted as u32,
            action: action as u32, predicate: predicate as u32, reserved: 0 }
    }
    fn denied(self) -> RawResult {
        RawResult { candidate_state: self.raw(), decision: Decision::Denied as u32,
            action: Action::None as u32, predicate: 0, reserved: 0 }
    }

    fn readiness_matches(self, native: NativeReadiness) -> bool {
        self.installed == Freshness::Fresh && self.challenge == Presence::Present && native.ready // UO-R01
            && native.operation == NativeEquality::Equal // UO-R02
            && native.target == NativeEquality::Equal // UO-R03
            && native.candidate == NativeEquality::Equal // UO-R04
            && native.menu == NativeEquality::Equal // UO-R05
            && native.nonce == NativeEquality::Equal // UO-R06
    }

    fn evaluate(mut self, operation: Operation) -> RawResult {
        match operation {
            Operation::BindBroker { binding, valid, version, build } => {
                if binding != BindingMatch::Exact || self.stage != Stage::Prepared || self.broker != Presence::Absent // UO-B01
                    || valid != NativeValidity::Valid || version != NativeEquality::Equal || build != NativeEquality::Equal { return self.denied(); } // UO-B02
                self.broker = Presence::Present;
                self.accepted(Action::PublishBroker, false)
            }
            Operation::BindCandidate { binding, valid, build, executable } => {
                if binding != BindingMatch::Exact || self.candidate != Presence::Absent // UO-C01
                    || !matches!(self.stage, Stage::Prepared | Stage::PossiblyArmed) // UO-C02
                    || valid != NativeValidity::Valid || build != BuildProgress::Newer || executable != NativeDifference::Different { return self.denied(); } // UO-C03
                self.candidate = Presence::Present;
                self.accepted(Action::PublishCandidate, false)
            }
            Operation::MarkPossiblyArmed(binding) => {
                if binding != BindingMatch::Exact || self.stage != Stage::Prepared || self.broker != Presence::Present { return self.denied(); } // UO-A01
                self.stage = Stage::PossiblyArmed;
                self.accepted(Action::MarkPossiblyArmed, false)
            }
            Operation::AcceptInstalledCompletion { binding, candidate } => {
                if binding != BindingMatch::Exact || self.stage == Stage::Prepared || self.broker != Presence::Present // UO-I01
                    || self.installed != Freshness::NotFresh || self.candidate != Presence::Present || candidate != NativeEquality::Equal { return self.denied(); } // UO-I02
                if self.stage == Stage::PossiblyArmed { self.stage = Stage::InstalledVerified; } // UO-I03
                self.installed = Freshness::Fresh;
                self.readiness = Freshness::NotFresh; // UO-I04
                self.challenge = Presence::Absent; // UO-I05
                self.accepted(Action::AcceptInstalledCompletion, false)
            }
            Operation::IssueChallenge { menu_valid, nonce_valid, new_menu,
                nonce_operation, nonce_predecessor, nonce_recorded } => {
                if self.installed != Freshness::Fresh || self.readiness != Freshness::NotFresh
                    || self.challenge != Presence::Absent || self.candidate != Presence::Present { return self.denied(); } // UO-H01
                if menu_valid != NativeValidity::Valid || nonce_valid != NativeValidity::Valid || new_menu != NativeDifference::Different
                    || nonce_operation != NativeDifference::Different || nonce_predecessor != NativeDifference::Different
                    || nonce_recorded != NativeDifference::Different { return self.denied(); } // UO-H02
                self.challenge = Presence::Present;
                self.accepted(Action::PublishChallenge, false)
            }
            Operation::PrepareReadinessEncoding(native) => {
                if !self.readiness_matches(native) { return self.denied(); }
                // No state/freshness publication before the existing native encoder.
                self.accepted(Action::PrepareReadinessEncoding, false)
            }
            Operation::AcceptReadiness { native, encoding } => {
                if !self.readiness_matches(native) || encoding != NativeBound::WithinBound { return self.denied(); } // UO-R07
                self.challenge = Presence::Absent;
                self.recorded_readiness = Presence::Present;
                self.stage = Stage::ReadyToRelease;
                self.readiness = Freshness::Fresh;
                self.accepted(Action::AcceptReadiness, false)
            }
            Operation::ObserveIdle | Operation::ObserveCancelled => self.accepted(Action::None, false),
            Operation::ObserveUpdaterFailed | Operation::ObserveBrokerExited => {
                self.installed = Freshness::NotFresh; // UO-F01
                self.readiness = Freshness::NotFresh; // UO-F02
                self.challenge = Presence::Absent; // UO-F03
                self.accepted(Action::InvalidateFreshness, false)
            }
            Operation::QueryInstallerMayRemainArmed => self.accepted(Action::None, self.stage != Stage::Prepared), // UO-Q01
            Operation::QueryPermitsFenceRelease => {
                let allowed = self.broker == Presence::Present && self.stage == Stage::ReadyToRelease // UO-Q02
                    && self.installed == Freshness::Fresh && self.readiness == Freshness::Fresh; // UO-Q03
                self.accepted(Action::None, allowed)
            }
            Operation::QueryPermitsRuntimeActivation => self.accepted(Action::None, false), // UO-Q04
        }
    }
}

/// Unknown ABI, domain, opcode, reserved or nonzero unused fact returns the exact
/// caller-supplied old state, InvalidInput, no native assignment and predicate false.
#[must_use]
pub fn step(abi_version: u32, before: RawState, event: RawEvent) -> RawResult {
    let invalid = RawResult { candidate_state: before, decision: Decision::InvalidInput as u32,
        action: Action::None as u32, predicate: 0, reserved: 0 };
    if abi_version != ABI_VERSION { return invalid; } // UO-M06
    let Some(state) = Projection::decode(before) else { return invalid; };
    let Some(operation) = Operation::decode(event) else { return invalid; };
    state.evaluate(operation)
}
