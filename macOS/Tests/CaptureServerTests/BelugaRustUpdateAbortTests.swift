import BelugaCore
import BelugaUpdateCore
import XCTest

/// Copied-value wrapper coverage only; no native callback, SDK or retirement authority.
final class BelugaRustUpdateAbortTests: XCTestCase {
    private typealias Bridge = BelugaRustUpdateAbort

    /// Independent literal original inner decision, not production masks or decoding.
    private func reference(flags: UInt32) -> Bridge.Action {
        if flags & 1 != 0 && flags & 2 != 0 && flags & 4 != 0
            && flags & 8 == 0 && flags & 16 != 0 {
            return .markAbort
        } else if flags & 32 != 0 {
            return .preserve
        }
        return .poison
    }

    private func classify(flags: UInt32) -> Bridge.Action? {
        Bridge.classify(failurePresent: flags & 1 != 0,
            cleanUnarmedCycle: flags & 2 != 0, acknowledged: flags & 4 != 0,
            observedAbort: flags & 8 != 0, sameFailureError: flags & 16 != 0,
            sameNoUpdateError: flags & 32 != 0)
    }

    func testExactRequestAndResultLayoutsThroughActualC() {
        XCTAssertEqual(MemoryLayout<Bridge.Request>.size, 8)
        XCTAssertEqual(MemoryLayout<Bridge.Request>.stride, 8)
        XCTAssertEqual(MemoryLayout<Bridge.Request>.alignment, 4)
        XCTAssertEqual(MemoryLayout<Bridge.Request>.offset(of: \Bridge.Request.abi_version), 0)
        XCTAssertEqual(MemoryLayout<Bridge.Request>.offset(of: \Bridge.Request.flags), 4)
        XCTAssertEqual(MemoryLayout<Bridge.Result>.size, 12)
        XCTAssertEqual(MemoryLayout<Bridge.Result>.stride, 12)
        XCTAssertEqual(MemoryLayout<Bridge.Result>.alignment, 4)
        XCTAssertEqual(MemoryLayout<Bridge.Result>.offset(of: \Bridge.Result.abi_version), 0)
        XCTAssertEqual(MemoryLayout<Bridge.Result>.offset(of: \Bridge.Result.status), 4)
        XCTAssertEqual(MemoryLayout<Bridge.Result>.offset(of: \Bridge.Result.action), 8)
        XCTAssertTrue(Bridge.layoutIsExact)
        let raw = Bridge.Request(abi_version: 1, flags: 23)
        let actual = beluga_core_update_abort_decide(raw)
        XCTAssertEqual(actual.abi_version, 1)
        XCTAssertEqual(actual.status, 0)
        XCTAssertEqual(actual.action, Bridge.Action.markAbort.rawValue)
        XCTAssertEqual(beluga_core_update_abort_result_is_valid(raw, actual), 1)
    }

    func testAllSixFactBitsAndOriginalFirstIfPriorityThroughActualClassify() {
        for flags: UInt32 in 0..<64 {
            let expected = reference(flags: flags)
            let raw = Bridge.Request(abi_version: 1, flags: flags)
            let actual = beluga_core_update_abort_decide(raw)
            XCTAssertEqual(actual.abi_version, 1, "flags \(flags)")
            XCTAssertEqual(actual.status, 0, "flags \(flags)")
            XCTAssertEqual(actual.action, expected.rawValue, "flags \(flags)")
            XCTAssertEqual(beluga_core_update_abort_result_is_valid(raw, actual), 1,
                           "flags \(flags)")
            XCTAssertEqual(Bridge.evaluate(raw), expected, "flags \(flags)")
            XCTAssertEqual(classify(flags: flags), expected, "ABORT_FACT_PACKING flags \(flags)")
        }
        // Both alternatives are true, but the original first if owns the decision.
        XCTAssertEqual(reference(flags: 55), .markAbort)
        XCTAssertEqual(classify(flags: 55), .markAbort, "ABORT_FIRST_IF_PRIORITY")
    }

    func testUnknownABIAndEveryUnknownFlagRefuse() {
        for flags: UInt32 in 0..<64 {
            var requests: [Bridge.Request] = []
            for abi: UInt32 in [0, 2, .max] {
                requests.append(.init(abi_version: abi, flags: flags))
            }
            for bit in 6..<32 {
                requests.append(.init(abi_version: 1, flags: flags | (UInt32(1) << bit)))
            }
            for raw in requests {
                let refusal = beluga_core_update_abort_decide(raw)
                XCTAssertEqual(refusal.abi_version, 1)
                XCTAssertEqual(refusal.status, 1)
                XCTAssertEqual(refusal.action, 0)
                XCTAssertEqual(beluga_core_update_abort_result_is_valid(raw, refusal), 0)
                XCTAssertNil(Bridge.evaluate(raw))
            }
        }
    }

    func testWholeResultFieldsAndCoherentWrongSupportedActionsRefuse() {
        for flags: UInt32 in 0..<64 {
            let raw = Bridge.Request(abi_version: 1, flags: flags)
            let expected = reference(flags: flags)
            for field in 0..<3 {
                XCTAssertNil(Bridge.evaluate(raw, resultMutation: { _, actual in
                    var changed = actual
                    switch field {
                    case 0: changed.abi_version = 2
                    case 1: changed.status = 1
                    default: changed.action = actual.action % 3 + 1
                    }
                    return changed
                }), "ABORT_RESULT_FIELD flags \(flags) field \(field)")
            }
            for action: UInt32 in 1...3 where action != expected.rawValue {
                XCTAssertNil(Bridge.evaluate(raw, resultMutation: { _, _ in
                    Bridge.Result(abi_version: 1, status: 0, action: action)
                }), "ABORT_COHERENT_ACTION flags \(flags) action \(action)")
            }
            for action: UInt32 in [0, 4, .max] {
                XCTAssertNil(Bridge.evaluate(raw, resultMutation: { _, _ in
                    Bridge.Result(abi_version: 1, status: 0, action: action)
                }), "ABORT_CLOSED_ACTION flags \(flags) action \(action)")
            }
        }
    }
}
