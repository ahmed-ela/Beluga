import Foundation
@testable import WebRTCTransport
import XCTest

final class RemoteMediaSurfaceDiagnosticsTests: XCTestCase {
    private let base = "v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n"

    func testSurfaceSchemaRequiresItsOwnCurrentAudioAndPipelineNonceEcho() {
        let nonce = UUID()
        let offer = hostOffer(nonce: nonce)
        let answer = viewerAnswer(offer: offer)
        XCTAssertTrue(RemoteMediaSurfaceDiagnosticsSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: answer))
        XCTAssertEqual(RemoteMediaSurfaceDiagnosticsSDP.advertisedAuthorization(in: offer), nonce)
        XCTAssertEqual(RemoteMediaSurfaceDiagnosticsSDP.advertisingHostSupport(in: offer), offer)
        XCTAssertEqual(RemoteMediaSurfaceDiagnosticsSDP.advertisingViewerSupport(in: answer, hostOfferSDP: offer), answer)
        XCTAssertEqual(RemoteMediaSurfaceDiagnosticsSDP.advertisingHostSupport(in: base), base)

        let oldHost = RemoteMediaPipelineDiagnosticsSDP.advertisingHostSupport(in:
            AudioClientDiagnosticsSDP.advertisingHostSupport(in: base, authorization: nonce))
        let oldAnswer = RemoteMediaPipelineDiagnosticsSDP.advertisingViewerSupport(in:
            AudioClientDiagnosticsSDP.advertisingViewerSupport(in: base, remoteOfferSDP: oldHost), hostOfferSDP: oldHost)
        XCTAssertEqual(RemoteMediaSurfaceDiagnosticsSDP.advertisingViewerSupport(in: oldAnswer, hostOfferSDP: oldHost), oldAnswer)
        XCTAssertFalse(RemoteMediaSurfaceDiagnosticsSDP.negotiated(hostOfferSDP: oldHost, viewerAnswerSDP: oldAnswer))
        let legacyViewer = RemoteMediaPipelineDiagnosticsSDP.advertisingViewerSupport(in:
            AudioClientDiagnosticsSDP.advertisingViewerSupport(in: base, remoteOfferSDP: offer), hostOfferSDP: offer)
        XCTAssertFalse(RemoteMediaSurfaceDiagnosticsSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: legacyViewer))
        let other = hostOffer(nonce: UUID())
        XCTAssertFalse(RemoteMediaSurfaceDiagnosticsSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: viewerAnswer(offer: other)))
    }

    func testDuplicateMalformedMediaLevelAndMissingAncestorMarkersFailClosed() {
        let nonce = UUID()
        let offer = hostOffer(nonce: nonce)
        let answer = viewerAnswer(offer: offer)
        let line = RemoteMediaSurfaceDiagnosticsSDP.attributePrefix + "1:" + nonce.uuidString.lowercased()
        let invalid = [line + "\r\n" + answer, answer + line + "\r\n",
            answer.replacingOccurrences(of: line, with: line + ":extra"),
            answer.replacingOccurrences(of: line, with: RemoteMediaSurfaceDiagnosticsSDP.attributePrefix + "2:" + nonce.uuidString.lowercased()),
            answer.replacingOccurrences(of: line, with: RemoteMediaSurfaceDiagnosticsSDP.attributePrefix + "1:invalid"),
            answer.replacingOccurrences(of: line, with: RemoteMediaSurfaceDiagnosticsSDP.attributePrefix + "1:" + UUID().uuidString.lowercased()),
            answer.replacingOccurrences(of: line + "\r\n", with: "") + line + "\r\n",
            stripped(answer, prefix: RemoteMediaPipelineDiagnosticsSDP.attributePrefix),
            stripped(answer, prefix: AudioClientDiagnosticsSDP.prefix)]
        for candidate in invalid {
            XCTAssertFalse(RemoteMediaSurfaceDiagnosticsSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: candidate))
        }
        let noPipeline = stripped(offer, prefix: RemoteMediaPipelineDiagnosticsSDP.attributePrefix)
        XCTAssertEqual(RemoteMediaSurfaceDiagnosticsSDP.advertisingViewerSupport(in: answer, hostOfferSDP: noPipeline), answer)
        let markerOnly = "v=0\r\n" + line + "\r\n"
        XCTAssertFalse(RemoteMediaSurfaceDiagnosticsSDP.negotiated(hostOfferSDP: markerOnly, viewerAnswerSDP: markerOnly))
    }

    func testBoundedReadbackAndEntrypointRoundTripWithoutContentIdentifiers() throws {
        let value = sample()
        XCTAssertTrue(value.isValid)
        let bytes = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(WebRTCRemoteMediaSurfaceDiagnostics.self, from: bytes), value)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(root.keys), Set(["n", "c"]))
        XCTAssertEqual(Set(try XCTUnwrap(root["n"] as? [String: Any]).keys), Set(["r", "s", "p", "m", "v", "c"]))
        XCTAssertEqual(Set(try XCTUnwrap(root["c"] as? [String: Any]).keys), Set(["q", "o", "r", "a", "t"]))
        let json = String(decoding: bytes, as: UTF8.self)
        for forbidden in ["contextID", "title", "URL", "device", "https", "timestamp", "elapsedTime"] {
            XCTAssertFalse(json.contains(forbidden))
        }
    }

    func testInvalidLocalRangesCannotBecomeWireEvidence() throws {
        typealias Metadata = WebRTCRemoteMediaSurfaceDiagnostics.NativeMetadata
        typealias Control = WebRTCRemoteMediaSurfaceDiagnostics.ControlObservation
        let invalid = [WebRTCRemoteMediaSurfaceDiagnostics(nativeMetadata: Metadata(expectedRevision: 0)),
            .init(nativeMetadata: Metadata(expectedState: .paused)),
            .init(nativeMetadata: Metadata(currentItemMatches: false)),
            .init(nativeMetadata: Metadata(expectedRevision: 1, expectedState: .paused, currentItemMatches: true)),
            .init(nativeMetadata: Metadata(playbackRate: .positive)),
            .init(nativeMetadata: Metadata(enabledCommandMask: 64)),
            .init(lastControl: Control(sequence: 0, origin: .nativeCommandCenter, admitted: false)),
            .init(lastControl: Control(sequence: 1, origin: .customNotification, revision: 0, admitted: false)),
            .init(lastControl: Control(sequence: 1, origin: .customNotification, admitted: true)),
            .init(lastControl: Control(sequence: 1, origin: .customNotification, admitted: false, ageMilliseconds: 86_400_001))]
        for value in invalid {
            XCTAssertFalse(value.isValid)
            XCTAssertThrowsError(try JSONDecoder().decode(WebRTCRemoteMediaSurfaceDiagnostics.self, from: JSONEncoder().encode(value)))
            var heartbeat = heartbeat()
            heartbeat.mediaSurface = value
            XCTAssertThrowsError(try AudioClientDiagnosticsEnvelope(version: 1, negotiationID: UUID(), heartbeat: heartbeat).encoded())
        }
    }

    func testMalformedOptionalSurfaceDoesNotErasePipelineAudioOrAuthority() throws {
        var baseline = heartbeat()
        baseline.mediaPipeline = .init(received: .init(revision: 7, itemCount: 1, playingMask: 0))
        let nonce = UUID()
        let bytes = try AudioClientDiagnosticsEnvelope(version: 1, negotiationID: nonce, heartbeat: baseline).encoded()
        let malformed: [Any] = [["privateTitle": "never transmit"],
            ["n": ["r": 0, "p": true, "v": "zero", "c": 0]],
            ["n": ["r": 7, "s": "future", "p": true, "v": "zero", "c": 0]],
            ["n": ["p": true, "v": "zero", "c": 64]],
            ["c": ["q": 1, "o": "unknown", "a": false]],
            ["c": ["q": 0, "o": "nativeCommandCenter", "a": false]],
            ["c": ["q": 1, "o": "nativeCommandCenter", "a": true]],
            ["c": ["q": 1, "o": "nativeCommandCenter", "a": false, "t": 86_400_001]],
            ["n": ["p": false, "v": "positive", "c": 0]], "not-an-object"]
        for mutation in malformed {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            var beat = try XCTUnwrap(root["h"] as? [String: Any])
            beat["u"] = mutation
            root["h"] = beat
            let mutated = try JSONSerialization.data(withJSONObject: root)
            XCTAssertEqual(try AudioClientDiagnosticsEnvelope.decode(mutated).heartbeat, baseline)
            let proxy = WebRTCDelegateProxy()
            proxy.markNativeTransportHealthyForTesting()
            let gate = WebRTCInputAuthorization()
            XCTAssertTrue(proxy.installInputAuthorization(gate))
            proxy.audioDiagnosticsLane.configure(negotiationID: nonce, acceptsIncoming: true)
            proxy.audioDiagnosticsLane.receive(mutated)
            XCTAssertEqual(proxy.audioDiagnosticsLane.highestReceivedSequenceForTesting, 1)
            XCTAssertTrue(proxy.hasHealthyInstalledInputAuthorization(gate))
            XCTAssertFalse(proxy.didFailEventDelivery())
            proxy.close()
        }
    }

    private func hostOffer(nonce: UUID) -> String {
        RemoteMediaSurfaceDiagnosticsSDP.advertisingHostSupport(in:
            RemoteMediaPipelineDiagnosticsSDP.advertisingHostSupport(in:
                AudioClientDiagnosticsSDP.advertisingHostSupport(in: base, authorization: nonce)))
    }

    private func viewerAnswer(offer: String) -> String {
        RemoteMediaSurfaceDiagnosticsSDP.advertisingViewerSupport(in:
            RemoteMediaPipelineDiagnosticsSDP.advertisingViewerSupport(in:
                AudioClientDiagnosticsSDP.advertisingViewerSupport(in: base, remoteOfferSDP: offer), hostOfferSDP: offer), hostOfferSDP: offer)
    }

    private func stripped(_ sdp: String, prefix: String) -> String {
        sdp.components(separatedBy: "\r\n").filter { !$0.hasPrefix(prefix) }.joined(separator: "\r\n")
    }

    private func sample() -> WebRTCRemoteMediaSurfaceDiagnostics {
        .init(nativeMetadata: .init(expectedRevision: 7, expectedState: .paused, metadataPresent: true,
                                   currentItemMatches: true, playbackRate: .zero, enabledCommandMask: 5),
              lastControl: .init(sequence: 1, origin: .customNotification, revision: 7, admitted: true, ageMilliseconds: 123))
    }

    private func heartbeat() -> WebRTCAudioClientDiagnosticsHeartbeat {
        .init(sequence: 1, sessionID: UUID(), build: .init(buildNumber: 92), snapshot: .init())
    }
}
