import CaptureCore
import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

/// In-memory peer executes the real pairing crypto and no network/native media operations.
actor CatalogPairingTransport: WorldwideHostPairingTransport {
    private let viewer: RemoteDeviceIdentity
    private let participant: RemotePairingParticipant
    private let failAfterProposal: Bool
    private let holdCompletion: AsyncStream<Void>?
    private let events = PairingBootstrapSignalingClient.EventStream.makeStream()
    private var agreement: RemotePairingAgreement?
    private var record: RemotePairedDeviceRecord?
    private(set) var completionSendStarted = false
    private var closed = false

    init(invitation: RemoteInvitationCode, failAfterProposal: Bool = false,
         holdCompletion: AsyncStream<Void>? = nil) throws {
        viewer = try RemoteDeviceIdentity.generate(role: .viewer, displayName: "Another Phone")
        participant = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        self.failAfterProposal = failAfterProposal
        self.holdCompletion = holdCompletion
    }

    func connect() async throws -> PairingBootstrapSignalingClient.EventStream {
        guard !closed else { throw CancellationError() }
        events.continuation.yield(.ready(role: .host, invitationExpiresAt: Date().addingTimeInterval(300)))
        return events.stream
    }

    func send(_ payload: RemotePairingPayload) async throws {
        guard !closed else { throw CancellationError() }
        switch payload {
        case .hello(let hello):
            agreement = try participant.accept(hello)
            events.continuation.yield(.signal(.hello(participant.hello)))
        case .confirmation(let confirmation):
            guard let agreement else { throw CatalogBootstrapTestError.unexpected }
            record = try agreement.makePendingRecord(peerConfirmation: confirmation)
            events.continuation.yield(.signal(.confirmation(try agreement.makeConfirmation())))
        case .commit(let commit):
            guard var record else { throw CatalogBootstrapTestError.unexpected }
            switch commit.phase {
            case .proposal:
                if failAfterProposal {
                    events.continuation.yield(.peerLeft(.viewer))
                    return
                }
                let acknowledgement = try record.prepareAcknowledgement(after: commit, using: viewer)
                self.record = record
                events.continuation.yield(.signal(.commit(acknowledgement)))
            case .completion:
                completionSendStarted = true
                if let holdCompletion { for await _ in holdCompletion { break } }
                // Intentionally return success even after close to exercise host post-await fence.
                guard !closed else { return }
                let activation = try record.acceptCompletion(commit, using: viewer)
                self.record = record
                events.continuation.yield(.signal(.commit(activation)))
            case .acknowledgement, .activationAcknowledgement:
                throw CatalogBootstrapTestError.unexpected
            }
        }
    }

    func close() async { closed = true; events.continuation.finish() }
}

final class WorldwidePairingCatalogBootstrapTests: XCTestCase {
    func testStopBeforeHeldCompletionReturnsCannotPersistCompletionSent() async throws {
        let memory = BootstrapCatalogMemory()
        let store = WorldwidePairingStore(dataStore: memory)
        let host = try store.loadOrCreateHostIdentity(displayName: "Private Test Mac")
        let empty = try store.phoneCatalog.loadOrMigrate(for: host)
        let checkpoint = WorldwidePairingCatalogCheckpoint(
            store: store, identity: host, snapshot: empty, ownerIsValid: { true }
        )
        let invitation = try RemoteInvitationCode.generate()
        let release = AsyncStream<Void>.makeStream()
        let transport = try CatalogPairingTransport(invitation: invitation, holdCompletion: release.stream)
        let bootstrap = try WorldwidePairingBootstrap(endpoint: URL(string: "wss://example.invalid")!,
            identity: host, checkpoint: checkpoint, invitation: invitation,
            signalingFactory: { _, _ in transport }, logger: BootstrapCatalogLogger())
        _ = try await bootstrap.start()
        for _ in 0..<1_000 {
            if await transport.completionSendStarted { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let started = await transport.completionSendStarted
        XCTAssertTrue(started)
        let beforeStop = try checkpoint.readback()
        let record = try XCTUnwrap(beforeStop.record)
        XCTAssertEqual(record.pairingState, .acceptedReceived)
        guard case .resend(let completion) = record.recoveryAction else {
            await bootstrap.stop()
            return XCTFail("A saved completion must exist before sending")
        }
        XCTAssertEqual(completion.phase, .completion)
        await bootstrap.stop()
        release.continuation.yield(())
        release.continuation.finish()
        // The consumer has no write authority after stop even if the fake send succeeds late.
        XCTAssertEqual(try checkpoint.readback().snapshot, beforeStop.snapshot)
        XCTAssertThrowsError(try checkpoint.update(record))
        XCTAssertNil(try memory.data(for: WorldwidePairingStore.pairedViewerAccount))
    }
}

private enum CatalogBootstrapTestError: Error { case unexpected }
private struct BootstrapCatalogLogger: Logger {
    func info(_: String) {}
    func debug(_: String) {}
    func error(_: String) {}
}
private final class BootstrapCatalogMemory: WorldwidePairingDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func data(for account: String) throws -> Data? { lock.withLock { values[account] } }
    func set(_ data: Data, for account: String) throws { lock.withLock { values[account] = data } }
    func removeData(for account: String) throws { _ = lock.withLock { values.removeValue(forKey: account) } }
}
