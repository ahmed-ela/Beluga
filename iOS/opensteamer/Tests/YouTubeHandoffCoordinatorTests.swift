import UIKit
import SwiftUI
import WebKit
import XCTest
@testable import WebRTCTransport
@testable import opensteamer

/// Real coordinator + WK bridge, with explicit audio and transport boundary doubles.
/// This does not prove YouTube network playback, a native Mac pause or acoustic output.
@MainActor
final class YouTubeHandoffCoordinatorTests: XCTestCase {
    @MainActor private final class Probe {
        var current = true
        var audioValid = true
        var invalidation: (@MainActor () -> Void)?
        var audioReleases = 0
        var commits = 0
        var cancels = 0
        var discards = 0
        var authorization: WebRTCControlAuthorization?
        var onCommit: (@MainActor () -> Void)?
        var stopAcknowledgement: (@MainActor () -> Void)?
        var onDiscard: (@MainActor () -> Void)?
        func acknowledgeStop() {
            let done = stopAcknowledgement; stopAcknowledgement = nil; done?()
        }
        var connection: YouTubeHandoffCoordinator.Connection {
            .init(isCurrent: { self.current }, acquireAudio: { invalidated in
                self.invalidation = invalidated
                return .init(isValid: { self.audioValid }, release: { self.audioReleases += 1 })
            }, commit: { _, authorization in
                self.authorization = authorization; self.commits += 1; self.onCommit?()
            }, cancel: { self.cancels += 1 }, discard: { self.discards += 1; self.onDiscard?() })
        }
    }

    private func request() throws -> YouTubeHandoffRequest {
        let now = ProcessInfo.processInfo.systemUptime
        return try .init(operationID: UUID(), videoID: "dQw4w9WgXcQ", positionSeconds: 20,
            durationSeconds: 200, playbackRate: 1, deadlineUptime: now + 30, now: now)
    }

    private func coordinator(_ probe: Probe) -> YouTubeHandoffCoordinator {
        YouTubeHandoffCoordinator(makePlayer: { request, handler in
            YouTubeHandoffPlayer(request: request,
                htmlDocument: YouTubeHandoffWebViewTests.localDocument,
                stopMedia: { _, done in probe.stopAcknowledgement = done }, eventHandler: handler)
        })
    }

    private func mount(_ player: YouTubeHandoffPlayer) -> (UIWindow, WKWebView) {
        let view = player.makeWebView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(view)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.makeKeyAndVisible()
        player.setPresentation(isPresented: true, sceneIsActive: true)
        return (window, view)
    }

    func testExactOfferDispatchesOnceAndFastCompletionKeepsLocalPlayer() async throws {
        let probe = Probe()
        let coordinator = coordinator(probe)
        // The real WK cleanup path is tested separately; this case checks the commit ordering.
        coordinator.registerPresenter(UUID(), priority: 0)
        let request = try request(), committed = expectation(description: "commit boundary")
        probe.onCommit = {
            coordinator.receiveCompletion(.init(id: request.id, result: .macPaused))
            committed.fulfill()
        }
        XCTAssertTrue(coordinator.receive(request, connection: probe.connection))
        let presentation = try XCTUnwrap(coordinator.presentation)
        let (window, view) = mount(presentation.player)
        defer { coordinator.invalidate(); probe.acknowledgeStop(); window.isHidden = true }
        await fulfillment(of: [committed], timeout: 8)
        XCTAssertEqual(probe.commits, 1)
        XCTAssertEqual(presentation.player.phase, .localPlayback)
        XCTAssertEqual(probe.audioReleases, 0)
        XCTAssertFalse(view.isHidden)
        XCTAssertFalse(try XCTUnwrap(probe.authorization).isValid)
        coordinator.receiveCompletion(.init(id: UUID(), result: .notApplied))
        XCTAssertEqual(presentation.player.phase, .localPlayback)
    }

    func testDismissRevokesImmediatelyButCannotUnmuteUntilExactStopAcknowledgement() async throws {
        let probe = Probe(), request = try request()
        let coordinator = coordinator(probe)
        coordinator.registerPresenter(UUID(), priority: 0)
        let committed = expectation(description: "commit")
        probe.onCommit = { committed.fulfill() }
        XCTAssertTrue(coordinator.receive(request, connection: probe.connection))
        let presentation = try XCTUnwrap(coordinator.presentation)
        let (window, view) = mount(presentation.player)
        defer { coordinator.invalidate(); probe.acknowledgeStop(); window.isHidden = true }
        await fulfillment(of: [committed], timeout: 8)
        let authorization = try XCTUnwrap(probe.authorization)
        coordinator.dismiss(presentation.id)
        XCTAssertFalse(authorization.isValid)
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(probe.audioReleases, 0)
        XCTAssertFalse(coordinator.receive(try self.request(), connection: probe.connection))
        coordinator.receiveCompletion(.init(id: request.id, result: .macPaused))
        XCTAssertEqual(presentation.player.macPauseStatus, .unknown)
        let done = try XCTUnwrap(probe.stopAcknowledgement)
        probe.stopAcknowledgement = nil
        done(); done()
        XCTAssertEqual(probe.audioReleases, 1)
        XCTAssertTrue(coordinator.receive(try self.request(), connection: probe.connection))
        done() // A stale WebKit callback cannot release the replacement's suppression.
        XCTAssertEqual(probe.audioReleases, 1)
        coordinator.dismiss(presentation.id) // Nor may an old sheet dismiss the new operation.
        XCTAssertNotNil(coordinator.presentation)
    }

    func testOwnerInvalidationBeforePlaybackClosesWithoutSendingPause() throws {
        let probe = Probe()
        let coordinator = coordinator(probe)
        coordinator.registerPresenter(UUID(), priority: 0)
        XCTAssertTrue(coordinator.receive(try request(), connection: probe.connection))
        let player = try XCTUnwrap(coordinator.presentation?.player)
        probe.audioValid = false; probe.invalidation?()
        XCTAssertNil(coordinator.presentation)
        XCTAssertFalse(player.playbackAuthorization.isValid)
        XCTAssertEqual(probe.commits, 0)
        XCTAssertEqual(probe.audioReleases, 1, "No WebView was created, so cleanup is synchronous")
    }

    func testPresentationSelectsTopmostOnceAndRejectsAmbiguityOrReplacement() throws {
        let probe = Probe(), root = UUID(), screen = UUID()
        let coordinator = coordinator(probe)
        coordinator.registerPresenter(root, priority: 0)
        coordinator.registerPresenter(screen, priority: 1)
        XCTAssertTrue(coordinator.receive(try request(), connection: probe.connection))
        XCTAssertEqual(coordinator.presentation?.presenterID, screen)
        XCTAssertFalse(coordinator.receive(try request(), connection: probe.connection))
        coordinator.unregisterPresenter(screen)
        XCTAssertNil(coordinator.presentation)
        XCTAssertEqual(probe.audioReleases, 1)
        coordinator.registerPresenter(UUID(), priority: 0)
        XCTAssertFalse(coordinator.receive(try request(), connection: probe.connection))
        XCTAssertEqual(probe.commits, 0)
    }

    func testNativeWebKitStopAcknowledgesBeforeReleaseAndOnlyOnce() async throws {
        let stopped = expectation(description: "native WK stop callbacks")
        let player = YouTubeHandoffPlayer(request: try request(),
            htmlDocument: YouTubeHandoffWebViewTests.localDocument) { _ in }
        let (window, view) = mount(player)
        defer { player.dismiss(); window.isHidden = true }
        var completions = 0
        player.afterMediaStopped { completions += 1; stopped.fulfill() }
        player.dismiss()
        XCTAssertTrue(view.isHidden)
        await fulfillment(of: [stopped], timeout: 8)
        player.dismiss()
        XCTAssertTrue(player.cleanupCompleted)
        XCTAssertEqual(completions, 1)
    }

    func testUnpresentedOfferTimesOutWithoutHoldingAudioForever() async throws {
        let probe = Probe()
        let coordinator = coordinator(probe)
        coordinator.registerPresenter(UUID(), priority: 0)
        let now = ProcessInfo.processInfo.systemUptime
        let request = try YouTubeHandoffRequest(operationID: UUID(), videoID: "dQw4w9WgXcQ",
            positionSeconds: 20, durationSeconds: 200, playbackRate: 1,
            deadlineUptime: now + 0.2, now: now)
        let discarded = expectation(description: "unpresented offer retired")
        probe.onDiscard = { discarded.fulfill() }
        XCTAssertTrue(coordinator.receive(request, connection: probe.connection))
        await fulfillment(of: [discarded], timeout: 2)
        XCTAssertEqual(probe.audioReleases, 1)
        XCTAssertEqual(probe.commits, 0)
        coordinator.invalidate()
    }

    func testSwiftUIPresenterActuallyMountsOnePlayerAboveRootAndFullScreen() async throws {
        for fullScreen in [false, true] {
            let probe = Probe()
            let coordinator = coordinator(probe)
            let ready = expectation(description: "presenter registered")
            let committed = expectation(description: "SwiftUI-mounted WK playback confirmation")
            let request = try request()
            probe.onCommit = {
                coordinator.receiveCompletion(.init(id: request.id, result: .macPaused))
                committed.fulfill()
            }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let root = PresenterFixture(coordinator: coordinator, fullScreen: fullScreen,
                                        ready: { ready.fulfill() })
                .environment(\.scenePhase, .active)
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            defer { coordinator.invalidate(); probe.acknowledgeStop(); window.isHidden = true }
            await fulfillment(of: [ready], timeout: 5)
            XCTAssertTrue(coordinator.receive(request, connection: probe.connection))
            await fulfillment(of: [committed], timeout: 10)
            XCTAssertEqual(probe.commits, 1)
            XCTAssertEqual(coordinator.presentation?.player.phase, .localPlayback)
            XCTAssertEqual(probe.audioReleases, 0)
        }
    }

    func testAcquisitionRevocationCannotCreateAPlayerOrLeakSuppression() throws {
        let probe = Probe(), coordinator = coordinator(Probe())
        coordinator.registerPresenter(UUID(), priority: 0)
        let connection = YouTubeHandoffCoordinator.Connection(isCurrent: { true }, acquireAudio: { invalidated in
            invalidated()
            return .init(isValid: { true }, release: { probe.audioReleases += 1 })
        }, commit: { _, _ in XCTFail("Rejected acquisition sent pause") }, cancel: {}, discard: {})
        XCTAssertFalse(coordinator.receive(try request(), connection: connection))
        XCTAssertNil(coordinator.presentation)
        XCTAssertEqual(probe.audioReleases, 1)
    }

    func testStaleConnectionAndRegressingClockCannotAcquireAudio() throws {
        let request = try request()
        for clock in [request.positionObservedAtUptime - 1, .nan, request.deadlineUptime] {
            let probe = Probe(), coordinator = YouTubeHandoffCoordinator(now: { clock })
            coordinator.registerPresenter(UUID(), priority: 0)
            XCTAssertFalse(coordinator.receive(request, connection: probe.connection))
            XCTAssertNil(probe.invalidation)
        }
        let probe = Probe(), coordinator = coordinator(Probe())
        coordinator.registerPresenter(UUID(), priority: 0); probe.current = false
        XCTAssertFalse(coordinator.receive(request, connection: probe.connection))
        XCTAssertNil(probe.invalidation)
    }

    private struct PresenterFixture: View {
        let coordinator: YouTubeHandoffCoordinator
        let fullScreen: Bool
        let ready: @MainActor () -> Void
        @State private var showsScreen = false
        var body: some View {
            Color.blue
                .modifier(YouTubeHandoffPresenter(coordinator: coordinator, priority: 0))
                .onAppear { if fullScreen { showsScreen = true } else { ready() } }
                .fullScreenCover(isPresented: $showsScreen) {
                    Color.black
                        .modifier(YouTubeHandoffPresenter(coordinator: coordinator, priority: 1))
                        .onAppear { ready() }
                }
        }
    }
}
