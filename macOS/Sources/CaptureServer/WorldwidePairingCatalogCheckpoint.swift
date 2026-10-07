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
    private var core: BelugaRustPairingCatalogCheckpointBoundary.State
    private var bridgeFaulted: Bool
    private let producer: BelugaRustPairingCatalogCheckpointProducer

    init(store: WorldwidePairingStore, identity: RemoteDeviceIdentity,
         snapshot: WorldwidePairedPhoneCatalogSnapshot,
         ownerIsValid: @escaping @Sendable () -> Bool,
         producer: BelugaRustPairingCatalogCheckpointProducer = .actual) {
        catalog = store.phoneCatalog
        self.identity = identity
        self.snapshot = snapshot
        self.ownerIsValid = ownerIsValid
        self.producer = producer
        let initial = producer.initial()
        core = initial
        bridgeFaulted = !BelugaRustPairingCatalogCheckpointBoundary.acceptsInitial(initial)
    }

    func revoke() {
        locked {
            // Even a malformed terminal proposal leaves a sticky write denial;
            // known snapshot/binding custody is never erased or reset.
            do { core = try proposal(opcode: 2, ownerValid: false) }
            catch { bridgeFaulted = true }
        }
    }

    func add(_ record: RemotePairedDeviceRecord) throws {
        try locked {
            try validateStoredState()
            let candidate = try proposal(opcode: 0, ownerValid: projectedOwner())
            let saved = try catalog.addPairedPhone(record, for: identity, expectedToken: snapshot.token)
            snapshot = saved
            binding = (record.remoteDeviceID, record.pairID, record.commitID)
            core = candidate
        }
    }

    func update(_ record: RemotePairedDeviceRecord) throws {
        try locked {
            try validateStoredState()
            let ownerValid = projectedOwner()
            let matches = binding.map {
                $0.deviceID == record.remoteDeviceID && $0.pairID == record.pairID
                    && $0.commitID == record.commitID
            } ?? false
            let candidate = try proposal(opcode: 1, ownerValid: ownerValid, bindingMatches: matches)
            let saved = try catalog.updatePairedPhone(record, for: identity, expectedToken: snapshot.token)
            snapshot = saved
            core = candidate
        }
    }

    /// Reads only this attempt's exact pair, never the selected/pre-existing phone.
    /// May be used after revoke for interrupted-commit recovery; fresh durable bytes and
    /// the entire revision still have to match this cursor's last successful checkpoint.
    func readback() throws -> (snapshot: WorldwidePairedPhoneCatalogSnapshot,
                              record: RemotePairedDeviceRecord?) {
        try locked {
            let fresh = try catalog.loadOrMigrate(for: identity)
            _ = try proposal(opcode: 3, ownerValid: false, snapshotMatches: fresh == snapshot)
            let record = binding.flatMap { binding in
                fresh.records.first {
                    $0.remoteDeviceID == binding.deviceID && $0.pairID == binding.pairID &&
                        $0.commitID == binding.commitID
                }
            }
            return (fresh, record)
        }
    }

    /// Preserve the original callback short circuit: revoked attempts never call
    /// the owner, but an already-bound Add still does. This projects a native fact;
    /// it does not manufacture an admitted Rust successor.
    private func projectedOwner() -> Bool {
        core.flags & 2 == 0 ? ownerIsValid() : false
    }

    private func validateStoredState() throws {
        guard !bridgeFaulted,
              BelugaRustPairingCatalogCheckpointBoundary.valid(core, bindingPresent: binding != nil) else {
            bridgeFaulted = true
            throw WorldwidePhoneCatalogRuntimeError.invalidCheckpointBridge
        }
    }

    private func proposal(opcode: UInt32, ownerValid: Bool, bindingMatches: Bool = false,
                          snapshotMatches: Bool = false) throws -> BelugaRustPairingCatalogCheckpointBoundary.State {
        try validateStoredState()
        var event = BelugaRustPairingCatalogCheckpointBoundary.Event()
        event.opcode = opcode
        event.owner_valid = ownerValid ? 1 : 0
        event.binding_matches = bindingMatches ? 1 : 0
        event.snapshot_matches = snapshotMatches ? 1 : 0
        let output = producer.step(1, core, event)
        guard BelugaRustPairingCatalogCheckpointBoundary.accepts(before: core, event: event, output: output) else {
            bridgeFaulted = true
            throw WorldwidePhoneCatalogRuntimeError.invalidCheckpointBridge
        }
        guard output.decision == 0 else { throw WorldwidePhoneCatalogRuntimeError.staleAttempt }
        return output.candidate_state
    }

    /// Read-only actual stored copied state; no UUID, credential or mutation handle.
    var copiedStateForTesting: BelugaRustPairingCatalogCheckpointBoundary.State { locked { core } }
    var bridgeFaultedForTesting: Bool { locked { bridgeFaulted } }

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
    case invalidCheckpointBridge
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
