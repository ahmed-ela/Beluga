import Foundation

/// Transfers the existing consume-once invitation, never a reusable connection credential.
public struct RemotePairingQRCode: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let maximumPayloadBytes = 128
    private static let prefix = "BELUGA-PAIRING-V1\n"
    public let invitation: RemoteInvitationCode

    public init(invitation: RemoteInvitationCode) {
        self.invitation = invitation
    }

    public init(scannedPayload: String) throws {
        guard scannedPayload.utf8.count <= Self.maximumPayloadBytes,
              scannedPayload.hasPrefix(Self.prefix) else {
            throw RemotePairingQRCodeError.invalidPayload
        }
        let code = String(scannedPayload.dropFirst(Self.prefix.count))
        let invitation = try RemoteInvitationCode(code)
        guard code == invitation.exportedCode else {
            throw RemotePairingQRCodeError.invalidPayload
        }
        self.invitation = invitation
    }

    /// Display only as a QR code. Do not place in URLs, diagnostics, or telemetry.
    public var exportedPayload: String { Self.prefix + invitation.exportedCode }
    public var description: String { "<redacted Beluga pairing QR>" }
    public var debugDescription: String { description }
}

public enum RemotePairingQRCodeError: Error, Equatable {
    case invalidPayload
}
