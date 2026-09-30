import Foundation
import UIKit
@preconcurrency import UserNotifications
import WebRTCTransport

/// The app remains the sole live-session owner. The extension is a bounded intent mailbox, not
/// another WebRTC client, audio session, or source of optimistic playback state.
@MainActor
final class MediaNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    typealias Dispatch = (MediaNotificationRequest,
                         @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) -> Bool
    nonisolated static let notificationIdentifier = "beluga.media.controls"

    private let store: MediaNotificationStore?
    private let center: UNUserNotificationCenter
    private let allowsNotificationDelivery: Bool
    private let automaticallyPolls: Bool
    private var epoch = UUID()
    private var state: WebRTCReceivedRemoteMediaState?
    private var dispatch: Dispatch?
    private var task: Task<Void, Never>?
    private var lastPublished: Double = 0
    private var permissionAttempted = false
    private var permissionNeedsForeground = false
    private var notificationTask: Task<Void, Never>?
    private var deliveredEpoch: UUID?
    private var pendingAcknowledgements: [UUID: (request: MediaNotificationRequest,
        result: MediaNotificationResult, expiresAt: Double)] = [:]

    init(store: MediaNotificationStore? = .configured(),
         center: UNUserNotificationCenter = .current(),
         allowsNotificationDelivery: Bool = true, automaticallyPolls: Bool = true) {
        self.store = store
        self.center = center
        self.allowsNotificationDelivery = allowsNotificationDelivery
        self.automaticallyPolls = automaticallyPolls
        super.init()
        if allowsNotificationDelivery, center.delegate == nil { center.delegate = self }
        // Supersede stale shared state left by a terminated app before accepting new commands.
        publishUnavailable()
        removeNotification()
    }

    func update(state: WebRTCReceivedRemoteMediaState?, ready: Bool, dispatch: @escaping Dispatch) {
        guard let state, ready, !state.update.allItems.isEmpty, store != nil else {
            if self.state != nil { invalidate() }
            return
        }
        if let previous = self.state, !previous.isSameNegotiation(as: state) { invalidate() }
        if self.state == nil { epoch = UUID() }
        self.state = state
        self.dispatch = dispatch
        guard publishCurrent() else { return }
        ensureNotification()
        guard automaticallyPolls, task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.pollOnce()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }

    func invalidate() {
        task?.cancel()
        task = nil
        notificationTask?.cancel()
        state = nil
        dispatch = nil
        pendingAcknowledgements.removeAll()
        epoch = UUID()
        deliveredEpoch = nil
        publishUnavailable()
        removeNotification()
    }

    private func removeNotification() {
        guard allowsNotificationDelivery else { return }
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }

    private func publishUnavailable() {
        try? store?.publishSnapshot(.init(epoch: epoch, revision: 1,
            publishedAtUptime: ProcessInfo.processInfo.systemUptime, ready: false, entries: []))
    }

    @discardableResult
    private func publishCurrent() -> Bool {
        guard let state, let store else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        let entries = state.update.allItems.map { item in
            MediaNotificationEntry(contextID: item.contextID, sourceName: item.sourceName,
                title: item.title, isPlaying: item.playbackState == .playing,
                position: item.elapsedTime, duration: item.duration,
                capabilities: .init(canPlay: item.capabilities.canPlay,
                    canPause: item.capabilities.canPause,
                    canSeekBackward: item.capabilities.canSeekBackward,
                    canSeekForward: item.capabilities.canSeekForward))
        }
        do {
            try store.publishSnapshot(.init(epoch: epoch, revision: state.update.revision,
                publishedAtUptime: now, ready: true, entries: entries))
            lastPublished = now
            return true
        } catch {
            // A busy or unavailable shared container never weakens the live command gate.
            return false
        }
    }

    func pollOnce() {
        let now = ProcessInfo.processInfo.systemUptime
        guard state != nil, let store else { return }
        flushAcknowledgements(now: now)
        if pendingAcknowledgements.isEmpty,
           (try? store.needsIdleEpochRotation(epoch: epoch, now: now)) == true {
            // A full replay journal gets a new card/epoch, never a cleared history under an
            // existing card. This leaves the transport and native Now Playing owner untouched.
            epoch = UUID()
            deliveredEpoch = nil
            lastPublished = 0
            notificationTask?.cancel()
            removeNotification()
        }
        if now - lastPublished >= 1, !publishCurrent() { return }
        ensureNotification()
        guard let request = try? store.claimPendingRequest(epoch: epoch, now: now) else { return }
        guard let state, request.epoch == epoch, request.revision <= state.update.revision,
              request.deadlineUptime > now, let dispatch else {
            finish(request, result: .stale)
            return
        }
        let completion = MediaNotificationCompletion { [weak self] result in
            Task { @MainActor in self?.finish(request, result: Self.result(result)) }
        }
        if !dispatch(request, { completion.call($0) }) { completion.call(.staleContext) }
    }

    private func finish(_ request: MediaNotificationRequest, result: MediaNotificationResult) {
        guard request.epoch == epoch, pendingAcknowledgements.count < 8 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        pendingAcknowledgements[request.id] = (request, result, now + 3)
        flushAcknowledgements(now: now)
    }

    private func flushAcknowledgements(now: Double) {
        guard let store else { return }
        for (id, pending) in pendingAcknowledgements {
            guard pending.request.epoch == epoch, now < pending.expiresAt else {
                pendingAcknowledgements.removeValue(forKey: id)
                continue
            }
            do {
                // A false return is terminal: the mailbox has already advanced. A contended
                // lock is not terminal; retry only this exact acknowledgement, never the command.
                _ = try store.acknowledge(.init(id: id, epoch: epoch, result: pending.result))
                pendingAcknowledgements.removeValue(forKey: id)
            } catch {
                // Bounded retries also cover temporary shared-container unavailability.
            }
        }
    }

    private nonisolated static func result(_ result: WebRTCRemoteMediaCommandResult) -> MediaNotificationResult {
        switch result {
        case .applied: .applied
        case .unsupported: .rejected
        case .staleContext: .stale
        case .noActiveMedia: .unavailable
        case .failed: .failed
        }
    }

    private func ensureNotification() {
        guard allowsNotificationDelivery, state != nil, deliveredEpoch != epoch, notificationTask == nil,
              !permissionNeedsForeground || UIApplication.shared.applicationState == .active else { return }
        let capturedEpoch = epoch
        notificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.notificationTask = nil
                if self.epoch != capturedEpoch { self.ensureNotification() }
            }
            let settings = await center.notificationSettings()
            guard !Task.isCancelled, epoch == capturedEpoch, state != nil else { return }
            switch Self.deliveryPolicy(status: settings.authorizationStatus,
                                       applicationIsActive: UIApplication.shared.applicationState == .active) {
            case .waitForForeground:
                permissionNeedsForeground = true
                return
            case .requestPermission:
                permissionNeedsForeground = false
                guard !permissionAttempted else { deliveredEpoch = capturedEpoch; return }
                permissionAttempted = true
                guard (try? await center.requestAuthorization(options: [.alert])) == true else {
                    deliveredEpoch = capturedEpoch
                    return
                }
            case .unavailable:
                deliveredEpoch = capturedEpoch
                return
            case .deliver:
                permissionNeedsForeground = false
            }
            guard !Task.isCancelled, epoch == capturedEpoch, state != nil else { return }
            var categories = await center.notificationCategories()
            categories = Set(categories.filter { $0.identifier != MediaNotificationConfiguration.category })
            categories.insert(UNNotificationCategory(identifier: MediaNotificationConfiguration.category,
                actions: [], intentIdentifiers: [], options: []))
            center.setNotificationCategories(categories)
            let content = UNMutableNotificationContent()
            content.title = "Beluga media controls"
            content.body = "Expand to choose a source and control playback."
            content.categoryIdentifier = MediaNotificationConfiguration.category
            content.userInfo = [MediaNotificationConfiguration.epochKey: capturedEpoch.uuidString]
            content.threadIdentifier = Self.notificationIdentifier
            guard !Task.isCancelled, epoch == capturedEpoch, state != nil else { return }
            do {
                try await center.add(UNNotificationRequest(identifier: Self.notificationIdentifier,
                                                           content: content, trigger: nil))
                guard !Task.isCancelled, epoch == capturedEpoch, state != nil else {
                    // An invalidation during notification delivery must not leave an actionable card.
                    center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
                    return
                }
                deliveredEpoch = capturedEpoch
            } catch {
                // Permission or delivery failure does not affect native playback or live transport.
                deliveredEpoch = capturedEpoch
            }
        }
    }

    enum DeliveryPolicy: Equatable { case requestPermission, waitForForeground, deliver, unavailable }

    /// Existing notification permission permits delivery while genuine playback keeps the app
    /// running in the background. Only a new permission prompt requires a foreground app.
    static func deliveryPolicy(status: UNAuthorizationStatus, applicationIsActive: Bool) -> DeliveryPolicy {
        switch status {
        case .notDetermined: applicationIsActive ? .requestPermission : .waitForForeground
        case .authorized, .provisional, .ephemeral: .deliver
        case .denied: .unavailable
        @unknown default: .unavailable
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier == Self.notificationIdentifier ? [.banner, .list] : []
    }
}

/// Both admission and transport failure paths may finish synchronously; expose only one outcome.
private final class MediaNotificationCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (WebRTCRemoteMediaCommandResult) -> Void)?
    init(_ handler: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) { self.handler = handler }
    func call(_ result: WebRTCRemoteMediaCommandResult) {
        let captured = lock.withLock { let value = handler; handler = nil; return value }
        captured?(result)
    }
}
