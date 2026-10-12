//! Independent assignment expectations from native setters, not native effect/capture proof.
use super::dependencies::*;
use super::policy::*;
use super::service::*;
use super::time_assignments::*;

#[derive(Default)]
struct EqualClock { sites: Vec<ClockSite> }
impl ClockFacts for EqualClock {
    fn cut(&mut self, site: ClockSite) -> i128 { self.sites.push(site); 0 }
}
fn explicit(site: ExplicitTime, delta: i128) -> TimeEdit {
    TimeEdit::Set(Origin { source: TimeSource::Explicit(site), delta })
}
fn measurement(responses: u64) -> Observation {
    Observation::Measurement { fingerprint: [0x6161_6161_6161_6161; 8], fingerprint_length: 64,
        total_bits: (responses as f64 * 0.004).to_bits(), responses }
}
fn seed() -> Owner {
    let mut owner = Owner::new(50_000_000, 60, Dependencies::default());
    let p = &mut owner.policy;
    p.peer = Some(1); p.probe_deadline = Some(41); p.probe_qualification_at = Some(42);
    p.promotion = Some(Promotion { tier: p.tier, maximum_total: 40_000_000, deadline: 43 });
    p.floor_first_witness = Some(FloorWitness { observed_at: 44, bandwidth: Scalar::new(306_000.0) });
    p.floor_cooldown_at = Some(45); p.startup_sparse_deadline = Some(46);
    p.queue.low_observation = Some(47); p.queue.soft_observation = Some(48);
    p.rtt.last_advancement = Some(49); p.rtt.raw.advancement_present = 1;
    owner.last_evidence = Some(50); owner.begin_time_assignment_frame(); owner
}
fn prepared(owner: &Owner) -> Prepared {
    let mut policy = owner.policy;
    policy.begin_time_assignment_frame();
    Prepared { policy, source_generation: 1, expected_revision: owner.revision,
        applying_revision: owner.revision, lane: ProposalLane::Regular, capture_active: true,
        capacity_only: false, changed: None, recommendation: policy.current_recommendation(),
        route_action: RouteAction::Retain, floor_diagnostics: None, capacity_diagnostics: None }
}
fn outcome() -> ApplyOutcomeFacts {
    ApplyOutcomeFacts { peer: PeerFacts { exact_peer: true, current_generation: 1 },
        exact_source: true, exact_sink: true, exact_capture_authorization: true,
        exact_forwarding_authorization: true, capture_authorization_valid: true,
        forwarding_authorization_valid: true, sink_allows_active_use: true, exact_base_dimensions: true }
}

#[test]
fn equal_queue_stamps_are_not_retained_coordinates() {
    let deps = Dependencies::default(); let mut queue = PacketQueue::default();
    queue.packets = Some(10); queue.delay_bits = Some(0.0_f64.to_bits());
    queue.low_observation = Some(0); queue.times.begin_current_frame();
    queue.observe(Some(20), Some(Scalar::new(0.0)), false, 0, deps);
    assert_eq!(queue.low_observation, Some(0));
    assert_eq!(queue.times.edit(TimeSlot::QueueLow), explicit(ExplicitTime::PolicyObservedAt, 0));
    queue.times.begin_current_frame();
    queue.observe(Some(20), Some(Scalar::new(0.0)), false, 0, deps);
    assert_eq!(queue.times.edit(TimeSlot::QueueLow), TimeEdit::Retain);
    queue.soft_observation = Some(0); queue.times.begin_current_frame();
    queue.observe(Some(30), Some(Scalar::new(1.5)), false, 0, deps);
    assert_eq!(queue.soft_observation, Some(0));
    assert_eq!(queue.times.edit(TimeSlot::QueueSoft), explicit(ExplicitTime::PolicyObservedAt, 0));
    queue.times.begin_current_frame();
    queue.observe(Some(30), Some(Scalar::new(1.5)), false, 0, deps);
    assert_eq!(queue.times.edit(TimeSlot::QueueSoft), TimeEdit::Retain);
}

#[test]
fn equal_rtt_advancement_is_set_but_duplicate_retains() {
    let deps = Dependencies::default(); let mut rtt = RoundTripTime::default();
    rtt.observe(Some(Scalar::new(0.004)), measurement(1), 0, false, false, deps);
    rtt.times.begin_current_frame();
    rtt.observe(Some(Scalar::new(0.004)), measurement(2), 0, false, false, deps);
    assert_eq!(rtt.last_advancement, Some(0));
    assert_eq!(rtt.times.edit(TimeSlot::RttAdvancement), explicit(ExplicitTime::PolicyObservedAt, 0));
    rtt.times.begin_current_frame();
    rtt.observe(Some(Scalar::new(0.004)), measurement(2), 0, false, false, deps);
    assert_eq!(rtt.times.edit(TimeSlot::RttAdvancement), TimeEdit::Retain);
}

#[test]
fn explicit_absent_clear_and_fault_retention_remain_distinct() {
    let deps = Dependencies::default(); let mut native = EqualClock::default();
    let mut clock = TrackedClock::<_, 15>::new(&mut native);
    let mut queue = PacketQueue::default(); queue.reset(true, &mut clock, deps);
    assert_eq!(queue.times.edit(TimeSlot::QueueLow), TimeEdit::Clear);
    assert_eq!(queue.times.edit(TimeSlot::QueueSoft), TimeEdit::Clear);
    let mut rtt = RoundTripTime::default(); rtt.implicit(5, Observation::LegacyAbsent, &mut clock, deps);
    assert_eq!(rtt.times.edit(TimeSlot::RttAdvancement), TimeEdit::Clear);
    rtt.times.begin_current_frame(); rtt.faulted = true;
    rtt.implicit(5, Observation::LegacyAbsent, &mut clock, deps);
    assert_eq!(rtt.times.edit(TimeSlot::RttAdvancement), TimeEdit::Retain);
    assert_eq!(clock.len(), 5); // Queue, event/apply, event/apply even with owned fault.
    assert_eq!(clock.read(ClockSite::RttEvent, 1), Some(0));
    assert_eq!(clock.read(ClockSite::RttApply, 2), Some(0));
    assert_eq!(clock.read(ClockSite::RttApply, 1), None);
}

#[test]
fn working_origin_copy_flattens_new_assignment_and_checked_delta() {
    let mut journal = AssignmentJournal::default();
    journal.set(TimeSlot::ProbeDeadline, 3_500 * MS,
        Origin::explicit(ExplicitTime::PolicyObservedAt).advanced(3_500 * MS));
    journal.copy(TimeSlot::SparseDeadline, TimeSlot::ProbeDeadline, 3_500 * MS, 0);
    assert_eq!(journal.edit(TimeSlot::SparseDeadline), explicit(ExplicitTime::PolicyObservedAt, 3_500 * MS));
    journal.copy(TimeSlot::FloorCooldown, TimeSlot::SparseDeadline, 4_000 * MS, 500 * MS);
    assert_eq!(journal.edit(TimeSlot::FloorCooldown), explicit(ExplicitTime::PolicyObservedAt, 4_000 * MS));
    journal.set(TimeSlot::ProbeDeadline, 0, Some(Origin { source: TimeSource::Explicit(ExplicitTime::PolicyObservedAt), delta: i128::MAX }));
    journal.copy(TimeSlot::SparseDeadline, TimeSlot::ProbeDeadline, 0, 1);
    assert_eq!(journal.edit(TimeSlot::SparseDeadline), TimeEdit::Invalid);
    journal.clear::<i128>(TimeSlot::SparseDeadline);
    assert_eq!(journal.edit(TimeSlot::SparseDeadline), TimeEdit::Clear);
    assert!(!journal.valid()); // A later overwrite cannot erase the per-frame failure.
    journal.import_prepared(TimeSlot::SparseDeadline, Some(0));
    assert!(!journal.valid());
}

#[test]
fn policy_sparse_copy_uses_frozen_current_deadline_not_output_reference() {
    let deps = Dependencies::default(); let mut p = Policy::new(50_000_000, 60, deps);
    p.peer = Some(1); p.floor_show = Some(1); p.floor_reserved = true;
    p.startup_peer = Some(1); p.startup_show = Some(1); p.probe_deadline = Some(2 * ATTO);
    p.startup_sparse_deadline = p.probe_deadline;
    p.begin_time_assignment_frame();
    let mut native = EqualClock::default(); let mut clock = TrackedClock::<_, 15>::new(&mut native);
    p.update(Report { peer: 1, capture_active: true, automatically_suspended: false,
        bandwidth: None, current_rtt: None, observation: Observation::Unavailable,
        collection_sequence: Some(1), strict: true, route: RouteFacts { incoming_present: false, equal_to_retained: true },
        packets: None, delay: None, native_timestamp: Some(Scalar::new(1.0)), observed_at: 0 }, &mut clock, deps);
    assert_eq!(p.startup_sparse_deadline, Some(2 * ATTO));
    assert_eq!(p.time_edit(TimeSlot::SparseDeadline), TimeEdit::Set(Origin { source: TimeSource::CurrentInput(TimeSlot::ProbeDeadline), delta: 0 }));
}

#[test]
fn nested_reset_clears_only_executed_slots_and_bookkeeping_retains() {
    let mut owner = seed(); let deps = Dependencies::default();
    let mut native = EqualClock::default(); let mut clock = TrackedClock::<_, 15>::new(&mut native);
    owner.policy.reset_incomplete(&mut clock, deps);
    for slot in [TimeSlot::FloorWitness, TimeSlot::PromotionDeadline, TimeSlot::QueueLow, TimeSlot::QueueSoft] {
        assert_eq!(owner.time_edit(slot), TimeEdit::Clear);
    }
    for slot in [TimeSlot::ProbeDeadline, TimeSlot::ProbeQualification, TimeSlot::FloorCooldown,
        TimeSlot::SparseDeadline, TimeSlot::RttAdvancement, TimeSlot::EvidenceTime] {
        assert_eq!(owner.time_edit(slot), TimeEdit::Retain);
    }
    owner.begin_time_assignment_frame();
    owner.apply_native_bookkeeping_cut(super::bookkeeping::NativeBookkeepingCut::PeerStartReturned);
    for slot in SLOTS { assert_eq!(owner.time_edit(slot), TimeEdit::Retain); }
}

#[test]
fn corresponding_prepared_adoption_imports_even_equal_values() {
    let mut owner = seed(); let proposal = prepared(&owner);
    let before = owner.policy;
    owner.final_adopt(proposal, PeerFacts { exact_peer: true, current_generation: 1 });
    assert!(owner.policy.swift_equal(&before, true)); // Provenance cannot alter policy equality.
    for slot in &SLOTS[..9] {
        assert_eq!(owner.time_edit(*slot), TimeEdit::Set(Origin { source: TimeSource::CorrespondingPreparedInput(*slot), delta: 0 }));
    }
    assert_eq!(owner.time_edit(TimeSlot::EvidenceTime), TimeEdit::Retain);
    assert!(ClockProjection::assignment_edits(&owner, None)[9..12].iter().all(Option::is_none));
    owner.begin_time_assignment_frame();
    let mut proposal = prepared(&owner);
    proposal.policy.floor_cooldown_at = Some(200);
    proposal.policy.rtt.last_advancement = None; proposal.policy.rtt.raw.advancement_present = 0;
    owner.final_adopt(proposal, PeerFacts { exact_peer: true, current_generation: 1 });
    assert_eq!(owner.policy.floor_cooldown_at, Some(200));
    assert_eq!(owner.time_edit(TimeSlot::FloorCooldown), TimeEdit::Set(Origin { source: TimeSource::CorrespondingPreparedInput(TimeSlot::FloorCooldown), delta: 0 }));
    assert_eq!(owner.time_edit(TimeSlot::RttAdvancement), TimeEdit::Clear);
    let input = Snapshot { current: [Some(41), Some(42), Some(43), Some(44), Some(45), Some(46),
        Some(47), Some(48), Some(49), None, None, None, Some(50)],
        prepared: [Some(41), Some(42), Some(43), Some(44), Some(200), Some(46),
            Some(47), Some(48), None, None, None, None, None], explicit: None };
    let mut native = EqualClock::default(); let clock = TrackedClock::<_, 15>::new(&mut native);
    assert!(ClockProjection::validate_assignments(&owner, None, &input, &clock).is_ok());
    let wrong_direction = Snapshot { prepared: input.current, ..input };
    assert!(ClockProjection::validate_assignments(&owner, None, &wrong_direction, &clock).is_err());
}

#[test]
fn positive_failure_never_imports_proposed_clock_and_keeps_allowlisted_clear() {
    let deps = Dependencies::default(); let mut owner = seed();
    owner.policy.floor_show = Some(1); owner.policy.probe_origin = Some(Tier::AudioPriority);
    let mut proposal = prepared(&owner); proposal.capacity_only = true;
    proposal.policy.floor_attempt_consumed = true;
    proposal.policy.probe_origin = Some(Tier::AudioPriority);
    proposal.policy.capacity_sequence = Some(1);
    proposal.policy.rtt.last_advancement = Some(999);
    proposal.policy.probe_deadline = Some(998);
    let mut native = EqualClock::default(); let mut clock = TrackedClock::<_, 15>::new(&mut native);
    let result = owner.finish_failure(proposal, outcome(), &mut clock, deps);
    assert_eq!(result.disposition, FailureDisposition::RetainedFastIdentity);
    assert_eq!(owner.policy.rtt.last_advancement, Some(49));
    assert_eq!(owner.policy.probe_deadline, Some(41));
    assert_eq!(owner.time_edit(TimeSlot::FloorWitness), TimeEdit::Clear);
    assert_eq!(owner.time_edit(TimeSlot::RttAdvancement), TimeEdit::Retain);
    assert_eq!(owner.time_edit(TimeSlot::ProbeDeadline), TimeEdit::Retain);
    assert_eq!(clock.len(), 1);
    assert_eq!(clock.read(ClockSite::CopyFence, 0), Some(0));
}

#[test]
fn cadence_max_uses_native_equal_winner_and_old_origin_before_early_return() {
    let mut cadence = Cadence::new(100);
    cadence.begin_time_assignment_frame(); cadence.set_capacity_enabled(false, 100);
    assert_eq!(cadence.times.edit(TimeSlot::CadenceLatest), explicit(ExplicitTime::CadenceObservation, 0));
    assert_eq!(cadence.times.edit(TimeSlot::CadenceCapacity), TimeEdit::Retain);
    cadence.begin_time_assignment_frame(); cadence.take_due(99);
    assert_eq!(cadence.times.edit(TimeSlot::CadenceLatest), TimeEdit::Set(Origin { source: TimeSource::CurrentInput(TimeSlot::CadenceLatest), delta: 0 }));
    assert_eq!(cadence.times.edit(TimeSlot::CadenceRegular), TimeEdit::Retain);
    cadence.begin_time_assignment_frame(); cadence.finish(101);
    assert_eq!(cadence.times.edit(TimeSlot::CadenceLatest), explicit(ExplicitTime::CadenceObservation, 0));
    assert_eq!(cadence.times.edit(TimeSlot::CadenceRegular), TimeEdit::Retain);
}

#[test]
fn cadence_finish_then_enable_composes_original_finish_origin() {
    let owner = Owner::new(50_000_000, 60, Dependencies::default());
    let mut cadence = Cadence::new(0); cadence.in_flight = Some(Sample::Regular);
    cadence.capacity_enabled = true; cadence.next_capacity = Some(200 * MS);
    cadence.begin_time_assignment_frame();
    owner.finish_collection_slot(&mut cadence, 800 * MS, true, true);
    assert_eq!(cadence.next_regular, 1_300 * MS);
    assert_eq!(cadence.times.edit(TimeSlot::CadenceRegular), explicit(ExplicitTime::CadenceObservation, 500 * MS));
    assert_eq!(cadence.next_capacity, None); // Refresh disables AFTER enabled finish assignment.
    assert_eq!(cadence.times.edit(TimeSlot::CadenceCapacity), TimeEdit::Clear);
    cadence.begin_time_assignment_frame(); cadence.set_capacity_enabled(true, 700 * MS);
    assert_eq!(cadence.next_capacity, Some(1_000 * MS));
    assert_eq!(cadence.times.edit(TimeSlot::CadenceCapacity), TimeEdit::Set(Origin { source: TimeSource::CurrentInput(TimeSlot::CadenceLatest), delta: 200 * MS }));
}

#[test]
fn evidence_equal_stamp_and_absent_clear_are_not_final_diff_actions() {
    let deps = Dependencies::default(); let mut owner = seed();
    let mut native = EqualClock::default(); let mut clock = TrackedClock::<_, 15>::new(&mut native);
    owner.prepare_evidence(EvidenceLane::FastSender, 50, &mut clock, deps);
    assert_eq!(owner.last_evidence, Some(50));
    assert_eq!(owner.time_edit(TimeSlot::EvidenceTime), explicit(ExplicitTime::EvidencePreparation, 0));
    owner.last_evidence = None; owner.begin_time_assignment_frame(); owner.stop_sampling_bookkeeping();
    assert_eq!(owner.time_edit(TimeSlot::EvidenceTime), TimeEdit::Clear);
    assert_eq!(clock.len(), 0);
}

struct Snapshot { current: [Option<i128>; 13], prepared: [Option<i128>; 13], explicit: Option<i128> }
impl TimeInputs for Snapshot {
    fn coordinate(&self, source: TimeSource) -> Option<i128> {
        match source {
            TimeSource::CurrentInput(slot) => self.current[slot as usize],
            TimeSource::CorrespondingPreparedInput(slot) => self.prepared[slot as usize],
            TimeSource::Explicit(_) => self.explicit,
            _ => None,
        }
    }
}
#[test]
fn full_projection_validation_rejects_unresolved_or_overflow_without_partial_commit() {
    let mut owner = Owner::new(50_000_000, 60, Dependencies::default());
    owner.begin_time_assignment_frame();
    let mut native = EqualClock::default(); let mut clock = TrackedClock::<_, 1>::new(&mut native);
    let input = Snapshot { current: [None; 13], prepared: [None; 13], explicit: Some(0) };
    assert!(ClockProjection::validate_assignments(&owner, None, &input, &clock).is_ok());
    owner.last_evidence = owner.times.set(TimeSlot::EvidenceTime, 0, Some(Origin::explicit(ExplicitTime::EvidencePreparation)));
    assert!(ClockProjection::validate_assignments(&owner, None, &input, &clock).is_ok());
    let missing = Snapshot { explicit: None, ..input };
    assert!(ClockProjection::validate_assignments(&owner, None, &missing, &clock).is_err());
    owner.times.set(TimeSlot::EvidenceTime, 0, Some(Origin { source: TimeSource::Explicit(ExplicitTime::EvidencePreparation), delta: 1 }));
    let overflow = Snapshot { explicit: Some(i128::MAX), ..missing };
    assert!(ClockProjection::validate_assignments(&owner, None, &overflow, &clock).is_err());
    assert_eq!(owner.last_evidence, Some(0)); // Validator itself writes neither policy nor native state.
    assert_eq!(clock.cut(ClockSite::RttEvent), 0); assert_eq!(clock.cut(ClockSite::RttApply), 0);
    assert!(!clock.valid()); assert_eq!(clock.last_time_source(), TimeSource::Untracked);
    owner.last_evidence = owner.times.clear(TimeSlot::EvidenceTime);
    assert!(ClockProjection::validate_assignments(&owner, None, &input, &clock).is_err());
    owner.begin_time_assignment_frame();
    owner.times.set(TimeSlot::EvidenceTime, 0, None);
    owner.last_evidence = owner.times.clear(TimeSlot::EvidenceTime);
    let mut native = EqualClock::default(); let clock = TrackedClock::<_, 1>::new(&mut native);
    assert!(ClockProjection::validate_assignments(&owner, None, &input, &clock).is_err());
    owner.last_evidence = owner.times.set(TimeSlot::EvidenceTime, 0, Some(Origin::explicit(ExplicitTime::EvidencePreparation)));
    assert!(ClockProjection::validate_assignments(&owner, None, &input, &clock).is_err());
}
