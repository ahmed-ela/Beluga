//! Public synchronous post-apply scalar seams; native actor enrollment remains closed.
//! 702 keeps AcceptedApplication within this call: fence, unpublished scalar
//! record, complete validation, permitted native output, infallible publication.
//! 704 is a SEPARATE fresh final peer/generation/revision fence after native
//! output and applied recording. Actual resources and exact rollback handle
//! remain native. Never use these seams for catch/failure's live negative prefix.
use core::{ffi::c_void, ptr};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Metadata, encode_edit, range};
use crate::native_owner_codec::disjoint;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CompletionRequest {
    pub abi: u32, pub operation: u32, pub invocation: u64,
    pub current_generation: u64, pub facts: u32, pub reserved: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CompletionOutcome {
    pub abi: u32, pub operation: u32, pub invocation: u64,
    pub disposition: u32, pub route: u32, pub fps_changed: u32, pub reserved: u32,
}
/// Nonthrowing synchronous native thunk; cannot deny after producing an effect.
/// Its caller-owned context holds the original capturer/base dimensions. It
/// neither awaits, reenters this frame/owner, mutates borrowed POD, nor unwinds.
pub type OutputCallback = unsafe extern "C" fn(*mut c_void, u64, i64);
/// Synchronous pre-effect native import/currentness validation. Borrowed draft
/// pointers expire on return; no concurrent access/mutation, await, reentry or
/// unwind. Import and read-only currentness checks only: no native effect,
/// resource acquisition, clock read or actor publication. Complete every
/// allocation, conversion and sticky/currentness check before accepting.
/// Only return1 admits output. Its context may retain a losslessly imported draft,
/// but cannot turn scalar identities into native authority or publish actor state.
pub type ValidationCallback = unsafe extern "C" fn(
    *mut c_void, u64, *const codec::Header, *const codec::Atom, u32,
    *const Metadata, *const CompletionOutcome, *const Edit, u32, *const Time, u32,
) -> u32;
enum ValidationMode {
    NotRequested,
    Required(Option<ValidationCallback>),
}

fn outcome_facts(r: CompletionRequest) -> ApplyOutcomeFacts {
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
    state: codec::Wire, metadata: Metadata, outcome: CompletionOutcome,
    edits: [Edit; 13], coordinates: [Time; 13], output_fps: Option<i64>,
}
fn evaluate(r: CompletionRequest, operation: u32, owner_header: codec::Header, owner_atoms: &[codec::Atom],
            prepared_header: codec::Header, prepared_atoms: &[codec::Atom]) -> Result<Bundle, u32> {
    let allowed = if operation == 702 { 511 } else { 1 };
    if r.abi != 1 || r.operation != operation || r.invocation == 0 ||
        r.facts & !allowed != 0 || r.reserved != 0 { return Err(2); }
    let current = codec::decode_owner_snapshot(owner_header, owner_atoms).map_err(|_| 2u32)?;
    let prepared = codec::decode_prepared_continuation(prepared_header, prepared_atoms).map_err(|_| 2u32)?;
    let before = values(&current);
    let mut draft = current;
    draft.begin_time_assignment_frame();
    let (disposition, route, output_fps) = if operation == 702 {
        match draft.success_fence(prepared, outcome_facts(r)) {
            SuccessFence::RollbackExactReturnedNativeHandle => (0, 0, None),
            SuccessFence::PermitOutput { fps_changed, accepted } => {
                // Pure precomputation does not publish applied before the effect.
                // AcceptedApplication is never serialized or reconstructed.
                draft.record_success_after_native_output(accepted);
                (1, 0, fps_changed.then_some(prepared.recommendation.fps))
            },
        }
    } else {
        match draft.final_adopt(prepared, PeerFacts { exact_peer: r.facts == 1,
            current_generation: r.current_generation }) {
            None => (0, 0, None), Some(action) => (1, route(action), None),
        }
    };
    if !draft.times.valid() || !draft.policy.times.valid() ||
        !draft.policy.queue.times.valid() || !draft.policy.rtt.times.valid() { return Err(5); }
    let after = values(&draft);
    let mut edits = [Edit::default(); 13];
    let mut coordinates = [Time::default(); 13];
    let prepared_times = {
        let mut projected = current; projected.policy = prepared.policy; values(&projected)
    };
    for (index, slot) in SLOTS.into_iter().enumerate() {
        let edit = draft.time_edit(slot);
        if index >= 9 {
            if edit != TimeEdit::Retain || before[index] != after[index] { return Err(5); }
            continue; // cadence/evidence sidecars are unowned zero, not clear
        }
        let expected = if operation == 702 || disposition == 0 {
            if edit != TimeEdit::Retain { return Err(5); }
            before[index]
        } else {
            match edit {
                TimeEdit::Set(origin) if origin == (Origin {
                    source: TimeSource::CorrespondingPreparedInput(slot), delta: 0,
                }) && prepared_times[index].is_some() => prepared_times[index],
                TimeEdit::Clear if prepared_times[index].is_none() => None,
                _ => return Err(5),
            }
        };
        if expected != after[index] { return Err(5); }
        edits[index] = encode_edit(edit)?;
        coordinates[index] = Time::encode(after[index]); coordinates[index].decode()?;
    }
    let state = codec::encode_owner(draft, codec::RESULT).map_err(|_| 2u32)?;
    codec::validate_result(state.header, &state.atoms).map_err(|_| 2u32)?;
    // Native output consumes Int32 FPS. Real sender success already validated
    // its narrower range; raw shape must also exclude a conversion trap BEFORE
    // calling the nonthrowing thunk. No new policy vote or post-effect error.
    if let Some(fps) = output_fps { i32::try_from(fps).map_err(|_| 2u32)?; }
    if operation == 702 {
        if state.atoms[..173] != owner_atoms[..173] { return Err(5); }
        if disposition == 0 && state.atoms.as_slice() != owner_atoms { return Err(5); }
    } else {
        if state.atoms[169..] != owner_atoms[169..] { return Err(5); }
        if disposition == 0 {
            if state.atoms.as_slice() != owner_atoms { return Err(5); }
        } else {
            if draft.revision != current.revision.wrapping_add(1) ||
                state.atoms[..168] != prepared_atoms[..168] { return Err(5); }
            // Do not turn a scalar route-presence projection into an added
            // policy vote. CopyIncoming may copy an absent Optional route;
            // exact retained/incoming sidecar custody belongs to the caller.
        }
    }
    let metadata = Metadata { abi: 1, operation, scope: 2, invocation: r.invocation,
        revision: draft.revision, peer: draft.policy.peer.unwrap_or(0),
        peer_present: draft.policy.peer.is_some() as u32, route,
        queue_fault: draft.policy.queue.faulted as u32, rtt_fault: draft.policy.rtt.faulted as u32,
        ..Metadata::default() };
    let outcome = CompletionOutcome { abi: 1, operation, invocation: r.invocation,
        disposition, route, fps_changed: output_fps.is_some() as u32, reserved: 0 };
    Ok(Bundle { state, metadata, outcome, edits, coordinates, output_fps })
}

unsafe fn boundary(
    operation: u32, request: *const CompletionRequest,
    owner_header: *const codec::Header, owner_atoms: *const codec::Atom, owner_count: u32,
    prepared_header: *const codec::Header, prepared_atoms: *const codec::Atom, prepared_count: u32,
    callback: Option<OutputCallback>, context: *mut c_void, validation: ValidationMode,
    output_header: *mut codec::Header, output_atoms: *mut codec::Atom, output_count: u32,
    metadata: *mut Metadata, outcome: *mut CompletionOutcome,
    edits: *mut Edit, edit_count: u32, coordinates: *mut Time, coordinate_count: u32,
) -> u32 {
    if owner_count != 179 || prepared_count != 222 || output_count != 179 ||
        edit_count != 13 || coordinate_count != 13 { return 2; }
    let ranges = [range(request, 1), range(owner_header, 1), range(owner_atoms, owner_count as usize),
        range(prepared_header, 1), range(prepared_atoms, prepared_count as usize),
        range(output_header, 1), range(output_atoms, output_count as usize), range(metadata, 1),
        range(outcome, 1), range(edits, edit_count as usize), range(coordinates, coordinate_count as usize)];
    if !disjoint(&ranges) || (operation == 702 && callback.is_none()) { return 2; }
    let validator = match validation {
        ValidationMode::NotRequested => None,
        ValidationMode::Required(None) => return 2,
        ValidationMode::Required(Some(validator)) => Some(validator),
    };
    let request = unsafe { ptr::read(request) };
    let current_header = unsafe { ptr::read(owner_header) };
    let current = unsafe { core::slice::from_raw_parts(owner_atoms, owner_count as usize) };
    let prepared_header = unsafe { ptr::read(prepared_header) };
    let prepared = unsafe { core::slice::from_raw_parts(prepared_atoms, prepared_count as usize) };
    let bundle = match evaluate(request, operation, current_header, current, prepared_header, prepared) {
        Ok(bundle) => bundle, Err(status) => return status,
    };
    if let Some(validator) = validator {
        let accepted = unsafe { validator(context, request.invocation,
            &bundle.state.header, bundle.state.atoms.as_ptr(), 179,
            &bundle.metadata, &bundle.outcome, bundle.edits.as_ptr(), 13,
            bundle.coordinates.as_ptr(), 13) };
        if accepted != 1 { return 3; }
    }
    // No allocation, fallible validation, await, recheck, or status branch after
    // an effect. The callback MUST uphold the caller's non-reentry/no-unwind
    // contract; raw integer ranges cannot prove that or any native identity.
    if let (Some(fps), Some(callback)) = (bundle.output_fps, callback) {
        unsafe { callback(context, request.invocation, fps); }
    }
    unsafe {
        ptr::write(output_header, bundle.state.header);
        ptr::copy_nonoverlapping(bundle.state.atoms.as_ptr(), output_atoms, output_count as usize);
        ptr::write(metadata, bundle.metadata); ptr::write(outcome, bundle.outcome);
        ptr::copy_nonoverlapping(bundle.edits.as_ptr(), edits, edit_count as usize);
        ptr::copy_nonoverlapping(bundle.coordinates.as_ptr(), coordinates, coordinate_count as usize);
    }
    1
}

/// Status1 complete;2 shape/range/strict scalar domain;5 invalid result/journal.
/// Every non1 leaves six outputs unchanged AND performs no native effect. A
/// rollback decision is status1/disposition0, not an infrastructure failure.
#[no_mangle]
#[must_use]
pub unsafe extern "C" fn beluga_core_network_adaptation_owner_finish_success(
    request: *const CompletionRequest,
    owner_header: *const codec::Header, owner_atoms: *const codec::Atom, owner_count: u32,
    prepared_header: *const codec::Header, prepared_atoms: *const codec::Atom, prepared_count: u32,
    callback: Option<OutputCallback>, context: *mut c_void,
    output_header: *mut codec::Header, output_atoms: *mut codec::Atom, output_count: u32,
    metadata: *mut Metadata, outcome: *mut CompletionOutcome,
    edits: *mut Edit, edit_count: u32, coordinates: *mut Time, coordinate_count: u32,
) -> u32 {
    unsafe { boundary(702, request, owner_header, owner_atoms, owner_count, prepared_header, prepared_atoms,
        prepared_count, callback, context, ValidationMode::NotRequested,
        output_header, output_atoms, output_count,
        metadata, outcome, edits, edit_count, coordinates, coordinate_count) }
}
/// Additive702: one complete private evaluation, mandatory native validation,
/// then conditional FPS and infallible publication. Denial3 calls no FPS thunk
/// and writes no outputs, including stale rollback and same-FPS bundles. The
/// trusted validator itself must uphold its effect-free/lifetime contract.
#[no_mangle]
#[must_use]
pub unsafe extern "C" fn beluga_core_network_adaptation_owner_finish_success_validated(
    request: *const CompletionRequest,
    owner_header: *const codec::Header, owner_atoms: *const codec::Atom, owner_count: u32,
    prepared_header: *const codec::Header, prepared_atoms: *const codec::Atom, prepared_count: u32,
    validator: Option<ValidationCallback>, callback: Option<OutputCallback>, context: *mut c_void,
    output_header: *mut codec::Header, output_atoms: *mut codec::Atom, output_count: u32,
    metadata: *mut Metadata, outcome: *mut CompletionOutcome,
    edits: *mut Edit, edit_count: u32, coordinates: *mut Time, coordinate_count: u32,
) -> u32 {
    unsafe { boundary(702, request, owner_header, owner_atoms, owner_count, prepared_header, prepared_atoms,
        prepared_count, callback, context, ValidationMode::Required(validator),
        output_header, output_atoms, output_count,
        metadata, outcome, edits, edit_count, coordinates, coordinate_count) }
}
/// Separate original final fence; never reuse the pre-output facts for this call.
#[no_mangle]
#[must_use]
pub unsafe extern "C" fn beluga_core_network_adaptation_owner_final_adopt(
    request: *const CompletionRequest,
    owner_header: *const codec::Header, owner_atoms: *const codec::Atom, owner_count: u32,
    prepared_header: *const codec::Header, prepared_atoms: *const codec::Atom, prepared_count: u32,
    output_header: *mut codec::Header, output_atoms: *mut codec::Atom, output_count: u32,
    metadata: *mut Metadata, outcome: *mut CompletionOutcome,
    edits: *mut Edit, edit_count: u32, coordinates: *mut Time, coordinate_count: u32,
) -> u32 {
    unsafe { boundary(704, request, owner_header, owner_atoms, owner_count, prepared_header, prepared_atoms,
        prepared_count, None, ptr::null_mut(), ValidationMode::NotRequested,
        output_header, output_atoms, output_count,
        metadata, outcome, edits, edit_count, coordinates, coordinate_count) }
}
const _: () = {
    assert!(core::mem::size_of::<CompletionRequest>() == 32);
    assert!(core::mem::align_of::<CompletionRequest>() == 8);
    assert!(core::mem::offset_of!(CompletionRequest, abi) == 0);
    assert!(core::mem::offset_of!(CompletionRequest, operation) == 4);
    assert!(core::mem::offset_of!(CompletionRequest, invocation) == 8);
    assert!(core::mem::offset_of!(CompletionRequest, current_generation) == 16);
    assert!(core::mem::offset_of!(CompletionRequest, facts) == 24);
    assert!(core::mem::offset_of!(CompletionRequest, reserved) == 28);
    assert!(core::mem::size_of::<CompletionOutcome>() == 32);
    assert!(core::mem::align_of::<CompletionOutcome>() == 8);
    assert!(core::mem::offset_of!(CompletionOutcome, abi) == 0);
    assert!(core::mem::offset_of!(CompletionOutcome, operation) == 4);
    assert!(core::mem::offset_of!(CompletionOutcome, invocation) == 8);
    assert!(core::mem::offset_of!(CompletionOutcome, disposition) == 16);
    assert!(core::mem::offset_of!(CompletionOutcome, route) == 20);
    assert!(core::mem::offset_of!(CompletionOutcome, fps_changed) == 24);
    assert!(core::mem::offset_of!(CompletionOutcome, reserved) == 28);
};
