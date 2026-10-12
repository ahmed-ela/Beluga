//! Bounded one-use offers and timeline policy. Native identity facts remain
//! primitive projections, never playback or Pause authority.
#![forbid(unsafe_code)]
use core::num::NonZeroU64;

pub const ABI: u32 = crate::ABI_VERSION;
pub const RETIRE_SENT: u32 = 1;
pub const RETIRE_RECEIVED: u32 = 2;
pub const MINT_SENT: u32 = 4;
pub const MINT_RECEIVED: u32 = 8;
pub const ALL_NATIVE_MATCHES: u64 = 15;
pub const AUTH_EQUAL: u64 = 1;
pub const ID_EQUAL: u64 = 2;
pub const CONTEXT_EQUAL: u64 = 4;
pub const VIDEO_EQUAL: u64 = 8;

pub const UPDATE_VALID: u64 = 1;
pub const ITEM_PRESENT: u64 = 2;
pub const SOURCE_YOUTUBE: u64 = 4;
pub const ARTWORK_YOUTUBE: u64 = 8;
pub const PLAYING: u64 = 16;
pub const CAN_PAUSE: u64 = 32;
pub const CAN_SEEK: u64 = 64;
pub const POSITION_PRESENT: u64 = 128;
pub const DURATION_PRESENT: u64 = 256;
pub const PRIMARY_FLAGS: u64 = 511;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[repr(C)]
pub struct Primary {
    pub flags: u64,
    /// Current primary versus the timeline/incoming offer, NOT commit header equality.
    pub native_matches: u64,
    pub revision: u64,
    pub position: u64,
    pub duration: u64,
    pub rate: u64,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[repr(C)]
pub struct Envelope {
    /// Original native context-byte/control-scalar and video-ID checks only.
    pub text_valid: u32,
    pub reserved: u32,
    pub sequence: u64,
    pub revision: u64,
    pub position: u64,
    pub duration: u64,
    pub rate: u64,
    pub lifetime: u64,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[repr(C)]
pub struct Source {
    pub present: u32,
    pub video_equal: u32,
    pub position: u64,
    pub duration: u64,
    pub rate: u64,
    pub observed_at: u64,
    pub deadline: u64,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[repr(C)]
pub struct TimelineWire {
    pub token: u64,
    pub sequence: u64,
    pub revision: u64,
    pub position: u64,
    pub duration: u64,
    pub rate: u64,
    pub lifetime: u64,
    pub origin: u64,
    pub deadline: u64,
    pub last_observation: u64,
    pub last_position: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct State {
    pub abi: u32,
    /// sent, received, sentStateAt, receivedStateAt presence bits respectively.
    pub presence: u32,
    pub terminal: u32,
    pub reserved: u32,
    pub next_sent: u64,
    pub highest_received: u64,
    pub sent_at: u64,
    pub received_at: u64,
    pub sent: TimelineWire,
    pub received: TimelineWire,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[repr(C)]
pub struct Event {
    /// recordSent0, recordReceived1, prepareSent2, sentFailed3,
    /// consumeSent4, receive5, consumeReceived6, prepareCommit7,
    /// discardReceived8, clearTransient9. Reset is initial(), never clear.
    pub opcode: u32,
    pub reserved: u32,
    pub token: u64,
    pub native_matches: u64,
    pub now: u64,
    pub phone_position: u64,
    pub phone_observed_at: u64,
    pub primary: Primary,
    pub envelope: Envelope,
    pub source: Source,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum Decision { None = 0, SentReady = 1, ReceivedReady = 2, ReceivedConsumed = 3, SentConsumed = 4, CommitReady = 5 }

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct Result {
    pub state: State,
    /// 0 valid step (including declined product operation); 3 malformed input.
    pub status: u32,
    pub decision: u32,
    pub effects: u32,
    pub reserved: u32,
    pub retired_sent: u64,
    pub retired_received: u64,
    pub minted_token: u64,
    pub sequence: u64,
    pub lifetime: u64,
    pub deadline: u64,
}

#[derive(Clone, Copy)]
struct Token(NonZeroU64);
impl Token { fn new(raw: u64) -> Option<Self> { NonZeroU64::new(raw).map(Self) } fn raw(self) -> u64 { self.0.get() } }

/// Domain-distinct primitives prevent a commit match from standing in for a
/// current source match even though the copied scalar ABI uses two masks.
#[derive(Clone, Copy)]
struct CommitIdentityFacts(u64);
impl CommitIdentityFacts {
    fn parse(raw: u64) -> Option<Self> { (raw & !ALL_NATIVE_MATCHES == 0).then_some(Self(raw)) }
    fn exact(self) -> bool { self.0 == ALL_NATIVE_MATCHES }
    fn authorization(self) -> bool { self.0 & AUTH_EQUAL != 0 }
    fn requested_context(self) -> bool { self.0 & CONTEXT_EQUAL != 0 }
}
#[derive(Clone, Copy)]
struct PrimaryIdentityFacts(u64);
impl PrimaryIdentityFacts {
    fn parse(raw: u64) -> Option<Self> { (raw & !(CONTEXT_EQUAL | VIDEO_EQUAL) == 0).then_some(Self(raw)) }
    fn exact(self) -> bool { self.0 == CONTEXT_EQUAL | VIDEO_EQUAL }
}
#[derive(Clone, Copy)]
enum Operation {
    RecordSent, RecordReceived, PrepareSent, SentFailed, ConsumeSent,
    Receive, ConsumeReceived, PrepareCommit, DiscardReceived, ClearTransient,
}
impl Operation {
    fn parse(opcode: u32) -> Option<Self> {
        Some(match opcode {
            0 => Self::RecordSent, 1 => Self::RecordReceived, 2 => Self::PrepareSent,
            3 => Self::SentFailed, 4 => Self::ConsumeSent, 5 => Self::Receive,
            6 => Self::ConsumeReceived, 7 => Self::PrepareCommit,
            8 => Self::DiscardReceived, 9 => Self::ClearTransient,
            _ => return None,
        })
    }
}
#[derive(Clone, Copy)]
struct Projection { operation: Operation, raw: Event, commit: CommitIdentityFacts, primary: PrimaryIdentityFacts }

#[derive(Clone, Copy)]
struct Timeline { wire: TimelineWire, owner: Token }
impl Timeline {
    fn new(token: Token, e: Envelope, now: f64) -> Self {
        Self { owner: token, wire: TimelineWire {
            token: token.raw(), sequence: e.sequence, revision: e.revision,
            position: e.position, duration: e.duration, rate: e.rate, lifetime: e.lifetime,
            origin: now.to_bits(), deadline: (now + f(e.lifetime)).to_bits(),
            last_observation: now.to_bits(), last_position: e.position,
        } }
    }
    fn parse(w: TimelineWire) -> Option<Self> {
        let token = Token::new(w.token)?;
        let e = Envelope { text_valid: 1, sequence: w.sequence, revision: w.revision,
            position: w.position, duration: w.duration, rate: w.rate, lifetime: w.lifetime, reserved: 0 };
        if !offer_valid(e) || !f(w.origin).is_finite() || !f(w.last_observation).is_finite()
            || f(w.last_observation) < f(w.origin) || !f(w.last_position).is_finite()
            || f(w.last_position) < f(w.position) || f(w.last_position) >= f(w.duration)
            || w.deadline != (f(w.origin) + f(w.lifetime)).to_bits() { return None; }
        Some(Self { wire: w, owner: token })
    }
    fn expected(self, now: f64) -> f64 { f(self.wire.position) + (now - f(self.wire.origin)) * f(self.wire.rate) }
    fn observe(&mut self, p: Primary, identity: PrimaryIdentityFacts, now: f64) -> bool {
        if !now.is_finite() || now < f(self.wire.last_observation) || !(now < f(self.wire.deadline))
            || !eligible(p) || !identity.exact()
            || f(p.duration) != f(self.wire.duration) || f(p.rate) != f(self.wire.rate)
            || p.revision < self.wire.revision || f(p.position) < f(self.wire.last_position) { return false; }
        let uncertainty = 2.0 * f(self.wire.rate) + 0.25;
        if !((f(p.position) - self.expected(now)).abs() <= uncertainty) { return false; }
        self.wire.last_observation = now.to_bits();
        self.wire.last_position = p.position;
        true
    }
}

#[derive(Clone, Copy)]
struct Store {
    terminal: bool,
    next_sent: u64,
    highest_received: u64,
    sent_at: Option<f64>,
    received_at: Option<f64>,
    sent: Option<Timeline>,
    received: Option<Timeline>,
}
impl Store {
    fn parse(s: State) -> Option<Self> {
        if s.abi != ABI || s.reserved != 0 || s.presence & !15 != 0 || s.terminal > 1 || s.next_sent == 0 { return None; }
        let clock = |flag, value| if s.presence & flag != 0 {
            if f(value).is_finite() { Some(Some(f(value))) } else { None }
        } else if value == 0 { Some(None) } else { None };
        let slot = |flag, value: TimelineWire| if s.presence & flag != 0 {
            Timeline::parse(value).map(Some)
        } else if value == TimelineWire::default() { Some(None) } else { None };
        let out = Self { terminal: s.terminal == 1, next_sent: s.next_sent, highest_received: s.highest_received,
            sent_at: clock(4, s.sent_at)?, received_at: clock(8, s.received_at)?,
            sent: slot(1, s.sent)?, received: slot(2, s.received)? };
        if out.sent.map(|x| x.wire.sequence >= out.next_sent).unwrap_or(false)
            || out.received.map(|x| x.wire.sequence != out.highest_received).unwrap_or(false)
            || (out.terminal && (s.presence != 0 || s.next_sent != u64::MAX || s.highest_received != u64::MAX)) { return None; }
        Some(out)
    }
    fn wire(self) -> State {
        State { abi: ABI, presence: u32::from(self.sent.is_some()) | (u32::from(self.received.is_some()) << 1)
                | (u32::from(self.sent_at.is_some()) << 2) | (u32::from(self.received_at.is_some()) << 3),
            terminal: u32::from(self.terminal), reserved: 0, next_sent: self.next_sent, highest_received: self.highest_received,
            sent_at: self.sent_at.map(f64::to_bits).unwrap_or(0), received_at: self.received_at.map(f64::to_bits).unwrap_or(0),
            sent: self.sent.map(|x| x.wire).unwrap_or_default(), received: self.received.map(|x| x.wire).unwrap_or_default() }
    }
    fn retire_sent(&mut self, out: &mut Result) {
        if let Some(old) = self.sent.take() { out.effects |= RETIRE_SENT; out.retired_sent = old.owner.raw(); }
    }
    fn retire_received(&mut self, out: &mut Result) {
        if let Some(old) = self.received.take() { out.effects |= RETIRE_RECEIVED; out.retired_received = old.owner.raw(); }
    }
    fn consume_received(&mut self, event: Projection, out: &mut Result) -> bool {
        let e = event.raw;
        let Some(mut pending) = self.received.filter(|p| p.owner.raw() == e.token) else { return false; };
        self.retire_received(out);
        event.commit.authorization() && fresh(self.received_at, f(e.now))
            && pending.observe(e.primary, event.primary, f(e.now))
    }
    fn apply(mut self, event: Projection) -> Result {
        let e = event.raw;
        let mut out = blank(self.wire());
        if self.terminal { return out; }
        let now = f(e.now);
        match event.operation {
            Operation::RecordSent | Operation::RecordReceived => {
                let at = now.is_finite().then_some(now);
                if matches!(event.operation, Operation::RecordSent) {
                    self.sent_at = at;
                    if let Some(mut pending) = self.sent {
                        if pending.observe(e.primary, event.primary, now) { self.sent = Some(pending); }
                        else { self.retire_sent(&mut out); }
                    }
                } else {
                    self.received_at = at;
                    if let Some(mut pending) = self.received {
                        if pending.observe(e.primary, event.primary, now) { self.received = Some(pending); }
                        else { self.retire_received(&mut out); }
                    }
                }
            }
            Operation::PrepareSent => {
                if self.sent.map(|p| now >= f(p.wire.deadline)).unwrap_or(false) { self.retire_sent(&mut out); }
                if self.sent.is_none() && fresh(self.sent_at, now) && self.next_sent < u64::MAX
                    && eligible(e.primary) && event.commit.requested_context()
                    && source_matches(e.source, e.primary, now) {
                    let lifetime = if e.source.present == 0 { 30.0 } else {
                        let remaining = f(e.source.deadline) - now;
                        if remaining < 30.0 { remaining } else { 30.0 }
                    };
                    let offered = Envelope { text_valid: e.envelope.text_valid, sequence: self.next_sent,
                        revision: e.primary.revision, position: e.primary.position, duration: e.primary.duration,
                        rate: e.primary.rate, lifetime: lifetime.to_bits(), reserved: 0 };
                    if let Some(owner) = Token::new(e.token).filter(|_| offer_valid(offered)) {
                        self.next_sent += 1;
                        let timeline = Timeline::new(owner, offered, now);
                        self.sent = Some(timeline);
                        out.decision = Decision::SentReady as u32; out.effects |= MINT_SENT;
                        out.minted_token = owner.raw(); out.sequence = offered.sequence;
                        out.lifetime = offered.lifetime; out.deadline = timeline.wire.deadline;
                    }
                }
            }
            Operation::SentFailed => if self.sent.map(|p| p.owner.raw() == e.token).unwrap_or(false) { self.retire_sent(&mut out); },
            Operation::ConsumeSent => if let Some(mut pending) = self.sent {
                if commit_valid(e.envelope, f(e.phone_position)) && event.commit.exact()
                    && e.envelope.sequence == pending.wire.sequence
                    && f(e.envelope.duration) == f(pending.wire.duration)
                    && f(e.envelope.rate) == f(pending.wire.rate) {
                    self.retire_sent(&mut out);
                    if fresh(self.sent_at, now) && pending.observe(e.primary, event.primary, now)
                        && (f(e.phone_position) - pending.expected(now)).abs() <= 2.0 + 2.0 * f(pending.wire.rate) {
                        out.decision = Decision::SentConsumed as u32; out.deadline = pending.wire.deadline;
                    }
                }
            },
            Operation::Receive => if offer_valid(e.envelope) && event.commit.authorization()
                && e.envelope.sequence > self.highest_received {
                self.highest_received = e.envelope.sequence;
                self.retire_received(&mut out);
                if fresh(self.received_at, now) && e.envelope.revision == e.primary.revision
                    && eligible(e.primary) && event.primary.exact()
                    && f(e.primary.duration) == f(e.envelope.duration) && f(e.primary.rate) == f(e.envelope.rate)
                    && f(e.primary.position) == f(e.envelope.position) {
                    if let Some(owner) = Token::new(e.token) {
                        let timeline = Timeline::new(owner, e.envelope, now);
                        self.received = Some(timeline);
                        out.decision = Decision::ReceivedReady as u32; out.effects |= MINT_RECEIVED;
                        out.minted_token = owner.raw(); out.sequence = e.envelope.sequence;
                        out.lifetime = e.envelope.lifetime; out.deadline = timeline.wire.deadline;
                    }
                }
            },
            Operation::ConsumeReceived => if self.consume_received(event, &mut out) { out.decision = Decision::ReceivedConsumed as u32; },
            Operation::PrepareCommit => if commit_valid(e.envelope, f(e.phone_position)) && now.is_finite()
                && f(e.phone_observed_at).is_finite() && now >= f(e.phone_observed_at)
                && now - f(e.phone_observed_at) <= 0.75 && self.consume_received(event, &mut out) {
                out.decision = Decision::CommitReady as u32;
            },
            Operation::DiscardReceived => if self.received.map(|p| p.owner.raw() == e.token).unwrap_or(false) { self.retire_received(&mut out); },
            Operation::ClearTransient => { self.retire_sent(&mut out); self.retire_received(&mut out); self.sent_at = None; self.received_at = None; }
        }
        out.state = self.wire(); out
    }
}

fn f(raw: u64) -> f64 { f64::from_bits(raw) }
fn fresh(at: Option<f64>, now: f64) -> bool {
    let Some(at) = at else { return false; };
    if !at.is_finite() || !now.is_finite() { return false; }
    let age = now - at; age >= 0.0 && age < 2.0
}
fn eligible(p: Primary) -> bool {
    p.flags == PRIMARY_FLAGS && f(p.rate) > 0.0 && f(p.position).is_finite()
        && f(p.duration).is_finite() && f(p.duration) > 0.0 && f(p.position) >= 0.0
        && f(p.position) < f(p.duration)
}
fn offer_valid(e: Envelope) -> bool {
    e.text_valid == 1 && e.sequence > 0 && e.revision > 0
        && f(e.position).is_finite() && f(e.position) >= 0.0 && f(e.position) < f(e.duration)
        && f(e.duration).is_finite() && f(e.duration) > 0.0 && f(e.duration) <= 31_536_000.0
        && f(e.rate).is_finite() && f(e.rate) > 0.0 && f(e.rate) <= 16.0
        && f(e.lifetime).is_finite() && f(e.lifetime) > 0.0 && f(e.lifetime) <= 30.0
}
fn commit_valid(e: Envelope, phone: f64) -> bool {
    e.text_valid == 1 && e.sequence > 0 && f(e.duration).is_finite()
        && f(e.duration) > 0.0 && f(e.duration) <= 31_536_000.0
        && phone.is_finite() && phone >= 0.0 && phone < f(e.duration)
        && f(e.rate).is_finite() && f(e.rate) > 0.0 && f(e.rate) <= 16.0
}
fn source_matches(s: Source, p: Primary, now: f64) -> bool {
    if s.present == 0 { return true; }
    let age = now - f(s.observed_at);
    age.is_finite() && age >= 0.0 && age < 2.0 && f(s.observed_at) >= 0.0
        && f(s.deadline).is_finite() && f(s.deadline) > now && f(s.deadline) - f(s.observed_at) <= 30.0
        && f(s.position).is_finite() && f(s.position) >= 0.0 && f(s.position) < f(s.duration)
        && f(s.duration).is_finite() && f(s.duration) <= 31_536_000.0
        && f(s.rate).is_finite() && f(s.rate) > 0.0 && f(s.rate) <= 16.0 && s.video_equal == 1
        && f(p.duration) == f(s.duration) && f(p.rate) == f(s.rate)
        && (f(p.position) - (f(s.position) + age * f(s.rate))).abs() <= 2.0 * f(s.rate) + 0.25
}
fn blank(state: State) -> Result {
    Result { state, status: 0, decision: 0, effects: 0, reserved: 0,
        retired_sent: 0, retired_received: 0, minted_token: 0, sequence: 0, lifetime: 0, deadline: 0 }
}
pub fn initial() -> State {
    Store { terminal: false, next_sent: 1, highest_received: 0, sent_at: None,
        received_at: None, sent: None, received: None }.wire()
}
pub fn step(abi: u32, state: State, event: Event) -> Result {
    let Some(store) = Store::parse(state).filter(|_| abi == ABI) else {
        let closed = Store { terminal: true, next_sent: u64::MAX, highest_received: u64::MAX,
            sent_at: None, received_at: None, sent: None, received: None }.wire();
        let mut out = blank(closed); out.status = 3;
        if state.sent.token != 0 { out.effects |= RETIRE_SENT; out.retired_sent = state.sent.token; }
        if state.received.token != 0 { out.effects |= RETIRE_RECEIVED; out.retired_received = state.received.token; }
        return out;
    };
    if event.reserved != 0 || event.primary.flags & !PRIMARY_FLAGS != 0
        || event.primary.native_matches & !(CONTEXT_EQUAL | VIDEO_EQUAL) != 0
        || event.native_matches & !ALL_NATIVE_MATCHES != 0 || event.envelope.text_valid > 1
        || event.envelope.reserved != 0 || event.source.present > 1 || event.source.video_equal > 1 {
        let mut out = blank(state); out.status = 3; return out;
    }
    let Some(commit) = CommitIdentityFacts::parse(event.native_matches) else { let mut out = blank(state); out.status = 3; return out; };
    let Some(primary) = PrimaryIdentityFacts::parse(event.primary.native_matches) else { let mut out = blank(state); out.status = 3; return out; };
    let Some(operation) = Operation::parse(event.opcode) else { let mut out = blank(state); out.status = 3; return out; };
    store.apply(Projection { operation, raw: event, commit, primary })
}
