//! First incremental product-core slice: stable media-handoff menu admission.
//!
//! This pure projection never dispatches a command, owns native resources, or
//! authorizes a target identity. Native transaction fencing remains mandatory.

pub mod host_lifecycle;
pub mod handoff_transactions;
pub mod handoff_offers;
pub mod youtube_handoff_operation;

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_youtube_handoff_operation_initial(
    request: youtube_handoff_operation::Request, now: u64,
) -> youtube_handoff_operation::State {
    youtube_handoff_operation::initial(request, now)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_youtube_handoff_operation_step(
    abi_version: u32, state: youtube_handoff_operation::State,
    event: youtube_handoff_operation::Event,
) -> youtube_handoff_operation::Result {
    youtube_handoff_operation::step(abi_version, state, event)
}

// Foreign symbol declarations stay outside the forbid(unsafe_code) pure reducer.
// These wrappers only copy scalar values; there are no pointers or unsafe blocks.
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_handoff_offers_initial() -> handoff_offers::State {
    handoff_offers::initial()
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_handoff_offers_step(
    abi_version: u32, state: handoff_offers::State, event: handoff_offers::Event,
) -> handoff_offers::Result {
    handoff_offers::step(abi_version, state, event)
}

/// Current scalar-only C ABI. Future snapshots must not reinterpret version 1.
pub const ABI_VERSION: u32 = 1;
pub const HAS_STARTED: u32 = 1 << 0;
pub const FINISHED: u32 = 1 << 1;
pub const CHANGING_PHONE: u32 = 1 << 2;
pub const REQUEST_IN_FLIGHT: u32 = 1 << 3;
pub const PHASE_READY: u32 = 1 << 4;
pub const TARGET_PRESENT: u32 = 1 << 5;
pub const COMMAND_INSTALLED: u32 = 1 << 6;
pub const KNOWN_FLAGS: u32 = (1 << 7) - 1;

/// Stable disabled-reason wire values, not native command authority.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum DisabledReason {
    Ready = 0,
    Stopped = 1,
    NotStarted = 2,
    ChangingPhone = 3,
    RequestInFlight = 4,
    WaitingSession = 5,
    TargetAbsent = 6,
    CommandUnavailable = 7,
    UnknownAbi = 8,
    UnknownFlags = 9,
}

/// No pointers, allocation, shared mutable state, or foreign ownership.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(C)]
pub struct HandoffMenuPolicy {
    pub abi_version: u32,
    pub visible: u32,
    pub enabled: u32,
    pub reason: u32,
}

#[derive(Clone, Copy)]
struct Snapshot {
    has_started: bool,
    finished: bool,
    changing_phone: bool,
    request_in_flight: bool,
    phase_ready: bool,
    target_present: bool,
    command_installed: bool,
}

impl Snapshot {
    const fn from_known_flags(flags: u32) -> Self {
        Self {
            has_started: flags & HAS_STARTED != 0,
            finished: flags & FINISHED != 0,
            changing_phone: flags & CHANGING_PHONE != 0,
            request_in_flight: flags & REQUEST_IN_FLIGHT != 0,
            phase_ready: flags & PHASE_READY != 0,
            target_present: flags & TARGET_PRESENT != 0,
            command_installed: flags & COMMAND_INSTALLED != 0,
        }
    }

    const fn disabled_reason(self) -> DisabledReason {
        if self.finished {
            DisabledReason::Stopped
        } else if !self.has_started {
            DisabledReason::NotStarted
        } else if self.changing_phone {
            DisabledReason::ChangingPhone
        } else if self.request_in_flight {
            DisabledReason::RequestInFlight
        } else if !self.phase_ready {
            DisabledReason::WaitingSession
        } else if !self.target_present {
            DisabledReason::TargetAbsent
        } else if !self.command_installed {
            DisabledReason::CommandUnavailable
        } else {
            DisabledReason::Ready
        }
    }
}

/// Projects stable visibility independently from transient connection readiness.
/// Unknown input fails closed without hiding a previously started menu action.
#[must_use]
pub const fn handoff_menu_policy(abi_version: u32, flags: u32) -> HandoffMenuPolicy {
    let snapshot = Snapshot::from_known_flags(flags);
    let reason = if abi_version != ABI_VERSION {
        DisabledReason::UnknownAbi
    } else if flags & !KNOWN_FLAGS != 0 {
        DisabledReason::UnknownFlags
    } else {
        snapshot.disabled_reason()
    };
    HandoffMenuPolicy {
        abi_version: ABI_VERSION,
        visible: snapshot.has_started as u32,
        enabled: (matches!(reason, DisabledReason::Ready)) as u32,
        reason: reason as u32,
    }
}

/// Queries the exact ABI supported by this linked core.
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Scalar-only exported admission projection. All `u32` inputs are valid values.
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_handoff_menu_policy(
    abi_version: u32,
    flags: u32,
) -> HandoffMenuPolicy {
    handoff_menu_policy(abi_version, flags)
}
