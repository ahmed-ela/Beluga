#include <BelugaCore/beluga_core.h>
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

_Static_assert(sizeof(beluga_core_pairing_catalog_checkpoint_state_t) == 8, "checkpoint state size");
_Static_assert(_Alignof(beluga_core_pairing_catalog_checkpoint_state_t) == 4, "checkpoint state alignment");
_Static_assert(offsetof(beluga_core_pairing_catalog_checkpoint_state_t, abi_version) == 0, "checkpoint ABI offset");
_Static_assert(offsetof(beluga_core_pairing_catalog_checkpoint_state_t, flags) == 4, "checkpoint flags offset");
_Static_assert(sizeof(beluga_core_pairing_catalog_checkpoint_event_t) == 16, "checkpoint event size");
_Static_assert(_Alignof(beluga_core_pairing_catalog_checkpoint_event_t) == 4, "checkpoint event alignment");
_Static_assert(offsetof(beluga_core_pairing_catalog_checkpoint_event_t, opcode) == 0, "checkpoint opcode offset");
_Static_assert(offsetof(beluga_core_pairing_catalog_checkpoint_event_t, owner_valid) == 4, "checkpoint owner offset");
_Static_assert(offsetof(beluga_core_pairing_catalog_checkpoint_event_t, binding_matches) == 8, "checkpoint binding offset");
_Static_assert(offsetof(beluga_core_pairing_catalog_checkpoint_event_t, snapshot_matches) == 12, "checkpoint snapshot offset");
_Static_assert(sizeof(beluga_core_pairing_catalog_checkpoint_result_t) == 12, "checkpoint result size");
_Static_assert(_Alignof(beluga_core_pairing_catalog_checkpoint_result_t) == 4, "checkpoint result alignment");
_Static_assert(offsetof(beluga_core_pairing_catalog_checkpoint_result_t, candidate_state) == 0, "checkpoint candidate offset");
_Static_assert(offsetof(beluga_core_pairing_catalog_checkpoint_result_t, decision) == 8, "checkpoint decision offset");

static void pairing_catalog_checkpoint_smoke(void) {
    beluga_core_pairing_catalog_checkpoint_state_t state = beluga_core_pairing_catalog_checkpoint_initial();
    assert(state.abi_version == 1 && state.flags == 0);
    beluga_core_pairing_catalog_checkpoint_event_t event = {0, 1, 0, 0};
    beluga_core_pairing_catalog_checkpoint_result_t result = beluga_core_pairing_catalog_checkpoint_step(1, state, event);
    assert(result.decision == 0 && result.candidate_state.flags == 1 && state.flags == 0);
    state = result.candidate_state;
    result = beluga_core_pairing_catalog_checkpoint_step(1, state, event);
    assert(result.decision == 1 && memcmp(&state, &result.candidate_state, sizeof(state)) == 0);
    event = (beluga_core_pairing_catalog_checkpoint_event_t){1, 1, 0, 0};
    result = beluga_core_pairing_catalog_checkpoint_step(1, state, event);
    assert(result.decision == 1 && result.candidate_state.flags == 1);
    event.binding_matches = 1;
    result = beluga_core_pairing_catalog_checkpoint_step(1, state, event);
    assert(result.decision == 0 && result.candidate_state.flags == 1);
    event = (beluga_core_pairing_catalog_checkpoint_event_t){2, 0, 0, 0};
    result = beluga_core_pairing_catalog_checkpoint_step(1, state, event);
    assert(result.decision == 0 && result.candidate_state.flags == 3);
    state = result.candidate_state;
    event = (beluga_core_pairing_catalog_checkpoint_event_t){0, 1, 0, 0};
    result = beluga_core_pairing_catalog_checkpoint_step(1, state, event);
    assert(result.decision == 1 && result.candidate_state.flags == 3);
    event = (beluga_core_pairing_catalog_checkpoint_event_t){3, 0, 0, 1};
    result = beluga_core_pairing_catalog_checkpoint_step(1, state, event);
    assert(result.decision == 0 && result.candidate_state.flags == 3);
    event.snapshot_matches = 0;
    result = beluga_core_pairing_catalog_checkpoint_step(1, state, event);
    assert(result.decision == 1 && result.candidate_state.flags == 3);
    event.opcode = UINT32_MAX;
    result = beluga_core_pairing_catalog_checkpoint_step(1, state, event);
    assert(result.decision == 3 && memcmp(&state, &result.candidate_state, sizeof(state)) == 0);
    event.opcode = 2;
    result = beluga_core_pairing_catalog_checkpoint_step(2, state, event);
    assert(result.decision == 3 && memcmp(&state, &result.candidate_state, sizeof(state)) == 0);
    state.flags = UINT32_MAX;
    result = beluga_core_pairing_catalog_checkpoint_step(1, state, event);
    assert(result.decision == 3 && memcmp(&state, &result.candidate_state, sizeof(state)) == 0);
    puts("BelugaCore C catalog checkpoint ABI PASS: exact layouts, candidate custody, terminal revoke and full readback");
}

_Static_assert(sizeof(beluga_core_handoff_menu_policy_t) == 16, "ABI size");
_Static_assert(_Alignof(beluga_core_handoff_menu_policy_t) == 4, "ABI alignment");
_Static_assert(offsetof(beluga_core_handoff_menu_policy_t, abi_version) == 0, "ABI version offset");
_Static_assert(offsetof(beluga_core_handoff_menu_policy_t, visible) == 4, "visibility offset");
_Static_assert(offsetof(beluga_core_handoff_menu_policy_t, enabled) == 8, "admission offset");
_Static_assert(offsetof(beluga_core_handoff_menu_policy_t, reason) == 12, "reason offset");
_Static_assert(sizeof(beluga_core_host_lifecycle_state_t) == 24, "lifecycle state size");
_Static_assert(_Alignof(beluga_core_host_lifecycle_state_t) == 8, "lifecycle state alignment");
_Static_assert(offsetof(beluga_core_host_lifecycle_state_t, active_token) == 8, "active owner offset");
_Static_assert(offsetof(beluga_core_host_lifecycle_state_t, media_token) == 16, "media owner offset");
_Static_assert(sizeof(beluga_core_host_lifecycle_event_t) == 24, "lifecycle event size");
_Static_assert(offsetof(beluga_core_host_lifecycle_event_t, exchange_token) == 8, "event token offset");
_Static_assert(offsetof(beluga_core_host_lifecycle_event_t, original_utf8_length) == 16, "event length offset");
_Static_assert(sizeof(beluga_core_host_lifecycle_result_t) == 32, "lifecycle result size");
_Static_assert(offsetof(beluga_core_host_lifecycle_result_t, status) == 24, "status offset");
_Static_assert(sizeof(beluga_core_handoff_transactions_state_t) == 48, "transaction state size");
_Static_assert(_Alignof(beluga_core_handoff_transactions_state_t) == 8, "transaction state alignment");
_Static_assert(offsetof(beluga_core_handoff_transactions_state_t, host_receipt) == 8, "host receipt offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_state_t, host_envelope) == 16, "host envelope offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_state_t, host_result) == 24, "host result offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_state_t, reserved) == 28, "state reserved offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_state_t, viewer_envelope) == 32, "viewer envelope offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_state_t, viewer_offer) == 40, "viewer offer offset");
_Static_assert(sizeof(beluga_core_handoff_transactions_event_t) == 40, "transaction event size");
_Static_assert(_Alignof(beluga_core_handoff_transactions_event_t) == 8, "transaction event alignment");
_Static_assert(offsetof(beluga_core_handoff_transactions_event_t, receipt_token) == 8, "event receipt offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_event_t, envelope_token) == 16, "event envelope offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_event_t, offer_token) == 24, "event offer offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_event_t, result) == 32, "event result offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_event_t, reserved) == 36, "event reserved offset");
_Static_assert(sizeof(beluga_core_handoff_transactions_result_t) == 80, "transaction result size");
_Static_assert(_Alignof(beluga_core_handoff_transactions_result_t) == 8, "transaction result alignment");
_Static_assert(offsetof(beluga_core_handoff_transactions_result_t, status) == 48, "transaction status offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_result_t, effects) == 52, "transaction effects offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_result_t, revoked_receipt) == 56, "revoked receipt offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_result_t, completed_offer) == 64, "completed offer offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_result_t, completed_result) == 72, "completed result offset");
_Static_assert(offsetof(beluga_core_handoff_transactions_result_t, reserved) == 76, "result reserved offset");

_Static_assert(sizeof(beluga_core_handoff_offers_primary_t) == 48, "offers primary size");
_Static_assert(_Alignof(beluga_core_handoff_offers_primary_t) == 8, "offers primary alignment");
_Static_assert(offsetof(beluga_core_handoff_offers_primary_t, flags) == 0, "offers primary flags offset");
_Static_assert(offsetof(beluga_core_handoff_offers_primary_t, native_matches) == 8, "offers primary native_matches offset");
_Static_assert(offsetof(beluga_core_handoff_offers_primary_t, revision) == 16, "offers primary revision offset");
_Static_assert(offsetof(beluga_core_handoff_offers_primary_t, position) == 24, "offers primary position offset");
_Static_assert(offsetof(beluga_core_handoff_offers_primary_t, duration) == 32, "offers primary duration offset");
_Static_assert(offsetof(beluga_core_handoff_offers_primary_t, rate) == 40, "offers primary rate offset");
_Static_assert(sizeof(beluga_core_handoff_offers_envelope_t) == 56, "offers envelope size");
_Static_assert(_Alignof(beluga_core_handoff_offers_envelope_t) == 8, "offers envelope alignment");
_Static_assert(offsetof(beluga_core_handoff_offers_envelope_t, text_valid) == 0, "offers envelope text_valid offset");
_Static_assert(offsetof(beluga_core_handoff_offers_envelope_t, reserved) == 4, "offers envelope reserved offset");
_Static_assert(offsetof(beluga_core_handoff_offers_envelope_t, sequence) == 8, "offers envelope sequence offset");
_Static_assert(offsetof(beluga_core_handoff_offers_envelope_t, revision) == 16, "offers envelope revision offset");
_Static_assert(offsetof(beluga_core_handoff_offers_envelope_t, position) == 24, "offers envelope position offset");
_Static_assert(offsetof(beluga_core_handoff_offers_envelope_t, duration) == 32, "offers envelope duration offset");
_Static_assert(offsetof(beluga_core_handoff_offers_envelope_t, rate) == 40, "offers envelope rate offset");
_Static_assert(offsetof(beluga_core_handoff_offers_envelope_t, lifetime) == 48, "offers envelope lifetime offset");
_Static_assert(sizeof(beluga_core_handoff_offers_source_t) == 48, "offers source size");
_Static_assert(_Alignof(beluga_core_handoff_offers_source_t) == 8, "offers source alignment");
_Static_assert(offsetof(beluga_core_handoff_offers_source_t, present) == 0, "offers source present offset");
_Static_assert(offsetof(beluga_core_handoff_offers_source_t, video_equal) == 4, "offers source video_equal offset");
_Static_assert(offsetof(beluga_core_handoff_offers_source_t, position) == 8, "offers source position offset");
_Static_assert(offsetof(beluga_core_handoff_offers_source_t, duration) == 16, "offers source duration offset");
_Static_assert(offsetof(beluga_core_handoff_offers_source_t, rate) == 24, "offers source rate offset");
_Static_assert(offsetof(beluga_core_handoff_offers_source_t, observed_at) == 32, "offers source observed_at offset");
_Static_assert(offsetof(beluga_core_handoff_offers_source_t, deadline) == 40, "offers source deadline offset");
_Static_assert(sizeof(beluga_core_handoff_offers_timeline_t) == 88, "offers timeline size");
_Static_assert(_Alignof(beluga_core_handoff_offers_timeline_t) == 8, "offers timeline alignment");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, token) == 0, "offers timeline token offset");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, sequence) == 8, "offers timeline sequence offset");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, revision) == 16, "offers timeline revision offset");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, position) == 24, "offers timeline position offset");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, duration) == 32, "offers timeline duration offset");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, rate) == 40, "offers timeline rate offset");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, lifetime) == 48, "offers timeline lifetime offset");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, origin) == 56, "offers timeline origin offset");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, deadline) == 64, "offers timeline deadline offset");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, last_observation) == 72, "offers timeline last_observation offset");
_Static_assert(offsetof(beluga_core_handoff_offers_timeline_t, last_position) == 80, "offers timeline last_position offset");
_Static_assert(sizeof(beluga_core_handoff_offers_state_t) == 224, "offers state size");
_Static_assert(_Alignof(beluga_core_handoff_offers_state_t) == 8, "offers state alignment");
_Static_assert(offsetof(beluga_core_handoff_offers_state_t, abi) == 0, "offers state abi offset");
_Static_assert(offsetof(beluga_core_handoff_offers_state_t, presence) == 4, "offers state presence offset");
_Static_assert(offsetof(beluga_core_handoff_offers_state_t, terminal) == 8, "offers state terminal offset");
_Static_assert(offsetof(beluga_core_handoff_offers_state_t, reserved) == 12, "offers state reserved offset");
_Static_assert(offsetof(beluga_core_handoff_offers_state_t, next_sent) == 16, "offers state next_sent offset");
_Static_assert(offsetof(beluga_core_handoff_offers_state_t, highest_received) == 24, "offers state highest_received offset");
_Static_assert(offsetof(beluga_core_handoff_offers_state_t, sent_at) == 32, "offers state sent_at offset");
_Static_assert(offsetof(beluga_core_handoff_offers_state_t, received_at) == 40, "offers state received_at offset");
_Static_assert(offsetof(beluga_core_handoff_offers_state_t, sent) == 48, "offers state sent offset");
_Static_assert(offsetof(beluga_core_handoff_offers_state_t, received) == 136, "offers state received offset");
_Static_assert(sizeof(beluga_core_handoff_offers_event_t) == 200, "offers event size");
_Static_assert(_Alignof(beluga_core_handoff_offers_event_t) == 8, "offers event alignment");
_Static_assert(offsetof(beluga_core_handoff_offers_event_t, opcode) == 0, "offers event opcode offset");
_Static_assert(offsetof(beluga_core_handoff_offers_event_t, reserved) == 4, "offers event reserved offset");
_Static_assert(offsetof(beluga_core_handoff_offers_event_t, token) == 8, "offers event token offset");
_Static_assert(offsetof(beluga_core_handoff_offers_event_t, native_matches) == 16, "offers event native_matches offset");
_Static_assert(offsetof(beluga_core_handoff_offers_event_t, now) == 24, "offers event now offset");
_Static_assert(offsetof(beluga_core_handoff_offers_event_t, phone_position) == 32, "offers event phone_position offset");
_Static_assert(offsetof(beluga_core_handoff_offers_event_t, phone_observed_at) == 40, "offers event phone_observed_at offset");
_Static_assert(offsetof(beluga_core_handoff_offers_event_t, primary) == 48, "offers event primary offset");
_Static_assert(offsetof(beluga_core_handoff_offers_event_t, envelope) == 96, "offers event envelope offset");
_Static_assert(offsetof(beluga_core_handoff_offers_event_t, source) == 152, "offers event source offset");
_Static_assert(sizeof(beluga_core_handoff_offers_result_t) == 288, "offers result size");
_Static_assert(_Alignof(beluga_core_handoff_offers_result_t) == 8, "offers result alignment");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, state) == 0, "offers result state offset");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, status) == 224, "offers result status offset");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, decision) == 228, "offers result decision offset");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, effects) == 232, "offers result effects offset");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, reserved) == 236, "offers result reserved offset");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, retired_sent) == 240, "offers result retired_sent offset");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, retired_received) == 248, "offers result retired_received offset");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, minted_token) == 256, "offers result minted_token offset");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, sequence) == 264, "offers result sequence offset");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, lifetime) == 272, "offers result lifetime offset");
_Static_assert(offsetof(beluga_core_handoff_offers_result_t, deadline) == 280, "offers result deadline offset");

/* memcpy preserves the exact floating bit pattern without aliasing or casts. */
static uint64_t double_bits(double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}
static beluga_core_handoff_offers_event_t offers_event(uint32_t opcode, double now) {
    beluga_core_handoff_offers_event_t event = {0};
    event.opcode = opcode; event.token = 100; event.native_matches = 15;
    event.now = double_bits(now); event.phone_position = double_bits(20.0);
    event.phone_observed_at = double_bits(now);
    event.primary = (beluga_core_handoff_offers_primary_t){511, 12, 1,
        double_bits(20.0), double_bits(200.0), double_bits(1.0)};
    event.envelope = (beluga_core_handoff_offers_envelope_t){1, 0, 1, 1,
        double_bits(20.0), double_bits(200.0), double_bits(1.0), double_bits(30.0)};
    return event;
}
static beluga_core_handoff_offers_state_t offers_pair(void) {
    beluga_core_handoff_offers_state_t state = beluga_core_handoff_offers_initial();
    assert(state.abi == 1 && state.presence == 0 && state.terminal == 0 && state.next_sent == 1);
    const uint32_t operations[] = {0, 1, 2, 5};
    for (unsigned i = 0; i < sizeof(operations) / sizeof(operations[0]); ++i) {
        beluga_core_handoff_offers_result_t result =
            beluga_core_handoff_offers_step(1, state, offers_event(operations[i], 10.0));
        assert(result.status == 0 && result.reserved == 0);
        if (operations[i] == 2 || operations[i] == 5) {
            assert(result.decision == (operations[i] == 2 ? 1U : 2U));
            assert(result.minted_token == 100 && result.sequence == 1);
            assert(result.lifetime == double_bits(30.0) && result.deadline == double_bits(40.0));
        }
        state = result.state;
    }
    assert(state.presence == 15 && state.next_sent == 2 && state.highest_received == 1);
    assert(state.sent.token == 100 && state.received.token == 100);
    return state;
}

static uint32_t expected_reason(uint32_t f) {
    if (f > 127) return 9;
    if (f & 2) return 1;
    if (!(f & 1)) return 2;
    if (f & 4) return 3;
    if (f & 8) return 4;
    if (!(f & 16)) return 5;
    if (!(f & 32)) return 6;
    if (!(f & 64)) return 7;
    return 0;
}

static void tier_demand_smoke(void) {
    /* Checked copied tier-demand ABI, emitted after the predecessor cohort. */
    _Static_assert(sizeof(beluga_core_tier_demand_facts_t) == 24, "tier facts size");
    _Static_assert(_Alignof(beluga_core_tier_demand_facts_t) == 8, "tier facts alignment");
    _Static_assert(sizeof(beluga_core_tier_demand_projection_t) == 80, "tier projection size");
    _Static_assert(_Alignof(beluga_core_tier_demand_projection_t) == 8, "tier projection alignment");
    _Static_assert(offsetof(beluga_core_tier_demand_facts_t, abi_version) == 0, "tier facts ABI offset");
    _Static_assert(offsetof(beluga_core_tier_demand_facts_t, configured_cap) == 4, "tier cap offset");
    _Static_assert(offsetof(beluga_core_tier_demand_facts_t, current_tier) == 8, "tier ordinal offset");
    _Static_assert(offsetof(beluga_core_tier_demand_facts_t, bandwidth_present) == 12, "tier presence offset");
    _Static_assert(offsetof(beluga_core_tier_demand_facts_t, bandwidth_bits) == 16, "tier bandwidth offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, abi_version) == 0, "tier result ABI offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, status) == 4, "tier status offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, current_tier) == 8, "tier result ordinal offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, reserved) == 12, "tier reserved offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, basis_points) == 16, "tier basis offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, baseline_video) == 20, "tier baseline offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, maximum_tier_video) == 24, "tier budget offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, maximum_video) == 28, "tier video offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, maximum_total_rtp) == 32, "tier RTP offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, minimum_sustainable) == 36, "tier demand offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, initial_tier) == 40, "tier initial offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, sustainable_tier) == 44, "tier sustainable offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, upgrade_present) == 48, "tier upgrade presence offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, upgrade_tier) == 52, "tier upgrade offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, direct_threshold_present) == 56, "tier direct presence offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, direct_threshold_minimum) == 60, "tier direct minimum offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, required_bitrate_bits) == 64, "tier required bits offset");
    _Static_assert(offsetof(beluga_core_tier_demand_projection_t, direct_threshold_bits) == 72, "tier direct bits offset");
    beluga_core_tier_demand_facts_t tier_facts = {1, 50000000, 0, 1, 0};
    tier_facts.bandwidth_bits = double_bits(15000000.0);
    beluga_core_tier_demand_projection_t tier_projection = beluga_core_tier_demand_project(tier_facts);
    assert(tier_projection.status == 1 && tier_projection.basis_points == 10000);
    assert(tier_projection.maximum_tier_video == 39744000 && tier_projection.maximum_video == 39744000);
    assert(tier_projection.maximum_total_rtp == 16200001 && tier_projection.minimum_sustainable == 12000000);
    assert(tier_projection.initial_tier == 5 && tier_projection.sustainable_tier == 0);
    assert(tier_projection.upgrade_present == 0 && tier_projection.direct_threshold_present == 0);
    assert(tier_projection.required_bitrate_bits == double_bits(12000000.0));
    assert(beluga_core_tier_demand_projection_is_valid(tier_facts, tier_projection) == 1);
    tier_facts.current_tier = 7;
    tier_projection = beluga_core_tier_demand_project(tier_facts);
    assert(tier_projection.upgrade_present == 1 && tier_projection.upgrade_tier == 0);
    assert(tier_projection.direct_threshold_minimum == 546000 && tier_projection.direct_threshold_bits == double_bits(546000.0));
    tier_projection.reserved = 1;
    assert(beluga_core_tier_demand_projection_is_valid(tier_facts, tier_projection) == 0);
    tier_facts.configured_cap = UINT32_MAX; tier_facts.current_tier = 1;
    tier_projection = beluga_core_tier_demand_project(tier_facts);
    assert(tier_projection.maximum_tier_video == 3435717836U && tier_projection.maximum_video == 2301930950U);
    tier_facts.configured_cap = 0;
    tier_projection = beluga_core_tier_demand_project(tier_facts);
    beluga_core_tier_demand_projection_t tier_denied = {0}; tier_denied.abi_version = 1;
    assert(memcmp(&tier_projection, &tier_denied, sizeof(tier_denied)) == 0);
    assert(beluga_core_tier_demand_projection_is_valid(tier_facts, tier_projection) == 0);
    puts("BelugaCore C tier demand ABI PASS: exact copied layouts, calibrated budgets and checked projections");
}

#include <BelugaCore/beluga_core.h>
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#define PHONE_TYPE(suffix) beluga_core_youtube_handoff_operation_##suffix##_t
#define PHONE_LAYOUT(type, bytes) \
    _Static_assert(sizeof(PHONE_TYPE(type)) == bytes, "phone " #type " size"); \
    _Static_assert(_Alignof(PHONE_TYPE(type)) == 8, "phone " #type " alignment")
#define PHONE_OFFSET(type, field, bytes) \
    _Static_assert(offsetof(PHONE_TYPE(type), field) == bytes, "phone " #type " " #field " offset")
PHONE_LAYOUT(request, 40);
PHONE_OFFSET(request, position, 0); PHONE_OFFSET(request, duration, 8);
PHONE_OFFSET(request, rate, 16); PHONE_OFFSET(request, deadline, 24);
PHONE_OFFSET(request, position_observed_at, 32);
PHONE_LAYOUT(evidence, 32);
PHONE_OFFSET(evidence, token, 0); PHONE_OFFSET(evidence, position, 8);
PHONE_OFFSET(evidence, rate, 16); PHONE_OFFSET(evidence, observed_at, 24);
PHONE_LAYOUT(state, 152);
PHONE_OFFSET(state, abi, 0); PHONE_OFFSET(state, phase, 4);
PHONE_OFFSET(state, failure, 8); PHONE_OFFSET(state, mac_pause, 12);
PHONE_OFFSET(state, flags, 16); PHONE_OFFSET(state, presence, 20);
PHONE_OFFSET(state, sequence, 24); PHONE_OFFSET(state, reserved, 28);
PHONE_OFFSET(state, request, 32); PHONE_OFFSET(state, last_now, 72);
PHONE_OFFSET(state, first_position, 80); PHONE_OFFSET(state, first_at, 88);
PHONE_OFFSET(state, latest_playing_at, 96); PHONE_OFFSET(state, latest_state, 104);
PHONE_OFFSET(state, latest_state_reserved, 108); PHONE_OFFSET(state, evidence, 112);
PHONE_OFFSET(state, reply_deadline, 144);
PHONE_LAYOUT(event, 80);
PHONE_OFFSET(event, opcode, 0); PHONE_OFFSET(event, flags, 4);
PHONE_OFFSET(event, presence, 8); PHONE_OFFSET(event, sequence, 12);
PHONE_OFFSET(event, kind, 16); PHONE_OFFSET(event, sample_state, 20);
PHONE_OFFSET(event, completion, 24); PHONE_OFFSET(event, failure, 28);
PHONE_OFFSET(event, now, 32); PHONE_OFFSET(event, proof_token, 40);
PHONE_OFFSET(event, candidate_token, 48); PHONE_OFFSET(event, sample_position, 56);
PHONE_OFFSET(event, sample_duration, 64); PHONE_OFFSET(event, sample_rate, 72);
PHONE_LAYOUT(result, 168);
PHONE_OFFSET(result, state, 0); PHONE_OFFSET(result, status, 152);
PHONE_OFFSET(result, event, 156); PHONE_OFFSET(result, accepted, 160);
PHONE_OFFSET(result, failure, 164);
#undef PHONE_OFFSET
#undef PHONE_LAYOUT

static uint64_t phone_bits(double value) {
    uint64_t bits; memcpy(&bits, &value, sizeof(bits)); return bits;
}
static PHONE_TYPE(request) phone_request(void) {
    return (PHONE_TYPE(request)){phone_bits(20.0), phone_bits(200.0), phone_bits(1.0),
        phone_bits(40.0), phone_bits(10.0)};
}
static PHONE_TYPE(event) phone_event(uint32_t opcode, double now) {
    PHONE_TYPE(event) event = {0}; event.opcode = opcode; event.now = phone_bits(now); return event;
}
static PHONE_TYPE(event) phone_message(uint32_t sequence, uint32_t kind, double position, double now) {
    PHONE_TYPE(event) event = phone_event(2, now);
    event.flags = 14; event.sequence = sequence; event.kind = kind; event.candidate_token = 91;
    if (kind == 2) {
        event.presence = 15; event.sample_state = 1; event.sample_position = phone_bits(position);
        event.sample_duration = phone_bits(200.0); event.sample_rate = phone_bits(1.0);
    }
    return event;
}
static PHONE_TYPE(result) phone_apply(PHONE_TYPE(state) *state, PHONE_TYPE(event) event) {
    PHONE_TYPE(result) result = beluga_core_youtube_handoff_operation_step(1, *state, event);
    assert(result.status == 0); *state = result.state; return result;
}
static PHONE_TYPE(state) phone_confirm(uint64_t token) {
    PHONE_TYPE(state) state = beluga_core_youtube_handoff_operation_initial(phone_request(), phone_bits(10.0));
    assert(state.abi == 1 && state.phase == 0 && state.flags == 0 && state.presence == 0);
    PHONE_TYPE(event) event = phone_event(0, 10.0); event.flags = 1; phone_apply(&state, event);
    phone_apply(&state, phone_message(1, 0, 20.0, 10.0));
    phone_apply(&state, phone_message(2, 2, 20.0, 10.1));
    event = phone_message(3, 2, 20.3, 10.4); event.candidate_token = token;
    PHONE_TYPE(result) result = phone_apply(&state, event);
    assert(result.event == 2 && result.accepted == 0 && result.failure == 0);
    assert(state.phase == 4 && state.mac_pause == 0 && state.evidence.token == token);
    assert(state.evidence.position == phone_bits(20.3) && state.evidence.observed_at == phone_bits(10.4));
    return state;
}
static PHONE_TYPE(event) phone_proof(uint32_t opcode, double now, uint64_t token) {
    PHONE_TYPE(event) event = phone_event(opcode, now); event.flags = 16; event.proof_token = token; return event;
}
static PHONE_TYPE(event) phone_completion(uint32_t outcome, double now) {
    PHONE_TYPE(event) event = phone_event(5, now); event.flags = 32; event.completion = outcome; return event;
}
static PHONE_TYPE(state) phone_pending(void) {
    PHONE_TYPE(state) state = phone_confirm(91);
    PHONE_TYPE(result) result = phone_apply(&state, phone_proof(4, 10.5, 91));
    assert(result.accepted == 1 && result.event == 0 && state.mac_pause == 1 && state.phase == 5);
    assert(state.reply_deadline == phone_bits(13.5)); return state;
}
static void phone_unchanged(PHONE_TYPE(result) result, PHONE_TYPE(state) expected, uint32_t status) {
    assert(result.status == status && result.event == 0 && result.accepted == 0 && result.failure == 0);
    assert(memcmp(&result.state, &expected, sizeof(expected)) == 0);
}
static void phone_operation_smoke(void) {
    const uint64_t infinity_bits = UINT64_C(0x7ff0000000000000);
    const uint64_t negative_infinity_bits = UINT64_C(0xfff0000000000000);
    const uint64_t nan_bits = UINT64_C(0x7ff8000000001234);
    PHONE_TYPE(state) state = beluga_core_youtube_handoff_operation_initial(phone_request(), nan_bits);
    assert(state.phase == 0 && state.last_now == nan_bits);
    PHONE_TYPE(event) event = phone_message(1, 0, 0.0, 0.0); event.flags = 0; event.now = infinity_bits;
    phone_unchanged(beluga_core_youtube_handoff_operation_step(1, state, event), state, 0);
    PHONE_TYPE(result) result = phone_apply(&state, phone_event(1, 10.0));
    assert(result.event == 4 && result.failure == 9 && state.last_now == nan_bits);

    state = phone_confirm(91); PHONE_TYPE(state) before = state;
    event = phone_message(99, 3, 0.0, 0.0); event.flags = 10; event.now = infinity_bits;
    phone_unchanged(beluga_core_youtube_handoff_operation_step(1, state, event), before, 0);
    event = phone_message(1, 0, 0.0, 40.0); result = phone_apply(&state, event);
    assert(result.event == 4 && result.failure == 2 && state.sequence == before.sequence);

    state = phone_confirm(91);
    result = phone_apply(&state, phone_proof(4, 10.5, 92));
    assert(result.accepted == 0 && state.mac_pause == 0);
    event = phone_event(4, 10.5); result = phone_apply(&state, event);
    assert(result.accepted == 0 && state.evidence.token == 91);
    state = phone_pending(); before = state;
    event = phone_proof(4, 0.0, 91); event.now = nan_bits;
    phone_unchanged(beluga_core_youtube_handoff_operation_step(1, state, event), before, 0);
    event = phone_completion(1, 0.0); event.flags = 0; event.now = infinity_bits;
    phone_unchanged(beluga_core_youtube_handoff_operation_step(1, state, event), before, 0);
    phone_apply(&state, phone_message(4, 2, 21.3, 11.4));
    result = phone_apply(&state, phone_proof(3, 11.4, 91));
    assert(result.accepted == 0 && state.evidence.observed_at == phone_bits(10.4));
    result = phone_apply(&state, phone_completion(1, 11.5));
    assert(result.event == 3 && state.phase == 6 && state.mac_pause == 2 && state.evidence.token == 0);
    event = phone_message(5, 2, 80.0, 60.0); event.sample_state = 2; event.sample_rate = phone_bits(2.0);
    result = phone_apply(&state, event);
    assert(result.event == 0 && state.phase == 6 && state.mac_pause == 2);
    result = phone_apply(&state, phone_proof(3, 60.0, 91)); assert(result.accepted == 0);

    state = phone_pending(); result = phone_apply(&state, phone_completion(1, 11.5));
    assert(result.event == 4 && result.failure == 12 && state.mac_pause == 2 && state.evidence.token == 91);
    assert(state.phase == 7 && (state.flags & 8) == 8);
    state = phone_pending(); event = (PHONE_TYPE(event)){0}; event.opcode = 6; event.failure = 4;
    result = phone_apply(&state, event);
    assert(result.event == 4 && result.failure == 4 && state.mac_pause == 4 && state.evidence.token == 91);
    before = state; phone_unchanged(beluga_core_youtube_handoff_operation_step(1, state, phone_completion(1, 10.6)), before, 0);

    state = beluga_core_youtube_handoff_operation_initial(phone_request(), phone_bits(10.0));
    event = phone_event(0, 10.0); event.flags = 1; phone_apply(&state, event);
    event = phone_message(1, 0, 0.0, 10.0); event.candidate_token = 0; phone_apply(&state, event);
    event = phone_message(2, 2, 20.0, 10.1); event.candidate_token = 0; phone_apply(&state, event);
    assert(state.phase == 3 && state.evidence.token == 0);
    event = phone_message(3, 2, 20.3, 10.4); event.candidate_token = 0; result = phone_apply(&state, event);
    assert(result.event == 4 && result.failure == 8 && state.phase == 7);
    assert(state.sequence == 3 && state.last_now == phone_bits(10.4) && state.evidence.token == 0);
    state = phone_confirm(UINT64_MAX); event = phone_message(4, 2, 20.5, 10.6); event.candidate_token = 0;
    phone_apply(&state, event); assert(state.evidence.token == UINT64_MAX && state.phase == 4);

    before = state; event = phone_event(7, 10.6);
    phone_unchanged(beluga_core_youtube_handoff_operation_step(1, state, event), before, 3);
    phone_unchanged(beluga_core_youtube_handoff_operation_step(2, state, phone_event(1, 10.6)), before, 3);
    state.reserved = 1; before = state;
    phone_unchanged(beluga_core_youtube_handoff_operation_step(1, state, phone_event(1, 10.6)), before, 3);

    state = beluga_core_youtube_handoff_operation_initial(phone_request(), negative_infinity_bits);
    event = phone_event(0, -20.0); event.flags = 1; phone_apply(&state, event);
    phone_apply(&state, phone_message(1, 0, 0.0, -20.0));
    phone_apply(&state, phone_message(2, 2, 20.0, -19.9));
    result = phone_apply(&state, phone_message(3, 2, 20.3, -19.6)); assert(result.event == 2);
    result = phone_apply(&state, phone_proof(4, -19.5, 91)); assert(result.accepted == 1);
    assert(state.evidence.observed_at == phone_bits(-19.6) && state.reply_deadline == phone_bits(-16.5));
    result = phone_apply(&state, phone_completion(1, -19.4)); assert(result.event == 3);
    state = beluga_core_youtube_handoff_operation_initial(phone_request(), phone_bits(-0.0));
    assert(state.last_now == UINT64_C(0x8000000000000000));
    phone_apply(&state, phone_event(1, 0.0)); assert(state.last_now == 0);
    phone_apply(&state, phone_event(1, -0.0)); assert(state.last_now == UINT64_C(0x8000000000000000));
    puts("BelugaCore C phone operation ABI PASS: exact layouts, original ordering, immutable proof and honest pause outcomes");
}
#undef PHONE_TYPE


_Static_assert(_Alignof(beluga_core_invitation_acceptance_state_t) == 4, "invitation state alignment");
_Static_assert(offsetof(beluga_core_invitation_acceptance_state_t, abi_version) == 0, "invitation state version offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_state_t, flags) == 4, "invitation flags offset");
_Static_assert(_Alignof(beluga_core_invitation_acceptance_event_t) == 4, "invitation event alignment");
_Static_assert(offsetof(beluga_core_invitation_acceptance_event_t, opcode) == 0, "invitation opcode offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_event_t, generation_matches) == 4, "invitation generation projection offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_event_t, phase) == 8, "invitation phase offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_event_t, admission_callback_present) == 12, "invitation admission projection offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_event_t, prepared_kind) == 16, "invitation prepared kind offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_event_t, prepared_flags) == 20, "invitation prepared flags offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_event_t, owner_matches) == 24, "invitation exact owner projection offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_event_t, callback_outcome) == 28, "invitation actual outcome offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_result_t, state) == 0, "invitation state offset");
_Static_assert(sizeof(beluga_core_invitation_acceptance_state_t) == 8, "state size");
_Static_assert(sizeof(beluga_core_invitation_acceptance_event_t) == 32, "event size");
_Static_assert(sizeof(beluga_core_invitation_acceptance_result_t) == 32, "result size");
_Static_assert(_Alignof(beluga_core_invitation_acceptance_result_t) == 4, "result alignment");
_Static_assert(offsetof(beluga_core_invitation_acceptance_result_t, callback_success_state) == 8, "candidate offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_result_t, status) == 16, "status offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_result_t, completion_succeeded) == 20, "completion offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_result_t, callback_kind) == 24, "kind offset");
_Static_assert(offsetof(beluga_core_invitation_acceptance_result_t, prepared_flags) == 28, "prepared offset");

static beluga_core_invitation_acceptance_result_t invitation_step(
    beluga_core_invitation_acceptance_state_t state,
    beluga_core_invitation_acceptance_event_t event) {
    return beluga_core_invitation_acceptance_step(1, state, event);
}
static void invitation_acceptance_smoke(void) {
    beluga_core_invitation_acceptance_state_t state = beluga_core_invitation_acceptance_initial();
    assert(state.abi_version == 1 && state.flags == 0);
    beluga_core_invitation_acceptance_event_t e = { .opcode = BELUGA_INVITATION_ARM, .admission_callback_present = 1 };
    beluga_core_invitation_acceptance_result_t r = invitation_step(state, e);
    assert(r.status == BELUGA_INVITATION_APPLIED && r.state.flags == 7 && r.callback_kind == 0);
    state = r.state;
    e = (beluga_core_invitation_acceptance_event_t){ .opcode = BELUGA_INVITATION_PREPARE_ADMISSION, .phase = UINT32_MAX };
    r = invitation_step(state, e);
    assert(r.status == BELUGA_INVITATION_IGNORED && r.state.flags == 7 && r.callback_kind == 0);
    e.generation_matches = 1; e.phase = BELUGA_INVITATION_PHASE_ACCEPTED_ISSUED;
    r = invitation_step(state, e);
    assert(r.status == BELUGA_INVITATION_NEEDS_CALLBACK && r.state.flags == 7 &&
          r.callback_success_state.flags == 15 && r.callback_kind == BELUGA_INVITATION_ADMISSION_CALLBACK &&
          r.prepared_flags == 7 && r.completion_succeeded == 0);
    e = (beluga_core_invitation_acceptance_event_t){ .opcode = BELUGA_INVITATION_ACKNOWLEDGE_CALLBACK,
        .prepared_kind = r.callback_kind, .prepared_flags = r.prepared_flags,
        .owner_matches = 1, .callback_outcome = BELUGA_INVITATION_CALLBACK_THREW };
    r = invitation_step(state, e);
    assert(r.status == BELUGA_INVITATION_CALLBACK_FAILED && r.state.flags == 7 && r.completion_succeeded == 0);
    e.callback_outcome = BELUGA_INVITATION_CALLBACK_SUCCEEDED;
    r = invitation_step(state, e); assert(r.status == BELUGA_INVITATION_APPLIED && r.state.flags == 15);
    state = r.state;
    e = (beluga_core_invitation_acceptance_event_t){ .opcode = BELUGA_INVITATION_PREPARE_ADMISSION,
        .generation_matches = 1, .phase = UINT32_MAX };
    r = invitation_step(state, e); assert(r.status == BELUGA_INVITATION_IGNORED && r.state.flags == 15);
    e = (beluga_core_invitation_acceptance_event_t){ .opcode = BELUGA_INVITATION_PREPARE_COMPLETION,
        .generation_matches = 1, .phase = BELUGA_INVITATION_PHASE_ACTIVE };
    r = invitation_step(state, e);
    assert(r.status == BELUGA_INVITATION_NEEDS_CALLBACK && r.state.flags == 15 && r.callback_success_state.flags == 0 && r.callback_kind == 2);
    e = (beluga_core_invitation_acceptance_event_t){ .opcode = BELUGA_INVITATION_ACKNOWLEDGE_CALLBACK,
        .prepared_kind = r.callback_kind, .prepared_flags = r.prepared_flags,
        .owner_matches = 0, .callback_outcome = BELUGA_INVITATION_CALLBACK_SUCCEEDED };
    r = invitation_step(state, e); assert(r.status == BELUGA_INVITATION_STALE_PREPARED_PLAN && r.state.flags == 15);
    e.owner_matches = 1; r = invitation_step(state, e);
    assert(r.status == BELUGA_INVITATION_APPLIED && r.state.flags == 0 && r.completion_succeeded == 1);
    state = r.state;
    e = (beluga_core_invitation_acceptance_event_t){ .opcode = BELUGA_INVITATION_ARM };
    state = invitation_step(state, e).state;
    e = (beluga_core_invitation_acceptance_event_t){ .opcode = BELUGA_INVITATION_PREPARE_ADMISSION,
        .generation_matches = 1, .phase = BELUGA_INVITATION_PHASE_ACCEPTED_ISSUED };
    r = invitation_step(state, e); assert(r.status == BELUGA_INVITATION_APPLIED && r.state.flags == 13 && r.callback_kind == 0);
    e = (beluga_core_invitation_acceptance_event_t){ .opcode = BELUGA_INVITATION_CANCEL, .generation_matches = 1 };
    r = beluga_core_invitation_acceptance_step(2, state, e);
    assert(r.status == BELUGA_INVITATION_INVALID_INPUT && r.state.flags == state.flags && r.callback_kind == 0);
    puts("BelugaCore C invitation acceptance ABI PASS: exact layouts, original guard order and one-use callback outcomes");
}

_Static_assert(sizeof(beluga_core_signaling_replay_state_t) == 24, "replay state size");
_Static_assert(_Alignof(beluga_core_signaling_replay_state_t) == 8, "replay state alignment");
_Static_assert(offsetof(beluga_core_signaling_replay_state_t, abi_version) == 0, "replay ABI offset");
_Static_assert(offsetof(beluga_core_signaling_replay_state_t, has_highest) == 4, "replay presence offset");
_Static_assert(offsetof(beluga_core_signaling_replay_state_t, highest) == 8, "replay highest offset");
_Static_assert(offsetof(beluga_core_signaling_replay_state_t, bitmap) == 16, "replay bitmap offset");
_Static_assert(sizeof(beluga_core_signaling_replay_result_t) == 32, "replay result size");
_Static_assert(_Alignof(beluga_core_signaling_replay_result_t) == 8, "replay result alignment");
_Static_assert(offsetof(beluga_core_signaling_replay_result_t, state) == 0, "replay state result offset");
_Static_assert(offsetof(beluga_core_signaling_replay_result_t, decision) == 24, "replay decision offset");
_Static_assert(offsetof(beluga_core_signaling_replay_result_t, reserved) == 28, "replay reserved offset");

static void replay_same(beluga_core_signaling_replay_state_t left,
                        beluga_core_signaling_replay_state_t right) {
    assert(memcmp(&left, &right, sizeof(left)) == 0);
}
static void signaling_replay_smoke(void) {
    const beluga_core_signaling_replay_state_t empty = beluga_core_signaling_replay_initial();
    assert(empty.abi_version == 1 && empty.has_highest == 0 && empty.highest == 0 && empty.bitmap == 0);
    beluga_core_signaling_replay_result_t r = beluga_core_signaling_replay_step(1, empty, 0);
    assert(r.decision == 0 && r.reserved == 0 && r.state.abi_version == 1 &&
           r.state.has_highest == 1 && r.state.highest == 0 && r.state.bitmap == 1);
    const beluga_core_signaling_replay_state_t zero = r.state;
    r = beluga_core_signaling_replay_step(1, zero, 0);
    assert(r.decision == 1 && r.reserved == 0); replay_same(r.state, zero);
    r = beluga_core_signaling_replay_step(1, zero, 63);
    assert(r.decision == 0 && r.state.highest == 63 && r.state.bitmap == ((UINT64_C(1) << 63) | 1));
    r = beluga_core_signaling_replay_step(1, zero, 64);
    assert(r.decision == 0 && r.state.highest == 64 && r.state.bitmap == 1);
    const beluga_core_signaling_replay_state_t sixty_four = r.state;
    r = beluga_core_signaling_replay_step(1, sixty_four, 1);
    assert(r.decision == 0 && r.state.highest == 64 && r.state.bitmap == ((UINT64_C(1) << 63) | 1));
    const beluga_core_signaling_replay_state_t reordered = r.state;
    r = beluga_core_signaling_replay_step(1, reordered, 0);
    assert(r.decision == 2 && r.reserved == 0); replay_same(r.state, reordered);
    r = beluga_core_signaling_replay_step(1, reordered, 2);
    assert(r.decision == 0 && r.state.bitmap == ((UINT64_C(1) << 63) | (UINT64_C(1) << 62) | 1));
    assert(sixty_four.bitmap == 1 && reordered.bitmap == ((UINT64_C(1) << 63) | 1));
    r = beluga_core_signaling_replay_step(1, empty, UINT64_MAX);
    assert(r.decision == 0 && r.state.highest == UINT64_MAX && r.state.bitmap == 1);
    const beluga_core_signaling_replay_state_t maximum = r.state;
    r = beluga_core_signaling_replay_step(1, maximum, UINT64_MAX - 63);
    assert(r.decision == 0 && r.state.bitmap == ((UINT64_C(1) << 63) | 1));
    r = beluga_core_signaling_replay_step(1, maximum, UINT64_MAX - 64);
    assert(r.decision == 2 && r.reserved == 0); replay_same(r.state, maximum);
    r = beluga_core_signaling_replay_step(1, maximum, UINT64_MAX);
    assert(r.decision == 1 && r.reserved == 0); replay_same(r.state, maximum);
    r = beluga_core_signaling_replay_step(2, maximum, UINT64_MAX);
    assert(r.decision == 3 && r.reserved == 0); replay_same(r.state, maximum);
    const beluga_core_signaling_replay_state_t bad[] = {
        {0, 0, 0, 0}, {1, 2, 0, 0}, {1, 0, 1, 0}, {1, 0, 0, 1},
        {1, 1, 10, 0}, {1, 1, 10, 2}, {1, 1, 0, 3}
    };
    for (unsigned i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        r = beluga_core_signaling_replay_step(1, bad[i], 7);
        assert(r.decision == 3 && r.reserved == 0); replay_same(r.state, bad[i]);
    }
    puts("BelugaCore C signaling replay ABI PASS: exact layouts, zero/MAX, 63/64 window and unchanged rejection");
}
_Static_assert(sizeof(beluga_core_reconnect_counters_state_t) == 24, "reconnect state size");
_Static_assert(_Alignof(beluga_core_reconnect_counters_state_t) == 8, "reconnect state alignment");
_Static_assert(offsetof(beluga_core_reconnect_counters_state_t, abi_version) == 0, "reconnect state ABI offset");
_Static_assert(offsetof(beluga_core_reconnect_counters_state_t, reserved) == 4, "reconnect state reserved offset");
_Static_assert(offsetof(beluga_core_reconnect_counters_state_t, next_outbound) == 8, "reconnect outbound offset");
_Static_assert(offsetof(beluga_core_reconnect_counters_state_t, highest_accepted) == 16, "reconnect highwater offset");
_Static_assert(sizeof(beluga_core_reconnect_counters_event_t) == 16, "reconnect event size");
_Static_assert(_Alignof(beluga_core_reconnect_counters_event_t) == 8, "reconnect event alignment");
_Static_assert(offsetof(beluga_core_reconnect_counters_event_t, opcode) == 0, "reconnect opcode offset");
_Static_assert(offsetof(beluga_core_reconnect_counters_event_t, reserved) == 4, "reconnect event reserved offset");
_Static_assert(offsetof(beluga_core_reconnect_counters_event_t, request_sequence) == 8, "reconnect request offset");
_Static_assert(sizeof(beluga_core_reconnect_counters_result_t) == 32, "reconnect result size");
_Static_assert(_Alignof(beluga_core_reconnect_counters_result_t) == 8, "reconnect result alignment");
_Static_assert(offsetof(beluga_core_reconnect_counters_result_t, candidate_state) == 0, "reconnect candidate offset");
_Static_assert(offsetof(beluga_core_reconnect_counters_result_t, decision) == 24, "reconnect decision offset");
_Static_assert(offsetof(beluga_core_reconnect_counters_result_t, reserved) == 28, "reconnect result reserved offset");

static void reconnect_counters_same(beluga_core_reconnect_counters_state_t a,
                                    beluga_core_reconnect_counters_state_t b) {
    assert(a.abi_version == b.abi_version && a.reserved == b.reserved &&
           a.next_outbound == b.next_outbound && a.highest_accepted == b.highest_accepted);
}

static void reconnect_counters_smoke(void) {
    const uint64_t values[] = {0, 1, 2, (UINT64_C(1) << 53) + 1, UINT64_MAX - 1, UINT64_MAX};
    for (unsigned n = 0; n < sizeof(values) / sizeof(values[0]); ++n) {
        for (unsigned h = 0; h < sizeof(values) / sizeof(values[0]); ++h) {
            const beluga_core_reconnect_counters_state_t before = {1, 0, values[n], values[h]};
            beluga_core_reconnect_counters_event_t event = {0, 0, 0};
            beluga_core_reconnect_counters_result_t r = beluga_core_reconnect_counters_step(1, before, event);
            assert(r.decision == (values[n] < UINT64_MAX ? 0U : 1U) && r.reserved == 0);
            assert(r.candidate_state.abi_version == 1 && r.candidate_state.reserved == 0);
            assert(r.candidate_state.next_outbound == (values[n] < UINT64_MAX ? values[n] + 1 : values[n]));
            assert(r.candidate_state.highest_accepted == values[h]);
            for (unsigned s = 0; s < sizeof(values) / sizeof(values[0]); ++s) {
                event = (beluga_core_reconnect_counters_event_t){1, 0, values[s]};
                r = beluga_core_reconnect_counters_step(1, before, event);
                assert(r.decision == (values[s] > values[h] ? 0U : 2U) && r.reserved == 0);
                assert(r.candidate_state.next_outbound == values[n]);
                assert(r.candidate_state.highest_accepted == (values[s] > values[h] ? values[s] : values[h]));
            }
        }
    }
    const beluga_core_reconnect_counters_state_t before = {1, 0, 0, UINT64_MAX - 1};
    beluga_core_reconnect_counters_event_t event = {0, 0, 0};
    beluga_core_reconnect_counters_result_t r = beluga_core_reconnect_counters_step(1, before, event);
    assert(r.decision == 0 && r.candidate_state.next_outbound == 1);
    reconnect_counters_same(before, (beluga_core_reconnect_counters_state_t){1, 0, 0, UINT64_MAX - 1});
    const uint32_t bad[] = {2, UINT32_MAX};
    for (unsigned i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        r = beluga_core_reconnect_counters_step(bad[i], before, event);
        assert(r.decision == 3 && r.reserved == 0); reconnect_counters_same(r.candidate_state, before);
        beluga_core_reconnect_counters_state_t malformed = before;
        malformed.abi_version = bad[i];
        r = beluga_core_reconnect_counters_step(1, malformed, event);
        assert(r.decision == 3 && r.reserved == 0); reconnect_counters_same(r.candidate_state, malformed);
        malformed = before; malformed.reserved = bad[i];
        r = beluga_core_reconnect_counters_step(1, malformed, event);
        assert(r.decision == 3 && r.reserved == 0); reconnect_counters_same(r.candidate_state, malformed);
        event.reserved = bad[i];
        r = beluga_core_reconnect_counters_step(1, before, event);
        assert(r.decision == 3 && r.reserved == 0); reconnect_counters_same(r.candidate_state, before);
        event = (beluga_core_reconnect_counters_event_t){bad[i], 0, 0};
        r = beluga_core_reconnect_counters_step(1, before, event);
        assert(r.decision == 3 && r.reserved == 0); reconnect_counters_same(r.candidate_state, before);
        event = (beluga_core_reconnect_counters_event_t){0, 0, UINT64_MAX};
        r = beluga_core_reconnect_counters_step(1, before, event);
        assert(r.decision == 3 && r.reserved == 0); reconnect_counters_same(r.candidate_state, before);
        event = (beluga_core_reconnect_counters_event_t){0, 0, 0};
    }
    puts("BelugaCore C reconnect counters ABI PASS: exact layouts, zero/MAX, strict admission and unchanged refusal");
}

/* Actual linked pairing-commit contract: layouts and copied plans, not native effects. */
_Static_assert(sizeof(beluga_core_pairing_commit_state_t) == 24, "commit state size");
_Static_assert(_Alignof(beluga_core_pairing_commit_state_t) == 4, "commit state alignment");
_Static_assert(offsetof(beluga_core_pairing_commit_state_t, abi_version) == 0, "commit state ABI offset");
_Static_assert(offsetof(beluga_core_pairing_commit_state_t, reserved) == 4, "commit state reserved offset");
_Static_assert(offsetof(beluga_core_pairing_commit_state_t, local_role) == 8, "commit role offset");
_Static_assert(offsetof(beluga_core_pairing_commit_state_t, pairing_state) == 12, "commit phase offset");
_Static_assert(offsetof(beluga_core_pairing_commit_state_t, recovery_phase) == 16, "commit recovery offset");
_Static_assert(offsetof(beluga_core_pairing_commit_state_t, reserved_tail) == 20, "commit state tail offset");
_Static_assert(sizeof(beluga_core_pairing_commit_event_t) == 16, "commit event size");
_Static_assert(_Alignof(beluga_core_pairing_commit_event_t) == 4, "commit event alignment");
_Static_assert(offsetof(beluga_core_pairing_commit_event_t, opcode) == 0, "commit opcode offset");
_Static_assert(offsetof(beluga_core_pairing_commit_event_t, reserved) == 4, "commit event reserved offset");
_Static_assert(offsetof(beluga_core_pairing_commit_event_t, commit_id_matches) == 8, "commit UUID fact offset");
_Static_assert(offsetof(beluga_core_pairing_commit_event_t, reserved_tail) == 12, "commit event tail offset");
_Static_assert(sizeof(beluga_core_pairing_commit_result_t) == 40, "commit result size");
_Static_assert(_Alignof(beluga_core_pairing_commit_result_t) == 4, "commit result alignment");
_Static_assert(offsetof(beluga_core_pairing_commit_result_t, candidate_state) == 0, "commit candidate offset");
_Static_assert(offsetof(beluga_core_pairing_commit_result_t, decision) == 24, "commit decision offset");
_Static_assert(offsetof(beluga_core_pairing_commit_result_t, action) == 28, "commit action offset");
_Static_assert(offsetof(beluga_core_pairing_commit_result_t, auth_phase) == 32, "commit authentication offset");
_Static_assert(offsetof(beluga_core_pairing_commit_result_t, reserved) == 36, "commit result reserved offset");

static beluga_core_pairing_commit_state_t pc_state(uint32_t role, uint32_t phase, uint32_t cache) {
    return (beluga_core_pairing_commit_state_t){1, 0, role, phase, cache, 0};
}
static void pc_check(beluga_core_pairing_commit_state_t before, uint32_t opcode, uint32_t exact,
    uint32_t phase, uint32_t cache, uint32_t decision, uint32_t action, uint32_t auth) {
    const beluga_core_pairing_commit_event_t event = {opcode, 0, exact, 0};
    beluga_core_pairing_commit_state_t expected = before;
    expected.pairing_state = phase; expected.recovery_phase = cache;
    const beluga_core_pairing_commit_result_t actual = beluga_core_pairing_commit_step(1, before, event);
    assert(memcmp(&actual.candidate_state, &expected, sizeof(expected)) == 0);
    assert(actual.decision == decision && actual.action == action && actual.auth_phase == auth && actual.reserved == 0);
}
static void pc_invalid(uint32_t abi, beluga_core_pairing_commit_state_t before,
    beluga_core_pairing_commit_event_t event) {
    const beluga_core_pairing_commit_result_t result = beluga_core_pairing_commit_step(abi, before, event);
    assert(result.decision == 4 && result.action == 0 && result.auth_phase == 0 && result.reserved == 0);
    assert(memcmp(&result.candidate_state, &before, sizeof(before)) == 0);
}
static void pairing_commit_smoke(void) {
    /* Literal expected original-method branches; these do not call Rust helpers. */
    pc_check(pc_state(0, 0, 0), 0, 0, 0, 0, 0, 2, 0);
    pc_check(pc_state(1, 0, 0), 0, 0, 0, 0, 0, 1, 0);
    pc_check(pc_state(0, 1, 0), 0, 0, 1, 0, 0, 1, 0);
    pc_check(pc_state(1, 2, 0), 0, 0, 2, 0, 0, 4, 0);
    pc_check(pc_state(1, 3, 0), 0, 0, 3, 0, 0, 0, 0);
    pc_check(pc_state(0, 1, 4), 0, 0, 1, 4, 0, 3, 0);
    pc_check(pc_state(0, 0, 0), 1, 0, 0, 1, 0, 5, 0);
    pc_check(pc_state(0, 0, 1), 1, 0, 0, 1, 0, 3, 0);
    pc_check(pc_state(0, 0, 4), 1, 0, 0, 4, 1, 0, 0);
    pc_check(pc_state(1, 0, 4), 2, 0, 1, 2, 0, 6, 1);
    pc_check(pc_state(1, 1, 4), 2, 0, 1, 4, 0, 3, 1);
    pc_check(pc_state(1, 2, 4), 2, 0, 2, 4, 1, 0, 0);
    pc_check(pc_state(0, 0, 3), 3, 0, 2, 0, 0, 0, 2);
    pc_check(pc_state(0, 2, 3), 3, 0, 2, 3, 0, 0, 2);
    pc_check(pc_state(0, 3, 4), 3, 0, 3, 4, 0, 0, 2);
    pc_check(pc_state(0, 2, 0), 4, 0, 2, 3, 0, 7, 0);
    pc_check(pc_state(0, 2, 3), 4, 0, 2, 3, 0, 3, 0);
    pc_check(pc_state(0, 3, 0), 4, 0, 3, 0, 0, 7, 0);
    pc_check(pc_state(0, 3, 3), 4, 0, 3, 3, 1, 0, 0);
    pc_check(pc_state(0, 2, 3), 5, 1, 2, 3, 0, 0, 0);
    pc_check(pc_state(0, 2, 3), 5, 0, 2, 3, 1, 0, 0);
    pc_check(pc_state(0, 3, 0), 5, 1, 3, 0, 0, 0, 0);
    pc_check(pc_state(1, 3, 4), 6, 0, 3, 4, 0, 3, 3);
    pc_check(pc_state(1, 3, 0), 6, 0, 3, 0, 2, 0, 3);
    pc_check(pc_state(1, 3, 3), 6, 0, 3, 3, 2, 0, 3);
    pc_check(pc_state(1, 1, 2), 6, 0, 3, 4, 0, 8, 3);
    pc_check(pc_state(1, 0, 0), 6, 0, 0, 0, 1, 0, 0);
    pc_check(pc_state(0, 2, 3), 7, 0, 3, 0, 0, 0, 4);
    pc_check(pc_state(0, 3, 4), 7, 0, 3, 0, 0, 0, 4);
    pc_check(pc_state(1, 1, 2), 8, 0, 1, 2, 0, 9, 0);
    pc_check(pc_state(0, 3, 3), 8, 0, 3, 3, 3, 0, 0);
    pc_check(pc_state(1, 0, 0), 8, 0, 0, 0, 0, 0, 0);
    const beluga_core_pairing_commit_state_t before = pc_state(1, 3, 4);
    const beluga_core_pairing_commit_event_t event = {6, 0, 0, 0};
    for (uint32_t i = 0; i < 3; ++i) {
        const uint32_t bad = i == 0 ? 0 : i == 1 ? 2 : UINT32_MAX;
        pc_invalid(bad, before, event);
        beluga_core_pairing_commit_state_t raw = before; raw.abi_version = bad;
        pc_invalid(1, raw, event);
    }
    for (uint32_t bit = 0; bit < 32; ++bit) {
        beluga_core_pairing_commit_state_t raw = before; raw.reserved = UINT32_C(1) << bit;
        pc_invalid(1, raw, event); raw = before; raw.reserved_tail = UINT32_C(1) << bit;
        pc_invalid(1, raw, event);
        beluga_core_pairing_commit_event_t input = event; input.reserved = UINT32_C(1) << bit;
        pc_invalid(1, before, input); input = event; input.reserved_tail = UINT32_C(1) << bit;
        pc_invalid(1, before, input);
    }
    beluga_core_pairing_commit_state_t raw = before; raw.local_role = 2; pc_invalid(1, raw, event);
    raw = before; raw.pairing_state = 4; pc_invalid(1, raw, event);
    raw = before; raw.recovery_phase = 5; pc_invalid(1, raw, event);
    pc_invalid(1, before, (beluga_core_pairing_commit_event_t){9, 0, 0, 0});
    pc_invalid(1, before, (beluga_core_pairing_commit_event_t){5, 0, 2, 0});
    pc_invalid(1, before, (beluga_core_pairing_commit_event_t){6, 0, 1, 0});
    puts("BelugaCore C pairing commit ABI PASS: exact layouts, phase plans, auth ordering and unchanged refusal");
}
_Static_assert(sizeof(beluga_core_supported_player_arbitration_input_t) == 20, "arbitration input size");
_Static_assert(_Alignof(beluga_core_supported_player_arbitration_input_t) == 4, "arbitration input alignment");
_Static_assert(offsetof(beluga_core_supported_player_arbitration_input_t, abi_version) == 0, "arbitration input ABI offset");
_Static_assert(offsetof(beluga_core_supported_player_arbitration_input_t, selected_source) == 4, "arbitration selected offset");
_Static_assert(offsetof(beluga_core_supported_player_arbitration_input_t, browser_observation) == 8, "arbitration browser offset");
_Static_assert(offsetof(beluga_core_supported_player_arbitration_input_t, music_observation) == 12, "arbitration Music offset");
_Static_assert(offsetof(beluga_core_supported_player_arbitration_input_t, reserved) == 16, "arbitration input reserved offset");
_Static_assert(sizeof(beluga_core_supported_player_arbitration_output_t) == 16, "arbitration output size");
_Static_assert(_Alignof(beluga_core_supported_player_arbitration_output_t) == 4, "arbitration output alignment");
_Static_assert(offsetof(beluga_core_supported_player_arbitration_output_t, abi_version) == 0, "arbitration output ABI offset");
_Static_assert(offsetof(beluga_core_supported_player_arbitration_output_t, action) == 4, "arbitration action offset");
_Static_assert(offsetof(beluga_core_supported_player_arbitration_output_t, primary_or_hold) == 8, "arbitration primary/hold offset");
_Static_assert(offsetof(beluga_core_supported_player_arbitration_output_t, reserved) == 12, "arbitration output reserved offset");

static void supported_player_arbitration_smoke(void) {
    /* Frozen native-reference rows: selected/browser/Music/action/source-or-hold. */
    const uint32_t literals[48][5] = {
        {0,0,0,2,0}, {0,0,1,2,2}, {0,0,2,2,2}, {0,0,3,1,0},
        {0,1,0,2,1}, {0,1,1,2,1}, {0,1,2,2,2}, {0,1,3,1,0},
        {0,2,0,2,1}, {0,2,1,2,1}, {0,2,2,2,1}, {0,2,3,1,0},
        {0,3,0,1,0}, {0,3,1,1,0}, {0,3,2,1,0}, {0,3,3,1,0},
        {1,0,0,2,0}, {1,0,1,2,2}, {1,0,2,2,2}, {1,0,3,1,1},
        {1,1,0,2,1}, {1,1,1,2,1}, {1,1,2,2,2}, {1,1,3,1,1},
        {1,2,0,2,1}, {1,2,1,2,1}, {1,2,2,2,1}, {1,2,3,1,1},
        {1,3,0,1,1}, {1,3,1,1,1}, {1,3,2,1,1}, {1,3,3,1,1},
        {2,0,0,2,0}, {2,0,1,2,2}, {2,0,2,2,2}, {2,0,3,1,2},
        {2,1,0,2,1}, {2,1,1,2,2}, {2,1,2,2,2}, {2,1,3,1,2},
        {2,2,0,2,1}, {2,2,1,2,1}, {2,2,2,2,2}, {2,2,3,1,2},
        {2,3,0,1,2}, {2,3,1,1,2}, {2,3,2,1,2}, {2,3,3,1,2}
    };
    const uint32_t invalids[5][3] = {
        {0,2,UINT32_MAX}, {3,4,UINT32_MAX}, {4,5,UINT32_MAX},
        {4,5,UINT32_MAX}, {1,2,UINT32_MAX}
    };
    size_t invalid_attempts = 0;
    for (size_t row = 0; row < 48; ++row) {
        const uint32_t *literal = literals[row];
        const beluga_core_supported_player_arbitration_input_t input = {
            1, literal[0], literal[1], literal[2], 0
        };
        const beluga_core_supported_player_arbitration_output_t output =
            beluga_core_supported_player_arbitrate(input);
        assert(output.abi_version == 1 && output.action == literal[3]);
        assert(output.primary_or_hold == literal[4] && output.reserved == 0);
        for (size_t field = 0; field < 5; ++field) {
            for (size_t bad = 0; bad < 3; ++bad) {
                beluga_core_supported_player_arbitration_input_t raw = input;
                switch (field) {
                    case 0: raw.abi_version = invalids[field][bad]; break;
                    case 1: raw.selected_source = invalids[field][bad]; break;
                    case 2: raw.browser_observation = invalids[field][bad]; break;
                    case 3: raw.music_observation = invalids[field][bad]; break;
                    case 4: raw.reserved = invalids[field][bad]; break;
                    default: assert(0); break;
                }
                const beluga_core_supported_player_arbitration_output_t refused =
                    beluga_core_supported_player_arbitrate(raw);
                assert(refused.abi_version == 1 && refused.action == 0);
                assert(refused.primary_or_hold == 0 && refused.reserved == 0);
                ++invalid_attempts;
            }
        }
        assert(input.abi_version == 1 && input.selected_source == literal[0]);
        assert(input.browser_observation == literal[1] && input.music_observation == literal[2]);
        assert(input.reserved == 0);
    }
    assert(invalid_attempts == 720);
    puts("BelugaCore C supported player arbitration ABI PASS: exact layouts, 48 literal choices and 720 closed-field refusals");
}

_Static_assert(sizeof(beluga_core_availability_retry_state_t) == 16, "availability state size");
_Static_assert(_Alignof(beluga_core_availability_retry_state_t) == 4, "availability state alignment");
_Static_assert(offsetof(beluga_core_availability_retry_state_t, abi_version) == 0, "availability state ABI offset");
_Static_assert(offsetof(beluga_core_availability_retry_state_t, next_delay_seconds) == 4, "availability delay offset");
_Static_assert(offsetof(beluga_core_availability_retry_state_t, has_validated_connection) == 8, "availability validation offset");
_Static_assert(offsetof(beluga_core_availability_retry_state_t, reserved) == 12, "availability state reserved offset");
_Static_assert(sizeof(beluga_core_availability_retry_event_t) == 8, "availability event size");
_Static_assert(_Alignof(beluga_core_availability_retry_event_t) == 4, "availability event alignment");
_Static_assert(offsetof(beluga_core_availability_retry_event_t, opcode) == 0, "availability event opcode offset");
_Static_assert(offsetof(beluga_core_availability_retry_event_t, reserved) == 4, "availability event reserved offset");
_Static_assert(sizeof(beluga_core_availability_retry_result_t) == 32, "availability result size");
_Static_assert(_Alignof(beluga_core_availability_retry_result_t) == 4, "availability result alignment");
_Static_assert(offsetof(beluga_core_availability_retry_result_t, candidate_state) == 0, "availability result state offset");
_Static_assert(offsetof(beluga_core_availability_retry_result_t, decision) == 16, "availability result decision offset");
_Static_assert(offsetof(beluga_core_availability_retry_result_t, became_validated) == 20, "availability result became offset");
_Static_assert(offsetof(beluga_core_availability_retry_result_t, retry_delay_seconds) == 24, "availability result delay offset");
_Static_assert(offsetof(beluga_core_availability_retry_result_t, reserved) == 28, "availability result reserved offset");

static void availability_retry_assert_state(
    beluga_core_availability_retry_state_t actual,
    beluga_core_availability_retry_state_t expected) {
    assert(actual.abi_version == expected.abi_version);
    assert(actual.next_delay_seconds == expected.next_delay_seconds);
    assert(actual.has_validated_connection == expected.has_validated_connection);
    assert(actual.reserved == expected.reserved);
}

static size_t availability_retry_assert_refused(
    uint32_t abi_version,
    beluga_core_availability_retry_state_t before,
    beluga_core_availability_retry_event_t event) {
    const beluga_core_availability_retry_state_t copied_state = before;
    const beluga_core_availability_retry_event_t copied_event = event;
    const beluga_core_availability_retry_result_t output =
        beluga_core_availability_retry_step(abi_version, before, event);
    availability_retry_assert_state(output.candidate_state, before);
    assert(output.decision == 2 && output.became_validated == 0);
    assert(output.retry_delay_seconds == 0 && output.reserved == 0);
    availability_retry_assert_state(before, copied_state);
    assert(event.opcode == copied_event.opcode && event.reserved == copied_event.reserved);
    return 1;
}

static void availability_retry_smoke(void) {
    /* Frozen original rows: before delay/validated, opcode, candidate delay/validated,
     * decision, became validated, original retry delay. No expected reducer call. */
    const uint32_t literals[14][8] = {
        {1,0,0,1,1,0,1,0}, {1,0,1,2,0,1,0,1},
        {2,0,0,1,1,0,1,0}, {2,0,1,4,0,1,0,2},
        {4,0,0,1,1,0,1,0}, {4,0,1,8,0,1,0,4},
        {8,0,0,1,1,0,1,0}, {8,0,1,16,0,1,0,8},
        {16,0,0,1,1,0,1,0}, {16,0,1,30,0,1,0,16},
        {30,0,0,1,1,0,1,0}, {30,0,1,30,0,1,0,30},
        {1,1,0,1,1,0,0,0}, {1,1,1,2,0,1,0,1}
    };
    const uint32_t invalids[7][4] = {
        {0,2,UINT32_MAX,0}, {0,2,UINT32_MAX,0}, {0,3,32,UINT32_MAX},
        {2,UINT32_MAX,0,0}, {1,UINT32_MAX,0,0},
        {2,UINT32_MAX,0,0}, {1,UINT32_MAX,0,0}
    };
    const size_t invalid_counts[7] = {3,3,4,2,2,2,2};
    size_t refused_attempts = 0;
    for (size_t row = 0; row < 14; ++row) {
        const uint32_t *literal = literals[row];
        const beluga_core_availability_retry_state_t before = {1,literal[0],literal[1],0};
        const beluga_core_availability_retry_event_t event = {literal[2],0};
        const beluga_core_availability_retry_result_t output =
            beluga_core_availability_retry_step(1, before, event);
        const beluga_core_availability_retry_state_t expected = {1,literal[3],literal[4],0};
        availability_retry_assert_state(output.candidate_state, expected);
        assert(output.decision == literal[5] && output.became_validated == literal[6]);
        assert(output.retry_delay_seconds == literal[7] && output.reserved == 0);
        for (size_t field = 0; field < 7; ++field) {
            for (size_t bad = 0; bad < invalid_counts[field]; ++bad) {
                uint32_t call_abi = 1;
                beluga_core_availability_retry_state_t raw_state = before;
                beluga_core_availability_retry_event_t raw_event = event;
                const uint32_t value = invalids[field][bad];
                switch (field) {
                    case 0: call_abi = value; break;
                    case 1: raw_state.abi_version = value; break;
                    case 2: raw_state.next_delay_seconds = value; break;
                    case 3: raw_state.has_validated_connection = value; break;
                    case 4: raw_state.reserved = value; break;
                    case 5: raw_event.opcode = value; break;
                    case 6: raw_event.reserved = value; break;
                    default: assert(0); break;
                }
                refused_attempts += availability_retry_assert_refused(call_abi, raw_state, raw_event);
            }
        }
        beluga_core_availability_retry_state_t raw_state = before;
        raw_state.next_delay_seconds = 2;
        raw_state.has_validated_connection = 1;
        refused_attempts += availability_retry_assert_refused(1, raw_state, event);
        raw_state = before;
        raw_state.abi_version = 9;
        raw_state.reserved = 17;
        refused_attempts += availability_retry_assert_refused(0, raw_state,
            (beluga_core_availability_retry_event_t){7,UINT32_MAX});
        availability_retry_assert_state(before,
            (beluga_core_availability_retry_state_t){1,literal[0],literal[1],0});
        assert(event.opcode == literal[2] && event.reserved == 0);
    }
    assert(refused_attempts == 280);
    puts("BelugaCore C availability retry ABI PASS: exact layouts, 14 literal transitions and 280 unchanged refusals");
}

/* PRIVATE, UNCOMPILED, UNEXECUTED additive fragment for the existing C smoke.
 * Include after BelugaCore.h and invoke smoke_batch_a_policies() from its main.
 * All calls use the six actual production exports, not a shadow reducer.
 */
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifdef NDEBUG
#error "Batch A smoke requires enabled ordinary assertions"
#endif

#define BA_LAYOUT(T, S, A) _Static_assert(sizeof(T) == (S), #T " size"); _Static_assert(_Alignof(T) == (A), #T " alignment")
#define BA_OFFSET(T, F, N) _Static_assert(offsetof(T, F) == (N), #T "." #F " offset")
BA_LAYOUT(beluga_core_safe_output_retry_config_t, 32, 8);
BA_OFFSET(beluga_core_safe_output_retry_config_t, abi_version, 0);
BA_OFFSET(beluga_core_safe_output_retry_config_t, reserved, 4);
BA_OFFSET(beluga_core_safe_output_retry_config_t, maximum_failed_attempt_count, 8);
BA_OFFSET(beluga_core_safe_output_retry_config_t, maximum_backoff_tick_count, 16);
BA_OFFSET(beluga_core_safe_output_retry_config_t, capped_cooldown_tick_count, 24);
BA_LAYOUT(beluga_core_safe_output_retry_state_t, 56, 8);
BA_OFFSET(beluga_core_safe_output_retry_state_t, abi_version, 0);
BA_OFFSET(beluga_core_safe_output_retry_state_t, reserved, 4);
BA_OFFSET(beluga_core_safe_output_retry_state_t, maximum_failed_attempt_count, 8);
BA_OFFSET(beluga_core_safe_output_retry_state_t, maximum_backoff_tick_count, 16);
BA_OFFSET(beluga_core_safe_output_retry_state_t, capped_cooldown_tick_count, 24);
BA_OFFSET(beluga_core_safe_output_retry_state_t, failed_attempt_count, 32);
BA_OFFSET(beluga_core_safe_output_retry_state_t, backoff_tick_count, 40);
BA_OFFSET(beluga_core_safe_output_retry_state_t, cooldown_tick_count, 48);
BA_LAYOUT(beluga_core_safe_output_retry_result_t, 64, 8);
BA_OFFSET(beluga_core_safe_output_retry_result_t, state, 0);
BA_OFFSET(beluga_core_safe_output_retry_result_t, status, 56);
BA_OFFSET(beluga_core_safe_output_retry_result_t, tick_decision, 60);
BA_LAYOUT(beluga_core_system_audio_start_facts_t, 32, 4);
BA_OFFSET(beluga_core_system_audio_start_facts_t, abi_version, 0);
BA_OFFSET(beluga_core_system_audio_start_facts_t, reserved, 4);
BA_OFFSET(beluga_core_system_audio_start_facts_t, is_live, 8);
BA_OFFSET(beluga_core_system_audio_start_facts_t, is_paused_for_recovery, 12);
BA_OFFSET(beluga_core_system_audio_start_facts_t, has_source, 16);
BA_OFFSET(beluga_core_system_audio_start_facts_t, has_sink, 20);
BA_OFFSET(beluga_core_system_audio_start_facts_t, has_valid_authorization, 24);
BA_OFFSET(beluga_core_system_audio_start_facts_t, peer_generation_matches, 28);
BA_LAYOUT(beluga_core_system_audio_start_decision_t, 16, 4);
BA_OFFSET(beluga_core_system_audio_start_decision_t, abi_version, 0);
BA_OFFSET(beluga_core_system_audio_start_decision_t, status, 4);
BA_OFFSET(beluga_core_system_audio_start_decision_t, mode, 8);
BA_OFFSET(beluga_core_system_audio_start_decision_t, reserved, 12);
BA_LAYOUT(beluga_core_hosted_call_observation_facts_t, 120, 8);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, abi_version, 0);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, reserved, 4);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, observation_sequence, 8);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, highest_admitted_sequence, 16);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, observation_challenge_present, 24);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, current_challenge_present, 28);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, current_protocol_version, 32);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, observation_challenge_sequence, 40);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, current_challenge_sequence, 48);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, observation_nonce, 56);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, observation_call_epoch_nonce, 72);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, current_nonce, 88);
BA_OFFSET(beluga_core_hosted_call_observation_facts_t, current_call_epoch_nonce, 104);
BA_LAYOUT(beluga_core_hosted_call_evidence_facts_t, 16, 4);
BA_OFFSET(beluga_core_hosted_call_evidence_facts_t, abi_version, 0);
BA_OFFSET(beluga_core_hosted_call_evidence_facts_t, reserved, 4);
BA_OFFSET(beluga_core_hosted_call_evidence_facts_t, active, 8);
BA_OFFSET(beluga_core_hosted_call_evidence_facts_t, armed, 12);
BA_LAYOUT(beluga_core_hosted_call_peer_facts_t, 40, 8);
BA_OFFSET(beluga_core_hosted_call_peer_facts_t, abi_version, 0);
BA_OFFSET(beluga_core_hosted_call_peer_facts_t, reserved, 4);
BA_OFFSET(beluga_core_hosted_call_peer_facts_t, audio_present, 8);
BA_OFFSET(beluga_core_hosted_call_peer_facts_t, challenge_present, 12);
BA_OFFSET(beluga_core_hosted_call_peer_facts_t, audio_generation, 16);
BA_OFFSET(beluga_core_hosted_call_peer_facts_t, challenge_generation, 24);
BA_OFFSET(beluga_core_hosted_call_peer_facts_t, current_generation, 32);
BA_LAYOUT(beluga_core_hosted_call_decision_t, 16, 4);
BA_OFFSET(beluga_core_hosted_call_decision_t, abi_version, 0);
BA_OFFSET(beluga_core_hosted_call_decision_t, status, 4);
BA_OFFSET(beluga_core_hosted_call_decision_t, value, 8);
BA_OFFSET(beluga_core_hosted_call_decision_t, reserved, 12);
#undef BA_LAYOUT
#undef BA_OFFSET

/* Every wrapper invokes actual C once, then checks the caller-owned complete
 * input bytes. All structs are initialized to zero, including copied payloads.
 * Result expectations below are literal/native-reference assertions.
 */
static beluga_core_safe_output_retry_result_t ba_initialize(beluga_core_safe_output_retry_config_t input) {
    const beluga_core_safe_output_retry_config_t before = input;
    const beluga_core_safe_output_retry_result_t result = beluga_core_safe_output_retry_initialize(input);
    assert(memcmp(&input, &before, sizeof(input)) == 0);
    return result;
}
static beluga_core_safe_output_retry_result_t ba_transition(beluga_core_safe_output_retry_state_t input, uint32_t event) {
    const beluga_core_safe_output_retry_state_t before = input;
    const uint32_t before_event = event;
    const beluga_core_safe_output_retry_result_t result = beluga_core_safe_output_retry_transition(input, event);
    assert(memcmp(&input, &before, sizeof(input)) == 0 && event == before_event);
    return result;
}
static beluga_core_system_audio_start_decision_t ba_start(beluga_core_system_audio_start_facts_t input) {
    const beluga_core_system_audio_start_facts_t before = input;
    const beluga_core_system_audio_start_decision_t result = beluga_core_system_audio_start(input);
    assert(memcmp(&input, &before, sizeof(input)) == 0);
    return result;
}
static beluga_core_hosted_call_decision_t ba_observation(beluga_core_hosted_call_observation_facts_t input) {
    const beluga_core_hosted_call_observation_facts_t before = input;
    const beluga_core_hosted_call_decision_t result = beluga_core_hosted_call_observation(input);
    assert(memcmp(&input, &before, sizeof(input)) == 0);
    return result;
}
static beluga_core_hosted_call_decision_t ba_evidence(beluga_core_hosted_call_evidence_facts_t input) {
    const beluga_core_hosted_call_evidence_facts_t before = input;
    const beluga_core_hosted_call_decision_t result = beluga_core_hosted_call_evidence(input);
    assert(memcmp(&input, &before, sizeof(input)) == 0);
    return result;
}
static beluga_core_hosted_call_decision_t ba_peer(beluga_core_hosted_call_peer_facts_t input) {
    const beluga_core_hosted_call_peer_facts_t before = input;
    const beluga_core_hosted_call_decision_t result = beluga_core_hosted_call_peer_generation(input);
    assert(memcmp(&input, &before, sizeof(input)) == 0);
    return result;
}
static beluga_core_safe_output_retry_config_t ba_config(int64_t failed, int64_t backoff, int64_t cooldown) {
    beluga_core_safe_output_retry_config_t x = {0};
    x.abi_version = 1;
    x.maximum_failed_attempt_count = failed;
    x.maximum_backoff_tick_count = backoff;
    x.capped_cooldown_tick_count = cooldown;
    return x;
}
static void ba_retry_counts(beluga_core_safe_output_retry_result_t x, uint32_t status, uint32_t tick,
    int64_t failed, int64_t backoff, int64_t cooldown) {
    assert(x.status == status && x.tick_decision == tick);
    assert(x.state.failed_attempt_count == failed && x.state.backoff_tick_count == backoff
        && x.state.cooldown_tick_count == cooldown);
}
static void ba_retry_config(beluga_core_safe_output_retry_state_t x, int64_t failed, int64_t backoff, int64_t cooldown) {
    assert(x.abi_version == 1 && x.reserved == 0);
    assert(x.maximum_failed_attempt_count == failed && x.maximum_backoff_tick_count == backoff
        && x.capped_cooldown_tick_count == cooldown);
}
static void ba_invalid_retry(beluga_core_safe_output_retry_state_t raw) {
    for (uint32_t event = 1; event <= 3; ++event) {
        const beluga_core_safe_output_retry_result_t x = ba_transition(raw, event);
        assert(x.status == 0 && x.tick_decision == 0);
        assert(memcmp(&x.state, &raw, sizeof(raw)) == 0);
    }
}

static void ba_safe_output_smoke(void) {
    const int64_t requested[] = {INT64_MIN, -9, 0, 1, 2, INT64_MAX};
    const int64_t normalized[] = {1, 1, 1, 1, 2, INT64_MAX};
    for (size_t f = 0; f < 6; ++f) for (size_t b = 0; b < 6; ++b) for (size_t c = 0; c < 6; ++c) {
        const beluga_core_safe_output_retry_result_t x = ba_initialize(ba_config(requested[f], requested[b], requested[c]));
        ba_retry_counts(x, 1, 0, 0, 0, 0);
        ba_retry_config(x.state, normalized[f], normalized[b], normalized[c]);
    }
    const struct { uint32_t event; int64_t failed, backoff, cooldown; uint32_t tick; } trace[] = {
        {1,0,0,0,2}, {2,1,1,0,0}, {1,1,0,0,1}, {1,1,0,0,2}, {2,2,2,0,0},
        {1,2,1,0,1}, {1,2,0,0,1}, {1,2,0,0,2}, {2,3,0,3,0}, {2,3,0,3,0},
        {1,3,0,2,1}, {1,3,0,1,1}, {1,3,0,0,1}, {1,0,0,0,2}, {2,1,1,0,0},
        {3,0,0,0,0}, {1,0,0,0,2}, {3,0,0,0,0}, {1,0,0,0,2}
    };
    beluga_core_safe_output_retry_state_t raw = ba_initialize(ba_config(3,4,3)).state;
    for (size_t i = 0; i < sizeof(trace)/sizeof(trace[0]); ++i) {
        const beluga_core_safe_output_retry_result_t x = ba_transition(raw, trace[i].event);
        ba_retry_counts(x, 1, trace[i].tick, trace[i].failed, trace[i].backoff, trace[i].cooldown);
        ba_retry_config(x.state, 3,4,3);
        raw = x.state;
    }
    const int64_t default_rows[][3] = {{1,1,0},{2,2,0},{3,4,0},{4,8,0},{5,16,0},{6,0,60}};
    raw = ba_initialize(ba_config(6,16,60)).state;
    for (size_t i = 0; i < 6; ++i) {
        const beluga_core_safe_output_retry_result_t x = ba_transition(raw, 2);
        ba_retry_counts(x, 1,0,default_rows[i][0],default_rows[i][1],default_rows[i][2]);
        ba_retry_config(x.state, 6,16,60);
        raw = x.state;
    }
    for (int64_t tick = 0; tick < 60; ++tick) {
        const beluga_core_safe_output_retry_result_t x = ba_transition(raw, 1);
        ba_retry_counts(x, 1,1,6,0,59-tick);
        raw = x.state;
    }
    ba_retry_counts(ba_transition(raw, 1), 1,2,0,0,0);
    raw = ba_initialize(ba_config(1,INT64_MAX,INT64_MAX)).state;
    const beluga_core_safe_output_retry_result_t cap = ba_transition(raw, 2);
    ba_retry_counts(cap, 1,0,1,0,INT64_MAX);
    const beluga_core_safe_output_retry_result_t waited = ba_transition(cap.state, 1);
    ba_retry_counts(waited, 1,1,1,0,INT64_MAX-1);
    const beluga_core_safe_output_retry_result_t retained = ba_transition(waited.state, 2);
    assert(retained.status == 1 && retained.tick_decision == 0);
    assert(memcmp(&retained.state, &waited.state, sizeof(retained.state)) == 0);
    raw = ba_initialize(ba_config(INT64_MAX,INT64_MAX,INT64_MAX)).state;
    raw.failed_attempt_count = INT64_MAX-1;
    ba_retry_counts(ba_transition(raw, 2), 1,0,INT64_MAX,0,INT64_MAX);
    const int64_t prior[] = {30,31,32,64,999,INT64_MAX-2};
    for (size_t i = 0; i < 6; ++i) {
        raw = ba_initialize(ba_config(INT64_MAX,INT64_MAX,5)).state;
        raw.failed_attempt_count = prior[i];
        ba_retry_counts(ba_transition(raw, 2), 1,0,prior[i]+1,INT64_C(1073741824),0);
    }
    raw = ba_initialize(ba_config(1000,7,5)).state;
    raw.failed_attempt_count = 998;
    ba_retry_counts(ba_transition(raw, 2), 1,0,999,7,0);

    const uint32_t envelopes[][2] = {{0,0},{2,0},{UINT32_MAX,0},{1,1},{1,2},{1,UINT32_MAX},{9,17}};
    const beluga_core_safe_output_retry_config_t configs[] = {ba_config(INT64_MIN,-7,INT64_MAX),ba_config(3,4,3)};
    for (size_t i = 0; i < 2; ++i) for (size_t j = 0; j < 7; ++j) {
        beluga_core_safe_output_retry_config_t input = configs[i];
        input.abi_version = envelopes[j][0]; input.reserved = envelopes[j][1];
        beluga_core_safe_output_retry_state_t expected = {0};
        expected.abi_version = input.abi_version; expected.reserved = input.reserved;
        expected.maximum_failed_attempt_count = input.maximum_failed_attempt_count;
        expected.maximum_backoff_tick_count = input.maximum_backoff_tick_count;
        expected.capped_cooldown_tick_count = input.capped_cooldown_tick_count;
        const beluga_core_safe_output_retry_result_t x = ba_initialize(input);
        assert(x.status == 0 && x.tick_decision == 0);
        assert(memcmp(&x.state, &expected, sizeof(expected)) == 0);
    }
    const beluga_core_safe_output_retry_state_t initial = ba_initialize(ba_config(3,4,3)).state;
    const beluga_core_safe_output_retry_state_t pending = ba_transition(initial, 2).state;
    const beluga_core_safe_output_retry_state_t capped = ba_transition(ba_transition(pending, 2).state, 2).state;
    const beluga_core_safe_output_retry_state_t bases[] = {initial,pending,capped};
    const uint32_t unknown_events[] = {0,4,UINT32_MAX};
    const int64_t bad_limits[] = {INT64_MIN,-1,0};
    for (size_t i = 0; i < 3; ++i) {
        for (size_t e = 0; e < 3; ++e) {
            const beluga_core_safe_output_retry_result_t x = ba_transition(bases[i], unknown_events[e]);
            assert(x.status == 0 && x.tick_decision == 0);
            assert(memcmp(&x.state, &bases[i], sizeof(x.state)) == 0);
        }
        beluga_core_safe_output_retry_state_t bad = bases[i];
        bad.abi_version = 0; ba_invalid_retry(bad);
        bad = bases[i]; bad.abi_version = 2; ba_invalid_retry(bad);
        bad = bases[i]; bad.reserved = 1; ba_invalid_retry(bad);
        for (size_t limit = 0; limit < 3; ++limit) {
            bad = bases[i]; bad.maximum_failed_attempt_count = bad_limits[limit]; ba_invalid_retry(bad);
            bad = bases[i]; bad.maximum_backoff_tick_count = bad_limits[limit]; ba_invalid_retry(bad);
            bad = bases[i]; bad.capped_cooldown_tick_count = bad_limits[limit]; ba_invalid_retry(bad);
        }
        bad = bases[i]; bad.failed_attempt_count = -1; ba_invalid_retry(bad);
        bad = bases[i]; bad.failed_attempt_count = 4; ba_invalid_retry(bad);
        bad = bases[i]; bad.backoff_tick_count = -1; ba_invalid_retry(bad);
        bad = bases[i]; bad.backoff_tick_count = 9; ba_invalid_retry(bad);
        bad = bases[i]; bad.cooldown_tick_count = -1; ba_invalid_retry(bad);
        bad = bases[i]; bad.cooldown_tick_count = 4; ba_invalid_retry(bad);
    }
    raw = initial; raw.cooldown_tick_count = 1; ba_invalid_retry(raw);
    raw = pending; raw.cooldown_tick_count = 1; ba_invalid_retry(raw);
    raw = capped; raw.backoff_tick_count = 1; ba_invalid_retry(raw);
    const beluga_core_safe_output_retry_result_t reset = ba_transition(pending, 3);
    ba_retry_counts(reset, 1,0,0,0,0);
    assert(memcmp(&reset.state, &initial, sizeof(initial)) == 0);
    assert(pending.failed_attempt_count == 1 && pending.backoff_tick_count == 1);
    puts("BelugaCore C safe output retry ABI PASS: exact layouts, frozen literal transitions and unchanged refusals");
}

static beluga_core_system_audio_start_facts_t ba_start_input(uint32_t bits) {
    beluga_core_system_audio_start_facts_t x = {0};
    x.abi_version = 1;
    x.is_live = bits & 1; x.is_paused_for_recovery = (bits >> 1) & 1;
    x.has_source = (bits >> 2) & 1; x.has_sink = (bits >> 3) & 1;
    x.has_valid_authorization = (bits >> 4) & 1; x.peer_generation_matches = (bits >> 5) & 1;
    return x;
}
static void ba_assert_start(beluga_core_system_audio_start_decision_t x, uint32_t status, uint32_t mode) {
    assert(x.abi_version == 1 && x.status == status && x.mode == mode && x.reserved == 0);
}
static void ba_system_audio_smoke(void) {
    /* Frozen literal native table, not generated by a production guard. */
    const uint32_t modes[64] = {
        3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        3,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0
    };
    const uint32_t malformed[] = {2,UINT32_MAX};
    for (uint32_t bits = 0; bits < 64; ++bits) {
        const beluga_core_system_audio_start_facts_t base = ba_start_input(bits);
        ba_assert_start(ba_start(base), 1,modes[bits]);
        for (uint32_t field = 0; field < 8; ++field) for (size_t b = 0; b < 2; ++b) {
            beluga_core_system_audio_start_facts_t raw = base;
            switch (field) {
                case 0: raw.abi_version = malformed[b]; break;
                case 1: raw.reserved = malformed[b]; break;
                case 2: raw.is_live = malformed[b]; break;
                case 3: raw.is_paused_for_recovery = malformed[b]; break;
                case 4: raw.has_source = malformed[b]; break;
                case 5: raw.has_sink = malformed[b]; break;
                case 6: raw.has_valid_authorization = malformed[b]; break;
                default: raw.peer_generation_matches = malformed[b]; break;
            }
            ba_assert_start(ba_start(raw), 0,0);
        }
        beluga_core_system_audio_start_facts_t raw = base;
        raw.abi_version = 0; ba_assert_start(ba_start(raw), 0,0);
        raw = base; raw.reserved = 1; ba_assert_start(ba_start(raw), 0,0);
    }
    puts("BelugaCore C system audio start ABI PASS: exact layouts, 64 literal choices and 1152 closed-field refusals");
}

static const uint8_t ba_nonce[16] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
static const uint8_t ba_epoch[16] = {16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1};
static beluga_core_hosted_call_observation_facts_t ba_observation_input(void) {
    beluga_core_hosted_call_observation_facts_t x = {0};
    x.abi_version = 1; x.observation_sequence = 11; x.highest_admitted_sequence = 10;
    x.observation_challenge_present = 1; x.current_challenge_present = 1;
    x.current_protocol_version = 3; x.observation_challenge_sequence = 7; x.current_challenge_sequence = 7;
    memcpy(x.observation_nonce,ba_nonce,16); memcpy(x.current_nonce,ba_nonce,16);
    memcpy(x.observation_call_epoch_nonce,ba_epoch,16); memcpy(x.current_call_epoch_nonce,ba_epoch,16);
    return x;
}
static void ba_assert_hosted(beluga_core_hosted_call_decision_t x, uint32_t status, uint32_t value) {
    assert(x.abi_version == 1 && x.status == status && x.value == value && x.reserved == 0);
}
static beluga_core_hosted_call_peer_facts_t ba_peer_input(uint32_t audio_present, uint64_t audio,
    uint32_t challenge_present, uint64_t challenge, uint64_t current) {
    beluga_core_hosted_call_peer_facts_t x = {0};
    x.abi_version = 1; x.audio_present = audio_present; x.challenge_present = challenge_present;
    x.audio_generation = audio; x.challenge_generation = challenge; x.current_generation = current;
    return x;
}
static void ba_hosted_smoke(void) {
    const struct { uint64_t sequence, highest; uint32_t value; } watermarks[] = {
        {0,0,0},{1,0,1},{10,10,0},{11,10,1},{10,11,0},{UINT64_MAX,0,1},{0,UINT64_MAX,0},
        {UINT64_MAX,UINT64_MAX-1,1},{UINT64_MAX,UINT64_MAX,0},{UINT64_MAX-1,UINT64_MAX,0}
    };
    for (size_t i = 0; i < 10; ++i) {
        beluga_core_hosted_call_observation_facts_t x = ba_observation_input();
        x.observation_sequence = watermarks[i].sequence; x.highest_admitted_sequence = watermarks[i].highest;
        ba_assert_hosted(ba_observation(x), 1,watermarks[i].value);
    }
    const int64_t versions[] = {INT64_MIN,-1,0,1,2,3,4,INT64_MAX};
    const uint32_t version_values[] = {0,0,0,0,0,1,0,0};
    for (size_t i = 0; i < 8; ++i) {
        beluga_core_hosted_call_observation_facts_t x = ba_observation_input();
        x.current_protocol_version = versions[i]; ba_assert_hosted(ba_observation(x), 1,version_values[i]);
    }
    const uint64_t sequences[] = {0,1,UINT64_MAX};
    const uint32_t sequence_values[] = {0,1,1};
    for (size_t i = 0; i < 3; ++i) {
        beluga_core_hosted_call_observation_facts_t x = ba_observation_input();
        x.observation_challenge_sequence = sequences[i]; x.current_challenge_sequence = sequences[i];
        ba_assert_hosted(ba_observation(x), 1,sequence_values[i]);
    }
    const uint32_t absent[][2] = {{0,0},{0,1},{1,0}};
    for (size_t i = 0; i < 3; ++i) {
        beluga_core_hosted_call_observation_facts_t x = ba_observation_input();
        x.observation_challenge_present = absent[i][0]; x.current_challenge_present = absent[i][1];
        x.current_protocol_version = INT64_MIN; x.current_challenge_sequence = UINT64_MAX;
        ba_assert_hosted(ba_observation(x), 1,0); /* Present flags absent: payload ignored, accepted refusal. */
    }
    beluga_core_hosted_call_observation_facts_t x = ba_observation_input();
    memset(x.observation_nonce,0,16); memset(x.current_nonce,0,16); ba_assert_hosted(ba_observation(x), 1,0);
    x = ba_observation_input(); memset(x.observation_call_epoch_nonce,0,16); memset(x.current_call_epoch_nonce,0,16);
    ba_assert_hosted(ba_observation(x), 1,0);
    x = ba_observation_input(); memcpy(x.observation_call_epoch_nonce,ba_nonce,16); memcpy(x.current_call_epoch_nonce,ba_nonce,16);
    ba_assert_hosted(ba_observation(x), 1,0);
    x = ba_observation_input(); x.observation_challenge_sequence = 6; ba_assert_hosted(ba_observation(x), 1,0);
    for (size_t byte = 0; byte < 16; ++byte) for (uint32_t field = 0; field < 4; ++field) {
        x = ba_observation_input();
        switch (field) {
            case 0: x.observation_nonce[byte] ^= 0x80; break;
            case 1: x.observation_call_epoch_nonce[byte] ^= 0x80; break;
            case 2: x.current_nonce[byte] ^= 0x80; break;
            default: x.current_call_epoch_nonce[byte] ^= 0x80; break;
        }
        ba_assert_hosted(ba_observation(x), 1,0);
    }
    const uint32_t malformed[] = {2,UINT32_MAX};
    for (uint32_t field = 0; field < 4; ++field) for (size_t b = 0; b < 2; ++b) {
        x = ba_observation_input();
        switch (field) {
            case 0: x.abi_version = malformed[b]; break;
            case 1: x.reserved = malformed[b]; break;
            case 2: x.observation_challenge_present = malformed[b]; break;
            default: x.current_challenge_present = malformed[b]; break;
        }
        ba_assert_hosted(ba_observation(x), 0,0);
    }
    x = ba_observation_input(); x.abi_version = 0; ba_assert_hosted(ba_observation(x), 0,0);
    x = ba_observation_input(); x.reserved = 1; ba_assert_hosted(ba_observation(x), 0,0);
    const uint32_t evidence_rows[][3] = {{0,0,1},{0,1,2},{1,0,3},{1,1,0}};
    for (size_t i = 0; i < 4; ++i) {
        beluga_core_hosted_call_evidence_facts_t e = {0};
        e.abi_version = 1; e.active = evidence_rows[i][0]; e.armed = evidence_rows[i][1];
        ba_assert_hosted(ba_evidence(e), 1,evidence_rows[i][2]);
        for (uint32_t field = 0; field < 4; ++field) for (size_t b = 0; b < 2; ++b) {
            beluga_core_hosted_call_evidence_facts_t bad = e;
            switch (field) {
                case 0: bad.abi_version = malformed[b]; break;
                case 1: bad.reserved = malformed[b]; break;
                case 2: bad.active = malformed[b]; break;
                default: bad.armed = malformed[b]; break;
            }
            ba_assert_hosted(ba_evidence(bad), 0,0);
        }
        beluga_core_hosted_call_evidence_facts_t bad = e;
        bad.abi_version = 0; ba_assert_hosted(ba_evidence(bad), 0,0);
        bad = e; bad.reserved = 1; ba_assert_hosted(ba_evidence(bad), 0,0);
    }
    const struct { uint32_t ap; uint64_t a; uint32_t cp; uint64_t c, current; uint32_t value; } peers[] = {
        {0,0,0,0,0,0},{1,0,1,0,0,0},{0,0,1,7,7,0},{1,7,0,0,7,0},
        {1,6,1,7,7,0},{1,7,1,6,7,0},{1,7,1,7,7,1},{1,1,1,1,1,1},
        {1,UINT64_MAX,1,UINT64_MAX,UINT64_MAX,1},{1,UINT64_MAX-1,1,UINT64_MAX,UINT64_MAX,0},
        {1,0,1,7,7,0},{1,7,1,0,7,0}
    };
    for (size_t i = 0; i < 12; ++i)
        ba_assert_hosted(ba_peer(ba_peer_input(peers[i].ap,peers[i].a,peers[i].cp,peers[i].c,peers[i].current)), 1,peers[i].value);
    beluga_core_hosted_call_peer_facts_t absent_payload = ba_peer_input(0,UINT64_MAX,0,UINT64_MAX,7);
    ba_assert_hosted(ba_peer(absent_payload), 1,0);
    const beluga_core_hosted_call_peer_facts_t peer_bases[] = {ba_peer_input(1,7,1,7,7),ba_peer_input(0,0,0,0,7),ba_peer_input(1,0,1,0,0)};
    for (size_t i = 0; i < 3; ++i) {
        for (uint32_t field = 0; field < 4; ++field) for (size_t b = 0; b < 2; ++b) {
            beluga_core_hosted_call_peer_facts_t bad = peer_bases[i];
            switch (field) {
                case 0: bad.abi_version = malformed[b]; break;
                case 1: bad.reserved = malformed[b]; break;
                case 2: bad.audio_present = malformed[b]; break;
                default: bad.challenge_present = malformed[b]; break;
            }
            ba_assert_hosted(ba_peer(bad), 0,0);
        }
        beluga_core_hosted_call_peer_facts_t bad = peer_bases[i];
        bad.abi_version = 0; ba_assert_hosted(ba_peer(bad), 0,0);
        bad = peer_bases[i]; bad.reserved = 1; ba_assert_hosted(ba_peer(bad), 0,0);
    }
    puts("BelugaCore C hosted call ABI PASS: exact layouts, strict watermark and generation identity, unchanged refusals");
}

static void smoke_batch_a_policies(void) {
    ba_safe_output_smoke();
    ba_system_audio_smoke();
    ba_hosted_smoke();
}


/* Display admission smoke: copied values only; no native display IO. */
_Static_assert(sizeof(beluga_core_display_requirement_facts_t) == 64, "display RequirementInput size");
_Static_assert(_Alignof(beluga_core_display_requirement_facts_t) == 8, "display RequirementInput alignment");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, abi_version) == 0, "display RequirementInput.abi_version offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, reserved) == 4, "display RequirementInput.reserved offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, required_vendor_id) == 8, "display RequirementInput.required_vendor_id offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, required_product_id) == 12, "display RequirementInput.required_product_id offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, required_serial_number) == 16, "display RequirementInput.required_serial_number offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, requires_sole_main_display) == 20, "display RequirementInput.requires_sole_main_display offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, display_id) == 24, "display RequirementInput.display_id offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, observed_vendor_id) == 28, "display RequirementInput.observed_vendor_id offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, observed_product_id) == 32, "display RequirementInput.observed_product_id offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, observed_serial_number) == 36, "display RequirementInput.observed_serial_number offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, is_online) == 40, "display RequirementInput.is_online offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, is_active) == 44, "display RequirementInput.is_active offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, main_display_id) == 48, "display RequirementInput.main_display_id offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, sole_online_display_id) == 52, "display RequirementInput.sole_online_display_id offset");
_Static_assert(offsetof(beluga_core_display_requirement_facts_t, online_display_count) == 56, "display RequirementInput.online_display_count offset");
_Static_assert(sizeof(beluga_core_display_boolean_decision_t) == 16, "display BooleanOutput size");
_Static_assert(_Alignof(beluga_core_display_boolean_decision_t) == 4, "display BooleanOutput alignment");
_Static_assert(offsetof(beluga_core_display_boolean_decision_t, abi_version) == 0, "display BooleanOutput.abi_version offset");
_Static_assert(offsetof(beluga_core_display_boolean_decision_t, status) == 4, "display BooleanOutput.status offset");
_Static_assert(offsetof(beluga_core_display_boolean_decision_t, value) == 8, "display BooleanOutput.value offset");
_Static_assert(offsetof(beluga_core_display_boolean_decision_t, reserved) == 12, "display BooleanOutput.reserved offset");
_Static_assert(sizeof(beluga_core_source_dimension_kind_facts_t) == 16, "display KindInput size");
_Static_assert(_Alignof(beluga_core_source_dimension_kind_facts_t) == 4, "display KindInput alignment");
_Static_assert(offsetof(beluga_core_source_dimension_kind_facts_t, abi_version) == 0, "display KindInput.abi_version offset");
_Static_assert(offsetof(beluga_core_source_dimension_kind_facts_t, reserved) == 4, "display KindInput.reserved offset");
_Static_assert(offsetof(beluga_core_source_dimension_kind_facts_t, vendor_id) == 8, "display KindInput.vendor_id offset");
_Static_assert(offsetof(beluga_core_source_dimension_kind_facts_t, product_id) == 12, "display KindInput.product_id offset");
_Static_assert(sizeof(beluga_core_source_dimension_kind_decision_t) == 16, "display KindOutput size");
_Static_assert(_Alignof(beluga_core_source_dimension_kind_decision_t) == 4, "display KindOutput alignment");
_Static_assert(offsetof(beluga_core_source_dimension_kind_decision_t, abi_version) == 0, "display KindOutput.abi_version offset");
_Static_assert(offsetof(beluga_core_source_dimension_kind_decision_t, status) == 4, "display KindOutput.status offset");
_Static_assert(offsetof(beluga_core_source_dimension_kind_decision_t, kind) == 8, "display KindOutput.kind offset");
_Static_assert(offsetof(beluga_core_source_dimension_kind_decision_t, reserved) == 12, "display KindOutput.reserved offset");
_Static_assert(sizeof(beluga_core_source_dimensions_facts_t) == 88, "display SourceInput size");
_Static_assert(_Alignof(beluga_core_source_dimensions_facts_t) == 8, "display SourceInput alignment");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, abi_version) == 0, "display SourceInput.abi_version offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, reserved) == 4, "display SourceInput.reserved offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, vendor_id) == 8, "display SourceInput.vendor_id offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, product_id) == 12, "display SourceInput.product_id offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, logical_width) == 16, "display SourceInput.logical_width offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, logical_height) == 24, "display SourceInput.logical_height offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, core_graphics_logical_width) == 32, "display SourceInput.core_graphics_logical_width offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, core_graphics_logical_height) == 40, "display SourceInput.core_graphics_logical_height offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, core_graphics_pixel_width) == 48, "display SourceInput.core_graphics_pixel_width offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, core_graphics_pixel_height) == 56, "display SourceInput.core_graphics_pixel_height offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, filter_content_width) == 64, "display SourceInput.filter_content_width offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, filter_content_height) == 72, "display SourceInput.filter_content_height offset");
_Static_assert(offsetof(beluga_core_source_dimensions_facts_t, point_pixel_scale) == 80, "display SourceInput.point_pixel_scale offset");
_Static_assert(sizeof(beluga_core_source_dimensions_decision_t) == 32, "display SourceOutput size");
_Static_assert(_Alignof(beluga_core_source_dimensions_decision_t) == 8, "display SourceOutput alignment");
_Static_assert(offsetof(beluga_core_source_dimensions_decision_t, abi_version) == 0, "display SourceOutput.abi_version offset");
_Static_assert(offsetof(beluga_core_source_dimensions_decision_t, status) == 4, "display SourceOutput.status offset");
_Static_assert(offsetof(beluga_core_source_dimensions_decision_t, kind) == 8, "display SourceOutput.kind offset");
_Static_assert(offsetof(beluga_core_source_dimensions_decision_t, has_dimensions) == 12, "display SourceOutput.has_dimensions offset");
_Static_assert(offsetof(beluga_core_source_dimensions_decision_t, width) == 16, "display SourceOutput.width offset");
_Static_assert(offsetof(beluga_core_source_dimensions_decision_t, height) == 24, "display SourceOutput.height offset");
_Static_assert(sizeof(beluga_core_source_dimensions_stability_facts_t) == 40, "display StabilityInput size");
_Static_assert(_Alignof(beluga_core_source_dimensions_stability_facts_t) == 8, "display StabilityInput alignment");
_Static_assert(offsetof(beluga_core_source_dimensions_stability_facts_t, abi_version) == 0, "display StabilityInput.abi_version offset");
_Static_assert(offsetof(beluga_core_source_dimensions_stability_facts_t, reserved) == 4, "display StabilityInput.reserved offset");
_Static_assert(offsetof(beluga_core_source_dimensions_stability_facts_t, before_width) == 8, "display StabilityInput.before_width offset");
_Static_assert(offsetof(beluga_core_source_dimensions_stability_facts_t, before_height) == 16, "display StabilityInput.before_height offset");
_Static_assert(offsetof(beluga_core_source_dimensions_stability_facts_t, after_width) == 24, "display StabilityInput.after_width offset");
_Static_assert(offsetof(beluga_core_source_dimensions_stability_facts_t, after_height) == 32, "display StabilityInput.after_height offset");

static double display_f64_bits(uint64_t bits) {
    double value; memcpy(&value, &bits, sizeof(value)); return value;
}
static beluga_core_display_requirement_facts_t display_requirement_input(void) {
    return (beluga_core_display_requirement_facts_t){
        .abi_version=1, .reserved=0, .required_vendor_id=0x6f73, .required_product_id=0x1717,
        .required_serial_number=7, .requires_sole_main_display=1, .display_id=42,
        .observed_vendor_id=0x6f73, .observed_product_id=0x1717, .observed_serial_number=7,
        .is_online=1, .is_active=1, .main_display_id=42, .sole_online_display_id=42,
        .online_display_count=1
    };
}
static beluga_core_source_dimensions_facts_t display_source_input(void) {
    return (beluga_core_source_dimensions_facts_t){
        .abi_version=1, .reserved=0, .vendor_id=0x6f73, .product_id=0x1717,
        .logical_width=390, .logical_height=844, .core_graphics_logical_width=390,
        .core_graphics_logical_height=844, .core_graphics_pixel_width=1170,
        .core_graphics_pixel_height=2532, .filter_content_width=390.0,
        .filter_content_height=844.0, .point_pixel_scale=3.0
    };
}
static void display_expect_requirement(beluga_core_display_requirement_facts_t input,
                                       uint32_t status, uint32_t value) {
    const beluga_core_display_requirement_facts_t before = input;
    const beluga_core_display_boolean_decision_t output = beluga_core_display_requirement_admission(input);
    assert(memcmp(&input, &before, sizeof(input)) == 0);
    assert(output.abi_version == 1 && output.status == status && output.value == value && output.reserved == 0);
}
static void display_expect_kind(beluga_core_source_dimension_kind_facts_t input,
                               uint32_t status, uint32_t kind) {
    const beluga_core_source_dimension_kind_facts_t before = input;
    const beluga_core_source_dimension_kind_decision_t output = beluga_core_source_dimension_kind(input);
    assert(memcmp(&input, &before, sizeof(input)) == 0);
    assert(output.abi_version == 1 && output.status == status && output.kind == kind && output.reserved == 0);
}
static void display_expect_source(beluga_core_source_dimensions_facts_t input,
                                 uint32_t status, uint32_t kind, uint32_t present,
                                 int64_t width, int64_t height) {
    const beluga_core_source_dimensions_facts_t before = input;
    const beluga_core_source_dimensions_decision_t output = beluga_core_source_dimensions(input);
    assert(memcmp(&input, &before, sizeof(input)) == 0);
    assert(output.abi_version == 1 && output.status == status && output.kind == kind &&
           output.has_dimensions == present && output.width == width && output.height == height);
}
static void display_expect_stable(beluga_core_source_dimensions_stability_facts_t input,
                                 uint32_t status, uint32_t value) {
    const beluga_core_source_dimensions_stability_facts_t before = input;
    const beluga_core_display_boolean_decision_t output = beluga_core_source_dimensions_stable(input);
    assert(memcmp(&input, &before, sizeof(input)) == 0);
    assert(output.abi_version == 1 && output.status == status && output.value == value && output.reserved == 0);
}
static void display_admission_smoke(void) {
    /* exact sole main identity */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();

      display_expect_requirement(input, 1, 1); }
    /* required_vendor_id independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.required_vendor_id = 0x00016f73;
      display_expect_requirement(input, 1, 0); }
    /* observed_vendor_id independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.observed_vendor_id = 0x00016f73;
      display_expect_requirement(input, 1, 0); }
    /* required_product_id independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.required_product_id = 0x00011717;
      display_expect_requirement(input, 1, 0); }
    /* observed_product_id independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.observed_product_id = 0x00011717;
      display_expect_requirement(input, 1, 0); }
    /* required_serial_number independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.required_serial_number = 0x00010007;
      display_expect_requirement(input, 1, 0); }
    /* observed_serial_number independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.observed_serial_number = 0x00010007;
      display_expect_requirement(input, 1, 0); }
    /* is_online independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.is_online = 0;
      display_expect_requirement(input, 1, 0); }
    /* is_active independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.is_active = 0;
      display_expect_requirement(input, 1, 0); }
    /* main_display_id independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.main_display_id = 0x0001002a;
      display_expect_requirement(input, 1, 0); }
    /* sole_online_display_id independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.sole_online_display_id = 0x0001002a;
      display_expect_requirement(input, 1, 0); }
    /* display_id independent mismatch */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.display_id = 0x0001002a;
      display_expect_requirement(input, 1, 0); }
    /* exact topology count 0 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.online_display_count = 0;
      display_expect_requirement(input, 1, 0); }
    /* exact topology count 2 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.online_display_count = 2;
      display_expect_requirement(input, 1, 0); }
    /* exact topology count UINT64_MAX */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.online_display_count = UINT64_MAX;
      display_expect_requirement(input, 1, 0); }
    /* exact topology count 0x0000000100000001 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.online_display_count = 0x0000000100000001;
      display_expect_requirement(input, 1, 0); }
    /* optional ignores absent and arbitrary topology */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.requires_sole_main_display = 0;       input.main_display_id = 0;       input.sole_online_display_id = UINT32_MAX;       input.online_display_count = UINT64_MAX;
      display_expect_requirement(input, 1, 1); }
    /* full high-bit identity remains valid */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.required_vendor_id = 0x00016f73;       input.observed_vendor_id = 0x00016f73;       input.required_product_id = 0x00011717;       input.observed_product_id = 0x00011717;       input.required_serial_number = 0x00010007;       input.observed_serial_number = 0x00010007;       input.display_id = 0x0001002a;       input.main_display_id = 0x0001002a;       input.sole_online_display_id = 0x0001002a;
      display_expect_requirement(input, 1, 1); }
    /* exact unrestricted identity 0 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.required_vendor_id = 0;       input.observed_vendor_id = 0;       input.required_product_id = 0;       input.observed_product_id = 0;       input.required_serial_number = 0;       input.observed_serial_number = 0;       input.display_id = 0;       input.main_display_id = 0;       input.sole_online_display_id = 0;
      display_expect_requirement(input, 1, 1); }
    /* exact unrestricted identity UINT32_MAX */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.required_vendor_id = UINT32_MAX;       input.observed_vendor_id = UINT32_MAX;       input.required_product_id = UINT32_MAX;       input.observed_product_id = UINT32_MAX;       input.required_serial_number = UINT32_MAX;       input.observed_serial_number = UINT32_MAX;       input.display_id = UINT32_MAX;       input.main_display_id = UINT32_MAX;       input.sole_online_display_id = UINT32_MAX;
      display_expect_requirement(input, 1, 1); }
    /* closed requires_sole_main_display=2 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.requires_sole_main_display = 2;
      display_expect_requirement(input, 0, 0); }
    /* closed requires_sole_main_display=UINT32_MAX */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.requires_sole_main_display = UINT32_MAX;
      display_expect_requirement(input, 0, 0); }
    /* closed is_online=2 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.requires_sole_main_display = 0;       input.is_online = 2;
      display_expect_requirement(input, 0, 0); }
    /* closed is_online=UINT32_MAX */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.requires_sole_main_display = 0;       input.is_online = UINT32_MAX;
      display_expect_requirement(input, 0, 0); }
    /* closed is_active=2 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.requires_sole_main_display = 0;       input.is_active = 2;
      display_expect_requirement(input, 0, 0); }
    /* closed is_active=UINT32_MAX */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.requires_sole_main_display = 0;       input.is_active = UINT32_MAX;
      display_expect_requirement(input, 0, 0); }
    /* literal vendor=0x6f73 product=0x1717 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.vendor_id = 0x6f73;       input.product_id = 0x1717;
      display_expect_kind(input, 1, 1); }
    /* literal vendor=0x6f73 product=0x1718 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.vendor_id = 0x6f73;       input.product_id = 0x1718;
      display_expect_kind(input, 1, 1); }
    /* literal vendor=0 product=0x1717 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.vendor_id = 0;       input.product_id = 0x1717;
      display_expect_kind(input, 1, 0); }
    /* literal vendor=0x6f73 product=0x1719 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.vendor_id = 0x6f73;       input.product_id = 0x1719;
      display_expect_kind(input, 1, 0); }
    /* literal vendor=0x00016f73 product=0x1717 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.vendor_id = 0x00016f73;       input.product_id = 0x1717;
      display_expect_kind(input, 1, 0); }
    /* literal vendor=0x00016f73 product=0x1718 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.vendor_id = 0x00016f73;       input.product_id = 0x1718;
      display_expect_kind(input, 1, 0); }
    /* literal vendor=0x6f73 product=0x00011717 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.vendor_id = 0x6f73;       input.product_id = 0x00011717;
      display_expect_kind(input, 1, 0); }
    /* literal vendor=0x6f73 product=0x00011718 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.vendor_id = 0x6f73;       input.product_id = 0x00011718;
      display_expect_kind(input, 1, 0); }
    /* literal vendor=0x00016f73 product=0x00011717 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.vendor_id = 0x00016f73;       input.product_id = 0x00011717;
      display_expect_kind(input, 1, 0); }
    /* literal vendor=UINT32_MAX product=UINT32_MAX */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.vendor_id = UINT32_MAX;       input.product_id = UINT32_MAX;
      display_expect_kind(input, 1, 0); }
    /* ordinary signed endpoints INT64_MIN/INT64_MAX */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0;       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;
      display_expect_source(input, 1, 0, 1, INT64_MIN, INT64_MAX); }
    /* ordinary signed endpoints INT64_MAX/INT64_MIN */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0;       input.logical_width = INT64_MAX;       input.logical_height = INT64_MIN;
      display_expect_source(input, 1, 0, 1, INT64_MAX, INT64_MIN); }
    /* ordinary signed endpoints -1/0 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0;       input.logical_width = -1;       input.logical_height = 0;
      display_expect_source(input, 1, 0, 1, -1, 0); }
    /* ordinary signed endpoints 0/1 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0;       input.logical_width = 0;       input.logical_height = 1;
      display_expect_source(input, 1, 0, 1, 0, 1); }
    /* ordinary signed endpoints 32769/-32769 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0;       input.logical_width = 32769;       input.logical_height = -32769;
      display_expect_source(input, 1, 0, 1, 32769, -32769); }
    /* ordinary alias/source early return 0/0x1717 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0;       input.product_id = 0x1717;       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;
      display_expect_source(input, 1, 0, 1, INT64_MIN, INT64_MAX); }
    /* ordinary alias/source early return 0x6f73/0x1719 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0x6f73;       input.product_id = 0x1719;       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;
      display_expect_source(input, 1, 0, 1, INT64_MIN, INT64_MAX); }
    /* ordinary alias/source early return 0x00016f73/0x1717 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0x00016f73;       input.product_id = 0x1717;       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;
      display_expect_source(input, 1, 0, 1, INT64_MIN, INT64_MAX); }
    /* ordinary alias/source early return 0x00016f73/0x1718 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0x00016f73;       input.product_id = 0x1718;       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;
      display_expect_source(input, 1, 0, 1, INT64_MIN, INT64_MAX); }
    /* ordinary alias/source early return 0x6f73/0x00011717 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0x6f73;       input.product_id = 0x00011717;       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;
      display_expect_source(input, 1, 0, 1, INT64_MIN, INT64_MAX); }
    /* ordinary alias/source early return 0x6f73/0x00011718 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0x6f73;       input.product_id = 0x00011718;       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;
      display_expect_source(input, 1, 0, 1, INT64_MIN, INT64_MAX); }
    /* ordinary alias/source early return 0x00016f73/0x00011717 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = 0x00016f73;       input.product_id = 0x00011717;       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;
      display_expect_source(input, 1, 0, 1, INT64_MIN, INT64_MAX); }
    /* ordinary alias/source early return UINT32_MAX/UINT32_MAX */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.vendor_id = UINT32_MAX;       input.product_id = UINT32_MAX;       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;
      display_expect_source(input, 1, 0, 1, INT64_MIN, INT64_MAX); }
    /* owned exact current framebuffer */
    { beluga_core_source_dimensions_facts_t input = display_source_input();

      display_expect_source(input, 1, 1, 1, 1170, 2532); }
    /* second owned product exact current framebuffer */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.product_id = 0x1718;
      display_expect_source(input, 1, 1, 1, 1170, 2532); }
    /* owned minimum inclusive */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.logical_width = 2;       input.logical_height = 2;       input.core_graphics_logical_width = 2;       input.core_graphics_logical_height = 2;       input.core_graphics_pixel_width = 2;       input.core_graphics_pixel_height = 2;       input.filter_content_width = 2.0;       input.filter_content_height = 2.0;       input.point_pixel_scale = 1.0;
      display_expect_source(input, 1, 1, 1, 2, 2); }
    /* owned maximum inclusive */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.logical_width = 32768;       input.logical_height = 32768;       input.core_graphics_logical_width = 32768;       input.core_graphics_logical_height = 32768;       input.core_graphics_pixel_width = 32768;       input.core_graphics_pixel_height = 32768;       input.filter_content_width = 32768.0;       input.filter_content_height = 32768.0;       input.point_pixel_scale = 4.0;
      display_expect_source(input, 1, 1, 1, 32768, 32768); }
    /* owned odd framebuffer has no chroma/output rounding */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.logical_width = 2;       input.logical_height = 2;       input.core_graphics_logical_width = 2;       input.core_graphics_logical_height = 2;       input.core_graphics_pixel_width = 3;       input.core_graphics_pixel_height = 5;       input.filter_content_width = 2.0;       input.filter_content_height = 2.0;       input.point_pixel_scale = 4.0;
      display_expect_source(input, 1, 1, 1, 3, 5); }
    /* owned refuses logical_width=1 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.logical_width = 1;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses logical_width=32769 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.logical_width = 32769;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses logical_height=1 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.logical_height = 1;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses logical_height=32769 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.logical_height = 32769;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses core_graphics_logical_width=1 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = 1;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses core_graphics_logical_width=32769 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_width = 32769;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses core_graphics_logical_height=1 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_height = 1;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses core_graphics_logical_height=32769 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_logical_height = 32769;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses core_graphics_pixel_width=1 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_pixel_width = 1;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses core_graphics_pixel_width=32769 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_pixel_width = 32769;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses core_graphics_pixel_height=1 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_pixel_height = 1;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses core_graphics_pixel_height=32769 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.core_graphics_pixel_height = 32769;
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses nonfinite filter_content_width 0x7ff80000000000a5 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses nonfinite filter_content_width 0x7ff0000000000000 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_width = display_f64_bits(UINT64_C(0x7ff0000000000000));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses nonfinite filter_content_width 0xfff0000000000000 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_width = display_f64_bits(UINT64_C(0xfff0000000000000));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses nonfinite filter_content_height 0x7ff80000000000a5 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_height = display_f64_bits(UINT64_C(0x7ff80000000000a5));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses nonfinite filter_content_height 0x7ff0000000000000 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses nonfinite filter_content_height 0xfff0000000000000 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_height = display_f64_bits(UINT64_C(0xfff0000000000000));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses nonfinite point_pixel_scale 0x7ff80000000000a5 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.point_pixel_scale = display_f64_bits(UINT64_C(0x7ff80000000000a5));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses nonfinite point_pixel_scale 0x7ff0000000000000 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.point_pixel_scale = display_f64_bits(UINT64_C(0x7ff0000000000000));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned refuses nonfinite point_pixel_scale 0xfff0000000000000 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.point_pixel_scale = display_f64_bits(UINT64_C(0xfff0000000000000));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned scale literal {"bits":"0x3fefffffffffffff"} */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.point_pixel_scale = display_f64_bits(UINT64_C(0x3fefffffffffffff));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned scale literal "1.0" */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.point_pixel_scale = 1.0;
      display_expect_source(input, 1, 1, 1, 1170, 2532); }
    /* owned scale literal "4.0" */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.point_pixel_scale = 4.0;
      display_expect_source(input, 1, 1, 1, 1170, 2532); }
    /* owned scale literal {"bits":"0x4010000000000001"} */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.point_pixel_scale = display_f64_bits(UINT64_C(0x4010000000000001));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned half-pixel literal filter_content_width 0x4078580000000000 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_width = display_f64_bits(UINT64_C(0x4078580000000000));
      display_expect_source(input, 1, 1, 1, 1170, 2532); }
    /* owned half-pixel literal filter_content_width 0x407857ffffffffff */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_width = display_f64_bits(UINT64_C(0x407857ffffffffff));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned half-pixel literal filter_content_width 0x4078680000000000 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_width = display_f64_bits(UINT64_C(0x4078680000000000));
      display_expect_source(input, 1, 1, 1, 1170, 2532); }
    /* owned half-pixel literal filter_content_width 0x4078680000000001 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_width = display_f64_bits(UINT64_C(0x4078680000000001));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned half-pixel literal filter_content_height 0x408a5c0000000000 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_height = display_f64_bits(UINT64_C(0x408a5c0000000000));
      display_expect_source(input, 1, 1, 1, 1170, 2532); }
    /* owned half-pixel literal filter_content_height 0x408a5bffffffffff */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_height = display_f64_bits(UINT64_C(0x408a5bffffffffff));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* owned half-pixel literal filter_content_height 0x408a640000000000 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_height = display_f64_bits(UINT64_C(0x408a640000000000));
      display_expect_source(input, 1, 1, 1, 1170, 2532); }
    /* owned half-pixel literal filter_content_height 0x408a640000000001 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.filter_content_height = display_f64_bits(UINT64_C(0x408a640000000001));
      display_expect_source(input, 1, 1, 0, 0, 0); }
    /* signed exact stability */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.before_width = INT64_MIN;       input.before_height = INT64_MAX;       input.after_width = INT64_MIN;       input.after_height = INT64_MAX;
      display_expect_stable(input, 1, 1); }
    /* signed exact stability */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.before_width = INT64_MIN;       input.before_height = INT64_MAX;       input.after_width = INT64_MIN;       input.after_height = 0;
      display_expect_stable(input, 1, 0); }
    /* signed exact stability */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.before_width = INT64_MIN;       input.before_height = INT64_MAX;       input.after_width = 0;       input.after_height = INT64_MAX;
      display_expect_stable(input, 1, 0); }
    /* signed exact stability */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.before_width = 0;       input.before_height = 0;       input.after_width = 0;       input.after_height = 0;
      display_expect_stable(input, 1, 1); }
    /* signed exact stability */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.before_width = -1;       input.before_height = 1;       input.after_width = -1;       input.after_height = 1;
      display_expect_stable(input, 1, 1); }
    /* signed exact stability */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.before_width = 32769;       input.before_height = -32769;       input.after_width = 32769;       input.after_height = -32769;
      display_expect_stable(input, 1, 1); }
    /* independent envelope abi_version=0 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.abi_version = 0;
      display_expect_requirement(input, 0, 0); }
    /* independent envelope abi_version=2 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.abi_version = 2;
      display_expect_requirement(input, 0, 0); }
    /* independent envelope abi_version=UINT32_MAX */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.abi_version = UINT32_MAX;
      display_expect_requirement(input, 0, 0); }
    /* independent envelope reserved=1 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.reserved = 1;
      display_expect_requirement(input, 0, 0); }
    /* independent envelope reserved=2 */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.reserved = 2;
      display_expect_requirement(input, 0, 0); }
    /* independent envelope reserved=UINT32_MAX */
    { beluga_core_display_requirement_facts_t input = display_requirement_input();
      input.reserved = UINT32_MAX;
      display_expect_requirement(input, 0, 0); }
    /* independent envelope abi_version=0 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.abi_version = 0;
      display_expect_kind(input, 0, 0); }
    /* independent envelope abi_version=2 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.abi_version = 2;
      display_expect_kind(input, 0, 0); }
    /* independent envelope abi_version=UINT32_MAX */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.abi_version = UINT32_MAX;
      display_expect_kind(input, 0, 0); }
    /* independent envelope reserved=1 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.reserved = 1;
      display_expect_kind(input, 0, 0); }
    /* independent envelope reserved=2 */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.reserved = 2;
      display_expect_kind(input, 0, 0); }
    /* independent envelope reserved=UINT32_MAX */
    { beluga_core_source_dimension_kind_facts_t input = {1, 0, 0x6f73, 0x1717};
      input.reserved = UINT32_MAX;
      display_expect_kind(input, 0, 0); }
    /* independent envelope abi_version=0 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.abi_version = 0;
      display_expect_source(input, 0, 0, 0, 0, 0); }
    /* independent envelope abi_version=2 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.abi_version = 2;
      display_expect_source(input, 0, 0, 0, 0, 0); }
    /* independent envelope abi_version=UINT32_MAX */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.abi_version = UINT32_MAX;
      display_expect_source(input, 0, 0, 0, 0, 0); }
    /* independent envelope reserved=1 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.reserved = 1;
      display_expect_source(input, 0, 0, 0, 0, 0); }
    /* independent envelope reserved=2 */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.reserved = 2;
      display_expect_source(input, 0, 0, 0, 0, 0); }
    /* independent envelope reserved=UINT32_MAX */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.reserved = UINT32_MAX;
      display_expect_source(input, 0, 0, 0, 0, 0); }
    /* independent envelope abi_version=0 */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.abi_version = 0;
      display_expect_stable(input, 0, 0); }
    /* independent envelope abi_version=2 */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.abi_version = 2;
      display_expect_stable(input, 0, 0); }
    /* independent envelope abi_version=UINT32_MAX */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.abi_version = UINT32_MAX;
      display_expect_stable(input, 0, 0); }
    /* independent envelope reserved=1 */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.reserved = 1;
      display_expect_stable(input, 0, 0); }
    /* independent envelope reserved=2 */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.reserved = 2;
      display_expect_stable(input, 0, 0); }
    /* independent envelope reserved=UINT32_MAX */
    { beluga_core_source_dimensions_stability_facts_t input = {1, 0, INT64_MIN, INT64_MAX, INT64_MIN, INT64_MAX};
      input.reserved = UINT32_MAX;
      display_expect_stable(input, 0, 0); }
    /* envelope precedes ordinary branch abi_version */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.vendor_id = 0;       input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;       input.abi_version = 0;
      display_expect_source(input, 0, 0, 0, 0, 0); }
    /* envelope precedes ordinary branch reserved */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.vendor_id = 0;       input.core_graphics_logical_width = INT64_MIN;       input.core_graphics_logical_height = INT64_MAX;       input.core_graphics_pixel_width = INT64_MIN;       input.core_graphics_pixel_height = INT64_MAX;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0x7ff0000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));       input.logical_width = INT64_MIN;       input.logical_height = INT64_MAX;       input.reserved = 1;
      display_expect_source(input, 0, 0, 0, 0, 0); }
    /* envelope precedes legitimate owned absence abi_version */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.logical_width = 1;       input.abi_version = 0;
      display_expect_source(input, 0, 0, 0, 0, 0); }
    /* envelope precedes legitimate owned absence reserved */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.logical_width = 1;       input.reserved = 1;
      display_expect_source(input, 0, 0, 0, 0, 0); }
    /* ordinary ignores three distinct NaN payloads */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.vendor_id = 0;       input.logical_width = INT64_MAX;       input.logical_height = INT64_MIN;       input.filter_content_width = display_f64_bits(UINT64_C(0x7ff80000000000a5));       input.filter_content_height = display_f64_bits(UINT64_C(0xfff800000000005a));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x7ff8000000000001));
      display_expect_source(input, 1, 0, 1, INT64_MAX, INT64_MIN); }
    /* ordinary ignores positive and negative signed zero */
    { beluga_core_source_dimensions_facts_t input = display_source_input();
      input.vendor_id = 0;       input.logical_width = -1;       input.logical_height = 1;       input.filter_content_width = display_f64_bits(UINT64_C(0x8000000000000000));       input.filter_content_height = display_f64_bits(UINT64_C(0x0000000000000000));       input.point_pixel_scale = display_f64_bits(UINT64_C(0x8000000000000000));
      display_expect_source(input, 1, 0, 1, -1, 1); }
    puts("BelugaCore C display admission ABI PASS: exact layouts, native branch order, signed endpoints and unchanged refusals");
}


/* Output dimensions: actual copied ABI only; uncompiled authored rows, no capture IO. */
_Static_assert(sizeof(beluga_core_output_dimensions_facts_t) == 32, "output beluga_core_output_dimensions_facts_t size");
_Static_assert(_Alignof(beluga_core_output_dimensions_facts_t) == 8, "output beluga_core_output_dimensions_facts_t alignment");
_Static_assert(offsetof(beluga_core_output_dimensions_facts_t, abi_version) == 0, "output beluga_core_output_dimensions_facts_t.abi_version offset");
_Static_assert(offsetof(beluga_core_output_dimensions_facts_t, reserved) == 4, "output beluga_core_output_dimensions_facts_t.reserved offset");
_Static_assert(offsetof(beluga_core_output_dimensions_facts_t, source_width) == 8, "output beluga_core_output_dimensions_facts_t.source_width offset");
_Static_assert(offsetof(beluga_core_output_dimensions_facts_t, source_height) == 16, "output beluga_core_output_dimensions_facts_t.source_height offset");
_Static_assert(offsetof(beluga_core_output_dimensions_facts_t, maximum_width) == 24, "output beluga_core_output_dimensions_facts_t.maximum_width offset");
_Static_assert(sizeof(beluga_core_output_dimensions_decision_t) == 40, "output beluga_core_output_dimensions_decision_t size");
_Static_assert(_Alignof(beluga_core_output_dimensions_decision_t) == 8, "output beluga_core_output_dimensions_decision_t alignment");
_Static_assert(offsetof(beluga_core_output_dimensions_decision_t, abi_version) == 0, "output beluga_core_output_dimensions_decision_t.abi_version offset");
_Static_assert(offsetof(beluga_core_output_dimensions_decision_t, status) == 4, "output beluga_core_output_dimensions_decision_t.status offset");
_Static_assert(offsetof(beluga_core_output_dimensions_decision_t, decision) == 8, "output beluga_core_output_dimensions_decision_t.decision offset");
_Static_assert(offsetof(beluga_core_output_dimensions_decision_t, reserved) == 12, "output beluga_core_output_dimensions_decision_t.reserved offset");
_Static_assert(offsetof(beluga_core_output_dimensions_decision_t, width) == 16, "output beluga_core_output_dimensions_decision_t.width offset");
_Static_assert(offsetof(beluga_core_output_dimensions_decision_t, height) == 24, "output beluga_core_output_dimensions_decision_t.height offset");
_Static_assert(offsetof(beluga_core_output_dimensions_decision_t, rounded_height_bits) == 32, "output beluga_core_output_dimensions_decision_t.rounded_height_bits offset");

static void output_dimensions_expect(beluga_core_output_dimensions_facts_t input,
                                     uint32_t status, uint32_t decision,
                                     int64_t width, int64_t height, uint64_t rounded_bits) {
    const beluga_core_output_dimensions_facts_t before = input;
    const beluga_core_output_dimensions_decision_t actual = beluga_core_output_dimensions(input);
    assert(memcmp(&input, &before, sizeof(input)) == 0);
    assert(actual.abi_version == 1 && actual.status == status && actual.decision == decision);
    assert(actual.reserved == 0 && actual.width == width && actual.height == height);
    assert(actual.rounded_height_bits == rounded_bits);
}
static void output_dimensions_smoke(void) {
    /* phone-retina */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(1206), INT64_C(2622), INT64_C(1920)},
                             UINT32_C(1), UINT32_C(1), INT64_C(1206), INT64_C(2622), UINT64_C(0x40a47c0000000000));
    /* landscape */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(3840), INT64_C(2160), INT64_C(1920)},
                             UINT32_C(1), UINT32_C(1), INT64_C(1920), INT64_C(1080), UINT64_C(0x4090e00000000000));
    /* odd-full-frame */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(1205), INT64_C(2621), INT64_C(1920)},
                             UINT32_C(1), UINT32_C(1), INT64_C(1204), INT64_C(2618), UINT64_C(0x40a4760000000000));
    /* half-scale */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(603), INT64_C(1312), INT64_C(1920)},
                             UINT32_C(1), UINT32_C(1), INT64_C(602), INT64_C(1310), UINT64_C(0x4094780000000000));
    /* odd-cap */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(7), INT64_C(11), INT64_C(5)},
                             UINT32_C(1), UINT32_C(1), INT64_C(4), INT64_C(6), UINT64_C(0x4018000000000000));
    /* positive-half-up */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(4), INT64_C(7), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(4), UINT64_C(0x4010000000000000));
    /* positive-half-chroma */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(4), INT64_C(5), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(2), UINT64_C(0x4008000000000000));
    /* nearest-upper */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(100), INT64_C(99), INT64_C(20)},
                             UINT32_C(1), UINT32_C(1), INT64_C(20), INT64_C(20), UINT64_C(0x4034000000000000));
    /* nearest-lower */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(100), INT64_C(91), INT64_C(20)},
                             UINT32_C(1), UINT32_C(1), INT64_C(20), INT64_C(18), UINT64_C(0x4032000000000000));
    /* nearest-chroma */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(100), INT64_C(96), INT64_C(20)},
                             UINT32_C(1), UINT32_C(1), INT64_C(20), INT64_C(18), UINT64_C(0x4033000000000000));
    /* floor-zero */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(100), INT64_C(11), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(2), UINT64_C(0x0000000000000000));
    /* floor-one */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(100), INT64_C(26), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(2), UINT64_C(0x3ff0000000000000));
    /* cap-small */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(4), INT64_C(6), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(2), UINT64_C(0x4008000000000000));
    /* cap-exact */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(4), INT64_C(6), INT64_C(4)},
                             UINT32_C(1), UINT32_C(1), INT64_C(4), INT64_C(6), UINT64_C(0x4018000000000000));
    /* cap-no-upscale */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(4), INT64_C(6), INT64_C(100)},
                             UINT32_C(1), UINT32_C(1), INT64_C(4), INT64_C(6), UINT64_C(0x4018000000000000));
    /* width-chroma-before-scale */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(7), INT64_C(14), INT64_C(5)},
                             UINT32_C(1), UINT32_C(1), INT64_C(4), INT64_C(8), UINT64_C(0x4020000000000000));
    /* source-chroma-before-scale */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(5), INT64_C(10), INT64_C(20)},
                             UINT32_C(1), UINT32_C(1), INT64_C(4), INT64_C(8), UINT64_C(0x4020000000000000));
    /* third-width */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(3), INT64_C(9), INT64_C(3)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(6), UINT64_C(0x4018000000000000));
    /* larger-half-up */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(400), INT64_C(699), INT64_C(200)},
                             UINT32_C(1), UINT32_C(1), INT64_C(200), INT64_C(350), UINT64_C(0x4075e00000000000));
    /* larger-half-even-chroma */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(400), INT64_C(698), INT64_C(200)},
                             UINT32_C(1), UINT32_C(1), INT64_C(200), INT64_C(348), UINT64_C(0x4075d00000000000));
    /* integer-ratio-is-not-policy */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(5), INT64_C(9), INT64_C(4)},
                             UINT32_C(1), UINT32_C(1), INT64_C(4), INT64_C(6), UINT64_C(0x401c000000000000));
    /* wide-signed-min-height */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(9223372036854775807), INT64_C(2), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(2), UINT64_C(0x0000000000000000));
    /* wide-signed-no-arbitrary-cap */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(9223372036854775807), INT64_C(2), INT64_C(9223372036854775807)},
                             UINT32_C(1), UINT32_C(1), INT64_C(9223372036854775806), INT64_C(2), UINT64_C(0x4000000000000000));
    /* source-width-high-u16 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(65538), INT64_C(6), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(2), UINT64_C(0x0000000000000000));
    /* source-width-high-u32 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(4294967298), INT64_C(6), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(2), UINT64_C(0x0000000000000000));
    /* source-height-high-u32 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(4294967297), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(4294967296), UINT64_C(0x41f0000000100000));
    /* cap-high-u16 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(8), INT64_C(16), INT64_C(65538)},
                             UINT32_C(1), UINT32_C(1), INT64_C(8), INT64_C(16), UINT64_C(0x4030000000000000));
    /* cap-high-u32 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(8), INT64_C(16), INT64_C(4294967298)},
                             UINT32_C(1), UINT32_C(1), INT64_C(8), INT64_C(16), UINT64_C(0x4030000000000000));
    /* height-2pow53-plus1 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(9007199254740993), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(9007199254740992), UINT64_C(0x4340000000000000));
    /* height-2pow53-plus3 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(9007199254740995), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(9007199254740996), UINT64_C(0x4340000000000002));
    /* upper-minus1024 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(9223372036854774783), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(9223372036854774784), UINT64_C(0x43dfffffffffffff));
    /* upper-representable-adjacent */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(9223372036854775295), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(9223372036854774784), UINT64_C(0x43dfffffffffffff));
    /* upper-minus1023 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(9223372036854774784), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(9223372036854774784), UINT64_C(0x43dfffffffffffff));
    /* height-maximum-width-three */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(3), INT64_C(9223372036854775807), INT64_C(2)},
                             UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(6148914691236516864), UINT64_C(0x43d5555555555555));
    /* upper-distinct-refusal */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(9223372036854775807), INT64_C(2)},
                             UINT32_C(1), UINT32_C(2), INT64_C(2), INT64_C(0), UINT64_C(0x43e0000000000000));
    /* upper-midpoint-distinct-refusal */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(9223372036854775296), INT64_C(2)},
                             UINT32_C(1), UINT32_C(2), INT64_C(2), INT64_C(0), UINT64_C(0x43e0000000000000));
    /* maximum-triple-distinct-refusal */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(9223372036854775807), INT64_C(9223372036854775807), INT64_C(9223372036854775807)},
                             UINT32_C(1), UINT32_C(2), INT64_C(9223372036854775806), INT64_C(0), UINT64_C(0x43e0000000000000));
    /* invalid-slot-0--9223372036854775808 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_MIN, INT64_C(2), INT64_C(2)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-1--9223372036854775808 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_MIN, INT64_C(2)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-2--9223372036854775808 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(2), INT64_MIN},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-0--4294967296 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(-4294967296), INT64_C(2), INT64_C(2)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-1--4294967296 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(-4294967296), INT64_C(2)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-2--4294967296 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(2), INT64_C(-4294967296)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-0--1 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(-1), INT64_C(2), INT64_C(2)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-1--1 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(-1), INT64_C(2)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-2--1 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(2), INT64_C(-1)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-0-0 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(2), INT64_C(2)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-1-0 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(0), INT64_C(2)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-2-0 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(2), INT64_C(0)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-0-1 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(1), INT64_C(2), INT64_C(2)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-1-1 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(1), INT64_C(2)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* invalid-slot-2-1 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(0), INT64_C(2), INT64_C(2), INT64_C(1)},
                             UINT32_C(1), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* unknown-abi-0 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(0), UINT32_C(0), INT64_C(2), INT64_C(2), INT64_C(2)},
                             UINT32_C(0), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* unknown-abi-2 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(2), UINT32_C(0), INT64_C(2), INT64_C(2), INT64_C(2)},
                             UINT32_C(0), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* unknown-abi-2147483649 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(2147483649), UINT32_C(0), INT64_C(2), INT64_C(2), INT64_C(2)},
                             UINT32_C(0), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* unknown-abi-4294967295 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(4294967295), UINT32_C(0), INT64_C(2), INT64_C(2), INT64_C(2)},
                             UINT32_C(0), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* nonzero-reserved-1 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(2), INT64_C(2)},
                             UINT32_C(0), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* nonzero-reserved-2 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(2), INT64_C(2), INT64_C(2), INT64_C(2)},
                             UINT32_C(0), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* nonzero-reserved-2147483648 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(2147483648), INT64_C(2), INT64_C(2), INT64_C(2)},
                             UINT32_C(0), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* nonzero-reserved-4294967295 */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(4294967295), INT64_C(2), INT64_C(2), INT64_C(2)},
                             UINT32_C(0), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* unknown-envelope-before-invalid-dimensions */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(0), UINT32_C(0), INT64_MIN, INT64_C(9223372036854775807), INT64_C(-1)},
                             UINT32_C(0), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    /* reserved-before-former-trap */
    output_dimensions_expect((beluga_core_output_dimensions_facts_t){UINT32_C(1), UINT32_C(1), INT64_C(2), INT64_C(9223372036854775807), INT64_C(2)},
                             UINT32_C(0), UINT32_C(0), INT64_C(0), INT64_C(0), UINT64_C(0x0000000000000000));
    puts("BelugaCore C output dimensions ABI PASS: two layouts, twelve offsets, signed projection and distinct conversion refusal");
}

/* Private append body: retain every old helper/body/call. Invoke before old C footer. */
static void ice_state_equal(beluga_core_ice_recovery_state_t a, beluga_core_ice_recovery_state_t b) {
    assert(a.abi_version == b.abi_version); assert(a.phase == b.phase); assert(a.epoch == b.epoch);
    assert(a.attempts == b.attempts); assert(a.maximum_attempts == b.maximum_attempts);
    assert(a.exhaustion_delivered == b.exhaustion_delivered); assert(a.grace_positive == b.grace_positive);
    assert(a.cursor == b.cursor); assert(a.reserved == b.reserved);
}
static void ice_event_equal(beluga_core_ice_recovery_event_t a, beluga_core_ice_recovery_event_t b) {
    assert(a.abi_version == b.abi_version); assert(a.opcode == b.opcode); assert(a.workflow_epoch == b.workflow_epoch);
    assert(a.task_cancelled == b.task_cancelled); assert(a.succeeded == b.succeeded);
    assert(a.wait_kind == b.wait_kind); assert(a.reserved == b.reserved);
}
static void ice_row(uint32_t abi, beluga_core_ice_recovery_state_t before,
                    beluga_core_ice_recovery_event_t event, uint32_t status,
                    beluga_core_ice_recovery_state_t after, uint32_t effect, uint32_t flags) {
    beluga_core_ice_recovery_result_t out = beluga_core_ice_recovery_step(abi, before, event);
    assert(out.abi_version == 1); assert(out.status == status); assert(out.effect == effect);
    assert(out.flags == flags); assert(out.reserved == 0);
    ice_state_equal(out.copied_before, before); ice_event_equal(out.copied_event, event);
    ice_state_equal(out.candidate_state, after);
}
static void ice_recovery_smoke(void) {
    /* Five layouts; all 31 named member offsets, no inferred padding/cached native fallback. */
    assert(sizeof(beluga_core_ice_recovery_config_t) == 16); assert(_Alignof(beluga_core_ice_recovery_config_t) == 8);
    assert(sizeof(beluga_core_ice_recovery_state_t) == 48); assert(_Alignof(beluga_core_ice_recovery_state_t) == 8);
    assert(sizeof(beluga_core_ice_recovery_event_t) == 32); assert(_Alignof(beluga_core_ice_recovery_event_t) == 8);
    assert(sizeof(beluga_core_ice_recovery_init_result_t) == 72); assert(_Alignof(beluga_core_ice_recovery_init_result_t) == 8);
    assert(sizeof(beluga_core_ice_recovery_result_t) == 152); assert(_Alignof(beluga_core_ice_recovery_result_t) == 8);
#define ICE_OFFSET(type, member, number) assert(offsetof(type, member) == number)
    ICE_OFFSET(beluga_core_ice_recovery_config_t, maximum_attempts, 0);
    ICE_OFFSET(beluga_core_ice_recovery_config_t, grace_positive, 8);
    ICE_OFFSET(beluga_core_ice_recovery_config_t, reserved, 12);
    ICE_OFFSET(beluga_core_ice_recovery_state_t, abi_version, 0); ICE_OFFSET(beluga_core_ice_recovery_state_t, phase, 4);
    ICE_OFFSET(beluga_core_ice_recovery_state_t, epoch, 8); ICE_OFFSET(beluga_core_ice_recovery_state_t, attempts, 16);
    ICE_OFFSET(beluga_core_ice_recovery_state_t, maximum_attempts, 24); ICE_OFFSET(beluga_core_ice_recovery_state_t, exhaustion_delivered, 32);
    ICE_OFFSET(beluga_core_ice_recovery_state_t, grace_positive, 36); ICE_OFFSET(beluga_core_ice_recovery_state_t, cursor, 40);
    ICE_OFFSET(beluga_core_ice_recovery_state_t, reserved, 44);
    ICE_OFFSET(beluga_core_ice_recovery_event_t, abi_version, 0); ICE_OFFSET(beluga_core_ice_recovery_event_t, opcode, 4);
    ICE_OFFSET(beluga_core_ice_recovery_event_t, workflow_epoch, 8); ICE_OFFSET(beluga_core_ice_recovery_event_t, task_cancelled, 16);
    ICE_OFFSET(beluga_core_ice_recovery_event_t, succeeded, 20); ICE_OFFSET(beluga_core_ice_recovery_event_t, wait_kind, 24);
    ICE_OFFSET(beluga_core_ice_recovery_event_t, reserved, 28);
    ICE_OFFSET(beluga_core_ice_recovery_init_result_t, status, 0); ICE_OFFSET(beluga_core_ice_recovery_init_result_t, reserved, 4);
    ICE_OFFSET(beluga_core_ice_recovery_init_result_t, copied_config, 8); ICE_OFFSET(beluga_core_ice_recovery_init_result_t, candidate_state, 24);
    ICE_OFFSET(beluga_core_ice_recovery_result_t, abi_version, 0); ICE_OFFSET(beluga_core_ice_recovery_result_t, status, 4);
    ICE_OFFSET(beluga_core_ice_recovery_result_t, copied_before, 8); ICE_OFFSET(beluga_core_ice_recovery_result_t, copied_event, 56);
    ICE_OFFSET(beluga_core_ice_recovery_result_t, candidate_state, 88); ICE_OFFSET(beluga_core_ice_recovery_result_t, effect, 136);
    ICE_OFFSET(beluga_core_ice_recovery_result_t, flags, 140); ICE_OFFSET(beluga_core_ice_recovery_result_t, reserved, 144);
#undef ICE_OFFSET
    const beluga_core_ice_recovery_config_t config = { INT64_MAX, 1, 0 };
    const beluga_core_ice_recovery_state_t idle = { 1, 0, 0, 0, INT64_MAX, 0, 1, 0, 0 };
    beluga_core_ice_recovery_init_result_t initial = beluga_core_ice_recovery_initialize(1, config);
    assert(initial.status == 0); assert(initial.reserved == 0);
    assert(initial.copied_config.maximum_attempts == INT64_MAX); assert(initial.copied_config.grace_positive == 1);
    assert(initial.copied_config.reserved == 0); ice_state_equal(initial.candidate_state, idle);
    beluga_core_ice_recovery_init_result_t denied = beluga_core_ice_recovery_initialize(0x10001, config);
    assert(denied.status == 1); assert(denied.reserved == 0);
    assert(denied.copied_config.maximum_attempts == INT64_MAX); assert(denied.copied_config.grace_positive == 1);
    assert(denied.copied_config.reserved == 0);
    ice_state_equal(denied.candidate_state, (beluga_core_ice_recovery_state_t){0,0,0,0,0,0,0,0,0});
    beluga_core_ice_recovery_state_t wrap = { 1, 0, UINT64_MAX, 0, INT64_MAX, 0, 1, 0, 0 };
    beluga_core_ice_recovery_state_t entered = { 1, 2, 0, 0, INT64_MAX, 0, 1, 1, 0 };
    ice_row(1, wrap, (beluga_core_ice_recovery_event_t){1,8,0,0,0,0,0}, 0, entered, 1, 1);
    ice_row(1, entered, (beluga_core_ice_recovery_event_t){1,10,0,0,0,0,0}, 0,
        (beluga_core_ice_recovery_state_t){1,2,0,0,INT64_MAX,0,1,2,0}, 2, 0);
    ice_row(1, (beluga_core_ice_recovery_state_t){1,2,0,0,INT64_MAX,0,1,2,0},
        (beluga_core_ice_recovery_event_t){1,11,0,0,0,0,0}, 0,
        (beluga_core_ice_recovery_state_t){1,2,0,1,INT64_MAX,0,1,3,0}, 3, 0);
    ice_row(1, (beluga_core_ice_recovery_state_t){1,2,0,1,INT64_MAX,0,1,3,0},
        (beluga_core_ice_recovery_event_t){1,12,0,0,0,0,0}, 0,
        (beluga_core_ice_recovery_state_t){1,2,0,1,INT64_MAX,0,1,6,0}, 10, 0);
    ice_row(1, (beluga_core_ice_recovery_state_t){1,2,0,INT64_MAX,INT64_MAX,0,1,6,0},
        (beluga_core_ice_recovery_event_t){1,15,0,0,0,0,0}, 0,
        (beluga_core_ice_recovery_state_t){1,2,0,INT64_MAX,INT64_MAX,0,1,7,0}, 11, 0);
    ice_row(1, (beluga_core_ice_recovery_state_t){1,2,0,INT64_MAX,INT64_MAX,0,1,7,0},
        (beluga_core_ice_recovery_event_t){1,16,0,0,0,0,0}, 0,
        (beluga_core_ice_recovery_state_t){1,5,0,INT64_MAX,INT64_MAX,1,1,8,0}, 12, 0);
    ice_row(1, (beluga_core_ice_recovery_state_t){1,5,0,INT64_MAX,INT64_MAX,1,1,8,0},
        (beluga_core_ice_recovery_event_t){1,17,0,1,0,0,0}, 0,
        (beluga_core_ice_recovery_state_t){1,5,0,INT64_MAX,INT64_MAX,1,1,0,0}, 14, 0);
    ice_row(1, entered, (beluga_core_ice_recovery_event_t){1,10,0,2,0,0,0}, 3, entered, 0, 0);
    ice_row(0x10001, entered, (beluga_core_ice_recovery_event_t){1,10,0,0,0,0,0}, 1, entered, 0, 0);
    beluga_core_ice_recovery_state_t bad = {1,0,UINT64_MAX,INT64_MIN,INT64_MAX,0,1,0,0};
    ice_row(1, bad, (beluga_core_ice_recovery_event_t){1,8,0,0,0,0,0}, 2, bad, 0, 0);
    puts("BelugaCore C ICE recovery ABI PASS: five layouts, thirty-one offsets and full-width transactional transitions");
}

/* Authored-only smoke addition. Integrate with the existing architecture smokes. */
#include <BelugaCore/beluga_core.h>
#include <stddef.h>
#include <assert.h>

_Static_assert(sizeof(beluga_core_screen_liveness_optional_t) == 16, "RawOptional size");
_Static_assert(_Alignof(beluga_core_screen_liveness_optional_t) == 8, "RawOptional alignment");
_Static_assert(offsetof(beluga_core_screen_liveness_optional_t, present) == 0, "RawOptional.present");
_Static_assert(offsetof(beluga_core_screen_liveness_optional_t, value) == 8, "RawOptional.value");
_Static_assert(sizeof(beluga_core_screen_liveness_sample_t) == 192, "RawSample size");
_Static_assert(_Alignof(beluga_core_screen_liveness_sample_t) == 8, "RawSample alignment");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, generation) == 0, "RawSample.generation");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, observed_at) == 8, "RawSample.observed_at");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, track_attached) == 16, "RawSample.track_attached");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, cover) == 24, "RawSample.cover");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, inbound_present) == 32, "RawSample.inbound_present");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, inbound_bytes) == 40, "RawSample.inbound_bytes");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, inbound_packets) == 56, "RawSample.inbound_packets");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, decoded_frames) == 72, "RawSample.decoded_frames");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, inbound_width) == 88, "RawSample.inbound_width");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, inbound_height) == 104, "RawSample.inbound_height");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, frames_per_second_bits) == 120, "RawSample.frames_per_second_bits");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, render_present) == 136, "RawSample.render_present");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, presented_frames) == 144, "RawSample.presented_frames");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, content_samples) == 152, "RawSample.content_samples");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, content_changes) == 160, "RawSample.content_changes");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, presented_at) == 168, "RawSample.presented_at");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, render_width_bits) == 176, "RawSample.render_width_bits");
_Static_assert(offsetof(beluga_core_screen_liveness_sample_t, render_height_bits) == 184, "RawSample.render_height_bits");
_Static_assert(sizeof(beluga_core_screen_liveness_state_t) == 216, "RawState size");
_Static_assert(_Alignof(beluga_core_screen_liveness_state_t) == 8, "RawState alignment");
_Static_assert(offsetof(beluga_core_screen_liveness_state_t, previous_present) == 0, "RawState.previous_present");
_Static_assert(offsetof(beluga_core_screen_liveness_state_t, last_change_at) == 8, "RawState.last_change_at");
_Static_assert(offsetof(beluga_core_screen_liveness_state_t, previous) == 24, "RawState.previous");
_Static_assert(sizeof(beluga_core_screen_liveness_snapshot_t) == 296, "RawSnapshot size");
_Static_assert(_Alignof(beluga_core_screen_liveness_snapshot_t) == 8, "RawSnapshot alignment");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, liveness) == 0, "RawSnapshot.liveness");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, reset_reason) == 8, "RawSnapshot.reset_reason");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, generation) == 16, "RawSnapshot.generation");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, track_attached) == 24, "RawSnapshot.track_attached");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, cover) == 32, "RawSnapshot.cover");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, inbound_bytes) == 40, "RawSnapshot.inbound_bytes");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, inbound_byte_delta) == 56, "RawSnapshot.inbound_byte_delta");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, inbound_packets) == 72, "RawSnapshot.inbound_packets");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, inbound_packet_delta) == 88, "RawSnapshot.inbound_packet_delta");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, decoded_frames) == 104, "RawSnapshot.decoded_frames");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, decoded_frame_delta) == 120, "RawSnapshot.decoded_frame_delta");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, presented_frames) == 136, "RawSnapshot.presented_frames");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, presented_frame_delta) == 152, "RawSnapshot.presented_frame_delta");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, content_samples) == 168, "RawSnapshot.content_samples");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, content_sample_delta) == 184, "RawSnapshot.content_sample_delta");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, content_changes) == 200, "RawSnapshot.content_changes");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, content_change_delta) == 216, "RawSnapshot.content_change_delta");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, presentation_age_ms) == 232, "RawSnapshot.presentation_age_ms");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, frame_width) == 248, "RawSnapshot.frame_width");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, frame_height) == 264, "RawSnapshot.frame_height");
_Static_assert(offsetof(beluga_core_screen_liveness_snapshot_t, frames_per_second_bits) == 280, "RawSnapshot.frames_per_second_bits");
_Static_assert(sizeof(beluga_core_screen_liveness_result_t) == 536, "RawResult size");
_Static_assert(_Alignof(beluga_core_screen_liveness_result_t) == 8, "RawResult alignment");
_Static_assert(offsetof(beluga_core_screen_liveness_result_t, abi_version) == 0, "RawResult.abi_version");
_Static_assert(offsetof(beluga_core_screen_liveness_result_t, status) == 8, "RawResult.status");
_Static_assert(offsetof(beluga_core_screen_liveness_result_t, reserved) == 16, "RawResult.reserved");
_Static_assert(offsetof(beluga_core_screen_liveness_result_t, state) == 24, "RawResult.state");
_Static_assert(offsetof(beluga_core_screen_liveness_result_t, snapshot) == 240, "RawResult.snapshot");

void screen_liveness_smoke(void) {
    beluga_core_screen_liveness_state_t state = {0};
    beluga_core_screen_liveness_sample_t sample = {0};
    sample.generation = UINT64_MAX; sample.observed_at = UINT64_MAX;
    sample.track_attached = 1; sample.cover = 3; sample.inbound_present = 1;
    sample.inbound_bytes = (beluga_core_screen_liveness_optional_t){1, UINT64_MAX};
    sample.inbound_packets = (beluga_core_screen_liveness_optional_t){1, UINT64_C(0x8000000000000000)};
    sample.decoded_frames = (beluga_core_screen_liveness_optional_t){1, UINT64_C(0x20000000000000)};
    sample.inbound_width = (beluga_core_screen_liveness_optional_t){1, UINT64_C(0x8000000000000000)};
    sample.inbound_height = (beluga_core_screen_liveness_optional_t){1, INT64_MAX};
    sample.frames_per_second_bits = (beluga_core_screen_liveness_optional_t){1, UINT64_C(0xfff8000000000042)};
    sample.render_present = 1; sample.presented_frames = UINT64_MAX;
    sample.content_samples = UINT64_C(0x8000000000000000);
    sample.content_changes = UINT64_C(0x20000000000000);
    sample.presented_at = UINT64_MAX - 1;
    sample.render_width_bits = INT64_MAX; sample.render_height_bits = UINT64_C(0x8000000000000000);
    beluga_core_screen_liveness_result_t out = beluga_core_screen_liveness_observe(1, state, sample);
    assert(out.abi_version == 1 && out.status == 0 && out.reserved == 0);
    assert(out.snapshot.liveness == 1 && out.snapshot.reset_reason == 1);
    assert(out.state.previous_present == 1 && out.state.last_change_at.present == 0);
    assert(out.state.previous.generation == UINT64_MAX);
    assert(out.state.previous.frames_per_second_bits.present == 1);
    assert(out.state.previous.frames_per_second_bits.value == UINT64_C(0xfff8000000000042));
    assert(out.snapshot.frames_per_second_bits.present == 0);
    out = beluga_core_screen_liveness_observe(1, out.state, sample);
    assert(out.snapshot.reset_reason == 0 && out.snapshot.inbound_byte_delta.present == 1);
    assert(out.snapshot.inbound_byte_delta.value == 0);
    out = beluga_core_screen_liveness_observe(2, out.state, sample);
    assert(out.status == 3 && out.state.previous.generation == UINT64_MAX);
}


/*
 * Additive architecture behavior corpus; source-only, uncompiled and unexecuted.
 * Literal tables below are frozen expected values, not a native classifier.
 * All old 49 offset and layout assertions remain above and execute via the old
 * smoke. Fixture indices select local arrays only: no ABI handles or authority.
 */
static const uint64_t liveness_c_samples[57][24] = {
    /* 0: zero */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 1: A_covered_high */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0xfffffffffffffffe), UINT64_C(0x1), UINT64_C(0x3), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f7), UINT64_C(0x1), UINT64_C(0x8000000000000021), UINT64_C(0x1), UINT64_C(0x20000000000023), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0xfff8000000000042), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe1), UINT64_C(0x8000000000000037), UINT64_C(0x20000000000041), UINT64_C(0xfffffffffffffffd), UINT64_C(0x780), UINT64_C(0x7ffffffffffffffa)
    },
    /* 2: B_progress */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047), UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 3: C_clock_reversal */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047), UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 4: timing_before */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 5: timing_exact */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0x9502f900), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 6: timing_ns_after */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0x9502f901), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 7: timing_ms_last */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0x95123b3f), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 8: timing_ms_after */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0x95123b40), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 9: H_decode_stalled */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0xb2d05e00), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f9), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1),
        UINT64_C(0x438), UINT64_C(0x1), UINT64_C(0x924), UINT64_C(0x1), UINT64_C(0x408f400000000000), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 10: I_presentation_stalled */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0xb2d05e01), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8fa), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000027), UINT64_C(0x1),
        UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0x7fffffffffffffff), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 11: J_metadata_only */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0xb2d05e02), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8001), UINT64_C(0x1), UINT64_C(0x7ff0000000000000), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 12: K_missing_track */ {
        UINT64_C(0x0), UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 13: L_intentional */ {
        UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 14: M_privacy */ {
        UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x2), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 15: N_hidden */ {
        UINT64_C(0xffffffffffffffff), UINT64_C(0x2), UINT64_C(0x0), UINT64_C(0x4), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 16: O_regression */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 17: P_generation_zero */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x7ff8000000000011), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x8000), UINT64_C(0x1)
    },
    /* 18: Q_before */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0x7), UINT64_C(0x1), UINT64_C(0xb), UINT64_C(0x1), UINT64_C(0xd), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x4038000000000000), UINT64_C(0x1),
        UINT64_C(0x11), UINT64_C(0x13), UINT64_C(0x16), UINT64_C(0x0), UINT64_C(0x780), UINT64_C(0x438)
    },
    /* 19: Q_change_zero */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0x7), UINT64_C(0x1), UINT64_C(0xb), UINT64_C(0x1), UINT64_C(0xd), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x4038000000000000), UINT64_C(0x1),
        UINT64_C(0x11), UINT64_C(0x13), UINT64_C(0x17), UINT64_C(0x0), UINT64_C(0x780), UINT64_C(0x438)
    },
    /* 20: R_no_objects */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 21: S_empty_inbound */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 22: T_before */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x408f400000000000), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x8000), UINT64_C(0x1)
    },
    /* 23: T_max */ {
        UINT64_C(0x0), UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x408f400000000000), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x8000), UINT64_C(0x1)
    },
    /* 24: fps_above_upper */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x408f480000000000), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 25: fps_negative */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0xbff0000000000000), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 26: fps_negative_inf */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0xfff0000000000000), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 27: hidden_generation */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 28: absent_inbound_payload_0 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 29: inbound_optional_0_presence_2 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x2),
        UINT64_C(0x11), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 30: inbound_optional_0_absent_payload */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 31: absent_inbound_payload_1 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000021), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 32: inbound_optional_1_presence_2 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x2), UINT64_C(0x11), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 33: inbound_optional_1_absent_payload */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 34: absent_inbound_payload_2 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000023), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 35: inbound_optional_2_presence_2 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x2), UINT64_C(0x11), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 36: inbound_optional_2_absent_payload */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 37: absent_inbound_payload_3 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x8000000000000000), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 38: inbound_optional_3_presence_2 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x2),
        UINT64_C(0x11), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 39: inbound_optional_3_absent_payload */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 40: absent_inbound_payload_4 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x7fffffffffffffff), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 41: inbound_optional_4_presence_2 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x2), UINT64_C(0x11), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 42: inbound_optional_4_absent_payload */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 43: absent_inbound_payload_5 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0xfff8000000000042), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 44: inbound_optional_5_presence_2 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x2), UINT64_C(0x11), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 45: inbound_optional_5_absent_payload */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 46: bad_track */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x2), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 47: bad_cover */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x5), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 48: bad_inbound_presence */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x2), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 49: bad_render_presence */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x2),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 50: absent_render_payload_0 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 51: absent_render_payload_1 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x8000000000000037), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 52: absent_render_payload_2 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x20000000000041), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 53: absent_render_payload_3 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 54: absent_render_payload_4 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x8000000000000000), UINT64_C(0x0)
    },
    /* 55: absent_render_payload_5 */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x7fffffffffffffff)
    },
    /* 56: bad_previous_track */ {
        UINT64_C(0xffffffffffffffe0), UINT64_C(0xffffffffffffffff), UINT64_C(0x2), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1),
        UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047), UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    }
};
static const uint64_t liveness_c_states[36][27] = {
    /* 0: empty */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 1: after_A */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0xfffffffffffffffe), UINT64_C(0x1),
        UINT64_C(0x3), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f7), UINT64_C(0x1), UINT64_C(0x8000000000000021),
        UINT64_C(0x1), UINT64_C(0x20000000000023), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0xfff8000000000042), UINT64_C(0x1), UINT64_C(0xffffffffffffffe1), UINT64_C(0x8000000000000037), UINT64_C(0x20000000000041),
        UINT64_C(0xfffffffffffffffd), UINT64_C(0x780), UINT64_C(0x7ffffffffffffffa)
    },
    /* 2: after_B */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffe0), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 3: after_C */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffe0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 4: timing_zero_change */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 5: after_timing_exact */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x9502f900), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 6: after_timing_ns_after */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x9502f901), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 7: after_timing_ms_last */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x95123b3f), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 8: after_timing_ms_after */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x95123b40), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 9: after_H */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffe0), UINT64_C(0xb2d05e00), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f9), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x438), UINT64_C(0x1), UINT64_C(0x924),
        UINT64_C(0x1), UINT64_C(0x408f400000000000), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 10: after_I */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffe0), UINT64_C(0xb2d05e01), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8fa), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x1), UINT64_C(0x20000000000027), UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0x7fffffffffffffff),
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 11: after_J */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffe0), UINT64_C(0xb2d05e02), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8001),
        UINT64_C(0x1), UINT64_C(0x7ff0000000000000), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 12: after_K */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0xffffffffffffffff), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 13: after_L */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 14: after_M */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x2), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 15: after_N */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0xffffffffffffffff), UINT64_C(0x2), UINT64_C(0x0),
        UINT64_C(0x4), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 16: after_O */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 17: after_P */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x7ff8000000000011), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x8000), UINT64_C(0x1)
    },
    /* 18: before_Q */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x7), UINT64_C(0x1), UINT64_C(0xb),
        UINT64_C(0x1), UINT64_C(0xd), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x4038000000000000), UINT64_C(0x1), UINT64_C(0x11), UINT64_C(0x13), UINT64_C(0x16),
        UINT64_C(0x0), UINT64_C(0x780), UINT64_C(0x438)
    },
    /* 19: after_Q */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x7), UINT64_C(0x1), UINT64_C(0xb),
        UINT64_C(0x1), UINT64_C(0xd), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x4038000000000000), UINT64_C(0x1), UINT64_C(0x11), UINT64_C(0x13), UINT64_C(0x17),
        UINT64_C(0x0), UINT64_C(0x780), UINT64_C(0x438)
    },
    /* 20: after_R */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 21: after_S */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 22: before_T */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x408f400000000000), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x8000), UINT64_C(0x1)
    },
    /* 23: after_T */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff),
        UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x408f400000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffff),
        UINT64_C(0x0), UINT64_C(0x8000), UINT64_C(0x1)
    },
    /* 24: after_fps_above_upper */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x1), UINT64_C(0x408f480000000000), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 25: after_fps_negative */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x1), UINT64_C(0xbff0000000000000), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 26: after_fps_negative_inf */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x1), UINT64_C(0xfff0000000000000), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 27: bad_before_presence_2 */ {
        UINT64_C(0x2), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffe0), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 28: bad_clock_presence_2 */ {
        UINT64_C(0x1), UINT64_C(0x2), UINT64_C(0x11), UINT64_C(0xffffffffffffffe0), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 29: bad_clock_presence_max */ {
        UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffe0), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 30: bad_clock_absent_payload */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0xffffffffffffffe0), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 31: bad_absent_before_generation */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 32: bad_absent_before_full */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    },
    /* 33: bad_absent_before_clock_0 */ {
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 34: bad_absent_before_clock_18446744073709551615 */ {
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0)
    },
    /* 35: bad_nested_previous */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0xffffffffffffffe0), UINT64_C(0xffffffffffffffff), UINT64_C(0x2),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x8000000000000023),
        UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x8000000000000003), UINT64_C(0x1), UINT64_C(0x8000),
        UINT64_C(0x1), UINT64_C(0x8000000000000000), UINT64_C(0x1), UINT64_C(0xffffffffffffffe5), UINT64_C(0x800000000000003c), UINT64_C(0x20000000000047),
        UINT64_C(0xfffffffffffffff8), UINT64_C(0x1), UINT64_C(0x340)
    }
};
static const uint64_t liveness_c_snapshots[21][37] = {
    /* 0: A_initial */ {
        UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x3), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f7), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000021), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000023), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000037), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000041), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x780), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x0),
        UINT64_C(0x0)
    },
    /* 1: A_plateau */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x3), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f7), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000021), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000023), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000037), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000041), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x780), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x0),
        UINT64_C(0x0)
    },
    /* 2: B_progress */ {
        UINT64_C(0x8), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1),
        UINT64_C(0x2), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x3), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x1), UINT64_C(0x4), UINT64_C(0x1), UINT64_C(0x800000000000003c), UINT64_C(0x1),
        UINT64_C(0x5), UINT64_C(0x1), UINT64_C(0x20000000000047), UINT64_C(0x1), UINT64_C(0x6), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x340), UINT64_C(0x1),
        UINT64_C(0x8000000000000000)
    },
    /* 3: C_reversal */ {
        UINT64_C(0x7), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x800000000000003c), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000047), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x340), UINT64_C(0x1),
        UINT64_C(0x8000000000000000)
    },
    /* 4: timing_exact */ {
        UINT64_C(0x8), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x800000000000003c), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000047), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x9c4), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x340), UINT64_C(0x1),
        UINT64_C(0x8000000000000000)
    },
    /* 5: timing_ns_after */ {
        UINT64_C(0x7), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x800000000000003c), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000047), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x9c4), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x340), UINT64_C(0x1),
        UINT64_C(0x8000000000000000)
    },
    /* 6: timing_ms_last */ {
        UINT64_C(0x7), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x800000000000003c), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000047), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x9c4), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x340), UINT64_C(0x1),
        UINT64_C(0x8000000000000000)
    },
    /* 7: timing_ms_after */ {
        UINT64_C(0x4), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f8), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x800000000000003c), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000047), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x9c5), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x340), UINT64_C(0x1),
        UINT64_C(0x8000000000000000)
    },
    /* 8: H_decode_stalled */ {
        UINT64_C(0x5), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8f9), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x438), UINT64_C(0x1), UINT64_C(0x924), UINT64_C(0x1),
        UINT64_C(0x408f400000000000)
    },
    /* 9: I_presentation_stalled */ {
        UINT64_C(0x6), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xfefdfcfbfaf9f8fa), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000027), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0)
    },
    /* 10: J_metadata_only */ {
        UINT64_C(0x3), UINT64_C(0x0), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0)
    },
    /* 11: K_missing_track */ {
        UINT64_C(0x2), UINT64_C(0x2), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0)
    },
    /* 12: L_intentional */ {
        UINT64_C(0x0), UINT64_C(0x2), UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0)
    },
    /* 13: M_privacy */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x2), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0)
    },
    /* 14: N_hidden */ {
        UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0xffffffffffffffff), UINT64_C(0x0), UINT64_C(0x4), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0)
    },
    /* 15: O_regression */ {
        UINT64_C(0x3), UINT64_C(0x3), UINT64_C(0xffffffffffffffe0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000000000000023), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000026), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffe5), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x800000000000003c), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x20000000000047), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x340), UINT64_C(0x1),
        UINT64_C(0x8000000000000000)
    },
    /* 16: P_generation_zero */ {
        UINT64_C(0x3), UINT64_C(0x2), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x0),
        UINT64_C(0x0)
    },
    /* 17: Q_change_zero */ {
        UINT64_C(0x8), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x7), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0xb), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0xd), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0x11), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x13), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x17), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x780), UINT64_C(0x1), UINT64_C(0x438), UINT64_C(0x1),
        UINT64_C(0x4038000000000000)
    },
    /* 18: R_no_objects */ {
        UINT64_C(0x3), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0)
    },
    /* 19: T_max */ {
        UINT64_C(0x8), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x1), UINT64_C(0x0), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1), UINT64_C(0xffffffffffffffff), UINT64_C(0x1),
        UINT64_C(0x5265c00), UINT64_C(0x1), UINT64_C(0x8000), UINT64_C(0x1), UINT64_C(0x1), UINT64_C(0x1),
        UINT64_C(0x408f400000000000)
    },
    /* 20: refusal_zero */ {
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0), UINT64_C(0x0),
        UINT64_C(0x0)
    }
};

typedef struct {
    uint64_t abi;
    size_t before_index;
    size_t sample_index;
    uint64_t status;
    size_t after_index;
    size_t snapshot_index;
} liveness_c_literal_case_t;
static const liveness_c_literal_case_t liveness_c_cases[64] = {
    /* 0: covered_initial_full_width */ {UINT64_C(0x1), 0, 1, UINT64_C(0x0), 1, 0},
    /* 1: covered_plateau_full_width */ {UINT64_C(0x1), 1, 1, UINT64_C(0x0), 1, 1},
    /* 2: all_six_distinct_deltas_negative_zero */ {UINT64_C(0x1), 1, 2, UINT64_C(0x0), 2, 2},
    /* 3: clock_reversal_retains_full_width_recent_change */ {UINT64_C(0x1), 2, 3, UINT64_C(0x0), 3, 3},
    /* 4: timing_exact */ {UINT64_C(0x1), 4, 5, UINT64_C(0x0), 5, 4},
    /* 5: timing_ns_after */ {UINT64_C(0x1), 4, 6, UINT64_C(0x0), 6, 5},
    /* 6: timing_ms_last */ {UINT64_C(0x1), 4, 7, UINT64_C(0x0), 7, 6},
    /* 7: timing_ms_after */ {UINT64_C(0x1), 4, 8, UINT64_C(0x0), 8, 7},
    /* 8: decode_stalled_inbound_only */ {UINT64_C(0x1), 2, 9, UINT64_C(0x0), 9, 8},
    /* 9: presentation_stalled_signed_dimension_bounds_positive_zero */ {UINT64_C(0x1), 9, 10, UINT64_C(0x0), 10, 9},
    /* 10: metadata_only_empty_counters_inf_and_invalid_dimensions */ {UINT64_C(0x1), 10, 11, UINT64_C(0x0), 11, 10},
    /* 11: track_missing_generation_change */ {UINT64_C(0x1), 11, 12, UINT64_C(0x0), 12, 11},
    /* 12: intentional_cover_precedes_track_and_reset */ {UINT64_C(0x1), 12, 13, UINT64_C(0x0), 13, 12},
    /* 13: privacy_cover */ {UINT64_C(0x1), 13, 14, UINT64_C(0x0), 14, 13},
    /* 14: hidden_cover */ {UINT64_C(0x1), 14, 15, UINT64_C(0x0), 15, 14},
    /* 15: counter_regression_resets_all_deltas_and_recent_change */ {UINT64_C(0x1), 2, 16, UINT64_C(0x0), 16, 15},
    /* 16: generation_change_precedes_regression_nan_raw_history */ {UINT64_C(0x1), 2, 17, UINT64_C(0x0), 17, 16},
    /* 17: present_zero_change_clock_is_not_absent */ {UINT64_C(0x1), 18, 19, UINT64_C(0x0), 19, 17},
    /* 18: no_objects_is_not_empty_inbound */ {UINT64_C(0x1), 0, 20, UINT64_C(0x0), 20, 18},
    /* 19: empty_inbound_is_not_absent_object */ {UINT64_C(0x1), 0, 21, UINT64_C(0x0), 21, 18},
    /* 20: maximum_deltas_age_clamp_recent_clock */ {UINT64_C(0x1), 22, 23, UINT64_C(0x0), 23, 19},
    /* 21: fps_above_upper */ {UINT64_C(0x1), 0, 24, UINT64_C(0x0), 24, 18},
    /* 22: fps_negative */ {UINT64_C(0x1), 0, 25, UINT64_C(0x0), 25, 18},
    /* 23: fps_negative_inf */ {UINT64_C(0x1), 0, 26, UINT64_C(0x0), 26, 18},
    /* 24: abi_0 */ {UINT64_C(0x0), 2, 2, UINT64_C(0x3), 2, 20},
    /* 25: abi_2 */ {UINT64_C(0x2), 2, 2, UINT64_C(0x3), 2, 20},
    /* 26: abi_18446744073709551615 */ {UINT64_C(0xffffffffffffffff), 2, 2, UINT64_C(0x3), 2, 20},
    /* 27: bad_before_presence_2 */ {UINT64_C(0x1), 27, 2, UINT64_C(0x3), 27, 20},
    /* 28: bad_clock_presence_2 */ {UINT64_C(0x1), 28, 2, UINT64_C(0x3), 28, 20},
    /* 29: bad_clock_presence_max */ {UINT64_C(0x1), 29, 2, UINT64_C(0x3), 29, 20},
    /* 30: bad_clock_absent_payload */ {UINT64_C(0x1), 30, 2, UINT64_C(0x3), 30, 20},
    /* 31: bad_absent_before_generation */ {UINT64_C(0x1), 31, 2, UINT64_C(0x3), 31, 20},
    /* 32: bad_absent_before_full */ {UINT64_C(0x1), 32, 2, UINT64_C(0x3), 32, 20},
    /* 33: bad_absent_before_clock_0 */ {UINT64_C(0x1), 33, 2, UINT64_C(0x3), 33, 20},
    /* 34: bad_absent_before_clock_18446744073709551615 */ {UINT64_C(0x1), 34, 2, UINT64_C(0x3), 34, 20},
    /* 35: absent_inbound_payload_0 */ {UINT64_C(0x1), 2, 28, UINT64_C(0x3), 2, 20},
    /* 36: inbound_optional_0_presence_2 */ {UINT64_C(0x1), 2, 29, UINT64_C(0x3), 2, 20},
    /* 37: inbound_optional_0_absent_payload */ {UINT64_C(0x1), 2, 30, UINT64_C(0x3), 2, 20},
    /* 38: absent_inbound_payload_1 */ {UINT64_C(0x1), 2, 31, UINT64_C(0x3), 2, 20},
    /* 39: inbound_optional_1_presence_2 */ {UINT64_C(0x1), 2, 32, UINT64_C(0x3), 2, 20},
    /* 40: inbound_optional_1_absent_payload */ {UINT64_C(0x1), 2, 33, UINT64_C(0x3), 2, 20},
    /* 41: absent_inbound_payload_2 */ {UINT64_C(0x1), 2, 34, UINT64_C(0x3), 2, 20},
    /* 42: inbound_optional_2_presence_2 */ {UINT64_C(0x1), 2, 35, UINT64_C(0x3), 2, 20},
    /* 43: inbound_optional_2_absent_payload */ {UINT64_C(0x1), 2, 36, UINT64_C(0x3), 2, 20},
    /* 44: absent_inbound_payload_3 */ {UINT64_C(0x1), 2, 37, UINT64_C(0x3), 2, 20},
    /* 45: inbound_optional_3_presence_2 */ {UINT64_C(0x1), 2, 38, UINT64_C(0x3), 2, 20},
    /* 46: inbound_optional_3_absent_payload */ {UINT64_C(0x1), 2, 39, UINT64_C(0x3), 2, 20},
    /* 47: absent_inbound_payload_4 */ {UINT64_C(0x1), 2, 40, UINT64_C(0x3), 2, 20},
    /* 48: inbound_optional_4_presence_2 */ {UINT64_C(0x1), 2, 41, UINT64_C(0x3), 2, 20},
    /* 49: inbound_optional_4_absent_payload */ {UINT64_C(0x1), 2, 42, UINT64_C(0x3), 2, 20},
    /* 50: absent_inbound_payload_5 */ {UINT64_C(0x1), 2, 43, UINT64_C(0x3), 2, 20},
    /* 51: inbound_optional_5_presence_2 */ {UINT64_C(0x1), 2, 44, UINT64_C(0x3), 2, 20},
    /* 52: inbound_optional_5_absent_payload */ {UINT64_C(0x1), 2, 45, UINT64_C(0x3), 2, 20},
    /* 53: bad_track */ {UINT64_C(0x1), 2, 46, UINT64_C(0x3), 2, 20},
    /* 54: bad_cover */ {UINT64_C(0x1), 2, 47, UINT64_C(0x3), 2, 20},
    /* 55: bad_inbound_presence */ {UINT64_C(0x1), 2, 48, UINT64_C(0x3), 2, 20},
    /* 56: bad_render_presence */ {UINT64_C(0x1), 2, 49, UINT64_C(0x3), 2, 20},
    /* 57: absent_render_payload_0 */ {UINT64_C(0x1), 2, 50, UINT64_C(0x3), 2, 20},
    /* 58: absent_render_payload_1 */ {UINT64_C(0x1), 2, 51, UINT64_C(0x3), 2, 20},
    /* 59: absent_render_payload_2 */ {UINT64_C(0x1), 2, 52, UINT64_C(0x3), 2, 20},
    /* 60: absent_render_payload_3 */ {UINT64_C(0x1), 2, 53, UINT64_C(0x3), 2, 20},
    /* 61: absent_render_payload_4 */ {UINT64_C(0x1), 2, 54, UINT64_C(0x3), 2, 20},
    /* 62: absent_render_payload_5 */ {UINT64_C(0x1), 2, 55, UINT64_C(0x3), 2, 20},
    /* 63: bad_nested_previous */ {UINT64_C(0x1), 35, 2, UINT64_C(0x3), 35, 20}
};

static beluga_core_screen_liveness_sample_t liveness_c_sample_from_words(const uint64_t words[24]) {
    beluga_core_screen_liveness_sample_t out = {0};
    out.generation = words[0];
    out.observed_at = words[1];
    out.track_attached = words[2];
    out.cover = words[3];
    out.inbound_present = words[4];
    out.inbound_bytes.present = words[5];
    out.inbound_bytes.value = words[6];
    out.inbound_packets.present = words[7];
    out.inbound_packets.value = words[8];
    out.decoded_frames.present = words[9];
    out.decoded_frames.value = words[10];
    out.inbound_width.present = words[11];
    out.inbound_width.value = words[12];
    out.inbound_height.present = words[13];
    out.inbound_height.value = words[14];
    out.frames_per_second_bits.present = words[15];
    out.frames_per_second_bits.value = words[16];
    out.render_present = words[17];
    out.presented_frames = words[18];
    out.content_samples = words[19];
    out.content_changes = words[20];
    out.presented_at = words[21];
    out.render_width_bits = words[22];
    out.render_height_bits = words[23];
    return out;
}
static void liveness_c_sample_words(beluga_core_screen_liveness_sample_t sample, uint64_t out[24]) {
    out[0] = sample.generation;
    out[1] = sample.observed_at;
    out[2] = sample.track_attached;
    out[3] = sample.cover;
    out[4] = sample.inbound_present;
    out[5] = sample.inbound_bytes.present;
    out[6] = sample.inbound_bytes.value;
    out[7] = sample.inbound_packets.present;
    out[8] = sample.inbound_packets.value;
    out[9] = sample.decoded_frames.present;
    out[10] = sample.decoded_frames.value;
    out[11] = sample.inbound_width.present;
    out[12] = sample.inbound_width.value;
    out[13] = sample.inbound_height.present;
    out[14] = sample.inbound_height.value;
    out[15] = sample.frames_per_second_bits.present;
    out[16] = sample.frames_per_second_bits.value;
    out[17] = sample.render_present;
    out[18] = sample.presented_frames;
    out[19] = sample.content_samples;
    out[20] = sample.content_changes;
    out[21] = sample.presented_at;
    out[22] = sample.render_width_bits;
    out[23] = sample.render_height_bits;
}
static beluga_core_screen_liveness_state_t liveness_c_state_from_words(const uint64_t words[27]) {
    beluga_core_screen_liveness_state_t out = {0};
    out.previous_present = words[0];
    out.last_change_at.present = words[1];
    out.last_change_at.value = words[2];
    out.previous = liveness_c_sample_from_words(words + 3);
    return out;
}
static void liveness_c_state_words(beluga_core_screen_liveness_state_t state, uint64_t out[27]) {
    out[0] = state.previous_present;
    out[1] = state.last_change_at.present;
    out[2] = state.last_change_at.value;
    liveness_c_sample_words(state.previous, out + 3);
}
static void liveness_c_snapshot_words(beluga_core_screen_liveness_snapshot_t snapshot, uint64_t out[37]) {
    out[0] = snapshot.liveness;
    out[1] = snapshot.reset_reason;
    out[2] = snapshot.generation;
    out[3] = snapshot.track_attached;
    out[4] = snapshot.cover;
    out[5] = snapshot.inbound_bytes.present;
    out[6] = snapshot.inbound_bytes.value;
    out[7] = snapshot.inbound_byte_delta.present;
    out[8] = snapshot.inbound_byte_delta.value;
    out[9] = snapshot.inbound_packets.present;
    out[10] = snapshot.inbound_packets.value;
    out[11] = snapshot.inbound_packet_delta.present;
    out[12] = snapshot.inbound_packet_delta.value;
    out[13] = snapshot.decoded_frames.present;
    out[14] = snapshot.decoded_frames.value;
    out[15] = snapshot.decoded_frame_delta.present;
    out[16] = snapshot.decoded_frame_delta.value;
    out[17] = snapshot.presented_frames.present;
    out[18] = snapshot.presented_frames.value;
    out[19] = snapshot.presented_frame_delta.present;
    out[20] = snapshot.presented_frame_delta.value;
    out[21] = snapshot.content_samples.present;
    out[22] = snapshot.content_samples.value;
    out[23] = snapshot.content_sample_delta.present;
    out[24] = snapshot.content_sample_delta.value;
    out[25] = snapshot.content_changes.present;
    out[26] = snapshot.content_changes.value;
    out[27] = snapshot.content_change_delta.present;
    out[28] = snapshot.content_change_delta.value;
    out[29] = snapshot.presentation_age_ms.present;
    out[30] = snapshot.presentation_age_ms.value;
    out[31] = snapshot.frame_width.present;
    out[32] = snapshot.frame_width.value;
    out[33] = snapshot.frame_height.present;
    out[34] = snapshot.frame_height.value;
    out[35] = snapshot.frames_per_second_bits.present;
    out[36] = snapshot.frames_per_second_bits.value;
}
static void liveness_c_result_words(beluga_core_screen_liveness_result_t result, uint64_t out[67]) {
    out[0] = result.abi_version;
    out[1] = result.status;
    out[2] = result.reserved;
    liveness_c_state_words(result.state, out + 3);
    liveness_c_snapshot_words(result.snapshot, out + 30);
}

void screen_liveness_full_custody_smoke(void) {
    /* Keep the frozen original architecture/layout behavior prefix intact. */
    screen_liveness_smoke();
    for (size_t index = 0; index < sizeof(liveness_c_cases) / sizeof(liveness_c_cases[0]); ++index) {
        const liveness_c_literal_case_t row = liveness_c_cases[index];
        assert(row.before_index < sizeof(liveness_c_states) / sizeof(liveness_c_states[0]));
        assert(row.after_index < sizeof(liveness_c_states) / sizeof(liveness_c_states[0]));
        assert(row.sample_index < sizeof(liveness_c_samples) / sizeof(liveness_c_samples[0]));
        assert(row.snapshot_index < sizeof(liveness_c_snapshots) / sizeof(liveness_c_snapshots[0]));
        beluga_core_screen_liveness_state_t before = liveness_c_state_from_words(liveness_c_states[row.before_index]);
        beluga_core_screen_liveness_sample_t sample = liveness_c_sample_from_words(liveness_c_samples[row.sample_index]);

        /* Actual export first. No fallback, callback, corruption, or policy helper. */
        const beluga_core_screen_liveness_result_t result = beluga_core_screen_liveness_observe(row.abi, before, sample);
        uint64_t actual[67] = {0}, expected[67] = {0}, unchanged_before[27] = {0}, unchanged_sample[24] = {0};
        liveness_c_result_words(result, actual);
        expected[0] = 1;
        expected[1] = row.status;
        expected[2] = 0;
        for (size_t word = 0; word < 27; ++word) expected[word + 3] = liveness_c_states[row.after_index][word];
        for (size_t word = 0; word < 37; ++word) expected[word + 30] = liveness_c_snapshots[row.snapshot_index][word];
        for (size_t word = 0; word < 67; ++word) assert(actual[word] == expected[word]);
        liveness_c_state_words(before, unchanged_before);
        liveness_c_sample_words(sample, unchanged_sample);
        for (size_t word = 0; word < 27; ++word) assert(unchanged_before[word] == liveness_c_states[row.before_index][word]);
        for (size_t word = 0; word < 24; ++word) assert(unchanged_sample[word] == liveness_c_samples[row.sample_index][word]);
    }
    /* No PASS marker here; root must emit it only after this entrypoint returns. */
}

/* Private unexecuted addition: place before the existing C main, then insert
 * c_main_call_addition.c after its existing final screen-liveness marker.
 * Uses the existing includes; every exported input and output is by value. */
#define UO_LAYOUT(type, size) \
    _Static_assert(sizeof(type) == size, "update operation " #type " size"); \
    _Static_assert(_Alignof(type) == 4, "update operation " #type " alignment")
#define UO_OFFSET(type, field, offset) \
    _Static_assert(offsetof(type, field) == offset, "update operation " #field " offset")
UO_LAYOUT(BelugaUpdateOperationState, 40);
UO_OFFSET(BelugaUpdateOperationState, abi_version, 0);
UO_OFFSET(BelugaUpdateOperationState, reserved, 4);
UO_OFFSET(BelugaUpdateOperationState, stage, 8);
UO_OFFSET(BelugaUpdateOperationState, broker_present, 12);
UO_OFFSET(BelugaUpdateOperationState, candidate_present, 16);
UO_OFFSET(BelugaUpdateOperationState, recorded_readiness_present, 20);
UO_OFFSET(BelugaUpdateOperationState, installed_fresh, 24);
UO_OFFSET(BelugaUpdateOperationState, readiness_fresh, 28);
UO_OFFSET(BelugaUpdateOperationState, challenge_present, 32);
UO_OFFSET(BelugaUpdateOperationState, reserved_tail, 36);
UO_LAYOUT(BelugaUpdateOperationEvent, 40);
UO_OFFSET(BelugaUpdateOperationEvent, opcode, 0);
UO_OFFSET(BelugaUpdateOperationEvent, reserved, 4);
UO_OFFSET(BelugaUpdateOperationEvent, fact0, 8);
UO_OFFSET(BelugaUpdateOperationEvent, fact1, 12);
UO_OFFSET(BelugaUpdateOperationEvent, fact2, 16);
UO_OFFSET(BelugaUpdateOperationEvent, fact3, 20);
UO_OFFSET(BelugaUpdateOperationEvent, fact4, 24);
UO_OFFSET(BelugaUpdateOperationEvent, fact5, 28);
UO_OFFSET(BelugaUpdateOperationEvent, fact6, 32);
UO_OFFSET(BelugaUpdateOperationEvent, reserved_tail, 36);
UO_LAYOUT(BelugaUpdateOperationResult, 56);
UO_OFFSET(BelugaUpdateOperationResult, candidate_state, 0);
UO_OFFSET(BelugaUpdateOperationResult, decision, 40);
UO_OFFSET(BelugaUpdateOperationResult, action, 44);
UO_OFFSET(BelugaUpdateOperationResult, predicate, 48);
UO_OFFSET(BelugaUpdateOperationResult, reserved, 52);
#undef UO_LAYOUT
#undef UO_OFFSET

static BelugaUpdateOperationState uo_state(uint32_t stage, uint32_t broker,
    uint32_t candidate, uint32_t recorded, uint32_t installed,
    uint32_t readiness, uint32_t challenge) {
    return (BelugaUpdateOperationState){1, 0, stage, broker, candidate,
        recorded, installed, readiness, challenge, 0};
}
static BelugaUpdateOperationEvent uo_event(uint32_t opcode, uint32_t f0,
    uint32_t f1, uint32_t f2, uint32_t f3, uint32_t f4, uint32_t f5, uint32_t f6) {
    return (BelugaUpdateOperationEvent){opcode, 0, f0, f1, f2, f3, f4, f5, f6, 0};
}
static void uo_check(uint32_t abi, BelugaUpdateOperationState before,
    BelugaUpdateOperationEvent input, BelugaUpdateOperationState expected,
    uint32_t decision, uint32_t action, uint32_t predicate) {
    const BelugaUpdateOperationState saved = before;
    const BelugaUpdateOperationEvent saved_input = input;
    const BelugaUpdateOperationResult actual = beluga_core_update_operation_step(abi, before, input);
    assert(memcmp(&actual.candidate_state, &expected, sizeof(expected)) == 0);
    assert(actual.decision == decision && actual.action == action &&
        actual.predicate == predicate && actual.reserved == 0);
    assert(memcmp(&before, &saved, sizeof(before)) == 0);
    assert(memcmp(&input, &saved_input, sizeof(input)) == 0);
}
static void uo_invalid(uint32_t abi, BelugaUpdateOperationState before,
    BelugaUpdateOperationEvent input) {
    uo_check(abi, before, input, before, 2, 0, 0);
}
static BelugaUpdateOperationEvent uo_fact(BelugaUpdateOperationEvent input,
    uint32_t slot, uint32_t value) {
    switch (slot) {
        case 0: input.fact0 = value; break;
        case 1: input.fact1 = value; break;
        case 2: input.fact2 = value; break;
        case 3: input.fact3 = value; break;
        case 4: input.fact4 = value; break;
        case 5: input.fact5 = value; break;
        case 6: input.fact6 = value; break;
        default: assert(0); break;
    }
    return input;
}
static void update_operation_smoke(void) {
    /* Literal expected plans; constructors only create DTOs, not an oracle. */
    const BelugaUpdateOperationState prepared = uo_state(0, 0, 0, 0, 0, 0, 0);
    const BelugaUpdateOperationState broker = uo_state(0, 1, 0, 0, 0, 0, 0);
    const BelugaUpdateOperationState armed = uo_state(1, 1, 0, 0, 0, 0, 0);
    const BelugaUpdateOperationState candidate = uo_state(1, 1, 1, 0, 0, 0, 0);
    const BelugaUpdateOperationState installed = uo_state(2, 1, 1, 0, 1, 0, 0);
    const BelugaUpdateOperationState challenged = uo_state(2, 1, 1, 0, 1, 0, 1);
    const BelugaUpdateOperationState ready = uo_state(3, 1, 1, 1, 1, 1, 0);
    const BelugaUpdateOperationState restored = uo_state(3, 1, 1, 1, 0, 0, 0);
    const BelugaUpdateOperationEvent bind_broker = uo_event(0, 1, 1, 1, 1, 0, 0, 0);
    const BelugaUpdateOperationEvent bind_candidate = uo_event(1, 1, 1, 1, 1, 0, 0, 0);
    const BelugaUpdateOperationEvent completion = uo_event(3, 1, 1, 0, 0, 0, 0, 0);
    const BelugaUpdateOperationEvent challenge = uo_event(4, 1, 1, 1, 1, 1, 1, 0);
    const BelugaUpdateOperationEvent preflight = uo_event(5, 1, 1, 1, 1, 1, 1, 0);
    const BelugaUpdateOperationEvent commit = uo_event(6, 1, 1, 1, 1, 1, 1, 1);
    uo_check(1, prepared, bind_broker, broker, 0, 1, 0);
    uo_check(1, broker, bind_broker, broker, 1, 0, 0);
    uo_check(1, broker, uo_event(2, 1, 0, 0, 0, 0, 0, 0), armed, 0, 3, 0);
    uo_check(1, armed, bind_candidate, candidate, 0, 2, 0);
    uo_check(1, candidate, uo_fact(completion, 1, 0), candidate, 1, 0, 0);
    uo_check(1, candidate, completion, installed, 0, 4, 0);
    uo_check(1, installed, challenge, challenged, 0, 5, 0);
    uo_check(1, challenged, preflight, challenged, 0, 6, 0);
    uo_check(1, challenged, uo_fact(preflight, 5, 0), challenged, 1, 0, 0);
    uo_check(1, challenged, uo_fact(commit, 6, 0), challenged, 1, 0, 0);
    uo_check(1, challenged, commit, ready, 0, 7, 0);
    uo_check(1, ready, commit, ready, 1, 0, 0); /* one-use challenge */
    uo_check(1, ready, uo_event(7, 0, 0, 0, 0, 0, 0, 0), ready, 0, 0, 0);
    uo_check(1, ready, uo_event(8, 0, 0, 0, 0, 0, 0, 0), ready, 0, 0, 0);
    for (uint32_t opcode = 9; opcode <= 10; ++opcode) {
        uo_check(1, ready, uo_event(opcode, 0, 0, 0, 0, 0, 0, 0), restored, 0, 8, 0);
        uo_check(1, challenged, uo_event(opcode, 0, 0, 0, 0, 0, 0, 0),
            uo_state(2, 1, 1, 0, 0, 0, 0), 0, 8, 0);
    }
    uo_check(1, prepared, uo_event(11, 0, 0, 0, 0, 0, 0, 0), prepared, 0, 0, 0);
    uo_check(1, ready, uo_event(11, 0, 0, 0, 0, 0, 0, 0), ready, 0, 0, 1);
    uo_check(1, ready, uo_event(12, 0, 0, 0, 0, 0, 0, 0), ready, 0, 0, 1);
    uo_check(1, restored, uo_event(12, 0, 0, 0, 0, 0, 0, 0), restored, 0, 0, 0);
    uo_check(1, ready, uo_event(13, 0, 0, 0, 0, 0, 0, 0), ready, 0, 0, 0);
    uo_check(1, restored, completion, uo_state(3, 1, 1, 1, 1, 0, 0), 0, 4, 0);
    /* Closed scalar projections deliberately do not invent a whole-record invariant. */
    uo_check(1, uo_state(3, 1, 0, 0, 1, 1, 0), uo_event(12, 0, 0, 0, 0, 0, 0, 0),
        uo_state(3, 1, 0, 0, 1, 1, 0), 0, 0, 1);

    for (uint32_t i = 0; i < 3; ++i) {
        const uint32_t bad = i == 0 ? 0 : i == 1 ? 2 : UINT32_MAX;
        uo_invalid(bad, challenged, commit);
        BelugaUpdateOperationState raw = challenged; raw.abi_version = bad;
        uo_invalid(1, raw, commit);
    }
#define UO_BAD_STATE(field, value) do { \
    BelugaUpdateOperationState raw = challenged; raw.field = value; \
    uo_invalid(1, raw, commit); \
} while (0)
    UO_BAD_STATE(stage, 4); UO_BAD_STATE(stage, UINT32_MAX);
    for (uint32_t i = 0; i < 2; ++i) {
        const uint32_t bad = i == 0 ? 2 : UINT32_MAX;
        UO_BAD_STATE(broker_present, bad); UO_BAD_STATE(candidate_present, bad);
        UO_BAD_STATE(recorded_readiness_present, bad); UO_BAD_STATE(installed_fresh, bad);
        UO_BAD_STATE(readiness_fresh, bad); UO_BAD_STATE(challenge_present, bad);
    }
    for (uint32_t bit = 0; bit < 32; ++bit) {
        const uint32_t bad = UINT32_C(1) << bit;
        UO_BAD_STATE(reserved, bad); UO_BAD_STATE(reserved_tail, bad);
        BelugaUpdateOperationEvent input = commit; input.reserved = bad;
        uo_invalid(1, challenged, input); input = commit; input.reserved_tail = bad;
        uo_invalid(1, challenged, input);
    }
#undef UO_BAD_STATE
    for (uint32_t slot = 0; slot < 7; ++slot) {
        uo_invalid(1, challenged, uo_fact(commit, slot, 2));
        uo_invalid(1, challenged, uo_fact(commit, slot, UINT32_MAX));
    }
    BelugaUpdateOperationEvent input = commit; input.opcode = 14;
    uo_invalid(1, challenged, input); input.opcode = UINT32_MAX;
    uo_invalid(1, challenged, input);
    const uint32_t used[14] = {4, 4, 1, 2, 6, 6, 7, 0, 0, 0, 0, 0, 0, 0};
    for (uint32_t opcode = 0; opcode < 14; ++opcode) {
        for (uint32_t slot = used[opcode]; slot < 7; ++slot) {
            uo_invalid(1, challenged, uo_fact(uo_event(opcode, 0, 0, 0, 0, 0, 0, 0), slot, 1));
        }
    }
    /* The caller must emit the new marker only after this entrypoint returns. */
}

/* Add this helper before the existing main; invoke only after tier_demand_smoke(). */
static void media_command_gate_smoke(void) {
    _Static_assert(sizeof(beluga_core_media_command_gate_state_t) == 24, "media gate state size");
    _Static_assert(_Alignof(beluga_core_media_command_gate_state_t) == 8, "media gate state alignment");
    _Static_assert(sizeof(beluga_core_media_command_gate_event_t) == 32, "media gate event size");
    _Static_assert(_Alignof(beluga_core_media_command_gate_event_t) == 8, "media gate event alignment");
    _Static_assert(sizeof(beluga_core_media_command_gate_result_t) == 40, "media gate result size");
    _Static_assert(_Alignof(beluga_core_media_command_gate_result_t) == 8, "media gate result alignment");
    _Static_assert(offsetof(beluga_core_media_command_gate_state_t, abi_version) == 0, "media gate state ABI offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_state_t, is_open) == 4, "media gate open offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_state_t, lifecycle) == 8, "media gate lifecycle offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_state_t, command_epoch) == 16, "media gate epoch offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_event_t, opcode) == 0, "media gate opcode offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_event_t, context_is_current) == 4, "media gate membership offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_event_t, reserved0) == 8, "media gate reserved0 offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_event_t, reserved1) == 12, "media gate reserved1 offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_event_t, candidate_lifecycle) == 16, "media gate candidate lifecycle offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_event_t, candidate_command_epoch) == 24, "media gate candidate epoch offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_result_t, abi_version) == 0, "media gate result ABI offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_result_t, status) == 4, "media gate status offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_result_t, allowed) == 8, "media gate grant offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_result_t, reserved) == 12, "media gate result reserved offset");
    _Static_assert(offsetof(beluga_core_media_command_gate_result_t, state) == 16, "media gate successor offset");

    const beluga_core_media_command_gate_state_t initial = {1, 0, 0, 0};
    const beluga_core_media_command_gate_state_t maximum = {1, 0, UINT64_MAX, UINT64_MAX};
    const beluga_core_media_command_gate_event_t open = {0, 0, 0, 0, 0, 0};
    const beluga_core_media_command_gate_event_t close = {1, 0, 0, 0, 0, 0};
    const beluga_core_media_command_gate_event_t invalidate = {2, 0, 0, 0, 0, 0};
    const beluga_core_media_command_gate_event_t lifecycle_zero = {3, 0, 0, 0, 0, 0};
    const beluga_core_media_command_gate_event_t capture = {4, 1, 0, 0, 0, 0};
    const beluga_core_media_command_gate_event_t admit_zero = {5, 1, 0, 0, 0, 0};
    beluga_core_media_command_gate_result_t result = beluga_core_media_command_gate_step(initial, capture);
    assert(result.abi_version == 1 && result.status == 1 && result.allowed == 0 && result.reserved == 0);
    assert(memcmp(&result.state, &initial, sizeof(initial)) == 0);
    assert(beluga_core_media_command_gate_result_is_valid(initial, capture, result) == 1);

    result = beluga_core_media_command_gate_step(maximum, open);
    const beluga_core_media_command_gate_state_t wrapped = {1, 1, 0, 0};
    assert(result.abi_version == 1 && result.status == 1 && result.allowed == 0 && result.reserved == 0);
    assert(memcmp(&result.state, &wrapped, sizeof(wrapped)) == 0);
    assert(beluga_core_media_command_gate_result_is_valid(maximum, open, result) == 1);
    result = beluga_core_media_command_gate_step(wrapped, lifecycle_zero);
    assert(result.status == 1 && result.allowed == 1 && result.reserved == 0);
    assert(memcmp(&result.state, &wrapped, sizeof(wrapped)) == 0);
    assert(beluga_core_media_command_gate_result_is_valid(wrapped, lifecycle_zero, result) == 1);
    result.state.command_epoch = 1; /* Query-only copied state must also be verified. */
    assert(beluga_core_media_command_gate_result_is_valid(wrapped, lifecycle_zero, result) == 0);

    result = beluga_core_media_command_gate_step(wrapped, admit_zero);
    assert(result.status == 1 && result.allowed == 1);
    assert(beluga_core_media_command_gate_result_is_valid(wrapped, admit_zero, result) == 1);
    result = beluga_core_media_command_gate_step(wrapped, invalidate);
    const beluga_core_media_command_gate_state_t invalidated = {1, 1, 0, 1};
    assert(result.status == 1 && result.allowed == 0);
    assert(memcmp(&result.state, &invalidated, sizeof(invalidated)) == 0);
    result = beluga_core_media_command_gate_step(invalidated, lifecycle_zero);
    assert(result.status == 1 && result.allowed == 1);
    result = beluga_core_media_command_gate_step(invalidated, admit_zero);
    assert(result.status == 1 && result.allowed == 0);
    beluga_core_media_command_gate_event_t admit_current = admit_zero;
    admit_current.candidate_command_epoch = 1;
    result = beluga_core_media_command_gate_step(invalidated, admit_current);
    assert(result.status == 1 && result.allowed == 1);
    result = beluga_core_media_command_gate_step(invalidated, close);
    const beluga_core_media_command_gate_state_t closed = {1, 0, 1, 2};
    assert(result.status == 1 && result.allowed == 0);
    assert(memcmp(&result.state, &closed, sizeof(closed)) == 0);

    beluga_core_media_command_gate_event_t bad = capture;
    bad.context_is_current = 2;
    result = beluga_core_media_command_gate_step(wrapped, bad);
    const beluga_core_media_command_gate_result_t denied = {1, 0, 0, 0, {1, 0, 0, 0}};
    assert(memcmp(&result, &denied, sizeof(denied)) == 0);
    assert(beluga_core_media_command_gate_result_is_valid(wrapped, bad, result) == 0);
    bad = open; bad.candidate_lifecycle = 1;
    result = beluga_core_media_command_gate_step(wrapped, bad);
    assert(memcmp(&result, &denied, sizeof(denied)) == 0);
    assert(beluga_core_media_command_gate_result_is_valid(wrapped, bad, result) == 0);
    puts("BelugaCore C media command gate ABI PASS: exact copied layouts, wrapping epochs and checked admission");
}

/* Private additive smoke: insert helper before main, call only after prior media-command marker. */
static beluga_core_screen_suspension_event_t suspension_bound_event(uint32_t op, beluga_core_screen_suspension_state_t state) {
    beluga_core_screen_suspension_event_t event = {0};
    event.opcode = op; event.peer_generation = state.peer_generation;
    event.visibility_epoch = state.visibility_epoch; event.recovery_epoch = state.recovery_epoch;
    return event;
}
static beluga_core_screen_suspension_event_t suspension_proof_event(uint32_t op, uint32_t facts, beluga_core_screen_suspension_state_t state) {
    beluga_core_screen_suspension_event_t event = suspension_bound_event(op, state);
    event.native_facts = facts; event.notice_screen_request_id = state.screen_request_id;
    event.notice_generation = state.suspension_generation; return event;
}
static beluga_core_screen_suspension_result_t suspension_checked_step(beluga_core_screen_suspension_state_t state, beluga_core_screen_suspension_event_t event) {
    beluga_core_screen_suspension_result_t result = beluga_core_screen_suspension_step(state, event);
    assert(result.abi_version == 1 && result.status == 1 && result.reserved == 0);
    assert(beluga_core_screen_suspension_result_is_valid(state, event, result) == 1);
    return result;
}
static void screen_suspension_smoke(void) {
    _Static_assert(sizeof(beluga_core_screen_suspension_state_t) == 88, "suspension state size");
    _Static_assert(_Alignof(beluga_core_screen_suspension_state_t) == 8, "suspension state alignment");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, abi_version) == 0, "suspension state abi_version offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, phase) == 4, "suspension state phase offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, next_generation) == 8, "suspension state next_generation offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, screen_request_id) == 16, "suspension state screen_request_id offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, suspension_generation) == 24, "suspension state suspension_generation offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, peer_generation) == 32, "suspension state peer_generation offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, visibility_epoch) == 40, "suspension state visibility_epoch offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, recovery_epoch) == 48, "suspension state recovery_epoch offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, prior_screen_request_id) == 56, "suspension state prior_screen_request_id offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, prior_suspension_generation) == 64, "suspension state prior_suspension_generation offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, cover_confirmed) == 72, "suspension state cover_confirmed offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, inactive_confirmed) == 76, "suspension state inactive_confirmed offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, custody_mask) == 80, "suspension state custody_mask offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_state_t, reserved) == 84, "suspension state reserved offset");
    _Static_assert(sizeof(beluga_core_screen_suspension_event_t) == 64, "suspension event size");
    _Static_assert(_Alignof(beluga_core_screen_suspension_event_t) == 8, "suspension event alignment");
    _Static_assert(offsetof(beluga_core_screen_suspension_event_t, opcode) == 0, "suspension event opcode offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_event_t, flags) == 4, "suspension event flags offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_event_t, native_facts) == 8, "suspension event native_facts offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_event_t, reserved) == 12, "suspension event reserved offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_event_t, screen_request_id) == 16, "suspension event screen_request_id offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_event_t, peer_generation) == 24, "suspension event peer_generation offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_event_t, visibility_epoch) == 32, "suspension event visibility_epoch offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_event_t, recovery_epoch) == 40, "suspension event recovery_epoch offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_event_t, notice_screen_request_id) == 48, "suspension event notice_screen_request_id offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_event_t, notice_generation) == 56, "suspension event notice_generation offset");
    _Static_assert(sizeof(beluga_core_screen_suspension_result_t) == 128, "suspension result size");
    _Static_assert(_Alignof(beluga_core_screen_suspension_result_t) == 8, "suspension result alignment");
    _Static_assert(offsetof(beluga_core_screen_suspension_result_t, abi_version) == 0, "suspension result abi_version offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_result_t, status) == 4, "suspension result status offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_result_t, accepted) == 8, "suspension result accepted offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_result_t, custody_action) == 12, "suspension result custody_action offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_result_t, state) == 16, "suspension result state offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_result_t, query_flags) == 104, "suspension result query_flags offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_result_t, reserved) == 108, "suspension result reserved offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_result_t, produced_notice_screen_request_id) == 112, "suspension result produced_notice_screen_request_id offset");
    _Static_assert(offsetof(beluga_core_screen_suspension_result_t, produced_notice_generation) == 120, "suspension result produced_notice_generation offset");
    beluga_core_screen_suspension_state_t state = {0};
    state.abi_version = 1; state.next_generation = UINT64_MAX;
    beluga_core_screen_suspension_event_t event = {0};
    beluga_core_screen_suspension_result_t result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.query_flags == 0 && result.custody_action == 0);
    assert(memcmp(&state, &result.state, sizeof(state)) == 0);
    for (size_t i = 0; i < sizeof(result); i++) {
        beluga_core_screen_suspension_result_t forged = result;
        unsigned char *bytes = (unsigned char *)&forged; bytes[i] ^= 1;
        assert(beluga_core_screen_suspension_result_is_valid(state, event, forged) == 0);
    }
    event.opcode = 1; event.screen_request_id = UINT64_MAX;
    event.peer_generation = UINT64_MAX; event.visibility_epoch = UINT64_MAX - 1;
    result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.custody_action == 1 && result.query_flags == 72);
    state = result.state;
    event = suspension_bound_event(4, state); event.flags = 1;
    result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.custody_action == 3 && result.query_flags == 250);
    assert(result.produced_notice_screen_request_id == UINT64_MAX && result.produced_notice_generation == UINT64_MAX);
    assert(result.state.next_generation == 1 && result.state.custody_mask == 1);
    state = result.state;
    event = suspension_proof_event(5, 1U << 1, state);
    result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.custody_action == 0 && result.state.cover_confirmed == 1);
    assert(result.state.phase == 2 && result.state.inactive_confirmed == 0); state = result.state;
    event = suspension_proof_event(6, 1U, state); event.visibility_epoch = UINT64_MAX;
    result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.custody_action == 5 && result.query_flags == 249);
    assert(result.state.phase == 3 && result.state.visibility_epoch == UINT64_MAX); state = result.state;
    event = suspension_bound_event(7, state); event.native_facts = 1U << 2;
    result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.custody_action == 6 && result.query_flags == 253); state = result.state;
    const uint32_t proof_facts[] = {(1U << 3) | (1U << 4), 1U << 5,
        (1U << 3) | (1U << 6) | (1U << 7), (1U << 3) | (1U << 8) | (1U << 9)};
    const uint32_t proof_masks[] = {13, 21, 37, 69};
    for (uint32_t i = 0; i < 4; i++) {
        event = suspension_proof_event(8 + i, proof_facts[i], state);
        result = suspension_checked_step(state, event);
        assert(result.accepted == 1 && result.custody_action == 7 + i && result.state.phase == 5 + i);
        assert(result.state.custody_mask == proof_masks[i] && result.query_flags == 253); state = result.state;
    }
    event = suspension_proof_event(16, (1U << 3) | (1U << 10), state);
    result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.custody_action == 0 && memcmp(&state, &result.state, sizeof(state)) == 0);
    event = suspension_proof_event(12, 1U << 10, state);
    result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.custody_action == 11 && result.state.phase == 1);
    assert(result.query_flags == 248 && result.state.custody_mask == 1 && result.state.suspension_generation == UINT64_MAX);
    state = result.state;
    event = suspension_bound_event(4, state); event.flags = 1;
    result = suspension_checked_step(state, event);
    assert(result.state.prior_suspension_generation == UINT64_MAX && result.state.suspension_generation == 1);
    assert(result.state.next_generation == 2 && result.state.custody_mask == 3); state = result.state;
    event = suspension_bound_event(3, state);
    result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.custody_action == 4 && result.state.suspension_generation == UINT64_MAX);
    assert(result.state.next_generation == 2 && result.query_flags == 248); state = result.state;
    const beluga_core_screen_suspension_state_t completed = state;
    event = suspension_bound_event(14, state); event.flags = 1;
    result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.custody_action == 12 && result.state.phase == 3);
    event = suspension_proof_event(13, 1U | (1U << 11), completed);
    result = suspension_checked_step(completed, event);
    assert(result.accepted == 1 && result.custody_action == 14 && result.state.phase == 3); state = result.state;
    event = suspension_bound_event(15, state);
    result = suspension_checked_step(state, event); assert(result.accepted == 1);
    event.recovery_epoch = 1;
    result = suspension_checked_step(state, event);
    assert(result.accepted == 0 && memcmp(&state, &result.state, sizeof(state)) == 0);
    event = (beluga_core_screen_suspension_event_t){0}; event.opcode = 2;
    result = suspension_checked_step(state, event);
    assert(result.accepted == 1 && result.custody_action == 2 && result.state.phase == 0 && result.state.next_generation == 2);
    state = result.state;
    event = (beluga_core_screen_suspension_event_t){0}; event.opcode = 17;
    event.peer_generation = 1; event.visibility_epoch = 1; event.recovery_epoch = UINT64_MAX;
    result = suspension_checked_step(state, event); assert(result.accepted == 1);
    event.peer_generation = 0; result = suspension_checked_step(state, event); assert(result.accepted == 0);
    event.reserved = 1; result = beluga_core_screen_suspension_step(state, event);
    assert(result.abi_version == 1 && result.status == 0 && result.accepted == 0 && result.custody_action == 0);
    assert(result.query_flags == 0 && result.reserved == 0 && result.state.phase == 0 && result.state.next_generation == 1);
    assert(beluga_core_screen_suspension_result_is_valid(state, event, result) == 0);
    puts("BelugaCore C screen suspension ABI PASS: exact copied layouts, ordered transcript and retained provenance");
}

_Static_assert(sizeof(beluga_core_phone_catalog_input_t) == 104, "phone catalog input size");
_Static_assert(_Alignof(beluga_core_phone_catalog_input_t) == 8, "phone catalog input alignment");
_Static_assert(sizeof(beluga_core_phone_catalog_result_t) == 72, "phone catalog result size");
_Static_assert(_Alignof(beluga_core_phone_catalog_result_t) == 8, "phone catalog result alignment");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, abi_version) == 0, "phone catalog input abi_version");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, stage) == 4, "phone catalog input stage");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, operation) == 8, "phone catalog input operation");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, flags) == 12, "phone catalog input flags");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, count) == 16, "phone catalog input count");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, selected_slot) == 20, "phone catalog input selected_slot");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, target_slot) == 24, "phone catalog input target_slot");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, duplicate_axes) == 28, "phone catalog input duplicate_axes");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, previous_phase) == 32, "phone catalog input previous_phase");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, candidate_phase) == 36, "phone catalog input candidate_phase");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, previous_recovery) == 40, "phone catalog input previous_recovery");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, candidate_recovery) == 44, "phone catalog input candidate_recovery");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, reserved0) == 48, "phone catalog input reserved0");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, reserved1) == 52, "phone catalog input reserved1");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, revision) == 56, "phone catalog input revision");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, previous_outbound) == 64, "phone catalog input previous_outbound");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, candidate_outbound) == 72, "phone catalog input candidate_outbound");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, previous_accepted) == 80, "phone catalog input previous_accepted");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, candidate_accepted) == 88, "phone catalog input candidate_accepted");
_Static_assert(offsetof(beluga_core_phone_catalog_input_t, reserved2) == 96, "phone catalog input reserved2");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, abi_version) == 0, "phone catalog result abi_version");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, status) == 4, "phone catalog result status");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, error) == 8, "phone catalog result error");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, action) == 12, "phone catalog result action");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, count) == 16, "phone catalog result count");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, selected_slot) == 20, "phone catalog result selected_slot");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, target_slot) == 24, "phone catalog result target_slot");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, reserved) == 28, "phone catalog result reserved");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, slot0) == 32, "phone catalog result slot0");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, slot1) == 36, "phone catalog result slot1");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, slot2) == 40, "phone catalog result slot2");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, slot3) == 44, "phone catalog result slot3");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, slot4) == 48, "phone catalog result slot4");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, slot5) == 52, "phone catalog result slot5");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, slot6) == 56, "phone catalog result slot6");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, slot7) == 60, "phone catalog result slot7");
_Static_assert(offsetof(beluga_core_phone_catalog_result_t, revision) == 64, "phone catalog result revision");

static void phone_catalog_assert_result(
    beluga_core_phone_catalog_result_t result, uint32_t action, uint32_t count,
    uint32_t selected, uint32_t target, const uint32_t map[8], uint64_t revision) {
    assert(result.abi_version == 1 && result.status == 1 && result.error == 0);
    assert(result.action == action && result.count == count && result.selected_slot == selected);
    assert(result.target_slot == target && result.reserved == 0 && result.revision == revision);
    uint32_t actual[8] = {result.slot0,result.slot1,result.slot2,result.slot3,result.slot4,result.slot5,result.slot6,result.slot7};
    assert(memcmp(actual, map, sizeof(actual)) == 0);
}
static void phone_catalog_corrupt_every_byte(
    beluga_core_phone_catalog_input_t input, beluga_core_phone_catalog_result_t actual) {
    assert(beluga_core_phone_catalog_result_is_valid(input, actual) == 1);
    for (size_t byte = 0; byte < 72; ++byte) {
        for (unsigned bit = 0; bit < 8; ++bit) {
            beluga_core_phone_catalog_result_t mutant = actual;
            ((unsigned char *)&mutant)[byte] ^= (unsigned char)(1u << bit);
            assert(beluga_core_phone_catalog_result_is_valid(input, mutant) == 0);
        }
    }
}
static void phone_catalog_smoke(void) {
    for (uint32_t operation = 1; operation <= 4; ++operation) {
        beluga_core_phone_catalog_input_t input = {0};
        input.abi_version = 1; input.stage = 10; input.operation = operation;
        input.count = 3; input.selected_slot = 2; input.target_slot = operation == 1 ? 8 : 0;
        beluga_core_phone_catalog_result_t actual = beluga_core_phone_catalog_decide(input);
        /* Independent original append/replace/select/remove expectations AFTER actual C. */
        uint32_t expected[8] = {0,1,2,9,9,9,9,9};
        uint32_t count = 3, selected = 2;
        if (operation == 1) { expected[3] = 8; count = 4; }
        if (operation == 2) { expected[0] = 8; }
        if (operation == 3) { selected = 0; }
        if (operation == 4) { expected[0] = 1; expected[1] = 2; expected[2] = 9; count = 2; selected = 1; }
        phone_catalog_assert_result(actual, 1, count, selected, input.target_slot, expected, 0);
        phone_catalog_corrupt_every_byte(input, actual);
        input.stage = 11; input.revision = UINT64_MAX - 1;
        actual = beluga_core_phone_catalog_decide(input);
        phone_catalog_assert_result(actual, 3, count, selected, input.target_slot, expected, UINT64_MAX);
        phone_catalog_corrupt_every_byte(input, actual);
        input.revision = UINT64_MAX;
        actual = beluga_core_phone_catalog_decide(input);
        beluga_core_phone_catalog_result_t exhausted = {0};
        exhausted.abi_version = 1; exhausted.status = 1; exhausted.error = 9;
        assert(memcmp(&actual, &exhausted, sizeof(actual)) == 0);
        phone_catalog_corrupt_every_byte(input, actual);
    }
    for (uint32_t operation = 2; operation <= 3; ++operation) {
        beluga_core_phone_catalog_input_t input = {0};
        input.abi_version = 1; input.stage = 11; input.operation = operation;
        input.flags = 1; input.count = 8; input.selected_slot = 7; input.target_slot = 7; input.revision = UINT64_MAX;
        beluga_core_phone_catalog_result_t actual = beluga_core_phone_catalog_decide(input);
        const uint32_t original[8] = {0,1,2,3,4,5,6,7};
        phone_catalog_assert_result(actual, 2, 8, 7, 7, original, UINT64_MAX);
        phone_catalog_corrupt_every_byte(input, actual);
    }
    beluga_core_phone_catalog_input_t input = {0};
    input.abi_version = 1; input.flags = 3;
    beluga_core_phone_catalog_result_t actual = beluga_core_phone_catalog_decide(input);
    beluga_core_phone_catalog_result_t continuation = {0};
    continuation.abi_version = 1; continuation.status = 1;
    assert(memcmp(&actual, &continuation, sizeof(actual)) == 0);
    phone_catalog_corrupt_every_byte(input, actual);
    input.abi_version = 2;
    actual = beluga_core_phone_catalog_decide(input);
    beluga_core_phone_catalog_result_t malformed = {0};
    malformed.abi_version = 1;
    assert(memcmp(&actual, &malformed, sizeof(actual)) == 0);
    assert(beluga_core_phone_catalog_result_is_valid(input, actual) == 0);
    puts("BelugaCore C phone catalog ABI PASS: every offset, all operations/actions, full maps, 72-byte verifier");
}

/* Add above main(); add runtime_catalog_smoke() to the existing main invocation list. */
_Static_assert(sizeof(beluga_core_runtime_catalog_state_t) == 24, "runtime catalog state size");
_Static_assert(_Alignof(beluga_core_runtime_catalog_state_t) == 4, "runtime catalog state alignment");
_Static_assert(offsetof(beluga_core_runtime_catalog_state_t, abi_version) == 0, "runtime catalog state abi_version");
_Static_assert(offsetof(beluga_core_runtime_catalog_state_t, phase) == 4, "runtime catalog state phase");
_Static_assert(offsetof(beluga_core_runtime_catalog_state_t, operation) == 8, "runtime catalog state operation");
_Static_assert(offsetof(beluga_core_runtime_catalog_state_t, eligible) == 12, "runtime catalog state eligible");
_Static_assert(offsetof(beluga_core_runtime_catalog_state_t, intent) == 16, "runtime catalog state intent");
_Static_assert(offsetof(beluga_core_runtime_catalog_state_t, first_grant) == 20, "runtime catalog state first_grant");
_Static_assert(sizeof(beluga_core_runtime_catalog_event_t) == 16, "runtime catalog event size");
_Static_assert(_Alignof(beluga_core_runtime_catalog_event_t) == 4, "runtime catalog event alignment");
_Static_assert(offsetof(beluga_core_runtime_catalog_event_t, opcode) == 0, "runtime catalog event opcode");
_Static_assert(offsetof(beluga_core_runtime_catalog_event_t, operation) == 4, "runtime catalog event operation");
_Static_assert(offsetof(beluga_core_runtime_catalog_event_t, facts) == 8, "runtime catalog event facts");
_Static_assert(offsetof(beluga_core_runtime_catalog_event_t, reserved) == 12, "runtime catalog event reserved");
_Static_assert(sizeof(beluga_core_runtime_catalog_result_t) == 40, "runtime catalog result size");
_Static_assert(_Alignof(beluga_core_runtime_catalog_result_t) == 4, "runtime catalog result alignment");
_Static_assert(offsetof(beluga_core_runtime_catalog_result_t, state) == 0, "runtime catalog result state");
_Static_assert(offsetof(beluga_core_runtime_catalog_result_t, status) == 24, "runtime catalog result status");
_Static_assert(offsetof(beluga_core_runtime_catalog_result_t, decision) == 28, "runtime catalog result decision");
_Static_assert(offsetof(beluga_core_runtime_catalog_result_t, effect) == 32, "runtime catalog result effect");
_Static_assert(offsetof(beluga_core_runtime_catalog_result_t, value) == 36, "runtime catalog result value");

static beluga_core_runtime_catalog_result_t runtime_catalog_expected(
    beluga_core_runtime_catalog_state_t state, uint32_t status,
    uint32_t decision, uint32_t effect, uint32_t value) {
    return (beluga_core_runtime_catalog_result_t){state,status,decision,effect,value};
}
static void runtime_catalog_assert(
    beluga_core_runtime_catalog_state_t state, beluga_core_runtime_catalog_event_t event,
    beluga_core_runtime_catalog_result_t actual, beluga_core_runtime_catalog_result_t expected) {
    assert(memcmp(&actual,&expected,sizeof(actual)) == 0);
    assert(beluga_core_runtime_catalog_result_is_valid(state,event,actual) == expected.status);
}
static void runtime_catalog_corrupt_every_byte(
    beluga_core_runtime_catalog_state_t state, beluga_core_runtime_catalog_event_t event,
    beluga_core_runtime_catalog_result_t actual) {
    assert(beluga_core_runtime_catalog_result_is_valid(state,event,actual) == 1);
    for (size_t byte = 0; byte < 40; ++byte) {
        for (unsigned bit = 0; bit < 8; ++bit) {
            beluga_core_runtime_catalog_result_t mutant = actual;
            ((unsigned char *)&mutant)[byte] ^= (unsigned char)(1u << bit);
            assert(beluga_core_runtime_catalog_result_is_valid(state,event,mutant) == 0);
        }
    }
}
static void runtime_catalog_smoke(void) {
    /* Independent row facts and native-state setup; no candidate supplies expected results. */
    const uint32_t facts[58] = {
        0,31,24,2047,1,1,3,1,3,3,1,3,127,3,7,1,3,1,1,1,1,1,0,1,7,3,1,7,3,
        3,1,3,2047,1,7,1,3,3,7,1,1023,3,1,63,3,1023,31,15,0,3,1,3,1,3,3,7,7,1
    };
    for (uint32_t opcode = 0; opcode < 58; ++opcode) {
        beluga_core_runtime_catalog_state_t state = {1,0,0,0,0,0};
        beluga_core_runtime_catalog_event_t event = {opcode,0,facts[opcode],0};
        if (opcode == 2 || opcode == 8) event.operation = 3;
        if (opcode == 8 || opcode == 48) state.eligible = 1;
        if (opcode == 9 || opcode == 10) state = (beluga_core_runtime_catalog_state_t){1,1,3,0,0,1};
        if (opcode == 11 || opcode == 12 || opcode == 14 || opcode == 24)
            state = (beluga_core_runtime_catalog_state_t){1,2,3,0,0,0};
        if (opcode == 13) state = (beluga_core_runtime_catalog_state_t){1,2,3,0,1,0};
        if (opcode == 21) state = (beluga_core_runtime_catalog_state_t){1,2,3,0,0,1};
        if (opcode == 22 || opcode == 23) state.intent = 1;
        beluga_core_runtime_catalog_result_t actual = beluga_core_runtime_catalog_step(state,event);
        /* Construct ORIGINAL expected state/effect/value only AFTER the actual C call. */
        beluga_core_runtime_catalog_state_t next = state;
        uint32_t effect = 0, value = 0;
        if (opcode == 1) { next.eligible = 1; effect = 1; }
        if (opcode == 8) { next.phase = 1; next.operation = 3; next.eligible = 0; next.first_grant = 1; effect = 2; value = 1; }
        if (opcode == 10) { next.phase = 2; effect = 3; value = 1; }
        if (opcode == 13) { next.phase = 0; next.operation = 0; next.first_grant = 0; effect = 4; value = 1; }
        if (opcode == 21) { next.intent = 1; next.first_grant = 0; effect = 5; value = 1; }
        if (opcode == 22) { next.intent = 0; effect = 6; }
        if (opcode == 23) { next.intent = 0; effect = 7; value = 1; }
        if (opcode == 48) { next = (beluga_core_runtime_catalog_state_t){1,3,0,0,0,0}; effect = 8; }
        runtime_catalog_assert(state,event,actual,runtime_catalog_expected(next,1,0,effect,value));
        runtime_catalog_corrupt_every_byte(state,event,actual);
    }
    for (uint32_t operation = 1; operation <= 3; ++operation) {
        beluga_core_runtime_catalog_state_t state = {1,0,0,1,0,0};
        beluga_core_runtime_catalog_event_t event = {8,operation,3,0};
        beluga_core_runtime_catalog_result_t actual = beluga_core_runtime_catalog_step(state,event);
        uint32_t grant = operation == 3 ? 1 : 0;
        beluga_core_runtime_catalog_state_t next = {1,1,operation,0,0,grant};
        runtime_catalog_assert(state,event,actual,runtime_catalog_expected(next,1,0,2,grant));
        runtime_catalog_corrupt_every_byte(state,event,actual);
    }
    beluga_core_runtime_catalog_state_t state = {1,0,0,0,0,0};
    beluga_core_runtime_catalog_event_t event = {2,1,1,0};
    beluga_core_runtime_catalog_result_t actual = beluga_core_runtime_catalog_step(state,event);
    runtime_catalog_assert(state,event,actual,runtime_catalog_expected(state,1,3,0,0));
    event = (beluga_core_runtime_catalog_event_t){2,3,4,0};
    actual = beluga_core_runtime_catalog_step(state,event);
    runtime_catalog_assert(state,event,actual,runtime_catalog_expected(state,1,8,0,0));
    event.facts = 0;
    actual = beluga_core_runtime_catalog_step(state,event);
    runtime_catalog_assert(state,event,actual,runtime_catalog_expected(state,1,4,0,0));
    state.intent = 1; event = (beluga_core_runtime_catalog_event_t){8,3,0,0};
    actual = beluga_core_runtime_catalog_step(state,event);
    runtime_catalog_assert(state,event,actual,runtime_catalog_expected(state,0,0,0,0));
    state = (beluga_core_runtime_catalog_state_t){1,3,0,0,0,0};
    event = (beluga_core_runtime_catalog_event_t){9,0,3,0};
    actual = beluga_core_runtime_catalog_step(state,event);
    runtime_catalog_assert(state,event,actual,runtime_catalog_expected(state,1,0,0,0));
    event = (beluga_core_runtime_catalog_event_t){10,0,1,0};
    actual = beluga_core_runtime_catalog_step(state,event);
    runtime_catalog_assert(state,event,actual,runtime_catalog_expected(state,1,0,0,1));
    event = (beluga_core_runtime_catalog_event_t){55,0,7,0};
    actual = beluga_core_runtime_catalog_step(state,event);
    runtime_catalog_assert(state,event,actual,runtime_catalog_expected(state,1,0,0,0));
    event = (beluga_core_runtime_catalog_event_t){56,0,7,0};
    actual = beluga_core_runtime_catalog_step(state,event);
    runtime_catalog_assert(state,event,actual,runtime_catalog_expected(state,1,8,0,0));
    state.abi_version = 0; event = (beluga_core_runtime_catalog_event_t){48,0,0,0};
    actual = beluga_core_runtime_catalog_step(state,event);
    runtime_catalog_assert(state,event,actual,runtime_catalog_expected(state,0,0,0,0));
    state = (beluga_core_runtime_catalog_state_t){1,0,0,0,0,0}; event.reserved = UINT32_MAX;
    actual = beluga_core_runtime_catalog_step(state,event);
    runtime_catalog_assert(state,event,actual,runtime_catalog_expected(state,0,0,0,0));
    puts("BelugaCore C runtime catalog ABI PASS: 58 ordered cuts, every offset, historical grant, 40-byte verifier");
}

/* Additive, unexecuted product-link smoke fragment. The literal kind ledger and
 * adversarial payloads are synthetic transport inputs, not native telemetry or
 * resource custody. Only the five handwritten StopSampling mutations define the
 * expected successor; no reducer/encoder computes this test's expected state. */
_Static_assert(sizeof(beluga_core_adaptation_owner_event_request_t) == 40, "owner_event_request size");
_Static_assert(_Alignof(beluga_core_adaptation_owner_event_request_t) == 8, "owner_event_request alignment");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_request_t, abi) == 0, "owner_event_request.abi offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_request_t, operation) == 4, "owner_event_request.operation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_request_t, generation) == 8, "owner_event_request.generation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_request_t, invocation) == 16, "owner_event_request.invocation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_request_t, show) == 24, "owner_event_request.show offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_request_t, capture_source_present) == 32, "owner_event_request.capture_source_present offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_request_t, resume_context_absent) == 36, "owner_event_request.resume_context_absent offset");
_Static_assert(sizeof(beluga_core_adaptation_state_header_t) == 16, "state_header size");
_Static_assert(_Alignof(beluga_core_adaptation_state_header_t) == 4, "state_header alignment");
_Static_assert(offsetof(beluga_core_adaptation_state_header_t, abi) == 0, "state_header.abi offset");
_Static_assert(offsetof(beluga_core_adaptation_state_header_t, domain) == 4, "state_header.domain offset");
_Static_assert(offsetof(beluga_core_adaptation_state_header_t, phase) == 8, "state_header.phase offset");
_Static_assert(offsetof(beluga_core_adaptation_state_header_t, count) == 12, "state_header.count offset");
_Static_assert(sizeof(beluga_core_adaptation_state_atom_t) == 24, "state_atom size");
_Static_assert(_Alignof(beluga_core_adaptation_state_atom_t) == 8, "state_atom alignment");
_Static_assert(offsetof(beluga_core_adaptation_state_atom_t, kind) == 0, "state_atom.kind offset");
_Static_assert(offsetof(beluga_core_adaptation_state_atom_t, present) == 4, "state_atom.present offset");
_Static_assert(offsetof(beluga_core_adaptation_state_atom_t, high) == 8, "state_atom.high offset");
_Static_assert(offsetof(beluga_core_adaptation_state_atom_t, low) == 16, "state_atom.low offset");
_Static_assert(sizeof(beluga_core_adaptation_time_edit_t) == 32, "time_edit size");
_Static_assert(_Alignof(beluga_core_adaptation_time_edit_t) == 8, "time_edit alignment");
_Static_assert(offsetof(beluga_core_adaptation_time_edit_t, action) == 0, "time_edit.action offset");
_Static_assert(offsetof(beluga_core_adaptation_time_edit_t, source) == 4, "time_edit.source offset");
_Static_assert(offsetof(beluga_core_adaptation_time_edit_t, index) == 8, "time_edit.index offset");
_Static_assert(offsetof(beluga_core_adaptation_time_edit_t, ordinal) == 12, "time_edit.ordinal offset");
_Static_assert(offsetof(beluga_core_adaptation_time_edit_t, high) == 16, "time_edit.high offset");
_Static_assert(offsetof(beluga_core_adaptation_time_edit_t, low) == 24, "time_edit.low offset");
_Static_assert(sizeof(beluga_core_adaptation_time_coordinate_t) == 24, "time_coordinate size");
_Static_assert(_Alignof(beluga_core_adaptation_time_coordinate_t) == 8, "time_coordinate alignment");
_Static_assert(offsetof(beluga_core_adaptation_time_coordinate_t, present) == 0, "time_coordinate.present offset");
_Static_assert(offsetof(beluga_core_adaptation_time_coordinate_t, reserved) == 4, "time_coordinate.reserved offset");
_Static_assert(offsetof(beluga_core_adaptation_time_coordinate_t, high) == 8, "time_coordinate.high offset");
_Static_assert(offsetof(beluga_core_adaptation_time_coordinate_t, low) == 16, "time_coordinate.low offset");
_Static_assert(sizeof(beluga_core_adaptation_clock_reply_t) == 48, "clock_reply size");
_Static_assert(_Alignof(beluga_core_adaptation_clock_reply_t) == 8, "clock_reply alignment");
_Static_assert(offsetof(beluga_core_adaptation_clock_reply_t, abi) == 0, "clock_reply.abi offset");
_Static_assert(offsetof(beluga_core_adaptation_clock_reply_t, status) == 4, "clock_reply.status offset");
_Static_assert(offsetof(beluga_core_adaptation_clock_reply_t, site) == 8, "clock_reply.site offset");
_Static_assert(offsetof(beluga_core_adaptation_clock_reply_t, ordinal) == 12, "clock_reply.ordinal offset");
_Static_assert(offsetof(beluga_core_adaptation_clock_reply_t, invocation) == 16, "clock_reply.invocation offset");
_Static_assert(offsetof(beluga_core_adaptation_clock_reply_t, high) == 24, "clock_reply.high offset");
_Static_assert(offsetof(beluga_core_adaptation_clock_reply_t, low) == 32, "clock_reply.low offset");
_Static_assert(offsetof(beluga_core_adaptation_clock_reply_t, reserved) == 40, "clock_reply.reserved offset");
_Static_assert(sizeof(beluga_core_adaptation_owner_event_metadata_t) == 72, "owner_event_metadata size");
_Static_assert(_Alignof(beluga_core_adaptation_owner_event_metadata_t) == 8, "owner_event_metadata alignment");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, abi) == 0, "owner_event_metadata.abi offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, operation) == 4, "owner_event_metadata.operation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, scope) == 8, "owner_event_metadata.scope offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, read_count) == 12, "owner_event_metadata.read_count offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, invocation) == 16, "owner_event_metadata.invocation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, revision) == 24, "owner_event_metadata.revision offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, peer) == 32, "owner_event_metadata.peer offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, peer_present) == 40, "owner_event_metadata.peer_present offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, bound) == 44, "owner_event_metadata.bound offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, route) == 48, "owner_event_metadata.route offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, sample) == 52, "owner_event_metadata.sample offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, enabled) == 56, "owner_event_metadata.enabled offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, lease) == 60, "owner_event_metadata.lease offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, queue_fault) == 64, "owner_event_metadata.queue_fault offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_event_metadata_t, rtt_fault) == 68, "owner_event_metadata.rtt_fault offset");

typedef struct {
    beluga_core_adaptation_state_header_t header;
    beluga_core_adaptation_state_atom_t atoms[179];
    beluga_core_adaptation_owner_event_metadata_t metadata;
    beluga_core_adaptation_time_edit_t edits[13];
    beluga_core_adaptation_time_coordinate_t coordinates[13];
    beluga_core_adaptation_clock_reply_t reads[15];
} owner105_buffers_t;

static void owner105_seed(beluga_core_adaptation_state_atom_t atoms[179]) {
    static const uint32_t kinds[179] = {
        2,2,2,1,7,2,2,2,2,2,2,2,10,2,2,4,4,4,2,2,
        7,7,7,10,2,4,7,2,10,2,2,2,4,4,4,3,1,3,2,10,
        10,4,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
        3,3,3,3,3,2,2,1,1,1,1,1,1,1,1,3,1,1,1,1,
        1,1,1,1,1,3,1,3,10,4,6,2,2,2,2,3,2,2,2,2,
        2,3,2,2,2,2,2,3,2,2,2,2,2,3,2,2,2,2,2,3,
        2,2,2,2,2,3,2,2,2,2,2,3,2,2,2,2,2,3,2,5,
        4,5,2,1,4,4,1,3,3,3,1,4,1,4,4,4,4,3,4,10,
        3,1,3,10,1,1,4,10,1,4,8,10,1,4,7,2,2,2,3
    };
    for (uint32_t i = 0; i < 179; ++i) {
        uint64_t low = 0;
        switch (kinds[i]) {
            case 1: low = UINT64_C(10000) + i; break;
            case 2: low = UINT64_C(1000) + i; break;
            case 3: low = UINT64_C(0x7ff8000000000000) + i; break;
            case 6: low = UINT64_C(20000) + i; break;
            case 10: low = UINT64_C(1000000) + i; break;
            default: break;
        }
        atoms[i] = (beluga_core_adaptation_state_atom_t){kinds[i],1,0,low};
    }
    static const uint32_t ones[] = {15,16,25,33,41,140,145,151,154,156,158,169,173};
    for (size_t i = 0; i < sizeof(ones)/sizeof(ones[0]); ++i) atoms[ones[i]].low = 1;
    atoms[4].low = 5; atoms[20].low = 3; atoms[21].low = 4;
    atoms[22].low = 6; atoms[26].low = 1; atoms[174].low = 2;
    atoms[139].low = 250; atoms[141].low = 251; atoms[170].low = 1;
    atoms[168].low = UINT64_MAX; /* wrapping owner revision */
    atoms[171].high = -1; atoms[171].low = UINT64_MAX - 6; /* -7 attoseconds */
    atoms[172].low = UINT64_MAX;
}

static int owner105_buffers_equal(const owner105_buffers_t *a, const owner105_buffers_t *b) {
    return memcmp(&a->header,&b->header,sizeof(a->header)) == 0 &&
        memcmp(a->atoms,b->atoms,sizeof(a->atoms)) == 0 &&
        memcmp(&a->metadata,&b->metadata,sizeof(a->metadata)) == 0 &&
        memcmp(a->edits,b->edits,sizeof(a->edits)) == 0 &&
        memcmp(a->coordinates,b->coordinates,sizeof(a->coordinates)) == 0 &&
        memcmp(a->reads,b->reads,sizeof(a->reads)) == 0;
}

static uint32_t owner105_call(const beluga_core_adaptation_owner_event_request_t *request,
    const beluga_core_adaptation_state_header_t *header,
    const beluga_core_adaptation_state_atom_t atoms[179], uint32_t output_count,
    owner105_buffers_t *output) {
    return beluga_core_network_adaptation_owner_zero_clock_event(request,header,atoms,179,
        &output->header,output->atoms,output_count,&output->metadata,
        output->edits,13,output->coordinates,13,output->reads,15);
}

static void adaptation_owner_zero_clock_smoke_v1(void) {
    beluga_core_adaptation_owner_event_request_t request = {1,105,0,UINT64_C(0xfedcba9876543210),0,0,0};
    const beluga_core_adaptation_state_header_t header = {1,2,1,179};
    beluga_core_adaptation_state_atom_t current[179]; owner105_seed(current);
    const beluga_core_adaptation_owner_event_request_t request_before = request;
    const beluga_core_adaptation_state_header_t header_before = header;
    beluga_core_adaptation_state_atom_t input_before[179]; memcpy(input_before,current,sizeof(current));
    owner105_buffers_t actual; memset(&actual,0xa5,sizeof(actual));
    assert(owner105_call(&request,&header,current,179,&actual) == 1);
    owner105_buffers_t expected; memset(&expected,0,sizeof(expected));
    expected.header = (beluga_core_adaptation_state_header_t){1,2,2,179};
    memcpy(expected.atoms,input_before,sizeof(expected.atoms));
    expected.atoms[168].low = 0;
    expected.atoms[169].low = 0;
    for (uint32_t i = 170; i <= 172; ++i) {
        expected.atoms[i].present = 0; expected.atoms[i].high = 0; expected.atoms[i].low = 0;
    }
    expected.metadata = (beluga_core_adaptation_owner_event_metadata_t){
        1,105,2,0,UINT64_C(0xfedcba9876543210),0,10003,1,0,0,0,0,0,1,0};
    expected.edits[12].action = 2;
    assert(owner105_buffers_equal(&actual,&expected));
    assert(memcmp(current,input_before,sizeof(current)) == 0);
    assert(memcmp(&header,&header_before,sizeof(header)) == 0);
    assert(memcmp(&request,&request_before,sizeof(request)) == 0);

    /* Closed policy op, malformed request, malformed full-state atom, short output.
     * Each starts with six fresh sentinels and preserves every input byte. */
    for (uint32_t mode = 0; mode < 4; ++mode) {
        request = request_before; memcpy(current,input_before,sizeof(current));
        uint32_t output_count = 179;
        if (mode == 0) request.operation = 104;
        if (mode == 1) request.abi = 2;
        if (mode == 2) current[35].kind = 99;
        if (mode == 3) output_count = 178;
        const beluga_core_adaptation_owner_event_request_t malformed_before = request;
        beluga_core_adaptation_state_atom_t malformed_atoms[179]; memcpy(malformed_atoms,current,sizeof(current));
        memset(&actual,0xa5,sizeof(actual)); const owner105_buffers_t sentinel = actual;
        assert(owner105_call(&request,&header,current,output_count,&actual) == 2);
        assert(owner105_buffers_equal(&actual,&sentinel));
        assert(memcmp(current,malformed_atoms,sizeof(current)) == 0);
        assert(memcmp(&request,&malformed_before,sizeof(request)) == 0);
        assert(memcmp(&header,&header_before,sizeof(header)) == 0);
    }
    puts("BelugaCore C adaptation Owner zero-clock PASS: layouts, full179 stop, four untouched denials");
}

/* SOURCE-ONLY additive public C import/link smoke. The full179 wire fixture is
 * synthetic: no actual native Instant, actor adoption or effect proof. */
_Static_assert(sizeof(beluga_core_adaptation_owner_clocked_event_request_t) == 48, "clocked request size");
_Static_assert(_Alignof(beluga_core_adaptation_owner_clocked_event_request_t) == 8, "clocked request alignment");
_Static_assert(offsetof(beluga_core_adaptation_owner_clocked_event_request_t, abi) == 0, "clocked abi offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_clocked_event_request_t, operation) == 4, "clocked operation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_clocked_event_request_t, generation) == 8, "clocked generation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_clocked_event_request_t, invocation) == 16, "clocked invocation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_clocked_event_request_t, show) == 24, "clocked show offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_clocked_event_request_t, minimum) == 32, "clocked minimum offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_clocked_event_request_t, flag) == 40, "clocked flag offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_clocked_event_request_t, minimum_present) == 44, "clocked minimum presence offset");

typedef struct { uint32_t calls, mode; } owner216_clock_context_t;
static uint32_t owner216_clock(void *context, uint64_t invocation, uint32_t site,
    uint32_t ordinal, beluga_core_adaptation_clock_reply_t *reply) {
    assert(context != NULL && reply != NULL);
    owner216_clock_context_t *clock = context;
    assert(invocation == UINT64_C(0xfedcba9876543210));
    assert(site == 2 && ordinal == 0 && clock->calls == 0);
    clock->calls += 1;
    if (clock->mode == 1) return 0;
    *reply = (beluga_core_adaptation_clock_reply_t){1,1,2,0,
        UINT64_C(0xfedcba9876543210),0,9000000,clock->mode == 2 ? 1 : 0};
    return 1;
}
static uint32_t owner216_call(const beluga_core_adaptation_owner_clocked_event_request_t *request,
    const beluga_core_adaptation_state_header_t *header,
    const beluga_core_adaptation_state_atom_t atoms[179], uint32_t output_count,
    beluga_core_adaptation_owner_clock_callback_t callback, owner216_clock_context_t *clock,
    owner105_buffers_t *output) {
    return beluga_core_network_adaptation_owner_clocked_event(request,header,atoms,179,
        callback,clock,&output->header,output->atoms,output_count,&output->metadata,
        output->edits,13,output->coordinates,13,output->reads,15);
}
static void owner216_absent(beluga_core_adaptation_state_atom_t atoms[179], uint32_t index) {
    atoms[index].present = 0; atoms[index].high = 0; atoms[index].low = 0;
}

static void adaptation_owner_clocked_smoke_v1(void) {
    const beluga_core_adaptation_owner_clocked_event_request_t request =
        {1,216,0,UINT64_C(0xfedcba9876543210),0,0,0,0};
    const beluga_core_adaptation_state_header_t header = {1,2,1,179};
    beluga_core_adaptation_state_atom_t current[179]; owner105_seed(current);
    const beluga_core_adaptation_owner_clocked_event_request_t request_before = request;
    const beluga_core_adaptation_state_header_t header_before = header;
    beluga_core_adaptation_state_atom_t input_before[179]; memcpy(input_before,current,sizeof(current));
    owner216_clock_context_t clock = {0,0};
    owner105_buffers_t actual; memset(&actual,0xa5,sizeof(actual));
    assert(owner216_call(&request,&header,current,179,owner216_clock,&clock,&actual) == 1);
    assert(clock.calls == 1);
    owner105_buffers_t expected; memset(&expected,0,sizeof(expected));
    expected.header = (beluga_core_adaptation_state_header_t){1,2,2,179};
    memcpy(expected.atoms,input_before,sizeof(expected.atoms));
    /* Literal full179 successor: sticky queue fault retains its native stamps;
     * fast identity, route, RTT data and every applied profile atom are retained. */
    static const uint32_t zero[] = {5,6,7,8,9,10,25,145,158};
    for (size_t i = 0; i < sizeof(zero)/sizeof(zero[0]); ++i) expected.atoms[zero[i]].low = 0;
    static const uint32_t absent[] = {21,26,27,28,146,147,148,159,160,170,171,172};
    for (size_t i = 0; i < sizeof(absent)/sizeof(absent[0]); ++i) owner216_absent(expected.atoms,absent[i]);
    expected.atoms[168].low = 0;
    expected.metadata = (beluga_core_adaptation_owner_event_metadata_t){
        1,216,2,1,UINT64_C(0xfedcba9876543210),0,10003,1,0,0,0,0,0,1,0};
    expected.edits[2].action = 2; expected.edits[3].action = 2;
    expected.edits[6].action = 1; expected.edits[7].action = 1; expected.edits[12].action = 2;
    expected.coordinates[6] = (beluga_core_adaptation_time_coordinate_t){1,0,0,1000039};
    expected.coordinates[7] = (beluga_core_adaptation_time_coordinate_t){1,0,0,1000040};
    expected.reads[0] = (beluga_core_adaptation_clock_reply_t){1,1,2,0,
        UINT64_C(0xfedcba9876543210),0,9000000,0};
    assert(owner105_buffers_equal(&actual,&expected));
    assert(memcmp(current,input_before,sizeof(current)) == 0);
    assert(memcmp(&request,&request_before,sizeof(request)) == 0);
    assert(memcmp(&header,&header_before,sizeof(header)) == 0);

    /* Earlier EndShow remains lazy and does not advance the owner revision.
     * Confirmed probe with absent origin exits before queue-reset provider use. */
    beluga_core_adaptation_owner_clocked_event_request_t lazy_request = request;
    lazy_request.operation = 202;
    owner105_seed(current); owner216_absent(current,20);
    memcpy(input_before,current,sizeof(current));
    const beluga_core_adaptation_owner_clocked_event_request_t lazy_before = lazy_request;
    clock = (owner216_clock_context_t){0,0}; memset(&actual,0xa5,sizeof(actual));
    assert(owner216_call(&lazy_request,&header,current,179,owner216_clock,&clock,&actual) == 1);
    assert(clock.calls == 0);
    memset(&expected,0,sizeof(expected)); expected.header = (beluga_core_adaptation_state_header_t){1,2,2,179};
    memcpy(expected.atoms,input_before,sizeof(expected.atoms));
    static const uint32_t lazy_absent[] = {164,165,167,159,160};
    for (size_t i = 0; i < sizeof(lazy_absent)/sizeof(lazy_absent[0]); ++i) owner216_absent(expected.atoms,lazy_absent[i]);
    expected.atoms[166].low = 0; expected.atoms[153].low = 0;
    expected.atoms[154].low = 0; expected.atoms[158].low = 0;
    expected.metadata = (beluga_core_adaptation_owner_event_metadata_t){
        1,202,1,0,UINT64_C(0xfedcba9876543210),UINT64_MAX,10003,1,0,0,0,0,0,1,0};
    expected.edits[0].action = 1; expected.edits[1].action = 1; expected.edits[2].action = 1;
    expected.edits[3].action = 2; expected.edits[5].action = 2;
    expected.edits[6].action = 1; expected.edits[7].action = 1;
    expected.coordinates[0] = (beluga_core_adaptation_time_coordinate_t){1,0,0,1000012};
    expected.coordinates[1] = (beluga_core_adaptation_time_coordinate_t){1,0,0,1000023};
    expected.coordinates[2] = (beluga_core_adaptation_time_coordinate_t){1,0,0,1000028};
    expected.coordinates[6] = (beluga_core_adaptation_time_coordinate_t){1,0,0,1000039};
    expected.coordinates[7] = (beluga_core_adaptation_time_coordinate_t){1,0,0,1000040};
    assert(owner105_buffers_equal(&actual,&expected));
    assert(memcmp(current,input_before,sizeof(current)) == 0);
    assert(memcmp(&lazy_request,&lazy_before,sizeof(lazy_request)) == 0);
    assert(memcmp(&header,&header_before,sizeof(header)) == 0);

    /* Shape refusals have no callback; provider failure and malformed reply
     * consume exactly their one external call but publish none of six outputs. */
    for (uint32_t mode = 0; mode < 8; ++mode) {
        beluga_core_adaptation_owner_clocked_event_request_t denied_request = request;
        beluga_core_adaptation_state_header_t denied_header = header;
        owner105_seed(current); uint32_t output_count = 179;
        beluga_core_adaptation_owner_clock_callback_t callback = owner216_clock;
        clock = (owner216_clock_context_t){0,0};
        if (mode == 0) denied_request.operation = 201;
        if (mode == 1) denied_request.abi = 2;
        if (mode == 2) current[88].kind = 99;
        if (mode == 3) output_count = 178;
        if (mode == 4) callback = NULL;
        if (mode == 5) clock.mode = 1;
        if (mode == 6) clock.mode = 2;
        if (mode == 7) denied_header.phase = 2;
        const beluga_core_adaptation_owner_clocked_event_request_t denied_before = denied_request;
        const beluga_core_adaptation_state_header_t denied_header_before = denied_header;
        memcpy(input_before,current,sizeof(current));
        memset(&actual,0xa5,sizeof(actual)); const owner105_buffers_t sentinel = actual;
        assert(owner216_call(&denied_request,&denied_header,current,output_count,callback,&clock,&actual) ==
            (mode == 5 ? 3u : mode == 6 ? 4u : 2u));
        assert(clock.calls == (mode == 5 || mode == 6 ? 1u : 0u));
        assert(owner105_buffers_equal(&actual,&sentinel));
        assert(memcmp(current,input_before,sizeof(current)) == 0);
        assert(memcmp(&denied_request,&denied_before,sizeof(denied_request)) == 0);
        assert(memcmp(&denied_header,&denied_header_before,sizeof(denied_header)) == 0);
    }
    puts("BelugaCore C adaptation Owner clocked PASS: layout, two full179 cuts, lazy callback, eight untouched denials");
}

/* Additive PUBLIC501 import/link smoke. The existing handwritten full179
 * input is synthetic and rejected before policy reads. Completed None is not
 * Prepared222 adoption, native route/Instant custody, or actor authority. */
_Static_assert(sizeof(beluga_core_adaptation_owner_prepare_request_t) == 56, "501 beluga_core_adaptation_owner_prepare_request_t size");
_Static_assert(_Alignof(beluga_core_adaptation_owner_prepare_request_t) == 8, "501 beluga_core_adaptation_owner_prepare_request_t alignment");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_request_t, abi) == 0, "501 abi offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_request_t, operation) == 4, "501 operation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_request_t, invocation) == 8, "501 invocation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_request_t, source_generation) == 16, "501 source_generation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_request_t, expected_revision) == 24, "501 expected_revision offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_request_t, current_generation) == 32, "501 current_generation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_request_t, entry_flags) == 40, "501 entry_flags offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_request_t, capacity_only) == 44, "501 capacity_only offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_request_t, allows_resume) == 48, "501 allows_resume offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_request_t, report_present) == 52, "501 report_present offset");
_Static_assert(sizeof(beluga_core_adaptation_owner_prepare_outcome_t) == 24, "501 beluga_core_adaptation_owner_prepare_outcome_t size");
_Static_assert(_Alignof(beluga_core_adaptation_owner_prepare_outcome_t) == 8, "501 beluga_core_adaptation_owner_prepare_outcome_t alignment");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_outcome_t, abi) == 0, "501 abi offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_outcome_t, operation) == 4, "501 operation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_outcome_t, invocation) == 8, "501 invocation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_outcome_t, prepared_present) == 16, "501 prepared_present offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_prepare_outcome_t, reserved) == 20, "501 reserved offset");
_Static_assert(sizeof(beluga_core_adaptation_owner_report_t) == 192, "501 beluga_core_adaptation_owner_report_t size");
_Static_assert(_Alignof(beluga_core_adaptation_owner_report_t) == 8, "501 beluga_core_adaptation_owner_report_t alignment");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, peer) == 0, "501 peer offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, capture_active) == 8, "501 capture_active offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, automatically_suspended) == 12, "501 automatically_suspended offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, strict) == 16, "501 strict offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, incoming_present) == 20, "501 incoming_present offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, equal_to_retained) == 24, "501 equal_to_retained offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, observation_kind) == 28, "501 observation_kind offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, collection_sequence_present) == 32, "501 collection_sequence_present offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, bandwidth_present) == 36, "501 bandwidth_present offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, current_rtt_present) == 40, "501 current_rtt_present offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, packets_present) == 44, "501 packets_present offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, delay_present) == 48, "501 delay_present offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, native_timestamp_present) == 52, "501 native_timestamp_present offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, fingerprint_length) == 56, "501 fingerprint_length offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, reserved) == 60, "501 reserved offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, collection_sequence) == 64, "501 collection_sequence offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, bandwidth_bits) == 72, "501 bandwidth_bits offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, current_rtt_bits) == 80, "501 current_rtt_bits offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, packets) == 88, "501 packets offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, delay_bits) == 96, "501 delay_bits offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, native_timestamp_bits) == 104, "501 native_timestamp_bits offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, fingerprint) == 112, "501 fingerprint offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, measurement_total_bits) == 176, "501 measurement_total_bits offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_report_t, measurement_responses) == 184, "501 measurement_responses offset");

typedef struct {
    beluga_core_adaptation_state_header_t header;
    beluga_core_adaptation_state_atom_t atoms[222];
    beluga_core_adaptation_owner_event_metadata_t metadata;
    beluga_core_adaptation_owner_prepare_outcome_t outcome;
    beluga_core_adaptation_time_edit_t edits[13];
    beluga_core_adaptation_time_coordinate_t coordinates[13];
    beluga_core_adaptation_clock_reply_t reads[15];
} owner501_buffers_t;

static int owner501_buffers_equal(const owner501_buffers_t *a, const owner501_buffers_t *b) {
    return memcmp(&a->header,&b->header,sizeof(a->header)) == 0 &&
        memcmp(a->atoms,b->atoms,sizeof(a->atoms)) == 0 &&
        memcmp(&a->metadata,&b->metadata,sizeof(a->metadata)) == 0 &&
        memcmp(&a->outcome,&b->outcome,sizeof(a->outcome)) == 0 &&
        memcmp(a->edits,b->edits,sizeof(a->edits)) == 0 &&
        memcmp(a->coordinates,b->coordinates,sizeof(a->coordinates)) == 0 &&
        memcmp(a->reads,b->reads,sizeof(a->reads)) == 0;
}
static uint32_t owner501_call(const beluga_core_adaptation_owner_prepare_request_t *request,
    const beluga_core_adaptation_state_header_t *header,
    const beluga_core_adaptation_state_atom_t atoms[179],
    const beluga_core_adaptation_owner_report_t *report,
    const beluga_core_adaptation_time_coordinate_t *observed,
    uint32_t output_count, beluga_core_adaptation_owner_clock_callback_t callback,
    owner216_clock_context_t *clock, owner501_buffers_t *output) {
    return beluga_core_network_adaptation_owner_prepare_event(request,header,atoms,179,report,observed,
        callback,clock,&output->header,output->atoms,output_count,&output->metadata,&output->outcome,
        output->edits,13,output->coordinates,13,output->reads,15);
}
static void adaptation_owner_prepare_smoke_v1(void) {
    const beluga_core_adaptation_owner_prepare_request_t admitted =
        {1,501,UINT64_C(0xfedcba9876543210),42,UINT64_MAX,42,127,0,0,0};
    const beluga_core_adaptation_state_header_t header = {1,2,1,179};
    const beluga_core_adaptation_owner_report_t report = {0};
    const beluga_core_adaptation_time_coordinate_t observed = {0};
    beluga_core_adaptation_state_atom_t current[179]; owner105_seed(current);
    beluga_core_adaptation_state_atom_t input_before[179]; memcpy(input_before,current,sizeof(current));
    for (uint32_t mode = 0; mode < 5; ++mode) {
        beluga_core_adaptation_owner_prepare_request_t request = admitted;
        if (mode == 0) request.entry_flags &= ~1u;
        if (mode == 1) request.entry_flags &= ~2u;
        if (mode == 2) request.current_generation = 43;
        if (mode == 3) request.expected_revision = UINT64_MAX - 1;
        if (mode == 4) request.entry_flags &= ~4u;
        const beluga_core_adaptation_owner_prepare_request_t request_before = request;
        const beluga_core_adaptation_state_header_t header_before = header;
        const beluga_core_adaptation_owner_report_t report_before = report;
        const beluga_core_adaptation_time_coordinate_t observed_before = observed;
        owner216_clock_context_t clock = {0,0};
        owner501_buffers_t actual; memset(&actual,0xa5,sizeof(actual));
        assert(owner501_call(&request,&header,current,&report,&observed,222,
            owner216_clock,&clock,&actual) == 1);
        assert(clock.calls == 0);
        owner501_buffers_t expected; memset(&expected,0,sizeof(expected));
        expected.metadata = (beluga_core_adaptation_owner_event_metadata_t){
            1,501,1,0,UINT64_C(0xfedcba9876543210),UINT64_MAX,10003,1,0,0,0,0,0,1,0};
        expected.outcome = (beluga_core_adaptation_owner_prepare_outcome_t){
            1,501,UINT64_C(0xfedcba9876543210),0,0};
        assert(owner501_buffers_equal(&actual,&expected));
        assert(memcmp(&request,&request_before,sizeof(request)) == 0);
        assert(memcmp(&header,&header_before,sizeof(header)) == 0);
        assert(memcmp(current,input_before,sizeof(current)) == 0);
        assert(memcmp(&report,&report_before,sizeof(report)) == 0);
        assert(memcmp(&observed,&observed_before,sizeof(observed)) == 0);
    }
    /* Structural validation precedes even entry rejection. Fresh sentinels
     * cover every output object; no invalid shape may call the provider. */
    for (uint32_t mode = 0; mode < 15; ++mode) {
        beluga_core_adaptation_owner_prepare_request_t request = admitted; request.entry_flags = 0;
        beluga_core_adaptation_state_header_t denied_header = header;
        beluga_core_adaptation_owner_report_t denied_report = report;
        beluga_core_adaptation_time_coordinate_t denied_observed = observed;
        memcpy(current,input_before,sizeof(current));
        uint32_t output_count = 222;
        beluga_core_adaptation_owner_clock_callback_t callback = owner216_clock;
        if (mode == 0) request.operation = 401;
        if (mode == 1) request.abi = 2;
        if (mode == 2) request.invocation = 0;
        if (mode == 3) request.entry_flags = 256;
        if (mode == 4) request.capacity_only = 2;
        if (mode == 5) request.allows_resume = 2;
        if (mode == 6) request.report_present = 2;
        if (mode == 7) denied_report.peer = 42;
        if (mode == 8) { request.report_present = 1; denied_report.reserved = 1; }
        if (mode == 9) current[178].kind = 99;
        if (mode == 10) output_count = 221;
        if (mode == 11) callback = NULL;
        if (mode == 12) denied_observed.reserved = 1;
        if (mode == 13) request.entry_flags = 127;
        if (mode == 14) denied_header.phase = 2;
        const beluga_core_adaptation_owner_prepare_request_t request_before = request;
        const beluga_core_adaptation_state_header_t header_before = denied_header;
        const beluga_core_adaptation_owner_report_t report_before = denied_report;
        const beluga_core_adaptation_time_coordinate_t observed_before = denied_observed;
        beluga_core_adaptation_state_atom_t atoms_before[179]; memcpy(atoms_before,current,sizeof(current));
        owner216_clock_context_t clock = {0,0};
        owner501_buffers_t actual; memset(&actual,0xa5,sizeof(actual));
        const owner501_buffers_t sentinel = actual;
        assert(owner501_call(&request,&denied_header,current,&denied_report,&denied_observed,
            output_count,callback,&clock,&actual) == 2);
        assert(clock.calls == 0 && owner501_buffers_equal(&actual,&sentinel));
        assert(memcmp(&request,&request_before,sizeof(request)) == 0);
        assert(memcmp(&denied_header,&header_before,sizeof(denied_header)) == 0);
        assert(memcmp(current,atoms_before,sizeof(current)) == 0);
        assert(memcmp(&denied_report,&report_before,sizeof(denied_report)) == 0);
        assert(memcmp(&denied_observed,&observed_before,sizeof(denied_observed)) == 0);
    }
    puts("BelugaCore C adaptation Owner prepare PASS: layouts, full179 lazy None, fifteen untouched denials");
}

/* Additive public601 C import/link smoke: synthetic full179/Prepared222 PODs,
 * never a native prepared seal, route/Instant permission, or actor adoption. */
_Static_assert(sizeof(beluga_core_adaptation_owner_inactive_request_t) == 32, "601 request size");
_Static_assert(_Alignof(beluga_core_adaptation_owner_inactive_request_t) == 8, "601 request alignment");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_request_t, abi) == 0, "601 abi offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_request_t, operation) == 4, "601 operation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_request_t, invocation) == 8, "601 invocation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_request_t, current_generation) == 16, "601 generation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_request_t, exact_peer) == 24, "601 exact peer offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_request_t, suspended) == 28, "601 suspended offset");
_Static_assert(sizeof(beluga_core_adaptation_owner_inactive_outcome_t) == 24, "601 outcome size");
_Static_assert(_Alignof(beluga_core_adaptation_owner_inactive_outcome_t) == 8, "601 outcome alignment");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_outcome_t, abi) == 0, "601 outcome abi offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_outcome_t, operation) == 4, "601 outcome op offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_outcome_t, invocation) == 8, "601 outcome invocation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_outcome_t, disposition) == 16, "601 disposition offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_inactive_outcome_t, route) == 20, "601 route offset");

typedef struct {
    beluga_core_adaptation_state_header_t header;
    beluga_core_adaptation_state_atom_t atoms[179];
    beluga_core_adaptation_owner_event_metadata_t metadata;
    beluga_core_adaptation_owner_inactive_outcome_t outcome;
    beluga_core_adaptation_time_edit_t edits[13];
    beluga_core_adaptation_time_coordinate_t coordinates[13];
    beluga_core_adaptation_clock_reply_t reads[15];
} owner601_buffers_t;
static int owner601_buffers_equal(const owner601_buffers_t *a, const owner601_buffers_t *b) {
    return memcmp(&a->header,&b->header,sizeof(a->header)) == 0 &&
        memcmp(a->atoms,b->atoms,sizeof(a->atoms)) == 0 &&
        memcmp(&a->metadata,&b->metadata,sizeof(a->metadata)) == 0 &&
        memcmp(&a->outcome,&b->outcome,sizeof(a->outcome)) == 0 &&
        memcmp(a->edits,b->edits,sizeof(a->edits)) == 0 &&
        memcmp(a->coordinates,b->coordinates,sizeof(a->coordinates)) == 0 &&
        memcmp(a->reads,b->reads,sizeof(a->reads)) == 0;
}
static void owner601_prepared_seed(const beluga_core_adaptation_state_atom_t current[179],
    beluga_core_adaptation_state_atom_t prepared[222]) {
    /* Independent literal tail ledger: generation/expected/applying/lane,
     * active/capacity/changed + optional profile, effective profile/route,
     * absent floor24 and capacity12 diagnostics. Input definition only. */
    static const uint32_t tail[54] = {
        1,1,1,6,4,4,4,7,2,2,2,3,7,2,2,2,3,6,4,
        1,4,4,4,4,2,1,1,1,1,1,3,3,1,2,2,6,6,6,6,1,6,4,
        4,6,7,1,1,1,2,2,1,1,1,1
    };
    memset(prepared,0,222*sizeof(*prepared));
    memcpy(prepared,current,168*sizeof(*prepared));
    for (uint32_t i = 0; i < 54; ++i) prepared[168+i].kind = tail[i];
    for (uint32_t i = 168; i <= 174; ++i) prepared[i].present = 1;
    for (uint32_t i = 180; i <= 186; ++i) prepared[i].present = 1;
    prepared[210].present = 1;
    prepared[168].low = 42; prepared[169].low = UINT64_MAX;
    prepared[170].low = 99; /* applying revision deliberately differs */
    prepared[180].low = 2; prepared[181].low = 333333;
    prepared[182].low = 444444; prepared[183].low = 30;
    prepared[184].low = UINT64_C(0x3ff0000000000000);
    prepared[0].low = 32123456;
    prepared[12].high = -1; prepared[12].low = UINT64_MAX - 9; /* -10 attoseconds */
}
static uint32_t owner601_call(const beluga_core_adaptation_owner_inactive_request_t *request,
    const beluga_core_adaptation_state_header_t *current_header,
    const beluga_core_adaptation_state_atom_t current[179],
    const beluga_core_adaptation_state_header_t *prepared_header,
    const beluga_core_adaptation_state_atom_t prepared[222], uint32_t output_count,
    beluga_core_adaptation_owner_clock_callback_t callback,
    owner216_clock_context_t *clock, owner601_buffers_t *output) {
    return beluga_core_network_adaptation_owner_adopt_inactive(request,current_header,current,179,
        prepared_header,prepared,222,callback,clock,&output->header,output->atoms,output_count,
        &output->metadata,&output->outcome,output->edits,13,output->coordinates,13,output->reads,15);
}
static void adaptation_owner_inactive_smoke_v1(void) {
    const beluga_core_adaptation_owner_inactive_request_t admitted =
        {1,601,UINT64_C(0xfedcba9876543210),42,1,0};
    const beluga_core_adaptation_state_header_t current_header = {1,2,1,179};
    const beluga_core_adaptation_state_header_t prepared_header = {1,4,3,222};
    beluga_core_adaptation_state_atom_t current[179]; owner105_seed(current);
    beluga_core_adaptation_state_atom_t prepared[222]; owner601_prepared_seed(current,prepared);
    /* Sticky demand fault (atom140), not queue fault alone, makes this zero-read. */
    assert(current[41].low == 1 && prepared[41].low == 1 &&
        current[140].low == 1 && prepared[140].low == 1);
    for (uint32_t mode = 0; mode < 4; ++mode) {
        beluga_core_adaptation_owner_inactive_request_t request = admitted;
        owner601_prepared_seed(current,prepared);
        if (mode == 1) request.exact_peer = 0;
        if (mode == 2) request.current_generation = 43;
        if (mode == 3) prepared[169].low = UINT64_MAX - 1;
        const beluga_core_adaptation_owner_inactive_request_t request_before = request;
        const beluga_core_adaptation_state_header_t ch_before = current_header, ph_before = prepared_header;
        beluga_core_adaptation_state_atom_t c_before[179], p_before[222];
        memcpy(c_before,current,sizeof(current)); memcpy(p_before,prepared,sizeof(prepared));
        owner216_clock_context_t clock = {0,0};
        owner601_buffers_t actual; memset(&actual,0xa5,sizeof(actual));
        assert(owner601_call(&request,&current_header,current,&prepared_header,prepared,179,
            owner216_clock,&clock,&actual) == 1 && clock.calls == 0);
        owner601_buffers_t expected; memset(&expected,0,sizeof(expected));
        expected.header = (beluga_core_adaptation_state_header_t){1,2,2,179};
        memcpy(expected.atoms,current,sizeof(current));
        if (mode == 0) {
            memcpy(expected.atoms,prepared,168*sizeof(*prepared)); expected.atoms[168].low = 0;
        }
        expected.metadata = (beluga_core_adaptation_owner_event_metadata_t){
            1,601,2,0,UINT64_C(0xfedcba9876543210),mode == 0 ? 0 : UINT64_MAX,
            10003,1,0,0,0,0,0,1,0};
        expected.outcome = (beluga_core_adaptation_owner_inactive_outcome_t){
            1,601,UINT64_C(0xfedcba9876543210),mode == 0 ? 1u : 0u,0};
        static const uint32_t time_atoms[9] = {12,23,28,159,163,167,39,40,88};
        for (uint32_t i = 0; i < 9; ++i) {
            const beluga_core_adaptation_state_atom_t value = (mode == 0 ? prepared : current)[time_atoms[i]];
            expected.edits[i] = (beluga_core_adaptation_time_edit_t){mode == 0 ? 3u : 1u,
                mode == 0 ? 2u : 0u,mode == 0 ? i : 0u,0,0,0};
            expected.coordinates[i] = (beluga_core_adaptation_time_coordinate_t){value.present,0,value.high,value.low};
        }
        assert(owner601_buffers_equal(&actual,&expected));
        assert(memcmp(&request,&request_before,sizeof(request)) == 0);
        assert(memcmp(&current_header,&ch_before,sizeof(current_header)) == 0);
        assert(memcmp(&prepared_header,&ph_before,sizeof(prepared_header)) == 0);
        assert(memcmp(current,c_before,sizeof(current)) == 0 && memcmp(prepared,p_before,sizeof(prepared)) == 0);
    }
    for (uint32_t mode = 0; mode < 12; ++mode) {
        beluga_core_adaptation_owner_inactive_request_t request = admitted;
        owner105_seed(current); owner601_prepared_seed(current,prepared);
        beluga_core_adaptation_state_header_t ch = current_header, ph = prepared_header;
        uint32_t output_count = 179;
        beluga_core_adaptation_owner_clock_callback_t callback = owner216_clock;
        if (mode == 0) request.operation = 501;
        if (mode == 1) request.abi = 2;
        if (mode == 2) request.invocation = 0;
        if (mode == 3) request.exact_peer = 2;
        if (mode == 4) request.suspended = 2;
        if (mode == 5) current[178].kind = 99;
        if (mode == 6) prepared[221].kind = 99;
        if (mode == 7) ch.phase = 2;
        if (mode == 8) ph.domain = 2;
        if (mode == 9) ph.phase = 2;
        if (mode == 10) output_count = 178;
        if (mode == 11) callback = NULL;
        const beluga_core_adaptation_owner_inactive_request_t request_before = request;
        const beluga_core_adaptation_state_header_t ch_before = ch, ph_before = ph;
        beluga_core_adaptation_state_atom_t c_before[179], p_before[222];
        memcpy(c_before,current,sizeof(current)); memcpy(p_before,prepared,sizeof(prepared));
        owner216_clock_context_t clock = {0,0};
        owner601_buffers_t actual; memset(&actual,0xa5,sizeof(actual)); const owner601_buffers_t sentinel = actual;
        assert(owner601_call(&request,&ch,current,&ph,prepared,output_count,callback,&clock,&actual) == 2);
        assert(clock.calls == 0 && owner601_buffers_equal(&actual,&sentinel));
        assert(memcmp(&request,&request_before,sizeof(request)) == 0);
        assert(memcmp(&ch,&ch_before,sizeof(ch)) == 0 && memcmp(&ph,&ph_before,sizeof(ph)) == 0);
        assert(memcmp(current,c_before,sizeof(current)) == 0 && memcmp(prepared,p_before,sizeof(prepared)) == 0);
    }
    puts("BelugaCore C adaptation Owner inactive PASS: layouts, full179 adoption/stale, nine origins, twelve untouched denials");
}

/* Public701 scalar ABI smoke; synthetic POD is not genuine native preparation. */
_Static_assert(sizeof(beluga_core_adaptation_owner_begin_active_request_t) == 24, "701 request size");
_Static_assert(_Alignof(beluga_core_adaptation_owner_begin_active_request_t) == 8, "701 request alignment");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_request_t, abi) == 0, "701 abi offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_request_t, operation) == 4, "701 op offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_request_t, invocation) == 8, "701 invocation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_request_t, resource_flags) == 16, "701 flags offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_request_t, reserved) == 20, "701 reserved offset");
_Static_assert(sizeof(beluga_core_adaptation_owner_begin_active_outcome_t) == 32, "701 outcome size");
_Static_assert(_Alignof(beluga_core_adaptation_owner_begin_active_outcome_t) == 8, "701 outcome alignment");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_outcome_t, abi) == 0, "701 outcome abi offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_outcome_t, operation) == 4, "701 outcome op offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_outcome_t, invocation) == 8, "701 outcome invocation offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_outcome_t, disposition) == 16, "701 disposition offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_outcome_t, route) == 20, "701 route offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_outcome_t, prepared_present) == 24, "701 prepared offset");
_Static_assert(offsetof(beluga_core_adaptation_owner_begin_active_outcome_t, reserved) == 28, "701 outcome reserved offset");
typedef struct {
    beluga_core_adaptation_state_header_t header;
    beluga_core_adaptation_state_atom_t atoms[179];
    beluga_core_adaptation_state_header_t prepared_header;
    beluga_core_adaptation_state_atom_t prepared_atoms[222];
    beluga_core_adaptation_owner_event_metadata_t metadata;
    beluga_core_adaptation_owner_begin_active_outcome_t outcome;
    beluga_core_adaptation_time_edit_t edits[13];
    beluga_core_adaptation_time_coordinate_t coordinates[13];
    beluga_core_adaptation_clock_reply_t reads[15];
} owner701_buffers_t;
static int owner701_buffers_equal(const owner701_buffers_t *a, const owner701_buffers_t *b) {
    /* Compare each initialized ABI object, never enclosing-struct padding. */
    return memcmp(&a->header,&b->header,sizeof(a->header)) == 0 &&
        memcmp(a->atoms,b->atoms,sizeof(a->atoms)) == 0 &&
        memcmp(&a->prepared_header,&b->prepared_header,sizeof(a->prepared_header)) == 0 &&
        memcmp(a->prepared_atoms,b->prepared_atoms,sizeof(a->prepared_atoms)) == 0 &&
        memcmp(&a->metadata,&b->metadata,sizeof(a->metadata)) == 0 &&
        memcmp(&a->outcome,&b->outcome,sizeof(a->outcome)) == 0 &&
        memcmp(a->edits,b->edits,sizeof(a->edits)) == 0 &&
        memcmp(a->coordinates,b->coordinates,sizeof(a->coordinates)) == 0 &&
        memcmp(a->reads,b->reads,sizeof(a->reads)) == 0;
}
static void adaptation_owner_begin_active_smoke_v1(void) {
    const uint64_t invocation = UINT64_C(0xfedcba9876543210);
    for (uint32_t mode = 0; mode < 16; ++mode) {
        beluga_core_adaptation_owner_begin_active_request_t request = {1,701,invocation,0,0};
        beluga_core_adaptation_state_header_t ch = {1,2,1,179}, ph = {1,4,3,222};
        beluga_core_adaptation_state_atom_t current[179]; owner105_seed(current);
        beluga_core_adaptation_state_atom_t prepared[222]; owner601_prepared_seed(current,prepared);
        prepared[89].low = 0; prepared[140].low = 0;
        if (mode == 1) {
            current[173].low = 1;
            current[174].low = 2; current[175].low = 333333; current[176].low = 444444;
            current[177].low = 30; current[178].low = UINT64_C(0x3ff0000000000000);
        } else {
            current[173].low = 0;
            for (uint32_t i = 174; i <= 178; ++i) {
                current[i].present = 0; current[i].high = 0; current[i].low = 0;
            }
        }
        uint32_t output_count = 179, output_prepared_count = 222, edit_count = 13;
        beluga_core_adaptation_owner_clock_callback_t callback = owner216_clock;
        if (mode == 2) request.operation = 702;
        if (mode == 3) request.abi = 2;
        if (mode == 4) request.invocation = 0;
        if (mode == 5) request.resource_flags = 64;
        if (mode == 6) request.reserved = 1;
        if (mode == 7) current[178].kind = 99;
        if (mode == 8) prepared[221].kind = 99;
        if (mode == 9) ch.phase = 2;
        if (mode == 10) ph.domain = 2;
        if (mode == 11) ph.phase = 2;
        if (mode == 12) output_count = 178;
        if (mode == 13) output_prepared_count = 221;
        if (mode == 14) callback = NULL;
        if (mode == 15) edit_count = 12;
        const beluga_core_adaptation_owner_begin_active_request_t request_before = request;
        const beluga_core_adaptation_state_header_t ch_before = ch, ph_before = ph;
        beluga_core_adaptation_state_atom_t current_before[179], prepared_before[222];
        memcpy(current_before,current,sizeof(current)); memcpy(prepared_before,prepared,sizeof(prepared));
        owner216_clock_context_t clock = {0,0};
        owner701_buffers_t actual; memset(&actual,0xa5,sizeof(actual)); const owner701_buffers_t sentinel = actual;
        const uint32_t status = beluga_core_network_adaptation_owner_begin_active(&request,&ch,current,179,
            &ph,prepared,222,callback,&clock,&actual.header,actual.atoms,output_count,
            &actual.prepared_header,actual.prepared_atoms,output_prepared_count,&actual.metadata,&actual.outcome,
            actual.edits,edit_count,actual.coordinates,13,actual.reads,15);
        assert(clock.calls == 0);
        if (mode >= 2) {
            assert(status == 2 && owner701_buffers_equal(&actual,&sentinel));
        } else {
            assert(status == 1);
            owner701_buffers_t expected; memset(&expected,0,sizeof(expected));
            expected.header = (beluga_core_adaptation_state_header_t){1,2,2,179};
            memcpy(expected.atoms,current,sizeof(current));
            if (mode == 1) {
                expected.prepared_header = ph; memcpy(expected.prepared_atoms,prepared,sizeof(prepared));
            }
            expected.metadata = (beluga_core_adaptation_owner_event_metadata_t){
                1,701,2,0,invocation,UINT64_MAX,10003,1,0,0,0,0,0,1,0};
            expected.outcome = (beluga_core_adaptation_owner_begin_active_outcome_t){
                1,701,invocation,mode,0,mode,0};
            static const uint32_t time_atoms[9] = {12,23,28,159,163,167,39,40,88};
            for (uint32_t i = 0; i < 9; ++i) {
                const beluga_core_adaptation_state_atom_t value = current[time_atoms[i]];
                expected.edits[i] = (beluga_core_adaptation_time_edit_t){1,0,0,0,0,0};
                expected.coordinates[i] = (beluga_core_adaptation_time_coordinate_t){value.present,0,value.high,value.low};
            }
            assert(owner701_buffers_equal(&actual,&expected));
        }
        assert(memcmp(&request,&request_before,sizeof(request)) == 0);
        assert(memcmp(&ch,&ch_before,sizeof(ch)) == 0 && memcmp(&ph,&ph_before,sizeof(ph)) == 0);
        assert(memcmp(current,current_before,sizeof(current)) == 0 && memcmp(prepared,prepared_before,sizeof(prepared)) == 0);
    }
    puts("BelugaCore C adaptation Owner begin-active PASS: layouts, exact179/222 Return/NoNativeApply, fourteen untouched denials");
}

/* Public702/703/704 C scalar link smoke. All resources/Prepared are synthetic. */
#define OWNER_COMPLETION_LAYOUT(type) \
    _Static_assert(sizeof(type)==32, "completion ABI size"); \
    _Static_assert(_Alignof(type)==8, "completion ABI alignment"); \
    _Static_assert(offsetof(type,abi)==0, "completion ABI abi"); \
    _Static_assert(offsetof(type,operation)==4, "completion ABI operation"); \
    _Static_assert(offsetof(type,invocation)==8, "completion ABI invocation")
OWNER_COMPLETION_LAYOUT(beluga_core_adaptation_owner_completion_request_t);
OWNER_COMPLETION_LAYOUT(beluga_core_adaptation_owner_failure_request_t);
OWNER_COMPLETION_LAYOUT(beluga_core_adaptation_owner_completion_outcome_t);
OWNER_COMPLETION_LAYOUT(beluga_core_adaptation_owner_failure_outcome_t);
_Static_assert(offsetof(beluga_core_adaptation_owner_completion_request_t,current_generation)==16,"completion generation");
_Static_assert(offsetof(beluga_core_adaptation_owner_completion_request_t,facts)==24,"completion facts");
_Static_assert(offsetof(beluga_core_adaptation_owner_completion_request_t,reserved)==28,"completion reserved");
_Static_assert(offsetof(beluga_core_adaptation_owner_completion_outcome_t,disposition)==16,"completion disposition");
_Static_assert(offsetof(beluga_core_adaptation_owner_completion_outcome_t,route)==20,"completion route");
_Static_assert(offsetof(beluga_core_adaptation_owner_completion_outcome_t,fps_changed)==24,"completion fps");
_Static_assert(offsetof(beluga_core_adaptation_owner_completion_outcome_t,reserved)==28,"completion outcome reserved");
_Static_assert(offsetof(beluga_core_adaptation_owner_failure_outcome_t,disposition)==16,"failure disposition");
_Static_assert(offsetof(beluga_core_adaptation_owner_failure_outcome_t,route)==20,"failure route");
_Static_assert(offsetof(beluga_core_adaptation_owner_failure_outcome_t,semantic_error)==24,"failure semantic error");
_Static_assert(offsetof(beluga_core_adaptation_owner_failure_outcome_t,attempted_reads)==28,"failure attempted reads");
#undef OWNER_COMPLETION_LAYOUT
typedef struct {
    beluga_core_adaptation_state_header_t header;
    beluga_core_adaptation_state_atom_t atoms[179];
    beluga_core_adaptation_owner_event_metadata_t metadata;
    union {
        beluga_core_adaptation_owner_completion_outcome_t completion;
        beluga_core_adaptation_owner_failure_outcome_t failure;
    } outcome;
    beluga_core_adaptation_time_edit_t edits[13];
    beluga_core_adaptation_time_coordinate_t coordinates[13];
    beluga_core_adaptation_clock_reply_t reads[15];
} owner_completion_buffers_t;
static int owner_completion_equal(const owner_completion_buffers_t *a,const owner_completion_buffers_t *b) {
    return memcmp(&a->header,&b->header,sizeof(a->header))==0 &&
        memcmp(a->atoms,b->atoms,sizeof(a->atoms))==0 &&
        memcmp(&a->metadata,&b->metadata,sizeof(a->metadata))==0 &&
        memcmp(&a->outcome,&b->outcome,sizeof(a->outcome))==0 &&
        memcmp(a->edits,b->edits,sizeof(a->edits))==0 &&
        memcmp(a->coordinates,b->coordinates,sizeof(a->coordinates))==0 &&
        memcmp(a->reads,b->reads,sizeof(a->reads))==0;
}
typedef struct {
    uint32_t calls, unpublished;
    uint64_t invocation;
    int64_t fps;
    const owner_completion_buffers_t *output,*sentinel;
} owner_completion_effect_t;
static void owner_completion_output(void *context,uint64_t invocation,int64_t fps) {
    owner_completion_effect_t *effect=context;
    effect->calls++; effect->invocation=invocation; effect->fps=fps;
    effect->unpublished=owner_completion_equal(effect->output,effect->sentinel);
}
typedef struct {
    owner_completion_effect_t effect;
    uint32_t calls, reply, counts[3], unpublished, trace[2], trace_count;
    uint64_t invocation;
    owner_completion_buffers_t draft;
} owner_completion_validation_t;
static uint32_t owner_completion_validate(void *context,uint64_t invocation,
    const beluga_core_adaptation_state_header_t *header,
    const beluga_core_adaptation_state_atom_t *atoms,uint32_t atom_count,
    const beluga_core_adaptation_owner_event_metadata_t *metadata,
    const beluga_core_adaptation_owner_completion_outcome_t *outcome,
    const beluga_core_adaptation_time_edit_t *edits,uint32_t edit_count,
    const beluga_core_adaptation_time_coordinate_t *coordinates,uint32_t coordinate_count) {
    owner_completion_validation_t *v=context;
    v->calls++; v->invocation=invocation;
    v->counts[0]=atom_count; v->counts[1]=edit_count; v->counts[2]=coordinate_count;
    v->unpublished=owner_completion_equal(v->effect.output,v->effect.sentinel);
    if(v->trace_count<2) v->trace[v->trace_count++]=1;
    if(!header || !atoms || !metadata || !outcome || !edits || !coordinates ||
        atom_count!=179 || edit_count!=13 || coordinate_count!=13) return 2;
    v->draft=*v->effect.sentinel; /* Unowned reads retain their original sentinel. */
    v->draft.header=*header; memcpy(v->draft.atoms,atoms,sizeof(v->draft.atoms));
    v->draft.metadata=*metadata; v->draft.outcome.completion=*outcome;
    memcpy(v->draft.edits,edits,sizeof(v->draft.edits));
    memcpy(v->draft.coordinates,coordinates,sizeof(v->draft.coordinates));
    return v->reply;
}
static void owner_completion_validated_output(void *context,uint64_t invocation,int64_t fps) {
    owner_completion_validation_t *v=context;
    if(v->trace_count<2) v->trace[v->trace_count++]=2;
    owner_completion_output(&v->effect,invocation,fps);
}
static void adaptation_owner_completion_smoke_v1(void) {
    const uint64_t invocation=UINT64_C(0xfedcba9876543210);
    for(uint32_t operation=702;operation<=704;++operation) {
        for(uint32_t mode=0;mode<15;++mode) {
            beluga_core_adaptation_owner_completion_request_t request={1,operation,invocation,42,
                mode==0?0:(operation==704?1:511),0};
            beluga_core_adaptation_state_header_t ch={1,2,1,179},ph={1,4,3,222};
            beluga_core_adaptation_state_atom_t current[179]; owner105_seed(current);
            beluga_core_adaptation_state_atom_t prepared[222]; owner601_prepared_seed(current,prepared);
            prepared[170].low=UINT64_MAX; prepared[185].low=2;
            /*703 ordinary branch: no new negative observation or cancelled floor. */
            prepared[151].low=0; prepared[154].low=0;
            if(mode==2 && operation==702) current[177].low=30;
            uint32_t output_count=179,edit_count=13,coordinate_count=13;
            if(mode==3) request.abi=2;
            if(mode==4) request.operation=701;
            if(mode==5) request.invocation=0;
            if(mode==6) request.facts=operation==704?2:512;
            if(mode==7) request.reserved=1;
            if(mode==8) current[178].kind=99;
            if(mode==9) prepared[221].kind=99;
            if(mode==10) ch.phase=2;
            if(mode==11) ph.phase=2;
            if(mode==12) output_count=178;
            if(mode==13) edit_count=12;
            if(mode==14 && operation==704) coordinate_count=12;
            const beluga_core_adaptation_owner_completion_request_t request_before=request;
            const beluga_core_adaptation_state_header_t ch_before=ch,ph_before=ph;
            beluga_core_adaptation_state_atom_t current_before[179],prepared_before[222];
            memcpy(current_before,current,sizeof(current)); memcpy(prepared_before,prepared,sizeof(prepared));
            owner_completion_buffers_t actual; memset(&actual,0xa5,sizeof(actual));
            /*702/704 do not own a read buffer. Keep its sentinel while comparing. */
            const owner_completion_buffers_t sentinel=actual;
            owner_completion_effect_t effect={0,0,0,0,&actual,&sentinel};
            owner216_clock_context_t clock={0,0}; uint32_t status;
            if(operation==702) {
                status=beluga_core_network_adaptation_owner_finish_success(&request,&ch,current,179,&ph,prepared,222,
                    mode==14?NULL:owner_completion_output,&effect,&actual.header,actual.atoms,output_count,
                    &actual.metadata,&actual.outcome.completion,actual.edits,edit_count,actual.coordinates,coordinate_count);
            } else if(operation==703) {
                status=beluga_core_network_adaptation_owner_finish_failure(&request,&ch,current,179,&ph,prepared,222,
                    mode==14?NULL:owner216_clock,&clock,&actual.header,actual.atoms,output_count,
                    &actual.metadata,&actual.outcome.failure,actual.edits,edit_count,actual.coordinates,coordinate_count,actual.reads,15);
            } else {
                status=beluga_core_network_adaptation_owner_final_adopt(&request,&ch,current,179,&ph,prepared,222,
                    &actual.header,actual.atoms,output_count,&actual.metadata,&actual.outcome.completion,
                    actual.edits,edit_count,actual.coordinates,coordinate_count);
            }
            assert(clock.calls==0);
            if(mode>=3) {
                assert(status==2 && owner_completion_equal(&actual,&sentinel));
                assert(effect.calls==0);
            } else {
                assert(status==1);
                owner_completion_buffers_t expected; memset(&expected,0,sizeof(expected));
                if(operation!=703) memcpy(expected.reads,sentinel.reads,sizeof(expected.reads));
                expected.header=(beluga_core_adaptation_state_header_t){1,2,2,179};
                memcpy(expected.atoms,current,sizeof(current));
                const uint32_t accepted=mode!=0;
                if(accepted && operation==702) {
                    expected.atoms[173].low=1;
                    for(uint32_t i=0;i<5;++i) expected.atoms[174+i].low=prepared[180+i].low;
                } else if(accepted && operation==703) expected.atoms[168].low=0;
                else if(accepted && operation==704) {
                    memcpy(expected.atoms,prepared,168*sizeof(*prepared)); expected.atoms[168].low=0;
                }
                const uint32_t route=accepted && operation==704?2:0;
                const uint32_t fps_changed=accepted && operation==702 && mode!=2;
                expected.metadata=(beluga_core_adaptation_owner_event_metadata_t){
                    1,operation,2,0,invocation,expected.atoms[168].low,10003,1,0,route,0,0,0,1,0};
                if(operation==703) expected.outcome.failure=(beluga_core_adaptation_owner_failure_outcome_t){
                    1,703,invocation,accepted,0,0,0};
                else expected.outcome.completion=(beluga_core_adaptation_owner_completion_outcome_t){
                    1,operation,invocation,accepted,route,fps_changed,0};
                static const uint32_t time_atoms[9]={12,23,28,159,163,167,39,40,88};
                for(uint32_t i=0;i<9;++i) {
                    const beluga_core_adaptation_state_atom_t value=expected.atoms[time_atoms[i]];
                    if(accepted && operation==704)
                        expected.edits[i]=(beluga_core_adaptation_time_edit_t){value.present?3:2,value.present?2:0,value.present?i:0,0,0,0};
                    else expected.edits[i]=(beluga_core_adaptation_time_edit_t){1,0,0,0,0,0};
                    expected.coordinates[i]=(beluga_core_adaptation_time_coordinate_t){value.present,0,value.high,value.low};
                }
                assert(owner_completion_equal(&actual,&expected));
                assert(effect.calls==fps_changed);
                if(fps_changed) assert(effect.unpublished==1 && effect.invocation==invocation && effect.fps==30);
            }
            if(operation==702) {
                const owner_completion_buffers_t legacy=actual;
                const uint32_t replies[]={1,0,2,UINT32_MAX};
                for(uint32_t admission=0;admission<5;++admission) {
                    actual=sentinel;
                    owner_completion_validation_t validation={0};
                    validation.effect=(owner_completion_effect_t){0,0,0,0,&actual,&sentinel};
                    validation.reply=admission<4?replies[admission]:1;
                    const uint32_t checked=beluga_core_network_adaptation_owner_finish_success_validated(
                        &request,&ch,current,179,&ph,prepared,222,
                        admission==4?NULL:owner_completion_validate,
                        mode==14?NULL:owner_completion_validated_output,&validation,
                        &actual.header,actual.atoms,output_count,&actual.metadata,&actual.outcome.completion,
                        actual.edits,edit_count,actual.coordinates,coordinate_count);
                    if(mode>=3 || admission==4) {
                        assert(checked==2 && owner_completion_equal(&actual,&sentinel));
                        assert(validation.calls==0 && validation.effect.calls==0 && validation.trace_count==0);
                    } else {
                        assert(validation.calls==1 && validation.invocation==invocation && validation.unpublished==1);
                        assert(validation.counts[0]==179 && validation.counts[1]==13 && validation.counts[2]==13);
                        assert(owner_completion_equal(&validation.draft,&legacy));
                        assert(validation.trace[0]==1);
                        if(admission==0) {
                            assert(checked==1 && owner_completion_equal(&actual,&legacy));
                            assert(validation.effect.calls==legacy.outcome.completion.fps_changed);
                            assert(validation.trace_count==1+validation.effect.calls);
                            if(validation.effect.calls) assert(validation.trace[1]==2 && validation.effect.unpublished==1 &&
                                validation.effect.invocation==invocation && validation.effect.fps==30);
                        } else {
                            assert(checked==3 && owner_completion_equal(&actual,&sentinel));
                            assert(validation.effect.calls==0 && validation.trace_count==1);
                        }
                    }
                }
            }
            assert(memcmp(&request,&request_before,sizeof(request))==0);
            assert(memcmp(&ch,&ch_before,sizeof(ch))==0 && memcmp(&ph,&ph_before,sizeof(ph))==0);
            assert(memcmp(current,current_before,sizeof(current))==0 && memcmp(prepared,prepared_before,sizeof(prepared))==0);
        }
    }
    puts("BelugaCore C adaptation Owner completion PASS: 702/703/704 layouts, exact179 results, effect-before-publication, untouched denials");
    puts("BelugaCore C adaptation Owner validated702 PASS: actual private bundle, validator-before-effect, stale/sameFPS, strict denial and missing thunks");
}

/* Add before existing main, then call microphone_forwarding_evidence_smoke_v1(). */
#define MIC_SIZE(type, size) _Static_assert(sizeof(type) == size, #type " size")
#define MIC_OFF(type, field, offset) _Static_assert(offsetof(type, field) == offset, #type "." #field " offset")
#define MIC_EQ(actual, expected) assert(memcmp(&(actual), &(expected), sizeof(expected)) == 0)
static void microphone_forwarding_evidence_smoke_v1(void) {
    MIC_SIZE(beluga_core_microphone_optional_u64_t, 16);
    MIC_SIZE(beluga_core_microphone_progress_t, 40);
    MIC_SIZE(beluga_core_microphone_readiness_facts_t, 96);
    MIC_SIZE(beluga_core_microphone_readiness_result_t, 16);
    MIC_SIZE(beluga_core_microphone_watermark_t, 72);
    MIC_SIZE(beluga_core_microphone_watermark_state_t, 80);
    MIC_SIZE(beluga_core_microphone_watermark_event_t, 80);
    MIC_SIZE(beluga_core_microphone_watermark_result_t, 96);
    MIC_SIZE(beluga_core_microphone_freshness_state_t, 40);
    MIC_SIZE(beluga_core_microphone_freshness_event_t, 32);
    MIC_SIZE(beluga_core_microphone_freshness_result_t, 16);
    _Static_assert(_Alignof(beluga_core_microphone_watermark_result_t) == 8, "watermark alignment");
    MIC_OFF(beluga_core_microphone_optional_u64_t, value, 8);
    MIC_OFF(beluga_core_microphone_progress_t, post_start_callback_count, 8);
    MIC_OFF(beluga_core_microphone_progress_t, successful_pull_count, 16);
    MIC_OFF(beluga_core_microphone_progress_t, successful_frame_count, 24);
    MIC_OFF(beluga_core_microphone_progress_t, enqueue_failure_count, 32);
    MIC_OFF(beluga_core_microphone_readiness_facts_t, current, 8);
    MIC_OFF(beluga_core_microphone_readiness_facts_t, previous_present, 48);
    MIC_OFF(beluga_core_microphone_readiness_facts_t, previous, 56);
    MIC_OFF(beluga_core_microphone_readiness_result_t, continuing, 12);
    MIC_OFF(beluga_core_microphone_watermark_t, fields, 8);
    MIC_OFF(beluga_core_microphone_watermark_state_t, retained, 8);
    MIC_OFF(beluga_core_microphone_watermark_event_t, current, 8);
    MIC_OFF(beluga_core_microphone_watermark_result_t, status, 80);
    MIC_OFF(beluga_core_microphone_watermark_result_t, continuous, 84);
    MIC_OFF(beluga_core_microphone_watermark_result_t, did_advance, 88);
    MIC_OFF(beluga_core_microphone_freshness_state_t, advancement_count, 8);
    MIC_OFF(beluga_core_microphone_freshness_state_t, consecutive_stale_samples, 16);
    MIC_OFF(beluga_core_microphone_freshness_state_t, deadline, 24);
    MIC_OFF(beluga_core_microphone_freshness_event_t, maximum_stale_samples, 8);
    MIC_OFF(beluga_core_microphone_freshness_event_t, now, 16);
    MIC_OFF(beluga_core_microphone_freshness_result_t, fresh, 8);

    beluga_core_microphone_readiness_facts_t facts = {1, 0, {1,0,2,1,480,0}, 1,0,{1,0,1,1,479,0}};
    const beluga_core_microphone_readiness_facts_t original_facts = facts;
    beluga_core_microphone_readiness_result_t health = beluga_core_microphone_forwarding_readiness_decide(facts);
    beluga_core_microphone_readiness_result_t expected_health = {1,1,1,1};
    MIC_EQ(health, expected_health); MIC_EQ(facts, original_facts);
    for (unsigned mode = 0; mode < 8; mode++) {
        facts = original_facts;
        if (mode == 0) facts.abi_version = 2;
        if (mode == 1) facts.reserved = 1;
        if (mode == 2) facts.current.queue_running = 2;
        if (mode == 3) facts.current.reserved = 1;
        if (mode == 4) facts.previous_present = 2;
        if (mode == 5) facts.previous_reserved = 1;
        if (mode == 6) facts.previous.queue_running = 2;
        if (mode == 7) facts.previous.reserved = 1;
        const beluga_core_microphone_readiness_facts_t before = facts;
        health = beluga_core_microphone_forwarding_readiness_decide(facts);
        expected_health = (beluga_core_microphone_readiness_result_t){1,0,0,0};
        MIC_EQ(health, expected_health); MIC_EQ(facts, before);
    }
    facts = original_facts; facts.previous_present = 0; facts.previous.queue_running = 9; facts.previous.reserved = 7;
    health = beluga_core_microphone_forwarding_readiness_decide(facts);
    expected_health = (beluga_core_microphone_readiness_result_t){1,1,1,0}; MIC_EQ(health, expected_health);
    for (unsigned counter = 0; counter < 2; counter++) {
        facts = original_facts;
        if (counter == 0) facts.current.post_start_callback_count = 1;
        else facts.current.successful_frame_count = 479;
        health = beluga_core_microphone_forwarding_readiness_decide(facts); MIC_EQ(health, expected_health);
    }

    beluga_core_microphone_watermark_state_t state = {1,0,{1,0,{{1,0,10},{1,0,100},{1,0,20},{1,0,200}}}};
    beluga_core_microphone_watermark_event_t event = {1,0,{1,0,{{1,0,11},{1,0,101},{0,0,UINT64_MAX},{0,0,UINT64_MAX}}}};
    const beluga_core_microphone_watermark_state_t original_state = state;
    const beluga_core_microphone_watermark_event_t original_event = event;
    beluga_core_microphone_watermark_result_t marked = beluga_core_microphone_forwarding_watermark_step(state, event);
    beluga_core_microphone_watermark_result_t expected_marked = {{1,0,{1,0,{{1,0,11},{1,0,101},{1,0,20},{1,0,200}}}},1,1,1,0};
    MIC_EQ(marked, expected_marked); MIC_EQ(state, original_state); MIC_EQ(event, original_event);
    for (unsigned mode = 0; mode < 8; mode++) {
        state = original_state; event = original_event;
        if (mode == 0) state.abi_version = 2;
        if (mode == 1) state.reserved = 1;
        if (mode == 2) state.retained.present = 2;
        if (mode == 3) state.retained.fields[0].reserved = 1;
        if (mode == 4) event.abi_version = 2;
        if (mode == 5) event.reserved = 1;
        if (mode == 6) event.current.present = 2;
        if (mode == 7) event.current.fields[0].present = 2;
        const beluga_core_microphone_watermark_state_t before = state;
        const beluga_core_microphone_watermark_event_t before_event = event;
        marked = beluga_core_microphone_forwarding_watermark_step(state, event);
        expected_marked = (beluga_core_microphone_watermark_result_t){before,0,0,0,0};
        MIC_EQ(marked, expected_marked); MIC_EQ(state, before); MIC_EQ(event, before_event);
    }
    state = original_state; event = original_event; event.current.fields[0].value = 9;
    marked = beluga_core_microphone_forwarding_watermark_step(state, event);
    expected_marked = (beluga_core_microphone_watermark_result_t){state,1,0,0,0}; MIC_EQ(marked, expected_marked);
    event.current.present = 0; event.current.reserved = 0;
    event.current.fields[0].present = 9; event.current.fields[0].reserved = 7;
    marked = beluga_core_microphone_forwarding_watermark_step(state, event); MIC_EQ(marked, expected_marked);

    beluga_core_microphone_freshness_state_t fresh_state = {1,0,1,0,{1,0,100}};
    beluga_core_microphone_freshness_event_t fresh_event = {1,0,3,{0,0,UINT64_MAX}};
    const beluga_core_microphone_freshness_state_t original_fresh_state = fresh_state;
    const beluga_core_microphone_freshness_event_t original_fresh_event = fresh_event;
    beluga_core_microphone_freshness_result_t fresh = beluga_core_microphone_forwarding_freshness_decide(fresh_state, fresh_event);
    beluga_core_microphone_freshness_result_t expected_fresh = {1,2,0,0}; MIC_EQ(fresh, expected_fresh);
    /* These are explicit scalar inputs, not a native clock callback or permission. */
    fresh_event.now = (beluga_core_microphone_optional_u64_t){1,0,99};
    fresh = beluga_core_microphone_forwarding_freshness_decide(fresh_state, fresh_event);
    expected_fresh = (beluga_core_microphone_freshness_result_t){1,1,1,0}; MIC_EQ(fresh, expected_fresh);
    fresh_event.now.value = 100;
    fresh = beluga_core_microphone_forwarding_freshness_decide(fresh_state, fresh_event);
    expected_fresh = (beluga_core_microphone_freshness_result_t){1,1,0,0}; MIC_EQ(fresh, expected_fresh);
    fresh_state.deadline.present = 0; fresh_event.now = original_fresh_event.now;
    fresh = beluga_core_microphone_forwarding_freshness_decide(fresh_state, fresh_event); MIC_EQ(fresh, expected_fresh);
    for (unsigned mode = 0; mode < 8; mode++) {
        fresh_state = original_fresh_state; fresh_event = original_fresh_event;
        if (mode == 0) fresh_state.abi_version = 2;
        if (mode == 1) fresh_state.reserved = 1;
        if (mode == 2) fresh_state.deadline.present = 2;
        if (mode == 3) fresh_state.deadline.reserved = 1;
        if (mode == 4) fresh_event.abi_version = 2;
        if (mode == 5) fresh_event.reserved = 1;
        if (mode == 6) fresh_event.now.present = 2;
        if (mode == 7) fresh_event.now.reserved = 1;
        const beluga_core_microphone_freshness_state_t before = fresh_state;
        const beluga_core_microphone_freshness_event_t before_event = fresh_event;
        fresh = beluga_core_microphone_forwarding_freshness_decide(fresh_state, fresh_event);
        expected_fresh = (beluga_core_microphone_freshness_result_t){1,0,0,0};
        MIC_EQ(fresh, expected_fresh); MIC_EQ(fresh_state, before); MIC_EQ(fresh_event, before_event);
    }
    puts("BelugaCore C microphone evidence ABI PASS: copied layouts, whole results, refusal and conditional NeedsNow");
}
#undef MIC_SIZE
#undef MIC_OFF
#undef MIC_EQ

/* Append before main; copied correlation only, no native resource or clock calls. */
static void microphone_forwarding_result_correlation_smoke_v1(void) {
    beluga_core_microphone_readiness_facts_t facts = {1,0,{1,0,2,1,480,0},1,0,{1,0,1,1,479,0}};
    const beluga_core_microphone_readiness_facts_t saved_facts = facts;
    beluga_core_microphone_readiness_result_t ready = {1,1,1,1};
    const beluga_core_microphone_readiness_result_t saved_ready = ready;
    assert(beluga_core_microphone_forwarding_readiness_result_is_valid(facts, ready) == 1);
    ready.ready = 0; ready.continuing = 0; /* coherent but wrong for these exact facts */
    assert(beluga_core_microphone_forwarding_readiness_result_is_valid(facts, ready) == 0);
    facts.current.successful_pull_count = 0;
    assert(beluga_core_microphone_forwarding_readiness_result_is_valid(facts, ready) == 1);
    facts = saved_facts; facts.abi_version = 2;
    ready = (beluga_core_microphone_readiness_result_t){1,0,0,0};
    assert(beluga_core_microphone_forwarding_readiness_result_is_valid(facts, ready) == 0);
    facts = saved_facts; ready = saved_ready;
    assert(beluga_core_microphone_forwarding_readiness_result_is_valid(facts, ready) == 1);
    assert(memcmp(&facts, &saved_facts, sizeof facts) == 0);
    assert(memcmp(&ready, &saved_ready, sizeof ready) == 0);

    beluga_core_microphone_watermark_state_t before = {1,0,{1,0,{{1,0,10},{1,0,100},{1,0,20},{1,0,200}}}};
    beluga_core_microphone_watermark_event_t event = {1,0,{1,0,{{1,0,11},{1,0,101},{0,0,0},{0,0,0}}}};
    beluga_core_microphone_watermark_result_t marked = {{1,0,{1,0,{{1,0,11},{1,0,101},{1,0,20},{1,0,200}}}},1,1,1,0};
    const beluga_core_microphone_watermark_state_t saved_before = before;
    const beluga_core_microphone_watermark_event_t saved_event = event;
    const beluga_core_microphone_watermark_result_t saved_marked = marked;
    assert(beluga_core_microphone_forwarding_watermark_result_is_valid(before, event, marked) == 1);
    marked = (beluga_core_microphone_watermark_result_t){before,1,0,0,0};
    assert(beluga_core_microphone_forwarding_watermark_result_is_valid(before, event, marked) == 0);
    event.current.fields[0].value = 9;
    assert(beluga_core_microphone_forwarding_watermark_result_is_valid(before, event, marked) == 1);
    event = saved_event; event.abi_version = 2; marked.status = 0;
    assert(beluga_core_microphone_forwarding_watermark_result_is_valid(before, event, marked) == 0);
    before = saved_before; event = saved_event; marked = saved_marked;
    assert(beluga_core_microphone_forwarding_watermark_result_is_valid(before, event, marked) == 1);
    assert(memcmp(&before, &saved_before, sizeof before) == 0);
    assert(memcmp(&event, &saved_event, sizeof event) == 0);
    assert(memcmp(&marked, &saved_marked, sizeof marked) == 0);

    beluga_core_microphone_freshness_state_t state = {1,0,1,0,{1,0,100}};
    beluga_core_microphone_freshness_event_t sample = {1,0,3,{0,0,UINT64_MAX}};
    beluga_core_microphone_freshness_result_t freshness = {1,2,0,0};
    const beluga_core_microphone_freshness_state_t saved_state = state;
    const beluga_core_microphone_freshness_event_t saved_sample = sample;
    const beluga_core_microphone_freshness_result_t saved_freshness = freshness;
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(state, sample, freshness) == 1);
    freshness = (beluga_core_microphone_freshness_result_t){1,1,1,0};
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(state, sample, freshness) == 0);
    sample.now = (beluga_core_microphone_optional_u64_t){1,0,99};
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(state, sample, freshness) == 1);
    sample.now.value = 100; freshness.fresh = 0;
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(state, sample, freshness) == 1);
    sample = saved_sample; state.abi_version = 2;
    freshness = (beluga_core_microphone_freshness_result_t){1,0,0,0};
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(state, sample, freshness) == 0);
    state = saved_state; freshness = saved_freshness;
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(state, sample, freshness) == 1);
    assert(memcmp(&state, &saved_state, sizeof state) == 0);
    assert(memcmp(&sample, &saved_sample, sizeof sample) == 0);
    assert(memcmp(&freshness, &saved_freshness, sizeof freshness) == 0);
    puts("BelugaCore C microphone result correlation PASS: exact result, coherent corruption, refusal and NeedsNow");
}

/* Additive per-key retry ABI coverage; genuine imported product PODs only. */
typedef beluga_core_microphone_forwarding_retry_config_t mic_retry_config_t;
typedef beluga_core_microphone_forwarding_retry_state_t mic_retry_state_t;
typedef beluga_core_microphone_forwarding_retry_event_t mic_retry_event_t;
typedef beluga_core_microphone_forwarding_retry_result_t mic_retry_result_t;

#define MIC_RETRY_LAYOUT(type, bytes, alignment) \
    _Static_assert(sizeof(type) == bytes, #type " size"); \
    _Static_assert(_Alignof(type) == alignment, #type " alignment")
#define MIC_RETRY_OFFSET(type, field, value) \
    _Static_assert(offsetof(type, field) == value, #type "." #field " offset")
MIC_RETRY_LAYOUT(mic_retry_config_t, 16, 8);
MIC_RETRY_LAYOUT(mic_retry_state_t, 24, 8);
MIC_RETRY_LAYOUT(mic_retry_event_t, 16, 4);
MIC_RETRY_LAYOUT(mic_retry_result_t, 40, 8);
MIC_RETRY_OFFSET(mic_retry_config_t, abi_version, 0);
MIC_RETRY_OFFSET(mic_retry_config_t, reserved, 4);
MIC_RETRY_OFFSET(mic_retry_config_t, maximum_attempt_count, 8);
MIC_RETRY_OFFSET(mic_retry_state_t, abi_version, 0);
MIC_RETRY_OFFSET(mic_retry_state_t, present, 4);
MIC_RETRY_OFFSET(mic_retry_state_t, may_retry, 8);
MIC_RETRY_OFFSET(mic_retry_state_t, reserved, 12);
MIC_RETRY_OFFSET(mic_retry_state_t, count, 16);
MIC_RETRY_OFFSET(mic_retry_event_t, opcode, 0);
MIC_RETRY_OFFSET(mic_retry_event_t, failure_category, 4);
MIC_RETRY_OFFSET(mic_retry_event_t, bridge_faulted, 8);
MIC_RETRY_OFFSET(mic_retry_event_t, reserved, 12);
MIC_RETRY_OFFSET(mic_retry_result_t, state, 0);
MIC_RETRY_OFFSET(mic_retry_result_t, status, 24);
MIC_RETRY_OFFSET(mic_retry_result_t, decision, 28);
MIC_RETRY_OFFSET(mic_retry_result_t, redrive_action, 32);
MIC_RETRY_OFFSET(mic_retry_result_t, reserved, 36);
#undef MIC_RETRY_LAYOUT
#undef MIC_RETRY_OFFSET

static int mic_retry_state_equal(mic_retry_state_t a, mic_retry_state_t b) {
    return a.abi_version == b.abi_version && a.present == b.present &&
        a.may_retry == b.may_retry && a.reserved == b.reserved && a.count == b.count;
}
static int mic_retry_result_equal(mic_retry_result_t a, mic_retry_result_t b) {
    return mic_retry_state_equal(a.state, b.state) && a.status == b.status &&
        a.decision == b.decision && a.redrive_action == b.redrive_action &&
        a.reserved == b.reserved;
}
static void mic_retry_assert_refused(
    mic_retry_config_t config, mic_retry_state_t before, mic_retry_event_t event
) {
    const mic_retry_result_t expected = {before, 0, 0, 0, 0};
    const mic_retry_result_t actual =
        beluga_core_microphone_forwarding_retry_step(config, before, event);
    assert(mic_retry_result_equal(actual, expected));
    assert(beluga_core_microphone_forwarding_retry_result_is_valid(
        config, before, event, expected) == 0);
    /* A forged accepted-false envelope is not a fallback for raw refusal. */
    mic_retry_result_t forged = expected; forged.status = 1;
    assert(beluga_core_microphone_forwarding_retry_result_is_valid(
        config, before, event, forged) == 0);
}

static void microphone_forwarding_retry_smoke_v1(void) {
    /* ABI=1; opcodes Eligible/Record/RetryFailure/Exhaust=1/2/3/4;
     * redrive Retain/Clear/Request=0/1/2. Expected values are handwritten. */
    typedef struct {
        mic_retry_config_t config;
        mic_retry_state_t before;
        mic_retry_event_t event;
        mic_retry_result_t expected;
    } mic_retry_case_t;
    const mic_retry_case_t cases[] = {
        {{1,0,3},{1,0,0,0,0},{1,0,0,0},{{1,0,0,0,0},1,1,0,0}},
        {{1,0,3},{1,1,1,0,1},{1,0,0,0},{{1,1,1,0,1},1,1,0,0}},
        {{1,0,3},{1,1,1,0,3},{1,0,0,0},{{1,1,1,0,3},1,0,0,0}},
        {{1,0,3},{1,0,0,0,0},{1,0,1,0},{{1,0,0,0,0},1,0,0,0}},
        {{1,0,3},{1,0,0,0,0},{2,0,0,0},{{1,1,0,0,1},1,0,0,0}},
        {{1,0,3},{1,1,1,0,1},{2,0,0,0},{{1,1,0,0,2},1,0,0,0}},
        {{1,0,3},{1,1,1,0,3},{2,0,0,0},{{1,1,0,0,4},1,0,0,0}},
        {{1,0,3},{1,1,0,0,1},{3,3,0,0},{{1,1,1,0,1},1,1,2,0}},
        {{1,0,3},{1,1,1,0,1},{3,4,0,0},{{1,1,1,0,1},1,0,1,0}},
        {{1,0,3},{1,0,0,0,0},{3,3,0,0},{{1,0,0,0,0},1,0,1,0}},
        {{1,0,3},{1,1,1,0,3},{3,3,0,0},{{1,1,1,0,3},1,0,1,0}},
        {{1,0,3},{1,1,1,0,1},{3,3,1,0},{{1,1,1,0,1},1,0,1,0}},
        {{1,0,3},{1,0,0,0,0},{4,0,0,0},{{1,0,0,0,0},1,0,0,0}},
        {{1,0,3},{1,1,1,0,1},{4,0,0,0},{{1,1,0,0,1},1,0,1,0}},
        {{1,0,INT64_MAX},{1,1,1,0,INT64_MAX-1},{2,0,0,0},
            {{1,1,0,0,INT64_MAX},1,0,0,0}},
        {{1,0,INT64_MAX},{1,1,1,0,INT64_MAX},{1,0,0,0},
            {{1,1,1,0,INT64_MAX},1,0,0,0}}
    };
    for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
        const mic_retry_case_t row = cases[i];
        const mic_retry_result_t actual = beluga_core_microphone_forwarding_retry_step(
            row.config, row.before, row.event);
        assert(mic_retry_result_equal(actual, row.expected));
        assert(beluga_core_microphone_forwarding_retry_result_is_valid(
            row.config, row.before, row.event, row.expected) == 1);
        /* Nine distinct result fields are changed independently. Additional
         * status=2 and coherent whole-history replacements are also rejected. */
        for (unsigned field = 0; field < 11; ++field) {
            mic_retry_result_t corrupt = row.expected;
            switch (field) {
                case 0: corrupt.state.abi_version = 2; break;
                case 1: corrupt.state.present ^= 1; break;
                case 2: corrupt.state.may_retry ^= 1; break;
                case 3: corrupt.state.reserved = 1; break;
                case 4: corrupt.state.count = 7; break;
                case 5: corrupt.status = 0; break;
                case 6: corrupt.decision ^= 1; break;
                case 7: corrupt.redrive_action = row.expected.redrive_action == 2 ? 1 : 2; break;
                case 8: corrupt.reserved = 1; break;
                case 9: corrupt.status = 2; break;
                case 10: corrupt.state = row.expected.state.present == 0
                    ? (mic_retry_state_t){1,1,0,0,7}
                    : (mic_retry_state_t){1,0,0,0,0}; break;
            }
            assert(!mic_retry_result_equal(corrupt, row.expected));
            assert(beluga_core_microphone_forwarding_retry_result_is_valid(
                row.config, row.before, row.event, corrupt) == 0);
            assert(mic_retry_result_equal(actual, row.expected));
        }
    }

    const mic_retry_config_t config = {1,0,3};
    const mic_retry_state_t before = {1,1,1,0,1};
    const mic_retry_event_t eligible = {1,0,0,0};
    const mic_retry_config_t bad_configs[] = {
        {0,0,3},{2,0,3},{1,1,3},{1,0,0},{1,0,-1},{1,0,INT64_MIN}
    };
    for (size_t i = 0; i < sizeof(bad_configs)/sizeof(bad_configs[0]); ++i)
        mic_retry_assert_refused(bad_configs[i], before, eligible);
    const mic_retry_state_t bad_states[] = {
        {0,1,1,0,1},{2,1,1,0,1},{1,2,1,0,1},{1,1,2,0,1},{1,1,1,1,1},
        {1,1,1,0,0},{1,1,1,0,-1},{1,1,1,0,INT64_MIN},
        {1,0,0,0,1},{1,0,1,0,0}
    };
    for (size_t i = 0; i < sizeof(bad_states)/sizeof(bad_states[0]); ++i)
        mic_retry_assert_refused(config, bad_states[i], eligible);
    const mic_retry_event_t bad_events[] = {
        {0,0,0,0},{5,0,0,0},{UINT32_MAX,0,0,0},{1,0,0,1},{1,0,2,0},
        {1,1,0,0},{2,3,0,0},{2,0,1,0},{4,3,0,0},{4,0,1,0},
        {3,0,0,0},{3,12,0,0},{3,UINT32_MAX,1,0},{3,3,2,0}
    };
    for (size_t i = 0; i < sizeof(bad_events)/sizeof(bad_events[0]); ++i)
        mic_retry_assert_refused(config, before, bad_events[i]);
    /* Signed overflow must refuse with the exact MAX history, not clamp/wrap. */
    mic_retry_assert_refused((mic_retry_config_t){1,0,INT64_MAX},
        (mic_retry_state_t){1,1,1,0,INT64_MAX}, (mic_retry_event_t){2,0,0,0});
    puts("BelugaCore C microphone retry ABI PASS: literal layouts/results, all-field correlation, refusal and signed overflow");
}

static void update_admission_smoke_v1(void) {
    typedef beluga_core_update_admission_request_t Request;
    typedef beluga_core_update_admission_result_t Result;
    _Static_assert(sizeof(Request) == 8 && _Alignof(Request) == 4, "update request layout");
    _Static_assert(sizeof(Result) == 24 && _Alignof(Result) == 4, "update result layout");
    _Static_assert(offsetof(Request, abi_version) == 0 && offsetof(Request, flags) == 4, "update request offsets");
    _Static_assert(offsetof(Result, abi_version) == 0 && offsetof(Result, status) == 4 &&
        offsetof(Result, permits_update) == 8 && offsetof(Result, is_in_progress) == 12 &&
        offsetof(Result, can_check) == 16 && offsetof(Result, status_kind) == 20, "update result offsets");
    for (uint32_t flags = 0; flags < 512; ++flags) {
        Request request = {1, flags};
        uint32_t permits = (flags & 1) && (flags & 16) && !(flags & 14);
        uint32_t release = !!(flags & 32), busy = !!(flags & 192), failed = !!(flags & 256);
        uint32_t progress = release && (busy || failed);
        Result expected = {1, 0, permits, progress, release && !progress && permits,
            !release ? 0 : failed ? 1 : busy ? 2 : permits ? 3 : 4};
        Result actual = beluga_core_update_admission_decide(request);
        assert(memcmp(&actual, &expected, sizeof(Result)) == 0);
        assert(beluga_core_update_admission_result_is_valid(request, actual) == 1);
        for (uint32_t field = 0; field < 6; ++field) {
            Result corrupt = actual;
            switch (field) {
                case 0: corrupt.abi_version = 2; break;
                case 1: corrupt.status = 1; break;
                case 2: corrupt.permits_update ^= 1; break;
                case 3: corrupt.is_in_progress ^= 1; break;
                case 4: corrupt.can_check ^= 1; break;
                default: corrupt.status_kind = (corrupt.status_kind + 1) % 5;
            }
            assert(beluga_core_update_admission_result_is_valid(request, corrupt) == 0);
        }
    }
    for (uint32_t bit = 9; bit < 32; ++bit) {
        Request invalid = {1, 49 | (UINT32_C(1) << bit)};
        Result denied = beluga_core_update_admission_decide(invalid);
        assert(denied.status == 1 && denied.permits_update == 0 && denied.can_check == 0 &&
            denied.is_in_progress == 1 && denied.status_kind == 1);
        assert(beluga_core_update_admission_result_is_valid(invalid, denied) == 0);
    }
    Request invalid_abi = {2, 49};
    Result denied = beluga_core_update_admission_decide(invalid_abi);
    assert(denied.status == 1 && beluga_core_update_admission_result_is_valid(invalid_abi, denied) == 0);
    puts("BelugaCore C updater admission ABI PASS: exact layouts, 512 parity cases, all-field correlation and refusal");
}

_Static_assert(sizeof(beluga_core_update_sparkle_admission_request_t) == 12, "SDK admission request size");
_Static_assert(_Alignof(beluga_core_update_sparkle_admission_request_t) == 4, "SDK admission request alignment");
_Static_assert(offsetof(beluga_core_update_sparkle_admission_request_t, abi_version) == 0, "SDK ABI offset");
_Static_assert(offsetof(beluga_core_update_sparkle_admission_request_t, phase) == 4, "SDK phase offset");
_Static_assert(offsetof(beluga_core_update_sparkle_admission_request_t, flags) == 8, "SDK flags offset");
_Static_assert(sizeof(beluga_core_update_sparkle_admission_result_t) == 12, "SDK admission result size");
_Static_assert(_Alignof(beluga_core_update_sparkle_admission_result_t) == 4, "SDK admission result alignment");
_Static_assert(offsetof(beluga_core_update_sparkle_admission_result_t, abi_version) == 0, "SDK result ABI offset");
_Static_assert(offsetof(beluga_core_update_sparkle_admission_result_t, status) == 4, "SDK result status offset");
_Static_assert(offsetof(beluga_core_update_sparkle_admission_result_t, action) == 8, "SDK result action offset");

static void update_sparkle_admission_smoke_v1(void) {
    typedef beluga_core_update_sparkle_admission_request_t Request;
    typedef beluga_core_update_sparkle_admission_result_t Result;
    const uint32_t actions[12] = {1, 2, 1, 3, 1, 2, 1, 5, 3, 4, 3, 6};
    for (uint32_t phase = 1; phase <= 2; ++phase) {
        uint32_t count = phase == 1 ? 8 : 4;
        for (uint32_t flags = 0; flags < count; ++flags) {
            Request request = {1, phase, flags};
            Result result = beluga_core_update_sparkle_admission_decide(request);
            assert(result.abi_version == 1 && result.status == 0 &&
                result.action == actions[(phase == 1 ? 0 : 8) + flags]);
            assert(beluga_core_update_sparkle_admission_result_is_valid(request, result) == 1);
            for (uint32_t field = 0; field < 3; ++field) {
                Result corrupt = result;
                if (field == 0) corrupt.abi_version = 2;
                else if (field == 1) corrupt.status = 1;
                else corrupt.action = corrupt.action % 6 + 1;
                assert(beluga_core_update_sparkle_admission_result_is_valid(request, corrupt) == 0);
            }
            for (uint32_t bit = phase == 1 ? 3 : 2; bit < 32; ++bit) {
                Request invalid = {1, phase, flags | (UINT32_C(1) << bit)};
                Result refused = beluga_core_update_sparkle_admission_decide(invalid);
                assert(refused.abi_version == 1 && refused.status == 1 && refused.action == 0);
                assert(beluga_core_update_sparkle_admission_result_is_valid(invalid, refused) == 0);
            }
        }
    }
    const Request invalids[] = {{0,1,7}, {2,2,3}, {1,0,0}, {1,3,0}, {1,UINT32_MAX,0}};
    for (size_t i = 0; i < sizeof(invalids) / sizeof(invalids[0]); ++i) {
        Result refused = beluga_core_update_sparkle_admission_decide(invalids[i]);
        assert(refused.abi_version == 1 && refused.status == 1 && refused.action == 0);
        assert(beluga_core_update_sparkle_admission_result_is_valid(invalids[i], refused) == 0);
    }
    puts("BelugaCore C SDK admission ABI PASS: exact layouts, twelve phases, whole correlation and refusal");
}

_Static_assert(sizeof(beluga_core_update_unarmed_completion_request_t) == 12, "unarmed request size");
_Static_assert(_Alignof(beluga_core_update_unarmed_completion_request_t) == 4, "unarmed request alignment");
_Static_assert(offsetof(beluga_core_update_unarmed_completion_request_t, abi_version) == 0, "unarmed ABI offset");
_Static_assert(offsetof(beluga_core_update_unarmed_completion_request_t, flags) == 4, "unarmed flags offset");
_Static_assert(offsetof(beluga_core_update_unarmed_completion_request_t, failure_kind) == 8, "unarmed failure-kind offset");
_Static_assert(sizeof(beluga_core_update_unarmed_completion_result_t) == 12, "unarmed result size");
_Static_assert(_Alignof(beluga_core_update_unarmed_completion_result_t) == 4, "unarmed result alignment");
_Static_assert(offsetof(beluga_core_update_unarmed_completion_result_t, abi_version) == 0, "unarmed result ABI offset");
_Static_assert(offsetof(beluga_core_update_unarmed_completion_result_t, status) == 4, "unarmed result status offset");
_Static_assert(offsetof(beluga_core_update_unarmed_completion_result_t, reason) == 8, "unarmed result reason offset");
static void update_unarmed_completion_smoke_v1(void) {
    typedef beluga_core_update_unarmed_completion_request_t Request;
    typedef beluga_core_update_unarmed_completion_result_t Result;
    const Request goldens[] = {{1,0,0},{1,3,0},{1,960,1},{1,960,2},{1,544,0},{1,491536,0}};
    for (uint32_t reason = 0; reason < 6; reason++) {
        const Request request = goldens[reason];
        Result actual = beluga_core_update_unarmed_completion_decide(request);
        assert(actual.abi_version == 1 && actual.status == 0 && actual.reason == reason);
        assert(beluga_core_update_unarmed_completion_result_is_valid(request, actual) == 1);
        for (uint32_t field = 0; field < 3; field++) {
            Result corrupt = actual;
            if (field == 0) corrupt.abi_version = 2;
            else if (field == 1) corrupt.status = 1;
            else corrupt.reason = (corrupt.reason + 1) % 6;
            assert(beluga_core_update_unarmed_completion_result_is_valid(request, corrupt) == 0);
        }
        for (uint32_t other = 0; other < 6; other++) {
            const Result copied = beluga_core_update_unarmed_completion_decide(goldens[other]);
            assert(beluga_core_update_unarmed_completion_result_is_valid(request, copied) == (other == reason));
        }
        for (uint32_t bit = 19; bit < 32; bit++) {
            Request invalid = request; invalid.flags |= UINT32_C(1) << bit;
            const Result refusal = beluga_core_update_unarmed_completion_decide(invalid);
            assert(refusal.abi_version == 1 && refusal.status == 1 && refusal.reason == 0);
            assert(beluga_core_update_unarmed_completion_result_is_valid(invalid, refusal) == 0);
        }
    }
    const Request invalids[] = {{0,3,0},{2,3,0},{1,960,3},{1,960,UINT32_MAX}};
    for (size_t i = 0; i < sizeof(invalids)/sizeof(invalids[0]); i++) {
        const Result refusal = beluga_core_update_unarmed_completion_decide(invalids[i]);
        assert(refusal.abi_version == 1 && refusal.status == 1 && refusal.reason == 0);
        assert(beluga_core_update_unarmed_completion_result_is_valid(invalids[i], refusal) == 0);
    }
    puts("BelugaCore C unarmed completion ABI PASS: copied layouts, six reasons, whole correlation and refusal");
}

_Static_assert(sizeof(beluga_core_update_abort_request_t) == 8, "abort request size");
_Static_assert(_Alignof(beluga_core_update_abort_request_t) == 4, "abort request alignment");
_Static_assert(offsetof(beluga_core_update_abort_request_t, abi_version) == 0, "abort ABI offset");
_Static_assert(offsetof(beluga_core_update_abort_request_t, flags) == 4, "abort flags offset");
_Static_assert(sizeof(beluga_core_update_abort_result_t) == 12, "abort result size");
_Static_assert(_Alignof(beluga_core_update_abort_result_t) == 4, "abort result alignment");
_Static_assert(offsetof(beluga_core_update_abort_result_t, abi_version) == 0, "abort result ABI offset");
_Static_assert(offsetof(beluga_core_update_abort_result_t, status) == 4, "abort result status offset");
_Static_assert(offsetof(beluga_core_update_abort_result_t, action) == 8, "abort result action offset");
static uint32_t update_abort_literal_action_v1(uint32_t flags) {
    if ((flags & 1) && (flags & 2) && (flags & 4) && !(flags & 8) && (flags & 16)) return 1;
    return flags & 32 ? 2 : 3;
}
static void update_abort_smoke_v1(void) {
    typedef beluga_core_update_abort_request_t Request;
    typedef beluga_core_update_abort_result_t Result;
    const uint32_t values[] = {0, 1, 2, 3, 4, UINT32_MAX};
    for (uint32_t flags = 0; flags < 64; ++flags) {
        const Request request = {1, flags};
        const uint32_t expected = update_abort_literal_action_v1(flags);
        const Result actual = beluga_core_update_abort_decide(request);
        assert(actual.abi_version == 1 && actual.status == 0 && actual.action == expected);
        assert(beluga_core_update_abort_result_is_valid(request, actual) == 1);
        for (size_t i = 0; i < sizeof(values)/sizeof(values[0]); ++i) {
            for (uint32_t field = 0; field < 3; ++field) {
                Result changed = actual;
                if (field == 0) changed.abi_version = values[i];
                else if (field == 1) changed.status = values[i];
                else changed.action = values[i];
                const uint32_t same = changed.abi_version == 1 && changed.status == 0 && changed.action == expected;
                assert(beluga_core_update_abort_result_is_valid(request, changed) == same);
            }
        }
        for (uint32_t other = 0; other < 64; ++other) {
            const Result copied = beluga_core_update_abort_decide((Request){1, other});
            assert(copied.abi_version == 1 && copied.status == 0 && copied.action == update_abort_literal_action_v1(other));
            assert(beluga_core_update_abort_result_is_valid(request, copied) == (copied.action == expected));
        }
        for (uint32_t bit = 6; bit < 32; ++bit) {
            const Request invalid = {1, flags | (UINT32_C(1) << bit)};
            const Result denied = beluga_core_update_abort_decide(invalid);
            assert(denied.abi_version == 1 && denied.status == 1 && denied.action == 0);
            assert(beluga_core_update_abort_result_is_valid(invalid, denied) == 0);
            for (uint32_t action = 1; action <= 3; ++action)
                assert(beluga_core_update_abort_result_is_valid(invalid, (Result){1, 0, action}) == 0);
        }
        const uint32_t invalid_abis[] = {0, 2, UINT32_MAX};
        for (size_t i = 0; i < sizeof(invalid_abis)/sizeof(invalid_abis[0]); ++i) {
            const Request invalid = {invalid_abis[i], flags};
            const Result denied = beluga_core_update_abort_decide(invalid);
            assert(denied.abi_version == 1 && denied.status == 1 && denied.action == 0);
            assert(beluga_core_update_abort_result_is_valid(invalid, denied) == 0);
            for (uint32_t action = 1; action <= 3; ++action)
                assert(beluga_core_update_abort_result_is_valid(invalid, (Result){1, 0, action}) == 0);
        }
    }
    puts("BelugaCore C abort classifier ABI PASS: copied layouts, 64 carriers, whole correlation and refusal");
}


_Static_assert(sizeof(beluga_core_handoff_source_prepare_facts_t) == 56, "prepare size");
_Static_assert(_Alignof(beluga_core_handoff_source_prepare_facts_t) == 8, "prepare alignment");
_Static_assert(offsetof(beluga_core_handoff_source_prepare_facts_t, abi_version) == 0, "prepare ABI");
_Static_assert(offsetof(beluga_core_handoff_source_prepare_facts_t, reserved) == 4, "prepare reserved");
_Static_assert(offsetof(beluga_core_handoff_source_prepare_facts_t, flags) == 8, "prepare flags");
_Static_assert(offsetof(beluga_core_handoff_source_prepare_facts_t, position) == 16, "prepare position");
_Static_assert(offsetof(beluga_core_handoff_source_prepare_facts_t, duration) == 24, "prepare duration");
_Static_assert(offsetof(beluga_core_handoff_source_prepare_facts_t, rate) == 32, "prepare rate");
_Static_assert(offsetof(beluga_core_handoff_source_prepare_facts_t, observed_at_page_ms) == 40, "prepare page");
_Static_assert(offsetof(beluga_core_handoff_source_prepare_facts_t, phone_position) == 48, "prepare phone");
_Static_assert(sizeof(beluga_core_handoff_source_match_facts_t) == 88, "match size");
_Static_assert(_Alignof(beluga_core_handoff_source_match_facts_t) == 8, "match alignment");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, abi_version) == 0, "match ABI");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, reserved) == 4, "match reserved");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, flags) == 8, "match flags");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, anchor_position) == 16, "match anchor position");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, anchor_duration) == 24, "match anchor duration");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, anchor_rate) == 32, "match anchor rate");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, anchor_observed_at_page_ms) == 40, "match anchor page");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, phone_position) == 48, "match phone");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, current_position) == 56, "match position");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, current_duration) == 64, "match duration");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, current_rate) == 72, "match rate");
_Static_assert(offsetof(beluga_core_handoff_source_match_facts_t, current_observed_at_page_ms) == 80, "match page");
_Static_assert(sizeof(beluga_core_handoff_source_result_t) == 16, "result size");
_Static_assert(_Alignof(beluga_core_handoff_source_result_t) == 4, "result alignment");
_Static_assert(offsetof(beluga_core_handoff_source_result_t, abi_version) == 0, "result ABI");
_Static_assert(offsetof(beluga_core_handoff_source_result_t, status) == 4, "result status");
_Static_assert(offsetof(beluga_core_handoff_source_result_t, allowed) == 8, "result allowed");
_Static_assert(offsetof(beluga_core_handoff_source_result_t, reserved) == 12, "result reserved");

static uint64_t handoff_source_bits(double value) {
    uint64_t result;
    _Static_assert(sizeof(result) == sizeof(value), "copied Double word");
    memcpy(&result, &value, sizeof(result));
    return result;
}

static void handoff_source_expect(beluga_core_handoff_source_result_t result, uint32_t status, uint32_t allowed) {
    assert(result.abi_version == 1 && result.status == status);
    assert(result.allowed == allowed && result.reserved == 0);
}

static void handoff_source_smoke_v1(void) {
    beluga_core_handoff_source_prepare_facts_t p = {
        .abi_version = 1, .flags = 127,
        .position = handoff_source_bits(15), .duration = handoff_source_bits(120), .rate = handoff_source_bits(1),
        .observed_at_page_ms = handoff_source_bits(50000), .phone_position = handoff_source_bits(15),
    };
    beluga_core_handoff_source_result_t result = beluga_core_handoff_source_prepare(p);
    handoff_source_expect(result, 1, 1);
    assert(beluga_core_handoff_source_prepare_result_is_valid(p, result) == 1);
    result.allowed = 0;
    assert(beluga_core_handoff_source_prepare_result_is_valid(p, result) == 0);
    p.flags = 63;
    handoff_source_expect(beluga_core_handoff_source_prepare(p), 1, 0);
    p.flags = 255;
    handoff_source_expect(beluga_core_handoff_source_prepare(p), 0, 0);
    p.flags = 127; p.position = handoff_source_bits(-0.0); p.phone_position = handoff_source_bits(-0.0);
    handoff_source_expect(beluga_core_handoff_source_prepare(p), 1, 1);
    assert(p.position == UINT64_C(0x8000000000000000));

    beluga_core_handoff_source_match_facts_t m = {
        .abi_version = 1, .flags = 127,
        .anchor_position = handoff_source_bits(15), .anchor_duration = handoff_source_bits(120), .anchor_rate = handoff_source_bits(1),
        .anchor_observed_at_page_ms = handoff_source_bits(50000), .phone_position = handoff_source_bits(15),
        .current_position = handoff_source_bits(15), .current_duration = handoff_source_bits(120), .current_rate = handoff_source_bits(1),
        .current_observed_at_page_ms = handoff_source_bits(50000),
    };
    result = beluga_core_handoff_source_matches(m); handoff_source_expect(result, 1, 1);
    assert(beluga_core_handoff_source_matches_result_is_valid(m, result) == 1);
    m.current_position = handoff_source_bits(16); handoff_source_expect(beluga_core_handoff_source_matches(m), 1, 1);
    m.current_position = handoff_source_bits(16.001); handoff_source_expect(beluga_core_handoff_source_matches(m), 1, 0);
    m.current_position = handoff_source_bits(15); m.phone_position = handoff_source_bits(13);
    handoff_source_expect(beluga_core_handoff_source_matches(m), 1, 1);
    m.phone_position = handoff_source_bits(12.999); handoff_source_expect(beluga_core_handoff_source_matches(m), 1, 0);
    m.current_position = handoff_source_bits(45); m.phone_position = handoff_source_bits(45); m.current_observed_at_page_ms = handoff_source_bits(80000);
    handoff_source_expect(beluga_core_handoff_source_matches(m), 1, 0);
    puts("BelugaCore C handoff source ABI PASS: exact layouts, timeline/phone boundaries, whole correlation and refusal");
}

_Static_assert(sizeof(beluga_core_microphone_input_lease_facts_t) == 32, "input lease facts size");
_Static_assert(_Alignof(beluga_core_microphone_input_lease_facts_t) == 8, "input lease facts alignment");
_Static_assert(offsetof(beluga_core_microphone_input_lease_facts_t, abi_version) == 0, "input lease ABI offset");
_Static_assert(offsetof(beluga_core_microphone_input_lease_facts_t, opcode) == 4, "input lease opcode offset");
_Static_assert(offsetof(beluga_core_microphone_input_lease_facts_t, disposition) == 8, "input lease disposition offset");
_Static_assert(offsetof(beluga_core_microphone_input_lease_facts_t, reserved) == 12, "input lease reserved offset");
_Static_assert(offsetof(beluga_core_microphone_input_lease_facts_t, attempt_count) == 16, "input lease count offset");
_Static_assert(offsetof(beluga_core_microphone_input_lease_facts_t, maximum_attempt_count) == 24, "input lease maximum offset");
_Static_assert(sizeof(beluga_core_microphone_input_lease_result_t) == 20, "input lease result size");
_Static_assert(_Alignof(beluga_core_microphone_input_lease_result_t) == 4, "input lease result alignment");
_Static_assert(offsetof(beluga_core_microphone_input_lease_result_t, abi_version) == 0, "input lease result ABI offset");
_Static_assert(offsetof(beluga_core_microphone_input_lease_result_t, status) == 4, "input lease result status offset");
_Static_assert(offsetof(beluga_core_microphone_input_lease_result_t, opcode) == 8, "input lease result opcode offset");
_Static_assert(offsetof(beluga_core_microphone_input_lease_result_t, action) == 12, "input lease result action offset");
_Static_assert(offsetof(beluga_core_microphone_input_lease_result_t, reserved) == 16, "input lease result reserved offset");

static void microphone_input_lease_smoke_v1(void) {
    typedef beluga_core_microphone_input_lease_facts_t Facts;
    typedef beluga_core_microphone_input_lease_result_t Result;
    const struct { Facts facts; uint32_t action; } rows[] = {
        {{1, 1, 0, 0, 0, 3}, 1}, {{1, 1, 0, 0, 3, 3}, 2},
        {{1, 1, 0, 0, INT64_MAX - 1, INT64_MAX}, 1},
        {{1, 1, 0, 0, INT64_MAX, INT64_MAX}, 2},
        {{1, 2, 1, 0, 0, 0}, 3}, {{1, 2, 2, 0, 0, 0}, 4},
        {{1, 2, 3, 0, 0, 0}, 5}, {{1, 3, 2, 0, 1, 3}, 6},
        {{1, 3, 2, 0, 3, 3}, 7}, {{1, 3, 3, 0, 1, 3}, 7},
        {{1, 4, 0, 0, 0, 0}, 8}, {{1, 4, 1, 0, 0, 0}, 9},
        {{1, 4, 2, 0, 0, 0}, 10}, {{1, 4, 3, 0, 0, 0}, 9}
    };
    for (size_t i = 0; i < sizeof(rows) / sizeof(rows[0]); i++) {
        const Facts input = rows[i].facts;
        const Result actual = beluga_core_microphone_input_lease_decide(input);
        assert(actual.abi_version == 1 && actual.status == 1 && actual.opcode == input.opcode &&
            actual.action == rows[i].action && actual.reserved == 0);
        assert(beluga_core_microphone_input_lease_result_is_valid(input, actual) == 1);
        const uint32_t values[] = {0, 1, 2, 3, 4, 10, 11, UINT32_MAX};
        for (size_t j = 0; j < sizeof(values) / sizeof(values[0]); j++) {
            for (uint32_t field = 0; field < 5; field++) {
                Result changed = actual;
                if (field == 0) changed.abi_version = values[j];
                else if (field == 1) changed.status = values[j];
                else if (field == 2) changed.opcode = values[j];
                else if (field == 3) changed.action = values[j];
                else changed.reserved = values[j];
                const uint32_t same = changed.abi_version == 1 && changed.status == 1 &&
                    changed.opcode == input.opcode && changed.action == rows[i].action && changed.reserved == 0;
                assert(beluga_core_microphone_input_lease_result_is_valid(input, changed) == same);
            }
        }
        for (uint32_t action = 1; action <= 10; action++) {
            Result coherent = actual; coherent.action = action;
            assert(beluga_core_microphone_input_lease_result_is_valid(input, coherent) == (action == rows[i].action));
        }
    }
    const Facts invalid[] = {
        {0, 1, 0, 0, 0, 3}, {2, 1, 0, 0, 0, 3}, {1, 1, 0, 1, 0, 3},
        {1, 0, 0, 0, 0, 3}, {1, 5, 0, 0, 0, 3}, {1, UINT32_MAX, 0, 0, 0, 3},
        {1, 1, 1, 0, 0, 3}, {1, 1, 0, 0, -1, 3}, {1, 1, 0, 0, 0, 0},
        {1, 2, 0, 0, 0, 0}, {1, 2, 4, 0, 0, 0}, {1, 2, 1, 0, 1, 0},
        {1, 2, 1, 0, 0, 1}, {1, 3, 4, 0, 1, 3}, {1, 3, 2, 0, 0, 3},
        {1, 3, 2, 0, 1, 0}, {1, 4, 4, 0, 0, 0}, {1, 4, 0, 0, 1, 0},
        {1, 4, 0, 0, 0, 1}
    };
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        const Result denied = beluga_core_microphone_input_lease_decide(invalid[i]);
        assert(denied.abi_version == 1 && denied.status == 0 && denied.opcode == 0 &&
            denied.action == 0 && denied.reserved == 0);
        assert(beluga_core_microphone_input_lease_result_is_valid(invalid[i], denied) == 0);
        assert(beluga_core_microphone_input_lease_result_is_valid(invalid[i], (Result){1, 1, 1, 1, 0}) == 0);
    }
    puts("BelugaCore C input lease ABI PASS: four copied operations, literal layouts, full-width counts and whole refusal");
}

_Static_assert(sizeof(beluga_core_microphone_output_format_facts_t) == 80, "output format facts size");
_Static_assert(_Alignof(beluga_core_microphone_output_format_facts_t) == 8, "output format facts alignment");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, abi_version) == 0, "output format facts abi_version offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, wire_reserved) == 4, "output format facts wire_reserved offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, stream_description_status) == 8, "output format facts stream_description_status offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, device_sample_rate_status) == 12, "output format facts device_sample_rate_status offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, device_channel_count_status) == 16, "output format facts device_channel_count_status offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, converter_error_read_status) == 20, "output format facts converter_error_read_status offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, stream_sample_rate_bits) == 24, "output format facts stream_sample_rate_bits offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, stream_format_id) == 32, "output format facts stream_format_id offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, stream_format_flags) == 36, "output format facts stream_format_flags offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, stream_bytes_per_packet) == 40, "output format facts stream_bytes_per_packet offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, stream_frames_per_packet) == 44, "output format facts stream_frames_per_packet offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, stream_bytes_per_frame) == 48, "output format facts stream_bytes_per_frame offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, stream_channels_per_frame) == 52, "output format facts stream_channels_per_frame offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, stream_bits_per_channel) == 56, "output format facts stream_bits_per_channel offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, stream_reserved) == 60, "output format facts stream_reserved offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, device_sample_rate_bits) == 64, "output format facts device_sample_rate_bits offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, device_channel_count) == 72, "output format facts device_channel_count offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_facts_t, converter_error) == 76, "output format facts converter_error offset");
_Static_assert(sizeof(beluga_core_microphone_output_format_observation_t) == 56, "output format observation size");
_Static_assert(_Alignof(beluga_core_microphone_output_format_observation_t) == 8, "output format observation alignment");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, sample_rate_bits) == 0, "output format observation sample_rate_bits offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, format_id) == 8, "output format observation format_id offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, format_flags) == 12, "output format observation format_flags offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, bytes_per_packet) == 16, "output format observation bytes_per_packet offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, frames_per_packet) == 20, "output format observation frames_per_packet offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, bytes_per_frame) == 24, "output format observation bytes_per_frame offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, channels_per_frame) == 28, "output format observation channels_per_frame offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, bits_per_channel) == 32, "output format observation bits_per_channel offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, stream_reserved) == 36, "output format observation stream_reserved offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, device_sample_rate_bits) == 40, "output format observation device_sample_rate_bits offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, device_channel_count) == 48, "output format observation device_channel_count offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_observation_t, converter_error) == 52, "output format observation converter_error offset");
_Static_assert(sizeof(beluga_core_microphone_output_format_result_t) == 96, "output format result size");
_Static_assert(_Alignof(beluga_core_microphone_output_format_result_t) == 8, "output format result alignment");
_Static_assert(offsetof(beluga_core_microphone_output_format_result_t, abi_version) == 0, "output format result abi_version offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_result_t, status) == 4, "output format result status offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_result_t, accepted) == 8, "output format result accepted offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_result_t, reason) == 12, "output format result reason offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_result_t, actual_core_audio_status) == 16, "output format result actual_core_audio_status offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_result_t, actual_u32) == 20, "output format result actual_u32 offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_result_t, actual_rate_bits) == 24, "output format result actual_rate_bits offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_result_t, observation) == 32, "output format result observation offset");
_Static_assert(offsetof(beluga_core_microphone_output_format_result_t, wire_reserved) == 88, "output format result wire_reserved offset");

static beluga_core_microphone_output_format_facts_t microphone_output_format_valid_facts(void) {
    return (beluga_core_microphone_output_format_facts_t){
        .abi_version = 1, .stream_sample_rate_bits = UINT64_C(0x40e7700000000000),
        .stream_format_id = UINT32_C(0x6c70636d), .stream_format_flags = 12,
        .stream_bytes_per_packet = 2, .stream_frames_per_packet = 1,
        .stream_bytes_per_frame = 2, .stream_channels_per_frame = 1,
        .stream_bits_per_channel = 16, .device_sample_rate_bits = UINT64_C(0x40e7700000000000),
        .device_channel_count = 1,
    };
}

static void microphone_output_format_fail_guard(beluga_core_microphone_output_format_facts_t *facts, uint32_t reason) {
    switch (reason) {
        case 1: facts->stream_description_status = INT32_MIN + 1; break;
        case 2: facts->device_sample_rate_status = INT32_MIN + 2; break;
        case 3: facts->device_channel_count_status = INT32_MIN + 3; break;
        case 4: facts->converter_error_read_status = INT32_MIN + 4; break;
        case 5: facts->stream_sample_rate_bits = UINT64_C(0x7ff8000000000042); break;
        case 6: facts->stream_format_id = UINT32_MAX; break;
        case 7: facts->stream_format_flags = UINT32_MAX; break;
        case 8: facts->stream_bytes_per_packet = UINT32_MAX; break;
        case 9: facts->stream_frames_per_packet = UINT32_MAX; break;
        case 10: facts->stream_bytes_per_frame = UINT32_MAX; break;
        case 11: facts->stream_channels_per_frame = UINT32_MAX; break;
        case 12: facts->stream_bits_per_channel = UINT32_MAX; break;
        case 13: facts->stream_reserved = UINT32_MAX; break;
        case 14: facts->device_sample_rate_bits = UINT64_C(0xfff800000000005a); break;
        case 15: facts->device_channel_count = UINT32_MAX; break;
        case 16: facts->converter_error = UINT32_MAX; break;
        default: assert(0 && "unknown output format reason");
    }
}

static void microphone_output_format_expect(beluga_core_microphone_output_format_result_t actual,
    beluga_core_microphone_output_format_result_t expected) {
    assert(actual.abi_version == expected.abi_version);
    assert(actual.status == expected.status);
    assert(actual.accepted == expected.accepted);
    assert(actual.reason == expected.reason);
    assert(actual.actual_core_audio_status == expected.actual_core_audio_status);
    assert(actual.actual_u32 == expected.actual_u32);
    assert(actual.actual_rate_bits == expected.actual_rate_bits);
    assert(actual.observation.sample_rate_bits == expected.observation.sample_rate_bits);
    assert(actual.observation.format_id == expected.observation.format_id);
    assert(actual.observation.format_flags == expected.observation.format_flags);
    assert(actual.observation.bytes_per_packet == expected.observation.bytes_per_packet);
    assert(actual.observation.frames_per_packet == expected.observation.frames_per_packet);
    assert(actual.observation.bytes_per_frame == expected.observation.bytes_per_frame);
    assert(actual.observation.channels_per_frame == expected.observation.channels_per_frame);
    assert(actual.observation.bits_per_channel == expected.observation.bits_per_channel);
    assert(actual.observation.stream_reserved == expected.observation.stream_reserved);
    assert(actual.observation.device_sample_rate_bits == expected.observation.device_sample_rate_bits);
    assert(actual.observation.device_channel_count == expected.observation.device_channel_count);
    assert(actual.observation.converter_error == expected.observation.converter_error);
    assert(actual.wire_reserved == expected.wire_reserved);
}

static void microphone_output_format_corruption_refusal(beluga_core_microphone_output_format_facts_t facts,
    beluga_core_microphone_output_format_result_t actual) {
    assert(beluga_core_microphone_output_format_result_is_valid(facts, actual) == 1);
    for (uint32_t field = 0; field < 20; ++field) {
        beluga_core_microphone_output_format_result_t changed = actual;
        switch (field) {
            case 0: changed.abi_version ^= 1; break;
            case 1: changed.status ^= 1; break;
            case 2: changed.accepted ^= 1; break;
            case 3: changed.reason ^= 1; break;
            case 4: changed.actual_core_audio_status ^= 1; break;
            case 5: changed.actual_u32 ^= 1; break;
            case 6: changed.actual_rate_bits ^= 1; break;
            case 7: changed.observation.sample_rate_bits ^= 1; break;
            case 8: changed.observation.format_id ^= 1; break;
            case 9: changed.observation.format_flags ^= 1; break;
            case 10: changed.observation.bytes_per_packet ^= 1; break;
            case 11: changed.observation.frames_per_packet ^= 1; break;
            case 12: changed.observation.bytes_per_frame ^= 1; break;
            case 13: changed.observation.channels_per_frame ^= 1; break;
            case 14: changed.observation.bits_per_channel ^= 1; break;
            case 15: changed.observation.stream_reserved ^= 1; break;
            case 16: changed.observation.device_sample_rate_bits ^= 1; break;
            case 17: changed.observation.device_channel_count ^= 1; break;
            case 18: changed.observation.converter_error ^= 1; break;
            case 19: changed.wire_reserved ^= 1; break;
            default: assert(0 && "unknown output format result field");
        }
        assert(beluga_core_microphone_output_format_result_is_valid(facts, changed) == 0);
    }
}

static void microphone_output_format_smoke_v1(void) {
    typedef beluga_core_microphone_output_format_facts_t Facts;
    typedef beluga_core_microphone_output_format_result_t Result;
    const Facts valid = microphone_output_format_valid_facts();
    const Result expected_success = {
        .abi_version = 1, .status = 1, .accepted = 1,
        .observation = {
            .sample_rate_bits = UINT64_C(0x40e7700000000000), .format_id = UINT32_C(0x6c70636d),
            .format_flags = 12, .bytes_per_packet = 2, .frames_per_packet = 1,
            .bytes_per_frame = 2, .channels_per_frame = 1, .bits_per_channel = 16,
            .device_sample_rate_bits = UINT64_C(0x40e7700000000000), .device_channel_count = 1,
        },
    };
    const Result success = beluga_core_microphone_output_format_decide(valid);
    microphone_output_format_expect(success, expected_success);
    microphone_output_format_corruption_refusal(valid, success);

    for (uint32_t reason = 1; reason <= 16; ++reason) {
        Facts facts = valid;
        microphone_output_format_fail_guard(&facts, reason);
        Result expected = {.abi_version = 1, .status = 1, .reason = reason};
        if (reason <= 4) expected.actual_core_audio_status = INT32_MIN + (int32_t)reason;
        else if (reason == 5) expected.actual_rate_bits = UINT64_C(0x7ff8000000000042);
        else if (reason == 14) expected.actual_rate_bits = UINT64_C(0xfff800000000005a);
        else expected.actual_u32 = UINT32_MAX;
        const Result actual = beluga_core_microphone_output_format_decide(facts);
        microphone_output_format_expect(actual, expected);
        microphone_output_format_corruption_refusal(facts, actual);
        assert(beluga_core_microphone_output_format_result_is_valid(facts, success) == 0);
        assert(beluga_core_microphone_output_format_result_is_valid(valid, actual) == 0);
        for (uint32_t later = reason + 1; later <= 16; ++later) {
            microphone_output_format_fail_guard(&facts, later);
            const Result ordered = beluga_core_microphone_output_format_decide(facts);
            microphone_output_format_expect(ordered, expected);
            assert(beluga_core_microphone_output_format_result_is_valid(facts, ordered) == 1);
        }
    }

    // Raw words are never normalized, including signed/signaling NaN payloads.
    const uint64_t rejected_rates[] = {
        0, UINT64_C(0x8000000000000000), UINT64_C(0x7ff0000000000000),
        UINT64_C(0xfff0000000000000), UINT64_C(0x7ff8000000000042),
        UINT64_C(0xfff800000000005a), UINT64_C(0x7ff0000000000001),
        1, UINT64_C(0x8000000000000001), UINT64_C(0x40e76fffffffffff),
        UINT64_C(0x40e7700000000001),
    };
    for (size_t i = 0; i < sizeof(rejected_rates) / sizeof(rejected_rates[0]); ++i) {
        for (uint32_t device = 0; device <= 1; ++device) {
            Facts facts = valid;
            if (device) facts.device_sample_rate_bits = rejected_rates[i];
            else facts.stream_sample_rate_bits = rejected_rates[i];
            const Result expected = {.abi_version = 1, .status = 1,
                .reason = device ? 14 : 5, .actual_rate_bits = rejected_rates[i]};
            const Result actual = beluga_core_microphone_output_format_decide(facts);
            microphone_output_format_expect(actual, expected);
            microphone_output_format_corruption_refusal(facts, actual);
        }
    }

    const uint32_t invalid_words[] = {0, 2, UINT32_MAX};
    const Result expected_invalid = {.abi_version = 1};
    for (size_t i = 0; i < sizeof(invalid_words) / sizeof(invalid_words[0]); ++i) {
        Facts invalid = valid; invalid.abi_version = invalid_words[i];
        const Result denied = beluga_core_microphone_output_format_decide(invalid);
        microphone_output_format_expect(denied, expected_invalid);
        assert(beluga_core_microphone_output_format_result_is_valid(invalid, denied) == 0);
        assert(beluga_core_microphone_output_format_result_is_valid(invalid, success) == 0);
    }
    const uint32_t invalid_reserved[] = {1, UINT32_MAX};
    for (size_t i = 0; i < sizeof(invalid_reserved) / sizeof(invalid_reserved[0]); ++i) {
        Facts invalid = valid; invalid.wire_reserved = invalid_reserved[i];
        const Result denied = beluga_core_microphone_output_format_decide(invalid);
        microphone_output_format_expect(denied, expected_invalid);
        assert(beluga_core_microphone_output_format_result_is_valid(invalid, denied) == 0);
        assert(beluga_core_microphone_output_format_result_is_valid(invalid, success) == 0);
    }
    puts("BelugaCore C output format ABI PASS: literal layouts, sixteen ordered guards, exact observations and whole refusal");
}

int main(void) {
    assert(beluga_core_abi_version() == 1);
    for (uint32_t f = 0; f < 4096; ++f) {
        beluga_core_handoff_menu_policy_t p = beluga_core_handoff_menu_policy(1, f);
        assert(p.abi_version == 1);
        assert(p.visible == (f & 1));
        assert(p.reason == expected_reason(f));
        assert(p.enabled == (p.reason == 0));
        p = beluga_core_handoff_menu_policy(2, f);
        assert(p.abi_version == 1 && p.reason == 8 && p.enabled == 0 && p.visible == (f & 1));
    }
    puts("BelugaCore C ABI PASS: 4096 flags and unknown ABI");
    beluga_core_host_lifecycle_state_t s = beluga_core_host_lifecycle_initial();
    assert(s.abi_version == 1 && s.run_state == 0 && s.active_token == 0 && s.media_token == 0);
    const beluga_core_host_lifecycle_event_t events[] = {
        {0, 1, 0, 0}, {2, 0, 1, 64}, {3, 0, 1, 999}, {4, 0, 1, 999}, {2, 0, 2, 64}
    };
    for (unsigned i = 0; i < sizeof(events) / sizeof(events[0]); ++i) {
        beluga_core_host_lifecycle_result_t r = beluga_core_host_lifecycle_step(1, s, events[i]);
        assert(r.status == 0); s = r.state;
    }
    assert(s.run_state == 2 && s.active_token == 2 && s.media_token == 1);
    beluga_core_host_lifecycle_result_t r = beluga_core_host_lifecycle_step(1, s,
        (beluga_core_host_lifecycle_event_t){4, 0, 1, 1});
    assert(r.status == 2 && r.state.active_token == 2 && r.state.media_token == 1);
    r = beluga_core_host_lifecycle_step(2, s, (beluga_core_host_lifecycle_event_t){0, 1, 0, 0});
    assert(r.status == 3 && r.state.run_state == 3 && r.state.active_token == 0 && r.state.media_token == 0);
    puts("BelugaCore C lifecycle ABI PASS: reconnect ownership and invalid ABI");
    beluga_core_handoff_transactions_state_t t = beluga_core_handoff_transactions_initial();
    assert(t.abi_version == 1 && t.host_phase == 0 && t.viewer_envelope == 0);
    beluga_core_handoff_transactions_result_t q = beluga_core_handoff_transactions_step(1, t,
        (beluga_core_handoff_transactions_event_t){0, 0, 11, 12, 0, 0, 0});
    assert(q.status == 0 && q.effects == 0 && q.state.host_receipt == 11); t = q.state;
    q = beluga_core_handoff_transactions_step(1, t,
        (beluga_core_handoff_transactions_event_t){0, 0, 21, 22, 0, 0, 0});
    assert(q.status == 1 && q.effects == 0 && q.state.host_receipt == 11);
    q = beluga_core_handoff_transactions_step(1, t,
        (beluga_core_handoff_transactions_event_t){2, 1, 0, 31, 32, 0, 0});
    assert(q.status == 0 && q.state.viewer_offer == 32); t = q.state;
    q = beluga_core_handoff_transactions_step(1, t,
        (beluga_core_handoff_transactions_event_t){1, 0, 11, 99, 0, 1, 0});
    assert(q.status == 1 && q.effects == 0 && q.state.host_phase == 1);
    q = beluga_core_handoff_transactions_step(1, t,
        (beluga_core_handoff_transactions_event_t){1, 0, 11, 12, 0, 1, 0});
    assert(q.status == 0 && q.effects == 3 && q.revoked_receipt == 11 && q.state.host_result == 1); t = q.state;
    q = beluga_core_handoff_transactions_step(1, t,
        (beluga_core_handoff_transactions_event_t){1, 0, 11, 12, 0, 1, 0});
    assert(q.status == 2 && q.effects == 2 && q.revoked_receipt == 0);
    q = beluga_core_handoff_transactions_step(1, t,
        (beluga_core_handoff_transactions_event_t){1, 0, 11, 12, 0, 2, 0});
    assert(q.status == 1 && q.effects == 0 && q.state.host_result == 1);
    q = beluga_core_handoff_transactions_step(1, t,
        (beluga_core_handoff_transactions_event_t){4, 0, 0, 0, 32, 0, 0});
    assert(q.status == 0 && q.effects == 4 && q.completed_offer == 32 && q.completed_result == 3);
    q = beluga_core_handoff_transactions_step(2, t,
        (beluga_core_handoff_transactions_event_t){5, 0, 0, 0, 0, 0, 0});
    assert(q.status == 3 && q.effects == 5 && q.revoked_receipt == 11 && q.completed_offer == 32 && q.completed_result == 3);
    assert(q.state.host_phase == 0 && q.state.viewer_offer == 0 && q.reserved == 0);
    puts("BelugaCore C transaction ABI PASS: exact identity, cached reply, revocation and unknown outcome");
    beluga_core_handoff_offers_state_t offers = offers_pair();
    beluga_core_handoff_offers_result_t offer_result =
        beluga_core_handoff_offers_step(1, offers, offers_event(3, 10.0));
    assert(offer_result.status == 0 && offer_result.effects == 1 && offer_result.retired_sent == 100);
    assert(offer_result.state.sent.token == 0 && offer_result.state.received.token == 100);
    offer_result = beluga_core_handoff_offers_step(1, offers, offers_event(8, 10.0));
    assert(offer_result.effects == 2 && offer_result.retired_received == 100);
    assert(offer_result.state.sent.token == 100 && offer_result.state.received.token == 0);
    beluga_core_handoff_offers_event_t offer_event = offers_event(5, 12.0);
    offer_event.token = 101; offer_event.envelope.sequence = 2;
    offer_result = beluga_core_handoff_offers_step(1, offers, offer_event);
    assert(offer_result.status == 0 && offer_result.decision == 0 && offer_result.effects == 2);
    assert(offer_result.retired_received == 100 && offer_result.state.highest_received == 2);
    assert(offer_result.state.received.token == 0 && offer_result.state.sent.token == 100);
    offers = offer_result.state;
    offer_result = beluga_core_handoff_offers_step(1, offers, offers_event(1, 12.0));
    offers = offer_result.state;
    offer_result = beluga_core_handoff_offers_step(1, offers, offer_event);
    assert(offer_result.status == 0 && offer_result.decision == 0 && offer_result.effects == 0);
    assert(offer_result.state.received.token == 0 && offer_result.state.highest_received == 2);
    offers = offers_pair();
    offer_result = beluga_core_handoff_offers_step(1, offers, offers_event(4, 10.0));
    assert(offer_result.decision == 4 && offer_result.effects == 1 && offer_result.retired_sent == 100);
    assert(offer_result.deadline == double_bits(40.0) && offer_result.state.received.token == 100);
    offer_event = offers_event(7, 10.0); offer_event.phone_observed_at = double_bits(9.25);
    offer_result = beluga_core_handoff_offers_step(1, offers, offer_event);
    assert(offer_result.decision == 5 && offer_result.effects == 2 && offer_result.retired_received == 100);
    assert(offer_result.state.sent.token == 100 && offer_result.state.received.token == 0);
    for (uint32_t opcode = 4; opcode <= 6; opcode += 2) {
        offers = offers_pair();
        offer_result = beluga_core_handoff_offers_step(1, offers, offers_event(opcode, 12.0));
        assert(offer_result.status == 0 && offer_result.decision == 0);
        assert(offer_result.effects == (opcode == 4 ? 1U : 2U));
        offers = offer_result.state;
        offer_result = beluga_core_handoff_offers_step(1, offers, offers_event(opcode, 10.1));
        assert(offer_result.status == 0 && offer_result.decision == 0 && offer_result.effects == 0);
    }
    offers = offers_pair();
    offer_result = beluga_core_handoff_offers_step(1, offers, offers_event(9, 10.0));
    assert(offer_result.effects == 3 && offer_result.state.presence == 0);
    assert(offer_result.state.next_sent == 2 && offer_result.state.highest_received == 1);
    offer_result = beluga_core_handoff_offers_step(1, offers, offers_event(UINT32_MAX, 10.0));
    assert(offer_result.status == 3 && offer_result.effects == 0 && offer_result.decision == 0);
    assert(memcmp(&offer_result.state, &offers, sizeof(offers)) == 0);
    offer_result = beluga_core_handoff_offers_step(2, offers, offers_event(9, 10.0));
    assert(offer_result.status == 3 && offer_result.effects == 3 && offer_result.state.terminal == 1);
    assert(offer_result.state.presence == 0 && offer_result.state.next_sent == UINT64_MAX);
    assert(offer_result.retired_sent == 100 && offer_result.retired_received == 100);
    puts("BelugaCore C offers ABI PASS: independent owners, sequence burn, consuming rejection and exact layouts");
    phone_operation_smoke();
    invitation_acceptance_smoke();
    signaling_replay_smoke();
    pairing_catalog_checkpoint_smoke();
    reconnect_counters_smoke();
    pairing_commit_smoke();
    supported_player_arbitration_smoke();
    availability_retry_smoke();
    smoke_batch_a_policies();
    display_admission_smoke();
    output_dimensions_smoke();
    ice_recovery_smoke();
    screen_liveness_full_custody_smoke();
    puts("BelugaCore C screen liveness ABI PASS: exact copied layouts, full-width values and unchanged refusal");
    update_operation_smoke();
    puts("BelugaCore C update operation ABI PASS: three copied layouts, exact phase plans and unchanged refusal");
    _Static_assert(sizeof(beluga_core_packet_send_queue_state_t) == 48, "queue state size");
    _Static_assert(sizeof(beluga_core_packet_send_queue_event_t) == 64, "queue event size");
    _Static_assert(sizeof(beluga_core_packet_send_queue_result_t) == 96, "queue result size");
    _Static_assert(offsetof(beluga_core_packet_send_queue_state_t, packets) == 24, "queue packets offset");
    _Static_assert(offsetof(beluga_core_packet_send_queue_event_t, low_age_seconds) == 32, "queue clock offset");
    _Static_assert(offsetof(beluga_core_packet_send_queue_result_t, state) == 48, "queue state result offset");
    beluga_core_packet_send_queue_state_t queue_state = {0};
    queue_state.abi_version = 1;
    beluga_core_packet_send_queue_event_t queue_event = {0};
    queue_event.packets_present = 1; queue_event.delay_present = 1;
    queue_event.packets = UINT64_MAX - 1;
    queue_event.delay_bits = double_bits(0.0);
    beluga_core_packet_send_queue_result_t queue_result = beluga_core_packet_send_queue_step(queue_state, queue_event);
    assert(queue_result.status == 1 && queue_result.observation == 0);
    queue_state = queue_result.state;
    queue_event.packets = UINT64_MAX; queue_event.delay_bits = double_bits(0.02);
    queue_result = beluga_core_packet_send_queue_step(queue_state, queue_event);
    assert(queue_result.status == 1 && queue_result.observation == 2 && queue_result.upgrade == 1);
    assert(queue_result.measured_delay_bits == double_bits(0.02) && queue_result.low_action == 2);
    queue_state = queue_result.state;
    queue_event.low_age_seconds = 1; queue_event.low_age_attoseconds = 500000000000000000LL;
    queue_result = beluga_core_packet_send_queue_step(queue_state, queue_event);
    assert(queue_result.observation == 1 && queue_result.upgrade == 1 && queue_result.low_action == 0);
    queue_event.low_age_attoseconds += 1;
    queue_result = beluga_core_packet_send_queue_step(queue_state, queue_event);
    assert(queue_result.observation == 1 && queue_result.upgrade == 0 && queue_result.low_action == 1);
    queue_state.reserved = 1;
    queue_result = beluga_core_packet_send_queue_step(queue_state, queue_event);
    assert(queue_result.status == 0 && queue_result.upgrade == 0 && queue_result.capacity_growth == 0);
    puts("BelugaCore C packet queue ABI PASS: exact layouts, full-width counters and bounded evidence leases");
    _Static_assert(sizeof(beluga_core_rtt_evidence_measurement_t) == 80, "RTT measurement size");
    _Static_assert(sizeof(beluga_core_rtt_evidence_state_t) == 296, "RTT state size");
    _Static_assert(sizeof(beluga_core_rtt_evidence_event_t) == 128, "RTT event size");
    _Static_assert(sizeof(beluga_core_rtt_evidence_result_t) == 336, "RTT result size");
    _Static_assert(offsetof(beluga_core_rtt_evidence_state_t, watermark) == 128, "RTT watermark offset");
    _Static_assert(offsetof(beluga_core_rtt_evidence_event_t, age_seconds) == 112, "RTT age offset");
    _Static_assert(offsetof(beluga_core_rtt_evidence_result_t, state) == 40, "RTT state result offset");
    beluga_core_rtt_evidence_state_t rtt_state = {0};
    rtt_state.abi_version = 1; rtt_state.disposition = 6; rtt_state.permits_initial = 1;
    beluga_core_rtt_evidence_event_t rtt_event = {0};
    rtt_event.observation_kind = 2; rtt_event.fingerprint_length = 64;
    rtt_event.current_present = 1; rtt_event.current_bits = double_bits(0.1);
    for (size_t i = 0; i < 8; i++) rtt_event.measurement.fingerprint_words[i] = 0x6161616161616161ULL;
    rtt_event.measurement.total_bits = double_bits(0.2); rtt_event.measurement.responses = UINT64_MAX;
    beluga_core_rtt_evidence_result_t rtt_result = beluga_core_rtt_evidence_step(rtt_state, rtt_event);
    assert(rtt_result.status == 1 && rtt_result.allows_upgrade == 1 && rtt_result.clock_action == 2);
    assert(rtt_result.state.watermark.responses == UINT64_MAX);
    assert(beluga_core_rtt_evidence_result_is_valid(rtt_state, rtt_event, rtt_result) == 1);
    rtt_state = rtt_result.state; rtt_event.age_seconds = 4;
    rtt_result = beluga_core_rtt_evidence_step(rtt_state, rtt_event);
    assert(rtt_result.allows_upgrade == 1 && rtt_result.clock_action == 0 && rtt_result.state.disposition == 4);
    rtt_event.age_attoseconds = 1;
    rtt_result = beluga_core_rtt_evidence_step(rtt_state, rtt_event);
    assert(rtt_result.allows_upgrade == 0 && rtt_result.state.disposition == 7);
    rtt_result.allows_upgrade = 1;
    assert(beluga_core_rtt_evidence_result_is_valid(rtt_state, rtt_event, rtt_result) == 0);
    puts("BelugaCore C RTT evidence ABI PASS: exact copied layouts, identity and nonrenewable freshness");
    tier_demand_smoke();
    media_command_gate_smoke();
    screen_suspension_smoke();
    phone_catalog_smoke();
    runtime_catalog_smoke();
    adaptation_owner_zero_clock_smoke_v1();
    adaptation_owner_clocked_smoke_v1();
    adaptation_owner_prepare_smoke_v1();
    adaptation_owner_inactive_smoke_v1();
    adaptation_owner_begin_active_smoke_v1();
    adaptation_owner_completion_smoke_v1();
    microphone_forwarding_evidence_smoke_v1();
    microphone_forwarding_result_correlation_smoke_v1();
    microphone_forwarding_retry_smoke_v1();
    update_admission_smoke_v1();
    update_sparkle_admission_smoke_v1();
    update_unarmed_completion_smoke_v1();
    update_abort_smoke_v1();
    handoff_source_smoke_v1();
    microphone_input_lease_smoke_v1();
    microphone_output_format_smoke_v1();
    return 0;
}
