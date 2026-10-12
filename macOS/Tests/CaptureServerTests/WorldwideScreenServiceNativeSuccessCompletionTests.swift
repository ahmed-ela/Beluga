import Foundation
import XCTest
@testable import CaptureServer
@testable import WebRTCTransport

@MainActor
final class WorldwideScreenServiceNativeSuccessCompletionTests: XCTestCase {
    private typealias Case = WorldwideScreenService.Native702FixtureCase
    private typealias Observation = WorldwideScreenService.Native702FixtureObservation
    private typealias Snapshot = WorldwideScreenService.NativeOwnerPublicationSnapshotObservation
    private typealias Atom = WorldwideScreenService.NativeOwnerPublicationAtomObservation

    private func run(_ selectedCase: Case) async throws -> Observation {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1" else {
            throw XCTSkip("Owned fresh network-denied process and clean sticky route monitor required")
        }
        let fixture = try BatchAActualServiceFixture(profile: .secondaryTest)
        do {
            let v = try await fixture.service.native702FixtureObservationForTesting(
                selectedCase: selectedCase, readNative: { peer in
                    .init(topology: await peer.mediaTopologyForTesting,
                        externalAudioIsAbsent: peer.externalAudioCapturer == nil,
                        encodingGeneration: await peer.screenVideoEncodingMutationGenerationForTesting(),
                        limits: await peer.screenVideoEncodingLimitsForTesting(),
                        totalCeiling: await peer.maximumTotalRTPBitrateBpsForTesting(),
                        encodingActivity: await peer.screenVideoEncodingActivityForTesting())
                })
            await fixture.service.stop()
            XCTAssertTrue(fixture.hal.inputWrites.isEmpty)
            XCTAssertEqual(fixture.hal.listenerCount, 0)
            XCTAssertEqual(fixture.hal.inputUID, "BuiltInMic_UID")
            XCTAssertTrue(v.cleanupSourceStopped)
            XCTAssertTrue(v.cleanupPeerClosed)
            XCTAssertTrue(v.cleanupFieldsAreAbsent)
            XCTAssertTrue(v.cleanupAuthorizationsAreRevoked)
            XCTAssertEqual(v.nativeBeforeSDK.topology, .videoControlOnly)
            XCTAssertEqual(v.nativeAfterSDK.topology, .videoControlOnly)
            XCTAssertTrue(v.nativeBeforeSDK.externalAudioIsAbsent)
            XCTAssertTrue(v.nativeAfterSDK.externalAudioIsAbsent)
            XCTAssertEqual(v.nativeBeforeSDK.encodingActivity, v.nativeAfterSDK.encodingActivity)
            XCTAssertEqual(v.nativeAfter702, v.nativeAfterSDK, "702 does not reapply native sender ceilings")
            XCTAssertEqual(v.nativeAfterReplay, v.nativeAfter702)
            XCTAssertTrue(v.completionReplayRefused)
            XCTAssertTrue(v.primaryTraceIdentityRetained, "replay must not replace/reset dispatch/store evidence")
            XCTAssertEqual(v.primaryDispatchAfterReplay, v.primaryDispatch)
            XCTAssertEqual(v.afterReplay, v.afterSecondary ?? v.afterPrimary)
            return v
        } catch {
            await fixture.service.stop()
            XCTAssertTrue(fixture.hal.inputWrites.isEmpty)
            XCTAssertEqual(fixture.hal.listenerCount, 0)
            throw error
        }
    }
    private func assertOnlyAppliedTail(_ before: Snapshot, _ after: Snapshot,
        expected: [Atom], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(before.atoms.count, 179, file: file, line: line)
        XCTAssertEqual(after.atoms.count, 179, file: file, line: line)
        XCTAssertEqual(expected.count, 6, file: file, line: line)
        guard before.atoms.count == 179, after.atoms.count == 179 else { return }
        XCTAssertEqual(Array(after.atoms.prefix(173)), Array(before.atoms.prefix(173)), file: file, line: line)
        XCTAssertEqual(Array(after.atoms.suffix(6)), expected, file: file, line: line)
        XCTAssertEqual(before.times.count, 13, file: file, line: line)
        XCTAssertEqual(after.times, before.times, file: file, line: line)
        XCTAssertEqual(after.anchor, before.anchor, file: file, line: line)
        XCTAssertEqual(after.route, before.route, file: file, line: line)
    }
    private func assertRolledBackExactly(_ v: Observation, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(v.cleanupSucceeded, true, file: file, line: line)
        XCTAssertEqual(v.cleanupReplayRefused, true, file: file, line: line)
        let restored = try XCTUnwrap(v.nativeAfterCleanup, file: file, line: line)
        XCTAssertEqual(restored.limits, v.nativeBeforeSDK.limits, file: file, line: line)
        XCTAssertEqual(restored.totalCeiling, v.nativeBeforeSDK.totalCeiling, file: file, line: line)
        XCTAssertEqual(restored.encodingActivity, v.nativeBeforeSDK.encodingActivity, file: file, line: line)
        XCTAssertEqual(restored.encodingGeneration, v.nativeAfterSDK.encodingGeneration &+ 1, file: file, line: line)
        XCTAssertEqual(v.nativeAfterCleanupReplay, restored, file: file, line: line)
        XCTAssertEqual(v.primaryDispatch.calls, 0, file: file, line: line)
        XCTAssertEqual(v.primaryDispatch.stores, 0, file: file, line: line)
        XCTAssertEqual(v.primaryDispatchAfterCleanupReplay.calls, 0, file: file, line: line)
        XCTAssertEqual(v.primaryDispatchAfterCleanupReplay.stores, 0, file: file, line: line)
        XCTAssertEqual(v.primaryDispatchAfterCleanupReplay.rollbackDispatches, 1, file: file, line: line)
        XCTAssertEqual(v.ownerAfterCleanup, v.afterReplay, file: file, line: line)
        XCTAssertEqual(v.ownerAfterCleanupReplay, v.afterReplay, file: file, line: line)
        XCTAssertEqual(v.finalReceiptCount, 0, file: file, line: line)
    }

    func testActualNative702AbsentAppliedAcceptsOnlyAppliedTailAndOneOriginalDispatch() async throws {
        let v = try await run(.absentApplied)
        XCTAssertEqual(v.primaryResult, .accepted)
        XCTAssertEqual(v.beforePrimary.atoms[173].low, 0)
        assertOnlyAppliedTail(v.beforePrimary, v.afterPrimary, expected: v.expectedPrimaryAppliedTail)
        XCTAssertEqual(v.primaryDispatch.calls, 1)
        XCTAssertEqual(v.primaryDispatch.stores, 1)
        XCTAssertEqual(v.primaryDispatch.rollbackDispatches, 0)
        XCTAssertEqual(v.primaryDispatch.width, 320)
        XCTAssertEqual(v.primaryDispatch.height, 180)
        XCTAssertEqual(v.primaryDispatch.fps, Int32(exactly: v.requestedLimits.maximumFramesPerSecond))
        XCTAssertEqual(v.finalReceiptCount, 1)
        XCTAssertNil(v.secondaryResult)
        XCTAssertNil(v.cleanupSucceeded)
        XCTAssertEqual(v.nativeAfterSDK.encodingGeneration, v.nativeBeforeSDK.encodingGeneration &+ 1)
    }
    func testActualNative702SameFPSAcceptsWithoutRepeatingOriginalDispatch() async throws {
        let v = try await run(.sameFPS)
        XCTAssertEqual(v.primaryResult, .accepted)
        XCTAssertEqual(v.secondaryResult, .accepted)
        assertOnlyAppliedTail(v.beforePrimary, v.afterPrimary, expected: v.expectedPrimaryAppliedTail)
        let before = try XCTUnwrap(v.beforeSecondary), after = try XCTUnwrap(v.afterSecondary)
        assertOnlyAppliedTail(before, after, expected: try XCTUnwrap(v.expectedSecondaryAppliedTail))
        XCTAssertEqual(before, v.afterPrimary)
        XCTAssertEqual(v.primaryDispatch.calls, 1)
        XCTAssertEqual(v.primaryDispatch.stores, 1)
        XCTAssertEqual(v.primaryDispatch.rollbackDispatches, 0)
        XCTAssertEqual(v.secondaryDispatch?.calls, 0)
        XCTAssertEqual(v.secondaryDispatch?.stores, 1)
        XCTAssertEqual(v.secondaryDispatch?.rollbackDispatches, 0)
        XCTAssertNil(v.secondaryDispatch?.width)
        XCTAssertNil(v.secondaryDispatch?.height)
        XCTAssertNil(v.secondaryDispatch?.fps)
        XCTAssertEqual(v.finalReceiptCount, 2)
        XCTAssertEqual(v.finalReceiptsWereDistinct, true)
        XCTAssertNil(v.cleanupSucceeded)
        XCTAssertEqual(v.nativeAfterSDK.encodingGeneration, v.nativeBeforeSDK.encodingGeneration &+ 2)
    }
    func testActualNative702StalePeerKeepsOwnerAndRollsBackOriginalTokenOnce() async throws {
        let v = try await run(.stalePeer)
        XCTAssertEqual(v.primaryResult, .rollback)
        XCTAssertEqual(v.afterPrimary, v.beforePrimary)
        XCTAssertEqual(v.nativeAfterSDK.encodingGeneration, v.nativeBeforeSDK.encodingGeneration &+ 1)
        try assertRolledBackExactly(v)
    }
    func testActualNative702WrongBoundaryBurnsCompletionAndRetainsOriginalCleanup() async throws {
        let v = try await run(.wrongBoundary)
        XCTAssertEqual(v.primaryResult, .refused)
        XCTAssertTrue(v.originalUseBurnedAfterWrongBoundary)
        XCTAssertEqual(v.afterPrimary, v.beforePrimary)
        XCTAssertEqual(v.nativeAfterSDK.encodingGeneration, v.nativeBeforeSDK.encodingGeneration &+ 1)
        try assertRolledBackExactly(v)
    }
    func testActualNative702CompletionReplayCannotStoreOrDispatchAgain() async throws {
        let v = try await run(.completionReplay)
        XCTAssertEqual(v.primaryResult, .accepted)
        assertOnlyAppliedTail(v.beforePrimary, v.afterPrimary, expected: v.expectedPrimaryAppliedTail)
        XCTAssertEqual(v.primaryDispatch.calls, 1)
        XCTAssertEqual(v.primaryDispatch.stores, 1)
        XCTAssertEqual(v.primaryDispatchAfterCleanupReplay, v.primaryDispatch)
        XCTAssertEqual(v.finalReceiptCount, 1)
        XCTAssertEqual(v.afterReplay, v.afterPrimary)
        XCTAssertNil(v.cleanupSucceeded)
        XCTAssertEqual(v.nativeAfterSDK.encodingGeneration, v.nativeBeforeSDK.encodingGeneration &+ 1)
    }
}
