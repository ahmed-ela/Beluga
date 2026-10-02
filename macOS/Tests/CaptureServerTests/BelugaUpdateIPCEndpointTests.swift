import Darwin
import Foundation
import XCTest
@testable import BelugaUpdateCore

/// Real local socket I/O in exact private fixtures, not native peer authentication.
final class BelugaUpdateIPCEndpointTests: XCTestCase {
    private typealias Endpoint = BelugaUpdateIPCEndpoint

    private enum FixtureFailure: Error { case io(Int32), shortIO }

    private final class AcceptResult: @unchecked Sendable {
        private let lock = NSLock()
        private var failure: Error?
        func record(_ error: Error) { lock.lock(); failure = error; lock.unlock() }
        func snapshot() -> Error? { lock.lock(); defer { lock.unlock() }; return failure }
    }

    private struct Fixture {
        let operationID = UUID()
        let root: URL
        init() throws {
            root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("beluga-update-endpoint-fixture-" + operationID.uuidString,
                                        isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
        var directory: URL { root.appendingPathComponent("e", isDirectory: true) }
    }

    private func listener(_ fixture: Fixture, purpose: Endpoint.Purpose = .control) throws -> Endpoint.Listener {
        try Endpoint.createFixture(root: fixture.root, operationID: fixture.operationID, purpose: purpose)
    }

    private func connect(_ fixture: Fixture, purpose: Endpoint.Purpose = .control,
                         timeout: TimeInterval = 0.5) throws -> Int32 {
        try Endpoint.connectFixture(root: fixture.root, operationID: fixture.operationID,
                                    purpose: purpose, timeout: timeout)
    }

    private func metadata(_ path: URL) throws -> stat {
        var value = stat()
        guard Darwin.lstat(path.path, &value) == 0 else { throw FixtureFailure.io(errno) }
        return value
    }

    private func assertFlags(_ descriptor: Int32, file: StaticString = #filePath, line: UInt = #line) {
        let status = Darwin.fcntl(descriptor, F_GETFL), ownership = Darwin.fcntl(descriptor, F_GETFD)
        XCTAssertGreaterThanOrEqual(status, 0, file: file, line: line)
        XCTAssertNotEqual(status & O_NONBLOCK, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(ownership, 0, file: file, line: line)
        XCTAssertNotEqual(ownership & FD_CLOEXEC, 0, file: file, line: line)
        var enabled: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        XCTAssertEqual(Darwin.getsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, &size), 0,
                       file: file, line: line)
        XCTAssertEqual(enabled, 1, file: file, line: line)
    }

    private func roundTrip(sender: Int32, receiver: Int32, bytes: Data) throws {
        var ready = pollfd(fd: sender, events: Int16(POLLOUT), revents: 0)
        guard Darwin.poll(&ready, 1, 500) == 1 else { throw FixtureFailure.io(errno) }
        let sent = bytes.withUnsafeBytes { Darwin.send(sender, $0.baseAddress, $0.count, 0) }
        guard sent == bytes.count else { throw FixtureFailure.shortIO }
        ready = pollfd(fd: receiver, events: Int16(POLLIN), revents: 0)
        guard Darwin.poll(&ready, 1, 500) == 1 else { throw FixtureFailure.io(errno) }
        var received = Data(count: bytes.count)
        let count = received.withUnsafeMutableBytes { Darwin.recv(receiver, $0.baseAddress, $0.count, 0) }
        guard count == bytes.count else { throw FixtureFailure.shortIO }
        XCTAssertEqual(received, bytes)
    }

    func testRealConnectAndAcceptReturnOwnedNonblockingDescriptorsWithoutClaimingAuthentication() throws {
        let f = try Fixture(); defer { f.remove() }
        let owner = try listener(f); defer { owner.close() }
        let client = try connect(f); defer { Darwin.close(client) }
        let accepted = try owner.accept(timeout: 0.5); defer { Darwin.close(accepted) }
        assertFlags(client); assertFlags(accepted)
        try roundTrip(sender: client, receiver: accepted, bytes: Data("menu to broker".utf8))
        try roundTrip(sender: accepted, receiver: client, bytes: Data("broker to menu".utf8))
        XCTAssertEqual(owner.endpointURL.path, f.directory.path + "/control.sock")
        XCTAssertEqual(owner.directoryURL, f.directory)
        XCTAssertLessThan(owner.endpointURL.path.utf8.count, 104)
        XCTAssertEqual(try metadata(f.directory).st_mode & 0o7777, 0o700)
        XCTAssertEqual(try metadata(owner.endpointURL).st_mode & 0o7777, 0o600)
        XCTAssertEqual(try metadata(owner.endpointURL).st_mode & S_IFMT, S_IFSOCK)
    }

    func testReadinessUsesSameExistingNamespaceButIndependentFreshSocket() throws {
        let f = try Fixture(); defer { f.remove() }
        let control = try listener(f); defer { control.close() }
        let readiness = try listener(f, purpose: .readiness); defer { readiness.close() }
        XCTAssertEqual(control.directoryURL, readiness.directoryURL)
        XCTAssertEqual(readiness.endpointURL.path, f.directory.path + "/readiness.sock")
        XCTAssertLessThan(readiness.endpointURL.path.utf8.count, 104)
        let controlClient = try connect(f); defer { Darwin.close(controlClient) }
        let readyClient = try connect(f, purpose: .readiness); defer { Darwin.close(readyClient) }
        let controlAccepted = try control.accept(timeout: 0.5); defer { Darwin.close(controlAccepted) }
        let readyAccepted = try readiness.accept(timeout: 0.5); defer { Darwin.close(readyAccepted) }
        try roundTrip(sender: controlClient, receiver: controlAccepted, bytes: Data("control".utf8))
        try roundTrip(sender: readyClient, receiver: readyAccepted, bytes: Data("readiness".utf8))
    }

    func testReadinessCannotCreateNamespaceOrProceedWithoutTheControlSocket() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertThrowsError(try listener(f, purpose: .readiness))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
        try FileManager.default.createDirectory(at: f.directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        XCTAssertThrowsError(try listener(f, purpose: .readiness))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).isEmpty)
        XCTAssertThrowsError(try listener(f)) { XCTAssertEqual($0 as? Endpoint.Failure, .collision) }
    }

    func testEachSocketCreationIsExclusiveAndClosingNeverUnlinksOrReusesEvidence() throws {
        let f = try Fixture(); defer { f.remove() }
        let control = try listener(f)
        let readiness = try listener(f, purpose: .readiness)
        let controlBefore = try metadata(control.endpointURL), readinessBefore = try metadata(readiness.endpointURL)
        XCTAssertThrowsError(try listener(f)) { XCTAssertEqual($0 as? Endpoint.Failure, .collision) }
        XCTAssertThrowsError(try listener(f, purpose: .readiness)) { XCTAssertEqual($0 as? Endpoint.Failure, .collision) }
        control.close(); control.close(); readiness.close(); readiness.close()
        XCTAssertEqual(try metadata(control.endpointURL).st_ino, controlBefore.st_ino)
        XCTAssertEqual(try metadata(readiness.endpointURL).st_ino, readinessBefore.st_ino)
        XCTAssertThrowsError(try listener(f)) { XCTAssertEqual($0 as? Endpoint.Failure, .collision) }
        XCTAssertThrowsError(try listener(f, purpose: .readiness)) { XCTAssertEqual($0 as? Endpoint.Failure, .collision) }
        XCTAssertThrowsError(try control.accept(timeout: 0.1)) { XCTAssertEqual($0 as? Endpoint.Failure, .closed) }
    }

    func testConnectIsNoncreatingWhenNamespaceOrPurposeSocketIsMissing() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertThrowsError(try connect(f))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
        let control = try listener(f); defer { control.close() }
        let before = try FileManager.default.contentsOfDirectory(atPath: f.directory.path).sorted()
        XCTAssertThrowsError(try connect(f, purpose: .readiness))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).sorted(), before)
    }

    func testDirectoryReadbackIsNoncreatingAndRequiresTheExactPrivateControlAnchor() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertThrowsError(try Endpoint.directoryFixture(root: f.root, operationID: f.operationID))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
        let control = try listener(f); defer { control.close() }
        let before = try FileManager.default.contentsOfDirectory(atPath: f.directory.path).sorted()
        XCTAssertEqual(try Endpoint.directoryFixture(root: f.root, operationID: f.operationID), f.directory)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).sorted(), before)
        XCTAssertEqual(Darwin.chmod(control.endpointURL.path, 0o644), 0)
        XCTAssertThrowsError(try Endpoint.directoryFixture(root: f.root, operationID: f.operationID)) {
            XCTAssertEqual($0 as? Endpoint.Failure, .unsafeSocket)
        }
        XCTAssertEqual(try metadata(control.endpointURL).st_mode & 0o7777, 0o644)
    }

    func testInvalidUIDZeroOperationAndMalformedFixtureRefuseBeforeFilesystemMutation() throws {
        let f = try Fixture(); defer { f.remove() }
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let wrongUser = Darwin.geteuid() == UInt32.max ? UInt32.max - 1 : Darwin.geteuid() + 1
        XCTAssertThrowsError(try Endpoint.create(operationID: zero, effectiveUID: Darwin.geteuid())) {
            XCTAssertEqual($0 as? Endpoint.Failure, .invalidOperation)
        }
        XCTAssertThrowsError(try Endpoint.connect(operationID: zero, effectiveUID: Darwin.geteuid())) {
            XCTAssertEqual($0 as? Endpoint.Failure, .invalidOperation)
        }
        XCTAssertThrowsError(try Endpoint.create(operationID: f.operationID, effectiveUID: wrongUser)) {
            XCTAssertEqual($0 as? Endpoint.Failure, .wrongUser)
        }
        XCTAssertThrowsError(try Endpoint.connect(operationID: f.operationID, effectiveUID: wrongUser)) {
            XCTAssertEqual($0 as? Endpoint.Failure, .wrongUser)
        }
        XCTAssertThrowsError(try Endpoint.createFixture(root: f.root, operationID: UUID())) {
            XCTAssertEqual($0 as? Endpoint.Failure, .unsafeFixture)
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
    }

    func testInvalidConnectTimeoutsDoNotCreateOrTouchNamespace() throws {
        let f = try Fixture(); defer { f.remove() }
        for timeout in [0.0, -1.0, .nan, .infinity, 30.001] {
            XCTAssertThrowsError(try connect(f, timeout: timeout)) {
                XCTAssertEqual($0 as? Endpoint.Failure, .invalidTimeout)
            }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
    }

    func testFiniteAcceptTimeoutRetiresListenerAndPreservesSocketEvidence() throws {
        let f = try Fixture(); defer { f.remove() }
        let owner = try listener(f); defer { owner.close() }
        let before = try metadata(owner.endpointURL)
        XCTAssertThrowsError(try owner.accept(timeout: 0.025)) {
            XCTAssertEqual($0 as? Endpoint.Failure, .timeout)
        }
        XCTAssertThrowsError(try owner.accept(timeout: 0.1)) {
            XCTAssertEqual($0 as? Endpoint.Failure, .closed)
        }
        XCTAssertEqual(try metadata(owner.endpointURL).st_ino, before.st_ino)
    }

    func testClosedListenerCannotBeConnectedAndEvidenceRemains() throws {
        let f = try Fixture(); defer { f.remove() }
        let owner = try listener(f)
        let path = owner.endpointURL
        owner.close()
        XCTAssertThrowsError(try connect(f)) {
            guard case Endpoint.Failure.io(let code) = $0 else {
                return XCTFail("Closed listener did not refuse the connection: \($0)")
            }
            XCTAssertEqual(code, ECONNREFUSED)
        }
        XCTAssertEqual(try metadata(path).st_mode & S_IFMT, S_IFSOCK)
    }

    func testNonprivateOrSymlinkNamespaceCannotBeConnectedOrReused() throws {
        let f = try Fixture(); defer { f.remove() }
        let owner = try listener(f); defer { owner.close() }
        XCTAssertEqual(Darwin.chmod(f.directory.path, 0o755), 0)
        XCTAssertThrowsError(try connect(f))
        XCTAssertThrowsError(try listener(f, purpose: .readiness))
        XCTAssertEqual(Darwin.chmod(f.directory.path, 0o700), 0)
        let displaced = f.root.appendingPathComponent("retained")
        try FileManager.default.moveItem(at: f.directory, to: displaced)
        try FileManager.default.createSymbolicLink(at: f.directory, withDestinationURL: displaced)
        XCTAssertThrowsError(try connect(f))
        XCTAssertThrowsError(try listener(f, purpose: .readiness))
        XCTAssertThrowsError(try listener(f)) { XCTAssertEqual($0 as? Endpoint.Failure, .collision) }
    }

    func testWrongSocketTypeOrSymlinkIsRejectedBeforeConnecting() throws {
        for symlink in [false, true] {
            let f = try Fixture(); defer { f.remove() }
            let owner = try listener(f); defer { owner.close() }
            let displaced = f.directory.appendingPathComponent("retained.sock")
            try FileManager.default.moveItem(at: owner.endpointURL, to: displaced)
            if symlink {
                try FileManager.default.createSymbolicLink(at: owner.endpointURL, withDestinationURL: displaced)
            } else {
                try Data("not a socket".utf8).write(to: owner.endpointURL)
                XCTAssertEqual(Darwin.chmod(owner.endpointURL.path, 0o600), 0)
            }
            XCTAssertThrowsError(try connect(f)) { XCTAssertEqual($0 as? Endpoint.Failure, .unsafeSocket) }
            XCTAssertThrowsError(try owner.accept(timeout: 0.1)) { XCTAssertEqual($0 as? Endpoint.Failure, .unsafeSocket) }
        }
    }

    func testSocketPermissionsDriftIsRefusedWithoutRepair() throws {
        let f = try Fixture(); defer { f.remove() }
        let owner = try listener(f); defer { owner.close() }
        XCTAssertEqual(Darwin.chmod(owner.endpointURL.path, 0o644), 0)
        XCTAssertThrowsError(try connect(f)) { XCTAssertEqual($0 as? Endpoint.Failure, .unsafeSocket) }
        XCTAssertThrowsError(try listener(f, purpose: .readiness)) { XCTAssertEqual($0 as? Endpoint.Failure, .unsafeSocket) }
        XCTAssertEqual(try metadata(owner.endpointURL).st_mode & 0o7777, 0o644)
    }

    func testHeldNamespaceReplacementCannotRetargetExistingListener() throws {
        let f = try Fixture(); defer { f.remove() }
        let owner = try listener(f); defer { owner.close() }
        let displaced = f.root.appendingPathComponent("retained")
        try FileManager.default.moveItem(at: f.directory, to: displaced)
        try FileManager.default.createDirectory(at: f.directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        XCTAssertThrowsError(try owner.accept(timeout: 0.1)) {
            XCTAssertEqual($0 as? Endpoint.Failure, .directoryChanged)
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).isEmpty)
    }

    func testReadinessListenerRevalidatesItsOriginalControlSocketPin() throws {
        let f = try Fixture(); defer { f.remove() }
        let control = try listener(f); defer { control.close() }
        let readiness = try listener(f, purpose: .readiness); defer { readiness.close() }
        try FileManager.default.moveItem(at: control.endpointURL,
                                        to: f.directory.appendingPathComponent("retained-control.sock"))
        // Leave the exact retained readiness socket unchanged. A missing control
        // anchor still prevents accepting a new-menu connection.
        XCTAssertThrowsError(try readiness.accept(timeout: 0.1))
        XCTAssertThrowsError(try connect(f, purpose: .readiness))
    }

    func testFixtureParentModeAndAliasCannotCrossThePrivateTestBoundary() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertEqual(Darwin.chmod(f.root.path, 0o755), 0)
        XCTAssertThrowsError(try listener(f)) { XCTAssertEqual($0 as? Endpoint.Failure, .unsafeDirectory) }
        XCTAssertEqual(Darwin.chmod(f.root.path, 0o700), 0)
        let aliasOperation = UUID()
        let alias = f.root.deletingLastPathComponent().appendingPathComponent(
            "beluga-update-endpoint-fixture-" + aliasOperation.uuidString, isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.root)
        defer { try? FileManager.default.removeItem(at: alias) }
        XCTAssertThrowsError(try Endpoint.createFixture(root: alias, operationID: aliasOperation))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
    }

    func testClosingListenerDoesNotCloseAlreadyTransferredConnections() throws {
        let f = try Fixture(); defer { f.remove() }
        let owner = try listener(f)
        let client = try connect(f); defer { Darwin.close(client) }
        let accepted = try owner.accept(timeout: 0.5); defer { Darwin.close(accepted) }
        owner.close()
        try roundTrip(sender: client, receiver: accepted, bytes: Data("owned independently".utf8))
        XCTAssertEqual(try metadata(owner.endpointURL).st_mode & S_IFMT, S_IFSOCK)
    }

    func testCloseBeforeOrDuringPendingAcceptIsPromptAndLeavesNoWorkerOrRemovedEvidence() throws {
        let f = try Fixture(); defer { f.remove() }
        let owner = try listener(f)
        let started = DispatchSemaphore(value: 0), finished = DispatchGroup(), result = AcceptResult()
        finished.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { finished.leave() }
            started.signal()
            do {
                let descriptor = try owner.accept(timeout: 2)
                Darwin.close(descriptor)
                result.record(FixtureFailure.shortIO)
            } catch { result.record(error) }
        }
        defer {
            owner.close()
            XCTAssertEqual(finished.wait(timeout: .now() + 3), .success)
        }
        guard started.wait(timeout: .now() + 1) == .success else { throw FixtureFailure.shortIO }
        let before = DispatchTime.now().uptimeNanoseconds
        owner.close()
        XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
        XCTAssertLessThan(DispatchTime.now().uptimeNanoseconds - before, 1_000_000_000)
        XCTAssertEqual(result.snapshot() as? Endpoint.Failure, .closed)
        XCTAssertEqual(try metadata(owner.endpointURL).st_mode & S_IFMT, S_IFSOCK)
    }
}
