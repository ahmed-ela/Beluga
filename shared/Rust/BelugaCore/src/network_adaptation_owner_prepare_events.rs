//! Public complete-Owner501 unpublished preparation boundary, UNWIRED to the actor.
//! One full stored179 snapshot calls the actual shared try_prepare_proposal once.
//! Prepared222 scalars intentionally omit invocation journals and native custody;
//! the original journal/coordinates/read transcript are separate success outputs.
//! Failure discards the local result and never writes any output. Shared methods
//! do not promise rollback of their private draft mutations. Caller-owned valid
//! pointer provenance/lifetimes/initialized POD/exclusive objects and synchronous
//! non-reentrant callback/context custody remain trusted. Numeric disjoint-range
//! checks cannot prove those obligations. Success writes sequentially, not as a
//! concurrently atomic publication, and grants no continuation-currentness vote.
use core::{ffi::c_void, ptr};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Reply, Metadata, Callback, NativeClock, encode_edit, range};
use crate::native_owner_codec::disjoint;
/// Lossless report POD. Presence/unused payloads are canonical; IEEE payloads
/// and overlong measurement fingerprints are not normalized or semantically
/// rejected here. Consumed subowners apply their existing validation/fault rules.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ReportWire {
    pub peer: u64,
    pub capture_active: u32, pub automatically_suspended: u32, pub strict: u32,
    pub incoming_present: u32, pub equal_to_retained: u32, pub observation_kind: u32,
    pub collection_sequence_present: u32, pub bandwidth_present: u32,
    pub current_rtt_present: u32, pub packets_present: u32,
    pub delay_present: u32, pub native_timestamp_present: u32,
    pub fingerprint_length: u32, pub reserved: u32,
    pub collection_sequence: u64, pub bandwidth_bits: u64, pub current_rtt_bits: u64,
    pub packets: u64, pub delay_bits: u64, pub native_timestamp_bits: u64,
    pub fingerprint: [u64; 8], pub measurement_total_bits: u64, pub measurement_responses: u64,
}
impl ReportWire {
    pub(crate) fn decode(self, observed_at: RelativeTime) -> Result<Report, u32> {
        if self.reserved != 0 || self.observation_kind > 2 ||
            [self.capture_active, self.automatically_suspended, self.strict,
             self.incoming_present, self.equal_to_retained].into_iter().any(|v| v > 1) {
            return Err(2);
        }
        fn optional(present: u32, bits: u64) -> Result<Option<u64>, u32> {
            match present { 0 if bits == 0 => Ok(None), 1 => Ok(Some(bits)), _ => Err(2) }
        }
        let collection_sequence = optional(self.collection_sequence_present, self.collection_sequence)?;
        let bandwidth = optional(self.bandwidth_present, self.bandwidth_bits)?.map(Scalar);
        let current_rtt = optional(self.current_rtt_present, self.current_rtt_bits)?.map(Scalar);
        let packets = optional(self.packets_present, self.packets)?;
        let delay = optional(self.delay_present, self.delay_bits)?.map(Scalar);
        let native_timestamp = optional(self.native_timestamp_present, self.native_timestamp_bits)?.map(Scalar);
        if self.observation_kind != 2 && (self.fingerprint_length != 0 ||
            self.fingerprint != [0; 8] || self.measurement_total_bits != 0 || self.measurement_responses != 0) {
            return Err(2);
        }
        let observation = match self.observation_kind {
            0 => Observation::LegacyAbsent,
            1 => Observation::Unavailable,
            2 => Observation::Measurement { fingerprint: self.fingerprint,
                fingerprint_length: self.fingerprint_length,
                total_bits: self.measurement_total_bits, responses: self.measurement_responses },
            _ => unreachable!(),
        };
        Ok(Report { peer: self.peer, capture_active: self.capture_active == 1,
            automatically_suspended: self.automatically_suspended == 1, strict: self.strict == 1,
            bandwidth, current_rtt, observation, collection_sequence,
            route: RouteFacts { incoming_present: self.incoming_present == 1,
                equal_to_retained: self.equal_to_retained == 1 }, packets, delay,
            native_timestamp, observed_at })
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PrepareRequest {
    pub abi: u32, pub operation: u32, pub invocation: u64,
    pub source_generation: u64, pub expected_revision: u64, pub current_generation: u64,
    pub entry_flags: u32, pub capacity_only: u32, pub allows_resume: u32, pub report_present: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PrepareOutcome {
    pub abi: u32, pub operation: u32, pub invocation: u64,
    pub prepared_present: u32, pub reserved: u32,
}

fn entry(flags: u32, current_generation: u64) -> EntryFacts {
    EntryFacts { resume_context_absent: flags & 1 != 0,
        peer: PeerFacts { exact_peer: flags & 2 != 0, current_generation },
        capture: CaptureFacts { source_present: flags & 4 != 0, sink_present: flags & 8 != 0,
            capture_authorization_valid: flags & 16 != 0,
            forwarding_authorization_valid: flags & 32 != 0, sink_allows_active_use: flags & 64 != 0 },
        automatically_suspended: flags & 128 != 0 }
}
fn values(owner: &Owner) -> [Option<RelativeTime>; 13] {
    let p = ClockProjection::observe(owner, None);
    [p.policy[0], p.policy[1], p.policy[2], p.policy[3], p.policy[4], p.policy[5],
     p.policy[6], p.policy[7], p.policy[8], None, None, None, p.last_evidence]
}
fn allowed_origin(lane: ProposalLane, index: usize, origin: Origin) -> bool {
    if lane == ProposalLane::Expiry { return false; }
    if index == 5 {
        return origin == (Origin { source: TimeSource::CurrentInput(TimeSlot::ProbeDeadline), delta: 0 });
    }
    if lane == ProposalLane::Capacity { return false; }
    let delta = match index { 0 => 3_500_000_000_000_000_000,
        2 => 2_000_000_000_000_000_000, 1 | 3 | 4 | 6 | 7 | 8 => 0, _ => return false };
    origin == (Origin { source: TimeSource::Explicit(ExplicitTime::PolicyObservedAt), delta })
}
struct Bundle {
    header: codec::Header, atoms: [codec::Atom; codec::PREPARED_COUNT],
    meta: Metadata, outcome: PrepareOutcome, edits: [Edit; 13], coordinates: [Time; 13],
}
fn evaluate(r: PrepareRequest, h: codec::Header, atoms: &[codec::Atom], wire: ReportWire,
            supplied_time: Time, clock: &mut NativeClock) -> Result<Bundle, u32> {
    if r.abi != 1 || r.operation != 501 || r.invocation == 0 || r.entry_flags & !255 != 0 ||
        [r.capacity_only, r.allows_resume, r.report_present].into_iter().any(|v| v > 1) { return Err(2); }
    // Full structural input validation precedes every semantic entry return.
    let owner = codec::decode_owner_snapshot(h, atoms).map_err(|_| 2u32)?;
    let observed_at = supplied_time.decode()?;
    let report = if r.report_present == 1 {
        // This placeholder has no native origin and is never consumed on the
        // only admitted absent-time shape: a pure zero-cut entry rejection.
        Some(wire.decode(observed_at.unwrap_or(0))?)
    } else {
        if wire != ReportWire::default() { return Err(2); }
        None
    };
    let entry = entry(r.entry_flags, r.current_generation);
    let rejects_before_policy = !entry.resume_context_absent || !entry.peer.exact_peer ||
        entry.peer.current_generation != r.source_generation || owner.revision != r.expected_revision ||
        (!entry.capture.active() && r.allows_resume == 0);
    if observed_at.is_none() && !rejects_before_policy { return Err(2); }
    let before = values(&owner);
    // Exactly one actual shared operation; no constructor, dry-run, infallible
    // preview, terminal preflight, or eager clock cut stands in for preparation.
    let prepared = owner.try_prepare_proposal(r.source_generation, r.expected_revision, entry, report,
        r.capacity_only == 1, r.allows_resume == 1, observed_at.unwrap_or(0), clock, Dependencies::default())?;
    let mut bundle = Bundle { header: codec::Header::default(), atoms: [codec::Atom::default(); codec::PREPARED_COUNT],
        meta: Metadata { abi: 1, operation: 501, scope: 1, read_count: clock.len as u32,
            invocation: r.invocation, revision: owner.revision, peer: owner.policy.peer.unwrap_or(0),
            peer_present: owner.policy.peer.is_some() as u32, queue_fault: owner.policy.queue.faulted as u32,
            rtt_fault: owner.policy.rtt.faulted as u32, ..Metadata::default() },
        outcome: PrepareOutcome { abi: 1, operation: 501, invocation: r.invocation,
            ..PrepareOutcome::default() }, edits: [Edit::default(); 13], coordinates: [Time::default(); 13] };
    let Some(prepared) = prepared else {
        // A late None can have real reads and discarded local expiry mutations.
        // Neither its assignments nor any discarded proposal scalar may escape.
        return Ok(bundle);
    };
    let route = match prepared.route_action { RouteAction::Retain => 0,
        RouteAction::Clear => 1, RouteAction::CopyIncoming => 2 };
    match prepared.route_action {
        RouteAction::Retain if prepared.policy.route_present != owner.policy.route_present => return Err(5),
        RouteAction::Clear if prepared.policy.route_present => return Err(5),
        RouteAction::CopyIncoming if r.report_present != 1 || wire.incoming_present != 1 || !prepared.policy.route_present => return Err(5),
        _ => {},
    }
    let mut projected = owner;
    projected.policy = prepared.policy;
    let after = values(&projected);
    let mask: u16 = if prepared.lane == ProposalLane::Regular { 0x01ff } else { 0x00ef };
    for (index, slot) in SLOTS.into_iter().enumerate() {
        let edit = prepared.policy.time_edit(slot);
        if mask & (1 << index) == 0 {
            if edit != TimeEdit::Retain || before[index] != after[index] { return Err(5); }
            continue;
        }
        let expected = match edit {
            TimeEdit::Retain => before[index], TimeEdit::Clear => None,
            TimeEdit::Set(origin) if allowed_origin(prepared.lane, index, origin) => {
                let source = match origin.source {
                    TimeSource::CurrentInput(source) => before[source as usize].ok_or(5u32)?,
                    TimeSource::Explicit(ExplicitTime::PolicyObservedAt) => observed_at.ok_or(5u32)?,
                    _ => return Err(5),
                };
                Some(source.checked_add(origin.delta).ok_or(2u32)?)
            }
            _ => return Err(5),
        };
        if expected != after[index] { return Err(5); }
        bundle.edits[index] = encode_edit(edit)?;
        bundle.coordinates[index] = Time::encode(after[index]);
        bundle.coordinates[index].decode()?; // before any raw output write
    }
    // Encode only after checking the ORIGINAL invocation journals above. Codec
    // decode/re-encode would erase them and cannot manufacture native authority.
    let state = codec::encode_prepared_continuation(prepared).map_err(|_| 2u32)?;
    bundle.header = state.header;
    bundle.atoms.copy_from_slice(&state.atoms);
    bundle.outcome.prepared_present = 1;
    bundle.meta.peer = prepared.policy.peer.unwrap_or(0);
    bundle.meta.peer_present = prepared.policy.peer.is_some() as u32;
    bundle.meta.route = route;
    bundle.meta.queue_fault = prepared.policy.queue.faulted as u32;
    bundle.meta.rtt_fault = prepared.policy.rtt.faulted as u32;
    Ok(bundle)
}

/// Status1 completed Some/None;2 bad shape/range/coordinate/consumed arithmetic;
/// 3 provider denial/budget;4 reply correlation;5 illegal journal/origin/route.
/// Exactly twelve known ranges are disjoint; opaque context is not such a range.
/// Exact counts are checked before reading any pointer. Callback is mandatory,
/// including zero-cut entry rejection. All seven outputs remain untouched on
/// non1; successful writes require exclusive caller custody through return.
#[no_mangle]
#[must_use]
pub unsafe extern "C" fn beluga_core_network_adaptation_owner_prepare_event(
    request: *const PrepareRequest, header: *const codec::Header,
    atoms: *const codec::Atom, count: u32, report: *const ReportWire, observed_at: *const Time,
    callback: Option<Callback>, context: *mut c_void,
    output_header: *mut codec::Header, output_atoms: *mut codec::Atom, output_count: u32,
    metadata: *mut Metadata, outcome: *mut PrepareOutcome,
    edits: *mut Edit, edit_count: u32, coordinates: *mut Time, coordinate_count: u32,
    reads: *mut Reply, read_count: u32,
) -> u32 {
    if count != codec::OWNER_COUNT as u32 || output_count != codec::PREPARED_COUNT as u32 ||
        edit_count != 13 || coordinate_count != 13 || read_count != 15 { return 2; }
    let ranges = [range(request, 1), range(header, 1), range(atoms, count as usize),
        range(report, 1), range(observed_at, 1), range(output_header, 1),
        range(output_atoms, output_count as usize), range(metadata, 1), range(outcome, 1),
        range(edits, edit_count as usize), range(coordinates, coordinate_count as usize),
        range(reads, read_count as usize)];
    if !disjoint(&ranges) { return 2; }
    let Some(callback) = callback else { return 2; };
    let request = unsafe { ptr::read(request) };
    let header = unsafe { ptr::read(header) };
    let atoms = unsafe { core::slice::from_raw_parts(atoms, count as usize) };
    let report = unsafe { ptr::read(report) };
    let observed_at = unsafe { ptr::read(observed_at) };
    let mut clock = NativeClock::new(callback, context, request.invocation);
    match evaluate(request, header, atoms, report, observed_at, &mut clock) {
        Err(status) => status,
        Ok(bundle) => {
            unsafe {
                ptr::write(output_header, bundle.header);
                ptr::copy_nonoverlapping(bundle.atoms.as_ptr(), output_atoms, output_count as usize);
                ptr::write(metadata, bundle.meta); ptr::write(outcome, bundle.outcome);
                ptr::copy_nonoverlapping(bundle.edits.as_ptr(), edits, edit_count as usize);
                ptr::copy_nonoverlapping(bundle.coordinates.as_ptr(), coordinates, coordinate_count as usize);
                ptr::copy_nonoverlapping(clock.reads.as_ptr(), reads, read_count as usize);
            }
            1
        }
    }
}
const _: () = {
    assert!(core::mem::size_of::<PrepareRequest>() == 56);
    assert!(core::mem::align_of::<PrepareRequest>() == 8);
    assert!(core::mem::offset_of!(PrepareRequest, abi) == 0);
    assert!(core::mem::offset_of!(PrepareRequest, operation) == 4);
    assert!(core::mem::offset_of!(PrepareRequest, invocation) == 8);
    assert!(core::mem::offset_of!(PrepareRequest, source_generation) == 16);
    assert!(core::mem::offset_of!(PrepareRequest, expected_revision) == 24);
    assert!(core::mem::offset_of!(PrepareRequest, current_generation) == 32);
    assert!(core::mem::offset_of!(PrepareRequest, entry_flags) == 40);
    assert!(core::mem::offset_of!(PrepareRequest, capacity_only) == 44);
    assert!(core::mem::offset_of!(PrepareRequest, allows_resume) == 48);
    assert!(core::mem::offset_of!(PrepareRequest, report_present) == 52);
    assert!(core::mem::size_of::<PrepareOutcome>() == 24);
    assert!(core::mem::align_of::<PrepareOutcome>() == 8);
    assert!(core::mem::offset_of!(PrepareOutcome, abi) == 0);
    assert!(core::mem::offset_of!(PrepareOutcome, operation) == 4);
    assert!(core::mem::offset_of!(PrepareOutcome, invocation) == 8);
    assert!(core::mem::offset_of!(PrepareOutcome, prepared_present) == 16);
    assert!(core::mem::offset_of!(PrepareOutcome, reserved) == 20);
};

// Mechanical ReportWire layout assertions retained from the exact original POD.
const _: () = {
    assert!(core::mem::size_of::<ReportWire>() == 192);
    assert!(core::mem::align_of::<ReportWire>() == 8);
    assert!(core::mem::offset_of!(ReportWire, peer) == 0);
    assert!(core::mem::offset_of!(ReportWire, capture_active) == 8);
    assert!(core::mem::offset_of!(ReportWire, automatically_suspended) == 12);
    assert!(core::mem::offset_of!(ReportWire, strict) == 16);
    assert!(core::mem::offset_of!(ReportWire, incoming_present) == 20);
    assert!(core::mem::offset_of!(ReportWire, equal_to_retained) == 24);
    assert!(core::mem::offset_of!(ReportWire, observation_kind) == 28);
    assert!(core::mem::offset_of!(ReportWire, collection_sequence_present) == 32);
    assert!(core::mem::offset_of!(ReportWire, bandwidth_present) == 36);
    assert!(core::mem::offset_of!(ReportWire, current_rtt_present) == 40);
    assert!(core::mem::offset_of!(ReportWire, packets_present) == 44);
    assert!(core::mem::offset_of!(ReportWire, delay_present) == 48);
    assert!(core::mem::offset_of!(ReportWire, native_timestamp_present) == 52);
    assert!(core::mem::offset_of!(ReportWire, fingerprint_length) == 56);
    assert!(core::mem::offset_of!(ReportWire, reserved) == 60);
    assert!(core::mem::offset_of!(ReportWire, collection_sequence) == 64);
    assert!(core::mem::offset_of!(ReportWire, bandwidth_bits) == 72);
    assert!(core::mem::offset_of!(ReportWire, current_rtt_bits) == 80);
    assert!(core::mem::offset_of!(ReportWire, packets) == 88);
    assert!(core::mem::offset_of!(ReportWire, delay_bits) == 96);
    assert!(core::mem::offset_of!(ReportWire, native_timestamp_bits) == 104);
    assert!(core::mem::offset_of!(ReportWire, fingerprint) == 112);
    assert!(core::mem::offset_of!(ReportWire, measurement_total_bits) == 176);
    assert!(core::mem::offset_of!(ReportWire, measurement_responses) == 184);
};
