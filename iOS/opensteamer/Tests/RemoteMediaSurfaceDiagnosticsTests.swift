import Foundation
@preconcurrency import MediaPlayer
import XCTest
@testable import opensteamer
@testable import WebRTCTransport

@MainActor
final class RemoteMediaSurfaceDiagnosticsTests: XCTestCase {
    func testSameItemPauseReadsActualNativeRateWithoutChangingLocalPlaybackIntent() throws {
        try withCoordinator { coordinator, owner in
            let negotiation = WebRTCRemoteMediaAuthorization()
            coordinator.setRemoteMediaTransportReady(true, owner: owner)
            coordinator.publishRemoteMedia(state(revision: 11, playing: true, negotiation: negotiation), owner: owner)
            let playing = try XCTUnwrap(coordinator.mediaSurfaceDiagnostics(owner: owner).nativeMetadata)
            XCTAssertEqual(playing.expectedRevision, 11)
            XCTAssertEqual(playing.expectedState, .playing)
            XCTAssertEqual(playing.playbackRate, .positive)
            XCTAssertEqual(playing.currentItemMatches, true)
            XCTAssertEqual(playing.enabledCommandMask, 63)

            coordinator.publishRemoteMedia(state(revision: 16, playing: false, negotiation: negotiation), owner: owner)
            coordinator.publishLiveStream(serverName: "private host", isPlaying: true)
            let paused = coordinator.mediaSurfaceDiagnostics(owner: owner)
            XCTAssertEqual(paused.nativeMetadata?.expectedRevision, 16)
            XCTAssertEqual(paused.nativeMetadata?.expectedState, .paused)
            XCTAssertEqual(paused.nativeMetadata?.playbackRate, .zero)
            XCTAssertEqual(paused.nativeMetadata?.currentItemMatches, true)
            XCTAssertEqual(paused.nativeMetadata?.enabledCommandMask, 63)
            XCTAssertTrue(paused.isValid)
            XCTAssertNil(paused.lastControl)
        }
    }

    func testNativeRateReadbackReportsActualMissingPositiveAndMalformedValues() throws {
        try withCoordinator { coordinator, owner in
            coordinator.setRemoteMediaTransportReady(true, owner: owner)
            coordinator.publishRemoteMedia(state(playing: false), owner: owner)
            let center = MPNowPlayingInfoCenter.default()
            let values: [(Any?, WebRTCRemoteMediaSurfaceDiagnostics.PlaybackRate)] = [
                (nil, .absent), (NSNumber(value: 0), .zero), (NSNumber(value: 1), .positive),
                (NSNumber(value: 16), .positive), (NSNumber(value: -1), .invalid),
                (NSNumber(value: 17), .invalid), (NSNumber(value: Double.nan), .invalid),
                (NSNumber(value: Double.infinity), .invalid), ("1", .invalid),
                (NSNumber(value: true), .invalid)
            ]
            for (value, expected) in values {
                var info: [String: Any] = [MPNowPlayingInfoPropertyExternalContentIdentifier: "private-context"]
                info[MPNowPlayingInfoPropertyPlaybackRate] = value
                center.nowPlayingInfo = info
                let observed = coordinator.mediaSurfaceDiagnostics(owner: owner)
                XCTAssertEqual(observed.nativeMetadata?.playbackRate, expected)
                XCTAssertEqual(observed.nativeMetadata?.expectedState, .paused,
                               "Readback must not replace the authoritative Mac state")
                XCTAssertTrue(observed.isValid)
            }
            center.nowPlayingInfo = nil
            let missing = try XCTUnwrap(coordinator.mediaSurfaceDiagnostics(owner: owner).nativeMetadata)
            XCTAssertFalse(missing.metadataPresent)
            XCTAssertEqual(missing.currentItemMatches, false)
            XCTAssertEqual(missing.playbackRate, .absent)
        }
    }

    func testNativeMetadataMismatchAndPrivacyUseOnlyReducedObservations() throws {
        try withCoordinator { coordinator, owner in
            coordinator.setRemoteMediaTransportReady(true, owner: owner)
            coordinator.publishRemoteMedia(state(playing: false), owner: owner)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPNowPlayingInfoPropertyExternalContentIdentifier: "different-private-context",
                MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: 1),
                MPMediaItemPropertyTitle: "private-title",
                MPMediaItemPropertyArtist: "private-artist"
            ]
            let observed = coordinator.mediaSurfaceDiagnostics(owner: owner)
            XCTAssertEqual(observed.nativeMetadata?.currentItemMatches, false)
            XCTAssertEqual(observed.nativeMetadata?.playbackRate, .positive)
            let encoded = String(decoding: try JSONEncoder().encode(observed), as: UTF8.self)
            for forbidden in ["private-context", "private-title", "private-artist", "https://", "contextID", "title"] {
                XCTAssertFalse(encoded.contains(forbidden))
            }
            XCTAssertEqual(try JSONDecoder().decode(WebRTCRemoteMediaSurfaceDiagnostics.self,
                                                    from: Data(encoded.utf8)), observed)
        }
    }

    func testUncertaintyAndOwnerReplacementRetireExpectedNativeRevision() throws {
        try withCoordinator { coordinator, owner in
            coordinator.setRemoteMediaTransportReady(true, owner: owner)
            coordinator.publishRemoteMedia(state(revision: 7), owner: owner)
            coordinator.setRemoteMediaTransportReady(false, owner: owner)
            let uncertain = try XCTUnwrap(coordinator.mediaSurfaceDiagnostics(owner: owner).nativeMetadata)
            XCTAssertNil(uncertain.expectedRevision)
            XCTAssertNil(uncertain.expectedState)
            XCTAssertNil(uncertain.currentItemMatches)
            XCTAssertEqual(uncertain.enabledCommandMask, 0)
            XCTAssertNil(coordinator.mediaSurfaceDiagnostics(owner: owner).lastControl)
            let replacement = coordinator.claimRemoteMediaCommandSender { _ in }
            defer { coordinator.releaseRemoteMediaCommandSender(owner: replacement) }
            XCTAssertEqual(coordinator.mediaSurfaceDiagnostics(owner: owner), .init())
            XCTAssertEqual(coordinator.mediaSurfaceDiagnostics(owner: nil), .init())
            let current = coordinator.mediaSurfaceDiagnostics(owner: replacement)
            XCTAssertNil(current.nativeMetadata?.expectedRevision)
            XCTAssertNil(current.lastControl)
            XCTAssertTrue(current.isValid)
        }
    }

    func testControlObservationLabelsOriginsAndRecordsRejectionsWithoutDispatch() throws {
        let gate = RemoteMediaCommandDispatchGate()
        let owner = RemoteMediaCommandOwnerToken()
        let recorder = SurfaceDispatchRecorder()
        gate.claim(owner: owner) { recorder.append($0) }
        XCTAssertTrue(gate.update(owner: owner, state: state(revision: 4), transportIsReady: true))
        XCTAssertTrue(gate.dispatch(.pause))
        XCTAssertEqual(gate.controlObservation(owner: owner, now: 0), .init(sequence: 1, origin: .unspecified,
                                                                    revision: 4, admitted: true))
        XCTAssertTrue(gate.dispatch(.explicit(.pause), origin: .nativeCommandCenter))
        XCTAssertEqual(gate.controlObservation(owner: owner, now: 0), .init(sequence: 2, origin: .nativeCommandCenter,
                                                                    revision: 4, admitted: true))
        XCTAssertFalse(gate.dispatch(.seekToPosition(-1), contextID: "private-context", observedRevision: 4,
                                    completion: nil, origin: .customNotification))
        XCTAssertEqual(gate.controlObservation(owner: owner, now: 0), .init(sequence: 3, origin: .customNotification,
                                                                    revision: 4, admitted: false))
        XCTAssertEqual(recorder.values.count, 2)
        XCTAssertEqual(recorder.values.map(\.command), [.pause, .pause])
        XCTAssertTrue(try XCTUnwrap(gate.controlObservation(owner: owner)).isValid)
    }

    func testControlObservationResetsAtExistingAuthorityRetirementBoundaries() throws {
        let gate = RemoteMediaCommandDispatchGate()
        let owner = RemoteMediaCommandOwnerToken()
        let recorder = SurfaceDispatchRecorder()
        let first = state()
        gate.claim(owner: owner) { recorder.append($0) }
        gate.update(owner: owner, state: first, transportIsReady: true)
        XCTAssertTrue(gate.dispatch(.explicit(.pause), origin: .nativeCommandCenter))
        let originalAuthorization = try XCTUnwrap(recorder.values.last).authorization
        gate.update(owner: owner, state: first, transportIsReady: false)
        XCTAssertNil(gate.controlObservation(owner: owner))
        XCTAssertFalse(originalAuthorization.isValid)
        XCTAssertFalse(gate.dispatch(.explicit(.pause), origin: .nativeCommandCenter))
        XCTAssertEqual(gate.controlObservation(owner: owner)?.sequence, 1)
        XCTAssertEqual(gate.controlObservation(owner: owner)?.admitted, false)
        gate.update(owner: owner, state: first, transportIsReady: true)
        XCTAssertTrue(gate.dispatch(.explicit(.pause), origin: .customNotification))
        let beforeNegotiationChange = try XCTUnwrap(recorder.values.last).authorization
        gate.update(owner: owner, state: state(revision: 2), transportIsReady: true)
        XCTAssertNil(gate.controlObservation(owner: owner))
        XCTAssertFalse(beforeNegotiationChange.isValid)
        XCTAssertTrue(gate.dispatch(.pause))
        let replacement = RemoteMediaCommandOwnerToken()
        gate.claim(owner: replacement) { recorder.append($0) }
        XCTAssertNil(gate.controlObservation(owner: owner))
        XCTAssertNil(gate.controlObservation(owner: replacement))
        XCTAssertFalse(gate.dispatch(.pause))
        XCTAssertEqual(gate.controlObservation(owner: replacement)?.admitted, false)
        XCTAssertNil(gate.controlObservation(owner: replacement)?.revision)
        XCTAssertTrue(gate.release(owner: replacement))
        XCTAssertNil(gate.controlObservation(owner: replacement))
    }

    func testControlObservationKeepsOnlyLatestAttemptAndSenderRunsOutsideGateLock() {
        let gate = RemoteMediaCommandDispatchGate()
        let owner = RemoteMediaCommandOwnerToken()
        let recorder = SurfaceDispatchRecorder()
        gate.claim(owner: owner) { dispatch in
            XCTAssertEqual(gate.controlObservation(owner: owner)?.admitted, true)
            recorder.append(dispatch)
        }
        gate.update(owner: owner, state: state(revision: 9), transportIsReady: true)
        for _ in 0..<100 { XCTAssertTrue(gate.dispatch(.explicit(.pause), origin: .nativeCommandCenter)) }
        XCTAssertEqual(gate.controlObservation(owner: owner, now: 0), .init(sequence: 100, origin: .nativeCommandCenter,
                                                                    revision: 9, admitted: true))
        XCTAssertEqual(recorder.values.count, 100)
        XCTAssertTrue(recorder.values.allSatisfy { $0.authorization.isValid && $0.state.update.revision == 9 })
    }

    func testControlObservationAgeUsesAttemptTimeWithoutRenewalAndBoundsUnknownOrFutureSamples() throws {
        let gate = RemoteMediaCommandDispatchGate(observationNow: { 100 })
        let owner = RemoteMediaCommandOwnerToken()
        gate.claim(owner: owner) { _ in }
        gate.update(owner: owner, state: state(), transportIsReady: true)
        XCTAssertTrue(gate.dispatch(.explicit(.pause), origin: .nativeCommandCenter))
        XCTAssertEqual(gate.controlObservation(owner: owner, now: 100)?.ageMilliseconds, 0)
        XCTAssertEqual(gate.controlObservation(owner: owner, now: 103.25)?.ageMilliseconds, 3_250)
        XCTAssertEqual(gate.controlObservation(owner: owner, now: 104)?.ageMilliseconds, 4_000)
        XCTAssertNil(gate.controlObservation(owner: owner, now: 99)?.ageMilliseconds)
        XCTAssertNil(gate.controlObservation(owner: owner, now: .nan)?.ageMilliseconds)
        XCTAssertEqual(gate.controlObservation(owner: owner, now: 100 + 100_000)?.ageMilliseconds, 86_400_000)
        let malformed = RemoteMediaCommandDispatchGate(observationNow: { .nan })
        malformed.claim(owner: owner) { _ in }
        malformed.update(owner: owner, state: state(), transportIsReady: true)
        XCTAssertTrue(malformed.dispatch(.pause))
        XCTAssertNil(malformed.controlObservation(owner: owner, now: 100)?.ageMilliseconds)
    }

    private func state(revision: UInt64 = 1, playing: Bool = true,
                       negotiation: WebRTCRemoteMediaAuthorization = .init()) -> WebRTCReceivedRemoteMediaState {
        let item = WebRTCRemoteMediaItem(contextID: "private-context", sourceName: "YouTube", title: "private-title",
            playbackState: playing ? .playing : .paused, elapsedTime: 12, duration: 120,
            playbackRate: playing ? 1 : 0,
            capabilities: .init(canPlay: true, canPause: true, canSkipForward: true, canSkipBackward: true,
                                canSeekForward: true, canSeekBackward: true, canSeekToPosition: true))
        return .init(envelope: .init(authorization: negotiation, update: .init(revision: revision, item: item)))
    }

    private func withCoordinator(_ body: (BackgroundPlaybackCoordinator, RemoteMediaCommandOwnerToken) throws -> Void) rethrows {
        let center = MPNowPlayingInfoCenter.default()
        let savedInfo = center.nowPlayingInfo
        let savedState = center.playbackState
        let commands = MPRemoteCommandCenter.shared()
        let nativeCommands: [MPRemoteCommand] = [commands.playCommand, commands.pauseCommand,
            commands.togglePlayPauseCommand, commands.skipBackwardCommand, commands.skipForwardCommand,
            commands.changePlaybackPositionCommand, commands.nextTrackCommand, commands.previousTrackCommand]
        let savedEnabled = nativeCommands.map(\.isEnabled)
        let coordinator = BackgroundPlaybackCoordinator(installNativeCommandTargets: false)
        let owner = coordinator.claimRemoteMediaCommandSender { _ in }
        defer {
            coordinator.releaseRemoteMediaCommandSender(owner: owner)
            coordinator.clear()
            center.nowPlayingInfo = savedInfo
            center.playbackState = savedState
            for (command, enabled) in zip(nativeCommands, savedEnabled) { command.isEnabled = enabled }
        }
        try body(coordinator, owner)
    }
}

private final class SurfaceDispatchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [RemoteMediaCommandDispatch] = []
    var values: [RemoteMediaCommandDispatch] { lock.withLock { recorded } }
    func append(_ dispatch: RemoteMediaCommandDispatch) { lock.withLock { recorded.append(dispatch) } }
}
