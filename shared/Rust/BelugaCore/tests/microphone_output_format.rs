// Independent original-policy parity and complete copied-result refusal coverage.
use beluga_core::microphone_output_format::{self as policy, RawFacts, RawObservation, RawResult};

fn valid() -> RawFacts {
    RawFacts { abi_version: 1, stream_sample_rate_bits: 48_000.0_f64.to_bits(),
        stream_format_id: 0x6c70_636d, stream_format_flags: 12,
        stream_bytes_per_packet: 2, stream_frames_per_packet: 1,
        stream_bytes_per_frame: 2, stream_channels_per_frame: 1,
        stream_bits_per_channel: 16, device_sample_rate_bits: 48_000.0_f64.to_bits(),
        device_channel_count: 1, ..RawFacts::default() }
}

// Independent ordered table transcribes the original Swift guards (preimage
// a978c83a59acc3b5e1ec340c6b3681afe417197dbc2ffd75e6e59282b5c4b1f0).
// It does not call the new classifier, its constructors, or its policy constants.
fn original_swift_oracle(f: RawFacts) -> RawResult {
    let checks = [
        (f.stream_description_status == 0, 1, f.stream_description_status, 0, 0),
        (f.device_sample_rate_status == 0, 2, f.device_sample_rate_status, 0, 0),
        (f.device_channel_count_status == 0, 3, f.device_channel_count_status, 0, 0),
        (f.converter_error_read_status == 0, 4, f.converter_error_read_status, 0, 0),
        (f64::from_bits(f.stream_sample_rate_bits) == 48_000.0, 5, 0, 0, f.stream_sample_rate_bits),
        (f.stream_format_id == u32::from_be_bytes(*b"lpcm"), 6, 0, f.stream_format_id, 0),
        (f.stream_format_flags == (4 | 8), 7, 0, f.stream_format_flags, 0),
        (f.stream_bytes_per_packet == 2, 8, 0, f.stream_bytes_per_packet, 0),
        (f.stream_frames_per_packet == 1, 9, 0, f.stream_frames_per_packet, 0),
        (f.stream_bytes_per_frame == 2, 10, 0, f.stream_bytes_per_frame, 0),
        (f.stream_channels_per_frame == 1, 11, 0, f.stream_channels_per_frame, 0),
        (f.stream_bits_per_channel == 16, 12, 0, f.stream_bits_per_channel, 0),
        (f.stream_reserved == 0, 13, 0, f.stream_reserved, 0),
        (f64::from_bits(f.device_sample_rate_bits) == 48_000.0, 14, 0, 0, f.device_sample_rate_bits),
        (f.device_channel_count == 1, 15, 0, f.device_channel_count, 0),
        (f.converter_error == 0, 16, 0, f.converter_error, 0),
    ];
    if let Some((_, reason, status, word, bits)) = checks.into_iter().find(|row| !row.0) {
        return RawResult { abi_version: 1, status: 1, accepted: 0, reason,
            actual_core_audio_status: status, actual_u32: word, actual_rate_bits: bits,
            observation: RawObservation::default(), wire_reserved: 0 };
    }
    RawResult { abi_version: 1, status: 1, accepted: 1, reason: 0,
        actual_core_audio_status: 0, actual_u32: 0, actual_rate_bits: 0,
        observation: RawObservation {
            sample_rate_bits: f.stream_sample_rate_bits,
            format_id: f.stream_format_id, format_flags: f.stream_format_flags,
            bytes_per_packet: f.stream_bytes_per_packet, frames_per_packet: f.stream_frames_per_packet,
            bytes_per_frame: f.stream_bytes_per_frame, channels_per_frame: f.stream_channels_per_frame,
            bits_per_channel: f.stream_bits_per_channel, stream_reserved: f.stream_reserved,
            device_sample_rate_bits: f.device_sample_rate_bits,
            device_channel_count: f.device_channel_count, converter_error: f.converter_error,
        }, wire_reserved: 0 }
}

fn check(input: RawFacts) -> RawResult {
    assert_eq!((input.abi_version, input.wire_reserved), (1, 0));
    let expected = original_swift_oracle(input);
    assert_eq!(policy::decide(input), expected);
    assert_eq!(policy::result_is_valid(input, expected), 1);
    expected
}

fn break_guard(mut f: RawFacts, reason: u32, raw: u64) -> RawFacts {
    match reason {
        1 => f.stream_description_status = raw as u32 as i32,
        2 => f.device_sample_rate_status = raw as u32 as i32,
        3 => f.device_channel_count_status = raw as u32 as i32,
        4 => f.converter_error_read_status = raw as u32 as i32,
        5 => f.stream_sample_rate_bits = raw,
        6 => f.stream_format_id = raw as u32,
        7 => f.stream_format_flags = raw as u32,
        8 => f.stream_bytes_per_packet = raw as u32,
        9 => f.stream_frames_per_packet = raw as u32,
        10 => f.stream_bytes_per_frame = raw as u32,
        11 => f.stream_channels_per_frame = raw as u32,
        12 => f.stream_bits_per_channel = raw as u32,
        13 => f.stream_reserved = raw as u32,
        14 => f.device_sample_rate_bits = raw,
        15 => f.device_channel_count = raw as u32,
        16 => f.converter_error = raw as u32,
        _ => panic!("unknown guard"),
    }
    f
}

fn bad_value(reason: u32) -> u64 {
    match reason { 5 | 14 => 44_100.0_f64.to_bits(), _ => u32::MAX.into() }
}

#[test]
fn output_format_literal_contract_preserves_signed_and_full_width_fields() {
    assert_eq!((std::mem::size_of::<RawFacts>(), std::mem::align_of::<RawFacts>()), (80, 8));
    assert_eq!((std::mem::size_of::<RawObservation>(), std::mem::align_of::<RawObservation>()), (56, 8));
    assert_eq!((std::mem::size_of::<RawResult>(), std::mem::align_of::<RawResult>()), (96, 8));
    assert_eq!([std::mem::offset_of!(RawFacts, stream_description_status),
        std::mem::offset_of!(RawFacts, converter_error_read_status),
        std::mem::offset_of!(RawFacts, stream_sample_rate_bits),
        std::mem::offset_of!(RawFacts, stream_reserved),
        std::mem::offset_of!(RawFacts, device_sample_rate_bits),
        std::mem::offset_of!(RawFacts, converter_error)], [8, 20, 24, 60, 64, 76]);
    assert_eq!((policy::LINEAR_PCM, policy::SIGNED_INTEGER_PACKED), (0x6c70_636d, 12));
    assert_eq!(policy::REQUIRED_SAMPLE_RATE.to_bits(), 0x40e7_7000_0000_0000);
}

#[test]
fn output_format_acceptance_copies_all_twelve_observation_fields() {
    let input = valid();
    let result = check(input);
    assert_eq!((result.status, result.accepted, result.reason), (1, 1, 0));
    assert_eq!(result.observation, original_swift_oracle(input).observation);
}

#[test]
fn output_format_each_known_rejection_is_a_valid_projection() {
    for reason in 1..=16 {
        let result = check(break_guard(valid(), reason, bad_value(reason)));
        assert_eq!((result.status, result.accepted, result.reason), (1, 0, reason));
        assert_eq!(result.observation, RawObservation::default());
    }
}

#[test]
fn output_format_every_simultaneous_error_pair_preserves_first_guard() {
    for earlier in 1..=16 {
        for later in (earlier + 1)..=16 {
            let input = break_guard(break_guard(valid(), later, bad_value(later)), earlier, bad_value(earlier));
            assert_eq!(check(input).reason, earlier, "{earlier} before {later}");
        }
        let mut all_later_wrong = valid();
        for reason in earlier..=16 {
            all_later_wrong = break_guard(all_later_wrong, reason, bad_value(reason));
        }
        assert_eq!(check(all_later_wrong).reason, earlier);
    }
}

#[test]
fn output_format_four_signed_statuses_preserve_negative_and_extreme_values() {
    for reason in 1..=4 {
        for status in [i32::MIN, i32::MIN + 1, -50, -1, 1, i32::MAX] {
            let result = check(break_guard(valid(), reason, status as u32 as u64));
            assert_eq!(result.reason, reason);
            assert_eq!(result.actual_core_audio_status, status);
            assert_eq!((result.actual_u32, result.actual_rate_bits), (0, 0));
        }
    }
}

#[test]
fn output_format_integer_fields_are_exact_not_masks_ranges_or_truncated_values() {
    for reason in [6, 7, 8, 9, 10, 11, 12, 13, 15, 16] {
        for word in [0, 1, 2, 3, 4, 8, 12, 16, 0x0001_0000, 0x8000_0000, u32::MAX] {
            let input = break_guard(valid(), reason, word.into());
            let result = check(input);
            if result.accepted == 0 {
                assert_eq!((result.reason, result.actual_u32), (reason, word));
            }
        }
    }
    for bit in 0..32 {
        let word = 12 ^ (1_u32 << bit);
        assert_eq!(check(break_guard(valid(), 7, word.into())).actual_u32, word);
    }
}

#[test]
fn output_format_rates_use_numeric_equality_but_rejections_keep_original_bits() {
    let required = 48_000.0_f64.to_bits();
    let rate_bits = [required, required - 1, required + 1, 0, 1, 1_u64 << 63,
        44_100.0_f64.to_bits(), (-48_000.0_f64).to_bits(),
        f64::MIN_POSITIVE.to_bits(), f64::MAX.to_bits(), f64::MIN.to_bits(),
        f64::INFINITY.to_bits(), f64::NEG_INFINITY.to_bits(),
        0x7ff8_0000_0000_0001, 0x7ff0_0000_0000_0001,
        0xfff8_1234_5678_9abc, 0xffff_ffff_ffff_ffff];
    for reason in [5, 14] {
        for bits in rate_bits {
            let result = check(break_guard(valid(), reason, bits));
            if bits == required { assert_eq!(result.accepted, 1); }
            else { assert_eq!((result.reason, result.actual_rate_bits), (reason, bits)); }
        }
    }
}

#[test]
fn output_format_malformed_wire_is_not_an_ordinary_policy_rejection() {
    for underlying in [valid(), break_guard(valid(), 1, u32::MAX.into()),
        break_guard(valid(), 5, 0x7ff8_0000_0000_0001)] {
        for input in [RawFacts { abi_version: 0, ..underlying },
            RawFacts { abi_version: 2, ..underlying }, RawFacts { abi_version: u32::MAX, ..underlying },
            RawFacts { wire_reserved: 1, ..underlying }, RawFacts { wire_reserved: u32::MAX, ..underlying }] {
            let result = policy::decide(input);
            assert_eq!(result, RawResult { abi_version: 1, ..RawResult::default() });
            assert_eq!(policy::result_is_valid(input, result), 0);
            assert_eq!(policy::result_is_valid(input, original_swift_oracle(underlying)), 0);
        }
    }
}

fn every_field_corrupted(r: RawResult) -> Vec<RawResult> {
    macro_rules! field {
        ($name:ident) => {{ let mut changed = r; changed.$name ^= 1; changed }};
    }
    macro_rules! observed {
        ($name:ident) => {{ let mut changed = r; changed.observation.$name ^= 1; changed }};
    }
    vec![field!(abi_version), field!(status), field!(accepted), field!(reason),
        field!(actual_core_audio_status), field!(actual_u32), field!(actual_rate_bits),
        observed!(sample_rate_bits), observed!(format_id), observed!(format_flags),
        observed!(bytes_per_packet), observed!(frames_per_packet), observed!(bytes_per_frame),
        observed!(channels_per_frame), observed!(bits_per_channel), observed!(stream_reserved),
        observed!(device_sample_rate_bits), observed!(device_channel_count),
        observed!(converter_error), field!(wire_reserved)]
}

#[test]
fn output_format_authoritative_verifier_rejects_corruption_of_every_result_field() {
    let mut inputs = vec![valid()];
    inputs.extend((1..=16).map(|reason| break_guard(valid(), reason, bad_value(reason))));
    inputs.push(break_guard(valid(), 5, 0x7ff8_0000_0000_0001));
    for input in inputs {
        let actual = check(input);
        let corruptions = every_field_corrupted(actual);
        assert_eq!(corruptions.len(), 20);
        for corrupt in corruptions {
            assert_ne!(corrupt, actual);
            assert_eq!(policy::result_is_valid(input, corrupt), 0);
        }
    }
}

#[test]
fn output_format_verifier_rejects_coherent_wrong_success_rejection_and_precedence() {
    let mut inputs = vec![valid()];
    inputs.extend((1..=16).map(|reason| break_guard(valid(), reason, bad_value(reason))));
    let results: Vec<_> = inputs.iter().copied().map(original_swift_oracle).collect();
    for input in inputs {
        let expected = check(input);
        for wrong in &results {
            assert_eq!(policy::result_is_valid(input, *wrong), u32::from(*wrong == expected));
        }
    }
    let both_bad = break_guard(break_guard(valid(), 5, bad_value(5)), 14, bad_value(14));
    let coherent_later_failure = original_swift_oracle(break_guard(valid(), 14, bad_value(14)));
    assert_eq!(check(both_bad).reason, 5);
    assert_eq!(policy::result_is_valid(both_bad, coherent_later_failure), 0);
}

#[test]
fn output_format_raw_nan_result_equality_is_reflexive_and_payload_exact() {
    let input = break_guard(valid(), 5, 0x7ff8_0000_0000_0001);
    let nan_rejection = check(input);
    assert_eq!(nan_rejection, nan_rejection);
    assert_eq!(policy::result_is_valid(input, nan_rejection), 1);
    let other_nan_rejection = check(break_guard(valid(), 5, 0x7ff8_0000_0000_0002));
    assert_ne!(nan_rejection, other_nan_rejection);
    assert_eq!(policy::result_is_valid(input, other_nan_rejection), 0);
}

#[test]
fn output_format_actual_c_exports_correlate_success_rejection_and_refusal() {
    use beluga_core::{beluga_core_microphone_output_format_decide as produce,
        beluga_core_microphone_output_format_result_is_valid as verify};
    let mut inputs = vec![valid()];
    inputs.extend((1..=16).map(|reason| break_guard(valid(), reason, bad_value(reason))));
    inputs.push(break_guard(valid(), 5, 0x7ff8_0000_0000_0001));
    for input in inputs {
        let expected = original_swift_oracle(input);
        assert_eq!(produce(input), expected);
        assert_eq!(verify(input, expected), 1);
        for changed in every_field_corrupted(expected) {
            assert_eq!(verify(input, changed), 0);
        }
    }
    for input in [RawFacts { abi_version: 2, ..valid() },
        RawFacts { wire_reserved: 1, ..valid() }] {
        let refused = produce(input);
        assert_eq!(refused, RawResult { abi_version: 1, ..RawResult::default() });
        assert_eq!(verify(input, refused), 0);
        assert_eq!(verify(input, original_swift_oracle(valid())), 0);
    }
}
