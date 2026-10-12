import AudioToolbox
import CaptureCore
import CoreMedia
import Foundation
import RemoteSessionCore
import WebRTCTransport
import XCTest
@testable import CaptureServer

/// No native factory, capture source, socket, route, credentials, or live service is used.
final class BelugaAudioShareCoordinatorTests: XCTestCase {
    func testFragmentOnlyCapabilityAndNoSourceBeforeExactAnswerAndHealth() async throws {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.coordinator()
        let started = try await coordinator.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(fixture.sockets.first)
        let registration = try XCTUnwrap(socket.registration)
        XCTAssertEqual(started.url.path, "/audio-share")
        XCTAssertNil(URLComponents(url: started.url, resolvingAgainstBaseURL: false)?.query)
        XCTAssertNil(socket.url?.fragment)
        XCTAssertNil(socket.url?.query)
        XCTAssertEqual(socket.url?.path, "/v3/audio-share/\(try socket.shareID())")
        XCTAssertEqual(registration["maxListeners"] as? Int, 8)
        XCTAssertNotEqual(registration["ownerProof"] as? String, registration["listenerProof"] as? String)
        XCTAssertFalse(started.url.absoluteString.contains(try XCTUnwrap(registration["ownerProof"] as? String)))
        XCTAssertFalse(String(describing: started).contains(started.url.absoluteString))
        XCTAssertFalse(String(reflecting: started).contains(started.url.absoluteString))
        XCTAssertTrue(fixture.sources.isEmpty)

        let listener = try await fixture.join(started, socket: socket, byte: 2)
        listener.peer.emit(.peerStateChanged(.connected))
        listener.peer.emit(.iceStateChanged(.connected))
        await fixture.settle()
        XCTAssertEqual(listener.peer.admissions, 0)
        XCTAssertTrue(fixture.sources.isEmpty, "Transport health without an exact encrypted answer is insufficient")
        try listener.answer(socket)
        checkTrue(await fixture.eventually { fixture.sources.first?.starts == 1 })
        XCTAssertEqual(listener.peer.admissions, 1)
        checkTrue(await coordinator.stop())
        XCTAssertEqual(fixture.sources.first?.stops, 1)
    }

    func testBoundedFanoutUsesOneSourceAndDuplicateHealthDoesNotReadmit() async throws {
        let fixture = CoordinatorFixture()
        let owned = fixture.coordinator()
        let started = try await owned.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(fixture.sockets.first)
        let first = try await fixture.join(started, socket: socket, byte: 2)
        try first.answer(socket)
        first.peer.emit(.peerStateChanged(.connected)); first.peer.emit(.iceStateChanged(.connected))
        checkTrue(await fixture.eventually { fixture.sources.first?.starts == 1 })
        let second = try await fixture.join(started, socket: socket, byte: 3)
        try second.answer(socket)
        second.peer.emit(.peerStateChanged(.connected)); second.peer.emit(.iceStateChanged(.completed))
        checkTrue(await fixture.eventually { second.peer.admissions == 1 })
        for _ in 0..<8 {
            first.peer.emit(.peerStateChanged(.connected)); first.peer.emit(.iceStateChanged(.completed))
            second.peer.emit(.peerStateChanged(.connected)); second.peer.emit(.iceStateChanged(.connected))
        }
        await fixture.settle()
        XCTAssertEqual(first.peer.admissions, 1)
        XCTAssertEqual(second.peer.admissions, 1)
        XCTAssertEqual(fixture.sources.count, 1)
        let source = try XCTUnwrap(fixture.sources.first)
        source.deliver()
        XCTAssertEqual(first.peer.fakeSink.frames, 1)
        XCTAssertEqual(second.peer.fakeSink.frames, 1)
        checkTrue(await owned.stop())
    }

    func testSocketLossClosesAllCallbackVisibleGatesBeforeActorCleanup() async throws {
        let fixture = CoordinatorFixture(), coordinator = fixture.coordinator()
        let (_, socket, listener, source) = try await fixture.active(coordinator)
        source.deliver()
        XCTAssertEqual(listener.peer.fakeSink.frames, 1)
        socket.cancel()
        XCTAssertGreaterThan(listener.peer.fakeSink.revocations, 0, "Fatal transport hook is synchronous")
        source.deliver()
        XCTAssertEqual(listener.peer.fakeSink.frames, 1)
        checkTrue(await fixture.eventually { fixture.statuses.contains(.failed) })
        checkTrue(await coordinator.stop())
    }

    func testOwnerInvalidationStopsCallbacksAndRejectsFreshStart() async throws {
        let fixture = CoordinatorFixture(), coordinator = fixture.coordinator()
        let (_, _, listener, source) = try await fixture.active(coordinator)
        source.deliver(); fixture.owner.set(false); source.deliver()
        XCTAssertEqual(listener.peer.fakeSink.frames, 1)
        XCTAssertGreaterThan(listener.peer.fakeSink.revocations, 0)
        checkTrue(await coordinator.stop())
        do { _ = try await coordinator.start(ttlSeconds: 30); XCTFail("Terminal host owner may not reopen sharing") }
        catch { XCTAssertEqual(error as? BelugaAudioShareCoordinatorError, .unavailable) }
        XCTAssertEqual(fixture.sockets.count, 1)
    }

    func testFailedNativeStopRetainsExactSourceAndQuarantinesReplacement() async throws {
        let fixture = CoordinatorFixture(), coordinator = fixture.coordinator()
        let (_, _, listener, source) = try await fixture.active(coordinator)
        source.failStop = true
        checkFalse(await coordinator.stop())
        XCTAssertGreaterThan(listener.peer.fakeSink.revocations, 0)
        source.deliver(); XCTAssertEqual(listener.peer.fakeSink.frames, 0)
        do { _ = try await coordinator.start(ttlSeconds: 30); XCTFail("Unconfirmed source must not be replaced") }
        catch { XCTAssertEqual(error as? BelugaAudioShareCoordinatorError, .quarantined) }
        XCTAssertEqual(fixture.sources.count, 1)
        XCTAssertFalse(fixture.statuses.contains(.ended))
    }

    func testNativeStopTimeoutReturnsFalseWithoutLosingOwnership() async throws {
        let fixture = CoordinatorFixture()
        fixture.timeout = 5_000_000
        let coordinator = fixture.coordinator()
        let (_, _, _, source) = try await fixture.active(coordinator)
        source.blockStop = true
        checkFalse(await coordinator.stop())
        XCTAssertEqual(fixture.sources.count, 1)
        do { _ = try await coordinator.start(ttlSeconds: 30); XCTFail("Timed-out source must stay quarantined") }
        catch { XCTAssertEqual(error as? BelugaAudioShareCoordinatorError, .quarantined) }
        source.finishStop()
        checkTrue(await fixture.eventually { source.stops == 1 })
        checkTrue(await coordinator.stop(), "A later explicit stop may confirm cleanup, not clear quarantine")
        do { _ = try await coordinator.start(ttlSeconds: 30); XCTFail("Timeout quarantine is terminal for this host") }
        catch { XCTAssertEqual(error as? BelugaAudioShareCoordinatorError, .quarantined) }
    }

    func testStopFencesPendingRegistrationAndOldFatalCannotRevokeSuccessor() async throws {
        let fixture = CoordinatorFixture(); fixture.delayRegistration = true
        let coordinator = fixture.coordinator()
        let starting = Task { try await coordinator.start(ttlSeconds: 30) }
        checkTrue(await fixture.eventually { fixture.sockets.first?.registration != nil })
        let old = try XCTUnwrap(fixture.sockets.first)
        checkTrue(await coordinator.stop())
        do { _ = try await starting.value; XCTFail("Stopped registration cannot publish a capability") }
        catch { }
        fixture.delayRegistration = false
        let fresh = try await coordinator.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(fixture.sockets.last)
        old.fireSavedFatal()
        let listener = try await fixture.join(fresh, socket: socket, byte: 4)
        try listener.answer(socket)
        listener.peer.emit(.peerStateChanged(.connected)); listener.peer.emit(.iceStateChanged(.connected))
        checkTrue(await fixture.eventually { fixture.sources.first?.starts == 1 })
        XCTAssertEqual(listener.peer.fakeSink.revocations, 0)
        checkTrue(await coordinator.stop())
    }

    func testMalformedGrantAndOwnerTopologyFailBeforeCapture() async throws {
        for mode in [CoordinatorFakeSocket.GrantMode.booleanVersion, .extraField, .extendedExpiry, .expiredExpiry] {
            let fixture = CoordinatorFixture(); fixture.grantMode = mode
            let coordinator = fixture.coordinator()
            do { _ = try await coordinator.start(ttlSeconds: 30); XCTFail("Malformed grant must be rejected") }
            catch { }
            XCTAssertTrue(fixture.sources.isEmpty)
            XCTAssertTrue(fixture.peers.isEmpty)
            checkTrue(await coordinator.stop())
        }
        let fixture = CoordinatorFixture(), coordinator = fixture.coordinator()
        let started = try await coordinator.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(fixture.sockets.first)
        try socket.pushReady(started: started, listenerID: fixture.id(byte: 2), role: "listener")
        checkTrue(await fixture.eventually { fixture.statuses.contains(.failed) })
        XCTAssertTrue(fixture.peers.isEmpty)
        XCTAssertTrue(fixture.sources.isEmpty)
        checkTrue(await coordinator.stop())
    }

    func testShortenedRegistrationGrantIsAcceptedWithoutExtendingSentAtDeadline() async throws {
        let fixture = CoordinatorFixture(); fixture.grantMode = .shortenedExpiry
        let coordinator = fixture.coordinator()
        let started = try await coordinator.start(ttlSeconds: 12)
        XCTAssertEqual(Int64(started.expiresAt.timeIntervalSince1970 * 1_000),
                       CoordinatorFakeSocket.serverTime + 11_750)
        let socket = try XCTUnwrap(fixture.sockets.first)
        let listener = try await fixture.join(started, socket: socket, byte: 2)
        try listener.answer(socket)
        listener.peer.emit(.peerStateChanged(.connected)); listener.peer.emit(.iceStateChanged(.connected))
        checkTrue(await fixture.eventually { fixture.sources.first?.starts == 1 })
        let source = try XCTUnwrap(fixture.sources.first)
        // sentAt is 1 ns. Admission remains valid immediately before the shortened
        // 11,750 ms deadline, and closes at it, not at the originally requested 12 s.
        fixture.clock.set(11_750_000_000); source.deliver()
        XCTAssertEqual(listener.peer.fakeSink.frames, 1)
        fixture.clock.set(11_750_000_001); source.deliver()
        XCTAssertEqual(listener.peer.fakeSink.frames, 1)
        XCTAssertGreaterThan(listener.peer.fakeSink.revocations, 0)
        checkTrue(await coordinator.stop())
    }

    func testRegistrationMonotonicDeadlineOverflowFailsBeforeNativeAllocation() async throws {
        let fixture = CoordinatorFixture(); fixture.clock.set(UInt64.max - 1)
        let coordinator = fixture.coordinator()
        do { _ = try await coordinator.start(ttlSeconds: 30); XCTFail("Overflow may not wrap the absolute deadline") }
        catch { }
        XCTAssertTrue(fixture.sources.isEmpty); XCTAssertTrue(fixture.peers.isEmpty)
        checkTrue(await coordinator.stop())
    }

    func testLeaseExpiryStopsCallbackDespiteHealthyPeersAndDoesNotReopen() async throws {
        let fixture = CoordinatorFixture(), coordinator = fixture.coordinator()
        let (_, _, listener, source) = try await fixture.active(coordinator)
        source.deliver()
        fixture.clock.set(15_000_000_001); source.deliver()
        fixture.clock.set(1); source.deliver()
        XCTAssertEqual(listener.peer.fakeSink.frames, 1)
        XCTAssertGreaterThan(listener.peer.fakeSink.revocations, 0)
        checkTrue(await coordinator.stop())
    }

    func testWrongAcknowledgementAndEncryptedNonAudioCommandFailClosed() async throws {
        let fixture = CoordinatorFixture(), coordinator = fixture.coordinator()
        let started = try await coordinator.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(fixture.sockets.first)
        let listener = try await fixture.join(started, socket: socket, byte: 2)
        try listener.send(["kind": "control", "action": "microphone"], socket: socket)
        checkTrue(await fixture.eventually { listener.peer.closes == 1 })
        XCTAssertTrue(fixture.sources.isEmpty)
        socket.push(try CoordinatorFixture.json(["type": "probe-ack", "v": 1,
            "nonce": fixture.id(byte: 7), "serverTime": CoordinatorFakeSocket.serverTime,
            "leaseExpiresAt": CoordinatorFakeSocket.serverTime + 15_000]))
        checkTrue(await fixture.eventually { fixture.statuses.contains(.failed) })
        checkTrue(await coordinator.stop())
    }

    func testEmptyShareKeepsOriginalSourceAndRejoinDoesNotRestartCapture() async throws {
        let fixture = CoordinatorFixture(), coordinator = fixture.coordinator()
        let (started, socket, first, source) = try await fixture.active(coordinator)
        socket.push(try CoordinatorFixture.json(["type": "listener-left", "v": 1,
                                                "listenerID": fixture.id(byte: 2)]))
        checkTrue(await fixture.eventually { first.peer.closes == 1 && fixture.statuses.last == .active(listeners: 0) })
        XCTAssertEqual(source.stops, 0)
        XCTAssertFalse(fixture.statuses.contains(.ended))
        source.deliver(); XCTAssertEqual(first.peer.fakeSink.frames, 0)
        let second = try await fixture.join(started, socket: socket, byte: 3)
        try second.answer(socket)
        second.peer.emit(.peerStateChanged(.connected)); second.peer.emit(.iceStateChanged(.connected))
        checkTrue(await fixture.eventually { fixture.statuses.last == .active(listeners: 1) })
        source.deliver(); XCTAssertEqual(second.peer.fakeSink.frames, 1)
        XCTAssertEqual(fixture.sources.count, 1)
        XCTAssertEqual(source.starts, 1)
        checkTrue(await coordinator.stop())
    }

    func testRetiringRecipientRemainsOwnedUntilNativeCloseConfirms() async throws {
        let fixture = CoordinatorFixture(); fixture.timeout = 5_000_000
        let coordinator = fixture.coordinator()
        let (_, socket, listener, source) = try await fixture.active(coordinator)
        listener.peer.blockClose = true
        socket.push(try CoordinatorFixture.json(["type": "listener-left", "v": 1,
                                                "listenerID": fixture.id(byte: 2)]))
        checkTrue(await fixture.eventually { listener.peer.closeStarted })
        checkFalse(await coordinator.stop(), "Removal from active map is not native teardown confirmation")
        XCTAssertEqual(source.stops, 0, "Owned cleanup still waits for the retired recipient")
        do { _ = try await coordinator.start(ttlSeconds: 30); XCTFail("Retiring native peer may not be replaced") }
        catch { XCTAssertEqual(error as? BelugaAudioShareCoordinatorError, .quarantined) }
        listener.peer.finishClose()
        checkTrue(await fixture.eventually { source.stops == 1 })
        checkTrue(await coordinator.stop())
    }

    func testUnhealthyTransitionRetiresAdmittedRecipientWithoutSilentlyReadmitting() async throws {
        for event in [WebRTCAudioShareEvent.peerStateChanged(.connecting), .iceStateChanged(.checking)] {
            let fixture = CoordinatorFixture(), coordinator = fixture.coordinator()
            let (_, socket, listener, source) = try await fixture.active(coordinator)
            source.deliver(); listener.peer.emit(event)
            checkTrue(await fixture.eventually {
                listener.peer.closes == 1 && fixture.statuses.last == .active(listeners: 0)
            })
            listener.peer.emit(.peerStateChanged(.connected)); listener.peer.emit(.iceStateChanged(.completed))
            await fixture.settle(); source.deliver()
            XCTAssertEqual(listener.peer.admissions, 1)
            XCTAssertEqual(listener.peer.fakeSink.frames, 1)
            XCTAssertEqual(fixture.statuses.last, .active(listeners: 0))
            XCTAssertEqual(source.stops, 0, "Other/rejoining listeners keep the reusable link")
            XCTAssertEqual(socket.cancels, 0, "Retiring the current event-consumer must not cancel the share socket")
            checkTrue(await fixture.eventually {
                socket.sent.contains { $0["type"] as? String == "retire-listener" &&
                    $0["listenerID"] as? String == fixture.id(byte: 2) }
            })
            checkTrue(await coordinator.stop())
        }
    }

    func testEightActiveOrRetiringPeersBoundNativeFactoryAllocation() async throws {
        let fixture = CoordinatorFixture(); fixture.timeout = 5_000_000
        fixture.peerSetup = { $0.blockClose = true }
        let coordinator = fixture.coordinator()
        let started = try await coordinator.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(fixture.sockets.first)
        for byte in UInt8(2)...UInt8(9) { _ = try await fixture.join(started, socket: socket, byte: byte) }
        for byte in UInt8(2)...UInt8(9) {
            socket.push(try CoordinatorFixture.json(["type": "listener-left", "v": 1,
                                                    "listenerID": fixture.id(byte: byte)]))
        }
        checkTrue(await fixture.eventually { fixture.peers.count == 8 && fixture.peers.allSatisfy(\.closeStarted) })
        try socket.pushReady(started: started, listenerID: fixture.id(byte: 10))
        checkTrue(await fixture.eventually { fixture.statuses.contains(.failed) })
        XCTAssertEqual(fixture.peers.count, 8, "Retiring peers occupy the same maximum-eight budget")
        checkFalse(await coordinator.stop())
        for peer in fixture.peers { peer.finishClose() }
        checkTrue(await fixture.eventually { fixture.peers.allSatisfy { $0.closes == 1 } })
        checkTrue(await coordinator.stop())
    }

    func testRejectedFactoryCandidateIsOwnedBeforeCloseAndCannotEscapeStop() async throws {
        let fixture = CoordinatorFixture(); fixture.timeout = 5_000_000
        fixture.peerSetup = { [fixture] peer in
            peer.blockClose = true
            fixture.sockets.first?.fireSavedFatal()
        }
        let coordinator = fixture.coordinator()
        let started = try await coordinator.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(fixture.sockets.first)
        try socket.pushReady(started: started, listenerID: fixture.id(byte: 2))
        checkTrue(await fixture.eventually { fixture.peers.first?.closeStarted == true })
        checkFalse(await coordinator.stop(), "Rejected native candidate remains in exact retiring ownership")
        XCTAssertEqual(fixture.peers.count, 1)
        XCTAssertTrue(fixture.sources.isEmpty)
        fixture.peers.first?.finishClose()
        checkTrue(await fixture.eventually { fixture.peers.first?.closes == 1 })
        checkTrue(await coordinator.stop())
    }

    func testPreOfferFailureExplicitlyRetiresBrowserAndBrokerOccupancy() async throws {
        let fixture = CoordinatorFixture(); fixture.peerSetup = { $0.failOffer = true }
        let coordinator = fixture.coordinator()
        let started = try await coordinator.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(fixture.sockets.first)
        _ = try await fixture.join(started, socket: socket, byte: 2)
        checkTrue(await fixture.eventually {
            socket.sent.contains { $0["type"] as? String == "retire-listener" &&
                $0["listenerID"] as? String == fixture.id(byte: 2) && Set($0.keys) == Set(["type", "v", "listenerID"]) }
        })
        XCTAssertEqual(fixture.peers.first?.closes, 1)
        XCTAssertTrue(fixture.sources.isEmpty)
        checkTrue(await coordinator.stop())
    }

    func testHeldNegotiationCannotStarveAckAndStopAccountsItsExactTask() async throws {
        let fixture = CoordinatorFixture(); fixture.timeout = 5_000_000
        fixture.peerSetup = { $0.blockOffer = true }
        let coordinator = fixture.coordinator()
        let started = try await coordinator.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(fixture.sockets.first)
        let listener = try await fixture.join(started, socket: socket, byte: 2)
        checkTrue(await fixture.eventually { listener.peer.offerStarted })
        // A deliberately invalid ACK is consumed promptly despite a held offer. Previously it
        // would sit behind createOffer, leaving the actor unable to process owner authorization.
        socket.push(try CoordinatorFixture.json(["type": "probe-ack", "v": 1,
            "nonce": fixture.id(byte: 7), "serverTime": CoordinatorFakeSocket.serverTime,
            "leaseExpiresAt": CoordinatorFakeSocket.serverTime + 15_000]))
        checkTrue(await fixture.eventually { fixture.statuses.contains(.failed) })
        checkFalse(await coordinator.stop(), "Native close is not completion of every pending negotiation")
        listener.peer.finishOffer()
        checkTrue(await coordinator.stop())
        XCTAssertFalse(fixture.statuses.contains(.active(listeners: 1)))
        XCTAssertTrue(fixture.sources.isEmpty)
    }

    func testHeldSourceStartCannotOutliveSuccessfulStopOrCreateReplacement() async throws {
        let fixture = CoordinatorFixture(); fixture.timeout = 5_000_000
        fixture.sourceSetup = { $0.blockStart = true }
        let coordinator = fixture.coordinator()
        let started = try await coordinator.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(fixture.sockets.first)
        let listener = try await fixture.join(started, socket: socket, byte: 2)
        try listener.answer(socket)
        listener.peer.emit(.peerStateChanged(.connected)); listener.peer.emit(.iceStateChanged(.connected))
        checkTrue(await fixture.eventually { fixture.sources.first?.startHeld == true })
        let source = try XCTUnwrap(fixture.sources.first)
        checkFalse(await coordinator.stop())
        source.deliver(); XCTAssertEqual(listener.peer.fakeSink.frames, 0)
        do { _ = try await coordinator.start(ttlSeconds: 30); XCTFail("Held source ownership cannot be replaced") }
        catch { XCTAssertEqual(error as? BelugaAudioShareCoordinatorError, .quarantined) }
        source.finishStart()
        checkTrue(await coordinator.stop())
        XCTAssertEqual(fixture.sources.count, 1)
    }

    func testSaturatedSerialOutboxFailsShareRatherThanRetainingUnboundedSignals() async throws {
        let fixture = CoordinatorFixture(); fixture.timeout = 50_000_000
        let coordinator = fixture.coordinator()
        let (_, socket, listener, source) = try await fixture.active(coordinator)
        socket.blockSignals = true
        for _ in 0..<80 {
            listener.peer.emit(.localCandidate(.init(sdp: "candidate:fake 1 udp 1 127.0.0.1 1 typ host",
                sdpMid: "audio", sdpMLineIndex: 0, usernameFragment: "fake-fragment")))
        }
        checkTrue(await fixture.eventually { fixture.statuses.contains(.failed) })
        XCTAssertGreaterThan(listener.peer.fakeSink.revocations, 0)
        source.deliver(); XCTAssertEqual(listener.peer.fakeSink.frames, 0)
        XCTAssertLessThanOrEqual(socket.sent.filter { $0["type"] as? String == "signal" }.count, 2)
        checkTrue(await coordinator.stop())
    }
}

private func checkTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value, message, file: file, line: line)
}
private func checkFalse(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(value, message, file: file, line: line)
}

private final class CoordinatorFixture: @unchecked Sendable {
    let clock = CoordinatorClock(), owner = CoordinatorOwner()
    private let lock = NSLock()
    private var socketValues: [CoordinatorFakeSocket] = []
    private var peerValues: [CoordinatorFakeRecipient] = []
    private var sourceValues: [CoordinatorFakeSource] = []
    private var statusValues: [BelugaAudioShareStatus] = []
    var timeout: UInt64 = 100_000_000
    var delayRegistration = false
    var grantMode = CoordinatorFakeSocket.GrantMode.valid
    var peerSetup: @Sendable (CoordinatorFakeRecipient) -> Void = { _ in }
    var sourceSetup: @Sendable (CoordinatorFakeSource) -> Void = { _ in }
    var sockets: [CoordinatorFakeSocket] { lock.withLock { socketValues } }
    var peers: [CoordinatorFakeRecipient] { lock.withLock { peerValues } }
    var sources: [CoordinatorFakeSource] { lock.withLock { sourceValues } }
    var statuses: [BelugaAudioShareStatus] { lock.withLock { statusValues } }
    func coordinator() -> BelugaAudioShareCoordinator {
        var dependencies = BelugaAudioShareDependencies()
        dependencies.now = clock.read
        dependencies.teardownTimeoutNanoseconds = timeout
        dependencies.socket = { [self] in
            let socket = CoordinatorFakeSocket(delay: delayRegistration, mode: grantMode)
            lock.withLock { socketValues.append(socket) }; return socket
        }
        dependencies.recipient = { [self] _, _ in
            let peer = CoordinatorFakeRecipient()
            lock.withLock { peerValues.append(peer) }; peerSetup(peer); return peer
        }
        dependencies.source = { [self] fanout, _ in
            let source = CoordinatorFakeSource(fanout: fanout)
            lock.withLock { sourceValues.append(source) }; sourceSetup(source); return source
        }
        return BelugaAudioShareCoordinator(endpoint: URL(string: "https://share.invalid")!,
            logger: CoordinatorSilentLogger(), status: { [self] value in lock.withLock { statusValues.append(value) } },
            ownerIsValid: owner.read, dependencies: dependencies)
    }
    func id(byte: UInt8) -> String { BelugaAudioShareEncoding.encode(Data(repeating: byte, count: 16)) }
    func join(_ started: BelugaAudioShareStarted, socket: CoordinatorFakeSocket, byte: UInt8) async throws -> CoordinatorListener {
        let count = peers.count, listenerID = id(byte: byte)
        try socket.pushReady(started: started, listenerID: listenerID)
        let joined = await eventually { self.peers.count > count }
        XCTAssertTrue(joined)
        let peer = try XCTUnwrap(peers.last)
        let fragment = try XCTUnwrap(URLComponents(url: started.url, resolvingAgainstBaseURL: false)?.fragment)
        let fields = try XCTUnwrap(URLComponents(string: "https://share.invalid/?\(fragment)")?.queryItems)
        let rootString = try XCTUnwrap(fields.first(where: { $0.name == "k" })?.value)
        let context = BelugaAudioShareSignalContext(shareID: try socket.shareID(),
            generation: socket.generation, listenerID: listenerID,
            expiresAt: Int64(started.expiresAt.timeIntervalSince1970 * 1_000))
        let cipher = try BelugaAudioShareSignalCipher(root: BelugaAudioShareEncoding.decode(rootString, count: 32...32),
                                                     context: context, role: "listener")
        return CoordinatorListener(peer: peer, cipher: cipher)
    }
    func active(_ coordinator: BelugaAudioShareCoordinator) async throws
        -> (BelugaAudioShareStarted, CoordinatorFakeSocket, CoordinatorListener, CoordinatorFakeSource) {
        let started = try await coordinator.start(ttlSeconds: 30)
        let socket = try XCTUnwrap(sockets.first)
        let listener = try await join(started, socket: socket, byte: 2)
        try listener.answer(socket)
        listener.peer.emit(.peerStateChanged(.connected)); listener.peer.emit(.iceStateChanged(.connected))
        let capturing = await eventually { self.sources.first?.starts == 1 }
        XCTAssertTrue(capturing)
        return (started, socket, listener, try XCTUnwrap(sources.first))
    }
    func eventually(_ predicate: @escaping @Sendable () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return predicate()
    }
    func settle() async { for _ in 0..<10 { await Task.yield() } }
    static func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
}

private struct CoordinatorListener: Sendable {
    let peer: CoordinatorFakeRecipient
    let cipher: BelugaAudioShareSignalCipher
    func answer(_ socket: CoordinatorFakeSocket) throws { try send(["kind": "answer", "sdp": "fake-audio-answer"], socket: socket) }
    func send(_ value: [String: Any], socket: CoordinatorFakeSocket) throws {
        var envelope = try cipher.seal(Data(CoordinatorFixture.json(value).utf8))
        envelope.from = "listener"
        socket.push(String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self))
    }
}

private final class CoordinatorClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 1
    func read() -> UInt64 { lock.withLock { value } }
    func set(_ value: UInt64) { lock.withLock { self.value = value } }
}
private final class CoordinatorOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true
    func read() -> Bool { lock.withLock { value } }
    func set(_ value: Bool) { lock.withLock { self.value = value } }
}
private struct CoordinatorSilentLogger: CaptureCore.Logger {
    func debug(_ message: String) { }
    func info(_ message: String) { }
    func error(_ message: String) { }
}

private final class CoordinatorFakeSocket: BelugaAudioShareSocket, @unchecked Sendable {
    enum GrantMode { case valid, shortenedExpiry, booleanVersion, extraField, extendedExpiry, expiredExpiry }
    static let serverTime: Int64 = 1_000_000
    let generation = BelugaAudioShareEncoding.encode(Data(repeating: 1, count: 16))
    private let lock = NSLock()
    private let delay: Bool, mode: GrantMode
    private var savedURL: URL?
    private var savedRegistration: [String: Any]?
    private var savedGrantExpiry: Int64?
    private var sentValues: [[String: Any]] = []
    private var fatal: (@Sendable () -> Void)?
    private var closed = false
    private var cancelCount = 0
    private var messages: [String] = []
    private var pending: CheckedContinuation<String, any Error>?
    private var pendingSend: CheckedContinuation<Void, any Error>?
    var blockSignals = false
    var url: URL? { lock.withLock { savedURL } }
    var registration: [String: Any]? { lock.withLock { savedRegistration } }
    var sent: [[String: Any]] { lock.withLock { sentValues } }
    var cancels: Int { lock.withLock { cancelCount } }
    init(delay: Bool, mode: GrantMode) { self.delay = delay; self.mode = mode }
    func shareID() throws -> String { try XCTUnwrap(url?.lastPathComponent) }
    func open(url: URL, onFatal: @escaping @Sendable () -> Void) async throws {
        lock.withLock { savedURL = url; fatal = onFatal }
    }
    func send(_ text: String) async throws {
        guard !lock.withLock({ closed }) else { throw BelugaAudioShareCoordinatorError.unavailable }
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        lock.withLock { sentValues.append(value) }
        if blockSignals, value["type"] as? String == "signal" {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock { () -> Bool in
                    guard !closed else { return true }; pendingSend = continuation; return false
                }
                if cancelled { continuation.resume(throwing: BelugaAudioShareCoordinatorError.unavailable) }
            }
        }
        switch value["type"] as? String {
        case "register":
            lock.withLock { savedRegistration = value }
            guard !delay else { return }
            let ttl = try XCTUnwrap(value["ttlSeconds"] as? Int)
            var grant: [String: Any] = ["type": "registered", "v": 1, "shareID": try shareID(),
                "generation": generation, "expiresAt": Self.serverTime + Int64(ttl) * 1_000,
                "serverTime": Self.serverTime, "leaseExpiresAt": Self.serverTime + min(Int64(ttl) * 1_000, 15_000),
                "maxListeners": 8]
            switch mode {
            case .valid: break
            case .shortenedExpiry:
                grant["expiresAt"] = Self.serverTime + Int64(ttl) * 1_000 - 250
                grant["leaseExpiresAt"] = Self.serverTime + min(Int64(ttl) * 1_000 - 250, 15_000)
            case .booleanVersion: grant["v"] = true
            case .extraField: grant["authority"] = "unexpected"
            case .extendedExpiry: grant["expiresAt"] = Self.serverTime + Int64(ttl + 1) * 1_000
            case .expiredExpiry: grant["expiresAt"] = Self.serverTime
            }
            lock.withLock { savedGrantExpiry = grant["expiresAt"] as? Int64 }
            push(try CoordinatorFixture.json(grant))
        case "probe":
            push(try CoordinatorFixture.json(["type": "probe-ack", "v": 1,
                "nonce": try XCTUnwrap(value["nonce"] as? String), "serverTime": Self.serverTime,
                "leaseExpiresAt": min(Self.serverTime + 15_000, lock.withLock { savedGrantExpiry } ?? (Self.serverTime + 15_000))]))
        default: break
        }
    }
    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let immediate = lock.withLock { () -> Result<String, BelugaAudioShareCoordinatorError>? in
                if closed { return .failure(.unavailable) }
                if !messages.isEmpty { return .success(messages.removeFirst()) }
                if pending != nil { return .failure(.invalidMessage) }
                pending = continuation; return nil
            }
            if let immediate { continuation.resume(with: immediate.mapError { $0 as any Error }) }
        }
    }
    func push(_ text: String) {
        let waiter = lock.withLock { () -> CheckedContinuation<String, any Error>? in
            guard !closed else { return nil }
            if let waiter = pending { pending = nil; return waiter }
            messages.append(text); return nil
        }
        waiter?.resume(returning: text)
    }
    func pushReady(started: BelugaAudioShareStarted, listenerID: String, role: String = "owner") throws {
        push(try CoordinatorFixture.json(["type": "listener-ready", "v": 1, "role": role,
            "shareID": try shareID(), "generation": generation, "listenerID": listenerID,
            "expiresAt": Int64(started.expiresAt.timeIntervalSince1970 * 1_000),
            "serverTime": Self.serverTime, "iceServers": []]))
    }
    func cancel() {
        let state = lock.withLock { () -> ((@Sendable () -> Void)?, CheckedContinuation<String, any Error>?, CheckedContinuation<Void, any Error>?) in
            closed = true; cancelCount += 1
            let waiter = pending, send = pendingSend; pending = nil; pendingSend = nil
            return (fatal, waiter, send)
        }
        state.0?(); state.1?.resume(throwing: BelugaAudioShareCoordinatorError.unavailable)
        state.2?.resume(throwing: BelugaAudioShareCoordinatorError.unavailable)
    }
    func fireSavedFatal() { lock.withLock { fatal }?() }
}

private final class CoordinatorFakeRecipient: BelugaAudioShareRecipient, @unchecked Sendable {
    let events: AsyncStream<WebRTCAudioShareEvent>
    let continuation: AsyncStream<WebRTCAudioShareEvent>.Continuation
    let fakeSink = CoordinatorFakeSink()
    var sink: any BelugaAudioShareSink { fakeSink }
    private let lock = NSLock()
    private var admissionCount = 0, closeCount = 0
    private var beganClose = false
    private var closeWaiter: CheckedContinuation<Void, Never>?
    private var offerWaiter: CheckedContinuation<Void, Never>?
    private var beganOffer = false
    var blockClose = false
    var blockOffer = false, failOffer = false
    var admissions: Int { lock.withLock { admissionCount } }
    var closes: Int { lock.withLock { closeCount } }
    var closeStarted: Bool { lock.withLock { beganClose } }
    var offerStarted: Bool { lock.withLock { beganOffer } }
    init() { (events, continuation) = AsyncStream.makeStream() }
    func emit(_ event: WebRTCAudioShareEvent) { continuation.yield(event) }
    func createOffer() async throws -> String {
        if blockOffer {
            await withCheckedContinuation { waiter in lock.withLock { beganOffer = true; offerWaiter = waiter } }
        }
        if failOffer { throw BelugaAudioShareCoordinatorError.unavailable }
        return "fake-audio-offer"
    }
    func finishOffer() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let waiter = offerWaiter; offerWaiter = nil; return waiter
        }
        waiter?.resume()
    }
    func setAnswer(_ sdp: String) async throws { }
    func addICE(_ candidate: RemoteICECandidate) async throws { }
    func admitCapture() async throws { lock.withLock { admissionCount += 1 } }
    func revokeCapture() { fakeSink.revokeCapture() }
    func close() async {
        if blockClose {
            await withCheckedContinuation { waiter in
                lock.withLock { beganClose = true; closeWaiter = waiter }
            }
        }
        lock.withLock { closeCount += 1 }; continuation.finish()
    }
    func finishClose() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let waiter = closeWaiter; closeWaiter = nil; return waiter
        }
        waiter?.resume()
    }
}
private final class CoordinatorFakeSink: BelugaAudioShareSink, @unchecked Sendable {
    private let lock = NSLock()
    private var frameCount = 0, revocationCount = 0
    private var closed = false
    var frames: Int { lock.withLock { frameCount } }
    var revocations: Int { lock.withLock { revocationCount } }
    func capture(sampleBuffer: CMSampleBuffer) { lock.withLock { if !closed { frameCount += 1 } } }
    func capture(audioBufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription,
                 frameCount: UInt32, presentationTime: CMTime) { lock.withLock { if !closed { self.frameCount += 1 } } }
    func revokeCapture() { lock.withLock { closed = true; revocationCount += 1 } }
}
private final class CoordinatorFakeSource: BelugaAudioShareSource, @unchecked Sendable {
    private let lock = NSLock()
    let fanout: BelugaAudioShareFanout
    private var startCount = 0, stopCount = 0
    private var stopWaiter: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var beganStart = false
    var failStop = false, blockStop = false
    var blockStart = false
    var starts: Int { lock.withLock { startCount } }
    var stops: Int { lock.withLock { stopCount } }
    var startHeld: Bool { lock.withLock { beganStart } }
    init(fanout: BelugaAudioShareFanout) { self.fanout = fanout }
    func start() async throws {
        lock.withLock { startCount += 1 }
        if blockStart {
            await withCheckedContinuation { waiter in lock.withLock { beganStart = true; startWaiter = waiter } }
        }
    }
    func finishStart() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let waiter = startWaiter; startWaiter = nil; return waiter
        }
        waiter?.resume()
    }
    func revokeStart() { }
    func stop() async throws {
        if blockStop {
            await withCheckedContinuation { continuation in lock.withLock { stopWaiter = continuation } }
        }
        if failStop { throw BelugaAudioShareCoordinatorError.unavailable }
        lock.withLock { stopCount += 1 }
    }
    func finishStop() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let waiter = stopWaiter; stopWaiter = nil; return waiter
        }
        waiter?.resume()
    }
    func deliver() {
        var list = AudioBufferList(mNumberBuffers: 0, mBuffers: AudioBuffer())
        withUnsafePointer(to: &list) {
            fanout.consumeSystemAudioFrames($0, format: AudioStreamBasicDescription(), frameCount: 480, presentationTime: .zero)
        }
    }
}
