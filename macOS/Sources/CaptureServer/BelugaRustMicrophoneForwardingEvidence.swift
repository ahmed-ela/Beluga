import BelugaCore

/// Unwired copied-evidence bridge. The driver retains all attempt, privacy and
/// device ownership, accepted watermark storage, counters and native effects.
/// V2 is callback-free: both mutable bridge borrows end before caller clock work.
struct BelugaRustMicrophoneForwardingEvidence {
    typealias OptionalCounter = beluga_core_microphone_optional_u64_t
    typealias Progress = beluga_core_microphone_progress_t
    typealias ReadinessFacts = beluga_core_microphone_readiness_facts_t
    typealias ReadinessResult = beluga_core_microphone_readiness_result_t
    typealias Watermark = beluga_core_microphone_watermark_t
    typealias WatermarkState = beluga_core_microphone_watermark_state_t
    typealias WatermarkEvent = beluga_core_microphone_watermark_event_t
    typealias WatermarkResult = beluga_core_microphone_watermark_result_t
    typealias FreshnessState = beluga_core_microphone_freshness_state_t
    typealias FreshnessEvent = beluga_core_microphone_freshness_event_t
    typealias FreshnessResult = beluga_core_microphone_freshness_result_t

    enum Failure: Error, Equatable { case layout, refused, faulted }
    struct ReadinessDecision: Equatable, Sendable {
        let ready: Bool
        let continuing: Bool
    }
    struct WatermarkDecision: Equatable, Sendable {
        let retained: WorldwideIPhoneMicrophoneInboundMediaWatermark?
        let continuous: Bool
        let didAdvance: Bool
    }

    /// Pure copied input, constructor-sealed to a verified NeedsNow result.
    /// This is neither native clock permission nor attempt/currentness authority.
    struct FreshnessSnapshot {
        fileprivate let before: FreshnessState
        fileprivate let maximumStaleSamples: Int64
        fileprivate init(before: FreshnessState, maximumStaleSamples: Int64) {
            self.before = before; self.maximumStaleSamples = maximumStaleSamples
        }
    }
    enum FreshnessPlan {
        case decided(Bool)
        case needsNow(FreshnessSnapshot)
    }

    private(set) var hasNativeFault = false

#if DEBUG
    // Test-only post-result corruption. The actual producers and authoritative
    // Rust verifiers are fixed; neither can be replaced by this seam.
    struct Mutations {
        var readiness: ((ReadinessFacts, ReadinessResult) -> ReadinessResult)?
        var watermark: ((WatermarkState, WatermarkEvent, WatermarkResult) -> WatermarkResult)?
        var freshness: ((FreshnessState, FreshnessEvent, FreshnessResult) -> FreshnessResult)?
        init(readiness: ((ReadinessFacts, ReadinessResult) -> ReadinessResult)? = nil,
             watermark: ((WatermarkState, WatermarkEvent, WatermarkResult) -> WatermarkResult)? = nil,
             freshness: ((FreshnessState, FreshnessEvent, FreshnessResult) -> FreshnessResult)? = nil) {
            self.readiness = readiness; self.watermark = watermark; self.freshness = freshness
        }
    }
    private let mutations: Mutations
    init(mutations: Mutations = Mutations()) { self.mutations = mutations }
#else
    init() {}
#endif

    static var layoutIsExact: Bool {
        MemoryLayout<Int>.size == 8
            && UInt16(littleEndian: 1) == 1
            && exact(OptionalCounter.self, 16, 8) && exact(Progress.self, 40, 8)
            && exact(ReadinessFacts.self, 96, 8) && exact(ReadinessResult.self, 16, 4)
            && exact(Watermark.self, 72, 8) && exact(WatermarkState.self, 80, 8)
            && exact(WatermarkEvent.self, 80, 8) && exact(WatermarkResult.self, 96, 8)
            && exact(FreshnessState.self, 40, 8) && exact(FreshnessEvent.self, 32, 8)
            && exact(FreshnessResult.self, 16, 4)
            && MemoryLayout<OptionalCounter>.offset(of: \OptionalCounter.present) == 0
            && MemoryLayout<OptionalCounter>.offset(of: \OptionalCounter.reserved) == 4
            && MemoryLayout<OptionalCounter>.offset(of: \OptionalCounter.value) == 8
            && MemoryLayout<Progress>.offset(of: \Progress.queue_running) == 0
            && MemoryLayout<Progress>.offset(of: \Progress.reserved) == 4
            && MemoryLayout<Progress>.offset(of: \Progress.post_start_callback_count) == 8
            && MemoryLayout<Progress>.offset(of: \Progress.successful_pull_count) == 16
            && MemoryLayout<Progress>.offset(of: \Progress.successful_frame_count) == 24
            && MemoryLayout<Progress>.offset(of: \Progress.enqueue_failure_count) == 32
            && MemoryLayout<ReadinessFacts>.offset(of: \ReadinessFacts.abi_version) == 0
            && MemoryLayout<ReadinessFacts>.offset(of: \ReadinessFacts.reserved) == 4
            && MemoryLayout<ReadinessFacts>.offset(of: \ReadinessFacts.current) == 8
            && MemoryLayout<ReadinessFacts>.offset(of: \ReadinessFacts.previous_present) == 48
            && MemoryLayout<ReadinessFacts>.offset(of: \ReadinessFacts.previous_reserved) == 52
            && MemoryLayout<ReadinessFacts>.offset(of: \ReadinessFacts.previous) == 56
            && MemoryLayout<ReadinessResult>.offset(of: \ReadinessResult.abi_version) == 0
            && MemoryLayout<ReadinessResult>.offset(of: \ReadinessResult.status) == 4
            && MemoryLayout<ReadinessResult>.offset(of: \ReadinessResult.ready) == 8
            && MemoryLayout<ReadinessResult>.offset(of: \ReadinessResult.continuing) == 12
            && MemoryLayout<Watermark>.offset(of: \Watermark.present) == 0
            && MemoryLayout<Watermark>.offset(of: \Watermark.reserved) == 4
            && MemoryLayout<Watermark>.offset(of: \Watermark.fields) == 8
            && MemoryLayout<WatermarkState>.offset(of: \WatermarkState.abi_version) == 0
            && MemoryLayout<WatermarkState>.offset(of: \WatermarkState.reserved) == 4
            && MemoryLayout<WatermarkState>.offset(of: \WatermarkState.retained) == 8
            && MemoryLayout<WatermarkEvent>.offset(of: \WatermarkEvent.abi_version) == 0
            && MemoryLayout<WatermarkEvent>.offset(of: \WatermarkEvent.reserved) == 4
            && MemoryLayout<WatermarkEvent>.offset(of: \WatermarkEvent.current) == 8
            && MemoryLayout<WatermarkResult>.offset(of: \WatermarkResult.state) == 0
            && MemoryLayout<WatermarkResult>.offset(of: \WatermarkResult.status) == 80
            && MemoryLayout<WatermarkResult>.offset(of: \WatermarkResult.continuous) == 84
            && MemoryLayout<WatermarkResult>.offset(of: \WatermarkResult.did_advance) == 88
            && MemoryLayout<WatermarkResult>.offset(of: \WatermarkResult.reserved) == 92
            && MemoryLayout<FreshnessState>.offset(of: \FreshnessState.abi_version) == 0
            && MemoryLayout<FreshnessState>.offset(of: \FreshnessState.reserved) == 4
            && MemoryLayout<FreshnessState>.offset(of: \FreshnessState.advancement_count) == 8
            && MemoryLayout<FreshnessState>.offset(of: \FreshnessState.consecutive_stale_samples) == 16
            && MemoryLayout<FreshnessState>.offset(of: \FreshnessState.deadline) == 24
            && MemoryLayout<FreshnessEvent>.offset(of: \FreshnessEvent.abi_version) == 0
            && MemoryLayout<FreshnessEvent>.offset(of: \FreshnessEvent.reserved) == 4
            && MemoryLayout<FreshnessEvent>.offset(of: \FreshnessEvent.maximum_stale_samples) == 8
            && MemoryLayout<FreshnessEvent>.offset(of: \FreshnessEvent.now) == 16
            && MemoryLayout<FreshnessResult>.offset(of: \FreshnessResult.abi_version) == 0
            && MemoryLayout<FreshnessResult>.offset(of: \FreshnessResult.status) == 4
            && MemoryLayout<FreshnessResult>.offset(of: \FreshnessResult.fresh) == 8
            && MemoryLayout<FreshnessResult>.offset(of: \FreshnessResult.reserved) == 12
    }

    mutating func readiness(current: BlackHoleMicrophoneOutputProgressSnapshot,
                            previous: BlackHoleMicrophoneOutputProgressSnapshot?) throws -> ReadinessDecision {
        try requireAvailable()
        let facts = ReadinessFacts(abi_version: 1, reserved: 0,
            current: Self.encode(current), previous_present: previous == nil ? 0 : 1,
            previous_reserved: 0, previous: previous.map(Self.encode) ?? Self.encode(.zero))
        let actual = beluga_core_microphone_forwarding_readiness_decide(facts)
#if DEBUG
        let result = mutations.readiness?(facts, actual) ?? actual
#else
        let result = actual
#endif
        guard beluga_core_microphone_forwarding_readiness_result_is_valid(facts, result) == 1 else {
            throw refuse()
        }
        return ReadinessDecision(ready: result.ready == 1, continuing: result.continuing == 1)
    }

    mutating func watermark(previous: WorldwideIPhoneMicrophoneInboundMediaWatermark?,
                            current: WorldwideIPhoneMicrophoneInboundMediaWatermark?) throws -> WatermarkDecision {
        try requireAvailable()
        let before = WatermarkState(abi_version: 1, reserved: 0, retained: Self.encode(previous))
        let event = WatermarkEvent(abi_version: 1, reserved: 0, current: Self.encode(current))
        let actual = beluga_core_microphone_forwarding_watermark_step(before, event)
#if DEBUG
        let result = mutations.watermark?(before, event, actual) ?? actual
#else
        let result = actual
#endif
        guard beluga_core_microphone_forwarding_watermark_result_is_valid(before, event, result) == 1 else {
            throw refuse()
        }
        return WatermarkDecision(retained: Self.decode(result.state.retained),
            continuous: result.continuous == 1, didAdvance: result.did_advance == 1)
    }

    /// Captures copied inputs once and returns only the verified pure clock plan.
    /// The caller independently admits the original native cut AFTER this borrow.
    mutating func planFreshness(advancementCount: UInt64, consecutiveStaleSamples: Int,
                               maximumStaleSamples: Int, deadlineNanoseconds: UInt64?) throws -> FreshnessPlan {
        try requireAvailable()
        guard let stale = Int64(exactly: consecutiveStaleSamples),
              let maximum = Int64(exactly: maximumStaleSamples) else { throw refuse() }
        let before = FreshnessState(abi_version: 1, reserved: 0,
            advancement_count: advancementCount, consecutive_stale_samples: stale,
            deadline: Self.encode(deadlineNanoseconds))
        let event = FreshnessEvent(abi_version: 1, reserved: 0,
            maximum_stale_samples: maximum, now: Self.encode(nil as UInt64?))
        let first = try evaluateFreshness(before, event)
        if first.status == 1 { return .decided(first.fresh == 1) }
        guard first.status == 2 else { throw refuse() }
        return .needsNow(FreshnessSnapshot(before: before, maximumStaleSamples: maximum))
    }

    /// Callback-free. Supply the SAME returned snapshot and exactly the original
    /// clock scalar only after a fresh original-owner/currentness check. A copied
    /// snapshot is not one-use authority; native admission/storage remains caller-owned.
    mutating func finishFreshness(_ snapshot: FreshnessSnapshot, now: UInt64) throws -> Bool {
        try requireAvailable()
        let event = FreshnessEvent(abi_version: 1, reserved: 0,
            maximum_stale_samples: snapshot.maximumStaleSamples, now: Self.encode(now))
        let second = try evaluateFreshness(snapshot.before, event)
        guard second.status == 1 else { throw refuse() }
        return second.fresh == 1
    }

    private mutating func evaluateFreshness(_ before: FreshnessState, _ event: FreshnessEvent) throws -> FreshnessResult {
        let actual = beluga_core_microphone_forwarding_freshness_decide(before, event)
#if DEBUG
        let result = mutations.freshness?(before, event, actual) ?? actual
#else
        let result = actual
#endif
        guard beluga_core_microphone_forwarding_freshness_result_is_valid(before, event, result) == 1 else {
            throw refuse()
        }
        return result
    }

    private mutating func requireAvailable() throws {
        guard !hasNativeFault else { throw Failure.faulted }
        guard Self.layoutIsExact else { hasNativeFault = true; throw Failure.layout }
    }
    private mutating func refuse() -> Failure { hasNativeFault = true; return .refused }
    private static func exact<T>(_ type: T.Type, _ size: Int, _ alignment: Int) -> Bool {
        MemoryLayout<T>.size == size && MemoryLayout<T>.stride == size && MemoryLayout<T>.alignment == alignment
    }
    private static func encode(_ value: UInt64?) -> OptionalCounter {
        OptionalCounter(present: value == nil ? 0 : 1, reserved: 0, value: value ?? 0)
    }
    private static func encode(_ value: BlackHoleMicrophoneOutputProgressSnapshot) -> Progress {
        Progress(queue_running: value.queueRunning ? 1 : 0, reserved: 0,
            post_start_callback_count: value.postStartCallbackCount,
            successful_pull_count: value.successfulPullCount, successful_frame_count: value.successfulFrameCount,
            enqueue_failure_count: value.enqueueFailureCount)
    }
    private static func encode(_ value: WorldwideIPhoneMicrophoneInboundMediaWatermark?) -> Watermark {
        Watermark(present: value == nil ? 0 : 1, reserved: 0,
            fields: (encode(value?.packetsReceived), encode(value?.bytesReceived),
                     encode(value?.jitterBufferEmittedCount), encode(value?.totalSamplesReceived)))
    }
    private static func decode(_ value: Watermark) -> WorldwideIPhoneMicrophoneInboundMediaWatermark? {
        guard value.present == 1 else { return nil }
        func counter(_ raw: OptionalCounter) -> UInt64? { raw.present == 1 ? raw.value : nil }
        return WorldwideIPhoneMicrophoneInboundMediaWatermark(packetsReceived: counter(value.fields.0),
            bytesReceived: counter(value.fields.1), jitterBufferEmittedCount: counter(value.fields.2),
            totalSamplesReceived: counter(value.fields.3))
    }
}
