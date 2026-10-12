//! Hosted-call scalar admission/projection only. No callback ordering, high-water
//! mutation, UUID generation, authorization ownership, or evidence transmission.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;
pub const CURRENT_PROTOCOL_VERSION: i64 = 3;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ObservationChallenge {
    pub sequence: u64,
    pub nonce: [u8; 16],
    pub call_epoch_nonce: [u8; 16],
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CurrentChallenge {
    pub protocol_version: i64,
    pub sequence: u64,
    pub nonce: [u8; 16],
    pub call_epoch_nonce: [u8; 16],
}

impl CurrentChallenge {
    fn is_valid(self) -> bool {
        self.protocol_version == CURRENT_PROTOCOL_VERSION && self.sequence > 0
            && self.nonce != [0; 16] && self.call_epoch_nonce != [0; 16]
            && self.nonce != self.call_epoch_nonce
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ObservationFacts {
    pub observation_sequence: u64,
    pub highest_admitted_sequence: u64,
    pub observation_challenge: Option<ObservationChallenge>,
    pub current_challenge: Option<CurrentChallenge>,
}

pub fn observation_admits(facts: ObservationFacts) -> bool {
    if facts.observation_sequence <= facts.highest_admitted_sequence { return false; }
    let Some(observation) = facts.observation_challenge else { return false; };
    let Some(current) = facts.current_challenge else { return false; };
    current.is_valid() && observation.sequence == current.sequence
        && observation.nonce == current.nonce
        && observation.call_epoch_nonce == current.call_epoch_nonce
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum EvidenceState { Inactive, PreflightArmed, Active }

pub fn evidence_state(active: bool, armed: bool) -> Option<EvidenceState> {
    match (active, armed) {
        (true, false) => Some(EvidenceState::Active),
        (false, true) => Some(EvidenceState::PreflightArmed),
        (false, false) => Some(EvidenceState::Inactive),
        (true, true) => None,
    }
}

pub fn peer_generation_admits(audio: Option<u64>, challenge: Option<u64>, current: u64) -> bool {
    current > 0 && audio == Some(current) && challenge == Some(current)
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawObservationFacts {
    pub abi_version: u32,
    pub reserved: u32,
    pub observation_sequence: u64,
    pub highest_admitted_sequence: u64,
    pub observation_challenge_present: u32,
    pub current_challenge_present: u32,
    pub current_protocol_version: i64,
    pub observation_challenge_sequence: u64,
    pub current_challenge_sequence: u64,
    pub observation_nonce: [u8; 16],
    pub observation_call_epoch_nonce: [u8; 16],
    pub current_nonce: [u8; 16],
    pub current_call_epoch_nonce: [u8; 16],
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawEvidenceFacts {
    pub abi_version: u32,
    pub reserved: u32,
    pub active: u32,
    pub armed: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawPeerFacts {
    pub abi_version: u32,
    pub reserved: u32,
    pub audio_present: u32,
    pub challenge_present: u32,
    pub audio_generation: u64,
    pub challenge_generation: u64,
    pub current_generation: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawDecision {
    pub abi_version: u32,
    /// 0 = invalid bridge input; 1 = accepted, including legitimate refusal/None.
    pub status: u32,
    /// Admission: 0 = false, 1 = true. Evidence: 0 = None, 1 = inactive,
    /// 2 = preflightArmed, 3 = active. Decoding is function-specific and closed.
    pub value: u32,
    pub reserved: u32,
}

const _: [(); 120] = [(); size_of::<RawObservationFacts>()];
const _: [(); 16] = [(); size_of::<RawEvidenceFacts>()];
const _: [(); 40] = [(); size_of::<RawPeerFacts>()];
const _: [(); 16] = [(); size_of::<RawDecision>()];
const _: [(); 8] = [(); align_of::<RawObservationFacts>()];
const _: [(); 8] = [(); align_of::<RawPeerFacts>()];

fn boolean(raw: u32) -> Option<bool> {
    match raw { 0 => Some(false), 1 => Some(true), _ => None }
}
fn invalid() -> RawDecision {
    RawDecision { abi_version: ABI_VERSION, status: 0, value: 0, reserved: 0 }
}
fn accepted(value: u32) -> RawDecision {
    RawDecision { abi_version: ABI_VERSION, status: 1, value, reserved: 0 }
}

pub fn decide_observation(raw: RawObservationFacts) -> RawDecision {
    if raw.abi_version != ABI_VERSION || raw.reserved != 0 { return invalid(); }
    let Some(observation_present) = boolean(raw.observation_challenge_present) else { return invalid(); };
    let Some(current_present) = boolean(raw.current_challenge_present) else { return invalid(); };
    // Payload under a valid absent tag is ignored, not silently converted into
    // a present zero-valued challenge and not subjected to invented zeroing rules.
    let observation_challenge = observation_present.then_some(ObservationChallenge {
        sequence: raw.observation_challenge_sequence,
        nonce: raw.observation_nonce,
        call_epoch_nonce: raw.observation_call_epoch_nonce,
    });
    let current_challenge = current_present.then_some(CurrentChallenge {
        protocol_version: raw.current_protocol_version,
        sequence: raw.current_challenge_sequence,
        nonce: raw.current_nonce,
        call_epoch_nonce: raw.current_call_epoch_nonce,
    });
    accepted(u32::from(observation_admits(ObservationFacts {
        observation_sequence: raw.observation_sequence,
        highest_admitted_sequence: raw.highest_admitted_sequence,
        observation_challenge, current_challenge,
    })))
}

pub fn decide_evidence(raw: RawEvidenceFacts) -> RawDecision {
    if raw.abi_version != ABI_VERSION || raw.reserved != 0 { return invalid(); }
    let Some(active) = boolean(raw.active) else { return invalid(); };
    let Some(armed) = boolean(raw.armed) else { return invalid(); };
    accepted(match evidence_state(active, armed) { None => 0,
        Some(EvidenceState::Inactive) => 1, Some(EvidenceState::PreflightArmed) => 2,
        Some(EvidenceState::Active) => 3 })
}

pub fn decide_peer_generation(raw: RawPeerFacts) -> RawDecision {
    if raw.abi_version != ABI_VERSION || raw.reserved != 0 { return invalid(); }
    let Some(audio_present) = boolean(raw.audio_present) else { return invalid(); };
    let Some(challenge_present) = boolean(raw.challenge_present) else { return invalid(); };
    accepted(u32::from(peer_generation_admits(audio_present.then_some(raw.audio_generation),
        challenge_present.then_some(raw.challenge_generation), raw.current_generation)))
}
