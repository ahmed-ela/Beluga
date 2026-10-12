//! Copied-value availability retry proposals; native retains sockets and effects.
#![forbid(unsafe_code)]

pub const ABI_VERSION: u32 = 1;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawState {
    pub abi_version: u32,
    pub next_delay_seconds: u32,
    pub has_validated_connection: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawEvent {
    pub opcode: u32,
    pub reserved: u32,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Decision {
    ValidStateObserved = 0,
    FailureDelay = 1,
    InvalidInput = 2,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawResult {
    pub candidate_state: RawState,
    pub decision: u32,
    pub became_validated: u32,
    pub retry_delay_seconds: u32,
    pub reserved: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Delay { One, Two, Four, Eight, Sixteen, Thirty }

impl Delay {
    fn decode(raw: u32) -> Option<Self> {
        match raw {
            1 => Some(Self::One), 2 => Some(Self::Two),
            4 => Some(Self::Four), 8 => Some(Self::Eight),
            16 => Some(Self::Sixteen), 30 => Some(Self::Thirty),
            _ => None,
        }
    }

    fn seconds(self) -> u32 {
        match self {
            Self::One => 1, Self::Two => 2, Self::Four => 4,
            Self::Eight => 8, Self::Sixteen => 16, Self::Thirty => 30,
        }
    }

    fn successor(self) -> Self {
        match self {
            Self::One => Self::Two,
            Self::Two => Self::Four,
            Self::Four => Self::Eight,
            Self::Eight => Self::Sixteen,
            Self::Sixteen => Self::Thirty,
            Self::Thirty => Self::Thirty,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum State { AwaitingValidation(Delay), Validated }

impl State {
    fn decode(raw: RawState) -> Option<Self> {
        if raw.abi_version != ABI_VERSION { return None; }
        if raw.reserved != 0 { return None; }
        let delay = Delay::decode(raw.next_delay_seconds)?;
        match raw.has_validated_connection {
            0 => Some(Self::AwaitingValidation(delay)),
            1 if delay == Delay::One => Some(Self::Validated),
            _ => None,
        }
    }

    fn delay(self) -> Delay {
        match self { Self::AwaitingValidation(delay) => delay, Self::Validated => Delay::One }
    }

    fn raw(self) -> RawState {
        RawState {
            abi_version: ABI_VERSION,
            next_delay_seconds: self.delay().seconds(),
            has_validated_connection: u32::from(matches!(self, Self::Validated)),
            reserved: 0,
        }
    }

    fn evaluate(self, operation: Operation) -> Evaluation {
        match operation {
            Operation::ValidAvailabilityState => Evaluation {
                candidate: State::Validated,
                action: Action::Validated { became: !matches!(self, Self::Validated) },
            },
            Operation::Failure => {
                let old_delay = self.delay();
                Evaluation {
                    candidate: State::AwaitingValidation(old_delay.successor()),
                    action: Action::RetryAfter(old_delay),
                }
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Operation { ValidAvailabilityState, Failure }

impl Operation {
    fn decode(raw: RawEvent) -> Option<Self> {
        if raw.reserved != 0 { return None; }
        match raw.opcode {
            0 => Some(Self::ValidAvailabilityState),
            1 => Some(Self::Failure),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Action { Validated { became: bool }, RetryAfter(Delay) }

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Evaluation { candidate: State, action: Action }

impl Evaluation {
    fn raw(self) -> RawResult {
        let (decision, became_validated, retry_delay_seconds) = match self.action {
            Action::Validated { became } => (Decision::ValidStateObserved, u32::from(became), 0),
            Action::RetryAfter(delay) => (Decision::FailureDelay, 0, delay.seconds()),
        };
        RawResult {
            candidate_state: self.candidate.raw(),
            decision: decision as u32,
            became_validated,
            retry_delay_seconds,
            reserved: 0,
        }
    }
}

#[must_use]
pub fn step(abi_version: u32, before: RawState, event: RawEvent) -> RawResult {
    let invalid = || RawResult {
        candidate_state: before,
        decision: Decision::InvalidInput as u32,
        became_validated: 0,
        retry_delay_seconds: 0,
        reserved: 0,
    };
    if abi_version != ABI_VERSION { return invalid(); }
    let Some(state) = State::decode(before) else { return invalid(); };
    let Some(operation) = Operation::decode(event) else { return invalid(); };
    state.evaluate(operation).raw()
}
