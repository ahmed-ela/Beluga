import BelugaUpdateCore
import Combine
import Foundation

/// The menu is an authenticated client, never Sparkle's lifetime owner.
@MainActor
final class BelugaUpdateController: ObservableObject {
    struct Operations: Sendable {
        var hasFence: @Sendable (URL) throws -> Bool
        var begin: @Sendable (URL, UUID) throws -> Void
        var ready: @Sendable (URL, UUID) throws -> Void
        static let native = Self(hasFence: { try BelugaUpdateMenuClient.hasFence(bundleURL: $0) },
            begin: {
                let check = try BelugaUpdateMenuClient.begin(bundleURL: $0, menuInstanceID: $1)
                try check.waitForRelease()
            }, ready: { try BelugaUpdateMenuClient.becomeReady(bundleURL: $0, menuInstanceID: $1) })
    }
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isUpdateInProgress = false
    @Published private(set) var statusText = "Updates are unavailable in this development build."
    private let bundleURL: URL
    private let isRelease: Bool
    private let menuInstanceID = UUID()
    private var admission = BelugaUpdateAdmission()
    private var task: Task<Void, Never>?
    private var needsReadiness = false
    private var failed = false
    private let operations: Operations

    init(bundle: Bundle = .main, operations: Operations = .native) {
        self.operations = operations
        bundleURL = bundle.bundleURL
        isRelease = (try? BelugaReleaseConfiguration(info: bundle.infoDictionary ?? [:])) != nil
        guard isRelease else { return }
        do { needsReadiness = try operations.hasFence(bundleURL) }
        catch { failed = true }
        refreshAvailability()
    }

    func updateAdmission(_ state: BelugaUpdateAdmission) {
        admission = state
        refreshAvailability()
    }

    func menuDidBecomeReady() {
        guard isRelease, needsReadiness, task == nil, !failed else { return }
        let url = bundleURL, menuID = menuInstanceID, operations = operations
        task = Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try operations.ready(url, menuID)
                }.value
                self?.needsReadiness = false
            } catch { self?.failed = true }
            self?.task = nil
            self?.refreshAvailability()
        }
        refreshAvailability()
    }

    func checkForUpdates() {
        guard canCheckForUpdates, task == nil else { return }
        let url = bundleURL, menuID = menuInstanceID, operations = operations
        task = Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try operations.begin(url, menuID)
                }.value
            } catch { self?.failed = true }
            self?.task = nil
            self?.refreshAvailability()
        }
        refreshAvailability()
    }

    // Allows deterministic test/lifetime draining; awaiting never grants admission.
    func waitForCurrentOperation() async { await task?.value }

    private func refreshAvailability() {
        isUpdateInProgress = isRelease && (task != nil || needsReadiness || failed)
        canCheckForUpdates = isRelease && !isUpdateInProgress && admission.permitsUpdate
        guard isRelease else { return }
        if failed {
            statusText = "Update verification needs recovery. Streaming remains blocked; no session will be interrupted."
        } else if task != nil || needsReadiness {
            statusText = "The separate updater owns this check. Streaming waits for verified completion."
        } else if admission.permitsUpdate {
            statusText = "Updates are signed and verified before installation."
        } else {
            statusText = "To update, finish sharing, quit Beluga, then reopen it before starting a stream."
        }
    }
}
