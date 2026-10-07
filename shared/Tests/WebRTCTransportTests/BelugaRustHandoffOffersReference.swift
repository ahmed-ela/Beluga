// Independent test-only transcription of the original Swift offer/timeline reducer.
// General catalog and video-ID validation stay native; handoff predicates do not
// delegate to production policy. This reference never owns native dispatch authority.
import Foundation
@testable import WebRTCTransport

struct BelugaRustHandoffOffersReference {
    private struct Timeline {
        let envelope: WebRTCMediaHandoffOfferEnvelope
        let origin: Double
        let deadline: Double
        var lastObservation: Double
        var lastPosition: Double

        init(envelope: WebRTCMediaHandoffOfferEnvelope, now: Double) {
            self.envelope = envelope
            origin = now
            deadline = now + envelope.validForSeconds
            lastObservation = now
            lastPosition = envelope.positionSeconds
        }

        mutating func observe(_ update: WebRTCRemoteMediaStateUpdate, now: Double) -> Bool {
            guard now.isFinite, now >= lastObservation, now < deadline,
                  BelugaRustHandoffOffersReference.matchesPrimary(envelope, update),
                  let position = update.item?.elapsedTime,
                  position >= lastPosition else { return false }
            let expected = envelope.positionSeconds + (now - origin) * envelope.playbackRate
            let uncertainty = 2 * envelope.playbackRate + 0.25
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
    private var sentStateAt: Double?
    private var receivedStateAt: Double?

    init() {}

    init(testingNextSentSequence: UInt64, highestReceivedSequence: UInt64) {
        precondition(testingNextSentSequence > 0)
        nextSentSequence = testingNextSentSequence
        self.highestReceivedSequence = highestReceivedSequence
    }

    mutating func recordSentState(_ update: WebRTCRemoteMediaStateUpdate, now: Double) {
        sentStateAt = now.isFinite ? now : nil
        if var pending = sent {
            sent = pending.observe(update, now: now) ? pending : nil
        }
    }

    mutating func recordReceivedState(_ update: WebRTCRemoteMediaStateUpdate, now: Double) {
        receivedStateAt = now.isFinite ? now : nil
        if var pending = received {
            received = pending.timeline.observe(update, now: now) ? pending : nil
        }
    }

    mutating func prepareSent(contextID: String, update: WebRTCRemoteMediaStateUpdate,
                              authorization: WebRTCRemoteMediaAuthorization,
                              now: Double, id: UUID,
                              source: WebRTCMediaHandoffSourceDescription? = nil)
        -> WebRTCMediaHandoffOfferEnvelope? {
        if let pending = sent, now >= pending.deadline { sent = nil }
        guard sent == nil, Self.fresh(sentStateAt, now: now), nextSentSequence < UInt64.max,
              let item = Self.eligiblePrimary(update), item.contextID == contextID,
              let videoID = item.artwork?.videoID, let position = item.elapsedTime,
              let duration = item.duration,
              source.map({ Self.sourceMatches($0, item: item, now: now) }) ?? true else { return nil }
        let envelope = WebRTCMediaHandoffOfferEnvelope(authorization: authorization,
            sequence: nextSentSequence, id: id, observedRevision: update.revision,
            contextID: contextID, videoID: videoID, positionSeconds: position,
            durationSeconds: duration, playbackRate: item.playbackRate,
            validForSeconds: min(30, source.map { $0.deadlineUptime - now } ?? 30))
        guard Self.offerIsValid(envelope) else { return nil }
        nextSentSequence += 1
        sent = Timeline(envelope: envelope, now: now)
        return envelope
    }

    mutating func sentFailed(id: UUID) {
        if sent?.envelope.id == id { sent = nil }
    }

    mutating func consumeSent(_ commit: WebRTCMediaHandoffCommitEnvelope,
                             state: WebRTCRemoteMediaStateUpdate, now: Double) -> Double? {
        guard var pending = sent, Self.commitMatches(commit, pending.envelope) else { return nil }
        sent = nil
        guard Self.fresh(sentStateAt, now: now), pending.observe(state, now: now) else { return nil }
        let expected = pending.envelope.positionSeconds + (now - pending.origin) * pending.envelope.playbackRate
        guard abs(commit.phonePositionSeconds - expected) <= 2 + 2 * pending.envelope.playbackRate else { return nil }
        return pending.deadline
    }

    mutating func prepareCommit(_ receipt: WebRTCReceivedMediaHandoffOffer,
                               phonePositionSeconds: Double, observedAtUptime: Double,
                               state: WebRTCReceivedRemoteMediaState,
                               now: Double) -> WebRTCMediaHandoffCommitEnvelope? {
        let commit = WebRTCMediaHandoffCommitEnvelope(offer: receipt.envelope,
                                                     phonePositionSeconds: phonePositionSeconds)
        guard Self.commitIsValid(commit), now.isFinite, observedAtUptime.isFinite,
              now >= observedAtUptime, now - observedAtUptime <= 0.75,
              consume(receipt, state: state, now: now) else { return nil }
        return commit
    }

    mutating func receive(_ envelope: WebRTCMediaHandoffOfferEnvelope,
                         state: WebRTCReceivedRemoteMediaState,
                         now: Double) -> WebRTCReceivedMediaHandoffOffer? {
        guard Self.offerIsValid(envelope), envelope.authorization == state.authorization,
              envelope.sequence > highestReceivedSequence else { return nil }
        highestReceivedSequence = envelope.sequence
        received = nil
        guard Self.fresh(receivedStateAt, now: now),
              envelope.observedRevision == state.update.revision,
              Self.matchesPrimary(envelope, state.update),
              state.update.item?.elapsedTime == envelope.positionSeconds else { return nil }
        let receipt = WebRTCReceivedMediaHandoffOffer(envelope: envelope, receivedAtUptime: now)
        received = (receipt, Timeline(envelope: envelope, now: now))
        return receipt
    }

    mutating func consume(_ receipt: WebRTCReceivedMediaHandoffOffer,
                         state: WebRTCReceivedRemoteMediaState, now: Double) -> Bool {
        guard var pending = received, pending.receipt == receipt else { return false }
        received = nil
        return receipt.envelope.authorization == state.authorization
            && Self.fresh(receivedStateAt, now: now)
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

    private static func fresh(_ observed: Double?, now: Double) -> Bool {
        guard let observed, observed.isFinite, now.isFinite else { return false }
        let age = now - observed
        return age >= 0 && age < 2
    }

    // These helpers freeze the original handoff predicates independently of a
    // future Rust adapter. General remote-catalog/11-byte video-ID validation
    // still uses native protocol types because it is outside this reducer seam.
    private static func offerIsValid(_ envelope: WebRTCMediaHandoffOfferEnvelope) -> Bool {
        envelope.sequence > 0 && envelope.observedRevision > 0
            && !envelope.contextID.isEmpty
            && envelope.contextID.utf8.count <= WebRTCRemoteMediaItem.maximumContextIDBytes
            && !envelope.contextID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && WebRTCRemoteMediaArtworkReference(videoID: envelope.videoID) != nil
            && envelope.positionSeconds.isFinite && envelope.positionSeconds >= 0
            && envelope.durationSeconds.isFinite && envelope.durationSeconds > 0
            && envelope.durationSeconds <= 31_536_000 && envelope.positionSeconds < envelope.durationSeconds
            && envelope.playbackRate.isFinite && envelope.playbackRate > 0 && envelope.playbackRate <= 16
            && envelope.validForSeconds.isFinite && envelope.validForSeconds > 0 && envelope.validForSeconds <= 30
    }

    private static func eligiblePrimary(_ update: WebRTCRemoteMediaStateUpdate) -> WebRTCRemoteMediaItem? {
        guard update.isValid, let item = update.item, item.sourceName == "YouTube",
              item.artwork?.provider == .youtube, item.playbackState == .playing,
              item.playbackRate > 0, item.capabilities.canPause, item.capabilities.canSeekToPosition,
              let position = item.elapsedTime, let duration = item.duration,
              position.isFinite, duration.isFinite, duration > 0,
              position >= 0, position < duration else { return nil }
        return item
    }

    private static func matchesPrimary(_ envelope: WebRTCMediaHandoffOfferEnvelope,
                                       _ update: WebRTCRemoteMediaStateUpdate) -> Bool {
        guard let item = eligiblePrimary(update) else { return false }
        return item.contextID == envelope.contextID && item.artwork?.videoID == envelope.videoID
            && item.duration == envelope.durationSeconds && item.playbackRate == envelope.playbackRate
            && update.revision >= envelope.observedRevision
    }

    private static func sourceMatches(_ source: WebRTCMediaHandoffSourceDescription,
                                      item: WebRTCRemoteMediaItem, now: Double) -> Bool {
        let age = now - source.observedAtUptime
        guard age.isFinite, age >= 0, age < 2, source.observedAtUptime >= 0,
              source.deadlineUptime.isFinite, source.deadlineUptime > now,
              source.deadlineUptime - source.observedAtUptime <= 30,
              source.positionSeconds.isFinite, source.positionSeconds >= 0,
              source.positionSeconds < source.durationSeconds,
              source.durationSeconds.isFinite, source.durationSeconds <= 31_536_000,
              source.playbackRate.isFinite, source.playbackRate > 0, source.playbackRate <= 16,
              item.artwork?.videoID == source.videoID, item.duration == source.durationSeconds,
              item.playbackRate == source.playbackRate, let position = item.elapsedTime else { return false }
        return abs(position - (source.positionSeconds + age * source.playbackRate)) <= 2 * source.playbackRate + 0.25
    }

    private static func commitIsValid(_ commit: WebRTCMediaHandoffCommitEnvelope) -> Bool {
        commit.sequence > 0 && !commit.contextID.isEmpty
            && commit.contextID.utf8.count <= WebRTCRemoteMediaItem.maximumContextIDBytes
            && !commit.contextID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && WebRTCRemoteMediaArtworkReference(videoID: commit.videoID) != nil
            && commit.durationSeconds.isFinite && commit.durationSeconds > 0 && commit.durationSeconds <= 31_536_000
            && commit.phonePositionSeconds.isFinite && commit.phonePositionSeconds >= 0
            && commit.phonePositionSeconds < commit.durationSeconds
            && commit.playbackRate.isFinite && commit.playbackRate > 0 && commit.playbackRate <= 16
    }

    private static func commitMatches(_ commit: WebRTCMediaHandoffCommitEnvelope,
                                      _ offer: WebRTCMediaHandoffOfferEnvelope) -> Bool {
        commitIsValid(commit) && commit.authorization == offer.authorization
            && commit.sequence == offer.sequence && commit.id == offer.id
            && commit.contextID == offer.contextID && commit.videoID == offer.videoID
            && commit.durationSeconds == offer.durationSeconds && commit.playbackRate == offer.playbackRate
    }
}
