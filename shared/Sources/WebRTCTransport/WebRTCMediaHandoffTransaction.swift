import Foundation

/// Scalar cross-check supplied by native source preparation, not native authority itself.
/// The host retains its opaque source object and binds the offer ID to that object.
public struct WebRTCMediaHandoffSourceDescription: Sendable {
    public let videoID: String
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let playbackRate: Double
    public let observedAtUptime: Double
    public let deadlineUptime: Double

    public init(videoID: String, positionSeconds: Double, durationSeconds: Double,
                playbackRate: Double, observedAtUptime: Double, deadlineUptime: Double) {
        self.videoID = videoID; self.positionSeconds = positionSeconds; self.durationSeconds = durationSeconds
        self.playbackRate = playbackRate; self.observedAtUptime = observedAtUptime; self.deadlineUptime = deadlineUptime
    }

    func matches(_ item: WebRTCRemoteMediaItem, now: Double) -> Bool {
        let age = now - observedAtUptime
        guard age.isFinite, age >= 0, age < 2, observedAtUptime >= 0,
              deadlineUptime.isFinite, deadlineUptime > now,
              deadlineUptime - observedAtUptime <= 30, positionSeconds.isFinite,
              positionSeconds >= 0, positionSeconds < durationSeconds,
              durationSeconds.isFinite, durationSeconds <= 31_536_000,
              playbackRate.isFinite, playbackRate > 0, playbackRate <= 16,
              item.artwork?.videoID == videoID, item.duration == durationSeconds,
              item.playbackRate == playbackRate, let position = item.elapsedTime else { return false }
        return abs(position - (positionSeconds + age * playbackRate)) <= 2 * playbackRate + 0.25
    }
}

/// Only native source readback may justify `macPaused`. A timeout or missing reply is unknown,
/// never proof that the Mac did or did not pause. No result authorizes automatic replay/resume.
public enum WebRTCMediaHandoffResult: String, Codable, Equatable, Sendable {
    case macPaused, notApplied, outcomeUnknown
}

public struct WebRTCMediaHandoffCompletion: Equatable, Sendable {
    public let id: UUID
    public let result: WebRTCMediaHandoffResult
}

/// Exact transport admission, not independent evidence of acoustic output on the phone.
/// The host must match its previously prepared native source and perform native readback.
public struct WebRTCReceivedMediaHandoffCommit: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible {
    let envelope: WebRTCMediaHandoffCommitEnvelope
    let receiptID = UUID()
    let execution = WebRTCControlAuthorization()
    let deadlineUptime: Double
    private let continuityIsCurrent: @Sendable () -> Bool
    public var id: UUID { envelope.id }
    public var contextID: String { envelope.contextID }
    public var videoID: String { envelope.videoID }
    public var phonePositionSeconds: Double { envelope.phonePositionSeconds }
    public var isValid: Bool {
        execution.isValid && ProcessInfo.processInfo.systemUptime < deadlineUptime && continuityIsCurrent()
    }
    init(envelope: WebRTCMediaHandoffCommitEnvelope, deadlineUptime: Double,
         continuityIsCurrent: @escaping @Sendable () -> Bool) {
        self.envelope = envelope; self.deadlineUptime = deadlineUptime
        self.continuityIsCurrent = continuityIsCurrent
    }
    public var description: String { "[Beluga media handoff commit]" }
    public var debugDescription: String { description }
}

struct WebRTCMediaHandoffCommitEnvelope: Codable, Equatable, Sendable {
    let authorization: WebRTCRemoteMediaAuthorization
    let sequence: UInt64
    let id: UUID
    let contextID: String
    let videoID: String
    let phonePositionSeconds: Double
    let durationSeconds: Double
    let playbackRate: Double

    init(offer: WebRTCMediaHandoffOfferEnvelope, phonePositionSeconds: Double) {
        authorization = offer.authorization; sequence = offer.sequence; id = offer.id
        contextID = offer.contextID; videoID = offer.videoID
        durationSeconds = offer.durationSeconds; playbackRate = offer.playbackRate
        self.phonePositionSeconds = phonePositionSeconds
    }

    var isValid: Bool {
        sequence > 0 && !contextID.isEmpty
            && contextID.utf8.count <= WebRTCRemoteMediaItem.maximumContextIDBytes
            && !contextID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && WebRTCRemoteMediaArtworkReference(videoID: videoID) != nil
            && durationSeconds.isFinite && durationSeconds > 0 && durationSeconds <= 31_536_000
            && phonePositionSeconds.isFinite && phonePositionSeconds >= 0 && phonePositionSeconds < durationSeconds
            && playbackRate.isFinite && playbackRate > 0 && playbackRate <= 16
    }

    func matches(_ offer: WebRTCMediaHandoffOfferEnvelope) -> Bool {
        isValid && authorization == offer.authorization && sequence == offer.sequence && id == offer.id
            && contextID == offer.contextID && videoID == offer.videoID
            && durationSeconds == offer.durationSeconds && playbackRate == offer.playbackRate
    }
}

struct WebRTCMediaHandoffCompletionEnvelope: Codable, Equatable, Sendable {
    let commit: WebRTCMediaHandoffCommitEnvelope
    let result: WebRTCMediaHandoffResult
}

/// One admitted host execution and one viewer reply at a time, owned by the peer actor.
/// References escape only as revocable receipts, never as mutation-capable native objects.
struct MediaHandoffTransactions {
    private(set) var hostCommit: WebRTCReceivedMediaHandoffCommit?
    private(set) var hostReply: WebRTCMediaHandoffCompletionEnvelope?
    private(set) var viewerCommit: WebRTCMediaHandoffCommitEnvelope?

    var hostIsBusy: Bool { hostCommit != nil && hostReply == nil }

    mutating func admitHost(_ commit: WebRTCReceivedMediaHandoffCommit) -> Bool {
        guard !hostIsBusy else { return false }
        hostCommit?.execution.revoke()
        hostCommit = commit; hostReply = nil
        return true
    }

    mutating func finishHost(_ commit: WebRTCReceivedMediaHandoffCommit,
                             result: WebRTCMediaHandoffResult) -> WebRTCMediaHandoffCompletionEnvelope? {
        guard hostCommit?.receiptID == commit.receiptID, hostCommit?.envelope == commit.envelope else { return nil }
        if let hostReply { return hostReply.result == result ? hostReply : nil }
        commit.execution.revoke()
        let reply = WebRTCMediaHandoffCompletionEnvelope(commit: commit.envelope, result: result)
        hostReply = reply
        return reply
    }

    mutating func beginViewer(_ commit: WebRTCMediaHandoffCommitEnvelope) -> Bool {
        guard viewerCommit == nil, commit.isValid else { return false }
        viewerCommit = commit
        return true
    }

    mutating func receiveCompletion(_ reply: WebRTCMediaHandoffCompletionEnvelope) -> WebRTCMediaHandoffCompletion? {
        guard reply.commit == viewerCommit else { return nil }
        viewerCommit = nil
        return .init(id: reply.commit.id, result: reply.result)
    }

    mutating func expireViewer(id: UUID) -> WebRTCMediaHandoffCompletion? {
        guard viewerCommit?.id == id else { return nil }
        viewerCommit = nil
        return .init(id: id, result: .outcomeUnknown)
    }

    mutating func clear() -> WebRTCMediaHandoffCompletion? {
        let lost = viewerCommit.map { WebRTCMediaHandoffCompletion(id: $0.id, result: .outcomeUnknown) }
        hostCommit?.execution.revoke()
        hostCommit = nil; hostReply = nil; viewerCommit = nil
        return lost
    }
}
