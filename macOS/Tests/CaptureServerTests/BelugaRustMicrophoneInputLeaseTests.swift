import BelugaCore
import XCTest
@testable import CaptureServer

#if DEBUG
final class BelugaRustMicrophoneInputLeaseTests: XCTestCase {
    private typealias Bridge = BelugaRustMicrophoneInputLease

    func testInputLeaseLiteralLayoutsAndAllFourCopiedOperations() throws {
        XCTAssertTrue(Bridge.layoutIsExact)
        XCTAssertEqual([MemoryLayout<Bridge.Facts>.size, MemoryLayout<Bridge.Facts>.stride,
            MemoryLayout<Bridge.Facts>.alignment], [32, 32, 8])
        XCTAssertEqual([MemoryLayout<Bridge.Result>.size, MemoryLayout<Bridge.Result>.stride,
            MemoryLayout<Bridge.Result>.alignment], [20, 20, 4])
        let rows: [(UInt32, UInt32, Int64, Int64, Bridge.Action)] = [
            (1, 0, 0, 3, .acquire), (1, 0, 3, 3, .budgetExhausted),
            (2, 1, 0, 0, .authorizeAcquired), (2, 2, 0, 0, .retryAcquisition),
            (2, 3, 0, 0, .terminalAcquisition), (3, 2, 1, 3, .retryRelease),
            (3, 2, 3, 3, .finishRelease), (3, 3, 1, 3, .finishRelease),
            (4, 0, 0, 0, .useNativeFallback), (4, 1, 0, 0, .released),
            (4, 2, 0, 0, .degraded), (4, 3, 0, 0, .released),
        ]
        for (operation, disposition, count, maximum, expected) in rows {
            let input = facts(operation, disposition, count, maximum)
            var calls = 0
            let action = try Bridge.evaluateRawForTesting(facts: input) { actualInput, result in
                calls += 1
                XCTAssertEqual(actualInput.abi_version, 1)
                XCTAssertEqual(actualInput.opcode, operation)
                XCTAssertEqual(actualInput.disposition, disposition)
                XCTAssertEqual(actualInput.reserved, 0)
                XCTAssertEqual(actualInput.attempt_count, count)
                XCTAssertEqual(actualInput.maximum_attempt_count, maximum)
                XCTAssertEqual(result.status, 1)
                XCTAssertEqual(result.action, expected.rawValue)
                return result
            }
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(action, expected)
        }
    }

    func testInputLeaseNativeIntegerBoundaryAndNoSuccessfulSwiftFallback() throws {
        for (maximum, expected) in [(1, [true, false, false, false]), (3, [true, true, true, false])] {
            for (count, admitted) in expected.enumerated() {
                let result = try Bridge.evaluate(operation: .acquisitionBudget,
                    attemptCount: count, maximumAttemptCount: maximum)
                XCTAssertEqual(result, admitted ? .acquire : .budgetExhausted)
            }
        }
        XCTAssertEqual(try Bridge.evaluate(operation: .acquisitionBudget,
            attemptCount: Int.max - 1, maximumAttemptCount: Int.max), .acquire)
        XCTAssertEqual(try Bridge.evaluate(operation: .acquisitionBudget,
            attemptCount: Int.max, maximumAttemptCount: Int.max), .budgetExhausted)
        XCTAssertThrowsError(try Bridge.evaluate(operation: .acquisitionBudget,
            attemptCount: -1, maximumAttemptCount: 3)) { XCTAssertEqual($0 as? Bridge.Failure, .refused) }
        XCTAssertThrowsError(try Bridge.evaluate(operation: .releaseContinuation,
            disposition: 2, attemptCount: 0, maximumAttemptCount: 3)) {
            XCTAssertEqual($0 as? Bridge.Failure, .refused)
        }
    }

    func testInputLeaseWholeResultRejectsEveryFieldAndCoherentWrongAction() throws {
        let inputs = [facts(1, 0, 0, 3), facts(1, 0, 3, 3), facts(2, 1, 0, 0),
            facts(2, 2, 0, 0), facts(2, 3, 0, 0), facts(3, 2, 1, 3),
            facts(3, 2, 3, 3), facts(4, 0, 0, 0), facts(4, 1, 0, 0), facts(4, 2, 0, 0)]
        for input in inputs {
            for index in 0..<9 {
                XCTAssertThrowsError(try Bridge.evaluateRawForTesting(facts: input) { _, actual in
                    var changed = actual
                    switch index {
                    case 0: changed.abi_version = 2
                    case 1: changed.status = 0
                    case 2: changed.status = 2
                    case 3: changed.opcode = 0
                    case 4: changed.opcode = input.opcode % 4 + 1
                    case 5: changed.action = 0
                    case 6: changed.action = 11
                    case 7: changed.action = actual.action % 10 + 1
                    default: changed.reserved = 1
                    }
                    return changed
                }) { XCTAssertEqual($0 as? Bridge.Failure, .refused) }
            }
            for action in UInt32(1)...10 {
                let actual = beluga_core_microphone_input_lease_decide(input)
                guard action != actual.action else { continue }
                XCTAssertThrowsError(try Bridge.evaluateRawForTesting(facts: input) { _, actual in
                    var coherent = actual; coherent.action = action; return coherent
                }) { XCTAssertEqual($0 as? Bridge.Failure, .refused) }
            }
        }
    }

    func testInputLeaseMalformedFactsRemainRefusedEvenWithCanonicalInvalidResult() {
        var malformed = [facts(1, 1, 0, 3), facts(1, 0, -1, 3), facts(1, 0, 0, 0),
            facts(2, 0, 0, 0), facts(2, 4, 0, 0), facts(2, 1, 1, 0), facts(2, 1, 0, 1),
            facts(3, 4, 1, 3), facts(3, 2, 0, 3), facts(3, 2, 1, 0),
            facts(4, 4, 0, 0), facts(4, 0, 1, 0), facts(4, 0, 0, 1)]
        for original in [facts(1, 0, 0, 3), facts(2, 1, 0, 0), facts(3, 2, 1, 3), facts(4, 0, 0, 0)] {
            var abi = original; abi.abi_version = 2; malformed.append(abi)
            var reserved = original; reserved.reserved = 1; malformed.append(reserved)
            for operation in [UInt32(0), 5, UInt32.max] {
                var opcode = original; opcode.opcode = operation; malformed.append(opcode)
            }
        }
        for input in malformed {
            XCTAssertThrowsError(try Bridge.evaluateRawForTesting(facts: input) { _, actual in
                XCTAssertEqual(actual.status, 0)
                XCTAssertEqual(actual.opcode, 0)
                XCTAssertEqual(actual.action, 0)
                return actual
            }) { XCTAssertEqual($0 as? Bridge.Failure, .refused) }
        }
    }

    private func facts(_ operation: UInt32, _ disposition: UInt32,
                       _ count: Int64, _ maximum: Int64) -> Bridge.Facts {
        Bridge.Facts(abi_version: 1, opcode: operation, disposition: disposition,
            reserved: 0, attempt_count: count, maximum_attempt_count: maximum)
    }
}
#endif
