import Foundation

/// Acquires the ordinary host lease before reading a replacement target's durable fence.
/// The same returned lease must remain retained through all native runtime teardown.
package enum BelugaUpdateRuntimeAdmission {
    package static func validateTarget(_ context: BelugaUpdateRuntimeContext) throws {
        try context.revalidate()
        let store = try BelugaUpdateFenceStore(directoryURL: context.fenceDirectoryURL)
        guard try store.read(expectedTarget: context.target) == nil else {
            throw Failure.unresolvedUpdate
        }
    }

    package static func acquire(
        requiresExclusiveOwnership: Bool,
        validateUpdateTarget: (() throws -> Void)?,
        acquireOwnership: () throws -> WorldwideHostProcessLock = {
            try WorldwideHostProcessLock.acquire()
        }
    ) throws -> WorldwideHostProcessLock? {
        // Unbundled nonexclusive diagnostic/development modes keep existing behavior.
        // Every app replacement target, including its direct LAN CLI, requires ownership.
        guard requiresExclusiveOwnership || validateUpdateTarget != nil else { return nil }
        let owner = try acquireOwnership()
        do {
            try validateUpdateTarget?()
            return owner
        } catch {
            // No runtime effect is permitted before this check; rejected admission need
            // not strand an otherwise idle host lease. It never clears the durable fence.
            owner.release()
            throw error
        }
    }

    package enum Failure: LocalizedError {
        case unresolvedUpdate

        package var errorDescription: String? {
            "A Beluga update is unresolved. Complete update recovery before starting this app's streaming runtime."
        }
    }
}
