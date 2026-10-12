//! Private source-only proposal: copied mic-forwarding evidence, never native authority.
//! No callbacks, clocks, audio devices, track mutations, retry or watchdog ownership.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Progress {
    pub queue_running: bool,
    pub post_start_callback_count: u64,
    pub successful_pull_count: u64,
    pub successful_frame_count: u64,
    pub enqueue_failure_count: u64,
}

pub fn is_ready(progress: Progress) -> bool {
    progress.queue_running && progress.enqueue_failure_count == 0
        && progress.successful_pull_count > 0 && progress.successful_frame_count > 0
}

pub fn proves_continuing_health(previous: Progress, current: Progress) -> bool {
    is_ready(previous) && is_ready(current)
        && current.post_start_callback_count > previous.post_start_callback_count
        && current.successful_frame_count > previous.successful_frame_count
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Watermark {
    pub packets_received: Option<u64>,
    pub bytes_received: Option<u64>,
    pub jitter_buffer_emitted_count: Option<u64>,
    pub total_samples_received: Option<u64>,
}

fn regressed(current: Option<u64>, previous: Option<u64>) -> bool {
    matches!((current, previous), (Some(current), Some(previous)) if current < previous)
}

fn advanced(current: Option<u64>, previous: Option<u64>) -> bool {
    matches!((current, previous), (Some(current), Some(previous)) if current > previous)
}

fn maximum(lhs: Option<u64>, rhs: Option<u64>) -> Option<u64> {
    match (lhs, rhs) {
        (Some(lhs), Some(rhs)) => Some(lhs.max(rhs)),
        (Some(value), None) | (None, Some(value)) => Some(value),
        (None, None) => None,
    }
}

impl Watermark {
    pub fn is_continuous(self, previous: Option<Self>) -> bool {
        let Some(previous) = previous else { return true; };
        !regressed(self.packets_received, previous.packets_received)
            && !regressed(self.bytes_received, previous.bytes_received)
            && !regressed(self.jitter_buffer_emitted_count, previous.jitter_buffer_emitted_count)
            && !regressed(self.total_samples_received, previous.total_samples_received)
    }

    pub fn advances(self, previous: Option<Self>) -> bool {
        let Some(previous) = previous else { return false; };
        advanced(self.packets_received, previous.packets_received)
            || advanced(self.bytes_received, previous.bytes_received)
    }

    pub fn preserving_maximums(self, previous: Option<Self>) -> Self {
        let Some(previous) = previous else { return self; };
        Self {
            packets_received: maximum(previous.packets_received, self.packets_received),
            bytes_received: maximum(previous.bytes_received, self.bytes_received),
            jitter_buffer_emitted_count: maximum(previous.jitter_buffer_emitted_count, self.jitter_buffer_emitted_count),
            total_samples_received: maximum(previous.total_samples_received, self.total_samples_received),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct WatermarkState { pub retained: Option<Watermark> }

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WatermarkEvent { Observe(Option<Watermark>) }

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct WatermarkResult {
    pub state: WatermarkState,
    pub continuous: bool,
    pub did_advance: bool,
}

/// This is only the already-owned sample's lines760–773 calculation.
/// It does not admit a sample, increment counters, renew a deadline or fail an attempt.
pub fn watermark_transition(before: WatermarkState, event: WatermarkEvent) -> WatermarkResult {
    let WatermarkEvent::Observe(current) = event;
    let Some(current) = current else {
        return WatermarkResult { state: before, continuous: false, did_advance: false };
    };
    let continuous = current.is_continuous(before.retained);
    WatermarkResult {
        state: if continuous {
            WatermarkState { retained: Some(current.preserving_maximums(before.retained)) }
        } else { before },
        continuous,
        did_advance: continuous && current.advances(before.retained),
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct FreshnessState {
    pub advancement_count: u64,
    pub consecutive_stale_samples: i64,
    pub deadline_nanoseconds: Option<u64>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FreshnessEvent {
    /// Config retains Swift's constructor clamp. Supplied Int values stay signed.
    Observe { maximum_stale_samples: i64, now_nanoseconds: Option<u64> },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FreshnessResult { NotFresh, Fresh, NeedsNow }

/// NeedsNow preserves the original short-circuit clock-read ordering without a callback.
pub fn freshness(before: FreshnessState, event: FreshnessEvent) -> FreshnessResult {
    let FreshnessEvent::Observe { maximum_stale_samples, now_nanoseconds } = event;
    let Some(deadline) = before.deadline_nanoseconds else { return FreshnessResult::NotFresh; };
    if before.advancement_count == 0 || before.consecutive_stale_samples >= maximum_stale_samples {
        return FreshnessResult::NotFresh;
    }
    match now_nanoseconds {
        None => FreshnessResult::NeedsNow,
        Some(now) if now < deadline => FreshnessResult::Fresh,
        Some(_) => FreshnessResult::NotFresh,
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct OptionalU64 { pub present: u32, pub reserved: u32, pub value: u64 }

fn boolean(value: u32) -> Option<bool> {
    match value { 0 => Some(false), 1 => Some(true), _ => None }
}

impl OptionalU64 {
    fn decode(self) -> Option<Option<u64>> {
        if self.reserved != 0 { return None; }
        Some(if boolean(self.present)? { Some(self.value) } else { None })
    }
    fn encode(value: Option<u64>) -> Self {
        Self { present: u32::from(value.is_some()), reserved: 0, value: value.unwrap_or(0) }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawProgress {
    pub queue_running: u32, pub reserved: u32,
    pub post_start_callback_count: u64, pub successful_pull_count: u64,
    pub successful_frame_count: u64, pub enqueue_failure_count: u64,
}

impl RawProgress {
    fn decode(self) -> Option<Progress> {
        if self.reserved != 0 { return None; }
        Some(Progress { queue_running: boolean(self.queue_running)?,
            post_start_callback_count: self.post_start_callback_count,
            successful_pull_count: self.successful_pull_count,
            successful_frame_count: self.successful_frame_count,
            enqueue_failure_count: self.enqueue_failure_count })
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawReadinessFacts {
    pub abi_version: u32, pub reserved: u32, pub current: RawProgress,
    pub previous_present: u32, pub previous_reserved: u32, pub previous: RawProgress,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawReadinessResult { pub abi_version: u32, pub status: u32, pub ready: u32, pub continuing: u32 }

pub fn readiness_decide(raw: RawReadinessFacts) -> RawReadinessResult {
    let invalid = RawReadinessResult { abi_version: ABI_VERSION, status: 0, ready: 0, continuing: 0 };
    if raw.abi_version != ABI_VERSION || raw.reserved != 0 || raw.previous_reserved != 0 { return invalid; }
    let Some(has_previous) = boolean(raw.previous_present) else { return invalid; };
    let Some(current) = raw.current.decode() else { return invalid; };
    let previous = if has_previous {
        let Some(previous) = raw.previous.decode() else { return invalid; };
        Some(previous)
    } else { None };
    RawReadinessResult { abi_version: ABI_VERSION, status: 1, ready: u32::from(is_ready(current)),
        continuing: u32::from(previous.is_some_and(|previous| proves_continuing_health(previous, current))) }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawWatermark { pub present: u32, pub reserved: u32, pub fields: [OptionalU64; 4] }

impl RawWatermark {
    fn decode(self) -> Option<Option<Watermark>> {
        if self.reserved != 0 { return None; }
        if !boolean(self.present)? { return Some(None); }
        Some(Some(Watermark { packets_received: self.fields[0].decode()?, bytes_received: self.fields[1].decode()?,
            jitter_buffer_emitted_count: self.fields[2].decode()?, total_samples_received: self.fields[3].decode()? }))
    }
    fn encode(value: Option<Watermark>) -> Self {
        let Some(value) = value else { return Self::default(); };
        Self { present: 1, reserved: 0, fields: [OptionalU64::encode(value.packets_received),
            OptionalU64::encode(value.bytes_received), OptionalU64::encode(value.jitter_buffer_emitted_count),
            OptionalU64::encode(value.total_samples_received)] }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawWatermarkState { pub abi_version: u32, pub reserved: u32, pub retained: RawWatermark }

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawWatermarkEvent { pub abi_version: u32, pub reserved: u32, pub current: RawWatermark }

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawWatermarkResult { pub state: RawWatermarkState, pub status: u32, pub continuous: u32, pub did_advance: u32, pub reserved: u32 }

pub fn watermark_step(before: RawWatermarkState, event: RawWatermarkEvent) -> RawWatermarkResult {
    let unchanged = |status| RawWatermarkResult { state: before, status, continuous: 0, did_advance: 0, reserved: 0 };
    if before.abi_version != ABI_VERSION || before.reserved != 0 || event.abi_version != ABI_VERSION || event.reserved != 0 {
        return unchanged(0);
    }
    let Some(retained) = before.retained.decode() else { return unchanged(0); };
    let Some(current) = event.current.decode() else { return unchanged(0); };
    let result = watermark_transition(WatermarkState { retained }, WatermarkEvent::Observe(current));
    // Preserve raw before bytes when the original native watermark is unchanged.
    let state = if !result.continuous { before } else {
        RawWatermarkState { abi_version: ABI_VERSION, reserved: 0, retained: RawWatermark::encode(result.state.retained) }
    };
    RawWatermarkResult { state, status: 1, continuous: u32::from(result.continuous), did_advance: u32::from(result.did_advance), reserved: 0 }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawFreshnessState {
    pub abi_version: u32, pub reserved: u32, pub advancement_count: u64,
    pub consecutive_stale_samples: i64, pub deadline: OptionalU64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawFreshnessEvent {
    pub abi_version: u32, pub reserved: u32, pub maximum_stale_samples: i64, pub now: OptionalU64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawFreshnessResult {
    pub abi_version: u32,
    /// 0 invalid; 1 evaluated (fresh may be0); 2 original predicate needs one native clock read.
    pub status: u32, pub fresh: u32, pub reserved: u32,
}

pub fn freshness_decide(before: RawFreshnessState, event: RawFreshnessEvent) -> RawFreshnessResult {
    let result = |status, fresh| RawFreshnessResult { abi_version: ABI_VERSION, status, fresh, reserved: 0 };
    if before.abi_version != ABI_VERSION || before.reserved != 0 || event.abi_version != ABI_VERSION || event.reserved != 0 {
        return result(0, 0);
    }
    let Some(deadline_nanoseconds) = before.deadline.decode() else { return result(0, 0); };
    let Some(now_nanoseconds) = event.now.decode() else { return result(0, 0); };
    match freshness(FreshnessState { advancement_count: before.advancement_count,
        consecutive_stale_samples: before.consecutive_stale_samples, deadline_nanoseconds },
        FreshnessEvent::Observe { maximum_stale_samples: event.maximum_stale_samples, now_nanoseconds }) {
        FreshnessResult::NotFresh => result(1, 0), FreshnessResult::Fresh => result(1, 1),
        FreshnessResult::NeedsNow => result(2, 0),
    }
}

const _: [(); 16] = [(); size_of::<OptionalU64>()];
const _: [(); 40] = [(); size_of::<RawProgress>()];
const _: [(); 96] = [(); size_of::<RawReadinessFacts>()];
const _: [(); 16] = [(); size_of::<RawReadinessResult>()];
const _: [(); 72] = [(); size_of::<RawWatermark>()];
const _: [(); 80] = [(); size_of::<RawWatermarkState>()];
const _: [(); 80] = [(); size_of::<RawWatermarkEvent>()];
const _: [(); 96] = [(); size_of::<RawWatermarkResult>()];
const _: [(); 40] = [(); size_of::<RawFreshnessState>()];
const _: [(); 32] = [(); size_of::<RawFreshnessEvent>()];
const _: [(); 16] = [(); size_of::<RawFreshnessResult>()];
const _: [(); 8] = [(); align_of::<RawWatermarkResult>()];

#[cfg(test)]
mod tests {
    use super::*;

    fn watermark(values: [Option<u64>; 4]) -> Watermark {
        Watermark { packets_received: values[0], bytes_received: values[1],
            jitter_buffer_emitted_count: values[2], total_samples_received: values[3] }
    }

    #[test]
    fn mic_evidence_readiness_requires_all_four_original_terms() {
        for flags in 0..16 {
            let current = Progress { queue_running: flags & 1 != 0, enqueue_failure_count: if flags & 2 != 0 { 0 } else { 7 },
                successful_pull_count: u64::from(flags & 4 != 0), successful_frame_count: u64::from(flags & 8 != 0), post_start_callback_count: 0 };
            assert_eq!(is_ready(current), flags == 15, "flags={flags}");
        }
    }

    #[test]
    fn mic_evidence_health_needs_two_ready_snapshots_and_both_strict_advances() {
        let previous = Progress { queue_running: true, post_start_callback_count: 9, successful_pull_count: 7,
            successful_frame_count: 80, enqueue_failure_count: 0 };
        let current = Progress { post_start_callback_count: 10, successful_pull_count: 1, successful_frame_count: 81, ..previous };
        assert!(proves_continuing_health(previous, current)); // Pull monotonicity is NOT an original vote.
        for (callbacks, frames) in [(9, 81), (8, 81), (10, 80), (10, 79), (9, 80)] {
            assert!(!proves_continuing_health(previous, Progress { post_start_callback_count: callbacks, successful_frame_count: frames, ..current }));
        }
        for fail_previous in [false, true] {
            let bad = Progress { enqueue_failure_count: 1, ..previous };
            assert!(!proves_continuing_health(if fail_previous { bad } else { previous }, if fail_previous { current } else { bad }));
        }
    }

    #[test]
    fn mic_evidence_none_and_first_observation_are_not_rtp_advancement() {
        let none = WatermarkState { retained: None };
        assert_eq!(watermark_transition(none, WatermarkEvent::Observe(None)), WatermarkResult { state: none, continuous: false, did_advance: false });
        let first = watermark([Some(0), Some(u64::MAX), None, Some(48)]);
        assert_eq!(watermark_transition(none, WatermarkEvent::Observe(Some(first))), WatermarkResult {
            state: WatermarkState { retained: Some(first) }, continuous: true, did_advance: false });
        let empty = watermark([None; 4]);
        assert!(empty.is_continuous(None));
        assert!(!empty.advances(None));
        assert!(!empty.advances(Some(empty)));
    }

    #[test]
    fn mic_evidence_all_four_regressions_win_over_rtp_advancement() {
        let before = WatermarkState { retained: Some(watermark([Some(10), Some(100), Some(20), Some(200)])) };
        for field in 0..4 {
            let mut values = [Some(11), Some(101), Some(21), Some(201)];
            values[field] = Some([9, 99, 19, 199][field]);
            assert_eq!(watermark_transition(before, WatermarkEvent::Observe(Some(watermark(values)))), WatermarkResult {
                state: before, continuous: false, did_advance: false }, "field={field}");
        }
    }

    #[test]
    fn mic_evidence_concealment_alone_never_advances_packets_or_bytes() {
        let before = watermark([Some(10), Some(100), Some(20), Some(200)]);
        let current = watermark([Some(10), Some(100), Some(21), Some(680)]);
        assert!(current.is_continuous(Some(before)));
        assert!(!current.advances(Some(before)));
        for current in [watermark([Some(11), None, None, None]), watermark([None, Some(101), None, None])] {
            assert!(current.advances(Some(before)));
        }
    }

    #[test]
    fn mic_evidence_optional_gaps_keep_every_maximum_and_reject_lower_reappearance() {
        let old = watermark([Some(10), Some(100), Some(20), Some(200)]);
        let gap = watermark([None, Some(101), None, None]);
        let kept = watermark([Some(10), Some(101), Some(20), Some(200)]);
        assert_eq!(watermark_transition(WatermarkState { retained: Some(old) }, WatermarkEvent::Observe(Some(gap))), WatermarkResult {
            state: WatermarkState { retained: Some(kept) }, continuous: true, did_advance: true });
        let lower = watermark([Some(9), Some(102), None, None]);
        assert!(!lower.is_continuous(Some(kept)));
        assert_eq!(lower.preserving_maximums(Some(kept)), watermark([Some(10), Some(102), Some(20), Some(200)]));
        // The maxima helper alone is NOT the accepted transition for this regressed input.
        assert_eq!(watermark_transition(WatermarkState { retained: Some(kept) }, WatermarkEvent::Observe(Some(lower))).state.retained, Some(kept));
        assert!(lower.advances(Some(kept))); // Individual advances does not perform continuity's independent vote.
        let greater = watermark([Some(11), Some(103), Some(21), Some(201)]);
        assert_eq!(watermark_transition(WatermarkState { retained: Some(kept) }, WatermarkEvent::Observe(Some(greater))), WatermarkResult {
            state: WatermarkState { retained: Some(greater) }, continuous: true, did_advance: true });
        assert!(!watermark([Some(10), None, None, None]).advances(Some(watermark([None; 4]))));
    }

    #[test]
    fn mic_evidence_zero_max_and_wrapping_counters_keep_numeric_semantics() {
        let zero = watermark([Some(0), Some(0), None, None]);
        let maximum = watermark([Some(u64::MAX), Some(u64::MAX), None, None]);
        assert!(maximum.is_continuous(Some(zero)));
        assert!(maximum.advances(Some(zero)));
        assert!(maximum.is_continuous(Some(maximum)));
        assert!(!maximum.advances(Some(maximum)));
        assert!(!zero.is_continuous(Some(maximum))); // RTP counters do not use nextNonzero's wrapping domain.
        assert!(!zero.advances(Some(maximum)));
        assert_eq!(watermark_transition(WatermarkState { retained: Some(maximum) }, WatermarkEvent::Observe(Some(zero))),
            WatermarkResult { state: WatermarkState { retained: Some(maximum) }, continuous: false, did_advance: false });
        assert_eq!(watermark_transition(WatermarkState { retained: Some(maximum) }, WatermarkEvent::Observe(None)).state.retained, Some(maximum));
    }

    #[test]
    fn mic_evidence_freshness_short_circuits_and_expires_at_exact_deadline() {
        let state = FreshnessState { advancement_count: 1, consecutive_stale_samples: 2, deadline_nanoseconds: Some(100) };
        let event = |now| FreshnessEvent::Observe { maximum_stale_samples: 3, now_nanoseconds: now };
        assert_eq!(freshness(state, event(None)), FreshnessResult::NeedsNow);
        assert_eq!(freshness(state, event(Some(99))), FreshnessResult::Fresh);
        assert_eq!(freshness(state, event(Some(100))), FreshnessResult::NotFresh);
        assert_eq!(freshness(state, event(Some(101))), FreshnessResult::NotFresh);
        for state in [FreshnessState { advancement_count: 0, ..state }, FreshnessState { consecutive_stale_samples: 3, ..state },
            FreshnessState { deadline_nanoseconds: None, ..state }] {
            assert_eq!(freshness(state, event(None)), FreshnessResult::NotFresh);
        }
        assert_eq!(freshness(FreshnessState { deadline_nanoseconds: Some(u64::MAX), ..state }, event(Some(u64::MAX - 1))), FreshnessResult::Fresh);
        assert_eq!(freshness(FreshnessState { deadline_nanoseconds: Some(u64::MAX), ..state }, event(Some(u64::MAX))), FreshnessResult::NotFresh);
        assert_eq!(freshness(FreshnessState { consecutive_stale_samples: i64::MIN, ..state },
            FreshnessEvent::Observe { maximum_stale_samples: i64::MIN + 1, now_nanoseconds: Some(99) }), FreshnessResult::Fresh);
    }

    #[test]
    fn mic_evidence_wire_refusal_is_distinct_from_legitimate_no_evidence() {
        let absent = RawWatermark { present: 0, reserved: 0, fields: [OptionalU64 { present: 9, reserved: 7, value: u64::MAX }; 4] };
        let before = RawWatermarkState { abi_version: 1, reserved: 0, retained: absent };
        let event = RawWatermarkEvent { abi_version: 1, reserved: 0, current: RawWatermark::default() };
        assert_eq!(watermark_step(before, event), RawWatermarkResult { state: before, status: 1, continuous: 0, did_advance: 0, reserved: 0 });
        for bad in [RawWatermarkEvent { abi_version: 2, ..event }, RawWatermarkEvent { reserved: 1, ..event },
            RawWatermarkEvent { current: RawWatermark { present: 2, ..event.current }, ..event },
            RawWatermarkEvent { current: RawWatermark { present: 1, fields: [OptionalU64 { present: 2, ..OptionalU64::default() }; 4], ..event.current }, ..event }] {
            assert_eq!(watermark_step(before, bad), RawWatermarkResult { state: before, status: 0, continuous: 0, did_advance: 0, reserved: 0 });
        }
        let state = RawFreshnessState { abi_version: 1, reserved: 0, advancement_count: 1, consecutive_stale_samples: 0, deadline: OptionalU64::encode(Some(100)) };
        let event = RawFreshnessEvent { abi_version: 1, reserved: 0, maximum_stale_samples: 3, now: OptionalU64::default() };
        assert_eq!(freshness_decide(state, event), RawFreshnessResult { abi_version: 1, status: 2, fresh: 0, reserved: 0 });
        assert_eq!(freshness_decide(state, RawFreshnessEvent { now: OptionalU64::encode(Some(100)), ..event }), RawFreshnessResult { abi_version: 1, status: 1, fresh: 0, reserved: 0 });
        assert_eq!(freshness_decide(state, RawFreshnessEvent { now: OptionalU64 { present: 2, ..event.now }, ..event }).status, 0);
    }

    #[test]
    fn mic_evidence_progress_raw_shape_and_absent_previous_are_closed() {
        let current = RawProgress { queue_running: 1, reserved: 0, post_start_callback_count: 2,
            successful_pull_count: 1, successful_frame_count: 480, enqueue_failure_count: 0 };
        let facts = RawReadinessFacts { abi_version: 1, reserved: 0, current, previous_present: 0, previous_reserved: 0,
            previous: RawProgress { queue_running: 7, reserved: 9, ..current } };
        assert_eq!(readiness_decide(facts), RawReadinessResult { abi_version: 1, status: 1, ready: 1, continuing: 0 });
        for bad in [RawReadinessFacts { abi_version: 0, ..facts }, RawReadinessFacts { reserved: 1, ..facts },
            RawReadinessFacts { previous_present: 2, ..facts }, RawReadinessFacts { previous_reserved: 1, ..facts },
            RawReadinessFacts { current: RawProgress { queue_running: 2, ..current }, ..facts },
            RawReadinessFacts { current: RawProgress { reserved: 1, ..current }, ..facts },
            RawReadinessFacts { previous_present: 1, ..facts }] {
            assert_eq!(readiness_decide(bad), RawReadinessResult { abi_version: 1, status: 0, ready: 0, continuing: 0 });
        }
    }
}

/// Correlates a copied result to the unchanged raw decision. Invalid inputs never vote valid.
#[must_use]
pub fn readiness_result_is_valid(facts: RawReadinessFacts, result: RawReadinessResult) -> u32 {
    let expected = readiness_decide(facts);
    u32::from(expected.status == 1 && result == expected)
}

/// Includes every retained/absent carrier and result field, not only decision flags.
#[must_use]
pub fn watermark_result_is_valid(
    before: RawWatermarkState, event: RawWatermarkEvent, result: RawWatermarkResult,
) -> u32 {
    let expected = watermark_step(before, event);
    u32::from(expected.status == 1 && result == expected)
}

/// NeedsNow is a correlated plan only; this predicate never reads or authorizes a clock.
#[must_use]
pub fn freshness_result_is_valid(
    before: RawFreshnessState, event: RawFreshnessEvent, result: RawFreshnessResult,
) -> u32 {
    let expected = freshness_decide(before, event);
    u32::from(matches!(expected.status, 1 | 2) && result == expected)
}
