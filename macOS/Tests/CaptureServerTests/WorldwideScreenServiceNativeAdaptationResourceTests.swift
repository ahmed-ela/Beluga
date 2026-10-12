// Native fresh-process resource cases; an unset controller flag is a skip, never proof.
import Foundation
import XCTest
@testable import CaptureServer
@testable import WebRTCTransport

@MainActor
final class WorldwideScreenServiceNativeAdaptationResourceTests: XCTestCase {
    private typealias Case = WorldwideScreenService.NativeAdaptationResourceFixtureCase
    private typealias Observation = WorldwideScreenService.NativeAdaptationResourceFixtureObservation

    private func requireFreshNativeFixtureInvocation() throws {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1" else {
            throw XCTSkip("Fresh network-denied native process and sticky route monitor required")
        }
    }

    private func run(_ selectedCase: Case) async throws -> Observation {
        let f = try BatchAActualServiceFixture(profile: .secondaryTest)
        do {
            let result = try await f.service.nativeAdaptationResourceFixtureObservationForTesting(
                selectedCase: selectedCase, readNative: { peer in
                    let topology = await peer.mediaTopologyForTesting
                    let generation = await peer.screenVideoEncodingMutationGenerationForTesting()
                    let limits = await peer.screenVideoEncodingLimitsForTesting()
                    let total = await peer.maximumTotalRTPBitrateBpsForTesting()
                    let activity = await peer.screenVideoEncodingActivityForTesting()
                    return .init(topology: topology,
                        externalAudioIsAbsent: peer.externalAudioCapturer == nil,
                        encodingGeneration: generation, limits: limits,
                        totalCeiling: total, encodingActivity: activity)
                })
            await f.service.stop()
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)
            XCTAssertEqual(f.hal.inputUID, "BuiltInMic_UID")
            XCTAssertTrue(result.cleanupSourceStopped)
            XCTAssertTrue(result.cleanupPeerClosed)
            XCTAssertTrue(result.cleanupFieldsAreAbsent)
            XCTAssertTrue(result.cleanupAuthorizationsAreRevoked)
            XCTAssertEqual(result.nativeBefore.topology, .videoControlOnly)
            XCTAssertEqual(result.nativeAfter.topology, .videoControlOnly)
            XCTAssertTrue(result.nativeBefore.externalAudioIsAbsent)
            XCTAssertTrue(result.nativeAfter.externalAudioIsAbsent)
            XCTAssertEqual(result.nativeBefore.encodingActivity, result.nativeAfter.encodingActivity)
            XCTAssertTrue(result.prepared)
            XCTAssertTrue(result.preparedReplayRefused)
            return result
        } catch {
            await f.service.stop()
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)
            throw error
        }
    }

    func testActualInertNativeBeginActiveApplyConsumerRetainsActualCustody() async throws {
        try requireFreshNativeFixtureInvocation()
        let v = try await run(.apply)
        XCTAssertFalse(v.beginReturned)
        XCTAssertTrue(v.resourceCustodyIsExact)
        XCTAssertTrue(v.intentIsSenderApply)
        XCTAssertEqual(v.beginInvocation, 2)
        XCTAssertEqual(v.consumerInvocation, 3)
        XCTAssertTrue(v.beginReplayRefused)
        XCTAssertFalse(v.runRefused)
        XCTAssertTrue(v.runReplayRefused)
        XCTAssertTrue(v.completionIsSenderSucceeded)
        XCTAssertFalse(v.completionIsFinalAdoptionOnly)
        XCTAssertTrue(v.actualSDKTokenWasRetained)
        XCTAssertTrue(v.actualSDKTokenRollbackSucceeded)
        XCTAssertEqual(v.nativeAfter.encodingGeneration, v.nativeBefore.encodingGeneration &+ 1)
        // A real parameter getter confirms the requested native operation. This
        // is plumbing/custody proof, not an independent policy-quality oracle.
        let actualSender = try XCTUnwrap(v.nativeAfter.limits)
        let requested = try XCTUnwrap(v.requestedLimits)
        XCTAssertEqual(actualSender.maximumBitrateBps, requested.maximumBitrateBps)
        XCTAssertEqual(actualSender.maximumFramesPerSecond, requested.maximumFramesPerSecond)
        XCTAssertEqual(actualSender.scaleResolutionDownBy, requested.scaleResolutionDownBy)
        XCTAssertNil(actualSender.maximumTotalRTPBitrateBps,
            "The sender-only getter excludes the independently stored peer-wide ceiling")
        // Accepted peer-wide configuration is separate from sender parameters;
        // this is not an independently measured bandwidth/throughput assertion.
        XCTAssertEqual(v.nativeAfter.totalCeiling, v.requestedLimits?.maximumTotalRTPBitrateBps)
        let rolledBack = try XCTUnwrap(v.nativeAfterTokenRollback)
        XCTAssertEqual(rolledBack.limits, v.nativeBefore.limits)
        XCTAssertEqual(rolledBack.totalCeiling, v.nativeBefore.totalCeiling)
        XCTAssertEqual(rolledBack.encodingActivity, v.nativeBefore.encodingActivity)
        XCTAssertEqual(rolledBack.encodingGeneration, v.nativeAfter.encodingGeneration &+ 1)
        XCTAssertEqual(v.ownerAfterConsume, v.ownerAfterBegin)
        XCTAssertEqual(v.ownerAfterRun, v.ownerAfterBegin)
    }

    // The attempt burns once; completion spending belongs to the later adapters.
    func testActualInertNativeBeginActiveNoApplyAttemptBurnsOnce() async throws {
        try requireFreshNativeFixtureInvocation()
        let v = try await run(.noNativeApply)
        XCTAssertFalse(v.beginReturned)
        XCTAssertTrue(v.resourceCustodyIsExact)
        XCTAssertFalse(v.intentIsSenderApply)
        XCTAssertTrue(v.beginReplayRefused)
        XCTAssertFalse(v.runRefused)
        XCTAssertTrue(v.runReplayRefused)
        XCTAssertTrue(v.completionIsFinalAdoptionOnly)
        XCTAssertFalse(v.completionIsSenderSucceeded)
        XCTAssertFalse(v.actualSDKTokenWasRetained)
        XCTAssertFalse(v.actualSDKTokenRollbackSucceeded)
        XCTAssertNil(v.nativeAfterTokenRollback)
        XCTAssertEqual(v.nativeAfter, v.nativeBefore, "no native sender mutation in the noApply branch")
        XCTAssertEqual(v.ownerAfterConsume, v.ownerAfterBegin)
        XCTAssertEqual(v.ownerAfterRun, v.ownerAfterBegin)
    }

    func testActualInertNativeBeginActiveResourceReturnsAndWrongIssuerBurnWithoutSenderMutation() async throws {
        try requireFreshNativeFixtureInvocation()
        let missing: [Case] = [.sourceAbsentAfterPrepare, .sinkAbsentAfterPrepare,
            .captureAuthorizationAbsentAfterPrepare, .forwardingAuthorizationAbsentAfterPrepare,
            .dimensionsAbsentAfterPrepare]
        for selectedCase in missing {
            let v = try await run(selectedCase)
            XCTAssertTrue(v.beginReturned, selectedCase.rawValue)
            XCTAssertNil(v.beginInvocation)
            XCTAssertNil(v.consumerInvocation)
            XCTAssertFalse(v.completionIsSenderSucceeded)
            XCTAssertFalse(v.completionIsFinalAdoptionOnly)
            XCTAssertEqual(v.nativeAfter, v.nativeBefore, selectedCase.rawValue)
            XCTAssertEqual(v.ownerAfterConsume, v.ownerAfterBegin)
            XCTAssertEqual(v.ownerAfterRun, v.ownerAfterBegin)
        }
        let v = try await run(.wrongBoundaryConsume)
        XCTAssertFalse(v.beginReturned)
        XCTAssertTrue(v.wrongBoundaryRefused)
        XCTAssertTrue(v.wrongBoundaryBurnedOriginalUse)
        XCTAssertEqual(v.nativeAfter, v.nativeBefore)
        XCTAssertEqual(v.ownerAfterConsume, v.ownerAfterBegin)
        XCTAssertEqual(v.ownerAfterRun, v.ownerAfterBegin)
    }

    func testActualInertNativeAttemptRejectsDelayedPeerGenerationRevisionAndResumeBeforeSDK() async throws {
        try requireFreshNativeFixtureInvocation()
        let delayed: [Case] = [.peerAbsentBeforeRun, .generationAdvancedBeforeRun,
            .revisionAdvancedBeforeRun, .dimensionsChangedBeforeRun, .resumeOccupancyBeforeRun]
        for selectedCase in delayed {
            let v = try await run(selectedCase)
            XCTAssertFalse(v.beginReturned, selectedCase.rawValue)
            XCTAssertTrue(v.resourceCustodyIsExact)
            XCTAssertTrue(v.intentIsSenderApply)
            XCTAssertTrue(v.beginReplayRefused)
            XCTAssertTrue(v.runRefused, selectedCase.rawValue)
            XCTAssertTrue(v.runReplayRefused, "even the delayed refusal spends the attempt")
            XCTAssertFalse(v.completionIsSenderSucceeded)
            XCTAssertFalse(v.completionIsFinalAdoptionOnly)
            XCTAssertEqual(v.nativeAfter, v.nativeBefore, selectedCase.rawValue)
            XCTAssertEqual(v.ownerAfterConsume, v.ownerAfterBegin)
            XCTAssertEqual(v.ownerAfterRun, v.ownerBeforeRun,
                "pre-SDK refusal must preserve every newer Owner field and native sidecar")
            if selectedCase == .revisionAdvancedBeforeRun {
                // The existing evidence-lane writer intentionally changed Owner;
                // noApply/native completion must not erase that newer revision.
                XCTAssertEqual(v.ownerAfterRun.atoms[168].low,
                    v.ownerAfterBegin.atoms[168].low &+ 1)
            }
        }
    }
}

