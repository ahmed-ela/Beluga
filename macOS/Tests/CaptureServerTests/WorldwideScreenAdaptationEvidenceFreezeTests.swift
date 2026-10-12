import XCTest
import WebRTCTransport
@testable import CaptureServer

final class WorldwideScreenAdaptationEvidenceFreezeTests: XCTestCase {
    func testCollectionFenceUsesExactFullWidthInclusiveBoundary() {
        for minimum in [UInt64(0), 1, UInt64.max - 1, UInt64.max] {
            var actual = WorldwideScreenVideoAdaptationFreshnessFence()
            var reference = FrozenScreenAdaptationFreshnessFence()
            actual.beginPostResumeEpoch(minimumCollectionSequence: minimum)
            reference.beginPostResumeEpoch(minimumCollectionSequence: minimum)
            for sequence in [UInt64?.none, 0, 1, UInt64.max - 1, UInt64.max] {
                let expected = sequence.map { $0 >= minimum } ?? false
                XCTAssertEqual(actual.admits(.init(collectionSequence: sequence)), expected)
                XCTAssertEqual(reference.admits(sequence: sequence), expected)
            }
            XCTAssertEqual(actual.minimumCollectionSequence, minimum)
            XCTAssertEqual(reference.minimumCollectionSequence, minimum)
        }
    }

    func testCollectionFenceCannotRegressAndResetRestoresUnfencedAdmission() {
        var actual = WorldwideScreenVideoAdaptationFreshnessFence()
        var reference = FrozenScreenAdaptationFreshnessFence()
        for minimum in [UInt64.max - 1, 0, UInt64.max, 1] {
            actual.beginPostResumeEpoch(minimumCollectionSequence: minimum)
            reference.beginPostResumeEpoch(minimumCollectionSequence: minimum)
        }
        XCTAssertEqual(actual.minimumCollectionSequence, UInt64.max)
        XCTAssertEqual(reference.minimumCollectionSequence, UInt64.max)
        XCTAssertFalse(actual.admits(.init(collectionSequence: UInt64.max - 1)))
        XCTAssertFalse(reference.admits(sequence: UInt64.max - 1))
        XCTAssertTrue(actual.admits(.init(collectionSequence: UInt64.max)))
        XCTAssertTrue(reference.admits(sequence: UInt64.max))
        actual.reset(); reference.reset()
        XCTAssertNil(actual.minimumCollectionSequence)
        XCTAssertNil(reference.minimumCollectionSequence)
        XCTAssertTrue(actual.admits(.init(collectionSequence: nil)))
        XCTAssertTrue(reference.admits(sequence: nil))
    }

    func testFrozenLaneGapHasStrictTwoSecondBoundaryAndExactSignedTime() {
        let origin = ContinuousClock.now
        let attosecond = Duration(secondsComponent: 0, attosecondsComponent: 1)
        for (gap, resets) in [(Duration.seconds(2) - attosecond, 0),
                              (.seconds(2), 0),
                              (.seconds(2) + attosecond, 1),
                              (Duration.zero - attosecond, 0)] {
            var reference = FrozenScreenAdaptationEvidenceLaneReference()
            XCTAssertEqual(reference.prepare(from: .fastSender, at: origin), 0)
            let observed = origin.advanced(by: gap)
            XCTAssertEqual(origin.duration(to: observed), gap)
            XCTAssertEqual(reference.prepare(from: .fastSender, at: observed), UInt64(resets))
            XCTAssertEqual(reference.resetCount, resets)
            XCTAssertEqual(reference.lastEvidenceTime, observed)
            XCTAssertEqual(reference.lane, .fastSender)
        }
    }

    func testFrozenLaneChangeWrapsRevisionWithoutSaturatingOrMintingAnEpoch() {
        let origin = ContinuousClock.now
        var reference = FrozenScreenAdaptationEvidenceLaneReference(revision: UInt64.max)
        XCTAssertEqual(reference.prepare(from: .fastSender, at: origin), UInt64.max)
        XCTAssertEqual(reference.resetCount, 0)
        XCTAssertEqual(reference.prepare(from: .ordinaryFallback, at: origin), 0)
        XCTAssertEqual(reference.resetCount, 1)
        XCTAssertEqual(reference.prepare(from: .ordinaryFallback, at: origin.advanced(by: .seconds(3))), 1)
        XCTAssertEqual(reference.resetCount, 2)
        XCTAssertEqual(reference.lane, .ordinaryFallback)
    }

    func testFrozenFirstLaneDoesNotSpendRevisionOrResetForAFirstLateReport() {
        let origin = ContinuousClock.now
        var reference = FrozenScreenAdaptationEvidenceLaneReference(revision: 19)
        XCTAssertEqual(reference.prepare(from: .ordinaryFallback, at: origin.advanced(by: .seconds(100))), 19)
        XCTAssertEqual(reference.resetCount, 0)
        XCTAssertEqual(reference.prepare(from: .fastSender, at: origin.advanced(by: .seconds(101))), 20)
        XCTAssertEqual(reference.resetCount, 1)
    }
}
