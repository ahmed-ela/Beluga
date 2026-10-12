import Foundation
import XCTest
@testable import WebRTCTransport

final class MediaHandoffTransactionTests: XCTestCase {
    private let authority = WebRTCRemoteMediaAuthorization()
    private func state(_ revision: UInt64 = 1, position: Double = 20) -> WebRTCRemoteMediaStateUpdate {
        .init(revision: revision, item: .init(contextID: "selected", sourceName: "YouTube", title: "Test",
            playbackState: .playing, elapsedTime: position, duration: 200, playbackRate: 1,
            capabilities: .init(canPlay: true, canPause: true, canSkipForward: false,
                canSkipBackward: false, canSeekToPosition: true), artwork: .init(videoID: "dQw4w9WgXcQ")))
    }
    private func offer(_ host: inout MediaHandoffOffers) throws -> WebRTCMediaHandoffOfferEnvelope {
        host.recordSentState(state(), now: 10)
        return try XCTUnwrap(host.prepareSent(contextID: "selected", update: state(), authorization: authority, now: 10))
    }
    private func receipt(_ envelope: WebRTCMediaHandoffCommitEnvelope,
                         current: @escaping @Sendable () -> Bool = { true }) -> WebRTCReceivedMediaHandoffCommit {
        .init(envelope: envelope, deadlineUptime: ProcessInfo.processInfo.systemUptime + 10,
              continuityIsCurrent: current)
    }

    func testCommitCompletionAndCancellationWireRemainBoundedAndExact() throws {
        var host = MediaHandoffOffers()
        let envelope = WebRTCMediaHandoffCommitEnvelope(offer: try offer(&host), phonePositionSeconds: 20.5)
        for message in [ControlChannelMessage.mediaHandoffCommit(envelope),
                        .mediaHandoffCompletion(.init(commit: envelope, result: .macPaused)),
                        .mediaHandoffCancellation(envelope)] {
            let data = try JSONEncoder().encode(message)
            XCTAssertLessThan(data.count, 4096)
            XCTAssertEqual(try JSONDecoder().decode(ControlChannelMessage.self, from: data), message)
        }
        XCTAssertFalse(String(describing: receipt(envelope)).contains(envelope.videoID))
    }

    func testNativeOfferConsumptionIsOneUseAndRetiredTimelineCannotRevive() throws {
        for changed in [false, true] {
            var host = MediaHandoffOffers()
            let envelope = WebRTCMediaHandoffCommitEnvelope(offer: try offer(&host), phonePositionSeconds: 20)
            let first = host.consumeSent(envelope, state: state(2, position: changed ? 80 : 20), now: 10.1)
            XCTAssertEqual(first, changed ? nil : 40)
            XCTAssertNil(host.consumeSent(envelope, state: state(3), now: 10.2))
        }
        var host = MediaHandoffOffers()
        let envelope = WebRTCMediaHandoffCommitEnvelope(offer: try offer(&host), phonePositionSeconds: 20)
        XCTAssertNil(host.consumeSent(envelope, state: state(), now: 40))
    }

    func testNativeDescriptionCannotBeSubstitutedAndOfferKeepsOriginalDeadline() throws {
        let id = UUID()
        for field in ["valid", "video", "position", "duration", "rate", "age", "deadline"] {
            var host = MediaHandoffOffers()
            host.recordSentState(state(), now: 11)
            let source = WebRTCMediaHandoffSourceDescription(videoID: field == "video" ? "abcdefghijk" : "dQw4w9WgXcQ",
                positionSeconds: field == "position" ? 80 : 19,
                durationSeconds: field == "duration" ? 400 : 200, playbackRate: field == "rate" ? 2 : 1,
                observedAtUptime: field == "age" ? 8 : 10, deadlineUptime: field == "deadline" ? 45 : 40)
            let value = host.prepareSent(contextID: "selected", update: state(), authorization: authority,
                now: 11, id: id, source: source)
            if field == "valid" { XCTAssertEqual(value?.id, id); XCTAssertEqual(value?.validForSeconds, 29) }
            else { XCTAssertNil(value, field) }
        }
    }

    func testStalePlaybackSampleDoesNotDispatchAndFreshReceiptCommitsOnce() throws {
        var host = MediaHandoffOffers(), viewer = MediaHandoffOffers()
        let value = try offer(&host)
        let received = WebRTCReceivedRemoteMediaState(envelope: .init(authorization: authority, update: state()))
        viewer.recordReceivedState(state(), now: 10)
        let offer = try XCTUnwrap(viewer.receive(value, state: received, now: 10))
        for observed in [9.0, 11.0, Double.nan] {
            XCTAssertNil(viewer.prepareCommit(offer, phonePositionSeconds: 20,
                observedAtUptime: observed, state: received, now: 10))
        }
        let commit = try XCTUnwrap(viewer.prepareCommit(offer, phonePositionSeconds: 20,
            observedAtUptime: 10, state: received, now: 10))
        XCTAssertTrue(commit.matches(value))
        XCTAssertNil(viewer.prepareCommit(offer, phonePositionSeconds: 20,
            observedAtUptime: 10, state: received, now: 10))
    }

    func testExactReceiptAndExactCompletionRequiredNoConflictingReplay() throws {
        var host = MediaHandoffOffers(), transactions = MediaHandoffTransactions()
        let value = try offer(&host)
        let envelope = WebRTCMediaHandoffCommitEnvelope(offer: value, phonePositionSeconds: 20)
        let accepted = receipt(envelope)
        XCTAssertTrue(transactions.admitHost(accepted))
        XCTAssertFalse(transactions.admitHost(receipt(envelope)))
        XCTAssertNil(transactions.finishHost(receipt(envelope), result: .macPaused))
        let reply = try XCTUnwrap(transactions.finishHost(accepted, result: .macPaused))
        XCTAssertFalse(accepted.isValid)
        XCTAssertEqual(transactions.finishHost(accepted, result: .macPaused), reply)
        XCTAssertNil(transactions.finishHost(accepted, result: .notApplied))
        XCTAssertTrue(transactions.beginViewer(envelope))
        XCTAssertFalse(transactions.beginViewer(envelope))
        let changed = WebRTCMediaHandoffCommitEnvelope(offer: value, phonePositionSeconds: 21)
        XCTAssertNil(transactions.receiveCompletion(.init(commit: changed, result: .macPaused)))
        XCTAssertEqual(transactions.receiveCompletion(reply), .init(id: value.id, result: .macPaused))
        XCTAssertNil(transactions.receiveCompletion(reply))
    }

    func testTimeoutAndClearAreUnknownAndCannotReviveNativeAuthority() throws {
        var host = MediaHandoffOffers(), transactions = MediaHandoffTransactions()
        let value = try offer(&host), envelope = WebRTCMediaHandoffCommitEnvelope(offer: value, phonePositionSeconds: 20)
        let accepted = receipt(envelope)
        XCTAssertTrue(transactions.admitHost(accepted)); XCTAssertTrue(accepted.isValid)
        XCTAssertTrue(transactions.beginViewer(envelope))
        XCTAssertNil(transactions.expireViewer(id: UUID()))
        XCTAssertEqual(transactions.clear(), .init(id: value.id, result: .outcomeUnknown))
        XCTAssertFalse(accepted.isValid)
        XCTAssertNil(transactions.finishHost(accepted, result: .macPaused))
        XCTAssertTrue(transactions.beginViewer(envelope))
        XCTAssertEqual(transactions.expireViewer(id: value.id), .init(id: value.id, result: .outcomeUnknown))
        XCTAssertNil(transactions.receiveCompletion(.init(commit: envelope, result: .macPaused)))
    }

    func testNativeDisconnectRecoveryRetiresCommitBeforeActorDrain() throws {
        var host = MediaHandoffOffers()
        let envelope = WebRTCMediaHandoffCommitEnvelope(offer: try offer(&host), phonePositionSeconds: 20)
        let proxy = WebRTCDelegateProxy(); proxy.markNativeTransportHealthyForTesting()
        let continuity = try XCTUnwrap(proxy.currentMediaHandoffContinuity())
        let accepted = receipt(envelope) { proxy.currentMediaHandoffContinuity() == continuity }
        XCTAssertTrue(accepted.isValid)
        proxy.receivePeerStateForTesting(.disconnected)
        proxy.markNativeTransportHealthyForTesting()
        XCTAssertFalse(accepted.isValid)
        proxy.close()
    }
}
