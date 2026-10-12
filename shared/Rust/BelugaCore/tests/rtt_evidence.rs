use beluga_core::{beluga_core_rtt_evidence_step as step,
    beluga_core_rtt_evidence_result_is_valid as verify};
use beluga_core::rtt_evidence::{RawMeasurement as M, RawState as S, RawEvent as E, RawResult as O};
use std::mem::{align_of, offset_of, size_of};

fn measurement(pair: u8, total: f64, responses: u64) -> M {
    M { fingerprint_words: [u64::from_le_bytes([pair; 8]); 8], total_bits: total.to_bits(), responses }
}

fn native(current: f64, total: f64, responses: u64) -> E {
    E { observation_kind: 2, current_present: 1, fingerprint_length: 64,
        current_bits: current.to_bits(), measurement: measurement(b'a', total, responses), ..E::default() }
}

fn aged(mut event: E, seconds: i64, attoseconds: i64) -> E {
    event.age_seconds = seconds; event.age_attoseconds = attoseconds; event
}

fn operation(opcode: u32) -> E { E { opcode, ..E::default() } }

fn checked(before: S, event: E) -> O {
    let result = step(before, event);
    assert_eq!(result.status, 1);
    assert_eq!(verify(before, event, result), 1);
    assert_eq!((result.reserved, result.reserved2), (0, 0));
    result
}

fn healthy() -> S { checked(S::initial(), native(0.100, 1.0, 100)).state }

fn unknown(result: O, disposition: u32) {
    assert_eq!((result.fresh_pressure, result.allows_upgrade, result.legacy_missing), (0, 0, 0));
    assert_eq!(result.clock_action, 0);
    assert_eq!((result.validation_disposition, result.state.disposition), (disposition, disposition));
    assert_eq!(result.state.health, 0);
}

fn rejected(before: S, event: E) {
    let actual = step(before, event);
    let expected = O { abi_version: 1, status: 0, fresh_pressure: 0, allows_upgrade: 0,
        legacy_missing: 0, clock_action: 0, validation_disposition: 6, primary_lease_current: 0,
        reserved: 0, reserved2: 0, state: before };
    assert_eq!(actual, expected);
    assert_eq!(verify(before, event, actual), 0);
}

#[test]
fn rtt_evidence_all_four_layouts_and_every_field_offset_are_literal() {
    assert_eq!((size_of::<M>(), align_of::<M>()), (80, 8));
    assert_eq!((size_of::<S>(), align_of::<S>()), (296, 8));
    assert_eq!((size_of::<E>(), align_of::<E>()), (128, 8));
    assert_eq!((size_of::<O>(), align_of::<O>()), (336, 8));
    let offsets = [
        (offset_of!(M, fingerprint_words), 0), (offset_of!(M, total_bits), 64), (offset_of!(M, responses), 72),
        (offset_of!(S, abi_version), 0), (offset_of!(S, reserved), 4),
        (offset_of!(S, baseline_present), 8), (offset_of!(S, bootstrap_count), 12),
        (offset_of!(S, disposition), 16), (offset_of!(S, health), 20),
        (offset_of!(S, uses_native), 24), (offset_of!(S, provisional), 28),
        (offset_of!(S, permits_initial), 32), (offset_of!(S, distinct_count), 36),
        (offset_of!(S, last_measured_present), 40), (offset_of!(S, advancement_present), 44),
        (offset_of!(S, age_present), 48), (offset_of!(S, watermark_present), 52),
        (offset_of!(S, fence_present), 56), (offset_of!(S, fence_current_present), 60),
        (offset_of!(S, reserved2), 64), (offset_of!(S, reserved3), 68),
        (offset_of!(S, baseline_bits), 72), (offset_of!(S, last_measured_bits), 80),
        (offset_of!(S, bootstrap_bits), 88), (offset_of!(S, age_seconds), 112),
        (offset_of!(S, age_attoseconds), 120), (offset_of!(S, watermark), 128),
        (offset_of!(S, fence), 208), (offset_of!(S, fence_current_bits), 288),
        (offset_of!(E, opcode), 0), (offset_of!(E, observation_kind), 4),
        (offset_of!(E, current_present), 8), (offset_of!(E, fingerprint_length), 12),
        (offset_of!(E, route_changed), 16), (offset_of!(E, reserved), 20),
        (offset_of!(E, current_bits), 24), (offset_of!(E, measurement), 32),
        (offset_of!(E, age_seconds), 112), (offset_of!(E, age_attoseconds), 120),
        (offset_of!(O, abi_version), 0), (offset_of!(O, status), 4),
        (offset_of!(O, fresh_pressure), 8), (offset_of!(O, allows_upgrade), 12),
        (offset_of!(O, legacy_missing), 16), (offset_of!(O, clock_action), 20),
        (offset_of!(O, validation_disposition), 24), (offset_of!(O, primary_lease_current), 28),
        (offset_of!(O, reserved), 32), (offset_of!(O, reserved2), 36), (offset_of!(O, state), 40),
    ];
    assert_eq!(offsets.len(), 50);
    for (actual, expected) in offsets { assert_eq!(actual, expected); }
    let actual = checked(S::initial(), native(0.1, 1.0, 0));
    assert_eq!(actual.state.watermark.responses, 0);
}

#[test]
fn rtt_evidence_initial_and_first_native_provisional_reference_are_exact() {
    let initial = S::initial();
    assert_eq!((initial.abi_version, initial.disposition, initial.health, initial.permits_initial), (1, 6, 0, 1));
    let result = checked(initial, native(0.100, 0.100, 0));
    assert_eq!((result.fresh_pressure, result.allows_upgrade, result.clock_action), (0, 1, 2));
    assert_eq!((result.validation_disposition, result.primary_lease_current), (1, 0));
    assert_eq!((result.state.baseline_present, result.state.baseline_bits), (1, 0.100f64.to_bits()));
    assert_eq!((result.state.distinct_count, result.state.provisional, result.state.permits_initial), (1, 1, 0));
    assert_eq!((result.state.age_present, result.state.age_seconds, result.state.age_attoseconds), (1, 0, 0));
    assert_eq!((result.state.advancement_present, result.state.last_measured_present), (1, 1));
    assert_eq!(result.state.last_measured_bits, 0.100f64.to_bits());
}

#[test]
fn rtt_evidence_native_three_distinct_healthy_references_saturate_without_cached_credit() {
    let mut state = healthy();
    let duplicate = checked(state, aged(native(0.100, 1.0, 100), 1, 0));
    assert_eq!((duplicate.state.distinct_count, duplicate.state.provisional, duplicate.clock_action), (1, 1, 0));
    for (count, provisional, responses) in [(2, 1, 101), (3, 0, 102), (3, 0, 103)] {
        let result = checked(state, aged(native(0.100, 1.0, responses), 1, 0));
        assert_eq!((result.state.distinct_count, result.state.provisional, result.validation_disposition), (count, provisional, 2));
        assert_eq!(result.clock_action, 2);
        state = result.state;
    }
}

#[test]
fn rtt_evidence_legacy_three_sample_bootstrap_uses_sorted_median() {
    let mut state = S::initial();
    for (index, value) in [0.300f64, 0.100, 0.200].into_iter().enumerate() {
        let result = checked(state, E { current_present: 1, current_bits: value.to_bits(), ..E::default() });
        assert_eq!((result.validation_disposition, result.state.uses_native, result.clock_action), (0, 0, 0));
        if index < 2 {
            assert_eq!(result.state.baseline_present, 0);
            assert_eq!(result.state.bootstrap_count, index as u32 + 1);
            assert_eq!(result.allows_upgrade, 0);
        } else {
            assert_eq!(result.state.baseline_bits, 0.200f64.to_bits());
            assert_eq!((result.state.bootstrap_count, result.state.bootstrap_bits), (0, [0; 3]));
            assert_eq!(result.allows_upgrade, 1);
        }
        state = result.state;
    }
}

#[test]
fn rtt_evidence_legacy_nil_refreshes_age_and_does_not_mint_native_health() {
    let before = healthy();
    let result = checked(before, aged(E::default(), 5, 0));
    assert_eq!((result.legacy_missing, result.allows_upgrade, result.fresh_pressure), (1, 0, 0));
    assert_eq!((result.state.uses_native, result.validation_disposition), (0, 0));
    assert_eq!((result.state.age_seconds, result.state.age_attoseconds), (5, 0));
    assert_eq!(result.state.watermark, before.watermark);
    assert_eq!(result.state.health, before.health);
    assert_eq!(result.clock_action, 0);
}

#[test]
fn rtt_evidence_literal_inflation_thresholds_and_ieee_neighbors_are_unchanged() {
    for baseline in [0.020f64, 0.200] {
        let mut before = healthy();
        before.baseline_bits = baseline.to_bits();
        let threshold = if baseline == 0.020 { baseline + 0.050 } else { baseline * 1.5 };
        for (current, pressure) in [(f64::from_bits(threshold.to_bits() - 1), 0),
            (threshold, 0), (f64::from_bits(threshold.to_bits() + 1), 1)] {
            let result = checked(before, native(current, 2.0, 101));
            assert_eq!((result.fresh_pressure, result.allows_upgrade), (pressure, 1 - pressure));
            assert_eq!(result.validation_disposition, if pressure != 0 { 3 } else { 2 });
            assert_eq!(result.clock_action, 2);
        }
    }
}

#[test]
fn rtt_evidence_baseline_falls_at_most_ten_milliseconds_and_never_rises() {
    let mut before = healthy(); before.baseline_bits = 0.200f64.to_bits();
    let lower = checked(before, native(0.050, 2.0, 101));
    assert_eq!(lower.state.baseline_bits, (0.200f64 - 0.010).to_bits());
    let higher = checked(lower.state, native(0.250, 3.0, 102));
    assert_eq!(higher.state.baseline_bits, lower.state.baseline_bits);
    let inflated = checked(higher.state, native(0.500, 4.0, 103));
    assert_eq!(inflated.state.baseline_bits, lower.state.baseline_bits);
    assert_eq!(inflated.state.distinct_count, higher.state.distinct_count);
    let mut legacy = before; legacy.uses_native = 0;
    let result = checked(legacy, E { current_present: 1, current_bits: 0.500f64.to_bits(), ..E::default() });
    assert_eq!((result.fresh_pressure, result.allows_upgrade), (1, 0));
    assert_eq!(result.state.baseline_bits, before.baseline_bits);
}

#[test]
fn rtt_evidence_response_counts_are_full_width_and_either_counter_can_advance() {
    let first = checked(S::initial(), native(0.100, 1.0, 9_007_199_254_740_992)).state;
    let response_only = checked(first, native(0.100, 1.0, 9_007_199_254_740_993));
    assert_eq!((response_only.clock_action, response_only.validation_disposition), (2, 2));
    assert_eq!(response_only.state.watermark.responses, 9_007_199_254_740_993);
    let maximum = checked(response_only.state, native(0.100, 1.0, u64::MAX));
    assert_eq!((maximum.clock_action, maximum.state.watermark.responses), (2, u64::MAX));
    let total_only = checked(maximum.state, native(0.100, 2.0, u64::MAX));
    assert_eq!((total_only.clock_action, total_only.validation_disposition), (2, 2));
}

#[test]
fn rtt_evidence_cached_healthy_lease_is_closed_at_four_seconds_without_quantization() {
    let before = healthy();
    for (seconds, attoseconds, disposition, allows) in [
        (0, 0, 4, 1), (3, 999_999_999_999_999_999, 4, 1), (4, 0, 4, 1),
        (4, 1, 7, 0), (i64::MAX, 999_999_999_999_999_999, 7, 0)] {
        let result = checked(before, aged(native(0.100, 1.0, 100), seconds, attoseconds));
        assert_eq!((result.validation_disposition, result.allows_upgrade), (disposition, allows));
        assert_eq!(result.primary_lease_current, allows);
        assert_eq!(result.clock_action, 0);
        assert_eq!((result.state.age_seconds, result.state.age_attoseconds), (seconds, attoseconds));
    }
}

#[test]
fn rtt_evidence_cached_watermark_never_renews_clock_or_repeats_inflation_pressure() {
    let inflated = checked(healthy(), native(0.200, 2.0, 101));
    assert_eq!((inflated.fresh_pressure, inflated.clock_action, inflated.validation_disposition), (1, 2, 3));
    for (seconds, attoseconds) in [(0, 0), (4, 1), (i64::MAX, 0)] {
        let result = checked(inflated.state, aged(native(0.200, 2.0, 101), seconds, attoseconds));
        assert_eq!((result.fresh_pressure, result.allows_upgrade, result.clock_action), (0, 0, 0));
        assert_eq!((result.validation_disposition, result.state.health), (5, 2));
        assert_eq!(result.state.last_measured_bits, 0.200f64.to_bits());
    }
}

#[test]
fn rtt_evidence_scalar_contradiction_consumes_identity_and_cannot_be_repaired_in_place() {
    let before = healthy();
    let changed = checked(before, native(0.110, 1.0, 100));
    unknown(changed, 6);
    assert_eq!(changed.state.fence_current_bits, 0.110f64.to_bits());
    let repaired = checked(changed.state, native(0.100, 1.0, 100));
    unknown(repaired, 6);
    let advance = checked(repaired.state, native(0.100, 1.0, 101));
    assert_eq!((advance.clock_action, advance.allows_upgrade), (2, 1));
}

#[test]
fn rtt_evidence_invalid_current_consumes_first_privilege_and_valid_watermark() {
    for invalid in [0.0f64, -0.0, -1.0, f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        let consumed = checked(S::initial(), native(invalid, 1.0, 100));
        unknown(consumed, 6);
        assert_eq!((consumed.state.watermark_present, consumed.state.permits_initial), (1, 0));
        assert_eq!((consumed.state.fence_current_present, consumed.state.fence_current_bits), (0, 0));
        let same = checked(consumed.state, native(0.100, 1.0, 100));
        unknown(same, 6);
        let next = checked(same.state, native(0.100, 1.0, 101));
        assert_eq!((next.allows_upgrade, next.validation_disposition, next.state.provisional), (1, 2, 1));
    }
    let mut missing = native(0.100, 1.0, 100); missing.current_present = 0; missing.current_bits = 0;
    unknown(checked(S::initial(), missing), 6);
    unknown(checked(S::initial(), native(0.200, 0.100, 100)), 6);
}

#[test]
fn rtt_evidence_unavailable_promotes_fence_to_tombstone_and_blocks_revival() {
    let before = healthy();
    let mut fast = native(0.100, 2.0, 101); fast.opcode = 1;
    let advanced_fence = checked(before, fast);
    assert_eq!(advanced_fence.state.watermark, before.watermark);
    let unavailable = checked(advanced_fence.state, E { observation_kind: 1, ..E::default() });
    unknown(unavailable, 6);
    assert_eq!(unavailable.state.watermark, fast.measurement);
    let repaired = checked(unavailable.state, native(0.100, 2.0, 101));
    unknown(repaired, 6);
    assert_eq!(repaired.clock_action, 0);
}

#[test]
fn rtt_evidence_pair_a_b_a_reseeds_and_clears_only_reference_not_peer_clock() {
    let mut before = healthy();
    for pair in [b'b', b'a'] {
        let mut event = native(0.100, 2.0, 101); event.measurement = measurement(pair, 2.0, 101);
        let seeded = checked(before, event);
        unknown(seeded, 8);
        assert_eq!((seeded.state.baseline_present, seeded.state.distinct_count, seeded.state.provisional), (0, 0, 0));
        assert_eq!((seeded.state.advancement_present, seeded.state.last_measured_bits), (1, before.last_measured_bits));
        assert_eq!(seeded.state.fence, event.measurement);
        before = seeded.state;
    }
    let advanced = checked(before, native(0.100, 3.0, 102));
    assert_eq!((advanced.validation_disposition, advanced.clock_action, advanced.state.provisional), (2, 2, 1));
}

#[test]
fn rtt_evidence_regression_reseeds_without_discarding_same_pair_baseline() {
    let before = healthy();
    for event in [native(0.100, 0.500, 100), native(0.100, 1.0, 99), native(0.100, 0.500, 99)] {
        let seeded = checked(before, event);
        unknown(seeded, 8);
        assert_eq!((seeded.state.baseline_bits, seeded.state.distinct_count, seeded.state.provisional),
            (before.baseline_bits, before.distinct_count, before.provisional));
        assert_eq!(seeded.state.watermark, event.measurement);
        let advanced = checked(seeded.state, native(0.100, 2.0, 101));
        assert_eq!((advanced.clock_action, advanced.allows_upgrade), (2, 1));
    }
}

#[test]
fn rtt_evidence_malformed_measurement_is_accepted_unknown_not_abi_rejection() {
    let before = healthy();
    for length in [0, 63, 65, u32::MAX] {
        let mut event = native(0.100, 2.0, 101); event.fingerprint_length = length;
        unknown(checked(before, event), 6);
    }
    for byte in [b'A', b'g', b'/', 0, 255] {
        let mut event = native(0.100, 2.0, 101);
        event.measurement.fingerprint_words[7] = u64::from_le_bytes([byte; 8]);
        unknown(checked(before, event), 6);
    }
    for total in [-1.0f64, f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        unknown(checked(before, native(0.100, total, 101)), 6);
    }
}

#[test]
fn rtt_evidence_zero_totals_and_signed_zero_raw_bits_are_preserved_without_health() {
    for total in [0.0f64, -0.0] {
        let result = checked(S::initial(), native(0.0, total, 0));
        unknown(result, 6);
        assert_eq!(result.state.watermark.total_bits, total.to_bits());
        assert_eq!(result.state.fence.total_bits, total.to_bits());
        let mut forged = result; forged.state.watermark.total_bits ^= 1 << 63;
        assert_eq!(verify(S::initial(), native(0.0, total, 0), forged), 0);
    }
    let mut before = S::initial(); before.fence_present = 1;
    before.fence = measurement(b'a', -0.0, 0);
    let equivalent = checked(before, native(0.0, 0.0, 0));
    unknown(equivalent, 6);
    assert_eq!(equivalent.state.fence.total_bits, 0.0f64.to_bits());
}

#[test]
fn rtt_evidence_future_clock_age_consumes_tuple_but_cannot_stamp_or_authorize() {
    let before = healthy();
    for (seconds, atto) in [(0, -1), (-1, 0), (i64::MIN, -999_999_999_999_999_999)] {
        let result = checked(before, aged(native(0.100, 2.0, 101), seconds, atto));
        unknown(result, 6);
        assert_eq!(result.primary_lease_current, 0);
        assert_eq!(result.state.watermark.responses, 101);
        assert_eq!(result.state.last_measured_bits, before.last_measured_bits);
    }
}

#[test]
fn rtt_evidence_path_hide_and_peer_reset_have_distinct_identity_and_clock_ownership() {
    let before = healthy();
    let hidden = checked(before, operation(3));
    unknown(hidden, 6);
    assert_eq!(hidden.state.watermark, before.watermark);
    assert_eq!(hidden.state.fence, before.fence);
    assert_eq!(hidden.state.baseline_bits, before.baseline_bits);
    assert_eq!(hidden.state.advancement_present, 1);
    assert_eq!(hidden.state.uses_native, 1);
    let path = checked(before, operation(4));
    unknown(path, 6);
    assert_eq!((path.state.baseline_present, path.state.bootstrap_count, path.state.provisional, path.state.distinct_count), (0, 0, 0, 0));
    assert_eq!((path.state.watermark, path.state.fence, path.state.advancement_present), (before.watermark, before.fence, 1));
    assert_eq!(path.state.age_present, before.age_present);
    let peer = checked(before, operation(5));
    assert_eq!(peer.clock_action, 1);
    let expected = S { uses_native: 1, ..S::initial() };
    assert_eq!(peer.state, expected);
    assert_eq!(peer.validation_disposition, 6);
}

#[test]
fn rtt_evidence_disabled_initial_privilege_requires_seed_then_distinct_advancement() {
    for opcode in [3, 4] {
        let before = checked(S::initial(), operation(opcode)).state;
        assert_eq!((before.watermark_present, before.permits_initial), (0, 0));
        let seeded = checked(before, native(0.100, 1.0, 100));
        unknown(seeded, 8);
        assert_eq!(seeded.state.baseline_present, 0);
        let advanced = checked(seeded.state, native(0.100, 1.0, 101));
        assert_eq!((advanced.allows_upgrade, advanced.clock_action, advanced.validation_disposition), (1, 2, 2));
    }
}

#[test]
fn rtt_evidence_inactive_tombstone_replaces_watermark_but_preserves_fence_and_clock() {
    let before = healthy();
    let mut inactive = native(0.100, 2.0, 101); inactive.opcode = 6;
    let result = checked(before, inactive);
    unknown(result, 6);
    assert_eq!(result.state.watermark, inactive.measurement);
    assert_eq!(result.state.fence, before.fence);
    assert_eq!(result.state.last_measured_bits, before.last_measured_bits);
    assert_eq!(result.state.advancement_present, 1);
    assert_eq!(result.state.uses_native, 1);
    assert_eq!(result.state.baseline_present, 0);
    inactive.fingerprint_length = 65;
    assert_eq!(checked(before, inactive).state.watermark, before.watermark);
}

#[test]
fn rtt_evidence_revoke_allow_initial_and_ordering_are_narrow_named_operations() {
    let before = healthy();
    let revoked = checked(before, operation(2));
    let mut expected = before; expected.health = 0; expected.disposition = 6;
    assert_eq!(revoked.state, expected);
    let reordered = checked(before, operation(8));
    expected = before; expected.disposition = 9;
    assert_eq!(reordered.state, expected);
    assert_eq!(reordered.validation_disposition, 9);
    let mut legacy_before = before; legacy_before.uses_native = 0;
    let strict = checked(legacy_before, operation(9));
    expected = legacy_before; expected.uses_native = 1; expected.health = 0; expected.disposition = 6;
    assert_eq!(strict.state, expected);
    let allowed = checked(before, operation(7));
    expected = before; expected.permits_initial = 1;
    assert_eq!(allowed.state, expected);
    for result in [revoked, reordered, strict, allowed] {
        assert_eq!((result.fresh_pressure, result.allows_upgrade, result.legacy_missing, result.clock_action), (0, 0, 0, 0));
    }
}

#[test]
fn rtt_evidence_age_only_and_primary_query_have_no_hidden_state_or_evidence_effects() {
    let before = healthy();
    for (seconds, atto, fresh) in [(0, -1, 0), (0, 0, 1), (4, 0, 1), (4, 1, 0), (i64::MAX, 0, 0)] {
        let result = checked(before, aged(operation(12), seconds, atto));
        assert_eq!(result.state, before);
        assert_eq!(result.primary_lease_current, fresh);
        assert_eq!((result.fresh_pressure, result.allows_upgrade, result.legacy_missing, result.clock_action), (0, 0, 0, 0));
        assert_eq!(result.validation_disposition, before.disposition);
        let result = checked(before, aged(operation(10), seconds, atto));
        let mut expected = before; expected.age_seconds = seconds; expected.age_attoseconds = atto;
        assert_eq!(result.state, expected);
        assert_eq!(result.primary_lease_current, fresh);
    }
    let mut no_clock = before; no_clock.advancement_present = 0;
    let result = checked(no_clock, operation(10));
    assert_eq!((result.state.age_present, result.state.age_seconds, result.state.age_attoseconds), (0, 0, 0));
    assert_eq!(result.primary_lease_current, 0);
}

#[test]
fn rtt_evidence_fast_positive_commits_only_fence_never_ordinary_reference_or_clock() {
    let mut before = healthy(); before.age_seconds = 1;
    let mut event = aged(native(0.050, 2.0, 101), 2, 0); event.opcode = 1;
    let result = checked(before, event);
    let mut expected = before;
    expected.fence = event.measurement; expected.fence_current_bits = event.current_bits;
    assert_eq!(result.state, expected);
    assert_eq!((result.fresh_pressure, result.allows_upgrade, result.clock_action, result.validation_disposition), (0, 1, 0, 2));
    assert_eq!(result.primary_lease_current, 1);
    assert_eq!(result.state.watermark.responses, 100);
    assert_eq!((result.state.baseline_bits, result.state.age_seconds, result.state.distinct_count), (before.baseline_bits, 1, 1));
}

#[test]
fn rtt_evidence_fast_pressure_preserves_watermark_for_one_ordinary_pressure_decision() {
    let before = healthy();
    let mut event = native(0.200, 2.0, 101); event.opcode = 1;
    let fast = checked(before, event);
    assert_eq!((fast.fresh_pressure, fast.allows_upgrade, fast.validation_disposition, fast.clock_action), (1, 0, 3, 0));
    assert_eq!(fast.state.watermark, before.watermark);
    assert_eq!(fast.state.baseline_bits, before.baseline_bits);
    assert_eq!(fast.state.last_measured_bits, before.last_measured_bits);
    assert_eq!((fast.state.health, fast.state.disposition, fast.state.permits_initial), (0, 6, 0));
    event.opcode = 0;
    let ordinary = checked(fast.state, event);
    assert_eq!((ordinary.fresh_pressure, ordinary.clock_action, ordinary.validation_disposition), (1, 2, 3));
    let duplicate = checked(ordinary.state, event);
    assert_eq!((duplicate.fresh_pressure, duplicate.clock_action, duplicate.validation_disposition), (0, 0, 5));
}

#[test]
fn rtt_evidence_fast_fence_scalar_contradiction_cannot_be_reinterpreted_as_ordinary_advancement() {
    let before = healthy();
    let mut event = native(0.100, 2.0, 101); event.opcode = 1;
    let fast = checked(before, event);
    assert_eq!(fast.state.watermark.responses, 100);
    let contradiction = checked(fast.state, native(0.110, 2.0, 101));
    unknown(contradiction, 6);
    assert_eq!(contradiction.state.watermark.responses, 101);
    assert_eq!(contradiction.state.last_measured_bits, before.last_measured_bits);
    let fixed = checked(contradiction.state, native(0.100, 2.0, 101));
    unknown(fixed, 6);
}

#[test]
fn rtt_evidence_fast_negative_reseeds_identity_and_clears_reference_only_for_pair_change() {
    let before = healthy();
    let mut regression = native(0.100, 0.500, 99); regression.opcode = 1;
    let negative = checked(before, regression);
    assert_eq!((negative.state.watermark, negative.state.disposition, negative.validation_disposition), (regression.measurement, 8, 8));
    assert_eq!(negative.state.baseline_bits, before.baseline_bits);
    assert_eq!(negative.state.age_present, before.age_present);
    let mut replacement = native(0.100, 2.0, 101); replacement.opcode = 1;
    replacement.measurement.fingerprint_words = measurement(b'b', 2.0, 101).fingerprint_words;
    let negative = checked(before, replacement);
    assert_eq!((negative.state.baseline_present, negative.state.distinct_count, negative.state.provisional), (0, 0, 0));
    assert_eq!(negative.state.watermark, replacement.measurement);
    assert_eq!(negative.state.last_measured_bits, before.last_measured_bits);
    assert_eq!(negative.clock_action, 0);
}

#[test]
fn rtt_evidence_fast_route_change_copies_watermark_but_never_healthy_clock_or_baseline() {
    let before = healthy();
    let mut event = native(0.050, 2.0, 101); event.opcode = 1; event.route_changed = 1;
    let result = checked(before, event);
    assert_eq!((result.allows_upgrade, result.validation_disposition, result.clock_action), (1, 2, 0));
    assert_eq!((result.state.health, result.state.disposition, result.state.permits_initial), (0, 6, 0));
    assert_eq!(result.state.watermark, event.measurement);
    assert_eq!(result.state.baseline_bits, before.baseline_bits);
    assert_eq!(result.state.last_measured_bits, before.last_measured_bits);
    assert_eq!(result.state.distinct_count, before.distinct_count);
}

#[test]
fn rtt_evidence_fast_nil_is_unavailable_not_legacy_scalar_authority() {
    let before = healthy();
    let result = checked(before, E { opcode: 1, current_present: 1,
        current_bits: 0.100f64.to_bits(), ..E::default() });
    unknown(result, 6);
    assert_eq!(result.legacy_missing, 0);
    assert_eq!(result.state.baseline_bits, before.baseline_bits);
    assert_eq!(result.state.watermark, before.fence);
    let expired = checked(before, aged(E { opcode: 1, ..native(0.100, 1.0, 100) }, 4, 1));
    assert_eq!((expired.validation_disposition, expired.state.disposition, expired.state.health), (7, 7, 0));
    assert_eq!(expired.state.age_seconds, before.age_seconds);
    assert_eq!(expired.primary_lease_current, 0);
}

#[test]
fn rtt_evidence_fence_copy_is_typed_identity_only_and_never_renews_health() {
    let before = healthy();
    let mut event = native(0.200, 2.0, 101); event.opcode = 11;
    let copied = checked(before, event);
    let mut expected = before; expected.fence = event.measurement; expected.fence_current_bits = event.current_bits;
    assert_eq!(copied.state, expected);
    assert_eq!((copied.fresh_pressure, copied.allows_upgrade, copied.legacy_missing, copied.clock_action), (0, 0, 0, 0));
    let cleared = checked(before, E { opcode: 11, observation_kind: 1, ..E::default() });
    expected = before; expected.fence_present = 0; expected.fence = M::default();
    expected.fence_current_present = 0; expected.fence_current_bits = 0;
    assert_eq!(cleared.state, expected);
    event.current_bits = f64::NAN.to_bits(); rejected(before, event);
    event.current_bits = 0.200f64.to_bits(); event.fingerprint_length = 65; rejected(before, event);
    rejected(before, E { opcode: 11, observation_kind: 1, current_present: 1, current_bits: 0.100f64.to_bits(), ..E::default() });
}

#[test]
fn rtt_evidence_malformed_state_fields_preserve_exact_before_without_authority() {
    let mutators: [fn(&mut S); 30] = [
        |s| s.abi_version = 0, |s| s.abi_version = u32::MAX,
        |s| s.reserved = 1, |s| s.reserved2 = 1, |s| s.reserved3 = 1,
        |s| s.baseline_present = 2, |s| s.bootstrap_count = 3,
        |s| s.disposition = 10, |s| s.health = 3, |s| s.uses_native = 2,
        |s| s.provisional = 2, |s| s.permits_initial = 2, |s| s.distinct_count = 4,
        |s| s.last_measured_present = 2, |s| s.advancement_present = 2, |s| s.age_present = 2,
        |s| s.watermark_present = 2, |s| s.fence_present = 2, |s| s.fence_current_present = 2,
        |s| s.baseline_bits = f64::NAN.to_bits(), |s| s.last_measured_bits = 0,
        |s| s.fence_current_bits = f64::INFINITY.to_bits(),
        |s| s.baseline_present = 0, |s| s.last_measured_present = 0,
        |s| s.age_present = 0, |s| s.watermark_present = 0,
        |s| s.fence_present = 0, |s| s.bootstrap_bits[2] = 1,
        |s| s.age_attoseconds = 1_000_000_000_000_000_000,
        |s| { s.age_seconds = 1; s.age_attoseconds = -1; },
    ];
    for mutate in mutators {
        let mut before = healthy(); before.age_seconds = 1; mutate(&mut before);
        rejected(before, native(0.100, 2.0, 101));
    }
    let mut before = healthy(); before.fence.total_bits = f64::NAN.to_bits();
    rejected(before, native(0.100, 2.0, 101));
    before = healthy(); before.watermark.fingerprint_words[0] = 0;
    rejected(before, native(0.100, 2.0, 101));
}

#[test]
fn rtt_evidence_malformed_event_tags_and_unused_fields_cannot_obtain_authority() {
    let before = healthy();
    let mutators: [fn(&mut E); 10] = [
        |e| e.opcode = 13, |e| e.opcode = u32::MAX,
        |e| e.observation_kind = 3, |e| e.current_present = 2,
        |e| e.route_changed = 2, |e| e.route_changed = 1, |e| e.reserved = 1,
        |e| e.current_present = 0,
        |e| e.age_attoseconds = i64::MIN,
        |e| { e.age_seconds = -1; e.age_attoseconds = 1; },
    ];
    for mutate in mutators { let mut event = native(0.100, 2.0, 101); mutate(&mut event); rejected(before, event); }
    for kind in [0, 1] {
        let mut event = E { observation_kind: kind, ..E::default() };
        event.fingerprint_length = 1; rejected(before, event);
        event.fingerprint_length = 0; event.measurement.responses = 1; rejected(before, event);
    }
    for op in [2, 3, 4, 5, 7, 8, 9, 10, 12] {
        rejected(before, E { opcode: op, current_present: 1, current_bits: 0.100f64.to_bits(), ..E::default() });
        rejected(before, E { opcode: op, observation_kind: 1, ..E::default() });
        if op != 10 && op != 12 { rejected(before, aged(operation(op), 0, 1)); }
    }
    rejected(S::initial(), aged(native(0.100, 1.0, 100), 0, 1));
    rejected(before, operation(6));
    rejected(before, operation(11));
}

#[test]
fn rtt_evidence_well_typed_mixed_legacy_native_states_are_not_semantically_rejected() {
    let before = S { disposition: 0, health: 2, uses_native: 0, provisional: 1,
        distinct_count: 3, advancement_present: 1, age_present: 1,
        last_measured_present: 1, last_measured_bits: 0.100f64.to_bits(), ..S::initial() };
    let result = checked(before, operation(12));
    assert_eq!(result.state, before);
    assert_eq!(result.primary_lease_current, 1);
    let mut before = S::initial(); before.bootstrap_count = 2;
    before.bootstrap_bits = [0.300f64.to_bits(), 0.100f64.to_bits(), 0];
    let result = checked(before, native(0.200, 1.0, 1));
    assert_eq!(result.state.baseline_bits, 0.200f64.to_bits());
    assert_eq!((result.state.bootstrap_count, result.state.distinct_count), (0, 1));
}

// Logical u32 fields first, then both 32-bit halves of every copied u64/i64 field.
// This covers all 84 physical 32-bit words of the 336-byte result without unsafe casts.
fn tamper_word(result: &mut O, index: usize) {
    match index {
        0 => result.abi_version ^= 1, 1 => result.status ^= 1,
        2 => result.fresh_pressure ^= 1, 3 => result.allows_upgrade ^= 1,
        4 => result.legacy_missing ^= 1, 5 => result.clock_action ^= 1,
        6 => result.validation_disposition ^= 1, 7 => result.primary_lease_current ^= 1,
        8 => result.reserved ^= 1, 9 => result.reserved2 ^= 1,
        10 => result.state.abi_version ^= 1, 11 => result.state.reserved ^= 1,
        12 => result.state.baseline_present ^= 1, 13 => result.state.bootstrap_count ^= 1,
        14 => result.state.disposition ^= 1, 15 => result.state.health ^= 1,
        16 => result.state.uses_native ^= 1, 17 => result.state.provisional ^= 1,
        18 => result.state.permits_initial ^= 1, 19 => result.state.distinct_count ^= 1,
        20 => result.state.last_measured_present ^= 1, 21 => result.state.advancement_present ^= 1,
        22 => result.state.age_present ^= 1, 23 => result.state.watermark_present ^= 1,
        24 => result.state.fence_present ^= 1, 25 => result.state.fence_current_present ^= 1,
        26 => result.state.reserved2 ^= 1, 27 => result.state.reserved3 ^= 1,
        28..=83 => {
            let field = (index - 28) / 2;
            let mask = 1u64 << (((index - 28) % 2) * 32);
            match field {
                0 => result.state.baseline_bits ^= mask,
                1 => result.state.last_measured_bits ^= mask,
                2..=4 => result.state.bootstrap_bits[field - 2] ^= mask,
                5 => result.state.age_seconds = ((result.state.age_seconds as u64) ^ mask) as i64,
                6 => result.state.age_attoseconds = ((result.state.age_attoseconds as u64) ^ mask) as i64,
                7..=14 => result.state.watermark.fingerprint_words[field - 7] ^= mask,
                15 => result.state.watermark.total_bits ^= mask,
                16 => result.state.watermark.responses ^= mask,
                17..=24 => result.state.fence.fingerprint_words[field - 17] ^= mask,
                25 => result.state.fence.total_bits ^= mask,
                26 => result.state.fence.responses ^= mask,
                27 => result.state.fence_current_bits ^= mask,
                _ => unreachable!(),
            }
        }
        _ => unreachable!(),
    }
}

#[test]
fn rtt_evidence_actual_verifier_rejects_every_result_word_and_wrong_input_correlation() {
    let before = healthy();
    for event in [native(0.100, 2.0, 101), native(0.200, 2.0, 101), operation(4), operation(5),
        E { opcode: 1, ..native(0.100, 2.0, 101) }, aged(operation(12), 4, 0)] {
        let actual = checked(before, event);
        for word in 0..84 {
            let mut forged = actual; tamper_word(&mut forged, word);
            assert_ne!(forged, actual);
            assert_eq!(verify(before, event, forged), 0, "physical copied word {word}");
        }
        let mut wrong_before = before; wrong_before.reserved = 1;
        assert_eq!(verify(wrong_before, event, actual), 0);
        let mut wrong_event = event; wrong_event.reserved = 1;
        assert_eq!(verify(before, wrong_event, actual), 0);
    }
}
