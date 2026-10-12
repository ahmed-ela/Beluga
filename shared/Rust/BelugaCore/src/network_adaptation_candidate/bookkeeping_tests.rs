//! PRIVATE, unexecuted expectations derived from unchanged native Swift cuts.
//! Intended as a child module of the private complete adaptation module:
//! `#[cfg(test)] mod tests_bookkeeping;`. No ABI, native authority or actor proof.
use super::*;

const ATTO: i128 = 1_000_000_000_000_000_000;
const NAN_PAYLOAD: u64 = 0x7ff8_0000_0000_0042;
const NEGATIVE_ZERO: u64 = 0x8000_0000_0000_0000;

#[derive(Default)]
struct OrderedClock { calls: Vec<ClockSite>, value: i128 }
impl ClockFacts for OrderedClock {
    fn cut(&mut self, site: ClockSite) -> i128 {
        self.calls.push(site);
        self.value
    }
}

fn previous_applied() -> Recommendation {
    Recommendation { tier: Tier::Balanced, maximum_video: 1_234_567,
        maximum_total: 2_345_678, fps: 29, scale: Scalar::new(1.5) }
}
fn captured_recommendation() -> Recommendation {
    Recommendation { tier: Tier::Emergency, maximum_video: 93_440,
        maximum_total: 589_680, fps: 2, scale: Scalar::new(8.0) }
}

// A pure copied-state sentinel, NOT an installed/active native capture fixture. Its
// optional NaN is intentional: Swift owner equality is non-reflexive, but unrelated
// bookkeeping must still retain every bit. Every outer stored field is represented by
// Debug, including immutable profiles, nested raw RTT DTOs and private mathematical clocks.
fn sentinel() -> Owner {
    let mut owner = Owner::new(4_000_000, 60, Dependencies::default());
    owner.revision = u64::MAX;
    owner.fast_statistics_available = true;
    owner.evidence_lane = Some(EvidenceLane::OrdinaryFallback);
    owner.last_evidence = Some(-7 * ATTO - 1);
    owner.freshness.minimum = Some(u64::MAX - 1);
    owner.applied = Some(previous_applied());
    let policy = &mut owner.policy;
    policy.peer = Some(u64::MAX - 3);
    policy.tier = Tier::Critical;
    policy.healthy_upgrades = 1;
    policy.bandwidth_downgrades = 2;
    policy.unavailable_samples = 3;
    policy.positive_bootstrap = 4;
    policy.limited_upgrades = 5;
    policy.probe_healthy = 6;
    policy.probe_grace = 7;
    policy.probe_deadline = Some(17 * ATTO + 1);
    policy.probe_cooldown = 8;
    policy.probe_failures = 9;
    policy.below_reserve_disproved = true;
    policy.resume_restoration = Some(Restoration { disproved: true, cooldown: 23, failures: 4 });
    policy.probe_origin = Some(Tier::AudioPriority);
    policy.probe_best = Some(Tier::Emergency);
    policy.probe_confirmed = Some(Tier::Survival);
    policy.probe_qualification_at = Some(-13 * ATTO - 1);
    policy.probe_maximum = Some(3_456_789);
    policy.promotion = Some(Promotion { tier: Tier::Critical, maximum_total: 1_234_000, deadline: 19 * ATTO - 1 });
    policy.suspension_pressure = 10;
    policy.stable_resume = 11;
    policy.maximum_resume = 12;
    policy.bandwidth_unavailable = true;
    policy.last_latency_pressure = true;
    policy.last_positive_suspension_pressure = true;
    policy.last_average_delay = Some(Scalar(NAN_PAYLOAD));
    policy.queue.packets = Some(u64::MAX);
    policy.queue.delay_bits = Some(Scalar::new(0.25).0);
    policy.queue.pressure_count = 2;
    policy.queue.low_observation = Some(-ATTO - 1);
    policy.queue.soft_observation = Some(ATTO + 1);
    policy.rtt.last_advancement = Some(-4 * ATTO - 1);
    policy.rtt.raw.watermark.fingerprint_words = [1, 2, 3, 4, 5, 6, 7, u64::MAX];
    policy.rtt.raw.watermark.total_bits = Scalar::new(1.25).0;
    policy.rtt.raw.watermark.responses = u64::MAX;
    policy.rtt.raw.fence.fingerprint_words = [8, 9, 10, 11, 12, 13, 14, u64::MAX - 1];
    policy.rtt.raw.fence.total_bits = Scalar::new(2.5).0;
    policy.rtt.raw.fence.responses = u64::MAX - 1;
    policy.consumed_sequence = Some(u64::MAX - 7);
    policy.route_present = true;
    policy.capacity_sample = Some(CapacitySample { packets: Some(u64::MAX - 6), delay: Some(Scalar(NAN_PAYLOAD)) });
    policy.capacity_bandwidth_high = Some(Scalar::new(3_000_001.0));
    policy.capacity_timestamp = Some(Scalar::new(123.25));
    policy.capacity_sequence = Some(u64::MAX - 5);
    policy.capacity_growth_veto = true;
    policy.floor_show = Some(u64::MAX - 4);
    policy.floor_reserved = true;
    policy.floor_active = true;
    policy.floor_attempt_consumed = true;
    policy.floor_probe_cancelled = true;
    policy.floor_seed = Some(Scalar::new(360_001.0));
    policy.floor_first_witness = Some(FloorWitness { observed_at: -2 * ATTO + 1, bandwidth: Scalar::new(400_001.0) });
    policy.floor_regular_sequence = Some(u64::MAX - 2);
    policy.floor_regular_timestamp = Some(Scalar::new(124.25));
    policy.floor_cooldown_at = Some(-11 * ATTO + 1);
    policy.startup_peer = policy.peer;
    policy.startup_show = policy.floor_show;
    policy.startup_disproved = true;
    policy.startup_sparse_deadline = Some(17 * ATTO + 1);
    owner
}

// Not PartialEq: Scalar's numerical equality must keep NaN != NaN and +0 == -0.
// Derive(Debug) on this pinned typed representation recursively prints Scalar's raw u64,
// every field, optional structure, integers and exact i128 clocks. This independently
// checks preservation without asking candidate Policy::bits_equal to bless itself.
fn assert_all_bits(actual: &Owner, expected: &Owner) {
    assert_eq!(format!("{actual:?}"), format!("{expected:?}"));
}

// Literal native resetIncompleteEvidenceWindow (Swift614–630), not a candidate call.
// Current native queue tier reset preserves packet/delay identity and clears only leases
// and pressure. RTT, full-width tombstones, probe ownership/deadline/backoff stay retained.
fn native_expected_incomplete_reset(mut expected: Owner) -> Owner {
    expected.policy.floor_first_witness = None;
    expected.policy.capacity_sample = None;
    expected.policy.capacity_bandwidth_high = None;
    expected.policy.promotion = None;
    expected.policy.healthy_upgrades = 0;
    expected.policy.bandwidth_downgrades = 0;
    expected.policy.queue.pressure_count = 0;
    expected.policy.queue.low_observation = None;
    expected.policy.queue.soft_observation = None;
    expected.policy.unavailable_samples = 0;
    expected.policy.positive_bootstrap = 0;
    expected.policy.limited_upgrades = 0;
    expected.policy.probe_healthy = 0;
    expected.policy.probe_best = None;
    expected
}

fn native_expected_epoch(mut expected: Owner, minimum: Option<u64>) -> Owner {
    expected.freshness.minimum = match minimum {
        Some(minimum) => Some(expected.freshness.minimum.map(|old| old.max(minimum)).unwrap_or(minimum)),
        None => None,
    };
    expected = native_expected_incomplete_reset(expected);
    expected.evidence_lane = None;
    expected.last_evidence = None;
    expected.revision = expected.revision.wrapping_add(1);
    expected
}

#[test]
fn network_adaptation_bookkeeping_peer_start_clears_only_fast_availability() {
    for already_false in [false, true] {
        let mut actual = sentinel();
        actual.fast_statistics_available = !already_false;
        let mut expected = actual;
        expected.fast_statistics_available = false;
        assert_eq!(actual.apply_native_bookkeeping_cut(NativeBookkeepingCut::PeerStartReturned),
            BookkeepingChange::FastAvailabilityCleared);
        assert_all_bits(&actual, &expected);
        assert_eq!(actual.revision, u64::MAX);
    }
}

#[test]
fn network_adaptation_bookkeeping_resume_probe_plan_strict_ten_fps_edges_all_tiers() {
    // Native tier FPS and scale tables; cap4m maximum-video values are pinned old tier
    // arithmetic, not computed by this candidate to construct its expected output.
    let tiers = [Tier::Full, Tier::High, Tier::Balanced, Tier::Constrained,
        Tier::Critical, Tier::Survival, Tier::Emergency, Tier::AudioPriority];
    let tier_fps = [60, 45, 30, 20, 10, 5, 2, 1];
    let scales: [f64; 8] = [1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 8.0, 12.0];
    let videos = [2_944_000, 2_944_000, 2_944_000, 1_962_240, 747_520, 280_320, 93_440, 32_000];
    for index in 0..tiers.len() {
        for base_fps in [1, 9, 10, 11, 60] {
            let mut actual = Owner::new(4_000_000, base_fps, Dependencies::default());
            actual.policy.tier = tiers[index];
            actual.revision = u64::MAX;
            actual.applied = Some(previous_applied());
            let before = actual;
            let plan = actual.resume_probe_plan();
            let fps = base_fps.min(tier_fps[index]);
            assert_eq!(plan.captured_recommendation.tier, tiers[index]);
            assert_eq!(plan.captured_recommendation.maximum_video, videos[index]);
            assert_eq!(plan.captured_recommendation.fps, fps);
            assert_eq!(plan.captured_recommendation.scale.0, scales[index].to_bits());
            if fps < 10 {
                let limits = plan.limits.expect("native strict <10 temporary probe branch");
                assert_eq!(limits.maximum_video, videos[index]);
                assert_eq!(limits.fps, 10);
                assert_eq!(limits.scale.0, scales[index].to_bits());
            } else { assert!(plan.limits.is_none()); }
            assert_all_bits(&actual, &before);
        }
    }
}

#[test]
fn network_adaptation_bookkeeping_resume_probe_output_cut_clears_only_applied() {
    for was_applied in [false, true] {
        let mut actual = sentinel();
        if !was_applied { actual.applied = None; }
        let mut expected = actual;
        expected.applied = None;
        assert_eq!(actual.apply_native_bookkeeping_cut(NativeBookkeepingCut::ResumeProbeOutputReturned),
            BookkeepingChange::AppliedCleared);
        assert_all_bits(&actual, &expected);
        assert_eq!(actual.revision, u64::MAX);
    }
}

#[test]
fn network_adaptation_bookkeeping_missing_resources_clear_is_separate_after_epoch() {
    for minimum in [None, Some(0), Some(u64::MAX)] {
        let mut actual = sentinel();
        let mut expected = native_expected_epoch(actual, minimum);
        let mut clock = OrderedClock { value: -29 * ATTO + 1, ..OrderedClock::default() };
        actual.begin_post_resume_epoch(minimum, &mut clock, Dependencies::default());
        assert_all_bits(&actual, &expected);
        assert_eq!(clock.calls, [ClockSite::QueueReset]);
        assert_eq!(actual.applied, Some(previous_applied()));
        expected.applied = None;
        assert_eq!(actual.apply_native_bookkeeping_cut(NativeBookkeepingCut::ResumeMissingResourcesContextCleared),
            BookkeepingChange::AppliedCleared);
        assert_all_bits(&actual, &expected);
        assert_eq!(actual.revision, 0);
    }
}

#[test]
fn network_adaptation_bookkeeping_restoration_stores_captured_not_current_recommendation() {
    let mut actual = sentinel();
    let captured = captured_recommendation();
    assert_ne!(captured, actual.policy.current_recommendation());
    let mut expected = actual;
    expected.applied = Some(captured);
    assert_eq!(actual.apply_native_bookkeeping_cut(NativeBookkeepingCut::ResumeRestorationOutputReturned {
        captured_recommendation: captured }), BookkeepingChange::AppliedStored);
    assert_all_bits(&actual, &expected);
    assert_eq!(actual.revision, u64::MAX);
}

#[test]
fn network_adaptation_bookkeeping_restoration_store_then_epoch_does_not_erase_applied() {
    let mut actual = sentinel();
    let captured = captured_recommendation();
    let mut expected = actual;
    expected.applied = Some(captured);
    actual.apply_native_bookkeeping_cut(NativeBookkeepingCut::ResumeRestorationOutputReturned {
        captured_recommendation: captured });
    assert_all_bits(&actual, &expected);
    expected = native_expected_epoch(expected, Some(u64::MAX));
    let mut clock = OrderedClock::default();
    actual.begin_post_resume_epoch(Some(u64::MAX), &mut clock, Dependencies::default());
    assert_all_bits(&actual, &expected);
    assert_eq!(clock.calls, [ClockSite::QueueReset]);
    assert_eq!(actual.applied, Some(captured));
}

#[test]
fn network_adaptation_bookkeeping_catch_clear_unconditional_but_epoch_only_matching_context() {
    // Context ownership is deliberately native-only. These three literal caller paths do
    // not install contexts or test actor admission. Missing and foreign contexts both omit
    // the epoch; all three still execute original4223's unconditional copied-state clear.
    for path in ["matching", "missing", "foreign"] {
        let mut actual = sentinel();
        let mut expected = actual;
        let mut clock = OrderedClock::default();
        if path == "matching" {
            actual.begin_post_resume_epoch(Some(u64::MAX), &mut clock, Dependencies::default());
            expected = native_expected_epoch(expected, Some(u64::MAX));
        }
        expected.applied = None;
        assert_eq!(actual.apply_native_bookkeeping_cut(NativeBookkeepingCut::ResumeRestorationCatchContextHandled),
            BookkeepingChange::AppliedCleared);
        assert_all_bits(&actual, &expected);
        assert_eq!(actual.revision, if path == "matching" { 0 } else { u64::MAX });
        assert_eq!(clock.calls.len(), usize::from(path == "matching"));
    }
}

#[test]
fn network_adaptation_bookkeeping_stale_restoration_epoch_cleanup_retains_applied() {
    // A stale successful native return is rolled back natively. There is no setter-only
    // event for it; its optional exact-attempt/binding cleanup must not invent applied=nil.
    for matching_context in [false, true] {
        let mut actual = sentinel();
        let mut expected = actual;
        let mut clock = OrderedClock::default();
        if matching_context {
            actual.begin_post_resume_epoch(Some(u64::MAX), &mut clock, Dependencies::default());
            expected = native_expected_epoch(expected, Some(u64::MAX));
        }
        assert_all_bits(&actual, &expected);
        assert_eq!(actual.applied, Some(previous_applied()));
        assert_eq!(clock.calls.len(), usize::from(matching_context));
    }
}

#[test]
fn network_adaptation_bookkeeping_startup_present_stores_captured_absent_retains() {
    // This pure cut is positioned BEFORE native geometry/input-bounds/capturer output.
    // It does not itself execute or prove those effects or the preceding startup fence.
    for native_update_returned in [false, true] {
        let mut actual = sentinel();
        let mut expected = actual;
        if native_update_returned { expected.applied = Some(captured_recommendation()); }
        assert_eq!(actual.apply_native_bookkeeping_cut(NativeBookkeepingCut::StartupSenderFencePassedBeforeGeometry {
            captured_recommendation: captured_recommendation(), native_update_returned }),
            if native_update_returned { BookkeepingChange::AppliedStored } else { BookkeepingChange::AppliedRetained });
        assert_all_bits(&actual, &expected);
        assert_eq!(actual.revision, u64::MAX);
    }
}

#[test]
fn network_adaptation_bookkeeping_freshness_full_width_inclusive_nonregressing_reset() {
    let mut freshness = Freshness::default();
    assert!(freshness.admits(None));
    assert!(freshness.admits(Some(0)));
    for minimum in [0, 1, (1u64 << 53) + 1, u64::MAX - 1, u64::MAX] {
        freshness.reset();
        freshness.begin(minimum);
        assert_eq!(freshness.minimum, Some(minimum));
        assert!(!freshness.admits(None));
        assert!(freshness.admits(Some(minimum)));
        if minimum > 0 { assert!(!freshness.admits(Some(minimum - 1))); }
        if minimum < u64::MAX { assert!(freshness.admits(Some(minimum + 1))); }
        freshness.begin(0);
        assert_eq!(freshness.minimum, Some(minimum));
        freshness.begin(u64::MAX);
        assert_eq!(freshness.minimum, Some(u64::MAX));
        assert!(!freshness.admits(Some(u64::MAX - 1)));
        freshness.reset();
        assert_eq!(freshness.minimum, None);
        assert!(freshness.admits(None));
    }
}

#[test]
fn network_adaptation_bookkeeping_evidence_same_lane_strict_two_seconds_backward_wrapping() {
    for delta in [-ATTO, 0, 2 * ATTO - 1, 2 * ATTO, 2 * ATTO + 1] {
        let mut actual = sentinel();
        let before = actual;
        let now = before.last_evidence.unwrap() + delta;
        let resets = delta > 2 * ATTO;
        let mut expected = if resets { native_expected_incomplete_reset(before) } else { before };
        if resets { expected.revision = 0; }
        expected.last_evidence = Some(now);
        let mut clock = OrderedClock::default();
        let revision = actual.prepare_evidence(EvidenceLane::OrdinaryFallback, now, &mut clock, Dependencies::default());
        assert_eq!(revision, if resets { 0 } else { u64::MAX });
        assert_all_bits(&actual, &expected);
        assert_eq!(clock.calls.len(), usize::from(resets));
    }
}

#[test]
fn network_adaptation_bookkeeping_first_evidence_no_reset_lane_switch_resets_once() {
    let mut actual = sentinel();
    actual.evidence_lane = None;
    // Deliberately keep a historical time: original guard requires previousLane, so a
    // mathematical gap alone cannot reset a first-lane report.
    actual.last_evidence = Some(-100 * ATTO);
    let mut expected = actual;
    expected.evidence_lane = Some(EvidenceLane::FastSender);
    expected.last_evidence = Some(100 * ATTO);
    let mut clock = OrderedClock::default();
    assert_eq!(actual.prepare_evidence(EvidenceLane::FastSender, 100 * ATTO, &mut clock, Dependencies::default()), u64::MAX);
    assert_all_bits(&actual, &expected);
    assert!(clock.calls.is_empty());
    expected = native_expected_incomplete_reset(expected);
    expected.evidence_lane = Some(EvidenceLane::OrdinaryFallback);
    expected.last_evidence = Some(99 * ATTO);
    expected.revision = 0;
    assert_eq!(actual.prepare_evidence(EvidenceLane::OrdinaryFallback, 99 * ATTO, &mut clock, Dependencies::default()), 0);
    assert_all_bits(&actual, &expected);
    assert_eq!(clock.calls, [ClockSite::QueueReset]);
}

#[test]
fn network_adaptation_bookkeeping_state_bits_are_not_swift_numeric_equality() {
    let mut owner = sentinel();
    assert!(!owner.policy.swift_equal(&owner.policy, true));
    assert_all_bits(&owner, &owner);
    owner.policy.last_average_delay = Some(Scalar(NEGATIVE_ZERO));
    owner.policy.capacity_sample.as_mut().unwrap().delay = Some(Scalar(NEGATIVE_ZERO));
    let mut numeric_equal = owner;
    numeric_equal.policy.last_average_delay = Some(Scalar(0));
    numeric_equal.policy.capacity_sample.as_mut().unwrap().delay = Some(Scalar(0));
    assert!(owner.policy.swift_equal(&numeric_equal.policy, true));
    assert_ne!(format!("{owner:?}"), format!("{numeric_equal:?}"));
    let mut expected = owner;
    expected.applied = None;
    owner.apply_native_bookkeeping_cut(NativeBookkeepingCut::ResumeRestorationCatchContextHandled);
    assert_all_bits(&owner, &expected);
}

// Root-authored additive None-state edge from native7671-7672's presence branch.
// This is copied-state bookkeeping coverage, not execution of the native fence/output.
#[test]
fn network_adaptation_bookkeeping_startup_none_present_stores_absent_keeps_none() {
    for native_update_returned in [false, true] {
        let mut actual = sentinel();
        actual.applied = None;
        let mut expected = actual;
        if native_update_returned {
            expected.applied = Some(captured_recommendation());
        }
        assert_eq!(
            actual.apply_native_bookkeeping_cut(
                NativeBookkeepingCut::StartupSenderFencePassedBeforeGeometry {
                    captured_recommendation: captured_recommendation(),
                    native_update_returned,
                },
            ),
            if native_update_returned {
                BookkeepingChange::AppliedStored
            } else {
                BookkeepingChange::AppliedRetained
            },
        );
        assert_all_bits(&actual, &expected);
        assert_eq!(actual.revision, u64::MAX);
    }
}

