//! Copied pairing-commit phase plans; native code retains all opaque proof and effects.
//!
//! A ready plan is symbolic until required native authentication and construction
//! succeed. It is neither a durable write nor permission to transmit a message.
#![forbid(unsafe_code)]

pub const ABI_VERSION: u32 = 1;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawState {
    pub abi_version: u32,
    pub reserved: u32,
    pub local_role: u32,
    pub pairing_state: u32,
    pub recovery_phase: u32,
    pub reserved_tail: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawEvent {
    pub opcode: u32,
    pub reserved: u32,
    pub commit_id_matches: u32,
    pub reserved_tail: u32,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Decision {
    Ready = 0,
    PreAuthRejected = 1,
    PostAuthRejected = 2,
    InvalidStoredShape = 3,
    InvalidInput = 4,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Action {
    None = 0,
    AwaitProposal = 1,
    IssueProposal = 2,
    ExactCachedCommit = 3,
    IssueCompletion = 4,
    MintProposal = 5,
    MintAcknowledgement = 6,
    MintCompletion = 7,
    MintActivation = 8,
    VerifyStoredRecovery = 9,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthPhase {
    None = 0,
    Proposal = 1,
    Acknowledgement = 2,
    Completion = 3,
    Activation = 4,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub candidate_state: RawState,
    pub decision: u32,
    pub action: u32,
    pub auth_phase: u32,
    pub reserved: u32,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Role { Host = 0, Viewer = 1 }

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum State { Pending = 0, AcceptedIssued = 1, AcceptedReceived = 2, Active = 3 }

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CachedCommitPhase {
    Absent = 0, Proposal = 1, Acknowledgement = 2, Completion = 3, Activation = 4,
}

#[derive(Clone, Copy)]
enum CommitIDMatch { Different, Exact }

#[derive(Clone, Copy)]
enum Operation {
    RecoveryAction,
    PrepareProposal,
    PrepareAcknowledgement,
    AcceptAcknowledgement,
    PrepareCompletion,
    MarkCompletionSent(CommitIDMatch),
    AcceptCompletion,
    AcceptActivationAcknowledgement,
    ValidateStoredShape,
}

impl Operation {
    fn decode(raw: RawEvent) -> Option<Self> {
        if raw.reserved != 0 || raw.reserved_tail != 0 { return None; }
        let exact = match raw.commit_id_matches {
            0 => CommitIDMatch::Different,
            1 => CommitIDMatch::Exact,
            _ => return None,
        };
        if raw.opcode != 5 && raw.commit_id_matches != 0 { return None; }
        match raw.opcode {
            0 => Some(Self::RecoveryAction),
            1 => Some(Self::PrepareProposal),
            2 => Some(Self::PrepareAcknowledgement),
            3 => Some(Self::AcceptAcknowledgement),
            4 => Some(Self::PrepareCompletion),
            5 => Some(Self::MarkCompletionSent(exact)),
            6 => Some(Self::AcceptCompletion),
            7 => Some(Self::AcceptActivationAcknowledgement),
            8 => Some(Self::ValidateStoredShape),
            _ => None,
        }
    }
}

#[derive(Clone, Copy)]
struct Projection { role: Role, state: State, cached: CachedCommitPhase }

#[derive(Clone, Copy)]
struct Plan { candidate: Projection, decision: Decision, action: Action, auth: AuthPhase }

impl Projection {
    fn decode(raw: RawState) -> Option<Self> {
        if raw.abi_version != ABI_VERSION || raw.reserved != 0 || raw.reserved_tail != 0 {
            return None;
        }
        let role = match raw.local_role { 0 => Role::Host, 1 => Role::Viewer, _ => return None };
        let state = match raw.pairing_state {
            0 => State::Pending, 1 => State::AcceptedIssued,
            2 => State::AcceptedReceived, 3 => State::Active, _ => return None,
        };
        let cached = match raw.recovery_phase {
            0 => CachedCommitPhase::Absent, 1 => CachedCommitPhase::Proposal,
            2 => CachedCommitPhase::Acknowledgement, 3 => CachedCommitPhase::Completion,
            4 => CachedCommitPhase::Activation, _ => return None,
        };
        Some(Self { role, state, cached })
    }

    fn raw(self) -> RawState {
        RawState { abi_version: ABI_VERSION, reserved: 0, local_role: self.role as u32,
            pairing_state: self.state as u32, recovery_phase: self.cached as u32, reserved_tail: 0 }
    }

    fn ready(self, action: Action, auth: AuthPhase) -> Plan {
        Plan { candidate: self, decision: Decision::Ready, action, auth }
    }

    fn reject(self) -> Plan {
        Plan { candidate: self, decision: Decision::PreAuthRejected,
            action: Action::None, auth: AuthPhase::None }
    }

    fn evaluate(self, operation: Operation) -> Plan {
        use CachedCommitPhase::{Absent, Acknowledgement, Activation, Completion, Proposal};
        use State::{AcceptedIssued, AcceptedReceived, Active, Pending};
        match operation {
            Operation::RecoveryAction => {
                if self.cached != Absent {
                    return self.ready(Action::ExactCachedCommit, AuthPhase::None);
                }
                let action = match self.state {
                    Pending => match self.role { Role::Host => Action::IssueProposal, Role::Viewer => Action::AwaitProposal },
                    AcceptedIssued => Action::AwaitProposal,
                    AcceptedReceived => Action::IssueCompletion,
                    Active => Action::None,
                };
                self.ready(action, AuthPhase::None)
            }
            Operation::PrepareProposal => {
                if self.role != Role::Host || self.state != Pending { return self.reject(); }
                match self.cached {
                    Absent => Self { cached: Proposal, ..self }.ready(Action::MintProposal, AuthPhase::None),
                    Proposal => self.ready(Action::ExactCachedCommit, AuthPhase::None),
                    Acknowledgement | Completion | Activation => self.reject(),
                }
            }
            Operation::PrepareAcknowledgement => {
                if self.role != Role::Viewer || !matches!(self.state, Pending | AcceptedIssued) { return self.reject(); }
                if self.state == AcceptedIssued && self.cached != Absent {
                    return self.ready(Action::ExactCachedCommit, AuthPhase::Proposal);
                }
                Self { state: AcceptedIssued, cached: Acknowledgement, ..self }
                    .ready(Action::MintAcknowledgement, AuthPhase::Proposal)
            }
            Operation::AcceptAcknowledgement => {
                if self.role != Role::Host || !matches!(self.state, Pending | AcceptedReceived | Active) { return self.reject(); }
                if self.state != Pending {
                    return self.ready(Action::None, AuthPhase::Acknowledgement);
                }
                Self { state: AcceptedReceived, cached: Absent, ..self }
                    .ready(Action::None, AuthPhase::Acknowledgement)
            }
            Operation::PrepareCompletion => {
                if self.role != Role::Host || !matches!(self.state, AcceptedReceived | Active) { return self.reject(); }
                if self.state == Active {
                    if self.cached != Absent { return self.reject(); }
                    return self.ready(Action::MintCompletion, AuthPhase::None);
                }
                match self.cached {
                    Absent => Self { cached: Completion, ..self }.ready(Action::MintCompletion, AuthPhase::None),
                    Completion => self.ready(Action::ExactCachedCommit, AuthPhase::None),
                    Proposal | Acknowledgement | Activation => self.reject(),
                }
            }
            Operation::MarkCompletionSent(exact) => {
                if self.role != Role::Host || !matches!(exact, CommitIDMatch::Exact) { return self.reject(); }
                match (self.state, self.cached) {
                    (AcceptedReceived, Completion) | (Active, Absent) => self.ready(Action::None, AuthPhase::None),
                    (Pending | AcceptedIssued, _) | (AcceptedReceived | Active, _) => self.reject(),
                }
            }
            Operation::AcceptCompletion => {
                if self.role != Role::Viewer { return self.reject(); }
                if self.state == Active {
                    if self.cached == Activation {
                        return self.ready(Action::ExactCachedCommit, AuthPhase::Completion);
                    }
                    return Plan { candidate: self, decision: Decision::PostAuthRejected,
                        action: Action::None, auth: AuthPhase::Completion };
                }
                if self.state != AcceptedIssued { return self.reject(); }
                Self { state: Active, cached: Activation, ..self }
                    .ready(Action::MintActivation, AuthPhase::Completion)
            }
            Operation::AcceptActivationAcknowledgement => {
                if self.role != Role::Host || !matches!(self.state, AcceptedReceived | Active) { return self.reject(); }
                Self { state: Active, cached: Absent, ..self }.ready(Action::None, AuthPhase::Activation)
            }
            Operation::ValidateStoredShape => {
                let valid = match (self.role, self.state, self.cached) {
                    (Role::Host, Pending, Absent | Proposal)
                    | (Role::Host, AcceptedReceived, Absent | Completion)
                    | (Role::Host, Active, Absent)
                    | (Role::Viewer, Pending, Absent)
                    | (Role::Viewer, AcceptedIssued, Acknowledgement)
                    | (Role::Viewer, Active, Activation) => true,
                    _ => false,
                };
                if !valid {
                    return Plan { candidate: self, decision: Decision::InvalidStoredShape,
                        action: Action::None, auth: AuthPhase::None };
                }
                let action = if self.cached == Absent { Action::None } else { Action::VerifyStoredRecovery };
                self.ready(action, AuthPhase::None)
            }
        }
    }
}

#[must_use]
pub fn step(abi_version: u32, before: RawState, event: RawEvent) -> RawResult {
    let refused = || RawResult { candidate_state: before, decision: Decision::InvalidInput as u32,
        action: Action::None as u32, auth_phase: AuthPhase::None as u32, reserved: 0 };
    if abi_version != ABI_VERSION { return refused(); }
    let Some(projection) = Projection::decode(before) else { return refused(); };
    let Some(operation) = Operation::decode(event) else { return refused(); };
    let plan = projection.evaluate(operation);
    RawResult { candidate_state: plan.candidate.raw(), decision: plan.decision as u32,
        action: plan.action as u32, auth_phase: plan.auth as u32, reserved: 0 }
}
