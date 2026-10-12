use beluga_core::{beluga_core_tier_demand_project as project,
    beluga_core_tier_demand_projection_is_valid as verify};
use beluga_core::tier_demand::{RawTierDemandFacts as F, RawTierDemandProjection as P};
use std::mem::{align_of, offset_of, size_of};

const BASELINE: [u32; 8] = [9_344_000, 6_260_480, 3_924_480, 1_962_240,
    747_520, 280_320, 93_440, 32_000];
const BASIS: [u32; 8] = [10_000, 6_700, 4_200, 2_100, 800, 300, 100, 25];
const REQUIRED: [f64; 8] = [12_000_000.0, 8_145_600.0, 5_225_600.0, 2_772_800.0,
    1_254_400.0, 670_400.0, 436_800.0, 360_000.0];
const VIDEO_50M: [u32; 8] = [39_744_000, 26_628_480, 16_692_480, 8_346_240,
    3_179_520, 1_192_320, 397_440, 99_360];
const RTP_50M: [u32; 8] = [16_200_001, 10_996_560, 7_054_560, 3_743_281,
    1_693_440, 905_041, 589_680, 486_001];
const UPGRADE: [f64; 8] = [15_000_000.0, 10_182_000.0, 6_532_000.0, 3_466_000.0,
    1_568_000.0, 838_000.0, 546_000.0, 450_000.0];

fn facts(cap: u32, tier: u32, bandwidth: Option<f64>) -> F {
    F { abi_version: 1, configured_cap: cap, current_tier: tier,
        bandwidth_present: u32::from(bandwidth.is_some()),
        bandwidth_bits: bandwidth.map(f64::to_bits).unwrap_or(0) }
}

fn checked(input: F) -> P {
    let output = project(input);
    assert_eq!((output.abi_version, output.status, output.reserved), (1, 1, 0));
    assert_eq!(verify(input, output), 1);
    output
}

fn rejected(input: F) {
    let expected = P { abi_version: 1, ..P::default() };
    assert_eq!(project(input), expected);
    assert_eq!(verify(input, expected), 0);
}

#[test]
fn tier_demand_layouts_and_all_twenty_three_field_offsets_are_literal() {
    assert_eq!((size_of::<F>(), align_of::<F>()), (24, 8));
    assert_eq!((size_of::<P>(), align_of::<P>()), (80, 8));
    assert_eq!(offset_of!(F, abi_version), 0);
    assert_eq!(offset_of!(F, configured_cap), 4);
    assert_eq!(offset_of!(F, current_tier), 8);
    assert_eq!(offset_of!(F, bandwidth_present), 12);
    assert_eq!(offset_of!(F, bandwidth_bits), 16);
    assert_eq!(offset_of!(P, abi_version), 0);
    assert_eq!(offset_of!(P, status), 4);
    assert_eq!(offset_of!(P, current_tier), 8);
    assert_eq!(offset_of!(P, reserved), 12);
    assert_eq!(offset_of!(P, basis_points), 16);
    assert_eq!(offset_of!(P, baseline_video), 20);
    assert_eq!(offset_of!(P, maximum_tier_video), 24);
    assert_eq!(offset_of!(P, maximum_video), 28);
    assert_eq!(offset_of!(P, maximum_total_rtp), 32);
    assert_eq!(offset_of!(P, minimum_sustainable), 36);
    assert_eq!(offset_of!(P, initial_tier), 40);
    assert_eq!(offset_of!(P, sustainable_tier), 44);
    assert_eq!(offset_of!(P, upgrade_present), 48);
    assert_eq!(offset_of!(P, upgrade_tier), 52);
    assert_eq!(offset_of!(P, direct_threshold_present), 56);
    assert_eq!(offset_of!(P, direct_threshold_minimum), 60);
    assert_eq!(offset_of!(P, required_bitrate_bits), 64);
    assert_eq!(offset_of!(P, direct_threshold_bits), 72);
}

#[test]
fn tier_demand_all_eight_literal_fifty_megabit_profiles_preserve_distinct_fields() {
    for tier in 0..8 {
        let i = tier as usize;
        let direct = if tier == 0 { 0.0 } else { UPGRADE[i - 1] };
        let expected = P { abi_version: 1, status: 1, current_tier: tier, reserved: 0,
            basis_points: BASIS[i], baseline_video: BASELINE[i], maximum_tier_video: 39_744_000,
            maximum_video: VIDEO_50M[i], maximum_total_rtp: RTP_50M[i],
            minimum_sustainable: REQUIRED[i] as u32, initial_tier: 5, sustainable_tier: 7,
            upgrade_present: 0, upgrade_tier: 0,
            direct_threshold_present: u32::from(tier != 0),
            direct_threshold_minimum: direct as u32,
            required_bitrate_bits: REQUIRED[i].to_bits(),
            direct_threshold_bits: if tier == 0 { 0 } else { direct.to_bits() } };
        assert_eq!(checked(facts(50_000_000, tier, None)), expected);
    }
}

#[test]
fn tier_demand_basis_points_and_calibrated_baselines_do_not_follow_configured_ceiling() {
    for cap in [1, 32_000, 360_000, 1_000_000, 12_000_000, 50_000_000, u32::MAX] {
        for tier in 0..8 {
            let output = checked(facts(cap, tier, None));
            assert_eq!((output.basis_points, output.baseline_video),
                (BASIS[tier as usize], BASELINE[tier as usize]));
            assert_eq!(output.required_bitrate_bits, REQUIRED[tier as usize].to_bits());
        }
    }
}

#[test]
fn tier_demand_configured_video_budget_reserve_floor_and_tiny_cap_are_literal() {
    let cases = [(1, 1), (31_999, 31_999), (32_000, 32_000), (32_001, 32_000),
        (319_999, 32_000), (320_000, 32_000), (320_001, 32_000),
        (359_999, 32_000), (360_000, 32_000), (360_001, 32_000),
        (360_002, 32_001), (360_003, 32_002), (360_004, 32_003),
        (12_000_000, 9_344_000), (50_000_000, 39_744_000)];
    for (cap, expected) in cases {
        for tier in 0..8 {
            let output = checked(facts(cap, tier, None));
            assert_eq!(output.maximum_tier_video, expected);
            assert_eq!(output.maximum_video <= expected, true);
        }
    }
}

#[test]
fn tier_demand_full_width_scaling_divides_as_integers_before_conversion() {
    let expected = [3_435_717_836, 2_301_930_950, 1_443_001_491, 721_500_745,
        274_857_426, 103_071_535, 34_357_178, 8_589_294];
    for tier in 0..8 {
        let output = checked(facts(u32::MAX, tier, None));
        assert_eq!(output.maximum_tier_video, 3_435_717_836);
        assert_eq!(output.maximum_video, expected[tier as usize]);
        assert_eq!(output.maximum_total_rtp, RTP_50M[tier as usize]);
    }
}

#[test]
fn tier_demand_binary64_total_rtp_ceiling_artifacts_are_not_algebraically_removed() {
    for tier in 0..8 {
        assert_eq!(checked(facts(50_000_000, tier, None)).maximum_total_rtp,
            RTP_50M[tier as usize]);
    }
    assert_eq!(checked(facts(50_000_000, 0, None)).maximum_total_rtp, 16_200_001);
    assert_eq!(checked(facts(50_000_000, 3, None)).maximum_total_rtp, 3_743_281);
    assert_eq!(checked(facts(50_000_000, 5, None)).maximum_total_rtp, 905_041);
    assert_eq!(checked(facts(50_000_000, 7, None)).maximum_total_rtp, 486_001);
}

#[test]
fn tier_demand_total_rtp_clips_to_configured_cap_before_rounding_up() {
    for cap in [1, 320_000, 360_000, 486_000, 16_200_000, 16_200_001, 50_000_000] {
        for tier in 0..8 {
            assert_eq!(checked(facts(cap, tier, None)).maximum_total_rtp,
                cap.min(RTP_50M[tier as usize]));
        }
    }
}

#[test]
fn tier_demand_required_diagnostic_is_not_capped_by_restrictive_sender_budget() {
    for tier in 0..8 {
        let output = checked(facts(1, tier, None));
        assert_eq!(output.minimum_sustainable, REQUIRED[tier as usize] as u32);
        assert_eq!(output.required_bitrate_bits, REQUIRED[tier as usize].to_bits());
        assert_eq!((output.maximum_tier_video, output.maximum_video, output.maximum_total_rtp), (1, 1, 1));
    }
}

#[test]
fn tier_demand_initial_tier_is_no_better_than_survival_even_at_full_capacity() {
    for cap in [670_400, 1_254_400, 2_772_800, 5_225_600, 8_145_600, 12_000_000,
        50_000_000, u32::MAX] {
        for tier in 0..8 { assert_eq!(checked(facts(cap, tier, None)).initial_tier, 5); }
    }
}

#[test]
fn tier_demand_initial_tier_inclusive_emergency_and_survival_cap_boundaries() {
    for (cap, expected) in [(1, 7), (359_999, 7), (360_000, 7), (436_799, 7),
        (436_800, 6), (436_801, 6), (670_399, 6), (670_400, 5), (670_401, 5)] {
        assert_eq!(checked(facts(cap, 0, None)).initial_tier, expected);
    }
}

#[test]
fn tier_demand_sustainable_admission_is_inclusive_at_every_literal_ieee_neighbor() {
    for tier in 0..8 {
        let threshold = REQUIRED[tier as usize];
        for current in 0..8 {
            let at = checked(facts(50_000_000, current, Some(threshold)));
            let below = checked(facts(50_000_000, current,
                Some(f64::from_bits(threshold.to_bits() - 1))));
            let above = checked(facts(50_000_000, current,
                Some(f64::from_bits(threshold.to_bits() + 1))));
            assert_eq!(at.sustainable_tier, tier);
            assert_eq!(below.sustainable_tier, (tier + 1).min(7));
            assert_eq!(above.sustainable_tier, tier);
        }
    }
}

#[test]
fn tier_demand_sustainable_quality_cannot_bypass_configured_cap_with_huge_bandwidth() {
    for tier in 0..8 {
        let required = REQUIRED[tier as usize] as u32;
        assert_eq!(checked(facts(required, 7, Some(f64::MAX))).sustainable_tier, tier);
        assert_eq!(checked(facts(required - 1, 7, Some(f64::MAX))).sustainable_tier,
            (tier + 1).min(7));
    }
}

#[test]
fn tier_demand_highest_upgrade_can_skip_tiers_but_never_select_current_or_lower_quality() {
    for current in 1..8 {
        let output = checked(facts(50_000_000, current, Some(50_000_000.0)));
        assert_eq!((output.upgrade_present, output.upgrade_tier), (1, 0));
    }
    let full = checked(facts(50_000_000, 0, Some(50_000_000.0)));
    assert_eq!((full.upgrade_present, full.upgrade_tier), (0, 0));
    let same = checked(facts(50_000_000, 3, Some(2_772_800.0)));
    assert_eq!((same.sustainable_tier, same.upgrade_present, same.upgrade_tier), (3, 0, 0));
}

#[test]
fn tier_demand_upgrade_margin_is_independent_and_inclusive_at_ieee_neighbors() {
    for tier in 0..7 {
        let threshold = UPGRADE[tier as usize];
        for (value, expected_present, expected_tier) in [
            (f64::from_bits(threshold.to_bits() - 1), u32::from(tier != 6),
                if tier == 6 { 0 } else { tier + 1 }),
            (threshold, 1, tier),
            (f64::from_bits(threshold.to_bits() + 1), 1, tier)] {
            let output = checked(facts(50_000_000, 7, Some(value)));
            assert_eq!((output.upgrade_present, output.upgrade_tier), (expected_present, expected_tier));
        }
    }
}

#[test]
fn tier_demand_upgrade_threshold_saturates_at_cap_without_admitting_over_cap_demand() {
    let at = checked(facts(12_000_000, 7, Some(12_000_000.0)));
    assert_eq!((at.upgrade_present, at.upgrade_tier), (1, 0));
    let under = checked(facts(11_999_999, 7, Some(11_999_999.0)));
    assert_eq!((under.upgrade_present, under.upgrade_tier), (1, 1));
    let floor = checked(facts(360_000, 7, Some(f64::MAX)));
    assert_eq!((floor.upgrade_present, floor.upgrade_tier), (0, 0));
}

#[test]
fn tier_demand_direct_threshold_is_adjacent_not_the_highest_qualified_upgrade() {
    let output = checked(facts(50_000_000, 7, Some(50_000_000.0)));
    assert_eq!((output.upgrade_present, output.upgrade_tier), (1, 0));
    assert_eq!((output.direct_threshold_present, output.direct_threshold_minimum), (1, 546_000));
    assert_eq!(output.direct_threshold_bits, 546_000.0_f64.to_bits());
}

#[test]
fn tier_demand_direct_threshold_preserves_exact_unrounded_bits_and_ceil_projection() {
    for current in 1..8 {
        let expected = UPGRADE[(current - 1) as usize];
        let output = checked(facts(50_000_000, current, None));
        assert_eq!(output.direct_threshold_present, 1);
        assert_eq!(output.direct_threshold_bits, expected.to_bits());
        assert_eq!(output.direct_threshold_minimum, expected as u32);
    }
    let capped = checked(facts(12_000_000, 1, None));
    assert_eq!((capped.direct_threshold_bits, capped.direct_threshold_minimum),
        (12_000_000.0_f64.to_bits(), 12_000_000));
}

#[test]
fn tier_demand_direct_threshold_absence_is_canonical_at_full_or_over_cap_neighbor() {
    for input in [facts(50_000_000, 0, None), facts(11_999_999, 1, None),
        facts(436_799, 7, None), facts(1, 7, Some(f64::MAX))] {
        let output = checked(input);
        assert_eq!((output.direct_threshold_present, output.direct_threshold_minimum,
            output.direct_threshold_bits), (0, 0, 0));
    }
    assert_eq!(checked(facts(436_800, 7, None)).direct_threshold_bits,
        436_800.0_f64.to_bits());
}

#[test]
fn tier_demand_absent_bandwidth_preserves_profiles_without_minting_quality_evidence() {
    for cap in [1, 360_000, 12_000_000, 50_000_000, u32::MAX] {
        for tier in 0..8 {
            let output = checked(facts(cap, tier, None));
            assert_eq!((output.sustainable_tier, output.upgrade_present, output.upgrade_tier), (7, 0, 0));
            assert_eq!(output.current_tier, tier);
            assert_eq!(output.required_bitrate_bits, REQUIRED[tier as usize].to_bits());
        }
    }
}

#[test]
fn tier_demand_smallest_positive_subnormal_bandwidth_is_valid_but_not_capacity() {
    let input = facts(50_000_000, 7, Some(f64::from_bits(1)));
    let output = checked(input);
    assert_eq!((output.sustainable_tier, output.upgrade_present, output.upgrade_tier), (7, 0, 0));
}

#[test]
fn tier_demand_maximum_finite_bandwidth_is_valid_without_overflow_or_scaling_capacity() {
    for cap in [1, 360_000, 436_800, 12_000_000, u32::MAX] {
        let output = checked(facts(cap, 7, Some(f64::MAX)));
        assert_eq!(output.maximum_total_rtp, cap.min(486_001));
        assert_eq!(output.maximum_video <= output.maximum_tier_video, true);
    }
    assert_eq!(checked(facts(u32::MAX, 7, Some(f64::MAX))).upgrade_tier, 0);
}

#[test]
fn tier_demand_malformed_abi_cap_tier_and_option_tags_reject_canonical_without_authority() {
    let good = facts(50_000_000, 7, None);
    for abi in [0, 2, u32::MAX] { rejected(F { abi_version: abi, ..good }); }
    rejected(F { configured_cap: 0, ..good });
    for tier in [8, 9, 255, u32::MAX] { rejected(F { current_tier: tier, ..good }); }
    for tag in [2, 3, u32::MAX] { rejected(F { bandwidth_present: tag, ..good }); }
}

#[test]
fn tier_demand_absent_bandwidth_rejects_every_noncanonical_payload_including_negative_zero() {
    let good = facts(50_000_000, 7, None);
    for bits in [1, (-0.0_f64).to_bits(), 1.0_f64.to_bits(), f64::INFINITY.to_bits(),
        f64::NAN.to_bits(), u64::MAX] { rejected(F { bandwidth_bits: bits, ..good }); }
}

#[test]
fn tier_demand_present_bandwidth_rejects_zero_negative_nonfinite_and_nan_payloads() {
    for bits in [0, (-0.0_f64).to_bits(), (-1.0_f64).to_bits(), f64::INFINITY.to_bits(),
        f64::NEG_INFINITY.to_bits(), f64::NAN.to_bits(), 0x7ff0_0000_0000_0001,
        0xfff8_0000_0000_0001, u64::MAX] {
        rejected(F { bandwidth_bits: bits, ..facts(50_000_000, 7, Some(1.0)) });
    }
}

fn tampered(mut output: P, word: usize) -> P {
    match word {
        0 => output.abi_version ^= 1,
        1 => output.status ^= 1,
        2 => output.current_tier ^= 1,
        3 => output.reserved ^= 1,
        4 => output.basis_points ^= 1,
        5 => output.baseline_video ^= 1,
        6 => output.maximum_tier_video ^= 1,
        7 => output.maximum_video ^= 1,
        8 => output.maximum_total_rtp ^= 1,
        9 => output.minimum_sustainable ^= 1,
        10 => output.initial_tier ^= 1,
        11 => output.sustainable_tier ^= 1,
        12 => output.upgrade_present ^= 1,
        13 => output.upgrade_tier ^= 1,
        14 => output.direct_threshold_present ^= 1,
        15 => output.direct_threshold_minimum ^= 1,
        16 => output.required_bitrate_bits ^= 1,
        17 => output.required_bitrate_bits ^= 1_u64 << 32,
        18 => output.direct_threshold_bits ^= 1,
        19 => output.direct_threshold_bits ^= 1_u64 << 32,
        _ => panic!("not a copied result word"),
    }
    output
}

#[test]
fn tier_demand_actual_recomputing_verifier_rejects_every_copied_result_word() {
    for input in [facts(50_000_000, 7, Some(15_000_000.0)), facts(1, 0, None),
        facts(u32::MAX, 3, None), facts(436_800, 7, Some(436_800.0))] {
        let output = checked(input);
        for word in 0..20 { assert_eq!(verify(input, tampered(output, word)), 0, "word {word}"); }
    }
}

#[test]
fn tier_demand_verifier_recomputes_changed_cap_tier_and_qualifying_bandwidth() {
    let input = facts(50_000_000, 7, Some(15_000_000.0));
    let output = checked(input);
    for changed in [facts(12_000_000, 7, Some(15_000_000.0)),
        facts(50_000_000, 6, Some(15_000_000.0)), facts(50_000_000, 7, Some(1.0)),
        facts(50_000_000, 7, None), F { abi_version: 0, ..input }] {
        assert_eq!(verify(changed, output), 0);
    }
    // Equivalent telemetry need not be echoed by the projection; only output recomputation is authority.
    assert_eq!(verify(facts(50_000_000, 7, Some(16_000_000.0)), output), 1);
}

#[test]
fn tier_demand_verifier_never_admits_even_exact_canonical_rejection() {
    let invalid = F::default();
    let denied = project(invalid);
    assert_eq!(denied, P { abi_version: 1, ..P::default() });
    assert_eq!(verify(invalid, denied), 0);
    assert_eq!(verify(facts(50_000_000, 7, None), denied), 0);
}

#[test]
fn tier_demand_bandwidth_observations_never_mutate_immutable_profile_projections() {
    for cap in [1, 436_800, 12_000_000, 50_000_000, u32::MAX] {
        for tier in 0..8 {
            let baseline = checked(facts(cap, tier, None));
            for bandwidth in [f64::from_bits(1), 436_800.0, 12_000_000.0, f64::MAX] {
                let output = checked(facts(cap, tier, Some(bandwidth)));
                assert_eq!((output.basis_points, output.baseline_video, output.maximum_tier_video,
                    output.maximum_video, output.maximum_total_rtp, output.minimum_sustainable,
                    output.initial_tier, output.direct_threshold_present, output.direct_threshold_minimum,
                    output.required_bitrate_bits, output.direct_threshold_bits),
                    (baseline.basis_points, baseline.baseline_video, baseline.maximum_tier_video,
                    baseline.maximum_video, baseline.maximum_total_rtp, baseline.minimum_sustainable,
                    baseline.initial_tier, baseline.direct_threshold_present, baseline.direct_threshold_minimum,
                    baseline.required_bitrate_bits, baseline.direct_threshold_bits));
            }
        }
    }
}
