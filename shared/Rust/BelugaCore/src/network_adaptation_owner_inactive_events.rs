//! Public complete-Owner601 inactive continuation boundary, UNWIRED to the actor. Separate stored179/prepared222 inputs
//! enter one actual shared try_adopt_inactive call. No native resume/resource,
//! route identity, held-await, or actor authority is granted by scalar facts.
//! Non1 discards the local draft and leaves all seven output buffers unchanged.
//! Valid initialized/aligned exclusive POD, pointer provenance/lifetimes and
//! synchronous non-reentrant callback/context custody remain caller obligations.
//! Successful writes are sequential, not concurrent atomic publication.
use core::{ffi::c_void, ptr};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Reply, Metadata, Callback, NativeClock, encode_edit, range};
use crate::native_owner_codec::disjoint;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct InactiveAdoptionRequest {
    pub abi: u32, pub operation: u32, pub invocation: u64,
    pub current_generation: u64, pub exact_peer: u32, pub suspended: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct InactiveAdoptionOutcome {
    pub abi: u32, pub operation: u32, pub invocation: u64,
    pub disposition: u32, pub route: u32,
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
    state: codec::Wire, metadata: Metadata, outcome: InactiveAdoptionOutcome,
    edits: [Edit; 13], coordinates: [Time; 13],
}
fn evaluate(r: InactiveAdoptionRequest, owner_header: codec::Header, owner_atoms: &[codec::Atom],
            prepared_header: codec::Header, prepared_atoms: &[codec::Atom], clock: &mut NativeClock)
    -> Result<Bundle, u32>
{
    if r.abi != 1 || r.operation != 601 || r.invocation == 0 || r.exact_peer > 1 || r.suspended > 1 {
        return Err(2);
    }
    // Both complete scalar domains are decoded before any stale semantic return.
    let current = codec::decode_owner_snapshot(owner_header, owner_atoms).map_err(|_| 2u32)?;
    let prepared = codec::decode_prepared_continuation(prepared_header, prepared_atoms).map_err(|_| 2u32)?;
    let peer = PeerFacts { exact_peer: r.exact_peer == 1, current_generation: r.current_generation };
    let stale = !peer.exact_peer || peer.current_generation != prepared.source_generation ||
        current.revision != prepared.expected_revision;
    let before = values(&current);
    let prepared_times = {
        let mut projected = current;
        projected.policy = prepared.policy;
        values(&projected)
    };
    let mut draft = current;
    draft.begin_time_assignment_frame();
    // Exactly one reducer call: no constructor, dry-run, infallible forwarding,
    // preview evaluation, or eager native-time read substitutes for the event.
    let result = draft.try_adopt_inactive(prepared, peer, r.suspended == 1, clock, Dependencies::default())?;
    let disposition = match result.disposition {
        InactiveDisposition::StaleReturn => 0,
        InactiveDisposition::Adopted => 1,
        InactiveDisposition::BeginNativeResume => 2,
    };
    let resulting_route = route(result.route_action);
    if stale {
        if disposition != 0 || resulting_route != 0 || clock.len != 0 || draft.revision != current.revision {
            return Err(5);
        }
    } else {
        if disposition == 0 || result.route_action != prepared.route_action ||
            draft.revision != current.revision.wrapping_add(1) { return Err(5); }
        // Route action and the copied policy scalar are independent typed fields.
        // Actual Optional route custody belongs to the native adapter, not this vote.
    }
    let after = values(&draft);
    let mut edits = [Edit::default(); 13];
    let mut coordinates = [Time::default(); 13];
    let newly_faulted = !prepared.policy.terminal_fault() && draft.policy.terminal_fault();
    for (index, slot) in SLOTS.into_iter().enumerate() {
        let edit = draft.time_edit(slot);
        if index >= 9 {
            if edit != TimeEdit::Retain || before[index] != after[index] { return Err(5); }
            continue; // unowned cadence/evidence outputs remain canonical zero
        }
        let expected = if stale {
            if edit != TimeEdit::Retain { return Err(5); }
            before[index]
        } else {
            match edit {
                TimeEdit::Set(origin) if origin == (Origin {
                    source: TimeSource::CorrespondingPreparedInput(slot), delta: 0,
                }) => prepared_times[index],
                TimeEdit::Clear if prepared_times[index].is_none() => None,
                // The suspension RTT-fault path may clear only the original
                // terminal-revert slots0/1/2/3/5/6/7, never cooldown4 or RTT8.
                TimeEdit::Clear if newly_faulted && 0x00efu16 & (1 << index) != 0 => None,
                _ => return Err(5),
            }
        };
        if expected != after[index] { return Err(5); }
        if matches!(edit, TimeEdit::Set(_)) && expected.is_none() { return Err(5); }
        edits[index] = encode_edit(edit)?;
        coordinates[index] = Time::encode(after[index]);
        coordinates[index].decode()?;
    }
    // Scalar output cannot substitute for the independent future native exact
    // []/L/LQ plan or authorize providers before a cut. That adapter is separate.
    let state = codec::encode_owner(draft, codec::RESULT).map_err(|_| 2u32)?;
    if state.atoms[169..] != owner_atoms[169..] { return Err(5); }
    if stale && state.atoms.as_slice() != owner_atoms { return Err(5); }
    let metadata = Metadata { abi: 1, operation: 601, scope: 2, read_count: clock.len as u32,
        invocation: r.invocation, revision: draft.revision, peer: draft.policy.peer.unwrap_or(0),
        peer_present: draft.policy.peer.is_some() as u32, route: resulting_route,
        queue_fault: draft.policy.queue.faulted as u32, rtt_fault: draft.policy.rtt.faulted as u32,
        ..Metadata::default() };
    let outcome = InactiveAdoptionOutcome { abi: 1, operation: 601, invocation: r.invocation,
        disposition, route: resulting_route };
    Ok(Bundle { state, metadata, outcome, edits, coordinates })
}

/// Exact counts179/222/179/13/13/15 precede pointer reads. Twelve known
/// input/output ranges are nonempty/aligned/disjoint; opaque context is not one.
/// Callback required even on stale zero-cut success. Status1 completed;
/// 2 shape/range/coordinate/arithmetic,3 callback denial/budget,4 correlation,
/// 5 illegal journal/source/route/revision/tail. No output is written on non1.
#[no_mangle]
#[must_use]
pub unsafe extern "C" fn beluga_core_network_adaptation_owner_adopt_inactive(
    request: *const InactiveAdoptionRequest,
    owner_header: *const codec::Header, owner_atoms: *const codec::Atom, owner_count: u32,
    prepared_header: *const codec::Header, prepared_atoms: *const codec::Atom, prepared_count: u32,
    callback: Option<Callback>, context: *mut c_void,
    output_header: *mut codec::Header, output_atoms: *mut codec::Atom, output_count: u32,
    metadata: *mut Metadata, outcome: *mut InactiveAdoptionOutcome,
    edits: *mut Edit, edit_count: u32, coordinates: *mut Time, coordinate_count: u32,
    reads: *mut Reply, read_count: u32,
) -> u32 {
    if owner_count != codec::OWNER_COUNT as u32 || prepared_count != codec::PREPARED_COUNT as u32 ||
        output_count != codec::OWNER_COUNT as u32 || edit_count != 13 || coordinate_count != 13 || read_count != 15 {
        return 2;
    }
    let ranges = [range(request, 1), range(owner_header, 1), range(owner_atoms, owner_count as usize),
        range(prepared_header, 1), range(prepared_atoms, prepared_count as usize),
        range(output_header, 1), range(output_atoms, output_count as usize), range(metadata, 1),
        range(outcome, 1), range(edits, edit_count as usize), range(coordinates, coordinate_count as usize),
        range(reads, read_count as usize)];
    if !disjoint(&ranges) { return 2; }
    let Some(callback) = callback else { return 2; };
    let request = unsafe { ptr::read(request) };
    let owner_header = unsafe { ptr::read(owner_header) };
    let owner_atoms = unsafe { core::slice::from_raw_parts(owner_atoms, owner_count as usize) };
    let prepared_header = unsafe { ptr::read(prepared_header) };
    let prepared_atoms = unsafe { core::slice::from_raw_parts(prepared_atoms, prepared_count as usize) };
    let mut clock = NativeClock::new(callback, context, request.invocation);
    match evaluate(request, owner_header, owner_atoms, prepared_header, prepared_atoms, &mut clock) {
        Err(status) => status,
        Ok(bundle) => {
            unsafe {
                ptr::write(output_header, bundle.state.header);
                ptr::copy_nonoverlapping(bundle.state.atoms.as_ptr(), output_atoms, output_count as usize);
                ptr::write(metadata, bundle.metadata); ptr::write(outcome, bundle.outcome);
                ptr::copy_nonoverlapping(bundle.edits.as_ptr(), edits, edit_count as usize);
                ptr::copy_nonoverlapping(bundle.coordinates.as_ptr(), coordinates, coordinate_count as usize);
                ptr::copy_nonoverlapping(clock.reads.as_ptr(), reads, read_count as usize);
            }
            1
        }
    }
}
const _: () = {
    assert!(core::mem::size_of::<InactiveAdoptionRequest>() == 32);
    assert!(core::mem::align_of::<InactiveAdoptionRequest>() == 8);
    assert!(core::mem::offset_of!(InactiveAdoptionRequest, abi) == 0);
    assert!(core::mem::offset_of!(InactiveAdoptionRequest, operation) == 4);
    assert!(core::mem::offset_of!(InactiveAdoptionRequest, invocation) == 8);
    assert!(core::mem::offset_of!(InactiveAdoptionRequest, current_generation) == 16);
    assert!(core::mem::offset_of!(InactiveAdoptionRequest, exact_peer) == 24);
    assert!(core::mem::offset_of!(InactiveAdoptionRequest, suspended) == 28);
    assert!(core::mem::size_of::<InactiveAdoptionOutcome>() == 24);
    assert!(core::mem::align_of::<InactiveAdoptionOutcome>() == 8);
    assert!(core::mem::offset_of!(InactiveAdoptionOutcome, abi) == 0);
    assert!(core::mem::offset_of!(InactiveAdoptionOutcome, operation) == 4);
    assert!(core::mem::offset_of!(InactiveAdoptionOutcome, invocation) == 8);
    assert!(core::mem::offset_of!(InactiveAdoptionOutcome, disposition) == 16);
    assert!(core::mem::offset_of!(InactiveAdoptionOutcome, route) == 20);
};
