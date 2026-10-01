import Foundation
import Darwin
import XCTest
@testable import opensteamer

final class MediaNotificationStoreTests: XCTestCase {
    private var directory: URL!
    private let epoch = UUID()
    private let now: Double = 100

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("media-mailbox-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    func testSnapshotFreshnessAndRevisionFence() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot())
        XCTAssertNotNil(try store.readSnapshot(now: now + 5))
        XCTAssertNil(try store.readSnapshot(now: now + 5.001))
        XCTAssertNil(try store.readSnapshot(now: now - 0.001))
        XCTAssertThrowsError(try store.publishSnapshot(snapshot(entries: [entry(playing: true)])))
        try store.publishSnapshot(snapshot(time: now + 1))
        XCTAssertNotNil(try store.readSnapshot(now: now + 6))
    }

    func testRetiredSelectionNeverFallsBackToAnotherPlayer() {
        var selection = MediaNotificationSelection()
        selection.refresh(contextIDs: ["browser", "music"])
        XCTAssertEqual(selection.contextID, "browser")
        selection.select("music", available: ["browser", "music"])
        selection.refresh(contextIDs: ["browser", "music"])
        XCTAssertEqual(selection.contextID, "music", "Ordinary seek readback retains selection")
        selection.refresh(contextIDs: ["browser", "next-music-track"])
        XCTAssertNil(selection.contextID)
        selection.refresh(contextIDs: ["browser", "next-music-track"])
        XCTAssertNil(selection.contextID, "Polling must not silently reselect primary")
        selection.select("missing", available: ["browser", "next-music-track"])
        XCTAssertNil(selection.contextID)
        selection.select("next-music-track", available: ["browser", "next-music-track"])
        XCTAssertEqual(selection.contextID, "next-music-track")
    }

    func testTwoInstancesCannotOverwriteOutstandingRequestAndClaimOnce() throws {
        let app = MediaNotificationStore(directoryURL: directory)
        let extensionStore = MediaNotificationStore(directoryURL: directory)
        try app.publishSnapshot(snapshot())
        let first = request()
        XCTAssertTrue(try extensionStore.submit(first, now: now))
        XCTAssertFalse(try extensionStore.submit(request(), now: now))
        XCTAssertEqual(try app.claimPendingRequest(epoch: epoch, now: now), first)
        XCTAssertNil(try MediaNotificationStore(directoryURL: directory).claimPendingRequest(epoch: epoch, now: now))
        XCTAssertEqual(try extensionStore.acknowledgement(for: first)?.result, .pending)
        XCTAssertTrue(try app.acknowledge(.init(id: first.id, epoch: epoch, result: .applied)))
        XCTAssertEqual(try extensionStore.acknowledgement(for: first)?.result, .applied)
    }

    func testConsumedIdentitySurvivesAcknowledgementAndMailboxReplacement() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot())
        let first = request()
        XCTAssertTrue(try store.submit(first, now: now))
        XCTAssertNotNil(try store.claimPendingRequest(epoch: epoch, now: now))
        XCTAssertTrue(try store.acknowledge(.init(id: first.id, epoch: epoch, result: .applied)))
        let second = request()
        XCTAssertTrue(try store.submit(second, now: now))
        XCTAssertNotNil(try store.claimPendingRequest(epoch: epoch, now: now))
        XCTAssertTrue(try store.acknowledge(.init(id: second.id, epoch: epoch, result: .applied)))
        XCTAssertFalse(try MediaNotificationStore(directoryURL: directory).submit(first, now: now))
        XCTAssertEqual(try store.acknowledgement(for: first)?.result, .applied)
    }

    func testExpiredClaimCannotReplayOrOverwriteNewRequestAcknowledgement() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot())
        let expired = request(deadline: now + 1)
        XCTAssertTrue(try store.submit(expired, now: now))
        XCTAssertNil(try store.claimPendingRequest(epoch: epoch, now: now + 1))
        XCTAssertEqual(try store.acknowledgement(for: expired)?.result, .expired)
        let first = request(deadline: now + 1.5)
        XCTAssertTrue(try store.submit(first, now: now + 1))
        XCTAssertNotNil(try store.claimPendingRequest(epoch: epoch, now: now + 1))
        let second = request(deadline: now + 3)
        XCTAssertTrue(try store.submit(second, now: now + 2))
        XCTAssertFalse(try store.acknowledge(.init(id: first.id, epoch: epoch, result: .applied)))
        XCTAssertEqual(try store.claimPendingRequest(epoch: epoch, now: now + 2), second)
    }

    func testEpochRotationAndUnavailableSnapshotRejectOldWork() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot())
        let command = request()
        XCTAssertTrue(try store.submit(command, now: now))
        try store.publishSnapshot(snapshot(revision: 2, ready: false, entries: []))
        XCTAssertNil(try store.claimPendingRequest(epoch: epoch, now: now))
        XCTAssertEqual(try store.acknowledgement(for: command)?.result, .stale)
        let replacement = UUID()
        try store.publishSnapshot(snapshot(epoch: replacement))
        XCTAssertFalse(try store.submit(command, now: now))
        XCTAssertNil(try store.claimPendingRequest(epoch: epoch, now: now))
        XCTAssertFalse(try store.acknowledge(.init(id: command.id, epoch: epoch, result: .applied)))
    }

    func testExactSourceRevisionAndCapabilitiesAreRequired() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot())
        XCTAssertFalse(try store.submit(request(context: "missing"), now: now))
        XCTAssertFalse(try store.submit(request(revision: 2), now: now))
        XCTAssertFalse(try store.submit(request(epoch: UUID()), now: now))
        XCTAssertFalse(try store.submit(request(action: .pause), now: now))
        XCTAssertFalse(try store.submit(request(deadline: .infinity), now: now))
        XCTAssertFalse(try store.submit(request(deadline: now + 2.001), now: now))
        XCTAssertTrue(try store.submit(request(), now: now))
        try store.publishSnapshot(snapshot(revision: 2, entries: [entry(context: "B")]))
        XCTAssertNil(try store.claimPendingRequest(epoch: epoch, now: now))
    }

    func testLegacyCapabilitiesAndRequestsDecodeWithNewAuthorityDisabled() throws {
        let legacy = Data(#"{"canPlay":true,"canPause":false,"canSeekBackward":true,"canSeekForward":true}"#.utf8)
        let decoded = try JSONDecoder().decode(MediaNotificationCapabilities.self, from: legacy)
        XCTAssertFalse(decoded.canNext)
        XCTAssertFalse(decoded.canPrevious)
        XCTAssertFalse(decoded.canSeekToPosition)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request())) as? [String: Any])
        object.removeValue(forKey: "positionSeconds")
        let oldRequest = try JSONDecoder().decode(MediaNotificationRequest.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(oldRequest.positionSeconds)
        XCTAssertNil(oldRequest.expectedDurationSeconds)
        XCTAssertTrue(oldRequest.isValid(at: now))
        object["action"] = "unknown-action"
        XCTAssertThrowsError(try JSONDecoder().decode(MediaNotificationRequest.self,
            from: JSONSerialization.data(withJSONObject: object)))
        let malformed = Data(#"{"canPlay":true,"canPause":false,"canSeekBackward":true,"canSeekForward":true,"canNext":"true"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MediaNotificationCapabilities.self, from: malformed))
    }

    func testAbsoluteSeekRequiresBoundedPayloadAndCurrentTimeline() {
        let current = snapshot(entries: [entry(expanded: true)])
        for position: Double? in [nil, .nan, .infinity, -.infinity, -1, 31_536_001, 900.001] {
            XCTAssertFalse(request(action: .seekToPosition, position: position).isAdmitted(by: current, at: now))
        }
        for position in [0.0, 47.125, 900] {
            XCTAssertTrue(request(action: .seekToPosition, position: position).isAdmitted(by: current, at: now))
        }
        for action in [MediaNotificationAction.play, .pause, .nextTrack, .previousTrack, .seekBackward30, .seekForward30] {
            XCTAssertFalse(request(action: action, position: 47.125).isValid(at: now))
        }
        let seek = request(action: .seekToPosition, position: 47.125)
        for duration: Double? in [nil, 0, 20] {
            XCTAssertFalse(seek.isAdmitted(by: snapshot(entries: [entry(expanded: true, duration: duration)]), at: now))
        }
        XCTAssertFalse(seek.isAdmitted(by: snapshot(entries: [entry(expanded: true, position: nil)]), at: now))
        XCTAssertFalse(seek.isAdmitted(by: snapshot(), at: now))
        for expectedDuration: Double? in [nil, .nan, .infinity, 0, -1, 31_536_001] {
            let malformed = MediaNotificationRequest(id: UUID(), epoch: epoch, revision: 1, contextID: "A",
                action: .seekToPosition, deadlineUptime: now + 2, positionSeconds: 47.125,
                expectedDurationSeconds: expectedDuration)
            XCTAssertFalse(malformed.isValid(at: now))
        }
    }

    func testTrackAndAbsoluteSeekCommandsRemainAtMostOnceAcrossMailboxInstances() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot(entries: [entry(expanded: true)]))
        for action in [MediaNotificationAction.nextTrack, .previousTrack, .seekToPosition] {
            let command = request(action: action, position: action == .seekToPosition ? 47.125 : nil)
            XCTAssertTrue(try store.submit(command, now: now))
            XCTAssertEqual(try store.claimPendingRequest(epoch: epoch, now: now), command)
            XCTAssertNil(try MediaNotificationStore(directoryURL: directory).claimPendingRequest(epoch: epoch, now: now))
            XCTAssertTrue(try store.acknowledge(.init(id: command.id, epoch: epoch, result: .applied)))
            XCTAssertFalse(try store.submit(command, now: now))
        }
    }

    func testQueuedSeekRevalidatesTimelineAndCapabilitiesAtClaim() throws {
        for replacement in [entry(expanded: true, duration: 600), entry(expanded: true, duration: 1_000),
                            entry(expanded: true, duration: 20), entry(), entry(context: "retired", expanded: true)] {
            let store = MediaNotificationStore(directoryURL: directory)
            let testEpoch = UUID()
            try store.publishSnapshot(snapshot(epoch: testEpoch, entries: [entry(expanded: true)]))
            let command = request(epoch: testEpoch, action: .seekToPosition, position: 47.125)
            XCTAssertTrue(try store.submit(command, now: now))
            try store.publishSnapshot(snapshot(epoch: testEpoch, revision: 2, entries: [replacement]))
            XCTAssertNil(try store.claimPendingRequest(epoch: testEpoch, now: now))
            XCTAssertEqual(try store.acknowledgement(for: command)?.result, .stale)
        }
    }

    func testExtensionReadReceiptContainsOnlyBoundedPrivacyReducedFields() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        let receipt = readReceipt()
        XCTAssertTrue(try store.recordExtensionReadReceipt(receipt))
        XCTAssertEqual(try store.readExtensionReadReceipt(), receipt)
        let file = directory.appendingPathComponent("extension-read.json")
        let data = try Data(contentsOf: file)
        XCTAssertLessThan(data.count, MediaNotificationStore.maximumExtensionReceiptBytes)
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let value = try XCTUnwrap(record["value"] as? [String: Any])
        XCTAssertEqual(Set(value.keys), Set(["epoch", "revision", "itemCount", "playingMask",
                                            "readStatus", "selectedItemIndex", "sampledAtUptime"]))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("contextID"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("title"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("URL"))
    }

    func testExtensionReadReceiptThrottlesHeartbeatButRecordsSemanticTransitions() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        XCTAssertTrue(try store.recordExtensionReadReceipt(readReceipt()))
        XCTAssertFalse(try store.recordExtensionReadReceipt(readReceipt(time: now + 0.2)))
        XCTAssertEqual(try store.readExtensionReadReceipt()?.sampledAtUptime, now)
        XCTAssertTrue(try store.recordExtensionReadReceipt(readReceipt(time: now + 1)))
        XCTAssertTrue(try store.recordExtensionReadReceipt(readReceipt(mask: 0, time: now + 1.1)))
        XCTAssertTrue(try store.recordExtensionReadReceipt(readReceipt(revision: 2, mask: 0, time: now + 1.2)))
        XCTAssertTrue(try store.recordExtensionReadReceipt(readReceipt(revision: 2, mask: 0, index: 0, time: now + 1.3)))
        let busy = readReceipt(revision: nil, count: 0, mask: 0, status: .busy, index: nil, time: now + 1.4)
        XCTAssertTrue(try store.recordExtensionReadReceipt(busy))
        XCTAssertFalse(try store.recordExtensionReadReceipt(readReceipt(revision: nil, count: 0, mask: 0,
            status: .busy, index: nil, time: now + 1.5)))
        XCTAssertEqual(try store.readExtensionReadReceipt(), busy)
    }

    func testExtensionReadReceiptCannotAlterSnapshotOrCommandAdmission() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        let initial = snapshot()
        try store.publishSnapshot(initial)
        let command = request()
        XCTAssertTrue(try store.submit(command, now: now))
        let unrelated = MediaNotificationExtensionReadReceipt(epoch: UUID(), revision: 99,
            itemCount: 2, playingMask: 3, readStatus: .current, selectedItemIndex: 1, sampledAtUptime: now)
        XCTAssertTrue(try store.recordExtensionReadReceipt(unrelated))
        XCTAssertEqual(try store.readSnapshot(now: now), initial)
        XCTAssertEqual(try store.claimPendingRequest(epoch: epoch, now: now), command)
        XCTAssertEqual(try store.acknowledgement(for: command)?.result, .pending)
    }

    func testInvalidAndOversizedExtensionReadReceiptsFailClosed() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        let invalid = [readReceipt(revision: 0), readReceipt(count: 3), readReceipt(mask: 4),
            readReceipt(index: 2), readReceipt(time: .nan), readReceipt(time: -1),
            readReceipt(status: .failed), readReceipt(revision: nil), readReceipt(count: 0, mask: 0, index: nil)]
        for receipt in invalid {
            XCTAssertFalse(receipt.isValid)
            XCTAssertThrowsError(try store.recordExtensionReadReceipt(receipt))
        }
        XCTAssertTrue(try store.recordExtensionReadReceipt(readReceipt()))
        try Data(repeating: 65, count: MediaNotificationStore.maximumExtensionReceiptBytes + 1)
            .write(to: directory.appendingPathComponent("extension-read.json"))
        XCTAssertThrowsError(try store.readExtensionReadReceipt())
    }

    func testExtensionReceiptReadAndWriteReturnBusyWithoutBlockingAuthoritativeMailbox() async throws {
        let store = MediaNotificationStore(directoryURL: directory)
        let receipt = readReceipt()
        XCTAssertTrue(try store.recordExtensionReadReceipt(receipt))
        let descriptor = Darwin.open(directory.appendingPathComponent("diagnostics.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        let returned = expectation(description: "receipt operations return while owner still holds lock")
        let worker = Task.detached {
            var writeWasBusy = false
            var readWasBusy = false
            do { _ = try store.recordExtensionReadReceipt(receipt) }
            catch MediaNotificationStore.StoreError.busy { writeWasBusy = true }
            catch { }
            do { _ = try store.readExtensionReadReceipt() }
            catch MediaNotificationStore.StoreError.busy { readWasBusy = true }
            catch { }
            returned.fulfill()
            return writeWasBusy && readWasBusy
        }
        await fulfillment(of: [returned], timeout: 1)
        try store.publishSnapshot(snapshot())
        XCTAssertTrue(try store.submit(request(), now: now))
        // Drain even if an accidental blocking-lock mutation caused the expectation to fail.
        XCTAssertEqual(flock(descriptor, LOCK_UN), 0)
        let bothWereBusy = await worker.value
        XCTAssertTrue(bothWereBusy)
        XCTAssertEqual(try store.readExtensionReadReceipt(), receipt)
    }

    func testNonblockingLockRefusesConcurrentOwner() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot())
        let descriptor = Darwin.open(store.directoryURL.appendingPathComponent("mailbox.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try MediaNotificationStore(directoryURL: directory).submit(request(), now: now)) { error in
            guard case MediaNotificationStore.StoreError.busy = error else { return XCTFail("Expected busy lock") }
        }
    }

    func testElapsedTimeRevisionAdvanceDoesNotInvalidateAnAbsoluteIntent() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot())
        let command = request()
        XCTAssertTrue(try store.submit(command, now: now))
        let updated = MediaNotificationEntry(contextID: "A", sourceName: "Player", title: "Track",
            isPlaying: false, position: 121, duration: 900,
            capabilities: entry().capabilities)
        try store.publishSnapshot(snapshot(revision: 2, entries: [updated]))
        XCTAssertEqual(try store.claimPendingRequest(epoch: epoch, now: now), command)
        XCTAssertTrue(try store.acknowledge(.init(id: command.id, epoch: epoch, result: .applied)))
        XCTAssertTrue(try store.submit(request(), now: now), "Older observation may target the same current context")
        try store.publishSnapshot(snapshot(revision: 3, entries: [entry(context: "B")]))
        XCTAssertNil(try store.claimPendingRequest(epoch: epoch, now: now), "A changed source is never a fallback")
    }

    func testOversizedMalformedAndLinkedFilesFailClosed() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot())
        let file = store.directoryURL.appendingPathComponent("snapshot.json")
        try Data(repeating: 65, count: MediaNotificationStore.maximumFileBytes + 1).write(to: file)
        XCTAssertThrowsError(try store.readSnapshot(now: now))
        try Data("{}".utf8).write(to: file)
        XCTAssertThrowsError(try store.readSnapshot(now: now))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: store.directoryURL.appendingPathComponent("journal.json"))
        XCTAssertThrowsError(try store.readSnapshot(now: now))
    }

    func testInvalidSnapshotsNeverPublish() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        XCTAssertThrowsError(try store.publishSnapshot(snapshot(entries: [entry(), entry()])))
        XCTAssertThrowsError(try store.publishSnapshot(snapshot(entries: [entry(context: "A"), entry(context: "B"), entry(context: "C")])))
        XCTAssertThrowsError(try store.publishSnapshot(snapshot(entries: [])))
        XCTAssertThrowsError(try store.publishSnapshot(snapshot(revision: 0)))
        XCTAssertThrowsError(try store.publishSnapshot(snapshot(time: .nan)))
        XCTAssertThrowsError(try store.publishSnapshot(snapshot(entries: [entry(context: String(repeating: "x", count: 129))])))
    }

    func testBoundedConsumedHistoryFailsClosedUntilNewEpoch() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot())
        let acknowledgements = (0..<MediaNotificationStore.maximumConsumedRequests).map { _ in
            ["id": UUID().uuidString, "epoch": epoch.uuidString, "result": "applied"]
        }
        let journal: [String: Any] = ["version": 1, "value": ["epoch": epoch.uuidString, "acknowledgements": acknowledgements]]
        try JSONSerialization.data(withJSONObject: journal).write(to: store.directoryURL.appendingPathComponent("journal.json"))
        XCTAssertThrowsError(try store.submit(request(), now: now)) { error in
            guard case MediaNotificationStore.StoreError.capacity = error else { return XCTFail("Expected bounded history") }
        }
        XCTAssertTrue(try store.needsIdleEpochRotation(epoch: epoch, now: now))
        let next = UUID()
        try store.publishSnapshot(snapshot(epoch: next))
        XCTAssertTrue(try store.submit(request(epoch: next), now: now))
    }

    func testFullJournalWaitsForTheLastCommandWindowBeforeEpochRotation() throws {
        let store = MediaNotificationStore(directoryURL: directory)
        try store.publishSnapshot(snapshot())
        let command = request()
        XCTAssertTrue(try store.submit(command, now: now))
        let acknowledgements = (0..<MediaNotificationStore.maximumConsumedRequests).map { index in
            ["id": index == 0 ? command.id.uuidString : UUID().uuidString,
             "epoch": epoch.uuidString, "result": index == 0 ? "pending" : "applied"]
        }
        let journal: [String: Any] = ["version": 1, "value": ["epoch": epoch.uuidString, "acknowledgements": acknowledgements]]
        try JSONSerialization.data(withJSONObject: journal).write(to: directory.appendingPathComponent("journal.json"))
        XCTAssertFalse(try store.needsIdleEpochRotation(epoch: epoch, now: now + 4.999))
        XCTAssertTrue(try store.needsIdleEpochRotation(epoch: epoch, now: now + 5))
        XCTAssertFalse(try store.needsIdleEpochRotation(epoch: UUID(), now: now + 5))
    }

    func testConcurrentExtensionsProduceOnlyOneMailboxWinner() throws {
        let first = MediaNotificationStore(directoryURL: directory)
        let second = MediaNotificationStore(directoryURL: directory)
        try first.publishSnapshot(snapshot())
        let requests = [request(), request()]
        let stores = [first, second]
        let results = SubmissionResults()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            results.record((try? stores[index].submit(requests[index], now: 100)) == true)
        }
        XCTAssertEqual(results.accepted, 1)
        XCTAssertNotNil(try first.claimPendingRequest(epoch: epoch, now: now))
        XCTAssertNil(try second.claimPendingRequest(epoch: epoch, now: now))
    }

    private func readReceipt(revision: UInt64? = 1, count: UInt8 = 2, mask: UInt8 = 1,
                             status: MediaNotificationExtensionReadReceipt.ReadStatus = .current,
                             index: UInt8? = 1, time: Double? = nil) -> MediaNotificationExtensionReadReceipt {
        .init(epoch: epoch, revision: revision, itemCount: count, playingMask: mask,
              readStatus: status, selectedItemIndex: index, sampledAtUptime: time ?? now)
    }

    private func entry(context: String = "A", playing: Bool = false, expanded: Bool = false,
                       position: Double? = 120, duration: Double? = 900) -> MediaNotificationEntry {
        .init(contextID: context, sourceName: "Player", title: "Track", isPlaying: playing,
              position: position, duration: duration,
              capabilities: .init(canPlay: !playing, canPause: playing, canSeekBackward: true, canSeekForward: true,
                                  canNext: expanded, canPrevious: expanded, canSeekToPosition: expanded))
    }

    private func snapshot(epoch: UUID? = nil, revision: UInt64 = 1, time: Double? = nil,
                          ready: Bool = true, entries: [MediaNotificationEntry]? = nil) -> MediaNotificationSnapshot {
        .init(epoch: epoch ?? self.epoch, revision: revision, publishedAtUptime: time ?? now,
              ready: ready, entries: entries ?? [entry()])
    }

    private func request(epoch: UUID? = nil, revision: UInt64 = 1, context: String = "A",
                         action: MediaNotificationAction = .seekForward30, deadline: Double? = nil,
                         position: Double? = nil) -> MediaNotificationRequest {
        .init(id: UUID(), epoch: epoch ?? self.epoch, revision: revision, contextID: context,
              action: action, deadlineUptime: deadline ?? now + 2, positionSeconds: position,
              expectedDurationSeconds: action == .seekToPosition ? 900 : nil)
    }
}

private final class SubmissionResults: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var accepted: Int { lock.withLock { count } }
    func record(_ accepted: Bool) { lock.withLock { if accepted { count += 1 } } }
}
