// PROSPECTIVE actual-C -> boundary -> constructor callback -> Simulator-native retirement.
import Foundation
import XCTest
@testable import WebRTCTransport
@testable import opensteamer

final class WorldwideICERecoveryPolicyChainTests: XCTestCase {
    @MainActor
    func testActualCorruptCheckingCResultRetiresMatchingViewerThroughInstalledCallbackOnce() async throws {
        let viewModel = WorldwideSessionViewModel()
        let peer = try WebRTCPeer(configuration: .init(role: .viewer, iceServers: []))
        let generation = UUID()
        XCTAssertTrue(viewModel.debugInstallScreenSessionForTests(
            peer: peer, generation: generation, bindAudioTransactionDevice: true))
        let fixture = viewModel.debugInstallActiveScreenPresentationForTests(peer: peer, generation: generation)
        let injection = ICERecoveryCoordinator.CheckingFaultInjectionForTesting()
        let coordinator = viewModel.debugInstallActualICERecoveryCoordinatorForTests(
            generation: generation, checkingFaultInjection: injection,
            restart: { throw CancellationError() })
        let accepted = await coordinator.faultDeliverySnapshotForTesting()
        XCTAssertTrue(fixture.authorization.isValid)
        XCTAssertTrue(viewModel.remoteInputIsAvailable(for: fixture.lease))
        let retirementBefore = WebRTCPeer.debugIOSPeerRetirementSnapshotForTesting()
        await coordinator.iceStateChanged(.checking)
        let joined = await coordinator.joinPolicyFailureDeliveryForTesting()
        XCTAssertTrue(joined)
        let retired = await viewModel.admitFreshConnectionPreparation()
        XCTAssertTrue(retired) // Joins the real retirement task, peer close and coordinator cancel.
        let retirementAfter = WebRTCPeer.debugIOSPeerRetirementSnapshotForTesting()
        XCTAssertEqual(retirementAfter.retirementAttemptCount, retirementBefore.retirementAttemptCount + 1)
        XCTAssertEqual(retirementAfter.retirementFailureCount, retirementBefore.retirementFailureCount)
        XCTAssertFalse(retirementAfter.processFailureIsLatched)
        XCTAssertEqual(WebRTCPeer.iOSAudioDeviceRetirementAdmissionState(), .available)
        let after = viewModel.debugScreenPresentationState
        XCTAssertFalse(after.hasActiveSession)
        XCTAssertNotEqual(after.sessionGeneration, generation)
        XCTAssertNil(after.currentLease)
        XCTAssertNil(after.activeLease)
        XCTAssertNil(after.recoveringLease)
        XCTAssertFalse(after.isScreenVisible || after.inputAvailable)
        XCTAssertFalse(viewModel.debugScreenPeerIs(peer))
        XCTAssertFalse(viewModel.debugICERecoveryCoordinatorIsForTests(coordinator))
        XCTAssertFalse(fixture.authorization.isValid)
        XCTAssertEqual(viewModel.stateText, "Connection failed")
        XCTAssertEqual(viewModel.lastError, "Secure media recovery evidence is unavailable.")
        let actor = await coordinator.faultDeliverySnapshotForTesting()
        XCTAssertEqual(actor.acceptedStateWords, accepted.acceptedStateWords)
        assertFaultWithoutEffects(actor)
        assertActualCorruptionAndCallback(injection)
        await coordinator.iceStateChanged(.checking)
        await coordinator.cancel()
        let rejoined = await coordinator.joinPolicyFailureDeliveryForTesting()
        XCTAssertTrue(rejoined)
        assertActualCorruptionAndCallback(injection)
        XCTAssertEqual(viewModel.stateText, "Connection failed")
        XCTAssertEqual(viewModel.lastError, "Secure media recovery evidence is unavailable.")
        viewModel.disconnect()
        let cleaned = await viewModel.admitFreshConnectionPreparation()
        XCTAssertTrue(cleaned)
        await peer.close()
    }

    @MainActor
    func testDelayedActualCPolicyFaultCannotRetireReplacementViewerCoordinator() async throws {
        let viewModel = WorldwideSessionViewModel()
        let peerA = try WebRTCPeer(configuration: .init(role: .viewer, iceServers: []))
        let peerB: WebRTCPeer
        do { peerB = try WebRTCPeer(configuration: .init(role: .viewer, iceServers: [])) }
        catch { await peerA.close(); throw error }
        let generationA = UUID(), generationB = UUID()
        viewModel.debugInstallActiveScreenPresentationForTests(peer: peerA, generation: generationA)
        let gate = ICEViewerFaultDeliveryGate()
        let parked = expectation(description: "A fault latched before constructor-installed callback")
        let injection = ICERecoveryCoordinator.CheckingFaultInjectionForTesting {
            parked.fulfill()
            await gate.wait()
        }
        let a = viewModel.debugInstallActualICERecoveryCoordinatorForTests(
            generation: generationA, checkingFaultInjection: injection,
            restart: { throw CancellationError() })
        let accepted = await a.faultDeliverySnapshotForTesting()
        await a.iceStateChanged(.checking)
        await fulfillment(of: [parked], timeout: 1)
        let faulted = await a.faultDeliverySnapshotForTesting()
        XCTAssertEqual(faulted.acceptedStateWords, accepted.acceptedStateWords)
        assertFaultWithoutEffects(faulted)
        XCTAssertEqual(injection.snapshot().callbackStartedCount, 0)
        XCTAssertTrue(viewModel.debugInstallScreenSessionForTests(
            peer: peerB, generation: generationB, bindAudioTransactionDevice: true))
        let fixtureB = viewModel.debugInstallActiveScreenPresentationForTests(peer: peerB, generation: generationB)
        let b = viewModel.debugInstallActualICERecoveryCoordinatorForTests(
            generation: generationB, restart: { throw CancellationError() })
        let before = viewModel.debugScreenPresentationState
        let inputBefore = viewModel.debugRemoteInputState
        let bBefore = await b.faultDeliverySnapshotForTesting()
        XCTAssertNotNil(bBefore.acceptedStateWords)
        XCTAssertFalse(bBefore.bridgeFaulted || bBefore.failureWasDelivered || bBefore.taskOwned)
        let text = viewModel.stateText, error = viewModel.lastError
        await gate.release()
        let joined = await a.joinPolicyFailureDeliveryForTesting()
        XCTAssertTrue(joined) // No negative assertion until the installed stale callback returned.
        let after = viewModel.debugScreenPresentationState
        let bAfter = await b.faultDeliverySnapshotForTesting()
        XCTAssertTrue(viewModel.debugScreenPeerIs(peerB))
        XCTAssertTrue(viewModel.debugICERecoveryCoordinatorIsForTests(b))
        XCTAssertEqual(bAfter, bBefore)
        XCTAssertEqual(after.sessionGeneration, generationB)
        XCTAssertEqual(after.currentLease, before.currentLease)
        XCTAssertEqual(after.activeLease, before.activeLease)
        XCTAssertEqual(after.recoveringLease, before.recoveringLease)
        XCTAssertEqual(after.activeScreenRequestID, before.activeScreenRequestID)
        XCTAssertEqual(after.pendingRequestKey, before.pendingRequestKey)
        XCTAssertEqual(after.displacedPendingRequestCount, before.displacedPendingRequestCount)
        XCTAssertEqual(after.remoteHideRequired, before.remoteHideRequired)
        XCTAssertEqual(viewModel.debugRemoteInputState, inputBefore)
        XCTAssertTrue(after.hasActiveSession && after.isScreenVisible && after.inputAvailable)
        XCTAssertTrue(fixtureB.authorization.isValid)
        XCTAssertTrue(viewModel.remoteInputIsAvailable(for: fixtureB.lease))
        XCTAssertEqual(viewModel.stateText, text)
        XCTAssertEqual(viewModel.lastError, error)
        assertActualCorruptionAndCallback(injection)
        await a.cancel()
        let retirementBefore = WebRTCPeer.debugIOSPeerRetirementSnapshotForTesting()
        viewModel.disconnect()
        let retired = await viewModel.admitFreshConnectionPreparation()
        XCTAssertTrue(retired)
        let retirementAfter = WebRTCPeer.debugIOSPeerRetirementSnapshotForTesting()
        XCTAssertEqual(retirementAfter.retirementAttemptCount, retirementBefore.retirementAttemptCount + 1)
        XCTAssertEqual(retirementAfter.retirementFailureCount, retirementBefore.retirementFailureCount)
        XCTAssertFalse(retirementAfter.processFailureIsLatched)
        XCTAssertEqual(WebRTCPeer.iOSAudioDeviceRetirementAdmissionState(), .available)
        await peerA.close() // A's synthetic peer was displaced, not retained by B's real teardown.
        await peerB.close()
    }

    private func assertFaultWithoutEffects(_ s: ICERecoveryCoordinator.FaultDeliverySnapshotForTesting) {
        XCTAssertTrue(s.bridgeFaulted && s.failureWasDelivered)
        XCTAssertFalse(s.taskOwned)
        XCTAssertEqual(s.nativeRestartCount, 0)
        XCTAssertEqual(s.nativeSleepCount, 0)
        XCTAssertEqual(s.nativeExhaustionCount, 0)
    }
    private func assertActualCorruptionAndCallback(_ injection: ICERecoveryCoordinator.CheckingFaultInjectionForTesting) {
        let s = injection.snapshot()
        XCTAssertEqual(s.actualInitialCount, 1)
        XCTAssertTrue(s.actualInitialAccepted)
        XCTAssertEqual(s.actualStepCount, 1)
        XCTAssertTrue(s.uncorruptedCheckingAccepted)
        XCTAssertEqual(s.corruptionCount, 1)
        XCTAssertEqual(s.callbackStartedCount, 1)
        XCTAssertEqual(s.callbackCompletedCount, 1)
    }
}

private actor ICEViewerFaultDeliveryGate {
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
