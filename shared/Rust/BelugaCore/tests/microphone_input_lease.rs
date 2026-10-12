use beluga_core::microphone_input_lease::{self as policy, RawFacts, RawResult};

fn facts(opcode: u32, disposition: u32, count: i64, maximum: i64) -> RawFacts {
    RawFacts { abi_version: 1, opcode, disposition, reserved: 0,
        attempt_count: count, maximum_attempt_count: maximum }
}

fn expect(input: RawFacts, action: u32) {
    let expected = RawResult { abi_version: 1, status: 1, opcode: input.opcode,
        action, reserved: 0 };
    assert_eq!(policy::decide(input), expected);
    assert_eq!(policy::result_is_valid(input, expected), 1);
}

fn refuse(input: RawFacts) {
    let result = policy::decide(input);
    assert_eq!(result, RawResult { abi_version: 1, status: 0, opcode: 0, action: 0, reserved: 0 });
    assert_eq!(policy::result_is_valid(input, result), 0);
}

#[test]
fn input_lease_literal_layout_and_field_offsets() {
    assert_eq!((std::mem::size_of::<RawFacts>(), std::mem::align_of::<RawFacts>()), (32, 8));
    assert_eq!((std::mem::size_of::<RawResult>(), std::mem::align_of::<RawResult>()), (20, 4));
    assert_eq!([std::mem::offset_of!(RawFacts, abi_version), std::mem::offset_of!(RawFacts, opcode),
        std::mem::offset_of!(RawFacts, disposition), std::mem::offset_of!(RawFacts, reserved),
        std::mem::offset_of!(RawFacts, attempt_count), std::mem::offset_of!(RawFacts, maximum_attempt_count)],
        [0, 4, 8, 12, 16, 24]);
    assert_eq!([std::mem::offset_of!(RawResult, abi_version), std::mem::offset_of!(RawResult, status),
        std::mem::offset_of!(RawResult, opcode), std::mem::offset_of!(RawResult, action),
        std::mem::offset_of!(RawResult, reserved)], [0, 4, 8, 12, 16]);
}

#[test]
fn input_lease_acquisition_budget_preserves_literal_one_and_three_caps() {
    for (maximum, actions) in [(1, [1, 2, 2, 2, 2]), (3, [1, 1, 1, 2, 2])] {
        for (count, action) in actions.into_iter().enumerate() {
            expect(facts(1, 0, count as i64, maximum), action);
        }
    }
    expect(facts(1, 0, i64::MAX - 1, i64::MAX), 1);
    expect(facts(1, 0, i64::MAX, i64::MAX), 2);
    // The kernel does not increment counts, reset identities, or manufacture a row.
}

#[test]
fn input_lease_acquisition_native_outcomes_have_three_literal_actions() {
    for (disposition, action) in [(1, 3), (2, 4), (3, 5)] {
        expect(facts(2, disposition, 0, 0), action);
    }
}

#[test]
fn input_lease_release_continuation_requires_retryable_and_strict_budget() {
    for disposition in 0..=3 {
        for (count, maximum, expected_retry) in [
            (1, 1, false), (1, 3, true), (2, 3, true), (3, 3, false),
            (4, 3, false), (i64::MAX - 1, i64::MAX, true),
            (i64::MAX, i64::MAX, false),
        ] {
            expect(facts(3, disposition, count, maximum),
                if disposition == 2 && expected_retry { 6 } else { 7 });
        }
    }
}

#[test]
fn input_lease_release_outcome_preserves_native_fallback_and_external_result() {
    for (disposition, action) in [(0, 8), (1, 9), (2, 10), (3, 9)] {
        expect(facts(4, disposition, 0, 0), action);
    }
}

#[test]
fn input_lease_closed_wire_rejects_all_unused_and_negative_domains() {
    let valid = [facts(1, 0, 0, 3), facts(2, 1, 0, 0), facts(3, 2, 1, 3), facts(4, 0, 0, 0)];
    for input in valid {
        refuse(RawFacts { abi_version: 0, ..input });
        refuse(RawFacts { abi_version: 2, ..input });
        refuse(RawFacts { reserved: 1, ..input });
        for opcode in [0, 5, u32::MAX] { refuse(RawFacts { opcode, ..input }); }
    }
    for input in [facts(1, 1, 0, 3), facts(1, 0, -1, 3), facts(1, 0, 0, 0),
        facts(1, 0, 0, -1), facts(2, 0, 0, 0), facts(2, 4, 0, 0),
        facts(2, 1, 1, 0), facts(2, 1, 0, 1), facts(3, 4, 1, 3),
        facts(3, 2, 0, 3), facts(3, 2, -1, 3), facts(3, 2, 1, 0),
        facts(3, 2, 1, -1), facts(4, 4, 0, 0), facts(4, 0, 1, 0),
        facts(4, 0, 0, 1)] { refuse(input); }
}

#[test]
fn input_lease_verifier_rejects_each_field_and_coherent_cross_operation_results() {
    for input in [facts(1, 0, 0, 3), facts(1, 0, 3, 3), facts(2, 1, 0, 0),
        facts(2, 2, 0, 0), facts(2, 3, 0, 0), facts(3, 2, 1, 3),
        facts(3, 2, 3, 3), facts(4, 0, 0, 0), facts(4, 1, 0, 0), facts(4, 2, 0, 0)] {
        let actual = policy::decide(input);
        for malformed in [RawResult { abi_version: 2, ..actual },
            RawResult { status: 0, ..actual }, RawResult { status: 2, ..actual },
            RawResult { opcode: 0, ..actual }, RawResult { opcode: input.opcode % 4 + 1, ..actual },
            RawResult { action: 0, ..actual }, RawResult { action: 11, ..actual },
            RawResult { action: actual.action % 10 + 1, ..actual }, RawResult { reserved: 1, ..actual }] {
            assert_eq!(policy::result_is_valid(input, malformed), 0);
        }
        for action in 1..=10 {
            let coherent = RawResult { action, ..actual };
            assert_eq!(policy::result_is_valid(input, coherent), u32::from(action == actual.action));
        }
    }
}

#[test]
fn input_lease_actual_c_exports_correlate_accepted_and_refused_results() {
    for input in [facts(1, 0, 0, 3), facts(1, 0, 3, 3), facts(2, 1, 0, 0),
        facts(2, 2, 0, 0), facts(2, 3, 0, 0), facts(3, 2, 1, 3),
        facts(3, 3, 1, 3), facts(4, 0, 0, 0), facts(4, 1, 0, 0),
        facts(4, 2, 0, 0), facts(4, 3, 0, 0)] {
        let actual = beluga_core::beluga_core_microphone_input_lease_decide(input);
        assert_eq!(actual, policy::decide(input));
        assert_eq!(beluga_core::beluga_core_microphone_input_lease_result_is_valid(input, actual), 1);
        assert_eq!(beluga_core::beluga_core_microphone_input_lease_result_is_valid(input,
            RawResult { action: actual.action % 10 + 1, ..actual }), 0);
    }
    let invalid = facts(1, 0, -1, 3);
    let actual = beluga_core::beluga_core_microphone_input_lease_decide(invalid);
    assert_eq!(beluga_core::beluga_core_microphone_input_lease_result_is_valid(invalid, actual), 0);
}
