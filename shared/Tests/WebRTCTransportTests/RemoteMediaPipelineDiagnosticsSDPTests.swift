import Foundation
@testable import WebRTCTransport
import XCTest

final class RemoteMediaPipelineDiagnosticsSDPTests: XCTestCase {
    private let base = "v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n"

    func testExactSessionEchoRequiresExistingAudioDiagnosticsNegotiation() {
        let nonce = UUID()
        let offer = hostOffer(nonce: nonce)
        let answer = viewerAnswer(offer: offer)
        XCTAssertTrue(RemoteMediaPipelineDiagnosticsSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: answer))
        XCTAssertEqual(RemoteMediaPipelineDiagnosticsSDP.advertisedAuthorization(in: offer), nonce)
        XCTAssertEqual(RemoteMediaPipelineDiagnosticsSDP.advertisingHostSupport(in: offer), offer)
        XCTAssertEqual(RemoteMediaPipelineDiagnosticsSDP.advertisingViewerSupport(in: answer, hostOfferSDP: offer), answer)
        XCTAssertEqual(RemoteMediaPipelineDiagnosticsSDP.advertisingHostSupport(in: base), base)
        XCTAssertEqual(RemoteMediaPipelineDiagnosticsSDP.advertisingViewerSupport(in: base, hostOfferSDP: offer), base)
    }

    func testLegacyHostOrViewerNeverNegotiatesAdditionalHeartbeatFields() {
        let legacyOffer = AudioClientDiagnosticsSDP.advertisingHostSupport(in: base, authorization: UUID())
        let answer = AudioClientDiagnosticsSDP.advertisingViewerSupport(in: base, remoteOfferSDP: legacyOffer)
        XCTAssertEqual(RemoteMediaPipelineDiagnosticsSDP.advertisingViewerSupport(in: answer, hostOfferSDP: legacyOffer), answer)
        XCTAssertFalse(RemoteMediaPipelineDiagnosticsSDP.negotiated(hostOfferSDP: legacyOffer, viewerAnswerSDP: answer))
        let offer = hostOffer(nonce: UUID())
        let legacyAnswer = AudioClientDiagnosticsSDP.advertisingViewerSupport(in: base, remoteOfferSDP: offer)
        XCTAssertFalse(RemoteMediaPipelineDiagnosticsSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: legacyAnswer))
    }

    func testDuplicateMalformedMediaLevelOrWrongNonceMarkersFailClosed() {
        let nonce = UUID()
        let offer = hostOffer(nonce: nonce)
        let answer = viewerAnswer(offer: offer)
        let line = RemoteMediaPipelineDiagnosticsSDP.attributePrefix + "1:" + nonce.uuidString.lowercased()
        let invalid = [
            line + "\r\n" + answer,
            answer + line + "\r\n",
            answer.replacingOccurrences(of: line, with: line.replacingOccurrences(of: ":1:", with: ":2:")),
            answer.replacingOccurrences(of: line, with: RemoteMediaPipelineDiagnosticsSDP.attributePrefix + "1:" + UUID().uuidString.lowercased()),
            answer.replacingOccurrences(of: line, with: RemoteMediaPipelineDiagnosticsSDP.attributePrefix + "1:invalid"),
            answer.replacingOccurrences(of: line, with: line + ":extra"),
            answer.replacingOccurrences(of: line + "\r\n", with: "") + line + "\r\n",
        ]
        for candidate in invalid {
            XCTAssertFalse(RemoteMediaPipelineDiagnosticsSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: candidate))
            let malformedOffer = candidate
            let ordinaryAnswer = AudioClientDiagnosticsSDP.advertisingViewerSupport(in: base, remoteOfferSDP: malformedOffer)
            XCTAssertEqual(RemoteMediaPipelineDiagnosticsSDP.advertisingViewerSupport(in: ordinaryAnswer, hostOfferSDP: malformedOffer), ordinaryAnswer)
        }
    }

    func testMarkerWithoutMatchingAudioNonceCannotNegotiate() {
        let offer = hostOffer(nonce: UUID())
        let other = hostOffer(nonce: UUID())
        XCTAssertFalse(RemoteMediaPipelineDiagnosticsSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: viewerAnswer(offer: other)))
        let markerOnly = "v=0\r\n" + RemoteMediaPipelineDiagnosticsSDP.attributePrefix + "1:" + UUID().uuidString.lowercased() + "\r\n"
        XCTAssertFalse(RemoteMediaPipelineDiagnosticsSDP.negotiated(hostOfferSDP: markerOnly, viewerAnswerSDP: markerOnly))
    }

    private func hostOffer(nonce: UUID) -> String {
        RemoteMediaPipelineDiagnosticsSDP.advertisingHostSupport(in:
            AudioClientDiagnosticsSDP.advertisingHostSupport(in: base, authorization: nonce))
    }

    private func viewerAnswer(offer: String) -> String {
        RemoteMediaPipelineDiagnosticsSDP.advertisingViewerSupport(in:
            AudioClientDiagnosticsSDP.advertisingViewerSupport(in: base, remoteOfferSDP: offer), hostOfferSDP: offer)
    }
}
