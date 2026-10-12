//! Proposed ordinary integration tests; no compiler/runtime execution recorded.
//! Expectations are literal tables derived from the pre-migration Swift cuts.
#![forbid(unsafe_code)]

use beluga_core::microphone_forwarding_retry as retry;
use retry::*;

fn config(maximum: i64) -> RawConfig {
    RawConfig { abi_version: 1, reserved: 0, maximum_attempt_count: maximum }
}
fn absent() -> RawState {
    RawState { abi_version: 1, present: 0, may_retry: 0, reserved: 0, count: 0 }
}
fn present(count: i64, may_retry: bool) -> RawState {
    RawState { abi_version: 1, present: 1, may_retry: u32::from(may_retry),
        reserved: 0, count }
}
fn event(opcode: u32) -> RawEvent {
    RawEvent { opcode, failure_category: 0, bridge_faulted: 0, reserved: 0 }
}
fn failure(category: u32, faulted: bool) -> RawEvent {
    RawEvent { opcode: OP_RETRY_FAILURE, failure_category: category,
        bridge_faulted: u32::from(faulted), reserved: 0 }
}
fn accepted(state: RawState, decision: bool, redrive_action: u32) -> RawResult {
    RawResult { state, status: 1, decision: u32::from(decision),
        redrive_action, reserved: 0 }
}
fn assert_refused(c: RawConfig, before: RawState, e: RawEvent) {
    let expected = RawResult { state: before, status: 0, decision: 0,
        redrive_action: 0, reserved: 0 };
    assert_eq!(step(c, before, e), expected);
    assert_eq!(result_is_valid(c, before, e, expected), 0,
        "matching invalid output must not become an accepted false vote");
}

#[test]
fn wire_sizes_alignments_and_discriminants_are_literal() {
    use core::mem::{align_of, offset_of, size_of};
    assert_eq!((size_of::<RawConfig>(), align_of::<RawConfig>()), (16, 8));
    assert_eq!((size_of::<RawState>(), align_of::<RawState>()), (24, 8));
    assert_eq!((size_of::<RawEvent>(), align_of::<RawEvent>()), (16, 4));
    assert_eq!((size_of::<RawResult>(), align_of::<RawResult>()), (40, 8));
    assert_eq!([
        offset_of!(RawConfig, abi_version), offset_of!(RawConfig, reserved),
        offset_of!(RawConfig, maximum_attempt_count),
    ], [0, 4, 8]);
    assert_eq!([
        offset_of!(RawState, abi_version), offset_of!(RawState, present),
        offset_of!(RawState, may_retry), offset_of!(RawState, reserved),
        offset_of!(RawState, count),
    ], [0, 4, 8, 12, 16]);
    assert_eq!([
        offset_of!(RawEvent, opcode), offset_of!(RawEvent, failure_category),
        offset_of!(RawEvent, bridge_faulted), offset_of!(RawEvent, reserved),
    ], [0, 4, 8, 12]);
    assert_eq!([
        offset_of!(RawResult, state), offset_of!(RawResult, status),
        offset_of!(RawResult, decision), offset_of!(RawResult, redrive_action),
        offset_of!(RawResult, reserved),
    ], [0, 24, 28, 32, 36]);
    assert_eq!([OP_ELIGIBLE, OP_RECORD_ATTEMPT, OP_RETRY_FAILURE, OP_EXHAUST], [1, 2, 3, 4]);
    assert_eq!([REDRIVE_RETAIN, REDRIVE_CLEAR, REDRIVE_REQUEST], [0, 1, 2]);
}

#[test]
fn eligibility_preserves_absence_fault_and_strict_budget_boundary() {
    let mut e = event(OP_ELIGIBLE);
    assert_eq!(step(config(3), absent(), e), accepted(absent(), true, 0));
    e.bridge_faulted = 1;
    assert_eq!(step(config(3), absent(), e), accepted(absent(), false, 0));
    // Each tuple contains the independent expected healthy vote.
    for (count, may_retry, expected) in [
        (1, false, false), (1, true, true), (2, true, true),
        (3, true, false), (4, true, false), (i64::MAX, true, false),
    ] {
        let before = present(count, may_retry);
        e.bridge_faulted = 0;
        assert_eq!(step(config(3), before, e), accepted(before, expected, 0));
        e.bridge_faulted = 1;
        assert_eq!(step(config(3), before, e), accepted(before, false, 0));
    }
    let before = present(i64::MAX - 1, true);
    e.bridge_faulted = 0;
    assert_eq!(step(config(i64::MAX), before, e), accepted(before, true, 0));
}

#[test]
fn recording_sets_one_or_increments_and_always_consumes_retry_permission() {
    assert_eq!(step(config(3), absent(), event(OP_RECORD_ATTEMPT)),
        accepted(present(1, false), false, 0));
    for (count, expected_count) in [(1, 2), (2, 3), (3, 4), (i64::MAX - 1, i64::MAX)] {
        for may_retry in [false, true] {
            assert_eq!(step(config(3), present(count, may_retry), event(OP_RECORD_ATTEMPT)),
                accepted(present(expected_count, false), false, 0));
        }
    }
}

#[test]
fn all_eleven_native_failure_categories_have_literal_retry_votes() {
    // monitoring, output, start, admission, readiness, stalled source, format,
    // shared clock, enqueue, progress stall, bridge refusal.
    let whitelist = [false, true, true, false, true, true, false, false, true, true, false];
    for (index, expected) in whitelist.into_iter().enumerate() {
        let before = present(1, false);
        let e = failure((index + 1) as u32, false);
        let expected_state = present(1, expected);
        assert_eq!(step(config(3), before, e),
            accepted(expected_state, expected, if expected { 2 } else { 1 }));
        assert_eq!(step(config(3), before, failure((index + 1) as u32, true)),
            accepted(before, false, 1));
    }
}

#[test]
fn retry_failure_never_creates_history_or_reopens_a_consumed_budget() {
    assert_eq!(step(config(3), absent(), failure(3, false)),
        accepted(absent(), false, 1));
    for (count, expected) in [(1, true), (2, true), (3, false), (4, false), (i64::MAX, false)] {
        for prior_permission in [false, true] {
            let before = present(count, prior_permission);
            let expected_state = if expected { present(count, true) } else { before };
            assert_eq!(step(config(3), before, failure(9, false)),
                accepted(expected_state, expected, if expected { 2 } else { 1 }));
            assert_eq!(step(config(3), before, failure(9, true)), accepted(before, false, 1));
        }
    }
    // A nonretryable category does not silently clear existing history permission.
    let before = present(1, true);
    assert_eq!(step(config(3), before, failure(4, false)), accepted(before, false, 1));
}

#[test]
fn exhaust_absent_history_retains_redrive_but_existing_history_clears_it() {
    assert_eq!(step(config(3), absent(), event(OP_EXHAUST)),
        accepted(absent(), false, REDRIVE_RETAIN));
    for count in [1, 3, 4, i64::MAX] {
        for permission in [false, true] {
            assert_eq!(step(config(3), present(count, permission), event(OP_EXHAUST)),
                accepted(present(count, false), false, REDRIVE_CLEAR));
        }
    }
}

#[test]
fn default_three_attempt_sequence_exhausts_and_fresh_native_key_starts_independently() {
    let c = config(3);
    let before = absent();
    assert_eq!(step(c, before, event(OP_ELIGIBLE)), accepted(before, true, 0));
    for (before, recorded, retry_result, next_vote) in [
        (absent(), present(1, false), present(1, true), true),
        (present(1, true), present(2, false), present(2, true), true),
        (present(2, true), present(3, false), present(3, false), false),
    ] {
        assert_eq!(step(c, before, event(OP_RECORD_ATTEMPT)), accepted(recorded, false, 0));
        assert_eq!(step(c, recorded, failure(3, false)),
            accepted(retry_result, next_vote, if next_vote { 2 } else { 1 }));
        assert_eq!(step(c, retry_result, event(OP_ELIGIBLE)),
            accepted(retry_result, next_vote, 0));
    }
    assert_eq!(step(c, absent(), event(OP_ELIGIBLE)), accepted(absent(), true, 0));
    // Native dictionary removal/new key chooses this absence; Rust has no key/reset authority.
    assert_eq!(step(config(1), absent(), event(OP_ELIGIBLE)), accepted(absent(), true, 0));
    assert_eq!(step(config(1), absent(), event(OP_RECORD_ATTEMPT)),
        accepted(present(1, false), false, 0));
    assert_eq!(step(config(1), present(1, false), event(OP_ELIGIBLE)),
        accepted(present(1, false), false, 0));
    assert_eq!(step(config(1), present(1, false), failure(3, false)),
        accepted(present(1, false), false, 1));
    assert_eq!(step(config(1), present(1, true), event(OP_ELIGIBLE)),
        accepted(present(1, true), false, 0));
}

#[test]
fn malformed_config_state_and_event_carriers_refuse_with_exact_state_retention() {
    let c = config(3);
    let before = present(1, true);
    let e = event(OP_ELIGIBLE);
    for bad in [
        RawConfig { abi_version: 0, ..c }, RawConfig { abi_version: 2, ..c },
        RawConfig { reserved: 1, ..c }, config(0), config(-1), config(i64::MIN),
    ] { assert_refused(bad, before, e); }
    for bad in [
        RawState { abi_version: 0, ..before }, RawState { abi_version: 2, ..before },
        RawState { reserved: 1, ..before }, RawState { present: 2, ..before },
        RawState { may_retry: 2, ..before }, RawState { count: 0, ..before },
        RawState { count: -1, ..before }, RawState { count: i64::MIN, ..before },
        RawState { count: 1, ..absent() }, RawState { may_retry: 1, ..absent() },
    ] { assert_refused(c, bad, e); }
    for bad in [
        RawEvent { opcode: 0, ..e }, RawEvent { opcode: 5, ..e },
        RawEvent { opcode: u32::MAX, ..e }, RawEvent { reserved: 1, ..e },
        RawEvent { bridge_faulted: 2, ..e }, RawEvent { failure_category: 1, ..e },
        RawEvent { bridge_faulted: 1, ..event(OP_RECORD_ATTEMPT) },
        RawEvent { failure_category: 3, ..event(OP_RECORD_ATTEMPT) },
        RawEvent { bridge_faulted: 1, ..event(OP_EXHAUST) },
        RawEvent { failure_category: 3, ..event(OP_EXHAUST) },
        failure(0, false), failure(12, false), failure(u32::MAX, true),
        RawEvent { bridge_faulted: 2, ..failure(3, false) },
    ] { assert_refused(c, before, bad); }
}

#[test]
fn unrepresentable_increment_refuses_without_saturating_or_wrapping() {
    let before = present(i64::MAX, true);
    assert_refused(config(i64::MAX), before, event(OP_RECORD_ATTEMPT));
    assert_eq!(step(config(i64::MAX), before, event(OP_ELIGIBLE)),
        accepted(before, false, 0));
    assert_eq!(step(config(i64::MAX), before, failure(3, false)),
        accepted(before, false, 1));
    assert_eq!(step(config(i64::MAX), before, event(OP_EXHAUST)),
        accepted(present(i64::MAX, false), false, 1));
}

#[test]
fn result_correlation_rejects_every_coherent_or_malformed_changed_field() {
    let c = config(3);
    let before = present(1, false);
    let e = failure(3, false);
    let expected = accepted(present(1, true), true, REDRIVE_REQUEST);
    assert_eq!(step(c, before, e), expected);
    assert_eq!(result_is_valid(c, before, e, expected), 1);
    for corrupt in [
        RawResult { state: present(2, true), ..expected },
        RawResult { state: present(1, false), ..expected },
        RawResult { state: absent(), ..expected },
        RawResult { state: RawState { present: 2, ..expected.state }, ..expected },
        RawResult { state: RawState { count: 0, ..expected.state }, ..expected },
        RawResult { state: RawState { may_retry: 2, ..expected.state }, ..expected },
        RawResult { state: RawState { abi_version: 2, ..expected.state }, ..expected },
        RawResult { state: RawState { reserved: 1, ..expected.state }, ..expected },
        RawResult { status: 0, ..expected }, RawResult { status: 2, ..expected },
        RawResult { decision: 0, ..expected }, RawResult { decision: 2, ..expected },
        RawResult { redrive_action: REDRIVE_CLEAR, ..expected },
        RawResult { redrive_action: 3, ..expected }, RawResult { reserved: 1, ..expected },
    ] { assert_eq!(result_is_valid(c, before, e, corrupt), 0); }
    // An accepted false vote is valid; flipping just its decision is not.
    for (before, e, expected) in [
        (present(3, true), event(OP_ELIGIBLE),
            accepted(present(3, true), false, REDRIVE_RETAIN)),
        (present(1, true), failure(4, false),
            accepted(present(1, true), false, REDRIVE_CLEAR)),
    ] {
        assert_eq!(step(c, before, e), expected);
        assert_eq!(result_is_valid(c, before, e, expected), 1);
        assert_eq!(result_is_valid(c, before, e,
            RawResult { decision: 1, ..expected }), 0);
    }
    // Accepted Record/Exhaust outputs must also correlate every result field.
    // These literal states are independent of the candidate evaluator.
    for (before, e, expected) in [
        (absent(), event(OP_RECORD_ATTEMPT),
            accepted(present(1, false), false, REDRIVE_RETAIN)),
        (present(1, true), event(OP_RECORD_ATTEMPT),
            accepted(present(2, false), false, REDRIVE_RETAIN)),
        (absent(), event(OP_EXHAUST),
            accepted(absent(), false, REDRIVE_RETAIN)),
        (present(1, true), event(OP_EXHAUST),
            accepted(present(1, false), false, REDRIVE_CLEAR)),
    ] {
        assert_eq!(step(c, before, e), expected);
        assert_eq!(result_is_valid(c, before, e, expected), 1);
        for corrupt in [
            RawResult { state: present(7, false), ..expected },
            RawResult { state: present(1, true), ..expected },
            RawResult { state: RawState { abi_version: 2, ..expected.state }, ..expected },
            RawResult { state: RawState { reserved: 1, ..expected.state }, ..expected },
            RawResult { state: RawState { may_retry: 2, ..expected.state }, ..expected },
            RawResult { status: 0, ..expected },
            RawResult { status: 2, ..expected },
            RawResult { decision: 1, ..expected },
            RawResult { redrive_action: REDRIVE_REQUEST, ..expected },
            RawResult { reserved: 1, ..expected },
        ] {
            assert_ne!(corrupt, expected);
            assert_eq!(result_is_valid(c, before, e, corrupt), 0);
        }
    }
}

