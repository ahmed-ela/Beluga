import Foundation
import Darwin
import XCTest
import UserNotifications
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
