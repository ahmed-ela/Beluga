// PROSPECTIVE RECEIVER TESTS. Actual view model/native peers; no live ICE or media.
import Foundation
import XCTest
@testable import WebRTCTransport
@testable import opensteamer

final class WorldwideICERecoveryPolicyReceiverTests: XCTestCase {
    @MainActor
    func testCurrentPolicyFaultClearsActualViewerAndJoinsNativeRetirement() async throws {
        let viewModel = WorldwideSessionViewModel()
        let peer = try WebRTCPeer(
            configuration: WebRTCTransportConfiguration(role: .viewer, iceServers: []))
        let generation = UUID()
        XCTAssertTrue(viewModel.debugInstallScreenSessionForTests(
            peer: peer, generation: generation, bindAudioTransactionDevice: true))
        let fixture = viewModel.debugInstallActiveScreenPresentationForTests(
            peer: peer, generation: generation)
        let before = viewModel.debugScreenPresentationState
        XCTAssertEqual(before.sessionGeneration, generation)
        XCTAssertTrue(before.hasActiveSession)
        XCTAssertTrue(fixture.authorization.isValid)
        XCTAssertTrue(viewModel.remoteInputIsAvailable(for: fixture.lease))
        // Transport is healthy, so ordinary exhaustion's uncertain-transport guard would return.
        let retirementBefore = WebRTCPeer.debugIOSPeerRetirementSnapshotForTesting()
        viewModel.debugDeliverICERecoveryPolicyFaultForTests(generation: generation)

        let after = viewModel.debugScreenPresentationState
        XCTAssertFalse(after.hasActiveSession)
        XCTAssertNotEqual(after.sessionGeneration, generation)
        XCTAssertNil(after.currentLease)
        XCTAssertNil(after.activeLease)
        XCTAssertNil(after.recoveringLease)
        XCTAssertFalse(after.isScreenVisible)
        XCTAssertFalse(after.inputAvailable)
        XCTAssertFalse(viewModel.debugScreenPeerIs(peer))
        XCTAssertFalse(fixture.authorization.isValid)
        XCTAssertEqual(viewModel.stateText, "Connection failed")
        XCTAssertEqual(viewModel.lastError, "Secure media recovery evidence is unavailable.")
        // This existing production admission barrier awaits the exact retiring peer/signaling
        // task and coordinator cancellation; an arbitrary yield is not a cleanup witness.
        let retired = await viewModel.admitFreshConnectionPreparation()
        XCTAssertTrue(retired)
        let retirementAfter = WebRTCPeer.debugIOSPeerRetirementSnapshotForTesting()
        XCTAssertEqual(retirementAfter.retirementAttemptCount, retirementBefore.retirementAttemptCount + 1)
        XCTAssertEqual(retirementAfter.retirementFailureCount, retirementBefore.retirementFailureCount)
        XCTAssertFalse(retirementAfter.processFailureIsLatched)
        XCTAssertEqual(WebRTCPeer.iOSAudioDeviceRetirementAdmissionState(), .available)
        viewModel.debugDeliverICERecoveryPolicyFaultForTests(generation: generation)
        XCTAssertEqual(viewModel.stateText, "Connection failed")
        XCTAssertEqual(viewModel.lastError, "Secure media recovery evidence is unavailable.")

        viewModel.disconnect()
        let cleanup = await viewModel.admitFreshConnectionPreparation()
        XCTAssertTrue(cleanup)
        await peer.close()
    }

    @MainActor
    func testCapturedOldPolicyFaultCannotCloseReplacementViewer() async throws {
        let viewModel = WorldwideSessionViewModel()
        let peerA = try WebRTCPeer(
            configuration: WebRTCTransportConfiguration(role: .viewer, iceServers: []))
        let peerB: WebRTCPeer
        do {
            peerB = try WebRTCPeer(
                configuration: WebRTCTransportConfiguration(role: .viewer, iceServers: []))
        } catch {
            await peerA.close()
            throw error
        }
        let generationA = UUID()
        let generationB = UUID()
        viewModel.debugInstallActiveScreenPresentationForTests(peer: peerA, generation: generationA)
        XCTAssertTrue(viewModel.debugInstallScreenSessionForTests(
            peer: peerB, generation: generationB, bindAudioTransactionDevice: true))
        let fixtureB = viewModel.debugInstallActiveScreenPresentationForTests(
            peer: peerB, generation: generationB)
        let before = viewModel.debugScreenPresentationState
        let beforeText = viewModel.stateText
        let beforeError = viewModel.lastError
        XCTAssertTrue(fixtureB.authorization.isValid)
        XCTAssertTrue(viewModel.remoteInputIsAvailable(for: fixtureB.lease))

        // Captured A delivery occurs only after B's actual peer/generation/lease is installed.
        viewModel.debugDeliverICERecoveryPolicyFaultForTests(generation: generationA)
        let after = viewModel.debugScreenPresentationState
        XCTAssertEqual(after.sessionGeneration, generationB)
        XCTAssertEqual(after.currentLease, before.currentLease)
        XCTAssertEqual(after.activeLease, before.activeLease)
        XCTAssertEqual(after.recoveringLease, before.recoveringLease)
        XCTAssertEqual(after.activeScreenRequestID, before.activeScreenRequestID)
        XCTAssertEqual(after.remoteHideRequired, before.remoteHideRequired)
        XCTAssertEqual(after.pendingRequestKey, before.pendingRequestKey)
        XCTAssertEqual(after.displacedPendingRequestCount, before.displacedPendingRequestCount)
        XCTAssertTrue(after.hasActiveSession)
        XCTAssertTrue(after.isScreenVisible)
        XCTAssertTrue(after.inputAvailable)
        XCTAssertTrue(viewModel.debugScreenPeerIs(peerB))
        XCTAssertTrue(fixtureB.authorization.isValid)
        XCTAssertTrue(viewModel.remoteInputIsAvailable(for: fixtureB.lease))
        XCTAssertEqual(viewModel.stateText, beforeText)
        XCTAssertEqual(viewModel.lastError, beforeError)

        let retirementBefore = WebRTCPeer.debugIOSPeerRetirementSnapshotForTesting()
        viewModel.disconnect()
        let retired = await viewModel.admitFreshConnectionPreparation()
        XCTAssertTrue(retired)
        let retirementAfter = WebRTCPeer.debugIOSPeerRetirementSnapshotForTesting()
        XCTAssertEqual(retirementAfter.retirementAttemptCount, retirementBefore.retirementAttemptCount + 1)
        XCTAssertEqual(retirementAfter.retirementFailureCount, retirementBefore.retirementFailureCount)
        XCTAssertFalse(retirementAfter.processFailureIsLatched)
        XCTAssertEqual(WebRTCPeer.iOSAudioDeviceRetirementAdmissionState(), .available)
        await peerA.close() // replaced synthetic fixture was never owned by B's retirement
        await peerB.close()
    }
}
