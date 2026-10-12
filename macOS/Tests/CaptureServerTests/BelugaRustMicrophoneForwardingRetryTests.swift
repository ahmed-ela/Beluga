import BelugaCore
import XCTest
@testable import CaptureServer

#if DEBUG
/// Genuine producer/verifier calls over copied values only. No native driver,
/// key, FIFO, frame, clock, resource or replacement producer enters this fixture.
final class BelugaRustMicrophoneForwardingRetryTests: XCTestCase {
    private typealias Bridge = BelugaRustMicrophoneForwardingRetry

    func testLiteralLayoutsOffsetsAndDiscriminants() {
        XCTAssertTrue(Bridge.layoutIsExact)
        XCTAssertEqual([MemoryLayout<Bridge.Config>.size, MemoryLayout<Bridge.Config>.stride,
                        MemoryLayout<Bridge.Config>.alignment], [16, 16, 8])
        XCTAssertEqual([MemoryLayout<Bridge.State>.size, MemoryLayout<Bridge.State>.stride,
                        MemoryLayout<Bridge.State>.alignment], [24, 24, 8])
        XCTAssertEqual([MemoryLayout<Bridge.Event>.size, MemoryLayout<Bridge.Event>.stride,
                        MemoryLayout<Bridge.Event>.alignment], [16, 16, 4])
        XCTAssertEqual([MemoryLayout<Bridge.Result>.size, MemoryLayout<Bridge.Result>.stride,
                        MemoryLayout<Bridge.Result>.alignment], [40, 40, 8])
        XCTAssertEqual([MemoryLayout<Bridge.Config>.offset(of: \Bridge.Config.abi_version),
                        MemoryLayout<Bridge.Config>.offset(of: \Bridge.Config.reserved),
                        MemoryLayout<Bridge.Config>.offset(of: \Bridge.Config.maximum_attempt_count)], [0, 4, 8])
        XCTAssertEqual([MemoryLayout<Bridge.State>.offset(of: \Bridge.State.abi_version),
                        MemoryLayout<Bridge.State>.offset(of: \Bridge.State.present),
                        MemoryLayout<Bridge.State>.offset(of: \Bridge.State.may_retry),
                        MemoryLayout<Bridge.State>.offset(of: \Bridge.State.reserved),
                        MemoryLayout<Bridge.State>.offset(of: \Bridge.State.count)], [0, 4, 8, 12, 16])
        XCTAssertEqual([MemoryLayout<Bridge.Event>.offset(of: \Bridge.Event.opcode),
                        MemoryLayout<Bridge.Event>.offset(of: \Bridge.Event.failure_category),
                        MemoryLayout<Bridge.Event>.offset(of: \Bridge.Event.bridge_faulted),
                        MemoryLayout<Bridge.Event>.offset(of: \Bridge.Event.reserved)], [0, 4, 8, 12])
        XCTAssertEqual([MemoryLayout<Bridge.Result>.offset(of: \Bridge.Result.state),
                        MemoryLayout<Bridge.Result>.offset(of: \Bridge.Result.status),
                        MemoryLayout<Bridge.Result>.offset(of: \Bridge.Result.decision),
                        MemoryLayout<Bridge.Result>.offset(of: \Bridge.Result.redrive_action),
                        MemoryLayout<Bridge.Result>.offset(of: \Bridge.Result.reserved)], [0, 24, 28, 32, 36])
        XCTAssertEqual([Bridge.Operation.eligible.rawValue, Bridge.Operation.recordAttempt.rawValue,
                        Bridge.Operation.retryFailure.rawValue, Bridge.Operation.exhaust.rawValue], [1, 2, 3, 4])
        XCTAssertEqual([Bridge.RedriveAction.retain.rawValue, Bridge.RedriveAction.clear.rawValue,
                        Bridge.RedriveAction.request.rawValue], [0, 1, 2])
    }

    func testEligibilityLiteralAbsencePermissionFaultAndStrictBoundary() throws {
        let cases: [(Bridge.Row?, Bool)] = [
            (nil, true), (row(1, false), false), (row(1, true), true),
            (row(2, true), true), (row(3, true), false), (row(4, true), false),
            (row(Int.max, true), false),
        ]
        for (before, expected) in cases {
            let healthy = try Bridge.evaluate(maximumAttemptCount: 3, before: before,
                operation: .eligible, bridgeFaulted: false)
            assertEvaluation(healthy, before: before, after: before, decision: expected, redrive: .retain)
            let faulted = try Bridge.evaluate(maximumAttemptCount: 3, before: before,
                operation: .eligible, bridgeFaulted: true)
            assertEvaluation(faulted, before: before, after: before, decision: false, redrive: .retain)
        }
        let before = row(Int.max - 1, true)
        let result = try Bridge.evaluate(maximumAttemptCount: Int.max, before: before,
            operation: .eligible, bridgeFaulted: false)
        assertEvaluation(result, before: before, after: before, decision: true, redrive: .retain)
        XCTAssertEqual(result.config.maximum_attempt_count, Int64.max)
        XCTAssertEqual(result.original.count, Int64.max - 1)
    }

    func testRecordLiteralIncrementConsumesPermissionAndRejectsOverflow() throws {
        let cases: [(Bridge.Row?, Bridge.Row)] = [
            (nil, row(1, false)), (row(1, false), row(2, false)),
            (row(1, true), row(2, false)), (row(2, true), row(3, false)),
            (row(3, true), row(4, false)), (row(Int.max - 1, true), row(Int.max, false)),
        ]
        for (before, expected) in cases {
            let result = try Bridge.evaluate(maximumAttemptCount: 3, before: before,
                operation: .recordAttempt, bridgeFaulted: false)
            assertEvaluation(result, before: before, after: expected, decision: false, redrive: .retain)
        }
        assertRefused(try Bridge.evaluate(maximumAttemptCount: Int.max, before: row(Int.max, true),
            operation: .recordAttempt, bridgeFaulted: false))
    }

    func testAllElevenFailureCategoriesHaveLiteralVotes() throws {
        let cases: [(Bridge.FailureCategory, Bool)] = [
            (.monitoringFailed, false), (.outputUnavailable, true), (.startFailed, true),
            (.admissionFailed, false), (.readinessFailed, true), (.sourceMediaStalled, true),
            (.formatUnsafe, false), (.sharedClockUnsafe, false), (.runtimeEnqueueFailed, true),
            (.runtimeProgressStalled, true), (.evidenceBridgeRefused, false),
        ]
        XCTAssertEqual(cases.map { $0.0.rawValue }, Array(1...11).map { UInt32($0) })
        for (category, expected) in cases {
            let before = row(1, false)
            let result = try Bridge.evaluate(maximumAttemptCount: 3, before: before,
                operation: .retryFailure, failureCategory: category, bridgeFaulted: false)
            assertEvaluation(result, before: before, after: row(1, expected), decision: expected,
                             redrive: expected ? .request : .clear)
            let faulted = try Bridge.evaluate(maximumAttemptCount: 3, before: before,
                operation: .retryFailure, failureCategory: category, bridgeFaulted: true)
            assertEvaluation(faulted, before: before, after: before, decision: false, redrive: .clear)
        }
    }

    func testRetryFalsePreservesPriorPermissionAndNeverCreatesHistory() throws {
        let absent = try Bridge.evaluate(maximumAttemptCount: 3, before: nil,
            operation: .retryFailure, failureCategory: .startFailed, bridgeFaulted: false)
        assertEvaluation(absent, before: nil, after: nil, decision: false, redrive: .clear)
        let cases: [(Bridge.Row, Bridge.FailureCategory, Bridge.Row, Bool, Bridge.RedriveAction)] = [
            (row(1, true), .admissionFailed, row(1, true), false, .clear),
            (row(1, false), .runtimeEnqueueFailed, row(1, true), true, .request),
            (row(2, true), .runtimeEnqueueFailed, row(2, true), true, .request),
            (row(3, true), .startFailed, row(3, true), false, .clear),
            (row(4, false), .startFailed, row(4, false), false, .clear),
            (row(Int.max, true), .startFailed, row(Int.max, true), false, .clear),
        ]
        for (before, category, after, decision, redrive) in cases {
            let result = try Bridge.evaluate(maximumAttemptCount: 3, before: before,
                operation: .retryFailure, failureCategory: category, bridgeFaulted: false)
            assertEvaluation(result, before: before, after: after, decision: decision, redrive: redrive)
        }
    }

    func testLiteralDefaultThreeAndMaximumOneSequences() throws {
        // Each input/output is written independently; no evaluator generates expectations.
        let cases: [(Bridge.Row?, Bridge.Operation, Bridge.FailureCategory?, Bridge.Row?, Bool, Bridge.RedriveAction)] = [
            (nil, .eligible, nil, nil, true, .retain),
            (nil, .recordAttempt, nil, row(1, false), false, .retain),
            (row(1, false), .retryFailure, .startFailed, row(1, true), true, .request),
            (row(1, true), .eligible, nil, row(1, true), true, .retain),
            (row(1, true), .recordAttempt, nil, row(2, false), false, .retain),
            (row(2, false), .retryFailure, .startFailed, row(2, true), true, .request),
            (row(2, true), .recordAttempt, nil, row(3, false), false, .retain),
            (row(3, false), .retryFailure, .startFailed, row(3, false), false, .clear),
            (row(3, false), .eligible, nil, row(3, false), false, .retain),
            (nil, .eligible, nil, nil, true, .retain),
        ]
        for (before, operation, category, after, decision, redrive) in cases {
            let result = try Bridge.evaluate(maximumAttemptCount: 3, before: before,
                operation: operation, failureCategory: category, bridgeFaulted: false)
            assertEvaluation(result, before: before, after: after, decision: decision, redrive: redrive)
        }
        let maxOne: [(Bridge.Row?, Bridge.Operation, Bridge.FailureCategory?, Bridge.Row?, Bool, Bridge.RedriveAction)] = [
            (nil, .eligible, nil, nil, true, .retain),
            (nil, .recordAttempt, nil, row(1, false), false, .retain),
            (row(1, false), .eligible, nil, row(1, false), false, .retain),
            (row(1, false), .retryFailure, .startFailed, row(1, false), false, .clear),
            (row(1, true), .eligible, nil, row(1, true), false, .retain),
        ]
        for (before, operation, category, after, decision, redrive) in maxOne {
            let result = try Bridge.evaluate(maximumAttemptCount: 1, before: before,
                operation: operation, failureCategory: category, bridgeFaulted: false)
            assertEvaluation(result, before: before, after: after, decision: decision, redrive: redrive)
        }
    }

    func testFixedExhaustAfterRefusalRetainsAbsentRedriveAndClosesPresentPermission() throws {
        // A failed copied evaluation is not a driver fault reset or a native frame.
        assertRefused(try Bridge.evaluate(maximumAttemptCount: Int.max, before: row(Int.max, true),
            operation: .recordAttempt, bridgeFaulted: false))
        let absent = try Bridge.exhaustBookkeeping(maximumAttemptCount: 3, before: nil)
        XCTAssertNil(absent.originalRow); XCTAssertNil(absent.row)
        XCTAssertEqual(absent.redrive, .retain)
        XCTAssertEqual(bytes(absent.result), bytes(accepted(nil, false, .retain)))
        let cases: [Bridge.Row] = [row(1, false), row(1, true), row(3, true), row(4, true), row(Int.max, true)]
        for before in cases {
            let result = try Bridge.exhaustBookkeeping(maximumAttemptCount: 3, before: before)
            XCTAssertEqual(result.originalRow, before)
            XCTAssertEqual(result.row, row(before.count, false))
            XCTAssertEqual(result.redrive, .clear)
            XCTAssertEqual(result.event.opcode, 4)
            XCTAssertEqual(result.event.failure_category, 0)
            XCTAssertEqual(result.event.bridge_faulted, 0)
            XCTAssertEqual(bytes(result.original), bytes(state(before)))
            XCTAssertEqual(bytes(result.result), bytes(accepted(row(before.count, false), false, .clear)))
        }
    }

    func testMalformedInputsAndMatchingInvalidStatusZeroNeverBecomeFalseVotes() {
        let c = config(3), s = state(row(1, true)), e = event(.eligible)
        var badConfig: [Bridge.Config] = []
        var changedConfig = c; changedConfig.abi_version = 0; badConfig.append(changedConfig)
        changedConfig = c; changedConfig.abi_version = 2; badConfig.append(changedConfig)
        changedConfig = c; changedConfig.reserved = 1; badConfig.append(changedConfig)
        badConfig.append(contentsOf: [config(0), config(-1), config(Int64.min)])
        for bad in badConfig { assertRawRefused(bad, s, e) }
        var badState: [Bridge.State] = []
        var changedState = s; changedState.abi_version = 0; badState.append(changedState)
        changedState = s; changedState.abi_version = 2; badState.append(changedState)
        changedState = s; changedState.reserved = 1; badState.append(changedState)
        changedState = s; changedState.present = 2; badState.append(changedState)
        changedState = s; changedState.may_retry = 2; badState.append(changedState)
        let badCounts: [Int64] = [0, -1, Int64.min]
        for count in badCounts {
            changedState = s; changedState.count = count; badState.append(changedState)
        }
        changedState = state(nil); changedState.count = 1; badState.append(changedState)
        changedState = state(nil); changedState.may_retry = 1; badState.append(changedState)
        for bad in badState { assertRawRefused(c, bad, e) }
        var badEvent: [Bridge.Event] = []
        var changedEvent = e
        let badOpcodes: [UInt32] = [0, 5, UInt32.max]
        for opcode in badOpcodes {
            changedEvent = e; changedEvent.opcode = opcode; badEvent.append(changedEvent)
        }
        changedEvent = e; changedEvent.reserved = 1; badEvent.append(changedEvent)
        changedEvent = e; changedEvent.bridge_faulted = 2; badEvent.append(changedEvent)
        changedEvent = e; changedEvent.failure_category = 1; badEvent.append(changedEvent)
        let unusedFieldOperations: [Bridge.Operation] = [.recordAttempt, .exhaust]
        for operation in unusedFieldOperations {
            changedEvent = event(operation); changedEvent.bridge_faulted = 1; badEvent.append(changedEvent)
            changedEvent = event(operation); changedEvent.failure_category = 3; badEvent.append(changedEvent)
        }
        let badCategories: [UInt32] = [0, 12, UInt32.max]
        for category in badCategories {
            changedEvent = event(.retryFailure); changedEvent.failure_category = category; badEvent.append(changedEvent)
        }
        changedEvent = event(.retryFailure, .startFailed); changedEvent.bridge_faulted = 2; badEvent.append(changedEvent)
        for bad in badEvent { assertRawRefused(c, s, bad) }
        assertRefused(try Bridge.evaluate(maximumAttemptCount: 0, before: nil,
            operation: .eligible, bridgeFaulted: false))
        assertRefused(try Bridge.evaluate(maximumAttemptCount: 3, before: row(0, false),
            operation: .eligible, bridgeFaulted: false))
    }

    func testEveryReturnedByteIsCorrelatedForEveryOperation() throws {
        let cases: [(Bridge.Row?, Bridge.Operation, Bridge.FailureCategory?, Bridge.Row?, Bool, Bridge.RedriveAction)] = [
            (nil, .eligible, nil, nil, true, .retain),
            (row(3, true), .eligible, nil, row(3, true), false, .retain),
            (nil, .recordAttempt, nil, row(1, false), false, .retain),
            (row(1, true), .recordAttempt, nil, row(2, false), false, .retain),
            (row(1, false), .retryFailure, .startFailed, row(1, true), true, .request),
            (row(1, true), .retryFailure, .admissionFailed, row(1, true), false, .clear),
            (nil, .exhaust, nil, nil, false, .retain),
            (row(1, true), .exhaust, nil, row(1, false), false, .clear),
        ]
        for (before, operation, category, after, decision, redrive) in cases {
            let baseline = try Bridge.evaluate(maximumAttemptCount: 3, before: before,
                operation: operation, failureCategory: category, bridgeFaulted: false)
            assertEvaluation(baseline, before: before, after: after, decision: decision, redrive: redrive)
            for offset in 0..<40 {
                var calls = 0
                assertRefused(try Bridge.evaluateForTesting(maximumAttemptCount: 3, before: before,
                    operation: operation, failureCategory: category, bridgeFaulted: false) { c, s, e, result in
                    calls += 1
                    XCTAssertEqual(bytes(c), bytes(config(3)))
                    XCTAssertEqual(bytes(s), bytes(state(before)))
                    XCTAssertEqual(bytes(e), bytes(event(operation, category)))
                    XCTAssertEqual(bytes(result), bytes(accepted(after, decision, redrive)))
                    var corrupt = result
                    withUnsafeMutableBytes(of: &corrupt) { $0[offset] ^= 1 }
                    return corrupt
                })
                XCTAssertEqual(calls, 1)
            }
        }
    }

    func testAcceptedFalseCorrelationAndCoherentDecisionFlips() throws {
        let cases: [(Bridge.Row, Bridge.Operation, Bridge.FailureCategory?, Bridge.RedriveAction)] = [
            (row(3, true), .eligible, nil, .retain),
            (row(1, true), .retryFailure, .admissionFailed, .clear),
        ]
        for (before, operation, category, redrive) in cases {
            let valid = try Bridge.evaluate(maximumAttemptCount: 3, before: before,
                operation: operation, failureCategory: category, bridgeFaulted: false)
            assertEvaluation(valid, before: before, after: before, decision: false, redrive: redrive)
            assertRefused(try Bridge.evaluateForTesting(maximumAttemptCount: 3, before: before,
                operation: operation, failureCategory: category, bridgeFaulted: false) { _, _, _, result in
                var corrupt = result; corrupt.decision = 1; return corrupt
            })
            assertRefused(try Bridge.evaluateForTesting(maximumAttemptCount: 3, before: before,
                operation: operation, failureCategory: category, bridgeFaulted: false) { _, _, _, result in
                var corrupt = result; corrupt.status = 0; return corrupt
            })
        }
    }

    private func row(_ count: Int, _ mayRetry: Bool) -> Bridge.Row {
        Bridge.Row(count: count, mayRetry: mayRetry)
    }
    private func config(_ maximum: Int64) -> Bridge.Config {
        Bridge.Config(abi_version: 1, reserved: 0, maximum_attempt_count: maximum)
    }
    private func state(_ row: Bridge.Row?) -> Bridge.State {
        if let row {
            return Bridge.State(abi_version: 1, present: 1, may_retry: row.mayRetry ? 1 : 0,
                                reserved: 0, count: Int64(row.count))
        }
        return Bridge.State(abi_version: 1, present: 0, may_retry: 0, reserved: 0, count: 0)
    }
    private func event(_ operation: Bridge.Operation, _ category: Bridge.FailureCategory? = nil) -> Bridge.Event {
        Bridge.Event(opcode: operation.rawValue, failure_category: category?.rawValue ?? 0,
                     bridge_faulted: 0, reserved: 0)
    }
    private func accepted(_ row: Bridge.Row?, _ decision: Bool, _ redrive: Bridge.RedriveAction) -> Bridge.Result {
        Bridge.Result(state: state(row), status: 1, decision: decision ? 1 : 0,
                      redrive_action: redrive.rawValue, reserved: 0)
    }
    private func bytes<T>(_ value: T) -> [UInt8] {
        var value = value
        return withUnsafeBytes(of: &value) { Array($0) }
    }
    private func assertEvaluation(_ actual: Bridge.Evaluation, before: Bridge.Row?, after: Bridge.Row?,
                                  decision: Bool, redrive: Bridge.RedriveAction,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.originalRow, before, file: file, line: line)
        XCTAssertEqual(actual.row, after, file: file, line: line)
        XCTAssertEqual(actual.decision, decision, file: file, line: line)
        XCTAssertEqual(actual.redrive, redrive, file: file, line: line)
        XCTAssertEqual(bytes(actual.original), bytes(state(before)), file: file, line: line)
        XCTAssertEqual(bytes(actual.result), bytes(accepted(after, decision, redrive)), file: file, line: line)
    }
    private func assertRefused<T>(_ expression: @autoclosure () throws -> T,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? Bridge.Failure, .refused, file: file, line: line)
        }
    }
    private func assertRawRefused(_ config: Bridge.Config, _ before: Bridge.State, _ event: Bridge.Event,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let originalConfig = bytes(config), originalState = bytes(before), originalEvent = bytes(event)
        var calls = 0
        var produced: Bridge.Result?
        assertRefused(try Bridge.evaluateRawForTesting(config: config, before: before, event: event) { c, s, e, result in
            calls += 1; produced = result
            XCTAssertEqual(bytes(c), originalConfig, file: file, line: line)
            XCTAssertEqual(bytes(s), originalState, file: file, line: line)
            XCTAssertEqual(bytes(e), originalEvent, file: file, line: line)
            return result
        }, file: file, line: line)
        XCTAssertEqual(calls, 1, file: file, line: line)
        XCTAssertNotNil(produced, file: file, line: line)
        if let produced {
            let expected = Bridge.Result(state: before, status: 0, decision: 0, redrive_action: 0, reserved: 0)
            XCTAssertEqual(bytes(produced), bytes(expected), file: file, line: line)
        }
        XCTAssertEqual(bytes(config), originalConfig, file: file, line: line)
        XCTAssertEqual(bytes(before), originalState, file: file, line: line)
        XCTAssertEqual(bytes(event), originalEvent, file: file, line: line)
    }
}
#endif
