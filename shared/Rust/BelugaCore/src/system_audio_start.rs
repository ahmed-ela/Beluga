//! Select a native system-audio operation from copied ownership facts only.
#![forbid(unsafe_code)]

use core::mem::size_of;

pub const ABI_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Facts {
    pub is_live: bool,
    pub is_paused_for_recovery: bool,
    pub has_source: bool,
    pub has_sink: bool,
    pub has_valid_authorization: bool,
    pub peer_generation_matches: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StartMode { AlreadyLive, ResumeExisting, StartNew }

pub fn start_mode(facts: Facts) -> Option<StartMode> {
    if facts.is_live && !facts.is_paused_for_recovery && facts.has_source
        && facts.has_sink && facts.has_valid_authorization && facts.peer_generation_matches {
        return Some(StartMode::AlreadyLive);
    }
    if !facts.is_live && facts.is_paused_for_recovery && facts.has_source
        && facts.has_sink && !facts.has_valid_authorization && facts.peer_generation_matches {
        return Some(StartMode::ResumeExisting);
    }
    // The original native policy deliberately does not inspect peer generation
    // when no source, sink, or authorization exists. Preserve both boolean cases.
    if !facts.is_live && !facts.is_paused_for_recovery && !facts.has_source
        && !facts.has_sink && !facts.has_valid_authorization {
        return Some(StartMode::StartNew);
    }
    None
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawFacts {
    pub abi_version: u32,
    pub reserved: u32,
    pub is_live: u32,
    pub is_paused_for_recovery: u32,
    pub has_source: u32,
    pub has_sink: u32,
    pub has_valid_authorization: u32,
    pub peer_generation_matches: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawDecision {
    pub abi_version: u32,
    /// 0 = invalid ABI input; 1 = accepted, including a legitimate no-match.
    pub status: u32,
    /// 0 = no match; 1 = alreadyLive; 2 = resumeExisting; 3 = startNew.
    pub mode: u32,
    pub reserved: u32,
}

const _: [(); 32] = [(); size_of::<RawFacts>()];
const _: [(); 16] = [(); size_of::<RawDecision>()];

fn boolean(raw: u32) -> Option<bool> {
    match raw { 0 => Some(false), 1 => Some(true), _ => None }
}

pub fn decide(raw: RawFacts) -> RawDecision {
    let invalid = RawDecision { abi_version: ABI_VERSION, status: 0, mode: 0, reserved: 0 };
    if raw.abi_version != ABI_VERSION || raw.reserved != 0 { return invalid; }
    let Some(is_live) = boolean(raw.is_live) else { return invalid; };
    let Some(is_paused_for_recovery) = boolean(raw.is_paused_for_recovery) else { return invalid; };
    let Some(has_source) = boolean(raw.has_source) else { return invalid; };
    let Some(has_sink) = boolean(raw.has_sink) else { return invalid; };
    let Some(has_valid_authorization) = boolean(raw.has_valid_authorization) else { return invalid; };
    let Some(peer_generation_matches) = boolean(raw.peer_generation_matches) else { return invalid; };
    let result = start_mode(Facts { is_live, is_paused_for_recovery, has_source, has_sink,
        has_valid_authorization, peer_generation_matches });
    RawDecision {
        abi_version: ABI_VERSION, status: 1, reserved: 0,
        mode: match result { None => 0, Some(StartMode::AlreadyLive) => 1,
            Some(StartMode::ResumeExisting) => 2, Some(StartMode::StartNew) => 3 },
    }
}
