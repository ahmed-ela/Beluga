//! Proposed product namespace for five existing zero-clock Owner cuts.
//! No native resource/ACK/stop/resume admission is conferred by these numeric
//! snapshots. The caller retains the actor, route and actual Instant sidecars.
//! This bridge forwards to the reviewed complete-state implementation; it is not
//! a second reducer and never imports an observed policy or calls a provider.
use core::ptr;
use crate::native_clock_assay::{range, Edit, Metadata, Reply, Time};
use crate::native_owner_codec::disjoint;
use crate::native_owner_events::{beluga_private_owner_event, EventRequest};
use crate::network_adaptation_candidate::state_codec::{Atom, Header};

pub type RawOwnerEventRequest = EventRequest;
pub const OWNER_STOP_SAMPLING: u32 = 105;
pub const OWNER_ACTIVATE_SHOW: u32 = 106;
pub const OWNER_RESUME_WITHOUT_REVISION: u32 = 107;
pub const OWNER_RESUME_AND_ADVANCE: u32 = 108;
pub const OWNER_COLLECTOR_GATE: u32 = 109;

/// Status 1: all six outputs contain the complete validated result. Status 2:
/// unsupported operation or malformed shape; all outputs remain untouched.
/// Inputs and all exact-sized outputs must be initialized, aligned, mutually
/// disjoint, live and not concurrently mutated until return. These range checks
/// cannot establish allocation provenance, lifetime or native identity.
/// Output writes are sequential; publish the correlated tuple only after return.
/// No callback/observed input exists, and all fifteen reply slots are zero on 1.
#[no_mangle]
#[must_use]
pub unsafe extern "C" fn beluga_core_network_adaptation_owner_zero_clock_event(
    request: *const RawOwnerEventRequest,
    header: *const Header, atoms: *const Atom, count: u32,
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
    // Only the initialized request is read before this closed Owner-only vote.
    // Policy-only 101–104 and clock-reading 202 cannot reach the state decoder.
    let operation = unsafe { ptr::read(request) }.operation;
    if !matches!(operation, OWNER_STOP_SAMPLING | OWNER_ACTIVATE_SHOW |
        OWNER_RESUME_WITHOUT_REVISION | OWNER_RESUME_AND_ADVANCE | OWNER_COLLECTOR_GATE) {
        return 2;
    }
    if !disjoint(&[
        range(request, 1), range(header, 1), range(atoms, count as usize),
        range(output_header, 1), range(output_atoms, output_count as usize),
        range(metadata, 1), range(edits, edit_count as usize),
        range(coordinates, coordinate_count as usize), range(reads, read_count as usize),
    ]) { return 2; }
    unsafe {
        beluga_private_owner_event(request, header, atoms, count,
            ptr::null(), ptr::null(), 0,
            output_header, output_atoms, metadata, edits, coordinates, reads)
    }
}
