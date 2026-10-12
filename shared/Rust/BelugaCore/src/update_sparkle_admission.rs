//! Two copied phases of manual Sparkle check admission only.
//! The native owner performs exact callback matching, invokes retained authority
//! once between phases, reads the requested bit freshly and owns all assignments.
//! No callback, object identity, SDK object, task or native authority crosses here.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;
pub const STATUS_VALID: u32 = 0;
pub const STATUS_INVALID: u32 = 1;
pub const PHASE_PREFLIGHT: u32 = 1;
pub const PHASE_AFTER_AUTHORITY: u32 = 2;

pub const EXACT_CALLBACK: u32 = 1 << 0;
pub const MANUAL_UPDATES: u32 = 1 << 1;
pub const PRE_CALLBACK_RUNNING: u32 = 1 << 2;
pub const PREFLIGHT_KNOWN_FLAGS: u32 = 7;
pub const RETAINED_AUTHORITY: u32 = 1 << 0;
pub const FRESH_REQUESTED: u32 = 1 << 1;
pub const AFTER_AUTHORITY_KNOWN_FLAGS: u32 = 3;

pub const ACTION_NONE: u32 = 0;
pub const ACTION_FOREIGN: u32 = 1;
pub const ACTION_NON_MANUAL: u32 = 2;
pub const ACTION_AUTHORITY_NOT_RETAINED: u32 = 3;
pub const ACTION_CHECK_NOT_REQUESTED: u32 = 4;
pub const ACTION_QUERY_AUTHORITY: u32 = 5;
pub const ACTION_CONSUME_AND_ADMIT: u32 = 6;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawRequest {
    pub abi_version: u32,
    pub phase: u32,
    pub flags: u32,
}

/// A closed copied outcome, never proof that a native callback was invoked.
#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub abi_version: u32,
    pub status: u32,
    pub action: u32,
}

const _: [(); 12] = [(); size_of::<RawRequest>()];
const _: [(); 12] = [(); size_of::<RawResult>()];
const _: [(); 4] = [(); align_of::<RawRequest>()];
const _: [(); 4] = [(); align_of::<RawResult>()];

fn has(flags: u32, bit: u32) -> bool { flags & bit != 0 }

/// Preserve the original error precedence without querying authority eagerly.
/// Only a verified phase-one query permits the native owner to invoke its
/// retained-authority callback. Only a verified phase-two admission permits the
/// native owner to consume its current request and mark its current cycle.
#[must_use]
pub fn decide(request: RawRequest) -> RawResult {
    let invalid = RawResult {
        abi_version: ABI_VERSION,
        status: STATUS_INVALID, // USA-M12
        action: ACTION_NONE, // USA-M13
    };
    if request.abi_version != ABI_VERSION { return invalid; } // USA-M01
    let action = match request.phase {
        PHASE_PREFLIGHT => {
            if request.flags & !PREFLIGHT_KNOWN_FLAGS != 0 { return invalid; } // USA-M03
            if !has(request.flags, EXACT_CALLBACK) { ACTION_FOREIGN } // USA-M05
            else if !has(request.flags, MANUAL_UPDATES) { ACTION_NON_MANUAL } // USA-M06
            else if !has(request.flags, PRE_CALLBACK_RUNNING) { ACTION_AUTHORITY_NOT_RETAINED } // USA-M07
            else { ACTION_QUERY_AUTHORITY } // USA-M08
        }
        PHASE_AFTER_AUTHORITY => {
            if request.flags & !AFTER_AUTHORITY_KNOWN_FLAGS != 0 { return invalid; } // USA-M04
            if !has(request.flags, RETAINED_AUTHORITY) { ACTION_AUTHORITY_NOT_RETAINED } // USA-M09
            else if !has(request.flags, FRESH_REQUESTED) { ACTION_CHECK_NOT_REQUESTED } // USA-M10
            else { ACTION_CONSUME_AND_ADMIT } // USA-M11
        }
        _ => return invalid, // USA-M02
    };
    RawResult {
        abi_version: ABI_VERSION, // USA-M17
        status: STATUS_VALID, // USA-M14
        action,
    }
}

/// Whole copied-result correlation only. The verifier is callback-free and
/// rejects malformed input even when its exact canonical refusal is supplied.
#[must_use]
pub fn result_is_valid(request: RawRequest, result: RawResult) -> u32 {
    let expected = decide(request);
    let input_is_valid = expected.status == STATUS_VALID; // USA-M16
    u32::from(input_is_valid && expected == result) // USA-M15
}
