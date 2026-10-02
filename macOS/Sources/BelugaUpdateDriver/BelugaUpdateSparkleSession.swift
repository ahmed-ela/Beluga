import BelugaUpdateCore
import CoreFoundation
import Foundation
import Sparkle

/// Supported Sparkle composition for one externally owned broker operation.
/// This object never verifies a bundle, clears a fence, releases a lease, or quits.
@MainActor
package final class BelugaUpdateSparkleSession: NSObject, SPUUpdaterDelegate {
    package struct Authority {
        /// Publish the durable prepared operation and retain its lease before invoking body.
        /// A thrown/omitted body or any later uncertainty does not authorize fence removal.
        package let withPreparedAuthority: @MainActor (UUID, () throws -> Void) throws -> Void
        package let isRetained: @MainActor (UUID) -> Bool
        /// Persist this positively signed candidate while the predecessor is still current.
        package let bindCandidate: @MainActor (UUID, BelugaUpdateOperation.ArtifactIdentity) throws -> Void
        /// Persist possiblyArmed before returning true, including resumed-install/retry paths.
        package let authorizeInstallation: @MainActor (BelugaUpdateInstallRequest) throws -> Bool
        package let mayTerminateTarget: @MainActor (UUID) -> Bool
        /// Optional explicit owner path; omission never grants prepared-fence clearance.
        package let retirePreparedUnarmed: (@MainActor (BelugaUpdateUnarmedCompletion) throws -> Void)?

        package init(
            withPreparedAuthority: @escaping @MainActor (UUID, () throws -> Void) throws -> Void,
            isRetained: @escaping @MainActor (UUID) -> Bool,
            bindCandidate: @escaping @MainActor (UUID, BelugaUpdateOperation.ArtifactIdentity) throws -> Void,
            authorizeInstallation: @escaping @MainActor (BelugaUpdateInstallRequest) throws -> Bool,
            mayTerminateTarget: @escaping @MainActor (UUID) -> Bool,
            retirePreparedUnarmed: (@MainActor (BelugaUpdateUnarmedCompletion) throws -> Void)? = nil
        ) {
            self.withPreparedAuthority = withPreparedAuthority
            self.isRetained = isRetained
            self.bindCandidate = bindCandidate
            self.authorizeInstallation = authorizeInstallation
            self.mayTerminateTarget = mayTerminateTarget
            self.retirePreparedUnarmed = retirePreparedUnarmed
        }
    }

    package struct Observation {
        package enum Event {
            case candidateFound(SUAppcastItem)
            /// Public admission was not seen for this item; this is not installer absence proof.
            case resumePossible(SUAppcastItem)
            case resumedInstallation(SUAppcastItem)
            case noUpdate(Error)
            case cycleFinished(check: SPUUpdateCheck, error: Error?)
            case aborted(Error)
            case startupFailed(Error)
            case willExtract(SUAppcastItem)
            case willInstall(SUAppcastItem)
            case unexpectedInstallOnQuit(SUAppcastItem)
            case targetTerminationRequested(allowed: Bool)
            case installed(relaunched: Bool)
            case extractionInvariantFailed
            case unarmedRetired
            case unarmedRetirementFailed(Error)
        }
        package let operationID: UUID
        package let event: Event
    }

    package enum SessionError: Error, Equatable {
        case alreadyStarted, startupBodyNotInvoked, duplicateStartupBody
        case authorityNotRetained, foreignUpdater, nonManualCheck, checkNotRequested
        case feedDoesNotMatchVerifiedTarget
        case candidateChanged, candidateBindingInProgress, candidateNotBound, candidateNotFresh
    }

    /// Test seam only: native engine instances remain private and cannot be replaced mid-cycle.
    @MainActor
    protocol Engine: AnyObject {
        var callbackIdentity: AnyObject { get }
        var sessionInProgress: Bool { get }
        func configureManualOnly()
        func start() throws
        func checkForUpdates()
    }

    @MainActor
    struct Factory {
        let userDriver: (Bundle) -> any SPUUserDriver
        let engine: (Bundle, any SPUUserDriver, any SPUUpdaterDelegate) -> any Engine
        let candidate: (SUAppcastItem) throws -> BelugaUpdateOperation.ArtifactIdentity

        static var native: Self {
            Self(userDriver: { SPUStandardUserDriver(hostBundle: $0, delegate: nil) },
                 engine: { target, driver, delegate in
                    NativeEngine(updater: SPUUpdater(hostBundle: target, applicationBundle: target,
                                                    userDriver: driver, delegate: delegate))
                 }, candidate: BelugaUpdateCandidateMetadata.parse)
        }
    }

    private enum State { case idle, preparing, starting, running, completed, failed }
    private let targetBundle: Bundle
    private let verifiedFeedURLString: String
    private let operationID: UUID
    private let authority: Authority
    private let observe: @MainActor (Observation) -> Void
    private let factory: Factory
    private var state = State.idle
    private var engine: (any Engine)?
    private var callbackIdentity: AnyObject?
    private var adapter: BelugaUpdateUserDriver?
    private var manualCheckRequested = false
    private var manualCycleAdmitted = false
    private var admittedItem: SUAppcastItem?
    private var installationAuthorized = false
    private var boundCandidate: BelugaUpdateOperation.ArtifactIdentity?
    private var candidateBindingInProgress = false
    private var startupBodyInvocations = 0
    private let cycleNonce = UUID()
    private var startupSucceeded = false
    private var cleanUnarmedCycle = true
    private var noUpdateError: NSError?
    private var unarmedCompletion: BelugaUpdateUnarmedCompletion?
    private var retirementInProgress = false
    private var initialCheckPresentation: UUID?
    private var cancelledInitialCheck = false
    private var foundItem: SUAppcastItem?
    private var decline: Decline?

    private struct Decline {
        let presentationID: UUID
        let item: SUAppcastItem
        let state: SPUUserUpdateState
        let choice: SPUUserUpdateChoice
        let candidate: BelugaUpdateOperation.ArtifactIdentity
        var observedSDKChoice = false
    }

    /// Caller already verified this exact target Bundle and broker's signing/dependency closure.
    /// No SDK/user-driver construction, startup, UI, or network activity occurs here.
    package convenience init(targetBundle: Bundle, verifiedFeedURL: URL, operationID: UUID,
                             authority: Authority,
                             observe: @escaping @MainActor (Observation) -> Void) throws {
        guard targetBundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ==
                verifiedFeedURL.absoluteString else {
            throw SessionError.feedDoesNotMatchVerifiedTarget
        }
        self.init(targetBundle: targetBundle, operationID: operationID, authority: authority,
                  verifiedFeedURLString: verifiedFeedURL.absoluteString, factory: .native,
                  observe: observe)
    }

    init(targetBundle: Bundle, operationID: UUID, authority: Authority,
         verifiedFeedURLString: String, factory: Factory,
         observe: @escaping @MainActor (Observation) -> Void) {
        self.targetBundle = targetBundle
        self.verifiedFeedURLString = verifiedFeedURLString
        self.operationID = operationID
        self.authority = authority
        self.factory = factory
        self.observe = observe
        super.init()
    }

    /// Starts exactly one user-initiated cycle; SDK startup can probe a retained installer.
    /// Even a startup error leaves the engine and external ownership retained for recovery.
    package func startManualCheck() throws {
        guard state == .idle else { throw SessionError.alreadyStarted }
        state = .preparing
        do {
            try authority.withPreparedAuthority(operationID) { [self] in
                startupBodyInvocations += 1
                guard startupBodyInvocations == 1 else { throw SessionError.duplicateStartupBody }
                guard state == .preparing, authority.isRetained(operationID) else {
                    throw SessionError.authorityNotRetained
                }
                state = .starting
                let standard = factory.userDriver(targetBundle)
                guard state == .starting, authority.isRetained(operationID) else {
                    throw SessionError.authorityNotRetained
                }
                let adapter = BelugaUpdateUserDriver(operationID: operationID, userDriver: standard,
                    authorizeInstallation: { [weak self] request in
                        guard let self else { return false }
                        return try self.authorize(request)
                    }, unarmedIntent: { [weak self] intent in
                        self?.receivedUnarmedIntent(intent)
                    }, installed: { [weak self] value in
                        guard let self, value.operationID == self.operationID else { return }
                        self.state = .completed
                        self.cleanUnarmedCycle = false
                        self.manualCheckRequested = false
                        self.manualCycleAdmitted = false
                        self.emit(.installed(relaunched: value.relaunched))
                    })
                self.adapter = adapter
                let engine = factory.engine(targetBundle, adapter, self)
                self.engine = engine
                callbackIdentity = engine.callbackIdentity
                guard state == .starting, authority.isRetained(operationID) else {
                    throw SessionError.authorityNotRetained
                }
                engine.configureManualOnly()
                guard state == .starting, authority.isRetained(operationID) else {
                    throw SessionError.authorityNotRetained
                }
                try engine.start()
                if state == .completed { return }
                guard state == .starting, authority.isRetained(operationID) else {
                    throw SessionError.authorityNotRetained
                }
                state = .running
                // SDK startup is now proven and ownership is retained. A supported
                // check may synchronously show its initial progress UI; later failure
                // of this outer ownership body still poisons every retirement proof.
                startupSucceeded = true
                manualCheckRequested = true
                engine.checkForUpdates()
            }
            guard startupBodyInvocations > 0 else { throw SessionError.startupBodyNotInvoked }
            guard startupBodyInvocations == 1 else { throw SessionError.duplicateStartupBody }
            if state == .completed { return }
            guard state == .running, authority.isRetained(operationID) else {
                throw SessionError.authorityNotRetained
            }
        } catch {
            state = .failed
            cleanUnarmedCycle = false
            manualCheckRequested = false
            emit(.startupFailed(error))
            throw error
        }
    }

    package func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try admitCheck(from: updater, check: updateCheck)
    }

    package func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem,
                 updateCheck: SPUUpdateCheck) throws {
        try admitUpdate(from: updater, item: item, check: updateCheck)
    }

    package func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    package func feedURLString(for updater: SPUUpdater) -> String? {
        feedURL(from: updater)
    }

    package func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        foundUpdate(from: updater, item: item)
    }

    package func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        noUpdate(from: updater, error: error)
    }

    package func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        aborted(from: updater, error: error)
    }

    package func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: Error?) {
        finishedCycle(from: updater, check: updateCheck, error: error)
    }

    @objc(updater:userDidMakeChoice:forUpdate:state:)
    package func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
        madeChoice(from: updater, item: item, choice: choice, state: state)
    }

    package func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        guard matches(updater) else { return }
        let valid = extractionInvariantHolds(from: updater)
        // A void hook cannot safely veto extraction after the first install reply.
        // Stop the broker on broken ownership; its durable fence remains sticky.
        precondition(valid, "Beluga updater extraction ownership invariant failed")
        emit(.willExtract(item))
        precondition(extractionInvariantHolds(from: updater),
                     "Beluga updater extraction observation lost ownership")
    }

    package func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        guard matches(updater) else { return }
        cleanUnarmedCycle = false
        emit(.willInstall(item))
    }

    package func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        permitsTargetTermination(from: updater)
    }

    package func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock: @escaping () -> Void) -> Bool {
        interceptInstallOnQuit(from: updater, item: item)
    }

    func interceptInstallOnQuit(from identity: AnyObject, item: SUAppcastItem) -> Bool {
        guard matches(identity) else { return false }
        cleanUnarmedCycle = false
        emit(.unexpectedInstallOnQuit(item))
        // Supported interception stalls this unexpected automatic cycle. We neither invoke
        // nor retain its block. Sparkle may still install on target quit: never clear authority.
        return true
    }

    func admitCheck(from identity: AnyObject, check: SPUUpdateCheck) throws {
        guard matches(identity) else { throw SessionError.foreignUpdater }
        guard check == .updates else { throw SessionError.nonManualCheck }
        guard state == .running, authority.isRetained(operationID) else {
            throw SessionError.authorityNotRetained
        }
        guard manualCheckRequested else { throw SessionError.checkNotRequested }
        manualCheckRequested = false
        manualCycleAdmitted = true
    }

    func admitUpdate(from identity: AnyObject, item: SUAppcastItem,
                     check: SPUUpdateCheck) throws {
        guard matches(identity) else { throw SessionError.foreignUpdater }
        guard check == .updates else { throw SessionError.nonManualCheck }
        guard state == .running, manualCycleAdmitted, authority.isRetained(operationID) else {
            throw SessionError.authorityNotRetained
        }
        if let admittedItem {
            // Keep exact same-item admission idempotent for supported SDK reentry,
            // but a repeated admission cannot certify a single clean unarmed cycle.
            cleanUnarmedCycle = false
            guard admittedItem === item else { throw SessionError.candidateChanged }
            try bindVerifiedCandidate(item)
            return
        }
        guard !cancelledInitialCheck, decline == nil else {
            cleanUnarmedCycle = false
            throw SessionError.candidateChanged
        }
        do { try bindVerifiedCandidate(item) }
        catch { cleanUnarmedCycle = false; throw error }
        admittedItem = item
    }

    func foundUpdate(from identity: AnyObject, item: SUAppcastItem) {
        guard matches(identity) else { return }
        if admittedItem !== item || foundItem != nil {
            cleanUnarmedCycle = false
            emit(.resumePossible(item))
        } else { foundItem = item }
        emit(.candidateFound(item))
    }

    func madeChoice(from identity: AnyObject, item: SUAppcastItem,
                    choice: SPUUserUpdateChoice, state userState: SPUUserUpdateState) {
        guard matches(identity) else { return }
        if userState.stage == .installing { emit(.resumedInstallation(item)) }
        guard self.state == .running, startupSucceeded, manualCycleAdmitted,
              cleanUnarmedCycle, !installationAuthorized, authority.isRetained(operationID),
              var decline, !decline.observedSDKChoice, decline.item === item,
              decline.state === userState, decline.choice == choice,
              choice == .dismiss || choice == .skip,
              userState.stage == .notDownloaded, userState.userInitiated,
              admittedItem === item, foundItem === item,
              boundCandidate == decline.candidate else {
            cleanUnarmedCycle = false
            return
        }
        decline.observedSDKChoice = true
        self.decline = decline
    }

    private func receivedUnarmedIntent(_ intent: BelugaUpdateUserDriver.UnarmedIntent) {
        guard state == .running, startupSucceeded, manualCycleAdmitted, cleanUnarmedCycle,
              !installationAuthorized, authority.isRetained(operationID) else {
            cleanUnarmedCycle = false
            return
        }
        switch intent {
        case .initialCheckShown(let presentationID):
            guard initialCheckPresentation == nil, admittedItem == nil, boundCandidate == nil,
                  noUpdateError == nil, decline == nil, !cancelledInitialCheck else {
                cleanUnarmedCycle = false; return
            }
            initialCheckPresentation = presentationID
        case .cancelledInitialCheck(let presentationID):
            guard initialCheckPresentation == presentationID, admittedItem == nil,
                  boundCandidate == nil, noUpdateError == nil, decline == nil,
                  !cancelledInitialCheck else { cleanUnarmedCycle = false; return }
            cancelledInitialCheck = true
        case .declinedCandidate(let presentationID, let item, let userState, let choice):
            guard decline == nil, !cancelledInitialCheck, noUpdateError == nil,
                  choice == .dismiss || choice == .skip,
                  userState.stage == .notDownloaded, userState.userInitiated,
                  admittedItem === item, foundItem === item, let candidate = boundCandidate else {
                cleanUnarmedCycle = false; return
            }
            decline = Decline(presentationID: presentationID, item: item, state: userState,
                              choice: choice, candidate: candidate)
        case .unsafeActivity:
            cleanUnarmedCycle = false
        }
    }

    func noUpdate(from identity: AnyObject, error: Error) {
        guard matches(identity) else { return }
        let native = error as NSError
        if state == .running, startupSucceeded, manualCycleAdmitted, noUpdateError == nil,
           cleanUnarmedCycle, !cancelledInitialCheck, decline == nil,
           admittedItem == nil, boundCandidate == nil, Self.isManualNoUpdate(native) {
            noUpdateError = native
        } else { cleanUnarmedCycle = false }
        emit(.noUpdate(error))
    }

    func aborted(from identity: AnyObject, error: Error) {
        guard matches(identity) else { return }
        // Pinned SDK reports its no-update error as didAbort immediately before didFinish.
        // Any other abort is uncertainty, not a successful unarmed cycle.
        if noUpdateError !== (error as NSError) { cleanUnarmedCycle = false }
        emit(.aborted(error))
    }

    func finishedCycle(from identity: AnyObject, check: SPUUpdateCheck, error: Error?) {
        guard matches(identity) else { return }
        let finishedError = error.map { $0 as NSError }
        let reason: BelugaUpdateUnarmedCompletion.Reason?
        if state == .running, startupSucceeded, manualCycleAdmitted, check == .updates,
           cleanUnarmedCycle, !installationAuthorized, engine?.sessionInProgress == false,
           authority.isRetained(operationID) {
            if noUpdateError != nil, noUpdateError === finishedError,
               boundCandidate == nil, admittedItem == nil, decline == nil, !cancelledInitialCheck {
                reason = .noUpdate
            } else if finishedError == nil, noUpdateError == nil, cancelledInitialCheck,
                      initialCheckPresentation != nil, boundCandidate == nil,
                      admittedItem == nil, decline == nil {
                reason = .cancelledCheck
            } else if finishedError == nil, noUpdateError == nil, !cancelledInitialCheck,
                      let decline, decline.observedSDKChoice, boundCandidate == decline.candidate,
                      admittedItem === decline.item, foundItem === decline.item {
                reason = .declinedCandidate(decline.candidate)
            } else { reason = nil }
        } else { reason = nil }
        manualCheckRequested = false
        manualCycleAdmitted = false
        state = .completed
        if let reason {
            unarmedCompletion = .init(operationID: operationID, cycleNonce: cycleNonce, reason: reason)
        }
        emit(.cycleFinished(check: check, error: error))
        guard reason != nil, cleanUnarmedCycle, state == .completed, authority.isRetained(operationID),
              let completion = unarmedCompletion, let retire = authority.retirePreparedUnarmed else {
            unarmedCompletion = nil
            return
        }
        retirementInProgress = true
        defer { retirementInProgress = false; unarmedCompletion = nil }
        do {
            try retire(completion)
            emit(.unarmedRetired)
        } catch {
            state = .failed
            cleanUnarmedCycle = false
            emit(.unarmedRetirementFailed(error))
        }
    }

    /// Valid only synchronously inside the exact owner retirement callback, never restored
    /// from an observation or used after that callback returns. It does not verify lineage.
    package func isCurrentUnarmedCompletion(_ completion: BelugaUpdateUnarmedCompletion) -> Bool {
        retirementInProgress && state == .completed && cleanUnarmedCycle &&
            unarmedCompletion == completion && engine?.sessionInProgress == false &&
            authority.isRetained(operationID)
    }

    private static func isManualNoUpdate(_ error: NSError) -> Bool {
        guard error.domain == SUSparkleErrorDomain, error.code == Int(SUError.noUpdateError.rawValue),
              let manual = error.userInfo[SPUNoUpdateFoundUserInitiatedKey] as? NSNumber,
              CFGetTypeID(manual) == CFBooleanGetTypeID() else { return false }
        return manual.boolValue
    }

    func extractionInvariantHolds(from identity: AnyObject) -> Bool {
        guard matches(identity) else { return false }
        cleanUnarmedCycle = false
        let valid = installationAuthorized && authority.isRetained(operationID)
        if !valid { emit(.extractionInvariantFailed) }
        return valid
    }

    func permitsTargetTermination(from identity: AnyObject) -> Bool {
        guard matches(identity) else { return false }
        cleanUnarmedCycle = false
        let allowed = state == .running && installationAuthorized && authority.isRetained(operationID) &&
            authority.mayTerminateTarget(operationID) && authority.isRetained(operationID)
        emit(.targetTerminationRequested(allowed: allowed))
        return allowed && state == .running && authority.isRetained(operationID)
    }

    func feedURL(from identity: AnyObject) -> String? {
        // Delegate precedence bypasses persisted SUFeedURL without mutating user defaults.
        matches(identity) ? verifiedFeedURLString : nil
    }

    private func authorize(_ request: BelugaUpdateInstallRequest) throws -> Bool {
        if request.operationID == operationID { cleanUnarmedCycle = false }
        guard request.operationID == operationID, state == .running,
              authority.isRetained(operationID) else { return false }
        switch request.phase {
        case .updateFound(let item, let state):
            if state.stage == .installing { emit(.resumedInstallation(item)) }
            // Archived items preserve signingValidationStatus without re-verification.
            // Only this manual cycle's exact, freshly admitted object may reach first install.
            // Resumed installers need a separate recovery proof; the durable fence stays held.
            guard manualCycleAdmitted, admittedItem === item, state.stage != .installing else {
                throw SessionError.candidateNotFresh
            }
            try bindVerifiedCandidate(item)
        case .readyToInstallAndRelaunch, .retryTerminatingApplication:
            guard boundCandidate != nil, installationAuthorized else {
                throw SessionError.candidateNotBound
            }
        }
        guard self.state == .running, authority.isRetained(operationID) else { return false }
        let allowed = try authority.authorizeInstallation(request)
        guard allowed, self.state == .running, authority.isRetained(operationID) else { return false }
        installationAuthorized = true
        return true
    }

    private func bindVerifiedCandidate(_ item: SUAppcastItem) throws {
        guard state == .running, authority.isRetained(operationID) else {
            throw SessionError.authorityNotRetained
        }
        guard !candidateBindingInProgress else { throw SessionError.candidateBindingInProgress }
        candidateBindingInProgress = true
        defer { candidateBindingInProgress = false }
        // Native composition always uses the real signed-item parser. The factory seam
        // can substitute it only inside this module's isolated, SDK-free tests.
        let candidate = try factory.candidate(item)
        if let boundCandidate {
            guard boundCandidate == candidate else { throw SessionError.candidateChanged }
        } else {
            try authority.bindCandidate(operationID, candidate)
            guard state == .running, authority.isRetained(operationID) else {
                throw SessionError.authorityNotRetained
            }
            boundCandidate = candidate
        }
    }

    private func matches(_ identity: AnyObject) -> Bool { callbackIdentity === identity }
    private func emit(_ event: Observation.Event) {
        observe(Observation(operationID: operationID, event: event))
    }

    @MainActor
    private final class NativeEngine: Engine {
        private let updater: SPUUpdater
        var callbackIdentity: AnyObject { updater }
        var sessionInProgress: Bool { updater.sessionInProgress }
        init(updater: SPUUpdater) { self.updater = updater }
        func configureManualOnly() {
            updater.automaticallyChecksForUpdates = false
            updater.automaticallyDownloadsUpdates = false
        }
        func start() throws { try updater.start() }
        func checkForUpdates() { updater.checkForUpdates() }
    }
}
