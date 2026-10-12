//! Pure bounded phone playback policy; native identity facts are not Pause authority.
//! Request construction, provider decoding, localization and platform effects stay native.
#![forbid(unsafe_code)]
use core::num::NonZeroU64;

pub const ABI: u32 = crate::ABI_VERSION;
pub const VISIBLE: u32 = 1;
pub const HAS_BEEN_VISIBLE: u32 = 2;
pub const READY: u32 = 4;
pub const EVIDENCE_REVOKED: u32 = 8;
pub const STATE_FLAGS: u32 = 15;
pub const FIRST_PLAYING: u32 = 1;
pub const LATEST_PLAYING: u32 = 2;
pub const LATEST_STATE: u32 = 4;
pub const EVIDENCE: u32 = 8;
pub const REPLY_DEADLINE: u32 = 16;
pub const STATE_PRESENCE: u32 = 31;
pub const OPERATION_EQUAL: u32 = 2;
pub const PAGE_EQUAL: u32 = 4;
pub const VIDEO_EQUAL: u32 = 8;
pub const PROOF_EQUAL: u32 = 16;
pub const COMPLETION_EQUAL: u32 = 32;
pub const EVENT_FLAGS: u32 = 63;
pub const SAMPLE_STATE: u32 = 1;
pub const SAMPLE_POSITION: u32 = 2;
pub const SAMPLE_DURATION: u32 = 4;
pub const SAMPLE_RATE: u32 = 8;
pub const SAMPLE_PRESENCE: u32 = 15;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[repr(C)]
pub struct Request {
    pub position: u64,
    pub duration: u64,
    pub rate: u64,
    pub deadline: u64,
    pub position_observed_at: u64,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[repr(C)]
pub struct Evidence {
    pub token: u64,
    pub position: u64,
    pub rate: u64,
    pub observed_at: u64,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[repr(C)]
pub struct State {
    pub abi: u32,
    pub phase: u32,
    pub failure: u32,
    pub mac_pause: u32,
    pub flags: u32,
    pub presence: u32,
    pub sequence: u32,
    pub reserved: u32,
    pub request: Request,
    pub last_now: u64,
    pub first_position: u64,
    pub first_at: u64,
    pub latest_playing_at: u64,
    pub latest_state: i32,
    pub latest_state_reserved: u32,
    pub evidence: Evidence,
    pub reply_deadline: u64,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[repr(C)]
pub struct Event {
    pub opcode: u32,
    pub flags: u32,
    pub presence: u32,
    pub sequence: u32,
    pub kind: u32,
    pub sample_state: i32,
    pub completion: u32,
    pub failure: u32,
    pub now: u64,
    pub proof_token: u64,
    pub candidate_token: u64,
    pub sample_position: u64,
    pub sample_duration: u64,
    pub sample_rate: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct Result {
    pub state: State,
    /// Valid product step=0 (including no-op/false/failure); malformed=3.
    pub status: u32,
    /// None0, playRequired1, confirmed2, movedToPhone3, failed4.
    pub event: u32,
    pub accepted: u32,
    /// Nonzero only for the emitted failed event, not for isCurrent's silent failure.
    pub failure: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
enum Failure {
    InvalidRequest = 1, TimedOut = 2, NotVisible = 3, Dismissed = 4,
    Replaced = 5, PlayerUnavailable = 6, WrongVideo = 7, InvalidBridge = 8,
    ClockChanged = 9, UnsupportedRate = 10, PositionChanged = 11,
    PlaybackInterrupted = 12, MacPauseNotApplied = 13, MacPauseUnknown = 14,
}
impl Failure {
    fn parse(raw: u32) -> Option<Self> {
        Some(match raw {
            1 => Self::InvalidRequest, 2 => Self::TimedOut, 3 => Self::NotVisible,
            4 => Self::Dismissed, 5 => Self::Replaced, 6 => Self::PlayerUnavailable,
            7 => Self::WrongVideo, 8 => Self::InvalidBridge, 9 => Self::ClockChanged,
            10 => Self::UnsupportedRate, 11 => Self::PositionChanged,
            12 => Self::PlaybackInterrupted, 13 => Self::MacPauseNotApplied,
            14 => Self::MacPauseUnknown, _ => return None,
        })
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase { Preparing, Ready, PlayRequired, Verifying, Confirmed, AwaitingMacPause, LocalPlayback, Failed(Failure) }
impl Phase {
    fn parse(raw: u32, failure: u32) -> Option<Self> {
        if raw != 7 && failure != 0 { return None; }
        Some(match raw {
            0 => Self::Preparing, 1 => Self::Ready, 2 => Self::PlayRequired,
            3 => Self::Verifying, 4 => Self::Confirmed, 5 => Self::AwaitingMacPause,
            6 => Self::LocalPlayback, 7 => Self::Failed(Failure::parse(failure)?),
            _ => return None,
        })
    }
    fn wire(self) -> (u32, u32) {
        match self {
            Self::Preparing => (0, 0), Self::Ready => (1, 0), Self::PlayRequired => (2, 0),
            Self::Verifying => (3, 0), Self::Confirmed => (4, 0),
            Self::AwaitingMacPause => (5, 0), Self::LocalPlayback => (6, 0),
            Self::Failed(failure) => (7, failure as u32),
        }
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
enum MacPause { NotRequested = 0, Pending = 1, Paused = 2, NotApplied = 3, Unknown = 4 }
impl MacPause {
    fn parse(raw: u32) -> Option<Self> {
        Some(match raw { 0 => Self::NotRequested, 1 => Self::Pending, 2 => Self::Paused,
            3 => Self::NotApplied, 4 => Self::Unknown, _ => return None })
    }
}
#[derive(Clone, Copy)]
enum Completion { MacPaused, NotApplied, OutcomeUnknown }
impl Completion {
    fn parse(raw: u32) -> Option<Self> {
        Some(match raw { 1 => Self::MacPaused, 2 => Self::NotApplied,
            3 => Self::OutcomeUnknown, _ => return None })
    }
}
#[derive(Clone, Copy)]
enum BridgeKind { Ready, Blocked, Sample, Error, UnsupportedRate }
impl BridgeKind {
    fn parse(raw: u32) -> Option<Self> {
        Some(match raw { 0 => Self::Ready, 1 => Self::Blocked, 2 => Self::Sample,
            3 => Self::Error, 4 => Self::UnsupportedRate, _ => return None })
    }
}
#[derive(Clone, Copy)]
struct ProofToken(NonZeroU64);
impl ProofToken { fn parse(raw: u64) -> Option<Self> { NonZeroU64::new(raw).map(Self) } fn raw(self) -> u64 { self.0.get() } }
/// The three identity domains cannot be passed to each other's helpers.
#[derive(Clone, Copy)]
struct MessageIdentity { operation: bool, page: bool, video: bool }
#[derive(Clone, Copy)]
struct ProofIdentity { native_equal: bool, token: Option<ProofToken> }
#[derive(Clone, Copy)]
struct CompletionIdentity(bool);
#[derive(Clone, Copy)]
struct Sample { state: i32, position: u64, duration: u64, rate: u64 }
#[derive(Clone, Copy)]
struct Observation { owner: ProofToken, position: u64, rate: u64, observed_at: u64 }
impl Observation {
    fn parse(raw: Evidence) -> Option<Self> {
        Some(Self { owner: ProofToken::parse(raw.token)?, position: bounded_position(raw.position)?.to_bits(),
            rate: bounded_rate(raw.rate)?.to_bits(), observed_at: finite(raw.observed_at)?.to_bits() })
    }
    fn wire(self) -> Evidence {
        Evidence { token: self.owner.raw(), position: self.position, rate: self.rate, observed_at: self.observed_at }
    }
}
#[derive(Clone, Copy)]
enum Operation {
    Visibility { visible: bool, now: u64 }, Poll { now: u64 },
    Receive { identity: MessageIdentity, sequence: u32, kind: BridgeKind,
        sample: Option<Sample>, now: u64, candidate: Option<ProofToken> },
    IsCurrent { identity: ProofIdentity, now: u64 }, BeginMacPause { identity: ProofIdentity, now: u64 },
    CompleteMacPause { identity: CompletionIdentity, completion: Completion, now: u64 },
    Fail { failure: Failure },
}
impl Operation {
    fn parse(raw: Event) -> Option<Self> {
        if raw.flags & !EVENT_FLAGS != 0 || raw.presence & !SAMPLE_PRESENCE != 0 { return None; }
        let allowed = match raw.opcode { 0 => VISIBLE, 2 => OPERATION_EQUAL | PAGE_EQUAL | VIDEO_EQUAL,
            3 | 4 => PROOF_EQUAL, 5 => COMPLETION_EQUAL, 1 | 6 => 0, _ => return None };
        if raw.flags & !allowed != 0
            || (raw.opcode != 2 && (raw.kind != 0 || raw.sequence != 0 || raw.candidate_token != 0))
            || (raw.opcode == 2 && (raw.kind > 4 || raw.sequence == 0))
            || (raw.opcode != 5 && raw.completion != 0) || (raw.opcode != 6 && raw.failure != 0)
            || (!matches!(raw.opcode, 3 | 4) && raw.proof_token != 0)
            || ((raw.flags & PROOF_EQUAL != 0) != (raw.proof_token != 0)) { return None; }
        let sample = if raw.opcode == 2 && raw.kind == 2 {
            if raw.presence & SAMPLE_STATE != 0 {
                if !valid_player_state(raw.sample_state) { return None; }
            } else if raw.sample_state != 0 { return None; }
            let field = |flag, value, valid: fn(u64) -> Option<f64>| {
                if raw.presence & flag != 0 { valid(value).is_some() } else { value == 0 }
            };
            if !field(SAMPLE_POSITION, raw.sample_position, bounded_position)
                || !field(SAMPLE_DURATION, raw.sample_duration, bounded_position)
                || !field(SAMPLE_RATE, raw.sample_rate, bounded_rate) { return None; }
            (raw.presence == SAMPLE_PRESENCE).then_some(Sample { state: raw.sample_state,
                position: raw.sample_position, duration: raw.sample_duration, rate: raw.sample_rate })
        } else {
            if raw.presence != 0 || raw.sample_state != 0 || raw.sample_position != 0
                || raw.sample_duration != 0 || raw.sample_rate != 0 { return None; }
            None
        };
        let proof = ProofIdentity { native_equal: raw.flags & PROOF_EQUAL != 0, token: ProofToken::parse(raw.proof_token) };
        Some(match raw.opcode {
            0 => Self::Visibility { visible: raw.flags & VISIBLE != 0, now: raw.now },
            1 => Self::Poll { now: raw.now },
            2 => Self::Receive { identity: MessageIdentity { operation: raw.flags & OPERATION_EQUAL != 0,
                page: raw.flags & PAGE_EQUAL != 0, video: raw.flags & VIDEO_EQUAL != 0 },
                sequence: raw.sequence, kind: BridgeKind::parse(raw.kind)?, sample, now: raw.now,
                candidate: ProofToken::parse(raw.candidate_token) },
            3 => Self::IsCurrent { identity: proof, now: raw.now },
            4 => Self::BeginMacPause { identity: proof, now: raw.now },
            5 => Self::CompleteMacPause { identity: CompletionIdentity(raw.flags & COMPLETION_EQUAL != 0),
                completion: Completion::parse(raw.completion)?, now: raw.now },
            6 => Self::Fail { failure: Failure::parse(raw.failure)? },
            _ => return None,
        })
    }
}

#[derive(Clone, Copy)]
enum PlayerEvent { PlayRequired, Confirmed, MovedToPhone, Failed(Failure) }
#[derive(Clone, Copy)]
struct ProductOutput { event: Option<PlayerEvent>, accepted: bool }
impl ProductOutput {
    fn none() -> Self { Self { event: None, accepted: false } }
    fn event(event: Option<PlayerEvent>) -> Self { Self { event, accepted: false } }
    fn boolean(accepted: bool) -> Self { Self { event: None, accepted } }
    fn wire(self, state: State) -> Result {
        let (event, failure) = match self.event {
            None => (0, 0), Some(PlayerEvent::PlayRequired) => (1, 0),
            Some(PlayerEvent::Confirmed) => (2, 0), Some(PlayerEvent::MovedToPhone) => (3, 0),
            Some(PlayerEvent::Failed(failure)) => (4, failure as u32),
        };
        Result { state, status: 0, event, accepted: u32::from(self.accepted), failure }
    }
}

#[derive(Clone, Copy)]
struct Store {
    request: Request, phase: Phase, mac_pause: MacPause,
    visible: bool, has_been_visible: bool, ready: bool, evidence_revoked: bool,
    last_now: u64, sequence: u32, first_playing: Option<(u64, u64)>,
    latest_playing_at: Option<u64>, latest_state: Option<i32>,
    evidence: Option<Observation>, reply_deadline: Option<u64>,
}
impl Store {
    fn parse(raw: State) -> Option<Self> {
        if raw.abi != ABI || raw.reserved != 0 || raw.latest_state_reserved != 0
            || raw.flags & !STATE_FLAGS != 0 || raw.presence & !STATE_PRESENCE != 0
            || (raw.flags & VISIBLE != 0 && raw.flags & HAS_BEEN_VISIBLE == 0)
            || !valid_request(raw.request) { return None; }
        let phase = Phase::parse(raw.phase, raw.failure)?;
        let mac_pause = MacPause::parse(raw.mac_pause)?;
        let first_playing = if raw.presence & FIRST_PLAYING != 0 {
            bounded_position(raw.first_position)?; finite(raw.first_at)?;
            Some((raw.first_position, raw.first_at))
        } else { if raw.first_position != 0 || raw.first_at != 0 { return None; } None };
        let time = |flag, value| if raw.presence & flag != 0 {
            finite(value).map(|_| Some(value))
        } else if value == 0 { Some(None) } else { None };
        let latest_playing_at = time(LATEST_PLAYING, raw.latest_playing_at)?;
        let latest_state = if raw.presence & LATEST_STATE != 0 {
            if !valid_player_state(raw.latest_state) { return None; } Some(raw.latest_state)
        } else { if raw.latest_state != 0 { return None; } None };
        let evidence = if raw.presence & EVIDENCE != 0 { Some(Observation::parse(raw.evidence)?) }
            else { if raw.evidence != Evidence::default() { return None; } None };
        let reply_deadline = time(REPLY_DEADLINE, raw.reply_deadline)?;
        if (reply_deadline.is_some()) != (mac_pause == MacPause::Pending)
            || (!matches!(phase, Phase::Preparing | Phase::Failed(_)) && finite(raw.last_now).is_none()) { return None; }
        let out = Self { request: raw.request, phase, mac_pause,
            visible: raw.flags & VISIBLE != 0, has_been_visible: raw.flags & HAS_BEEN_VISIBLE != 0,
            ready: raw.flags & READY != 0, evidence_revoked: raw.flags & EVIDENCE_REVOKED != 0,
            last_now: raw.last_now, sequence: raw.sequence, first_playing, latest_playing_at,
            latest_state, evidence, reply_deadline };
        let valid = match phase {
            Phase::Confirmed => evidence.is_some() && mac_pause == MacPause::NotRequested,
            Phase::AwaitingMacPause => mac_pause == MacPause::Pending && evidence.is_some() && reply_deadline.is_some(),
            Phase::LocalPlayback => mac_pause == MacPause::Paused && evidence.is_none()
                && first_playing.is_none() && reply_deadline.is_none() && out.evidence_revoked,
            Phase::Failed(_) => !out.visible && out.evidence_revoked && mac_pause != MacPause::Pending
                && first_playing.is_none() && latest_playing_at.is_none() && latest_state.is_none() && reply_deadline.is_none(),
            Phase::Preparing | Phase::Ready | Phase::PlayRequired | Phase::Verifying =>
                mac_pause == MacPause::NotRequested && evidence.is_none(),
        };
        valid.then_some(out)
    }
    fn wire(self) -> State {
        let (phase, failure) = self.phase.wire();
        State { abi: ABI, phase, failure, mac_pause: self.mac_pause as u32,
            flags: u32::from(self.visible) | (u32::from(self.has_been_visible) << 1)
                | (u32::from(self.ready) << 2) | (u32::from(self.evidence_revoked) << 3),
            presence: u32::from(self.first_playing.is_some()) | (u32::from(self.latest_playing_at.is_some()) << 1)
                | (u32::from(self.latest_state.is_some()) << 2) | (u32::from(self.evidence.is_some()) << 3)
                | (u32::from(self.reply_deadline.is_some()) << 4),
            sequence: self.sequence, reserved: 0, request: self.request, last_now: self.last_now,
            first_position: self.first_playing.map(|x| x.0).unwrap_or(0), first_at: self.first_playing.map(|x| x.1).unwrap_or(0),
            latest_playing_at: self.latest_playing_at.unwrap_or(0), latest_state: self.latest_state.unwrap_or(0),
            latest_state_reserved: 0, evidence: self.evidence.map(Observation::wire).unwrap_or_default(),
            reply_deadline: self.reply_deadline.unwrap_or(0) }
    }
    fn terminal(self) -> bool { matches!(self.phase, Phase::Failed(_)) }
    fn fail(&mut self, failure: Failure) -> Option<PlayerEvent> {
        if self.terminal() { return None; }
        if self.mac_pause == MacPause::Pending { self.mac_pause = MacPause::Unknown; }
        self.reply_deadline = None; self.evidence_revoked = true;
        self.phase = Phase::Failed(failure); self.visible = false;
        self.first_playing = None; self.latest_playing_at = None; self.latest_state = None;
        Some(PlayerEvent::Failed(failure))
    }
    fn observe_time(&mut self, now: u64) -> Option<Failure> {
        if self.terminal() { return None; }
        let time = f(now);
        if !time.is_finite() || !(time >= f(self.last_now)) { return Some(Failure::ClockChanged); }
        self.last_now = now;
        if self.reply_deadline.map(|end| time >= f(end)).unwrap_or(false) { return Some(Failure::MacPauseUnknown); }
        if self.phase != Phase::LocalPlayback && time >= f(self.request.deadline) { return Some(Failure::TimedOut); }
        None
    }
    fn current(&mut self, identity: ProofIdentity, now: u64) -> bool {
        if let Some(failure) = self.observe_time(now) { let _ = self.fail(failure); }
        let Some(owned) = self.evidence else { return false; };
        let Some(last) = self.latest_playing_at else { return false; };
        !self.terminal() && matches!(self.mac_pause, MacPause::NotRequested | MacPause::Pending)
            && self.visible && !self.evidence_revoked && identity.native_equal
            && identity.token.map(|x| x.raw()) == Some(owned.owner.raw()) && f(now) < f(self.request.deadline)
            && f(now) >= f(owned.observed_at) && f(now) - f(owned.observed_at) <= 0.75
            && self.latest_state == Some(1) && f(now) >= f(last) && f(now) - f(last) <= 0.75
    }
    fn receive(&mut self, identity: MessageIdentity, sequence: u32, kind: BridgeKind,
               sample: Option<Sample>, now: u64, candidate: Option<ProofToken>) -> Option<PlayerEvent> {
        if !identity.operation || !identity.page { return None; }
        if let Some(failure) = self.observe_time(now) { return self.fail(failure); }
        if self.terminal() || sequence <= self.sequence { return None; }
        self.sequence = sequence;
        if !identity.video { return self.fail(Failure::WrongVideo); }
        if self.phase == Phase::LocalPlayback {
            return match kind {
                BridgeKind::Error => self.fail(Failure::PlayerUnavailable),
                BridgeKind::UnsupportedRate => self.fail(Failure::UnsupportedRate),
                BridgeKind::Blocked => Some(PlayerEvent::PlayRequired),
                BridgeKind::Ready | BridgeKind::Sample => None,
            };
        }
        match kind {
            BridgeKind::Error => self.fail(Failure::PlayerUnavailable),
            BridgeKind::UnsupportedRate => self.fail(Failure::UnsupportedRate),
            BridgeKind::Ready => { self.ready = true; if self.evidence.is_none() { self.phase = Phase::Ready; } None },
            BridgeKind::Blocked => {
                self.first_playing = None; self.latest_playing_at = None; self.latest_state = None;
                if self.evidence.is_some() { self.evidence_revoked = true; }
                if self.mac_pause == MacPause::Pending { return self.fail(Failure::PlaybackInterrupted); }
                if self.evidence.is_none() { self.phase = Phase::PlayRequired; }
                Some(PlayerEvent::PlayRequired)
            },
            BridgeKind::Sample => {
                let Some(sample) = sample.filter(|_| self.visible && self.ready) else { return None; };
                let (time, position, duration, rate) = (f(now), f(sample.position), f(sample.duration), f(sample.rate));
                self.latest_state = Some(sample.state);
                if !(sample.state == 1 && (duration - f(self.request.duration)).abs() <= swift_max(1.0, f(self.request.duration) * 0.002)
                    && (rate - f(self.request.rate)).abs() <= 0.01 && position <= duration) {
                    self.first_playing = None; self.latest_playing_at = None;
                    if self.evidence.is_some() { self.evidence_revoked = true; }
                    if self.mac_pause == MacPause::Pending { return self.fail(Failure::PlaybackInterrupted); }
                    if self.evidence.is_none() { self.phase = Phase::Ready; }
                    return None;
                }
                if let Some(proof) = self.evidence {
                    if (position - (f(proof.position) + (time - f(proof.observed_at)) * rate)).abs() > 2.0 {
                        return self.fail(Failure::PositionChanged);
                    }
                }
                self.latest_playing_at = Some(now);
                if self.evidence.is_some() { return None; }
                let Some((first_position, first_at)) = self.first_playing else {
                    if (position - expected_position(self.request, now)).abs() <= 2.0 {
                        self.first_playing = Some((sample.position, now)); self.phase = Phase::Verifying;
                    }
                    return None;
                };
                let elapsed = time - f(first_at);
                let advance = position - f(first_position);
                if !(elapsed <= 1.5 && (position - expected_position(self.request, now)).abs() <= 2.0) {
                    self.first_playing = None; self.phase = Phase::Ready; return None;
                }
                if !(elapsed >= 0.2 && advance > 0.02
                    && (advance - elapsed * rate).abs() <= swift_max(0.15, elapsed * rate * 0.5)) { return None; }
                // Exhaustion is considered only at the actual mint point, after clock
                // admission, sequence burn and ordinary sample/liveness updates.
                let Some(owner) = candidate else { return self.fail(Failure::InvalidBridge); };
                self.evidence = Some(Observation { owner, position: sample.position, rate: sample.rate, observed_at: now });
                self.phase = Phase::Confirmed; Some(PlayerEvent::Confirmed)
            },
        }
    }
    fn apply(&mut self, operation: Operation) -> ProductOutput {
        match operation {
            Operation::Visibility { visible, now } => {
                if let Some(failure) = self.observe_time(now) { return ProductOutput::event(self.fail(failure)); }
                if self.terminal() { return ProductOutput::none(); }
                self.visible = visible;
                if visible { self.has_been_visible = true; return ProductOutput::none(); }
                self.first_playing = None; self.latest_playing_at = None;
                ProductOutput::event(if self.has_been_visible { self.fail(Failure::NotVisible) } else { None })
            },
            Operation::Poll { now } => {
                let failure = self.observe_time(now); ProductOutput::event(failure.and_then(|failure| self.fail(failure)))
            },
            Operation::Receive { identity, sequence, kind, sample, now, candidate } =>
                ProductOutput::event(self.receive(identity, sequence, kind, sample, now, candidate)),
            Operation::IsCurrent { identity, now } => ProductOutput::boolean(self.current(identity, now)),
            Operation::BeginMacPause { identity, now } => {
                if self.mac_pause != MacPause::NotRequested || !self.current(identity, now) { return ProductOutput::boolean(false); }
                self.mac_pause = MacPause::Pending;
                self.reply_deadline = Some(swift_min(f(self.request.deadline), f(now) + 3.0).to_bits());
                self.phase = Phase::AwaitingMacPause; ProductOutput::boolean(true)
            },
            Operation::CompleteMacPause { identity, completion, now } => {
                if !identity.0 || self.mac_pause != MacPause::Pending { return ProductOutput::none(); }
                if let Some(failure) = self.observe_time(now) { return ProductOutput::event(self.fail(failure)); }
                self.reply_deadline = None;
                match completion {
                    Completion::MacPaused => {
                        self.mac_pause = MacPause::Paused;
                        if !(self.visible && !self.evidence_revoked && self.latest_state == Some(1)
                            && self.latest_playing_at.map(|last| f(now) >= f(last) && f(now) - f(last) <= 0.75).unwrap_or(false)) {
                            return ProductOutput::event(self.fail(Failure::PlaybackInterrupted));
                        }
                        self.evidence_revoked = true; self.evidence = None; self.first_playing = None;
                        self.phase = Phase::LocalPlayback; ProductOutput::event(Some(PlayerEvent::MovedToPhone))
                    },
                    Completion::NotApplied => {
                        self.mac_pause = MacPause::NotApplied; ProductOutput::event(self.fail(Failure::MacPauseNotApplied))
                    },
                    Completion::OutcomeUnknown => {
                        self.mac_pause = MacPause::Unknown; ProductOutput::event(self.fail(Failure::MacPauseUnknown))
                    },
                }
            },
            Operation::Fail { failure } => ProductOutput::event(self.fail(failure)),
        }
    }
}

fn f(raw: u64) -> f64 { f64::from_bits(raw) }
fn finite(raw: u64) -> Option<f64> { f(raw).is_finite().then_some(f(raw)) }
fn bounded_position(raw: u64) -> Option<f64> { finite(raw).filter(|x| *x >= 0.0 && *x <= 31_536_000.0) }
fn bounded_rate(raw: u64) -> Option<f64> { finite(raw).filter(|x| *x > 0.0 && *x <= 16.0) }
fn valid_player_state(value: i32) -> bool { matches!(value, -1 | 0 | 1 | 2 | 3 | 5) }
fn valid_request(value: Request) -> bool {
    bounded_position(value.position).is_some() && bounded_position(value.duration).is_some()
        && f(value.duration) > f(value.position) && bounded_rate(value.rate).is_some()
        && f(value.position_observed_at).is_finite() && f(value.position_observed_at) >= 0.0
        && f(value.deadline).is_finite() && f(value.deadline) > f(value.position_observed_at)
}
// Swift standard-library min/max selection: retain exact NaN/tie/signed-zero behavior.
fn swift_min(x: f64, y: f64) -> f64 { if y < x { y } else { x } }
fn swift_max(x: f64, y: f64) -> f64 { if y >= x { y } else { x } }
fn expected_position(request: Request, now: u64) -> f64 {
    swift_min(f(request.duration), f(request.position)
        + swift_max(0.0, f(now) - f(request.position_observed_at)) * f(request.rate))
}
fn invalid(state: State) -> Result { Result { state, status: 3, event: 0, accepted: 0, failure: 0 } }

/// Initial clock is copied without observation or finite/nonnegative normalization.
/// The request remains the independently validated native request value.
#[must_use]
pub fn initial(request: Request, now: u64) -> State {
    State { abi: ABI, request, last_now: now, ..State::default() }
}

/// Structural malformed input is rejected without altering one input bit. Nonfinite
/// event clocks are ordinary product inputs and retain original observation ordering.
#[must_use]
pub fn step(abi_version: u32, state: State, event: Event) -> Result {
    if abi_version != ABI { return invalid(state); }
    let Some(mut store) = Store::parse(state) else { return invalid(state); };
    let Some(operation) = Operation::parse(event) else { return invalid(state); };
    let output = store.apply(operation);
    output.wire(store.wire())
}
