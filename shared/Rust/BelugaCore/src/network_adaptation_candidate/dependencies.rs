//! Existing Rust reducers versus CURRENT native facade semantics are deliberately separate.
//! These imports name the already adopted subowners, not a new candidate implementation.
use crate::{packet_send_queue as queue, rtt_evidence as rtt, tier_demand as demand};
use super::time_assignments::*;

pub const ATTO: i128 = 1_000_000_000_000_000_000;
pub const MS: i128 = 1_000_000_000_000_000;
pub type RelativeTime = i128;

/// Exact relative attoseconds are a PRIVATE mathematical coordinate, NOT a native Instant ABI.
/// Caller-supplied clock cuts must correspond to original .now evaluation sites. No clock here.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ClockSite { RttEvent, RttApply, QueueReset, PublishedLease, CopyFence }
pub trait ClockFacts {
    fn cut(&mut self, site: ClockSite) -> RelativeTime;
    fn last_time_source(&self) -> TimeSource { TimeSource::Untracked }
}

/// A native callback may fail. Selected bridge operations propagate that failure
/// without supplying a made-up coordinate or continuing the draft transaction.
pub trait TryClockFacts {
    type Error;
    fn try_cut(&mut self, site: ClockSite) -> Result<RelativeTime, Self::Error>;
    fn last_try_time_source(&self) -> TimeSource;
    // Native Swift traps at a consumed overflowing Int expression. Infallible
    // reference callers retain that contract; a raw unpublished draft may deny
    // the actual consumed expression without a panic crossing the C boundary.
    fn try_arithmetic<T>(&mut self, value: Option<T>) -> Result<T, Self::Error> {
        Ok(value.expect("consumed native arithmetic is not representable"))
    }
}
impl<C: ClockFacts> TryClockFacts for C {
    type Error = core::convert::Infallible;
    fn try_cut(&mut self, site: ClockSite) -> Result<RelativeTime, Self::Error> { Ok(self.cut(site)) }
    fn last_try_time_source(&self) -> TimeSource { ClockFacts::last_time_source(self) }
}
pub fn infallible<T>(result: Result<T, core::convert::Infallible>) -> T {
    match result { Ok(value) => value, Err(impossible) => match impossible {} }
}

pub fn native_floor_integer(value: f64) -> Option<i64> {
    let value = value.floor();
    // Double(Int64.max) rounds upward to 2^63; it is not a valid upper bound.
    (value.is_finite() && value >= -9_223_372_036_854_775_808.0 &&
        value < 9_223_372_036_854_775_808.0).then(|| value as i64)
}

/// Store IEEE bits; native semantic equality intentionally is non-reflexive for NaN.
#[derive(Clone, Copy, Debug)]
pub struct Scalar(pub u64);
impl Scalar {
    pub fn new(value: f64) -> Self { Self(value.to_bits()) }
    pub fn value(self) -> f64 { f64::from_bits(self.0) }
    pub fn bits_equal(self, other: Self) -> bool { self.0 == other.0 }
    pub fn positive(self) -> bool { self.value().is_finite() && self.value() > 0.0 }
}
impl PartialEq for Scalar {
    fn eq(&self, other: &Self) -> bool { self.value() == other.value() }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Observation {
    LegacyAbsent,
    Unavailable,
    Measurement { fingerprint: [u64; 8], fingerprint_length: u32, total_bits: u64, responses: u64 },
}
impl Observation {
    pub fn is_unavailable(self) -> bool { self == Self::Unavailable }
    fn copy_into(self, event: &mut rtt::RawEvent) {
        match self {
            Self::LegacyAbsent => {}
            Self::Unavailable => event.observation_kind = 1,
            Self::Measurement { fingerprint, fingerprint_length, total_bits, responses } => {
                event.observation_kind = 2;
                event.fingerprint_length = fingerprint_length;
                event.measurement = rtt::RawMeasurement { fingerprint_words: fingerprint, total_bits, responses };
            }
        }
    }
}

/// Per-call pure producer injection mirrors native test seams; NEVER part of owner equality.
#[derive(Clone, Copy)]
pub struct Dependencies {
    pub queue: fn(queue::RawState, queue::RawEvent) -> queue::RawResult,
    pub rtt: fn(rtt::RawState, rtt::RawEvent) -> rtt::RawResult,
    pub demand: fn(demand::RawTierDemandFacts) -> demand::RawTierDemandProjection,
    pub queue_layout_exact: bool,
    pub rtt_layout_exact: bool,
    pub demand_layout_exact: bool,
}
impl Default for Dependencies {
    fn default() -> Self {
        Self { queue: queue::transition, rtt: rtt::transition, demand: demand::project,
            queue_layout_exact: true, rtt_layout_exact: true, demand_layout_exact: true }
    }
}

fn parts(age: i128) -> Option<(i64, i64)> {
    Some((i64::try_from(age / ATTO).ok()?, i64::try_from(age % ATTO).ok()?))
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum QueueObservation { UnavailableOrReset, NoNewPackets, Measured(Scalar) }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct QueueDecision {
    pub observation: QueueObservation,
    pub sample_inflated: bool,
    pub immediate: bool,
    pub inflated: bool,
    pub allows_upgrade: bool,
    pub allows_growth: bool,
}
impl QueueDecision {
    fn unavailable() -> Self {
        Self { observation: QueueObservation::UnavailableOrReset, sample_inflated: false,
            immediate: false, inflated: false, allows_upgrade: false, allows_growth: false }
    }
    fn from_result(result: queue::RawResult) -> Self {
        Self { observation: match result.observation { 2 => QueueObservation::Measured(Scalar(result.measured_delay_bits)),
                1 => QueueObservation::NoNewPackets, _ => QueueObservation::UnavailableOrReset },
            sample_inflated: result.sample_inflated == 1, immediate: result.immediate == 1,
            inflated: result.inflated == 1, allows_upgrade: result.upgrade == 1,
            allows_growth: result.capacity_growth == 1 }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct PacketQueue {
    pub times: AssignmentJournal,
    pub packets: Option<u64>,
    pub delay_bits: Option<u64>,
    pub pressure_count: i64,
    pub low_observation: Option<RelativeTime>,
    pub soft_observation: Option<RelativeTime>,
    pub faulted: bool,
}
impl PacketQueue {
    fn raw(self) -> queue::RawState {
        queue::RawState { abi_version: 1, reserved: 0, packets_present: self.packets.is_some() as u32,
            delay_present: self.delay_bits.is_some() as u32, low_present: self.low_observation.is_some() as u32,
            soft_present: self.soft_observation.is_some() as u32, packets: self.packets.unwrap_or(0),
            delay_bits: self.delay_bits.unwrap_or(0), pressure_count: self.pressure_count as u64 }
    }
    fn event(self, opcode: u32, packets: Option<u64>, delay: Option<Scalar>, inflated: bool,
             now: RelativeTime) -> Option<queue::RawEvent> {
        let low = if opcode < 2 || opcode == 4 { self.low_observation.map(|at| now - at) } else { None };
        let soft = if opcode < 2 { self.soft_observation.map(|at| now - at) } else { None };
        let (low_s, low_a) = parts(low.unwrap_or(0))?;
        let (soft_s, soft_a) = parts(soft.unwrap_or(0))?;
        Some(queue::RawEvent { opcode, packets_present: packets.is_some() as u32,
            delay_present: delay.is_some() as u32, rtt_inflated: inflated as u32,
            packets: packets.unwrap_or(0), delay_bits: delay.map(|v| v.0).unwrap_or(0),
            low_age_seconds: low_s, low_age_attoseconds: low_a,
            soft_age_seconds: soft_s, soft_age_attoseconds: soft_a })
    }
    fn correlated(before: queue::RawState, event: queue::RawEvent, result: queue::RawResult,
                  dependencies: Dependencies) -> bool {
        // For exact Duration components this is the same complete correlation as the native
        // boundary. The hardwired actual module is NOT replaced by the injected producer.
        dependencies.queue_layout_exact && result.status == 1 && result == queue::transition(before, event)
    }
    fn deny(&mut self) {
        self.packets = None; self.delay_bits = None; self.pressure_count = 0;
        self.low_observation = self.times.clear(TimeSlot::QueueLow);
        self.soft_observation = self.times.clear(TimeSlot::QueueSoft); self.faulted = true;
    }
    fn apply(&mut self, event: Option<queue::RawEvent>, now: RelativeTime, dependencies: Dependencies, source: TimeSource) -> QueueDecision {
        if self.faulted { return QueueDecision::unavailable(); }
        let Some(event) = event else { self.deny(); return QueueDecision::unavailable(); };
        let before = self.raw();
        let result = (dependencies.queue)(before, event);
        if !Self::correlated(before, event, result, dependencies) {
            self.deny(); return QueueDecision::unavailable();
        }
        self.packets = (result.state.packets_present == 1).then_some(result.state.packets);
        self.delay_bits = (result.state.delay_present == 1).then_some(result.state.delay_bits);
        self.pressure_count = result.state.pressure_count as i64;
        if result.low_action == 1 { self.low_observation = self.times.clear(TimeSlot::QueueLow); }
        if result.low_action == 2 { self.low_observation = self.times.set(TimeSlot::QueueLow, now, Some(Origin { source, delta: 0 })); }
        if result.soft_action == 1 { self.soft_observation = self.times.clear(TimeSlot::QueueSoft); }
        if result.soft_action == 2 { self.soft_observation = self.times.set(TimeSlot::QueueSoft, now, Some(Origin { source, delta: 0 })); }
        QueueDecision::from_result(result)
    }
    pub fn observe(&mut self, packets: Option<u64>, delay: Option<Scalar>, inflated: bool,
                   now: RelativeTime, dependencies: Dependencies) -> QueueDecision {
        self.apply(self.event(0, packets, delay, inflated, now), now, dependencies, TimeSource::Explicit(ExplicitTime::PolicyObservedAt))
    }
    pub fn capacity(self, previous_packets: Option<u64>, previous_delay: Option<Scalar>,
                    packets: Option<u64>, delay: Option<Scalar>, now: RelativeTime,
                    dependencies: Dependencies) -> QueueDecision {
        if self.faulted { return QueueDecision::unavailable(); }
        let mut before = self.raw();
        before.packets_present = previous_packets.is_some() as u32;
        before.delay_present = previous_delay.is_some() as u32;
        before.packets = previous_packets.unwrap_or(0);
        before.delay_bits = previous_delay.map(|v| v.0).unwrap_or(0);
        let Some(event) = self.event(1, packets, delay, false, now) else { return QueueDecision::unavailable(); };
        let result = (dependencies.queue)(before, event);
        if Self::correlated(before, event, result, dependencies) { QueueDecision::from_result(result) }
        else { QueueDecision::unavailable() }
    }
    pub fn reset(&mut self, path: bool, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_reset(path, clock, dependencies));
    }
    pub fn try_reset<C: TryClockFacts>(&mut self, path: bool, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        let now = clock.try_cut(ClockSite::QueueReset)?;
        self.apply(self.event(if path { 3 } else { 2 }, None, None, false, now), now, dependencies, clock.last_try_time_source());
        Ok(())
    }
    pub fn low_fresh(self, now: RelativeTime, dependencies: Dependencies) -> bool {
        if self.faulted { return false; }
        let Some(event) = self.event(4, None, None, false, now) else { return false; };
        let result = queue::transition(self.raw(), event);
        Self::correlated(self.raw(), event, result, dependencies) && result.upgrade == 1
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RttEvidence {
    pub fresh_pressure: bool,
    pub allows_upgrade: bool,
    pub legacy_missing: bool,
    pub validation_disposition: u32,
    pub primary_lease_current: bool,
}
impl RttEvidence {
    fn unavailable() -> Self {
        Self { fresh_pressure: false, allows_upgrade: false, legacy_missing: false,
            validation_disposition: 6, primary_lease_current: false }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RoundTripTime {
    pub times: AssignmentJournal,
    pub raw: rtt::RawState,
    pub last_advancement: Option<RelativeTime>,
    pub faulted: bool,
}
impl Default for RoundTripTime {
    fn default() -> Self { Self { times: AssignmentJournal::default(), raw: rtt::RawState::initial(), last_advancement: None, faulted: false } }
}
impl RoundTripTime {
    fn event(self, opcode: u32, current: Option<Scalar>, observation: Observation, route_changed: bool,
             now: RelativeTime) -> Option<rtt::RawEvent> {
        let mut event = rtt::RawEvent { opcode, current_present: current.is_some() as u32,
            current_bits: current.map(|v| v.0).unwrap_or(0), route_changed: route_changed as u32,
            ..rtt::RawEvent::default() };
        observation.copy_into(&mut event);
        if matches!(opcode, 0 | 1 | 10 | 12) {
            let (seconds, attoseconds) = parts(self.last_advancement.map(|at| now - at).unwrap_or(0))?;
            event.age_seconds = seconds; event.age_attoseconds = attoseconds;
        }
        Some(event)
    }
    fn apply(&mut self, event: Option<rtt::RawEvent>, now: RelativeTime, dependencies: Dependencies, source: TimeSource) -> RttEvidence {
        if self.faulted { return RttEvidence::unavailable(); }
        if !dependencies.rtt_layout_exact || self.raw.advancement_present != self.last_advancement.is_some() as u32 {
            self.faulted = true; return RttEvidence::unavailable();
        }
        let Some(event) = event else { self.faulted = true; return RttEvidence::unavailable(); };
        let result = (dependencies.rtt)(self.raw, event);
        if rtt::result_is_valid(self.raw, event, result) != 1 {
            self.faulted = true; return RttEvidence::unavailable();
        }
        let stamp = match result.clock_action { 0 => self.last_advancement, 1 => None, 2 => Some(now),
            _ => { self.faulted = true; return RttEvidence::unavailable(); } };
        if result.state.advancement_present != stamp.is_some() as u32 {
            self.faulted = true; return RttEvidence::unavailable();
        }
        self.raw = result.state;
        self.last_advancement = match result.clock_action {
            0 => stamp,
            1 => self.times.clear(TimeSlot::RttAdvancement),
            2 => self.times.set(TimeSlot::RttAdvancement, now, Some(Origin { source, delta: 0 })),
            _ => unreachable!("validated above"),
        };
        RttEvidence { fresh_pressure: result.fresh_pressure == 1, allows_upgrade: result.allows_upgrade == 1,
            legacy_missing: result.legacy_missing == 1, validation_disposition: result.validation_disposition,
            primary_lease_current: result.primary_lease_current == 1 }
    }
    pub fn observe(&mut self, current: Option<Scalar>, mut observation: Observation, now: RelativeTime,
                   fast: bool, route_changed: bool, dependencies: Dependencies) -> RttEvidence {
        if fast && observation == Observation::LegacyAbsent { observation = Observation::Unavailable; }
        self.apply(self.event(fast as u32, current, observation, route_changed, now), now, dependencies, TimeSource::Explicit(ExplicitTime::PolicyObservedAt))
    }
    pub fn age(&mut self, now: RelativeTime, dependencies: Dependencies) {
        self.apply(self.event(10, None, Observation::LegacyAbsent, false, now), now, dependencies, TimeSource::Explicit(ExplicitTime::PolicyObservedAt));
    }
    pub fn implicit(&mut self, opcode: u32, observation: Observation,
                    clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_implicit(opcode, observation, clock, dependencies));
    }
    pub fn try_implicit<C: TryClockFacts>(&mut self, opcode: u32, observation: Observation,
                    clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        // Preserve the original event(at:.now), apply(at:.now) TWO clock evaluation sites.
        let event_time = clock.try_cut(ClockSite::RttEvent)?;
        let event = self.event(opcode, None, observation, false, event_time);
        let apply_time = clock.try_cut(ClockSite::RttApply)?;
        self.apply(event, apply_time, dependencies, clock.last_try_time_source());
        Ok(())
    }
    pub fn copy_fence(&mut self, other: Self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_copy_fence(other, clock, dependencies));
    }
    pub fn try_copy_fence<C: TryClockFacts>(&mut self, other: Self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        if other.faulted { self.faulted = true; return Ok(()); }
        let mut event = rtt::RawEvent { opcode: 11,
            observation_kind: if other.raw.fence_present == 1 { 2 } else { 1 }, ..rtt::RawEvent::default() };
        if event.observation_kind == 2 {
            event.fingerprint_length = 64; event.measurement = other.raw.fence;
            event.current_present = other.raw.fence_current_present; event.current_bits = other.raw.fence_current_bits;
        }
        let now = clock.try_cut(ClockSite::CopyFence)?;
        self.apply(Some(event), now, dependencies, clock.last_try_time_source());
        Ok(())
    }
    pub fn published_lease(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) -> bool {
        infallible(self.try_published_lease(clock, dependencies))
    }
    pub fn try_published_lease<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<bool, C::Error> {
        if self.faulted || self.raw.age_present != 1 { return Ok(false); }
        let event = rtt::RawEvent { opcode: 12, age_seconds: self.raw.age_seconds,
            age_attoseconds: self.raw.age_attoseconds, ..rtt::RawEvent::default() };
        let now = clock.try_cut(ClockSite::PublishedLease)?;
        Ok(self.apply(Some(event), now, dependencies, clock.last_try_time_source()).primary_lease_current)
    }
    pub fn primary_lease(&mut self, now: RelativeTime, dependencies: Dependencies) -> bool {
        self.apply(self.event(12, None, Observation::LegacyAbsent, false, now), now, dependencies, TimeSource::Explicit(ExplicitTime::PolicyObservedAt)).primary_lease_current
    }
    pub fn health(self) -> u32 { if self.faulted { 0 } else { self.raw.health } }
    pub fn disposition(self) -> u32 { if self.faulted { 6 } else { self.raw.disposition } }
    pub fn uses_native(self) -> bool { self.faulted || self.raw.uses_native == 1 }
    pub fn permits_initial(self) -> bool { !self.faulted && self.raw.permits_initial == 1 }
    pub fn baseline(self) -> Option<Scalar> {
        (!self.faulted && self.raw.baseline_present == 1).then_some(Scalar(self.raw.baseline_bits))
    }
    pub fn provisional(self) -> bool { !self.faulted && self.raw.provisional == 1 }
    pub fn distinct_count(self) -> u32 { if self.faulted { 0 } else { self.raw.distinct_count } }
    pub fn observation_age(self) -> Option<i128> {
        (self.raw.age_present == 1).then_some(self.raw.age_seconds as i128 * ATTO + self.raw.age_attoseconds as i128)
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Profile {
    pub baseline_video: i64, pub maximum_video: i64, pub maximum_total: i64,
    pub minimum_sustainable: i64, pub required: Scalar, pub next_direct: Option<i64>,
}
impl Default for Profile {
    fn default() -> Self { Self { baseline_video: 0, maximum_video: 0, maximum_total: 0,
        minimum_sustainable: 0, required: Scalar(0), next_direct: None } }
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TierDemand {
    pub configured_cap: u32, pub profiles: [Profile; 8], pub profiles_count: u8,
    pub faulted: bool, pub initial: u8, pub maximum_video: i64,
}
impl TierDemand {
    pub fn new(configured_cap: u32, dependencies: Dependencies) -> Self {
        let mut owner = Self { configured_cap, profiles: [Profile::default(); 8], profiles_count: 0,
            faulted: false, initial: 7, maximum_video: 1 };
        if !dependencies.demand_layout_exact { owner.faulted = true; return owner; }
        let mut admitted = [Profile::default(); 8];
        let mut initial = 7; let mut maximum = 1;
        for tier in 0..8 {
            let facts = owner.facts(tier, None); let result = (dependencies.demand)(facts);
            if demand::projection_is_valid(facts, result) != 1 || result.initial_tier > 7 {
                owner.faulted = true; return owner;
            }
            admitted[tier as usize] = Profile { baseline_video: result.baseline_video as i64,
                maximum_video: result.maximum_video as i64, maximum_total: result.maximum_total_rtp as i64,
                minimum_sustainable: result.minimum_sustainable as i64, required: Scalar(result.required_bitrate_bits),
                next_direct: (result.direct_threshold_present == 1).then_some(result.direct_threshold_minimum as i64) };
            initial = result.initial_tier as u8; maximum = result.maximum_tier_video as i64;
        }
        owner.profiles = admitted; owner.profiles_count = 8; owner.initial = initial; owner.maximum_video = maximum;
        owner
    }
    fn facts(self, tier: u32, bandwidth: Option<Scalar>) -> demand::RawTierDemandFacts {
        demand::RawTierDemandFacts { abi_version: 1, configured_cap: self.configured_cap, current_tier: tier,
            bandwidth_present: bandwidth.is_some() as u32, bandwidth_bits: bandwidth.map(|v| v.0).unwrap_or(0) }
    }
    pub fn profile(self, tier: u8) -> Option<Profile> {
        (tier < self.profiles_count).then(|| self.profiles[tier as usize])
    }
    pub fn selection(&mut self, tier: u8, bandwidth: Scalar, dependencies: Dependencies) -> Option<(u8, Option<u8>)> {
        if self.faulted { return None; }
        let facts = self.facts(tier as u32, Some(bandwidth)); let result = (dependencies.demand)(facts);
        if !dependencies.demand_layout_exact || demand::projection_is_valid(facts, result) != 1 || result.sustainable_tier > 7 {
            self.faulted = true; return None;
        }
        Some((result.sustainable_tier as u8, (result.upgrade_present == 1).then_some(result.upgrade_tier as u8)))
    }
}
