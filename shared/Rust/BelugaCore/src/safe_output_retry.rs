//! Copy-only retry scheduling. No route, authorization, timer, or global ownership.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;
pub const STATUS_INVALID: u32 = 0;
pub const STATUS_ACCEPTED: u32 = 1;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Event {
    Tick,
    Failure,
    Reset,
}

impl Event {
    fn decode(raw: u32) -> Option<Self> {
        match raw {
            1 => Some(Self::Tick),
            2 => Some(Self::Failure),
            3 => Some(Self::Reset),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Config {
    maximum_failed_attempt_count: i64,
    maximum_backoff_tick_count: i64,
    capped_cooldown_tick_count: i64,
}

impl Config {
    /// Swift Int is signed 64-bit on the supported Apple targets. All values,
    /// including negative values and Int.min, are accepted and clamped to 1.
    pub fn new(maximum_failed: i64, maximum_backoff: i64, cooldown: i64) -> Self {
        Self {
            maximum_failed_attempt_count: maximum_failed.max(1),
            maximum_backoff_tick_count: maximum_backoff.max(1),
            capped_cooldown_tick_count: cooldown.max(1),
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        Self::new(6, 16, 60)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Policy {
    config: Config,
    failed_attempt_count: i64,
    backoff_tick_count: i64,
    cooldown_tick_count: i64,
}

impl Policy {
    pub fn new(config: Config) -> Self {
        Self { config, failed_attempt_count: 0, backoff_tick_count: 0, cooldown_tick_count: 0 }
    }

    pub fn transition(mut self, event: Event) -> (Self, Option<bool>) {
        match event {
            Event::Tick => {
                if self.failed_attempt_count >= self.config.maximum_failed_attempt_count {
                    if self.cooldown_tick_count != 0 {
                        self.cooldown_tick_count -= 1;
                        return (self, Some(false));
                    }
                    self.failed_attempt_count = 0;
                    self.backoff_tick_count = 0;
                }
                if self.backoff_tick_count != 0 {
                    self.backoff_tick_count -= 1;
                    return (self, Some(false));
                }
                (self, Some(true))
            }
            Event::Failure => {
                if self.failed_attempt_count >= self.config.maximum_failed_attempt_count {
                    return (self, None);
                }
                self.failed_attempt_count += 1;
                if self.failed_attempt_count >= self.config.maximum_failed_attempt_count {
                    self.backoff_tick_count = 0;
                    self.cooldown_tick_count = self.config.capped_cooldown_tick_count;
                    return (self, None);
                }
                let shift = (self.failed_attempt_count - 1).min(30) as u32;
                self.backoff_tick_count = (1_i64 << shift).min(self.config.maximum_backoff_tick_count);
                (self, None)
            }
            Event::Reset => {
                self.failed_attempt_count = 0;
                self.backoff_tick_count = 0;
                self.cooldown_tick_count = 0;
                (self, None)
            }
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawConfig {
    pub abi_version: u32,
    pub reserved: u32,
    pub maximum_failed_attempt_count: i64,
    pub maximum_backoff_tick_count: i64,
    pub capped_cooldown_tick_count: i64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawState {
    pub abi_version: u32,
    pub reserved: u32,
    pub maximum_failed_attempt_count: i64,
    pub maximum_backoff_tick_count: i64,
    pub capped_cooldown_tick_count: i64,
    pub failed_attempt_count: i64,
    pub backoff_tick_count: i64,
    pub cooldown_tick_count: i64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub state: RawState,
    pub status: u32,
    /// 0 = no tick decision; 1 = wait; 2 = attempt. Status must be checked first.
    pub tick_decision: u32,
}

const _: [(); 32] = [(); size_of::<RawConfig>()];
const _: [(); 56] = [(); size_of::<RawState>()];
const _: [(); 64] = [(); size_of::<RawResult>()];
const _: [(); 8] = [(); align_of::<RawState>()];

impl Policy {
    pub fn copied_state(self) -> RawState {
        RawState {
            abi_version: ABI_VERSION,
            reserved: 0,
            maximum_failed_attempt_count: self.config.maximum_failed_attempt_count,
            maximum_backoff_tick_count: self.config.maximum_backoff_tick_count,
            capped_cooldown_tick_count: self.config.capped_cooldown_tick_count,
            failed_attempt_count: self.failed_attempt_count,
            backoff_tick_count: self.backoff_tick_count,
            cooldown_tick_count: self.cooldown_tick_count,
        }
    }

    fn from_copied_state(raw: RawState) -> Option<Self> {
        if raw.abi_version != ABI_VERSION || raw.reserved != 0
            || raw.maximum_failed_attempt_count < 1 || raw.maximum_backoff_tick_count < 1
            || raw.capped_cooldown_tick_count < 1 || raw.failed_attempt_count < 0
            || raw.failed_attempt_count > raw.maximum_failed_attempt_count
            || raw.backoff_tick_count < 0 || raw.cooldown_tick_count < 0
            || raw.cooldown_tick_count > raw.capped_cooldown_tick_count
        {
            return None;
        }
        // These are the exact reachable scalar shapes from the native initializer
        // and its Tick/Failure/Reset events, not a smaller fixed-configuration cap.
        if raw.failed_attempt_count == raw.maximum_failed_attempt_count {
            if raw.backoff_tick_count != 0 { return None; }
        } else {
            if raw.cooldown_tick_count != 0 { return None; }
            let largest_backoff = if raw.failed_attempt_count == 0 {
                0
            } else {
                let shift = (raw.failed_attempt_count - 1).min(30) as u32;
                (1_i64 << shift).min(raw.maximum_backoff_tick_count)
            };
            if raw.backoff_tick_count > largest_backoff { return None; }
        }
        Some(Self {
            config: Config {
                maximum_failed_attempt_count: raw.maximum_failed_attempt_count,
                maximum_backoff_tick_count: raw.maximum_backoff_tick_count,
                capped_cooldown_tick_count: raw.capped_cooldown_tick_count,
            },
            failed_attempt_count: raw.failed_attempt_count,
            backoff_tick_count: raw.backoff_tick_count,
            cooldown_tick_count: raw.cooldown_tick_count,
        })
    }
}

/// No pointers, allocations, side effects, process-global state, or hidden retry timer.
pub fn initialize(raw: RawConfig) -> RawResult {
    if raw.abi_version != ABI_VERSION || raw.reserved != 0 {
        // An invalid envelope is not normalized into a fresh accepted policy.
        return RawResult {
            state: RawState {
                abi_version: raw.abi_version, reserved: raw.reserved,
                maximum_failed_attempt_count: raw.maximum_failed_attempt_count,
                maximum_backoff_tick_count: raw.maximum_backoff_tick_count,
                capped_cooldown_tick_count: raw.capped_cooldown_tick_count,
                failed_attempt_count: 0, backoff_tick_count: 0, cooldown_tick_count: 0,
            },
            status: STATUS_INVALID, tick_decision: 0,
        };
    }
    RawResult {
        state: Policy::new(Config::new(raw.maximum_failed_attempt_count,
            raw.maximum_backoff_tick_count, raw.capped_cooldown_tick_count)).copied_state(),
        status: STATUS_ACCEPTED,
        tick_decision: 0,
    }
}

/// Invalid input or an unknown event returns the *exact unchanged raw state*.
pub fn transition(raw: RawState, raw_event: u32) -> RawResult {
    let invalid = RawResult { state: raw, status: STATUS_INVALID, tick_decision: 0 };
    let Some(policy) = Policy::from_copied_state(raw) else { return invalid; };
    let Some(event) = Event::decode(raw_event) else { return invalid; };
    let (state, decision) = policy.transition(event);
    RawResult {
        state: state.copied_state(), status: STATUS_ACCEPTED,
        tick_decision: match decision { None => 0, Some(false) => 1, Some(true) => 2 },
    }
}
