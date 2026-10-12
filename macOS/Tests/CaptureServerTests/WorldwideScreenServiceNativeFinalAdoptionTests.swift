// SOURCE-ONLY proposal: current actual704/custody API and genuine actor fixture.
// Uncompiled/unexecuted. Six literal methods; stale methods have serial matrices.
import Foundation
import XCTest
@testable import CaptureServer
@testable import WebRTCTransport

@MainActor
final class WorldwideScreenServiceNativeFinalAdoptionTests: XCTestCase {
    private typealias Path = WorldwideScreenService.Native704FixturePath
    private typealias Cut = WorldwideScreenService.Native704FixtureCut
    private typealias Observation = WorldwideScreenService.Native704FixtureObservation
    private typealias Snapshot = WorldwideScreenService.NativeOwnerPublicationSnapshotObservation

    private func run(_ path: Path, _ cut: Cut) async throws -> Observation {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1" else {
            throw XCTSkip("Owned fresh network-denied process and clean sticky route monitor required")
        }
        let f = try BatchAActualServiceFixture(profile: .secondaryTest)
        do {
            let v = try await f.service.native704FixtureObservationForTesting(path: path, cut: cut,
                readNative: { peer in
                    .init(peer: .init(topology: await peer.mediaTopologyForTesting,
                        externalAudioIsAbsent: peer.externalAudioCapturer == nil,
                        encodingGeneration: await peer.screenVideoEncodingMutationGenerationForTesting(),
                        limits: await peer.screenVideoEncodingLimitsForTesting(),
                        totalCeiling: await peer.maximumTotalRTPBitrateBpsForTesting(),
                        encodingActivity: await peer.screenVideoEncodingActivityForTesting()),
                        senderApplyInvocations: await peer.screenVideoEncodingApplyInvocationCountForTesting(),
                        outputAdaptInvocations: peer.externalVideoCapturer?.outputAdaptInvocationCountForTesting())
                })
            await f.service.stop()
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)
            XCTAssertEqual(f.hal.inputUID, "BuiltInMic_UID")
            XCTAssertTrue(v.cleanupSourceStopped)
            XCTAssertTrue(v.cleanupPeerClosed)
            XCTAssertTrue(v.cleanupFieldsAreAbsent)
            XCTAssertTrue(v.cleanupAuthorizationsAreRevoked)
            XCTAssertEqual(v.nativeBeforeFinal.peer.topology, .videoControlOnly)
            XCTAssertTrue(v.nativeBeforeFinal.peer.externalAudioIsAbsent)
            XCTAssertNotNil(v.nativeBeforeFinal.outputAdaptInvocations)
            XCTAssertLessThanOrEqual(v.nativeBeforeFinal.senderApplyInvocations, 2)
            XCTAssertLessThanOrEqual(try XCTUnwrap(v.nativeBeforeFinal.outputAdaptInvocations), 2)
            // Actual wrapper method-entry/dispatch counters, not invented zeros,
            // SDK acceptance, frames or BWE throughput. Full peer readback exact.
            XCTAssertEqual(v.nativeAfterFinal, v.nativeBeforeFinal)
            XCTAssertEqual(v.nativeAfterReplay, v.nativeAfterFinal)
            XCTAssertEqual(v.successDispatchAfterFinal, v.successDispatchBeforeFinal)
            XCTAssertEqual(v.successDispatchAfterReplay, v.successDispatchAfterFinal)
            XCTAssertFalse(v.codecUseSpentBeforeFinal)
            XCTAssertTrue(v.nativeEntryAvailableBeforeFinal)
            XCTAssertTrue(v.codecUseSpentAfterFinal)
            XCTAssertTrue(v.nativeEntryUnavailableAfterFinal)
            XCTAssertTrue(v.codecUseSpentAfterReplay)
            XCTAssertTrue(v.nativeEntryUnavailableAfterReplay)
            XCTAssertTrue(v.replayRefused)
            XCTAssertEqual(v.afterReplay, v.afterFinal)
            XCTAssertEqual(v.ownerBeforeStaleCut.atoms.count, 179)
            guard v.ownerBeforeStaleCut.atoms.count == 179 else { return v }
            XCTAssertEqual(v.ownerBeforeStaleCut.atoms[168].low, v.preparedApplyingRevision)
            switch path {
            case .success:
                XCTAssertNil(v.noApplyCompletionReplayRefused)
                XCTAssertEqual(v.nativeBeforeRun.senderApplyInvocations, 0)
                XCTAssertEqual(v.nativeBeforeRun.outputAdaptInvocations, 0)
                XCTAssertEqual(v.nativeAfterRun.senderApplyInvocations, 1)
                XCTAssertEqual(v.nativeAfterRun.outputAdaptInvocations, 0)
                XCTAssertEqual(v.nativeAfterRun.peer.encodingGeneration, v.nativeBeforeRun.peer.encodingGeneration &+ 1)
                XCTAssertEqual(v.nativeBeforeFinal.senderApplyInvocations, 1)
                XCTAssertEqual(v.nativeBeforeFinal.outputAdaptInvocations, 1)
                XCTAssertEqual(v.successDispatchBeforeFinal?.calls, 1)
                XCTAssertEqual(v.successDispatchBeforeFinal?.stores, 1)
                XCTAssertEqual(v.successDispatchBeforeFinal?.rollbackDispatches, 0)
            case .noApply:
                XCTAssertEqual(v.noApplyCompletionReplayRefused, true)
                XCTAssertEqual(v.nativeAfterRun, v.nativeBeforeRun,
                    "Genuine noApply run must not call native sender/FPS")
                XCTAssertEqual(v.nativeBeforeRun.senderApplyInvocations, 1,
                    "Setup count belongs to one genuine original-path warmup")
                XCTAssertEqual(v.nativeBeforeRun.outputAdaptInvocations, 1)
                XCTAssertNil(v.successDispatchBeforeFinal)
                XCTAssertNil(v.successDispatchAfterFinal)
                XCTAssertNil(v.successDispatchAfterReplay)
            }
            return v
        } catch {
            await f.service.stop()
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)
            throw error
        }
    }
    private func assertOnlyRevisionAdvance(_ before: Snapshot, _ after: Snapshot,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(before.atoms.count, 179, file: file, line: line)
        XCTAssertEqual(after.atoms.count, 179, file: file, line: line)
        guard before.atoms.count == 179, after.atoms.count == 179 else { return }
        XCTAssertEqual(Array(after.atoms.prefix(168)), Array(before.atoms.prefix(168)), file: file, line: line)
        XCTAssertEqual(Array(after.atoms.suffix(10)), Array(before.atoms.suffix(10)), file: file, line: line)
        XCTAssertEqual(after.atoms[168].kind, before.atoms[168].kind, file: file, line: line)
        XCTAssertEqual(after.atoms[168].present, before.atoms[168].present, file: file, line: line)
        XCTAssertEqual(after.atoms[168].high, before.atoms[168].high, file: file, line: line)
        XCTAssertEqual(after.atoms[168].low, before.atoms[168].low &+ 1, file: file, line: line)
        XCTAssertEqual(after.times, before.times, file: file, line: line)
        XCTAssertEqual(after.anchor, before.anchor, file: file, line: line)
        XCTAssertEqual(after.route, before.route, file: file, line: line)
    }
    private func assertCurrentAdoption(_ v: Observation, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(v.result, .adopted, file: file, line: line)
        XCTAssertEqual(v.beforeFinal, v.ownerBeforeStaleCut, file: file, line: line)
        XCTAssertEqual(v.beforeFinal.atoms.count, 179, file: file, line: line)
        XCTAssertEqual(v.afterFinal.atoms.count, 179, file: file, line: line)
        XCTAssertEqual(v.preparedPolicyAtoms.count, 168, file: file, line: line)
        XCTAssertEqual(v.preparedNativeTimes.count, 9, file: file, line: line)
        XCTAssertEqual(v.beforeFinal.times.count, 13, file: file, line: line)
        XCTAssertEqual(v.afterFinal.times.count, 13, file: file, line: line)
        guard v.beforeFinal.atoms.count == 179, v.afterFinal.atoms.count == 179 else { return }
        // Compare actual output against ORIGINAL genuine Prepared donor values;
        // do not construct/supply a copied final Owner or expected native receipt.
        XCTAssertEqual(Array(v.afterFinal.atoms.prefix(168)), v.preparedPolicyAtoms, file: file, line: line)
        XCTAssertEqual(v.afterFinal.atoms[168].kind, 1, file: file, line: line)
        XCTAssertEqual(v.afterFinal.atoms[168].present, 1, file: file, line: line)
        XCTAssertEqual(v.afterFinal.atoms[168].high, 0, file: file, line: line)
        XCTAssertEqual(v.afterFinal.atoms[168].low, v.beforeFinal.atoms[168].low &+ 1, file: file, line: line)
        XCTAssertEqual(Array(v.afterFinal.atoms.suffix(10)), Array(v.beforeFinal.atoms.suffix(10)), file: file, line: line)
        XCTAssertEqual(Array(v.afterFinal.times.prefix(9)), v.preparedNativeTimes, file: file, line: line)
        XCTAssertEqual(Array(v.afterFinal.times.suffix(4)), Array(v.beforeFinal.times.suffix(4)), file: file, line: line)
        XCTAssertEqual(v.afterFinal.anchor, v.beforeFinal.anchor, file: file, line: line)
        switch v.preparedRouteAction {
        case .retain: XCTAssertEqual(v.afterFinal.route, v.beforeFinal.route, file: file, line: line)
        case .clear: XCTAssertNil(v.afterFinal.route, file: file, line: line)
        case .copyIncoming: XCTAssertEqual(v.afterFinal.route, v.preparedIncomingRoute, file: file, line: line)
        }
    }
    private func assertStaleMatrix(_ path: Path) async throws {
        let cuts: [Cut] = [.peerAbsent, .generationAdvanced, .revisionAdvanced]
        for cut in cuts {
            let v = try await run(path, cut)
            XCTAssertEqual(v.result, .superseded)
            if cut == .revisionAdvanced {
                assertOnlyRevisionAdvance(v.ownerBeforeStaleCut, v.beforeFinal)
            } else { XCTAssertEqual(v.beforeFinal, v.ownerBeforeStaleCut) }
            XCTAssertEqual(v.afterFinal, v.beforeFinal,
                "Actual704 stale fence preserves complete179+13/time/route/anchor")
        }
    }
    func testActualNative704SuccessfulApplyAdoptsPreparedPolicyOnceWithoutNewSenderOrFPS() async throws {
        let v = try await run(.success, .current)
        assertCurrentAdoption(v)
        // Real unnegotiated peer report is nil-route; first original peer bind
        // legitimately selects Clear. Fail if this genuine input changes.
        XCTAssertNil(v.preparedIncomingRoute)
        XCTAssertEqual(v.preparedRouteAction, .clear)
    }
    func testActualNative704NoApplyAdoptsPreparedPolicyOnceWithoutNewSenderOrFPS() async throws {
        let v = try await run(.noApply, .current)
        assertCurrentAdoption(v)
        // After genuine original warmup, the second genuine no-route report
        // retains native nil. No CopyIncoming(nil) Prepared is manufactured.
        XCTAssertNil(v.preparedIncomingRoute)
        XCTAssertEqual(v.preparedRouteAction, .retain)
    }
    func testActualNative704SuccessfulApplyThreeStaleFencesPreserveEntireOwner() async throws {
        try await assertStaleMatrix(.success)
    }
    func testActualNative704NoApplyThreeStaleFencesPreserveEntireOwner() async throws {
        try await assertStaleMatrix(.noApply)
    }
    func testActualNative704SuccessfulApplyWrongBoundaryBurnsBothUsesWithoutOwnerOrNativeEffects() async throws {
        let v = try await run(.success, .wrongBoundary)
        XCTAssertEqual(v.result, .refused)
        XCTAssertEqual(v.beforeFinal, v.ownerBeforeStaleCut)
        XCTAssertEqual(v.afterFinal, v.beforeFinal)
    }
    func testActualNative704NoApplyWrongBoundaryBurnsBothUsesWithoutOwnerOrNativeEffects() async throws {
        let v = try await run(.noApply, .wrongBoundary)
        XCTAssertEqual(v.result, .refused)
        XCTAssertEqual(v.beforeFinal, v.ownerBeforeStaleCut)
        XCTAssertEqual(v.afterFinal, v.beforeFinal)
    }
}
