import Foundation
import Sparkle
import XCTest
@testable import BelugaUpdateDriver
@testable import BelugaUpdateCore

/// Additive actual-session regressions. Only existing fake-owned interfaces run;
/// no native Sparkle engine, file-backed broker, process, UI or network is started.
final class BelugaUpdateSparkleFinishedCycleTests: XCTestCase {
    @MainActor
    func testFinishedCycleEarlierEligibilityFailuresSkipSDKGetterAndAuthority() throws {
        // Foreign/unconstructed, foreign/running, not admitted, non-manual,
        // dirty, completed and failed. Independent guard reachability is not implied.
        for mode in 0..<7 {
            let h = FinishedCycleProbeHarness()
            let session = h.makeSession()
            if mode == 6 {
                h.engine.startError = FinishedCycleProbeFailure.refused
                XCTAssertThrowsError(try session.startManualCheck())
            } else if mode != 0 {
                try session.startManualCheck()
                if mode != 2 { try session.admitCheck(from: h.engine.identity, check: .updates) }
            }
            if mode == 4 { XCTAssertFalse(session.extractionInvariantHolds(from: h.engine.identity)) }
            if mode == 5 { h.engine.userDriver?.showUpdateInstalledAndRelaunched(true) {} }
            h.resetProbe()
            session.finishedCycle(from: mode == 1 ? NSObject() : h.engine.identity,
                check: mode == 3 ? .updatesInBackground : .updates, error: nil)
            XCTAssertEqual(h.engine.idleReads, 0, "mode \(mode)")
            XCTAssertEqual(h.retainedQueries, 0, "mode \(mode)")
            XCTAssertEqual(h.trace, mode < 2 ? [] : ["cycle"], "mode \(mode)")
            XCTAssertTrue(h.retirements.isEmpty, "mode \(mode)")
        }
    }

    @MainActor
    func testFinishedCycleIdleGetterPrecedesInitialAuthorityAndDenialSkipsLaterQueries() throws {
        for mode in 0..<3 {
            let h = FinishedCycleProbeHarness()
            let session = try h.startAdmittedSession()
            let error = finishedCycleNoUpdateError()
            if mode != 2 { session.noUpdate(from: h.engine.identity, error: error) }
            if mode == 0 { h.engine.inProgress = true }
            if mode == 1 { h.retained = false }
            h.resetProbe()
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertEqual(h.engine.idleReads, 1, "mode \(mode)")
            XCTAssertEqual(h.retainedQueries, mode == 0 ? 0 : 1, "mode \(mode)")
            XCTAssertEqual(h.trace, mode == 0 ? ["sdk-idle", "cycle"] :
                ["sdk-idle", "authority", "cycle"], "mode \(mode)")
            XCTAssertTrue(h.retirements.isEmpty, "mode \(mode)")
            // Terminal observation does not restore a pending check on later recovery.
            h.engine.inProgress = false
            h.retained = true
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertEqual(h.engine.idleReads, 1)
            XCTAssertEqual(h.retainedQueries, mode == 0 ? 0 : 1)
            XCTAssertTrue(h.retirements.isEmpty)
        }
    }

    @MainActor
    func testFinishedCycleSuccessfulPairHasExactSDKAuthorityAndRetirementOrder() throws {
        let h = FinishedCycleProbeHarness()
        let session = try h.startAdmittedSession()
        let error = finishedCycleNoUpdateError()
        session.noUpdate(from: h.engine.identity, error: error)
        h.resetProbe()
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertEqual(h.trace, ["sdk-idle", "authority", "cycle", "authority",
            "retire-enter", "sdk-idle", "authority", "retire-verified", "retired"])
        XCTAssertEqual(h.engine.idleReads, 2)
        XCTAssertEqual(h.retainedQueries, 3)
        XCTAssertEqual(h.retirements.map(\.reason), [.noUpdate])
        let proof = try XCTUnwrap(h.retirements.first)
        XCTAssertEqual(proof.operationID, h.operationID)
        XCTAssertFalse(session.isCurrentUnarmedCompletion(proof))
        XCTAssertEqual(h.engine.idleReads, 2, "Expired proof must short-circuit before SDK")
        XCTAssertEqual(h.retainedQueries, 3)
        XCTAssertThrowsError(try session.admitCheck(from: h.engine.identity, check: .updates)) {
            XCTAssertEqual($0 as? BelugaUpdateSparkleSession.SessionError, .authorityNotRetained)
        }
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertEqual(h.retirements.count, 1)
        XCTAssertEqual(h.engine.idleReads, 2)
        XCTAssertEqual(h.retainedQueries, 3)
    }

    @MainActor
    func testFinishedCycleSDKGetterReentryCreatesFreshNoUpdateBeforeAuthority() throws {
        let h = FinishedCycleProbeHarness()
        let session = try h.startAdmittedSession()
        let error = finishedCycleNoUpdateError()
        h.resetProbe()
        h.onIdleRead = {
            h.onIdleRead = nil
            XCTAssertEqual(h.retainedQueries, 0, "SDK observation must be before authority")
            session.noUpdate(from: h.engine.identity, error: error)
        }
        defer { h.onIdleRead = nil }
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertEqual(h.trace, ["sdk-idle", "no-update", "authority", "cycle", "authority",
            "retire-enter", "sdk-idle", "authority", "retire-verified", "retired"])
        XCTAssertEqual(h.retirements.map(\.reason), [.noUpdate])
        XCTAssertEqual(h.engine.idleReads, 2)
        XCTAssertEqual(h.retainedQueries, 3)
    }

    @MainActor
    func testFinishedCycleInitialAuthorityReentrySelectsFreshNoUpdateIdentity() throws {
        let h = FinishedCycleProbeHarness()
        let session = try h.startAdmittedSession()
        let error = finishedCycleNoUpdateError()
        h.resetProbe()
        h.onRetained = { _ in
            h.onRetained = nil
            XCTAssertEqual(h.engine.idleReads, 1)
            session.noUpdate(from: h.engine.identity, error: error)
            return true
        }
        defer { h.onRetained = nil }
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertEqual(h.trace, ["sdk-idle", "authority", "no-update", "cycle", "authority",
            "retire-enter", "sdk-idle", "authority", "retire-verified", "retired"])
        XCTAssertEqual(h.retirements.map(\.reason), [.noUpdate])
        XCTAssertEqual(h.engine.idleReads, 2)
        XCTAssertEqual(h.retainedQueries, 3)
    }

    @MainActor
    func testFinishedCycleInitialAuthorityReentrySelectsFreshAcknowledgedAndAbortedFailure() throws {
        for (code, expected): (SUError, BelugaUpdateUnarmedCompletion.FailedInitialCheck) in [
            (.downloadError, .feedFetch), (.appcastParseError, .feedParseOrSignature)
        ] {
            let h = FinishedCycleProbeHarness()
            h.ui.deferErrorAcknowledgements = true
            let session = try h.startAdmittedSession()
            let driver = try XCTUnwrap(h.engine.userDriver)
            driver.showUserInitiatedUpdateCheck {}
            let error = NSError(domain: SUSparkleErrorDomain, code: Int(code.rawValue))
            var acknowledgements = 0
            driver.showUpdaterError(error) { [weak h] in acknowledgements += 1; h?.trace.append("sdk-ack") }
            XCTAssertEqual(acknowledgements, 0)
            let acknowledge = try XCTUnwrap(h.ui.errorAcknowledgements.first)
            h.resetProbe()
            h.onRetained = { _ in
                h.onRetained = nil // Acknowledgement itself performs a nested native query.
                acknowledge()
                session.aborted(from: h.engine.identity, error: error)
                return true
            }
            defer { h.onRetained = nil }
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
            XCTAssertEqual(h.trace, ["sdk-idle", "authority", "authority", "sdk-ack", "aborted",
                "cycle", "authority", "retire-enter", "sdk-idle", "authority", "retire-verified", "retired"])
            XCTAssertEqual(acknowledgements, 1)
            XCTAssertEqual(h.retirements.map(\.reason), [.failedInitialCheck(expected)])
            XCTAssertEqual(h.engine.idleReads, 2)
            XCTAssertEqual(h.retainedQueries, 4)
            XCTAssertTrue(h.boundCandidates.isEmpty)
            XCTAssertTrue(h.installRequests.isEmpty)
        }
    }

    @MainActor
    func testFinishedCycleInitialAuthorityReentrySelectsFreshCancellationAfterPresentation() throws {
        let h = FinishedCycleProbeHarness()
        let session = try h.startAdmittedSession()
        let driver = try XCTUnwrap(h.engine.userDriver)
        var sdkCancels = 0
        driver.showUserInitiatedUpdateCheck { [weak h] in sdkCancels += 1; h?.trace.append("sdk-cancel") }
        let cancel = try XCTUnwrap(h.ui.checkCancellation)
        h.resetProbe()
        h.onRetained = { _ in
            h.onRetained = nil // The supported cancellation intent performs its own query.
            cancel()
            return true
        }
        defer { h.onRetained = nil }
        session.finishedCycle(from: h.engine.identity, check: .updates, error: nil)
        XCTAssertEqual(h.trace, ["sdk-idle", "authority", "authority", "sdk-cancel", "cycle",
            "authority", "retire-enter", "sdk-idle", "authority", "retire-verified", "retired"])
        XCTAssertEqual(sdkCancels, 1)
        XCTAssertEqual(h.retirements.map(\.reason), [.cancelledCheck])
        XCTAssertEqual(h.engine.idleReads, 2)
        XCTAssertEqual(h.retainedQueries, 4)
    }

    @MainActor
    func testFinishedCycleInitialAuthorityReentrySelectsFreshDeclineAndExactNativePayload() throws {
        let h = FinishedCycleProbeHarness()
        let session = try h.startAdmittedSession()
        let item = SUAppcastItem.empty()
        try session.admitUpdate(from: h.engine.identity, item: item, check: .updates)
        session.foundUpdate(from: h.engine.identity, item: item)
        let driver = try XCTUnwrap(h.engine.userDriver)
        let state = try XCTUnwrap(SPUUserUpdateState(coder: FinishedCycleProbeCoder()))
        var sdkChoices = [SPUUserUpdateChoice]()
        driver.showUpdateFound(with: item, state: state) { sdkChoices.append($0) }
        let choose = try XCTUnwrap(h.ui.foundReply)
        choose(.dismiss)
        XCTAssertEqual(sdkChoices, [.dismiss])
        let candidate = try XCTUnwrap(h.boundCandidates.first)
        h.resetProbe()
        h.onRetained = { _ in
            h.onRetained = nil
            session.madeChoice(from: h.engine.identity, item: item, choice: .dismiss, state: state)
            return true
        }
        defer { h.onRetained = nil }
        session.finishedCycle(from: h.engine.identity, check: .updates, error: nil)
        XCTAssertEqual(h.trace, ["sdk-idle", "authority", "authority", "cycle", "authority",
            "retire-enter", "sdk-idle", "authority", "retire-verified", "retired"])
        XCTAssertEqual(h.retirements.map(\.reason), [.declinedCandidate(candidate)])
        XCTAssertEqual(h.engine.idleReads, 2)
        XCTAssertEqual(h.retainedQueries, 4)
        XCTAssertTrue(h.installRequests.isEmpty)
    }

    @MainActor
    func testFinishedCycleNestedObservationClearsOuterProofBeforeRetirement() throws {
        let h = FinishedCycleProbeHarness()
        let session = try h.startAdmittedSession()
        let error = finishedCycleNoUpdateError()
        session.noUpdate(from: h.engine.identity, error: error)
        var nested = 0
        h.resetProbe()
        h.onObservation = { value in
            guard case .cycleFinished = value.event else { return }
            h.onObservation = nil
            nested += 1
            // Outer already consumed its manual cycle and entered completed state.
            // The nested terminal observation cannot make its own reason, and its
            // reason-nil tail clears the pending outer native completion.
            session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        }
        defer { h.onObservation = nil }
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertEqual(nested, 1)
        XCTAssertEqual(h.trace, ["sdk-idle", "authority", "cycle", "cycle", "authority"])
        XCTAssertEqual(h.engine.idleReads, 1)
        XCTAssertEqual(h.retainedQueries, 2)
        XCTAssertTrue(h.retirements.isEmpty)
        XCTAssertTrue(h.retained)
        session.finishedCycle(from: h.engine.identity, check: .updates, error: error)
        XCTAssertEqual(h.engine.idleReads, 1)
        XCTAssertEqual(h.retainedQueries, 2)
        XCTAssertTrue(h.retirements.isEmpty)
    }
}

/// New instrumentation of the existing actual Engine/Factory/Authority seams.
/// The original private Harness and its 55 test methods are not modified.
@MainActor
private final class FinishedCycleProbeHarness {
    let operationID = UUID()
    let engine = FinishedCycleProbeEngine()
    let ui = FinishedCycleProbeUserDriver()
    var retained = false
    var retainedQueries = 0
    var trace = [String]()
    var observations = [BelugaUpdateSparkleSession.Observation]()
    var retirements = [BelugaUpdateUnarmedCompletion]()
    var boundCandidates = [BelugaUpdateOperation.ArtifactIdentity]()
    var installRequests = [BelugaUpdateInstallRequest]()
    var onIdleRead: (() -> Void)?
    var onRetained: ((UUID) -> Bool)?
    var onObservation: ((BelugaUpdateSparkleSession.Observation) -> Void)?
    private weak var currentSession: BelugaUpdateSparkleSession?

    func makeSession() -> BelugaUpdateSparkleSession {
        engine.readHook = { [weak self] in
            guard let self else { return }
            trace.append("sdk-idle")
            onIdleRead?()
        }
        let authority = BelugaUpdateSparkleSession.Authority(
            withPreparedAuthority: { [self] value, body in
                XCTAssertEqual(value, operationID)
                retained = true
                try body()
            }, isRetained: { [self] value in
                XCTAssertEqual(value, operationID)
                retainedQueries += 1
                trace.append("authority")
                return onRetained?(value) ?? retained
            }, bindCandidate: { [self] value, candidate in
                XCTAssertEqual(value, operationID)
                boundCandidates.append(candidate)
            }, authorizeInstallation: { [self] request in
                installRequests.append(request)
                return true
            }, mayTerminateTarget: { _ in false }, retirePreparedUnarmed: { [self] completion in
                trace.append("retire-enter")
                let current = currentSession?.isCurrentUnarmedCompletion(completion) == true
                XCTAssertTrue(current)
                guard current else { throw FinishedCycleProbeFailure.refused }
                retirements.append(completion)
                trace.append("retire-verified")
            })
        let factory = BelugaUpdateSparkleSession.Factory(userDriver: { [self] _ in ui },
            engine: { [self] _, driver, _ in engine.userDriver = driver; return engine },
            candidate: { _ in try .init(version: "0.2.1", build: 101,
                executableSHA256: String(repeating: "c", count: 64),
                dependencyClosureSHA256: String(repeating: "d", count: 64)) })
        let session = BelugaUpdateSparkleSession(targetBundle: .main, operationID: operationID,
            authority: authority, verifiedFeedURLString: "https://updates.example.invalid/beluga/appcast.xml",
            factory: factory, observe: { [self] value in
                XCTAssertEqual(value.operationID, operationID)
                observations.append(value)
                switch value.event {
                case .noUpdate: trace.append("no-update")
                case .aborted: trace.append("aborted")
                case .cycleFinished: trace.append("cycle")
                case .unarmedRetired: trace.append("retired")
                case .unarmedRetirementFailed: trace.append("retirement-failed")
                default: trace.append("other-observation")
                }
                onObservation?(value)
            })
        currentSession = session
        return session
    }

    func startAdmittedSession() throws -> BelugaUpdateSparkleSession {
        let session = makeSession()
        try session.startManualCheck()
        try session.admitCheck(from: engine.identity, check: .updates)
        return session
    }

    func resetProbe() {
        engine.idleReads = 0
        retainedQueries = 0
        trace.removeAll()
        observations.removeAll()
    }
}

@MainActor
private final class FinishedCycleProbeEngine: BelugaUpdateSparkleSession.Engine {
    let identity = NSObject()
    var callbackIdentity: AnyObject { identity }
    var inProgress = false
    var idleReads = 0
    var readHook: (() -> Void)?
    var startError: Error?
    var userDriver: (any SPUUserDriver)?
    var sessionInProgress: Bool {
        idleReads += 1
        readHook?()
        return inProgress
    }
    func configureManualOnly() {}
    func start() throws { if let startError { throw startError } }
    func checkForUpdates() {}
}

/// Ordinary inert protocol implementation, like the pinned existing FakeUserDriver.
@MainActor
private final class FinishedCycleProbeUserDriver: NSObject, SPUUserDriver {
    var foundReply: ((SPUUserUpdateChoice) -> Void)?
    var checkCancellation: (() -> Void)?
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
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}

private final class FinishedCycleProbeCoder: NSCoder {
    override var allowsKeyedCoding: Bool { true }
    override func decodeInteger(forKey key: String) -> Int { 0 }
    override func decodeBool(forKey key: String) -> Bool { true }
}

private enum FinishedCycleProbeFailure: Error { case refused }
private func finishedCycleNoUpdateError() -> NSError {
    NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue),
        userInfo: [SPUNoUpdateFoundUserInitiatedKey: true])
}
