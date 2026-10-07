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
    return 0;
}
