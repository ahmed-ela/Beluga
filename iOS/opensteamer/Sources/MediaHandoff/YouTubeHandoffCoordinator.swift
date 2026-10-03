import SwiftUI
import WebKit
import WebRTCTransport

/// Main-actor ownership of one offer, one visible provider player and one audio suppression.
/// Transport/native source authority remains with the exact peer and Mac prepared source.
@MainActor
final class YouTubeHandoffCoordinator: ObservableObject {
    struct AudioSuppression {
        let isValid: @MainActor () -> Bool
        let release: @MainActor () -> Void
    }

    struct Connection {
        let isCurrent: @MainActor () -> Bool
        let acquireAudio: @MainActor (@escaping @MainActor () -> Void) -> AudioSuppression?
        let commit: @MainActor (YouTubePhonePlaybackEvidence, WebRTCControlAuthorization) async throws -> Void
        let cancel: @MainActor () async -> Void
        let discard: @MainActor () async -> Void
    }

    struct Presentation: Identifiable {
        let id: UUID // Local incarnation, deliberately not the untrusted wire operation ID.
        let presenterID: UUID
        let player: YouTubeHandoffPlayer
    }

    private final class Context {
        let id: UUID
        let player: YouTubeHandoffPlayer
        let connection: Connection
        let audio: AudioSuppression
        var commitStarted = false
        var commitTask: Task<Void, Never>?
        var deadlineTask: Task<Void, Never>?
        init(id: UUID, player: YouTubeHandoffPlayer, connection: Connection, audio: AudioSuppression) {
            self.id = id; self.player = player; self.connection = connection; self.audio = audio
        }
    }

    @Published private(set) var presentation: Presentation?
    private var presenters: [UUID: Int] = [:]
    private var active: Context?
    private var closing: Context?
    private let now: @MainActor () -> Double
    private let makePlayer: @MainActor (YouTubeHandoffRequest, @escaping @MainActor (YouTubeHandoffPlayerEvent) -> Void) -> YouTubeHandoffPlayer

    init(now: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime },
         makePlayer: (@MainActor (YouTubeHandoffRequest, @escaping @MainActor (YouTubeHandoffPlayerEvent) -> Void) -> YouTubeHandoffPlayer)? = nil) {
        self.now = now
        self.makePlayer = makePlayer ?? { YouTubeHandoffPlayer(request: $0, eventHandler: $1) }
    }

    func registerPresenter(_ id: UUID, priority: Int) {
        presenters[id] = priority
        // Never migrate an already-created WK player into another presentation hierarchy.
        if let presentation, selectedPresenter != presentation.presenterID { invalidate() }
    }

    func unregisterPresenter(_ id: UUID) {
        presenters.removeValue(forKey: id)
        if presentation?.presenterID == id { invalidate() }
    }

    private var selectedPresenter: UUID? {
        let highest = presenters.values.max()
        let candidates = presenters.filter { $0.value == highest }.map(\.key)
        return candidates.count == 1 ? candidates.first : nil
    }

    @discardableResult
    func receive(_ request: YouTubeHandoffRequest, connection: Connection) -> Bool {
        let instant = now()
        guard active == nil, closing == nil, presentation == nil,
              let presenter = selectedPresenter, connection.isCurrent(),
              instant.isFinite, instant >= request.positionObservedAtUptime,
              instant < request.deadlineUptime else {
            Task { await connection.discard() }; return false
        }
        let id = UUID()
        var invalidatedDuringAcquire = false
        let audio = connection.acquireAudio { [weak self] in
            invalidatedDuringAcquire = true
            guard let self, self.active?.id == id else { return }
            self.invalidate()
        }
        guard let audio else { Task { await connection.discard() }; return false }
        guard !invalidatedDuringAcquire, audio.isValid(), connection.isCurrent(),
              selectedPresenter == presenter else {
            audio.release(); Task { await connection.discard() }; return false
        }
        let player = makePlayer(request) { [weak self] event in self?.receive(event, id: id) }
        let context = Context(id: id, player: player, connection: connection, audio: audio)
        active = context
        presentation = Presentation(id: id, presenterID: presenter, player: player)
        context.deadlineTask = Task { [weak self, weak context, now] in
            do { try await Task.sleep(for: .seconds(max(0, request.deadlineUptime - now()))) }
            catch { return }
            guard let self, let context, self.active === context else { return }
            // Also bounds an offer whose sheet could not be presented. Releasing audio still
            // requires exact WebKit cleanup if a view was ever created.
            self.retire(context)
        }
        return true
    }

    func receiveCompletion(_ completion: WebRTCMediaHandoffCompletion) {
        guard let context = active, context.connection.isCurrent(), context.audio.isValid(),
              context.player.id == completion.id else { return }
        context.player.receiveMacPauseCompletion(completion)
    }

    func dismiss(_ id: UUID) {
        guard presentation?.id == id else { return }
        invalidate()
    }

    /// Called synchronously on peer/session/authorization/foreground retirement.
    func invalidate() {
        presentation = nil
        guard let context = active else { return }
        retire(context)
    }

    private func receive(_ event: YouTubeHandoffPlayerEvent, id: UUID) {
        guard let context = active, context.id == id else { return }
        switch event {
        case .confirmed(let evidence):
            guard context.connection.isCurrent(), context.audio.isValid(),
                  context.player.beginMacPause(using: evidence) else { retire(context); return }
            context.commitStarted = true // A completion can arrive before the send returns.
            context.commitTask = Task { [weak self, context] in
                guard !Task.isCancelled, context.connection.isCurrent(), context.audio.isValid(),
                      context.player.isCurrent(evidence) else { self?.retireIfActive(context); return }
                do {
                    try await context.connection.commit(evidence, context.player.playbackAuthorization)
                } catch {
                    self?.retireIfActive(context)
                }
            }
        case .failed:
            retire(context) // Keep the failed sheet's honest Mac-outcome text until dismissed.
        case .movedToPhone:
            context.deadlineTask?.cancel(); context.deadlineTask = nil
        case .playRequired:
            break
        }
    }

    private func retireIfActive(_ context: Context) {
        guard active === context else { return }
        retire(context)
    }

    private func retire(_ context: Context) {
        guard active === context else { return }
        context.player.playbackAuthorization.revoke()
        active = nil; closing = context
        context.commitTask?.cancel(); context.commitTask = nil
        context.deadlineTask?.cancel(); context.deadlineTask = nil
        // Register before dismiss: no-view cleanup can acknowledge synchronously.
        context.player.afterMediaStopped { [weak self, context] in
            context.audio.release()
            if self?.closing === context { self?.closing = nil }
        }
        context.player.dismiss()
        Task {
            if context.commitStarted { await context.connection.cancel() }
            await context.connection.discard()
        }
    }
}

/// Root and full-screen surfaces register independently; only one wins the offer. SwiftUI
/// owns presentation, while the narrow representable owns the single WK provider instance.
struct YouTubeHandoffPresenter: ViewModifier {
    @ObservedObject var coordinator: YouTubeHandoffCoordinator
    let priority: Int
    @State private var presenterID = UUID()

    func body(content: Content) -> some View {
        let displayed = coordinator.presentation.flatMap { $0.presenterID == presenterID ? $0 : nil }
        content
            .onAppear { coordinator.registerPresenter(presenterID, priority: priority) }
            .onDisappear { coordinator.unregisterPresenter(presenterID) }
            .sheet(item: Binding(get: { displayed }, set: { value in
                if value == nil, let displayed { coordinator.dismiss(displayed.id) }
            }), onDismiss: {
                if let displayed { coordinator.dismiss(displayed.id) }
            }) { presentation in
                YouTubeHandoffSheet(player: presentation.player)
            }
    }
}
