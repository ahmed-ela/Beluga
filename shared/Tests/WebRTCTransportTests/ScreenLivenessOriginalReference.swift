import Foundation
@testable import WebRTCTransport

// Frozen original policy: only the classifier type is renamed; never called in production.
/// Constant-space liveness classifier. It retains only the preceding sample and the time of the
/// latest observed pixel-content change; all output is deterministic from explicit inputs.
public struct FrozenWorldwideScreenLivenessClassifier: Sendable {
    public static let freshPresentationWindowNanoseconds: UInt64 = 2_500_000_000

    private var previousSample: WorldwideScreenLivenessSample?
    private var lastContentChangeUptimeNanoseconds: UInt64?

    public init() {}

    public mutating func reset() {
        previousSample = nil
        lastContentChangeUptimeNanoseconds = nil
    }

    public mutating func observe(
        _ sample: WorldwideScreenLivenessSample
    ) -> WorldwideScreenLivenessDiagnosticSnapshot {
        let resetReason = resetReason(for: sample)
        let comparison = resetReason == .none ? previousSample : nil
        let deltas = Deltas(current: sample, previous: comparison)

        if resetReason != .none {
            lastContentChangeUptimeNanoseconds = nil
        } else if deltas.contentChanges.map({ $0 > 0 }) == true {
            lastContentChangeUptimeNanoseconds = sample.observedAtUptimeNanoseconds
        }

        let presentationAge = Self.presentationAgeMilliseconds(
            now: sample.observedAtUptimeNanoseconds,
            presentedAt: sample.renderObservation?.presentedAtUptimeNanoseconds
        )
        let state = classify(
            sample,
            resetReason: resetReason,
            deltas: deltas,
            presentationAgeMilliseconds: presentationAge
        )
        let inbound = sample.inboundVideo
        let render = sample.renderObservation
        let snapshot = WorldwideScreenLivenessDiagnosticSnapshot(
            state: state,
            resetReason: resetReason,
            generation: sample.generation,
            trackAttached: sample.hasRemoteVideoTrack,
            coverState: sample.coverState,
            inboundBytes: inbound?.bytes,
            inboundByteDelta: deltas.inboundBytes,
            inboundPackets: inbound?.packets,
            inboundPacketDelta: deltas.inboundPackets,
            decodedFrames: inbound?.framesEncodedOrDecoded,
            decodedFrameDelta: deltas.decodedFrames,
            presentedFrames: render?.presentedFrames,
            presentedFrameDelta: deltas.presentedFrames,
            contentSamples: render?.contentSamples,
            contentSampleDelta: deltas.contentSamples,
            contentChanges: render?.contentChanges,
            contentChangeDelta: deltas.contentChanges,
            lastPresentationAgeMilliseconds: presentationAge,
            frameWidth: Self.validDimension(render?.frameWidth) ?? Self.validDimension(inbound?.frameWidth),
            frameHeight: Self.validDimension(render?.frameHeight) ?? Self.validDimension(inbound?.frameHeight),
            framesPerSecond: Self.validFramesPerSecond(inbound?.framesPerSecond)
        )
        previousSample = sample
        return snapshot
    }

    private mutating func classify(
        _ sample: WorldwideScreenLivenessSample,
        resetReason: WorldwideScreenLivenessResetReason,
        deltas: Deltas,
        presentationAgeMilliseconds: UInt64?
    ) -> WorldwideScreenLivenessState {
        if sample.coverState == .intentionalBandwidthPause {
            return .intentionallyCovered
        }
        if sample.coverState != .none {
            return .covered
        }
        guard sample.hasRemoteVideoTrack else {
            return .trackMissing
        }
        guard resetReason == .none else {
            return .awaitingEvidence
        }

        let presentationIsFresh = presentationAgeMilliseconds.map {
            $0 <= Self.freshPresentationWindowNanoseconds / 1_000_000
        } == true
        let contentChangeIsFresh = lastContentChangeUptimeNanoseconds.map {
            sample.observedAtUptimeNanoseconds >= $0
                && sample.observedAtUptimeNanoseconds - $0
                    <= Self.freshPresentationWindowNanoseconds
        } == true

        if deltas.presentedFrames.map({ $0 > 0 }) == true {
            return deltas.contentChanges.map({ $0 > 0 }) == true
                ? .presentingLive
                : .presentingUnchanged
        }
        if presentationIsFresh,
           sample.renderObservation?.contentSamples ?? 0 > 0 {
            return contentChangeIsFresh ? .presentingLive : .presentingUnchanged
        }

        let inboundDeltas = [deltas.inboundBytes, deltas.inboundPackets]
            .compactMap { $0 }
        if !inboundDeltas.isEmpty,
           inboundDeltas.allSatisfy({ $0 == 0 }) {
            return .inboundRTPStalled
        }
        if inboundDeltas.contains(where: { $0 > 0 }) {
            if let decodedFrames = deltas.decodedFrames {
                return decodedFrames > 0 ? .presentationStalled : .decodeStalled
            }
            return .awaitingEvidence
        }
        if deltas.decodedFrames.map({ $0 > 0 }) == true {
            return .presentationStalled
        }
        return .awaitingEvidence
    }

    private func resetReason(
        for sample: WorldwideScreenLivenessSample
    ) -> WorldwideScreenLivenessResetReason {
        guard let previousSample else { return .initialSample }
        guard previousSample.generation == sample.generation else {
            return .generationChanged
        }
        return Self.counterRegressed(current: sample, previous: previousSample)
            ? .counterRegression
            : .none
    }

    private static func counterRegressed(
        current: WorldwideScreenLivenessSample,
        previous: WorldwideScreenLivenessSample
    ) -> Bool {
        let pairs: [(UInt64?, UInt64?)] = [
            (current.inboundVideo?.bytes, previous.inboundVideo?.bytes),
            (current.inboundVideo?.packets, previous.inboundVideo?.packets),
            (
                current.inboundVideo?.framesEncodedOrDecoded,
                previous.inboundVideo?.framesEncodedOrDecoded
            ),
            (
                current.renderObservation?.presentedFrames,
                previous.renderObservation?.presentedFrames
            ),
            (
                current.renderObservation?.contentSamples,
                previous.renderObservation?.contentSamples
            ),
            (
                current.renderObservation?.contentChanges,
                previous.renderObservation?.contentChanges
            ),
        ]
        return pairs.contains { current, previous in
            guard let current, let previous else { return false }
            return current < previous
        }
    }

    private static func presentationAgeMilliseconds(
        now: UInt64,
        presentedAt: UInt64?
    ) -> UInt64? {
        guard let presentedAt else { return nil }
        let nanoseconds = now >= presentedAt ? now - presentedAt : 0
        return min(
            nanoseconds / 1_000_000,
            WorldwideScreenLivenessDiagnosticSnapshot
                .maximumPresentationAgeMilliseconds
        )
    }

    private static func validDimension(_ value: Int?) -> Int? {
        guard let value, (1 ... 32_768).contains(value) else { return nil }
        return value
    }

    private static func validFramesPerSecond(_ value: Double?) -> Double? {
        guard let value,
              value.isFinite,
              (0 ... 1_000).contains(value) else { return nil }
        return value
    }

    private struct Deltas {
        let inboundBytes: UInt64?
        let inboundPackets: UInt64?
        let decodedFrames: UInt64?
        let presentedFrames: UInt64?
        let contentSamples: UInt64?
        let contentChanges: UInt64?

        init(
            current: WorldwideScreenLivenessSample,
            previous: WorldwideScreenLivenessSample?
        ) {
            inboundBytes = Self.delta(
                current.inboundVideo?.bytes,
                previous?.inboundVideo?.bytes
            )
            inboundPackets = Self.delta(
                current.inboundVideo?.packets,
                previous?.inboundVideo?.packets
            )
            decodedFrames = Self.delta(
                current.inboundVideo?.framesEncodedOrDecoded,
                previous?.inboundVideo?.framesEncodedOrDecoded
            )
            presentedFrames = Self.delta(
                current.renderObservation?.presentedFrames,
                previous?.renderObservation?.presentedFrames
            )
            contentSamples = Self.delta(
                current.renderObservation?.contentSamples,
                previous?.renderObservation?.contentSamples
            )
            contentChanges = Self.delta(
                current.renderObservation?.contentChanges,
                previous?.renderObservation?.contentChanges
            )
        }

        private static func delta(_ current: UInt64?, _ previous: UInt64?) -> UInt64? {
            guard let current, let previous, current >= previous else { return nil }
            return current - previous
        }
    }
}
