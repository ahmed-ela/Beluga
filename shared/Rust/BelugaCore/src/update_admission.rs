//! Copied update admission and menu presentation only; no tasks or SDK authority.
//! Native code owns Bundle validation, callbacks, UUIDs, fences and runtime effects.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;
pub const STATUS_VALID: u32 = 0;
pub const STATUS_INVALID: u32 = 1;
pub const INTERACTIVE: u32 = 1 << 0;
pub const ACTIVE_MEDIA: u32 = 1 << 1;
pub const PENDING_PAIRING: u32 = 1 << 2;
pub const AUDIO_SHARES: u32 = 1 << 3;
pub const TEARDOWN_COMPLETE: u32 = 1 << 4;
pub const RELEASE: u32 = 1 << 5;
pub const TASK_PRESENT: u32 = 1 << 6;
pub const NEEDS_READINESS: u32 = 1 << 7;
pub const FAILED: u32 = 1 << 8;
pub const KNOWN_FLAGS: u32 = 511;

pub const KIND_DEVELOPMENT: u32 = 0;
pub const KIND_RECOVERY: u32 = 1;
pub const KIND_OWNED: u32 = 2;
pub const KIND_READY: u32 = 3;
pub const KIND_UNAVAILABLE: u32 = 4;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawRequest {
    pub abi_version: u32,
    pub flags: u32,
}

/// Closed canonical booleans and symbolic presentation; never a native effect.
#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub abi_version: u32,
    pub status: u32,
    pub permits_update: u32,
    pub is_in_progress: u32,
    pub can_check: u32,
    pub status_kind: u32,
}

const _: [(); 8] = [(); size_of::<RawRequest>()];
const _: [(); 24] = [(); size_of::<RawResult>()];
const _: [(); 4] = [(); align_of::<RawRequest>()];
const _: [(); 4] = [(); align_of::<RawResult>()];

fn has(flags: u32, bit: u32) -> bool { flags & bit != 0 }

/// ABI/flag refusal is not a valid false vote. Its conservative busy/recovery
/// shape cannot reopen streaming or check/install permission.
#[must_use]
pub fn decide(request: RawRequest) -> RawResult {
    let invalid = RawResult {
        abi_version: ABI_VERSION,
        status: STATUS_INVALID,
        permits_update: 0,
        is_in_progress: 1,
        can_check: 0,
        status_kind: KIND_RECOVERY,
    };
    if request.abi_version != ABI_VERSION { return invalid; } // UA-M01
    if request.flags & !KNOWN_FLAGS != 0 { return invalid; } // UA-M02
    let flags = request.flags;
    let permits_update = has(flags, INTERACTIVE) // UA-M03
        && !has(flags, ACTIVE_MEDIA) // UA-M04
        && !has(flags, PENDING_PAIRING) // UA-M05
        && !has(flags, AUDIO_SHARES) // UA-M06
        && has(flags, TEARDOWN_COMPLETE); // UA-M07
    let release = has(flags, RELEASE);
    let task_present = has(flags, TASK_PRESENT); // UA-M09
    let needs_readiness = has(flags, NEEDS_READINESS); // UA-M10
    let failed = has(flags, FAILED); // UA-M11
    let is_in_progress = release && (task_present || needs_readiness || failed); // UA-M08
    let can_check = release && !is_in_progress && permits_update; // UA-M14
    let status_kind = if !release {
        KIND_DEVELOPMENT // UA-M15
    } else if failed {
        KIND_RECOVERY // UA-M12
    } else if task_present || needs_readiness {
        KIND_OWNED // UA-M16
    } else if permits_update {
        KIND_READY // UA-M17
    } else {
        KIND_UNAVAILABLE
    };
    RawResult {
        abi_version: ABI_VERSION,
        status: STATUS_VALID,
        permits_update: u32::from(permits_update),
        is_in_progress: u32::from(is_in_progress),
        can_check: u32::from(can_check),
        status_kind,
    }
}

/// Valid-input whole-result correlation. No native action is replayed and no
/// invalid carrier, even its exact refusal output, is accepted by this verifier.
#[must_use]
pub fn result_is_valid(request: RawRequest, result: RawResult) -> u32 {
    let expected = decide(request);
    u32::from(expected.status == STATUS_VALID && expected == result) // UA-M13
}
