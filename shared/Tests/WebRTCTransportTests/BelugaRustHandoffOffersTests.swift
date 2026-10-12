// Production-bridge differential coverage against the independent original Swift reducer.
import Foundation
import XCTest
@testable import WebRTCTransport

private struct OfferPair {
    let actual: WebRTCMediaHandoffOfferEnvelope
    let reference: WebRTCMediaHandoffOfferEnvelope
    init(_ value: WebRTCMediaHandoffOfferEnvelope) { actual = value; reference = value }
    init(actual: WebRTCMediaHandoffOfferEnvelope, reference: WebRTCMediaHandoffOfferEnvelope) {
        self.actual = actual; self.reference = reference
    }
}

private struct ReceiptPair {
    let actual: WebRTCReceivedMediaHandoffOffer
    let reference: WebRTCReceivedMediaHandoffOffer
    func makeCounterfeit() -> ReceiptPair {
        .init(actual: .init(envelope: actual.envelope, receivedAtUptime: actual.receivedAtUptime),
              reference: .init(envelope: reference.envelope, receivedAtUptime: reference.receivedAtUptime))
    }
}

private struct PairedOffers {
    var actual = MediaHandoffOffers()
    var reference = BelugaRustHandoffOffersReference()
    private var mintedActualReceipts: Set<UUID> = []

    init() {}

    init(testingNextSentSequence: UInt64, highestReceivedSequence: UInt64, nextToken: UInt64) {
        actual = .init(testingNextSentSequence: testingNextSentSequence,
                       highestReceivedSequence: highestReceivedSequence, nextToken: nextToken)
        reference = .init(testingNextSentSequence: testingNextSentSequence,
                          highestReceivedSequence: highestReceivedSequence)
    }

    mutating func recordSent(_ state: WebRTCRemoteMediaStateUpdate, _ now: Double) {
        actual.recordSentState(state, now: now); reference.recordSentState(state, now: now)
    }
    mutating func recordReceived(_ state: WebRTCRemoteMediaStateUpdate, _ now: Double) {
        actual.recordReceivedState(state, now: now); reference.recordReceivedState(state, now: now)
    }
    mutating func clear() { actual.clearTransient(); reference.clearTransient() }
    mutating func reset() { actual = .init(); reference = .init() }
    mutating func sentFailed(_ id: UUID) { actual.sentFailed(id: id); reference.sentFailed(id: id) }
    mutating func discard(_ receipt: ReceiptPair) {
        actual.discard(receipt.actual); reference.discard(receipt.reference)
    }

    mutating func prepare(_ state: WebRTCRemoteMediaStateUpdate, authorization: WebRTCRemoteMediaAuthorization,
                          now: Double, id: UUID, context: String = "selected",
                          source: WebRTCMediaHandoffSourceDescription? = nil,
                          file: StaticString = #filePath, line: UInt = #line) -> OfferPair? {
        let a = actual.prepareSent(contextID: context, update: state, authorization: authorization,
                                   now: now, id: id, source: source)
        let r = reference.prepareSent(contextID: context, update: state, authorization: authorization,
                                      now: now, id: id, source: source)
        Self.compareOffers(a, r, file: file, line: line)
        guard let a, let r else { return nil }
        return .init(actual: a, reference: r)
    }

    mutating func receive(_ offer: OfferPair, state: WebRTCReceivedRemoteMediaState, now: Double,
                          file: StaticString = #filePath, line: UInt = #line) -> ReceiptPair? {
        let a = actual.receive(offer.actual, state: state, now: now)
        let r = reference.receive(offer.reference, state: state, now: now)
        XCTAssertEqual(a == nil, r == nil, file: file, line: line)
        guard let a, let r else { return nil }
        // Fresh receipt UUIDs are not compared across implementations. Retain
        // each actual/reference receipt independently for every later operation.
        Self.compareOffers(a.envelope, r.envelope, file: file, line: line)
        XCTAssertEqual(a.id, r.id, file: file, line: line)
        XCTAssertEqual(Array(a.contextID.utf8), Array(r.contextID.utf8), file: file, line: line)
        XCTAssertEqual(Array(a.videoID.utf8), Array(r.videoID.utf8), file: file, line: line)
        for (left, right) in [(a.positionSeconds, r.positionSeconds), (a.durationSeconds, r.durationSeconds),
                              (a.playbackRate, r.playbackRate), (a.deadlineUptime, r.deadlineUptime),
                              (a.receivedAtUptime, r.receivedAtUptime)] {
            XCTAssertEqual(left.bitPattern, right.bitPattern, file: file, line: line)
        }
        XCTAssertTrue(mintedActualReceipts.insert(a.receiptToken).inserted,
                      "Each accepted receive must mint a fresh native receipt identity", file: file, line: line)
        return .init(actual: a, reference: r)
    }

    mutating func consume(_ receipt: ReceiptPair, state: WebRTCReceivedRemoteMediaState, now: Double,
                          file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let a = actual.consume(receipt.actual, state: state, now: now)
        let r = reference.consume(receipt.reference, state: state, now: now)
        XCTAssertEqual(a, r, file: file, line: line)
        return a
    }

    mutating func commit(_ receipt: ReceiptPair, phonePosition: Double, observedAt: Double,
                         state: WebRTCReceivedRemoteMediaState, now: Double,
                         file: StaticString = #filePath, line: UInt = #line) -> WebRTCMediaHandoffCommitEnvelope? {
        let a = actual.prepareCommit(receipt.actual, phonePositionSeconds: phonePosition,
                                      observedAtUptime: observedAt, state: state, now: now)
        let r = reference.prepareCommit(receipt.reference, phonePositionSeconds: phonePosition,
                                         observedAtUptime: observedAt, state: state, now: now)
        XCTAssertEqual(a, r, file: file, line: line)
        if let a, let r {
            XCTAssertEqual(Array(a.contextID.utf8), Array(r.contextID.utf8), file: file, line: line)
            XCTAssertEqual(a.phonePositionSeconds.bitPattern, r.phonePositionSeconds.bitPattern, file: file, line: line)
        }
        return a
    }

    mutating func consumeSent(_ offer: OfferPair, phonePosition: Double,
                              state: WebRTCRemoteMediaStateUpdate, now: Double,
                              file: StaticString = #filePath, line: UInt = #line) -> Double? {
        let a = actual.consumeSent(.init(offer: offer.actual, phonePositionSeconds: phonePosition), state: state, now: now)
        let r = reference.consumeSent(.init(offer: offer.reference, phonePositionSeconds: phonePosition), state: state, now: now)
        XCTAssertEqual(a?.bitPattern, r?.bitPattern, file: file, line: line)
        return a
    }

    private static func compareOffers(_ a: WebRTCMediaHandoffOfferEnvelope?,
                                       _ r: WebRTCMediaHandoffOfferEnvelope?,
                                       file: StaticString, line: UInt) {
        XCTAssertEqual(a, r, file: file, line: line)
        if let a, let r {
            // String == is canonical-equivalent. Storage must also preserve the original bytes.
            XCTAssertEqual(Array(a.contextID.utf8), Array(r.contextID.utf8), file: file, line: line)
            XCTAssertEqual(Array(a.videoID.utf8), Array(r.videoID.utf8), file: file, line: line)
            for (left, right) in [(a.positionSeconds, r.positionSeconds), (a.durationSeconds, r.durationSeconds),
                                  (a.playbackRate, r.playbackRate), (a.validForSeconds, r.validForSeconds)] {
                XCTAssertEqual(left.bitPattern, right.bitPattern, file: file, line: line)
            }
        }
    }
}

final class BelugaRustHandoffOffersTests: XCTestCase {
    private let authorization = WebRTCRemoteMediaAuthorization()
    private let otherAuthorization = WebRTCRemoteMediaAuthorization()
    private func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", UInt64(index)))!
    }
    private func state(_ revision: UInt64 = 1, position: Double = 20, rate: Double = 1,
                       context: String = "selected", playing: Bool = true,
                       video: String = "dQw4w9WgXcQ") -> WebRTCRemoteMediaStateUpdate {
        .init(revision: revision, item: .init(contextID: context, sourceName: "YouTube", title: "Test",
            playbackState: playing ? .playing : .paused, elapsedTime: position, duration: 200,
            playbackRate: rate, capabilities: .init(canPlay: true, canPause: true,
                canSkipForward: false, canSkipBackward: false, canSeekToPosition: true),
            artwork: .init(videoID: video)))
    }
    private func received(_ update: WebRTCRemoteMediaStateUpdate,
                          authorization: WebRTCRemoteMediaAuthorization? = nil) -> WebRTCReceivedRemoteMediaState {
        .init(envelope: .init(authorization: authorization ?? self.authorization, update: update))
    }
    private func literal(_ sequence: UInt64 = 1, revision: UInt64 = 1, position: Double = 20,
                         rate: Double = 1, context: String = "selected", lifetime: Double = 30,
                         video: String = "dQw4w9WgXcQ",
                         authorization: WebRTCRemoteMediaAuthorization? = nil) -> OfferPair {
        .init(.init(authorization: authorization ?? self.authorization, sequence: sequence, id: id(Int(sequence & 0xffff)),
                    observedRevision: revision, contextID: context, videoID: video,
                    positionSeconds: position, durationSeconds: 200, playbackRate: rate, validForSeconds: lifetime))
    }
    private func readyReceipt(_ pair: inout PairedOffers, offer: OfferPair? = nil,
                              update: WebRTCRemoteMediaStateUpdate? = nil, now: Double = 10) throws -> ReceiptPair {
        let value = update ?? state()
        pair.recordReceived(value, now)
        return try XCTUnwrap(pair.receive(offer ?? literal(), state: received(value), now: now))
    }

    // Each trace starts with both slots live. Stored native values are reused
    // verbatim, including stale originals and one cached counterfeit pair.
    // The alphabet is finite; it is not an unbounded sequence-counter BFS.
    private enum TraceEvent: Int, CaseIterable {
        case recordSentFresh, recordSentPaused, recordSentNonfinite
        case recordReceivedFresh, recordReceivedPaused, recordReceivedRegressed
        case prepareSent, failMatchingSent, failOtherSent
        case receiveHigher, receiveHigherStale, replayOriginal
        case consumeSentValid, consumeSentDriftFailure, consumeSentMismatch
        case consumeCurrentReceipt, consumeOldReceipt, consumeCounterfeit
        case prepareFreshCommit, prepareStaleCommit, discardCurrent, discardCounterfeit
        case clear, reset
    }

    private func runTrace(_ events: [TraceEvent], file: StaticString = #filePath, line: UInt = #line) throws {
        var pair = PairedOffers()
        pair.recordSent(state(), 10)
        var currentOffer = try XCTUnwrap(pair.prepare(state(), authorization: authorization, now: 10, id: id(1)))
        let originalOffer = currentOffer
        var currentReceipt = try readyReceipt(&pair, offer: currentOffer)
        let originalReceipt = currentReceipt
        let counterfeit = originalReceipt.makeCounterfeit()
        for (index, event) in events.enumerated() {
            switch event {
            case .recordSentFresh: pair.recordSent(state(2), 10)
            case .recordSentPaused: pair.recordSent(state(2, playing: false), 10)
            case .recordSentNonfinite: pair.recordSent(state(2), .nan)
            case .recordReceivedFresh: pair.recordReceived(state(2), 10)
            case .recordReceivedPaused: pair.recordReceived(state(2, playing: false), 10)
            case .recordReceivedRegressed: pair.recordReceived(state(2), 9)
            case .prepareSent:
                if let next = pair.prepare(state(2), authorization: authorization, now: 10, id: id(index + 2)) {
                    currentOffer = next
                }
            case .failMatchingSent: pair.sentFailed(currentOffer.actual.id)
            case .failOtherSent: pair.sentFailed(id(999_999))
            case .receiveHigher:
                if let next = pair.receive(literal(2, revision: 2), state: received(state(2)), now: 10) {
                    currentReceipt = next
                }
            case .receiveHigherStale:
                _ = pair.receive(literal(2, revision: 2), state: received(state(2)), now: 12)
            case .replayOriginal:
                _ = pair.receive(originalOffer, state: received(state()), now: 10)
            case .consumeSentValid:
                _ = pair.consumeSent(currentOffer, phonePosition: 20, state: state(2), now: 10)
            case .consumeSentDriftFailure:
                _ = pair.consumeSent(currentOffer, phonePosition: 199, state: state(2), now: 10)
            case .consumeSentMismatch:
                _ = pair.consumeSent(literal(99), phonePosition: 20, state: state(2), now: 10)
            case .consumeCurrentReceipt:
                _ = pair.consume(currentReceipt, state: received(state(2)), now: 10)
            case .consumeOldReceipt:
                _ = pair.consume(originalReceipt, state: received(state(2)), now: 10)
            case .consumeCounterfeit:
                _ = pair.consume(counterfeit, state: received(state(2)), now: 10)
            case .prepareFreshCommit:
                _ = pair.commit(currentReceipt, phonePosition: 20, observedAt: 9.25, state: received(state(2)), now: 10)
            case .prepareStaleCommit:
                _ = pair.commit(currentReceipt, phonePosition: 20, observedAt: Double(9.25).nextDown,
                                state: received(state(2)), now: 10)
            case .discardCurrent: pair.discard(currentReceipt)
            case .discardCounterfeit: pair.discard(counterfeit)
            case .clear: pair.clear()
            case .reset: pair.reset()
            }
            // Read-only-to-the-original probes execute on separate value copies.
            // They expose effects of output-less record/clear/discard/fail calls.
            var sentProbe = pair
            _ = sentProbe.consumeSent(currentOffer, phonePosition: 20, state: state(2), now: 10, file: file, line: line)
            var receivedProbe = pair
            _ = receivedProbe.consume(currentReceipt, state: received(state(2)), now: 10, file: file, line: line)
            var sequenceProbe = pair
            _ = sequenceProbe.prepare(state(2), authorization: authorization, now: 10,
                                      id: id(1_000_000 + index), file: file, line: line)
            var floorProbe = pair
            _ = floorProbe.receive(literal(3, revision: 2), state: received(state(2)), now: 10, file: file, line: line)
        }
    }

    func testAllBoundedSmallEventTracesMatchOriginalReference() throws {
        var prefix: [TraceEvent] = []
        func visit(_ remaining: Int) throws {
            try runTrace(prefix)
            guard remaining > 0 else { return }
            for event in TraceEvent.allCases {
                prefix.append(event)
                try visit(remaining - 1)
                prefix.removeLast()
            }
        }
        try visit(3) // Exactly 1 + 24 + 24^2 + 24^3 = 14,425 independent traces.
    }

    func testSeededLongChurnKeepsBothSlotsAndReceiptIdentityInParity() throws {
        for seed in 1...16 {
            var generator = UInt64(seed)
            var events: [TraceEvent] = []
            for _ in 0..<512 {
                generator = generator &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                events.append(TraceEvent.allCases[Int((generator >> 32) % UInt64(TraceEvent.allCases.count))])
            }
            try runTrace(events)
        }
    }

    func testSnapshotAgeBoundariesAndFiniteNegativeClockMatchOriginalReference() {
        for now in [Double(12).nextDown, 12, Double(12).nextUp, 10, Double(10).nextDown, .nan, .infinity, -.infinity] {
            var pair = PairedOffers()
            pair.recordSent(state(), 10)
            let offer = pair.prepare(state(), authorization: authorization, now: now, id: id(1))
            XCTAssertEqual(offer != nil, now.isFinite && now >= 10 && now < 12)
        }
        var negative = PairedOffers()
        negative.recordSent(state(), -10)
        XCTAssertNotNil(negative.prepare(state(), authorization: authorization, now: -9.5, id: id(1)))
        var native = PairedOffers()
        native.recordSent(state(), -10)
        let source = WebRTCMediaHandoffSourceDescription(videoID: "dQw4w9WgXcQ", positionSeconds: 20,
            durationSeconds: 200, playbackRate: 1, observedAtUptime: -10, deadlineUptime: 20)
        XCTAssertNil(native.prepare(state(), authorization: authorization, now: -10, id: id(1), source: source))
    }

    func testTimelineClockPositionAndStrictDeadlineBoundariesMatchReference() throws {
        for now in [Double(40).nextDown, 40, Double(40).nextUp] {
            var pair = PairedOffers()
            let receipt = try readyReceipt(&pair)
            pair.recordReceived(state(2, position: 50), now)
            XCTAssertEqual(pair.consume(receipt, state: received(state(2, position: 50)), now: now), now < 40)
        }
        var pair = PairedOffers()
        let receipt = try readyReceipt(&pair)
        pair.recordReceived(state(2, position: 20.5), 10.5)
        pair.recordReceived(state(3, position: 20.5), 10.5) // Equal observation/position is valid.
        XCTAssertTrue(pair.consume(receipt, state: received(state(3, position: 20.5)), now: 10.5))
        for backwardsClock in [true, false] {
            var pair = PairedOffers()
            let receipt = try readyReceipt(&pair)
            pair.recordReceived(state(2, position: 20.5), 10.5)
            pair.recordReceived(state(3, position: backwardsClock ? 20.5 : 20.4), backwardsClock ? 10.4 : 10.75)
            pair.recordReceived(state(4, position: 21), 11)
            XCTAssertFalse(pair.consume(receipt, state: received(state(4, position: 21)), now: 11))
        }
    }

    func testTimelineDriftScalesWithRateAndKeepsInclusiveBoundary() throws {
        for rate in [0.5, 1, 16] {
            let edge = 20 + 2 * rate + 0.25
            for position in [edge.nextDown, edge, edge.nextUp] {
                var pair = PairedOffers()
                let receipt = try readyReceipt(&pair, offer: literal(rate: rate), update: state(rate: rate))
                XCTAssertEqual(pair.consume(receipt, state: received(state(2, position: position, rate: rate)), now: 10),
                               position <= edge)
            }
        }
    }

    func testHostPhoneDriftUsesItsDistinctInclusiveBound() throws {
        for rate in [0.5, 1, 16] {
            let edge = 80 + 2 + 2 * rate
            for phonePosition in [edge.nextDown, edge, edge.nextUp] {
                var pair = PairedOffers()
                let update = state(position: 80, rate: rate)
                pair.recordSent(update, 10)
                let offer = try XCTUnwrap(pair.prepare(update, authorization: authorization, now: 10, id: id(1)))
                XCTAssertEqual(pair.consumeSent(offer, phonePosition: phonePosition, state: update, now: 10) != nil,
                               phonePosition <= edge)
            }
        }
    }

    func testPlaybackSamplePreflightPreservesReceiptUntilConsumption() throws {
        for observed in [Double(9.25).nextDown, Double(10).nextUp, .nan, .infinity, -.infinity] {
            var pair = PairedOffers()
            let receipt = try readyReceipt(&pair)
            XCTAssertNil(pair.commit(receipt, phonePosition: 20, observedAt: observed, state: received(state()), now: 10))
            XCTAssertNotNil(pair.commit(receipt, phonePosition: 20, observedAt: 9.25, state: received(state()), now: 10))
        }
        for invalidPosition in [-1.0, 200, .nan, .infinity] {
            var pair = PairedOffers()
            let receipt = try readyReceipt(&pair)
            XCTAssertNil(pair.commit(receipt, phonePosition: invalidPosition, observedAt: 10,
                                     state: received(state()), now: 10))
            XCTAssertNotNil(pair.commit(receipt, phonePosition: 199, observedAt: 10,
                                        state: received(state()), now: 10))
        }
    }

    func testOriginalRevisionFloorDoesNotBecomeLatestRevisionHighWater() throws {
        var pair = PairedOffers()
        let receipt = try readyReceipt(&pair, offer: literal(revision: 6), update: state(6))
        pair.recordReceived(state(8, position: 20.5), 10.5)
        XCTAssertTrue(pair.consume(receipt, state: received(state(7, position: 21)), now: 11))
    }

    func testHigherRejectedSequenceBurnsFloorAndRetiresPreviousReceipt() throws {
        var pair = PairedOffers()
        let old = try readyReceipt(&pair)
        XCTAssertNil(pair.receive(literal(2), state: received(state()), now: 13))
        pair.recordReceived(state(), 13)
        XCTAssertNil(pair.receive(literal(2), state: received(state()), now: 13))
        XCTAssertFalse(pair.consume(old, state: received(state()), now: 13))
        XCTAssertNotNil(pair.receive(literal(3), state: received(state()), now: 13))
        for input in [literal(), literal(2, context: "bad\u{0000}context"),
                      literal(2, authorization: otherAuthorization)] {
            var pair = PairedOffers()
            let current = try readyReceipt(&pair)
            XCTAssertNil(pair.receive(input, state: received(state()), now: 10))
            XCTAssertTrue(pair.consume(current, state: received(state()), now: 10))
        }
    }

    func testMatchingConsumptionBurnsBeforeLateValidation() throws {
        for failure in 0..<3 {
            var host = PairedOffers()
            host.recordSent(state(), 10)
            let offer = try XCTUnwrap(host.prepare(state(), authorization: authorization, now: 10, id: id(1)))
            let badState = failure == 1 ? state(2, position: 90) : state()
            let badNow = failure == 0 ? 12.0 : 10
            let phone = failure == 2 ? 199.0 : 20
            XCTAssertNil(host.consumeSent(offer, phonePosition: phone, state: badState, now: badNow))
            host.recordSent(state(), 12)
            XCTAssertNil(host.consumeSent(offer, phonePosition: 22, state: state(2, position: 22), now: 12))
        }
        for failure in 0..<3 {
            var pair = PairedOffers()
            let receipt = try readyReceipt(&pair)
            let badState = received(failure == 1 ? state(2, position: 90) : state(),
                                    authorization: failure == 2 ? otherAuthorization : nil)
            XCTAssertFalse(pair.consume(receipt, state: badState, now: failure == 0 ? 12 : 10))
            pair.recordReceived(state(2, position: 22), 12)
            XCTAssertFalse(pair.consume(receipt, state: received(state(2, position: 22)), now: 12))
        }
    }

    func testMismatchAndCounterfeitInputsPreserveExactPendingAuthority() throws {
        var pair = PairedOffers()
        let receipt = try readyReceipt(&pair)
        let counterfeit = receipt.makeCounterfeit()
        XCTAssertFalse(pair.consume(counterfeit, state: received(state()), now: 10))
        pair.discard(counterfeit)
        XCTAssertTrue(pair.consume(receipt, state: received(state()), now: 10))
        var host = PairedOffers()
        host.recordSent(state(), 10)
        let offer = try XCTUnwrap(host.prepare(state(), authorization: authorization, now: 10, id: id(9)))
        host.sentFailed(id(10))
        XCTAssertNil(host.consumeSent(literal(2), phonePosition: 20, state: state(), now: 10))
        XCTAssertEqual(host.consumeSent(offer, phonePosition: 20, state: state(), now: 10), 40)
    }

    func testFailedPreparationDoesNotBurnButFailedSendDoesBurnSequence() throws {
        var pair = PairedOffers()
        pair.recordSent(state(), 10)
        XCTAssertNil(pair.prepare(state(), authorization: authorization, now: 10, id: id(1), context: "other"))
        let first = try XCTUnwrap(pair.prepare(state(), authorization: authorization, now: 10, id: id(2)))
        XCTAssertEqual(first.actual.sequence, 1)
        pair.sentFailed(first.actual.id)
        let second = try XCTUnwrap(pair.prepare(state(), authorization: authorization, now: 10, id: id(3)))
        XCTAssertEqual(second.actual.sequence, 2)
    }

    func testNativeSourceKeepsFractionalOriginalDeadlineAndBounds() throws {
        for deadline in [Double(40).nextDown, 40, Double(40).nextUp] {
            var pair = PairedOffers()
            pair.recordSent(state(position: 21), 11)
            let source = WebRTCMediaHandoffSourceDescription(videoID: "dQw4w9WgXcQ", positionSeconds: 20,
                durationSeconds: 200, playbackRate: 1, observedAtUptime: 10, deadlineUptime: deadline)
            let offer = pair.prepare(state(position: 21), authorization: authorization, now: 11, id: id(1), source: source)
            // Use representable absolute deadlines for a precise nextUp assertion.
            XCTAssertEqual(offer != nil, source.deadlineUptime - 10 <= 30)
        }
        var pair = PairedOffers()
        pair.recordSent(state(position: 21.5), 11.5)
        let source = WebRTCMediaHandoffSourceDescription(videoID: "dQw4w9WgXcQ", positionSeconds: 20,
            durationSeconds: 200, playbackRate: 1, observedAtUptime: 10, deadlineUptime: 39.75)
        let offer = try XCTUnwrap(pair.prepare(state(position: 21.5), authorization: authorization,
                                              now: 11.5, id: id(1), source: source))
        XCTAssertEqual(offer.actual.validForSeconds, 28.25)
        XCTAssertEqual(pair.consumeSent(offer, phonePosition: 21.5, state: state(position: 21.5), now: 11.5), 39.75)
    }

    func testSentAndReceivedSlotsRemainIndependentAcrossSingleSlotFailures() throws {
        for operation in 0..<6 {
            var pair = PairedOffers()
            pair.recordSent(state(), 10)
            let sent = try XCTUnwrap(pair.prepare(state(), authorization: authorization, now: 10, id: id(9)))
            let receipt = try readyReceipt(&pair)
            switch operation {
            case 0: pair.recordSent(state(2, playing: false), 10)
            case 1: pair.sentFailed(sent.actual.id)
            case 2: _ = pair.consumeSent(sent, phonePosition: 199, state: state(), now: 10)
            case 3: pair.recordReceived(state(2, playing: false), 10)
            case 4: pair.discard(receipt)
            default: _ = pair.consume(receipt, state: received(state(), authorization: otherAuthorization), now: 10)
            }
            if operation < 3 { XCTAssertTrue(pair.consume(receipt, state: received(state()), now: 10)) }
            else { XCTAssertEqual(pair.consumeSent(sent, phonePosition: 20, state: state(), now: 10), 40) }
        }
    }

    func testClearRetainsCountersButNewNegotiationResetsThem() throws {
        var pair = PairedOffers()
        pair.recordSent(state(), 10)
        let first = try XCTUnwrap(pair.prepare(state(), authorization: authorization, now: 10, id: id(1)))
        let receipt = try readyReceipt(&pair)
        pair.clear()
        XCTAssertNil(pair.prepare(state(), authorization: authorization, now: 10, id: id(2)))
        pair.recordSent(state(), 10); pair.recordReceived(state(), 10)
        let second = try XCTUnwrap(pair.prepare(state(), authorization: authorization, now: 10, id: id(2)))
        XCTAssertEqual(first.actual.sequence, 1); XCTAssertEqual(second.actual.sequence, 2)
        XCTAssertNil(pair.receive(literal(), state: received(state()), now: 10))
        XCTAssertFalse(pair.consume(receipt, state: received(state()), now: 10))
        pair.reset()
        pair.recordSent(state(), 10); pair.recordReceived(state(), 10)
        XCTAssertEqual(pair.prepare(state(), authorization: authorization, now: 10, id: id(3))?.actual.sequence, 1)
        XCTAssertNotNil(pair.receive(literal(), state: received(state()), now: 10))
    }

    func testCanonicalNativeEqualityPreservesOriginalBytesAndValueCopies() throws {
        let composed = "caf\u{00e9}", decomposed = "cafe\u{0301}"
        XCTAssertEqual(composed, decomposed)
        XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))
        var pair = PairedOffers()
        pair.recordSent(state(context: composed), 10)
        let offer = try XCTUnwrap(pair.prepare(state(context: composed), authorization: authorization,
                                              now: 10, id: id(1), context: decomposed))
        XCTAssertEqual(Array(offer.actual.contextID.utf8), Array(decomposed.utf8))
        let receipt = try readyReceipt(&pair, offer: offer, update: state(context: composed))
        let copiedReceipt = receipt
        var copiedLedger = pair
        XCTAssertTrue(pair.consume(copiedReceipt, state: received(state(context: composed)), now: 10))
        XCTAssertTrue(copiedLedger.consume(copiedReceipt, state: received(state(context: decomposed)), now: 10))
        XCTAssertEqual(pair.consumeSent(offer, phonePosition: 20, state: state(context: composed), now: 10), 40)
        XCTAssertEqual(copiedLedger.consumeSent(offer, phonePosition: 20, state: state(context: decomposed), now: 10), 40)
    }

    func testCanonicalAliasCannotBypassUTF8BoundOrBurnSequenceOnPreparationFailure() throws {
        let composed = String(repeating: "\u{00e9}", count: 64)
        let decomposed = String(repeating: "e\u{0301}", count: 64)
        XCTAssertEqual(composed, decomposed)
        XCTAssertEqual(composed.utf8.count, 128)
        XCTAssertEqual(decomposed.utf8.count, 192)
        var pair = PairedOffers()
        pair.recordSent(state(context: composed), 10)
        XCTAssertNil(pair.prepare(state(context: composed), authorization: authorization,
                                  now: 10, id: id(1), context: decomposed))
        let valid = try XCTUnwrap(pair.prepare(state(context: composed), authorization: authorization,
                                              now: 10, id: id(2), context: composed))
        XCTAssertEqual(valid.actual.sequence, 1)
        XCTAssertEqual(Array(valid.actual.contextID.utf8), Array(composed.utf8))
    }

    func testCommitHeaderAndCurrentPrimaryIdentityAreIndependent() throws {
        for changeContext in [true, false] {
            var sourceChanged = PairedOffers()
            sourceChanged.recordSent(state(), 10)
            let original = try XCTUnwrap(sourceChanged.prepare(state(), authorization: authorization, now: 10, id: id(1)))
            let changedState = state(2, context: changeContext ? "replacement" : "selected",
                                     video: changeContext ? "dQw4w9WgXcQ" : "abcdefghijk")
            // Header matches old offer; CURRENT primary does not. Consume, then reject.
            XCTAssertNil(sourceChanged.consumeSent(original, phonePosition: 20, state: changedState, now: 10))
            sourceChanged.recordSent(state(3), 10)
            XCTAssertNil(sourceChanged.consumeSent(original, phonePosition: 20, state: state(3), now: 10))

            var headerChanged = PairedOffers()
            headerChanged.recordSent(state(), 10)
            let genuine = try XCTUnwrap(headerChanged.prepare(state(), authorization: authorization, now: 10, id: id(1)))
            let wrongHeader = literal(context: changeContext ? "replacement" : "selected",
                                      video: changeContext ? "dQw4w9WgXcQ" : "abcdefghijk")
            // CURRENT primary matches old offer; header does not. Preserve old offer.
            XCTAssertNil(headerChanged.consumeSent(wrongHeader, phonePosition: 20, state: state(), now: 10))
            XCTAssertEqual(headerChanged.consumeSent(genuine, phonePosition: 20, state: state(), now: 10), 40)
        }
    }

    func testReceivePrimaryIsBoundToIncomingEnvelopeNotRetiredReceipt() throws {
        for changeContext in [true, false] {
            let replacementContext = changeContext ? "replacement" : "selected"
            let replacementVideo = changeContext ? "dQw4w9WgXcQ" : "abcdefghijk"
            let replacementState = state(2, context: replacementContext, video: replacementVideo)
            var accepting = PairedOffers()
            let old = try readyReceipt(&accepting)
            // No recordReceived replacement: the fresh timestamp already exists,
            // and old receipt is still live when the new receive retires it.
            let next = try XCTUnwrap(accepting.receive(literal(2, revision: 2, context: replacementContext,
                video: replacementVideo), state: received(replacementState), now: 10))
            XCTAssertFalse(accepting.consume(old, state: received(replacementState), now: 10))
            XCTAssertTrue(accepting.consume(next, state: received(replacementState), now: 10))

            var rejecting = PairedOffers()
            let original = try readyReceipt(&rejecting)
            // Primary matches OLD receipt, not the NEW incoming envelope.
            let incoming = literal(2, revision: 2, context: replacementContext, video: replacementVideo)
            XCTAssertNil(rejecting.receive(incoming, state: received(state(2)), now: 10))
            XCTAssertFalse(rejecting.consume(original, state: received(state(2)), now: 10))
            rejecting.recordReceived(replacementState, 10)
            XCTAssertNil(rejecting.receive(incoming, state: received(replacementState), now: 10))
        }
    }

    func testNonfiniteReceiveClockDoesNotMoveEarlyGuardsAheadOfSequenceBurn() throws {
        for now in [Double.nan, .infinity, -.infinity, 9] {
            for input in [literal(), literal(2, context: "bad\u{0000}context"),
                          literal(2, authorization: otherAuthorization)] {
                var preserved = PairedOffers()
                let current = try readyReceipt(&preserved)
                XCTAssertNil(preserved.receive(input, state: received(state()), now: now))
                XCTAssertTrue(preserved.consume(current, state: received(state()), now: 10))
            }
            var burned = PairedOffers()
            let old = try readyReceipt(&burned)
            XCTAssertNil(burned.receive(literal(2), state: received(state()), now: now))
            burned.recordReceived(state(), 10)
            XCTAssertNil(burned.receive(literal(2), state: received(state()), now: 10))
            XCTAssertFalse(burned.consume(old, state: received(state()), now: 10))
        }
    }

    func testSignedZeroStorageAndRoundedLargeClockDeadlineMatchOriginalReference() throws {
        var signedZero = PairedOffers()
        signedZero.recordSent(state(position: -0.0), -0.0)
        let offer = try XCTUnwrap(signedZero.prepare(state(position: -0.0), authorization: authorization,
                                                    now: -0.0, id: id(1)))
        XCTAssertEqual(offer.actual.positionSeconds.bitPattern, (-0.0 as Double).bitPattern)
        let receipt = try readyReceipt(&signedZero, offer: offer, update: state(position: -0.0), now: -0.0)
        XCTAssertEqual(receipt.actual.receivedAtUptime.bitPattern, (-0.0 as Double).bitPattern)
        XCTAssertTrue(signedZero.consume(receipt, state: received(state(position: 0.0)), now: 0.0))
        XCTAssertEqual(signedZero.consumeSent(offer, phonePosition: 0.0, state: state(position: 0.0), now: 0.0), 30)

        let now = Double.greatestFiniteMagnitude
        XCTAssertEqual(now + 30, now)
        var rounded = PairedOffers()
        rounded.recordSent(state(), now)
        let first = try XCTUnwrap(rounded.prepare(state(), authorization: authorization, now: now, id: id(1)))
        let expiredAtCreation = try readyReceipt(&rounded, offer: first, now: now)
        XCTAssertEqual(expiredAtCreation.actual.deadlineUptime.bitPattern, now.bitPattern)
        XCTAssertFalse(rounded.consume(expiredAtCreation, state: received(state()), now: now))
        let second = try XCTUnwrap(rounded.prepare(state(), authorization: authorization, now: now, id: id(2)))
        XCTAssertEqual(first.actual.sequence, 1)
        XCTAssertEqual(second.actual.sequence, 2)
        XCTAssertNil(rounded.consumeSent(second, phonePosition: 20, state: state(), now: now))
    }

    func testNativeSourceSnapshotAgeAndScaledDriftKeepOriginalBounds() throws {
        for observed in [Double(8).nextDown, 8, Double(8).nextUp] {
            var pair = PairedOffers()
            pair.recordSent(state(), 10)
            let source = WebRTCMediaHandoffSourceDescription(videoID: "dQw4w9WgXcQ", positionSeconds: 18,
                durationSeconds: 200, playbackRate: 1, observedAtUptime: observed, deadlineUptime: 38)
            let offer = pair.prepare(state(), authorization: authorization, now: 10, id: id(1), source: source)
            XCTAssertEqual(offer != nil, 10 - observed < 2)
        }
        for rate in [0.5, 1, 16] {
            let edge = 20 + 2 * rate + 0.25
            for position in [edge.nextDown, edge, edge.nextUp] {
                var pair = PairedOffers()
                let update = state(position: position, rate: rate)
                pair.recordSent(update, 10)
                let source = WebRTCMediaHandoffSourceDescription(videoID: "dQw4w9WgXcQ", positionSeconds: 20,
                    durationSeconds: 200, playbackRate: rate, observedAtUptime: 10, deadlineUptime: 40)
                let offer = pair.prepare(update, authorization: authorization, now: 10, id: id(1), source: source)
                XCTAssertEqual(offer != nil, position <= edge)
            }
        }
    }

    func testActualSuppliedCommitUnicodeAndNaNPreservePreconsumeValidityOrdering() throws {
        let composed = "caf\u{00e9}", decomposed = "cafe\u{0301}"
        var canonical = PairedOffers()
        canonical.recordSent(state(context: composed), 10)
        _ = try XCTUnwrap(canonical.prepare(state(context: composed), authorization: authorization,
                                             now: 10, id: id(1), context: composed))
        XCTAssertEqual(canonical.consumeSent(literal(context: decomposed), phonePosition: 20,
                                              state: state(context: composed), now: 10), 40)

        let short = String(repeating: "\u{00e9}", count: 64)
        let long = String(repeating: "e\u{0301}", count: 64)
        XCTAssertEqual(short, long)
        for malformed in [false, true] {
            var pair = PairedOffers()
            pair.recordSent(state(context: short), 10)
            let genuine = try XCTUnwrap(pair.prepare(state(context: short), authorization: authorization,
                                                    now: 10, id: id(1), context: short))
            let input = malformed ? genuine : literal(context: long)
            XCTAssertNil(pair.consumeSent(input, phonePosition: malformed ? .nan : 20,
                                           state: state(context: short), now: 10))
            // An invalid supplied commit does not consume the valid stored offer.
            XCTAssertEqual(pair.consumeSent(genuine, phonePosition: 20, state: state(context: short), now: 10), 40)
        }
        for invalid in [literal(position: .nan), literal(rate: .nan), literal(lifetime: .nan)] {
            var pair = PairedOffers()
            let receipt = try readyReceipt(&pair)
            XCTAssertNil(pair.receive(invalid, state: received(state()), now: .nan))
            XCTAssertTrue(pair.consume(receipt, state: received(state()), now: 10))
        }
    }

    func testSeededSendCounterExhaustionRefusesMaxAndClearCannotResetIt() throws {
        var pair = PairedOffers(testingNextSentSequence: .max - 1, highestReceivedSequence: 0, nextToken: 1)
        pair.recordSent(state(), 10)
        let last = try XCTUnwrap(pair.prepare(state(), authorization: authorization, now: 10, id: id(1)))
        XCTAssertEqual(last.actual.sequence, .max - 1)
        pair.sentFailed(last.actual.id)
        XCTAssertNil(pair.prepare(state(), authorization: authorization, now: 10, id: id(2)))
        pair.clear(); pair.recordSent(state(), 10)
        XCTAssertNil(pair.prepare(state(), authorization: authorization, now: 10, id: id(3)))
        pair.reset(); pair.recordSent(state(), 10)
        XCTAssertEqual(pair.prepare(state(), authorization: authorization, now: 10, id: id(4))?.actual.sequence, 1)
    }

    func testSeededReceiverMaxBurnAndIndependentSenderRemainInOriginalParity() throws {
        for stale in [false, true] {
            var pair = PairedOffers(testingNextSentSequence: 1, highestReceivedSequence: .max - 1, nextToken: 1)
            pair.recordReceived(state(), 10)
            let receipt = pair.receive(literal(.max), state: received(state()), now: stale ? 12 : 10)
            XCTAssertEqual(receipt != nil, !stale)
            pair.clear(); pair.recordReceived(state(), 10)
            XCTAssertNil(pair.receive(literal(.max), state: received(state()), now: 10))
            XCTAssertNil(pair.receive(literal(), state: received(state()), now: 10))
            pair.recordSent(state(), 10)
            XCTAssertEqual(pair.prepare(state(), authorization: authorization, now: 10, id: id(1))?.actual.sequence, 1)
        }
        var senderFull = PairedOffers(testingNextSentSequence: .max, highestReceivedSequence: 0, nextToken: 1)
        senderFull.recordSent(state(), 10); senderFull.recordReceived(state(), 10)
        XCTAssertNil(senderFull.prepare(state(), authorization: authorization, now: 10, id: id(1)))
        let receipt = try XCTUnwrap(senderFull.receive(literal(), state: received(state()), now: 10))
        XCTAssertTrue(senderFull.consume(receipt, state: received(state()), now: 10))
    }

    func testTokenMaxIssuesOnceAndExhaustionCannotReuseOrResetMintCapacity() throws {
        var store = MediaHandoffOffers(testingNextSentSequence: 1, highestReceivedSequence: 0, nextToken: .max)
        store.recordSentState(state(), now: 10)
        let offer = try XCTUnwrap(store.prepareSent(contextID: "selected", update: state(),
                                                  authorization: authorization, now: 10, id: id(1)))
        XCTAssertEqual(offer.sequence, 1)
        store.recordReceivedState(state(), now: 10)
        XCTAssertNil(store.receive(literal().actual, state: received(state()), now: 10))
        var copied = store
        let commit = WebRTCMediaHandoffCommitEnvelope(offer: offer, phonePositionSeconds: 20)
        XCTAssertEqual(store.consumeSent(commit, state: state(), now: 10), 40)
        XCTAssertEqual(copied.consumeSent(commit, state: state(), now: 10), 40)
        for _ in 0..<3 {
            store.clearTransient()
            store.recordSentState(state(), now: 10); store.recordReceivedState(state(), now: 10)
            XCTAssertNil(store.prepareSent(contextID: "selected", update: state(), authorization: authorization,
                                           now: 10, id: id(2)))
            XCTAssertNil(store.receive(literal(2).actual, state: received(state()), now: 10))
        }
        store = MediaHandoffOffers()
        store.recordSentState(state(), now: 10)
        XCTAssertEqual(store.prepareSent(contextID: "selected", update: state(), authorization: authorization,
                                        now: 10, id: id(3))?.sequence, 1)
    }

    func testTokenExhaustionStillExpiresSentAndRetiresReplacedReceived() throws {
        var sent = MediaHandoffOffers(testingNextSentSequence: 1, highestReceivedSequence: 0, nextToken: .max)
        sent.recordSentState(state(), now: 10)
        let offer = try XCTUnwrap(sent.prepareSent(contextID: "selected", update: state(),
                                                 authorization: authorization, now: 10, id: id(1)))
        XCTAssertNil(sent.prepareSent(contextID: "selected", update: state(), authorization: authorization,
                                     now: 40, id: id(2)))
        // Return to the formerly valid time: skipping expiry before candidate-token
        // refusal would wrongly keep this exact old offer usable.
        XCTAssertNil(sent.consumeSent(.init(offer: offer, phonePositionSeconds: 20), state: state(), now: 10))

        var viewer = MediaHandoffOffers(testingNextSentSequence: 1, highestReceivedSequence: 0, nextToken: .max)
        viewer.recordReceivedState(state(), now: 10)
        let receipt = try XCTUnwrap(viewer.receive(literal().actual, state: received(state()), now: 10))
        XCTAssertNil(viewer.receive(literal(2).actual, state: received(state()), now: 10))
        XCTAssertFalse(viewer.consume(receipt, state: received(state()), now: 10))
        viewer.clearTransient(); viewer.recordReceivedState(state(), now: 10)
        XCTAssertNil(viewer.receive(literal(2).actual, state: received(state()), now: 10))
    }

    func testZeroCounterSeedIsTerminalButZeroTokenOnlyRefusesNewMint() {
        for nextToken in [UInt64(0), 1, .max] {
            var closed = MediaHandoffOffers(testingNextSentSequence: 0, highestReceivedSequence: 0, nextToken: nextToken)
            for _ in 0..<2 {
                closed.recordSentState(state(), now: 10); closed.recordReceivedState(state(), now: 10)
                XCTAssertNil(closed.prepareSent(contextID: "selected", update: state(), authorization: authorization,
                                               now: 10, id: id(1)))
                XCTAssertNil(closed.receive(literal().actual, state: received(state()), now: 10))
                closed.clearTransient()
            }
        }
        var exhausted = MediaHandoffOffers(testingNextSentSequence: 1, highestReceivedSequence: 0, nextToken: 0)
        exhausted.recordSentState(state(), now: 10); exhausted.recordReceivedState(state(), now: 10)
        XCTAssertNil(exhausted.prepareSent(contextID: "selected", update: state(), authorization: authorization,
                                          now: 10, id: id(1)))
        XCTAssertNil(exhausted.receive(literal().actual, state: received(state()), now: 10))
    }

    private typealias Boundary = BelugaRustHandoffOffersBoundary
    private typealias OfferState = Boundary.State
    private typealias OfferEvent = Boundary.Event
    private typealias OfferOutput = Boundary.Output
    private typealias OfferTimeline = Boundary.Timeline

    private func scalarTimeline(_ token: UInt64, sequence: UInt64 = 1,
                                now: Double = 10, position: Double = 20) -> OfferTimeline {
        var value = OfferTimeline()
        value.token = token; value.sequence = sequence; value.revision = 1
        value.position = position.bitPattern; value.duration = (200.0).bitPattern
        value.rate = (1.0).bitPattern; value.lifetime = (30.0).bitPattern
        value.origin = now.bitPattern; value.deadline = (now + 30).bitPattern
        value.last_observation = now.bitPattern; value.last_position = position.bitPattern
        return value
    }

    private func scalarState(both: Bool = false) -> OfferState {
        var value = OfferState()
        value.abi = 1; value.next_sent = both ? 2 : 1
        if both {
            value.presence = 15; value.highest_received = 1
            value.sent_at = (10.0).bitPattern; value.received_at = (10.0).bitPattern
            value.sent = scalarTimeline(11); value.received = scalarTimeline(12)
        }
        return value
    }

    private func scalarEvent(_ opcode: UInt32, token: UInt64 = 0,
                             now: Double = 10, sequence: UInt64 = 1,
                             position: Double = 20) -> OfferEvent {
        var value = OfferEvent()
        value.opcode = opcode; value.token = token; value.native_matches = 15
        value.now = now.bitPattern; value.phone_position = position.bitPattern
        value.phone_observed_at = now.bitPattern
        value.primary.flags = 511; value.primary.native_matches = 12
        value.primary.revision = 1; value.primary.position = position.bitPattern
        value.primary.duration = (200.0).bitPattern; value.primary.rate = (1.0).bitPattern
        value.envelope.text_valid = 1; value.envelope.sequence = sequence
        value.envelope.revision = 1; value.envelope.position = position.bitPattern
        value.envelope.duration = (200.0).bitPattern; value.envelope.rate = (1.0).bitPattern
        value.envelope.lifetime = (30.0).bitPattern
        return value
    }

    private func scalarOutput(_ state: OfferState, decision: UInt32 = 0, effects: UInt32 = 0,
                              retiredSent: UInt64 = 0, retiredReceived: UInt64 = 0,
                              minted: UInt64 = 0, sequence: UInt64 = 0,
                              lifetime: Double? = nil, deadline: Double? = nil) -> OfferOutput {
        var value = OfferOutput()
        value.state = state; value.decision = decision; value.effects = effects
        value.retired_sent = retiredSent; value.retired_received = retiredReceived
        value.minted_token = minted; value.sequence = sequence
        value.lifetime = lifetime?.bitPattern ?? 0; value.deadline = deadline?.bitPattern ?? 0
        return value
    }

    func testCopiedOfferBoundaryAcceptsAllLegitimateCustodyTransitions() {
        typealias Case = (String, OfferState, OfferEvent, OfferOutput)
        var cases: [Case] = []
        let both = scalarState(both: true)
        let empty = scalarState()
        cases.append(("empty clear", empty, scalarEvent(9), scalarOutput(empty)))
        cases.append(("wrong sent failure", both, scalarEvent(3, token: 99), scalarOutput(both)))
        cases.append(("wrong receipt consumption", both, scalarEvent(6, token: 99), scalarOutput(both)))
        cases.append(("wrong receipt discard", both, scalarEvent(8, token: 99), scalarOutput(both)))
        var wrongHeader = scalarEvent(4); wrongHeader.native_matches &= ~4
        cases.append(("mismatched header preserves sent", both, wrongHeader, scalarOutput(both)))
        var staleSample = scalarEvent(7, token: 12); staleSample.phone_observed_at = (9.0).bitPattern
        cases.append(("stale sample preserves received", both, staleSample, scalarOutput(both)))
        var invalidPhone = scalarEvent(7, token: 12); invalidPhone.phone_position = Double.nan.bitPattern
        cases.append(("invalid phone wire payload preserves received", both, invalidPhone, scalarOutput(both)))
        var futureSample = scalarEvent(7, token: 12); futureSample.phone_observed_at = Double(10).nextUp.bitPattern
        cases.append(("future playback sample preserves received", both, futureSample, scalarOutput(both)))
        var nonfiniteSample = scalarEvent(7, token: 12); nonfiniteSample.phone_observed_at = Double.nan.bitPattern
        cases.append(("nonfinite playback sample preserves received", both, nonfiniteSample, scalarOutput(both)))
        cases.append(("nonfinite commit clock preserves received", both,
            scalarEvent(7, token: 12, now: .nan), scalarOutput(both)))

        for opcode in [UInt32(0), 1] {
            var after = both
            let observed = scalarEvent(opcode, now: 10.5, position: 20.5)
            if opcode == 0 {
                after.sent_at = (10.5).bitPattern
                after.sent.last_observation = (10.5).bitPattern; after.sent.last_position = (20.5).bitPattern
            } else {
                after.received_at = (10.5).bitPattern
                after.received.last_observation = (10.5).bitPattern; after.received.last_position = (20.5).bitPattern
            }
            cases.append(("record \(opcode) advancing", both, observed, scalarOutput(after)))
            var nonfiniteAfter = both
            if opcode == 0 {
                nonfiniteAfter.presence &= ~5; nonfiniteAfter.sent_at = 0; nonfiniteAfter.sent = .init()
            } else {
                nonfiniteAfter.presence &= ~10; nonfiniteAfter.received_at = 0; nonfiniteAfter.received = .init()
            }
            cases.append(("record \(opcode) nonfinite retirement", both, scalarEvent(opcode, now: .nan),
                scalarOutput(nonfiniteAfter, effects: opcode == 0 ? 1 : 2,
                             retiredSent: opcode == 0 ? 11 : 0, retiredReceived: opcode == 1 ? 12 : 0)))
        }

        var noSent = both; noSent.presence &= ~1; noSent.sent = .init()
        cases.append(("matching sent failure", both, scalarEvent(3, token: 11),
                      scalarOutput(noSent, effects: 1, retiredSent: 11)))
        cases.append(("sent consumed", both, scalarEvent(4),
                      scalarOutput(noSent, decision: 4, effects: 1, retiredSent: 11, deadline: 40)))
        cases.append(("late sent rejection still retires", both, scalarEvent(4, now: 12),
                      scalarOutput(noSent, effects: 1, retiredSent: 11)))
        var changedPrimary = scalarEvent(4); changedPrimary.primary.native_matches &= ~4
        cases.append(("matching header changed primary retires", both, changedPrimary,
                      scalarOutput(noSent, effects: 1, retiredSent: 11)))

        var noReceived = both; noReceived.presence &= ~2; noReceived.received = .init()
        for (opcode, decision) in [(UInt32(6), UInt32(3)), (7, 5), (8, 0)] {
            cases.append(("received retirement \(opcode)", both, scalarEvent(opcode, token: 12),
                scalarOutput(noReceived, decision: decision, effects: 2, retiredReceived: 12)))
        }
        var wrongAuth = scalarEvent(6, token: 12); wrongAuth.native_matches &= ~1
        cases.append(("exact receipt wrong auth retires", both, wrongAuth,
                      scalarOutput(noReceived, effects: 2, retiredReceived: 12)))

        var freshSent = empty; freshSent.presence = 4; freshSent.sent_at = (10.0).bitPattern
        var mintedSent = freshSent; mintedSent.presence |= 1; mintedSent.next_sent = 2
        mintedSent.sent = scalarTimeline(11)
        cases.append(("new sent mint", freshSent, scalarEvent(2, token: 11),
            scalarOutput(mintedSent, decision: 1, effects: 4, minted: 11, sequence: 1, lifetime: 30, deadline: 40)))

        var replaced = both; replaced.highest_received = 2
        replaced.received = scalarTimeline(13, sequence: 2)
        cases.append(("new received retires old and mints", both, scalarEvent(5, token: 13, sequence: 2),
            scalarOutput(replaced, decision: 2, effects: 10, retiredReceived: 12,
                         minted: 13, sequence: 2, lifetime: 30, deadline: 40)))
        var burned = noReceived; burned.highest_received = 2
        cases.append(("stale receive burns before validation", both, scalarEvent(5, token: 13, now: 12, sequence: 2),
            scalarOutput(burned, effects: 2, retiredReceived: 12)))
        var emptyBurned = empty; emptyBurned.highest_received = 1
        cases.append(("empty received slot still burns accepted incoming sequence", empty,
            scalarEvent(5, token: 13, now: 12), scalarOutput(emptyBurned)))

        var expiring = both; expiring.sent_at = (39.0).bitPattern
        var renewedOwner = expiring; renewedOwner.next_sent = 3
        renewedOwner.sent = scalarTimeline(13, sequence: 2, now: 40, position: 50)
        cases.append(("expired sent retires and new owner mints", expiring, scalarEvent(2, token: 13, now: 40, position: 50),
            scalarOutput(renewedOwner, decision: 1, effects: 5, retiredSent: 11,
                         minted: 13, sequence: 2, lifetime: 30, deadline: 70)))
        var cleared = both; cleared.presence = 0; cleared.sent_at = 0; cleared.received_at = 0
        cleared.sent = .init(); cleared.received = .init()
        cases.append(("clear retires both without counter reset", both, scalarEvent(9),
                      scalarOutput(cleared, effects: 3, retiredSent: 11, retiredReceived: 12)))

        XCTAssertEqual(cases.count, 28)
        for (name, before, event, output) in cases {
            XCTAssertTrue(Boundary.accepts(before: before, event: event, output: output), name)
        }
    }

    func testCopiedOfferBoundaryRejectsForgedMintConsumptionRetirementAndCounterReset() {
        typealias Case = (String, OfferState, OfferEvent, OfferOutput)
        var cases: [Case] = []
        let both = scalarState(both: true)
        var noSent = both; noSent.presence &= ~1; noSent.sent = .init()
        let consumed = scalarOutput(noSent, decision: 4, effects: 1, retiredSent: 11, deadline: 40)
        let consume = scalarEvent(4)
        let badConsume: [(String, (inout OfferOutput) -> Void)] = [
            ("missing retirement effect", { $0.effects = 0 }),
            ("wrong retired owner", { $0.retired_sent = 99 }),
            ("retained consumed owner", { $0.state = both }),
            ("renewed consumption deadline", { $0.deadline = (41.0).bitPattern }),
            ("send counter reset", { $0.state.next_sent = 1 }),
            ("receive counter reset", { $0.state.highest_received = 0 }),
            ("other owner dropped", { $0.state.presence &= ~2; $0.state.received = .init() }),
            ("other timestamp changed", { $0.state.received_at = (11.0).bitPattern }),
            ("absent slot retains payload", { $0.state.sent.position = (20.0).bitPattern }),
            ("unknown status", { $0.status = 1 }),
            ("invalid status with success", { $0.status = 3 }),
            ("unknown decision", { $0.decision = 99 }),
            ("unknown effect", { $0.effects |= 16 }),
            ("reserved result", { $0.reserved = 1 }),
            ("wrong state ABI", { $0.state.abi = 2 }),
            ("mint on consumption", { $0.effects |= 4; $0.minted_token = 13 }),
            ("phantom received retirement", { $0.effects |= 2; $0.retired_received = 12 })
        ]
        for (name, edit) in badConsume {
            var output = consumed; edit(&output); cases.append((name, both, consume, output))
        }
        let badInputs: [(String, (inout OfferEvent) -> Void)] = [
            ("wrong commit authorization", { (value: inout OfferEvent) in value.native_matches &= ~1 }),
            ("wrong commit context", { (value: inout OfferEvent) in value.native_matches &= ~4 }),
            ("wrong current-primary video", { (value: inout OfferEvent) in value.primary.native_matches &= ~8 }),
            ("unknown opcode success", { (value: inout OfferEvent) in value.opcode = 10 }),
            ("unknown primary flag", { (value: inout OfferEvent) in value.primary.flags |= 512 }),
            ("malformed text boolean", { (value: inout OfferEvent) in value.envelope.text_valid = 2 })
        ]
        for (name, edit) in badInputs {
            var event = consume; edit(&event); cases.append((name, both, event, consumed))
        }

        var fresh = scalarState(); fresh.presence = 4; fresh.sent_at = (10.0).bitPattern
        var sent = fresh; sent.presence |= 1; sent.next_sent = 2; sent.sent = scalarTimeline(11)
        let minted = scalarOutput(sent, decision: 1, effects: 4, minted: 11, sequence: 1, lifetime: 30, deadline: 40)
        let prepare = scalarEvent(2, token: 11)
        let badMint: [(String, (inout OfferOutput) -> Void)] = [
            ("mint effect missing", { $0.effects = 0 }),
            ("zero minted token", { $0.minted_token = 0 }),
            ("mint differs from input candidate", { $0.minted_token = 99; $0.state.sent.token = 99 }),
            ("mint sequence differs", { $0.sequence = 2 }),
            ("mint lifetime differs", { $0.lifetime = (29.0).bitPattern }),
            ("mint deadline differs", { $0.deadline = (41.0).bitPattern }),
            ("send counter jumps", { $0.state.next_sent = 3 }),
            ("mint unknown slot bit", { $0.state.presence |= 16 }),
            ("mint nonfinite origin", { $0.state.sent.origin = Double.nan.bitPattern })
        ]
        for (name, edit) in badMint {
            var output = minted; edit(&output); cases.append((name, fresh, prepare, output))
        }
        cases.append(("mint on record", fresh, scalarEvent(0, token: 11), minted))
        var advanced = both
        advanced.sent_at = (10.5).bitPattern
        advanced.sent.last_observation = (10.5).bitPattern
        advanced.sent.last_position = (20.5).bitPattern
        var regressed = advanced
        regressed.sent_at = (10.6).bitPattern
        regressed.sent.last_observation = (10.6).bitPattern
        regressed.sent.last_position = (20.4).bitPattern
        cases.append(("retained record rolls back position above original floor", advanced,
            scalarEvent(0, now: 10.6, position: 20.4), scalarOutput(regressed)))

        var replaced = both; replaced.highest_received = 2; replaced.received = scalarTimeline(13, sequence: 2)
        let receivedMint = scalarOutput(replaced, decision: 2, effects: 10, retiredReceived: 12,
                                       minted: 13, sequence: 2, lifetime: 30, deadline: 40)
        let receive = scalarEvent(5, token: 13, sequence: 2)
        var wrongFloor = receivedMint; wrongFloor.state.highest_received = 3
        cases.append(("receiver floor exceeds incoming", both, receive, wrongFloor))
        var missingOld = receivedMint; missingOld.effects = 8; missingOld.retired_received = 0
        cases.append(("replacement lacks exact old retirement", both, receive, missingOld))
        var wrongIncomingAuth = receive; wrongIncomingAuth.native_matches &= ~1
        cases.append(("receive minted without incoming authorization", both, wrongIncomingAuth, receivedMint))
        var wrongIncomingPrimary = receive; wrongIncomingPrimary.primary.native_matches = 0
        cases.append(("receive matched wrong primary domain", both, wrongIncomingPrimary, receivedMint))

        var expiring = both; expiring.sent_at = (39.0).bitPattern
        for reused in [UInt64(11), 12] {
            var after = expiring; after.next_sent = 3
            after.sent = scalarTimeline(reused, sequence: 2, now: 40, position: 50)
            cases.append(("reused native owner \(reused)", expiring,
                scalarEvent(2, token: reused, now: 40, position: 50),
                scalarOutput(after, decision: 1, effects: 5, retiredSent: 11,
                             minted: reused, sequence: 2, lifetime: 30, deadline: 70)))
        }
        var cleared = both; cleared.presence = 0; cleared.sent_at = 0; cleared.received_at = 0
        cleared.sent = .init(); cleared.received = .init()
        var badClear = scalarOutput(cleared, effects: 3, retiredSent: 11, retiredReceived: 12)
        badClear.state.next_sent = 1; badClear.state.highest_received = 0
        cases.append(("clear resets counters", both, scalarEvent(9), badClear))
        cases.append(("clear refuses live ownership cleanup", both, scalarEvent(9), scalarOutput(both)))
        var retainTimestamp = scalarOutput(cleared, effects: 3, retiredSent: 11, retiredReceived: 12)
        retainTimestamp.state.presence = 4; retainTimestamp.state.sent_at = (10.0).bitPattern
        cases.append(("clear retains freshness", both, scalarEvent(9), retainTimestamp))
        var consumeReceived = scalarEvent(6, token: 99)
        var noReceived = both; noReceived.presence &= ~2; noReceived.received = .init()
        let receiptConsumed = scalarOutput(noReceived, decision: 3, effects: 2, retiredReceived: 12)
        cases.append(("counterfeit receipt consumed", both, consumeReceived, receiptConsumed))
        consumeReceived.token = 12
        var retained = receiptConsumed; retained.state = both
        cases.append(("receipt success retains native ownership", both, consumeReceived, retained))
        for opcode in [UInt32(6), 7] {
            cases.append(("counterfeit receipt retired on declined \(opcode)", both,
                scalarEvent(opcode, token: 99), scalarOutput(noReceived, effects: 2, retiredReceived: 12)))
        }
        let declinedSent = scalarOutput(noSent, effects: 1, retiredSent: 11)
        let wrongRetirementInputs: [(String, (inout OfferEvent) -> Void)] = [
            ("mismatched header retired on decline", { $0.native_matches &= ~4 }),
            ("mismatched sequence retired on decline", { $0.envelope.sequence = 2 }),
            ("mismatched duration retired on decline", { $0.envelope.duration = (201.0).bitPattern }),
            ("mismatched rate retired on decline", { $0.envelope.rate = (2.0).bitPattern })
        ]
        for (name, edit) in wrongRetirementInputs {
            var event = consume; edit(&event); cases.append((name, both, event, declinedSent))
        }
        for (name, event) in [
            ("exact sent failure skips retirement", scalarEvent(3, token: 11)),
            ("exact receipt discard skips retirement", scalarEvent(8, token: 12)),
            ("exact receipt consume skips retirement", scalarEvent(6, token: 12)),
            ("matching valid sent consume skips retirement", consume)
        ] {
            cases.append((name, both, event, scalarOutput(both)))
        }
        for observed in [10.0, 9.25] {
            var event = scalarEvent(7, token: 12); event.phone_observed_at = observed.bitPattern
            cases.append(("valid commit sample skips required retirement \(observed)", both,
                event, scalarOutput(both)))
        }
        var wrongCommitAuth = scalarEvent(7, token: 12); wrongCommitAuth.native_matches &= ~1
        cases.append(("valid commit sample with changed auth skips retirement", both,
            wrongCommitAuth, scalarOutput(both)))
        for (name, observed, now) in [
            ("NaN observed", Double.nan, 10.0),
            ("infinite observed", Double.infinity, 10.0),
            ("future observed", Double(10).nextUp, 10.0),
            ("older than inclusive sample bound", Double(9.25).nextDown, 10.0),
            ("NaN current clock", 10.0, Double.nan)
        ] {
            var event = scalarEvent(7, token: 12, now: now); event.phone_observed_at = observed.bitPattern
            for decision in [UInt32(0), 5] {
                cases.append(("invalid sample \(name) forged retirement decision \(decision)", both, event,
                    scalarOutput(noReceived, decision: decision, effects: 2, retiredReceived: 12)))
            }
        }
        for sequence in [UInt64(1), 2] {
            cases.append(("received retirement without exact floor burn \(sequence)", both,
                scalarEvent(5, token: 13, sequence: sequence),
                scalarOutput(noReceived, effects: 2, retiredReceived: 12)))
        }
        let emptyReceived = scalarState()
        cases.append(("empty received slot skips required sequence burn", emptyReceived,
            scalarEvent(5, token: 13), scalarOutput(emptyReceived)))
        var emptyBurned = emptyReceived; emptyBurned.highest_received = 1
        let invalidEnvelopeInputs: [(String, (inout OfferEvent) -> Void)] = [
            ("zero revision cannot burn floor", { $0.envelope.revision = 0 }),
            ("nonfinite position cannot burn floor", { $0.envelope.position = Double.nan.bitPattern }),
            ("zero duration cannot burn floor", { $0.envelope.duration = (0.0).bitPattern }),
            ("out-of-range rate cannot burn floor", { $0.envelope.rate = (17.0).bitPattern }),
            ("out-of-range lifetime cannot burn floor", { $0.envelope.lifetime = (31.0).bitPattern })
        ]
        for (name, edit) in invalidEnvelopeInputs {
            var event = scalarEvent(5, token: 13); edit(&event)
            cases.append((name, emptyReceived, event, scalarOutput(emptyBurned)))
        }

        XCTAssertEqual(cases.count, 76)
        for (name, before, event, output) in cases {
            XCTAssertFalse(Boundary.accepts(before: before, event: event, output: output), name)
        }
    }
}
