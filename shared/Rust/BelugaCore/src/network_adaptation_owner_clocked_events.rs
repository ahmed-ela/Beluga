//! Source-only product namespace for the existing complete-owner clocked cuts.
//! This wrapper closes the operation/count surface and forwards to the reviewed
//! implementation; it neither reauthors policy nor grants native effect authority.
use core::{ffi::c_void, ptr};
use crate::native_clock_assay::{range, Callback, Edit, Metadata, Reply, Time};
use crate::native_owner_clock_events::{beluga_private_owner_clock_event, ClockEventRequest};
use crate::native_owner_codec::disjoint;
use crate::network_adaptation_candidate::state_codec::{Atom, Header};

pub type RawOwnerClockedEventRequest = ClockEventRequest;
pub const OWNER_END_SHOW_WITHOUT_REVISION: u32 = 202;
pub const OWNER_ROUTE_INVALIDATED: u32 = 212;
pub const OWNER_END_SHOW_AND_ADVANCE: u32 = 213;
pub const OWNER_VISIBILITY_COMMAND: u32 = 214;
pub const OWNER_HIDE_HEALTH_REVOCATION: u32 = 215;
pub const OWNER_BEGIN_POST_RESUME_EPOCH: u32 = 216;
pub const OWNER_RESUME_ACCEPTED: u32 = 217;
pub const OWNER_RESUME_FAILED_AND_ADVANCE: u32 = 218;

/// Status 1 publishes all six correlated outputs; 2 rejects shape/arithmetic,
/// 3 rejects a provider read, 4 rejects its reply, 5 rejects a time witness.
/// Every non-1 return leaves all six outputs untouched, but cannot undo external
/// callback effects. Inputs/outputs are initialized, exact-sized, aligned, live,
/// mutually disjoint and not concurrently modified until return. The callback
/// is synchronous and must not mutate/free borrowed buffers, unwind, or reenter
/// the same native owner frame. The caller supplies/guards its context lifetime,
/// exact native read plan, actor identity and actual Instant sidecars. Pointer
/// ranges and numeric request fields do not prove any of those authorities.
/// Sequential writes are not an atomic commit: validate the whole native tuple
/// after return before publishing it. No observed-policy input is accepted.
#[no_mangle]
#[must_use]
pub unsafe extern "C" fn beluga_core_network_adaptation_owner_clocked_event(
    request: *const RawOwnerClockedEventRequest,
    header: *const Header, atoms: *const Atom, count: u32,
    callback: Option<Callback>, context: *mut c_void,
    output_header: *mut Header, output_atoms: *mut Atom, output_count: u32,
    metadata: *mut Metadata,
    edits: *mut Edit, edit_count: u32,
    coordinates: *mut Time, coordinate_count: u32,
    reads: *mut Reply, read_count: u32,
) -> u32 {
    if count != 179 || output_count != 179 || edit_count != 13 ||
        coordinate_count != 13 || read_count != 15 || range(request, 1).is_none() {
        return 2;
    }
    // Read only the initialized request before the closed operation vote.
    let operation = unsafe { ptr::read(request) }.operation;
    if !matches!(operation, OWNER_END_SHOW_WITHOUT_REVISION | OWNER_ROUTE_INVALIDATED |
        OWNER_END_SHOW_AND_ADVANCE | OWNER_VISIBILITY_COMMAND | OWNER_HIDE_HEALTH_REVOCATION |
        OWNER_BEGIN_POST_RESUME_EPOCH | OWNER_RESUME_ACCEPTED | OWNER_RESUME_FAILED_AND_ADVANCE) {
        return 2;
    }
    if !disjoint(&[
        range(request, 1), range(header, 1), range(atoms, count as usize),
        range(output_header, 1), range(output_atoms, output_count as usize),
        range(metadata, 1), range(edits, edit_count as usize),
        range(coordinates, coordinate_count as usize), range(reads, read_count as usize),
    ]) { return 2; }
    unsafe {
        beluga_private_owner_clock_event(request, header, atoms, count,
            ptr::null(), ptr::null(), 0, callback, context,
            output_header, output_atoms, metadata, edits, coordinates, reads)
    }
}
