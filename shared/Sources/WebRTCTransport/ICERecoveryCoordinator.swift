import Foundation

/// Runs one bounded ICE-recovery workflow for one peer-connection generation.
///
/// This coordinator deliberately does not reconnect signaling. A restart can succeed only while
/// the authenticated rendezvous socket that carries its offer, answer, and candidates is alive.
public actor ICERecoveryCoordinator {
    /// Bounded timing and retry limits for one recovery workflow.
    public struct Policy: Equatable, Sendable {
        public let disconnectedGrace: Duration
        public let restartTimeout: Duration
        public let retryDelay: Duration
        public let maximumAttempts: Int

        public init(
            disconnectedGrace: Duration = .seconds(2),
            restartTimeout: Duration = .seconds(8),
            retryDelay: Duration = .seconds(2),
            maximumAttempts: Int = 2
        ) {
            precondition(disconnectedGrace >= .zero)
            precondition(restartTimeout >= .zero)
            precondition(retryDelay >= .zero)
            precondition(maximumAttempts > 0)

            self.disconnectedGrace = disconnectedGrace
            self.restartTimeout = restartTimeout
            self.retryDelay = retryDelay
            self.maximumAttempts = maximumAttempts
        }
    }

    public typealias RestartAction = @Sendable () async throws -> Void
    public typealias ExhaustedAction = @Sendable () async -> Void
    internal typealias Sleeper = @Sendable (Duration) async throws -> Void
    public enum PolicyFailure: Equatable, Sendable { case invalidBridge }
    public typealias PolicyFailureAction = @Sendable (PolicyFailure) async -> Void
    internal typealias WorkflowFinished = @Sendable (UInt64) -> Void

    private let policy: Policy
    private let restart: RestartAction
    private let exhausted: ExhaustedAction
    private let sleeper: Sleeper
    private let policyFailed: PolicyFailureAction
    private let workflowFinished: WorkflowFinished
    private var controller: BelugaRustICERecoveryPolicy?
    private var bridgeFaulted = false
    private var failureWasDelivered = false
    private var recoveryTask: Task<Void, Never>?
    #if DEBUG
    private var debugCheckingFaultInjection: CheckingFaultInjectionForTesting?
    private var debugPolicyFailureDeliveryTask: Task<Void, Never>?
    private var debugNativeRestartCount = 0
    private var debugNativeSleepCount = 0
    private var debugNativeExhaustionCount = 0
    #endif

    public init(
        policy: Policy = .init(),
        restart: @escaping RestartAction,
        exhausted: @escaping ExhaustedAction,
        policyFailed: @escaping PolicyFailureAction = { _ in }
    ) {
        self.policy = policy; self.restart = restart; self.exhausted = exhausted
        self.policyFailed = policyFailed; workflowFinished = { _ in }
        sleeper = { try await Task.sleep(for: $0) }
        controller = try? BelugaRustICERecoveryPolicy(policy: policy)
    }

    internal init(
        policy: Policy,
        restart: @escaping RestartAction,
        exhausted: @escaping ExhaustedAction,
        sleeper: @escaping Sleeper,
        policyFailed: @escaping PolicyFailureAction = { _ in },
        producer: BelugaRustICERecoveryProducer = .actual,
        workflowFinished: @escaping WorkflowFinished = { _ in }
    ) {
        self.policy = policy; self.restart = restart; self.exhausted = exhausted
        self.sleeper = sleeper; self.policyFailed = policyFailed
        self.workflowFinished = workflowFinished
        controller = try? BelugaRustICERecoveryPolicy(policy: policy, producer: producer)
    }

    /// Native enum projection only; Rust owns every admission/successor decision.
    public func iceStateChanged(_ state: WebRTCICEState) {
        let opcode: UInt32
        switch state {
        case .new: opcode = 0
        case .checking: opcode = 1
        case .connected: opcode = 2
        case .completed: opcode = 3
        case .disconnected: opcode = 4
        case .failed: opcode = 5
        case .closed: opcode = 6
        case .unknown: opcode = 7
        }
        external(opcode)
    }
    public func restartRequested() { external(8) }
    public func cancel() { external(9) }

    private func external(_ opcode: UInt32) {
        guard let output = transition(event(opcode)) else { return }
        // Accepted epoch advances before native invalidation. No await intervenes.
        if output.flags == 1 { recoveryTask?.cancel(); recoveryTask = nil }
        if output.effect == 1 {
            let workflowEpoch = output.candidate_state.epoch
            recoveryTask = Task { [weak self] in await self?.runWorkflow(epoch: workflowEpoch) }
        }
    }

    private func event(_ opcode: UInt32, epoch: UInt64 = 0, succeeded: Bool = false,
                       waitKind: UInt32 = 0) -> BelugaRustICERecoveryProducer.Event {
        .init(abi_version: 1, opcode: opcode, workflow_epoch: epoch,
              task_cancelled: opcode <= 9 ? 0 : (Task.isCancelled ? 1 : 0),
              succeeded: succeeded ? 1 : 0, wait_kind: waitKind, reserved: 0)
    }

    private func transition(_ event: BelugaRustICERecoveryProducer.Event)
        -> BelugaRustICERecoveryProducer.Output? {
        guard !bridgeFaulted, var current = controller else {
            bridgeFailed(); return nil
        }
        do {
            let output = try current.transition(event)
            controller = current // Commit only the accepted Rust candidate, before effects.
            return output
        } catch {
            controller = current // Preserve accepted before-state and sticky typed fault.
            bridgeFailed(); return nil
        }
    }

    private func bridgeFailed() {
        bridgeFaulted = true
        recoveryTask?.cancel(); recoveryTask = nil
        guard !failureWasDelivered else { return }
        failureWasDelivered = true
        let callback = policyFailed
        #if DEBUG
        let injection = debugCheckingFaultInjection
        let delivery = Task {
            await injection?.waitBeforeDelivery()
            injection?.recordCallbackStarted()
            await callback(.invalidBridge)
            injection?.recordCallbackCompleted()
        }
        debugPolicyFailureDeliveryTask = delivery
        #else
        Task { await callback(.invalidBridge) }
        #endif
    }

    private func runWorkflow(epoch workflowEpoch: UInt64) async {
        defer {
            finishWorkflow(epoch: workflowEpoch)
            // Test-only non-suspending completion witness; runs after actual deferred cleanup.
            workflowFinished(workflowEpoch)
        }
        guard let entered = transition(event(10, epoch: workflowEpoch)) else { return }
        var effect = entered.effect
        while true {
            let output: BelugaRustICERecoveryProducer.Output?
            switch effect {
            case 2: // Original for-loop admission, including after grace/retry waits.
                output = transition(event(11, epoch: workflowEpoch))
            case 3:
                let sent: Bool
                #if DEBUG
                debugNativeRestartCount += 1
                #endif
                do { try await restart(); sent = true }
                catch { sent = false } // CancellationError also consumes a current attempt.
                output = transition(event(12, epoch: workflowEpoch, succeeded: sent))
            case 4, 5, 6: // Original wait preflight, before touching native exact Duration.
                output = transition(event(13, epoch: workflowEpoch, waitKind: effect - 3))
            case 7, 8, 9:
                let kind = effect - 6
                let duration: Duration
                switch kind {
                case 1: duration = policy.disconnectedGrace
                case 2: duration = policy.restartTimeout
                default: duration = policy.retryDelay
                }
                let completed: Bool
                if duration > .zero {
                    #if DEBUG
                    debugNativeSleepCount += 1
                    #endif
                    do { try await sleeper(duration); completed = true }
                    catch { completed = false }
                } else { completed = true } // No await/yield, no conversion/rounding.
                output = transition(event(14, epoch: workflowEpoch, succeeded: completed, waitKind: kind))
            case 10: // Original post-wait/action admission before retry vs final attempt.
                output = transition(event(15, epoch: workflowEpoch))
            case 11: // Original exhaust() has another independent current/cancel admission.
                output = transition(event(16, epoch: workflowEpoch))
            case 12:
                #if DEBUG
                debugNativeExhaustionCount += 1
                #endif
                await exhausted(); return
            case 13:
                return
            default:
                bridgeFailed(); return
            }
            guard let output else { return }
            effect = output.effect
        }
    }

    private func finishWorkflow(epoch workflowEpoch: UInt64) {
        guard let output = transition(event(17, epoch: workflowEpoch)) else { return }
        if output.effect == 14 { recoveryTask = nil }
    }

    #if DEBUG
    /// A narrow test hook: always obtain the real C result, then corrupt only one copied word.
    /// It does not supply state, effects, callbacks, a policy fallback, or native IO.
    public final class CheckingFaultInjectionForTesting: @unchecked Sendable {
        public struct Snapshot: Sendable, Equatable {
            public let actualInitialCount: Int
            public let actualInitialAccepted: Bool
            public let actualStepCount: Int
            public let uncorruptedCheckingAccepted: Bool
            public let corruptionCount: Int
            public let callbackStartedCount: Int
            public let callbackCompletedCount: Int
        }
        private let lock = NSLock()
        private var initialCount = 0
        private var initialAccepted = false
        private var stepCount = 0
        private var checkingAccepted = false
        private var corruptions = 0
        private var callbackStarted = 0
        private var callbackCompleted = 0
        private let beforeDelivery: @Sendable () async -> Void

        public init(beforePolicyFailureDelivery: @escaping @Sendable () async -> Void = {}) {
            beforeDelivery = beforePolicyFailureDelivery
        }
        public func snapshot() -> Snapshot {
            lock.withLock {
                .init(actualInitialCount: initialCount, actualInitialAccepted: initialAccepted,
                      actualStepCount: stepCount, uncorruptedCheckingAccepted: checkingAccepted,
                      corruptionCount: corruptions, callbackStartedCount: callbackStarted,
                      callbackCompletedCount: callbackCompleted)
            }
        }
        fileprivate func waitBeforeDelivery() async { await beforeDelivery() }
        fileprivate func recordCallbackStarted() { lock.withLock { callbackStarted += 1 } }
        fileprivate func recordCallbackCompleted() { lock.withLock { callbackCompleted += 1 } }
        fileprivate func producer() -> BelugaRustICERecoveryProducer {
            .init(initialize: { [self] abi, config in
                let output = BelugaRustICERecoveryProducer.actual.initialize(abi, config)
                lock.withLock {
                    initialCount += 1
                    initialAccepted = BelugaRustICERecoveryBoundary.accepts(config: config, output: output)
                }
                return output
            }, step: { [self] abi, before, event in
                var output = BelugaRustICERecoveryProducer.actual.step(abi, before, event)
                let corrupt = lock.withLock {
                    stepCount += 1
                    guard event.opcode == 1, corruptions == 0 else { return false }
                    checkingAccepted = BelugaRustICERecoveryBoundary.accepts(
                        before: before, event: event, output: output)
                    corruptions += 1
                    return true
                }
                if corrupt { output.copied_event.reserved = 1 }
                return output
            })
        }
    }

    /// Uses the same actual policy and native sleeper as the public production initializer.
    /// Only a checking result's copied reserved word and test delivery timing are instrumented.
    public init(
        policy: Policy = .init(),
        restart: @escaping RestartAction,
        exhausted: @escaping ExhaustedAction,
        policyFailed: @escaping PolicyFailureAction,
        checkingFaultInjectionForTesting injection: CheckingFaultInjectionForTesting
    ) {
        self.policy = policy; self.restart = restart; self.exhausted = exhausted
        self.policyFailed = policyFailed; workflowFinished = { _ in }
        sleeper = { try await Task.sleep(for: $0) }
        debugCheckingFaultInjection = injection
        controller = try? BelugaRustICERecoveryPolicy(policy: policy, producer: injection.producer())
    }

    public struct FaultDeliverySnapshotForTesting: Sendable, Equatable {
        public let acceptedStateWords: [UInt64]?
        public let bridgeFaulted: Bool
        public let taskOwned: Bool
        public let failureWasDelivered: Bool
        public let nativeRestartCount: Int
        public let nativeSleepCount: Int
        public let nativeExhaustionCount: Int
    }
    public func faultDeliverySnapshotForTesting() -> FaultDeliverySnapshotForTesting {
        .init(acceptedStateWords: controller.map { BelugaRustICERecoveryBoundary.stateWords($0.state) },
              bridgeFaulted: bridgeFaulted, taskOwned: recoveryTask != nil,
              failureWasDelivered: failureWasDelivered, nativeRestartCount: debugNativeRestartCount,
              nativeSleepCount: debugNativeSleepCount, nativeExhaustionCount: debugNativeExhaustionCount)
    }

    /// Test-only join AFTER the awaited constructor-installed callback has returned.
    /// Never invoked from cancel/finish/stop/retirement: such a lifecycle join would self-deadlock.
    public func joinPolicyFailureDeliveryForTesting() async -> Bool {
        guard let task = debugPolicyFailureDeliveryTask else { return false }
        await task.value
        return true
    }
    #endif

    internal struct TestSnapshot: Equatable, Sendable {
        let stateWords: [UInt64]?
        let bridgeFaulted: Bool
        let taskOwned: Bool
        let failureWasDelivered: Bool
    }
    internal func snapshotForTesting() -> TestSnapshot {
        .init(stateWords: controller.map { BelugaRustICERecoveryBoundary.stateWords($0.state) },
              bridgeFaulted: bridgeFaulted, taskOwned: recoveryTask != nil,
              failureWasDelivered: failureWasDelivered)
    }
}
