// PRIVATE DRAFT ONLY: not copied into the authoritative crate and never executed.
// Frozen from ScreenVideoOutputPolicy.swift's three admission policies and the
// first 15 existing native tests. Encoder/output arithmetic is outside this file.
use beluga_core::display_admission::{
    self, RawBooleanDecision, RawDisplayFacts, RawKindDecision, RawKindFacts,
    RawSourceDecision, RawSourceFacts, RawStabilityFacts,
};
use beluga_core::{
    beluga_core_display_requirement_admission as actual_requirement,
    beluga_core_source_dimension_kind as actual_kind,
    beluga_core_source_dimensions as actual_source,
    beluga_core_source_dimensions_stable as actual_stability,
};
use std::mem::{align_of, offset_of, size_of};

fn display() -> RawDisplayFacts {
    RawDisplayFacts {
        abi_version: 1, reserved: 0,
        required_vendor_id: 0x6f73, required_product_id: 0x1718,
        required_serial_number: 1, requires_sole_main_display: 1,
        display_id: 42, observed_vendor_id: 0x6f73,
        observed_product_id: 0x1718, observed_serial_number: 1,
        is_online: 1, is_active: 1, main_display_id: 42,
        sole_online_display_id: 42, online_display_count: 1,
    }
}

fn kind(vendor: u32, product: u32) -> RawKindFacts {
    RawKindFacts { abi_version: 1, reserved: 0, vendor_id: vendor, product_id: product }
}

fn owned() -> RawSourceFacts {
    RawSourceFacts {
        abi_version: 1, reserved: 0, vendor_id: 0x6f73, product_id: 0x1718,
        logical_width: 540, logical_height: 1_170,
        core_graphics_logical_width: 540, core_graphics_logical_height: 1_170,
        core_graphics_pixel_width: 1_080, core_graphics_pixel_height: 2_340,
        filter_content_width: 540.0, filter_content_height: 1_170.0,
        point_pixel_scale: 2.0,
    }
}

fn stability(before: (i64, i64), after: (i64, i64)) -> RawStabilityFacts {
    RawStabilityFacts { abi_version: 1, reserved: 0,
        before_width: before.0, before_height: before.1,
        after_width: after.0, after_height: after.1 }
}

// Independent transcription of the original native policies. These functions
// never call a production decoder, helper, constant, pure function or C export.
// Native online IDs remain an actual vector here, rather than repeating the
// production bridge's count/singleton projection as the expected policy.
fn original_requirement(raw: RawDisplayFacts, online_ids: &[u32]) -> bool {
    if !(raw.is_online == 1 && raw.is_active == 1
        && raw.observed_vendor_id == raw.required_vendor_id
        && raw.observed_product_id == raw.required_product_id
        && raw.observed_serial_number == raw.required_serial_number) {
        return false;
    }
    if raw.requires_sole_main_display == 0 { return true; }
    raw.main_display_id == raw.display_id && online_ids == [raw.display_id]
}

fn original_kind(vendor: u32, product: u32) -> u32 {
    if vendor != 0x6f73 { return 0; }
    match product { 0x1717 | 0x1718 => 1, _ => 0 }
}

fn original_source(raw: RawSourceFacts) -> Option<(i64, i64)> {
    if original_kind(raw.vendor_id, raw.product_id) != 1 {
        return Some((raw.logical_width, raw.logical_height));
    }
    let native_guard = raw.logical_width >= 2 && raw.logical_height >= 2
        && raw.logical_width <= 32_768 && raw.logical_height <= 32_768
        && raw.filter_content_width.is_finite()
        && raw.filter_content_height.is_finite()
        && raw.point_pixel_scale.is_finite()
        && raw.point_pixel_scale >= 1.0 && raw.point_pixel_scale <= 4.0
        && raw.core_graphics_logical_width >= 2
        && raw.core_graphics_logical_height >= 2
        && raw.core_graphics_pixel_width >= 2
        && raw.core_graphics_pixel_height >= 2
        && raw.core_graphics_pixel_width <= 32_768
        && raw.core_graphics_pixel_height <= 32_768
        && (raw.logical_width, raw.logical_height)
            == (raw.core_graphics_logical_width, raw.core_graphics_logical_height)
        && (raw.filter_content_width - raw.logical_width as f64).abs() <= 0.5
        && (raw.filter_content_height - raw.logical_height as f64).abs() <= 0.5;
    if native_guard {
        Some((raw.core_graphics_pixel_width, raw.core_graphics_pixel_height))
    } else { None }
}

fn original_stability(raw: RawStabilityFacts) -> bool {
    (raw.before_width, raw.before_height) == (raw.after_width, raw.after_height)
}

// The actual C-callable production export is always called before either
// oracle or the pure function. Literal expectations are not computed by the
// production implementation; the frozen native oracle is a second assertion.
fn assert_requirement(raw: RawDisplayFacts, online_ids: &[u32], literal: bool) {
    let actual = actual_requirement(raw);
    let expected = RawBooleanDecision { abi_version: 1, status: 1,
        value: u32::from(literal), reserved: 0 };
    assert_eq!(actual, expected, "actual C requirement result for {raw:?}");
    assert_eq!(original_requirement(raw, online_ids), literal, "frozen native requirement");
    assert_eq!(display_admission::requirement_admission(raw), expected, "pure requirement result");
}

fn assert_kind(raw: RawKindFacts, literal: u32) {
    let actual = actual_kind(raw);
    let expected = RawKindDecision { abi_version: 1, status: 1, kind: literal, reserved: 0 };
    assert_eq!(actual, expected, "actual C kind result for {raw:?}");
    assert_eq!(original_kind(raw.vendor_id, raw.product_id), literal, "frozen native kind");
    assert_eq!(display_admission::dimension_kind(raw), expected, "pure kind result");
}

fn assert_source(raw: RawSourceFacts, literal: Option<(i64, i64)>, literal_kind: u32) {
    let actual = actual_source(raw);
    let (presence, width, height) = match literal {
        Some((width, height)) => (1, width, height), None => (0, 0, 0),
    };
    let expected = RawSourceDecision { abi_version: 1, status: 1,
        kind: literal_kind, has_dimensions: presence, width, height };
    assert_eq!(actual, expected, "actual C source result for {raw:?}");
    assert_eq!(original_source(raw), literal, "frozen native source");
    assert_eq!(display_admission::source_dimensions(raw), expected, "pure source result");
}

fn assert_stability(raw: RawStabilityFacts, literal: bool) {
    let actual = actual_stability(raw);
    let expected = RawBooleanDecision { abi_version: 1, status: 1,
        value: u32::from(literal), reserved: 0 };
    assert_eq!(actual, expected, "actual C stability result for {raw:?}");
    assert_eq!(original_stability(raw), literal, "frozen native stability");
    assert_eq!(display_admission::dimensions_stable(raw), expected, "pure stability result");
}

fn assert_invalid_requirement(raw: RawDisplayFacts) {
    let actual = actual_requirement(raw);
    let expected = RawBooleanDecision { abi_version: 1, status: 0, value: 0, reserved: 0 };
    assert_eq!(actual, expected, "invalid C requirement for {raw:?}");
    assert_eq!(display_admission::requirement_admission(raw), expected);
}

fn assert_invalid_kind(raw: RawKindFacts) {
    let actual = actual_kind(raw);
    let expected = RawKindDecision { abi_version: 1, status: 0, kind: 0, reserved: 0 };
    assert_eq!(actual, expected, "invalid C kind for {raw:?}");
    assert_eq!(display_admission::dimension_kind(raw), expected);
}

fn assert_invalid_source(raw: RawSourceFacts) {
    let actual = actual_source(raw);
    let expected = RawSourceDecision { abi_version: 1, status: 0, kind: 0,
        has_dimensions: 0, width: 0, height: 0 };
    assert_eq!(actual, expected, "invalid C source for {raw:?}");
    assert_eq!(display_admission::source_dimensions(raw), expected);
}

fn assert_invalid_stability(raw: RawStabilityFacts) {
    let actual = actual_stability(raw);
    let expected = RawBooleanDecision { abi_version: 1, status: 0, value: 0, reserved: 0 };
    assert_eq!(actual, expected, "invalid C stability for {raw:?}");
    assert_eq!(display_admission::dimensions_stable(raw), expected);
}

fn source_bits(raw: RawSourceFacts) -> [u64; 13] {
    [u64::from(raw.abi_version), u64::from(raw.reserved),
        u64::from(raw.vendor_id), u64::from(raw.product_id),
        raw.logical_width as u64, raw.logical_height as u64,
        raw.core_graphics_logical_width as u64, raw.core_graphics_logical_height as u64,
        raw.core_graphics_pixel_width as u64, raw.core_graphics_pixel_height as u64,
        raw.filter_content_width.to_bits(), raw.filter_content_height.to_bits(),
        raw.point_pixel_scale.to_bits()]
}

#[test]
fn display_admission_all_seven_layouts_and_every_field_offset_are_literal() {
    assert_eq!((size_of::<RawDisplayFacts>(), align_of::<RawDisplayFacts>()), (64, 8));
    assert_eq!([offset_of!(RawDisplayFacts, abi_version), offset_of!(RawDisplayFacts, reserved),
        offset_of!(RawDisplayFacts, required_vendor_id), offset_of!(RawDisplayFacts, required_product_id),
        offset_of!(RawDisplayFacts, required_serial_number), offset_of!(RawDisplayFacts, requires_sole_main_display),
        offset_of!(RawDisplayFacts, display_id), offset_of!(RawDisplayFacts, observed_vendor_id),
        offset_of!(RawDisplayFacts, observed_product_id), offset_of!(RawDisplayFacts, observed_serial_number),
        offset_of!(RawDisplayFacts, is_online), offset_of!(RawDisplayFacts, is_active),
        offset_of!(RawDisplayFacts, main_display_id), offset_of!(RawDisplayFacts, sole_online_display_id),
        offset_of!(RawDisplayFacts, online_display_count)], [0,4,8,12,16,20,24,28,32,36,40,44,48,52,56]);
    assert_eq!((size_of::<RawBooleanDecision>(), align_of::<RawBooleanDecision>()), (16, 4));
    assert_eq!([offset_of!(RawBooleanDecision, abi_version), offset_of!(RawBooleanDecision, status),
        offset_of!(RawBooleanDecision, value), offset_of!(RawBooleanDecision, reserved)], [0,4,8,12]);
    assert_eq!((size_of::<RawKindFacts>(), align_of::<RawKindFacts>()), (16, 4));
    assert_eq!([offset_of!(RawKindFacts, abi_version), offset_of!(RawKindFacts, reserved),
        offset_of!(RawKindFacts, vendor_id), offset_of!(RawKindFacts, product_id)], [0,4,8,12]);
    assert_eq!((size_of::<RawKindDecision>(), align_of::<RawKindDecision>()), (16, 4));
    assert_eq!([offset_of!(RawKindDecision, abi_version), offset_of!(RawKindDecision, status),
        offset_of!(RawKindDecision, kind), offset_of!(RawKindDecision, reserved)], [0,4,8,12]);
    assert_eq!((size_of::<RawSourceFacts>(), align_of::<RawSourceFacts>()), (88, 8));
    assert_eq!([offset_of!(RawSourceFacts, abi_version), offset_of!(RawSourceFacts, reserved),
        offset_of!(RawSourceFacts, vendor_id), offset_of!(RawSourceFacts, product_id),
        offset_of!(RawSourceFacts, logical_width), offset_of!(RawSourceFacts, logical_height),
        offset_of!(RawSourceFacts, core_graphics_logical_width), offset_of!(RawSourceFacts, core_graphics_logical_height),
        offset_of!(RawSourceFacts, core_graphics_pixel_width), offset_of!(RawSourceFacts, core_graphics_pixel_height),
        offset_of!(RawSourceFacts, filter_content_width), offset_of!(RawSourceFacts, filter_content_height),
        offset_of!(RawSourceFacts, point_pixel_scale)], [0,4,8,12,16,24,32,40,48,56,64,72,80]);
    assert_eq!((size_of::<RawSourceDecision>(), align_of::<RawSourceDecision>()), (32, 8));
    assert_eq!([offset_of!(RawSourceDecision, abi_version), offset_of!(RawSourceDecision, status),
        offset_of!(RawSourceDecision, kind), offset_of!(RawSourceDecision, has_dimensions),
        offset_of!(RawSourceDecision, width), offset_of!(RawSourceDecision, height)], [0,4,8,12,16,24]);
    assert_eq!((size_of::<RawStabilityFacts>(), align_of::<RawStabilityFacts>()), (40, 8));
    assert_eq!([offset_of!(RawStabilityFacts, abi_version), offset_of!(RawStabilityFacts, reserved),
        offset_of!(RawStabilityFacts, before_width), offset_of!(RawStabilityFacts, before_height),
        offset_of!(RawStabilityFacts, after_width), offset_of!(RawStabilityFacts, after_height)], [0,4,8,16,24,32]);
    assert_requirement(display(), &[42], true);
    assert_kind(kind(0x6f73, 0x1718), 1);
    assert_source(owned(), Some((1_080, 2_340)), 1);
    assert_stability(stability((1_206, 2_622), (1_206, 2_622)), true);
}

#[test]
fn display_requirement_each_original_identity_and_liveness_guard_is_independent() {
    assert_requirement(display(), &[42], true);
    let mut input = display(); input.is_online = 0;
    assert_requirement(input, &[42], false);
    input = display(); input.is_active = 0;
    assert_requirement(input, &[42], false);
    input = display(); input.observed_vendor_id = 0xffff;
    assert_requirement(input, &[42], false);
    input = display(); input.observed_product_id = 0x1717;
    assert_requirement(input, &[42], false);
    input = display(); input.observed_serial_number = 2;
    assert_requirement(input, &[42], false);
}

#[test]
fn display_requirement_sole_topology_is_exact_singleton_including_duplicates() {
    // Each original native vector is paired with its literal ABI projection.
    let cases: [(&[u32], u64, u32, bool); 6] = [
        (&[], 0, 0, false), (&[42], 1, 42, true), (&[99], 1, 99, false),
        (&[42, 99], 2, 42, false), (&[99, 42], 2, 99, false),
        (&[42, 42], 2, 42, false),
    ];
    for &(ids, count, singleton, literal) in &cases {
        let input = RawDisplayFacts { online_display_count: count,
            sole_online_display_id: singleton, ..display() };
        assert_requirement(input, ids, literal);
    }
    // Huge counts cannot be singletons, including a count whose low 32 bits are
    // one. Assert these literals without allocating fictitious native vectors.
    for count in [0x0000_0001_0000_0001, u64::MAX] {
        let input = RawDisplayFacts { online_display_count: count, ..display() };
        let actual = actual_requirement(input);
        let expected = RawBooleanDecision { abi_version: 1, status: 1, value: 0, reserved: 0 };
        assert_eq!(actual, expected);
        assert_eq!(display_admission::requirement_admission(input), expected);
    }
}

#[test]
fn display_requirement_sole_main_mismatch_alone_refuses() {
    assert_requirement(RawDisplayFacts { main_display_id: 99, ..display() }, &[42], false);
}

#[test]
fn display_requirement_optional_topology_ignores_main_count_and_singleton() {
    for count in [0, 1, 2, u64::MAX] {
        let input = RawDisplayFacts { requires_sole_main_display: 0,
            main_display_id: 99, online_display_count: count,
            sole_online_display_id: u32::MAX, ..display() };
        assert_requirement(input, &[], true);
    }
    // Optional topology never bypasses exact native identity/liveness.
    assert_requirement(RawDisplayFacts { requires_sole_main_display: 0,
        observed_serial_number: 2, ..display() }, &[], false);
}

#[test]
fn display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum() {
    for value in [0, u32::MAX] {
        let input = RawDisplayFacts {
            required_vendor_id: value, required_product_id: value,
            required_serial_number: value, observed_vendor_id: value,
            observed_product_id: value, observed_serial_number: value,
            display_id: value, main_display_id: value,
            sole_online_display_id: value, ..display()
        };
        assert_requirement(input, &[value], true);
        assert_requirement(RawDisplayFacts { observed_serial_number: value ^ 1, ..input }, &[value], false);
        assert_requirement(RawDisplayFacts { observed_vendor_id: value ^ 0x0001_0000, ..input }, &[value], false);
        assert_requirement(RawDisplayFacts { observed_product_id: value ^ 0x0001_0000, ..input }, &[value], false);
        assert_requirement(RawDisplayFacts { observed_serial_number: value ^ 0x0001_0000, ..input }, &[value], false);
        assert_requirement(RawDisplayFacts { main_display_id: value ^ 0x0001_0000, ..input }, &[value], false);
        assert_requirement(RawDisplayFacts { sole_online_display_id: value ^ 0x0001_0000, ..input },
            &[value ^ 0x0001_0000], false);
    }
}

#[test]
fn source_kind_frozen_literal_table_selects_only_the_two_owned_products() {
    const CASES: [(u32, u32, u32); 12] = [
        (0x610, 0xa0e1, 0), (0x6f73, 0x1717, 1), (0x6f73, 0x1718, 1),
        (0xffff, 0x1717, 0), (0xffff, 0x1718, 0), (0x6f73, 0x1719, 0),
        (0x6f72, 0x1717, 0), (0x6f74, 0x1718, 0),
        (0, 0, 0), (u32::MAX, u32::MAX, 0),
        (0x6f73, 0, 0), (0x6f73, u32::MAX, 0),
    ];
    for (vendor, product, literal) in CASES { assert_kind(kind(vendor, product), literal); }
}

#[test]
fn source_kind_cartesian_boundaries_match_independent_frozen_native() {
    for vendor in [0, 0x610, 0x6f72, 0x6f73, 0x6f74, 0xffff, u32::MAX] {
        for product in [0, 0x1716, 0x1717, 0x1718, 0x1719, 0xa0e1, u32::MAX] {
            let input = kind(vendor, product);
            let actual = actual_kind(input);
            let literal = original_kind(vendor, product);
            let expected = RawKindDecision { abi_version: 1, status: 1, kind: literal, reserved: 0 };
            assert_eq!(actual, expected);
            assert_eq!(display_admission::dimension_kind(input), expected);
        }
    }
}

#[test]
fn source_dimensions_all_twenty_nine_supported_native_modes_return_exact_pixels() {
    // Literal source/framebuffer entries frozen from the existing native test.
    // Its encoder expectation column remains in the native output-math tests.
    const MODES: [(i64, i64, f64, i64, i64); 29] = [
        (540,960,1.0,540,960), (603,1_312,1.0,603,1_312), (640,480,1.0,640,480),
        (640,1_392,1.0,640,1_392), (720,1_280,1.0,720,1_280), (750,1_334,1.0,750,1_334),
        (400,300,2.0,800,600), (800,600,1.0,800,600), (400,870,2.0,800,1_740),
        (800,1_740,1.0,800,1_740), (405,720,2.0,810,1_440), (810,1_440,1.0,810,1_440),
        (414,896,2.0,828,1_792), (828,1_792,1.0,828,1_792), (450,800,2.0,900,1_600),
        (900,1_600,1.0,900,1_600), (512,384,2.0,1_024,768), (1_024,768,1.0,1_024,768),
        (512,1_113,2.0,1_024,2_226), (1_024,2_226,1.0,1_024,2_226),
        (540,960,2.0,1_080,1_920), (1_080,1_920,1.0,1_080,1_920),
        (540,1_170,2.0,1_080,2_340), (1_080,2_340,1.0,1_080,2_340),
        (603,1_311,2.0,1_206,2_622), (1_206,2_622,1.0,1_206,2_622),
        (640,480,2.0,1_280,960), (672,504,2.0,1_344,1_008), (800,600,2.0,1_600,1_200),
    ];
    for product in [0x1717, 0x1718] {
        for (width, height, scale, pixels_w, pixels_h) in MODES {
            let raw = RawSourceFacts { product_id: product,
                logical_width: width, logical_height: height,
                core_graphics_logical_width: width, core_graphics_logical_height: height,
                core_graphics_pixel_width: pixels_w, core_graphics_pixel_height: pixels_h,
                filter_content_width: width as f64, filter_content_height: height as f64,
                point_pixel_scale: scale, ..owned() };
            assert_source(raw, Some((pixels_w, pixels_h)), 1);
        }
    }
}

#[test]
fn ordinary_source_preserves_entire_signed_domain_before_any_metadata_guard() {
    let dimensions = [i64::MIN, -1, 0, 1, 2, 32_768, 32_769, i64::MAX];
    let ignored = [f64::from_bits(0x7ff8_1234_5678_9abc), f64::NEG_INFINITY,
        f64::INFINITY, -0.0, 0.0, 4.1];
    for (vendor, product) in [(0x610,0xa0e1), (0xffff,0x1717), (0x6f73,0x1719), (0,0), (u32::MAX,u32::MAX)] {
        for width in dimensions {
            for height in dimensions {
                for metadata in ignored {
                    let raw = RawSourceFacts { vendor_id: vendor, product_id: product,
                        logical_width: width, logical_height: height,
                        core_graphics_logical_width: i64::MIN, core_graphics_logical_height: i64::MAX,
                        core_graphics_pixel_width: 0, core_graphics_pixel_height: -1,
                        filter_content_width: metadata, filter_content_height: metadata,
                        point_pixel_scale: metadata, ..owned() };
                    assert_source(raw, Some((width, height)), 0);
                }
            }
        }
    }
}

#[test]
fn owned_source_logical_width_and_height_minimum_are_two() {
    let at = RawSourceFacts { logical_width: 2, logical_height: 2,
        core_graphics_logical_width: 2, core_graphics_logical_height: 2,
        filter_content_width: 2.0, filter_content_height: 2.0, ..owned() };
    assert_source(at, Some((1_080,2_340)), 1);
    for value in [i64::MIN, -1, 0, 1] {
        assert_source(RawSourceFacts { logical_width: value,
            core_graphics_logical_width: value, filter_content_width: value as f64, ..at }, None, 1);
        assert_source(RawSourceFacts { logical_height: value,
            core_graphics_logical_height: value, filter_content_height: value as f64, ..at }, None, 1);
    }
}

#[test]
fn owned_source_logical_width_and_height_maximum_are_32768() {
    let at = RawSourceFacts { logical_width: 32_768, logical_height: 32_768,
        core_graphics_logical_width: 32_768, core_graphics_logical_height: 32_768,
        filter_content_width: 32_768.0, filter_content_height: 32_768.0, ..owned() };
    assert_source(at, Some((1_080,2_340)), 1);
    for value in [32_769, i64::MAX] {
        assert_source(RawSourceFacts { logical_width: value,
            core_graphics_logical_width: value, filter_content_width: value as f64, ..at }, None, 1);
        assert_source(RawSourceFacts { logical_height: value,
            core_graphics_logical_height: value, filter_content_height: value as f64, ..at }, None, 1);
    }
}

#[test]
fn owned_source_pixel_width_and_height_minimum_are_two() {
    assert_source(RawSourceFacts { core_graphics_pixel_width: 2,
        core_graphics_pixel_height: 2, ..owned() }, Some((2,2)), 1);
    for value in [i64::MIN, -1, 0, 1] {
        assert_source(RawSourceFacts { core_graphics_pixel_width: value, ..owned() }, None, 1);
        assert_source(RawSourceFacts { core_graphics_pixel_height: value, ..owned() }, None, 1);
    }
}

#[test]
fn owned_source_pixel_width_and_height_maximum_are_32768() {
    assert_source(RawSourceFacts { core_graphics_pixel_width: 32_768,
        core_graphics_pixel_height: 32_768, ..owned() }, Some((32_768,32_768)), 1);
    for value in [32_769, i64::MAX] {
        assert_source(RawSourceFacts { core_graphics_pixel_width: value, ..owned() }, None, 1);
        assert_source(RawSourceFacts { core_graphics_pixel_height: value, ..owned() }, None, 1);
    }
}

#[test]
fn owned_source_core_graphics_logical_minimum_literals_and_exact_snapshot_equality() {
    assert_source(RawSourceFacts { logical_width: 2, logical_height: 2,
        core_graphics_logical_width: 2, core_graphics_logical_height: 2,
        filter_content_width: 2.0, filter_content_height: 2.0, ..owned() }, Some((1_080,2_340)), 1);
    for value in [i64::MIN, 0, 1, 2, 539, 541, 32_769, i64::MAX] {
        assert_source(RawSourceFacts { core_graphics_logical_width: value, ..owned() }, None, 1);
    }
    for value in [i64::MIN, 0, 1, 2, 1_169, 1_171, 32_769, i64::MAX] {
        assert_source(RawSourceFacts { core_graphics_logical_height: value, ..owned() }, None, 1);
    }
}

#[test]
fn owned_source_core_graphics_width_snapshot_mismatch_alone_refuses() {
    assert_source(RawSourceFacts { core_graphics_logical_width: 541, ..owned() }, None, 1);
}

#[test]
fn owned_source_core_graphics_height_snapshot_mismatch_alone_refuses() {
    assert_source(RawSourceFacts { core_graphics_logical_height: 1_171, ..owned() }, None, 1);
}

#[test]
fn owned_source_filter_width_must_be_finite() {
    for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY,
        f64::from_bits(0x7ff8_1234_5678_9abc), f64::from_bits(0x7ff0_0000_0000_0001)] {
        assert_source(RawSourceFacts { filter_content_width: value, ..owned() }, None, 1);
    }
}

#[test]
fn owned_source_filter_height_must_be_finite() {
    for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY,
        f64::from_bits(0xfff8_1234_5678_9abc), f64::from_bits(0x7ff0_0000_0000_0001)] {
        assert_source(RawSourceFacts { filter_content_height: value, ..owned() }, None, 1);
    }
}

#[test]
fn owned_source_scale_includes_one_and_four_and_refuses_actual_double_neighbors() {
    let cases = [(f64::from_bits(1.0_f64.to_bits()-1), false), (1.0, true),
        (f64::from_bits(1.0_f64.to_bits()+1), true),
        (f64::from_bits(4.0_f64.to_bits()-1), true), (4.0, true),
        (f64::from_bits(4.0_f64.to_bits()+1), false),
        (f64::NAN, false), (f64::INFINITY, false), (f64::NEG_INFINITY, false),
        (-0.0, false), (0.0, false), (-1.0, false), (4.1, false)];
    for (value, present) in cases {
        assert_source(RawSourceFacts { point_pixel_scale: value, ..owned() },
            if present { Some((1_080,2_340)) } else { None }, 1);
    }
}

#[test]
fn owned_source_filter_width_half_pixel_boundary_is_inclusive_both_directions() {
    let cases = [(f64::from_bits(539.5_f64.to_bits()-1), false), (539.5, true),
        (f64::from_bits(539.5_f64.to_bits()+1), true),
        (f64::from_bits(540.5_f64.to_bits()-1), true), (540.5, true),
        (f64::from_bits(540.5_f64.to_bits()+1), false),
        (539.0, false), (541.0, false), (0.0, false), (-0.0, false)];
    for (value, present) in cases {
        assert_source(RawSourceFacts { filter_content_width: value, ..owned() },
            if present { Some((1_080,2_340)) } else { None }, 1);
    }
}

#[test]
fn owned_source_filter_height_half_pixel_boundary_is_inclusive_both_directions() {
    let cases = [(f64::from_bits(1_169.5_f64.to_bits()-1), false), (1_169.5, true),
        (f64::from_bits(1_169.5_f64.to_bits()+1), true),
        (f64::from_bits(1_170.5_f64.to_bits()-1), true), (1_170.5, true),
        (f64::from_bits(1_170.5_f64.to_bits()+1), false),
        (1_169.0, false), (1_171.0, false), (0.0, false), (-0.0, false)];
    for (value, present) in cases {
        assert_source(RawSourceFacts { filter_content_height: value, ..owned() },
            if present { Some((1_080,2_340)) } else { None }, 1);
    }
}

#[test]
fn owned_source_returns_current_framebuffer_independent_of_scale_ratio_or_rounding() {
    for scale in [1.0, 2.0, 4.0] {
        // Odd and unrelated framebuffer values are admitted: the policy neither
        // infers pixels from the scale nor applies encoder chroma rounding.
        assert_source(RawSourceFacts { point_pixel_scale: scale,
            core_graphics_pixel_width: 603, core_graphics_pixel_height: 1_311, ..owned() }, Some((603,1_311)), 1);
    }
    assert_source(RawSourceFacts { point_pixel_scale: 1.0, ..owned() }, Some((1_080,2_340)), 1);
}

#[test]
fn owned_source_literal_startup_geometry_trace_covers_stale_scale_and_refusals() {
    // Literal observations in native startup order. There is no stateful Rust
    // startup protocol here; the native caller owns when it takes each snapshot.
    let trace: [(RawSourceFacts, Option<(i64,i64)>); 6] = [
        (owned(), Some((1_080,2_340))),
        (RawSourceFacts { point_pixel_scale: 1.0, ..owned() }, Some((1_080,2_340))),
        (RawSourceFacts { filter_content_width: 539.5, filter_content_height: 1_170.5, ..owned() }, Some((1_080,2_340))),
        (RawSourceFacts { core_graphics_logical_width: 541, ..owned() }, None),
        (RawSourceFacts { filter_content_height: 0.0, ..owned() }, None),
        (RawSourceFacts { core_graphics_pixel_width: 1_206,
            core_graphics_pixel_height: 2_622, ..owned() }, Some((1_206,2_622))),
    ];
    for (input, literal) in trace { assert_source(input, literal, 1); }
}

#[test]
fn owned_source_cartesian_integer_and_float_boundaries_match_frozen_native() {
    for logical in [i64::MIN, 1, 2, 540, 32_768, 32_769, i64::MAX] {
        for pixel in [i64::MIN, 1, 2, 1_080, 32_768, 32_769, i64::MAX] {
            for scale in [f64::NAN, f64::NEG_INFINITY, 0.0, 1.0, 2.0, 4.0, 4.1, f64::INFINITY] {
                for delta in [-1.0, -0.5, 0.0, 0.5, 1.0] {
                    let input = RawSourceFacts { logical_width: logical, logical_height: logical,
                        core_graphics_logical_width: logical, core_graphics_logical_height: logical,
                        core_graphics_pixel_width: pixel, core_graphics_pixel_height: pixel,
                        filter_content_width: logical as f64 + delta,
                        filter_content_height: logical as f64 + delta,
                        point_pixel_scale: scale, ..owned() };
                    let actual = actual_source(input);
                    let expected_native = original_source(input);
                    let (has_dimensions, width, height) = match expected_native {
                        Some((w,h)) => (1,w,h), None => (0,0,0),
                    };
                    let expected = RawSourceDecision { abi_version: 1, status: 1,
                        kind: 1, has_dimensions, width, height };
                    assert_eq!(actual, expected);
                    assert_eq!(display_admission::source_dimensions(input), expected);
                }
            }
        }
    }
}

#[test]
fn source_stability_requires_both_dimensions_exactly_equal_without_sanity_limits() {
    let domain = [i64::MIN, -1, 0, 1, 2, 1_206, 2_622, 32_768, i64::MAX];
    for width in domain {
        for height in domain {
            assert_stability(stability((width,height), (width,height)), true);
            assert_stability(stability((width,height), (width ^ 1,height)), false);
            assert_stability(stability((width,height), (width,height ^ 1)), false);
        }
    }
    assert_stability(stability((1_206,2_622), (1_080,2_340)), false);
}

#[test]
fn source_stability_literal_startup_trace_refuses_single_axis_drift_and_recovers() {
    const TRACE: [((i64,i64),(i64,i64),bool); 6] = [
        ((1_206,2_622),(1_206,2_622),true), ((1_206,2_622),(1_205,2_622),false),
        ((1_206,2_622),(1_206,2_621),false), ((1_206,2_622),(1_080,2_340),false),
        ((1_080,2_340),(1_080,2_340),true), ((i64::MIN,i64::MAX),(i64::MIN,i64::MAX),true),
    ];
    for (before,after,literal) in TRACE { assert_stability(stability(before,after), literal); }
}

#[test]
fn display_requirement_unknown_abi_is_invalid_independent_of_policy_result() {
    for abi in [0, 2, u32::MAX] {
        assert_invalid_requirement(RawDisplayFacts { abi_version: abi, ..display() });
        assert_invalid_requirement(RawDisplayFacts { abi_version: abi, is_online: 0, ..display() });
    }
}

#[test]
fn display_requirement_reserved_is_invalid_independent_of_policy_result() {
    for reserved in [1, u32::MAX] {
        assert_invalid_requirement(RawDisplayFacts { reserved, ..display() });
        assert_invalid_requirement(RawDisplayFacts { reserved, is_online: 0, ..display() });
    }
}

#[test]
fn display_requirement_each_raw_boolean_domain_is_closed_even_if_ignored() {
    for invalid in [2, 3, u32::MAX] {
        assert_invalid_requirement(RawDisplayFacts { requires_sole_main_display: invalid, ..display() });
        assert_invalid_requirement(RawDisplayFacts { is_online: invalid, ..display() });
        assert_invalid_requirement(RawDisplayFacts { is_active: invalid, ..display() });
        assert_invalid_requirement(RawDisplayFacts { requires_sole_main_display: 0,
            is_online: 0, is_active: invalid, ..display() });
        assert_invalid_requirement(RawDisplayFacts { requires_sole_main_display: invalid,
            is_online: 0, ..display() });
    }
}

#[test]
fn source_kind_unknown_abi_and_reserved_are_independent_invalid_inputs() {
    for product in [0x1717, 0x1718, 0x1719] {
        for abi in [0, 2, u32::MAX] {
            assert_invalid_kind(RawKindFacts { abi_version: abi, ..kind(0x6f73,product) });
        }
        for reserved in [1, u32::MAX] {
            assert_invalid_kind(RawKindFacts { reserved, ..kind(0x6f73,product) });
        }
    }
}

#[test]
fn source_dimensions_invalid_bridge_is_distinct_from_legitimate_owned_absence() {
    assert_source(RawSourceFacts { filter_content_width: f64::NAN, ..owned() }, None, 1);
    for vendor in [0x610, 0x6f73] {
        for abi in [0, 2, u32::MAX] {
            assert_invalid_source(RawSourceFacts { abi_version: abi, vendor_id: vendor, ..owned() });
        }
        for reserved in [1, u32::MAX] {
            assert_invalid_source(RawSourceFacts { reserved, vendor_id: vendor, ..owned() });
        }
    }
}

#[test]
fn source_stability_unknown_abi_and_reserved_are_independent_invalid_inputs() {
    for after in [(1_206,2_622), (1_080,2_340)] {
        let valid = stability((1_206,2_622),after);
        for abi in [0, 2, u32::MAX] {
            assert_invalid_stability(RawStabilityFacts { abi_version: abi, ..valid });
        }
        for reserved in [1, u32::MAX] {
            assert_invalid_stability(RawStabilityFacts { reserved, ..valid });
        }
    }
}

#[test]
fn display_admission_all_copied_inputs_remain_exact_including_nan_payload_bits() {
    let requirement = display(); let saved_requirement = requirement;
    let _ = actual_requirement(requirement);
    let _ = actual_requirement(RawDisplayFacts { reserved: 1, ..requirement });
    assert_eq!(requirement, saved_requirement);
    let raw_kind = kind(0x6f73,0x1717); let saved_kind = raw_kind;
    let _ = actual_kind(raw_kind);
    let _ = actual_kind(RawKindFacts { reserved: 1, ..raw_kind });
    assert_eq!(raw_kind, saved_kind);
    let raw_stability = stability((i64::MIN,i64::MAX),(i64::MIN,i64::MAX));
    let saved_stability = raw_stability;
    let _ = actual_stability(raw_stability);
    let _ = actual_stability(RawStabilityFacts { reserved: 1, ..raw_stability });
    assert_eq!(raw_stability, saved_stability);
    for vendor in [0x610,0x6f73] {
        for (width_bits,height_bits,scale_bits) in [
            (0x7ff8_1234_5678_9abc,0xfff8_8765_4321_abcd,0x7ff0_0000_0000_0001),
            (0x8000_0000_0000_0000,0,0x7ff0_0000_0000_0000),
            (540.0_f64.to_bits(),1_170.0_f64.to_bits(),2.0_f64.to_bits()),
        ] {
            let input = RawSourceFacts { vendor_id: vendor,
                filter_content_width: f64::from_bits(width_bits),
                filter_content_height: f64::from_bits(height_bits),
                point_pixel_scale: f64::from_bits(scale_bits), ..owned() };
            let saved = source_bits(input);
            let actual = actual_source(input);
            assert_eq!(source_bits(input), saved);
            if vendor == 0x610 {
                assert_eq!(actual, RawSourceDecision { abi_version: 1, status: 1,
                    kind: 0, has_dimensions: 1, width: 540, height: 1_170 });
            }
            let malformed = RawSourceFacts { reserved: 1, ..input };
            let saved_malformed = source_bits(malformed);
            let actual_invalid = actual_source(malformed);
            assert_eq!(actual_invalid, RawSourceDecision { abi_version: 1, status: 0,
                kind: 0, has_dimensions: 0, width: 0, height: 0 });
            assert_eq!(source_bits(malformed), saved_malformed);
        }
    }
}

// PRIVATE ADDITIVE DRAFT ONLY. Append after the frozen 34-test inventory.
// Reuses its imports and independent native helpers without changing them.
#[test]
fn source_kind_and_dimensions_high_bit_identity_aliases_remain_ordinary() {
    // Every expected kind is independently literal 0. These values alias owned
    // identities only if a producer incorrectly narrows UInt32 payloads to u16.
    const ALIASES: [(u32, u32); 6] = [
        (0x0001_6f73, 0x0000_1717), (0x0001_6f73, 0x0000_1718),
        (0x0000_6f73, 0x0001_1717), (0x0000_6f73, 0x0001_1718),
        (0x0001_6f73, 0x0001_1717), (0x0001_6f73, 0x0001_1718),
    ];
    const SIGNED_DIMENSIONS: [(i64, i64); 5] = [
        (i64::MIN, i64::MAX), (i64::MAX, i64::MIN), (-1, 0), (0, 1), (1, 2),
    ];
    for (vendor, product) in ALIASES {
        let kind_input = RawKindFacts { abi_version: 1, reserved: 0,
            vendor_id: vendor, product_id: product };
        let actual_kind_output = actual_kind(kind_input);
        let literal_kind_output = RawKindDecision {
            abi_version: 1, status: 1, kind: 0, reserved: 0,
        };
        assert_eq!(actual_kind_output, literal_kind_output,
            "actual C kind must keep complete identity {vendor:#x}/{product:#x}");
        assert_eq!(original_kind(vendor, product), 0, "independent frozen native kind");
        assert_eq!(display_admission::dimension_kind(kind_input), literal_kind_output);

        for (width, height) in SIGNED_DIMENSIONS {
            let source_input = RawSourceFacts {
                abi_version: 1, reserved: 0, vendor_id: vendor, product_id: product,
                logical_width: width, logical_height: height,
                core_graphics_logical_width: i64::MAX,
                core_graphics_logical_height: i64::MIN,
                core_graphics_pixel_width: -1, core_graphics_pixel_height: 0,
                filter_content_width: f64::from_bits(0x7ff8_1234_5678_9abc),
                filter_content_height: f64::NEG_INFINITY,
                point_pixel_scale: f64::from_bits(0xfff8_8765_4321_abcd),
            };
            let original_bits = source_bits(source_input);
            let actual_source_output = actual_source(source_input);
            let literal_source_output = RawSourceDecision {
                abi_version: 1, status: 1, kind: 0, has_dimensions: 1, width, height,
            };
            assert_eq!(actual_source_output, literal_source_output,
                "actual C source must return ordinary signed dimensions {vendor:#x}/{product:#x}");
            assert_eq!(source_bits(source_input), original_bits, "copied NaN payload bits");
            assert_eq!(original_source(source_input), Some((width, height)),
                "independent frozen native source");
            assert_eq!(display_admission::source_dimensions(source_input), literal_source_output);
        }
    }
}
