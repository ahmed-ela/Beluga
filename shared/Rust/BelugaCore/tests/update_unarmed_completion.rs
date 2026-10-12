//! Ordinary source-only proposal tests; no execution is claimed.
#![forbid(unsafe_code)]
use beluga_core::update_unarmed_completion::*;

fn request(flags: u32, failure_kind: u32) -> RawRequest {
    RawRequest { abi_version: 1, flags, failure_kind }
}
fn valid(reason: u32) -> RawResult {
    RawResult { abi_version: 1, status: 0, reason }
}

/// Literal transcription of the original Swift inner branches. This oracle
/// does not import production masks/reasons or call the production classifier.
fn original_swift(raw: RawRequest) -> RawResult {
    let p = |bit: u32| raw.flags & (1 << bit) != 0;
    let failure = raw.failure_kind != 0;
    let reason =
        if p(0) && p(1) && !p(2) && !p(3) && !p(4) && !failure && !p(5) { 1 }
        else if failure && p(6) && p(7) && p(8) && p(9) && !p(10) && !p(11)
            && !p(12) && !p(3) && !p(13) && !p(2) && !p(0) && !p(4) && !p(5) {
            if raw.failure_kind == 1 { 2 } else { 3 }
        }
        else if !p(14) && !p(0) && p(5) && p(9) && !p(2) && !p(3) && !p(4)
            && !failure { 4 }
        else if !p(14) && !p(0) && !p(5) && !failure && p(4) && p(15)
            && p(16) && p(17) && p(18) { 5 }
        else { 0 };
    valid(reason)
}
fn goldens() -> [RawRequest; 6] {
    [
        request(0, 0),
        request(3, 0),
        request(960, 1), // ack,abort,same error,initial presentation
        request(960, 2),
        request(544, 0), // cancel,initial presentation
        request(491536, 0), // decline,choice,bound/admitted/found matches
    ]
}
fn assert_refused(raw: RawRequest) {
    let refusal = RawResult { abi_version: 1, status: 1, reason: 0 };
    assert_eq!(decide(raw), refusal, "raw={raw:?}");
    assert_eq!(result_is_valid(raw, refusal), 0, "raw={raw:?}");
    for reason in 0..=5 {
        assert_eq!(result_is_valid(raw, valid(reason)), 0, "raw={raw:?}, reason={reason}");
    }
}

#[test]
fn wire_layout_offsets_and_closed_literal_values_are_fixed() {
    use core::mem::{align_of, offset_of, size_of};
    assert_eq!((size_of::<RawRequest>(), align_of::<RawRequest>()), (12, 4));
    assert_eq!((size_of::<RawResult>(), align_of::<RawResult>()), (12, 4));
    assert_eq!([offset_of!(RawRequest, abi_version), offset_of!(RawRequest, flags),
        offset_of!(RawRequest, failure_kind)], [0, 4, 8]);
    assert_eq!([offset_of!(RawResult, abi_version), offset_of!(RawResult, status),
        offset_of!(RawResult, reason)], [0, 4, 8]);
    assert_eq!([ABI_VERSION, STATUS_VALID, STATUS_INVALID], [1, 0, 1]);
    assert_eq!([FAILURE_ABSENT, FAILURE_FEED_FETCH, FAILURE_FEED_PARSE_OR_SIGNATURE], [0, 1, 2]);
    assert_eq!([REASON_NONE, REASON_NO_UPDATE, REASON_FEED_FETCH_FAILURE,
        REASON_FEED_PARSE_FAILURE, REASON_CANCELLED_CHECK, REASON_DECLINED_CANDIDATE],
        [0, 1, 2, 3, 4, 5]);
    assert_eq!([NO_UPDATE_PRESENT, NO_UPDATE_IS_FINISHED, BOUND_CANDIDATE_PRESENT,
        ADMITTED_ITEM_PRESENT, DECLINE_PRESENT, CANCELLED_INITIAL_CHECK,
        FAILURE_ACKNOWLEDGED, FAILURE_ABORT_OBSERVED, FAILURE_IS_FINISHED,
        INITIAL_PRESENTATION_PRESENT, CANDIDATE_ADMISSION_ATTEMPTED,
        CANDIDATE_PRESENTATION_OBSERVED, CANDIDATE_BINDING_IN_PROGRESS,
        FOUND_ITEM_PRESENT, FINISHED_ERROR_PRESENT, DECLINE_SDK_CHOICE_OBSERVED,
        BOUND_MATCHES_DECLINE, ADMITTED_MATCHES_DECLINE, FOUND_MATCHES_DECLINE],
        core::array::from_fn::<u32, 19, _>(|bit| 1 << bit));
    assert_eq!(KNOWN_FLAGS, 524287);
}

#[test]
fn all_1572864_valid_carriers_match_the_literal_original_branch_priority() {
    let mut count = 0u32;
    for failure_kind in 0..=2 {
        for flags in 0..524288 {
            let raw = request(flags, failure_kind);
            let expected = original_swift(raw);
            let actual = decide(raw);
            assert_eq!(actual, expected, "raw={raw:?}");
            assert_eq!(result_is_valid(raw, actual), 1, "raw={raw:?}");
            count += 1;
        }
    }
    assert_eq!(count, 1_572_864);
}

#[test]
fn each_native_reason_path_and_its_blocking_presence_facts_are_exact() {
    for (raw, reason) in goldens().into_iter().zip(0..=5) {
        assert_eq!(decide(raw), valid(reason), "raw={raw:?}");
        for bit in 0..19 {
            let changed = request(raw.flags ^ (1 << bit), raw.failure_kind);
            assert_eq!(decide(changed), original_swift(changed), "changed={changed:?}");
        }
    }
    // A different original path's presence cannot be treated as clean absence.
    assert_eq!(decide(request(3, 1)), valid(0)); // failure blocks no-update
    assert_eq!(decide(request(3 | 16, 0)), valid(0)); // decline blocks no-update
    assert_eq!(decide(request(544 | 16, 0)), valid(0)); // decline blocks cancel
    assert_eq!(decide(request(491536 | 32, 0)), valid(0)); // cancellation blocks decline
    assert_eq!(decide(request(960 | 1, 1)), valid(0)); // no-update blocks feed error
}

#[test]
fn original_found_item_and_candidate_attempt_omissions_are_not_strengthened() {
    let omitted = [1 << 10, 1 << 11, 1 << 12, 1 << 13];
    for base in [goldens()[1], goldens()[4], goldens()[5]] {
        for bits in 0..16 {
            let extra = omitted.into_iter().enumerate().fold(0, |f, (bit, value)| {
                f | if bits & (1 << bit) != 0 { value } else { 0 }
            });
            assert_eq!(decide(request(base.flags | extra, 0)), decide(base),
                "base={base:?}, extra={extra}");
        }
    }
    // The feed-failure path DOES exclude all four, and the original already did.
    for raw in [goldens()[2], goldens()[3]] {
        for extra in omitted {
            assert_eq!(decide(request(raw.flags | extra, raw.failure_kind)), valid(0));
        }
    }
}

#[test]
fn unsupported_abi_failure_kind_and_every_unknown_flag_fail_closed() {
    for base in goldens() {
        for abi_version in [0, 2, u32::MAX] {
            assert_refused(RawRequest { abi_version, ..base });
        }
        for failure_kind in [3, 4, u32::MAX] {
            assert_refused(RawRequest { failure_kind, ..base });
        }
        for bit in 19..32 {
            assert_refused(RawRequest { flags: base.flags | (1 << bit), ..base });
        }
        assert_refused(RawRequest { flags: u32::MAX, ..base });
    }
}

#[test]
fn every_copied_result_field_requires_whole_request_correlation() {
    for raw in goldens() {
        let expected = original_swift(raw);
        for value in [0, 1, 2, 3, 4, 5, 6, u32::MAX] {
            for result in [
                RawResult { abi_version: value, ..expected },
                RawResult { status: value, ..expected },
                RawResult { reason: value, ..expected },
            ] {
                assert_eq!(result_is_valid(raw, result), u32::from(result == expected),
                    "raw={raw:?}, result={result:?}");
            }
        }
    }
}

#[test]
fn coherent_cross_request_reasons_cannot_mint_a_different_completion() {
    for raw in goldens() {
        for other in goldens() {
            let result = original_swift(other);
            assert_eq!(result_is_valid(raw, result), u32::from(result == original_swift(raw)),
                "raw={raw:?}, other={other:?}");
        }
        for reason in 0..=6 {
            assert_eq!(result_is_valid(raw, valid(reason)),
                u32::from(valid(reason) == original_swift(raw)));
        }
    }
}

#[test]
fn copied_inputs_and_results_have_no_retained_owner_or_effect_state() {
    for raw in goldens() {
        let before = raw;
        let result = decide(raw);
        assert_eq!(raw, before);
        assert_eq!(decide(raw), result);
        assert_eq!(result_is_valid(raw, result), 1);
    }
}
