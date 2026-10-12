//! PRIVATE, uncompiled policy trace draft. Original-native expectations, not candidate goldens.
//! Intended as a sibling test module of the complete private adaptation proposal.
//! No ABI/native adapter, route-body, actual-service, capture, or deployment claim.

use super::dependencies::{ClockFacts, ClockSite, Dependencies, Observation, RelativeTime, Scalar, MS};
use super::diagnostics::{CapacityReason, FloorIdentity, FloorReason};
use super::policy::{Policy, Report, Restoration, RouteFacts, Tier};

/// Pure mathematical fixture: every conditional implicit clock cut remains separate, but
/// these policy examples choose equal cuts at anchor zero. This is not a native clock ABI.
#[derive(Clone, Default)]
struct TraceClock { reads: Vec<ClockSite> }
impl ClockFacts for TraceClock {
    fn cut(&mut self, site: ClockSite) -> RelativeTime {
        self.reads.push(site);
        0
    }
}

#[derive(Clone)]
struct Trace {
    policy: Policy,
    clock: TraceClock,
    deps: Dependencies,
    sequence: u64,
    packets: u64,
}
impl Trace {
    fn new() -> Self {
        let deps = Dependencies::default();
        Self { policy: Policy::new(50_000_000, 60, deps), clock: TraceClock::default(),
            deps, sequence: 0, packets: 0 }
    }
    fn show() -> Self {
        let mut trace = Self::new();
        trace.policy.reserve_show(1, 1, &mut trace.clock, trace.deps);
        trace.policy.activate_show(1, 1);
        trace
    }
    fn report(&mut self, milliseconds: i128, bandwidth: f64) -> Report {
        self.sequence += 1;
        self.packets += 10;
        Report { peer: 1, capture_active: true, automatically_suspended: false,
            bandwidth: Some(Scalar::new(bandwidth)), current_rtt: Some(Scalar::new(0.004)),
            observation: Observation::Measurement { fingerprint: [0x6161_6161_6161_6161; 8],
                fingerprint_length: 64, total_bits: 0.004_f64.to_bits(), responses: 1 },
            collection_sequence: Some(self.sequence), strict: true,
            // The original fixture's route A is the same full native .direct route each time.
            // This fact is only for that trace, not evidence for a route adapter.
            route: RouteFacts { incoming_present: true, equal_to_retained: true },
            packets: Some(self.packets), delay: Some(Scalar::new(0.0)),
            native_timestamp: Some(Scalar::new(1_000_000.0 + self.sequence as f64 * 1_000_000.0)),
            observed_at: milliseconds * MS }
    }
    fn regular(&mut self, milliseconds: i128, bandwidth: f64) {
        let report = self.report(milliseconds, bandwidth);
        self.policy.update(report, &mut self.clock, self.deps);
    }
    fn first_witness() -> Self {
        let mut trace = Self::show();
        for milliseconds in [0, 500, 1_000] { trace.regular(milliseconds, 306_000.0); }
        visible_floor(&trace.policy, 486_001);
        assert!(!trace.policy.floor_attempt_consumed);
        trace
    }
    fn cold_trial() -> Self {
        let mut trace = Self::first_witness();
        trace.regular(1_500, 306_000.0);
        visible_floor(&trace.policy, 612_000);
        assert!(trace.policy.floor_probe_active());
        assert!(trace.policy.floor_attempt_consumed);
        assert_eq!(trace.policy.probe_deadline, Some(5_000 * MS));
        trace
    }
}

fn visible_floor(policy: &Policy, total: i64) {
    let recommendation = policy.current_recommendation();
    assert_eq!(recommendation.tier, Tier::AudioPriority);
    assert_eq!(recommendation.maximum_total, total);
    assert_eq!(recommendation.fps, 1);
    assert_eq!(recommendation.scale.value(), 12.0);
}

/// Complete current typed-state unchanged/assignment-set observation, not a full independent
/// Swift golden. Derived Debug includes the nested state and the Scalar u64 payloads, so NaN
/// non-reflexivity does not make an unchanged-state comparison vacuous. No policy equality
/// helper under test is used to certify these unchanged-state assertions.
fn bits_snapshot(policy: &Policy) -> String { format!("{policy:?}") }

#[test]
fn original_rejected_optional_identity_ages_without_floor_authority() {
    let seed = Trace::first_witness();
    for rejected in 0..6 {
        let mut trace = seed.clone();
        let before = bits_snapshot(&trace.policy);
        let mut report = trace.report(1_500, 306_000.0);
        match rejected {
            0 => report.collection_sequence = None,
            1 => report.collection_sequence = Some(3),
            2 => report.native_timestamp = None,
            3 => report.native_timestamp = Some(Scalar::new(3_000_000.0)),
            4 => report.native_timestamp = Some(Scalar(0x7ff8_0000_0000_0042)),
            _ => report.native_timestamp = Some(Scalar::new(-0.0)),
        }
        let result = trace.policy.update(report, &mut trace.clock, trace.deps);
        if rejected < 2 {
            assert_eq!(result.diagnostics.identity, FloorIdentity::RejectedOrder);
            assert_eq!(result.diagnostics.reason, FloorReason::RejectedOrder);
            assert_eq!(trace.policy.consumed_sequence, Some(3));
        } else {
            assert_eq!(result.diagnostics.identity, FloorIdentity::RejectedTimestamp);
            assert_eq!(trace.policy.consumed_sequence, Some(4));
        }
        assert!(!trace.policy.floor_attempt_consumed);
        assert!(!trace.policy.floor_probe_active());
        assert_eq!(trace.policy.tier, Tier::AudioPriority);
        assert_eq!(trace.policy.rtt.observation_age(), Some(1_500 * MS));
        assert_ne!(bits_snapshot(&trace.policy), before);
    }
}

#[test]
fn original_present_full_width_sequences_are_ordered_without_float_coercion() {
    let mut trace = Trace::new();
    trace.policy.reserve_show(u64::MAX, u64::MAX, &mut trace.clock, trace.deps);
    trace.policy.activate_show(u64::MAX, u64::MAX);
    // Each expected tombstone comes from native UInt64 admission/order, independently
    // of the subject. A final MAX alone would miss adjacent-value float coercion.
    for (sequence, expected_consumed) in [
        (1_u64 << 53, 1_u64 << 53),
        ((1_u64 << 53) + 1, (1_u64 << 53) + 1),
        (u64::MAX, u64::MAX), (u64::MAX, u64::MAX), (0, u64::MAX),
    ] {
        let mut report = trace.report(500, 306_000.0);
        report.peer = u64::MAX;
        report.collection_sequence = Some(sequence);
        report.packets = Some(sequence);
        report.observation = Observation::Measurement { fingerprint: [0x6161_6161_6161_6161; 8],
            fingerprint_length: 64, total_bits: 1.0_f64.to_bits(), responses: sequence };
        let result = trace.policy.update(report, &mut trace.clock, trace.deps);
        assert_eq!(trace.policy.consumed_sequence, Some(expected_consumed));
        if trace.sequence <= 3 {
            assert_eq!(result.diagnostics.identity, FloorIdentity::Fresh);
        } else {
            assert_eq!(result.diagnostics.identity, FloorIdentity::RejectedOrder);
            assert_eq!(result.diagnostics.reason, FloorReason::RejectedOrder);
        }
    }
    assert_eq!(trace.policy.consumed_sequence, Some(u64::MAX));
    trace.policy.invalidate_route(&mut trace.clock, trace.deps);
    assert_eq!(trace.policy.consumed_sequence, Some(u64::MAX));
    trace.policy.reset_incomplete(&mut trace.clock, trace.deps);
    assert_eq!(trace.policy.consumed_sequence, Some(u64::MAX));
    trace.policy.bind(u64::MAX - 1, &mut trace.clock, trace.deps);
    assert_eq!(trace.policy.consumed_sequence, None);
}

#[test]
fn original_missing_timestamp_and_legacy_absence_have_different_authority() {
    let mut startup = Trace::show();
    for milliseconds in [0, 500, 1_000] {
        let mut report = startup.report(milliseconds, 50_000_000.0);
        report.native_timestamp = None;
        startup.policy.update(report, &mut startup.clock, startup.deps);
        assert_eq!(startup.policy.tier, Tier::Survival);
        assert_eq!(startup.policy.rtt.baseline(), None);
        assert_eq!(startup.policy.rtt.disposition(), 6); // Original .unavailable.
        assert!(!startup.policy.floor_attempt_consumed);
    }
    let mut ordinary = Trace::new();
    for milliseconds in [0, 500] {
        let mut report = ordinary.report(milliseconds, 50_000_000.0);
        report.native_timestamp = None;
        ordinary.policy.update(report, &mut ordinary.clock, ordinary.deps);
    }
    assert_eq!(ordinary.policy.tier, Tier::Full);
    assert!(!ordinary.policy.floor_attempt_consumed);

    let mut legacy = Trace::new();
    for milliseconds in [0, 500, 1_000] {
        let mut report = legacy.report(milliseconds, 50_000_000.0);
        report.strict = false;
        report.observation = Observation::LegacyAbsent;
        report.current_rtt = None;
        report.native_timestamp = None;
        report.collection_sequence = None;
        legacy.policy.update(report, &mut legacy.clock, legacy.deps);
        assert_eq!(legacy.policy.rtt.disposition(), 0); // Original .legacy.
    }
    assert_eq!(legacy.policy.tier, Tier::Full);
    assert_eq!(legacy.policy.rtt.baseline(), None);
    assert!(!legacy.policy.floor_attempt_consumed);

    let mut strict = Trace::new();
    for milliseconds in [0, 500, 1_000] {
        let mut report = strict.report(milliseconds, 50_000_000.0);
        report.observation = Observation::LegacyAbsent;
        report.current_rtt = None;
        report.native_timestamp = None;
        strict.policy.update(report, &mut strict.clock, strict.deps);
    }
    assert_eq!(strict.policy.tier, Tier::Survival);
    assert_eq!(strict.policy.rtt.disposition(), 6);
}

#[test]
fn original_stale_regular_report_still_retires_expired_trial() {
    let mut trace = Trace::cold_trial();
    let mut report = trace.report(5_000, 50_000_000.0);
    report.collection_sequence = Some(4);
    let result = trace.policy.update(report, &mut trace.clock, trace.deps);
    assert_eq!(result.diagnostics.identity, FloorIdentity::RejectedOrder);
    assert_eq!(result.diagnostics.reason, FloorReason::RejectedOrder);
    assert_eq!(trace.policy.consumed_sequence, Some(4));
    assert_eq!(trace.policy.rtt.observation_age(), Some(5_000 * MS));
    assert!(!trace.policy.floor_probe_active());
    assert!(trace.policy.floor_attempt_consumed);
    assert_eq!(trace.policy.probe_deadline, None);
    assert_eq!(result.recommendation.map(|r| r.maximum_total), Some(486_001));
    visible_floor(&trace.policy, 486_001);
}

#[test]
fn original_wrong_peer_or_inactive_capacity_does_not_age_owner() {
    let seed = Trace::cold_trial();
    for wrong_peer in [false, true] {
        let mut trace = seed.clone();
        let before = bits_snapshot(&trace.policy);
        let reads = trace.clock.reads.len();
        let mut report = trace.report(20_000, 340_000.0);
        report.peer = if wrong_peer { 2 } else { 1 };
        report.capture_active = wrong_peer;
        let result = trace.policy.update_capacity(report, &mut trace.clock, trace.deps);
        assert_eq!(result.recommendation, None);
        assert_eq!(result.diagnostics.reason, CapacityReason::Inactive);
        assert_eq!(bits_snapshot(&trace.policy), before);
        assert_eq!(trace.clock.reads.len(), reads);
    }
}

#[test]
fn original_capacity_expiry_precedes_optional_report_admission_at_exact_deadline() {
    let seed = Trace::cold_trial();
    for (at, expires) in [(5_000 * MS - 1, false), (5_000 * MS, true)] {
        let mut trace = seed.clone();
        let mut report = trace.report(5_000, 340_000.0);
        report.observed_at = at;
        report.collection_sequence = None;
        report.native_timestamp = None;
        let result = trace.policy.update_capacity(report, &mut trace.clock, trace.deps);
        assert_eq!(trace.policy.consumed_sequence, Some(4));
        assert_eq!(trace.policy.capacity_sequence, None);
        assert_eq!(trace.policy.rtt.observation_age(), Some(at));
        assert!(trace.policy.floor_attempt_consumed);
        assert_eq!(trace.policy.floor_probe_active(), !expires);
        if expires {
            assert_eq!(result.diagnostics.reason, CapacityReason::Expired);
            assert_eq!(result.recommendation.map(|r| r.maximum_total), Some(486_001));
            assert_eq!(trace.policy.probe_deadline, None);
            assert_eq!(trace.policy.probe_origin, None);
            visible_floor(&trace.policy, 486_001);
        } else {
            assert_eq!(result.recommendation, None);
            assert_eq!(result.diagnostics.reason, CapacityReason::RejectedReport);
            assert_eq!(trace.policy.probe_deadline, Some(5_000 * MS));
            visible_floor(&trace.policy, 612_000);
        }
    }
}

#[test]
fn original_failed_positive_capacity_retains_only_identity_not_budget_or_health() {
    let mut trace = Trace::cold_trial();
    let before_recommendation = trace.policy.current_recommendation();
    assert_eq!(trace.policy.consumed_sequence, Some(4));
    assert_eq!(trace.policy.rtt.observation_age(), Some(1_500 * MS));
    let mut proposed = trace.clone();
    let report = proposed.report(1_700, 340_000.0);
    let result = proposed.policy.update_capacity(report, &mut proposed.clock, proposed.deps);
    assert!(result.recommendation.is_some()); // Frozen native trace's positive speculative apply.
    trace.policy.retain_fast_identity(proposed.policy, &mut trace.clock, trace.deps);
    assert_eq!(trace.policy.capacity_sequence, Some(5));
    assert_eq!(trace.policy.capacity_timestamp.map(|v| v.value()), Some(6_000_000.0));
    assert_eq!(trace.policy.current_recommendation(), before_recommendation);
    assert_eq!(trace.policy.probe_deadline, Some(5_000 * MS));
    assert_eq!(trace.policy.consumed_sequence, Some(4));
    assert_eq!(trace.policy.rtt.observation_age(), Some(1_500 * MS));
    let once = bits_snapshot(&trace.policy);
    trace.policy.retain_fast_identity(proposed.policy, &mut trace.clock, trace.deps);
    assert_eq!(bits_snapshot(&trace.policy), once);
}

#[test]
fn original_same_show_retention_copies_only_monotone_attempt_fences() {
    let mut trace = Trace::first_witness();
    let mut proposed = trace.clone();
    proposed.regular(1_500, 306_000.0);
    assert!(proposed.policy.floor_attempt_consumed);
    let mut expected = trace.policy;
    // Original native method has exactly these writes on this accepted branch.
    expected.floor_attempt_consumed = true;
    expected.floor_first_witness = None;
    expected.floor_regular_sequence = Some(4);
    expected.floor_regular_timestamp = Some(Scalar::new(5_000_000.0));
    trace.policy.retain_attempt(proposed.policy);
    assert_eq!(bits_snapshot(&trace.policy), bits_snapshot(&expected));
    visible_floor(&trace.policy, 486_001);
    assert_eq!(trace.policy.rtt.observation_age(), Some(1_000 * MS));
    assert!(!trace.policy.floor_probe_active());
    // The speculative clone alone produced sequence4. Advance the fixture counter
    // explicitly so the subject next admits 5/6M before retaining the older 4/5M.
    trace.sequence = 4;
    trace.regular(2_000, 306_000.0);
    assert_eq!(trace.policy.floor_regular_sequence, Some(5));
    assert_eq!(trace.policy.floor_regular_timestamp.map(|v| v.value()), Some(6_000_000.0));
    let monotone = bits_snapshot(&trace.policy);
    trace.policy.retain_attempt(proposed.policy);
    assert_eq!(bits_snapshot(&trace.policy), monotone);
    for successor_peer in [false, true] {
        let mut successor = trace.clone();
        if successor_peer { successor.policy.bind(2, &mut successor.clock, successor.deps); }
        else { successor.policy.reserve_show(1, 2, &mut successor.clock, successor.deps); }
        let before = bits_snapshot(&successor.policy);
        successor.policy.retain_attempt(proposed.policy);
        assert_eq!(bits_snapshot(&successor.policy), before);
        assert!(!successor.policy.floor_attempt_consumed);
    }
}

#[test]
fn original_present_resume_restoration_restores_and_success_discards_it() {
    let mut trace = Trace::cold_trial();
    trace.policy.expire(1, true, 5_000 * MS, &mut trace.clock, trace.deps);
    assert_eq!(trace.policy.probe_cooldown, 16);
    assert_eq!(trace.policy.probe_failures, 1);
    assert!(trace.policy.below_reserve_disproved);
    trace.policy.resume_began(&mut trace.clock, trace.deps);
    assert_eq!(trace.policy.resume_restoration, Some(Restoration { disproved: true, cooldown: 16, failures: 1 }));
    assert_eq!(trace.policy.probe_cooldown, 0);
    assert_eq!(trace.policy.probe_failures, 0);
    assert!(!trace.policy.below_reserve_disproved);
    trace.policy.resume_failed(&mut trace.clock, trace.deps);
    assert_eq!(trace.policy.resume_restoration, None);
    assert_eq!(trace.policy.probe_cooldown, 16);
    assert_eq!(trace.policy.probe_failures, 1);
    assert!(trace.policy.below_reserve_disproved);
    visible_floor(&trace.policy, 486_001);
    trace.policy.resume_began(&mut trace.clock, trace.deps);
    trace.policy.resume_succeeded();
    assert_eq!(trace.policy.resume_restoration, None);
    // A later failed callback with None cannot re-import the discarded predecessor.
    trace.policy.resume_failed(&mut trace.clock, trace.deps);
    assert_eq!(trace.policy.probe_cooldown, 0);
    assert_eq!(trace.policy.probe_failures, 0);
    assert!(!trace.policy.below_reserve_disproved);
    assert_eq!(trace.policy.probe_origin, None);
    assert_eq!(trace.policy.probe_deadline, None);
    visible_floor(&trace.policy, 486_001);
}

#[test]
fn original_optional_nan_equality_is_not_unchanged_bit_state_equality() {
    let mut trace = Trace::cold_trial();
    let mut report = trace.report(1_700, 340_000.0);
    report.delay = Some(Scalar(0x7ff8_0000_0000_0042));
    trace.policy.update_capacity(report, &mut trace.clock, trace.deps);
    let sample = trace.policy.capacity_sample.expect("native fast baseline retains optional raw delay");
    assert_eq!(sample.delay.map(|v| v.0), Some(0x7ff8_0000_0000_0042));
    assert!(!(trace.policy == trace.policy));
    assert!(!trace.policy.swift_equal(&trace.policy, true));
    assert!(!trace.policy.terminal_fault());
    let before = bits_snapshot(&trace.policy);
    let observed = trace.policy;
    trace.policy.retain_fault(observed, &mut trace.clock, trace.deps);
    assert_eq!(bits_snapshot(&trace.policy), before);
    assert!(!(trace.policy == observed));
    assert_eq!(Some(Scalar::new(-0.0)), Some(Scalar::new(0.0)));
    assert_ne!(Scalar::new(-0.0).0, Scalar::new(0.0).0);
}

#[test]
fn original_optional_promotion_shrinks_only_and_expires_at_exact_two_seconds() {
    let mut trace = Trace::new();
    let mut total_delay = 0.0;
    let mut legacy = |trace: &mut Trace, milliseconds: i128, bandwidth: f64, queue: f64| {
        let mut report = trace.report(milliseconds, bandwidth);
        total_delay += queue * 10.0;
        report.strict = false;
        report.collection_sequence = None;
        report.native_timestamp = None;
        report.route = RouteFacts { incoming_present: false, equal_to_retained: true };
        report.current_rtt = Some(Scalar::new(0.003));
        report.observation = Observation::LegacyAbsent;
        report.delay = Some(Scalar::new(total_delay));
        trace.policy.update(report, &mut trace.clock, trace.deps);
    };
    for (index, bandwidth) in [100_000.0, 400_000.0, 400_000.0, 688_500.0, 1_073_000.0].into_iter().enumerate() {
        legacy(&mut trace, index as i128 * 500, bandwidth, 0.001);
    }
    assert_eq!(trace.policy.tier, Tier::Survival);
    assert_eq!(trace.policy.current_recommendation().maximum_total, 1_073_000);
    assert_eq!(trace.policy.promotion.map(|p| p.deadline), Some(4_000 * MS));
    for (milliseconds, bandwidth, total) in [(2_500, 1_200_000.0, 1_073_000),
                                           (3_000, 980_000.0, 980_000),
                                           (3_500, 1_200_000.0, 980_000)] {
        legacy(&mut trace, milliseconds, bandwidth, 0.050);
        assert_eq!(trace.policy.current_recommendation().maximum_total, total);
        assert_eq!(trace.policy.promotion.map(|p| p.deadline), Some(4_000 * MS));
    }
    trace.policy.expire(1, true, 4_000 * MS - 1, &mut trace.clock, trace.deps);
    assert_eq!(trace.policy.current_recommendation().maximum_total, 980_000);
    trace.policy.expire(1, true, 4_000 * MS, &mut trace.clock, trace.deps);
    assert_eq!(trace.policy.promotion, None);
    assert_eq!(trace.policy.current_recommendation().maximum_total, 905_041);
    assert_eq!(trace.policy.tier, Tier::Survival);
    assert_eq!(trace.policy.probe_failures, 0);
}
