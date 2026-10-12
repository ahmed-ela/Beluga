import Foundation

/// Closed, privacy-safe reasons why the iPhone renderer is intentionally covered.
public enum WorldwideScreenLivenessCoverState: String, Codable, Equatable, Sendable {
    case none
    case intentionalBandwidthPause
    case privacy
    case resuming
    case screenHidden

    public var statusText: String {
        switch self {
        case .none:
            "Not covered"
        case .intentionalBandwidthPause:
            "Screen paused to save bandwidth"
        case .privacy:
            "Screen paused for privacy"
        case .resuming:
            "Resuming screen"
        case .screenHidden:
            "Screen is not being presented"
        }
    }
}

/// Evidence-bounded client pipeline states. Unchanged rendered content is kept distinct from a
/// stalled presentation because a static desktop is valid screen content.
public enum WorldwideScreenLivenessState: String, Codable, CaseIterable, Equatable, Sendable {
    case intentionallyCovered
    case covered
    case trackMissing
    case awaitingEvidence
    case inboundRTPStalled
    case decodeStalled
    case presentationStalled
    case presentingUnchanged
    case presentingLive

    public var statusText: String {
        switch self {
        case .intentionallyCovered:
            WorldwideScreenLivenessCoverState.intentionalBandwidthPause.statusText
        case .covered:
            "Screen presentation is covered"
        case .trackMissing:
            "Waiting for the remote video track"
        case .awaitingEvidence:
            "Waiting for client screen evidence"
        case .inboundRTPStalled:
            "Inbound screen RTP is not advancing"
        case .decodeStalled:
            "Inbound screen video is not decoding"
        case .presentationStalled:
            "Decoded screen video is not presenting"
        case .presentingUnchanged:
            "Screen frames are presenting without content changes"
        case .presentingLive:
            "Screen frames are presenting and changing"
        }
    }
}

/// Why the classifier discarded its single retained comparison floor.
public enum WorldwideScreenLivenessResetReason: String, Codable, Equatable, Sendable {
    case none
    case initialSample
    case generationChanged
    case counterRegression
}

/// Content-free renderer totals copied from `WebRTCVideoRenderObservation` at MainActor receipt.
/// The renderer-local digest, RTP timestamp, and media timestamp are deliberately excluded.
public struct WorldwideScreenLivenessRenderObservation: Codable, Equatable, Sendable {
    public let presentedFrames: UInt64
    public let contentSamples: UInt64
    public let contentChanges: UInt64
    public let presentedAtUptimeNanoseconds: UInt64
    public let frameWidth: Int
    public let frameHeight: Int

    public init(
        presentedFrames: UInt64,
        contentSamples: UInt64,
        contentChanges: UInt64,
        presentedAtUptimeNanoseconds: UInt64,
        frameWidth: Int,
        frameHeight: Int
    ) {
        self.presentedFrames = presentedFrames
        self.contentSamples = contentSamples
        self.contentChanges = contentChanges
        self.presentedAtUptimeNanoseconds = presentedAtUptimeNanoseconds
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }
}

#if os(iOS)
public extension WorldwideScreenLivenessRenderObservation {
    init(
        _ observation: WebRTCVideoRenderObservation,
        presentedAtUptimeNanoseconds: UInt64
    ) {
        self.init(
            presentedFrames: observation.frameCount,
            contentSamples: observation.contentSampleCount,
            contentChanges: observation.contentChangeCount,
            presentedAtUptimeNanoseconds: presentedAtUptimeNanoseconds,
            frameWidth: observation.width,
            frameHeight: observation.height
        )
    }
}
#endif

/// One deterministic classifier input. `generation` is an ephemeral local counter rotated when
/// the session, remote track, or renderer counter domain changes.
public struct WorldwideScreenLivenessSample: Equatable, Sendable {
    public let generation: UInt64
    public let observedAtUptimeNanoseconds: UInt64
    public let hasRemoteVideoTrack: Bool
    public let coverState: WorldwideScreenLivenessCoverState
    public let inboundVideo: WebRTCVideoStatistics?
    public let renderObservation: WorldwideScreenLivenessRenderObservation?

    public init(
        generation: UInt64,
        observedAtUptimeNanoseconds: UInt64,
        hasRemoteVideoTrack: Bool,
        coverState: WorldwideScreenLivenessCoverState,
        inboundVideo: WebRTCVideoStatistics?,
        renderObservation: WorldwideScreenLivenessRenderObservation?
    ) {
        self.generation = generation
        self.observedAtUptimeNanoseconds = observedAtUptimeNanoseconds
        self.hasRemoteVideoTrack = hasRemoteVideoTrack
        self.coverState = coverState
        self.inboundVideo = inboundVideo
        self.renderObservation = renderObservation
    }
}

/// A bounded, privacy-safe projection suitable for local UI and conversion to a wire heartbeat.
/// It retains no pixels, content digest, receiver identity, SSRC, track ID, or session UUID.
public struct WorldwideScreenLivenessDiagnosticSnapshot: Codable, Equatable, Sendable {
    public static let maximumPresentationAgeMilliseconds: UInt64 = 86_400_000

    public let state: WorldwideScreenLivenessState
    public let resetReason: WorldwideScreenLivenessResetReason
    public let generation: UInt64
    public let trackAttached: Bool
    public let coverState: WorldwideScreenLivenessCoverState
    public let inboundBytes: UInt64?
    public let inboundByteDelta: UInt64?
    public let inboundPackets: UInt64?
    public let inboundPacketDelta: UInt64?
    public let decodedFrames: UInt64?
    public let decodedFrameDelta: UInt64?
    public let presentedFrames: UInt64?
    public let presentedFrameDelta: UInt64?
    public let contentSamples: UInt64?
    public let contentSampleDelta: UInt64?
    public let contentChanges: UInt64?
    public let contentChangeDelta: UInt64?
    public let lastPresentationAgeMilliseconds: UInt64?
    public let frameWidth: Int?
    public let frameHeight: Int?
    public let framesPerSecond: Double?

    public var statusText: String {
        switch state {
        case .intentionallyCovered:
            WorldwideScreenLivenessCoverState.intentionalBandwidthPause.statusText
        case .covered:
            coverState.statusText
        default:
            state.statusText
        }
    }

    public static var unobserved: Self {
        Self(
            state: .trackMissing,
            resetReason: .initialSample,
            generation: 0,
            trackAttached: false,
            coverState: .screenHidden,
            inboundBytes: nil,
            inboundByteDelta: nil,
            inboundPackets: nil,
            inboundPacketDelta: nil,
            decodedFrames: nil,
            decodedFrameDelta: nil,
            presentedFrames: nil,
            presentedFrameDelta: nil,
            contentSamples: nil,
            contentSampleDelta: nil,
            contentChanges: nil,
            contentChangeDelta: nil,
            lastPresentationAgeMilliseconds: nil,
            frameWidth: nil,
            frameHeight: nil,
            framesPerSecond: nil
        )
    }

    init(
        state: WorldwideScreenLivenessState,
        resetReason: WorldwideScreenLivenessResetReason,
        generation: UInt64,
        trackAttached: Bool,
        coverState: WorldwideScreenLivenessCoverState,
        inboundBytes: UInt64?,
        inboundByteDelta: UInt64?,
        inboundPackets: UInt64?,
        inboundPacketDelta: UInt64?,
        decodedFrames: UInt64?,
        decodedFrameDelta: UInt64?,
        presentedFrames: UInt64?,
        presentedFrameDelta: UInt64?,
        contentSamples: UInt64?,
        contentSampleDelta: UInt64?,
        contentChanges: UInt64?,
        contentChangeDelta: UInt64?,
        lastPresentationAgeMilliseconds: UInt64?,
        frameWidth: Int?,
        frameHeight: Int?,
        framesPerSecond: Double?
    ) {
        self.state = state
        self.resetReason = resetReason
        self.generation = generation
        self.trackAttached = trackAttached
        self.coverState = coverState
        self.inboundBytes = inboundBytes
        self.inboundByteDelta = inboundByteDelta
        self.inboundPackets = inboundPackets
        self.inboundPacketDelta = inboundPacketDelta
        self.decodedFrames = decodedFrames
        self.decodedFrameDelta = decodedFrameDelta
        self.presentedFrames = presentedFrames
        self.presentedFrameDelta = presentedFrameDelta
        self.contentSamples = contentSamples
        self.contentSampleDelta = contentSampleDelta
        self.contentChanges = contentChanges
        self.contentChangeDelta = contentChangeDelta
        self.lastPresentationAgeMilliseconds = lastPresentationAgeMilliseconds
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.framesPerSecond = framesPerSecond
    }
}

/// Constant-space Rust-backed classifier. Its copied state and output contain diagnostics only.
public struct WorldwideScreenLivenessClassifier: Sendable {
    public static let freshPresentationWindowNanoseconds: UInt64 = 2_500_000_000
    private var state = BelugaRustScreenLivenessBoundary.State()
    private let producer: BelugaRustScreenLivenessProducer

    public init() { producer = .actual }
    internal init(producer: BelugaRustScreenLivenessProducer) { self.producer = producer }
    public mutating func reset() { state = BelugaRustScreenLivenessBoundary.State() }

    public mutating func observe(
        _ sample: WorldwideScreenLivenessSample
    ) throws -> WorldwideScreenLivenessDiagnosticSnapshot {
        let rawSample = BelugaRustScreenLivenessBoundary.sample(sample)
        let output = producer.observe(1, state, rawSample)
        guard BelugaRustScreenLivenessBoundary.accepts(before: state, sample: rawSample, output: output) else {
            throw WorldwideScreenLivenessBridgeError.invalidBridge
        }
        let snapshot = try BelugaRustScreenLivenessBoundary.snapshot(output.snapshot)
        state = output.state
        return snapshot
    }

    internal var rawStateForTests: BelugaRustScreenLivenessBoundary.State { state }
}
