//! Copied numeric policy for MacChromeHandoffPauseCondition.
//! Native parsing, exact identity, one-use authority and browser effects stay outside this core.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;
pub const PREPARE_FLAGS: u64 = 127;
pub const MATCH_FLAGS: u64 = 127;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawPrepareFacts {
    pub abi_version: u32,
    pub reserved: u32,
    /// continuityValid, videoValid, canSeek, playing, canPause, durationPresent, positionPresent.
    pub flags: u64,
    pub position: u64,
    pub duration: u64,
    pub rate: u64,
    pub observed_at_page_ms: u64,
    pub phone_position: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawMatchFacts {
    pub abi_version: u32,
    pub reserved: u32,
    /// continuityEqual, videoEqual, playing, canPause, canSeek, durationPresent, positionPresent.
    pub flags: u64,
    pub anchor_position: u64,
    pub anchor_duration: u64,
    pub anchor_rate: u64,
    pub anchor_observed_at_page_ms: u64,
    pub phone_position: u64,
    pub current_position: u64,
    pub current_duration: u64,
    pub current_rate: u64,
    pub current_observed_at_page_ms: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawDecision {
    pub abi_version: u32,
    /// 0 = malformed copied input; 1 = valid projection, including an ordinary refusal.
    pub status: u32,
    pub allowed: u32,
    pub reserved: u32,
}

const _: [(); 56] = [(); size_of::<RawPrepareFacts>()];
const _: [(); 88] = [(); size_of::<RawMatchFacts>()];
const _: [(); 16] = [(); size_of::<RawDecision>()];
const _: [(); 8] = [(); align_of::<RawPrepareFacts>()];
const _: [(); 8] = [(); align_of::<RawMatchFacts>()];
const _: [(); 4] = [(); align_of::<RawDecision>()];

const fn invalid() -> RawDecision {
    RawDecision { abi_version: ABI_VERSION, status: 0, allowed: 0, reserved: 0 }
}

fn decision(allowed: bool) -> RawDecision {
    RawDecision { abi_version: ABI_VERSION, status: 1, allowed: u32::from(allowed), reserved: 0 }
}

fn number(bits: u64) -> f64 { f64::from_bits(bits) }

/// The native adapter supplies the original UUID/video parser facts and option presence.
/// Floating payloads are copied bits; this projection never normalizes or returns new values.
pub fn prepare(raw: RawPrepareFacts) -> RawDecision {
    if raw.abi_version != ABI_VERSION || raw.reserved != 0 || raw.flags & !PREPARE_FLAGS != 0 {
        return invalid();
    }
    let position = number(raw.position);
    let duration = number(raw.duration);
    let rate = number(raw.rate);
    let observed_at_page_ms = number(raw.observed_at_page_ms);
    let phone_position = number(raw.phone_position);
    decision(raw.flags == PREPARE_FLAGS
        && rate.is_finite() && rate > 0.0 && rate <= 16.0
        && duration.is_finite() && duration > 0.0 && duration <= 31_536_000.0
        && position.is_finite() && position >= 0.0 && position < duration
        && phone_position.is_finite() && phone_position >= 0.0 && phone_position < duration
        && observed_at_page_ms.is_finite() && observed_at_page_ms >= 0.0
        && observed_at_page_ms <= 9_007_199_254_740_991.0)
}

/// This is the original match predicate, not shared-offer uptime freshness or drift policy.
/// Native source preparation owns the anchor; current native snapshot validation stays native.
pub fn matches(raw: RawMatchFacts) -> RawDecision {
    if raw.abi_version != ABI_VERSION || raw.reserved != 0 || raw.flags & !MATCH_FLAGS != 0 {
        return invalid();
    }
    let elapsed = (number(raw.current_observed_at_page_ms)
        - number(raw.anchor_observed_at_page_ms)) / 1000.0;
    let position = number(raw.current_position);
    decision(raw.flags == MATCH_FLAGS
        && elapsed.is_finite() && elapsed >= 0.0 && elapsed < 30.0
        && number(raw.current_duration) == number(raw.anchor_duration)
        && number(raw.current_rate) == number(raw.anchor_rate)
        && position.is_finite()
        && (position - (number(raw.anchor_position) + elapsed * number(raw.anchor_rate))).abs() <= 1.0
        && (position - number(raw.phone_position)).abs() <= 2.0)
}

pub fn prepare_result_is_valid(raw: RawPrepareFacts, output: RawDecision) -> u32 {
    let expected = prepare(raw);
    u32::from(expected.status == 1 && expected == output)
}

pub fn matches_result_is_valid(raw: RawMatchFacts, output: RawDecision) -> u32 {
    let expected = matches(raw);
    u32::from(expected.status == 1 && expected == output)
}

