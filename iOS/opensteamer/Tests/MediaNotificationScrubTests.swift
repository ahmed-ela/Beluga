import XCTest
@testable import opensteamer

final class MediaNotificationScrubTests: XCTestCase {
    private let epoch = UUID()

    func testDragOnlyProducesOneFractionalRequestOnRelease() throws {
        let initial = snapshot()
        var scrub = try XCTUnwrap(MediaNotificationScrub(snapshot: initial, contextID: "A", now: 100))
        scrub.update(position: 35.125)
        scrub.update(position: 47.625)
        XCTAssertEqual(scrub.position, 47.625)
        let refreshed = snapshot(revision: 2, published: 101)
        let request = try XCTUnwrap(scrub.finish(snapshot: refreshed, selectedContextID: "A", now: 101))
        XCTAssertEqual(request.action, .seekToPosition)
        XCTAssertEqual(request.positionSeconds, 47.625)
        XCTAssertEqual(request.expectedDurationSeconds, 300)
        XCTAssertEqual(request.contextID, "A")
        XCTAssertEqual(request.epoch, epoch)
        XCTAssertEqual(request.revision, 2)
        XCTAssertNil(scrub.finish(snapshot: refreshed, selectedContextID: "A", now: 101))
    }

    func testSourceEpochTimelineAndAuthorityChangesCancelInsteadOfRetargeting() throws {
        let changed = [snapshot(context: "B"), snapshot(epoch: UUID()), snapshot(duration: 150),
                       snapshot(capability: false), snapshot(ready: false), snapshot(position: nil)]
        for value in changed {
            var scrub = try XCTUnwrap(MediaNotificationScrub(snapshot: snapshot(), contextID: "A", now: 100))
            scrub.update(position: 90)
            XCTAssertNil(scrub.finish(snapshot: value, selectedContextID: value.entries.first?.contextID, now: 100))
        }
        var scrub = try XCTUnwrap(MediaNotificationScrub(snapshot: snapshot(), contextID: "A", now: 100))
        XCTAssertNil(scrub.finish(snapshot: snapshot(), selectedContextID: "B", now: 100))
    }

    func testExpiredOrRegressedSnapshotCannotFinishDrag() throws {
        var scrub = try XCTUnwrap(MediaNotificationScrub(snapshot: snapshot(revision: 2), contextID: "A", now: 100))
        XCTAssertNil(scrub.finish(snapshot: snapshot(), selectedContextID: "A", now: 100))
        scrub = try XCTUnwrap(MediaNotificationScrub(snapshot: snapshot(), contextID: "A", now: 100))
        XCTAssertNil(scrub.finish(snapshot: snapshot(), selectedContextID: "A", now: 106))
        XCTAssertNil(MediaNotificationScrub(snapshot: snapshot(), contextID: "A", now: 106))
    }

    func testRejectedReleaseCannotReviveAfterSameSourceRecovers() throws {
        for unavailable in [snapshot(capability: false), snapshot(duration: nil), snapshot(ready: false)] {
            var scrub = try XCTUnwrap(MediaNotificationScrub(snapshot: snapshot(), contextID: "A", now: 100))
            scrub.update(position: 75)
            XCTAssertNil(scrub.finish(snapshot: unavailable, selectedContextID: "A", now: 100))
            XCTAssertNil(scrub.finish(snapshot: snapshot(), selectedContextID: "A", now: 100))
        }
    }

    func testInvalidTimelineNeverCreatesDragAndDraftClampsWithoutNonfiniteValues() throws {
        for duration: Double? in [nil, 0, -1, .nan, .infinity, 31_536_001] {
            XCTAssertNil(MediaNotificationScrub(snapshot: snapshot(duration: duration), contextID: "A", now: 100))
        }
        for position: Double? in [nil, -1, .nan, .infinity] {
            XCTAssertNil(MediaNotificationScrub(snapshot: snapshot(position: position), contextID: "A", now: 100))
        }
        var scrub = try XCTUnwrap(MediaNotificationScrub(snapshot: snapshot(), contextID: "A", now: 100))
        scrub.update(position: -30)
        XCTAssertEqual(scrub.position, 0)
        scrub.update(position: 900)
        XCTAssertEqual(scrub.position, 300)
        scrub.update(position: .nan)
        XCTAssertEqual(scrub.position, 300)
    }

    private func snapshot(epoch: UUID? = nil, revision: UInt64 = 1, context: String = "A",
                          duration: Double? = 300, position: Double? = 20, capability: Bool = true,
                          ready: Bool = true, published: Double = 100) -> MediaNotificationSnapshot {
        .init(epoch: epoch ?? self.epoch, revision: revision, publishedAtUptime: published, ready: ready,
            entries: [.init(contextID: context, sourceName: "YouTube", title: "Test video", isPlaying: true,
                position: position, duration: duration,
                capabilities: .init(canPlay: true, canPause: true, canSeekBackward: true,
                    canSeekForward: true, canSeekToPosition: capability))])
    }
}
