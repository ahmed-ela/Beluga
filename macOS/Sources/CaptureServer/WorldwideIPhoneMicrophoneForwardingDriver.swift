import CaptureCore
import Foundation

enum WorldwideIPhoneMicrophoneForwardingPolicy:
    String,
    Equatable,
    Sendable
{
    case enabled
    case suppressedForLANCoexistence
}

enum WorldwideIPhoneMicrophoneForwardingPhase:
    String,
    Equatable,
    Sendable
{
    case waitingForMonitor
    case monitoringFailed
    case waitingForDevice
    case waitingForPeer
    case waitingForTransport
    case waitingForTrack
    case starting
    case admittingTrack
    case checkingReadiness
    case awaitingFrames
    case forwardingReady
    case forwardingHealthy
    case outputUnavailable
    case startFailed
    case admissionFailed
    case readinessFailed
    case sourceMediaStalled
    case formatUnsafe
    case sharedClockUnsafe
    case runtimeFailed
    case suppressedForLANCoexistence
    case stopped
}

enum WorldwideIPhoneMicrophoneForwardingFailureCategory:
    String,
    Equatable,
    Sendable
{
    case monitoringFailed
    case outputUnavailable
    case startFailed
    case admissionFailed
    case readinessFailed
    case sourceMediaStalled
    case formatUnsafe
    case sharedClockUnsafe
    case runtimeEnqueueFailed
    case runtimeProgressStalled
    case evidenceBridgeRefused
}

struct WorldwideIPhoneMicrophoneForwardingKey:
    Equatable,
    Hashable,
    Sendable
{
    let monitorEpoch: UUID
    let deviceGeneration: UInt64
    let peerGeneration: UInt64
    let transportAuthorizationEpoch: UInt64
    let trackGeneration: UInt64
}

struct WorldwideIPhoneMicrophoneForwardingHostSnapshot:
    Equatable,
    Sendable
{
    let policy: WorldwideIPhoneMicrophoneForwardingPolicy
    let phase: WorldwideIPhoneMicrophoneForwardingPhase
    let monitorEpoch: UUID?
    let deviceGeneration: UInt64
    let deviceUID: String?
    let sinkDeviceUID: String?
    let deviceAvailable: Bool
    let currentKey: WorldwideIPhoneMicrophoneForwardingKey?
    let lastAttemptedKey: WorldwideIPhoneMicrophoneForwardingKey?
    let peerGeneration: UInt64
    let transportAuthorizationEpoch: UInt64
    let transportAuthorized: Bool
    let trackGeneration: UInt64
    let currentAttemptID: UUID?
    let lastAttemptID: UUID?
    let attemptGeneration: UInt64
    let exactTrackAdmitted: Bool
    let queueRunning: Bool
    let progress: BlackHoleMicrophoneOutputProgressSnapshot
    let inboundMediaSampleSequence: UInt64
    let inboundMediaAdvancementCount: UInt64
    let consecutiveStaleInboundMediaSamples: Int
    let inboundMediaFresh: Bool
    let lastFailureCategory:
        WorldwideIPhoneMicrophoneForwardingFailureCategory?

    var hiddenWriterSelectionProven: Bool {
        deviceAvailable
            && sinkDeviceUID != nil
            && queueRunning
    }

    static func inactive(
        policy: WorldwideIPhoneMicrophoneForwardingPolicy
    ) -> Self {
        Self(
            policy: policy,
            phase: policy == .suppressedForLANCoexistence
                ? .suppressedForLANCoexistence
                : .waitingForPeer,
            monitorEpoch: nil,
            deviceGeneration: 0,
            deviceUID: nil,
            sinkDeviceUID: nil,
            deviceAvailable: false,
            currentKey: nil,
            lastAttemptedKey: nil,
            peerGeneration: 0,
            transportAuthorizationEpoch: 0,
            transportAuthorized: false,
            trackGeneration: 0,
            currentAttemptID: nil,
            lastAttemptID: nil,
            attemptGeneration: 0,
            exactTrackAdmitted: false,
            queueRunning: false,
            progress: .zero,
            inboundMediaSampleSequence: 0,
            inboundMediaAdvancementCount: 0,
            consecutiveStaleInboundMediaSamples: 0,
            inboundMediaFresh: false,
            lastFailureCategory: nil
        )
    }
}

enum WorldwideIPhoneMicrophoneForwardingProgressEvaluator {
    static func isReady(
        _ progress: BlackHoleMicrophoneOutputProgressSnapshot
    ) -> Bool {
        progress.queueRunning
            && progress.enqueueFailureCount == 0
            && progress.successfulPullCount > 0
            && progress.successfulFrameCount > 0
    }

    static func provesContinuingHealth(
        previous: BlackHoleMicrophoneOutputProgressSnapshot,
        current: BlackHoleMicrophoneOutputProgressSnapshot
    ) -> Bool {
        isReady(previous)
            && isReady(current)
            && current.postStartCallbackCount
                > previous.postStartCallbackCount
            && current.successfulFrameCount
                > previous.successfulFrameCount
    }
}

struct WorldwideIPhoneMicrophoneInboundMediaWatermark:
    Equatable,
    Sendable
{
    let packetsReceived: UInt64?
    let bytesReceived: UInt64?
    let jitterBufferEmittedCount: UInt64?
    let totalSamplesReceived: UInt64?

    func isContinuous(
        from previous: Self?
    ) -> Bool {
        guard let previous else { return true }
        return !Self.regressed(
            current: packetsReceived,
            previous: previous.packetsReceived
        ) && !Self.regressed(
            current: bytesReceived,
            previous: previous.bytesReceived
        ) && !Self.regressed(
            current: jitterBufferEmittedCount,
            previous: previous.jitterBufferEmittedCount
        ) && !Self.regressed(
            current: totalSamplesReceived,
            previous: previous.totalSamplesReceived
        )
    }

    func advances(
        from previous: Self?
    ) -> Bool {
        guard let previous else { return false }
        return Self.advanced(
            current: packetsReceived,
            previous: previous.packetsReceived
        ) || Self.advanced(
            current: bytesReceived,
            previous: previous.bytesReceived
        )
    }

    func preservingMaximums(
        from previous: Self?
    ) -> Self {
        guard let previous else { return self }
        return Self(
            packetsReceived: Self.maximum(
                previous.packetsReceived,
                packetsReceived
            ),
            bytesReceived: Self.maximum(
                previous.bytesReceived,
                bytesReceived
            ),
            jitterBufferEmittedCount: Self.maximum(
                previous.jitterBufferEmittedCount,
                jitterBufferEmittedCount
            ),
            totalSamplesReceived: Self.maximum(
                previous.totalSamplesReceived,
                totalSamplesReceived
            )
        )
    }

    private static func advanced(
        current: UInt64?,
        previous: UInt64?
    ) -> Bool {
        guard let current, let previous else { return false }
        return current > previous
    }

    private static func regressed(
        current: UInt64?,
        previous: UInt64?
    ) -> Bool {
        guard let current, let previous else { return false }
        return current < previous
    }

    private static func maximum(
        _ lhs: UInt64?,
        _ rhs: UInt64?
    ) -> UInt64? {
        switch (lhs, rhs) {
        case (let lhs?, let rhs?):
            max(lhs, rhs)
        case (let value?, nil), (nil, let value?):
            value
        case (nil, nil):
            nil
        }
    }
}

/// Actor-owned, generation-keyed driver for the Mac microphone forwarding lane.
///
/// Public methods inherit the caller's actor. Every suspension revalidates the
/// complete key and exact peer, track, and output objects before continuing.
final class WorldwideIPhoneMicrophoneForwardingDriver<
    Peer: AnyObject & Sendable,
    Track: AnyObject & Sendable
> {
    typealias OutputFactory =
        @Sendable (
            Peer,
            BlackHoleDeviceEndpointIdentity
        ) -> (any WorldwideIPhoneMicrophoneOutput)?
    typealias OutputStarter =
        @Sendable (
            any WorldwideIPhoneMicrophoneOutput
        ) async throws -> Void
    typealias Admission =
        @Sendable (Peer, Track) async throws -> Void
    typealias TrackDisabler =
        @Sendable (Track) -> Void
    typealias ReadinessSleep =
        @Sendable () async throws -> Void
    typealias MonotonicNow = @Sendable () -> UInt64
    typealias MediaFreshnessDeadlineSleep =
        @Sendable (_ deadlineNanoseconds: UInt64) async throws -> Void
    typealias SharedClockFailureHandler =
        @Sendable (
            WorldwideIPhoneMicrophoneForwardingKey,
            BlackHoleFaceTimeClockRejection
        ) async -> Void
    typealias FormatFailureHandler =
        @Sendable (
            WorldwideIPhoneMicrophoneForwardingKey,
            BlackHoleMicrophoneOutputFormatRejection
        ) async -> Void

    private struct Candidate {
        let key: WorldwideIPhoneMicrophoneForwardingKey
        let peer: Peer
        let track: Track
        let sinkEndpoint: BlackHoleDeviceEndpointIdentity
    }

    private struct InboundMediaSample: Equatable {
        let sequence: UInt64
        let peerGeneration: UInt64
        let trackGeneration: UInt64
        let watermark:
            WorldwideIPhoneMicrophoneInboundMediaWatermark?
    }

    private final class Attempt {
        let id: UUID
        let key: WorldwideIPhoneMicrophoneForwardingKey
        let peer: Peer
        let track: Track
        let sinkEndpoint: BlackHoleDeviceEndpointIdentity
        let output: any WorldwideIPhoneMicrophoneOutput
        var exactTrackAdmitted = false
        var deferredReadyProgress:
            BlackHoleMicrophoneOutputProgressSnapshot?
        var sinkContinuingHealthProven = false
        var lastInboundMediaWatermark:
            WorldwideIPhoneMicrophoneInboundMediaWatermark?
        var lastInboundMediaSampleSequence: UInt64
        var inboundMediaAdvancementCount: UInt64 = 0
        var consecutiveStaleInboundMediaSamples = 0
        var requiresFreshInboundMediaAdvance: Bool
        var mediaFreshnessDeadlineNanoseconds: UInt64?
        var mediaFreshnessWatchdogGeneration: UInt64 = 0

        init(
            id: UUID,
            candidate: Candidate,
            output: any WorldwideIPhoneMicrophoneOutput,
            baselineInboundMediaSample: InboundMediaSample?,
            requiresFreshInboundMediaAdvance: Bool
        ) {
            self.id = id
            key = candidate.key
            peer = candidate.peer
            track = candidate.track
            sinkEndpoint = candidate.sinkEndpoint
            self.output = output
            lastInboundMediaWatermark =
                baselineInboundMediaSample?.watermark
            lastInboundMediaSampleSequence =
                baselineInboundMediaSample?.sequence ?? 0
            self.requiresFreshInboundMediaAdvance =
                requiresFreshInboundMediaAdvance
        }
    }

    private let policy: WorldwideIPhoneMicrophoneForwardingPolicy
    private let makeOutput: OutputFactory
    private let startOutput: OutputStarter
    private let admit: Admission
    private let disableTrack: TrackDisabler
    private let readinessSleep: ReadinessSleep
    private let retrySleep: ReadinessSleep
    private let readinessSampleLimit: Int
    private let maximumStaleInboundMediaSamples: Int
    private let mediaFreshnessTimeoutNanoseconds: UInt64
    private let mediaFreshnessNow: MonotonicNow
    private let mediaFreshnessDeadlineSleep:
        MediaFreshnessDeadlineSleep
    private let maximumAttemptCountPerKey: Int
    private let makeAttemptID: @Sendable () -> UUID
    private let sharedClockFailureHandler:
        SharedClockFailureHandler
    private let formatFailureHandler:
        FormatFailureHandler

    private var activeMonitorEpoch: UUID?
    private var monitorSnapshot: BlackHoleDeviceAvailabilitySnapshot?
    private var monitoringFailed = false

    private var peer: Peer?
    private var peerGeneration: UInt64 = 0
    private var transportAuthorizationEpoch: UInt64 = 0
    private var transportAuthorized = false
    private var track: Track?
    private var trackGeneration: UInt64 = 0
    private var inboundMediaSampleSequence: UInt64 = 0
    private var latestInboundMediaSample: InboundMediaSample?

    private var currentAttempt: Attempt?
    private struct AttemptHistory: Equatable {
        var count: Int
        var mayRetry: Bool
    }

    private var attemptHistory:
        [WorldwideIPhoneMicrophoneForwardingKey: AttemptHistory] = [:]
    private var attemptedKeyOrder:
        [WorldwideIPhoneMicrophoneForwardingKey] = []
    private var lastAttemptedKey:
        WorldwideIPhoneMicrophoneForwardingKey?
    private var lastAttemptID: UUID?
    private var attemptGeneration: UInt64 = 0
    private var lastFailureCategory:
        WorldwideIPhoneMicrophoneForwardingFailureCategory?
    private var preserveSharedClockUnsafePhaseUntilPeerOrPairChanges =
        false
    private var preserveFormatUnsafePhaseUntilPeerOrPairChanges =
        false

    private var phase: WorldwideIPhoneMicrophoneForwardingPhase
    private var isDriving = false
    private var redriveRequested = false
    private var isStopped = false
    private var mediaFreshnessWatchdogTask: Task<Void, Never>?
    private var evidenceBridge = BelugaRustMicrophoneForwardingEvidence()
    private var evidenceBusy = false
    private var evidencePoisoned = false
    private var evidenceSuperseded = false
    private var evidenceBridgeFaulted = false
    private final class EvidenceFrame {
        var retiredAttempt: Attempt?
        var retiredRetryKey: WorldwideIPhoneMicrophoneForwardingKey?
        var faultExhaustConsumed = false
    }
    private var activeEvidenceFrame: EvidenceFrame?

    #if DEBUG
    private var retryPostResultMutation:
        BelugaRustMicrophoneForwardingRetry.PostResultMutation?
    private var faultExhaustCallsForTesting = 0
    #endif

    private enum EvidenceDecisionFailure: Error { case superseded, poisoned }

    private struct EvidenceHistory: Equatable {
        let admitted: Bool
        let deferredProgress: BlackHoleMicrophoneOutputProgressSnapshot?
        let sinkHealthy: Bool
        let watermark: WorldwideIPhoneMicrophoneInboundMediaWatermark?
        let sequence: UInt64
        let advancementCount: UInt64
        let staleCount: Int
        let requiresAdvance: Bool
        let deadline: UInt64?
        let watchdogGeneration: UInt64

        init(_ attempt: Attempt) {
            admitted = attempt.exactTrackAdmitted
            deferredProgress = attempt.deferredReadyProgress
            sinkHealthy = attempt.sinkContinuingHealthProven
            watermark = attempt.lastInboundMediaWatermark
            sequence = attempt.lastInboundMediaSampleSequence
            advancementCount = attempt.inboundMediaAdvancementCount
            staleCount = attempt.consecutiveStaleInboundMediaSamples
            requiresAdvance = attempt.requiresFreshInboundMediaAdvance
            deadline = attempt.mediaFreshnessDeadlineNanoseconds
            watchdogGeneration = attempt.mediaFreshnessWatchdogGeneration
        }
    }

    private struct EvidenceWitness {
        let attempt: Attempt
        let history: EvidenceHistory
        let latestSample: InboundMediaSample?
    }

    private func beginEvidenceFrame() -> Bool {
        if evidenceBusy {
            evidencePoisoned = true
            evidenceBridgeFaulted = true
            retainEvidenceFailurePhase()
            return false
        }
        guard !evidenceBridgeFaulted else {
            retainEvidenceFailurePhase()
            return false
        }
        evidenceBusy = true
        activeEvidenceFrame = EvidenceFrame()
        evidencePoisoned = false
        evidenceSuperseded = false
        return true
    }

    private func endEvidenceFrame() {
        evidenceBusy = false
        activeEvidenceFrame = nil
        evidencePoisoned = false
        evidenceSuperseded = false
        retainEvidenceFailurePhase()
    }

    private func supersedeEvidenceFrame() {
        if evidenceBusy { evidenceSuperseded = true }
    }

    private func evidenceWitness(for attempt: Attempt) throws -> EvidenceWitness {
        try requireEvidenceOwner(attempt)
        return EvidenceWitness(attempt: attempt, history: EvidenceHistory(attempt),
                               latestSample: latestInboundMediaSample)
    }

    private func requireEvidenceOwner(_ attempt: Attempt) throws {
        precondition(evidenceBusy)
        guard !evidencePoisoned, !evidenceBridgeFaulted else {
            throw EvidenceDecisionFailure.poisoned
        }
        guard !evidenceSuperseded, candidateStillOwnsAttempt(attempt) else {
            throw EvidenceDecisionFailure.superseded
        }
    }

    private func requireEvidenceWitness(_ witness: EvidenceWitness) throws {
        try requireEvidenceOwner(witness.attempt)
        guard EvidenceHistory(witness.attempt) == witness.history,
              latestInboundMediaSample == witness.latestSample else {
            throw EvidenceDecisionFailure.superseded
        }
    }

    private func finishEvidenceFailure(_ error: Error, original: Attempt?) {
        if let failure = error as? EvidenceDecisionFailure,
           case .superseded = failure, !evidencePoisoned, !evidenceBridgeFaulted {
            return
        }
        evidenceBridgeFaulted = true
        if let original, currentAttempt === original {
            // Native privacy retirement precedes fixed, callback-free bookkeeping.
            if retireAttemptNative(original) {
                exhaustFaultedRetryBookkeeping(original.key)
            }
        } else if let original, activeEvidenceFrame?.retiredAttempt === original {
            exhaustFaultedRetryBookkeeping(original.key)
        } else if original == nil, let key = activeEvidenceFrame?.retiredRetryKey {
            exhaustFaultedRetryBookkeeping(key)
        }
        retainEvidenceFailurePhase()
    }

    private func retainEvidenceFailurePhase() {
        guard evidenceBridgeFaulted else { return }
        redriveRequested = false
        if isStopped {
            phase = .stopped
            return
        }
        lastFailureCategory = .evidenceBridgeRefused
        phase = .runtimeFailed
    }

    #if DEBUG
    func configureEvidenceMutationsForTesting(
        isolation: isolated (any Actor)? = #isolation,
        _ mutations: BelugaRustMicrophoneForwardingEvidence.Mutations
    ) {
        precondition(!evidenceBusy && !evidenceBridgeFaulted)
        precondition(currentAttempt == nil && attemptGeneration == 0)
        evidenceBridge = BelugaRustMicrophoneForwardingEvidence(mutations: mutations)
    }

    func configureRetryMutationForTesting(
        isolation: isolated (any Actor)? = #isolation,
        _ mutation: BelugaRustMicrophoneForwardingRetry.PostResultMutation?
    ) {
        precondition(!evidenceBusy && !evidenceBridgeFaulted)
        precondition(currentAttempt == nil && attemptGeneration == 0)
        retryPostResultMutation = mutation
    }
    #endif

    #if DEBUG
    /// Read-only copied bookkeeping. No row setter, native admission or producer.
    func retryObservationForTesting(
        isolation: isolated (any Actor)? = #isolation,
        key: WorldwideIPhoneMicrophoneForwardingKey
    ) -> (count: Int?, mayRetry: Bool?, redrive: Bool, faultExhaustCalls: Int,
          bridgeFaulted: Bool, retainedKeys: [WorldwideIPhoneMicrophoneForwardingKey]) {
        let row = attemptHistory[key]
        return (row?.count, row?.mayRetry, redriveRequested, faultExhaustCallsForTesting,
                evidenceBridgeFaulted, attemptedKeyOrder)
    }

    func seedUnauthorizedFailureForTesting(
        isolation: isolated (any Actor)? = #isolation,
        _ category: WorldwideIPhoneMicrophoneForwardingFailureCategory
    ) {
        precondition(category == .sharedClockUnsafe || category == .formatUnsafe)
        precondition(!isStopped && currentAttempt == nil && peer == nil && track == nil)
        precondition(!transportAuthorized && mediaFreshnessWatchdogTask == nil)
        preserveSharedClockUnsafePhaseUntilPeerOrPairChanges = false
        preserveFormatUnsafePhaseUntilPeerOrPairChanges = false
        lastFailureCategory = category
        phase = category == .sharedClockUnsafe ? .sharedClockUnsafe : .formatUnsafe
    }
    #endif

    init(
        policy: WorldwideIPhoneMicrophoneForwardingPolicy,
        makeOutput: @escaping OutputFactory,
        startOutput: @escaping OutputStarter,
        admit: @escaping Admission,
        disableTrack: @escaping TrackDisabler,
        readinessSleep: @escaping ReadinessSleep = {
            try await Task.sleep(for: .milliseconds(20))
        },
        readinessSampleLimit: Int = 50,
        maximumStaleInboundMediaSamples: Int = 3,
        mediaFreshnessTimeoutNanoseconds: UInt64 = 3_000_000_000,
        mediaFreshnessNow: @escaping MonotonicNow = {
            DispatchTime.now().uptimeNanoseconds
        },
        mediaFreshnessDeadlineSleep:
            @escaping MediaFreshnessDeadlineSleep = { deadline in
                while true {
                    let now = DispatchTime.now().uptimeNanoseconds
                    guard now < deadline else { return }
                    try await Task.sleep(
                        nanoseconds: deadline - now
                    )
                }
            },
        retrySleep: @escaping ReadinessSleep = {
            try await Task.sleep(for: .milliseconds(100))
        },
        maximumAttemptCountPerKey: Int = 3,
        makeAttemptID: @escaping @Sendable () -> UUID = {
            UUID()
        },
        sharedClockFailureHandler:
            @escaping SharedClockFailureHandler = { _, _ in
        },
        formatFailureHandler:
            @escaping FormatFailureHandler = { _, _ in
        }
    ) {
        self.policy = policy
        self.makeOutput = makeOutput
        self.startOutput = startOutput
        self.admit = admit
        self.disableTrack = disableTrack
        self.readinessSleep = readinessSleep
        self.retrySleep = retrySleep
        self.readinessSampleLimit = max(2, readinessSampleLimit)
        self.maximumStaleInboundMediaSamples = max(
            1,
            maximumStaleInboundMediaSamples
        )
        self.mediaFreshnessTimeoutNanoseconds = max(
            1,
            mediaFreshnessTimeoutNanoseconds
        )
        self.mediaFreshnessNow = mediaFreshnessNow
        self.mediaFreshnessDeadlineSleep =
            mediaFreshnessDeadlineSleep
        self.maximumAttemptCountPerKey = max(
            1,
            maximumAttemptCountPerKey
        )
        self.makeAttemptID = makeAttemptID
        self.sharedClockFailureHandler =
            sharedClockFailureHandler
        self.formatFailureHandler = formatFailureHandler
        phase = policy == .suppressedForLANCoexistence
            ? .suppressedForLANCoexistence
            : .waitingForMonitor
    }

    deinit {
        mediaFreshnessWatchdogTask?.cancel()
    }

    func beginMonitoring(
        isolation: isolated (any Actor)? = #isolation,
        epoch: UUID
    ) {
        guard !isStopped,
              policy == .enabled,
              activeMonitorEpoch != epoch else {
            return
        }

        preserveSharedClockUnsafePhaseUntilPeerOrPairChanges = false
        preserveFormatUnsafePhaseUntilPeerOrPairChanges = false
        supersedeEvidenceFrame()
        invalidateCurrentAttempt()
        activeMonitorEpoch = epoch
        monitorSnapshot = nil
        monitoringFailed = false
        disableCurrentTrack()
        phase = .waitingForMonitor
        redriveRequested = true
        retainEvidenceFailurePhase()
    }

    func monitoringDidFail(
        isolation: isolated (any Actor)? = #isolation
    ) {
        guard !isStopped, policy == .enabled else { return }
        preserveSharedClockUnsafePhaseUntilPeerOrPairChanges = false
        preserveFormatUnsafePhaseUntilPeerOrPairChanges = false
        supersedeEvidenceFrame()
        invalidateCurrentAttempt()
        monitoringFailed = true
        monitorSnapshot = nil
        disableCurrentTrack()
        lastFailureCategory = .monitoringFailed
        phase = .monitoringFailed
        redriveRequested = true
        retainEvidenceFailurePhase()
    }

    func updateDeviceSnapshot(
        isolation: isolated (any Actor)? = #isolation,
        _ snapshot: BlackHoleDeviceAvailabilitySnapshot
    ) async {
        guard !isStopped,
              policy == .enabled,
              snapshot.monitorEpoch == activeMonitorEpoch else {
            return
        }
        if let current = monitorSnapshot {
            guard snapshot.deviceGeneration
                    > current.deviceGeneration else {
                return
            }
        }

        preserveSharedClockUnsafePhaseUntilPeerOrPairChanges = false
        preserveFormatUnsafePhaseUntilPeerOrPairChanges = false
        supersedeEvidenceFrame()
        invalidateCurrentAttempt()
        monitorSnapshot = snapshot
        monitoringFailed = false
        if !snapshot.isAvailable {
            disableCurrentTrack()
        }
        redriveRequested = true
        await drive(isolation: isolation)
    }

    func replacePeer(
        isolation: isolated (any Actor)? = #isolation,
        peer: Peer,
        peerGeneration: UInt64
    ) {
        guard !isStopped else { return }
        if self.peer === peer,
           self.peerGeneration == peerGeneration {
            return
        }

        preserveSharedClockUnsafePhaseUntilPeerOrPairChanges = false
        preserveFormatUnsafePhaseUntilPeerOrPairChanges = false
        supersedeEvidenceFrame()
        invalidateCurrentAttempt()
        disableCurrentTrack()
        track = nil
        self.peer = peer
        self.peerGeneration = peerGeneration
        latestInboundMediaSample = nil
        transportAuthorized = false
        redriveRequested = true
        updateIneligiblePhase()
    }

    func clearPeer(
        isolation: isolated (any Actor)? = #isolation
    ) {
        guard !isStopped else { return }
        preserveSharedClockUnsafePhaseUntilPeerOrPairChanges = false
        preserveFormatUnsafePhaseUntilPeerOrPairChanges = false
        supersedeEvidenceFrame()
        invalidateCurrentAttempt()
        disableCurrentTrack()
        track = nil
        peer = nil
        latestInboundMediaSample = nil
        transportAuthorized = false
        redriveRequested = true
        updateIneligiblePhase()
    }

    func authorizeTransport(
        isolation: isolated (any Actor)? = #isolation,
        peer: Peer,
        peerGeneration: UInt64
    ) async {
        guard !isStopped else { return }
        guard policy == .enabled else {
            disableCurrentTrack()
            phase = .suppressedForLANCoexistence
            return
        }
        guard self.peer === peer,
              self.peerGeneration == peerGeneration else {
            return
        }
        guard !transportAuthorized else {
            return
        }

        supersedeEvidenceFrame()
        transportAuthorizationEpoch = Self.nextNonzero(
            transportAuthorizationEpoch
        )
        transportAuthorized = true
        redriveRequested = true
        await drive(isolation: isolation)
    }

    func invalidateTransport(
        isolation: isolated (any Actor)? = #isolation,
        preservingSharedClockUnsafeFailure: Bool = false,
        preservingFormatUnsafeFailure: Bool = false
    ) {
        guard !isStopped else { return }
        if preservingSharedClockUnsafeFailure,
           phase == .sharedClockUnsafe,
           lastFailureCategory == .sharedClockUnsafe {
            preserveSharedClockUnsafePhaseUntilPeerOrPairChanges = true
        }
        if preservingFormatUnsafeFailure,
           phase == .formatUnsafe,
           lastFailureCategory == .formatUnsafe {
            preserveFormatUnsafePhaseUntilPeerOrPairChanges = true
        }
        supersedeEvidenceFrame()
        transportAuthorized = false
        latestInboundMediaSample = nil
        invalidateCurrentAttempt()
        disableCurrentTrack()
        redriveRequested = true
        updateIneligiblePhase()
    }

    func installTrack(
        isolation: isolated (any Actor)? = #isolation,
        _ track: Track
    ) async {
        guard !isStopped else {
            disableTrack(track)
            return
        }

        if self.track === track {
            if policy == .suppressedForLANCoexistence
                || !transportAuthorized {
                disableTrack(track)
            }
            return
        }

        supersedeEvidenceFrame()
        invalidateCurrentAttempt()
        disableCurrentTrack()
        self.track = track
        trackGeneration = Self.nextNonzero(trackGeneration)
        latestInboundMediaSample = nil
        disableTrack(track)
        redriveRequested = true

        guard policy == .enabled else {
            phase = .suppressedForLANCoexistence
            return
        }
        await drive(isolation: isolation)
    }

    func clearTrack(
        isolation: isolated (any Actor)? = #isolation
    ) {
        guard !isStopped else { return }
        supersedeEvidenceFrame()
        invalidateCurrentAttempt()
        disableCurrentTrack()
        track = nil
        latestInboundMediaSample = nil
        redriveRequested = true
        updateIneligiblePhase()
    }

    func updateInboundMediaFreshness(
        isolation: isolated (any Actor)? = #isolation,
        peer sourcePeer: Peer,
        peerGeneration sourcePeerGeneration: UInt64,
        watermark: WorldwideIPhoneMicrophoneInboundMediaWatermark?
    ) async {
        let shouldDrive = processInboundMediaSample(
            isolation: isolation, peer: sourcePeer,
            peerGeneration: sourcePeerGeneration, watermark: watermark
        )
        if shouldDrive { await drive(isolation: isolation) }
    }

    private func processInboundMediaSample(
        isolation: isolated (any Actor)?,
        peer sourcePeer: Peer,
        peerGeneration sourcePeerGeneration: UInt64,
        watermark: WorldwideIPhoneMicrophoneInboundMediaWatermark?
    ) -> Bool {
        let original = currentAttempt
        guard beginEvidenceFrame() else { return false }
        defer { endEvidenceFrame() }
        let frame = activeEvidenceFrame!
        guard !isStopped,
              self.peer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              sourcePeerGeneration > 0 else {
            return false
        }

        inboundMediaSampleSequence = Self.nextNonzero(inboundMediaSampleSequence)
        let previousSample = latestInboundMediaSample
        let sample = InboundMediaSample(
            sequence: inboundMediaSampleSequence,
            peerGeneration: sourcePeerGeneration,
            trackGeneration: trackGeneration,
            watermark: watermark
        )
        latestInboundMediaSample = sample

        do {
            guard let attempt = currentAttempt,
                  candidateStillOwnsAttempt(attempt),
                  attempt.exactTrackAdmitted,
                  attempt.peer === sourcePeer,
                  attempt.key.peerGeneration == sourcePeerGeneration,
                  sample.trackGeneration == attempt.key.trackGeneration,
                  sample.sequence > attempt.lastInboundMediaSampleSequence else {
                return try reviveSourceMediaStalledCandidateIfFreshHeld(
                    previousSample: previousSample, sample: sample
                )
            }

            let progressWitness = try evidenceWitness(for: attempt)
            let progress = attempt.output.forwardingProgressSnapshot
            try requireEvidenceWitness(progressWitness)
            if progress.enqueueFailureCount > 0 {
                try failAttemptHeld(attempt, category: .runtimeEnqueueFailed, frame: frame)
            } else if !progress.queueRunning {
                try failAttemptHeld(attempt, category: .readinessFailed, frame: frame)
            } else {
                try promoteDeferredReadinessIfPossibleHeld(attempt: attempt, progress: progress)
                try requireEvidenceOwner(attempt)
                attempt.lastInboundMediaSampleSequence = sample.sequence
                let watermarkWitness = try evidenceWitness(for: attempt)
                let decision = try evidenceBridge.watermark(
                    previous: attempt.lastInboundMediaWatermark, current: sample.watermark
                )
                try requireEvidenceWitness(watermarkWitness)
                if decision.continuous {
                    attempt.lastInboundMediaWatermark = decision.retained
                }
                if decision.didAdvance {
                    attempt.inboundMediaAdvancementCount = Self.nextNonzero(attempt.inboundMediaAdvancementCount)
                    attempt.consecutiveStaleInboundMediaSamples = 0
                    attempt.requiresFreshInboundMediaAdvance = false
                    guard armMediaFreshnessWatchdog(for: attempt, isolation: isolation) else {
                        try requireEvidenceOwner(attempt)
                        throw EvidenceDecisionFailure.superseded
                    }
                } else if attempt.inboundMediaAdvancementCount > 0
                            || attempt.requiresFreshInboundMediaAdvance {
                    attempt.consecutiveStaleInboundMediaSamples += 1
                    if attempt.consecutiveStaleInboundMediaSamples >= maximumStaleInboundMediaSamples {
                        try failAttemptHeld(attempt, category: .sourceMediaStalled, frame: frame)
                    }
                }
                if currentAttempt === attempt {
                    try updateForwardingPhaseHeld(for: attempt)
                }
            }
        } catch {
            finishEvidenceFailure(error, original: original)
        }
        return redriveRequested && !evidenceBridgeFaulted
    }

    @discardableResult
    func handleRuntimeFailure(
        isolation: isolated (any Actor)? = #isolation,
        from output: any WorldwideIPhoneMicrophoneOutput,
        category:
            WorldwideIPhoneMicrophoneForwardingFailureCategory
    ) async -> Bool {
        guard !isStopped,
              let attempt = currentAttempt,
              attempt.output === output else {
            return false
        }

        failAttempt(attempt, category: category)
        if redriveRequested && !evidenceBridgeFaulted {
            await drive(isolation: isolation)
        }
        retainEvidenceFailurePhase()
        return true
    }

    func shutdown(
        isolation: isolated (any Actor)? = #isolation
    ) {
        guard !isStopped else { return }
        supersedeEvidenceFrame()
        isStopped = true
        preserveSharedClockUnsafePhaseUntilPeerOrPairChanges = false
        preserveFormatUnsafePhaseUntilPeerOrPairChanges = false
        transportAuthorized = false
        invalidateCurrentAttempt()
        disableCurrentTrack()
        track = nil
        peer = nil
        phase = .stopped
        redriveRequested = false
    }

    func snapshot(
        isolation: isolated (any Actor)? = #isolation
    ) -> WorldwideIPhoneMicrophoneForwardingHostSnapshot {
        let original = currentAttempt
        guard beginEvidenceFrame() else {
            return makeHostSnapshot(progress: .zero, inboundMediaFresh: false)
        }
        defer { endEvidenceFrame() }
        var progress = BlackHoleMicrophoneOutputProgressSnapshot.zero
        var fresh = false
        do {
            if let original {
                let witness = try evidenceWitness(for: original)
                progress = original.output.forwardingProgressSnapshot
                try requireEvidenceWitness(witness)
                try promoteDeferredReadinessIfPossibleHeld(attempt: original, progress: progress)
                try requireEvidenceOwner(original)
                if original.sinkContinuingHealthProven {
                    fresh = try sourceMediaIsFreshHeld(for: original)
                }
                try requireEvidenceOwner(original)
            }
        } catch {
            finishEvidenceFailure(error, original: original)
            progress = .zero
            fresh = false
        }
        return makeHostSnapshot(progress: progress, inboundMediaFresh: fresh)
    }

    private func makeHostSnapshot(
        progress: BlackHoleMicrophoneOutputProgressSnapshot,
        inboundMediaFresh: Bool
    ) -> WorldwideIPhoneMicrophoneForwardingHostSnapshot {
        return WorldwideIPhoneMicrophoneForwardingHostSnapshot(
            policy: policy,
            phase: phase,
            monitorEpoch: activeMonitorEpoch,
            deviceGeneration:
                monitorSnapshot?.deviceGeneration ?? 0,
            deviceUID:
                monitorSnapshot?.defaultInputEndpoint?.deviceUID,
            sinkDeviceUID:
                monitorSnapshot?.hiddenMirrorSinkEndpoint?.deviceUID,
            deviceAvailable:
                monitorSnapshot?.isAvailable ?? false,
            currentKey: currentAttempt?.key,
            lastAttemptedKey: lastAttemptedKey,
            peerGeneration: peerGeneration,
            transportAuthorizationEpoch:
                transportAuthorizationEpoch,
            transportAuthorized: transportAuthorized,
            trackGeneration: trackGeneration,
            currentAttemptID: currentAttempt?.id,
            lastAttemptID: lastAttemptID,
            attemptGeneration: attemptGeneration,
            exactTrackAdmitted:
                currentAttempt?.exactTrackAdmitted ?? false,
            queueRunning: progress.queueRunning,
            progress: progress,
            inboundMediaSampleSequence:
                currentAttempt?.lastInboundMediaSampleSequence
                    ?? latestInboundMediaSample?.sequence ?? 0,
            inboundMediaAdvancementCount:
                currentAttempt?.inboundMediaAdvancementCount ?? 0,
            consecutiveStaleInboundMediaSamples:
                currentAttempt?.consecutiveStaleInboundMediaSamples
                    ?? 0,
            inboundMediaFresh: inboundMediaFresh,
            lastFailureCategory: lastFailureCategory
        )
    }

    private func drive(
        isolation: isolated (any Actor)?
    ) async {
        guard !isStopped else { return }
        guard !evidenceBridgeFaulted else { retainEvidenceFailurePhase(); return }
        if isDriving {
            redriveRequested = true
            return
        }

        isDriving = true
        defer { isDriving = false }

        while !isStopped {
            redriveRequested = false
            await driveOne(isolation: isolation)
            if redriveRequested || hasUnattemptedEligibleCandidate {
                continue
            }
            break
        }

        if currentAttempt == nil,
           currentCandidate() == nil {
            updateIneligiblePhase()
        }
    }

    private func driveOne(
        isolation: isolated (any Actor)?
    ) async {
        if let attempt = currentAttempt {
            guard candidateStillOwnsAttempt(attempt) else {
                finishSupersededAttempt(attempt)
                return
            }
            return
        }

        guard let candidate = currentCandidate() else {
            updateIneligiblePhase()
            return
        }
        do {
            guard try candidateMayBeAttempted(candidate) else { return }
        } catch {
            finishEvidenceFailure(error, original: nil)
            return
        }

        if attemptHistory[candidate.key] != nil {
            do {
                try await retrySleep()
            } catch {
                guard candidateStillCurrent(candidate) else {
                    redriveRequested = true
                    return
                }
                do {
                    try markRetryExhausted(candidate)
                } catch {
                    finishEvidenceFailure(error, original: nil)
                }
                return
            }

            guard candidateStillCurrent(candidate) else {
                redriveRequested = true
                return
            }
        }

        do {
            try rememberAttempted(candidate)
        } catch {
            finishEvidenceFailure(error, original: nil)
            return
        }
        attemptGeneration = Self.nextNonzero(attemptGeneration)
        let attemptID = makeAttemptID()
        lastAttemptID = attemptID

        guard let output = makeOutput(
            candidate.peer,
            candidate.sinkEndpoint
        ) else {
            failWithoutOutput(
                candidate: candidate,
                category: .outputUnavailable
            )
            return
        }

        let attempt = Attempt(
            id: attemptID,
            candidate: candidate,
            output: output,
            baselineInboundMediaSample:
                latestInboundMediaSample.map { sample in
                    sample.peerGeneration
                            == candidate.key.peerGeneration
                        && sample.trackGeneration
                            == candidate.key.trackGeneration
                        ? sample
                        : nil
                } ?? nil,
            // Every admitted receiver must prove one fresh RTP advance. Without this initial
            // watchdog, a newly negotiated track that never produces its first packet can leave
            // the virtual microphone indefinitely visible but silent in `awaitingFrames`.
            requiresFreshInboundMediaAdvance: true
        )
        currentAttempt = attempt
        phase = .starting

        do {
            try await startOutput(output)
        } catch {
            guard candidateStillOwnsAttempt(attempt) else {
                finishSupersededAttempt(attempt)
                return
            }
            if let outputError =
                    error as? BlackHoleMicrophoneOutputError,
               case .formatUnsafe(let rejection) =
                    outputError {
                failAttempt(
                    attempt,
                    category: .formatUnsafe,
                    allowRetry: false
                )
                await formatFailureHandler(
                    attempt.key,
                    rejection
                )
            } else if let outputError =
                        error as? BlackHoleMicrophoneOutputError,
                      case .sharedClockUnsafe(let rejection) =
                        outputError {
                failAttempt(
                    attempt,
                    category: .sharedClockUnsafe,
                    allowRetry: false
                )
                await sharedClockFailureHandler(
                    attempt.key,
                    rejection
                )
            } else {
                failAttempt(
                    attempt,
                    category: .startFailed,
                    allowRetry: !Task.isCancelled
                )
            }
            return
        }

        guard candidateStillOwnsAttempt(attempt) else {
            finishSupersededAttempt(attempt)
            return
        }
        // A replacement output reaches this point only after its queue has
        // committed the authoritative startup format and shared-clock proof.
        // The prior epoch rejection must not leak back into status if this
        // newly authorized route is later invalidated for another reason.
        preserveSharedClockUnsafePhaseUntilPeerOrPairChanges = false

        phase = .admittingTrack
        do {
            try await admit(attempt.peer, attempt.track)
        } catch {
            guard candidateStillOwnsAttempt(attempt) else {
                finishSupersededAttempt(attempt)
                return
            }
            failAttempt(attempt, category: .admissionFailed)
            return
        }

        guard candidateStillOwnsAttempt(attempt) else {
            finishSupersededAttempt(attempt)
            return
        }
        attempt.exactTrackAdmitted = true
        let admissionFloor = latestInboundMediaSample.flatMap { sample in
            sample.peerGeneration == attempt.key.peerGeneration
                && sample.trackGeneration == attempt.key.trackGeneration
                ? sample
                : nil
        }
        attempt.lastInboundMediaWatermark = admissionFloor?.watermark
        attempt.lastInboundMediaSampleSequence = admissionFloor?.sequence ?? 0
        attempt.inboundMediaAdvancementCount = 0
        attempt.consecutiveStaleInboundMediaSamples = 0
        phase = .checkingReadiness
        guard armMediaFreshnessWatchdog(
            for: attempt,
            isolation: isolation
        ) else { return }
        await awaitReadiness(
            for: attempt,
            isolation: isolation
        )
    }

    private enum ReadinessSample {
        case finished
        case next(BlackHoleMicrophoneOutputProgressSnapshot)
    }

    private func sampleReadiness(
        for attempt: Attempt,
        previousPollingProgress: BlackHoleMicrophoneOutputProgressSnapshot?
    ) -> ReadinessSample {
        guard beginEvidenceFrame() else { return .finished }
        defer { endEvidenceFrame() }
        let frame = activeEvidenceFrame!
        do {
            try requireEvidenceOwner(attempt)
            if attempt.sinkContinuingHealthProven {
                try updateForwardingPhaseHeld(for: attempt)
                return .finished
            }
            let witness = try evidenceWitness(for: attempt)
            let progress = attempt.output.forwardingProgressSnapshot
            try requireEvidenceWitness(witness)
            if progress.enqueueFailureCount > 0 {
                try failAttemptHeld(attempt, category: .runtimeEnqueueFailed,
                                    allowRetry: !Task.isCancelled, frame: frame)
                return .finished
            }
            guard progress.queueRunning else {
                try failAttemptHeld(attempt, category: .readinessFailed,
                                    allowRetry: !Task.isCancelled, frame: frame)
                return .finished
            }
            if let previousPollingProgress,
               progress.postStartCallbackCount > previousPollingProgress.postStartCallbackCount,
               progress.successfulFrameCount == previousPollingProgress.successfulFrameCount {
                attempt.deferredReadyProgress = nil
                phase = .awaitingFrames
                return .finished
            }

            let decision = try evidenceBridge.readiness(
                current: progress, previous: attempt.deferredReadyProgress
            )
            try requireEvidenceWitness(witness)
            if decision.ready {
                if decision.continuing {
                    attempt.sinkContinuingHealthProven = true
                    attempt.deferredReadyProgress = progress
                    try updateForwardingPhaseHeld(for: attempt)
                    return .finished
                }
                attempt.deferredReadyProgress = progress
                phase = .forwardingReady
            }
            return .next(progress)
        } catch {
            finishEvidenceFailure(error, original: attempt)
            return .finished
        }
    }

    private func awaitReadiness(
        for attempt: Attempt,
        isolation: isolated (any Actor)?
    ) async {
        var previousProgress: BlackHoleMicrophoneOutputProgressSnapshot?
        for sampleIndex in 0..<readinessSampleLimit {
            guard !evidenceBridgeFaulted else { return }
            guard candidateStillOwnsAttempt(attempt) else {
                finishSupersededAttempt(attempt)
                return
            }
            switch sampleReadiness(for: attempt, previousPollingProgress: previousProgress) {
            case .finished: return
            case .next(let progress): previousProgress = progress
            }
            guard sampleIndex + 1 < readinessSampleLimit else { break }
            do {
                try await readinessSleep()
            } catch {
                guard !evidenceBridgeFaulted else { return }
                guard candidateStillOwnsAttempt(attempt) else {
                    finishSupersededAttempt(attempt)
                    return
                }
                failAttempt(attempt, category: .readinessFailed, allowRetry: !Task.isCancelled)
                return
            }
        }
        guard !evidenceBridgeFaulted else { return }
        guard candidateStillOwnsAttempt(attempt) else {
            finishSupersededAttempt(attempt)
            return
        }
        failAttempt(attempt, category: .readinessFailed, allowRetry: !Task.isCancelled)
    }

    private var hasUnattemptedEligibleCandidate: Bool {
        guard currentAttempt == nil,
              let candidate = currentCandidate() else {
            return false
        }
        do {
            return try candidateMayBeAttempted(candidate)
        } catch {
            finishEvidenceFailure(error, original: nil)
            return false
        }
    }

    private func currentCandidate() -> Candidate? {
        guard !isStopped, !evidenceBridgeFaulted,
              policy == .enabled,
              !monitoringFailed,
              let activeMonitorEpoch,
              let monitorSnapshot,
              monitorSnapshot.monitorEpoch == activeMonitorEpoch,
              monitorSnapshot.isAvailable,
              monitorSnapshot.deviceGeneration > 0,
              let defaultInputDeviceUID = monitorSnapshot
                .defaultInputEndpoint?.deviceUID,
              !defaultInputDeviceUID.isEmpty,
              let defaultInputEndpoint = monitorSnapshot
                .defaultInputEndpoint,
              defaultInputEndpoint.deviceUID
                == defaultInputDeviceUID,
              let sinkEndpoint = monitorSnapshot
                .hiddenMirrorSinkEndpoint,
              !sinkEndpoint.deviceUID.isEmpty,
              sinkEndpoint.deviceUID != defaultInputDeviceUID,
              sinkEndpoint.deviceID
                != defaultInputEndpoint.deviceID,
              let peer,
              peerGeneration > 0,
              transportAuthorized,
              transportAuthorizationEpoch > 0,
              let track,
              trackGeneration > 0 else {
            return nil
        }

        return Candidate(
            key: WorldwideIPhoneMicrophoneForwardingKey(
                monitorEpoch: activeMonitorEpoch,
                deviceGeneration:
                    monitorSnapshot.deviceGeneration,
                peerGeneration: peerGeneration,
                transportAuthorizationEpoch:
                    transportAuthorizationEpoch,
                trackGeneration: trackGeneration
            ),
            peer: peer,
            track: track,
            sinkEndpoint: sinkEndpoint
        )
    }

    private func candidateStillOwnsAttempt(
        _ attempt: Attempt
    ) -> Bool {
        guard currentAttempt === attempt,
              let candidate = currentCandidate(),
              candidate.key == attempt.key,
              candidate.peer === attempt.peer,
              candidate.track === attempt.track,
              candidate.sinkEndpoint == attempt.sinkEndpoint else {
            return false
        }
        return true
    }

    private func candidateStillCurrent(
        _ candidate: Candidate
    ) -> Bool {
        guard let current = currentCandidate(),
              current.key == candidate.key,
              current.peer === candidate.peer,
              current.track === candidate.track,
              current.sinkEndpoint == candidate.sinkEndpoint else {
            return false
        }
        return true
    }

    private func promoteDeferredReadinessIfPossibleHeld(
        attempt: Attempt,
        progress: BlackHoleMicrophoneOutputProgressSnapshot
    ) throws {
        try requireEvidenceOwner(attempt)
        guard attempt.exactTrackAdmitted else { return }
        if attempt.sinkContinuingHealthProven {
            try updateForwardingPhaseHeld(for: attempt)
            return
        }
        guard phase == .checkingReadiness || phase == .awaitingFrames || phase == .forwardingReady else {
            return
        }
        let witness = try evidenceWitness(for: attempt)
        let decision = try evidenceBridge.readiness(current: progress, previous: attempt.deferredReadyProgress)
        try requireEvidenceWitness(witness)
        guard decision.ready else {
            attempt.deferredReadyProgress = nil
            phase = .awaitingFrames
            return
        }
        if decision.continuing {
            attempt.sinkContinuingHealthProven = true
            attempt.deferredReadyProgress = progress
            try updateForwardingPhaseHeld(for: attempt)
            return
        }
        attempt.deferredReadyProgress = progress
        phase = .forwardingReady
    }

    private func updateForwardingPhaseHeld(for attempt: Attempt) throws {
        try requireEvidenceOwner(attempt)
        guard attempt.exactTrackAdmitted else { return }
        if attempt.sinkContinuingHealthProven {
            let fresh = try sourceMediaIsFreshHeld(for: attempt)
            try requireEvidenceOwner(attempt)
            phase = fresh ? .forwardingHealthy : .awaitingFrames
        } else if attempt.deferredReadyProgress != nil {
            phase = .forwardingReady
        } else {
            phase = .awaitingFrames
        }
    }

    private func sourceMediaIsFreshHeld(for attempt: Attempt) throws -> Bool {
        let witness = try evidenceWitness(for: attempt)
        let plan = try evidenceBridge.planFreshness(
            advancementCount: witness.history.advancementCount,
            consecutiveStaleSamples: witness.history.staleCount,
            maximumStaleSamples: maximumStaleInboundMediaSamples,
            deadlineNanoseconds: witness.history.deadline
        )
        try requireEvidenceWitness(witness)
        switch plan {
        case .decided(let fresh):
            return fresh
        case .needsNow(let snapshot):
            // No mutable adapter borrow is held across this original clock cut.
            try requireEvidenceWitness(witness)
            let now = mediaFreshnessNow()
            try requireEvidenceWitness(witness)
            let fresh = try evidenceBridge.finishFreshness(snapshot, now: now)
            try requireEvidenceWitness(witness)
            return fresh
        }
    }

    @discardableResult
    private func armMediaFreshnessWatchdog(
        for attempt: Attempt,
        isolation: isolated (any Actor)?
    ) -> Bool {
        precondition(
            isolation != nil,
            "The forwarding driver watchdog requires actor ownership."
        )
        // The initial admission arm is outside an evidence read. Subsequent
        // advancement arms reuse their already-held, synchronous frame.
        let ownsFrame = !evidenceBusy
        if ownsFrame && !beginEvidenceFrame() { return false }
        defer { if ownsFrame { endEvidenceFrame() } }
        guard candidateStillOwnsAttempt(attempt),
              attempt.exactTrackAdmitted,
              !evidenceBridgeFaulted, !evidencePoisoned, !evidenceSuperseded else {
            return false
        }

        cancelMediaFreshnessWatchdog()
        attempt.mediaFreshnessWatchdogGeneration =
            Self.nextNonzero(
                attempt.mediaFreshnessWatchdogGeneration
            )
        let history = EvidenceHistory(attempt)
        let latestSample = latestInboundMediaSample
        let nowValue = mediaFreshnessNow()
        guard candidateStillOwnsAttempt(attempt), attempt.exactTrackAdmitted,
              !evidenceBridgeFaulted, !evidencePoisoned, !evidenceSuperseded,
              EvidenceHistory(attempt) == history,
              latestInboundMediaSample == latestSample else {
            if ownsFrame {
                let failure: EvidenceDecisionFailure =
                    evidencePoisoned || evidenceBridgeFaulted ? .poisoned : .superseded
                finishEvidenceFailure(failure, original: attempt)
            }
            return false
        }
        let deadline = Self.addingClamped(nowValue, mediaFreshnessTimeoutNanoseconds)
        attempt.mediaFreshnessDeadlineNanoseconds = deadline

        let attemptID = attempt.id
        let key = attempt.key
        let peerIdentity = ObjectIdentifier(attempt.peer)
        let trackIdentity = ObjectIdentifier(attempt.track)
        let outputIdentity = ObjectIdentifier(attempt.output)
        let watchdogGeneration =
            attempt.mediaFreshnessWatchdogGeneration
        let deadlineSleep = mediaFreshnessDeadlineSleep
        let now = mediaFreshnessNow

        mediaFreshnessWatchdogTask = Task { [weak self] in
            do {
                while !Task.isCancelled, now() < deadline {
                    try await deadlineSleep(deadline)
                }
            } catch {
                return
            }
            guard !Task.isCancelled, let self else {
                return
            }
            await self.mediaFreshnessWatchdogDidReachDeadline(
                isolation: isolation,
                attemptID: attemptID,
                key: key,
                peerIdentity: peerIdentity,
                trackIdentity: trackIdentity,
                outputIdentity: outputIdentity,
                watchdogGeneration: watchdogGeneration,
                deadlineNanoseconds: deadline
            )
        }
        return true
    }

    private func mediaFreshnessWatchdogDidReachDeadline(
        isolation: isolated (any Actor)?,
        attemptID: UUID,
        key: WorldwideIPhoneMicrophoneForwardingKey,
        peerIdentity: ObjectIdentifier,
        trackIdentity: ObjectIdentifier,
        outputIdentity: ObjectIdentifier,
        watchdogGeneration: UInt64,
        deadlineNanoseconds: UInt64
    ) async {
        guard !isStopped,
              mediaFreshnessNow() >= deadlineNanoseconds,
              let attempt = currentAttempt,
              candidateStillOwnsAttempt(attempt),
              attempt.exactTrackAdmitted,
              attempt.id == attemptID,
              attempt.key == key,
              ObjectIdentifier(attempt.peer) == peerIdentity,
              ObjectIdentifier(attempt.track) == trackIdentity,
              ObjectIdentifier(attempt.output) == outputIdentity,
              attempt.mediaFreshnessWatchdogGeneration
                == watchdogGeneration,
              attempt.mediaFreshnessDeadlineNanoseconds
                == deadlineNanoseconds else {
            return
        }

        // Clear the task before failing so the deadline task does not cancel
        // itself and poison the bounded retry sleep that follows.
        mediaFreshnessWatchdogTask = nil
        attempt.mediaFreshnessDeadlineNanoseconds = nil
        failAttempt(attempt, category: .sourceMediaStalled)
        if redriveRequested {
            await drive(isolation: isolation)
        }
    }

    private func cancelMediaFreshnessWatchdog() {
        mediaFreshnessWatchdogTask?.cancel()
        mediaFreshnessWatchdogTask = nil
    }

    private func invalidateCurrentAttempt() {
        guard let attempt = currentAttempt else { return }
        cancelMediaFreshnessWatchdog()
        currentAttempt = nil
        if track === attempt.track {
            disableTrack(attempt.track)
        }
        attempt.output.stop()
    }

    private func finishSupersededAttempt(
        _ attempt: Attempt
    ) {
        if currentAttempt === attempt {
            cancelMediaFreshnessWatchdog()
            currentAttempt = nil
        }

        let replacementOwnsSameTrack =
            currentAttempt.map {
                $0.track === attempt.track
            } ?? false
        if !replacementOwnsSameTrack {
            disableTrack(attempt.track)
        }
        attempt.output.stop()
        redriveRequested = true
    }

    private func failAttempt(
        _ attempt: Attempt,
        category: WorldwideIPhoneMicrophoneForwardingFailureCategory,
        allowRetry: Bool = true
    ) {
        guard currentAttempt === attempt else {
            finishSupersededAttempt(attempt)
            retainEvidenceFailurePhase()
            return
        }
        guard beginEvidenceFrame() else {
            if retireAttemptNative(attempt) {
                exhaustFaultedRetryBookkeeping(attempt.key)
            }
            retainEvidenceFailurePhase()
            return
        }
        defer { endEvidenceFrame() }
        do {
            try failAttemptHeld(attempt, category: category,
                                allowRetry: allowRetry, frame: activeEvidenceFrame!)
        } catch {
            finishEvidenceFailure(error, original: attempt)
        }
    }

    private func failAttemptHeld(
        _ attempt: Attempt,
        category: WorldwideIPhoneMicrophoneForwardingFailureCategory,
        allowRetry: Bool = true,
        frame: EvidenceFrame
    ) throws {
        try requireRetryFrame(frame)
        guard retireAttemptNative(attempt) else { return }
        if isStopped {
            phase = .stopped
            redriveRequested = false
            return
        }
        let candidate = candidateForRetiredAttempt(attempt)
        try requireRetryCandidate(candidate, frame: frame)
        lastFailureCategory = category
        phase = Self.phase(for: category)
        // Preserve the native short circuit: no operation-three call on false.
        if allowRetry {
            redriveRequested = try markRetryableHeld(candidate, category: category, frame: frame)
        } else {
            redriveRequested = false
        }
    }

    @discardableResult
    private func retireAttemptNative(_ attempt: Attempt) -> Bool {
        guard currentAttempt === attempt else {
            finishSupersededAttempt(attempt)
            return false
        }
        activeEvidenceFrame?.retiredAttempt = attempt
        activeEvidenceFrame?.retiredRetryKey = attempt.key
        cancelMediaFreshnessWatchdog()
        currentAttempt = nil
        if track === attempt.track {
            disableTrack(attempt.track)
        }
        attempt.output.stop()
        return true
    }

    private func failWithoutOutput(
        candidate: Candidate,
        category: WorldwideIPhoneMicrophoneForwardingFailureCategory
    ) {
        guard candidateStillCurrent(candidate) else {
            redriveRequested = true
            retainEvidenceFailurePhase()
            return
        }
        guard beginEvidenceFrame() else {
            disableTrack(candidate.track)
            retainEvidenceFailurePhase()
            return
        }
        defer { endEvidenceFrame() }
        let frame = activeEvidenceFrame!
        disableTrack(candidate.track)
        if isStopped {
            phase = .stopped
            redriveRequested = false
            return
        }
        do {
            try requireRetryCandidate(candidate, frame: frame)
            frame.retiredRetryKey = candidate.key
            lastFailureCategory = category
            phase = Self.phase(for: category)
            redriveRequested = try markRetryableHeld(candidate, category: category, frame: frame)
        } catch {
            finishEvidenceFailure(error, original: nil)
        }
    }

    private func candidateForRetiredAttempt(_ attempt: Attempt) -> Candidate {
        Candidate(key: attempt.key, peer: attempt.peer, track: attempt.track,
                  sinkEndpoint: attempt.sinkEndpoint)
    }

    private struct RetryWitness {
        let frame: EvidenceFrame?
        let key: WorldwideIPhoneMicrophoneForwardingKey
        let row: AttemptHistory?
        let monitorEpoch: UUID?
        let monitorSnapshot: BlackHoleDeviceAvailabilitySnapshot?
        let monitoringFailed: Bool
        let peer: Peer?
        let peerGeneration: UInt64
        let transportEpoch: UInt64
        let transportAuthorized: Bool
        let track: Track?
        let trackGeneration: UInt64
        let attempt: Attempt?
        let attemptGeneration: UInt64
        let lastAttemptID: UUID?
        let lastAttemptedKey: WorldwideIPhoneMicrophoneForwardingKey?
        let order: [WorldwideIPhoneMicrophoneForwardingKey]
        let latestSample: InboundMediaSample?
        let phase: WorldwideIPhoneMicrophoneForwardingPhase
        let failure: WorldwideIPhoneMicrophoneForwardingFailureCategory?
        let redrive: Bool
        let stopped: Bool
    }

    private func retryWitness(_ key: WorldwideIPhoneMicrophoneForwardingKey) -> RetryWitness {
        RetryWitness(frame: activeEvidenceFrame, key: key, row: attemptHistory[key],
            monitorEpoch: activeMonitorEpoch, monitorSnapshot: monitorSnapshot,
            monitoringFailed: monitoringFailed, peer: peer, peerGeneration: peerGeneration,
            transportEpoch: transportAuthorizationEpoch, transportAuthorized: transportAuthorized,
            track: track, trackGeneration: trackGeneration, attempt: currentAttempt,
            attemptGeneration: attemptGeneration, lastAttemptID: lastAttemptID,
            lastAttemptedKey: lastAttemptedKey, order: attemptedKeyOrder,
            latestSample: latestInboundMediaSample, phase: phase, failure: lastFailureCategory,
            redrive: redriveRequested, stopped: isStopped)
    }

    private func retryWitnessStillMatches(_ witness: RetryWitness) -> Bool {
        activeEvidenceFrame === witness.frame
            && attemptHistory[witness.key] == witness.row
            && activeMonitorEpoch == witness.monitorEpoch
            && monitorSnapshot == witness.monitorSnapshot
            && monitoringFailed == witness.monitoringFailed
            && peer === witness.peer && peerGeneration == witness.peerGeneration
            && transportAuthorizationEpoch == witness.transportEpoch
            && transportAuthorized == witness.transportAuthorized
            && track === witness.track && trackGeneration == witness.trackGeneration
            && currentAttempt === witness.attempt
            && attemptGeneration == witness.attemptGeneration
            && lastAttemptID == witness.lastAttemptID
            && lastAttemptedKey == witness.lastAttemptedKey
            && attemptedKeyOrder == witness.order
            && latestInboundMediaSample == witness.latestSample
            && phase == witness.phase && lastFailureCategory == witness.failure
            && redriveRequested == witness.redrive && isStopped == witness.stopped
    }

    private func requireRetryFrame(_ frame: EvidenceFrame) throws {
        precondition(evidenceBusy && activeEvidenceFrame === frame)
        guard !evidencePoisoned, !evidenceBridgeFaulted else {
            throw EvidenceDecisionFailure.poisoned
        }
        guard !evidenceSuperseded else { throw EvidenceDecisionFailure.superseded }
    }

    private func requireRetryCandidate(_ candidate: Candidate, frame: EvidenceFrame) throws {
        try requireRetryFrame(frame)
        guard currentAttempt == nil, candidateStillCurrent(candidate) else {
            throw EvidenceDecisionFailure.superseded
        }
    }

    private func evaluateRetryHeld(
        _ candidate: Candidate,
        operation: BelugaRustMicrophoneForwardingRetry.Operation,
        category: WorldwideIPhoneMicrophoneForwardingFailureCategory? = nil,
        frame: EvidenceFrame
    ) throws -> BelugaRustMicrophoneForwardingRetry.Evaluation {
        try requireRetryCandidate(candidate, frame: frame)
        let witness = retryWitness(candidate.key)
        let row = witness.row.map {
            BelugaRustMicrophoneForwardingRetry.Row(count: $0.count, mayRetry: $0.mayRetry)
        }
        let result: BelugaRustMicrophoneForwardingRetry.Evaluation
        #if DEBUG
        let mutation = retryPostResultMutation
        if let mutation {
            result = try BelugaRustMicrophoneForwardingRetry.evaluateForTesting(
                maximumAttemptCount: maximumAttemptCountPerKey, before: row, operation: operation,
                failureCategory: category.map(Self.retryFailureCategory), bridgeFaulted: false,
                postResultMutation: mutation)
        } else {
            result = try BelugaRustMicrophoneForwardingRetry.evaluate(
                maximumAttemptCount: maximumAttemptCountPerKey, before: row, operation: operation,
                failureCategory: category.map(Self.retryFailureCategory), bridgeFaulted: false)
        }
        #else
        result = try BelugaRustMicrophoneForwardingRetry.evaluate(
            maximumAttemptCount: maximumAttemptCountPerKey, before: row, operation: operation,
            failureCategory: category.map(Self.retryFailureCategory), bridgeFaulted: false)
        #endif
        try requireRetryCandidate(candidate, frame: frame)
        guard retryWitnessStillMatches(witness) else {
            throw EvidenceDecisionFailure.superseded
        }
        return result
    }

    private func rememberAttempted(_ candidate: Candidate) throws {
        guard beginEvidenceFrame() else { throw EvidenceDecisionFailure.poisoned }
        defer { endEvidenceFrame() }
        let frame = activeEvidenceFrame!
        let result = try evaluateRetryHeld(candidate, operation: .recordAttempt, frame: frame)
        guard let row = result.row else { throw BelugaRustMicrophoneForwardingRetry.Failure.refused }
        // All observable work has ended; retain the original native FIFO/write cuts.
        attemptHistory[candidate.key] = AttemptHistory(count: row.count, mayRetry: row.mayRetry)
        if result.originalRow == nil {
            attemptedKeyOrder.append(candidate.key)
        }
        let maximumRetainedKeys = 256
        while attemptedKeyOrder.count > maximumRetainedKeys {
            let removed = attemptedKeyOrder.removeFirst()
            attemptHistory.removeValue(forKey: removed)
        }
        lastAttemptedKey = candidate.key
    }

    private func candidateMayBeAttempted(_ candidate: Candidate) throws -> Bool {
        guard beginEvidenceFrame() else { throw EvidenceDecisionFailure.poisoned }
        defer { endEvidenceFrame() }
        return try evaluateRetryHeld(candidate, operation: .eligible,
                                     frame: activeEvidenceFrame!).decision
    }

    private func markRetryableHeld(
        _ candidate: Candidate,
        category: WorldwideIPhoneMicrophoneForwardingFailureCategory,
        frame: EvidenceFrame
    ) throws -> Bool {
        let result = try evaluateRetryHeld(candidate, operation: .retryFailure,
                                           category: category, frame: frame)
        if let row = result.row {
            attemptHistory[candidate.key] = AttemptHistory(count: row.count, mayRetry: row.mayRetry)
        }
        return result.decision
    }

    private func markRetryExhausted(_ candidate: Candidate) throws {
        guard beginEvidenceFrame() else { throw EvidenceDecisionFailure.poisoned }
        defer { endEvidenceFrame() }
        let result = try evaluateRetryHeld(candidate, operation: .exhaust, frame: activeEvidenceFrame!)
        if let row = result.row {
            attemptHistory[candidate.key] = AttemptHistory(count: row.count, mayRetry: row.mayRetry)
        }
        applyRetryRedrive(result.redrive)
    }

    private func exhaustFaultedRetryBookkeeping(_ key: WorldwideIPhoneMicrophoneForwardingKey) {
        precondition(evidenceBridgeFaulted)
        if let frame = activeEvidenceFrame {
            guard frame.retiredRetryKey == key, !frame.faultExhaustConsumed else { return }
            frame.faultExhaustConsumed = true
        }
        // Capture AFTER native cleanup. This fixed C/validator call has no hooks,
        // clocks, borrowed evidence bridge, healthy vote or recursive error handler.
        let witness = retryWitness(key)
        #if DEBUG
        faultExhaustCallsForTesting += 1
        #endif
        do {
            let result = try BelugaRustMicrophoneForwardingRetry.exhaustBookkeeping(
                maximumAttemptCount: maximumAttemptCountPerKey,
                before: witness.row.map {
                    BelugaRustMicrophoneForwardingRetry.Row(count: $0.count, mayRetry: $0.mayRetry)
                })
            guard evidenceBridgeFaulted, retryWitnessStillMatches(witness) else { return }
            if let row = result.row {
                attemptHistory[key] = AttemptHistory(count: row.count, mayRetry: row.mayRetry)
            }
            applyRetryRedrive(result.redrive)
        } catch {
            // Original output is already closed. Refused bookkeeping stays
            // untouched and cannot reopen a faulted driver or recurse.
        }
    }

    private func applyRetryRedrive(_ action: BelugaRustMicrophoneForwardingRetry.RedriveAction) {
        switch action {
        case .retain: break
        case .clear: redriveRequested = false
        case .request: redriveRequested = true
        }
    }

    private static func retryFailureCategory(
        _ category: WorldwideIPhoneMicrophoneForwardingFailureCategory
    ) -> BelugaRustMicrophoneForwardingRetry.FailureCategory {
        switch category {
        case .monitoringFailed: .monitoringFailed
        case .outputUnavailable: .outputUnavailable
        case .startFailed: .startFailed
        case .admissionFailed: .admissionFailed
        case .readinessFailed: .readinessFailed
        case .sourceMediaStalled: .sourceMediaStalled
        case .formatUnsafe: .formatUnsafe
        case .sharedClockUnsafe: .sharedClockUnsafe
        case .runtimeEnqueueFailed: .runtimeEnqueueFailed
        case .runtimeProgressStalled: .runtimeProgressStalled
        case .evidenceBridgeRefused: .evidenceBridgeRefused
        }
    }

    private func reviveSourceMediaStalledCandidateIfFreshHeld(
        previousSample: InboundMediaSample?,
        sample: InboundMediaSample
    ) throws -> Bool {
        precondition(evidenceBusy)
        guard !evidenceBridgeFaulted, !evidencePoisoned, !evidenceSuperseded,
              currentAttempt == nil,
              lastFailureCategory == .sourceMediaStalled,
              let candidate = currentCandidate(),
              candidate.key.peerGeneration == sample.peerGeneration,
              candidate.key.trackGeneration == sample.trackGeneration,
              let previousSample,
              previousSample.peerGeneration == sample.peerGeneration,
              previousSample.trackGeneration == sample.trackGeneration,
              sample.sequence > previousSample.sequence else {
            return false
        }
        let decision = try evidenceBridge.watermark(
            previous: previousSample.watermark, current: sample.watermark
        )
        guard !evidenceBridgeFaulted, !evidencePoisoned else {
            throw EvidenceDecisionFailure.poisoned
        }
        guard !evidenceSuperseded, currentAttempt == nil,
              candidateStillCurrent(candidate), latestInboundMediaSample == sample,
              lastFailureCategory == .sourceMediaStalled else {
            throw EvidenceDecisionFailure.superseded
        }
        guard decision.didAdvance else { return false }
        attemptHistory.removeValue(forKey: candidate.key)
        attemptedKeyOrder.removeAll { $0 == candidate.key }
        redriveRequested = true
        return true
    }

    private func disableCurrentTrack() {
        if let track {
            disableTrack(track)
        }
    }

    private func updateIneligiblePhase() {
        guard currentAttempt == nil else { return }
        if isStopped {
            phase = .stopped
            return
        }
        if evidenceBridgeFaulted {
            retainEvidenceFailurePhase()
            return
        }
        if policy == .suppressedForLANCoexistence {
            phase = .suppressedForLANCoexistence
            return
        }
        if monitoringFailed {
            phase = .monitoringFailed
            return
        }
        if preserveSharedClockUnsafePhaseUntilPeerOrPairChanges {
            phase = .sharedClockUnsafe
            return
        }
        if preserveFormatUnsafePhaseUntilPeerOrPairChanges {
            phase = .formatUnsafe
            return
        }
        guard activeMonitorEpoch != nil,
              let monitorSnapshot else {
            phase = .waitingForMonitor
            return
        }
        guard monitorSnapshot.isAvailable,
              monitorSnapshot.defaultInputEndpoint != nil,
              monitorSnapshot.hiddenMirrorSinkEndpoint != nil else {
            phase = .waitingForDevice
            return
        }
        guard peer != nil else {
            phase = .waitingForPeer
            return
        }
        guard transportAuthorized else {
            phase = .waitingForTransport
            return
        }
        guard track != nil else {
            phase = .waitingForTrack
            return
        }

        if let candidate = currentCandidate(),
           attemptHistory[candidate.key] != nil {
            do {
                if try candidateMayBeAttempted(candidate) == false {
                    // Preserve the terminal result for this already-attempted key.
                    return
                }
            } catch {
                finishEvidenceFailure(error, original: nil)
                return
            }
        }
        phase = .waitingForTrack
    }

    private static func phase(
        for category:
            WorldwideIPhoneMicrophoneForwardingFailureCategory
    ) -> WorldwideIPhoneMicrophoneForwardingPhase {
        switch category {
        case .monitoringFailed:
            .monitoringFailed
        case .outputUnavailable:
            .outputUnavailable
        case .startFailed:
            .startFailed
        case .admissionFailed:
            .admissionFailed
        case .readinessFailed:
            .readinessFailed
        case .sourceMediaStalled:
            .sourceMediaStalled
        case .formatUnsafe:
            .formatUnsafe
        case .sharedClockUnsafe:
            .sharedClockUnsafe
        case .runtimeEnqueueFailed, .runtimeProgressStalled, .evidenceBridgeRefused:
            .runtimeFailed
        }
    }

    private static func nextNonzero(
        _ value: UInt64
    ) -> UInt64 {
        let next = value &+ 1
        return next == 0 ? 1 : next
    }

    private static func addingClamped(
        _ lhs: UInt64,
        _ rhs: UInt64
    ) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }
}

protocol WorldwideBlackHoleDefaultInputLeasing:
    AnyObject,
    Sendable
{
    func acquisitionResult(
        generation: UInt64,
        targetEndpoint: BlackHoleDeviceEndpointIdentity
    ) -> BlackHoleDefaultInputLeaseAcquisitionResult
    func authorizationProof(
        generation: UInt64,
        targetEndpoint: BlackHoleDeviceEndpointIdentity
    ) -> BlackHoleDefaultInputLeaseAuthorization?
    func release(
        generation: UInt64
    ) -> BlackHoleDefaultInputLeaseReleaseResult
    func parkForClockEpochRecovery(
        generation: UInt64,
        targetEndpoint: BlackHoleDeviceEndpointIdentity
    ) -> BlackHoleDefaultInputLeaseParkingResult
    func clockEpochParkingProofIsCurrent(
        _ proof: BlackHoleDefaultInputLeaseParkingProof
    ) -> Bool
    func reacquisitionResult(
        parkingProof: BlackHoleDefaultInputLeaseParkingProof,
        targetEndpoint: BlackHoleDeviceEndpointIdentity
    ) -> BlackHoleDefaultInputLeaseAcquisitionResult
    func shutdown()
        -> BlackHoleDefaultInputLeaseReleaseResult
}

extension BlackHoleDefaultInputLease:
    WorldwideBlackHoleDefaultInputLeasing
{}

struct WorldwideBlackHoleDefaultInputKey:
    Equatable,
    Sendable
{
    let monitorEpoch: UUID
    let deviceGeneration: UInt64
    let peerGeneration: UInt64
    let connectionGeneration: UInt64
    let leaseGeneration: UInt64
    let deviceEndpoint: BlackHoleDeviceEndpointIdentity
    let inputAuthorization:
        BlackHoleDefaultInputLeaseAuthorization

    var deviceUID: String {
        deviceEndpoint.deviceUID
    }
}

enum WorldwideBlackHoleDefaultInputOutcome:
    Equatable,
    Sendable
{
    case noChange
    case waitingForMonitor
    case waitingForDevice
    case selected(WorldwideBlackHoleDefaultInputKey)
    case released
    case degraded
    case suppressed
}

enum WorldwideBlackHoleClockEpochParkingOutcome:
    Equatable,
    Sendable
{
    case parked(BlackHoleDefaultInputLeaseParkingProof)
    case degraded
}

enum WorldwideBlackHoleAudioRoutingCleanupResult:
    Equatable,
    Sendable
{
    case cleaned
    case degraded
}

/// Runs default-input and device-list cleanup as one bounded lifecycle policy.
///
/// Every episode drives both owners. A completed half remains safe to call
/// idempotently while the other half is redriven with its retained exact
/// Core Audio identity.
enum WorldwideBlackHoleAudioRoutingCleanupPolicy {
    static func run(
        maximumEpisodeCount: Int,
        shutdownDefaultInput:
            () -> WorldwideBlackHoleDefaultInputOutcome,
        stopDeviceMonitor:
            () -> BlackHoleDeviceAvailabilityMonitorStopResult
    ) -> WorldwideBlackHoleAudioRoutingCleanupResult {
        let boundedEpisodeCount = max(
            1,
            maximumEpisodeCount
        )

        for _ in 0..<boundedEpisodeCount {
            let defaultInputOutcome =
                shutdownDefaultInput()
            let monitorOutcome =
                stopDeviceMonitor()

            if defaultInputOutcome != .degraded,
               monitorOutcome == .stopped {
                return .cleaned
            }
        }

        return .degraded
    }
}

protocol WorldwideBlackHoleAudioRoutingCleanupRetaining:
    AnyObject,
    Sendable
{
    func retain(
        id: UUID,
        attempt: @escaping @Sendable () -> Bool
    )
    func remove(id: UUID)

    @discardableResult
    func redriveRetained(
        maximumAttemptCount: Int
    ) -> Int

    var retainedJobCount: Int { get }
}

/// One shared lifecycle fence between retained exact Core Audio cleanup and
/// installation of any replacement monitor/default-input ownership.
enum WorldwideBlackHoleAudioRoutingStartupGate {
    static func redriveAndPermitNewOwnership(
        retainer:
            any WorldwideBlackHoleAudioRoutingCleanupRetaining,
        maximumAttemptCount: Int = 1,
        deferredDefaultInputCleanup:
            @Sendable (Int) -> Bool = {
                maximumAttemptCount in
                BlackHoleDefaultInputLease
                    .redriveRetainedDeferredCleanup(
                        maximumAttemptCount:
                            maximumAttemptCount
                    )
            }
    ) -> Bool {
        let defaultInputCleanupCompleted =
            deferredDefaultInputCleanup(
                maximumAttemptCount
            )
        let serviceCleanupCompleted =
            retainer.redriveRetained(
                maximumAttemptCount:
                    maximumAttemptCount
            ) == 0
        return defaultInputCleanupCompleted
            && serviceCleanupCompleted
    }
}

/// Retains exact degraded Core Audio cleanup ownership after its originating
/// service has stopped.
///
/// Each redrive call has one global attempt budget shared across all retained
/// jobs. A failed job moves to the back of the queue and remains retained for a
/// later explicit lifecycle redrive; there is no timer loop or unbounded retry.
final class WorldwideBlackHoleAudioRoutingCleanupRetainer:
    WorldwideBlackHoleAudioRoutingCleanupRetaining,
    @unchecked Sendable
{
    private struct Job {
        let id: UUID
        let attempt: @Sendable () -> Bool
    }

    static let shared =
        WorldwideBlackHoleAudioRoutingCleanupRetainer()

    private let lock = NSLock()
    private var jobs: [UUID: Job] = [:]
    private var jobOrder: [UUID] = []

    func retain(
        id: UUID,
        attempt: @escaping @Sendable () -> Bool
    ) {
        withLock {
            let isNew = jobs[id] == nil
            jobs[id] = Job(
                id: id,
                attempt: attempt
            )
            if isNew {
                jobOrder.append(id)
            }
        }
    }

    func remove(id: UUID) {
        withLock {
            jobs.removeValue(forKey: id)
            jobOrder.removeAll {
                $0 == id
            }
        }
    }

    /// Performs at most `maximumAttemptCount` total cleanup episodes, not that
    /// many episodes per retained owner.
    @discardableResult
    func redriveRetained(
        maximumAttemptCount: Int
    ) -> Int {
        let boundedAttemptCount = max(
            0,
            maximumAttemptCount
        )

        for _ in 0..<boundedAttemptCount {
            let job: Job? = withLock {
                while let id = jobOrder.first {
                    jobOrder.removeFirst()
                    if let job = jobs[id] {
                        return job
                    }
                }
                return nil
            }
            guard let job else {
                break
            }

            let completed = job.attempt()
            withLock {
                guard jobs[job.id] != nil else {
                    return
                }
                if completed {
                    jobs.removeValue(
                        forKey: job.id
                    )
                } else {
                    jobOrder.append(job.id)
                }
            }
        }

        return retainedJobCount
    }

    var retainedJobCount: Int {
        withLock {
            jobs.count
        }
    }

    private func withLock<T>(
        _ body: () -> T
    ) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Connection-level default-input ownership, deliberately independent of remote
/// track arrival, decoded PCM, and forwarding readiness.
final class WorldwideBlackHoleDefaultInputCoordinator {
    private struct CandidateIdentity: Equatable {
        let monitorEpoch: UUID
        let deviceGeneration: UInt64
        let peerGeneration: UInt64
        let connectionGeneration: UInt64
        let deviceEndpoint: BlackHoleDeviceEndpointIdentity
    }

    private struct LeaseKey: Equatable {
        let monitorEpoch: UUID
        let deviceGeneration: UInt64
        let peerGeneration: UInt64
        let connectionGeneration: UInt64
        let leaseGeneration: UInt64
        let deviceEndpoint: BlackHoleDeviceEndpointIdentity

        init(
            monitorEpoch: UUID,
            deviceGeneration: UInt64,
            peerGeneration: UInt64,
            connectionGeneration: UInt64,
            leaseGeneration: UInt64,
            deviceEndpoint: BlackHoleDeviceEndpointIdentity
        ) {
            self.monitorEpoch = monitorEpoch
            self.deviceGeneration = deviceGeneration
            self.peerGeneration = peerGeneration
            self.connectionGeneration = connectionGeneration
            self.leaseGeneration = leaseGeneration
            self.deviceEndpoint = deviceEndpoint
        }

        init(_ key: WorldwideBlackHoleDefaultInputKey) {
            self.init(
                monitorEpoch: key.monitorEpoch,
                deviceGeneration: key.deviceGeneration,
                peerGeneration: key.peerGeneration,
                connectionGeneration: key.connectionGeneration,
                leaseGeneration: key.leaseGeneration,
                deviceEndpoint: key.deviceEndpoint
            )
        }

        func authorized(
            by authorization:
                BlackHoleDefaultInputLeaseAuthorization
        ) -> WorldwideBlackHoleDefaultInputKey {
            WorldwideBlackHoleDefaultInputKey(
                monitorEpoch: monitorEpoch,
                deviceGeneration: deviceGeneration,
                peerGeneration: peerGeneration,
                connectionGeneration: connectionGeneration,
                leaseGeneration: leaseGeneration,
                deviceEndpoint: deviceEndpoint,
                inputAuthorization: authorization
            )
        }
    }

    private enum ReleaseDisposition {
        case noChange
        case released
        case retryableFailure
        case externallySuperseded
    }

    private struct ReleaseOwnership: Equatable {
        let activeKey: WorldwideBlackHoleDefaultInputKey?
        let pendingKey: LeaseKey?
    }

    private struct ReleaseContext: Equatable {
        let activeMonitorEpoch: UUID?
        let monitorSnapshot: BlackHoleDeviceAvailabilitySnapshot?
        let healthyPeerGeneration: UInt64?
        let highestPeerGenerationSeen: UInt64
        let connectionGeneration: UInt64
        let isStopped: Bool
    }

    private struct ReleaseProtection: Equatable {
        let terminalConnectionGeneration: UInt64?
        let externallySupersededPeerGeneration: UInt64?
    }

    private struct ReleaseEpisode {
        // Nil means the expected owner or context changed before a native call. A
        // non-nil value preserves the actual result, including noChange
        // for the original no-owner path. Currentness is not a Rust fact.
        let disposition: ReleaseDisposition?
        let expectedContext: ReleaseContext
        let expectedProtection: ReleaseProtection
        // Includes lifecycle changes that retain the same ownership slot.
        let currentnessChanged: Bool
    }

    private var releaseOwnership: ReleaseOwnership {
        ReleaseOwnership(activeKey: activeKey, pendingKey: pendingKey)
    }

    private var releaseContext: ReleaseContext {
        ReleaseContext(
            activeMonitorEpoch: activeMonitorEpoch,
            monitorSnapshot: monitorSnapshot,
            healthyPeerGeneration: healthyPeerGeneration,
            highestPeerGenerationSeen: highestPeerGenerationSeen,
            connectionGeneration: connectionGeneration,
            isStopped: isStopped
        )
    }

    private var releaseProtection: ReleaseProtection {
        ReleaseProtection(
            terminalConnectionGeneration: terminalConnectionGeneration,
            externallySupersededPeerGeneration: externallySupersededPeerGeneration
        )
    }

    private func releaseIsCurrent(_ episode: ReleaseEpisode) -> Bool {
        !episode.currentnessChanged
            && releaseContext == episode.expectedContext
            && releaseProtection == episode.expectedProtection
    }

    private let policy:
        WorldwideIPhoneMicrophoneForwardingPolicy
    private let lease:
        any WorldwideBlackHoleDefaultInputLeasing
    private let maximumAcquisitionAttemptCount: Int
    private let maximumReleaseAttemptCount: Int
    private let maximumShutdownAttemptCount: Int

    private var activeMonitorEpoch: UUID?
    private var monitorSnapshot: BlackHoleDeviceAvailabilitySnapshot?
    private var healthyPeerGeneration: UInt64?
    private var highestPeerGenerationSeen: UInt64 = 0
    private var connectionGeneration: UInt64 = 0
    private var nextLeaseGeneration: UInt64 = 0
    private var activeKey: WorldwideBlackHoleDefaultInputKey?
    private var pendingKey: LeaseKey?
    private var releaseIsPending = false
    private var clockEpochParkingProof:
        BlackHoleDefaultInputLeaseParkingProof?
    private var terminalConnectionGeneration: UInt64?
    private var externallySupersededPeerGeneration: UInt64?
    private var lastAttemptedIdentity: CandidateIdentity?
    private var acquisitionAttemptCount = 0
    // Out-of-domain policy refusal blocks new healthy admission, not the
    // original exact native release/shutdown callbacks for retained ownership.
    private var inputLeasePolicyRefused = false
    private var isStopped = false
    private var shutdownCleanupWasPending = false

    init(
        policy:
            WorldwideIPhoneMicrophoneForwardingPolicy,
        lease:
            any WorldwideBlackHoleDefaultInputLeasing,
        maximumAcquisitionAttemptCount: Int = 3,
        maximumReleaseAttemptCount: Int = 1,
        maximumShutdownAttemptCount: Int = 1
    ) {
        self.policy = policy
        self.lease = lease
        self.maximumAcquisitionAttemptCount = max(
            1,
            maximumAcquisitionAttemptCount
        )
        self.maximumReleaseAttemptCount = max(
            1,
            maximumReleaseAttemptCount
        )
        self.maximumShutdownAttemptCount = max(
            1,
            maximumShutdownAttemptCount
        )
    }

    func beginMonitoring(
        epoch: UUID
    ) -> WorldwideBlackHoleDefaultInputOutcome {
        guard !isStopped else {
            return .noChange
        }
        guard policy == .enabled else {
            return .suppressed
        }
        guard activeMonitorEpoch != epoch else {
            return .noChange
        }

        let release = releaseActiveBounded()
        guard releaseIsCurrent(release) else { return .degraded }
        activeMonitorEpoch = epoch
        monitorSnapshot = nil
        resetAcquisitionAttempts()
        return outcome(
            for: release,
            whenNoChange: .waitingForMonitor
        )
    }

    func monitoringDidFail()
        -> WorldwideBlackHoleDefaultInputOutcome {
        guard !isStopped else {
            return .noChange
        }
        guard policy == .enabled else {
            return .suppressed
        }
        let release = releaseActiveBounded()
        guard releaseIsCurrent(release) else { return .degraded }
        activeMonitorEpoch = nil
        monitorSnapshot = nil
        resetAcquisitionAttempts()
        return .degraded
    }

    func deviceRevalidationDidFail()
        -> WorldwideBlackHoleDefaultInputOutcome {
        guard !isStopped else {
            return .noChange
        }
        guard policy == .enabled else {
            return .suppressed
        }
        let release = releaseActiveBounded()
        guard releaseIsCurrent(release) else { return .degraded }
        monitorSnapshot = nil
        resetAcquisitionAttempts()
        return .degraded
    }

    func updateDeviceSnapshot(
        _ snapshot:
            BlackHoleDeviceAvailabilitySnapshot
    ) -> WorldwideBlackHoleDefaultInputOutcome {
        guard !isStopped else {
            return .noChange
        }
        guard policy == .enabled else {
            return .suppressed
        }
        guard snapshot.monitorEpoch
                == activeMonitorEpoch else {
            return .noChange
        }
        if let monitorSnapshot {
            guard snapshot.deviceGeneration
                    > monitorSnapshot.deviceGeneration else {
                return .noChange
            }
        }

        monitorSnapshot = snapshot
        if !snapshot.isAvailable
            || snapshot.defaultInputEndpoint == nil
            || snapshot.hiddenMirrorSinkEndpoint == nil {
            resetAcquisitionAttempts()
            return outcome(
                for: releaseActiveBounded(),
                whenNoChange: .waitingForDevice
            )
        }
        return drive()
    }

    func transportDidBecomeHealthy(
        peerGeneration: UInt64
    ) -> WorldwideBlackHoleDefaultInputOutcome {
        guard !isStopped, peerGeneration > 0 else {
            return .noChange
        }
        guard policy == .enabled else {
            return .suppressed
        }
        guard clockEpochParkingProof == nil else {
            return .degraded
        }
        guard peerGeneration
                >= highestPeerGenerationSeen else {
            return .noChange
        }
        let isStrictlyNewerPeer =
            peerGeneration > highestPeerGenerationSeen
        if isStrictlyNewerPeer {
            highestPeerGenerationSeen = peerGeneration
        }

        if externallySupersededPeerGeneration
                == peerGeneration {
            if releaseIsPending {
                _ = releaseActiveBounded()
            }
            return .degraded
        }

        if healthyPeerGeneration == peerGeneration {
            return drive()
        }

        let release = releaseActiveBounded()
        guard releaseIsCurrent(release) else { return .degraded }
        healthyPeerGeneration = peerGeneration
        connectionGeneration = Self.nextNonzero(
            connectionGeneration
        )
        terminalConnectionGeneration = nil
        resetAcquisitionAttempts()
        if isStrictlyNewerPeer {
            // A genuinely newer authenticated peer is the only runtime event
            // allowed to clear a prior external-selector terminal fence.
            externallySupersededPeerGeneration = nil
        }
        if release.disposition == .retryableFailure {
            return .degraded
        }
        return drive()
    }

    func transportDidBecomeUnhealthy(
        peerGeneration: UInt64
    ) -> WorldwideBlackHoleDefaultInputOutcome {
        guard !isStopped else {
            return .noChange
        }
        let ownsPeer =
            healthyPeerGeneration == peerGeneration
                || activeKey?.peerGeneration == peerGeneration
                || pendingKey?.peerGeneration == peerGeneration
        guard ownsPeer else {
            return .noChange
        }
        if healthyPeerGeneration == peerGeneration {
            healthyPeerGeneration = nil
        }
        resetAcquisitionAttempts()
        let release = releaseActiveBounded()
        guard releaseIsCurrent(release),
              let disposition = release.disposition else { return .degraded }
        let releaseOutcome = outcome(
            for: release,
            whenNoChange: .noChange
        )
        switch disposition {
        case .retryableFailure:
            return releaseOutcome
        case .noChange, .released,
             .externallySuperseded:
            break
        }

        guard healthyPeerGeneration != nil else {
            return releaseOutcome
        }
        let replacementOutcome = drive()
        if case .noChange = replacementOutcome {
            return releaseOutcome
        }
        return replacementOutcome
    }

    func parkForSharedClockEpochRecovery(
        peerGeneration: UInt64
    ) -> WorldwideBlackHoleClockEpochParkingOutcome {
        guard !isStopped,
              policy == .enabled,
              healthyPeerGeneration == peerGeneration,
              let activeKey,
              activeKey.peerGeneration == peerGeneration,
              pendingKey == nil,
              !releaseIsPending,
              clockEpochParkingProof == nil else {
            return .degraded
        }

        healthyPeerGeneration = nil
        resetAcquisitionAttempts()
        switch lease.parkForClockEpochRecovery(
            generation: activeKey.leaseGeneration,
            targetEndpoint: activeKey.deviceEndpoint
        ) {
        case .parked(let proof)
            where proof.leaseGeneration
                == activeKey.leaseGeneration
                && proof.targetEndpoint
                    == activeKey.deviceEndpoint:
            self.activeKey = LeaseKey(activeKey).authorized(
                by: BlackHoleDefaultInputLeaseAuthorization(
                    leaseGeneration: proof.leaseGeneration,
                    listenerRegistrationID:
                        proof.listenerRegistrationID,
                    acceptedListenerSequence:
                        proof.acceptedListenerSequence,
                    targetEndpoint: proof.targetEndpoint
                )
            )
            clockEpochParkingProof = proof
            return .parked(proof)

        case .parked, .retryableFailure, .terminalFailure:
            _ = releaseActiveBounded()
            return .degraded
        }
    }

    func sharedClockParkingProofIsCurrent(
        _ proof: BlackHoleDefaultInputLeaseParkingProof,
        peerGeneration: UInt64,
        snapshot: BlackHoleDeviceAvailabilitySnapshot
    ) -> Bool {
        guard clockEpochParkingProof == proof,
              healthyPeerGeneration == nil,
              let activeKey,
              activeKey.leaseGeneration == proof.leaseGeneration,
              activeKey.peerGeneration == peerGeneration,
              activeKey.monitorEpoch == snapshot.monitorEpoch,
              activeKey.deviceGeneration
                == snapshot.deviceGeneration,
              activeKey.deviceEndpoint
                == snapshot.defaultInputEndpoint,
              proof.targetEndpoint == activeKey.deviceEndpoint else {
            return false
        }
        guard lease.clockEpochParkingProofIsCurrent(proof) else {
            _ = releaseActiveBounded()
            return false
        }
        return true
    }

    func transportDidBecomeHealthyAfterSharedClockRecovery(
        peerGeneration: UInt64,
        parkingProof: BlackHoleDefaultInputLeaseParkingProof
    ) -> WorldwideBlackHoleDefaultInputOutcome {
        guard !isStopped,
              !inputLeasePolicyRefused,
              policy == .enabled,
              healthyPeerGeneration == nil,
              clockEpochParkingProof == parkingProof,
              let snapshot = monitorSnapshot,
              snapshot.isAvailable,
              let activeKey,
              activeKey.peerGeneration == peerGeneration,
              activeKey.monitorEpoch == snapshot.monitorEpoch,
              activeKey.deviceGeneration
                == snapshot.deviceGeneration,
              activeKey.deviceEndpoint
                == snapshot.defaultInputEndpoint,
              parkingProof.targetEndpoint
                == activeKey.deviceEndpoint,
              !releaseIsPending else {
            return .degraded
        }
        let leaseKey = LeaseKey(activeKey)
        let parkingProofIsCurrent = lease.clockEpochParkingProofIsCurrent(
            parkingProof
        )
        guard !inputLeasePolicyRefused else {
            cleanupRefusedInputLease(for: leaseKey)
            return .degraded
        }
        guard parkingProofIsCurrent else {
            _ = releaseActiveBounded()
            return .degraded
        }

        let reacquisition = lease.reacquisitionResult(
            parkingProof: parkingProof,
            targetEndpoint: activeKey.deviceEndpoint
        )
        guard !inputLeasePolicyRefused else {
            cleanupRefusedInputLease(for: leaseKey)
            return .degraded
        }
        switch reacquisition {
        case .acquired:
            guard let authorization =
                    authorizationProof(
                        for: leaseKey
                    ) else {
                if inputLeasePolicyRefused {
                    cleanupRefusedInputLease(for: leaseKey)
                    return .degraded
                }
                _ = releaseActiveBounded()
                return .degraded
            }
            let refreshedKey = leaseKey.authorized(
                by: authorization
            )
            self.activeKey = refreshedKey
            clockEpochParkingProof = nil
            healthyPeerGeneration = peerGeneration
            return .selected(refreshedKey)

        case .retryableFailure, .terminalFailure:
            _ = releaseActiveBounded()
            return .degraded
        }
    }

    /// Consumes a raw exact-listener event after the realtime writer gate has
    /// already been closed. Only the event incorporated by the current proof is
    /// stale. Every other event terminalizes this connection generation and
    /// releases without restoring over the external selector choice.
    func defaultInputDidBecomeUncertain(
        _ event: BlackHoleDefaultInputLeaseUncertaintyEvent
    ) -> WorldwideBlackHoleDefaultInputOutcome {
        guard !isStopped else {
            return .noChange
        }
        guard policy == .enabled else {
            return .suppressed
        }
        guard let activeKey else {
            return .noChange
        }
        let authorization =
            activeKey.inputAuthorization
        guard event.leaseGeneration
                == activeKey.leaseGeneration,
              event.listenerRegistrationID
                == authorization.listenerRegistrationID else {
            // A callback retained by an older registration cannot poison the
            // current peer or replacement lease.
            return .noChange
        }
        if authorization.incorporates(event) {
            return .noChange
        }

        recordExternalSupersession(
            peerGeneration:
                activeKey.peerGeneration
        )
        terminalConnectionGeneration =
            activeKey.connectionGeneration
        resetAcquisitionAttempts()
        _ = releaseActiveBounded()
        return .degraded
    }

    func invalidateCurrentConnection()
        -> WorldwideBlackHoleDefaultInputOutcome {
        guard !isStopped else {
            return .noChange
        }
        healthyPeerGeneration = nil
        resetAcquisitionAttempts()
        return outcome(
            for: releaseActiveBounded(),
            whenNoChange: .noChange
        )
    }

    func shutdown()
        -> WorldwideBlackHoleDefaultInputOutcome {
        if !isStopped {
            isStopped = true
            healthyPeerGeneration = nil
            resetAcquisitionAttempts()
        }

        var completedCleanup =
            shutdownCleanupWasPending
        var attemptCount = 0

        while attemptCount
                < maximumShutdownAttemptCount {
            attemptCount += 1

            let release = releaseActiveBounded()
            guard releaseIsCurrent(release),
                  let disposition = release.disposition else { return .degraded }
            switch disposition {
            case .retryableFailure:
                shutdownCleanupWasPending = true
                continue

            case .released,
                 .externallySuperseded:
                completedCleanup = true

            case .noChange:
                break
            }

            let expectedOwnership = releaseOwnership
            let expectedContext = releaseContext
            let expectedProtection = releaseProtection
            let shutdownResult = lease.shutdown()
            guard releaseOwnership == expectedOwnership,
                  releaseContext == expectedContext,
                  releaseProtection == expectedProtection else { return .degraded }
            switch shutdownResult {
            case .released,
                 .externallySuperseded:
                shutdownCleanupWasPending = false
                return completedCleanup
                    ? .released
                    : .noChange

            case .retryableFailure:
                shutdownCleanupWasPending = true
            }
        }

        return .degraded
    }

    private func drive()
        -> WorldwideBlackHoleDefaultInputOutcome {
        guard !isStopped else {
            return .noChange
        }
        guard clockEpochParkingProof == nil else {
            return .degraded
        }
        guard let activeMonitorEpoch,
              let monitorSnapshot else {
            return .waitingForMonitor
        }
        guard monitorSnapshot.isAvailable,
              let deviceEndpoint =
                monitorSnapshot.defaultInputEndpoint,
              !deviceEndpoint.deviceUID.isEmpty,
              monitorSnapshot.defaultInputEndpoint?.deviceUID
                == deviceEndpoint.deviceUID,
              monitorSnapshot.hiddenMirrorSinkEndpoint != nil else {
            return .waitingForDevice
        }
        guard let healthyPeerGeneration else {
            return .noChange
        }
        if externallySupersededPeerGeneration
                == healthyPeerGeneration {
            return .degraded
        }
        if terminalConnectionGeneration
                == connectionGeneration,
           activeKey == nil,
           pendingKey == nil {
            return .degraded
        }

        let identity = CandidateIdentity(
            monitorEpoch: activeMonitorEpoch,
            deviceGeneration:
                monitorSnapshot.deviceGeneration,
            peerGeneration: healthyPeerGeneration,
            connectionGeneration:
                connectionGeneration,
            deviceEndpoint: deviceEndpoint
        )
        let currentLeaseKey =
            activeKey.map(LeaseKey.init) ?? pendingKey
        let activeKeyMatchesIdentity =
            currentLeaseKey.map {
                $0.monitorEpoch == identity.monitorEpoch
                    && $0.deviceGeneration
                        == identity.deviceGeneration
                    && $0.peerGeneration
                        == identity.peerGeneration
                    && $0.connectionGeneration
                        == identity.connectionGeneration
                    && $0.deviceEndpoint
                        == identity.deviceEndpoint
            } ?? false
        if let activeKey,
           activeKeyMatchesIdentity,
           !releaseIsPending {
            guard !inputLeasePolicyRefused else { return .degraded }
            let leaseKey = LeaseKey(activeKey)
            guard let authorization =
                    authorizationProof(for: leaseKey) else {
                if inputLeasePolicyRefused {
                    cleanupRefusedInputLease(for: leaseKey)
                    return .degraded
                }
                terminalConnectionGeneration =
                    activeKey.connectionGeneration
                resetAcquisitionAttempts()
                _ = releaseActiveBounded()
                return .degraded
            }
            let refreshedKey = leaseKey.authorized(
                by: authorization
            )
            self.activeKey = refreshedKey
            return .selected(refreshedKey)
        }

        if currentLeaseKey != nil,
           releaseIsPending
                || !activeKeyMatchesIdentity {
            let release = releaseActiveBounded()
            guard releaseIsCurrent(release),
                  let disposition = release.disposition else { return .degraded }
            if disposition == .retryableFailure {
                return .degraded
            }
            if terminalConnectionGeneration
                == connectionGeneration {
                return .degraded
            }
        }

        if lastAttemptedIdentity != identity {
            lastAttemptedIdentity = identity
            acquisitionAttemptCount = 0
        }
        guard inputLeasePolicyAction(
            operation: .acquisitionBudget,
            attemptCount: acquisitionAttemptCount,
            maximumAttemptCount: maximumAcquisitionAttemptCount
        ) == .acquire else {
            return .degraded
        }

        let key: LeaseKey
        if let pendingKey {
            key = pendingKey
        } else {
            nextLeaseGeneration = Self.nextNonzero(
                nextLeaseGeneration
            )
            key = LeaseKey(
                monitorEpoch: identity.monitorEpoch,
                deviceGeneration:
                    identity.deviceGeneration,
                peerGeneration: identity.peerGeneration,
                connectionGeneration:
                    identity.connectionGeneration,
                leaseGeneration:
                    nextLeaseGeneration,
                deviceEndpoint:
                    identity.deviceEndpoint
            )
            pendingKey = key
        }

        while true {
            // The key exists at this second admission cut. Refusal must drive
            // its existing exact native cleanup before returning degraded.
            guard let admission = inputLeasePolicyAction(
                operation: .acquisitionBudget,
                attemptCount: acquisitionAttemptCount,
                maximumAttemptCount: maximumAcquisitionAttemptCount
            ) else {
                cleanupRefusedInputLease(for: key)
                return .degraded
            }
            guard admission == .acquire else { break }
            acquisitionAttemptCount += 1
            let nativeResult = lease.acquisitionResult(
                generation: key.leaseGeneration,
                targetEndpoint: deviceEndpoint
            )
            let nativeDisposition: UInt32
            switch nativeResult {
            case .acquired: nativeDisposition = 1
            case .retryableFailure: nativeDisposition = 2
            case .terminalFailure: nativeDisposition = 3
            }
            guard let acquisition = inputLeasePolicyAction(
                operation: .acquisitionOutcome,
                disposition: nativeDisposition
            ) else {
                cleanupRefusedInputLease(for: key)
                return .degraded
            }
            switch acquisition {
            case .authorizeAcquired:
                guard let authorization =
                        authorizationProof(for: key) else {
                    if inputLeasePolicyRefused {
                        cleanupRefusedInputLease(for: key)
                        return .degraded
                    }
                    terminalConnectionGeneration =
                        key.connectionGeneration
                    acquisitionAttemptCount =
                        maximumAcquisitionAttemptCount
                    _ = releaseActiveBounded()
                    return .degraded
                }
                let authorizedKey = key.authorized(
                    by: authorization
                )
                pendingKey = nil
                activeKey = authorizedKey
                return .selected(authorizedKey)
            case .retryAcquisition:
                continue
            case .terminalAcquisition:
                terminalConnectionGeneration =
                    key.connectionGeneration
                acquisitionAttemptCount =
                    maximumAcquisitionAttemptCount
                _ = releaseActiveBounded()
                return .degraded
            default:
                inputLeasePolicyRefused = true
                cleanupRefusedInputLease(for: key)
                return .degraded
            }
        }

        // Retryable pre-write failures can retain the exact generation's
        // retry baseline or pending listener deregistration even without a
        // default-input write. Exhaustion therefore performs one bounded
        // exact cleanup episode. A retryable release preserves activeKey and
        // releaseIsPending for a later lifecycle callback; success clears the
        // key through the existing release path. Keep the exhausted identity
        // and attempt count so no callback can bypass its acquisition budget.
        _ = releaseActiveBounded()
        return .degraded
    }

    private func releaseActive(
        for expectedOwnership: ReleaseOwnership,
        context expectedContext: ReleaseContext,
        protection expectedProtection: ReleaseProtection
    ) -> ReleaseEpisode {
        guard releaseOwnership == expectedOwnership,
              releaseContext == expectedContext,
              releaseProtection == expectedProtection else {
            return ReleaseEpisode(disposition: nil, expectedContext: expectedContext,
                expectedProtection: expectedProtection, currentnessChanged: true)
        }
        guard let leaseKey =
                expectedOwnership.activeKey.map(LeaseKey.init)
                    ?? expectedOwnership.pendingKey else {
            releaseIsPending = false
            clockEpochParkingProof = nil
            return ReleaseEpisode(disposition: .noChange, expectedContext: expectedContext,
                expectedProtection: expectedProtection, currentnessChanged: false)
        }
        let nativeResult = lease.release(
            generation: leaseKey.leaseGeneration
        )
        let actualDisposition: ReleaseDisposition
        switch nativeResult {
        case .released: actualDisposition = .released
        case .retryableFailure: actualDisposition = .retryableFailure
        case .externallySuperseded: actualDisposition = .externallySuperseded
        }
        guard releaseOwnership == expectedOwnership,
              releaseContext == expectedContext,
              releaseProtection == expectedProtection else {
            // Native cleanup may have reentered the coordinator. Retain its
            // real result, but do not clear/fence a replacement owner or commit
            // across newer lifecycle context that retains the same owner.
            return ReleaseEpisode(disposition: actualDisposition, expectedContext: expectedContext,
                expectedProtection: expectedProtection, currentnessChanged: true)
        }
        let expectedPostProtection: ReleaseProtection
        switch nativeResult {
        case .externallySuperseded:
            // Derive the exact original own-write transition from copied
            // facts. Never adopt a nested callback's newer protection state.
            expectedPostProtection = ReleaseProtection(
                terminalConnectionGeneration: leaseKey.connectionGeneration,
                externallySupersededPeerGeneration: leaseKey.peerGeneration > 0
                    ? max(expectedProtection.externallySupersededPeerGeneration ?? 0,
                        leaseKey.peerGeneration)
                    : expectedProtection.externallySupersededPeerGeneration
            )
        case .released, .retryableFailure:
            expectedPostProtection = expectedProtection
        }
        switch nativeResult {
        case .released:
            self.activeKey = nil
            pendingKey = nil
            releaseIsPending = false
            clockEpochParkingProof = nil

        case .retryableFailure:
            releaseIsPending = true

        case .externallySuperseded:
            self.activeKey = nil
            pendingKey = nil
            releaseIsPending = false
            clockEpochParkingProof = nil
            terminalConnectionGeneration =
                leaseKey.connectionGeneration
            recordExternalSupersession(
                peerGeneration:
                    leaseKey.peerGeneration
            )
        }
        return ReleaseEpisode(disposition: actualDisposition, expectedContext: expectedContext,
            expectedProtection: expectedPostProtection, currentnessChanged: false)
    }

    private func authorizationProof(
        for key: LeaseKey
    ) -> BlackHoleDefaultInputLeaseAuthorization? {
        guard !inputLeasePolicyRefused else { return nil }
        guard let authorization = lease.authorizationProof(
            generation: key.leaseGeneration,
            targetEndpoint: key.deviceEndpoint
        ),
        !inputLeasePolicyRefused,
        authorization.leaseGeneration == key.leaseGeneration,
        authorization.targetEndpoint == key.deviceEndpoint else {
            return nil
        }
        return authorization
    }

    private func cleanupRefusedInputLease(for key: LeaseKey) {
        // Never release a reentrantly newer coordinator owner. This entry
        // key fence precedes a full-slot-fenced bounded release episode.
        guard (activeKey.map(LeaseKey.init) ?? pendingKey) == key else { return }
        // Keep the real disposition/bookkeeping: retryable release retains
        // this exact key and releaseIsPending for later lifecycle callbacks.
        _ = releaseActiveBounded()
    }

    private func releaseActiveBounded()
        -> ReleaseEpisode {
        let expectedOwnership = releaseOwnership
        let expectedContext = releaseContext
        let expectedProtection = releaseProtection
        var episode = releaseActive(for: expectedOwnership, context: expectedContext,
            protection: expectedProtection)
        var attemptCount = 1
        while true {
            guard releaseIsCurrent(episode),
                  let result = episode.disposition else { return episode }
            // The first exact native cleanup call above is unconditional even
            // after refusal. A refusal does not fabricate its native disposition.
            let continuation = inputLeasePolicyAction(
                operation: .releaseContinuation,
                disposition: inputLeaseDisposition(result),
                attemptCount: attemptCount,
                maximumAttemptCount: maximumReleaseAttemptCount
            )
            if result == .retryableFailure,
               (releaseOwnership != expectedOwnership || releaseContext != expectedContext
                    || releaseProtection != expectedProtection) {
                return ReleaseEpisode(disposition: result, expectedContext: expectedContext,
                    expectedProtection: expectedProtection, currentnessChanged: true)
            }
            guard releaseIsCurrent(episode) else {
                return ReleaseEpisode(disposition: result, expectedContext: expectedContext,
                    expectedProtection: episode.expectedProtection, currentnessChanged: true)
            }
            guard let continuation else { return episode }
            guard continuation == .retryRelease else { break }
            attemptCount += 1
            // The entire episode owns one captured slot, never whichever
            // replacement key a nested callback has since published.
            episode = releaseActive(for: expectedOwnership, context: expectedContext,
                protection: expectedProtection)
        }
        return episode
    }

    private func outcome(
        for release: ReleaseEpisode,
        whenNoChange fallback:
            WorldwideBlackHoleDefaultInputOutcome
    ) -> WorldwideBlackHoleDefaultInputOutcome {
        // An admitted caller may already have committed its own new epoch.
        // Reentry refusal is sticky in this result; do not reject those
        // intentional caller commits by rechecking the captured old context.
        guard !release.currentnessChanged,
              let disposition = release.disposition else { return .degraded }
        guard let result = inputLeasePolicyAction(
            operation: .releaseOutcome,
            disposition: inputLeaseDisposition(disposition)
        ) else { return .degraded }
        switch result {
        case .useNativeFallback:
            return fallback
        case .released:
            return .released
        case .degraded:
            return .degraded
        default:
            inputLeasePolicyRefused = true
            return .degraded
        }
    }

    private func inputLeaseDisposition(_ result: ReleaseDisposition) -> UInt32 {
        switch result {
        case .noChange: 0
        case .released: 1
        case .retryableFailure: 2
        case .externallySuperseded: 3
        }
    }

    private func inputLeasePolicyAction(
        operation: BelugaRustMicrophoneInputLease.Operation,
        disposition: UInt32 = 0,
        attemptCount: Int = 0,
        maximumAttemptCount: Int = 0
    ) -> BelugaRustMicrophoneInputLease.Action? {
        guard !inputLeasePolicyRefused || operation == .releaseContinuation else { return nil }
        do {
            return try BelugaRustMicrophoneInputLease.evaluate(
                operation: operation, disposition: disposition,
                attemptCount: attemptCount, maximumAttemptCount: maximumAttemptCount
            )
        } catch {
            inputLeasePolicyRefused = true
            return nil
        }
    }

    private func resetAcquisitionAttempts() {
        lastAttemptedIdentity = nil
        acquisitionAttemptCount = 0
    }

    private func recordExternalSupersession(
        peerGeneration: UInt64
    ) {
        guard peerGeneration > 0 else {
            return
        }
        externallySupersededPeerGeneration = max(
            externallySupersededPeerGeneration ?? 0,
            peerGeneration
        )
    }

    private static func nextNonzero(
        _ value: UInt64
    ) -> UInt64 {
        let next = value &+ 1
        return next == 0 ? 1 : next
    }
}
