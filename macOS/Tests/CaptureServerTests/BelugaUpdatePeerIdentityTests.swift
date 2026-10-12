import Darwin
import Foundation
import Security
import XCTest
@testable import BelugaUpdateCore

final class BelugaUpdatePeerIdentityTests: XCTestCase {
    private typealias Identity = BelugaUpdatePeerIdentity

    private struct Fixture {
        let root: URL
        let expectation: Identity.Expectation
        let observation: Identity.Observation

        func inputs() -> Identity.Inputs {
            .init(readKernelPeer: { _ in observation },
                  executablePath: { _ in expectation.canonicalExecutablePath },
                  validateDynamicCode: { _, supplied in
                      XCTAssertEqual(supplied, expectation)
                  })
        }
    }

    private func fixture(role: Identity.Role = .main,
                         prefix: String = "beluga-peer-identity-fixture-") throws -> Fixture {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            let app = root.appendingPathComponent(role == .main ? "Beluga.app" : "BelugaUpdater.app")
            let name = role == .main ? "CaptureServer" : "BelugaUpdater"
            let executable = app.appendingPathComponent("Contents/MacOS/" + name)
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            try Data("owned-unsigned-fixture".utf8).write(to: executable)
            let expectation = try Identity.Expectation(role: role, canonicalExecutablePath: executable.path,
                effectiveUID: Darwin.geteuid(), nativeCDHash: Data(repeating: 7, count: 20))
            // These synthetic observations never enter native Security or BSM.
            let token = Identity.Token(bytes: Data(repeating: 3, count: MemoryLayout<audit_token_t>.size),
                                       effectiveUID: Darwin.geteuid(), processIdentifier: 123,
                                       processVersion: 456)
            return Fixture(root: root, expectation: expectation,
                observation: .init(socket: .init(device: 1, inode: 2), token: token))
        } catch { try? FileManager.default.removeItem(at: root); throw error }
    }

    private func authenticate(_ fixture: Fixture, inputs: Identity.Inputs? = nil) throws -> Identity.Peer {
        try Identity.authenticateFixture(connectedSocket: 42, expectation: fixture.expectation,
                                         inputs: inputs ?? fixture.inputs())
    }

    func testExactSyntheticPeerKeepsOpaqueProcessIncarnationAndRevalidates() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let peer = try authenticate(f)
        XCTAssertEqual(peer.processIdentifier, 123)
        XCTAssertEqual(peer.processVersion, 456)
        try peer.revalidateFixture(connectedSocket: 42, inputs: f.inputs())
        XCTAssertEqual(peer, try authenticate(f))
    }

    func testFixedRoleRequirementIncludesDeveloperIDTeamIdentifierAndExactCDHash() throws {
        for role in [Identity.Role.main, .broker] {
            let f = try fixture(role: role); defer { try? FileManager.default.removeItem(at: f.root) }
            let source = f.expectation.requirementSource
            XCTAssertTrue(source.contains("anchor apple generic"))
            XCTAssertTrue(source.contains("identifier \"\(role == .main ? "com.elamin.AudioStreamer.CaptureServer" : "com.elamin.beluga.Updater")\""))
            XCTAssertTrue(source.contains("certificate leaf[subject.OU] = \"MSMG8CJLB3\""))
            XCTAssertTrue(source.contains("certificate leaf[field.1.2.840.113635.100.6.1.13] exists"))
            XCTAssertTrue(source.hasSuffix("cdhash H\"\(String(repeating: "07", count: 20))\""))
            XCTAssertEqual(try authenticate(f).processIdentifier, 123)
            var requirement: SecRequirement?
            XCTAssertEqual(SecRequirementCreateWithString(source as CFString, [], &requirement), errSecSuccess)
            XCTAssertNotNil(requirement)
        }
    }

    func testActualKernelSocketPairCannotAuthenticateAnotherExecutablePath() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var descriptors: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
        guard descriptors.allSatisfy({ $0 >= 0 }) else { return }
        defer { for descriptor in descriptors { Darwin.close(descriptor) } }
        // The actual kernel token names this test runner, not the unsigned fixture
        // executable. No synthetic observation or dynamic-verifier override is used.
        XCTAssertThrowsError(try Identity.authenticate(connectedSocket: descriptors[0],
                                                       expectation: f.expectation)) {
            XCTAssertEqual($0 as? Identity.Failure, .unexpectedExecutable)
        }
    }

    func testExpectationRejectsNoncanonicalPathsWrongRoleSuffixAndUnsetHash() throws {
        let valid = "/Applications/Beluga.app/Contents/MacOS/CaptureServer"
        let paths = ["relative.app/Contents/MacOS/CaptureServer",
                     "/Applications//Beluga.app/Contents/MacOS/CaptureServer",
                     "/Applications/../Beluga.app/Contents/MacOS/CaptureServer",
                     "/Applications/Beluga.app/Contents/MacOS/BelugaUpdater",
                     "/Applications/Beluga.app/Contents/MacOS/CaptureServer\n",
                     "/Applications/Beluga/Contents/MacOS/CaptureServer"]
        for path in paths {
            XCTAssertThrowsError(try Identity.Expectation(role: .main, canonicalExecutablePath: path,
                effectiveUID: Darwin.geteuid(), nativeCDHash: Data(repeating: 7, count: 20)))
        }
        for hash in [Data(), Data(repeating: 7, count: 19), Data(repeating: 7, count: 21),
                     Data(repeating: 0, count: 20)] {
            XCTAssertThrowsError(try Identity.Expectation(role: .main, canonicalExecutablePath: valid,
                                                        effectiveUID: Darwin.geteuid(), nativeCDHash: hash))
        }
    }

    func testKernelFailureCannotFallBackToProcessOrPathClaims() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var downstream = 0
        let inputs = Identity.Inputs(readKernelPeer: { _ in throw Identity.Failure.kernel(ENOTCONN) },
            executablePath: { _ in downstream += 1; return f.expectation.canonicalExecutablePath },
            validateDynamicCode: { _, _ in downstream += 1 })
        XCTAssertThrowsError(try authenticate(f, inputs: inputs)) {
            XCTAssertEqual($0 as? Identity.Failure, .kernel(ENOTCONN))
        }
        XCTAssertEqual(downstream, 0)
    }

    func testTokenLengthAndInvalidPIDAreRejectedBeforeNativeIdentityWork() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let changes: [(inout Identity.Token) -> Void] = [
            { $0.bytes.removeLast() }, { $0.bytes.append(0) },
            { $0.processIdentifier = 0 }, { $0.processIdentifier = -1 }
        ]
        for change in changes {
            var observation = f.observation; change(&observation.token)
            var downstream = 0
            var inputs = f.inputs(); inputs.readKernelPeer = { _ in observation }
            inputs.executablePath = { _ in downstream += 1; return f.expectation.canonicalExecutablePath }
            XCTAssertThrowsError(try authenticate(f, inputs: inputs)) {
                XCTAssertEqual($0 as? Identity.Failure, .invalidToken)
            }
            XCTAssertEqual(downstream, 0)
        }
    }

    func testKernelEUIDMustEqualActualUserAndExpectedUser() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var observation = f.observation; observation.token.effectiveUID ^= 1
        var inputs = f.inputs(); inputs.readKernelPeer = { _ in observation }
        XCTAssertThrowsError(try authenticate(f, inputs: inputs)) {
            XCTAssertEqual($0 as? Identity.Failure, .wrongUser)
        }
        let wrong = try Identity.Expectation(role: .main,
            canonicalExecutablePath: f.expectation.canonicalExecutablePath,
            effectiveUID: Darwin.geteuid() ^ 1, nativeCDHash: f.expectation.nativeCDHash)
        var read = false; inputs.readKernelPeer = { _ in read = true; return f.observation }
        XCTAssertThrowsError(try Identity.authenticateFixture(connectedSocket: 42, expectation: wrong,
                                                              inputs: inputs))
        XCTAssertFalse(read)
    }

    func testPathIsExactNotAnotherInstallationAliasOrRole() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        for path in ["/Applications/Other.app/Contents/MacOS/CaptureServer",
                     f.expectation.canonicalExecutablePath.replacingOccurrences(of: "Beluga.app", with: "Alias.app"),
                     f.expectation.canonicalExecutablePath + "/../CaptureServer"] {
            var dynamic = false
            var inputs = f.inputs(); inputs.executablePath = { _ in path }
            inputs.validateDynamicCode = { _, _ in dynamic = true }
            XCTAssertThrowsError(try authenticate(f, inputs: inputs)) {
                XCTAssertEqual($0 as? Identity.Failure, .unexpectedExecutable)
            }
            XCTAssertFalse(dynamic)
        }
    }

    func testAuditTokenPathFailureAndDynamicSignatureFailurePropagateWithoutFallback() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var pathFailure = f.inputs()
        pathFailure.executablePath = { _ in throw Identity.Failure.kernel(ESRCH) }
        XCTAssertThrowsError(try authenticate(f, inputs: pathFailure)) {
            XCTAssertEqual($0 as? Identity.Failure, .kernel(ESRCH))
        }
        var dynamicFailure = f.inputs()
        dynamicFailure.validateDynamicCode = { _, _ in throw Identity.Failure.signature(errSecCSUnsigned) }
        XCTAssertThrowsError(try authenticate(f, inputs: dynamicFailure)) {
            XCTAssertEqual($0 as? Identity.Failure, .signature(errSecCSUnsigned))
        }
    }

    func testDynamicValidationBoundaryReceivesExactOpaqueTokenAndTrustedExpectedHash() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var inputs = f.inputs(); var checked = 0
        inputs.validateDynamicCode = { token, expected in
            XCTAssertEqual(token, f.observation.token)
            XCTAssertEqual(expected.nativeCDHash, Data(repeating: 7, count: 20))
            checked += 1
        }
        _ = try authenticate(f, inputs: inputs)
        XCTAssertEqual(checked, 1)
    }

    func testTokenGenerationOrSocketReplacementDuringAuthenticationIsRejected() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let changes: [(inout Identity.Observation) -> Void] = [
            { $0.token.bytes[0] ^= 1 }, { $0.token.processVersion += 1 },
            { $0.token.processIdentifier += 1 }, { $0.socket.inode += 1 },
            { $0.socket.device += 1 }
        ]
        for change in changes {
            var after = f.observation; change(&after)
            var reads = 0; var inputs = f.inputs()
            inputs.readKernelPeer = { _ in reads += 1; return reads == 1 ? f.observation : after }
            XCTAssertThrowsError(try authenticate(f, inputs: inputs)) {
                XCTAssertEqual($0 as? Identity.Failure, .changedPeer)
            }
        }
    }

    func testPathChangeAfterCodeValidationIsRejected() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var paths = 0; var inputs = f.inputs()
        inputs.executablePath = { _ in
            paths += 1
            return paths == 1 ? f.expectation.canonicalExecutablePath : "/Applications/Other.app/Contents/MacOS/CaptureServer"
        }
        XCTAssertThrowsError(try authenticate(f, inputs: inputs)) {
            XCTAssertEqual($0 as? Identity.Failure, .unexpectedExecutable)
        }
    }

    func testRevalidationRejectsSamePIDWithChangedGenerationAndDifferentDescriptor() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let peer = try authenticate(f)
        var replacement = f.observation; replacement.token.processVersion += 1
        replacement.token.bytes[0] ^= 1
        var inputs = f.inputs(); inputs.readKernelPeer = { _ in replacement }
        XCTAssertThrowsError(try peer.revalidateFixture(connectedSocket: 42, inputs: inputs)) {
            XCTAssertEqual($0 as? Identity.Failure, .changedPeer)
        }
        XCTAssertThrowsError(try peer.revalidateFixture(connectedSocket: 43, inputs: f.inputs())) {
            XCTAssertEqual($0 as? Identity.Failure, .changedPeer)
        }
    }

    func testInvalidSocketCannotInvokeKernelReader() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var invoked = false; var inputs = f.inputs()
        inputs.readKernelPeer = { _ in invoked = true; return f.observation }
        XCTAssertThrowsError(try Identity.authenticateFixture(connectedSocket: -1,
            expectation: f.expectation, inputs: inputs)) {
            XCTAssertEqual($0 as? Identity.Failure, .invalidSocket)
        }
        XCTAssertFalse(invoked)
    }

    func testFixtureInjectionCannotTargetArbitraryOrNonprivateNamespace() throws {
        let f = try fixture(prefix: "beluga-other-fixture-")
        defer { try? FileManager.default.removeItem(at: f.root) }
        var invoked = false; var inputs = f.inputs()
        inputs.readKernelPeer = { _ in invoked = true; return f.observation }
        XCTAssertThrowsError(try authenticate(f, inputs: inputs)) {
            XCTAssertEqual($0 as? Identity.Failure, .unsafeFixture)
        }
        XCTAssertFalse(invoked)
        let privateFixture = try fixture()
        defer { try? FileManager.default.removeItem(at: privateFixture.root) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                             ofItemAtPath: privateFixture.root.path)
        XCTAssertThrowsError(try authenticate(privateFixture)) {
            XCTAssertEqual($0 as? Identity.Failure, .unsafeFixture)
        }
    }

    func testPrivateFixtureIdentityIsRecheckedAfterInjectedValidation() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var inputs = f.inputs()
        inputs.validateDynamicCode = { _, _ in
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.root.path)
        }
        XCTAssertThrowsError(try authenticate(f, inputs: inputs)) {
            XCTAssertEqual($0 as? Identity.Failure, .unsafeFixture)
        }
    }
}
