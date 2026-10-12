//! Source-only ordinary tests. No compiler or runtime execution is claimed.
//! Parity oracle transcribes the two current production Swift expressions.
#![forbid(unsafe_code)]

use beluga_core::update_admission::*;

fn request(flags: u32) -> RawRequest { RawRequest { abi_version: 1, flags } }
fn valid(permits: u32, progress: u32, can_check: u32, kind: u32) -> RawResult {
    RawResult { abi_version: 1, status: 0, permits_update: permits,
        is_in_progress: progress, can_check, status_kind: kind }
}
fn original_swift_projection(flags: u32) -> RawResult {
    // Literal bit positions, not production flags/decoder helpers.
    let interactive = flags & 1 != 0;
    let media = flags & 2 != 0;
    let pairing = flags & 4 != 0;
    let shares = flags & 8 != 0;
    let teardown = flags & 16 != 0;
    let release = flags & 32 != 0;
    let task = flags & 64 != 0;
    let readiness = flags & 128 != 0;
    let failed = flags & 256 != 0;
    let admission = interactive && teardown && !media && !pairing && !shares;
    let progress = release && (task || readiness || failed);
    let can_check = release && !progress && admission;
    let kind = match (release, failed, task || readiness, admission) {
        (false, _, _, _) => 0,
        (true, true, _, _) => 1,
        (true, false, true, _) => 2,
        (true, false, false, true) => 3,
        (true, false, false, false) => 4,
    };
    valid(u32::from(admission), u32::from(progress), u32::from(can_check), kind)
}
fn assert_refused(raw: RawRequest) {
    let refusal = RawResult { abi_version: 1, status: 1, permits_update: 0,
        is_in_progress: 1, can_check: 0, status_kind: 1 };
    assert_eq!(decide(raw), refusal);
    assert_eq!(result_is_valid(raw, refusal), 0,
        "an exact refusal shape is not accepted as an ordinary false vote");
    assert_eq!(result_is_valid(raw, valid(1, 0, 1, 3)), 0,
        "an invalid carrier cannot gain permission from a plausible ready result");
}

#[test]
fn wire_sizes_offsets_and_literal_constants_are_fixed() {
    use core::mem::{align_of, offset_of, size_of};
    assert_eq!((size_of::<RawRequest>(), align_of::<RawRequest>()), (8, 4));
    assert_eq!((size_of::<RawResult>(), align_of::<RawResult>()), (24, 4));
    assert_eq!([offset_of!(RawRequest, abi_version), offset_of!(RawRequest, flags)], [0, 4]);
    assert_eq!([offset_of!(RawResult, abi_version), offset_of!(RawResult, status),
        offset_of!(RawResult, permits_update), offset_of!(RawResult, is_in_progress),
        offset_of!(RawResult, can_check), offset_of!(RawResult, status_kind)], [0, 4, 8, 12, 16, 20]);
    assert_eq!([ABI_VERSION, STATUS_VALID, STATUS_INVALID], [1, 0, 1]);
    assert_eq!([INTERACTIVE, ACTIVE_MEDIA, PENDING_PAIRING, AUDIO_SHARES,
        TEARDOWN_COMPLETE, RELEASE, TASK_PRESENT, NEEDS_READINESS, FAILED,
        KNOWN_FLAGS], [1, 2, 4, 8, 16, 32, 64, 128, 256, 511]);
    assert_eq!([KIND_DEVELOPMENT, KIND_RECOVERY, KIND_OWNED, KIND_READY,
        KIND_UNAVAILABLE], [0, 1, 2, 3, 4]);
}

#[test]
fn all_512_production_boolean_combinations_match_original_swift() {
    for flags in 0..512 {
        let raw = request(flags);
        let actual = decide(raw);
        assert_eq!(actual, original_swift_projection(flags), "flags={flags}");
        assert_eq!(result_is_valid(raw, actual), 1, "flags={flags}");
    }
}

#[test]
fn each_owned_activity_and_missing_teardown_or_interactivity_denies_admission() {
    assert_eq!(decide(request(49)), valid(1, 0, 1, 3));
    // Remove interactive, add media/pairing/shares, remove complete teardown.
    for flags in [48, 51, 53, 57, 33] {
        assert_eq!(decide(request(flags)), valid(0, 0, 0, 4), "flags={flags}");
    }
    assert_eq!(decide(request(0)), valid(0, 0, 0, 0));
}

#[test]
fn release_progress_and_menu_precedence_are_independent_of_admission() {
    // Quiet admission remains true, even when release/check presentation is blocked.
    for (flags, expected) in [
        (17, valid(1, 0, 0, 0)),
        (49, valid(1, 0, 1, 3)),
        (113, valid(1, 1, 0, 2)),
        (177, valid(1, 1, 0, 2)),
        (305, valid(1, 1, 0, 1)),
        (241, valid(1, 1, 0, 2)),
        (497, valid(1, 1, 0, 1)),
        (465, valid(1, 0, 0, 0)),
        (32, valid(0, 0, 0, 4)),
        (352, valid(0, 1, 0, 1)),
    ] { assert_eq!(decide(request(flags)), expected, "flags={flags}"); }
}

#[test]
fn malformed_abi_and_each_unknown_flag_fail_closed() {
    for abi in [0, 2, u32::MAX] {
        for flags in [0, 17, 49, 511] {
            assert_refused(RawRequest { abi_version: abi, flags });
        }
    }
    for shift in 9..32 {
        for base in [0, 17, 49, 511] {
            assert_refused(request(base | (1 << shift)));
        }
    }
    assert_refused(request(u32::MAX));
    assert_refused(RawRequest { abi_version: u32::MAX, flags: u32::MAX });
}

#[test]
fn every_result_field_corruption_is_rejected_for_every_valid_request() {
    for flags in 0..512 {
        let raw = request(flags);
        let expected = decide(raw);
        for replacement in [0, 1, 2, 3, 4, 5, u32::MAX] {
            let corruptions = [
                RawResult { abi_version: replacement, ..expected },
                RawResult { status: replacement, ..expected },
                RawResult { permits_update: replacement, ..expected },
                RawResult { is_in_progress: replacement, ..expected },
                RawResult { can_check: replacement, ..expected },
                RawResult { status_kind: replacement, ..expected },
            ];
            for candidate in corruptions {
                assert_eq!(result_is_valid(raw, candidate), u32::from(candidate == expected),
                    "flags={flags}, candidate={candidate:?}");
            }
        }
    }
}

#[test]
fn coherent_but_wrong_permission_progress_and_presentation_are_rejected() {
    // Closed 0/1 fields and valid enum values do not prove request correlation.
    for flags in [0, 17, 49, 51, 53, 57, 33, 113, 177, 305, 497] {
        let raw = request(flags);
        let expected = decide(raw);
        for candidate in [valid(1, 0, 1, 3), valid(0, 1, 0, 1),
            valid(0, 1, 0, 2), valid(0, 0, 0, 4), valid(1, 0, 0, 0)] {
            assert_eq!(result_is_valid(raw, candidate), u32::from(candidate == expected),
                "flags={flags}, candidate={candidate:?}");
        }
    }
}

#[test]
fn denial_for_one_activity_cannot_certify_a_ready_result_from_another_request() {
    let ready = decide(request(49));
    for flags in [48, 51, 53, 57, 33, 113, 177, 305] {
        assert_eq!(result_is_valid(request(flags), ready), 0, "flags={flags}");
    }
    assert_eq!(result_is_valid(request(49), ready), 1);
}
