//! Source-only proposal: one copied per-key retry history, never native authority.
//! No keys, FIFO, peer/track/output handles, callbacks, clocks, timers or globals.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;
pub const STATUS_INVALID: u32 = 0;
pub const STATUS_ACCEPTED: u32 = 1;
pub const OP_ELIGIBLE: u32 = 1;
pub const OP_RECORD_ATTEMPT: u32 = 2;
pub const OP_RETRY_FAILURE: u32 = 3;
pub const OP_EXHAUST: u32 = 4;
pub const REDRIVE_RETAIN: u32 = 0;
pub const REDRIVE_CLEAR: u32 = 1;
pub const REDRIVE_REQUEST: u32 = 2;

/// Constructor input is the actual Swift driver's already-clamped maximum.
/// This step does not manufacture or replace configuration.
#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawConfig {
    pub abi_version: u32,
    pub reserved: u32,
    pub maximum_attempt_count: i64,
}

/// present=0 requires count=0 and may_retry=0. A present history has count>=1.
/// Counts above the configured cap remain representable and deny retry, as Swift
/// comparisons do; they are not silently clamped or reset.
#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawState {
    pub abi_version: u32,
    pub present: u32,
    pub may_retry: u32,
    pub reserved: u32,
    pub count: i64,
}

/// failure_category is used only by RETRY_FAILURE:
/// 1 monitoringFailed, 2 outputUnavailable, 3 startFailed, 4 admissionFailed,
/// 5 readinessFailed, 6 sourceMediaStalled, 7 formatUnsafe, 8 sharedClockUnsafe,
/// 9 runtimeEnqueueFailed, 10 runtimeProgressStalled, 11 evidenceBridgeRefused.
/// Other operations require category=0. bridge_faulted is used by ELIGIBLE and
/// RETRY_FAILURE only; RECORD_ATTEMPT and EXHAUST require its canonical zero.
#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawEvent {
    pub opcode: u32,
    pub failure_category: u32,
    pub bridge_faulted: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub state: RawState,
    pub status: u32,
    /// ELIGIBLE: may attempt. RETRY_FAILURE: marked retryable.
    /// RECORD_ATTEMPT and EXHAUST: canonical zero. Check status first.
    pub decision: u32,
    /// Explicit caller disposition. Invalid/ELIGIBLE/RECORD_ATTEMPT retain.
    /// RETRY_FAILURE requests or clears; EXHAUST clears only existing history.
    pub redrive_action: u32,
    pub reserved: u32,
}

const _: [(); 16] = [(); size_of::<RawConfig>()];
const _: [(); 24] = [(); size_of::<RawState>()];
const _: [(); 16] = [(); size_of::<RawEvent>()];
const _: [(); 40] = [(); size_of::<RawResult>()];
const _: [(); 8] = [(); align_of::<RawConfig>()];
const _: [(); 8] = [(); align_of::<RawState>()];
const _: [(); 4] = [(); align_of::<RawEvent>()];
const _: [(); 8] = [(); align_of::<RawResult>()];

#[derive(Clone, Copy)]
struct History {
    count: i64,
    may_retry: bool,
}

fn history(raw: RawState) -> Option<Option<History>> {
    if raw.abi_version != ABI_VERSION || raw.reserved != 0 || raw.may_retry > 1 {
        return None;
    }
    match raw.present {
        0 if raw.count == 0 && raw.may_retry == 0 => Some(None),
        1 if raw.count >= 1 => Some(Some(History {
            count: raw.count,
            may_retry: raw.may_retry == 1,
        })),
        _ => None,
    }
}

fn retryable(category: u32) -> Option<bool> {
    match category {
        2 | 3 | 5 | 6 | 9 | 10 => Some(true),
        1 | 4 | 7 | 8 | 11 => Some(false),
        _ => None,
    }
}

/// A malformed envelope, category/operation, or unrepresentable increment
/// returns status=0 and the exact unchanged input state. This is not a valid
/// false vote. Native callers must not use it as a successful fallback.
#[must_use]
pub fn step(config: RawConfig, before: RawState, event: RawEvent) -> RawResult {
    let invalid = RawResult {
        state: before,
        status: STATUS_INVALID,
        decision: 0,
        redrive_action: REDRIVE_RETAIN,
        reserved: 0,
    };
    if config.abi_version != ABI_VERSION || config.reserved != 0
        || config.maximum_attempt_count < 1
        || event.reserved != 0 || event.bridge_faulted > 1
    {
        return invalid;
    }
    let Some(old) = history(before) else { return invalid; };
    let mut result = RawResult {
        state: before,
        status: STATUS_ACCEPTED,
        decision: 0,
        redrive_action: REDRIVE_RETAIN,
        reserved: 0,
    };
    match event.opcode {
        OP_ELIGIBLE => {
            if event.failure_category != 0 { return invalid; }
            result.decision = u32::from(event.bridge_faulted == 0
                && old.map_or(true, |h| h.may_retry && h.count < config.maximum_attempt_count));
        }
        OP_RECORD_ATTEMPT => {
            if event.failure_category != 0 || event.bridge_faulted != 0 {
                return invalid;
            }
            let count = match old {
                None => 1,
                Some(h) => {
                    let Some(next) = h.count.checked_add(1) else { return invalid; };
                    next
                }
            };
            result.state = RawState {
                abi_version: ABI_VERSION,
                present: 1,
                may_retry: 0,
                reserved: 0,
                count,
            };
        }
        OP_RETRY_FAILURE => {
            let Some(category_retryable) = retryable(event.failure_category) else {
                return invalid;
            };
            let marked = event.bridge_faulted == 0 && category_retryable
                && old.is_some_and(|h| h.count < config.maximum_attempt_count);
            result.decision = u32::from(marked);
            result.redrive_action = if marked { REDRIVE_REQUEST } else { REDRIVE_CLEAR };
            if marked { result.state.may_retry = 1; }
        }
        OP_EXHAUST => {
            if event.failure_category != 0 || event.bridge_faulted != 0 {
                return invalid;
            }
            if old.is_some() {
                result.state.may_retry = 0;
                result.redrive_action = REDRIVE_CLEAR;
            }
        }
        _ => return invalid,
    }
    result
}

/// Result correlation only: recompute the unchanged raw function, require an
/// accepted expected status and compare every field. No invalid status=0 match
/// is accepted, no side effect is replayed and no native authority is granted.
#[must_use]
pub fn result_is_valid(
    config: RawConfig,
    before: RawState,
    event: RawEvent,
    result: RawResult,
) -> u32 {
    let expected = step(config, before, event);
    u32::from(expected.status == STATUS_ACCEPTED && expected == result)
}
