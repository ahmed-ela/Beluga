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
    return 0;
}
