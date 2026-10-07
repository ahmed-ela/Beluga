// PRIVATE UNCOMPILED ADDITIVE TESTS. Real actor + real transaction/gate/lease.
import Foundation
import XCTest
@testable import CaptureCore
@testable import CaptureServer
@testable import WebRTCTransport

@MainActor
final class WorldwideScreenServiceBatchASuccessorTests: XCTestCase {
    private func withFixture(
        body: (BatchAActualServiceFixture) async throws -> Void
    ) async throws {
        let f = try BatchAActualServiceFixture()
        do {
            try await body(f)
            await f.service.stop()
            await f.service.batchADrainOwnedInertRoutingObserversForTesting()
        } catch {
            await f.service.stop()
            await f.service.batchADrainOwnedInertRoutingObserversForTesting()
            throw error
        }
        let joined = await f.service.batchAObserverJoinSnapshotForTesting()
        XCTAssertEqual(joined.retainedHandleCount, 0)
        XCTAssertEqual(joined.totalRetainedByKind, joined.totalJoinedByKind)
        XCTAssertEqual(f.hal.listenerCount, 0)
        XCTAssertEqual(f.listenerCleanup.retainedJobCount, 0)
        XCTAssertEqual(f.inputCleanup.retainedJobCount, 0)
        XCTAssertEqual(f.serviceCleanup.retainedJobCount, 0)
        XCTAssertEqual(f.trace.count("cleanup.schedule.UNEXPECTED"), 0)
        XCTAssertEqual(f.trace.count("inventory.retry.UNEXPECTED"), 0)
        XCTAssertEqual(f.trace.count("output.write.UNEXPECTED"), 0)
    }

    func testStartupJoinsExactInitialObserverBeforeTransportStaging() async throws {
        try await withFixture { f in
            // Actual startup method joins the real initially-published observer
            // Task before returning. No sleep/observer replay/transaction stub.
            await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
            let joined = await f.service.batchAObserverJoinSnapshotForTesting()
            XCTAssertEqual(joined.retainedHandleCount, 0)
            XCTAssertEqual(joined.totalRetainedByKind["inventoryObservation"], 1)
            XCTAssertEqual(joined.totalJoinedByKind["inventoryObservation"], 1)
            XCTAssertEqual(joined.totalRetainedByKind, joined.totalJoinedByKind)
            let before = await f.service.batchAPolicyFixtureSnapshotForTesting()
            XCTAssertEqual(before.nativeAdmissionCallCount, 0)
            XCTAssertEqual(f.trace.count("C.retry.3"), 0)
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            await f.service.batchAStageAggregateTransportForTesting(needsRedrive: false)
            let staged = await f.service.batchAObserverJoinSnapshotForTesting()
            XCTAssertEqual(staged.retainedHandleCount, 0)
        }
    }

    func testSuccessResetTypedCatchPreservesForeignHistoryAfterActualInputCallbacksJoin()
        async throws {
        for category in [WorldwideIPhoneMicrophoneForwardingFailureCategory.sharedClockUnsafe,
                         .formatUnsafe] {
            try await withFixture { f in
                await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
                await f.service.batchAStageAggregateTransportForTesting(needsRedrive: false)
                // Outputs are already safe, so the real invariant never enters
                // its beforeFirstMutation cleanup. Seed only terminal diagnostic
                // history, not a native peer, PCM queue, or authorization.
                await f.service.batchASeedForeignFailureForTesting(category)
                f.faults.armRetry(3)
                let admitted = await f.service.batchAAdmitForTesting()
                // Own select+release uncertainty Tasks must actually execute.
                // The proof is evaluated ONLY after their exact handles join.
                await f.service.batchADrainOwnedInertRoutingObserversForTesting()
                XCTAssertFalse(admitted)
                XCTAssertEqual(f.trace.count("reset.sawCommittedGateOpen"), 1)
                XCTAssertEqual(f.hal.inputWrites, [2, 1])
                XCTAssertEqual(f.hal.inputUID, "BuiltInMic_UID")
                let joined = await f.service.batchAObserverJoinSnapshotForTesting()
                XCTAssertEqual(joined.retainedHandleCount, 0)
                XCTAssertEqual(joined.totalRetainedByKind["inputUncertainty"], 2)
                XCTAssertEqual(joined.totalJoinedByKind["inputUncertainty"], 2)
                XCTAssertEqual(joined.totalRetainedByKind, joined.totalJoinedByKind)
                let actorState = await f.service.batchAPolicyFixtureSnapshotForTesting()
                XCTAssertEqual(actorState.nativeAdmissionCallCount, 1)
                XCTAssertEqual(actorState.fault, .invalidTransition(opcode: 3))
                XCTAssertFalse(actorState.gateOpen)
                XCTAssertFalse(actorState.safeProofPresent)
                XCTAssertFalse(actorState.endpointProofPresent)
                XCTAssertFalse(actorState.inputProofPresent)
                let driver = await f.service.iPhoneMicrophoneForwardingSnapshot()
                XCTAssertEqual(driver.lastFailureCategory, category)
                XCTAssertEqual(driver.phase, category == .sharedClockUnsafe
                               ? .sharedClockUnsafe : .formatUnsafe)
                XCTAssertFalse(driver.transportAuthorized)
                XCTAssertFalse(driver.queueRunning)
                XCTAssertNil(driver.currentAttemptID)
                // Deleting the typed catch makes generic invalidateTransport
                // change the seeded phase BEFORE the preserving observer. These
                // phase assertions then fail even though gate/proof cleanup passes.
            }
        }
    }
}
