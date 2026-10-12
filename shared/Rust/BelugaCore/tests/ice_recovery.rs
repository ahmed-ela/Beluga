// Prospective tests: actual exported functions, no native decoder or policy fallback.
use beluga_core::ice_recovery::*;
use beluga_core::{beluga_core_ice_recovery_initialize as init, beluga_core_ice_recovery_step as actual};
use std::mem::{align_of, offset_of, size_of};

fn base(maximum_attempts: i64, grace: bool) -> State {
    let out = init(1, Config { maximum_attempts, grace_positive: u32::from(grace), reserved: 0 });
    assert_eq!(out.status, OK); out.candidate_state
}
fn external(opcode: u32) -> Event { Event { abi_version: 1, opcode, ..Event::default() } }
fn internal(opcode: u32, s: State) -> Event {
    Event { abi_version: 1, opcode, workflow_epoch: s.epoch, ..Event::default() }
}
fn call(s: State, e: Event, effect: u32) -> State {
    let out = actual(1, s, e);
    assert_eq!(out.status, OK); assert_eq!(out.abi_version, 1);
    assert_eq!(out.copied_before, s); assert_eq!(out.copied_event, e);
    assert_eq!(out.effect, effect); assert_eq!(out.reserved, 0);
    assert_eq!((valid_state(out.candidate_state), out.abi_version), (true, ABI)); out.candidate_state
}
fn started(max: i64) -> State {
    let s = call(base(max, false), external(REQUEST), LAUNCH);
    let s = call(s, internal(WORKFLOW_ENTERED, s), NEXT_ATTEMPT);
    call(s, internal(BEGIN_ATTEMPT, s), RESTART)
}
fn returned(s: State, success: bool) -> State {
    let mut e = internal(RESTART_RETURNED, s); e.succeeded = u32::from(success);
    call(s, e, if success { PREFLIGHT_TIMEOUT } else { NEXT_BOUNDARY })
}
fn wait(s: State, kind: u32, success: bool) -> State {
    let mut e = internal(ADMIT_WAIT, s); e.wait_kind = kind;
    let s = call(s, e, SLEEP_GRACE + kind - 1);
    let mut e = internal(WAIT_RETURNED, s); e.wait_kind = kind; e.succeeded = u32::from(success);
    call(s, e, if !success { STOP } else if kind == 2 { NEXT_BOUNDARY } else { NEXT_ATTEMPT })
}
fn finish(s: State) -> State { call(s, internal(FINISH, s), RELEASE_TASK) }
fn refusal(abi: u32, s: State, e: Event, status: u32) {
    let out = actual(abi, s, e);
    assert_eq!(out.status, status); assert_eq!(out.candidate_state, s);
    assert_eq!(out.copied_before, s); assert_eq!(out.copied_event, e);
    assert_eq!(out.effect, NO_EFFECT); assert_eq!(out.flags, 0); assert_eq!(out.reserved, 0);
}

#[test] fn ice_layouts_and_offsets_are_exact() {
    assert_eq!((size_of::<Config>(), align_of::<Config>()), (16, 8));
    assert_eq!((size_of::<State>(), align_of::<State>()), (48, 8));
    assert_eq!((size_of::<Event>(), align_of::<Event>()), (32, 8));
    assert_eq!((size_of::<InitResult>(), align_of::<InitResult>()), (72, 8));
    assert_eq!((size_of::<Result>(), align_of::<Result>()), (152, 8));
    assert_eq!([offset_of!(State, abi_version), offset_of!(State, phase), offset_of!(State, epoch),
        offset_of!(State, attempts), offset_of!(State, maximum_attempts), offset_of!(State, exhaustion_delivered),
        offset_of!(State, grace_positive), offset_of!(State, cursor), offset_of!(State, reserved)],
        [0, 4, 8, 16, 24, 32, 36, 40, 44]);
    assert_eq!([offset_of!(Event, abi_version), offset_of!(Event, opcode), offset_of!(Event, workflow_epoch),
        offset_of!(Event, task_cancelled), offset_of!(Event, succeeded), offset_of!(Event, wait_kind),
        offset_of!(Event, reserved)], [0, 4, 8, 16, 20, 24, 28]);
    assert_eq!([offset_of!(Result, abi_version), offset_of!(Result, status), offset_of!(Result, copied_before),
        offset_of!(Result, copied_event), offset_of!(Result, candidate_state), offset_of!(Result, effect),
        offset_of!(Result, flags), offset_of!(Result, reserved)], [0, 4, 8, 56, 88, 136, 140, 144]);
}
#[test] fn ice_initializer_preserves_full_positive_int64_domain() {
    for max in [1, 2, i64::from(u32::MAX) + 1, i64::MAX] {
        let s = base(max, true); assert_eq!(s.maximum_attempts, max);
        assert_eq!(s.epoch, 0); assert_eq!(s.phase, IDLE); assert_eq!(s.attempts, 0);
    }
}
#[test] fn ice_initializer_refuses_nonpositive_reserved_and_noncanonical() {
    for c in [Config { maximum_attempts: 0, grace_positive: 0, reserved: 0 },
        Config { maximum_attempts: -1, grace_positive: 0, reserved: 0 },
        Config { maximum_attempts: 1, grace_positive: 2, reserved: 0 },
        Config { maximum_attempts: 1, grace_positive: 0, reserved: 1 }] {
        let o = init(1, c); assert_eq!(o.status, BAD_CONFIG); assert_eq!(o.copied_config, c);
        assert_eq!(o.candidate_state, State::default());
    }
}
#[test] fn ice_abi_refuses_zero_and_high_alias() {
    for abi in [0, 2, 0x1_0001, u32::MAX] {
        let c = Config { maximum_attempts: 2, grace_positive: 1, reserved: 0 };
        assert_eq!(init(abi, c).status, BAD_ABI);
        refusal(abi, base(2, true), external(REQUEST), BAD_ABI);
    }
}
#[test] fn ice_grace_acceleration_advances_epoch_and_coalesces_attempts() {
    let s = call(base(2, true), external(ICE_DISCONNECTED), LAUNCH);
    assert_eq!((s.phase, s.epoch), (GRACE, 1));
    assert_eq!(call(s, external(ICE_DISCONNECTED), NO_EFFECT), s);
    let s = call(s, external(REQUEST), LAUNCH); assert_eq!((s.phase, s.epoch), (ATTEMPTING, 2));
    assert_eq!(call(s, external(ICE_FAILED), NO_EFFECT), s);
}
#[test] fn ice_zero_grace_starts_attempting_without_grace_effect() {
    let s = call(base(2, false), external(ICE_DISCONNECTED), LAUNCH);
    assert_eq!((s.phase, s.attempts), (ATTEMPTING, 0));
    let s = call(s, internal(WORKFLOW_ENTERED, s), NEXT_ATTEMPT);
    assert_eq!(call(s, internal(BEGIN_ATTEMPT, s), RESTART).attempts, 1);
}
#[test] fn ice_success_wait_retry_then_exactly_once_exhaustion() {
    let s = wait(returned(started(2), true), 2, true);
    let s = call(s, internal(ATTEMPT_BOUNDARY, s), PREFLIGHT_RETRY);
    let s = wait(s, 3, true); let s = call(s, internal(BEGIN_ATTEMPT, s), RESTART);
    assert_eq!(s.attempts, 2);
    let s = wait(returned(s, true), 2, true);
    let s = call(s, internal(ATTEMPT_BOUNDARY, s), PREFLIGHT_EXHAUST);
    let s = call(s, internal(ADMIT_EXHAUST, s), DELIVER_EXHAUSTION);
    assert_eq!((s.phase, s.exhaustion_delivered), (EXHAUSTED, 1));
    assert_eq!(call(s, external(REQUEST), NO_EFFECT), s);
    let s = finish(s); assert_eq!((s.phase, s.attempts, s.exhaustion_delivered), (EXHAUSTED, 2, 1));
}
#[test] fn ice_failed_restart_consumes_attempt_and_skips_timeout() {
    let s = returned(started(2), false); assert_eq!((s.phase, s.attempts), (ATTEMPTING, 1));
    let s = call(s, internal(ATTEMPT_BOUNDARY, s), PREFLIGHT_RETRY);
    assert_eq!((s.phase, s.attempts), (RETRY, 1));
}
#[test] fn ice_each_failed_sleep_stops_then_same_epoch_finish_resets_idle() {
    let grace = call(base(2, true), external(ICE_DISCONNECTED), LAUNCH);
    let grace = call(grace, internal(WORKFLOW_ENTERED, grace), PREFLIGHT_GRACE);
    let timeout = returned(started(2), true);
    let retry = returned(started(2), false);
    let retry = call(retry, internal(ATTEMPT_BOUNDARY, retry), PREFLIGHT_RETRY);
    for (s, kind) in [(grace, 1), (timeout, 2), (retry, 3)] {
        let s = wait(s, kind, false); let s = finish(s);
        assert_eq!((s.phase, s.attempts, s.exhaustion_delivered), (IDLE, 0, 0));
        assert_eq!(call(s, external(REQUEST), LAUNCH).epoch, s.epoch.wrapping_add(1));
    }
}
#[test] fn ice_epoch_wrap_zero_is_a_current_workflow() {
    let mut s = base(1, false); s.epoch = u64::MAX;
    let s = call(s, external(REQUEST), LAUNCH); assert_eq!(s.epoch, 0);
    let s = call(s, internal(WORKFLOW_ENTERED, s), NEXT_ATTEMPT);
    assert_eq!(call(s, internal(BEGIN_ATTEMPT, s), RESTART).attempts, 1);
}
#[test] fn ice_maximum_final_attempt_does_not_increment_past_int64() {
    let mut s = started(i64::MAX); s.attempts = i64::MAX;
    let s = returned(s, false);
    let s = call(s, internal(ATTEMPT_BOUNDARY, s), PREFLIGHT_EXHAUST);
    let s = call(s, internal(ADMIT_EXHAUST, s), DELIVER_EXHAUSTION);
    assert_eq!(s.attempts, i64::MAX); assert_eq!(s.exhaustion_delivered, 1);
}
#[test] fn ice_connection_resets_exhaustion_and_preserves_wrapping() {
    let s = returned(started(1), false);
    let s = call(s, internal(ATTEMPT_BOUNDARY, s), PREFLIGHT_EXHAUST);
    let s = call(s, internal(ADMIT_EXHAUST, s), DELIVER_EXHAUSTION);
    let mut s = call(s, external(ICE_CONNECTED), NO_EFFECT);
    assert_eq!((s.phase, s.exhaustion_delivered), (IDLE, 0)); s.epoch = u64::MAX;
    assert_eq!(call(s, external(ICE_COMPLETED), NO_EFFECT).epoch, 0);
}
#[test] fn ice_direct_cancel_repeats_but_cancelled_ice_signals_do_not() {
    let s = call(base(2, false), external(CANCEL), NO_EFFECT);
    for opcode in ICE_NEW..=REQUEST { assert_eq!(call(s, external(opcode), NO_EFFECT), s); }
    let t = call(s, external(CANCEL), NO_EFFECT); assert_eq!(t.epoch, s.epoch + 1);
}
#[test] fn ice_cancel_retains_delivered_flag_but_clears_attempts() {
    let s = returned(started(1), false);
    let s = call(s, internal(ATTEMPT_BOUNDARY, s), PREFLIGHT_EXHAUST);
    let s = call(s, internal(ADMIT_EXHAUST, s), DELIVER_EXHAUSTION);
    let s = call(s, external(CANCEL), NO_EFFECT);
    assert_eq!((s.phase, s.attempts, s.exhaustion_delivered), (CANCELLED, 0, 1));
}
#[test] fn ice_stale_restart_and_noncooperative_sleep_have_no_successor() {
    let old = started(2); let replacement = call(old, external(ICE_CONNECTED), NO_EFFECT);
    let mut e = internal(RESTART_RETURNED, old); e.succeeded = 1;
    assert_eq!(call(replacement, e, STOP), replacement);
    let timeout = returned(started(2), true);
    let mut admit = internal(ADMIT_WAIT, timeout); admit.wait_kind = 2;
    let pending = call(timeout, admit, SLEEP_TIMEOUT);
    let replacement = call(pending, external(ICE_CONNECTED), NO_EFFECT);
    let mut e = internal(WAIT_RETURNED, pending); e.wait_kind = 2; e.succeeded = 1;
    assert_eq!(call(replacement, e, STOP), replacement);
}
#[test] fn ice_task_cancellation_admission_stops_but_finish_is_epoch_only() {
    let s = started(2); let mut e = internal(RESTART_RETURNED, s); e.task_cancelled = 1;
    assert_eq!(call(s, e, STOP), s);
    let mut e = internal(FINISH, s); e.task_cancelled = 1;
    let s = call(s, e, RELEASE_TASK); assert_eq!((s.phase, s.attempts), (IDLE, 0));
}
#[test] fn ice_stale_finish_cannot_release_replacement_task() {
    let old = call(base(2, true), external(ICE_DISCONNECTED), LAUNCH);
    let new = call(old, external(REQUEST), LAUNCH);
    assert_eq!(call(new, internal(FINISH, old), NO_EFFECT), new);
}
#[test] fn ice_exhaust_admission_observes_late_task_cancellation() {
    let s = returned(started(1), false);
    let s = call(s, internal(ATTEMPT_BOUNDARY, s), PREFLIGHT_EXHAUST);
    let mut e = internal(ADMIT_EXHAUST, s); e.task_cancelled = 1;
    assert_eq!(call(s, e, STOP), s); assert_eq!(finish(s).phase, IDLE);
}
#[test] fn ice_new_checking_unknown_never_start_recovery() {
    let s = base(2, true);
    for opcode in [ICE_NEW, ICE_CHECKING, ICE_UNKNOWN] { assert_eq!(call(s, external(opcode), NO_EFFECT), s); }
}
#[test] fn ice_current_wait_kind_and_program_counter_are_exact() {
    let s = returned(started(2), true); let mut e = internal(ADMIT_WAIT, s); e.wait_kind = 1;
    refusal(1, s, e, BAD_EVENT); refusal(1, s, internal(BEGIN_ATTEMPT, s), BAD_EVENT);
}
#[test] fn ice_event_envelope_rejects_alias_boolean_reserved_and_unused_fields() {
    let s = base(2, true);
    for e in [Event { opcode: 0x1_0008, ..external(REQUEST) },
        Event { task_cancelled: 1, ..external(REQUEST) }, Event { workflow_epoch: 1, ..external(REQUEST) },
        Event { succeeded: 1, ..external(REQUEST) }, Event { wait_kind: 1, ..external(REQUEST) },
        Event { reserved: 1, ..external(REQUEST) }, Event { abi_version: 0, ..external(REQUEST) }] {
        refusal(1, s, e, BAD_EVENT);
    }
    let s = started(2);
    for e in [Event { task_cancelled: 2, ..internal(RESTART_RETURNED, s) },
        Event { succeeded: 2, ..internal(RESTART_RETURNED, s) }] { refusal(1, s, e, BAD_EVENT); }
}
#[test] fn ice_state_envelope_rejects_every_closed_field_corruption() {
    let b = base(2, true);
    for s in [State { abi_version: 0, ..b }, State { phase: 0x1_0000, ..b },
        State { maximum_attempts: 0, ..b }, State { attempts: -1, ..b },
        State { attempts: 3, ..b }, State { exhaustion_delivered: 2, ..b },
        State { grace_positive: 2, ..b }, State { cursor: 0x1_0000, ..b },
        State { reserved: 1, ..b }] { refusal(1, s, external(REQUEST), BAD_STATE); }
}
#[test] fn ice_finish_preserves_cancelled_and_exhausted_terminal_state() {
    let s = call(base(2, true), external(CANCEL), NO_EFFECT);
    assert_eq!(finish(s), s);
    let s = returned(started(1), false);
    let s = call(s, internal(ATTEMPT_BOUNDARY, s), PREFLIGHT_EXHAUST);
    let s = call(s, internal(ADMIT_EXHAUST, s), DELIVER_EXHAUSTION);
    let f = finish(s); assert_eq!((f.phase, f.attempts, f.exhaustion_delivered), (EXHAUSTED, 1, 1));
}
#[test] fn ice_all_active_phases_coalesce_failed_and_requested() {
    let restart = started(2); let awaiting = returned(restart, true);
    let advance = returned(restart, false);
    let retry = call(advance, internal(ATTEMPT_BOUNDARY, advance), PREFLIGHT_RETRY);
    for s in [restart, awaiting, retry] {
        for op in [REQUEST, ICE_FAILED, ICE_DISCONNECTED] { assert_eq!(call(s, external(op), NO_EFFECT), s); }
    }
}
#[test] fn ice_exhaust_admission_cursor_requires_final_attempt() {
    for phase in [ATTEMPTING, AWAITING] {
        let s = State { phase, cursor: EXHAUST_ADMISSION, ..started(2) };
        refusal(1, s, internal(ADMIT_EXHAUST, s), BAD_STATE);
    }
}
