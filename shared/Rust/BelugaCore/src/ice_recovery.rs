//! Complete deterministic ICE recovery continuation policy. No socket, task or timer ownership.
pub const ABI: u32 = 1;
pub const OK: u32 = 0;
pub const BAD_ABI: u32 = 1;
pub const BAD_STATE: u32 = 2;
pub const BAD_EVENT: u32 = 3;
pub const BAD_CONFIG: u32 = 4;

// Public phases preserve the original seven-state domain.
pub const IDLE: u32 = 0;
pub const GRACE: u32 = 1;
pub const ATTEMPTING: u32 = 2;
pub const AWAITING: u32 = 3;
pub const RETRY: u32 = 4;
pub const EXHAUSTED: u32 = 5;
pub const CANCELLED: u32 = 6;
// Continuation cursor reifies the original program counter, not an eighth phase.
pub const NONE: u32 = 0;
pub const ENTERED: u32 = 1;
pub const BEGIN: u32 = 2;
pub const RESTART_PENDING: u32 = 3;
pub const WAIT_ADMISSION: u32 = 4;
pub const WAIT_PENDING: u32 = 5;
pub const ADVANCE: u32 = 6;
pub const EXHAUST_ADMISSION: u32 = 7;
pub const EXHAUST_PENDING: u32 = 8;

pub const ICE_NEW: u32 = 0;
pub const ICE_CHECKING: u32 = 1;
pub const ICE_CONNECTED: u32 = 2;
pub const ICE_COMPLETED: u32 = 3;
pub const ICE_DISCONNECTED: u32 = 4;
pub const ICE_FAILED: u32 = 5;
pub const ICE_CLOSED: u32 = 6;
pub const ICE_UNKNOWN: u32 = 7;
pub const REQUEST: u32 = 8;
pub const CANCEL: u32 = 9;
pub const WORKFLOW_ENTERED: u32 = 10;
pub const BEGIN_ATTEMPT: u32 = 11;
pub const RESTART_RETURNED: u32 = 12;
pub const ADMIT_WAIT: u32 = 13;
pub const WAIT_RETURNED: u32 = 14;
pub const ATTEMPT_BOUNDARY: u32 = 15;
pub const ADMIT_EXHAUST: u32 = 16;
pub const FINISH: u32 = 17;

pub const NO_EFFECT: u32 = 0;
pub const LAUNCH: u32 = 1;
pub const NEXT_ATTEMPT: u32 = 2;
pub const RESTART: u32 = 3;
pub const PREFLIGHT_GRACE: u32 = 4;
pub const PREFLIGHT_TIMEOUT: u32 = 5;
pub const PREFLIGHT_RETRY: u32 = 6;
pub const SLEEP_GRACE: u32 = 7;
pub const SLEEP_TIMEOUT: u32 = 8;
pub const SLEEP_RETRY: u32 = 9;
pub const NEXT_BOUNDARY: u32 = 10;
pub const PREFLIGHT_EXHAUST: u32 = 11;
pub const DELIVER_EXHAUSTION: u32 = 12;
pub const STOP: u32 = 13;
pub const RELEASE_TASK: u32 = 14;
pub const CANCEL_TASK: u32 = 1;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Config {
    pub maximum_attempts: i64,
    pub grace_positive: u32,
    pub reserved: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct State {
    pub abi_version: u32,
    pub phase: u32,
    pub epoch: u64,
    pub attempts: i64,
    pub maximum_attempts: i64,
    pub exhaustion_delivered: u32,
    pub grace_positive: u32,
    pub cursor: u32,
    pub reserved: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Event {
    pub abi_version: u32,
    pub opcode: u32,
    pub workflow_epoch: u64,
    pub task_cancelled: u32,
    pub succeeded: u32,
    pub wait_kind: u32,
    pub reserved: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct InitResult {
    pub status: u32,
    pub reserved: u32,
    pub copied_config: Config,
    pub candidate_state: State,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Result {
    pub abi_version: u32,
    pub status: u32,
    pub copied_before: State,
    pub copied_event: Event,
    pub candidate_state: State,
    pub effect: u32,
    pub flags: u32,
    pub reserved: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Phase { Idle, Grace, Attempting, Awaiting, Retry, Exhausted, Cancelled }
impl Phase {
    fn decode(raw: u32) -> Option<Self> {
        match raw { IDLE => Some(Self::Idle), GRACE => Some(Self::Grace), ATTEMPTING => Some(Self::Attempting),
            AWAITING => Some(Self::Awaiting), RETRY => Some(Self::Retry), EXHAUSTED => Some(Self::Exhausted),
            CANCELLED => Some(Self::Cancelled), _ => None }
    }
    fn raw(self) -> u32 {
        match self { Self::Idle => IDLE, Self::Grace => GRACE, Self::Attempting => ATTEMPTING,
            Self::Awaiting => AWAITING, Self::Retry => RETRY, Self::Exhausted => EXHAUSTED, Self::Cancelled => CANCELLED }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Cursor { None, Entered, Begin, RestartPending, WaitAdmission, WaitPending, Advance, ExhaustAdmission, ExhaustPending }
impl Cursor {
    fn decode(raw: u32) -> Option<Self> {
        match raw { NONE => Some(Self::None), ENTERED => Some(Self::Entered), BEGIN => Some(Self::Begin),
            RESTART_PENDING => Some(Self::RestartPending), WAIT_ADMISSION => Some(Self::WaitAdmission),
            WAIT_PENDING => Some(Self::WaitPending), ADVANCE => Some(Self::Advance),
            EXHAUST_ADMISSION => Some(Self::ExhaustAdmission), EXHAUST_PENDING => Some(Self::ExhaustPending), _ => None }
    }
    fn raw(self) -> u32 {
        match self { Self::None => NONE, Self::Entered => ENTERED, Self::Begin => BEGIN,
            Self::RestartPending => RESTART_PENDING, Self::WaitAdmission => WAIT_ADMISSION,
            Self::WaitPending => WAIT_PENDING, Self::Advance => ADVANCE,
            Self::ExhaustAdmission => EXHAUST_ADMISSION, Self::ExhaustPending => EXHAUST_PENDING }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Opcode { IceNew, IceChecking, Connected, Completed, Disconnected, Failed, Closed, Unknown, Request, Cancel,
              Entered, Begin, RestartReturned, AdmitWait, WaitReturned, Boundary, AdmitExhaust, Finish }
impl Opcode {
    fn decode(raw: u32) -> Option<Self> {
        match raw { ICE_NEW => Some(Self::IceNew), ICE_CHECKING => Some(Self::IceChecking),
            ICE_CONNECTED => Some(Self::Connected), ICE_COMPLETED => Some(Self::Completed),
            ICE_DISCONNECTED => Some(Self::Disconnected), ICE_FAILED => Some(Self::Failed),
            ICE_CLOSED => Some(Self::Closed), ICE_UNKNOWN => Some(Self::Unknown), REQUEST => Some(Self::Request),
            CANCEL => Some(Self::Cancel), WORKFLOW_ENTERED => Some(Self::Entered), BEGIN_ATTEMPT => Some(Self::Begin),
            RESTART_RETURNED => Some(Self::RestartReturned), ADMIT_WAIT => Some(Self::AdmitWait),
            WAIT_RETURNED => Some(Self::WaitReturned), ATTEMPT_BOUNDARY => Some(Self::Boundary),
            ADMIT_EXHAUST => Some(Self::AdmitExhaust), FINISH => Some(Self::Finish), _ => None }
    }
    fn external(self) -> bool {
        match self {
            Self::IceNew | Self::IceChecking | Self::Connected | Self::Completed | Self::Disconnected
                | Self::Failed | Self::Closed | Self::Unknown | Self::Request | Self::Cancel => true,
            Self::Entered | Self::Begin | Self::RestartReturned | Self::AdmitWait | Self::WaitReturned
                | Self::Boundary | Self::AdmitExhaust | Self::Finish => false,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Effect { None, Launch, Begin, Restart, PreflightGrace, PreflightTimeout, PreflightRetry,
              SleepGrace, SleepTimeout, SleepRetry, Boundary, PreflightExhaust, Exhaust, Stop, Release }
impl Effect {
    fn raw(self) -> u32 {
        match self { Self::None => NO_EFFECT, Self::Launch => LAUNCH, Self::Begin => NEXT_ATTEMPT,
            Self::Restart => RESTART, Self::PreflightGrace => PREFLIGHT_GRACE,
            Self::PreflightTimeout => PREFLIGHT_TIMEOUT, Self::PreflightRetry => PREFLIGHT_RETRY,
            Self::SleepGrace => SLEEP_GRACE, Self::SleepTimeout => SLEEP_TIMEOUT, Self::SleepRetry => SLEEP_RETRY,
            Self::Boundary => NEXT_BOUNDARY, Self::PreflightExhaust => PREFLIGHT_EXHAUST,
            Self::Exhaust => DELIVER_EXHAUSTION, Self::Stop => STOP, Self::Release => RELEASE_TASK }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Model {
    phase: Phase, cursor: Cursor, epoch: u64, attempts: i64, maximum: i64,
    delivered: bool, grace: bool,
}
impl Model {
    fn decode(s: State) -> Option<Self> {
        if s.abi_version != ABI || s.maximum_attempts <= 0 || s.attempts < 0
            || s.attempts > s.maximum_attempts || s.exhaustion_delivered > 1
            || s.grace_positive > 1 || s.reserved != 0 { return None; }
        let m = Self { phase: Phase::decode(s.phase)?, cursor: Cursor::decode(s.cursor)?,
            epoch: s.epoch, attempts: s.attempts, maximum: s.maximum_attempts,
            delivered: s.exhaustion_delivered == 1, grace: s.grace_positive == 1 };
        let closed = match m.phase {
            Phase::Idle => m.attempts == 0 && !m.delivered && m.cursor == Cursor::None,
            Phase::Grace => m.attempts == 0 && !m.delivered && m.grace
                && [Cursor::Entered, Cursor::WaitAdmission, Cursor::WaitPending, Cursor::Begin].contains(&m.cursor),
            Phase::Attempting => !m.delivered && ((m.attempts == 0
                && [Cursor::Entered, Cursor::Begin].contains(&m.cursor)) || (m.attempts > 0
                && ([Cursor::RestartPending, Cursor::Advance].contains(&m.cursor)
                    || (m.cursor == Cursor::ExhaustAdmission && m.attempts == m.maximum)))),
            Phase::Awaiting => m.attempts > 0 && !m.delivered
                && ([Cursor::WaitAdmission, Cursor::WaitPending, Cursor::Advance].contains(&m.cursor)
                    || (m.cursor == Cursor::ExhaustAdmission && m.attempts == m.maximum)),
            Phase::Retry => m.attempts > 0 && m.attempts < m.maximum && !m.delivered
                && [Cursor::WaitAdmission, Cursor::WaitPending, Cursor::Begin].contains(&m.cursor),
            Phase::Exhausted => m.attempts == m.maximum && m.delivered
                && [Cursor::ExhaustPending, Cursor::None].contains(&m.cursor),
            Phase::Cancelled => m.attempts == 0 && m.cursor == Cursor::None,
        };
        if closed { Some(m) } else { None }
    }
    fn raw(self) -> State {
        State { abi_version: ABI, phase: self.phase.raw(), epoch: self.epoch, attempts: self.attempts,
            maximum_attempts: self.maximum, exhaustion_delivered: u32::from(self.delivered),
            grace_positive: u32::from(self.grace), cursor: self.cursor.raw(), reserved: 0 }
    }
    fn current(self, e: Event) -> bool {
        e.workflow_epoch == self.epoch && e.task_cancelled == 0 && self.phase != Phase::Cancelled
    }
    fn start(&mut self, grace: bool) {
        self.epoch = self.epoch.wrapping_add(1); self.attempts = 0; self.delivered = false;
        self.phase = if grace { Phase::Grace } else { Phase::Attempting }; self.cursor = Cursor::Entered;
    }
    fn wait_kind(self) -> u32 {
        match self.phase { Phase::Grace => 1, Phase::Awaiting => 2, Phase::Retry => 3,
            Phase::Idle | Phase::Attempting | Phase::Exhausted | Phase::Cancelled => 0 }
    }
}
pub fn valid_state(s: State) -> bool { Model::decode(s).is_some() }
fn decode_event(e: Event) -> Option<Opcode> {
    let opcode = Opcode::decode(e.opcode)?;
    if e.abi_version != ABI || e.task_cancelled > 1 || e.succeeded > 1 || e.reserved != 0 { return None; }
    if opcode.external() {
        return if e.workflow_epoch == 0 && e.task_cancelled == 0 && e.succeeded == 0 && e.wait_kind == 0
            { Some(opcode) } else { None };
    }
    if ![Opcode::RestartReturned, Opcode::WaitReturned].contains(&opcode) && e.succeeded != 0 { return None; }
    if [Opcode::AdmitWait, Opcode::WaitReturned].contains(&opcode) {
        if !(1..=3).contains(&e.wait_kind) { return None; }
    } else if e.wait_kind != 0 { return None; }
    Some(opcode)
}
pub fn initialize(abi: u32, config: Config) -> InitResult {
    let mut out = InitResult { status: OK, reserved: 0, copied_config: config, candidate_state: State::default() };
    if abi != ABI { out.status = BAD_ABI; return out; }
    if config.maximum_attempts <= 0 || config.grace_positive > 1 || config.reserved != 0 {
        out.status = BAD_CONFIG; return out;
    }
    out.candidate_state = Model { phase: Phase::Idle, cursor: Cursor::None, epoch: 0,
        attempts: 0, maximum: config.maximum_attempts, delivered: false, grace: config.grace_positive == 1 }.raw();
    out
}
fn accepted(mut out: Result, model: Model, effect: Effect, cancel: bool) -> Result {
    out.candidate_state = model.raw(); out.effect = effect.raw(); out.flags = u32::from(cancel); out
}
pub fn step(abi: u32, before: State, event: Event) -> Result {
    let mut out = Result { abi_version: ABI, status: OK, copied_before: before, copied_event: event,
        candidate_state: before, effect: NO_EFFECT, flags: 0, reserved: 0 };
    if abi != ABI { out.status = BAD_ABI; return out; }
    let Some(mut s) = Model::decode(before) else { out.status = BAD_STATE; return out; };
    let Some(opcode) = decode_event(event) else { out.status = BAD_EVENT; return out; };
    if opcode.external() {
        if s.phase == Phase::Cancelled && opcode != Opcode::Cancel { return out; }
        match opcode {
            Opcode::Connected | Opcode::Completed => {
                s.epoch = s.epoch.wrapping_add(1); s.attempts = 0; s.delivered = false;
                s.phase = Phase::Idle; s.cursor = Cursor::None;
                return accepted(out, s, Effect::None, true);
            }
            Opcode::Disconnected if s.phase == Phase::Idle => {
                let grace = s.grace; s.start(grace); return accepted(out, s, Effect::Launch, true);
            }
            Opcode::Failed | Opcode::Request if [Phase::Idle, Phase::Grace].contains(&s.phase) => {
                s.start(false); return accepted(out, s, Effect::Launch, true);
            }
            Opcode::Closed | Opcode::Cancel => {
                s.epoch = s.epoch.wrapping_add(1); s.attempts = 0;
                s.phase = Phase::Cancelled; s.cursor = Cursor::None;
                return accepted(out, s, Effect::None, true);
            }
            Opcode::IceNew | Opcode::IceChecking | Opcode::Unknown | Opcode::Disconnected
                | Opcode::Failed | Opcode::Request => return out,
            Opcode::Entered | Opcode::Begin | Opcode::RestartReturned | Opcode::AdmitWait
                | Opcode::WaitReturned | Opcode::Boundary | Opcode::AdmitExhaust | Opcode::Finish => {
                    out.status = BAD_EVENT; return out;
                }
        }
    }
    // Deferred finish is epoch-only, intentionally independent of cancellation/phase.
    if opcode == Opcode::Finish {
        if event.workflow_epoch == s.epoch {
            s.cursor = Cursor::None;
            if ![Phase::Exhausted, Phase::Cancelled].contains(&s.phase) {
                s.attempts = 0; s.phase = Phase::Idle;
            }
            return accepted(out, s, Effect::Release, false);
        }
        return out;
    }
    if !s.current(event) { return accepted(out, s, Effect::Stop, false); }
    let expected = match opcode {
        Opcode::Entered => Cursor::Entered, Opcode::Begin => Cursor::Begin,
        Opcode::RestartReturned => Cursor::RestartPending, Opcode::AdmitWait => Cursor::WaitAdmission,
        Opcode::WaitReturned => Cursor::WaitPending, Opcode::Boundary => Cursor::Advance,
        Opcode::AdmitExhaust => Cursor::ExhaustAdmission,
        Opcode::IceNew | Opcode::IceChecking | Opcode::Connected | Opcode::Completed | Opcode::Disconnected
            | Opcode::Failed | Opcode::Closed | Opcode::Unknown | Opcode::Request | Opcode::Cancel
            | Opcode::Finish => { out.status = BAD_EVENT; return out; }
    };
    if s.cursor != expected || ([Opcode::AdmitWait, Opcode::WaitReturned].contains(&opcode)
        && s.wait_kind() != event.wait_kind) { out.status = BAD_EVENT; return out; }
    let effect = match opcode {
        Opcode::Entered => {
            if s.phase == Phase::Grace { s.cursor = Cursor::WaitAdmission; Effect::PreflightGrace }
            else { s.cursor = Cursor::Begin; Effect::Begin }
        }
        Opcode::Begin => {
            if s.attempts == s.maximum { out.status = BAD_EVENT; return out; }
            s.attempts += 1; s.phase = Phase::Attempting; s.cursor = Cursor::RestartPending; Effect::Restart
        }
        Opcode::RestartReturned => {
            if event.succeeded == 1 { s.phase = Phase::Awaiting; s.cursor = Cursor::WaitAdmission; Effect::PreflightTimeout }
            else { s.cursor = Cursor::Advance; Effect::Boundary }
        }
        Opcode::AdmitWait => {
            s.cursor = Cursor::WaitPending;
            match s.phase { Phase::Grace => Effect::SleepGrace, Phase::Awaiting => Effect::SleepTimeout,
                Phase::Retry => Effect::SleepRetry,
                Phase::Idle | Phase::Attempting | Phase::Exhausted | Phase::Cancelled => {
                    out.status = BAD_EVENT; return out;
                }
            }
        }
        Opcode::WaitReturned => {
            if event.succeeded == 0 { Effect::Stop }
            else if s.phase == Phase::Awaiting { s.cursor = Cursor::Advance; Effect::Boundary }
            else { s.cursor = Cursor::Begin; Effect::Begin }
        }
        Opcode::Boundary => {
            if s.attempts == s.maximum { s.cursor = Cursor::ExhaustAdmission; Effect::PreflightExhaust }
            else { s.phase = Phase::Retry; s.cursor = Cursor::WaitAdmission; Effect::PreflightRetry }
        }
        Opcode::AdmitExhaust => {
            if s.delivered { Effect::Stop }
            else { s.delivered = true; s.phase = Phase::Exhausted; s.cursor = Cursor::ExhaustPending; Effect::Exhaust }
        }
        Opcode::IceNew | Opcode::IceChecking | Opcode::Connected | Opcode::Completed | Opcode::Disconnected
            | Opcode::Failed | Opcode::Closed | Opcode::Unknown | Opcode::Request | Opcode::Cancel
            | Opcode::Finish => { out.status = BAD_EVENT; return out; }
    };
    accepted(out, s, effect, false)
}
