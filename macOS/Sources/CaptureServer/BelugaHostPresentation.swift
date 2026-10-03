import Foundation
import RemoteSessionCore

enum BelugaHostPresentationPhase: Sendable, Equatable {
    case starting
    case unselected
    case inviting
    case invitationExpired
    case pairedConnecting
    case pairedWaiting
    case preparingSession
    case sessionPrepared
    case unavailable
    case stopped

    var title: String {
        switch self {
        case .starting: "Starting Beluga"
        case .unselected: "Choose or pair a phone"
        case .inviting: "Waiting for secure pairing"
        case .invitationExpired: "Pairing invitation expired"
        case .pairedConnecting: "Connecting to the pairing service"
        case .pairedWaiting: "Ready for your selected phone"
        case .preparingSession: "Preparing an encrypted session"
        case .sessionPrepared: "Encrypted session negotiated"
        case .unavailable: "Connection unavailable — retrying"
        case .stopped: "Beluga stopped"
        }
    }
}

struct BelugaPairingInvitation: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let code: RemoteInvitationCode
    let expiresAt: Date

    func isValid(at date: Date) -> Bool { date < expiresAt }

    var description: String { "<redacted Beluga pairing invitation>" }
    var debugDescription: String { description }
}

enum BelugaPairingInvitationEvent: Sendable {
    case available(BelugaPairingInvitation)
    case hidden
}

/// Presentation is not media-health evidence. Only the coordinator can advance its revision.
struct BelugaHostPresentation: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let revision: UInt64
    let phase: BelugaHostPresentationPhase
    let pairedPhoneName: String?
    let invitation: BelugaPairingInvitation?
    let phones: BelugaPhoneCatalogPresentation
    let connectedMediaTarget: BelugaConnectedPhoneMediaTarget?

    init(revision: UInt64, phase: BelugaHostPresentationPhase, pairedPhoneName: String?,
         invitation: BelugaPairingInvitation?, phones: BelugaPhoneCatalogPresentation = .unavailable,
         connectedMediaTarget: BelugaConnectedPhoneMediaTarget? = nil) {
        self.revision = revision
        self.phase = phase
        self.pairedPhoneName = pairedPhoneName.map(BelugaPairedPhonePresentation.safeName)
        self.invitation = invitation
        self.phones = phones
        self.connectedMediaTarget = connectedMediaTarget
    }

    static let starting = BelugaHostPresentation(
        revision: 0, phase: .starting, pairedPhoneName: nil, invitation: nil
    )

    var description: String { "Beluga host presentation: \(phase.title)" }
    var debugDescription: String { description }
}

enum BelugaHostLaunchMode: Equatable {
    case commandLine([String])
    case menuBar(arguments: [String]?, endpoint: URL?)

    static func resolve(arguments: [String], bundleIdentifier: String?,
                        bundlePath: String, configuredEndpoint: String?) -> Self {
        let explicitMenuBar = arguments.dropFirst().contains("--menu-bar")
        let finderLaunch = arguments.count == 1
            && bundleIdentifier == "com.elamin.AudioStreamer.CaptureServer"
            && bundlePath.hasSuffix(".app")
        guard explicitMenuBar || finderLaunch else { return .commandLine(arguments) }
        let runtimeArguments = arguments.filter { $0 != "--menu-bar" }
        let endpoint = configuredEndpoint.flatMap(URL.init(string:)).flatMap { url in
            url.scheme == "wss" && url.host != nil && url.user == nil && url.password == nil
                && url.query == nil && url.fragment == nil ? url : nil
        }
        return .menuBar(
            arguments: runtimeArguments.count > 1 ? runtimeArguments : nil,
            endpoint: endpoint
        )
    }

    static func normalDisplayArguments(executable: String, endpoint: URL,
                                       allowRemoteControl: Bool) -> [String] {
        var arguments = [executable, "--worldwide", "--duration", "0",
                         "--rendezvous-url", endpoint.absoluteString]
        if allowRemoteControl { arguments.append("--allow-remote-control") }
        return arguments
    }
}
