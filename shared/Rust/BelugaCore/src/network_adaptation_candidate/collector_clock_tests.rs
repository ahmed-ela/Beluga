//! Author-only fixtures for the shared typed collector/evidence/Stop seam.
//! Literal successors follow native service2915–2930/2993–3048/2732–2757 and
//! policy resetIncomplete/endShow ordering. No expected state calls the reducer.
//! Copied179 state and assignment journals are checked separately; these tests do
//! not grant native Instant/resource/provider authority or establish actor adoption.
use super::*;
use super::dependencies::{ATTO, MS};
use super::state_codec;

const Q: ClockSite = ClockSite::QueueReset;
const PAYLOAD: u64 = 0x7ff8_0000_0000_0042;
const NEGATIVE_ZERO: u64 = 0x8000_0000_0000_0000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Denied { Cut { ordinal: usize, site: ClockSite }, Arithmetic }
#[derive(Default)]
struct Cuts { calls: Vec<ClockSite>, fail: Option<usize>, last: Option<usize> }
impl TryClockFacts for Cuts {
    type Error = Denied;
    fn try_cut(&mut self, site: ClockSite) -> Result<RelativeTime, Denied> {
        let ordinal = self.calls.len(); self.calls.push(site);
        if self.fail == Some(ordinal) { return Err(Denied::Cut { ordinal, site }); }
        self.last = Some(ordinal); Ok((100 + ordinal as i128) * MS)
    }
    fn last_try_time_source(&self) -> TimeSource {
        self.last.map(|ordinal| TimeSource::ActualRead { site: self.calls[ordinal], ordinal })
            .unwrap_or(TimeSource::Untracked)
    }
    fn try_arithmetic<T>(&mut self, value: Option<T>) -> Result<T, Denied> { value.ok_or(Denied::Arithmetic) }
}
#[derive(Default)]
struct LegacyCuts { calls: Vec<ClockSite> }
impl ClockFacts for LegacyCuts {
    fn cut(&mut self, site: ClockSite) -> RelativeTime {
        let ordinal = self.calls.len(); self.calls.push(site); (100 + ordinal as i128) * MS
    }
    fn last_time_source(&self) -> TimeSource {
        let ordinal = self.calls.len() - 1;
        TimeSource::ActualRead { site: self.calls[ordinal], ordinal }
    }
}
fn denial() -> Denied { Denied::Cut { ordinal: 0, site: Q } }

fn owner() -> Owner {
    let mut v = Owner::new(50_000_000, 60, Dependencies::default());
    v.revision = 57; v.fast_statistics_available = false;
    v.evidence_lane = Some(EvidenceLane::OrdinaryFallback); v.last_evidence = Some(0);
    v.freshness.minimum = Some(31);
    v.applied = Some(Recommendation { tier: Tier::Balanced, maximum_video: 1_234_567,
        maximum_total: 2_345_678, fps: 29, scale: Scalar(NEGATIVE_ZERO) });
    let p = &mut v.policy;
    p.peer = Some(1); p.tier = Tier::Critical; p.route_present = true;
    p.healthy_upgrades = 8; p.bandwidth_downgrades = 9; p.unavailable_samples = 10;
    p.positive_bootstrap = 11; p.limited_upgrades = 12; p.probe_healthy = 13;
    p.probe_best = Some(Tier::Survival); p.probe_grace = 14;
    p.probe_deadline = Some(3_500 * MS); p.probe_cooldown = 15; p.probe_failures = 16;
    p.probe_qualification_at = Some(43); p.probe_maximum = Some(612_000);
    p.floor_show = Some(7); p.floor_reserved = true; p.floor_active = true;
    p.startup_peer = Some(1); p.startup_show = Some(7); p.startup_disproved = true;
    p.startup_sparse_deadline = Some(46);
    p.floor_first_witness = Some(FloorWitness { observed_at: 44, bandwidth: Scalar::new(306_000.0) });
    p.floor_cooldown_at = Some(45); p.consumed_sequence = Some(u64::MAX);
    p.floor_regular_sequence = Some(u64::MAX - 1);
    p.floor_regular_timestamp = Some(Scalar(NEGATIVE_ZERO));
    p.capacity_sequence = Some(u64::MAX - 2); p.capacity_timestamp = Some(Scalar(PAYLOAD));
    p.capacity_sample = Some(CapacitySample { packets: Some(31), delay: Some(Scalar(PAYLOAD)) });
    p.capacity_bandwidth_high = Some(Scalar::new(306_000.0));
    p.promotion = Some(Promotion { tier: Tier::Critical, maximum_total: 712_000, deadline: 42 });
    p.last_average_delay = Some(Scalar(PAYLOAD));
    p.queue.packets = Some(30); p.queue.delay_bits = Some(0.25_f64.to_bits());
    p.queue.pressure_count = 2; p.queue.low_observation = Some(47); p.queue.soft_observation = Some(48);
    v.begin_time_assignment_frame(); v
}
fn probe(mut v: Owner) -> Owner {
    v.policy.tier = Tier::Survival;
    v.policy.probe_origin = Some(Tier::AudioPriority);
    v.policy.probe_confirmed = Some(Tier::Survival);
    v.policy.floor_seed = Some(Scalar::new(306_000.0));
    v.policy.floor_probe_cancelled = false; v
}
fn report() -> Report {
    // Deliberately opaque payloads: this seam routes a report, it does not reduce it.
    Report { peer: u64::MAX, capture_active: true, automatically_suspended: true,
        bandwidth: Some(Scalar(PAYLOAD)), current_rtt: Some(Scalar(NEGATIVE_ZERO)),
        observation: Observation::Measurement { fingerprint: [u64::MAX; 8],
            fingerprint_length: 64, total_bits: NEGATIVE_ZERO, responses: u64::MAX },
        collection_sequence: Some(31), strict: false,
        route: RouteFacts { incoming_present: true, equal_to_retained: false },
        packets: Some(u64::MAX), delay: Some(Scalar(PAYLOAD)),
        native_timestamp: Some(Scalar(PAYLOAD)), observed_at: -7 * ATTO - 1 }
}
fn expected(v: Owner) -> CollectorExpected {
    CollectorExpected { generation: 1, revision: v.revision, visibility_epoch: 7 }
}
fn lifecycle() -> CollectorLifecycleFacts {
    CollectorLifecycleFacts { task_cancelled: false, stopped: false,
        peer: PeerFacts { exact_peer: true, current_generation: 1 } }
}
fn facts() -> CollectorReportFacts {
    CollectorReportFacts { current_visibility_epoch: 7, exact_source: true, exact_capture_authorization: true }
}
fn clear_policy(p: &mut Policy, slot: TimeSlot) {
    match slot {
        TimeSlot::QueueLow | TimeSlot::QueueSoft => { p.queue.times.clear::<i128>(slot); }
        TimeSlot::RttAdvancement => { p.rtt.times.clear::<i128>(slot); }
        _ => { p.times.clear::<i128>(slot); }
    }
}
fn reset_before_q(v: &mut Owner) {
    // Literal resetIncomplete prefix, before the actual queueReset evaluation.
    v.policy.floor_first_witness = None; clear_policy(&mut v.policy, TimeSlot::FloorWitness);
    v.policy.capacity_sample = None; v.policy.capacity_bandwidth_high = None;
    v.policy.promotion = None; clear_policy(&mut v.policy, TimeSlot::PromotionDeadline);
    v.policy.healthy_upgrades = 0; v.policy.bandwidth_downgrades = 0;
}
fn queue_reset_success(v: &mut Owner) {
    // A tier reset keeps cumulative packets/delay; a sticky facade does no state write.
    if !v.policy.queue.faulted {
        v.policy.queue.pressure_count = 0;
        v.policy.queue.low_observation = None; v.policy.queue.soft_observation = None;
        clear_policy(&mut v.policy, TimeSlot::QueueLow); clear_policy(&mut v.policy, TimeSlot::QueueSoft);
    }
}
fn reset_after_q(v: &mut Owner) {
    queue_reset_success(v);
    v.policy.unavailable_samples = 0; v.policy.positive_bootstrap = 0;
    v.policy.limited_upgrades = 0; v.policy.probe_healthy = 0; v.policy.probe_best = None;
}
fn evidence_write(v: &mut Owner, lane: EvidenceLane, now: RelativeTime) {
    v.evidence_lane = Some(lane); v.last_evidence = Some(now);
    v.times.set(TimeSlot::EvidenceTime, now, Some(Origin::explicit(ExplicitTime::EvidencePreparation)));
}
fn end_show_prefix(v: &mut Owner) {
    v.policy.startup_peer = None; v.policy.startup_show = None; v.policy.startup_disproved = false;
    v.policy.startup_sparse_deadline = None; clear_policy(&mut v.policy, TimeSlot::SparseDeadline);
    v.policy.floor_reserved = false; v.policy.floor_active = false;
    v.policy.floor_first_witness = None; clear_policy(&mut v.policy, TimeSlot::FloorWitness);
}
fn end_show_before_q(v: &mut Owner) {
    end_show_prefix(v);
    v.policy.floor_probe_cancelled = true; v.policy.floor_seed = None;
    v.policy.tier = Tier::AudioPriority;
    v.policy.capacity_sample = None; v.policy.capacity_bandwidth_high = None;
    v.policy.promotion = None; clear_policy(&mut v.policy, TimeSlot::PromotionDeadline);
}
fn end_show_after_q(v: &mut Owner) {
    queue_reset_success(v);
    v.policy.probe_origin = None; v.policy.probe_confirmed = None;
    v.policy.probe_qualification_at = None; clear_policy(&mut v.policy, TimeSlot::ProbeQualification);
    v.policy.probe_best = None; v.policy.probe_maximum = None; v.policy.probe_healthy = 0;
    v.policy.probe_grace = 0; v.policy.probe_deadline = None; clear_policy(&mut v.policy, TimeSlot::ProbeDeadline);
}
fn all(actual: Owner, expected: Owner) {
    let a = state_codec::encode_owner(actual, state_codec::RESULT).unwrap();
    let e = state_codec::encode_owner(expected, state_codec::RESULT).unwrap();
    assert_eq!(a.header, state_codec::Header { abi: 1, domain: 2, phase: 2, count: 179 });
    assert_eq!(a.atoms.len(), 179);
    assert_eq!(a.header, e.header); assert_eq!(a.atoms, e.atoms, "literal all179 IEEE/state successor");
    for (aj, ej) in [(actual.times, expected.times), (actual.policy.times, expected.policy.times),
        (actual.policy.queue.times, expected.policy.queue.times), (actual.policy.rtt.times, expected.policy.rtt.times)] {
        assert_eq!(aj.valid(), ej.valid());
        for slot in SLOTS {
            assert_eq!(aj.edit(slot), ej.edit(slot), "edit {slot:?}");
            assert_eq!(aj.origin(slot), ej.origin(slot), "origin {slot:?}");
        }
    }
}
fn collection(actual: CollectorDisposition, expected: CollectorDisposition) {
    // Report contains NaN: numeric PartialEq is deliberately not the wire-bit oracle.
    assert_eq!(format!("{actual:?}"), format!("{expected:?}"));
}
fn fallback(actual: Option<(Option<Report>, u64, bool)>, expected: Option<(Option<Report>, u64, bool)>) {
    assert_eq!(format!("{actual:?}"), format!("{expected:?}"));
}

#[test]
fn collector_clock_prepare_absent_prior_lane_ignores_gap_zero_cuts() {
    let mut v = owner(); v.evidence_lane = None; v.last_evidence = Some(-7 * ATTO);
    let mut literal = v; evidence_write(&mut literal, EvidenceLane::FastSender, 0);
    let mut c = Cuts { fail: Some(0), ..Cuts::default() };
    assert_eq!(v.try_prepare_evidence(EvidenceLane::FastSender, 0, &mut c, Dependencies::default()), Ok(57));
    assert!(c.calls.is_empty()); all(v, literal);
}
#[test]
fn collector_clock_prepare_same_lane_strictly_greater_than_two_seconds() {
    for (now, reset) in [(2 * ATTO - 1, false), (2 * ATTO, false), (2 * ATTO + 1, true)] {
        let seed = owner(); let mut v = seed; let mut literal = seed;
        if reset { reset_before_q(&mut literal); reset_after_q(&mut literal); literal.revision = 58; }
        evidence_write(&mut literal, EvidenceLane::OrdinaryFallback, now);
        let mut c = Cuts::default();
        assert_eq!(v.try_prepare_evidence(EvidenceLane::OrdinaryFallback, now, &mut c, Dependencies::default()),
            Ok(if reset { 58 } else { 57 }));
        assert_eq!(c.calls, if reset { vec![Q] } else { vec![] }); all(v, literal);
        let mut legacy = seed; let mut lc = LegacyCuts::default();
        assert_eq!(legacy.prepare_evidence(EvidenceLane::OrdinaryFallback, now, &mut lc, Dependencies::default()), literal.revision);
        assert_eq!(lc.calls, c.calls); all(legacy, literal);
    }
}
#[test]
fn collector_clock_prepare_lane_change_even_backward_time_resets() {
    let mut v = owner(); let mut literal = v;
    reset_before_q(&mut literal); reset_after_q(&mut literal); literal.revision = 58;
    evidence_write(&mut literal, EvidenceLane::FastSender, -1);
    let mut c = Cuts::default();
    assert_eq!(v.try_prepare_evidence(EvidenceLane::FastSender, -1, &mut c, Dependencies::default()), Ok(58));
    assert_eq!(c.calls, [Q]); all(v, literal);
}
#[test]
fn collector_clock_prepare_denied_reset_preserves_exact_pre_queue_prefix() {
    let mut v = owner(); let mut literal = v; reset_before_q(&mut literal);
    let mut c = Cuts { fail: Some(0), ..Cuts::default() };
    assert_eq!(v.try_prepare_evidence(EvidenceLane::FastSender, 99, &mut c, Dependencies::default()), Err(denial()));
    assert_eq!(c.calls, [Q]); all(v, literal);
    assert_eq!(v.revision, 57); assert_eq!(v.evidence_lane, Some(EvidenceLane::OrdinaryFallback));
    assert_eq!(v.last_evidence, Some(0)); assert_eq!(v.time_edit(TimeSlot::EvidenceTime), TimeEdit::Retain);
}
#[test]
fn collector_clock_prepare_revision_wrap_occurs_only_after_successful_reset() {
    let mut seed = owner(); seed.revision = u64::MAX;
    let mut success = seed; let mut literal = seed;
    reset_before_q(&mut literal); reset_after_q(&mut literal); literal.revision = 0;
    evidence_write(&mut literal, EvidenceLane::FastSender, 99);
    let mut c = Cuts::default();
    assert_eq!(success.try_prepare_evidence(EvidenceLane::FastSender, 99, &mut c, Dependencies::default()), Ok(0));
    assert_eq!(c.calls, [Q]); all(success, literal);
    let mut failed = seed; let mut prefix = seed; reset_before_q(&mut prefix);
    let mut c = Cuts { fail: Some(0), ..Cuts::default() };
    assert_eq!(failed.try_prepare_evidence(EvidenceLane::FastSender, 99, &mut c, Dependencies::default()), Err(denial()));
    all(failed, prefix); assert_eq!(failed.revision, u64::MAX);
}
#[test]
fn collector_clock_prepare_equal_coordinate_is_new_explicit_assignment() {
    let mut v = owner(); let mut literal = v;
    evidence_write(&mut literal, EvidenceLane::OrdinaryFallback, 0);
    let mut c = Cuts { fail: Some(0), ..Cuts::default() };
    assert_eq!(v.try_prepare_evidence(EvidenceLane::OrdinaryFallback, 0, &mut c, Dependencies::default()), Ok(57));
    all(v, literal); assert!(c.calls.is_empty());
    assert_eq!(v.time_edit(TimeSlot::EvidenceTime),
        TimeEdit::Set(Origin::explicit(ExplicitTime::EvidencePreparation)));
}
#[test]
fn collector_clock_regular_success_routes_unchanged_report_and_legacy_matches() {
    let seed = owner(); let input = report(); let mut v = seed; let mut literal = seed;
    literal.fast_statistics_available = true; reset_before_q(&mut literal); reset_after_q(&mut literal);
    literal.revision = 58; evidence_write(&mut literal, EvidenceLane::FastSender, 99);
    let decision = CollectorDisposition::Adapt { report: Some(input), expected_revision: 58, capacity_only: false };
    let mut c = Cuts::default();
    collection(v.try_collected_report(expected(seed), Sample::Regular, lifecycle(), facts(), Some(input),
        99, &mut c, Dependencies::default()).unwrap(), decision);
    assert_eq!(c.calls, [Q]); all(v, literal);
    let mut legacy = seed; let mut lc = LegacyCuts::default();
    collection(legacy.collected_report(expected(seed), Sample::Regular, lifecycle(), facts(), Some(input),
        99, &mut lc, Dependencies::default()), decision);
    assert_eq!(lc.calls, c.calls); all(legacy, literal);
}
#[test]
fn collector_clock_regular_denial_keeps_fast_true_before_partial_reset_no_revision() {
    let seed = owner(); let mut v = seed; let mut literal = seed;
    literal.fast_statistics_available = true; reset_before_q(&mut literal);
    let mut c = Cuts { fail: Some(0), ..Cuts::default() };
    assert_eq!(v.try_collected_report(expected(seed), Sample::Regular, lifecycle(), facts(), Some(report()),
        99, &mut c, Dependencies::default()).unwrap_err(), denial());
    assert_eq!(c.calls, [Q]); all(v, literal);
    assert_eq!(v.revision, 57); assert!(v.fast_statistics_available);
    assert_eq!(v.time_edit(TimeSlot::EvidenceTime), TimeEdit::Retain);
}
#[test]
fn collector_clock_lifecycle_rejection_is_end_loop_without_owner_or_clock_writes() {
    for sample in [Sample::Regular, Sample::CapacityOnly] {
        for bit in 0..4 {
            let seed = owner(); let mut v = seed; let mut l = lifecycle();
            match bit { 0 => l.task_cancelled = true, 1 => l.stopped = true,
                2 => l.peer.exact_peer = false, 3 => l.peer.current_generation = 2, _ => unreachable!() }
            let mut c = Cuts { fail: Some(0), ..Cuts::default() };
            collection(v.try_collected_report(expected(seed), sample, l, facts(), Some(report()),
                99, &mut c, Dependencies::default()).unwrap(), CollectorDisposition::EndLoop);
            assert!(c.calls.is_empty()); all(v, seed);
        }
    }
}
#[test]
fn collector_clock_report_rejection_uses_live_revision_and_lane_specific_fast_flag() {
    for sample in [Sample::Regular, Sample::CapacityOnly] {
        for bit in 0..8 {
            let mut seed = owner(); seed.fast_statistics_available = true;
            let mut v = seed; let mut literal = seed; let mut e = expected(seed);
            let mut f = facts(); let mut r = Some(report());
            match bit {
                0 => r = None,
                1 => r.as_mut().unwrap().collection_sequence = None,
                2 => r.as_mut().unwrap().collection_sequence = Some(30),
                3 => f.current_visibility_epoch = 8,
                4 => f.exact_source = false,
                5 => f.exact_capture_authorization = false,
                6 => e.revision = 56,
                7 => e.revision = 58,
                _ => unreachable!()
            }
            if sample == Sample::Regular { literal.fast_statistics_available = false; }
            let mut c = Cuts { fail: Some(0), ..Cuts::default() };
            collection(v.try_collected_report(e, sample, lifecycle(), f, r,
                99, &mut c, Dependencies::default()).unwrap(),
                CollectorDisposition::Adapt { report: None, expected_revision: 57, capacity_only: false });
            assert!(c.calls.is_empty()); all(v, literal);
        }
    }
}
#[test]
fn collector_clock_capacity_acceptance_never_prepares_evidence_or_changes_fast_flag() {
    for fast in [false, true] {
        let mut seed = owner(); seed.fast_statistics_available = fast;
        let mut v = seed; let input = report(); let mut c = Cuts { fail: Some(0), ..Cuts::default() };
        let decision = CollectorDisposition::Adapt { report: Some(input), expected_revision: 57, capacity_only: true };
        collection(v.try_collected_report(expected(seed), Sample::CapacityOnly, lifecycle(), facts(), Some(input),
            99 * ATTO, &mut c, Dependencies::default()).unwrap(), decision);
        assert!(c.calls.is_empty()); all(v, seed);
        let mut legacy = seed; let mut lc = LegacyCuts::default();
        collection(legacy.collected_report(expected(seed), Sample::CapacityOnly, lifecycle(), facts(), Some(input),
            99 * ATTO, &mut lc, Dependencies::default()), decision);
        assert!(lc.calls.is_empty()); all(legacy, seed);
    }
}
#[test]
fn collector_clock_fallback_success_removes_only_timestamp_after_preparation() {
    let mut seed = owner(); seed.evidence_lane = Some(EvidenceLane::FastSender);
    let input = report(); let mut output = input; output.native_timestamp = None;
    let mut v = seed; let mut literal = seed;
    reset_before_q(&mut literal); reset_after_q(&mut literal); literal.revision = 58;
    evidence_write(&mut literal, EvidenceLane::OrdinaryFallback, 99);
    let mut c = Cuts::default();
    fallback(v.try_fallback_report(true, input, false, 99, &mut c, Dependencies::default()).unwrap(),
        Some((Some(output), 58, true)));
    assert_eq!(c.calls, [Q]); all(v, literal);
    assert_eq!(input.native_timestamp.unwrap().0, PAYLOAD);
    let mut legacy = seed; let mut lc = LegacyCuts::default();
    fallback(legacy.fallback_report(true, input, false, 99, &mut lc, Dependencies::default()),
        Some((Some(output), 58, true)));
    assert_eq!(lc.calls, c.calls); all(legacy, literal);
}
#[test]
fn collector_clock_fallback_denial_keeps_exact_prefix_and_returns_no_prepared_report() {
    let mut seed = owner(); seed.evidence_lane = Some(EvidenceLane::FastSender);
    seed.fast_statistics_available = true; let mut v = seed; let mut literal = seed; reset_before_q(&mut literal);
    let input = report(); let mut c = Cuts { fail: Some(0), ..Cuts::default() };
    assert_eq!(v.try_fallback_report(true, input, true, 99, &mut c, Dependencies::default()).unwrap_err(), denial());
    assert_eq!(c.calls, [Q]); all(v, literal);
    assert!(v.fast_statistics_available); assert_eq!(input.native_timestamp.unwrap().0, PAYLOAD);
    assert_eq!(v.revision, 57); assert_eq!(v.time_edit(TimeSlot::EvidenceTime), TimeEdit::Retain);
}
#[test]
fn collector_clock_fallback_missing_report_and_ownership_are_zero_cut() {
    for fast in [false, true] {
        for suspended in [false, true] {
            let mut seed = owner(); seed.fast_statistics_available = fast;
            let mut v = seed; let mut c = Cuts { fail: Some(0), ..Cuts::default() };
            let owns = suspended || !fast;
            fallback(v.try_fallback_report(false, report(), suspended, 99, &mut c, Dependencies::default()).unwrap(),
                if owns { Some((None, 57, false)) } else { None });
            assert!(c.calls.is_empty()); all(v, seed);
            if !owns {
                let mut c = Cuts { fail: Some(0), ..Cuts::default() };
                fallback(v.try_fallback_report(true, report(), suspended, 99, &mut c, Dependencies::default()).unwrap(), None);
                assert!(c.calls.is_empty()); all(v, seed);
            }
        }
    }
}
#[test]
fn collector_clock_fallback_freshness_rejection_and_unfenced_absence_are_distinct() {
    for sequence in [None, Some(30)] {
        let seed = owner(); let mut v = seed; let mut input = report(); input.collection_sequence = sequence;
        let mut c = Cuts { fail: Some(0), ..Cuts::default() };
        fallback(v.try_fallback_report(true, input, false, 99, &mut c, Dependencies::default()).unwrap(), None);
        assert!(c.calls.is_empty()); all(v, seed);
    }
    let mut seed = owner(); seed.freshness.minimum = None;
    let mut v = seed; let mut input = report(); input.collection_sequence = None;
    let mut output = input; output.native_timestamp = None;
    let mut literal = seed; evidence_write(&mut literal, EvidenceLane::OrdinaryFallback, 99);
    let mut c = Cuts { fail: Some(0), ..Cuts::default() };
    fallback(v.try_fallback_report(true, input, false, 99, &mut c, Dependencies::default()).unwrap(),
        Some((Some(output), 57, true)));
    assert!(c.calls.is_empty()); all(v, literal);
}
#[test]
fn collector_clock_end_show_without_revision_precedes_later_sampling_bookkeeping() {
    let mut seed = owner(); seed.revision = u64::MAX; seed.fast_statistics_available = true;
    let mut v = seed; let mut literal = seed; end_show_prefix(&mut literal);
    let mut c = Cuts { fail: Some(0), ..Cuts::default() };
    assert_eq!(v.try_end_show_without_revision(&mut c, Dependencies::default()), Ok(()));
    assert!(c.calls.is_empty()); all(v, literal); assert_eq!(v.revision, u64::MAX);
    assert!(v.fast_statistics_available); assert_eq!(v.last_evidence, Some(0));
    // This later actual Stop cut is distinct, not fused into the EndShow wrapper.
    v.stop_sampling_bookkeeping();
    literal.fast_statistics_available = false; literal.evidence_lane = None;
    literal.last_evidence = None; literal.times.clear::<i128>(TimeSlot::EvidenceTime);
    literal.freshness.minimum = None; literal.revision = 0;
    all(v, literal); assert!(v.applied.is_some()); assert!(c.calls.is_empty());
}
#[test]
fn collector_clock_end_show_probe_success_keeps_revision_and_legacy_matches() {
    let seed = probe(owner()); let mut v = seed; let mut literal = seed;
    end_show_before_q(&mut literal); end_show_after_q(&mut literal);
    let mut c = Cuts::default();
    assert_eq!(v.try_end_show_without_revision(&mut c, Dependencies::default()), Ok(()));
    assert_eq!(c.calls, [Q]); all(v, literal); assert_eq!(v.revision, 57);
    let mut legacy = seed; let mut lc = LegacyCuts::default();
    legacy.end_show_without_revision(&mut lc, Dependencies::default());
    assert_eq!(lc.calls, c.calls); all(legacy, literal);
}
#[test]
fn collector_clock_end_show_probe_denial_retains_pre_queue_negative_prefix_no_revision() {
    let seed = probe(owner()); let mut v = seed; let mut literal = seed; end_show_before_q(&mut literal);
    let mut c = Cuts { fail: Some(0), ..Cuts::default() };
    assert_eq!(v.try_end_show_without_revision(&mut c, Dependencies::default()), Err(denial()));
    assert_eq!(c.calls, [Q]); all(v, literal);
    assert_eq!(v.revision, 57); assert!(v.policy.probe_origin.is_some());
    assert_eq!(v.policy.probe_deadline, seed.policy.probe_deadline);
    assert_eq!(v.time_edit(TimeSlot::ProbeDeadline), TimeEdit::Retain);
}
#[test]
fn collector_clock_sticky_queue_fault_still_reads_q_before_facade_guard() {
    for stop in [false, true] {
        let mut seed = if stop { probe(owner()) } else { owner() };
        seed.policy.queue.faulted = true;
        let mut v = seed; let mut literal = seed;
        if stop { end_show_before_q(&mut literal); end_show_after_q(&mut literal); }
        else {
            reset_before_q(&mut literal); reset_after_q(&mut literal); literal.revision = 58;
            evidence_write(&mut literal, EvidenceLane::FastSender, 99);
        }
        let mut c = Cuts::default();
        if stop { v.try_end_show_without_revision(&mut c, Dependencies::default()).unwrap(); }
        else { assert_eq!(v.try_prepare_evidence(EvidenceLane::FastSender, 99, &mut c, Dependencies::default()), Ok(58)); }
        assert_eq!(c.calls, [Q]); all(v, literal);
        assert_eq!(v.policy.queue, seed.policy.queue);
        let mut denied = seed; let mut prefix = seed;
        if stop { end_show_before_q(&mut prefix); } else { reset_before_q(&mut prefix); }
        let mut c = Cuts { fail: Some(0), ..Cuts::default() };
        if stop { assert_eq!(denied.try_end_show_without_revision(&mut c, Dependencies::default()), Err(denial())); }
        else { assert_eq!(denied.try_prepare_evidence(EvidenceLane::FastSender, 99, &mut c, Dependencies::default()), Err(denial())); }
        assert_eq!(c.calls, [Q]); all(denied, prefix);
    }
}
