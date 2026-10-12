//! PRIVATE adaptation candidate with separate ABI assays; no product actor adoption.
#![forbid(unsafe_code)]

mod dependencies;
mod time_assignments;
mod diagnostics;
mod policy;
mod service;
mod bookkeeping;
pub mod state_codec;

pub use dependencies::{ClockFacts, ClockSite, Dependencies, Observation, RelativeTime, Scalar};
pub use dependencies::TryClockFacts;
pub use time_assignments::{TimeSlot, TimeSource, TimeEdit, ExplicitTime, Origin, SLOTS};
pub use dependencies::{PacketQueue, RoundTripTime, Profile, TierDemand};
pub use diagnostics::*;
pub use policy::*;
pub use service::*;
pub use bookkeeping::*;

#[cfg(test)]
mod bookkeeping_tests;

#[cfg(test)]
mod native_option_traces;

#[cfg(test)]
mod time_assignment_tests;

#[cfg(test)]
mod report_clock_tests;

#[cfg(test)]
mod preparation_clock_tests;

#[cfg(test)]
mod continuation_clock_tests;

#[cfg(test)]
mod collector_clock_tests;
