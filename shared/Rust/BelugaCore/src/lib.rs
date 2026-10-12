//! First incremental product-core slice: stable media-handoff menu admission.
//!
//! This pure projection never dispatches a command, owns native resources, or
//! authorizes a target identity. Native transaction fencing remains mandatory.

pub mod screen_liveness;
pub mod ice_recovery;
pub mod output_dimensions;
pub mod packet_send_queue;
pub mod rtt_evidence;
pub mod tier_demand;
pub mod media_command_gate;
pub mod screen_suspension;
pub mod phone_catalog;
pub mod update_admission;

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_update_admission_decide(
    request: update_admission::RawRequest,
) -> update_admission::RawResult {
    update_admission::decide(request)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_update_admission_result_is_valid(
    request: update_admission::RawRequest,
    result: update_admission::RawResult,
) -> u32 {
    update_admission::result_is_valid(request, result)
}
// Add beside the existing public policy modules and C exports; preserve all others.
pub mod runtime_catalog;

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_runtime_catalog_step(
    state: runtime_catalog::RawRuntimeCatalogState,
    event: runtime_catalog::RawRuntimeCatalogEvent,
) -> runtime_catalog::RawRuntimeCatalogResult {
    runtime_catalog::step(state, event)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_runtime_catalog_result_is_valid(
    state: runtime_catalog::RawRuntimeCatalogState,
    event: runtime_catalog::RawRuntimeCatalogEvent,
    result: runtime_catalog::RawRuntimeCatalogResult,
) -> u32 {
    runtime_catalog::result_is_valid(state, event, result)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_phone_catalog_decide(
    input: phone_catalog::RawPhoneCatalogInput,
) -> phone_catalog::RawPhoneCatalogResult {
    phone_catalog::decide(input)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_phone_catalog_result_is_valid(
    input: phone_catalog::RawPhoneCatalogInput,
    result: phone_catalog::RawPhoneCatalogResult,
) -> u32 {
    phone_catalog::result_is_valid(input, result)
}


#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_screen_suspension_step(
    state: screen_suspension::RawScreenSuspensionState,
    event: screen_suspension::RawScreenSuspensionEvent,
) -> screen_suspension::RawScreenSuspensionResult {
    screen_suspension::transition(state, event)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_screen_suspension_result_is_valid(
    state: screen_suspension::RawScreenSuspensionState,
    event: screen_suspension::RawScreenSuspensionEvent,
    result: screen_suspension::RawScreenSuspensionResult,
) -> u32 {
    screen_suspension::result_is_valid(state, event, result)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_media_command_gate_step(
    state: media_command_gate::RawState, event: media_command_gate::RawEvent,
) -> media_command_gate::RawResult {
    media_command_gate::transition(state, event)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_media_command_gate_result_is_valid(
    state: media_command_gate::RawState, event: media_command_gate::RawEvent,
    result: media_command_gate::RawResult,
) -> u32 {
    media_command_gate::result_is_valid(state, event, result)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_tier_demand_project(
    facts: tier_demand::RawTierDemandFacts,
) -> tier_demand::RawTierDemandProjection {
    tier_demand::project(facts)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_tier_demand_projection_is_valid(
    facts: tier_demand::RawTierDemandFacts, projection: tier_demand::RawTierDemandProjection,
) -> u32 {
    tier_demand::projection_is_valid(facts, projection)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_rtt_evidence_step(
    state: rtt_evidence::RawState, event: rtt_evidence::RawEvent,
) -> rtt_evidence::RawResult {
    rtt_evidence::transition(state, event)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_rtt_evidence_result_is_valid(
    state: rtt_evidence::RawState, event: rtt_evidence::RawEvent, result: rtt_evidence::RawResult,
) -> u32 {
    let expected = rtt_evidence::transition(state, event);
    u32::from(expected.status == 1 && expected == result)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_packet_send_queue_step(
    state: packet_send_queue::RawState, event: packet_send_queue::RawEvent,
) -> packet_send_queue::RawResult {
    packet_send_queue::transition(state, event)
}
pub mod display_admission;
pub mod host_lifecycle;
pub mod handoff_transactions;
pub mod handoff_offers;
pub mod handoff_source_position;
// Copied C exports: no native identity, resources or effects cross this boundary.
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_handoff_source_prepare(raw: handoff_source_position::RawPrepareFacts) -> handoff_source_position::RawDecision {
    handoff_source_position::prepare(raw)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_handoff_source_matches(raw: handoff_source_position::RawMatchFacts) -> handoff_source_position::RawDecision {
    handoff_source_position::matches(raw)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_handoff_source_prepare_result_is_valid(
    raw: handoff_source_position::RawPrepareFacts, output: handoff_source_position::RawDecision,
) -> u32 {
    handoff_source_position::prepare_result_is_valid(raw, output)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_handoff_source_matches_result_is_valid(
    raw: handoff_source_position::RawMatchFacts, output: handoff_source_position::RawDecision,
) -> u32 {
    handoff_source_position::matches_result_is_valid(raw, output)
}
pub mod youtube_handoff_operation;
pub mod invitation_acceptance;
pub mod replay_policy;
pub mod pairing_catalog_checkpoint;
pub mod supported_player_arbitration;
pub mod availability_retry;
pub mod safe_output_retry;
pub mod system_audio_start;
pub mod hosted_call_policy;

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_safe_output_retry_initialize(input: safe_output_retry::RawConfig) -> safe_output_retry::RawResult {
    safe_output_retry::initialize(input)
}
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_safe_output_retry_transition(input: safe_output_retry::RawState, event: u32) -> safe_output_retry::RawResult {
    safe_output_retry::transition(input, event)
}
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_system_audio_start(input: system_audio_start::RawFacts) -> system_audio_start::RawDecision {
    system_audio_start::decide(input)
}
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_hosted_call_observation(input: hosted_call_policy::RawObservationFacts) -> hosted_call_policy::RawDecision {
    hosted_call_policy::decide_observation(input)
}
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_hosted_call_evidence(input: hosted_call_policy::RawEvidenceFacts) -> hosted_call_policy::RawDecision {
    hosted_call_policy::decide_evidence(input)
}
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_hosted_call_peer_generation(input: hosted_call_policy::RawPeerFacts) -> hosted_call_policy::RawDecision {
    hosted_call_policy::decide_peer_generation(input)
}


#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_availability_retry_step(
    abi_version: u32,
    state: availability_retry::RawState,
    event: availability_retry::RawEvent,
) -> availability_retry::RawResult {
    availability_retry::step(abi_version, state, event)
}

// Eleventh copied scalar contract: source choice only; no native authority or effects.
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_supported_player_arbitrate(
    input: supported_player_arbitration::ArbitrationInput,
) -> supported_player_arbitration::ArbitrationOutput {
    supported_player_arbitration::arbitrate(input)
}

pub mod pairing_commit;

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_pairing_commit_step(
    abi_version: u32, state: pairing_commit::RawState, event: pairing_commit::RawEvent,
) -> pairing_commit::RawResult {
    pairing_commit::step(abi_version, state, event)
}
pub mod reconnect_counters;

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_reconnect_counters_step(
    abi_version: u32, state: reconnect_counters::RawState,
    event: reconnect_counters::RawEvent,
) -> reconnect_counters::RawResult {
    reconnect_counters::step(abi_version, state, event)
}

// Eighth copied scalar contract: one catalog attempt's admission/revocation.
// Native identity, lock, durable snapshot and successful effect custody remain native.
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_pairing_catalog_checkpoint_initial() -> pairing_catalog_checkpoint::RawState {
    pairing_catalog_checkpoint::initial()
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_pairing_catalog_checkpoint_step(
    abi_version: u32, state: pairing_catalog_checkpoint::RawState,
    event: pairing_catalog_checkpoint::RawEvent,
) -> pairing_catalog_checkpoint::RawResult {
    pairing_catalog_checkpoint::step(abi_version, state, event)
}

// Seventh scalar contract: bounded replay-window value policy only.
// Native cipher authentication, admitted peer/exchange ownership and resets
// remain outside this copied-value ABI. No pointer or unsafe block crosses it.
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_signaling_replay_initial() -> replay_policy::RawState {
    replay_policy::initial()
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_signaling_replay_step(
    abi_version: u32, state: replay_policy::RawState, sequence: u64,
) -> replay_policy::RawResult {
    replay_policy::step(abi_version, state, sequence)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_invitation_acceptance_initial() -> invitation_acceptance::RawState {
    invitation_acceptance::initial()
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_invitation_acceptance_step(
    abi_version: u32, state: invitation_acceptance::RawState, event: invitation_acceptance::RawEvent,
) -> invitation_acceptance::RawOutput {
    invitation_acceptance::step(abi_version, state, event)
}


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

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_display_requirement_admission(input: display_admission::RawDisplayFacts) -> display_admission::RawBooleanDecision {
    display_admission::requirement_admission(input)
}
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_source_dimension_kind(input: display_admission::RawKindFacts) -> display_admission::RawKindDecision {
    display_admission::dimension_kind(input)
}
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_source_dimensions(input: display_admission::RawSourceFacts) -> display_admission::RawSourceDecision {
    display_admission::source_dimensions(input)
}
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_source_dimensions_stable(input: display_admission::RawStabilityFacts) -> display_admission::RawBooleanDecision {
    display_admission::dimensions_stable(input)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_output_dimensions(input: output_dimensions::RawOutputFacts) -> output_dimensions::RawOutputDecision {
    output_dimensions::output_dimensions(input)
}

// Append after existing exports; insert `pub mod ice_recovery;` after the intact crate-doc header.
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_ice_recovery_initialize(abi: u32, config: ice_recovery::Config)
    -> ice_recovery::InitResult { ice_recovery::initialize(abi, config) }
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_ice_recovery_step(abi: u32, before: ice_recovery::State,
    event: ice_recovery::Event) -> ice_recovery::Result { ice_recovery::step(abi, before, event) }
#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_screen_liveness_observe(
    abi_version: u64, state: screen_liveness::RawState, sample: screen_liveness::RawSample,
) -> screen_liveness::RawResult {
    screen_liveness::observe(abi_version, state, sample)
}

// Proposed additive enrollment, not applied to the canonical crate.
pub mod update_operation;
pub mod update_sparkle_admission;
pub mod update_unarmed_completion;
pub mod update_abort;

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_update_abort_decide(
    request: update_abort::RawRequest,
) -> update_abort::RawResult {
    update_abort::decide(request)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_update_abort_result_is_valid(
    request: update_abort::RawRequest,
    result: update_abort::RawResult,
) -> u32 {
    update_abort::result_is_valid(request, result)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_update_unarmed_completion_decide(
    request: update_unarmed_completion::RawRequest,
) -> update_unarmed_completion::RawResult {
    update_unarmed_completion::decide(request)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_update_unarmed_completion_result_is_valid(
    request: update_unarmed_completion::RawRequest,
    result: update_unarmed_completion::RawResult,
) -> u32 {
    update_unarmed_completion::result_is_valid(request, result)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_update_sparkle_admission_decide(
    request: update_sparkle_admission::RawRequest,
) -> update_sparkle_admission::RawResult {
    update_sparkle_admission::decide(request)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_update_sparkle_admission_result_is_valid(
    request: update_sparkle_admission::RawRequest,
    result: update_sparkle_admission::RawResult,
) -> u32 {
    update_sparkle_admission::result_is_valid(request, result)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_update_operation_step(
    abi_version: u32,
    before: update_operation::RawState,
    event: update_operation::RawEvent,
) -> update_operation::RawResult {
    update_operation::step(abi_version, before, event)
}

pub mod network_adaptation_candidate;
pub mod native_clock_assay;
pub mod native_owner_codec;
pub mod native_owner_events;
pub mod network_adaptation_owner_events;
#[cfg(test)]
mod network_adaptation_owner_events_tests;
pub mod native_owner_clock_events;
pub mod network_adaptation_owner_clocked_events;
#[cfg(test)]
mod network_adaptation_owner_clocked_events_tests;
pub mod network_adaptation_owner_prepare_events;
#[cfg(test)]
mod network_adaptation_owner_prepare_events_tests;
pub mod network_adaptation_owner_inactive_events;
#[cfg(test)]
mod network_adaptation_owner_inactive_events_tests;
pub mod network_adaptation_owner_begin_active_events;
#[cfg(test)]
mod network_adaptation_owner_begin_active_events_tests;
pub mod network_adaptation_owner_completion_events;
#[cfg(test)]
mod network_adaptation_owner_completion_events_tests;
pub mod network_adaptation_owner_failure_events;
#[cfg(test)]
mod network_adaptation_owner_failure_events_tests;

pub mod microphone_forwarding_evidence;
pub mod microphone_forwarding_retry;

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_microphone_forwarding_retry_step(
    config: microphone_forwarding_retry::RawConfig,
    before: microphone_forwarding_retry::RawState,
    event: microphone_forwarding_retry::RawEvent,
) -> microphone_forwarding_retry::RawResult {
    microphone_forwarding_retry::step(config, before, event)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_microphone_forwarding_retry_result_is_valid(
    config: microphone_forwarding_retry::RawConfig,
    before: microphone_forwarding_retry::RawState,
    event: microphone_forwarding_retry::RawEvent,
    result: microphone_forwarding_retry::RawResult,
) -> u32 {
    microphone_forwarding_retry::result_is_valid(config, before, event, result)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_microphone_forwarding_readiness_decide(
    facts: microphone_forwarding_evidence::RawReadinessFacts,
) -> microphone_forwarding_evidence::RawReadinessResult {
    microphone_forwarding_evidence::readiness_decide(facts)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_microphone_forwarding_watermark_step(
    before: microphone_forwarding_evidence::RawWatermarkState,
    event: microphone_forwarding_evidence::RawWatermarkEvent,
) -> microphone_forwarding_evidence::RawWatermarkResult {
    microphone_forwarding_evidence::watermark_step(before, event)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_microphone_forwarding_freshness_decide(
    before: microphone_forwarding_evidence::RawFreshnessState,
    event: microphone_forwarding_evidence::RawFreshnessEvent,
) -> microphone_forwarding_evidence::RawFreshnessResult {
    microphone_forwarding_evidence::freshness_decide(before, event)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_microphone_forwarding_readiness_result_is_valid(
    facts: microphone_forwarding_evidence::RawReadinessFacts,
    result: microphone_forwarding_evidence::RawReadinessResult,
) -> u32 {
    microphone_forwarding_evidence::readiness_result_is_valid(facts, result)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_microphone_forwarding_watermark_result_is_valid(
    before: microphone_forwarding_evidence::RawWatermarkState,
    event: microphone_forwarding_evidence::RawWatermarkEvent,
    result: microphone_forwarding_evidence::RawWatermarkResult,
) -> u32 {
    microphone_forwarding_evidence::watermark_result_is_valid(before, event, result)
}

#[no_mangle]
#[must_use]
pub extern "C" fn beluga_core_microphone_forwarding_freshness_result_is_valid(
    before: microphone_forwarding_evidence::RawFreshnessState,
    event: microphone_forwarding_evidence::RawFreshnessEvent,
    result: microphone_forwarding_evidence::RawFreshnessResult,
) -> u32 {
    microphone_forwarding_evidence::freshness_result_is_valid(before, event, result)
}

pub mod microphone_input_lease;

#[no_mangle]
pub extern "C" fn beluga_core_microphone_input_lease_decide(
    facts: microphone_input_lease::RawFacts,
) -> microphone_input_lease::RawResult {
    microphone_input_lease::decide(facts)
}

#[no_mangle]
pub extern "C" fn beluga_core_microphone_input_lease_result_is_valid(
    facts: microphone_input_lease::RawFacts,
    result: microphone_input_lease::RawResult,
) -> u32 {
    microphone_input_lease::result_is_valid(facts, result)
}

pub mod microphone_output_format;

#[no_mangle]
pub extern "C" fn beluga_core_microphone_output_format_decide(
    facts: microphone_output_format::RawFacts,
) -> microphone_output_format::RawResult {
    microphone_output_format::decide(facts)
}

#[no_mangle]
pub extern "C" fn beluga_core_microphone_output_format_result_is_valid(
    facts: microphone_output_format::RawFacts,
    result: microphone_output_format::RawResult,
) -> u32 {
    microphone_output_format::result_is_valid(facts, result)
}
