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

/// Bounded state owned exclusively by WebRTCPeer. Snapshot checks reject observable timeline
/// discontinuities, not every possible small native seek: the existing wire has no seek epoch
/// or native observation timestamp. They never authorize a host mutation.
struct MediaHandoffOffers {
    private struct Timeline {
        let envelope: WebRTCMediaHandoffOfferEnvelope
        let origin: TimeInterval
        let deadline: TimeInterval
        var lastObservation: TimeInterval
        var lastPosition: TimeInterval

        init(envelope: WebRTCMediaHandoffOfferEnvelope, now: TimeInterval) {
            self.envelope = envelope
            origin = now
            deadline = now + envelope.validForSeconds
            lastObservation = now
            lastPosition = envelope.positionSeconds
        }

        mutating func observe(_ update: WebRTCRemoteMediaStateUpdate, now: TimeInterval) -> Bool {
            guard now.isFinite, now >= lastObservation, now < deadline,
                  envelope.matchesPrimary(in: update), let position = update.item?.elapsedTime,
                  position >= lastPosition else { return false }
            let expected = envelope.positionSeconds + (now - origin) * envelope.playbackRate
            let uncertainty = WebRTCMediaHandoffOfferEnvelope.maximumSnapshotAge * envelope.playbackRate + 0.25
            guard abs(position - expected) <= uncertainty else { return false }
            lastObservation = now
            lastPosition = position
            return true
        }
    }

    private var nextSentSequence: UInt64 = 1
    private var highestReceivedSequence: UInt64 = 0
    private var sent: Timeline?
    private var received: (receipt: WebRTCReceivedMediaHandoffOffer, timeline: Timeline)?
    private var sentStateAt: TimeInterval?
    private var receivedStateAt: TimeInterval?

    mutating func recordSentState(_ update: WebRTCRemoteMediaStateUpdate, now: TimeInterval) {
        sentStateAt = now.isFinite ? now : nil
        if var pending = sent {
            sent = pending.observe(update, now: now) ? pending : nil
        }
    }

    mutating func recordReceivedState(_ update: WebRTCRemoteMediaStateUpdate, now: TimeInterval) {
        receivedStateAt = now.isFinite ? now : nil
        if var pending = received {
            received = pending.timeline.observe(update, now: now) ? pending : nil
        }
    }

    mutating func prepareSent(contextID: String, update: WebRTCRemoteMediaStateUpdate,
                              authorization: WebRTCRemoteMediaAuthorization,
                              now: TimeInterval, id: UUID = UUID(),
                              source: WebRTCMediaHandoffSourceDescription? = nil) -> WebRTCMediaHandoffOfferEnvelope? {
        if let pending = sent, now >= pending.deadline { sent = nil }
        guard sent == nil, fresh(sentStateAt, now: now), nextSentSequence < UInt64.max,
              let item = WebRTCMediaHandoffOfferEnvelope.eligiblePrimary(in: update),
              item.contextID == contextID, let videoID = item.artwork?.videoID,
              let position = item.elapsedTime, let duration = item.duration,
              source.map({ $0.matches(item, now: now) }) ?? true else { return nil }
        let envelope = WebRTCMediaHandoffOfferEnvelope(authorization: authorization,
            sequence: nextSentSequence, id: id, observedRevision: update.revision,
            contextID: contextID, videoID: videoID, positionSeconds: position,
            durationSeconds: duration, playbackRate: item.playbackRate,
            validForSeconds: min(WebRTCMediaHandoffOfferEnvelope.maximumLifetime,
                source.map { $0.deadlineUptime - now } ?? WebRTCMediaHandoffOfferEnvelope.maximumLifetime))
        guard envelope.isValid else { return nil }
        nextSentSequence += 1
        sent = Timeline(envelope: envelope, now: now)
        return envelope
    }

    mutating func sentFailed(id: UUID) {
        if sent?.envelope.id == id { sent = nil }
    }

    /// A matching commit consumes the sent offer before validation: refreshed snapshots
    /// cannot revive a rejected timeline. The native source remains independently guarded.
    mutating func consumeSent(_ commit: WebRTCMediaHandoffCommitEnvelope,
                             state: WebRTCRemoteMediaStateUpdate,
                             now: TimeInterval) -> TimeInterval? {
        guard var pending = sent, commit.matches(pending.envelope) else { return nil }
        sent = nil
        guard fresh(sentStateAt, now: now), pending.observe(state, now: now) else { return nil }
        let expected = pending.envelope.positionSeconds + (now - pending.origin) * pending.envelope.playbackRate
        guard abs(commit.phonePositionSeconds - expected) <= 2 + 2 * pending.envelope.playbackRate else { return nil }
        return pending.deadline
    }

    mutating func prepareCommit(_ receipt: WebRTCReceivedMediaHandoffOffer,
                               phonePositionSeconds: Double, observedAtUptime: Double,
                               state: WebRTCReceivedRemoteMediaState,
                               now: Double) -> WebRTCMediaHandoffCommitEnvelope? {
        let commit = WebRTCMediaHandoffCommitEnvelope(offer: receipt.envelope, phonePositionSeconds: phonePositionSeconds)
        guard commit.isValid, now.isFinite, observedAtUptime.isFinite,
              now >= observedAtUptime, now - observedAtUptime <= 0.75,
              consume(receipt, state: state, now: now) else { return nil }
        return commit
    }

    mutating func receive(_ envelope: WebRTCMediaHandoffOfferEnvelope,
                         state: WebRTCReceivedRemoteMediaState,
                         now: TimeInterval) -> WebRTCReceivedMediaHandoffOffer? {
        guard envelope.isValid, envelope.authorization == state.authorization,
              envelope.sequence > highestReceivedSequence else { return nil }
        // Consume the sequence even if its source has become stale. A later snapshot cannot
        // revive a previously rejected offer or renew its original deadline.
        highestReceivedSequence = envelope.sequence
        received = nil
        guard fresh(receivedStateAt, now: now), envelope.observedRevision == state.update.revision,
              envelope.matchesPrimary(in: state.update), state.update.item?.elapsedTime == envelope.positionSeconds else { return nil }
        let receipt = WebRTCReceivedMediaHandoffOffer(envelope: envelope, receivedAtUptime: now)
        received = (receipt, Timeline(envelope: envelope, now: now))
        return receipt
    }

    mutating func consume(_ receipt: WebRTCReceivedMediaHandoffOffer,
                         state: WebRTCReceivedRemoteMediaState,
                         now: TimeInterval) -> Bool {
        guard var pending = received, pending.receipt == receipt else { return false }
        received = nil
        return receipt.envelope.authorization == state.authorization
            && fresh(receivedStateAt, now: now)
            && pending.timeline.observe(state.update, now: now)
    }

    mutating func discard(_ receipt: WebRTCReceivedMediaHandoffOffer) {
        if received?.receipt == receipt { received = nil }
    }

    mutating func clearTransient() {
        sent = nil
        received = nil
        sentStateAt = nil
        receivedStateAt = nil
    }

    private func fresh(_ observed: TimeInterval?, now: TimeInterval) -> Bool {
        guard let observed, observed.isFinite, now.isFinite else { return false }
        let age = now - observed
        return age >= 0 && age < WebRTCMediaHandoffOfferEnvelope.maximumSnapshotAge
    }
}
