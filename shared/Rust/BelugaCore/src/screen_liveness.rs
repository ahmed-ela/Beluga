//! Copied client screen-liveness diagnostics, never capture/input authority.
#![forbid(unsafe_code)]

pub const ABI_VERSION: u64 = 1;
pub const FRESH_PRESENTATION_NS: u64 = 2_500_000_000;
pub const MAX_PRESENTATION_AGE_MS: u64 = 86_400_000;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawOptional { pub present: u64, pub value: u64 }
impl RawOptional {
    pub fn some(value: u64) -> Self { Self { present: 1, value } }
    fn value(self) -> Option<u64> { (self.present == 1).then_some(self.value) }
    fn valid(self) -> bool { self.present <= 1 && (self.present == 1 || self.value == 0) }
    fn from(value: Option<u64>) -> Self { value.map(Self::some).unwrap_or_default() }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawSample {
    pub generation: u64,
    pub observed_at: u64,
    pub track_attached: u64,
    pub cover: u64,
    pub inbound_present: u64,
    pub inbound_bytes: RawOptional,
    pub inbound_packets: RawOptional,
    pub decoded_frames: RawOptional,
    pub inbound_width: RawOptional,
    pub inbound_height: RawOptional,
    pub frames_per_second_bits: RawOptional,
    pub render_present: u64,
    pub presented_frames: u64,
    pub content_samples: u64,
    pub content_changes: u64,
    pub presented_at: u64,
    pub render_width_bits: u64,
    pub render_height_bits: u64,
}
impl RawSample {
    pub fn valid(self) -> bool {
        self.track_attached <= 1 && self.cover <= 4 && self.inbound_present <= 1
            && self.render_present <= 1
            && [self.inbound_bytes, self.inbound_packets, self.decoded_frames,
                self.inbound_width, self.inbound_height, self.frames_per_second_bits]
                .iter().all(|v| v.valid())
            && (self.inbound_present == 1 || [self.inbound_bytes, self.inbound_packets,
                self.decoded_frames, self.inbound_width, self.inbound_height,
                self.frames_per_second_bits].iter().all(|v| *v == RawOptional::default()))
            && (self.render_present == 1 || [self.presented_frames, self.content_samples,
                self.content_changes, self.presented_at, self.render_width_bits,
                self.render_height_bits].iter().all(|v| *v == 0))
    }
    fn counters(self) -> [Option<u64>; 6] {
        [self.inbound_bytes.value(), self.inbound_packets.value(), self.decoded_frames.value(),
            (self.render_present == 1).then_some(self.presented_frames),
            (self.render_present == 1).then_some(self.content_samples),
            (self.render_present == 1).then_some(self.content_changes)]
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawState {
    pub previous_present: u64,
    pub last_change_at: RawOptional,
    pub previous: RawSample,
}
impl RawState {
    pub fn valid(self) -> bool {
        self.previous_present <= 1 && self.last_change_at.valid()
            && self.previous.valid()
            && (self.previous_present == 1
                || (self.previous == RawSample::default()
                    && self.last_change_at == RawOptional::default()))
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawSnapshot {
    pub liveness: u64,
    pub reset_reason: u64,
    pub generation: u64,
    pub track_attached: u64,
    pub cover: u64,
    pub inbound_bytes: RawOptional,
    pub inbound_byte_delta: RawOptional,
    pub inbound_packets: RawOptional,
    pub inbound_packet_delta: RawOptional,
    pub decoded_frames: RawOptional,
    pub decoded_frame_delta: RawOptional,
    pub presented_frames: RawOptional,
    pub presented_frame_delta: RawOptional,
    pub content_samples: RawOptional,
    pub content_sample_delta: RawOptional,
    pub content_changes: RawOptional,
    pub content_change_delta: RawOptional,
    pub presentation_age_ms: RawOptional,
    pub frame_width: RawOptional,
    pub frame_height: RawOptional,
    pub frames_per_second_bits: RawOptional,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawResult {
    pub abi_version: u64,
    pub status: u64,
    pub reserved: u64,
    pub state: RawState,
    pub snapshot: RawSnapshot,
}

fn delta(current: Option<u64>, previous: Option<u64>) -> Option<u64> {
    current.zip(previous).and_then(|(current, previous)| current.checked_sub(previous))
}
fn dimension(raw: Option<u64>) -> Option<u64> {
    raw.filter(|bits| (1..=32_768).contains(&(*bits as i64)))
}
fn valid_fps(raw: Option<u64>) -> Option<u64> {
    raw.filter(|bits| {
        let value = f64::from_bits(*bits);
        value.is_finite() && (0.0..=1_000.0).contains(&value)
    })
}

/// No clock monotonicity or nonzero-generation constraint is invented here.
pub fn observe(abi_version: u64, before: RawState, sample: RawSample) -> RawResult {
    if abi_version != ABI_VERSION || !before.valid() || !sample.valid() {
        return RawResult { abi_version: ABI_VERSION, status: 3, state: before,
            ..RawResult::default() };
    }
    let current = sample.counters();
    let previous = before.previous.counters();
    let reset_reason = if before.previous_present == 0 { 1 }
        else if before.previous.generation != sample.generation { 2 }
        else if current.iter().zip(previous).any(|(current, previous)|
            current.zip(previous).is_some_and(|(current, previous)| current < previous)) { 3 }
        else { 0 };
    let deltas: [Option<u64>; 6] = std::array::from_fn(|i|
        if reset_reason == 0 { delta(current[i], previous[i]) } else { None });
    let last_change = if reset_reason != 0 { None }
        else if deltas[5].is_some_and(|value| value > 0) { Some(sample.observed_at) }
        else { before.last_change_at.value() };
    let age = (sample.render_present == 1).then(|| {
        let ns = if sample.observed_at >= sample.presented_at {
            sample.observed_at - sample.presented_at
        } else { 0 };
        (ns / 1_000_000).min(MAX_PRESENTATION_AGE_MS)
    });
    let presentation_fresh = age.is_some_and(|age| age <= FRESH_PRESENTATION_NS / 1_000_000);
    let content_fresh = last_change.is_some_and(|change|
        sample.observed_at >= change && sample.observed_at - change <= FRESH_PRESENTATION_NS);
    let liveness = if sample.cover == 1 { 0 }
        else if sample.cover != 0 { 1 }
        else if sample.track_attached == 0 { 2 }
        else if reset_reason != 0 { 3 }
        else if deltas[3].is_some_and(|value| value > 0) {
            if deltas[5].is_some_and(|value| value > 0) { 8 } else { 7 }
        } else if presentation_fresh && sample.content_samples > 0 {
            if content_fresh { 8 } else { 7 }
        } else {
            let inbound = [deltas[0], deltas[1]];
            if inbound.iter().any(Option::is_some) && inbound.iter().flatten().all(|value| *value == 0) { 4 }
            else if inbound.iter().flatten().any(|value| *value > 0) {
                match deltas[2] { Some(0) => 5, Some(_) => 6, None => 3 }
            } else if deltas[2].is_some_and(|value| value > 0) { 6 }
            else { 3 }
        };
    let render_width = (sample.render_present == 1).then_some(sample.render_width_bits);
    let render_height = (sample.render_present == 1).then_some(sample.render_height_bits);
    let snapshot = RawSnapshot {
        liveness, reset_reason, generation: sample.generation,
        track_attached: sample.track_attached, cover: sample.cover,
        inbound_bytes: RawOptional::from(current[0]),
        inbound_byte_delta: RawOptional::from(deltas[0]),
        inbound_packets: RawOptional::from(current[1]),
        inbound_packet_delta: RawOptional::from(deltas[1]),
        decoded_frames: RawOptional::from(current[2]),
        decoded_frame_delta: RawOptional::from(deltas[2]),
        presented_frames: RawOptional::from(current[3]),
        presented_frame_delta: RawOptional::from(deltas[3]),
        content_samples: RawOptional::from(current[4]),
        content_sample_delta: RawOptional::from(deltas[4]),
        content_changes: RawOptional::from(current[5]),
        content_change_delta: RawOptional::from(deltas[5]),
        presentation_age_ms: RawOptional::from(age),
        frame_width: RawOptional::from(dimension(render_width)
            .or_else(|| dimension(sample.inbound_width.value()))),
        frame_height: RawOptional::from(dimension(render_height)
            .or_else(|| dimension(sample.inbound_height.value()))),
        frames_per_second_bits: RawOptional::from(valid_fps(sample.frames_per_second_bits.value())),
    };
    RawResult { abi_version: ABI_VERSION, status: 0, reserved: 0,
        state: RawState { previous_present: 1, last_change_at: RawOptional::from(last_change),
            previous: sample }, snapshot }
}

#[cfg(test)]
#[path = "screen_liveness_tests.rs"]
mod tests;
