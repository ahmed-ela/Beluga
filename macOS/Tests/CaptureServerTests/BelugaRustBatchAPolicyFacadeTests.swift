// Test actual production C first;
// only then corrupt copied result fields. No route/capture/phone effects.
import BelugaCore
import Foundation
@testable import CaptureCore
@testable import CaptureServer
@testable import WebRTCTransport
import XCTest

private final class BatchACallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
private final class BatchACopiedProbe<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?
    func record(_ value: Value) { lock.lock(); defer { lock.unlock() }; stored = value }
    var value: Value? { lock.lock(); defer { lock.unlock() }; return stored }
}

private enum RetryOutputField: CaseIterable, Sendable {
    case abi, reserved, failedLimit, backoffLimit, cooldownLimit
    case failedCounter, backoffCounter, cooldownCounter, status, decision
    func corrupt(_ original: BelugaRustSafeOutputRetryBoundary.Output)
        -> BelugaRustSafeOutputRetryBoundary.Output {
        var result = original
        switch self {
        case .abi: result.state.abi_version = 0
        case .reserved: result.state.reserved = 1
        case .failedLimit: result.state.maximum_failed_attempt_count += 1
        case .backoffLimit: result.state.maximum_backoff_tick_count += 1
        case .cooldownLimit: result.state.capped_cooldown_tick_count += 1
        case .failedCounter: result.state.failed_attempt_count = -1
        case .backoffCounter: result.state.backoff_tick_count = -1
        case .cooldownCounter: result.state.cooldown_tick_count = -1
        case .status: result.status = 2
        case .decision: result.tick_decision = 99
        }
        return result
    }
}
private enum StatelessOutputField: CaseIterable, Sendable {
    case abi, status, value, reserved
    func corruptStart(_ original: BelugaRustSystemAudioStartBoundary.Output)
        -> BelugaRustSystemAudioStartBoundary.Output {
        var result = original
        switch self {
        case .abi: result.abi_version = 0
        case .status: result.status = 2
        case .reserved: result.reserved = 1
        case .value: result.mode = (result.mode + 1) % 4 // legal but semantically wrong
        }
        return result
    }
    func corruptHosted(_ original: BelugaRustMacHostedCallBoundary.Output, evidence: Bool)
        -> BelugaRustMacHostedCallBoundary.Output {
        var result = original
        switch self {
        case .abi: result.abi_version = 0
        case .status: result.status = 2
        case .reserved: result.reserved = 1
        case .value: result.value = evidence ? (result.value + 1) % 4 : 1 - result.value
        }
        return result
    }
}

final class BelugaRustBatchAPolicyFacadeTests: XCTestCase {
    func testRetryEveryInitialOutputFieldFaultIsStickyAndNonAuthorizing() throws {
        XCTAssertEqual(RetryOutputField.allCases.count, 10)
        for field in RetryOutputField.allCases {
            let initialCalls = BatchACallCounter(), transitionCalls = BatchACallCounter()
            let producer = BelugaRustSafeOutputRetryProducer(
                initial: { input in
                    let actual = BelugaRustSafeOutputRetryProducer.actual.initial(input)
                    initialCalls.increment()
                    return field.corrupt(actual)
                },
                transition: { state, opcode in
                    let actual = BelugaRustSafeOutputRetryProducer.actual.transition(state, opcode)
                    transitionCalls.increment()
                    return actual
                }
            )
            var policy = WorldwideSafeOutputInvariantRetryPolicy(producer: producer)
            XCTAssertEqual(initialCalls.value, 1)
            XCTAssertEqual(policy.bridgeFault, .invalidInitial)
            XCTAssertTrue(policy.hasBridgeFault)
            // Intended original configuration/counters are diagnostic only.
            XCTAssertEqual(policy.maximumFailedAttemptCount, 6)
            XCTAssertEqual(policy.maximumBackoffTickCount, 16)
            XCTAssertEqual(policy.cappedCooldownTickCount, 60)
            XCTAssertEqual(policy.failedAttemptCount, 0)
            XCTAssertEqual(policy.backoffTickCount, 0)
            XCTAssertEqual(policy.cooldownTickCount, 0)
            for operation in 1...3 {
                XCTAssertThrowsError(try self.perform(&policy, opcode: UInt32(operation))) {
                    XCTAssertEqual($0 as? WorldwideSafeOutputInvariantRetryBridgeError, .invalidInitial)
                }
            }
            XCTAssertEqual(transitionCalls.value, 0, "sticky fault must not call C or recover")
            XCTAssertEqual(policy.failedAttemptCount, 0)
        }
    }

    func testRetryEveryTransitionOutputFieldFaultRetainsExactBeforeSnapshot() throws {
        for opcode in [UInt32(1), 2, 3] {
            for field in RetryOutputField.allCases {
                let calls = BatchACallCounter()
                let producer = BelugaRustSafeOutputRetryProducer(
                    initial: BelugaRustSafeOutputRetryProducer.actual.initial,
                    transition: { state, event in
                        let actual = BelugaRustSafeOutputRetryProducer.actual.transition(state, event)
                        calls.increment()
                        return event == opcode ? field.corrupt(actual) : actual
                    }
                )
                var policy = WorldwideSafeOutputInvariantRetryPolicy(
                    maximumFailedAttemptCount: 3, maximumBackoffTickCount: 4,
                    cappedCooldownTickCount: 3, producer: producer)
                if opcode == 3 { try policy.recordFailure() }
                let before = (policy.maximumFailedAttemptCount, policy.maximumBackoffTickCount,
                    policy.cappedCooldownTickCount, policy.failedAttemptCount,
                    policy.backoffTickCount, policy.cooldownTickCount)
                let priorCalls = calls.value
                XCTAssertThrowsError(try self.perform(&policy, opcode: opcode)) {
                    XCTAssertEqual($0 as? WorldwideSafeOutputInvariantRetryBridgeError,
                        .invalidTransition(opcode: opcode))
                }
                XCTAssertEqual(calls.value, priorCalls + 1, "actual C must run before copied corruption")
                XCTAssertEqual(policy.maximumFailedAttemptCount, before.0)
                XCTAssertEqual(policy.maximumBackoffTickCount, before.1)
                XCTAssertEqual(policy.cappedCooldownTickCount, before.2)
                XCTAssertEqual(policy.failedAttemptCount, before.3)
                XCTAssertEqual(policy.backoffTickCount, before.4)
                XCTAssertEqual(policy.cooldownTickCount, before.5)
                let faultedCallCount = calls.value
                XCTAssertThrowsError(try policy.reset())
                XCTAssertThrowsError(try policy.recordFailure())
                XCTAssertThrowsError(try policy.shouldAttemptOnCurrentTick())
                XCTAssertEqual(calls.value, faultedCallCount)
            }
        }
    }

    func testRetryCopiesKeepIndependentCountersAndFaultLifetimes() throws {
        let producer = BelugaRustSafeOutputRetryProducer(
            initial: BelugaRustSafeOutputRetryProducer.actual.initial,
            transition: { state, opcode in
                var actual = BelugaRustSafeOutputRetryProducer.actual.transition(state, opcode)
                if opcode == 1 { actual.status = 99 }
                return actual
            }
        )
        var policy = WorldwideSafeOutputInvariantRetryPolicy(producer: producer)
        try policy.recordFailure()
        var copy = policy
        XCTAssertThrowsError(try policy.shouldAttemptOnCurrentTick())
        XCTAssertTrue(policy.hasBridgeFault)
        XCTAssertFalse(copy.hasBridgeFault)
        XCTAssertEqual(copy.failedAttemptCount, 1)
        XCTAssertEqual(copy.backoffTickCount, 1)
        try copy.recordFailure()
        XCTAssertEqual(copy.failedAttemptCount, 2)
        XCTAssertEqual(copy.backoffTickCount, 2)
        XCTAssertEqual(policy.failedAttemptCount, 1)
        XCTAssertEqual(policy.backoffTickCount, 1)
    }

    func testRetryActualCClampsArbitrarySignedNativeLimitsAndKeepsLiteralTrace() throws {
        var clamped = WorldwideSafeOutputInvariantRetryPolicy(
            maximumFailedAttemptCount: Int.min, maximumBackoffTickCount: 0,
            cappedCooldownTickCount: -7)
        XCTAssertFalse(clamped.hasBridgeFault)
        XCTAssertEqual(clamped.maximumFailedAttemptCount, 1)
        XCTAssertEqual(clamped.maximumBackoffTickCount, 1)
        XCTAssertEqual(clamped.cappedCooldownTickCount, 1)
        XCTAssertTrue(try clamped.shouldAttemptOnCurrentTick())
        try clamped.recordFailure()
        XCTAssertFalse(try clamped.shouldAttemptOnCurrentTick())
        XCTAssertTrue(try clamped.shouldAttemptOnCurrentTick())
        var maximum = WorldwideSafeOutputInvariantRetryPolicy(
            maximumFailedAttemptCount: Int.max, maximumBackoffTickCount: Int.max,
            cappedCooldownTickCount: Int.max)
        XCTAssertFalse(maximum.hasBridgeFault)
        XCTAssertEqual(maximum.maximumFailedAttemptCount, Int.max)
        try maximum.recordFailure()
        XCTAssertEqual(maximum.failedAttemptCount, 1)
        XCTAssertEqual(maximum.backoffTickCount, 1)
    }

    func testSystemAudioEveryOutputFieldRefusesAcrossAll64TypedInputs() throws {
        for bits in UInt32(0)..<64 {
            for field in StatelessOutputField.allCases {
                let calls = BatchACallCounter()
                let producer = BelugaRustSystemAudioStartProducer { input in
                    let actual = BelugaRustSystemAudioStartProducer.actual.decide(input)
                    calls.increment()
                    return field.corruptStart(actual)
                }
                XCTAssertThrowsError(try WorldwideSystemAudioRecoveryPolicy.startMode(
                    isLive: bits & 1 != 0, isPausedForRecovery: bits & 2 != 0,
                    hasSource: bits & 4 != 0, hasSink: bits & 8 != 0,
                    hasValidAuthorization: bits & 16 != 0, peerGenerationMatches: bits & 32 != 0,
                    producer: producer)) {
                    XCTAssertEqual($0 as? WorldwideSystemAudioStartBridgeError, .invalidBridge)
                }
                XCTAssertEqual(calls.value, 1)
            }
        }
    }

    func testHostedEveryOutputFieldRefusesAcrossAdmissionAndEvidenceFunctions() throws {
        let current = WebRTCMacHostedCallChallenge(sequence: 7,
            callEpochNonce: UUID(uuid: epochBytes), nonce: UUID(uuid: nonceBytes))
        let native = SystemAudioMacFaceTimeActivityChallenge(sequence: 7,
            nonce: current.nonce, callEpochNonce: current.callEpochNonce)
        for field in StatelessOutputField.allCases {
            let calls = BatchACallCounter()
            let producer = BelugaRustMacHostedCallProducer(
                observation: { input in
                    let actual = BelugaRustMacHostedCallProducer.actual.observation(input)
                    calls.increment(); return field.corruptHosted(actual, evidence: false)
                },
                evidence: { input in
                    let actual = BelugaRustMacHostedCallProducer.actual.evidence(input)
                    calls.increment(); return field.corruptHosted(actual, evidence: true)
                },
                peerGeneration: { input in
                    let actual = BelugaRustMacHostedCallProducer.actual.peerGeneration(input)
                    calls.increment(); return field.corruptHosted(actual, evidence: false)
                }
            )
            for (sequence, highest) in [(UInt64(11), UInt64(10)), (10, 11)] {
                XCTAssertThrowsError(try WorldwideMacHostedCallObservationPolicy.admits(
                    observationSequence: sequence, highestAdmittedSequence: highest,
                    observationChallenge: native, currentChallenge: current, producer: producer)) {
                    XCTAssertEqual($0 as? WorldwideMacHostedCallBridgeError, .observation)
                }
            }
            for (active, armed) in [(false, false), (false, true), (true, false), (true, true)] {
                XCTAssertThrowsError(try WorldwideMacHostedCallEvidenceStatePolicy.state(
                    isCausallyBoundActive: active, isCausallyArmed: armed, producer: producer)) {
                    XCTAssertEqual($0 as? WorldwideMacHostedCallBridgeError, .evidence)
                }
            }
            let generationCases: [(UInt64?, UInt64?, UInt64)] = [(7, 7, 7), (nil, 7, 7), (0, 0, 0)]
            for generations in generationCases {
                XCTAssertThrowsError(try WorldwideMacHostedCallPeerGenerationPolicy.admits(
                    audioPeerGeneration: generations.0, challengePeerGeneration: generations.1,
                    currentPeerGeneration: generations.2, producer: producer)) {
                    XCTAssertEqual($0 as? WorldwideMacHostedCallBridgeError, .peerGeneration)
                }
            }
            XCTAssertEqual(calls.value, 9)
        }
    }

    func testHostedUUIDTupleAndMaximumNumericValuesProjectLosslessly() throws {
        let probe = BatchACopiedProbe<BelugaRustMacHostedCallBoundary.Observation>()
        let producer = BelugaRustMacHostedCallProducer(
            observation: { input in
                let actual = BelugaRustMacHostedCallProducer.actual.observation(input)
                probe.record(input); return actual
            }, evidence: BelugaRustMacHostedCallProducer.actual.evidence,
            peerGeneration: BelugaRustMacHostedCallProducer.actual.peerGeneration)
        let current = WebRTCMacHostedCallChallenge(sequence: UInt64.max,
            callEpochNonce: UUID(uuid: epochBytes), nonce: UUID(uuid: nonceBytes))
        let native = SystemAudioMacFaceTimeActivityChallenge(sequence: UInt64.max,
            nonce: current.nonce, callEpochNonce: current.callEpochNonce)
        XCTAssertTrue(try WorldwideMacHostedCallObservationPolicy.admits(
            observationSequence: UInt64.max, highestAdmittedSequence: UInt64.max - 1,
            observationChallenge: native, currentChallenge: current, producer: producer))
        let input = try XCTUnwrap(probe.value)
        XCTAssertEqual(input.observation_sequence, UInt64.max)
        XCTAssertEqual(input.highest_admitted_sequence, UInt64.max - 1)
        XCTAssertEqual(input.current_challenge_sequence, UInt64.max)
        XCTAssertTrue(BelugaRustMacHostedCallBoundary.sameBytes(input.observation_nonce, nonceBytes))
        XCTAssertTrue(BelugaRustMacHostedCallBoundary.sameBytes(input.current_nonce, nonceBytes))
        XCTAssertTrue(BelugaRustMacHostedCallBoundary.sameBytes(input.observation_call_epoch_nonce, epochBytes))
        XCTAssertTrue(BelugaRustMacHostedCallBoundary.sameBytes(input.current_call_epoch_nonce, epochBytes))

        let invalidVersion = WebRTCMacHostedCallChallenge(sequence: UInt64.max,
            callEpochNonce: current.callEpochNonce, nonce: current.nonce, protocolVersion: Int.min)
        XCTAssertFalse(try WorldwideMacHostedCallObservationPolicy.admits(
            observationSequence: UInt64.max, highestAdmittedSequence: 0,
            observationChallenge: native, currentChallenge: invalidVersion, producer: producer))
        XCTAssertEqual(try XCTUnwrap(probe.value).current_protocol_version, Int64.min)
    }

    func testHostedValidPoisonAndAbsentGenerationStayLegitimateRefusals() throws {
        XCTAssertNil(try WorldwideMacHostedCallEvidenceStatePolicy.state(
            isCausallyBoundActive: true, isCausallyArmed: true))
        XCTAssertEqual(try WorldwideMacHostedCallEvidenceStatePolicy.state(
            isCausallyBoundActive: false, isCausallyArmed: false), .inactive)
        XCTAssertFalse(try WorldwideMacHostedCallPeerGenerationPolicy.admits(
            audioPeerGeneration: nil, challengePeerGeneration: 0, currentPeerGeneration: 0))
        XCTAssertFalse(try WorldwideMacHostedCallPeerGenerationPolicy.admits(
            audioPeerGeneration: 0, challengePeerGeneration: 0, currentPeerGeneration: 0))
        XCTAssertTrue(try WorldwideMacHostedCallPeerGenerationPolicy.admits(
            audioPeerGeneration: UInt64.max, challengePeerGeneration: UInt64.max,
            currentPeerGeneration: UInt64.max))
    }

    private func perform(_ policy: inout WorldwideSafeOutputInvariantRetryPolicy,
                         opcode: UInt32) throws {
        switch opcode {
        case 1: _ = try policy.shouldAttemptOnCurrentTick()
        case 2: try policy.recordFailure()
        case 3: try policy.reset()
        default: XCTFail("Test harness opcode is not a production event")
        }
    }
    private var nonceBytes: BelugaRustMacHostedCallBoundary.UUIDBytes {
        (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    }
    private var epochBytes: BelugaRustMacHostedCallBoundary.UUIDBytes {
        (16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1)
    }
}
