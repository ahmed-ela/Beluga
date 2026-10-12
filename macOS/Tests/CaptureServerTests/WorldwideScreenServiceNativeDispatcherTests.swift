// STOPPED SOURCE-ONLY proposal; three genuine safe-path XCTest methods.
// The matrix contains TWO serial disposable tuples, not two process passes.
import Foundation
import XCTest
@testable import CaptureServer
@testable import WebRTCTransport

@MainActor
final class WorldwideScreenServiceNativeDispatcherTests: XCTestCase {
    private typealias Case = WorldwideScreenService.NativeDispatchFixtureCase
    private typealias Observation = WorldwideScreenService.NativeDispatchFixtureObservation
    private typealias Snapshot = WorldwideScreenService.NativeOwnerPublicationSnapshotObservation
    private func run(_ selected: Case) async throws -> Observation {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1" else {
            throw XCTSkip("Owned fresh network-denied process and clean sticky route monitor required")
        }
        let f = try BatchAActualServiceFixture(profile: .secondaryTest)
        do {
            let v = try await f.service.nativeDispatchFixtureObservationForTesting(selected,
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
            XCTAssertTrue(v.quarantineAbsent)
            XCTAssertTrue(v.cleanupSourceStopped)
            XCTAssertTrue(v.cleanupPeerClosed)
            XCTAssertTrue(v.cleanupFieldsAreAbsent)
            XCTAssertTrue(v.cleanupAuthorizationsAreRevoked)
            XCTAssertEqual(v.before.atoms.count, 179)
            XCTAssertEqual(v.after.atoms.count, 179)
            XCTAssertEqual(v.before.times.count, 13)
            XCTAssertEqual(v.after.times.count, 13)
            return v
        } catch {
            await f.service.stop()
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)
            XCTAssertEqual(f.hal.inputUID, "BuiltInMic_UID")
            throw error
        }
    }
    private func assertOnlyRevisionAdvanced(_ before: Snapshot, _ after: Snapshot,
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
    func testActualNativeDispatcherSuccessUsesOneSenderOneFPSAndFinalStore() async throws {
        let v = try await run(.success)
        XCTAssertEqual(v.kind, .adopted)
        XCTAssertEqual(v.nativeBefore.senderApplyInvocations, 0)
        XCTAssertEqual(v.nativeBefore.outputAdaptInvocations, 0)
        XCTAssertEqual(v.nativeAfter.senderApplyInvocations, 1)
        XCTAssertEqual(v.nativeAfter.outputAdaptInvocations, 1)
        XCTAssertEqual(v.nativeAfter.peer.encodingGeneration, v.nativeBefore.peer.encodingGeneration &+ 1)
        guard v.before.atoms.count == 179, v.after.atoms.count == 179 else { return }
        XCTAssertEqual(v.after.atoms[168].low, v.before.atoms[168].low &+ 1)
        XCTAssertNil(v.semanticStatus)
        XCTAssertNil(v.actualSenderErrorIsTransportClosed)
    }
    func testActualNativeDispatcherNoApplyUsesNoNewSenderOrFPS() async throws {
        let v = try await run(.noApply)
        XCTAssertEqual(v.kind, .adopted)
        XCTAssertEqual(v.nativeBefore.senderApplyInvocations, 1)
        XCTAssertEqual(v.nativeBefore.outputAdaptInvocations, 1)
        XCTAssertEqual(v.nativeAfter, v.nativeBefore)
        guard v.before.atoms.count == 179, v.after.atoms.count == 179 else { return }
        XCTAssertEqual(v.after.atoms[168].low, v.before.atoms[168].low &+ 1)
        XCTAssertNil(v.semanticStatus)
        XCTAssertNil(v.actualSenderErrorIsTransportClosed)
    }
    func testActualNativeDispatcherClosedPeerFailureAndPreSDKStaleRefusalHaveNoFPS() async throws {
        let failure = try await run(.closedPeerFailure)
        XCTAssertEqual(failure.kind, .retainedFailure)
        XCTAssertEqual(failure.actualSenderErrorIsTransportClosed, true)
        XCTAssertEqual(failure.semanticStatus, 0)
        XCTAssertEqual(failure.acceptedReads, 0)
        XCTAssertEqual(failure.attemptedReads, 0)
        assertOnlyRevisionAdvanced(failure.before, failure.after)
        XCTAssertEqual(failure.nativeAfter.senderApplyInvocations,
            failure.nativeBefore.senderApplyInvocations &+ 1)
        XCTAssertEqual(failure.nativeAfter.outputAdaptInvocations, failure.nativeBefore.outputAdaptInvocations)
        XCTAssertEqual(failure.nativeAfter.peer, failure.nativeBefore.peer)
        let stale = try await run(.staleBeforeRun)
        XCTAssertEqual(stale.kind, .preSDKRefused)
        XCTAssertEqual(stale.after, stale.before)
        XCTAssertEqual(stale.nativeAfter, stale.nativeBefore)
        XCTAssertNil(stale.semanticStatus)
        XCTAssertNil(stale.actualSenderErrorIsTransportClosed)
    }
}

// Fault-injected post-effect adapter refusal; not a naturally failed C/SDK call.
extension WorldwideScreenServiceNativeDispatcherTests {
    func testActualNativeDispatcherPostEffectRefusalClaimsAndJoinsOwnedInertStop() async throws {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1" else {
            throw XCTSkip("Owned fresh network-denied process and clean sticky route monitor required")
        }
        let f = try BatchAActualServiceFixture(profile: .secondaryTest)
        do {
            let v = try await f.service.nativeDispatchPostEffectRecoveryObservationForTesting(
                readNative: { peer in
                    .init(sdk: .init(peer: .init(topology: await peer.mediaTopologyForTesting,
                        externalAudioIsAbsent: peer.externalAudioCapturer == nil,
                        encodingGeneration: await peer.screenVideoEncodingMutationGenerationForTesting(),
                        limits: await peer.screenVideoEncodingLimitsForTesting(),
                        totalCeiling: await peer.maximumTotalRTPBitrateBpsForTesting(),
                        encodingActivity: await peer.screenVideoEncodingActivityForTesting()),
                        senderApplyInvocations: await peer.screenVideoEncodingApplyInvocationCountForTesting(),
                        outputAdaptInvocations: peer.externalVideoCapturer?.outputAdaptInvocationCountForTesting()),
                        isClosed: await peer.isClosedForTesting)
                })
            XCTAssertTrue(v.consumedBeforeC)
            XCTAssertEqual(v.actualCStatus, 1) // Actual Rust returned normal success.
            XCTAssertEqual(v.substitutions, 1) // The adapter, not SDK, was faulted.
            XCTAssertEqual(v.nativeBefore.sdk.senderApplyInvocations, 0)
            XCTAssertEqual(v.nativeBefore.sdk.outputAdaptInvocations, 0)
            XCTAssertFalse(v.nativeBefore.isClosed)
            XCTAssertEqual(v.nativeAfter.sdk.senderApplyInvocations, 1)
            XCTAssertEqual(v.nativeAfter.sdk.outputAdaptInvocations, 1)
            XCTAssertTrue(v.nativeAfter.isClosed) // BEFORE secondary close helper.
            XCTAssertEqual(v.successDispatch.calls, 1)
            XCTAssertEqual(v.successDispatch.stores, 0) // No accepted702 store.
            XCTAssertEqual(v.successDispatch.rollbackDispatches, 0)
            XCTAssertTrue(v.cleanupUseSpent)
            XCTAssertTrue(v.terminalStopConfirmed)
            XCTAssertTrue(v.serviceStopped)
            XCTAssertTrue(v.stopTailJoined)
            XCTAssertTrue(v.originalSourceOwnershipClearedByTail)
            XCTAssertTrue(v.originalAuthorizationsRevokedByTail)
            XCTAssertTrue(v.originalSinkGateClosedByTail)
            XCTAssertTrue(v.dispatchSlotCleared)
            XCTAssertTrue(v.quarantineAbsent)
            XCTAssertTrue(v.hostUnconfirmedStopAbsent)
            XCTAssertTrue(v.secondaryCleanupSourceStopped)
            XCTAssertTrue(v.secondaryCleanupPeerClosed)
            XCTAssertTrue(v.secondaryCleanupFieldsAbsent)
            XCTAssertTrue(v.secondaryCleanupAuthorizationsRevoked)
            XCTAssertEqual(v.before.atoms.count, 179)
            XCTAssertEqual(v.after.atoms.count, 179)
            XCTAssertEqual(v.before.times.count, 13)
            XCTAssertEqual(v.after.times.count, 13)
            await f.service.stop()
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)
            XCTAssertEqual(f.hal.inputUID, "BuiltInMic_UID")
        } catch {
            await f.service.stop()
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)
            XCTAssertEqual(f.hal.inputUID, "BuiltInMic_UID")
            throw error
        }
    }
}

extension WorldwideScreenServiceNativeDispatcherTests {
    private func runActualReturnCut(_ selected: WorldwideScreenService.NativeDispatchReturnFixtureCut)
        async throws -> WorldwideScreenService.NativeDispatchReturnFixtureObservation {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1" else {
            throw XCTSkip("Owned fresh network-denied process and clean sticky route monitor required")
        }
        let f = try BatchAActualServiceFixture(profile: .secondaryTest)
        do {
            let v = try await f.service.nativeDispatchReturnFixtureObservationForTesting(selected,
                readNative: { peer in
                    .init(sdk: .init(peer: .init(topology: await peer.mediaTopologyForTesting,
                        externalAudioIsAbsent: peer.externalAudioCapturer == nil,
                        encodingGeneration: await peer.screenVideoEncodingMutationGenerationForTesting(),
                        limits: await peer.screenVideoEncodingLimitsForTesting(),
                        totalCeiling: await peer.maximumTotalRTPBitrateBpsForTesting(),
                        encodingActivity: await peer.screenVideoEncodingActivityForTesting()),
                        senderApplyInvocations: await peer.screenVideoEncodingApplyInvocationCountForTesting(),
                        outputAdaptInvocations: peer.externalVideoCapturer?.outputAdaptInvocationCountForTesting()),
                        isClosed: await peer.isClosedForTesting)
                })
            XCTAssertTrue(v.terminalOwnedBeforeRelease) // Includes nil slots.
            XCTAssertTrue(v.slotsAbsentBeforeRelease)
            XCTAssertTrue(v.originalAuthorizationsRevokedBeforeRelease)
            XCTAssertTrue(v.originalSinkClosedBeforeRelease)
            XCTAssertEqual(v.nativeBefore.sdk.senderApplyInvocations, 0)
            XCTAssertEqual(v.nativeAfterSetter.sdk.senderApplyInvocations, 1)
            XCTAssertEqual(v.nativeAfterDispatch.sdk.senderApplyInvocations, 1)
            XCTAssertEqual(v.nativeBefore.sdk.outputAdaptInvocations, 0)
            XCTAssertEqual(v.nativeAfterSetter.sdk.outputAdaptInvocations, 0)
            XCTAssertEqual(v.nativeAfterDispatch.sdk.outputAdaptInvocations, 0)
            XCTAssertEqual(v.successDispatch.calls, 0)
            XCTAssertEqual(v.successDispatch.stores, 0)
            XCTAssertEqual(v.successDispatch.rollbackDispatches, 1)
            XCTAssertTrue(v.cleanupUseSpent)
            XCTAssertTrue(v.dispatchSlotsCleared)
            XCTAssertEqual(v.afterDispatch, v.afterCut) // Full179/13/anchor/route.
            XCTAssertEqual(v.afterDispatch.atoms.count, 179)
            XCTAssertEqual(v.afterDispatch.times.count, 13)
            XCTAssertTrue(v.secondaryCleanupSourceStopped)
            XCTAssertTrue(v.secondaryCleanupPeerClosed)
            XCTAssertTrue(v.secondaryCleanupFieldsAbsent)
            XCTAssertTrue(v.secondaryCleanupAuthorizationsRevoked)
            await f.service.stop()
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)
            XCTAssertEqual(f.hal.inputUID, "BuiltInMic_UID")
            return v
        } catch {
            await f.service.stop()
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)
            XCTAssertEqual(f.hal.inputUID, "BuiltInMic_UID")
            throw error
        }
    }
    func testActualNativeDispatcherHeldSDKReturnCaptureStopRollsBackOriginalToken() async throws {
        let v = try await runActualReturnCut(.captureStop)
        XCTAssertEqual(v.result, .rollbackTrue)
        XCTAssertFalse(v.nativeAfterCut.isClosed)
        XCTAssertFalse(v.nativeAfterDispatch.isClosed)
        XCTAssertFalse(v.publicUnconfirmedAfterDispatch)
        XCTAssertEqual(v.nativeAfterDispatch.sdk.peer.topology, v.nativeBefore.sdk.peer.topology)
        XCTAssertEqual(v.nativeAfterDispatch.sdk.peer.externalAudioIsAbsent, v.nativeBefore.sdk.peer.externalAudioIsAbsent)
        XCTAssertEqual(v.nativeAfterDispatch.sdk.peer.limits, v.nativeBefore.sdk.peer.limits)
        XCTAssertEqual(v.nativeAfterDispatch.sdk.peer.totalCeiling, v.nativeBefore.sdk.peer.totalCeiling)
        XCTAssertEqual(v.nativeAfterDispatch.sdk.peer.encodingActivity, v.nativeBefore.sdk.peer.encodingActivity)
        XCTAssertEqual(v.nativeAfterSetter.sdk.peer.encodingGeneration, v.nativeBefore.sdk.peer.encodingGeneration &+ 1)
        XCTAssertEqual(v.nativeAfterDispatch.sdk.peer.encodingGeneration, v.nativeAfterSetter.sdk.peer.encodingGeneration &+ 1)
        XCTAssertNil(v.afterRepeatedStop)
        XCTAssertNil(v.nativeAfterRepeatedStop)
        XCTAssertNil(v.publicUnconfirmedAfterRepeatedStop)
    }
    func testActualNativeDispatcherHeldSDKReturnFullStopKeepsLateRollbackQuarantined() async throws {
        let v = try await runActualReturnCut(.serviceStop)
        XCTAssertEqual(v.result, .rollbackUncertainTransportClosed)
        XCTAssertTrue(v.nativeAfterCut.isClosed) // Actual close before release.
        XCTAssertTrue(v.nativeAfterDispatch.isClosed)
        XCTAssertTrue(v.publicUnconfirmedAfterDispatch)
        XCTAssertEqual(v.publicUnconfirmedAfterRepeatedStop, true)
        XCTAssertEqual(v.exactQuarantineSurvivedRepeatedStop, true)
        XCTAssertEqual(try XCTUnwrap(v.afterRepeatedStop), v.afterDispatch)
        // Closed original peer and its full native state remain unchanged by
        // failed rollback/repeated generic stop; no newer/ambient sender used.
        XCTAssertEqual(v.nativeAfterDispatch.sdk, v.nativeAfterCut.sdk)
        XCTAssertEqual(try XCTUnwrap(v.nativeAfterRepeatedStop).sdk, v.nativeAfterDispatch.sdk)
        XCTAssertTrue(try XCTUnwrap(v.nativeAfterRepeatedStop).isClosed)
    }
}
