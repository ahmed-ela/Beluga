import Combine
import UIKit
import WebKit
import XCTest
@testable import opensteamer

/// Opt-in external-provider playback probe, intentionally separate from deterministic CI.
/// No fake HTML, injected playback event, Mac completion, peer, or native audio policy.
/// A pass means exact advancing provider playback; it is not acoustic or Mac-handoff proof.
@MainActor
final class YouTubeHandoffProviderProbeTests: XCTestCase {
    func testActualYouTubeEmbedConfirmsAdvancingPlaybackInDevelopmentSimulator() async throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["OPENSTEAMER_LIVE_YOUTUBE_PROBE"] == "1" else {
            throw XCTSkip("Explicit opt-in required for the live external-provider probe")
        }
        let now = ProcessInfo.processInfo.systemUptime
        let request = try YouTubeHandoffRequest(operationID: UUID(), videoID: "M7lc1UVf-VE",
            // The public YouTube API documentation demo: 22:24 as observed in the real player.
            // A changed duration must fail this explicit probe, not broaden the product tolerance.
            positionSeconds: 20, durationSeconds: 1344, playbackRate: 1,
            deadlineUptime: now + 30, now: now)
        var events: [YouTubeHandoffPlayerEvent] = []
        var phases: [YouTubeHandoffPhase] = []
        let player = YouTubeHandoffPlayer(request: request) { events.append($0) }
        let observation = player.$phase.sink { phases.append($0) }
        let webView = player.makeWebView()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { player.dismiss(); observation.cancel(); window.isHidden = true }
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(webView)
        webView.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.makeKeyAndVisible()
        player.setPresentation(isPresented: true, sceneIsActive: true)
        // No peer/commit callback is installed. Even real confirmation cannot pause a Mac.
        for _ in 0..<150 {
            if player.phase == .confirmed { break }
            if phases.contains(where: { if case .failed = $0 { true } else { false } }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let proof = events.compactMap { event -> YouTubePhonePlaybackEvidence? in
            if case .confirmed(let value) = event { return value }; return nil
        }.first
        XCTAssertEqual(player.phase, .confirmed)
        XCTAssertTrue(proof.map { player.isCurrent($0) } ?? false)
        XCTAssertEqual(proof?.videoID, request.videoID)
        let page = try? await webView.evaluateJavaScript("JSON.stringify({visibility:document.visibilityState,ready:document.readyState,frames:Array.from(document.querySelectorAll('iframe')).map(f=>({src:f.src,bounds:f.getBoundingClientRect().toJSON()}))})")
        let diagnostic = "phase=\(player.phase) events=\(events) observedPhases=\(Array(Set(phases.map { String(describing: $0) })).sorted()) scene=\(scene.activationState.rawValue) page=\(String(describing: page))"
        let attachment = XCTAttachment(string: diagnostic)
        attachment.name = "actual-provider-playback"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let image = try? await webView.takeSnapshot(configuration: nil) {
            let screenshot = XCTAttachment(image: image)
            screenshot.name = "actual-provider-visible-webview"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertFalse(phases.contains(where: { if case .failed = $0 { true } else { false } }), diagnostic)
        XCTAssertFalse(events.contains(.movedToPhone))
        var stopped = false
        player.afterMediaStopped { stopped = true }
        player.dismiss()
        for _ in 0..<50 {
            if stopped { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        observation.cancel()
        window.isHidden = true
        XCTAssertTrue(stopped, "Actual WebKit stop must acknowledge before the probe leaves")
        #else
        throw XCTSkip("This probe is development-Simulator-only")
        #endif
    }
}
