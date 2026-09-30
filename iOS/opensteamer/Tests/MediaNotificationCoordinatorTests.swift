import Foundation
import Darwin
import XCTest
import UserNotifications
import MediaPlayer
@testable import opensteamer
@testable import WebRTCTransport

@MainActor
final class MediaNotificationCoordinatorTests: XCTestCase {
    func testReplacementDeliveryNeedsForegroundOnlyForNewPermission() {
        for active in [false, true] {
            for status in [UNAuthorizationStatus.authorized, .provisional, .ephemeral] {
                XCTAssertEqual(MediaNotificationCoordinator.deliveryPolicy(status: status, applicationIsActive: active), .deliver)
            }
            XCTAssertEqual(MediaNotificationCoordinator.deliveryPolicy(status: .denied, applicationIsActive: active), .unavailable)
        }
        XCTAssertEqual(MediaNotificationCoordinator.deliveryPolicy(status: .notDetermined, applicationIsActive: false), .waitForForeground)
        XCTAssertEqual(MediaNotificationCoordinator.deliveryPolicy(status: .notDetermined, applicationIsActive: true), .requestPermission)
    }
    func testInstalledApplicationHasItsIsolatedSharedContainerConfiguration() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "BelugaMediaAppGroup") as? String,
                       "group.org.example.AudioStreamer.dev.media")
        let store = try XCTUnwrap(MediaNotificationStore.configured())
        XCTAssertEqual(store.directoryURL.lastPathComponent, "MediaControls-v1")
    }

    func testSecondarySourceReachesGateAndOnlyHostAcknowledgementReportsApplied() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appStore = MediaNotificationStore(directoryURL: directory)
        let extensionStore = MediaNotificationStore(directoryURL: directory)
        let coordinator = MediaNotificationCoordinator(store: appStore,
            allowsNotificationDelivery: false, automaticallyPolls: false)
        let gate = RemoteMediaCommandDispatchGate()
        let owner = RemoteMediaCommandOwnerToken()
        let sent = DispatchCapture()
        gate.claim(owner: owner) { sent.append($0) }
        let state = makeState()
        gate.update(owner: owner, state: state, transportIsReady: true)
        coordinator.update(state: state, ready: true) { request, completion in
            gate.dispatch(.explicit(.seekForward30), contextID: request.contextID,
                          observedRevision: request.revision, completion: completion)
        }
        let snapshot = try XCTUnwrap(extensionStore.readSnapshot())
        XCTAssertEqual(snapshot.entries.map(\.contextID), ["browser", "music"])
        let request = makeRequest(snapshot)
        XCTAssertTrue(try extensionStore.submit(request))
        coordinator.pollOnce()
        coordinator.pollOnce()
        XCTAssertEqual(sent.values.count, 1)
        let command = try XCTUnwrap(sent.values.first)
        XCTAssertEqual(command.contextID, "music")
        XCTAssertEqual(command.command, .seekForward30)
        XCTAssertEqual(command.state.update.item?.contextID, "browser", "Selection must not replace native Now Playing")
        XCTAssertEqual(try extensionStore.acknowledgement(for: request)?.result, .pending)
        let lock = Darwin.open(appStore.directoryURL.appendingPathComponent("mailbox.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(lock, 0)
        defer { Darwin.close(lock) }
        XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
        command.completion?(.applied)
        command.completion?(.failed)
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(flock(lock, LOCK_UN), 0)
        XCTAssertEqual(try extensionStore.acknowledgement(for: request)?.result, .pending)
        coordinator.pollOnce()
        XCTAssertEqual(try extensionStore.acknowledgement(for: request)?.result, .applied)
        XCTAssertEqual(sent.values.count, 1, "Retrying an acknowledgement must never resend the seek")
        XCTAssertEqual(try extensionStore.readSnapshot()?.entries.first?.position, 120,
                       "Command success must not invent a newer playback state")
        coordinator.invalidate()
    }

    func testRecoveryInvalidatesCardAndLateAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MediaNotificationStore(directoryURL: directory)
        let coordinator = MediaNotificationCoordinator(store: store,
            allowsNotificationDelivery: false, automaticallyPolls: false)
        var completion: (@Sendable (WebRTCRemoteMediaCommandResult) -> Void)?
        coordinator.update(state: makeState(), ready: true) { _, callback in completion = callback; return true }
        let initial = try XCTUnwrap(store.readSnapshot())
        let request = makeRequest(initial)
        XCTAssertTrue(try store.submit(request))
        coordinator.pollOnce()
        coordinator.update(state: nil, ready: false) { _, _ in XCTFail("Retired owner dispatched"); return false }
        completion?(.applied)
        await Task.yield()
        XCTAssertFalse(try XCTUnwrap(store.readSnapshot()).ready)
        XCTAssertNil(try store.acknowledgement(for: request))
        coordinator.update(state: makeState(), ready: true) { _, _ in false }
        let replacement = try XCTUnwrap(store.readSnapshot())
        XCTAssertNotEqual(initial.epoch, replacement.epoch)
        XCTAssertFalse(try store.submit(request))
        coordinator.invalidate()
    }

    func testExplicitUnknownContextNeverFallsBackToPrimaryAndFutureRevisionIsRejected() {
        let gate = RemoteMediaCommandDispatchGate()
        let owner = RemoteMediaCommandOwnerToken()
        let sent = DispatchCapture()
        gate.claim(owner: owner) { sent.append($0) }
        let state = makeState()
        gate.update(owner: owner, state: state, transportIsReady: true)
        XCTAssertFalse(gate.dispatch(.explicit(.pause), contextID: "missing", observedRevision: 1, completion: nil))
        XCTAssertFalse(gate.dispatch(.explicit(.pause), contextID: "music", observedRevision: 2, completion: nil))
        XCTAssertTrue(RemoteMediaCommandAdmission.permits(.pause, contextID: "music",
                                                        observedRevision: 1, currentUpdate: state.update))
        XCTAssertTrue(gate.dispatch(.explicit(.pause), contextID: "music", observedRevision: 1, completion: nil))
        XCTAssertEqual(sent.values.map(\.contextID), ["music"])
        gate.update(owner: owner, state: makeState(revision: 2, authorization: state.authorization), transportIsReady: true)
        XCTAssertTrue(gate.dispatch(.explicit(.seekForward30), contextID: "music", observedRevision: 1, completion: nil))
        XCTAssertFalse(gate.dispatch(.explicit(.seekForward30), contextID: "music", observedRevision: 0, completion: nil))
        gate.release(owner: owner)
        XCTAssertFalse(sent.values[0].authorization.isValid)
    }

    func testFullJournalGetsFreshEpochWithoutReplacingLiveSessionOwner() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MediaNotificationStore(directoryURL: directory)
        let coordinator = MediaNotificationCoordinator(store: store, allowsNotificationDelivery: false, automaticallyPolls: false)
        var dispatched = 0
        coordinator.update(state: makeState(), ready: true) { _, _ in dispatched += 1; return true }
        let first = try XCTUnwrap(store.readSnapshot())
        let acknowledgements = (0..<MediaNotificationStore.maximumConsumedRequests).map { _ in
            ["id": UUID().uuidString, "epoch": first.epoch.uuidString, "result": "applied"]
        }
        let journal: [String: Any] = ["version": 1, "value": ["epoch": first.epoch.uuidString, "acknowledgements": acknowledgements]]
        try JSONSerialization.data(withJSONObject: journal).write(to: directory.appendingPathComponent("journal.json"))
        coordinator.pollOnce()
        let replacement = try XCTUnwrap(store.readSnapshot())
        XCTAssertNotEqual(first.epoch, replacement.epoch)
        XCTAssertEqual(first.entries, replacement.entries)
        XCTAssertFalse(try store.submit(makeRequest(first)))
        XCTAssertTrue(try store.submit(makeRequest(replacement)))
        coordinator.pollOnce()
        XCTAssertEqual(dispatched, 1)
        coordinator.invalidate()
    }

    private func makeState(revision: UInt64 = 1, authorization: WebRTCRemoteMediaAuthorization = .init()) -> WebRTCReceivedRemoteMediaState {
        func item(_ context: String) -> WebRTCRemoteMediaItem {
            .init(contextID: context, sourceName: context, title: "Track", playbackState: .playing,
                  elapsedTime: 120, duration: 500, playbackRate: 1,
                  capabilities: .init(canPlay: true, canPause: true, canSkipForward: false,
                                      canSkipBackward: false, canSeekForward: true, canSeekBackward: true))
        }
        return .init(envelope: .init(authorization: authorization,
            update: .init(revision: revision, item: item("browser"), additionalItems: [item("music")]), refreshID: nil))
    }

    private func makeRequest(_ snapshot: MediaNotificationSnapshot) -> MediaNotificationRequest {
        .init(id: UUID(), epoch: snapshot.epoch, revision: snapshot.revision, contextID: "music",
              action: .seekForward30, deadlineUptime: ProcessInfo.processInfo.systemUptime + 2)
    }
}

private final class DispatchCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [RemoteMediaCommandDispatch] = []
    var values: [RemoteMediaCommandDispatch] { lock.withLock { captured } }
    func append(_ value: RemoteMediaCommandDispatch) { lock.withLock { captured.append(value) } }
}

@MainActor
final class NativeMediaSeekingTests: XCTestCase {
    func testSeekCapturesExactPositionContextAndNegotiation() throws {
        let gate = RemoteMediaCommandDispatchGate()
        let owner = RemoteMediaCommandOwnerToken()
        let sent = DispatchCapture()
        gate.claim(owner: owner) { sent.append($0) }
        let initial = state()
        gate.update(owner: owner, state: initial, transportIsReady: true)
        XCTAssertTrue(gate.dispatch(.seekToPosition(47.125)))
        let command = try XCTUnwrap(sent.values.first)
        XCTAssertEqual(command.command, .seekToPosition)
        XCTAssertEqual(command.positionSeconds, 47.125)
        XCTAssertEqual(command.contextID, "youtube-video")
        XCTAssertTrue(command.state.isSameNegotiation(as: initial))
        XCTAssertTrue(gate.dispatch(.seekToPosition(0)))
        XCTAssertTrue(gate.dispatch(.seekToPosition(600)))
        XCTAssertEqual(sent.values.map(\.positionSeconds), [47.125, 0, 300])
        gate.update(owner: owner, state: state(context: "next-video"), transportIsReady: true)
        XCTAssertFalse(command.authorization.isValid)
        gate.release(owner: owner)
    }

    func testMalformedOrUnavailableSeekNeverDispatches() {
        let gate = RemoteMediaCommandDispatchGate()
        let owner = RemoteMediaCommandOwnerToken()
        let sent = DispatchCapture()
        gate.claim(owner: owner) { sent.append($0) }
        gate.update(owner: owner, state: state(), transportIsReady: true)
        for position in [Double.nan, .infinity, -.infinity, -1, 31_536_001] {
            XCTAssertFalse(gate.dispatch(.seekToPosition(position)))
        }
        XCTAssertFalse(gate.dispatch(WebRTCRemoteMediaCommand.seekToPosition))
        for duration: Double? in [nil, 0, -1, .infinity, .nan] {
            gate.update(owner: owner, state: state(duration: duration), transportIsReady: true)
            XCTAssertFalse(gate.dispatch(.seekToPosition(30)))
        }
        gate.update(owner: owner, state: state(capability: false), transportIsReady: true)
        XCTAssertFalse(gate.dispatch(.seekToPosition(30)))
        gate.update(owner: owner, state: state(elapsed: nil), transportIsReady: true)
        XCTAssertFalse(gate.dispatch(.seekToPosition(30)))
        gate.update(owner: owner, state: state(), transportIsReady: false)
        XCTAssertFalse(gate.dispatch(.seekToPosition(30)))
        gate.release(owner: owner)
        XCTAssertFalse(gate.dispatch(.seekToPosition(30)))
        XCTAssertTrue(sent.values.isEmpty)
    }

    func testNativeScrubberTracksCapabilityTimelineAndTransport() {
        let coordinator = BackgroundPlaybackCoordinator.shared
        let owner = coordinator.claimRemoteMediaCommandSender { _ in }
        let center = MPRemoteCommandCenter.shared()
        defer { coordinator.releaseRemoteMediaCommandSender(owner: owner); coordinator.clear() }
        XCTAssertTrue(coordinator.debugHasNativeCommandTarget(center.changePlaybackPositionCommand))
        XCTAssertFalse(center.changePlaybackPositionCommand.isEnabled)
        coordinator.publishRemoteMedia(state(), owner: owner)
        coordinator.setRemoteMediaTransportReady(true, owner: owner)
        XCTAssertTrue(center.changePlaybackPositionCommand.isEnabled)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] as? Double, 300)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 20)
        XCTAssertTrue(center.skipBackwardCommand.isEnabled)
        XCTAssertTrue(center.skipForwardCommand.isEnabled)
        coordinator.setRemoteMediaTransportReady(false, owner: owner)
        XCTAssertFalse(center.changePlaybackPositionCommand.isEnabled)
        coordinator.setRemoteMediaTransportReady(true, owner: owner)
        coordinator.publishRemoteMedia(state(revision: 2, duration: nil), owner: owner)
        XCTAssertFalse(center.changePlaybackPositionCommand.isEnabled)
        coordinator.publishRemoteMedia(state(revision: 3, capability: false), owner: owner)
        XCTAssertFalse(center.changePlaybackPositionCommand.isEnabled)
    }

    func testAbsolutePositionSurvivesProductionViewModelSendBoundary() async throws {
        let peer = try WebRTCPeer(configuration: .init(role: .viewer, iceServers: [], mediaTopology: .videoControlOnly))
        let model = WorldwideSessionViewModel()
        let current = state()
        let sent = DispatchCapture()
        model.debugInstallRemoteMediaCommandPathForTests(peer: peer, state: current) { sent.append($0) }
        let dispatch = RemoteMediaCommandDispatch(command: .seekToPosition, state: current,
            authorization: WebRTCControlAuthorization(), contextID: "youtube-video", positionSeconds: 47.125)
        let task = try XCTUnwrap(model.debugEnqueueRemoteMediaCommandForTests(dispatch))
        await task.value
        XCTAssertEqual(sent.values.map(\.positionSeconds), [47.125])
        XCTAssertNil(model.debugEnqueueRemoteMediaCommandForTests(.init(command: .seekToPosition,
            state: current, authorization: WebRTCControlAuthorization(), positionSeconds: nil)))
        XCTAssertNil(model.debugEnqueueRemoteMediaCommandForTests(.init(command: .pause,
            state: current, authorization: WebRTCControlAuthorization(), positionSeconds: 20)))
        model.disconnect()
        _ = await peer.close()
    }

    func testAdmissionRejectsStaleContextAndMalformedPayload() {
        let current = state().update
        func permits(_ command: WebRTCRemoteMediaCommand = .seekToPosition,
                     context: String = "youtube-video", revision: UInt64 = 1, position: Double? = 47.125) -> Bool {
            RemoteMediaCommandAdmission.permits(command, contextID: context, observedRevision: revision,
                                                currentUpdate: current, positionSeconds: position)
        }
        XCTAssertTrue(permits())
        XCTAssertFalse(permits(context: "retired-video"))
        XCTAssertFalse(permits(revision: 0))
        XCTAssertFalse(permits(revision: 2))
        XCTAssertFalse(permits(position: nil))
        XCTAssertFalse(permits(position: .nan))
        XCTAssertFalse(permits(.play))
        XCTAssertTrue(permits(.play, position: nil))
    }

    private func state(context: String = "youtube-video", revision: UInt64 = 1,
                       duration: Double? = 300, capability: Bool = true,
                       elapsed: Double? = 20) -> WebRTCReceivedRemoteMediaState {
        .init(envelope: .init(authorization: .init(), update: .init(revision: revision,
            item: .init(contextID: context, sourceName: "YouTube", title: "Video", playbackState: .playing,
                elapsedTime: elapsed, duration: duration, playbackRate: 1,
                capabilities: .init(canPlay: true, canPause: true, canSkipForward: true,
                    canSkipBackward: true, canSeekForward: true, canSeekBackward: true,
                    canSeekToPosition: capability))), refreshID: nil))
    }
}
