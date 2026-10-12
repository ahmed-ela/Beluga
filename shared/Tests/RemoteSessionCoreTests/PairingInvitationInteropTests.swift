import Foundation
import XCTest
@testable import RemoteSessionCore

final class PairingInvitationInteropTests: XCTestCase {
    func testFixedInvitationVectorsForAndroidInteroperability() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ProtocolFixtures/pairing-invitations-v1.tsv")
        let contents = try String(contentsOf: fixtureURL, encoding: .utf8)
        let rows = contents.split(separator: "\n").filter { !$0.hasPrefix("#") }
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 else { return XCTFail("Invalid fixture row") }
            let hex = Array(fields[1].utf8)
            guard hex.count == 40 else { return XCTFail("Invalid fixture secret length") }
            var bytes = Data()
            for index in stride(from: 0, to: hex.count, by: 2) {
                bytes.append(try XCTUnwrap(UInt8(String(decoding: hex[index...index + 1], as: UTF8.self), radix: 16)))
            }
            let invitation = try RemoteInvitationCode(secret: bytes)
            XCTAssertEqual(invitation.exportedCode, String(fields[2]), String(fields[0]))
            let qr = RemotePairingQRCode(invitation: invitation)
            XCTAssertEqual(try RemotePairingQRCode(scannedPayload: qr.exportedPayload).invitation.exportedCode,
                           String(fields[2]))
        }
    }
}
