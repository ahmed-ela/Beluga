import CaptureCore
import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

@MainActor
final class WorldwideHostPairingCommitPersistenceTests: XCTestCase {
    func testAcknowledgementFirstSaveFailureBlocksCompletionAndColdRetryUsesStoredProposal() async throws {
        let fixture = try ACKPersistenceFixture.make()
        let h = try await startOwner(fixture)
        let before = try fixture.snapshot()
        let beforeBytes = try XCTUnwrap(fixture.backend.catalogBytes)
        let attempts = fixture.backend.catalogWriteAttempts
        let error = ACKPersistenceStorageError()
        fixture.backend.failCatalogWrite(afterSuccessfulWrites: 0, writeThenThrow: false, error: error)

        h.client.emit(.signal(.pairingCommit(fixture.acknowledgement)))
        try await waitUntil { h.presentations.latest?.phase == .unavailable }
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 1)
        XCTAssertTrue(fixture.backend.lastThrown === error)
        XCTAssertTrue(fixture.backend.catalogBytes == beforeBytes)
        XCTAssertEqual(try fixture.snapshot(), before)
        let memory = try await h.coordinator.pairedPhones()
        XCTAssertEqual(memory, before)
        let rejected = try fixture.lastAttemptedRecord()
        XCTAssertEqual(rejected, try fixture.receivedWithoutCompletion())
        XCTAssertEqual(rejected.pairingState, .acceptedReceived)
        XCTAssertEqual(rejected.recoveryAction, .issueCompletion)
        XCTAssertEqual(h.client.completions.count, 0)
        XCTAssertEqual(h.effects.mediaConstructions, 0)
        await stopOwner(h)

        // A fresh coordinator and store facade consume the actual unchanged bytes.
        let send = ACKPersistenceGate()
        let cold = try await startOwner(fixture, completionGate: send)
        XCTAssertTrue(try XCTUnwrap(cold.client.proposals.first).commit == fixture.proposal)
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 1)
        cold.client.emit(.signal(.pairingCommit(fixture.acknowledgement)))
        try await waitUntil { cold.client.completions.count == 1 }
        let sent = try XCTUnwrap(cold.client.completions.first)
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 3)
        assertBothCuts(fixture, after: attempts + 1, send: sent)
        _ = try authenticateCompletion(sent.commit, fixture: fixture)
        XCTAssertEqual(sent.durableRecord.pairingState, .acceptedReceived)
        XCTAssertEqual(cold.client.completionReturns, 0)
        XCTAssertEqual(cold.effects.mediaConstructions, 0)
        send.open()
        try await waitUntil { cold.client.completionReturns == 1 }
        try await settleCurrentHandler(cold)
        XCTAssertEqual(try fixture.savedHost(), sent.durableRecord)
    }

    func testAcknowledgementFirstWriteThenThrowKeepsReceivedWithoutCacheForColdRecovery() async throws {
        let fixture = try ACKPersistenceFixture.make()
        let h = try await startOwner(fixture)
        let before = try fixture.snapshot()
        let beforeBytes = try XCTUnwrap(fixture.backend.catalogBytes)
        let attempts = fixture.backend.catalogWriteAttempts
        let error = ACKPersistenceStorageError()
        fixture.backend.failCatalogWrite(afterSuccessfulWrites: 0, writeThenThrow: true, error: error)

        h.client.emit(.signal(.pairingCommit(fixture.acknowledgement)))
        try await waitUntil { h.presentations.latest?.phase == .unavailable }
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 1)
        XCTAssertTrue(fixture.backend.lastThrown === error)
        XCTAssertFalse(fixture.backend.catalogBytes == beforeBytes)
        let durable = try fixture.snapshot()
        XCTAssertEqual(durable.selectedRecord, try fixture.receivedWithoutCompletion())
        XCTAssertEqual(durable.token.catalogID, before.token.catalogID)
        XCTAssertEqual(durable.token.revision, before.token.revision + 1)
        XCTAssertEqual(try fixture.savedHost().recoveryAction, .issueCompletion)
        await assertMemorySnapshotIsStale(h)
        XCTAssertEqual(h.client.completions.count, 0)
        XCTAssertEqual(h.effects.mediaConstructions, 0)
        await stopOwner(h)

        // No invented rollback to pending and no repeated incoming ACK is needed.
        let send = ACKPersistenceGate()
        let cold = try await startOwner(fixture, completionGate: send, expectProposal: false)
        try await waitUntil { cold.client.completions.count == 1 }
        let sent = try XCTUnwrap(cold.client.completions.first)
        XCTAssertEqual(cold.client.proposals.count, 0)
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 2)
        XCTAssertEqual(sent.durableSnapshot.token.revision, durable.token.revision + 1)
        assertStoredCompletion(sent)
        _ = try authenticateCompletion(sent.commit, fixture: fixture)
        XCTAssertEqual(cold.client.completionReturns, 0)
        send.open()
        try await waitUntil { cold.client.completionReturns == 1 }
        try await settleCurrentHandler(cold)
        XCTAssertEqual(try fixture.savedHost(), sent.durableRecord)
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 2,
            "markCompletionSent must not invent a changed backend write or activation")
    }

    func testAcknowledgementSecondSaveFailureKeepsReceivedWithoutCacheForColdRecovery() async throws {
        let fixture = try ACKPersistenceFixture.make()
        let h = try await startOwner(fixture)
        let before = try fixture.snapshot()
        let attempts = fixture.backend.catalogWriteAttempts
        let error = ACKPersistenceStorageError()
        fixture.backend.failCatalogWrite(afterSuccessfulWrites: 1, writeThenThrow: false, error: error)

        h.client.emit(.signal(.pairingCommit(fixture.acknowledgement)))
        try await waitUntil { h.presentations.latest?.phase == .unavailable }
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 2)
        XCTAssertTrue(fixture.backend.lastThrown === error)
        let durable = try fixture.snapshot()
        XCTAssertEqual(durable.selectedRecord, try fixture.receivedWithoutCompletion())
        XCTAssertEqual(durable.token.revision, before.token.revision + 1)
        let memory = try await h.coordinator.pairedPhones()
        XCTAssertEqual(memory, durable)
        XCTAssertEqual(try fixture.savedHost().recoveryAction, .issueCompletion)
        let unsaved = try fixture.lastAttemptedRecord()
        guard case let .resend(unsavedCompletion) = unsaved.recoveryAction else {
            return XCTFail("The refused second cut must contain the actual prepared completion")
        }
        XCTAssertEqual(unsavedCompletion.phase, .completion)
        XCTAssertEqual(h.client.completions.count, 0)
        XCTAssertEqual(h.effects.mediaConstructions, 0)
        await stopOwner(h)

        let send = ACKPersistenceGate()
        let cold = try await startOwner(fixture, completionGate: send, expectProposal: false)
        try await waitUntil { cold.client.completions.count == 1 }
        let sent = try XCTUnwrap(cold.client.completions.first)
        XCTAssertEqual(cold.client.proposals.count, 0)
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 3)
        XCTAssertEqual(sent.durableSnapshot.token.revision, durable.token.revision + 1)
        assertStoredCompletion(sent)
        assertSameUnsignedCommit(sent.commit, unsavedCompletion)
        // Both independently minted signatures must genuinely authenticate; their
        // signature bytes need not be equal in this CryptoKit environment.
        _ = try authenticateCompletion(unsavedCompletion, fixture: fixture)
        _ = try authenticateCompletion(sent.commit, fixture: fixture)
        send.open()
        try await waitUntil { cold.client.completionReturns == 1 }
        try await settleCurrentHandler(cold)
        XCTAssertEqual(try fixture.savedHost(), sent.durableRecord)
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 3)
    }

    func testAcknowledgementSecondWriteThenThrowKeepsExactCachedCompletionWithoutSending() async throws {
        let fixture = try ACKPersistenceFixture.make()
        let h = try await startOwner(fixture)
        let before = try fixture.snapshot()
        let attempts = fixture.backend.catalogWriteAttempts
        let error = ACKPersistenceStorageError()
        fixture.backend.failCatalogWrite(afterSuccessfulWrites: 1, writeThenThrow: true, error: error)

        h.client.emit(.signal(.pairingCommit(fixture.acknowledgement)))
        try await waitUntil { h.presentations.latest?.phase == .unavailable }
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 2)
        XCTAssertTrue(fixture.backend.lastThrown === error)
        let durable = try fixture.snapshot()
        let saved = try fixture.savedHost()
        XCTAssertEqual(saved, try fixture.lastAttemptedRecord())
        XCTAssertEqual(durable.token.revision, before.token.revision + 2)
        guard case let .resend(cached) = saved.recoveryAction else {
            return XCTFail("Write-then-throw must retain the actual cached completion, not a fictional nil cache")
        }
        XCTAssertEqual(cached.phase, .completion)
        XCTAssertEqual(saved.pairingState, .acceptedReceived)
        _ = try authenticateCompletion(cached, fixture: fixture)
        await assertMemorySnapshotIsStale(h)
        XCTAssertEqual(h.client.completions.count, 0)
        XCTAssertEqual(h.effects.mediaConstructions, 0)
        await stopOwner(h)

        let send = ACKPersistenceGate()
        let cold = try await startOwner(fixture, completionGate: send, expectProposal: false)
        try await waitUntil { cold.client.completions.count == 1 }
        let sent = try XCTUnwrap(cold.client.completions.first)
        XCTAssertTrue(sent.commit == cached, "Cold recovery must resend the exact saved object, not re-sign an equivalent packet")
        XCTAssertEqual(sent.durableSnapshot, durable)
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 2)
        XCTAssertEqual(cold.client.proposals.count, 0)
        assertStoredCompletion(sent)
        send.open()
        try await waitUntil { cold.client.completionReturns == 1 }
        try await settleCurrentHandler(cold)
        XCTAssertEqual(try fixture.snapshot(), durable)
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 2)
    }

    func testCompletionSendRequiresBothDurableAcknowledgementCutsAndNeverActivatesHost() async throws {
        let fixture = try ACKPersistenceFixture.make()
        let send = ACKPersistenceGate()
        let h = try await startOwner(fixture, completionGate: send)
        let before = try fixture.snapshot()
        let attempts = fixture.backend.catalogWriteAttempts
        XCTAssertEqual(h.client.completions.count, 0)
        h.client.emit(.signal(.pairingCommit(fixture.acknowledgement)))
        try await waitUntil { h.client.completions.count == 1 }
        let sent = try XCTUnwrap(h.client.completions.first)
        assertBothCuts(fixture, after: attempts, send: sent)
        XCTAssertEqual(sent.durableSnapshot.token.catalogID, before.token.catalogID)
        XCTAssertEqual(sent.durableSnapshot.token.revision, before.token.revision + 2)
        XCTAssertEqual(sent.durableSnapshot.selectedPhoneID, before.selectedPhoneID)
        XCTAssertEqual(sent.durableSnapshot.legacyImportReceipt, before.legacyImportReceipt)
        let memory = try await h.coordinator.pairedPhones()
        XCTAssertEqual(memory, sent.durableSnapshot)
        XCTAssertEqual(h.client.completionReturns, 0)
        XCTAssertEqual(sent.durableRecord.pairingState, .acceptedReceived)
        XCTAssertNil(h.presentations.latest?.connectedMediaTarget)
        XCTAssertEqual(h.effects.mediaConstructions, 0)
        let activation = try authenticateCompletion(sent.commit, fixture: fixture)

        send.open()
        try await waitUntil { h.client.completionReturns == 1 }
        try await settleCurrentHandler(h)
        XCTAssertEqual(try fixture.snapshot(), sent.durableSnapshot)
        XCTAssertEqual(try fixture.savedHost().pairingState, .acceptedReceived)
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 2)
        // Only the peer's genuine activation ACK may activate the host.
        h.client.emit(.signal(.pairingCommit(activation)))
        try await waitUntil { try fixture.savedHost().pairingState == .active }
        var expected = sent.durableRecord
        try expected.acceptActivationAcknowledgement(activation)
        XCTAssertEqual(try fixture.savedHost(), expected)
        XCTAssertEqual(try fixture.savedHost().recoveryAction, .none)
        XCTAssertEqual(fixture.backend.catalogWriteAttempts, attempts + 3)
        XCTAssertEqual(h.client.completions.count, 1)
        XCTAssertEqual(h.effects.mediaConstructions, 0)
    }

    private func startOwner(_ fixture: ACKPersistenceFixture,
                            completionGate: ACKPersistenceGate? = nil,
                            expectProposal: Bool = true) async throws -> ACKPersistenceHarness {
        let store = WorldwidePairingStore(dataStore: fixture.backend)
        let retry = ACKPersistenceGate()
        let client = ACKPersistenceAvailabilityProbe(fixture: fixture, completionGate: completionGate)
        let presentations = ACKPersistencePresentations(), effects = ACKPersistenceEffects()
        let coordinator = WorldwideHostCoordinator(endpoint: URL(string: "wss://example.invalid")!,
            forceRelay: false, screenDisplayID: nil, systemAudioDisplayID: nil,
            maximumWidth: 1_280, framesPerSecond: 30, maximumVideoBitrate: 4_000_000,
            remoteInputController: MacRemoteInputController(allowRemoteControl: false),
            store: store, hostDisplayName: "Private ACK fixture Mac",
            availabilityClientFactory: { _, _ in client },
            availabilityRetrySleep: { _ in await retry.wait(); try Task.checkCancellation() },
            presentation: { presentations.append($0) },
            catalogMutationIsAuthorized: { true }, catalogOwnerIsValid: { true },
            pairingClientFactory: { _, _ in throw ACKPersistenceFixtureError.unexpectedEffect },
            mediaServiceFactory: { _ in
                effects.recordMediaConstruction()
                throw ACKPersistenceFixtureError.unexpectedEffect
            }, logger: ACKPersistenceLogger())
        let h = ACKPersistenceHarness(coordinator: coordinator, client: client,
            retry: retry, presentations: presentations, effects: effects)
        addTeardownBlock {
            retry.open(); client.releaseAll()
            _ = await coordinator.stop()
        }
        let result = try await coordinator.start(resetPairing: false)
        guard case .paired = result else { throw ACKPersistenceFixtureError.unexpectedEffect }
        try await waitUntil { client.isConnected }
        client.emit(.ready(role: .host,
            exchangeID: try RemoteAvailabilityExchangeID(wireValue: "AAAAAAAAAAAAAAAAAAAAAA")))
        if expectProposal {
            try await waitUntil { client.proposals.count == 1 && presentations.latest?.phase == .preparingSession }
            XCTAssertTrue(try XCTUnwrap(client.proposals.first).commit == fixture.proposal)
        } else {
            try await waitUntil { client.completions.count == 1 }
        }
        return h
    }

    private func stopOwner(_ h: ACKPersistenceHarness) async {
        h.retry.open(); h.client.releaseAll()
        let clean = await h.coordinator.stop()
        XCTAssertTrue(clean)
    }

    private func settleCurrentHandler(_ h: ACKPersistenceHarness) async throws {
        let revision = try XCTUnwrap(h.presentations.latest).revision
        h.client.emit(.waiting)
        // A later event in the same actual availability loop cannot publish until
        // the preceding post-send native call, store check and owner fence return.
        try await waitUntil { h.presentations.latest?.phase == .pairedWaiting &&
            (h.presentations.latest?.revision ?? 0) > revision }
    }

    private func assertMemorySnapshotIsStale(_ h: ACKPersistenceHarness) async {
        do {
            _ = try await h.coordinator.pairedPhones()
            XCTFail("A thrown write cannot publish success into actor memory when the byte backend did change")
        } catch WorldwidePhoneCatalogRuntimeError.staleSelection { }
        catch { XCTFail("Unexpected stale-snapshot error: \(error)") }
    }

    private func assertBothCuts(_ fixture: ACKPersistenceFixture, after previousAttempts: Int,
                                send: ACKPersistenceSentCommit,
                                file: StaticString = #filePath, line: UInt = #line) {
        do {
            let attempts = fixture.backend.catalogAttempts
            let first = try XCTUnwrap(attempts.first { $0.ordinal == previousAttempts + 1 }, file: file, line: line)
            let second = try XCTUnwrap(attempts.first { $0.ordinal == previousAttempts + 2 }, file: file, line: line)
            XCTAssertTrue(first.wrote && !first.threw, file: file, line: line)
            XCTAssertTrue(second.wrote && !second.threw, file: file, line: line)
            XCTAssertEqual(try fixture.record(in: first.bytes), try fixture.receivedWithoutCompletion(), file: file, line: line)
            XCTAssertEqual(try fixture.record(in: second.bytes), send.durableRecord, file: file, line: line)
            XCTAssertTrue(fixture.backend.catalogBytes == second.bytes, file: file, line: line)
            XCTAssertEqual(send.writeAttemptsAtSend, previousAttempts + 2, file: file, line: line)
            assertStoredCompletion(send, file: file, line: line)
        } catch { XCTFail("Could not inspect the genuine durable cuts: \(error)", file: file, line: line) }
    }

    private func assertStoredCompletion(_ sent: ACKPersistenceSentCommit,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(sent.commit.phase, .completion, file: file, line: line)
        XCTAssertEqual(sent.durableRecord.pairingState, .acceptedReceived, file: file, line: line)
        XCTAssertEqual(sent.durableRecord.recoveryAction, .resend(sent.commit), file: file, line: line)
        XCTAssertEqual(sent.durableSnapshot.selectedPhoneID, sent.commit.recipientDeviceID, file: file, line: line)
    }

    private func authenticateCompletion(_ completion: RemotePairingCommit,
                                        fixture: ACKPersistenceFixture) throws -> RemotePairingCommit {
        var viewer = fixture.viewerRecord
        let activation = try viewer.acceptCompletion(completion, using: fixture.viewerIdentity)
        XCTAssertEqual(viewer.pairingState, .active)
        var host = try fixture.receivedWithoutCompletion()
        try host.acceptActivationAcknowledgement(activation)
        XCTAssertEqual(host.pairingState, .active)
        return activation
    }

    private func assertSameUnsignedCommit(_ lhs: RemotePairingCommit, _ rhs: RemotePairingCommit) {
        XCTAssertEqual(lhs.protocolVersion, rhs.protocolVersion)
        XCTAssertEqual(lhs.pairID, rhs.pairID)
        XCTAssertEqual(lhs.commitID, rhs.commitID)
        XCTAssertEqual(lhs.senderDeviceID, rhs.senderDeviceID)
        XCTAssertEqual(lhs.senderRole, rhs.senderRole)
        XCTAssertEqual(lhs.recipientDeviceID, rhs.recipientDeviceID)
        XCTAssertEqual(lhs.transcriptHash, rhs.transcriptHash)
        XCTAssertEqual(lhs.phase, rhs.phase)
        XCTAssertEqual(lhs.commitTag, rhs.commitTag)
    }

    private func waitUntil(_ condition: @escaping @MainActor () async throws -> Bool) async throws {
        for _ in 0..<2_500 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw ACKPersistenceFixtureError.boundedObservationExpired
    }
}

private struct ACKPersistenceFixture: Sendable {
    let backend: ACKPersistenceByteStore
    let hostIdentity: RemoteDeviceIdentity
    let viewerIdentity: RemoteDeviceIdentity
    let hostRecord: RemotePairedDeviceRecord
    let viewerRecord: RemotePairedDeviceRecord
    let proposal: RemotePairingCommit
    let acknowledgement: RemotePairingCommit

    static func make() throws -> Self {
        let backend = ACKPersistenceByteStore(), store = WorldwidePairingStore(dataStore: backend)
        let host = try store.loadOrCreateHostIdentity(displayName: "Private ACK fixture Mac")
        let viewer = try RemoteDeviceIdentity.generate(role: .viewer, displayName: "Private ACK fixture phone")
        let invitation = try RemoteInvitationCode.generate()
        let hp = try RemotePairingParticipant(identity: host, invitation: invitation)
        let vp = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        let ha = try hp.accept(vp.hello), va = try vp.accept(hp.hello)
        var hr = try ha.makePendingRecord(peerConfirmation: va.makeConfirmation())
        var vr = try va.makePendingRecord(peerConfirmation: ha.makeConfirmation())
        let proposal = try hr.prepareProposal(using: host)
        let acknowledgement = try vr.prepareAcknowledgement(after: proposal, using: viewer)
        try store.savePairedViewer(hr, for: host)
        let imported = try store.phoneCatalog.loadOrMigrate(for: host)
        guard imported.selectedRecord == hr else { throw ACKPersistenceFixtureError.invalidFixture }
        return .init(backend: backend, hostIdentity: host, viewerIdentity: viewer,
            hostRecord: hr, viewerRecord: vr, proposal: proposal, acknowledgement: acknowledgement)
    }

    func snapshot() throws -> WorldwidePairedPhoneCatalogSnapshot {
        try WorldwidePairingStore(dataStore: backend).phoneCatalog.loadOrMigrate(for: hostIdentity)
    }
    func savedHost() throws -> RemotePairedDeviceRecord { try XCTUnwrap(snapshot().selectedRecord) }
    func receivedWithoutCompletion() throws -> RemotePairedDeviceRecord {
        var record = hostRecord
        try record.acceptAcknowledgement(acknowledgement)
        return record
    }
    func record(in bytes: Data) throws -> RemotePairedDeviceRecord {
        let envelope = try JSONDecoder().decode(ACKPersistenceCatalogEnvelope.self, from: bytes)
        return try XCTUnwrap(envelope.records.first { $0.remoteDeviceID == envelope.selectedPhoneID })
    }
    func lastAttemptedRecord() throws -> RemotePairedDeviceRecord {
        try record(in: XCTUnwrap(backend.catalogAttempts.last).bytes)
    }
}

// Used only to read an actual production-encoded catalog attempt. Never writes a schema.
private struct ACKPersistenceCatalogEnvelope: Decodable {
    let selectedPhoneID: UUID?
    let records: [RemotePairedDeviceRecord]
}

@MainActor
private struct ACKPersistenceHarness {
    let coordinator: WorldwideHostCoordinator
    let client: ACKPersistenceAvailabilityProbe
    let retry: ACKPersistenceGate
    let presentations: ACKPersistencePresentations
    let effects: ACKPersistenceEffects
}

private struct ACKPersistenceCatalogAttempt: Sendable {
    let ordinal: Int
    let bytes: Data
    let wrote: Bool
    let threw: Bool
}

private final class ACKPersistenceByteStore: WorldwidePairingDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var attempts: [ACKPersistenceCatalogAttempt] = []
    private var failure: (ordinal: Int, writeThenThrow: Bool, error: ACKPersistenceStorageError)?
    private var thrown: ACKPersistenceStorageError?
    var catalogWriteAttempts: Int { lock.withLock { attempts.count } }
    var catalogAttempts: [ACKPersistenceCatalogAttempt] { lock.withLock { attempts } }
    var lastThrown: ACKPersistenceStorageError? { lock.withLock { thrown } }
    var catalogBytes: Data? { lock.withLock { storage[WorldwidePairedPhoneCatalogStore.catalogAccount] } }
    func failCatalogWrite(afterSuccessfulWrites: Int, writeThenThrow: Bool,
                          error: ACKPersistenceStorageError) {
        lock.withLock { failure = (attempts.count + afterSuccessfulWrites + 1, writeThenThrow, error) }
    }
    func data(for account: String) throws -> Data? { lock.withLock { storage[account] } }
    func set(_ value: Data, for account: String) throws {
        try lock.withLock {
            guard account == WorldwidePairedPhoneCatalogStore.catalogAccount else {
                storage[account] = value; return
            }
            let ordinal = attempts.count + 1
            if let rejected = failure, rejected.ordinal == ordinal {
                failure = nil
                if rejected.writeThenThrow { storage[account] = value }
                attempts.append(.init(ordinal: ordinal, bytes: value,
                    wrote: rejected.writeThenThrow, threw: true))
                thrown = rejected.error
                throw rejected.error
            }
            storage[account] = value
            attempts.append(.init(ordinal: ordinal, bytes: value, wrote: true, threw: false))
        }
    }
    func removeData(for account: String) throws { _ = lock.withLock { storage.removeValue(forKey: account) } }
}

private struct ACKPersistenceSentCommit: Sendable {
    let commit: RemotePairingCommit
    let durableSnapshot: WorldwidePairedPhoneCatalogSnapshot
    let durableRecord: RemotePairedDeviceRecord
    let writeAttemptsAtSend: Int
}

private final class ACKPersistenceAvailabilityProbe: WorldwideHostAvailabilityTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let fixture: ACKPersistenceFixture
    private let completionGate: ACKPersistenceGate?
    private var continuation: PairedAvailabilitySignalingClient.EventStream.Continuation?
    private var sends: [ACKPersistenceSentCommit] = []
    private var completionReturnCount = 0
    init(fixture: ACKPersistenceFixture, completionGate: ACKPersistenceGate?) {
        self.fixture = fixture; self.completionGate = completionGate
    }
    func connect() async throws -> PairedAvailabilitySignalingClient.EventStream {
        let stream = PairedAvailabilitySignalingClient.EventStream.makeStream()
        lock.withLock { continuation = stream.continuation }
        return stream.stream
    }
    func send(_ payload: RemoteAvailabilityPayload) async throws {
        guard case let .pairingCommit(commit) = payload else { throw ACKPersistenceFixtureError.unexpectedEffect }
        let durable = try fixture.snapshot()
        guard let durableRecord = durable.selectedRecord else { throw ACKPersistenceFixtureError.invalidFixture }
        let sent = ACKPersistenceSentCommit(commit: commit, durableSnapshot: durable, durableRecord: durableRecord,
            writeAttemptsAtSend: fixture.backend.catalogWriteAttempts)
        lock.withLock { sends.append(sent) }
        if commit.phase == .completion {
            await completionGate?.wait()
            lock.withLock { completionReturnCount += 1 }
        } else if commit.phase != .proposal { throw ACKPersistenceFixtureError.unexpectedEffect }
    }
    func close() async {
        let old = lock.withLock { let value = continuation; continuation = nil; return value }
        old?.finish()
    }
    func emit(_ event: PairedAvailabilitySignalingEvent) { lock.withLock { continuation }?.yield(event) }
    func releaseAll() { completionGate?.open() }
    var isConnected: Bool { lock.withLock { continuation != nil } }
    var proposals: [ACKPersistenceSentCommit] { lock.withLock { sends.filter { $0.commit.phase == .proposal } } }
    var completions: [ACKPersistenceSentCommit] { lock.withLock { sends.filter { $0.commit.phase == .completion } } }
    var completionReturns: Int { lock.withLock { completionReturnCount } }
}

private final class ACKPersistenceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        await withCheckedContinuation { continuation in
            let immediate = lock.withLock {
                if opened { return true }
                waiters.append(continuation); return false
            }
            if immediate { continuation.resume() }
        }
    }
    func open() {
        let pending = lock.withLock { opened = true; defer { waiters.removeAll() }; return waiters }
        pending.forEach { $0.resume() }
    }
}

private final class ACKPersistencePresentations: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [BelugaHostPresentation] = []
    func append(_ value: BelugaHostPresentation) { lock.withLock { values.append(value) } }
    var latest: BelugaHostPresentation? { lock.withLock { values.last } }
}

private final class ACKPersistenceEffects: @unchecked Sendable {
    private let lock = NSLock()
    private var media = 0
    func recordMediaConstruction() { lock.withLock { media += 1 } }
    var mediaConstructions: Int { lock.withLock { media } }
}

private final class ACKPersistenceLogger: Logger, @unchecked Sendable {
    func info(_: String) { }
    func debug(_: String) { }
    func error(_: String) { }
}

private enum ACKPersistenceFixtureError: Error { case invalidFixture, unexpectedEffect, boundedObservationExpired }
private final class ACKPersistenceStorageError: Error, @unchecked Sendable {}
