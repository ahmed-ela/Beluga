import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

final class BelugaMenuBarTests: XCTestCase {
    func testFinderBundleLaunchUsesInteractiveMenuButBareCLIStaysLegacy() {
        let endpoint = "wss://audiostreamer-rendezvous.elaminahmed03.workers.dev"
        XCTAssertEqual(BelugaHostLaunchMode.resolve(
            arguments: ["/Applications/Beluga Host.app/Contents/MacOS/CaptureServer"],
            bundleIdentifier: "com.elamin.AudioStreamer.CaptureServer",
            bundlePath: "/Applications/Beluga Host.app", configuredEndpoint: endpoint
        ), .menuBar(arguments: nil, endpoint: URL(string: endpoint)))
        XCTAssertEqual(BelugaHostLaunchMode.resolve(
            arguments: ["CaptureServer"], bundleIdentifier: nil,
            bundlePath: "/private/tmp", configuredEndpoint: endpoint
        ), .commandLine(["CaptureServer"]))
    }

    func testExplicitServiceAndDiagnosticArgumentsDoNotStartAShell() {
        for arguments in [["CaptureServer", "--worldwide", "--virtual-phone-display"],
                          ["CaptureServer", "--help"],
                          ["CaptureServer", "--probe-secondary-test-viewer-status", "/tmp/status"]] {
            XCTAssertEqual(BelugaHostLaunchMode.resolve(
                arguments: arguments, bundleIdentifier: "com.elamin.AudioStreamer.CaptureServer",
                bundlePath: "/Applications/opensteamer Host.app", configuredEndpoint: nil
            ), .commandLine(arguments))
        }
    }

    func testNativeDefaultUsesNormalDisplayAndNoLANOrTestSidecar() throws {
        let endpoint = try XCTUnwrap(URL(string: "wss://host.test"))
        let arguments = BelugaHostLaunchMode.normalDisplayArguments(
            executable: "CaptureServer", endpoint: endpoint, allowRemoteControl: false
        )
        let options = try CaptureServerOptions.parse(arguments, environment: [:])
        XCTAssertTrue(options.worldwideEnabled)
        XCTAssertFalse(options.lanEnabled)
        XCTAssertFalse(options.virtualPhoneDisplayEnabled)
        XCTAssertFalse(options.secondaryTestViewerEnabled)
        XCTAssertFalse(options.allowRemoteControl)
        XCTAssertNil(options.duration)
        XCTAssertEqual(options.rendezvousURL, endpoint)
        XCTAssertFalse(arguments.contains("--reset-worldwide-pairing"))
    }

    func testMenuStartupRejectsInsecureOrCapabilityBearingEndpoint() {
        for endpoint in ["http://host.test", "ws://host.test", "wss://user:password@host.test",
                         "wss://host.test/?token=secret", "wss://host.test/#secret"] {
            XCTAssertEqual(BelugaHostLaunchMode.resolve(
                arguments: ["CaptureServer", "--menu-bar"], bundleIdentifier: nil,
                bundlePath: "/private/tmp", configuredEndpoint: endpoint
            ), .menuBar(arguments: nil, endpoint: nil))
        }
    }

    @MainActor
    func testMenuStartsRuntimeAtMostOnce() {
        let model = BelugaMenuBarModel()
        var starts = 0
        model.start = { starts += 1; return true }
        model.begin()
        model.begin()
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(model.hasStarted)
    }

    @MainActor
    func testConsumedOrSupersededInvitationCannotReturnFromOlderCallback() throws {
        let model = BelugaMenuBarModel()
        let now = Date()
        let code = try RemoteInvitationCode.generate()
        let invitation = BelugaPairingInvitation(code: code, expiresAt: now.addingTimeInterval(60))
        model.apply(.init(revision: 1, phase: .inviting, pairedPhoneName: nil,
                          invitation: invitation), now: now)
        XCTAssertNotNil(model.presentation.invitation)
        model.apply(.init(revision: 2, phase: .pairedWaiting, pairedPhoneName: "iPhone",
                          invitation: nil), now: now)
        model.apply(.init(revision: 1, phase: .inviting, pairedPhoneName: nil,
                          invitation: invitation), now: now)
        XCTAssertNil(model.presentation.invitation)
        XCTAssertEqual(model.presentation.phase, .pairedWaiting)
        XCTAssertEqual(model.presentation.pairedPhoneName, "iPhone")
        model.apply(.init(revision: 2, phase: .inviting, pairedPhoneName: nil,
                          invitation: invitation), now: now)
        XCTAssertNil(model.presentation.invitation)
    }

    @MainActor
    func testExpiredInvitationAndShutdownClearSecretPresentation() throws {
        let model = BelugaMenuBarModel()
        let now = Date()
        let code = try RemoteInvitationCode.generate()
        let expired = BelugaPairingInvitation(code: code, expiresAt: now)
        model.apply(.init(revision: 1, phase: .inviting, pairedPhoneName: nil,
                          invitation: expired), now: now)
        XCTAssertNil(model.presentation.invitation)
        XCTAssertEqual(model.presentation.phase, .invitationExpired)
        model.apply(.init(revision: 2, phase: .inviting, pairedPhoneName: nil,
                          invitation: .init(code: code, expiresAt: now.addingTimeInterval(60))), now: now)
        model.finished()
        XCTAssertNil(model.presentation.invitation)
        XCTAssertEqual(model.presentation.phase, .stopped)
        model.apply(.init(revision: 3, phase: .inviting, pairedPhoneName: nil,
                          invitation: .init(code: code, expiresAt: now.addingTimeInterval(60))), now: now)
        XCTAssertNil(model.presentation.invitation)
        XCTAssertEqual(model.presentation.phase, .stopped)
        XCTAssertFalse(String(describing: expired).contains(code.exportedCode))
        XCTAssertFalse(String(reflecting: expired).contains(code.exportedCode))
    }
}
