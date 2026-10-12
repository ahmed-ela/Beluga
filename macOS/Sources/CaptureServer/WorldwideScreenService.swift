import CaptureCore
import AudioToolbox
import CoreMedia
import Foundation
import RemoteSessionCore
import WebRTCTransport

struct WorldwideRemoteMediaPublicationMachine: Sendable, Equatable {
    struct Attempt: Sendable, Equatable {
        struct ID: Sendable, Equatable {
            fileprivate let peerEpoch: UInt64
            fileprivate let ordinal: UInt64
        }

        let id: ID
        let desiredVersion: UInt64
        let update: WebRTCRemoteMediaStateUpdate
    }

    enum Completion: Sendable, Equatable {
        case ignored
        case finished
        case publishNewest
        case retryLatest
    }

    private(set) var peerEpoch: UInt64 = 0
    private(set) var nextAttemptOrdinal: UInt64 = 0
    private(set) var desiredControllerRevision: UInt64?
    private(set) var desiredItem: WebRTCRemoteMediaItem?
    private(set) var desiredAdditionalItems: [WebRTCRemoteMediaItem] = []
    private(set) var desiredVersion: UInt64 = 0
    private(set) var publishedVersion: UInt64 = 0
    private(set) var lastSuccessfullySent: WebRTCRemoteMediaStateUpdate?
    private(set) var remoteMediaIsAvailable = false
    private(set) var inFlight: Attempt?

    var hasPendingPublication: Bool {
        desiredControllerRevision != nil && desiredVersion != publishedVersion
    }

    mutating func applyControllerUpdate(_ update: WebRTCRemoteMediaStateUpdate) {
        guard update.isValid,
              update.revision > (desiredControllerRevision ?? 0) else { return }
        desiredControllerRevision = update.revision
        desiredItem = update.item
        desiredAdditionalItems = update.additionalItems
        advanceDesiredVersion()
    }

    mutating func requestRefresh() {
        guard desiredControllerRevision != nil else { return }
        advanceDesiredVersion()
    }

    mutating func setRemoteMediaAvailable(_ isAvailable: Bool) {
        guard remoteMediaIsAvailable != isAvailable else { return }
        if !isAvailable,
           desiredControllerRevision != nil,
           (inFlight != nil || !hasPendingPublication) {
            // A same-peer authorization renegotiation must republish the last desired value but
            // must not reset the monotonically increasing wire revision.
            advanceDesiredVersion()
        }
        remoteMediaIsAvailable = isAvailable
    }

    mutating func beginIfPossible(transportIsReady: Bool) -> Attempt? {
        guard transportIsReady,
              remoteMediaIsAvailable,
              inFlight == nil,
              hasPendingPublication else { return nil }
        guard let wireRevision = Self.nextWireRevision(
            after: lastSuccessfullySent?.revision
        ) else {
            // The viewer's recovery floor saturates at max; wrapping to one on the same peer
            // would be rejected. Only a fresh peer authorization may reset the wire sequence.
            return nil
        }
        nextAttemptOrdinal &+= 1
        if nextAttemptOrdinal == 0 { nextAttemptOrdinal = 1 }
        let attempt = Attempt(
            id: Attempt.ID(
                peerEpoch: peerEpoch,
                ordinal: nextAttemptOrdinal
            ),
            desiredVersion: desiredVersion,
            update: WebRTCRemoteMediaStateUpdate(
                revision: wireRevision,
                item: desiredItem,
                additionalItems: desiredAdditionalItems
            )
        )
        inFlight = attempt
        return attempt
    }

    static func nextWireRevision(after revision: UInt64?) -> UInt64? {
        let revision = revision ?? 0
        guard revision < UInt64.max else { return nil }
        return revision + 1
    }

    mutating func complete(
        _ attempt: Attempt,
        succeeded: Bool
    ) -> Completion {
        guard inFlight?.id == attempt.id,
              attempt.id.peerEpoch == peerEpoch else { return .ignored }
        inFlight = nil
        if succeeded {
            lastSuccessfullySent = attempt.update
            publishedVersion = attempt.desiredVersion
        }
        if desiredVersion != attempt.desiredVersion {
            return .publishNewest
        }
        return succeeded ? .finished : .retryLatest
    }

    mutating func startNewPeer() {
        peerEpoch &+= 1
        nextAttemptOrdinal = 0
        publishedVersion = 0
        lastSuccessfullySent = nil
        remoteMediaIsAvailable = false
        inFlight = nil
    }

    mutating func stop() {
        startNewPeer()
        desiredControllerRevision = nil
        desiredItem = nil
        desiredAdditionalItems = []
        desiredVersion = 0
        publishedVersion = 0
    }

    private mutating func advanceDesiredVersion() {
        desiredVersion &+= 1
        if desiredVersion == 0 { desiredVersion = 1 }
    }
}

struct WorldwideRemoteMediaPublicationRetryGate: Sendable, Equatable {
    struct Token: Sendable, Equatable {
        fileprivate let epoch: UInt64
    }

    private(set) var epoch: UInt64 = 0
    private(set) var isScheduled = false

    mutating func schedule() -> Token? {
        guard !isScheduled else { return nil }
        isScheduled = true
        return Token(epoch: epoch)
    }

    mutating func consume(_ token: Token) -> Bool {
        guard isScheduled, token.epoch == epoch else { return false }
        isScheduled = false
        return true
    }

    mutating func cancel() {
        epoch &+= 1
        isScheduled = false
    }
}

struct WorldwideRemoteMediaCommandQueueCapacity: Sendable, Equatable {
    static let maximumCount = 16
    private(set) var count = 0
    private(set) var generation: UInt64 = 0

    mutating func reserve() -> UInt64? {
        guard count < Self.maximumCount else { return nil }
        count += 1
        return generation
    }

    mutating func finish(generation candidate: UInt64) {
        guard candidate == generation else { return }
        if count > 0 { count -= 1 }
    }

    func admits(generation candidate: UInt64) -> Bool {
        candidate == generation
    }

    mutating func reset() {
        generation &+= 1
        count = 0
    }
}

enum WorldwideRemoteInputFormatOrigin: Equatable, Sendable {
    case captureGateUnavailable(WorldwideScreenCaptureGateDiagnostic?)
    case controller(MacRemoteInputScreenFormatDiagnostic)
    case controllerUnknown
}

enum WorldwideScreenFrameMetadataDiagnosticState: String, Equatable, Sendable {
    case none
    case valid
    case absent
    case invalid
}

struct WorldwideScreenCaptureGateDiagnostic: Equatable, Sendable {
    let phase: String
    let formatIsProven: Bool
    let displayConfigurationInProgress: Bool
    let frameMetadataState: WorldwideScreenFrameMetadataDiagnosticState
    let frameSurfaceWidth: Int?
    let frameSurfaceHeight: Int?
    let retainedProvenGeometry: Bool
}

struct WorldwideRemoteInputInjectionOutcome: Equatable, Sendable {
    let result: MacRemoteInputResult
    let windowResizeFeedback: MacRemoteWindowResizeFeedback?
    let isWindowMove: Bool
    let verifiedFocus: MacRemoteInputFocus?
    let formatOrigin: WorldwideRemoteInputFormatOrigin?

    init(
        _ result: MacRemoteInputResult,
        windowResizeFeedback: MacRemoteWindowResizeFeedback? = nil,
        verifiedFocus: MacRemoteInputFocus? = nil,
        formatOrigin: WorldwideRemoteInputFormatOrigin? = nil
    ) {
        self.result = result
        self.windowResizeFeedback = windowResizeFeedback
        self.isWindowMove = false
        self.verifiedFocus = verifiedFocus
        self.formatOrigin = formatOrigin
    }

    init(_ diagnosedResult: MacRemoteInputDiagnosedResult) {
        result = diagnosedResult.result
        windowResizeFeedback = nil
        isWindowMove = false
        verifiedFocus = nil
        if let diagnostic = diagnosedResult.screenFormatDiagnostic {
            formatOrigin = .controller(diagnostic)
        } else if case .rejected(.screenFormatChanging) = diagnosedResult.result {
            formatOrigin = .controllerUnknown
        } else {
            formatOrigin = nil
        }
    }

    init(_ diagnosedResult: MacRemoteWindowResizeDiagnosedResult, isWindowMove: Bool = false) {
        result = diagnosedResult.result
        windowResizeFeedback = diagnosedResult.windowResizeFeedback
        self.isWindowMove = isWindowMove
        verifiedFocus = diagnosedResult.verifiedFocus
        if let diagnostic = diagnosedResult.screenFormatDiagnostic {
            formatOrigin = .controller(diagnostic)
        } else if case .rejected(.screenFormatChanging) = diagnosedResult.result {
            formatOrigin = .controllerUnknown
        } else {
            formatOrigin = nil
        }
    }
}

protocol WorldwideFocusedWindowResizeDispatching: Sendable {
    func requestFocusedWindowResizeTarget(
        screenRequestID: UInt64,
        inputSessionID: UUID,
        viewerVideoSize: MacRemoteInputVideoSize?
    ) -> MacRemoteWindowResizeDiagnosedResult

    func selectWindowForResize(
        screenRequestID: UInt64,
        inputSessionID: UUID,
        normalizedPoint: MacRemoteNormalizedPoint,
        viewerVideoSize: MacRemoteInputVideoSize?
    ) -> MacRemoteWindowResizeDiagnosedResult

    func commitFocusedWindowResize(
        screenRequestID: UInt64,
        inputSessionID: UUID,
        targetGeneration: UUID,
        start: MacRemoteNormalizedPoint,
        end: MacRemoteNormalizedPoint,
        viewerVideoSize: MacRemoteInputVideoSize?
    ) -> MacRemoteWindowResizeDiagnosedResult
}

extension MacRemoteInputController: WorldwideFocusedWindowResizeDispatching {}

enum WorldwideFocusedWindowResizeDispatcher {
    static func dispatch(
        _ request: WebRTCInputRequest,
        to controller: any WorldwideFocusedWindowResizeDispatching
    ) -> WorldwideRemoteInputInjectionOutcome? {
        let viewerVideoSize = request.viewerVideoSize.map {
            MacRemoteInputVideoSize(width: $0.width, height: $0.height)
        }
        switch request.action {
        case .requestFocusedWindowResizeTarget:
            return WorldwideRemoteInputInjectionOutcome(
                controller.requestFocusedWindowResizeTarget(
                    screenRequestID: request.screenRequestID,
                    inputSessionID: request.inputSessionID,
                    viewerVideoSize: viewerVideoSize
                )
            )

        case .selectWindowForResize(let point):
            return WorldwideRemoteInputInjectionOutcome(
                controller.selectWindowForResize(
                    screenRequestID: request.screenRequestID,
                    inputSessionID: request.inputSessionID,
                    normalizedPoint: .init(x: point.x, y: point.y),
                    viewerVideoSize: viewerVideoSize
                )
            )

        case .commitFocusedWindowResize(let targetGeneration, let start, let end):
            return WorldwideRemoteInputInjectionOutcome(
                controller.commitFocusedWindowResize(
                    screenRequestID: request.screenRequestID,
                    inputSessionID: request.inputSessionID,
                    targetGeneration: targetGeneration,
                    start: .init(x: start.x, y: start.y),
                    end: .init(x: end.x, y: end.y),
                    viewerVideoSize: viewerVideoSize
                )
            )

        default:
            return nil
        }
    }
}

protocol WorldwideFocusedWindowMoveDispatching: Sendable {
    func requestFocusedWindowMoveTarget(
        screenRequestID: UInt64, inputSessionID: UUID, viewerVideoSize: MacRemoteInputVideoSize?
    ) -> MacRemoteWindowResizeDiagnosedResult
    func selectWindowForMove(
        screenRequestID: UInt64, inputSessionID: UUID, normalizedPoint: MacRemoteNormalizedPoint,
        viewerVideoSize: MacRemoteInputVideoSize?
    ) -> MacRemoteWindowResizeDiagnosedResult
    func commitFocusedWindowMove(
        screenRequestID: UInt64, inputSessionID: UUID, targetGeneration: UUID,
        start: MacRemoteNormalizedPoint, end: MacRemoteNormalizedPoint,
        viewerVideoSize: MacRemoteInputVideoSize?,
        allowsRecoverableOffscreen: Bool
    ) -> MacRemoteWindowResizeDiagnosedResult
}

extension MacRemoteInputController: WorldwideFocusedWindowMoveDispatching {}

enum WorldwideFocusedWindowMoveDispatcher {
    static func dispatch(
        _ request: WebRTCInputRequest,
        to controller: any WorldwideFocusedWindowMoveDispatching
    ) -> WorldwideRemoteInputInjectionOutcome? {
        let size = request.viewerVideoSize.map { MacRemoteInputVideoSize(width: $0.width, height: $0.height) }
        let result: MacRemoteWindowResizeDiagnosedResult
        switch request.action {
        case .requestFocusedWindowMoveTarget:
            result = controller.requestFocusedWindowMoveTarget(
                screenRequestID: request.screenRequestID, inputSessionID: request.inputSessionID,
                viewerVideoSize: size
            )
        case .selectWindowForMove(let point):
            result = controller.selectWindowForMove(
                screenRequestID: request.screenRequestID, inputSessionID: request.inputSessionID,
                normalizedPoint: .init(x: point.x, y: point.y), viewerVideoSize: size
            )
        case .commitFocusedWindowMove(
            let generation,
            let start,
            let end,
            let allowsRecoverableOffscreen
        ):
            result = controller.commitFocusedWindowMove(
                screenRequestID: request.screenRequestID, inputSessionID: request.inputSessionID,
                targetGeneration: generation, start: .init(x: start.x, y: start.y),
                end: .init(x: end.x, y: end.y), viewerVideoSize: size,
                allowsRecoverableOffscreen: allowsRecoverableOffscreen
            )
        default:
            return nil
        }
        return WorldwideRemoteInputInjectionOutcome(result, isWindowMove: true)
    }
}

/// Serializes the irreversible resumed acknowledgement against every cleanup path. The operation
/// runs while the latch is held, so cleanup can only claim failure before it starts or observe the
/// completed commit afterward.
final class WorldwideScreenAutomaticResumeCommitLatch: @unchecked Sendable {
    private enum State {
        case pending
        case committed
        case failureClaimed
    }

    private let lock = NSLock()
    private var state = State.pending

    func commit<Result>(_ operation: () throws -> Result) throws -> Result {
        try lock.withLock {
            guard case .pending = state else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            let result = try operation()
            state = .committed
            return result
        }
    }

    func claimFailure() -> Bool {
        lock.withLock {
            guard case .pending = state else { return false }
            state = .failureClaimed
            return true
        }
    }

    var isCommitted: Bool {
        lock.withLock {
            if case .committed = state { return true }
            return false
        }
    }
}

/// Rejects statistics whose native request began before the latest encoder-resume boundary.
/// Ordinary WebRTC events are buffered, so callback time and event-delivery order cannot prove
/// which encoder epoch produced a report.
struct WorldwideScreenVideoAdaptationFreshnessFence: Equatable, Sendable {
    private(set) var minimumCollectionSequence: UInt64?

    mutating func beginPostResumeEpoch(
        minimumCollectionSequence: UInt64
    ) {
        self.minimumCollectionSequence = self.minimumCollectionSequence.map {
            max($0, minimumCollectionSequence)
        } ?? minimumCollectionSequence
    }

    mutating func reset() {
        minimumCollectionSequence = nil
    }

    func admits(_ snapshot: WebRTCStatisticsSnapshot) -> Bool {
        guard let minimumCollectionSequence else { return true }
        guard let collectionSequence = snapshot.collectionSequence else {
            return false
        }
        return collectionSequence >= minimumCollectionSequence
    }
}

/// Owns one consume-once rendezvous and its Mac-side WebRTC screen session.
///
/// The invitation authenticates and encrypts signaling. Reachability still comes from
/// ICE/STUN and, when a direct candidate pair is impossible, the configured TURN service.
actor WorldwideScreenService {
    private enum ScreenVideoAdaptationEvidenceLane: Equatable {
        case fastSender
        case ordinaryFallback
    }

    private static let maximumDisplayModeStartupRetries = 3
    private static let maximumForwardingStartupProofPolls = 40
    private static let forwardingStartupProofPollInterval = Duration.milliseconds(25)
    static let screenVideoAdaptationStatisticsInterval = Duration.milliseconds(
        WorldwideScreenVideoAdaptationPolicy.sampleIntervalMilliseconds
    )
    static let screenVideoAdaptationStatisticsTimeout = Duration.milliseconds(400)
    static let screenVideoAdaptationFallbackStatisticsInterval =
        Duration.seconds(1)
    static let screenVideoAdaptationMaximumEvidenceGap = Duration.seconds(2)
    private static let automaticScreenMediaResumeTimeout = Duration.seconds(12)
    private static let screenClientDiagnosticsStaleInterval: TimeInterval = 5
    private static let maximumSharedClockEpochQuiescencePolls = 20
    private static let sharedClockEpochQuiescencePollInterval =
        Duration.milliseconds(50)
    private static let requiredSharedClockIdleObservations = 2

    private struct ScreenCaptureStartupOwner: Equatable {
        let visibilityCommandEpoch: UInt64
        let peerGeneration: UInt64
        let recoveryEpoch: UInt64
    }

    /// Finishes once the consume-once media rendezvous has been fully torn down.
    nonisolated let completion: AsyncStream<Void>

    /// Formats peer state with the host PID so duplicate-process diagnostics remain actionable.
    nonisolated static func peerStateLogMessage(
        state: String,
        processIdentifier: Int32
    ) -> String {
        "Worldwide WebRTC peer state: \(state) pid=\(processIdentifier)"
    }

    /// Renders only bounded, content-free client pipeline counters and local protocol state.
    nonisolated static func screenClientDiagnosticsLogMessage(
        _ heartbeat: WebRTCScreenClientDiagnosticsHeartbeat,
        hostPhase: WorldwideScreenMediaSuspensionCoordinator.DiagnosticPhase,
        isCorrelated: Bool
    ) -> String {
        let dimensions = if let width = heartbeat.frameWidth,
                            let height = heartbeat.frameHeight {
            "\(width)x\(height)"
        } else {
            "unknown"
        }
        let rendererPath = if let path = heartbeat.rendererPath {
            " rendererEpoch=\(path.rendererEpoch)"
                + " nativeCover=\(path.nativeCoverVisible)"
                + " metalDelegate=\(path.metalDelegateInstalled)"
                + " renderEntries=\(path.renderFrameEntries)"
                + " mtkDrawEntries=\(path.mtkDrawEntries)"
                + " nilDrawable=\(path.nilDrawable)"
                + " producerBusy=\(path.producerBusy)"
                + " registrarUnsupported=\(path.registrarUnsupported)"
                + " registrarAlreadyPresented=\(path.registrarAlreadyPresented)"
                + " registrarRegistered=\(path.registrarRegistered)"
                + " presentedTimeReadable="
                + (path.presentedTimeReadable.map(String.init) ?? "unavailable")
                + " callbackEarly=\(path.callbackEarly)"
                + " callbackValid=\(path.callbackValid)"
                + " callbackFenceRejected=\(path.callbackFenceRejected)"
        } else {
            " rendererPath=unavailable"
        }
        return "Worldwide screen client diagnostics "
            + "seq=\(heartbeat.sequence) "
            + "screenRequestID="
            + (heartbeat.screenRequestID.map(String.init) ?? "none")
            + " hostPhase=\(hostPhase.rawValue) "
            + "correlation=\(isCorrelated ? "matched" : "mismatch") "
            + "liveness=\(heartbeat.liveness.rawValue) "
            + "trackAttached=\(heartbeat.trackAttached) "
            + "coverVisible=\(heartbeat.coverVisible) "
            + "coverReason=\(heartbeat.coverReason.rawValue) "
            + "inboundBytes="
            + (heartbeat.inboundBytes.map(String.init) ?? "none")
            + " inboundPackets="
            + (heartbeat.inboundPackets.map(String.init) ?? "none")
            + " decoded="
            + (heartbeat.framesDecoded.map(String.init) ?? "none")
            + " presented="
            + (heartbeat.framesPresented.map(String.init) ?? "none")
            + " contentSamples="
            + (heartbeat.contentSamples.map(String.init) ?? "none")
            + " contentChanges="
            + (heartbeat.contentChanges.map(String.init) ?? "none")
            + " presentationAgeMs="
            + (heartbeat.presentationAgeMilliseconds.map(String.init) ?? "none")
            + " dimensions=\(dimensions) fps="
            + (heartbeat.framesPerSecond.map {
                String(format: "%.1f", $0)
            } ?? "none")
            + rendererPath
    }

    /// Adds only structural state when a pointer action fails the screen-format fence.
    /// Coordinates, display names, session identifiers, and content remain excluded.
    nonisolated static func remoteInputFormatDiagnostic(
        viewerVideoSize: WebRTCInputVideoSize?,
        outcome: WorldwideRemoteInputInjectionOutcome
    ) -> String? {
        guard case .rejected(.screenFormatChanging) = outcome.result else {
            return nil
        }
        let viewerSize = viewerVideoSize.map {
            "\($0.width)x\($0.height)"
        } ?? "missing"
        switch outcome.formatOrigin {
        case .captureGateUnavailable(let diagnostic):
            let frameSurface = if let width = diagnostic?.frameSurfaceWidth,
                                  let height = diagnostic?.frameSurfaceHeight {
                "\(width)x\(height)"
            } else {
                "missing"
            }
            let capturePhase = diagnostic?.phase ?? "missing"
            let formatProven = diagnostic?.formatIsProven.description ?? "missing"
            let configurationInProgress =
                diagnostic?.displayConfigurationInProgress.description ?? "missing"
            let metadataState = diagnostic?.frameMetadataState.rawValue ?? "missing"
            let retainedGeometry =
                diagnostic?.retainedProvenGeometry.description ?? "missing"
            return "formatOrigin=captureGateUnavailable " +
                "viewerVideoSize=\(viewerSize) " +
                "capturePhase=\(capturePhase) " +
                "formatProven=\(formatProven) " +
                "displayConfigurationInProgress=\(configurationInProgress) " +
                "frameMetadata=\(metadataState) " +
                "frameSurface=\(frameSurface) " +
                "retainedProvenGeometry=\(retainedGeometry)"

        case .controller(let diagnostic):
            let frameSurface = if let width = diagnostic.frameSurfaceWidth,
                                  let height = diagnostic.frameSurfaceHeight {
                "\(width)x\(height)"
            } else {
                "missing"
            }
            let candidateAge = diagnostic.candidateAgeMilliseconds.map(String.init)
                ?? "missing"
            let aspectDeltaPPM = diagnostic.viewerAspectRelativeDifference.map {
                String(Int((min(max($0, 0), 1) * 1_000_000).rounded()))
            } ?? "missing"
            return "formatOrigin=controller.\(diagnostic.reason.rawValue) " +
                "viewerVideoSize=\(viewerSize) " +
                "frameSurface=\(frameSurface) " +
                "stableGeometry=\(diagnostic.stableGeometryAvailable) " +
                "candidateGeometry=\(diagnostic.candidateGeometryAvailable) " +
                "candidateAgeMs=\(candidateAge) " +
                "viewerAspectDeltaPPM=\(aspectDeltaPPM)"

        case .controllerUnknown, .none:
            return "formatOrigin=controller.unknown viewerVideoSize=\(viewerSize)"
        }
    }

    /// Binds the physical default-input boundary to the exact host process and peer.
    nonisolated static func defaultInputSelectionLogMessage(
        routingEpoch: String,
        peerGeneration: UInt64,
        deviceGeneration: UInt64,
        processIdentifier: Int32
    ) -> String {
        "Worldwide authenticated media route selected virtual microphone default input " +
            "routingEpoch=\(routingEpoch) " +
            "peerGeneration=\(peerGeneration) " +
            "deviceGeneration=\(deviceGeneration) " +
            "pid=\(processIdentifier)"
    }

    /// One nonsecret, privacy-safe identifier for this service's audio-routing evidence.
    nonisolated static func makeBlackHoleRoutingEpoch() -> String {
        UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    nonisolated static func iPhoneMicrophoneRuntimeFailureCategory(
        for error: BlackHoleMicrophoneOutputError
    ) -> WorldwideIPhoneMicrophoneForwardingFailureCategory {
        switch error {
        case .operation:
            return .runtimeEnqueueFailed
        case .progressStalled:
            return .runtimeProgressStalled
        case .formatUnsafe:
            return .formatUnsafe
        case .sharedClockUnsafe:
            return .sharedClockUnsafe
        }
    }

    nonisolated static func iPhoneMicrophoneRuntimeFailureLogMessage(
        error: BlackHoleMicrophoneOutputError
    ) -> String {
        switch error {
        case .formatUnsafe:
            return "iPhone microphone forwarding rejected the current " +
                "peer and virtual microphone pair because its output format/readback " +
                "is unsafe; automatic restart is blocked until the peer or " +
                "pair generation changes: " +
                error.localizedDescription
        case .sharedClockUnsafe(let rejection):
            if WorldwideSharedClockEpochRecoveryPolicy
                .canRecover(rejection) {
                return "iPhone microphone forwarding found an expired " +
                    "virtual microphone clock epoch; bounded idle proof and " +
                    "exact route cleanup are required before one fresh-epoch " +
                    "recovery attempt: " +
                    error.localizedDescription
            }
            return "iPhone microphone forwarding rejected the current " +
                "peer and virtual microphone pair because its shared clock is " +
                "unsafe for FaceTime; automatic restart is blocked until " +
                "the peer or pair generation changes: " +
                error.localizedDescription
        case .operation, .progressStalled:
            return "iPhone microphone forwarding encountered an output " +
                "runtime failure and ran its bounded restart policy: " +
                error.localizedDescription
        }
    }

    nonisolated static func hiddenWriterSelectionLogMessage(
        routingEpoch: String,
        peerGeneration: UInt64,
        deviceGeneration: UInt64,
        selectionProven: Bool,
        processIdentifier: Int32
    ) -> String? {
        guard selectionProven,
              peerGeneration > 0,
              deviceGeneration > 0 else {
            return nil
        }
        return "Worldwide iPhone microphone hidden writer selected " +
            "routingEpoch=\(routingEpoch) " +
            "peerGeneration=\(peerGeneration) " +
            "deviceGeneration=\(deviceGeneration) " +
            "pid=\(processIdentifier)"
    }

    /// Privacy-safe progress telemetry: no device UID, track ID, nonce, or attempt UUID.
    nonisolated static func iPhoneMicrophoneForwardingLogMessage(
        _ snapshot: WorldwideIPhoneMicrophoneForwardingHostSnapshot
    ) -> String {
        let progress = snapshot.progress
        let content = progress.pcmContent
        let decoded = progress.decodedContent
        let contentScalars = String(
            format:
                "pcmRMS=%.6f pcmRMSdBFS=%.2f " +
                "pcmPeak=%.6f pcmPeakdBFS=%.2f " +
                "pcmDC=%.6f pcmZeroFraction=%.6f " +
                "pcmClippingFraction=%.6f",
            content.metrics.rms,
            content.metrics.rmsDBFS,
            content.metrics.peak,
            content.metrics.peakDBFS,
            content.metrics.dc,
            content.metrics.zeroFraction,
            content.metrics.clippingFraction
        )
        let decodedScalars = String(
            format:
                "decRMS=%.6f decRMSdBFS=%.2f " +
                "decPeak=%.6f decPeakdBFS=%.2f " +
                "decDC=%.6f decZeroFraction=%.6f " +
                "decClippingFraction=%.6f",
            decoded.metrics.rms,
            decoded.metrics.rmsDBFS,
            decoded.metrics.peak,
            decoded.metrics.peakDBFS,
            decoded.metrics.dc,
            decoded.metrics.zeroFraction,
            decoded.metrics.clippingFraction
        )
        let forwardingIdentity = snapshot.lastAttemptedKey
        let forwardingIdentityMatchesSnapshot = forwardingIdentity.map {
            $0.monitorEpoch == snapshot.monitorEpoch
                && $0.deviceGeneration == snapshot.deviceGeneration
                && $0.peerGeneration == snapshot.peerGeneration
                && $0.transportAuthorizationEpoch
                    == snapshot.transportAuthorizationEpoch
                && $0.trackGeneration == snapshot.trackGeneration
        } ?? false
        return "Worldwide iPhone microphone forwarding " +
            "phase=\(snapshot.phase.rawValue) " +
            "monitorEpoch=\(snapshot.monitorEpoch?.uuidString.lowercased() ?? "none") " +
            "deviceGeneration=\(snapshot.deviceGeneration) " +
            "peerGeneration=\(snapshot.peerGeneration) " +
            "transportAuthorizationEpoch=" +
                "\(snapshot.transportAuthorizationEpoch) " +
            "trackGeneration=\(snapshot.trackGeneration) " +
            "attemptGeneration=\(snapshot.attemptGeneration) " +
            "lastAttemptedKeyMatchesSnapshot=" +
                "\(forwardingIdentityMatchesSnapshot) " +
            "inputEndpointAvailable=\(snapshot.deviceUID != nil) " +
            "hiddenSinkAvailable=\(snapshot.sinkDeviceUID != nil) " +
            "hiddenWriterSelectionProven=" +
                "\(snapshot.hiddenWriterSelectionProven) " +
            "transport=\(snapshot.transportAuthorized) " +
            "trackAdmitted=\(snapshot.exactTrackAdmitted) " +
            "queueRunning=\(snapshot.queueRunning) " +
            "callbacks=\(progress.postStartCallbackCount) " +
            "pulls=\(progress.successfulPullCount) " +
            "frames=\(progress.successfulFrameCount) " +
            "silenceFallbacks=\(progress.silenceFallbackCount) " +
            "enqueueFailures=\(progress.enqueueFailureCount) " +
            "pcmLifecycleGeneration=\(content.lifecycleGeneration) " +
            "pcmWindowSequence=\(content.windowSequence) " +
            "pcmCompletedFrames=\(content.completedFrameCount) " +
            "pcmSourceStartFrame=\(content.sourceStartFrame) " +
            "pcmSourceEndFrame=\(content.sourceEndFrame) " +
            "pcmWindowFrames=\(content.windowFrameCount) " +
            "pcmWindowBytes=\(content.windowByteCount) " +
            "boundDecGeneration=" +
                "\(progress.boundDecodedPlayoutGeneration) " +
            "boundDecRenderFloor=" +
                "\(progress.boundDecodedRenderCallFloor) " +
            contentScalars + " " +
            "decGeneration=\(decoded.playoutGeneration) " +
            "decCalls=\(decoded.renderCallCount) " +
            "decRequestedFrames=\(decoded.requestedFrameCount) " +
            "decRequestedBytes=\(decoded.requestedByteCount) " +
            "decReturnedBytes=\(decoded.returnedByteCount) " +
            "decNativeSuccess=" +
                "\(decoded.nativeSuccessRenderCallCount) " +
            "decNativeFailure=" +
                "\(decoded.nativeFailureRenderCallCount) " +
            "decExactContracts=\(decoded.exactBufferContractCount) " +
            "decAnalyzedCalls=\(decoded.analyzedRenderCallCount) " +
            "decAnalyzedFrames=\(decoded.analyzedFrameCount) " +
            "decAnalyzedBytes=\(decoded.analyzedByteCount) " +
            "decDropped=\(decoded.droppedTelemetryRenderCallCount) " +
            "decContractMismatch=\(decoded.bufferContractMismatchCount) " +
            "decPendingFrames=\(decoded.pendingWindowFrameCount) " +
            "decLatestCall=\(decoded.latestRenderCall) " +
            "decLatestStatus=\(decoded.latestRenderStatus) " +
            "decLatestRequestedFrames=" +
                "\(decoded.latestRequestedFrameCount) " +
            "decLatestRequestedBytes=" +
                "\(decoded.latestRequestedByteCount) " +
            "decLatestReturnedBytes=" +
                "\(decoded.latestReturnedByteCount) " +
            "decLatestExact=\(decoded.latestBufferContractWasExact) " +
            "decHasWindow=\(decoded.hasCompletedWindow) " +
            "decWindowSequence=\(decoded.windowSequence) " +
            "decWindowGeneration=\(decoded.windowGeneration) " +
            "decSourceStartFrame=\(decoded.windowSourceStartFrame) " +
            "decSourceEndFrame=\(decoded.windowSourceEndFrame) " +
            "decWindowFrames=\(decoded.windowFrameCount) " +
            "decWindowBytes=\(decoded.windowByteCount) " +
            decodedScalars + " " +
            "decAllZero=\(decoded.windowIsAllZero) " +
            "decFrozenBlocks=\(decoded.frozenBlockCount) " +
            "decLongestFrozenRun=\(decoded.longestFrozenBlockRun) " +
            "contentWindowsAlign=\(progress.contentWindowsAlign) " +
            "contentFingerprintsMatch=" +
                "\(progress.alignedContentFingerprintsMatch) " +
            "mediaSample=\(snapshot.inboundMediaSampleSequence) " +
            "mediaAdvances=\(snapshot.inboundMediaAdvancementCount) " +
            "mediaStale=\(snapshot.consecutiveStaleInboundMediaSamples) " +
            "mediaFresh=\(snapshot.inboundMediaFresh) " +
            "failure=\(snapshot.lastFailureCategory?.rawValue ?? "none")"
    }

    /// Privacy-safe receiver evidence: aggregate RTP/media counters only.
    nonisolated static func inboundAudioRTPLogMessage(
        packets: UInt64?,
        bytes: UInt64?,
        totalAudioEnergy: Double?,
        audioLevel: Double?
    ) -> String {
        "Worldwide inbound audio RTP packets="
            + (packets.map { String($0) } ?? "unknown")
            + " bytes=" + (bytes.map { String($0) } ?? "unknown")
            + " energy=" + (totalAudioEnergy.map {
                String(format: "%.6f", $0)
            } ?? "unknown")
            + " level=" + (audioLevel.map {
                String(format: "%.6f", $0)
            } ?? "unknown")
    }

    private let invitation: RemoteInvitationCode?
    private let signaling: RendezvousSignalingClient
    private let icePolicy: WebRTCICEPolicy
    private let screenDisplayID: UInt32?
    private let screenDisplayRequirement: ScreenVideoDisplayRequirement?
    private let systemAudioDisplayID: UInt32?
    private let maximumWidth: Int
    private let framesPerSecond: Int
    private let maximumVideoBitrate: Int
    private let featureProfile: WorldwideScreenServiceFeatureProfile
    // Sole writable adaptation tuple. Resource/dispatch owners stay in this actor.
    private var screenVideoAdaptationOwner: BelugaNetworkAdaptationOwnerValue
    // One synchronous publication scope per actor; never a second Owner store.
    private let screenVideoAdaptationOwnerBoundary = BelugaNetworkAdaptationOwnerBoundary()
    private static let allNetworkAdaptationOwnerWritersAreEnrolled = false
    private static let ownedStopPublicationIsEnrolled = false
    private var activeNativeAdaptationDispatch: BelugaNetworkAdaptationNativeAttempt?
    private var nativeAdaptationDispatchPhase: NativeDispatchPhase?
    private var unresolvedNativeAdaptationDispatch: NativeDispatchUnresolvedRecord?
    #if DEBUG
    // Only the fixed inert fixture below constructs/arms this one bounded use.
    private var nativeDispatchPostEffectFixtureRefusal: BelugaNetworkAdaptationPostEffectFixtureRefusal?
    private var nativeDispatchReturnFixtureUse: NativeDispatchReturnFixtureUse?
    #endif
    private enum NativeOwnerStopPublicationStage { case endShow, stopSampling, finished }
    private var nativeOwnerStopPublicationStage = NativeOwnerStopPublicationStage.endShow
    private var pendingNativeOwnerStopEntry: BelugaNetworkAdaptationActualStopEntry?
    private var pendingNativeOwnerEpochEntry: BelugaNetworkAdaptationActualEpochEntry?
    private var pendingNativeOwnerResetEntry: BelugaNetworkAdaptationActualResetEntry?
    #if DEBUG
    // Real Stop activation remains inert-test-only until every writer is enrolled.
    private var nativeOwnerStopPublicationEnabled = false
    private var nativeOwnerStopPublicationCuts: [NativeOwnerStopPublicationCut] = []
    private var nativeOwnerStopPublicationAttempts: [UInt32] = []
    private var nativeOwnerEpochPublicationEnabled = false
    private var nativeOwnerResetPublicationEnabled = false
    private var nativeOwnerResetFault = NativeOwnerResetPublicationFault.none
    private var nativeOwnerResetAttemptedOperations: [UInt32] = []
    private var nativeOwnerResetAfterPrimary: NativeOwnerPublicationSnapshotObservation?
    #endif
    private var screenVideoAdaptationPolicy: WorldwideScreenVideoAdaptationPolicy {
        screenVideoAdaptationOwner.policy
    }
    private let remoteInputController: MacRemoteInputController
    private let remoteInputOwnerToken = MacRemoteInputOwnerToken()
    private let remoteMediaController: any MacRemoteMediaControlling
    private weak var captureLifetime: CaptureServiceLifetime?
    private let captureLifetimeIsRequired: Bool
    private let iPhoneMicrophoneForwardingPolicy:
        WorldwideIPhoneMicrophoneForwardingPolicy
    private let blackHoleDeviceAvailabilityMonitor: BlackHoleDeviceAvailabilityMonitor
    private let blackHoleDefaultInputLease: BlackHoleDefaultInputLease
    private let worldwideSafeOutputInvariant: WorldwideSafeOutputInvariant
    private let blackHoleMicrophoneOutputAuthorizationGate: BlackHoleMicrophoneOutputAuthorizationGate?
    private let blackHoleAudioRoutingCleanupRetainer: any WorldwideBlackHoleAudioRoutingCleanupRetaining
    private let deferredBlackHoleDefaultInputCleanup: @Sendable (Int) -> Bool
    private let hostedCallPolicyProducer: BelugaRustMacHostedCallProducer
    #if DEBUG
    private let audioRoutingIsInertPolicyFixture: Bool
    private let batchAInertRoutingObserverJoin: InertBatchARoutingObserverJoin?
    private var batchANativeAdmissionCallCount = 0
    #endif
    private let blackHoleRoutingEpoch =
        WorldwideScreenService.makeBlackHoleRoutingEpoch()
    private let blackHoleAudioRoutingCleanupID =
        UUID()
    private let maximumBlackHoleAudioRoutingCleanupEpisodeCount =
        1
    private let logger: Logger
    private let completionContinuation: AsyncStream<Void>.Continuation
    private let makeServiceTeardownWatchdog: @Sendable () -> Task<Void, Never>?
    private let makeNativeCaptureWatchdog: @Sendable () -> Task<Void, Never>?

    private var signalingTask: Task<Void, Never>?
    private var peerEventTask: Task<Void, Never>?
    private var screenClientDiagnosticsEventTask: Task<Void, Never>?
    private var audioClientDiagnosticsEventTask: Task<Void, Never>?
    private var audioClientDiagnosticsFreshnessTask: Task<Void, Never>?
    private var audioClientDiagnostics = WorldwideAudioClientDiagnosticsSink(
        hostPID: ProcessInfo.processInfo.processIdentifier
    )
    private let audioClientDiagnosticsReportWriter:
        WorldwideAudioClientDiagnosticsReportWriter?
    private var screenVideoAdaptationTask: Task<Void, Never>?
    private var screenVideoAdaptationFastStatisticsAreAvailable: Bool {
        screenVideoAdaptationOwner.fastStatisticsAvailable
    }
    private var screenVideoAdaptationPolicyRevision: UInt64 {
        screenVideoAdaptationOwner.revision
    }
    private var screenVideoAdaptationEvidenceLane: ScreenVideoAdaptationEvidenceLane? {
        switch screenVideoAdaptationOwner.lane {
        case .fastSender: return .fastSender
        case .ordinaryFallback: return .ordinaryFallback
        case nil: return nil
        }
    }
    private var screenVideoAdaptationLastEvidenceTime: ContinuousClock.Instant? {
        screenVideoAdaptationOwner.evidenceTime
    }
    private var screenVideoAdaptationFreshnessFence: WorldwideScreenVideoAdaptationFreshnessFence {
        // Read-only one-field projection, never another stored freshness owner.
        var fence = WorldwideScreenVideoAdaptationFreshnessFence()
        if let minimum = screenVideoAdaptationOwner.minimumCollectionSequence {
            fence.beginPostResumeEpoch(minimumCollectionSequence: minimum)
        }
        return fence
    }
    private var screenStartupDiagnostics = WorldwideScreenStartupDiagnostics()
    private var keyFrameControlTask: Task<Void, Never>?
    private var remoteMediaCommandTask: Task<Void, Never>?
    private struct PendingMediaHandoff {
        let id: UUID
        let peer: WebRTCPeer
        let peerGeneration: UInt64
        let authorization: WebRTCControlAuthorization
        var prepared: MacPreparedMediaHandoff?
        var executionStarted = false
    }
    private var pendingMediaHandoff: PendingMediaHandoff?
    private var mediaHandoffExpiryTask: Task<Void, Never>?
    private var mediaHandoffExecutionTask: Task<Void, Never>?
    private let remoteMediaTraceSession = UUID()
    private var remoteMediaStateTraceGate = RemoteMediaStateTrace.Gate()
    private var remoteMediaCommandCapacity =
        WorldwideRemoteMediaCommandQueueCapacity()
    private var peer: WebRTCPeer?
    private var recoveryCoordinator: ICERecoveryCoordinator?
    private var peerGeneration: UInt64 = 0
    private var highestRestartRequestID: UInt64?
    private var peerIsConnected = false
    private var iceIsConnected = false
    private var controlChannelIsOpen = false
    private var latestRemoteMediaControllerRevision: UInt64 = 0
    private var latestRemoteMediaItem: WebRTCRemoteMediaItem?
    private var latestRemoteMediaAdditionalItems: [WebRTCRemoteMediaItem] = []
    private var remoteMediaPublication =
        WorldwideRemoteMediaPublicationMachine()
    private var remoteMediaPublicationRetryGate =
        WorldwideRemoteMediaPublicationRetryGate()
    private var remoteMediaPublicationRetryTask: Task<Void, Never>?
    private var pendingRemoteMediaStateRefresh:
        WebRTCReceivedRemoteMediaStateRefreshRequest?
    private var isRecovering = false
    private var recoveryProofRequired = false
    private var recoveryProofEpoch: UInt64 = 0
    private var restartAnswerAwaitingEpoch: UInt64?
    private var restartAnswerAppliedEpoch: UInt64?
    private var pendingRecoveryProofRequest: PendingRecoveryProofRequest?
    private var recoveryProofAcknowledgementInFlight: PendingRecoveryProofRequest?
    private var recoveryProofAuthorization: WebRTCControlAuthorization?
    private var screenVisibilityCommandEpoch: UInt64 = 0
    private var screenMediaSuspension =
        WorldwideScreenMediaSuspensionCoordinator()
    private var lastScreenClientDiagnosticsReceiptUptime: TimeInterval?
    private var lastScreenClientDiagnosticsSequence: UInt64?
    private var lastScreenClientDiagnosticsScreenRequestID: UInt64?
    private var screenClientDiagnosticsExpectedScreenRequestID: UInt64?
    private var screenClientDiagnosticsExpectationStartedUptime: TimeInterval?
    private var screenClientDiagnosticsSilenceWasReported = false
    private enum ResumeOwnerCompletionClaim: Equatable, Sendable {
        case unclaimed, admitted, refused, published, terminalClaimed
    }
    private struct AutomaticScreenMediaResumeContext: Sendable {
        let binding: WorldwideScreenMediaSuspensionCoordinator.Binding
        let notice: WebRTCScreenMediaSuspensionNotice
        let attemptID: UUID
        let finalAcknowledgementCommit:
            WorldwideScreenAutomaticResumeCommitLatch
        let inputOwnershipClaim: MacRemoteInputOwnershipClaim?
        var probeAuthorization: WebRTCControlAuthorization?
        var forwardingAuthorization: WebRTCControlAuthorization?
        var boundary: WorldwideScreenSampleSink.ResumeMarkerBoundary?
        var markerReady: WebRTCScreenMediaMarkerReady?
        var markerPresentation: WebRTCScreenMediaMarkerPresentation?
        var ownerCompletionClaim: ResumeOwnerCompletionClaim = .unclaimed
        var ownerCompletionEntryID: ObjectIdentifier? = nil
        var ownerResetEntryID: ObjectIdentifier? = nil
    }
    private var automaticScreenMediaResumeContext:
        AutomaticScreenMediaResumeContext?
    private var latestShowInputOwnershipClaim:
        MacRemoteInputOwnershipClaim?
    private var automaticScreenMediaResumeTimeoutTask: Task<Void, Never>?
    /// Invalidates a timeout that has already awakened but has not yet re-entered this actor.
    /// Task cancellation alone cannot fence that queued call across actor reentrancy.
    private var automaticScreenMediaResumeTimeoutGeneration: UInt64 = 0
    private var captureSource: ScreenVideoCaptureSource?
    private var captureSink: WorldwideScreenSampleSink?
    private var screenFormatRenegotiation =
        ScreenFormatRenegotiationCoordinator<WorldwideScreenSampleSink>()
    private var captureAuthorization: WebRTCControlAuthorization?
    private var captureForwardingAuthorization: WebRTCControlAuthorization?
    private var captureDisplayID: UInt32?
    private var captureAuthoritativeDisplayBounds: CGRect?
    private var captureVideoBaseDimensions: ScreenVideoPixelDimensions?
    private var appliedScreenVideoRecommendation: WorldwideScreenVideoEncodingRecommendation? {
        screenVideoAdaptationOwner.applied
    }
    private var audioSource: SystemAudioCaptureSource?
    private var audioSink: WorldwideSystemAudioSampleSink?
    private var audioAuthorization: WebRTCAudioAuthorization?
    private var audioPeerGeneration: UInt64?
    private var systemAudioStartInProgress = false
    private var systemAudioIsLive = false
    private var systemAudioIsPausedForTransportRecovery = false
    private var macHostedCallChallenge:
        WebRTCMacHostedCallChallenge?
    private var macHostedCallChallengePeerGeneration: UInt64?
    private var highestMacFaceTimeObservationSequence: UInt64 = 0
    private var blackHoleDeviceMonitorEpoch: UUID?
    private var safeOutputInvariantMonitoringEpoch:
        WorldwideSafeOutputInvariantMonitoringEpoch?
    private var safeOutputInvariantAuthorization:
        WorldwideSafeOutputInvariantAuthorization?
    /// Exact endpoint-pair inventory proof incorporated by the admission that
    /// last opened the realtime writer gate. A delayed actor reconciliation
    /// may be discarded only when this proof already includes its raw event.
    private struct BlackHoleEndpointPairAuthorization: Equatable {
        let monitorEpoch: UUID
        let deviceGeneration: UInt64
        let acceptedInventoryChangeSequence: UInt64
    }
    private var blackHoleEndpointPairAuthorization:
        BlackHoleEndpointPairAuthorization?
    private var blackHoleDefaultInputAuthorization:
        BlackHoleDefaultInputLeaseAuthorization?
    struct SharedClockBlockedPeerPair: Equatable, Sendable {
        let monitorEpoch: UUID
        let deviceGeneration: UInt64
        let peerGeneration: UInt64

        init(
            forwardingKey:
                WorldwideIPhoneMicrophoneForwardingKey
        ) {
            monitorEpoch = forwardingKey.monitorEpoch
            deviceGeneration = forwardingKey.deviceGeneration
            peerGeneration = forwardingKey.peerGeneration
        }

        func matches(
            peerGeneration: UInt64,
            snapshot: BlackHoleDeviceAvailabilitySnapshot
        ) -> Bool {
            self.peerGeneration == peerGeneration
                && monitorEpoch == snapshot.monitorEpoch
                && deviceGeneration == snapshot.deviceGeneration
        }
    }
    struct FormatUnsafeBlockedPeerPair: Equatable {
        let monitorEpoch: UUID
        let deviceGeneration: UInt64
        let peerGeneration: UInt64

        init(
            forwardingKey:
                WorldwideIPhoneMicrophoneForwardingKey
        ) {
            monitorEpoch = forwardingKey.monitorEpoch
            deviceGeneration = forwardingKey.deviceGeneration
            peerGeneration = forwardingKey.peerGeneration
        }

        func matches(
            peerGeneration: UInt64,
            snapshot: BlackHoleDeviceAvailabilitySnapshot
        ) -> Bool {
            self.peerGeneration == peerGeneration
                && monitorEpoch == snapshot.monitorEpoch
                && deviceGeneration == snapshot.deviceGeneration
        }
    }
    private var sharedClockBlockedPeerPair:
        SharedClockBlockedPeerPair?
    private let virtualMicrophoneEpochStateReader =
        WorldwideVirtualMicrophoneEpochStateReader()
    private var sharedClockEpochRecoveryPolicy =
        WorldwideSharedClockEpochRecoveryPolicy()
    private var sharedClockEpochRecoveryTask:
        Task<Void, Never>?
    private var sharedClockEpochRecoveryTaskGeneration: UInt64 = 0
    private var sharedClockEpochRecoveryKey:
        WorldwideIPhoneMicrophoneForwardingKey?
    private var sharedClockEpochRecoveryReadmissionTaskGeneration:
        UInt64?
    private var sharedClockEpochCleanupPendingPair:
        SharedClockBlockedPeerPair?
    private var formatUnsafeBlockedPeerPair:
        FormatUnsafeBlockedPeerPair?
    private lazy var blackHoleDefaultInput =
        WorldwideBlackHoleDefaultInputCoordinator(
            policy: iPhoneMicrophoneForwardingPolicy,
            lease: blackHoleDefaultInputLease
        )
    private lazy var iPhoneMicrophoneForwarding =
        WorldwideIPhoneMicrophoneForwardingDriver<
            WebRTCPeer,
            WebRTCRemoteAudioTrack
        >(
            policy: iPhoneMicrophoneForwardingPolicy,
            makeOutput: { [weak self] peer, hiddenEndpoint in
                guard let self,
                      let source = peer.macDecodedAudioSource,
                      let authorizationGate =
                        self.blackHoleMicrophoneOutputAuthorizationGate
                else {
                    return nil
                }
                return BlackHoleMicrophoneOutput(
                    source: source,
                    expectedHiddenEndpoint: hiddenEndpoint,
                    authorizationGate: authorizationGate,
                    runtimeFailureHandler: { [weak self] output, error in
                        Task { [weak self] in
                            await self?.iPhoneMicrophoneOutputDidFail(
                                output: output,
                                error: error
                            )
                        }
                    }
                )
            },
            startOutput: { output in
                try output.start()
            },
            admit: { peer, track in
                try await peer.enableRemoteIPhoneMicrophonePlaybackIfTransportHealthy(
                    track
                )
            },
            disableTrack: { track in
                track.setEnabled(false)
            },
            sharedClockFailureHandler: {
                [weak self] key, rejection in
                await self?.iPhoneMicrophoneSharedClockDidFail(
                    key: key,
                    rejection: rejection
                )
            },
            formatFailureHandler: {
                [weak self] key, rejection in
                await self?.iPhoneMicrophoneFormatDidFail(
                    key: key,
                    rejection: rejection
                )
            }
        )
    private var activeInputCapability: WebRTCInputCapability?
    private var activeInputAuthorization: WebRTCInputAuthorization?
    private var isStarted = false
    private var isStopped = false
    private var stopIsInProgress = false
    private var stopCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var safeOutputInvariantNeedsRedrive = false
    private var safeOutputInvariantVerificationWasFailing = false
    private var safeOutputInvariantRetryPolicy: WorldwideSafeOutputInvariantRetryPolicy
    private var safeOutputRetryBridgeFaultWasReported = false

    /// Fail-closed aggregate gate required before exposing either media source.
    private var transportAllowsCapture: Bool {
        peerIsConnected
            && iceIsConnected
            && controlChannelIsOpen
            && !isRecovering
            && !isStopped
            && (!captureLifetimeIsRequired || captureLifetime?.isValid == true)
    }

    /// Creates a legacy consume-once session with a newly generated invitation capability.
    init(
        endpoint: URL,
        forceRelay: Bool,
        screenDisplayID: UInt32?,
        screenDisplayRequirement: ScreenVideoDisplayRequirement? = nil,
        systemAudioDisplayID: UInt32?,
        maximumWidth: Int,
        framesPerSecond: Int,
        maximumVideoBitrate: Int,
        featureProfile: WorldwideScreenServiceFeatureProfile = .fullPrimary,
        remoteInputController: MacRemoteInputController,
        remoteMediaController: any MacRemoteMediaControlling =
            MacSystemNowPlayingController(),
        captureLifetime: CaptureServiceLifetime? = nil,
        iPhoneMicrophoneForwardingPolicy:
            WorldwideIPhoneMicrophoneForwardingPolicy = .enabled,
        makeServiceTeardownWatchdog: @escaping @Sendable () -> Task<Void, Never>? = { nil },
        makeNativeCaptureWatchdog: @escaping @Sendable () -> Task<Void, Never>? = { nil },
        audioRoutingDependencies: WorldwideScreenServiceAudioRoutingDependencies? = nil,
        safeOutputRetryPolicy: WorldwideSafeOutputInvariantRetryPolicy = .init(),
        hostedCallPolicyProducer: BelugaRustMacHostedCallProducer = .actual,
        logger: Logger
    ) throws {
        let completionPair = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        completion = completionPair.stream
        completionContinuation = completionPair.continuation
        let invitation = try RemoteInvitationCode.generate()
        self.invitation = invitation
        signaling = try RendezvousSignalingClient(
            endpoint: endpoint,
            invitation: invitation,
            role: .host
        )
        icePolicy = forceRelay ? .relayOnly : .directPreferred
        self.screenDisplayID = screenDisplayID
        self.screenDisplayRequirement = screenDisplayRequirement
        self.systemAudioDisplayID = systemAudioDisplayID
        self.maximumWidth = maximumWidth
        self.framesPerSecond = framesPerSecond
        let effectiveMaximumVideoBitrate = featureProfile
            .maximumVideoBitrate(configured: maximumVideoBitrate)
        self.maximumVideoBitrate = effectiveMaximumVideoBitrate
        self.featureProfile = featureProfile
        let audioRouting = audioRoutingDependencies ?? .live()
        blackHoleDeviceAvailabilityMonitor = audioRouting.monitor
        blackHoleDefaultInputLease = audioRouting.lease
        worldwideSafeOutputInvariant = audioRouting.invariant
        blackHoleMicrophoneOutputAuthorizationGate = audioRouting.writerGate
        blackHoleAudioRoutingCleanupRetainer = audioRouting.cleanupRetainer
        deferredBlackHoleDefaultInputCleanup = audioRouting.deferredInputCleanup
        safeOutputInvariantRetryPolicy = safeOutputRetryPolicy
        self.hostedCallPolicyProducer = hostedCallPolicyProducer
        #if DEBUG
        audioRoutingIsInertPolicyFixture = audioRouting.isInertPolicyFixture
        batchAInertRoutingObserverJoin = audioRouting.isInertPolicyFixture ? .init() : nil
        #endif
        audioClientDiagnosticsReportWriter = featureProfile
            .allowsAudioClientDiagnostics
                ? audioRouting.makeDiagnosticsWriter()
                : nil
        screenVideoAdaptationOwner = .init(policy: WorldwideScreenVideoAdaptationPolicy(
                configuredTotalRTPBitrateBps: effectiveMaximumVideoBitrate,
                baseFramesPerSecond: framesPerSecond
            ),
            revision: 0, fastStatisticsAvailable: false,
            lane: nil, evidenceTime: nil,
            minimumCollectionSequence: nil, applied: nil)
        self.remoteInputController = remoteInputController
        self.remoteMediaController = remoteMediaController
        self.captureLifetime = captureLifetime
        captureLifetimeIsRequired = captureLifetime != nil
        self.iPhoneMicrophoneForwardingPolicy = featureProfile
            .allowsIPhoneMicrophoneAndDefaultInputRouting
                ? iPhoneMicrophoneForwardingPolicy
                : .suppressedForLANCoexistence
        self.makeServiceTeardownWatchdog = makeServiceTeardownWatchdog
        self.makeNativeCaptureWatchdog = makeNativeCaptureWatchdog
        self.logger = logger
    }

    /// Creates a paired reconnect session from a fresh authenticated rendezvous credential.
    init(
        endpoint: URL,
        sessionCredential: RemoteRendezvousCredential,
        forceRelay: Bool,
        screenDisplayID: UInt32?,
        screenDisplayRequirement: ScreenVideoDisplayRequirement? = nil,
        systemAudioDisplayID: UInt32?,
        maximumWidth: Int,
        framesPerSecond: Int,
        maximumVideoBitrate: Int,
        featureProfile: WorldwideScreenServiceFeatureProfile = .fullPrimary,
        remoteInputController: MacRemoteInputController,
        remoteMediaController: any MacRemoteMediaControlling =
            MacSystemNowPlayingController(),
        captureLifetime: CaptureServiceLifetime? = nil,
        iPhoneMicrophoneForwardingPolicy:
            WorldwideIPhoneMicrophoneForwardingPolicy = .enabled,
        makeServiceTeardownWatchdog: @escaping @Sendable () -> Task<Void, Never>? = { nil },
        makeNativeCaptureWatchdog: @escaping @Sendable () -> Task<Void, Never>? = { nil },
        audioRoutingDependencies: WorldwideScreenServiceAudioRoutingDependencies? = nil,
        safeOutputRetryPolicy: WorldwideSafeOutputInvariantRetryPolicy = .init(),
        hostedCallPolicyProducer: BelugaRustMacHostedCallProducer = .actual,
        logger: Logger
    ) throws {
        let completionPair = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        completion = completionPair.stream
        completionContinuation = completionPair.continuation
        invitation = nil
        signaling = try RendezvousSignalingClient(
            endpoint: endpoint,
            credential: sessionCredential,
            role: .host
        )
        icePolicy = forceRelay ? .relayOnly : .directPreferred
        self.screenDisplayID = screenDisplayID
        self.screenDisplayRequirement = screenDisplayRequirement
        self.systemAudioDisplayID = systemAudioDisplayID
        self.maximumWidth = maximumWidth
        self.framesPerSecond = framesPerSecond
        let effectiveMaximumVideoBitrate = featureProfile
            .maximumVideoBitrate(configured: maximumVideoBitrate)
        self.maximumVideoBitrate = effectiveMaximumVideoBitrate
        self.featureProfile = featureProfile
        let audioRouting = audioRoutingDependencies ?? .live()
        blackHoleDeviceAvailabilityMonitor = audioRouting.monitor
        blackHoleDefaultInputLease = audioRouting.lease
        worldwideSafeOutputInvariant = audioRouting.invariant
        blackHoleMicrophoneOutputAuthorizationGate = audioRouting.writerGate
        blackHoleAudioRoutingCleanupRetainer = audioRouting.cleanupRetainer
        deferredBlackHoleDefaultInputCleanup = audioRouting.deferredInputCleanup
        safeOutputInvariantRetryPolicy = safeOutputRetryPolicy
        self.hostedCallPolicyProducer = hostedCallPolicyProducer
        #if DEBUG
        audioRoutingIsInertPolicyFixture = audioRouting.isInertPolicyFixture
        batchAInertRoutingObserverJoin = audioRouting.isInertPolicyFixture ? .init() : nil
        #endif
        audioClientDiagnosticsReportWriter = featureProfile
            .allowsAudioClientDiagnostics
                ? audioRouting.makeDiagnosticsWriter()
                : nil
        screenVideoAdaptationOwner = .init(policy: WorldwideScreenVideoAdaptationPolicy(
                configuredTotalRTPBitrateBps: effectiveMaximumVideoBitrate,
                baseFramesPerSecond: framesPerSecond
            ),
            revision: 0, fastStatisticsAvailable: false,
            lane: nil, evidenceTime: nil,
            minimumCollectionSequence: nil, applied: nil)
        self.remoteInputController = remoteInputController
        self.remoteMediaController = remoteMediaController
        self.captureLifetime = captureLifetime
        captureLifetimeIsRequired = captureLifetime != nil
        self.iPhoneMicrophoneForwardingPolicy = featureProfile
            .allowsIPhoneMicrophoneAndDefaultInputRouting
                ? iPhoneMicrophoneForwardingPolicy
                : .suppressedForLANCoexistence
        self.makeServiceTeardownWatchdog = makeServiceTeardownWatchdog
        self.makeNativeCaptureWatchdog = makeNativeCaptureWatchdog
        self.logger = logger
    }

    /// Starts the outbound rendezvous connection and deliberately returns the secret once
    /// for presentation to the user. Callers must never put this value in routine logs.
    func start() async throws -> String {
        guard let invitation else {
            throw WorldwideScreenServiceError.invalidLifecycle
        }
        try await startSignaling()
        logger.info("Worldwide screen host is waiting for a one-time viewer")
        return invitation.exportedCode
    }

    /// Starts a fresh paired-device media rendezvous without exposing session credentials.
    func startPairedSession() async throws {
        guard invitation == nil else {
            throw WorldwideScreenServiceError.invalidLifecycle
        }
        try await startSignaling()
        logger.info("Worldwide screen host is waiting for the paired iPhone media session")
    }

    /// Starts signaling once and supervises its event stream in a child task.
    private func startSignaling() async throws {
        guard !isStarted, !isStopped else {
            throw WorldwideScreenServiceError.invalidLifecycle
        }
        isStarted = true

        if featureProfile.allowsNowPlaying {
            remoteMediaController.start { [weak self] update in
                Task { await self?.remoteMediaStateDidChange(update) }
            }
        }

        await startIPhoneMicrophoneDeviceMonitoringIfNeeded()
        do {
            let events = try await signaling.connect()
            signalingTask = Task { [weak self] in
                await self?.consumeSignalingEvents(events)
            }
        } catch {
            isStopped = true
            if featureProfile.allowsNowPlaying {
                remoteMediaController.stop()
            }
            if featureProfile.allowsIPhoneMicrophoneAndDefaultInputRouting {
                shutdownBlackHoleAudioRouting()
            }
            iPhoneMicrophoneForwarding.shutdown()
            completionContinuation.finish()
            throw error
        }
    }

    /// Revokes all capabilities before stopping native capture, WebRTC, and signaling.
    ///
    /// Teardown is idempotent. Authorization and forwarding gates close synchronously
    /// before any `await`, so actor reentrancy cannot leak a late media or input callback.
    func stop() async {
        guard !isStopped else {
            await waitForStopToFinish()
            // A prior close may have retained the exact source after two failed native stops.
            // Explicit owners can retry without reopening any transport or forwarding gate.
            do {
                try await stopScreenCapture()
            } catch {
                logger.error(
                    "Worldwide retained screen capture stop remained unconfirmed: " +
                        error.localizedDescription
                )
            }
            if !(await stopSystemAudio()) {
                logger.error(
                    "Worldwide retained system audio stop remained unconfirmed"
                )
            }
            return
        }
        let plan = beginStop()
        await finishStop(consume plan)
    }

    /// Only the actor's synchronous shutdown claim can create this one-use plan.
    /// Native sources and the current peer stay owned by the actor, not a snapshot.
    private struct ServiceStopPlan: ~Copyable {
        let coordinator: ICERecoveryCoordinator?
        let teardownWatchdog: Task<Void, Never>?
    }

    /// Claims teardown and closes every callback gate without yielding the actor.
    /// Every caller must immediately pass the plan to the mandatory awaited tail.
    private func beginStop() -> ServiceStopPlan {
        let teardownWatchdog = makeServiceTeardownWatchdog()
        isStopped = true
        stopIsInProgress = true
        let ownerStopOrigin = networkAdaptationActualStopPublicationOrigin()
        let usesActualOwnerStop = ownerStopOrigin != nil
        if let ownerStopOrigin { applyNativeOwnerStopPublication(.endShow, origin: ownerStopOrigin) }
        if !usesActualOwnerStop {
            var updatedPolicy = screenVideoAdaptationPolicy
            updatedPolicy.endFloorRecoveryVisibility()
            screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        safeOutputInvariantNeedsRedrive = false
        safeOutputInvariantVerificationWasFailing = false
        _ = resetSafeOutputRetryPolicy(context: "service stop")
        cancelSharedClockEpochRecovery(
            resetPolicy: true,
            clearCompatibilityBlock: true
        )

        if featureProfile.allowsIPhoneMicrophoneAndDefaultInputRouting {
            shutdownBlackHoleAudioRouting()
        }
        iPhoneMicrophoneForwarding.shutdown()
        signalingTask?.cancel()
        signalingTask = nil
        peerEventTask?.cancel()
        peerEventTask = nil
        screenClientDiagnosticsEventTask?.cancel()
        screenClientDiagnosticsEventTask = nil
        audioClientDiagnosticsEventTask?.cancel()
        audioClientDiagnosticsEventTask = nil
        audioClientDiagnosticsFreshnessTask?.cancel()
        audioClientDiagnosticsFreshnessTask = nil
        if featureProfile.allowsAudioClientDiagnostics {
            audioClientDiagnostics.markUnavailable(.stopped)
            logAudioClientDiagnosticsIfDue()
        }
        screenVideoAdaptationTask?.cancel()
        screenVideoAdaptationTask = nil
        if let ownerStopOrigin { applyNativeOwnerStopPublication(.stopSampling, origin: ownerStopOrigin) }
        if !usesActualOwnerStop {
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: false,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: nil, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: nil,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            do {
                var updatedFreshnessFence = screenVideoAdaptationFreshnessFence
                updatedFreshnessFence.reset()
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: updatedFreshnessFence.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            }
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        keyFrameControlTask?.cancel()
        keyFrameControlTask = nil
        resetRemoteMediaCommandQueue()
        if featureProfile.allowsNowPlaying {
            remoteMediaController.stop()
        }
        latestRemoteMediaControllerRevision = 0
        latestRemoteMediaItem = nil
        latestRemoteMediaAdditionalItems = []
        let coordinator = recoveryCoordinator
        recoveryCoordinator = nil
        peerGeneration &+= 1
        resetAutomaticScreenMediaSuspensionState()
        resetScreenClientDiagnosticsFreshness()
        peerIsConnected = false
        iceIsConnected = false
        controlChannelIsOpen = false
        cancelRemoteMediaPublicationRetry()
        remoteMediaPublication.stop()
        pendingRemoteMediaStateRefresh = nil
        isRecovering = false
        recoveryProofRequired = false
        recoveryProofEpoch &+= 1
        restartAnswerAwaitingEpoch = nil
        restartAnswerAppliedEpoch = nil
        pendingRecoveryProofRequest = nil
        recoveryProofAcknowledgementInFlight = nil
        recoveryProofAuthorization?.revoke()
        recoveryProofAuthorization = nil
        revokeCaptureAuthorization()
        revokeSystemAudioAuthorization()
        captureSink?.stopForwarding()
        audioSink?.stopForwarding()
        return ServiceStopPlan(coordinator: coordinator, teardownWatchdog: teardownWatchdog)
    }

    /// Consuming the plan forbids a second tail; waiters join through watchdog exit.
    private func finishStop(_ plan: consuming ServiceStopPlan) async {
        defer { finishStopping() }
        await plan.coordinator?.cancel()
        var nativeScreenStopNeedsRetry = false
        do {
            try await stopScreenCapture()
        } catch {
            nativeScreenStopNeedsRetry = true
            // Session shutdown must continue through peer/signaling close even when
            // ScreenCaptureKit cannot confirm its native stop.
            logger.error(
                "Worldwide screen capture stop failed during session close: " +
                error.localizedDescription
            )
        }
        var nativeSystemAudioStopNeedsRetry = !(await stopSystemAudio())
        if let peer {
            await peer.close(reason: .hostStopped)
        }
        self.peer = nil
        if nativeScreenStopNeedsRetry {
            do {
                try await stopScreenCapture()
            } catch {
                // Retain the source until process exit; its callback gate is permanently closed.
                logger.error(
                    "Worldwide screen capture retry remained unconfirmed during session close: " +
                        error.localizedDescription
                )
            }
        }
        if nativeSystemAudioStopNeedsRetry {
            nativeSystemAudioStopNeedsRetry = !(await stopSystemAudio())
            if nativeSystemAudioStopNeedsRetry {
                logger.error(
                    "Worldwide system audio retry remained unconfirmed during session close"
                )
            }
        }
        await signaling.close()
        completionContinuation.yield(())
        completionContinuation.finish()
        plan.teardownWatchdog?.cancel()
        await plan.teardownWatchdog?.value
    }

    /// Joins the actor invocation that owns complete peer, audio, screen, and signaling teardown.
    private func waitForStopToFinish() async {
        guard stopIsInProgress else { return }
        await withCheckedContinuation { continuation in
            stopCompletionWaiters.append(continuation)
        }
    }

    /// Publishes complete service teardown before any repeated stop caller can return.
    private func finishStopping() {
        stopIsInProgress = false
        let waiters = stopCompletionWaiters
        stopCompletionWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
    }

    /// Reports whether any native screen or system-audio teardown remains unconfirmed.
    ///
    /// The coordinator uses this terminal ownership signal to quarantine the whole host instead
    /// of advertising a new media rendezvous while the exact retained `SCStream` may still run.
    func hasUnconfirmedNativeCaptureStop() -> Bool {
        // A detached unresolved completion remains owned even when the current
        // capture slot is nil or belongs to a newer Show. Never clear this from
        // generic stop without separately proven detached lifetime disposal.
        if nativeDispatchHasUnconfirmedBaseStop() { return true }
        guard let active = activeNativeAdaptationDispatch else {
            // A malformed unmatched phase is uncertainty, not disposal proof.
            return nativeAdaptationDispatchPhase != nil
        }
        if case let .ownStopTail(completion)? = nativeAdaptationDispatchPhase,
           completion.attempt === active,
           nativeDispatchOwnsExactClaimedStopTail(completion) {
            // This exact claimant already settled its SDK completion. Native
            // source uncertainty remains in the base predicate; no later
            // sender/FPS/rollback can be authorized after this owned tail.
            return false
        }
        return true // Waiting SDK/settlement/rollback custody is still owned.
    }

    // MARK: - Rendezvous signaling

    /// Serially consumes rendezvous events and closes the session on terminal failure.
    private func consumeSignalingEvents(
        _ events: RendezvousSignalingClient.EventStream
    ) async {
        do {
            for try await event in events {
                guard !isStopped else { return }
                try await handleSignalingEvent(event)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !isStopped else { return }
            logger.error("Worldwide rendezvous session ended: \(error.localizedDescription)")
            await stop()
        }
    }

    /// Applies invitation, ICE, and peer-lifecycle events in protocol order.
    private func handleSignalingEvent(_ event: RendezvousSignalingEvent) async throws {
        switch event {
        case .waiting(let invitationExpiresAt):
            let remaining = max(0, Int(invitationExpiresAt.timeIntervalSinceNow.rounded()))
            if invitation == nil {
                logger.info("Fresh paired media rendezvous expires in about \(remaining) seconds")
            } else {
                logger.info("One-time invitation is waiting (expires in about \(remaining) seconds)")
            }

        case .ready(_, _, let iceServers):
            guard peer == nil else { return }
            try await startPeer(iceServers: iceServers)

        case .signal(.iceRestartRequest(let request)):
            guard peer != nil, let recoveryCoordinator else {
                throw WorldwideScreenServiceError.signalBeforeReady
            }
            if let highestRestartRequestID,
               request.requestID <= highestRestartRequestID {
                return
            }
            highestRestartRequestID = request.requestID
            // Arm the proof gate before the first await. Otherwise an already-queued native
            // connected/open event can cancel the coordinator's zero-delay restart.
            installRecoveryProofBoundary(awaitingAnswer: false)
            await stopCaptureForTransportUncertainty(
                "the viewer requested route recovery"
            )
            await recoveryCoordinator.restartRequested()

        case .signal(let payload):
            guard let peer else {
                throw WorldwideScreenServiceError.signalBeforeReady
            }
            let answerEpoch: UInt64?
            if case .answer = payload,
               recoveryProofRequired,
               restartAnswerAwaitingEpoch == recoveryProofEpoch {
                answerEpoch = recoveryProofEpoch
            } else {
                answerEpoch = nil
            }
            try await peer.receive(payload)
            guard !isStopped, self.peer === peer else { return }
            if let answerEpoch,
               answerEpoch == recoveryProofEpoch,
               restartAnswerAwaitingEpoch == answerEpoch,
               recoveryProofRequired {
                // This is deliberately after `peer.receive` returns: only then is the answer
                // installed and the peer's signaling generation stable.
                restartAnswerAwaitingEpoch = nil
                restartAnswerAppliedEpoch = answerEpoch
                await completePendingRecoveryProofIfPossible(
                    peer: peer,
                    epoch: answerEpoch
                )
            }

        case .peerLeft:
            logger.info("Worldwide viewer disconnected; the media rendezvous is consumed")
            await stop()

        case .serverError(let error):
            throw WorldwideScreenServiceError.rendezvous(error)
        }
    }

    // MARK: - WebRTC peer lifecycle

    /// The product opt-in stays scoped to the full primary media owner. The shared
    /// transport remains default-off and still requires an exact capability echo.
    nonisolated static func makePeerConfiguration(
        iceServers: [RemoteICEServer],
        icePolicy: WebRTCICEPolicy,
        maximumVideoBitrate: Int,
        featureProfile: WorldwideScreenServiceFeatureProfile,
        remoteMediaControllerIsAvailable: Bool
    ) -> WebRTCTransportConfiguration {
        let ownsRemoteMedia = featureProfile.allowsNowPlaying
            && remoteMediaControllerIsAvailable
        return WebRTCTransportConfiguration(
            role: .host,
            iceServers: iceServers,
            icePolicy: icePolicy,
            maximumVideoBitrate: maximumVideoBitrate,
            mediaTopology: featureProfile.transportMediaTopology,
            supportsRemoteMediaControls: ownsRemoteMedia,
            supportsMediaHandoff: ownsRemoteMedia,
            supportsAudioClientDiagnostics: featureProfile.allowsAudioClientDiagnostics
        )
    }

    /// Creates a fresh WebRTC generation and its bounded ICE recovery supervisor.
    private func startPeer(iceServers: [RemoteICEServer]) async throws {
        let peer = try WebRTCPeer(
            configuration: Self.makePeerConfiguration(
                iceServers: iceServers,
                icePolicy: icePolicy,
                maximumVideoBitrate: maximumVideoBitrate,
                featureProfile: featureProfile,
                remoteMediaControllerIsAvailable: remoteMediaController.isAvailable
            )
        )
        cancelSharedClockEpochRecovery(
            resetPolicy: true,
            clearCompatibilityBlock: true
        )
        recordBlackHoleDefaultInputOutcome(
            blackHoleDefaultInput.invalidateCurrentConnection()
        )
        safeOutputInvariantNeedsRedrive = false
        safeOutputInvariantVerificationWasFailing = false
        _ = resetSafeOutputRetryPolicy(context: "new peer")
        peerGeneration &+= 1
        let generation = peerGeneration
        resetAutomaticScreenMediaSuspensionState()
        resetScreenClientDiagnosticsFreshness()
        do {
            var updatedPolicy = screenVideoAdaptationPolicy
            updatedPolicy.bind(toPeerGeneration: generation)
            screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: false,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: nil, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: nil,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        do {
            var updatedFreshnessFence = screenVideoAdaptationFreshnessFence
            updatedFreshnessFence.reset()
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: updatedFreshnessFence.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: nil)
        highestRestartRequestID = nil
        peerIsConnected = false
        iceIsConnected = false
        controlChannelIsOpen = false
        resetRemoteMediaCommandQueue()
        cancelRemoteMediaPublicationRetry()
        remoteMediaPublication.startNewPeer()
        pendingRemoteMediaStateRefresh = nil
        isRecovering = false
        recoveryProofRequired = false
        recoveryProofEpoch &+= 1
        restartAnswerAwaitingEpoch = nil
        restartAnswerAppliedEpoch = nil
        pendingRecoveryProofRequest = nil
        recoveryProofAcknowledgementInFlight = nil
        recoveryProofAuthorization?.revoke()
        recoveryProofAuthorization = nil
        revokeCaptureAuthorization()
        revokeSystemAudioAuthorization()
        iPhoneMicrophoneForwarding.clearPeer()
        guard await stopSystemAudio() else {
            await stop()
            throw WorldwideScreenServiceError.nativeSystemAudioStopUnconfirmed
        }

        let coordinator = makeICERecoveryCoordinator(
            peerGeneration: generation,
            restart: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.beginICERestart(
                    peer: peer,
                    peerGeneration: generation
                )
            }
        )
        self.peer = peer
        if featureProfile.allowsAudioClientDiagnostics {
            audioClientDiagnostics.bind(peerGeneration: generation)
        }
        iPhoneMicrophoneForwarding.replacePeer(
            peer: peer,
            peerGeneration: generation
        )
        recoveryCoordinator = coordinator
        let events = peer.events
        let screenClientDiagnosticsEvents = peer.screenClientDiagnosticsEvents
        let audioClientDiagnosticsEvents = featureProfile.allowsAudioClientDiagnostics
            ? peer.audioClientDiagnosticsEvents
            : nil
        peerEventTask = Task { [weak self] in
            await self?.consumePeerEvents(
                events,
                sourcePeer: peer,
                sourcePeerGeneration: generation
            )
        }
        screenClientDiagnosticsEventTask = Task { [weak self] in
            await self?.consumeScreenClientDiagnosticsEvents(
                screenClientDiagnosticsEvents,
                sourcePeer: peer,
                sourcePeerGeneration: generation
            )
        }
        if let audioClientDiagnosticsEvents {
            audioClientDiagnosticsEventTask = Task { [weak self] in
                for await event in audioClientDiagnosticsEvents {
                    guard !Task.isCancelled else { return }
                    await self?.handleAudioClientDiagnosticsEvent(
                        event, sourcePeer: peer, sourcePeerGeneration: generation
                    )
                }
                guard !Task.isCancelled else { return }
                await self?.audioClientDiagnosticsStreamEnded(
                    sourcePeer: peer, sourcePeerGeneration: generation
                )
            }
            audioClientDiagnosticsFreshnessTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    let negotiated = await peer.audioClientDiagnosticsIsNegotiated()
                    guard !Task.isCancelled else { return }
                    await self?.tickAudioClientDiagnostics(
                        negotiated: negotiated, sourcePeer: peer, sourcePeerGeneration: generation
                    )
                }
            }
        }
        try await peer.startStatistics(
            interval: Self.screenVideoAdaptationFallbackStatisticsInterval
        )
        try await peer.start()
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: false,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        screenVideoAdaptationTask = Task { [weak self] in
            await self?.sampleScreenVideoAdaptationStatistics(
                sourcePeer: peer,
                sourcePeerGeneration: generation
            )
        }
        logger.info("Worldwide WebRTC negotiation started")
    }

    /// Consumes native peer events until normal stop or an unexpected stream end.
    private func consumePeerEvents(
        _ events: AsyncStream<WebRTCTransportEvent>,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) async {
        for await event in events {
            guard !isStopped,
                  peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration else {
                return
            }
            do {
                try await handlePeerEvent(
                    event,
                    sourcePeer: sourcePeer,
                    sourcePeerGeneration: sourcePeerGeneration
                )
            } catch is CancellationError {
                return
            } catch {
                guard peer === sourcePeer,
                      peerGeneration == sourcePeerGeneration else {
                    return
                }
                logger.error("Worldwide WebRTC session failed: \(error.localizedDescription)")
                await stop()
                return
            }
        }
        guard !Task.isCancelled,
              !isStopped,
              peer === sourcePeer,
              peerGeneration == sourcePeerGeneration else {
            return
        }
        logger.error("Worldwide WebRTC event stream ended unexpectedly")
        await stop()
    }

    /// Consumes only privacy-safe, best-effort telemetry. This stream ending, dropping values, or
    /// reporting lane failure must never stop the peer or mutate media/control authorization.
    private func consumeScreenClientDiagnosticsEvents(
        _ events: AsyncStream<WebRTCScreenClientDiagnosticsEvent>,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) async {
        for await event in events {
            guard !isStopped,
                  peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration else {
                return
            }
            switch event {
            case .heartbeat(let heartbeat):
                handleScreenClientDiagnosticsHeartbeat(heartbeat)
            case .laneFailure(let message):
                logger.info("Worldwide screen client diagnostics unavailable: \(message)")
            }
        }
    }

    // MARK: - Best-effort client audio evidence

    private func handleAudioClientDiagnosticsEvent(
        _ event: WebRTCAudioClientDiagnosticsEvent,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) {
        guard !isStopped, peer === sourcePeer, peerGeneration == sourcePeerGeneration else { return }
        let now = ProcessInfo.processInfo.systemUptime
        switch event {
        case .heartbeat(let value):
            guard value.isValid else { return }
            _ = audioClientDiagnostics.receive(value, peerGeneration: sourcePeerGeneration, now: now)
        case .laneFailure:
            // Lane failures carry no negotiation authority. A queued old failure cannot replace
            // a current valid sample; revocation/freshness is checked independently below.
            if case .fresh = audioClientDiagnostics.latest(now: now).status { break }
            audioClientDiagnostics.markUnavailable(.laneUnavailable)
        }
        logAudioClientDiagnosticsIfDue()
    }

    private func audioClientDiagnosticsStreamEnded(
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) {
        guard !isStopped, peer === sourcePeer, peerGeneration == sourcePeerGeneration else { return }
        audioClientDiagnostics.markUnavailable(.streamEnded)
        logAudioClientDiagnosticsIfDue()
    }

    private func tickAudioClientDiagnostics(
        negotiated: Bool,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) {
        guard !isStopped, peer === sourcePeer, peerGeneration == sourcePeerGeneration else { return }
        audioClientDiagnostics.observeNegotiated(negotiated)
        logAudioClientDiagnosticsIfDue()
    }

    private func logAudioClientDiagnosticsIfDue() {
        guard let audioClientDiagnosticsReportWriter else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let latest = audioClientDiagnostics.latest(now: now)
        let terminal: Bool
        switch latest.status {
        case .unavailable, .stale: terminal = true
        case .fresh: terminal = false
        }
        audioClientDiagnosticsReportWriter.submit(
            .init(latest: latest, uptime: now, date: Date()), terminal: terminal
        )
        if let message = audioClientDiagnostics.logMessageIfDue(now: now) {
            logger.info(message + " reportStorage=\(audioClientDiagnosticsReportWriter.storageStatus.rawValue)")
        }
    }

    var latestAudioClientDiagnostics: WorldwideAudioClientDiagnosticsSink.Latest {
        audioClientDiagnostics.latest(now: ProcessInfo.processInfo.systemUptime)
    }

    var audioClientDiagnosticsReportWriterIsInstalledForTesting: Bool {
        audioClientDiagnosticsReportWriter != nil
    }

    // MARK: - System Now Playing

    private func remoteMediaStateDidChange(
        _ update: WebRTCRemoteMediaStateUpdate
    ) async {
        guard !isStopped,
              update.isValid,
              update.revision > latestRemoteMediaControllerRevision else {
            traceRemoteMediaState(.serviceRejected, update: update,
                controllerRevision: update.revision,
                reason: isStopped ? .retiredLifecycle : (!update.isValid ? .invalidState : .staleRevision),
                failure: true)
            return
        }
        latestRemoteMediaControllerRevision = update.revision
        latestRemoteMediaItem = update.item
        latestRemoteMediaAdditionalItems = update.additionalItems
        remoteMediaPublication.applyControllerUpdate(update)
        traceRemoteMediaState(.serviceDesired, update: update,
            controllerRevision: update.revision, reason: .state)
        await publishCurrentRemoteMediaStateIfPossible()
    }

    private func publishCurrentRemoteMediaStateIfPossible() async {
        while transportAllowsCapture, let peer {
            // Trace the captured peer, not a replacement installed during this actor hop.
            // These values do not participate in publication/transport admission.
            let traceSourcePeerGeneration = peerGeneration
            let tracePriorLastSentRevision = remoteMediaPublication.lastSuccessfullySent?.revision ?? 0
            let remoteMediaIsAvailable =
                await peer.remoteMediaControlsAreNegotiated()
            remoteMediaPublication.setRemoteMediaAvailable(
                remoteMediaIsAvailable
            )
            guard let attempt = remoteMediaPublication.beginIfPossible(
                transportIsReady: transportAllowsCapture
            ) else {
                return
            }
            let sourcePeerGeneration = peerGeneration
            let sourceControllerRevision = remoteMediaPublication.desiredControllerRevision ?? 0
            let refresh = pendingRemoteMediaStateRefresh
            var succeeded = false
            var nativeAccepted = false
            do {
                try await peer.sendRemoteMediaState(attempt.update, respondingTo: refresh)
                nativeAccepted = true
                if self.peer === peer,
                   peerGeneration == sourcePeerGeneration {
                    succeeded = true
                    if pendingRemoteMediaStateRefresh == refresh {
                        pendingRemoteMediaStateRefresh = nil
                    }
                }
            } catch {
                // Peer/ICE/data-channel events own recovery. Keep the newest desired value dirty;
                // the bounded same-peer retry or a later state/recovery event will redrive it.
                logger.debug(
                    "Worldwide remote media state deferred: \(error.localizedDescription)"
                )
            }
            let completion = remoteMediaPublication.complete(
                attempt,
                succeeded: succeeded
            )
            let traceLastSentRevision = traceSourcePeerGeneration == peerGeneration
                ? remoteMediaPublication.lastSuccessfullySent?.revision ?? 0
                : tracePriorLastSentRevision
            if succeeded, completion != .ignored {
                traceRemoteMediaState(.nativeSent, update: attempt.update,
                    controllerRevision: sourceControllerRevision,
                    sourcePeerGeneration: traceSourcePeerGeneration,
                    sourceLastSentRevision: traceLastSentRevision, reason: .state)
            } else {
                traceRemoteMediaState(nativeAccepted ? .nativeRetired : .nativeFailed,
                    update: attempt.update,
                    controllerRevision: sourceControllerRevision,
                    sourcePeerGeneration: traceSourcePeerGeneration,
                    sourceLastSentRevision: traceLastSentRevision,
                    reason: nativeAccepted ? .peerRetired : .sendFailed, failure: true)
            }
            if succeeded {
                cancelRemoteMediaPublicationRetry()
            } else if completion == .retryLatest,
                      !isStopped,
                      self.peer === peer,
                      peerGeneration == sourcePeerGeneration {
                scheduleRemoteMediaPublicationRetry(
                    sourcePeer: peer,
                    sourcePeerGeneration: sourcePeerGeneration
                )
            }
            guard completion == .publishNewest else { return }
        }
    }

    private func traceRemoteMediaState(_ stage: RemoteMediaStateTrace.Stage,
                                      update: WebRTCRemoteMediaStateUpdate,
                                      controllerRevision: UInt64,
                                      sourcePeerGeneration: UInt64? = nil,
                                      sourceLastSentRevision: UInt64? = nil,
                                      reason: RemoteMediaStateTrace.Reason,
                                      failure: Bool = false) {
        let generation = sourcePeerGeneration ?? peerGeneration
        let summary = RemoteMediaStateTraceSummary(item: update.item,
                                                  additionalItems: update.additionalItems)
        let uptime = ProcessInfo.processInfo.systemUptime
        guard remoteMediaStateTraceGate.shouldReport(stage: stage, summary: summary,
            epoch: generation, failure: failure, uptime: uptime) else { return }
        logger.info(RemoteMediaStateTrace.message(stage: stage, session: remoteMediaTraceSession,
            processID: ProcessInfo.processInfo.processIdentifier, peerGeneration: generation,
            controllerRevision: controllerRevision,
            wireRevision: stage == .serviceDesired || stage == .serviceRejected ? 0 : update.revision,
            lastSuccessfullySentRevision: sourceLastSentRevision
                ?? remoteMediaPublication.lastSuccessfullySent?.revision ?? 0,
            summary: summary, reason: reason, uptime: uptime))
    }

    private func scheduleRemoteMediaPublicationRetry(
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) {
        guard remoteMediaPublication.hasPendingPublication,
              let token = remoteMediaPublicationRetryGate.schedule() else {
            return
        }
        remoteMediaPublicationRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            await self.remoteMediaPublicationRetryDidFire(
                token,
                sourcePeer: sourcePeer,
                sourcePeerGeneration: sourcePeerGeneration
            )
        }
    }

    private func remoteMediaPublicationRetryDidFire(
        _ token: WorldwideRemoteMediaPublicationRetryGate.Token,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) async {
        guard remoteMediaPublicationRetryGate.consume(token) else { return }
        remoteMediaPublicationRetryTask = nil
        guard !isStopped,
              peer === sourcePeer,
              peerGeneration == sourcePeerGeneration else { return }
        await publishCurrentRemoteMediaStateIfPossible()
    }

    private func cancelRemoteMediaPublicationRetry() {
        remoteMediaPublicationRetryGate.cancel()
        remoteMediaPublicationRetryTask?.cancel()
        remoteMediaPublicationRetryTask = nil
    }

    private func enqueueRemoteMediaCommand(
        _ command: WebRTCReceivedRemoteMediaCommand,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) async {
        traceRemoteMediaCommand(.serviceReceived, command: command, sourcePeerGeneration: sourcePeerGeneration)
        guard let commandGeneration = remoteMediaCommandCapacity.reserve() else {
            traceRemoteMediaCommand(.capacityRejected, command: command,
                                    sourcePeerGeneration: sourcePeerGeneration, result: .failed)
            await acknowledgeRemoteMediaCommand(
                command,
                result: .failed,
                sourcePeer: sourcePeer,
                sourcePeerGeneration: sourcePeerGeneration
            )
            return
        }
        let predecessor = remoteMediaCommandTask
        remoteMediaCommandTask = Task { [weak self] in
            _ = await predecessor?.result
            guard let self else { return }
            if !Task.isCancelled {
                await self.executeRemoteMediaCommand(
                    command,
                    sourcePeer: sourcePeer,
                    sourcePeerGeneration: sourcePeerGeneration,
                    commandGeneration: commandGeneration
                )
            } else {
                await self.traceRemoteMediaCommand(.queueCancelled, command: command,
                                                   sourcePeerGeneration: sourcePeerGeneration)
            }
            await self.finishRemoteMediaCommand(generation: commandGeneration)
        }
    }

    private func executeRemoteMediaCommand(
        _ command: WebRTCReceivedRemoteMediaCommand,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64,
        commandGeneration: UInt64
    ) async {
        guard !isStopped,
              peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              remoteMediaCommandCapacity.admits(generation: commandGeneration),
              command.isValid,
              transportAllowsCapture else {
            traceRemoteMediaCommand(.executionRetired, command: command,
                                    sourcePeerGeneration: sourcePeerGeneration)
            return
        }

        let request = command.request
        let result: WebRTCRemoteMediaCommandResult
        if let rejection = WebRTCRemoteMediaCommandAdmission.rejection(
            for: request,
            latestSuccessfullySent: remoteMediaPublication.lastSuccessfullySent
        ) {
            result = rejection
        } else if let item = ([latestRemoteMediaItem].compactMap { $0 } + latestRemoteMediaAdditionalItems)
            .first(where: { $0.contextID == request.contextID }) {
            if item.contextID != request.contextID {
                result = .staleContext
            } else if !item.capabilities.permits(request.command) {
                result = .unsupported
            } else if let prepared = remoteMediaController.prepareCommand(
                request.command,
                contextID: request.contextID,
                positionSeconds: request.positionSeconds,
                isAuthorized: { command.isValid }
            ) {
                result = await remoteMediaController.perform(prepared)
            } else {
                result = .staleContext
            }
        } else {
            result = .noActiveMedia
        }

        traceRemoteMediaCommand(.resultResolved, command: command,
                                sourcePeerGeneration: sourcePeerGeneration, result: result)

        guard !Task.isCancelled,
              !isStopped,
              peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              remoteMediaCommandCapacity.admits(generation: commandGeneration),
              transportAllowsCapture else {
            traceRemoteMediaCommand(.acknowledgementRetired, command: command,
                                    sourcePeerGeneration: sourcePeerGeneration, result: result)
            return
        }
        await acknowledgeRemoteMediaCommand(
            command,
            result: result,
            sourcePeer: sourcePeer,
            sourcePeerGeneration: sourcePeerGeneration
        )
    }

    private func acknowledgeRemoteMediaCommand(
        _ command: WebRTCReceivedRemoteMediaCommand,
        result: WebRTCRemoteMediaCommandResult,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) async {
        guard !isStopped,
              peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              transportAllowsCapture else {
            traceRemoteMediaCommand(.acknowledgementRetired, command: command,
                                    sourcePeerGeneration: sourcePeerGeneration, result: result)
            return
        }
        do {
            try await sourcePeer.acknowledgeRemoteMediaCommand(
                command,
                result: result
            )
            traceRemoteMediaCommand(.acknowledgementSent, command: command,
                                    sourcePeerGeneration: sourcePeerGeneration, result: result)
        } catch {
            traceRemoteMediaCommand(.acknowledgementFailed, command: command,
                                    sourcePeerGeneration: sourcePeerGeneration, result: result)
            logger.debug(
                "Worldwide remote media command acknowledgement deferred: "
                    + error.localizedDescription
            )
        }
    }

    private func traceRemoteMediaCommand(
        _ stage: WorldwideRemoteMediaCommandTrace.Stage,
        command: WebRTCReceivedRemoteMediaCommand,
        sourcePeerGeneration: UInt64,
        result: WebRTCRemoteMediaCommandResult? = nil
    ) {
        logger.info(WorldwideRemoteMediaCommandTrace.message(
            stage: stage,
            session: remoteMediaTraceSession,
            processID: ProcessInfo.processInfo.processIdentifier,
            peerGeneration: sourcePeerGeneration,
            request: command.request,
            publishedRevision: remoteMediaPublication.lastSuccessfullySent?.revision,
            contextMatches: ([latestRemoteMediaItem].compactMap { $0 } + latestRemoteMediaAdditionalItems)
                .contains(where: { $0.contextID == command.request.contextID }),
            authorized: command.isValid,
            transportReady: !isStopped && peerGeneration == sourcePeerGeneration && transportAllowsCapture,
            result: result,
            uptime: ProcessInfo.processInfo.systemUptime
        ))
    }

    private func finishRemoteMediaCommand(generation: UInt64) {
        remoteMediaCommandCapacity.finish(generation: generation)
    }

    private func resetRemoteMediaCommandQueue() {
        retireMediaHandoff()
        remoteMediaCommandTask?.cancel()
        remoteMediaCommandTask = nil
        remoteMediaCommandCapacity.reset()
        remoteMediaController.invalidateCommands()
    }

    /// Actual phone playback transfer, not routing the Mac audio track to another speaker.
    /// Product callers must surface unsupported/unavailable results; never fall back to streaming.
    func moveMediaToConnectedPhone() async throws -> UUID {
        let generation = peerGeneration
        guard !Task.isCancelled, !isStopped, transportAllowsCapture, pendingMediaHandoff == nil,
              let sourcePeer = peer, let item = latestRemoteMediaItem, item.playbackState == .playing,
              await sourcePeer.mediaHandoffIsNegotiated() else { throw WebRTCTransportError.transportNotHealthy }
        guard !Task.isCancelled, !isStopped, transportAllowsCapture, pendingMediaHandoff == nil,
              peer === sourcePeer, peerGeneration == generation,
              latestRemoteMediaItem?.contextID == item.contextID else { throw WebRTCTransportError.controlAuthorizationRevoked }
        let id = UUID(), authorization = WebRTCControlAuthorization()
        pendingMediaHandoff = .init(id: id, peer: sourcePeer, peerGeneration: generation,
            authorization: authorization)
        let prepared = await remoteMediaController.prepareHandoff(contextID: item.contextID,
            isAuthorized: { authorization.isValid })
        guard !Task.isCancelled, let prepared, pendingMediaHandoff?.id == id, authorization.isValid,
              peer === sourcePeer, peerGeneration == generation, transportAllowsCapture,
              latestRemoteMediaItem?.contextID == prepared.contextID else {
            retireMediaHandoff(id: id); throw WebRTCTransportError.controlAuthorizationRevoked
        }
        // Store before the wire send: a fast phone reply may arrive during the peer actor hop.
        pendingMediaHandoff?.prepared = prepared
        mediaHandoffExpiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, prepared.deadlineUptime - ProcessInfo.processInfo.systemUptime))) }
            catch { return }
            await self?.retireMediaHandoff(id: id)
        }
        do {
            let sent = try await sourcePeer.sendMediaHandoffOffer(contextID: prepared.contextID,
                id: id, source: prepared.sourceDescription)
            guard !Task.isCancelled, sent == id, pendingMediaHandoff?.id == id, authorization.isValid,
                  peer === sourcePeer, peerGeneration == generation, transportAllowsCapture else {
                throw WebRTCTransportError.controlAuthorizationRevoked
            }
            return id
        } catch {
            retireMediaHandoff(id: id)
            await sourcePeer.discardSentMediaHandoffOffer(id: id)
            throw error
        }
    }

    private func retireMediaHandoff(id: UUID? = nil, cancelExecution: Bool = true) {
        guard let pending = pendingMediaHandoff, id == nil || pending.id == id else { return }
        pending.authorization.revoke()
        pendingMediaHandoff = nil
        mediaHandoffExpiryTask?.cancel(); mediaHandoffExpiryTask = nil
        if cancelExecution { mediaHandoffExecutionTask?.cancel() }
        mediaHandoffExecutionTask = nil
        Task { await pending.peer.discardSentMediaHandoffOffer(id: pending.id) }
    }

    private func receiveMediaHandoffCommit(_ commit: WebRTCReceivedMediaHandoffCommit,
                                          sourcePeer: WebRTCPeer, sourcePeerGeneration: UInt64) async {
        if pendingMediaHandoff?.id == commit.id, pendingMediaHandoff?.executionStarted == true { return }
        guard !isStopped, transportAllowsCapture, peer === sourcePeer, peerGeneration == sourcePeerGeneration,
              let pending = pendingMediaHandoff, pending.peer === sourcePeer,
              pending.peerGeneration == sourcePeerGeneration, pending.id == commit.id,
              !pending.executionStarted, pending.authorization.isValid, commit.isValid,
              let prepared = pending.prepared, prepared.contextID == commit.contextID,
              prepared.videoID == commit.videoID, latestRemoteMediaItem?.contextID == prepared.contextID else {
            // This branch has not invoked the native source operation.
            try? await sourcePeer.acknowledgeMediaHandoffCommit(commit, result: .notApplied)
            return
        }
        pendingMediaHandoff?.executionStarted = true
        mediaHandoffExecutionTask = Task { [weak self, remoteMediaController] in
            let result = await remoteMediaController.performHandoffPause(prepared,
                phonePositionSeconds: commit.phonePositionSeconds, executionIsAuthorized: { commit.isValid })
            await self?.finishMediaHandoff(commit, result: result, sourcePeer: sourcePeer,
                sourcePeerGeneration: sourcePeerGeneration)
        }
    }

    private func finishMediaHandoff(_ commit: WebRTCReceivedMediaHandoffCommit,
                                   result: WebRTCRemoteMediaCommandResult,
                                   sourcePeer: WebRTCPeer, sourcePeerGeneration: UInt64) async {
        guard !Task.isCancelled, !isStopped, pendingMediaHandoff?.id == commit.id,
              peer === sourcePeer, peerGeneration == sourcePeerGeneration, transportAllowsCapture else { return }
        retireMediaHandoff(id: commit.id, cancelExecution: false)
        // A failed readback may follow an already-dispatched Pause. Do not claim no effect,
        // retry Pause, or automatically resume the Mac on an ambiguous native outcome.
        try? await sourcePeer.acknowledgeMediaHandoffCommit(commit,
            result: result == .applied ? .macPaused : .outcomeUnknown)
    }

    /// Updates transport health, routes protocol requests, and emits sanitized diagnostics.
    private func handlePeerEvent(
        _ event: WebRTCTransportEvent,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) async throws {
        switch event {
        case .outboundSignal(let payload):
            try await signaling.send(payload)

        case .peerStateChanged(let state):
            logger.info(
                Self.peerStateLogMessage(
                    state: state.rawValue,
                    processIdentifier: ProcessInfo.processInfo.processIdentifier
                )
            )
            switch state {
            case .new, .connecting:
                let previouslyAuthorizedRoute = peerIsConnected
                    || captureSource != nil
                    || audioSource != nil
                peerIsConnected = false
                if previouslyAuthorizedRoute {
                    await enterRecovery(reason: "peer route became indeterminate")
                    await recoveryCoordinator?.iceStateChanged(.disconnected)
                }
            case .connected:
                peerIsConnected = true
                if recoveryProofRequired, let peer {
                    await completePendingRecoveryProofIfPossible(
                        peer: peer,
                        epoch: recoveryProofEpoch
                    )
                } else if await markRecoveryHealthyIfPossible() {
                    await recoveryCoordinator?.iceStateChanged(.connected)
                }
                await publishCurrentRemoteMediaStateIfPossible()
            case .disconnected:
                peerIsConnected = false
                await enterRecovery(reason: "peer disconnected")
                await recoveryCoordinator?.iceStateChanged(.disconnected)
            case .failed:
                peerIsConnected = false
                await enterRecovery(reason: "peer failed")
                await recoveryCoordinator?.iceStateChanged(.failed)
            case .closed:
                await stop()
            }

        case .iceStateChanged(let state):
            logger.debug("Worldwide ICE state: \(state.rawValue)")
            switch state {
            case .connected, .completed:
                iceIsConnected = true
                if recoveryProofRequired, let peer {
                    await completePendingRecoveryProofIfPossible(
                        peer: peer,
                        epoch: recoveryProofEpoch
                    )
                } else if await markRecoveryHealthyIfPossible() {
                    await recoveryCoordinator?.iceStateChanged(state)
                }
                await publishCurrentRemoteMediaStateIfPossible()
            case .disconnected, .failed:
                iceIsConnected = false
                await enterRecovery(reason: "ICE route unavailable")
                await recoveryCoordinator?.iceStateChanged(state)
            case .closed:
                iceIsConnected = false
                await recoveryCoordinator?.iceStateChanged(state)
                await stop()
            case .new, .checking, .unknown:
                let previouslyAuthorizedRoute = iceIsConnected
                    || captureSource != nil
                    || audioSource != nil
                iceIsConnected = false
                if previouslyAuthorizedRoute {
                    // Initial ICE negotiation is allowed to move through these states. Once a
                    // route has carried an authorized capture, however, moving back to an
                    // indeterminate state is an uncertainty boundary and must fail closed.
                    await enterRecovery(reason: "ICE route became indeterminate")
                    await recoveryCoordinator?.iceStateChanged(.disconnected)
                }
            }

        case .iceGatheringStateChanged(let state):
            logger.debug("Worldwide ICE gathering: \(state.rawValue)")

        case .dataChannelStateChanged(let state):
            logger.debug("Worldwide control channel: \(state.rawValue)")
            let wasOpen = controlChannelIsOpen
            controlChannelIsOpen = state == .open
            if state == .open {
                if recoveryProofRequired, let peer {
                    await completePendingRecoveryProofIfPossible(
                        peer: peer,
                        epoch: recoveryProofEpoch
                    )
                } else if await markRecoveryHealthyIfPossible() {
                    await recoveryCoordinator?.iceStateChanged(.connected)
                }
                await publishCurrentRemoteMediaStateIfPossible()
            }
            if state == .closing || state == .closed || (wasOpen && state != .open) {
                await enterRecovery(reason: "control channel unavailable")
                await recoveryCoordinator?.iceStateChanged(.failed)
            }

        case .controlRequestReceived(let request):
            await handleControlRequest(request)

        case .controlAcknowledgementReceived(_, inputAuthorization: _):
            // Only the viewer receives host acknowledgements.
            break

        case .inputRequestReceived(let request, authorization: let authorization):
            await handleRemoteInputRequest(request, authorization: authorization)

        case .inputFeedbackReceived:
            // Only the viewer receives host input feedback.
            break

        case .inputSessionInvalidated(let reason):
            revokeRemoteInputAuthorization()
            logger.info("Worldwide remote input stopped: \(reason)")

        case .remoteMediaControlsAvailabilityChanged(let isAvailable):
            remoteMediaPublication.setRemoteMediaAvailable(isAvailable)
            if isAvailable {
                await publishCurrentRemoteMediaStateIfPossible()
            } else {
                pendingRemoteMediaStateRefresh = nil
                resetRemoteMediaCommandQueue()
            }

        case .remoteMediaStateRefreshRequested(let refresh):
            // One latest request is sufficient: a superseded readiness UUID cannot authorize the
            // viewer's current controls. Congestion uses the existing single-flight retry path.
            pendingRemoteMediaStateRefresh = refresh
            remoteMediaPublication.requestRefresh()
            await publishCurrentRemoteMediaStateIfPossible()

        case .remoteMediaCommandReceived(let command):
            await enqueueRemoteMediaCommand(
                command,
                sourcePeer: sourcePeer,
                sourcePeerGeneration: sourcePeerGeneration
            )

        case .mediaHandoffCommitReceived(let commit):
            await receiveMediaHandoffCommit(commit, sourcePeer: sourcePeer, sourcePeerGeneration: sourcePeerGeneration)

        case .mediaHandoffOfferReceived, .mediaHandoffCompleted,
             .remoteMediaStateChanged,
             .remoteMediaCommandAcknowledgementReceived:
            // These messages are host-originated and are consumed only by the iPhone viewer.
            break

        case .macHostedCallChallengeReceived(let challenge):
            guard featureProfile.allowsSystemAudio else { break }
            installMacHostedCallChallenge(
                challenge,
                sourcePeer: sourcePeer,
                sourcePeerGeneration: sourcePeerGeneration
            )

        case .macHostedCallEvidenceChanged:
            // Only the iPhone viewer receives host-originated call evidence.
            break

        case .screenMediaCoveredAcknowledgementReceived(let acknowledgement):
            guard screenMediaSuspension.confirmCover(
                acknowledgement,
                binding: currentScreenMediaSuspensionBinding
            ) else {
                await sourcePeer.cancelScreenMediaSuspension(
                    reason: "The viewer cover acknowledgement lost service ownership."
                )
                resetAutomaticScreenMediaSuspensionState()
                break
            }

        case .screenMediaMarkerPresentationReceived(let presentation):
            await handleAutomaticScreenMediaMarkerPresentation(
                presentation,
                peer: sourcePeer,
                peerGeneration: sourcePeerGeneration
            )

        case .screenMediaResumeRequestReceived(let request):
            await handleAutomaticScreenMediaResumeRequest(
                request,
                peer: sourcePeer,
                peerGeneration: sourcePeerGeneration
            )

        case .screenMediaEncoderResumeProbeEvent(let probeEvent):
            await handleAutomaticScreenMediaEncoderProbeEvent(
                probeEvent,
                peer: sourcePeer,
                peerGeneration: sourcePeerGeneration
            )

        case .screenMediaSuspensionInvalidated(let reason):
            let diagnostic = screenMediaSuspension.diagnosticSnapshot
            let resumeAttemptWasInFlight = automaticScreenMediaResumeContext != nil
            let diagnosticReason = String(
                reason
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .prefix(256)
            )
            logger.error(
                "Worldwide .screenMediaSuspensionInvalidated "
                    + "phase=\(diagnostic.phase.rawValue) "
                    + "screenRequestID="
                    + (diagnostic.screenRequestID.map(String.init) ?? "none")
                    + " suspensionGeneration="
                    + (diagnostic.suspensionGeneration.map(String.init) ?? "none")
                    + " bindingPeerGeneration="
                    + (diagnostic.binding.map {
                        String($0.peerGeneration)
                    } ?? "none")
                    + " bindingVisibilityEpoch="
                    + (diagnostic.binding.map {
                        String($0.visibilityCommandEpoch)
                    } ?? "none")
                    + " bindingRecoveryEpoch="
                    + (diagnostic.binding.map {
                        String($0.recoveryEpoch)
                    } ?? "none")
                    + " sourcePeerGeneration=\(sourcePeerGeneration) "
                    + "resumeAttemptInFlight=\(resumeAttemptWasInFlight) "
                    + "reason=\(diagnosticReason)"
            )
            if let context = automaticScreenMediaResumeContext {
                await failAutomaticScreenMediaResume(
                    peer: sourcePeer,
                    attemptID: context.attemptID,
                    reason: reason
                )
            }
            // WebRTCPeer has already cleared the negotiated suspension and disabled host video.
            // Ordinary ordered Show/Hide supersession deliberately does not emit this event; every
            // invalidation that does reach the host is therefore terminal for this media
            // generation. Locally reopening capture would violate privacy and request ordering.
            // Close only this media generation; availability remains ready for reconnect/Show.
            resetAutomaticScreenMediaSuspensionState()
            logger.error(
                "Worldwide screen suspension invalidation is closing the media generation "
                    + "for a fresh ordered Show"
            )
            await stop()

        case .screenMediaSuspensionReceived,
             .screenMediaMarkerReadyReceived,
             .screenMediaResumeReadyReceived,
             .screenMediaResumedAcknowledgementReceived:
            // These phases are viewer-only.
            break

        case .controlReceived:
            // Legacy signaling controls deliberately cannot start worldwide capture because they
            // do not provide the request ID and completion acknowledgement required by the v2 path.
            logger.debug("Ignored legacy worldwide screen control without acknowledgement")

        case .routeChanged(let route):
            logger.info("Worldwide WebRTC route: \(route.kind.rawValue)")
            let policyBeforeRouteEvent = screenVideoAdaptationPolicy
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            do {
                var updatedPolicy = screenVideoAdaptationPolicy
                updatedPolicy.invalidateSelectedRoute()
                screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            }
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: nil, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: nil,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            logger.debug(
                "Worldwide screen startup boundary event=routeChanged "
                    + "peerGeneration=\(sourcePeerGeneration) showEpoch=\(screenVisibilityCommandEpoch) "
                    + "policyRevision=\(screenVideoAdaptationPolicyRevision) pairIdentity=notProvidedByEvent "
                    + WorldwideScreenStartupDiagnostics.transitionFields(
                        before: policyBeforeRouteEvent,
                        after: screenVideoAdaptationPolicy,
                        incomingRoute: route
                    )
            )

        case .statistics(
            let snapshot,
            let wholePeerReportWasCollected
        ):
            guard peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration else {
                return
            }
            let routingAdmission =
                admitBlackHoleInputWithinSafeOutputFence()
            if let currentBlackHoleSnapshot =
                    routingAdmission.snapshot {
                await iPhoneMicrophoneForwarding.updateDeviceSnapshot(
                    currentBlackHoleSnapshot
                )
                await authorizeIPhoneMicrophoneForwardingIfPossible()
            }
            guard peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration else {
                return
            }
            let inbound = snapshot.inboundAudio
            await iPhoneMicrophoneForwarding
                .updateInboundMediaFreshness(
                    peer: sourcePeer,
                    peerGeneration: sourcePeerGeneration,
                    watermark:
                        WorldwideIPhoneMicrophoneInboundMediaWatermark(
                            packetsReceived: inbound?.packets,
                            bytesReceived: inbound?.bytes,
                            jitterBufferEmittedCount:
                                inbound?.jitterBufferEmittedCount,
                            totalSamplesReceived:
                                inbound?.totalSamplesReceived
                        )
                )
            guard peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration else {
                return
            }
            if let rtt = snapshot.currentRoundTripTime {
                logger.debug("Worldwide WebRTC RTT: \(Int((rtt * 1_000).rounded())) ms")
            }
            if let outbound = snapshot.outboundAudio {
                logger.debug(
                    "Worldwide audio RTP sentPackets="
                        + (outbound.packets.map { String($0) } ?? "unknown")
                        + " bytes=" + (outbound.bytes.map { String($0) } ?? "unknown")
                )
            }
            if let inbound {
                logger.debug(
                    Self.inboundAudioRTPLogMessage(
                        packets: inbound.packets,
                        bytes: inbound.bytes,
                        totalAudioEnergy: inbound.totalAudioEnergy,
                        audioLevel: inbound.audioLevel
                    )
                )
            }
            if let remoteInbound = snapshot.remoteInboundAudio {
                logger.debug(
                    "Worldwide audio remote loss="
                        + (remoteInbound.packetsLost.map { String($0) } ?? "unknown")
                        + " jitterMs="
                        + (remoteInbound.jitter.map {
                            String(format: "%.1f", $0 * 1_000)
                        } ?? "unknown")
                )
            }
            if let diagnostics = sourcePeer.externalAudioCapturer?.runtimeDiagnostics() {
                logger.debug(
                    "Worldwide audio queue phase=\(diagnostics.phase) "
                        + "frames=\(diagnostics.queuedFrames) "
                        + "high=\(diagnostics.queueHighWaterFrames) "
                        + "underruns=\(diagnostics.underruns) "
                        + "rebuffers=\(diagnostics.rebuffers) "
                        + "overflowDrops=\(diagnostics.overflowDrops) "
                        + "sourceGaps=\(diagnostics.sourceGaps) "
                        + "sourceOverlaps=\(diagnostics.sourceOverlaps)"
                )
            }
            let microphoneSnapshot =
                iPhoneMicrophoneForwarding.snapshot()
            logger.debug(
                Self.iPhoneMicrophoneForwardingLogMessage(
                    microphoneSnapshot
                )
            )
            if let selection = Self.hiddenWriterSelectionLogMessage(
                routingEpoch: blackHoleRoutingEpoch,
                peerGeneration:
                    microphoneSnapshot.peerGeneration,
                deviceGeneration:
                    microphoneSnapshot.deviceGeneration,
                selectionProven:
                    microphoneSnapshot.hiddenWriterSelectionProven,
                processIdentifier:
                    ProcessInfo.processInfo.processIdentifier
            ) {
                logger.info(selection)
            }
            await maintainWorldwideSafeOutputInvariant()
            guard peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration else {
                return
            }
            let ordinaryFallbackOwnsVideoPolicy =
                screenMediaSuspension.isAutomaticallySuspended
                    || !screenVideoAdaptationFastStatisticsAreAvailable
            if wholePeerReportWasCollected,
               screenVideoAdaptationFreshnessFence.admits(snapshot),
               ordinaryFallbackOwnsVideoPolicy {
                let expectedPolicyRevision =
                    prepareScreenVideoAdaptationEvidence(
                        from: .ordinaryFallback
                    )
                await adaptScreenVideoForNetworkConditions(
                    snapshot,
                    sourcePeer: sourcePeer,
                    sourcePeerGeneration: sourcePeerGeneration,
                    expectedPolicyRevision: expectedPolicyRevision,
                    allowsAutomaticResume: true
                )
            } else if !wholePeerReportWasCollected,
                      ordinaryFallbackOwnsVideoPolicy {
                // The microphone-health event still fires when the native whole-peer request is
                // busy or times out. Missing telemetry is not transport evidence; it may only
                // expire an already-raised, time-bounded application-limited video probe.
                await adaptScreenVideoForNetworkConditions(
                    nil,
                    sourcePeer: sourcePeer,
                    sourcePeerGeneration: sourcePeerGeneration,
                    expectedPolicyRevision:
                        screenVideoAdaptationPolicyRevision,
                    allowsAutomaticResume: false
                )
            }
            // Client diagnostics are an observability-only lane. Evaluate freshness strictly
            // after media adaptation so these best-effort heartbeats can never drive policy.
            await observeScreenClientDiagnosticsFreshness(
                peer: sourcePeer,
                peerGeneration: sourcePeerGeneration
            )

        case .iceCandidateError(let error):
            logger.error(
                "Worldwide ICE probe failed for \(error.url) " +
                "from \(error.address):\(error.port) [\(error.errorCode)]: \(error.reason)"
            )

        case .diagnosticFailure(let message):
            logger.error("Worldwide WebRTC diagnostic: \(message)")

        case .ended:
            await stop()

        case .remoteAudioTrack(let track):
            await installIPhoneMicrophoneTrack(track)

        case .identityReceived, .remoteVideoTrack, .negotiationNeeded:
            break
        }
    }

    /// Emits only stale/recovered transitions for the negotiated best-effort diagnostics lane.
    /// Missing evidence never mutates capture, adaptation, control, audio, or input state.
    private func handleScreenClientDiagnosticsHeartbeat(
        _ heartbeat: WebRTCScreenClientDiagnosticsHeartbeat
    ) {
        guard lastScreenClientDiagnosticsSequence.map({
            heartbeat.sequence > $0
        }) ?? true else {
            return
        }
        let receiptUptime = ProcessInfo.processInfo.systemUptime
        let activeScreenRequestID = screenMediaSuspension.activeScreenRequestID
        let matchesActiveScreen = activeScreenRequestID != nil
            && heartbeat.screenRequestID == activeScreenRequestID
        let staleReference: TimeInterval?
        if lastScreenClientDiagnosticsScreenRequestID
                == screenClientDiagnosticsExpectedScreenRequestID {
            staleReference = lastScreenClientDiagnosticsReceiptUptime
                ?? screenClientDiagnosticsExpectationStartedUptime
        } else {
            staleReference = screenClientDiagnosticsExpectationStartedUptime
        }
        lastScreenClientDiagnosticsReceiptUptime = receiptUptime
        lastScreenClientDiagnosticsSequence = heartbeat.sequence
        lastScreenClientDiagnosticsScreenRequestID = heartbeat.screenRequestID
        let matchesExpectedScreen =
            matchesActiveScreen
                && screenClientDiagnosticsExpectedScreenRequestID
                    == activeScreenRequestID
        if screenClientDiagnosticsSilenceWasReported,
           matchesExpectedScreen {
            let silenceMilliseconds = staleReference.map {
                Int(max(0, receiptUptime - $0) * 1_000)
            } ?? 0
            screenClientDiagnosticsSilenceWasReported = false
            logger.info(
                "Worldwide screen client diagnostics heartbeat recovered "
                    + "seq=\(heartbeat.sequence) "
                    + "silenceMs=\(silenceMilliseconds)"
            )
        }
        let message = Self.screenClientDiagnosticsLogMessage(
            heartbeat,
            hostPhase: screenMediaSuspension.diagnosticSnapshot.phase,
            isCorrelated: matchesActiveScreen
        )
        if !matchesActiveScreen {
            logger.info(message)
            return
        }
        switch heartbeat.liveness {
        case .intentionallyCovered, .covered,
             .presentingUnchanged, .presentingLive:
            logger.debug(message)
        case .trackMissing, .awaitingEvidence, .inboundRTPStalled,
             .decodeStalled, .presentationStalled, .unavailable:
            logger.info(message)
        }
    }

    private func observeScreenClientDiagnosticsFreshness(
        peer sourcePeer: WebRTCPeer,
        peerGeneration sourcePeerGeneration: UInt64
    ) async {
        guard !isStopped,
              peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              let screenRequestID = screenMediaSuspension.activeScreenRequestID else {
            screenClientDiagnosticsExpectedScreenRequestID = nil
            screenClientDiagnosticsExpectationStartedUptime = nil
            screenClientDiagnosticsSilenceWasReported = false
            return
        }
        let isNegotiated = await sourcePeer.screenClientDiagnosticsIsNegotiated()
        guard !isStopped,
              peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              screenMediaSuspension.activeScreenRequestID == screenRequestID else {
            return
        }
        guard isNegotiated else {
            screenClientDiagnosticsExpectedScreenRequestID = nil
            screenClientDiagnosticsExpectationStartedUptime = nil
            screenClientDiagnosticsSilenceWasReported = false
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if screenClientDiagnosticsExpectedScreenRequestID != screenRequestID {
            screenClientDiagnosticsExpectedScreenRequestID = screenRequestID
            screenClientDiagnosticsExpectationStartedUptime = now
            screenClientDiagnosticsSilenceWasReported = false
            return
        }
        if screenClientDiagnosticsExpectationStartedUptime == nil {
            screenClientDiagnosticsExpectationStartedUptime = now
        }
        guard let expectationStarted =
                screenClientDiagnosticsExpectationStartedUptime else {
            return
        }
        let freshnessReference = max(
            expectationStarted,
            lastScreenClientDiagnosticsScreenRequestID == screenRequestID
                ? (lastScreenClientDiagnosticsReceiptUptime ?? expectationStarted)
                : expectationStarted
        )
        let staleInterval = now - freshnessReference
        guard staleInterval >= Self.screenClientDiagnosticsStaleInterval,
              !screenClientDiagnosticsSilenceWasReported else {
            return
        }
        screenClientDiagnosticsSilenceWasReported = true
        let diagnostic = screenMediaSuspension.diagnosticSnapshot
        logger.info(
            "Worldwide screen client diagnostics warning=heartbeatMissing "
                + "phase=\(diagnostic.phase.rawValue) "
                + "screenRequestID=\(screenRequestID) "
                + "lastSequence="
                + (lastScreenClientDiagnosticsSequence.map(String.init) ?? "none")
                + " staleMs=\(Int(staleInterval * 1_000))"
        )
    }

    /// Starts a fresh threshold window whenever statistics switch between native request lanes or
    /// arrive after a long gap. This prevents nominally consecutive evidence from being assembled
    /// out of samples that were actually separated by a timeout or a cadence change.
    private func prepareScreenVideoAdaptationEvidence(
        from lane: ScreenVideoAdaptationEvidenceLane
    ) -> UInt64 {
        let now = ContinuousClock.now
        let exceededMaximumGap = screenVideoAdaptationLastEvidenceTime.map {
            $0.duration(to: now)
                > Self.screenVideoAdaptationMaximumEvidenceGap
        } ?? false
        if let previousLane = screenVideoAdaptationEvidenceLane,
           previousLane != lane || exceededMaximumGap {
            do {
                var updatedPolicy = screenVideoAdaptationPolicy
                updatedPolicy.resetIncompleteEvidenceWindow()
                screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            }
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: lane == .fastSender ? .fastSender : .ordinaryFallback, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: now,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        return screenVideoAdaptationPolicyRevision
    }

    /// One collector retains ordinary quality decisions while observing bounded startup probes
    /// between them. Microphone freshness and route maintenance keep their one-second cadence.
    private func sampleScreenVideoAdaptationStatistics(
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) async {
        let clock = ContinuousClock()
        var cadence = WorldwideScreenVideoSamplingCadence(startedAt: clock.now)
        while !Task.isCancelled {
            do {
                try await clock.sleep(until: cadence.nextDeadline)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  !isStopped,
                  peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration else {
                return
            }
            guard let sample = cadence.takeDueSample(at: clock.now) else { continue }
            let capacityProbeOnly = sample == .capacityOnly
            defer {
                let now = clock.now
                cadence.didFinishSample(at: now)
                cadence.setCapacityProbeEnabled(
                    captureSource != nil
                        && automaticScreenMediaResumeContext == nil
                        && screenVideoAdaptationFastStatisticsAreAvailable
                        && screenVideoAdaptationPolicy.applicationLimitedProbeOriginTier != nil,
                    at: now
                )
            }
            logNativeScreenProbeDiagnostics()
            guard captureSource != nil else {
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: false,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                continue
            }
            guard automaticScreenMediaResumeContext == nil else {
                // The exact resume attempt owns the sender ceiling until both the ACK and the
                // ordinary encoder limits have committed. Do not launch a request inside that
                // interval: its result could otherwise arrive just after the context is released
                // and cause a second back-to-back encoder transition from pre-restoration data.
                continue
            }

            let expectedPolicyRevision =
                screenVideoAdaptationPolicyRevision
            let expectedVisibilityEpoch = screenVisibilityCommandEpoch
            let expectedCaptureSource = captureSource
            let expectedCaptureAuthorization = captureAuthorization
            let statisticsStartedAt = clock.now
            let report = await sourcePeer.screenVideoStatisticsSnapshot(
                timeout: capacityProbeOnly
                    ? .milliseconds(100)
                    : Self.screenVideoAdaptationStatisticsTimeout
            )
            guard !Task.isCancelled,
                  !isStopped,
                  peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration else {
                return
            }
            let statisticsDuration = statisticsStartedAt.duration(to: clock.now).components
            let statisticsMilliseconds = Double(statisticsDuration.seconds) * 1_000
                + Double(statisticsDuration.attoseconds) / 1_000_000_000_000_000
            logger.debug(
                "Worldwide screen statistics evidenceLane=\(capacityProbeOnly ? "capacityOnly" : "regular") "
                    + "peerGeneration=\(sourcePeerGeneration) showEpoch=\(expectedVisibilityEpoch) "
                    + "durationMs=\(String(format: "%.1f", statisticsMilliseconds)) "
                    + "received=\(report != nil)"
            )
            if let report,
               // The enriched diagnostics route can be cached and differ only in optional
               // metadata. Only this native report's route may reset adaptation ownership.
               case let snapshot = report.nativeSnapshot,
               screenVideoAdaptationFreshnessFence.admits(snapshot),
               screenVisibilityCommandEpoch == expectedVisibilityEpoch,
               captureSource === expectedCaptureSource,
               captureAuthorization === expectedCaptureAuthorization,
               screenVideoAdaptationPolicyRevision
                == expectedPolicyRevision {
                if !capacityProbeOnly {
                    screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                        revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: true,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
                let adaptationRevision = capacityProbeOnly
                    ? expectedPolicyRevision
                    : prepareScreenVideoAdaptationEvidence(from: .fastSender)
                await adaptScreenVideoForNetworkConditions(
                    snapshot,
                    sourcePeer: sourcePeer,
                    sourcePeerGeneration: sourcePeerGeneration,
                    expectedPolicyRevision: adaptationRevision,
                    allowsAutomaticResume: false,
                    nativeReportTimestampMicroseconds: report.nativeReportTimestampMicroseconds,
                    capacityProbeOnly: capacityProbeOnly
                )
            } else {
                // A timeout, an outstanding native request, or an ordered route/policy change
                // makes the ordinary one-second event the authoritative fallback until a fresh
                // sender-scoped sample succeeds.
                if !capacityProbeOnly {
                    screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                        revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: false,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
                // A missing report cannot extend a temporary ceiling indefinitely, even if the
                // ordinary statistics lane is also stalled. Expiry never supplies health proof.
                await adaptScreenVideoForNetworkConditions(
                    nil,
                    sourcePeer: sourcePeer,
                    sourcePeerGeneration: sourcePeerGeneration,
                    expectedPolicyRevision: screenVideoAdaptationPolicyRevision,
                    allowsAutomaticResume: false
                )
            }

        }
    }

    private func logNativeScreenProbeDiagnostics() {
        let batch = WebRTCNativeProbeDiagnostics.drain()
        for event in batch.events {
            // Native log callbacks are process-wide; do not attach this peer's identity to them.
            logger.debug(
                "Worldwide screen native probe scope=process "
                    + "seq=\(event.sequence) ageMs=\(event.processDiagnosticsAgeMilliseconds) "
                    + "kind=\(event.kind.rawValue) "
                    + "active=\(event.isActive.map(String.init) ?? "unknown") "
                    + "sendBps=\(event.bitrateBps.map(String.init) ?? "unknown") "
                    + "receiveBps=\(event.receiveBitrateBps.map(String.init) ?? "unknown") "
                    + "sendIntervalUs=\(event.sendInterval?.diagnosticToken ?? "unknown") "
                    + "receiveIntervalUs=\(event.receiveInterval?.diagnosticToken ?? "unknown") "
                    + "minimumBytes=\(event.minimumBytes.map(String.init) ?? "unknown") "
                    + "minimumPackets=\(event.minimumPackets.map(String.init) ?? "unknown") "
                    + "cluster=\(event.clusterID.map(String.init) ?? "unknown") "
                    + "blocked=\(event.blockReason?.rawValue ?? "none") "
                    + "dropped=\(batch.droppedEventCount)"
            )
        }
    }

    /// Applies a new sender ceiling only after the current capture and peer identities survive
    /// the cross-actor parameter update. Failed native updates are retried by the next sample.
    private func adaptScreenVideoForNetworkConditions(
        _ snapshot: WebRTCStatisticsSnapshot?,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64,
        expectedPolicyRevision: UInt64,
        allowsAutomaticResume: Bool,
        nativeReportTimestampMicroseconds: Double? = nil,
        capacityProbeOnly: Bool = false
    ) async {
        // Marker and real-frame RTP deltas are valid only while the exact sender configuration
        // remains frozen. The bounded probe owns its temporary ceiling; the first statistics
        // sample after success or retry reapplies ordinary policy.
        guard automaticScreenMediaResumeContext == nil,
              peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              screenVideoAdaptationPolicyRevision
                == expectedPolicyRevision else {
            return
        }
        let forwardingAuthorization = captureForwardingAuthorization
        let isCaptureActive = captureSource != nil
            && captureSink != nil
            && captureAuthorization?.isValid == true
            && forwardingAuthorization?.isValid == true
            && forwardingAuthorization.map {
                captureSink?.allowsActiveUse(authorizedBy: $0) == true
            } == true
        guard isCaptureActive || allowsAutomaticResume else { return }

        var proposedPolicy = screenVideoAdaptationPolicy
        var capacityDiagnostics: WorldwideScreenCapacityProbeDiagnostics?
        var floorDiagnostics: WorldwideScreenFloorRecoveryDiagnostics?
        let changedRecommendation:
            WorldwideScreenVideoEncodingRecommendation?
        if let snapshot, capacityProbeOnly {
            changedRecommendation = proposedPolicy.updateCapacityProbe(
                peerGeneration: sourcePeerGeneration,
                isCaptureActive: isCaptureActive,
                availableOutgoingBitrateBps: snapshot.availableOutgoingBitrate,
                currentRoundTripTimeSeconds: snapshot.currentRoundTripTime,
                roundTripTimeObservation: snapshot.roundTripTimeObservation,
                collectionSequence: snapshot.collectionSequence,
                nativeReportTimestampMicroseconds: nativeReportTimestampMicroseconds,
                selectedRoute: snapshot.route,
                outboundVideoPacketsSent: snapshot.outboundVideo?.packets,
                outboundVideoTotalPacketSendDelaySeconds:
                    snapshot.outboundVideo?.totalPacketSendDelay,
                diagnostics: { capacityDiagnostics = $0 }
            )
        } else if let snapshot {
            changedRecommendation = proposedPolicy.update(
                peerGeneration: sourcePeerGeneration,
                isCaptureActive: isCaptureActive,
                isAutomaticallySuspended:
                    screenMediaSuspension.isAutomaticallySuspended,
                availableOutgoingBitrateBps: snapshot.availableOutgoingBitrate,
                currentRoundTripTimeSeconds: snapshot.currentRoundTripTime,
                roundTripTimeObservation: snapshot.roundTripTimeObservation,
                collectionSequence: snapshot.collectionSequence,
                requireRoundTripTimeObservation: true,
                selectedRoute: snapshot.route,
                outboundVideoPacketsSent: snapshot.outboundVideo?.packets,
                outboundVideoTotalPacketSendDelaySeconds:
                    snapshot.outboundVideo?.totalPacketSendDelay,
                nativeReportTimestampMicroseconds: nativeReportTimestampMicroseconds,
                diagnostics: { floorDiagnostics = $0 }
            )
        } else {
            changedRecommendation = proposedPolicy
                .expireApplicationLimitedProbeWithoutReport(
                    peerGeneration: sourcePeerGeneration,
                    isCaptureActive: isCaptureActive
                )
            // A terminal native fault must survive a no-op recommendation. Retry restrictive
            // limits only until the applied sender matches; never reapply every faulted tick.
            guard changedRecommendation != nil
                || appliedScreenVideoRecommendation != proposedPolicy.currentRecommendation
                || (proposedPolicy.hasNativeAdaptationPolicyFault
                    && !screenVideoAdaptationPolicy.hasNativeAdaptationPolicyFault) else { return }
        }
        let recommendation = changedRecommendation
            ?? proposedPolicy.currentRecommendation
        let pairContinuity = screenStartupDiagnostics.observePair(
            peerGeneration: sourcePeerGeneration,
            showEpoch: screenVisibilityCommandEpoch,
            collectionSequence: snapshot?.collectionSequence,
            nativeTimestamp: nativeReportTimestampMicroseconds,
            observation: snapshot?.roundTripTimeObservation
        )
        // Keep the regular-lane admission evidence during spatial startup as well as at the
        // recovery floor. In particular, a proposal is not an accepted native geometry change.
        if let floorDiagnostics,
           screenVideoAdaptationPolicy.currentTier == .audioPriority
            || proposedPolicy.currentTier == .audioPriority
            || screenVideoAdaptationPolicy.startupSpatialModeIsActive
            || proposedPolicy.startupSpatialModeIsActive {
            logger.debug(
                "Worldwide screen floor proposal peerGeneration=\(sourcePeerGeneration) "
                    + "policyRevision=\(expectedPolicyRevision) "
                    + "visibilityEpoch=\(screenVisibilityCommandEpoch) "
                    + floorDiagnostics.logFields
            )
        }
        if let capacityDiagnostics {
            logger.debug(
                "Worldwide screen capacity proposal peerGeneration=\(sourcePeerGeneration) "
                    + "policyRevision=\(expectedPolicyRevision) "
                    + capacityDiagnostics.logFields
            )
        }
        let rttDiagnostics = WorldwideScreenRoundTripTimeDiagnostics(
            observation: snapshot?.roundTripTimeObservation
        )
        logger.debug(
            "Worldwide screen network peerGeneration=\(sourcePeerGeneration) "
                + "showEpoch=\(screenVisibilityCommandEpoch) policyRevision=\(expectedPolicyRevision) "
                + "nativePairContinuity=\(pairContinuity.rawValue) "
                + "nativeReportMicros="
                + (WorldwideScreenCapacityProbeDiagnostics.boundedInteger(
                    nativeReportTimestampMicroseconds
                ).map(String.init) ?? "unknown")
                + " " + WorldwideScreenStartupDiagnostics.transitionFields(
                    before: screenVideoAdaptationPolicy,
                    after: proposedPolicy,
                    incomingRoute: snapshot?.route
                )
                + " totalCapKbps=\(maximumVideoBitrate / 1_000) "
                + "fullVideoKbps=\(proposedPolicy.maximumTierVideoBitrateBps / 1_000) "
                + "tier=\(String(describing: recommendation.tier)) "
                + "sustainKbps="
                + "\(proposedPolicy.currentTierMinimumSustainableBitrateBps / 1_000) "
                + "directUpgradeKbps="
                + (proposedPolicy.nextHigherTierMinimumDirectUpgradeBitrateBps.map {
                    String($0 / 1_000)
                } ?? "none")
                + " proposedCeilingKbps=\(recommendation.maximumBitrateBps / 1_000)"
                + " proposedTotalCapKbps="
                + "\(recommendation.maximumTotalRTPBitrateBps / 1_000)"
                + " promotionCapKbps="
                + (proposedPolicy.promotionCapacityContinuity.map {
                    String($0.maximumTotalRTPBitrateBps / 1_000)
                } ?? "none")
                + " probeOrigin="
                + (proposedPolicy.applicationLimitedProbeOriginTier.map {
                    String(describing: $0)
                } ?? "none")
                + " probeBest="
                + (proposedPolicy.applicationLimitedProbeBestQualifiedTier.map {
                    String(describing: $0)
                } ?? "none")
                + " probeHealthySamples="
                + "\(proposedPolicy.applicationLimitedProbeHealthySampleCount)"
                + " startupSpatial="
                + (proposedPolicy.startupSpatialModeIsActive ? "active"
                    : (proposedPolicy.startupSpatialModeIsDisproved
                        ? "disproved" : "inactive"))
                + " queuePressureSamples=\(proposedPolicy.queuePressureSampleCount) "
                + "bweKbps="
                + (snapshot?.availableOutgoingBitrate.map {
                    String(format: "%.0f", $0 / 1_000)
                } ?? "unknown")
                + " rttMs="
                + (snapshot?.currentRoundTripTime.map {
                    String(format: "%.1f", $0 * 1_000)
                } ?? "unknown")
                + " rttObservation=\(proposedPolicy.roundTripTimeDisposition.rawValue)"
                + " rttTotalMicros="
                + (rttDiagnostics.totalMicroseconds.map(String.init) ?? "unknown")
                + " rttResponses="
                + (rttDiagnostics.responsesReceived.map(String.init) ?? "unknown")
                + " collectionSeq="
                + (snapshot?.collectionSequence.map(String.init) ?? "unknown")
                + " consumedSeq="
                + (proposedPolicy.lastConsumedCollectionSequence.map(String.init) ?? "unknown")
                + " primarySendQueueMs="
                + (proposedPolicy.lastAveragePacketSendDelaySeconds.map {
                    String(format: "%.1f", $0 * 1_000)
                } ?? "unknown")
                + " encoded="
                + (snapshot?.outboundVideo.flatMap { video in
                    guard let width = video.frameWidth,
                          let height = video.frameHeight else {
                        return nil
                    }
                    return "\(width)x\(height)"
                } ?? "unknown")
                + " fps="
                + (snapshot?.outboundVideo?.framesPerSecond.map {
                    String(format: "%.1f", $0)
                } ?? "unknown")
                + " evidenceLane=\(capacityProbeOnly ? "capacityOnly" : "regular")"
        )
        guard isCaptureActive else {
            if peer === sourcePeer,
               peerGeneration == sourcePeerGeneration,
               screenVideoAdaptationPolicyRevision
                == expectedPolicyRevision {
                let decision = proposedPolicy.automaticSuspensionDecision(
                    isCaptureActive: false,
                    isAutomaticallySuspended:
                        screenMediaSuspension.isAutomaticallySuspended
                )
                screenVideoAdaptationOwner = .init(policy: proposedPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                if decision == .resume {
                    await beginAutomaticScreenMediaResumeIfPossible(
                        peer: sourcePeer,
                        peerGeneration: sourcePeerGeneration
                    )
                }
            }
            return
        }
        var applyingPolicyRevision = expectedPolicyRevision
        if proposedPolicy.hasNativeAdaptationPolicyFault {
            var faultRetention = screenVideoAdaptationPolicy
            // This actor's peer/revision gate authorizes the first bound lifetime as well.
            faultRetention.bind(toPeerGeneration: sourcePeerGeneration)
            faultRetention.retainNativeAdaptationPolicyFault(from: proposedPolicy)
            if faultRetention != screenVideoAdaptationPolicy {
                screenVideoAdaptationOwner = .init(policy: faultRetention,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                applyingPolicyRevision = screenVideoAdaptationPolicyRevision
            }
        }
        if changedRecommendation != nil
            || appliedScreenVideoRecommendation != recommendation {
            guard let source = captureSource,
                  let sink = captureSink,
                  let captureAuthorization,
                  let forwardingAuthorization,
                  let baseDimensions = captureVideoBaseDimensions,
                  let capturer = sourcePeer.externalVideoCapturer else {
                return
            }

            var attemptConsumption = screenVideoAdaptationPolicy
            attemptConsumption.retainFloorRecoveryAttemptConsumption(from: proposedPolicy)
            if attemptConsumption != screenVideoAdaptationPolicy {
                // The attempt belongs to this Show even if native apply is later superseded.
                screenVideoAdaptationOwner = .init(policy: attemptConsumption,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                applyingPolicyRevision = screenVideoAdaptationPolicyRevision
            }
            do {
                let senderUpdate = try await sourcePeer.applyScreenVideoEncodingLimits(
                    recommendation.webRTCLimits
                )
                guard peer === sourcePeer,
                      peerGeneration == sourcePeerGeneration,
                      screenVideoAdaptationPolicyRevision
                        == applyingPolicyRevision,
                      captureSource === source,
                      captureSink === sink,
                      self.captureAuthorization === captureAuthorization,
                      self.captureForwardingAuthorization
                        === forwardingAuthorization,
                      captureAuthorization.isValid,
                      forwardingAuthorization.isValid,
                      sink.allowsActiveUse(
                          authorizedBy: forwardingAuthorization
                      ),
                      captureVideoBaseDimensions == baseDimensions else {
                    logger.debug(
                        "Worldwide screen capacity nativeApply=stale "
                            + "peerGeneration=\(sourcePeerGeneration) policyRevision=\(applyingPolicyRevision)"
                    )
                    do {
                        _ = try await sourcePeer
                            .rollbackScreenVideoEncodingUpdateIfCurrent(
                                senderUpdate
                            )
                    } catch {
                        logger.error(
                            "Worldwide screen video stale-update rollback failed: "
                                + error.localizedDescription
                        )
                    }
                    return
                }
                if appliedScreenVideoRecommendation?.maximumFramesPerSecond
                    != recommendation.maximumFramesPerSecond {
                    capturer.adaptOutput(
                        width: Int32(baseDimensions.width),
                        height: Int32(baseDimensions.height),
                        framesPerSecond: Int32(
                            recommendation.maximumFramesPerSecond
                        )
                    )
                }
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: recommendation)
                logger.debug(
                    "Worldwide screen capacity nativeApply=accepted "
                        + "peerGeneration=\(sourcePeerGeneration) policyRevision=\(applyingPolicyRevision) "
                        + "showEpoch=\(screenVisibilityCommandEpoch) "
                        + "totalCapBps=\(recommendation.maximumTotalRTPBitrateBps)"
                )
                logger.info(
                    "Worldwide screen video tier=\(String(describing: recommendation.tier)) "
                        + "maxKbps=\(recommendation.maximumBitrateBps / 1_000) "
                        + "fps=\(recommendation.maximumFramesPerSecond) "
                        + "scale=\(String(format: "%.2f", recommendation.scaleResolutionDownBy)) "
                        + "totalCapKbps=\(recommendation.maximumTotalRTPBitrateBps / 1_000) "
                        + "evidenceLane=\(capacityProbeOnly ? "capacityOnly" : "regular")"
                )
            } catch {
                guard peer === sourcePeer,
                      peerGeneration == sourcePeerGeneration,
                      screenVideoAdaptationPolicyRevision
                        == applyingPolicyRevision,
                      captureSource === source,
                      captureSink === sink,
                      self.captureAuthorization === captureAuthorization,
                      self.captureForwardingAuthorization === forwardingAuthorization,
                      captureAuthorization.isValid,
                      forwardingAuthorization.isValid,
                      sink.allowsActiveUse(authorizedBy: forwardingAuthorization),
                      captureVideoBaseDimensions == baseDimensions else {
                    return
                }
                logger.error(
                    "Worldwide screen video adaptation held its previous tier: "
                        + error.localizedDescription
                )
                logger.debug(
                    "Worldwide screen capacity nativeApply=failed "
                        + "peerGeneration=\(sourcePeerGeneration) policyRevision=\(applyingPolicyRevision) "
                        + "proposedTotalCapBps=\(recommendation.maximumTotalRTPBitrateBps)"
                )
                let cancelledFloorRecoveryProbe =
                    screenVideoAdaptationPolicy.floorRecoveryProbeIsActive
                        && proposedPolicy.floorRecoveryProbeWasCancelled
                do {
                    var updatedPolicy = screenVideoAdaptationPolicy
                    updatedPolicy
                        .retainStartupSpatialModeTerminalState(from: proposedPolicy)
                    screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                        revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
                do {
                    var updatedPolicy = screenVideoAdaptationPolicy
                    updatedPolicy.retainFloorRecoveryAttemptConsumption(
                        from: proposedPolicy
                    )
                    screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                        revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
                if cancelledFloorRecoveryProbe
                    || (capacityProbeOnly
                        && screenVideoAdaptationPolicy.applicationLimitedProbeOriginTier != nil
                        && proposedPolicy.applicationLimitedProbeOriginTier == nil) {
                    // A failed cap reduction must not erase a terminal floor or fast negative.
                    screenVideoAdaptationOwner = .init(policy: proposedPolicy,
                        revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                    screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                        revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                } else if capacityProbeOnly {
                    do {
                        var updatedPolicy = screenVideoAdaptationPolicy
                        updatedPolicy.retainCapacityProbeObservationIdentity(
                            from: proposedPolicy
                        )
                        screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                    }
                    screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                        revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                } else {
                    screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                        revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
                return
            }
        }

        guard peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              screenVideoAdaptationPolicyRevision
                == applyingPolicyRevision else {
            return
        }
        screenVideoAdaptationOwner = .init(policy: proposedPolicy,
            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
    }

    private func beginAutomaticScreenMediaResumeIfPossible(
        peer sourcePeer: WebRTCPeer,
        peerGeneration sourcePeerGeneration: UInt64
    ) async {
        guard peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              screenMediaSuspension.isAutomaticallySuspended,
              !screenMediaSuspension.isResumeProbeInFlight,
              automaticScreenMediaResumeContext == nil,
              let notice = screenMediaSuspension.currentSuspensionNotice,
              await sourcePeer.screenMediaSuspensionIsNegotiated() else {
            return
        }
        let binding = currentScreenMediaSuspensionBinding
        let attemptID = UUID()
        guard screenMediaSuspension.beginResumeAttempt(
            attemptID: attemptID,
            binding: binding
        ) else {
            return
        }
        do {
            var updatedPolicy = screenVideoAdaptationPolicy
            updatedPolicy.automaticResumeAttemptBegan()
            screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        automaticScreenMediaResumeContext = AutomaticScreenMediaResumeContext(
            binding: binding,
            notice: notice,
            attemptID: attemptID,
            finalAcknowledgementCommit:
                WorldwideScreenAutomaticResumeCommitLatch(),
            inputOwnershipClaim: latestShowInputOwnershipClaim,
            probeAuthorization: nil,
            forwardingAuthorization: nil,
            boundary: nil,
            markerReady: nil,
            markerPresentation: nil
        )

        do {
            let authorization = try await startScreenCaptureWithDisplayModeRetries()
            guard peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration,
                  screenMediaSuspension.owns(binding),
                  var context = automaticScreenMediaResumeContext,
                  context.attemptID == attemptID,
                  let source = captureSource,
                  let sink = captureSink,
                  captureForwardingAuthorization === authorization,
                  let baseDimensions = captureVideoBaseDimensions,
                  let capturer = sourcePeer.externalVideoCapturer else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            let probeAuthorization = WebRTCControlAuthorization()
            context.probeAuthorization = probeAuthorization
            context.forwardingAuthorization = authorization
            automaticScreenMediaResumeContext = context

            let recommendation = screenVideoAdaptationPolicy.currentRecommendation
            // Ten encoder slots per second are enough to admit the one marker and the bounded
            // one-Hz real recovery lane without restoring the ordinary 60 fps ceiling while the
            // link is still congested.
            let probeFramesPerSecond = 10
            if recommendation.maximumFramesPerSecond < probeFramesPerSecond {
                let probeUpdate = try await sourcePeer.applyScreenVideoEncodingLimits(
                    WebRTCScreenVideoEncodingLimits(
                        maximumBitrateBps: recommendation.maximumBitrateBps,
                        maximumFramesPerSecond: probeFramesPerSecond,
                        scaleResolutionDownBy:
                            recommendation.scaleResolutionDownBy
                    )
                )
                guard peer === sourcePeer,
                      peerGeneration == sourcePeerGeneration,
                      captureSource === source,
                      captureSink === sink,
                      captureForwardingAuthorization === authorization,
                      authorization.isValid,
                      captureVideoBaseDimensions == baseDimensions,
                      screenMediaSuspension.owns(binding),
                      let current = automaticScreenMediaResumeContext,
                      current.attemptID == attemptID,
                      current.binding == binding,
                      current.probeAuthorization === probeAuthorization,
                      current.forwardingAuthorization === authorization else {
                    _ = try? await sourcePeer
                        .rollbackScreenVideoEncodingUpdateIfCurrent(probeUpdate)
                    throw WorldwideScreenServiceError.transportUnavailable
                }
                capturer.adaptOutput(
                    width: Int32(baseDimensions.width),
                    height: Int32(baseDimensions.height),
                    framesPerSecond: Int32(probeFramesPerSecond)
                )
                // The probe ceiling is temporary and must be restored after final presentation.
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: nil)
            }

            let boundary = try await source.performSampleDeliveryBarrier {
                sink.beginAutomaticResumeMarkerGate(
                    authorizedBy: authorization
                )
            }
            guard let boundary,
                  peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration,
                  captureSource === source,
                  captureSink === sink,
                  captureForwardingAuthorization === authorization,
                  authorization.isValid,
                  screenMediaSuspension.owns(binding),
                  var current = automaticScreenMediaResumeContext,
                  current.attemptID == attemptID else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            current.boundary = boundary
            automaticScreenMediaResumeContext = current

            let nonceBytes = withUnsafeBytes(of: attemptID.uuid) { Array($0) }
            guard let marker = ScreenVideoInBandMarkerNonce(bytes: nonceBytes) else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            let markerBuffer = try ScreenVideoInBandMarkerPixelBufferFactory.make(
                width: boundary.geometry.surfaceWidth,
                height: boundary.geometry.surfaceHeight,
                marker: marker
            )
            try await sourcePeer.beginScreenMediaResumeProbeIfTransportHealthy(
                attemptID: attemptID,
                marker: marker,
                boundaryRevision: boundary.revision,
                markerInputGateIsClosed: true,
                authorization: probeAuthorization
            )
            guard peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration,
                  captureSource === source,
                  captureSink === sink,
                  captureForwardingAuthorization === authorization,
                  authorization.isValid,
                  probeAuthorization.isValid,
                  screenMediaSuspension.owns(binding),
                  let current = automaticScreenMediaResumeContext,
                  current.attemptID == attemptID,
                  current.binding == binding,
                  current.probeAuthorization === probeAuthorization,
                  current.forwardingAuthorization === authorization,
                  current.boundary == boundary else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            capturer.capture(
                pixelBuffer: markerBuffer,
                timestamp: CMClockGetTime(CMClockGetHostTimeClock())
            )
            scheduleAutomaticScreenMediaResumeTimeout(
                attemptID: attemptID,
                peerGeneration: sourcePeerGeneration
            )
            logger.info("Worldwide screen video resume marker injected")
        } catch {
            await failAutomaticScreenMediaResume(
                peer: sourcePeer,
                attemptID: attemptID,
                reason: "resume probe startup failed: \(error.localizedDescription)"
            )
        }
    }

    private func scheduleAutomaticScreenMediaResumeTimeout(
        attemptID: UUID,
        peerGeneration sourcePeerGeneration: UInt64
    ) {
        cancelAutomaticScreenMediaResumeTimeout()
        automaticScreenMediaResumeTimeoutGeneration &+= 1
        if automaticScreenMediaResumeTimeoutGeneration == 0 {
            automaticScreenMediaResumeTimeoutGeneration = 1
        }
        let timeoutGeneration = automaticScreenMediaResumeTimeoutGeneration
        automaticScreenMediaResumeTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.automaticScreenMediaResumeTimeout)
            } catch {
                return
            }
            await self?.automaticScreenMediaResumeTimedOut(
                attemptID: attemptID,
                peerGeneration: sourcePeerGeneration,
                timeoutGeneration: timeoutGeneration
            )
        }
    }

    private func cancelAutomaticScreenMediaResumeTimeout() {
        automaticScreenMediaResumeTimeoutGeneration &+= 1
        if automaticScreenMediaResumeTimeoutGeneration == 0 {
            automaticScreenMediaResumeTimeoutGeneration = 1
        }
        automaticScreenMediaResumeTimeoutTask?.cancel()
        automaticScreenMediaResumeTimeoutTask = nil
    }

    /// Fences native requests at sender restoration or Hide and discards partial threshold
    /// evidence from the preceding encoder/visibility epoch.
    private func beginPostResumeScreenVideoAdaptationEpoch() {
        if let peer {
            do {
                var updatedFreshnessFence = screenVideoAdaptationFreshnessFence
                updatedFreshnessFence.beginPostResumeEpoch(
                    minimumCollectionSequence:
                        peer.minimumNextStatisticsCollectionSequence()
                )
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: updatedFreshnessFence.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            }
        } else {
            do {
                var updatedFreshnessFence = screenVideoAdaptationFreshnessFence
                updatedFreshnessFence.reset()
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: updatedFreshnessFence.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            }
        }
        do {
            var updatedPolicy = screenVideoAdaptationPolicy
            updatedPolicy.resetIncompleteEvidenceWindow()
            screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: nil, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: nil,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
    }

    private func automaticScreenMediaResumeTimedOut(
        attemptID: UUID,
        peerGeneration sourcePeerGeneration: UInt64,
        timeoutGeneration: UInt64
    ) async {
        guard automaticScreenMediaResumeTimeoutGeneration == timeoutGeneration,
              peerGeneration == sourcePeerGeneration,
              let peer,
              automaticScreenMediaResumeContext?.attemptID == attemptID else {
            return
        }
        await failAutomaticScreenMediaResume(
            peer: peer,
            attemptID: attemptID,
            reason: "resume proof timed out"
        )
    }

    private func failAutomaticScreenMediaResume(
        peer sourcePeer: WebRTCPeer,
        attemptID: UUID,
        reason: String
    ) async {
        guard let context = automaticScreenMediaResumeContext,
              context.attemptID == attemptID else {
            return
        }
        guard context.finalAcknowledgementCommit.claimFailure() else {
            // The irreversible send won the same latch. The viewer can already uncover, so a
            // concurrent display/route lifecycle owns any subsequent capture transition.
            cancelAutomaticScreenMediaResumeTimeout()
            do {
                var updatedPolicy = screenVideoAdaptationPolicy
                updatedPolicy.automaticResumeAttemptSucceeded()
                screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            }
            beginPostResumeScreenVideoAdaptationEpoch()
            automaticScreenMediaResumeContext = nil
            return
        }
        let ownedSource = captureSource
        let ownedSink = captureSink
        let ownedForwardingAuthorization = context.forwardingAuthorization
        let ownedCaptureIsCurrent = ownedSource != nil
            && ownedSink != nil
            && ownedForwardingAuthorization.map {
                captureForwardingAuthorization === $0
            } == true
        // Claim and close the exact local attempt before the first suspension point. A timeout
        // that loses this race can no longer resume later and stop a newer Show/capture owner.
        cancelAutomaticScreenMediaResumeTimeout()
        automaticScreenMediaResumeContext = nil
        context.probeAuthorization?.revoke()
        context.forwardingAuthorization?.revoke()
        let logicalScreenIsStillRequested = peer === sourcePeer
            && peerGeneration == context.binding.peerGeneration
            && recoveryProofEpoch == context.binding.recoveryEpoch
            && screenVisibilityCommandEpoch
                == context.binding.visibilityCommandEpoch
            && screenMediaSuspension.activeScreenRequestID
                == context.notice.screenRequestID
        _ = screenMediaSuspension.rollbackFinalizationBeforeAcknowledgement(
            notice: context.notice,
            binding: context.binding
        )
        screenMediaSuspension.cancelResume(
            binding: context.binding,
            logicalScreenIsStillRequested: logicalScreenIsStillRequested
        )
        let failureDiagnostic = screenMediaSuspension.diagnosticSnapshot
        do {
            var updatedPolicy = screenVideoAdaptationPolicy
            updatedPolicy.automaticResumeAttemptFailed()
            screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        await sourcePeer.cancelScreenMediaResumeProbe(
            attemptID: attemptID,
            reason: reason
        )
        let diagnosticReason = String(
            reason
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(256)
        )
        logger.error(
            "Worldwide screen video resume failed "
                + "phase=\(failureDiagnostic.phase.rawValue) "
                + "screenRequestID="
                + (failureDiagnostic.screenRequestID.map(String.init) ?? "none")
                + " suspensionGeneration="
                + (failureDiagnostic.suspensionGeneration.map(String.init) ?? "none")
                + " logicalScreenIsStillRequested=\(logicalScreenIsStillRequested) "
                + "captureGenerationOwned=\(ownedCaptureIsCurrent) "
                + "reason=\(diagnosticReason)"
        )
        guard !logicalScreenIsStillRequested
                || screenMediaSuspension.isAutomaticallySuspended else {
            // A failed attempt may stay covered only while the exact suspension transcript can
            // drive another bounded retry. If that ownership disappeared, require reconnect and
            // a fresh ordered Show instead of leaving a logically visible viewer permanently dark.
            logger.error(
                "Worldwide screen resume lost covered ownership; closing the media generation "
                    + "for a fresh ordered Show"
            )
            await stop()
            return
        }
        guard ownedCaptureIsCurrent,
              let ownedSource,
              let ownedSink,
              let ownedForwardingAuthorization,
              captureSource === ownedSource,
              captureSink === ownedSink,
              captureForwardingAuthorization === ownedForwardingAuthorization else {
            return
        }
        guard await stopScreenCaptureOrCloseSession(
            context: "automatic screen-media resume failure"
        ) else {
            return
        }
        logger.info(
            "Worldwide screen video remained covered for a bounded retry after resume failure"
        )
    }

    private func handleAutomaticScreenMediaEncoderProbeEvent(
        _ event: ScreenVideoEncoderResumeProbeEvent,
        peer sourcePeer: WebRTCPeer,
        peerGeneration sourcePeerGeneration: UInt64
    ) async {
        guard peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              let context = automaticScreenMediaResumeContext else {
            return
        }
        switch event {
        case .markerEncoded(let proof):
            guard proof.attemptID == context.attemptID,
                  let boundary = context.boundary,
                  proof.boundaryRevision == boundary.revision,
                  let probeAuthorization = context.probeAuthorization else {
                await failAutomaticScreenMediaResume(
                    peer: sourcePeer,
                    attemptID: context.attemptID,
                    reason: "marker proof did not match its capture boundary"
                )
                return
            }
            let geometry = WebRTCScreenMediaGeometry(
                geometryRevision: boundary.revision,
                captureWidth: boundary.geometry.surfaceWidth,
                captureHeight: boundary.geometry.surfaceHeight
            )
            let ready = WebRTCScreenMediaMarkerReady(
                attemptID: proof.attemptID,
                screenRequestID: context.notice.screenRequestID,
                suspensionGeneration:
                    context.notice.suspensionGeneration,
                encoderGeneration: proof.encoderGeneration,
                encoderMarkerRTPTimestamp: proof.rtpTimestamp,
                boundaryRevision: proof.boundaryRevision,
                geometry: geometry
            )
            guard screenMediaSuspension.acceptMarkerReady(
                ready,
                binding: context.binding
            ) else {
                await failAutomaticScreenMediaResume(
                    peer: sourcePeer,
                    attemptID: context.attemptID,
                    reason: "marker-ready state was stale"
                )
                return
            }
            do {
                try await sourcePeer.sendScreenMediaMarkerReady(
                    ready,
                    authorization: probeAuthorization
                )
                guard peer === sourcePeer,
                      peerGeneration == sourcePeerGeneration,
                      screenMediaSuspension.owns(context.binding),
                      let forwardingAuthorization = context.forwardingAuthorization,
                      captureForwardingAuthorization === forwardingAuthorization,
                      forwardingAuthorization.isValid,
                      probeAuthorization.isValid,
                      var current = automaticScreenMediaResumeContext,
                      current.attemptID == context.attemptID,
                      current.binding == context.binding,
                      current.boundary == boundary,
                      current.markerReady == nil,
                      current.probeAuthorization === probeAuthorization,
                      current.forwardingAuthorization === forwardingAuthorization else {
                    throw WorldwideScreenServiceError.transportUnavailable
                }
                current.markerReady = ready
                automaticScreenMediaResumeContext = current
                // Treat the timeout as a no-progress deadline. A 32 kbps key frame may spend most
                // of one window reaching the viewer; real-frame recovery still needs its own
                // bounded window instead of inheriting only the marker's leftover time.
                scheduleAutomaticScreenMediaResumeTimeout(
                    attemptID: context.attemptID,
                    peerGeneration: sourcePeerGeneration
                )
            } catch {
                await failAutomaticScreenMediaResume(
                    peer: sourcePeer,
                    attemptID: context.attemptID,
                    reason: "marker-ready send failed: \(error.localizedDescription)"
                )
            }

        case .realFrameEncoded(let proof):
            guard proof.attemptID == context.attemptID,
                  let presentation = context.markerPresentation,
                  let probeAuthorization = context.probeAuthorization,
                  let receiverFloor = WebRTCScreenMediaResumeReady
                    .predictedReceiverRealFrameFloorRTPTimestamp(
                        markerPresentation: presentation,
                        encoderRealFrameRTPTimestamp: proof.rtpTimestamp
                    ) else {
                await failAutomaticScreenMediaResume(
                    peer: sourcePeer,
                    attemptID: context.attemptID,
                    reason: "real-frame proof could not translate its RTP floor"
                )
                return
            }
            let ready = WebRTCScreenMediaResumeReady(
                markerPresentation: presentation,
                encoderMarkerRTPTimestamp:
                    presentation.markerReady.encoderMarkerRTPTimestamp,
                encoderRealFrameRTPTimestamp: proof.rtpTimestamp,
                receiverMarkerRTPTimestamp:
                    presentation.receiverMarkerRTPTimestamp,
                receiverRealFrameFloorRTPTimestamp: receiverFloor,
                geometry: presentation.markerReady.geometry
            )
            guard proof.encoderGeneration == ready.encoderGeneration,
                  screenMediaSuspension.acceptResumeReady(
                    ready,
                    binding: context.binding
                  ) else {
                await failAutomaticScreenMediaResume(
                    peer: sourcePeer,
                    attemptID: context.attemptID,
                    reason: "resume-ready state was stale"
                )
                return
            }
            do {
                try await sourcePeer.sendScreenMediaResumeReady(
                    ready,
                    authorization: probeAuthorization
                )
                guard peer === sourcePeer,
                      peerGeneration == sourcePeerGeneration,
                      screenMediaSuspension.owns(context.binding),
                      let forwardingAuthorization = context.forwardingAuthorization,
                      captureForwardingAuthorization === forwardingAuthorization,
                      forwardingAuthorization.isValid,
                      probeAuthorization.isValid,
                      let current = automaticScreenMediaResumeContext,
                      current.attemptID == context.attemptID,
                      current.binding == context.binding,
                      current.markerPresentation == presentation,
                      current.probeAuthorization === probeAuthorization,
                      current.forwardingAuthorization === forwardingAuthorization else {
                    throw WorldwideScreenServiceError.transportUnavailable
                }
                scheduleAutomaticScreenMediaResumeTimeout(
                    attemptID: context.attemptID,
                    peerGeneration: sourcePeerGeneration
                )
            } catch {
                await failAutomaticScreenMediaResume(
                    peer: sourcePeer,
                    attemptID: context.attemptID,
                    reason: "resume-ready send failed: \(error.localizedDescription)"
                )
            }

        case .cancelled(let attemptID, let reason):
            guard attemptID == context.attemptID else { return }
            await failAutomaticScreenMediaResume(
                peer: sourcePeer,
                attemptID: attemptID,
                reason: reason
            )
        }
    }

    private func handleAutomaticScreenMediaMarkerPresentation(
        _ presentation: WebRTCScreenMediaMarkerPresentation,
        peer sourcePeer: WebRTCPeer,
        peerGeneration sourcePeerGeneration: UInt64
    ) async {
        guard peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              let context = automaticScreenMediaResumeContext,
              presentation.markerReady == context.markerReady,
              let source = captureSource,
              let sink = captureSink,
              let boundary = context.boundary,
              let probeAuthorization = context.probeAuthorization,
              let forwardingAuthorization = context.forwardingAuthorization,
              captureForwardingAuthorization === forwardingAuthorization,
              screenMediaSuspension.acceptMarkerPresentation(
                presentation,
                binding: context.binding
              ) else {
            if let context = automaticScreenMediaResumeContext {
                await failAutomaticScreenMediaResume(
                    peer: sourcePeer,
                    attemptID: context.attemptID,
                    reason: "marker presentation lost capture ownership"
                )
            }
            return
        }
        do {
            try await sourcePeer.beginScreenMediaRealFrameAdmission(
                authorization: probeAuthorization
            )
            guard peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration,
                  captureSource === source,
                  captureSink === sink,
                  captureForwardingAuthorization === forwardingAuthorization,
                  forwardingAuthorization.isValid,
                  probeAuthorization.isValid,
                  screenMediaSuspension.owns(context.binding),
                  let admittedContext = automaticScreenMediaResumeContext,
                  admittedContext.attemptID == context.attemptID,
                  admittedContext.binding == context.binding,
                  admittedContext.boundary == boundary,
                  admittedContext.markerReady == presentation.markerReady,
                  admittedContext.probeAuthorization === probeAuthorization,
                  admittedContext.forwardingAuthorization === forwardingAuthorization else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            let didArm = try await source.performSampleDeliveryBarrier {
                sink.armAutomaticResumeRealFrame(
                    boundary: boundary,
                    authorizedBy: forwardingAuthorization
                )
            }
            guard didArm,
                  peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration,
                  captureSource === source,
                  captureSink === sink,
                  captureForwardingAuthorization === forwardingAuthorization,
                  forwardingAuthorization.isValid,
                  probeAuthorization.isValid,
                  screenMediaSuspension.owns(context.binding),
                  let current = automaticScreenMediaResumeContext,
                  current.attemptID == context.attemptID,
                  current.binding == context.binding,
                  current.boundary == boundary,
                  current.markerReady == presentation.markerReady,
                  current.probeAuthorization === probeAuthorization,
                  current.forwardingAuthorization === forwardingAuthorization else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            var updatedContext = current
            updatedContext.markerPresentation = presentation
            automaticScreenMediaResumeContext = updatedContext
            scheduleAutomaticScreenMediaResumeTimeout(
                attemptID: context.attemptID,
                peerGeneration: sourcePeerGeneration
            )
        } catch {
            await failAutomaticScreenMediaResume(
                peer: sourcePeer,
                attemptID: context.attemptID,
                reason: "real-frame gate failed: \(error.localizedDescription)"
            )
        }
    }

    private func handleAutomaticScreenMediaResumeRequest(
        _ request: WebRTCScreenMediaResumeRequest,
        peer sourcePeer: WebRTCPeer,
        peerGeneration sourcePeerGeneration: UInt64
    ) async {
        guard peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              let context = automaticScreenMediaResumeContext,
              let sink = captureSink,
              let boundary = context.boundary,
              let probeAuthorization = context.probeAuthorization,
              let forwardingAuthorization = context.forwardingAuthorization,
              captureForwardingAuthorization === forwardingAuthorization,
              screenMediaSuspension.acceptResumeRequest(
                request,
                binding: context.binding
              ) else {
            if let context = automaticScreenMediaResumeContext {
                await failAutomaticScreenMediaResume(
                    peer: sourcePeer,
                    attemptID: context.attemptID,
                    reason: "resume request lost capture ownership"
                )
            }
            return
        }

        do {
            let resumeAuthorization = try await sourcePeer
                .issueScreenMediaResumeAuthorization(
                    for: request.id,
                    authorization: probeAuthorization
                )
            guard peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration,
                  captureSink === sink,
                  captureForwardingAuthorization === forwardingAuthorization,
                  forwardingAuthorization.isValid,
                  probeAuthorization.isValid,
                  screenMediaSuspension.authorizesFinalization(
                    of: request,
                    binding: context.binding
                  ),
                  let current = automaticScreenMediaResumeContext,
                  current.attemptID == context.attemptID,
                  current.binding == context.binding,
                  current.boundary == boundary,
                  current.markerPresentation == context.markerPresentation,
                  current.probeAuthorization === probeAuthorization,
                  current.forwardingAuthorization === forwardingAuthorization else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            let inputSession = armRemoteInputIfAvailable(
                screenRequestID: context.notice.screenRequestID,
                ownershipClaim: context.inputOwnershipClaim,
                initialFrameGeometry: boundary.geometry
            )
            // Retire the queued deadline before entering the atomic forwarding/ACK critical
            // section. Its generation fence also makes an already-awakened timeout a no-op.
            cancelAutomaticScreenMediaResumeTimeout()
            guard peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration,
                  captureSink === sink,
                  captureForwardingAuthorization === forwardingAuthorization,
                  forwardingAuthorization.isValid,
                  probeAuthorization.isValid,
                  automaticScreenMediaResumeContext?.attemptID == context.attemptID,
                  screenMediaSuspension.commitFinalization(
                    of: request,
                    binding: context.binding
                  ) else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            try await sourcePeer.acknowledgeScreenMediaResumedIfTransportHealthy(
                requestID: request.id,
                resumeAuthorization: resumeAuthorization,
                probeAuthorization: probeAuthorization,
                inputCapability: inputSession?.capability,
                inputAuthorization: inputSession?.authorization,
                withFinalAuthorizationCommit: { operation in
                    try sink.withAutomaticResumeCommitAuthorization(
                        boundary: boundary,
                        authorizedBy: forwardingAuthorization
                    ) {
                        try context.finalAcknowledgementCommit.commit {
                            guard let inputSession else {
                                try operation(false)
                                return false
                            }
                            return try remoteInputController
                                .withPreparedActivationCommit(
                                    inputSession.activation,
                                    operation: operation
                                )
                        }
                    }
                }
            )
            if let inputSession,
               !remoteInputController.isCommitted(inputSession.activation),
               activeInputCapability == inputSession.capability,
               activeInputAuthorization === inputSession.authorization {
                inputSession.authorization.revoke()
                activeInputCapability = nil
                activeInputAuthorization = nil
            }
        } catch {
            await failAutomaticScreenMediaResume(
                peer: sourcePeer,
                attemptID: context.attemptID,
                reason: "resume finalization failed: \(error.localizedDescription)"
            )
            return
        }

        // The ACK is irreversible and already atomically bound to this sink generation. A newer
        // lifecycle may nevertheless have taken ownership immediately afterward; in that case its
        // cleanup remains authoritative and this completed older task must not mutate it.
        guard !isStopped,
              let currentPeer = peer,
              currentPeer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              context.binding.peerGeneration == sourcePeerGeneration,
              screenVisibilityCommandEpoch == context.binding.visibilityCommandEpoch,
              recoveryProofEpoch == context.binding.recoveryEpoch,
              let activeScreenRequestID = screenMediaSuspension.activeScreenRequestID,
              activeScreenRequestID == context.notice.screenRequestID,
              let currentSink = captureSink,
              currentSink === sink,
              let currentForwarding = captureForwardingAuthorization,
              currentForwarding === forwardingAuthorization,
              let completed = automaticScreenMediaResumeContext,
              completed.attemptID == context.attemptID,
              completed.binding == context.binding,
              completed.notice == context.notice,
              completed.finalAcknowledgementCommit === context.finalAcknowledgementCommit,
              completed.finalAcknowledgementCommit.isCommitted,
              let completedBoundary = completed.boundary,
              completedBoundary == boundary,
              completed.markerReady == context.markerReady,
              completed.markerPresentation == context.markerPresentation,
              let completedProbe = completed.probeAuthorization,
              completedProbe === probeAuthorization,
              let completedForwarding = completed.forwardingAuthorization,
              completedForwarding === forwardingAuthorization,
              screenMediaSuspension.owns(context.binding) else {
            return
        }

        // Consume success only after the original committed attempt is still owned. Use the
        // current tuple: a route event during the ACK await may have advanced its revision and
        // cleared evidence. Probe revocation is expected after ACK; forwarding can also be
        // retired by a display callback before its actor-owned rebuild runs.
        do {
            var updatedPolicy = screenVideoAdaptationPolicy
            updatedPolicy.automaticResumeAttemptSucceeded()
            screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)

        let recommendation = screenVideoAdaptationPolicy.currentRecommendation
        guard let source = captureSource,
              let captureAuthorization,
              let capturer = sourcePeer.externalVideoCapturer,
              let baseDimensions = captureVideoBaseDimensions else {
            beginPostResumeScreenVideoAdaptationEpoch()
            automaticScreenMediaResumeContext = nil
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: nil)
            logger.info("Worldwide screen video resumed after exact receiver presentation")
            return
        }
        do {
            let senderUpdate = try await sourcePeer.applyScreenVideoEncodingLimits(
                recommendation.webRTCLimits
            )
            guard peer === sourcePeer,
                  peerGeneration == sourcePeerGeneration,
                  let finalizing = automaticScreenMediaResumeContext,
                  finalizing.attemptID == context.attemptID,
                  finalizing.binding == context.binding,
                  finalizing.boundary == boundary,
                  captureSource === source,
                  captureSink === sink,
                  self.captureAuthorization === captureAuthorization,
                  captureForwardingAuthorization === forwardingAuthorization,
                  captureAuthorization.isValid,
                  forwardingAuthorization.isValid,
                  sink.allowsActiveUse(authorizedBy: forwardingAuthorization),
                  captureVideoBaseDimensions == baseDimensions,
                  screenMediaSuspension.owns(context.binding) else {
                _ = try? await sourcePeer
                    .rollbackScreenVideoEncodingUpdateIfCurrent(senderUpdate)
                if let current = automaticScreenMediaResumeContext,
                   current.attemptID == context.attemptID,
                   current.binding == context.binding {
                    beginPostResumeScreenVideoAdaptationEpoch()
                    automaticScreenMediaResumeContext = nil
                }
                return
            }
            capturer.adaptOutput(
                width: Int32(baseDimensions.width),
                height: Int32(baseDimensions.height),
                framesPerSecond: Int32(
                    recommendation.maximumFramesPerSecond
                )
            )
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: recommendation)
            beginPostResumeScreenVideoAdaptationEpoch()
            automaticScreenMediaResumeContext = nil
        } catch {
            // The typed resume already committed. Keep the safe probe ceiling and let the next
            // statistics sample retry ordinary adaptation without hiding the screen.
            if let current = automaticScreenMediaResumeContext,
               current.attemptID == context.attemptID,
               current.binding == context.binding {
                beginPostResumeScreenVideoAdaptationEpoch()
                automaticScreenMediaResumeContext = nil
            }
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: nil)
            logger.error(
                "Worldwide screen resumed with its probe ceiling: "
                    + error.localizedDescription
            )
        }
        logger.info("Worldwide screen video resumed after exact receiver presentation")
    }

    // MARK: - Screen control protocol

    private var currentScreenMediaSuspensionBinding:
        WorldwideScreenMediaSuspensionCoordinator.Binding {
        WorldwideScreenMediaSuspensionCoordinator.Binding(
            peerGeneration: peerGeneration,
            visibilityCommandEpoch: screenVisibilityCommandEpoch,
            recoveryEpoch: recoveryProofEpoch
        )
    }

    private func resetAutomaticScreenMediaSuspensionState() {
        cancelAutomaticScreenMediaResumeTimeout()
        if let context = automaticScreenMediaResumeContext {
            if context.finalAcknowledgementCommit.claimFailure() {
                do {
                    var updatedPolicy = screenVideoAdaptationPolicy
                    updatedPolicy.automaticResumeAttemptFailed()
                    screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                        revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            } else {
                do {
                    var updatedPolicy = screenVideoAdaptationPolicy
                    updatedPolicy.automaticResumeAttemptSucceeded()
                    screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                        revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
                beginPostResumeScreenVideoAdaptationEpoch()
            }
        }
        retireAutomaticScreenMediaResumeNativeContext()
    }

    private func retireAutomaticScreenMediaResumeNativeContext() {
        automaticScreenMediaResumeContext?.probeAuthorization?.revoke()
        automaticScreenMediaResumeContext?.forwardingAuthorization?.revoke()
        automaticScreenMediaResumeContext = nil
        screenMediaSuspension.retire()
    }

    private func resetScreenClientDiagnosticsFreshness() {
        lastScreenClientDiagnosticsReceiptUptime = nil
        lastScreenClientDiagnosticsSequence = nil
        lastScreenClientDiagnosticsScreenRequestID = nil
        screenClientDiagnosticsExpectedScreenRequestID = nil
        screenClientDiagnosticsExpectationStartedUptime = nil
        screenClientDiagnosticsSilenceWasReported = false
    }

    private func activateAutomaticScreenMediaSuspensionOwnership(
        screenRequestID: UInt64
    ) {
        _ = screenMediaSuspension.activate(
            screenRequestID: screenRequestID,
            binding: currentScreenMediaSuspensionBinding
        )
    }

    /// Linearizes Show, Hide, and key-frame requests with native capture state.
    ///
    /// Active is acknowledged only after capture and transport health are proven. Inactive
    /// is acknowledged only after native stop succeeds; every uncertainty path revokes media.
    private func handleControlRequest(_ request: WebRTCControlRequest) async {
        guard let peer else {
            do {
                var updatedPolicy = screenVideoAdaptationPolicy
                updatedPolicy.endFloorRecoveryVisibility()
                screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            }
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            _ = await stopScreenCaptureOrCloseSession(
                context: "a control request arrived without a peer"
            )
            return
        }

        let inputOwnershipClaim: MacRemoteInputOwnershipClaim?
        if request.command == .showScreen {
            let claim = remoteInputController.reserveOwnershipClaim(
                for: remoteInputOwnerToken
            )
            latestShowInputOwnershipClaim = claim
            inputOwnershipClaim = claim
        } else {
            inputOwnershipClaim = nil
        }

        if request.command != .requestKeyFrame {
            screenVisibilityCommandEpoch &+= 1
            if screenVisibilityCommandEpoch == 0 {
                screenVisibilityCommandEpoch = 1
            }
            if request.command == .showScreen {
                do {
                    var updatedPolicy = screenVideoAdaptationPolicy
                    updatedPolicy.beginFloorRecoveryVisibility(
                        peerGeneration: peerGeneration,
                        showEpoch: screenVisibilityCommandEpoch
                    )
                    screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                        revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
            } else {
                do {
                    var updatedPolicy = screenVideoAdaptationPolicy
                    updatedPolicy.endFloorRecoveryVisibility()
                    screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                        revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
            }
            screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            // Visibility commands own the serial control lane immediately. A deferred key-frame
            // acknowledgement must yield before Hide stops capture or Show starts a new generation.
            keyFrameControlTask?.cancel()
            keyFrameControlTask = nil
        }
        let visibilityCommandEpoch = screenVisibilityCommandEpoch
        let visibilityPeerGeneration = peerGeneration

        if request.command == .showScreen,
           screenMediaSuspension.activeScreenRequestID != nil {
            await peer.cancelScreenMediaSuspension(
                reason: "A newer ordinary Show replaced automatic screen suspension."
            )
            resetAutomaticScreenMediaSuspensionState()
            guard await stopScreenCaptureOrCloseSession(
                context: "a newer ordinary Show replaced automatic screen suspension"
            ) else {
                return
            }
        }

        if recoveryProofRequired,
           request.command != .hideScreen,
           let pendingRecoveryProofRequest,
           request.id > pendingRecoveryProofRequest.id {
            // WebRTCPeer only permits the highest received request to be acknowledged.
            // A later non-Hide therefore makes an older proof request unusable.
            self.pendingRecoveryProofRequest = nil
        }

        switch request.command {
        case .showScreen:
            do {
                guard transportAllowsCapture else {
                    throw WorldwideScreenServiceError.transportUnavailable
                }
                let authorization = try await startScreenCaptureWithDisplayModeRetries()
                guard captureSource != nil,
                      let sink = captureSink,
                      captureAuthorization?.isValid == true,
                      captureForwardingAuthorization === authorization,
                      sink.allowsActiveUse(authorizedBy: authorization),
                      authorization.isValid,
                      transportAllowsCapture else {
                    throw WorldwideScreenServiceError.transportUnavailable
                }
                let inputSession = armRemoteInputIfAvailable(
                    screenRequestID: request.id,
                    ownershipClaim: inputOwnershipClaim,
                    initialFrameGeometry: sink.remoteInputStartupGeometry(
                        authorizedBy: authorization
                    )
                )
                let authorizationPeerGeneration = peerGeneration
                let authorizationRecoveryEpoch = recoveryProofEpoch
                // The viewer may say "Screen live" only after ScreenCaptureKit has actually
                // started. The revocable token linearizes recovery/capture-stop against the
                // final native-health check, track enable, and Active ACK send.
                try await peer.acknowledgeActiveControlRequestIfTransportHealthy(
                    id: request.id,
                    authorization: authorization,
                    inputCapability: inputSession?.capability,
                    inputAuthorization: inputSession?.authorization,
                    finalAuthorizationCheck: {
                        sink.allowsActiveUseWhileAuthorizationHeld(authorization)
                    },
                    withFinalInputOwnershipCommit: { operation in
                        guard let inputSession else {
                            try operation(false)
                            return false
                        }
                        return try remoteInputController
                            .withPreparedActivationCommit(
                                inputSession.activation,
                                operation: operation
                            )
                    }
                )
                if let inputSession,
                   !remoteInputController.isCommitted(inputSession.activation),
                   activeInputCapability == inputSession.capability,
                   activeInputAuthorization === inputSession.authorization {
                    inputSession.authorization.revoke()
                    activeInputCapability = nil
                    activeInputAuthorization = nil
                }
                let inputSessionRemainsCurrent =
                    Self.activeAcknowledgementInputStateIsCurrent(
                        preparedCapability: inputSession?.capability,
                        preparedAuthorization: inputSession?.authorization,
                        activeCapability: activeInputCapability,
                        activeAuthorization: activeInputAuthorization,
                        preparedActivationIsCommitted: inputSession.map {
                            remoteInputController.isCommitted($0.activation)
                        } ?? false
                    )
                let acknowledgementSessionIsCurrent =
                    authorizationPeerGeneration == peerGeneration
                        && authorizationRecoveryEpoch == recoveryProofEpoch
                        && self.peer === peer
                        && inputSessionRemainsCurrent
                        && transportAllowsCapture
                let captureTransitionIsOwned = screenCaptureTransitionIsOwned
                guard acknowledgementSessionIsCurrent,
                      captureTransitionIsOwned else {
                    // The Active transition linearized before a newer uncertainty boundary.
                    // Stop immediately and never send a contradictory ACK for the same ID.
                    if self.peer === peer,
                       peerGeneration == visibilityPeerGeneration,
                       screenVisibilityCommandEpoch == visibilityCommandEpoch {
                        do {
                            var updatedPolicy = screenVideoAdaptationPolicy
                            updatedPolicy.endFloorRecoveryVisibility()
                            screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                        }
                        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                            revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                    }
                    _ = await stopScreenCaptureOrCloseSession(
                        context: "screen authorization changed during Active acknowledgement"
                    )
                    await peer.suspendScreenMediaForTransportUncertainty()
                    logger.error("Worldwide screen authorization changed during Active acknowledgement")
                    return
                }
                if self.peer === peer,
                   peerGeneration == visibilityPeerGeneration,
                   screenVisibilityCommandEpoch == visibilityCommandEpoch {
                    do {
                        var updatedPolicy = screenVideoAdaptationPolicy
                        updatedPolicy.activateFloorRecoveryVisibility(
                            peerGeneration: visibilityPeerGeneration,
                            showEpoch: visibilityCommandEpoch
                        )
                        screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                    }
                    screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                        revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
                activateAutomaticScreenMediaSuspensionOwnership(
                    screenRequestID: request.id
                )
            } catch {
                if self.peer === peer,
                   peerGeneration == visibilityPeerGeneration,
                   screenVisibilityCommandEpoch == visibilityCommandEpoch {
                    do {
                        var updatedPolicy = screenVideoAdaptationPolicy
                        updatedPolicy.endFloorRecoveryVisibility()
                        screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                            revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                    }
                    screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                        revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
                screenMediaSuspension.retire()
                if isNativeScreenStopFailure(error) {
                    logger.error(
                        "Worldwide screen Show could not verify native capture shutdown: " +
                        error.localizedDescription
                    )
                    await stop()
                } else {
                    _ = await acknowledgeInactiveAfterVerifiedScreenStop(
                        peer: peer,
                        requestID: request.id,
                        context: "screen Show failed before Active acknowledgement"
                    )
                }
                logger.error("Worldwide screen Show failed closed: \(error.localizedDescription)")
            }

        case .hideScreen:
            logger.debug(
                "Worldwide screen visibility command=hide "
                    + "requestID=\(request.id) peerGeneration=\(peerGeneration) "
                    + "hostPID=\(ProcessInfo.processInfo.processIdentifier)"
            )
            // Hide and a new Show can complete between statistics polls. Retire old RTT health
            // and in-flight reports synchronously, without resetting the native watermark.
            do {
                var updatedPolicy = screenVideoAdaptationPolicy
                updatedPolicy.invalidateRoundTripTimeObservation()
                screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
            }
            beginPostResumeScreenVideoAdaptationEpoch()
            if recoveryProofRequired {
                let proofRequest = PendingRecoveryProofRequest(
                    id: request.id,
                    epoch: recoveryProofEpoch
                )
                if pendingRecoveryProofRequest.map({ request.id > $0.id }) != false {
                    pendingRecoveryProofRequest = proofRequest
                }
                guard await stopScreenCaptureOrCloseSession(
                    context: "recovery-proof Hide"
                ) else {
                    return
                }
                await completePendingRecoveryProofIfPossible(
                    peer: peer,
                    epoch: proofRequest.epoch
                )
                return
            }

            if screenMediaSuspension.suspensionIsInFlight,
               let notice = screenMediaSuspension.currentSuspensionNotice {
                let didStop = await acknowledgeInactiveAfterVerifiedScreenStop(
                    peer: peer,
                    requestID: request.id,
                    context: "automatic weak-network screen suspension"
                )
                guard didStop else {
                    await peer.cancelScreenMediaSuspension(
                        reason: "Automatic screen suspension could not prove Inactive."
                    )
                    resetAutomaticScreenMediaSuspensionState()
                    return
                }
                guard screenMediaSuspension.confirmInactive(
                    for: notice,
                    binding: currentScreenMediaSuspensionBinding
                ) else {
                    await peer.cancelScreenMediaSuspension(
                        reason: "Automatic screen suspension lost its Hide ownership."
                    )
                    resetAutomaticScreenMediaSuspensionState()
                    return
                }
                logger.info("Worldwide screen video paused to preserve audio latency")
                return
            }

            if screenMediaSuspension.activeScreenRequestID != nil {
                await peer.cancelScreenMediaSuspension(
                    reason: "An ordinary Hide retired automatic screen suspension."
                )
                resetAutomaticScreenMediaSuspensionState()
            }

            _ = await acknowledgeInactiveAfterVerifiedScreenStop(
                peer: peer,
                requestID: request.id,
                context: "screen Hide"
            )

        case .requestKeyFrame:
            if let context = automaticScreenMediaResumeContext {
                await failAutomaticScreenMediaResume(
                    peer: peer,
                    attemptID: context.attemptID,
                    reason: "an ordinary key-frame request interrupted the resume proof"
                )
            }
            // RTP feedback remains WebRTC-owned; acknowledge the screen state without reusing a
            // VideoToolbox frame from the legacy path. This retry must not occupy the sole serial
            // peer-event consumer: a later Hide, Show, or transport failure has to run immediately.
            let requestPeerGeneration = peerGeneration
            let requestRecoveryEpoch = recoveryProofEpoch
            keyFrameControlTask?.cancel()
            keyFrameControlTask = Task { [weak self] in
                await self?.handleKeyFrameRequest(
                    request,
                    peer: peer,
                    peerGeneration: requestPeerGeneration,
                    recoveryEpoch: requestRecoveryEpoch
                )
            }
        }
    }

    /// Re-evaluates an exact forwarding token across a bounded live display transition. Running in
    /// its own task keeps the ordered peer event stream free to process a newer Hide/Show or route
    /// failure, which cancels or invalidates this older request before it can affect new capture.
    private func handleKeyFrameRequest(
        _ request: WebRTCControlRequest,
        peer: WebRTCPeer,
        peerGeneration requestPeerGeneration: UInt64,
        recoveryEpoch requestRecoveryEpoch: UInt64
    ) async {
        for attempt in 0..<600 {
            guard !Task.isCancelled,
                  self.peer === peer,
                  requestPeerGeneration == peerGeneration,
                  requestRecoveryEpoch == recoveryProofEpoch else {
                return
            }

            if captureSource != nil,
               let sink = captureSink,
               captureAuthorization?.isValid == true,
               let authorization = captureForwardingAuthorization,
               sink.allowsActiveUse(authorizedBy: authorization),
               authorization.isValid,
               transportAllowsCapture {
                do {
                    try await peer.acknowledgeControlRequestIfTransportHealthy(
                        id: request.id,
                        state: .active,
                        authorization: authorization,
                        finalAuthorizationCheck: {
                            sink.allowsActiveUseWhileAuthorizationHeld(authorization)
                        }
                    )
                    // The acknowledgement was linearized against this exact forwarding token.
                    // Any state observed after the await belongs to the same owned transition or
                    // to a newer request, so this older key-frame command must not stop it.
                    return
                } catch {
                    if Self.isSupersededScreenControlRequest(error) {
                        return
                    }
                    if Self.isRevokedScreenControlAuthorization(error),
                       screenCaptureTransitionIsOwned,
                       attempt < 599 {
                        try? await Task.sleep(for: .milliseconds(25))
                        continue
                    }
                    guard !Task.isCancelled,
                          self.peer === peer,
                          requestPeerGeneration == peerGeneration,
                          requestRecoveryEpoch == recoveryProofEpoch else {
                        return
                    }
                    _ = await acknowledgeInactiveAfterVerifiedScreenStop(
                        peer: peer,
                        requestID: request.id,
                        context: "key-frame request failed before Active acknowledgement"
                    )
                    guard !Task.isCancelled,
                          self.peer === peer,
                          requestPeerGeneration == peerGeneration,
                          requestRecoveryEpoch == recoveryProofEpoch else {
                        return
                    }
                    await peer.suspendScreenMediaForTransportUncertainty()
                    logger.error(
                        "Worldwide key-frame acknowledgement failed: " +
                            error.localizedDescription
                    )
                    return
                }
            }

            if captureSource == nil {
                do {
                    try await peer.acknowledgeControlRequest(
                        id: request.id,
                        state: .inactive
                    )
                } catch {
                    if !Self.isSupersededScreenControlRequest(error) {
                        logger.error(
                            "Worldwide key-frame acknowledgement failed: " +
                                error.localizedDescription
                        )
                    }
                }
                return
            }

            if screenCaptureTransitionIsOwned,
               attempt < 599 {
                try? await Task.sleep(for: .milliseconds(25))
                continue
            }

            guard !Task.isCancelled else { return }
            _ = await acknowledgeInactiveAfterVerifiedScreenStop(
                peer: peer,
                requestID: request.id,
                context: "key-frame request during screen format renegotiation"
            )
            guard !Task.isCancelled,
                  self.peer === peer,
                  requestPeerGeneration == peerGeneration,
                  requestRecoveryEpoch == recoveryProofEpoch else {
                return
            }
            await peer.suspendScreenMediaForTransportUncertainty()
            return
        }
    }

    /// Stops native screen capture before sending the matching Inactive acknowledgement.
    @discardableResult
    private func acknowledgeInactiveAfterVerifiedScreenStop(
        peer: WebRTCPeer,
        requestID: UInt64,
        context: String
    ) async -> Bool {
        let failure = await WorldwideScreenInactiveTransition.perform(
            stopNativeCapture: {
                try await self.stopScreenCapture()
            },
            acknowledgeInactive: {
                try await peer.acknowledgeControlRequest(
                    id: requestID,
                    state: .inactive
                )
            },
            failClosed: { error in
                self.logger.error(
                    "Worldwide native screen stop failed during \(context); " +
                    "closing the peer/session without an Inactive acknowledgement: " +
                    error.localizedDescription
                )
                await self.stop()
            }
        )

        guard let failure else { return true }
        switch failure {
        case .nativeStop:
            // The fail-closed closure has already closed the peer and rendezvous.
            return false
        case .acknowledgement(let error):
            logger.error(
                "Worldwide screen Inactive acknowledgement failed during \(context): " +
                error.localizedDescription
            )
            return false
        }
    }

    /// Stops capture or closes the whole session if native shutdown cannot be proven.
    @discardableResult
    private func stopScreenCaptureOrCloseSession(context: String) async -> Bool {
        do {
            try await stopScreenCapture()
            return true
        } catch {
            logger.error(
                "Worldwide native screen stop failed during \(context); " +
                "closing the peer/session: " + error.localizedDescription
            )
            await stop()
            return false
        }
    }

    /// Distinguishes native-stop uncertainty from ordinary Show startup failures.
    private func isNativeScreenStopFailure(_ error: any Error) -> Bool {
        guard let serviceError = error as? WorldwideScreenServiceError else {
            return false
        }
        if case .nativeScreenStopFailed = serviceError {
            return true
        }
        return false
    }

    // MARK: - Remote input

    /// A superseded prepared owner is a successful view-only Active transition, not a screen
    /// failure. If input was published, however, every local identity and the controller commit
    /// must still match exactly before the service keeps that capability alive.
    nonisolated static func activeAcknowledgementInputStateIsCurrent(
        preparedCapability: WebRTCInputCapability?,
        preparedAuthorization: WebRTCInputAuthorization?,
        activeCapability: WebRTCInputCapability?,
        activeAuthorization: WebRTCInputAuthorization?,
        preparedActivationIsCommitted: Bool
    ) -> Bool {
        if activeCapability == nil, activeAuthorization == nil {
            return true
        }
        guard preparedActivationIsCommitted,
              let preparedCapability,
              let preparedAuthorization,
              activeCapability == preparedCapability,
              activeAuthorization === preparedAuthorization,
              preparedAuthorization.isValid else {
            return false
        }
        return true
    }

    /// Binds an input capability to the active display and exact Show request.
    private func armRemoteInputIfAvailable(
        screenRequestID: UInt64,
        ownershipClaim: MacRemoteInputOwnershipClaim?,
        initialFrameGeometry: ScreenVideoFrameGeometry?
    ) -> ArmedRemoteInputSession? {
        revokeRemoteInputAuthorization()
        guard let captureDisplayID,
              let ownershipClaim else {
            return nil
        }

        let inputSessionID = UUID()
        let authorization = WebRTCInputAuthorization()
        let capability = Self.remoteInputCapability(
            inputSessionID: inputSessionID,
            screenRequestID: screenRequestID
        )
        switch remoteInputController.prepareArm(
            displayID: captureDisplayID,
            screenRequestID: screenRequestID,
            inputSessionID: inputSessionID,
            ownerToken: remoteInputOwnerToken,
            ownershipClaim: ownershipClaim,
            initialFrameGeometry: initialFrameGeometry,
            authoritativeDisplayBounds: captureAuthoritativeDisplayBounds,
            supportsFocusedWindowResizeScaleRebinding:
                capability.supportsFocusedWindowResizeScaleRebinding,
            revokeAuthorization: {
                authorization.revoke()
            }
        ) {
        case .prepared(let activation):
            activeInputCapability = capability
            activeInputAuthorization = authorization
            logger.info("Worldwide remote input is prepared for this screen session")
            return ArmedRemoteInputSession(
                capability: capability,
                authorization: authorization,
                activation: activation
            )

        case .superseded:
            authorization.revoke()
            logger.info(
                "Worldwide remote input remains inactive because a newer viewer owns control"
            )
            return nil

        case .disabled:
            authorization.revoke()
            return nil

        case .permissionRequired(let status):
            authorization.revoke()
            logger.info(
                "Worldwide remote input remains view-only; Accessibility trusted=" +
                "\(status.accessibilityTrusted), event posting allowed=\(status.postEventAllowed)"
            )
            return nil

        case .displayUnavailable:
            authorization.revoke()
            logger.error("Worldwide remote input could not bind the captured display")
            return nil
        }
    }

    /// Injects one request under revocable gates, then returns content-free feedback.
    private func handleRemoteInputRequest(
        _ request: WebRTCInputRequest,
        authorization: WebRTCInputAuthorization
    ) async {
        guard let sourcePeer = peer else {
            revokeRemoteInputAuthorization()
            return
        }
        let sourcePeerGeneration = peerGeneration
        let sourceCapability = activeInputCapability

        // Keep both revocable gates held through controller validation and OS event injection.
        // The lock order is always input then capture. The first suspension is the feedback send
        // below, after the irreversible operation has either completed or been rejected.
        let inputOutcome = injectRemoteInputIfAuthorized(
            request,
            authorization: authorization
        )
        let formatDiagnostic = Self.remoteInputFormatDiagnostic(
            viewerVideoSize: request.viewerVideoSize,
            outcome: inputOutcome
        )
        logger.debug(
            "Worldwide remote input \(Self.remoteInputDiagnosticName(for: request.action)): " +
            diagnosticName(for: inputOutcome.result) +
            (formatDiagnostic.map { " \($0)" } ?? "")
        )

        let feedback = transportFeedback(for: inputOutcome)
        if feedback.revokesSession {
            revokeRemoteInputAuthorization()
        }

        do {
            try await sourcePeer.sendInputFeedback(
                for: request.id,
                result: feedback.result,
                rejectionReason: feedback.rejectionReason,
                screenFormatChanging: feedback.screenFormatChanging,
                focus: feedback.focus,
                windowResize: feedback.windowResize,
                windowMove: feedback.windowMove
            )
        } catch {
            // A delayed send failure from an old peer must never revoke a newer session.
            if peer === sourcePeer,
               peerGeneration == sourcePeerGeneration,
               activeInputAuthorization === authorization,
               activeInputCapability == sourceCapability {
                revokeRemoteInputAuthorization()
            }
            // Never include action payloads or typed text in diagnostics.
            logger.error("Worldwide remote-input feedback failed: \(error.localizedDescription)")
        }
    }

    /// Holds input, capture, then the exact forwarding authorization across the irreversible OS
    /// event post. The forwarding token is acquired before the sink lock, matching every other
    /// token-to-sink call site; sink transitions detach under lock and revoke only after unlock.
    private func injectRemoteInputIfAuthorized(
        _ request: WebRTCInputRequest,
        authorization: WebRTCInputAuthorization
    ) -> WorldwideRemoteInputInjectionOutcome {
        guard let capability = activeInputCapability,
              let expectedInputAuthorization = activeInputAuthorization,
              expectedInputAuthorization === authorization,
              capability.screenRequestID == request.screenRequestID,
              capability.inputSessionID == request.inputSessionID,
              transportAllowsCapture else {
            return WorldwideRemoteInputInjectionOutcome(.rejected(.staleSession))
        }
        guard Self.remoteInputActionIsSupported(request.action, capability: capability) else {
            return WorldwideRemoteInputInjectionOutcome(.rejected(.staleSession))
        }
        guard
              captureDisplayID != nil,
              captureSource != nil,
              let expectedCaptureAuthorization = captureAuthorization,
              let expectedForwardingAuthorization = captureForwardingAuthorization,
              captureSink?.allowsActiveUse(
                  authorizedBy: expectedForwardingAuthorization
              ) == true
        else {
            return remoteInputCaptureUnavailableResult()
        }

        do {
            let result: WorldwideRemoteInputInjectionOutcome? =
                try authorization.withValidAuthorization {
                try expectedCaptureAuthorization.withValidAuthorization {
                    try expectedForwardingAuthorization.withValidAuthorization {
                        guard activeInputAuthorization === authorization,
                              activeInputCapability == capability,
                              captureAuthorization === expectedCaptureAuthorization,
                              captureForwardingAuthorization ===
                                  expectedForwardingAuthorization,
                              captureSink?.allowsActiveUseWhileAuthorizationHeld(
                                  expectedForwardingAuthorization
                              ) == true,
                              captureSource != nil,
                              captureDisplayID != nil,
                              transportAllowsCapture else {
                            return nil
                        }
                        return injectRemoteInput(request)
                    }
                }
            }
            // Classify a transition only after every nonrecursive authorization lock is released.
            return result ?? remoteInputCaptureUnavailableResult()
        } catch {
            guard authorization.isValid,
                  activeInputAuthorization === authorization,
                  activeInputCapability == capability else {
                return WorldwideRemoteInputInjectionOutcome(.rejected(.staleSession))
            }
            return remoteInputCaptureUnavailableResult()
        }
    }

    /// A live, actor-owned display rebuild is a dropped input action, not a stale Show session.
    /// Keeping the input capability armed lets the next gesture use the replacement frame.
    private func remoteInputCaptureUnavailableResult() -> WorldwideRemoteInputInjectionOutcome {
        guard screenCaptureTransitionIsOwned else {
            return WorldwideRemoteInputInjectionOutcome(.rejected(.staleSession))
        }
        return WorldwideRemoteInputInjectionOutcome(
            .rejected(.screenFormatChanging),
            formatOrigin: .captureGateUnavailable(
                captureSink?.remoteInputFormatDiagnosticSnapshot()
            )
        )
    }

    /// Maps validated wire actions onto the narrow macOS input controller surface.
    private func injectRemoteInput(
        _ request: WebRTCInputRequest
    ) -> WorldwideRemoteInputInjectionOutcome {
        switch request.action {
        case .tap(let point):
            WorldwideRemoteInputInjectionOutcome(
                remoteInputController.handleTapWithDiagnostics(
                    screenRequestID: request.screenRequestID,
                    inputSessionID: request.inputSessionID,
                    normalizedPoint: .init(x: point.x, y: point.y),
                    viewerVideoSize: request.viewerVideoSize.map {
                        .init(width: $0.width, height: $0.height)
                    }
                )
            )

        case .primaryDrag(let start, let end):
            WorldwideRemoteInputInjectionOutcome(
                remoteInputController.handlePrimaryDragWithDiagnostics(
                    screenRequestID: request.screenRequestID,
                    inputSessionID: request.inputSessionID,
                    start: .init(x: start.x, y: start.y),
                    end: .init(x: end.x, y: end.y),
                    viewerVideoSize: request.viewerVideoSize.map {
                        .init(width: $0.width, height: $0.height)
                    }
                )
            )

        case .scroll(let anchor, let deltaX, let deltaY):
            WorldwideRemoteInputInjectionOutcome(
                remoteInputController.handleScrollWithDiagnostics(
                    screenRequestID: request.screenRequestID,
                    inputSessionID: request.inputSessionID,
                    anchor: .init(x: anchor.x, y: anchor.y),
                    deltaX: deltaX,
                    deltaY: deltaY,
                    viewerVideoSize: request.viewerVideoSize.map {
                        .init(width: $0.width, height: $0.height)
                    }
                )
            )

        case .requestFocusedWindowResizeTarget,
             .selectWindowForResize,
             .commitFocusedWindowResize:
            WorldwideFocusedWindowResizeDispatcher.dispatch(
                request,
                to: remoteInputController
            ) ?? WorldwideRemoteInputInjectionOutcome(.rejected(.invalidPoint))

        case .requestFocusedWindowMoveTarget, .selectWindowForMove, .commitFocusedWindowMove:
            WorldwideFocusedWindowMoveDispatcher.dispatch(
                request, to: remoteInputController
            ) ?? WorldwideRemoteInputInjectionOutcome(.rejected(.invalidPoint))

        case .insertText(let text, let focusGeneration):
            WorldwideRemoteInputInjectionOutcome(
                remoteInputController.insertText(
                    screenRequestID: request.screenRequestID,
                    inputSessionID: request.inputSessionID,
                    focusGeneration: focusGeneration,
                    text: text
                )
            )

        case .backspace(let focusGeneration):
            WorldwideRemoteInputInjectionOutcome(
                remoteInputController.pressKey(
                    screenRequestID: request.screenRequestID,
                    inputSessionID: request.inputSessionID,
                    focusGeneration: focusGeneration,
                    key: .backspace
                )
            )

        case .returnKey(let focusGeneration):
            WorldwideRemoteInputInjectionOutcome(
                remoteInputController.pressKey(
                    screenRequestID: request.screenRequestID,
                    inputSessionID: request.inputSessionID,
                    focusGeneration: focusGeneration,
                    key: .returnKey
                )
            )
        }
    }

    /// Verbose acceptance diagnostics deliberately contain neither text payloads nor field data.
    nonisolated static func remoteInputDiagnosticName(for action: WebRTCInputAction) -> String {
        switch action {
        case .tap:
            return "tap"
        case .primaryDrag:
            return "primary-drag"
        case .scroll:
            return "scroll"
        case .requestFocusedWindowResizeTarget:
            return "focused-window-target"
        case .selectWindowForResize:
            return "focused-window-selection"
        case .commitFocusedWindowResize:
            return "focused-window-resize-commit"
        case .requestFocusedWindowMoveTarget:
            return "focused-window-move-target"
        case .selectWindowForMove:
            return "focused-window-move-selection"
        case .commitFocusedWindowMove:
            return "focused-window-move-commit"
        case .insertText:
            return "committed-text"
        case .backspace:
            return "backspace"
        case .returnKey:
            return "return"
        }
    }

    /// Keeps additive input actions behind the exact capability acknowledged to the viewer.
    nonisolated static func remoteInputActionIsSupported(
        _ action: WebRTCInputAction,
        capability: WebRTCInputCapability
    ) -> Bool {
        switch action {
        case .primaryDrag:
            capability.supportsPrimaryDrag
        case .scroll:
            capability.supportsScroll
        case .requestFocusedWindowResizeTarget,
             .selectWindowForResize,
             .commitFocusedWindowResize:
            capability.supportsFocusedWindowResize
        case .requestFocusedWindowMoveTarget, .selectWindowForMove:
            capability.supportsFocusedWindowMove
        case .commitFocusedWindowMove(_, _, _, let allowsRecoverableOffscreen):
            capability.supportsFocusedWindowMove
                && (!allowsRecoverableOffscreen
                    || capability.supportsFocusedWindowMoveRecoverableOffscreen)
        case .tap, .insertText, .backspace, .returnKey:
            true
        }
    }

    /// Builds the additive host capability installed only after the controller arms successfully.
    nonisolated static func remoteInputCapability(
        inputSessionID: UUID,
        screenRequestID: UInt64
    ) -> WebRTCInputCapability {
        WebRTCInputCapability(
            inputSessionID: inputSessionID,
            screenRequestID: screenRequestID,
            supportsPrimaryDrag: true,
            supportsScroll: true,
            supportsFocusedWindowResize: true,
            supportsFocusedWindowResizeScaleRebinding: true,
            supportsFocusedWindowMove: true,
            supportsFocusedWindowMoveScaleRebinding: true,
            supportsFocusedWindowMoveRecoverableOffscreen: true
        )
    }

    /// Reduces controller results to non-sensitive operational descriptions.
    private func diagnosticName(for result: MacRemoteInputResult) -> String {
        switch result {
        case .accepted(.none):
            return "accepted without editable focus"
        case .accepted(.editable):
            return "accepted with editable focus"
        case .rejected(let reason):
            return "rejected (\(reason))"
        }
    }

    /// Maps local outcomes to stable wire feedback and session-revocation policy.
    private func transportFeedback(
        for outcome: WorldwideRemoteInputInjectionOutcome
    ) -> RemoteInputTransportFeedback {
        switch outcome.result {
        case .accepted(.none):
            return .accepted(
                focus: .none,
                windowResize: outcome.isWindowMove ? nil : wireWindowResizeFeedback(outcome.windowResizeFeedback),
                windowMove: outcome.isWindowMove ? wireWindowMoveFeedback(outcome.windowResizeFeedback) : nil
            )
        case .accepted(.editable(let generation, let secure)):
            return .accepted(
                focus: .editable(generation: generation, secure: secure),
                windowResize: outcome.isWindowMove ? nil : wireWindowResizeFeedback(outcome.windowResizeFeedback),
                windowMove: outcome.isWindowMove ? wireWindowMoveFeedback(outcome.windowResizeFeedback) : nil
            )

        case .rejected(let rejection):
            let reason: WebRTCInputRejectionReason
            let screenFormatChanging: Bool
            let revokesSession: Bool
            switch rejection {
            case .disabled:
                reason = .inputDisabled
                screenFormatChanging = false
                revokesSession = true
            case .permissionRequired:
                let permission = remoteInputController.permissionStatus()
                reason = permission.accessibilityTrusted
                    ? .eventPostingPermissionRequired
                    : .accessibilityPermissionRequired
                screenFormatChanging = false
                revokesSession = true
            case .staleSession, .displayUnavailable:
                reason = .staleSession
                screenFormatChanging = false
                revokesSession = true
            case .screenFormatChanging:
                // Reuse the established non-terminal wire reason so older TestFlight clients
                // remain decode-compatible; newer clients use the optional flag to distinguish
                // this from real input throttling without retaining action content.
                reason = .rateLimited
                screenFormatChanging = true
                revokesSession = false
            case .invalidPoint, .invalidScrollDelta, .invalidText:
                reason = .invalidRequest
                screenFormatChanging = false
                revokesSession = false
            case .rateLimited:
                reason = .rateLimited
                screenFormatChanging = false
                revokesSession = false
            case .focusChanged:
                reason = .invalidFocus
                screenFormatChanging = false
                revokesSession = false
            case .primaryButtonInUse, .injectionFailed:
                reason = .injectionFailed
                screenFormatChanging = false
                revokesSession = false
            case .windowUnavailable, .windowResizeFailed:
                reason = .invalidRequest
                screenFormatChanging = false
                revokesSession = false
            case .windowResizeUncertain:
                // The AX rollback could not prove the original frame. Reuse the established
                // terminal session reason so deployed clients revoke all input authority.
                reason = .staleSession
                screenFormatChanging = false
                revokesSession = true
            }
            return .rejected(
                reason: reason,
                screenFormatChanging: screenFormatChanging,
                focus: wireFocus(outcome.verifiedFocus),
                revokesSession: revokesSession
            )
        }
    }

    private func wireFocus(_ focus: MacRemoteInputFocus?) -> WebRTCInputFocus {
        switch focus {
        case .some(.editable(let generation, let secure)):
            .editable(generation: generation, secure: secure)
        case .some(.none), nil:
            .none
        }
    }

    private func wireWindowResizeFeedback(
        _ feedback: MacRemoteWindowResizeFeedback?
    ) -> WebRTCWindowResizeFeedback? {
        guard let feedback else { return nil }
        let kind: WebRTCWindowResizeFeedbackKind? = switch feedback.kind {
        case .targetAcquired: .targetAcquired
        case .windowSelected: .windowSelected
        case .resizeCommitted: .resizeCommitted
        case .moveCommitted: nil
        }
        guard let kind else { return nil }
        let frame = feedback.target.normalizedFrame
        return WebRTCWindowResizeFeedback(
            kind: kind,
            committedTargetGeneration: feedback.committedTargetGeneration,
            target: WebRTCWindowResizeTarget(
                generation: feedback.target.generation,
                normalizedFrame: WebRTCNormalizedRect(
                    x: frame.minX,
                    y: frame.minY,
                    width: frame.width,
                    height: frame.height
                )
            )
        )
    }

    private func wireWindowMoveFeedback(
        _ feedback: MacRemoteWindowResizeFeedback?
    ) -> WebRTCWindowMoveFeedback? {
        guard let feedback else { return nil }
        let kind: WebRTCWindowMoveFeedbackKind? = switch feedback.kind {
        case .targetAcquired: .targetAcquired
        case .windowSelected: .windowSelected
        case .moveCommitted: .moveCommitted
        case .resizeCommitted: nil
        }
        guard let kind else { return nil }
        let frame = feedback.target.normalizedFrame
        let unclipped = feedback.target.unclippedNormalizedFrame
        return WebRTCWindowMoveFeedback(
            kind: kind, committedTargetGeneration: feedback.committedTargetGeneration,
            target: .init(
                generation: feedback.target.generation,
                normalizedFrame: .init(
                    x: frame.minX,
                    y: frame.minY,
                    width: frame.width,
                    height: frame.height
                ),
                unclippedNormalizedFrame: unclipped.map {
                    .init(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height)
                }
            )
        )
    }

    /// Revokes the transport token and controller state synchronously.
    private func revokeRemoteInputAuthorization() {
        let authorization = activeInputAuthorization
        activeInputAuthorization = nil
        activeInputCapability = nil
        // Detach actor state first, then acquire the shared controller before the independent
        // transport token. The final Active-ACK path owns those locks in that same order.
        remoteInputController.revoke(ifOwnedBy: remoteInputOwnerToken)
        authorization?.revoke()
    }

    // MARK: - ICE recovery and proof

    /// Stops visible capture when the authenticated transport route becomes uncertain.
    private func stopScreenCaptureForTransportUncertainty(_ reason: String) async {
        guard captureSource != nil else { return }
        // Privacy is fail-closed: a recovered peer must receive a fresh, acknowledged Show.
        logger.info("Stopping worldwide screen capture because \(reason)")
        _ = await stopScreenCaptureOrCloseSession(
            context: "transport uncertainty: \(reason)"
        )
    }

    /// Revokes both media gates before asynchronously stopping their native sources.
    private func stopCaptureForTransportUncertainty(_ reason: String) async {
        // Revoke both media gates before either asynchronous ScreenCaptureKit stop begins.
        do {
            var updatedPolicy = screenVideoAdaptationPolicy
            updatedPolicy.endFloorRecoveryVisibility()
            screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        revokeCaptureAuthorization()
        pauseSystemAudioForTransportUncertainty()
        captureSink?.stopForwarding()
        recordBlackHoleDefaultInputOutcome(
            blackHoleDefaultInput
                .transportDidBecomeUnhealthy(
                    peerGeneration: peerGeneration
                )
        )
        iPhoneMicrophoneForwarding.invalidateTransport()
        // This path is also used when a local ICE restart is armed before native state reports a
        // disconnect. Retire the screen probe and RTP encoding locally on every uncertainty
        // boundary, not only on peer/ICE callbacks that happen to call `enterRecovery` first.
        await peer?.suspendScreenMediaForTransportUncertainty()
        await peer?.suspendSystemAudioForTransportUncertainty()
        await stopScreenCaptureForTransportUncertainty(reason)
        await stopSystemAudioForTransportUncertainty(reason)
    }

    /// Installs a new proof epoch, removes media, then requests native ICE restart.
    private func beginICERestart(
        peer: WebRTCPeer,
        peerGeneration generation: UInt64
    ) async throws {
        guard generation == peerGeneration, !isStopped, self.peer != nil else {
            throw CancellationError()
        }
        let epoch = installRecoveryProofBoundary(awaitingAnswer: true)
        await stopCaptureForTransportUncertainty("an ICE restart began")
        guard generation == peerGeneration,
              epoch == recoveryProofEpoch,
              !isStopped,
              self.peer === peer else {
            throw CancellationError()
        }
        do {
            try await peer.restartICE()
        } catch {
            if epoch == recoveryProofEpoch,
               restartAnswerAwaitingEpoch == epoch {
                restartAnswerAwaitingEpoch = nil
            }
            throw error
        }
    }

    /// Enters fail-closed recovery and invalidates any pre-uncertainty authorization.
    private func enterRecovery(reason: String) async {
        isRecovering = true
        do {
            var updatedPolicy = screenVideoAdaptationPolicy
            updatedPolicy.endFloorRecoveryVisibility()
            screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        resetRemoteMediaCommandQueue()
        resetAutomaticScreenMediaSuspensionState()
        revokeCaptureAuthorization()
        pauseSystemAudioForTransportUncertainty()
        recordBlackHoleDefaultInputOutcome(
            blackHoleDefaultInput
                .transportDidBecomeUnhealthy(
                    peerGeneration: peerGeneration
                )
        )
        iPhoneMicrophoneForwarding.invalidateTransport()
        if recoveryProofRequired {
            // Invalidate a pre-uncertainty Hide/ACK without severing the current offer→answer
            // epoch. Native disconnected events are expected during an in-flight restart.
            recoveryProofAuthorization?.revoke()
            recoveryProofAuthorization = WebRTCControlAuthorization()
            pendingRecoveryProofRequest = nil
            recoveryProofAcknowledgementInFlight = nil
        }
        await stopCaptureForTransportUncertainty(reason)
    }

    /// Creates a fresh epoch that requires answer installation plus a Hide/Inactive proof.
    @discardableResult
    private func installRecoveryProofBoundary(awaitingAnswer: Bool) -> UInt64 {
        do {
            var updatedPolicy = screenVideoAdaptationPolicy
            updatedPolicy.endFloorRecoveryVisibility()
            screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        }
        screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
            revision: screenVideoAdaptationPolicyRevision &+ 1, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
        resetRemoteMediaCommandQueue()
        resetAutomaticScreenMediaSuspensionState()
        revokeCaptureAuthorization()
        pauseSystemAudioForTransportUncertainty()
        recordBlackHoleDefaultInputOutcome(
            blackHoleDefaultInput
                .transportDidBecomeUnhealthy(
                    peerGeneration: peerGeneration
                )
        )
        iPhoneMicrophoneForwarding.invalidateTransport()
        recoveryProofAuthorization?.revoke()
        recoveryProofEpoch &+= 1
        let epoch = recoveryProofEpoch
        recoveryProofRequired = true
        isRecovering = true
        restartAnswerAwaitingEpoch = awaitingAnswer ? epoch : nil
        restartAnswerAppliedEpoch = nil
        pendingRecoveryProofRequest = nil
        recoveryProofAcknowledgementInFlight = nil
        recoveryProofAuthorization = WebRTCControlAuthorization()
        return epoch
    }

    /// Completes recovery only when transport, restart answer, and proof request agree on epoch.
    private func completePendingRecoveryProofIfPossible(
        peer: WebRTCPeer,
        epoch: UInt64
    ) async {
        guard !isStopped,
              self.peer === peer,
              recoveryProofRequired,
              epoch == recoveryProofEpoch,
              restartAnswerAppliedEpoch == epoch,
              let request = pendingRecoveryProofRequest,
              request.epoch == epoch,
              recoveryProofAcknowledgementInFlight == nil,
              let authorization = recoveryProofAuthorization,
              authorization.isValid else {
            return
        }

        recoveryProofAcknowledgementInFlight = request
        do {
            try await peer.acknowledgeControlRequestIfTransportHealthy(
                id: request.id,
                state: .inactive,
                authorization: authorization
            )
        } catch {
            if recoveryProofAcknowledgementInFlight == request {
                recoveryProofAcknowledgementInFlight = nil
            }
            if let transportError = error as? WebRTCTransportError,
               transportError == .transportNotHealthy
                    || transportError == .controlAuthorizationRevoked {
                return
            }
            logger.error("Worldwide recovery proof acknowledgement failed: \(error.localizedDescription)")
            return
        }

        guard recoveryProofAcknowledgementInFlight == request else { return }
        recoveryProofAcknowledgementInFlight = nil
        guard !isStopped,
              self.peer === peer,
              recoveryProofRequired,
              epoch == recoveryProofEpoch,
              restartAnswerAppliedEpoch == epoch,
              pendingRecoveryProofRequest == request,
              recoveryProofAuthorization === authorization,
              authorization.isValid else {
            return
        }

        authorization.revoke()
        recoveryProofAuthorization = nil
        pendingRecoveryProofRequest = nil
        restartAnswerAwaitingEpoch = nil
        restartAnswerAppliedEpoch = nil
        recoveryProofRequired = false
        isRecovering = false
        let routingAdmission =
            admitBlackHoleInputWithinSafeOutputFence()
        let outputsAreSafe = routingAdmission.outputsAreSafe
        let currentBlackHoleSnapshot = routingAdmission.snapshot
        guard await startSystemAudioOrStopSession() else {
            await recoverFromSystemAudioStartUncertainty(
                "system audio could not be enabled after route proof"
            )
            return
        }
        if outputsAreSafe,
           let currentBlackHoleSnapshot {
            await iPhoneMicrophoneForwarding.updateDeviceSnapshot(
                currentBlackHoleSnapshot
            )
            await authorizeIPhoneMicrophoneForwardingIfPossible()
        }
        await recoveryCoordinator?.iceStateChanged(.connected)
    }

    /// Marks an initially healthy route usable and ensures system audio is live.
    @discardableResult
    private func markRecoveryHealthyIfPossible() async -> Bool {
        guard !recoveryProofRequired,
              peerIsConnected,
              iceIsConnected,
              controlChannelIsOpen else {
            return false
        }
        isRecovering = false
        let routingAdmission =
            admitBlackHoleInputWithinSafeOutputFence()
        let outputsAreSafe = routingAdmission.outputsAreSafe
        let currentBlackHoleSnapshot = routingAdmission.snapshot
        guard await startSystemAudioOrStopSession() else {
            await recoverFromSystemAudioStartUncertainty(
                "system audio could not be enabled on the healthy route"
            )
            return false
        }
        if outputsAreSafe,
           let currentBlackHoleSnapshot {
            await iPhoneMicrophoneForwarding.updateDeviceSnapshot(
                currentBlackHoleSnapshot
            )
            await authorizeIPhoneMicrophoneForwardingIfPossible()
        }
        return true
    }

    // MARK: - iPhone microphone to BlackHole

    private func observeSafeOutputRetryBridgeFault(_ error: Error, context: String) {
        safeOutputInvariantNeedsRedrive = true
        if featureProfile.allowsIPhoneMicrophoneAndDefaultInputRouting {
            _ = revokeWorldwideMicrophoneForUnsafeOutputInvariant(
                preservingSharedClockUnsafeFailure: true,
                preservingFormatUnsafeFailure: true)
        }
        if !safeOutputRetryBridgeFaultWasReported {
            safeOutputRetryBridgeFaultWasReported = true
            logger.error("Worldwide microphone routing refused a Rust retry bridge fault during "
                + context + ": " + error.localizedDescription)
        }
    }

    @discardableResult
    private func resetSafeOutputRetryPolicy(context: String) -> Bool {
        do {
            try safeOutputInvariantRetryPolicy.reset()
            return true
        } catch {
            observeSafeOutputRetryBridgeFault(error, context: context)
            return false
        }
    }

    private func safeOutputRetryBridgeIsHealthy(context: String) -> Bool {
        guard let fault = safeOutputInvariantRetryPolicy.bridgeFault else { return true }
        observeSafeOutputRetryBridgeFault(fault, context: context)
        return false
    }

    /// Called only after the existing native source/auth/liveness/peer-generation
    /// guards. Observation projection precedes the original exact-peer gate;
    /// watermark mutation precedes legitimate nil or evidence bridge refusal.
    private func consumeMacHostedCallObservationAfterNativeGuards(
        observation: SystemAudioMacFaceTimeActivityObservation,
        challenge: WebRTCMacHostedCallChallenge,
        exactPeerIsPresent: () -> Bool
    ) throws -> WebRTCMacHostedCallEvidence.State? {
        guard try WorldwideMacHostedCallObservationPolicy.admits(
            observationSequence: observation.observationSequence,
            highestAdmittedSequence: highestMacFaceTimeObservationSequence,
            observationChallenge: observation.challenge,
            currentChallenge: challenge, producer: hostedCallPolicyProducer
        ), exactPeerIsPresent() else { return nil }
        highestMacFaceTimeObservationSequence = observation.observationSequence
        return try WorldwideMacHostedCallEvidenceStatePolicy.state(
            isCausallyBoundActive: observation.isCausallyBoundActive,
            isCausallyArmed: observation.isCausallyArmed,
            producer: hostedCallPolicyProducer)
    }

    #if DEBUG
    struct BatchAPolicyFixtureSnapshot: Sendable {
        let needsRedrive: Bool
        let fault: WorldwideSafeOutputInvariantRetryBridgeError?
        let gateOpen: Bool
        let safeProofPresent: Bool
        let endpointProofPresent: Bool
        let inputProofPresent: Bool
        let stopped: Bool
        let stopInProgress: Bool
        let highestHostedObservation: UInt64
        let retryConfiguration: [Int]
        let retryCounters: [Int]
        let nativeAdmissionCallCount: Int
    }

    private func requireInertBatchAPolicyFixture() {
        precondition(audioRoutingIsInertPolicyFixture)
        precondition(peer == nil && audioSource == nil && audioSink == nil
                     && captureSource == nil && captureSink == nil)
    }

    /// DEBUG observation only: the actual getter stays inside this actor. No
    /// mutable Owner setter, producer query, native read, clock or second storage.
    /// Checked Sendable is required at this exact cross-actor test boundary.
    struct NativeOwnerStorageInertObservation: Equatable, Sendable {
        let policy: WorldwideScreenVideoAdaptationPolicy
        let revision: UInt64
        let fastStatisticsAvailable: Bool
        let laneRawValue: UInt64?
        let evidenceTime: ContinuousClock.Instant?
        let minimumCollectionSequence: UInt64?
        let applied: WorldwideScreenVideoEncodingRecommendation?
    }

    func nativeOwnerStorageInertObservationForTesting()
        -> NativeOwnerStorageInertObservation {
        requireInertBatchAPolicyFixture()
        let value = networkAdaptationOwnerCopiedValue()
        return .init(policy: value.policy, revision: value.revision,
            fastStatisticsAvailable: value.fastStatisticsAvailable,
            laneRawValue: value.lane?.rawValue, evidenceTime: value.evidenceTime,
            minimumCollectionSequence: value.minimumCollectionSequence,
            applied: value.applied)
    }

    struct NativeOwnerPublicationAtomObservation: Equatable, Sendable {
        let kind: UInt32
        let present: UInt32
        let high: Int64
        let low: UInt64
    }

    struct NativeOwnerPublicationSnapshotObservation: Equatable, Sendable {
        let atoms: [NativeOwnerPublicationAtomObservation]
        let times: [ContinuousClock.Instant?]
        let anchor: ContinuousClock.Instant?
        let route: WebRTCICERouteDiagnostics?
    }

    struct NativeOwnerStopPublicationFault: Sendable {
        enum Kind: Sendable { case refused, malformed, swallowedReentry }
        let operation: UInt32
        let kind: Kind
    }
    struct NativeOwnerStopPublicationCut: Equatable, Sendable {
        enum Disposition: Equatable, Sendable { case accepted, refused, malformed, reentry }
        let operation: UInt32
        let before: NativeOwnerPublicationSnapshotObservation
        let after: NativeOwnerPublicationSnapshotObservation
        let disposition: Disposition
    }
    struct NativeOwnerStopPublicationObservation: Equatable, Sendable {
        let current: NativeOwnerPublicationSnapshotObservation
        let cuts: [NativeOwnerStopPublicationCut]
        let attemptedOperations: [UInt32]
    }
    func enableNativeOwnerStopPublicationForTesting(faults: [NativeOwnerStopPublicationFault]) throws {
        requireInertBatchAPolicyFixture()
        guard !isStarted, !isStopped, !nativeOwnerStopPublicationEnabled else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        try screenVideoAdaptationOwnerBoundary.configureActualStopFaults(faults)
        nativeOwnerStopPublicationEnabled = true
    }

    private func nativeOwnerStopSnapshotObservation(retainingAnchor: ContinuousClock.Instant? = nil)
        throws -> NativeOwnerPublicationSnapshotObservation {
        let snapshot = try BelugaNetworkAdaptationOwnerSnapshot.capture(
            screenVideoAdaptationOwner, retainingAnchor: retainingAnchor)
        return .init(atoms: snapshot.atoms.map {
            .init(kind: $0.kind, present: $0.present, high: $0.high, low: $0.low)
        }, times: snapshot.times, anchor: snapshot.anchor, route: snapshot.route)
    }

    func nativeOwnerStopPublicationObservationForTesting() throws -> NativeOwnerStopPublicationObservation {
        requireInertBatchAPolicyFixture()
        return .init(current: try nativeOwnerStopSnapshotObservation(),
            cuts: nativeOwnerStopPublicationCuts, attemptedOperations: nativeOwnerStopPublicationAttempts)
    }

    enum NativeOwnerEpochPublicationFault: CaseIterable, Sendable {
        case none, refused, malformed, swallowedReentry, invocationExhausted, outerReentry, wrongBoundary
    }
    struct NativeOwnerEpochPublicationObservation: Sendable {
        let before: NativeOwnerPublicationSnapshotObservation
        let after: NativeOwnerPublicationSnapshotObservation
        let afterReplay: NativeOwnerPublicationSnapshotObservation
        let afterFresh: NativeOwnerPublicationSnapshotObservation?
        let disposition: String
        let operation: UInt32?
        let invocation: UInt64?
        let minimumResolutions: Int
        let peerGetterCalls: Int
        let rawCalls: Int
        let clockReads: Int
        let stores: Int
        let consumedBeforeReplay: Bool
        let pendingCleared: Bool
        let replayAccepted: Bool
        let replayDidWork: Bool
    }

    // One bounded same-actor assay. No capability, caller minimum, producer,
    // mutable Owner or native resources can cross this DEBUG fixture boundary.
    func nativeOwnerEpochPublicationInertObservationForTesting(fault: NativeOwnerEpochPublicationFault)
        throws -> NativeOwnerEpochPublicationObservation {
        requireInertBatchAPolicyFixture()
        guard !isStarted, !isStopped, !nativeOwnerEpochPublicationEnabled,
              pendingNativeOwnerEpochEntry == nil else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        nativeOwnerEpochPublicationEnabled = true
        defer { nativeOwnerEpochPublicationEnabled = false }
        let kind: NativeOwnerStopPublicationFault.Kind?
        switch fault {
        case .refused: kind = .refused
        case .malformed: kind = .malformed
        case .swallowedReentry: kind = .swallowedReentry
        default: kind = nil
        }
        try screenVideoAdaptationOwnerBoundary.configureActualEpochFault(kind,
            exhaustInvocation: fault == .invocationExhausted)
        let before = try nativeOwnerStopSnapshotObservation()
        let entry = try networkAdaptationActualEpochEntry()
        defer { networkAdaptationActualEpochRetire(entry) }
        var disposition = "refused"
        var operation: UInt32?, invocation: UInt64?
        do {
            if fault == .outerReentry {
                try screenVideoAdaptationOwnerBoundary.testSwallowedActualEpochOuterReentry(entry, on: self)
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            } else {
                let boundary = fault == .wrongBoundary ? BelugaNetworkAdaptationOwnerBoundary()
                    : screenVideoAdaptationOwnerBoundary
                switch try boundary.publishActualEpoch(entry, on: self) {
                case let .accepted(receipt):
                    disposition = "accepted"; operation = receipt.operation; invocation = receipt.invocation
                case .refused: disposition = "refused"
                case .superseded: disposition = "superseded"
                }
            }
        } catch BelugaNetworkAdaptationOwnerError.refused { disposition = "refused"
        } catch BelugaNetworkAdaptationOwnerError.reentry { disposition = "reentry"
        } catch BelugaNetworkAdaptationOwnerError.invocationExhausted { disposition = "exhausted"
        } catch BelugaNetworkAdaptationOwnerError.invalidResult { disposition = "malformed" }
        let after = try nativeOwnerStopSnapshotObservation(retainingAnchor: before.anchor)
        let consumed = entry.phase == .published || entry.phase == .retired
        let cleared = pendingNativeOwnerEpochEntry == nil
        let counts = screenVideoAdaptationOwnerBoundary.actualEpochDiagnosticsForTesting()
        let resolutions = entry.minimumResolutionCount, peerReads = entry.peerGetterCount, stores = entry.storeCount
        var replayAccepted = false
        do {
            if case .accepted = try screenVideoAdaptationOwnerBoundary.publishActualEpoch(entry, on: self) {
                replayAccepted = true
            }
        } catch BelugaNetworkAdaptationOwnerError.invocationExhausted { }
        let afterReplay = try nativeOwnerStopSnapshotObservation(retainingAnchor: before.anchor)
        let replayCounts = screenVideoAdaptationOwnerBoundary.actualEpochDiagnosticsForTesting()
        let replayDidWork = entry.minimumResolutionCount != resolutions || entry.peerGetterCount != peerReads
            || entry.storeCount != stores || replayCounts.rawCalls != counts.rawCalls
            || replayCounts.clockReads != counts.clockReads
        var afterFresh: NativeOwnerPublicationSnapshotObservation?
        if fault != .invocationExhausted {
            try screenVideoAdaptationOwnerBoundary.configureActualEpochFault(nil)
            let fresh = try networkAdaptationActualEpochEntry()
            defer { networkAdaptationActualEpochRetire(fresh) }
            guard case .accepted = try screenVideoAdaptationOwnerBoundary.publishActualEpoch(fresh, on: self) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            afterFresh = try nativeOwnerStopSnapshotObservation(retainingAnchor: before.anchor)
        }
        return .init(before: before, after: after, afterReplay: afterReplay, afterFresh: afterFresh,
            disposition: disposition, operation: operation, invocation: invocation,
            minimumResolutions: resolutions, peerGetterCalls: peerReads, rawCalls: counts.rawCalls,
            clockReads: counts.clockReads, stores: stores, consumedBeforeReplay: consumed,
            pendingCleared: cleared && pendingNativeOwnerEpochEntry == nil,
            replayAccepted: replayAccepted, replayDidWork: replayDidWork)
    }

    enum NativeOwnerResetInitialContext: CaseIterable, Sendable {
        case absent, pending, committed, failureClaimed
    }
    enum NativeOwnerResetPublicationFault: CaseIterable, Sendable {
        case none, refused, malformed, swallowedReentry, invocationExhausted, outerReentry, wrongBoundary, epochRefused
    }
    struct NativeOwnerResetPublicationObservation: Sendable {
        let before: NativeOwnerPublicationSnapshotObservation
        let afterPrimary: NativeOwnerPublicationSnapshotObservation?
        let after: NativeOwnerPublicationSnapshotObservation
        let disposition: String
        let operations: [UInt32]
        let cancelledOnce: Bool
        let contextCleared: Bool
        let pendingCleared: Bool
        let latchCommitted: Bool
        let repeatClaim: Bool
        let bindingWasOlder: Bool
        let rawCalls: Int
        let clockReads: Int
    }

    // Truthful native-latch classification on the existing nil-resource actor.
    // Synthetic context/notice is NOT a real ACK, live peer or capture proof.
    func nativeOwnerResetPublicationInertObservationForTesting(initial: NativeOwnerResetInitialContext,
        fault: NativeOwnerResetPublicationFault) throws -> NativeOwnerResetPublicationObservation {
        requireInertBatchAPolicyFixture()
        guard !isStarted, !isStopped, !nativeOwnerResetPublicationEnabled,
              pendingNativeOwnerResetEntry == nil, automaticScreenMediaResumeContext == nil else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let latch = WorldwideScreenAutomaticResumeCommitLatch()
        switch initial {
        case .committed: try latch.commit { }
        case .failureClaimed: precondition(latch.claimFailure())
        case .absent, .pending: break
        }
        let olderBinding = currentScreenMediaSuspensionBinding
        // Models the original Stop/startPeer generation advance before reset.
        peerGeneration &+= 1
        if initial != .absent {
            automaticScreenMediaResumeContext = .init(binding: olderBinding,
                notice: .init(screenRequestID: 1, suspensionGeneration: 1), attemptID: UUID(),
                finalAcknowledgementCommit: latch, inputOwnershipClaim: nil,
                probeAuthorization: nil, forwardingAuthorization: nil, boundary: nil,
                markerReady: nil, markerPresentation: nil)
        }
        let fixtureContext = automaticScreenMediaResumeContext
        let fixtureSuspension = screenMediaSuspension.snapshot
        defer {
            if let fixtureContext {
                retireOriginalResumeResetContext(fixtureContext, suspension: fixtureSuspension)
            }
        }
        nativeOwnerResetPublicationEnabled = true
        nativeOwnerEpochPublicationEnabled = true
        nativeOwnerResetFault = fault
        nativeOwnerResetAttemptedOperations = []
        nativeOwnerResetAfterPrimary = nil
        defer {
            nativeOwnerResetPublicationEnabled = false
            nativeOwnerEpochPublicationEnabled = false
            nativeOwnerResetFault = .none
            nativeOwnerResetAfterPrimary = nil
        }
        let kind: NativeOwnerStopPublicationFault.Kind?
        switch fault {
        case .refused: kind = .refused
        case .malformed: kind = .malformed
        case .swallowedReentry: kind = .swallowedReentry
        default: kind = nil
        }
        try screenVideoAdaptationOwnerBoundary.configureActualResetFault(kind,
            exhaustInvocation: fault == .invocationExhausted)
        try screenVideoAdaptationOwnerBoundary.configureActualEpochFault(fault == .epochRefused ? .refused : nil)
        let before = try nativeOwnerStopSnapshotObservation()
        let timeoutGeneration = automaticScreenMediaResumeTimeoutGeneration
        var disposition = "accepted"
        do { try publishActualResetOwner()
        } catch BelugaNetworkAdaptationOwnerError.refused { disposition = "refused"
        } catch BelugaNetworkAdaptationOwnerError.invalidResult { disposition = "malformed"
        } catch BelugaNetworkAdaptationOwnerError.reentry { disposition = "reentry"
        } catch BelugaNetworkAdaptationOwnerError.invocationExhausted { disposition = "exhausted" }
        let diagnostics = screenVideoAdaptationOwnerBoundary.actualResetDiagnosticsForTesting()
        return .init(before: before, afterPrimary: nativeOwnerResetAfterPrimary,
            after: try nativeOwnerStopSnapshotObservation(retainingAnchor: before.anchor),
            disposition: disposition, operations: nativeOwnerResetAttemptedOperations,
            cancelledOnce: automaticScreenMediaResumeTimeoutGeneration == timeoutGeneration &+ 1
                && automaticScreenMediaResumeTimeoutTask == nil,
            contextCleared: automaticScreenMediaResumeContext == nil,
            pendingCleared: pendingNativeOwnerResetEntry == nil && pendingNativeOwnerEpochEntry == nil,
            latchCommitted: latch.isCommitted,
            repeatClaim: initial == .absent ? false : latch.claimFailure(),
            bindingWasOlder: olderBinding.peerGeneration != peerGeneration,
            rawCalls: diagnostics.rawCalls, clockReads: diagnostics.clockReads)
    }

    struct NativeOwnerPublicationInertObservation: Sendable {
        let actualBefore: NativeOwnerPublicationSnapshotObservation
        let actualAfter: NativeOwnerPublicationSnapshotObservation
        let rejected: NativeOwnerPublicationSnapshotObservation
        let accepted: NativeOwnerPublicationSnapshotObservation
        let nestedReentryRejected: Bool
        let outerReentryRejected: Bool
        let rejectedPublications: Int
        let acceptedPublications: Int
        let operation: UInt32
        let invocation: UInt64
        let collectorEnabled: Bool
        let rawInvocations: [UInt64]
        let trace: [String]
    }

    /// Synchronous DEBUG-only isolation assay. Boundary and simulated slot are
    /// constructed and retired on this actor; only checked-Sendable copies leave.
    /// The actual Owner is observed, never replaced by this simulated publication.
    func nativeOwnerPublicationIsolatedInertObservationForTesting() throws
        -> NativeOwnerPublicationInertObservation {
        requireInertBatchAPolicyFixture()
        func observe(_ value: BelugaNetworkAdaptationOwnerValue) throws
            -> NativeOwnerPublicationSnapshotObservation {
            let s = try BelugaNetworkAdaptationOwnerSnapshot.capture(value)
            return .init(atoms: s.atoms.map {
                .init(kind: $0.kind, present: $0.present, high: $0.high, low: $0.low)
            }, times: s.times, anchor: s.anchor, route: s.route)
        }
        let seed = networkAdaptationOwnerCopiedValue()
        let before = try observe(seed)
        var rawInvocations: [UInt64] = []
        let boundary = BelugaNetworkAdaptationOwnerBoundary(testProducer: { request, source in
            rawInvocations.append(request.invocation)
            return try BelugaNetworkAdaptationOwnerBoundary.actual(request, source)
        })
        let slot = BelugaNetworkAdaptationOwnerPublicationFixture(
            boundary: boundary, value: seed, event: .stopSampling)
        var nestedReentryRejected = false
        slot.testHook = { stage in
            guard stage == .precommit else { return }
            do { _ = try boundary.propose(seed, event: .stopSampling) }
            catch BelugaNetworkAdaptationOwnerError.reentry { nestedReentryRejected = true }
        }
        var outerReentryRejected = false
        do { _ = try boundary.testPublishIsolated(slot, event: .stopSampling, on: self) }
        catch BelugaNetworkAdaptationOwnerError.reentry { outerReentryRejected = true }
        let rejected = try observe(slot.acceptedValue)
        let rejectedPublications = slot.publications
        slot.testHook = nil
        guard case let .accepted(receipt) = try boundary.testPublishIsolated(
            slot, event: .stopSampling, on: self) else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        return .init(actualBefore: before, actualAfter: try observe(networkAdaptationOwnerCopiedValue()),
            rejected: rejected, accepted: try observe(slot.acceptedValue),
            nestedReentryRejected: nestedReentryRejected, outerReentryRejected: outerReentryRejected,
            rejectedPublications: rejectedPublications, acceptedPublications: slot.publications,
            operation: receipt.operation, invocation: receipt.invocation,
            collectorEnabled: receipt.collectorEnabled, rawInvocations: rawInvocations,
            trace: slot.trace.map(\.rawValue))
    }

    func batchAStartOnlyInertRoutingMonitorForTesting() async {
        requireInertBatchAPolicyFixture()
        await startIPhoneMicrophoneDeviceMonitoringIfNeeded()
        await batchADrainOwnedInertRoutingObserversForTesting()
    }

    func batchADrainOwnedInertRoutingObserversForTesting() async {
        requireInertBatchAPolicyFixture()
        guard let join = batchAInertRoutingObserverJoin else {
            preconditionFailure("Only explicitly inert fixture owns a callback join")
        }
        await join.drainAllRetainedTasks()
        precondition(join.snapshot().retainedHandleCount == 0)
    }

    func batchAObserverJoinSnapshotForTesting() -> InertBatchARoutingObserverJoin.Snapshot {
        requireInertBatchAPolicyFixture()
        guard let join = batchAInertRoutingObserverJoin else {
            preconditionFailure("Only explicitly inert fixture owns a callback join")
        }
        return join.snapshot()
    }

    func batchAStageAggregateTransportForTesting(needsRedrive: Bool) {
        requireInertBatchAPolicyFixture()
        precondition(!isStarted && !isStopped && !captureLifetimeIsRequired)
        precondition(batchAInertRoutingObserverJoin?.snapshot().retainedHandleCount == 0)
        peerIsConnected = true
        iceIsConnected = true
        controlChannelIsOpen = true
        isRecovering = false
        peerGeneration = 1
        safeOutputInvariantNeedsRedrive = needsRedrive
    }

    private var debugCheckingICERecoveryFaultInjection:
        ICERecoveryCoordinator.CheckingFaultInjectionForTesting?

    /// Builds and installs through the SAME constructor helper as createPeer, but only in
    /// the existing explicitly inert fixture. Caller retains the old handle when swapping.
    func batchAInstallActualICERecoveryCoordinatorForTesting(
        peerGeneration generation: UInt64,
        checkingFaultInjection: ICERecoveryCoordinator.CheckingFaultInjectionForTesting? = nil,
        restart: @escaping ICERecoveryCoordinator.RestartAction
    ) -> ICERecoveryCoordinator {
        requireInertBatchAPolicyFixture()
        precondition(!isStarted && !isStopped && !captureLifetimeIsRequired)
        precondition(batchAInertRoutingObserverJoin?.snapshot().retainedHandleCount == 0)
        precondition(debugCheckingICERecoveryFaultInjection == nil)
        debugCheckingICERecoveryFaultInjection = checkingFaultInjection
        defer { debugCheckingICERecoveryFaultInjection = nil }
        let coordinator = makeICERecoveryCoordinator(peerGeneration: generation, restart: restart)
        peerGeneration = generation
        recoveryCoordinator = coordinator
        return coordinator
    }

    func batchAICERecoveryCoordinatorIsForTesting(_ candidate: ICERecoveryCoordinator) -> Bool {
        requireInertBatchAPolicyFixture()
        return recoveryCoordinator === candidate
    }

    /// Receiver-level test state only; it never grants a native media or input resource.
    struct ICERecoveryPolicyReceiverFixtureSnapshot: Sendable, Equatable {
        let peerGeneration: UInt64
        let stopped: Bool
        let stopInProgress: Bool
        let peerIsConnected: Bool
        let iceIsConnected: Bool
        let controlChannelIsOpen: Bool
        let isRecovering: Bool
        let recoveryProofRequired: Bool
        let peerIsPresent: Bool
        let coordinatorIsPresent: Bool
        let captureAuthorizationIsValid: Bool
        let audioAuthorizationIsValid: Bool
    }

    /// Exact synthetic generation custody is available only to the existing inert harness.
    func batchASetICERecoveryReceiverGenerationForTesting(_ generation: UInt64) {
        requireInertBatchAPolicyFixture()
        precondition(!isStarted && !isStopped && !captureLifetimeIsRequired)
        precondition(recoveryCoordinator == nil)
        precondition(batchAInertRoutingObserverJoin?.snapshot().retainedHandleCount == 0)
        peerGeneration = generation
    }

    func batchAICERecoveryPolicyReceiverSnapshotForTesting()
        -> ICERecoveryPolicyReceiverFixtureSnapshot {
        requireInertBatchAPolicyFixture()
        return .init(peerGeneration: peerGeneration, stopped: isStopped,
            stopInProgress: stopIsInProgress, peerIsConnected: peerIsConnected,
            iceIsConnected: iceIsConnected, controlChannelIsOpen: controlChannelIsOpen,
            isRecovering: isRecovering, recoveryProofRequired: recoveryProofRequired,
            peerIsPresent: peer != nil, coordinatorIsPresent: recoveryCoordinator != nil,
            captureAuthorizationIsValid: captureAuthorization?.isValid == true,
            audioAuthorizationIsValid: audioAuthorization?.isValid == true)
    }

    /// Delivers the captured generation through the actual production receiver, not exhaustion.
    func batchADeliverICERecoveryPolicyFaultForTesting(peerGeneration generation: UInt64) async {
        requireInertBatchAPolicyFixture()
        await recoveryPolicyDidFail(peerGeneration: generation)
    }

    func batchAAdmitForTesting() -> Bool {
        requireInertBatchAPolicyFixture()
        return admitBlackHoleInputWithinSafeOutputFence().outputsAreSafe
    }

    func batchASeedForeignFailureForTesting(
        _ category: WorldwideIPhoneMicrophoneForwardingFailureCategory
    ) {
        requireInertBatchAPolicyFixture()
        iPhoneMicrophoneForwarding.seedUnauthorizedFailureForTesting(category)
    }

    func batchAPolicyFixtureSnapshotForTesting() -> BatchAPolicyFixtureSnapshot {
        requireInertBatchAPolicyFixture()
        return .init(needsRedrive: safeOutputInvariantNeedsRedrive,
            fault: safeOutputInvariantRetryPolicy.bridgeFault,
            gateOpen: blackHoleMicrophoneOutputAuthorizationGate?.isOpen == true,
            safeProofPresent: safeOutputInvariantAuthorization != nil,
            endpointProofPresent: blackHoleEndpointPairAuthorization != nil,
            inputProofPresent: blackHoleDefaultInputAuthorization != nil,
            stopped: isStopped, stopInProgress: stopIsInProgress,
            highestHostedObservation: highestMacFaceTimeObservationSequence,
            retryConfiguration: [safeOutputInvariantRetryPolicy.maximumFailedAttemptCount,
                safeOutputInvariantRetryPolicy.maximumBackoffTickCount,
                safeOutputInvariantRetryPolicy.cappedCooldownTickCount],
            retryCounters: [safeOutputInvariantRetryPolicy.failedAttemptCount,
                safeOutputInvariantRetryPolicy.backoffTickCount,
                safeOutputInvariantRetryPolicy.cooldownTickCount],
            nativeAdmissionCallCount: batchANativeAdmissionCallCount)
    }

    func batchAConsumeHostedTailForTesting(
        observation: SystemAudioMacFaceTimeActivityObservation,
        challenge: WebRTCMacHostedCallChallenge,
        exactPeerIsPresent: Bool = true
    ) throws -> WebRTCMacHostedCallEvidence.State? {
        requireInertBatchAPolicyFixture()
        return try consumeMacHostedCallObservationAfterNativeGuards(
            observation: observation, challenge: challenge,
            exactPeerIsPresent: { exactPeerIsPresent })
    }
    #endif

    /// Keeps the exact output listeners registered through input-only admission.
    /// LAN coexistence retains its legacy policy and never reaches this ownership path.
    private func admitBlackHoleInputWithinSafeOutputFence(
        sharedClockRecoveryTaskGeneration: UInt64? = nil,
        sharedClockRecoveryParkingProof:
            BlackHoleDefaultInputLeaseParkingProof? = nil
    )
        -> (
            outputsAreSafe: Bool,
            snapshot: BlackHoleDeviceAvailabilitySnapshot?
        ) {
        guard safeOutputRetryBridgeIsHealthy(context: "safe-output admission") else {
            return (false, nil)
        }
        guard iPhoneMicrophoneForwardingPolicy == .enabled else {
            safeOutputInvariantNeedsRedrive = false
            safeOutputInvariantVerificationWasFailing = false
            _ = resetSafeOutputRetryPolicy(context: "microphone-disabled admission")
            return (false, nil)
        }
        guard transportAllowsCapture else {
            return (false, nil)
        }
        if let activeRecoveryTaskGeneration =
                sharedClockEpochRecoveryReadmissionTaskGeneration {
            guard sharedClockRecoveryTaskGeneration
                    == activeRecoveryTaskGeneration,
                  sharedClockRecoveryParkingProof != nil else {
                return (false, nil)
            }
        } else if sharedClockRecoveryTaskGeneration != nil
                    || sharedClockRecoveryParkingProof != nil {
            return (false, nil)
        }
        guard let monitoringEpoch =
                safeOutputInvariantMonitoringEpoch,
              let authorizationGate =
                blackHoleMicrophoneOutputAuthorizationGate else {
            return (false, nil)
        }
        if sharedClockBlocksCurrentPeerAndPair() {
            authorizationGate.close()
            return (false, nil)
        }
        if formatUnsafeBlocksCurrentPeerAndPair() {
            authorizationGate.close()
            return (false, nil)
        }
        if safeOutputInvariantNeedsRedrive {
            do {
                guard try safeOutputInvariantRetryPolicy.shouldAttemptOnCurrentTick() else {
                    return (false, nil)
                }
            } catch {
                observeSafeOutputRetryBridgeFault(error, context: "safe-output retry tick")
                return (false, nil)
            }
        }

        var admittedOutcomes:
            [WorldwideBlackHoleDefaultInputOutcome] = []
        var defaultInputAdmissionSucceeded = false
        var admittedDefaultInputAuthorization:
            BlackHoleDefaultInputLeaseAuthorization?
        var preMutationOutcome:
            WorldwideBlackHoleDefaultInputOutcome?
        var rollbackOutcome:
            WorldwideBlackHoleDefaultInputOutcome?
        var gateOpeningPreparation:
            BlackHoleMicrophoneOutputAuthorizationGate
                .OpeningPreparation?
        do {
            #if DEBUG
            batchANativeAdmissionCallCount += 1
            #endif
            let transaction = try worldwideSafeOutputInvariant
                .enforceDuringAdmission(
                    monitoringEpoch: monitoringEpoch,
                    beforeFirstMutation: {
                        authorizationGate.close()
                        self.safeOutputInvariantAuthorization = nil
                        self.blackHoleEndpointPairAuthorization = nil
                        self.blackHoleDefaultInputAuthorization = nil
                        self.iPhoneMicrophoneForwarding
                            .invalidateTransport()
                        let outcome:
                            WorldwideBlackHoleDefaultInputOutcome
                        if let sharedClockRecoveryParkingProof,
                           let snapshot = self
                            .blackHoleDeviceAvailabilityMonitor
                            .currentSnapshot(),
                           self.blackHoleDefaultInput
                            .sharedClockParkingProofIsCurrent(
                                sharedClockRecoveryParkingProof,
                                peerGeneration:
                                    self.peerGeneration,
                                snapshot: snapshot
                            ) {
                            outcome = .released
                        } else if sharedClockRecoveryParkingProof != nil {
                            outcome = .degraded
                        } else {
                            outcome = self.blackHoleDefaultInput
                                .transportDidBecomeUnhealthy(
                                    peerGeneration:
                                        self.peerGeneration
                                )
                        }
                        preMutationOutcome = outcome
                        if outcome == .degraded {
                            throw WorldwideScreenServiceError
                                .microphoneInputReleaseUnproved
                        }
                    },
                    admission: { ()
                        -> BlackHoleDeviceAvailabilitySnapshot? in
                        // First acquire under a fresh atomic-pair validation.
                        // Its owned default-input write produces the exact
                        // listener event that the lease incorporates below.
                        guard let initialRevalidation =
                                self.revalidateCurrentBlackHoleDeviceSnapshotForDefaultInput()
                        else {
                            return nil
                        }
                        admittedOutcomes.append(
                            initialRevalidation.outcome
                        )
                        let initialOutcome:
                            WorldwideBlackHoleDefaultInputOutcome
                        if let sharedClockRecoveryParkingProof {
                            initialOutcome = self.blackHoleDefaultInput
                                .transportDidBecomeHealthyAfterSharedClockRecovery(
                                    peerGeneration:
                                        self.peerGeneration,
                                    parkingProof:
                                        sharedClockRecoveryParkingProof
                                )
                        } else {
                            initialOutcome = self.blackHoleDefaultInput
                                .transportDidBecomeHealthy(
                                    peerGeneration:
                                        self.peerGeneration
                                )
                        }
                        admittedOutcomes.append(initialOutcome)
                        guard case .selected = initialOutcome else {
                            return nil
                        }

                        // Prepare only after the lease's owned notification has
                        // been consumed. Then span a final pair validation and
                        // exact input-listener proof. Any later device, output,
                        // or input callback closes this generation and prevents
                        // commit from reopening stale routing.
                        gateOpeningPreparation =
                            authorizationGate.prepareToOpen()
                        guard let finalRevalidation =
                                self.revalidateCurrentBlackHoleDeviceSnapshotForDefaultInput()
                        else {
                            return nil
                        }
                        admittedOutcomes.append(
                            finalRevalidation.outcome
                        )
                        let finalOutcome = self.blackHoleDefaultInput
                            .transportDidBecomeHealthy(
                                peerGeneration:
                                    self.peerGeneration
                            )
                        admittedOutcomes.append(finalOutcome)
                        switch finalOutcome {
                        case .selected(let key)
                            where key.monitorEpoch
                                == finalRevalidation.snapshot.monitorEpoch
                                && key.deviceGeneration
                                    == finalRevalidation.snapshot.deviceGeneration
                                && key.peerGeneration == self.peerGeneration
                                && key.deviceEndpoint
                                    == finalRevalidation.snapshot.defaultInputEndpoint
                                && key.inputAuthorization.targetEndpoint
                                    == finalRevalidation.snapshot.defaultInputEndpoint:
                            admittedDefaultInputAuthorization =
                                key.inputAuthorization
                            defaultInputAdmissionSucceeded = true

                        case .selected, .noChange,
                             .waitingForMonitor, .waitingForDevice,
                             .released, .degraded, .suppressed:
                            defaultInputAdmissionSucceeded = false
                        }
                        return finalRevalidation.snapshot
                    },
                    rollback: { _ in
                        authorizationGate.close()
                        self.safeOutputInvariantAuthorization = nil
                        self.blackHoleEndpointPairAuthorization = nil
                        self.blackHoleDefaultInputAuthorization = nil
                        self.iPhoneMicrophoneForwarding
                            .invalidateTransport()
                        rollbackOutcome =
                            self.blackHoleDefaultInput
                                .transportDidBecomeUnhealthy(
                                    peerGeneration:
                                        self.peerGeneration
                                )
                    },
                    commit: { admittedSnapshot, authorization in
                        guard let admittedSnapshot,
                              admittedSnapshot.isAvailable,
                              defaultInputAdmissionSucceeded,
                              let admittedDefaultInputAuthorization,
                              admittedDefaultInputAuthorization.targetEndpoint
                                == admittedSnapshot.defaultInputEndpoint else {
                            throw WorldwideScreenServiceError
                                .microphoneInputAdmissionUnavailable
                        }
                        guard let gateOpeningPreparation else {
                            throw WorldwideScreenServiceError
                                .microphoneWriterAuthorizationSuperseded
                        }
                        guard authorizationGate.open(
                            preparation: gateOpeningPreparation,
                            authorization: authorization
                        ) else {
                            throw WorldwideScreenServiceError
                                .microphoneWriterAuthorizationSuperseded
                        }
                        self.safeOutputInvariantAuthorization =
                            authorization
                        self.blackHoleDefaultInputAuthorization =
                            admittedDefaultInputAuthorization
                        self.blackHoleEndpointPairAuthorization =
                            BlackHoleEndpointPairAuthorization(
                                monitorEpoch:
                                    admittedSnapshot.monitorEpoch,
                                deviceGeneration:
                                    admittedSnapshot.deviceGeneration,
                                acceptedInventoryChangeSequence:
                                    admittedSnapshot
                                        .acceptedInventoryChangeSequence
                            )
                    }
                )
            safeOutputInvariantNeedsRedrive = false
            safeOutputInvariantVerificationWasFailing = false
            try safeOutputInvariantRetryPolicy.reset()
            if transaction.invariant.changedAnything {
                logger.info(
                    "Worldwide audio routing moved the virtual microphone off the " +
                        "default output selectors before selecting it " +
                        "as the iPhone microphone input"
                )
            }
            if let preMutationOutcome {
                recordBlackHoleDefaultInputOutcome(
                    preMutationOutcome
                )
            }
            for outcome in admittedOutcomes {
                recordBlackHoleDefaultInputOutcome(outcome)
            }
            return (true, transaction.admission)
        } catch let bridgeFault as WorldwideSafeOutputInvariantRetryBridgeError {
            observeSafeOutputRetryBridgeFault(bridgeFault,
                context: "safe-output committed admission reset")
            if let preMutationOutcome {
                recordBlackHoleDefaultInputOutcome(preMutationOutcome)
            }
            if let rollbackOutcome {
                recordBlackHoleDefaultInputOutcome(rollbackOutcome)
            }
            return (false, nil)
        } catch {
            authorizationGate.close()
            safeOutputInvariantAuthorization = nil
            blackHoleEndpointPairAuthorization = nil
            blackHoleDefaultInputAuthorization = nil
            iPhoneMicrophoneForwarding.invalidateTransport()
            if let preMutationOutcome {
                recordBlackHoleDefaultInputOutcome(
                    preMutationOutcome
                )
            }
            if let rollbackOutcome {
                recordBlackHoleDefaultInputOutcome(
                    rollbackOutcome
                )
            } else {
                recordBlackHoleDefaultInputOutcome(
                    blackHoleDefaultInput
                        .transportDidBecomeUnhealthy(
                            peerGeneration: peerGeneration
                        )
                )
            }
            safeOutputInvariantNeedsRedrive = true
            do {
                try safeOutputInvariantRetryPolicy.recordFailure()
            } catch {
                observeSafeOutputRetryBridgeFault(error, context: "safe-output failure bookkeeping")
            }
            logger.error(
                "Worldwide iPhone microphone routing remains disabled " +
                    "because the safe-output invariant could not be " +
                    "proven: " + error.localizedDescription
            )
            return (false, nil)
        }
    }

    /// Continuously verifies the output invariant. Any unsafe or unprovable route
    /// synchronously revokes microphone admission and default-input ownership before
    /// a capped, backed-off mutation attempt can run.
    private func maintainWorldwideSafeOutputInvariant() async {
        guard safeOutputRetryBridgeIsHealthy(context: "safe-output maintenance") else { return }
        guard iPhoneMicrophoneForwardingPolicy == .enabled else {
            return
        }
        if redriveSharedClockEpochCleanupIfNeeded() {
            return
        }
        guard transportAllowsCapture else { return }
        guard let monitoringEpoch =
                safeOutputInvariantMonitoringEpoch else {
            safeOutputInvariantNeedsRedrive = true
            revokeWorldwideMicrophoneForUnsafeOutputInvariant()
            return
        }

        let verification:
            WorldwideSafeOutputInvariantVerification
        do {
            verification = try worldwideSafeOutputInvariant.verify(
                monitoringEpoch: monitoringEpoch
            )
        } catch {
            let wasVerificationFailing =
                safeOutputInvariantVerificationWasFailing
            safeOutputInvariantVerificationWasFailing = true
            safeOutputInvariantNeedsRedrive = true
            revokeWorldwideMicrophoneForUnsafeOutputInvariant()
            if !wasVerificationFailing {
                logger.error(
                    "Worldwide microphone routing was revoked because " +
                        "the safe-output invariant could not be verified: " +
                        error.localizedDescription
                )
            }
            return
        }

        if safeOutputInvariantVerificationWasFailing {
            safeOutputInvariantVerificationWasFailing = false
            guard resetSafeOutputRetryPolicy(context: "verification recovered") else { return }
        }

        if verification.isSatisfied {
            guard resetSafeOutputRetryPolicy(context: "verification satisfied") else { return }
            guard safeOutputInvariantNeedsRedrive else {
                return
            }
            safeOutputInvariantNeedsRedrive = false
            await resumeWorldwideMicrophoneAfterSafeOutputInvariant()
            return
        }

        if verification.changedSincePreviousObservation {
            guard resetSafeOutputRetryPolicy(context: "verification changed") else { return }
        }
        safeOutputInvariantNeedsRedrive = true
        revokeWorldwideMicrophoneForUnsafeOutputInvariant()
        await resumeWorldwideMicrophoneAfterSafeOutputInvariant()
    }

    /// A selector callback has already closed the lock-free writer gate before
    /// this actor work is queued. Discard only events superseded by an exact
    /// listener-sequence authorization; every newer event revokes ownership
    /// before any repair or suspension point.
    private func safeOutputInvariantDidBecomeUncertain(
        epoch: WorldwideSafeOutputInvariantMonitoringEpoch,
        eventSequence: UInt64
    ) async {
        guard !isStopped,
              safeOutputInvariantMonitoringEpoch == epoch else {
            return
        }
        if let authorization = safeOutputInvariantAuthorization,
           authorization.monitoringEpoch == epoch,
           eventSequence <= authorization.listenerSequence {
            return
        }

        safeOutputInvariantAuthorization = nil
        blackHoleEndpointPairAuthorization = nil
        blackHoleDefaultInputAuthorization = nil
        safeOutputInvariantNeedsRedrive = true
        guard resetSafeOutputRetryPolicy(context: "safe-output uncertainty") else { return }
        revokeWorldwideMicrophoneForUnsafeOutputInvariant()
        await resumeWorldwideMicrophoneAfterSafeOutputInvariant()
    }

    @discardableResult
    private func revokeWorldwideMicrophoneForUnsafeOutputInvariant()
        -> WorldwideBlackHoleDefaultInputOutcome {
        revokeWorldwideMicrophoneForUnsafeOutputInvariant(
            preservingSharedClockUnsafeFailure: false,
            preservingFormatUnsafeFailure: false
        )
    }

    @discardableResult
    private func revokeWorldwideMicrophoneForUnsafeOutputInvariant(
        preservingSharedClockUnsafeFailure: Bool,
        preservingFormatUnsafeFailure: Bool = false
    ) -> WorldwideBlackHoleDefaultInputOutcome {
        blackHoleMicrophoneOutputAuthorizationGate?.close()
        safeOutputInvariantAuthorization = nil
        blackHoleEndpointPairAuthorization = nil
        blackHoleDefaultInputAuthorization = nil
        iPhoneMicrophoneForwarding.invalidateTransport(
            preservingSharedClockUnsafeFailure:
                preservingSharedClockUnsafeFailure,
            preservingFormatUnsafeFailure:
                preservingFormatUnsafeFailure
        )
        let outcome = blackHoleDefaultInput.transportDidBecomeUnhealthy(
            peerGeneration: peerGeneration
        )
        recordBlackHoleDefaultInputOutcome(outcome)
        return outcome
    }

    private func parkWorldwideMicrophoneForSharedClockRecovery()
        -> WorldwideBlackHoleClockEpochParkingOutcome {
        blackHoleMicrophoneOutputAuthorizationGate?.close()
        safeOutputInvariantAuthorization = nil
        blackHoleEndpointPairAuthorization = nil
        blackHoleDefaultInputAuthorization = nil
        iPhoneMicrophoneForwarding.invalidateTransport(
            preservingSharedClockUnsafeFailure: true
        )
        let outcome = blackHoleDefaultInput
            .parkForSharedClockEpochRecovery(
                peerGeneration: peerGeneration
            )
        switch outcome {
        case .parked:
            recordBlackHoleDefaultInputOutcome(.released)
        case .degraded:
            recordBlackHoleDefaultInputOutcome(.degraded)
        }
        return outcome
    }

    private func resumeWorldwideMicrophoneAfterSafeOutputInvariant(
        sharedClockRecoveryTaskGeneration: UInt64? = nil,
        sharedClockRecoveryParkingProof:
            BlackHoleDefaultInputLeaseParkingProof? = nil
    )
        async {
        guard safeOutputRetryBridgeIsHealthy(context: "microphone resume") else { return }
        guard transportAllowsCapture else { return }
        let routingAdmission =
            admitBlackHoleInputWithinSafeOutputFence(
                sharedClockRecoveryTaskGeneration:
                    sharedClockRecoveryTaskGeneration,
                sharedClockRecoveryParkingProof:
                    sharedClockRecoveryParkingProof
            )
        guard routingAdmission.outputsAreSafe else { return }
        let currentBlackHoleSnapshot = routingAdmission.snapshot
        if let currentBlackHoleSnapshot {
            await iPhoneMicrophoneForwarding.updateDeviceSnapshot(
                currentBlackHoleSnapshot
            )
            await authorizeIPhoneMicrophoneForwardingIfPossible(
                sharedClockRecoveryTaskGeneration:
                    sharedClockRecoveryTaskGeneration
            )
        }
    }

    /// Holds the captured clock rejection across statistics ticks and transport
    /// epochs. Signed-32 headroom exhaustion gets one release-and-idle recovery
    /// episode; every other rejection, and a repeated exhaustion, remains
    /// blocked until a genuinely new peer or atomic endpoint-pair generation.
    private func sharedClockBlocksCurrentPeerAndPair() -> Bool {
        Self.sharedClockBlockRemainsActive(
            &sharedClockBlockedPeerPair,
            peerGeneration: peerGeneration,
            snapshot:
                blackHoleDeviceAvailabilityMonitor.currentSnapshot()
        )
    }

    nonisolated static func sharedClockBlockRemainsActive(
        _ blockedPeerPair: inout SharedClockBlockedPeerPair?,
        peerGeneration: UInt64,
        snapshot: BlackHoleDeviceAvailabilitySnapshot?
    ) -> Bool {
        guard let blocked = blockedPeerPair else {
            return false
        }
        guard blocked.peerGeneration == peerGeneration else {
            blockedPeerPair = nil
            return false
        }
        guard let snapshot else {
            return true
        }
        guard blocked.matches(
            peerGeneration: peerGeneration,
            snapshot: snapshot
        ) else {
            blockedPeerPair = nil
            return false
        }
        return true
    }

    /// A format/readback rejection is deterministic for the captured output
    /// pair. Keep that exact peer/pair fenced until either generation changes.
    private func formatUnsafeBlocksCurrentPeerAndPair() -> Bool {
        Self.formatUnsafeBlockRemainsActive(
            &formatUnsafeBlockedPeerPair,
            peerGeneration: peerGeneration,
            snapshot:
                blackHoleDeviceAvailabilityMonitor.currentSnapshot()
        )
    }

    nonisolated static func formatUnsafeBlockRemainsActive(
        _ blockedPeerPair: inout FormatUnsafeBlockedPeerPair?,
        peerGeneration: UInt64,
        snapshot: BlackHoleDeviceAvailabilitySnapshot?
    ) -> Bool {
        guard let blocked = blockedPeerPair else {
            return false
        }
        guard blocked.peerGeneration == peerGeneration else {
            blockedPeerPair = nil
            return false
        }
        guard let snapshot else {
            return true
        }
        guard blocked.matches(
            peerGeneration: peerGeneration,
            snapshot: snapshot
        ) else {
            blockedPeerPair = nil
            return false
        }
        return true
    }

    private func iPhoneMicrophoneSharedClockDidFail(
        key: WorldwideIPhoneMicrophoneForwardingKey,
        rejection: BlackHoleFaceTimeClockRejection
    ) {
        guard key.peerGeneration == peerGeneration else {
            return
        }
        if let snapshot =
                blackHoleDeviceAvailabilityMonitor.currentSnapshot() {
            guard snapshot.monitorEpoch == key.monitorEpoch,
                  snapshot.deviceGeneration
                    == key.deviceGeneration else {
                return
            }
        }

        let blockedPair =
            SharedClockBlockedPeerPair(forwardingKey: key)
        sharedClockBlockedPeerPair = blockedPair
        let recoveryDecision = sharedClockEpochRecoveryPolicy
            .registerFailure(
                key: key,
                rejection: rejection
            )
        switch recoveryDecision {
        case .recover(let attempt, let maximumAttemptCount):
            // Preserve the captured failure while this exact owner releases
            // both endpoints and proves a real idle gap. No route can reopen
            // until the task clears the service-level peer/pair block.
            let parkingOutcome =
                parkWorldwideMicrophoneForSharedClockRecovery()
            guard case .parked(let parkingProof) = parkingOutcome,
                  let parkingRoute =
                    WorldwideSharedClockEpochRecoveryParkingRoute(
                        defaultInputUID:
                            parkingProof.parkingEndpoint.deviceUID
                    ) else {
                cancelSharedClockEpochRecovery(
                    resetPolicy: false,
                    clearCompatibilityBlock: false
                )
                _ = revokeWorldwideMicrophoneForSharedClockFailure(
                    blockedPair: blockedPair
                )
                break
            }
            guard scheduleSharedClockEpochRecovery(
                key: key,
                blockedPair: blockedPair,
                parkingProof: parkingProof,
                parkingRoute: parkingRoute,
                attempt: attempt,
                maximumAttemptCount: maximumAttemptCount
            ) else {
                _ = revokeWorldwideMicrophoneForSharedClockFailure(
                    blockedPair: blockedPair
                )
                break
            }

        case .failClosed:
            cancelSharedClockEpochRecovery(
                resetPolicy: false,
                clearCompatibilityBlock: false
            )
            revokeWorldwideMicrophoneForSharedClockFailure(
                blockedPair: blockedPair
            )
        }
        logger.error(
            Self.iPhoneMicrophoneRuntimeFailureLogMessage(
                error: .sharedClockUnsafe(rejection)
            )
        )
    }

    private func scheduleSharedClockEpochRecovery(
        key: WorldwideIPhoneMicrophoneForwardingKey,
        blockedPair: SharedClockBlockedPeerPair,
        parkingProof: BlackHoleDefaultInputLeaseParkingProof,
        parkingRoute:
            WorldwideSharedClockEpochRecoveryParkingRoute,
        attempt: Int,
        maximumAttemptCount: Int
    ) -> Bool {
        guard let snapshot =
                blackHoleDeviceAvailabilityMonitor.currentSnapshot(),
              blockedPair.matches(
                peerGeneration: peerGeneration,
                snapshot: snapshot
              ),
              let visibleInputEndpoint =
                snapshot.defaultInputEndpoint,
              let hiddenWriterEndpoint =
                snapshot.hiddenMirrorSinkEndpoint else {
            return false
        }

        sharedClockEpochRecoveryTask?.cancel()
        let taskGeneration =
            advanceSharedClockEpochRecoveryTaskGeneration()
        sharedClockEpochRecoveryKey = key
        sharedClockEpochRecoveryTask = Task { [weak self] in
            await self?.runSharedClockEpochRecovery(
                key: key,
                blockedPair: blockedPair,
                parkingProof: parkingProof,
                parkingRoute: parkingRoute,
                visibleInputEndpoint: visibleInputEndpoint,
                hiddenWriterEndpoint: hiddenWriterEndpoint,
                taskGeneration: taskGeneration
            )
        }
        logger.info(
            "Worldwide iPhone microphone released its expired clock " +
                "epoch and began bounded idle recovery attempt " +
                "\(attempt)/\(maximumAttemptCount)"
        )
        return true
    }

    private func runSharedClockEpochRecovery(
        key: WorldwideIPhoneMicrophoneForwardingKey,
        blockedPair: SharedClockBlockedPeerPair,
        parkingProof: BlackHoleDefaultInputLeaseParkingProof,
        parkingRoute:
            WorldwideSharedClockEpochRecoveryParkingRoute,
        visibleInputEndpoint: BlackHoleDeviceEndpointIdentity,
        hiddenWriterEndpoint: BlackHoleDeviceEndpointIdentity,
        taskGeneration: UInt64
    ) async {
        let poller = WorldwideSharedClockEpochRecoveryPoller(
            maximumPollCount:
                Self.maximumSharedClockEpochQuiescencePolls,
            requiredConsecutiveIdleObservations:
                Self.requiredSharedClockIdleObservations
        )
        let pollOutcome = await poller.wait(
            sleep: {
                try await Task.sleep(
                    for: Self.sharedClockEpochQuiescencePollInterval
                )
            },
            isCurrent: {
                sharedClockEpochRecoveryIsCurrent(
                    key: key,
                    blockedPair: blockedPair,
                    parkingProof: parkingProof,
                    visibleInputEndpoint: visibleInputEndpoint,
                    hiddenWriterEndpoint: hiddenWriterEndpoint,
                    taskGeneration: taskGeneration
                )
            },
            sample: {
                switch virtualMicrophoneEpochStateReader.observe(
                    visibleInputDeviceID:
                        visibleInputEndpoint.deviceID,
                    hiddenWriterDeviceID:
                        hiddenWriterEndpoint.deviceID
                ) {
                case .success(let observation):
                    return observation.provesGlobalIdleCandidate(
                        parkedOn: parkingRoute
                    )
                        ? .idle
                        : .active
                case .failure:
                    return .unreadable
                }
            }
        )

        switch pollOutcome {
        case .idleProven:
            guard sharedClockEpochRecoveryIsCurrent(
                key: key,
                blockedPair: blockedPair,
                parkingProof: parkingProof,
                visibleInputEndpoint: visibleInputEndpoint,
                hiddenWriterEndpoint: hiddenWriterEndpoint,
                taskGeneration: taskGeneration
            ) else {
                if sharedClockEpochRecoveryEpisodeIsCurrent(
                    key: key,
                    blockedPair: blockedPair,
                    visibleInputEndpoint: visibleInputEndpoint,
                    hiddenWriterEndpoint: hiddenWriterEndpoint,
                    taskGeneration: taskGeneration
                ) {
                    _ = revokeWorldwideMicrophoneForSharedClockFailure(
                        blockedPair: blockedPair
                    )
                }
                finishSharedClockEpochRecoveryTaskIfCurrent(
                    taskGeneration: taskGeneration
                )
                return
            }

            // A stable public idle candidate warrants this one bounded retry.
            // Keep the exact rejected full key until readmission returns: a
            // track or authorization change during the await must not be
            // mistaken for this recovery's newly proven clock epoch.
            sharedClockEpochRecoveryReadmissionTaskGeneration =
                taskGeneration
            sharedClockBlockedPeerPair = nil
            await resumeWorldwideMicrophoneAfterSafeOutputInvariant(
                sharedClockRecoveryTaskGeneration: taskGeneration,
                sharedClockRecoveryParkingProof: parkingProof
            )

            guard sharedClockEpochRecoveryEpisodeIsCurrent(
                key: key,
                blockedPair: blockedPair,
                visibleInputEndpoint: visibleInputEndpoint,
                hiddenWriterEndpoint: hiddenWriterEndpoint,
                taskGeneration: taskGeneration
            ) else {
                finishSharedClockEpochRecoveryTaskIfCurrent(
                    taskGeneration: taskGeneration
                )
                return
            }

            let forwarding = iPhoneMicrophoneForwarding.snapshot()
            guard WorldwideSharedClockEpochRecoveryAdmissionPolicy
                .accepts(snapshot: forwarding, after: key) else {
                // This exact peer/pair spent its only recovery attempt. Restore
                // the compatibility fence before revoking any mismatched route.
                sharedClockBlockedPeerPair = blockedPair
                _ = revokeWorldwideMicrophoneForSharedClockFailure(
                    blockedPair: blockedPair
                )
                finishSharedClockEpochRecoveryTaskIfCurrent(
                    taskGeneration: taskGeneration
                )
                logger.error(
                    "Worldwide iPhone microphone fresh-epoch recovery " +
                        "failed exact readmission: " +
                        WorldwideSharedClockEpochRecoveryAdmissionPolicy
                            .diagnosticDescription(
                                snapshot: forwarding,
                                after: key
                            )
                )
                return
            }

            cancelSharedClockEpochRecovery(
                resetPolicy: false,
                clearCompatibilityBlock: true
            )
            logger.info(
                "Worldwide iPhone microphone established a fresh " +
                    "FaceTime-safe virtual microphone clock epoch"
            )
            return

        case .cancelled, .staleOwner:
            if sharedClockEpochRecoveryEpisodeIsCurrent(
                key: key,
                blockedPair: blockedPair,
                visibleInputEndpoint: visibleInputEndpoint,
                hiddenWriterEndpoint: hiddenWriterEndpoint,
                taskGeneration: taskGeneration
            ) {
                _ = revokeWorldwideMicrophoneForSharedClockFailure(
                    blockedPair: blockedPair
                )
            }
            finishSharedClockEpochRecoveryTaskIfCurrent(
                taskGeneration: taskGeneration
            )
            return

        case .timedOut:
            if sharedClockEpochRecoveryEpisodeIsCurrent(
                key: key,
                blockedPair: blockedPair,
                visibleInputEndpoint: visibleInputEndpoint,
                hiddenWriterEndpoint: hiddenWriterEndpoint,
                taskGeneration: taskGeneration
            ) {
                _ = revokeWorldwideMicrophoneForSharedClockFailure(
                    blockedPair: blockedPair
                )
            }
            finishSharedClockEpochRecoveryTaskIfCurrent(
                taskGeneration: taskGeneration
            )
            logger.error(
                "Worldwide iPhone microphone fresh-epoch recovery remained " +
                    "blocked because both virtual endpoints did not become " +
                    "stably idle on the exact parking route within the " +
                    "bounded wait"
            )
            return
        }
    }

    private func sharedClockEpochRecoveryIsCurrent(
        key: WorldwideIPhoneMicrophoneForwardingKey,
        blockedPair: SharedClockBlockedPeerPair,
        parkingProof: BlackHoleDefaultInputLeaseParkingProof,
        visibleInputEndpoint: BlackHoleDeviceEndpointIdentity,
        hiddenWriterEndpoint: BlackHoleDeviceEndpointIdentity,
        taskGeneration: UInt64
    ) -> Bool {
        guard !isStopped,
              transportAllowsCapture,
              sharedClockEpochRecoveryTaskGeneration
                == taskGeneration,
              sharedClockEpochRecoveryKey == key,
              sharedClockBlockedPeerPair == blockedPair,
              peerGeneration == key.peerGeneration,
              safeOutputInvariantAuthorization == nil,
              blackHoleEndpointPairAuthorization == nil,
              blackHoleDefaultInputAuthorization == nil,
              let authorizationGate =
                blackHoleMicrophoneOutputAuthorizationGate,
              !authorizationGate.isOpen,
              let snapshot =
                blackHoleDeviceAvailabilityMonitor.currentSnapshot(),
              blockedPair.matches(
                peerGeneration: peerGeneration,
                snapshot: snapshot
              ),
              snapshot.defaultInputEndpoint
                == visibleInputEndpoint,
              snapshot.hiddenMirrorSinkEndpoint
                == hiddenWriterEndpoint,
              blackHoleDefaultInput.sharedClockParkingProofIsCurrent(
                parkingProof,
                peerGeneration: peerGeneration,
                snapshot: snapshot
              ) else {
            return false
        }

        let forwarding = iPhoneMicrophoneForwarding.snapshot()
        return forwarding.monitorEpoch == key.monitorEpoch
            && forwarding.deviceGeneration
                == key.deviceGeneration
            && forwarding.peerGeneration == key.peerGeneration
            && forwarding.transportAuthorizationEpoch
                == key.transportAuthorizationEpoch
            && forwarding.trackGeneration == key.trackGeneration
            && !forwarding.transportAuthorized
            && !forwarding.queueRunning
    }

    private func sharedClockEpochRecoveryEpisodeIsCurrent(
        key: WorldwideIPhoneMicrophoneForwardingKey,
        blockedPair: SharedClockBlockedPeerPair,
        visibleInputEndpoint: BlackHoleDeviceEndpointIdentity,
        hiddenWriterEndpoint: BlackHoleDeviceEndpointIdentity,
        taskGeneration: UInt64
    ) -> Bool {
        guard !isStopped,
              transportAllowsCapture,
              sharedClockEpochRecoveryTaskGeneration
                == taskGeneration,
              sharedClockEpochRecoveryKey == key,
              peerGeneration == key.peerGeneration,
              let snapshot =
                blackHoleDeviceAvailabilityMonitor.currentSnapshot(),
              blockedPair.matches(
                peerGeneration: peerGeneration,
                snapshot: snapshot
              ),
              snapshot.defaultInputEndpoint
                == visibleInputEndpoint,
              snapshot.hiddenMirrorSinkEndpoint
                == hiddenWriterEndpoint else {
            return false
        }
        return true
    }

    @discardableResult
    private func advanceSharedClockEpochRecoveryTaskGeneration()
        -> UInt64 {
        sharedClockEpochRecoveryTaskGeneration &+= 1
        if sharedClockEpochRecoveryTaskGeneration == 0 {
            sharedClockEpochRecoveryTaskGeneration = 1
        }
        return sharedClockEpochRecoveryTaskGeneration
    }

    private func finishSharedClockEpochRecoveryTaskIfCurrent(
        taskGeneration: UInt64
    ) {
        guard sharedClockEpochRecoveryTaskGeneration
                == taskGeneration else {
            return
        }
        sharedClockEpochRecoveryTask = nil
        sharedClockEpochRecoveryKey = nil
        if sharedClockEpochRecoveryReadmissionTaskGeneration
                == taskGeneration {
            sharedClockEpochRecoveryReadmissionTaskGeneration = nil
        }
    }

    /// A failed clock-epoch parking transition may retain the exact lease when
    /// Core Audio is temporarily unreadable. Retry cleanup immediately, then
    /// retain only the blocked peer/pair identity so statistics ticks can keep
    /// redriving the safe compare-and-restore path without touching a successor.
    @discardableResult
    private func revokeWorldwideMicrophoneForSharedClockFailure(
        blockedPair: SharedClockBlockedPeerPair
    ) -> WorldwideBlackHoleDefaultInputOutcome {
        let outcome =
            revokeWorldwideMicrophoneForUnsafeOutputInvariant(
                preservingSharedClockUnsafeFailure: true
            )
        switch outcome {
        case .degraded:
            sharedClockEpochCleanupPendingPair = blockedPair
        case .selected, .noChange, .waitingForMonitor,
             .waitingForDevice, .released, .suppressed:
            if sharedClockEpochCleanupPendingPair == blockedPair {
                sharedClockEpochCleanupPendingPair = nil
            }
        }
        return outcome
    }

    /// Returns true when a still-current cleanup fence consumed this tick. The
    /// lease release is listener-fenced: an external selector choice
    /// terminalizes ownership and is never restored over.
    private func redriveSharedClockEpochCleanupIfNeeded() -> Bool {
        guard let blockedPair =
                sharedClockEpochCleanupPendingPair else {
            return false
        }
        guard sharedClockBlockedPeerPair == blockedPair,
              blockedPair.peerGeneration == peerGeneration else {
            sharedClockEpochCleanupPendingPair = nil
            return false
        }
        if let snapshot =
                blackHoleDeviceAvailabilityMonitor.currentSnapshot(),
           !blockedPair.matches(
                peerGeneration: peerGeneration,
                snapshot: snapshot
           ) {
            sharedClockEpochCleanupPendingPair = nil
            return false
        }

        _ = revokeWorldwideMicrophoneForSharedClockFailure(
            blockedPair: blockedPair
        )
        return true
    }

    private func cancelSharedClockEpochRecovery(
        resetPolicy: Bool,
        clearCompatibilityBlock: Bool
    ) {
        sharedClockEpochRecoveryTask?.cancel()
        sharedClockEpochRecoveryTask = nil
        sharedClockEpochRecoveryKey = nil
        sharedClockEpochRecoveryReadmissionTaskGeneration = nil
        _ = advanceSharedClockEpochRecoveryTaskGeneration()
        if resetPolicy {
            sharedClockEpochRecoveryPolicy.reset()
        }
        if clearCompatibilityBlock {
            sharedClockBlockedPeerPair = nil
        }
        if resetPolicy || clearCompatibilityBlock {
            sharedClockEpochCleanupPendingPair = nil
        }
    }

    private func iPhoneMicrophoneFormatDidFail(
        key: WorldwideIPhoneMicrophoneForwardingKey,
        rejection: BlackHoleMicrophoneOutputFormatRejection
    ) {
        guard key.peerGeneration == peerGeneration else {
            return
        }
        if let snapshot =
                blackHoleDeviceAvailabilityMonitor.currentSnapshot() {
            guard snapshot.monitorEpoch == key.monitorEpoch,
                  snapshot.deviceGeneration
                    == key.deviceGeneration else {
                return
            }
        }

        formatUnsafeBlockedPeerPair =
            FormatUnsafeBlockedPeerPair(forwardingKey: key)
        revokeWorldwideMicrophoneForUnsafeOutputInvariant(
            preservingSharedClockUnsafeFailure: false,
            preservingFormatUnsafeFailure: true
        )
        logger.error(
            Self.iPhoneMicrophoneRuntimeFailureLogMessage(
                error: .formatUnsafe(rejection)
            )
        )
    }

    private func startIPhoneMicrophoneDeviceMonitoringIfNeeded()
        async {
        #if DEBUG
        let observerJoin = batchAInertRoutingObserverJoin
        #endif
        guard iPhoneMicrophoneForwardingPolicy == .enabled else {
            return
        }

        guard WorldwideBlackHoleAudioRoutingStartupGate
            .redriveAndPermitNewOwnership(
                retainer:
                    blackHoleAudioRoutingCleanupRetainer,
                maximumAttemptCount: 1,
                deferredDefaultInputCleanup: deferredBlackHoleDefaultInputCleanup
            ) else {
            blackHoleDeviceMonitorEpoch = nil
            logger.error(
                "Virtual microphone device monitoring startup is deferred " +
                    "because an older lease or service still retains unresolved " +
                    "exact Core Audio routing cleanup ownership"
            )
            return
        }

        guard let authorizationGate =
                blackHoleMicrophoneOutputAuthorizationGate else {
            logger.error(
                "Virtual microphone writer authorization is unavailable; " +
                    "automatic input selection and forwarding remain disabled"
            )
            return
        }

        blackHoleDefaultInputLease.setUncertaintyHandler {
            [weak self, authorizationGate] event in
            // This is the raw default-input selector callback. Close the
            // realtime writer before the lease or actor can reconcile it.
            authorizationGate.close()
            let callbackTask = Task<Void, Never> { [weak self] in
                await self?
                    .blackHoleDefaultInputDidBecomeUncertain(event)
            }
            #if DEBUG
            observerJoin?.retain(callbackTask, kind: .inputUncertainty)
            #endif
        }

        do {
            safeOutputInvariantMonitoringEpoch =
                try worldwideSafeOutputInvariant
                    .beginSessionMonitoring {
                        [weak self, authorizationGate]
                        epoch,
                        eventSequence in
                        authorizationGate.close()
                        let callbackTask = Task<Void, Never> { [weak self] in
                            await self?
                                .safeOutputInvariantDidBecomeUncertain(
                                    epoch: epoch,
                                    eventSequence: eventSequence
                                )
                        }
                        #if DEBUG
                        observerJoin?.retain(callbackTask, kind: .safeOutputUncertainty)
                        #endif
                    }
        } catch {
            safeOutputInvariantMonitoringEpoch = nil
            authorizationGate.close()
            logger.error(
                "Safe-output session monitoring is unavailable; " +
                    "automatic input selection and forwarding remain " +
                    "disabled: " + error.localizedDescription
            )
            return
        }

        do {
            let epoch = try blackHoleDeviceAvailabilityMonitor.start(
                onUncertain: {
                    [weak self, authorizationGate]
                    monitorEpoch,
                    eventSequence in
                    // This is the raw Core Audio callback boundary. Close
                    // synchronously before the monitor dispatches refresh or
                    // either reconciliation Task can reach this actor.
                    authorizationGate.close()
                    let callbackTask = Task<Void, Never> { [weak self] in
                        await self?
                            .blackHoleDeviceInventoryDidBecomeUncertain(
                                monitorEpoch: monitorEpoch,
                                eventSequence: eventSequence
                            )
                    }
                    #if DEBUG
                    observerJoin?.retain(callbackTask, kind: .inventoryUncertainty)
                    #endif
                },
                observer: { [weak self] snapshot in
                    let callbackTask = Task<Void, Never> { [weak self] in
                        await self?.blackHoleDeviceAvailabilityDidChange(
                            snapshot
                        )
                    }
                    #if DEBUG
                    observerJoin?.retain(callbackTask, kind: .inventoryObservation)
                    #endif
                }
            )
            blackHoleDeviceMonitorEpoch = epoch
            _ = blackHoleDefaultInput.beginMonitoring(
                epoch: epoch
            )
            iPhoneMicrophoneForwarding.beginMonitoring(
                epoch: epoch
            )
            await consumeCurrentBlackHoleDeviceSnapshot()
        } catch {
            blackHoleDeviceMonitorEpoch = nil
            endSafeOutputInvariantMonitoring()
            recordBlackHoleDefaultInputOutcome(
                blackHoleDefaultInput.monitoringDidFail()
            )
            iPhoneMicrophoneForwarding.monitoringDidFail()
            logger.error(
                "Virtual microphone device monitoring is unavailable; " +
                    "iPhone microphone forwarding remains disabled: " +
                    error.localizedDescription
            )
        }
    }

    private func consumeCurrentBlackHoleDeviceSnapshot()
        async {
        let snapshot: BlackHoleDeviceAvailabilitySnapshot?
        if transportAllowsCapture {
            snapshot =
                admitBlackHoleInputWithinSafeOutputFence().snapshot
        } else {
            snapshot =
                consumeCurrentBlackHoleDeviceSnapshotForDefaultInput()
        }
        guard let snapshot else {
            return
        }
        await iPhoneMicrophoneForwarding.updateDeviceSnapshot(
            snapshot
        )
        if transportAllowsCapture {
            await authorizeIPhoneMicrophoneForwardingIfPossible()
        }
    }

    private struct RevalidatedBlackHoleDeviceSnapshot {
        let snapshot: BlackHoleDeviceAvailabilitySnapshot
        let outcome: WorldwideBlackHoleDefaultInputOutcome
    }

    @discardableResult
    private func consumeCurrentBlackHoleDeviceSnapshotForDefaultInput()
        -> BlackHoleDeviceAvailabilitySnapshot? {
        guard let revalidated =
                revalidateCurrentBlackHoleDeviceSnapshotForDefaultInput()
        else {
            return nil
        }
        recordBlackHoleDefaultInputOutcome(
            revalidated.outcome
        )
        return revalidated.snapshot
    }

    private func revalidateCurrentBlackHoleDeviceSnapshotForDefaultInput()
        -> RevalidatedBlackHoleDeviceSnapshot? {
        guard !isStopped else { return nil }
        switch blackHoleDeviceAvailabilityMonitor
            .revalidateCurrentSnapshot() {
        case .validated(let snapshot):
            guard snapshot.monitorEpoch
                    == blackHoleDeviceMonitorEpoch else {
                return nil
            }
            return RevalidatedBlackHoleDeviceSnapshot(
                snapshot: snapshot,
                outcome: blackHoleDefaultInput
                    .updateDeviceSnapshot(snapshot)
            )

        case .validationFailed, .inactive:
            recordBlackHoleDefaultInputOutcome(
                blackHoleDefaultInput
                    .deviceRevalidationDidFail()
            )
            iPhoneMicrophoneForwarding.monitoringDidFail()
            logger.error(
                "Virtual microphone endpoint-pair revalidation failed; " +
                    "automatic input selection and iPhone microphone " +
                    "forwarding were revoked"
            )
            return nil
        }
    }

    private func blackHoleDeviceAvailabilityDidChange(
        _ snapshot: BlackHoleDeviceAvailabilitySnapshot
    ) async {
        guard !isStopped,
              snapshot.monitorEpoch == blackHoleDeviceMonitorEpoch else {
            return
        }
        // The observer crosses into this actor through an unsequenced Task.
        // Never admit its captured snapshot directly: a newer synchronous
        // validation failure may already have revoked that same generation.
        // Re-read the exact pair so only fresh evidence can restore routing.
        if safeOutputInvariantNeedsRedrive {
            guard resetSafeOutputRetryPolicy(context: "device availability changed") else { return }
        }
        await consumeCurrentBlackHoleDeviceSnapshot()
    }

    /// The raw callback has already closed the lock-free writer gate. If a
    /// same-event revalidation committed while this Task waited for the actor,
    /// its exact sequence supersedes this reconciliation. A newer event always
    /// revokes the pair proof and must complete a fresh admission.
    private func blackHoleDeviceInventoryDidBecomeUncertain(
        monitorEpoch: UUID,
        eventSequence: UInt64
    ) async {
        guard !isStopped,
              blackHoleDeviceMonitorEpoch == monitorEpoch else {
            return
        }
        if let authorization = blackHoleEndpointPairAuthorization,
           authorization.monitorEpoch == monitorEpoch,
           eventSequence
                <= authorization.acceptedInventoryChangeSequence {
            return
        }

        blackHoleEndpointPairAuthorization = nil
        blackHoleDefaultInputAuthorization = nil
        safeOutputInvariantNeedsRedrive = true
        guard resetSafeOutputRetryPolicy(context: "device inventory uncertainty") else { return }
        revokeWorldwideMicrophoneForUnsafeOutputInvariant()
        await resumeWorldwideMicrophoneAfterSafeOutputInvariant()
    }

    /// The exact default-input listener already closed the writer gate at the
    /// raw callback boundary. Drop only the callback included by the admission
    /// proof that reopened it. A newer or mismatched event is an external choice:
    /// stop forwarding, relinquish ownership without restoration, and leave this
    /// connection terminal instead of automatically selecting over the user.
    private func blackHoleDefaultInputDidBecomeUncertain(
        _ event: BlackHoleDefaultInputLeaseUncertaintyEvent
    ) async {
        guard !isStopped else { return }
        if let authorization = blackHoleDefaultInputAuthorization,
           authorization.incorporates(event) {
            return
        }

        blackHoleDefaultInputAuthorization = nil
        blackHoleEndpointPairAuthorization = nil
        iPhoneMicrophoneForwarding.invalidateTransport()
        recordBlackHoleDefaultInputOutcome(
            blackHoleDefaultInput
                .defaultInputDidBecomeUncertain(event)
        )
    }

    func iPhoneMicrophoneForwardingSnapshot()
        -> WorldwideIPhoneMicrophoneForwardingHostSnapshot {
        iPhoneMicrophoneForwarding.snapshot()
    }

    private func authorizeIPhoneMicrophoneForwardingIfPossible(
        sharedClockRecoveryTaskGeneration: UInt64? = nil
    )
        async {
        guard safeOutputRetryBridgeIsHealthy(context: "microphone authorization") else { return }
        if let activeRecoveryTaskGeneration =
                sharedClockEpochRecoveryReadmissionTaskGeneration {
            guard sharedClockRecoveryTaskGeneration
                    == activeRecoveryTaskGeneration else {
                return
            }
        } else if sharedClockRecoveryTaskGeneration != nil {
            return
        }
        guard transportAllowsCapture,
              let peer,
              safeOutputInvariantAuthorization != nil,
              blackHoleEndpointPairAuthorization != nil,
              blackHoleDefaultInputAuthorization != nil,
              let authorizationGate =
                blackHoleMicrophoneOutputAuthorizationGate,
              authorizationGate.isOpen,
              !sharedClockBlocksCurrentPeerAndPair(),
              !formatUnsafeBlocksCurrentPeerAndPair() else {
            return
        }
        await iPhoneMicrophoneForwarding.authorizeTransport(
            peer: peer,
            peerGeneration: peerGeneration
        )
    }

    private func shutdownBlackHoleAudioRouting() {
        blackHoleMicrophoneOutputAuthorizationGate?.close()
        safeOutputInvariantAuthorization = nil
        blackHoleEndpointPairAuthorization = nil
        blackHoleDefaultInputAuthorization = nil
        let safeOutputMonitoringEpoch =
            safeOutputInvariantMonitoringEpoch
        safeOutputInvariantMonitoringEpoch = nil
        blackHoleDeviceMonitorEpoch = nil

        let result =
            WorldwideBlackHoleAudioRoutingCleanupPolicy.run(
                maximumEpisodeCount:
                    maximumBlackHoleAudioRoutingCleanupEpisodeCount,
                shutdownDefaultInput: {
                    self.blackHoleDefaultInput.shutdown()
                },
                stopDeviceMonitor: {
                    self.blackHoleDeviceAvailabilityMonitor
                        .stop()
                }
            )

        if result == .degraded {
            let lease = blackHoleDefaultInputLease
            let monitor =
                blackHoleDeviceAvailabilityMonitor
            let invariant = worldwideSafeOutputInvariant
            blackHoleAudioRoutingCleanupRetainer
                .retain(
                    id: blackHoleAudioRoutingCleanupID
                ) {
                    let defaultInputCompleted =
                        lease.shutdown()
                            != .retryableFailure
                    let monitorCompleted =
                        monitor.stop() == .stopped
                    guard defaultInputCompleted,
                          monitorCompleted else {
                        return false
                    }
                    if let safeOutputMonitoringEpoch {
                        // The writer gate was closed before this retained
                        // cleanup began. Listener-removal failure is itself
                        // retained by the invariant with the exact identities.
                        try? invariant.endSessionMonitoring(
                            epoch: safeOutputMonitoringEpoch
                        )
                    }
                    return true
                }
            logger.error(
                "Virtual microphone audio-routing cleanup remains degraded " +
                    "after its single globally bounded shutdown " +
                    "episode; exact Core Audio cleanup ownership " +
                    "is retained for a later explicit lifecycle redrive"
            )
        } else {
            if let safeOutputMonitoringEpoch {
                do {
                    try worldwideSafeOutputInvariant
                        .endSessionMonitoring(
                            epoch: safeOutputMonitoringEpoch
                        )
                } catch {
                    logger.error(
                        "Safe-output listener cleanup remains degraded: " +
                            error.localizedDescription
                    )
                }
            }
            blackHoleAudioRoutingCleanupRetainer
                .remove(
                    id: blackHoleAudioRoutingCleanupID
                )
        }
    }

    private func endSafeOutputInvariantMonitoring() {
        blackHoleMicrophoneOutputAuthorizationGate?.close()
        safeOutputInvariantAuthorization = nil
        blackHoleEndpointPairAuthorization = nil
        blackHoleDefaultInputAuthorization = nil
        guard let epoch = safeOutputInvariantMonitoringEpoch else {
            return
        }
        safeOutputInvariantMonitoringEpoch = nil
        do {
            try worldwideSafeOutputInvariant.endSessionMonitoring(
                epoch: epoch
            )
        } catch {
            logger.error(
                "Safe-output listener cleanup remains degraded: " +
                    error.localizedDescription
            )
        }
    }

    private func recordBlackHoleDefaultInputOutcome(
        _ outcome:
            WorldwideBlackHoleDefaultInputOutcome
    ) {
        switch outcome {
        case .selected(let key):
            logger.info(
                Self.defaultInputSelectionLogMessage(
                    routingEpoch: blackHoleRoutingEpoch,
                    peerGeneration: key.peerGeneration,
                    deviceGeneration: key.deviceGeneration,
                    processIdentifier:
                        ProcessInfo.processInfo
                            .processIdentifier
                )
            )
        case .degraded:
            logger.error(
                "Automatic virtual microphone default-input selection is unavailable; " +
                    "the worldwide media session remains active"
            )
        case .noChange, .waitingForMonitor, .waitingForDevice,
             .released, .suppressed:
            break
        }
    }

    private func iPhoneMicrophoneOutputDidFail(
        output: BlackHoleMicrophoneOutput,
        error: BlackHoleMicrophoneOutputError
    ) async {
        let category =
            Self.iPhoneMicrophoneRuntimeFailureCategory(
                for: error
            )
        let failedKey =
            iPhoneMicrophoneForwarding.snapshot().currentKey

        if case .formatUnsafe(let rejection) = error {
            guard let failedKey,
                  await iPhoneMicrophoneForwarding.handleRuntimeFailure(
                    from: output,
                    category: category
                  ) else {
                return
            }
            iPhoneMicrophoneFormatDidFail(
                key: failedKey,
                rejection: rejection
            )
            return
        }

        if case .sharedClockUnsafe(let rejection) = error {
            guard let failedKey,
                  await iPhoneMicrophoneForwarding.handleRuntimeFailure(
                    from: output,
                    category: category
                  ) else {
                return
            }
            iPhoneMicrophoneSharedClockDidFail(
                key: failedKey,
                rejection: rejection
            )
            return
        }

        // A listener may already have closed the realtime gate while its actor
        // reconciliation is still queued. Revalidate the exact endpoint pair
        // and safe-output proof before the driver can spend this key's retry or
        // synchronously redrive it.
        await consumeCurrentBlackHoleDeviceSnapshot()
        guard await iPhoneMicrophoneForwarding.handleRuntimeFailure(
            from: output,
            category: category
        ) else {
            return
        }
        logger.error(
            Self.iPhoneMicrophoneRuntimeFailureLogMessage(
                error: error
            )
        )
    }

    private func installIPhoneMicrophoneTrack(
        _ track: WebRTCRemoteAudioTrack
    ) async {
        guard track.logicalLane == .iPhoneMicrophone else {
            iPhoneMicrophoneForwarding.clearTrack()
            track.setEnabled(false)
            logger.error(
                "Rejected unexpected worldwide remote audio lane "
                    + track.logicalLane.rawValue
            )
            return
        }
        await iPhoneMicrophoneForwarding.installTrack(track)
    }

    /// Converts unexplained audio-start failure on a healthy route into ICE recovery.
    private func recoverFromSystemAudioStartUncertainty(_ reason: String) async {
        guard !isStopped,
              !isRecovering,
              !recoveryProofRequired,
              // Actor reentrancy can deliver another healthy native event while the first
              // event owns ScreenCaptureKit startup. Pending startup is not route failure; its
              // owner will publish connected or return here with this flag cleared.
              !systemAudioStartInProgress,
              !systemAudioIsLive else {
            return
        }
        await enterRecovery(reason: reason)
        await recoveryCoordinator?.iceStateChanged(.failed)
    }

    /// A malformed core result is not an exhausted attempt or a recovered media route.
    /// One constructor site owns the unchanged production generation-capturing callbacks.
    private func makeICERecoveryCoordinator(
        peerGeneration generation: UInt64,
        restart: @escaping ICERecoveryCoordinator.RestartAction
    ) -> ICERecoveryCoordinator {
        let exhausted: ICERecoveryCoordinator.ExhaustedAction = { [weak self] in
            await self?.recoveryDidExhaust(peerGeneration: generation)
        }
        let policyFailed: ICERecoveryCoordinator.PolicyFailureAction = { [weak self] _ in
            await self?.recoveryPolicyDidFail(peerGeneration: generation)
        }
        #if DEBUG
        if let injection = debugCheckingICERecoveryFaultInjection {
            return ICERecoveryCoordinator(restart: restart, exhausted: exhausted,
                policyFailed: policyFailed, checkingFaultInjectionForTesting: injection)
        }
        #endif
        return ICERecoveryCoordinator(restart: restart, exhausted: exhausted, policyFailed: policyFailed)
    }

    private func recoveryPolicyDidFail(peerGeneration generation: UInt64) async {
        guard generation == peerGeneration, !isStopped else { return }
        logger.error("Worldwide ICE recovery policy evidence is unavailable")
        await stop()
    }

    /// Closes the current peer generation when bounded recovery cannot restore all gates.
    private func recoveryDidExhaust(peerGeneration generation: UInt64) async {
        guard generation == peerGeneration, !isStopped else {
            return
        }
        let recoveryAudioIsReady = Self.recoveryAudioIsReady(
            allowsSystemAudio: featureProfile.allowsSystemAudio,
            systemAudioIsLive: systemAudioIsLive,
            audioAuthorizationIsValid: audioAuthorization?.isValid == true
        )
        if !recoveryProofRequired,
           peerIsConnected,
           iceIsConnected,
           controlChannelIsOpen,
           recoveryAudioIsReady {
            isRecovering = false
            return
        }
        guard isRecovering
                || recoveryProofRequired
                || systemAudioStartInProgress
                || !recoveryAudioIsReady else { return }
        logger.error("Worldwide ICE recovery exhausted its bounded attempts")
        await stop()
    }

    nonisolated static func recoveryAudioIsReady(
        allowsSystemAudio: Bool,
        systemAudioIsLive: Bool,
        audioAuthorizationIsValid: Bool
    ) -> Bool {
        !allowsSystemAudio || (systemAudioIsLive && audioAuthorizationIsValid)
    }

    // MARK: - Native screen capture

    /// Proves the currently installed source, long-lived capture gate, and exact forwarding
    /// generation together. This may describe a replacement completed during actor reentrancy.
    private var screenCaptureIsActivelyForwarding: Bool {
        guard captureSource != nil,
              let sink = captureSink,
              captureAuthorization?.isValid == true,
              let forwardingAuthorization = captureForwardingAuthorization,
              forwardingAuthorization.isValid else {
            return false
        }
        return sink.allowsActiveUse(authorizedBy: forwardingAuthorization)
    }

    /// Preserves an already-linearized Active acknowledgement across the current exact rebuild,
    /// queued successor, or bounded geometry debounce. Failure closes the gate before yielding.
    private var screenCaptureTransitionIsOwned: Bool {
        guard transportAllowsCapture else { return false }
        if screenCaptureIsActivelyForwarding {
            return true
        }
        switch screenFormatRenegotiation.phase {
        case .rebuilding:
            return screenFormatRenegotiation.owner != nil
        case .queued:
            guard let pendingSink = screenFormatRenegotiation.pending else {
                return false
            }
            return captureSource != nil
                && captureSink === pendingSink
                && captureAuthorization?.isValid == true
                && pendingSink.isAwaitingFormatRenegotiation
        case .failed:
            return false
        case .idle:
            guard let currentSink = captureSink else { return false }
            return captureSource != nil
                && captureAuthorization?.isValid == true
                && (
                    currentSink.isAwaitingFormatRenegotiation
                        || currentSink.isDebouncingFormatRenegotiation
                        || currentSink.isDisplayConfigurationInProgress
                )
        }
    }

    /// A newer ordered request owns the screen state, so an older key-frame command must not stop
    /// capture merely because its acknowledgement can no longer be sent.
    nonisolated static func isSupersededScreenControlRequest(_ error: any Error) -> Bool {
        guard let transportError = error as? WebRTCTransportError else { return false }
        switch transportError {
        case .unknownControlRequest, .staleControlRequest:
            return true
        default:
            return false
        }
    }

    /// Revocation caused by a currently-owned display transition is retryable with its new token.
    nonisolated static func isRevokedScreenControlAuthorization(_ error: any Error) -> Bool {
        guard let transportError = error as? WebRTCTransportError else { return false }
        return transportError == .controlAuthorizationRevoked
    }

    /// Retries a startup whose observer proves that Display Settings changed mode mid-flight.
    private func startScreenCaptureWithDisplayModeRetries(
        requiredDisplayID: UInt32? = nil,
        remainingRetries: Int = maximumDisplayModeStartupRetries,
        owner requestedOwner: ScreenCaptureStartupOwner? = nil
    ) async throws -> WebRTCControlAuthorization {
        let owner = requestedOwner ?? ScreenCaptureStartupOwner(
            visibilityCommandEpoch: screenVisibilityCommandEpoch,
            peerGeneration: peerGeneration,
            recoveryEpoch: recoveryProofEpoch
        )
        guard screenCaptureStartupOwnerIsCurrent(owner) else {
            throw CancellationError()
        }
        do {
            let authorization = try await startScreenCapture(
                requiredDisplayID: requiredDisplayID
            )
            guard screenCaptureStartupOwnerIsCurrent(owner) else {
                throw CancellationError()
            }
            return authorization
        } catch {
            guard remainingRetries > 0,
                  Self.isDisplayModeChangedDuringScreenStart(error),
                  captureSource == nil,
                  transportAllowsCapture else {
                throw error
            }
            logger.info("Retrying worldwide screen startup after another display mode change")
            // Let ScreenCaptureKit's filter snapshot catch up with the already-notified
            // CoreGraphics mode. The bounded, throwing sleep preserves cancellation semantics.
            try await Task.sleep(for: .milliseconds(125))
            guard screenCaptureStartupOwnerIsCurrent(owner),
                  captureSource == nil,
                  transportAllowsCapture else {
                throw CancellationError()
            }
            return try await startScreenCaptureWithDisplayModeRetries(
                requiredDisplayID: requiredDisplayID,
                remainingRetries: remainingRetries - 1,
                owner: owner
            )
        }
    }

    private func screenCaptureStartupOwnerIsCurrent(
        _ owner: ScreenCaptureStartupOwner
    ) -> Bool {
        !Self.screenFormatRenegotiationWasSuperseded(
            visibilityCommandEpoch: owner.visibilityCommandEpoch,
            currentVisibilityCommandEpoch: screenVisibilityCommandEpoch,
            peerGeneration: owner.peerGeneration,
            currentPeerGeneration: peerGeneration,
            recoveryEpoch: owner.recoveryEpoch,
            currentRecoveryEpoch: recoveryProofEpoch,
            serviceIsStopped: isStopped
        )
    }

    private nonisolated static func isDisplayModeChangedDuringScreenStart(
        _ error: any Error
    ) -> Bool {
        guard let captureError = error as? ScreenVideoCaptureError else { return false }
        if case .displayModeChangedDuringStart = captureError {
            return true
        }
        return false
    }

    /// Starts ScreenCaptureKit behind a revocable WebRTC control authorization.
    ///
    /// Forwarding begins only after both native startup and a post-await transport-health
    /// check succeed. Any uncertain partial start is synchronously revoked and stopped.
    private func startScreenCapture(
        requiredDisplayID: UInt32? = nil
    ) async throws -> WebRTCControlAuthorization {
        if captureSource != nil,
           let captureSink,
           requiredDisplayID.map({ $0 == captureDisplayID }) != false,
           captureAuthorization?.isValid == true,
           let captureForwardingAuthorization,
           captureSink.allowsActiveUse(
               authorizedBy: captureForwardingAuthorization
           ),
           captureForwardingAuthorization.isValid,
           transportAllowsCapture {
            return captureForwardingAuthorization
        }
        guard captureSource == nil else {
            throw WorldwideScreenServiceError.transportUnavailable
        }
        guard transportAllowsCapture else {
            throw WorldwideScreenServiceError.transportUnavailable
        }
        guard let peer, let capturer = peer.externalVideoCapturer else {
            throw WorldwideScreenServiceError.videoCapturerUnavailable
        }

        // Construct the revocable capture gate before the callback sink. ScreenCaptureKit may
        // report an unexpected stop from outside this actor, so the callback must close the gate
        // and revoke controller state synchronously before it schedules actor cleanup.
        let authorization = WebRTCControlAuthorization()
        let inputController = remoteInputController
        let inputOwnerToken = remoteInputOwnerToken
        let sink = WorldwideScreenSampleSink(
            capturer: capturer,
            captureLifetime: captureLifetime,
            remoteInputController: inputController,
            remoteInputOwnerToken: inputOwnerToken,
            didRequireCaptureFormatRenegotiation: { [weak self] sink in
                Task {
                    await self?.renegotiateScreenCaptureFormat(for: sink)
                }
            }
        ) { [weak self] source, message in
            authorization.revoke()
            inputController.revoke(ifOwnedBy: inputOwnerToken)
            Task {
                await self?.screenCaptureDidStop(
                    source: source,
                    authorization: authorization,
                    message: message
                )
            }
        }
        let displayModeRequirement = screenDisplayRequirement
        let source = ScreenVideoCaptureSource(
            displayID: requiredDisplayID ?? screenDisplayID,
            displayRequirement: screenDisplayRequirement,
            maximumWidth: maximumWidth,
            framesPerSecond: framesPerSecond,
            consumer: sink,
            displayModeSnapshotProvider: { displayID in
                try await ScreenVideoDisplayModeSubprocessResolver.resolveLive(
                    displayID,
                    displayRequirement: displayModeRequirement
                )
            },
            makeStopWatchdog: makeNativeCaptureWatchdog,
            logger: logger
        )
        captureSink = sink
        captureSource = source
        captureAuthorization = authorization

        do {
            let format = try await source.start()
            guard requiredDisplayID.map({ $0 == format.displayID }) != false else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            let nativeTransportIsHealthy = await peer.isTransportHealthyForCapture()
            guard nativeTransportIsHealthy,
                  captureSource === source,
                  captureAuthorization === authorization,
                  authorization.isValid,
                  transportAllowsCapture else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            let baseDimensions = ScreenVideoPixelDimensions(
                width: format.width,
                height: format.height
            )
            let encodingRecommendation =
                screenVideoAdaptationPolicy.currentRecommendation
            let senderUpdate: WebRTCScreenVideoEncodingUpdate?
            do {
                senderUpdate = try await peer.applyScreenVideoEncodingLimits(
                    encodingRecommendation.webRTCLimits
                )
            } catch {
                senderUpdate = nil
                logger.error(
                    "Worldwide screen video retained its native sender limits at startup: "
                        + error.localizedDescription
                )
            }
            guard self.peer === peer,
                  captureSource === source,
                  captureAuthorization === authorization,
                  authorization.isValid,
                  transportAllowsCapture else {
                if let senderUpdate {
                    do {
                        _ = try await peer
                            .rollbackScreenVideoEncodingUpdateIfCurrent(
                                senderUpdate
                            )
                    } catch {
                        logger.error(
                            "Worldwide screen video startup rollback failed: "
                                + error.localizedDescription
                        )
                    }
                }
                throw WorldwideScreenServiceError.transportUnavailable
            }
            if senderUpdate != nil {
                screenVideoAdaptationOwner = .init(policy: screenVideoAdaptationPolicy,
                    revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                    lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                    minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: encodingRecommendation)
            }
            captureDisplayID = format.displayID
            captureAuthoritativeDisplayBounds = format.authoritativeDisplayBounds
            captureVideoBaseDimensions = baseDimensions
            remoteInputController.updateAuthoritativeDisplayBounds(
                format.authoritativeDisplayBounds,
                for: format.displayID,
                ownerToken: remoteInputOwnerToken
            )
            capturer.adaptOutput(
                width: Int32(baseDimensions.width),
                height: Int32(baseDimensions.height),
                framesPerSecond: Int32(
                    encodingRecommendation.maximumFramesPerSecond
                )
            )
            guard let forwardingAuthorization = sink.beginForwarding(
                expectedFrameDimensions: ScreenVideoPixelDimensions(
                    width: format.width,
                    height: format.height
                ),
                expectedScaleFactor: format.expectedScaleFactor,
                expectedContentScale: format.expectedContentScale
            ) else {
                if sink.requiresForwardingStartupRetry {
                    throw ScreenVideoCaptureError.displayModeChangedDuringStart(
                        format.displayID
                    )
                }
                throw WorldwideScreenServiceError.transportUnavailable
            }
            captureForwardingAuthorization = forwardingAuthorization
            try source.beginSampleDelivery()
            try await waitForForwardingStartupProof(
                sink: sink,
                source: source,
                captureAuthorization: authorization,
                forwardingAuthorization: forwardingAuthorization,
                displayID: format.displayID
            )
            guard sink.commitForwardingStartup(
                authorizedBy: forwardingAuthorization
            ) else {
                if sink.requiresForwardingStartupRetry {
                    throw ScreenVideoCaptureError.displayModeChangedDuringStart(
                        format.displayID
                    )
                }
                throw WorldwideScreenServiceError.transportUnavailable
            }
            logger.info(
                "Worldwide screen capture is visible at "
                    + "\(format.width)x\(format.height)@\(format.framesPerSecond) "
                    + "encoderTier=\(String(describing: encodingRecommendation.tier)) "
                    + "encoderFPS=\(encodingRecommendation.maximumFramesPerSecond) "
                    + "encoderScale=\(String(format: "%.2f", encodingRecommendation.scaleResolutionDownBy))"
            )
            return forwardingAuthorization
        } catch {
            let startError = error
            if captureSource === source {
                // A current live format rebuild keeps the acknowledged Show/input generation.
                // Native capture retries roll only capture tokens; terminal rebuild failure is
                // handled by the owner and closes the full session below that boundary.
                revokeCaptureAuthorization(
                    preservingRemoteInput: screenCaptureTransitionIsOwned
                )
            }
            sink.stopForwarding()
            do {
                // Even a failed post-start health check can leave a native SCStream running.
                // Never turn that uncertainty into a protocol-level Inactive acknowledgement.
                try await source.stop()
                if captureSource === source {
                    captureSource = nil
                    captureSink = nil
                    captureDisplayID = nil
                    captureAuthoritativeDisplayBounds = nil
                    captureVideoBaseDimensions = nil
                }
            } catch {
                // Retain the exact source so session shutdown can retry its native stop before
                // process exit. Forwarding and remote input are already synchronously revoked.
                throw WorldwideScreenServiceError.nativeScreenStopFailed(error)
            }
            throw startError
        }
    }

    /// Waits only for the first exact image surface selected for this capture generation. No
    /// frame or geometry becomes control-visible until this proof succeeds; a mismatch is a typed
    /// display transition so the bounded owner can rebuild without publishing stale dimensions.
    private func waitForForwardingStartupProof(
        sink: WorldwideScreenSampleSink,
        source: ScreenVideoCaptureSource,
        captureAuthorization authorization: WebRTCControlAuthorization,
        forwardingAuthorization: WebRTCControlAuthorization,
        displayID: UInt32
    ) async throws {
        for poll in 0...Self.maximumForwardingStartupProofPolls {
            guard captureSink === sink,
                  captureSource === source,
                  captureAuthorization === authorization,
                  authorization.isValid,
                  captureForwardingAuthorization === forwardingAuthorization,
                  transportAllowsCapture else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            switch sink.forwardingStartupProofState(
                authorizedBy: forwardingAuthorization
            ) {
            case .proven:
                return
            case .rejected:
                throw ScreenVideoCaptureError.displayModeChangedDuringStart(displayID)
            case .waiting:
                guard poll < Self.maximumForwardingStartupProofPolls else {
                    throw ScreenVideoCaptureError.displayModeChangedDuringStart(displayID)
                }
                try await Task.sleep(for: Self.forwardingStartupProofPollInterval)
            }
        }
    }

    /// Revokes visibility before awaiting native ScreenCaptureKit shutdown.
    private func stopScreenCapture() async throws {
        revokeCaptureAuthorization()
        let source = captureSource
        let sink = captureSink
        sink?.stopForwarding()
        guard let source else { return }
        do {
            try await source.stop()
        } catch {
            // Preserve ownership for the caller's fail-closed session teardown retry.
            throw error
        }
        if captureSource === source {
            captureSource = nil
            captureSink = nil
            captureDisplayID = nil
            captureAuthoritativeDisplayBounds = nil
            captureVideoBaseDimensions = nil
        }
    }

    /// Handles a native stop only if its source and authorization still own capture.
    private func screenCaptureDidStop(
        source: ScreenVideoCaptureSource,
        authorization: WebRTCControlAuthorization,
        message: String
    ) async {
        guard captureSource === source,
              captureAuthorization === authorization else { return }
        revokeCaptureAuthorization()
        captureSink?.stopForwarding()
        captureSink = nil
        captureSource = nil
        captureVideoBaseDimensions = nil
        logger.error("Worldwide screen capture stopped unexpectedly: \(message)")
        // The viewer's already-acknowledged Show cannot be contradicted by an unsolicited
        // Inactive ACK. Close the session so it cannot retain a frozen visible frame.
        await stop()
    }

    /// Recreates the native screen source and its forwarding generation when a live macOS scale
    /// choice changes the framebuffer. The viewer's already-acknowledged Show remains visible,
    /// while exact source/token identities keep every reentrant control request fail closed.
    private func renegotiateScreenCaptureFormat(
        for sink: WorldwideScreenSampleSink
    ) async {
        if let context = automaticScreenMediaResumeContext {
            if context.finalAcknowledgementCommit.isCommitted {
                // The exact resumed ACK won under the old sink lock. Treat this callback as an
                // ordinary post-resume display rebuild even if the service continuation has not
                // yet cleared its bookkeeping context.
                cancelAutomaticScreenMediaResumeTimeout()
                do {
                    var updatedPolicy = screenVideoAdaptationPolicy
                    updatedPolicy.automaticResumeAttemptSucceeded()
                    screenVideoAdaptationOwner = .init(policy: updatedPolicy,
                        revision: screenVideoAdaptationPolicyRevision, fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
                        lane: screenVideoAdaptationOwner.lane, evidenceTime: screenVideoAdaptationLastEvidenceTime,
                        minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence, applied: appliedScreenVideoRecommendation)
                }
                beginPostResumeScreenVideoAdaptationEpoch()
                automaticScreenMediaResumeContext = nil
            } else {
                if let peer {
                    await failAutomaticScreenMediaResume(
                        peer: peer,
                        attemptID: context.attemptID,
                        reason: "capture geometry changed during the resume proof"
                    )
                } else {
                    resetAutomaticScreenMediaSuspensionState()
                    _ = await stopScreenCaptureOrCloseSession(
                        context: "capture geometry changed without a resume-proof peer"
                    )
                }
                return
            }
        }
        guard screenFormatRenegotiation.admit(
            sink,
            isCurrent: captureSink === sink,
            isAwaitingRenegotiation: sink.isAwaitingFormatRenegotiation
        ) == .begin else {
            return
        }
        guard captureSink === sink,
              let source = captureSource,
              let authorization = captureAuthorization,
              let replacementDisplayID = captureDisplayID,
              authorization.isValid,
              transportAllowsCapture,
              peer != nil else {
            screenFormatRenegotiation.fail(owner: sink)
            _ = screenFormatRenegotiation.finish(owner: sink)
            return
        }
        let visibilityCommandEpoch = screenVisibilityCommandEpoch
        let renegotiationPeerGeneration = peerGeneration
        let renegotiationRecoveryEpoch = recoveryProofEpoch
        let startupOwner = ScreenCaptureStartupOwner(
            visibilityCommandEpoch: visibilityCommandEpoch,
            peerGeneration: renegotiationPeerGeneration,
            recoveryEpoch: renegotiationRecoveryEpoch
        )
        defer {
            if let pendingSink = screenFormatRenegotiation.finish(owner: sink) {
                Task { [weak self] in
                    await self?.renegotiateScreenCaptureFormat(for: pendingSink)
                }
            }
        }

        logger.info("Renegotiating worldwide screen capture after display mode change")
        captureDisplayID = nil
        captureAuthoritativeDisplayBounds = nil
        captureForwardingAuthorization?.revoke()
        captureForwardingAuthorization = nil
        remoteInputController.updateScreenVideoFrameGeometry(
            nil,
            ownerToken: remoteInputOwnerToken
        )
        do {
            try await source.stop()
            guard captureSink === sink,
                  captureSource === source,
                  captureAuthorization === authorization,
                  authorization.isValid,
                  transportAllowsCapture else {
                screenFormatRenegotiation.fail(owner: sink)
                return
            }

            sink.stopForwarding()
            authorization.revoke()
            captureSource = nil
            captureSink = nil
            captureAuthorization = nil
            captureVideoBaseDimensions = nil

            _ = try await startScreenCaptureWithDisplayModeRetries(
                requiredDisplayID: replacementDisplayID,
                owner: startupOwner
            )
            logger.info("Worldwide screen capture format renegotiation completed")
        } catch {
            let renegotiationError = error
            let wasSuperseded = Self.screenFormatRenegotiationWasSuperseded(
                visibilityCommandEpoch: visibilityCommandEpoch,
                currentVisibilityCommandEpoch: screenVisibilityCommandEpoch,
                peerGeneration: renegotiationPeerGeneration,
                currentPeerGeneration: peerGeneration,
                recoveryEpoch: renegotiationRecoveryEpoch,
                currentRecoveryEpoch: recoveryProofEpoch,
                serviceIsStopped: isStopped
            )
            // Close post-ACK preservation synchronously before any failure path yields.
            screenFormatRenegotiation.fail(owner: sink)
            if captureSink === sink,
               captureSource === source,
               captureAuthorization === authorization {
                sink.stopForwarding()
                authorization.revoke()
                captureForwardingAuthorization?.revoke()
                captureForwardingAuthorization = nil
                captureDisplayID = nil
                captureAuthoritativeDisplayBounds = nil
            }
            if wasSuperseded {
                logger.info(
                    "Worldwide screen capture format renegotiation yielded to newer lifecycle state"
                )
                return
            }
            logger.error(
                "Worldwide screen capture format renegotiation failed: " +
                renegotiationError.localizedDescription
            )
            // No unsolicited Inactive ACK can safely replace the viewer's acknowledged Show.
            // Closing the session prevents a terminal rebuild failure from freezing its last frame.
            await stop()
        }
    }

    /// A newer visibility command, peer, recovery epoch, or completed service owns any failure
    /// observed after replacement startup yields. The retired rebuild must not close that owner.
    nonisolated static func screenFormatRenegotiationWasSuperseded(
        visibilityCommandEpoch: UInt64,
        currentVisibilityCommandEpoch: UInt64,
        peerGeneration: UInt64,
        currentPeerGeneration: UInt64,
        recoveryEpoch: UInt64,
        currentRecoveryEpoch: UInt64,
        serviceIsStopped: Bool
    ) -> Bool {
        serviceIsStopped
            || visibilityCommandEpoch != currentVisibilityCommandEpoch
            || peerGeneration != currentPeerGeneration
            || recoveryEpoch != currentRecoveryEpoch
    }

    // MARK: - Native system audio

    /// Starts audio for a healthy route and closes on non-recoverable startup failure.
    private func startSystemAudioOrStopSession() async -> Bool {
        guard featureProfile.allowsSystemAudio else { return true }
        guard !systemAudioStartInProgress else { return false }
        do {
            try await startSystemAudio()
            return !isStopped
                && systemAudioIsLive
                && audioSource != nil
                && audioAuthorization?.isValid == true
        } catch {
            guard !isStopped else { return false }
            if isRecovering
                || recoveryProofRequired
                || !transportAllowsCapture
                || isTransportAudioStartCancellation(error) {
                logger.debug(
                    "Worldwide system audio startup yielded to transport recovery: " +
                    error.localizedDescription
                )
                return false
            }
            logger.error("Worldwide system audio failed to start: \(error.localizedDescription)")
            await stop()
            return false
        }
    }

    /// Identifies expected audio-start cancellation caused by concurrent route revocation.
    private func isTransportAudioStartCancellation(_ error: Error) -> Bool {
        guard let transportError = error as? WebRTCTransportError else { return false }
        switch transportError {
        case .transportNotHealthy, .audioAuthorizationRevoked, .transportClosed:
            return true
        default:
            return false
        }
    }

    /// Starts 48 kHz stereo system audio behind a revocable transport authorization.
    ///
    /// Same-peer recovery reuses the exact continuously monitored native source and sink, while
    /// installing a fresh route authorization before forwarding can reopen.
    private func startSystemAudio() async throws {
        guard !systemAudioStartInProgress,
              transportAllowsCapture else {
            throw WorldwideScreenServiceError.transportUnavailable
        }
        guard let peer,
              let capturer = peer.externalAudioCapturer else {
            throw WorldwideScreenServiceError.audioCapturerUnavailable
        }
        let generation = peerGeneration
        let mode: WorldwideSystemAudioStartMode?
        do {
            mode = try WorldwideSystemAudioRecoveryPolicy.startMode(
                isLive: systemAudioIsLive,
                isPausedForRecovery:
                    systemAudioIsPausedForTransportRecovery,
                hasSource: audioSource != nil,
                hasSink: audioSink != nil,
                hasValidAuthorization:
                    audioAuthorization?.isValid == true,
                peerGenerationMatches:
                    audioPeerGeneration == generation
            )
        } catch {
            logger.error("Worldwide system-audio start refused a Rust policy bridge fault")
            throw WorldwideScreenServiceError.transportUnavailable
        }
        guard let mode else {
            throw WorldwideScreenServiceError.transportUnavailable
        }
        if mode == .alreadyLive { return }

        systemAudioStartInProgress = true
        defer { systemAudioStartInProgress = false }

        if mode == .resumeExisting {
            guard let source = audioSource,
                  let sink = audioSink else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            try await resumeSystemAudio(
                source: source,
                sink: sink,
                peer: peer,
                capturer: capturer,
                peerGeneration: generation
            )
            return
        }

        let authorization = WebRTCAudioAuthorization()
        let sink = WorldwideSystemAudioSampleSink(
            capturer: capturer,
            captureLifetime: captureLifetime,
            didObserveMacFaceTimeActivity: {
                [weak self]
                source,
                callbackAuthorization,
                observation,
                evidenceAuthorization in
                Task {
                    await self?.macFaceTimeActivityDidChange(
                        source: source,
                        authorization: callbackAuthorization,
                        observation: observation,
                        evidenceAuthorization: evidenceAuthorization
                    )
                }
            },
            didStop: { [weak self] source, stoppedSink, message in
                Task {
                    await self?.systemAudioCaptureDidStop(
                        source: source,
                        sink: stoppedSink,
                        message: message
                    )
                }
            }
        )
        let source = SystemAudioCaptureSource(
            displayID: systemAudioDisplayID,
            consumer: sink,
            makeStopWatchdog: makeNativeCaptureWatchdog,
            logger: logger
        )
        audioSink = sink
        audioSource = source
        audioAuthorization = authorization
        audioPeerGeneration = generation
        systemAudioIsPausedForTransportRecovery = false
        highestMacFaceTimeObservationSequence = 0

        var nativeSourceStarted = false
        do {
            let format = try await source.start()
            nativeSourceStarted = true
            guard audioSource === source,
                  audioSink === sink,
                  audioAuthorization === authorization,
                  authorization.isValid,
                  transportAllowsCapture,
                  self.peer === peer,
                  peerGeneration == generation,
                  audioPeerGeneration == generation else {
                throw WorldwideScreenServiceError.transportUnavailable
            }

            try await peer.enableSystemAudioIfTransportHealthy(
                authorization: authorization
            )
            guard audioSource === source,
                  audioSink === sink,
                  audioAuthorization === authorization,
                  authorization.isValid,
                  transportAllowsCapture,
                  self.peer === peer,
                  peerGeneration == generation,
                  audioPeerGeneration == generation,
                  sink.beginForwarding(with: authorization),
                  authorization.isValid else {
                throw WorldwideScreenServiceError.transportUnavailable
            }

            systemAudioIsLive = true
            systemAudioIsPausedForTransportRecovery = false
            installCurrentMacHostedCallChallenge(on: source)
            logger.info(
                "Worldwide system audio is live from display \(format.displayID) at " +
                "\(format.sampleRate) Hz, \(format.channelCount) channels"
            )
        } catch {
            let startError = error
            let stillOwnsNativeSource = audioSource === source
                && audioSink === sink
                && audioPeerGeneration == generation
            if nativeSourceStarted, stillOwnsNativeSource {
                pauseSystemAudioForTransportUncertainty()
                await peer.suspendSystemAudioForTransportUncertainty()
                capturer.reset()

                // A healthy event may complete while native startup is suspended. Resume now so
                // no additional peer event is required to reopen the same source.
                if transportAllowsCapture,
                   self.peer === peer,
                   peerGeneration == generation {
                    try await resumeSystemAudio(
                        source: source,
                        sink: sink,
                        peer: peer,
                        capturer: capturer,
                        peerGeneration: generation
                    )
                    return
                }
            } else if stillOwnsNativeSource {
                revokeSystemAudioAuthorization()
                sink.stopForwarding()
                do {
                    try await source.stop()
                    if audioSource === source, audioSink === sink {
                        audioSource = nil
                        audioSink = nil
                        audioPeerGeneration = nil
                    }
                } catch {
                    throw WorldwideScreenServiceError.nativeSystemAudioStopUnconfirmed
                }
            } else {
                authorization.revoke()
                sink.stopForwarding()
            }
            throw startError
        }
    }

    /// Reopens the same native source only after the peer accepts a fresh audio capability.
    private func resumeSystemAudio(
        source: SystemAudioCaptureSource,
        sink: WorldwideSystemAudioSampleSink,
        peer: WebRTCPeer,
        capturer: MacExternalAudioCapturer,
        peerGeneration generation: UInt64
    ) async throws {
        guard audioSource === source,
              audioSink === sink,
              audioPeerGeneration == generation,
              peerGeneration == generation,
              self.peer === peer,
              transportAllowsCapture,
              audioAuthorization == nil else {
            throw WorldwideScreenServiceError.transportUnavailable
        }

        let authorization = WebRTCAudioAuthorization()
        audioAuthorization = authorization
        do {
            try await peer.enableSystemAudioIfTransportHealthy(
                authorization: authorization
            )
            guard audioSource === source,
                  audioSink === sink,
                  audioPeerGeneration == generation,
                  peerGeneration == generation,
                  self.peer === peer,
                  audioAuthorization === authorization,
                  authorization.isValid,
                  transportAllowsCapture,
                  sink.beginForwarding(with: authorization),
                  authorization.isValid else {
                throw WorldwideScreenServiceError.transportUnavailable
            }
            systemAudioIsLive = true
            systemAudioIsPausedForTransportRecovery = false
            installCurrentMacHostedCallChallenge(on: source)
            logger.info(
                "Worldwide system audio resumed on the recovered route"
            )
        } catch {
            if audioSource === source,
               audioSink === sink,
               audioPeerGeneration == generation {
                pauseSystemAudioForTransportUncertainty()
            } else {
                authorization.revoke()
                sink.stopForwarding()
            }
            await peer.suspendSystemAudioForTransportUncertainty()
            capturer.reset()
            throw error
        }
    }

    /// Recovery closes transport capabilities but keeps native call monitoring continuous.
    private func stopSystemAudioForTransportUncertainty(_ reason: String) async {
        guard audioSource != nil || audioAuthorization != nil else {
            return
        }
        pauseSystemAudioForTransportUncertainty()
        logger.info(
            "Paused worldwide system-audio forwarding because \(reason); " +
                "native call monitoring remains continuous"
        )
    }

    /// Revokes forwarding, suspends the track, resets buffered PCM, and stops native capture.
    @discardableResult
    private func stopSystemAudio() async -> Bool {
        revokeSystemAudioAuthorization()
        let source = audioSource
        let sink = audioSink
        sink?.stopForwarding()
        await peer?.suspendSystemAudioForTransportUncertainty()
        peer?.externalAudioCapturer?.reset()
        guard let source else { return true }
        do {
            try await source.stop()
        } catch {
            logger.error("Worldwide system audio stop failed: \(error.localizedDescription)")
            return false
        }
        if audioSource === source {
            audioSource = nil
            audioSink = nil
            audioPeerGeneration = nil
        }
        return true
    }

    /// Installs a viewer nonce only while this actor owns the exact live process-tap source. The
    /// source performs a new native scan after serially installing the nonce.
    private func installMacHostedCallChallenge(
        _ challenge: WebRTCMacHostedCallChallenge,
        sourcePeer: WebRTCPeer,
        sourcePeerGeneration: UInt64
    ) {
        guard featureProfile.allowsSystemAudio,
              peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              sourcePeerGeneration > 0 else {
            return
        }
        guard challenge.isValid else {
            macHostedCallChallenge = nil
            macHostedCallChallengePeerGeneration = nil
            return
        }
        macHostedCallChallenge = challenge
        macHostedCallChallengePeerGeneration = sourcePeerGeneration
        guard let source = audioSource,
              audioAuthorization?.isValid == true,
              systemAudioIsLive,
              transportAllowsCapture else {
            return
        }
        installCurrentMacHostedCallChallenge(on: source)
    }

    /// Reinstalls the actor's current challenge after a route authorization rollover.
    private func installCurrentMacHostedCallChallenge(
        on source: SystemAudioCaptureSource
    ) {
        do {
            guard audioSource === source,
                  try WorldwideMacHostedCallPeerGenerationPolicy.admits(
                      audioPeerGeneration: audioPeerGeneration,
                      challengePeerGeneration:
                          macHostedCallChallengePeerGeneration,
                      currentPeerGeneration: peerGeneration,
                      producer: hostedCallPolicyProducer
                  ),
                  let challenge = macHostedCallChallenge,
                  challenge.isValid else {
                return
            }
            _ = source.installMacFaceTimeActivityChallenge(
                SystemAudioMacFaceTimeActivityChallenge(
                    sequence: challenge.sequence,
                    nonce: challenge.nonce,
                    callEpochNonce: challenge.callEpochNonce
                )
            )
        } catch {
            logger.error("Mac-hosted call challenge refused a Rust policy bridge fault")
        }
    }

    /// Binds every activity heartbeat to the exact live capture source, authorization, peer,
    /// challenge, and monotonically stamped native observation before it reaches the wire.
    private func macFaceTimeActivityDidChange(
        source: SystemAudioCaptureSource,
        authorization: WebRTCAudioAuthorization,
        observation: SystemAudioMacFaceTimeActivityObservation,
        evidenceAuthorization:
            WebRTCMacHostedCallEvidenceAuthorization
    ) async {
        do {
            guard audioSource === source,
                  audioAuthorization === authorization,
                  authorization.isValid,
                  systemAudioIsLive,
                  transportAllowsCapture,
                  try WorldwideMacHostedCallPeerGenerationPolicy.admits(
                      audioPeerGeneration: audioPeerGeneration,
                      challengePeerGeneration: macHostedCallChallengePeerGeneration,
                      currentPeerGeneration: peerGeneration,
                      producer: hostedCallPolicyProducer
                  ),
                  let challenge = macHostedCallChallenge else { return }
            var admittedPeer: WebRTCPeer?
            guard let evidenceState = try consumeMacHostedCallObservationAfterNativeGuards(
                observation: observation, challenge: challenge,
                exactPeerIsPresent: {
                    guard let currentPeer = self.peer,
                          self.peer === currentPeer else { return false }
                    admittedPeer = currentPeer
                    return true
                }
            ), let peer = admittedPeer else { return }
            do {
                try await peer.updateMacHostedCallEvidenceIfTransportHealthy(
                    state: evidenceState,
                    challenge: challenge,
                    nativeObservationSequence:
                        observation.observationSequence,
                    authorization: authorization,
                    evidenceAuthorization: evidenceAuthorization
                )
            } catch let error as WebRTCTransportError {
                switch error {
                case .transportNotHealthy,
                     .audioAuthorizationRevoked,
                     .macHostedCallEvidenceAuthorizationRevoked,
                     .transportClosed:
                    // A missing heartbeat is intentionally fail-closed on the iPhone.
                    break
                default:
                    logger.error(
                        "Mac-hosted call evidence send failed: "
                            + error.localizedDescription
                    )
                }
            } catch {
                logger.error(
                    "Mac-hosted call evidence send failed: "
                        + error.localizedDescription
                )
            }
        } catch {
            logger.error("Mac-hosted call evidence refused a Rust policy bridge fault")
        }
    }

    /// Fails the consume-once session when its current native audio source stops unexpectedly.
    private func systemAudioCaptureDidStop(
        source: SystemAudioCaptureSource,
        sink: WorldwideSystemAudioSampleSink,
        message: String
    ) async {
        guard audioSource === source,
              audioSink === sink else { return }
        revokeSystemAudioAuthorization()
        audioSink = nil
        audioSource = nil
        audioPeerGeneration = nil
        await peer?.suspendSystemAudioForTransportUncertainty()
        peer?.externalAudioCapturer?.reset()
        logger.error("Worldwide system audio stopped unexpectedly: \(message)")
        await stop()
    }

    /// Revokes one route while retaining the exact source/sink and native causal binder.
    private func pauseSystemAudioForTransportUncertainty() {
        systemAudioIsLive = false
        systemAudioIsPausedForTransportRecovery =
            audioSource != nil
                && audioSink != nil
                && audioPeerGeneration == peerGeneration
        let authorization = audioAuthorization
        audioAuthorization = nil
        audioSink?.stopForwarding()
        authorization?.revoke()
        peer?.externalAudioCapturer?.reset()
    }

    /// Synchronously closes audio authorization and clears external capturer buffers.
    private func revokeSystemAudioAuthorization() {
        systemAudioIsLive = false
        systemAudioIsPausedForTransportRecovery = false
        macHostedCallChallenge = nil
        macHostedCallChallengePeerGeneration = nil
        highestMacFaceTimeObservationSequence = 0
        let authorization = audioAuthorization
        audioAuthorization = nil
        audioSink?.stopForwarding()
        authorization?.revoke()
        peer?.externalAudioCapturer?.reset()
    }

    /// Revokes remote input before the screen capability that authorized it.
    private func revokeCaptureAuthorization(
        preservingRemoteInput: Bool = false
    ) {
        // Input revocation is first and synchronous: no queued tap or key may outlive the
        // screen authorization boundary that made the capability valid.
        if !preservingRemoteInput {
            revokeRemoteInputAuthorization()
        }
        captureDisplayID = nil
        captureAuthoritativeDisplayBounds = nil
        captureForwardingAuthorization?.revoke()
        captureForwardingAuthorization = nil
        captureAuthorization?.revoke()
        captureAuthorization = nil
    }
}

/// Actor-owned handoff for sequential live capture-format rebuilds.
/// A queued sink remains explicit until the next task atomically claims it.
struct ScreenFormatRenegotiationCoordinator<Sink: AnyObject> {
    enum Phase: Equatable {
        case idle
        case rebuilding
        case queued
        case failed
    }

    enum Admission: Equatable {
        case begin
        case coalesced
        case rejected
    }

    private(set) var phase = Phase.idle
    private(set) var owner: Sink?
    private(set) var pending: Sink?

    mutating func admit(
        _ sink: Sink,
        isCurrent: Bool,
        isAwaitingRenegotiation: Bool
    ) -> Admission {
        switch phase {
        case .idle:
            guard owner == nil,
                  pending == nil,
                  isCurrent,
                  isAwaitingRenegotiation else {
                return .rejected
            }
            owner = sink
            phase = .rebuilding
            return .begin

        case .rebuilding:
            guard let owner else { return .rejected }
            guard owner !== sink,
                  isCurrent,
                  isAwaitingRenegotiation else {
                return .coalesced
            }
            pending = sink
            return .coalesced

        case .queued:
            guard owner == nil else { return .rejected }
            if pending !== sink {
                guard isCurrent, isAwaitingRenegotiation else {
                    return .rejected
                }
                pending = sink
            }
            guard isCurrent, isAwaitingRenegotiation else {
                pending = nil
                phase = .idle
                return .rejected
            }
            pending = nil
            owner = sink
            phase = .rebuilding
            return .begin

        case .failed:
            return .rejected
        }
    }

    mutating func fail(owner expectedOwner: Sink) {
        guard owner === expectedOwner else { return }
        phase = .failed
    }

    /// Releases the exact owner and returns a queued sink without erasing its queued identity.
    mutating func finish(owner expectedOwner: Sink) -> Sink? {
        guard owner === expectedOwner else { return nil }
        owner = nil
        if phase == .failed {
            pending = nil
            phase = .idle
            return nil
        }
        guard let pending else {
            phase = .idle
            return nil
        }
        phase = .queued
        return pending
    }
}

/// Wire feedback plus the local decision to revoke the current input capability.
private struct RemoteInputTransportFeedback {
    let result: WebRTCInputFeedbackResult
    let rejectionReason: WebRTCInputRejectionReason?
    let screenFormatChanging: Bool
    let focus: WebRTCInputFocus
    let windowResize: WebRTCWindowResizeFeedback?
    let windowMove: WebRTCWindowMoveFeedback?
    let revokesSession: Bool

    static func accepted(
        focus: WebRTCInputFocus,
        windowResize: WebRTCWindowResizeFeedback? = nil,
        windowMove: WebRTCWindowMoveFeedback? = nil
    ) -> Self {
        Self(
            result: .accepted,
            rejectionReason: nil,
            screenFormatChanging: false,
            focus: focus,
            windowResize: windowResize,
            windowMove: windowMove,
            revokesSession: false
        )
    }

    static func rejected(
        reason: WebRTCInputRejectionReason,
        screenFormatChanging: Bool = false,
        focus: WebRTCInputFocus = .none,
        revokesSession: Bool
    ) -> Self {
        Self(
            result: .rejected,
            rejectionReason: reason,
            screenFormatChanging: screenFormatChanging,
            focus: focus,
            windowResize: nil,
            windowMove: nil,
            revokesSession: revokesSession
        )
    }
}

/// Hide request used as proof that a particular recovery epoch is media-inactive.
private struct PendingRecoveryProofRequest: Equatable {
    let id: UInt64
    let epoch: UInt64
}

/// Transport capability and revocable authorization installed for one Show request.
private struct ArmedRemoteInputSession: Sendable {
    let capability: WebRTCInputCapability
    let authorization: WebRTCInputAuthorization
    let activation: MacRemoteInputPreparedActivation
}

/// Thread-safe gate between ScreenCaptureKit callbacks and the WebRTC video capturer.
///
/// The lock closes forwarding synchronously on actor-driven revocation or native stop;
/// samples arriving after either boundary are discarded before touching WebRTC.
protocol WorldwideScreenFrameCapturing: AnyObject, Sendable {
    func captureScreenFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime)
}

extension MacExternalVideoCapturer: WorldwideScreenFrameCapturing {
    func captureScreenFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        capture(pixelBuffer: pixelBuffer, timestamp: timestamp)
    }
}

/// The only remote-input capability needed by the screen-sample boundary. Keeping this narrow
/// makes geometry continuity independently testable without exposing input injection itself.
protocol WorldwideRemoteInputGeometryUpdating: Sendable {
    func updateScreenVideoFrameGeometry(
        _ geometry: ScreenVideoFrameGeometry?,
        ownerToken: MacRemoteInputOwnerToken
    )
}

extension MacRemoteInputController: WorldwideRemoteInputGeometryUpdating {}

final class WorldwideScreenSampleSink: ScreenVideoSampleConsumer, @unchecked Sendable {
    typealias FormatRenegotiationFallbackScheduler =
        @Sendable (
            _ delay: TimeInterval,
            _ action: @escaping @Sendable () -> Void
        ) -> Void

    static let formatRenegotiationFallbackDelay =
        ScreenVideoFormatRenegotiationDetector.fallbackDelay
    /// While the viewer is covered, a lossy 32 kbps path needs later source frames so RTX/PLI can
    /// recover from a dropped first real key frame. Keep that recovery lane strictly bounded and
    /// far below ordinary capture rate; the service's independent 12-second proof timeout is the
    /// terminal fence.
    private static let automaticResumeRealFrameRetryIntervalSeconds = 1.0
    private static let maximumAutomaticResumeRealFrameCount = 12

    private enum ForwardingPhase: Equatable {
        case ready
        case starting
        case active
        case resumeMarkerBlocked
        case resumeRealArmed
        case resumeAwaitingPresentation
        case renegotiating
        case stopped

        var diagnosticName: String {
            switch self {
            case .ready: "ready"
            case .starting: "starting"
            case .active: "active"
            case .resumeMarkerBlocked: "resumeMarkerBlocked"
            case .resumeRealArmed: "resumeRealArmed"
            case .resumeAwaitingPresentation: "resumeAwaitingPresentation"
            case .renegotiating: "renegotiating"
            case .stopped: "stopped"
            }
        }
    }

    struct ResumeMarkerBoundary: Equatable, Sendable {
        let revision: UInt64
        let geometry: ScreenVideoFrameGeometry
    }

    enum ForwardingStartupProofState: Equatable {
        case waiting
        case proven
        case rejected
    }

    private let capturer: any WorldwideScreenFrameCapturing
    private let remoteInputController: any WorldwideRemoteInputGeometryUpdating
    private let remoteInputOwnerToken: MacRemoteInputOwnerToken
    private let didRequireCaptureFormatRenegotiation:
        @Sendable (WorldwideScreenSampleSink) -> Void
    private let didStop: @Sendable (ScreenVideoCaptureSource, String) -> Void
    private let scheduleFormatRenegotiationFallback:
        FormatRenegotiationFallbackScheduler
    private weak var captureLifetime: CaptureServiceLifetime?
    private let captureLifetimeIsRequired: Bool
    private let lock = NSLock()
    private var forwardingPhase = ForwardingPhase.ready
    private var formatIsProven = false
    /// Set by Core Graphics' begin-configuration callback before any same-surface transition
    /// frame can inherit the preceding coordinate transform. Only the settled callback clears it.
    private var displayConfigurationInProgress = false
    private var expectedFrameDimensions: ScreenVideoPixelDimensions?
    private var expectedFrameScaleFactor: Double?
    private var expectedFrameContentScale: Double?
    /// Last concrete geometry admitted by the format detector for the current forwarding
    /// generation. A later frame whose optional ScreenCaptureKit geometry is absent may inherit
    /// this transform only while its pixel surface is still exactly the same size.
    private var lastProvenFrameGeometry: ScreenVideoFrameGeometry?
    private var lastFrameMetadataState = WorldwideScreenFrameMetadataDiagnosticState.none
    private var lastFrameSurfaceWidth: Int?
    private var lastFrameSurfaceHeight: Int?
    private var forwardingAuthorization: WebRTCControlAuthorization?
    private var resumeBoundaryRevision: UInt64 = 0
    private var resumeBoundaryGeometry: ScreenVideoFrameGeometry?
    private var automaticResumeRealFrameCount = 0
    private var lastAutomaticResumeRealFrameTimestampSeconds: Double?
    private var formatRenegotiationDetector = ScreenVideoFormatRenegotiationDetector()
    private var nextFormatRenegotiationFallbackToken: UInt64 = 0
    private var scheduledFormatRenegotiationFallbackToken: UInt64?

    init(
        capturer: any WorldwideScreenFrameCapturing,
        captureLifetime: CaptureServiceLifetime? = nil,
        remoteInputController: any WorldwideRemoteInputGeometryUpdating,
        remoteInputOwnerToken: MacRemoteInputOwnerToken = MacRemoteInputOwnerToken(),
        didRequireCaptureFormatRenegotiation: @escaping @Sendable (
            WorldwideScreenSampleSink
        ) -> Void,
        scheduleFormatRenegotiationFallback:
            @escaping FormatRenegotiationFallbackScheduler = { delay, action in
                DispatchQueue.global(qos: .userInitiated).asyncAfter(
                    deadline: .now() + delay,
                    execute: action
                )
            },
        didStop: @escaping @Sendable (ScreenVideoCaptureSource, String) -> Void
    ) {
        self.capturer = capturer
        self.captureLifetime = captureLifetime
        captureLifetimeIsRequired = captureLifetime != nil
        self.remoteInputController = remoteInputController
        self.remoteInputOwnerToken = remoteInputOwnerToken
        self.didRequireCaptureFormatRenegotiation =
            didRequireCaptureFormatRenegotiation
        self.scheduleFormatRenegotiationFallback =
            scheduleFormatRenegotiationFallback
        self.didStop = didStop
    }

    /// Opens the callback gate after capture and transport health are proven.
    func beginForwarding(
        expectedFrameDimensions: ScreenVideoPixelDimensions? = nil,
        expectedScaleFactor: Double? = nil,
        expectedContentScale: Double? = nil
    ) -> WebRTCControlAuthorization? {
        guard lifetimeAllowsCapture else { return nil }
        let authorization = WebRTCControlAuthorization()
        let transition = lock.withLock { () -> (
            installed: Bool,
            retiredAuthorization: WebRTCControlAuthorization?
        ) in
            guard lifetimeAllowsCapture, forwardingPhase == .ready else {
                return (false, nil)
            }
            remoteInputController.updateScreenVideoFrameGeometry(
                nil,
                ownerToken: remoteInputOwnerToken
            )
            invalidateFormatRenegotiationFallbackLocked()
            formatRenegotiationDetector.reset()
            let retiredAuthorization = forwardingAuthorization
            forwardingAuthorization = authorization
            forwardingPhase = .starting
            displayConfigurationInProgress = false
            self.expectedFrameDimensions = expectedFrameDimensions
            expectedFrameScaleFactor = expectedScaleFactor
            expectedFrameContentScale = expectedContentScale
            lastProvenFrameGeometry = nil
            lastFrameMetadataState = .none
            lastFrameSurfaceWidth = nil
            lastFrameSurfaceHeight = nil
            automaticResumeRealFrameCount = 0
            lastAutomaticResumeRealFrameTimestampSeconds = nil
            formatIsProven = expectedFrameDimensions == nil
            return (true, retiredAuthorization)
        }
        transition.retiredAuthorization?.revoke()
        return transition.installed ? authorization : nil
    }

    /// Reports whether a delivered frame has proved the exact output surface selected at start.
    /// Authorization validity is checked before taking the sink lock, preserving the global
    /// authorization-then-sink lock order used by remote input.
    func forwardingStartupProofState(
        authorizedBy authorization: WebRTCControlAuthorization
    ) -> ForwardingStartupProofState {
        guard authorization.isValid else { return .rejected }
        return lock.withLock {
            guard forwardingAuthorization === authorization,
                  callbackGateAllowsEntry else {
                return .rejected
            }
            guard forwardingPhase == .starting else {
                return forwardingPhase == .active && formatIsProven
                    ? .proven
                    : .rejected
            }
            return formatIsProven ? .proven : .waiting
        }
    }

    /// Publishes the control-visible generation only after source delivery is fully armed.
    func commitForwardingStartup(
        authorizedBy authorization: WebRTCControlAuthorization
    ) -> Bool {
        let committed = lock.withLock { () -> Bool in
            guard forwardingPhase == .starting,
                  formatIsProven,
                  forwardingAuthorization === authorization,
                  callbackGateAllowsEntry else {
                return false
            }
            forwardingPhase = .active
            expectedFrameDimensions = nil
            expectedFrameScaleFactor = nil
            expectedFrameContentScale = nil
            return true
        }
        return committed && authorization.isValid
    }

    /// Returns the exact frame transform already admitted for this Show generation.
    ///
    /// Remote input arms after native capture startup. Handing this snapshot to the controller
    /// prevents an otherwise static screen from waiting indefinitely for another post-arm frame.
    func remoteInputStartupGeometry(
        authorizedBy authorization: WebRTCControlAuthorization
    ) -> ScreenVideoFrameGeometry? {
        guard authorization.isValid else { return nil }
        return lock.withLock {
            guard forwardingAuthorization === authorization,
                  forwardingPhase == .active,
                  formatIsProven,
                  callbackGateAllowsEntry else {
                return nil
            }
            return lastProvenFrameGeometry
        }
    }

    /// Distinguishes a retriable display transition from terminal startup unavailability.
    var requiresForwardingStartupRetry: Bool {
        lock.withLock {
            forwardingPhase == .renegotiating
                || (forwardingPhase == .starting && !formatIsProven)
        }
    }

    /// Lets the actor preserve an already-linearized Active ACK while its exact rebuild owns it.
    var isAwaitingFormatRenegotiation: Bool {
        lock.withLock { forwardingPhase == .renegotiating }
    }

    /// Preserves only a control response that already linearized before a changed frame entered
    /// the bounded debounce window. New control and input admission still require proven format.
    var isDebouncingFormatRenegotiation: Bool {
        lock.withLock {
            forwardingPhase == .active
                && !formatIsProven
                && forwardingAuthorization != nil
                && callbackGateAllowsEntry
        }
    }

    /// Keeps the already-acknowledged screen/input generation owned after Core Graphics begins a
    /// display transaction and before its settled callback can start the exact capture rebuild.
    var isDisplayConfigurationInProgress: Bool {
        lock.withLock {
            displayConfigurationInProgress
                && (forwardingPhase == .starting || forwardingPhase == .active)
                && callbackGateAllowsEntry
        }
    }

    /// Privacy-safe capture state sampled by the actor only after admission rejected an input.
    func remoteInputFormatDiagnosticSnapshot() -> WorldwideScreenCaptureGateDiagnostic {
        lock.withLock {
            WorldwideScreenCaptureGateDiagnostic(
                phase: forwardingPhase.diagnosticName,
                formatIsProven: formatIsProven,
                displayConfigurationInProgress: displayConfigurationInProgress,
                frameMetadataState: lastFrameMetadataState,
                frameSurfaceWidth: lastFrameSurfaceWidth,
                frameSurfaceHeight: lastFrameSurfaceHeight,
                retainedProvenGeometry: lastProvenFrameGeometry != nil
            )
        }
    }

    /// Atomically proves that a control/input operation belongs to the current visible format.
    func allowsActiveUse(
        authorizedBy authorization: WebRTCControlAuthorization
    ) -> Bool {
        guard allowsActiveUseWhileAuthorizationHeld(authorization) else { return false }
        return authorization.isValid
    }

    /// Rechecks the sink-owned half of the forwarding generation while the caller already holds
    /// the token. No sink path acquires that token while holding this lock, so remote input can
    /// close the precheck-to-injection race without introducing an authorization/sink ABBA cycle.
    func allowsActiveUseWhileAuthorizationHeld(
        _ authorization: WebRTCControlAuthorization
    ) -> Bool {
        lock.withLock {
            forwardingPhase == .active
                && formatIsProven
                && forwardingAuthorization === authorization
                && callbackGateAllowsEntry
        }
    }

    /// Closes the ScreenCaptureKit-to-WebRTC callback gate on the source's exact sample queue.
    /// The returned revision and geometry are the only capture generation a later marker/real
    /// proof may reopen. Remote input is cleared before this method returns.
    func beginAutomaticResumeMarkerGate(
        authorizedBy authorization: WebRTCControlAuthorization
    ) -> ResumeMarkerBoundary? {
        let boundary: ResumeMarkerBoundary?
        do {
            boundary = try authorization.withValidAuthorization {
                lock.withLock { () -> ResumeMarkerBoundary? in
                    guard forwardingPhase == .active,
                          formatIsProven,
                          forwardingAuthorization === authorization,
                          callbackGateAllowsEntry,
                          let geometry = lastProvenFrameGeometry else {
                        return nil
                    }
                    resumeBoundaryRevision &+= 1
                    if resumeBoundaryRevision == 0 { resumeBoundaryRevision = 1 }
                    resumeBoundaryGeometry = geometry
                    automaticResumeRealFrameCount = 0
                    lastAutomaticResumeRealFrameTimestampSeconds = nil
                    forwardingPhase = .resumeMarkerBlocked
                    return ResumeMarkerBoundary(
                        revision: resumeBoundaryRevision,
                        geometry: geometry
                    )
                }
            }
        } catch {
            return nil
        }
        guard let boundary else { return nil }
        remoteInputController.updateScreenVideoFrameGeometry(
            nil,
            ownerToken: remoteInputOwnerToken
        )
        return boundary
    }

    /// Opens exactly one current-generation real frame after the marker was presented. This is
    /// invoked behind a second source sample-queue barrier, so no callback queued before the
    /// viewer's proof can acquire the newly opened gate.
    func armAutomaticResumeRealFrame(
        boundary: ResumeMarkerBoundary,
        authorizedBy authorization: WebRTCControlAuthorization
    ) -> Bool {
        do {
            return try authorization.withValidAuthorization {
                lock.withLock {
                    guard forwardingPhase == .resumeMarkerBlocked,
                          formatIsProven,
                          forwardingAuthorization === authorization,
                          resumeBoundaryRevision == boundary.revision,
                          resumeBoundaryGeometry == boundary.geometry,
                          lastProvenFrameGeometry == boundary.geometry,
                          callbackGateAllowsEntry else {
                        return false
                    }
                    forwardingPhase = .resumeRealArmed
                    automaticResumeRealFrameCount = 0
                    lastAutomaticResumeRealFrameTimestampSeconds = nil
                    return true
                }
            }
        } catch {
            return false
        }
    }

    /// Reopens ordinary delivery only after the receiver proves a current real frame. Geometry is
    /// republished for the fresh input capability after the proof wins the authorization race.
    func commitAutomaticResume(
        boundary: ResumeMarkerBoundary,
        authorizedBy authorization: WebRTCControlAuthorization
    ) -> Bool {
        do {
            try withAutomaticResumeCommitAuthorization(
                boundary: boundary,
                authorizedBy: authorization
            ) {
                // Deterministic tests and non-wire callers need only the atomic local commit.
            }
            return true
        } catch {
            return false
        }
    }

    /// Holds the forwarding capability and sink generation across the irreversible final ACK.
    /// Display callbacks detach under this lock and revoke after unlocking, so either they win
    /// before this guard or the exact resumed acknowledgement wins before they can retire it.
    func withAutomaticResumeCommitAuthorization<Result>(
        boundary: ResumeMarkerBoundary,
        authorizedBy authorization: WebRTCControlAuthorization,
        operation: () throws -> Result
    ) throws -> Result {
        try authorization.withValidAuthorization {
            try lock.withLock {
                guard forwardingPhase == .resumeAwaitingPresentation,
                      formatIsProven,
                      forwardingAuthorization === authorization,
                      resumeBoundaryRevision == boundary.revision,
                      resumeBoundaryGeometry == boundary.geometry,
                      lastProvenFrameGeometry == boundary.geometry,
                      callbackGateAllowsEntry else {
                    throw WebRTCTransportError.transportNotHealthy
                }
                forwardingPhase = .active
                resumeBoundaryGeometry = nil
                automaticResumeRealFrameCount = 0
                lastAutomaticResumeRealFrameTimestampSeconds = nil
                remoteInputController.updateScreenVideoFrameGeometry(
                    boundary.geometry,
                    ownerToken: remoteInputOwnerToken
                )
                do {
                    return try operation()
                } catch {
                    // The viewer was not told to uncover. Restore the covered proof phase and
                    // remove geometry before releasing either lock so input cannot leak through.
                    forwardingPhase = .resumeAwaitingPresentation
                    resumeBoundaryGeometry = boundary.geometry
                    remoteInputController.updateScreenVideoFrameGeometry(
                        nil,
                        ownerToken: remoteInputOwnerToken
                    )
                    throw error
                }
            }
        }
    }

    /// Closes the callback gate synchronously.
    func stopForwarding() {
        let retiredAuthorization = lock.withLock { () -> WebRTCControlAuthorization? in
            forwardingPhase = .stopped
            formatIsProven = false
            displayConfigurationInProgress = false
            expectedFrameDimensions = nil
            expectedFrameScaleFactor = nil
            expectedFrameContentScale = nil
            lastProvenFrameGeometry = nil
            lastFrameMetadataState = .none
            lastFrameSurfaceWidth = nil
            lastFrameSurfaceHeight = nil
            resumeBoundaryGeometry = nil
            automaticResumeRealFrameCount = 0
            lastAutomaticResumeRealFrameTimestampSeconds = nil
            invalidateFormatRenegotiationFallbackLocked()
            let authorization = forwardingAuthorization
            forwardingAuthorization = nil
            return authorization
        }
        retiredAuthorization?.revoke()
        remoteInputController.updateScreenVideoFrameGeometry(
            nil,
            ownerToken: remoteInputOwnerToken
        )
    }

    /// Forwards image-backed, timestamped samples only while the gate is open.
    func consumeScreenVideoSample(_ sampleBuffer: CMSampleBuffer) {
        consumeScreenVideoSample(sampleBuffer, frameGeometryObservation: .absent)
    }

    /// Compatibility entry point for deterministic callers that have optional geometry only.
    func consumeScreenVideoSample(
        _ sampleBuffer: CMSampleBuffer,
        frameGeometry: ScreenVideoFrameGeometry?
    ) {
        consumeScreenVideoSample(
            sampleBuffer,
            frameGeometryObservation:
                frameGeometry.map(ScreenVideoFrameGeometryObservation.valid) ?? .absent
        )
    }

    /// Forwards the frame before publishing its geometry. The controller independently requires
    /// a bounded propagation interval before reopening input after any transform change.
    func consumeScreenVideoSample(
        _ sampleBuffer: CMSampleBuffer,
        frameGeometryObservation: ScreenVideoFrameGeometryObservation
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let frameGeometry = frameGeometryObservation.geometry
        let surfaceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let surfaceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid else { return }
        let transition = lock.withLock { () -> (
            requiresRenegotiation: Bool,
            retiredAuthorization: WebRTCControlAuthorization?,
            fallbackToken: UInt64?
        ) in
            guard forwardingPhase == .starting
                    || forwardingPhase == .active
                    || forwardingPhase == .resumeMarkerBlocked
                    || forwardingPhase == .resumeRealArmed
                    || forwardingPhase == .resumeAwaitingPresentation,
                  callbackGateAllowsEntry else {
                return (false, nil, nil)
            }
            switch frameGeometryObservation {
            case .valid: lastFrameMetadataState = .valid
            case .absent: lastFrameMetadataState = .absent
            case .invalid: lastFrameMetadataState = .invalid
            }
            lastFrameSurfaceWidth = surfaceWidth
            lastFrameSurfaceHeight = surfaceHeight
            guard !displayConfigurationInProgress else {
                return (false, nil, nil)
            }
            if forwardingPhase == .resumeMarkerBlocked
                || forwardingPhase == .resumeRealArmed
                || forwardingPhase == .resumeAwaitingPresentation {
                let geometryRemainsExact: Bool
                if let resumeBoundaryGeometry,
                   surfaceWidth == resumeBoundaryGeometry.surfaceWidth,
                   surfaceHeight == resumeBoundaryGeometry.surfaceHeight {
                    switch frameGeometryObservation {
                    case .valid(let frameGeometry):
                        geometryRemainsExact = frameGeometry == resumeBoundaryGeometry
                            && !frameGeometry.requiresCaptureFormatRenegotiation
                    case .absent:
                        // Optional ScreenCaptureKit attachments may disappear without a surface
                        // transition. The exact retained geometry remains authoritative while the
                        // pixel surface and display callbacks are unchanged.
                        geometryRemainsExact = lastProvenFrameGeometry
                            == resumeBoundaryGeometry
                    case .invalid:
                        geometryRemainsExact = false
                    }
                } else {
                    geometryRemainsExact = false
                }
                guard geometryRemainsExact else {
                    let suspension = suspendForFormatRenegotiationLocked()
                    return (
                        suspension.requiresRenegotiation,
                        suspension.retiredAuthorization,
                        nil
                    )
                }
                switch forwardingPhase {
                case .resumeRealArmed:
                    // Admit the first exact real surface immediately. The encoder wrapper forces
                    // this boundary to a key frame and admits one matching callback.
                    forwardingPhase = .resumeAwaitingPresentation
                    automaticResumeRealFrameCount = 1
                    lastAutomaticResumeRealFrameTimestampSeconds =
                        CMTimeGetSeconds(timestamp)
                    capturer.captureScreenFrame(
                        pixelBuffer: pixelBuffer,
                        timestamp: timestamp
                    )
                case .resumeAwaitingPresentation:
                    // A covered 1 fps trickle gives native NACK/PLI recovery a bounded later
                    // frame without reopening ordinary capture or input. Every frame still uses
                    // the exact retained surface/geometry checked above.
                    let timestampSeconds = CMTimeGetSeconds(timestamp)
                    if automaticResumeRealFrameCount
                            < Self.maximumAutomaticResumeRealFrameCount,
                       timestampSeconds.isFinite,
                       let lastTimestampSeconds =
                            lastAutomaticResumeRealFrameTimestampSeconds,
                       timestampSeconds - lastTimestampSeconds
                            >= Self.automaticResumeRealFrameRetryIntervalSeconds {
                        automaticResumeRealFrameCount += 1
                        lastAutomaticResumeRealFrameTimestampSeconds =
                            timestampSeconds
                        capturer.captureScreenFrame(
                            pixelBuffer: pixelBuffer,
                            timestamp: timestamp
                        )
                    }
                case .resumeMarkerBlocked:
                    break
                default:
                    break
                }
                return (false, nil, nil)
            }
            if frameGeometry == nil,
               let lastProvenFrameGeometry,
               (lastProvenFrameGeometry.surfaceWidth != surfaceWidth
                   || lastProvenFrameGeometry.surfaceHeight != surfaceHeight) {
                // Pixel dimensions are authoritative even when optional SCK attachments vanish.
                // A different surface cannot reuse the prior coordinate transform.
                let suspension = suspendForFormatRenegotiationLocked()
                return (
                    suspension.requiresRenegotiation,
                    suspension.retiredAuthorization,
                    nil
                )
            }
            if forwardingPhase == .starting,
               let expectedFrameDimensions,
               frameGeometry.map({ geometry in
                   geometry.surfaceWidth == expectedFrameDimensions.width
                       && geometry.surfaceHeight == expectedFrameDimensions.height
                       && !geometry.requiresCaptureFormatRenegotiation
                       && (expectedFrameScaleFactor.map { expectedScaleFactor in
                           abs(Double(geometry.scaleFactor) - expectedScaleFactor) <= 0.005
                       } ?? true)
                       && (expectedFrameContentScale.map { expectedContentScale in
                           abs(Double(geometry.contentScale) - expectedContentScale) <= 0.005
                       } ?? true)
               }) != true {
                // ScreenCaptureKit can replay one image-backed `.started` sample whose geometry
                // still describes the preceding surface. Keep the generation closed and wait for
                // the first exact frame; the actor's bounded startup-proof deadline handles a
                // persistently stale stream, while the display-mode observer remains immediate.
                formatIsProven = false
                return (false, nil, nil)
            }
            switch formatRenegotiationDetector.observe(frameGeometryObservation) {
            case .forwardFrame:
                if case .invalid = frameGeometryObservation {
                    // Defensive backstop: invalid metadata must never enter media/input admission
                    // even if the detector's classification changes in a future refactor.
                    formatIsProven = false
                    remoteInputController.updateScreenVideoFrameGeometry(
                        nil,
                        ownerToken: remoteInputOwnerToken
                    )
                    return (false, nil, armFormatRenegotiationFallbackLocked())
                }
                invalidateFormatRenegotiationFallbackLocked()
                formatIsProven = true
                capturer.captureScreenFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
                if let frameGeometry {
                    lastProvenFrameGeometry = frameGeometry
                    remoteInputController.updateScreenVideoFrameGeometry(
                        frameGeometry,
                        ownerToken: remoteInputOwnerToken
                    )
                } else if let lastProvenFrameGeometry {
                    // Missing per-frame attachments are not themselves a format transition. The
                    // exact pixel-surface check above and the authoritative display-mode callback
                    // fence this reuse to the currently proven capture generation.
                    remoteInputController.updateScreenVideoFrameGeometry(
                        lastProvenFrameGeometry,
                        ownerToken: remoteInputOwnerToken
                    )
                } else {
                    remoteInputController.updateScreenVideoFrameGeometry(
                        nil,
                        ownerToken: remoteInputOwnerToken
                    )
                }
                return (false, nil, nil)
            case .dropFrame:
                formatIsProven = false
                remoteInputController.updateScreenVideoFrameGeometry(
                    nil,
                    ownerToken: remoteInputOwnerToken
                )
                return (false, nil, armFormatRenegotiationFallbackLocked())
            case .renegotiate:
                let suspension = suspendForFormatRenegotiationLocked()
                return (
                    suspension.requiresRenegotiation,
                    suspension.retiredAuthorization,
                    nil
                )
            }
        }
        transition.retiredAuthorization?.revoke()
        if transition.requiresRenegotiation {
            remoteInputController.updateScreenVideoFrameGeometry(
                nil,
                ownerToken: remoteInputOwnerToken
            )
            didRequireCaptureFormatRenegotiation(self)
        }
        if let fallbackToken = transition.fallbackToken {
            scheduleFormatRenegotiationFallback(
                Self.formatRenegotiationFallbackDelay
            ) { [weak self] in
                self?.formatRenegotiationFallbackDidFire(fallbackToken)
            }
        }
    }

    func screenVideoCaptureSourceDisplayModeDidChange(
        _: ScreenVideoCaptureSource
    ) {
        displayModeDidChange()
    }

    func screenVideoCaptureSourceDisplayConfigurationWillChange(
        _: ScreenVideoCaptureSource
    ) {
        displayConfigurationWillChange()
    }

    /// Closes the coordinate generation at Core Graphics' pre-configuration boundary without
    /// rebuilding against display state that is not settled yet. The post callback performs the
    /// existing authoritative renegotiation after the transaction completes.
    func displayConfigurationWillChange() {
        let transition = lock.withLock { () -> (
            didLatch: Bool,
            retiredAuthorization: WebRTCControlAuthorization?
        ) in
            guard !displayConfigurationInProgress,
                  forwardingPhase == .starting
                    || forwardingPhase == .active
                    || forwardingPhase == .resumeMarkerBlocked
                    || forwardingPhase == .resumeRealArmed
                    || forwardingPhase == .resumeAwaitingPresentation else {
                return (false, nil)
            }
            displayConfigurationInProgress = true
            formatIsProven = false
            lastProvenFrameGeometry = nil
            invalidateFormatRenegotiationFallbackLocked()
            let authorization = forwardingAuthorization
            forwardingAuthorization = nil
            return (true, authorization)
        }
        guard transition.didLatch else { return }
        // Clear the old transform before revocation waits for an already-linearized input action.
        remoteInputController.updateScreenVideoFrameGeometry(
            nil,
            ownerToken: remoteInputOwnerToken
        )
        transition.retiredAuthorization?.revoke()
    }

    /// Shared authoritative trigger used by the source callback and deterministic lifecycle tests.
    func displayModeDidChange() {
        let transition = lock.withLock { () -> (
            requiresRenegotiation: Bool,
            retiredAuthorization: WebRTCControlAuthorization?
        ) in
            invalidateFormatRenegotiationFallbackLocked()
            displayConfigurationInProgress = false
            if forwardingPhase == .starting
                || forwardingPhase == .active
                || forwardingPhase == .resumeMarkerBlocked
                || forwardingPhase == .resumeRealArmed
                || forwardingPhase == .resumeAwaitingPresentation {
                // Core Graphics can invoke this callback from inside its reconfiguration
                // transaction. Remote input acquires the control token before this sink lock, so
                // detach here and revoke only after unlock to preserve the global lock order.
                // Every already-published resume phase owns a live capture generation. A settled
                // display mutation must notify its actor immediately; otherwise `.renegotiating`
                // drops every later sample and the covered probe can linger until its timeout.
                let shouldNotify = forwardingPhase != .starting
                forwardingPhase = .renegotiating
                formatIsProven = false
                lastProvenFrameGeometry = nil
                let authorization = forwardingAuthorization
                forwardingAuthorization = nil
                return (shouldNotify, authorization)
            }
            guard forwardingPhase == .ready else { return (false, nil) }
            forwardingPhase = .renegotiating
            formatIsProven = false
            lastProvenFrameGeometry = nil
            let authorization = forwardingAuthorization
            forwardingAuthorization = nil
            return (false, authorization)
        }
        // Close the stale coordinate map before token revocation can wait for an input operation
        // that already linearized against the previous sink generation.
        remoteInputController.updateScreenVideoFrameGeometry(
            nil,
            ownerToken: remoteInputOwnerToken
        )
        transition.retiredAuthorization?.revoke()
        if transition.requiresRenegotiation {
            didRequireCaptureFormatRenegotiation(self)
        }
    }

    func screenVideoCaptureSource(
        _ source: ScreenVideoCaptureSource,
        didStopWithErrorDescription errorDescription: String
    ) {
        stopForwarding()
        didStop(source, errorDescription)
    }

    private var lifetimeAllowsCapture: Bool {
        !captureLifetimeIsRequired || captureLifetime?.isValid == true
    }

    private var callbackGateAllowsEntry: Bool {
        !captureLifetimeIsRequired || captureLifetime?.allowsCallbackEntry == true
    }

    /// Arms at most one deadline for the current changed-geometry candidate. Scheduling happens
    /// after unlocking; the token makes a recovered frame, stop, or authoritative mode callback
    /// invalidate work that was already enqueued without relying on cancellation timing.
    private func armFormatRenegotiationFallbackLocked() -> UInt64? {
        guard formatRenegotiationDetector.hasPendingFormatChange,
              scheduledFormatRenegotiationFallbackToken == nil else {
            return nil
        }
        nextFormatRenegotiationFallbackToken &+= 1
        if nextFormatRenegotiationFallbackToken == 0 {
            nextFormatRenegotiationFallbackToken = 1
        }
        scheduledFormatRenegotiationFallbackToken =
            nextFormatRenegotiationFallbackToken
        return nextFormatRenegotiationFallbackToken
    }

    private func invalidateFormatRenegotiationFallbackLocked() {
        scheduledFormatRenegotiationFallbackToken = nil
    }

    private func formatRenegotiationFallbackDidFire(_ token: UInt64) {
        let transition = lock.withLock { () -> (
            requiresRenegotiation: Bool,
            retiredAuthorization: WebRTCControlAuthorization?
        ) in
            guard scheduledFormatRenegotiationFallbackToken == token else {
                return (false, nil)
            }
            scheduledFormatRenegotiationFallbackToken = nil
            guard forwardingPhase == .starting || forwardingPhase == .active,
                  callbackGateAllowsEntry,
                  formatRenegotiationDetector
                    .requestRenegotiationAfterFallbackDeadline() else {
                return (false, nil)
            }
            return suspendForFormatRenegotiationLocked()
        }
        transition.retiredAuthorization?.revoke()
        if transition.requiresRenegotiation {
            remoteInputController.updateScreenVideoFrameGeometry(
                nil,
                ownerToken: remoteInputOwnerToken
            )
            didRequireCaptureFormatRenegotiation(self)
        }
    }

    /// Latches a format transition and returns its token for revocation after unlocking.
    private func suspendForFormatRenegotiationLocked() -> (
        requiresRenegotiation: Bool,
        retiredAuthorization: WebRTCControlAuthorization?
    ) {
        guard forwardingPhase == .starting
                || forwardingPhase == .active
                || forwardingPhase == .resumeMarkerBlocked
                || forwardingPhase == .resumeRealArmed
                || forwardingPhase == .resumeAwaitingPresentation else {
            return (false, nil)
        }
        invalidateFormatRenegotiationFallbackLocked()
        let shouldNotify = forwardingPhase != .starting
        forwardingPhase = .renegotiating
        formatIsProven = false
        displayConfigurationInProgress = false
        lastProvenFrameGeometry = nil
        resumeBoundaryGeometry = nil
        automaticResumeRealFrameCount = 0
        lastAutomaticResumeRealFrameTimestampSeconds = nil
        let authorization = forwardingAuthorization
        forwardingAuthorization = nil
        return (shouldNotify, authorization)
    }
}

/// Lock-owned callback capability that can be rolled to a fresh transport authorization without
/// replacing the continuously monitored native source. Audio is always acquired before causal
/// evidence, matching `WebRTCPeer`'s global authorization order.
final class WorldwideSystemAudioForwardingGate: @unchecked Sendable {
    private struct EvidenceTransition {
        let retired: WebRTCMacHostedCallEvidenceAuthorization?
        let delivery: WebRTCMacHostedCallEvidenceAuthorization?
    }

    private let lock = NSLock()
    private var isForwarding = false
    private var isTerminated = false
    private var authorization: WebRTCAudioAuthorization?
    private var macHostedCallCausalBindingID: UUID?
    private var macHostedCallEvidenceAuthorization:
        WebRTCMacHostedCallEvidenceAuthorization?

    /// Installs one fresh route capability. A prior route must be synchronously paused first.
    @discardableResult
    func beginForwarding(
        with authorization: WebRTCAudioAuthorization
    ) -> Bool {
        do {
            return try authorization.withValidAuthorization {
                lock.withLock {
                    if isForwarding,
                       self.authorization === authorization {
                        return true
                    }
                    guard !isForwarding,
                          self.authorization == nil,
                          !isTerminated else {
                        return false
                    }
                    self.authorization = authorization
                    isForwarding = true
                    return true
                }
            }
        } catch {
            return false
        }
    }

    /// Closes PCM and evidence synchronously, then revokes the old capabilities in lock order.
    func stopForwarding() {
        closeForwarding(terminal: false)
    }

    /// Permanently closes a gate whose native source has failed.
    func terminate() {
        closeForwarding(terminal: true)
    }

    private func closeForwarding(terminal: Bool) {
        let retired = lock.withLock {
            let retired = (
                authorization,
                macHostedCallEvidenceAuthorization
            )
            isForwarding = false
            isTerminated = isTerminated || terminal
            authorization = nil
            macHostedCallCausalBindingID = nil
            macHostedCallEvidenceAuthorization = nil
            return retired
        }
        retired.0?.revoke()
        retired.1?.revoke()
    }

    var authorizationSnapshot: WebRTCAudioAuthorization? {
        lock.withLock {
            guard isForwarding else { return nil }
            return authorization
        }
    }

    /// Rechecks exact token identity under the callback gate after acquiring the audio token.
    @discardableResult
    func withCurrentAuthorization(
        _ candidate: WebRTCAudioAuthorization,
        operation: () -> Void
    ) -> Bool {
        do {
            return try candidate.withValidAuthorization {
                lock.withLock {
                    guard isForwarding,
                          authorization === candidate else {
                        return false
                    }
                    operation()
                    return true
                }
            }
        } catch {
            return false
        }
    }

    /// Creates or reuses evidence only for the exact native binding and call epoch sampled.
    @discardableResult
    func withEvidenceAuthorization(
        for observation: SystemAudioMacFaceTimeActivityObservation,
        operation: (
            WebRTCAudioAuthorization,
            WebRTCMacHostedCallEvidenceAuthorization
        ) -> Void
    ) -> Bool {
        guard let candidate = authorizationSnapshot else { return false }
        do {
            return try candidate.withValidAuthorization {
                let transition = lock.withLock { () -> EvidenceTransition in
                    guard isForwarding,
                          authorization === candidate else {
                        return EvidenceTransition(
                            retired: nil,
                            delivery: nil
                        )
                    }
                    guard let challenge = observation.challenge,
                          Self.isValid(challenge) else {
                        return retireEvidenceLocked()
                    }

                    if let bindingID = observation.causalBindingID,
                       macHostedCallCausalBindingID == bindingID,
                       let current =
                            macHostedCallEvidenceAuthorization,
                       current.callEpochNonce
                            == challenge.callEpochNonce,
                       current.isValid {
                        return EvidenceTransition(
                            retired: nil,
                            delivery: current
                        )
                    }

                    let retired = macHostedCallEvidenceAuthorization
                    let replacement =
                        WebRTCMacHostedCallEvidenceAuthorization(
                            callEpochNonce: challenge.callEpochNonce
                        )
                    macHostedCallCausalBindingID =
                        observation.causalBindingID
                    // Non-active evidence is one-shot: the next observation replaces it instead of
                    // reusing it, while retaining it here lets a recovery pause revoke it.
                    macHostedCallEvidenceAuthorization = replacement
                    return EvidenceTransition(
                        retired: retired,
                        delivery: replacement
                    )
                }
                transition.retired?.revoke()
                guard let evidenceAuthorization = transition.delivery else {
                    return false
                }
                operation(candidate, evidenceAuthorization)
                return true
            }
        } catch {
            return false
        }
    }

    private func retireEvidenceLocked() -> EvidenceTransition {
        let retired = macHostedCallEvidenceAuthorization
        macHostedCallCausalBindingID = nil
        macHostedCallEvidenceAuthorization = nil
        return EvidenceTransition(retired: retired, delivery: nil)
    }

    private static func isValid(
        _ challenge: SystemAudioMacFaceTimeActivityChallenge
    ) -> Bool {
        challenge.sequence > 0
            && challenge.nonce != zeroUUID
            && challenge.callEpochNonce != zeroUUID
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// Thread-safe, doubly authorized bridge from system-audio callbacks into WebRTC.
final class WorldwideSystemAudioSampleSink: SystemAudioSampleConsumer, @unchecked Sendable {
    private let capturer: MacExternalAudioCapturer
    private let gate: WorldwideSystemAudioForwardingGate
    private weak var captureLifetime: CaptureServiceLifetime?
    private let captureLifetimeIsRequired: Bool
    private let didObserveMacFaceTimeActivity:
        @Sendable (
            SystemAudioCaptureSource,
            WebRTCAudioAuthorization,
            SystemAudioMacFaceTimeActivityObservation,
            WebRTCMacHostedCallEvidenceAuthorization
        ) -> Void
    private let didStop:
        @Sendable (
            SystemAudioCaptureSource,
            WorldwideSystemAudioSampleSink,
            String
        ) -> Void

    init(
        capturer: MacExternalAudioCapturer,
        gate: WorldwideSystemAudioForwardingGate =
            WorldwideSystemAudioForwardingGate(),
        captureLifetime: CaptureServiceLifetime? = nil,
        didObserveMacFaceTimeActivity:
            @escaping @Sendable (
                SystemAudioCaptureSource,
                WebRTCAudioAuthorization,
                SystemAudioMacFaceTimeActivityObservation,
                WebRTCMacHostedCallEvidenceAuthorization
            ) -> Void,
        didStop:
            @escaping @Sendable (
                SystemAudioCaptureSource,
                WorldwideSystemAudioSampleSink,
                String
            ) -> Void
    ) {
        self.capturer = capturer
        self.gate = gate
        self.captureLifetime = captureLifetime
        captureLifetimeIsRequired = captureLifetime != nil
        self.didObserveMacFaceTimeActivity =
            didObserveMacFaceTimeActivity
        self.didStop = didStop
    }

    @discardableResult
    func beginForwarding(
        with authorization: WebRTCAudioAuthorization
    ) -> Bool {
        lifetimeAllowsCapture
            && gate.beginForwarding(with: authorization)
    }

    func stopForwarding() {
        gate.stopForwarding()
    }

    func consumeSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let authorization = gate.authorizationSnapshot else {
            return
        }
        gate.withCurrentAuthorization(authorization) {
            guard callbackGateAllowsEntry else { return }
            capturer.capture(sampleBuffer: sampleBuffer)
        }
    }

    func consumeSystemAudioFrames(
        _ audioBufferList: UnsafePointer<AudioBufferList>,
        format: AudioStreamBasicDescription,
        frameCount: UInt32,
        presentationTime: CMTime
    ) {
        guard let authorization = gate.authorizationSnapshot else {
            return
        }
        gate.withCurrentAuthorization(authorization) {
            guard callbackGateAllowsEntry else { return }
            capturer.capture(
                audioBufferList: audioBufferList,
                format: format,
                frameCount: frameCount,
                presentationTime: presentationTime
            )
        }
    }

    func systemAudioCaptureSource(
        _ source: SystemAudioCaptureSource,
        didStopWithErrorDescription errorDescription: String
    ) {
        gate.terminate()
        capturer.reset()
        didStop(source, self, errorDescription)
    }

    func systemAudioCaptureSource(
        _ source: SystemAudioCaptureSource,
        didObserveMacFaceTimeActivity observation:
            SystemAudioMacFaceTimeActivityObservation
    ) {
        guard callbackGateAllowsEntry else { return }
        gate.withEvidenceAuthorization(for: observation) {
            authorization, evidenceAuthorization in
            didObserveMacFaceTimeActivity(
                source,
                authorization,
                observation,
                evidenceAuthorization
            )
        }
    }

    private var lifetimeAllowsCapture: Bool {
        !captureLifetimeIsRequired || captureLifetime?.isValid == true
    }

    private var callbackGateAllowsEntry: Bool {
        !captureLifetimeIsRequired || captureLifetime?.allowsCallbackEntry == true
    }
}

/// Lifecycle, transport-health, and rendezvous failures for one media session.
private enum WorldwideScreenServiceError: LocalizedError {
    case invalidLifecycle
    case signalBeforeReady
    case videoCapturerUnavailable
    case audioCapturerUnavailable
    case transportUnavailable
    case microphoneInputAdmissionUnavailable
    case microphoneInputReleaseUnproved
    case microphoneWriterAuthorizationSuperseded
    case nativeScreenStopFailed(any Error)
    case nativeSystemAudioStopUnconfirmed
    case rendezvous(RendezvousServerError)

    var errorDescription: String? {
        switch self {
        case .invalidLifecycle:
            "The worldwide screen service cannot be started in its current state."
        case .signalBeforeReady:
            "The rendezvous delivered signaling before the WebRTC peer was ready."
        case .videoCapturerUnavailable:
            "The Mac WebRTC screen capturer is unavailable."
        case .audioCapturerUnavailable:
            "The Mac WebRTC system-audio capturer is unavailable."
        case .transportUnavailable:
            "The secure media transport is not healthy enough to expose the screen."
        case .microphoneInputAdmissionUnavailable:
            "The visible microphone input lease could not be proven."
        case .microphoneInputReleaseUnproved:
            "The visible microphone input lease could not be released before output-route repair."
        case .microphoneWriterAuthorizationSuperseded:
            "A newer Mac output-route event superseded microphone writer admission."
        case .nativeScreenStopFailed(let error):
            "The native screen source could not confirm that capture stopped " +
                "(\(error.localizedDescription))."
        case .nativeSystemAudioStopUnconfirmed:
            "The native system-audio source could not confirm that capture stopped."
        case .rendezvous(let error):
            "The rendezvous rejected the session (\(String(describing: error)))."
        }
    }
}

// Read-only authoritative actor value. No parallel storage, publication, async
// suspension, producer query or clock read; returned by value without rehydration.
extension WorldwideScreenService {
    func networkAdaptationOwnerCopiedValue() -> BelugaNetworkAdaptationOwnerValue {
        screenVideoAdaptationOwner
    }
}

// Release-shaped capability, not yet minted by the production ACK handler.
// Only this actor file can construct it from the original committed attempt.
final class BelugaNetworkAdaptationCommittedResumeEntry {
    fileprivate enum Phase { case fresh, admitted, published, retired }
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let generation: UInt64
    fileprivate let owner: WorldwideScreenService
    fileprivate let sourcePeer: WebRTCPeer
    fileprivate let sink: WorldwideScreenSampleSink
    fileprivate let probeAuthorization: WebRTCControlAuthorization
    fileprivate let forwardingAuthorization: WebRTCControlAuthorization
    fileprivate let binding: WorldwideScreenMediaSuspensionCoordinator.Binding
    fileprivate let notice: WebRTCScreenMediaSuspensionNotice
    fileprivate let attemptID: UUID
    fileprivate let latch: WorldwideScreenAutomaticResumeCommitLatch
    fileprivate let markerBoundary: WorldwideScreenSampleSink.ResumeMarkerBoundary
    fileprivate let markerReady: WebRTCScreenMediaMarkerReady?
    fileprivate let markerPresentation: WebRTCScreenMediaMarkerPresentation?
    fileprivate var phase: Phase = .fresh

    fileprivate init(owner: WorldwideScreenService, boundary: BelugaNetworkAdaptationOwnerBoundary,
        generation: UInt64, sourcePeer: WebRTCPeer, sink: WorldwideScreenSampleSink,
        probeAuthorization: WebRTCControlAuthorization,
        forwardingAuthorization: WebRTCControlAuthorization,
        binding: WorldwideScreenMediaSuspensionCoordinator.Binding,
        notice: WebRTCScreenMediaSuspensionNotice, attemptID: UUID,
        latch: WorldwideScreenAutomaticResumeCommitLatch,
        markerBoundary: WorldwideScreenSampleSink.ResumeMarkerBoundary,
        markerReady: WebRTCScreenMediaMarkerReady?,
        markerPresentation: WebRTCScreenMediaMarkerPresentation?) {
        self.owner = owner
        self.boundary = boundary
        self.generation = generation
        self.sourcePeer = sourcePeer
        self.sink = sink
        self.probeAuthorization = probeAuthorization
        self.forwardingAuthorization = forwardingAuthorization
        self.binding = binding
        self.notice = notice
        self.attemptID = attemptID
        self.latch = latch
        self.markerBoundary = markerBoundary
        self.markerReady = markerReady
        self.markerPresentation = markerPresentation
    }
}

extension WorldwideScreenService {
    private func networkAdaptationCommittedResumeEntry(
        context: AutomaticScreenMediaResumeContext, sourcePeer: WebRTCPeer,
        generation: UInt64, sink: WorldwideScreenSampleSink,
        probeAuthorization: WebRTCControlAuthorization,
        forwardingAuthorization: WebRTCControlAuthorization,
        markerBoundary: WorldwideScreenSampleSink.ResumeMarkerBoundary
    ) -> BelugaNetworkAdaptationCommittedResumeEntry? {
        guard Self.allNetworkAdaptationOwnerWritersAreEnrolled,
              Self.ownedStopPublicationIsEnrolled,
              let current = automaticScreenMediaResumeContext,
              current.attemptID == context.attemptID,
              current.finalAcknowledgementCommit === context.finalAcknowledgementCommit,
              current.ownerCompletionClaim == .unclaimed,
              current.ownerCompletionEntryID == nil else { return nil }
        let entry = BelugaNetworkAdaptationCommittedResumeEntry(
            owner: self, boundary: screenVideoAdaptationOwnerBoundary,
            generation: generation, sourcePeer: sourcePeer, sink: sink,
            probeAuthorization: probeAuthorization,
            forwardingAuthorization: forwardingAuthorization,
            binding: context.binding, notice: context.notice, attemptID: context.attemptID,
            latch: context.finalAcknowledgementCommit, markerBoundary: markerBoundary,
            markerReady: context.markerReady, markerPresentation: context.markerPresentation)
        automaticScreenMediaResumeContext?.ownerCompletionEntryID = ObjectIdentifier(entry)
        return entry
    }

    private func networkAdaptationCommittedResumeNativeWitnessIsCurrent(
        _ entry: BelugaNetworkAdaptationCommittedResumeEntry
    ) -> Bool {
        guard entry.owner === self,
              entry.boundary === screenVideoAdaptationOwnerBoundary,
              !isStopped, let currentPeer = peer,
              currentPeer === entry.sourcePeer,
              peerGeneration == entry.generation,
              entry.binding.peerGeneration == entry.generation,
              screenVisibilityCommandEpoch == entry.binding.visibilityCommandEpoch,
              recoveryProofEpoch == entry.binding.recoveryEpoch,
              let activeScreenRequestID = screenMediaSuspension.activeScreenRequestID,
              activeScreenRequestID == entry.notice.screenRequestID,
              let currentSink = captureSink, currentSink === entry.sink,
              let currentForwarding = captureForwardingAuthorization,
              currentForwarding === entry.forwardingAuthorization,
              let completed = automaticScreenMediaResumeContext,
              completed.ownerCompletionEntryID == ObjectIdentifier(entry),
              completed.attemptID == entry.attemptID,
              completed.binding == entry.binding, completed.notice == entry.notice,
              completed.finalAcknowledgementCommit === entry.latch,
              completed.finalAcknowledgementCommit.isCommitted,
              let completedBoundary = completed.boundary,
              completedBoundary == entry.markerBoundary,
              completed.markerReady == entry.markerReady,
              completed.markerPresentation == entry.markerPresentation,
              let completedProbe = completed.probeAuthorization,
              completedProbe === entry.probeAuthorization,
              let completedForwarding = completed.forwardingAuthorization,
              completedForwarding === entry.forwardingAuthorization,
              screenMediaSuspension.owns(entry.binding) else { return false }
        return true
    }

    func networkAdaptationCommittedResumeAdmit(_ entry: BelugaNetworkAdaptationCommittedResumeEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary, key: [UInt64]) -> Bool {
        let fresh = entry.phase == .fresh
        entry.phase = .retired
        guard fresh, Self.allNetworkAdaptationOwnerWritersAreEnrolled,
              Self.ownedStopPublicationIsEnrolled,
              entry.boundary === boundary, key == [108, 0, 0, 0, 0],
              networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry),
              automaticScreenMediaResumeContext?.ownerCompletionClaim == .unclaimed else { return false }
        automaticScreenMediaResumeContext?.ownerCompletionClaim = .admitted
        entry.phase = .admitted
        return true
    }

    func networkAdaptationCommittedResumeIsCurrent(_ entry: BelugaNetworkAdaptationCommittedResumeEntry) -> Bool {
        entry.phase == .admitted
            && automaticScreenMediaResumeContext?.ownerCompletionClaim == .admitted
            && networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry)
    }

    func networkAdaptationCommittedResumeMatches(_ entry: BelugaNetworkAdaptationCommittedResumeEntry,
        slot: ObjectIdentifier, key: [UInt64], generation: UInt64) -> Bool {
        slot == ObjectIdentifier(entry) && key == [108, 0, 0, 0, 0]
            && generation == entry.generation && networkAdaptationCommittedResumeIsCurrent(entry)
    }

    func networkAdaptationCommittedResumeCapture(_ entry: BelugaNetworkAdaptationCommittedResumeEntry,
        retainingAnchor: ContinuousClock.Instant?) throws -> BelugaNetworkAdaptationOwnerSnapshot {
        guard networkAdaptationCommittedResumeIsCurrent(entry) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return try BelugaNetworkAdaptationOwnerSnapshot.capture(screenVideoAdaptationOwner,
            retainingAnchor: retainingAnchor)
    }

    // Pure claim bookkeeping, including rejection of a poisoned nested frame.
    func networkAdaptationCommittedResumeRetire(_ entry: BelugaNetworkAdaptationCommittedResumeEntry) {
        guard entry.phase != .published else { return }
        entry.phase = .retired
        guard entry.owner === self, entry.boundary === screenVideoAdaptationOwnerBoundary,
              let completed = automaticScreenMediaResumeContext,
              completed.ownerCompletionEntryID == ObjectIdentifier(entry),
              completed.attemptID == entry.attemptID,
              completed.binding == entry.binding, completed.notice == entry.notice,
              completed.finalAcknowledgementCommit === entry.latch,
              let claim = automaticScreenMediaResumeContext?.ownerCompletionClaim,
              claim == .unclaimed || claim == .admitted else { return }
        automaticScreenMediaResumeContext?.ownerCompletionClaim = .refused
    }

    func networkAdaptationCommittedResumeCommit(_ packet: BelugaNetworkAdaptationCommittedResumeCommit) {
        packet.entry.phase = .published
        automaticScreenMediaResumeContext?.ownerCompletionClaim = .published
        screenVideoAdaptationOwner = packet.replacement.value
    }

    private func claimCommittedResumeRefusalStop(
        _ entry: BelugaNetworkAdaptationCommittedResumeEntry
    ) -> ServiceStopPlan? {
        guard Self.allNetworkAdaptationOwnerWritersAreEnrolled,
              Self.ownedStopPublicationIsEnrolled,
              networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry),
              let claim = automaticScreenMediaResumeContext?.ownerCompletionClaim,
              claim != .published, claim != .terminalClaimed else { return nil }
        automaticScreenMediaResumeContext?.ownerCompletionClaim = .terminalClaimed
        entry.phase = .retired
        cancelAutomaticScreenMediaResumeTimeout()
        retireAutomaticScreenMediaResumeNativeContext()
        return beginStop()
    }

    private func stopAfterCommittedResumeRefusal(
        _ entry: BelugaNetworkAdaptationCommittedResumeEntry
    ) async {
        guard let plan = claimCommittedResumeRefusalStop(entry) else { return }
        await finishStop(consume plan)
    }

    private func publishCommittedResumeOwner(
        _ entry: BelugaNetworkAdaptationCommittedResumeEntry
    ) async -> Bool {
        do {
            switch try screenVideoAdaptationOwnerBoundary.publishCommittedResume(entry, on: self) {
            case .accepted: return true
            case .superseded:
                guard networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry) else { return false }
            case .refused: break
            }
        } catch {
            logger.error("Committed screen resume owner publication failed: \(error.localizedDescription)")
        }
        await stopAfterCommittedResumeRefusal(entry)
        return false
    }
}

private extension NSLock {
    /// Runs a synchronous critical section and always releases the lock.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

/// Constructor sealed to the actor's original Stop cuts. Strong exact references
/// are custody, not active-media authority: nil resources and revoked tokens are
/// valid during cleanup. No caller-supplied state, votes, callback or setter.
final class BelugaNetworkAdaptationActualStopEntry {
    fileprivate enum Origin {
        case nativeShutdown
        #if DEBUG
        case inertFixture
        #endif
    }
    enum Cut {
        case endShow, stopSampling
        var operation: UInt32 { self == .endShow ? 202 : 105 }
        var key: [UInt64] { self == .endShow ? [202, 0, 0, 0, 0, 0] : [105, 0, 0, 0, 0] }
    }
    fileprivate enum Phase { case fresh, admitted, retired }
    let owner: WorldwideScreenService
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let cut: Cut
    let generation: UInt64
    fileprivate let origin: Origin
    var operation: UInt32 { cut.operation }
    var permitsInertNegativeControls: Bool {
        #if DEBUG
        origin == .inertFixture
        #else
        false
        #endif
    }
    fileprivate var phase: Phase = .fresh
    fileprivate let sourcePeer: WebRTCPeer?
    fileprivate let coordinator: ICERecoveryCoordinator?
    fileprivate let source: ScreenVideoCaptureSource?
    fileprivate let sink: WorldwideScreenSampleSink?
    fileprivate let authorization: WebRTCControlAuthorization?
    fileprivate let forwarding: WebRTCControlAuthorization?
    fileprivate let audioSource: SystemAudioCaptureSource?
    fileprivate let audioSink: WorldwideSystemAudioSampleSink?
    fileprivate let audioAuthorization: WebRTCAudioAuthorization?
    fileprivate let visibilityEpoch: UInt64
    fileprivate let recoveryEpoch: UInt64

    fileprivate init(owner: WorldwideScreenService, boundary: BelugaNetworkAdaptationOwnerBoundary,
        cut: Cut, origin: Origin, generation: UInt64, sourcePeer: WebRTCPeer?, coordinator: ICERecoveryCoordinator?,
        source: ScreenVideoCaptureSource?, sink: WorldwideScreenSampleSink?,
        authorization: WebRTCControlAuthorization?, forwarding: WebRTCControlAuthorization?,
        audioSource: SystemAudioCaptureSource?, audioSink: WorldwideSystemAudioSampleSink?,
        audioAuthorization: WebRTCAudioAuthorization?, visibilityEpoch: UInt64, recoveryEpoch: UInt64) {
        self.owner = owner; self.boundary = boundary; self.cut = cut; self.origin = origin; self.generation = generation
        self.sourcePeer = sourcePeer; self.coordinator = coordinator; self.source = source; self.sink = sink
        self.authorization = authorization; self.forwarding = forwarding
        self.audioSource = audioSource; self.audioSink = audioSink; self.audioAuthorization = audioAuthorization
        self.visibilityEpoch = visibilityEpoch; self.recoveryEpoch = recoveryEpoch
    }
}

extension WorldwideScreenService {
    // One constructor-sealed origin is selected before the original two cuts.
    // Neither Release nor a DEBUG native origin can borrow fixture fault authority.
    private func networkAdaptationActualStopPublicationOrigin() -> BelugaNetworkAdaptationActualStopEntry.Origin? {
        if Self.allNetworkAdaptationOwnerWritersAreEnrolled && Self.ownedStopPublicationIsEnrolled {
            return .nativeShutdown
        }
        #if DEBUG
        if nativeOwnerStopPublicationEnabled { return .inertFixture }
        #endif
        return nil
    }

    // Rejection never abandons teardown or falls back to a Swift replacement.
    // Each cut creates fresh custody; diagnostic reads cannot admit a publication.
    private func applyNativeOwnerStopPublication(_ cut: BelugaNetworkAdaptationActualStopEntry.Cut,
        origin: BelugaNetworkAdaptationActualStopEntry.Origin) {
        guard pendingNativeOwnerStopEntry == nil else { return }
        let entry = networkAdaptationActualStopEntry(cut, origin: origin)
        pendingNativeOwnerStopEntry = entry
        defer {
            entry.phase = .retired
            pendingNativeOwnerStopEntry = nil
            switch cut {
            case .endShow: nativeOwnerStopPublicationStage = .stopSampling
            case .stopSampling: nativeOwnerStopPublicationStage = .finished
            }
        }
        #if DEBUG
        var before: NativeOwnerPublicationSnapshotObservation?
        var disposition = NativeOwnerStopPublicationCut.Disposition.refused
        if entry.permitsInertNegativeControls {
            nativeOwnerStopPublicationAttempts.append(cut.operation)
            do { before = try nativeOwnerStopSnapshotObservation() }
            catch { logger.error("Inert native Owner Stop observation failed; native teardown continues") }
        }
        #endif
        do {
            switch try screenVideoAdaptationOwnerBoundary.publishActualStop(entry, on: self) {
            case .accepted:
                #if DEBUG
                disposition = .accepted
                #endif
                break
            case .refused, .superseded: break
            }
        } catch BelugaNetworkAdaptationOwnerError.reentry {
            #if DEBUG
            disposition = .reentry
            #endif
            logger.error("Native Owner Stop publication reentered; native teardown continues")
        } catch BelugaNetworkAdaptationOwnerError.refused {
            logger.error("Native Owner Stop publication refused; native teardown continues")
        } catch {
            #if DEBUG
            disposition = .malformed
            #endif
            logger.error("Native Owner Stop publication failed; native teardown continues")
        }
        #if DEBUG
        if entry.permitsInertNegativeControls, let before {
            do {
                // Diagnostic recapture is outside the held frame, never a Release read.
                nativeOwnerStopPublicationCuts.append(.init(operation: cut.operation, before: before,
                    after: try nativeOwnerStopSnapshotObservation(retainingAnchor: before.anchor),
                    disposition: disposition))
            } catch { logger.error("Inert native Owner Stop observation failed; native teardown continues") }
        }
        #endif
    }

    private func networkAdaptationActualStopEntry(_ cut: BelugaNetworkAdaptationActualStopEntry.Cut,
        origin: BelugaNetworkAdaptationActualStopEntry.Origin)
        -> BelugaNetworkAdaptationActualStopEntry {
        .init(owner: self, boundary: screenVideoAdaptationOwnerBoundary, cut: cut, origin: origin,
            generation: peerGeneration, sourcePeer: peer, coordinator: recoveryCoordinator,
            source: captureSource, sink: captureSink, authorization: captureAuthorization,
            forwarding: captureForwardingAuthorization, audioSource: audioSource, audioSink: audioSink,
            audioAuthorization: audioAuthorization, visibilityEpoch: screenVisibilityCommandEpoch,
            recoveryEpoch: recoveryProofEpoch)
    }

    func networkAdaptationActualStopAdmit(_ entry: BelugaNetworkAdaptationActualStopEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary, key: [UInt64]) -> Bool {
        let fresh = entry.phase == .fresh
        // Consume even a wrong-boundary attempt; a failed capability cannot replay.
        entry.phase = .retired
        guard fresh, entry.owner === self, entry.boundary === boundary,
              boundary === screenVideoAdaptationOwnerBoundary, key == entry.cut.key,
              networkAdaptationActualStopNativeWitnessIsCurrent(entry) else { return false }
        entry.phase = .admitted
        return true
    }

    private func networkAdaptationActualStopNativeWitnessIsCurrent(_ entry: BelugaNetworkAdaptationActualStopEntry) -> Bool {
        switch entry.origin {
        case .nativeShutdown:
            guard Self.allNetworkAdaptationOwnerWritersAreEnrolled,
                  Self.ownedStopPublicationIsEnrolled else { return false }
        #if DEBUG
        case .inertFixture:
            // An opt-in cannot survive a later start into partially migrated media.
            guard audioRoutingIsInertPolicyFixture, !isStarted,
                  peer == nil, captureSource == nil, captureSink == nil,
                  audioSource == nil, audioSink == nil,
                  nativeOwnerStopPublicationEnabled else { return false }
        #endif
        }
        guard isStopped, stopIsInProgress,
              pendingNativeOwnerStopEntry === entry,
              entry.owner === self, entry.boundary === screenVideoAdaptationOwnerBoundary,
              entry.generation == peerGeneration, entry.sourcePeer === peer,
              entry.coordinator === recoveryCoordinator, entry.source === captureSource,
              entry.sink === captureSink, entry.authorization === captureAuthorization,
              entry.forwarding === captureForwardingAuthorization, entry.audioSource === audioSource,
              entry.audioSink === audioSink, entry.audioAuthorization === audioAuthorization,
              entry.visibilityEpoch == screenVisibilityCommandEpoch,
              entry.recoveryEpoch == recoveryProofEpoch else { return false }
        switch entry.cut {
        case .endShow: return nativeOwnerStopPublicationStage == .endShow
        case .stopSampling:
            return nativeOwnerStopPublicationStage == .stopSampling && screenVideoAdaptationTask == nil
        }
    }

    func networkAdaptationActualStopIsCurrent(_ entry: BelugaNetworkAdaptationActualStopEntry) -> Bool {
        entry.phase == .admitted && networkAdaptationActualStopNativeWitnessIsCurrent(entry)
    }

    func networkAdaptationActualStopMatches(_ entry: BelugaNetworkAdaptationActualStopEntry,
        slot: ObjectIdentifier, key: [UInt64], generation: UInt64) -> Bool {
        slot == ObjectIdentifier(entry) && key == entry.cut.key && generation == entry.generation
            && networkAdaptationActualStopIsCurrent(entry)
    }

    func networkAdaptationActualStopCapture(_ entry: BelugaNetworkAdaptationActualStopEntry,
        retainingAnchor: ContinuousClock.Instant?) throws -> BelugaNetworkAdaptationOwnerSnapshot {
        guard networkAdaptationActualStopIsCurrent(entry) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return try BelugaNetworkAdaptationOwnerSnapshot.capture(screenVideoAdaptationOwner,
            retainingAnchor: retainingAnchor)
    }

    // Only the held codec can construct this packet. Retire before the sole fixed
    // assignment; no callback, clock, recapture, await or throwing work follows it.
    func networkAdaptationActualStopCommit(_ packet: BelugaNetworkAdaptationActualStopCommit) {
        packet.entry.phase = .retired
        screenVideoAdaptationOwner = packet.replacement.value
    }
}

// Constructor custody is separate from the resolved optional minimum. In
// particular unread, nil and Some(0) are three different states.
final class BelugaNetworkAdaptationActualEpochEntry {
    fileprivate enum Origin {
        case nativeEpoch
        #if DEBUG
        case inertFixture
        #endif
    }
    fileprivate enum Phase { case fresh, admitted, sealed, published, retired }
    fileprivate enum Payload { case unread, sealed(UInt64?) }
    let owner: WorldwideScreenService
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let generation: UInt64
    fileprivate let origin: Origin
    fileprivate var phase: Phase = .fresh
    fileprivate var payload: Payload = .unread
    fileprivate let sourcePeer: WebRTCPeer?
    fileprivate let coordinator: ICERecoveryCoordinator?
    fileprivate let source: ScreenVideoCaptureSource?
    fileprivate let sink: WorldwideScreenSampleSink?
    fileprivate let authorization: WebRTCControlAuthorization?
    fileprivate let forwarding: WebRTCControlAuthorization?
    fileprivate let audioSource: SystemAudioCaptureSource?
    fileprivate let audioSink: WorldwideSystemAudioSampleSink?
    fileprivate let audioAuthorization: WebRTCAudioAuthorization?
    fileprivate let visibilityEpoch: UInt64
    fileprivate let recoveryEpoch: UInt64
    #if DEBUG
    fileprivate var minimumResolutionCount = 0
    fileprivate var peerGetterCount = 0
    fileprivate var storeCount = 0
    #endif
    var permitsInertNegativeControls: Bool {
        #if DEBUG
        origin == .inertFixture
        #else
        false
        #endif
    }
    fileprivate init(owner: WorldwideScreenService, boundary: BelugaNetworkAdaptationOwnerBoundary,
        origin: Origin, generation: UInt64, sourcePeer: WebRTCPeer?, coordinator: ICERecoveryCoordinator?,
        source: ScreenVideoCaptureSource?, sink: WorldwideScreenSampleSink?,
        authorization: WebRTCControlAuthorization?, forwarding: WebRTCControlAuthorization?,
        audioSource: SystemAudioCaptureSource?, audioSink: WorldwideSystemAudioSampleSink?,
        audioAuthorization: WebRTCAudioAuthorization?, visibilityEpoch: UInt64, recoveryEpoch: UInt64) {
        self.owner = owner; self.boundary = boundary; self.origin = origin; self.generation = generation
        self.sourcePeer = sourcePeer; self.coordinator = coordinator; self.source = source; self.sink = sink
        self.authorization = authorization; self.forwarding = forwarding
        self.audioSource = audioSource; self.audioSink = audioSink; self.audioAuthorization = audioAuthorization
        self.visibilityEpoch = visibilityEpoch; self.recoveryEpoch = recoveryEpoch
    }
}

extension WorldwideScreenService {
    private func networkAdaptationActualEpochPublicationOrigin() -> BelugaNetworkAdaptationActualEpochEntry.Origin? {
        if Self.allNetworkAdaptationOwnerWritersAreEnrolled && Self.ownedStopPublicationIsEnrolled {
            return .nativeEpoch
        }
        #if DEBUG
        if nativeOwnerEpochPublicationEnabled { return .inertFixture }
        #endif
        return nil
    }

    private func networkAdaptationActualEpochEntry() throws -> BelugaNetworkAdaptationActualEpochEntry {
        guard pendingNativeOwnerEpochEntry == nil,
              let origin = networkAdaptationActualEpochPublicationOrigin() else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        let entry = BelugaNetworkAdaptationActualEpochEntry(owner: self,
            boundary: screenVideoAdaptationOwnerBoundary, origin: origin,
            generation: peerGeneration, sourcePeer: peer, coordinator: recoveryCoordinator,
            source: captureSource, sink: captureSink, authorization: captureAuthorization,
            forwarding: captureForwardingAuthorization, audioSource: audioSource, audioSink: audioSink,
            audioAuthorization: audioAuthorization, visibilityEpoch: screenVisibilityCommandEpoch,
            recoveryEpoch: recoveryProofEpoch)
        pendingNativeOwnerEpochEntry = entry
        return entry
    }

    func networkAdaptationActualEpochAdmit(_ entry: BelugaNetworkAdaptationActualEpochEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary) -> Bool {
        let fresh = entry.phase == .fresh
        entry.phase = .retired
        guard fresh, entry.owner === self, entry.boundary === boundary,
              boundary === screenVideoAdaptationOwnerBoundary,
              networkAdaptationActualEpochNativeWitnessIsCurrent(entry) else { return false }
        entry.phase = .admitted
        return true
    }

    private func networkAdaptationActualEpochNativeWitnessIsCurrent(_ entry: BelugaNetworkAdaptationActualEpochEntry) -> Bool {
        switch entry.origin {
        case .nativeEpoch:
            guard Self.allNetworkAdaptationOwnerWritersAreEnrolled,
                  Self.ownedStopPublicationIsEnrolled else { return false }
        #if DEBUG
        case .inertFixture:
            guard audioRoutingIsInertPolicyFixture, !isStarted,
                  peer == nil, captureSource == nil, captureSink == nil,
                  audioSource == nil, audioSink == nil,
                  nativeOwnerEpochPublicationEnabled else { return false }
        #endif
        }
        // Hide, cleanup and post-ACK need custody, not active-media health votes.
        guard pendingNativeOwnerEpochEntry === entry,
              entry.owner === self, entry.boundary === screenVideoAdaptationOwnerBoundary,
              entry.generation == peerGeneration, entry.sourcePeer === peer,
              entry.coordinator === recoveryCoordinator, entry.source === captureSource,
              entry.sink === captureSink, entry.authorization === captureAuthorization,
              entry.forwarding === captureForwardingAuthorization, entry.audioSource === audioSource,
              entry.audioSink === audioSink, entry.audioAuthorization === audioAuthorization,
              entry.visibilityEpoch == screenVisibilityCommandEpoch,
              entry.recoveryEpoch == recoveryProofEpoch else { return false }
        return true
    }

    func networkAdaptationActualEpochSealMinimum(_ entry: BelugaNetworkAdaptationActualEpochEntry) throws -> UInt64? {
        guard entry.phase == .admitted, case .unread = entry.payload,
              networkAdaptationActualEpochNativeWitnessIsCurrent(entry) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        #if DEBUG
        if entry.permitsInertNegativeControls {
            entry.minimumResolutionCount += 1
            if entry.sourcePeer != nil { entry.peerGetterCount += 1 }
        }
        #endif
        let minimum = entry.sourcePeer?.minimumNextStatisticsCollectionSequence()
        guard networkAdaptationActualEpochNativeWitnessIsCurrent(entry) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        entry.payload = .sealed(minimum)
        entry.phase = .sealed
        return minimum
    }

    func networkAdaptationActualEpochIsCurrent(_ entry: BelugaNetworkAdaptationActualEpochEntry) -> Bool {
        guard entry.phase == .sealed, case .sealed = entry.payload else { return false }
        return networkAdaptationActualEpochNativeWitnessIsCurrent(entry)
    }

    func networkAdaptationActualEpochMatches(_ entry: BelugaNetworkAdaptationActualEpochEntry,
        slot: ObjectIdentifier, key: [UInt64], generation: UInt64) -> Bool {
        guard case let .sealed(minimum) = entry.payload else { return false }
        return slot == ObjectIdentifier(entry) && generation == entry.generation
            && key == [216, 0, 0, minimum ?? 0, 0, minimum == nil ? 0 : 1]
            && networkAdaptationActualEpochIsCurrent(entry)
    }

    func networkAdaptationActualEpochCapture(_ entry: BelugaNetworkAdaptationActualEpochEntry,
        retainingAnchor: ContinuousClock.Instant?) throws -> BelugaNetworkAdaptationOwnerSnapshot {
        guard networkAdaptationActualEpochIsCurrent(entry) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return try BelugaNetworkAdaptationOwnerSnapshot.capture(screenVideoAdaptationOwner,
            retainingAnchor: retainingAnchor)
    }

    func networkAdaptationActualEpochRetire(_ entry: BelugaNetworkAdaptationActualEpochEntry) {
        if entry.phase != .published { entry.phase = .retired }
        guard entry.owner === self, entry.boundary === screenVideoAdaptationOwnerBoundary,
              pendingNativeOwnerEpochEntry === entry else { return }
        pendingNativeOwnerEpochEntry = nil
    }

    func networkAdaptationActualEpochCommit(_ packet: BelugaNetworkAdaptationActualEpochCommit) {
        precondition(pendingNativeOwnerEpochEntry === packet.entry)
        packet.entry.phase = .published
        pendingNativeOwnerEpochEntry = nil
        #if DEBUG
        if packet.entry.permitsInertNegativeControls { packet.entry.storeCount += 1 }
        #endif
        screenVideoAdaptationOwner = packet.replacement.value
    }
}

// Append to WorldwideScreenService.swift. No production event calls this seam yet.
/// Reset cleanup owns the original latch classification, not a caller vote.
/// Current resource custody deliberately does not equate the older binding's
/// generation with the actor generation already advanced by Stop/startPeer.
final class BelugaNetworkAdaptationActualResetEntry {
    fileprivate enum Origin {
        case nativeReset
        #if DEBUG
        case inertFixture
        #endif
    }
    fileprivate enum Outcome { case claimedFailure, alreadyCommitted, alreadyFailureClaimed }
    fileprivate enum Phase { case fresh, admitted, published, retired }
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let generation: UInt64
    fileprivate let owner: WorldwideScreenService
    fileprivate let origin: Origin
    fileprivate let outcome: Outcome
    fileprivate let native: BelugaNetworkAdaptationActualEpochEntry
    fileprivate let binding: WorldwideScreenMediaSuspensionCoordinator.Binding
    fileprivate let notice: WebRTCScreenMediaSuspensionNotice
    fileprivate let attemptID: UUID
    fileprivate let latch: WorldwideScreenAutomaticResumeCommitLatch
    fileprivate let probe: WebRTCControlAuthorization?
    fileprivate let forwarding: WebRTCControlAuthorization?
    fileprivate let markerBoundary: WorldwideScreenSampleSink.ResumeMarkerBoundary?
    fileprivate let markerReady: WebRTCScreenMediaMarkerReady?
    fileprivate let markerPresentation: WebRTCScreenMediaMarkerPresentation?
    fileprivate let suspension: WorldwideScreenMediaSuspensionCoordinator.Snapshot
    fileprivate var phase = Phase.fresh
    var operation: UInt32 { outcome == .claimedFailure ? 218 : 107 }
    var key: [UInt64] { operation == 218 ? [218, 0, 0, 0, 0, 0] : [107, 0, 0, 0, 0] }
    var permitsInertNegativeControls: Bool {
        #if DEBUG
        origin == .inertFixture
        #else
        false
        #endif
    }
    fileprivate init(owner: WorldwideScreenService, origin: Origin, outcome: Outcome,
        native: BelugaNetworkAdaptationActualEpochEntry,
        binding: WorldwideScreenMediaSuspensionCoordinator.Binding,
        notice: WebRTCScreenMediaSuspensionNotice, attemptID: UUID,
        latch: WorldwideScreenAutomaticResumeCommitLatch,
        probe: WebRTCControlAuthorization?, forwarding: WebRTCControlAuthorization?,
        markerBoundary: WorldwideScreenSampleSink.ResumeMarkerBoundary?,
        markerReady: WebRTCScreenMediaMarkerReady?, markerPresentation: WebRTCScreenMediaMarkerPresentation?,
        suspension: WorldwideScreenMediaSuspensionCoordinator.Snapshot) {
        self.owner = owner; self.origin = origin; self.outcome = outcome; self.native = native
        boundary = native.boundary; generation = native.generation
        self.binding = binding; self.notice = notice; self.attemptID = attemptID; self.latch = latch
        self.probe = probe; self.forwarding = forwarding; self.markerBoundary = markerBoundary
        self.markerReady = markerReady; self.markerPresentation = markerPresentation; self.suspension = suspension
    }
}

extension WorldwideScreenService {
    private func networkAdaptationActualResetOrigin() -> BelugaNetworkAdaptationActualResetEntry.Origin? {
        if Self.allNetworkAdaptationOwnerWritersAreEnrolled && Self.ownedStopPublicationIsEnrolled {
            return .nativeReset
        }
        #if DEBUG
        if nativeOwnerResetPublicationEnabled { return .inertFixture }
        #endif
        return nil
    }

    // The cancellation and latch claim are original native cleanup effects. They
    // precede guarded policy admission even when that admission is busy/exhausted.
    // No production reset caller selects this wrapper yet.
    private func publishActualResetOwner() throws {
        guard let origin = networkAdaptationActualResetOrigin() else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        let original = automaticScreenMediaResumeContext
        let suspension = screenMediaSuspension.snapshot
        defer { retireOriginalResumeResetContext(original, suspension: suspension) }
        cancelAutomaticScreenMediaResumeTimeout()
        guard let context = original else { return }
        guard pendingNativeOwnerResetEntry == nil, context.ownerResetEntryID == nil else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        let claimed = context.finalAcknowledgementCommit.claimFailure()
        let outcome: BelugaNetworkAdaptationActualResetEntry.Outcome = claimed ? .claimedFailure
            : (context.finalAcknowledgementCommit.isCommitted ? .alreadyCommitted : .alreadyFailureClaimed)
        let nativeOrigin: BelugaNetworkAdaptationActualEpochEntry.Origin
        switch origin {
        case .nativeReset: nativeOrigin = .nativeEpoch
        #if DEBUG
        case .inertFixture: nativeOrigin = .inertFixture
        #endif
        }
        // Reuse only the sealed resource-custody carrier, not its epoch payload,
        // admission or pending slot. No epoch getter is resolved by this reset.
        let native = BelugaNetworkAdaptationActualEpochEntry(owner: self,
            boundary: screenVideoAdaptationOwnerBoundary,
            origin: nativeOrigin,
            generation: peerGeneration, sourcePeer: peer, coordinator: recoveryCoordinator,
            source: captureSource, sink: captureSink, authorization: captureAuthorization,
            forwarding: captureForwardingAuthorization, audioSource: audioSource, audioSink: audioSink,
            audioAuthorization: audioAuthorization, visibilityEpoch: screenVisibilityCommandEpoch,
            recoveryEpoch: recoveryProofEpoch)
        let entry = BelugaNetworkAdaptationActualResetEntry(owner: self, origin: origin, outcome: outcome,
            native: native, binding: context.binding, notice: context.notice, attemptID: context.attemptID,
            latch: context.finalAcknowledgementCommit, probe: context.probeAuthorization,
            forwarding: context.forwardingAuthorization, markerBoundary: context.boundary,
            markerReady: context.markerReady, markerPresentation: context.markerPresentation, suspension: suspension)
        automaticScreenMediaResumeContext?.ownerResetEntryID = ObjectIdentifier(entry)
        pendingNativeOwnerResetEntry = entry
        defer { networkAdaptationActualResetRetire(entry) }
        #if DEBUG
        nativeOwnerResetAttemptedOperations.append(entry.operation)
        let boundary = nativeOwnerResetFault == .wrongBoundary ? BelugaNetworkAdaptationOwnerBoundary()
            : screenVideoAdaptationOwnerBoundary
        if nativeOwnerResetFault == .outerReentry {
            try boundary.testSwallowedActualResetOuterReentry(entry, on: self)
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        #else
        let boundary = screenVideoAdaptationOwnerBoundary
        #endif
        guard case .accepted = try boundary.publishActualReset(entry, on: self) else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        #if DEBUG
        nativeOwnerResetAfterPrimary = try nativeOwnerStopSnapshotObservation()
        #endif
        if entry.operation == 107 {
            let epoch = try networkAdaptationActualEpochEntry()
            defer { networkAdaptationActualEpochRetire(epoch) }
            #if DEBUG
            nativeOwnerResetAttemptedOperations.append(216)
            #endif
            guard case .accepted = try screenVideoAdaptationOwnerBoundary.publishActualEpoch(epoch, on: self) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
        }
    }

    private func retireOriginalResumeResetContext(_ original: AutomaticScreenMediaResumeContext?,
        suspension: WorldwideScreenMediaSuspensionCoordinator.Snapshot) {
        guard screenMediaSuspension.snapshot == suspension else { return }
        if let original {
            guard let current = automaticScreenMediaResumeContext,
                  current.attemptID == original.attemptID, current.binding == original.binding,
                  current.notice == original.notice,
                  current.finalAcknowledgementCommit === original.finalAcknowledgementCommit,
                  current.probeAuthorization === original.probeAuthorization,
                  current.forwardingAuthorization === original.forwardingAuthorization,
                  current.boundary == original.boundary, current.markerReady == original.markerReady,
                  current.markerPresentation == original.markerPresentation else { return }
            original.probeAuthorization?.revoke()
            original.forwardingAuthorization?.revoke()
        } else {
            guard automaticScreenMediaResumeContext == nil else { return }
        }
        automaticScreenMediaResumeContext = nil
        screenMediaSuspension.retire()
    }

    private func networkAdaptationActualResetWitness(_ entry: BelugaNetworkAdaptationActualResetEntry) -> Bool {
        switch entry.origin {
        case .nativeReset:
            guard Self.allNetworkAdaptationOwnerWritersAreEnrolled,
                  Self.ownedStopPublicationIsEnrolled else { return false }
        #if DEBUG
        case .inertFixture:
            guard audioRoutingIsInertPolicyFixture, !isStarted,
                  peer == nil, captureSource == nil, captureSink == nil, audioSource == nil, audioSink == nil,
                  nativeOwnerResetPublicationEnabled else { return false }
        #endif
        }
        let n = entry.native
        guard pendingNativeOwnerResetEntry === entry, entry.owner === self,
              entry.boundary === screenVideoAdaptationOwnerBoundary,
              entry.generation == peerGeneration, n.sourcePeer === peer,
              n.coordinator === recoveryCoordinator, n.source === captureSource, n.sink === captureSink,
              n.authorization === captureAuthorization, n.forwarding === captureForwardingAuthorization,
              n.audioSource === audioSource, n.audioSink === audioSink, n.audioAuthorization === audioAuthorization,
              n.visibilityEpoch == screenVisibilityCommandEpoch, n.recoveryEpoch == recoveryProofEpoch,
              screenMediaSuspension.snapshot == entry.suspension,
              let context = automaticScreenMediaResumeContext,
              context.ownerResetEntryID == ObjectIdentifier(entry),
              context.attemptID == entry.attemptID, context.binding == entry.binding, context.notice == entry.notice,
              context.finalAcknowledgementCommit === entry.latch,
              context.probeAuthorization === entry.probe, context.forwardingAuthorization === entry.forwarding,
              context.boundary == entry.markerBoundary, context.markerReady == entry.markerReady,
              context.markerPresentation == entry.markerPresentation else { return false }
        return true
    }

    func networkAdaptationActualResetAdmit(_ entry: BelugaNetworkAdaptationActualResetEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary, key: [UInt64]) -> Bool {
        let fresh = entry.phase == .fresh
        entry.phase = .retired
        guard fresh, entry.boundary === boundary, key == entry.key,
              networkAdaptationActualResetWitness(entry) else { return false }
        entry.phase = .admitted
        return true
    }
    func networkAdaptationActualResetIsCurrent(_ entry: BelugaNetworkAdaptationActualResetEntry) -> Bool {
        entry.phase == .admitted && networkAdaptationActualResetWitness(entry)
    }
    func networkAdaptationActualResetMatches(_ entry: BelugaNetworkAdaptationActualResetEntry,
        slot: ObjectIdentifier, key: [UInt64], generation: UInt64) -> Bool {
        slot == ObjectIdentifier(entry) && key == entry.key
            && generation == entry.generation && networkAdaptationActualResetIsCurrent(entry)
    }
    func networkAdaptationActualResetCapture(_ entry: BelugaNetworkAdaptationActualResetEntry,
        retainingAnchor: ContinuousClock.Instant?) throws -> BelugaNetworkAdaptationOwnerSnapshot {
        guard networkAdaptationActualResetIsCurrent(entry) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return try BelugaNetworkAdaptationOwnerSnapshot.capture(screenVideoAdaptationOwner, retainingAnchor: retainingAnchor)
    }
    func networkAdaptationActualResetRetire(_ entry: BelugaNetworkAdaptationActualResetEntry) {
        if entry.phase != .published { entry.phase = .retired }
        guard entry.owner === self, pendingNativeOwnerResetEntry === entry else { return }
        pendingNativeOwnerResetEntry = nil
    }
    func networkAdaptationActualResetCommit(_ packet: BelugaNetworkAdaptationActualResetCommit) {
        precondition(pendingNativeOwnerResetEntry === packet.entry)
        packet.entry.phase = .published
        pendingNativeOwnerResetEntry = nil
        screenVideoAdaptationOwner = packet.replacement.value
    }
}

// Append to WorldwideScreenService.swift. No production event calls this seam yet.
// Construction is sealed to this actor file; no caller can supply entry wire votes.
final class BelugaNetworkAdaptationNativePrepareEntry {
    let owner: WorldwideScreenService
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let value: BelugaNetworkAdaptationOwnerValue
    let report: WebRTCScreenVideoStatisticsReport
    let generation: UInt64
    let revision: UInt64
    let flags: UInt32
    let active: Bool
    let allowsResume: Bool
    fileprivate let sourcePeer: WebRTCPeer
    fileprivate let source: ScreenVideoCaptureSource?
    fileprivate let sink: WorldwideScreenSampleSink?
    fileprivate let captureAuthorization: WebRTCControlAuthorization?
    fileprivate let forwardingAuthorization: WebRTCControlAuthorization?
    fileprivate let visibilityEpoch: UInt64

    fileprivate init(owner: WorldwideScreenService, boundary: BelugaNetworkAdaptationOwnerBoundary,
        value: BelugaNetworkAdaptationOwnerValue,
        report: WebRTCScreenVideoStatisticsReport, generation: UInt64, revision: UInt64,
        flags: UInt32, active: Bool, allowsResume: Bool, sourcePeer: WebRTCPeer,
        source: ScreenVideoCaptureSource?, sink: WorldwideScreenSampleSink?,
        captureAuthorization: WebRTCControlAuthorization?, forwardingAuthorization: WebRTCControlAuthorization?,
        visibilityEpoch: UInt64) {
        self.owner = owner; self.boundary = boundary; self.value = value; self.report = report
        self.generation = generation; self.revision = revision; self.flags = flags
        self.active = active; self.allowsResume = allowsResume; self.sourcePeer = sourcePeer
        self.source = source; self.sink = sink; self.captureAuthorization = captureAuthorization
        self.forwardingAuthorization = forwardingAuthorization; self.visibilityEpoch = visibilityEpoch
    }
}

extension WorldwideScreenService {
    // Called ONLY by Boundary while its guard is held on this actor's executor.
    // The report is telemetry, not authority. Future collector wiring must keep
    // the original post-await cancellation/freshness/visibility/resource gates.
    func networkAdaptationTerminalPrepareEntry(boundary: BelugaNetworkAdaptationOwnerBoundary,
        report: WebRTCScreenVideoStatisticsReport,
        sourcePeer: WebRTCPeer, generation: UInt64, revision: UInt64,
        allowsResume: Bool) -> BelugaNetworkAdaptationNativePrepareEntry? {
        guard screenVideoAdaptationOwnerBoundary === boundary,
              automaticScreenMediaResumeContext == nil,
              peer === sourcePeer, peerGeneration == generation,
              screenVideoAdaptationOwner.revision == revision else { return nil }
        // Same short-circuit order as the original adaptation entry. Retain the
        // actual objects even when an earlier vote skips a later validity query.
        let source = captureSource, sink = captureSink
        let authorization = captureAuthorization
        let forwarding = captureForwardingAuthorization
        var flags: UInt32 = 1 | 2
        if sink != nil { flags |= 8 }
        let active: Bool
        if source != nil {
            flags |= 4
            if sink != nil {
                if authorization?.isValid == true {
                    flags |= 16
                    if forwarding?.isValid == true {
                        flags |= 32
                        if forwarding.map({ sink?.allowsActiveUse(authorizedBy: $0) == true }) == true {
                            flags |= 64
                        }
                    }
                }
            }
        }
        active = flags & 0x7c == 0x7c
        guard active || allowsResume else { return nil }
        if screenMediaSuspension.isAutomaticallySuspended { flags |= 128 }
        return .init(owner: self, boundary: boundary, value: screenVideoAdaptationOwner, report: report,
            generation: generation, revision: revision, flags: flags, active: active,
            allowsResume: allowsResume, sourcePeer: sourcePeer, source: source, sink: sink,
            captureAuthorization: authorization, forwardingAuthorization: forwarding,
            visibilityEpoch: screenVisibilityCommandEpoch)
    }

    // Rebuild from the actual current actor state, never from Prepared.policy.
    // Strong references are custody, not authorization; revoked tokens and a
    // closed sink generation still refuse. No native effect or clock is invoked.
    func networkAdaptationTerminalPrepareIsCurrent(_ entry: BelugaNetworkAdaptationNativePrepareEntry,
        original: BelugaNetworkAdaptationOwnerSnapshot) throws -> Bool {
        guard entry.owner === self, screenVideoAdaptationOwnerBoundary === entry.boundary,
              captureSource === entry.source,
              captureSink === entry.sink, captureAuthorization === entry.captureAuthorization,
              captureForwardingAuthorization === entry.forwardingAuthorization,
              screenVisibilityCommandEpoch == entry.visibilityEpoch,
              let current = networkAdaptationTerminalPrepareEntry(boundary: entry.boundary, report: entry.report,
                sourcePeer: entry.sourcePeer, generation: entry.generation,
                revision: entry.revision, allowsResume: entry.allowsResume),
              current.flags == entry.flags, current.active == entry.active else { return false }
        let captured = try BelugaNetworkAdaptationOwnerSnapshot.capture(
            screenVideoAdaptationOwner, retainingAnchor: original.anchor)
        return BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(captured.atoms, original.atoms)
            && captured.times == original.times && captured.anchor == original.anchor
            && captured.route == original.route
    }

    // Capture ACTUAL storage again; Prepared.value is not a current-state witness.
    func networkAdaptationTerminalInactiveCapture(_ entry: BelugaNetworkAdaptationNativePrepareEntry,
        original: BelugaNetworkAdaptationOwnerSnapshot) throws -> BelugaNetworkAdaptationOwnerSnapshot? {
        guard !entry.active, entry.allowsResume,
              try networkAdaptationTerminalPrepareIsCurrent(entry, original: original) else { return nil }
        return try .capture(screenVideoAdaptationOwner, retainingAnchor: original.anchor)
    }

    // Codec-file sealed packet, synchronous final store only. No callbacks,
    // fallible import, native resume effect or new permission follows this write.
    func networkAdaptationTerminalInactiveCommit(_ packet: BelugaNetworkAdaptationTerminalInactiveCommit) {
        precondition(packet.entry.owner === self)
        precondition(screenVideoAdaptationOwnerBoundary === packet.entry.boundary)
        screenVideoAdaptationOwner = packet.replacement.value
    }
}

// General501 retains actual native origin separately from telemetry. No
// production collector selects this seam until every owner writer is enrolled.
final class BelugaNetworkAdaptationNativeGeneralPrepareEntry {
    let owner: WorldwideScreenService
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let value: BelugaNetworkAdaptationOwnerValue
    let snapshot: WebRTCStatisticsSnapshot?
    let timestamp: Double?
    let generation: UInt64
    let revision: UInt64
    let capacityOnly: Bool
    let flags: UInt32
    let active: Bool
    let allowsResume: Bool
    fileprivate let peer: WebRTCPeer
    fileprivate let source: ScreenVideoCaptureSource?
    fileprivate let sink: WorldwideScreenSampleSink?
    fileprivate let captureAuthorization: WebRTCControlAuthorization?
    fileprivate let forwardingAuthorization: WebRTCControlAuthorization?
    fileprivate let visibilityEpoch: UInt64
    fileprivate init(owner: WorldwideScreenService, boundary: BelugaNetworkAdaptationOwnerBoundary,
        value: BelugaNetworkAdaptationOwnerValue, snapshot: WebRTCStatisticsSnapshot?, timestamp: Double?,
        generation: UInt64, revision: UInt64, capacityOnly: Bool, flags: UInt32, active: Bool,
        allowsResume: Bool, peer: WebRTCPeer, source: ScreenVideoCaptureSource?, sink: WorldwideScreenSampleSink?,
        captureAuthorization: WebRTCControlAuthorization?, forwardingAuthorization: WebRTCControlAuthorization?,
        visibilityEpoch: UInt64) {
        self.owner = owner; self.boundary = boundary; self.value = value
        self.snapshot = snapshot; self.timestamp = timestamp; self.generation = generation; self.revision = revision
        self.capacityOnly = capacityOnly; self.flags = flags; self.active = active; self.allowsResume = allowsResume
        self.peer = peer; self.source = source; self.sink = sink; self.captureAuthorization = captureAuthorization
        self.forwardingAuthorization = forwardingAuthorization; self.visibilityEpoch = visibilityEpoch
    }
}

extension WorldwideScreenService {
    func networkAdaptationGeneralPrepareEntry(boundary: BelugaNetworkAdaptationOwnerBoundary,
        snapshot: WebRTCStatisticsSnapshot?, timestamp: Double?, sourcePeer: WebRTCPeer,
        generation: UInt64, revision: UInt64, capacityOnly: Bool,
        allowsResume: Bool) -> BelugaNetworkAdaptationNativeGeneralPrepareEntry? {
        guard screenVideoAdaptationOwnerBoundary === boundary,
              automaticScreenMediaResumeContext == nil, peer === sourcePeer,
              peerGeneration == generation, screenVideoAdaptationOwner.revision == revision else { return nil }
        let source = captureSource, sink = captureSink
        let authorization = captureAuthorization, forwarding = captureForwardingAuthorization
        var flags: UInt32 = 1 | 2
        if sink != nil { flags |= 8 }
        // Original left-to-right active-use short circuit; a retained reference
        // alone does not authorize a revoked token or closed sink generation.
        if source != nil {
            flags |= 4
            if sink != nil {
                if authorization?.isValid == true {
                    flags |= 16
                    if forwarding?.isValid == true {
                        flags |= 32
                        if forwarding.map({ sink?.allowsActiveUse(authorizedBy: $0) == true }) == true { flags |= 64 }
                    }
                }
            }
        }
        let active = flags & 0x7c == 0x7c
        guard active || allowsResume else { return nil }
        if screenMediaSuspension.isAutomaticallySuspended { flags |= 128 }
        return .init(owner: self, boundary: boundary, value: screenVideoAdaptationOwner,
            snapshot: snapshot, timestamp: timestamp, generation: generation, revision: revision,
            capacityOnly: capacityOnly, flags: flags, active: active, allowsResume: allowsResume,
            peer: sourcePeer, source: source, sink: sink, captureAuthorization: authorization,
            forwardingAuthorization: forwarding, visibilityEpoch: screenVisibilityCommandEpoch)
    }

    func networkAdaptationGeneralPrepareIsCurrent(_ entry: BelugaNetworkAdaptationNativeGeneralPrepareEntry,
        original: BelugaNetworkAdaptationOwnerSnapshot) throws -> Bool {
        guard entry.owner === self, screenVideoAdaptationOwnerBoundary === entry.boundary,
              captureSource === entry.source, captureSink === entry.sink,
              captureAuthorization === entry.captureAuthorization,
              captureForwardingAuthorization === entry.forwardingAuthorization,
              screenVisibilityCommandEpoch == entry.visibilityEpoch,
              let current = networkAdaptationGeneralPrepareEntry(boundary: entry.boundary,
                snapshot: entry.snapshot, timestamp: entry.timestamp, sourcePeer: entry.peer,
                generation: entry.generation, revision: entry.revision,
                capacityOnly: entry.capacityOnly, allowsResume: entry.allowsResume),
              current.flags == entry.flags, current.active == entry.active else { return false }
        let captured = try BelugaNetworkAdaptationOwnerSnapshot.capture(screenVideoAdaptationOwner,
            retainingAnchor: original.anchor)
        return BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(captured.atoms, original.atoms)
            && captured.times == original.times && captured.anchor == original.anchor && captured.route == original.route
    }
}

// Constructor-sealed actual701 custody. No public scalar resource flags can
// manufacture any of these native references or authorize a sender await.
final class BelugaNetworkAdaptationNativeBeginActiveEntry {
    let value: BelugaNetworkAdaptationOwnerValue
    let resourceFlags: UInt32
    fileprivate let preparation: BelugaNetworkAdaptationNativeGeneralPrepareEntry
    fileprivate let source: ScreenVideoCaptureSource?
    fileprivate let sink: WorldwideScreenSampleSink?
    fileprivate let captureAuthorization: WebRTCControlAuthorization?
    fileprivate let forwardingAuthorization: WebRTCControlAuthorization?
    fileprivate let baseDimensions: ScreenVideoPixelDimensions?
    fileprivate let capturer: MacExternalVideoCapturer?
    fileprivate init(preparation: BelugaNetworkAdaptationNativeGeneralPrepareEntry,
        value: BelugaNetworkAdaptationOwnerValue, source: ScreenVideoCaptureSource?, sink: WorldwideScreenSampleSink?,
        captureAuthorization: WebRTCControlAuthorization?, forwardingAuthorization: WebRTCControlAuthorization?,
        baseDimensions: ScreenVideoPixelDimensions?, capturer: MacExternalVideoCapturer?) {
        self.preparation = preparation; self.value = value; self.source = source; self.sink = sink
        self.captureAuthorization = captureAuthorization; self.forwardingAuthorization = forwardingAuthorization
        self.baseDimensions = baseDimensions; self.capturer = capturer
        resourceFlags = (source == nil ? 0 : 1) | (sink == nil ? 0 : 2)
            | (captureAuthorization == nil ? 0 : 4) | (forwardingAuthorization == nil ? 0 : 8)
            | (baseDimensions == nil ? 0 : 16) | (capturer == nil ? 0 : 32)
    }
}

extension WorldwideScreenService {
    func networkAdaptationBeginActiveEntry(_ preparation: BelugaNetworkAdaptationNativeGeneralPrepareEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary) -> BelugaNetworkAdaptationNativeBeginActiveEntry? {
        // These are issuer/custody checks, NOT a replacement of the original
        // synchronous continuation with another peer/revision/active-use vote.
        guard preparation.owner === self, preparation.boundary === boundary,
              screenVideoAdaptationOwnerBoundary === boundary else { return nil }
        return .init(preparation: preparation, value: screenVideoAdaptationOwner,
            source: captureSource, sink: captureSink, captureAuthorization: captureAuthorization,
            forwardingAuthorization: captureForwardingAuthorization, baseDimensions: captureVideoBaseDimensions,
            capturer: preparation.peer.externalVideoCapturer)
    }

    func networkAdaptationBeginActiveRecapture(_ entry: BelugaNetworkAdaptationNativeBeginActiveEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary,
        retainingAnchor: ContinuousClock.Instant?) throws -> BelugaNetworkAdaptationOwnerSnapshot {
        guard entry.preparation.owner === self, entry.preparation.boundary === boundary,
              screenVideoAdaptationOwnerBoundary === boundary,
              captureSource === entry.source, captureSink === entry.sink,
              captureAuthorization === entry.captureAuthorization,
              captureForwardingAuthorization === entry.forwardingAuthorization,
              captureVideoBaseDimensions == entry.baseDimensions,
              entry.preparation.peer.externalVideoCapturer === entry.capturer else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        return try BelugaNetworkAdaptationOwnerSnapshot.capture(screenVideoAdaptationOwner,
            retainingAnchor: retainingAnchor)
    }

    // Constructor-sealed packet from the same held codec call. No callback,
    // recapture, clock, native effect, await or throwing work follows the store.
    func networkAdaptationBeginActiveCommit(_ packet: BelugaNetworkAdaptationActualBeginActiveCommit) {
        precondition(packet.entry.preparation.owner === self
            && packet.entry.preparation.boundary === packet.boundary
            && screenVideoAdaptationOwnerBoundary === packet.boundary)
        screenVideoAdaptationOwner = packet.replacement.value
    }
}

/// Non-Sendable, actor-file-sealed continuation. The retained seed includes
/// original report/route/13 native Instants/anchor and all actual701 custody.
/// Applying resources cannot be constructed from resourceFlags or scalar IDs.
final class BelugaNetworkAdaptationNativeAttempt {
    fileprivate struct ApplyResources {
        let source: ScreenVideoCaptureSource
        let sink: WorldwideScreenSampleSink
        let captureAuthorization: WebRTCControlAuthorization
        let forwardingAuthorization: WebRTCControlAuthorization
        let baseDimensions: ScreenVideoPixelDimensions
        let capturer: MacExternalVideoCapturer
    }
    fileprivate enum Phase { case ready, running, settled }
    fileprivate let owner: WorldwideScreenService
    fileprivate let seed: BelugaNetworkAdaptationNativeAttemptSeed
    fileprivate let sourcePeer: WebRTCPeer
    fileprivate let resources: ApplyResources?
    fileprivate var phase: Phase = .ready
    var intent: BelugaNetworkAdaptationNativeAttemptSeed.Intent { seed.intent }
    var beginActiveInvocation: UInt64 { seed.beginActiveInvocation }
    var consumerInvocation: UInt64 { seed.consumerInvocation }
    fileprivate init(owner: WorldwideScreenService,
        seed: BelugaNetworkAdaptationNativeAttemptSeed, resources: ApplyResources?) {
        self.owner = owner; self.seed = seed
        sourcePeer = seed.entry.preparation.peer; self.resources = resources
    }
    fileprivate func claim(by owner: WorldwideScreenService,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws {
        guard case .ready = phase else { throw BelugaNetworkAdaptationOwnerError.refused }
        phase = .running // A rejected wrong actor/boundary also spends this use.
        guard self.owner === owner, seed.boundary === boundary else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
    }
}

/// A NEW completion owns the exact original attempt and actual SDK settlement.
/// Success never discards a stale token; failure has no fabricated rollback
/// token. The handle/error are not exported, writable, or caller-supplied.
/// A future codec completion adapter must enter through an actor-file factory
/// that calls spend; no public scalar facts can manufacture that adapter entry.
final class BelugaNetworkAdaptationNativeCompletion {
    enum Kind { case finalAdoptionOnly, senderSucceeded, senderFailed }
    fileprivate enum Settlement {
        case finalAdoptionOnly
        case senderSucceeded(WebRTCScreenVideoEncodingUpdate)
        case senderFailed(any Error)
    }
    let kind: Kind
    fileprivate let attempt: BelugaNetworkAdaptationNativeAttempt
    fileprivate let settlement: Settlement
    #if DEBUG
    fileprivate var successDispatchTrace: NativeSuccessDispatchTrace?
    #endif
    private var spent = false
    fileprivate init(attempt: BelugaNetworkAdaptationNativeAttempt, settlement: Settlement) {
        self.attempt = attempt; self.settlement = settlement
        switch settlement {
        case .finalAdoptionOnly: kind = .finalAdoptionOnly
        case .senderSucceeded: kind = .senderSucceeded
        case .senderFailed: kind = .senderFailed
        }
    }
    fileprivate func spend(by owner: WorldwideScreenService,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws {
        guard !spent else { throw BelugaNetworkAdaptationOwnerError.refused }
        spent = true // Future wrong-origin completion admission also burns.
        guard attempt.owner === owner, attempt.seed.boundary === boundary,
              case .settled = attempt.phase else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
    }
}

extension WorldwideScreenService {
    /// Only the codec's sealed seed reaches this synchronous factory. The codec
    /// already compared all current Owner atoms/native sidecars to the actual701
    /// published replacement; this is native custody, not repeat501 admission.
    func networkAdaptationNativeAttempt(_ seed: BelugaNetworkAdaptationNativeAttemptSeed)
        throws -> BelugaNetworkAdaptationNativeAttempt {
        guard seed.entry.preparation.owner === self,
              seed.entry.preparation.boundary === seed.boundary,
              screenVideoAdaptationOwnerBoundary === seed.boundary else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        let resources: BelugaNetworkAdaptationNativeAttempt.ApplyResources?
        switch seed.intent {
        case .finalAdoptionOnly:
            // The real no-native-apply path does not require the six resources.
            // Do not unwrap them or mint sender/FPS permission on this path.
            resources = nil
        case .senderApply:
            guard let source = seed.entry.source, let sink = seed.entry.sink,
                  let captureAuthorization = seed.entry.captureAuthorization,
                  let forwardingAuthorization = seed.entry.forwardingAuthorization,
                  let baseDimensions = seed.entry.baseDimensions,
                  let capturer = seed.entry.capturer else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            resources = .init(source: source, sink: sink,
                captureAuthorization: captureAuthorization,
                forwardingAuthorization: forwardingAuthorization,
                baseDimensions: baseDimensions, capturer: capturer)
        }
        return .init(owner: self, seed: seed, resources: resources)
    }

    /// UNWIRED: this method performs the actual sender await but deliberately
    /// has no caller until success702/failure703/fresh704 adapters are complete.
    /// Both production selection gates stay false. No Boundary guard/frame is
    /// retained across await. No fallback, FPS call, rollback, or Owner store.
    func networkAdaptationRunNativeAttempt(_ attempt: BelugaNetworkAdaptationNativeAttempt)
        async throws -> BelugaNetworkAdaptationNativeCompletion {
        try attempt.claim(by: self, boundary: screenVideoAdaptationOwnerBoundary)
        guard automaticScreenMediaResumeContext == nil,
              peer === attempt.sourcePeer,
              peerGeneration == attempt.seed.entry.preparation.generation,
              screenVideoAdaptationOwner.revision == attempt.seed.prepared.tail.applyingRevision else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        // An exported attempt must not be delayed across a newer Owner/resource
        // cut and then mutate the sender. This is exact701 custody recapture,
        // not a recomputed policy vote. Rejection remains rejection, not 703.
        let current = try networkAdaptationBeginActiveRecapture(attempt.seed.entry,
            boundary: attempt.seed.boundary, retainingAnchor: attempt.seed.published.anchor)
        let published = attempt.seed.published
        guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(current.atoms, published.atoms),
              current.times == published.times, current.anchor == published.anchor,
              current.route == published.route else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        let settlement: BelugaNetworkAdaptationNativeCompletion.Settlement
        switch attempt.seed.intent {
        case .finalAdoptionOnly:
            precondition(attempt.resources == nil)
            settlement = .finalAdoptionOnly
        case .senderApply:
            precondition(attempt.resources != nil)
            // Only this actual return can create senderSucceeded. Capture the
            // exact original-peer token even when actor state changed at await.
            // DO NOT put custody refusal/currentness work inside this SDK catch.
            do {
                let update = try await attempt.sourcePeer.applyScreenVideoEncodingLimits(
                    attempt.seed.prepared.tail.recommendation.webRTCLimits)
                settlement = .senderSucceeded(update)
            } catch {
                settlement = .senderFailed(error)
            }
        }
        attempt.phase = .settled
        let completion = BelugaNetworkAdaptationNativeCompletion(attempt: attempt, settlement: settlement)
        #if DEBUG
        if let use = nativeDispatchReturnFixtureUse {
            // AFTER the real SDK-only catch and completion construction. No
            // C frame/Boundary guard or manufactured settlement crosses await.
            precondition(use.attempt === attempt && use.boundary === screenVideoAdaptationOwnerBoundary
                && activeNativeAdaptationDispatch === attempt && use.completion == nil)
            use.completion = completion
            await use.gate.holdActualReturn()
        }
        #endif
        return completion
    }
}
// Test-only genuine native resources; require the owned fresh-process controller.
// No live refs or receipts leave this actor. Capture and transport never start.
#if DEBUG
extension WorldwideScreenService {
    struct NativeAdaptationFixturePeerReadback: Equatable, Sendable {
        let topology: WebRTCTransportMediaTopology
        let externalAudioIsAbsent: Bool
        let encodingGeneration: UInt64
        let limits: WebRTCScreenVideoEncodingLimits?
        let totalCeiling: Int?
        let encodingActivity: [Bool]?
    }

    enum NativeAdaptationResourceFixtureCase: String, CaseIterable, Sendable {
        case apply, noNativeApply, wrongBoundaryConsume
        case sourceAbsentAfterPrepare, sinkAbsentAfterPrepare
        case captureAuthorizationAbsentAfterPrepare
        case forwardingAuthorizationAbsentAfterPrepare
        case dimensionsAbsentAfterPrepare
        case peerAbsentBeforeRun, generationAdvancedBeforeRun
        case revisionAdvancedBeforeRun, dimensionsChangedBeforeRun
        case resumeOccupancyBeforeRun
    }

    struct NativeAdaptationResourceFixtureObservation: Sendable {
        let selectedCase: NativeAdaptationResourceFixtureCase
        let prepared: Bool
        let beginReturned: Bool
        let resourceCustodyIsExact: Bool
        let intentIsSenderApply: Bool
        let beginInvocation: UInt64?
        let consumerInvocation: UInt64?
        let preparedReplayRefused: Bool
        let beginReplayRefused: Bool
        let wrongBoundaryRefused: Bool
        let wrongBoundaryBurnedOriginalUse: Bool
        let runRefused: Bool
        let runReplayRefused: Bool
        let completionIsSenderSucceeded: Bool
        let completionIsFinalAdoptionOnly: Bool
        let actualSDKTokenWasRetained: Bool
        let actualSDKTokenRollbackSucceeded: Bool
        let requestedLimits: WebRTCScreenVideoEncodingLimits?
        let nativeBefore: NativeAdaptationFixturePeerReadback
        let nativeAfter: NativeAdaptationFixturePeerReadback
        let nativeAfterTokenRollback: NativeAdaptationFixturePeerReadback?
        let ownerAfterBegin: NativeOwnerPublicationSnapshotObservation
        let ownerAfterConsume: NativeOwnerPublicationSnapshotObservation
        let ownerBeforeRun: NativeOwnerPublicationSnapshotObservation
        let ownerAfterRun: NativeOwnerPublicationSnapshotObservation
        let cleanupSourceStopped: Bool
        let cleanupPeerClosed: Bool
        let cleanupFieldsAreAbsent: Bool
        let cleanupAuthorizationsAreRevoked: Bool
    }

    private enum NativeAdaptationFixtureError: Error {
        case unsafeSetup, missingCapturer, sinkDidNotOpen, reportUnavailable
        case noPrepared, noBeginReceipt, wrongIntent, missingResources
        case badActualOrigin, unexpectedSDKFailure, unexpectedCompletion
    }

    // A closed constructor holds the original resources for cleanup even after
    // a negative case removes one from actual actor storage.
    private final class NativeAdaptationFixtureResources {
        let peer: WebRTCPeer
        let source: ScreenVideoCaptureSource
        let sink: WorldwideScreenSampleSink
        let captureAuthorization: WebRTCControlAuthorization
        let forwardingAuthorization: WebRTCControlAuthorization
        let dimensions: ScreenVideoPixelDimensions
        let capturer: MacExternalVideoCapturer
        var resumeOccupancyID: UUID?
        init(peer: WebRTCPeer, source: ScreenVideoCaptureSource,
            sink: WorldwideScreenSampleSink,
            captureAuthorization: WebRTCControlAuthorization,
            forwardingAuthorization: WebRTCControlAuthorization,
            dimensions: ScreenVideoPixelDimensions, capturer: MacExternalVideoCapturer) {
            self.peer = peer; self.source = source; self.sink = sink
            self.captureAuthorization = captureAuthorization
            self.forwardingAuthorization = forwardingAuthorization
            self.dimensions = dimensions; self.capturer = capturer
        }
    }

    private func makeNativeAdaptationFixtureResources() async throws
        -> NativeAdaptationFixtureResources {
        requireInertBatchAPolicyFixture()
        guard !isStarted, !isStopped, !captureLifetimeIsRequired,
              !Self.allNetworkAdaptationOwnerWritersAreEnrolled,
              !Self.ownedStopPublicationIsEnrolled,
              !nativeOwnerStopPublicationEnabled,
              !nativeOwnerEpochPublicationEnabled, !nativeOwnerResetPublicationEnabled,
              pendingNativeOwnerStopEntry == nil, pendingNativeOwnerEpochEntry == nil,
              pendingNativeOwnerResetEntry == nil,
              batchAInertRoutingObserverJoin?.snapshot().retainedHandleCount == 0,
              peer == nil, peerGeneration == 0,
              captureSource == nil, captureSink == nil,
              captureAuthorization == nil, captureForwardingAuthorization == nil,
              captureVideoBaseDimensions == nil, automaticScreenMediaResumeContext == nil,
              audioSource == nil, audioSink == nil, audioAuthorization == nil else {
            throw NativeAdaptationFixtureError.unsafeSetup
        }
        let nativePeer = try WebRTCPeer(configuration: .init(role: .host,
            iceServers: [], icePolicy: .directPreferred,
            maximumVideoBitrate: maximumVideoBitrate,
            mediaTopology: .videoControlOnly,
            supportsRemoteMediaControls: false, supportsMediaHandoff: false,
            supportsAudioClientDiagnostics: false))
        do {
            guard let capturer = nativePeer.externalVideoCapturer,
                  nativePeer.externalAudioCapturer == nil else {
                throw NativeAdaptationFixtureError.missingCapturer
            }
            let sink = WorldwideScreenSampleSink(capturer: capturer,
                remoteInputController: remoteInputController,
                didRequireCaptureFormatRenegotiation: { _ in
                    preconditionFailure("Unstarted fixture scheduled format renegotiation")
                }, scheduleFormatRenegotiationFallback: { _, _ in
                    preconditionFailure("Unstarted fixture scheduled a fallback")
                }, didStop: { _, _ in
                    preconditionFailure("Unstarted fixture delivered a native stop")
                })
            guard let forwarding = sink.beginForwarding(expectedFrameDimensions: nil),
                  sink.commitForwardingStartup(authorizedBy: forwarding),
                  sink.allowsActiveUse(authorizedBy: forwarding) else {
                sink.stopForwarding()
                throw NativeAdaptationFixtureError.sinkDidNotOpen
            }
            // No source.start, sample delivery, pixel injection, peer.start or SDP.
            let source = ScreenVideoCaptureSource(displayID: nil,
                maximumWidth: maximumWidth, framesPerSecond: framesPerSecond,
                consumer: sink, logger: logger)
            let capture = WebRTCControlAuthorization()
            let dimensions = ScreenVideoPixelDimensions(width: 320, height: 180)
            let resources = NativeAdaptationFixtureResources(peer: nativePeer,
                source: source, sink: sink, captureAuthorization: capture,
                forwardingAuthorization: forwarding, dimensions: dimensions,
                capturer: capturer)
            peer = nativePeer; peerGeneration = 1
            captureSource = source; captureSink = sink
            captureAuthorization = capture; captureForwardingAuthorization = forwarding
            captureVideoBaseDimensions = dimensions
            return resources
        } catch {
            _ = await nativePeer.close(reason: .normal)
            throw error
        }
    }

    private func closeNativeAdaptationFixture(_ f: NativeAdaptationFixtureResources) async
        -> (sourceStopped: Bool, peerClosed: Bool, absent: Bool, revoked: Bool) {
        f.captureAuthorization.revoke(); f.forwardingAuthorization.revoke()
        f.sink.stopForwarding()
        if captureSource === f.source { captureSource = nil }
        if captureSink === f.sink { captureSink = nil }
        if captureAuthorization === f.captureAuthorization { captureAuthorization = nil }
        if captureForwardingAuthorization === f.forwardingAuthorization {
            captureForwardingAuthorization = nil
        }
        // Only this fixture owns the existing peer slot; negative cases may
        // already have removed it. No replacement peer is constructed.
        if peer === f.peer { peer = nil }
        captureVideoBaseDimensions = nil
        if let id = f.resumeOccupancyID,
           automaticScreenMediaResumeContext?.attemptID == id {
            automaticScreenMediaResumeContext = nil
        }
        let stopped: Bool
        do { try await f.source.stop(); stopped = true }
        catch { stopped = false }
        let closed = await f.peer.close(reason: .normal)
        return (stopped, closed,
            peer == nil && captureSource == nil && captureSink == nil
                && captureAuthorization == nil && captureForwardingAuthorization == nil
                && captureVideoBaseDimensions == nil && automaticScreenMediaResumeContext == nil,
            !f.captureAuthorization.isValid && !f.forwardingAuthorization.isValid)
    }

    private func nativeAdaptationFixtureReport(_ f: NativeAdaptationFixtureResources)
        async throws -> WebRTCScreenVideoStatisticsReport {
        guard let report = await f.peer.screenVideoStatisticsSnapshot(timeout: .seconds(1)) else {
            throw NativeAdaptationFixtureError.reportUnavailable
        }
        return report
    }

    // The callback is fixed by the XCTest source and reads real peer fields
    // through @testable WebRTCTransport. It is never called under a Boundary
    // guard and cannot manufacture a receipt, resource or SDK update handle.
    func nativeAdaptationResourceFixtureObservationForTesting(
        selectedCase: NativeAdaptationResourceFixtureCase,
        readNative: @Sendable (WebRTCPeer) async -> NativeAdaptationFixturePeerReadback
    ) async throws -> NativeAdaptationResourceFixtureObservation {
        let f = try await makeNativeAdaptationFixtureResources()
        do {
            if selectedCase == .noNativeApply {
                // Genuine original-path setup only. No seeded/applied Owner or
                // copied proposal substitutes for this native sender operation.
                let report = try await nativeAdaptationFixtureReport(f)
                await adaptScreenVideoForNetworkConditions(report.nativeSnapshot,
                    sourcePeer: f.peer, sourcePeerGeneration: peerGeneration,
                    expectedPolicyRevision: screenVideoAdaptationOwner.revision,
                    allowsAutomaticResume: false,
                    nativeReportTimestampMicroseconds: report.nativeReportTimestampMicroseconds)
                guard appliedScreenVideoRecommendation != nil else {
                    throw NativeAdaptationFixtureError.wrongIntent
                }
            }
            let nativeBefore = await readNative(f.peer)
            let report = try await nativeAdaptationFixtureReport(f)
            guard let prepared = try screenVideoAdaptationOwnerBoundary.prepareGeneral(on: self,
                snapshot: report.nativeSnapshot,
                nativeTimestamp: report.nativeReportTimestampMicroseconds,
                sourcePeer: f.peer, generation: peerGeneration,
                expectedRevision: screenVideoAdaptationOwner.revision,
                capacityOnly: false, allowsResume: false) else {
                throw NativeAdaptationFixtureError.noPrepared
            }
            switch selectedCase {
            case .sourceAbsentAfterPrepare: captureSource = nil
            case .sinkAbsentAfterPrepare: captureSink = nil
            case .captureAuthorizationAbsentAfterPrepare: captureAuthorization = nil
            case .forwardingAuthorizationAbsentAfterPrepare: captureForwardingAuthorization = nil
            case .dimensionsAbsentAfterPrepare: captureVideoBaseDimensions = nil
            default: break
            }
            let begin = try screenVideoAdaptationOwnerBoundary.beginActive(prepared, on: self)
            let ownerAfterBegin = try nativeOwnerStopSnapshotObservation()
            var preparedReplayRefused = false
            do { _ = try screenVideoAdaptationOwnerBoundary.beginActive(prepared, on: self) }
            catch BelugaNetworkAdaptationOwnerError.refused { preparedReplayRefused = true }
            var exact = false, senderIntent = false, wrongBoundaryRefused = false
            var originalBurned = false, beginReplayRefused = false, runRefused = false
            var runReplayRefused = false, senderSucceeded = false, finalAdoptionOnly = false
            var tokenRetained = false
            var SDKUpdate: WebRTCScreenVideoEncodingUpdate?
            var beginInvocation: UInt64?, consumerInvocation: UInt64?
            var requested: WebRTCScreenVideoEncodingLimits?
            var ownerAfterConsume = ownerAfterBegin
            var ownerBeforeRun = ownerAfterBegin
            if let begin {
                if selectedCase == .wrongBoundaryConsume {
                    let foreignBoundary = BelugaNetworkAdaptationOwnerBoundary()
                    do { _ = try foreignBoundary.consumeBeginActive(begin, on: self) }
                    catch BelugaNetworkAdaptationOwnerError.refused { wrongBoundaryRefused = true }
                    do { _ = try screenVideoAdaptationOwnerBoundary.consumeBeginActive(begin, on: self) }
                    catch BelugaNetworkAdaptationOwnerError.refused { originalBurned = true }
                    ownerAfterConsume = try nativeOwnerStopSnapshotObservation()
                    ownerBeforeRun = ownerAfterConsume
                } else {
                    let attempt = try screenVideoAdaptationOwnerBoundary.consumeBeginActive(begin, on: self)
                    beginInvocation = attempt.beginActiveInvocation
                    consumerInvocation = attempt.consumerInvocation
                    senderIntent = attempt.intent == .senderApply
                    requested = attempt.seed.prepared.tail.recommendation.webRTCLimits
                    let issuerIsExact = attempt.owner === self
                        && attempt.seed.boundary === screenVideoAdaptationOwnerBoundary
                        && attempt.sourcePeer === f.peer
                    if senderIntent {
                        guard let resources = attempt.resources else {
                            throw NativeAdaptationFixtureError.missingResources
                        }
                        exact = issuerIsExact && resources.source === f.source && resources.sink === f.sink
                            && resources.captureAuthorization === f.captureAuthorization
                            && resources.forwardingAuthorization === f.forwardingAuthorization
                            && resources.baseDimensions == f.dimensions
                            && resources.capturer === f.capturer
                    } else { exact = issuerIsExact && attempt.resources == nil }
                    guard exact else { throw NativeAdaptationFixtureError.badActualOrigin }
                    ownerAfterConsume = try nativeOwnerStopSnapshotObservation()
                    do { _ = try screenVideoAdaptationOwnerBoundary.consumeBeginActive(begin, on: self) }
                    catch BelugaNetworkAdaptationOwnerError.refused { beginReplayRefused = true }
                    switch selectedCase {
                    case .peerAbsentBeforeRun: peer = nil
                    case .generationAdvancedBeforeRun: peerGeneration &+= 1
                    case .revisionAdvancedBeforeRun:
                        // Exercise the EXISTING actor writer, not a new Owner setter.
                        _ = prepareScreenVideoAdaptationEvidence(from: .fastSender)
                        _ = prepareScreenVideoAdaptationEvidence(from: .ordinaryFallback)
                    case .dimensionsChangedBeforeRun:
                        captureVideoBaseDimensions = .init(width: f.dimensions.width + 1,
                            height: f.dimensions.height)
                    case .resumeOccupancyBeforeRun:
                        // A non-authorizing occupancy blocker only, matching the
                        // existing inert reset fixture. No real resume/ACK claim.
                        let id = UUID(); f.resumeOccupancyID = id
                        automaticScreenMediaResumeContext = .init(
                            binding: currentScreenMediaSuspensionBinding,
                            notice: .init(screenRequestID: 1, suspensionGeneration: 1),
                            attemptID: id,
                            finalAcknowledgementCommit: WorldwideScreenAutomaticResumeCommitLatch(),
                            inputOwnershipClaim: nil, probeAuthorization: nil,
                            forwardingAuthorization: nil, boundary: nil,
                            markerReady: nil, markerPresentation: nil)
                    default: break
                    }
                    ownerBeforeRun = try nativeOwnerStopSnapshotObservation()
                    do {
                        let completion = try await networkAdaptationRunNativeAttempt(attempt)
                        switch completion.settlement {
                        case let .senderSucceeded(update):
                            senderSucceeded = completion.kind == .senderSucceeded
                            tokenRetained = completion.attempt === attempt
                            SDKUpdate = update
                        case .finalAdoptionOnly:
                            finalAdoptionOnly = completion.kind == .finalAdoptionOnly
                        case .senderFailed:
                            throw NativeAdaptationFixtureError.unexpectedSDKFailure
                        }
                    } catch BelugaNetworkAdaptationOwnerError.refused { runRefused = true }
                    do { _ = try await networkAdaptationRunNativeAttempt(attempt) }
                    catch BelugaNetworkAdaptationOwnerError.refused { runReplayRefused = true }
                }
            }
            let ownerAfterRun = try nativeOwnerStopSnapshotObservation()
            let nativeAfter = await readNative(f.peer)
            let tokenRollbackSucceeded: Bool
            let nativeAfterTokenRollback: NativeAdaptationFixturePeerReadback?
            if let SDKUpdate {
                // Use the stored opaque SDK token against its original peer.
                // No synthetic handle is created, and this is not a702 adapter.
                tokenRollbackSucceeded = try await f.peer.rollbackScreenVideoEncodingUpdateIfCurrent(SDKUpdate)
                nativeAfterTokenRollback = await readNative(f.peer)
            } else {
                tokenRollbackSucceeded = false
                nativeAfterTokenRollback = nil
            }
            let cleanup = await closeNativeAdaptationFixture(f)
            return .init(selectedCase: selectedCase, prepared: true, beginReturned: begin == nil,
                resourceCustodyIsExact: exact, intentIsSenderApply: senderIntent,
                beginInvocation: beginInvocation, consumerInvocation: consumerInvocation,
                preparedReplayRefused: preparedReplayRefused, beginReplayRefused: beginReplayRefused,
                wrongBoundaryRefused: wrongBoundaryRefused, wrongBoundaryBurnedOriginalUse: originalBurned,
                runRefused: runRefused, runReplayRefused: runReplayRefused,
                completionIsSenderSucceeded: senderSucceeded, completionIsFinalAdoptionOnly: finalAdoptionOnly,
                actualSDKTokenWasRetained: tokenRetained,
                actualSDKTokenRollbackSucceeded: tokenRollbackSucceeded, requestedLimits: requested,
                nativeBefore: nativeBefore, nativeAfter: nativeAfter,
                nativeAfterTokenRollback: nativeAfterTokenRollback,
                ownerAfterBegin: ownerAfterBegin, ownerAfterConsume: ownerAfterConsume,
                ownerBeforeRun: ownerBeforeRun,
                ownerAfterRun: ownerAfterRun,
                cleanupSourceStopped: cleanup.sourceStopped, cleanupPeerClosed: cleanup.peerClosed,
                cleanupFieldsAreAbsent: cleanup.absent, cleanupAuthorizationsAreRevoked: cleanup.revoked)
        } catch {
            let cleanup = await closeNativeAdaptationFixture(f)
            guard cleanup.sourceStopped && cleanup.peerClosed && cleanup.absent && cleanup.revoked else {
                throw NativeAdaptationFixtureError.unsafeSetup
            }
            throw error
        }
    }
}
#endif


struct BelugaNetworkAdaptationNativeFailureObservation {
    let source: BelugaNetworkAdaptationOwnerSnapshot
    let generation: UInt64
    let facts: UInt32
    fileprivate init(source: BelugaNetworkAdaptationOwnerSnapshot, generation: UInt64, facts: UInt32) {
        self.source = source; self.generation = generation; self.facts = facts
    }
}
final class BelugaNetworkAdaptationNativeFailureEntry {
    enum Admission { case ready(BelugaNetworkAdaptationNativeFailureObservation), refused(any Error) }
    let admission: Admission
    let senderError: any Error // EXACT caught SDK error, not a new bridge substitute.
    var seed: BelugaNetworkAdaptationNativeAttemptSeed { completion.attempt.seed }
    fileprivate let completion: BelugaNetworkAdaptationNativeCompletion
    fileprivate init(completion: BelugaNetworkAdaptationNativeCompletion, senderError: any Error,
        admission: Admission) {
        self.completion = completion; self.senderError = senderError; self.admission = admission
    }
}
extension BelugaNetworkAdaptationNativeCompletion {
    fileprivate func claimForFailure(by owner: WorldwideScreenService,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws -> (error: any Error, exactOrigin: Bool) {
        guard !spent else { throw BelugaNetworkAdaptationOwnerError.refused }
        spent = true // Wrong kind/actor/boundary also burns the completion.
        guard case .settled = attempt.phase, let _ = attempt.resources,
              case let .senderFailed(error) = settlement else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        return (error, attempt.owner === owner && attempt.seed.boundary === boundary)
    }
}
extension WorldwideScreenService {
    func networkAdaptationFailureCompletionEntry(_ completion: BelugaNetworkAdaptationNativeCompletion,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws -> BelugaNetworkAdaptationNativeFailureEntry {
        let claimed = try completion.claimForFailure(by: self, boundary: boundary)
        let admission: BelugaNetworkAdaptationNativeFailureEntry.Admission
        if claimed.exactOrigin && boundary === screenVideoAdaptationOwnerBoundary {
            do { admission = .ready(try networkAdaptationReadFailure(completion)) }
            catch { admission = .refused(error) }
        } else { admission = .refused(BelugaNetworkAdaptationOwnerError.refused) }
        return .init(completion: completion, senderError: claimed.error, admission: admission)
    }
    private func networkAdaptationReadFailure(_ completion: BelugaNetworkAdaptationNativeCompletion)
        throws -> BelugaNetworkAdaptationNativeFailureObservation {
        let attempt = completion.attempt
        guard attempt.owner === self, attempt.seed.boundary === screenVideoAdaptationOwnerBoundary,
              let r = attempt.resources, case .senderFailed = completion.settlement else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        let source = try BelugaNetworkAdaptationOwnerSnapshot.capture(screenVideoAdaptationOwner,
            retainingAnchor: attempt.seed.published.anchor)
        // Literal original catch short-circuit order. No stopped/resume/cancellation vote.
        var facts: UInt32 = 0
        if peer === attempt.sourcePeer {
            facts |= 1
            if peerGeneration == attempt.seed.prepared.tail.generation,
               screenVideoAdaptationOwner.revision == attempt.seed.prepared.tail.applyingRevision {
                if captureSource === r.source { facts |= 2
                    if captureSink === r.sink { facts |= 4
                        if captureAuthorization === r.captureAuthorization { facts |= 8
                            if captureForwardingAuthorization === r.forwardingAuthorization { facts |= 16
                                if r.captureAuthorization.isValid { facts |= 32
                                    if r.forwardingAuthorization.isValid { facts |= 64
                                        if r.sink.allowsActiveUse(authorizedBy: r.forwardingAuthorization) { facts |= 128
                                            if captureVideoBaseDimensions == r.baseDimensions { facts |= 256 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return .init(source: source, generation: peerGeneration, facts: facts)
    }
    func networkAdaptationFailureRecapture(_ entry: BelugaNetworkAdaptationNativeFailureEntry)
        throws -> BelugaNetworkAdaptationNativeFailureObservation {
        try networkAdaptationReadFailure(entry.completion)
    }
    // Fixed store only. The valid semantic-denial prefix is committed BEFORE
    // its diagnostic result is returned. No sender/FPS/rollback/fallback here.
    func networkAdaptationFailureCommit(_ packet: BelugaNetworkAdaptationFailureCommit) {
        screenVideoAdaptationOwner = packet.replacement.value
    }
}
// Actual702 prerequisites only: production selection stays closed. Constructors
// are actor-file sealed; no caller-supplied settlement, token or resource flags.
final class BelugaNetworkAdaptationSuccessCleanupReceipt {
    fileprivate enum State { case available, spent, retired }
    fileprivate let completion: BelugaNetworkAdaptationNativeCompletion
    fileprivate var state: State = .available
    fileprivate init(_ completion: BelugaNetworkAdaptationNativeCompletion) { self.completion = completion }
    fileprivate func claim(by owner: WorldwideScreenService,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws -> WebRTCScreenVideoEncodingUpdate {
        guard case .available = state else { throw BelugaNetworkAdaptationOwnerError.refused }
        state = .spent
        guard completion.attempt.owner === owner,
              completion.attempt.seed.boundary === boundary,
              case let .senderSucceeded(update) = completion.settlement else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        return update
    }
}

// The future704 adapter uses this same entry shape for actual702 acceptance or
// a separately consumed noNativeApply completion. It never grants FPS authority.
final class BelugaNetworkAdaptationNativeFinalAdoptionEntry {
    fileprivate enum State { case pendingSuccess, availableSuccess, availableNoApply, spent, retired }
    private enum Origin { case success, noApply }
    let seed: BelugaNetworkAdaptationNativeAttemptSeed
    fileprivate let completion: BelugaNetworkAdaptationNativeCompletion
    private let origin: Origin
    private var actualSuccessWasPublished = false
    private var useWasSpent = false
    private var finalStoreRetired = false
    // There is no state setter. Neither fixed publication mark clears either
    // monotonic latch, so a late702 store can NEVER reopen a refused native use.
    fileprivate var state: State {
        if finalStoreRetired { return .retired }
        if useWasSpent { return .spent }
        switch origin {
        case .noApply: return .availableNoApply
        case .success: return actualSuccessWasPublished ? .availableSuccess : .pendingSuccess
        }
    }
    fileprivate init(_ completion: BelugaNetworkAdaptationNativeCompletion) {
        self.completion = completion; seed = completion.attempt.seed; origin = .success
    }
    fileprivate init(noApplyCompletion completion: BelugaNetworkAdaptationNativeCompletion) {
        self.completion = completion; seed = completion.attempt.seed; origin = .noApply
    }

    fileprivate func claim(by owner: isolated WorldwideScreenService,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws {
        let previous = state
        // Consume only this non-Sendable capability record before all refusal.
        // No native SDK, resource, or actor Owner is read or written here.
        useWasSpent = true
        let wasSuccess: Bool
        switch previous {
        case .availableSuccess: wasSuccess = true
        case .availableNoApply: wasSuccess = false
        default: throw BelugaNetworkAdaptationOwnerError.refused
        }
        guard completion.attempt.owner === owner, seed.boundary === boundary,
              case .settled = completion.attempt.phase else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        if wasSuccess {
            guard case .senderSucceeded = completion.settlement,
                  case .senderApply = seed.intent, completion.attempt.resources != nil else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
        } else {
            guard case .finalAdoptionOnly = completion.settlement,
                  case .finalAdoptionOnly = seed.intent, completion.attempt.resources == nil else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
        }
    }

    // Disposal only, including wrong issuer/owner. This non-Sendable record's
    // latch is not native resource/actor state; no retry or effect grant exists.
    fileprivate func retireUse() { useWasSpent = true }
    // Fixed actual702 publication only; BEFORE its existing Owner assignment.
    // No branch/check/throw after native FPS and no latch/state reopening.
    fileprivate func markActualSuccessPublished() { actualSuccessWasPublished = true }
    // Fixed actual704 store only. Does not clear the spent latch.
    fileprivate func markFinalStoreRetired() { finalStoreRetired = true }
}


struct BelugaNetworkAdaptationNativeFinalAdoptionObservation {
    let source: BelugaNetworkAdaptationOwnerSnapshot
    let exactPeer: Bool
    // Nil means the preceding exact-peer guard failed and generation was NOT
    // read. The ABI's ignored generation carrier is0 when facts0; not an invented
    // successful generation or a cached702 sample.
    let generation: UInt64?
    fileprivate init(source: BelugaNetworkAdaptationOwnerSnapshot,
        exactPeer: Bool, generation: UInt64?) {
        self.source = source; self.exactPeer = exactPeer; self.generation = generation
    }
}

extension WorldwideScreenService {
    func networkAdaptationFinalOnlyCompletionEntry(_ completion: BelugaNetworkAdaptationNativeCompletion,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws -> BelugaNetworkAdaptationNativeFinalAdoptionEntry {
        // Existing real completion spend burns wrong-kind/origin before refusal.
        // A succeeded completion already spent by702 cannot issue a second path.
        try completion.spend(by: self, boundary: boundary)
        guard boundary === screenVideoAdaptationOwnerBoundary,
              case .finalAdoptionOnly = completion.settlement,
              case .finalAdoptionOnly = completion.attempt.seed.intent,
              completion.attempt.resources == nil else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        return .init(noApplyCompletion: completion)
    }

    func networkAdaptationFinalAdoptionEntry(_ entry: BelugaNetworkAdaptationNativeFinalAdoptionEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws -> BelugaNetworkAdaptationNativeFinalAdoptionObservation {
        try entry.claim(by: self, boundary: boundary)
        guard boundary === screenVideoAdaptationOwnerBoundary else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        return try networkAdaptationReadFinalAdoption(entry, boundary: boundary)
    }

    private func networkAdaptationReadFinalAdoption(_ entry: BelugaNetworkAdaptationNativeFinalAdoptionEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws -> BelugaNetworkAdaptationNativeFinalAdoptionObservation {
        guard case .spent = entry.state,
              entry.completion.attempt.owner === self,
              entry.seed.boundary === boundary,
              boundary === screenVideoAdaptationOwnerBoundary else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        // ORIGINAL final fence order: exact peer, then generation, then current
        // applying revision. Do not add capture/auth/sink/dimensions/stopped/
        // cancellation/resume checks or reuse702's resource facts. Owner capture
        // is still needed for the exact stale-return image, not a new policy vote.
        let exactPeer = peer === entry.completion.attempt.sourcePeer
        let generation: UInt64?
        if exactPeer { generation = peerGeneration } else { generation = nil }
        let source = try BelugaNetworkAdaptationOwnerSnapshot.capture(screenVideoAdaptationOwner,
            retainingAnchor: entry.seed.published.anchor)
        return .init(source: source, exactPeer: exactPeer, generation: generation)
    }

    func networkAdaptationFinalAdoptionRecapture(_ entry: BelugaNetworkAdaptationNativeFinalAdoptionEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws -> BelugaNetworkAdaptationNativeFinalAdoptionObservation {
        try networkAdaptationReadFinalAdoption(entry, boundary: boundary)
    }

    // Fixed synchronous receiver; every fallible operation/currentness check
    // and all result construction completed before this call. No sender/FPS,
    // rollback, clock, callback, dependency producer, await or fallible work.
    func networkAdaptationFinalAdoptionCommit(_ packet: BelugaNetworkAdaptationFinalAdoptionCommit) {
        packet.entry.markFinalStoreRetired()
        screenVideoAdaptationOwner = packet.replacement.value
    }
}


extension WorldwideScreenService {
    // Narrow synchronous disposal receiver. Unconditionally consumes only the
    // non-Sendable entry latch; no native/Owner read, effect, hop or new grant.
    func networkAdaptationRetireFinalAdoption(_ entry: BelugaNetworkAdaptationNativeFinalAdoptionEntry) {
        entry.retireUse()
    }
}

struct BelugaNetworkAdaptationNativeSuccessObservation {
    let source: BelugaNetworkAdaptationOwnerSnapshot
    let generation: UInt64
    let facts: UInt32
    fileprivate init(source: BelugaNetworkAdaptationOwnerSnapshot, generation: UInt64, facts: UInt32) {
        self.source = source; self.generation = generation; self.facts = facts
    }
}

final class BelugaNetworkAdaptationNativeSuccessEntry {
    enum Admission { case ready(BelugaNetworkAdaptationNativeSuccessObservation), refused(any Error) }
    let admission: Admission
    let cleanup: BelugaNetworkAdaptationSuccessCleanupReceipt
    let finalEntry: BelugaNetworkAdaptationNativeFinalAdoptionEntry
    var seed: BelugaNetworkAdaptationNativeAttemptSeed { completion.attempt.seed }
    fileprivate let completion: BelugaNetworkAdaptationNativeCompletion
    #if DEBUG
    let postEffectFixtureRefusal: BelugaNetworkAdaptationPostEffectFixtureRefusal?
    fileprivate init(completion: BelugaNetworkAdaptationNativeCompletion, admission: Admission,
        cleanup: BelugaNetworkAdaptationSuccessCleanupReceipt,
        finalEntry: BelugaNetworkAdaptationNativeFinalAdoptionEntry,
        postEffectFixtureRefusal: BelugaNetworkAdaptationPostEffectFixtureRefusal?) {
        self.completion = completion; self.admission = admission
        self.cleanup = cleanup; self.finalEntry = finalEntry
        self.postEffectFixtureRefusal = postEffectFixtureRefusal
    }
    #else
    fileprivate init(completion: BelugaNetworkAdaptationNativeCompletion, admission: Admission,
        cleanup: BelugaNetworkAdaptationSuccessCleanupReceipt,
        finalEntry: BelugaNetworkAdaptationNativeFinalAdoptionEntry) {
        self.completion = completion; self.admission = admission
        self.cleanup = cleanup; self.finalEntry = finalEntry
    }
    #endif
}

// Issued before validator acceptance, after exact native currentness and all
// Int32 conversions. The effect thunk uses this command, never arbitrary FPS.
final class BelugaNetworkAdaptationNativeSuccessOutput {
    fileprivate let capturer: MacExternalVideoCapturer
    fileprivate let width: Int32, height: Int32, fps: Int32
    #if DEBUG
    fileprivate var dispatchTrace: NativeSuccessDispatchTrace?
    #endif
    fileprivate init(capturer: MacExternalVideoCapturer, width: Int32, height: Int32, fps: Int32) {
        self.capturer = capturer; self.width = width; self.height = height; self.fps = fps
    }
    func perform() {
        capturer.adaptOutput(width: width, height: height, framesPerSecond: fps)
        #if DEBUG
        // Preallocated scalar trace only, after the real void SDK dispatch.
        // It does not establish libwebrtc format acceptance or rendered frames.
        dispatchTrace?.record(width: width, height: height, fps: fps)
        #endif
    }
}

extension BelugaNetworkAdaptationNativeCompletion {
    fileprivate func claimForSuccess(by owner: WorldwideScreenService,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws -> Bool {
        guard !spent else { throw BelugaNetworkAdaptationOwnerError.refused }
        spent = true // Also burns wrong kind/issuer/boundary. No replay permit.
        guard case .settled = attempt.phase,
              case .senderSucceeded = settlement, attempt.resources != nil else {
            // No actual returned SDK token exists on either other completion.
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        return attempt.owner === owner && attempt.seed.boundary === boundary
    }
}

extension WorldwideScreenService {
    func networkAdaptationSuccessCompletionEntry(_ completion: BelugaNetworkAdaptationNativeCompletion,
        boundary: BelugaNetworkAdaptationOwnerBoundary) throws -> BelugaNetworkAdaptationNativeSuccessEntry {
        let originIsExact = try completion.claimForSuccess(by: self, boundary: boundary)
        // Construct native cleanup custody BEFORE origin/capture/guard refusal.
        // Wrong-origin cleanup remains bound to the ORIGINAL actual actor only.
        let cleanup = BelugaNetworkAdaptationSuccessCleanupReceipt(completion)
        let finalEntry = BelugaNetworkAdaptationNativeFinalAdoptionEntry(completion)
        let admission: BelugaNetworkAdaptationNativeSuccessEntry.Admission
        if originIsExact && screenVideoAdaptationOwnerBoundary === boundary {
            do { admission = .ready(try networkAdaptationReadSuccess(completion)) }
            catch { admission = .refused(error) }
        } else { admission = .refused(BelugaNetworkAdaptationOwnerError.refused) }
        #if DEBUG
        // All fault admission/custody/latch work precedes C and native FPS.
        let fixtureRefusal = try bindNativeDispatchPostEffectFixtureRefusal(
            completion, boundary: boundary, admission: admission, cleanup: cleanup)
        let entry = BelugaNetworkAdaptationNativeSuccessEntry(completion: completion,
            admission: admission, cleanup: cleanup, finalEntry: finalEntry,
            postEffectFixtureRefusal: fixtureRefusal)
        #else
        let entry = BelugaNetworkAdaptationNativeSuccessEntry(completion: completion,
            admission: admission, cleanup: cleanup, finalEntry: finalEntry)
        #endif
        #if DEBUG
        // Only a sealed actual entry can construct the preallocated trace.
        // Replay throws before entry construction, so cannot create/reset it.
        completion.successDispatchTrace = NativeSuccessDispatchTrace(entry)
        #endif
        return entry
    }

    private func networkAdaptationReadSuccess(_ completion: BelugaNetworkAdaptationNativeCompletion)
        throws -> BelugaNetworkAdaptationNativeSuccessObservation {
        let attempt = completion.attempt
        guard attempt.owner === self, attempt.seed.boundary === screenVideoAdaptationOwnerBoundary,
              let r = attempt.resources, case .senderSucceeded = completion.settlement else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        let source = try BelugaNetworkAdaptationOwnerSnapshot.capture(screenVideoAdaptationOwner,
            retainingAnchor: attempt.seed.published.anchor)
        // Exactly the original left-to-right guard: later getters are NOT read
        // after an earlier failure. Cleared fact bits mean permission unproven.
        var facts: UInt32 = 0
        if peer === attempt.sourcePeer {
            facts |= 1
            if peerGeneration == attempt.seed.prepared.tail.generation,
               screenVideoAdaptationOwner.revision == attempt.seed.prepared.tail.applyingRevision {
                if captureSource === r.source { facts |= 2
                    if captureSink === r.sink { facts |= 4
                        if captureAuthorization === r.captureAuthorization { facts |= 8
                            if captureForwardingAuthorization === r.forwardingAuthorization { facts |= 16
                                if r.captureAuthorization.isValid { facts |= 32
                                    if r.forwardingAuthorization.isValid { facts |= 64
                                        if r.sink.allowsActiveUse(authorizedBy: r.forwardingAuthorization) { facts |= 128
                                            if captureVideoBaseDimensions == r.baseDimensions { facts |= 256 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return .init(source: source, generation: peerGeneration, facts: facts)
    }

    func networkAdaptationSuccessRecapture(_ entry: BelugaNetworkAdaptationNativeSuccessEntry)
        throws -> BelugaNetworkAdaptationNativeSuccessObservation {
        try networkAdaptationReadSuccess(entry.completion)
    }

    func networkAdaptationPrepareSuccessOutput(_ packet: BelugaNetworkAdaptationSuccessCommit)
        throws -> BelugaNetworkAdaptationNativeSuccessOutput? {
        guard packet.entry.completion.attempt.owner === self,
              packet.boundary === screenVideoAdaptationOwnerBoundary,
              packet.entry.seed.boundary === packet.boundary else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        guard let fps = packet.outputFPS else { return nil }
        guard let r = packet.entry.completion.attempt.resources,
              packet.entry.completion.attempt.sourcePeer.externalVideoCapturer === r.capturer,
              let width = Int32(exactly: r.baseDimensions.width),
              let height = Int32(exactly: r.baseDimensions.height),
              let nativeFPS = Int32(exactly: fps) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let output = BelugaNetworkAdaptationNativeSuccessOutput(capturer: r.capturer,
            width: width, height: height, fps: nativeFPS)
        #if DEBUG
        output.dispatchTrace = packet.entry.completion.successDispatchTrace
        #endif
        return output
    }

    // Mandatory isolated fixed receiver. Every check/allocation/conversion is
    // complete before C validator acceptance. No callback/check/throw/await here.
    func networkAdaptationSuccessCommit(_ packet: BelugaNetworkAdaptationSuccessCommit) {
        packet.entry.cleanup.state = .retired
        packet.entry.finalEntry.markActualSuccessPublished()
        #if DEBUG
        packet.entry.completion.successDispatchTrace?.recordStore()
        #endif
        screenVideoAdaptationOwner = packet.replacement.value
    }

    // Call only AFTER finishSuccess returns and its synchronous guard retires.
    // This reverts exactly the retained token on the ORIGINAL peer once. If a
    // result requires guarded recovery, this does NOT claim FPS/full recovery.
    func networkAdaptationRollbackSuccessCleanup(_ receipt: BelugaNetworkAdaptationSuccessCleanupReceipt)
        async throws -> Bool {
        let update = try receipt.claim(by: self, boundary: screenVideoAdaptationOwnerBoundary)
        #if DEBUG
        if let use = nativeDispatchReturnFixtureUse {
            precondition(use.completion === receipt.completion && use.cleanup == nil)
            use.cleanup = receipt // The actual spent receipt; no copied token.
        }
        receipt.completion.successDispatchTrace?.recordRollbackDispatch()
        #endif
        return try await receipt.completion.attempt.sourcePeer.rollbackScreenVideoEncodingUpdateIfCurrent(update)
    }
}

#if DEBUG
fileprivate final class NativeSuccessDispatchTrace {
    private(set) var calls: UInt64 = 0
    private(set) var stores: UInt64 = 0, rollbackDispatches: UInt64 = 0
    private(set) var width: Int32?, height: Int32?, fps: Int32?
    fileprivate init(_ entry: BelugaNetworkAdaptationNativeSuccessEntry) {
        let completion = entry.completion
        precondition(completion.kind == .senderSucceeded)
        guard case .senderSucceeded = completion.settlement else {
            preconditionFailure("Trace requires actual returned SDK completion custody")
        }
        precondition(completion.attempt.resources != nil)
    }
    fileprivate func record(width: Int32, height: Int32, fps: Int32) {
        // Called by the same-executor checked output command only. Scalar
        // stores allocate nothing, throw nothing and invoke no callback.
        calls &+= 1; self.width = width; self.height = height; self.fps = fps
    }
    fileprivate var observation: WorldwideScreenService.Native702DispatchObservation {
        .init(calls: calls, stores: stores, rollbackDispatches: rollbackDispatches,
            width: width, height: height, fps: fps)
    }
    fileprivate func recordStore() { stores &+= 1 }
    fileprivate func recordRollbackDispatch() { rollbackDispatches &+= 1 }
}

extension WorldwideScreenService {
    enum Native702FixtureCase: String, CaseIterable, Sendable {
        case absentApplied, sameFPS, stalePeer, wrongBoundary, completionReplay
    }
    enum Native702FixtureResult: String, Equatable, Sendable { case accepted, rollback, refused }
    struct Native702DispatchObservation: Equatable, Sendable {
        let calls: UInt64
        let stores: UInt64, rollbackDispatches: UInt64
        let width: Int32?, height: Int32?, fps: Int32?
    }
    struct Native702FixtureObservation: Sendable {
        let selectedCase: Native702FixtureCase
        let primaryResult: Native702FixtureResult
        let secondaryResult: Native702FixtureResult?
        let expectedPrimaryAppliedTail: [NativeOwnerPublicationAtomObservation]
        let expectedSecondaryAppliedTail: [NativeOwnerPublicationAtomObservation]?
        let beforePrimary: NativeOwnerPublicationSnapshotObservation
        let afterPrimary: NativeOwnerPublicationSnapshotObservation
        let beforeSecondary: NativeOwnerPublicationSnapshotObservation?
        let afterSecondary: NativeOwnerPublicationSnapshotObservation?
        let afterReplay: NativeOwnerPublicationSnapshotObservation
        let ownerAfterCleanup: NativeOwnerPublicationSnapshotObservation?
        let ownerAfterCleanupReplay: NativeOwnerPublicationSnapshotObservation?
        let completionReplayRefused: Bool
        let originalUseBurnedAfterWrongBoundary: Bool
        let cleanupSucceeded: Bool?
        let cleanupReplayRefused: Bool?
        let primaryDispatch: Native702DispatchObservation
        let primaryDispatchAfterReplay: Native702DispatchObservation
        let primaryDispatchAfterCleanupReplay: Native702DispatchObservation
        let primaryTraceIdentityRetained: Bool
        let secondaryDispatch: Native702DispatchObservation?
        let finalReceiptCount: Int
        let finalReceiptsWereDistinct: Bool?
        let nativeBeforeSDK: NativeAdaptationFixturePeerReadback
        let nativeAfterSDK: NativeAdaptationFixturePeerReadback
        let nativeAfter702: NativeAdaptationFixturePeerReadback
        let nativeAfterReplay: NativeAdaptationFixturePeerReadback
        let nativeAfterCleanup: NativeAdaptationFixturePeerReadback?
        let nativeAfterCleanupReplay: NativeAdaptationFixturePeerReadback?
        let requestedLimits: WebRTCScreenVideoEncodingLimits
        let cleanupSourceStopped: Bool
        let cleanupPeerClosed: Bool
        let cleanupFieldsAreAbsent: Bool
        let cleanupAuthorizationsAreRevoked: Bool
    }
    private enum Native702FixtureError: Error {
        case noApplyAttempt, noSuccessfulCompletion, incompatibleSameFPSSetup
        case badActualOrigin
        case missingDispatchTrace, unexpectedResult, wrongRefusalReason, guardedRecoveryRequired
    }

    private func native702FixtureAttempt(_ f: NativeAdaptationFixtureResources)
        async throws -> BelugaNetworkAdaptationNativeAttempt {
        let report = try await nativeAdaptationFixtureReport(f)
        guard let prepared = try screenVideoAdaptationOwnerBoundary.prepareGeneral(on: self,
            snapshot: report.nativeSnapshot, nativeTimestamp: report.nativeReportTimestampMicroseconds,
            sourcePeer: f.peer, generation: peerGeneration,
            expectedRevision: screenVideoAdaptationOwner.revision,
            capacityOnly: false, allowsResume: false),
              let begin = try screenVideoAdaptationOwnerBoundary.beginActive(prepared, on: self) else {
            throw Native702FixtureError.noApplyAttempt
        }
        let attempt = try screenVideoAdaptationOwnerBoundary.consumeBeginActive(begin, on: self)
        guard attempt.intent == .senderApply else { throw Native702FixtureError.noApplyAttempt }
        guard let resources = attempt.resources,
              attempt.owner === self,
              attempt.seed.boundary === screenVideoAdaptationOwnerBoundary,
              attempt.sourcePeer === f.peer,
              resources.source === f.source, resources.sink === f.sink,
              resources.captureAuthorization === f.captureAuthorization,
              resources.forwardingAuthorization === f.forwardingAuthorization,
              resources.baseDimensions == f.dimensions, resources.capturer === f.capturer else {
            throw Native702FixtureError.badActualOrigin
        }
        return attempt
    }

    // Manual six-atom expected tail, independent of the production702 importer.
    private func native702ExpectedTail(_ r: WorldwideScreenVideoEncodingRecommendation)
        -> [NativeOwnerPublicationAtomObservation] {
        [.init(kind: 4, present: 1, high: 0, low: 1),
         .init(kind: 7, present: 1, high: 0, low: UInt64(r.tier.rawValue)),
         .init(kind: 2, present: 1, high: 0, low: UInt64(bitPattern: Int64(r.maximumBitrateBps))),
         .init(kind: 2, present: 1, high: 0, low: UInt64(bitPattern: Int64(r.maximumTotalRTPBitrateBps))),
         .init(kind: 2, present: 1, high: 0, low: UInt64(bitPattern: Int64(r.maximumFramesPerSecond))),
         .init(kind: 3, present: 1, high: 0, low: r.scaleResolutionDownBy.bitPattern)]
    }
    private func native702Trace(_ completion: BelugaNetworkAdaptationNativeCompletion)
        throws -> Native702DispatchObservation {
        guard let trace = completion.successDispatchTrace else {
            throw Native702FixtureError.missingDispatchTrace
        }
        return trace.observation
    }

    func native702FixtureObservationForTesting(selectedCase: Native702FixtureCase,
        readNative: @Sendable (WebRTCPeer) async -> NativeAdaptationFixturePeerReadback)
        async throws -> Native702FixtureObservation {
        // Existing constructor proves exact fresh inert actor, no real HAL,
        // no capture/transport start, videoControlOnly and both false gates.
        let f = try await makeNativeAdaptationFixtureResources()
        do {
            let nativeBefore = await readNative(f.peer)
            let firstAttempt = try await native702FixtureAttempt(f)
            let firstCompletion = try await networkAdaptationRunNativeAttempt(firstAttempt)
            guard firstCompletion.kind == .senderSucceeded,
                  firstCompletion.attempt === firstAttempt,
                  case .senderSucceeded = firstCompletion.settlement else {
                throw Native702FixtureError.noSuccessfulCompletion
            }
            var secondAttempt: BelugaNetworkAdaptationNativeAttempt?
            var secondCompletion: BelugaNetworkAdaptationNativeCompletion?
            if selectedCase == .sameFPS {
                // Build TWO genuine pending completions before the first702
                // records applied. No seeded Owner/applied state or fake token.
                let attempt = try await native702FixtureAttempt(f)
                guard attempt.seed.prepared.tail.applyingRevision == firstAttempt.seed.prepared.tail.applyingRevision,
                      screenVideoAdaptationOwner.revision == firstAttempt.seed.prepared.tail.applyingRevision,
                      attempt.seed.prepared.tail.recommendation.maximumFramesPerSecond
                        == firstAttempt.seed.prepared.tail.recommendation.maximumFramesPerSecond else {
                    throw Native702FixtureError.incompatibleSameFPSSetup
                }
                let completion = try await networkAdaptationRunNativeAttempt(attempt)
                guard completion.kind == .senderSucceeded,
                      completion.attempt === attempt,
                      case .senderSucceeded = completion.settlement else {
                    throw Native702FixtureError.noSuccessfulCompletion
                }
                secondAttempt = attempt; secondCompletion = completion
            }
            let nativeAfterSDK = await readNative(f.peer)
            if selectedCase == .stalePeer { peer = nil }
            let anchor = firstAttempt.seed.published.anchor
            let before = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
            let result: BelugaNetworkAdaptationSuccessResult
            if selectedCase == .wrongBoundary {
                result = try BelugaNetworkAdaptationOwnerBoundary().finishSuccess(firstCompletion, on: self)
            } else { result = try screenVideoAdaptationOwnerBoundary.finishSuccess(firstCompletion, on: self) }
            var firstFinal: BelugaNetworkAdaptationFinalAdoptionReceipt?
            var secondFinal: BelugaNetworkAdaptationFinalAdoptionReceipt?
            var cleanupReceipt: BelugaNetworkAdaptationSuccessCleanupReceipt?
            let primaryKind: Native702FixtureResult
            switch result {
            case let .accepted(final): primaryKind = .accepted; firstFinal = final
            case let .rollback(cleanup): primaryKind = .rollback; cleanupReceipt = cleanup
            case let .refused(cleanup, error):
                guard let error = error as? BelugaNetworkAdaptationOwnerError,
                      case .refused = error else { throw Native702FixtureError.wrongRefusalReason }
                primaryKind = .refused; cleanupReceipt = cleanup
            case .requiresGuardedRecovery: throw Native702FixtureError.guardedRecoveryRequired
            }
            let after = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
            guard let primaryTraceObject = firstCompletion.successDispatchTrace else {
                throw Native702FixtureError.missingDispatchTrace
            }
            let primaryTrace = try native702Trace(firstCompletion)
            var beforeSecond: NativeOwnerPublicationSnapshotObservation?
            var afterSecond: NativeOwnerPublicationSnapshotObservation?
            var secondaryKind: Native702FixtureResult?
            var secondaryTrace: Native702DispatchObservation?
            if let secondCompletion {
                beforeSecond = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
                guard case let .accepted(final) = try screenVideoAdaptationOwnerBoundary.finishSuccess(secondCompletion, on: self) else {
                    throw Native702FixtureError.unexpectedResult
                }
                secondFinal = final; secondaryKind = .accepted
                afterSecond = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
                secondaryTrace = try native702Trace(secondCompletion)
            }
            let nativeAfter702 = await readNative(f.peer)
            var replayRefused = false
            do { _ = try screenVideoAdaptationOwnerBoundary.finishSuccess(firstCompletion, on: self) }
            catch BelugaNetworkAdaptationOwnerError.refused { replayRefused = true }
            let afterReplay = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
            let primaryTraceAfterReplay = primaryTraceObject.observation
            let traceIdentityRetained = firstCompletion.successDispatchTrace === primaryTraceObject
            let nativeAfterReplay = await readNative(f.peer)
            var cleanupSucceeded: Bool?, cleanupReplayRefused: Bool?
            var nativeAfterCleanup: NativeAdaptationFixturePeerReadback?
            var nativeAfterCleanupReplay: NativeAdaptationFixturePeerReadback?
            var ownerAfterCleanup: NativeOwnerPublicationSnapshotObservation?
            var ownerAfterCleanupReplay: NativeOwnerPublicationSnapshotObservation?
            if let cleanupReceipt {
                // Guard has returned/retired. This receipt carries the ACTUAL
                // original token, and acts on f.peer even when actor.peer=nil.
                cleanupSucceeded = try await networkAdaptationRollbackSuccessCleanup(cleanupReceipt)
                nativeAfterCleanup = await readNative(f.peer)
                ownerAfterCleanup = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
                do { _ = try await networkAdaptationRollbackSuccessCleanup(cleanupReceipt); cleanupReplayRefused = false }
                catch BelugaNetworkAdaptationOwnerError.refused { cleanupReplayRefused = true }
                nativeAfterCleanupReplay = await readNative(f.peer)
                ownerAfterCleanupReplay = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
            }
            let finalCount = (firstFinal == nil ? 0 : 1) + (secondFinal == nil ? 0 : 1)
            let distinct: Bool?
            if let firstFinal, let secondFinal { distinct = firstFinal !== secondFinal }
            else { distinct = nil }
            let secondaryTail = secondAttempt.map { native702ExpectedTail($0.seed.prepared.tail.recommendation) }
            let cleanup = await closeNativeAdaptationFixture(f)
            return .init(selectedCase: selectedCase, primaryResult: primaryKind, secondaryResult: secondaryKind,
                expectedPrimaryAppliedTail: native702ExpectedTail(firstAttempt.seed.prepared.tail.recommendation),
                expectedSecondaryAppliedTail: secondaryTail,
                beforePrimary: before, afterPrimary: after, beforeSecondary: beforeSecond, afterSecondary: afterSecond,
                afterReplay: afterReplay,
                ownerAfterCleanup: ownerAfterCleanup, ownerAfterCleanupReplay: ownerAfterCleanupReplay,
                completionReplayRefused: replayRefused,
                originalUseBurnedAfterWrongBoundary: selectedCase == .wrongBoundary && replayRefused,
                cleanupSucceeded: cleanupSucceeded, cleanupReplayRefused: cleanupReplayRefused,
                primaryDispatch: primaryTrace,
                primaryDispatchAfterReplay: primaryTraceAfterReplay,
                primaryDispatchAfterCleanupReplay: primaryTraceObject.observation,
                primaryTraceIdentityRetained: traceIdentityRetained,
                secondaryDispatch: secondaryTrace,
                finalReceiptCount: finalCount, finalReceiptsWereDistinct: distinct,
                nativeBeforeSDK: nativeBefore, nativeAfterSDK: nativeAfterSDK, nativeAfter702: nativeAfter702,
                nativeAfterReplay: nativeAfterReplay, nativeAfterCleanup: nativeAfterCleanup,
                nativeAfterCleanupReplay: nativeAfterCleanupReplay,
                requestedLimits: firstAttempt.seed.prepared.tail.recommendation.webRTCLimits,
                cleanupSourceStopped: cleanup.sourceStopped, cleanupPeerClosed: cleanup.peerClosed,
                cleanupFieldsAreAbsent: cleanup.absent, cleanupAuthorizationsAreRevoked: cleanup.revoked)
        } catch {
            // Owned inert peer closure retires all actual sender configurations.
            // No guesses at FPS restoration and no effect on any external peer.
            let cleanup = await closeNativeAdaptationFixture(f)
            guard cleanup.sourceStopped && cleanup.peerClosed && cleanup.absent && cleanup.revoked else {
                throw NativeAdaptationFixtureError.unsafeSetup
            }
            throw error
        }
    }
}
#endif

#if DEBUG
extension WorldwideScreenService {
    enum ClosedPeer703FixtureCase: Sendable {
        case current, wrongBoundary, peerAbsent, generationAdvanced, revisionAdvanced
        case forwardingAuthorizationRevoked, dimensionsChanged
    }
    struct ClosedPeer703FixtureObservation: Sendable {
        let normalOwnedPeerCloseSucceeded: Bool
        let actualReturnedErrorIsTransportClosed: Bool
        let returnedFailureErrorKindIsTransportClosed: Bool
        let recoveryRetainsOriginalCompletion: Bool?
        let actualFactsBefore703: UInt32
        let resultWasRetained: Bool
        let resultWasGuardedRecovery: Bool
        let staleDisposition: Bool
        let semanticStatus: UInt32?
        let acceptedReads: UInt32?
        let attemptedReads: UInt32?
        let ownerBeforeRun: NativeOwnerPublicationSnapshotObservation
        let ownerAfterSDKFailure: NativeOwnerPublicationSnapshotObservation
        let ownerBefore703: NativeOwnerPublicationSnapshotObservation
        let ownerAfter703: NativeOwnerPublicationSnapshotObservation
        let ownerAfterReplay: NativeOwnerPublicationSnapshotObservation
        let completionReplayRefused: Bool
        let cleanupSourceStopped: Bool
        let cleanupPeerClosed: Bool
        let cleanupFieldsAreAbsent: Bool
        let cleanupAuthorizationsAreRevoked: Bool
    }
    func closedPeer703FixtureObservationForTesting(_ selected: ClosedPeer703FixtureCase)
        async throws -> ClosedPeer703FixtureObservation {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1" else {
            throw NativeAdaptationFixtureError.unsafeSetup
        }
        // Existing constructor itself enforces inert HAL/service, empty native
        // fields, no retained controls, unstarted capture and both false gates.
        let f = try await makeNativeAdaptationFixtureResources()
        do {
            let report = try await nativeAdaptationFixtureReport(f)
            guard let general = try screenVideoAdaptationOwnerBoundary.prepareGeneral(on: self,
                snapshot: report.nativeSnapshot, nativeTimestamp: report.nativeReportTimestampMicroseconds,
                sourcePeer: f.peer, generation: peerGeneration,
                expectedRevision: screenVideoAdaptationOwner.revision,
                capacityOnly: false, allowsResume: false),
                let begin = try screenVideoAdaptationOwnerBoundary.beginActive(general, on: self) else {
                throw NativeAdaptationFixtureError.noPrepared
            }
            let attempt = try screenVideoAdaptationOwnerBoundary.consumeBeginActive(begin, on: self)
            guard case .senderApply = attempt.intent else { throw NativeAdaptationFixtureError.wrongIntent }
            // Normal actual lifecycle on ONLY this owned disposable peer.
            // Do not nil the actor peer/resources or revoke fixture authorizations.
            // The unstarted fixture installed no live service event consumer.
            let closed = await f.peer.close(reason: .normal)
            guard closed, peer === f.peer,
                  captureSource === f.source, captureSink === f.sink,
                  captureAuthorization === f.captureAuthorization,
                  captureForwardingAuthorization === f.forwardingAuthorization,
                  f.captureAuthorization.isValid, f.forwardingAuthorization.isValid,
                  f.sink.allowsActiveUse(authorizedBy: f.forwardingAuthorization),
                  captureVideoBaseDimensions == f.dimensions,
                  f.peer.externalVideoCapturer === f.capturer else {
                throw NativeAdaptationFixtureError.unsafeSetup
            }
            let beforeRun = try nativeOwnerStopSnapshotObservation()
            // No hook/error injection between guards and SDK catch. Returning a
            // sealed completion proves the unchanged runner passed its pre-SDK
            // guards and actually reached the peer method's caught throw.
            let completion = try await networkAdaptationRunNativeAttempt(attempt)
            guard case let .senderFailed(error) = completion.settlement,
                  let transport = error as? WebRTCTransportError,
                  case .transportClosed = transport else {
                throw NativeAdaptationFixtureError.unexpectedSDKFailure
            }
            let afterSDK = try nativeOwnerStopSnapshotObservation()
            // Genuine stale native changes only AFTER the actual failed call.
            switch selected {
            case .current, .wrongBoundary: break
            case .peerAbsent: peer = nil
            case .generationAdvanced: peerGeneration &+= 1
            case .revisionAdvanced:
                let v = screenVideoAdaptationOwner
                screenVideoAdaptationOwner = .init(policy: v.policy, revision: v.revision &+ 1,
                    fastStatisticsAvailable: v.fastStatisticsAvailable, lane: v.lane,
                    evidenceTime: v.evidenceTime, minimumCollectionSequence: v.minimumCollectionSequence,
                    applied: v.applied)
            case .forwardingAuthorizationRevoked: f.forwardingAuthorization.revoke()
            case .dimensionsChanged:
                captureVideoBaseDimensions = .init(width: f.dimensions.width + 1, height: f.dimensions.height)
            }
            // Read-only actual facts, never passed into/publicly supplied to703.
            // This does not spend the completion or construct an entry/result.
            let observed = try networkAdaptationReadFailure(completion)
            let before703 = try nativeOwnerStopSnapshotObservation()
            let result: BelugaNetworkAdaptationFailureResult
            switch selected {
            case .wrongBoundary:
                let wrongBoundary = BelugaNetworkAdaptationOwnerBoundary()
                result = try wrongBoundary.finishFailure(completion, on: self)
            default:
                result = try screenVideoAdaptationOwnerBoundary.finishFailure(completion, on: self)
            }
            var retained = false, recovery = false, stale = false, errorKindRetained = false
            var recoveryRetainsCompletion: Bool?
            var status: UInt32?, accepted: UInt32?, attempted: UInt32?
            switch result {
            case let .retained(receipt):
                retained = true
                if case .stale = receipt.disposition { stale = true }
                status = receipt.semanticStatus; accepted = receipt.acceptedReads; attempted = receipt.attemptedReads
                if let returned = receipt.actualSenderError as? WebRTCTransportError,
                   case .transportClosed = returned { errorKindRetained = true }
            case let .requiresGuardedRecovery(entry, _):
                recovery = true
                // Actor-file entry retains the actual settled completion itself.
                recoveryRetainsCompletion = entry.completion === completion
                if let returned = entry.senderError as? WebRTCTransportError,
                   case .transportClosed = returned { errorKindRetained = true }
            }
            let after703 = try nativeOwnerStopSnapshotObservation()
            var replayRefused = false
            do { _ = try screenVideoAdaptationOwnerBoundary.finishFailure(completion, on: self) }
            catch BelugaNetworkAdaptationOwnerError.refused { replayRefused = true }
            let afterReplay = try nativeOwnerStopSnapshotObservation()
            let cleanup = await closeNativeAdaptationFixture(f)
            return .init(normalOwnedPeerCloseSucceeded: closed, actualReturnedErrorIsTransportClosed: true,
                returnedFailureErrorKindIsTransportClosed: errorKindRetained,
                recoveryRetainsOriginalCompletion: recoveryRetainsCompletion,
                actualFactsBefore703: observed.facts, resultWasRetained: retained,
                resultWasGuardedRecovery: recovery, staleDisposition: stale, semanticStatus: status,
                acceptedReads: accepted, attemptedReads: attempted,
                ownerBeforeRun: beforeRun, ownerAfterSDKFailure: afterSDK,
                ownerBefore703: before703, ownerAfter703: after703, ownerAfterReplay: afterReplay,
                completionReplayRefused: replayRefused,
                cleanupSourceStopped: cleanup.sourceStopped, cleanupPeerClosed: cleanup.peerClosed,
                cleanupFieldsAreAbsent: cleanup.absent, cleanupAuthorizationsAreRevoked: cleanup.revoked)
        } catch {
            _ = await closeNativeAdaptationFixture(f)
            throw error
        }
    }
}
#endif

// SOURCE-ONLY append in SAME WorldwideScreenService.swift DEBUG scope.
// Requires reviewed actual704 API/custody design and SDK_CALL_COUNTERS.md.
// Does not construct anything until the explicit owned controller flag is set.
#if DEBUG
extension WorldwideScreenService {
    enum Native704FixturePath: Equatable, Sendable { case success, noApply }
    enum Native704FixtureCut: Equatable, Sendable { case current, peerAbsent, generationAdvanced, revisionAdvanced, wrongBoundary }
    enum Native704FixtureResult: Equatable, Sendable { case adopted, superseded, refused }
    enum Native704FixtureRouteAction: Equatable, Sendable { case retain, clear, copyIncoming }
    struct Native704SDKReadback: Equatable, Sendable {
        let peer: NativeAdaptationFixturePeerReadback
        let senderApplyInvocations: UInt64
        let outputAdaptInvocations: UInt64?
    }
    struct Native704FixtureObservation: Sendable {
        let path: Native704FixturePath
        let cut: Native704FixtureCut
        let result: Native704FixtureResult
        let preparedPolicyAtoms: [NativeOwnerPublicationAtomObservation]
        let preparedNativeTimes: [ContinuousClock.Instant?]
        let preparedRouteAction: Native704FixtureRouteAction
        let preparedIncomingRoute: WebRTCICERouteDiagnostics?
        let preparedApplyingRevision: UInt64
        let ownerBeforeStaleCut: NativeOwnerPublicationSnapshotObservation
        let beforeFinal: NativeOwnerPublicationSnapshotObservation
        let afterFinal: NativeOwnerPublicationSnapshotObservation
        let afterReplay: NativeOwnerPublicationSnapshotObservation
        let nativeBeforeRun: Native704SDKReadback
        let nativeAfterRun: Native704SDKReadback
        let nativeBeforeFinal: Native704SDKReadback
        let nativeAfterFinal: Native704SDKReadback
        let nativeAfterReplay: Native704SDKReadback
        let successDispatchBeforeFinal: Native702DispatchObservation?
        let successDispatchAfterFinal: Native702DispatchObservation?
        let successDispatchAfterReplay: Native702DispatchObservation?
        let codecUseSpentBeforeFinal: Bool
        let nativeEntryAvailableBeforeFinal: Bool
        let codecUseSpentAfterFinal: Bool
        let nativeEntryUnavailableAfterFinal: Bool
        let codecUseSpentAfterReplay: Bool
        let nativeEntryUnavailableAfterReplay: Bool
        let replayRefused: Bool
        let noApplyCompletionReplayRefused: Bool?
        let cleanupSourceStopped: Bool
        let cleanupPeerClosed: Bool
        let cleanupFieldsAreAbsent: Bool
        let cleanupAuthorizationsAreRevoked: Bool
    }
    private enum Native704FixtureError: Error {
        case wrongIntent, noPrepared, notSuccessful, noFinalReceipt
        case unexpectedResult, wrongRefusal, badCustody, unsafeCleanup
    }

    private func native704NoApplyAttempt(_ f: NativeAdaptationFixtureResources)
        async throws -> BelugaNetworkAdaptationNativeAttempt {
        // EXACT existing native701 noApply setup path: one genuine original
        // policy/sender warmup, then one fresh real statistics preparation.
        // No loop, seeded Applied/Owner, forged telemetry or forcing fallback.
        let warm = try await nativeAdaptationFixtureReport(f)
        await adaptScreenVideoForNetworkConditions(warm.nativeSnapshot,
            sourcePeer: f.peer, sourcePeerGeneration: peerGeneration,
            expectedPolicyRevision: screenVideoAdaptationOwner.revision,
            allowsAutomaticResume: false,
            nativeReportTimestampMicroseconds: warm.nativeReportTimestampMicroseconds)
        guard appliedScreenVideoRecommendation != nil else { throw Native704FixtureError.wrongIntent }
        let report = try await nativeAdaptationFixtureReport(f)
        guard let p = try screenVideoAdaptationOwnerBoundary.prepareGeneral(on: self,
            snapshot: report.nativeSnapshot, nativeTimestamp: report.nativeReportTimestampMicroseconds,
            sourcePeer: f.peer, generation: peerGeneration,
            expectedRevision: screenVideoAdaptationOwner.revision,
            capacityOnly: false, allowsResume: false),
              let begin = try screenVideoAdaptationOwnerBoundary.beginActive(p, on: self) else {
            throw Native704FixtureError.noPrepared
        }
        let attempt = try screenVideoAdaptationOwnerBoundary.consumeBeginActive(begin, on: self)
        guard attempt.intent == .finalAdoptionOnly, attempt.resources == nil,
              attempt.owner === self, attempt.sourcePeer === f.peer,
              attempt.seed.boundary === screenVideoAdaptationOwnerBoundary else {
            throw Native704FixtureError.wrongIntent
        }
        return attempt
    }
    private func native704EntryUnavailable(_ entry: BelugaNetworkAdaptationNativeFinalAdoptionEntry) -> Bool {
        switch entry.state {
        case .spent, .retired: return true
        default: return false
        }
    }

    func native704FixtureObservationForTesting(path: Native704FixturePath, cut: Native704FixtureCut,
        readNative: @Sendable (WebRTCPeer) async -> Native704SDKReadback)
        async throws -> Native704FixtureObservation {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1" else {
            throw NativeAdaptationFixtureError.unsafeSetup
        }
        let f = try await makeNativeAdaptationFixtureResources()
        do {
            let attempt: BelugaNetworkAdaptationNativeAttempt
            switch path {
            case .success: attempt = try await native702FixtureAttempt(f)
            case .noApply: attempt = try await native704NoApplyAttempt(f)
            }
            let nativeBeforeRun = await readNative(f.peer)
            let completion = try await networkAdaptationRunNativeAttempt(attempt)
            guard completion.attempt === attempt else { throw Native704FixtureError.badCustody }
            let nativeAfterRun = await readNative(f.peer)
            let final: BelugaNetworkAdaptationFinalAdoptionReceipt
            var noApplyReplayRefused: Bool?
            switch path {
            case .success:
                guard completion.kind == .senderSucceeded,
                      case .senderSucceeded = completion.settlement,
                      case let .accepted(receipt) = try screenVideoAdaptationOwnerBoundary.finishSuccess(completion, on: self) else {
                    throw Native704FixtureError.notSuccessful
                }
                final = receipt
            case .noApply:
                guard completion.kind == .finalAdoptionOnly,
                      case .finalAdoptionOnly = completion.settlement else {
                    throw Native704FixtureError.wrongIntent
                }
                final = try screenVideoAdaptationOwnerBoundary.consumeFinalAdoptionOnly(completion, on: self)
                do {
                    _ = try screenVideoAdaptationOwnerBoundary.consumeFinalAdoptionOnly(completion, on: self)
                    noApplyReplayRefused = false
                } catch BelugaNetworkAdaptationOwnerError.refused { noApplyReplayRefused = true }
            }
            let actualEntry = try screenVideoAdaptationOwnerBoundary.finalAdoptionEntryForTesting(final)
            guard actualEntry.completion === completion,
                  actualEntry.seed.boundary === screenVideoAdaptationOwnerBoundary else {
                throw Native704FixtureError.badCustody
            }
            let prepared = attempt.seed.prepared, anchor = attempt.seed.published.anchor
            let beforeStale = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
            switch cut {
            case .current, .wrongBoundary: break
            case .peerAbsent: peer = nil
            case .generationAdvanced: peerGeneration &+= 1
            case .revisionAdvanced:
                let v = screenVideoAdaptationOwner
                screenVideoAdaptationOwner = .init(policy: v.policy, revision: v.revision &+ 1,
                    fastStatisticsAvailable: v.fastStatisticsAvailable, lane: v.lane,
                    evidenceTime: v.evidenceTime, minimumCollectionSequence: v.minimumCollectionSequence, applied: v.applied)
            }
            let beforeFinal = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
            let nativeBeforeFinal = await readNative(f.peer)
            let trace = completion.successDispatchTrace
            let dispatchBefore = trace?.observation
            let useBefore = try screenVideoAdaptationOwnerBoundary.finalAdoptionReceiptWasSpentForTesting(final)
            let entryBefore: Bool
            switch actualEntry.state {
            case .availableSuccess, .availableNoApply: entryBefore = true
            default: entryBefore = false
            }
            let result: BelugaNetworkAdaptationFinalAdoptionResult
            if cut == .wrongBoundary {
                result = try BelugaNetworkAdaptationOwnerBoundary().finalAdopt(final, on: self)
            } else { result = try screenVideoAdaptationOwnerBoundary.finalAdopt(final, on: self) }
            let primaryKind: Native704FixtureResult
            switch result {
            case .adopted: primaryKind = .adopted
            case .superseded: primaryKind = .superseded
            case let .refused(entry, error):
                guard entry === actualEntry,
                      let error = error as? BelugaNetworkAdaptationOwnerError,
                      case .refused = error else { throw Native704FixtureError.wrongRefusal }
                primaryKind = .refused
            }
            let afterFinal = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
            let useAfter = try screenVideoAdaptationOwnerBoundary.finalAdoptionReceiptWasSpentForTesting(final)
            let entryAfter = native704EntryUnavailable(actualEntry)
            let dispatchAfter = trace?.observation
            let nativeAfterFinal = await readNative(f.peer)
            var replayRefused = false
            do {
                let replay = try screenVideoAdaptationOwnerBoundary.finalAdopt(final, on: self)
                if case let .refused(entry, error) = replay,
                   entry === actualEntry,
                   let error = error as? BelugaNetworkAdaptationOwnerError,
                   case .refused = error { replayRefused = true }
            } catch BelugaNetworkAdaptationOwnerError.refused { replayRefused = true }
            let afterReplay = try nativeOwnerStopSnapshotObservation(retainingAnchor: anchor)
            let useAfterReplay = try screenVideoAdaptationOwnerBoundary.finalAdoptionReceiptWasSpentForTesting(final)
            let entryAfterReplay = native704EntryUnavailable(actualEntry)
            let nativeAfterReplay = await readNative(f.peer)
            let routeAction: Native704FixtureRouteAction
            switch prepared.tail.routeAction {
            case .retain: routeAction = .retain
            case .clear: routeAction = .clear
            case .copyIncoming: routeAction = .copyIncoming
            }
            let cleanup = await closeNativeAdaptationFixture(f)
            return .init(path: path, cut: cut, result: primaryKind,
                preparedPolicyAtoms: prepared.atoms.prefix(168).map { .init(kind: $0.kind, present: $0.present, high: $0.high, low: $0.low) },
                preparedNativeTimes: prepared.policyTimes, preparedRouteAction: routeAction,
                preparedIncomingRoute: prepared.report.incomingRoute, preparedApplyingRevision: prepared.tail.applyingRevision,
                ownerBeforeStaleCut: beforeStale, beforeFinal: beforeFinal, afterFinal: afterFinal, afterReplay: afterReplay,
                nativeBeforeRun: nativeBeforeRun, nativeAfterRun: nativeAfterRun,
                nativeBeforeFinal: nativeBeforeFinal, nativeAfterFinal: nativeAfterFinal, nativeAfterReplay: nativeAfterReplay,
                successDispatchBeforeFinal: dispatchBefore, successDispatchAfterFinal: dispatchAfter,
                successDispatchAfterReplay: trace?.observation,
                codecUseSpentBeforeFinal: useBefore, nativeEntryAvailableBeforeFinal: entryBefore,
                codecUseSpentAfterFinal: useAfter, nativeEntryUnavailableAfterFinal: entryAfter,
                codecUseSpentAfterReplay: useAfterReplay, nativeEntryUnavailableAfterReplay: entryAfterReplay,
                replayRefused: replayRefused, noApplyCompletionReplayRefused: noApplyReplayRefused,
                cleanupSourceStopped: cleanup.sourceStopped, cleanupPeerClosed: cleanup.peerClosed,
                cleanupFieldsAreAbsent: cleanup.absent, cleanupAuthorizationsAreRevoked: cleanup.revoked)
        } catch {
            let cleanup = await closeNativeAdaptationFixture(f)
            guard cleanup.sourceStopped && cleanup.peerClosed && cleanup.absent && cleanup.revoked else {
                throw Native704FixtureError.unsafeCleanup
            }
            throw error
        }
    }
}
#endif

// STOPPED SOURCE-ONLY PROPOSAL. No canonical adoption or compilation.
// Apply the companion ACTOR_INSERTIONS patch: two actual-record fields plus
// mandatory hasUnconfirmedNativeCaptureStop quarantine visibility. Append the
// remaining definitions in the SAME WSS source file, not a separate module.

extension WorldwideScreenService {
    private enum NativeDispatchUnverifiedReason {
        case adapterRefused, rollbackUncertain, recoveryCustodyMismatch
        case alreadyStoppedUnverified, nativeStopUnconfirmed
    }
    // Strong, constructor-sealed retention only. Not a retry/effect grant.
    // No setter/clear API. owner→record→completion→owner intentionally retains
    // unresolved custody until process exit; host terminal predicate sees it.
    // Positive paths do not create this record or its cycle. Generic stop does
    // NOT clear it; future live activation requires a reviewed owned disposal.
    private final class NativeDispatchUnresolvedRecord {
        let completion: BelugaNetworkAdaptationNativeCompletion
        let reason: NativeDispatchUnverifiedReason
        let secondaryError: (any Error)?
        let actualSenderError: (any Error)?
        init(completion: BelugaNetworkAdaptationNativeCompletion,
            reason: NativeDispatchUnverifiedReason, secondaryError: (any Error)?) {
            self.completion = completion; self.reason = reason
            self.secondaryError = secondaryError
            if case let .senderFailed(error) = completion.settlement {
                actualSenderError = error
            } else { actualSenderError = nil }
        }
    }
    private enum NativeDispatchOutcome {
        case adopted, superseded
        case rollbackOnly(reverted: Bool, adapterRefusal: (any Error)?)
        case retainedFailure(BelugaNetworkAdaptationFailureRetainedReceipt)
        case terminalStopConfirmed
        case unverified(NativeDispatchUnverifiedReason)
    }
    // Private actor-file sealed result of a synchronous claim, never supplied
    // by a caller as recovery authority. Owns the one existing consuming plan.
    private enum NativeDispatchPostFPSClaim: ~Copyable {
        case stop(ServiceStopPlan)
        case alreadyStopped
        case unverified(NativeDispatchUnverifiedReason)
    }

    // ONE owned RunNativeAttempt result. No caller-supplied settlement/result,
    // recovery enum, SDK token, fake Owner or mutable permission flag.
    private func dispatchActualNativeAdaptation(_ attempt: BelugaNetworkAdaptationNativeAttempt)
        async throws -> NativeDispatchOutcome {
        guard activeNativeAdaptationDispatch == nil,
              nativeAdaptationDispatchPhase == nil,
              unresolvedNativeAdaptationDispatch == nil else {
            // Consume only this waiting attempt; never replace an active owner.
            try attempt.claim(by: self, boundary: screenVideoAdaptationOwnerBoundary)
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        activeNativeAdaptationDispatch = attempt
        nativeAdaptationDispatchPhase = .waitingSDK
        defer { retireNativeAdaptationDispatch(attempt) }
        let completion = try await networkAdaptationRunNativeAttempt(attempt)
        precondition(completion.attempt === attempt)
        nativeAdaptationDispatchPhase = .settling
        switch completion.settlement {
        case .senderSucceeded:
            let result: BelugaNetworkAdaptationSuccessResult
            do { result = try screenVideoAdaptationOwnerBoundary.finishSuccess(completion, on: self) }
            catch {
                return retainUnverifiedNativeDispatch(completion, .adapterRefused, error)
            }
            switch result {
            case let .accepted(final):
                // No suspension or arbitrary callback between actual702/704.
                return finishActualNativeDispatchFinal(final, completion: completion)
            case let .rollback(cleanup):
                nativeAdaptationDispatchPhase = .waitingRollback
                return await finishNativeDispatchTokenRollback(cleanup,
                    completion: completion, refusal: nil)
            case let .refused(cleanup, error):
                nativeAdaptationDispatchPhase = .waitingRollback
                return await finishNativeDispatchTokenRollback(cleanup,
                    completion: completion, refusal: error)
            case let .requiresGuardedRecovery(cleanup):
                // The result came from OUR actual synchronous finishSuccess.
                // Synchronous cleanup spend + exact native claim + beginStop
                // happen HERE before the first await on this result path.
                let claim = claimCurrentNativeDispatchPostFPSRecovery(cleanup,
                    completion: completion)
                switch consume claim {
                case let .stop(plan):
                    // Only this exact synchronous noncopyable claim creates
                    // the exemption; never an ambient recovery/phase flag.
                    nativeAdaptationDispatchPhase = .ownStopTail(completion)
                    await finishStop(consume plan)
                    guard nativeDispatchOwnsExactClaimedStopTail(completion),
                          !nativeDispatchHasUnconfirmedBaseStop() else {
                        return retainUnverifiedNativeDispatch(completion, .nativeStopUnconfirmed, nil)
                    }
                    return .terminalStopConfirmed
                case .alreadyStopped:
                    await waitForStopToFinish()
                    return retainUnverifiedNativeDispatch(completion, .alreadyStoppedUnverified, nil)
                case let .unverified(reason):
                    return retainUnverifiedNativeDispatch(completion, reason, nil)
                }
            }
        case .senderFailed:
            do {
                switch try screenVideoAdaptationOwnerBoundary.finishFailure(completion, on: self) {
                case let .retained(receipt):
                    // Actual703 stored its complete/prefix result before return.
                    // Preserve SDK error and semanticStatus/clockDenial separately.
                    return .retainedFailure(receipt)
                case let .requiresGuardedRecovery(entry, error):
                    precondition(entry.completion === completion)
                    // No returned token and no proven full-stop admission here.
                    return retainUnverifiedNativeDispatch(completion, .adapterRefused, error)
                }
            } catch {
                return retainUnverifiedNativeDispatch(completion, .adapterRefused, error)
            }
        case .finalAdoptionOnly:
            do {
                let final = try screenVideoAdaptationOwnerBoundary.consumeFinalAdoptionOnly(completion, on: self)
                return finishActualNativeDispatchFinal(final, completion: completion)
            } catch {
                return retainUnverifiedNativeDispatch(completion, .adapterRefused, error)
            }
        }
    }

    private func finishActualNativeDispatchFinal(_ final: BelugaNetworkAdaptationFinalAdoptionReceipt,
        completion: BelugaNetworkAdaptationNativeCompletion) -> NativeDispatchOutcome {
        do {
            switch try screenVideoAdaptationOwnerBoundary.finalAdopt(final, on: self) {
            case .adopted: return .adopted
            case .superseded: return .superseded
            case let .refused(_, error):
                // Accepted702 cleanup is already retired. Do not mint/revive
                // a token receipt or stop an ambient newer source on704 refusal.
                return retainUnverifiedNativeDispatch(completion, .adapterRefused, error)
            }
        } catch {
            return retainUnverifiedNativeDispatch(completion, .adapterRefused, error)
        }
    }

    private func finishNativeDispatchTokenRollback(_ cleanup: BelugaNetworkAdaptationSuccessCleanupReceipt,
        completion: BelugaNetworkAdaptationNativeCompletion,
        refusal: (any Error)?) async -> NativeDispatchOutcome {
        precondition(cleanup.completion === completion)
        do {
            let reverted = try await networkAdaptationRollbackSuccessCleanup(cleanup)
            // false is native token supersession, not rollback success.
            // No Owner store, FPS, authorization revoke or current-source stop.
            return .rollbackOnly(reverted: reverted, adapterRefusal: refusal)
        } catch {
            return retainUnverifiedNativeDispatch(completion, .rollbackUncertain, error)
        }
    }

    // No await, callback or borrowed C frame. The caller owns the consuming
    // result; native shutdown claim cannot be delayed behind an async hop.
    private func claimCurrentNativeDispatchPostFPSRecovery(
        _ cleanup: BelugaNetworkAdaptationSuccessCleanupReceipt,
        completion: BelugaNetworkAdaptationNativeCompletion) -> NativeDispatchPostFPSClaim {
        // One-use record disposal precedes every rejection. No token/FPS retry.
        guard case .available = cleanup.state else {
            return .unverified(.recoveryCustodyMismatch)
        }
        cleanup.state = .spent
        let attempt = completion.attempt
        guard cleanup.completion === completion,
              activeNativeAdaptationDispatch === attempt,
              attempt.owner === self,
              attempt.seed.boundary === screenVideoAdaptationOwnerBoundary,
              case .settled = attempt.phase,
              case .senderSucceeded = completion.settlement,
              let r = attempt.resources else {
            return .unverified(.recoveryCustodyMismatch)
        }
        if isStopped {
            // Caller joins only; prior service stop is not old-source proof.
            return .alreadyStopped
        }
        guard !stopIsInProgress,
              peer === attempt.sourcePeer,
              peerGeneration == attempt.seed.entry.preparation.generation,
              screenVideoAdaptationOwner.revision == attempt.seed.prepared.tail.applyingRevision,
              screenVisibilityCommandEpoch == attempt.seed.entry.preparation.visibilityEpoch,
              captureSource === r.source, captureSink === r.sink,
              captureAuthorization === r.captureAuthorization,
              captureForwardingAuthorization === r.forwardingAuthorization,
              captureVideoBaseDimensions == r.baseDimensions,
              attempt.sourcePeer.externalVideoCapturer === r.capturer,
              automaticScreenMediaResumeContext == nil else {
            // Shared/newer Show/capturer ownership is not disposal permission.
            // Retain actual unresolved custody; do not touch native resources.
            return .unverified(.recoveryCustodyMismatch)
        }
        // Deliberately NO .isValid predicate: an already-revoked exact token
        // still identifies the affected lifetime needing disposal. No await
        // occurred since actual702 returned; no actor owner can interleave here.
        return .stop(beginStop())
    }

    private func retainUnverifiedNativeDispatch(_ completion: BelugaNetworkAdaptationNativeCompletion,
        _ reason: NativeDispatchUnverifiedReason, _ error: (any Error)?) -> NativeDispatchOutcome {
        precondition(activeNativeAdaptationDispatch === completion.attempt)
        precondition(unresolvedNativeAdaptationDispatch == nil)
        unresolvedNativeAdaptationDispatch = .init(completion: completion,
            reason: reason, secondaryError: error)
        return .unverified(reason)
    }
}
// STOPPED SOURCE-ONLY append in SAME WSS file; no fake SDK completion/error.
#if DEBUG
extension WorldwideScreenService {
    enum NativeDispatchFixtureCase: Equatable, Sendable { case success, noApply, closedPeerFailure, staleBeforeRun }
    enum NativeDispatchFixtureKind: Equatable, Sendable { case adopted, retainedFailure, preSDKRefused }
    struct NativeDispatchFixtureObservation: Sendable {
        let selected: NativeDispatchFixtureCase
        let kind: NativeDispatchFixtureKind
        let before: NativeOwnerPublicationSnapshotObservation
        let after: NativeOwnerPublicationSnapshotObservation
        let nativeBefore: Native704SDKReadback
        let nativeAfter: Native704SDKReadback
        let semanticStatus: UInt32?
        let acceptedReads: UInt32?
        let attemptedReads: UInt32?
        let actualSenderErrorIsTransportClosed: Bool?
        let quarantineAbsent: Bool
        let cleanupSourceStopped: Bool
        let cleanupPeerClosed: Bool
        let cleanupFieldsAreAbsent: Bool
        let cleanupAuthorizationsAreRevoked: Bool
    }
    private enum NativeDispatchFixtureError: Error { case unexpectedDisposition, unsafeCleanup }
    func nativeDispatchFixtureObservationForTesting(_ selected: NativeDispatchFixtureCase,
        readNative: @Sendable (WebRTCPeer) async -> Native704SDKReadback)
        async throws -> NativeDispatchFixtureObservation {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1",
              activeNativeAdaptationDispatch == nil, unresolvedNativeAdaptationDispatch == nil else {
            throw NativeAdaptationFixtureError.unsafeSetup
        }
        let f = try await makeNativeAdaptationFixtureResources()
        do {
            let attempt: BelugaNetworkAdaptationNativeAttempt
            if selected == .noApply { attempt = try await native704NoApplyAttempt(f) }
            else { attempt = try await native702FixtureAttempt(f) }
            if selected == .closedPeerFailure {
                guard await f.peer.close(reason: .normal) else {
                    throw NativeAdaptationFixtureError.unsafeSetup
                }
            }
            if selected == .staleBeforeRun { peer = nil }
            let before = try nativeOwnerStopSnapshotObservation(retainingAnchor: attempt.seed.published.anchor)
            let nativeBefore = await readNative(f.peer)
            let kind: NativeDispatchFixtureKind
            var semantic: UInt32?, accepted: UInt32?, attempted: UInt32?, transportClosed: Bool?
            do {
                let result = try await dispatchActualNativeAdaptation(attempt)
                switch result {
                case .adopted:
                    guard selected == .success || selected == .noApply else {
                        throw NativeDispatchFixtureError.unexpectedDisposition
                    }
                    kind = .adopted
                case let .retainedFailure(receipt):
                    guard selected == .closedPeerFailure,
                          receipt.disposition == .ordinary else {
                        throw NativeDispatchFixtureError.unexpectedDisposition
                    }
                    semantic = receipt.semanticStatus; accepted = receipt.acceptedReads
                    attempted = receipt.attemptedReads
                    if let error = receipt.actualSenderError as? WebRTCTransportError,
                       case .transportClosed = error { transportClosed = true }
                    else { transportClosed = false }
                    kind = .retainedFailure
                default: throw NativeDispatchFixtureError.unexpectedDisposition
                }
            } catch BelugaNetworkAdaptationOwnerError.refused {
                guard selected == .staleBeforeRun else { throw BelugaNetworkAdaptationOwnerError.refused }
                kind = .preSDKRefused
            }
            let after = try nativeOwnerStopSnapshotObservation(retainingAnchor: attempt.seed.published.anchor)
            let nativeAfter = await readNative(f.peer)
            let quarantineAbsent = unresolvedNativeAdaptationDispatch == nil
            let cleanup = await closeNativeAdaptationFixture(f)
            guard cleanup.sourceStopped && cleanup.peerClosed && cleanup.absent && cleanup.revoked else {
                throw NativeDispatchFixtureError.unsafeCleanup
            }
            return .init(selected: selected, kind: kind, before: before, after: after,
                nativeBefore: nativeBefore, nativeAfter: nativeAfter,
                semanticStatus: semantic, acceptedReads: accepted, attemptedReads: attempted,
                actualSenderErrorIsTransportClosed: transportClosed, quarantineAbsent: quarantineAbsent,
                cleanupSourceStopped: cleanup.sourceStopped, cleanupPeerClosed: cleanup.peerClosed,
                cleanupFieldsAreAbsent: cleanup.absent, cleanupAuthorizationsAreRevoked: cleanup.revoked)
        } catch {
            let cleanup = await closeNativeAdaptationFixture(f)
            guard cleanup.sourceStopped && cleanup.peerClosed && cleanup.absent && cleanup.revoked else {
                throw NativeDispatchFixtureError.unsafeCleanup
            }
            throw error
        }
    }
}
#endif

// The fault models post-C adapter refusal, NOT a natural SDK/Rust failure.
#if DEBUG
final class BelugaNetworkAdaptationPostEffectFixtureRefusal {
    fileprivate let attempt: BelugaNetworkAdaptationNativeAttempt
    fileprivate let boundary: BelugaNetworkAdaptationOwnerBoundary
    fileprivate var consumedBeforeC = false
    fileprivate var completion: BelugaNetworkAdaptationNativeCompletion?
    fileprivate var cleanup: BelugaNetworkAdaptationSuccessCleanupReceipt?
    private(set) var actualStatus: UInt32?
    private(set) var substitutions: UInt64 = 0
    fileprivate init(attempt: BelugaNetworkAdaptationNativeAttempt,
        boundary: BelugaNetworkAdaptationOwnerBoundary) {
        self.attempt = attempt; self.boundary = boundary
    }
    // Only the fixed post-effect adapter site uses this preallocated record.
    // These scalar writes neither manufacture recovery nor alter C/SDK output.
    func recordActualPostEffectStatus(_ status: UInt32) {
        actualStatus = status
        substitutions &+= 1
    }
}

extension WorldwideScreenService {
    private func bindNativeDispatchPostEffectFixtureRefusal(
        _ completion: BelugaNetworkAdaptationNativeCompletion,
        boundary: BelugaNetworkAdaptationOwnerBoundary,
        admission: BelugaNetworkAdaptationNativeSuccessEntry.Admission,
        cleanup: BelugaNetworkAdaptationSuccessCleanupReceipt) throws
        -> BelugaNetworkAdaptationPostEffectFixtureRefusal? {
        guard let fault = nativeDispatchPostEffectFixtureRefusal else { return nil }
        guard !fault.consumedBeforeC else { throw BelugaNetworkAdaptationOwnerError.refused }
        fault.consumedBeforeC = true // Also burns any wrong-identity admission.
        let attempt = completion.attempt
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1",
              fault.completion == nil, fault.cleanup == nil, fault.attempt === attempt,
              fault.boundary === boundary, boundary === screenVideoAdaptationOwnerBoundary,
              activeNativeAdaptationDispatch === attempt, attempt.owner === self,
              attempt.seed.boundary === boundary, case .settled = attempt.phase,
              case .senderSucceeded = completion.settlement, let r = attempt.resources,
              cleanup.completion === completion, case .available = cleanup.state,
              case let .ready(observation) = admission, observation.facts == 511,
              observation.generation == attempt.seed.prepared.tail.generation,
              observation.source.value.revision == attempt.seed.prepared.tail.applyingRevision,
              peer === attempt.sourcePeer,
              peerGeneration == attempt.seed.entry.preparation.generation,
              captureSource === r.source, captureSink === r.sink,
              captureAuthorization === r.captureAuthorization,
              captureForwardingAuthorization === r.forwardingAuthorization,
              captureVideoBaseDimensions == r.baseDimensions,
              attempt.sourcePeer.externalVideoCapturer === r.capturer else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        // The actual returned completion is sealed HERE, before borrowed C/FPS.
        fault.completion = completion
        fault.cleanup = cleanup
        return fault
    }

    struct NativeDispatchPostEffectPeerReadback: Sendable {
        let sdk: Native704SDKReadback
        let isClosed: Bool
    }
    struct NativeDispatchPostEffectRecoveryObservation: Sendable {
        let before: NativeOwnerPublicationSnapshotObservation
        let after: NativeOwnerPublicationSnapshotObservation
        let nativeBefore: NativeDispatchPostEffectPeerReadback
        let nativeAfter: NativeDispatchPostEffectPeerReadback
        let consumedBeforeC: Bool
        let actualCStatus: UInt32?
        let substitutions: UInt64
        let successDispatch: Native702DispatchObservation
        let cleanupUseSpent: Bool
        let terminalStopConfirmed: Bool
        let serviceStopped: Bool
        let stopTailJoined: Bool
        let originalSourceOwnershipClearedByTail: Bool
        let originalAuthorizationsRevokedByTail: Bool
        let originalSinkGateClosedByTail: Bool
        let dispatchSlotCleared: Bool
        let quarantineAbsent: Bool
        let hostUnconfirmedStopAbsent: Bool
        let secondaryCleanupSourceStopped: Bool
        let secondaryCleanupPeerClosed: Bool
        let secondaryCleanupFieldsAbsent: Bool
        let secondaryCleanupAuthorizationsRevoked: Bool
    }
    private enum NativeDispatchPostEffectFixtureError: Error {
        case unexpectedDisposition, missingActualCompletion, unsafeCleanup
    }

    // No external selected-case/effect flag or supplied completion/error. This
    // one fixed test factory owns a fresh inert tuple and its one fault use.
    func nativeDispatchPostEffectRecoveryObservationForTesting(
        readNative: @Sendable (WebRTCPeer) async -> NativeDispatchPostEffectPeerReadback)
        async throws -> NativeDispatchPostEffectRecoveryObservation {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1",
              activeNativeAdaptationDispatch == nil, unresolvedNativeAdaptationDispatch == nil,
              nativeDispatchPostEffectFixtureRefusal == nil else {
            throw NativeAdaptationFixtureError.unsafeSetup
        }
        let f = try await makeNativeAdaptationFixtureResources()
        defer { nativeDispatchPostEffectFixtureRefusal = nil }
        do {
            let attempt = try await native702FixtureAttempt(f)
            let fault = BelugaNetworkAdaptationPostEffectFixtureRefusal(attempt: attempt,
                boundary: screenVideoAdaptationOwnerBoundary)
            nativeDispatchPostEffectFixtureRefusal = fault
            let before = try nativeOwnerStopSnapshotObservation(retainingAnchor: attempt.seed.published.anchor)
            let nativeBefore = await readNative(f.peer)
            let outcome = try await dispatchActualNativeAdaptation(attempt)
            guard case .terminalStopConfirmed = outcome else {
                throw NativeDispatchPostEffectFixtureError.unexpectedDisposition
            }
            // Capture all tail assertions BEFORE secondary fixture cleanup.
            // stopScreenCapture clears an exact source only after source.stop
            // returned; this tuple never starts an SCStream or transport.
            let serviceStopped = isStopped
            let tailJoined = !stopIsInProgress
            let sourceCleared = captureSource == nil && captureSink == nil
                && captureVideoBaseDimensions == nil
            let revoked = !f.captureAuthorization.isValid && !f.forwardingAuthorization.isValid
                && captureAuthorization == nil && captureForwardingAuthorization == nil
            let sinkClosed = !f.sink.allowsActiveUse(authorizedBy: f.forwardingAuthorization)
            let slotCleared = activeNativeAdaptationDispatch == nil
            let quarantineAbsent = unresolvedNativeAdaptationDispatch == nil
            let unconfirmedAbsent = !hasUnconfirmedNativeCaptureStop()
            guard let completion = fault.completion, let cleanupReceipt = fault.cleanup else {
                throw NativeDispatchPostEffectFixtureError.missingActualCompletion
            }
            let trace = try native702Trace(completion)
            let spent: Bool
            // Observe the actual entry's exact cleanup latch, not a derived
            // status vote. No receipt or returned update escapes the actor.
            if case .spent = cleanupReceipt.state { spent = true }
            else { spent = false }
            let after = try nativeOwnerStopSnapshotObservation(retainingAnchor: attempt.seed.published.anchor)
            let nativeAfter = await readNative(f.peer)
            let cleanup = await closeNativeAdaptationFixture(f)
            guard cleanup.sourceStopped && cleanup.peerClosed && cleanup.absent && cleanup.revoked else {
                throw NativeDispatchPostEffectFixtureError.unsafeCleanup
            }
            return .init(before: before, after: after, nativeBefore: nativeBefore, nativeAfter: nativeAfter,
                consumedBeforeC: fault.consumedBeforeC, actualCStatus: fault.actualStatus,
                substitutions: fault.substitutions, successDispatch: trace, cleanupUseSpent: spent,
                terminalStopConfirmed: true, serviceStopped: serviceStopped, stopTailJoined: tailJoined,
                originalSourceOwnershipClearedByTail: sourceCleared,
                originalAuthorizationsRevokedByTail: revoked, originalSinkGateClosedByTail: sinkClosed,
                dispatchSlotCleared: slotCleared, quarantineAbsent: quarantineAbsent,
                hostUnconfirmedStopAbsent: unconfirmedAbsent,
                secondaryCleanupSourceStopped: cleanup.sourceStopped,
                secondaryCleanupPeerClosed: cleanup.peerClosed,
                secondaryCleanupFieldsAbsent: cleanup.absent,
                secondaryCleanupAuthorizationsRevoked: cleanup.revoked)
        } catch {
            let cleanup = await closeNativeAdaptationFixture(f)
            guard cleanup.sourceStopped && cleanup.peerClosed && cleanup.absent && cleanup.revoked else {
                throw NativeDispatchPostEffectFixtureError.unsafeCleanup
            }
            throw error
        }
    }
}
#endif

extension WorldwideScreenService {
    private enum NativeDispatchPhase {
        case waitingSDK, settling, waitingRollback
        case ownStopTail(BelugaNetworkAdaptationNativeCompletion)
    }
    private func nativeDispatchHasUnconfirmedBaseStop() -> Bool {
        unresolvedNativeAdaptationDispatch != nil
            || (isStopped && (captureSource != nil || audioSource != nil))
    }
    private func nativeDispatchOwnsExactClaimedStopTail(
        _ completion: BelugaNetworkAdaptationNativeCompletion) -> Bool {
        guard case let .ownStopTail(recorded)? = nativeAdaptationDispatchPhase,
              recorded === completion,
              activeNativeAdaptationDispatch === completion.attempt,
              completion.attempt.owner === self,
              completion.attempt.seed.boundary === screenVideoAdaptationOwnerBoundary,
              case .settled = completion.attempt.phase,
              case .senderSucceeded = completion.settlement,
              completion.attempt.resources != nil, isStopped else { return false }
        return true
    }
    private func retireNativeAdaptationDispatch(_ attempt: BelugaNetworkAdaptationNativeAttempt) {
        precondition(activeNativeAdaptationDispatch === attempt && nativeAdaptationDispatchPhase != nil)
        // Result/quarantine is already published inside this actor; no await
        // can split these two custody writes or reopen a waiting admission.
        nativeAdaptationDispatchPhase = nil
        activeNativeAdaptationDispatch = nil
    }
}

#if DEBUG
extension WorldwideScreenService {
    // Pure event rendezvous. NO attempt/completion/resources/C POD enter this
    // Sendable actor; those remain in the service's sealed private use below.
    private actor NativeDispatchReturnFixtureGate {
        private enum State { case armed, held, released, completedBeforeArrival }
        private var state = State.armed
        private var arrivalWaiter: CheckedContinuation<Void, Never>?
        private var releaseWaiter: CheckedContinuation<Void, Never>?
        func holdActualReturn() async {
            guard case .armed = state else { preconditionFailure("Return gate used twice") }
            state = .held
            let arrival = arrivalWaiter; arrivalWaiter = nil
            arrival?.resume()
            await withCheckedContinuation { continuation in
                precondition(releaseWaiter == nil)
                releaseWaiter = continuation
            }
            guard case .released = state else { preconditionFailure("Return gate was not released") }
        }
        func waitForHeldOrEarlyCompletion() async -> Bool {
            if case .held = state { return true }
            if case .completedBeforeArrival = state { return false }
            guard case .armed = state, arrivalWaiter == nil else {
                preconditionFailure("Return gate arrival waited twice")
            }
            await withCheckedContinuation { arrivalWaiter = $0 }
            if case .held = state { return true }
            guard case .completedBeforeArrival = state else {
                preconditionFailure("Unexpected return gate arrival state")
            }
            return false
        }
        func releaseOwnedReturn() {
            guard case .held = state, let release = releaseWaiter else {
                preconditionFailure("Return gate release without held return")
            }
            state = .released; releaseWaiter = nil
            release.resume()
        }
        func releaseHeldReturnForFailureCleanup() {
            if case .held = state { releaseOwnedReturn() }
        }
        func noteOwnedRunFinished() {
            if case .armed = state {
                state = .completedBeforeArrival
                let arrival = arrivalWaiter; arrivalWaiter = nil
                arrival?.resume()
                return
            }
            guard case .released = state else {
                preconditionFailure("Owned dispatch ended with held return")
            }
        }
    }
    private final class NativeDispatchReturnFixtureUse {
        let attempt: BelugaNetworkAdaptationNativeAttempt
        let boundary: BelugaNetworkAdaptationOwnerBoundary
        let gate: NativeDispatchReturnFixtureGate
        var completion: BelugaNetworkAdaptationNativeCompletion?
        var cleanup: BelugaNetworkAdaptationSuccessCleanupReceipt?
        var outcome: NativeDispatchOutcome?
        var failure: (any Error)?
        var didReturn = false
        init(attempt: BelugaNetworkAdaptationNativeAttempt,
            boundary: BelugaNetworkAdaptationOwnerBoundary,
            gate: NativeDispatchReturnFixtureGate) {
            self.attempt = attempt; self.boundary = boundary; self.gate = gate
        }
    }
    enum NativeDispatchReturnFixtureCut: Equatable, Sendable { case captureStop, serviceStop }
    enum NativeDispatchReturnFixtureResult: Equatable, Sendable { case rollbackTrue, rollbackUncertainTransportClosed }
    struct NativeDispatchReturnFixtureObservation: Sendable {
        let selected: NativeDispatchReturnFixtureCut
        let result: NativeDispatchReturnFixtureResult
        let before: NativeOwnerPublicationSnapshotObservation
        let afterCut: NativeOwnerPublicationSnapshotObservation
        let afterDispatch: NativeOwnerPublicationSnapshotObservation
        let afterRepeatedStop: NativeOwnerPublicationSnapshotObservation?
        let nativeBefore: NativeDispatchPostEffectPeerReadback
        let nativeAfterSetter: NativeDispatchPostEffectPeerReadback
        let nativeAfterCut: NativeDispatchPostEffectPeerReadback
        let nativeAfterDispatch: NativeDispatchPostEffectPeerReadback
        let nativeAfterRepeatedStop: NativeDispatchPostEffectPeerReadback?
        let terminalOwnedBeforeRelease: Bool
        let slotsAbsentBeforeRelease: Bool
        let originalAuthorizationsRevokedBeforeRelease: Bool
        let originalSinkClosedBeforeRelease: Bool
        let publicUnconfirmedAfterDispatch: Bool
        let publicUnconfirmedAfterRepeatedStop: Bool?
        let exactQuarantineSurvivedRepeatedStop: Bool?
        let successDispatch: Native702DispatchObservation
        let cleanupUseSpent: Bool
        let dispatchSlotsCleared: Bool
        let secondaryCleanupSourceStopped: Bool
        let secondaryCleanupPeerClosed: Bool
        let secondaryCleanupFieldsAbsent: Bool
        let secondaryCleanupAuthorizationsRevoked: Bool
    }
    private enum NativeDispatchReturnFixtureError: Error {
        case earlyReturn, notSuccessfulActualCompletion, wrongDisposition
        case missingActualCleanup, unsafeCleanup
    }
    // Task captures ONLY the Sendable service actor. All non-Sendable attempt,
    // completion, receipt, result and Error custody stays in its private slot.
    private func runOwnedNativeDispatchReturnFixture() async {
        guard let use = nativeDispatchReturnFixtureUse else {
            preconditionFailure("Missing owned native return fixture")
        }
        do { use.outcome = try await dispatchActualNativeAdaptation(use.attempt) }
        catch { use.failure = error }
        use.didReturn = true
        await use.gate.noteOwnedRunFinished()
    }
    func nativeDispatchReturnFixtureObservationForTesting(_ selected: NativeDispatchReturnFixtureCut,
        readNative: @Sendable (WebRTCPeer) async -> NativeDispatchPostEffectPeerReadback)
        async throws -> NativeDispatchReturnFixtureObservation {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1",
              activeNativeAdaptationDispatch == nil, nativeAdaptationDispatchPhase == nil,
              unresolvedNativeAdaptationDispatch == nil,
              nativeDispatchPostEffectFixtureRefusal == nil, nativeDispatchReturnFixtureUse == nil else {
            throw NativeAdaptationFixtureError.unsafeSetup
        }
        let f = try await makeNativeAdaptationFixtureResources()
        var ownedTask: Task<Void, Never>?
        var ownedGate: NativeDispatchReturnFixtureGate?
        defer { nativeDispatchReturnFixtureUse = nil }
        do {
            let attempt = try await native702FixtureAttempt(f)
            let gate = NativeDispatchReturnFixtureGate()
            let use = NativeDispatchReturnFixtureUse(attempt: attempt,
                boundary: screenVideoAdaptationOwnerBoundary, gate: gate)
            nativeDispatchReturnFixtureUse = use; ownedGate = gate
            let before = try nativeOwnerStopSnapshotObservation(retainingAnchor: attempt.seed.published.anchor)
            let nativeBefore = await readNative(f.peer)
            let task = Task<Void, Never> { [self] in await runOwnedNativeDispatchReturnFixture() }
            ownedTask = task
            guard await gate.waitForHeldOrEarlyCompletion() else {
                throw NativeDispatchReturnFixtureError.earlyReturn
            }
            guard let completion = use.completion,
                  completion.attempt === attempt, case .senderSucceeded = completion.settlement else {
                throw NativeDispatchReturnFixtureError.notSuccessfulActualCompletion
            }
            let nativeAfterSetter = await readNative(f.peer)
            // Fixed original lifecycle actions only; never Owner/generation
            // seeding, replacement resources, SDK error/token fabrication.
            switch selected {
            case .captureStop: try await stopScreenCapture()
            case .serviceStop: await stop()
            }
            let afterCut = try nativeOwnerStopSnapshotObservation(retainingAnchor: attempt.seed.published.anchor)
            let nativeAfterCut = await readNative(f.peer)
            let terminalOwnedBeforeRelease = hasUnconfirmedNativeCaptureStop()
            let slotsAbsent = captureSource == nil && captureSink == nil
                && captureAuthorization == nil && captureForwardingAuthorization == nil
                && captureVideoBaseDimensions == nil
            let revoked = !f.captureAuthorization.isValid && !f.forwardingAuthorization.isValid
            let sinkClosed = !f.sink.allowsActiveUse(authorizedBy: f.forwardingAuthorization)
            await gate.releaseOwnedReturn()
            await task.value // genuine Void Task, joined BEFORE helper cleanup
            guard use.didReturn else { preconditionFailure("Owned dispatch task did not return") }
            if let error = use.failure { throw error }
            let result: NativeDispatchReturnFixtureResult
            switch use.outcome {
            case let .rollbackOnly(reverted, refusal)?:
                guard selected == .captureStop, reverted, refusal == nil else {
                    throw NativeDispatchReturnFixtureError.wrongDisposition
                }
                result = .rollbackTrue
            case let .unverified(reason)?:
                guard selected == .serviceStop, case .rollbackUncertain = reason,
                      let record = unresolvedNativeAdaptationDispatch,
                      record.completion === completion,
                      let error = record.secondaryError as? WebRTCTransportError,
                      case .transportClosed = error else {
                    throw NativeDispatchReturnFixtureError.wrongDisposition
                }
                result = .rollbackUncertainTransportClosed
            default: throw NativeDispatchReturnFixtureError.wrongDisposition
            }
            guard let receipt = use.cleanup, receipt.completion === completion else {
                throw NativeDispatchReturnFixtureError.missingActualCleanup
            }
            let spent: Bool
            if case .spent = receipt.state { spent = true } else { spent = false }
            let trace = try native702Trace(completion)
            let afterDispatch = try nativeOwnerStopSnapshotObservation(retainingAnchor: attempt.seed.published.anchor)
            let nativeAfterDispatch = await readNative(f.peer)
            let publicAfterDispatch = hasUnconfirmedNativeCaptureStop()
            let slotsCleared = activeNativeAdaptationDispatch == nil && nativeAdaptationDispatchPhase == nil
            var afterRepeated: NativeOwnerPublicationSnapshotObservation?
            var nativeAfterRepeated: NativeDispatchPostEffectPeerReadback?
            var publicAfterRepeated: Bool?, exactQuarantine: Bool?
            if selected == .serviceStop {
                let retained = unresolvedNativeAdaptationDispatch
                await stop() // cannot clear the already-published actual record
                afterRepeated = try nativeOwnerStopSnapshotObservation(retainingAnchor: attempt.seed.published.anchor)
                nativeAfterRepeated = await readNative(f.peer)
                publicAfterRepeated = hasUnconfirmedNativeCaptureStop()
                exactQuarantine = retained != nil && unresolvedNativeAdaptationDispatch === retained
            }
            // All outcome/native/quarantine observations precede this helper.
            let cleanup = await closeNativeAdaptationFixture(f)
            guard cleanup.sourceStopped && cleanup.peerClosed && cleanup.absent && cleanup.revoked else {
                throw NativeDispatchReturnFixtureError.unsafeCleanup
            }
            return .init(selected: selected, result: result, before: before, afterCut: afterCut,
                afterDispatch: afterDispatch, afterRepeatedStop: afterRepeated,
                nativeBefore: nativeBefore, nativeAfterSetter: nativeAfterSetter,
                nativeAfterCut: nativeAfterCut, nativeAfterDispatch: nativeAfterDispatch,
                nativeAfterRepeatedStop: nativeAfterRepeated,
                terminalOwnedBeforeRelease: terminalOwnedBeforeRelease,
                slotsAbsentBeforeRelease: slotsAbsent,
                originalAuthorizationsRevokedBeforeRelease: revoked,
                originalSinkClosedBeforeRelease: sinkClosed,
                publicUnconfirmedAfterDispatch: publicAfterDispatch,
                publicUnconfirmedAfterRepeatedStop: publicAfterRepeated,
                exactQuarantineSurvivedRepeatedStop: exactQuarantine,
                successDispatch: trace, cleanupUseSpent: spent, dispatchSlotsCleared: slotsCleared,
                secondaryCleanupSourceStopped: cleanup.sourceStopped,
                secondaryCleanupPeerClosed: cleanup.peerClosed,
                secondaryCleanupFieldsAbsent: cleanup.absent,
                secondaryCleanupAuthorizationsRevoked: cleanup.revoked)
        } catch {
            // No native tuple is cleaned while its owned dispatch Task remains
            // parked. Early native admission failure wakes arrival separately.
            await ownedGate?.releaseHeldReturnForFailureCleanup()
            await ownedTask?.value
            let cleanup = await closeNativeAdaptationFixture(f)
            guard cleanup.sourceStopped && cleanup.peerClosed && cleanup.absent && cleanup.revoked else {
                throw NativeDispatchReturnFixtureError.unsafeCleanup
            }
            throw error
        }
    }
}
#endif
