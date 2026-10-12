//! Independent native report-cut expectations, not physical actor/FFI proof.
//! Native anchors: FrozenWorldwideScreenVideoAdaptationPolicy.swift 632–804,
//! 829–1067, 1703–1794, 1884–1980, 2035–2192; FrozenPinned RTT 199–240.
//! The forwarding parity check is secondary (both wrappers share an impl).
//! Literal branch/read/deadline assertions below are the mutation-sensitive oracle.
use super::*;
use super::dependencies::{ATTO, MS};
use super::policy::{CapacitySample, FloorWitness, Promotion, RouteFacts};
use super::state_codec;

const Q: ClockSite = ClockSite::QueueReset;
const E: ClockSite = ClockSite::RttEvent;
const A: ClockSite = ClockSite::RttApply;
const L: ClockSite = ClockSite::PublishedLease;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct RejectedCut { ordinal: usize, site: ClockSite }

#[derive(Default)]
struct FallibleClock { calls: Vec<ClockSite>, fail: Option<usize>, last: Option<usize> }
fn cut_value(ordinal: usize) -> RelativeTime { (50 + ordinal as i128) * MS }
impl TryClockFacts for FallibleClock {
    type Error = RejectedCut;
    fn try_cut(&mut self, site: ClockSite) -> Result<RelativeTime, Self::Error> {
        let ordinal = self.calls.len();
        self.calls.push(site);
        if self.fail == Some(ordinal) { return Err(RejectedCut { ordinal, site }); }
        self.last = Some(ordinal);
        Ok(cut_value(ordinal))
    }
    fn last_try_time_source(&self) -> TimeSource {
        self.last.map(|ordinal| TimeSource::ActualRead { site: self.calls[ordinal], ordinal })
            .unwrap_or(TimeSource::Untracked)
    }
}
#[derive(Default)]
struct ForwardClock { calls: Vec<ClockSite> }
impl ClockFacts for ForwardClock {
    fn cut(&mut self, site: ClockSite) -> RelativeTime {
        let ordinal = self.calls.len(); self.calls.push(site); cut_value(ordinal)
    }
    fn last_time_source(&self) -> TimeSource {
        self.calls.len().checked_sub(1).map(|ordinal| TimeSource::ActualRead {
            site: self.calls[ordinal], ordinal }).unwrap_or(TimeSource::Untracked)
    }
}

// Constructors only seed immutable demand profiles. No report reducer produces
// an expected successor, transcript, deadline, diagnostic, or branch decision.
fn owner() -> Owner {
    let mut v = Owner::new(50_000_000, 60, Dependencies::default());
    v.revision = u64::MAX - 7; v.fast_statistics_available = true;
    v.evidence_lane = Some(EvidenceLane::OrdinaryFallback);
    v.last_evidence = Some(-7 * ATTO - 1); v.freshness.minimum = Some(31);
    v.applied = Some(Recommendation { tier: Tier::Balanced, maximum_video: 1_234_567,
        maximum_total: 2_345_678, fps: 29, scale: Scalar::new(1.5) });
    v.policy.peer = Some(1); v.policy.route_present = true;
    v.policy.consumed_sequence = Some(39);
    v.policy.floor_regular_sequence = Some(39);
    v.policy.floor_regular_timestamp = Some(Scalar::new(39_000_000.0));
    v.policy.capacity_timestamp = Some(Scalar::new(39_000_000.0));
    v.begin_time_assignment_frame(); v
}
fn report() -> Report {
    Report { peer: 1, capture_active: true, automatically_suspended: false,
        bandwidth: Some(Scalar::new(306_000.0)), current_rtt: Some(Scalar::new(0.004)),
        observation: Observation::Measurement { fingerprint: [0x6161_6161_6161_6161; 8],
            fingerprint_length: 64, total_bits: 0.016_f64.to_bits(), responses: 4 },
        collection_sequence: Some(40), strict: true,
        route: RouteFacts { incoming_present: true, equal_to_retained: true },
        packets: Some(40), delay: Some(Scalar::new(0.0)),
        native_timestamp: Some(Scalar::new(40_000_000.0)), observed_at: 500 * MS }
}
fn healthy(mut v: Owner) -> Owner {
    // Coherent literal primary native RTT lease. Positive fast samples must not
    // renew this Instant, which starts at zero independently of callback values.
    let r = &mut v.policy.rtt.raw;
    r.baseline_present = 1; r.baseline_bits = 0.004_f64.to_bits();
    r.disposition = 2; r.health = 1; r.uses_native = 1;
    r.permits_initial = 0; r.distinct_count = 3;
    r.last_measured_present = 1; r.last_measured_bits = 0.004_f64.to_bits();
    r.advancement_present = 1; r.age_present = 1;
    r.watermark_present = 1; r.fence_present = 1; r.fence_current_present = 1;
    r.watermark = crate::rtt_evidence::RawMeasurement {
        fingerprint_words: [0x6161_6161_6161_6161; 8], total_bits: 0.012_f64.to_bits(), responses: 3 };
    r.fence = r.watermark; r.fence_current_bits = 0.004_f64.to_bits();
    v.policy.rtt.last_advancement = Some(0);
    v.policy.queue.packets = Some(30); v.policy.queue.delay_bits = Some(0.0_f64.to_bits());
    v.policy.queue.low_observation = Some(0); v
}
fn probe(mut v: Owner) -> Owner {
    v.policy.tier = Tier::AudioPriority; v.policy.probe_origin = Some(Tier::AudioPriority);
    v.policy.probe_deadline = Some(3_500 * MS); v.policy.probe_maximum = Some(612_000);
    v.policy.probe_grace = 7; v.policy.capacity_bandwidth_high = Some(Scalar::new(306_000.0));
    v.policy.capacity_sample = Some(CapacitySample { packets: Some(30), delay: Some(Scalar::new(0.0)) });
    v
}
fn startup(mut v: Owner) -> Owner {
    v.policy.floor_show = Some(11); v.policy.floor_reserved = true; v.policy.floor_active = true;
    v.policy.startup_peer = Some(1); v.policy.startup_show = Some(11); v
}
fn wire(v: Owner) -> Vec<state_codec::Atom> {
    let encoded = state_codec::encode_owner(v, state_codec::RESULT).unwrap();
    assert_eq!(encoded.header.count, 179); assert_eq!(encoded.atoms.len(), 179);
    encoded.atoms
}
fn assert_whole(actual: Owner, expected: Owner) { assert_eq!(wire(actual), wire(expected)); }
fn assert_edits(actual: Owner, expected: Owner) {
    for slot in SLOTS { assert_eq!(actual.time_edit(slot), expected.time_edit(slot), "{slot:?}"); }
}

fn regular_parity(seed: Owner, input: Report, plan: &[ClockSite], deps: Dependencies) -> (Owner, RegularEvaluation) {
    let (mut actual, mut forwarding) = (seed, seed);
    let mut clock = FallibleClock::default(); let mut old_clock = ForwardClock::default();
    let result = actual.policy.try_update(input, &mut clock, deps).unwrap();
    let old = forwarding.policy.update(input, &mut old_clock, deps);
    assert_eq!(clock.calls, plan); assert_eq!(old_clock.calls, plan);
    assert_eq!(result, old); assert_whole(actual, forwarding); assert_edits(actual, forwarding);
    for ordinal in 0..plan.len() {
        let mut draft = seed; let mut failure = FallibleClock { fail: Some(ordinal), ..Default::default() };
        assert_eq!(draft.policy.try_update(input, &mut failure, deps),
            Err(RejectedCut { ordinal, site: plan[ordinal] }));
        assert_eq!(failure.calls, plan[..=ordinal], "regular error must end this exact prefix");
    }
    (actual, result)
}
fn capacity_parity(seed: Owner, input: Report, plan: &[ClockSite], deps: Dependencies) -> (Owner, CapacityEvaluation) {
    let (mut actual, mut forwarding) = (seed, seed);
    let mut clock = FallibleClock::default(); let mut old_clock = ForwardClock::default();
    let result = actual.policy.try_update_capacity(input, &mut clock, deps).unwrap();
    let old = forwarding.policy.update_capacity(input, &mut old_clock, deps);
    assert_eq!(clock.calls, plan); assert_eq!(old_clock.calls, plan);
    assert_eq!(result, old); assert_whole(actual, forwarding); assert_edits(actual, forwarding);
    for ordinal in 0..plan.len() {
        let mut draft = seed; let mut failure = FallibleClock { fail: Some(ordinal), ..Default::default() };
        assert_eq!(draft.policy.try_update_capacity(input, &mut failure, deps),
            Err(RejectedCut { ordinal, site: plan[ordinal] }));
        assert_eq!(failure.calls, plan[..=ordinal], "capacity error must end this exact prefix");
    }
    (actual, result)
}
fn expiry_parity(seed: Owner, peer: u64, active: bool, now: i128, plan: &[ClockSite]) -> (Owner, Option<Recommendation>) {
    let deps = Dependencies::default(); let (mut actual, mut forwarding) = (seed, seed);
    let mut clock = FallibleClock::default(); let mut old_clock = ForwardClock::default();
    let result = actual.policy.try_expire(peer, active, now, &mut clock, deps).unwrap();
    let old = forwarding.policy.expire(peer, active, now, &mut old_clock, deps);
    assert_eq!(clock.calls, plan); assert_eq!(old_clock.calls, plan);
    assert_eq!(result, old); assert_whole(actual, forwarding); assert_edits(actual, forwarding);
    for ordinal in 0..plan.len() {
        let mut draft = seed; let mut failure = FallibleClock { fail: Some(ordinal), ..Default::default() };
        assert_eq!(draft.policy.try_expire(peer, active, now, &mut failure, deps),
            Err(RejectedCut { ordinal, site: plan[ordinal] }));
        assert_eq!(failure.calls, plan[..=ordinal]);
    }
    (actual, result)
}
fn suspension_parity(seed: Owner, suspended: bool, plan: &[ClockSite], deps: Dependencies) -> (Owner, Option<SuspensionDecision>) {
    let (mut actual, mut forwarding) = (seed, seed);
    let mut clock = FallibleClock::default(); let mut old_clock = ForwardClock::default();
    let result = actual.policy.try_suspension_decision(false, suspended, &mut clock, deps).unwrap();
    let old = forwarding.policy.suspension_decision(false, suspended, &mut old_clock, deps);
    assert_eq!(clock.calls, plan); assert_eq!(old_clock.calls, plan);
    assert_eq!(result, old); assert_whole(actual, forwarding); assert_edits(actual, forwarding);
    for ordinal in 0..plan.len() {
        let mut draft = seed; let mut failure = FallibleClock { fail: Some(ordinal), ..Default::default() };
        assert_eq!(draft.policy.try_suspension_decision(false, suspended, &mut failure, deps),
            Err(RejectedCut { ordinal, site: plan[ordinal] }));
        assert_eq!(failure.calls, plan[..=ordinal]);
    }
    (actual, result)
}
fn explicit(delta: i128) -> TimeEdit {
    TimeEdit::Set(Origin { source: TimeSource::Explicit(ExplicitTime::PolicyObservedAt), delta })
}

#[test]
fn report_clock_changed_peer_and_hidden_route_keep_separate_default_reads() {
    let mut input = report(); input.peer = 2; input.strict = false;
    input.capture_active = false; input.automatically_suspended = false;
    input.route.incoming_present = false;
    let (actual, result) = regular_parity(owner(), input, &[Q,E,A,E,A,Q,E,A,E,A], Dependencies::default());
    assert_eq!(result.route_action, RouteAction::Clear);
    assert_eq!(result.diagnostics.reason, FloorReason::InactiveVisibility);
    assert_eq!(actual.policy.peer, Some(2)); assert!(!actual.policy.route_present);
    assert_eq!(actual.policy.capacity_timestamp, input.native_timestamp);
    // Bind completes before admission diagnostics; neither old Show nor old stamp leaks.
    assert_eq!(result.diagnostics.show_epoch, None);
    assert_eq!(result.diagnostics.previous_regular_sequence, None);
    assert_eq!(result.diagnostics.capacity_report_microseconds, None);
}

#[test]
fn report_clock_initial_route_then_hidden_reset_preserves_two_ordered_EA_pairs() {
    let mut seed = owner(); seed.policy.route_present = false;
    let mut input = report(); input.capture_active = false; input.strict = false;
    let (actual, result) = regular_parity(seed, input, &[Q,E,A,E,A,Q,E,A,E,A], Dependencies::default());
    assert_eq!(result.route_action, RouteAction::CopyIncoming);
    assert!(actual.policy.route_present); assert_eq!(result.diagnostics.reason, FloorReason::InactiveVisibility);
}

#[test]
fn report_clock_strict_missing_and_reordered_are_EA_but_capacity_fence_is_not() {
    for rejection in 0..3 {
        let mut seed = probe(owner()); seed.policy.probe_deadline = Some(500 * MS);
        seed.policy.probe_healthy = 1;
        seed.policy.floor_first_witness = Some(FloorWitness { observed_at: 0, bandwidth: Scalar::new(306_000.0) });
        let mut input = report();
        let plan: &[ClockSite] = if rejection == 1 { &[Q] } else { &[E,A,Q] };
        match rejection {
            0 => input.collection_sequence = None,
            1 => seed.policy.capacity_sequence = Some(40),
            _ => input.collection_sequence = Some(39),
        }
        let (actual, result) = regular_parity(seed, input, plan, Dependencies::default());
        assert_eq!(result.diagnostics.identity, FloorIdentity::RejectedOrder);
        assert_eq!(result.diagnostics.reason, FloorReason::RejectedOrder);
        assert_eq!(actual.policy.consumed_sequence, seed.policy.consumed_sequence);
        assert_eq!(actual.policy.capacity_timestamp, seed.policy.capacity_timestamp);
        assert_eq!(actual.policy.probe_deadline, None); assert_eq!(actual.policy.probe_origin, None);
        assert_eq!(actual.policy.probe_failures, 1); assert_eq!(actual.policy.probe_cooldown, 16);
    }
}

#[test]
fn report_clock_missing_order_rejection_local_mutation_precedes_first_cut_only() {
    let mut seed = owner(); seed.policy.probe_healthy = 6;
    seed.policy.last_latency_pressure = true; seed.policy.last_positive_suspension_pressure = true;
    seed.policy.floor_first_witness = Some(FloorWitness { observed_at: 0, bandwidth: Scalar::new(400_000.0) });
    let mut input = report(); input.collection_sequence = None;
    let mut expected = seed; expected.policy.floor_first_witness = None; expected.policy.probe_healthy = 0;
    // The literal initial RTT DTO has no advancement to age, so opcode10 is a
    // successful no-op before the missing-order guard. EA rejects before flags clear.
    let mut actual = seed; let mut clock = FallibleClock { fail: Some(0), ..Default::default() };
    assert_eq!(actual.policy.try_update(input, &mut clock, Dependencies::default()), Err(RejectedCut { ordinal: 0, site: E }));
    assert_eq!(clock.calls, [E]); assert_whole(actual, expected);
    assert_eq!(actual.policy.time_edit(TimeSlot::FloorWitness), TimeEdit::Clear);
    assert!(actual.policy.last_latency_pressure && actual.policy.last_positive_suspension_pressure);
}

#[test]
fn report_clock_startup_timestamp_guard_consumes_order_but_not_baseline_or_EA() {
    let seed = startup(owner()); let mut input = report();
    input.native_timestamp = Some(Scalar::new(39_000_000.0));
    let (actual, result) = regular_parity(seed, input, &[], Dependencies::default());
    assert_eq!(result.diagnostics.identity, FloorIdentity::RejectedTimestamp);
    assert_eq!(result.diagnostics.reason, FloorReason::RejectedTimestamp);
    let mut expected = seed; expected.policy.consumed_sequence = Some(40);
    expected.policy.floor_first_witness = None;
    assert_whole(actual, expected);
    assert_eq!(actual.policy.capacity_timestamp, Some(Scalar::new(39_000_000.0)));
}

#[test]
fn report_clock_route_probe_revert_then_path_reset_is_Q_Q_EA() {
    let seed = probe(healthy(owner())); let mut input = report();
    input.route.equal_to_retained = false; input.bandwidth = None;
    input.current_rtt = None; input.observation = Observation::Unavailable;
    let (actual, result) = regular_parity(seed, input, &[Q,Q,E,A], Dependencies::default());
    assert_eq!(result.route_action, RouteAction::CopyIncoming);
    assert_eq!(actual.policy.probe_origin, None); assert_eq!(actual.policy.probe_deadline, None);
    assert_eq!(actual.policy.probe_failures, 0); // Route reset is not a congestion failure.
    assert_eq!(actual.policy.capacity_timestamp, input.native_timestamp); // Native defer ran.
}

#[test]
fn report_clock_strict_legacy_absence_defaults_unavailable_not_legacy_authority() {
    for strict in [false, true] {
        let seed = owner(); let mut input = report();
        input.strict = strict; input.capture_active = false; input.automatically_suspended = true;
        input.bandwidth = None; input.current_rtt = None; input.observation = Observation::LegacyAbsent;
        input.packets = None; input.delay = None;
        let (actual, _) = regular_parity(seed, input, &[], Dependencies::default());
        assert_eq!(actual.policy.rtt.raw.uses_native, strict as u32);
        assert_eq!(actual.policy.rtt.raw.disposition, if strict { 6 } else { 0 });
        assert_eq!(actual.policy.capacity_timestamp, input.native_timestamp);
    }
}

#[test]
fn report_clock_regular_network_early_return_still_records_deferred_baseline() {
    let mut seed = healthy(owner()); seed.policy.queue.faulted = true;
    seed.policy.capacity_sample = Some(CapacitySample { packets: Some(21), delay: Some(Scalar::new(0.2)) });
    seed.policy.capacity_bandwidth_high = Some(Scalar::new(9_000_000.0));
    let input = report();
    let (actual, result) = regular_parity(seed, input, &[], Dependencies::default());
    assert_eq!(result.recommendation, None);
    assert_eq!(actual.policy.capacity_timestamp, input.native_timestamp);
    assert_eq!(actual.policy.capacity_sample, None); assert_eq!(actual.policy.capacity_bandwidth_high, None);
    assert_eq!(actual.policy.consumed_sequence, Some(40));
}

#[test]
fn report_clock_floor_probe_uses_observedAt_plus_3500ms_not_any_default_read() {
    let mut seed = healthy(owner()); seed.policy.tier = Tier::AudioPriority;
    seed.policy.floor_show = Some(11); seed.policy.floor_reserved = true; seed.policy.floor_active = true;
    seed.policy.positive_bootstrap = 1;
    seed.policy.floor_first_witness = Some(FloorWitness { observed_at: 0, bandwidth: Scalar::new(306_000.0) });
    let (actual, result) = regular_parity(seed, report(), &[], Dependencies::default());
    assert_eq!(result.diagnostics.reason, FloorReason::Admitted);
    assert_eq!(actual.policy.probe_origin, Some(Tier::AudioPriority));
    assert_eq!(actual.policy.probe_deadline, Some(4_000 * MS));
    assert_eq!(actual.policy.probe_maximum, Some(612_000));
    assert_eq!(actual.policy.time_edit(TimeSlot::ProbeDeadline), explicit(3_500 * MS));
    assert_eq!(actual.policy.time_edit(TimeSlot::RttAdvancement), explicit(0));
    assert_eq!(actual.policy.time_edit(TimeSlot::QueueLow), explicit(0));
    assert_eq!(actual.policy.floor_first_witness, None);
}

fn legacy_completing_probe() -> (Owner, Report) {
    let mut seed = probe(owner()); seed.policy.route_present = false;
    // Native strictUpgradeEvidenceIsHealthy1446–1450 requires an existing RTT
    // reference even on the legacy lane. The frozen promotion trace has already
    // completed its three 0.003s bootstrap samples before its final qualification.
    // A raw.initial first sample cannot supply that health, so seed its literal
    // established reference; do not evaluate a report to manufacture this seed.
    seed.policy.rtt.raw.baseline_present = 1;
    seed.policy.rtt.raw.baseline_bits = 0.003_f64.to_bits();
    seed.policy.probe_best = Some(Tier::Survival); seed.policy.probe_healthy = 1;
    seed.policy.probe_maximum = Some(1_200_000); seed.policy.positive_bootstrap = 1;
    seed.policy.queue.packets = Some(30); seed.policy.queue.delay_bits = Some(0.0_f64.to_bits());
    seed.policy.queue.low_observation = Some(0);
    let mut input = report(); input.strict = false; input.collection_sequence = None;
    input.native_timestamp = None; input.route.incoming_present = false;
    input.bandwidth = Some(Scalar::new(1_073_000.0));
    input.current_rtt = Some(Scalar::new(0.003)); input.observation = Observation::LegacyAbsent;
    input.delay = Some(Scalar::new(0.01));
    (seed, input)
}

#[test]
fn report_clock_completed_probe_Q_precedes_explicit_two_second_promotion() {
    let (seed, input) = legacy_completing_probe();
    let (actual, _) = regular_parity(seed, input, &[Q], Dependencies::default());
    assert_eq!(actual.policy.tier, Tier::Survival);
    assert_eq!(actual.policy.promotion, Some(Promotion { tier: Tier::Survival, maximum_total: 1_073_000, deadline: 2_500 * MS }));
    assert_eq!(actual.policy.time_edit(TimeSlot::PromotionDeadline), explicit(2 * ATTO));
    assert_eq!(actual.policy.probe_deadline, None); assert_eq!(actual.policy.probe_origin, None);
    let mut draft = seed; let mut fault = FallibleClock { fail: Some(0), ..Default::default() };
    assert_eq!(draft.policy.try_update(input, &mut fault, Dependencies::default()), Err(RejectedCut { ordinal: 0, site: Q }));
    // Native complete setter changes tier BEFORE queue reset, but removes probe
    // ownership/creates promotion AFTER it. New callback errors cannot leapfrog Q.
    assert_eq!(draft.policy.tier, Tier::Survival);
    assert_eq!(draft.policy.probe_origin, Some(Tier::AudioPriority));
    assert_eq!(draft.policy.probe_deadline, seed.policy.probe_deadline);
    assert_eq!(draft.policy.promotion, None);
    assert_eq!(draft.policy.capacity_timestamp, seed.policy.capacity_timestamp); // no invented throwing defer
}

#[test]
fn report_clock_capacity_expires_before_invalid_report_admission_and_never_rebinds() {
    let mut seed = probe(owner()); seed.policy.probe_deadline = Some(500 * MS);
    let mut input = report(); input.collection_sequence = None; input.native_timestamp = None;
    let (actual, result) = capacity_parity(seed, input, &[Q], Dependencies::default());
    assert_eq!(result.diagnostics.reason, CapacityReason::Expired); assert!(result.recommendation.is_some());
    assert_eq!(actual.policy.capacity_sequence, seed.policy.capacity_sequence);
    assert_eq!(actual.policy.capacity_timestamp, seed.policy.capacity_timestamp);
    input.peer = 2;
    let (actual, result) = capacity_parity(seed, input, &[], Dependencies::default());
    assert_eq!(result.diagnostics.reason, CapacityReason::Inactive); assert_whole(actual, seed);
    input.peer = 1; input.capture_active = false;
    let (actual, result) = capacity_parity(seed, input, &[], Dependencies::default());
    assert_eq!(result.diagnostics.reason, CapacityReason::Inactive); assert_whole(actual, seed);
}

#[test]
fn report_clock_capacity_positive_growth_and_missing_bandwidth_do_not_renew_health() {
    for missing in [false, true] {
        let seed = probe(healthy(owner())); let mut input = report();
        input.bandwidth = if missing { None } else { Some(Scalar::new(400_000.0)) };
        let (actual, result) = capacity_parity(seed, input, &[], Dependencies::default());
        assert_eq!(result.diagnostics.reason, if missing { CapacityReason::MissingBandwidth } else { CapacityReason::Increased });
        assert_eq!(actual.policy.probe_deadline, seed.policy.probe_deadline);
        assert_eq!(actual.policy.rtt.last_advancement, Some(0));
        assert_eq!(actual.policy.time_edit(TimeSlot::RttAdvancement), TimeEdit::Retain);
        assert_eq!(actual.policy.queue.low_observation, Some(0));
        assert_eq!(actual.policy.time_edit(TimeSlot::QueueLow), TimeEdit::Retain);
        assert_eq!(actual.policy.capacity_sequence, Some(40));
        if missing { assert!(actual.policy.capacity_growth_veto); }
        else { assert_eq!(actual.policy.probe_maximum, Some(800_000)); }
    }
}

#[test]
fn report_clock_capacity_route_negative_uses_Q_without_RTT_implicit_reads() {
    let seed = probe(healthy(owner())); let mut input = report(); input.route.equal_to_retained = false;
    let (actual, result) = capacity_parity(seed, input, &[Q], Dependencies::default());
    // The advanced fast tuple validates positively, then revokes primary health
    // for routeChanged. Its evidence still reaches the explicit route guard.
    assert_eq!(result.diagnostics.reason, CapacityReason::RouteChanged);
    assert_eq!(actual.policy.probe_origin, None); assert_eq!(actual.policy.probe_deadline, None);
    assert_eq!(actual.policy.probe_failures, 1); assert_eq!(actual.policy.capacity_sequence, Some(40));
}

#[test]
fn report_clock_expiry_exact_deadline_inactive_and_foreign_peer_order() {
    let seed = probe(owner());
    let (before, result) = expiry_parity(seed, 1, true, 3_500 * MS - 1, &[]);
    assert_eq!(result, None); assert_whole(before, seed);
    let (at, result) = expiry_parity(seed, 1, true, 3_500 * MS, &[Q]);
    assert!(result.is_some()); assert_eq!(at.policy.probe_deadline, None);
    assert_eq!(at.policy.probe_failures, 1);
    let (inactive, result) = expiry_parity(seed, 1, false, 3_500 * MS, &[]);
    assert_eq!(result, None); assert_whole(inactive, seed);
    let (foreign, result) = expiry_parity(seed, 2, true, 3_500 * MS, &[]);
    assert_eq!(result, None); assert_whole(foreign, seed);
}

#[test]
fn report_clock_promotion_shrinks_without_renewal_and_expires_at_two_seconds() {
    let mut seed = owner(); seed.policy.tier = Tier::Survival;
    seed.policy.promotion = Some(Promotion { tier: Tier::Survival, maximum_total: 1_073_000, deadline: 2_500 * MS });
    let mut shrinking = seed; shrinking.policy.route_present = false;
    shrinking.policy.queue.packets = Some(30);
    shrinking.policy.queue.delay_bits = Some(0.0_f64.to_bits());
    let mut input = report(); input.strict = false; input.collection_sequence = None;
    input.native_timestamp = None; input.route.incoming_present = false;
    input.bandwidth = Some(Scalar::new(980_000.0)); input.current_rtt = Some(Scalar::new(0.003));
    input.observation = Observation::LegacyAbsent; input.delay = Some(Scalar::new(0.5));
    let (shrunk, _) = regular_parity(shrinking, input, &[], Dependencies::default());
    // Frozen native updatePromotionCapacityContinuity2166–2192 changes only the
    // numeric cap at 500ms. Its existing observedAt+2s Instant must not renew.
    assert_eq!(shrunk.policy.promotion, Some(Promotion {
        tier: Tier::Survival, maximum_total: 980_000, deadline: 2_500 * MS }));
    assert_eq!(shrunk.policy.time_edit(TimeSlot::PromotionDeadline), TimeEdit::Retain);
    let (before, result) = expiry_parity(seed, 1, true, 2_500 * MS - 1, &[]);
    assert_eq!(result, None); assert_whole(before, seed);
    let (at, result) = expiry_parity(seed, 1, true, 2_500 * MS, &[]);
    assert!(result.is_some()); let mut expected = seed; expected.policy.promotion = None;
    assert_whole(at, expected); assert_eq!(at.policy.time_edit(TimeSlot::PromotionDeadline), TimeEdit::Clear);
}

#[test]
fn report_clock_suspension_short_circuits_PL_and_preserves_pre_cut_counter_order() {
    let mut seed = healthy(owner()); seed.policy.tier = Tier::AudioPriority;
    seed.policy.suspension_pressure = 9; seed.policy.stable_resume = 4; seed.policy.maximum_resume = 2;
    let (actual, result) = suspension_parity(seed, true, &[L], Dependencies::default());
    assert_eq!(result, None); let mut expected = seed;
    expected.policy.suspension_pressure = 0; expected.policy.maximum_resume = 3; expected.policy.stable_resume = 5;
    assert_whole(actual, expected);
    let mut draft = seed; let mut fault = FallibleClock { fail: Some(0), ..Default::default() };
    assert_eq!(draft.policy.try_suspension_decision(false, true, &mut fault, Dependencies::default()), Err(RejectedCut { ordinal: 0, site: L }));
    expected.policy.stable_resume = 4; assert_whole(draft, expected);
    for no_cut in 0..4 {
        let mut branch = seed;
        match no_cut {
            0 => branch.policy.tier = Tier::Survival,
            1 => branch.policy.maximum_resume = 63,
            2 => branch.policy.rtt.raw.health = 0,
            _ => branch.policy.rtt.raw.age_present = 0,
        }
        let (actual, result) = suspension_parity(branch, true, &[], Dependencies::default());
        assert_eq!(result, if no_cut < 2 { Some(SuspensionDecision::Resume) } else { None });
        assert_eq!(actual.policy.stable_resume, 0);
    }
}

fn invalid_published_rtt(before: crate::rtt_evidence::RawState, event: crate::rtt_evidence::RawEvent) -> crate::rtt_evidence::RawResult {
    let mut result = crate::rtt_evidence::transition(before, event);
    if event.opcode == 12 { result.primary_lease_current ^= 1; }
    result
}

#[test]
fn report_clock_suspension_PL_native_rejection_then_probe_revoke_Q() {
    let seed = probe(healthy(owner())); let deps = Dependencies { rtt: invalid_published_rtt, ..Dependencies::default() };
    let (actual, result) = suspension_parity(seed, true, &[L,Q], deps);
    assert_eq!(result, None); assert!(actual.policy.rtt.faulted);
    assert_eq!(actual.policy.probe_origin, None); assert_eq!(actual.policy.probe_deadline, None);
    assert_eq!(actual.policy.probe_failures, 0); // fault retirement is not congestion backoff
    let mut draft = seed; let mut fault = FallibleClock { fail: Some(1), ..Default::default() };
    assert_eq!(draft.policy.try_suspension_decision(false, true, &mut fault, deps), Err(RejectedCut { ordinal: 1, site: Q }));
    assert_eq!(fault.calls, [L,Q]); assert!(draft.policy.rtt.faulted);
    assert_eq!(draft.policy.probe_origin, seed.policy.probe_origin);
}
