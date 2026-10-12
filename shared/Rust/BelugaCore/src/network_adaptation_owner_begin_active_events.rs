//! Public complete-Owner701 active-before-await boundary, UNWIRED to the actor.
//! Resource bits are projections, not
//! native objects or a permission to await/apply. One actual shared reducer call
//! consumes separate owner179/prepared222 inputs on an unpublished local draft.
//! This event is NOT the later catch/failure boundary: its draft-discard contract
//! must never erase try_finish_failure's deliberately live negative prefixes.
//! Caller-owned initialized exclusive POD, pointer provenance/lifetimes and
//! synchronous callback/context custody remain trusted obligations. Sequential
//! successful writes are not a concurrently atomic native publication.
use core::{ffi::c_void, ptr};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Reply, Metadata, Callback, NativeClock, encode_edit, range};
use crate::native_owner_codec::disjoint;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BeginActiveRequest {
    pub abi: u32, pub operation: u32, pub invocation: u64,
    pub resource_flags: u32, pub reserved: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BeginActiveOutcome {
    pub abi: u32, pub operation: u32, pub invocation: u64,
    pub disposition: u32, pub route: u32, pub prepared_present: u32, pub reserved: u32,
}
fn resources(flags: u32) -> ApplyResources {
    ApplyResources { source_present: flags & 1 != 0, sink_present: flags & 2 != 0,
        capture_authorization_present: flags & 4 != 0,
        forwarding_authorization_present: flags & 8 != 0,
        base_dimensions_present: flags & 16 != 0, capturer_present: flags & 32 != 0 }
}
fn values(owner: &Owner) -> [Option<RelativeTime>; 13] {
    let p = ClockProjection::observe(owner, None);
    [p.policy[0], p.policy[1], p.policy[2], p.policy[3], p.policy[4], p.policy[5],
     p.policy[6], p.policy[7], p.policy[8], None, None, None, p.last_evidence]
}
struct Bundle {
    owner: codec::Wire, prepared_header: codec::Header,
    prepared_atoms: [codec::Atom; codec::PREPARED_COUNT],
    metadata: Metadata, outcome: BeginActiveOutcome, edits: [Edit; 13], coordinates: [Time; 13],
}
fn evaluate(r: BeginActiveRequest, owner_header: codec::Header, owner_atoms: &[codec::Atom],
            prepared_header: codec::Header, prepared_atoms: &[codec::Atom], clock: &mut NativeClock)
    -> Result<Bundle, u32>
{
    if r.abi != 1 || r.operation != 701 || r.invocation == 0 || r.resource_flags & !63 != 0 || r.reserved != 0 {
        return Err(2);
    }
    // All scalar structure is checked even when the eventual resource gate skips.
    let current = codec::decode_owner_snapshot(owner_header, owner_atoms).map_err(|_| 2u32)?;
    let prepared = codec::decode_prepared_continuation(prepared_header, prepared_atoms).map_err(|_| 2u32)?;
    let before = values(&current);
    let bind_reachable = prepared.policy.terminal_fault() && current.policy.peer != Some(prepared.source_generation);
    let mut draft = current;
    draft.begin_time_assignment_frame();
    // No peer/revision/capture-active/cancellation/resume vote is added here.
    // The original synchronous continuation is already after proposal admission.
    let result = draft.try_begin_active_apply(prepared, resources(r.resource_flags), clock, Dependencies::default())?;
    let (disposition, retained_route, returned) = match result {
        BeginActive::Return { retained_route_action } => (0, retained_route_action, None),
        BeginActive::NoNativeApply { prepared, retained_route_action } => (1, retained_route_action, Some(prepared)),
        BeginActive::Apply { prepared, retained_route_action } => (2, retained_route_action, Some(prepared)),
    };
    let route = match retained_route { RouteAction::Retain => 0, RouteAction::Clear => 1,
        RouteAction::CopyIncoming => return Err(5) };
    // At most two original restrictive publication sites. NaN non-reflexivity is
    // deliberately not replaced with byte equality or a merged revision site.
    if ![current.revision, current.revision.wrapping_add(1), current.revision.wrapping_add(2)].contains(&draft.revision) {
        return Err(5);
    }
    if route == 1 && (!bind_reachable || draft.policy.route_present) { return Err(5); }
    if !draft.times.valid() || !draft.policy.times.valid() || !draft.policy.queue.times.valid() || !draft.policy.rtt.times.valid() {
        return Err(5);
    }
    let after = values(&draft);
    let mut edits = [Edit::default(); 13]; let mut coordinates = [Time::default(); 13];
    let mask = if bind_reachable { 0x01ffu16 } else { 0x00efu16 };
    for (index, slot) in SLOTS.into_iter().enumerate() {
        let edit = draft.time_edit(slot);
        if index >= 9 {
            if edit != TimeEdit::Retain || before[index] != after[index] { return Err(5); }
            continue; // unowned cadence/evidence sidecars are canonical zero
        }
        let expected = match edit {
            TimeEdit::Retain => before[index],
            TimeEdit::Clear if mask & (1 << index) != 0 => None,
            _ => return Err(5), // no import, equal-coordinate copy, stamp or delta
        };
        if expected != after[index] { return Err(5); }
        edits[index] = encode_edit(edit)?;
        coordinates[index] = Time::encode(after[index]); coordinates[index].decode()?;
    }
    let owner = codec::encode_owner(draft, codec::RESULT).map_err(|_| 2u32)?;
    if owner.atoms[169..] != owner_atoms[169..] { return Err(5); }
    let mut returned_header = codec::Header::default();
    let mut returned_atoms = [codec::Atom::default(); codec::PREPARED_COUNT];
    if let Some(returned) = returned {
        let expected_applying = if draft.revision == current.revision { prepared.applying_revision } else { draft.revision };
        if returned.applying_revision != expected_applying { return Err(5); }
        let wire = codec::encode_prepared_continuation(returned).map_err(|_| 2u32)?;
        // Only applying_revision may differ. Scalar serialization does not mint a
        // replacement preparation anchor, route object, resource or native grant.
        if wire.header != prepared_header || wire.atoms[..170] != prepared_atoms[..170] ||
            wire.atoms[171..] != prepared_atoms[171..] { return Err(5); }
        returned_header = wire.header; returned_atoms.copy_from_slice(&wire.atoms);
    }
    let metadata = Metadata { abi: 1, operation: 701, scope: 2, read_count: clock.len as u32,
        invocation: r.invocation, revision: draft.revision, peer: draft.policy.peer.unwrap_or(0),
        peer_present: draft.policy.peer.is_some() as u32, route,
        queue_fault: draft.policy.queue.faulted as u32, rtt_fault: draft.policy.rtt.faulted as u32,
        ..Metadata::default() };
    let outcome = BeginActiveOutcome { abi: 1, operation: 701, invocation: r.invocation,
        disposition, route, prepared_present: returned.is_some() as u32, reserved: 0 };
    Ok(Bundle { owner, prepared_header: returned_header, prepared_atoms: returned_atoms,
        metadata, outcome, edits, coordinates })
}

/// Exact counts179/222/179/222/13/13/15 before any pointer reads; fourteen
/// nonempty aligned known ranges disjoint. Callback mandatory even zero cuts.
/// Status1 success;2 shape/range/coordinate/arithmetic;3 callback denial/budget;
/// 4 correlation;5 forbidden assignment/result. Every non1 leaves all nine
/// outputs unchanged. Current179 and prepared222 are separately immutable.
#[no_mangle]
#[must_use]
pub unsafe extern "C" fn beluga_core_network_adaptation_owner_begin_active(
    request: *const BeginActiveRequest,
    owner_header: *const codec::Header, owner_atoms: *const codec::Atom, owner_count: u32,
    prepared_header: *const codec::Header, prepared_atoms: *const codec::Atom, prepared_count: u32,
    callback: Option<Callback>, context: *mut c_void,
    output_header: *mut codec::Header, output_atoms: *mut codec::Atom, output_count: u32,
    output_prepared_header: *mut codec::Header, output_prepared_atoms: *mut codec::Atom, output_prepared_count: u32,
    metadata: *mut Metadata, outcome: *mut BeginActiveOutcome,
    edits: *mut Edit, edit_count: u32, coordinates: *mut Time, coordinate_count: u32,
    reads: *mut Reply, read_count: u32,
) -> u32 {
    if owner_count != codec::OWNER_COUNT as u32 || prepared_count != codec::PREPARED_COUNT as u32 ||
        output_count != codec::OWNER_COUNT as u32 || output_prepared_count != codec::PREPARED_COUNT as u32 ||
        edit_count != 13 || coordinate_count != 13 || read_count != 15 { return 2; }
    let ranges = [range(request, 1), range(owner_header, 1), range(owner_atoms, owner_count as usize),
        range(prepared_header, 1), range(prepared_atoms, prepared_count as usize),
        range(output_header, 1), range(output_atoms, output_count as usize),
        range(output_prepared_header, 1), range(output_prepared_atoms, output_prepared_count as usize),
        range(metadata, 1), range(outcome, 1), range(edits, edit_count as usize),
        range(coordinates, coordinate_count as usize), range(reads, read_count as usize)];
    if !disjoint(&ranges) { return 2; }
    let Some(callback) = callback else { return 2; };
    let request = unsafe { ptr::read(request) }; let owner_header = unsafe { ptr::read(owner_header) };
    let owner_atoms = unsafe { core::slice::from_raw_parts(owner_atoms, owner_count as usize) };
    let prepared_header = unsafe { ptr::read(prepared_header) };
    let prepared_atoms = unsafe { core::slice::from_raw_parts(prepared_atoms, prepared_count as usize) };
    let mut clock = NativeClock::new(callback, context, request.invocation);
    match evaluate(request, owner_header, owner_atoms, prepared_header, prepared_atoms, &mut clock) {
        Err(status) => status,
        Ok(b) => {
            unsafe {
                ptr::write(output_header, b.owner.header);
                ptr::copy_nonoverlapping(b.owner.atoms.as_ptr(), output_atoms, output_count as usize);
                ptr::write(output_prepared_header, b.prepared_header);
                ptr::copy_nonoverlapping(b.prepared_atoms.as_ptr(), output_prepared_atoms, output_prepared_count as usize);
                ptr::write(metadata, b.metadata); ptr::write(outcome, b.outcome);
                ptr::copy_nonoverlapping(b.edits.as_ptr(), edits, edit_count as usize);
                ptr::copy_nonoverlapping(b.coordinates.as_ptr(), coordinates, coordinate_count as usize);
                ptr::copy_nonoverlapping(clock.reads.as_ptr(), reads, read_count as usize);
            }
            1
        }
    }
}
const _: () = {
    assert!(core::mem::size_of::<BeginActiveRequest>() == 24);
    assert!(core::mem::align_of::<BeginActiveRequest>() == 8);
    assert!(core::mem::offset_of!(BeginActiveRequest, abi) == 0);
    assert!(core::mem::offset_of!(BeginActiveRequest, operation) == 4);
    assert!(core::mem::offset_of!(BeginActiveRequest, invocation) == 8);
    assert!(core::mem::offset_of!(BeginActiveRequest, resource_flags) == 16);
    assert!(core::mem::offset_of!(BeginActiveRequest, reserved) == 20);
    assert!(core::mem::size_of::<BeginActiveOutcome>() == 32);
    assert!(core::mem::align_of::<BeginActiveOutcome>() == 8);
    assert!(core::mem::offset_of!(BeginActiveOutcome, abi) == 0);
    assert!(core::mem::offset_of!(BeginActiveOutcome, operation) == 4);
    assert!(core::mem::offset_of!(BeginActiveOutcome, invocation) == 8);
    assert!(core::mem::offset_of!(BeginActiveOutcome, disposition) == 16);
    assert!(core::mem::offset_of!(BeginActiveOutcome, route) == 20);
    assert!(core::mem::offset_of!(BeginActiveOutcome, prepared_present) == 24);
    assert!(core::mem::offset_of!(BeginActiveOutcome, reserved) == 28);
};
