//! Scalar coordinator votes only. This module owns no route, lease key,
//! generation, authorization, listener, callback, clock, or cleanup effect.

pub const ABI_VERSION: u32 = 1;
pub const ACQUISITION_BUDGET: u32 = 1;
pub const ACQUISITION_OUTCOME: u32 = 2;
pub const RELEASE_CONTINUATION: u32 = 3;
pub const RELEASE_OUTCOME: u32 = 4;

pub const ACQUIRE: u32 = 1;
pub const BUDGET_EXHAUSTED: u32 = 2;
pub const AUTHORIZE_ACQUIRED: u32 = 3;
pub const RETRY_ACQUISITION: u32 = 4;
pub const TERMINAL_ACQUISITION: u32 = 5;
pub const RETRY_RELEASE: u32 = 6;
pub const FINISH_RELEASE: u32 = 7;
pub const USE_NATIVE_FALLBACK: u32 = 8;
pub const RELEASED: u32 = 9;
pub const DEGRADED: u32 = 10;

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RawFacts {
    pub abi_version: u32,
    pub opcode: u32,
    /// Acquisition: 1 acquired, 2 retryable, 3 terminal.
    /// Release: 0 no change, 1 released, 2 retryable, 3 externally superseded.
    /// This is a copied native result, never a native ownership proof.
    pub disposition: u32,
    pub reserved: u32,
    pub attempt_count: i64,
    pub maximum_attempt_count: i64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RawResult {
    pub abi_version: u32,
    /// 0 refused, 1 accepted. Refusal is distinct from an exhausted budget.
    pub status: u32,
    pub opcode: u32,
    pub action: u32,
    pub reserved: u32,
}

const fn refused() -> RawResult {
    RawResult { abi_version: ABI_VERSION, status: 0, opcode: 0, action: 0, reserved: 0 }
}

const fn accepted(opcode: u32, action: u32) -> RawResult {
    RawResult { abi_version: ABI_VERSION, status: 1, opcode, action, reserved: 0 }
}

pub fn decide(facts: RawFacts) -> RawResult {
    if facts.abi_version != ABI_VERSION || facts.reserved != 0 {
        return refused();
    }
    let action = match facts.opcode {
        ACQUISITION_BUDGET => {
            if facts.disposition != 0 || facts.attempt_count < 0
                || facts.maximum_attempt_count < 1 { return refused(); }
            if facts.attempt_count < facts.maximum_attempt_count { ACQUIRE }
            else { BUDGET_EXHAUSTED }
        }
        ACQUISITION_OUTCOME => {
            if facts.attempt_count != 0 || facts.maximum_attempt_count != 0 {
                return refused();
            }
            match facts.disposition {
                1 => AUTHORIZE_ACQUIRED,
                2 => RETRY_ACQUISITION,
                3 => TERMINAL_ACQUISITION,
                _ => return refused(),
            }
        }
        RELEASE_CONTINUATION => {
            if facts.disposition > 3 || facts.attempt_count < 1
                || facts.maximum_attempt_count < 1 { return refused(); }
            if facts.disposition == 2 && facts.attempt_count < facts.maximum_attempt_count {
                RETRY_RELEASE
            } else { FINISH_RELEASE }
        }
        RELEASE_OUTCOME => {
            if facts.attempt_count != 0 || facts.maximum_attempt_count != 0 {
                return refused();
            }
            match facts.disposition {
                0 => USE_NATIVE_FALLBACK,
                1 | 3 => RELEASED,
                2 => DEGRADED,
                _ => return refused(),
            }
        }
        _ => return refused(),
    };
    accepted(facts.opcode, action)
}

/// Fixed whole-result correlation. Even the canonical invalid result is not
/// accepted for malformed facts. Every field must match the genuine decision.
pub fn result_is_valid(facts: RawFacts, result: RawResult) -> u32 {
    let expected = decide(facts);
    u32::from(expected.status == 1 && result == expected)
}
