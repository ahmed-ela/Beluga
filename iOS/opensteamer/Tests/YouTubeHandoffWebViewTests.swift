import UIKit
import WebKit
import XCTest
import Combine
@testable import WebRTCTransport
@testable import opensteamer

/// Actual WK main-frame/bridge/lifecycle integration with inert local HTML. This does not
/// claim YouTube playback, phone acoustics, offer correlation or a Mac-pause result.
@MainActor
final class YouTubeHandoffWebViewTests: XCTestCase {
    func testOwnedMainFrameCanConfirmThenDismantleRevokesAndHides() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        let request = try YouTubeHandoffRequest(operationID: UUID(), videoID: "dQw4w9WgXcQ",
            positionSeconds: 20, durationSeconds: 200, playbackRate: 1, deadlineUptime: start + 20, now: start)
        let confirmed = expectation(description: "owned local page reached native bridge")
        var evidence: YouTubePhonePlaybackEvidence?
        var events: [YouTubeHandoffPlayerEvent] = []
        let player = YouTubeHandoffPlayer(request: request, htmlDocument: Self.localDocument) { event in
            events.append(event)
            if case .confirmed(let value) = event { evidence = value; confirmed.fulfill() }
        }
        let view = player.makeWebView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(view)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.makeKeyAndVisible()
        defer { player.dismiss(); window.isHidden = true }
        player.setPresentation(isPresented: true, sceneIsActive: true)
        await fulfillment(of: [confirmed], timeout: 8)
        let proof = try XCTUnwrap(evidence, "phase=\(player.phase) events=\(events)")
        XCTAssertTrue(player.isCurrent(proof))
        player.dismantle(view)
        XCTAssertFalse(player.isCurrent(proof))
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(player.phase, .failed(.dismissed))
    }

    func testBackgroundRevokesPlayerAndCannotResumeOldOperation() async throws {
        let now = ProcessInfo.processInfo.systemUptime
        let request = try YouTubeHandoffRequest(operationID: UUID(), videoID: "dQw4w9WgXcQ",
            positionSeconds: 20, durationSeconds: 200, playbackRate: 1, deadlineUptime: now + 20, now: now)
        let player = YouTubeHandoffPlayer(request: request, htmlDocument: Self.localDocument) { _ in }
        let view = player.makeWebView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(view)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.makeKeyAndVisible()
        defer { player.dismiss(); window.isHidden = true }
        player.setPresentation(isPresented: true, sceneIsActive: true)
        player.setPresentation(isPresented: true, sceneIsActive: false)
        XCTAssertEqual(player.phase, .failed(.notVisible))
        XCTAssertTrue(view.isHidden)
        player.setPresentation(isPresented: true, sceneIsActive: true)
        XCTAssertEqual(player.phase, .failed(.notVisible))
    }

    func testSuppliedCompletionKeepsWebViewAliveForLocalPauseSeekAndRateControls() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        let request = try YouTubeHandoffRequest(operationID: UUID(), videoID: "dQw4w9WgXcQ",
            positionSeconds: 20, durationSeconds: 200, playbackRate: 1, deadlineUptime: start + 20, now: start)
        let confirmed = expectation(description: "provider double confirmed")
        let finalBridgeMessage = expectation(description: "native received the final ordered message")
        var evidence: YouTubePhonePlaybackEvidence?
        var events: [YouTubeHandoffPlayerEvent] = []
        let player = YouTubeHandoffPlayer(request: request, htmlDocument: Self.localDocument) { event in
            events.append(event)
            if case .confirmed(let value) = event { evidence = value; confirmed.fulfill() }
            if case .failed = event { finalBridgeMessage.fulfill() }
        }
        var observedPhases: [YouTubeHandoffPhase] = []
        let observation = player.$phase.sink { observedPhases.append($0) }
        defer { observation.cancel() }
        let view = player.makeWebView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(view)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.makeKeyAndVisible()
        defer { player.dismiss(); window.isHidden = true }
        player.setPresentation(isPresented: true, sceneIsActive: true)
        await fulfillment(of: [confirmed], timeout: 8)
        let proof = try XCTUnwrap(evidence)
        XCTAssertTrue(player.beginMacPause(using: proof))
        XCTAssertEqual(player.phase, .awaitingMacPause)
        // Supplied completion boundary: this is local native bridge proof, not a Mac pause.
        player.receiveMacPauseCompletion(.init(id: request.id, result: .macPaused))
        XCTAssertEqual(player.phase, .localPlayback)
        let localPhaseStart = observedPhases.count
        XCTAssertEqual(events.filter { $0 == .movedToPhone }.count, 1)
        XCTAssertFalse(player.isCurrent(proof))
        for state in [2, 1, 3, 0] {
            _ = try await view.evaluateJavaScript("emit('sample',{state:\(state),position:80,duration:200,rate:2});")
            XCTAssertFalse(view.isHidden)
            XCTAssertEqual(player.phase, .localPlayback)
            XCTAssertEqual(player.macPauseStatus, .paused)
        }
        XCTAssertEqual(events.filter { if case .confirmed = $0 { true } else { false } }.count, 1)
        XCTAssertFalse(player.beginMacPause(using: proof))
        // Drain through a final observable native transition, rather than assuming an
        // evaluateJavaScript reply proves its earlier script messages were delivered.
        _ = try await view.evaluateJavaScript("emit('sample',{video:'aaaaaaaaaaa',state:1,position:80,duration:200,rate:2});")
        await fulfillment(of: [finalBridgeMessage], timeout: 5)
        XCTAssertTrue(observedPhases.dropFirst(localPhaseStart).allSatisfy {
            $0 == .localPlayback || $0 == .failed(.wrongVideo)
        }, "Local controls must not transiently return the native player to handoff verification")
        XCTAssertEqual(events.filter { if case .failed = $0 { true } else { false } }, [.failed(.wrongVideo)])
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(player.phase, .failed(.wrongVideo))
        XCTAssertEqual(player.macPauseStatus, .paused)
        XCTAssertEqual(player.statusText, "The Mac source was paused. Playback on this iPhone has stopped.")
    }

    func testDismissAfterReservationClosesWebViewWithoutClaimingMacWasUntouched() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        let request = try YouTubeHandoffRequest(operationID: UUID(), videoID: "dQw4w9WgXcQ",
            positionSeconds: 20, durationSeconds: 200, playbackRate: 1, deadlineUptime: start + 20, now: start)
        let confirmed = expectation(description: "provider double confirmed")
        var evidence: YouTubePhonePlaybackEvidence?
        let player = YouTubeHandoffPlayer(request: request, htmlDocument: Self.localDocument) { event in
            if case .confirmed(let value) = event { evidence = value; confirmed.fulfill() }
        }
        let view = player.makeWebView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(view)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.makeKeyAndVisible()
        defer { player.dismiss(); window.isHidden = true }
        player.setPresentation(isPresented: true, sceneIsActive: true)
        await fulfillment(of: [confirmed], timeout: 8)
        XCTAssertTrue(player.beginMacPause(using: try XCTUnwrap(evidence)))
        player.dismiss()
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(player.phase, .failed(.dismissed))
        XCTAssertEqual(player.macPauseStatus, .unknown)
        player.receiveMacPauseCompletion(.init(id: request.id, result: .macPaused))
        XCTAssertEqual(player.phase, .failed(.dismissed))
        XCTAssertEqual(player.macPauseStatus, .unknown)
        XCTAssertEqual(player.statusText, "The Mac’s pause status is uncertain. Check the Mac before trying another transfer.")
    }

    static func localDocument(_ request: YouTubeHandoffRequest, _ page: UUID, _ origin: String) -> String {
        // The real owner installs the handler and validates exact navigation/frame/origin.
        // A provider double emits no ready/sample until native visibility is replayed after load.
        """
        <!doctype html><html><body><script>
        const operation='\(request.operationID.uuidString.lowercased())',page='\(page.uuidString.lowercased())',video='\(request.videoID)';
        let sent=false,sequence=0,position=20;
        window.belugaHandoffTimeline = value => {position=value;};
        function emit(kind,extra){window.webkit.messageHandlers.belugaYouTubeHandoff.postMessage(Object.assign({kind,operation,page,video,sequence:++sequence},extra||{}));}
        window.belugaHandoffVisibility = visible => {
          if (!visible || sent) return; sent=true;
          const start=position;
          emit('ready');emit('sample',{state:1,position:start,duration:200,rate:1});
          setTimeout(()=>emit('sample',{state:1,position:start+0.3,duration:200,rate:1}),300);
        };
        </script></body></html>
        """
    }
}
