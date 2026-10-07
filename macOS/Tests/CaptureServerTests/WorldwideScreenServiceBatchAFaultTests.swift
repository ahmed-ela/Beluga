// PRIVATE UNCOMPILED COPY-ONLY TESTS. Actual WorldwideScreenService actor only.
import Foundation
import XCTest
@testable import CaptureCore
@testable import CaptureServer
@testable import WebRTCTransport

@MainActor
final class WorldwideScreenServiceBatchAFaultTests: XCTestCase {
    private func withFixture(
        profile: WorldwideScreenServiceFeatureProfile = .fullPrimary,
        initiallyFaulted: Bool = false,
        body: (BatchAActualServiceFixture) async throws -> Void
    ) async throws {
        let fixture = try BatchAActualServiceFixture(profile: profile,
                                                    initiallyFaulted: initiallyFaulted)
        do {
            try await body(fixture)
            await fixture.service.stop()
            await fixture.service.batchADrainOwnedInertRoutingObserversForTesting()
        } catch {
            await fixture.service.stop()
            await fixture.service.batchADrainOwnedInertRoutingObserversForTesting()
            assertCleanup(fixture)
            throw error
        }
        assertCleanup(fixture)
    }
    private func assertCleanup(_ fixture: BatchAActualServiceFixture) {
        XCTAssertEqual(fixture.hal.listenerCount, 0)
        XCTAssertEqual(fixture.listenerCleanup.retainedJobCount, 0)
        XCTAssertEqual(fixture.inputCleanup.retainedJobCount, 0)
        XCTAssertEqual(fixture.serviceCleanup.retainedJobCount, 0)
        XCTAssertFalse(fixture.gate.isOpen)
        for unexpected in ["output.write.UNEXPECTED", "cleanup.schedule.UNEXPECTED",
                           "inventory.retry.UNEXPECTED", "media.start.UNEXPECTED",
                           "media.refresh.UNEXPECTED"] {
            XCTAssertEqual(fixture.trace.count(unexpected), 0, unexpected)
        }
    }

    func testStickyFaultRefusesAdmissionWhenNeedsRedriveIsFalse() async throws {
        try await withFixture(initiallyFaulted: true) { f in
            await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
            await f.service.batchAStageAggregateTransportForTesting(needsRedrive: false)
            for _ in 0..<3 {
                let admitted = await f.service.batchAAdmitForTesting()
                XCTAssertFalse(admitted)
            }
            let state = await f.service.batchAPolicyFixtureSnapshotForTesting()
            XCTAssertEqual(state.fault, .invalidInitial)
            XCTAssertTrue(state.needsRedrive)
            XCTAssertEqual(state.retryConfiguration, [6, 16, 60])
            XCTAssertEqual(state.retryCounters, [0, 0, 0])
            XCTAssertEqual(state.nativeAdmissionCallCount, 0)
            XCTAssertEqual(f.trace.count("C.retry.1"), 0)
            XCTAssertEqual(f.trace.count("C.retry.2"), 0)
            XCTAssertEqual(f.trace.count("C.retry.3"), 0)
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            assertRevoked(state)
            let driver = await f.service.iPhoneMicrophoneForwardingSnapshot()
            XCTAssertFalse(driver.transportAuthorized)
            XCTAssertFalse(driver.queueRunning)
            XCTAssertNil(driver.currentAttemptID)
        }
    }

    func testSuccessResetFaultRevokesCommittedNativeProofBeforeReturningFalse() async throws {
        try await withFixture { f in
            await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
            await f.service.batchAStageAggregateTransportForTesting(needsRedrive: false)
            f.faults.armRetry(3)
            let admitted = await f.service.batchAAdmitForTesting()
            await f.service.batchADrainOwnedInertRoutingObserversForTesting()
            XCTAssertFalse(admitted)
            // Actual invariant/lease/commit opened the actual C atomic gate;
            // the copied-C reset producer observed it before rejecting output.
            XCTAssertEqual(f.trace.count("reset.sawCommittedGateOpen"), 1)
            XCTAssertEqual(f.hal.inputWrites, [2, 1])
            XCTAssertEqual(f.hal.inputUID, "BuiltInMic_UID")
            let state = await f.service.batchAPolicyFixtureSnapshotForTesting()
            XCTAssertEqual(state.fault, .invalidTransition(opcode: 3))
            XCTAssertEqual(state.nativeAdmissionCallCount, 1)
            XCTAssertTrue(state.needsRedrive)
            XCTAssertEqual(state.retryConfiguration, [6, 16, 60])
            XCTAssertEqual(state.retryCounters, [0, 0, 0])
            assertRevoked(state)
            let driver = await f.service.iPhoneMicrophoneForwardingSnapshot()
            XCTAssertFalse(driver.transportAuthorized)
            XCTAssertFalse(driver.exactTrackAdmitted)
            XCTAssertFalse(driver.queueRunning)
            let calls = f.trace.count("C.retry.3")
            let again = await f.service.batchAAdmitForTesting()
            XCTAssertFalse(again)
            XCTAssertEqual(f.trace.count("C.retry.3"), calls)
            XCTAssertEqual(f.hal.inputWrites, [2, 1])
        }
    }

    func testStopResetFaultContinuesRealTeardown() async throws {
        try await withFixture { f in
            await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
            XCTAssertEqual(f.hal.listenerCount, 3) // inventory plus two safe outputs
            f.faults.armRetry(3)
            let finished = expectation(description: "actual completion stream finished")
            let join = Task {
                var count = 0
                for await _ in f.service.completion { count += 1 }
                XCTAssertEqual(count, 1)
                finished.fulfill()
            }
            await f.service.stop()
            await fulfillment(of: [finished], timeout: 1)
            join.cancel()
            await join.value
            await f.service.batchADrainOwnedInertRoutingObserversForTesting()
            let state = await f.service.batchAPolicyFixtureSnapshotForTesting()
            XCTAssertTrue(state.stopped)
            XCTAssertFalse(state.stopInProgress)
            XCTAssertEqual(state.fault, .invalidTransition(opcode: 3))
            assertRevoked(state)
            let driver = await f.service.iPhoneMicrophoneForwardingSnapshot()
            XCTAssertEqual(driver.phase, .stopped)
            XCTAssertFalse(driver.transportAuthorized)
            XCTAssertFalse(driver.queueRunning)
            XCTAssertEqual(f.trace.count("devices.remove"), 1)
            XCTAssertEqual(f.trace.count("output.remove"), 2)
            XCTAssertEqual(f.trace.count("media.stop"), 1)
            let transitionCalls = f.trace.count("C.retry.3")
            await f.service.stop() // actual repeated-stop join, never reset/restart
            XCTAssertEqual(f.trace.count("C.retry.3"), transitionCalls)
            XCTAssertEqual(f.trace.count("devices.remove"), 1)
            XCTAssertEqual(f.trace.count("output.remove"), 2)
            XCTAssertEqual(f.trace.count("media.stop"), 1)
            XCTAssertEqual(f.hal.listenerCount, 0)
        }
    }

    func testSecondaryProfileFaultHasNoRouteOperations() async throws {
        try await withFixture(profile: .secondaryTest, initiallyFaulted: true) { f in
            await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
            await f.service.batchAStageAggregateTransportForTesting(needsRedrive: false)
            let admitted = await f.service.batchAAdmitForTesting()
            XCTAssertFalse(admitted)
            await f.service.stop()
            let state = await f.service.batchAPolicyFixtureSnapshotForTesting()
            XCTAssertTrue(state.stopped)
            XCTAssertEqual(state.fault, .invalidInitial)
            assertRevoked(state)
            // Fault reporting must not claim route ownership for a non-mic profile.
            let routeEvents = f.trace.events.filter {
                $0.hasPrefix("input.") || $0.hasPrefix("output.")
                    || $0.hasPrefix("devices.") || $0.hasPrefix("cleanup.")
            }
            XCTAssertTrue(routeEvents.isEmpty)
            XCTAssertEqual(f.trace.count("C.retry.initial"), 1)
            XCTAssertEqual(f.trace.count("C.retry.3"), 0)
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)
            let driver = await f.service.iPhoneMicrophoneForwardingSnapshot()
            XCTAssertFalse(driver.transportAuthorized)
            XCTAssertFalse(driver.queueRunning)
        }
    }

    func testForeignFailureHistorySurvivesStickyFault() async throws {
        for category in [WorldwideIPhoneMicrophoneForwardingFailureCategory.sharedClockUnsafe,
                         .formatUnsafe] {
            try await withFixture(initiallyFaulted: true) { f in
                await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
                await f.service.batchAStageAggregateTransportForTesting(needsRedrive: false)
                await f.service.batchASeedForeignFailureForTesting(category)
                let before = await f.service.iPhoneMicrophoneForwardingSnapshot()
                XCTAssertEqual(before.lastFailureCategory, category)
                let admitted = await f.service.batchAAdmitForTesting()
                XCTAssertFalse(admitted)
                let after = await f.service.iPhoneMicrophoneForwardingSnapshot()
                XCTAssertEqual(after.lastFailureCategory, category)
                XCTAssertEqual(after.phase, category == .sharedClockUnsafe
                               ? .sharedClockUnsafe : .formatUnsafe)
                XCTAssertFalse(after.transportAuthorized)
                XCTAssertFalse(after.queueRunning)
                XCTAssertNil(after.currentAttemptID)
                XCTAssertTrue(f.hal.inputWrites.isEmpty)
            }
        }
    }

    func testHostedNoneAndEvidenceFaultConsumeWatermark() async throws {
        try await withFixture { f in
            let challenge = fixedChallenge()
            // Native classifier's legitimate ambiguous/poisoned evidence state:
            // optional causal identity exists AND prospective arm remains true.
            let none = observation(challenge, sequence: 7, active: true, armed: true)
            let result = try await f.service.batchAConsumeHostedTailForTesting(
                observation: none, challenge: challenge)
            XCTAssertNil(result)
            var state = await f.service.batchAPolicyFixtureSnapshotForTesting()
            XCTAssertEqual(state.highestHostedObservation, 7)
            XCTAssertEqual(f.trace.count("C.hosted.evidence"), 1)
            let replay = try await f.service.batchAConsumeHostedTailForTesting(
                observation: none, challenge: challenge)
            XCTAssertNil(replay)
            XCTAssertEqual(f.trace.count("C.hosted.evidence"), 1)

            f.faults.armEvidence(true)
            do {
                _ = try await f.service.batchAConsumeHostedTailForTesting(
                    observation: observation(challenge, sequence: 8, active: false, armed: false),
                    challenge: challenge)
                XCTFail("Actual-C-first copied evidence refusal must throw distinctly")
            } catch {
                XCTAssertEqual(error as? WorldwideMacHostedCallBridgeError, .evidence)
            }
            state = await f.service.batchAPolicyFixtureSnapshotForTesting()
            XCTAssertEqual(state.highestHostedObservation, 8)
            XCTAssertEqual(f.trace.count("C.hosted.evidence"), 2)
            let refusalReplay = try await f.service.batchAConsumeHostedTailForTesting(
                observation: observation(challenge, sequence: 8, active: false, armed: false),
                challenge: challenge)
            XCTAssertNil(refusalReplay)
            XCTAssertEqual(f.trace.count("C.hosted.evidence"), 2)
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
        }
    }

    func testHostedObservationFaultAndMissingPeerDoNotConsumeWatermark() async throws {
        try await withFixture { f in
            let challenge = fixedChallenge()
            f.faults.armObservation(true)
            do {
                _ = try await f.service.batchAConsumeHostedTailForTesting(
                    observation: observation(challenge, sequence: 9, active: false, armed: false),
                    challenge: challenge)
                XCTFail("Actual-C-first copied observation refusal must throw distinctly")
            } catch {
                XCTAssertEqual(error as? WorldwideMacHostedCallBridgeError, .observation)
            }
            var state = await f.service.batchAPolicyFixtureSnapshotForTesting()
            XCTAssertEqual(state.highestHostedObservation, 0)
            XCTAssertEqual(f.trace.count("C.hosted.evidence"), 0)
            f.faults.armObservation(false)
            let absentPeer = try await f.service.batchAConsumeHostedTailForTesting(
                observation: observation(challenge, sequence: 9, active: false, armed: false),
                challenge: challenge, exactPeerIsPresent: false)
            XCTAssertNil(absentPeer)
            state = await f.service.batchAPolicyFixtureSnapshotForTesting()
            XCTAssertEqual(state.highestHostedObservation, 0)
            XCTAssertEqual(f.trace.count("C.hosted.observation"), 2)
            XCTAssertEqual(f.trace.count("C.hosted.evidence"), 0)
        }
    }

    func testHostedHealthyProjectionAndOldChallengeKeepExactOrder() async throws {
        try await withFixture { f in
            let challenge = fixedChallenge()
            let healthy = try await f.service.batchAConsumeHostedTailForTesting(
                observation: observation(challenge, sequence: 10, active: false, armed: false),
                challenge: challenge)
            XCTAssertEqual(healthy, .inactive)
            let old = WebRTCMacHostedCallChallenge(sequence: 4,
                callEpochNonce: challenge.callEpochNonce, nonce: challenge.nonce)
            let rejected = try await f.service.batchAConsumeHostedTailForTesting(
                observation: observation(old, sequence: 11, active: true, armed: false),
                challenge: challenge)
            XCTAssertNil(rejected)
            let state = await f.service.batchAPolicyFixtureSnapshotForTesting()
            XCTAssertEqual(state.highestHostedObservation, 10)
            XCTAssertEqual(f.trace.count("C.hosted.evidence"), 1)
            XCTAssertEqual(Array(f.trace.events.prefix(3)),
                           ["C.retry.initial", "C.hosted.observation", "C.hosted.evidence"])
        }
    }

    private func assertRevoked(_ state: WorldwideScreenService.BatchAPolicyFixtureSnapshot) {
        XCTAssertFalse(state.gateOpen)
        XCTAssertFalse(state.safeProofPresent)
        XCTAssertFalse(state.endpointProofPresent)
        XCTAssertFalse(state.inputProofPresent)
    }
    private func fixedChallenge() -> WebRTCMacHostedCallChallenge {
        .init(sequence: 5,
            callEpochNonce: UUID(uuid: (17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32)),
            nonce: UUID(uuid: (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16)))
    }
    private func observation(_ challenge: WebRTCMacHostedCallChallenge,
                             sequence: UInt64, active: Bool, armed: Bool)
        -> SystemAudioMacFaceTimeActivityObservation {
        .init(challenge: .init(sequence: challenge.sequence, nonce: challenge.nonce,
                             callEpochNonce: challenge.callEpochNonce),
              observationSequence: sequence,
              causalBindingID: active ? UUID(uuid: (33,34,35,36,37,38,39,40,
                                                   41,42,43,44,45,46,47,48)) : nil,
              isCausallyArmed: armed)
    }
}
