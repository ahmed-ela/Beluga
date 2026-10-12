//! Pure scheduling/evidence and staged service decisions. Actual native resources/effects
//! remain outside this model. No pending global token, fabricated handle or native clock.
use super::dependencies::*;
use super::diagnostics::*;
use super::policy::*;
use super::time_assignments::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Sample { Regular, CapacityOnly }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cadence {
    pub times: AssignmentJournal,
    pub next_regular: RelativeTime, pub next_capacity: Option<RelativeTime>,
    pub capacity_enabled: bool, pub in_flight: Option<Sample>, pub latest: RelativeTime,
}
impl Cadence {
    pub fn new(start: RelativeTime) -> Self {
        let mut times = AssignmentJournal::default();
        times.set(TimeSlot::CadenceRegular, start + 500 * MS, Origin::explicit(ExplicitTime::CadenceStart).advanced(500 * MS));
        times.clear::<RelativeTime>(TimeSlot::CadenceCapacity);
        times.set(TimeSlot::CadenceLatest, start, Some(Origin::explicit(ExplicitTime::CadenceStart)));
        Self { times, next_regular: start + 500 * MS, next_capacity: None, capacity_enabled: false,
            in_flight: None, latest: start }
    }
    pub fn begin_time_assignment_frame(&mut self) { self.times.begin_current_frame(); }
    fn assign_latest(&mut self, now: RelativeTime) {
        // Pinned Swift max(x,y) selects y when equal (public Swift interface21–24).
        let origin = if now >= self.latest { Origin::explicit(ExplicitTime::CadenceObservation) }
            else { self.times.origin(TimeSlot::CadenceLatest) };
        self.times.set(TimeSlot::CadenceLatest, self.latest.max(now), Some(origin));
        self.latest = self.latest.max(now);
    }
    pub fn next_deadline(self) -> RelativeTime { self.next_capacity.map(|v| v.min(self.next_regular)).unwrap_or(self.next_regular) }
    pub fn set_capacity_enabled(&mut self, enabled: bool, now: RelativeTime) {
        self.assign_latest(now);
        if self.capacity_enabled == enabled { return; }
        self.capacity_enabled = enabled;
        self.next_capacity = if enabled { self.times.copy(TimeSlot::CadenceCapacity, TimeSlot::CadenceLatest, self.latest + 200 * MS, 200 * MS) }
            else { self.times.clear(TimeSlot::CadenceCapacity) };
    }
    pub fn take_due(&mut self, now: RelativeTime) -> Option<Sample> {
        self.assign_latest(now);
        if self.in_flight.is_some() { return None; }
        // Supplied now, NOT projected latest: preserve backward-observation distinction.
        let sample = if now >= self.next_regular { Sample::Regular }
            else if self.next_capacity.is_some_and(|deadline| now >= deadline) { Sample::CapacityOnly }
            else { return None; };
        self.in_flight = Some(sample); Some(sample)
    }
    pub fn finish(&mut self, now: RelativeTime) {
        self.assign_latest(now);
        let Some(sample) = self.in_flight.take() else { return; };
        if sample == Sample::Regular {
            self.times.copy(TimeSlot::CadenceRegular, TimeSlot::CadenceLatest, self.latest + 500 * MS, 500 * MS);
            self.next_regular = self.latest + 500 * MS;
        }
        if self.capacity_enabled { self.next_capacity = self.times.copy(TimeSlot::CadenceCapacity, TimeSlot::CadenceLatest, self.latest + 200 * MS, 200 * MS); }
    }
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Freshness { pub minimum: Option<u64> }
impl Freshness {
    pub fn begin(&mut self, minimum: u64) { self.minimum = Some(self.minimum.map(|v| v.max(minimum)).unwrap_or(minimum)); }
    pub fn reset(&mut self) { self.minimum = None; }
    pub fn admits(self, sequence: Option<u64>) -> bool {
        self.minimum.map(|minimum| sequence.is_some_and(|value| value >= minimum)).unwrap_or(true)
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EvidenceLane { FastSender, OrdinaryFallback }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Owner {
    pub times: AssignmentJournal,
    pub policy: Policy, pub revision: u64, pub fast_statistics_available: bool,
    pub evidence_lane: Option<EvidenceLane>, pub last_evidence: Option<RelativeTime>,
    pub freshness: Freshness, pub applied: Option<Recommendation>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PeerFacts { pub exact_peer: bool, pub current_generation: u64 }
impl PeerFacts { fn matches(self, source_generation: u64) -> bool { self.exact_peer && self.current_generation == source_generation } }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CaptureFacts {
    pub source_present: bool, pub sink_present: bool, pub capture_authorization_valid: bool,
    pub forwarding_authorization_valid: bool, pub sink_allows_active_use: bool,
}
impl CaptureFacts {
    pub fn active(self) -> bool {
        self.source_present && self.sink_present && self.capture_authorization_valid
            && self.forwarding_authorization_valid && self.sink_allows_active_use
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EntryFacts {
    pub resume_context_absent: bool, pub peer: PeerFacts,
    pub capture: CaptureFacts, pub automatically_suspended: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ApplyResources {
    pub source_present: bool, pub sink_present: bool, pub capture_authorization_present: bool,
    pub forwarding_authorization_present: bool, pub base_dimensions_present: bool, pub capturer_present: bool,
}
impl ApplyResources {
    fn present(self) -> bool { self.source_present && self.sink_present && self.capture_authorization_present
        && self.forwarding_authorization_present && self.base_dimensions_present && self.capturer_present }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ApplyOutcomeFacts {
    pub peer: PeerFacts,
    pub exact_source: bool, pub exact_sink: bool, pub exact_capture_authorization: bool,
    pub exact_forwarding_authorization: bool, pub capture_authorization_valid: bool,
    pub forwarding_authorization_valid: bool, pub sink_allows_active_use: bool, pub exact_base_dimensions: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProposalLane { Regular, Capacity, Expiry }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Prepared {
    pub policy: Policy, pub source_generation: u64, pub expected_revision: u64,
    pub applying_revision: u64, pub lane: ProposalLane, pub capture_active: bool,
    pub capacity_only: bool,
    pub changed: Option<Recommendation>, pub recommendation: Recommendation,
    pub route_action: RouteAction, pub floor_diagnostics: Option<FloorDiagnostics>,
    pub capacity_diagnostics: Option<CapacityDiagnostics>,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum BeginActive {
    Return { retained_route_action: RouteAction },
    NoNativeApply { prepared: Prepared, retained_route_action: RouteAction },
    Apply { prepared: Prepared, retained_route_action: RouteAction },
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SuccessFence {
    RollbackExactReturnedNativeHandle,
    PermitOutput { fps_changed: bool, accepted: AcceptedApplication },
}
/// Continuation-local pure projection, NOT an opaque/native admission token. No public ctor.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct AcceptedApplication { prepared: Prepared }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FailureDisposition { StaleReturn, RetainedOrdinary, RetainedFastIdentity, AdoptedTerminalNegative }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FailureProjection { pub disposition: FailureDisposition, pub route_action: RouteAction }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InactiveDisposition { StaleReturn, Adopted, BeginNativeResume }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct InactiveProjection { pub disposition: InactiveDisposition, pub route_action: RouteAction }

impl Owner {
    pub fn new(cap: i64, fps: i64, dependencies: Dependencies) -> Self {
        Self { times: AssignmentJournal::default(), policy: Policy::new(cap, fps, dependencies), revision: 0, fast_statistics_available: false,
            evidence_lane: None, last_evidence: None, freshness: Freshness::default(), applied: None }
    }
    pub fn begin_time_assignment_frame(&mut self) {
        self.times.begin_current_frame(); self.policy.begin_time_assignment_frame();
    }
    pub fn time_edit(&self, slot: TimeSlot) -> TimeEdit {
        if slot == TimeSlot::EvidenceTime { self.times.edit(slot) } else { self.policy.time_edit(slot) }
    }
    fn advance(&mut self) { self.revision = self.revision.wrapping_add(1); }
    pub fn prepare_evidence(&mut self, lane: EvidenceLane, now: RelativeTime,
                            clock: &mut impl ClockFacts, dependencies: Dependencies) -> u64 {
        infallible(self.try_prepare_evidence(lane, now, clock, dependencies))
    }
    pub fn try_prepare_evidence<C: TryClockFacts>(&mut self, lane: EvidenceLane, now: RelativeTime,
                            clock: &mut C, dependencies: Dependencies) -> Result<u64, C::Error> {
        let gap = self.last_evidence.is_some_and(|previous| now - previous > 2 * ATTO);
        if self.evidence_lane.is_some_and(|previous| previous != lane || gap) {
            self.policy.try_reset_incomplete(clock, dependencies)?; self.advance();
        }
        self.evidence_lane = Some(lane); self.last_evidence = self.times.set(TimeSlot::EvidenceTime, now, Some(Origin::explicit(ExplicitTime::EvidencePreparation))); Ok(self.revision)
    }
    pub fn bind_native_peer(&mut self, generation: u64, clock: &mut impl ClockFacts, dependencies: Dependencies) -> RouteAction {
        infallible(self.try_bind_native_peer(generation, clock, dependencies))
    }
    pub fn try_bind_native_peer<C: TryClockFacts>(&mut self, generation: u64, clock: &mut C, dependencies: Dependencies) -> Result<RouteAction, C::Error> {
        let bound = self.policy.try_bind(generation, clock, dependencies)?; self.advance();
        self.fast_statistics_available = false; self.evidence_lane = None; self.last_evidence = self.times.clear(TimeSlot::EvidenceTime);
        self.freshness.reset(); self.applied = None;
        Ok(if bound { RouteAction::Clear } else { RouteAction::Retain })
    }
    pub fn route_invalidated(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) -> RouteAction {
        infallible(self.try_route_invalidated(clock, dependencies))
    }
    pub fn try_route_invalidated<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<RouteAction, C::Error> {
        self.advance(); self.policy.try_invalidate_route(clock, dependencies)?;
        self.evidence_lane = None; self.last_evidence = self.times.clear(TimeSlot::EvidenceTime); Ok(RouteAction::Clear)
    }
    pub fn stop_sampling_bookkeeping(&mut self) {
        // Actual stop's EndShow occurs at an earlier native cut; do not fuse the two stages.
        self.fast_statistics_available = false; self.evidence_lane = None; self.last_evidence = self.times.clear(TimeSlot::EvidenceTime);
        self.freshness.reset(); self.advance();
    }
    /// Actual Stop ends the Show before later sampling bookkeeping advances revision.
    /// A clock error may retain the policy's pre-cut negative mutations; no rollback promised.
    pub fn end_show_without_revision(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_end_show_without_revision(clock, dependencies));
    }
    pub fn try_end_show_without_revision<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.policy.try_end_show(clock, dependencies)
    }
    pub fn end_show_and_advance(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_end_show_and_advance(clock, dependencies));
    }
    pub fn try_end_show_and_advance<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.policy.try_end_show(clock, dependencies)?; self.advance();
        Ok(())
    }
    pub fn visibility_command(&mut self, show: bool, generation: u64, native_show_epoch: u64,
                              clock: &mut impl ClockFacts, dependencies: Dependencies) -> RouteAction {
        infallible(self.try_visibility_command(show, generation, native_show_epoch, clock, dependencies))
    }
    pub fn try_visibility_command<C: TryClockFacts>(&mut self, show: bool, generation: u64, native_show_epoch: u64,
                              clock: &mut C, dependencies: Dependencies) -> Result<RouteAction, C::Error> {
        // Native owns command-epoch wrapping, zero->1 correction and async control custody.
        let bound = if show { self.policy.try_reserve_show(generation, native_show_epoch, clock, dependencies)? }
            else { self.policy.try_end_show(clock, dependencies)?; false };
        self.advance(); Ok(if bound { RouteAction::Clear } else { RouteAction::Retain })
    }
    pub fn activate_owned_show(&mut self, generation: u64, epoch: u64) {
        // Called only at native exact peer/generation/Show+actual Active ACK cut.
        self.policy.activate_show(generation, epoch); self.advance();
    }
    pub fn hide_health_revocation(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_hide_health_revocation(clock, dependencies));
    }
    pub fn try_hide_health_revocation<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.policy.try_revoke_for_hide(clock, dependencies)
    }
    pub fn begin_post_resume_epoch(&mut self, minimum_next_native_sequence: Option<u64>,
                                 clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_begin_post_resume_epoch(minimum_next_native_sequence, clock, dependencies));
    }
    pub fn try_begin_post_resume_epoch<C: TryClockFacts>(&mut self, minimum_next_native_sequence: Option<u64>,
                                 clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        if let Some(minimum) = minimum_next_native_sequence { self.freshness.begin(minimum); } else { self.freshness.reset(); }
        self.policy.try_reset_incomplete(clock, dependencies)?; self.evidence_lane = None; self.last_evidence = self.times.clear(TimeSlot::EvidenceTime); self.advance();
        Ok(())
    }
    pub fn resume_accepted(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_resume_accepted(clock, dependencies));
    }
    pub fn try_resume_accepted<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.policy.try_resume_began(clock, dependencies)?; self.advance();
        Ok(())
    }
    pub fn resume_succeeded_without_revision(&mut self) { self.policy.resume_succeeded(); }
    pub fn resume_succeeded_and_advance(&mut self) { self.policy.resume_succeeded(); self.advance(); }
    pub fn resume_failed_and_advance(&mut self, clock: &mut impl ClockFacts, dependencies: Dependencies) {
        infallible(self.try_resume_failed_and_advance(clock, dependencies));
    }
    pub fn try_resume_failed_and_advance<C: TryClockFacts>(&mut self, clock: &mut C, dependencies: Dependencies) -> Result<(), C::Error> {
        self.policy.try_resume_failed(clock, dependencies)?; self.advance();
        Ok(())
    }
    pub fn prepare_proposal(&self, source_generation: u64, expected_revision: u64, entry: EntryFacts,
                            report: Option<Report>, capacity_only: bool, allows_resume: bool,
                            expiry_now: RelativeTime, clock: &mut impl ClockFacts,
                            dependencies: Dependencies) -> Option<Prepared> {
        infallible(self.try_prepare_proposal(source_generation, expected_revision, entry, report,
            capacity_only, allows_resume, expiry_now, clock, dependencies))
    }
    pub fn try_prepare_proposal<C: TryClockFacts>(&self, source_generation: u64, expected_revision: u64, entry: EntryFacts,
                            report: Option<Report>, capacity_only: bool, allows_resume: bool,
                            expiry_now: RelativeTime, clock: &mut C,
                            dependencies: Dependencies) -> Result<Option<Prepared>, C::Error> {
        if !entry.resume_context_absent || !entry.peer.matches(source_generation) || self.revision != expected_revision { return Ok(None); }
        let active = entry.capture.active();
        if !active && !allows_resume { return Ok(None); }
        let mut proposed = self.policy;
        proposed.begin_time_assignment_frame();
        let mut route_action = RouteAction::Retain;
        let mut floor_diagnostics = None; let mut capacity_diagnostics = None;
        let lane;
        let changed;
        if let Some(mut report) = report {
            report.peer = source_generation; report.capture_active = active;
            report.automatically_suspended = entry.automatically_suspended;
            if capacity_only {
                lane = ProposalLane::Capacity;
                let evaluation = proposed.try_update_capacity(report, clock, dependencies)?;
                changed = evaluation.recommendation; capacity_diagnostics = Some(evaluation.diagnostics);
            } else {
                lane = ProposalLane::Regular; report.strict = true;
                let evaluation = proposed.try_update(report, clock, dependencies)?;
                changed = evaluation.recommendation; route_action = evaluation.route_action;
                floor_diagnostics = Some(evaluation.diagnostics);
            }
        } else {
            lane = ProposalLane::Expiry;
            changed = proposed.try_expire(source_generation, active, expiry_now, clock, dependencies)?;
            if changed.is_none() && self.applied == Some(proposed.current_recommendation())
                && !(proposed.terminal_fault() && !self.policy.terminal_fault()) { return Ok(None); }
        }
        let recommendation = changed.unwrap_or_else(|| proposed.current_recommendation());
        Ok(Some(Prepared { policy: proposed, source_generation, expected_revision, applying_revision: expected_revision,
            lane, capture_active: active, capacity_only, changed, recommendation, route_action, floor_diagnostics, capacity_diagnostics }))
    }
    pub fn adopt_inactive(&mut self, prepared: Prepared, peer: PeerFacts, suspended: bool,
                          clock: &mut impl ClockFacts, dependencies: Dependencies) -> InactiveProjection {
        infallible(self.try_adopt_inactive(prepared, peer, suspended, clock, dependencies))
    }
    pub fn try_adopt_inactive<C: TryClockFacts>(&mut self, mut prepared: Prepared, peer: PeerFacts, suspended: bool,
                          clock: &mut C, dependencies: Dependencies) -> Result<InactiveProjection, C::Error> {
        if !peer.matches(prepared.source_generation) || self.revision != prepared.expected_revision {
            return Ok(InactiveProjection { disposition: InactiveDisposition::StaleReturn, route_action: RouteAction::Retain });
        }
        prepared.policy.import_corresponding_prepared_times();
        let decision = prepared.policy.try_suspension_decision(false, suspended, clock, dependencies)?;
        self.policy = prepared.policy; self.advance();
        Ok(InactiveProjection { disposition: if decision == Some(SuspensionDecision::Resume) {
            InactiveDisposition::BeginNativeResume } else { InactiveDisposition::Adopted }, route_action: prepared.route_action })
    }
    pub fn begin_active_apply(&mut self, prepared: Prepared, resources: ApplyResources,
                              clock: &mut impl ClockFacts, dependencies: Dependencies) -> BeginActive {
        infallible(self.try_begin_active_apply(prepared, resources, clock, dependencies))
    }
    pub fn try_begin_active_apply<C: TryClockFacts>(&mut self, mut prepared: Prepared, resources: ApplyResources,
                              clock: &mut C, dependencies: Dependencies) -> Result<BeginActive, C::Error> {
        // No new entry/cancellation guard is invented here: this is the synchronous original
        // continuation from a successfully admitted proposal to its first actual apply await.
        let mut retained_route = RouteAction::Retain;
        if prepared.policy.terminal_fault() {
            let mut retention = self.policy;
            let bound = retention.try_bind(prepared.source_generation, clock, dependencies)?;
            retention.try_retain_fault(prepared.policy, clock, dependencies)?;
            if !retention.swift_equal(&self.policy, !bound) {
                self.policy = retention; self.advance(); prepared.applying_revision = self.revision;
                if bound { retained_route = RouteAction::Clear; }
            }
        }
        if prepared.changed.is_some() || self.applied != Some(prepared.recommendation) {
            if !resources.present() { return Ok(BeginActive::Return { retained_route_action: retained_route }); }
            let mut consumption = self.policy; consumption.retain_attempt(prepared.policy);
            if !consumption.swift_equal(&self.policy, true) {
                self.policy = consumption; self.advance(); prepared.applying_revision = self.revision;
            }
            Ok(BeginActive::Apply { prepared, retained_route_action: retained_route })
        } else { Ok(BeginActive::NoNativeApply { prepared, retained_route_action: retained_route }) }
    }
    fn outcome_current(&self, prepared: Prepared, facts: ApplyOutcomeFacts) -> bool {
        // Literal original short-circuit order. Deliberately no added stopped/cancel/context vote.
        facts.peer.exact_peer && facts.peer.current_generation == prepared.source_generation
            && self.revision == prepared.applying_revision && facts.exact_source && facts.exact_sink
            && facts.exact_capture_authorization && facts.exact_forwarding_authorization
            && facts.capture_authorization_valid && facts.forwarding_authorization_valid
            && facts.sink_allows_active_use && facts.exact_base_dimensions
    }
    pub fn success_fence(&self, prepared: Prepared, facts: ApplyOutcomeFacts) -> SuccessFence {
        if !self.outcome_current(prepared, facts) { return SuccessFence::RollbackExactReturnedNativeHandle; }
        SuccessFence::PermitOutput { fps_changed: self.applied.map(|v| v.fps) != Some(prepared.recommendation.fps),
            accepted: AcceptedApplication { prepared } }
    }
    pub fn record_success_after_native_output(&mut self, accepted: AcceptedApplication) -> Prepared {
        // Native performed the permitted synchronous FPS effect first; no await/recheck inserted.
        self.applied = Some(accepted.prepared.recommendation); accepted.prepared
    }
    pub fn finish_failure(&mut self, prepared: Prepared, facts: ApplyOutcomeFacts,
                          clock: &mut impl ClockFacts, dependencies: Dependencies) -> FailureProjection {
        infallible(self.try_finish_failure(prepared, facts, clock, dependencies))
    }
    pub fn try_finish_failure<C: TryClockFacts>(&mut self, prepared: Prepared, facts: ApplyOutcomeFacts,
                          clock: &mut C, dependencies: Dependencies) -> Result<FailureProjection, C::Error> {
        if !self.outcome_current(prepared, facts) {
            return Ok(FailureProjection { disposition: FailureDisposition::StaleReturn, route_action: RouteAction::Retain });
        }
        let cancelled_floor = self.policy.floor_probe_active() && prepared.policy.floor_probe_cancelled;
        self.policy.retain_startup_terminal(prepared.policy); self.policy.retain_attempt(prepared.policy);
        let terminal_capacity = prepared.capacity_only && self.policy.probe_origin.is_some() && prepared.policy.probe_origin.is_none();
        if cancelled_floor || terminal_capacity {
            self.policy = prepared.policy; self.policy.import_corresponding_prepared_times(); self.advance();
            Ok(FailureProjection { disposition: FailureDisposition::AdoptedTerminalNegative, route_action: prepared.route_action })
        } else if prepared.capacity_only {
            self.policy.try_retain_fast_identity(prepared.policy, clock, dependencies)?; self.advance();
            Ok(FailureProjection { disposition: FailureDisposition::RetainedFastIdentity, route_action: RouteAction::Retain })
        } else {
            self.advance(); Ok(FailureProjection { disposition: FailureDisposition::RetainedOrdinary, route_action: RouteAction::Retain })
        }
    }
    pub fn final_adopt(&mut self, prepared: Prepared, facts: PeerFacts) -> Option<RouteAction> {
        if !facts.matches(prepared.source_generation) || self.revision != prepared.applying_revision { return None; }
        self.policy = prepared.policy; self.policy.import_corresponding_prepared_times(); self.advance(); Some(prepared.route_action)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CollectorExpected { pub generation: u64, pub revision: u64, pub visibility_epoch: u64 }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CollectorLifecycleFacts { pub task_cancelled: bool, pub stopped: bool, pub peer: PeerFacts }
impl CollectorLifecycleFacts {
    fn admitted(self, generation: u64) -> bool { !self.task_cancelled && !self.stopped && self.peer.matches(generation) }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CollectorReportFacts { pub current_visibility_epoch: u64, pub exact_source: bool, pub exact_capture_authorization: bool }
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum CollectorDisposition {
    EndLoop,
    Adapt { report: Option<Report>, expected_revision: u64, capacity_only: bool },
}
impl Owner {
    pub fn take_collection_slot(&self, cadence: &mut Cadence, now: RelativeTime,
                                source_generation: u64, facts: CollectorLifecycleFacts) -> Result<Option<Sample>, ()> {
        if !facts.admitted(source_generation) { return Err(()); }
        Ok(cadence.take_due(now))
    }
    pub fn finish_collection_slot(&self, cadence: &mut Cadence, now: RelativeTime,
                                  capture_source_present: bool, resume_context_absent: bool) {
        // Exact defer order: completion under OLD eligibility first, then eligibility refresh.
        cadence.finish(now);
        cadence.set_capacity_enabled(capture_source_present && resume_context_absent
            && self.fast_statistics_available && self.policy.probe_origin.is_some(), now);
    }
    pub fn collector_capture_gate(&mut self, capture_source_present: bool, resume_context_absent: bool) -> bool {
        if !capture_source_present { self.fast_statistics_available = false; return false; }
        resume_context_absent
    }
    pub fn collected_report(&mut self, expected: CollectorExpected, sample: Sample,
                            lifecycle: CollectorLifecycleFacts, facts: CollectorReportFacts,
                            report: Option<Report>, preparation_now: RelativeTime,
                            clock: &mut impl ClockFacts, dependencies: Dependencies) -> CollectorDisposition {
        infallible(self.try_collected_report(expected, sample, lifecycle, facts, report,
            preparation_now, clock, dependencies))
    }
    pub fn try_collected_report<C: TryClockFacts>(&mut self, expected: CollectorExpected, sample: Sample,
                            lifecycle: CollectorLifecycleFacts, facts: CollectorReportFacts,
                            report: Option<Report>, preparation_now: RelativeTime,
                            clock: &mut C, dependencies: Dependencies) -> Result<CollectorDisposition, C::Error> {
        if !lifecycle.admitted(expected.generation) { return Ok(CollectorDisposition::EndLoop); }
        let capacity = sample == Sample::CapacityOnly;
        if report.is_some_and(|report| self.freshness.admits(report.collection_sequence))
            && facts.current_visibility_epoch == expected.visibility_epoch && facts.exact_source
            && facts.exact_capture_authorization && self.revision == expected.revision {
            if !capacity { self.fast_statistics_available = true; }
            let revision = if capacity { expected.revision }
                else { self.try_prepare_evidence(EvidenceLane::FastSender, preparation_now, clock, dependencies)? };
            Ok(CollectorDisposition::Adapt { report, expected_revision: revision, capacity_only: capacity })
        } else {
            if !capacity { self.fast_statistics_available = false; }
            Ok(CollectorDisposition::Adapt { report: None, expected_revision: self.revision, capacity_only: false })
        }
    }
    pub fn fallback_report(&mut self, whole_report_collected: bool, report: Report,
                           suspended: bool, preparation_now: RelativeTime,
                           clock: &mut impl ClockFacts, dependencies: Dependencies) -> Option<(Option<Report>, u64, bool)> {
        infallible(self.try_fallback_report(whole_report_collected, report, suspended,
            preparation_now, clock, dependencies))
    }
    pub fn try_fallback_report<C: TryClockFacts>(&mut self, whole_report_collected: bool, report: Report,
                           suspended: bool, preparation_now: RelativeTime,
                           clock: &mut C, dependencies: Dependencies) -> Result<Option<(Option<Report>, u64, bool)>, C::Error> {
        let owns = suspended || !self.fast_statistics_available;
        if whole_report_collected && self.freshness.admits(report.collection_sequence) && owns {
            let revision = self.try_prepare_evidence(EvidenceLane::OrdinaryFallback, preparation_now, clock, dependencies)?;
            let mut report = report; report.native_timestamp = None;
            Ok(Some((Some(report), revision, true)))
        } else if !whole_report_collected && owns { Ok(Some((None, self.revision, false))) }
        else { Ok(None) }
    }
}

/// Exact mathematical before/after clock projection, NOT approved native anchor actions.
/// Same mathematical coordinate can arise from retain or stamp; final native action ABI must
/// preserve actual origin/cut/alias custody, and cannot infer it from this snapshot alone.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ClockProjection { pub policy: [Option<RelativeTime>; 9], pub schedule: [Option<RelativeTime>; 3],
    pub last_evidence: Option<RelativeTime> }
impl ClockProjection {
    pub fn observe(owner: &Owner, cadence: Option<Cadence>) -> Self {
        Self { policy: [owner.policy.probe_deadline, owner.policy.probe_qualification_at,
            owner.policy.promotion.map(|p| p.deadline), owner.policy.floor_first_witness.map(|v| v.observed_at),
            owner.policy.floor_cooldown_at, owner.policy.startup_sparse_deadline,
            owner.policy.queue.low_observation, owner.policy.queue.soft_observation, owner.policy.rtt.last_advancement],
            schedule: cadence.map(|c| [Some(c.next_regular), c.next_capacity, Some(c.latest)]).unwrap_or([None; 3]),
            last_evidence: owner.last_evidence }
    }
}

impl ClockProjection {
    /// None means cadence isn't owned by this stage, NOT an instruction to clear a collector.
    pub fn assignment_edits(owner: &Owner, cadence: Option<Cadence>) -> [Option<TimeEdit>; 13] {
        SLOTS.map(|slot| match slot {
            TimeSlot::CadenceRegular | TimeSlot::CadenceCapacity | TimeSlot::CadenceLatest =>
                cadence.map(|c| c.times.edit(slot)),
            _ => Some(owner.time_edit(slot)),
        })
    }
    /// All descriptors resolve against immutable snapshots before any future native commit.
    /// This pure check exports no partially validated sidecar writes or native permission.
    pub fn validate_assignments<C: ClockFacts, const N: usize>(owner: &Owner, cadence: Option<Cadence>,
        input: &impl TimeInputs, clock: &TrackedClock<'_, C, N>)
        -> Result<[Option<TimeEdit>; 13], ()>
    {
        if !clock.valid() || !owner.times.valid() || !owner.policy.times.valid()
            || !owner.policy.queue.times.valid() || !owner.policy.rtt.times.valid()
            || cadence.is_some_and(|c| !c.times.valid()) { return Err(()); }
        let projection = Self::observe(owner, cadence);
        let actual = [projection.policy[0], projection.policy[1], projection.policy[2],
            projection.policy[3], projection.policy[4], projection.policy[5], projection.policy[6],
            projection.policy[7], projection.policy[8], projection.schedule[0],
            projection.schedule[1], projection.schedule[2], projection.last_evidence];
        let edits = Self::assignment_edits(owner, cadence);
        for (index, slot) in SLOTS.into_iter().enumerate() {
            if let Some(edit) = edits[index] {
                if resolve(slot, edit, input)? != actual[index] { return Err(()); }
            }
        }
        Ok(edits)
    }
}
