import Foundation

/// An ephemeral source description, not playback, Pause, input, or successful-transfer authority.
/// Only the current receiving peer can consume this exact receipt. It never contains a URL.
public struct WebRTCReceivedMediaHandoffOffer: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible {
    public let id: UUID
    public let contextID: String
    public let videoID: String
    public let positionSeconds: TimeInterval
    public let durationSeconds: TimeInterval
    public let playbackRate: Double
    public let deadlineUptime: TimeInterval
    public let receivedAtUptime: TimeInterval
    let envelope: WebRTCMediaHandoffOfferEnvelope
    let receiptToken: UUID

    init(envelope: WebRTCMediaHandoffOfferEnvelope, receivedAtUptime: TimeInterval) {
        self.envelope = envelope
        receiptToken = UUID()
        id = envelope.id
        contextID = envelope.contextID
        videoID = envelope.videoID
        positionSeconds = envelope.positionSeconds
        durationSeconds = envelope.durationSeconds
        playbackRate = envelope.playbackRate
        deadlineUptime = receivedAtUptime + envelope.validForSeconds
        self.receivedAtUptime = receivedAtUptime
    }

    public var description: String { "[Beluga media handoff offer]" }
    public var debugDescription: String { description }
}

struct WebRTCMediaHandoffOfferEnvelope: Codable, Equatable, Sendable {
    static let maximumLifetime: TimeInterval = 30
    static let maximumSnapshotAge: TimeInterval = 2
    let authorization: WebRTCRemoteMediaAuthorization
    let sequence: UInt64
    let id: UUID
    let observedRevision: UInt64
    let contextID: String
    let videoID: String
    let positionSeconds: TimeInterval
    let durationSeconds: TimeInterval
    let playbackRate: Double
    let validForSeconds: TimeInterval

    var isValid: Bool {
        sequence > 0 && observedRevision > 0
            && !contextID.isEmpty
            && contextID.utf8.count <= WebRTCRemoteMediaItem.maximumContextIDBytes
            && !contextID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && WebRTCRemoteMediaArtworkReference(videoID: videoID) != nil
            && positionSeconds.isFinite && positionSeconds >= 0
            && durationSeconds.isFinite && durationSeconds > 0 && durationSeconds <= 31_536_000
            && positionSeconds < durationSeconds
            && playbackRate.isFinite && playbackRate > 0 && playbackRate <= 16
            && validForSeconds.isFinite && validForSeconds > 0
            && validForSeconds <= Self.maximumLifetime
    }

    static func eligiblePrimary(in update: WebRTCRemoteMediaStateUpdate) -> WebRTCRemoteMediaItem? {
        guard update.isValid, let item = update.item, item.sourceName == "YouTube",
              item.artwork?.provider == .youtube, item.playbackState == .playing,
              item.playbackRate > 0, item.capabilities.canPause, item.capabilities.canSeekToPosition,
              let position = item.elapsedTime, let duration = item.duration,
              position.isFinite, duration.isFinite, duration > 0, position >= 0, position < duration else { return nil }
        return item
    }

    func matchesPrimary(in update: WebRTCRemoteMediaStateUpdate) -> Bool {
        guard let item = Self.eligiblePrimary(in: update) else { return false }
        return item.contextID == contextID && item.artwork?.videoID == videoID
            && item.duration == durationSeconds && item.playbackRate == playbackRate
            && update.revision >= observedRevision
    }
}
