import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

/// Concrete persistence composition over isolated opaque bytes, not a throwing-store shortcut.
/// Denial-only decode selection exercises refusal before persistence effects.
final class WorldwidePairingCommitDecodeFaultTests: XCTestCase {
    func testLegacyRecordDecodeBridgeRefusalPreservesExactBytesWithoutMigrationOrDeletion() throws {
        let bytes = PairingCommitDecodeMemory()
        let actual = WorldwidePairingStore(dataStore: bytes)
        let identity = try actual.loadOrCreateHostIdentity(displayName: "Decode fixture")
        let pair = try makeDecodePair(host: identity)
        try actual.savePairedViewer(pair.host, for: identity)
        let before = bytes.snapshot
        let denied = WorldwidePairingStore(dataStore: bytes, pairedRecordDecodeFault: UInt32(1))

        XCTAssertThrowsError(try denied.loadPairedViewer(for: identity)) { error in
            XCTAssertEqual(error as? RemoteSessionCoreError, .invalidPairingCommitBridge)
        }
        XCTAssertThrowsError(try denied.phoneCatalog.loadOrMigrate(for: identity)) { error in
            XCTAssertEqual(error as? RemoteSessionCoreError, .invalidPairingCommitBridge,
                "Legacy import must not remap a copied bridge refusal to invalidCatalog")
        }
        XCTAssertEqual(try denied.loadOrCreateHostIdentity(displayName: "Ignored"), identity)
        XCTAssertEqual(bytes.snapshot, before,
            "Both refused decodes must preserve every account byte and all write/delete counts")
        XCTAssertNil(try bytes.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount),
            "A refused legacy import must not create an empty authoritative catalog")
        let cold = WorldwidePairingStore(dataStore: bytes)
        XCTAssertEqual(try cold.loadPairedViewer(for: identity), pair.host)
        XCTAssertEqual(try cold.loadOrCreateHostIdentity(displayName: nil), identity)
        XCTAssertEqual(bytes.snapshot, before)
    }

    func testCatalogLoadAndCheckpointReadbackBridgeRefusalNeverResetNamespaceOrWrite() throws {
        let bytes = PairingCommitDecodeMemory()
        let actual = WorldwidePairingStore(dataStore: bytes)
        let identity = try actual.loadOrCreateHostIdentity(displayName: "Catalog decode fixture")
        let pair = try makeDecodePair(host: identity)
        try actual.savePairedViewer(pair.host, for: identity)
        let snapshot = try actual.phoneCatalog.loadOrMigrate(for: identity)
        XCTAssertEqual(snapshot.selectedRecord, pair.host)
        XCTAssertNotNil(snapshot.legacyImportReceipt)
        let before = bytes.snapshot
        let denied = WorldwidePairingStore(dataStore: bytes, pairedRecordDecodeFault: UInt32(1))
        let checkpoint = WorldwidePairingCatalogCheckpoint(
            store: denied, identity: identity, snapshot: snapshot, ownerIsValid: { false })
        let copiedBefore = checkpoint.copiedStateForTesting

        XCTAssertThrowsError(try denied.phoneCatalog.loadOrMigrate(for: identity)) { error in
            XCTAssertEqual(error as? RemoteSessionCoreError, .invalidPairingCommitBridge)
        }
        XCTAssertThrowsError(try checkpoint.readback()) { error in
            XCTAssertEqual(error as? RemoteSessionCoreError, .invalidPairingCommitBridge,
                "Concrete catalog read must fail before checkpoint policy or ordinary stale mapping")
        }
        XCTAssertEqual(checkpoint.copiedStateForTesting.abi_version, copiedBefore.abi_version)
        XCTAssertEqual(checkpoint.copiedStateForTesting.flags, copiedBefore.flags)
        XCTAssertFalse(checkpoint.bridgeFaultedForTesting,
            "The catalog decode error is not a checkpoint producer fault")
        XCTAssertEqual(bytes.snapshot, before,
            "Catalog and checkpoint refusals must not rewrite, delete, migrate or reset any namespace")
        XCTAssertThrowsError(try actual.loadPairedViewer(for: identity)) { error in
            XCTAssertEqual(error as? WorldwidePairingStoreError, .catalogIsAuthoritative,
                "Existing catalog authority must survive the failed readback")
        }
        let cold = WorldwidePairingStore(dataStore: bytes)
        let recovered = try cold.phoneCatalog.loadOrMigrate(for: identity)
        XCTAssertEqual(recovered, snapshot)
        XCTAssertEqual(recovered.selectedRecord, pair.host)
        guard case .resend(let completion) = try XCTUnwrap(recovered.selectedRecord).recoveryAction else {
            return XCTFail("Actual cold decoding must retain the exact durable completion")
        }
        XCTAssertEqual(completion, pair.completion)
        var viewer = pair.viewer
        let activation = try viewer.acceptCompletion(completion, using: pair.viewerIdentity)
        var host = pair.host
        try host.acceptActivationAcknowledgement(activation)
        XCTAssertEqual(host.pairingState, .active,
            "Genuine peer authentication must still accept the actual cold-read opaque commit")
        XCTAssertEqual(bytes.snapshot, before,
            "Cold decoding and in-memory authentication are not storage repair writes")
    }

    func testCandidateRecordRoundtripBridgeRefusalPreservesOriginalCatalogAndIdentityPriority() throws {
        let bytes = PairingCommitDecodeMemory()
        let actual = WorldwidePairingStore(dataStore: bytes)
        let identity = try actual.loadOrCreateHostIdentity(displayName: "Candidate decode fixture")
        let pair = try makeDecodePair(host: identity)
        try actual.savePairedViewer(pair.host, for: identity)
        let snapshot = try actual.phoneCatalog.loadOrMigrate(for: identity)
        XCTAssertEqual(snapshot.selectedRecord, pair.host)
        XCTAssertEqual(pair.host.pairingState, .acceptedReceived)
        XCTAssertEqual(pair.host.recoveryAction, .resend(pair.completion))
        let before = bytes.snapshot

        var viewer = pair.viewer
        let activation = try viewer.acceptCompletion(pair.completion, using: pair.viewerIdentity)
        var candidate = pair.host
        try candidate.acceptActivationAcknowledgement(activation)
        XCTAssertEqual(candidate.pairingState, .active)
        XCTAssertEqual(candidate.recoveryAction, .none)

        // Only host/active/nil-cache is denied. The stored received/completion catalog
        // decodes normally, so update reaches validateRecord's candidate roundtrip.
        let denied = WorldwidePairingStore(dataStore: bytes,
            pairedRecordDecodeFault: UInt32(0x8000_0030)).phoneCatalog
        XCTAssertEqual(try denied.loadOrMigrate(for: identity), snapshot)
        XCTAssertThrowsError(try denied.updatePairedPhone(candidate, for: identity,
                                                        expectedToken: snapshot.token)) { error in
            XCTAssertEqual(error as? RemoteSessionCoreError, .invalidPairingCommitBridge,
                "Candidate roundtrip refusal must not become invalidCatalog or staleRecord")
        }
        XCTAssertEqual(bytes.snapshot, before)
        XCTAssertThrowsError(try denied.updatePairedPhone(pair.viewer, for: identity,
                                                        expectedToken: snapshot.token)) { error in
            XCTAssertEqual(error as? WorldwidePairedPhoneCatalogError, .identityMismatch,
                "Original candidate identity guard remains before record decoding")
        }
        XCTAssertEqual(bytes.snapshot, before,
            "Neither refusal may rewrite or delete the durable record, identity or catalog")
        let cold = WorldwidePairingStore(dataStore: bytes)
        let recovered = try cold.phoneCatalog.loadOrMigrate(for: identity)
        XCTAssertEqual(recovered, snapshot)
        XCTAssertEqual(recovered.selectedRecord, pair.host)
        XCTAssertEqual(recovered.selectedRecord?.recoveryAction, .resend(pair.completion))
        XCTAssertEqual(try cold.loadOrCreateHostIdentity(displayName: nil), identity)
        XCTAssertEqual(bytes.snapshot, before)
    }
}

private struct PairingCommitDecodePair {
    let host: RemotePairedDeviceRecord
    let viewer: RemotePairedDeviceRecord
    let viewerIdentity: RemoteDeviceIdentity
    let completion: RemotePairingCommit
}

/// Every record and commit is produced by the genuine public pairing/authentication path.
private func makeDecodePair(host: RemoteDeviceIdentity) throws -> PairingCommitDecodePair {
    let viewerIdentity = try RemoteDeviceIdentity.generate(role: .viewer)
    let invitation = try RemoteInvitationCode.generate()
    let hostParticipant = try RemotePairingParticipant(identity: host, invitation: invitation)
    let viewerParticipant = try RemotePairingParticipant(identity: viewerIdentity, invitation: invitation)
    let hostAgreement = try hostParticipant.accept(viewerParticipant.hello)
    let viewerAgreement = try viewerParticipant.accept(hostParticipant.hello)
    var hostRecord = try hostAgreement.makePendingRecord(
        peerConfirmation: viewerAgreement.makeConfirmation())
    var viewerRecord = try viewerAgreement.makePendingRecord(
        peerConfirmation: hostAgreement.makeConfirmation())
    let proposal = try hostRecord.prepareProposal(using: host)
    let acknowledgement = try viewerRecord.prepareAcknowledgement(after: proposal, using: viewerIdentity)
    try hostRecord.acceptAcknowledgement(acknowledgement)
    let completion = try hostRecord.prepareCompletion(using: host)
    return .init(host: hostRecord, viewer: viewerRecord,
                 viewerIdentity: viewerIdentity, completion: completion)
}

/// The real stores encode, decode and validate these bytes; this backend only retains them.
private final class PairingCommitDecodeMemory: WorldwidePairingDataStore, @unchecked Sendable {
    struct Snapshot: Equatable {
        let values: [String: Data]
        let writtenAccounts: [String]
        let removedAccounts: [String]
    }
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var writtenAccounts: [String] = []
    private var removedAccounts: [String] = []
    var snapshot: Snapshot {
        lock.withLock {
            .init(values: values, writtenAccounts: writtenAccounts, removedAccounts: removedAccounts)
        }
    }
    func data(for account: String) throws -> Data? { lock.withLock { values[account] } }
    func set(_ data: Data, for account: String) throws {
        lock.withLock { values[account] = data; writtenAccounts.append(account) }
    }
    func removeData(for account: String) throws {
        lock.withLock { values.removeValue(forKey: account); removedAccounts.append(account) }
    }
}
