//! Complete outer-policy candidate, PRIVATE mathematical domain, not adopted/compiled.
use super::dependencies::*;
use super::time_assignments::*;
use super::diagnostics::*;

const HALF_SECOND: i128 = 500 * MS;
const QUEUE_VALIDITY: i128 = 1_500 * MS;
const PROBE_GRACE: i128 = 3_500 * MS;
const CONTINUITY: i128 = 2 * ATTO;

#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Tier { Full, High, Balanced, Constrained, Critical, Survival, Emergency, AudioPriority }
impl Tier {
    pub fn from_ordinal(value: u8) -> Option<Self> {
        Some(match value { 0 => Self::Full, 1 => Self::High, 2 => Self::Balanced, 3 => Self::Constrained,
            4 => Self::Critical, 5 => Self::Survival, 6 => Self::Emergency, 7 => Self::AudioPriority, _ => return None })
    }
    fn fps(self) -> i64 { [60, 45, 30, 20, 10, 5, 2, 1][self as usize] }
    fn scale(self) -> f64 { [1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 8.0, 12.0][self as usize] }
    fn higher(self) -> Option<Self> { (self as u8).checked_sub(1).and_then(Self::from_ordinal) }
    fn lower(self) -> Option<Self> { Self::from_ordinal(self as u8 + 1) }
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Recommendation { pub tier: Tier, pub maximum_video: i64, pub maximum_total: i64,
    pub fps: i64, pub scale: Scalar }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SuspensionDecision { Suspend, Resume }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Restoration { pub disproved: bool, pub cooldown: i64, pub failures: i64 }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Promotion { pub tier: Tier, pub maximum_total: i64, pub deadline: RelativeTime }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CapacitySample { pub packets: Option<u64>, pub delay: Option<Scalar> }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FloorWitness { pub observed_at: RelativeTime, pub bandwidth: Scalar }

/// Full optional native equality supplied for the corresponding retained native route.
/// No route hash/token/body is minted or stored by this mathematical model.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RouteFacts { pub incoming_present: bool, pub equal_to_retained: bool }
impl RouteFacts {
    fn equals(self, retained_present: bool) -> bool {
        self.incoming_present == retained_present && (!retained_present || self.equal_to_retained)
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RouteAction { Retain, Clear, CopyIncoming }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Report {
    pub peer: u64, pub capture_active: bool, pub automatically_suspended: bool,
    pub bandwidth: Option<Scalar>, pub current_rtt: Option<Scalar>, pub observation: Observation,
    pub collection_sequence: Option<u64>, pub strict: bool, pub route: RouteFacts,
    pub packets: Option<u64>, pub delay: Option<Scalar>, pub native_timestamp: Option<Scalar>,
    pub observed_at: RelativeTime,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RegularEvaluation { pub recommendation: Option<Recommendation>, pub route_action: RouteAction,
    pub diagnostics: FloorDiagnostics }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CapacityEvaluation { pub recommendation: Option<Recommendation>, pub diagnostics: CapacityDiagnostics }

/// Exactly 3 immutable +51 mutable stored outer fields, with native route value represented
/// only by presence and a separate corresponding native sidecar. Semantic Eq needs that sidecar.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Policy {
    pub times: AssignmentJournal,
    pub configured_cap: i64, pub maximum_tier_video: i64, pub base_fps: i64,
    pub peer: Option<u64>, pub tier: Tier, pub healthy_upgrades: i64,
    pub bandwidth_downgrades: i64, pub unavailable_samples: i64, pub positive_bootstrap: i64,
    pub limited_upgrades: i64, pub probe_healthy: i64, pub probe_grace: i64,
    pub probe_deadline: Option<RelativeTime>, pub probe_cooldown: i64, pub probe_failures: i64,
    pub below_reserve_disproved: bool, pub resume_restoration: Option<Restoration>,
    pub probe_origin: Option<Tier>, pub probe_best: Option<Tier>, pub probe_confirmed: Option<Tier>,
    pub probe_qualification_at: Option<RelativeTime>, pub probe_maximum: Option<i64>,
    pub promotion: Option<Promotion>, pub suspension_pressure: i64, pub stable_resume: i64,
    pub maximum_resume: i64, pub bandwidth_unavailable: bool, pub last_latency_pressure: bool,
    pub last_positive_suspension_pressure: bool, pub last_average_delay: Option<Scalar>,
    pub queue: PacketQueue, pub rtt: RoundTripTime, pub demand: TierDemand,
    pub consumed_sequence: Option<u64>, pub route_present: bool,
    pub capacity_sample: Option<CapacitySample>, pub capacity_bandwidth_high: Option<Scalar>,
    pub capacity_timestamp: Option<Scalar>, pub capacity_sequence: Option<u64>, pub capacity_growth_veto: bool,
    pub floor_show: Option<u64>, pub floor_reserved: bool, pub floor_active: bool,
    pub floor_attempt_consumed: bool, pub floor_probe_cancelled: bool, pub floor_seed: Option<Scalar>,
    pub floor_first_witness: Option<FloorWitness>, pub floor_regular_sequence: Option<u64>,
    pub floor_regular_timestamp: Option<Scalar>, pub floor_cooldown_at: Option<RelativeTime>,
    pub startup_peer: Option<u64>, pub startup_show: Option<u64>, pub startup_disproved: bool,
    pub startup_sparse_deadline: Option<RelativeTime>,
}
impl Policy {
    pub fn new(configured_cap: i64, base_fps: i64, dependencies: Dependencies) -> Self {
        let cap = configured_cap.max(1).min(u32::MAX as i64);
        let demand = TierDemand::new(cap as u32, dependencies);
        Self { times: AssignmentJournal::default(), configured_cap: cap, maximum_tier_video: demand.maximum_video, base_fps: base_fps.max(1),
            peer: None, tier: Tier::from_ordinal(demand.initial).unwrap_or(Tier::AudioPriority),
            healthy_upgrades: 0, bandwidth_downgrades: 0, unavailable_samples: 0, positive_bootstrap: 0,
            limited_upgrades: 0, probe_healthy: 0, probe_grace: 0, probe_deadline: None,
            probe_cooldown: 0, probe_failures: 0, below_reserve_disproved: false, resume_restoration: None,
            probe_origin: None, probe_best: None, probe_confirmed: None, probe_qualification_at: None,
            probe_maximum: None, promotion: None, suspension_pressure: 0, stable_resume: 0, maximum_resume: 0,
            bandwidth_unavailable: false, last_latency_pressure: false, last_positive_suspension_pressure: false,
            last_average_delay: None, queue: PacketQueue::default(), rtt: RoundTripTime::default(), demand,
            consumed_sequence: None, route_present: false, capacity_sample: None, capacity_bandwidth_high: None,
            capacity_timestamp: None, capacity_sequence: None, capacity_growth_veto: false,
            floor_show: None, floor_reserved: false, floor_active: false, floor_attempt_consumed: false,
            floor_probe_cancelled: false, floor_seed: None, floor_first_witness: None,
            floor_regular_sequence: None, floor_regular_timestamp: None, floor_cooldown_at: None,
            startup_peer: None, startup_show: None, startup_disproved: false, startup_sparse_deadline: None }
    }

    /// Invocation-local metadata must be rebased once at the original outer entry, not helpers.
    pub fn begin_time_assignment_frame(&mut self) {
        self.times.begin_current_frame();
        self.queue.times.begin_current_frame(); self.rtt.times.begin_current_frame();
    }
    pub fn import_corresponding_prepared_times(&mut self) {
        self.times.import_prepared(TimeSlot::ProbeDeadline, self.probe_deadline);
        self.times.import_prepared(TimeSlot::ProbeQualification, self.probe_qualification_at);
        self.times.import_prepared(TimeSlot::PromotionDeadline, self.promotion.map(|p| p.deadline));
        self.times.import_prepared(TimeSlot::FloorWitness, self.floor_first_witness.map(|w| w.observed_at));
        self.times.import_prepared(TimeSlot::FloorCooldown, self.floor_cooldown_at);
        self.times.import_prepared(TimeSlot::SparseDeadline, self.startup_sparse_deadline);
        self.queue.times.import_prepared(TimeSlot::QueueLow, self.queue.low_observation);
        self.queue.times.import_prepared(TimeSlot::QueueSoft, self.queue.soft_observation);
        self.rtt.times.import_prepared(TimeSlot::RttAdvancement, self.rtt.last_advancement);
    }
    pub fn time_edit(&self, slot: TimeSlot) -> TimeEdit {
        match slot {
            TimeSlot::QueueLow | TimeSlot::QueueSoft => self.queue.times.edit(slot),
            TimeSlot::RttAdvancement => self.rtt.times.edit(slot),
            _ => self.times.edit(slot),
        }
    }
    pub fn swift_equal(&self, other: &Self, native_routes_equal: bool) -> bool {
        // Derived PartialEq deliberately uses numeric Scalar semantics, raw DTO bit equality,
        // and mathematical clock equality. Opaque full route comparison remains native.
        self == other && (!self.route_present || native_routes_equal)
    }
    fn extract_float_bits(&mut self) -> [Option<u64>; 15] {
        let mut result = [None; 15];
        let slots = [&mut self.last_average_delay, &mut self.capacity_bandwidth_high,
            &mut self.capacity_timestamp, &mut self.floor_seed, &mut self.floor_regular_timestamp];
        for (index, slot) in slots.into_iter().enumerate() {
            result[index] = slot.map(|v| v.0); *slot = slot.map(|_| Scalar(0));
        }
        if let Some(sample) = &mut self.capacity_sample {
            result[5] = sample.delay.map(|v| v.0); sample.delay = sample.delay.map(|_| Scalar(0));
        }
        if let Some(witness) = &mut self.floor_first_witness { result[6] = Some(witness.bandwidth.0); witness.bandwidth = Scalar(0); }
        for (index, profile) in self.demand.profiles.iter_mut().enumerate() {
            result[7 + index] = Some(profile.required.0); profile.required = Scalar(0);
        }
        result
    }
    pub fn bits_equal(&self, other: &Self, native_route_bits_equal: bool) -> bool {
        let mut left = *self; let mut right = *other;
        left.extract_float_bits() == right.extract_float_bits()
            && left == right && (!left.route_present || native_route_bits_equal)
    }
    pub fn terminal_fault(self) -> bool { self.rtt.faulted || self.demand.faulted }
    pub fn startup_active(self) -> bool {
        !self.startup_disproved && self.startup_peer.is_some() && self.startup_show.is_some()
            && self.peer == self.startup_peer && self.floor_show == self.startup_show
            && (self.floor_reserved || self.floor_active)
    }
    pub fn floor_probe_active(self) -> bool { self.floor_seed.is_some() && self.probe_origin == Some(Tier::AudioPriority) }
    pub fn recommendation(self, tier: Tier) -> Recommendation {
        Recommendation { tier, maximum_video: self.demand.profile(tier as u8).map(|v| v.maximum_video).unwrap_or(1),
            maximum_total: self.total_for(tier), fps: self.base_fps.min(tier.fps()), scale: Scalar::new(tier.scale()) }
    }
    pub fn current_recommendation(self) -> Recommendation {
        let mut recommendation = self.recommendation(self.tier);
        if let Some(promotion) = self.promotion.filter(|p| p.tier == self.tier) { recommendation.maximum_total = promotion.maximum_total; }
        if self.probe_origin.is_some() {
            if let Some(cap) = self.probe_maximum { recommendation.maximum_video = self.maximum_tier_video; recommendation.maximum_total = cap; }
        }
        if self.startup_active() {
            let initial = Tier::Survival.fps().min(recommendation.fps);
            let scale = recommendation.scale.value();
            let pixel_fps = (recommendation.fps as f64 / (scale * scale)).floor() as i64;
            recommendation.fps = recommendation.fps.min(initial.max(pixel_fps)); recommendation.scale = Scalar::new(1.0);
        }
        recommendation
    }
    pub fn current_minimum_sustainable(self) -> i64 { self.demand.profile(self.tier as u8).map(|p| p.minimum_sustainable).unwrap_or(i64::MAX) }
    pub fn next_direct_threshold(self) -> Option<i64> { self.demand.profile(self.tier as u8).and_then(|p| p.next_direct) }
    fn required(self, tier: Tier) -> f64 { self.demand.profile(tier as u8).map(|v| v.required.value()).unwrap_or(f64::INFINITY) }
    fn total_for(self, tier: Tier) -> i64 { self.demand.profile(tier as u8).map(|v| v.maximum_total).unwrap_or(1) }
    pub fn bind(&mut self, generation: u64, clock: &mut impl ClockFacts, dependencies: Dependencies) -> bool {
        infallible(self.try_bind(generation, clock, dependencies))
    }
    pub fn try_bind<C: TryClockFacts>(&mut self, generation: u64, clock: &mut C, dependencies: Dependencies) -> Result<bool, C::Error> {
        if self.peer == Some(generation) { return Ok(false); }
        self.clear_startup(); self.peer = Some(generation);
        self.tier = Tier::from_ordinal(self.demand.initial).unwrap_or(Tier::AudioPriority);
        self.route_present = false; self.try_reset_path(clock, dependencies)?;
        self.consumed_sequence = None; self.floor_show = None; self.floor_reserved = false; self.floor_active = false;
        self.floor_attempt_consumed = false; self.floor_probe_cancelled = false; self.floor_seed = None;
        self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); self.floor_regular_sequence = None; self.floor_regular_timestamp = None;
        self.floor_cooldown_at = self.times.clear(TimeSlot::FloorCooldown); self.capacity_sequence = None; self.capacity_timestamp = None;
        self.rtt.try_implicit(5, Observation::LegacyAbsent, clock, dependencies)?; self.reset_legacy(); Ok(true)
    }
    pub fn reserve_show(&mut self, generation: u64, show: u64, clock: &mut impl ClockFacts, dependencies: Dependencies) -> bool {
        infallible(self.try_reserve_show(generation, show, clock, dependencies))
    }
    pub fn try_reserve_show<C: TryClockFacts>(&mut self, generation: u64, show: u64, clock: &mut C, dependencies: Dependencies) -> Result<bool, C::Error> {
        let bound = self.try_bind(generation, clock, dependencies)?;
        if show == 0 || show <= self.floor_show.unwrap_or(0) { return Ok(bound); }
        self.try_end_show(clock, dependencies)?; self.floor_show = Some(show); self.floor_reserved = true;
        self.floor_attempt_consumed = false; self.floor_probe_cancelled = false;
        if !self.terminal_fault() && self.peer == Some(generation) && self.floor_show == Some(show)
            && self.floor_reserved && self.tier == Tier::Survival && self.required(Tier::Full) <= self.configured_cap as f64 {
            self.startup_peer = Some(generation); self.startup_show = Some(show);
            self.startup_disproved = false; self.startup_sparse_deadline = self.times.clear(TimeSlot::SparseDeadline);
        }
        Ok(bound)
    }
    pub fn activate_show(&mut self, generation: u64, show: u64) {
        if self.peer == Some(generation) && self.floor_show == Some(show) && self.floor_reserved { self.floor_active = true; }
    }
    pub fn end_show(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_end_show(clock, dependencies));
    }
    pub fn try_end_show<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.clear_startup(); self.floor_reserved = false; self.floor_active = false; self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness);
        if self.floor_probe_active() || self.probe_confirmed.is_some() { self.try_revert_probe(clock, dependencies)?; }
        Ok(())
    }
    pub fn retain_attempt(&mut self, observed: Self) {
        if self.peer != observed.peer || self.floor_show.is_none() || self.floor_show != observed.floor_show || !observed.floor_attempt_consumed { return; }
        self.floor_attempt_consumed = true; self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness);
        if let Some(sequence) = observed.floor_regular_sequence { self.floor_regular_sequence = Some(self.floor_regular_sequence.unwrap_or(0).max(sequence)); }
        if let Some(timestamp) = observed.floor_regular_timestamp {
            // Swift max(x, y) selects y >= x ? y : x, including unordered
            // NaNs and signed-zero ties. Preserve the selected Scalar's bits.
            let current = self.floor_regular_timestamp.unwrap_or(Scalar::new(0.0));
            self.floor_regular_timestamp = Some(if timestamp.value() >= current.value() { timestamp } else { current });
        }
    }
    pub fn retain_rtt_fault(&mut self, observed: Self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_retain_rtt_fault(observed, clock, dependencies));
    }
    pub fn try_retain_rtt_fault<C: TryClockFacts>(&mut self, observed: Self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        if observed.rtt.faulted { self.try_retain_fault(observed, clock, dependencies)?; }
        Ok(())
    }
    pub fn retain_fault(&mut self, observed: Self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_retain_fault(observed, clock, dependencies));
    }
    pub fn try_retain_fault<C: TryClockFacts>(&mut self, observed: Self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        if self.peer.is_none() || self.peer != observed.peer || !observed.terminal_fault() { return Ok(()); }
        if observed.rtt.faulted { self.rtt.faulted = true; }
        if observed.demand.faulted { self.demand.faulted = true; }
        self.try_fault_recommendation(false, clock, dependencies)?;
        Ok(())
    }
    fn fault_recommendation(&mut self, active: bool, clock: &mut impl ClockFacts, dependencies: Dependencies) -> Option<Recommendation> {
        infallible(self.try_fault_recommendation(active, clock, dependencies))
    }
    fn try_fault_recommendation<C: TryClockFacts>(&mut self, active: bool, clock: &mut C, dependencies: Dependencies) -> Result<Option<Recommendation>, C::Error> {
        if !self.terminal_fault() { return Ok(None); }
        let previous = self.current_recommendation(); self.try_revert_probe(clock, dependencies)?;
        self.promotion = self.times.clear(TimeSlot::PromotionDeadline); self.disprove_startup(); self.healthy_upgrades = 0; self.limited_upgrades = 0;
        Ok((active && self.current_recommendation() != previous).then(|| self.current_recommendation()))
    }
    pub fn invalidate_route(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_invalidate_route(clock, dependencies));
    }
    pub fn try_invalidate_route<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        let replaced = self.route_present; self.route_present = false;
        if replaced { self.disprove_startup(); }
        self.try_revert_probe(clock, dependencies)?; self.try_reset_path(clock, dependencies)?;
        Ok(())
    }
    pub fn retain_startup_terminal(&mut self, observed: Self) {
        let (Some(peer), Some(show)) = (self.startup_peer, self.startup_show) else { return; };
        if !self.startup_disproved && observed.startup_disproved && self.peer == Some(peer) && self.floor_show == Some(show)
            && observed.startup_peer == Some(peer) && observed.startup_show == Some(show)
            && observed.peer == Some(peer) && observed.floor_show == Some(show) {
            self.startup_disproved = true; self.startup_sparse_deadline = self.times.clear(TimeSlot::SparseDeadline);
        }
    }
    fn clear_startup(&mut self) { self.startup_peer = None; self.startup_show = None; self.startup_disproved = false; self.startup_sparse_deadline = self.times.clear(TimeSlot::SparseDeadline); }
    fn disprove_startup(&mut self) -> bool {
        if !self.startup_active() { return false; }
        self.startup_disproved = true; self.startup_sparse_deadline = self.times.clear(TimeSlot::SparseDeadline); true
    }
    fn observe_gap(&mut self, report: Report, primary_healthy: Option<bool>) {
        let Some(deadline) = self.probe_deadline else { self.startup_sparse_deadline = self.times.clear(TimeSlot::SparseDeadline); return; };
        if self.startup_active() && !report.route.incoming_present && report.bandwidth.is_none()
            && report.current_rtt.is_none() && report.observation.is_unavailable()
            && (primary_healthy.unwrap_or(self.rtt.health() == 1) || self.startup_sparse_deadline == Some(deadline)) {
            self.startup_sparse_deadline = self.times.copy(TimeSlot::SparseDeadline, TimeSlot::ProbeDeadline, deadline, 0);
        } else { self.startup_sparse_deadline = self.times.clear(TimeSlot::SparseDeadline); }
    }
    pub fn revoke_for_hide(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_revoke_for_hide(clock, dependencies));
    }
    pub fn try_revoke_for_hide<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.startup_sparse_deadline = self.times.clear(TimeSlot::SparseDeadline); self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness);
        if self.probe_confirmed.is_some() { self.try_revert_probe(clock, dependencies)?; }
        self.probe_healthy = 0; self.rtt.try_implicit(3, Observation::LegacyAbsent, clock, dependencies)?;
        if self.terminal_fault() { self.try_fault_recommendation(false, clock, dependencies)?; }
        Ok(())
    }
    pub fn reset_incomplete(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_reset_incomplete(clock, dependencies));
    }
    pub fn try_reset_incomplete<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); self.capacity_sample = None; self.capacity_bandwidth_high = None;
        self.promotion = self.times.clear(TimeSlot::PromotionDeadline); self.healthy_upgrades = 0; self.bandwidth_downgrades = 0;
        self.queue.try_reset(false, clock, dependencies)?; self.unavailable_samples = 0; self.positive_bootstrap = 0;
        self.limited_upgrades = 0; self.probe_healthy = 0; self.probe_best = None;
        Ok(())
    }
    pub fn update(&mut self, report: Report, clock: &mut impl ClockFacts, dependencies: Dependencies) -> RegularEvaluation {
        infallible(self.try_update(report, clock, dependencies))
    }
    pub fn try_update<C: TryClockFacts>(&mut self, report: Report, clock: &mut C,
                                       dependencies: Dependencies) -> Result<RegularEvaluation, C::Error> {
        let bound = self.try_bind(report.peer, clock, dependencies)?;
        let mut diagnostics = FloorDiagnostics::new(self, report, report.observed_at);
        let mut route_action = if bound { RouteAction::Clear } else { RouteAction::Retain };
        let recommendation = self.try_update_regular_body(report, bound, &mut diagnostics, &mut route_action, clock, dependencies)?;
        diagnostics.proposed_total = self.current_recommendation().maximum_total;
        Ok(RegularEvaluation { recommendation, route_action, diagnostics })
    }
    fn update_regular_body(&mut self, report: Report, bound: bool, diagnostics: &mut FloorDiagnostics,
                           route_action: &mut RouteAction, clock: &mut impl ClockFacts,
                           dependencies: Dependencies) -> Option<Recommendation> {
        infallible(self.try_update_regular_body(report, bound, diagnostics, route_action, clock, dependencies))
    }
    fn try_update_regular_body<C: TryClockFacts>(&mut self, report: Report, bound: bool, diagnostics: &mut FloorDiagnostics,
                                                route_action: &mut RouteAction, clock: &mut C,
                                                dependencies: Dependencies) -> Result<Option<Recommendation>, C::Error> {
        let active = report.capture_active; let now = report.observed_at;
        if self.terminal_fault() { return self.try_fault_recommendation(active, clock, dependencies); }
        self.rtt.age(now, dependencies);
        if self.terminal_fault() { return self.try_fault_recommendation(active, clock, dependencies); }
        if report.strict && report.collection_sequence.is_none() {
            diagnostics.identity = FloorIdentity::RejectedOrder; diagnostics.reason = FloorReason::RejectedOrder;
            self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); self.probe_healthy = 0;
            self.rtt.try_implicit(9, Observation::LegacyAbsent, clock, dependencies)?;
            self.last_latency_pressure = false; self.last_positive_suspension_pressure = false;
            return self.try_expire(report.peer, active, now, clock, dependencies);
        }
        if let Some(sequence) = report.collection_sequence {
            if self.capacity_sequence.is_some_and(|last| sequence <= last) {
                diagnostics.identity = FloorIdentity::RejectedOrder; diagnostics.reason = FloorReason::RejectedOrder;
                self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); self.probe_healthy = 0;
                return self.try_expire(report.peer, active, now, clock, dependencies);
            }
            if self.consumed_sequence.is_some_and(|last| sequence <= last) {
                diagnostics.identity = FloorIdentity::RejectedOrder; diagnostics.reason = FloorReason::RejectedOrder;
                self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); self.probe_healthy = 0;
                self.rtt.try_implicit(8, Observation::LegacyAbsent, clock, dependencies)?;
                self.last_latency_pressure = false; self.last_positive_suspension_pressure = false;
                return self.try_expire(report.peer, active, now, clock, dependencies);
            }
            self.consumed_sequence = Some(sequence);
        }
        self.capacity_growth_veto = false;
        let fresh = self.consume_floor_identity(report);
        diagnostics.identity = if fresh { FloorIdentity::Fresh } else if report.strict { FloorIdentity::RejectedTimestamp } else { FloorIdentity::RejectedOrder };
        if self.startup_active() && report.strict && !fresh {
            diagnostics.reason = FloorReason::RejectedTimestamp;
            return self.try_expire(report.peer, active, now, clock, dependencies);
        }
        self.observe_gap(report, None);
        let previous = self.current_recommendation(); let previous_tier = self.tier;
        let startup_was_active = self.startup_active(); let had_promotion = self.promotion.is_some();
        self.try_update_promotion(report.bandwidth, active, now, clock)?;
        let changed = self.try_update_network(report, bound, fresh, diagnostics, route_action, clock, dependencies)?;
        if self.last_latency_pressure { self.promotion = self.times.clear(TimeSlot::PromotionDeadline); }
        if self.last_latency_pressure || self.tier > previous_tier { self.disprove_startup(); }
        else if self.startup_active() && self.tier == Tier::Full { self.clear_startup(); }
        let startup_changed = startup_was_active != self.startup_active();
        let result = (active && (changed.is_some() || startup_changed || (had_promotion && self.current_recommendation() != previous)))
            .then(|| self.current_recommendation());
        // Swift defer records the fast baseline AFTER recommendation computation, including all
        // network-body early returns, but not earlier report-admission rejections.
        // A new clock error returns immediately before this baseline; the raw boundary
        // must discard the unpublished draft rather than invent a throwing Swift defer.
        self.record_capacity_baseline(report); Ok(result)
    }
    pub fn retain_fast_identity(&mut self, observed: Self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_retain_fast_identity(observed, clock, dependencies));
    }
    pub fn try_retain_fast_identity<C: TryClockFacts>(&mut self, observed: Self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        let Some(sequence) = observed.capacity_sequence else { return Ok(()); };
        if self.peer != observed.peer || self.probe_origin.is_none() || self.probe_origin != observed.probe_origin
            || sequence <= self.consumed_sequence.unwrap_or(0) || sequence <= self.capacity_sequence.unwrap_or(0) { return Ok(()); }
        self.capacity_sequence = Some(sequence); self.capacity_timestamp = observed.capacity_timestamp;
        self.rtt.try_copy_fence(observed.rtt, clock, dependencies)?;
        if observed.demand.faulted { self.demand.faulted = true; }
        if self.terminal_fault() { self.try_fault_recommendation(false, clock, dependencies)?; }
        Ok(())
    }
    pub fn update_capacity(&mut self, report: Report, clock: &mut impl ClockFacts, dependencies: Dependencies) -> CapacityEvaluation {
        infallible(self.try_update_capacity(report, clock, dependencies))
    }
    pub fn try_update_capacity<C: TryClockFacts>(&mut self, report: Report, clock: &mut C,
                                                dependencies: Dependencies) -> Result<CapacityEvaluation, C::Error> {
        let mut diagnostics = CapacityDiagnostics::new(self, report);
        let recommendation = self.try_capacity_body(report, &mut diagnostics, clock, dependencies)?;
        diagnostics.proposed_total = self.current_recommendation().maximum_total;
        Ok(CapacityEvaluation { recommendation, diagnostics })
    }
    fn capacity_body(&mut self, report: Report, diagnostics: &mut CapacityDiagnostics,
                     clock: &mut impl ClockFacts, dependencies: Dependencies) -> Option<Recommendation> {
        infallible(self.try_capacity_body(report, diagnostics, clock, dependencies))
    }
    fn try_capacity_body<C: TryClockFacts>(&mut self, report: Report, diagnostics: &mut CapacityDiagnostics,
                                         clock: &mut C, dependencies: Dependencies) -> Result<Option<Recommendation>, C::Error> {
        if self.peer != Some(report.peer) || !report.capture_active { diagnostics.reason = CapacityReason::Inactive; return Ok(None); }
        if let Some(expired) = self.try_expire(report.peer, true, report.observed_at, clock, dependencies)? {
            diagnostics.reason = CapacityReason::Expired; return Ok(Some(expired));
        }
        let (Some(origin), Some(ceiling), Some(sequence), Some(timestamp), Some(previous_timestamp)) =
            (self.probe_origin, self.probe_maximum, report.collection_sequence, report.native_timestamp, self.capacity_timestamp) else { return Ok(None); };
        if sequence <= self.consumed_sequence.unwrap_or(0) || sequence <= self.capacity_sequence.unwrap_or(0)
            || !timestamp.positive() || !(timestamp.value() > previous_timestamp.value()) { return Ok(None); }
        self.capacity_timestamp = Some(timestamp); self.capacity_sequence = Some(sequence);
        let baseline = self.capacity_sample;
        self.capacity_sample = Some(CapacitySample { packets: report.packets, delay: report.delay });
        let primary_healthy = self.rtt.health() == 1;
        let rtt = self.rtt.observe(report.current_rtt, report.observation, report.observed_at, true,
            !report.route.equals(self.route_present), dependencies);
        if self.terminal_fault() { return self.try_fault_recommendation(true, clock, dependencies); }
        let primary_lease = rtt.primary_lease_current;
        if !rtt.allows_upgrade {
            self.observe_gap(report, Some(primary_healthy)); diagnostics.reason = CapacityReason::RoundTripTime;
            if rtt.fresh_pressure { self.disprove_startup(); }
            diagnostics.record_queue(baseline.and_then(|v| v.packets), baseline.and_then(|v| v.delay), report.packets, report.delay);
            let queue = self.queue.capacity(baseline.and_then(|v| v.packets), baseline.and_then(|v| v.delay), report.packets, report.delay, report.observed_at, dependencies);
            let observable = !matches!(queue.observation, QueueObservation::UnavailableOrReset);
            if self.startup_active() {
                let negative = if report.route.incoming_present && self.route_present && !report.route.equal_to_retained { Some(CapacityReason::RouteChanged) }
                    else if queue.immediate { Some(CapacityReason::ImmediateQueue) }
                    else if report.bandwidth.is_some_and(|b| b.positive() && b.value() < self.collapse(origin)) { Some(CapacityReason::BandwidthCollapse) }
                    else { None };
                if let Some(reason) = negative { diagnostics.reason = reason; self.disprove_startup(); self.try_fail_probe(origin, clock, dependencies)?; return Ok(Some(self.current_recommendation())); }
            }
            if self.startup_active() && self.startup_sparse_deadline.is_some() && self.startup_sparse_deadline == self.probe_deadline
                && primary_lease && baseline.is_some() && observable && !rtt.fresh_pressure
                && report.observation.is_unavailable() && report.current_rtt.is_none() && report.bandwidth.is_none() && !report.route.incoming_present {
                diagnostics.reason = CapacityReason::MissingPrimaryEvidence; self.capacity_growth_veto = true; return Ok(None);
            }
            self.try_fail_probe(origin, clock, dependencies)?; return Ok(Some(self.current_recommendation()));
        }
        if !report.route.equals(self.route_present) {
            diagnostics.reason = CapacityReason::RouteChanged; self.disprove_startup();
            self.try_fail_probe(origin, clock, dependencies)?; return Ok(Some(self.current_recommendation()));
        }
        let awaits_ordinary = self.startup_active() && self.startup_sparse_deadline.is_some()
            && self.startup_sparse_deadline == self.probe_deadline && self.rtt.health() == 0
            && self.rtt.disposition() == 6 && rtt.validation_disposition == 2 && primary_lease;
        let Some(baseline) = baseline.filter(|_| primary_lease && (self.rtt.health() == 1 || awaits_ordinary)) else {
            diagnostics.reason = CapacityReason::MissingPrimaryEvidence; self.try_fail_probe(origin, clock, dependencies)?; return Ok(Some(self.current_recommendation()));
        };
        diagnostics.record_queue(baseline.packets, baseline.delay, report.packets, report.delay);
        let queue = self.queue.capacity(baseline.packets, baseline.delay, report.packets, report.delay, report.observed_at, dependencies);
        if queue.immediate { diagnostics.reason = CapacityReason::ImmediateQueue; self.disprove_startup(); self.try_fail_probe(origin, clock, dependencies)?; return Ok(Some(self.current_recommendation())); }
        let Some(bandwidth) = report.bandwidth.filter(|b| b.positive()) else { diagnostics.reason = CapacityReason::MissingBandwidth; self.capacity_growth_veto = true; return Ok(None); };
        let collapse = self.collapse(origin); diagnostics.collapse_threshold = bounded_integer(Some(collapse));
        if bandwidth.value() < collapse { diagnostics.reason = CapacityReason::BandwidthCollapse; self.disprove_startup(); self.try_fail_probe(origin, clock, dependencies)?; return Ok(Some(self.current_recommendation())); }
        if awaits_ordinary {
            if matches!(queue.observation, QueueObservation::UnavailableOrReset) {
                diagnostics.reason = CapacityReason::MissingPrimaryEvidence; self.try_fail_probe(origin, clock, dependencies)?; return Ok(Some(self.current_recommendation()));
            }
            diagnostics.reason = CapacityReason::MissingPrimaryEvidence; self.capacity_growth_veto = true; return Ok(None);
        }
        let Some(previous_bandwidth) = self.capacity_bandwidth_high else {
            diagnostics.reason = CapacityReason::MissingPrimaryEvidence; self.try_fail_probe(origin, clock, dependencies)?; return Ok(Some(self.current_recommendation()));
        };
        if !queue.allows_growth { diagnostics.reason = CapacityReason::QueueWithheld; self.capacity_growth_veto = true; return Ok(None); }
        if self.capacity_growth_veto { diagnostics.reason = CapacityReason::GrowthVetoed; return Ok(None); }
        if !(bandwidth.value() > previous_bandwidth.value()) { diagnostics.reason = CapacityReason::BandwidthNotAdvanced; return Ok(None); }
        self.capacity_bandwidth_high = Some(bandwidth);
        let next = self.try_bounded_ceiling(bandwidth, ceiling, clock)?;
        if next <= ceiling { diagnostics.reason = CapacityReason::AtCeiling; return Ok(None); }
        self.probe_maximum = Some(next); diagnostics.reason = CapacityReason::Increased; Ok(Some(self.current_recommendation()))
    }
    fn record_capacity_baseline(&mut self, report: Report) {
        let Some(timestamp) = report.native_timestamp.filter(|v| v.positive() && v.value() >= self.capacity_timestamp.map(|v| v.value()).unwrap_or(0.0)) else {
            self.capacity_sample = None; return;
        };
        self.capacity_timestamp = Some(timestamp);
        if self.startup_active() && self.startup_sparse_deadline.is_some() && self.startup_sparse_deadline == self.probe_deadline && report.bandwidth.is_none() {
            self.capacity_sample = Some(CapacitySample { packets: report.packets, delay: report.delay }); self.capacity_bandwidth_high = None; return;
        }
        let Some(bandwidth) = report.bandwidth.filter(|v| self.probe_origin.is_some() && v.positive()) else {
            self.capacity_sample = None; self.capacity_bandwidth_high = None; return;
        };
        self.capacity_bandwidth_high = Some(Scalar::new(self.capacity_bandwidth_high.map(|v| v.value()).unwrap_or(0.0).max(bandwidth.value())));
        self.capacity_sample = Some(CapacitySample { packets: report.packets, delay: report.delay });
    }
}

impl Policy {
    fn update_network(&mut self, report: Report, bound: bool, floor_fresh: bool,
                      diagnostics: &mut FloorDiagnostics, route_action: &mut RouteAction,
                      clock: &mut impl ClockFacts, dependencies: Dependencies) -> Option<Recommendation> {
        infallible(self.try_update_network(report, bound, floor_fresh, diagnostics, route_action, clock, dependencies))
    }
    fn try_update_network<C: TryClockFacts>(&mut self, report: Report, bound: bool, floor_fresh: bool,
                                          diagnostics: &mut FloorDiagnostics, route_action: &mut RouteAction,
                                          clock: &mut C, dependencies: Dependencies) -> Result<Option<Recommendation>, C::Error> {
        let active = report.capture_active; let now = report.observed_at;
        if report.route.incoming_present && (!self.route_present || !report.route.equal_to_retained) {
            let was_bound = self.route_present;
            let initial = !self.route_present && self.rtt.raw.watermark_present == 0 && self.rtt.permits_initial();
            self.route_present = true; *route_action = RouteAction::CopyIncoming;
            if was_bound { self.disprove_startup(); }
            self.try_revert_probe(clock, dependencies)?; self.try_reset_path(clock, dependencies)?;
            if initial { self.rtt.try_implicit(7, Observation::LegacyAbsent, clock, dependencies)?; }
        }
        if !active && !report.automatically_suspended {
            diagnostics.reason = FloorReason::InactiveVisibility; self.clear_startup();
            self.tier = Tier::from_ordinal(self.demand.initial).unwrap_or(Tier::AudioPriority);
            self.try_reset_path(clock, dependencies)?;
            let observation = if report.observation == Observation::LegacyAbsent { Observation::Unavailable } else { report.observation };
            self.rtt.try_implicit(6, observation, clock, dependencies)?; self.reset_legacy(); return Ok(None);
        }
        let observation = if report.strict && report.observation == Observation::LegacyAbsent { Observation::Unavailable } else { report.observation };
        let rtt = self.rtt.observe(report.current_rtt, observation, now, false, false, dependencies);
        if self.terminal_fault() { return self.try_fault_recommendation(active, clock, dependencies); }
        let rtt_inflated = rtt.fresh_pressure;
        let queue = self.queue.observe(report.packets, report.delay, rtt_inflated, now, dependencies);
        if self.queue.faulted { return Ok(None); }
        let average = match queue.observation { QueueObservation::Measured(delay) => Some(delay), _ => None };
        self.last_average_delay = average;
        let direct_healthy = average.map(|v| v.value() <= 0.020 && (rtt.legacy_missing || rtt.allows_upgrade)).unwrap_or(rtt.allows_upgrade);
        let strict_healthy = queue.allows_upgrade && rtt.allows_upgrade;
        let latency_pressure = rtt_inflated || queue.inflated;
        let latency_positive_healthy = !latency_pressure && direct_healthy;
        self.last_latency_pressure = latency_pressure;
        let floor_may_begin = self.observe_floor_witness(floor_fresh, queue.observation, rtt.allows_upgrade,
            report.bandwidth, active, now, diagnostics);
        let Some(bandwidth) = report.bandwidth.filter(|v| v.positive()) else {
            self.bandwidth_downgrades = 0; self.limited_upgrades = 0;
            if let Some(origin) = self.probe_origin {
                self.probe_healthy = 0;
                let expired = self.probe_deadline.map(|deadline| now >= deadline).unwrap_or(true);
                if latency_pressure {
                    self.try_fail_probe(origin, clock, dependencies)?; self.last_positive_suspension_pressure = true;
                    return Ok(active.then(|| self.current_recommendation()));
                } else if expired {
                    self.try_finish_probe(origin, clock, dependencies)?; self.last_positive_suspension_pressure = false;
                    return Ok(active.then(|| self.current_recommendation()));
                } else if self.probe_grace > 1 {
                    self.probe_grace -= 1; self.last_positive_suspension_pressure = false;
                    return Ok((active && bound).then(|| self.current_recommendation()));
                } else {
                    self.try_finish_probe(origin, clock, dependencies)?; self.last_positive_suspension_pressure = false;
                    return Ok(active.then(|| self.current_recommendation()));
                }
            }
            if !self.bandwidth_unavailable { self.healthy_upgrades = 0; }
            self.bandwidth_unavailable = true;
            if self.unavailable_samples < i64::MAX { self.unavailable_samples += 1; }
            self.last_positive_suspension_pressure = latency_pressure || self.below_reserve_disproved;
            if latency_pressure {
                self.healthy_upgrades = 0;
                let Some(lower) = self.tier.lower() else { return Ok((active && bound).then(|| self.current_recommendation())); };
                self.tier = lower; self.try_reset_queue_for_tier(clock, dependencies)?;
                return Ok(active.then(|| self.current_recommendation()));
            }
            if self.consume_cooldown(active) {
                self.healthy_upgrades = 0; return Ok((active && bound).then(|| self.current_recommendation()));
            }
            if self.startup_active() {
                self.healthy_upgrades = 0; return Ok((active && bound).then(|| self.current_recommendation()));
            }
            let upgrade = self.tier.higher();
            if !active || upgrade.is_none() || self.required(upgrade.unwrap_or(self.tier)) > self.configured_cap as f64
                || !queue.allows_upgrade || !rtt.allows_upgrade {
                self.healthy_upgrades = 0; return Ok((active && bound).then(|| self.current_recommendation()));
            }
            self.healthy_upgrades = clock.try_arithmetic(self.healthy_upgrades.checked_add(1))?;
            if self.healthy_upgrades < 2 { return Ok((active && bound).then(|| self.current_recommendation())); }
            self.tier = upgrade.unwrap_or(self.tier); self.try_reset_queue_for_tier(clock, dependencies)?;
            self.healthy_upgrades = 0; return Ok(Some(self.current_recommendation()));
        };
        if self.bandwidth_unavailable { self.healthy_upgrades = 0; }
        self.bandwidth_unavailable = false; self.unavailable_samples = 0;
        let effective = if bandwidth.value() >= self.configured_cap as f64 * 0.95 {
            Scalar::new(self.configured_cap as f64)
        } else { bandwidth };
        let Some((sustainable_ordinal, qualified_ordinal)) = self.demand.selection(self.tier as u8, effective, dependencies) else {
            return self.try_fault_recommendation(active, clock, dependencies);
        };
        let sustainable = Tier::from_ordinal(sustainable_ordinal).unwrap_or(Tier::AudioPriority);
        let qualified = qualified_ordinal.and_then(Tier::from_ordinal);
        let required_floor = self.required(Tier::AudioPriority);
        if effective.value() >= required_floor { self.below_reserve_disproved = false; self.resume_restoration = None; }
        let may_be_limited = self.estimator_limited(effective);
        if latency_pressure {
            self.positive_bootstrap = 1; self.limited_upgrades = 0;
        } else if self.positive_bootstrap < 1 {
            if qualified.is_some() { self.positive_bootstrap = 1; }
            else if may_be_limited {
                self.positive_bootstrap += 1; self.limited_upgrades = 0; self.last_positive_suspension_pressure = false;
                return Ok((active && bound).then(|| self.current_recommendation()));
            } else { self.positive_bootstrap = 1; }
        }
        if let Some(origin) = self.probe_origin {
            let probe_qualified = (sustainable < origin).then_some(sustainable);
            let collapsed = effective.value() < self.collapse(origin);
            let expired = self.probe_deadline.map(|deadline| now >= deadline).unwrap_or(true);
            if latency_pressure || collapsed {
                if collapsed && effective.value() < required_floor { self.below_reserve_disproved = true; }
                self.try_fail_probe(origin, clock, dependencies)?;
                if sustainable > origin { self.tier = sustainable; self.try_reset_queue_for_tier(clock, dependencies)?; }
                self.last_positive_suspension_pressure = latency_pressure || effective.value() < required_floor;
                return Ok(active.then(|| self.current_recommendation()));
            } else if queue.sample_inflated && !queue.inflated && !rtt_inflated {
                self.limited_upgrades = 0; self.probe_healthy = 0; self.last_positive_suspension_pressure = false;
                if expired {
                    if self.probe_best.is_none() && effective.value() < required_floor { self.below_reserve_disproved = true; }
                    self.try_finish_probe(origin, clock, dependencies)?; return Ok(active.then(|| self.current_recommendation()));
                }
                return Ok((active && bound).then(|| self.current_recommendation()));
            }
            let mut intermediate_changed = false;
            let empty_preserves = !expired && self.rtt.uses_native() && floor_fresh && strict_healthy
                && queue.observation == QueueObservation::NoNewPackets && self.probe_healthy > 0
                && self.probe_best.is_some_and(|best| sustainable <= best)
                && self.probe_qualification_at.is_some_and(|at| fresh_queue(at, now));
            if !expired && strict_healthy && (!self.rtt.uses_native() || (floor_fresh && average.is_some())) && probe_qualified.is_some() {
                if let Some(confirmed) = self.try_observe_qualification(probe_qualified.unwrap_or(origin), now, clock)? {
                    if confirmed < self.tier {
                        let high = self.capacity_bandwidth_high; self.tier = confirmed; self.probe_confirmed = Some(confirmed);
                        self.try_reset_queue_for_tier(clock, dependencies)?; self.capacity_bandwidth_high = high;
                        intermediate_changed = true;
                    }
                }
            } else if !empty_preserves { self.probe_healthy = 0; }
            if self.probe_healthy >= 2 {
                if let Some(tier) = self.probe_best {
                    self.try_complete_probe(tier, Some(bandwidth), Some(now), clock, dependencies)?;
                    self.last_positive_suspension_pressure = false; return Ok(active.then(|| self.current_recommendation()));
                }
            }
            if !expired && self.probe_grace > 1 && strict_healthy {
                if let Some(ceiling) = self.probe_maximum {
                    let next = self.try_bounded_ceiling(effective, ceiling, clock)?;
                    if next > ceiling {
                        self.probe_maximum = Some(next); self.probe_grace -= 1; self.limited_upgrades = 0;
                        self.last_positive_suspension_pressure = false; return Ok(active.then(|| self.current_recommendation()));
                    }
                }
            }
            if self.probe_grace > 0 { self.probe_grace -= 1; }
            self.limited_upgrades = 0; self.last_positive_suspension_pressure = false;
            if expired || self.probe_grace == 0 {
                if self.probe_best.is_none() && effective.value() < required_floor { self.below_reserve_disproved = true; }
                self.try_finish_probe(origin, clock, dependencies)?; return Ok(active.then(|| self.current_recommendation()));
            }
            return Ok((active && (bound || intermediate_changed)).then(|| self.current_recommendation()));
        }
        if qualified.is_some() && direct_healthy && !latency_pressure { self.reset_backoff(); }
        if floor_may_begin && self.try_begin_probe(Tier::AudioPriority, effective, now, clock)? {
            diagnostics.reason = FloorReason::Admitted; self.floor_attempt_consumed = true; self.floor_probe_cancelled = false;
            self.floor_seed = Some(effective); self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); self.last_positive_suspension_pressure = false;
            return Ok(Some(self.current_recommendation()));
        }
        let floor_feasible = self.tier == Tier::AudioPriority && self.tier.higher().is_some_and(|tier| self.required(tier) <= self.configured_cap as f64);
        let limited_can_hold = effective.value() >= required_floor || (floor_feasible && !self.below_reserve_disproved);
        let limited_hold = !latency_pressure && active && qualified.is_none() && may_be_limited && limited_can_hold;
        if limited_hold {
            self.bandwidth_downgrades = 0;
            if self.tier.higher().is_none() {
                self.limited_upgrades = 0; self.last_positive_suspension_pressure = false;
                return Ok((active && bound).then(|| self.current_recommendation()));
            }
            if self.consume_cooldown(active) {
                self.limited_upgrades = 0; self.last_positive_suspension_pressure = false;
                return Ok((active && bound).then(|| self.current_recommendation()));
            }
            if !strict_healthy {
                self.limited_upgrades = 0; self.last_positive_suspension_pressure = false;
                return Ok((active && bound).then(|| self.current_recommendation()));
            }
            self.limited_upgrades = clock.try_arithmetic(self.limited_upgrades.checked_add(1))?;
            if self.limited_upgrades >= 1 {
                self.limited_upgrades = 0;
                if self.try_begin_probe(self.tier, effective, now, clock)? {
                    self.last_positive_suspension_pressure = false; return Ok(active.then(|| self.current_recommendation()));
                }
            }
            self.last_positive_suspension_pressure = false; return Ok((active && bound).then(|| self.current_recommendation()));
        } else { self.limited_upgrades = 0; }
        if queue.sample_inflated && !queue.inflated && !rtt_inflated && sustainable <= self.tier {
            self.healthy_upgrades = 0; self.bandwidth_downgrades = 0; self.last_positive_suspension_pressure = false;
            return Ok((active && bound).then(|| self.current_recommendation()));
        }
        self.last_positive_suspension_pressure = latency_pressure || effective.value() < required_floor;
        let mut target = sustainable;
        if queue.inflated && !rtt_inflated {
            if let Some(lower) = self.tier.lower() { if lower > target { target = lower; } }
        } else if latency_pressure {
            if let Some(lower) = self.tier.lower() { if lower > target { target = lower; } }
        }
        if target > self.tier {
            self.healthy_upgrades = 0;
            if latency_positive_healthy {
                if self.bandwidth_downgrades < i64::MAX { self.bandwidth_downgrades += 1; }
                if self.bandwidth_downgrades < 2 { return Ok((active && bound).then(|| self.current_recommendation())); }
            }
            self.bandwidth_downgrades = 0; self.tier = target; self.try_reset_queue_for_tier(clock, dependencies)?;
            return Ok(active.then(|| self.current_recommendation()));
        }
        self.bandwidth_downgrades = 0;
        if target >= self.tier || qualified.is_none() {
            self.healthy_upgrades = 0; return Ok((active && bound).then(|| self.current_recommendation()));
        }
        let highest = qualified.unwrap_or(self.tier);
        let upgrade = if active { highest } else { self.tier.higher().unwrap_or(highest) };
        if latency_pressure || !direct_healthy {
            self.healthy_upgrades = 0; return Ok((active && bound).then(|| self.current_recommendation()));
        }
        self.healthy_upgrades = clock.try_arithmetic(self.healthy_upgrades.checked_add(1))?;
        if self.healthy_upgrades < if active { 2 } else { 8 } { return Ok((active && bound).then(|| self.current_recommendation())); }
        self.tier = upgrade; self.try_reset_queue_for_tier(clock, dependencies)?;
        self.healthy_upgrades = 0; self.bandwidth_downgrades = 0; Ok(active.then(|| self.current_recommendation()))
    }
    pub fn expire(&mut self, generation: u64, active: bool, now: RelativeTime,
                  clock: &mut impl ClockFacts, dependencies: Dependencies) -> Option<Recommendation> {
        infallible(self.try_expire(generation, active, now, clock, dependencies))
    }
    pub fn try_expire<C: TryClockFacts>(&mut self, generation: u64, active: bool, now: RelativeTime,
                                       clock: &mut C, dependencies: Dependencies) -> Result<Option<Recommendation>, C::Error> {
        if self.peer != Some(generation) { return Ok(None); }
        if self.terminal_fault() { return self.try_fault_recommendation(active, clock, dependencies); }
        self.rtt.age(now, dependencies);
        if self.terminal_fault() { return self.try_fault_recommendation(active, clock, dependencies); }
        if !active { return Ok(None); }
        let previous = self.current_recommendation();
        if self.promotion.is_some_and(|p| now >= p.deadline) { self.promotion = self.times.clear(TimeSlot::PromotionDeadline); }
        if let (Some(origin), Some(deadline)) = (self.probe_origin, self.probe_deadline) {
            if now >= deadline { self.try_finish_probe(origin, clock, dependencies)?; }
        }
        if self.startup_active() && self.tier == Tier::Full { self.clear_startup(); }
        Ok((self.current_recommendation() != previous).then(|| self.current_recommendation()))
    }
    pub fn suspension_decision(&mut self, active: bool, suspended: bool,
                               clock: &mut impl ClockFacts, dependencies: Dependencies) -> Option<SuspensionDecision> {
        infallible(self.try_suspension_decision(active, suspended, clock, dependencies))
    }
    pub fn try_suspension_decision<C: TryClockFacts>(&mut self, _active: bool, suspended: bool,
                                                   clock: &mut C, dependencies: Dependencies) -> Result<Option<SuspensionDecision>, C::Error> {
        if self.terminal_fault() { return Ok(None); }
        if suspended {
            self.suspension_pressure = 0;
            if self.maximum_resume < 64 { self.maximum_resume += 1; }
            if self.tier != Tier::AudioPriority {
                self.stable_resume = 0; self.maximum_resume = 0; return Ok(Some(SuspensionDecision::Resume));
            }
            if self.maximum_resume >= 64 {
                self.stable_resume = 0; self.maximum_resume = 0; return Ok(Some(SuspensionDecision::Resume));
            }
            // Swift && short-circuits the mutating published lease query.
            let native_stable = self.rtt.health() == 1 && self.rtt.try_published_lease(clock, dependencies)?;
            if self.terminal_fault() { self.try_fault_recommendation(false, clock, dependencies)?; return Ok(None); }
            if self.last_latency_pressure || (self.rtt.uses_native() && !native_stable) { self.stable_resume = 0; return Ok(None); }
            if self.stable_resume < 16 { self.stable_resume += 1; }
            if self.stable_resume < 16 { return Ok(None); }
            self.stable_resume = 0; return Ok(Some(SuspensionDecision::Resume));
        }
        self.stable_resume = 0; self.maximum_resume = 0; self.suspension_pressure = 0; Ok(None)
    }
    pub fn resume_began(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_resume_began(clock, dependencies));
    }
    pub fn try_resume_began<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.try_end_show(clock, dependencies)?; self.promotion = self.times.clear(TimeSlot::PromotionDeadline);
        if self.resume_restoration.is_some() { return Ok(()); }
        self.resume_restoration = Some(Restoration { disproved: self.below_reserve_disproved,
            cooldown: self.probe_cooldown, failures: self.probe_failures });
        self.below_reserve_disproved = false; self.limited_upgrades = 0; self.reset_backoff();
        Ok(())
    }
    pub fn resume_succeeded(&mut self) { self.promotion = self.times.clear(TimeSlot::PromotionDeadline); self.resume_restoration = None; }
    pub fn resume_failed(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_resume_failed(clock, dependencies));
    }
    pub fn try_resume_failed<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness);
        if self.floor_probe_active() { self.floor_probe_cancelled = true; }
        self.floor_seed = None;
        if let Some(restoration) = self.resume_restoration {
            self.below_reserve_disproved = restoration.disproved; self.probe_cooldown = restoration.cooldown; self.probe_failures = restoration.failures;
        }
        self.resume_restoration = None; self.tier = Tier::AudioPriority; self.probe_confirmed = None; self.probe_qualification_at = self.times.clear(TimeSlot::ProbeQualification);
        self.try_reset_queue_for_tier(clock, dependencies)?; self.healthy_upgrades = 0; self.bandwidth_downgrades = 0;
        self.limited_upgrades = 0; self.probe_healthy = 0; self.probe_grace = 0; self.probe_deadline = self.times.clear(TimeSlot::ProbeDeadline);
        self.probe_origin = None; self.probe_best = None; self.probe_maximum = None; self.reset_legacy();
        Ok(())
    }
    pub fn reset_inactive(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_reset_inactive(clock, dependencies));
    }
    pub fn try_reset_inactive<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.clear_startup(); self.tier = Tier::from_ordinal(self.demand.initial).unwrap_or(Tier::AudioPriority);
        self.try_reset_path(clock, dependencies)?; self.reset_legacy();
        Ok(())
    }
    fn consume_floor_identity(&mut self, report: Report) -> bool {
        let (Some(sequence), Some(timestamp)) = (report.collection_sequence, report.native_timestamp) else { self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); return false; };
        let previous = self.floor_regular_timestamp.map(|v| v.value()).unwrap_or(0.0)
            .max(self.capacity_timestamp.map(|v| v.value()).unwrap_or(0.0));
        if !report.strict || sequence <= self.floor_regular_sequence.unwrap_or(0) || !timestamp.positive() || !(timestamp.value() > previous) {
            self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); return false;
        }
        self.floor_regular_sequence = Some(sequence); self.floor_regular_timestamp = Some(timestamp); true
    }
    fn observe_floor_witness(&mut self, fresh: bool, queue: QueueObservation, rtt_upgrade: bool,
                             bandwidth: Option<Scalar>, active: bool, now: RelativeTime,
                             diagnostics: &mut FloorDiagnostics) -> bool {
        diagnostics.rtt_disposition = Some(self.rtt.disposition()); diagnostics.rtt_allows_upgrade = Some(rtt_upgrade);
        diagnostics.queue_kind = match queue { QueueObservation::Measured(delay) => {
            diagnostics.queue_microseconds = bounded_microseconds(Some(delay)); QueueKind::Measured },
            QueueObservation::NoNewPackets => QueueKind::NoNewPackets, QueueObservation::UnavailableOrReset => QueueKind::UnavailableOrReset };
        let rejection = if !fresh { Some(if diagnostics.identity == FloorIdentity::RejectedOrder { FloorReason::RejectedOrder } else { FloorReason::RejectedTimestamp }) }
            else if !active || !self.floor_active { Some(FloorReason::InactiveVisibility) }
            else if self.floor_attempt_consumed { Some(FloorReason::Consumed) }
            else if self.below_reserve_disproved { Some(FloorReason::Disproved) }
            else if self.tier != Tier::AudioPriority { Some(FloorReason::NotFloor) }
            else if self.probe_origin.is_some() { Some(FloorReason::ExistingProbe) }
            else if !self.rtt.uses_native() || self.rtt.health() != 1 || !rtt_upgrade { Some(FloorReason::RttBlocked) }
            else { None };
        if let Some(reason) = rejection { diagnostics.reason = reason; self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); return false; }
        let Some(bandwidth) = bandwidth.filter(|b| b.positive()) else { diagnostics.reason = FloorReason::InvalidBandwidth; self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); return false; };
        if self.estimator_limited(bandwidth) || !(bandwidth.value() * 2.0 > self.current_recommendation().maximum_total as f64) {
            diagnostics.reason = if self.estimator_limited(bandwidth) { FloorReason::OrdinaryProbeEligible } else { FloorReason::NoHeadroom };
            self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); return false;
        }
        if self.floor_first_witness.is_some_and(|first| !fresh_queue(first.observed_at, now)) { self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); }
        if self.floor_first_witness.is_some_and(|first| bandwidth.value() < first.bandwidth.value()) {
            diagnostics.reason = FloorReason::BandwidthFalling; self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); return false;
        }
        match queue {
            QueueObservation::Measured(delay) if delay.value() <= 0.020 => {}
            QueueObservation::NoNewPackets => { diagnostics.reason = FloorReason::NoNewPackets; return false; }
            _ => { diagnostics.reason = FloorReason::QueueBlocked; self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); return false; }
        }
        if self.probe_cooldown > 0 {
            diagnostics.reason = FloorReason::Cooldown; self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness);
            if self.floor_cooldown_at.map(|at| now - at >= HALF_SECOND).unwrap_or(true) {
                self.floor_cooldown_at = self.times.set(TimeSlot::FloorCooldown, now, Some(Origin::explicit(ExplicitTime::PolicyObservedAt))); self.consume_cooldown(true);
            }
            return false;
        }
        let Some(first) = self.floor_first_witness else {
            diagnostics.reason = FloorReason::FirstWitness; self.floor_first_witness = self.times.set(TimeSlot::FloorWitness, FloorWitness { observed_at: now, bandwidth }, Some(Origin::explicit(ExplicitTime::PolicyObservedAt))); return false;
        };
        if now - first.observed_at < HALF_SECOND { diagnostics.reason = FloorReason::TooEarly; return false; }
        diagnostics.reason = FloorReason::Qualified; true
    }
    fn collapse(self, origin: Tier) -> f64 {
        let confirmed = self.probe_confirmed.map(|tier| self.required(tier)).unwrap_or(0.0);
        if origin == Tier::AudioPriority {
            if let Some(seed) = self.floor_seed { return confirmed.max(seed.value() * 0.75); }
        }
        confirmed.max(self.required(Tier::AudioPriority)).max(self.demand.profile(origin as u8).map(|p| p.baseline_video).unwrap_or(0) as f64 * 0.75)
    }
    fn try_bounded_ceiling<C: TryClockFacts>(self, bandwidth: Scalar, current: i64, clock: &mut C) -> Result<i64, C::Error> {
        if !bandwidth.positive() { return Ok(current); }
        let doubled = (self.total_for(Tier::Full) as f64).min(bandwidth.value() * 2.0);
        Ok(current.max(clock.try_arithmetic(native_floor_integer(doubled))?))
    }
    fn estimator_limited(self, bandwidth: Scalar) -> bool { bandwidth.value() >= self.total_for(self.tier) as f64 * 0.80 }
    fn try_observe_qualification<C: TryClockFacts>(&mut self, tier: Tier, now: RelativeTime, clock: &mut C) -> Result<Option<Tier>, C::Error> {
        if !self.rtt.uses_native() {
            self.probe_qualification_at = self.times.clear(TimeSlot::ProbeQualification);
            self.probe_healthy = if self.probe_best == Some(tier) { clock.try_arithmetic(self.probe_healthy.checked_add(1))?.min(2) } else { 1 };
            self.probe_best = Some(tier); return Ok(None);
        }
        let mut preceding = None;
        if self.probe_healthy > 0 {
            if let Some(previous) = self.probe_qualification_at {
                let age = now - previous;
                if age >= 0 && age < HALF_SECOND {
                    if self.probe_best.is_some_and(|previous| tier > previous) {
                        self.probe_healthy = 0; self.probe_best = None; self.probe_qualification_at = self.times.clear(TimeSlot::ProbeQualification);
                    }
                    return Ok(None);
                }
                if age >= HALF_SECOND && age <= QUEUE_VALIDITY { preceding = self.probe_best; }
            }
        }
        self.probe_qualification_at = self.times.set(TimeSlot::ProbeQualification, now, Some(Origin::explicit(ExplicitTime::PolicyObservedAt))); self.probe_best = Some(tier);
        self.probe_healthy = if preceding == Some(tier) { 2 } else { 1 };
        Ok(preceding.map(|previous| if previous > tier { previous } else { tier }))
    }
    fn try_begin_probe<C: TryClockFacts>(&mut self, origin: Tier, bandwidth: Scalar, now: RelativeTime, clock: &mut C) -> Result<bool, C::Error> {
        let Some(next_tier) = origin.higher() else { return Ok(false); };
        if self.required(next_tier) > self.configured_cap as f64 { return Ok(false); }
        self.floor_seed = None; let current = self.current_recommendation().maximum_total;
        self.probe_origin = Some(origin); self.probe_confirmed = None; self.probe_qualification_at = self.times.clear(TimeSlot::ProbeQualification);
        self.probe_best = None; self.probe_healthy = 0;
        let cap = self.try_bounded_ceiling(bandwidth, current, clock)?;
        if cap <= current { self.probe_origin = None; return Ok(false); }
        self.probe_maximum = Some(cap); self.capacity_bandwidth_high = Some(bandwidth);
        self.capacity_growth_veto = false; self.promotion = self.times.clear(TimeSlot::PromotionDeadline); self.probe_grace = 7;
        self.probe_deadline = self.times.set(TimeSlot::ProbeDeadline, now + PROBE_GRACE, Origin::explicit(ExplicitTime::PolicyObservedAt).advanced(PROBE_GRACE)); self.limited_upgrades = 0; self.healthy_upgrades = 0; Ok(true)
    }
    fn complete_probe(&mut self, tier: Tier, bandwidth: Option<Scalar>, now: Option<RelativeTime>,
                      clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_complete_probe(tier, bandwidth, now, clock, dependencies));
    }
    fn try_complete_probe<C: TryClockFacts>(&mut self, tier: Tier, bandwidth: Option<Scalar>, now: Option<RelativeTime>,
                                           clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        let cap = self.probe_maximum; self.floor_seed = None; self.floor_probe_cancelled = false;
        self.tier = tier; self.try_reset_queue_for_tier(clock, dependencies)?;
        self.probe_origin = None; self.probe_best = None; self.probe_maximum = None; self.probe_confirmed = None;
        self.probe_qualification_at = self.times.clear(TimeSlot::ProbeQualification); self.probe_healthy = 0; self.probe_grace = 0; self.probe_deadline = self.times.clear(TimeSlot::ProbeDeadline);
        self.limited_upgrades = 0; self.below_reserve_disproved = false; self.resume_restoration = None; self.reset_backoff();
        if let (Some(bandwidth), Some(now), Some(cap)) = (bandwidth.filter(|b| b.positive()), now, cap) {
            let proven = clock.try_arithmetic(native_floor_integer((self.configured_cap as f64).min(cap as f64).min(bandwidth.value())))?;
            if proven > self.total_for(tier) { self.promotion = self.times.set(TimeSlot::PromotionDeadline, Promotion { tier, maximum_total: proven, deadline: now + CONTINUITY }, Origin::explicit(ExplicitTime::PolicyObservedAt).advanced(CONTINUITY)); }
        }
        Ok(())
    }
    fn try_update_promotion<C: TryClockFacts>(&mut self, bandwidth: Option<Scalar>, active: bool, now: RelativeTime, clock: &mut C) -> Result<(), C::Error> {
        let Some(mut promotion) = self.promotion else { return Ok(()); };
        let Some(bandwidth) = bandwidth.filter(|b| active && promotion.tier == self.tier && now < promotion.deadline && b.positive()) else { self.promotion = self.times.clear(TimeSlot::PromotionDeadline); return Ok(()); };
        let proven = clock.try_arithmetic(native_floor_integer((self.configured_cap as f64).min(bandwidth.value())))?;
        promotion.maximum_total = promotion.maximum_total.min(proven);
        self.promotion = if promotion.maximum_total > self.total_for(self.tier) { Some(promotion) }
            else { self.times.clear(TimeSlot::PromotionDeadline) };
        Ok(())
    }
    fn finish_probe(&mut self, origin: Tier, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_finish_probe(origin, clock, dependencies));
    }
    fn try_finish_probe<C: TryClockFacts>(&mut self, origin: Tier, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        if let Some(confirmed) = self.probe_confirmed { self.try_complete_probe(confirmed, None, None, clock, dependencies) }
        else if self.probe_healthy >= 2 && self.probe_best.is_some() { self.try_complete_probe(self.probe_best.unwrap_or(origin), None, None, clock, dependencies) }
        else { self.try_fail_probe(origin, clock, dependencies) }
    }
    fn revert_probe(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_revert_probe(clock, dependencies));
    }
    fn try_revert_probe<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        let Some(origin) = self.probe_origin else { return Ok(()); };
        if self.floor_probe_active() { self.floor_probe_cancelled = true; self.floor_seed = None; }
        self.tier = origin; self.try_reset_queue_for_tier(clock, dependencies)?; self.probe_origin = None;
        self.probe_confirmed = None; self.probe_qualification_at = self.times.clear(TimeSlot::ProbeQualification); self.probe_best = None;
        self.probe_maximum = None; self.probe_healthy = 0; self.probe_grace = 0; self.probe_deadline = self.times.clear(TimeSlot::ProbeDeadline);
        Ok(())
    }
    fn consume_cooldown(&mut self, active: bool) -> bool {
        if active { self.probe_cooldown = self.probe_cooldown.min(2); }
        if self.probe_cooldown <= 0 { return false; }
        self.probe_cooldown -= 1; true
    }
    fn fail_probe(&mut self, origin: Tier, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_fail_probe(origin, clock, dependencies));
    }
    fn try_fail_probe<C: TryClockFacts>(&mut self, origin: Tier, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        if self.floor_probe_active() { self.floor_probe_cancelled = true; self.floor_seed = None; self.below_reserve_disproved = true; }
        self.tier = origin; self.try_reset_queue_for_tier(clock, dependencies)?; self.probe_origin = None;
        self.probe_confirmed = None; self.probe_qualification_at = self.times.clear(TimeSlot::ProbeQualification); self.probe_best = None; self.probe_maximum = None;
        self.probe_healthy = 0; self.probe_grace = 0; self.probe_deadline = self.times.clear(TimeSlot::ProbeDeadline); self.limited_upgrades = 0;
        self.probe_failures = clock.try_arithmetic(self.probe_failures.checked_add(1))?.min(63);
        let exponent = (self.probe_failures - 1).min(3);
        // Swift's smart shift reverses direction for a negative exponent. The
        // positive operand 1 therefore becomes zero for every negative value.
        // Do not reinterpret an opaque signed failure count as a Rust shift.
        self.probe_cooldown = if exponent < 0 { 0 } else { (16 * (1i64 << exponent)).min(128) };
        Ok(())
    }
    fn reset_backoff(&mut self) { self.probe_cooldown = 0; self.probe_failures = 0; }
    fn reset_path(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_reset_path(clock, dependencies));
    }
    pub fn try_reset_path<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); self.probe_confirmed = None; self.probe_qualification_at = self.times.clear(TimeSlot::ProbeQualification);
        if self.floor_probe_active() { self.floor_probe_cancelled = true; }
        self.floor_seed = None; self.capacity_sample = None; self.capacity_bandwidth_high = None; self.promotion = self.times.clear(TimeSlot::PromotionDeadline);
        self.healthy_upgrades = 0; self.bandwidth_downgrades = 0; self.queue.try_reset(true, clock, dependencies)?;
        self.unavailable_samples = 0; self.positive_bootstrap = 0; self.limited_upgrades = 0; self.probe_healthy = 0;
        self.probe_grace = 0; self.probe_deadline = self.times.clear(TimeSlot::ProbeDeadline); self.probe_origin = None; self.probe_best = None; self.probe_maximum = None;
        self.below_reserve_disproved = false; self.resume_restoration = None; self.reset_backoff();
        self.rtt.try_implicit(4, Observation::LegacyAbsent, clock, dependencies)?; self.bandwidth_unavailable = false;
        self.last_latency_pressure = false; self.last_positive_suspension_pressure = false; self.last_average_delay = None;
        Ok(())
    }
    fn reset_queue_for_tier(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_reset_queue_for_tier(clock, dependencies));
    }
    fn try_reset_queue_for_tier<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.floor_first_witness = self.times.clear(TimeSlot::FloorWitness); self.capacity_sample = None; self.capacity_bandwidth_high = None;
        self.promotion = self.times.clear(TimeSlot::PromotionDeadline); self.queue.try_reset(false, clock, dependencies)?;
        Ok(())
    }
    fn reset_legacy(&mut self) { self.suspension_pressure = 0; self.stable_resume = 0; self.maximum_resume = 0; }
}

fn fresh_queue(at: RelativeTime, now: RelativeTime) -> bool { let age = now - at; age >= 0 && age <= QUEUE_VALIDITY }

/// Typed INTERNAL complete policy routing, deliberately no raw opcodes or exported ABI.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum PolicyEvent {
    Bind { peer: u64 }, ReserveShow { peer: u64, show: u64 }, ActivateShow { peer: u64, show: u64 },
    EndShow, RetainAttempt { observed: Policy }, RetainRttFault { observed: Policy },
    RetainFault { observed: Policy }, InvalidateRoute, RetainStartupTerminal { observed: Policy },
    RevokeForHide, ResetIncomplete, Regular(Report), RetainFastIdentity { observed: Policy },
    Capacity(Report), Expire { peer: u64, active: bool, now: RelativeTime },
    DecideLegacyResume { active: bool, suspended: bool }, ResumeBegan, ResumeSucceeded, ResumeFailed,
    ResetInactive, CurrentRecommendation, TierRecommendation(Tier), CurrentMinimum, NextDirectThreshold,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum PolicyValue { None, Bound(bool), Recommendation(Option<Recommendation>),
    Minimum(i64), Threshold(Option<i64>), LegacyDecision(Option<SuspensionDecision>),
    Regular(RegularEvaluation), Capacity(CapacityEvaluation) }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PolicyStep { pub value: PolicyValue, pub route_action: RouteAction }
impl Policy {
    pub fn step(&mut self, event: PolicyEvent, clock: &mut impl ClockFacts, dependencies: Dependencies) -> PolicyStep {
        let mut route_action = RouteAction::Retain;
        let value = match event {
            PolicyEvent::Bind { peer } => {
                let bound = self.bind(peer, clock, dependencies);
                if bound { route_action = RouteAction::Clear; } PolicyValue::Bound(bound)
            }
            PolicyEvent::ReserveShow { peer, show } => {
                if self.reserve_show(peer, show, clock, dependencies) { route_action = RouteAction::Clear; }
                PolicyValue::None
            }
            PolicyEvent::ActivateShow { peer, show } => { self.activate_show(peer, show); PolicyValue::None }
            PolicyEvent::EndShow => { self.end_show(clock, dependencies); PolicyValue::None }
            PolicyEvent::RetainAttempt { observed } => { self.retain_attempt(observed); PolicyValue::None }
            PolicyEvent::RetainRttFault { observed } => { self.retain_rtt_fault(observed, clock, dependencies); PolicyValue::None }
            PolicyEvent::RetainFault { observed } => { self.retain_fault(observed, clock, dependencies); PolicyValue::None }
            PolicyEvent::InvalidateRoute => { self.invalidate_route(clock, dependencies); route_action = RouteAction::Clear; PolicyValue::None }
            PolicyEvent::RetainStartupTerminal { observed } => { self.retain_startup_terminal(observed); PolicyValue::None }
            PolicyEvent::RevokeForHide => { self.revoke_for_hide(clock, dependencies); PolicyValue::None }
            PolicyEvent::ResetIncomplete => { self.reset_incomplete(clock, dependencies); PolicyValue::None }
            PolicyEvent::Regular(report) => {
                let evaluation = self.update(report, clock, dependencies); route_action = evaluation.route_action;
                PolicyValue::Regular(evaluation)
            }
            PolicyEvent::RetainFastIdentity { observed } => { self.retain_fast_identity(observed, clock, dependencies); PolicyValue::None }
            PolicyEvent::Capacity(report) => PolicyValue::Capacity(self.update_capacity(report, clock, dependencies)),
            PolicyEvent::Expire { peer, active, now } => PolicyValue::Recommendation(self.expire(peer, active, now, clock, dependencies)),
            PolicyEvent::DecideLegacyResume { active, suspended } => PolicyValue::LegacyDecision(self.suspension_decision(active, suspended, clock, dependencies)),
            PolicyEvent::ResumeBegan => { self.resume_began(clock, dependencies); PolicyValue::None }
            PolicyEvent::ResumeSucceeded => { self.resume_succeeded(); PolicyValue::None }
            PolicyEvent::ResumeFailed => { self.resume_failed(clock, dependencies); PolicyValue::None }
            PolicyEvent::ResetInactive => { self.reset_inactive(clock, dependencies); PolicyValue::None }
            PolicyEvent::CurrentRecommendation => PolicyValue::Recommendation(Some(self.current_recommendation())),
            PolicyEvent::TierRecommendation(tier) => PolicyValue::Recommendation(Some(self.recommendation(tier))),
            PolicyEvent::CurrentMinimum => PolicyValue::Minimum(self.current_minimum_sustainable()),
            PolicyEvent::NextDirectThreshold => PolicyValue::Threshold(self.next_direct_threshold()),
        };
        PolicyStep { value, route_action }
    }
}
