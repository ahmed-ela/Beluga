import Foundation
import RemoteSessionCore

protocol ViewerPairedMacCatalogStoring: ViewerPairingStoring {
    func saveBootstrapPair(_ record: RemotePairedDeviceRecord, invitationCode: String,
                           for identity: RemoteDeviceIdentity) throws
    func recoveryInvitationMatches(_ invitationCode: String, record: RemotePairedDeviceRecord,
                                   for identity: RemoteDeviceIdentity) throws -> Bool
    func loadSavedMacs(for identity: RemoteDeviceIdentity) throws -> [RemotePairedDeviceRecord]
    func selectMac(_ deviceID: UUID?, for identity: RemoteDeviceIdentity) throws
    func forgetMac(_ deviceID: UUID, for identity: RemoteDeviceIdentity) throws
}

protocol ViewerPairedMacCatalogDataStoring {
    func loadData() throws -> Data?
    func saveData(_ data: Data) throws
}

extension KeychainStore: ViewerPairedMacCatalogDataStoring {}

/// One atomically replaced Keychain item owns all pairs and the selected Mac. The existing
/// namespace selector still owns the unchanged iPhone identity and validates legacy migration.
final class ViewerPairedMacCatalogStore: ViewerPairedMacCatalogStoring {
    static let maximumMacCount = 32
    private struct InvitationBinding: Codable {
        let pairID: UUID
        let digest: Data
    }
    private struct Catalog: Codable {
        var version = 1
        let viewerDeviceID: UUID
        let viewerSigningPublicKey: Data
        var selectedMacID: UUID?
        var records: [RemotePairedDeviceRecord]
        var invitationBindings: [String: InvitationBinding]?
    }

    private let compatibilityStore: any ViewerPairingStoring
    private let dataStore: any ViewerPairedMacCatalogDataStoring

    init(
        compatibilityStore: any ViewerPairingStoring = ViewerPairingNamespaceSelectorStore(),
        dataStore: any ViewerPairedMacCatalogDataStoring = KeychainStore(item: .init(
            service: "org.example.AudioStreamer", account: "worldwide-paired-macs-catalog"
        ))
    ) {
        self.compatibilityStore = compatibilityStore
        self.dataStore = dataStore
    }

    func loadOrCreateViewerIdentity() throws -> RemoteDeviceIdentity {
        if try dataStore.loadData() != nil,
           let reader = compatibilityStore as? any ViewerPairingIdentityReading {
            guard let identity = try reader.loadExistingViewerIdentity() else {
                throw ViewerPairingStoreError.identityPersistenceFailed
            }
            return identity
        }
        return try compatibilityStore.loadOrCreateViewerIdentity()
    }

    func loadSavedMacs(for identity: RemoteDeviceIdentity) throws -> [RemotePairedDeviceRecord] {
        try loadCatalog(for: identity).records
    }

    func loadPairedMac(for identity: RemoteDeviceIdentity) throws -> RemotePairedDeviceRecord? {
        let catalog = try loadCatalog(for: identity)
        return catalog.records.first { $0.remoteDeviceID == catalog.selectedMacID }
    }

    func savePairedMac(_ record: RemotePairedDeviceRecord, for identity: RemoteDeviceIdentity) throws {
        try savePair(record, invitationCode: nil, for: identity)
    }

    func saveBootstrapPair(_ record: RemotePairedDeviceRecord, invitationCode: String,
                           for identity: RemoteDeviceIdentity) throws {
        try savePair(record, invitationCode: invitationCode, for: identity)
    }

    func recoveryInvitationMatches(_ invitationCode: String, record: RemotePairedDeviceRecord,
                                   for identity: RemoteDeviceIdentity) throws -> Bool {
        let catalog = try loadCatalog(for: identity)
        guard catalog.selectedMacID == record.remoteDeviceID,
              catalog.records.contains(record),
              let binding = catalog.invitationBindings?[record.remoteDeviceID.uuidString],
              binding.pairID == record.pairID else { return false }
        return binding.digest == (try WorldwideInvitationAdmissionKeychainStore.digest(for: invitationCode))
    }

    private func savePair(_ record: RemotePairedDeviceRecord, invitationCode: String?,
                          for identity: RemoteDeviceIdentity) throws {
        try ViewerPairingKeychainStore.validateRecord(record, for: identity)
        var catalog = try loadCatalog(for: identity)
        if let index = catalog.records.firstIndex(where: { $0.remoteDeviceID == record.remoteDeviceID }) {
            // An authenticated re-pair may replace this Mac's pair, never another Mac's identity.
            catalog.records[index] = record
        } else {
            guard catalog.records.count < Self.maximumMacCount else {
                throw ViewerPairedMacCatalogError.capacityReached
            }
            catalog.records.append(record)
        }
        catalog.selectedMacID = record.remoteDeviceID
        var bindings = catalog.invitationBindings ?? [:]
        let key = record.remoteDeviceID.uuidString
        if let invitationCode {
            bindings[key] = InvitationBinding(pairID: record.pairID,
                digest: try WorldwideInvitationAdmissionKeychainStore.digest(for: invitationCode))
        } else if bindings[key]?.pairID != record.pairID {
            bindings.removeValue(forKey: key)
        }
        catalog.invitationBindings = bindings
        try save(catalog)
    }

    func selectMac(_ deviceID: UUID?, for identity: RemoteDeviceIdentity) throws {
        var catalog = try loadCatalog(for: identity)
        if let deviceID, !catalog.records.contains(where: { $0.remoteDeviceID == deviceID }) {
            throw ViewerPairedMacCatalogError.unknownMac
        }
        catalog.selectedMacID = deviceID
        try save(catalog)
    }

    func forgetMac(_ deviceID: UUID, for identity: RemoteDeviceIdentity) throws {
        var catalog = try loadCatalog(for: identity)
        guard catalog.records.contains(where: { $0.remoteDeviceID == deviceID }) else {
            throw ViewerPairedMacCatalogError.unknownMac
        }
        // Remove an old compatibility copy only when it is the exact explicitly forgotten Mac.
        if try compatibilityStore.loadPairedMac(for: identity)?.remoteDeviceID == deviceID {
            try compatibilityStore.deletePairedMac()
        }
        catalog.records.removeAll { $0.remoteDeviceID == deviceID }
        catalog.invitationBindings?.removeValue(forKey: deviceID.uuidString)
        if catalog.selectedMacID == deviceID { catalog.selectedMacID = nil }
        try save(catalog)
    }

    func deletePairedMac() throws {
        let identity = try loadOrCreateViewerIdentity()
        guard let record = try loadPairedMac(for: identity) else { return }
        try forgetMac(record.remoteDeviceID, for: identity)
    }

    private func loadCatalog(for identity: RemoteDeviceIdentity) throws -> Catalog {
        guard try loadOrCreateViewerIdentity() == identity else {
            throw ViewerPairingStoreError.viewerIdentityConflict
        }
        if let data = try dataStore.loadData() {
            guard data.count <= 256 * 1024,
                  let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
                  catalog.version == 1,
                  catalog.viewerDeviceID == identity.deviceID,
                  catalog.viewerSigningPublicKey == identity.signingPublicKey,
                  catalog.records.count <= Self.maximumMacCount,
                  Set(catalog.records.map(\.remoteDeviceID)).count == catalog.records.count,
                  catalog.selectedMacID == nil || catalog.records.contains(where: {
                      $0.remoteDeviceID == catalog.selectedMacID
                  }) else { throw ViewerPairedMacCatalogError.invalidCatalog }
            for record in catalog.records { try ViewerPairingKeychainStore.validateRecord(record, for: identity) }
            for (key, binding) in catalog.invitationBindings ?? [:] {
                guard binding.digest.count == 32,
                      catalog.records.contains(where: {
                          $0.remoteDeviceID.uuidString == key && $0.pairID == binding.pairID
                      }) else { throw ViewerPairedMacCatalogError.invalidCatalog }
            }
            return catalog
        }
        let existing = try compatibilityStore.loadPairedMac(for: identity)
        let catalog = Catalog(viewerDeviceID: identity.deviceID,
                              viewerSigningPublicKey: identity.signingPublicKey,
                              selectedMacID: existing?.remoteDeviceID,
                              records: existing.map { [$0] } ?? [])
        if let existing { try ViewerPairingKeychainStore.validateRecord(existing, for: identity) }
        try save(catalog)
        return catalog
    }

    private func save(_ catalog: Catalog) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try dataStore.saveData(encoder.encode(catalog))
    }
}

enum ViewerPairedMacCatalogError: Error, Equatable {
    case invalidCatalog
    case unknownMac
    case capacityReached
}
