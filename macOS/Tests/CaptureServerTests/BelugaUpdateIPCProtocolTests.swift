import Foundation
import XCTest
@testable import BelugaUpdateCore

final class BelugaUpdateIPCProtocolTests: XCTestCase {
    private typealias Wire = BelugaUpdateIPCProtocol

    private func binding() throws -> Wire.Binding {
        try .init(operationID: UUID(), target: .init(canonicalPath: "/Applications/Beluga.app", effectiveUID: 501),
                  channelNonce: UUID())
    }

    private func candidate() throws -> BelugaUpdateOperation.ArtifactIdentity {
        try .init(version: "0.2.1", build: 101, executableSHA256: String(repeating: "a", count: 64),
                  dependencyClosureSHA256: String(repeating: "b", count: 64))
    }

    private func mutate(_ bytes: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    func testCheckAndReadinessMessagesRoundTripWithIndependentDirections() throws {
        let binding = try binding(), menuID = UUID(), nonce = UUID(), candidate = try candidate()
        var menu = Wire.Transcript(binding: binding, localRole: .menu)
        var broker = Wire.Transcript(binding: binding, localRole: .broker)
        let begin = Wire.Message.beginCheck(menuInstanceID: menuID)
        XCTAssertEqual(try broker.decode(menu.encode(begin)), begin)
        XCTAssertEqual(try menu.decode(broker.encode(.checkAccepted)), .checkAccepted)
        let request = Wire.Message.requestReadiness(menuInstanceID: menuID)
        XCTAssertEqual(try broker.decode(menu.encode(request)), request)
        let challenge = Wire.Message.readinessChallenge(menuInstanceID: menuID, candidate: candidate, nonce: nonce)
        XCTAssertEqual(try menu.decode(broker.encode(challenge)), challenge)
        let ready = Wire.Message.menuReady(.init(operationID: binding.operationID, target: binding.target,
            candidate: candidate, menuInstanceID: menuID, challengeNonce: nonce, isReady: true))
        XCTAssertEqual(try broker.decode(menu.encode(ready)), ready)
        XCTAssertEqual(try menu.decode(broker.encode(.released)), .released)
    }

    func testReplayRetiresTranscriptPermanently() throws {
        let binding = try binding()
        var menu = Wire.Transcript(binding: binding, localRole: .menu)
        var broker = Wire.Transcript(binding: binding, localRole: .broker)
        let bytes = try menu.encode(.beginCheck(menuInstanceID: UUID()))
        _ = try broker.decode(bytes)
        XCTAssertThrowsError(try broker.decode(bytes)) { XCTAssertEqual($0 as? Wire.Failure, .wrongSequence) }
        XCTAssertThrowsError(try broker.decode(menu.encode(.requestReadiness(menuInstanceID: UUID())))) {
            XCTAssertEqual($0 as? Wire.Failure, .retiredTranscript)
        }
    }

    func testAuthenticatedBootstrapOnlyAdoptsNonceForExactLocalTargetAndOperation() throws {
        let b = try binding()
        for message in [Wire.Message.beginCheck(menuInstanceID: UUID()),
                        .requestReadiness(menuInstanceID: UUID())] {
            var sender = Wire.Transcript(binding: b, localRole: .menu)
            let bytes = try sender.encode(message)
            XCTAssertEqual(try Wire.initialBinding(bytes, operationID: b.operationID, target: b.target), b)
            XCTAssertThrowsError(try Wire.initialBinding(bytes, operationID: UUID(), target: b.target))
            XCTAssertThrowsError(try Wire.initialBinding(bytes, operationID: b.operationID,
                target: .init(canonicalPath: "/Applications/Other.app", effectiveUID: 501)))
            XCTAssertThrowsError(try Wire.initialBinding(bytes + Data("\n".utf8),
                operationID: b.operationID, target: b.target))
            XCTAssertThrowsError(try Wire.initialBinding(sender.encode(message),
                operationID: b.operationID, target: b.target))
        }
    }

    func testBootstrapRejectsBrokerReplyAndReadinessResponseAsFirstFrame() throws {
        let b = try binding()
        var broker = Wire.Transcript(binding: b, localRole: .broker)
        XCTAssertThrowsError(try Wire.initialBinding(broker.encode(.checkAccepted),
            operationID: b.operationID, target: b.target))
        var menu = Wire.Transcript(binding: b, localRole: .menu)
        let ready = Wire.Message.menuReady(.init(operationID: b.operationID, target: b.target,
            candidate: try candidate(), menuInstanceID: UUID(), challengeNonce: UUID(), isReady: true))
        XCTAssertThrowsError(try Wire.initialBinding(menu.encode(ready), operationID: b.operationID,
                                                   target: b.target))
    }

    func testCrossOperationTargetAndChannelNonceAreRejected() throws {
        let b = try binding()
        var menu = Wire.Transcript(binding: b, localRole: .menu)
        let bytes = try menu.encode(.beginCheck(menuInstanceID: UUID()))
        let others = [try Wire.Binding(operationID: UUID(), target: b.target, channelNonce: b.channelNonce),
                      try Wire.Binding(operationID: b.operationID, target: b.target, channelNonce: UUID()),
                      try Wire.Binding(operationID: b.operationID,
                        target: .init(canonicalPath: "/Applications/Other.app", effectiveUID: 501),
                        channelNonce: b.channelNonce)]
        for other in others {
            var receiver = Wire.Transcript(binding: other, localRole: .broker)
            XCTAssertThrowsError(try receiver.decode(bytes)) { XCTAssertEqual($0 as? Wire.Failure, .unexpectedBinding) }
        }
    }

    func testWrongDirectionCannotEncodeOrDecodeAndRetires() throws {
        let b = try binding()
        var menu = Wire.Transcript(binding: b, localRole: .menu)
        XCTAssertThrowsError(try menu.encode(.released)) { XCTAssertEqual($0 as? Wire.Failure, .wrongDirection) }
        XCTAssertThrowsError(try menu.encode(.beginCheck(menuInstanceID: UUID()))) {
            XCTAssertEqual($0 as? Wire.Failure, .retiredTranscript)
        }
        var otherMenu = Wire.Transcript(binding: b, localRole: .menu)
        var receiver = Wire.Transcript(binding: b, localRole: .menu)
        XCTAssertThrowsError(try receiver.decode(otherMenu.encode(.beginCheck(menuInstanceID: UUID())))) {
            XCTAssertEqual($0 as? Wire.Failure, .wrongDirection)
        }
    }

    func testUnknownKeysDuplicateKeysWhitespaceAndTrailingBytesAreNotCanonical() throws {
        let b = try binding()
        var menu = Wire.Transcript(binding: b, localRole: .menu)
        let bytes = try menu.encode(.beginCheck(menuInstanceID: UUID()))
        let original = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let duplicate = Data(original.replacingOccurrences(of: "\"sequence\":0", with: "\"sequence\":0,\"sequence\":0").utf8)
        for bad in [try mutate(bytes) { $0["authority"] = true }, duplicate,
                    Data(" ".utf8) + bytes, bytes + Data("\n".utf8), bytes + Data("{}".utf8)] {
            var receiver = Wire.Transcript(binding: b, localRole: .broker)
            XCTAssertThrowsError(try receiver.decode(bad))
        }
    }

    func testWrongSchemaSequenceAndSpoofedSenderAreRejected() throws {
        let b = try binding()
        var menu = Wire.Transcript(binding: b, localRole: .menu)
        let bytes = try menu.encode(.beginCheck(menuInstanceID: UUID()))
        for bad in [try mutate(bytes) { $0["schema"] = "future" },
                    try mutate(bytes) { $0["sequence"] = 1 },
                    try mutate(bytes) { $0["sender"] = "broker" }] {
            var receiver = Wire.Transcript(binding: b, localRole: .broker)
            XCTAssertThrowsError(try receiver.decode(bad))
        }
    }

    func testFrameLimitAndExplicitRetirement() throws {
        for bytes in [Data(), Data(repeating: 0, count: Wire.maximumFrameBytes + 1)] {
            var receiver = Wire.Transcript(binding: try binding(), localRole: .broker)
            XCTAssertThrowsError(try receiver.decode(bytes)) { XCTAssertEqual($0 as? Wire.Failure, .oversizedFrame) }
        }
        var menu = Wire.Transcript(binding: try binding(), localRole: .menu)
        menu.retire()
        XCTAssertThrowsError(try menu.encode(.beginCheck(menuInstanceID: UUID()))) {
            XCTAssertEqual($0 as? Wire.Failure, .retiredTranscript)
        }
    }

    func testReadinessPayloadCannotChangeBindingOrSupplyFalseProof() throws {
        let b = try binding(), candidate = try candidate()
        for payload in [BelugaUpdateOperation.MenuReadiness(operationID: UUID(), target: b.target,
                            candidate: candidate, menuInstanceID: UUID(), challengeNonce: UUID(), isReady: true),
                        .init(operationID: b.operationID, target: b.target, candidate: candidate,
                              menuInstanceID: UUID(), challengeNonce: UUID(), isReady: false)] {
            var menu = Wire.Transcript(binding: b, localRole: .menu)
            XCTAssertThrowsError(try menu.encode(.menuReady(payload))) {
                XCTAssertEqual($0 as? Wire.Failure, .invalidFrame)
            }
        }
    }

    func testZeroAndReusedBindingNoncesAreRejected() throws {
        let b = try binding(), zero = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        XCTAssertThrowsError(try Wire.Binding(operationID: zero, target: b.target, channelNonce: UUID()))
        XCTAssertThrowsError(try Wire.Binding(operationID: b.operationID, target: b.target, channelNonce: b.operationID))
        var menu = Wire.Transcript(binding: b, localRole: .menu)
        XCTAssertThrowsError(try menu.encode(.beginCheck(menuInstanceID: zero)))
    }
}
