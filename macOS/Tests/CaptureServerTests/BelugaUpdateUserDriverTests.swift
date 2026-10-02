import Foundation
import Sparkle
import XCTest
@testable import BelugaUpdateDriver

final class BelugaUpdateUserDriverTests: XCTestCase {
    @MainActor
    func testInstalledObservationPrecedesSynchronousDelegationAndAcknowledgement() {
        let operationID = UUID()
        let fake = FakeUpdateUserDriver()
        var events = [String]()
        var observations = [BelugaUpdateUserDriver.InstalledObservation]()
        fake.onInstalled = { _ in events.append("delegate") }
        let adapter = BelugaUpdateUserDriver(operationID: operationID, userDriver: fake,
                                             authorizeInstallation: { _ in true }) {
            observations.append($0)
            events.append("observe")
        }

        adapter.showUpdateInstalledAndRelaunched(true) { events.append("acknowledge") }

        XCTAssertEqual(events, ["observe", "delegate", "acknowledge"])
        XCTAssertEqual(observations, [.init(operationID: operationID, relaunched: true)])
    }

    @MainActor
    func testNotRelaunchedStillObservesRealInstalledCallbackWithoutInventingReadiness() {
        let operationID = UUID()
        let fake = FakeUpdateUserDriver()
        var observations = [BelugaUpdateUserDriver.InstalledObservation]()
        var acknowledged = false
        let adapter = BelugaUpdateUserDriver(operationID: operationID, userDriver: fake,
                                             authorizeInstallation: { _ in true }) {
            observations.append($0)
        }

        adapter.showUpdateInstalledAndRelaunched(false) { acknowledged = true }

        XCTAssertEqual(observations, [.init(operationID: operationID, relaunched: false)])
        XCTAssertEqual(fake.installedArguments, [false])
        XCTAssertTrue(acknowledged)
    }

    @MainActor
    func testDuplicateCallbackObservesOnceButForwardsEveryAcknowledgement() {
        let operationID = UUID()
        let fake = FakeUpdateUserDriver()
        var observations = [BelugaUpdateUserDriver.InstalledObservation]()
        var acknowledgements = [Int]()
        let adapter = BelugaUpdateUserDriver(operationID: operationID, userDriver: fake,
                                             authorizeInstallation: { _ in true }) {
            observations.append($0)
        }

        adapter.showUpdateInstalledAndRelaunched(false) { acknowledgements.append(1) }
        adapter.dismissUpdateInstallation()
        adapter.showUpdaterError(testError) { acknowledgements.append(2) }
        adapter.showUpdateInstalledAndRelaunched(true) { acknowledgements.append(3) }

        XCTAssertEqual(observations, [.init(operationID: operationID, relaunched: false)])
        XCTAssertEqual(fake.installedArguments, [false, true])
        XCTAssertEqual(acknowledgements, [1, 2, 3])
    }

    @MainActor
    func testSynchronousReentrantObserverCannotPublishASecondTerminalObservation() {
        let operationID = UUID()
        let fake = FakeUpdateUserDriver()
        var observations = [BelugaUpdateUserDriver.InstalledObservation]()
        var acknowledgements = 0
        let reference = AdapterReference()
        let adapter = BelugaUpdateUserDriver(operationID: operationID, userDriver: fake,
                                         authorizeInstallation: { _ in true }) {
            observations.append($0)
            if observations.count == 1 {
                reference.value?.showUpdateInstalledAndRelaunched(false) { acknowledgements += 1 }
            }
        }
        reference.value = adapter

        adapter.showUpdateInstalledAndRelaunched(true) { acknowledgements += 1 }

        XCTAssertEqual(observations, [.init(operationID: operationID, relaunched: true)])
        XCTAssertEqual(fake.installedArguments, [false, true])
        XCTAssertEqual(acknowledgements, 2)
    }

    @MainActor
    func testOperationIdentityIsFixedPerAdapterRatherThanSharedAcrossOperations() {
        let firstID = UUID()
        let secondID = UUID()
        let fake = FakeUpdateUserDriver()
        var observations = [BelugaUpdateUserDriver.InstalledObservation]()
        let first = BelugaUpdateUserDriver(operationID: firstID, userDriver: fake,
                                           authorizeInstallation: { _ in true }) {
            observations.append($0)
        }
        let second = BelugaUpdateUserDriver(operationID: secondID, userDriver: fake,
                                            authorizeInstallation: { _ in true }) {
            observations.append($0)
        }

        first.showUpdateInstalledAndRelaunched(true) {}
        second.showUpdateInstalledAndRelaunched(false) {}
        first.showUpdateInstalledAndRelaunched(false) {}

        XCTAssertEqual(observations, [.init(operationID: firstID, relaunched: true),
                                     .init(operationID: secondID, relaunched: false)])
    }

    @MainActor
    func testForwardsEveryNonterminalRouteWithoutCreatingInstalledEvidence() throws {
        let fake = FocusUpdateUserDriver()
        fake.deferCancellations = true
        fake.foundChoice = .install
        fake.readyChoice = .install
        var observations = [BelugaUpdateUserDriver.InstalledObservation]()
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                                             authorizeInstallation: { _ in true }) {
            observations.append($0)
        }
        let request = SPUUpdatePermissionRequest(systemProfile: [])
        let item = SUAppcastItem.empty()
        let state = try XCTUnwrap(SPUUserUpdateState(coder: StateFixtureCoder()))
        // Public NSObject construction suffices: this fake asserts identity only and
        // never reads or renders release-note contents.
        let download = SPUDownloadData()
        let error = testError
        var replies = [String]()

        adapter.show(request) { response in
            XCTAssertTrue(response === fake.permissionResponse)
            replies.append("permission")
        }
        adapter.showUserInitiatedUpdateCheck { replies.append("check-cancel") }
        adapter.showUpdateFound(with: item, state: state) { choice in
            XCTAssertEqual(choice, .install)
            replies.append("found")
        }
        adapter.showUpdateReleaseNotes(with: download)
        adapter.showUpdateReleaseNotesFailedToDownloadWithError(error)
        adapter.showDownloadInitiated { replies.append("download-cancel") }
        adapter.showDownloadDidReceiveExpectedContentLength(UInt64.max)
        adapter.showDownloadDidReceiveData(ofLength: UInt64.max - 1)
        adapter.showDownloadDidStartExtractingUpdate()
        adapter.showExtractionReceivedProgress(0.375)
        adapter.showReady { choice in
            XCTAssertEqual(choice, .install)
            replies.append("ready")
        }
        adapter.showInstallingUpdate(withApplicationTerminated: false) {
            replies.append("retry")
        }
        adapter.showUpdateNotFoundWithError(error) { replies.append("not-found") }
        adapter.showUpdaterError(error) { replies.append("error") }
        adapter.dismissUpdateInstallation()
        adapter.showUpdateInFocus()

        XCTAssertEqual(fake.events, ["permission", "check", "found", "notes", "notes-error",
                                     "download", "content-length", "data-length", "extracting", "progress",
                                     "ready", "installing", "not-found", "error", "dismiss", "focus"])
        XCTAssertTrue(fake.request === request)
        XCTAssertTrue(fake.item === item)
        XCTAssertTrue(fake.state === state)
        XCTAssertTrue(fake.download === download)
        XCTAssertEqual(fake.errors.count, 3)
        for receivedError in fake.errors { XCTAssertTrue(receivedError === error) }
        XCTAssertEqual(fake.expectedContentLength, UInt64.max)
        XCTAssertEqual(fake.dataLength, UInt64.max - 1)
        XCTAssertEqual(fake.extractionProgress, 0.375)
        XCTAssertEqual(fake.applicationTerminated, false)
        XCTAssertEqual(replies, ["permission", "found", "ready", "retry", "not-found", "error"])
        XCTAssertTrue(observations.isEmpty)
    }

    @MainActor
    func testFocusIsSafeWhenInjectedDriverDoesNotImplementOptionalSelector() {
        let fake = FakeUpdateUserDriver()
        var observations = [BelugaUpdateUserDriver.InstalledObservation]()
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                                             authorizeInstallation: { _ in true }) {
            observations.append($0)
        }

        adapter.showUpdateInFocus()

        XCTAssertTrue(fake.events.isEmpty)
        XCTAssertTrue(observations.isEmpty)
    }

    @MainActor
    func testFoundInstallPublishesAuthorizationBeforeForwardingForEveryPublicStage() throws {
        for stage in [SPUUserUpdateStage.notDownloaded, .downloaded, .installing] {
            let operationID = UUID()
            let fake = FakeUpdateUserDriver()
            fake.foundChoice = .install
            let item = SUAppcastItem.empty()
            let state = try XCTUnwrap(SPUUserUpdateState(coder: StateFixtureCoder(stage: stage.rawValue)))
            var events = [String]()
            var requests = [BelugaUpdateUserDriver.InstallRequest]()
            let adapter = BelugaUpdateUserDriver(operationID: operationID, userDriver: fake,
                authorizeInstallation: { request in
                    requests.append(request)
                    guard case .updateFound(let receivedItem, let receivedState) = request.phase else {
                        XCTFail("Wrong authorization phase")
                        return false
                    }
                    XCTAssertTrue(receivedItem === item)
                    XCTAssertTrue(receivedState === state)
                    events.append("durably-authorized")
                    return true
                }, installed: { _ in XCTFail("Choice is not installed evidence") })

            adapter.showUpdateFound(with: item, state: state) { choice in
                XCTAssertEqual(choice, .install)
                events.append("forwarded")
            }

            XCTAssertEqual(events, ["durably-authorized", "forwarded"])
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.operationID, operationID)
        }
    }

    @MainActor
    func testReadyInstallExplicitAllowDeniedAndThrowingAuthorization() {
        for result in [AuthorizationResult.allow, .deny, .fail] {
            let fake = FakeUpdateUserDriver()
            fake.readyChoice = .install
            let operationID = UUID()
            var requests = [BelugaUpdateUserDriver.InstallRequest]()
            var forwarded = [SPUUserUpdateChoice]()
            let adapter = BelugaUpdateUserDriver(operationID: operationID, userDriver: fake,
                authorizeInstallation: { request in
                    requests.append(request)
                    guard case .readyToInstallAndRelaunch = request.phase else {
                        XCTFail("Wrong authorization phase")
                        return false
                    }
                    return try result.authorize()
                }, installed: { _ in XCTFail("Authorization is not installed evidence") })

            adapter.showReady { forwarded.append($0) }

            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.operationID, operationID)
            XCTAssertEqual(forwarded, [result == .allow ? .install : .dismiss])
        }
    }

    @MainActor
    func testDeniedOrThrowingFoundInstallUsesDismissWithoutInstalledEvidence() throws {
        let state = try XCTUnwrap(SPUUserUpdateState(coder: StateFixtureCoder()))
        for result in [AuthorizationResult.deny, .fail] {
            let fake = FakeUpdateUserDriver()
            fake.foundChoice = .install
            var calls = 0
            var forwarded = [SPUUserUpdateChoice]()
            let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                authorizeInstallation: { _ in
                    calls += 1
                    return try result.authorize()
                }, installed: { _ in XCTFail("Dismissal is not installed evidence") })

            adapter.showUpdateFound(with: .empty(), state: state) { forwarded.append($0) }

            XCTAssertEqual(calls, 1)
            XCTAssertEqual(forwarded, [.dismiss])
        }
    }

    @MainActor
    func testDismissAndSkipForwardWithoutConsultingAuthorization() throws {
        let state = try XCTUnwrap(SPUUserUpdateState(coder: StateFixtureCoder()))
        for choice in [SPUUserUpdateChoice.dismiss, .skip] {
            for ready in [false, true] {
                let fake = FakeUpdateUserDriver()
                fake.foundChoice = choice
                fake.readyChoice = choice
                var forwarded = [SPUUserUpdateChoice]()
                let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                    authorizeInstallation: { _ in
                        XCTFail("Non-install choice must not obtain install authority")
                        return false
                    }, installed: { _ in XCTFail("UI choice is not installed evidence") })
                if ready { adapter.showReady { forwarded.append($0) } }
                else { adapter.showUpdateFound(with: .empty(), state: state) { forwarded.append($0) } }
                XCTAssertEqual(forwarded, [choice])
            }
        }
    }

    @MainActor
    func testSupersededAndDuplicateRepliesCannotAuthorizeOrAbortNewPresentation() throws {
        let fake = FakeUpdateUserDriver()
        fake.deferReplies = true
        var requests = [BelugaUpdateUserDriver.InstallRequest]()
        var forwarded = [SPUUserUpdateChoice]()
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
            authorizeInstallation: { requests.append($0); return true }, installed: { _ in })
        let state = try XCTUnwrap(SPUUserUpdateState(coder: StateFixtureCoder()))
        adapter.showUpdateFound(with: .empty(), state: state) { forwarded.append($0) }
        adapter.showReady { forwarded.append($0) }

        fake.foundReplies[0](.install)
        fake.foundReplies[0](.dismiss)
        fake.readyReplies[0](.install)
        fake.readyReplies[0](.install)
        fake.readyReplies[0](.skip)

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(forwarded, [.install])
        let request = try XCTUnwrap(requests.first)
        guard case .readyToInstallAndRelaunch = request.phase else {
            return XCTFail("Only the current presentation may request authorization")
        }
    }

    @MainActor
    func testTerminalUncertaintyRetiresPendingAndLaterPresentationReplies() throws {
        for terminal in [TerminalEvent.error, .notFound, .dismiss, .installed] {
            let fake = FakeUpdateUserDriver()
            fake.deferReplies = true
            var requests = 0
            var observations = 0
            var forwarded = [SPUUserUpdateChoice]()
            let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                authorizeInstallation: { _ in requests += 1; return true },
                installed: { _ in observations += 1 })
            let state = try XCTUnwrap(SPUUserUpdateState(coder: StateFixtureCoder()))
            adapter.showUpdateFound(with: .empty(), state: state) { forwarded.append($0) }

            switch terminal {
            case .error: adapter.showUpdaterError(testError) {}
            case .notFound: adapter.showUpdateNotFoundWithError(testError) {}
            case .dismiss: adapter.dismissUpdateInstallation()
            case .installed: adapter.showUpdateInstalledAndRelaunched(false) {}
            }
            fake.foundReplies[0](.install)
            adapter.showReady { forwarded.append($0) }
            fake.readyReplies[0](.install)

            XCTAssertEqual(requests, 0)
            XCTAssertTrue(forwarded.isEmpty)
            XCTAssertEqual(observations, terminal == .installed ? 1 : 0)
        }
    }

    @MainActor
    func testAuthorizationReentryCannotLeakInstallAfterDismissOrPromptReplacement() {
        for replacePrompt in [false, true] {
            let fake = FakeUpdateUserDriver()
            fake.deferReplies = true
            var calls = 0
            var forwarded = [SPUUserUpdateChoice]()
            let reference = AdapterReference()
            let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                authorizeInstallation: { _ in
                    calls += 1
                    if calls == 1 {
                        if replacePrompt { reference.value?.showReady { forwarded.append($0) } }
                        else { reference.value?.dismissUpdateInstallation() }
                    }
                    return true
                }, installed: { _ in })
            reference.value = adapter
            adapter.showReady { forwarded.append($0) }

            fake.readyReplies[0](.install)
            XCTAssertTrue(forwarded.isEmpty)
            if replacePrompt {
                fake.readyReplies[1](.install)
                XCTAssertEqual(forwarded, [.install])
                XCTAssertEqual(calls, 2)
            } else { XCTAssertEqual(calls, 1) }
        }
    }

    @MainActor
    func testReplyIsConsumedBeforeAuthorizationCanReenterSameCallback() {
        let fake = FakeUpdateUserDriver()
        fake.deferReplies = true
        var calls = 0
        var forwarded = [SPUUserUpdateChoice]()
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
            authorizeInstallation: { _ in
                calls += 1
                if calls == 1 { fake.readyReplies[0](.install) }
                return true
            }, installed: { _ in })
        adapter.showReady { forwarded.append($0) }

        fake.readyReplies[0](.install)

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(forwarded, [.install])
    }

    @MainActor
    func testRetryTerminationRequiresFreshAuthorizationAndNeverRetriesTerminatedApplication() {
        for terminated in [false, true] {
            for result in [AuthorizationResult.allow, .deny, .fail] {
                let fake = FakeUpdateUserDriver()
                fake.deferReplies = true
                var requests = 0
                var retries = 0
                let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                    authorizeInstallation: { request in
                        requests += 1
                        guard case .retryTerminatingApplication = request.phase else {
                            XCTFail("Wrong retry authorization phase")
                            return false
                        }
                        return try result.authorize()
                    }, installed: { _ in })
                adapter.showInstallingUpdate(withApplicationTerminated: terminated) { retries += 1 }

                fake.retries[0]()
                fake.retries[0]()
                XCTAssertEqual(requests, terminated ? 0 : 2)
                XCTAssertEqual(retries, !terminated && result == .allow ? 2 : 0)
                adapter.showReady { _ in }
                fake.retries[0]()
                XCTAssertEqual(requests, terminated ? 0 : 2)
            }
        }
    }

    @MainActor
    func testRetryAuthorizationReentryAndTerminalErrorCannotRestartTermination() {
        let fake = FakeUpdateUserDriver()
        fake.deferReplies = true
        var requests = 0
        var retries = 0
        let reference = AdapterReference()
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
            authorizeInstallation: { _ in
                requests += 1
                fake.retries[0]()
                reference.value?.showUpdaterError(self.testError) {}
                return true
            }, installed: { _ in })
        reference.value = adapter
        adapter.showInstallingUpdate(withApplicationTerminated: false) { retries += 1 }

        fake.retries[0]()
        fake.retries[0]()

        XCTAssertEqual(requests, 1)
        XCTAssertEqual(retries, 0)
    }

    @MainActor
    func testStaleCancellationCannotRetireSuccessorAndCurrentCancellationIsOneShot() {
        let fake = FakeUpdateUserDriver()
        fake.deferReplies = true
        var cancelled = 0
        var forwarded = [SPUUserUpdateChoice]()
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
            authorizeInstallation: { _ in true }, installed: { _ in })
        adapter.showUserInitiatedUpdateCheck { cancelled += 1 }
        adapter.showReady { forwarded.append($0) }

        fake.checkCancellations[0]()
        fake.readyReplies[0](.install)
        XCTAssertEqual(cancelled, 0)
        XCTAssertEqual(forwarded, [.install])

        adapter.showDownloadInitiated { cancelled += 1 }
        fake.downloadCancellations[0]()
        fake.downloadCancellations[0]()
        XCTAssertEqual(cancelled, 1)
    }

    @MainActor
    func testAcceptedCheckAndDownloadCancellationRetireLateInstallAuthority() {
        for cancelDownload in [false, true] {
            let fake = FakeUpdateUserDriver()
            fake.deferReplies = true
            var cancelled = 0
            var authorizations = 0
            var forwarded = [SPUUserUpdateChoice]()
            let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                authorizeInstallation: { _ in authorizations += 1; return true },
                installed: { _ in XCTFail("Cancellation is not installed evidence") })
            if cancelDownload {
                adapter.showDownloadInitiated { cancelled += 1 }
                fake.downloadCancellations[0]()
                fake.downloadCancellations[0]()
            } else {
                adapter.showUserInitiatedUpdateCheck { cancelled += 1 }
                fake.checkCancellations[0]()
                fake.checkCancellations[0]()
            }

            adapter.showReady { forwarded.append($0) }
            fake.readyReplies[0](.install)
            fake.readyReplies[0](.dismiss)
            adapter.showInstallingUpdate(withApplicationTerminated: false) {
                XCTFail("Cancelled operation cannot restart termination")
            }
            fake.retries[0]()

            XCTAssertEqual(cancelled, 1)
            XCTAssertEqual(authorizations, 0)
            XCTAssertTrue(forwarded.isEmpty)
        }
    }

    @MainActor
    func testInitialCheckCancellationReportsExactOneShotIntentBeforeSDKForwarding() throws {
        let fake = FakeUpdateUserDriver(); fake.deferReplies = true
        var presented = [UUID](), cancelled = [UUID](), order = [String]()
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
            authorizeInstallation: { _ in XCTFail("No install"); return false },
            unarmedIntent: { intent in
                switch intent {
                case .initialCheckShown(let id): presented.append(id)
                case .cancelledInitialCheck(let id): cancelled.append(id); order.append("intent")
                default: XCTFail("Unexpected initial-check intent")
                }
            }, installed: { _ in XCTFail("No installed evidence") })
        adapter.showUserInitiatedUpdateCheck { order.append("sdk-cancel") }
        XCTAssertEqual(presented.count, 1)
        XCTAssertTrue(cancelled.isEmpty)
        fake.checkCancellations[0]()
        fake.checkCancellations[0]()
        XCTAssertEqual(cancelled, presented)
        XCTAssertEqual(order, ["intent", "sdk-cancel"])
    }

    @MainActor
    func testDownloadCancellationCannotProduceInitialCheckCompletionIntent() {
        let fake = FakeUpdateUserDriver(); fake.deferReplies = true
        var unsafe = 0, cancelled = 0
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
            authorizeInstallation: { _ in false }, unarmedIntent: { intent in
                if case .unsafeActivity = intent { unsafe += 1 }
                else { XCTFail("Download must not report safe check cancellation") }
            }, installed: { _ in })
        adapter.showDownloadInitiated { cancelled += 1 }
        fake.downloadCancellations[0]()
        fake.downloadCancellations[0]()
        XCTAssertEqual(unsafe, 2)
        XCTAssertEqual(cancelled, 1)
    }

    @MainActor
    func testDeclineIntentPrecedesExactSDKReplyAndRetiresAllLaterInstallAuthority() throws {
        for choice in [SPUUserUpdateChoice.dismiss, .skip] {
            let fake = FakeUpdateUserDriver(); fake.deferReplies = true
            let item = SUAppcastItem.empty()
            let state = try XCTUnwrap(SPUUserUpdateState(coder: StateFixtureCoder()))
            var intentCount = 0, order = [String](), forwarded = [SPUUserUpdateChoice]()
            let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                authorizeInstallation: { _ in XCTFail("Decline cannot install"); return true },
                unarmedIntent: { intent in
                    if case .declinedCandidate(let id, let received, let receivedState, let value) = intent {
                        XCTAssertNotEqual(id, UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
                        XCTAssertTrue(received === item)
                        XCTAssertTrue(receivedState === state)
                        XCTAssertEqual(value, choice)
                        intentCount += 1; order.append("intent")
                    }
                }, installed: { _ in XCTFail("Decline is not installed") })
            adapter.showUpdateFound(with: item, state: state) { forwarded.append($0); order.append("sdk") }
            fake.foundReplies[0](choice)
            fake.foundReplies[0](.install)
            adapter.showReady { forwarded.append($0) }
            fake.readyReplies[0](.install)
            XCTAssertEqual(intentCount, 1)
            XCTAssertEqual(order, ["intent", "sdk"])
            XCTAssertEqual(forwarded, [choice])
        }
    }

    @MainActor
    func testSupersededDeclineAndDeniedInstallSubstitutionNeverReportDeclineIntent() throws {
        for superseded in [false, true] {
            let fake = FakeUpdateUserDriver(); fake.deferReplies = true
            var declined = 0, forwarded = [SPUUserUpdateChoice]()
            let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                authorizeInstallation: { _ in false }, unarmedIntent: { intent in
                    if case .declinedCandidate = intent { declined += 1 }
                }, installed: { _ in })
            let state = try XCTUnwrap(SPUUserUpdateState(coder: StateFixtureCoder()))
            adapter.showUpdateFound(with: .empty(), state: state) { forwarded.append($0) }
            if superseded {
                adapter.showReady { forwarded.append($0) }
                fake.foundReplies[0](.dismiss)
                XCTAssertTrue(forwarded.isEmpty)
            } else {
                fake.foundReplies[0](.install)
                XCTAssertEqual(forwarded, [.dismiss])
            }
            XCTAssertEqual(declined, 0)
        }
    }

    @MainActor
    private var testError: NSError { NSError(domain: "Beluga.UpdateUserDriver.Test", code: 1) }

    @MainActor
    func testErrorAcknowledgementReportsExactOneShotIntentBeforeSDKForwarding() throws {
        let fake = FakeUpdateUserDriver(); fake.deferErrorAcknowledgements = true
        let error = testError
        var shown = [UUID](), acknowledged = [UUID](), order = [String]()
        var sdkAcknowledgements = 0, installAuthorizations = 0
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
            authorizeInstallation: { _ in installAuthorizations += 1; return true },
            unarmedIntent: { intent in
                switch intent {
                case .failedInitialCheckShown(let id, let received):
                    XCTAssertTrue(received === error)
                    shown.append(id); order.append("shown")
                case .acknowledgedFailedInitialCheck(let id, let received):
                    XCTAssertTrue(received === error)
                    acknowledged.append(id); order.append("ack-intent")
                case .unsafeActivity: break
                default: XCTFail("Unexpected error-dialog intent")
                }
            }, installed: { _ in XCTFail("Error acknowledgement is not installation") })
        adapter.showUpdaterError(error) { sdkAcknowledgements += 1; order.append("sdk-ack") }
        XCTAssertEqual(shown.count, 1)
        XCTAssertTrue(acknowledged.isEmpty)
        XCTAssertEqual(sdkAcknowledgements, 0)
        fake.errorAcknowledgements[0]()
        fake.errorAcknowledgements[0]()
        XCTAssertEqual(acknowledged, shown)
        XCTAssertEqual(order, ["shown", "ack-intent", "sdk-ack"])
        XCTAssertEqual(sdkAcknowledgements, 1)
        adapter.showReady { _ in XCTFail("Error terminalized install replies") }
        fake.readyReplies[0](.install)
        XCTAssertEqual(installAuthorizations, 0)
    }

    @MainActor
    func testSupersededErrorAcknowledgementCannotReportOrForwardAnOldCompletion() {
        let fake = FakeUpdateUserDriver(); fake.deferErrorAcknowledgements = true
        var observed = [NSError](), forwarded = [Int]()
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
            authorizeInstallation: { _ in false }, unarmedIntent: { intent in
                if case .acknowledgedFailedInitialCheck(_, let error) = intent { observed.append(error) }
            }, installed: { _ in XCTFail("Error is not installed") })
        let first = testError, second = testError
        XCTAssertFalse(first === second)
        adapter.showUpdaterError(first) { forwarded.append(1) }
        adapter.showUpdaterError(second) { forwarded.append(2) }
        fake.errorAcknowledgements[0]()
        XCTAssertTrue(observed.isEmpty)
        XCTAssertTrue(forwarded.isEmpty)
        fake.errorAcknowledgements[1]()
        fake.errorAcknowledgements[1]()
        XCTAssertEqual(observed.count, 1)
        XCTAssertTrue(observed.first === second)
        XCTAssertEqual(forwarded, [2])
    }

    @MainActor
    func testReadyInstalledOrDismissedPresentationRetiresPendingErrorAcknowledgement() {
        for mode in 0..<3 {
            let fake = FakeUpdateUserDriver(); fake.deferErrorAcknowledgements = true
            var observed = 0, forwarded = 0
            let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
                authorizeInstallation: { _ in XCTFail("No installation authority"); return true },
                unarmedIntent: { intent in
                    if case .acknowledgedFailedInitialCheck = intent { observed += 1 }
                }, installed: { _ in })
            adapter.showUpdaterError(testError) { forwarded += 1 }
            if mode == 0 { adapter.showReady { _ in } }
            else if mode == 1 { adapter.showUpdateInstalledAndRelaunched(false) {} }
            else { adapter.dismissUpdateInstallation() }
            fake.errorAcknowledgements[0]()
            XCTAssertEqual(observed, 0, "mode \(mode)")
            XCTAssertEqual(forwarded, 0, "mode \(mode)")
        }
    }

    @MainActor
    func testErrorAcknowledgementObserverReentryCannotForwardStaleSDKAbort() {
        let fake = FakeUpdateUserDriver(); fake.deferErrorAcknowledgements = true
        let reference = AdapterReference()
        var acknowledgementIntents = 0, sdkAcknowledgements = 0
        let adapter = BelugaUpdateUserDriver(operationID: UUID(), userDriver: fake,
            authorizeInstallation: { _ in XCTFail("Error cannot install"); return true },
            unarmedIntent: { intent in
                if case .acknowledgedFailedInitialCheck = intent {
                    acknowledgementIntents += 1
                    reference.value?.showReady { _ in XCTFail("Terminal error cannot revive install") }
                }
            }, installed: { _ in XCTFail("No installed evidence") })
        reference.value = adapter
        adapter.showUpdaterError(testError) { sdkAcknowledgements += 1 }
        fake.errorAcknowledgements[0]()
        fake.errorAcknowledgements[0]()
        XCTAssertEqual(acknowledgementIntents, 1)
        XCTAssertEqual(sdkAcknowledgements, 0)
        fake.readyReplies[0](.install)
    }
}

@MainActor
private final class AdapterReference {
    weak var value: BelugaUpdateUserDriver?
}

@MainActor
private class FakeUpdateUserDriver: NSObject, SPUUserDriver {
    let permissionResponse = SUUpdatePermissionResponse(automaticUpdateChecks: false,
                                                        sendSystemProfile: false)
    var events = [String]()
    var installedArguments = [Bool]()
    var onInstalled: ((Bool) -> Void)?
    var request: SPUUpdatePermissionRequest?
    var item: SUAppcastItem?
    var state: SPUUserUpdateState?
    var download: SPUDownloadData?
    var errors = [NSError]()
    var expectedContentLength: UInt64?
    var dataLength: UInt64?
    var extractionProgress: Double?
    var applicationTerminated: Bool?
    var deferReplies = false
    var deferCancellations = false
    var foundChoice: SPUUserUpdateChoice = .dismiss
    var readyChoice: SPUUserUpdateChoice = .skip
    var foundReplies = [(SPUUserUpdateChoice) -> Void]()
    var readyReplies = [(SPUUserUpdateChoice) -> Void]()
    var retries = [() -> Void]()
    var checkCancellations = [() -> Void]()
    var downloadCancellations = [() -> Void]()
    var deferErrorAcknowledgements = false
    var errorAcknowledgements = [() -> Void]()

    func show(_ request: SPUUpdatePermissionRequest,
                                     reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        events.append("permission")
        self.request = request
        reply(permissionResponse)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        events.append("check")
        checkCancellations.append(cancellation)
        if !deferReplies && !deferCancellations { cancellation() }
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        events.append("found")
        item = appcastItem
        self.state = state
        foundReplies.append(reply)
        if !deferReplies { reply(foundChoice) }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        events.append("notes")
        download = downloadData
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        events.append("notes-error")
        errors.append(error as NSError)
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        events.append("not-found")
        errors.append(error as NSError)
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        events.append("error")
        errors.append(error as NSError)
        errorAcknowledgements.append(acknowledgement)
        if !deferErrorAcknowledgements { acknowledgement() }
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        events.append("download")
        downloadCancellations.append(cancellation)
        if !deferReplies && !deferCancellations { cancellation() }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        events.append("content-length")
        self.expectedContentLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        events.append("data-length")
        dataLength = length
    }

    func showDownloadDidStartExtractingUpdate() { events.append("extracting") }

    func showExtractionReceivedProgress(_ progress: Double) {
        events.append("progress")
        extractionProgress = progress
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        events.append("ready")
        readyReplies.append(reply)
        if !deferReplies { reply(readyChoice) }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        events.append("installing")
        self.applicationTerminated = applicationTerminated
        retries.append(retryTerminatingApplication)
        if !deferReplies { retryTerminatingApplication() }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool,
                                         acknowledgement: @escaping () -> Void) {
        events.append("installed")
        installedArguments.append(relaunched)
        onInstalled?(relaunched)
        acknowledgement()
    }

    func dismissUpdateInstallation() { events.append("dismiss") }
}

@MainActor
private final class FocusUpdateUserDriver: FakeUpdateUserDriver {
    @objc func showUpdateInFocus() { events.append("focus") }
}

private final class StateFixtureCoder: NSCoder {
    private let stage: Int
    init(stage: Int = 0) { self.stage = stage; super.init() }
    override var allowsKeyedCoding: Bool { true }
    override func decodeInteger(forKey key: String) -> Int { stage }
    override func decodeBool(forKey key: String) -> Bool { false }
}

private enum AuthorizationResult: Equatable {
    case allow, deny, fail
    func authorize() throws -> Bool {
        if self == .fail { throw TestAuthorizationFailure.refused }
        return self == .allow
    }
}

private enum TestAuthorizationFailure: Error { case refused }
private enum TerminalEvent: Equatable { case error, notFound, dismiss, installed }
