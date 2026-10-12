import BelugaCore
import BelugaUpdateCore
import XCTest

/// Direct copied-value ABI coverage, not native retirement or SDK execution.
final class BelugaRustUnarmedCompletionTests: XCTestCase {
    private typealias Bridge = BelugaRustUnarmedCompletion

    private var goldens: [(UInt32, UInt32, Bridge.Reason)] {
        [(0, 0, .noCompletion), (3, 0, .noUpdate), (960, 1, .feedFetchFailure),
         (960, 2, .feedParseFailure), (544, 0, .cancelledCheck),
         (491536, 0, .declinedCandidate)]
    }

    /// Literal original inner selectors: no production masks or result decoder.
    private func reference(flags: UInt32, failureKind: UInt32) -> Bridge.Reason {
        let p: (Int) -> Bool = { flags & (UInt32(1) << $0) != 0 }
        let failure = failureKind != 0
        if p(0) && p(1) && !p(2) && !p(3) && !p(4) && !failure && !p(5) {
            return .noUpdate
        } else if failure && p(6) && p(7) && p(8) && p(9) && !p(10) && !p(11)
            && !p(12) && !p(3) && !p(13) && !p(2) && !p(0) && !p(4) && !p(5) {
            return failureKind == 1 ? .feedFetchFailure : .feedParseFailure
        } else if !p(14) && !p(0) && p(5) && p(9) && !p(2) && !p(3) && !p(4) && !failure {
            return .cancelledCheck
        } else if !p(14) && !p(0) && !p(5) && !failure && p(4) && p(15)
            && p(16) && p(17) && p(18) {
            return .declinedCandidate
        }
        return .noCompletion
    }

    private func classify(flags: UInt32, failureKind: Bridge.FailureKind) -> Bridge.Reason? {
        let p: (Int) -> Bool = { flags & (UInt32(1) << $0) != 0 }
        return Bridge.classify(noUpdatePresent: p(0), noUpdateIsFinished: p(1),
            boundCandidatePresent: p(2), admittedItemPresent: p(3), declinePresent: p(4),
            cancelledInitialCheck: p(5), failureAcknowledged: p(6), failureAbortObserved: p(7),
            failureIsFinished: p(8), initialPresentationPresent: p(9),
            candidateAdmissionAttempted: p(10), candidatePresentationObserved: p(11),
            candidateBindingInProgress: p(12), foundItemPresent: p(13), finishedErrorPresent: p(14),
            declineSDKChoiceObserved: p(15), boundMatchesDecline: p(16),
            admittedMatchesDecline: p(17), foundMatchesDecline: p(18), failureKind: failureKind)
    }

    func testExactLayoutsAndAllSixLiteralReasonsThroughActualCAndPacking() {
        XCTAssertTrue(Bridge.layoutIsExact)
        for (flags, failureKind, expected) in goldens {
            let raw = Bridge.Request(abi_version: 1, flags: flags, failure_kind: failureKind)
            let actual = beluga_core_update_unarmed_completion_decide(raw)
            XCTAssertEqual(actual.abi_version, 1)
            XCTAssertEqual(actual.status, 0)
            XCTAssertEqual(actual.reason, expected.rawValue)
            XCTAssertEqual(beluga_core_update_unarmed_completion_result_is_valid(raw, actual), 1)
            XCTAssertEqual(Bridge.evaluate(raw), expected)
            XCTAssertEqual(classify(flags: flags, failureKind: Bridge.FailureKind(rawValue: failureKind)!), expected)
        }
    }

    func testEveryBitPackingAndOriginalCandidateAndFoundItemOmissions() {
        for (base, _, _) in goldens {
            for failureKind: UInt32 in 0...2 {
                for bit in 0..<19 {
                    let flags = base ^ (UInt32(1) << bit)
                    let expected = reference(flags: flags, failureKind: failureKind)
                    XCTAssertEqual(classify(flags: flags,
                        failureKind: Bridge.FailureKind(rawValue: failureKind)!), expected)
                    XCTAssertEqual(Bridge.evaluate(.init(abi_version: 1, flags: flags,
                        failure_kind: failureKind)), expected)
                }
            }
        }
        for (base, expected): (UInt32, Bridge.Reason) in [
            (3, .noUpdate), (544, .cancelledCheck), (491536, .declinedCandidate)
        ] {
            for combination: UInt32 in 0..<16 {
                let flags = base | (combination << 10)
                XCTAssertEqual(classify(flags: flags, failureKind: .absent), expected)
            }
        }
        for failureKind in [Bridge.FailureKind.feedFetch, .feedParseOrSignature] {
            for bit in 10...13 {
                XCTAssertEqual(classify(flags: 960 | (UInt32(1) << bit),
                    failureKind: failureKind), .noCompletion)
            }
        }
    }

    func testUnsupportedABISeparateFailureKindAndEveryUnknownFlagRefuse() {
        for (flags, failureKind, _) in goldens {
            var requests: [Bridge.Request] = []
            for abi: UInt32 in [0, 2, .max] {
                requests.append(.init(abi_version: abi, flags: flags, failure_kind: failureKind))
            }
            for kind: UInt32 in [3, 4, .max] {
                requests.append(.init(abi_version: 1, flags: flags, failure_kind: kind))
            }
            for bit in 19..<32 {
                requests.append(.init(abi_version: 1, flags: flags | (UInt32(1) << bit),
                    failure_kind: failureKind))
            }
            for raw in requests {
                let refusal = beluga_core_update_unarmed_completion_decide(raw)
                XCTAssertEqual(refusal.abi_version, 1)
                XCTAssertEqual(refusal.status, 1)
                XCTAssertEqual(refusal.reason, 0)
                XCTAssertEqual(beluga_core_update_unarmed_completion_result_is_valid(raw, refusal), 0)
                XCTAssertNil(Bridge.evaluate(raw))
            }
        }
    }

    func testWholeResultAndCoherentCrossRequestReasonsCannotManufactureCompletion() {
        for (flags, failureKind, expected) in goldens {
            let raw = Bridge.Request(abi_version: 1, flags: flags, failure_kind: failureKind)
            for field in 0..<3 {
                XCTAssertNil(Bridge.evaluate(raw, resultMutation: { _, actual in
                    var changed = actual
                    switch field {
                    case 0: changed.abi_version = 2
                    case 1: changed.status = 1
                    default: changed.reason = (actual.reason + 1) % 6
                    }
                    return changed
                }))
            }
            for (_, _, other) in goldens where other != expected {
                XCTAssertNil(Bridge.evaluate(raw, resultMutation: { _, _ in
                    Bridge.Result(abi_version: 1, status: 0, reason: other.rawValue)
                }))
            }
            for reason: UInt32 in [6, 7, .max] {
                XCTAssertNil(Bridge.evaluate(raw, resultMutation: { _, _ in
                    Bridge.Result(abi_version: 1, status: 0, reason: reason)
                }))
            }
        }
    }
}
