//! Copied BlackHole output-format policy; native effects remain in Swift.
//! Original evaluate preimage: a978c83a59acc3b5e1ec340c6b3681afe417197dbc2ffd75e6e59282b5c4b1f0.
//! This pure module owns no native reads, queue, authorization, identity, clock,
//! callback, route, disposal, or diagnostic effect. No Swift success fallback.
#![forbid(unsafe_code)]

pub const ABI_VERSION: u32 = 1;
pub const REQUIRED_SAMPLE_RATE: f64 = 48_000.0;
// Pinned CoreAudioBaseTypes.h: 'lpcm', (1U << 2) | (1U << 3).
pub const LINEAR_PCM: u32 = 0x6c70_636d;
pub const SIGNED_INTEGER_PACKED: u32 = 12;

pub const STREAM_DESCRIPTION_STATUS: u32 = 1;
pub const DEVICE_SAMPLE_RATE_STATUS: u32 = 2;
pub const DEVICE_CHANNEL_COUNT_STATUS: u32 = 3;
pub const CONVERTER_ERROR_READ_STATUS: u32 = 4;
pub const STREAM_SAMPLE_RATE: u32 = 5;
pub const STREAM_FORMAT_ID: u32 = 6;
pub const STREAM_FORMAT_FLAGS: u32 = 7;
pub const STREAM_BYTES_PER_PACKET: u32 = 8;
pub const STREAM_FRAMES_PER_PACKET: u32 = 9;
pub const STREAM_BYTES_PER_FRAME: u32 = 10;
pub const STREAM_CHANNELS_PER_FRAME: u32 = 11;
pub const STREAM_BITS_PER_CHANNEL: u32 = 12;
pub const STREAM_RESERVED: u32 = 13;
pub const DEVICE_SAMPLE_RATE: u32 = 14;
pub const DEVICE_CHANNEL_COUNT: u32 = 15;
pub const CONVERTER_ERROR: u32 = 16;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawFacts {
    pub abi_version: u32,
    /// Wire guard, distinct from stream_reserved in the native ASBD.
    pub wire_reserved: u32,
    pub stream_description_status: i32,
    pub device_sample_rate_status: i32,
    pub device_channel_count_status: i32,
    pub converter_error_read_status: i32,
    pub stream_sample_rate_bits: u64,
    pub stream_format_id: u32,
    pub stream_format_flags: u32,
    pub stream_bytes_per_packet: u32,
    pub stream_frames_per_packet: u32,
    pub stream_bytes_per_frame: u32,
    pub stream_channels_per_frame: u32,
    pub stream_bits_per_channel: u32,
    pub stream_reserved: u32,
    pub device_sample_rate_bits: u64,
    pub device_channel_count: u32,
    pub converter_error: u32,
}

/// Accepted observations copy all original twelve fields. Rejections carry
/// a zero observation, not invented or partially trusted native evidence.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawObservation {
    pub sample_rate_bits: u64,
    pub format_id: u32,
    pub format_flags: u32,
    pub bytes_per_packet: u32,
    pub frames_per_packet: u32,
    pub bytes_per_frame: u32,
    pub channels_per_frame: u32,
    pub bits_per_channel: u32,
    pub stream_reserved: u32,
    pub device_sample_rate_bits: u64,
    pub device_channel_count: u32,
    pub converter_error: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawResult {
    pub abi_version: u32,
    /// 0 malformed wire; 1 well-formed projection, including a known rejection.
    pub status: u32,
    pub accepted: u32,
    /// 0 accepted (or malformed wire), otherwise the exact ordered reason 1..16.
    pub reason: u32,
    /// Only reasons 1..4 populate this original signed OSStatus.
    pub actual_core_audio_status: i32,
    /// Only reasons 6..13, 15 and 16 populate this full-width UInt32.
    pub actual_u32: u32,
    /// Only reasons 5 and 14 populate the original Double bit pattern.
    pub actual_rate_bits: u64,
    pub observation: RawObservation,
    pub wire_reserved: u64,
}

fn invalid() -> RawResult {
    RawResult { abi_version: ABI_VERSION, ..RawResult::default() }
}

fn rejection(reason: u32, status: i32, word: u32, rate_bits: u64) -> RawResult {
    RawResult { abi_version: ABI_VERSION, status: 1, reason,
        actual_core_audio_status: status, actual_u32: word,
        actual_rate_bits: rate_bits, ..RawResult::default() }
}

/// Exactly the sixteen original guards, in original order. Native getters must
/// already have run eagerly before these scalar facts are copied into this call.
pub fn decide(facts: RawFacts) -> RawResult {
    if facts.abi_version != ABI_VERSION || facts.wire_reserved != 0 { return invalid(); }
    if facts.stream_description_status != 0 {
        return rejection(STREAM_DESCRIPTION_STATUS, facts.stream_description_status, 0, 0);
    }
    if facts.device_sample_rate_status != 0 {
        return rejection(DEVICE_SAMPLE_RATE_STATUS, facts.device_sample_rate_status, 0, 0);
    }
    if facts.device_channel_count_status != 0 {
        return rejection(DEVICE_CHANNEL_COUNT_STATUS, facts.device_channel_count_status, 0, 0);
    }
    if facts.converter_error_read_status != 0 {
        return rejection(CONVERTER_ERROR_READ_STATUS, facts.converter_error_read_status, 0, 0);
    }
    if f64::from_bits(facts.stream_sample_rate_bits) != REQUIRED_SAMPLE_RATE {
        return rejection(STREAM_SAMPLE_RATE, 0, 0, facts.stream_sample_rate_bits);
    }
    if facts.stream_format_id != LINEAR_PCM {
        return rejection(STREAM_FORMAT_ID, 0, facts.stream_format_id, 0);
    }
    if facts.stream_format_flags != SIGNED_INTEGER_PACKED {
        return rejection(STREAM_FORMAT_FLAGS, 0, facts.stream_format_flags, 0);
    }
    if facts.stream_bytes_per_packet != 2 {
        return rejection(STREAM_BYTES_PER_PACKET, 0, facts.stream_bytes_per_packet, 0);
    }
    if facts.stream_frames_per_packet != 1 {
        return rejection(STREAM_FRAMES_PER_PACKET, 0, facts.stream_frames_per_packet, 0);
    }
    if facts.stream_bytes_per_frame != 2 {
        return rejection(STREAM_BYTES_PER_FRAME, 0, facts.stream_bytes_per_frame, 0);
    }
    if facts.stream_channels_per_frame != 1 {
        return rejection(STREAM_CHANNELS_PER_FRAME, 0, facts.stream_channels_per_frame, 0);
    }
    if facts.stream_bits_per_channel != 16 {
        return rejection(STREAM_BITS_PER_CHANNEL, 0, facts.stream_bits_per_channel, 0);
    }
    if facts.stream_reserved != 0 {
        return rejection(STREAM_RESERVED, 0, facts.stream_reserved, 0);
    }
    if f64::from_bits(facts.device_sample_rate_bits) != REQUIRED_SAMPLE_RATE {
        return rejection(DEVICE_SAMPLE_RATE, 0, 0, facts.device_sample_rate_bits);
    }
    if facts.device_channel_count != 1 {
        return rejection(DEVICE_CHANNEL_COUNT, 0, facts.device_channel_count, 0);
    }
    if facts.converter_error != 0 {
        return rejection(CONVERTER_ERROR, 0, facts.converter_error, 0);
    }
    RawResult { abi_version: ABI_VERSION, status: 1, accepted: 1,
        observation: RawObservation {
            sample_rate_bits: facts.stream_sample_rate_bits,
            format_id: facts.stream_format_id, format_flags: facts.stream_format_flags,
            bytes_per_packet: facts.stream_bytes_per_packet,
            frames_per_packet: facts.stream_frames_per_packet,
            bytes_per_frame: facts.stream_bytes_per_frame,
            channels_per_frame: facts.stream_channels_per_frame,
            bits_per_channel: facts.stream_bits_per_channel,
            stream_reserved: facts.stream_reserved,
            device_sample_rate_bits: facts.device_sample_rate_bits,
            device_channel_count: facts.device_channel_count,
            converter_error: facts.converter_error,
        }, ..RawResult::default() }
}

/// Authoritative, non-injectable whole-result correlation. Known rejections are
/// valid; malformed facts never validate, including against the canonical invalid result.
pub fn result_is_valid(facts: RawFacts, result: RawResult) -> u32 {
    let expected = decide(facts);
    u32::from(expected.status == 1 && result == expected)
}
