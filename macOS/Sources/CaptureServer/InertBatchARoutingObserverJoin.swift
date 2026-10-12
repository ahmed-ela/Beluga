// PRIVATE UNCOMPILED DEBUG CUSTODY ONLY. Not a policy, authorization, or scheduler.
#if DEBUG
import Foundation

final class InertBatchARoutingObserverJoin: @unchecked Sendable {
    enum Kind: String, Hashable, Sendable {
        case inventoryObservation
        case inputUncertainty
        case safeOutputUncertainty
        case inventoryUncertainty
    }
    struct Snapshot: Sendable {
        let retainedHandleCount: Int
        let totalRetainedByKind: [String: Int]
        let totalJoinedByKind: [String: Int]
    }
    private final class Entry: @unchecked Sendable {
        let token: UUID
        let task: Task<Void, Never>
        let kind: Kind
        init(token: UUID, task: Task<Void, Never>, kind: Kind) {
            self.token = token; self.task = task; self.kind = kind
        }
    }
    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var retainedByKind: [String: Int] = [:]
    private var joinedByKind: [String: Int] = [:]
    private var isJoining = false

    /// Receives the exact Task created by the actual callback, synchronously
    /// before that callback returns. Even already-completed tasks stay joinable.
    func retain(_ task: Task<Void, Never>, kind: Kind) {
        lock.withLock {
            var token = UUID()
            while entries[token] != nil { token = UUID() }
            entries[token] = .init(token: token, task: task, kind: kind)
            retainedByKind[kind.rawValue, default: 0] += 1
        }
    }

    /// Never holds a lock or the actor executor while waiting on an exact Task.
    /// Callback-created successors are joined too; this inert HAL produces only
    /// finite initial/owned-CAS callbacks, not a continuous live event source.
    func drainAllRetainedTasks() async {
        lock.withLock {
            precondition(!isJoining, "One inert observer join owner")
            isJoining = true
        }
        defer { lock.withLock { isJoining = false } }
        while true {
            let batch = lock.withLock { Array(entries.values) }
            guard !batch.isEmpty else { return }
            for entry in batch {
                await entry.task.value
                lock.withLock {
                    precondition(entries[entry.token] === entry,
                                 "Exact retained token/handle cannot be replaced")
                    entries.removeValue(forKey: entry.token)
                    joinedByKind[entry.kind.rawValue, default: 0] += 1
                }
            }
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            .init(retainedHandleCount: entries.count,
                  totalRetainedByKind: retainedByKind,
                  totalJoinedByKind: joinedByKind)
        }
    }
}
#endif
