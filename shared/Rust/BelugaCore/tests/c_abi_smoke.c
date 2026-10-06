#include <BelugaCore/beluga_core.h>
#include <assert.h>
#include <stddef.h>
#include <stdio.h>

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
    return 0;
}
