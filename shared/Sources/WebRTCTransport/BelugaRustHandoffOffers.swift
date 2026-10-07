import BelugaCore
import Foundation

/// Checks copied-result custody, not a second offers reducer. Exact native
/// payloads remain in the peer; Rust alone chooses admission and consumption.
enum BelugaRustHandoffOffersBoundary {
    typealias State = beluga_core_handoff_offers_state_t
    typealias Event = beluga_core_handoff_offers_event_t
    typealias Output = beluga_core_handoff_offers_result_t
    typealias Timeline = beluga_core_handoff_offers_timeline_t

    static func accepts(before: State, event: Event, output: Output) -> Bool {
        let after = output.state
        guard valid(before), valid(after), before.terminal == 0, after.terminal == 0,
              event.opcode <= 9, event.reserved == 0, event.envelope.reserved == 0,
              event.primary.flags & ~UInt64(511) == 0,
              event.primary.native_matches & ~UInt64(12) == 0,
              event.native_matches & ~UInt64(15) == 0, event.envelope.text_valid <= 1,
              event.source.present <= 1, event.source.video_equal <= 1,
              output.status == 0, output.reserved == 0, output.decision <= 5,
              output.effects & ~UInt32(15) == 0 else { return false }

        let retiresSent = before.sent.token != 0 && before.sent.token != after.sent.token
        let retiresReceived = before.received.token != 0 && before.received.token != after.received.token
        let mintsSent = after.sent.token != 0 && before.sent.token != after.sent.token
        let mintsReceived = after.received.token != 0 && before.received.token != after.received.token
        guard (output.effects & 1 != 0) == retiresSent,
              (output.effects & 2 != 0) == retiresReceived,
              (output.effects & 4 != 0) == mintsSent,
              (output.effects & 8 != 0) == mintsReceived,
              output.retired_sent == (retiresSent ? before.sent.token : 0),
              output.retired_received == (retiresReceived ? before.received.token : 0),
              !retiresSent || [0, 2, 3, 4, 9].contains(event.opcode),
              !retiresReceived || [1, 5, 6, 7, 8, 9].contains(event.opcode),
              !mintsSent || event.opcode == 2,
              !mintsReceived || event.opcode == 5,
              !(mintsSent && mintsReceived) else { return false }

        if mintsSent {
            guard before.next_sent < UInt64.max, after.next_sent == before.next_sent + 1,
                  freshToken(event.token, before: before), after.sent.token == event.token,
                  output.decision == 1, event.primary.flags == 511,
                  event.native_matches & 4 != 0, event.envelope.text_valid == 1,
                  event.source.present == 0 || event.source.video_equal == 1 else { return false }
            let lifetime = event.source.present == 0 ? 30
                : min(30, number(event.source.deadline) - number(event.now))
            guard minted(after.sent, token: event.token, sequence: before.next_sent,
                         revision: event.primary.revision, position: event.primary.position,
                         duration: event.primary.duration, rate: event.primary.rate,
                         lifetime: lifetime.bitPattern, now: event.now) else { return false }
        } else if after.next_sent != before.next_sent { return false }

        if after.highest_received != before.highest_received {
            guard event.opcode == 5, event.native_matches & 1 != 0,
                  validOfferPayload(event.envelope),
                  event.envelope.sequence > before.highest_received,
                  after.highest_received == event.envelope.sequence else { return false }
        }
        // An authorized valid higher wire offer burns its sequence before late
        // admission, including when there is no previous native owner to retire.
        if event.opcode == 5 && event.native_matches & 1 != 0
            && validOfferPayload(event.envelope)
            && event.envelope.sequence > before.highest_received
            && after.highest_received != event.envelope.sequence { return false }
        if mintsReceived {
            guard freshToken(event.token, before: before), after.received.token == event.token,
                  output.decision == 2, event.primary.flags == 511,
                  event.primary.native_matches == 12, event.native_matches & 1 != 0,
                  event.envelope.text_valid == 1,
                  after.highest_received == event.envelope.sequence,
                  event.envelope.sequence > before.highest_received,
                  minted(after.received, token: event.token, sequence: event.envelope.sequence,
                         revision: event.envelope.revision, position: event.envelope.position,
                         duration: event.envelope.duration, rate: event.envelope.rate,
                         lifetime: event.envelope.lifetime, now: event.now) else { return false }
        }

        guard clocksMatch(before: before, after: after, event: event),
              retained(before.sent, after.sent, recordOpcode: 0, event: event),
              retained(before.received, after.received, recordOpcode: 1, event: event) else { return false }
        if event.opcode == 9 && (after.presence != 0 || output.decision != 0) { return false }
        if event.opcode == 3 && retiresSent && event.token != before.sent.token { return false }
        if event.opcode == 8 && retiresReceived && event.token != before.received.token { return false }
        if event.opcode == 4 && retiresSent {
            guard event.native_matches == 15, event.envelope.text_valid == 1,
                  event.envelope.sequence == before.sent.sequence,
                  number(event.envelope.duration) == number(before.sent.duration),
                  number(event.envelope.rate) == number(before.sent.rate),
                  validPhonePayload(event) else { return false }
        }
        if [6, 7].contains(event.opcode) && retiresReceived {
            guard event.token == before.received.token else { return false }
            if event.opcode == 7 && (!validPhonePayload(event) || !validPhoneObservation(event)) { return false }
        }
        if event.opcode == 5 && retiresReceived {
            guard event.native_matches & 1 != 0, validOfferPayload(event.envelope),
                  event.envelope.sequence > before.highest_received,
                  after.highest_received == event.envelope.sequence else { return false }
        }
        if event.opcode == 3 && before.sent.token != 0 && event.token == before.sent.token && !retiresSent {
            return false
        }
        if [6, 8].contains(event.opcode) && before.received.token != 0
            && event.token == before.received.token && !retiresReceived { return false }
        if event.opcode == 7 && before.received.token != 0
            && event.token == before.received.token && validPhonePayload(event)
            && validPhoneObservation(event) && !retiresReceived { return false }
        if event.opcode == 4 && before.sent.token != 0 && event.native_matches == 15
            && event.envelope.sequence == before.sent.sequence
            && number(event.envelope.duration) == number(before.sent.duration)
            && number(event.envelope.rate) == number(before.sent.rate)
            && validPhonePayload(event) && !retiresSent { return false }

        switch output.decision {
        case 0:
            return !mintsSent && !mintsReceived && emptyDescriptors(output)
        case 1, 2:
            let timeline = output.decision == 1 ? after.sent : after.received
            return (output.decision == 1 ? mintsSent : mintsReceived)
                && output.minted_token == event.token && output.sequence == timeline.sequence
                && output.lifetime == timeline.lifetime && output.deadline == timeline.deadline
        case 3, 5:
            guard event.opcode == (output.decision == 3 ? 6 : 7),
                  retiresReceived, !retiresSent, !mintsSent, !mintsReceived,
                  event.token == before.received.token,
                  event.native_matches & 1 != 0, event.primary.flags == 511,
                  event.primary.native_matches == 12,
                  emptyDescriptors(output) else { return false }
            return output.decision != 5 || event.envelope.text_valid == 1
        case 4:
            return event.opcode == 4 && retiresSent && !retiresReceived && !mintsSent && !mintsReceived
                && event.native_matches == 15 && event.primary.native_matches == 12
                && event.primary.flags == 511 && event.envelope.text_valid == 1
                && event.envelope.sequence == before.sent.sequence
                && number(event.envelope.duration) == number(before.sent.duration)
                && number(event.envelope.rate) == number(before.sent.rate)
                && output.minted_token == 0 && output.sequence == 0 && output.lifetime == 0
                && output.deadline == before.sent.deadline
        default: return false
        }
    }

    private static func freshToken(_ token: UInt64, before: State) -> Bool {
        token != 0 && token != before.sent.token && token != before.received.token
    }

    private static func emptyDescriptors(_ output: Output) -> Bool {
        output.minted_token == 0 && output.sequence == 0 && output.lifetime == 0 && output.deadline == 0
    }

    // Wire payload sanity before retirement; freshness/drift choices stay in Rust.
    private static func validOfferPayload(_ envelope: beluga_core_handoff_offers_envelope_t) -> Bool {
        let position = number(envelope.position), duration = number(envelope.duration)
        let rate = number(envelope.rate), lifetime = number(envelope.lifetime)
        return envelope.text_valid == 1 && envelope.sequence != 0 && envelope.revision != 0
            && position.isFinite && position >= 0 && duration.isFinite && duration > 0
            && duration <= 31_536_000 && position < duration
            && rate.isFinite && rate > 0 && rate <= 16
            && lifetime.isFinite && lifetime > 0 && lifetime <= 30
    }

    private static func validPhonePayload(_ event: Event) -> Bool {
        let duration = number(event.envelope.duration), rate = number(event.envelope.rate)
        let position = number(event.phone_position)
        return event.envelope.text_valid == 1 && event.envelope.sequence != 0
            && duration.isFinite && duration > 0 && duration <= 31_536_000
            && rate.isFinite && rate > 0 && rate <= 16
            && position.isFinite && position >= 0 && position < duration
    }

    private static func validPhoneObservation(_ event: Event) -> Bool {
        let now = number(event.now), observed = number(event.phone_observed_at)
        return now.isFinite && observed.isFinite && now >= observed && now - observed <= 0.75
    }

    private static func clocksMatch(before: State, after: State, event: Event) -> Bool {
        for (flag, opcode, old, new) in [(UInt32(4), UInt32(0), before.sent_at, after.sent_at),
                                       (UInt32(8), UInt32(1), before.received_at, after.received_at)] {
            let present = after.presence & flag != 0
            if event.opcode == opcode {
                let finite = number(event.now).isFinite
                if present != finite || new != (finite ? event.now : 0) { return false }
            } else if event.opcode == 9 {
                if present || new != 0 { return false }
            } else if present != (before.presence & flag != 0) || new != old { return false }
        }
        return true
    }

    private static func retained(_ old: Timeline, _ new: Timeline,
                                 recordOpcode: UInt32, event: Event) -> Bool {
        guard old.token != 0, old.token == new.token else { return true }
        guard immutable(old) == immutable(new) else { return false }
        if event.opcode == recordOpcode {
            return event.primary.flags == 511 && event.primary.native_matches == 12
                && new.last_observation == event.now && new.last_position == event.primary.position
                && number(event.now).isFinite && number(event.now) >= number(old.last_observation)
                && number(event.now) < number(old.deadline)
                && number(new.last_position) >= number(old.last_position)
        }
        return old.last_observation == new.last_observation && old.last_position == new.last_position
    }

    private static func immutable(_ value: Timeline) -> [UInt64] {
        [value.token, value.sequence, value.revision, value.position, value.duration,
         value.rate, value.lifetime, value.origin, value.deadline]
    }

    private static func minted(_ value: Timeline, token: UInt64, sequence: UInt64,
                               revision: UInt64, position: UInt64, duration: UInt64,
                               rate: UInt64, lifetime: UInt64, now: UInt64) -> Bool {
        value.token == token && value.sequence == sequence && value.revision == revision
            && value.position == position && value.duration == duration && value.rate == rate
            && value.lifetime == lifetime && value.origin == now
            && value.deadline == (number(now) + number(lifetime)).bitPattern
            && value.last_observation == now && value.last_position == position
    }

    private static func valid(_ state: State) -> Bool {
        guard state.abi == 1, state.presence & ~UInt32(15) == 0,
              state.terminal <= 1, state.reserved == 0, state.next_sent != 0 else { return false }
        for (flag, raw) in [(UInt32(4), state.sent_at), (UInt32(8), state.received_at)] {
            if state.presence & flag != 0 ? !number(raw).isFinite : raw != 0 { return false }
        }
        guard valid(state.sent, present: state.presence & 1 != 0),
              valid(state.received, present: state.presence & 2 != 0),
              state.sent.token == 0 || state.sent.sequence < state.next_sent,
              state.received.token == 0 || state.received.sequence == state.highest_received else { return false }
        return state.terminal == 0 || (state.presence == 0 && state.next_sent == UInt64.max
            && state.highest_received == UInt64.max)
    }

    private static func valid(_ value: Timeline, present: Bool) -> Bool {
        if !present {
            return immutable(value).allSatisfy { $0 == 0 }
                && value.last_observation == 0 && value.last_position == 0
        }
        let position = number(value.position), duration = number(value.duration)
        let rate = number(value.rate), lifetime = number(value.lifetime)
        let origin = number(value.origin), observation = number(value.last_observation)
        let lastPosition = number(value.last_position)
        return value.token != 0 && value.sequence != 0 && value.revision != 0
            && position.isFinite && position >= 0 && duration.isFinite && duration > 0
            && duration <= 31_536_000 && position < duration
            && rate.isFinite && rate > 0 && rate <= 16
            && lifetime.isFinite && lifetime > 0 && lifetime <= 30
            && origin.isFinite && observation.isFinite && observation >= origin
            && lastPosition.isFinite && lastPosition >= position && lastPosition < duration
            && value.deadline == (origin + lifetime).bitPattern
    }

    private static func number(_ bits: UInt64) -> Double { Double(bitPattern: bits) }
}

/// Only the two current native payloads are retained. Rust owns their timelines,
/// counters and one-use policy; native comparison facts do not authorize Pause.
struct MediaHandoffOffers {
    private struct SentBinding { let token: UInt64; let envelope: WebRTCMediaHandoffOfferEnvelope }
    private struct ReceivedBinding { let token: UInt64; let receipt: WebRTCReceivedMediaHandoffOffer }
    private var core = beluga_core_handoff_offers_initial()
    private var sent: SentBinding?
    private var received: ReceivedBinding?
    private var nextToken: UInt64 = 1

    init() {}

    // Internal frontier seam; ordinary production negotiation uses init().
    init(testingNextSentSequence: UInt64, highestReceivedSequence: UInt64, nextToken: UInt64) {
        core.next_sent = testingNextSentSequence
        core.highest_received = highestReceivedSequence
        self.nextToken = nextToken
        if testingNextSentSequence == 0 { close() }
    }

    mutating func recordSentState(_ update: WebRTCRemoteMediaStateUpdate, now: TimeInterval) {
        var event = Self.event(0, now: now)
        event.primary = Self.primary(update, matching: sent?.envelope)
        _ = step(event)
    }

    mutating func recordReceivedState(_ update: WebRTCRemoteMediaStateUpdate, now: TimeInterval) {
        var event = Self.event(1, now: now)
        event.primary = Self.primary(update, matching: received?.receipt.envelope)
        _ = step(event)
    }

    mutating func prepareSent(contextID: String, update: WebRTCRemoteMediaStateUpdate,
                              authorization: WebRTCRemoteMediaAuthorization,
                              now: TimeInterval, id: UUID = UUID(),
                              source: WebRTCMediaHandoffSourceDescription? = nil) -> WebRTCMediaHandoffOfferEnvelope? {
        var event = Self.event(2, now: now)
        event.token = token()
        event.primary = Self.primary(update)
        event.native_matches = update.item?.contextID == contextID ? 4 : 0
        event.envelope.text_valid = Self.textValid(contextID, videoID: update.item?.artwork?.videoID ?? "") ? 1 : 0
        event.source = Self.source(source, primary: update.item)
        guard let output = step(event, makeSent: { output in
            guard let item = update.item, let videoID = item.artwork?.videoID,
                  let position = item.elapsedTime, let duration = item.duration else { return nil }
            return .init(authorization: authorization, sequence: output.sequence, id: id,
                         observedRevision: update.revision, contextID: contextID, videoID: videoID,
                         positionSeconds: position, durationSeconds: duration, playbackRate: item.playbackRate,
                         validForSeconds: Double(bitPattern: output.lifetime))
        }), output.decision == 1 else { return nil }
        return sent?.envelope
    }

    mutating func sentFailed(id: UUID) {
        var event = Self.event(3)
        event.token = sent?.envelope.id == id ? sent?.token ?? 0 : 0
        _ = step(event)
    }

    mutating func consumeSent(_ commit: WebRTCMediaHandoffCommitEnvelope,
                             state: WebRTCRemoteMediaStateUpdate, now: TimeInterval) -> TimeInterval? {
        var event = Self.event(4, now: now)
        event.native_matches = Self.headerFacts(commit, matching: sent?.envelope)
        event.primary = Self.primary(state, matching: sent?.envelope)
        event.envelope = Self.envelope(commit)
        event.phone_position = commit.phonePositionSeconds.bitPattern
        guard let output = step(event), output.decision == 4 else { return nil }
        return Double(bitPattern: output.deadline)
    }

    mutating func receive(_ envelope: WebRTCMediaHandoffOfferEnvelope,
                         state: WebRTCReceivedRemoteMediaState, now: TimeInterval) -> WebRTCReceivedMediaHandoffOffer? {
        var event = Self.event(5, now: now)
        event.token = token()
        event.envelope = Self.envelope(envelope)
        event.native_matches = envelope.authorization == state.authorization ? 1 : 0
        event.primary = Self.primary(state.update, matching: envelope)
        guard let output = step(event, makeReceived: { _ in
            .init(envelope: envelope, receivedAtUptime: now)
        }), output.decision == 2 else { return nil }
        return received?.receipt
    }

    mutating func consume(_ receipt: WebRTCReceivedMediaHandoffOffer,
                         state: WebRTCReceivedRemoteMediaState, now: TimeInterval) -> Bool {
        let event = receiptEvent(6, receipt: receipt, state: state, now: now)
        return step(event)?.decision == 3
    }

    mutating func prepareCommit(_ receipt: WebRTCReceivedMediaHandoffOffer,
                               phonePositionSeconds: Double, observedAtUptime: Double,
                               state: WebRTCReceivedRemoteMediaState, now: Double) -> WebRTCMediaHandoffCommitEnvelope? {
        var event = receiptEvent(7, receipt: receipt, state: state, now: now)
        event.envelope = Self.envelope(receipt.envelope)
        event.phone_position = phonePositionSeconds.bitPattern
        event.phone_observed_at = observedAtUptime.bitPattern
        guard step(event)?.decision == 5 else { return nil }
        return .init(offer: receipt.envelope, phonePositionSeconds: phonePositionSeconds)
    }

    mutating func discard(_ receipt: WebRTCReceivedMediaHandoffOffer) {
        var event = Self.event(8)
        event.token = received?.receipt == receipt ? received?.token ?? 0 : 0
        _ = step(event)
    }

    mutating func clearTransient() { _ = step(Self.event(9)) }

    private func receiptEvent(_ opcode: UInt32, receipt: WebRTCReceivedMediaHandoffOffer,
                              state: WebRTCReceivedRemoteMediaState, now: Double) -> beluga_core_handoff_offers_event_t {
        var event = Self.event(opcode, now: now)
        event.token = received?.receipt == receipt ? received?.token ?? 0 : 0
        event.native_matches = receipt.envelope.authorization == state.authorization ? 1 : 0
        event.primary = Self.primary(state.update, matching: received?.receipt.envelope)
        return event
    }

    private mutating func token() -> UInt64 {
        guard nextToken != 0 else { return 0 }
        let value = nextToken
        let successor = nextToken.addingReportingOverflow(1)
        nextToken = successor.overflow ? 0 : successor.partialValue
        return value
    }

    private mutating func close() {
        sent = nil; received = nil
        core = beluga_core_handoff_offers_state_t()
        core.abi = 1; core.terminal = 1
        core.next_sent = UInt64.max; core.highest_received = UInt64.max
    }

    private mutating func step(_ event: beluga_core_handoff_offers_event_t,
                               makeSent: (beluga_core_handoff_offers_result_t) -> WebRTCMediaHandoffOfferEnvelope? = { _ in nil },
                               makeReceived: (beluga_core_handoff_offers_result_t) -> WebRTCReceivedMediaHandoffOffer? = { _ in nil })
        -> beluga_core_handoff_offers_result_t? {
        guard core.terminal == 0 else { return nil }
        let output = beluga_core_handoff_offers_step(1, core, event)
        guard BelugaRustHandoffOffersBoundary.accepts(before: core, event: event, output: output) else {
            close(); return nil
        }
        var newSent = output.effects & 1 != 0 ? nil : sent
        var newReceived = output.effects & 2 != 0 ? nil : received
        if output.effects & 4 != 0 {
            guard let envelope = makeSent(output) else { close(); return nil }
            newSent = .init(token: output.minted_token, envelope: envelope)
        }
        if output.effects & 8 != 0 {
            guard let receipt = makeReceived(output) else { close(); return nil }
            newReceived = .init(token: output.minted_token, receipt: receipt)
        }
        guard Self.bound(newSent?.token, envelope: newSent?.envelope, to: output.state.sent),
              Self.bound(newReceived?.token, envelope: newReceived?.receipt.envelope, to: output.state.received),
              newReceived == nil || (newReceived?.receipt.receivedAtUptime.bitPattern == output.state.received.origin
                && newReceived?.receipt.deadlineUptime.bitPattern == output.state.received.deadline) else {
            close(); return nil
        }
        sent = newSent; received = newReceived; core = output.state
        return output
    }

    private static func bound(_ token: UInt64?, envelope: WebRTCMediaHandoffOfferEnvelope?,
                              to timeline: beluga_core_handoff_offers_timeline_t) -> Bool {
        guard let token, let envelope else { return timeline.token == 0 }
        return token == timeline.token && envelope.sequence == timeline.sequence
            && envelope.observedRevision == timeline.revision
            && envelope.positionSeconds.bitPattern == timeline.position
            && envelope.durationSeconds.bitPattern == timeline.duration
            && envelope.playbackRate.bitPattern == timeline.rate
            && envelope.validForSeconds.bitPattern == timeline.lifetime
    }

    private static func event(_ opcode: UInt32, now: Double = 0) -> beluga_core_handoff_offers_event_t {
        var value = beluga_core_handoff_offers_event_t()
        value.opcode = opcode; value.now = now.bitPattern
        return value
    }

    private static func primary(_ update: WebRTCRemoteMediaStateUpdate,
                                matching envelope: WebRTCMediaHandoffOfferEnvelope? = nil) -> beluga_core_handoff_offers_primary_t {
        var value = beluga_core_handoff_offers_primary_t()
        value.revision = update.revision
        if update.isValid { value.flags |= 1 }
        guard let item = update.item else { return value }
        value.flags |= 2
        if item.sourceName == "YouTube" { value.flags |= 4 }
        if item.artwork?.provider == .youtube { value.flags |= 8 }
        if item.playbackState == .playing { value.flags |= 16 }
        if item.capabilities.canPause { value.flags |= 32 }
        if item.capabilities.canSeekToPosition { value.flags |= 64 }
        if let position = item.elapsedTime { value.flags |= 128; value.position = position.bitPattern }
        if let duration = item.duration { value.flags |= 256; value.duration = duration.bitPattern }
        value.rate = item.playbackRate.bitPattern
        if let envelope {
            if item.contextID == envelope.contextID { value.native_matches |= 4 }
            if item.artwork?.videoID == envelope.videoID { value.native_matches |= 8 }
        }
        return value
    }

    private static func envelope(_ value: WebRTCMediaHandoffOfferEnvelope) -> beluga_core_handoff_offers_envelope_t {
        var result = beluga_core_handoff_offers_envelope_t()
        result.text_valid = textValid(value.contextID, videoID: value.videoID) ? 1 : 0
        result.sequence = value.sequence; result.revision = value.observedRevision
        result.position = value.positionSeconds.bitPattern; result.duration = value.durationSeconds.bitPattern
        result.rate = value.playbackRate.bitPattern; result.lifetime = value.validForSeconds.bitPattern
        return result
    }

    private static func envelope(_ value: WebRTCMediaHandoffCommitEnvelope) -> beluga_core_handoff_offers_envelope_t {
        var result = beluga_core_handoff_offers_envelope_t()
        result.text_valid = textValid(value.contextID, videoID: value.videoID) ? 1 : 0
        result.sequence = value.sequence; result.duration = value.durationSeconds.bitPattern
        result.rate = value.playbackRate.bitPattern
        return result
    }

    private static func textValid(_ contextID: String, videoID: String) -> Bool {
        !contextID.isEmpty && contextID.utf8.count <= WebRTCRemoteMediaItem.maximumContextIDBytes
            && !contextID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && WebRTCRemoteMediaArtworkReference(videoID: videoID) != nil
    }

    private static func headerFacts(_ commit: WebRTCMediaHandoffCommitEnvelope,
                                    matching offer: WebRTCMediaHandoffOfferEnvelope?) -> UInt64 {
        guard let offer else { return 0 }
        var facts: UInt64 = 0
        if commit.authorization == offer.authorization { facts |= 1 }
        if commit.id == offer.id { facts |= 2 }
        if commit.contextID == offer.contextID { facts |= 4 }
        if commit.videoID == offer.videoID { facts |= 8 }
        return facts
    }

    private static func source(_ value: WebRTCMediaHandoffSourceDescription?,
                               primary: WebRTCRemoteMediaItem?) -> beluga_core_handoff_offers_source_t {
        var result = beluga_core_handoff_offers_source_t()
        guard let value else { return result }
        result.present = 1; result.video_equal = primary?.artwork?.videoID == value.videoID ? 1 : 0
        result.position = value.positionSeconds.bitPattern; result.duration = value.durationSeconds.bitPattern
        result.rate = value.playbackRate.bitPattern; result.observed_at = value.observedAtUptime.bitPattern
        result.deadline = value.deadlineUptime.bitPattern
        return result
    }
}
