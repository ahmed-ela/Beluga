//! PRIVATE authored actual-export-first tests; uncompiled and unexecuted.
use beluga_core::{beluga_core_output_dimensions, output_dimensions::{RawOutputFacts, RawOutputDecision}};
use std::mem::{align_of, offset_of, size_of};

fn input(width: i64, height: i64, cap: i64) -> RawOutputFacts {
    RawOutputFacts { abi_version: 1, reserved: 0, source_width: width,
        source_height: height, maximum_width: cap }
}
fn fields(raw: RawOutputDecision) -> (u32, u32, u32, u32, i64, i64, u64) {
    (raw.abi_version, raw.status, raw.decision, raw.reserved,
        raw.width, raw.height, raw.rounded_height_bits)
}
fn assert_dimensions(facts: RawOutputFacts, width: i64, height: i64, rounded: f64) {
    let actual = beluga_core_output_dimensions(facts);
    assert_eq!(fields(actual), (1, 1, 1, 0, width, height, rounded.to_bits()));
}

#[test]
fn output_abi_has_exact_two_layouts_and_twelve_offsets() {
    let actual = beluga_core_output_dimensions(input(4, 7, 2));
    assert_eq!(fields(actual), (1, 1, 1, 0, 2, 4, 4.0_f64.to_bits()));
    assert_eq!((size_of::<RawOutputFacts>(), align_of::<RawOutputFacts>()), (32, 8));
    assert_eq!((size_of::<RawOutputDecision>(), align_of::<RawOutputDecision>()), (40, 8));
    assert_eq!([offset_of!(RawOutputFacts, abi_version), offset_of!(RawOutputFacts, reserved),
        offset_of!(RawOutputFacts, source_width), offset_of!(RawOutputFacts, source_height),
        offset_of!(RawOutputFacts, maximum_width)], [0, 4, 8, 16, 24]);
    assert_eq!([offset_of!(RawOutputDecision, abi_version), offset_of!(RawOutputDecision, status),
        offset_of!(RawOutputDecision, decision), offset_of!(RawOutputDecision, reserved),
        offset_of!(RawOutputDecision, width), offset_of!(RawOutputDecision, height),
        offset_of!(RawOutputDecision, rounded_height_bits)], [0, 4, 8, 12, 16, 24, 32]);
}

#[test]
fn output_literal_supported_modes_preserve_cap_round_even_and_height_floor() {
    // Independent literal tuples: source W/H, cap, expected W/H, rounded H.
    let cases = [
        (1206, 2622, 1920, 1206, 2622, 2622.0),
        (3840, 2160, 1920, 1920, 1080, 1080.0),
        (1205, 2621, 1920, 1204, 2618, 2619.0),
        (603, 1312, 1920, 602, 1310, 1310.0),
        (7, 11, 5, 4, 6, 6.0),
        (4, 7, 2, 2, 4, 4.0),
        (4, 5, 2, 2, 2, 3.0),
        (100, 99, 20, 20, 20, 20.0),
        (100, 91, 20, 20, 18, 18.0),
        (100, 96, 20, 20, 18, 19.0),
        (100, 11, 2, 2, 2, 0.0),
    ];
    for (sw, sh, cap, width, height, rounded) in cases {
        assert_dimensions(input(sw, sh, cap), width, height, rounded);
    }
}

#[test]
fn output_each_original_signed_guard_refuses_before_arithmetic() {
    for bad in [i64::MIN, -4_294_967_296, -1, 0, 1] {
        for slot in 0..3 {
            let mut raw = input(2, 2, 2);
            match slot { 0 => raw.source_width = bad, 1 => raw.source_height = bad,
                _ => raw.maximum_width = bad }
            let actual = beluga_core_output_dimensions(raw);
            assert_eq!(fields(actual), (1, 1, 0, 0, 0, 0, 0));
        }
    }
}

#[test]
fn output_width_cap_is_a_minimum_without_upscaling() {
    assert_dimensions(input(4, 6, 2), 2, 2, 3.0);
    assert_dimensions(input(4, 6, 4), 4, 6, 6.0);
    assert_dimensions(input(4, 6, 100), 4, 6, 6.0);
}

#[test]
fn output_even_width_is_chosen_before_scaling() {
    assert_dimensions(input(7, 14, 5), 4, 8, 8.0);
    assert_dimensions(input(5, 10, 20), 4, 8, 8.0);
    assert_dimensions(input(3, 9, 3), 2, 6, 6.0);
}

#[test]
fn output_positive_half_ties_round_away_before_even_height() {
    assert_dimensions(input(4, 7, 2), 2, 4, 4.0);
    assert_dimensions(input(4, 5, 2), 2, 2, 3.0);
    assert_dimensions(input(400, 699, 200), 200, 350, 350.0);
    assert_dimensions(input(400, 698, 200), 200, 348, 349.0);
}

#[test]
fn output_non_ties_keep_nearest_not_floor_or_ceil() {
    assert_dimensions(input(100, 99, 20), 20, 20, 20.0);
    assert_dimensions(input(100, 91, 20), 20, 18, 18.0);
    assert_dimensions(input(100, 96, 20), 20, 18, 19.0);
}

#[test]
fn output_height_chroma_adjustment_rounds_down_after_nearest() {
    assert_dimensions(input(2, 3, 2), 2, 2, 3.0);
    assert_dimensions(input(2, 5, 2), 2, 4, 5.0);
    assert_dimensions(input(2, 7, 2), 2, 6, 7.0);
}

#[test]
fn output_height_floor_keeps_two_when_scaled_rounds_to_zero_or_one() {
    assert_dimensions(input(100, 11, 2), 2, 2, 0.0);
    assert_dimensions(input(100, 26, 2), 2, 2, 1.0);
    assert_dimensions(input(i64::MAX, 2, 2), 2, 2, 0.0);
}

#[test]
fn output_float_multiply_then_divide_is_not_integer_ratio() {
    assert_dimensions(input(3840, 2160, 1920), 1920, 1080, 1080.0);
    assert_dimensions(input(5, 9, 4), 4, 6, 7.0);
}

#[test]
fn output_full_signed_projection_does_not_narrow_source_or_cap() {
    assert_dimensions(input(65_538, 6, 2), 2, 2, 0.0);
    assert_dimensions(input(4_294_967_298, 6, 2), 2, 2, 0.0);
    assert_dimensions(input(2, 4_294_967_297, 2), 2, 4_294_967_296, 4_294_967_297.0);
    assert_dimensions(input(8, 16, 65_538), 8, 16, 16.0);
    assert_dimensions(input(8, 16, 4_294_967_298), 8, 16, 16.0);
    assert_dimensions(input(i64::MAX, 2, i64::MAX), i64::MAX - 1, 2, 2.0);
}

#[test]
fn output_original_f64_precision_loss_is_not_replaced_by_exact_rational_or_height_cap() {
    assert_dimensions(input(2, 9_007_199_254_740_993, 2), 2,
        9_007_199_254_740_992, 9_007_199_254_740_992.0);
    assert_dimensions(input(2, 9_007_199_254_740_995, 2), 2,
        9_007_199_254_740_996, 9_007_199_254_740_996.0);
    assert_dimensions(input(2, i64::MAX - 1024, 2), 2,
        9_223_372_036_854_774_784, 9_223_372_036_854_774_784.0);
}

#[test]
fn output_two_to_sixty_three_is_distinct_refusal_not_saturation_or_dimensions() {
    for raw in [input(2, i64::MAX, 2), input(2, i64::MAX - 511, 2),
        input(i64::MAX, i64::MAX, i64::MAX)] {
        let actual = beluga_core_output_dimensions(raw);
        let width = if raw.source_width == 2 { 2 } else { i64::MAX - 1 };
        assert_eq!(fields(actual), (1, 1, 2, 0, width, 0, 0x43e0_0000_0000_0000));
    }
}

#[test]
fn output_adjacent_representable_upper_value_still_returns_dimensions() {
    assert_dimensions(input(2, i64::MAX - 512, 2), 2,
        9_223_372_036_854_774_784, 9_223_372_036_854_774_784.0);
    assert_dimensions(input(2, i64::MAX - 1023, 2), 2,
        9_223_372_036_854_774_784, 9_223_372_036_854_774_784.0);
}

#[test]
fn output_maximum_height_can_remain_representable_after_width_capping() {
    let actual = beluga_core_output_dimensions(input(3, i64::MAX, 2));
    assert_eq!(fields(actual), (1, 1, 1, 0, 2, 6_148_914_691_236_516_864,
        0x43d5_5555_5555_5555));
}

#[test]
fn output_malformed_envelope_is_not_a_legitimate_dimension_error() {
    for bad in [0, 2, 0x8000_0001, u32::MAX] {
        let mut raw = input(2, 2, 2);
        raw.abi_version = bad;
        let actual = beluga_core_output_dimensions(raw);
        assert_eq!(fields(actual), (1, 0, 0, 0, 0, 0, 0));
    }
    for reserved in [1, 2, 0x8000_0000, u32::MAX] {
        let mut raw = input(2, 2, 2);
        raw.reserved = reserved;
        let actual = beluga_core_output_dimensions(raw);
        assert_eq!(fields(actual), (1, 0, 0, 0, 0, 0, 0));
    }
}

#[test]
fn output_copies_have_no_state_or_mutating_input_ownership() {
    let original = input(603, 1312, 1920);
    let copy = original;
    let first = beluga_core_output_dimensions(original);
    let intervening = beluga_core_output_dimensions(input(2, i64::MAX, 2));
    let second = beluga_core_output_dimensions(copy);
    assert_eq!(fields(first), (1, 1, 1, 0, 602, 1310, 1310.0_f64.to_bits()));
    assert_eq!(intervening.decision, 2);
    assert_eq!(second, first);
    assert_eq!(original, copy);
}
