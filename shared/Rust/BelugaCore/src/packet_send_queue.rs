//! Copied cumulative packet-delay evidence. Native code owns clocks and stamps.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;
pub const STATUS_INVALID: u32 = 0;
pub const STATUS_ACCEPTED: u32 = 1;
pub const OBSERVATION_UNAVAILABLE: u32 = 0;
pub const OBSERVATION_NO_PACKETS: u32 = 1;
pub const OBSERVATION_MEASURED: u32 = 2;
pub const ACTION_RETAIN: u32 = 0;
pub const ACTION_CLEAR: u32 = 1;
pub const ACTION_STAMP_NOW: u32 = 2;
pub const OP_ORDINARY: u32 = 0;
pub const OP_CAPACITY: u32 = 1;
pub const OP_TIER_RESET: u32 = 2;
pub const OP_PATH_RESET: u32 = 3;
pub const OP_LOW_LEASE_QUERY: u32 = 4;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawState {
    pub abi_version: u32,
    pub reserved: u32,
    pub packets_present: u32,
    pub delay_present: u32,
    pub low_present: u32,
    pub soft_present: u32,
    pub packets: u64,
    pub delay_bits: u64,
    pub pressure_count: u64,
}

impl RawState {
    pub const fn empty() -> Self {
        Self { abi_version: ABI_VERSION, reserved: 0, packets_present: 0,
            delay_present: 0, low_present: 0, soft_present: 0, packets: 0,
            delay_bits: 0, pressure_count: 0 }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawEvent {
    pub opcode: u32,
    pub packets_present: u32,
    pub delay_present: u32,
    pub rtt_inflated: u32,
    pub packets: u64,
    pub delay_bits: u64,
    pub low_age_seconds: i64,
    pub low_age_attoseconds: i64,
    pub soft_age_seconds: i64,
    pub soft_age_attoseconds: i64,
}

impl RawEvent {
    pub const fn empty(opcode: u32) -> Self {
        Self { opcode, packets_present: 0, delay_present: 0, rtt_inflated: 0,
            packets: 0, delay_bits: 0, low_age_seconds: 0,
            low_age_attoseconds: 0, soft_age_seconds: 0, soft_age_attoseconds: 0 }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub abi_version: u32,
    pub status: u32,
    pub observation: u32,
    pub low_action: u32,
    pub soft_action: u32,
    pub sample_inflated: u32,
    pub immediate: u32,
    pub inflated: u32,
    pub upgrade: u32,
    pub capacity_growth: u32,
    pub measured_delay_bits: u64,
    pub state: RawState,
}

impl RawResult {
    pub const fn invalid() -> Self {
        Self { abi_version: ABI_VERSION, status: STATUS_INVALID,
            observation: OBSERVATION_UNAVAILABLE, low_action: ACTION_RETAIN,
            soft_action: ACTION_RETAIN, sample_inflated: 0, immediate: 0,
            inflated: 0, upgrade: 0, capacity_growth: 0, measured_delay_bits: 0,
            state: RawState::empty() }
    }
}

const _: [(); 48] = [(); size_of::<RawState>()];
const _: [(); 64] = [(); size_of::<RawEvent>()];
const _: [(); 96] = [(); size_of::<RawResult>()];
const _: [(); 8] = [(); align_of::<RawState>()];
const _: [(); 8] = [(); align_of::<RawEvent>()];
const _: [(); 8] = [(); align_of::<RawResult>()];

const ATTOSECONDS_PER_SECOND: i128 = 1_000_000_000_000_000_000;
const LEASE_ATTOSECONDS: i128 = 1_500_000_000_000_000_000;

fn boolean(value: u32) -> bool { value <= 1 }

fn age_valid(present: u32, seconds: i64, attoseconds: i64) -> bool {
    attoseconds > -1_000_000_000_000_000_000
        && attoseconds < 1_000_000_000_000_000_000
        && (present != 0 || (seconds == 0 && attoseconds == 0))
}

fn fresh(present: u32, seconds: i64, attoseconds: i64) -> bool {
    let age = i128::from(seconds) * ATTOSECONDS_PER_SECOND + i128::from(attoseconds);
    present != 0 && (0..=LEASE_ATTOSECONDS).contains(&age)
}

fn state_valid(state: RawState) -> bool {
    state.abi_version == ABI_VERSION && state.reserved == 0
        && boolean(state.packets_present) && boolean(state.delay_present)
        && boolean(state.low_present) && boolean(state.soft_present)
        && state.pressure_count <= i64::MAX as u64
        && (state.packets_present != 0 || state.packets == 0)
        && (state.delay_present != 0 || state.delay_bits == 0)
}

fn event_valid(state: RawState, event: RawEvent) -> bool {
    if event.opcode > OP_LOW_LEASE_QUERY || !boolean(event.packets_present)
        || !boolean(event.delay_present) || !boolean(event.rtt_inflated)
        || (event.opcode == OP_CAPACITY && event.rtt_inflated != 0)
        || (event.packets_present == 0 && event.packets != 0)
        || (event.delay_present == 0 && event.delay_bits != 0) {
        return false;
    }
    if event.opcode == OP_TIER_RESET || event.opcode == OP_PATH_RESET {
        return event == RawEvent::empty(event.opcode);
    }
    if event.opcode == OP_LOW_LEASE_QUERY {
        return event.packets_present == 0 && event.delay_present == 0
            && event.rtt_inflated == 0
            && event.soft_age_seconds == 0 && event.soft_age_attoseconds == 0
            && age_valid(state.low_present, event.low_age_seconds, event.low_age_attoseconds);
    }
    age_valid(state.low_present, event.low_age_seconds, event.low_age_attoseconds)
        && age_valid(state.soft_present, event.soft_age_seconds, event.soft_age_attoseconds)
}

fn classify(state: RawState, event: RawEvent) -> (RawState, u32, u64) {
    let current_delay = f64::from_bits(event.delay_bits);
    let mut next = state;
    if event.packets_present == 0 || event.delay_present == 0
        || !current_delay.is_finite() || current_delay < 0.0 {
        next.packets_present = 0; next.delay_present = 0;
        next.packets = 0; next.delay_bits = 0;
        return (next, OBSERVATION_UNAVAILABLE, 0);
    }
    next.packets_present = 1; next.delay_present = 1;
    next.packets = event.packets; next.delay_bits = event.delay_bits;
    if state.packets_present == 0 || state.delay_present == 0 {
        return (next, OBSERVATION_UNAVAILABLE, 0);
    }
    let previous_delay = f64::from_bits(state.delay_bits);
    if event.packets < state.packets || !(current_delay >= previous_delay) {
        return (next, OBSERVATION_UNAVAILABLE, 0);
    }
    if event.packets == state.packets {
        return (next, if current_delay == previous_delay {
            OBSERVATION_NO_PACKETS
        } else { OBSERVATION_UNAVAILABLE }, 0);
    }
    let average = (current_delay - previous_delay) / (event.packets - state.packets) as f64;
    (next, OBSERVATION_MEASURED, average.to_bits())
}

/// The returned value plans copied state and native stamp actions, never clock effects.
pub fn transition(state: RawState, event: RawEvent) -> RawResult {
    if !state_valid(state) || !event_valid(state, event) {
        return RawResult::invalid();
    }
    let mut result = RawResult { status: STATUS_ACCEPTED, state, ..RawResult::invalid() };
    if event.opcode == OP_LOW_LEASE_QUERY {
        result.upgrade = u32::from(fresh(state.low_present, event.low_age_seconds, event.low_age_attoseconds));
        return result;
    }
    if event.opcode == OP_TIER_RESET || event.opcode == OP_PATH_RESET {
        result.state.low_present = 0; result.state.soft_present = 0;
        result.state.pressure_count = 0;
        result.low_action = ACTION_CLEAR; result.soft_action = ACTION_CLEAR;
        if event.opcode == OP_PATH_RESET { result.state = RawState::empty(); }
        return result;
    }
    let (next, observation, bits) = classify(state, event);
    result.state = next; result.observation = observation; result.measured_delay_bits = bits;
    let measured = observation == OBSERVATION_MEASURED;
    let delay = f64::from_bits(bits);
    result.sample_inflated = u32::from(measured && delay > 0.100);
    result.immediate = u32::from(measured && delay >= 0.200);
    let low_fresh = fresh(state.low_present, event.low_age_seconds, event.low_age_attoseconds);
    let soft_fresh = fresh(state.soft_present, event.soft_age_seconds, event.soft_age_attoseconds);
    if event.opcode == OP_CAPACITY {
        result.inflated = u32::from(result.sample_inflated != 0
            && (result.immediate != 0 || state.pressure_count >= 2));
        result.upgrade = u32::from((measured && delay <= 0.020)
            || (observation == OBSERVATION_NO_PACKETS && low_fresh));
        result.capacity_growth = u32::from(result.upgrade != 0 && low_fresh);
        return result;
    }
    if measured && result.sample_inflated != 0 && event.rtt_inflated == 0 {
        if state.soft_present != 0 && !soft_fresh { result.state.pressure_count = 0; }
        result.state.pressure_count = (result.state.pressure_count + 1).min(i64::MAX as u64);
        result.state.soft_present = 1; result.soft_action = ACTION_STAMP_NOW;
    } else if observation == OBSERVATION_NO_PACKETS && event.rtt_inflated == 0 {
        if state.soft_present != 0 && !soft_fresh {
            result.state.pressure_count = 0; result.state.soft_present = 0;
            result.soft_action = ACTION_CLEAR;
        }
    } else {
        result.state.pressure_count = 0; result.state.soft_present = 0;
        result.soft_action = ACTION_CLEAR;
    }
    result.inflated = u32::from(result.sample_inflated != 0
        && (result.immediate != 0 || result.state.pressure_count >= 2));
    match observation {
        OBSERVATION_MEASURED => {
            if delay <= 0.020 {
                result.state.low_present = 1; result.low_action = ACTION_STAMP_NOW;
            } else {
                result.state.low_present = 0; result.low_action = ACTION_CLEAR;
            }
        }
        OBSERVATION_NO_PACKETS => {
            if state.low_present != 0 && !low_fresh {
                result.state.low_present = 0; result.low_action = ACTION_CLEAR;
            }
        }
        _ => { result.state.low_present = 0; result.low_action = ACTION_CLEAR; }
    }
    result.upgrade = u32::from((measured && delay <= 0.020)
        || (!measured && result.state.low_present != 0 && low_fresh));
    result
}
