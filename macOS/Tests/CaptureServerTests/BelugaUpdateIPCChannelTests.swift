import Darwin
import Foundation
import XCTest
@testable import BelugaUpdateCore

final class BelugaUpdateIPCChannelTests: XCTestCase {
    private typealias Channel = BelugaUpdateIPCChannel
    private typealias Wire = BelugaUpdateIPCProtocol

    private enum FixtureFailure: Error { case syscall(Int32), shortWrite, synchronizationTimeout }
    private enum AuthenticationFailure: Error, Equatable { case refused }

    func testTerminalDrainRequiresEOFAndRetiresTransportWithoutPostExitAuthentication() throws {
        try withFixture { root in
            let sockets = try SocketPair(), probe = AuthenticationProbe(failAt: 2)
            let channel = try channel(sockets.takeFirst(), root: root, binding: binding(), authentication: probe)
            sockets.closeSecond()
            XCTAssertNoThrow(try channel.waitForPeerClosure(timeout: 0.1))
            XCTAssertEqual(probe.calls, 1)
            assertClosed(channel)
        }
    }

    func testTerminalDrainRejectsUnexpectedDataAndIsBounded() throws {
        try withFixture { root in
            for sendsData in [true, false] {
                let sockets = try SocketPair()
                let channel = try channel(sockets.takeFirst(), root: root, binding: binding())
                if sendsData { try write(Data([1]), to: sockets.second) }
                XCTAssertThrowsError(try channel.waitForPeerClosure(timeout: 0.02)) {
                    XCTAssertEqual($0 as? Channel.Failure, sendsData ? .invalidLength : .timeout)
                }
                assertClosed(channel)
            }
        }
    }

    func testBootstrapAuthenticatesBeforeReadingAndDeliversFirstMessageOnce() throws {
        try withFixture { root in
            let sockets = try SocketPair(), b = try binding(), probe = AuthenticationProbe()
            var sender = Wire.Transcript(binding: b, localRole: .menu)
            let first = Wire.Message.requestReadiness(menuInstanceID: UUID())
            let second = Wire.Message.beginCheck(menuInstanceID: UUID())
            try write(frame(sender.encode(first)), to: sockets.second)
            try write(frame(sender.encode(second)), to: sockets.second)
            let broker = try Channel.acceptingFixtureSocket(sockets.takeFirst(), root: root,
                operationID: b.operationID, target: b.target, authenticate: { try probe.check() })
            defer { broker.close() }
            XCTAssertEqual(probe.calls, 2)
            XCTAssertEqual(broker.binding, b)
            XCTAssertEqual(try broker.receive(), first)
            XCTAssertEqual(try broker.receive(), second)
            XCTAssertEqual(probe.calls, 6)
        }
    }

    func testBootstrapAuthenticationFailureAndCrossOperationCloseSocket() throws {
        try withFixture { root in
            let b = try binding()
            for authFailure in [true, false] {
                let sockets = try SocketPair()
                var sender = Wire.Transcript(binding: b, localRole: .menu)
                if !authFailure { try write(frame(sender.encode(.beginCheck(menuInstanceID: UUID()))), to: sockets.second) }
                let probe = AuthenticationProbe(failAt: authFailure ? 1 : nil)
                XCTAssertThrowsError(try Channel.acceptingFixtureSocket(sockets.takeFirst(), root: root,
                    operationID: UUID(), target: b.target, timeout: 0.1, authenticate: { try probe.check() }))
                XCTAssertEqual(probe.calls, 1)
                assertPeerEOF(sockets.second)
            }
        }
    }

    /// Each endpoint has exactly one owner. A taken endpoint belongs to Channel,
    /// including when its initializer throws; this wrapper then never closes it.
    private final class SocketPair {
        private(set) var first: Int32 = -1
        private(set) var second: Int32 = -1

        init(type: Int32 = SOCK_STREAM) throws {
            var descriptors: [Int32] = [-1, -1]
            guard Darwin.socketpair(AF_UNIX, type, 0, &descriptors) == 0 else {
                let failure = errno
                descriptors.filter { $0 >= 0 }.forEach { Darwin.close($0) }
                throw FixtureFailure.syscall(failure)
            }
            first = descriptors[0]; second = descriptors[1]
        }

        func takeFirst() -> Int32 { defer { first = -1 }; return first }
        func takeSecond() -> Int32 { defer { second = -1 }; return second }
        func closeFirst() { if first >= 0 { Darwin.close(first); first = -1 } }
        func closeSecond() { if second >= 0 { Darwin.close(second); second = -1 } }
        deinit { closeFirst(); closeSecond() }
    }

    private final class AuthenticationProbe {
        private(set) var calls = 0
        let failAt: Int?
        init(failAt: Int? = nil) { self.failAt = failAt }
        func check() throws {
            calls += 1
            if calls == failAt { throw AuthenticationFailure.refused }
        }
    }

    private final class ReceiveResult: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<Wire.Message, Error>?

        func record(_ result: Result<Wire.Message, Error>) {
            lock.lock(); defer { lock.unlock() }
            value = result
        }

        func snapshot() -> Result<Wire.Message, Error>? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    private func withFixture(_ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("beluga-ipc-channel-fixture-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func binding() throws -> Wire.Binding {
        try .init(operationID: UUID(),
                  target: .init(canonicalPath: "/Applications/Beluga Host.app", effectiveUID: Darwin.geteuid()),
                  channelNonce: UUID())
    }

    private func channel(_ descriptor: Int32, root: URL, binding: Wire.Binding,
                         role: Wire.Sender = .broker,
                         authentication: AuthenticationProbe = AuthenticationProbe()) throws -> Channel {
        try Channel.fixture(takingOwnedSocket: descriptor, root: root, binding: binding,
                            localRole: role, authenticate: { try authentication.check() })
    }

    private func header(_ count: UInt32) -> Data {
        var value = count.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    private func frame(_ payload: Data) -> Data {
        header(UInt32(payload.count)) + payload
    }

    /// Only short, preloaded private-fixture writes. No peer scheduling or sleeps
    /// are needed: the largest fixture here is well below the socket send buffer.
    private func write(_ bytes: Data, to descriptor: Int32) throws {
        guard !bytes.isEmpty, bytes.count <= 2 * Wire.maximumFrameBytes else {
            throw FixtureFailure.shortWrite
        }
        var ready = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard Darwin.poll(&ready, 1, 500) == 1 else { throw FixtureFailure.syscall(errno) }
        let sent = bytes.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
        guard sent == bytes.count else { throw FixtureFailure.shortWrite }
    }

    private func assertClosed(_ channel: Channel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try channel.receive(timeout: 0.1), file: file, line: line) {
            XCTAssertEqual($0 as? Channel.Failure, .closed, file: file, line: line)
        }
    }

    private func assertPeerEOF(_ descriptor: Int32, file: StaticString = #filePath, line: UInt = #line) {
        var ready = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let polled = Darwin.poll(&ready, 1, 500)
        XCTAssertEqual(polled, 1, file: file, line: line)
        guard polled == 1 else { return }
        var byte: UInt8 = 0
        XCTAssertEqual(Darwin.recv(descriptor, &byte, 1, 0), 0, file: file, line: line)
    }

    func testRealSocketPairRoundTripUsesBothTranscriptDirectionsAndAuthenticationChecks() throws {
        try withFixture { root in
            let sockets = try SocketPair(), binding = try binding()
            let menuProbe = AuthenticationProbe(), brokerProbe = AuthenticationProbe()
            let menu = try channel(sockets.takeFirst(), root: root, binding: binding, role: .menu,
                                   authentication: menuProbe)
            defer { menu.close() }
            let broker = try channel(sockets.takeSecond(), root: root, binding: binding,
                                     authentication: brokerProbe)
            defer { broker.close() }
            let message = Wire.Message.beginCheck(menuInstanceID: UUID())
            try menu.send(message, timeout: 0.5)
            XCTAssertEqual(try broker.receive(timeout: 0.5), message)
            try broker.send(.checkAccepted, timeout: 0.5)
            XCTAssertEqual(try menu.receive(timeout: 0.5), .checkAccepted)
            XCTAssertEqual(menuProbe.calls, 4)
            XCTAssertEqual(brokerProbe.calls, 4)
        }
    }

    func testChunkedHeaderBodyAndAdjacentFramesDoNotLoseFraming() throws {
        try withFixture { root in
            let sockets = try SocketPair(), binding = try binding()
            var sender = Wire.Transcript(binding: binding, localRole: .menu)
            let first = Wire.Message.beginCheck(menuInstanceID: UUID())
            let second = Wire.Message.requestReadiness(menuInstanceID: UUID())
            let firstPayload = try sender.encode(first)
            let firstHeader = header(UInt32(firstPayload.count))
            let receiver = try channel(sockets.takeFirst(), root: root, binding: binding)
            defer { receiver.close() }
            try write(Data(firstHeader.prefix(2)), to: sockets.second)
            try write(Data(firstHeader.suffix(2)), to: sockets.second)
            let midpoint = firstPayload.count / 2
            try write(Data(firstPayload.prefix(midpoint)), to: sockets.second)
            try write(Data(firstPayload.suffix(firstPayload.count - midpoint)), to: sockets.second)
            try write(frame(sender.encode(second)), to: sockets.second)
            XCTAssertEqual(try receiver.receive(timeout: 0.5), first)
            XCTAssertEqual(try receiver.receive(timeout: 0.5), second)
        }
    }

    func testPartialHeaderThenEOFRefusesAndPoisonsChannel() throws {
        try withFixture { root in
            let sockets = try SocketPair()
            let receiver = try channel(sockets.takeFirst(), root: root, binding: binding())
            defer { receiver.close() }
            try write(Data(header(100).prefix(2)), to: sockets.second)
            sockets.closeSecond()
            XCTAssertThrowsError(try receiver.receive(timeout: 0.5)) {
                XCTAssertEqual($0 as? Channel.Failure, .eof)
            }
            assertClosed(receiver)
        }
    }

    func testPartialBodyThenEOFNeverReturnsAPartialMessage() throws {
        try withFixture { root in
            let sockets = try SocketPair(), binding = try binding()
            var sender = Wire.Transcript(binding: binding, localRole: .menu)
            let payload = try sender.encode(.beginCheck(menuInstanceID: UUID()))
            let receiver = try channel(sockets.takeFirst(), root: root, binding: binding)
            defer { receiver.close() }
            try write(header(UInt32(payload.count)) + payload.dropLast(), to: sockets.second)
            sockets.closeSecond()
            XCTAssertThrowsError(try receiver.receive(timeout: 0.5)) {
                XCTAssertEqual($0 as? Channel.Failure, .eof)
            }
            assertClosed(receiver)
        }
    }

    func testCompleteFinalFrameRemainsReadableWhenPeerHasClosed() throws {
        try withFixture { root in
            let sockets = try SocketPair(), binding = try binding()
            var sender = Wire.Transcript(binding: binding, localRole: .menu)
            let message = Wire.Message.beginCheck(menuInstanceID: UUID())
            let receiver = try channel(sockets.takeFirst(), root: root, binding: binding)
            defer { receiver.close() }
            try write(frame(sender.encode(message)), to: sockets.second)
            sockets.closeSecond()
            XCTAssertEqual(try receiver.receive(timeout: 0.5), message)
            XCTAssertThrowsError(try receiver.receive(timeout: 0.5)) {
                XCTAssertEqual($0 as? Channel.Failure, .eof)
            }
            assertClosed(receiver)
        }
    }

    func testZeroOversizedAndMaximumUInt32LengthsRefuseBeforeBodyAllocation() throws {
        for count in [UInt32(0), UInt32(Wire.maximumFrameBytes + 1), UInt32.max] {
            try withFixture { root in
                let sockets = try SocketPair()
                let receiver = try channel(sockets.takeFirst(), root: root, binding: binding())
                defer { receiver.close() }
                try write(header(count), to: sockets.second)
                XCTAssertThrowsError(try receiver.receive(timeout: 0.5)) {
                    XCTAssertEqual($0 as? Channel.Failure, .invalidLength)
                }
                assertClosed(receiver)
            }
        }
    }

    func testEmptySocketReadHasFiniteTimeoutAndCannotBeRetried() throws {
        try withFixture { root in
            let sockets = try SocketPair()
            let receiver = try channel(sockets.takeFirst(), root: root, binding: binding())
            defer { receiver.close() }
            let before = DispatchTime.now().uptimeNanoseconds
            XCTAssertThrowsError(try receiver.receive(timeout: 0.025)) {
                XCTAssertEqual($0 as? Channel.Failure, .timeout)
            }
            let elapsed = DispatchTime.now().uptimeNanoseconds - before
            XCTAssertLessThan(elapsed, 2_000_000_000)
            assertClosed(receiver)
        }
    }

    func testInvalidTimeoutValuesCloseWithoutEnteringIOOrAuthentication() throws {
        for timeout in [0.0, -1.0, .infinity, -.infinity, .nan, 30.001] {
            try withFixture { root in
                let sockets = try SocketPair(), authentication = AuthenticationProbe()
                let receiver = try channel(sockets.takeFirst(), root: root, binding: binding(),
                                           authentication: authentication)
                defer { receiver.close() }
                XCTAssertThrowsError(try receiver.receive(timeout: timeout)) {
                    XCTAssertEqual($0 as? Channel.Failure, .invalidTimeout)
                }
                XCTAssertEqual(authentication.calls, 0)
                assertClosed(receiver)
            }
        }
    }

    func testMalformedWireWrongRoleAndChangedBindingPermanentlyCloseChannel() throws {
        try withFixture { root in
            let binding = try binding()
            var wrongRole = Wire.Transcript(binding: binding, localRole: .broker)
            let otherBinding = try Wire.Binding(operationID: binding.operationID, target: binding.target,
                                               channelNonce: UUID())
            var wrongBinding = Wire.Transcript(binding: otherBinding, localRole: .menu)
            let cases: [(Data, Wire.Failure)] = [
                (Data("{}".utf8), .invalidFrame),
                (try wrongRole.encode(.released), .wrongDirection),
                (try wrongBinding.encode(.beginCheck(menuInstanceID: UUID())), .unexpectedBinding)
            ]
            for (payload, expected) in cases {
                let sockets = try SocketPair()
                let receiver = try channel(sockets.takeFirst(), root: root, binding: binding)
                defer { receiver.close() }
                try write(frame(payload), to: sockets.second)
                XCTAssertThrowsError(try receiver.receive(timeout: 0.5)) {
                    XCTAssertEqual($0 as? Wire.Failure, expected)
                }
                assertClosed(receiver)
            }
        }
    }

    func testReplayedFrameCannotBeRetriedAfterTheValidFirstDelivery() throws {
        try withFixture { root in
            let sockets = try SocketPair(), binding = try binding()
            var sender = Wire.Transcript(binding: binding, localRole: .menu)
            let message = Wire.Message.beginCheck(menuInstanceID: UUID())
            let payload = try sender.encode(message)
            let receiver = try channel(sockets.takeFirst(), root: root, binding: binding)
            defer { receiver.close() }
            try write(frame(payload) + frame(payload), to: sockets.second)
            XCTAssertEqual(try receiver.receive(timeout: 0.5), message)
            XCTAssertThrowsError(try receiver.receive(timeout: 0.5)) {
                XCTAssertEqual($0 as? Wire.Failure, .wrongSequence)
            }
            assertClosed(receiver)
        }
    }

    func testReceiveAuthenticationFailureBeforeOrAfterValidIOClosesAndNeverReturnsMessage() throws {
        for failAt in [1, 2] {
            try withFixture { root in
                let sockets = try SocketPair(), binding = try binding()
                var sender = Wire.Transcript(binding: binding, localRole: .menu)
                let authentication = AuthenticationProbe(failAt: failAt)
                let receiver = try channel(sockets.takeFirst(), root: root, binding: binding,
                                           authentication: authentication)
                defer { receiver.close() }
                try write(frame(sender.encode(.beginCheck(menuInstanceID: UUID()))), to: sockets.second)
                XCTAssertThrowsError(try receiver.receive(timeout: 0.5)) {
                    XCTAssertEqual($0 as? AuthenticationFailure, .refused)
                }
                XCTAssertEqual(authentication.calls, failAt)
                assertClosed(receiver)
                XCTAssertEqual(authentication.calls, failAt)
            }
        }
    }

    func testSendAuthenticationFailureBeforeOrAfterIOClosesAndCannotReportSuccess() throws {
        for failAt in [1, 2] {
            try withFixture { root in
                let sockets = try SocketPair(), authentication = AuthenticationProbe(failAt: failAt)
                let sender = try channel(sockets.takeFirst(), root: root, binding: binding(), role: .menu,
                                         authentication: authentication)
                defer { sender.close() }
                XCTAssertThrowsError(try sender.send(.beginCheck(menuInstanceID: UUID()), timeout: 0.5)) {
                    XCTAssertEqual($0 as? AuthenticationFailure, .refused)
                }
                // Post-I/O authentication cannot retract bytes already written.
                // Receiver authentication and operation policy remain mandatory.
                XCTAssertEqual(authentication.calls, failAt)
                assertClosed(sender)
            }
        }
    }

    func testClosedPeerSendUsesNoSigpipeAndFailsWithoutTerminatingTheTestProcess() throws {
        try withFixture { root in
            let sockets = try SocketPair()
            let sender = try channel(sockets.takeFirst(), root: root, binding: binding(), role: .menu)
            defer { sender.close() }
            sockets.closeSecond()
            XCTAssertThrowsError(try sender.send(.beginCheck(menuInstanceID: UUID()), timeout: 0.5)) {
                guard case Channel.Failure.io(let code) = $0 else {
                    return XCTFail("Closed-peer send did not fail with a socket I/O error: \($0)")
                }
                XCTAssertTrue(code == EPIPE || code == ECONNRESET)
            }
            assertClosed(sender)
        }
    }

    func testExplicitCloseIsIdempotentAndReleasesOwnedEndpoint() throws {
        try withFixture { root in
            let sockets = try SocketPair(), authentication = AuthenticationProbe()
            let channel = try channel(sockets.takeFirst(), root: root, binding: binding(),
                                      authentication: authentication)
            channel.close(); channel.close()
            assertClosed(channel)
            XCTAssertThrowsError(try channel.send(.checkAccepted, timeout: 0.1)) {
                XCTAssertEqual($0 as? Channel.Failure, .closed)
            }
            XCTAssertEqual(authentication.calls, 0)
            assertPeerEOF(sockets.second)
        }
    }

    func testDeinitializationClosesButDoesNotLeaveAnOwnedDescriptor() throws {
        try withFixture { root in
            let sockets = try SocketPair()
            var owned: Channel? = try channel(sockets.takeFirst(), root: root, binding: binding())
            XCTAssertNotNil(owned)
            owned = nil
            assertPeerEOF(sockets.second)
        }
    }

    func testDatagramAndRegularFileDescriptorsAreRefusedAndConsumed() throws {
        try withFixture { root in
            let sockets = try SocketPair(type: SOCK_DGRAM)
            let datagram = sockets.takeFirst()
            XCTAssertThrowsError(try channel(datagram, root: root, binding: binding())) {
                XCTAssertEqual($0 as? Channel.Failure, .invalidSocket)
            }
            XCTAssertEqual(Darwin.fcntl(datagram, F_GETFD), -1)
            XCTAssertEqual(errno, EBADF)
            let file = root.appendingPathComponent("not-a-socket")
            try Data("private fixture".utf8).write(to: file)
            let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            XCTAssertGreaterThanOrEqual(descriptor, 0)
            guard descriptor >= 0 else { return }
            XCTAssertThrowsError(try channel(descriptor, root: root, binding: binding())) {
                XCTAssertEqual($0 as? Channel.Failure, .invalidSocket)
            }
            XCTAssertEqual(Darwin.fcntl(descriptor, F_GETFD), -1)
            XCTAssertEqual(errno, EBADF)
        }
    }

    func testNonprivateWrongNameAndSymlinkFixtureRootsAreRefusedAndConsumeSocket() throws {
        try withFixture { root in
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            do {
                let sockets = try SocketPair(), descriptor = sockets.takeFirst()
                XCTAssertThrowsError(try channel(descriptor, root: root, binding: binding())) {
                    XCTAssertEqual($0 as? Channel.Failure, .unsafeFixture)
                }
                XCTAssertEqual(Darwin.fcntl(descriptor, F_GETFD), -1)
                XCTAssertEqual(errno, EBADF)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            let wrongName = root.appendingPathComponent("wrong-name", isDirectory: true)
            try FileManager.default.createDirectory(at: wrongName, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            let alias = root.deletingLastPathComponent().appendingPathComponent(
                "beluga-ipc-channel-fixture-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
            defer { try? FileManager.default.removeItem(at: alias) }
            for unsafe in [wrongName, alias] {
                let sockets = try SocketPair(), descriptor = sockets.takeFirst()
                XCTAssertThrowsError(try channel(descriptor, root: unsafe, binding: binding())) {
                    XCTAssertEqual($0 as? Channel.Failure, .unsafeFixture)
                }
                XCTAssertEqual(Darwin.fcntl(descriptor, F_GETFD), -1)
                XCTAssertEqual(errno, EBADF)
            }
        }
    }

    func testWrongNativePeerRoleConsumesSocketBeforeNativeAuthentication() throws {
        try withFixture { root in
            let binding = try binding()
            let cases: [(Wire.Sender, BelugaUpdatePeerIdentity.Role, String)] = [
                (.menu, .main, "Beluga Host.app/Contents/MacOS/CaptureServer"),
                (.broker, .broker, "BelugaUpdater.app/Contents/MacOS/BelugaUpdater")
            ]
            for (localRole, expectedRole, relative) in cases {
                let sockets = try SocketPair(), descriptor = sockets.takeFirst()
                // Shape-only metadata deliberately names a nonexistent private
                // fixture app. Any native path/authentication attempt would fail
                // differently; the role guard must run before it.
                let expectation = try BelugaUpdatePeerIdentity.Expectation(
                    role: expectedRole, canonicalExecutablePath: root.appendingPathComponent(relative).path,
                    effectiveUID: Darwin.geteuid(), nativeCDHash: Data(repeating: 0x19, count: 20))
                XCTAssertThrowsError(try Channel(takingOwnedSocket: descriptor, binding: binding,
                    localRole: localRole, expectedPeer: expectation)) {
                    XCTAssertEqual($0 as? Channel.Failure, .unexpectedPeerRole)
                }
                XCTAssertEqual(Darwin.fcntl(descriptor, F_GETFD), -1)
                XCTAssertEqual(errno, EBADF)
                assertPeerEOF(sockets.second)
            }
        }
    }

    func testFixtureAuthenticatedPeerCannotFabricateNativeAuthority() throws {
        try withFixture { root in
            let sockets = try SocketPair()
            let owned = try channel(sockets.takeFirst(), root: root, binding: binding())
            defer { owned.close() }
            XCTAssertThrowsError(try owned.authenticatedPeer()) {
                XCTAssertEqual($0 as? Channel.Failure, .invalidSocket)
            }
            assertClosed(owned)
            assertPeerEOF(sockets.second)
        }
    }

    func testCompetingReceiveSendAndPeerReadFailBusyWithoutPoisoningOwnedReceive() throws {
        try withFixture { root in
            let sockets = try SocketPair(), binding = try binding()
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            let finished = DispatchGroup(), result = ReceiveResult()
            let owned = try Channel.fixture(takingOwnedSocket: sockets.takeFirst(), root: root,
                binding: binding, localRole: .broker, authenticate: {
                    entered.signal()
                    guard release.wait(timeout: .now() + 2) == .success else {
                        throw FixtureFailure.synchronizationTimeout
                    }
                })
            var sender = Wire.Transcript(binding: binding, localRole: .menu)
            let message = Wire.Message.beginCheck(menuInstanceID: UUID())
            try write(frame(sender.encode(message)), to: sockets.second)
            finished.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { finished.leave() }
                do { result.record(.success(try owned.receive(timeout: 2))) }
                catch { result.record(.failure(error)) }
            }
            defer {
                // Both pre/post auth waits and worker I/O are bounded. Always
                // release both callbacks and join the worker before fixture removal.
                release.signal(); release.signal(); owned.close()
                XCTAssertEqual(finished.wait(timeout: .now() + 3), .success)
            }
            guard entered.wait(timeout: .now() + 1) == .success else {
                throw FixtureFailure.synchronizationTimeout
            }
            let start = DispatchTime.now().uptimeNanoseconds
            XCTAssertThrowsError(try owned.receive(timeout: 0.1)) {
                XCTAssertEqual($0 as? Channel.Failure, .busy)
            }
            XCTAssertThrowsError(try owned.send(.checkAccepted, timeout: 0.1)) {
                XCTAssertEqual($0 as? Channel.Failure, .busy)
            }
            XCTAssertThrowsError(try owned.authenticatedPeer()) {
                XCTAssertEqual($0 as? Channel.Failure, .busy)
            }
            XCTAssertLessThan(DispatchTime.now().uptimeNanoseconds - start, 500_000_000)
            release.signal(); release.signal()
            XCTAssertEqual(finished.wait(timeout: .now() + 3), .success)
            guard let outcome = result.snapshot() else { return XCTFail("Owned receive did not finish") }
            switch outcome {
            case .success(let actual): XCTAssertEqual(actual, message)
            case .failure(let error): XCTFail("Busy callers poisoned the owned receive: \(error)")
            }
        }
    }

    func testCloseDuringOwnedReceiveReturnsPromptlyAndOwnerNeverClosesAnotherSocket() throws {
        try withFixture { root in
            let sockets = try SocketPair(), binding = try binding()
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            let finished = DispatchGroup(), result = ReceiveResult()
            let owned = try Channel.fixture(takingOwnedSocket: sockets.takeFirst(), root: root,
                binding: binding, localRole: .broker, authenticate: {
                    entered.signal()
                    guard release.wait(timeout: .now() + 2) == .success else {
                        throw FixtureFailure.synchronizationTimeout
                    }
                })
            finished.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { finished.leave() }
                do { result.record(.success(try owned.receive(timeout: 2))) }
                catch { result.record(.failure(error)) }
            }
            defer {
                release.signal(); owned.close()
                XCTAssertEqual(finished.wait(timeout: .now() + 3), .success)
            }
            guard entered.wait(timeout: .now() + 1) == .success else {
                throw FixtureFailure.synchronizationTimeout
            }
            let start = DispatchTime.now().uptimeNanoseconds
            owned.close()
            XCTAssertLessThan(DispatchTime.now().uptimeNanoseconds - start, 500_000_000)
            // Allocate an unrelated pair while the receive owner remains inside
            // its callback. An erroneous early close may recycle the old FD into
            // this pair; the later owner cleanup must never close that new socket.
            let independent = try SocketPair()
            // A regression must report failure, not kill the process if stale
            // cleanup accidentally closes this unrelated pair's opposite end.
            var noSignal: Int32 = 1
            for descriptor in [independent.first, independent.second] {
                XCTAssertEqual(Darwin.setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal,
                    socklen_t(MemoryLayout<Int32>.size)), 0)
            }
            release.signal()
            XCTAssertEqual(finished.wait(timeout: .now() + 3), .success)
            guard let outcome = result.snapshot() else { return XCTFail("Cancelled receive did not finish") }
            switch outcome {
            case .success: XCTFail("Cancelled receive returned a message")
            case .failure(let error): XCTAssertEqual(error as? Channel.Failure, .closed)
            }
            assertClosed(owned)
            assertPeerEOF(sockets.second)
            let probe = Data("independent socket remains owned".utf8)
            try write(probe, to: independent.first)
            var ready = pollfd(fd: independent.second, events: Int16(POLLIN), revents: 0)
            let available = Darwin.poll(&ready, 1, 500)
            XCTAssertEqual(available, 1)
            guard available == 1 else { return }
            var bytes = Data(count: probe.count)
            let count = bytes.withUnsafeMutableBytes {
                Darwin.recv(independent.second, $0.baseAddress, $0.count, 0)
            }
            XCTAssertEqual(count, probe.count)
            XCTAssertEqual(bytes, probe)
        }
    }

    func testCloseCancelsAnOwnedEmptyReadWithinBoundedPollSlices() throws {
        try withFixture { root in
            let sockets = try SocketPair(), binding = try binding()
            let entered = DispatchSemaphore(value: 0), finished = DispatchGroup(), result = ReceiveResult()
            let owned = try Channel.fixture(takingOwnedSocket: sockets.takeFirst(), root: root,
                binding: binding, localRole: .broker, authenticate: { entered.signal() })
            finished.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { finished.leave() }
                do { result.record(.success(try owned.receive(timeout: 2))) }
                catch { result.record(.failure(error)) }
            }
            defer {
                owned.close()
                XCTAssertEqual(finished.wait(timeout: .now() + 3), .success)
            }
            guard entered.wait(timeout: .now() + 1) == .success else {
                throw FixtureFailure.synchronizationTimeout
            }
            // There is deliberately no scheduler sleep or internal poll hook:
            // cancellation immediately before a poll or inside it must both
            // release the owned empty read well before its two-second deadline.
            let start = DispatchTime.now().uptimeNanoseconds
            owned.close()
            XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
            XCTAssertLessThan(DispatchTime.now().uptimeNanoseconds - start, 1_000_000_000)
            guard let outcome = result.snapshot() else { return XCTFail("Empty read did not cancel") }
            switch outcome {
            case .success: XCTFail("Cancelled empty read returned a message")
            case .failure(let error): XCTAssertEqual(error as? Channel.Failure, .closed)
            }
            assertClosed(owned)
            assertPeerEOF(sockets.second)
        }
    }
}
