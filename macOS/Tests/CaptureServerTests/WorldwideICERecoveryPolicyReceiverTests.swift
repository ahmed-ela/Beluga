// PROSPECTIVE RECEIVER TESTS. No coordinator producer/factory injection or live session.
import Foundation
import XCTest
@testable import CaptureCore
@testable import CaptureServer
@testable import WebRTCTransport

@MainActor
final class WorldwideICERecoveryPolicyReceiverTests: XCTestCase {
    func testCurrentPolicyFaultStopsActualInertServiceAndJoinsCleanup() async throws {
        // Secondary's aggregate transport is healthy: ordinary exhaustion would return.
        // The distinct policy-fault receiver must still fail closed.
        let profiles: [WorldwideScreenServiceFeatureProfile] = [.fullPrimary, .secondaryTest]
        for profile in profiles {
            try await withFixture(profile: profile) { f in
                await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
                await f.service.batchAStageAggregateTransportForTesting(needsRedrive: false)
                let generation: UInt64 = UInt64.max
                await f.service.batchASetICERecoveryReceiverGenerationForTesting(generation)
                let before = await f.service.batchAICERecoveryPolicyReceiverSnapshotForTesting()
                XCTAssertEqual(before.peerGeneration, generation)
                XCTAssertFalse(before.stopped)
                XCTAssertTrue(before.peerIsConnected && before.iceIsConnected && before.controlChannelIsOpen)
                XCTAssertFalse(before.recoveryProofRequired)
                let finished = expectation(description: "actual policy-fault completion stream finished")
                let completion = Task {
                    var count = 0
                    for await _ in f.service.completion { count += 1 }
                    XCTAssertEqual(count, 1)
                    finished.fulfill()
                }

                await f.service.batchADeliverICERecoveryPolicyFaultForTesting(peerGeneration: generation)
                await fulfillment(of: [finished], timeout: 1)
                completion.cancel()
                await completion.value
                await f.service.batchADrainOwnedInertRoutingObserversForTesting()
                let after = await f.service.batchAICERecoveryPolicyReceiverSnapshotForTesting()
                XCTAssertTrue(after.stopped)
                XCTAssertFalse(after.stopInProgress)
                XCTAssertEqual(after.peerGeneration, 0) // existing native stop uses wrapping &+=
                XCTAssertFalse(after.peerIsConnected || after.iceIsConnected || after.controlChannelIsOpen)
                XCTAssertFalse(after.peerIsPresent || after.coordinatorIsPresent)
                XCTAssertFalse(after.captureAuthorizationIsValid || after.audioAuthorizationIsValid)
                let driver = await f.service.iPhoneMicrophoneForwardingSnapshot()
                XCTAssertEqual(driver.phase, .stopped)
                XCTAssertFalse(driver.transportAuthorized)
                XCTAssertFalse(driver.queueRunning)
                XCTAssertEqual(f.hal.listenerCount, 0)
                XCTAssertTrue(f.hal.inputWrites.isEmpty)
                XCTAssertEqual(f.trace.count("devices.remove"), profile == .fullPrimary ? 1 : 0)
                XCTAssertEqual(f.trace.count("output.remove"), profile == .fullPrimary ? 2 : 0)
                XCTAssertEqual(f.trace.count("media.stop"), profile == .fullPrimary ? 1 : 0)
                await f.service.batchADeliverICERecoveryPolicyFaultForTesting(peerGeneration: generation)
                XCTAssertEqual(f.trace.count("media.stop"), profile == .fullPrimary ? 1 : 0)
            }
        }
    }

    func testCapturedOldPolicyFaultCannotStopReplacementInertGeneration() async throws {
        try await withFixture { f in
            await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
            await f.service.batchAStageAggregateTransportForTesting(needsRedrive: false)
            let oldGeneration: UInt64 = UInt64.max
            await f.service.batchASetICERecoveryReceiverGenerationForTesting(oldGeneration)
            // Delivery is delayed until a distinct synthetic generation has replaced A.
            // No peer/coordinator is fabricated by this inert generation setter.
            await f.service.batchASetICERecoveryReceiverGenerationForTesting(0)
            let before = await f.service.batchAICERecoveryPolicyReceiverSnapshotForTesting()
            let events = f.trace.events
            XCTAssertEqual(before.peerGeneration, 0)
            XCTAssertFalse(before.stopped)
            XCTAssertEqual(f.hal.listenerCount, 3)

            await f.service.batchADeliverICERecoveryPolicyFaultForTesting(peerGeneration: oldGeneration)
            await f.service.batchADrainOwnedInertRoutingObserversForTesting()
            let after = await f.service.batchAICERecoveryPolicyReceiverSnapshotForTesting()
            XCTAssertEqual(after, before)
            XCTAssertEqual(f.trace.events, events)
            XCTAssertEqual(f.hal.listenerCount, 3)
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.trace.count("media.stop"), 0)
            XCTAssertFalse(f.gate.isOpen)
            let driver = await f.service.iPhoneMicrophoneForwardingSnapshot()
            XCTAssertFalse(driver.transportAuthorized)
            XCTAssertFalse(driver.queueRunning)
        }
    }

    private func withFixture(
        profile: WorldwideScreenServiceFeatureProfile = .fullPrimary,
        body: (BatchAActualServiceFixture) async throws -> Void
    ) async throws {
        let fixture = try BatchAActualServiceFixture(profile: profile)
        do {
            try await body(fixture)
        } catch {
            await fixture.service.stop()
            await fixture.service.batchADrainOwnedInertRoutingObserversForTesting()
            assertCleanup(fixture)
            throw error
        }
        // Await real, idempotent native stop and the existing retained-observer barrier.
        await fixture.service.stop()
        await fixture.service.batchADrainOwnedInertRoutingObserversForTesting()
        assertCleanup(fixture)
    }

    private func assertCleanup(_ f: BatchAActualServiceFixture) {
        XCTAssertEqual(f.hal.listenerCount, 0)
        XCTAssertEqual(f.listenerCleanup.retainedJobCount, 0)
        XCTAssertEqual(f.inputCleanup.retainedJobCount, 0)
        XCTAssertEqual(f.serviceCleanup.retainedJobCount, 0)
        XCTAssertFalse(f.gate.isOpen)
        for unexpected in ["output.write.UNEXPECTED", "cleanup.schedule.UNEXPECTED",
                           "inventory.retry.UNEXPECTED", "media.start.UNEXPECTED",
                           "media.refresh.UNEXPECTED"] {
            XCTAssertEqual(f.trace.count(unexpected), 0, unexpected)
        }
    }
}
