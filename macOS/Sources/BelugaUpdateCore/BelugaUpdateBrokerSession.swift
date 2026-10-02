import Foundation

/// One updater cycle's real lease and durable marker. Proof callbacks must perform the
/// caller's supported-installer, signature/readback and authenticated-IPC verification;
/// this component does not authenticate the supplied values or invoke Sparkle itself.
package final class BelugaUpdateBrokerSession {
    package enum State: Equatable { case unprepared, prepared, started, failed, cleared }
    package enum Failure: Error, Equatable {
        case reentrantCall, inactiveSession, unexpectedBinding, invalidTransition
        case updaterAlreadyStarted, authorizationDenied, unresolvedFence
        case controlledHistoryNotAdmitted, invalidUnarmedCompletion, predecessorChanged
        case brokerNotBound
    }

    private let serialization = NSRecursiveLock()
    private let reentrySerialization = NSLock()
    private let observationSerialization = NSLock()
    private let store: BelugaUpdateFenceStore
    private let acquireOwnership: () throws -> WorldwideHostProcessLock
    private var context: BelugaUpdateRuntimeContext
    private var owner: WorldwideHostProcessLock?
    private var operation: BelugaUpdateOperation?
    private var snapshot: BelugaUpdateFenceStore.Snapshot?
    private var completion: BelugaUpdateOperation.InstalledCompletion?
    private var readiness: BelugaUpdateOperation.MenuReadiness?
    private var controlledHistory: BelugaUpdateControlledHistoryAdmission?
    private var currentState: State = .unprepared
    private var updaterWasStarted = false
    private var busy = false
    private var reentryObserved = false
    private var published = Observation(state: .unprepared, ownsLease: false,
                                        operationID: nil, recordSHA256: nil)

    /// Source-only deterministic seam, after actual successful clearance and lease release.
    var afterClearedCommitForTesting: (() -> Void)?

    private struct Observation {
        let state: State
        let ownsLease: Bool
        let operationID: UUID?
        let recordSHA256: String?
    }

    package init(
        context: BelugaUpdateRuntimeContext,
        acquireOwnership: @escaping () throws -> WorldwideHostProcessLock = {
            try WorldwideHostProcessLock.acquire()
        }
    ) throws {
        self.context = context
        store = try BelugaUpdateFenceStore(directoryURL: context.fenceDirectoryURL)
        self.acquireOwnership = acquireOwnership
    }

    deinit { owner?.release() } // Lease loss never clears the persistent marker.

    package var state: State { observed { $0.state } }
    package var ownsLease: Bool { observed { $0.ownsLease } }
    package var operationID: UUID? { observed { $0.operationID } }
    package var recordSHA256: String? { observed { $0.recordSHA256 } }

    /// No verifier, target/storage read or namespace provisioning runs before the
    /// existing shared host lock has been acquired.
    package func prepare(
        operationID: UUID, predecessorMenuInstanceID: UUID,
        controlledHistory: BelugaUpdateControlledHistoryAdmission? = nil,
        verifyPredecessor: (BelugaUpdateOperation.Target) throws -> BelugaUpdateOperation.ArtifactIdentity
    ) throws {
        try guarded {
            guard currentState == .unprepared else { throw Failure.invalidTransition }
            owner = try acquireOwnership()
            publish()
            try rejectReentry()
            try context.revalidate()
            guard try store.read(expectedTarget: context.target) == nil else {
                throw Failure.unresolvedFence
            }
            let predecessor = try verifyPredecessor(context.target)
            try rejectReentry()
            try controlledHistory?.revalidate(operationID: operationID, target: context.target,
                                              predecessor: predecessor)
            try rejectReentry()
            try context.revalidate()
            guard try store.read(expectedTarget: context.target) == nil else {
                throw Failure.unresolvedFence
            }
            let prepared = try BelugaUpdateOperation(operationID: operationID,
                target: context.target, predecessor: predecessor,
                predecessorMenuInstanceID: predecessorMenuInstanceID)
            try BelugaUpdateNamespace.prepare(context: context)
            let persisted = try store.create(prepared)
            operation = prepared
            snapshot = persisted
            self.controlledHistory = controlledHistory
            currentState = .prepared
            publish()
        }
    }

    /// The attempt is consumed before invoking any SDK work, even if that closure throws.
    package func startUpdater(
        operationID: UUID, target: BelugaUpdateOperation.Target, _ start: () throws -> Void
    ) throws {
        try guarded {
            try requireBinding(operationID, target)
            guard !updaterWasStarted else { throw Failure.updaterAlreadyStarted }
            guard currentState == .prepared else { throw Failure.invalidTransition }
            try context.revalidate()
            try requireCurrent()
            let current = try requireOperation()
            guard current.brokerBinding != nil else { throw Failure.brokerNotBound }
            try controlledHistory?.revalidate(operationID: operationID, target: target,
                                              predecessor: current.predecessor)
            try rejectReentry()
            try context.revalidate()
            try requireCurrent()
            updaterWasStarted = true
            currentState = .started
            publish()
            try start()
            try rejectReentry()
            try context.revalidate()
            try requireCurrent()
        }
    }

    /// Bind the independently verified staged broker exactly once before SDK startup.
    package func bindBroker(_ binding: BelugaUpdateOperation.BrokerBinding,
                            operationID: UUID, target: BelugaUpdateOperation.Target) throws {
        try guarded {
            try requireBinding(operationID, target)
            guard currentState == .prepared, !updaterWasStarted else { throw Failure.invalidTransition }
            try context.revalidate()
            try requireCurrent()
            var next = try requireOperation()
            guard next.bindBroker(binding, operationID: operationID, target: target) else {
                throw Failure.invalidTransition
            }
            try persist(next)
        }
    }

    /// Only the still-live owner of a newly prepared operation may retire it without an
    /// installation. Unknown/restored history and SDK idleness alone never qualify.
    package func retirePreparedUnarmed(
        _ unarmed: BelugaUpdateUnarmedCompletion,
        verifyCompletion: (BelugaUpdateUnarmedCompletion) throws -> Void,
        verifyPredecessor: (BelugaUpdateOperation.Target) throws -> BelugaUpdateOperation.ArtifactIdentity
    ) throws {
        try guarded {
            guard let controlledHistory else { throw Failure.controlledHistoryNotAdmitted }
            let current = try requireOperation()
            try requireBinding(unarmed.operationID, current.target)
            guard currentState == .started, updaterWasStarted,
                  current.stage == .prepared, unarmed.reason.matches(candidate: current.candidate),
                  completion == nil, readiness == nil,
                  unarmed.cycleNonce != unarmed.operationID,
                  unarmed.cycleNonce != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                  let snapshot else { throw Failure.invalidUnarmedCompletion }
            try context.revalidate()
            try requireCurrent()
            try verifyCompletion(unarmed)
            try rejectReentry()
            try controlledHistory.revalidate(operationID: current.operationID, target: current.target,
                                              predecessor: current.predecessor)
            try rejectReentry()
            guard try verifyPredecessor(current.target) == current.predecessor else {
                throw Failure.predecessorChanged
            }
            try rejectReentry()
            // Native proof must still be current after lineage/signature work, which may
            // synchronously reenter its driver. No cached paired observation can clear.
            try verifyCompletion(unarmed)
            try rejectReentry()
            try context.revalidate()
            try requireCurrent()
            try store.retireFreshPrepared(current, expected: snapshot, reason: unarmed.reason)
            owner?.release()
            owner = nil
            currentState = .cleared
            publish()
            afterClearedCommitForTesting?()
        }
    }

    /// Candidate identity is supplied explicitly by the caller's artifact verifier.
    package func bindCandidate(
        _ candidate: BelugaUpdateOperation.ArtifactIdentity,
        operationID: UUID, target: BelugaUpdateOperation.Target
    ) throws {
        try guarded {
            try requireBinding(operationID, target)
            guard currentState == .prepared || currentState == .started else {
                throw Failure.invalidTransition
            }
            try context.revalidate()
            try requireCurrent()
            var next = try requireOperation()
            guard next.bindCandidate(candidate, operationID: operationID, target: target) else {
                throw Failure.invalidTransition
            }
            try persist(next)
        }
    }

    /// Wire to the public user-driver install authorization boundary. A repeated reply
    /// cannot bypass an exact current marker check; no candidate is inferred here.
    package func authorizeInstall(
        operationID: UUID, target: BelugaUpdateOperation.Target,
        authorize: () throws -> Bool
    ) throws -> Bool {
        try guarded {
            try requireBinding(operationID, target)
            guard currentState == .started else { throw Failure.invalidTransition }
            try context.revalidate()
            try requireCurrent()
            guard try authorize() else { throw Failure.authorizationDenied }
            try rejectReentry()
            try context.revalidate()
            try requireCurrent()
            var next = try requireOperation()
            if next.stage == .prepared {
                guard next.markPossiblyArmed(operationID: operationID, target: target) else {
                    throw Failure.invalidTransition
                }
            } else {
                guard next.stage == .possiblyArmed else { throw Failure.invalidTransition }
            }
            try persist(next)
            return true
        }
    }

    /// Replacement changes the app vnode. The verifier supplies a freshly resolved context
    /// for the same canonical target and namespace, not the predecessor's old inode.
    package func acceptInstalledCompletion(
        _ installed: BelugaUpdateOperation.InstalledCompletion,
        freshContext: BelugaUpdateRuntimeContext,
        verifyInstalled: (BelugaUpdateOperation.InstalledCompletion,
                          BelugaUpdateRuntimeContext) throws -> Void
    ) throws {
        try guarded {
            try requireBinding(installed.operationID, installed.target)
            guard currentState == .started, freshContext.target == context.target,
                  freshContext.fenceDirectoryURL == context.fenceDirectoryURL else {
                throw Failure.unexpectedBinding
            }
            try freshContext.revalidate()
            try requireCurrent()
            try verifyInstalled(installed, freshContext)
            try rejectReentry()
            try freshContext.revalidate()
            try requireCurrent()
            var next = try requireOperation()
            guard next.acceptInstalledCompletion(installed) else { throw Failure.invalidTransition }
            try persist(next)
            context = freshContext
            completion = installed
        }
    }

    package func issueReadinessChallenge(
        operationID: UUID, target: BelugaUpdateOperation.Target,
        menuInstanceID: UUID, nonce: UUID,
        authenticateMenu: (UUID, BelugaUpdateOperation.Target,
                           BelugaUpdateOperation.ArtifactIdentity) throws -> Void
    ) throws -> BelugaUpdateOperation.ReadinessChallenge {
        try guarded {
            try requireBinding(operationID, target)
            guard let completion else { throw Failure.invalidTransition }
            try context.revalidate()
            try requireCurrent()
            try authenticateMenu(menuInstanceID, target, completion.candidate)
            try rejectReentry()
            try context.revalidate()
            try requireCurrent()
            var next = try requireOperation()
            guard let challenge = next.issueReadinessChallenge(menuInstanceID: menuInstanceID,
                                                               nonce: nonce) else {
                throw Failure.invalidTransition
            }
            operation = next // The one-use challenge is intentionally not restored from disk.
            return challenge
        }
    }

    package func acceptReadiness(
        _ response: BelugaUpdateOperation.MenuReadiness,
        authenticateReadiness: (BelugaUpdateOperation.MenuReadiness) throws -> Void
    ) throws {
        try guarded {
            try requireBinding(response.operationID, response.target)
            guard completion != nil else { throw Failure.invalidTransition }
            try context.revalidate()
            try requireCurrent()
            try authenticateReadiness(response)
            try rejectReentry()
            try context.revalidate()
            try requireCurrent()
            var next = try requireOperation()
            guard next.acceptMenuReadiness(response) else { throw Failure.invalidTransition }
            try persist(next)
            readiness = response
        }
    }

    /// Fresh final proof is mandatory. A failed clear retains ownership, even if a failed
    /// directory sync leaves uncertain marker durability; it never authorizes activation.
    package func clearAndRelease(
        operationID: UUID, target: BelugaUpdateOperation.Target,
        verifyCompletionAndReadiness: (BelugaUpdateOperation.InstalledCompletion,
                                      BelugaUpdateOperation.MenuReadiness,
                                      BelugaUpdateRuntimeContext) throws -> Void
    ) throws {
        try guarded {
            try requireBinding(operationID, target)
            let current = try requireOperation()
            guard current.permitsFenceRelease, let completion, let readiness, let snapshot else {
                throw Failure.invalidTransition
            }
            try context.revalidate()
            try requireCurrent()
            try verifyCompletionAndReadiness(completion, readiness, context)
            try rejectReentry()
            try context.revalidate()
            try requireCurrent()
            try store.clear(current, expected: snapshot, installedCompletion: completion,
                            readiness: readiness)
            owner?.release()
            owner = nil
            currentState = .cleared
            publish()
            afterClearedCommitForTesting?()
        }
    }

    /// Cancellation is uncertainty, not a positive installer completion or safe retirement.
    package func cancel(operationID: UUID, target: BelugaUpdateOperation.Target) throws {
        try guarded {
            try requireBinding(operationID, target)
            try requireCurrent()
            failClosed()
        }
    }

    private func requireBinding(_ operationID: UUID, _ target: BelugaUpdateOperation.Target) throws {
        guard owner != nil, let operation, operation.operationID == operationID,
              operation.target == target else { throw Failure.unexpectedBinding }
    }

    private func requireOperation() throws -> BelugaUpdateOperation {
        guard let operation else { throw Failure.invalidTransition }
        return operation
    }

    private func requireCurrent() throws {
        guard let snapshot else { throw Failure.invalidTransition }
        // Same-byte replace is a nonwriting exact bytes/inode/directory comparison.
        _ = try store.replace(try requireOperation(), expected: snapshot)
    }

    private func persist(_ next: BelugaUpdateOperation) throws {
        guard let snapshot else { throw Failure.invalidTransition }
        let persisted = try store.replace(next, expected: snapshot)
        operation = next
        self.snapshot = persisted
        publish()
    }

    private func rejectReentry() throws {
        reentrySerialization.lock()
        defer { reentrySerialization.unlock() }
        guard !reentryObserved else { throw Failure.reentrantCall }
    }

    private func recordReentry() {
        reentrySerialization.lock()
        reentryObserved = true
        reentrySerialization.unlock()
    }

    private func failClosed() {
        guard currentState != .cleared else { return }
        currentState = .failed
        operation?.observe(.updaterFailed)
        completion = nil
        readiness = nil
        publish()
    }

    private func guarded<Value>(_ body: () throws -> Value) throws -> Value {
        // A callback that synchronously hops to another thread must reject rather than
        // wait on this owner and deadlock its caller. Reentry also poisons the outer call.
        guard serialization.try() else { recordReentry(); throw Failure.reentrantCall }
        defer { serialization.unlock() }
        guard !busy else { recordReentry(); throw Failure.reentrantCall }
        guard currentState != .failed, currentState != .cleared else { throw Failure.inactiveSession }
        busy = true
        defer { busy = false }
        do {
            let value = try body()
            // Exact durable clearance is an irreversible successful commit. A rejected
            // competing call cannot turn marker absence and lease release into failure.
            if currentState == .cleared { return value }
            try rejectReentry()
            return value
        } catch {
            failClosed()
            throw error
        }
    }

    private func publish() {
        let next = Observation(state: currentState, ownsLease: owner != nil,
                               operationID: operation?.operationID,
                               recordSHA256: snapshot?.recordSHA256)
        observationSerialization.lock()
        published = next
        observationSerialization.unlock()
    }

    private func observed<Value>(_ body: (Observation) -> Value) -> Value {
        observationSerialization.lock()
        let observation = published
        observationSerialization.unlock()
        return body(observation)
    }
}
