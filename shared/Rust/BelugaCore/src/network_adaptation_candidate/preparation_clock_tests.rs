//! Independent unpublished preparation contract. Frozen native service3075–3178
//! owns entry order/overrides/expiry guard; native policy632–804,829–1067,
//! 1703–1740,2079–2330 owns the literal branch successors below.
//! Constructors seed immutable cached demand only. No owner/policy reducer is
//! called to manufacture expected outputs. No actor/native-effect adoption claim.
use super::*;
use super::dependencies::{ATTO, MS};
use super::state_codec;
use super::time_assignments::AssignmentJournal;

const Q: ClockSite = ClockSite::QueueReset;
const E: ClockSite = ClockSite::RttEvent;
const A: ClockSite = ClockSite::RttApply;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Denied { Cut { ordinal: usize, site: ClockSite }, Arithmetic }
#[derive(Default)]
struct NativeCuts { calls: Vec<ClockSite>, fail: Option<usize>, last: Option<usize>, arithmetic: Vec<bool> }
impl TryClockFacts for NativeCuts {
    type Error = Denied;
    fn try_cut(&mut self, site: ClockSite) -> Result<RelativeTime, Denied> {
        let ordinal = self.calls.len(); self.calls.push(site);
        if self.fail == Some(ordinal) { return Err(Denied::Cut { ordinal, site }); }
        self.last = Some(ordinal); Ok((50 + ordinal as i128) * MS)
    }
    fn last_try_time_source(&self) -> TimeSource {
        self.last.map(|ordinal| TimeSource::ActualRead { site: self.calls[ordinal], ordinal })
            .unwrap_or(TimeSource::Untracked)
    }
    fn try_arithmetic<T>(&mut self, value: Option<T>) -> Result<T, Denied> {
        self.arithmetic.push(value.is_some()); value.ok_or(Denied::Arithmetic)
    }
}

#[derive(Clone, Copy)]
struct Case { owner: Owner, entry: EntryFacts, report: Option<Report>, capacity: bool,
    allows_resume: bool, expiry_at: RelativeTime, generation: u64, revision: u64 }
fn owner() -> Owner {
    let mut v = Owner::new(50_000_000, 60, Dependencies::default());
    v.revision = 57; v.fast_statistics_available = true;
    v.evidence_lane = Some(EvidenceLane::OrdinaryFallback); v.last_evidence = Some(-7 * ATTO - 1);
    v.freshness.minimum = Some(31);
    v.applied = Some(Recommendation { tier: Tier::Balanced, maximum_video: 1_234_567,
        maximum_total: 2_345_678, fps: 29, scale: Scalar::new(1.5) });
    v.policy.peer = Some(1); v.policy.tier = Tier::Survival; v.policy.route_present = true;
    v.policy.consumed_sequence = Some(39); v.policy.floor_regular_sequence = Some(39);
    v.policy.floor_regular_timestamp = Some(Scalar::new(39_000_000.0));
    v.policy.capacity_timestamp = Some(Scalar::new(39_000_000.0)); v
}
fn entry() -> EntryFacts {
    EntryFacts { resume_context_absent: true,
        peer: PeerFacts { exact_peer: true, current_generation: 1 },
        capture: CaptureFacts { source_present: true, sink_present: true,
            capture_authorization_valid: true, forwarding_authorization_valid: true,
            sink_allows_active_use: true }, automatically_suspended: false }
}
fn report() -> Report {
    Report { peer: 99, capture_active: false, automatically_suspended: true,
        bandwidth: Some(Scalar::new(306_000.0)), current_rtt: Some(Scalar::new(0.004)),
        observation: Observation::Measurement { fingerprint: [0x6161_6161_6161_6161; 8],
            fingerprint_length: 64, total_bits: 0.016_f64.to_bits(), responses: 4 },
        collection_sequence: Some(40), strict: false,
        route: RouteFacts { incoming_present: true, equal_to_retained: true },
        packets: Some(40), delay: Some(Scalar::new(0.0)),
        native_timestamp: Some(Scalar::new(40_000_000.0)), observed_at: 500 * MS }
}
fn case(v: Owner) -> Case { Case { owner: v, entry: entry(), report: Some(report()), capacity: false,
    allows_resume: false, expiry_at: 500 * MS, generation: 1, revision: 57 } }
fn inactive(mut e: EntryFacts, bit: usize) -> EntryFacts {
    match bit { 0 => e.capture.source_present = false, 1 => e.capture.sink_present = false,
        2 => e.capture.capture_authorization_valid = false,
        3 => e.capture.forwarding_authorization_valid = false,
        4 => e.capture.sink_allows_active_use = false, _ => panic!("fixture bit") }; e
}
fn probe(mut v: Owner) -> Owner {
    v.policy.tier = Tier::AudioPriority; v.policy.probe_origin = Some(Tier::AudioPriority);
    v.policy.probe_deadline = Some(3_500 * MS); v.policy.probe_maximum = Some(612_000);
    v.policy.probe_grace = 7; v.policy.capacity_bandwidth_high = Some(Scalar::new(306_000.0));
    v.policy.capacity_sample = Some(CapacitySample { packets: Some(30), delay: Some(Scalar::new(0.0)) }); v
}
fn healthy(mut v: Owner) -> Owner {
    let r = &mut v.policy.rtt.raw;
    r.baseline_present = 1; r.baseline_bits = 0.004_f64.to_bits(); r.disposition = 2;
    r.health = 1; r.uses_native = 1; r.permits_initial = 0; r.distinct_count = 3;
    r.last_measured_present = 1; r.last_measured_bits = 0.004_f64.to_bits();
    r.advancement_present = 1; r.age_present = 1; r.watermark_present = 1;
    r.fence_present = 1; r.fence_current_present = 1;
    r.watermark = crate::rtt_evidence::RawMeasurement { fingerprint_words: [0x6161_6161_6161_6161; 8],
        total_bits: 0.012_f64.to_bits(), responses: 3 };
    r.fence = r.watermark; r.fence_current_bits = 0.004_f64.to_bits();
    v.policy.rtt.last_advancement = Some(0);
    v.policy.queue.packets = Some(30); v.policy.queue.delay_bits = Some(0.0_f64.to_bits());
    v.policy.queue.low_observation = Some(0); v
}
fn fresh(mut p: Policy) -> Policy {
    p.times = AssignmentJournal::default(); p.queue.times = AssignmentJournal::default();
    p.rtt.times = AssignmentJournal::default(); p
}
fn clear(p: &mut Policy, slot: TimeSlot) {
    match slot { TimeSlot::QueueLow | TimeSlot::QueueSoft => { p.queue.times.clear::<i128>(slot); },
        TimeSlot::RttAdvancement => { p.rtt.times.clear::<i128>(slot); },
        _ => { p.times.clear::<i128>(slot); } }
}
fn explicit(slot: TimeSlot, delta: i128) -> TimeEdit {
    let _ = slot; TimeEdit::Set(Origin { source: TimeSource::Explicit(ExplicitTime::PolicyObservedAt), delta })
}
fn stamp(p: &mut Policy, slot: TimeSlot, value: i128, delta: i128) {
    let origin = Some(Origin { source: TimeSource::Explicit(ExplicitTime::PolicyObservedAt), delta });
    match slot { TimeSlot::QueueLow | TimeSlot::QueueSoft => { p.queue.times.set(slot, value, origin); },
        TimeSlot::RttAdvancement => { p.rtt.times.set(slot, value, origin); },
        _ => { p.times.set(slot, value, origin); } }
}

// Independent literal native currentRecommendation rule. Profiles are input
// values; this is not Policy::recommendation/current_recommendation or a reducer.
fn recommendation(p: Policy) -> Recommendation {
    let index = p.tier as usize; let profile = p.demand.profiles[index];
    let mut r = Recommendation { tier: p.tier, maximum_video: profile.maximum_video,
        maximum_total: profile.maximum_total, fps: p.base_fps.min([60,45,30,20,10,5,2,1][index]),
        scale: Scalar::new([1.0,1.25,1.5,2.0,3.0,4.0,8.0,12.0][index]) };
    if let Some(promotion) = p.promotion { if promotion.tier == p.tier { r.maximum_total = promotion.maximum_total; } }
    if p.probe_origin.is_some() { if let Some(cap) = p.probe_maximum {
        r.maximum_video = p.maximum_tier_video; r.maximum_total = cap;
    } }
    let startup = !p.startup_disproved && p.startup_peer.is_some() && p.startup_show.is_some()
        && p.peer == p.startup_peer && p.floor_show == p.startup_show && (p.floor_reserved || p.floor_active);
    if startup { let pixel_fps = (r.fps as f64 / (r.scale.value() * r.scale.value())).floor() as i64;
        r.fps = r.fps.min(5.min(r.fps).max(pixel_fps)); r.scale = Scalar::new(1.0); }
    r
}
fn floor(p: Policy, input: Report) -> FloorDiagnostics {
    // These fixtures use nil witnesses except the explicit floor-admission case.
    let first = p.floor_first_witness.map(|w| w.bandwidth);
    let current = input.bandwidth.filter(|b| b.value().is_finite() && b.value() > 0.0);
    let trend = match (current, first) { (Some(a), Some(b)) => if a.value() < b.value() { Trend::Falling }
        else if a.0 == b.0 { Trend::Flat } else { Trend::Rising }, _ => Trend::Unknown };
    FloorDiagnostics { show_epoch: p.floor_show, reserved: p.floor_reserved, active: p.floor_active,
        consumed: p.floor_attempt_consumed, disproved: p.below_reserve_disproved,
        cooldown_remaining: p.probe_cooldown, collection_sequence: input.collection_sequence,
        previous_regular_sequence: p.floor_regular_sequence,
        previous_regular_report_microseconds: p.floor_regular_timestamp.map(|x| x.value() as u64),
        capacity_report_microseconds: p.capacity_timestamp.map(|x| x.value() as u64),
        native_report_microseconds: input.native_timestamp.map(|x| x.value() as u64),
        current_bandwidth: current, first_bandwidth: first,
        witness_age_microseconds: p.floor_first_witness.map(|w| ((input.observed_at - w.observed_at) / (MS / 1_000)) as u64),
        before_total: recommendation(p).maximum_total, proposed_total: recommendation(p).maximum_total,
        trend, identity: FloorIdentity::NotChecked, reason: FloorReason::NotEvaluated,
        queue_kind: QueueKind::NotChecked, queue_microseconds: None,
        rtt_disposition: None, rtt_allows_upgrade: None }
}
fn capacity(p: Policy, input: Report, reason: CapacityReason) -> CapacityDiagnostics {
    CapacityDiagnostics { reason, origin: p.probe_origin, collection_sequence: input.collection_sequence,
        previous_native_microseconds: p.capacity_timestamp.map(|x| x.value() as u64),
        native_microseconds: input.native_timestamp.map(|x| x.value() as u64),
        before_total: recommendation(p).maximum_total, proposed_total: recommendation(p).maximum_total,
        collapse_threshold: None, delta_packets: None, delta_delay_microseconds: None, average_queue_microseconds: None }
}
fn prepared(c: Case, p: Policy, lane: ProposalLane, active: bool, changed: Option<Recommendation>,
    route: RouteAction, f: Option<FloorDiagnostics>, d: Option<CapacityDiagnostics>) -> Prepared {
    Prepared { policy: p, source_generation: c.generation, expected_revision: c.revision,
        applying_revision: c.revision, lane, capture_active: active, capacity_only: c.capacity,
        changed, recommendation: changed.unwrap_or_else(|| recommendation(p)), route_action: route,
        floor_diagnostics: f, capacity_diagnostics: d }
}
fn wire(v: Owner) -> Vec<state_codec::Atom> {
    let w = state_codec::encode_owner(v, state_codec::RESULT).unwrap();
    assert_eq!(w.header.count, 179); assert_eq!(w.atoms.len(), 179); w.atoms
}
fn owner_unchanged(actual: Owner, expected: Owner) {
    assert_eq!(wire(actual), wire(expected), "every stored owner atom, including opaque tail");
    for slot in SLOTS { assert_eq!(actual.times.edit(slot), expected.times.edit(slot));
        assert_eq!(actual.times.origin(slot), expected.times.origin(slot));
        assert_eq!(actual.policy.time_edit(slot), expected.policy.time_edit(slot));
        for (a,e) in [(actual.policy.times,expected.policy.times),
            (actual.policy.queue.times,expected.policy.queue.times),(actual.policy.rtt.times,expected.policy.rtt.times)] {
            assert_eq!(a.edit(slot),e.edit(slot)); assert_eq!(a.origin(slot),e.origin(slot));
            assert_eq!(a.valid(),e.valid());
        }
    }
}
fn full_prepared(c: Case, actual: Prepared, expected: Prepared) {
    let mut a = c.owner; let mut e = c.owner; a.policy = actual.policy; e.policy = expected.policy;
    assert_eq!(wire(a), wire(e), "complete proposed168 and unchanged owner11");
    for slot in SLOTS { assert_eq!(actual.policy.time_edit(slot), expected.policy.time_edit(slot), "{slot:?}");
        for (a,e) in [(actual.policy.times,expected.policy.times),
            (actual.policy.queue.times,expected.policy.queue.times),(actual.policy.rtt.times,expected.policy.rtt.times)] {
            assert_eq!(a.edit(slot),e.edit(slot)); assert_eq!(a.origin(slot),e.origin(slot));
            assert_eq!(a.valid(),e.valid());
        }
    }
    assert_eq!(actual.source_generation, expected.source_generation);
    assert_eq!(actual.expected_revision, expected.expected_revision);
    assert_eq!(actual.applying_revision, expected.applying_revision);
    assert_eq!(actual.lane, expected.lane); assert_eq!(actual.capture_active, expected.capture_active);
    assert_eq!(actual.capacity_only, expected.capacity_only); assert_eq!(actual.changed, expected.changed);
    assert_eq!(actual.recommendation, expected.recommendation); assert_eq!(actual.route_action, expected.route_action);
    assert_eq!(actual.floor_diagnostics, expected.floor_diagnostics);
    assert_eq!(actual.capacity_diagnostics, expected.capacity_diagnostics);
}
fn invoke(c: Case, clock: &mut NativeCuts) -> Result<Option<Prepared>, Denied> {
    c.owner.try_prepare_proposal(c.generation, c.revision, c.entry, c.report, c.capacity,
        c.allows_resume, c.expiry_at, clock, Dependencies::default())
}
fn success(c: Case, expected: Prepared, plan: &[ClockSite]) {
    let before = c.owner; let mut clock = NativeCuts::default();
    full_prepared(c, invoke(c, &mut clock).unwrap().expect("unpublished proposal"), expected);
    assert_eq!(clock.calls, plan); owner_unchanged(c.owner, before);
    for ordinal in 0..plan.len() { let mut denied = NativeCuts { fail: Some(ordinal), ..Default::default() };
        assert_eq!(invoke(c, &mut denied), Err(Denied::Cut { ordinal, site: plan[ordinal] }));
        assert_eq!(denied.calls, plan[..=ordinal], "no cut or defer after the exact denial");
        owner_unchanged(c.owner, before);
    }
}
fn none(c: Case) { let before = c.owner; let mut clock = NativeCuts { fail: Some(0), ..Default::default() };
    assert_eq!(invoke(c, &mut clock), Ok(None)); assert!(clock.calls.is_empty());
    assert!(clock.arithmetic.is_empty()); owner_unchanged(c.owner, before); }

// Only the literal reset/failure branches selected by these fixtures. Not a
// report evaluator: it cannot bind, admit a report, choose a lane or take a cut.
fn tier_reset(p: &mut Policy) {
    p.floor_first_witness = None; p.capacity_sample = None; p.capacity_bandwidth_high = None; p.promotion = None;
    p.queue.pressure_count = 0; p.queue.low_observation = None; p.queue.soft_observation = None;
    for slot in [TimeSlot::FloorWitness,TimeSlot::PromotionDeadline,TimeSlot::QueueLow,TimeSlot::QueueSoft] { clear(p, slot); }
}
fn failed_probe(mut p: Policy, failures: i64, cooldown: i64) -> Policy {
    p = fresh(p); p.tier = Tier::AudioPriority; tier_reset(&mut p);
    p.probe_origin = None; p.probe_confirmed = None; p.probe_qualification_at = None;
    p.probe_best = None; p.probe_maximum = None; p.probe_healthy = 0; p.probe_grace = 0;
    p.probe_deadline = None; p.limited_upgrades = 0; p.probe_failures = failures; p.probe_cooldown = cooldown;
    clear(&mut p,TimeSlot::ProbeQualification); clear(&mut p,TimeSlot::ProbeDeadline); p
}
fn empty_path_reset(p: &mut Policy) {
    tier_reset(p); p.probe_confirmed = None; p.probe_qualification_at = None;
    p.floor_seed = None; p.healthy_upgrades = 0; p.bandwidth_downgrades = 0;
    p.queue.packets = None; p.queue.delay_bits = None;
    p.unavailable_samples = 0; p.positive_bootstrap = 0; p.limited_upgrades = 0;
    p.probe_healthy = 0; p.probe_grace = 0; p.probe_deadline = None; p.probe_origin = None;
    p.probe_best = None; p.probe_maximum = None; p.below_reserve_disproved = false;
    p.resume_restoration = None; p.probe_cooldown = 0; p.probe_failures = 0;
    p.rtt.raw = crate::rtt_evidence::RawState::initial(); p.rtt.raw.permits_initial = 0;
    p.bandwidth_unavailable = false; p.last_latency_pressure = false;
    p.last_positive_suspension_pressure = false; p.last_average_delay = None;
    clear(p,TimeSlot::ProbeQualification); clear(p,TimeSlot::ProbeDeadline);
}
fn regular_sparse(c: Case, suspended: bool) -> (Case, Prepared, Vec<ClockSite>) {
    let mut c = c; c.entry = inactive(c.entry,0); c.entry.automatically_suspended = suspended;
    c.allows_resume = true; let mut r = c.report.unwrap(); r.automatically_suspended = !suspended;
    r.bandwidth = None; r.current_rtt = None; r.observation = Observation::LegacyAbsent;
    r.packets = None; r.delay = None; c.report = Some(r);
    let mut p = fresh(c.owner.policy); p.consumed_sequence = Some(40);
    p.floor_regular_sequence = Some(40); p.floor_regular_timestamp = r.native_timestamp;
    p.startup_sparse_deadline = None; clear(&mut p,TimeSlot::SparseDeadline);
    p.floor_first_witness = None; clear(&mut p,TimeSlot::FloorWitness);
    let mut d = floor(c.owner.policy,r); d.identity = FloorIdentity::Fresh; d.reason = FloorReason::InactiveVisibility;
    let plan = if suspended { p.rtt.raw.uses_native = 1; p.bandwidth_unavailable = true;
        p.unavailable_samples = 1; p.queue.low_observation = None; p.queue.soft_observation = None;
        clear(&mut p,TimeSlot::QueueLow); clear(&mut p,TimeSlot::QueueSoft);
        d.queue_kind = QueueKind::UnavailableOrReset; d.rtt_disposition = Some(6); d.rtt_allows_upgrade = Some(false);
        vec![]
    } else { p.startup_peer = None; p.startup_show = None; p.startup_disproved = false;
        p.tier = Tier::Survival; empty_path_reset(&mut p);
        p.suspension_pressure = 0; p.stable_resume = 0; p.maximum_resume = 0;
        vec![Q,E,A,E,A] };
    p.capacity_timestamp = r.native_timestamp; p.capacity_sample = None; p.capacity_bandwidth_high = None;
    d.proposed_total = recommendation(p).maximum_total;
    let expected = prepared(c,p,ProposalLane::Regular,false,None,RouteAction::Retain,Some(d),None);
    (c,expected,plan)
}

#[test]
fn preparation_clock_entry_resume_context_guard_zero_cuts() { let mut c = case(probe(owner())); c.entry.resume_context_absent = false; none(c); }
#[test]
fn preparation_clock_entry_exact_peer_guard_zero_cuts() { let mut c = case(probe(owner())); c.entry.peer.exact_peer = false; none(c); }
#[test]
fn preparation_clock_entry_generation_guard_zero_cuts() { let mut c = case(probe(owner())); c.entry.peer.current_generation = 2; none(c); }
#[test]
fn preparation_clock_entry_revision_guard_zero_cuts() { let mut c = case(probe(owner())); c.revision = 58; none(c); }
#[test]
fn preparation_clock_all_five_capture_guards_without_resume_zero_cuts() {
    for bit in 0..5 { let mut c = case(probe(owner())); c.entry = inactive(c.entry,bit); none(c); }
}
#[test]
fn preparation_clock_fallback_resume_permits_each_inactive_capture_fact() {
    for bit in 0..5 { let mut c = case(owner()); c.entry = inactive(c.entry,bit); c.allows_resume = true; c.capacity = true;
        let p = fresh(c.owner.policy); let d = capacity(p,c.report.unwrap(),CapacityReason::Inactive);
        success(c,prepared(c,p,ProposalLane::Capacity,false,None,RouteAction::Retain,None,Some(d)),&[]); }
}
#[test]
fn preparation_clock_capacity_overrides_report_peer_and_active_from_entry() {
    let mut c = case(owner()); c.capacity = true;
    let p = fresh(c.owner.policy); let d = capacity(p,c.report.unwrap(),CapacityReason::RejectedReport);
    success(c,prepared(c,p,ProposalLane::Capacity,true,None,RouteAction::Retain,None,Some(d)),&[]);
}
#[test]
fn preparation_clock_capacity_missing_order_never_enters_regular_strict_lane() {
    let mut c = case(probe(owner())); c.capacity = true; c.report.as_mut().unwrap().collection_sequence = None;
    let p = fresh(c.owner.policy); let d = capacity(p,c.report.unwrap(),CapacityReason::RejectedReport);
    success(c,prepared(c,p,ProposalLane::Capacity,true,None,RouteAction::Retain,None,Some(d)),&[]);
}
#[test]
fn preparation_clock_regular_forces_strict_even_when_input_is_legacy_unordered() {
    let mut c = case(owner()); c.report.as_mut().unwrap().collection_sequence = None;
    let mut p = fresh(c.owner.policy); p.rtt.raw.uses_native = 1; p.floor_first_witness = None;
    clear(&mut p,TimeSlot::FloorWitness);
    let mut d = floor(c.owner.policy,c.report.unwrap()); d.identity = FloorIdentity::RejectedOrder; d.reason = FloorReason::RejectedOrder;
    success(c,prepared(c,p,ProposalLane::Regular,true,None,RouteAction::Retain,Some(d),None),&[E,A]);
}
#[test]
fn preparation_clock_regular_entry_unsuspended_overrides_report_and_resets_hidden() {
    let (c,p,plan) = regular_sparse(case(owner()),false); success(c,p,&plan);
}
#[test]
fn preparation_clock_regular_entry_suspended_overrides_report_without_hidden_reset() {
    let (c,p,plan) = regular_sparse(case(owner()),true); success(c,p,&plan);
}
#[test]
fn preparation_clock_regular_startup_timestamp_rejection_complete_proposal_zero_cut() {
    let mut v = owner(); v.policy.floor_show = Some(11); v.policy.floor_reserved = true; v.policy.floor_active = true;
    v.policy.startup_peer = Some(1); v.policy.startup_show = Some(11);
    let mut c = case(v); c.report.as_mut().unwrap().native_timestamp = Some(Scalar::new(39_000_000.0));
    let mut p = fresh(c.owner.policy); p.consumed_sequence = Some(40); p.floor_first_witness = None;
    clear(&mut p,TimeSlot::FloorWitness);
    let mut d = floor(c.owner.policy,c.report.unwrap()); d.identity = FloorIdentity::RejectedTimestamp; d.reason = FloorReason::RejectedTimestamp;
    success(c,prepared(c,p,ProposalLane::Regular,true,None,RouteAction::Retain,Some(d),None),&[]);
}
#[test]
fn preparation_clock_rebases_only_proposed_policy_journals_not_stored_owner() {
    let mut v = owner(); v.policy.probe_deadline = Some(3_500 * MS);
    v.policy.times.set(TimeSlot::ProbeDeadline,3_500 * MS,Some(Origin::explicit(ExplicitTime::CadenceObservation)));
    v.policy.queue.times.set(TimeSlot::QueueLow,0,Some(Origin::explicit(ExplicitTime::EvidencePreparation)));
    v.times.set(TimeSlot::EvidenceTime,v.last_evidence.unwrap(),Some(Origin::explicit(ExplicitTime::EvidencePreparation)));
    let mut c = case(v); c.capacity = true; let p = fresh(v.policy);
    let d = capacity(p,c.report.unwrap(),CapacityReason::RejectedReport);
    success(c,prepared(c,p,ProposalLane::Capacity,true,None,RouteAction::Retain,None,Some(d)),&[]);
}
#[test]
fn preparation_clock_nil_expiry_noop_matches_applied_recommendation_zero_cut() {
    let mut v = owner(); v.applied = Some(recommendation(v.policy)); let mut c = case(v); c.report = None; none(c);
}
#[test]
fn preparation_clock_nil_expiry_without_applied_returns_full_expiry_not_capacity() {
    let mut v = owner(); v.applied = None; let mut c = case(v); c.report = None; c.capacity = true;
    success(c,prepared(c,fresh(v.policy),ProposalLane::Expiry,true,None,RouteAction::Retain,None,None),&[]);
}
#[test]
fn preparation_clock_nil_expiry_new_terminal_fault_survives_equal_recommendation() {
    let mut v = owner(); v.policy.rtt.raw.advancement_present = 1; v.applied = Some(recommendation(v.policy));
    let mut c = case(v); c.report = None; let mut p = fresh(v.policy); p.rtt.faulted = true;
    p.promotion = None; clear(&mut p,TimeSlot::PromotionDeadline);
    success(c,prepared(c,p,ProposalLane::Expiry,true,None,RouteAction::Retain,None,None),&[]);
}
#[test]
fn preparation_clock_nil_expiry_existing_terminal_fault_does_not_reapply_equal_sender() {
    let mut v = owner(); v.policy.rtt.faulted = true; v.applied = Some(recommendation(v.policy));
    let mut c = case(v); c.report = None; none(c);
}
#[test]
fn preparation_clock_nil_expiry_promotion_boundary_uses_explicit_time_without_cut() {
    let mut v = owner(); v.policy.tier = Tier::Survival;
    v.policy.promotion = Some(Promotion { tier: Tier::Survival, maximum_total: 1_073_000, deadline: 2_500 * MS });
    for delta in [-1,0,1] { let mut c = case(v); c.report = None; c.expiry_at = 2_500 * MS + delta;
        let mut p = fresh(v.policy); let changed = if delta >= 0 { p.promotion = None;
            clear(&mut p,TimeSlot::PromotionDeadline); Some(recommendation(p)) } else { None };
        success(c,prepared(c,p,ProposalLane::Expiry,true,changed,RouteAction::Retain,None,None),&[]); }
}
#[test]
fn preparation_clock_nil_expiry_probe_q_then_complete_unpublished_negative() {
    let v = probe(owner()); let mut c = case(v); c.report = None; c.expiry_at = 3_500 * MS;
    let p = failed_probe(v.policy,1,16); success(c,prepared(c,p,ProposalLane::Expiry,true,
        Some(recommendation(p)),RouteAction::Retain,None,None),&[Q]);
}
#[test]
fn preparation_clock_capacity_expiry_precedes_missing_identity_and_full_diagnostics() {
    let v = probe(owner()); let mut c = case(v); c.capacity = true;
    { let r = c.report.as_mut().unwrap(); r.observed_at = 3_500 * MS; r.collection_sequence = None; r.native_timestamp = None; }
    let p = failed_probe(v.policy,1,16); let mut d = capacity(v.policy,c.report.unwrap(),CapacityReason::Expired);
    d.proposed_total = recommendation(p).maximum_total;
    success(c,prepared(c,p,ProposalLane::Capacity,true,Some(recommendation(p)),RouteAction::Retain,None,Some(d)),&[Q]);
}
#[test]
fn preparation_clock_regular_missing_sequence_e_a_q_order_and_original_baseline() {
    let mut v = probe(owner()); v.policy.probe_deadline = Some(500 * MS);
    let mut c = case(v); c.report.as_mut().unwrap().collection_sequence = None;
    let mut p = failed_probe(v.policy,1,16); p.rtt.raw.uses_native = 1;
    let mut d = floor(v.policy,c.report.unwrap()); d.identity = FloorIdentity::RejectedOrder; d.reason = FloorReason::RejectedOrder;
    d.proposed_total = recommendation(p).maximum_total;
    success(c,prepared(c,p,ProposalLane::Regular,true,Some(recommendation(p)),RouteAction::Retain,Some(d),None),&[E,A,Q]);
}
#[test]
fn preparation_clock_regular_route_revert_q_q_e_a_has_no_published_partial_owner() {
    let v = probe(owner()); let mut c = case(v); { let r = c.report.as_mut().unwrap();
        r.route.equal_to_retained = false; r.bandwidth = None; r.current_rtt = None;
        r.observation = Observation::Unavailable; r.packets = None; r.delay = None; }
    let r = c.report.unwrap(); let mut p = fresh(v.policy); empty_path_reset(&mut p);
    p.consumed_sequence = Some(40); p.floor_regular_sequence = Some(40); p.floor_regular_timestamp = r.native_timestamp;
    p.startup_sparse_deadline = None; clear(&mut p,TimeSlot::SparseDeadline);
    p.rtt.raw.uses_native = 1; p.bandwidth_unavailable = true; p.unavailable_samples = 1;
    p.capacity_timestamp = r.native_timestamp;
    let mut d = floor(v.policy,r); d.identity = FloorIdentity::Fresh; d.reason = FloorReason::InactiveVisibility;
    d.queue_kind = QueueKind::UnavailableOrReset; d.rtt_disposition = Some(6); d.rtt_allows_upgrade = Some(false);
    d.proposed_total = recommendation(p).maximum_total;
    success(c,prepared(c,p,ProposalLane::Regular,true,None,RouteAction::CopyIncoming,Some(d),None),&[Q,Q,E,A]);
}
#[test]
fn preparation_clock_regular_bind_hidden_ten_cuts_exact_full_proposal() {
    let mut v = owner(); v.policy.peer = Some(7); let mut c = case(v); c.entry = inactive(c.entry,0); c.allows_resume = true;
    { let r = c.report.as_mut().unwrap(); r.route.incoming_present = false;
        r.bandwidth = None; r.current_rtt = None; r.observation = Observation::Unavailable; r.packets = None; r.delay = None; }
    let r = c.report.unwrap(); let mut p = fresh(v.policy); empty_path_reset(&mut p);
    p.peer = Some(1); p.tier = Tier::Survival; p.route_present = false;
    p.floor_show = None; p.floor_reserved = false; p.floor_active = false; p.floor_attempt_consumed = false;
    p.floor_probe_cancelled = false; p.floor_regular_sequence = None; p.floor_regular_timestamp = None;
    p.floor_cooldown_at = None; p.capacity_sequence = None; p.capacity_timestamp = None;
    p.startup_peer = None; p.startup_show = None; p.startup_disproved = false; p.startup_sparse_deadline = None;
    p.rtt.last_advancement = None; clear(&mut p,TimeSlot::RttAdvancement);
    clear(&mut p,TimeSlot::FloorCooldown); clear(&mut p,TimeSlot::SparseDeadline);
    // Diagnostics are captured after bind, before regular identity consumption.
    let mut d = floor(p,r); d.identity = FloorIdentity::Fresh; d.reason = FloorReason::InactiveVisibility;
    p.consumed_sequence = Some(40); p.floor_regular_sequence = Some(40); p.floor_regular_timestamp = r.native_timestamp;
    p.capacity_timestamp = r.native_timestamp;
    success(c,prepared(c,p,ProposalLane::Regular,false,None,RouteAction::Clear,Some(d),None),&[Q,E,A,E,A,Q,E,A,E,A]);
}

fn advanced_primary(p: &mut Policy, r: Report) {
    // Literal pinned native RTT advanced-same-pair result; distinct_count stays
    // saturated3, rather than using the proposal reducer as an expected oracle.
    let raw = &mut p.rtt.raw; raw.watermark = crate::rtt_evidence::RawMeasurement {
        fingerprint_words: [0x6161_6161_6161_6161;8], total_bits: 0.016_f64.to_bits(), responses: 4 };
    raw.fence = raw.watermark; raw.uses_native = 1; raw.permits_initial = 0;
    raw.age_seconds = 0; raw.age_attoseconds = 0; raw.disposition = 2;
    p.rtt.last_advancement = Some(r.observed_at); stamp(p,TimeSlot::RttAdvancement,r.observed_at,0);
    p.queue.packets = r.packets; p.queue.delay_bits = r.delay.map(|x|x.0);
    p.queue.low_observation = Some(r.observed_at); p.queue.soft_observation = None;
    stamp(p,TimeSlot::QueueLow,r.observed_at,0); clear(p,TimeSlot::QueueSoft);
    p.last_average_delay = Some(Scalar::new(r.delay.unwrap().value() / 10.0));
    p.consumed_sequence = Some(40); p.floor_regular_sequence = Some(40); p.floor_regular_timestamp = r.native_timestamp;
}
#[test]
fn preparation_clock_floor_probe_set_is_explicit_plus_3500ms_not_a_default_cut() {
    let mut v = healthy(owner()); v.policy.tier = Tier::AudioPriority;
    v.policy.floor_show = Some(11); v.policy.floor_reserved = true; v.policy.floor_active = true;
    v.policy.positive_bootstrap = 1;
    v.policy.floor_first_witness = Some(FloorWitness { observed_at: 0, bandwidth: Scalar::new(306_000.0) });
    let c = case(v); let r = c.report.unwrap(); let mut p = fresh(v.policy); advanced_primary(&mut p,r);
    p.startup_sparse_deadline = None; clear(&mut p,TimeSlot::SparseDeadline);
    p.probe_origin = Some(Tier::AudioPriority); p.probe_confirmed = None; p.probe_qualification_at = None;
    p.probe_best = None; p.probe_healthy = 0; p.probe_maximum = Some(612_000);
    p.capacity_bandwidth_high = r.bandwidth; p.capacity_growth_veto = false; p.promotion = None;
    p.probe_grace = 7; p.probe_deadline = Some(4_000 * MS); p.limited_upgrades = 0; p.healthy_upgrades = 0;
    p.floor_attempt_consumed = true; p.floor_probe_cancelled = false; p.floor_seed = r.bandwidth; p.floor_first_witness = None;
    clear(&mut p,TimeSlot::ProbeQualification); clear(&mut p,TimeSlot::PromotionDeadline); clear(&mut p,TimeSlot::FloorWitness);
    stamp(&mut p,TimeSlot::ProbeDeadline,4_000 * MS,3_500 * MS);
    p.capacity_sample = Some(CapacitySample { packets: r.packets, delay: r.delay }); p.capacity_timestamp = r.native_timestamp;
    let mut d = floor(v.policy,r); d.identity = FloorIdentity::Fresh; d.reason = FloorReason::Admitted;
    d.queue_kind = QueueKind::Measured; d.queue_microseconds = Some(0); d.rtt_disposition = Some(2); d.rtt_allows_upgrade = Some(true);
    d.proposed_total = 612_000;
    let out = prepared(c,p,ProposalLane::Regular,true,Some(recommendation(p)),RouteAction::Retain,Some(d),None);
    assert_eq!(out.policy.time_edit(TimeSlot::ProbeDeadline),explicit(TimeSlot::ProbeDeadline,3_500 * MS)); success(c,out,&[]);
}
#[test]
fn preparation_clock_probe_completion_q_precedes_explicit_two_second_promotion() {
    let mut v = probe(healthy(owner())); v.policy.tier = Tier::Survival; v.policy.probe_best = Some(Tier::Survival);
    v.policy.probe_healthy = 1; v.policy.probe_qualification_at = Some(0); v.policy.probe_maximum = Some(1_200_000);
    v.policy.positive_bootstrap = 1; let mut c = case(v); { let r = c.report.as_mut().unwrap();
        r.bandwidth = Some(Scalar::new(1_073_000.0)); r.delay = Some(Scalar::new(0.01)); }
    let r = c.report.unwrap(); let mut p = fresh(v.policy); advanced_primary(&mut p,r);
    p.startup_sparse_deadline = None; clear(&mut p,TimeSlot::SparseDeadline); tier_reset(&mut p);
    p.probe_origin = None; p.probe_best = None; p.probe_maximum = None; p.probe_confirmed = None;
    p.probe_qualification_at = None; p.probe_healthy = 0; p.probe_grace = 0; p.probe_deadline = None;
    p.limited_upgrades = 0; p.below_reserve_disproved = false; p.resume_restoration = None;
    p.probe_cooldown = 0; p.probe_failures = 0; p.floor_seed = None; p.floor_probe_cancelled = false;
    clear(&mut p,TimeSlot::ProbeQualification); clear(&mut p,TimeSlot::ProbeDeadline);
    p.promotion = Some(Promotion { tier: Tier::Survival, maximum_total: 1_073_000, deadline: 2_500 * MS });
    stamp(&mut p,TimeSlot::PromotionDeadline,2_500 * MS,2 * ATTO); p.capacity_timestamp = r.native_timestamp;
    let mut d = floor(v.policy,r); d.identity = FloorIdentity::Fresh; d.reason = FloorReason::InactiveVisibility;
    d.queue_kind = QueueKind::Measured; d.queue_microseconds = Some(1_000); d.rtt_disposition = Some(2); d.rtt_allows_upgrade = Some(true);
    d.proposed_total = 1_073_000;
    let out = prepared(c,p,ProposalLane::Regular,true,Some(recommendation(p)),RouteAction::Retain,Some(d),None);
    assert_eq!(out.policy.time_edit(TimeSlot::PromotionDeadline),explicit(TimeSlot::PromotionDeadline,2 * ATTO)); success(c,out,&[Q]);
}
#[test]
fn preparation_clock_consumed_max_failure_denies_after_q_skipped_max_is_opaque() {
    let mut v = probe(owner()); v.policy.probe_failures = i64::MAX;
    let mut c = case(v); c.report = None; c.expiry_at = 3_500 * MS;
    let mut clock = NativeCuts::default(); assert_eq!(invoke(c,&mut clock),Err(Denied::Arithmetic));
    assert_eq!(clock.calls,[Q]); assert_eq!(clock.arithmetic,[false]); owner_unchanged(c.owner,v);
    c.capacity = true; c.report = Some(report()); c.entry = inactive(c.entry,0); c.allows_resume = true;
    let p = fresh(v.policy); let d = capacity(p,c.report.unwrap(),CapacityReason::Inactive);
    success(c,prepared(c,p,ProposalLane::Capacity,false,None,RouteAction::Retain,None,Some(d)),&[]);
}
#[test]
fn preparation_clock_consumed_min_and_negative_one_preserve_native_smart_shift() {
    for (incoming,failures) in [(i64::MIN,i64::MIN+1),(-1,0)] {
        let mut v = probe(owner()); v.policy.probe_failures = incoming; let mut c = case(v); c.report = None; c.expiry_at = 3_500 * MS;
        let p = failed_probe(v.policy,failures,0); success(c,prepared(c,p,ProposalLane::Expiry,true,
            Some(recommendation(p)),RouteAction::Retain,None,None),&[Q]);
    }
}
#[test]
fn preparation_clock_consumed_positive_2pow63_floor_denies_skipped_payload_is_opaque() {
    let mut v = owner(); v.policy.configured_cap = i64::MAX;
    v.policy.promotion = Some(Promotion { tier: Tier::Survival, maximum_total: 1_073_000, deadline: 2_500 * MS });
    let mut c = case(v); c.report.as_mut().unwrap().bandwidth = Some(Scalar::new(9_223_372_036_854_775_808.0));
    let mut clock = NativeCuts::default(); assert_eq!(invoke(c,&mut clock),Err(Denied::Arithmetic));
    assert!(clock.calls.is_empty()); assert_eq!(clock.arithmetic,[false]); owner_unchanged(c.owner,v);
    c.capacity = true; c.entry = inactive(c.entry,0); c.allows_resume = true;
    let p = fresh(v.policy); let d = capacity(p,c.report.unwrap(),CapacityReason::Inactive);
    success(c,prepared(c,p,ProposalLane::Capacity,false,None,RouteAction::Retain,None,Some(d)),&[]);
}
