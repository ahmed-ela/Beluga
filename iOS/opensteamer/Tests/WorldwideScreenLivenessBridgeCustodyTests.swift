import BelugaCore
import Foundation
import XCTest
@testable import WebRTCTransport
@testable import opensteamer

final class WorldwideScreenLivenessBridgeCustodyTests: XCTestCase {
    @MainActor
    private func withModel(
        _ body: @MainActor (
            WorldwideSessionViewModel, WebRTCPeer, WorldwideScreenPresentationDebugFixture
        ) async throws -> Void
    ) async throws {
        let peer = try WebRTCPeer(configuration:
            WebRTCTransportConfiguration(role:.viewer,iceServers:[]))
        let model = WorldwideSessionViewModel()
        let generation = UUID()
        XCTAssertTrue(model.debugInstallScreenSessionForTests(
            peer: peer, generation: generation, bindAudioTransactionDevice: true))
        let fixture = model.debugInstallActiveScreenPresentationForTests(
            peer: peer, generation: generation)
        model.handleAppBecameActive()
        let producer = BelugaRustScreenLivenessProducer(observe:{abi,before,input in
            var actual = beluga_core_screen_liveness_observe(abi,before,input)
            if input.observed_at == 2 { actual.snapshot.generation ^= 1 }
            return actual
        })
        model.debugInstallScreenLivenessClassifier(
            WorldwideScreenLivenessClassifier(producer:producer))
        model.debugInstallScreenLivenessUptimeClock { 1 }
        model.debugRefreshScreenLivenessDiagnosticForTests()
        @MainActor
        func retireOwnedModel() async {
            let retirementBefore = WebRTCPeer.debugIOSPeerRetirementSnapshotForTesting()
            model.disconnect()
            let retired = await model.admitFreshConnectionPreparation()
            XCTAssertTrue(retired)
            let retirementAfter = WebRTCPeer.debugIOSPeerRetirementSnapshotForTesting()
            XCTAssertEqual(retirementAfter.retirementAttemptCount, retirementBefore.retirementAttemptCount + 1)
            XCTAssertEqual(retirementAfter.retirementFailureCount, retirementBefore.retirementFailureCount)
            XCTAssertFalse(retirementAfter.processFailureIsLatched)
            XCTAssertEqual(WebRTCPeer.iOSAudioDeviceRetirementAdmissionState(), .available)
            await peer.close()
        }
        do { try await body(model,peer,fixture) }
        catch { await retireOwnedModel(); throw error }
        await retireOwnedModel()
    }

    @MainActor
    private func assertOwnershipUnchanged(
        _ model: WorldwideSessionViewModel,
        _ before: WorldwideScreenPresentationDebugState,
        _ fixture: WorldwideScreenPresentationDebugFixture,
        _ peer: WebRTCPeer,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let after = model.debugScreenPresentationState
        XCTAssertEqual(after.sessionGeneration,before.sessionGeneration,file:file,line:line)
        XCTAssertEqual(after.currentLease,before.currentLease,file:file,line:line)
        XCTAssertEqual(after.activeLease,before.activeLease,file:file,line:line)
        XCTAssertEqual(after.recoveringLease,before.recoveringLease,file:file,line:line)
        XCTAssertEqual(after.activeScreenRequestID,before.activeScreenRequestID,file:file,line:line)
        XCTAssertEqual(after.isScreenVisible,before.isScreenVisible,file:file,line:line)
        XCTAssertEqual(after.inputAvailable,before.inputAvailable,file:file,line:line)
        XCTAssertEqual(after.remoteHideRequired,before.remoteHideRequired,file:file,line:line)
        XCTAssertEqual(after.pendingRequestKey,before.pendingRequestKey,file:file,line:line)
        XCTAssertEqual(after.hasActiveSession,before.hasActiveSession,file:file,line:line)
        XCTAssertTrue(fixture.authorization.isValid,file:file,line:line)
        XCTAssertTrue(model.debugScreenPeerIs(peer),file:file,line:line)
    }

    @MainActor
    func testBridgeFaultRetainsExplicitlyStaleEvidenceRefusesHeartbeatAndSuccessfulObservationRecovers() async throws {
        try await withModel { model,peer,fixture in
            var negotiatedReads = 0
            var delivered: [WebRTCScreenClientDiagnosticsHeartbeat] = []
            model.debugInstallScreenClientDiagnosticsNegotiatedReader { candidate in
                XCTAssertTrue(candidate === peer); negotiatedReads += 1; return true
            }
            model.debugInstallScreenClientDiagnosticsHeartbeatSender { candidate,heartbeat in
                XCTAssertTrue(candidate === peer); delivered.append(heartbeat)
            }
            let owned = model.debugScreenPresentationState
            let evidence = model.screenLivenessDiagnosticSnapshot
            let sequence = model.debugScreenClientDiagnosticsNextSequence
            model.debugInstallScreenLivenessUptimeClock { 2 }
            model.debugRefreshScreenLivenessDiagnosticForTests()
            XCTAssertEqual(model.screenLivenessBridgeError,.invalidBridge)
            XCTAssertEqual(model.screenLivenessDiagnosticSnapshot,evidence)
            XCTAssertEqual(model.screenLivenessStatusText,"Client screen evidence unavailable")
            XCTAssertEqual(model.screenClientDiagnosticsDeliveryText,"Local evidence unavailable")
            assertOwnershipUnchanged(model,owned,fixture,peer)
            await model.debugSendScreenClientDiagnosticsHeartbeatForTests()
            XCTAssertEqual(negotiatedReads,0)
            XCTAssertTrue(delivered.isEmpty)
            XCTAssertEqual(model.debugScreenClientDiagnosticsNextSequence,sequence)
            assertOwnershipUnchanged(model,owned,fixture,peer)

            model.debugInstallScreenLivenessUptimeClock { 3 }
            model.debugRefreshScreenLivenessDiagnosticForTests()
            XCTAssertNil(model.screenLivenessBridgeError)
            XCTAssertEqual(model.screenLivenessStatusText,model.screenLivenessDiagnosticSnapshot.statusText)
            await model.debugSendScreenClientDiagnosticsHeartbeatForTests()
            XCTAssertEqual(negotiatedReads,1); XCTAssertEqual(delivered.count,1)
            XCTAssertEqual(delivered.first?.sequence,sequence)
            XCTAssertEqual(model.debugScreenClientDiagnosticsNextSequence,sequence+1)
            XCTAssertEqual(model.screenClientDiagnosticsDeliveryText,"Reporting to Mac")
            assertOwnershipUnchanged(model,owned,fixture,peer)
        }
    }

    @MainActor
    func testBridgeFaultDuringNegotiationCannotReportRetainedSnapshotOrBurnSequence() async throws {
        try await withModel { model,peer,fixture in
            var delivered = 0
            model.debugInstallScreenClientDiagnosticsNegotiatedReader { candidate in
                XCTAssertTrue(candidate === peer)
                model.debugInstallScreenLivenessUptimeClock { 2 }
                model.debugRefreshScreenLivenessDiagnosticForTests()
                return true
            }
            model.debugInstallScreenClientDiagnosticsHeartbeatSender { _,_ in delivered += 1 }
            let owned = model.debugScreenPresentationState
            let evidence = model.screenLivenessDiagnosticSnapshot
            let sequence = model.debugScreenClientDiagnosticsNextSequence
            await model.debugSendScreenClientDiagnosticsHeartbeatForTests()
            XCTAssertEqual(model.screenLivenessBridgeError,.invalidBridge)
            XCTAssertEqual(model.screenLivenessDiagnosticSnapshot,evidence)
            XCTAssertEqual(delivered,0)
            XCTAssertEqual(model.debugScreenClientDiagnosticsNextSequence,sequence)
            XCTAssertEqual(model.screenClientDiagnosticsDeliveryText,"Local evidence unavailable")
            assertOwnershipUnchanged(model,owned,fixture,peer)
        }
    }

    @MainActor
    func testLaterFaultCannotTurnAcceptedSendCompletionIntoCurrentEvidenceStatus() async throws {
        try await withModel { model,peer,fixture in
            var delivered: [WebRTCScreenClientDiagnosticsHeartbeat] = []
            model.debugInstallScreenClientDiagnosticsNegotiatedReader { _ in true }
            model.debugInstallScreenClientDiagnosticsHeartbeatSender { _,heartbeat in
                delivered.append(heartbeat)
                model.debugInstallScreenLivenessUptimeClock { 2 }
                model.debugRefreshScreenLivenessDiagnosticForTests()
            }
            let owned = model.debugScreenPresentationState
            let sequence = model.debugScreenClientDiagnosticsNextSequence
            await model.debugSendScreenClientDiagnosticsHeartbeatForTests()
            XCTAssertEqual(delivered.count,1)
            // Send was already invoked; reservation must not be rolled back.
            XCTAssertEqual(model.debugScreenClientDiagnosticsNextSequence,sequence+1)
            XCTAssertEqual(model.screenLivenessBridgeError,.invalidBridge)
            XCTAssertEqual(model.screenClientDiagnosticsDeliveryText,"Local evidence unavailable")
            assertOwnershipUnchanged(model,owned,fixture,peer)
        }
    }
    @MainActor
    func testBridgeFaultDuringFalseNegotiationRetainsUnavailableStatusWithoutSendOrSequence() async throws {
        try await withModel { model,peer,fixture in
            var negotiatedReads = 0
            var delivered = 0
            model.debugInstallScreenClientDiagnosticsNegotiatedReader { candidate in
                XCTAssertTrue(candidate === peer)
                negotiatedReads += 1
                model.debugInstallScreenLivenessUptimeClock { 2 }
                model.debugRefreshScreenLivenessDiagnosticForTests()
                return false
            }
            model.debugInstallScreenClientDiagnosticsHeartbeatSender { _,_ in delivered += 1 }
            let owned = model.debugScreenPresentationState
            let evidence = model.screenLivenessDiagnosticSnapshot
            let sequence = model.debugScreenClientDiagnosticsNextSequence
            await model.debugSendScreenClientDiagnosticsHeartbeatForTests()
            XCTAssertEqual(negotiatedReads,1)
            XCTAssertEqual(model.screenLivenessBridgeError,.invalidBridge)
            XCTAssertEqual(model.screenLivenessDiagnosticSnapshot,evidence)
            XCTAssertEqual(model.screenLivenessStatusText,"Client screen evidence unavailable")
            XCTAssertEqual(model.screenClientDiagnosticsDeliveryText,"Local evidence unavailable")
            XCTAssertEqual(delivered,0)
            XCTAssertEqual(model.debugScreenClientDiagnosticsNextSequence,sequence)
            assertOwnershipUnchanged(model,owned,fixture,peer)
        }
    }

    @MainActor
    func testLaterFaultCannotTurnThrowingSendCompletionIntoHeartbeatUnavailableStatus() async throws {
        try await withModel { model,peer,fixture in
            var delivered: [WebRTCScreenClientDiagnosticsHeartbeat] = []
            model.debugInstallScreenClientDiagnosticsNegotiatedReader { _ in true }
            model.debugInstallScreenClientDiagnosticsHeartbeatSender { _,heartbeat in
                delivered.append(heartbeat)
                model.debugInstallScreenLivenessUptimeClock { 2 }
                model.debugRefreshScreenLivenessDiagnosticForTests()
                throw LivenessCustodySendFailure.expected
            }
            let owned = model.debugScreenPresentationState
            let evidence = model.screenLivenessDiagnosticSnapshot
            let sequence = model.debugScreenClientDiagnosticsNextSequence
            await model.debugSendScreenClientDiagnosticsHeartbeatForTests()
            XCTAssertEqual(delivered.count,1)
            XCTAssertEqual(model.debugScreenClientDiagnosticsNextSequence,sequence+1)
            XCTAssertEqual(model.screenLivenessBridgeError,.invalidBridge)
            XCTAssertEqual(model.screenLivenessDiagnosticSnapshot,evidence)
            XCTAssertEqual(model.screenLivenessStatusText,"Client screen evidence unavailable")
            XCTAssertEqual(model.screenClientDiagnosticsDeliveryText,"Local evidence unavailable")
            assertOwnershipUnchanged(model,owned,fixture,peer)
        }
    }
}

private enum LivenessCustodySendFailure: Error {
    case expected
}
