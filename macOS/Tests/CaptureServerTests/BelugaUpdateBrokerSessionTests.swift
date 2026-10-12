import Darwin
import Dispatch
import Foundation
import XCTest
@testable import BelugaUpdateCore

/// Actual lease/storage fixtures only, all beneath one unique private temporary directory.
final class BelugaUpdateBrokerSessionTests: XCTestCase {
    private typealias Session = BelugaUpdateBrokerSession
    private typealias Operation = BelugaUpdateOperation

    func testPreparationOwnsLeaseBeforeVerificationAndStoragePrecedesUpdaterStart() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.session()
        var verified = false
        try session.prepare(operationID: fixture.operationID,
                            predecessorMenuInstanceID: fixture.oldMenuID) { target in
            XCTAssertEqual(target, fixture.context.target)
            XCTAssertThrowsError(try fixture.acquire())
            XCTAssertNil(try fixture.store.read(expectedTarget: target))
            verified = true
            return try fixture.predecessor()
        }
        XCTAssertTrue(verified)
        XCTAssertEqual(session.state, .prepared)
        XCTAssertTrue(session.ownsLease)
        XCTAssertEqual(try fixture.current().operation.stage, .prepared)
        try session.bindBroker(fixture.brokerBinding(), operationID: fixture.operationID,
                               target: fixture.context.target)
        var starts = 0
        try session.startUpdater(operationID: fixture.operationID, target: fixture.context.target) {
            starts += 1
            XCTAssertThrowsError(try fixture.acquire())
            XCTAssertEqual(try fixture.current().operation.stage, .prepared)
        }
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(session.state, .started)
    }

    func testCompetingLeasePreventsVerificationAndAnyMarkerCreation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let active = try fixture.acquire()
        defer { active.release() }
        let session = try fixture.session()
        var verifies = 0
        XCTAssertThrowsError(try session.prepare(operationID: fixture.operationID,
            predecessorMenuInstanceID: fixture.oldMenuID) { _ in
                verifies += 1
                return try fixture.predecessor()
            })
        XCTAssertEqual(verifies, 0)
        XCTAssertFalse(session.ownsLease)
        XCTAssertNil(try fixture.store.read(expectedTarget: fixture.context.target))
    }

    func testFailedPredecessorVerificationRetainsLeaseWithoutStartingUpdater() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.session()
        XCTAssertThrowsError(try session.prepare(operationID: fixture.operationID,
            predecessorMenuInstanceID: fixture.oldMenuID) { _ in throw TestFailure.denied })
        XCTAssertEqual(session.state, .failed)
        XCTAssertTrue(session.ownsLease)
        XCTAssertThrowsError(try fixture.acquire())
        XCTAssertNil(try fixture.store.read(expectedTarget: fixture.context.target))
        var starts = 0
        XCTAssertThrowsError(try session.startUpdater(operationID: fixture.operationID,
            target: fixture.context.target) { starts += 1 })
        XCTAssertEqual(starts, 0)
    }

    func testCrashClosesLeaseButRestoredMarkerBlocksAnotherCycle() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var session: Session? = try fixture.preparedSession()
        let digest = try XCTUnwrap(session?.recordSHA256)
        session = nil
        let next = try fixture.session()
        var verifies = 0
        XCTAssertThrowsError(try next.prepare(operationID: UUID(),
            predecessorMenuInstanceID: UUID()) { _ in
                verifies += 1
                return try fixture.predecessor()
            })
        XCTAssertEqual(verifies, 0)
        XCTAssertTrue(next.ownsLease)
        XCTAssertEqual(try fixture.current().recordSHA256, digest)
        XCTAssertFalse(try fixture.current().operation.permitsFenceRelease)
        XCTAssertThrowsError(try fixture.acquire())
    }

    func testThrowingStartIsConsumedAndRetainsPreparedFenceAndLease() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.preparedSession()
        let before = try fixture.markerBytes()
        var starts = 0
        XCTAssertThrowsError(try session.startUpdater(operationID: fixture.operationID,
            target: fixture.context.target) { starts += 1; throw TestFailure.denied })
        XCTAssertThrowsError(try session.startUpdater(operationID: fixture.operationID,
            target: fixture.context.target) { starts += 1 })
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(session.state, .failed)
        XCTAssertTrue(session.ownsLease)
        XCTAssertEqual(try fixture.markerBytes(), before)
        XCTAssertThrowsError(try fixture.acquire())
    }

    func testDuplicateStartNeverInvokesSDKAgain() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.startedSession()
        var secondStarts = 0
        XCTAssertThrowsError(try session.startUpdater(operationID: fixture.operationID,
            target: fixture.context.target) { secondStarts += 1 }) { error in
                XCTAssertEqual(error as? Session.Failure, .updaterAlreadyStarted)
            }
        XCTAssertEqual(secondStarts, 0)
        XCTAssertTrue(session.ownsLease)
        XCTAssertEqual(try fixture.current().operation.stage, .prepared)
    }

    func testOperationMismatchCannotStartOrModifyTheMarker() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.preparedSession()
        let before = try fixture.markerBytes()
        var starts = 0
        XCTAssertThrowsError(try session.startUpdater(operationID: UUID(),
            target: fixture.context.target) { starts += 1 })
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(try fixture.markerBytes(), before)
        XCTAssertTrue(session.ownsLease)
    }

    func testIdenticalBytesWithReplacedMarkerInodeRejectBeforeUpdaterStart() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.preparedSession()
        let original = try fixture.markerBytes()
        try fixture.replaceMarker(original)
        var starts = 0
        XCTAssertThrowsError(try session.startUpdater(operationID: fixture.operationID,
            target: fixture.context.target) { starts += 1 })
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(try fixture.markerBytes(), original)
        XCTAssertTrue(session.ownsLease)
    }

    func testDeniedInstallAuthorizationKeepsUnarmedMarkerAndLease() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.startedSession()
        XCTAssertThrowsError(try session.authorizeInstall(operationID: fixture.operationID,
            target: fixture.context.target, authorize: { false })) { error in
                XCTAssertEqual(error as? Session.Failure, .authorizationDenied)
            }
        XCTAssertEqual(try fixture.current().operation.stage, .prepared)
        XCTAssertNil(try fixture.current().operation.candidate)
        XCTAssertTrue(session.ownsLease)
        XCTAssertThrowsError(try fixture.acquire())
    }

    func testRepeatedInstallAuthorizationStillRevalidatesCurrentMarker() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.startedSession()
        XCTAssertTrue(try session.authorizeInstall(operationID: fixture.operationID,
            target: fixture.context.target, authorize: { true }))
        XCTAssertEqual(try fixture.current().operation.stage, .possiblyArmed)
        XCTAssertNil(try fixture.current().operation.candidate)
        XCTAssertTrue(try session.authorizeInstall(operationID: fixture.operationID,
            target: fixture.context.target, authorize: { true }))
        try fixture.replaceMarker(fixture.markerBytes())
        var authorizations = 0
        XCTAssertThrowsError(try session.authorizeInstall(operationID: fixture.operationID,
            target: fixture.context.target, authorize: { authorizations += 1; return true }))
        XCTAssertEqual(authorizations, 0)
        XCTAssertTrue(session.ownsLease)
    }

    func testStorageRevalidationFailureNeverReturnsInstallAuthorization() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.startedSession()
        let before = try fixture.markerBytes()
        XCTAssertThrowsError(try session.authorizeInstall(operationID: fixture.operationID,
            target: fixture.context.target, authorize: {
                XCTAssertEqual(Darwin.chmod(fixture.context.fenceDirectoryURL.path, 0o755), 0)
                return true
            }))
        XCTAssertEqual(try fixture.markerBytes(), before)
        XCTAssertTrue(session.ownsLease)
        XCTAssertThrowsError(try fixture.acquire())
    }

    func testSwallowedSynchronousReentryFailsOuterSDKStartClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.preparedSession()
        XCTAssertThrowsError(try session.startUpdater(operationID: fixture.operationID,
            target: fixture.context.target) {
                XCTAssertThrowsError(try session.authorizeInstall(operationID: fixture.operationID,
                    target: fixture.context.target, authorize: { true })) { error in
                        XCTAssertEqual(error as? Session.Failure, .reentrantCall)
                    }
            }) { error in XCTAssertEqual(error as? Session.Failure, .reentrantCall) }
        XCTAssertEqual(session.state, .failed)
        XCTAssertEqual(try fixture.current().operation.stage, .prepared)
        XCTAssertTrue(session.ownsLease)
    }

    func testCrossThreadGettersDuringSDKCallbackAreBoundedAndMatchPublishedState() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.preparedSession()
        let holder = SessionBox(session)
        let expectedDigest = try XCTUnwrap(session.recordSHA256)
        let queue = DispatchQueue(label: "beluga-broker-getter-regression")
        let completed = expectation(description: "cross-thread getters return")
        try session.startUpdater(operationID: fixture.operationID, target: fixture.context.target) {
            XCTAssertEqual(session.state, .started)
            XCTAssertTrue(session.ownsLease)
            queue.async {
                XCTAssertEqual(holder.session.state, .started)
                XCTAssertTrue(holder.session.ownsLease)
                XCTAssertEqual(holder.session.operationID, fixture.operationID)
                XCTAssertEqual(holder.session.recordSHA256, expectedDigest)
                completed.fulfill()
            }
            // Timeout returns from the SDK callback, so even the old blocking getter
            // mutant can finish after the owner unlocks; no worker is left hanging.
            XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 2), .completed)
        }
        queue.sync {} // Drain the one owned work item after the serialization lease ends.
        XCTAssertEqual(session.state, .started)
        XCTAssertTrue(session.ownsLease)
    }

    func testMismatchedInstalledIdentityCannotManufactureCandidateOrCompletion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.armedSession()
        let wrong = Operation.InstalledCompletion(operationID: fixture.operationID,
            target: fixture.context.target, candidate: try fixture.candidate(build: 102))
        XCTAssertThrowsError(try session.acceptInstalledCompletion(wrong,
            freshContext: fixture.context, verifyInstalled: { _, _ in }))
        XCTAssertEqual(try fixture.current().operation.stage, .possiblyArmed)
        XCTAssertEqual(try fixture.current().operation.candidate, try fixture.candidate())
        XCTAssertTrue(session.ownsLease)
    }

    func testFreshReplacementContextAndProvenReadinessClearFenceBeforeLeaseRelease() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.armedSession()
        try fixture.replaceAppDirectory()
        XCTAssertThrowsError(try fixture.context.revalidate())
        let fresh = try fixture.resolveContext()
        XCTAssertEqual(fresh.target, fixture.context.target)
        let installed = fixture.completion(candidate: try fixture.candidate())
        try session.acceptInstalledCompletion(installed, freshContext: fresh) { actual, context in
            XCTAssertEqual(actual, installed)
            XCTAssertEqual(context.target, fresh.target)
            XCTAssertThrowsError(try fixture.acquire())
        }
        let response = try fixture.acceptReadiness(session)
        XCTAssertEqual(try fixture.current().operation.stage, .readyToRelease)
        XCTAssertFalse(try fixture.current().operation.permitsFenceRelease)
        try session.clearAndRelease(operationID: fixture.operationID, target: fresh.target) {
            completion, readiness, context in
            XCTAssertEqual(completion, installed)
            XCTAssertEqual(readiness, response)
            XCTAssertEqual(context.target, fresh.target)
            XCTAssertThrowsError(try fixture.acquire())
            XCTAssertNotNil(try fixture.store.read(expectedTarget: fresh.target))
        }
        XCTAssertEqual(session.state, .cleared)
        XCTAssertFalse(session.ownsLease)
        XCTAssertNil(try fixture.store.read(expectedTarget: fresh.target))
        let next = try fixture.acquire()
        next.release()
        XCTAssertThrowsError(try session.startUpdater(operationID: fixture.operationID,
            target: fresh.target, {}))
    }

    func testReadinessChallengeIsOneUseAndCancellationCannotRetireMarker() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.installedSession()
        let response = try fixture.acceptReadiness(session)
        let terminal = try fixture.markerBytes()
        XCTAssertThrowsError(try session.acceptReadiness(response, authenticateReadiness: { _ in }))
        XCTAssertEqual(try fixture.markerBytes(), terminal)
        XCTAssertTrue(session.ownsLease)
        XCTAssertThrowsError(try session.clearAndRelease(operationID: fixture.operationID,
            target: fixture.context.target, verifyCompletionAndReadiness: { _, _, _ in }))
    }

    func testFailedFinalClearAndCancellationRetainExactFenceAndCompetingLease() throws {
        for cancel in [false, true] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let session = try fixture.installedSession()
            _ = try fixture.acceptReadiness(session)
            let before = try fixture.markerBytes()
            if cancel {
                try session.cancel(operationID: fixture.operationID, target: fixture.context.target)
                XCTAssertThrowsError(try session.clearAndRelease(operationID: fixture.operationID,
                    target: fixture.context.target, verifyCompletionAndReadiness: { _, _, _ in }))
            } else {
                XCTAssertThrowsError(try session.clearAndRelease(operationID: fixture.operationID,
                    target: fixture.context.target, verifyCompletionAndReadiness: { _, _, _ in
                        try fixture.replaceMarker(before)
                    }))
            }
            XCTAssertEqual(try fixture.markerBytes(), before)
            XCTAssertEqual(session.state, .failed)
            XCTAssertTrue(session.ownsLease)
            XCTAssertThrowsError(try fixture.acquire())
        }
    }

    func testRejectedReentryAfterIrreversibleClearCannotRegressSuccessfulCommit() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = try fixture.installedSession()
        _ = try fixture.acceptReadiness(session)
        session.afterClearedCommitForTesting = {
            do {
                let current = try fixture.store.read(expectedTarget: fixture.context.target)
                XCTAssertNil(current)
            } catch { XCTFail("Cleared marker read failed: \(error)") }
            XCTAssertEqual(session.state, .cleared)
            XCTAssertFalse(session.ownsLease)
            do {
                try session.cancel(operationID: fixture.operationID, target: fixture.context.target)
                XCTFail("Reentrant cancellation must be rejected")
            } catch { XCTAssertEqual(error as? Session.Failure, .reentrantCall) }
        }
        XCTAssertNoThrow(try session.clearAndRelease(operationID: fixture.operationID,
            target: fixture.context.target, verifyCompletionAndReadiness: { _, _, _ in }))
        session.afterClearedCommitForTesting = nil
        XCTAssertEqual(session.state, .cleared)
        XCTAssertFalse(session.ownsLease)
        XCTAssertNil(try fixture.store.read(expectedTarget: fixture.context.target))
        let next = try fixture.acquire()
        next.release()
    }

    func testSDKStartupRequiresExactStagedBrokerBinding() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = try fixture.session()
        try session.prepare(operationID: fixture.operationID,
            predecessorMenuInstanceID: fixture.oldMenuID,
            verifyPredecessor: { _ in try fixture.predecessor() })
        XCTAssertNil(try fixture.current().operation.brokerBinding)
        XCTAssertThrowsError(try session.startUpdater(operationID: fixture.operationID,
            target: fixture.context.target, { XCTFail("Unbound broker cannot start SDK") })) {
                XCTAssertEqual($0 as? Session.Failure, .brokerNotBound)
            }
        XCTAssertEqual(session.state, .failed)
        XCTAssertTrue(session.ownsLease)
        XCTAssertNotNil(try fixture.store.read(expectedTarget: fixture.context.target))
    }

    func testControlledFreshNoUpdateRetiresOnlyPreparedFenceThenReleasesLease() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = try fixture.session()
        var historyChecks = 0
        let admission = BelugaUpdateControlledHistoryAdmission { operationID, target, predecessor in
            historyChecks += 1
            XCTAssertEqual(operationID, fixture.operationID)
            XCTAssertEqual(target, fixture.context.target)
            XCTAssertEqual(predecessor, try fixture.predecessor())
            XCTAssertThrowsError(try fixture.acquire())
        }
        try session.prepare(operationID: fixture.operationID, predecessorMenuInstanceID: fixture.oldMenuID,
                            controlledHistory: admission, verifyPredecessor: { _ in try fixture.predecessor() })
        try session.bindBroker(fixture.brokerBinding(), operationID: fixture.operationID,
                               target: fixture.context.target)
        try session.startUpdater(operationID: fixture.operationID, target: fixture.context.target, {})
        let completion = BelugaUpdateUnarmedCompletion(operationID: fixture.operationID, cycleNonce: UUID(), reason: .noUpdate)
        var sdkChecks = 0
        try session.retirePreparedUnarmed(completion, verifyCompletion: { received in
            sdkChecks += 1
            XCTAssertEqual(received, completion)
            XCTAssertEqual(try fixture.current().operation.stage, .prepared)
            XCTAssertNil(try fixture.current().operation.candidate)
            XCTAssertThrowsError(try fixture.acquire())
        }, verifyPredecessor: { _ in try fixture.predecessor() })
        XCTAssertEqual(historyChecks, 3)
        XCTAssertEqual(sdkChecks, 2)
        XCTAssertEqual(session.state, .cleared)
        XCTAssertFalse(session.ownsLease)
        XCTAssertNil(try fixture.store.read(expectedTarget: fixture.context.target))
        let next = try fixture.acquire(); next.release()
        XCTAssertThrowsError(try session.retirePreparedUnarmed(completion,
            verifyCompletion: { _ in XCTFail("Completion replay cannot reverify") },
            verifyPredecessor: { _ in try fixture.predecessor() }))
    }

    func testFreshExplicitCancelOrDeclineReleasesOnlyTheMatchingUnarmedRecord() throws {
        for declining in [false, true] {
            let fixture = try Fixture(); defer { fixture.remove() }
            let session = try fixture.controlledStartedSession()
            let candidate = try fixture.candidate()
            if declining {
                try session.bindCandidate(candidate, operationID: fixture.operationID,
                                          target: fixture.context.target)
            }
            let reason: BelugaUpdateUnarmedCompletion.Reason = declining ?
                .declinedCandidate(candidate) : .cancelledCheck
            let completion = BelugaUpdateUnarmedCompletion(operationID: fixture.operationID,
                                                          cycleNonce: UUID(), reason: reason)
            var proofs = 0
            try session.retirePreparedUnarmed(completion, verifyCompletion: { value in
                proofs += 1
                XCTAssertEqual(value.reason, reason)
                XCTAssertThrowsError(try fixture.acquire())
                XCTAssertEqual(try fixture.current().operation.candidate, declining ? candidate : nil)
            }, verifyPredecessor: { _ in try fixture.predecessor() })
            XCTAssertEqual(proofs, 2)
            XCTAssertNil(try fixture.store.read(expectedTarget: fixture.context.target))
            XCTAssertEqual(session.state, .cleared)
            XCTAssertFalse(session.ownsLease)
            let next = try fixture.acquire(); next.release()
            XCTAssertThrowsError(try session.retirePreparedUnarmed(completion,
                verifyCompletion: { _ in XCTFail("Cannot replay an unarmed completion") },
                verifyPredecessor: { _ in try fixture.predecessor() }))
        }
    }

    func testCancelAndDeclineNeverBorrowOtherCandidateOrArmedAuthority() throws {
        for mode in 0..<6 {
            let fixture = try Fixture(); defer { fixture.remove() }
            let session = try fixture.controlledStartedSession()
            let candidate = try fixture.candidate()
            if mode != 0 {
                try session.bindCandidate(candidate, operationID: fixture.operationID,
                                          target: fixture.context.target)
            }
            if mode == 3 {
                _ = try session.authorizeInstall(operationID: fixture.operationID,
                                                target: fixture.context.target, authorize: { true })
            }
            if mode == 4 { try session.cancel(operationID: fixture.operationID, target: fixture.context.target) }
            if mode == 5 {
                XCTAssertThrowsError(try session.authorizeInstall(operationID: fixture.operationID,
                    target: fixture.context.target, authorize: { throw TestFailure.denied }))
            }
            let reason: BelugaUpdateUnarmedCompletion.Reason
            if mode == 1 { reason = .cancelledCheck }
            else if mode == 2 { reason = .declinedCandidate(try fixture.predecessor()) }
            else { reason = .declinedCandidate(candidate) }
            let bytes = try fixture.markerBytes()
            XCTAssertThrowsError(try session.retirePreparedUnarmed(
                .init(operationID: fixture.operationID, cycleNonce: UUID(), reason: reason),
                verifyCompletion: { _ in XCTFail("Mismatched or poisoned completion cannot be verified") },
                verifyPredecessor: { _ in try fixture.predecessor() }))
            XCTAssertEqual(try fixture.markerBytes(), bytes)
            XCTAssertTrue(session.ownsLease)
            XCTAssertThrowsError(try fixture.acquire())
        }
    }

    func testDeclinedCandidateRechecksNativeProofAndUnchangedPredecessor() throws {
        for changedPredecessor in [false, true] {
            let fixture = try Fixture(); defer { fixture.remove() }
            let session = try fixture.controlledStartedSession()
            let candidate = try fixture.candidate()
            try session.bindCandidate(candidate, operationID: fixture.operationID, target: fixture.context.target)
            let bytes = try fixture.markerBytes()
            var proofs = 0
            XCTAssertThrowsError(try session.retirePreparedUnarmed(
                .init(operationID: fixture.operationID, cycleNonce: UUID(), reason: .declinedCandidate(candidate)),
                verifyCompletion: { _ in
                    proofs += 1
                    if proofs == 2 { throw TestFailure.denied }
                }, verifyPredecessor: { _ in
                    changedPredecessor ? candidate : try fixture.predecessor()
                }))
            XCTAssertEqual(proofs, changedPredecessor ? 1 : 2)
            XCTAssertEqual(try fixture.markerBytes(), bytes)
            XCTAssertTrue(session.ownsLease)
        }
    }

    func testAbsentFenceAndHighBuildNeverInferControlledHistory() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = try fixture.startedSession()
        let bytes = try fixture.markerBytes()
        var completions = 0
        XCTAssertThrowsError(try session.retirePreparedUnarmed(
            .init(operationID: fixture.operationID, cycleNonce: UUID(), reason: .noUpdate),
            verifyCompletion: { _ in completions += 1 },
            verifyPredecessor: { _ in try fixture.predecessor() })) {
            XCTAssertEqual($0 as? Session.Failure, .controlledHistoryNotAdmitted)
        }
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(try fixture.markerBytes(), bytes)
        XCTAssertTrue(session.ownsLease)
        XCTAssertThrowsError(try fixture.acquire())
    }

    func testDeniedControlledHistoryBeforePreparationCannotStartSDK() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = try fixture.session()
        XCTAssertThrowsError(try session.prepare(operationID: fixture.operationID,
            predecessorMenuInstanceID: fixture.oldMenuID,
            controlledHistory: .init(verify: { _, _, _ in throw TestFailure.denied }),
            verifyPredecessor: { _ in try fixture.predecessor() }))
        XCTAssertTrue(session.ownsLease)
        XCTAssertNil(try fixture.store.read(expectedTarget: fixture.context.target))
        XCTAssertThrowsError(try session.startUpdater(operationID: fixture.operationID,
            target: fixture.context.target, { XCTFail("Unknown lineage cannot start") }))
    }

    func testNoUpdateCannotRetireCandidateArmedCancelledOrFailedOperation() throws {
        for mode in 0..<4 {
            let fixture = try Fixture(); defer { fixture.remove() }
            let session = try fixture.controlledStartedSession()
            if mode == 0 { try session.bindCandidate(fixture.candidate(), operationID: fixture.operationID,
                                                    target: fixture.context.target) }
            if mode == 1 { _ = try session.authorizeInstall(operationID: fixture.operationID,
                target: fixture.context.target, authorize: { true }) }
            if mode == 2 { try session.cancel(operationID: fixture.operationID, target: fixture.context.target) }
            if mode == 3 { XCTAssertThrowsError(try session.authorizeInstall(operationID: fixture.operationID,
                target: fixture.context.target, authorize: { throw TestFailure.denied })) }
            let bytes = try fixture.markerBytes()
            XCTAssertThrowsError(try session.retirePreparedUnarmed(
                .init(operationID: fixture.operationID, cycleNonce: UUID(), reason: .noUpdate),
                verifyCompletion: { _ in XCTFail("Unclean operation cannot receive completion authority") },
                verifyPredecessor: { _ in try fixture.predecessor() }))
            XCTAssertEqual(try fixture.markerBytes(), bytes)
            XCTAssertTrue(session.ownsLease)
        }
    }

    func testNoUpdateWrongBindingNonceOrPredecessorCannotClear() throws {
        for mode in 0..<4 {
            let fixture = try Fixture(); defer { fixture.remove() }
            let session = try fixture.controlledStartedSession()
            let bytes = try fixture.markerBytes()
            let noUpdate = BelugaUpdateUnarmedCompletion(
                operationID: mode == 0 ? UUID() : fixture.operationID,
                cycleNonce: mode == 1 ? fixture.operationID : mode == 2 ?
                    UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) : UUID(), reason: .noUpdate)
            XCTAssertThrowsError(try session.retirePreparedUnarmed(noUpdate,
                verifyCompletion: { _ in }, verifyPredecessor: { _ in
                    mode == 3 ? try fixture.candidate() : try fixture.predecessor()
                }))
            XCTAssertEqual(try fixture.markerBytes(), bytes)
            XCTAssertTrue(session.ownsLease)
        }
    }

    func testNoUpdateFinalProofRevalidatesHistorySDKContextAndExactPreparedInode() throws {
        for mode in 0..<5 {
            let fixture = try Fixture(); defer { fixture.remove() }
            let session = try fixture.session()
            var checks = 0
            var sdkChecks = 0
            try session.prepare(operationID: fixture.operationID,
                predecessorMenuInstanceID: fixture.oldMenuID,
                controlledHistory: .init(verify: { _, _, _ in
                    checks += 1
                    if mode == 0, checks == 3 { throw TestFailure.denied }
                }), verifyPredecessor: { _ in try fixture.predecessor() })
            try session.bindBroker(fixture.brokerBinding(), operationID: fixture.operationID,
                                   target: fixture.context.target)
            try session.startUpdater(operationID: fixture.operationID, target: fixture.context.target, {})
            let bytes = try fixture.markerBytes()
            XCTAssertThrowsError(try session.retirePreparedUnarmed(
                .init(operationID: fixture.operationID, cycleNonce: UUID(), reason: .noUpdate),
                verifyCompletion: { _ in
                    sdkChecks += 1
                    if mode == 1 { throw TestFailure.denied }
                    if mode == 2 { try fixture.replaceMarker(bytes) }
                    if mode == 3 { try fixture.replaceAppDirectory() }
                    if mode == 4, sdkChecks == 2 { throw TestFailure.denied }
                }, verifyPredecessor: { _ in try fixture.predecessor() }))
            XCTAssertEqual(try fixture.markerBytes(), bytes)
            XCTAssertEqual(session.state, .failed)
            XCTAssertTrue(session.ownsLease)
            XCTAssertThrowsError(try fixture.acquire())
        }
    }

    func testPreparedCrashCannotRestoreControlledNoUpdateAuthority() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        var old: Session? = try fixture.controlledStartedSession()
        let bytes = try fixture.markerBytes()
        old = nil
        XCTAssertNil(old)
        let next = try fixture.session()
        var admissions = 0
        XCTAssertThrowsError(try next.prepare(operationID: UUID(), predecessorMenuInstanceID: UUID(),
            controlledHistory: .init(verify: { _, _, _ in admissions += 1 }),
            verifyPredecessor: { _ in try fixture.predecessor() }))
        XCTAssertEqual(admissions, 0)
        XCTAssertThrowsError(try next.retirePreparedUnarmed(
            .init(operationID: fixture.operationID, cycleNonce: UUID(), reason: .noUpdate), verifyCompletion: { _ in },
            verifyPredecessor: { _ in try fixture.predecessor() }))
        XCTAssertEqual(try fixture.markerBytes(), bytes)
        XCTAssertTrue(next.ownsLease)
    }

    private struct Fixture: Sendable {
        let root: URL
        let app: URL
        let context: BelugaUpdateRuntimeContext
        let store: BelugaUpdateFenceStore
        let lockDirectory: URL
        let operationID = UUID()
        let oldMenuID = UUID()

        init() throws {
            let fixtureRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("beluga-broker-session-" + UUID().uuidString, isDirectory: true)
            root = fixtureRoot
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            app = root.appendingPathComponent("Beluga.app", isDirectory: true)
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            context = try XCTUnwrap(BelugaUpdateRuntimeContext.resolve(
                bundleIdentifier: Operation.expectedBundleIdentifier, bundleURL: app,
                inputs: .init(effectiveUID: Darwin.geteuid(), accountHomeDirectory: { _ in fixtureRoot })
            ))
            try FileManager.default.createDirectory(
                at: context.fenceDirectoryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            store = try BelugaUpdateFenceStore(directoryURL: context.fenceDirectoryURL)
            lockDirectory = root.appendingPathComponent("runtime-lock", isDirectory: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
        func acquire() throws -> WorldwideHostProcessLock {
            try WorldwideHostProcessLock.acquire(lockDirectoryURL: lockDirectory)
        }
        func session() throws -> Session {
            try Session(context: context, acquireOwnership: { try acquire() })
        }
        func predecessor() throws -> Operation.ArtifactIdentity {
            try .init(version: "0.2.0", build: 100,
                      executableSHA256: String(repeating: "a", count: 64),
                      dependencyClosureSHA256: String(repeating: "b", count: 64))
        }
        func candidate(build: UInt64 = 101) throws -> Operation.ArtifactIdentity {
            try .init(version: "0.2.1", build: build,
                      executableSHA256: String(repeating: "c", count: 64),
                      dependencyClosureSHA256: String(repeating: "d", count: 64))
        }
        func preparedSession() throws -> Session {
            let value = try session()
            try value.prepare(operationID: operationID, predecessorMenuInstanceID: oldMenuID,
                              verifyPredecessor: { _ in try predecessor() })
            try value.bindBroker(brokerBinding(), operationID: operationID, target: context.target)
            return value
        }
        func startedSession() throws -> Session {
            let value = try preparedSession()
            try value.startUpdater(operationID: operationID, target: context.target, {})
            return value
        }
        func controlledStartedSession() throws -> Session {
            let value = try session()
            try value.prepare(operationID: operationID, predecessorMenuInstanceID: oldMenuID,
                controlledHistory: .init(verify: { _, _, _ in }),
                verifyPredecessor: { _ in try predecessor() })
            try value.bindBroker(brokerBinding(), operationID: operationID, target: context.target)
            try value.startUpdater(operationID: operationID, target: context.target, {})
            return value
        }
        func brokerBinding() throws -> Operation.BrokerBinding {
            try .init(artifact: predecessor(), nativeCDHash: Data(repeating: 7, count: 20))
        }
        func armedSession() throws -> Session {
            let value = try startedSession()
            try value.bindCandidate(candidate(), operationID: operationID, target: context.target)
            XCTAssertTrue(try value.authorizeInstall(operationID: operationID,
                target: context.target, authorize: { true }))
            return value
        }
        func installedSession() throws -> Session {
            let value = try armedSession()
            try value.acceptInstalledCompletion(completion(candidate: candidate()),
                freshContext: context, verifyInstalled: { _, _ in })
            return value
        }
        func completion(candidate: Operation.ArtifactIdentity) -> Operation.InstalledCompletion {
            .init(operationID: operationID, target: context.target, candidate: candidate)
        }
        func acceptReadiness(_ session: Session) throws -> Operation.MenuReadiness {
            let challenge = try session.issueReadinessChallenge(operationID: operationID,
                target: context.target, menuInstanceID: UUID(), nonce: UUID(),
                authenticateMenu: { _, _, _ in })
            let response = Operation.MenuReadiness(operationID: challenge.operationID,
                target: challenge.target, candidate: challenge.candidate,
                menuInstanceID: challenge.menuInstanceID, challengeNonce: challenge.nonce,
                isReady: true)
            try session.acceptReadiness(response, authenticateReadiness: { _ in })
            return response
        }
        func current() throws -> BelugaUpdateFenceStore.Snapshot {
            try XCTUnwrap(store.read(expectedTarget: context.target))
        }
        func markerBytes() throws -> Data {
            try Data(contentsOf: context.fenceDirectoryURL.appendingPathComponent(
                BelugaUpdateFenceStore.fileName))
        }
        func replaceMarker(_ bytes: Data) throws {
            let marker = context.fenceDirectoryURL.appendingPathComponent(BelugaUpdateFenceStore.fileName)
            try bytes.write(to: marker, options: .atomic)
            guard Darwin.chmod(marker.path, 0o600) == 0 else { throw TestFailure.fixtureWrite }
        }
        func replaceAppDirectory() throws {
            try FileManager.default.moveItem(at: app,
                to: root.appendingPathComponent("Predecessor.app", isDirectory: true))
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        }
        func resolveContext() throws -> BelugaUpdateRuntimeContext {
            try XCTUnwrap(BelugaUpdateRuntimeContext.resolve(
                bundleIdentifier: Operation.expectedBundleIdentifier, bundleURL: app,
                inputs: .init(effectiveUID: Darwin.geteuid(), accountHomeDirectory: { _ in root })
            ))
        }
    }

    /// The test intentionally crosses threads only through the component's synchronized API.
    private final class SessionBox: @unchecked Sendable {
        let session: Session
        init(_ session: Session) { self.session = session }
    }

    private enum TestFailure: Error { case denied, fixtureWrite }
}
