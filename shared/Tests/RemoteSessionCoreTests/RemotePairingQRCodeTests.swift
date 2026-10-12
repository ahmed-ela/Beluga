import XCTest
@testable import RemoteSessionCore

final class RemotePairingQRCodeTests: XCTestCase {
    func testQRCodeRoundTripsExistingInvitationWithoutURLOrSecretDescription() throws {
        let invitation = try RemoteInvitationCode.generate()
        let qr = RemotePairingQRCode(invitation: invitation)
        let decoded = try RemotePairingQRCode(scannedPayload: qr.exportedPayload)
        XCTAssertEqual(decoded.invitation.exportedCode, invitation.exportedCode)
        XCTAssertLessThanOrEqual(qr.exportedPayload.utf8.count, RemotePairingQRCode.maximumPayloadBytes)
        XCTAssertFalse(qr.exportedPayload.contains("://"))
        XCTAssertFalse(String(describing: qr).contains(invitation.exportedCode))
        XCTAssertEqual(String(reflecting: qr), qr.description)
    }

    func testQRCodeRejectsURLUnknownVersionExtraFieldsAndNoncanonicalOrOversizedCode() throws {
        let invitation = try RemoteInvitationCode.generate()
        let payload = RemotePairingQRCode(invitation: invitation).exportedPayload
        for bad in ["https://example.invalid/" + invitation.exportedCode,
                    invitation.exportedCode, payload + "\n", payload + "\nhost=Mac",
                    payload.replacingOccurrences(of: "V1", with: "V2"),
                    "BELUGA-PAIRING-V1\n" + invitation.exportedCode.lowercased(),
                    String(repeating: "A", count: 129)] {
            XCTAssertThrowsError(try RemotePairingQRCode(scannedPayload: bad))
        }
    }
}
