import SwiftUI
import UIKit
@preconcurrency import UserNotifications
@preconcurrency import UserNotificationsUI

@MainActor
final class NotificationViewController: UIViewController, @preconcurrency UNNotificationContentExtension {
    private let presentation = MediaNotificationPresentation(store: .configured())
    private var polling: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        let content = UIHostingController(rootView: MediaNotificationView(presentation: presentation))
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        content.view.backgroundColor = .clear
        view.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        content.didMove(toParent: self)
        preferredContentSize = CGSize(width: 360, height: 360)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extensionContext?.notificationActions = []
        presentation.refresh()
        polling?.invalidate()
        polling = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.presentation.refresh() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        polling?.invalidate()
        polling = nil
        presentation.becameHidden()
    }

    func didReceive(_ notification: UNNotification) {
        loadViewIfNeeded()
        extensionContext?.notificationActions = []
        let rawEpoch = notification.request.content.userInfo[MediaNotificationConfiguration.epochKey] as? String
        let epoch = rawEpoch.flatMap(UUID.init(uuidString:))
        guard notification.request.content.categoryIdentifier == MediaNotificationConfiguration.category,
              let epoch, epoch.uuidString == rawEpoch else {
            presentation.receive(epoch: nil)
            return
        }
        presentation.receive(epoch: epoch)
    }

    func didReceive(_ response: UNNotificationResponse,
                    completionHandler completion: @escaping @Sendable (UNNotificationContentExtensionResponseOption) -> Void) {
        // No standard actions are registered. Never reinterpret a cached system identifier.
        extensionContext?.notificationActions = []
        completion(.doNotDismiss)
    }
}

@MainActor
final class MediaNotificationPresentation: ObservableObject {
    @Published private(set) var snapshot: MediaNotificationSnapshot?
    @Published private(set) var selectedContextID: String?
    @Published private(set) var pending: MediaNotificationRequest?
    @Published private(set) var status = "Connect to your Mac in Beluga."
    private let store: MediaNotificationStore?
    private var epoch: UUID?
    private var selection = MediaNotificationSelection()

    init(store: MediaNotificationStore?) { self.store = store }

    var selected: MediaNotificationEntry? {
        snapshot?.entries.first { $0.contextID == selectedContextID }
    }

    var ready: Bool { snapshot?.ready == true && pending == nil }

    func receive(epoch: UUID?) {
        if self.epoch != epoch {
            self.epoch = epoch
            snapshot = nil
            selectedContextID = nil
            selection = MediaNotificationSelection()
            pending = nil
        }
        refresh()
    }

    func becameHidden() { snapshot = nil }

    func refresh() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let store, let epoch else {
            snapshot = nil
            status = "Controls unavailable. Open Beluga to reconnect."
            return
        }
        do {
            if let pending {
                if let acknowledgement = try store.acknowledgement(for: pending), acknowledgement.result != .pending {
                    self.pending = nil
                    status = acknowledgement.result == .applied ? "Updated on your Mac." : "Command not applied. Try again."
                } else if pending.deadlineUptime <= now {
                    self.pending = nil
                    status = "No confirmation from your Mac."
                }
            }
            guard let value = try store.readSnapshot(now: now), value.epoch == epoch, value.ready else {
                snapshot = nil
                status = "Controls unavailable. Open Beluga to reconnect."
                return
            }
            snapshot = value
            selection.refresh(contextIDs: value.entries.map(\.contextID))
            selectedContextID = selection.contextID
            if pending != nil { status = "Waiting for your Mac…" }
            else if selectedContextID == nil { status = "Source changed. Choose a source." }
            else if status == "Controls unavailable. Open Beluga to reconnect." || status == "Connect to your Mac in Beluga." {
                status = "Choose a source to control."
            }
        } catch MediaNotificationStore.StoreError.busy {
            // A contended read is not fresh authority, even when old UI remains visible.
            snapshot = nil
        } catch {
            snapshot = nil
            status = "Controls unavailable. Open Beluga to reconnect."
        }
    }

    func select(_ contextID: String) {
        guard ready, snapshot?.entries.contains(where: { $0.contextID == contextID }) == true else { return }
        selection.select(contextID, available: snapshot?.entries.map(\.contextID) ?? [])
        selectedContextID = selection.contextID
        status = "Choose a source to control."
    }

    func send(_ action: MediaNotificationAction) {
        guard pending == nil, let store, let snapshot, snapshot.epoch == epoch,
              let selected, selected.capabilities.permits(action) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let request = MediaNotificationRequest(id: UUID(), epoch: snapshot.epoch, revision: snapshot.revision,
                                               contextID: selected.contextID, action: action,
                                               deadlineUptime: now + MediaNotificationRequest.maximumLifetime)
        do {
            guard try store.submit(request, now: now) else {
                status = "Source changed or another command is pending. Try again."
                refresh()
                return
            }
            pending = request
            status = "Waiting for your Mac…"
        } catch {
            status = "Controls unavailable. Try again."
            self.snapshot = nil
        }
    }
}

private struct MediaNotificationView: View {
    @ObservedObject var presentation: MediaNotificationPresentation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Beluga · Mac playback").font(.headline)
                ForEach(presentation.snapshot?.entries ?? []) { entry in
                    Button { presentation.select(entry.contextID) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: entry.isPlaying ? "waveform" : "music.note")
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.sourceName).font(.caption).foregroundStyle(.secondary)
                                Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            if entry.contextID == presentation.selectedContextID {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.ready)
                    .accessibilityLabel("\(entry.sourceName), \(entry.title), \(entry.isPlaying ? "Playing" : "Paused")")
                    .accessibilityAddTraits(entry.contextID == presentation.selectedContextID ? .isSelected : [])
                }
                if let selected = presentation.selected {
                    HStack {
                        transport("Backward 30 seconds", symbol: "gobackward.30", action: .seekBackward30, entry: selected)
                        transport(selected.isPlaying ? "Pause" : "Play", symbol: selected.isPlaying ? "pause.fill" : "play.fill",
                                  action: selected.isPlaying ? .pause : .play, entry: selected)
                        transport("Forward 30 seconds", symbol: "goforward.30", action: .seekForward30, entry: selected)
                    }
                }
                Text(presentation.status).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("mediaControlsStatus")
            }
            .padding(16)
        }
    }

    private func transport(_ title: String, symbol: String, action: MediaNotificationAction,
                           entry: MediaNotificationEntry) -> some View {
        Button { presentation.send(action) } label: {
            Image(systemName: symbol).font(.title2).frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
        .disabled(!presentation.ready || !entry.capabilities.permits(action))
    }
}
