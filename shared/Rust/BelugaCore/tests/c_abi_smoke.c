#include <BelugaCore/beluga_core.h>
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

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
    return 0;
}
