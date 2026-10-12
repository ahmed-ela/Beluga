import Foundation
import XCTest
@testable import CaptureServer

@MainActor
final class WorldwideScreenServiceNativeFailureCompletionTests: XCTestCase {
    private typealias Case = WorldwideScreenService.ClosedPeer703FixtureCase
    private typealias Observation = WorldwideScreenService.ClosedPeer703FixtureObservation
    private typealias Snapshot = WorldwideScreenService.NativeOwnerPublicationSnapshotObservation

    private func run(_ selected: Case) async throws -> Observation {
        guard ProcessInfo.processInfo.environment["BELUGA_RUN_NATIVE_ADAPTATION_RESOURCE_FIXTURE"] == "1" else {
            throw XCTSkip("Owned fresh network-denied process and clean sticky route monitor required")
        }
        let fixture = try BatchAActualServiceFixture(profile: .secondaryTest)
        do {
            // The actor retains every genuine completion/error/resource. Only
            // these immutable Sendable observations leave the actor.
            let v = try await fixture.service.closedPeer703FixtureObservationForTesting(selected)
            await fixture.service.stop()
            XCTAssertTrue(fixture.hal.inputWrites.isEmpty)
            XCTAssertEqual(fixture.hal.listenerCount, 0)
            XCTAssertEqual(fixture.hal.inputUID, "BuiltInMic_UID")
            XCTAssertTrue(v.normalOwnedPeerCloseSucceeded)
            XCTAssertTrue(v.actualReturnedErrorIsTransportClosed)
            XCTAssertTrue(v.returnedFailureErrorKindIsTransportClosed)
            XCTAssertEqual(v.ownerAfterSDKFailure, v.ownerBeforeRun,
                "Compare only the real failed-call interval, after normal owned peer close")
            XCTAssertTrue(v.completionReplayRefused,
                "The same actual senderFailed completion must not be consumed twice")
            XCTAssertEqual(v.ownerAfterReplay, v.ownerAfter703)
            XCTAssertTrue(v.cleanupSourceStopped)
            XCTAssertTrue(v.cleanupPeerClosed)
            XCTAssertTrue(v.cleanupFieldsAreAbsent)
            XCTAssertTrue(v.cleanupAuthorizationsAreRevoked)
            return v
        } catch {
            await fixture.service.stop()
            XCTAssertTrue(fixture.hal.inputWrites.isEmpty)
            XCTAssertEqual(fixture.hal.listenerCount, 0)
            XCTAssertEqual(fixture.hal.inputUID, "BuiltInMic_UID")
            throw error
        }
    }

    // Expected comparison only; no Snapshot/Owner is manufactured or supplied
    // to production. Both sides are independently captured actual actor state.
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
        XCTAssertEqual(before.times.count, 13, file: file, line: line)
        XCTAssertEqual(after.times, before.times, file: file, line: line)
        XCTAssertEqual(after.anchor, before.anchor, file: file, line: line)
        XCTAssertEqual(after.route, before.route, file: file, line: line)
    }

    func testActualNative703ClosedPeerWrapperFailureRetainsOrdinaryOwnerAndBurnsCompletion() async throws {
        let v = try await run(.current)
        // These numbers are assertions against actual read-only recapture,
        // never flags passed into the failure API or a fabricated completion.
        XCTAssertEqual(v.actualFactsBefore703, 511)
        XCTAssertTrue(v.resultWasRetained)
        XCTAssertFalse(v.resultWasGuardedRecovery)
        XCTAssertNil(v.recoveryRetainsOriginalCompletion)
        XCTAssertFalse(v.staleDisposition)
        XCTAssertEqual(v.semanticStatus, 0)
        XCTAssertEqual(v.acceptedReads, 0)
        XCTAssertEqual(v.attemptedReads, 0)
        XCTAssertEqual(v.ownerBefore703, v.ownerAfterSDKFailure)

        // Fresh unstarted policy has no real Show/startup/floor attempt. Fail
        // visibly if that input contract changes; do not seed it to fit this test.
        XCTAssertEqual(v.ownerBefore703.atoms.count, 179)
        guard v.ownerBefore703.atoms.count == 179 else { return }
        XCTAssertEqual(v.ownerBefore703.atoms[152].present, 0)
        XCTAssertEqual(v.ownerBefore703.atoms[155].low, 0)
        XCTAssertEqual(v.ownerBefore703.atoms[158].low, 0)
        XCTAssertEqual(v.ownerBefore703.atoms[164].present, 0)
        XCTAssertEqual(v.ownerBefore703.atoms[165].present, 0)
        // This particular ordinary failure has no matching live negative scope
        // to retain. Actual703 advances revision and nothing else, including
        // the whole untouched Owner tail, native times, anchor and route.
        assertOnlyRevisionAdvanced(v.ownerBefore703, v.ownerAfter703)
    }

    func testActualNative703ClosedPeerWrapperFailureStaleCurrentnessRetainsWholeOwnerAndBurnsCompletion() async throws {
        let cases: [(Case, UInt32, String)] = [
            (.peerAbsent, 0, "peer absent"),
            (.generationAdvanced, 1, "generation advanced"),
            (.revisionAdvanced, 1, "revision advanced"),
            (.forwardingAuthorizationRevoked, 63, "forwarding authorization revoked"),
            (.dimensionsChanged, 255, "dimensions changed"),
        ]
        // Five serial disposable tuples inside this one literal test method,
        // not five separately qualified native processes. No retries/seeded state.
        for (selected, expectedFacts, label) in cases {
            let v = try await run(selected)
            XCTAssertEqual(v.actualFactsBefore703, expectedFacts, label)
            XCTAssertTrue(v.resultWasRetained, label)
            XCTAssertFalse(v.resultWasGuardedRecovery, label)
            XCTAssertNil(v.recoveryRetainsOriginalCompletion, label)
            XCTAssertTrue(v.staleDisposition, label)
            XCTAssertEqual(v.semanticStatus, 0, label)
            XCTAssertEqual(v.acceptedReads, 0, label)
            XCTAssertEqual(v.attemptedReads, 0, label)
            // The intentional post-failure stale change is not a703 store.
            if label == "revision advanced" {
                assertOnlyRevisionAdvanced(v.ownerAfterSDKFailure, v.ownerBefore703)
            } else {
                XCTAssertEqual(v.ownerBefore703, v.ownerAfterSDKFailure, label)
            }
            XCTAssertEqual(v.ownerAfter703, v.ownerBefore703,
                "Stale703 must retain the entire actual Owner and native sidecars: \(label)")
        }
    }
}

extension WorldwideScreenServiceNativeFailureCompletionTests {
    func testActualNative703ClosedPeerWrongBoundaryBurnsCompletionAndRetainsOriginalError() async throws {
        let v = try await run(.wrongBoundary)
        XCTAssertEqual(v.actualFactsBefore703, 511)
        XCTAssertFalse(v.resultWasRetained)
        XCTAssertTrue(v.resultWasGuardedRecovery)
        XCTAssertEqual(v.recoveryRetainsOriginalCompletion, true)
        XCTAssertFalse(v.staleDisposition)
        XCTAssertNil(v.semanticStatus)
        XCTAssertNil(v.acceptedReads)
        XCTAssertNil(v.attemptedReads)
        XCTAssertEqual(v.ownerBefore703, v.ownerAfterSDKFailure)
        XCTAssertEqual(v.ownerAfter703, v.ownerBefore703)
        XCTAssertEqual(v.ownerAfterReplay, v.ownerAfter703)
        XCTAssertTrue(v.completionReplayRefused,
            "A foreign issuer must burn the genuine completion before the original issuer retry")
    }
}
