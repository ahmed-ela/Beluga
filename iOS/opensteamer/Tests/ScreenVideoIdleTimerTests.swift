import Foundation
import XCTest
@testable import opensteamer
@testable import WebRTCTransport

/// Policy and scheduled-expiry proof, not physical Auto-Lock or Lock Screen pixel proof.
@MainActor
final class ScreenVideoIdleTimerTests: XCTestCase {
    func testPrimaryPlayingYouTubeHasExactlyFifteenSecondEvidence() throws {
        XCTAssertEqual(ScreenVideoPlaybackEvidence.maximumAge, 15)
        let proof = try XCTUnwrap(ScreenVideoPlaybackEvidence(update: update(), receivedAtUptime: 100))
        XCTAssertEqual(proof.expiresAtUptime, 115)
        XCTAssertNotNil(ScreenVideoPlaybackEvidence(update: update(), receivedAtUptime: 0))
    }

    func testSecondaryYouTubeCannotKeepPrimaryMusicOrAbsentItemAwake() {
        let video = item(context: "secondary-video")
        let music = item(context: "primary-music", source: "Apple Music", artwork: false)
        XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(primary: music, additional: [video]), receivedAtUptime: 100))
        XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(primary: nil), receivedAtUptime: 100))
        XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(primary: nil, additional: [video]), receivedAtUptime: 100))
    }

    func testPlayingPrimaryYouTubeRemainsEligibleWithValidSecondaryAudio() {
        let music = item(context: "music", source: "Apple Music", artwork: false)
        XCTAssertNotNil(ScreenVideoPlaybackEvidence(update: update(additional: [music]), receivedAtUptime: 100))
    }

    func testPauseStopZeroRateAndInvalidRatesNeverProduceEvidence() {
        for state in [WebRTCRemoteMediaPlaybackState.paused, .stopped] {
            XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(primary: item(state: state)), receivedAtUptime: 100))
        }
        for rate in [0.0, -1, .nan, .infinity, -.infinity, 16.01] {
            XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(primary: item(rate: rate)), receivedAtUptime: 100))
        }
        for rate in [0.001, 1, 2, 16] {
            XCTAssertNotNil(ScreenVideoPlaybackEvidence(update: update(primary: item(rate: rate)), receivedAtUptime: 100))
        }
    }

    func testOnlyExactYouTubeVideoClassificationQualifies() {
        for source in ["YouTube Music", "Apple Music", "Music", "Spotify", "Chrome", "youtube", "YouTube "] {
            XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(primary: item(source: source)), receivedAtUptime: 100))
        }
        XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(primary: item(artwork: false)), receivedAtUptime: 100))
    }

    func testWholeUpdateAndPrimaryMetadataMustBeValid() {
        let invalidItems = [
            item(context: ""), item(context: "bad\ncontext"), item(title: ""),
            item(title: String(repeating: "x", count: WebRTCRemoteMediaItem.maximumTitleBytes + 1)),
            item(elapsed: -1), item(duration: .nan)
        ]
        for invalid in invalidItems {
            XCTAssertFalse(invalid.isValid)
            XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(primary: invalid), receivedAtUptime: 100))
        }
        XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(revision: 0), receivedAtUptime: 100))
        XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(additional: [item(context: "primary")]), receivedAtUptime: 100))
        XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(additional: [item(context: "a"), item(context: "b")]), receivedAtUptime: 100))
        XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(additional: [item(context: "invalid", title: "")]), receivedAtUptime: 100))
    }

    func testInvalidReceiptTimesNeverProduceEvidence() {
        for time in [-1.0, .nan, .infinity, -.infinity] {
            XCTAssertNil(ScreenVideoPlaybackEvidence(update: update(), receivedAtUptime: time))
        }
    }

    func testNoPlaybackNeverWritesOrChangesIdleTimer() {
        let f = Fixture(), owner = UUID()
        f.timer.update(owner: owner, playback: nil, isViewingScreen: true, sceneIsActive: true)
        f.timer.update(owner: owner, playback: nil, isViewingScreen: false, sceneIsActive: false)
        f.timer.remove(owner: owner)
        XCTAssertEqual(f.writes, [])
    }

    func testScreenViewingAndActiveSceneAreBothRequired() throws {
        for viewing in [false, true] {
            for active in [false, true] {
                let f = Fixture(), owner = UUID(), proof = try evidence(received: 100)
                defer { f.timer.remove(owner: owner) }
                f.timer.update(owner: owner, playback: proof, isViewingScreen: viewing, sceneIsActive: active)
                XCTAssertEqual(f.writes, viewing && active ? [true] : [])
            }
        }
    }

    func testAudioOnlyOrHiddenScreenDoesNotPreventSleep() throws {
        let f = Fixture(), owner = UUID(), proof = try evidence(received: 100)
        f.timer.update(owner: owner, playback: proof, isViewingScreen: false, sceneIsActive: true)
        XCTAssertEqual(f.writes, [])
        f.timer.update(owner: owner, playback: proof, isViewingScreen: true, sceneIsActive: true)
        XCTAssertEqual(f.writes, [true])
        f.timer.update(owner: owner, playback: proof, isViewingScreen: false, sceneIsActive: true)
        XCTAssertEqual(f.writes, [true, false])
    }

    func testInactiveSceneAndNilPlaybackReleaseImmediately() throws {
        let f = Fixture(), owner = UUID(), proof = try evidence(received: 100)
        f.timer.update(owner: owner, playback: proof, isViewingScreen: true, sceneIsActive: true)
        f.timer.update(owner: owner, playback: proof, isViewingScreen: true, sceneIsActive: false)
        XCTAssertEqual(f.writes, [true, false])
        f.timer.update(owner: owner, playback: proof, isViewingScreen: true, sceneIsActive: true)
        f.timer.update(owner: owner, playback: nil, isViewingScreen: true, sceneIsActive: true)
        XCTAssertEqual(f.writes, [true, false, true, false])
    }

    func testPausedOrStoppedObservationReleasesPriorPlayingEvidence() throws {
        for state in [WebRTCRemoteMediaPlaybackState.paused, .stopped] {
            let f = Fixture(), owner = UUID(), playing = try evidence(received: 100)
            f.timer.update(owner: owner, playback: playing, isViewingScreen: true, sceneIsActive: true)
            let notPlaying = ScreenVideoPlaybackEvidence(update: update(primary: item(state: state)), receivedAtUptime: 100)
            XCTAssertNil(notPlaying)
            f.timer.update(owner: owner, playback: notPlaying, isViewingScreen: true, sceneIsActive: true)
            XCTAssertEqual(f.writes, [true, false])
        }
    }

    func testExclusiveFreshnessBoundaryAndFutureEvidenceRefusal() throws {
        let f = Fixture(), owner = UUID()
        f.timer.update(owner: owner, playback: try evidence(received: 85), isViewingScreen: true, sceneIsActive: true)
        f.timer.update(owner: owner, playback: try evidence(received: 84.99), isViewingScreen: true, sceneIsActive: true)
        f.timer.update(owner: owner, playback: try evidence(received: 100.01), isViewingScreen: true, sceneIsActive: true)
        XCTAssertEqual(f.writes, [])
        let fresh = try evidence(received: 85.01)
        f.timer.update(owner: owner, playback: fresh, isViewingScreen: true, sceneIsActive: true)
        XCTAssertEqual(f.writes, [true])
        f.now = fresh.expiresAtUptime
        f.timer.expire(owner: owner, deadline: fresh.expiresAtUptime)
        XCTAssertEqual(f.writes, [true, false])
    }

    func testInvalidClockCannotAcquireOrRetainCurrentOwnerLease() throws {
        for time in [-1.0, .nan, .infinity, -.infinity] {
            let f = Fixture(), owner = UUID(), proof = try evidence(received: 100)
            f.timer.update(owner: owner, playback: proof, isViewingScreen: true, sceneIsActive: true)
            f.now = time
            f.timer.update(owner: owner, playback: proof, isViewingScreen: true, sceneIsActive: true)
            XCTAssertEqual(f.writes, [true, false])
        }
    }

    func testRepeatedEvidenceAndRepeatedRemovalOnlyWriteEffectiveTransitions() throws {
        let f = Fixture(), owner = UUID(), proof = try evidence(received: 100)
        for _ in 0..<100 {
            f.timer.update(owner: owner, playback: proof, isViewingScreen: true, sceneIsActive: true)
        }
        XCTAssertEqual(f.writes, [true])
        for _ in 0..<100 { f.timer.remove(owner: owner) }
        XCTAssertEqual(f.writes, [true, false])
    }

    func testOverlappingOwnersReleaseOnlyAfterLastPresentationEnds() throws {
        let f = Fixture(), old = UUID(), replacement = UUID(), proof = try evidence(received: 100)
        f.timer.update(owner: old, playback: proof, isViewingScreen: true, sceneIsActive: true)
        f.timer.update(owner: replacement, playback: proof, isViewingScreen: true, sceneIsActive: true)
        XCTAssertEqual(f.writes, [true])
        f.timer.remove(owner: old); f.timer.remove(owner: UUID())
        XCTAssertEqual(f.writes, [true], "Old presentation disappearance cannot re-enable sleep under its replacement")
        f.timer.remove(owner: replacement)
        XCTAssertEqual(f.writes, [true, false])
    }

    func testForeignOrRemovedOwnerExpiryCannotReleaseSuccessor() throws {
        let f = Fixture(), old = UUID(), replacement = UUID(), proof = try evidence(received: 100)
        f.timer.update(owner: old, playback: proof, isViewingScreen: true, sceneIsActive: true)
        f.timer.update(owner: replacement, playback: proof, isViewingScreen: true, sceneIsActive: true)
        f.timer.remove(owner: old); f.now = proof.expiresAtUptime
        f.timer.expire(owner: old, deadline: proof.expiresAtUptime)
        f.timer.expire(owner: UUID(), deadline: proof.expiresAtUptime)
        XCTAssertEqual(f.writes, [true])
        f.timer.expire(owner: replacement, deadline: proof.expiresAtUptime)
        XCTAssertEqual(f.writes, [true, false])
    }

    func testOldDeadlineCannotRevokeRefreshedSameOwner() throws {
        let f = Fixture(), owner = UUID(), old = try evidence(received: 100)
        f.timer.update(owner: owner, playback: old, isViewingScreen: true, sceneIsActive: true)
        f.now = 101
        let fresh = try evidence(received: 101)
        f.timer.update(owner: owner, playback: fresh, isViewingScreen: true, sceneIsActive: true)
        f.now = old.expiresAtUptime
        f.timer.expire(owner: owner, deadline: old.expiresAtUptime)
        XCTAssertEqual(f.writes, [true])
        f.now = fresh.expiresAtUptime
        f.timer.expire(owner: owner, deadline: fresh.expiresAtUptime)
        XCTAssertEqual(f.writes, [true, false])
    }

    func testExpiryBeforeExactDeadlineIsNonAuthorizing() throws {
        let f = Fixture(), owner = UUID(), proof = try evidence(received: 100)
        f.timer.update(owner: owner, playback: proof, isViewingScreen: true, sceneIsActive: true)
        f.now = proof.expiresAtUptime - 0.001
        f.timer.expire(owner: owner, deadline: proof.expiresAtUptime)
        XCTAssertEqual(f.writes, [true])
        f.now = proof.expiresAtUptime
        f.timer.expire(owner: owner, deadline: proof.expiresAtUptime)
        f.timer.expire(owner: owner, deadline: proof.expiresAtUptime)
        XCTAssertEqual(f.writes, [true, false])
    }

    func testRenewedEvidenceDoesNotCauseExtraWritesAcrossOwnerExpiry() throws {
        let f = Fixture(), first = UUID(), second = UUID(), old = try evidence(received: 100)
        f.timer.update(owner: first, playback: old, isViewingScreen: true, sceneIsActive: true)
        f.now = 101
        let fresh = try evidence(received: 101)
        f.timer.update(owner: second, playback: fresh, isViewingScreen: true, sceneIsActive: true)
        f.now = old.expiresAtUptime
        f.timer.expire(owner: first, deadline: old.expiresAtUptime)
        XCTAssertEqual(f.writes, [true])
        f.now = fresh.expiresAtUptime
        f.timer.expire(owner: second, deadline: fresh.expiresAtUptime)
        XCTAssertEqual(f.writes, [true, false])
    }

    func testRealScheduledExpiryReleasesWithoutFurtherMediaUpdate() async throws {
        let expired = expectation(description: "The production expiry task releases the idle timer")
        expired.assertForOverFulfill = true
        var writes: [Bool] = []
        let timer = ScreenVideoIdleTimer { disabled in
            writes.append(disabled)
            if !disabled { expired.fulfill() }
        }
        let owner = UUID()
        defer { timer.remove(owner: owner) }
        let now = ProcessInfo.processInfo.systemUptime
        let nearExpiry = try evidence(received: now - ScreenVideoPlaybackEvidence.maximumAge + 0.25)
        timer.update(owner: owner, playback: nearExpiry, isViewingScreen: true, sceneIsActive: true)
        XCTAssertEqual(writes, [true])
        await fulfillment(of: [expired], timeout: 3)
        XCTAssertEqual(writes, [true, false])
    }

    private func evidence(received: TimeInterval) throws -> ScreenVideoPlaybackEvidence {
        try XCTUnwrap(ScreenVideoPlaybackEvidence(update: update(), receivedAtUptime: received))
    }

    private func update(revision: UInt64 = 1,
                        additional: [WebRTCRemoteMediaItem] = []) -> WebRTCRemoteMediaStateUpdate {
        update(revision: revision, primary: item(), additional: additional)
    }

    private func update(revision: UInt64 = 1, primary: WebRTCRemoteMediaItem?,
                        additional: [WebRTCRemoteMediaItem] = []) -> WebRTCRemoteMediaStateUpdate {
        WebRTCRemoteMediaStateUpdate(revision: revision, item: primary, additionalItems: additional)
    }

    private func item(context: String = "primary", source: String = "YouTube", title: String = "Test video",
                      state: WebRTCRemoteMediaPlaybackState = .playing, rate: Double = 1,
                      elapsed: TimeInterval? = 12, duration: TimeInterval? = 300,
                      artwork: Bool = true) -> WebRTCRemoteMediaItem {
        WebRTCRemoteMediaItem(contextID: context, sourceName: source, title: title,
            playbackState: state, elapsedTime: elapsed, duration: duration, playbackRate: rate,
            capabilities: .init(canPlay: true, canPause: true, canSkipForward: true, canSkipBackward: true),
            artwork: artwork ? WebRTCRemoteMediaArtworkReference(videoID: "aaaaaaaaaaa") : nil)
    }

    @MainActor
    private final class Fixture {
        var now: TimeInterval = 100
        var writes: [Bool] = []
        var timer: ScreenVideoIdleTimer!
        init() {
            timer = ScreenVideoIdleTimer(now: { [unowned self] in self.now },
                                         setDisabled: { [unowned self] in self.writes.append($0) })
        }
    }
}
