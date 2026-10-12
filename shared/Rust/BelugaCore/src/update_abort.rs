//! Copied abort-event decision only; native error identity and mutation stay native.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;
pub const STATUS_VALID: u32 = 0;
pub const STATUS_INVALID: u32 = 1;
pub const FAILURE_PRESENT: u32 = 1 << 0;
pub const CLEAN_UNARMED_CYCLE: u32 = 1 << 1;
pub const ACKNOWLEDGED: u32 = 1 << 2;
pub const OBSERVED_ABORT: u32 = 1 << 3;
pub const SAME_FAILURE_ERROR: u32 = 1 << 4;
pub const SAME_NO_UPDATE_ERROR: u32 = 1 << 5;
pub const KNOWN_FLAGS: u32 = (1 << 6) - 1;
pub const ACTION_INVALID: u32 = 0;
pub const ACTION_MARK_ABORT: u32 = 1;
pub const ACTION_PRESERVE: u32 = 2;
pub const ACTION_POISON: u32 = 3;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawRequest {
    pub abi_version: u32,
    pub flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub abi_version: u32,
    pub status: u32,
    pub action: u32,
}

const _: [(); 8] = [(); size_of::<RawRequest>()];
const _: [(); 12] = [(); size_of::<RawResult>()];
const _: [(); 4] = [(); align_of::<RawRequest>()];
const _: [(); 4] = [(); align_of::<RawResult>()];

fn has(flags: u32, bit: u32) -> bool { flags & bit != 0 }

#[must_use]
pub fn decide(request: RawRequest) -> RawResult {
    if request.abi_version != ABI_VERSION || request.flags & !KNOWN_FLAGS != 0 {
        return RawResult { abi_version: ABI_VERSION, status: STATUS_INVALID, action: ACTION_INVALID };
    }
    let f = request.flags;
    let action = if has(f, FAILURE_PRESENT)
        && has(f, CLEAN_UNARMED_CYCLE)
        && has(f, ACKNOWLEDGED)
        && !has(f, OBSERVED_ABORT)
        && has(f, SAME_FAILURE_ERROR) {
        ACTION_MARK_ABORT
    } else if has(f, SAME_NO_UPDATE_ERROR) {
        ACTION_PRESERVE
    } else {
        ACTION_POISON
    };
    RawResult { abi_version: ABI_VERSION, status: STATUS_VALID, action }
}

#[must_use]
pub fn result_is_valid(request: RawRequest, result: RawResult) -> u32 {
    let expected = decide(request);
    u32::from(expected.status == STATUS_VALID && result == expected)
}
