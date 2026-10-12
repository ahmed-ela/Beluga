import BelugaCore
import Foundation
import XCTest
@testable import WebRTCTransport

private final class ICEJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    private var completed: [UInt64] = []
    private var durations: [Duration] = []
    func record(_ value: String) { lock.lock(); entries.append(value); lock.unlock() }
    func finished(_ epoch: UInt64) { lock.lock(); completed.append(epoch); lock.unlock() }
    func values() -> [String] { lock.lock(); defer { lock.unlock() }; return entries }
    func finishes() -> [UInt64] { lock.lock(); defer { lock.unlock() }; return completed }
    func slept(_ duration: Duration) { lock.lock(); durations.append(duration); lock.unlock() }
    func exactDurations() -> [Duration] { lock.lock(); defer { lock.unlock() }; return durations }
}
private enum ICEProbeError: Error { case deliberate }
/// Intentionally non-cooperative: explicit completion is required after cancellation.
private actor ICEGate {
    private var waiters: [CheckedContinuation<Void, Error>] = []
    func suspend() async throws {
        try await withCheckedThrowingContinuation { waiters.append($0) }
    }
    func count() -> Int { waiters.count }
    func release(throwing: Bool = false) {
        guard !waiters.isEmpty else { return }
        let continuation = waiters.removeFirst()
        if throwing { continuation.resume(throwing: ICEProbeError.deliberate) }
        else { continuation.resume() }
    }
}
private struct ICEObserved: Equatable, Sendable {
    let phase: UInt32; let epoch: UInt64; let attempts: Int64; let delivered: Bool; let owned: Bool
}
private struct ICEHandle: Sendable {
    let signal: @Sendable (WebRTCICEState) async -> Void
    let request: @Sendable () async -> Void
    let cancel: @Sendable () async -> Void
    let snapshot: @Sendable () async -> ICEObserved
}
private func handle(reference: Bool, policy: ICERecoveryCoordinator.Policy,
                    restart: @escaping ICERecoveryCoordinator.RestartAction,
                    exhausted: @escaping ICERecoveryCoordinator.ExhaustedAction,
                    sleeper: @escaping @Sendable (Duration) async throws -> Void,
                    journal: ICEJournal) -> ICEHandle {
    if reference {
        let p = ICERecoveryOriginalReference.Policy(disconnectedGrace: policy.disconnectedGrace,
            restartTimeout: policy.restartTimeout, retryDelay: policy.retryDelay,
            maximumAttempts: policy.maximumAttempts)
        let c = ICERecoveryOriginalReference(policy: p, restart: restart, exhausted: exhausted,
            sleeper: sleeper, workflowFinished: { journal.finished($0) })
        return .init(signal: { await c.iceStateChanged($0) }, request: { await c.restartRequested() },
            cancel: { await c.cancel() }, snapshot: {
                let s = await c.snapshotForTesting()
                let phases: [String: UInt32] = ["idle": 0, "grace": 1, "attempting": 2,
                    "awaitingConnection": 3, "retryDelay": 4, "exhausted": 5, "cancelled": 6]
                return .init(phase: phases[s.phase]!, epoch: s.epoch, attempts: Int64(s.attempts),
                    delivered: s.exhaustionWasDelivered, owned: s.taskOwned)
            })
    }
    let c = ICERecoveryCoordinator(policy: policy, restart: restart, exhausted: exhausted,
        sleeper: sleeper, workflowFinished: { journal.finished($0) })
    return .init(signal: { await c.iceStateChanged($0) }, request: { await c.restartRequested() },
        cancel: { await c.cancel() }, snapshot: {
            let s = await c.snapshotForTesting()
            guard let w = s.stateWords else {
                return .init(phase: UInt32.max, epoch: 0, attempts: -1, delivered: false, owned: s.taskOwned)
            }
            return .init(phase: UInt32(w[1]), epoch: w[2], attempts: Int64(bitPattern: w[3]),
                delivered: w[5] == 1, owned: s.taskOwned)
        })
}
private func iceEventually(_ predicate: () async -> Bool) async -> Bool {
    for _ in 0..<10_000 { if await predicate() { return true }; await Task.yield() }
    return false
}
private func immediatePolicy(max: Int = 2) -> ICERecoveryCoordinator.Policy {
    .init(disconnectedGrace: .zero, restartTimeout: .zero, retryDelay: .zero, maximumAttempts: max)
}

final class BelugaRustICERecoveryTests: XCTestCase {
    func testRawCFullWidthStateAndEveryEnvelopeField() {
        let config = beluga_core_ice_recovery_config_t(maximum_attempts: Int64.max, grace_positive: 1, reserved: 0)
        let initial = beluga_core_ice_recovery_initialize(1, config)
        XCTAssertTrue(BelugaRustICERecoveryBoundary.accepts(config: config, output: initial))
        var before = initial.candidate_state; before.epoch = UInt64.max
        let event = beluga_core_ice_recovery_event_t(abi_version: 1, opcode: 8, workflow_epoch: 0,
            task_cancelled: 0, succeeded: 0, wait_kind: 0, reserved: 0)
        let output = beluga_core_ice_recovery_step(1, before, event)
        XCTAssertTrue(BelugaRustICERecoveryBoundary.accepts(before: before, event: event, output: output))
        XCTAssertEqual(output.candidate_state.epoch, 0)
        XCTAssertEqual(output.candidate_state.maximum_attempts, Int64.max)
        XCTAssertEqual(BelugaRustICERecoveryBoundary.stateWords(output.copied_before),
                       BelugaRustICERecoveryBoundary.stateWords(before))
        XCTAssertEqual(BelugaRustICERecoveryBoundary.eventWords(output.copied_event),
                       BelugaRustICERecoveryBoundary.eventWords(event))
        XCTAssertEqual(output.flags, 1); XCTAssertEqual(output.effect, 1)
        XCTAssertTrue(BelugaRustICERecoveryBoundary.layoutsAreExact())
        for abi: UInt32 in [0, 2, 0x10001, UInt32.max] {
            let rejected = beluga_core_ice_recovery_step(abi, before, event)
            XCTAssertEqual(rejected.status, 1); XCTAssertEqual(rejected.effect, 0)
            XCTAssertEqual(rejected.flags, 0)
            XCTAssertEqual(BelugaRustICERecoveryBoundary.stateWords(rejected.candidate_state),
                           BelugaRustICERecoveryBoundary.stateWords(before))
        }
    }

    func testActualCFirstRejectsEveryMalformedCopiedResultTransactionally() throws {
        typealias Output = BelugaRustICERecoveryProducer.Output
        let corruptions: [@Sendable (inout Output) -> Void] = [
            { $0.abi_version = 0 }, { $0.status = 1 }, { $0.reserved = 1 }, { $0.effect = 15 },
            { $0.flags = 2 }, { $0.copied_before.epoch ^= 1 }, { $0.copied_before.maximum_attempts -= 1 },
            { $0.copied_event.opcode ^= 1 }, { $0.copied_event.workflow_epoch = 1 },
            { $0.candidate_state.abi_version = 0 }, { $0.candidate_state.reserved = 1 },
            { $0.candidate_state.phase = 7 }, { $0.candidate_state.cursor = 99 },
            { $0.candidate_state.maximum_attempts = 1 }, { $0.candidate_state.grace_positive = 1 },
            { $0.candidate_state.exhaustion_delivered = 2 }, { $0.candidate_state.attempts = -1 },
            { $0.candidate_state.epoch = 44 }, { $0.effect = 14 }
        ]
        for corrupt in corruptions {
            let calls = ICEJournal()
            let producer = BelugaRustICERecoveryProducer(initialize: BelugaRustICERecoveryProducer.actual.initialize,
                step: { abi, before, event in
                    var out = beluga_core_ice_recovery_step(abi, before, event)
                    calls.record("actual-C-success-\(out.status)")
                    corrupt(&out); return out
                })
            var policy = try BelugaRustICERecoveryPolicy(policy: immediatePolicy(), producer: producer)
            let before = BelugaRustICERecoveryBoundary.stateWords(policy.state)
            let event = beluga_core_ice_recovery_event_t(abi_version: 1, opcode: 8, workflow_epoch: 0,
                task_cancelled: 0, succeeded: 0, wait_kind: 0, reserved: 0)
            XCTAssertThrowsError(try policy.transition(event))
            XCTAssertTrue(policy.faulted)
            XCTAssertEqual(BelugaRustICERecoveryBoundary.stateWords(policy.state), before)
            XCTAssertThrowsError(try policy.transition(event))
            XCTAssertEqual(calls.values(), ["actual-C-success-0"])
        }
    }

    func testRawEnvelopeCannotBorrowForgedSuccessfulFinishOrInitializer() {
        let config = beluga_core_ice_recovery_config_t(maximum_attempts: 2, grace_positive: 0, reserved: 0)
        let valid = beluga_core_ice_recovery_initialize(1, config)
        for malformed in [beluga_core_ice_recovery_config_t(maximum_attempts: 0, grace_positive: 0, reserved: 0),
                          .init(maximum_attempts: 2, grace_positive: 2, reserved: 0),
                          .init(maximum_attempts: 2, grace_positive: 0, reserved: 1)] {
            var actual = beluga_core_ice_recovery_initialize(1, malformed)
            XCTAssertEqual(actual.status, 4)
            actual.status = 0; actual.candidate_state = valid.candidate_state
            XCTAssertFalse(BelugaRustICERecoveryBoundary.accepts(config: malformed, output: actual))
        }
        let s = valid.candidate_state
        let events: [beluga_core_ice_recovery_event_t] = [
            .init(abi_version: 0, opcode: 17, workflow_epoch: 0, task_cancelled: 0, succeeded: 0, wait_kind: 0, reserved: 0),
            .init(abi_version: 1, opcode: 17, workflow_epoch: 0, task_cancelled: 2, succeeded: 0, wait_kind: 0, reserved: 0),
            .init(abi_version: 1, opcode: 17, workflow_epoch: 0, task_cancelled: 0, succeeded: 1, wait_kind: 0, reserved: 0),
            .init(abi_version: 1, opcode: 17, workflow_epoch: 0, task_cancelled: 0, succeeded: 0, wait_kind: 1, reserved: 0),
            .init(abi_version: 1, opcode: 17, workflow_epoch: 0, task_cancelled: 0, succeeded: 0, wait_kind: 0, reserved: 1)]
        for event in events {
            var out = beluga_core_ice_recovery_step(1, s, event)
            XCTAssertEqual(out.status, 3); out.status = 0; out.effect = 14
            XCTAssertFalse(BelugaRustICERecoveryBoundary.accepts(before: s, event: event, output: out))
        }
        let wrongStage = beluga_core_ice_recovery_event_t(abi_version: 1, opcode: 14,
            workflow_epoch: 0, task_cancelled: 0, succeeded: 0, wait_kind: 1, reserved: 0)
        var stop = beluga_core_ice_recovery_step(1, s, wrongStage)
        XCTAssertEqual(stop.status, 3); stop.status = 0; stop.effect = 13
        XCTAssertFalse(BelugaRustICERecoveryBoundary.accepts(before: s, event: wrongStage, output: stop))
    }

    func testExternalCopiedResultsCannotReviveReplaceOrSuppressCancellation() {
        let config = beluga_core_ice_recovery_config_t(maximum_attempts: 2, grace_positive: 0, reserved: 0)
        let idle = beluga_core_ice_recovery_initialize(1, config).candidate_state
        let event: @Sendable (UInt32) -> beluga_core_ice_recovery_event_t = {
            .init(abi_version: 1, opcode: $0, workflow_epoch: 0, task_cancelled: 0, succeeded: 0, wait_kind: 0, reserved: 0)
        }
        let cancelled = beluga_core_ice_recovery_step(1, idle, event(9)).candidate_state
        var revive = beluga_core_ice_recovery_step(1, cancelled, event(2))
        XCTAssertEqual(revive.flags, 0)
        revive.flags = 1; revive.candidate_state.phase = 0; revive.candidate_state.epoch = cancelled.epoch &+ 1
        XCTAssertFalse(BelugaRustICERecoveryBoundary.accepts(before: cancelled, event: event(2), output: revive))
        let active = beluga_core_ice_recovery_step(1, idle, event(8)).candidate_state
        var replace = beluga_core_ice_recovery_step(1, active, event(8))
        XCTAssertEqual(replace.flags, 0)
        replace.flags = 1; replace.effect = 1; replace.candidate_state.epoch = active.epoch &+ 1
        XCTAssertFalse(BelugaRustICERecoveryBoundary.accepts(before: active, event: event(8), output: replace))
        for opcode: UInt32 in [2, 3, 6, 9] {
            var suppress = beluga_core_ice_recovery_step(1, active, event(opcode))
            XCTAssertEqual(suppress.flags, 1)
            suppress.flags = 0; suppress.effect = 0; suppress.candidate_state = active
            XCTAssertFalse(BelugaRustICERecoveryBoundary.accepts(before: active, event: event(opcode), output: suppress))
        }
    }

    func testMalformedInitializerReportsFailureWithoutInventedState() async {
        let journal = ICEJournal()
        let producer = BelugaRustICERecoveryProducer(initialize: { abi, config in
            var out = beluga_core_ice_recovery_initialize(abi, config)
            journal.record("actual-init-\(out.status)"); out.copied_config.maximum_attempts = 9; return out
        }, step: BelugaRustICERecoveryProducer.actual.step)
        let c = ICERecoveryCoordinator(policy: immediatePolicy(), restart: { journal.record("restart") },
            exhausted: { journal.record("exhausted") }, sleeper: { _ in journal.record("sleep") },
            policyFailed: { _ in journal.record("fault") }, producer: producer)
        await c.restartRequested()
        let delivered = await iceEventually { journal.values().contains("fault") }; XCTAssertTrue(delivered)
        let s = await c.snapshotForTesting()
        XCTAssertNil(s.stateWords); XCTAssertTrue(s.bridgeFaulted); XCTAssertFalse(s.taskOwned)
        await c.cancel(); await c.restartRequested()
        XCTAssertEqual(journal.values(), ["actual-init-0", "fault"])
    }

    func testCallerFaultCancelsNativeOwnershipAndCannotGrantAnyRecoveryEffect() async {
        let journal = ICEJournal()
        let producer = BelugaRustICERecoveryProducer(initialize: BelugaRustICERecoveryProducer.actual.initialize,
            step: { abi, state, event in
                var out = beluga_core_ice_recovery_step(abi, state, event)
                journal.record("actual-\(event.opcode)-\(out.status)")
                if event.opcode == 11 { out.copied_event.reserved = 1 }; return out
            })
        let c = ICERecoveryCoordinator(policy: immediatePolicy(), restart: { journal.record("restart") },
            exhausted: { journal.record("exhaust") }, sleeper: { _ in journal.record("sleep") },
            policyFailed: { _ in journal.record("fault") }, producer: producer,
            workflowFinished: { journal.finished($0) })
        await c.restartRequested()
        let done = await iceEventually { journal.finishes() == [1] && journal.values().contains("fault") }
        XCTAssertTrue(done)
        let snapshot = await c.snapshotForTesting()
        XCTAssertTrue(snapshot.bridgeFaulted); XCTAssertFalse(snapshot.taskOwned)
        XCTAssertEqual(snapshot.stateWords?[3], 0) // Rejected begin never commits attempt 1.
        XCTAssertEqual(snapshot.stateWords?[7], 2) // Retained accepted BEGIN evidence, not invented idle.
        await c.iceStateChanged(.connected); await c.restartRequested()
        XCTAssertEqual(journal.values(), ["actual-8-0", "actual-10-0", "actual-11-0", "fault"])
    }

    func testFaultAfterSuspendedRestartCompletesBeforeNegativeAssertions() async {
        let journal = ICEJournal(), gate = ICEGate()
        let producer = BelugaRustICERecoveryProducer(initialize: BelugaRustICERecoveryProducer.actual.initialize,
            step: { abi, state, event in
                var out = beluga_core_ice_recovery_step(abi, state, event)
                journal.record("actual-\(event.opcode)-\(out.status)")
                if event.opcode == 12 { out.candidate_state.reserved = 1 }; return out
            })
        let c = ICERecoveryCoordinator(policy: immediatePolicy(), restart: {
            journal.record("restart"); try await gate.suspend()
        }, exhausted: { journal.record("exhaust") }, sleeper: { _ in journal.record("sleep") },
            policyFailed: { _ in journal.record("fault") }, producer: producer,
            workflowFinished: { journal.finished($0) })
        await c.restartRequested()
        let waiting = await iceEventually { await gate.count() == 1 }; XCTAssertTrue(waiting)
        await gate.release()
        let done = await iceEventually { journal.finishes() == [1] && journal.values().contains("fault") }
        XCTAssertTrue(done)
        XCTAssertFalse(journal.values().contains("sleep")); XCTAssertFalse(journal.values().contains("exhaust"))
        let s = await c.snapshotForTesting(); XCTAssertTrue(s.bridgeFaulted); XCTAssertFalse(s.taskOwned)
        XCTAssertEqual(s.stateWords?[1], 2); XCTAssertEqual(s.stateWords?[3], 1)
    }

    func testWrongWaitSelectorIsRejectedBeforeWrongNativeDuration() async {
        let j = ICEJournal()
        let producer = BelugaRustICERecoveryProducer(initialize: BelugaRustICERecoveryProducer.actual.initialize,
            step: { abi, state, event in
                var out = beluga_core_ice_recovery_step(abi, state, event)
                j.record("actual-\(event.opcode)-\(out.effect)")
                if event.opcode == 13 { out.effect = 8 }; return out // Actual grace effect7 first.
            })
        let c = ICERecoveryCoordinator(policy: .init(), restart: { j.record("restart") },
            exhausted: { j.record("exhaust") }, sleeper: { j.record("sleep-\($0)") },
            policyFailed: { _ in j.record("fault") }, producer: producer,
            workflowFinished: { j.finished($0) })
        await c.iceStateChanged(.disconnected)
        let done = await iceEventually { j.finishes() == [1] && j.values().contains("fault") }; XCTAssertTrue(done)
        XCTAssertEqual(j.values(), ["actual-4-1", "actual-10-4", "actual-13-7", "fault"])
        let snapshot = await c.snapshotForTesting(); XCTAssertFalse(snapshot.taskOwned)
    }

    func testExhaustEffectWithoutCommittedDeliveredStateIsRejected() async {
        let j = ICEJournal()
        let producer = BelugaRustICERecoveryProducer(initialize: BelugaRustICERecoveryProducer.actual.initialize,
            step: { abi, state, event in
                var out = beluga_core_ice_recovery_step(abi, state, event)
                if event.opcode == 16 { j.record("actual-exhaust-\(out.effect)"); out.candidate_state = state }
                return out
            })
        let c = ICERecoveryCoordinator(policy: immediatePolicy(max: 1), restart: { j.record("restart") },
            exhausted: { j.record("exhaust") }, sleeper: { _ in j.record("sleep") },
            policyFailed: { _ in j.record("fault") }, producer: producer,
            workflowFinished: { j.finished($0) })
        await c.restartRequested()
        let done = await iceEventually { j.finishes() == [1] && j.values().contains("fault") }; XCTAssertTrue(done)
        XCTAssertEqual(j.values(), ["restart", "actual-exhaust-12", "fault"])
        let s = await c.snapshotForTesting(); XCTAssertEqual(s.stateWords?[1], 3)
        XCTAssertEqual(s.stateWords?[5], 0); XCTAssertEqual(s.stateWords?[7], 7)
    }

    func testStaleFinishCannotReviveCancelledCoordinatorThroughCorruptCandidate() async {
        let j = ICEJournal(), gate = ICEGate()
        let producer = BelugaRustICERecoveryProducer(initialize: BelugaRustICERecoveryProducer.actual.initialize,
            step: { abi, state, event in
                var out = beluga_core_ice_recovery_step(abi, state, event)
                if event.opcode == 17 { j.record("actual-finish-\(out.effect)"); out.candidate_state.phase = 0 }
                return out
            })
        let c = ICERecoveryCoordinator(policy: immediatePolicy(), restart: {
            j.record("restart"); try await gate.suspend()
        }, exhausted: { j.record("exhaust") }, sleeper: { _ in j.record("sleep") },
            policyFailed: { _ in j.record("fault") }, producer: producer,
            workflowFinished: { j.finished($0) })
        await c.restartRequested(); let waiting = await iceEventually { await gate.count() == 1 }; XCTAssertTrue(waiting)
        await c.cancel(); await gate.release()
        let done = await iceEventually { j.finishes() == [1] && j.values().contains("fault") }; XCTAssertTrue(done)
        await c.restartRequested()
        XCTAssertEqual(j.values(), ["restart", "actual-finish-0", "fault"])
        let s = await c.snapshotForTesting(); XCTAssertEqual(s.stateWords?[1], 6); XCTAssertEqual(s.stateWords?[2], 2)
    }

    func testGraceAccelerationAndCoalescingMatchFrozenOriginal() async {
        var results: [[String]] = []
        for reference in [false, true] {
            let journal = ICEJournal(), gate = ICEGate()
            let policy = ICERecoveryCoordinator.Policy(disconnectedGrace: .seconds(10),
                restartTimeout: .seconds(20), retryDelay: .seconds(30), maximumAttempts: 2)
            let c = handle(reference: reference, policy: policy, restart: { journal.record("restart") },
                exhausted: { journal.record("exhaust") }, sleeper: { d in
                    journal.record("sleep-\(d)"); try await gate.suspend()
                }, journal: journal)
            await c.signal(.disconnected)
            let first = await iceEventually { await gate.count() == 1 }; XCTAssertTrue(first)
            await c.request()
            let second = await iceEventually { await gate.count() == 2 }; XCTAssertTrue(second)
            await c.request(); await c.signal(.failed)
            XCTAssertEqual(journal.values().filter { $0 == "restart" }.count, 1)
            await gate.release() // Old cancelled grace deliberately completes successfully.
            let oldDone = await iceEventually { journal.finishes().contains(1) }; XCTAssertTrue(oldDone)
            let replacement = await c.snapshot(); XCTAssertTrue(replacement.owned)
            XCTAssertEqual(replacement.epoch, 2); XCTAssertEqual(replacement.phase, 3)
            await c.signal(.connected); await gate.release()
            let allDone = await iceEventually { journal.finishes().contains(2) }; XCTAssertTrue(allDone)
            let final = await c.snapshot(); XCTAssertEqual(final.phase, 0)
            results.append(journal.values())
        }
        XCTAssertEqual(results[0], results[1])
    }

    func testZeroAndTinyExactDurationsMatchFrozenOriginal() async {
        let tiny = (Duration(secondsComponent: 0, attosecondsComponent: 1),
                    Duration(secondsComponent: 0, attosecondsComponent: 2),
                    Duration(secondsComponent: 0, attosecondsComponent: 3))
        for durations in [(Duration.zero, Duration.zero, Duration.zero), tiny,
                          (.zero, tiny.1, tiny.2), (tiny.0, .zero, tiny.2), (tiny.0, tiny.1, .zero)] {
            var traces: [[String]] = []
            for reference in [false, true] {
                let j = ICEJournal()
                let p = ICERecoveryCoordinator.Policy(disconnectedGrace: durations.0,
                    restartTimeout: durations.1, retryDelay: durations.2, maximumAttempts: 2)
                let c = handle(reference: reference, policy: p, restart: { j.record("restart") },
                    exhausted: { j.record("exhaust") }, sleeper: { j.slept($0); j.record("sleep-\($0)") }, journal: j)
                await c.signal(.disconnected)
                let done = await iceEventually { j.finishes() == [1] }; XCTAssertTrue(done)
                let final = await c.snapshot(); XCTAssertEqual(final.phase, 5)
                XCTAssertEqual(j.values().filter { $0 == "restart" }.count, 2)
                XCTAssertEqual(j.exactDurations(), [durations.0, durations.1, durations.2, durations.1].filter { $0 > .zero })
                traces.append(j.values())
            }
            XCTAssertEqual(traces[0], traces[1])
        }
    }

    func testEveryNonCancellationSleepFailureStopsAndAllowsFreshWorkflow() async {
        for failingKind in ["grace", "timeout", "retry"] {
            var traces: [[String]] = []
            for reference in [false, true] {
                let j = ICEJournal()
                let p = ICERecoveryCoordinator.Policy(disconnectedGrace: .seconds(10),
                    restartTimeout: .seconds(20), retryDelay: .seconds(30), maximumAttempts: 2)
                let c = handle(reference: reference, policy: p, restart: {
                    j.record("restart"); if failingKind == "retry" { throw ICEProbeError.deliberate }
                }, exhausted: { j.record("exhaust") }, sleeper: { d in
                    j.record("sleep-\(d)")
                    if (failingKind == "grace" && d == .seconds(10))
                        || (failingKind == "timeout" && d == .seconds(20))
                        || (failingKind == "retry" && d == .seconds(30)) { throw ICEProbeError.deliberate }
                }, journal: j)
                if failingKind == "grace" { await c.signal(.disconnected) } else { await c.request() }
                let done = await iceEventually { j.finishes() == [1] }; XCTAssertTrue(done)
                let s = await c.snapshot(); XCTAssertEqual(s.phase, 0); XCTAssertEqual(s.attempts, 0)
                XCTAssertFalse(s.owned); XCTAssertFalse(j.values().contains("exhaust"))
                await c.request(); let next = await iceEventually { j.finishes().contains(2) }; XCTAssertTrue(next)
                traces.append(j.values())
            }
            XCTAssertEqual(traces[0], traces[1])
        }
    }

    func testThrownCancellationErrorWithoutTaskCancellationConsumesAttempts() async {
        var traces: [[String]] = []
        for reference in [false, true] {
            let j = ICEJournal()
            let c = handle(reference: reference, policy: immediatePolicy(), restart: {
                j.record("restart"); throw CancellationError()
            }, exhausted: { j.record("exhaust") }, sleeper: { _ in j.record("sleep") }, journal: j)
            await c.request(); let done = await iceEventually { j.finishes() == [1] }; XCTAssertTrue(done)
            XCTAssertEqual(j.values(), ["restart", "restart", "exhaust"])
            traces.append(j.values())
        }
        XCTAssertEqual(traces[0], traces[1])
    }

    func testLateSuccessfulAndThrowingRestartCannotActAfterConnectionOrCancel() async {
        for throwsAction in [false, true] {
            for cancelled in [false, true] {
                var snapshots: [ICEObserved] = []
                for reference in [false, true] {
                    let j = ICEJournal(), gate = ICEGate()
                    let c = handle(reference: reference, policy: immediatePolicy(), restart: {
                        j.record("restart"); try await gate.suspend()
                    }, exhausted: { j.record("exhaust") }, sleeper: { _ in j.record("sleep") }, journal: j)
                    await c.request(); let waiting = await iceEventually { await gate.count() == 1 }; XCTAssertTrue(waiting)
                    if cancelled { await c.cancel() } else { await c.signal(.connected) }
                    await gate.release(throwing: throwsAction)
                    let done = await iceEventually { j.finishes() == [1] }; XCTAssertTrue(done)
                    XCTAssertEqual(j.values(), ["restart"])
                    snapshots.append(await c.snapshot())
                }
                XCTAssertEqual(snapshots[0], snapshots[1])
            }
        }
    }

    func testLateNonCooperativeSleepCannotAdvanceAfterReset() async {
        var traces: [[String]] = []
        for reference in [false, true] {
            let j = ICEJournal(), gate = ICEGate()
            let p = ICERecoveryCoordinator.Policy(disconnectedGrace: .seconds(1), maximumAttempts: 2)
            let c = handle(reference: reference, policy: p, restart: { j.record("restart") },
                exhausted: { j.record("exhaust") }, sleeper: { _ in j.record("sleep"); try await gate.suspend() }, journal: j)
            await c.signal(.disconnected); let waiting = await iceEventually { await gate.count() == 1 }; XCTAssertTrue(waiting)
            await c.signal(.connected); await gate.release()
            let done = await iceEventually { j.finishes() == [1] }; XCTAssertTrue(done)
            XCTAssertEqual(j.values(), ["sleep"]); let final = await c.snapshot(); XCTAssertEqual(final.phase, 0)
            traces.append(j.values())
        }
        XCTAssertEqual(traces[0], traces[1])
    }

    func testSuspendedExhaustionCompletionCannotClearNewWorkflow() async {
        var snapshots: [ICEObserved] = []
        for reference in [false, true] {
            let j = ICEJournal(), exhaustionGate = ICEGate(), restartGate = ICEGate()
            let c = handle(reference: reference, policy: immediatePolicy(max: 1), restart: {
                j.record("restart")
                if j.values().filter({ $0 == "restart" }).count == 2 { try await restartGate.suspend() }
            }, exhausted: { j.record("exhaust"); try? await exhaustionGate.suspend() },
                sleeper: { _ in j.record("sleep") }, journal: j)
            await c.request(); let oldWaiting = await iceEventually { await exhaustionGate.count() == 1 }; XCTAssertTrue(oldWaiting)
            await c.signal(.connected); await c.request()
            let newWaiting = await iceEventually { await restartGate.count() == 1 }; XCTAssertTrue(newWaiting)
            await exhaustionGate.release()
            let oldDone = await iceEventually { j.finishes().contains(1) }; XCTAssertTrue(oldDone)
            let new = await c.snapshot(); XCTAssertTrue(new.owned); XCTAssertEqual(new.epoch, 3)
            XCTAssertEqual(new.phase, 2); snapshots.append(new)
            await c.cancel(); await restartGate.release()
            let done = await iceEventually { j.finishes().contains(3) }; XCTAssertTrue(done)
            XCTAssertEqual(j.values(), ["restart", "exhaust", "restart"])
        }
        XCTAssertEqual(snapshots[0], snapshots[1])
    }

    func testRepeatedDirectCancelVersusIgnoredTerminalIceSignals() async {
        var snapshots: [ICEObserved] = []
        for reference in [false, true] {
            let j = ICEJournal()
            let c = handle(reference: reference, policy: immediatePolicy(), restart: { j.record("restart") },
                exhausted: { j.record("exhaust") }, sleeper: { _ in j.record("sleep") }, journal: j)
            await c.cancel(); await c.cancel()
            for signal: WebRTCICEState in [.new, .checking, .connected, .completed, .disconnected, .failed, .closed, .unknown] {
                await c.signal(signal)
            }
            await c.request()
            let s = await c.snapshot(); XCTAssertEqual(s.epoch, 2); XCTAssertEqual(s.phase, 6)
            XCTAssertEqual(j.values(), []); snapshots.append(s)
        }
        XCTAssertEqual(snapshots[0], snapshots[1])
    }
}
