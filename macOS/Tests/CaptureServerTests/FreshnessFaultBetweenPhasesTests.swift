import BelugaCore
import XCTest
@testable import CaptureServer

#if DEBUG

/// Additional copied-only regression; the frozen V2 eight-method file is unchanged.
extension BelugaRustMicrophoneForwardingEvidenceTests {
    func testFaultBetweenFreshnessPhasesRefusesBeforeProducer() throws {
        var freshnessCalls = 0
        var readinessCalls = 0
        var bridge = BelugaRustMicrophoneForwardingEvidence(mutations: .init(
            readiness: { _, actual in
                readinessCalls += 1
                var corrupted = actual
                corrupted.status = 0
                return corrupted
            },
            freshness: { _, _, actual in
                freshnessCalls += 1
                return actual
            }
        ))
        let plan = try bridge.planFreshness(advancementCount: 1,
            consecutiveStaleSamples: 0, maximumStaleSamples: 3,
            deadlineNanoseconds: 100)
        guard case .needsNow(let snapshot) = plan else {
            XCTFail("Exact positive copied input must request verified NeedsNow")
            return
        }
        XCTAssertEqual(freshnessCalls, 1)
        XCTAssertThrowsError(try bridge.readiness(current: .zero, previous: nil)) { error in
            XCTAssertEqual(error as? BelugaRustMicrophoneForwardingEvidence.Failure, .refused)
        }
        XCTAssertTrue(bridge.hasNativeFault)
        XCTAssertThrowsError(try bridge.finishFreshness(snapshot, now: 99)) { error in
            XCTAssertEqual(error as? BelugaRustMicrophoneForwardingEvidence.Failure, .faulted)
        }
        XCTAssertEqual(readinessCalls, 1)
        XCTAssertEqual(freshnessCalls, 1)
    }
}

#endif
