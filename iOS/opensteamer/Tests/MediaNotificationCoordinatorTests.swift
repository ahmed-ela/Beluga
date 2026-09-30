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

    func testExpandedCapabilitiesPublishAndCurrentStateRejectsQueuedSeekAfterFailedPublish() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MediaNotificationStore(directoryURL: directory)
        let coordinator = MediaNotificationCoordinator(store: store,
            allowsNotificationDelivery: false, automaticallyPolls: false)
        let initial = makeState(expanded: true)
        var dispatchCount = 0
        coordinator.update(state: initial, ready: true) { _, _ in dispatchCount += 1; return true }
        let snapshot = try XCTUnwrap(store.readSnapshot())
        let capabilities = try XCTUnwrap(snapshot.entries.last?.capabilities)
        XCTAssertTrue(capabilities.canNext)
        XCTAssertTrue(capabilities.canPrevious)
        XCTAssertTrue(capabilities.canSeekToPosition)
        let request = MediaNotificationRequest(id: UUID(), epoch: snapshot.epoch, revision: snapshot.revision,
            contextID: "music", action: .seekToPosition,
            deadlineUptime: ProcessInfo.processInfo.systemUptime + 2, positionSeconds: 47.125,
            expectedDurationSeconds: 500)
        XCTAssertTrue(try store.submit(request))
        let lock = Darwin.open(directory.appendingPathComponent("mailbox.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(lock, 0)
        defer { Darwin.close(lock) }
        XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
        coordinator.update(state: makeState(revision: 2, authorization: initial.authorization,
            expanded: true, duration: 20), ready: true) { _, _ in dispatchCount += 1; return true }
        XCTAssertEqual(flock(lock, LOCK_UN), 0)
        coordinator.pollOnce()
        XCTAssertEqual(dispatchCount, 0, "A stale mailbox is never current command authority")
        XCTAssertEqual(try store.acknowledgement(for: request)?.result, .stale)
        coordinator.invalidate()
    }

    func testHeartbeatRefreshDoesNotMakeFreshSeekAppearFromFuture() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MediaNotificationStore(directoryURL: directory)
        let coordinator = MediaNotificationCoordinator(store: store,
            allowsNotificationDelivery: false, automaticallyPolls: false)
        var dispatched: [MediaNotificationRequest] = []
        coordinator.update(state: makeState(expanded: true), ready: true) { request, _ in
            dispatched.append(request)
            return true
        }
        defer { coordinator.invalidate() }
        let snapshot = try XCTUnwrap(store.readSnapshot())
        // Force pollOnce's heartbeat branch, while keeping this catalog within its five-second
        // freshness window. Give the request its full lifetime only after this wait.
        Thread.sleep(forTimeInterval: 1.05)
        let now = ProcessInfo.processInfo.systemUptime
        let request = MediaNotificationRequest(id: UUID(), epoch: snapshot.epoch,
            revision: snapshot.revision, contextID: "music", action: .seekToPosition,
            deadlineUptime: now + 2, positionSeconds: 47.125, expectedDurationSeconds: 500)
        XCTAssertTrue(try store.submit(request, now: now))
        coordinator.pollOnce()
        let refreshed = try XCTUnwrap(store.readSnapshot())
        XCTAssertGreaterThan(refreshed.publishedAtUptime, snapshot.publishedAtUptime)
        XCTAssertEqual(dispatched, [request], "A freshly published heartbeat must not be future-dated relative to its claim")
        XCTAssertEqual(try store.acknowledgement(for: request)?.result, .pending)
        coordinator.pollOnce()
        XCTAssertEqual(dispatched, [request], "A second poll must not replay the durably claimed seek")
        XCTAssertEqual(try store.acknowledgement(for: request)?.result, .pending)
    }

    func testNotificationDeadlineIsBoundedAndSurvivesGateAdmission() throws {
        let gate = RemoteMediaCommandDispatchGate()
        let owner = RemoteMediaCommandOwnerToken()
        let sent = DispatchCapture()
        gate.claim(owner: owner) { sent.append($0) }
        gate.update(owner: owner, state: makeState(expanded: true), transportIsReady: true)
        let now = ProcessInfo.processInfo.systemUptime
        for deadline in [now - 1, .nan, .infinity, now + 60] {
            XCTAssertFalse(gate.dispatch(.explicit(.nextTrack), contextID: "music", observedRevision: 1,
                deadlineUptime: deadline, completion: nil))
        }
        let deadline = now + 2
        XCTAssertTrue(gate.dispatch(.seekToPosition(47.125), contextID: "music", observedRevision: 1,
            deadlineUptime: deadline, expectedDurationSeconds: 500, completion: nil))
        let dispatch = try XCTUnwrap(sent.values.first)
        XCTAssertEqual(dispatch.deadlineUptime, deadline)
        XCTAssertEqual(dispatch.positionSeconds, 47.125)
        XCTAssertEqual(dispatch.expectedDurationSeconds, 500)
        XCTAssertFalse(gate.dispatch(.seekToPosition(47.125), contextID: "music", observedRevision: 1,
            deadlineUptime: deadline, expectedDurationSeconds: 300, completion: nil))
        XCTAssertFalse(gate.dispatch(.seekToPosition(700), contextID: "music", observedRevision: 1,
            deadlineUptime: deadline, expectedDurationSeconds: 500, completion: nil),
            "An exact notification seek must not clamp a malformed payload")
        XCTAssertTrue(dispatch.isWithinDeadline(at: now))
        XCTAssertFalse(dispatch.isWithinDeadline(at: deadline))
        XCTAssertFalse(dispatch.isWithinDeadline(at: deadline + 1))
        XCTAssertTrue(gate.dispatch(.explicit(.previousTrack), contextID: "music", observedRevision: 1, completion: nil))
        XCTAssertNil(sent.values.last?.deadlineUptime, "Native controls retain their existing lifetime")
        gate.release(owner: owner)
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

    private func makeState(revision: UInt64 = 1, authorization: WebRTCRemoteMediaAuthorization = .init(),
                           expanded: Bool = false, duration: Double = 500) -> WebRTCReceivedRemoteMediaState {
        func item(_ context: String) -> WebRTCRemoteMediaItem {
            .init(contextID: context, sourceName: context, title: "Track", playbackState: .playing,
                  elapsedTime: 120, duration: duration, playbackRate: 1,
                  capabilities: .init(canPlay: true, canPause: true, canSkipForward: expanded,
                                      canSkipBackward: expanded, canSeekForward: true, canSeekBackward: true,
                                      canSeekToPosition: expanded))
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
        XCTAssertFalse(permits(position: 300.001), "A shorter current duration must not retarget a pending seek")
        XCTAssertFalse(permits(.play))
        XCTAssertTrue(permits(.play, position: nil))
    }

    func testNotificationDeadlineExpiresAcrossQueuedProductionSend() async throws {
        let peer = try WebRTCPeer(configuration: .init(role: .viewer, iceServers: [], mediaTopology: .videoControlOnly))
        let model = WorldwideSessionViewModel()
        let current = state()
        let sent = DispatchCapture()
        model.debugInstallRemoteMediaCommandPathForTests(peer: peer, state: current) { sent.append($0) }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.05
        let dispatch = RemoteMediaCommandDispatch(command: .seekToPosition, state: current,
            authorization: WebRTCControlAuthorization(), contextID: "youtube-video",
            positionSeconds: 47.125, deadlineUptime: deadline)
        let task = try XCTUnwrap(model.debugEnqueueRemoteMediaCommandForTests(dispatch))
        // Do not yield MainActor until the captured deadline has expired. The queued task
        // cannot acquire fresh authority after this deterministic local queue boundary.
        expireDeadlineWithoutYielding(deadline)
        await task.value
        XCTAssertTrue(sent.values.isEmpty)
        XCTAssertNil(model.debugEnqueueRemoteMediaCommandForTests(dispatch))
        model.disconnect()
        _ = await peer.close()
    }

    func testCapturedDurationIsRecheckedAfterProductionActorQueue() async throws {
        let peer = try WebRTCPeer(configuration: .init(role: .viewer, iceServers: [], mediaTopology: .videoControlOnly))
        let model = WorldwideSessionViewModel()
        let sent = DispatchCapture()
        for duration in [100.0, 600.0] {
            let current = state()
            model.debugInstallRemoteMediaCommandPathForTests(peer: peer, state: current) { sent.append($0) }
            let dispatch = RemoteMediaCommandDispatch(command: .seekToPosition, state: current,
                authorization: WebRTCControlAuthorization(), contextID: "youtube-video", positionSeconds: 47.125,
                deadlineUptime: ProcessInfo.processInfo.systemUptime + 2, expectedDurationSeconds: 300)
            let task = try XCTUnwrap(model.debugEnqueueRemoteMediaCommandForTests(dispatch))
            let replacement = WebRTCReceivedRemoteMediaState(envelope: .init(authorization: current.authorization,
                update: state(revision: 2, duration: duration).update, refreshID: nil))
            model.debugInstallRemoteMediaCommandPathForTests(peer: peer, state: replacement) { sent.append($0) }
            await task.value
        }
        XCTAssertTrue(sent.values.isEmpty)
        model.disconnect()
        _ = await peer.close()
    }

    private func expireDeadlineWithoutYielding(_ deadline: TimeInterval) {
        Thread.sleep(forTimeInterval: max(0, deadline - ProcessInfo.processInfo.systemUptime) + 0.001)
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
