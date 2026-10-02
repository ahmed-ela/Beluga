import Foundation
import RemoteSessionCore

/// One explicit bootstrap attempt, with one add and only exact updates afterward.
/// This cursor is revoked synchronously before transport teardown. The host's retained
/// process owner is still required: the backing catalog is not a cross-process CAS.
final class WorldwidePairingCatalogCheckpoint: @unchecked Sendable {
    let attemptID = UUID()
    private let lock = NSLock()
    private let catalog: WorldwidePairedPhoneCatalogStore
    private let identity: RemoteDeviceIdentity
    private let ownerIsValid: @Sendable () -> Bool
    private var snapshot: WorldwidePairedPhoneCatalogSnapshot
    private var binding: (deviceID: UUID, pairID: UUID, commitID: UUID)?
    private var revoked = false

    init(store: WorldwidePairingStore, identity: RemoteDeviceIdentity,
         snapshot: WorldwidePairedPhoneCatalogSnapshot,
         ownerIsValid: @escaping @Sendable () -> Bool) {
        catalog = store.phoneCatalog
        self.identity = identity
        self.snapshot = snapshot
        self.ownerIsValid = ownerIsValid
    }

    func revoke() {
        lock.lock()
        revoked = true
        lock.unlock()
    }

    func add(_ record: RemotePairedDeviceRecord) throws {
        try locked {
            guard !revoked, ownerIsValid(), binding == nil else { throw WorldwidePhoneCatalogRuntimeError.staleAttempt }
            snapshot = try catalog.addPairedPhone(record, for: identity, expectedToken: snapshot.token)
            binding = (record.remoteDeviceID, record.pairID, record.commitID)
        }
    }

    func update(_ record: RemotePairedDeviceRecord) throws {
        try locked {
            guard !revoked, ownerIsValid(), let binding,
                  binding.deviceID == record.remoteDeviceID,
                  binding.pairID == record.pairID, binding.commitID == record.commitID else {
                throw WorldwidePhoneCatalogRuntimeError.staleAttempt
            }
            snapshot = try catalog.updatePairedPhone(record, for: identity, expectedToken: snapshot.token)
        }
    }

    /// Reads only this attempt's exact pair, never the selected/pre-existing phone.
    /// May be used after revoke for interrupted-commit recovery; fresh durable bytes and
    /// the entire revision still have to match this cursor's last successful checkpoint.
    func readback() throws -> (snapshot: WorldwidePairedPhoneCatalogSnapshot,
                              record: RemotePairedDeviceRecord?) {
        try locked {
            let fresh = try catalog.loadOrMigrate(for: identity)
            guard fresh == snapshot else { throw WorldwidePhoneCatalogRuntimeError.staleAttempt }
            let record = binding.flatMap { binding in
                fresh.records.first {
                    $0.remoteDeviceID == binding.deviceID && $0.pairID == binding.pairID &&
                        $0.commitID == binding.commitID
                }
            }
            return (fresh, record)
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// A caller must return this exact token/epoch at a newly admitted quiet boundary.
/// It contains no pairing keys or invitation capability.
struct WorldwidePhoneCatalogAction: Equatable, Sendable {
    let token: WorldwidePairedPhoneCatalogToken
    let selectionEpoch: UUID
}

enum WorldwidePhoneCatalogRuntimeError: Error, Equatable {
    case staleAttempt
    case notQuiet
    case ownerNotAuthorized
    case staleSelection
}

/// Protocol quiescence and native-media ownership are independent. A genuine last waiting /
/// peer-left boundary may survive exact media teardown; any newer ready clears that proof.
func worldwidePhoneCatalogHasQuietBoundary(validatedWaiting: Bool, activeExchangeID: String?,
                                          mediaExchangeID: String?, hasMediaOwner: Bool) -> Bool {
    validatedWaiting && activeExchangeID == nil && mediaExchangeID == nil && !hasMediaOwner
}
