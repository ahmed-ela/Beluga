import SwiftUI
import UIKit
import XCTest
import WebRTCTransport
@testable import opensteamer

/// Exercises the production SwiftUI modifier and actual UIKit property in a signed Simulator.
/// This is not a physical Auto-Lock timeout or remote YouTube playback test.
@MainActor
final class ScreenVideoIdleTimerViewTests: XCTestCase {
    func testNativeIdleTimerTracksScenePlaybackHideAndViewRemoval() async throws {
        let application = UIApplication.shared
        let original = application.isIdleTimerDisabled
        let scene = try XCTUnwrap(application.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let model = Input()
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: Fixture(input: model))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
            application.isIdleTimerDisabled = original
        }

        await waitUntil { !application.isIdleTimerDisabled }
        model.playback = evidence()
        await waitUntil { application.isIdleTimerDisabled }
        model.phase = .inactive
        await waitUntil { !application.isIdleTimerDisabled }
        model.phase = .active
        await waitUntil { application.isIdleTimerDisabled }
        model.viewing = false
        await waitUntil { !application.isIdleTimerDisabled }
        model.viewing = true
        await waitUntil { application.isIdleTimerDisabled }
        model.playback = nil
        await waitUntil { !application.isIdleTimerDisabled }
        model.playback = evidence()
        await waitUntil { application.isIdleTimerDisabled }
        model.mounted = false
        await waitUntil { !application.isIdleTimerDisabled }
    }

    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath,
                           line: UInt = #line) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate(), file: file, line: line)
    }

    private func evidence() -> ScreenVideoPlaybackEvidence {
        let item = WebRTCRemoteMediaItem(contextID: "view-fixture", sourceName: "YouTube",
            title: "Video", playbackState: .playing, playbackRate: 1,
            capabilities: .init(canPlay: false, canPause: true,
                                canSkipForward: false, canSkipBackward: false),
            artwork: .init(videoID: "AAAAAAAAAAA"))
        return ScreenVideoPlaybackEvidence(update: .init(revision: 1, item: item),
            receivedAtUptime: ProcessInfo.processInfo.systemUptime)!
    }

    private final class Input: ObservableObject {
        @Published var playback: ScreenVideoPlaybackEvidence?
        @Published var phase: ScenePhase = .active
        @Published var viewing = true
        @Published var mounted = true
    }

    private struct Fixture: View {
        @ObservedObject var input: Input
        var body: some View {
            Group {
                if input.mounted {
                    Color.black.modifier(ScreenVideoIdleTimerModifier(
                        playback: input.playback, isViewingScreen: input.viewing))
                }
            }.environment(\.scenePhase, input.phase)
        }
    }
}
