//! Public scalar active catch boundary; native actor enrollment remains closed. Semantic clock failure publishes the valid
//! negative prefix reached by the shared reducer; it is NOT draft-discard.
//! Sender failure returned no native update handle. This boundary grants no
//! rollback token, capturer output, route identity or actor serialization.
use core::{ffi::c_void, ptr};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Reply, Metadata, Callback, NativeClock, encode_edit, range};
use crate::native_owner_codec::disjoint;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FailureRequest {
    pub abi: u32, pub operation: u32, pub invocation: u64,
    pub current_generation: u64, pub facts: u32, pub reserved: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FailureOutcome {
    pub abi: u32, pub operation: u32, pub invocation: u64,
    pub disposition: u32, pub route: u32, pub semantic_error: u32, pub attempted_reads: u32,
}
struct FailureClock {
    native: NativeClock,
    attempts: u32,
}
impl TryClockFacts for FailureClock {
    type Error = u32;
    fn try_cut(&mut self, site: ClockSite) -> Result<RelativeTime, u32> {
        self.attempts += 1;
        self.native.try_cut(site)
    }
    fn last_try_time_source(&self) -> TimeSource { self.native.last_try_time_source() }
    fn try_arithmetic<T>(&mut self, value: Option<T>) -> Result<T, u32> { value.ok_or(2) }
}
fn facts(r: FailureRequest) -> ApplyOutcomeFacts {
    ApplyOutcomeFacts {
        peer: PeerFacts { exact_peer: r.facts & 1 != 0, current_generation: r.current_generation },
        exact_source: r.facts & 2 != 0, exact_sink: r.facts & 4 != 0,
        exact_capture_authorization: r.facts & 8 != 0,
        exact_forwarding_authorization: r.facts & 16 != 0,
        capture_authorization_valid: r.facts & 32 != 0,
        forwarding_authorization_valid: r.facts & 64 != 0,
        sink_allows_active_use: r.facts & 128 != 0, exact_base_dimensions: r.facts & 256 != 0,
    }
}
fn values(owner: &Owner) -> [Option<RelativeTime>; 13] {
    let p = ClockProjection::observe(owner, None);
    [p.policy[0], p.policy[1], p.policy[2], p.policy[3], p.policy[4], p.policy[5],
     p.policy[6], p.policy[7], p.policy[8], None, None, None, p.last_evidence]
}
fn route(action: RouteAction) -> u32 {
    match action { RouteAction::Retain => 0, RouteAction::Clear => 1, RouteAction::CopyIncoming => 2 }
}
struct Bundle {
    state: codec::Wire, metadata: Metadata, outcome: FailureOutcome,
    edits: [Edit; 13], coordinates: [Time; 13],
}
fn evaluate(r: FailureRequest, owner_header: codec::Header, owner_atoms: &[codec::Atom],
    prepared_header: codec::Header, prepared_atoms: &[codec::Atom], clock: &mut FailureClock)
    -> Result<Bundle, u32>
{
    if r.abi != 1 || r.operation != 703 || r.invocation == 0 || r.facts & !511 != 0 || r.reserved != 0 {
        return Err(2);
    }
    let current = codec::decode_owner_snapshot(owner_header, owner_atoms).map_err(|_| 2u32)?;
    let prepared = codec::decode_prepared_continuation(prepared_header, prepared_atoms).map_err(|_| 2u32)?;
    let before = values(&current);
    let prepared_times = {
        let mut projected = current; projected.policy = prepared.policy; values(&projected)
    };
    let mut draft = current;
    draft.begin_time_assignment_frame();
    // Exactly one call. Err contains deliberate live writes before F/Q denial.
    let result = draft.try_finish_failure(prepared, facts(r), clock, Dependencies::default());
    let (disposition, resulting_route, semantic_error) = match result {
        Ok(p) => (match p.disposition {
            FailureDisposition::StaleReturn => 0, FailureDisposition::RetainedOrdinary => 1,
            FailureDisposition::RetainedFastIdentity => 2, FailureDisposition::AdoptedTerminalNegative => 3,
        }, route(p.route_action), 0),
        Err(error) if (2..=4).contains(&error) => (4, 0, error),
        Err(_) => return Err(5),
    };
    if !draft.times.valid() || !draft.policy.times.valid() || !draft.policy.queue.times.valid() ||
        !draft.policy.rtt.times.valid() { return Err(5); }
    let complete = semantic_error == 0 && disposition != 0;
    if draft.revision != if complete { current.revision.wrapping_add(1) } else { current.revision } {
        return Err(5);
    }
    let after = values(&draft);
    let mut edits = [Edit::default(); 13];
    let mut coordinates = [Time::default(); 13];
    for (index, slot) in SLOTS.into_iter().enumerate() {
        let edit = draft.time_edit(slot);
        if index >= 9 {
            if edit != TimeEdit::Retain || before[index] != after[index] { return Err(5); }
            continue;
        }
        let expected = if disposition == 3 {
            match edit {
                TimeEdit::Set(origin) if origin == (Origin {
                    source: TimeSource::CorrespondingPreparedInput(slot), delta: 0,
                }) && prepared_times[index].is_some() => prepared_times[index],
                TimeEdit::Clear if prepared_times[index].is_none() => None,
                _ => return Err(5),
            }
        } else {
            match edit {
                TimeEdit::Retain => before[index],
                TimeEdit::Clear if 0x00efu16 & (1 << index) != 0 => None,
                _ => return Err(5),
            }
        };
        if expected != after[index] { return Err(5); }
        edits[index] = encode_edit(edit)?;
        coordinates[index] = Time::encode(after[index]);
        coordinates[index].decode().map_err(|_| 5u32)?;
    }
    let state = codec::encode_owner(draft, codec::RESULT).map_err(|_| 5u32)?;
    codec::validate_result(state.header, &state.atoms).map_err(|_| 5u32)?;
    if state.atoms[169..] != owner_atoms[169..] { return Err(5); }
    if disposition == 0 && (state.atoms.as_slice() != owner_atoms || clock.attempts != 0) { return Err(5); }
    if disposition == 3 && state.atoms[..168] != prepared_atoms[..168] { return Err(5); }
    if disposition != 3 && resulting_route != 0 { return Err(5); }
    let metadata = Metadata { abi: 1, operation: 703, scope: 2, read_count: clock.native.len as u32,
        invocation: r.invocation, revision: draft.revision, peer: draft.policy.peer.unwrap_or(0),
        peer_present: draft.policy.peer.is_some() as u32, route: resulting_route,
        queue_fault: draft.policy.queue.faulted as u32, rtt_fault: draft.policy.rtt.faulted as u32,
        ..Metadata::default() };
    let outcome = FailureOutcome { abi: 1, operation: 703, invocation: r.invocation,
        disposition, route: resulting_route, semantic_error, attempted_reads: clock.attempts };
    Ok(Bundle { state, metadata, outcome, edits, coordinates })
}

/// Status1 means the event completed and publishes its full valid owner,
/// INCLUDING semantic_error2/3/4 prefixes. A caller must import those prefixes
/// before propagating that error. Status2 malformed input and5 invalid generated
/// result write nothing;5 requires fail-closed recovery, not continued operation.
/// This is not native adoption: provider custody, exact prepared sidecars and
/// synchronized non-reentrant publication remain trusted caller obligations.
#[no_mangle]
#[must_use]
pub unsafe extern "C" fn beluga_core_network_adaptation_owner_finish_failure(
    request: *const FailureRequest,
    owner_header: *const codec::Header, owner_atoms: *const codec::Atom, owner_count: u32,
    prepared_header: *const codec::Header, prepared_atoms: *const codec::Atom, prepared_count: u32,
    callback: Option<Callback>, context: *mut c_void,
    output_header: *mut codec::Header, output_atoms: *mut codec::Atom, output_count: u32,
    metadata: *mut Metadata, outcome: *mut FailureOutcome,
    edits: *mut Edit, edit_count: u32, coordinates: *mut Time, coordinate_count: u32,
    reads: *mut Reply, read_count: u32,
) -> u32 {
    if owner_count != 179 || prepared_count != 222 || output_count != 179 ||
        edit_count != 13 || coordinate_count != 13 || read_count != 15 { return 2; }
    let ranges = [range(request, 1), range(owner_header, 1), range(owner_atoms, owner_count as usize),
        range(prepared_header, 1), range(prepared_atoms, prepared_count as usize),
        range(output_header, 1), range(output_atoms, output_count as usize), range(metadata, 1),
        range(outcome, 1), range(edits, edit_count as usize), range(coordinates, coordinate_count as usize),
        range(reads, read_count as usize)];
    if !disjoint(&ranges) { return 2; }
    let Some(callback) = callback else { return 2; };
    let request = unsafe { ptr::read(request) };
    let header = unsafe { ptr::read(owner_header) };
    let atoms = unsafe { core::slice::from_raw_parts(owner_atoms, owner_count as usize) };
    let prepared_header = unsafe { ptr::read(prepared_header) };
    let prepared_atoms = unsafe { core::slice::from_raw_parts(prepared_atoms, prepared_count as usize) };
    let mut clock = FailureClock { native: NativeClock::new(callback, context, request.invocation), attempts: 0 };
    match evaluate(request, header, atoms, prepared_header, prepared_atoms, &mut clock) {
        Err(status) => status,
        Ok(bundle) => {
            unsafe {
                ptr::write(output_header, bundle.state.header);
                ptr::copy_nonoverlapping(bundle.state.atoms.as_ptr(), output_atoms, output_count as usize);
                ptr::write(metadata, bundle.metadata); ptr::write(outcome, bundle.outcome);
                ptr::copy_nonoverlapping(bundle.edits.as_ptr(), edits, edit_count as usize);
                ptr::copy_nonoverlapping(bundle.coordinates.as_ptr(), coordinates, coordinate_count as usize);
                ptr::copy_nonoverlapping(clock.native.reads.as_ptr(), reads, read_count as usize);
            }
            1
        }
    }
}
const _: () = {
    assert!(core::mem::size_of::<FailureRequest>() == 32);
    assert!(core::mem::align_of::<FailureRequest>() == 8);
    assert!(core::mem::offset_of!(FailureRequest, abi) == 0);
    assert!(core::mem::offset_of!(FailureRequest, operation) == 4);
    assert!(core::mem::offset_of!(FailureRequest, invocation) == 8);
    assert!(core::mem::offset_of!(FailureRequest, current_generation) == 16);
    assert!(core::mem::offset_of!(FailureRequest, facts) == 24);
    assert!(core::mem::offset_of!(FailureRequest, reserved) == 28);
    assert!(core::mem::size_of::<FailureOutcome>() == 32);
    assert!(core::mem::align_of::<FailureOutcome>() == 8);
    assert!(core::mem::offset_of!(FailureOutcome, abi) == 0);
    assert!(core::mem::offset_of!(FailureOutcome, operation) == 4);
    assert!(core::mem::offset_of!(FailureOutcome, invocation) == 8);
    assert!(core::mem::offset_of!(FailureOutcome, disposition) == 16);
    assert!(core::mem::offset_of!(FailureOutcome, route) == 20);
    assert!(core::mem::offset_of!(FailureOutcome, semantic_error) == 24);
    assert!(core::mem::offset_of!(FailureOutcome, attempted_reads) == 28);
};
