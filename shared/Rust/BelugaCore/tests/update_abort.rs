//! Ordinary proposed tests; no compilation or test execution is claimed.
#![forbid(unsafe_code)]
use beluga_core::update_abort::*;

fn request(flags: u32) -> RawRequest { RawRequest { abi_version: 1, flags } }
fn valid(action: u32) -> RawResult { RawResult { abi_version: 1, status: 0, action } }

// Literal original Swift first-if / else-if, independent of production masks/actions.
fn original_swift(raw: RawRequest) -> RawResult {
    let p = |bit: u32| raw.flags & (1 << bit) != 0;
    let action = if p(0) && p(1) && p(2) && !p(3) && p(4) { 1 }
        else if !p(5) { 3 }
        else { 2 };
    valid(action)
}

#[test]
fn wire_layout_offsets_and_literal_constants_are_fixed() {
    use core::mem::{align_of, offset_of, size_of};
    assert_eq!((size_of::<RawRequest>(), align_of::<RawRequest>()), (8, 4));
    assert_eq!((size_of::<RawResult>(), align_of::<RawResult>()), (12, 4));
    assert_eq!([offset_of!(RawRequest, abi_version), offset_of!(RawRequest, flags)], [0, 4]);
    assert_eq!([offset_of!(RawResult, abi_version), offset_of!(RawResult, status),
        offset_of!(RawResult, action)], [0, 4, 8]);
    assert_eq!([ABI_VERSION, STATUS_VALID, STATUS_INVALID], [1, 0, 1]);
    assert_eq!([FAILURE_PRESENT, CLEAN_UNARMED_CYCLE, ACKNOWLEDGED,
        OBSERVED_ABORT, SAME_FAILURE_ERROR, SAME_NO_UPDATE_ERROR], [1, 2, 4, 8, 16, 32]);
    assert_eq!(KNOWN_FLAGS, 63);
    assert_eq!([ACTION_INVALID, ACTION_MARK_ABORT, ACTION_PRESERVE, ACTION_POISON], [0, 1, 2, 3]);
}

#[test]
fn all_64_valid_carriers_match_the_literal_original_first_if_else_if() {
    let mut count = 0;
    for flags in 0..64 {
        let raw = request(flags);
        let expected = original_swift(raw);
        assert_eq!(decide(raw), expected, "flags={flags}");
        assert_eq!(result_is_valid(raw, expected), 1, "flags={flags}");
        count += 1;
    }
    assert_eq!(count, 64);
}

#[test]
fn first_if_mark_abort_wins_even_when_same_no_update_error_is_true() {
    // failure,clean,ack,same-failure,same-no-update; observed-abort is false.
    assert_eq!(decide(request(55)), valid(1));
    assert_eq!(decide(request(23)), valid(1));
    for bit in [0, 1, 2, 4] {
        assert_eq!(decide(request(55 ^ (1 << bit))), valid(2), "missing-bit={bit}");
        assert_eq!(decide(request(23 ^ (1 << bit))), valid(3), "missing-bit={bit}");
    }
    assert_eq!(decide(request(63)), valid(2)); // prior abort blocks the first branch.
    assert_eq!(decide(request(31)), valid(3));
}

#[test]
fn preserve_else_if_is_not_strengthened_by_unrelated_failure_facts() {
    for flags in 0..32 {
        let raw = request(flags | 32);
        assert_eq!(decide(raw), original_swift(raw), "flags={flags}");
    }
    assert_eq!(decide(request(32)), valid(2)); // even absent failure / unclean cycle.
    assert_eq!(decide(request(0)), valid(3));
}

#[test]
fn unsupported_abi_and_every_unknown_flag_refuse_without_valid_action() {
    let refused = RawResult { abi_version: 1, status: 1, action: 0 };
    for flags in 0..64 {
        let raw = request(flags);
        for abi_version in [0, 2, u32::MAX] {
            let invalid = RawRequest { abi_version, ..raw };
            assert_eq!(decide(invalid), refused, "abi={abi_version}, flags={flags}");
            assert_eq!(result_is_valid(invalid, refused), 0);
            for action in 1..=3 { assert_eq!(result_is_valid(invalid, valid(action)), 0); }
        }
        for bit in 6..32 {
            let invalid = RawRequest { flags: flags | (1 << bit), ..raw };
            assert_eq!(decide(invalid), refused, "bit={bit}, flags={flags}");
            assert_eq!(result_is_valid(invalid, refused), 0);
            for action in 1..=3 { assert_eq!(result_is_valid(invalid, valid(action)), 0); }
        }
    }
    assert_eq!(decide(request(u32::MAX)), refused);
    assert_eq!(result_is_valid(request(u32::MAX), refused), 0);
}

#[test]
fn every_result_field_and_coherent_cross_request_action_require_full_correlation() {
    for flags in 0..64 {
        let raw = request(flags);
        let expected = original_swift(raw);
        for value in [0, 1, 2, 3, 4, u32::MAX] {
            for result in [
                RawResult { abi_version: value, ..expected },
                RawResult { status: value, ..expected },
                RawResult { action: value, ..expected },
            ] {
                assert_eq!(result_is_valid(raw, result), u32::from(result == expected),
                    "flags={flags}, result={result:?}");
            }
        }
        for other_flags in 0..64 {
            let other = original_swift(request(other_flags));
            assert_eq!(result_is_valid(raw, other), u32::from(other == expected),
                "flags={flags}, other-flags={other_flags}");
        }
    }
}

#[test]
fn actual_c_exports_match_the_literal_original_and_refuse_unverified_carriers() {
    use beluga_core::{beluga_core_update_abort_decide, beluga_core_update_abort_result_is_valid};
    let refused = RawResult { abi_version: 1, status: 1, action: 0 };
    for flags in 0..64 {
        let raw = request(flags);
        let expected = original_swift(raw);
        let actual = beluga_core_update_abort_decide(raw);
        assert_eq!(actual, expected, "export flags={flags}");
        assert_eq!(beluga_core_update_abort_result_is_valid(raw, actual), 1);
        for value in [0, 1, 2, 3, 4, u32::MAX] {
            for result in [RawResult { abi_version: value, ..actual },
                RawResult { status: value, ..actual }, RawResult { action: value, ..actual }] {
                assert_eq!(beluga_core_update_abort_result_is_valid(raw, result),
                    u32::from(result == expected), "export flags={flags}, result={result:?}");
            }
        }
        for other_flags in 0..64 {
            let other = beluga_core_update_abort_decide(request(other_flags));
            assert_eq!(other, original_swift(request(other_flags)));
            assert_eq!(beluga_core_update_abort_result_is_valid(raw, other),
                u32::from(other == expected), "export flags={flags}, other={other_flags}");
        }
        let invalids = [0, 2, u32::MAX].map(|abi_version| RawRequest { abi_version, ..raw });
        for invalid in invalids.into_iter().chain((6..32).map(|bit|
            RawRequest { flags: flags | (1 << bit), ..raw })) {
            assert_eq!(beluga_core_update_abort_decide(invalid), refused);
            assert_eq!(beluga_core_update_abort_result_is_valid(invalid, refused), 0);
            for action in 1..=3 {
                assert_eq!(beluga_core_update_abort_result_is_valid(invalid, valid(action)), 0);
            }
        }
    }
}
