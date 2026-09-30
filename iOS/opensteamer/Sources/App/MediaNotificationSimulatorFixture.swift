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
                    do {
                        _ = try await viewer.requestRemoteMediaCommand(dispatch.command,
                            state: dispatch.state, authorization: dispatch.authorization,
                            contextID: dispatch.contextID,
                            positionSeconds: dispatch.positionSeconds,
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
            guard let command = WebRTCRemoteMediaCommand(rawValue: request.action.rawValue) else { return false }
            return gate.dispatch(.explicit(command), contextID: request.contextID,
                                 observedRevision: request.revision, completion: completion)
        }
    }

    private func publishInitialIfReady() async throws {
        guard hostOpen, viewerOpen, !sentInitial else { return }
        sentInitial = true
        try await host?.sendRemoteMediaState(update)
        updateEvidence()
    }

    private var update: WebRTCRemoteMediaStateUpdate {
        func item(_ context: String, _ source: String, _ playing: Bool, _ position: Double) -> WebRTCRemoteMediaItem {
            .init(contextID: context, sourceName: source, title: "Fixture \(context)",
                  playbackState: playing ? .playing : .paused, elapsedTime: position,
                  duration: 900, playbackRate: playing ? 1 : 0,
                  capabilities: .init(canPlay: true, canPause: true,
                      canSkipForward: false, canSkipBackward: false,
                      canSeekForward: true, canSeekBackward: true))
        }
        return .init(revision: revision, item: item("A", "Browser", aPlaying, aPosition),
                     additionalItems: [item("B", "Music", bPlaying, bPosition)])
    }

    private func applyOnFixtureHost(_ command: WebRTCReceivedRemoteMediaCommand) async throws {
        // A real asynchronous host boundary: the UI cannot authorize an optimistic local update.
        try await Task.sleep(for: .milliseconds(120))
        let request = command.request
        guard request.observedRevision == revision, ["A", "B"].contains(request.contextID) else {
            try await host?.acknowledgeRemoteMediaCommand(command, result: .staleContext)
            return
        }
        var playing = request.contextID == "A" ? aPlaying : bPlaying
        var position = request.contextID == "A" ? aPosition : bPosition
        switch request.command {
        case .play: playing = true
        case .pause: playing = false
        case .seekBackward30: position = max(0, position - 30)
        case .seekForward30: position = min(900, position + 30)
        default:
            try await host?.acknowledgeRemoteMediaCommand(command, result: .unsupported)
            return
        }
        if request.contextID == "A" { aPlaying = playing; aPosition = position }
        else { bPlaying = playing; bPosition = position }
        commands.append("\(request.contextID):\(request.command.rawValue)")
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
