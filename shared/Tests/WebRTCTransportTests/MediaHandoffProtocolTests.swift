import Foundation
import XCTest
@testable import WebRTCTransport

final class MediaHandoffProtocolTests: XCTestCase {
    private let authority = WebRTCRemoteMediaAuthorization()
    private func state(_ revision: UInt64 = 1, position: Double = 20, rate: Double = 1,
                       context: String = "original", playing: Bool = true) -> WebRTCRemoteMediaStateUpdate {
        .init(revision: revision, item: .init(contextID: context, sourceName: "YouTube", title: "Test",
            playbackState: playing ? .playing : .paused, elapsedTime: position, duration: 200,
            playbackRate: rate, capabilities: .init(canPlay: true, canPause: true,
                canSkipForward: false, canSkipBackward: false, canSeekToPosition: true),
            artwork: .init(videoID: "dQw4w9WgXcQ")))
    }
    private func received(_ update: WebRTCRemoteMediaStateUpdate) -> WebRTCReceivedRemoteMediaState {
        .init(envelope: .init(authorization: authority, update: update))
    }
    private func offer(_ store: inout MediaHandoffOffers) throws -> WebRTCMediaHandoffOfferEnvelope {
        store.recordSentState(state(), now: 10)
        return try XCTUnwrap(store.prepareSent(contextID: "original", update: state(), authorization: authority, now: 10))
    }

    func testDefaultOffAndExactAdditiveSDPEcho() {
        XCTAssertFalse(WebRTCTransportConfiguration(role: .viewer, iceServers: [], supportsRemoteMediaControls: true).supportsMediaHandoff)
        let base = "v=0\r\nm=audio 9 RTP/AVP 0\r\n"
        let legacy = RemoteMediaControlsSDP.advertisingHostSupport(in: base, authorization: authority)
        XCTAssertNil(MediaHandoffSDP.advertisedAuthorization(in: legacy))
        let host = RemoteMediaControlsSDP.advertisingHostSupport(in: base, authorization: authority, supportsMediaHandoff: true)
        let answer = RemoteMediaControlsSDP.advertisingViewerSupport(in: base, remoteOfferSDP: host, supportsMediaHandoff: true)
        XCTAssertTrue(MediaHandoffSDP.negotiated(hostOfferSDP: host, viewerAnswerSDP: answer))
        XCTAssertFalse(MediaHandoffSDP.negotiated(hostOfferSDP: host,
            viewerAnswerSDP: RemoteMediaControlsSDP.advertisingViewerSupport(in: base, remoteOfferSDP: host)))
        XCTAssertNil(MediaHandoffSDP.advertisedAuthorization(in:
            RemoteMediaControlsSDP.advertisingViewerSupport(in: base, remoteOfferSDP: legacy, supportsMediaHandoff: true)))
        let line = MediaHandoffSDP.attributePrefix + "1:" + authority.id.uuidString.lowercased()
        XCTAssertFalse(MediaHandoffSDP.negotiated(hostOfferSDP: host, viewerAnswerSDP: line + "\r\n" + answer))
        XCTAssertFalse(MediaHandoffSDP.negotiated(hostOfferSDP: host,
            viewerAnswerSDP: answer.replacingOccurrences(of: line, with: MediaHandoffSDP.attributePrefix + "1:" + UUID().uuidString.lowercased())))
        XCTAssertNil(MediaHandoffSDP.advertisedAuthorization(in: base + line + "\r\n"))
    }

    func testOfferWireRoundTripIsBoundedAndReceiptLogsHideSource() throws {
        var host = MediaHandoffOffers()
        let value = try offer(&host)
        let wire = try JSONEncoder().encode(ControlChannelMessage.mediaHandoffOffer(value))
        XCTAssertLessThan(wire.count, 4096)
        XCTAssertEqual(try JSONDecoder().decode(ControlChannelMessage.self, from: wire), .mediaHandoffOffer(value))
        XCTAssertTrue(value.isValid)
        XCTAssertFalse(String(describing: WebRTCReceivedMediaHandoffOffer(envelope: value, receivedAtUptime: 10)).contains(value.videoID))
    }

    func testOnlyFreshPrimaryPlayingSeekableSourceCanIssueAndOneIsPending() throws {
        var host = MediaHandoffOffers()
        XCTAssertNil(host.prepareSent(contextID: "original", update: state(), authorization: authority, now: 10))
        _ = try offer(&host)
        XCTAssertNil(host.prepareSent(contextID: "original", update: state(), authorization: authority, now: 10.2))
        host.clearTransient()
        host.recordSentState(state(), now: 10)
        XCTAssertNil(host.prepareSent(contextID: "original", update: state(), authorization: authority, now: 12))
        XCTAssertNil(host.prepareSent(contextID: "other", update: state(), authorization: authority, now: 11))
        XCTAssertNil(host.prepareSent(contextID: "original", update: state(playing: false), authorization: authority, now: 11))
    }

    func testReceiptIsExactOneUseAndDuplicateCannotRenewDeadline() throws {
        var host = MediaHandoffOffers(), viewer = MediaHandoffOffers()
        let envelope = try offer(&host)
        viewer.recordReceivedState(state(), now: 11)
        let receipt = try XCTUnwrap(viewer.receive(envelope, state: received(state()), now: 11))
        XCTAssertEqual(receipt.deadlineUptime, 41)
        XCTAssertNil(viewer.receive(envelope, state: received(state()), now: 12))
        let counterfeit = WebRTCReceivedMediaHandoffOffer(envelope: envelope, receivedAtUptime: 11)
        XCTAssertFalse(viewer.consume(counterfeit, state: received(state()), now: 11.1))
        XCTAssertTrue(viewer.consume(receipt, state: received(state()), now: 11.2))
        XCTAssertFalse(viewer.consume(receipt, state: received(state()), now: 11.3))
    }

    func testRejectedOfferCannotReviveAfterSnapshotRefresh() throws {
        var host = MediaHandoffOffers(), viewer = MediaHandoffOffers()
        let envelope = try offer(&host)
        XCTAssertNil(viewer.receive(envelope, state: received(state()), now: 11))
        viewer.recordReceivedState(state(), now: 12)
        XCTAssertNil(viewer.receive(envelope, state: received(state()), now: 12))
    }

    func testSourceReplacementPauseSeekRateAndClockRegressionRevokeReceipt() throws {
        for update in [state(2, context: "other"), state(2, playing: false), state(2, position: 2),
                       state(2, position: 90), state(2, rate: 2)] {
            var host = MediaHandoffOffers(), viewer = MediaHandoffOffers()
            let envelope = try offer(&host)
            viewer.recordReceivedState(state(), now: 10)
            let receipt = try XCTUnwrap(viewer.receive(envelope, state: received(state()), now: 10))
            viewer.recordReceivedState(update, now: 10.5)
            viewer.recordReceivedState(state(3, position: 21), now: 11)
            XCTAssertFalse(viewer.consume(receipt, state: received(state(3, position: 21)), now: 11))
        }
        var host = MediaHandoffOffers(), viewer = MediaHandoffOffers()
        let envelope = try offer(&host)
        viewer.recordReceivedState(state(), now: 10)
        let receipt = try XCTUnwrap(viewer.receive(envelope, state: received(state()), now: 10))
        XCTAssertFalse(viewer.consume(receipt, state: received(state()), now: 9))
        XCTAssertFalse(viewer.consume(receipt, state: received(state()), now: 10.1))
    }

    func testDeadlineDiscardAndContinuityResetCannotReviveReceipt() throws {
        for boundary in 0..<3 {
            var host = MediaHandoffOffers(), viewer = MediaHandoffOffers()
            let envelope = try offer(&host)
            viewer.recordReceivedState(state(), now: 10)
            let receipt = try XCTUnwrap(viewer.receive(envelope, state: received(state()), now: 10))
            if boundary == 0 { viewer.clearTransient() }
            if boundary == 1 { viewer.discard(receipt) }
            let now = boundary == 2 ? 40.0 : 11.0
            let update = state(2, position: 20 + now - 10)
            viewer.recordReceivedState(update, now: now)
            XCTAssertFalse(viewer.consume(receipt, state: received(update), now: now))
        }
    }

    func testNativeHealthABAInvalidatesPassiveContinuityBeforeActorDrain() throws {
        let boundaries: [(WebRTCDelegateProxy) -> Void] = [
            { $0.receivePeerStateForTesting(.disconnected) },
            { $0.receiveICEStateForTesting(.checking) },
            { $0.receiveDataChannelStateForTesting(.closing) },
            { $0.receiveControlProtocolFailureForTesting() }
        ]
        for boundary in boundaries {
            let proxy = WebRTCDelegateProxy()
            proxy.markNativeTransportHealthyForTesting()
            let initial = try XCTUnwrap(proxy.currentMediaHandoffContinuity())
            XCTAssertEqual(proxy.currentMediaHandoffContinuity(), initial)
            boundary(proxy)
            proxy.markNativeTransportHealthyForTesting()
            XCTAssertNotEqual(proxy.currentMediaHandoffContinuity(), initial)
            proxy.close()
            XCTAssertNil(proxy.currentMediaHandoffContinuity())
        }
    }

    func testNativeBacklogFailureCannotMintNewContinuity() throws {
        let proxy = WebRTCDelegateProxy()
        proxy.markNativeTransportHealthyForTesting()
        XCTAssertNotNil(proxy.currentMediaHandoffContinuity())
        for _ in 0...256 { proxy.emitForTesting(.negotiationNeeded) }
        XCTAssertTrue(proxy.didFailEventDelivery())
        proxy.markNativeTransportHealthyForTesting()
        XCTAssertNil(proxy.currentMediaHandoffContinuity())
        proxy.close()
    }
}
