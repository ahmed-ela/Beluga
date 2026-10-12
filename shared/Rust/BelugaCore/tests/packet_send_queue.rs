use beluga_core::beluga_core_packet_send_queue_step as transition;
use beluga_core::packet_send_queue::{RawEvent, RawResult, RawState};
use core::mem::{align_of, offset_of, size_of};

fn state(packets: u64, delay: f64) -> RawState {
    RawState { abi_version: 1, reserved: 0, packets_present: 1, delay_present: 1,
        low_present: 0, soft_present: 0, packets, delay_bits: delay.to_bits(), pressure_count: 0 }
}

fn event(opcode: u32, packets: u64, delay: f64) -> RawEvent {
    RawEvent { opcode, packets_present: 1, delay_present: 1, rtt_inflated: 0,
        packets, delay_bits: delay.to_bits(), low_age_seconds: 0,
        low_age_attoseconds: 0, soft_age_seconds: 0, soft_age_attoseconds: 0 }
}

fn empty_event(opcode: u32) -> RawEvent {
    RawEvent { opcode, packets_present: 0, delay_present: 0, rtt_inflated: 0,
        packets: 0, delay_bits: 0, low_age_seconds: 0,
        low_age_attoseconds: 0, soft_age_seconds: 0, soft_age_attoseconds: 0 }
}

fn empty_state() -> RawState {
    RawState { abi_version: 1, reserved: 0, packets_present: 0, delay_present: 0,
        low_present: 0, soft_present: 0, packets: 0, delay_bits: 0, pressure_count: 0 }
}

fn invalid() -> RawResult {
    RawResult { abi_version: 1, status: 0, observation: 0, low_action: 0,
        soft_action: 0, sample_inflated: 0, immediate: 0, inflated: 0,
        upgrade: 0, capacity_growth: 0, measured_delay_bits: 0, state: empty_state() }
}

fn words(result: RawResult) -> [u32; 10] {
    [result.abi_version, result.status, result.observation, result.low_action,
        result.soft_action, result.sample_inflated, result.immediate,
        result.inflated, result.upgrade, result.capacity_growth]
}

#[test]
fn packet_send_queue_exact_layout_and_all_offsets() {
    assert_eq!((size_of::<RawState>(), size_of::<RawEvent>(), size_of::<RawResult>()), (48, 64, 96));
    assert_eq!((align_of::<RawState>(), align_of::<RawEvent>(), align_of::<RawResult>()), (8, 8, 8));
    assert_eq!([offset_of!(RawState, abi_version), offset_of!(RawState, reserved),
        offset_of!(RawState, packets_present), offset_of!(RawState, delay_present),
        offset_of!(RawState, low_present), offset_of!(RawState, soft_present),
        offset_of!(RawState, packets), offset_of!(RawState, delay_bits),
        offset_of!(RawState, pressure_count)], [0, 4, 8, 12, 16, 20, 24, 32, 40]);
    assert_eq!([offset_of!(RawEvent, opcode), offset_of!(RawEvent, packets_present),
        offset_of!(RawEvent, delay_present), offset_of!(RawEvent, rtt_inflated),
        offset_of!(RawEvent, packets), offset_of!(RawEvent, delay_bits),
        offset_of!(RawEvent, low_age_seconds), offset_of!(RawEvent, low_age_attoseconds),
        offset_of!(RawEvent, soft_age_seconds), offset_of!(RawEvent, soft_age_attoseconds)],
        [0, 4, 8, 12, 16, 24, 32, 40, 48, 56]);
    assert_eq!([offset_of!(RawResult, abi_version), offset_of!(RawResult, status),
        offset_of!(RawResult, observation), offset_of!(RawResult, low_action),
        offset_of!(RawResult, soft_action), offset_of!(RawResult, sample_inflated),
        offset_of!(RawResult, immediate), offset_of!(RawResult, inflated),
        offset_of!(RawResult, upgrade), offset_of!(RawResult, capacity_growth),
        offset_of!(RawResult, measured_delay_bits), offset_of!(RawResult, state)],
        [0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 48]);
}

#[test]
fn packet_send_queue_first_and_partial_baselines_seed_without_measurement() {
    for initial in [empty_state(), RawState { packets_present: 1, packets: 7, ..empty_state() },
        RawState { delay_present: 1, delay_bits: (-1.0_f64).to_bits(), ..empty_state() }] {
        let result = transition(initial, event(0, 9, 0.125));
        assert_eq!(words(result), [1, 1, 0, 1, 1, 0, 0, 0, 0, 0]);
        assert_eq!(result.measured_delay_bits, 0);
        assert_eq!(result.state, state(9, 0.125));
    }
}

#[test]
fn packet_send_queue_invalid_observed_delays_clear_baseline_as_legitimate_unavailable() {
    for bits in [f64::NAN.to_bits(), f64::INFINITY.to_bits(), f64::NEG_INFINITY.to_bits(),
        (-0.001_f64).to_bits(), 0xfff0_0000_0000_0001, 0x7ff8_0000_0000_0021] {
        let mut sample = event(0, 12, 0.0); sample.delay_bits = bits;
        let result = transition(state(11, 0.1), sample);
        assert_eq!(words(result), [1, 1, 0, 1, 1, 0, 0, 0, 0, 0]);
        assert_eq!(result.state, empty_state());
    }
}

#[test]
fn packet_send_queue_missing_observed_components_clear_both_baselines() {
    for sample in [RawEvent { delay_present: 0, delay_bits: 0, ..event(0, 12, 0.0) },
        RawEvent { packets_present: 0, packets: 0, ..event(0, 12, 0.2) }, empty_event(0)] {
        let result = transition(state(11, 0.1), sample);
        assert_eq!(words(result), [1, 1, 0, 1, 1, 0, 0, 0, 0, 0]);
        assert_eq!(result.state, empty_state());
    }
}

#[test]
fn packet_send_queue_regressing_counts_or_delay_seed_current_valid_values() {
    for sample in [event(0, 9, 0.5), event(0, 12, 0.125), event(0, 10, 0.3)] {
        let result = transition(state(10, 0.25), sample);
        assert_eq!(result.observation, 0);
        assert_eq!(result.state, state(sample.packets, f64::from_bits(sample.delay_bits)));
        assert_eq!(result.measured_delay_bits, 0);
    }
}

#[test]
fn packet_send_queue_equal_counts_require_equal_delay_for_no_packets() {
    let still = transition(state(u64::MAX, 0.25), event(0, u64::MAX, 0.25));
    assert_eq!(words(still), [1, 1, 1, 0, 0, 0, 0, 0, 0, 0]);
    assert_eq!(still.state, state(u64::MAX, 0.25));
    let moved_delay = transition(state(u64::MAX, 0.25), event(0, u64::MAX, 0.5));
    assert_eq!(words(moved_delay), [1, 1, 0, 1, 1, 0, 0, 0, 0, 0]);
    assert_eq!(moved_delay.state, state(u64::MAX, 0.5));
}

#[test]
fn packet_send_queue_full_width_counter_difference_precedes_double_conversion() {
    let near_max = transition(state(u64::MAX - 2, 0.0), event(0, u64::MAX, 0.04));
    assert_eq!(near_max.observation, 2);
    assert_eq!(near_max.measured_delay_bits, 0.020_f64.to_bits());
    assert_eq!(near_max.upgrade, 1);
    let entire_range = transition(state(0, 0.0), event(0, u64::MAX, 1.0));
    assert_eq!(entire_range.measured_delay_bits, (1.0 / u64::MAX as f64).to_bits());
    assert_eq!(entire_range.state.packets, u64::MAX);
}

#[test]
fn packet_send_queue_literal_thresholds_and_adjacent_ieee_values() {
    let rows = [
        (0x3f94_7ae1_47ae_147a_u64, 0, 0, 0, 1),
        (0x3f94_7ae1_47ae_147b_u64, 0, 0, 0, 1),
        (0x3f94_7ae1_47ae_147c_u64, 0, 0, 0, 0),
        (0x3fb9_9999_9999_9999_u64, 0, 0, 0, 0),
        (0x3fb9_9999_9999_999a_u64, 0, 0, 0, 0),
        (0x3fb9_9999_9999_999b_u64, 1, 0, 0, 0),
        (0x3fc9_9999_9999_9999_u64, 1, 0, 0, 0),
        (0x3fc9_9999_9999_999a_u64, 1, 1, 1, 0),
        (0x3fc9_9999_9999_999b_u64, 1, 1, 1, 0),
    ];
    for (bits, sample, immediate, inflated, upgrade) in rows {
        let result = transition(state(0, 0.0), event(0, 1, f64::from_bits(bits)));
        assert_eq!((result.sample_inflated, result.immediate, result.inflated, result.upgrade),
            (sample, immediate, inflated, upgrade), "bits={bits:016x}");
        assert_eq!(result.measured_delay_bits, bits);
        assert_eq!(result.capacity_growth, 0);
    }
}

#[test]
fn packet_send_queue_soft_pressure_requires_two_reports_and_stamps_each_measurement() {
    let first = transition(state(0, 0.0), event(0, 1, 0.125));
    assert_eq!(words(first), [1, 1, 2, 1, 2, 1, 0, 0, 0, 0]);
    assert_eq!((first.state.pressure_count, first.state.soft_present), (1, 1));
    let second = transition(first.state, event(0, 2, 0.25));
    assert_eq!(words(second), [1, 1, 2, 1, 2, 1, 0, 1, 0, 0]);
    assert_eq!(second.state.pressure_count, 2);
}

#[test]
fn packet_send_queue_immediate_pressure_does_not_wait_for_soft_confirmation() {
    let result = transition(state(0, 0.0), event(0, 1, 0.25));
    assert_eq!(words(result), [1, 1, 2, 1, 2, 1, 1, 1, 0, 0]);
    assert_eq!(result.state.pressure_count, 1);
}

#[test]
fn packet_send_queue_fresh_rtt_pressure_clears_soft_count_but_not_immediate_classification() {
    let original = RawState { soft_present: 1, pressure_count: 7, ..state(0, 0.0) };
    let soft = transition(original, RawEvent { rtt_inflated: 1, ..event(0, 1, 0.125) });
    assert_eq!(words(soft), [1, 1, 2, 1, 1, 1, 0, 0, 0, 0]);
    assert_eq!((soft.state.pressure_count, soft.state.soft_present), (0, 0));
    let immediate = transition(original, RawEvent { rtt_inflated: 1, ..event(0, 1, 0.25) });
    assert_eq!(immediate.inflated, 1);
    assert_eq!(immediate.state.pressure_count, 0);
}

#[test]
fn packet_send_queue_soft_lease_is_exactly_closed_zero_through_one_point_five_seconds() {
    let original = RawState { soft_present: 1, pressure_count: 1, ..state(0, 0.0) };
    for (seconds, atto, expected_count) in [(0, 0, 2), (1, 499_999_999_999_999_999, 2),
        (1, 500_000_000_000_000_000, 2), (1, 500_000_000_000_000_001, 1),
        (0, -1, 1), (-1, 0, 1), (2, 0, 1)] {
        let result = transition(original, RawEvent { soft_age_seconds: seconds,
            soft_age_attoseconds: atto, ..event(0, 1, 0.125) });
        assert_eq!(result.state.pressure_count, expected_count, "{seconds}/{atto}");
        assert_eq!(result.soft_action, 2);
    }
}

#[test]
fn packet_send_queue_no_packets_never_renew_low_or_soft_stamps() {
    let original = RawState { low_present: 1, soft_present: 1, pressure_count: 2, ..state(4, 0.5) };
    let result = transition(original, RawEvent { low_age_seconds: 1,
        low_age_attoseconds: 500_000_000_000_000_000, soft_age_seconds: 1,
        soft_age_attoseconds: 500_000_000_000_000_000, ..event(0, 4, 0.5) });
    assert_eq!(words(result), [1, 1, 1, 0, 0, 0, 0, 0, 1, 0]);
    assert_eq!(result.state, original);
}

#[test]
fn packet_send_queue_no_packets_expired_or_future_stamps_are_cleared() {
    let original = RawState { low_present: 1, soft_present: 1, pressure_count: 2, ..state(4, 0.5) };
    for (seconds, atto) in [(1, 500_000_000_000_000_001), (0, -1), (i64::MAX, 0), (i64::MIN, 0)] {
        let result = transition(original, RawEvent { low_age_seconds: seconds,
            low_age_attoseconds: atto, soft_age_seconds: seconds,
            soft_age_attoseconds: atto, ..event(0, 4, 0.5) });
        assert_eq!(words(result), [1, 1, 1, 1, 1, 0, 0, 0, 0, 0]);
        assert_eq!((result.state.low_present, result.state.soft_present, result.state.pressure_count), (0, 0, 0));
    }
}

#[test]
fn packet_send_queue_no_packets_nil_soft_preserves_original_counter_branch() {
    let original = RawState { pressure_count: 9, ..state(3, 0.5) };
    let result = transition(original, event(0, 3, 0.5));
    assert_eq!(result.state, original);
    assert_eq!(words(result), [1, 1, 1, 0, 0, 0, 0, 0, 0, 0]);
    let measured = transition(original, event(0, 4, 0.625));
    assert_eq!(measured.state.pressure_count, 10);
    assert_eq!(measured.inflated, 1);
}

#[test]
fn packet_send_queue_signed_int_counter_saturates_without_wrap() {
    let original = RawState { soft_present: 1, pressure_count: i64::MAX as u64, ..state(0, 0.0) };
    let result = transition(original, event(0, 1, 0.125));
    assert_eq!(result.state.pressure_count, 9_223_372_036_854_775_807);
    assert_eq!(result.inflated, 1);
    let expired = transition(original, RawEvent { soft_age_seconds: 2, ..event(0, 1, 0.125) });
    assert_eq!(expired.state.pressure_count, 1);
}

#[test]
fn packet_send_queue_measured_low_delay_stamps_and_soft_or_unavailable_clear() {
    let original = RawState { low_present: 1, soft_present: 1, pressure_count: 4, ..state(0, 0.0) };
    let low = transition(original, event(0, 1, 0.010));
    assert_eq!(words(low), [1, 1, 2, 2, 1, 0, 0, 0, 1, 0]);
    assert_eq!((low.state.low_present, low.state.soft_present, low.state.pressure_count), (1, 0, 0));
    let neutral = transition(original, event(0, 1, 0.050));
    assert_eq!(words(neutral), [1, 1, 2, 1, 1, 0, 0, 0, 0, 0]);
    let missing = transition(original, empty_event(0));
    assert_eq!(missing.state, empty_state());
    assert_eq!(words(missing), [1, 1, 0, 1, 1, 0, 0, 0, 0, 0]);
}

#[test]
fn packet_send_queue_tier_reset_retains_raw_baseline_and_path_reset_clears_it() {
    let original = RawState { low_present: 1, soft_present: 1, pressure_count: 17,
        delay_bits: f64::NEG_INFINITY.to_bits(), ..state(u64::MAX, 0.0) };
    let tier = transition(original, empty_event(2));
    assert_eq!(words(tier), [1, 1, 0, 1, 1, 0, 0, 0, 0, 0]);
    assert_eq!(tier.state, RawState { low_present: 0, soft_present: 0, pressure_count: 0, ..original });
    let path = transition(original, empty_event(3));
    assert_eq!(words(path), [1, 1, 0, 1, 1, 0, 0, 0, 0, 0]);
    assert_eq!(path.state, empty_state());
}

#[test]
fn packet_send_queue_low_lease_query_is_nonmutating_and_has_no_telemetry() {
    let original = RawState { low_present: 1, soft_present: 1, pressure_count: 7, ..state(17, 0.25) };
    for (seconds, atto, permission) in [(0, 0, 1), (1, 500_000_000_000_000_000, 1),
        (1, 500_000_000_000_000_001, 0), (0, -1, 0), (i64::MAX, 0, 0)] {
        let result = transition(original, RawEvent { low_age_seconds: seconds,
            low_age_attoseconds: atto, ..empty_event(4) });
        assert_eq!(result.state, original);
        assert_eq!(words(result), [1, 1, 0, 0, 0, 0, 0, 0, permission, 0]);
        assert_eq!(result.measured_delay_bits, 0);
    }
}

#[test]
fn packet_send_queue_capacity_growth_needs_fresh_ordinary_low_lease() {
    let original = state(0, 0.0);
    let missing_lease = transition(original, event(1, 1, 0.010));
    assert_eq!(words(missing_lease), [1, 1, 2, 0, 0, 0, 0, 0, 1, 0]);
    let fresh = RawState { low_present: 1, ..original };
    let growth = transition(fresh, RawEvent { low_age_seconds: 1,
        low_age_attoseconds: 500_000_000_000_000_000, ..event(1, 1, 0.010) });
    assert_eq!(words(growth), [1, 1, 2, 0, 0, 0, 0, 0, 1, 1]);
    let expired = transition(fresh, RawEvent { low_age_seconds: 1,
        low_age_attoseconds: 500_000_000_000_000_001, ..event(1, 1, 0.010) });
    assert_eq!((expired.upgrade, expired.capacity_growth, expired.state.low_present, expired.low_action), (1, 0, 1, 0));
}

#[test]
fn packet_send_queue_capacity_no_packets_borrows_but_never_renews_low_lease() {
    let original = RawState { low_present: 1, ..state(17, 0.25) };
    let fresh = transition(original, event(1, 17, 0.25));
    assert_eq!(words(fresh), [1, 1, 1, 0, 0, 0, 0, 0, 1, 1]);
    assert_eq!(fresh.state, original);
    let expired = transition(original, RawEvent { low_age_seconds: 2, ..event(1, 17, 0.25) });
    assert_eq!(words(expired), [1, 1, 1, 0, 0, 0, 0, 0, 0, 0]);
    assert_eq!(expired.state, original);
}

#[test]
fn packet_send_queue_capacity_never_accumulates_or_retires_ordinary_pressure() {
    let original = RawState { low_present: 1, soft_present: 1, pressure_count: 2, ..state(0, 0.0) };
    let pressure = transition(original, RawEvent { low_age_seconds: 3, soft_age_seconds: 3,
        ..event(1, 1, 0.125) });
    assert_eq!(words(pressure), [1, 1, 2, 0, 0, 1, 0, 1, 0, 0]);
    assert_eq!((pressure.state.pressure_count, pressure.state.low_present, pressure.state.soft_present), (2, 1, 1));
    let immediate = transition(original, event(1, 1, 0.25));
    assert_eq!((immediate.sample_inflated, immediate.immediate, immediate.inflated), (1, 1, 1));
    assert_eq!(immediate.state.pressure_count, 2);
    assert_eq!(transition(original, RawEvent { rtt_inflated: 1, ..event(1, 1, 0.125) }), invalid());
}

#[test]
fn packet_send_queue_capacity_temporary_baseline_validation_does_not_change_evidence() {
    let original = RawState { low_present: 1, soft_present: 1, pressure_count: 3, ..state(17, 0.25) };
    let unavailable = transition(original, event(1, 18, f64::NAN));
    assert_eq!(words(unavailable), [1, 1, 0, 0, 0, 0, 0, 0, 0, 0]);
    assert_eq!(unavailable.state, RawState { packets_present: 0, delay_present: 0,
        packets: 0, delay_bits: 0, ..original });
    let partial = RawState { packets_present: 0, packets: 0, ..original };
    let seed = transition(partial, event(1, 18, 0.5));
    assert_eq!(seed.observation, 0);
    assert_eq!(seed.state, RawState { packets_present: 1, packets: 18,
        delay_bits: 0.5_f64.to_bits(), ..original });
}

#[test]
fn packet_send_queue_raw_negative_infinite_fast_baseline_can_measure_infinite_delay() {
    let original = state(4, f64::NEG_INFINITY);
    for opcode in [0, 1] {
        let result = transition(original, event(opcode, 5, 0.0));
        assert_eq!(result.status, 1);
        assert_eq!(result.observation, 2);
        assert_eq!(result.measured_delay_bits, 0x7ff0_0000_0000_0000);
        assert_eq!((result.sample_inflated, result.immediate, result.inflated, result.upgrade), (1, 1, 1, 0));
        assert_eq!(result.state.delay_bits, 0);
    }
}

#[test]
fn packet_send_queue_raw_nan_or_positive_infinite_prior_is_unavailable_then_seeded() {
    for previous in [f64::NAN, f64::INFINITY] {
        let result = transition(state(4, previous), event(1, 5, 0.0));
        assert_eq!(words(result), [1, 1, 0, 0, 0, 0, 0, 0, 0, 0]);
        assert_eq!(result.state, state(5, 0.0));
    }
}

#[test]
fn packet_send_queue_raw_negative_finite_prior_uses_original_difference() {
    let result = transition(state(4, -0.5), event(1, 6, 0.0));
    assert_eq!(result.measured_delay_bits, 0.25_f64.to_bits());
    assert_eq!(words(result), [1, 1, 2, 0, 0, 1, 1, 1, 0, 0]);
    assert_eq!(result.state, state(6, 0.0));
}

#[test]
fn packet_send_queue_signed_zero_and_subnormal_delay_bits_are_preserved() {
    let negative_zero = transition(state(0, 0.0), event(0, 1, -0.0));
    assert_eq!(negative_zero.measured_delay_bits, 0x8000_0000_0000_0000);
    assert_eq!(negative_zero.state.delay_bits, 0x8000_0000_0000_0000);
    assert_eq!(negative_zero.upgrade, 1);
    let tiny = transition(state(0, 0.0), event(0, 1, f64::from_bits(1)));
    assert_eq!(tiny.measured_delay_bits, 1);
    assert_eq!(tiny.upgrade, 1);
    let equal_signed = transition(state(1, -0.0), event(0, 1, 0.0));
    assert_eq!(equal_signed.observation, 1);
}

#[test]
fn packet_send_queue_exact_signed_duration_components_do_not_quantize() {
    let original = RawState { low_present: 1, ..empty_state() };
    for (seconds, atto, permission) in [(1, -500_000_000_000_000_000, 1),
        (2, -500_000_000_000_000_000, 1), (2, -499_999_999_999_999_999, 0),
        (-1, 999_999_999_999_999_999, 0), (i64::MAX, 999_999_999_999_999_999, 0),
        (i64::MIN, -999_999_999_999_999_999, 0)] {
        let result = transition(original, RawEvent { low_age_seconds: seconds,
            low_age_attoseconds: atto, ..empty_event(4) });
        assert_eq!((result.status, result.upgrade), (1, permission), "{seconds}/{atto}");
        assert_eq!(result.state, original);
    }
}

#[test]
fn packet_send_queue_malformed_state_words_have_canonical_no_authority_result() {
    let good = state(1, 0.0);
    for malformed in [RawState { abi_version: 0, ..good }, RawState { abi_version: 2, ..good },
        RawState { reserved: 1, ..good }, RawState { packets_present: 2, ..good },
        RawState { delay_present: 2, ..good }, RawState { low_present: 2, ..good },
        RawState { soft_present: 2, ..good }, RawState { pressure_count: i64::MAX as u64 + 1, ..good },
        RawState { packets_present: 0, packets: 1, ..good },
        RawState { delay_present: 0, delay_bits: 0x8000_0000_0000_0000, ..good }] {
        for opcode in 0..=4 {
            assert_eq!(transition(malformed, empty_event(opcode)), invalid());
        }
    }
}

#[test]
fn packet_send_queue_malformed_events_and_noncanonical_absent_ages_deny() {
    let initial = empty_state();
    for malformed in [RawEvent { opcode: 5, ..empty_event(0) },
        RawEvent { opcode: u32::MAX, ..empty_event(0) },
        RawEvent { packets_present: 2, ..empty_event(0) },
        RawEvent { delay_present: 2, ..empty_event(0) },
        RawEvent { rtt_inflated: 2, ..empty_event(0) },
        RawEvent { packets: 1, ..empty_event(0) },
        RawEvent { delay_bits: 0x8000_0000_0000_0000, ..empty_event(0) },
        RawEvent { low_age_seconds: 1, ..empty_event(0) },
        RawEvent { low_age_attoseconds: 1, ..empty_event(0) },
        RawEvent { soft_age_seconds: 1, ..empty_event(0) },
        RawEvent { soft_age_attoseconds: 1, ..empty_event(0) }] {
        assert_eq!(transition(initial, malformed), invalid());
    }
    let leases = RawState { low_present: 1, soft_present: 1, ..initial };
    for atto in [i64::MIN, -1_000_000_000_000_000_000, 1_000_000_000_000_000_000, i64::MAX] {
        assert_eq!(transition(leases, RawEvent { low_age_attoseconds: atto, ..empty_event(0) }), invalid());
        assert_eq!(transition(leases, RawEvent { soft_age_attoseconds: atto, ..empty_event(1) }), invalid());
    }
}

#[test]
fn packet_send_queue_reset_and_query_reject_irrelevant_nonzero_input_fields() {
    for opcode in [2, 3, 4] {
        for malformed in [RawEvent { packets_present: 1, ..empty_event(opcode) },
            RawEvent { delay_present: 1, ..empty_event(opcode) },
            RawEvent { rtt_inflated: 1, ..empty_event(opcode) },
            RawEvent { soft_age_seconds: 1, ..empty_event(opcode) }] {
            assert_eq!(transition(empty_state(), malformed), invalid());
        }
    }
    for opcode in [2, 3] {
        assert_eq!(transition(RawState { low_present: 1, ..empty_state() },
            RawEvent { low_age_attoseconds: 1, ..empty_event(opcode) }), invalid());
    }
}

#[test]
fn packet_send_queue_no_packets_fresh_rtt_pressure_retires_soft_only() {
    let original = RawState { low_present: 1, soft_present: 1, pressure_count: 3, ..state(7, 0.25) };
    let result = transition(original, RawEvent { rtt_inflated: 1, ..event(0, 7, 0.25) });
    assert_eq!(words(result), [1, 1, 1, 0, 1, 0, 0, 0, 1, 0]);
    assert_eq!(result.state, RawState { soft_present: 0, pressure_count: 0, ..original });
}
