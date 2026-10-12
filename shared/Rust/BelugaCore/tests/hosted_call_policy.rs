//! Frozen-native/literal assertions bind actual production, not a shadow module.
use beluga_core::hosted_call_policy::{decide_evidence, decide_observation, decide_peer_generation,
    RawEvidenceFacts, RawObservationFacts, RawPeerFacts};
use std::mem::{align_of, offset_of, size_of};

const NONCE: [u8; 16] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
const EPOCH: [u8; 16] = [16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1];

fn observation() -> RawObservationFacts {
    RawObservationFacts { abi_version: 1, reserved: 0, observation_sequence: 11,
        highest_admitted_sequence: 10, observation_challenge_present: 1,
        current_challenge_present: 1, current_protocol_version: 3,
        observation_challenge_sequence: 7, current_challenge_sequence: 7,
        observation_nonce: NONCE, observation_call_epoch_nonce: EPOCH,
        current_nonce: NONCE, current_call_epoch_nonce: EPOCH }
}
fn assert_observation(raw: RawObservationFacts, status: u32, admitted: u32) {
    let result = decide_observation(raw);
    assert_eq!((result.abi_version, result.status, result.value, result.reserved), (1, status, admitted, 0));
}
fn evidence(active: u32, armed: u32) -> RawEvidenceFacts {
    RawEvidenceFacts { abi_version: 1, reserved: 0, active, armed }
}
fn peer(audio: Option<u64>, challenge: Option<u64>, current: u64) -> RawPeerFacts {
    RawPeerFacts { abi_version: 1, reserved: 0,
        audio_present: u32::from(audio.is_some()), challenge_present: u32::from(challenge.is_some()),
        audio_generation: audio.unwrap_or(0), challenge_generation: challenge.unwrap_or(0),
        current_generation: current }
}

// Original native guard plus original protocol-v3 validity. This independent
// frozen transcription calls no Rust production policy/validity/decoder helper.
fn frozen_native_observation(raw: RawObservationFacts) -> bool {
    if raw.observation_sequence <= raw.highest_admitted_sequence
        || raw.observation_challenge_present != 1 || raw.current_challenge_present != 1 {
        return false;
    }
    let current_valid = raw.current_protocol_version == 3 && raw.current_challenge_sequence > 0
        && raw.current_nonce != [0; 16] && raw.current_call_epoch_nonce != [0; 16]
        && raw.current_nonce != raw.current_call_epoch_nonce;
    current_valid && raw.observation_challenge_sequence == raw.current_challenge_sequence
        && raw.observation_nonce == raw.current_nonce
        && raw.observation_call_epoch_nonce == raw.current_call_epoch_nonce
}

#[test]
fn literal_observation_watermarks_are_strict_and_never_wrap_at_u64_max() {
    for (sequence, highest, expected) in [(0, 0, 0), (1, 0, 1), (10, 10, 0),
        (11, 10, 1), (10, 11, 0), (u64::MAX, 0, 1), (0, u64::MAX, 0),
        (u64::MAX, u64::MAX - 1, 1), (u64::MAX, u64::MAX, 0),
        (u64::MAX - 1, u64::MAX, 0)] {
        let mut raw = observation(); raw.observation_sequence = sequence; raw.highest_admitted_sequence = highest;
        assert_observation(raw, 1, expected);
        assert_eq!(frozen_native_observation(raw), expected == 1);
    }
}

#[test]
fn invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error() {
    assert_observation(observation(), 1, 1);
    for (version, expected) in [(i64::MIN, 0), (-1, 0), (0, 0), (1, 0), (2, 0), (3, 1), (4, 0), (i64::MAX, 0)] {
        let mut raw = observation(); raw.current_protocol_version = version;
        assert_observation(raw, 1, expected);
    }
    for (sequence, expected) in [(0, 0), (1, 1), (u64::MAX, 1)] {
        let mut raw = observation(); raw.observation_challenge_sequence = sequence; raw.current_challenge_sequence = sequence;
        assert_observation(raw, 1, expected);
    }
    for (observation_present, current_present) in [(0, 0), (0, 1), (1, 0)] {
        let mut raw = observation(); raw.observation_challenge_present = observation_present;
        raw.current_challenge_present = current_present;
        // Absence payload is deliberately not normalized or newly rejected.
        raw.current_protocol_version = i64::MIN;
        raw.current_challenge_sequence = u64::MAX;
        assert_observation(raw, 1, 0);
    }
    let mut zero_nonce = observation(); zero_nonce.observation_nonce = [0; 16]; zero_nonce.current_nonce = [0; 16];
    assert_observation(zero_nonce, 1, 0);
    let mut zero_epoch = observation(); zero_epoch.observation_call_epoch_nonce = [0; 16]; zero_epoch.current_call_epoch_nonce = [0; 16];
    assert_observation(zero_epoch, 1, 0);
    let mut same = observation(); same.observation_call_epoch_nonce = NONCE; same.current_call_epoch_nonce = NONCE;
    assert_observation(same, 1, 0);
}

#[test]
fn old_sequence_nonce_and_epoch_each_refuse_independently() {
    let mut old_sequence = observation(); old_sequence.observation_challenge_sequence = 6;
    assert_observation(old_sequence, 1, 0);
    for byte in 0..16 {
        let mut changed_nonce = observation(); changed_nonce.observation_nonce[byte] ^= 0x80;
        assert_observation(changed_nonce, 1, 0);
        let mut changed_epoch = observation(); changed_epoch.observation_call_epoch_nonce[byte] ^= 0x80;
        assert_observation(changed_epoch, 1, 0);
        let mut changed_current_nonce = observation(); changed_current_nonce.current_nonce[byte] ^= 0x80;
        assert_observation(changed_current_nonce, 1, 0);
        let mut changed_current_epoch = observation(); changed_current_epoch.current_call_epoch_nonce[byte] ^= 0x80;
        assert_observation(changed_current_epoch, 1, 0);
    }
}

#[test]
fn cartesian_boundary_observations_match_frozen_original_without_identity_truncation() {
    let versions = [i64::MIN, 0, 2, 3, 4, i64::MAX];
    let counters = [0, 1, 7, u64::MAX - 1, u64::MAX];
    for &version in &versions {
        for &observation_sequence in &counters {
            for &highest in &counters {
                for &challenge_sequence in &counters {
                    for present in [(0, 0), (0, 1), (1, 0), (1, 1)] {
                        let mut raw = observation();
                        raw.current_protocol_version = version;
                        raw.observation_sequence = observation_sequence; raw.highest_admitted_sequence = highest;
                        raw.observation_challenge_sequence = challenge_sequence;
                        raw.current_challenge_sequence = challenge_sequence;
                        raw.observation_challenge_present = present.0; raw.current_challenge_present = present.1;
                        assert_observation(raw, 1, u32::from(frozen_native_observation(raw)));
                    }
                }
            }
        }
    }
}

#[test]
fn four_literal_evidence_states_distinguish_poison_from_empty_prospective_arm() {
    for (active, armed, value) in [(0, 0, 1), (0, 1, 2), (1, 0, 3), (1, 1, 0)] {
        let raw = evidence(active, armed);
        let result = decide_evidence(raw);
        assert_eq!((result.abi_version, result.status, result.value, result.reserved), (1, 1, value, 0));
        assert_eq!(beluga_core::beluga_core_hosted_call_evidence(raw), result);
    }
}

#[test]
fn literal_peer_fence_distinguishes_absence_zero_and_extreme_generation() {
    let cases = [
        (None, None, 0, 0), (Some(0), Some(0), 0, 0), (None, Some(7), 7, 0),
        (Some(7), None, 7, 0), (Some(6), Some(7), 7, 0), (Some(7), Some(6), 7, 0),
        (Some(7), Some(7), 7, 1), (Some(1), Some(1), 1, 1),
        (Some(u64::MAX), Some(u64::MAX), u64::MAX, 1),
        (Some(u64::MAX - 1), Some(u64::MAX), u64::MAX, 0),
        (Some(0), Some(7), 7, 0), (Some(7), Some(0), 7, 0),
    ];
    for &(audio, challenge, current, value) in &cases {
        let raw = peer(audio, challenge, current);
        let result = decide_peer_generation(raw);
        assert_eq!((result.abi_version, result.status, result.value, result.reserved), (1, 1, value, 0));
        assert_eq!(beluga_core::beluga_core_hosted_call_peer_generation(raw), result);
    }
    // Frozen direct native optional-comparison oracle, not core's admission.
    let generations = [None, Some(0), Some(1), Some(7), Some(u64::MAX)];
    for &audio in &generations {
        for &challenge in &generations {
            for current in [0, 1, 7, u64::MAX] {
                let original = current > 0 && audio == Some(current) && challenge == Some(current);
                assert_eq!(decide_peer_generation(peer(audio, challenge, current)).value, u32::from(original));
            }
        }
    }
    let mut absent = peer(None, None, 7);
    absent.audio_generation = u64::MAX; absent.challenge_generation = u64::MAX;
    assert_eq!((decide_peer_generation(absent).status, decide_peer_generation(absent).value), (1, 0));
}

#[test]
fn invalid_observation_fields_refuse_instead_of_authorizing() {
    for field in 0..4 {
        for bad in [2, u32::MAX] {
            let mut raw = observation();
            match field { 0 => raw.abi_version = bad, 1 => raw.reserved = bad,
                2 => raw.observation_challenge_present = bad, 3 => raw.current_challenge_present = bad,
                _ => unreachable!() }
            assert_observation(raw, 0, 0);
        }
    }
    let mut bad = observation(); bad.abi_version = 0; assert_observation(bad, 0, 0);
    let mut bad = observation(); bad.reserved = 1; assert_observation(bad, 0, 0);
}

#[test]
fn invalid_evidence_fields_do_not_alias_legitimate_poison() {
    for (active, armed) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
        for field in 0..4 {
            for bad in [2, u32::MAX] {
                let mut raw = evidence(active, armed);
                match field { 0 => raw.abi_version = bad, 1 => raw.reserved = bad,
                    2 => raw.active = bad, 3 => raw.armed = bad, _ => unreachable!() }
                let result = decide_evidence(raw);
                assert_eq!((result.abi_version, result.status, result.value, result.reserved), (1, 0, 0, 0));
            }
        }
        let mut bad = evidence(active, armed); bad.abi_version = 0;
        assert_eq!(decide_evidence(bad).status, 0);
        let mut bad = evidence(active, armed); bad.reserved = 1;
        assert_eq!(decide_evidence(bad).status, 0);
    }
}

#[test]
fn invalid_peer_fields_refuse_even_with_matching_generation_payloads() {
    for base in [peer(Some(7), Some(7), 7), peer(None, None, 7), peer(Some(0), Some(0), 0)] {
        for field in 0..4 {
            for bad in [2, u32::MAX] {
                let mut raw = base;
                match field { 0 => raw.abi_version = bad, 1 => raw.reserved = bad,
                    2 => raw.audio_present = bad, 3 => raw.challenge_present = bad,
                    _ => unreachable!() }
                let result = decide_peer_generation(raw);
                assert_eq!((result.abi_version, result.status, result.value, result.reserved), (1, 0, 0, 0));
            }
        }
        // Lower ABI and the smallest nonzero reserved field are independent
        // faults, including matching, absent, and zero-generation payloads.
        for (version, reserved) in [(0, 0), (1, 1)] {
            let mut raw = base;
            raw.abi_version = version;
            raw.reserved = reserved;
            let result = decide_peer_generation(raw);
            assert_eq!((result.abi_version, result.status, result.value, result.reserved), (1, 0, 0, 0));
        }
    }
}

#[test]
fn uuid_bytes_layout_and_observation_c_export_are_exact() {
    assert_eq!((size_of::<RawObservationFacts>(), align_of::<RawObservationFacts>()), (120, 8));
    assert_eq!(offset_of!(RawObservationFacts, observation_nonce), 56);
    assert_eq!(offset_of!(RawObservationFacts, current_call_epoch_nonce), 104);
    assert_eq!(size_of::<RawEvidenceFacts>(), 16);
    assert_eq!((size_of::<RawPeerFacts>(), align_of::<RawPeerFacts>()), (40, 8));
    assert_eq!(size_of::<beluga_core::hosted_call_policy::RawDecision>(), 16);
    let raw = observation();
    assert_eq!(beluga_core::beluga_core_hosted_call_observation(raw), decide_observation(raw));
    assert_eq!(raw.observation_nonce, NONCE);
    assert_eq!(raw.current_call_epoch_nonce, EPOCH);
}
