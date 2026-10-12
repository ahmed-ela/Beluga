import BelugaCore
import Foundation
import XCTest
@testable import CaptureServer

// PRIVATE, UNCOMPILED: requires the reviewed future ABI and native policy, neither integrated here.
final class BelugaRustAvailabilityRetryTests: XCTestCase {
    private typealias State = BelugaRustAvailabilityRetryProducer.State
    private typealias Event = BelugaRustAvailabilityRetryProducer.Event
    private typealias Output = BelugaRustAvailabilityRetryProducer.Output
    private let legalStates: [(UInt32, UInt32)] = [(1, 0), (2, 0), (4, 0), (8, 0),
                                                 (16, 0), (30, 0), (1, 1)]

    func testActualCABIAndAllFourteenLegalTransitionsMatchOriginal() {
        XCTAssertEqual(MemoryLayout<State>.size, 16)
        XCTAssertEqual(MemoryLayout<State>.stride, 16)
        XCTAssertEqual(MemoryLayout<State>.alignment, 4)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.abi_version), 0)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.next_delay_seconds), 4)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.has_validated_connection), 8)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.reserved), 12)
        XCTAssertEqual(MemoryLayout<Event>.size, 8)
        XCTAssertEqual(MemoryLayout<Event>.stride, 8)
        XCTAssertEqual(MemoryLayout<Event>.alignment, 4)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.opcode), 0)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.reserved), 4)
        XCTAssertEqual(MemoryLayout<Output>.size, 32)
        XCTAssertEqual(MemoryLayout<Output>.stride, 32)
        XCTAssertEqual(MemoryLayout<Output>.alignment, 4)
        XCTAssertEqual(MemoryLayout<Output>.offset(of: \.candidate_state), 0)
        XCTAssertEqual(MemoryLayout<Output>.offset(of: \.decision), 16)
        XCTAssertEqual(MemoryLayout<Output>.offset(of: \.became_validated), 20)
        XCTAssertEqual(MemoryLayout<Output>.offset(of: \.retry_delay_seconds), 24)
        XCTAssertEqual(MemoryLayout<Output>.offset(of: \.reserved), 28)

        // Complete literal oracle, not generated with the production rejection predicate.
        let table: [(UInt32, UInt32, UInt32, [UInt32])] = [
            (1, 0, 0, [1, 1, 1, 0, 0, 1, 0, 0]), (1, 0, 1, [1, 2, 0, 0, 1, 0, 1, 0]),
            (2, 0, 0, [1, 1, 1, 0, 0, 1, 0, 0]), (2, 0, 1, [1, 4, 0, 0, 1, 0, 2, 0]),
            (4, 0, 0, [1, 1, 1, 0, 0, 1, 0, 0]), (4, 0, 1, [1, 8, 0, 0, 1, 0, 4, 0]),
            (8, 0, 0, [1, 1, 1, 0, 0, 1, 0, 0]), (8, 0, 1, [1, 16, 0, 0, 1, 0, 8, 0]),
            (16, 0, 0, [1, 1, 1, 0, 0, 1, 0, 0]), (16, 0, 1, [1, 30, 0, 0, 1, 0, 16, 0]),
            (30, 0, 0, [1, 1, 1, 0, 0, 1, 0, 0]), (30, 0, 1, [1, 30, 0, 0, 1, 0, 30, 0]),
            (1, 1, 0, [1, 1, 1, 0, 0, 0, 0, 0]), (1, 1, 1, [1, 2, 0, 0, 1, 0, 1, 0])
        ]
        for (delay, validated, opcode, expected) in table {
            let before = state(delay, validated)
            let copied = fields(before)
            let event = Event(opcode: opcode, reserved: 0)
            let result = beluga_core_availability_retry_step(1, before, event)
            XCTAssertEqual(fields(result), expected)
            XCTAssertEqual(fields(before), copied)
            XCTAssertEqual(event.opcode, opcode)
            XCTAssertEqual(event.reserved, 0)
            XCTAssertTrue(BelugaRustAvailabilityRetryBoundary.accepts(before: before, event: event, output: result))
        }
    }

    func testIndependentOriginalTracesPreserveDelayBooleanEqualityAndCopies() throws {
        for (delay, validated) in legalStates {
            for length in 0...8 {
                for bits in 0..<(1 << length) {
                    var policy = try legalPolicy(delay: delay, validated: validated)
                    var original = AvailabilityRetryOriginalReference(
                        nextDelaySeconds: Int(delay), hasValidatedConnection: validated == 1)
                    var equalValue = policy
                    for position in 0..<length {
                        let beforeCopy = policy
                        let originalCopy = original
                        let opcode = UInt32((bits >> position) & 1)
                        if opcode == 0 {
                            let expected = original.observedValidAvailabilityState()
                            XCTAssertEqual(try policy.observedValidAvailabilityState(), expected)
                            XCTAssertEqual(try equalValue.observedValidAvailabilityState(), expected)
                        } else {
                            let expected = original.delayAfterFailure()
                            XCTAssertEqual(try policy.delayAfterFailure(), expected)
                            XCTAssertEqual(try equalValue.delayAfterFailure(), expected)
                        }
                        XCTAssertEqual(policy.nextDelaySeconds, original.nextDelaySeconds)
                        XCTAssertEqual(policy.hasValidatedConnection, original.hasValidatedConnection)
                        XCTAssertEqual(policy, equalValue)
                        XCTAssertEqual(beforeCopy.nextDelaySeconds, originalCopy.nextDelaySeconds)
                        XCTAssertEqual(beforeCopy.hasValidatedConnection, originalCopy.hasValidatedConnection)
                        XCTAssertFalse(beforeCopy.bridgeFaultedForTesting)
                    }
                }
            }
        }
    }

    func testEveryMalformedCopiedOutputRetainsRawStateAndFaultsWithoutRemint() throws {
        for (delay, validated) in legalStates {
            for opcode in [UInt32(0), 1] {
                for fault in AvailabilityRetryCopiedFault.allCases {
                    var policy = try legalPolicy(delay: delay, validated: validated)
                    let before = fields(policy.copiedStateForTesting)
                    let calls = AvailabilityRetryLocked<[UInt32]>([])
                    let producer = BelugaRustAvailabilityRetryProducer { abi, state, event in
                        var output = BelugaRustAvailabilityRetryProducer.actual.step(abi, state, event)
                        calls.modify { $0.append(event.opcode) }
                        fault.apply(to: &output, before: state, event: event)
                        return output
                    }
                    assertBridgeError { if opcode == 0 {
                        _ = try policy.observedValidAvailabilityState(using: producer)
                    } else { _ = try policy.delayAfterFailure(using: producer) } }
                    XCTAssertEqual(fields(policy.copiedStateForTesting), before, "\(fault)")
                    XCTAssertTrue(policy.bridgeFaultedForTesting)
                    assertBridgeError { _ = try policy.observedValidAvailabilityState(using: producer) }
                    assertBridgeError { _ = try policy.delayAfterFailure(using: producer) }
                    XCTAssertEqual(calls.value, [opcode], "A sticky fault must never remint: \(fault)")
                    XCTAssertEqual(fields(policy.copiedStateForTesting), before)
                }
            }
        }
    }

    func testBoundaryRejectsAllUnknownRawFieldsAndImpossibleValidatedStates() {
        for (delay, validated) in legalStates {
            let valid = state(delay, validated)
            for opcode in [UInt32(0), 1] {
                for outerABI in [UInt32(0), 2, .max] {
                    assertRawRefusal(outerABI, before: valid, event: Event(opcode: opcode, reserved: 0))
                }
                for abi in [UInt32(0), 2, .max] {
                    var bad = valid; bad.abi_version = abi
                    assertRawRefusal(1, before: bad, event: Event(opcode: opcode, reserved: 0))
                }
                for reserved in [UInt32(1), .max] {
                    var bad = valid; bad.reserved = reserved
                    assertRawRefusal(1, before: bad, event: Event(opcode: opcode, reserved: 0))
                    assertRawRefusal(1, before: valid, event: Event(opcode: opcode, reserved: reserved))
                }
                for badDelay in [UInt32(0), 3, 32, .max] {
                    var bad = valid; bad.next_delay_seconds = badDelay
                    assertRawRefusal(1, before: bad, event: Event(opcode: opcode, reserved: 0))
                }
                for flag in [UInt32(2), .max] {
                    var bad = valid; bad.has_validated_connection = flag
                    assertRawRefusal(1, before: bad, event: Event(opcode: opcode, reserved: 0))
                }
            }
            for opcode in [UInt32(2), 3, 17, .max] {
                assertRawRefusal(1, before: valid, event: Event(opcode: opcode, reserved: 0))
            }
        }
        for delay in [UInt32(2), 4, 8, 16, 30] {
            for opcode in [UInt32(0), 1] {
                assertRawRefusal(1, before: state(delay, 1), event: Event(opcode: opcode, reserved: 0))
            }
        }
    }

    func testFailureUsesActualPriorDelayAndResetsValidatedOnlyAfterCommit() throws {
        var policy = WorldwideAvailabilityRetryPolicy()
        XCTAssertEqual(try policy.delayAfterFailure(), 1)
        XCTAssertEqual(try policy.delayAfterFailure(), 2)
        XCTAssertTrue(try policy.observedValidAvailabilityState())
        let captured = AvailabilityRetryLocked<[[UInt32]]>([])
        let producer = BelugaRustAvailabilityRetryProducer { abi, before, event in
            let output = BelugaRustAvailabilityRetryProducer.actual.step(abi, before, event)
            captured.modify { $0.append([before.next_delay_seconds, before.has_validated_connection,
                event.opcode, output.candidate_state.next_delay_seconds,
                output.candidate_state.has_validated_connection, output.retry_delay_seconds]) }
            return output
        }
        XCTAssertEqual(try policy.delayAfterFailure(using: producer), 1)
        XCTAssertFalse(policy.hasValidatedConnection)
        XCTAssertEqual(policy.nextDelaySeconds, 2)
        XCTAssertEqual(try policy.delayAfterFailure(using: producer), 2)
        XCTAssertEqual(captured.value, [[1, 1, 1, 2, 0, 1], [2, 0, 1, 4, 0, 2]])
    }

    func testCopyFaultCustodyDoesNotResetOrFaultAnIndependentOriginal() throws {
        var original = WorldwideAvailabilityRetryPolicy()
        XCTAssertEqual(try original.delayAfterFailure(), 1)
        XCTAssertEqual(try original.delayAfterFailure(), 2)
        var copy = original
        let before = fields(original.copiedStateForTesting)
        let calls = AvailabilityRetryLocked<Int>(0)
        let producer = BelugaRustAvailabilityRetryProducer { abi, state, event in
            var output = BelugaRustAvailabilityRetryProducer.actual.step(abi, state, event)
            calls.modify { $0 += 1 }
            output.reserved = 1
            return output
        }
        assertBridgeError { _ = try copy.observedValidAvailabilityState(using: producer) }
        XCTAssertEqual(fields(copy.copiedStateForTesting), before)
        XCTAssertEqual(fields(original.copiedStateForTesting), before)
        XCTAssertNotEqual(copy, original)
        XCTAssertFalse(original.bridgeFaultedForTesting)
        XCTAssertEqual(try original.delayAfterFailure(), 4)
        XCTAssertTrue(try original.observedValidAvailabilityState())
        assertBridgeError { _ = try copy.delayAfterFailure(using: producer) }
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(fields(copy.copiedStateForTesting), before)
        XCTAssertEqual(original.nextDelaySeconds, 1)
        XCTAssertTrue(original.hasValidatedConnection)
    }

    private func state(_ delay: UInt32, _ validated: UInt32) -> State {
        State(abi_version: 1, next_delay_seconds: delay, has_validated_connection: validated, reserved: 0)
    }

    private func fields(_ state: State) -> [UInt32] {
        [state.abi_version, state.next_delay_seconds, state.has_validated_connection, state.reserved]
    }

    private func fields(_ output: Output) -> [UInt32] {
        fields(output.candidate_state) + [output.decision, output.became_validated,
            output.retry_delay_seconds, output.reserved]
    }

    private func legalPolicy(delay: UInt32, validated: UInt32) throws -> WorldwideAvailabilityRetryPolicy {
        enum ConstructionError: Error { case inadmissibleRequestedState }
        let progression = [1, 2, 4, 8, 16, 30]
        guard let targetIndex = progression.firstIndex(of: Int(delay)),
              validated == 0 || (validated == 1 && delay == 1) else {
            XCTFail("Test requested a state outside the independent seven-state table")
            throw ConstructionError.inadmissibleRequestedState
        }
        var policy = WorldwideAvailabilityRetryPolicy()
        XCTAssertEqual(policy.nextDelaySeconds, 1)
        XCTAssertFalse(policy.hasValidatedConnection)
        // Fixed six-entry literal table bounds construction to at most five failure operations.
        for step in 0..<targetIndex {
            XCTAssertEqual(policy.nextDelaySeconds, progression[step])
            XCTAssertFalse(policy.hasValidatedConnection)
            XCTAssertEqual(try policy.delayAfterFailure(), progression[step])
            XCTAssertEqual(policy.nextDelaySeconds, progression[step + 1])
            XCTAssertFalse(policy.hasValidatedConnection)
        }
        XCTAssertEqual(policy.nextDelaySeconds, Int(delay))
        if validated == 1 {
            XCTAssertTrue(try policy.observedValidAvailabilityState())
            XCTAssertEqual(policy.nextDelaySeconds, 1)
            XCTAssertTrue(policy.hasValidatedConnection)
        }
        XCTAssertEqual(fields(policy.copiedStateForTesting), [1, delay, validated, 0])
        XCTAssertFalse(policy.bridgeFaultedForTesting)
        return policy
    }

    private func assertBridgeError(_ action: () throws -> Void,
                                   file: StaticString = #filePath, line: UInt = #line) {
        do { try action(); XCTFail("Malformed output must not yield a successful value", file: file, line: line) }
        catch { XCTAssertEqual(error as? WorldwideAvailabilityRetryError, .invalidBridge, file: file, line: line) }
    }

    private func assertRawRefusal(_ abi: UInt32, before: State, event: Event,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let copied = fields(before)
        let output = beluga_core_availability_retry_step(abi, before, event)
        XCTAssertEqual(fields(output), copied + [2, 0, 0, 0], file: file, line: line)
        XCTAssertEqual(fields(before), copied, file: file, line: line)
        XCTAssertFalse(BelugaRustAvailabilityRetryBoundary.accepts(before: before, event: event, output: output),
                       file: file, line: line)
    }
}

private enum AvailabilityRetryCopiedFault: CaseIterable, Sendable {
    case candidateABI, candidateReserved, delayZero, delayUnknown, delayMaximum,
         flagUnknown, flagMaximum, otherEventCandidate, wrongReachableCandidate,
         invalidDecision, oppositeDecision, unknownDecision, becameOpposite,
         becameUnknown, becameMaximum, wrongReturnedDelay, resultReserved, resultReservedMaximum

    func apply(to output: inout BelugaRustAvailabilityRetryProducer.Output,
               before: BelugaRustAvailabilityRetryProducer.State,
               event: BelugaRustAvailabilityRetryProducer.Event) {
        switch self {
        case .candidateABI: output.candidate_state.abi_version = 2
        case .candidateReserved: output.candidate_state.reserved = 1
        case .delayZero: output.candidate_state.next_delay_seconds = 0
        case .delayUnknown: output.candidate_state.next_delay_seconds = 3
        case .delayMaximum: output.candidate_state.next_delay_seconds = .max
        case .flagUnknown: output.candidate_state.has_validated_connection = 2
        case .flagMaximum: output.candidate_state.has_validated_connection = .max
        case .otherEventCandidate:
            output.candidate_state.next_delay_seconds = event.opcode == 0
                ? min(before.next_delay_seconds * 2, 30) : 1
            output.candidate_state.has_validated_connection = event.opcode == 0 ? 0 : 1
        case .wrongReachableCandidate:
            output.candidate_state.has_validated_connection = 0
            output.candidate_state.next_delay_seconds = output.candidate_state.next_delay_seconds == 30 ? 16 : 30
        case .invalidDecision: output.decision = 2
        case .oppositeDecision: output.decision = 1 - event.opcode
        case .unknownDecision: output.decision = .max
        case .becameOpposite: output.became_validated = 1 - output.became_validated
        case .becameUnknown: output.became_validated = 2
        case .becameMaximum: output.became_validated = .max
        case .wrongReturnedDelay: output.retry_delay_seconds = event.opcode == 0 ? 1 : before.next_delay_seconds + 1
        case .resultReserved: output.reserved = 1
        case .resultReservedMaximum: output.reserved = .max
        }
    }
}

private final class AvailabilityRetryLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    init(_ value: Value) { storage = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return storage }
    func modify(_ body: (inout Value) -> Void) { lock.lock(); defer { lock.unlock() }; body(&storage) }
}
