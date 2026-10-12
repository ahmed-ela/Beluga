import WebRTCTransport

enum FrozenWorldwideScreenVideoAdaptationTier: Int, CaseIterable, Equatable, Sendable {
    case full
    case high
    case balanced
    case constrained
    case critical
    case survival
    case emergency
    case audioPriority

    fileprivate var framesPerSecond: Int {
        switch self {
        case .full: 60
        case .high: 45
        case .balanced: 30
        case .constrained: 20
        case .critical: 10
        case .survival: 5
        case .emergency: 2
        case .audioPriority: 1
        }
    }

    fileprivate var scaleResolutionDownBy: Double {
        switch self {
        case .full: 1
        case .high: 1.25
        case .balanced: 1.5
        case .constrained: 2
        case .critical: 3
        case .survival: 4
        case .emergency: 8
        case .audioPriority: 12
        }
    }

    fileprivate var nextHigherQuality: Self? {
        Self(rawValue: rawValue - 1)
    }

    fileprivate var nextLowerQuality: Self? {
        Self(rawValue: rawValue + 1)
    }
}

struct FrozenWorldwideScreenVideoEncodingRecommendation: Equatable, Sendable {
    let tier: FrozenWorldwideScreenVideoAdaptationTier
    let maximumBitrateBps: Int
    let maximumTotalRTPBitrateBps: Int
    let maximumFramesPerSecond: Int
    let scaleResolutionDownBy: Double

    var webRTCLimits: WebRTCScreenVideoEncodingLimits {
        WebRTCScreenVideoEncodingLimits(
            maximumBitrateBps: maximumBitrateBps,
            maximumFramesPerSecond: maximumFramesPerSecond,
            scaleResolutionDownBy: scaleResolutionDownBy,
            maximumTotalRTPBitrateBps: maximumTotalRTPBitrateBps
        )
    }
}

enum FrozenWorldwideScreenVideoAutomaticSuspensionDecision: Equatable, Sendable {
    case suspend
    case resume
}

/// Converts transport capacity into a stable, single-layer screen-video encoding ceiling.
struct FrozenWorldwideScreenVideoAdaptationPolicy: Equatable, Sendable {
    private typealias PacketQueueObservation = FrozenPinnedPacketSendQueueObservation

    enum RoundTripTimeDisposition: String, Equatable, Sendable {
        case legacy
        case provisionalHealthy
        case freshHealthy
        case freshInflated
        case retainedHealthy
        case retainedInflated
        case unavailable
        case expired
        case reseeded
        case reordered
    }

    private enum NativeRoundTripTimeHealth: Equatable, Sendable {
        case unknown, healthy, inflated
    }

    private struct AutomaticResumeProbeRestoration: Equatable, Sendable {
        let belowReserveProbeDisprovedSenderLimitation: Bool
        let applicationLimitedProbeCooldownSamplesRemaining: Int
        let applicationLimitedProbeFailureCount: Int
    }

    struct PromotionCapacityContinuity: Equatable, Sendable {
        let tier: FrozenWorldwideScreenVideoAdaptationTier
        var maximumTotalRTPBitrateBps: Int
        let deadline: ContinuousClock.Instant
    }

    private struct CapacityProbeSample: Equatable, Sendable {
        let packetsSent: UInt64?
        let totalPacketSendDelaySeconds: Double?
    }

    private struct FloorRecoveryWitness: Equatable, Sendable {
        let observedAt: ContinuousClock.Instant
        let bandwidthBps: Double
    }

    /// The dedicated video sampler runs independently from the one-second microphone-health
    /// stream. Calibrate evidence windows to its 500 ms cadence, then keep first-reaction counts
    /// bounded below five seconds when the one-second statistics stream is used as a fallback.
    static let sampleIntervalMilliseconds = 500
    static let fallbackSampleIntervalMilliseconds = 1_000
    static let requiredHealthyUpgradeSampleCount = sampleCount(for: 1_000)
    static let requiredSuspendedHealthyUpgradeSampleCount = fallbackSampleCount(
        for: 8_000
    )
    static let requiredPositiveBandwidthBootstrapSampleCount = sampleCount(for: 500)
    // Raising the peer-wide BWE ceiling does not change decoded geometry. Once RTT and advancing
    // low-delay packet evidence are established, one fresh 500 ms sample may request the bounded
    // native probe instead of waiting through another visible-quality interval.
    static let requiredApplicationLimitedUpgradeSampleCount = sampleCount(for: 500)
    static let applicationLimitedProbeGraceSampleCount = sampleCount(for: 3_500)
    static let applicationLimitedProbeGraceDuration = Duration.milliseconds(3_500)
    static let promotionCapacityContinuityDuration = Duration.seconds(2)
    static let initialApplicationLimitedProbeCooldownSampleCount = sampleCount(for: 8_000)
    static let maximumApplicationLimitedProbeCooldownSampleCount = sampleCount(for: 64_000)
    /// A visible sender drains stale probe cooldown within two one-second fallback samples even
    /// when an older failed probe installed the longer backoff retained for suspended recovery.
    static let maximumActiveApplicationLimitedProbeCooldownSampleCount =
        sampleCount(for: 1_000)
    /// When native candidate-pair bandwidth is unavailable, use a slower additive probe backed by
    /// both a stable RTT baseline and advancing low-delay outbound packets. This prevents an
    /// optional stats field from pinning a healthy session at its conservative startup tier.
    /// With no optional BWE field, require two consecutive low-delay RTT/queue reports for each
    /// additive tier. This reacts within one second while preventing alternating pressure samples
    /// from bouncing the encoder ceiling every poll.
    static let requiredUnavailableBandwidthUpgradeSampleCount = sampleCount(for: 1_000)
    static let requiredSuspensionPressureSampleCount = fallbackSampleCount(
        for: 3_000
    )
    /// A paused sender cannot produce a useful outbound bitrate estimate. Even when the last
    /// estimate remains positive-but-low, a long latency-stable window permits one bounded probe;
    /// a failed probe resets this counter and therefore supplies the same full cooldown again.
    static let requiredStableSuspensionResumeProbeSampleCount =
        fallbackSampleCount(for: 16_000)
    static let requiredMaximumSuspensionResumeProbeSampleCount =
        fallbackSampleCount(for: 64_000)
    static let requiredBandwidthOnlyDowngradeSampleCount = sampleCount(for: 1_000)
    /// Encoder reconfiguration and key-frame bursts can produce one high packet-send-delay delta
    /// even when the path is healthy. Require a second consecutive queue-pressure sample before
    /// treating queue delay as congestion; RTT inflation and bandwidth collapse remain immediate.
    static let requiredQueuePressureSampleCount = sampleCount(for: 1_000)

    private static let audioAndControlReserveBps = 320_000.0
    /// The native controller is capped at the same configured total. Treat a small estimator gap
    /// at that ceiling as cap saturation rather than requiring an exact floating-point sample.
    private static let configuredCapacitySaturationRatio = 0.95
    private static let applicationLimitedSaturationRatio = 0.80
    private static let applicationLimitedProbeImmediateAbortRatio = 0.75
    static let roundTripTimeBootstrapSampleCount = 3
    /// Observation age, not the exact ping age: only a distinct cumulative watermark renews it.
    /// This spans the pinned native stable-pair ping interval without granting indefinite health.
    static let roundTripTimeObservationValidity = Duration.seconds(4)
    private static let maximumUpgradePacketSendDelaySeconds = 0.020
    private static let lowDelayPacketQueueObservationValidity =
        Duration.milliseconds(1_500)

    private static func sampleCount(for windowMilliseconds: Int) -> Int {
        max(
            1,
            (windowMilliseconds + sampleIntervalMilliseconds - 1)
                / sampleIntervalMilliseconds
        )
    }

    private static func fallbackSampleCount(
        for windowMilliseconds: Int
    ) -> Int {
        max(
            1,
            (windowMilliseconds + fallbackSampleIntervalMilliseconds - 1)
                / fallbackSampleIntervalMilliseconds
        )
    }

    let configuredTotalRTPBitrateBps: Int
    let maximumTierVideoBitrateBps: Int
    let baseFramesPerSecond: Int
    private(set) var peerGeneration: UInt64?
    private(set) var currentTier: FrozenWorldwideScreenVideoAdaptationTier
    private(set) var healthyUpgradeSampleCount = 0
    private(set) var bandwidthOnlyDowngradeSampleCount = 0
    var queuePressureSampleCount: Int { packetQueue.pressureCount }
    private(set) var unavailableBandwidthSampleCount = 0
    private(set) var positiveBandwidthBootstrapSampleCount = 0
    private(set) var applicationLimitedUpgradeSampleCount = 0
    private(set) var applicationLimitedProbeHealthySampleCount = 0
    private(set) var applicationLimitedProbeGraceSamplesRemaining = 0
    private(set) var applicationLimitedProbeDeadline:
        ContinuousClock.Instant?
    private(set) var applicationLimitedProbeCooldownSamplesRemaining = 0
    private(set) var applicationLimitedProbeFailureCount = 0
    private(set) var belowReserveProbeDisprovedSenderLimitation = false
    private var automaticResumeProbeRestoration:
        AutomaticResumeProbeRestoration?
    private(set) var applicationLimitedProbeOriginTier:
        FrozenWorldwideScreenVideoAdaptationTier?
    private(set) var applicationLimitedProbeBestQualifiedTier:
        FrozenWorldwideScreenVideoAdaptationTier?
    private(set) var applicationLimitedProbeConfirmedTier:
        FrozenWorldwideScreenVideoAdaptationTier?
    private var applicationLimitedProbeQualificationObservedAt:
        ContinuousClock.Instant?
    private(set) var applicationLimitedProbeMaximumTotalRTPBitrateBps: Int?
    private(set) var promotionCapacityContinuity: PromotionCapacityContinuity?
    private(set) var automaticSuspensionPressureSampleCount = 0
    private(set) var stableSuspensionResumeProbeSampleCount = 0
    private(set) var maximumSuspensionResumeProbeSampleCount = 0
    private(set) var bandwidthEstimateIsUnavailable = false
    private(set) var lastSampleHasLatencyPressure = false
    private(set) var lastSampleHasPositiveSuspensionPressure = false
    private(set) var lastAveragePacketSendDelaySeconds: Double?
    private var packetQueue = FrozenPinnedPacketSendQueue()
    private var roundTripTime = FrozenPinnedRoundTripTimeEvidence()
    var hasNativeRoundTripTimeFault: Bool { roundTripTime.hasNativeFault }
    private var tierDemand: FrozenPinnedTierDemand
    var hasNativeTierDemandFault: Bool { tierDemand.hasNativeFault }
    var hasNativeAdaptationPolicyFault: Bool { hasNativeRoundTripTimeFault || hasNativeTierDemandFault }
    var roundTripTimeBaselineSeconds: Double? { roundTripTime.baseline }
    var roundTripTimeDisposition: RoundTripTimeDisposition {
        switch roundTripTime.disposition {
        case 0: return .legacy
        case 1: return .provisionalHealthy
        case 2: return .freshHealthy
        case 3: return .freshInflated
        case 4: return .retainedHealthy
        case 5: return .retainedInflated
        case 7: return .expired
        case 8: return .reseeded
        case 9: return .reordered
        default: return .unavailable
        }
    }
    var roundTripTimeObservationAge: Duration? { roundTripTime.observationAge }
    var roundTripTimeReferenceIsProvisional: Bool { roundTripTime.provisional }
    private(set) var lastConsumedCollectionSequence: UInt64?
    private var nativeRoundTripTimeHealth: NativeRoundTripTimeHealth {
        switch roundTripTime.health {
        case 1: return .healthy
        case 2: return .inflated
        default: return .unknown
        }
    }
    private var usesNativeRoundTripTimeEvidence: Bool { roundTripTime.usesNative }
    private(set) var selectedRoute: WebRTCICERouteDiagnostics?
    private var capacityProbeSample: CapacityProbeSample?
    private var capacityProbeBandwidthHighWatermark: Double?
    private var capacityProbeNativeReportTimestamp: Double?
    private var lastCapacityProbeCollectionSequence: UInt64?
    private var capacityProbeGrowthIsVetoed = false
    private var floorRecoveryShowEpoch: UInt64?
    private var floorRecoveryVisibilityIsReserved = false
    private var floorRecoveryVisibilityIsActive = false
    private(set) var floorRecoveryAttemptConsumed = false
    private(set) var floorRecoveryProbeWasCancelled = false
    private var floorRecoveryProbeSeedBandwidthBps: Double?
    private var floorRecoveryFirstWitness: FloorRecoveryWitness?
    private var floorRecoveryLastRegularSequence: UInt64?
    private var floorRecoveryLastRegularTimestamp: Double?
    private var floorRecoveryLastCooldownObservation: ContinuousClock.Instant?
    // A cold Show prioritizes readable pixels, not a speculative full-traffic tier: keep
    // existing video/peer ceilings and initially <=5 fps while bandwidth is learned. Healthy
    // tiers can spend their qualified pixel rate on more full-size frames without shrinking
    // those pixels; real pressure terminates this mode for the
    // exact Show. Missing/cached reports are not negative evidence or permission for FPS.
    private(set) var startupSpatialModePeerGeneration: UInt64?
    private(set) var startupSpatialModeShowEpoch: UInt64?
    private(set) var startupSpatialModeIsDisproved = false
    // Proof of a whole selected-pair telemetry gap, scoped to the exact active trial deadline.
    // Unknown RTT from malformed data must never acquire this bounded wait permission.
    // Keep the sequence and mutation oracles in SCREEN_STARTUP_REGRESSION_GUARDRAILS.md.
    private var startupSparseProbeDeadline: ContinuousClock.Instant?

    var startupSpatialModeIsActive: Bool {
        guard !startupSpatialModeIsDisproved,
              let startupSpatialModePeerGeneration,
              let startupSpatialModeShowEpoch else {
            return false
        }
        return peerGeneration == startupSpatialModePeerGeneration
            && floorRecoveryShowEpoch == startupSpatialModeShowEpoch
            && (floorRecoveryVisibilityIsReserved
                || floorRecoveryVisibilityIsActive)
    }

    var floorRecoveryProbeIsActive: Bool {
        floorRecoveryProbeSeedBandwidthBps != nil
            && applicationLimitedProbeOriginTier == .audioPriority
    }

    init(
        configuredTotalRTPBitrateBps: Int,
        baseFramesPerSecond: Int,
        roundTripTimeProducer: FrozenPinnedRoundTripTimeEvidence.Producer? = nil,
        tierDemandProducer: FrozenPinnedTierDemand.Producer? = nil
    ) {
        if let roundTripTimeProducer {
            roundTripTime = FrozenPinnedRoundTripTimeEvidence(producer: roundTripTimeProducer)
        }
        self.configuredTotalRTPBitrateBps = min(
            Int(UInt32.max),
            max(1, configuredTotalRTPBitrateBps)
        )
        if let tierDemandProducer {
            tierDemand = FrozenPinnedTierDemand(configuredCap: self.configuredTotalRTPBitrateBps,
                                             producer: tierDemandProducer)
        } else {
            tierDemand = FrozenPinnedTierDemand(configuredCap: self.configuredTotalRTPBitrateBps)
        }
        maximumTierVideoBitrateBps = tierDemand.maximumTierVideoBitrateBps
        self.baseFramesPerSecond = max(1, baseFramesPerSecond)
        currentTier = tierDemand.initialTier
    }

    var currentRecommendation: FrozenWorldwideScreenVideoEncodingRecommendation {
        let tierRecommendation = recommendation(for: currentTier)
        let ordinaryRecommendation = FrozenWorldwideScreenVideoEncodingRecommendation(
            tier: currentTier,
            maximumBitrateBps: tierRecommendation.maximumBitrateBps,
            maximumTotalRTPBitrateBps: promotionCapacityContinuity.flatMap {
                $0.tier == currentTier ? $0.maximumTotalRTPBitrateBps : nil
            } ?? tierRecommendation.maximumTotalRTPBitrateBps,
            maximumFramesPerSecond: tierRecommendation.maximumFramesPerSecond,
            scaleResolutionDownBy: tierRecommendation.scaleResolutionDownBy
        )
        guard applicationLimitedProbeOriginTier != nil,
              let applicationLimitedProbeMaximumTotalRTPBitrateBps else {
            return applyingStartupSpatialMode(to: ordinaryRecommendation)
        }
        // A capacity probe raises libwebrtc's peer-wide BWE ceiling in bounded steps. Geometry
        // changes require separate ordinary-report qualification. This path can extend a native
        // probe without requiring ALR; the requested budget retains its existing 2x bound.
        return applyingStartupSpatialMode(to: FrozenWorldwideScreenVideoEncodingRecommendation(
            tier: currentTier,
            maximumBitrateBps: maximumTierVideoBitrateBps,
            maximumTotalRTPBitrateBps:
                applicationLimitedProbeMaximumTotalRTPBitrateBps,
            maximumFramesPerSecond:
                ordinaryRecommendation.maximumFramesPerSecond,
            scaleResolutionDownBy:
                ordinaryRecommendation.scaleResolutionDownBy
        ))
    }

    private func applyingStartupSpatialMode(
        to recommendation: FrozenWorldwideScreenVideoEncodingRecommendation
    ) -> FrozenWorldwideScreenVideoEncodingRecommendation {
        guard startupSpatialModeIsActive else { return recommendation }
        let ordinaryFPS = recommendation.maximumFramesPerSecond
        let initialFPS = min(FrozenWorldwideScreenVideoAdaptationTier.survival.framesPerSecond,
                             ordinaryFPS)
        let scale = recommendation.scaleResolutionDownBy
        // Tier promotion already needs fresh capacity/latency evidence. Preserve its ordinary
        // approximate pixel rate when replacing downscaled frames with full-size frames, instead
        // of freezing a qualified moderate path at 5 fps until it can reach the full tier.
        // This is an encode-work proxy, not extra bandwidth permission: RTP caps and congestion
        // retirement stay unchanged, including the initial low-FPS spatial trial.
        let pixelRateFPS = Int((Double(ordinaryFPS) / (scale * scale)).rounded(.down))
        return FrozenWorldwideScreenVideoEncodingRecommendation(
            tier: recommendation.tier,
            maximumBitrateBps: recommendation.maximumBitrateBps,
            maximumTotalRTPBitrateBps:
                recommendation.maximumTotalRTPBitrateBps,
            maximumFramesPerSecond: min(ordinaryFPS, max(initialFPS, pixelRateFPS)),
            scaleResolutionDownBy: 1
        )
    }

    var currentTierMinimumSustainableBitrateBps: Int {
        tierDemand.profile(for: currentTier)?.minimumSustainableBitrateBps ?? Int.max
    }

    var nextHigherTierMinimumDirectUpgradeBitrateBps: Int? {
        tierDemand.profile(for: currentTier)?.nextHigherTierMinimumDirectUpgradeBitrateBps
    }

    func recommendation(
        for tier: FrozenWorldwideScreenVideoAdaptationTier
    ) -> FrozenWorldwideScreenVideoEncodingRecommendation {
        let maximumBitrateBps = tierDemand.profile(for: tier)?.maximumVideoBitrateBps ?? 1
        return FrozenWorldwideScreenVideoEncodingRecommendation(
            tier: tier,
            maximumBitrateBps: maximumBitrateBps,
            maximumTotalRTPBitrateBps:
                maximumTotalRTPBitrateBps(for: tier),
            maximumFramesPerSecond: min(
                baseFramesPerSecond,
                tier.framesPerSecond
            ),
            scaleResolutionDownBy: tier.scaleResolutionDownBy
        )
    }

    /// Returns true only when a different peer lifetime reset the adaptation state.
    @discardableResult
    mutating func bind(toPeerGeneration generation: UInt64) -> Bool {
        guard peerGeneration != generation else { return false }
        clearStartupSpatialMode()
        peerGeneration = generation
        currentTier = tierDemand.initialTier
        selectedRoute = nil
        resetPathMeasurements()
        // Collection order and native measurement identity belong to the peer, not the sampler
        // cadence, geometry, Show/Hide lifetime, or selected-route diagnostics lifetime.
        lastConsumedCollectionSequence = nil
        floorRecoveryShowEpoch = nil
        floorRecoveryVisibilityIsReserved = false
        floorRecoveryVisibilityIsActive = false
        floorRecoveryAttemptConsumed = false
        floorRecoveryProbeWasCancelled = false
        floorRecoveryProbeSeedBandwidthBps = nil
        floorRecoveryFirstWitness = nil
        floorRecoveryLastRegularSequence = nil
        floorRecoveryLastRegularTimestamp = nil
        floorRecoveryLastCooldownObservation = nil
        lastCapacityProbeCollectionSequence = nil
        capacityProbeNativeReportTimestamp = nil
        roundTripTime.resetPeer()
        resetAutomaticSuspensionMeasurements()
        return true
    }

    mutating func beginFloorRecoveryVisibility(peerGeneration generation: UInt64, showEpoch: UInt64) {
        bind(toPeerGeneration: generation)
        guard showEpoch > 0, showEpoch > (floorRecoveryShowEpoch ?? 0) else { return }
        endFloorRecoveryVisibility()
        floorRecoveryShowEpoch = showEpoch
        floorRecoveryVisibilityIsReserved = true
        floorRecoveryAttemptConsumed = false
        floorRecoveryProbeWasCancelled = false
        armStartupSpatialModeIfEligible(
            peerGeneration: generation,
            showEpoch: showEpoch
        )
    }

    mutating func activateFloorRecoveryVisibility(peerGeneration generation: UInt64, showEpoch: UInt64) {
        guard peerGeneration == generation, floorRecoveryShowEpoch == showEpoch,
              floorRecoveryVisibilityIsReserved else { return }
        floorRecoveryVisibilityIsActive = true
    }

    mutating func endFloorRecoveryVisibility() {
        clearStartupSpatialMode()
        floorRecoveryVisibilityIsReserved = false
        floorRecoveryVisibilityIsActive = false
        floorRecoveryFirstWitness = nil
        if floorRecoveryProbeIsActive || applicationLimitedProbeConfirmedTier != nil {
            revertApplicationLimitedProbeIfActive()
        }
    }

    /// Spend the Show-bound attempt before native application can suspend. Copy no positive
    /// health or speculative limits, and never let a predecessor consume a successor's allowance.
    mutating func retainFloorRecoveryAttemptConsumption(from observed: Self) {
        guard peerGeneration == observed.peerGeneration,
              let epoch = floorRecoveryShowEpoch, epoch == observed.floorRecoveryShowEpoch,
              observed.floorRecoveryAttemptConsumed else { return }
        floorRecoveryAttemptConsumed = true
        floorRecoveryFirstWitness = nil
        if let sequence = observed.floorRecoveryLastRegularSequence {
            floorRecoveryLastRegularSequence = max(floorRecoveryLastRegularSequence ?? 0, sequence)
        }
        if let timestamp = observed.floorRecoveryLastRegularTimestamp {
            floorRecoveryLastRegularTimestamp = max(floorRecoveryLastRegularTimestamp ?? 0, timestamp)
        }
    }

    /// Persist a same-peer terminal denial before a native cap reduction can suspend. This
    /// imports no proposed quality, reference, clock or identity, and cannot fault a successor.
    mutating func retainRoundTripTimeFault(from observed: Self) {
        guard observed.hasNativeRoundTripTimeFault else { return }
        retainNativeAdaptationPolicyFault(from: observed)
    }

    mutating func retainNativeAdaptationPolicyFault(from observed: Self) {
        guard let generation = peerGeneration,
              generation == observed.peerGeneration,
              observed.hasNativeAdaptationPolicyFault else { return }
        roundTripTime.retainFault(from: observed.roundTripTime)
        tierDemand.retainFault(from: observed.tierDemand)
        _ = nativePolicyFaultRecommendation(isCaptureActive: false)
    }

    /// A native rejection cannot commit a qualified probe, or leave its temporary raised cap
    /// armed indefinitely. Retire only positive limits; the service retries only while the
    /// applied sender limits differ from this restrictive state. This is not RTT fallback.
    private mutating func nativePolicyFaultRecommendation(
        isCaptureActive: Bool
    ) -> FrozenWorldwideScreenVideoEncodingRecommendation? {
        guard hasNativeAdaptationPolicyFault else { return nil }
        let previousRecommendation = currentRecommendation
        revertApplicationLimitedProbeIfActive()
        promotionCapacityContinuity = nil
        _ = disproveStartupSpatialMode()
        healthyUpgradeSampleCount = 0
        applicationLimitedUpgradeSampleCount = 0
        return isCaptureActive && currentRecommendation != previousRecommendation
            ? currentRecommendation : nil
    }

    /// Clears latency history when ICE invalidates the selected path, while retaining the
    /// conservative quality tier learned for this peer lifetime.
    mutating func invalidateSelectedRoute() {
        let replacedSelectedRoute = selectedRoute != nil
        selectedRoute = nil
        if replacedSelectedRoute {
            _ = disproveStartupSpatialMode()
        }
        revertApplicationLimitedProbeIfActive()
        resetPathMeasurements()
    }

    /// Retains only a terminal same-Show negative after native application fails. This can never
    /// arm a mode, borrow a successor Show, or import positive network evidence.
    mutating func retainStartupSpatialModeTerminalState(from observed: Self) {
        guard !startupSpatialModeIsDisproved,
              observed.startupSpatialModeIsDisproved,
              let peer = startupSpatialModePeerGeneration,
              let show = startupSpatialModeShowEpoch,
              self.peerGeneration == peer,
              self.floorRecoveryShowEpoch == show,
              observed.startupSpatialModePeerGeneration == peer,
              observed.startupSpatialModeShowEpoch == show,
              observed.peerGeneration == peer,
              observed.floorRecoveryShowEpoch == show else {
            return
        }
        startupSpatialModeIsDisproved = true
        startupSparseProbeDeadline = nil
    }

    private mutating func armStartupSpatialModeIfEligible(
        peerGeneration generation: UInt64,
        showEpoch: UInt64
    ) {
        guard !hasNativeAdaptationPolicyFault,
              peerGeneration == generation,
              floorRecoveryShowEpoch == showEpoch,
              floorRecoveryVisibilityIsReserved,
              currentTier == .survival,
              requiredOutgoingBitrateBps(for: .full)
                <= Double(configuredTotalRTPBitrateBps) else {
            return
        }
        startupSpatialModePeerGeneration = generation
        startupSpatialModeShowEpoch = showEpoch
        startupSpatialModeIsDisproved = false
        startupSparseProbeDeadline = nil
    }

    @discardableResult
    private mutating func disproveStartupSpatialMode() -> Bool {
        guard startupSpatialModeIsActive else { return false }
        startupSpatialModeIsDisproved = true
        startupSparseProbeDeadline = nil
        return true
    }

    private mutating func clearStartupSpatialMode() {
        startupSpatialModePeerGeneration = nil
        startupSpatialModeShowEpoch = nil
        startupSpatialModeIsDisproved = false
        startupSparseProbeDeadline = nil
    }

    private mutating func observeStartupSelectedPairGap(
        route: WebRTCICERouteDiagnostics?, bandwidth: Double?, rtt: Double?,
        observation: WebRTCRoundTripTimeObservation?, primaryWasHealthy: Bool? = nil
    ) {
        guard startupSpatialModeIsActive,
              let deadline = applicationLimitedProbeDeadline,
              route == nil, bandwidth == nil, rtt == nil, observation == .unavailable,
              (primaryWasHealthy ?? (nativeRoundTripTimeHealth == .healthy))
                || startupSparseProbeDeadline == deadline else {
            startupSparseProbeDeadline = nil
            return
        }
        startupSparseProbeDeadline = deadline
    }

    /// Revokes RTT health synchronously at Hide, even if Show arrives before an inactive stats
    /// report. Preserve peer-owned identity/order and the path reference; only advancement can
    /// reauthorize RTT health. The service's statistics epoch owns partial-window reset/fencing.
    mutating func invalidateRoundTripTimeObservation() {
        startupSparseProbeDeadline = nil
        floorRecoveryFirstWitness = nil
        if applicationLimitedProbeConfirmedTier != nil {
            revertApplicationLimitedProbeIfActive()
        }
        applicationLimitedProbeHealthySampleCount = 0
        roundTripTime.revoke(hide: true)
        if hasNativeAdaptationPolicyFault {
            _ = nativePolicyFaultRecommendation(isCaptureActive: false)
        }
    }

    /// Prevents threshold evidence collected on one cadence, or before a long observation gap,
    /// from being combined with a later sample. Stable route baselines and any already-applied
    /// probe remain intact; only incomplete evidence windows are discarded.
    mutating func resetIncompleteEvidenceWindow() {
        floorRecoveryFirstWitness = nil
        capacityProbeSample = nil
        capacityProbeBandwidthHighWatermark = nil
        promotionCapacityContinuity = nil
        healthyUpgradeSampleCount = 0
        bandwidthOnlyDowngradeSampleCount = 0
        packetQueue.reset(path: false)
        unavailableBandwidthSampleCount = 0
        positiveBandwidthBootstrapSampleCount = 0
        applicationLimitedUpgradeSampleCount = 0
        applicationLimitedProbeHealthySampleCount = 0
        applicationLimitedProbeBestQualifiedTier = nil
    }

    /// Returns a recommendation only when the current sender should apply new limits.
    mutating func update(
        peerGeneration generation: UInt64,
        isCaptureActive: Bool,
        isAutomaticallySuspended: Bool = false,
        availableOutgoingBitrateBps: Double?,
        currentRoundTripTimeSeconds: Double?,
        roundTripTimeObservation: WebRTCRoundTripTimeObservation? = nil,
        collectionSequence: UInt64? = nil,
        requireRoundTripTimeObservation: Bool = false,
        selectedRoute: WebRTCICERouteDiagnostics? = nil,
        outboundVideoPacketsSent: UInt64? = nil,
        outboundVideoTotalPacketSendDelaySeconds: Double? = nil,
        nativeReportTimestampMicroseconds: Double? = nil,
        observedAt: ContinuousClock.Instant = .now,
        diagnostics: ((FrozenWorldwideScreenFloorRecoveryDiagnostics) -> Void)? = nil
    ) -> FrozenWorldwideScreenVideoEncodingRecommendation? {
        let didResetForNewPeer = bind(toPeerGeneration: generation)
        var evaluation = FrozenWorldwideScreenFloorRecoveryDiagnostics(
            showEpoch: floorRecoveryShowEpoch,
            reserved: floorRecoveryVisibilityIsReserved, active: floorRecoveryVisibilityIsActive,
            consumed: floorRecoveryAttemptConsumed, disproved: belowReserveProbeDisprovedSenderLimitation,
            cooldownRemaining: applicationLimitedProbeCooldownSamplesRemaining,
            collectionSequence: collectionSequence, previousRegularSequence: floorRecoveryLastRegularSequence,
            previousRegularTimestamp: floorRecoveryLastRegularTimestamp,
            capacityTimestamp: capacityProbeNativeReportTimestamp,
            nativeReportTimestamp: nativeReportTimestampMicroseconds,
            currentBandwidthBps: availableOutgoingBitrateBps,
            firstBandwidthBps: floorRecoveryFirstWitness?.bandwidthBps,
            witnessAge: floorRecoveryFirstWitness.map { $0.observedAt.duration(to: observedAt) },
            beforeTotalCapBps: currentRecommendation.maximumTotalRTPBitrateBps
        )
        defer {
            evaluation.proposedTotalCapBps = currentRecommendation.maximumTotalRTPBitrateBps
            diagnostics?(evaluation)
        }
        // An already-denied owner may retire speculative permission, but cannot mutate another
        // policy's evidence history. Keep the post-age guard for a new RTT rejection.
        guard !hasNativeAdaptationPolicyFault else {
            return nativePolicyFaultRecommendation(isCaptureActive: isCaptureActive)
        }
        // Time still passes when a report is rejected. Aging an existing lease is not renewing
        // it or consuming the report, and prevents stale stable-resume authorization.
        roundTripTime.age(at: observedAt)
        guard !hasNativeAdaptationPolicyFault else {
            return nativePolicyFaultRecommendation(isCaptureActive: isCaptureActive)
        }
        if requireRoundTripTimeObservation, collectionSequence == nil {
            evaluation.identity = .rejectedOrder
            evaluation.reason = .rejectedOrder
            floorRecoveryFirstWitness = nil
            applicationLimitedProbeHealthySampleCount = 0
            // Native request ordering is part of the evidence boundary. Unordered metadata may
            // expire a wall-clock lease, but cannot change BWE/queue/RTT measurement state.
            roundTripTime.strictUnordered()
            lastSampleHasLatencyPressure = false
            lastSampleHasPositiveSuspensionPressure = false
            return expireApplicationLimitedProbeWithoutReport(
                peerGeneration: generation,
                isCaptureActive: isCaptureActive,
                observedAt: observedAt
            )
        }
        if let collectionSequence {
            if let lastCapacityProbeCollectionSequence,
               collectionSequence <= lastCapacityProbeCollectionSequence {
                evaluation.identity = .rejectedOrder
                evaluation.reason = .rejectedOrder
                floorRecoveryFirstWitness = nil
                applicationLimitedProbeHealthySampleCount = 0
                return expireApplicationLimitedProbeWithoutReport(
                    peerGeneration: generation,
                    isCaptureActive: isCaptureActive,
                    observedAt: observedAt
                )
            }
            if let lastConsumedCollectionSequence,
               collectionSequence <= lastConsumedCollectionSequence {
                evaluation.identity = .rejectedOrder
                evaluation.reason = .rejectedOrder
                floorRecoveryFirstWitness = nil
                applicationLimitedProbeHealthySampleCount = 0
                // A slower fallback request may finish after a newer fast-lane report. Reject
                // the entire older report, including BWE/queue/cap changes, before consuming it.
                roundTripTime.reordered()
                lastSampleHasLatencyPressure = false
                lastSampleHasPositiveSuspensionPressure = false
                return expireApplicationLimitedProbeWithoutReport(
                    peerGeneration: generation,
                    isCaptureActive: isCaptureActive,
                    observedAt: observedAt
                )
            }
            lastConsumedCollectionSequence = collectionSequence
        }
        capacityProbeGrowthIsVetoed = false
        let floorRecoveryReportIsFresh = consumeFloorRecoveryReportIdentity(
            sequence: collectionSequence,
            timestamp: nativeReportTimestampMicroseconds,
            requiresNativeEvidence: requireRoundTripTimeObservation
        )
        evaluation.identity = floorRecoveryReportIsFresh ? .fresh
            : (requireRoundTripTimeObservation ? .rejectedTimestamp : .rejectedOrder)
        if startupSpatialModeIsActive,
           requireRoundTripTimeObservation,
           !floorRecoveryReportIsFresh {
            evaluation.reason = .rejectedTimestamp
            // During the speculative full-pixel startup window, the native report identity is
            // the evidence boundary for every network signal, not only floor recovery. A newer
            // request carrying a missing, equal, or regressing native timestamp may age an
            // already-running ceiling, but cannot blur the Show or mint RTT/queue/BWE health.
            return expireApplicationLimitedProbeWithoutReport(
                peerGeneration: generation,
                isCaptureActive: isCaptureActive,
                observedAt: observedAt
            )
        }
        observeStartupSelectedPairGap(
            route: selectedRoute, bandwidth: availableOutgoingBitrateBps,
            rtt: currentRoundTripTimeSeconds, observation: roundTripTimeObservation)
        defer {
            recordCapacityProbeBaseline(
                nativeReportTimestampMicroseconds: nativeReportTimestampMicroseconds,
                availableOutgoingBitrateBps: availableOutgoingBitrateBps,
                packetsSent: outboundVideoPacketsSent,
                totalPacketSendDelaySeconds: outboundVideoTotalPacketSendDelaySeconds
            )
        }
        let previousRecommendation = currentRecommendation
        let previousTier = currentTier
        let startupSpatialModeWasActive = startupSpatialModeIsActive
        let hadPromotionCapacityContinuity = promotionCapacityContinuity != nil
        updatePromotionCapacityContinuity(
            availableOutgoingBitrateBps: availableOutgoingBitrateBps,
            isCaptureActive: isCaptureActive,
            observedAt: observedAt
        )
        let changedRecommendation = updateNetworkEvidence(
            peerGeneration: generation,
            didResetForNewPeer: didResetForNewPeer,
            isCaptureActive: isCaptureActive,
            isAutomaticallySuspended: isAutomaticallySuspended,
            availableOutgoingBitrateBps: availableOutgoingBitrateBps,
            currentRoundTripTimeSeconds: currentRoundTripTimeSeconds,
            roundTripTimeObservation: roundTripTimeObservation
                ?? (requireRoundTripTimeObservation ? .unavailable : nil),
            selectedRoute: selectedRoute,
            outboundVideoPacketsSent: outboundVideoPacketsSent,
            outboundVideoTotalPacketSendDelaySeconds:
                outboundVideoTotalPacketSendDelaySeconds,
            floorRecoveryReportIsFresh: floorRecoveryReportIsFresh,
            observedAt: observedAt,
            floorDiagnostics: &evaluation
        )
        if lastSampleHasLatencyPressure {
            promotionCapacityContinuity = nil
        }
        if lastSampleHasLatencyPressure
            || currentTier.rawValue > previousTier.rawValue {
            _ = disproveStartupSpatialMode()
        } else if startupSpatialModeIsActive, currentTier == .full {
            clearStartupSpatialMode()
        }
        let startupSpatialRecommendationChanged =
            startupSpatialModeWasActive != startupSpatialModeIsActive
        // Cap expiry/shrink must reach the sender even when no visible tier changed.
        guard isCaptureActive,
              changedRecommendation != nil
                || startupSpatialRecommendationChanged
                || (hadPromotionCapacityContinuity
                    && currentRecommendation != previousRecommendation) else {
            return nil
        }
        return currentRecommendation
    }

    /// An unsuccessful native cap increase does not erase a report already observed. Retain
    /// only ordering/identity fences; the unapplied budget and positive health stay unchanged.
    mutating func retainCapacityProbeObservationIdentity(from observed: Self) {
        guard peerGeneration == observed.peerGeneration,
              applicationLimitedProbeOriginTier != nil,
              applicationLimitedProbeOriginTier == observed.applicationLimitedProbeOriginTier,
              let sequence = observed.lastCapacityProbeCollectionSequence,
              sequence > (lastConsumedCollectionSequence ?? 0),
              sequence > (lastCapacityProbeCollectionSequence ?? 0) else {
            return
        }
        lastCapacityProbeCollectionSequence = sequence
        capacityProbeNativeReportTimestamp = observed.capacityProbeNativeReportTimestamp
        roundTripTime.copyFence(from: observed.roundTripTime)
        tierDemand.retainFault(from: observed.tierDemand)
        if hasNativeAdaptationPolicyFault {
            _ = nativePolicyFaultRecommendation(isCaptureActive: false)
        }
    }

    /// Intermediate reports can grow or revoke speculative capacity, never qualify geometry.
    /// Positive RTT/queue leases still belong exclusively to the ordinary 500 ms reducer.
    mutating func updateCapacityProbe(
        peerGeneration generation: UInt64,
        isCaptureActive: Bool,
        availableOutgoingBitrateBps: Double?,
        currentRoundTripTimeSeconds: Double?,
        roundTripTimeObservation: WebRTCRoundTripTimeObservation?,
        collectionSequence: UInt64?,
        nativeReportTimestampMicroseconds: Double?,
        selectedRoute: WebRTCICERouteDiagnostics? = nil,
        outboundVideoPacketsSent: UInt64?,
        outboundVideoTotalPacketSendDelaySeconds: Double?,
        observedAt: ContinuousClock.Instant = .now,
        diagnostics: ((FrozenWorldwideScreenCapacityProbeDiagnostics) -> Void)? = nil
    ) -> FrozenWorldwideScreenVideoEncodingRecommendation? {
        var evaluation = FrozenWorldwideScreenCapacityProbeDiagnostics(
            origin: applicationLimitedProbeOriginTier,
            collectionSequence: collectionSequence,
            previousNativeReportTimestamp: capacityProbeNativeReportTimestamp,
            nativeReportTimestamp: nativeReportTimestampMicroseconds,
            beforeTotalCapBps: currentRecommendation.maximumTotalRTPBitrateBps
        )
        defer {
            evaluation.proposedTotalCapBps = currentRecommendation.maximumTotalRTPBitrateBps
            diagnostics?(evaluation)
        }
        guard peerGeneration == generation, isCaptureActive else {
            evaluation.reason = .inactive
            return nil
        }
        if let expired = expireApplicationLimitedProbeWithoutReport(
            peerGeneration: generation,
            isCaptureActive: isCaptureActive,
            observedAt: observedAt
        ) {
            evaluation.reason = .expired
            return expired
        }
        guard let origin = applicationLimitedProbeOriginTier,
              let currentCeiling = applicationLimitedProbeMaximumTotalRTPBitrateBps,
              let collectionSequence,
              collectionSequence > (lastConsumedCollectionSequence ?? 0),
              collectionSequence > (lastCapacityProbeCollectionSequence ?? 0),
              let timestamp = nativeReportTimestampMicroseconds,
              timestamp.isFinite, timestamp > 0,
              let previousTimestamp = capacityProbeNativeReportTimestamp,
              timestamp > previousTimestamp else {
            return nil
        }
        // The native timestamp is a report identity, not an elapsed-time clock. Equal or
        // regressing UTC timestamps cannot mint capacity proof even with a new request number.
        capacityProbeNativeReportTimestamp = timestamp
        lastCapacityProbeCollectionSequence = collectionSequence
        let baseline = capacityProbeSample
        capacityProbeSample = CapacityProbeSample(
            packetsSent: outboundVideoPacketsSent,
            totalPacketSendDelaySeconds: outboundVideoTotalPacketSendDelaySeconds
        )
        // Positive fast observations advance only the identity fence, never the ordinary
        // reference or health lease. Negative identities must poison subsequent ordinary use.
        // The startup gap marker historically inspected primary health before fast revocation.
        let primaryWasHealthy = nativeRoundTripTimeHealth == .healthy
        let rtt = roundTripTime.observe(
            current: currentRoundTripTimeSeconds,
            observation: roundTripTimeObservation ?? .unavailable,
            at: observedAt, fast: true, routeChanged: selectedRoute != self.selectedRoute
        )
        guard !hasNativeAdaptationPolicyFault else {
            return nativePolicyFaultRecommendation(isCaptureActive: isCaptureActive)
        }
        let primaryRTTLeaseIsCurrent = rtt.primaryLeaseCurrent
        guard rtt.allowsUpgrade else {
            observeStartupSelectedPairGap(
                route: selectedRoute, bandwidth: availableOutgoingBitrateBps,
                rtt: currentRoundTripTimeSeconds, observation: roundTripTimeObservation,
                primaryWasHealthy: primaryWasHealthy)
            evaluation.reason = .roundTripTime
            if rtt.hasFreshPressure {
                _ = disproveStartupSpatialMode()
            }
            evaluation.recordQueue(
                previousPackets: baseline?.packetsSent,
                previousDelay: baseline?.totalPacketSendDelaySeconds,
                packets: outboundVideoPacketsSent,
                delay: outboundVideoTotalPacketSendDelaySeconds)
            let queueDecision = packetQueue.capacityObservation(
                previousPackets: baseline?.packetsSent,
                previousDelay: baseline?.totalPacketSendDelaySeconds,
                packets: outboundVideoPacketsSent,
                delay: outboundVideoTotalPacketSendDelaySeconds, at: observedAt)
            let queue = queueDecision.observation
            let queueIsObservable: Bool
            switch queue {
            case .measured, .noNewPackets: queueIsObservable = true
            case .unavailableOrReset: queueIsObservable = false
            }
            if startupSpatialModeIsActive {
                var negativeReason: FrozenWorldwideScreenCapacityProbeDiagnostics.Reason?
                if let selectedRoute, let previousRoute = self.selectedRoute,
                   selectedRoute != previousRoute {
                    negativeReason = .routeChanged
                } else if queueDecision.requiresImmediateResponse {
                    negativeReason = .immediateQueue
                } else if let bandwidth = availableOutgoingBitrateBps,
                          bandwidth.isFinite, bandwidth > 0,
                          bandwidth < applicationLimitedProbeCollapseThreshold(for: origin) {
                    negativeReason = .bandwidthCollapse
                }
                if let negativeReason {
                    // Missing RTT must not hide affirmative evidence from the other lanes.
                    evaluation.reason = negativeReason
                    _ = disproveStartupSpatialMode()
                    failApplicationLimitedProbe(revertingTo: origin)
                    return currentRecommendation
                }
            }
            if startupSpatialModeIsActive,
               startupSparseProbeDeadline != nil,
               startupSparseProbeDeadline == applicationLimitedProbeDeadline,
               primaryRTTLeaseIsCurrent, baseline != nil, queueIsObservable,
               !rtt.hasFreshPressure,
               roundTripTimeObservation == .unavailable,
               currentRoundTripTimeSeconds == nil,
               availableOutgoingBitrateBps == nil,
               selectedRoute == nil {
                // A filtered native report can temporarily omit the entire selected pair.
                // It cannot authorize growth, renew RTT health, or prove that an already
                // bounded discovery budget failed. Keep its original deadline and cap.
                // Independent fresh pressure was checked above, even with RTT unavailable.
                evaluation.reason = .missingPrimaryEvidence
                capacityProbeGrowthIsVetoed = true
                return nil
            }
            // Leave a fresh inflated measurement unconsumed: the ordinary lane must still
            // apply its one RTT-pressure decision, not lose it to this capacity-only abort.
            failApplicationLimitedProbe(revertingTo: origin)
            return currentRecommendation
        }
        if selectedRoute != self.selectedRoute {
            evaluation.reason = .routeChanged
            _ = disproveStartupSpatialMode()
            // Sender-filtered stats can reveal a route change before the ordinary route event.
            // Its RTT tuple must not become new health when the next regular report reuses it.
            failApplicationLimitedProbe(revertingTo: origin)
            return currentRecommendation
        }
        let awaitsOrdinaryRTTRequalification = startupSpatialModeIsActive
            && startupSparseProbeDeadline != nil
            && startupSparseProbeDeadline == applicationLimitedProbeDeadline
            && nativeRoundTripTimeHealth == .unknown
            && roundTripTimeDisposition == .unavailable
            && rtt.validationDisposition == 2
            && primaryRTTLeaseIsCurrent
        guard let baseline,
              primaryRTTLeaseIsCurrent,
              nativeRoundTripTimeHealth == .healthy || awaitsOrdinaryRTTRequalification else {
            evaluation.reason = .missingPrimaryEvidence
            failApplicationLimitedProbe(revertingTo: origin)
            return currentRecommendation
        }
        evaluation.recordQueue(
            previousPackets: baseline.packetsSent,
            previousDelay: baseline.totalPacketSendDelaySeconds,
            packets: outboundVideoPacketsSent,
            delay: outboundVideoTotalPacketSendDelaySeconds
        )
        let queueDecision = packetQueue.capacityObservation(
            previousPackets: baseline.packetsSent,
            previousDelay: baseline.totalPacketSendDelaySeconds,
            packets: outboundVideoPacketsSent,
            delay: outboundVideoTotalPacketSendDelaySeconds, at: observedAt)
        let queue = queueDecision.observation
        if queueDecision.requiresImmediateResponse {
            evaluation.reason = .immediateQueue
            _ = disproveStartupSpatialMode()
            failApplicationLimitedProbe(revertingTo: origin)
            return currentRecommendation
        }
        guard let availableOutgoingBitrateBps,
              availableOutgoingBitrateBps.isFinite,
              availableOutgoingBitrateBps > 0 else {
            evaluation.reason = .missingBandwidth
            capacityProbeGrowthIsVetoed = true
            return nil
        }
        let collapseThreshold = applicationLimitedProbeCollapseThreshold(for: origin)
        evaluation.collapseThresholdBps =
            FrozenWorldwideScreenCapacityProbeDiagnostics.boundedInteger(collapseThreshold)
        if availableOutgoingBitrateBps < collapseThreshold {
            evaluation.reason = .bandwidthCollapse
            _ = disproveStartupSpatialMode()
            failApplicationLimitedProbe(revertingTo: origin)
            return currentRecommendation
        }
        if awaitsOrdinaryRTTRequalification {
            if case .unavailableOrReset = queue {
                evaluation.reason = .missingPrimaryEvidence
                failApplicationLimitedProbe(revertingTo: origin)
                return currentRecommendation
            }
            // A sparse ordinary report revoked primary health. A genuinely advanced fast
            // ping may wait for the next ordinary witness, not fail an otherwise intact trial.
            // Do not copy its positive health, extend the old lease/deadline, or raise any cap.
            // Route replacement, immediate queue pressure and real BWE collapse above still win.
            evaluation.reason = .missingPrimaryEvidence
            capacityProbeGrowthIsVetoed = true
            return nil
        }
        guard let previousBandwidth = capacityProbeBandwidthHighWatermark else {
            evaluation.reason = .missingPrimaryEvidence
            failApplicationLimitedProbe(revertingTo: origin)
            return currentRecommendation
        }
        // Neutral transition bursts withhold growth for this regular observation window;
        // they do not turn a 200 ms poll into an extra congestion/backoff decision.
        guard queueDecision.allowsCapacityGrowth else {
            evaluation.reason = .queueWithheld
            capacityProbeGrowthIsVetoed = true
            return nil
        }
        guard !capacityProbeGrowthIsVetoed else {
            evaluation.reason = .growthVetoed
            return nil
        }
        guard availableOutgoingBitrateBps > previousBandwidth else {
            evaluation.reason = .bandwidthNotAdvanced
            return nil
        }
        capacityProbeBandwidthHighWatermark = availableOutgoingBitrateBps
        let nextCeiling = boundedApplicationLimitedProbeCeiling(
            availableOutgoingBitrateBps: availableOutgoingBitrateBps,
            currentCeilingBps: currentCeiling
        )
        guard nextCeiling > currentCeiling else {
            evaluation.reason = .atCeiling
            return nil
        }
        applicationLimitedProbeMaximumTotalRTPBitrateBps = nextCeiling
        evaluation.reason = .increased
        return currentRecommendation
    }

    private mutating func recordCapacityProbeBaseline(
        nativeReportTimestampMicroseconds: Double?,
        availableOutgoingBitrateBps: Double?,
        packetsSent: UInt64?,
        totalPacketSendDelaySeconds: Double?
    ) {
        guard let timestamp = nativeReportTimestampMicroseconds,
              timestamp.isFinite, timestamp > 0,
              timestamp >= (capacityProbeNativeReportTimestamp ?? 0) else {
            capacityProbeSample = nil
            return
        }
        capacityProbeNativeReportTimestamp = timestamp
        if startupSpatialModeIsActive,
           startupSparseProbeDeadline != nil,
           startupSparseProbeDeadline == applicationLimitedProbeDeadline,
           availableOutgoingBitrateBps == nil {
            // Selected-pair omission does not erase the separately collected sender counters.
            // Keep only their delta baseline for negative queue checks, never capacity proof.
            capacityProbeSample = CapacityProbeSample(
                packetsSent: packetsSent,
                totalPacketSendDelaySeconds: totalPacketSendDelaySeconds)
            capacityProbeBandwidthHighWatermark = nil
            return
        }
        guard applicationLimitedProbeOriginTier != nil,
              let availableOutgoingBitrateBps,
              availableOutgoingBitrateBps.isFinite,
              availableOutgoingBitrateBps > 0 else {
            capacityProbeSample = nil
            capacityProbeBandwidthHighWatermark = nil
            return
        }
        capacityProbeBandwidthHighWatermark = max(
            capacityProbeBandwidthHighWatermark ?? 0,
            availableOutgoingBitrateBps
        )
        capacityProbeSample = CapacityProbeSample(
            packetsSent: packetsSent,
            totalPacketSendDelaySeconds: totalPacketSendDelaySeconds
        )
    }

    private mutating func updateNetworkEvidence(
        peerGeneration generation: UInt64,
        didResetForNewPeer: Bool,
        isCaptureActive: Bool,
        isAutomaticallySuspended: Bool,
        availableOutgoingBitrateBps: Double?,
        currentRoundTripTimeSeconds: Double?,
        roundTripTimeObservation: WebRTCRoundTripTimeObservation?,
        selectedRoute: WebRTCICERouteDiagnostics?,
        outboundVideoPacketsSent: UInt64?,
        outboundVideoTotalPacketSendDelaySeconds: Double?,
        floorRecoveryReportIsFresh: Bool,
        observedAt: ContinuousClock.Instant,
        floorDiagnostics: inout FrozenWorldwideScreenFloorRecoveryDiagnostics
    ) -> FrozenWorldwideScreenVideoEncodingRecommendation? {
        if let selectedRoute,
           selectedRoute != self.selectedRoute {
            let startupSpatialRouteWasAlreadyBound = self.selectedRoute != nil
            let isInitialRoute = self.selectedRoute == nil
                && roundTripTime.watermark == nil
                && roundTripTime.permitsInitial
            self.selectedRoute = selectedRoute
            if startupSpatialRouteWasAlreadyBound {
                _ = disproveStartupSpatialMode()
            }
            revertApplicationLimitedProbeIfActive()
            resetPathMeasurements()
            if isInitialRoute {
                roundTripTime.allowInitial()
            }
        }

        // Pre-Show and manually hidden sessions have no outbound video with which to interpret
        // WebRTC's optional bandwidth estimate or packet-send delay. V27 treated those absent
        // samples as congestion and could walk all the way to audioPriority before the first Show.
        // Reset to the configured conservative start tier and consume path samples only for an
        // active sender or an explicit automatic-pause recovery probe.
        guard isCaptureActive || isAutomaticallySuspended else {
            floorDiagnostics.reason = .inactiveVisibility
            clearStartupSpatialMode()
            currentTier = tierDemand.initialTier
            resetPathMeasurements()
            // Hidden reports cannot authorize a later Show using a cached measurement. Keep a
            // valid watermark as a tombstone, without treating it as RTT/queue/BWE health.
            roundTripTime.inactive(observation: roundTripTimeObservation)
            resetAutomaticSuspensionMeasurements()
            return nil
        }

        let roundTripTimeEvidence = roundTripTime.observe(
            current: currentRoundTripTimeSeconds,
            observation: roundTripTimeObservation,
            at: observedAt
        )
        guard !hasNativeAdaptationPolicyFault else {
            return nativePolicyFaultRecommendation(isCaptureActive: isCaptureActive)
        }
        // Only a fresh inflated native watermark applies additional RTT-only descent. Retained
        // unhealthy/unknown RTT still vetoes upgrades, without suppressing fresh queue pressure.
        let roundTripTimeIsInflated = roundTripTimeEvidence.hasFreshPressure
        let queueDecision = packetQueue.observe(
            packets: outboundVideoPacketsSent,
            delay: outboundVideoTotalPacketSendDelaySeconds,
            rttInflated: roundTripTimeIsInflated, at: observedAt)
        guard !packetQueue.faulted else { return nil }
        let packetQueueObservation = queueDecision.observation
        let averagePacketSendDelaySeconds: Double?
        switch packetQueueObservation {
        case let .measured(value):
            averagePacketSendDelaySeconds = value
        case .noNewPackets, .unavailableOrReset:
            averagePacketSendDelaySeconds = nil
        }
        lastAveragePacketSendDelaySeconds = averagePacketSendDelaySeconds
        let packetQueueSampleIsInflated = queueDecision.sampleIsInflated
        let packetQueueIsInflated = queueDecision.isInflated
        let packetQueueAllowsUpgrade = queueDecision.allowsUpgrade
        let roundTripTimeAllowsUpgrade = roundTripTimeEvidence.allowsUpgrade
        let directUpgradeEvidenceIsHealthy = averagePacketSendDelaySeconds.map {
            $0 <= Self.maximumUpgradePacketSendDelaySeconds
                && (roundTripTimeEvidence.permitsLegacyMissingValue
                    || roundTripTimeAllowsUpgrade)
        } ?? roundTripTimeAllowsUpgrade
        let strictUpgradeEvidenceIsHealthy = packetQueueAllowsUpgrade
            && roundTripTimeAllowsUpgrade
        let latencyPressure = roundTripTimeIsInflated || packetQueueIsInflated
        let latencyEvidenceIsPositivelyHealthy = !latencyPressure
            && directUpgradeEvidenceIsHealthy
        lastSampleHasLatencyPressure = latencyPressure

        let floorRecoveryMayBegin = observeFloorRecoveryWitness(
            reportIsFresh: floorRecoveryReportIsFresh,
            queue: packetQueueObservation,
            roundTripTimeAllowsUpgrade: roundTripTimeAllowsUpgrade,
            bandwidthBps: availableOutgoingBitrateBps,
            isCaptureActive: isCaptureActive,
            observedAt: observedAt,
            diagnostics: &floorDiagnostics
        )

        guard let availableOutgoingBitrateBps,
              availableOutgoingBitrateBps.isFinite,
              availableOutgoingBitrateBps > 0 else {
            bandwidthOnlyDowngradeSampleCount = 0
            applicationLimitedUpgradeSampleCount = 0
            if let probeOriginTier = applicationLimitedProbeOriginTier {
                applicationLimitedProbeHealthySampleCount = 0
                let probeDeadlineExpired = applicationLimitedProbeDeadline.map {
                    observedAt >= $0
                } ?? true
                if latencyPressure {
                    failApplicationLimitedProbe(
                        revertingTo: probeOriginTier
                    )
                    lastSampleHasPositiveSuspensionPressure = true
                    return isCaptureActive ? currentRecommendation : nil
                } else if probeDeadlineExpired {
                    finishApplicationLimitedProbe(
                        revertingTo: probeOriginTier
                    )
                    lastSampleHasPositiveSuspensionPressure = false
                    return isCaptureActive ? currentRecommendation : nil
                } else if applicationLimitedProbeGraceSamplesRemaining > 1 {
                    applicationLimitedProbeGraceSamplesRemaining -= 1
                    lastSampleHasPositiveSuspensionPressure = false
                    return isCaptureActive && didResetForNewPeer
                        ? currentRecommendation
                        : nil
                } else {
                    finishApplicationLimitedProbe(
                        revertingTo: probeOriginTier
                    )
                    lastSampleHasPositiveSuspensionPressure = false
                    return isCaptureActive ? currentRecommendation : nil
                }
            }
            if !bandwidthEstimateIsUnavailable {
                healthyUpgradeSampleCount = 0
            }
            bandwidthEstimateIsUnavailable = true
            if unavailableBandwidthSampleCount < Int.max {
                unavailableBandwidthSampleCount += 1
            }
            // Missing BWE is telemetry, not new proof of congestion. Preserve a prior failed
            // raised-ceiling probe below the reserved floor, however: that probe already removed
            // the sender-limit ambiguity and remains actionable until capacity is positively
            // re-established or an automatic resume authorizes a fresh recovery probe.
            lastSampleHasPositiveSuspensionPressure = latencyPressure
                || belowReserveProbeDisprovedSenderLimitation
            if latencyPressure {
                healthyUpgradeSampleCount = 0
                guard let lowerTier = currentTier.nextLowerQuality else {
                    return isCaptureActive && didResetForNewPeer
                        ? currentRecommendation
                        : nil
                }
                currentTier = lowerTier
                resetQueueEvidenceForTierTransition()
                return isCaptureActive ? currentRecommendation : nil
            }
            if consumeApplicationLimitedProbeCooldown(
                isCaptureActive: isCaptureActive
            ) {
                healthyUpgradeSampleCount = 0
                return isCaptureActive && didResetForNewPeer
                    ? currentRecommendation
                    : nil
            }

            // Missing optional BWE cannot calibrate full-pixel demand. Keep the Show-bound
            // spatial-first profile at its existing caps until measured capacity returns;
            // absence alone is neither congestion nor permission to raise a transport tier.
            if startupSpatialModeIsActive {
                healthyUpgradeSampleCount = 0
                return isCaptureActive && didResetForNewPeer
                    ? currentRecommendation
                    : nil
            }

            // Candidate-pair availableOutgoingBitrate is optional. Once both independent latency
            // signals are healthy, cautiously probe one tier at a time instead of freezing the
            // startup scale forever. Each probe must earn a fresh complete window.
            guard isCaptureActive,
                  let upgradeTier = currentTier.nextHigherQuality,
                  requiredOutgoingBitrateBps(for: upgradeTier)
                    <= Double(configuredTotalRTPBitrateBps),
                  packetQueueAllowsUpgrade,
                  roundTripTimeAllowsUpgrade else {
                healthyUpgradeSampleCount = 0
                return isCaptureActive && didResetForNewPeer
                    ? currentRecommendation
                    : nil
            }
            healthyUpgradeSampleCount += 1
            guard healthyUpgradeSampleCount
                    >= Self.requiredUnavailableBandwidthUpgradeSampleCount else {
                return isCaptureActive && didResetForNewPeer
                    ? currentRecommendation
                    : nil
            }
            currentTier = upgradeTier
            resetQueueEvidenceForTierTransition()
            healthyUpgradeSampleCount = 0
            return currentRecommendation
        }
        if bandwidthEstimateIsUnavailable {
            healthyUpgradeSampleCount = 0
        }
        bandwidthEstimateIsUnavailable = false
        unavailableBandwidthSampleCount = 0
        let effectiveAvailableOutgoingBitrateBps: Double
        if availableOutgoingBitrateBps
            >= Double(configuredTotalRTPBitrateBps)
                * Self.configuredCapacitySaturationRatio {
            effectiveAvailableOutgoingBitrateBps = Double(
                configuredTotalRTPBitrateBps
            )
        } else {
            effectiveAvailableOutgoingBitrateBps = availableOutgoingBitrateBps
        }
        guard let tierSelection = tierDemand.selection(for: currentTier,
                availableBandwidth: effectiveAvailableOutgoingBitrateBps) else {
            return nativePolicyFaultRecommendation(isCaptureActive: isCaptureActive)
        }
        let capacitySustainableTier = tierSelection.sustainableTier
        let independentlyQualifiedUpgradeTier = tierSelection.highestQualifiedUpgradeTier
        let requiredAudioPriorityBitrateBps = requiredOutgoingBitrateBps(
            for: .audioPriority
        )
        if effectiveAvailableOutgoingBitrateBps
            >= requiredAudioPriorityBitrateBps {
            belowReserveProbeDisprovedSenderLimitation = false
            automaticResumeProbeRestoration = nil
        }
        let estimatorMayBeApplicationLimited = estimatorIsApplicationLimited(
            effectiveAvailableOutgoingBitrateBps
        )

        // Only a positive estimate already near the sender ceiling can be self-limited. Give that
        // exact cold-start case one bounded window for RTT/queue evidence; a genuinely low or
        // flapping estimate remains actionable on its first valid sample.
        if latencyPressure {
            positiveBandwidthBootstrapSampleCount =
                Self.requiredPositiveBandwidthBootstrapSampleCount
            applicationLimitedUpgradeSampleCount = 0
        } else if positiveBandwidthBootstrapSampleCount
            < Self.requiredPositiveBandwidthBootstrapSampleCount {
            if independentlyQualifiedUpgradeTier != nil {
                positiveBandwidthBootstrapSampleCount =
                    Self.requiredPositiveBandwidthBootstrapSampleCount
            } else if estimatorMayBeApplicationLimited {
                positiveBandwidthBootstrapSampleCount += 1
                applicationLimitedUpgradeSampleCount = 0
                lastSampleHasPositiveSuspensionPressure = false
                return isCaptureActive && didResetForNewPeer
                    ? currentRecommendation
                    : nil
            } else {
                positiveBandwidthBootstrapSampleCount =
                    Self.requiredPositiveBandwidthBootstrapSampleCount
            }
        }

        if let probeOriginTier = applicationLimitedProbeOriginTier {
            let probeQualifiedTier = capacitySustainableTier.rawValue
                < probeOriginTier.rawValue
                ? capacitySustainableTier
                : nil
            let probeCapacityCollapsed =
                effectiveAvailableOutgoingBitrateBps
                    < applicationLimitedProbeCollapseThreshold(for: probeOriginTier)
            let probeDeadlineExpired = applicationLimitedProbeDeadline.map {
                observedAt >= $0
            } ?? true
            if latencyPressure || probeCapacityCollapsed {
                if probeCapacityCollapsed,
                   effectiveAvailableOutgoingBitrateBps
                    < requiredAudioPriorityBitrateBps {
                    // Raising the sender ceiling removed the censoring ambiguity but the estimate
                    // stayed below the reserved floor. Preserve that evidence across backoff so a
                    // genuinely constrained path can still accumulate bounded pause pressure.
                    belowReserveProbeDisprovedSenderLimitation = true
                }
                failApplicationLimitedProbe(revertingTo: probeOriginTier)
                if capacitySustainableTier.rawValue > probeOriginTier.rawValue {
                    // This is still one terminal decision for the report: independently worse BWE
                    // may protect the audio/control reserve, while probe-only latency merely
                    // restores the unchanged visible origin tier.
                    currentTier = capacitySustainableTier
                    resetQueueEvidenceForTierTransition()
                }
                lastSampleHasPositiveSuspensionPressure = latencyPressure
                    || effectiveAvailableOutgoingBitrateBps
                        < requiredAudioPriorityBitrateBps
                return isCaptureActive ? currentRecommendation : nil
            } else if packetQueueSampleIsInflated,
                      !packetQueueIsInflated,
                      !roundTripTimeIsInflated {
                // A single transition burst neither confirms capacity nor consumes sample grace.
                // The absolute deadline still bounds the ceiling-only probe.
                applicationLimitedUpgradeSampleCount = 0
                applicationLimitedProbeHealthySampleCount = 0
                lastSampleHasPositiveSuspensionPressure = false
                if probeDeadlineExpired {
                    if applicationLimitedProbeBestQualifiedTier == nil,
                       effectiveAvailableOutgoingBitrateBps
                        < requiredAudioPriorityBitrateBps {
                        belowReserveProbeDisprovedSenderLimitation = true
                    }
                    finishApplicationLimitedProbe(
                        revertingTo: probeOriginTier
                    )
                    return isCaptureActive ? currentRecommendation : nil
                }
                return isCaptureActive && didResetForNewPeer
                    ? currentRecommendation
                    : nil
            }

            var intermediateGeometryChanged = false
            let emptyReportPreservesWitness = !probeDeadlineExpired
                && usesNativeRoundTripTimeEvidence
                && floorRecoveryReportIsFresh
                && strictUpgradeEvidenceIsHealthy
                && packetQueueObservation == .noNewPackets
                && applicationLimitedProbeHealthySampleCount > 0
                && applicationLimitedProbeBestQualifiedTier.map {
                    capacitySustainableTier.rawValue <= $0.rawValue
                } == true
                && applicationLimitedProbeQualificationObservedAt.map {
                    let age = $0.duration(to: observedAt)
                    return age >= .zero && age <= Self.lowDelayPacketQueueObservationValidity
                } == true
            if !probeDeadlineExpired,
               strictUpgradeEvidenceIsHealthy,
               !usesNativeRoundTripTimeEvidence
                || (floorRecoveryReportIsFresh && averagePacketSendDelaySeconds != nil),
               let qualifiedTier = probeQualifiedTier {
                if let confirmed = observeApplicationLimitedProbeQualification(
                    tier: qualifiedTier, observedAt: observedAt
                ), confirmed.rawValue < currentTier.rawValue {
                    let highWatermark = capacityProbeBandwidthHighWatermark
                    currentTier = confirmed
                    applicationLimitedProbeConfirmedTier = confirmed
                    resetQueueEvidenceForTierTransition()
                    capacityProbeBandwidthHighWatermark = highWatermark
                    intermediateGeometryChanged = true
                }
            } else if !emptyReportPreservesWitness {
                applicationLimitedProbeHealthySampleCount = 0
            }

            // A proven intermediate tier is useful immediately; the grace window bounds
            // unresolved probes, not how long a qualified improvement must stay hidden.
            if applicationLimitedProbeHealthySampleCount
                >= Self.requiredHealthyUpgradeSampleCount,
               let qualifiedTier = applicationLimitedProbeBestQualifiedTier {
                completeApplicationLimitedProbe(
                    committing: qualifiedTier,
                    availableOutgoingBitrateBps: availableOutgoingBitrateBps,
                    observedAt: observedAt
                )
                lastSampleHasPositiveSuspensionPressure = false
                return isCaptureActive ? currentRecommendation : nil
            }

            if !probeDeadlineExpired,
               applicationLimitedProbeGraceSamplesRemaining > 1,
               strictUpgradeEvidenceIsHealthy,
               let currentProbeCeiling =
                applicationLimitedProbeMaximumTotalRTPBitrateBps {
                let nextProbeCeiling = boundedApplicationLimitedProbeCeiling(
                    availableOutgoingBitrateBps:
                        effectiveAvailableOutgoingBitrateBps,
                    currentCeilingBps: currentProbeCeiling
                )
                if nextProbeCeiling > currentProbeCeiling {
                    applicationLimitedProbeMaximumTotalRTPBitrateBps =
                        nextProbeCeiling
                    applicationLimitedProbeGraceSamplesRemaining -= 1
                    applicationLimitedUpgradeSampleCount = 0
                    lastSampleHasPositiveSuspensionPressure = false
                    return isCaptureActive ? currentRecommendation : nil
                }
            }

            if applicationLimitedProbeGraceSamplesRemaining > 0 {
                applicationLimitedProbeGraceSamplesRemaining -= 1
            }
            applicationLimitedUpgradeSampleCount = 0
            lastSampleHasPositiveSuspensionPressure = false
            if probeDeadlineExpired
                || applicationLimitedProbeGraceSamplesRemaining == 0 {
                if applicationLimitedProbeBestQualifiedTier == nil,
                   effectiveAvailableOutgoingBitrateBps
                    < requiredAudioPriorityBitrateBps {
                    belowReserveProbeDisprovedSenderLimitation = true
                }
                finishApplicationLimitedProbe(revertingTo: probeOriginTier)
                return isCaptureActive ? currentRecommendation : nil
            }
            return isCaptureActive && (didResetForNewPeer || intermediateGeometryChanged)
                ? currentRecommendation
                : nil
        }

        if independentlyQualifiedUpgradeTier != nil,
           directUpgradeEvidenceIsHealthy,
           !latencyPressure {
            resetApplicationLimitedProbeBackoff()
        }

        if floorRecoveryMayBegin,
           beginApplicationLimitedProbe(
               from: .audioPriority,
               availableOutgoingBitrateBps: effectiveAvailableOutgoingBitrateBps,
               observedAt: observedAt
           ) {
            floorDiagnostics.reason = .admitted
            floorRecoveryAttemptConsumed = true
            floorRecoveryProbeWasCancelled = false
            floorRecoveryProbeSeedBandwidthBps = effectiveAvailableOutgoingBitrateBps
            floorRecoveryFirstWitness = nil
            lastSampleHasPositiveSuspensionPressure = false
            return currentRecommendation
        }

        // A near-ceiling estimate is censored by the sender and therefore cannot prove that the
        // path itself is congested. Below the absolute audio/control reserve, extend that neutral
        // treatment only at audioPriority: applying it at higher tiers could pin a truly starved
        // path above the fail-closed floor when strict probe telemetry is unavailable. At the
        // floor, fresh RTT and queue evidence may authorize one bounded higher-ceiling probe.
        let audioPriorityProbeIsFeasible = currentTier == .audioPriority
            && currentTier.nextHigherQuality.map {
                requiredOutgoingBitrateBps(for: $0)
                    <= Double(configuredTotalRTPBitrateBps)
            } == true
        let senderLimitedEstimateCanHoldCurrentTier =
            effectiveAvailableOutgoingBitrateBps
                >= requiredAudioPriorityBitrateBps
            || (audioPriorityProbeIsFeasible
                && !belowReserveProbeDisprovedSenderLimitation)
        let applicationLimitedHoldIsHealthy = !latencyPressure
            && isCaptureActive
            && independentlyQualifiedUpgradeTier == nil
            && estimatorMayBeApplicationLimited
            && senderLimitedEstimateCanHoldCurrentTier
        if applicationLimitedHoldIsHealthy {
            bandwidthOnlyDowngradeSampleCount = 0
            guard currentTier.nextHigherQuality != nil else {
                applicationLimitedUpgradeSampleCount = 0
                lastSampleHasPositiveSuspensionPressure = false
                return isCaptureActive && didResetForNewPeer
                    ? currentRecommendation
                    : nil
            }
            guard !consumeApplicationLimitedProbeCooldown(
                isCaptureActive: isCaptureActive
            ) else {
                applicationLimitedUpgradeSampleCount = 0
                lastSampleHasPositiveSuspensionPressure = false
                return isCaptureActive && didResetForNewPeer
                    ? currentRecommendation
                    : nil
            }
            guard strictUpgradeEvidenceIsHealthy else {
                applicationLimitedUpgradeSampleCount = 0
                lastSampleHasPositiveSuspensionPressure = false
                return isCaptureActive && didResetForNewPeer
                    ? currentRecommendation
                    : nil
            }
            applicationLimitedUpgradeSampleCount += 1
            if applicationLimitedUpgradeSampleCount
                >= Self.requiredApplicationLimitedUpgradeSampleCount {
                applicationLimitedUpgradeSampleCount = 0
                if beginApplicationLimitedProbe(
                    from: currentTier,
                    availableOutgoingBitrateBps:
                        effectiveAvailableOutgoingBitrateBps,
                    observedAt: observedAt
                ) {
                    lastSampleHasPositiveSuspensionPressure = false
                    return isCaptureActive ? currentRecommendation : nil
                }
            }
            lastSampleHasPositiveSuspensionPressure = false
            return isCaptureActive && didResetForNewPeer
                ? currentRecommendation
                : nil
        } else {
            applicationLimitedUpgradeSampleCount = 0
        }

        if packetQueueSampleIsInflated,
           !packetQueueIsInflated,
           !roundTripTimeIsInflated,
           capacitySustainableTier.rawValue <= currentTier.rawValue {
            // One transition-sized queue delta is neither healthy upgrade evidence nor proof that
            // a sender-censored BWE is the path capacity. Hold the visible tier for one sample.
            healthyUpgradeSampleCount = 0
            bandwidthOnlyDowngradeSampleCount = 0
            lastSampleHasPositiveSuspensionPressure = false
            return isCaptureActive && didResetForNewPeer
                ? currentRecommendation
                : nil
        }

        lastSampleHasPositiveSuspensionPressure = latencyPressure
            || effectiveAvailableOutgoingBitrateBps
                < requiredOutgoingBitrateBps(for: .audioPriority)

        var sustainableTier = capacitySustainableTier
        if packetQueueIsInflated,
           !roundTripTimeIsInflated,
           let lowerTier = currentTier.nextLowerQuality {
            // Queue-only congestion walks down one tier per fresh sample. This remains a fast
            // 500 ms response while avoiding a direct collapse based on a censored BWE.
            if lowerTier.rawValue > sustainableTier.rawValue {
                sustainableTier = lowerTier
            }
        } else if latencyPressure,
           let lowerTier = currentTier.nextLowerQuality,
           lowerTier.rawValue > sustainableTier.rawValue {
            sustainableTier = lowerTier
        }
        if sustainableTier.rawValue > currentTier.rawValue {
            healthyUpgradeSampleCount = 0
            if latencyEvidenceIsPositivelyHealthy {
                if bandwidthOnlyDowngradeSampleCount < Int.max {
                    bandwidthOnlyDowngradeSampleCount += 1
                }
                guard bandwidthOnlyDowngradeSampleCount
                        >= Self.requiredBandwidthOnlyDowngradeSampleCount else {
                    return isCaptureActive && didResetForNewPeer
                        ? currentRecommendation
                        : nil
                }
            }
            bandwidthOnlyDowngradeSampleCount = 0
            currentTier = sustainableTier
            resetQueueEvidenceForTierTransition()
            return isCaptureActive ? currentRecommendation : nil
        }
        bandwidthOnlyDowngradeSampleCount = 0

        guard sustainableTier.rawValue < currentTier.rawValue,
              let highestUpgradeTier = independentlyQualifiedUpgradeTier else {
            healthyUpgradeSampleCount = 0
            return isCaptureActive && didResetForNewPeer
                ? currentRecommendation
                : nil
        }
        // A paused sender cannot supply a fresh trustworthy capacity estimate. Preserve the
        // historical one-tier recovery probe until exact receiver presentation reopens ordinary
        // capture; only an active sender may jump directly to the proven target.
        let upgradeTier = isCaptureActive
            ? highestUpgradeTier
            : (currentTier.nextHigherQuality ?? highestUpgradeTier)
        guard !latencyPressure,
              directUpgradeEvidenceIsHealthy else {
            healthyUpgradeSampleCount = 0
            return isCaptureActive && didResetForNewPeer
                ? currentRecommendation
                : nil
        }

        healthyUpgradeSampleCount += 1
        let requiredUpgradeSampleCount = isCaptureActive
            ? Self.requiredHealthyUpgradeSampleCount
            : Self.requiredSuspendedHealthyUpgradeSampleCount
        guard healthyUpgradeSampleCount
                >= requiredUpgradeSampleCount else {
            return isCaptureActive && didResetForNewPeer
                ? currentRecommendation
                : nil
        }
        // The estimate already proves this target with both downgrade headroom and its own
        // upgrade margin. Select the highest independently qualified tier so crossing into the
        // next tier's raw sustainable band can never make recovery worse.
        currentTier = upgradeTier
        resetQueueEvidenceForTierTransition()
        healthyUpgradeSampleCount = 0
        bandwidthOnlyDowngradeSampleCount = 0
        return isCaptureActive ? currentRecommendation : nil
    }

    /// Expires only temporary raised ceilings when both statistics lanes stop
    /// producing native reports. Absence is neither healthy nor congested evidence, so this path
    /// cannot alter baselines, evidence counts, ordinary tiers, or automatic-suspension state.
    mutating func expireApplicationLimitedProbeWithoutReport(
        peerGeneration generation: UInt64,
        isCaptureActive: Bool,
        observedAt: ContinuousClock.Instant = .now
    ) -> FrozenWorldwideScreenVideoEncodingRecommendation? {
        guard peerGeneration == generation else { return nil }
        guard !hasNativeAdaptationPolicyFault else {
            return nativePolicyFaultRecommendation(isCaptureActive: isCaptureActive)
        }
        roundTripTime.age(at: observedAt)
        guard !hasNativeAdaptationPolicyFault else {
            return nativePolicyFaultRecommendation(isCaptureActive: isCaptureActive)
        }
        guard isCaptureActive else {
            return nil
        }
        let previousRecommendation = currentRecommendation
        if let continuity = promotionCapacityContinuity,
           observedAt >= continuity.deadline {
            promotionCapacityContinuity = nil
        }
        if let originTier = applicationLimitedProbeOriginTier,
           let deadline = applicationLimitedProbeDeadline,
           observedAt >= deadline {
            finishApplicationLimitedProbe(revertingTo: originTier)
        }
        if startupSpatialModeIsActive, currentTier == .full {
            clearStartupSpatialMode()
        }
        return currentRecommendation != previousRecommendation
            ? currentRecommendation
            : nil
    }

    /// Recovers a session created by an older automatic-suspension policy, but never turns an
    /// acknowledged visible session opaque. Network adaptation owns encoding limits only: even
    /// under genuine congestion the audio-priority 1 fps recommendation remains the visible floor.
    /// Explicit Hide, authorization loss, and transport uncertainty continue to own fail-closed
    /// capture teardown outside this policy.
    mutating func automaticSuspensionDecision(
        isCaptureActive: Bool,
        isAutomaticallySuspended: Bool
    ) -> FrozenWorldwideScreenVideoAutomaticSuspensionDecision? {
        guard !hasNativeAdaptationPolicyFault else { return nil }
        if isAutomaticallySuspended {
            automaticSuspensionPressureSampleCount = 0
            if maximumSuspensionResumeProbeSampleCount
                < Self.requiredMaximumSuspensionResumeProbeSampleCount {
                maximumSuspensionResumeProbeSampleCount += 1
            }
            if currentTier != .audioPriority {
                stableSuspensionResumeProbeSampleCount = 0
                maximumSuspensionResumeProbeSampleCount = 0
                return .resume
            }
            // Relative RTT pressure can remain permanently elevated after a path settles at a new
            // stable latency. Never turn that stale baseline into a permanent pause: permit one
            // bounded probe after a much longer maximum-pause window. A failed probe resets both
            // counters and therefore enforces the complete cooldown before another attempt.
            if maximumSuspensionResumeProbeSampleCount
                >= Self.requiredMaximumSuspensionResumeProbeSampleCount {
                stableSuspensionResumeProbeSampleCount = 0
                maximumSuspensionResumeProbeSampleCount = 0
                return .resume
            }
            let nativeRTTAllowsStableResume = nativeRoundTripTimeHealth == .healthy
                && roundTripTime.publishedLeaseIsCurrent
            guard !hasNativeAdaptationPolicyFault else {
                _ = nativePolicyFaultRecommendation(isCaptureActive: false)
                return nil
            }
            guard !lastSampleHasLatencyPressure,
                  !usesNativeRoundTripTimeEvidence || nativeRTTAllowsStableResume else {
                stableSuspensionResumeProbeSampleCount = 0
                return nil
            }
            if stableSuspensionResumeProbeSampleCount
                < Self.requiredStableSuspensionResumeProbeSampleCount {
                stableSuspensionResumeProbeSampleCount += 1
            }
            guard stableSuspensionResumeProbeSampleCount
                    >= Self.requiredStableSuspensionResumeProbeSampleCount else {
                return nil
            }
            stableSuspensionResumeProbeSampleCount = 0
            return .resume
        }

        stableSuspensionResumeProbeSampleCount = 0
        maximumSuspensionResumeProbeSampleCount = 0
        automaticSuspensionPressureSampleCount = 0
        return nil
    }

    /// Consumes retained below-reserve evidence only after the suspension coordinator accepts the
    /// exact resume attempt. A rejected decision therefore cannot weaken the pause invariant.
    mutating func automaticResumeAttemptBegan() {
        endFloorRecoveryVisibility()
        promotionCapacityContinuity = nil
        guard automaticResumeProbeRestoration == nil else { return }
        automaticResumeProbeRestoration = AutomaticResumeProbeRestoration(
            belowReserveProbeDisprovedSenderLimitation:
                belowReserveProbeDisprovedSenderLimitation,
            applicationLimitedProbeCooldownSamplesRemaining:
                applicationLimitedProbeCooldownSamplesRemaining,
            applicationLimitedProbeFailureCount:
                applicationLimitedProbeFailureCount
        )
        belowReserveProbeDisprovedSenderLimitation = false
        applicationLimitedUpgradeSampleCount = 0
        resetApplicationLimitedProbeBackoff()
    }

    mutating func automaticResumeAttemptSucceeded() {
        promotionCapacityContinuity = nil
        automaticResumeProbeRestoration = nil
    }

    mutating func automaticResumeAttemptFailed() {
        floorRecoveryFirstWitness = nil
        if floorRecoveryProbeIsActive {
            floorRecoveryProbeWasCancelled = true
        }
        floorRecoveryProbeSeedBandwidthBps = nil
        if let restoration = automaticResumeProbeRestoration {
            belowReserveProbeDisprovedSenderLimitation =
                restoration.belowReserveProbeDisprovedSenderLimitation
            applicationLimitedProbeCooldownSamplesRemaining =
                restoration.applicationLimitedProbeCooldownSamplesRemaining
            applicationLimitedProbeFailureCount =
                restoration.applicationLimitedProbeFailureCount
        }
        automaticResumeProbeRestoration = nil
        currentTier = .audioPriority
        applicationLimitedProbeConfirmedTier = nil
        applicationLimitedProbeQualificationObservedAt = nil
        resetQueueEvidenceForTierTransition()
        healthyUpgradeSampleCount = 0
        bandwidthOnlyDowngradeSampleCount = 0
        applicationLimitedUpgradeSampleCount = 0
        applicationLimitedProbeHealthySampleCount = 0
        applicationLimitedProbeGraceSamplesRemaining = 0
        applicationLimitedProbeDeadline = nil
        applicationLimitedProbeOriginTier = nil
        applicationLimitedProbeBestQualifiedTier = nil
        applicationLimitedProbeMaximumTotalRTPBitrateBps = nil
        resetAutomaticSuspensionMeasurements()
    }

    mutating func resetForInactiveCapture() {
        clearStartupSpatialMode()
        currentTier = tierDemand.initialTier
        resetPathMeasurements()
        resetAutomaticSuspensionMeasurements()
    }

    private func requiredOutgoingBitrateBps(
        for tier: FrozenWorldwideScreenVideoAdaptationTier
    ) -> Double {
        // Tier selection is based on calibrated codec demand. The separately configured 50 Mbps
        // RTP value remains a native sender ceiling, but must not multiply the bandwidth required
        // to choose a resolution/fps tier.
        return tierDemand.profile(for: tier)?.requiredOutgoingBitrateBps ?? .infinity
    }

    private mutating func consumeFloorRecoveryReportIdentity(
        sequence: UInt64?, timestamp: Double?, requiresNativeEvidence: Bool
    ) -> Bool {
        guard requiresNativeEvidence,
              let sequence, sequence > (floorRecoveryLastRegularSequence ?? 0),
              let timestamp, timestamp.isFinite, timestamp > 0,
              timestamp > max(floorRecoveryLastRegularTimestamp ?? 0,
                              capacityProbeNativeReportTimestamp ?? 0) else {
            floorRecoveryFirstWitness = nil
            return false
        }
        floorRecoveryLastRegularSequence = sequence
        floorRecoveryLastRegularTimestamp = timestamp
        return true
    }

    private mutating func observeFloorRecoveryWitness(
        reportIsFresh: Bool,
        queue: PacketQueueObservation,
        roundTripTimeAllowsUpgrade: Bool,
        bandwidthBps: Double?,
        isCaptureActive: Bool,
        observedAt: ContinuousClock.Instant,
        diagnostics: inout FrozenWorldwideScreenFloorRecoveryDiagnostics
    ) -> Bool {
        diagnostics.roundTripTimeDisposition = roundTripTimeDisposition
        diagnostics.roundTripTimeAllowsUpgrade = roundTripTimeAllowsUpgrade
        switch queue {
        case let .measured(delay):
            diagnostics.queueKind = .measured
            diagnostics.queueMicroseconds = FrozenWorldwideScreenFloorRecoveryDiagnostics.boundedMicroseconds(seconds: delay)
        case .noNewPackets: diagnostics.queueKind = .noNewPackets
        case .unavailableOrReset: diagnostics.queueKind = .unavailableOrReset
        }
        let rejection: FrozenWorldwideScreenFloorRecoveryDiagnostics.Reason?
        if !reportIsFresh {
            rejection = diagnostics.identity == .rejectedOrder ? .rejectedOrder : .rejectedTimestamp
        } else if !isCaptureActive || !floorRecoveryVisibilityIsActive {
            rejection = .inactiveVisibility
        } else if floorRecoveryAttemptConsumed {
            rejection = .consumed
        } else if belowReserveProbeDisprovedSenderLimitation {
            rejection = .disproved
        } else if currentTier != .audioPriority {
            rejection = .notFloor
        } else if applicationLimitedProbeOriginTier != nil {
            rejection = .existingProbe
        } else if !usesNativeRoundTripTimeEvidence || nativeRoundTripTimeHealth != .healthy || !roundTripTimeAllowsUpgrade {
            rejection = .rttBlocked
        } else {
            rejection = nil
        }
        if let rejection {
            diagnostics.reason = rejection
            floorRecoveryFirstWitness = nil
            return false
        }
        guard let bandwidthBps, bandwidthBps.isFinite, bandwidthBps > 0 else {
            diagnostics.reason = .invalidBandwidth
            floorRecoveryFirstWitness = nil
            return false
        }
        guard !estimatorIsApplicationLimited(bandwidthBps),
              bandwidthBps * 2 > Double(currentRecommendation.maximumTotalRTPBitrateBps) else {
            diagnostics.reason = estimatorIsApplicationLimited(bandwidthBps) ? .ordinaryProbeEligible : .noHeadroom
            floorRecoveryFirstWitness = nil
            return false
        }
        if let first = floorRecoveryFirstWitness,
           !isFreshPacketQueueObservation(first.observedAt, at: observedAt) {
            floorRecoveryFirstWitness = nil
        }
        if let first = floorRecoveryFirstWitness, bandwidthBps < first.bandwidthBps {
            // Negative evidence retires the window even on an early or no-packet report.
            diagnostics.reason = .bandwidthFalling
            floorRecoveryFirstWitness = nil
            return false
        }
        switch queue {
        case let .measured(delay) where delay <= Self.maximumUpgradePacketSendDelaySeconds:
            break
        case .noNewPackets:
            diagnostics.reason = .noNewPackets
            return false
        case .measured, .unavailableOrReset:
            diagnostics.reason = .queueBlocked
            floorRecoveryFirstWitness = nil
            return false
        }
        if applicationLimitedProbeCooldownSamplesRemaining > 0 {
            diagnostics.reason = .cooldown
            floorRecoveryFirstWitness = nil
            if floorRecoveryLastCooldownObservation.map({
                $0.duration(to: observedAt) >= .milliseconds(Self.sampleIntervalMilliseconds)
            }) ?? true {
                floorRecoveryLastCooldownObservation = observedAt
                _ = consumeApplicationLimitedProbeCooldown(isCaptureActive: true)
            }
            return false
        }
        guard let first = floorRecoveryFirstWitness else {
            diagnostics.reason = .firstWitness
            floorRecoveryFirstWitness = FloorRecoveryWitness(observedAt: observedAt, bandwidthBps: bandwidthBps)
            return false
        }
        // Flat estimates can be sender-limited too. Only this initial bounded discovery
        // accepts equality; subsequent ceiling growth still needs increasing measured BWE.
        guard first.observedAt.duration(to: observedAt) >= .milliseconds(Self.sampleIntervalMilliseconds) else {
            diagnostics.reason = .tooEarly
            return false
        }
        diagnostics.reason = .qualified
        return true
    }

    private func applicationLimitedProbeCollapseThreshold(
        for origin: FrozenWorldwideScreenVideoAdaptationTier
    ) -> Double {
        let confirmedThreshold = applicationLimitedProbeConfirmedTier.map {
            requiredOutgoingBitrateBps(for: $0)
        } ?? 0
        if origin == .audioPriority, let seed = floorRecoveryProbeSeedBandwidthBps {
            return max(confirmedThreshold, seed * Self.applicationLimitedProbeImmediateAbortRatio)
        }
        // Sender headroom is not codec demand: at 50 Mbps the nominal high-tier ceiling
        // would make even the full 16.2 Mbps probe budget look like a capacity collapse.
        return max(
            confirmedThreshold,
            requiredOutgoingBitrateBps(for: .audioPriority),
            Double(tierDemand.profile(for: origin)?.baselineVideoBitrateBps ?? 0)
                * Self.applicationLimitedProbeImmediateAbortRatio
        )
    }

    private func maximumTotalRTPBitrateBps(
        for tier: FrozenWorldwideScreenVideoAdaptationTier
    ) -> Int {
        tierDemand.profile(for: tier)?.maximumTotalRTPBitrateBps ?? 1
    }

    private func boundedApplicationLimitedProbeCeiling(
        availableOutgoingBitrateBps: Double,
        currentCeilingBps: Int
    ) -> Int {
        guard availableOutgoingBitrateBps.isFinite,
              availableOutgoingBitrateBps > 0 else {
            return currentCeilingBps
        }
        let fullProbeCeiling = maximumTotalRTPBitrateBps(for: .full)
        let doubledEstimate = min(
            Double(fullProbeCeiling),
            availableOutgoingBitrateBps * 2
        )
        return max(
            currentCeilingBps,
            Int(doubledEstimate.rounded(.down))
        )
    }

    private func estimatorIsApplicationLimited(
        _ availableOutgoingBitrateBps: Double
    ) -> Bool {
        return availableOutgoingBitrateBps
            >= Double(maximumTotalRTPBitrateBps(for: currentTier))
                * Self.applicationLimitedSaturationRatio
    }

    private mutating func observeApplicationLimitedProbeQualification(
        tier: FrozenWorldwideScreenVideoAdaptationTier,
        observedAt: ContinuousClock.Instant
    ) -> FrozenWorldwideScreenVideoAdaptationTier? {
        guard usesNativeRoundTripTimeEvidence else {
            applicationLimitedProbeQualificationObservedAt = nil
            if applicationLimitedProbeBestQualifiedTier == tier {
                applicationLimitedProbeHealthySampleCount = min(
                    Self.requiredHealthyUpgradeSampleCount,
                    applicationLimitedProbeHealthySampleCount + 1
                )
            } else {
                applicationLimitedProbeHealthySampleCount = 1
            }
            applicationLimitedProbeBestQualifiedTier = tier
            return nil
        }
        var precedingTier: FrozenWorldwideScreenVideoAdaptationTier?
        if applicationLimitedProbeHealthySampleCount > 0,
           let previousAt = applicationLimitedProbeQualificationObservedAt {
            let age = previousAt.duration(to: observedAt)
            if age >= .zero && age < .milliseconds(Self.sampleIntervalMilliseconds) {
                if let previousTier = applicationLimitedProbeBestQualifiedTier,
                   tier.rawValue > previousTier.rawValue {
                    applicationLimitedProbeHealthySampleCount = 0
                    applicationLimitedProbeBestQualifiedTier = nil
                    applicationLimitedProbeQualificationObservedAt = nil
                }
                return nil
            }
            if age >= .milliseconds(Self.sampleIntervalMilliseconds),
               age <= Self.lowDelayPacketQueueObservationValidity {
                precedingTier = applicationLimitedProbeBestQualifiedTier
            }
        }
        applicationLimitedProbeQualificationObservedAt = observedAt
        applicationLimitedProbeBestQualifiedTier = tier
        applicationLimitedProbeHealthySampleCount = precedingTier == tier ? 2 : 1
        guard let precedingTier else { return nil }
        // Improving capacity still proves the lower tier twice; the newest higher tier
        // remains a single witness, while the same discovery deadline keeps running.
        return precedingTier.rawValue > tier.rawValue ? precedingTier : tier
    }

    private mutating func beginApplicationLimitedProbe(
        from originTier: FrozenWorldwideScreenVideoAdaptationTier,
        availableOutgoingBitrateBps: Double,
        observedAt: ContinuousClock.Instant
    ) -> Bool {
        guard let probeTier = originTier.nextHigherQuality,
              requiredOutgoingBitrateBps(for: probeTier)
                <= Double(configuredTotalRTPBitrateBps) else {
            return false
        }
        floorRecoveryProbeSeedBandwidthBps = nil
        let currentCeiling = currentRecommendation.maximumTotalRTPBitrateBps
        applicationLimitedProbeOriginTier = originTier
        applicationLimitedProbeConfirmedTier = nil
        applicationLimitedProbeQualificationObservedAt = nil
        applicationLimitedProbeBestQualifiedTier = nil
        applicationLimitedProbeHealthySampleCount = 0
        let probeCeiling = boundedApplicationLimitedProbeCeiling(
            availableOutgoingBitrateBps: availableOutgoingBitrateBps,
            currentCeilingBps: currentCeiling
        )
        guard probeCeiling > currentCeiling else {
            applicationLimitedProbeOriginTier = nil
            return false
        }
        applicationLimitedProbeMaximumTotalRTPBitrateBps = probeCeiling
        capacityProbeBandwidthHighWatermark = availableOutgoingBitrateBps
        capacityProbeGrowthIsVetoed = false
        promotionCapacityContinuity = nil
        // This is a bitrate/BWE-ceiling-only transition. Preserve the fresh low-delay packet
        // observation so a 1 fps sender can evaluate the next no-packet poll; visible tier changes
        // still reset queue evidence through complete/fail paths.
        applicationLimitedProbeGraceSamplesRemaining =
            Self.applicationLimitedProbeGraceSampleCount
        applicationLimitedProbeDeadline = observedAt.advanced(
            by: Self.applicationLimitedProbeGraceDuration
        )
        applicationLimitedUpgradeSampleCount = 0
        healthyUpgradeSampleCount = 0
        return true
    }

    private mutating func completeApplicationLimitedProbe(
        committing tier: FrozenWorldwideScreenVideoAdaptationTier,
        availableOutgoingBitrateBps: Double? = nil,
        observedAt: ContinuousClock.Instant? = nil
    ) {
        let probeCeiling = applicationLimitedProbeMaximumTotalRTPBitrateBps
        floorRecoveryProbeSeedBandwidthBps = nil
        floorRecoveryProbeWasCancelled = false
        currentTier = tier
        resetQueueEvidenceForTierTransition()
        applicationLimitedProbeOriginTier = nil
        applicationLimitedProbeBestQualifiedTier = nil
        applicationLimitedProbeMaximumTotalRTPBitrateBps = nil
        applicationLimitedProbeConfirmedTier = nil
        applicationLimitedProbeQualificationObservedAt = nil
        applicationLimitedProbeHealthySampleCount = 0
        applicationLimitedProbeGraceSamplesRemaining = 0
        applicationLimitedProbeDeadline = nil
        applicationLimitedUpgradeSampleCount = 0
        belowReserveProbeDisprovedSenderLimitation = false
        automaticResumeProbeRestoration = nil
        resetApplicationLimitedProbeBackoff()
        if let availableOutgoingBitrateBps,
           availableOutgoingBitrateBps.isFinite,
           availableOutgoingBitrateBps > 0,
           let observedAt,
           let probeCeiling {
            let provenCeiling = Int(min(
                Double(configuredTotalRTPBitrateBps),
                Double(probeCeiling),
                availableOutgoingBitrateBps
            ).rounded(.down))
            if provenCeiling > maximumTotalRTPBitrateBps(for: tier) {
                // Preserve observed capacity through the geometry change, not the doubled probe.
                promotionCapacityContinuity = PromotionCapacityContinuity(
                    tier: tier,
                    maximumTotalRTPBitrateBps: provenCeiling,
                    deadline: observedAt.advanced(
                        by: Self.promotionCapacityContinuityDuration
                    )
                )
            }
        }
    }

    private mutating func updatePromotionCapacityContinuity(
        availableOutgoingBitrateBps: Double?,
        isCaptureActive: Bool,
        observedAt: ContinuousClock.Instant
    ) {
        guard var continuity = promotionCapacityContinuity else { return }
        guard isCaptureActive,
              continuity.tier == currentTier,
              observedAt < continuity.deadline,
              let availableOutgoingBitrateBps,
              availableOutgoingBitrateBps.isFinite,
              availableOutgoingBitrateBps > 0 else {
            promotionCapacityContinuity = nil
            return
        }
        let provenCeiling = Int(min(
            Double(configuredTotalRTPBitrateBps),
            availableOutgoingBitrateBps
        ).rounded(.down))
        continuity.maximumTotalRTPBitrateBps = min(
            continuity.maximumTotalRTPBitrateBps,
            provenCeiling
        )
        promotionCapacityContinuity = continuity.maximumTotalRTPBitrateBps
            > maximumTotalRTPBitrateBps(for: currentTier)
            ? continuity
            : nil
    }

    private mutating func finishApplicationLimitedProbe(
        revertingTo originTier: FrozenWorldwideScreenVideoAdaptationTier
    ) {
        if let confirmed = applicationLimitedProbeConfirmedTier {
            completeApplicationLimitedProbe(committing: confirmed)
        } else if applicationLimitedProbeHealthySampleCount
            >= Self.requiredHealthyUpgradeSampleCount,
           let qualifiedTier = applicationLimitedProbeBestQualifiedTier {
            completeApplicationLimitedProbe(committing: qualifiedTier)
        } else {
            failApplicationLimitedProbe(revertingTo: originTier)
        }
    }

    private mutating func revertApplicationLimitedProbeIfActive() {
        guard let applicationLimitedProbeOriginTier else { return }
        if floorRecoveryProbeIsActive {
            floorRecoveryProbeWasCancelled = true
            floorRecoveryProbeSeedBandwidthBps = nil
        }
        currentTier = applicationLimitedProbeOriginTier
        resetQueueEvidenceForTierTransition()
        self.applicationLimitedProbeOriginTier = nil
        applicationLimitedProbeConfirmedTier = nil
        applicationLimitedProbeQualificationObservedAt = nil
        applicationLimitedProbeBestQualifiedTier = nil
        applicationLimitedProbeMaximumTotalRTPBitrateBps = nil
        applicationLimitedProbeHealthySampleCount = 0
        applicationLimitedProbeGraceSamplesRemaining = 0
        applicationLimitedProbeDeadline = nil
    }

    /// Retains the long exponential backoff for an actually suspended legacy sender, but never
    /// lets stale failure history hide a changed network from a currently visible session for
    /// longer than the active reevaluation window.
    private mutating func consumeApplicationLimitedProbeCooldown(
        isCaptureActive: Bool
    ) -> Bool {
        if isCaptureActive {
            applicationLimitedProbeCooldownSamplesRemaining = min(
                applicationLimitedProbeCooldownSamplesRemaining,
                Self.maximumActiveApplicationLimitedProbeCooldownSampleCount
            )
        }
        guard applicationLimitedProbeCooldownSamplesRemaining > 0 else {
            return false
        }
        applicationLimitedProbeCooldownSamplesRemaining -= 1
        return true
    }

    private mutating func failApplicationLimitedProbe(
        revertingTo originTier: FrozenWorldwideScreenVideoAdaptationTier
    ) {
        if floorRecoveryProbeIsActive {
            floorRecoveryProbeWasCancelled = true
            floorRecoveryProbeSeedBandwidthBps = nil
            belowReserveProbeDisprovedSenderLimitation = true
        }
        currentTier = originTier
        resetQueueEvidenceForTierTransition()
        applicationLimitedProbeOriginTier = nil
        applicationLimitedProbeConfirmedTier = nil
        applicationLimitedProbeQualificationObservedAt = nil
        applicationLimitedProbeBestQualifiedTier = nil
        applicationLimitedProbeMaximumTotalRTPBitrateBps = nil
        applicationLimitedProbeHealthySampleCount = 0
        applicationLimitedProbeGraceSamplesRemaining = 0
        applicationLimitedProbeDeadline = nil
        applicationLimitedUpgradeSampleCount = 0
        applicationLimitedProbeFailureCount = min(
            applicationLimitedProbeFailureCount + 1,
            Int.bitWidth - 1
        )
        let exponent = min(
            applicationLimitedProbeFailureCount - 1,
            3
        )
        applicationLimitedProbeCooldownSamplesRemaining = min(
            Self.maximumApplicationLimitedProbeCooldownSampleCount,
            Self.initialApplicationLimitedProbeCooldownSampleCount
                * (1 << exponent)
        )
    }

    private mutating func resetApplicationLimitedProbeBackoff() {
        applicationLimitedProbeCooldownSamplesRemaining = 0
        applicationLimitedProbeFailureCount = 0
    }

    private mutating func resetPathMeasurements() {
        floorRecoveryFirstWitness = nil
        applicationLimitedProbeConfirmedTier = nil
        applicationLimitedProbeQualificationObservedAt = nil
        if floorRecoveryProbeIsActive {
            floorRecoveryProbeWasCancelled = true
        }
        floorRecoveryProbeSeedBandwidthBps = nil
        capacityProbeSample = nil
        capacityProbeBandwidthHighWatermark = nil
        promotionCapacityContinuity = nil
        healthyUpgradeSampleCount = 0
        bandwidthOnlyDowngradeSampleCount = 0
        packetQueue.reset(path: true)
        unavailableBandwidthSampleCount = 0
        positiveBandwidthBootstrapSampleCount = 0
        applicationLimitedUpgradeSampleCount = 0
        applicationLimitedProbeHealthySampleCount = 0
        applicationLimitedProbeGraceSamplesRemaining = 0
        applicationLimitedProbeDeadline = nil
        applicationLimitedProbeOriginTier = nil
        applicationLimitedProbeBestQualifiedTier = nil
        applicationLimitedProbeMaximumTotalRTPBitrateBps = nil
        belowReserveProbeDisprovedSenderLimitation = false
        automaticResumeProbeRestoration = nil
        resetApplicationLimitedProbeBackoff()
        roundTripTime.resetPath()
        bandwidthEstimateIsUnavailable = false
        lastSampleHasLatencyPressure = false
        lastSampleHasPositiveSuspensionPressure = false
        lastAveragePacketSendDelaySeconds = nil
    }

    private mutating func resetQueueEvidenceForTierTransition() {
        floorRecoveryFirstWitness = nil
        capacityProbeSample = nil
        capacityProbeBandwidthHighWatermark = nil
        promotionCapacityContinuity = nil
        packetQueue.reset(path: false)
    }

    private mutating func resetAutomaticSuspensionMeasurements() {
        automaticSuspensionPressureSampleCount = 0
        stableSuspensionResumeProbeSampleCount = 0
        maximumSuspensionResumeProbeSampleCount = 0
    }

    private func isFreshPacketQueueObservation(
        _ observation: ContinuousClock.Instant,
        at observedAt: ContinuousClock.Instant
    ) -> Bool {
        let age = observation.duration(to: observedAt)
        return age >= .zero
            && age <= Self.lowDelayPacketQueueObservationValidity
    }

}
