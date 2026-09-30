#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI
import WebRTCTransport

/// Isolated native-transport oracle. This route is removed from device and distribution builds.
/// Its two local peers have no media capture, hardware audio, rendezvous, or pairing owner.
@MainActor
final class MediaNotificationSimulatorFixture: ObservableObject {
    @Published private(set) var status = "Starting local peers"
    @Published private(set) var evidence = "No host commands"
    @Published private(set) var ready = false
    private let gate = RemoteMediaCommandDispatchGate()
    private let owner = RemoteMediaCommandOwnerToken()
    private let notifications = MediaNotificationCoordinator()
    private var host: WebRTCPeer?
    private var viewer: WebRTCPeer?
    private var forwarders: [Task<Void, Never>] = []
    private var hostOpen = false
    private var viewerOpen = false
    private var sentInitial = false
    private var armed = false
    private var state: WebRTCReceivedRemoteMediaState?
    private var revision: UInt64 = 1
    private var aPlaying = true
    private var bPlaying = false
    private var aPosition: Double = 120
    private var bPosition: Double = 240
    private var aTrack = 1
    private var bTrack = 1
    private var commands: [String] = []

    func start() async {
        guard host == nil else { return }
        do {
            let host = try WebRTCPeer(configuration: .init(role: .host, iceServers: [],
                mediaTopology: .videoControlOnly, supportsRemoteMediaControls: true,
                supportsAudioClientDiagnostics: false))
            let viewer = try WebRTCPeer(configuration: .init(role: .viewer, iceServers: [],
                mediaTopology: .videoControlOnly, supportsRemoteMediaControls: true,
                supportsAudioClientDiagnostics: false))
            self.host = host
            self.viewer = viewer
            gate.claim(owner: owner) { dispatch in
                Task {
                    guard dispatch.isWithinDeadline(at: ProcessInfo.processInfo.systemUptime) else {
                        dispatch.completion?(.staleContext)
                        return
                    }
                    do {
                        _ = try await viewer.requestRemoteMediaCommand(dispatch.command,
                            state: dispatch.state, authorization: dispatch.authorization,
                            contextID: dispatch.contextID,
                            positionSeconds: dispatch.positionSeconds,
                            deadlineUptime: dispatch.deadlineUptime,
                            expectedDurationSeconds: dispatch.expectedDurationSeconds,
                            acknowledgementHandler: dispatch.completion)
                    } catch { dispatch.completion?(.failed) }
                }
            }
            forwarders.append(Task { [weak self] in
                do {
                    for await event in host.events {
                        guard !Task.isCancelled, let self else { return }
                        if case .outboundSignal(let signal) = event { try await viewer.handle(signal) }
                        if case .dataChannelStateChanged(.open) = event {
                            self.hostOpen = true
                            try await self.publishInitialIfReady()
                        }
                        if case .remoteMediaCommandReceived(let command) = event {
                            try await self.applyOnFixtureHost(command)
                        }
                    }
                } catch { self?.status = "Host failed: \(error)" }
            })
            forwarders.append(Task { [weak self] in
                do {
                    for await event in viewer.events {
                        guard !Task.isCancelled, let self else { return }
                        if case .outboundSignal(let signal) = event { try await host.handle(signal) }
                        if case .dataChannelStateChanged(.open) = event {
                            self.viewerOpen = true
                            try await self.publishInitialIfReady()
                        }
                        if case .remoteMediaStateChanged(let state) = event {
                            self.state = state
                            self.gate.update(owner: self.owner, state: state, transportIsReady: true)
                            self.ready = true
                            self.status = "Local WebRTC ready"
                            self.updateNotification()
                        }
                    }
                } catch { self?.status = "Viewer failed: \(error)" }
            })
            try await host.start()
        } catch { status = "Start failed: \(error)" }
    }

    func showNotification() {
        armed = true
        updateNotification()
    }

    func stop() async {
        notifications.invalidate()
        gate.release(owner: owner)
        forwarders.forEach { $0.cancel() }
        forwarders.removeAll()
        if let host { _ = await host.close(reason: .normal) }
        if let viewer { _ = await viewer.close(reason: .normal) }
        host = nil
        viewer = nil
        ready = false
        status = "Stopped"
    }

    private func updateNotification() {
        guard armed else { return }
        let gate = gate
        notifications.update(state: state, ready: ready) { request, completion in
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

    private func publishInitialIfReady() async throws {
        guard hostOpen, viewerOpen, !sentInitial else { return }
        sentInitial = true
        try await host?.sendRemoteMediaState(update)
        updateEvidence()
    }

    private var update: WebRTCRemoteMediaStateUpdate {
        func item(_ sourceID: String, _ source: String, _ playing: Bool, _ position: Double, _ track: Int) -> WebRTCRemoteMediaItem {
            .init(contextID: Self.contextID(sourceID, track: track), sourceName: source,
                  title: track == 1 ? "Fixture \(sourceID)" : "Fixture \(sourceID) • Track \(track)",
                  playbackState: playing ? .playing : .paused, elapsedTime: position,
                  duration: 900, playbackRate: playing ? 1 : 0,
                  capabilities: .init(canPlay: true, canPause: true,
                      canSkipForward: true, canSkipBackward: true,
                      canSeekForward: true, canSeekBackward: true, canSeekToPosition: true))
        }
        return .init(revision: revision, item: item("A", "Browser", aPlaying, aPosition, aTrack),
                     additionalItems: [item("B", "Music", bPlaying, bPosition, bTrack)])
    }

    private static func contextID(_ sourceID: String, track: Int) -> String {
        track == 1 ? sourceID : "\(sourceID)-track\(track)"
    }

    private func applyOnFixtureHost(_ command: WebRTCReceivedRemoteMediaCommand) async throws {
        // A real asynchronous host boundary: the UI cannot authorize an optimistic local update.
        try await Task.sleep(for: .milliseconds(120))
        let request = command.request
        guard request.observedRevision == revision,
              [Self.contextID("A", track: aTrack), Self.contextID("B", track: bTrack)].contains(request.contextID) else {
            try await host?.acknowledgeRemoteMediaCommand(command, result: .staleContext)
            return
        }
        let sourceID = request.contextID == Self.contextID("A", track: aTrack) ? "A" : "B"
        var playing = sourceID == "A" ? aPlaying : bPlaying
        var position = sourceID == "A" ? aPosition : bPosition
        switch request.command {
        case .play: playing = true
        case .pause: playing = false
        case .seekBackward30: position = max(0, position - 30)
        case .seekForward30: position = min(900, position + 30)
        case .seekToPosition:
            guard let requested = request.positionSeconds, requested.isFinite,
                  requested >= 0, requested <= 900 else {
                try await host?.acknowledgeRemoteMediaCommand(command, result: .unsupported)
                return
            }
            position = requested
        case .nextTrack, .previousTrack:
            // Each track transition retires the old context, including Previous back to an
            // earlier track; a stale card must never acquire authority through an ABA identity.
            if sourceID == "A" { aTrack += 1 } else { bTrack += 1 }
            position = 0
        }
        if sourceID == "A" { aPlaying = playing; aPosition = position }
        else { bPlaying = playing; bPosition = position }
        let positionReceipt = request.command == .seekToPosition ? "@\(position)" : ""
        commands.append("\(sourceID):\(request.command.rawValue)\(positionReceipt)")
        revision += 1
        try await host?.sendRemoteMediaState(update)
        try await host?.acknowledgeRemoteMediaCommand(command, result: .applied)
        updateEvidence()
    }

    private func updateEvidence() {
        evidence = "revision=\(revision);commands=\(commands.count);A=\(aPlaying ? "playing" : "paused"):\(Int(aPosition));B=\(bPlaying ? "playing" : "paused"):\(Int(bPosition));received=\(commands.joined(separator: ","))"
    }
}

struct MediaNotificationSimulatorFixtureView: View {
    @StateObject private var fixture = MediaNotificationSimulatorFixture()
    var body: some View {
        VStack(spacing: 24) {
            Text("Isolated notification transport test").font(.headline)
            Text(fixture.status).accessibilityIdentifier("notificationFixtureStatus")
            Text(fixture.evidence).accessibilityIdentifier("notificationFixtureEvidence")
            Button("Show media notification") { fixture.showNotification() }.disabled(!fixture.ready)
            Button("Stop local peers") { Task { await fixture.stop() } }
        }
        .padding()
        .task { await fixture.start() }
    }
}
#endif
