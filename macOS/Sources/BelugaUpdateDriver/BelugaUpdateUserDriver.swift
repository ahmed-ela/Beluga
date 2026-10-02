import Foundation
import Sparkle

package struct BelugaUpdateInstalledObservation: Equatable, Sendable {
    package let operationID: UUID
    package let relaunched: Bool
}

package struct BelugaUpdateInstallRequest {
    package enum Phase {
        case updateFound(appcastItem: SUAppcastItem, state: SPUUserUpdateState)
        case readyToInstallAndRelaunch
        case retryTerminatingApplication
    }

    package let operationID: UUID
    package let presentationID: UUID
    package let phase: Phase
}

/// A public-API UI adapter, not installation verification or authority to release ownership.
@MainActor
final class BelugaUpdateUserDriver: NSObject, SPUUserDriver {
    typealias InstalledObservation = BelugaUpdateInstalledObservation
    typealias InstallRequest = BelugaUpdateInstallRequest

    /// Protected UI activity is not SDK completion. The session must pair a decline
    /// with the exact public SDK choice and wait for real cycle cleanup before release.
    enum UnarmedIntent {
        case initialCheckShown(presentationID: UUID)
        case cancelledInitialCheck(presentationID: UUID)
        case declinedCandidate(presentationID: UUID, item: SUAppcastItem,
                               state: SPUUserUpdateState, choice: SPUUserUpdateChoice)
        case unsafeActivity
    }

    private let operationID: UUID
    private let userDriver: any SPUUserDriver
    private let authorizeInstallation: @MainActor (InstallRequest) throws -> Bool
    private let installed: @MainActor (InstalledObservation) -> Void
    private let unarmedIntent: @MainActor (UnarmedIntent) -> Void
    private var observedInstallation = false
    private var replyAuthorityRetired = false
    private var presentation: Presentation?
    private var presentationGeneration: UUID?

    /// The gate must durably retain possibly-armed ownership before returning true.
    /// False/throw denies this reply only; it neither cancels Sparkle nor releases a fence.
    init(operationID: UUID, userDriver: any SPUUserDriver,
         authorizeInstallation: @escaping @MainActor (InstallRequest) throws -> Bool,
         unarmedIntent: @escaping @MainActor (UnarmedIntent) -> Void = { _ in },
         installed: @escaping @MainActor (InstalledObservation) -> Void) {
        self.operationID = operationID
        self.userDriver = userDriver
        self.authorizeInstallation = authorizeInstallation
        self.installed = installed
        self.unarmedIntent = unarmedIntent
        super.init()
    }

    func show(_ request: SPUUpdatePermissionRequest,
                                     reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        userDriver.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        userDriver.showUserInitiatedUpdateCheck(cancellation:
            protectedCancellation(cancellation, initialCheck: true))
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        userDriver.showUpdateFound(with: appcastItem, state: state,
            reply: protectedReply(phase: .updateFound(appcastItem: appcastItem, state: state),
                                  reply: reply))
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        userDriver.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        userDriver.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        retireReplyAuthority()
        userDriver.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        retireReplyAuthority()
        unarmedIntent(.unsafeActivity)
        userDriver.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        unarmedIntent(.unsafeActivity)
        userDriver.showDownloadInitiated(cancellation:
            protectedCancellation(cancellation, initialCheck: false))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        userDriver.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        userDriver.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        unarmedIntent(.unsafeActivity)
        userDriver.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        userDriver.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        unarmedIntent(.unsafeActivity)
        userDriver.showReady(toInstallAndRelaunch:
            protectedReply(phase: .readyToInstallAndRelaunch, reply: reply))
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        unarmedIntent(.unsafeActivity)
        let current = makePresentation(phase: .retryTerminatingApplication)
        userDriver.showInstallingUpdate(withApplicationTerminated: applicationTerminated,
            retryTerminatingApplication: { [weak self] in
                // Sparkle permits multiple retries, but each one can resume installation.
                // They are current-presentation authorized actions, not terminal evidence.
                guard !applicationTerminated, let self, self.isCurrent(current),
                      !current.authorizing else { return }
                current.authorizing = true
                defer { current.authorizing = false }
                guard self.isAuthorized(current), self.isCurrent(current) else { return }
                retryTerminatingApplication()
            })
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool,
                                         acknowledgement: @escaping () -> Void) {
        retireReplyAuthority()
        if !observedInstallation {
            // Standard UI may acknowledge synchronously. Reentrant callbacks must also see
            // this latch before the broker receives the one operation-bound observation.
            observedInstallation = true
            installed(InstalledObservation(operationID: operationID, relaunched: relaunched))
        }
        userDriver.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        retireReplyAuthority()
        userDriver.dismissUpdateInstallation()
    }

    func showUpdateInFocus() {
        userDriver.showUpdateInFocus?()
    }

    private func protectedReply(phase: InstallRequest.Phase,
                                reply: @escaping (SPUUserUpdateChoice) -> Void)
        -> (SPUUserUpdateChoice) -> Void {
        let current = makePresentation(phase: phase)
        return { [weak self] choice in
            guard !current.replied else { return }
            current.replied = true
            guard let self, self.isCurrent(current) else { return }
            switch choice {
            case .install:
                let allowed = self.isAuthorized(current)
                // Authorization performs synchronous durable work and may reenter UI.
                guard self.isCurrent(current) else { return }
                self.presentation = nil
                // Dismissal can defer an already-armed installer; it never clears a fence
                // or proves termination/installation stopped. The broker retains ownership.
                reply(allowed ? .install : .dismiss)
            case .dismiss, .skip:
                // The one-operation adapter cannot revive install authority after a
                // real decline. Dismissing an already armed installer is still unsafe.
                self.retireReplyAuthority()
                if case .updateFound(let item, let state) = phase {
                    self.unarmedIntent(.declinedCandidate(
                        presentationID: current.request.presentationID, item: item,
                        state: state, choice: choice))
                } else { self.unarmedIntent(.unsafeActivity) }
                reply(choice)
            @unknown default:
                self.presentation = nil
                reply(.dismiss)
            }
        }
    }

    private func makePresentation(phase: InstallRequest.Phase) -> Presentation {
        let current = Presentation(request: InstallRequest(operationID: operationID,
                                                           presentationID: UUID(), phase: phase))
        presentation = current
        presentationGeneration = current.request.presentationID
        return current
    }

    private func isCurrent(_ current: Presentation) -> Bool {
        !replyAuthorityRetired && presentation === current &&
            presentationGeneration == current.request.presentationID
    }

    private func isAuthorized(_ current: Presentation) -> Bool {
        do { return try authorizeInstallation(current.request) }
        catch { return false }
    }

    private func retireReplyAuthority() {
        replyAuthorityRetired = true
        presentation = nil
        presentationGeneration = nil
    }

    private func protectedCancellation(_ cancellation: @escaping () -> Void,
                                       initialCheck: Bool) -> () -> Void {
        let generation = UUID()
        presentation = nil
        presentationGeneration = generation
        if initialCheck, !replyAuthorityRetired {
            unarmedIntent(.initialCheckShown(presentationID: generation))
        }
        return { [weak self] in
            guard let self, !self.replyAuthorityRetired,
                  self.presentationGeneration == generation else { return }
            self.retireReplyAuthority()
            if initialCheck { self.unarmedIntent(.cancelledInitialCheck(presentationID: generation)) }
            else { self.unarmedIntent(.unsafeActivity) }
            cancellation()
        }
    }

    private final class Presentation {
        let request: InstallRequest
        var replied = false
        var authorizing = false
        init(request: InstallRequest) { self.request = request }
    }
}
