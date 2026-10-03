import SwiftUI
import UIKit
import WebRTCTransport

/// Observation only: neither this evidence nor the idle timer grants media-command authority.
/// The host's YouTube adapter admits only a www.youtube.com/watch HTMLVideoElement and supplies
/// its bounded artwork reference. Music apps and YouTube Music do not acquire this classification.
struct ScreenVideoPlaybackEvidence: Equatable {
    static let maximumAge: TimeInterval = 15
    let expiresAtUptime: TimeInterval

    init?(update: WebRTCRemoteMediaStateUpdate, receivedAtUptime: TimeInterval) {
        guard update.isValid, let item = update.item,
              item.sourceName == "YouTube", item.artwork?.provider == .youtube,
              item.playbackState == .playing, item.playbackRate > 0,
              receivedAtUptime.isFinite, receivedAtUptime >= 0 else { return nil }
        expiresAtUptime = receivedAtUptime + Self.maximumAge
    }
}

/// The one process-wide UIKit bridge. Per-presentation owners prevent a disappearing old viewer
/// from re-enabling sleep underneath its replacement. No audio-session changes or keepalive media.
@MainActor
final class ScreenVideoIdleTimer {
    static let shared = ScreenVideoIdleTimer {
        UIApplication.shared.isIdleTimerDisabled = $0
    }

    private let now: () -> TimeInterval
    private let setDisabled: (Bool) -> Void
    private var deadlines: [UUID: TimeInterval] = [:]
    private var expiryTasks: [UUID: Task<Void, Never>] = [:]
    private var disabled = false

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         setDisabled: @escaping (Bool) -> Void) {
        self.now = now
        self.setDisabled = setDisabled
    }

    func update(owner: UUID, playback: ScreenVideoPlaybackEvidence?,
                isViewingScreen: Bool, sceneIsActive: Bool) {
        let currentTime = now()
        guard isViewingScreen, sceneIsActive, let playback,
              currentTime.isFinite, currentTime >= 0,
              playback.expiresAtUptime.isFinite,
              playback.expiresAtUptime > currentTime,
              playback.expiresAtUptime - currentTime <= ScreenVideoPlaybackEvidence.maximumAge
        else {
            remove(owner: owner)
            return
        }
        let deadline = playback.expiresAtUptime
        guard deadlines[owner] != deadline else { return }
        deadlines[owner] = deadline
        expiryTasks.removeValue(forKey: owner)?.cancel()
        expiryTasks[owner] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(deadline - currentTime)) }
            catch { return }
            self?.expire(owner: owner, deadline: deadline)
        }
        reconcile()
    }

    func remove(owner: UUID) {
        deadlines.removeValue(forKey: owner)
        expiryTasks.removeValue(forKey: owner)?.cancel()
        reconcile()
    }

    func expire(owner: UUID, deadline: TimeInterval) {
        guard deadlines[owner] == deadline, now() >= deadline else { return }
        remove(owner: owner)
    }

    private func reconcile() {
        let next = !deadlines.isEmpty
        guard next != disabled else { return }
        disabled = next
        setDisabled(next)
    }
}

/// SwiftUI owns the lifetime and scene state; UIKit is used only for its native idle-timer switch.
struct ScreenVideoIdleTimerModifier: ViewModifier {
    let playback: ScreenVideoPlaybackEvidence?
    let isViewingScreen: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var owner = UUID()

    private struct Input: Equatable {
        let playback: ScreenVideoPlaybackEvidence?
        let isViewingScreen: Bool
        let sceneIsActive: Bool
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: Input(playback: playback, isViewingScreen: isViewingScreen,
                                sceneIsActive: scenePhase == .active), initial: true) { _, input in
                ScreenVideoIdleTimer.shared.update(owner: owner, playback: input.playback,
                    isViewingScreen: input.isViewingScreen, sceneIsActive: input.sceneIsActive)
            }
            .onDisappear { ScreenVideoIdleTimer.shared.remove(owner: owner) }
    }
}
