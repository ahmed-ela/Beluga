//! Copied fresh-unarmed reason selection after the native owner's unchanged
//! eligibility, SDK-idle and retained-authority observations. Native identities,
//! error objects, candidate payload, callbacks and retirement never cross here.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;
pub const STATUS_VALID: u32 = 0;
pub const STATUS_INVALID: u32 = 1;
pub const FAILURE_ABSENT: u32 = 0;
pub const FAILURE_FEED_FETCH: u32 = 1;
pub const FAILURE_FEED_PARSE_OR_SIGNATURE: u32 = 2;

pub const NO_UPDATE_PRESENT: u32 = 1 << 0;
pub const NO_UPDATE_IS_FINISHED: u32 = 1 << 1;
pub const BOUND_CANDIDATE_PRESENT: u32 = 1 << 2;
pub const ADMITTED_ITEM_PRESENT: u32 = 1 << 3;
pub const DECLINE_PRESENT: u32 = 1 << 4;
pub const CANCELLED_INITIAL_CHECK: u32 = 1 << 5;
pub const FAILURE_ACKNOWLEDGED: u32 = 1 << 6;
pub const FAILURE_ABORT_OBSERVED: u32 = 1 << 7;
pub const FAILURE_IS_FINISHED: u32 = 1 << 8;
pub const INITIAL_PRESENTATION_PRESENT: u32 = 1 << 9;
pub const CANDIDATE_ADMISSION_ATTEMPTED: u32 = 1 << 10;
pub const CANDIDATE_PRESENTATION_OBSERVED: u32 = 1 << 11;
pub const CANDIDATE_BINDING_IN_PROGRESS: u32 = 1 << 12;
pub const FOUND_ITEM_PRESENT: u32 = 1 << 13;
pub const FINISHED_ERROR_PRESENT: u32 = 1 << 14;
pub const DECLINE_SDK_CHOICE_OBSERVED: u32 = 1 << 15;
pub const BOUND_MATCHES_DECLINE: u32 = 1 << 16;
pub const ADMITTED_MATCHES_DECLINE: u32 = 1 << 17;
pub const FOUND_MATCHES_DECLINE: u32 = 1 << 18;
pub const KNOWN_FLAGS: u32 = (1 << 19) - 1;

pub const REASON_NONE: u32 = 0;
pub const REASON_NO_UPDATE: u32 = 1;
pub const REASON_FEED_FETCH_FAILURE: u32 = 2;
pub const REASON_FEED_PARSE_FAILURE: u32 = 3;
pub const REASON_CANCELLED_CHECK: u32 = 4;
pub const REASON_DECLINED_CANDIDATE: u32 = 5;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawRequest {
    pub abi_version: u32,
    pub flags: u32,
    /// Separately closed native enum: 0 absent,1 feed fetch,2 feed parse/signature.
    pub failure_kind: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub abi_version: u32,
    pub status: u32,
    pub reason: u32,
}

const _: [(); 12] = [(); size_of::<RawRequest>()];
const _: [(); 12] = [(); size_of::<RawResult>()];
const _: [(); 4] = [(); align_of::<RawRequest>()];
const _: [(); 4] = [(); align_of::<RawResult>()];

fn has(flags: u32, bit: u32) -> bool { flags & bit != 0 }

/// These are the original four inner branches, not native eligibility proof.
/// Do not add found-item or candidate-attempt exclusions to the branches which
/// originally omit them. Failed-kind validity is independent of Boolean facts.
#[must_use]
pub fn decide(request: RawRequest) -> RawResult {
    let invalid = RawResult { abi_version: ABI_VERSION, status: STATUS_INVALID, reason: REASON_NONE };
    if request.abi_version != ABI_VERSION || request.flags & !KNOWN_FLAGS != 0
        || request.failure_kind > FAILURE_FEED_PARSE_OR_SIGNATURE {
        return invalid;
    }
    let f = request.flags;
    let failure_present = request.failure_kind != FAILURE_ABSENT;
    let reason = if has(f, NO_UPDATE_PRESENT) && has(f, NO_UPDATE_IS_FINISHED)
        && !has(f, BOUND_CANDIDATE_PRESENT) && !has(f, ADMITTED_ITEM_PRESENT)
        && !has(f, DECLINE_PRESENT) && !failure_present && !has(f, CANCELLED_INITIAL_CHECK) {
        REASON_NO_UPDATE
    } else if failure_present && has(f, FAILURE_ACKNOWLEDGED)
        && has(f, FAILURE_ABORT_OBSERVED) && has(f, FAILURE_IS_FINISHED)
        && has(f, INITIAL_PRESENTATION_PRESENT) && !has(f, CANDIDATE_ADMISSION_ATTEMPTED)
        && !has(f, CANDIDATE_PRESENTATION_OBSERVED) && !has(f, CANDIDATE_BINDING_IN_PROGRESS)
        && !has(f, ADMITTED_ITEM_PRESENT) && !has(f, FOUND_ITEM_PRESENT)
        && !has(f, BOUND_CANDIDATE_PRESENT) && !has(f, NO_UPDATE_PRESENT)
        && !has(f, DECLINE_PRESENT) && !has(f, CANCELLED_INITIAL_CHECK) {
        if request.failure_kind == FAILURE_FEED_FETCH {
            REASON_FEED_FETCH_FAILURE
        } else {
            REASON_FEED_PARSE_FAILURE
        }
    } else if !has(f, FINISHED_ERROR_PRESENT) && !has(f, NO_UPDATE_PRESENT)
        && has(f, CANCELLED_INITIAL_CHECK) && has(f, INITIAL_PRESENTATION_PRESENT)
        && !has(f, BOUND_CANDIDATE_PRESENT) && !has(f, ADMITTED_ITEM_PRESENT)
        && !has(f, DECLINE_PRESENT) && !failure_present {
        REASON_CANCELLED_CHECK
    } else if !has(f, FINISHED_ERROR_PRESENT) && !has(f, NO_UPDATE_PRESENT)
        && !has(f, CANCELLED_INITIAL_CHECK) && !failure_present
        && has(f, DECLINE_PRESENT) && has(f, DECLINE_SDK_CHOICE_OBSERVED)
        && has(f, BOUND_MATCHES_DECLINE) && has(f, ADMITTED_MATCHES_DECLINE)
        && has(f, FOUND_MATCHES_DECLINE) {
        REASON_DECLINED_CANDIDATE
    } else { REASON_NONE };
    RawResult { abi_version: ABI_VERSION, status: STATUS_VALID, reason }
}

/// Whole-result correlation. Even the exact invalid refusal never constitutes
/// a valid ordinary no-completion result. No payload or native authority is made.
#[must_use]
pub fn result_is_valid(request: RawRequest, result: RawResult) -> u32 {
    let expected = decide(request);
    u32::from(expected.status == STATUS_VALID && result == expected)
}
