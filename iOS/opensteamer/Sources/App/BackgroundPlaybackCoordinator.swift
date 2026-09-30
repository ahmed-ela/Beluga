@preconcurrency import MediaPlayer
import UIKit
import WebRTCTransport

/// Minimal interface for borrowing iOS background time while a lifecycle transition settles.
/// Implementations must balance every successful begin with an end and must not treat the lease
/// as permission for indefinite background execution.
@MainActor
protocol TransitionBackgroundTaskCoordinating: AnyObject {
    func beginTransitionTask()
    func endTransitionTask()
}

/// A bounded iOS background-task lease for short state transitions that must finish atomically.
/// It does not grant continuous background execution and must never be used as a media lifetime.
@MainActor
final class AppTransitionBackgroundTaskCoordinator: TransitionBackgroundTaskCoordinating {
    private let name: String
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        self.name = name
    }

    func beginTransitionTask() {
        guard backgroundTask == .invalid else { return }

        let task = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.endTransitionTask()
            }
        }
        guard task != .invalid else { return }
        backgroundTask = task
    }

    func endTransitionTask() {
        guard backgroundTask != .invalid else { return }

        let task = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }
}

/// Thread-safe admission bridge used by MediaPlayer callbacks, which are not guaranteed to arrive
/// on the main actor. Authority is captured here, not reacquired after an actor hop.
struct RemoteMediaCommandDispatch: Sendable {
    let command: WebRTCRemoteMediaCommand
    let state: WebRTCReceivedRemoteMediaState
    let authorization: WebRTCControlAuthorization
    let contextID: String?
    let positionSeconds: TimeInterval?
    let deadlineUptime: TimeInterval?
    let expectedDurationSeconds: TimeInterval?
    let completion: (@Sendable (WebRTCRemoteMediaCommandResult) -> Void)?

    init(command: WebRTCRemoteMediaCommand, state: WebRTCReceivedRemoteMediaState,
         authorization: WebRTCControlAuthorization, contextID: String? = nil,
         positionSeconds: TimeInterval? = nil,
         deadlineUptime: TimeInterval? = nil,
         expectedDurationSeconds: TimeInterval? = nil,
         completion: (@Sendable (WebRTCRemoteMediaCommandResult) -> Void)? = nil) {
        self.command = command
        self.state = state
        self.authorization = authorization
        self.contextID = contextID
        self.positionSeconds = positionSeconds
        self.deadlineUptime = deadlineUptime
        self.expectedDurationSeconds = expectedDurationSeconds
        self.completion = completion
    }

    func isWithinDeadline(at now: TimeInterval) -> Bool {
        Self.isWithinDeadline(deadlineUptime, at: now)
    }

    static func isWithinDeadline(_ deadline: TimeInterval?, at now: TimeInterval) -> Bool {
        guard let deadline else { return true }
        return now.isFinite && now >= 0 && deadline.isFinite && deadline > now
            && deadline - now <= MediaNotificationRequest.maximumLifetime
    }
}

typealias RemoteMediaCommandSender = @Sendable (RemoteMediaCommandDispatch) -> Void

/// Accessory buttons may send a toggle rather than the Lock Screen's explicit play/pause.
/// Resolve it from the admitted Mac item, never local audio state or a later actor-hop snapshot.
enum RemoteMediaCommandIntent: Sendable {
    case explicit(WebRTCRemoteMediaCommand)
    case togglePlayPause
    case seekToPosition(TimeInterval)

    func positionSeconds(for item: WebRTCRemoteMediaItem) -> TimeInterval? {
        guard case .seekToPosition(let position) = self,
              position.isFinite, position >= 0, position <= 31_536_000,
              let elapsed = item.elapsedTime, elapsed.isFinite, elapsed >= 0,
              let duration = item.duration, duration.isFinite,
              duration > 0, duration <= 31_536_000 else { return nil }
        return min(position, duration)
    }

    func permittedCommand(for item: WebRTCRemoteMediaItem) -> WebRTCRemoteMediaCommand? {
        let command: WebRTCRemoteMediaCommand
        switch self {
        case .explicit(let explicit):
            guard explicit != .seekToPosition else { return nil }
            command = explicit
        case .seekToPosition:
            guard positionSeconds(for: item) != nil else { return nil }
            command = .seekToPosition
        case .togglePlayPause:
            command = switch item.playbackState {
            case .playing: .pause
            case .paused, .stopped: .play
            }
        }
        return item.capabilities.permits(command) ? command : nil
    }
}

/// Process-local authority for the one worldwide session allowed to mutate the process-global
/// MediaPlayer command center. A superseded view model can still drain delayed callbacks, but its
/// token can no longer replace metadata, reopen commands, or release a newer owner.
struct RemoteMediaCommandOwnerToken: Hashable, Sendable {
    fileprivate let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

final class RemoteMediaCommandDispatchGate: @unchecked Sendable {

    private let lock = NSLock()
    private var owner: RemoteMediaCommandOwnerToken?
    private var state: WebRTCReceivedRemoteMediaState?
    private var authorization: WebRTCControlAuthorization?
    private var transportIsReady = false
    private var sender: RemoteMediaCommandSender?

    func claim(
        owner: RemoteMediaCommandOwnerToken,
        sender: @escaping RemoteMediaCommandSender
    ) {
        lock.withLock {
            authorization?.revoke()
            authorization = nil
            self.owner = owner
            self.state = nil
            self.transportIsReady = false
            self.sender = sender
        }
    }

    @discardableResult
    func release(owner: RemoteMediaCommandOwnerToken) -> Bool {
        lock.withLock {
            guard self.owner == owner else { return false }
            authorization?.revoke()
            authorization = nil
            self.owner = nil
            self.state = nil
            self.transportIsReady = false
            self.sender = nil
            return true
        }
    }

    @discardableResult
    func update(
        owner: RemoteMediaCommandOwnerToken,
        state: WebRTCReceivedRemoteMediaState?,
        transportIsReady: Bool
    ) -> Bool {
        lock.withLock {
            guard self.owner == owner else { return false }
            let samePresentation = self.state.map { previous in
                state.map {
                    previous.isSameNegotiation(as: $0)
                        && previous.update.allItems.map(\.contextID) == $0.update.allItems.map(\.contextID)
                        && previous.update.allItems.map(\.capabilities) == $0.update.allItems.map(\.capabilities)
                } ?? false
            } ?? false
            if !transportIsReady || !samePresentation || state?.update.item == nil {
                authorization?.revoke()
                authorization = nil
            }
            if transportIsReady, state?.update.item != nil, authorization == nil {
                authorization = WebRTCControlAuthorization()
            }
            self.state = state
            self.transportIsReady = transportIsReady
            return true
        }
    }

    func dispatch(_ command: WebRTCRemoteMediaCommand) -> Bool {
        dispatch(RemoteMediaCommandIntent.explicit(command))
    }

    func dispatch(_ intent: RemoteMediaCommandIntent) -> Bool {
        dispatch(intent, contextID: nil, observedRevision: nil, completion: nil)
    }

    func dispatch(_ intent: RemoteMediaCommandIntent, contextID: String?,
                  observedRevision: UInt64?,
                  deadlineUptime: TimeInterval? = nil,
                  expectedDurationSeconds: TimeInterval? = nil,
                  completion: (@Sendable (WebRTCRemoteMediaCommandResult) -> Void)?) -> Bool {
        let admitted: (RemoteMediaCommandSender, RemoteMediaCommandDispatch)? = lock.withLock {
            guard RemoteMediaCommandDispatch.isWithinDeadline(deadlineUptime,
                      at: ProcessInfo.processInfo.systemUptime),
                  transportIsReady,
                  let state,
                  observedRevision.map({ $0 > 0 && $0 <= state.update.revision }) ?? true,
                  let item = contextID.map({ state.update.item(contextID: $0) }) ?? state.update.item,
                  let command = intent.permittedCommand(for: item),
                  expectedDurationSeconds.map({ expected in
                      guard case .seekToPosition(let position) = intent else { return false }
                      return expected.isFinite && expected > 0
                          && expected <= 31_536_000 && item.duration == expected
                          && position <= expected
                  }) ?? true,
                  state.update.revision > 0,
                  let authorization,
                  authorization.isValid,
                  let sender else { return nil }
            return (sender, RemoteMediaCommandDispatch(
                command: command,
                state: state,
                authorization: authorization,
                contextID: item.contextID,
                positionSeconds: intent.positionSeconds(for: item),
                deadlineUptime: deadlineUptime,
                expectedDurationSeconds: expectedDurationSeconds,
                completion: completion
            ))
        }
        guard let admitted else { return false }
        admitted.0(admitted.1)
        return true
    }
}

/// Publishes lock-screen playback state, installs native media commands exactly once, and owns
/// transition-only background leases. Continuous background eligibility still comes from genuine
/// audio playout rather than this object.
@MainActor
final class BackgroundPlaybackCoordinator {
    static let shared = BackgroundPlaybackCoordinator(enableMediaNotifications: true)

    private let transitionTask = AppTransitionBackgroundTaskCoordinator(
        name: "opensteamerBackgroundPlayback"
    )
    private let commandGate = RemoteMediaCommandDispatchGate()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var remoteMediaCommandOwner: RemoteMediaCommandOwnerToken?
    private var remoteMediaState: WebRTCReceivedRemoteMediaState?
    private var remoteMediaUpdate: WebRTCRemoteMediaStateUpdate? { remoteMediaState?.update }
    private var remoteMediaTransportIsReady = false
    private var remoteMediaCommandSender: RemoteMediaCommandSender?
    private var genericPlayback: (serverName: String?, isPlaying: Bool)?
    private let artwork: RemoteMediaArtworkPresentation
    private var metadataPublishedAt: TimeInterval = 0
    private let mediaNotifications: MediaNotificationCoordinator?
    var pendingArtworkLoadTask: Task<Void, Never>? { artwork.pendingLoadTask }

    init(
        artworkLoader: any RemoteMediaArtworkLoading = RemoteMediaArtworkLoader(),
        installNativeCommandTargets: Bool = true,
        enableMediaNotifications: Bool = false
    ) {
        artwork = RemoteMediaArtworkPresentation(loader: artworkLoader)
        mediaNotifications = enableMediaNotifications ? MediaNotificationCoordinator() : nil
        if installNativeCommandTargets { installCommandTargetsIfNeeded() }
        updateNativeCommandAvailability()
    }

    func beginTransitionTask() {
        // This is only transition grace; continuous background eligibility comes from active audio playback.
        transitionTask.beginTransitionTask()
    }

    func endTransitionTask() {
        transitionTask.endTransitionTask()
    }

    func publishLiveStream(serverName: String?, isPlaying: Bool) {
        genericPlayback = (serverName, isPlaying)
        guard remoteMediaUpdate?.item == nil else { return }
        publishGenericPlayback(serverName: serverName, isPlaying: isPlaying)
    }

    func claimRemoteMediaCommandSender(
        _ sender: @escaping RemoteMediaCommandSender
    ) -> RemoteMediaCommandOwnerToken {
        let owner = RemoteMediaCommandOwnerToken()
        remoteMediaCommandOwner = owner
        remoteMediaState = nil
        remoteMediaTransportIsReady = false
        remoteMediaCommandSender = sender
        commandGate.claim(owner: owner, sender: sender)
        mediaNotifications?.invalidate()
        updateNativeCommandAvailability()
        if let genericPlayback {
            publishGenericPlayback(
                serverName: genericPlayback.serverName,
                isPlaying: genericPlayback.isPlaying
            )
        } else {
            clearNowPlayingInfo()
        }
        return owner
    }

    func releaseRemoteMediaCommandSender(
        owner: RemoteMediaCommandOwnerToken
    ) {
        guard remoteMediaCommandOwner == owner else { return }
        remoteMediaCommandOwner = nil
        remoteMediaState = nil
        remoteMediaTransportIsReady = false
        remoteMediaCommandSender = nil
        _ = commandGate.release(owner: owner)
        mediaNotifications?.invalidate()
        updateNativeCommandAvailability()
        if let genericPlayback {
            publishGenericPlayback(
                serverName: genericPlayback.serverName,
                isPlaying: genericPlayback.isPlaying
            )
        } else {
            clearNowPlayingInfo()
        }
    }

    func setRemoteMediaTransportReady(
        _ isReady: Bool,
        owner: RemoteMediaCommandOwnerToken
    ) {
        guard remoteMediaCommandOwner == owner else { return }
        remoteMediaTransportIsReady = isReady
        updateCommandGate()
        updateNativeCommandAvailability()
        reconcileArtwork()
        if !isReady, var info = MPNowPlayingInfoCenter.default().nowPlayingInfo,
           info.removeValue(forKey: MPMediaItemPropertyArtwork) != nil {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    func publishRemoteMedia(
        _ state: WebRTCReceivedRemoteMediaState,
        owner: RemoteMediaCommandOwnerToken
    ) {
        let update = state.update
        guard remoteMediaCommandOwner == owner,
              update.isValid,
              update.revision > (remoteMediaUpdate?.revision ?? 0) else {
            return
        }
        if let previous = remoteMediaState, !previous.isSameNegotiation(as: state) {
            mediaNotifications?.invalidate()
        }
        remoteMediaState = state
        metadataPublishedAt = ProcessInfo.processInfo.systemUptime
        updateCommandGate()
        updateNativeCommandAvailability()
        reconcileArtwork()

        guard update.item != nil else {
            if let genericPlayback {
                publishGenericPlayback(
                    serverName: genericPlayback.serverName,
                    isPlaying: genericPlayback.isPlaying
                )
            } else {
                clearNowPlayingInfo()
            }
            return
        }
        publishCurrentRemoteMedia(advancingElapsed: false)
    }

    private func reconcileArtwork() {
        artwork.update(state: remoteMediaState, owner: remoteMediaCommandOwner,
                       isReady: remoteMediaTransportIsReady) { [weak self] in
            guard let self, self.remoteMediaTransportIsReady else { return }
            self.publishCurrentRemoteMedia(advancingElapsed: true)
        }
    }

    private func publishCurrentRemoteMedia(advancingElapsed: Bool) {
        guard let item = remoteMediaUpdate?.item else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artist ?? item.sourceName,
            MPNowPlayingInfoPropertyExternalContentIdentifier: item.contextID,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyPlaybackRate: item.playbackRate
        ]
        if let album = item.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let elapsedTime = item.elapsedTime {
            let delta = advancingElapsed
                ? max(0, ProcessInfo.processInfo.systemUptime - metadataPublishedAt) * item.playbackRate : 0
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = min(elapsedTime + delta, item.duration ?? .infinity)
        }
        if let duration = item.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let decoded = artwork.image {
            let image = UIImage(cgImage: decoded.image)
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = switch item.playbackState {
        case .playing: .playing
        case .paused: .paused
        case .stopped: .stopped
        }
    }

    func clearRemoteMedia(owner: RemoteMediaCommandOwnerToken) {
        guard remoteMediaCommandOwner == owner else { return }
        remoteMediaState = nil
        remoteMediaTransportIsReady = false
        updateCommandGate()
        updateNativeCommandAvailability()
        if let genericPlayback {
            publishGenericPlayback(
                serverName: genericPlayback.serverName,
                isPlaying: genericPlayback.isPlaying
            )
        } else {
            clearNowPlayingInfo()
        }
    }

    private func publishGenericPlayback(serverName: String?, isPlaying: Bool) {
        artwork.clear()
        // Lock-screen metadata is visible outside the unlocked app. Keep it deliberately generic
        // rather than exposing the paired Mac's user-assigned name.
        _ = serverName
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Beluga",
            MPMediaItemPropertyArtist: "Connected Mac",
            MPMediaItemPropertyAlbumTitle: "Mac audio stream",
            // Missing Mac item metadata does not identify a live broadcast.
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        genericPlayback = nil
        if remoteMediaUpdate?.item == nil { clearNowPlayingInfo() }
        endTransitionTask()
    }

    private func clearNowPlayingInfo() {
        artwork.clear()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func installCommandTargetsIfNeeded() {
        guard commandTargets.isEmpty else { return }
        let mappings: [(MPRemoteCommand, RemoteMediaCommandIntent)] = [
            (commandCenter.playCommand, .explicit(.play)),
            (commandCenter.pauseCommand, .explicit(.pause)),
            (commandCenter.togglePlayPauseCommand, .togglePlayPause),
            (commandCenter.nextTrackCommand, .explicit(.nextTrack)),
            (commandCenter.previousTrackCommand, .explicit(.previousTrack)),
            (commandCenter.skipForwardCommand, .explicit(.seekForward30)),
            (commandCenter.skipBackwardCommand, .explicit(.seekBackward30))
        ]
        for (nativeCommand, command) in mappings {
            let gate = commandGate
            let target = nativeCommand.addTarget { @Sendable _ in
                gate.dispatch(command) ? .success : .commandFailed
            }
            commandTargets.append((nativeCommand, target))
        }
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipBackwardCommand.preferredIntervals = [30]
        let gate = commandGate
        let positionTarget = commandCenter.changePlaybackPositionCommand.addTarget { @Sendable event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return gate.dispatch(.seekToPosition(event.positionTime)) ? .success : .commandFailed
        }
        commandTargets.append((commandCenter.changePlaybackPositionCommand, positionTarget))
        // These controls have no negotiated Mac-side semantic and must never appear as no-op UI.
        commandCenter.stopCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.changeRepeatModeCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.isEnabled = false
        commandCenter.enableLanguageOptionCommand.isEnabled = false
        commandCenter.disableLanguageOptionCommand.isEnabled = false
        commandCenter.ratingCommand.isEnabled = false
        commandCenter.likeCommand.isEnabled = false
        commandCenter.dislikeCommand.isEnabled = false
        commandCenter.bookmarkCommand.isEnabled = false
    }

    private func updateCommandGate() {
        guard let remoteMediaCommandOwner else { return }
        commandGate.update(
            owner: remoteMediaCommandOwner,
            state: remoteMediaState,
            transportIsReady: remoteMediaTransportIsReady
        )
        let gate = commandGate
        mediaNotifications?.update(state: remoteMediaState, ready: remoteMediaTransportIsReady) {
            request, completion in
            guard request.isValid(at: ProcessInfo.processInfo.systemUptime),
                  let command = WebRTCRemoteMediaCommand(rawValue: request.action.rawValue) else { return false }
            let intent: RemoteMediaCommandIntent
            if command == .seekToPosition {
                guard let position = request.positionSeconds else { return false }
                intent = .seekToPosition(position)
            } else { intent = .explicit(command) }
            return gate.dispatch(intent, contextID: request.contextID,
                                 observedRevision: request.revision,
                                 deadlineUptime: request.deadlineUptime,
                                 expectedDurationSeconds: request.expectedDurationSeconds, completion: completion)
        }
    }

    private func updateNativeCommandAvailability() {
        let capabilities = remoteMediaUpdate?.item?.capabilities
        let ready = remoteMediaTransportIsReady && remoteMediaCommandSender != nil
        commandCenter.playCommand.isEnabled = ready && (capabilities?.canPlay ?? false)
        commandCenter.pauseCommand.isEnabled = ready && (capabilities?.canPause ?? false)
        commandCenter.togglePlayPauseCommand.isEnabled = ready
            && remoteMediaUpdate?.item.flatMap {
                RemoteMediaCommandIntent.togglePlayPause.permittedCommand(for: $0)
            } != nil
        commandCenter.nextTrackCommand.isEnabled =
            ready && (capabilities?.canSkipForward ?? false)
        commandCenter.previousTrackCommand.isEnabled =
            ready && (capabilities?.canSkipBackward ?? false)
        commandCenter.skipForwardCommand.isEnabled = ready && (capabilities?.canSeekForward ?? false)
        commandCenter.skipBackwardCommand.isEnabled = ready && (capabilities?.canSeekBackward ?? false)
        commandCenter.changePlaybackPositionCommand.isEnabled = ready
            && remoteMediaUpdate?.item.flatMap {
                RemoteMediaCommandIntent.seekToPosition(0).permittedCommand(for: $0)
            } != nil
    }

    #if DEBUG
    func debugHasNativeCommandTarget(_ command: MPRemoteCommand) -> Bool {
        commandTargets.contains { $0.0 === command }
    }
    #endif
}

extension BackgroundPlaybackCoordinator: TransitionBackgroundTaskCoordinating {}
