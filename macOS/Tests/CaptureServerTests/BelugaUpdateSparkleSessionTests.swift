import Darwin
// The existing CaptureServerTests target owns these package-internal driver fixtures.
import Foundation
import Sparkle
import XCTest
@testable import BelugaUpdateDriver
@testable import BelugaUpdateCore

final class BelugaUpdateSparkleSessionTests: XCTestCase {
    @MainActor
    func testInitializationDoesNotConstructOrStartSparkleOrUserInterface() {
        let harness = Harness()
        _ = harness.makeSession()
        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertEqual(harness.engine.starts, 0)
        XCTAssertEqual(harness.engine.checks, 0)
        XCTAssertFalse(harness.retained)
    }

    @MainActor
    func testExplicitStartupPublishesPreparedAuthorityBeforeExactTargetConstruction() throws {
        let harness = Harness()
        let session = harness.makeSession()
        try session.startManualCheck()

        XCTAssertEqual(harness.events, ["prepared", "ui-factory", "engine-factory", "manual-only",
                                       "start", "manual-check"])
        XCTAssertEqual(harness.preparedOperations, [harness.operationID])
        XCTAssertTrue(harness.engine.target === harness.target)
        XCTAssertTrue(harness.engine.delegate === session)
        XCTAssertNotNil(harness.engine.userDriver as? BelugaUpdateUserDriver)
        XCTAssertEqual(harness.engine.starts, 1)
        XCTAssertEqual(harness.engine.checks, 1)
        XCTAssertTrue(harness.retained)
        XCTAssertThrowsError(try session.startManualCheck()) {
            XCTAssertEqual($0 as? BelugaUpdateSparkleSession.SessionError, .alreadyStarted)
        }
        XCTAssertEqual(harness.engine.starts, 1)
    }

    @MainActor
    func testMissingOrDeniedPreparedAuthorityNeverConstructsNativeMachinery() {
        for mode in [Preparation.omit, .reject, .noRetainedAuthority] {
            let harness = Harness()
            harness.preparation = mode
            let session = harness.makeSession()
            XCTAssertThrowsError(try session.startManualCheck())
            XCTAssertEqual(harness.engine.starts, 0)
            XCTAssertEqual(harness.engine.checks, 0)
            XCTAssertFalse(harness.events.contains("ui-factory"))
            XCTAssertEqual(harness.observationNames, ["startup-failed"])
        }
    }

    @MainActor
    func testDuplicateStartupBodyAndFailureAfterStartupCannotStartASecondEngine() {
        for mode in [Preparation.twice, .failAfterBody] {
            let harness = Harness()
            harness.preparation = mode
            let session = harness.makeSession()
            XCTAssertThrowsError(try session.startManualCheck())
            XCTAssertEqual(harness.engine.starts, 1)
            XCTAssertEqual(harness.engine.checks, 1)
            XCTAssertTrue(harness.retained)
            XCTAssertEqual(harness.observationNames, ["startup-failed"])
            XCTAssertThrowsError(try session.startManualCheck())
            XCTAssertEqual(harness.engine.starts, 1)
            XCTAssertThrowsError(try session.admitCheck(from: harness.engine.identity, check: .updates))
        }
    }

    @MainActor
    func testFactoryReentryCannotConstructEngineOrConfigureAfterAuthorityLoss() {
        for revokeInUI in [true, false] {
            let harness = Harness()
            harness.onUIFactory = { if revokeInUI { harness.retained = false } }
            harness.onEngineFactory = { if !revokeInUI { harness.retained = false } }
            let session = harness.makeSession()
            XCTAssertThrowsError(try session.startManualCheck())
            XCTAssertEqual(harness.engine.starts, 0)
            XCTAssertFalse(harness.events.contains("manual-only"))
            XCTAssertEqual(harness.events.contains("engine-factory"), !revokeInUI)
        }
    }

    @MainActor
    func testSDKStartupErrorRetainsOwnedEngineAndCannotRetryStart() {
        let harness = Harness()
        harness.engine.startError = TestFailure.refused
        let session = harness.makeSession()
        XCTAssertThrowsError(try session.startManualCheck())
        XCTAssertEqual(harness.engine.starts, 1)
        XCTAssertEqual(harness.engine.checks, 0)
        XCTAssertTrue(harness.retained)
        XCTAssertEqual(harness.observationNames, ["startup-failed"])
        XCTAssertThrowsError(try session.startManualCheck())
        XCTAssertEqual(harness.engine.starts, 1)
    }

    @MainActor
    func testOnlyExactRequestedManualCheckCanBeAdmittedOnce() throws {
        let harness = Harness()
        let session = harness.makeSession()
        try session.startManualCheck()
        let foreign = NSObject()
        for check in [SPUUpdateCheck.updates, .updatesInBackground, .updateInformation] {
            XCTAssertThrowsError(try session.admitCheck(from: foreign, check: check)) {
                XCTAssertEqual($0 as? BelugaUpdateSparkleSession.SessionError, .foreignUpdater)
            }
        }
        for check in [SPUUpdateCheck.updatesInBackground, .updateInformation] {
            XCTAssertThrowsError(try session.admitCheck(from: harness.engine.identity, check: check)) {
                XCTAssertEqual($0 as? BelugaUpdateSparkleSession.SessionError, .nonManualCheck)
            }
        }
        try session.admitCheck(from: harness.engine.identity, check: .updates)
        XCTAssertThrowsError(try session.admitCheck(from: harness.engine.identity, check: .updates)) {
            XCTAssertEqual($0 as? BelugaUpdateSparkleSession.SessionError, .checkNotRequested)
        }
        XCTAssertTrue(harness.observations.isEmpty)
    }

    @MainActor
    func testUpdateAdmissionNeedsManualCycleAndRetainedAuthority() throws {
        let harness = Harness()
        let session = harness.makeSession()
        try session.startManualCheck()
        let item = SUAppcastItem.empty()
        XCTAssertThrowsError(try session.admitUpdate(from: harness.engine.identity,
                                                     item: item, check: .updates))
        try session.admitCheck(from: harness.engine.identity, check: .updates)
        for check in [SPUUpdateCheck.updatesInBackground, .updateInformation] {
            XCTAssertThrowsError(try session.admitUpdate(from: harness.engine.identity,
                                                         item: item, check: check))
        }
        try session.admitUpdate(from: harness.engine.identity, item: item, check: .updates)
        session.foundUpdate(from: harness.engine.identity, item: item)
        XCTAssertEqual(harness.observationNames, ["candidate"])
        harness.retained = false
        XCTAssertThrowsError(try session.admitUpdate(from: harness.engine.identity,
                                                     item: item, check: .updates))
    }

    @MainActor
    func testInstallAndRetryUseExactOperationGateBeforeForwarding() throws {
        let harness = Harness()
        let session = harness.makeSession()
        try session.startManualCheck()
        let item = try harness.admitFreshCandidate(to: session)
        let driver = try XCTUnwrap(harness.engine.userDriver)
        let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0)))
        var choices = [SPUUserUpdateChoice]()
        driver.showUpdateFound(with: item, state: state) { choices.append($0) }
        harness.ui.foundReply?(.install)
        driver.showReady { choices.append($0) }
        harness.ui.readyReply?(.install)
        var retries = 0
        driver.showInstallingUpdate(withApplicationTerminated: false) { retries += 1 }
        harness.ui.retry?()

        XCTAssertEqual(choices, [.install, .install])
        XCTAssertEqual(retries, 1)
        XCTAssertEqual(harness.installRequests.count, 3)
        XCTAssertTrue(harness.installRequests.allSatisfy { $0.operationID == harness.operationID })
        XCTAssertEqual(Set(harness.installRequests.map(\.presentationID)).count, 3)
        XCTAssertTrue(session.extractionInvariantHolds(from: harness.engine.identity))
        XCTAssertTrue(harness.retained)
    }

    @MainActor
    func testInstallDenialThrowOrLostOwnershipNeverForwardsInstall() throws {
        for result in [InstallResult.deny, .fail, .revokeAfterAllow] {
            let harness = Harness()
            harness.installResult = result
            let session = harness.makeSession()
            try session.startManualCheck()
            let item = try harness.admitFreshCandidate(to: session)
            let driver = try XCTUnwrap(harness.engine.userDriver)
            let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0)))
            var choices = [SPUUserUpdateChoice]()
            driver.showUpdateFound(with: item, state: state) { choices.append($0) }
            harness.ui.foundReply?(.install)
            XCTAssertEqual(choices, [.dismiss])
            XCTAssertEqual(harness.installRequests.count, 1)
            XCTAssertFalse(session.extractionInvariantHolds(from: harness.engine.identity))
            XCTAssertEqual(harness.observationNames.last, "extraction-invariant")
        }
    }

    @MainActor
    func testExtractionInvariantDetectsMissingInstallGateWithoutExecutingNativeHook() throws {
        let harness = Harness()
        let session = harness.makeSession()
        try session.startManualCheck()
        XCTAssertFalse(session.extractionInvariantHolds(from: NSObject()))
        XCTAssertTrue(harness.observations.isEmpty)
        XCTAssertFalse(session.extractionInvariantHolds(from: harness.engine.identity))
        XCTAssertEqual(harness.observationNames, ["extraction-invariant"])
        XCTAssertEqual(harness.installRequests.count, 0)
        XCTAssertTrue(harness.retained)
    }

    @MainActor
    func testTargetTerminationRequiresExactUpdaterAndContinuouslyRetainedBrokerAuthority() throws {
        let harness = Harness()
        let session = harness.makeSession()
        try session.startManualCheck()
        XCTAssertFalse(session.permitsTargetTermination(from: NSObject()))
        XCTAssertFalse(session.permitsTargetTermination(from: harness.engine.identity))
        XCTAssertEqual(harness.terminationRequests, 0)
        let item = try harness.admitFreshCandidate(to: session)
        let driver = try XCTUnwrap(harness.engine.userDriver)
        let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0)))
        driver.showUpdateFound(with: item, state: state) { _ in }
        harness.ui.foundReply?(.install)
        harness.allowTermination = false
        XCTAssertFalse(session.permitsTargetTermination(from: harness.engine.identity))
        harness.allowTermination = true
        XCTAssertTrue(session.permitsTargetTermination(from: harness.engine.identity))
        harness.onTermination = { harness.retained = false }
        XCTAssertFalse(session.permitsTargetTermination(from: harness.engine.identity))
        XCTAssertEqual(harness.terminationRequests, 3)
    }

    @MainActor
    func testVerifiedFeedOverridesDefaultsOnlyForExactConstructedUpdaterIdentity() throws {
        let harness = Harness()
        let session = harness.makeSession()
        XCTAssertNil(session.feedURL(from: harness.engine.identity))
        try session.startManualCheck()
        XCTAssertEqual(session.feedURL(from: harness.engine.identity), harness.feed)
        XCTAssertNil(session.feedURL(from: NSObject()))
        XCTAssertTrue(harness.retained)
    }

    @MainActor
    func testResumeAndNonterminalObservationsNeverReleaseAuthorityOrRestartCycle() throws {
        let harness = Harness()
        let session = harness.makeSession()
        try session.startManualCheck()
        let item = SUAppcastItem.empty()
        let foreign = NSObject()
        session.foundUpdate(from: foreign, item: item)
        session.noUpdate(from: foreign, error: TestFailure.refused)
        session.aborted(from: foreign, error: TestFailure.refused)
        session.finishedCycle(from: foreign, check: .updates, error: nil)
        XCTAssertTrue(harness.observations.isEmpty)

        session.foundUpdate(from: harness.engine.identity, item: item)
        session.madeChoice(from: harness.engine.identity, item: item, choice: .dismiss,
            state: try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 2))))
        session.noUpdate(from: harness.engine.identity, error: TestFailure.refused)
        session.aborted(from: harness.engine.identity, error: TestFailure.refused)
        session.finishedCycle(from: harness.engine.identity, check: .updates, error: nil)
        XCTAssertEqual(harness.observationNames,
                       ["resume-possible", "candidate", "resumed-installation", "no-update", "aborted", "cycle"])
        XCTAssertTrue(harness.observations.allSatisfy { $0.operationID == harness.operationID })
        XCTAssertTrue(harness.retained)
        XCTAssertEqual(harness.engine.checks, 1)
        XCTAssertThrowsError(try session.admitCheck(from: harness.engine.identity, check: .updates))
    }

    @MainActor
    func testUnexpectedInstallOnQuitIsOnlyStalledAndNeverClaimedCancelled() throws {
        let harness = Harness()
        let session = harness.makeSession()
        try session.startManualCheck()
        let item = SUAppcastItem.empty()
        XCTAssertFalse(session.interceptInstallOnQuit(from: NSObject(), item: item))
        XCTAssertTrue(harness.observations.isEmpty)
        XCTAssertTrue(session.interceptInstallOnQuit(from: harness.engine.identity, item: item))
        XCTAssertEqual(harness.observationNames, ["install-on-quit"])
        XCTAssertTrue(harness.retained)
        XCTAssertEqual(harness.installRequests.count, 0)
    }

    @MainActor
    func testInstalledObservationIsOneUseAndCannotStartAnotherCheckDuringStartupReentry() throws {
        let harness = Harness()
        harness.engine.onStart = { harness.engine.userDriver?.showUpdateInstalledAndRelaunched(true) {} }
        let session = harness.makeSession()
        try session.startManualCheck()
        XCTAssertEqual(harness.engine.checks, 0)
        XCTAssertEqual(harness.observationNames, ["installed"])
        harness.engine.userDriver?.showUpdateInstalledAndRelaunched(false) {}
        XCTAssertEqual(harness.observationNames, ["installed"])
        XCTAssertTrue(harness.retained)
        XCTAssertThrowsError(try session.startManualCheck())
        XCTAssertFalse(session.permitsTargetTermination(from: harness.engine.identity))
    }

    @MainActor
    func testSupportedPublicDelegateSelectorsAreActuallyPresentWithoutInstantiatingSDK() {
        let session = Harness().makeSession()
        for selector in ["updater:mayPerformUpdateCheck:error:",
                         "updater:shouldProceedWithUpdate:updateCheck:error:",
                         "updaterShouldPromptForPermissionToCheckForUpdates:",
                         "feedURLStringForUpdater:",
                         "updater:didFindValidUpdate:", "updaterDidNotFindUpdate:error:",
                         "updater:didAbortWithError:",
                         "updater:didFinishUpdateCycleForUpdateCheck:error:",
                         "updater:userDidMakeChoice:forUpdate:state:",
                         "updater:willExtractUpdate:", "updater:willInstallUpdate:",
                         "updaterShouldRelaunchApplication:",
                         "updater:willInstallUpdateOnQuit:immediateInstallationBlock:"] {
            XCTAssertTrue(session.responds(to: NSSelectorFromString(selector)), selector)
        }
    }

    @MainActor
    func testActualPrivateBrokerLeaseAndFenceComposeBeforeStartupAndInstallReply() throws {
        let fixture = try PrivateBrokerFixture()
        defer { fixture.remove() }
        let broker = try BelugaUpdateBrokerSession(context: fixture.context,
                                                  acquireOwnership: { try fixture.acquire() })
        let harness = Harness(target: fixture.bundle, operationID: fixture.operationID)
        let authority = BelugaUpdateSparkleSession.Authority(
            withPreparedAuthority: { operationID, body in
                try broker.prepare(operationID: operationID, predecessorMenuInstanceID: UUID()) { target in
                    XCTAssertEqual(target, fixture.context.target)
                    XCTAssertThrowsError(try fixture.acquire())
                    return try fixture.predecessor()
                }
                try broker.bindBroker(.init(artifact: fixture.predecessor(),
                                             nativeCDHash: Data(repeating: 7, count: 20)),
                                      operationID: operationID, target: fixture.context.target)
                harness.retained = true
                XCTAssertEqual(try fixture.current().operation.stage, .prepared)
                try broker.startUpdater(operationID: operationID, target: fixture.context.target, body)
            }, isRetained: { operationID in
                broker.ownsLease && broker.operationID == operationID && broker.state == .started
            }, bindCandidate: { operationID, candidate in
                try broker.bindCandidate(candidate, operationID: operationID,
                                         target: fixture.context.target)
                XCTAssertEqual(try fixture.current().operation.candidate, candidate)
                XCTAssertEqual(try fixture.current().operation.stage, .prepared)
            }, authorizeInstallation: { request in
                try broker.authorizeInstall(operationID: request.operationID,
                    target: fixture.context.target, authorize: { true })
            }, mayTerminateTarget: { operationID in
                broker.ownsLease && broker.operationID == operationID && broker.state == .started
            })
        harness.engine.onStart = {
            XCTAssertTrue(broker.ownsLease)
            XCTAssertEqual(broker.state, .started)
            do {
                let current = try fixture.current()
                XCTAssertEqual(current.operation.stage, .prepared)
            } catch { XCTFail("Prepared record read failed: \(error)") }
            do {
                let unexpected = try fixture.acquire()
                unexpected.release()
                XCTFail("Broker must hold the shared lease during startup")
            } catch {}
        }
        let session = harness.makeSession(authority: authority)
        try session.startManualCheck()
        let item = try harness.admitFreshCandidate(to: session)
        let driver = try XCTUnwrap(harness.engine.userDriver)
        let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0)))
        var forwarded = 0
        driver.showUpdateFound(with: item, state: state) { choice in
            XCTAssertEqual(choice, .install)
            do {
                let current = try fixture.current()
                XCTAssertEqual(current.operation.stage, .possiblyArmed)
                XCTAssertEqual(current.operation.operationID, fixture.operationID)
            } catch { XCTFail("Armed record read failed: \(error)") }
            XCTAssertTrue(broker.ownsLease)
            do {
                let unexpected = try fixture.acquire()
                unexpected.release()
                XCTFail("Broker must hold the shared lease before forwarding install")
            } catch {}
            forwarded += 1
        }
        harness.ui.foundReply?(.install)
        XCTAssertEqual(forwarded, 1)
        let armedDigest = try fixture.current().recordSHA256
        XCTAssertTrue(session.extractionInvariantHolds(from: harness.engine.identity))

        session.noUpdate(from: harness.engine.identity, error: TestFailure.refused)
        session.finishedCycle(from: harness.engine.identity, check: .updates, error: nil)
        XCTAssertEqual(try fixture.current().recordSHA256, armedDigest)
        XCTAssertEqual(broker.state, .started)
        try broker.cancel(operationID: fixture.operationID, target: fixture.context.target)
        XCTAssertEqual(broker.state, .failed)
        XCTAssertTrue(broker.ownsLease)
        XCTAssertEqual(try fixture.current().recordSHA256, armedDigest)
        XCTAssertEqual(try fixture.current().operation.stage, .possiblyArmed)
        XCTAssertThrowsError(try fixture.acquire())
        var afterCancel = [SPUUserUpdateChoice]()
        driver.showReady { afterCancel.append($0) }
        harness.ui.readyReply?(.install)
        XCTAssertEqual(afterCancel, [.dismiss])
        XCTAssertEqual(try fixture.current().recordSHA256, armedDigest)
    }

    @MainActor
    func testMissingTrustedCandidateDeniesAdmissionAndFirstInstallBeforeAuthority() throws {
        let harness = Harness()
        harness.candidateError = TestFailure.refused
        let session = harness.makeSession()
        try session.startManualCheck()
        try session.admitCheck(from: harness.engine.identity, check: .updates)
        XCTAssertThrowsError(try session.admitUpdate(from: harness.engine.identity,
                                                     item: .empty(), check: .updates))
        let driver = try XCTUnwrap(harness.engine.userDriver)
        let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0)))
        var choices = [SPUUserUpdateChoice]()
        driver.showUpdateFound(with: .empty(), state: state) { choices.append($0) }
        harness.ui.foundReply?(.install)
        XCTAssertEqual(choices, [.dismiss])
        XCTAssertTrue(harness.boundCandidates.isEmpty)
        XCTAssertTrue(harness.installRequests.isEmpty)
        XCTAssertTrue(harness.retained)
    }

    @MainActor
    func testSignedHighBuildSingleViewerCandidateIsRejectedBeforeBindingOrInstall() throws {
        for rawBuild in ["1000000", String(UInt64.max)] {
            let harness = Harness()
            // Pure signature-positive metadata fixture; no real SDK or feed is started.
            harness.candidateInput = .init(
                signingStatus: SPUAppcastSigningValidationStatus.succeeded.rawValue,
                installationType: "application", isDelta: false,
                versionString: rawBuild, displayVersionString: "0.2.1",
                properties: ["sparkle:version": rawBuild, "sparkle:shortVersionString": "0.2.1",
                    "enclosure": ["beluga:artifactSchema": "beluga.update-candidate.v1",
                        "beluga:executableSHA256": String(repeating: "c", count: 64),
                        "beluga:bundleTreeSHA256": String(repeating: "d", count: 64),
                        "beluga:bundleTreeAlgorithm": "beluga.bundle-tree-json-v1"]])
            let session = harness.makeSession()
            try session.startManualCheck()
            try session.admitCheck(from: harness.engine.identity, check: .updates)
            let item = SUAppcastItem.empty()
            XCTAssertThrowsError(try session.admitUpdate(from: harness.engine.identity,
                                                         item: item, check: .updates)) {
                XCTAssertEqual($0 as? BelugaUpdateCandidateMetadata.Failure, .invalidSchema)
            }
            let driver = try XCTUnwrap(harness.engine.userDriver)
            let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0)))
            var choices = [SPUUserUpdateChoice]()
            driver.showUpdateFound(with: item, state: state) { choices.append($0) }
            harness.ui.foundReply?(.install)
            XCTAssertEqual(choices, [.dismiss])
            XCTAssertTrue(harness.boundCandidates.isEmpty)
            XCTAssertTrue(harness.installRequests.isEmpty)
            XCTAssertEqual(harness.terminationRequests, 0)
            XCTAssertTrue(harness.retained)
        }
    }

    @MainActor
    func testBindingFailureOrOwnershipLossCannotForwardInstall() throws {
        for revoke in [false, true] {
            let harness = Harness()
            if revoke { harness.onBind = { harness.retained = false } }
            else { harness.bindingError = TestFailure.refused }
            let session = harness.makeSession()
            try session.startManualCheck()
            XCTAssertThrowsError(try harness.admitFreshCandidate(to: session))
            let driver = try XCTUnwrap(harness.engine.userDriver)
            let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0)))
            var choices = [SPUUserUpdateChoice]()
            driver.showUpdateFound(with: .empty(), state: state) { choices.append($0) }
            harness.ui.foundReply?(.install)
            XCTAssertEqual(choices, [.dismiss])
            XCTAssertTrue(harness.installRequests.isEmpty)
            XCTAssertFalse(session.permitsTargetTermination(from: harness.engine.identity))
        }
    }

    @MainActor
    func testSameCandidateBindsOnceAndDifferentCandidateCannotReplaceIt() throws {
        let harness = Harness()
        let session = harness.makeSession()
        try session.startManualCheck()
        try session.admitCheck(from: harness.engine.identity, check: .updates)
        let item = SUAppcastItem.empty()
        try session.admitUpdate(from: harness.engine.identity, item: item, check: .updates)
        try session.admitUpdate(from: harness.engine.identity, item: item, check: .updates)
        let driver = try XCTUnwrap(harness.engine.userDriver)
        let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0)))
        var choices = [SPUUserUpdateChoice]()
        driver.showUpdateFound(with: item, state: state) { choices.append($0) }
        harness.ui.foundReply?(.install)
        XCTAssertEqual(harness.boundCandidates.count, 1)
        XCTAssertEqual(harness.installRequests.count, 1)
        harness.candidateOverride = try .init(version: "0.2.2", build: 102,
            executableSHA256: String(repeating: "e", count: 64),
            dependencyClosureSHA256: String(repeating: "f", count: 64))
        XCTAssertThrowsError(try session.admitUpdate(from: harness.engine.identity,
                                                     item: .empty(), check: .updates))
        driver.showUpdateFound(with: item, state: state) { choices.append($0) }
        harness.ui.foundReply?(.install)
        XCTAssertEqual(choices, [.install, .dismiss])
        XCTAssertEqual(harness.boundCandidates.count, 1)
        XCTAssertEqual(harness.installRequests.count, 1)
    }

    @MainActor
    func testReadyAndRetryCannotSkipSignedFirstInstallEvenAfterCandidateAdmission() throws {
        for admitted in [false, true] {
            let harness = Harness()
            let session = harness.makeSession()
            try session.startManualCheck()
            if admitted {
                try session.admitCheck(from: harness.engine.identity, check: .updates)
                try session.admitUpdate(from: harness.engine.identity, item: .empty(), check: .updates)
            }
            let driver = try XCTUnwrap(harness.engine.userDriver)
            var choices = [SPUUserUpdateChoice]()
            driver.showReady { choices.append($0) }
            harness.ui.readyReply?(.install)
            var retries = 0
            driver.showInstallingUpdate(withApplicationTerminated: false) { retries += 1 }
            harness.ui.retry?()
            XCTAssertEqual(choices, [.dismiss])
            XCTAssertEqual(retries, 0)
            XCTAssertTrue(harness.installRequests.isEmpty)
        }
    }

    @MainActor
    func testPairedNativeManualNoUpdateCompletionIsOneUseOnlyInsideRetirementCallback() throws {
        let h = Harness(); h.enableUnarmedRetirement = true
        let session = h.makeSession()
        try session.startManualCheck()
        try session.admitCheck(from: h.engine.identity, check: .updates)
        let error = manualNoUpdateError()
        session.noUpdate(from: h.engine.identity, error: error)
        XCTAssertTrue(h.unarmedRetirements.isEmpty)
        session.aborted(from: h.engine.identity, error: error)
        XCTAssertTrue(h.unarmedRetirements.isEmpty)
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertEqual(h.unarmedRetirements.count, 1)
        let completion = try XCTUnwrap(h.unarmedRetirements.first)
        XCTAssertEqual(completion.operationID, h.operationID)
        XCTAssertNotEqual(completion.cycleNonce, h.operationID)
        XCTAssertFalse(session.isCurrentUnarmedCompletion(completion))
        XCTAssertEqual(h.observationNames, ["no-update", "aborted", "cycle", "unarmed-retired"])
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        session.noUpdate(from: h.engine.identity, error: error)
        XCTAssertEqual(h.unarmedRetirements.count, 1)
        XCTAssertThrowsError(try session.startManualCheck())
    }

    @MainActor
    func testNoUpdateWithoutExplicitOwnerRetirementIsObservationOnly() throws {
        let h = Harness()
        let session = h.makeSession()
        try session.startManualCheck()
        try session.admitCheck(from: h.engine.identity, check: .updates)
        let error = manualNoUpdateError()
        session.noUpdate(from: h.engine.identity, error: error)
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertTrue(h.unarmedRetirements.isEmpty)
        XCTAssertTrue(h.retained)
        XCTAssertEqual(h.observationNames, ["no-update", "cycle"])
    }

    @MainActor
    func testNoUpdateRequiresSameNativeErrorManualCycleAndIdleCurrentSDK() throws {
        for mode in 0..<8 {
            let h = Harness(); h.enableUnarmedRetirement = true
            let session = h.makeSession()
            try session.startManualCheck()
            if mode != 0 { try session.admitCheck(from: h.engine.identity, check: .updates) }
            let error: NSError = mode == 1 ? manualNoUpdateError(manual: false) :
                mode == 2 ? NSError(domain: "other", code: Int(SUError.noUpdateError.rawValue),
                                    userInfo: [SPUNoUpdateFoundUserInitiatedKey: true]) : manualNoUpdateError()
            if mode != 3 { session.noUpdate(from: h.engine.identity, error: error) }
            if mode == 4 { h.engine.sessionInProgress = true }
            if mode == 5 { h.retained = false }
            let finish: NSError? = mode == 6 ? manualNoUpdateError() : mode == 7 ? nil : error
            session.finishedCycle(from: h.engine.identity, check: .updates, error: finish)
            XCTAssertTrue(h.unarmedRetirements.isEmpty, "mode \(mode)")
        }
    }

    @MainActor
    func testWrongOrDuplicateNoUpdateCycleAndForeignCallbacksNeverRetire() throws {
        for mode in 0..<5 {
            let h = Harness(); h.enableUnarmedRetirement = true
            let session = h.makeSession()
            try session.startManualCheck()
            try session.admitCheck(from: h.engine.identity, check: .updates)
            let error = manualNoUpdateError()
            session.noUpdate(from: mode == 0 ? NSObject() : h.engine.identity, error: error)
            if mode == 1 { session.noUpdate(from: h.engine.identity, error: error) }
            if mode == 2 { session.aborted(from: h.engine.identity, error: TestFailure.refused) }
            session.finishedCycle(from: h.engine.identity,
                check: mode == 3 ? .updatesInBackground : mode == 4 ? .updateInformation : .updates,
                error: error)
            XCTAssertTrue(h.unarmedRetirements.isEmpty, "mode \(mode)")
        }
    }

    @MainActor
    func testCandidateResumeArmExtractionAndTerminationContaminateUnarmedCycle() throws {
        for mode in 0..<6 {
            let h = Harness(); h.enableUnarmedRetirement = true
            let session = h.makeSession()
            try session.startManualCheck()
            try session.admitCheck(from: h.engine.identity, check: .updates)
            let item = SUAppcastItem.empty()
            switch mode {
            case 0: session.foundUpdate(from: h.engine.identity, item: item)
            case 1: session.madeChoice(from: h.engine.identity, item: item, choice: .dismiss,
                state: try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 2))))
            case 2: _ = session.interceptInstallOnQuit(from: h.engine.identity, item: item)
            case 3: _ = session.permitsTargetTermination(from: h.engine.identity)
            case 4: _ = session.extractionInvariantHolds(from: h.engine.identity)
            default:
                h.engine.userDriver?.showReady { _ in }
                h.ui.readyReply?(.install)
            }
            let error = manualNoUpdateError()
            session.noUpdate(from: h.engine.identity, error: error)
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertTrue(h.unarmedRetirements.isEmpty, "mode \(mode)")
            XCTAssertTrue(h.retained)
        }
    }

    @MainActor
    func testNoUpdateRetirementFailureOrCycleObservationReentryKeepsAuthority() throws {
        for reentry in [false, true] {
            let h = Harness(); h.enableUnarmedRetirement = true
            let session = h.makeSession()
            if reentry { h.onObservation = { value in
                if case .cycleFinished = value.event {
                    _ = session.permitsTargetTermination(from: h.engine.identity)
                }
            } } else { h.retirementError = TestFailure.refused }
            try session.startManualCheck()
            try session.admitCheck(from: h.engine.identity, check: .updates)
            let error = manualNoUpdateError()
            session.noUpdate(from: h.engine.identity, error: error)
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertTrue(h.retained)
            XCTAssertEqual(h.unarmedRetirements.count, reentry ? 0 : 1)
            XCTAssertEqual(h.observationNames.contains("unarmed-retired"), false)
            XCTAssertEqual(h.observationNames.contains("unarmed-retirement-failed"), !reentry)
            h.onObservation = nil
        }
    }

    @MainActor
    func testAcceptedInitialCheckCancelRetiresOnlyAfterActualIdleSDKCycleCompletion() throws {
        let h = Harness(); h.enableUnarmedRetirement = true
        let session = h.makeSession()
        try session.startManualCheck()
        try session.admitCheck(from: h.engine.identity, check: .updates)
        let driver = try XCTUnwrap(h.engine.userDriver)
        var sdkCancels = 0
        driver.showUserInitiatedUpdateCheck { sdkCancels += 1 }
        h.ui.checkCancellation?()
        h.ui.checkCancellation?()
        XCTAssertEqual(sdkCancels, 1)
        XCTAssertTrue(h.unarmedRetirements.isEmpty)
        session.finishedCycle(from: h.engine.identity, check: .updates, error: nil)
        XCTAssertEqual(h.unarmedRetirements.map(\.reason), [.cancelledCheck])
        XCTAssertEqual(h.observationNames, ["cycle", "unarmed-retired"])
        session.finishedCycle(from: h.engine.identity, check: .updates, error: nil)
        XCTAssertEqual(h.unarmedRetirements.count, 1)
    }

    @MainActor
    func testSynchronousInitialCheckUIAfterSDKStartupDoesNotPoisonFreshCancel() throws {
        let h = Harness(); h.enableUnarmedRetirement = true
        let session = h.makeSession()
        var sdkCancels = 0
        h.engine.onCheck = {
            do { try session.admitCheck(from: h.engine.identity, check: .updates) }
            catch { XCTFail("Exact fresh check admission failed") }
            h.engine.userDriver?.showUserInitiatedUpdateCheck { sdkCancels += 1 }
            h.ui.checkCancellation?()
        }
        try session.startManualCheck()
        h.engine.onCheck = nil
        XCTAssertEqual(sdkCancels, 1)
        XCTAssertTrue(h.unarmedRetirements.isEmpty)
        session.finishedCycle(from: h.engine.identity, check: .updates, error: nil)
        XCTAssertEqual(h.unarmedRetirements.map(\.reason), [.cancelledCheck])
    }

    @MainActor
    func testFreshNotDownloadedSkipOrDismissRequiresUIAndExactSDKChoiceThenCleanup() throws {
        for choice in [SPUUserUpdateChoice.skip, .dismiss] {
            let h = Harness(); h.enableUnarmedRetirement = true
            let session = h.makeSession()
            try session.startManualCheck()
            let item = try h.admitFreshCandidate(to: session)
            session.foundUpdate(from: h.engine.identity, item: item)
            let driver = try XCTUnwrap(h.engine.userDriver)
            let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0, userInitiated: true)))
            var forwarded = [SPUUserUpdateChoice]()
            driver.showUpdateFound(with: item, state: state) { forwarded.append($0) }
            h.ui.foundReply?(choice)
            XCTAssertEqual(forwarded, [choice])
            XCTAssertTrue(h.unarmedRetirements.isEmpty)
            session.madeChoice(from: h.engine.identity, item: item, choice: choice, state: state)
            XCTAssertTrue(h.unarmedRetirements.isEmpty)
            session.finishedCycle(from: h.engine.identity, check: .updates, error: nil)
            let candidate = try XCTUnwrap(h.boundCandidates.first)
            XCTAssertEqual(h.unarmedRetirements.map(\.reason), [.declinedCandidate(candidate)])
            XCTAssertEqual(h.installRequests.count, 0)
            XCTAssertEqual(h.observationNames.last, "unarmed-retired")
        }
    }

    @MainActor
    func testDeclineRejectsMissingMismatchedResumedDuplicateOrUncertainNativePair() throws {
        for mode in 0..<12 {
            let h = Harness(); h.enableUnarmedRetirement = true
            let session = h.makeSession()
            try session.startManualCheck()
            let item = try h.admitFreshCandidate(to: session)
            session.foundUpdate(from: h.engine.identity, item: item)
            let driver = try XCTUnwrap(h.engine.userDriver)
            let stage = mode == 5 ? 1 : mode == 6 ? 2 : 0
            let state = try XCTUnwrap(SPUUserUpdateState(coder:
                FixtureCoder(stage: stage, userInitiated: mode != 7)))
            driver.showUpdateFound(with: item, state: state) { _ in }
            if mode != 0 { h.ui.foundReply?(.dismiss) }
            let nativeItem = mode == 3 ? try decodedCandidateFixture() : item
            if mode == 3 { XCTAssertFalse(nativeItem === item) }
            let nativeState = mode == 2 ? try XCTUnwrap(SPUUserUpdateState(coder:
                FixtureCoder(stage: 0, userInitiated: true))) : state
            if mode != 1 {
                session.madeChoice(from: h.engine.identity, item: nativeItem,
                    choice: mode == 4 ? .skip : .dismiss, state: nativeState)
            }
            if mode == 8 { session.madeChoice(from: h.engine.identity, item: item, choice: .dismiss, state: state) }
            if mode == 10 { h.engine.sessionInProgress = true }
            if mode == 11 { _ = session.interceptInstallOnQuit(from: h.engine.identity, item: item) }
            session.finishedCycle(from: h.engine.identity, check: .updates,
                error: mode == 9 ? TestFailure.refused : nil)
            XCTAssertTrue(h.unarmedRetirements.isEmpty, "mode \(mode)")
            XCTAssertTrue(h.retained, "mode \(mode)")
        }
    }

    @MainActor
    func testCheckCancelRejectsMissingStaleDownloadCandidateErrorOrLaterUnsafeActivity() throws {
        for mode in 0..<9 {
            let h = Harness(); h.enableUnarmedRetirement = true
            let session = h.makeSession()
            try session.startManualCheck()
            if mode != 6 { try session.admitCheck(from: h.engine.identity, check: .updates) }
            let driver = try XCTUnwrap(h.engine.userDriver)
            if mode == 1 {
                driver.showDownloadInitiated {}
                h.ui.downloadCancellation?()
            } else if mode != 0 {
                driver.showUserInitiatedUpdateCheck {}
                if mode == 2 || mode == 3 {
                    let item = SUAppcastItem.empty()
                    try session.admitUpdate(from: h.engine.identity, item: item, check: .updates)
                    session.foundUpdate(from: h.engine.identity, item: item)
                    if mode == 2 {
                        let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0, userInitiated: true)))
                        driver.showUpdateFound(with: item, state: state) { _ in }
                    }
                }
                h.ui.checkCancellation?()
            }
            if mode == 5 { h.engine.sessionInProgress = true }
            if mode == 7 { driver.showReady { _ in } }
            if mode == 8 { session.foundUpdate(from: h.engine.identity, item: .empty()) }
            session.finishedCycle(from: h.engine.identity, check: .updates,
                error: mode == 4 ? TestFailure.refused : nil)
            XCTAssertTrue(h.unarmedRetirements.isEmpty, "mode \(mode)")
        }
    }

    @MainActor
    func testDeniedInstallConvertedToDismissCannotMasqueradeAsNeverArmedUserDecline() throws {
        for result in [InstallResult.deny, .fail, .revokeAfterAllow] {
            let h = Harness(); h.enableUnarmedRetirement = true; h.installResult = result
            let session = h.makeSession()
            try session.startManualCheck()
            let item = try h.admitFreshCandidate(to: session)
            session.foundUpdate(from: h.engine.identity, item: item)
            let driver = try XCTUnwrap(h.engine.userDriver)
            let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0, userInitiated: true)))
            var forwarded = [SPUUserUpdateChoice]()
            driver.showUpdateFound(with: item, state: state) { forwarded.append($0) }
            h.ui.foundReply?(.install)
            XCTAssertEqual(forwarded, [.dismiss])
            session.madeChoice(from: h.engine.identity, item: item, choice: .dismiss, state: state)
            session.finishedCycle(from: h.engine.identity, check: .updates, error: nil)
            XCTAssertTrue(h.unarmedRetirements.isEmpty)
            XCTAssertEqual(h.installRequests.count, 1)
        }
    }

    @MainActor
    func testDeclineCycleObservationReentryInvalidatesPendingRetirement() throws {
        let h = Harness(); h.enableUnarmedRetirement = true
        let session = h.makeSession()
        try session.startManualCheck()
        let item = try h.admitFreshCandidate(to: session)
        session.foundUpdate(from: h.engine.identity, item: item)
        let driver = try XCTUnwrap(h.engine.userDriver)
        let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0, userInitiated: true)))
        driver.showUpdateFound(with: item, state: state) { _ in }
        h.ui.foundReply?(.skip)
        session.madeChoice(from: h.engine.identity, item: item, choice: .skip, state: state)
        h.onObservation = { value in
            if case .cycleFinished = value.event { driver.showReady { _ in } }
        }
        session.finishedCycle(from: h.engine.identity, check: .updates, error: nil)
        XCTAssertTrue(h.unarmedRetirements.isEmpty)
        h.onObservation = nil
    }

    @MainActor
    func testRepeatedExactCandidateAdmissionCannotCertifyUnarmedDecline() throws {
        let h = Harness(); h.enableUnarmedRetirement = true
        let session = h.makeSession()
        try session.startManualCheck()
        let item = try h.admitFreshCandidate(to: session)
        try session.admitUpdate(from: h.engine.identity, item: item, check: .updates)
        session.foundUpdate(from: h.engine.identity, item: item)
        let driver = try XCTUnwrap(h.engine.userDriver)
        let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: 0, userInitiated: true)))
        driver.showUpdateFound(with: item, state: state) { _ in }
        h.ui.foundReply?(.dismiss)
        session.madeChoice(from: h.engine.identity, item: item, choice: .dismiss, state: state)
        session.finishedCycle(from: h.engine.identity, check: .updates, error: nil)
        XCTAssertTrue(h.unarmedRetirements.isEmpty)
        XCTAssertEqual(h.boundCandidates.count, 1)
    }

    @MainActor
    func testActualPrivateControlledBrokerNoUpdateRetiresOnlyAfterDriverPairing() throws {
        let fixture = try PrivateBrokerFixture(); defer { fixture.remove() }
        let broker = try BelugaUpdateBrokerSession(context: fixture.context,
                                                   acquireOwnership: { try fixture.acquire() })
        let h = Harness(target: fixture.bundle, operationID: fixture.operationID)
        var nativeSession: BelugaUpdateSparkleSession?
        let authority = BelugaUpdateSparkleSession.Authority(
            withPreparedAuthority: { operationID, body in
                try broker.prepare(operationID: operationID, predecessorMenuInstanceID: UUID(),
                    controlledHistory: .init(verify: { _, _, _ in }),
                    verifyPredecessor: { _ in try fixture.predecessor() })
                try broker.bindBroker(.init(artifact: fixture.predecessor(),
                                             nativeCDHash: Data(repeating: 7, count: 20)),
                                      operationID: operationID, target: fixture.context.target)
                h.retained = true
                try broker.startUpdater(operationID: operationID, target: fixture.context.target, body)
            }, isRetained: { broker.ownsLease && broker.operationID == $0 && broker.state == .started },
            bindCandidate: { operationID, candidate in
                try broker.bindCandidate(candidate, operationID: operationID, target: fixture.context.target)
            }, authorizeInstallation: { request in
                try broker.authorizeInstall(operationID: request.operationID,
                    target: fixture.context.target, authorize: { true })
            }, mayTerminateTarget: { _ in false }, retirePreparedUnarmed: { completion in
                try broker.retirePreparedUnarmed(completion, verifyCompletion: { value in
                    guard nativeSession?.isCurrentUnarmedCompletion(value) == true else {
                        throw TestFailure.refused
                    }
                    XCTAssertThrowsError(try fixture.acquire())
                }, verifyPredecessor: { _ in try fixture.predecessor() })
            })
        let session = h.makeSession(authority: authority)
        nativeSession = session
        try session.startManualCheck()
        try session.admitCheck(from: h.engine.identity, check: .updates)
        let error = manualNoUpdateError()
        session.noUpdate(from: h.engine.identity, error: error)
        XCTAssertEqual(try fixture.current().operation.stage, .prepared)
        XCTAssertTrue(broker.ownsLease)
        session.aborted(from: h.engine.identity, error: error)
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertEqual(broker.state, .cleared)
        XCTAssertFalse(broker.ownsLease)
        XCTAssertNil(try fixture.store.read(expectedTarget: fixture.context.target))
        XCTAssertEqual(h.observationNames.last, "unarmed-retired")
        let next = try fixture.acquire(); next.release()
        nativeSession = nil
    }

    @MainActor
    func testNativeFactoryUsesRealSignatureGateWithoutConstructingAnUpdater() {
        XCTAssertThrowsError(try BelugaUpdateSparkleSession.Factory.native.candidate(.empty()))
    }

    @MainActor
    func testFreshInitialFeedFailuresNeedAcknowledgementExactAbortAndIdleFinish() throws {
        let cases: [(SUError, BelugaUpdateUnarmedCompletion.FailedInitialCheck)] = [
            (.downloadError, .feedFetch), (.appcastParseError, .feedParseOrSignature),
        ]
        for (code, expected) in cases {
            let h = Harness(); h.enableUnarmedRetirement = true
            h.ui.deferErrorAcknowledgements = true
            let session = h.makeSession()
            try session.startManualCheck()
            try session.admitCheck(from: h.engine.identity, check: .updates)
            let driver = try XCTUnwrap(h.engine.userDriver)
            driver.showUserInitiatedUpdateCheck {}
            let error = initialFeedError(code)
            var sdkAcknowledgements = 0
            driver.showUpdaterError(error) { sdkAcknowledgements += 1 }
            XCTAssertEqual(sdkAcknowledgements, 0)
            XCTAssertTrue(h.unarmedRetirements.isEmpty)
            h.ui.errorAcknowledgements[0]()
            h.ui.errorAcknowledgements[0]()
            XCTAssertEqual(sdkAcknowledgements, 1)
            XCTAssertTrue(h.unarmedRetirements.isEmpty)
            session.aborted(from: h.engine.identity, error: error)
            XCTAssertTrue(h.unarmedRetirements.isEmpty)
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertEqual(h.unarmedRetirements.map(\.reason), [.failedInitialCheck(expected)])
            XCTAssertEqual(h.observationNames, ["aborted", "cycle", "unarmed-retired"])
            XCTAssertTrue(h.installRequests.isEmpty)
            XCTAssertTrue(h.boundCandidates.isEmpty)
            let proof = try XCTUnwrap(h.unarmedRetirements.first)
            XCTAssertFalse(session.isCurrentUnarmedCompletion(proof))
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertEqual(h.unarmedRetirements.count, 1)
        }
    }

    @MainActor
    func testFailedInitialCheckReasonsOnlyMatchNilDurableCandidate() throws {
        let candidate = try BelugaUpdateOperation.ArtifactIdentity(version: "0.2.1", build: 101,
            executableSHA256: String(repeating: "c", count: 64),
            dependencyClosureSHA256: String(repeating: "d", count: 64))
        for failure in [BelugaUpdateUnarmedCompletion.FailedInitialCheck.feedFetch, .feedParseOrSignature] {
            let reason = BelugaUpdateUnarmedCompletion.Reason.failedInitialCheck(failure)
            XCTAssertTrue(reason.matches(candidate: nil))
            XCTAssertFalse(reason.matches(candidate: candidate))
        }
    }

    @MainActor
    func testFeedFailureRejectsMissingMismatchedDuplicateOutOfOrderOrUncertainProof() throws {
        for mode in 0..<20 {
            let h = Harness(); h.enableUnarmedRetirement = true
            h.ui.deferErrorAcknowledgements = true
            let session = h.makeSession()
            try session.startManualCheck()
            if mode != 1 { try session.admitCheck(from: h.engine.identity, check: .updates) }
            let driver = try XCTUnwrap(h.engine.userDriver)
            if mode != 0 { driver.showUserInitiatedUpdateCheck {} }
            let error = mode == 11 ? initialFeedError(.signatureError) :
                mode == 12 ? NSError(domain: "other", code: Int(SUError.downloadError.rawValue)) :
                initialFeedError(.downloadError)
            driver.showUpdaterError(error) {}
            if mode == 2 { session.aborted(from: h.engine.identity, error: error) }
            if mode != 3 && mode != 17 { h.ui.errorAcknowledgements[0]() }
            if mode == 13 {
                driver.showUpdaterError(error) {}
                h.ui.errorAcknowledgements[1]()
            }
            if mode == 14 { driver.showUpdateNotFoundWithError(error) {} }
            if mode == 15 { session.noUpdate(from: h.engine.identity, error: manualNoUpdateError()) }
            if mode == 19 { driver.showUserInitiatedUpdateCheck {} }
            if mode != 4 {
                session.aborted(from: mode == 16 ? NSObject() : h.engine.identity,
                    error: mode == 5 ? initialFeedError(.downloadError) : error)
            }
            if mode == 7 { session.aborted(from: h.engine.identity, error: error) }
            if mode == 9 { h.engine.sessionInProgress = true }
            if mode == 10 { h.retained = false }
            session.finishedCycle(from: h.engine.identity,
                check: mode == 8 ? .updatesInBackground : .updates,
                error: mode == 6 ? initialFeedError(.downloadError) : mode == 18 ? nil : error)
            if mode == 17 { h.ui.errorAcknowledgements[0]() }
            XCTAssertTrue(h.unarmedRetirements.isEmpty, "mode \(mode)")
            XCTAssertEqual(h.retained, mode != 10, "mode \(mode)")
        }
    }

    @MainActor
    func testSameFeedErrorAfterAnyCandidateAttemptOrUnsafeActivityRemainsFenced() throws {
        for mode in 0..<15 {
            let h = Harness(); h.enableUnarmedRetirement = true
            let session = h.makeSession()
            try session.startManualCheck()
            try session.admitCheck(from: h.engine.identity, check: .updates)
            let driver = try XCTUnwrap(h.engine.userDriver)
            driver.showUserInitiatedUpdateCheck {}
            let item = SUAppcastItem.empty()
            switch mode {
            case 0: try session.admitUpdate(from: h.engine.identity, item: item, check: .updates)
            case 1:
                h.candidateError = TestFailure.refused
                XCTAssertThrowsError(try session.admitUpdate(from: h.engine.identity, item: item, check: .updates))
                XCTAssertTrue(h.boundCandidates.isEmpty)
            case 2:
                h.bindingError = TestFailure.refused
                XCTAssertThrowsError(try session.admitUpdate(from: h.engine.identity, item: item, check: .updates))
                XCTAssertTrue(h.boundCandidates.isEmpty)
            case 3:
                XCTAssertThrowsError(try session.admitUpdate(from: h.engine.identity,
                    item: item, check: .updateInformation))
                XCTAssertTrue(h.boundCandidates.isEmpty)
            case 4, 13:
                let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: mode == 13 ? 2 : 0)))
                driver.showUpdateFound(with: item, state: state) { _ in }
            case 5: session.foundUpdate(from: h.engine.identity, item: item)
            case 6:
                driver.showReady { _ in }
                h.ui.readyReply?(.install)
            case 7: driver.showDownloadInitiated {}
            case 8: driver.showDownloadDidStartExtractingUpdate()
            case 9: _ = session.permitsTargetTermination(from: h.engine.identity)
            case 10: _ = session.interceptInstallOnQuit(from: h.engine.identity, item: item)
            case 11: _ = session.extractionInvariantHolds(from: h.engine.identity)
            case 12: h.ui.checkCancellation?()
            default: driver.showInstallingUpdate(withApplicationTerminated: false) {}
            }
            let error = initialFeedError(.downloadError)
            driver.showUpdaterError(error) {}
            session.aborted(from: h.engine.identity, error: error)
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertTrue(h.unarmedRetirements.isEmpty, "mode \(mode)")
            XCTAssertTrue(h.retained, "mode \(mode)")
        }
    }

    @MainActor
    func testInitialFeedFailureCannotClearStartupFailureOrAbsentOwnerAdmission() throws {
        for startupFailure in [false, true] {
            let h = Harness()
            h.enableUnarmedRetirement = startupFailure
            if startupFailure { h.engine.startError = initialFeedError(.downloadError) }
            let session = h.makeSession()
            if startupFailure { XCTAssertThrowsError(try session.startManualCheck()) }
            else {
                try session.startManualCheck()
                try session.admitCheck(from: h.engine.identity, check: .updates)
            }
            let driver = try XCTUnwrap(h.engine.userDriver)
            driver.showUserInitiatedUpdateCheck {}
            let error = initialFeedError(.downloadError)
            driver.showUpdaterError(error) {}
            session.aborted(from: h.engine.identity, error: error)
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertTrue(h.unarmedRetirements.isEmpty)
            XCTAssertTrue(h.retained)
        }
    }

    @MainActor
    func testFeedFailureRetirementReentryOrVerifierFailureRetainsAuthority() throws {
        for reentry in [false, true] {
            let h = Harness(); h.enableUnarmedRetirement = true
            let session = h.makeSession()
            if reentry {
                h.onObservation = { value in
                    if case .cycleFinished = value.event { h.engine.userDriver?.showReady { _ in } }
                }
            } else { h.retirementError = TestFailure.refused }
            try session.startManualCheck()
            try session.admitCheck(from: h.engine.identity, check: .updates)
            let driver = try XCTUnwrap(h.engine.userDriver)
            driver.showUserInitiatedUpdateCheck {}
            let error = initialFeedError(.appcastParseError)
            driver.showUpdaterError(error) {}
            session.aborted(from: h.engine.identity, error: error)
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertEqual(h.unarmedRetirements.count, reentry ? 0 : 1)
            XCTAssertFalse(h.observationNames.contains("unarmed-retired"))
            XCTAssertTrue(h.retained)
            h.onObservation = nil
        }
    }

    @MainActor
    func testActualPrivateBrokerFeedFailureRequiresExplicitControlledHistory() throws {
        for controlled in [false, true] {
            let fixture = try PrivateBrokerFixture(); defer { fixture.remove() }
            let broker = try BelugaUpdateBrokerSession(context: fixture.context,
                acquireOwnership: { try fixture.acquire() })
            let h = Harness(target: fixture.bundle, operationID: fixture.operationID)
            var nativeSession: BelugaUpdateSparkleSession?
            let history: BelugaUpdateControlledHistoryAdmission? = controlled ?
                .init(verify: { _, _, _ in }) : nil
            let authority = BelugaUpdateSparkleSession.Authority(
                withPreparedAuthority: { operationID, body in
                    try broker.prepare(operationID: operationID, predecessorMenuInstanceID: UUID(),
                        controlledHistory: history, verifyPredecessor: { _ in try fixture.predecessor() })
                    try broker.bindBroker(.init(artifact: fixture.predecessor(),
                        nativeCDHash: Data(repeating: 7, count: 20)),
                        operationID: operationID, target: fixture.context.target)
                    h.retained = true
                    try broker.startUpdater(operationID: operationID, target: fixture.context.target, body)
                }, isRetained: { broker.ownsLease && broker.operationID == $0 && broker.state == .started },
                bindCandidate: { _, _ in XCTFail("Feed failure cannot bind a candidate") },
                authorizeInstallation: { _ in XCTFail("Feed failure cannot install"); return false },
                mayTerminateTarget: { _ in false }, retirePreparedUnarmed: { completion in
                    try broker.retirePreparedUnarmed(completion, verifyCompletion: { value in
                        guard nativeSession?.isCurrentUnarmedCompletion(value) == true else {
                            throw TestFailure.refused
                        }
                        XCTAssertThrowsError(try fixture.acquire())
                    }, verifyPredecessor: { _ in try fixture.predecessor() })
                })
            let session = h.makeSession(authority: authority)
            nativeSession = session
            try session.startManualCheck()
            try session.admitCheck(from: h.engine.identity, check: .updates)
            let driver = try XCTUnwrap(h.engine.userDriver)
            driver.showUserInitiatedUpdateCheck {}
            let error = initialFeedError(.downloadError)
            driver.showUpdaterError(error) {}
            session.aborted(from: h.engine.identity, error: error)
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertEqual(try fixture.store.read(expectedTarget: fixture.context.target) == nil, controlled)
            XCTAssertEqual(broker.ownsLease, !controlled)
            XCTAssertEqual(h.observationNames.contains("unarmed-retired"), controlled)
            if controlled {
                let next = try fixture.acquire(); next.release()
                XCTAssertEqual(broker.state, .cleared)
            }
            nativeSession = nil
        }
    }

    @MainActor
    func testRejectedCandidateDuringFailedCycleObservationInvalidatesMintedProof() throws {
        let h = Harness(); h.enableUnarmedRetirement = true
        let session = h.makeSession()
        var rejectedAdmissions = 0
        h.onObservation = { value in
            if case .cycleFinished = value.event {
                do {
                    try session.admitUpdate(from: h.engine.identity,
                        item: .empty(), check: .updates)
                    XCTFail("A finished failed check must reject candidate reentry")
                } catch {
                    rejectedAdmissions += 1
                }
            }
        }
        try session.startManualCheck()
        try session.admitCheck(from: h.engine.identity, check: .updates)
        let driver = try XCTUnwrap(h.engine.userDriver)
        driver.showUserInitiatedUpdateCheck {}
        let error = initialFeedError(.downloadError)
        driver.showUpdaterError(error) {}
        session.aborted(from: h.engine.identity, error: error)
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertEqual(rejectedAdmissions, 1)
        XCTAssertTrue(h.unarmedRetirements.isEmpty)
        XCTAssertFalse(h.observationNames.contains("unarmed-retired"))
        XCTAssertTrue(h.boundCandidates.isEmpty)
        XCTAssertTrue(h.installRequests.isEmpty)
        XCTAssertTrue(h.retained)
        h.onObservation = nil
    }

    @MainActor
    func testRejectedCandidateDuringActualCoreVerificationFailsSecondProofAndKeepsFence() throws {
        let fixture = try PrivateBrokerFixture(); defer { fixture.remove() }
        let broker = try BelugaUpdateBrokerSession(context: fixture.context,
            acquireOwnership: { try fixture.acquire() })
        let h = Harness(target: fixture.bundle, operationID: fixture.operationID)
        var nativeSession: BelugaUpdateSparkleSession?
        var verificationCalls = 0
        let authority = BelugaUpdateSparkleSession.Authority(
            withPreparedAuthority: { operationID, body in
                try broker.prepare(operationID: operationID, predecessorMenuInstanceID: UUID(),
                    controlledHistory: .init(verify: { _, _, _ in }),
                    verifyPredecessor: { _ in try fixture.predecessor() })
                try broker.bindBroker(.init(artifact: fixture.predecessor(),
                    nativeCDHash: Data(repeating: 7, count: 20)),
                    operationID: operationID, target: fixture.context.target)
                h.retained = true
                try broker.startUpdater(operationID: operationID, target: fixture.context.target, body)
            }, isRetained: { broker.ownsLease && broker.operationID == $0 && broker.state == .started },
            bindCandidate: { _, _ in XCTFail("Rejected admission cannot bind") },
            authorizeInstallation: { _ in XCTFail("No installation"); return false },
            mayTerminateTarget: { _ in false }, retirePreparedUnarmed: { completion in
                try broker.retirePreparedUnarmed(completion, verifyCompletion: { value in
                    verificationCalls += 1
                    guard let session = nativeSession,
                          session.isCurrentUnarmedCompletion(value) else { throw TestFailure.refused }
                    if verificationCalls == 1 {
                        XCTAssertThrowsError(try session.admitUpdate(from: h.engine.identity,
                            item: .empty(), check: .updates))
                        XCTAssertFalse(session.isCurrentUnarmedCompletion(value))
                        // Return deliberately: Core's second proof check must independently
                        // detect the invalidation before exact marker removal.
                    }
                }, verifyPredecessor: { _ in try fixture.predecessor() })
            })
        let session = h.makeSession(authority: authority)
        nativeSession = session
        try session.startManualCheck()
        try session.admitCheck(from: h.engine.identity, check: .updates)
        let driver = try XCTUnwrap(h.engine.userDriver)
        driver.showUserInitiatedUpdateCheck {}
        let error = initialFeedError(.appcastParseError)
        driver.showUpdaterError(error) {}
        session.aborted(from: h.engine.identity, error: error)
        let held = try fixture.current()
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertEqual(verificationCalls, 2)
        XCTAssertEqual(try fixture.current(), held)
        XCTAssertTrue(broker.ownsLease)
        XCTAssertThrowsError(try fixture.acquire())
        XCTAssertTrue(h.boundCandidates.isEmpty)
        XCTAssertTrue(h.installRequests.isEmpty)
        XCTAssertFalse(h.observationNames.contains("unarmed-retired"))
        XCTAssertEqual(h.observationNames.last, "unarmed-retirement-failed")
        nativeSession = nil
    }

    @MainActor
    func testSignedLookingCachedReplacedOrResumedItemCannotAuthorizeFirstInstall() throws {
        for mode in 0..<4 {
            let harness = Harness()
            let session = harness.makeSession()
            try session.startManualCheck()
            let item = try decodedCandidateFixture()
            XCTAssertEqual(item.signingValidationStatus, .succeeded)
            if mode != 0 {
                try session.admitCheck(from: harness.engine.identity, check: .updates)
                let admitted = mode == 1 ? try decodedCandidateFixture() : item
                if mode == 1 { XCTAssertFalse(admitted === item) }
                try session.admitUpdate(from: harness.engine.identity,
                                        item: admitted, check: .updates)
            }
            if mode == 3 {
                session.finishedCycle(from: harness.engine.identity, check: .updates, error: nil)
            }
            let driver = try XCTUnwrap(harness.engine.userDriver)
            let state = try XCTUnwrap(SPUUserUpdateState(coder: FixtureCoder(stage: mode == 2 ? 2 : 0)))
            if mode == 2 { XCTAssertEqual(state.stage, .installing) }
            var choices = [SPUUserUpdateChoice]()
            driver.showUpdateFound(with: item, state: state) { choices.append($0) }
            harness.ui.foundReply?(.install)
            XCTAssertEqual(choices, [.dismiss], "mode \(mode)")
            XCTAssertTrue(harness.installRequests.isEmpty)
            XCTAssertTrue(harness.retained)
            XCTAssertFalse(session.permitsTargetTermination(from: harness.engine.identity))
        }
    }
}

@MainActor
private final class Harness {
    let operationID: UUID
    let target: Bundle
    let feed = "https://updates.example.invalid/beluga/appcast.xml"
    let ui = FakeUserDriver()
    let engine = FakeEngine()
    var events = [String]()
    var preparedOperations = [UUID]()
    var retained = false
    var preparation = Preparation.normal
    var installResult = InstallResult.allow
    var installRequests = [BelugaUpdateInstallRequest]()
    var boundCandidates = [BelugaUpdateOperation.ArtifactIdentity]()
    var candidateError: Error?
    var candidateOverride: BelugaUpdateOperation.ArtifactIdentity?
    var candidateInput: BelugaUpdateCandidateMetadata.Input?
    var bindingError: Error?
    var onBind: (() -> Void)?
    var allowTermination = true
    var terminationRequests = 0
    var observations = [BelugaUpdateSparkleSession.Observation]()
    var onUIFactory: (() -> Void)?
    var onEngineFactory: (() -> Void)?
    var onTermination: (() -> Void)?
    var enableUnarmedRetirement = false
    var unarmedRetirements = [BelugaUpdateUnarmedCompletion]()
    var retirementError: Error?
    var onObservation: ((BelugaUpdateSparkleSession.Observation) -> Void)?
    private weak var currentSession: BelugaUpdateSparkleSession?

    init(target: Bundle = .main, operationID: UUID = UUID()) {
        self.target = target
        self.operationID = operationID
    }

    func admitFreshCandidate(to session: BelugaUpdateSparkleSession) throws -> SUAppcastItem {
        try session.admitCheck(from: engine.identity, check: .updates)
        let item = SUAppcastItem.empty()
        try session.admitUpdate(from: engine.identity, item: item, check: .updates)
        return item
    }

    func makeSession(authority suppliedAuthority: BelugaUpdateSparkleSession.Authority? = nil)
        -> BelugaUpdateSparkleSession {
        engine.event = { [self] in events.append($0) }
        var retirementHandler: (@MainActor (BelugaUpdateUnarmedCompletion) throws -> Void)?
        if enableUnarmedRetirement {
            retirementHandler = { [self] completion in
                XCTAssertTrue(currentSession?.isCurrentUnarmedCompletion(completion) == true)
                unarmedRetirements.append(completion)
                if let retirementError { throw retirementError }
            }
        }
        let authority = BelugaUpdateSparkleSession.Authority(
            withPreparedAuthority: { [self] operationID, body in
                preparedOperations.append(operationID)
                events.append("prepared")
                if preparation == .reject { throw TestFailure.refused }
                if preparation == .omit { return }
                retained = preparation != .noRetainedAuthority
                try body()
                if preparation == .twice { try body() }
                if preparation == .failAfterBody { throw TestFailure.refused }
            }, isRetained: { [self] in $0 == operationID && retained },
            bindCandidate: { [self] value, candidate in
                XCTAssertEqual(value, operationID)
                if let bindingError { throw bindingError }
                boundCandidates.append(candidate)
                onBind?()
            },
            authorizeInstallation: { [self] request in
                installRequests.append(request)
                if installResult == .fail { throw TestFailure.refused }
                if installResult == .revokeAfterAllow { retained = false }
                return installResult != .deny
            }, mayTerminateTarget: { [self] value in
                XCTAssertEqual(value, operationID)
                terminationRequests += 1
                onTermination?()
                return allowTermination
            }, retirePreparedUnarmed: retirementHandler)
        let factory = BelugaUpdateSparkleSession.Factory(userDriver: { [self] bundle in
            XCTAssertTrue(retained)
            XCTAssertTrue(bundle === target)
            events.append("ui-factory")
            onUIFactory?()
            return ui
        }, engine: { [self] bundle, userDriver, delegate in
            XCTAssertTrue(retained)
            events.append("engine-factory")
            engine.target = bundle
            engine.userDriver = userDriver
            engine.delegate = delegate
            onEngineFactory?()
            return engine
        }, candidate: { [self] _ in
            if let candidateError { throw candidateError }
            if let candidateInput { return try BelugaUpdateCandidateMetadata.parse(candidateInput) }
            if let candidateOverride { return candidateOverride }
            return try .init(version: "0.2.1", build: 101,
                executableSHA256: String(repeating: "c", count: 64),
                dependencyClosureSHA256: String(repeating: "d", count: 64))
        })
        let session = BelugaUpdateSparkleSession(targetBundle: target, operationID: operationID,
            authority: suppliedAuthority ?? authority, verifiedFeedURLString: feed, factory: factory,
            observe: { [self] in observations.append($0); onObservation?($0) })
        currentSession = session
        return session
    }

    var observationNames: [String] {
        observations.map { value in
            switch value.event {
            case .candidateFound: "candidate"
            case .resumePossible: "resume-possible"
            case .resumedInstallation: "resumed-installation"
            case .noUpdate: "no-update"
            case .cycleFinished: "cycle"
            case .aborted: "aborted"
            case .startupFailed: "startup-failed"
            case .willExtract: "extract"
            case .willInstall: "install"
            case .unexpectedInstallOnQuit: "install-on-quit"
            case .targetTerminationRequested: "termination"
            case .installed: "installed"
            case .extractionInvariantFailed: "extraction-invariant"
            case .unarmedRetired: "unarmed-retired"
            case .unarmedRetirementFailed: "unarmed-retirement-failed"
            }
        }
    }
}

@MainActor
private final class FakeEngine: BelugaUpdateSparkleSession.Engine {
    let identity = NSObject()
    var callbackIdentity: AnyObject { identity }
    var sessionInProgress = false
    var starts = 0
    var checks = 0
    var startError: Error?
    var event: (String) -> Void = { _ in }
    var onStart: (() -> Void)?
    var onCheck: (() -> Void)?
    var target: Bundle?
    var userDriver: (any SPUUserDriver)?
    weak var delegate: (any SPUUpdaterDelegate)?
    func configureManualOnly() { event("manual-only") }
    func start() throws {
        starts += 1
        event("start")
        onStart?()
        if let startError { throw startError }
    }
    func checkForUpdates() { checks += 1; event("manual-check"); onCheck?() }
}

@MainActor
private final class FakeUserDriver: NSObject, SPUUserDriver {
    var foundReply: ((SPUUserUpdateChoice) -> Void)?
    var readyReply: ((SPUUserUpdateChoice) -> Void)?
    var retry: (() -> Void)?
    var checkCancellation: (() -> Void)?
    var downloadCancellation: (() -> Void)?
    var deferErrorAcknowledgements = false
    var errorAcknowledgements = [() -> Void]()
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {}
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { checkCancellation = cancellation }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) { foundReply = reply }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        errorAcknowledgements.append(acknowledgement)
        if !deferErrorAcknowledgements { acknowledgement() }
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { downloadCancellation = cancellation }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { readyReply = reply }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) { retry = retryTerminatingApplication }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}

private final class FixtureCoder: NSCoder {
    let stage: Int
    let userInitiated: Bool
    init(stage: Int, userInitiated: Bool = false) {
        self.stage = stage; self.userInitiated = userInitiated; super.init()
    }
    override var allowsKeyedCoding: Bool { true }
    override func decodeInteger(forKey key: String) -> Int { stage }
    override func decodeBool(forKey key: String) -> Bool { userInitiated }
}
private enum Preparation { case normal, omit, reject, noRetainedAuthority, twice, failAfterBody }
private enum InstallResult { case allow, deny, fail, revokeAfterAllow }
private enum TestFailure: Error { case refused }

private func manualNoUpdateError(manual: Bool = true) -> NSError {
    NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue),
            userInfo: [SPUNoUpdateFoundUserInitiatedKey: manual])
}

private func initialFeedError(_ code: SUError) -> NSError {
    NSError(domain: SUSparkleErrorDomain, code: Int(code.rawValue))
}

/// Saved SDK status is intentionally synthesized here, with no feed signature.
/// This demonstrates why a decoded .succeeded item is not fresh admission proof.
private func decodedCandidateFixture() throws -> SUAppcastItem {
    let archive = NSKeyedArchiver(requiringSecureCoding: true)
    archive.encode(URL(string: "https://updates.example.invalid/Beluga.dmg")! as NSURL, forKey: "fileURL")
    archive.encode("application" as NSString, forKey: "SUAppcastItemInstallationType")
    archive.encode("101" as NSString, forKey: "versionString")
    archive.encode("0.2.1" as NSString, forKey: "displayVersionString")
    archive.encode([:] as NSDictionary, forKey: "propertiesDictionary")
    archive.encode(SPUAppcastSigningValidationStatus.succeeded.rawValue,
                   forKey: "SUAppcastItemSigningValidationStatus")
    archive.finishEncoding()
    let decoder = try NSKeyedUnarchiver(forReadingFrom: archive.encodedData)
    defer { decoder.finishDecoding() }
    return try XCTUnwrap(SUAppcastItem(coder: decoder))
}

/// This regression creates only its own unique private target, account-home and lock.
/// It performs no signing, real Sparkle, network, app launch, capture or production I/O.
private struct PrivateBrokerFixture {
    let root: URL
    let bundle: Bundle
    let context: BelugaUpdateRuntimeContext
    let store: BelugaUpdateFenceStore
    let lockDirectory: URL
    let operationID = UUID()

    init() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("beluga-sparkle-composition-" + UUID().uuidString, isDirectory: true)
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let app = root.appendingPathComponent("Beluga.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let info: [String: Any] = [
            "CFBundleIdentifier": BelugaUpdateOperation.expectedBundleIdentifier,
            "CFBundlePackageType": "APPL", "CFBundleVersion": "100",
            "SUFeedURL": "https://updates.example.invalid/beluga/appcast.xml",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        bundle = try XCTUnwrap(Bundle(url: app))
        context = try XCTUnwrap(BelugaUpdateRuntimeContext.resolve(
            bundleIdentifier: BelugaUpdateOperation.expectedBundleIdentifier, bundleURL: app,
            inputs: .init(effectiveUID: Darwin.geteuid(), accountHomeDirectory: { _ in root })))
        store = try BelugaUpdateFenceStore(directoryURL: context.fenceDirectoryURL)
        lockDirectory = root.appendingPathComponent("runtime-lock", isDirectory: true)
    }

    func acquire() throws -> WorldwideHostProcessLock {
        try WorldwideHostProcessLock.acquire(lockDirectoryURL: lockDirectory)
    }
    func current() throws -> BelugaUpdateFenceStore.Snapshot {
        try XCTUnwrap(store.read(expectedTarget: context.target))
    }
    func predecessor() throws -> BelugaUpdateOperation.ArtifactIdentity {
        try .init(version: "0.2.0", build: 100, executableSHA256: String(repeating: "a", count: 64),
                  dependencyClosureSHA256: String(repeating: "b", count: 64))
    }
    func candidate() throws -> BelugaUpdateOperation.ArtifactIdentity {
        try .init(version: "0.2.1", build: 101, executableSHA256: String(repeating: "c", count: 64),
                  dependencyClosureSHA256: String(repeating: "d", count: 64))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
