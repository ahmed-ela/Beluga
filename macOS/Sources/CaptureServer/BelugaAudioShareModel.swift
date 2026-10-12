import Combine
import Foundation

/// Secret-bearing URLs remain in this UI's memory only. No persistence, notification, or log.
@MainActor
final class BelugaAudioShareModel: ObservableObject {
    @Published var durationMinutes = 15
    @Published private(set) var url: URL?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var isWorking = false
    @Published private(set) var isQuarantined = false
    @Published private(set) var listenerCount = 0
    @Published private(set) var statusText = "Create a private, expiring link to this Mac’s system audio."
    private var revision: UInt64 = 0
    private var operation: UUID?
    private var isStopping = false
    private var ownerRetired = false
    private var task: Task<Void, Never>?
    private var startOperation: (@Sendable (Int) async throws -> BelugaAudioShareStarted)?
    private var stopOperation: (@Sendable () async -> Bool)?
    private var revokeOperation: (@Sendable () -> Void)?

    var hasPendingOrActiveShare: Bool { isWorking || url != nil || isQuarantined }

    func configure(start: @escaping @Sendable (Int) async throws -> BelugaAudioShareStarted,
                   stop: @escaping @Sendable () async -> Bool,
                   revoke: @escaping @Sendable () -> Void) {
        guard startOperation == nil else { return }
        startOperation = start
        stopOperation = stop
        revokeOperation = revoke
    }

    func start(ownerIsValid: Bool, updateInProgress: Bool) {
        guard !ownerRetired, ownerIsValid, !updateInProgress, !hasPendingOrActiveShare,
              [5, 15, 30, 60, 120].contains(durationMinutes), let startOperation else { return }
        let identity = UUID()
        operation = identity
        isStopping = false
        isWorking = true
        statusText = "Creating private link…"
        let duration = durationMinutes * 60
        task = Task { [weak self] in
            do {
                let started = try await startOperation(duration)
                guard let self, self.operation == identity, !Task.isCancelled else { return }
                self.url = started.url
                self.expiresAt = started.expiresAt
                self.isWorking = false
                self.statusText = "Link active — waiting for a browser listener."
            } catch {
                guard let self, self.operation == identity else { return }
                self.operation = nil
                self.isWorking = false
                // An opaque error is intentional: failures may embed capability-bearing URLs.
                self.statusText = "The private link could not be created."
            }
        }
    }

    func stop() {
        guard !ownerRetired, !isStopping, !isQuarantined, let stopOperation else { return }
        revokeOperation?()
        task?.cancel()
        let identity = UUID()
        operation = identity
        isStopping = true
        clearLink()
        isWorking = true
        statusText = "Ending share and confirming capture has stopped…"
        task = Task { [weak self] in
            let confirmed = await stopOperation()
            guard let self, self.operation == identity else { return }
            self.operation = nil
            self.isStopping = false
            self.isWorking = false
            self.isQuarantined = !confirmed
            self.statusText = confirmed ? "Audio share ended."
                : "Capture shutdown could not be confirmed. Sharing and updates remain disabled."
        }
    }

    func apply(_ status: BelugaAudioShareStatus, revision: UInt64) {
        guard !ownerRetired, revision > self.revision else { return }
        self.revision = revision
        switch status {
        case .idle, .starting: break
        case .active(let listeners):
            guard !isQuarantined else { return }
            listenerCount = listeners
            if url != nil { statusText = "Link active · \(listeners) browser listener(s)" }
        case .ended:
            clearLink()
            // The current stop still owns its native confirmation; do not clear its busy fence.
            if !isStopping {
                operation = nil
                isWorking = false
                statusText = "Audio share ended."
            }
        case .failed:
            clearLink()
            if !isStopping {
                operation = nil
                isWorking = false
                // Confirm the native boundary before permitting another share after any failure.
                stop()
            }
        }
    }

    /// Called only after the process owner's full native teardown returned confirmed. A failed
    /// native teardown exits through the existing fail-closed supervisor and never reaches here.
    func ownerStopped() {
        ownerRetired = true
        operation = nil
        task?.cancel()
        task = nil
        clearLink()
        isWorking = false
        isStopping = false
        isQuarantined = false
        statusText = "This Mac’s host has stopped."
    }

    private func clearLink() { url = nil; expiresAt = nil; listenerCount = 0 }
}

/// Stamps publication order before crossing actors, preventing delayed UI tasks from restoring
/// an older listener count or status. The coordinator additionally fences session generations.
final class BelugaAudioShareStatusRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private let sink: @Sendable (BelugaAudioShareStatus, UInt64) -> Void
    init(sink: @escaping @Sendable (BelugaAudioShareStatus, UInt64) -> Void) { self.sink = sink }
    func publish(_ status: BelugaAudioShareStatus) {
        lock.withLock {
            guard revision < UInt64.max else { return }
            revision += 1
            sink(status, revision)
        }
    }
}
