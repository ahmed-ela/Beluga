//! Ordinary source-only tests for the copied two-phase check admission.
//! No compiler, test runner, real SDK callback or native effect is claimed.
#![forbid(unsafe_code)]

use beluga_core::update_sparkle_admission::*;

fn request(phase: u32, flags: u32) -> RawRequest {
    RawRequest { abi_version: 1, phase, flags }
}
fn valid(action: u32) -> RawResult {
    RawResult { abi_version: 1, status: 0, action }
}
fn all_valid_requests() -> impl Iterator<Item = RawRequest> {
    (0..8).map(|flags| request(1, flags))
        .chain((0..4).map(|flags| request(2, flags)))
}
fn original_swift_projection(raw: RawRequest) -> RawResult {
    // Literal wire values, not the production decoder, masks or action names.
    // The source's retained-authority callback is an effect between the phases;
    // this oracle only transcribes the ordered guards on either side of it.
    let action = match raw.phase {
        1 => {
            let exact_callback = raw.flags & 1 != 0;
            let manual_updates = raw.flags & 2 != 0;
            let pre_callback_running = raw.flags & 4 != 0;
            if !exact_callback { 1 }
            else if !manual_updates { 2 }
            else if !pre_callback_running { 3 }
            else { 5 }
        }
        2 => {
            let retained_authority = raw.flags & 1 != 0;
            let freshly_requested = raw.flags & 2 != 0;
            if !retained_authority { 3 }
            else if !freshly_requested { 4 }
            else { 6 }
        }
        _ => panic!("literal parity oracle receives only the twelve valid carriers"),
    };
    valid(action)
}
fn assert_refused(raw: RawRequest) {
    let refusal = RawResult { abi_version: 1, status: 1, action: 0 };
    assert_eq!(decide(raw), refusal, "raw={raw:?}");
    assert_eq!(result_is_valid(raw, refusal), 0,
        "even an exact invalid refusal is not a valid ordinary denial: raw={raw:?}");
    for action in 0..=6 {
        assert_eq!(result_is_valid(raw, valid(action)), 0,
            "malformed input cannot certify a closed plausible action: raw={raw:?}, action={action}");
    }
}

#[test]
fn wire_sizes_offsets_and_literal_constants_are_fixed() {
    use core::mem::{align_of, offset_of, size_of};
    assert_eq!((size_of::<RawRequest>(), align_of::<RawRequest>()), (12, 4));
    assert_eq!((size_of::<RawResult>(), align_of::<RawResult>()), (12, 4));
    assert_eq!([offset_of!(RawRequest, abi_version), offset_of!(RawRequest, phase),
        offset_of!(RawRequest, flags)], [0, 4, 8]);
    assert_eq!([offset_of!(RawResult, abi_version), offset_of!(RawResult, status),
        offset_of!(RawResult, action)], [0, 4, 8]);
    assert_eq!([ABI_VERSION, STATUS_VALID, STATUS_INVALID], [1, 0, 1]);
    assert_eq!([PHASE_PREFLIGHT, PHASE_AFTER_AUTHORITY], [1, 2]);
    assert_eq!([EXACT_CALLBACK, MANUAL_UPDATES, PRE_CALLBACK_RUNNING,
        PREFLIGHT_KNOWN_FLAGS], [1, 2, 4, 7]);
    assert_eq!([RETAINED_AUTHORITY, FRESH_REQUESTED, AFTER_AUTHORITY_KNOWN_FLAGS], [1, 2, 3]);
    assert_eq!([ACTION_NONE, ACTION_FOREIGN, ACTION_NON_MANUAL,
        ACTION_AUTHORITY_NOT_RETAINED, ACTION_CHECK_NOT_REQUESTED,
        ACTION_QUERY_AUTHORITY, ACTION_CONSUME_AND_ADMIT], [0, 1, 2, 3, 4, 5, 6]);
}

#[test]
fn all_twelve_valid_carriers_match_literal_original_swift_guards() {
    let mut count = 0;
    for raw in all_valid_requests() {
        let expected = original_swift_projection(raw);
        let actual = decide(raw);
        assert_eq!(actual, expected, "raw={raw:?}");
        assert_eq!(result_is_valid(raw, actual), 1, "raw={raw:?}");
        count += 1;
    }
    assert_eq!(count, 12);
}

#[test]
fn each_original_guard_preserves_error_precedence_and_phase_actions() {
    // Exact callback is first even when check kind and state are also wrong.
    for flags in [0, 2, 4, 6] {
        assert_eq!(decide(request(1, flags)), valid(1), "flags={flags}");
    }
    // Non-manual is second and wins over not-running.
    for flags in [1, 5] {
        assert_eq!(decide(request(1, flags)), valid(2), "flags={flags}");
    }
    assert_eq!(decide(request(1, 3)), valid(3));
    assert_eq!(decide(request(1, 7)), valid(5));
    // Retention wins over requested, including a freshly true requested bit.
    for flags in [0, 2] {
        assert_eq!(decide(request(2, flags)), valid(3), "flags={flags}");
    }
    assert_eq!(decide(request(2, 1)), valid(4));
    assert_eq!(decide(request(2, 3)), valid(6));
}

#[test]
fn malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed() {
    for abi_version in [0, 2, u32::MAX] {
        for mut raw in all_valid_requests() {
            raw.abi_version = abi_version;
            assert_refused(raw);
        }
    }
    for phase in [0, 3, 4, u32::MAX] {
        for flags in [0, 1, 2, 3, 7, u32::MAX] {
            assert_refused(request(phase, flags));
        }
    }
    for shift in 3..32 {
        for base in 0..8 {
            assert_refused(request(1, base | (1u32 << shift)));
        }
    }
    for shift in 2..32 {
        for base in 0..4 {
            assert_refused(request(2, base | (1u32 << shift)));
        }
    }
    // Bit two has a meaning only before the native callback.
    assert_eq!(decide(request(1, 7)), valid(5));
    assert_refused(request(2, 7));
    assert_refused(request(1, u32::MAX));
    assert_refused(request(2, u32::MAX));
    assert_refused(RawRequest { abi_version: u32::MAX, phase: u32::MAX, flags: u32::MAX });
}

#[test]
fn every_result_field_corruption_is_rejected_for_all_valid_requests() {
    for raw in all_valid_requests() {
        let expected = original_swift_projection(raw);
        for replacement in [0, 1, 2, 3, 4, 5, 6, 7, 8, u32::MAX] {
            for candidate in [
                RawResult { abi_version: replacement, ..expected },
                RawResult { status: replacement, ..expected },
                RawResult { action: replacement, ..expected },
            ] {
                assert_eq!(result_is_valid(raw, candidate), u32::from(candidate == expected),
                    "raw={raw:?}, candidate={candidate:?}");
            }
        }
    }
}

#[test]
fn coherent_cross_request_results_require_whole_result_correlation() {
    for target in all_valid_requests() {
        let expected = original_swift_projection(target);
        for other in all_valid_requests() {
            let other_result = original_swift_projection(other);
            assert_eq!(result_is_valid(target, other_result), u32::from(expected == other_result),
                "target={target:?}, other={other:?}");
        }
        // Well-formed scalar fields and a known action do not prove correlation.
        for action in 0..=6 {
            let candidate = valid(action);
            assert_eq!(result_is_valid(target, candidate), u32::from(candidate == expected),
                "target={target:?}, candidate={candidate:?}");
        }
    }
}

#[test]
fn query_and_admission_results_cannot_cross_the_native_authority_boundary() {
    let preflight = request(1, 7);
    let after_authority = request(2, 3);
    let query = valid(5);
    let consume = valid(6);
    assert_eq!(result_is_valid(preflight, query), 1);
    assert_eq!(result_is_valid(preflight, consume), 0);
    assert_eq!(result_is_valid(after_authority, query), 0);
    assert_eq!(result_is_valid(after_authority, consume), 1);
    // Copied phase-two inputs are not evidence that native query occurred.
    // The native caller must own sequencing; Rust cannot mint that evidence.
    assert_eq!(decide(after_authority), consume);
}

#[test]
fn valid_denials_remain_distinct_from_invalid_and_do_not_grant_phase_actions() {
    for raw in all_valid_requests() {
        let expected = original_swift_projection(raw);
        if (1..=4).contains(&expected.action) {
            assert_eq!(expected.status, 0);
            assert_eq!(result_is_valid(raw, expected), 1);
            assert_eq!(result_is_valid(raw, valid(5)), 0, "raw={raw:?}");
            assert_eq!(result_is_valid(raw, valid(6)), 0, "raw={raw:?}");
            assert_eq!(result_is_valid(raw, RawResult { abi_version: 1, status: 1, action: 0 }), 0);
        }
    }
}
