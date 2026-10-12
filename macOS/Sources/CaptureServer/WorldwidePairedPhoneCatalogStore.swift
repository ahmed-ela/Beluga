import CryptoKit
import Foundation
import RemoteSessionCore

/// A durable generation and revision, not a cross-process compare-and-swap capability.
struct WorldwidePairedPhoneCatalogToken: Equatable, Sendable {
    let catalogID: UUID
    let revision: UInt64
}

/// Proof of the exact legacy bytes imported once; retained even after that phone is forgotten.
struct WorldwidePairedPhoneLegacyReceipt: Codable, Equatable, Sendable {
    let sourceAccount: String
    let sourceSHA256: Data
    let remoteDeviceID: UUID
    let pairID: UUID
    let commitID: UUID
}

/// A value snapshot. Callers must fence asynchronous runtime work with this token and the
/// selected binding; persistence does not disconnect or authorize a live connection.
struct WorldwidePairedPhoneCatalogSnapshot: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    let token: WorldwidePairedPhoneCatalogToken
    let selectedPhoneID: UUID?
    let records: [RemotePairedDeviceRecord]
    let legacyImportReceipt: WorldwidePairedPhoneLegacyReceipt?

    var selectedRecord: RemotePairedDeviceRecord? {
        records.first { $0.remoteDeviceID == selectedPhoneID }
    }

    var description: String { "WorldwidePairedPhoneCatalogSnapshot(<redacted>)" }
    var debugDescription: String { description }
}

/// One bounded, atomic Keychain item containing independent phone bindings for this host.
///
/// All instances serialize read/check/write inside this process. The underlying backend has
/// item replacement, not cross-process CAS: the host's existing single-process owner boundary
/// is still required. No operation rewrites identity or the legacy single-viewer item. Once the
/// catalog exists, even an empty catalog is authoritative and legacy fallback is forbidden.
struct WorldwidePairedPhoneCatalogStore: Sendable {
    static let catalogAccount = "worldwide-paired-phones-catalog-v1"
    static let maximumPhoneCount = 8
    static let maximumCatalogBytes = WorldwideKeychainDataStore.maximumItemBytes

    private static let serializationLock = NSLock()
    private let dataStore: any WorldwidePairingDataStore
    private let pairedRecordDecodeFault: UInt32?
    private let policy: BelugaRustPhoneCatalog

    init(dataStore: any WorldwidePairingDataStore, pairedRecordDecodeFault: UInt32? = nil,
         resultMutation: BelugaRustPhoneCatalog.ResultMutation? = nil) {
        self.dataStore = dataStore
        self.pairedRecordDecodeFault = pairedRecordDecodeFault
        self.policy = BelugaRustPhoneCatalog(resultMutation: resultMutation)
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
        try mutate(for: identity, expectedToken: expectedToken, operation: .add(record))
    }

    /// Advances only an existing exact binding. Old asynchronous completions cannot reinsert a
    /// forgotten phone, replace immutable keys, regress replay counters, or change selection.
    @discardableResult
    func updatePairedPhone(
        _ record: RemotePairedDeviceRecord,
        for identity: RemoteDeviceIdentity,
        expectedToken: WorldwidePairedPhoneCatalogToken
    ) throws -> WorldwidePairedPhoneCatalogSnapshot {
        try mutate(for: identity, expectedToken: expectedToken, operation: .update(record))
    }

    /// Selection is explicit. Passing nil disconnects durable selection without forgetting keys.
    @discardableResult
    func selectPhone(
        _ remoteDeviceID: UUID?,
        for identity: RemoteDeviceIdentity,
        expectedToken: WorldwidePairedPhoneCatalogToken
    ) throws -> WorldwidePairedPhoneCatalogSnapshot {
        try mutate(for: identity, expectedToken: expectedToken, operation: .select(remoteDeviceID))
    }

    /// Removes only this binding, never chooses a replacement, and preserves migration proof.
    @discardableResult
    func forgetPhone(
        _ remoteDeviceID: UUID,
        for identity: RemoteDeviceIdentity,
        expectedToken: WorldwidePairedPhoneCatalogToken
    ) throws -> WorldwidePairedPhoneCatalogSnapshot {
        try mutate(for: identity, expectedToken: expectedToken, operation: .forget(remoteDeviceID))
    }

    private func mutate(
        for identity: RemoteDeviceIdentity,
        expectedToken: WorldwidePairedPhoneCatalogToken,
        operation: Mutation
    ) throws -> WorldwidePairedPhoneCatalogSnapshot {
        try serialized {
            try validatePersistedIdentity(identity)
            let loaded = try loadCatalog(for: identity)
            var token = BelugaRustPhoneCatalog.input(3, operation: operation.opcode)
            token.flags = Self.flag(loaded != nil)
                | (Self.flag(loaded?.snapshot.token == expectedToken) << 1)
            _ = try policy.checked(token)
            guard let previous = loaded else { throw WorldwidePairedPhoneCatalogError.invalidCatalog }

            let (target, candidate) = try admit(operation, in: previous, for: identity)
            var planInput = BelugaRustPhoneCatalog.input(10, operation: operation.opcode)
            planInput.count = UInt32(previous.records.count)
            planInput.selected_slot = slot(of: previous.selectedPhoneID, in: previous)
            planInput.target_slot = target
            let plan = try policy.checked(planInput)
            guard plan.action == 1 else { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
            let temporary = try custody(previous, candidate: candidate, plan: plan,
                                        revision: previous.revision)

            var finish = planInput
            finish.stage = 11
            finish.revision = previous.revision
            finish.flags = Self.flag(temporary == previous)
            let result = try policy.checked(finish)
            let proposed = try custody(previous, candidate: candidate, plan: result,
                                       revision: result.revision)
            guard proposed.records == temporary.records,
                  proposed.selectedPhoneID == temporary.selectedPhoneID,
                  proposed.legacyImportReceipt == previous.legacyImportReceipt,
                  proposed.catalogID == previous.catalogID,
                  proposed.hostDeviceID == previous.hostDeviceID,
                  proposed.hostSigningPublicKey == previous.hostSigningPublicKey,
                  proposed.version == previous.version else {
                throw WorldwidePairedPhoneCatalogError.invalidCatalog
            }
            switch result.action {
            case 2:
                guard proposed == previous else { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
                return previous.snapshot
            case 3:
                guard proposed != previous else { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
                try persist(proposed, for: identity)
                return proposed.snapshot
            default: throw WorldwidePairedPhoneCatalogError.invalidCatalog
            }
        }
    }

    private enum Mutation {
        case add(RemotePairedDeviceRecord)
        case update(RemotePairedDeviceRecord)
        case select(UUID?)
        case forget(UUID)

        var opcode: UInt32 {
            switch self {
            case .add: 1
            case .update: 2
            case .select: 3
            case .forget: 4
            }
        }
    }

    private static func flag(_ value: Bool) -> UInt32 { value ? 1 : 0 }

    private func slot(of deviceID: UUID?, in catalog: Catalog) -> UInt32 {
        guard let deviceID,
              let index = catalog.records.firstIndex(where: { $0.remoteDeviceID == deviceID }) else {
            return 8
        }
        return UInt32(index)
    }

    /// Each opaque native cut is delayed until its preceding Rust decision passed.
    private func admit(
        _ operation: Mutation, in catalog: Catalog, for identity: RemoteDeviceIdentity
    ) throws -> (UInt32, RemotePairedDeviceRecord?) {
        switch operation {
        case let .add(record):
            try validateRecord(record, for: identity)
            var input = BelugaRustPhoneCatalog.input(4, operation: 1)
            input.count = UInt32(catalog.records.count)
            for previous in catalog.records {
                input.duplicate_axes |= duplicateAxes(record, previous)
            }
            _ = try policy.checked(input)
            return (8, record)
        case let .update(record):
            try validateRecord(record, for: identity)
            let target = slot(of: record.remoteDeviceID, in: catalog)
            var lookup = BelugaRustPhoneCatalog.input(5, operation: 2)
            lookup.count = UInt32(catalog.records.count)
            lookup.target_slot = target
            _ = try policy.checked(lookup)
            guard Int(target) < catalog.records.count else {
                throw WorldwidePairedPhoneCatalogError.invalidCatalog
            }
            let previous = catalog.records[Int(target)]
            let bindingEqual = try immutableBinding(of: previous) == immutableBinding(of: record)
            var monotonic = BelugaRustPhoneCatalog.input(6, operation: 2)
            monotonic.flags = Self.flag(bindingEqual)
            monotonic.previous_phase = phaseTag(previous.pairingState)
            monotonic.candidate_phase = phaseTag(record.pairingState)
            monotonic.previous_outbound = previous.nextOutboundReconnectSequence
            monotonic.candidate_outbound = record.nextOutboundReconnectSequence
            monotonic.previous_accepted = previous.highestAcceptedReconnectSequence
            monotonic.candidate_accepted = record.highestAcceptedReconnectSequence
            _ = try policy.checked(monotonic)

            let previousRecovery = previous.recoveryAction
            let candidateRecovery = record.recoveryAction
            var recovery = BelugaRustPhoneCatalog.input(7, operation: 2)
            recovery.previous_phase = monotonic.previous_phase
            recovery.candidate_phase = monotonic.candidate_phase
            recovery.previous_recovery = recoveryTag(previousRecovery)
            recovery.candidate_recovery = recoveryTag(candidateRecovery)
            if case let .resend(commit) = previousRecovery {
                recovery.flags = Self.flag(candidateRecovery == .resend(commit))
            }
            _ = try policy.checked(recovery)
            return (target, record)
        case let .select(deviceID):
            let target = slot(of: deviceID, in: catalog)
            var input = BelugaRustPhoneCatalog.input(8, operation: 3)
            input.count = UInt32(catalog.records.count)
            input.target_slot = target
            input.flags = Self.flag(deviceID == nil)
            _ = try policy.checked(input)
            return (target, nil)
        case let .forget(deviceID):
            let target = slot(of: deviceID, in: catalog)
            var input = BelugaRustPhoneCatalog.input(9, operation: 4)
            input.count = UInt32(catalog.records.count)
            input.target_slot = target
            _ = try policy.checked(input)
            return (target, nil)
        }
    }

    /// Materialize only a verified full recipe, retaining exact native record/receipt custody.
    private func custody(
        _ previous: Catalog, candidate: RemotePairedDeviceRecord?,
        plan: BelugaRustPhoneCatalog.Result, revision: UInt64
    ) throws -> Catalog {
        guard plan.count <= 8 else { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
        let slots = BelugaRustPhoneCatalog.slots(plan)
        var records: [RemotePairedDeviceRecord] = []
        for index in 0..<Int(plan.count) {
            let source = slots[index]
            if source == 8 {
                guard let candidate else { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
                records.append(candidate)
            } else {
                guard Int(source) < previous.records.count else {
                    throw WorldwidePairedPhoneCatalogError.invalidCatalog
                }
                records.append(previous.records[Int(source)])
            }
        }
        guard slots.dropFirst(Int(plan.count)).allSatisfy({ $0 == 9 }),
              plan.selected_slot == 8 || Int(plan.selected_slot) < records.count else {
            throw WorldwidePairedPhoneCatalogError.invalidCatalog
        }
        var result = previous
        result.records = records
        result.selectedPhoneID = plan.selected_slot == 8 ? nil
            : records[Int(plan.selected_slot)].remoteDeviceID
        result.revision = revision
        return result
    }

    private func duplicateAxes(_ lhs: RemotePairedDeviceRecord, _ rhs: RemotePairedDeviceRecord) -> UInt32 {
        Self.flag(lhs.remoteDeviceID == rhs.remoteDeviceID)
            | (Self.flag(lhs.remoteSigningPublicKey == rhs.remoteSigningPublicKey) << 1)
            | (Self.flag(lhs.pairID == rhs.pairID) << 2)
            | (Self.flag(lhs.commitID == rhs.commitID) << 3)
    }

    private func phaseTag(_ state: RemotePairingPersistenceState) -> UInt32 {
        switch state {
        case .pending: 0
        case .acceptedReceived: 1
        case .active: 2
        case .acceptedIssued: 3
        }
    }

    private func recoveryTag(_ action: RemotePairingRecoveryAction) -> UInt32 {
        switch action {
        case .none: 0
        case .resend: 1
        case .invalidBridge: 3
        case .awaitProposal, .issueProposal, .issueCompletion: 2
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
        var header = BelugaRustPhoneCatalog.input(0)
        header.flags = Self.flag(catalog.version == 1 && catalog.catalogID != Self.zeroUUID
            && catalog.revision > 0)
            | (Self.flag(catalog.hostDeviceID == identity.deviceID
                && catalog.hostSigningPublicKey == identity.signingPublicKey) << 1)
        header.count = UInt32(min(catalog.records.count, 9))
        _ = try policy.checked(header)
        var deviceIDs = Set<UUID>()
        var signingKeys = Set<Data>()
        var pairIDs = Set<UUID>()
        var commitIDs = Set<UUID>()
        for record in catalog.records {
            try validateRecord(record, for: identity)
            var uniqueness = BelugaRustPhoneCatalog.input(1)
            uniqueness.duplicate_axes = Self.flag(deviceIDs.contains(record.remoteDeviceID))
                | (Self.flag(signingKeys.contains(record.remoteSigningPublicKey)) << 1)
                | (Self.flag(pairIDs.contains(record.pairID)) << 2)
                | (Self.flag(commitIDs.contains(record.commitID)) << 3)
            _ = try policy.checked(uniqueness)
            deviceIDs.insert(record.remoteDeviceID)
            signingKeys.insert(record.remoteSigningPublicKey)
            pairIDs.insert(record.pairID)
            commitIDs.insert(record.commitID)
        }
        let selectionValid = catalog.selectedPhoneID.map { deviceIDs.contains($0) } ?? true
        var receiptValid = true
        if let receipt = catalog.legacyImportReceipt {
            receiptValid = receipt.sourceAccount == WorldwidePairingStore.pairedViewerAccount
                && receipt.sourceSHA256.count == SHA256.Digest.byteCount
                && receipt.remoteDeviceID != Self.zeroUUID
                && receipt.pairID != Self.zeroUUID && receipt.commitID != Self.zeroUUID
        }
        var trailer = BelugaRustPhoneCatalog.input(2)
        trailer.flags = Self.flag(selectionValid) | (Self.flag(receiptValid) << 1)
        _ = try policy.checked(trailer)
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

enum WorldwidePairedPhoneCatalogError: LocalizedError, Equatable {
    case invalidCatalog
    case identityMismatch
    case duplicatePhone
    case unknownPhone
    case capacityReached
    case oversizedCatalog
    case staleCatalog
    case staleRecord
    case bindingConflict
    case revisionExhausted
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: "The saved paired-phone catalog is invalid."
        case .identityMismatch: "The paired-phone catalog does not match this saved Mac identity."
        case .duplicatePhone: "This phone or pairing identity is already saved."
        case .unknownPhone: "This phone is no longer in the saved catalog."
        case .capacityReached: "The saved-phone limit has been reached; explicitly forget a phone first."
        case .oversizedCatalog: "The paired-phone catalog exceeds the existing secure-storage limit."
        case .staleCatalog: "The paired-phone catalog changed; reload before changing it."
        case .staleRecord: "A stale pairing state or reconnect counter cannot replace the saved state."
        case .bindingConflict: "A new pairing cannot silently replace this phone's saved binding."
        case .revisionExhausted: "The paired-phone catalog revision cannot advance safely."
        case .encodingFailed: "The paired-phone catalog could not be encoded."
        }
    }
}
