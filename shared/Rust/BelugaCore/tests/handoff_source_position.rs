//! Boundary and raw-ABI regression tests; independent native Swift parity is separate.
//! These scalar cases do not qualify native browser/phone playback or source identity.
use beluga_core::handoff_source_position::{
    matches, matches_result_is_valid, prepare, prepare_result_is_valid,
    RawDecision, RawMatchFacts, RawPrepareFacts,
};
use std::mem::{align_of, offset_of, size_of};

fn preparation() -> RawPrepareFacts {
    RawPrepareFacts { abi_version: 1, reserved: 0, flags: 127,
        position: 15.0_f64.to_bits(), duration: 120.0_f64.to_bits(), rate: 1.0_f64.to_bits(),
        observed_at_page_ms: 50_000.0_f64.to_bits(), phone_position: 15.0_f64.to_bits() }
}

fn current() -> RawMatchFacts {
    RawMatchFacts { abi_version: 1, reserved: 0, flags: 127,
        anchor_position: 15.0_f64.to_bits(), anchor_duration: 120.0_f64.to_bits(),
        anchor_rate: 1.0_f64.to_bits(), anchor_observed_at_page_ms: 50_000.0_f64.to_bits(),
        phone_position: 15.0_f64.to_bits(), current_position: 15.0_f64.to_bits(),
        current_duration: 120.0_f64.to_bits(), current_rate: 1.0_f64.to_bits(),
        current_observed_at_page_ms: 50_000.0_f64.to_bits() }
}

// Independent guard transcriptions of the exact original 43-line Swift implementation.
// They use no production constants, numeric helpers, classifiers or result validators.
fn frozen_swift_prepare(raw: RawPrepareFacts) -> bool {
    let rate = f64::from_bits(raw.rate);
    let duration = f64::from_bits(raw.duration);
    let position = f64::from_bits(raw.position);
    let phone = f64::from_bits(raw.phone_position);
    let page = f64::from_bits(raw.observed_at_page_ms);
    raw.flags == 127
        && rate.is_finite() && rate > 0.0 && rate <= 16.0
        && duration.is_finite() && duration > 0.0 && duration <= 31_536_000.0
        && position.is_finite() && position >= 0.0 && position < duration
        && phone.is_finite() && phone >= 0.0 && phone < duration
        && page.is_finite() && page >= 0.0 && page <= 9_007_199_254_740_991.0
}

fn frozen_swift_matches(raw: RawMatchFacts) -> bool {
    let elapsed = (f64::from_bits(raw.current_observed_at_page_ms)
        - f64::from_bits(raw.anchor_observed_at_page_ms)) / 1000.0;
    let position = f64::from_bits(raw.current_position);
    if !elapsed.is_finite() || elapsed < 0.0 || elapsed >= 30.0 || raw.flags != 127
        || f64::from_bits(raw.current_duration) != f64::from_bits(raw.anchor_duration)
        || f64::from_bits(raw.current_rate) != f64::from_bits(raw.anchor_rate)
        || !position.is_finite() { return false; }
    (position - (f64::from_bits(raw.anchor_position)
        + elapsed * f64::from_bits(raw.anchor_rate))).abs() <= 1.0
        && (position - f64::from_bits(raw.phone_position)).abs() <= 2.0
}

fn check_prepare(raw: RawPrepareFacts) {
    let before = raw;
    let result = prepare(raw);
    assert_eq!((result.abi_version, result.status, result.allowed, result.reserved),
        (1, 1, u32::from(frozen_swift_prepare(raw)), 0), "prepare input: {raw:?}");
    assert_eq!(raw, before, "copied raw floating payload must not be rewritten");
    assert_eq!(prepare_result_is_valid(raw, result), 1);
}

fn check_matches(raw: RawMatchFacts) {
    let before = raw;
    let result = matches(raw);
    assert_eq!((result.abi_version, result.status, result.allowed, result.reserved),
        (1, 1, u32::from(frozen_swift_matches(raw)), 0), "match input: {raw:?}");
    assert_eq!(raw, before, "copied raw floating payload must not be rewritten");
    assert_eq!(matches_result_is_valid(raw, result), 1);
}

fn invalid() -> RawDecision { RawDecision { abi_version: 1, status: 0, allowed: 0, reserved: 0 } }

#[test]
fn every_native_flag_combination_preserves_missing_and_identity_refusals() {
    for flags in 0..128 {
        let mut p = preparation(); p.flags = flags;
        let mut m = current(); m.flags = flags;
        assert_eq!(prepare(p).allowed, u32::from(flags == 127));
        assert_eq!(matches(m).allowed, u32::from(flags == 127));
        check_prepare(p); check_matches(m);
    }
}

#[test]
fn unknown_bits_wrong_abi_and_reserved_fields_are_malformed_not_business_refusals() {
    for flags in 0..128 {
        for bit in 7..64 {
            let mut p = preparation(); p.flags = flags | (1_u64 << bit);
            let mut m = current(); m.flags = flags | (1_u64 << bit);
            assert_eq!(prepare(p), invalid()); assert_eq!(matches(m), invalid());
            assert_eq!(prepare_result_is_valid(p, invalid()), 0);
            assert_eq!(matches_result_is_valid(m, invalid()), 0);
        }
    }
    for bad in [0, 2, u32::MAX] {
        let mut p = preparation(); p.abi_version = bad;
        let mut m = current(); m.abi_version = bad;
        assert_eq!(prepare(p), invalid()); assert_eq!(matches(m), invalid());
    }
    for bad in [1, 2, u32::MAX] {
        let mut p = preparation(); p.reserved = bad;
        let mut m = current(); m.reserved = bad;
        assert_eq!(prepare(p), invalid()); assert_eq!(matches(m), invalid());
    }
}

#[test]
fn preparation_scalar_edges_and_nonfinite_values_match_frozen_swift() {
    let values = [f64::NEG_INFINITY, -1.0, -f64::from_bits(1), -0.0, 0.0,
        f64::from_bits(1), 1.0, f64::from_bits(16.0_f64.to_bits() - 1), 16.0,
        f64::from_bits(16.0_f64.to_bits() + 1), 119.999, 120.0,
        f64::from_bits(120.0_f64.to_bits() + 1), 31_536_000.0,
        f64::from_bits(31_536_000.0_f64.to_bits() + 1), 9_007_199_254_740_991.0,
        f64::from_bits(9_007_199_254_740_991.0_f64.to_bits() + 1), f64::INFINITY,
        f64::from_bits(0x7ff8_0000_0000_1234), f64::from_bits(0xfff8_0000_0000_5678)];
    for field in 0..5 {
        for value in values {
            let mut raw = preparation();
            match field {
                0 => raw.position = value.to_bits(), 1 => raw.duration = value.to_bits(),
                2 => raw.rate = value.to_bits(), 3 => raw.observed_at_page_ms = value.to_bits(),
                4 => raw.phone_position = value.to_bits(), _ => unreachable!(),
            }
            check_prepare(raw);
        }
    }
    let mut rate = preparation(); rate.rate = 16.0_f64.to_bits();
    assert_eq!(prepare(rate).allowed, 1);
    rate.rate = f64::from_bits(16.0_f64.to_bits() + 1).to_bits();
    assert_eq!(prepare(rate).allowed, 0);
    let mut duration = preparation(); duration.duration = 31_536_000.0_f64.to_bits();
    assert_eq!(prepare(duration).allowed, 1);
    duration.duration = f64::from_bits(31_536_000.0_f64.to_bits() + 1).to_bits();
    assert_eq!(prepare(duration).allowed, 0);
}

#[test]
fn option_absence_is_a_valid_refusal_and_does_not_invent_payload_authority() {
    for mask in [32, 64, 96] {
        for bits in [0, 15.0_f64.to_bits(), u64::MAX, 0x7ff8_0000_0000_1234] {
            let mut p = preparation(); p.flags &= !mask; p.position = bits; p.duration = bits;
            let mut m = current(); m.flags &= !mask; m.current_position = bits; m.current_duration = bits;
            assert_eq!((prepare(p).status, prepare(p).allowed), (1, 0));
            assert_eq!((matches(m).status, matches(m).allowed), (1, 0));
            check_prepare(p); check_matches(m);
        }
    }
}

#[test]
fn exact_mac_one_second_and_phone_two_second_limits_are_inclusive_and_distinct() {
    let mut mac = current(); mac.current_position = 16.0_f64.to_bits();
    assert_eq!(matches(mac).allowed, 1); check_matches(mac);
    mac.current_position = f64::from_bits(16.0_f64.to_bits() + 1).to_bits();
    assert_eq!(matches(mac).allowed, 0); check_matches(mac);
    let mut phone = current(); phone.phone_position = 13.0_f64.to_bits();
    assert_eq!(matches(phone).allowed, 1); check_matches(phone);
    phone.phone_position = f64::from_bits(13.0_f64.to_bits() - 1).to_bits();
    assert_eq!(matches(phone).allowed, 0); check_matches(phone);
    // The native match limit is not the offers reducer's rate-scaled uncertainty.
    let mut fast = current(); fast.anchor_rate = 16.0_f64.to_bits(); fast.current_rate = fast.anchor_rate;
    fast.current_position = 16.5_f64.to_bits();
    assert_eq!(matches(fast).allowed, 0); check_matches(fast);
}

#[test]
fn page_millisecond_clock_zero_and_exclusive_thirty_second_edges_keep_original_domain() {
    let mut raw = current(); raw.anchor_observed_at_page_ms = 0.0_f64.to_bits();
    for page in [-1.0_f64, -0.0, 0.0, 29_999.0, 30_000.0, 30_001.0] {
        raw.current_observed_at_page_ms = page.to_bits();
        raw.current_position = (15.0 + page / 1000.0).to_bits();
        raw.phone_position = raw.current_position;
        let expected = page >= 0.0 && page < 30_000.0;
        assert_eq!(matches(raw).allowed, u32::from(expected)); check_matches(raw);
    }
    let mut milliseconds = current();
    milliseconds.current_observed_at_page_ms = 51_000.0_f64.to_bits();
    milliseconds.current_position = 16.0_f64.to_bits(); milliseconds.phone_position = 16.0_f64.to_bits();
    assert_eq!(matches(milliseconds).allowed, 1); check_matches(milliseconds);
}

#[test]
fn changed_rate_duration_and_all_nonfinite_match_words_match_frozen_swift() {
    let values = [f64::NEG_INFINITY, -1.0, -0.0, 0.0, f64::from_bits(1), 1.0, 2.0, 16.0,
        120.0, f64::INFINITY, f64::from_bits(0x7ff8_0000_0000_1234), f64::from_bits(0xfff8_0000_0000_5678)];
    for field in 0..9 {
        for value in values {
            let mut raw = current();
            match field {
                0 => raw.anchor_position = value.to_bits(), 1 => raw.anchor_duration = value.to_bits(),
                2 => raw.anchor_rate = value.to_bits(), 3 => raw.anchor_observed_at_page_ms = value.to_bits(),
                4 => raw.phone_position = value.to_bits(), 5 => raw.current_position = value.to_bits(),
                6 => raw.current_duration = value.to_bits(), 7 => raw.current_rate = value.to_bits(),
                8 => raw.current_observed_at_page_ms = value.to_bits(), _ => unreachable!(),
            }
            check_matches(raw);
        }
    }
    let mut rate = current(); rate.current_rate = 2.0_f64.to_bits();
    assert_eq!(matches(rate).allowed, 0);
    let mut duration = current(); duration.current_duration = 121.0_f64.to_bits();
    assert_eq!(matches(duration).allowed, 0);
    let mut nan = current(); nan.current_position = 0x7ff8_0000_0000_1234;
    assert_eq!(matches(nan).allowed, 0);
}

#[test]
fn signed_zero_raw_bits_and_original_unissuable_match_inputs_are_not_normalized() {
    let mut p = preparation(); p.position = (-0.0_f64).to_bits(); p.phone_position = (-0.0_f64).to_bits();
    p.observed_at_page_ms = (-0.0_f64).to_bits();
    assert_eq!(prepare(p).allowed, 1); check_prepare(p);
    assert_eq!(p.position, 0x8000_0000_0000_0000);
    let mut negative = current(); negative.anchor_position = 0.0_f64.to_bits();
    negative.phone_position = 0.0_f64.to_bits(); negative.current_position = (-0.5_f64).to_bits();
    assert_eq!(matches(negative).allowed, 1); check_matches(negative);
    // Native snapshot validation separately rejects this unissuable negative position.
    let mut at_end = current(); at_end.anchor_position = 119.0_f64.to_bits();
    at_end.phone_position = 119.0_f64.to_bits(); at_end.current_position = 120.0_f64.to_bits();
    assert_eq!(matches(at_end).allowed, 1); check_matches(at_end);
}

#[test]
fn copied_results_cannot_forge_allow_refuse_abi_status_or_reserved_fields() {
    for flags in [0, 126, 127] {
        let mut p = preparation(); p.flags = flags;
        let mut m = current(); m.flags = flags;
        let p_expected = prepare(p); let m_expected = matches(m);
        for field in 0..4 {
            for bad in [0, 1, 2, u32::MAX] {
                let mut p_out = p_expected; let mut m_out = m_expected;
                match field {
                    0 => { p_out.abi_version = bad; m_out.abi_version = bad; },
                    1 => { p_out.status = bad; m_out.status = bad; },
                    2 => { p_out.allowed = bad; m_out.allowed = bad; },
                    3 => { p_out.reserved = bad; m_out.reserved = bad; },
                    _ => unreachable!(),
                }
                assert_eq!(prepare_result_is_valid(p, p_out), u32::from(p_out == p_expected));
                assert_eq!(matches_result_is_valid(m, m_out), u32::from(m_out == m_expected));
            }
        }
    }
}

#[test]
fn copied_c_layouts_pin_every_word_and_no_pointer_or_native_object() {
    assert_eq!((size_of::<RawPrepareFacts>(), align_of::<RawPrepareFacts>()), (56, 8));
    assert_eq!((offset_of!(RawPrepareFacts, abi_version), offset_of!(RawPrepareFacts, reserved)), (0, 4));
    assert_eq!([offset_of!(RawPrepareFacts, flags), offset_of!(RawPrepareFacts, position),
        offset_of!(RawPrepareFacts, duration), offset_of!(RawPrepareFacts, rate),
        offset_of!(RawPrepareFacts, observed_at_page_ms), offset_of!(RawPrepareFacts, phone_position)],
        [8, 16, 24, 32, 40, 48]);
    assert_eq!((size_of::<RawMatchFacts>(), align_of::<RawMatchFacts>()), (88, 8));
    assert_eq!([offset_of!(RawMatchFacts, flags), offset_of!(RawMatchFacts, anchor_position),
        offset_of!(RawMatchFacts, anchor_duration), offset_of!(RawMatchFacts, anchor_rate),
        offset_of!(RawMatchFacts, anchor_observed_at_page_ms), offset_of!(RawMatchFacts, phone_position),
        offset_of!(RawMatchFacts, current_position), offset_of!(RawMatchFacts, current_duration),
        offset_of!(RawMatchFacts, current_rate), offset_of!(RawMatchFacts, current_observed_at_page_ms)],
        [8, 16, 24, 32, 40, 48, 56, 64, 72, 80]);
    assert_eq!((size_of::<RawDecision>(), align_of::<RawDecision>()), (16, 4));
    assert_eq!([offset_of!(RawDecision, abi_version), offset_of!(RawDecision, status),
        offset_of!(RawDecision, allowed), offset_of!(RawDecision, reserved)], [0, 4, 8, 12]);
}

#[test]
fn actual_c_exports_and_validators_preserve_votes_and_malformed_refusal() {
    use beluga_core::{beluga_core_handoff_source_prepare as export_prepare,
        beluga_core_handoff_source_matches as export_matches,
        beluga_core_handoff_source_prepare_result_is_valid as verify_prepare,
        beluga_core_handoff_source_matches_result_is_valid as verify_matches};
    for flags in 0..128 {
        let mut p = preparation(); p.flags = flags;
        let mut m = current(); m.flags = flags;
        let p_result = export_prepare(p); let m_result = export_matches(m);
        assert_eq!(p_result, prepare(p)); assert_eq!(m_result, matches(m));
        assert_eq!(verify_prepare(p, p_result), 1);
        assert_eq!(verify_matches(m, m_result), 1);
        let mut p_forged = p_result; p_forged.allowed ^= 1;
        let mut m_forged = m_result; m_forged.allowed ^= 1;
        assert_eq!(verify_prepare(p, p_forged), 0);
        assert_eq!(verify_matches(m, m_forged), 0);
    }
    for field in 0..3 {
        let mut p = preparation(); let mut m = current();
        match field {
            0 => { p.abi_version = 2; m.abi_version = 2; },
            1 => { p.reserved = 1; m.reserved = 1; },
            _ => { p.flags |= 128; m.flags |= 128; },
        }
        assert_eq!(export_prepare(p), invalid()); assert_eq!(export_matches(m), invalid());
        assert_eq!(verify_prepare(p, invalid()), 0);
        assert_eq!(verify_matches(m, invalid()), 0);
    }
}
