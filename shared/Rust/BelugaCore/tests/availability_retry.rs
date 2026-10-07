// Copied availability retry contract against the actual production crate export.
use beluga_core::beluga_core_availability_retry_step as actual;
use beluga_core::availability_retry::{RawEvent, RawResult, RawState};
use std::mem::{align_of, offset_of, size_of};

fn state(delay: u32, validated: u32) -> RawState {
    RawState { abi_version: 1, next_delay_seconds: delay,
        has_validated_connection: validated, reserved: 0 }
}
fn event(opcode: u32) -> RawEvent { RawEvent { opcode, reserved: 0 } }

// Independent literal states and full original transitions. No production enum,
// decoder, successor, or decision constant is used to compute these expectations.
const STATES: [(u32, u32); 7] = [(1,0), (2,0), (4,0), (8,0), (16,0), (30,0), (1,1)];
// input delay, input validated, operation, candidate delay, candidate validated,
// decision, became validated, returned retry seconds.
const TABLE: [(u32,u32,u32,u32,u32,u32,u32,u32); 14] = [
    (1,0,0,1,1,0,1,0), (1,0,1,2,0,1,0,1),
    (2,0,0,1,1,0,1,0), (2,0,1,4,0,1,0,2),
    (4,0,0,1,1,0,1,0), (4,0,1,8,0,1,0,4),
    (8,0,0,1,1,0,1,0), (8,0,1,16,0,1,0,8),
    (16,0,0,1,1,0,1,0), (16,0,1,30,0,1,0,16),
    (30,0,0,1,1,0,1,0), (30,0,1,30,0,1,0,30),
    (1,1,0,1,1,0,0,0), (1,1,1,2,0,1,0,1),
];

fn table_row(before: RawState, opcode: u32) -> RawResult {
    let row = TABLE.iter().find(|r| r.0 == before.next_delay_seconds
        && r.1 == before.has_validated_connection && r.2 == opcode).unwrap();
    RawResult { candidate_state: state(row.3, row.4), decision: row.5,
        became_validated: row.6, retry_delay_seconds: row.7, reserved: 0 }
}

// Separately transcribed original Swift two methods, for admitted states only.
// Traces compare each real reducer call to this original arithmetic, not a shared
// model helper that executes both expected and actual lifecycle effects.
fn original_native(before: RawState, opcode: u32) -> RawResult {
    let mut candidate = before;
    if opcode == 0 {
        candidate.has_validated_connection = 1;
        candidate.next_delay_seconds = 1;
        RawResult { candidate_state: candidate, decision: 0,
            became_validated: u32::from(before.has_validated_connection == 0),
            retry_delay_seconds: 0, reserved: 0 }
    } else {
        candidate.next_delay_seconds = (before.next_delay_seconds * 2).min(30);
        candidate.has_validated_connection = 0;
        RawResult { candidate_state: candidate, decision: 1,
            became_validated: 0, retry_delay_seconds: before.next_delay_seconds, reserved: 0 }
    }
}

fn assert_invalid(abi: u32, before: RawState, input: RawEvent) {
    assert_eq!(actual(abi, before, input), RawResult {
        candidate_state: before, decision: 2, became_validated: 0,
        retry_delay_seconds: 0, reserved: 0,
    });
}

#[test]
fn availability_retry_layout_and_actual_export_are_exact() {
    assert_eq!((size_of::<RawState>(), align_of::<RawState>()), (16,4));
    assert_eq!((offset_of!(RawState, abi_version), offset_of!(RawState, next_delay_seconds),
        offset_of!(RawState, has_validated_connection), offset_of!(RawState, reserved)), (0,4,8,12));
    assert_eq!((size_of::<RawEvent>(), align_of::<RawEvent>()), (8,4));
    assert_eq!((offset_of!(RawEvent, opcode), offset_of!(RawEvent, reserved)), (0,4));
    assert_eq!((size_of::<RawResult>(), align_of::<RawResult>()), (32,4));
    assert_eq!((offset_of!(RawResult, candidate_state), offset_of!(RawResult, decision),
        offset_of!(RawResult, became_validated), offset_of!(RawResult, retry_delay_seconds),
        offset_of!(RawResult, reserved)), (0,16,20,24,28));
    assert_eq!(actual(1, state(1,0), event(1)), table_row(state(1,0),1));
}

#[test]
fn availability_retry_all_fourteen_literal_transitions_match() {
    for &(delay, validated) in &STATES {
        for opcode in [0,1] {
            let before = state(delay,validated);
            let out = actual(1,before,event(opcode));
            assert_eq!(out,table_row(before,opcode));
            assert!(STATES.contains(&(out.candidate_state.next_delay_seconds,
                out.candidate_state.has_validated_connection)));
        }
    }
}

#[test]
fn availability_retry_reset_and_became_marker_match_each_state() {
    for &(delay,validated) in &STATES {
        let out = actual(1,state(delay,validated),event(0));
        assert_eq!(out.candidate_state,state(1,1));
        assert_eq!(out.became_validated,u32::from(validated == 0));
        assert_eq!(out.decision,0);
        assert_eq!(out.retry_delay_seconds,0);
        assert_eq!(out.reserved,0);
    }
}

#[test]
fn availability_retry_repeated_valid_state_is_reported_only_once() {
    let first = actual(1,state(30,0),event(0));
    let second = actual(1,first.candidate_state,event(0));
    assert_eq!(first.became_validated,1);
    assert_eq!(second,RawResult { candidate_state:state(1,1),decision:0,
        became_validated:0,retry_delay_seconds:0,reserved:0 });
}

#[test]
fn availability_retry_failure_returns_old_delay_and_clears_validation() {
    for &(delay,validated) in &STATES {
        let out = actual(1,state(delay,validated),event(1));
        assert_eq!(out.retry_delay_seconds,delay);
        assert_eq!(out.became_validated,0);
        assert_eq!(out.decision,1);
        assert_eq!(out.candidate_state.has_validated_connection,0);
        assert_eq!(out.reserved,0);
    }
}

#[test]
fn availability_retry_failures_double_then_saturate_at_thirty() {
    let mut current = state(1,0);
    for expected in [1,2,4,8,16,30,30,30,30] {
        let out = actual(1,current,event(1));
        assert_eq!(out.retry_delay_seconds,expected);
        assert_eq!(out,table_row(current,1));
        current = out.candidate_state;
    }
    assert_eq!(current,state(30,0));
}

#[test]
fn availability_retry_valid_failure_valid_rearms_marker() {
    let first = actual(1,state(8,0),event(0));
    let failure = actual(1,first.candidate_state,event(1));
    let next = actual(1,failure.candidate_state,event(0));
    assert_eq!(failure.retry_delay_seconds,1);
    assert_eq!(failure.candidate_state,state(2,0));
    assert_eq!(next.candidate_state,state(1,1));
    assert_eq!(next.became_validated,1);
}

#[test]
fn availability_retry_bounded_histories_match_original_native_and_literals() {
    // All 57,337 binary histories of length 0..12, from all seven legal starts.
    for &(delay,validated) in &STATES {
        for length in 0..=12 {
            for bits in 0..(1_u32 << length) {
                let mut actual_state = state(delay,validated);
                let mut expected_state = state(delay,validated);
                for position in 0..length {
                    let opcode = (bits >> position) & 1;
                    let expected = original_native(expected_state,opcode);
                    assert_eq!(expected,table_row(expected_state,opcode));
                    let out = actual(1,actual_state,event(opcode));
                    assert_eq!(out,expected);
                    actual_state = out.candidate_state;
                    expected_state = expected.candidate_state;
                }
            }
        }
    }
}

#[test]
fn availability_retry_long_traces_remain_bounded_without_counter_overflow() {
    for &(delay,validated) in &STATES {
        for schedule in [0,1,2] {
            let mut current = state(delay,validated);
            let mut expected = current;
            for tick in 0..16_384 {
                let opcode = match schedule { 0 => 1, 1 => 0, _ => u32::from(tick % 37 != 0) };
                let out = actual(1,current,event(opcode));
                let original = original_native(expected,opcode);
                assert_eq!(out,original);
                assert!(STATES.contains(&(out.candidate_state.next_delay_seconds,
                    out.candidate_state.has_validated_connection)));
                current = out.candidate_state;
                expected = original.candidate_state;
            }
        }
    }
}

#[test]
fn availability_retry_closed_raw_state_domains_never_normalize() {
    let delays: Vec<u32> = (0..=35).chain([u32::MAX]).collect();
    for delay in delays {
        for validated in [0,1,2,3,u32::MAX] {
            for abi in [0,1,2,u32::MAX] {
                for reserved in [0,1,u32::MAX] {
                    let before = RawState { abi_version:abi,next_delay_seconds:delay,
                        has_validated_connection:validated,reserved };
                    if abi == 1 && reserved == 0 && STATES.contains(&(delay,validated)) { continue; }
                    for opcode in [0,1] { assert_invalid(1,before,event(opcode)); }
                }
            }
        }
    }
}

#[test]
fn availability_retry_unknown_call_abi_is_invalid_unchanged() {
    for &(delay,validated) in &STATES {
        for abi in [0,2,3,4,u32::MAX] {
            for opcode in [0,1] { assert_invalid(abi,state(delay,validated),event(opcode)); }
        }
    }
}

#[test]
fn availability_retry_closed_event_opcode_and_reserved_never_reset() {
    for &(delay,validated) in &STATES {
        let before = state(delay,validated);
        for opcode in (2..=17).chain([u32::MAX]) { assert_invalid(1,before,event(opcode)); }
        for opcode in [0,1] {
            for reserved in [1,2,3,u32::MAX] {
                assert_invalid(1,before,RawEvent { opcode,reserved });
            }
        }
    }
}

#[test]
fn availability_retry_two_invalid_fields_preserve_exact_raw_state() {
    for &(delay,validated) in &STATES {
        let valid = state(delay,validated);
        let bad = RawState { abi_version:9,reserved:17,..valid };
        assert_invalid(0,bad,RawEvent { opcode:7,reserved:u32::MAX });
        assert_invalid(1,valid,RawEvent { opcode:7,reserved:3 });
        assert_invalid(2,valid,RawEvent { opcode:0,reserved:3 });
        assert_invalid(1,RawState { next_delay_seconds:7,
            has_validated_connection:2,..valid },event(1));
    }
}

#[test]
fn availability_retry_no_websocket_upgrade_operation_exists() {
    // An upgrade is native telemetry only; supplying a third ABI operation must
    // not fabricate validation, reset the accumulated delay, or emit a retry.
    assert_invalid(1,state(16,0),event(2));
}

#[test]
fn availability_retry_value_inputs_are_unmodified_for_valid_and_refused_calls() {
    for &(delay,validated) in &STATES {
        let before = state(delay,validated);
        let copied = before;
        for opcode in [0,1,2] { let _ = actual(1,before,event(opcode)); }
        assert_eq!(before,copied);
    }
}
