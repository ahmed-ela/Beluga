// PROSPECTIVE actual-C -> boundary -> constructor callback -> inert-native teardown tests.
import Foundation
import XCTest
@testable import CaptureCore
@testable import CaptureServer
@testable import WebRTCTransport

@MainActor
final class WorldwideICERecoveryPolicyChainTests: XCTestCase {
    func testActualCorruptCheckingCResultStopsMatchingHostThroughInstalledCallbackOnce() async throws {
        for profile in [WorldwideScreenServiceFeatureProfile.fullPrimary, .secondaryTest] {
            let f = try BatchAActualServiceFixture(profile: profile)
            await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
            await f.service.batchAStageAggregateTransportForTesting(needsRedrive: false)
            let injection = ICERecoveryCoordinator.CheckingFaultInjectionForTesting()
            let coordinator = await f.service.batchAInstallActualICERecoveryCoordinatorForTesting(
                peerGeneration: UInt64.max, checkingFaultInjection: injection,
                restart: { [trace = f.trace] in trace.record("ice.restart.UNEXPECTED"); throw CancellationError() })
            let accepted = await coordinator.faultDeliverySnapshotForTesting()
            let before = await f.service.batchAICERecoveryPolicyReceiverSnapshotForTesting()
            XCTAssertTrue(before.coordinatorIsPresent)
            XCTAssertTrue(before.peerIsConnected && before.iceIsConnected && before.controlChannelIsOpen)
            XCTAssertFalse(before.recoveryProofRequired)
            let finished = expectation(description: "constructor callback awaited actual host completion")
            let completion = Task {
                var count = 0
                for await _ in f.service.completion { count += 1 }
                XCTAssertEqual(count, 1)
                finished.fulfill()
            }

            await coordinator.iceStateChanged(.checking)
            let joined = await coordinator.joinPolicyFailureDeliveryForTesting()
            XCTAssertTrue(joined) // AFTER the installed callback's await service.stop returns.
            await fulfillment(of: [finished], timeout: 1)
            completion.cancel()
            await completion.value
            await f.service.batchADrainOwnedInertRoutingObserversForTesting()
            let after = await f.service.batchAICERecoveryPolicyReceiverSnapshotForTesting()
            XCTAssertTrue(after.stopped)
            XCTAssertFalse(after.stopInProgress)
            XCTAssertEqual(after.peerGeneration, 0)
            XCTAssertFalse(after.coordinatorIsPresent || after.peerIsPresent)
            XCTAssertFalse(after.peerIsConnected || after.iceIsConnected || after.controlChannelIsOpen)
            XCTAssertFalse(after.captureAuthorizationIsValid || after.audioAuthorizationIsValid)
            let actor = await coordinator.faultDeliverySnapshotForTesting()
            XCTAssertEqual(actor.acceptedStateWords, accepted.acceptedStateWords)
            assertFaultWithoutEffects(actor)
            XCTAssertEqual(injection.snapshot().actualInitialCount, 1)
            XCTAssertTrue(injection.snapshot().actualInitialAccepted)
            XCTAssertEqual(injection.snapshot().actualStepCount, 1)
            XCTAssertTrue(injection.snapshot().uncorruptedCheckingAccepted)
            XCTAssertEqual(injection.snapshot().corruptionCount, 1)
            XCTAssertEqual(injection.snapshot().callbackStartedCount, 1)
            XCTAssertEqual(injection.snapshot().callbackCompletedCount, 1)
            XCTAssertEqual(f.trace.count("ice.restart.UNEXPECTED"), 0)
            let events = f.trace.events
            await coordinator.iceStateChanged(.checking)
            await coordinator.cancel()
            let rejoined = await coordinator.joinPolicyFailureDeliveryForTesting()
            XCTAssertTrue(rejoined)
            XCTAssertEqual(injection.snapshot().actualStepCount, 1)
            XCTAssertEqual(injection.snapshot().callbackStartedCount, 1)
            XCTAssertEqual(injection.snapshot().callbackCompletedCount, 1)
            XCTAssertEqual(f.trace.events, events)
            let driver = await f.service.iPhoneMicrophoneForwardingSnapshot()
            XCTAssertEqual(driver.phase, .stopped)
            XCTAssertFalse(driver.transportAuthorized || driver.queueRunning)
            XCTAssertEqual(f.trace.count("media.stop"), profile == .fullPrimary ? 1 : 0)
            await cleanup(f)
        }
    }

    func testDelayedActualCPolicyFaultCannotStopReplacementHostCoordinator() async throws {
        let f = try BatchAActualServiceFixture()
        await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
        await f.service.batchAStageAggregateTransportForTesting(needsRedrive: false)
        let gate = ICEHostFaultDeliveryGate()
        let parked = expectation(description: "A fault latched before installed callback delivery")
        let injection = ICERecoveryCoordinator.CheckingFaultInjectionForTesting {
            parked.fulfill()
            await gate.wait()
        }
        let a = await f.service.batchAInstallActualICERecoveryCoordinatorForTesting(
            peerGeneration: UInt64.max, checkingFaultInjection: injection,
            restart: { [trace = f.trace] in trace.record("ice.restart.UNEXPECTED"); throw CancellationError() })
        let accepted = await a.faultDeliverySnapshotForTesting()
        await a.iceStateChanged(.checking)
        await fulfillment(of: [parked], timeout: 1)
        let faulted = await a.faultDeliverySnapshotForTesting()
        XCTAssertEqual(faulted.acceptedStateWords, accepted.acceptedStateWords)
        assertFaultWithoutEffects(faulted)
        XCTAssertEqual(injection.snapshot().callbackStartedCount, 0)
        let b = await f.service.batchAInstallActualICERecoveryCoordinatorForTesting(
            peerGeneration: 0,
            restart: { [trace = f.trace] in trace.record("ice.restart.UNEXPECTED"); throw CancellationError() })
        let before = await f.service.batchAICERecoveryPolicyReceiverSnapshotForTesting()
        let bBefore = await b.faultDeliverySnapshotForTesting()
        XCTAssertNotNil(bBefore.acceptedStateWords)
        XCTAssertFalse(bBefore.bridgeFaulted || bBefore.failureWasDelivered || bBefore.taskOwned)
        let events = f.trace.events
        await gate.release()
        let joined = await a.joinPolicyFailureDeliveryForTesting()
        XCTAssertTrue(joined) // Negative assertions occur only after A's real callback returned.
        await f.service.batchADrainOwnedInertRoutingObserversForTesting()
        let after = await f.service.batchAICERecoveryPolicyReceiverSnapshotForTesting()
        let bAfter = await b.faultDeliverySnapshotForTesting()
        let ownsB = await f.service.batchAICERecoveryCoordinatorIsForTesting(b)
        XCTAssertTrue(ownsB)
        XCTAssertEqual(after, before)
        XCTAssertEqual(bAfter, bBefore)
        XCTAssertEqual(f.trace.events, events)
        XCTAssertEqual(f.hal.listenerCount, 3)
        XCTAssertTrue(f.hal.inputWrites.isEmpty)
        XCTAssertEqual(injection.snapshot().actualInitialCount, 1)
        XCTAssertTrue(injection.snapshot().actualInitialAccepted)
        XCTAssertEqual(injection.snapshot().actualStepCount, 1)
        XCTAssertTrue(injection.snapshot().uncorruptedCheckingAccepted)
        XCTAssertEqual(injection.snapshot().corruptionCount, 1)
        XCTAssertEqual(injection.snapshot().callbackStartedCount, 1)
        XCTAssertEqual(injection.snapshot().callbackCompletedCount, 1)
        XCTAssertFalse(f.gate.isOpen)
        XCTAssertEqual(f.trace.count("ice.restart.UNEXPECTED"), 0)
        await a.cancel() // A was displaced; callback, not cancellation, has already been joined.
        await cleanup(f) // Real stop owns and cancels B, then joins retained native observers.
    }

    private func assertFaultWithoutEffects(_ s: ICERecoveryCoordinator.FaultDeliverySnapshotForTesting) {
        XCTAssertTrue(s.bridgeFaulted && s.failureWasDelivered)
        XCTAssertFalse(s.taskOwned)
        XCTAssertEqual(s.nativeRestartCount, 0)
        XCTAssertEqual(s.nativeSleepCount, 0)
        XCTAssertEqual(s.nativeExhaustionCount, 0)
    }
    private func cleanup(_ f: BatchAActualServiceFixture) async {
        await f.service.stop()
        await f.service.batchADrainOwnedInertRoutingObserversForTesting()
        XCTAssertEqual(f.hal.listenerCount, 0)
        XCTAssertEqual(f.listenerCleanup.retainedJobCount, 0)
        XCTAssertEqual(f.inputCleanup.retainedJobCount, 0)
        XCTAssertEqual(f.serviceCleanup.retainedJobCount, 0)
        XCTAssertTrue(f.hal.inputWrites.isEmpty)
        XCTAssertFalse(f.gate.isOpen)
        for event in ["output.write.UNEXPECTED", "cleanup.schedule.UNEXPECTED",
                      "inventory.retry.UNEXPECTED", "media.start.UNEXPECTED", "media.refresh.UNEXPECTED"] {
            XCTAssertEqual(f.trace.count(event), 0, event)
        }
    }
}

private actor ICEHostFaultDeliveryGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        released = true
        waiter?.resume(); waiter = nil
    }
}
