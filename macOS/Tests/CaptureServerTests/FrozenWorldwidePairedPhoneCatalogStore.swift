import CryptoKit
import Foundation
import RemoteSessionCore
@testable import CaptureServer

// Frozen before Rust authoring; all original storage and decision bodies are retained.
/// One bounded, atomic Keychain item containing independent phone bindings for this host.
///
/// All instances serialize read/check/write inside this process. The underlying backend has
/// item replacement, not cross-process CAS: the host's existing single-process owner boundary
/// is still required. No operation rewrites identity or the legacy single-viewer item. Once the
/// catalog exists, even an empty catalog is authoritative and legacy fallback is forbidden.
struct FrozenWorldwidePairedPhoneCatalogStore: Sendable {
    static let catalogAccount = "worldwide-paired-phones-catalog-v1"
    static let maximumPhoneCount = 8
    static let maximumCatalogBytes = WorldwideKeychainDataStore.maximumItemBytes

    private static let serializationLock = NSLock()
    private let dataStore: any WorldwidePairingDataStore
    private let pairedRecordDecodeFault: UInt32?

    init(dataStore: any WorldwidePairingDataStore, pairedRecordDecodeFault: UInt32? = nil) {
        self.dataStore = dataStore
        self.pairedRecordDecodeFault = pairedRecordDecodeFault
    }

    /// Imports the original record at most once, without changing any of its original bytes.
    /// The caller first obtains the stable host identity through WorldwidePairingStore.
    func loadOrMigrate(
        for identity: RemoteDeviceIdentity
    ) throws -> WorldwidePairedPhoneCatalogSnapshot {
        try serialized {
            try validatePersistedIdentity(identity)
            if let catalog = try loadCatalog(for: identity) { return catalog.snapshot }

            var catalog = Catalog(
                version: 1,
                catalogID: UUID(),
                revision: 1,
                hostDeviceID: identity.deviceID,
                hostSigningPublicKey: identity.signingPublicKey,
                selectedPhoneID: nil,
                records: [],
                legacyImportReceipt: nil
            )
            if let legacyBytes = try dataStore.data(for: WorldwidePairingStore.pairedViewerAccount) {
                try validateSize(legacyBytes)
                let record: RemotePairedDeviceRecord
                do {
                    record = try belugaPairingRecordDecoder(faultSelection: pairedRecordDecodeFault)
                        .decode(RemotePairedDeviceRecord.self, from: legacyBytes)
                }
                catch let error as RemoteSessionCoreError where error == .invalidPairingCommitBridge { throw error }
                catch { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
                try validateRecord(record, for: identity)
                catalog.records = [record]
                catalog.selectedPhoneID = record.remoteDeviceID
                catalog.legacyImportReceipt = WorldwidePairedPhoneLegacyReceipt(
                    sourceAccount: WorldwidePairingStore.pairedViewerAccount,
                    sourceSHA256: Data(SHA256.hash(data: legacyBytes)),
                    remoteDeviceID: record.remoteDeviceID,
                    pairID: record.pairID,
                    commitID: record.commitID
                )
            }
            try persist(catalog, for: identity)
            return catalog.snapshot
        }
    }

    /// Adds a new independent binding, leaving current selection unchanged. A re-pair requires
    /// explicit forgetting first; it cannot silently replace another phone or its key.
    @discardableResult
    func addPairedPhone(
        _ record: RemotePairedDeviceRecord,
        for identity: RemoteDeviceIdentity,
        expectedToken: WorldwidePairedPhoneCatalogToken
    ) throws -> WorldwidePairedPhoneCatalogSnapshot {
        try mutate(for: identity, expectedToken: expectedToken) { catalog in
            try validateRecord(record, for: identity)
            guard !catalog.records.contains(where: {
                $0.remoteDeviceID == record.remoteDeviceID ||
                    $0.remoteSigningPublicKey == record.remoteSigningPublicKey ||
                    $0.pairID == record.pairID || $0.commitID == record.commitID
            }) else { throw WorldwidePairedPhoneCatalogError.duplicatePhone }
            guard catalog.records.count < Self.maximumPhoneCount else {
                throw WorldwidePairedPhoneCatalogError.capacityReached
            }
            catalog.records.append(record)
        }
    }

    /// Advances only an existing exact binding. Old asynchronous completions cannot reinsert a
    /// forgotten phone, replace immutable keys, regress replay counters, or change selection.
    @discardableResult
    func updatePairedPhone(
        _ record: RemotePairedDeviceRecord,
        for identity: RemoteDeviceIdentity,
        expectedToken: WorldwidePairedPhoneCatalogToken
    ) throws -> WorldwidePairedPhoneCatalogSnapshot {
        try mutate(for: identity, expectedToken: expectedToken) { catalog in
            try validateRecord(record, for: identity)
            guard let index = catalog.records.firstIndex(where: {
                $0.remoteDeviceID == record.remoteDeviceID
            }) else { throw WorldwidePairedPhoneCatalogError.unknownPhone }
            let previous = catalog.records[index]
            guard try immutableBinding(of: previous) == immutableBinding(of: record) else {
                throw WorldwidePairedPhoneCatalogError.bindingConflict
            }
            guard record.nextOutboundReconnectSequence >= previous.nextOutboundReconnectSequence,
                  record.highestAcceptedReconnectSequence >= previous.highestAcceptedReconnectSequence,
                  phaseRank(record.pairingState) >= phaseRank(previous.pairingState) else {
                throw WorldwidePairedPhoneCatalogError.staleRecord
            }
            let previousRecovery = previous.recoveryAction
            let candidateRecovery = record.recoveryAction
            guard previousRecovery != .invalidBridge, candidateRecovery != .invalidBridge else {
                throw RemoteSessionCoreError.invalidPairingCommitBridge
            }
            if previous.pairingState == record.pairingState,
               case let .resend(commit) = previousRecovery,
               candidateRecovery != .resend(commit) {
                throw WorldwidePairedPhoneCatalogError.staleRecord
            }
            catalog.records[index] = record
        }
    }

    /// Selection is explicit. Passing nil disconnects durable selection without forgetting keys.
    @discardableResult
    func selectPhone(
        _ remoteDeviceID: UUID?,
        for identity: RemoteDeviceIdentity,
        expectedToken: WorldwidePairedPhoneCatalogToken
    ) throws -> WorldwidePairedPhoneCatalogSnapshot {
        try mutate(for: identity, expectedToken: expectedToken) { catalog in
            if let remoteDeviceID,
               !catalog.records.contains(where: { $0.remoteDeviceID == remoteDeviceID }) {
                throw WorldwidePairedPhoneCatalogError.unknownPhone
            }
            catalog.selectedPhoneID = remoteDeviceID
        }
    }

    /// Removes only this binding, never chooses a replacement, and preserves migration proof.
    @discardableResult
    func forgetPhone(
        _ remoteDeviceID: UUID,
        for identity: RemoteDeviceIdentity,
        expectedToken: WorldwidePairedPhoneCatalogToken
    ) throws -> WorldwidePairedPhoneCatalogSnapshot {
        try mutate(for: identity, expectedToken: expectedToken) { catalog in
            guard let index = catalog.records.firstIndex(where: {
                $0.remoteDeviceID == remoteDeviceID
            }) else { throw WorldwidePairedPhoneCatalogError.unknownPhone }
            catalog.records.remove(at: index)
            if catalog.selectedPhoneID == remoteDeviceID { catalog.selectedPhoneID = nil }
        }
    }

    private func mutate(
        for identity: RemoteDeviceIdentity,
        expectedToken: WorldwidePairedPhoneCatalogToken,
        change: (inout Catalog) throws -> Void
    ) throws -> WorldwidePairedPhoneCatalogSnapshot {
        try serialized {
            try validatePersistedIdentity(identity)
            guard var catalog = try loadCatalog(for: identity),
                  catalog.snapshot.token == expectedToken else {
                throw WorldwidePairedPhoneCatalogError.staleCatalog
            }
            let previous = catalog
            try change(&catalog)
            if catalog == previous { return previous.snapshot }
            guard catalog.revision < UInt64.max else {
                throw WorldwidePairedPhoneCatalogError.revisionExhausted
            }
            catalog.revision += 1
            try persist(catalog, for: identity)
            return catalog.snapshot
        }
    }

    private func serialized<Value>(_ body: () throws -> Value) rethrows -> Value {
        Self.serializationLock.lock()
        defer { Self.serializationLock.unlock() }
        return try body()
    }

    /// Never create or rotate an identity from this new catalog path.
    private func validatePersistedIdentity(_ identity: RemoteDeviceIdentity) throws {
        guard identity.role == .host,
              let bytes = try dataStore.data(for: WorldwidePairingStore.identityAccount) else {
            throw WorldwidePairedPhoneCatalogError.identityMismatch
        }
        try validateSize(bytes)
        let persisted: RemoteDeviceIdentity
        do { persisted = try JSONDecoder().decode(RemoteDeviceIdentity.self, from: bytes) }
        catch { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
        guard persisted == identity else {
            throw WorldwidePairedPhoneCatalogError.identityMismatch
        }
    }

    private func loadCatalog(for identity: RemoteDeviceIdentity) throws -> Catalog? {
        guard let bytes = try dataStore.data(for: Self.catalogAccount) else { return nil }
        try validateSize(bytes)
        let catalog: Catalog
        do {
            // Wrapper schemas are strict; the existing paired-record decoder validates the
            // complete cryptographic recovery state and keeps its deployed ABI unchanged.
            try validateWrapperKeys(bytes)
            catalog = try belugaPairingRecordDecoder(faultSelection: pairedRecordDecodeFault)
                .decode(Catalog.self, from: bytes)
            // Only this new store writes catalog bytes. Exact canonical round-trip rejects
            // duplicate keys, ignored nested fields, null/omitted aliases, and trailing data;
            // legacy import intentionally retains the deployed decoder's existing behavior.
            guard try Self.encoder().encode(catalog) == bytes else {
                throw WorldwidePairedPhoneCatalogError.invalidCatalog
            }
        } catch let error as RemoteSessionCoreError where error == .invalidPairingCommitBridge { throw error }
        catch { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
        try validate(catalog, for: identity)
        return catalog
    }

    private func persist(_ catalog: Catalog, for identity: RemoteDeviceIdentity) throws {
        try validate(catalog, for: identity)
        let bytes: Data
        do { bytes = try Self.encoder().encode(catalog) }
        catch { throw WorldwidePairedPhoneCatalogError.encodingFailed }
        try validateSize(bytes)
        try dataStore.set(bytes, for: Self.catalogAccount)
    }

    private func validateSize(_ bytes: Data) throws {
        guard !bytes.isEmpty else { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
        guard bytes.count <= Self.maximumCatalogBytes else {
            throw WorldwidePairedPhoneCatalogError.oversizedCatalog
        }
    }

    private func validate(_ catalog: Catalog, for identity: RemoteDeviceIdentity) throws {
        guard catalog.version == 1, catalog.catalogID != Self.zeroUUID, catalog.revision > 0 else {
            throw WorldwidePairedPhoneCatalogError.invalidCatalog
        }
        guard catalog.hostDeviceID == identity.deviceID,
              catalog.hostSigningPublicKey == identity.signingPublicKey else {
            throw WorldwidePairedPhoneCatalogError.identityMismatch
        }
        guard catalog.records.count <= Self.maximumPhoneCount else {
            throw WorldwidePairedPhoneCatalogError.capacityReached
        }
        var deviceIDs = Set<UUID>()
        var signingKeys = Set<Data>()
        var pairIDs = Set<UUID>()
        var commitIDs = Set<UUID>()
        for record in catalog.records {
            try validateRecord(record, for: identity)
            guard deviceIDs.insert(record.remoteDeviceID).inserted,
                  signingKeys.insert(record.remoteSigningPublicKey).inserted,
                  pairIDs.insert(record.pairID).inserted,
                  commitIDs.insert(record.commitID).inserted else {
                throw WorldwidePairedPhoneCatalogError.duplicatePhone
            }
        }
        if let selected = catalog.selectedPhoneID, !deviceIDs.contains(selected) {
            throw WorldwidePairedPhoneCatalogError.invalidCatalog
        }
        if let receipt = catalog.legacyImportReceipt {
            guard receipt.sourceAccount == WorldwidePairingStore.pairedViewerAccount,
                  receipt.sourceSHA256.count == SHA256.Digest.byteCount,
                  receipt.remoteDeviceID != Self.zeroUUID,
                  receipt.pairID != Self.zeroUUID, receipt.commitID != Self.zeroUUID else {
                throw WorldwidePairedPhoneCatalogError.invalidCatalog
            }
        }
    }

    private func validateRecord(
        _ record: RemotePairedDeviceRecord,
        for identity: RemoteDeviceIdentity
    ) throws {
        guard record.localRole == .host, record.remoteRole == .viewer,
              record.localDeviceID == identity.deviceID,
              record.localSigningPublicKey == identity.signingPublicKey else {
            throw WorldwidePairedPhoneCatalogError.identityMismatch
        }
        // The record's decoder authenticates any saved recovery commit. This round trip also
        // guards callers whose mutable counters/state came from a partially completed handshake.
        do {
            let bytes = try Self.encoder().encode(record)
            try validateSize(bytes)
            _ = try belugaPairingRecordDecoder(faultSelection: pairedRecordDecodeFault)
                .decode(RemotePairedDeviceRecord.self, from: bytes)
        } catch let error as WorldwidePairedPhoneCatalogError { throw error }
        catch let error as RemoteSessionCoreError where error == .invalidPairingCommitBridge { throw error }
        catch { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
    }

    /// Includes the private pair root and transcript without exposing them in the wrapper API.
    /// Only the four documented mutable fields are excluded from immutable binding comparison.
    private func immutableBinding(of record: RemotePairedDeviceRecord) throws -> Data {
        do {
            let bytes = try Self.encoder().encode(record)
            guard var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                throw WorldwidePairedPhoneCatalogError.invalidCatalog
            }
            for key in ["pairingState", "recoveryCommit", "nextOutboundReconnectSequence",
                        "highestAcceptedReconnectSequence"] {
                object.removeValue(forKey: key)
            }
            return Data(SHA256.hash(data: try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )))
        } catch let error as WorldwidePairedPhoneCatalogError { throw error }
        catch { throw WorldwidePairedPhoneCatalogError.encodingFailed }
    }

    private func phaseRank(_ state: RemotePairingPersistenceState) -> Int {
        switch state {
        case .pending: 0
        case .acceptedReceived: 1
        case .active: 2
        case .acceptedIssued: -1 // A viewer-only state; validateRecord rejects it before comparison.
        }
    }

    private func validateWrapperKeys(_ bytes: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw WorldwidePairedPhoneCatalogError.invalidCatalog
        }
        let required: Set<String> = ["version", "catalogID", "revision", "hostDeviceID",
                                     "hostSigningPublicKey", "records"]
        let allowed = required.union(["selectedPhoneID", "legacyImportReceipt"])
        guard required.isSubset(of: Set(object.keys)), Set(object.keys).isSubset(of: allowed) else {
            throw WorldwidePairedPhoneCatalogError.invalidCatalog
        }
        if let value = object["legacyImportReceipt"], !(value is NSNull) {
            guard let receipt = value as? [String: Any], Set(receipt.keys) == Set([
                "sourceAccount", "sourceSHA256", "remoteDeviceID", "pairID", "commitID",
            ]) else { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    private struct Catalog: Codable, Equatable {
        let version: UInt8
        let catalogID: UUID
        var revision: UInt64
        let hostDeviceID: UUID
        let hostSigningPublicKey: Data
        var selectedPhoneID: UUID?
        var records: [RemotePairedDeviceRecord]
        var legacyImportReceipt: WorldwidePairedPhoneLegacyReceipt?

        var snapshot: WorldwidePairedPhoneCatalogSnapshot {
            WorldwidePairedPhoneCatalogSnapshot(
                token: WorldwidePairedPhoneCatalogToken(catalogID: catalogID, revision: revision),
                selectedPhoneID: selectedPhoneID,
                records: records,
                legacyImportReceipt: legacyImportReceipt
            )
        }
    }
}
