import BelugaCore

/// Fixed producer + whole-result verifier over copied scalars only.
/// This bridge cannot manufacture a native lease key, authorization or route.
enum BelugaRustMicrophoneInputLease {
    typealias Facts = beluga_core_microphone_input_lease_facts_t
    typealias Result = beluga_core_microphone_input_lease_result_t

    enum Failure: Error, Equatable { case layout, integerConversion, refused }
    enum Operation: UInt32, Equatable {
        case acquisitionBudget = 1, acquisitionOutcome = 2
        case releaseContinuation = 3, releaseOutcome = 4
    }
    enum Action: UInt32, Equatable {
        case acquire = 1, budgetExhausted = 2, authorizeAcquired = 3
        case retryAcquisition = 4, terminalAcquisition = 5
        case retryRelease = 6, finishRelease = 7
        case useNativeFallback = 8, released = 9, degraded = 10
    }

    static var layoutIsExact: Bool {
        MemoryLayout<Int>.size == 8 && UInt16(littleEndian: 1) == 1
            && exact(Facts.self, 32, 8) && exact(Result.self, 20, 4)
            && MemoryLayout<Facts>.offset(of: \Facts.abi_version) == 0
            && MemoryLayout<Facts>.offset(of: \Facts.opcode) == 4
            && MemoryLayout<Facts>.offset(of: \Facts.disposition) == 8
            && MemoryLayout<Facts>.offset(of: \Facts.reserved) == 12
            && MemoryLayout<Facts>.offset(of: \Facts.attempt_count) == 16
            && MemoryLayout<Facts>.offset(of: \Facts.maximum_attempt_count) == 24
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.opcode) == 8
            && MemoryLayout<Result>.offset(of: \Result.action) == 12
            && MemoryLayout<Result>.offset(of: \Result.reserved) == 16
    }

    static func evaluate(operation: Operation, disposition: UInt32 = 0,
                         attemptCount: Int = 0, maximumAttemptCount: Int = 0) throws -> Action {
        let facts = try encode(operation: operation, disposition: disposition,
            attemptCount: attemptCount, maximumAttemptCount: maximumAttemptCount)
        let actual = beluga_core_microphone_input_lease_decide(facts)
        return try verified(facts: facts, result: actual)
    }

#if DEBUG
    /// Copied-result corruption only AFTER the genuine producer. No native
    /// caller seam and no injectable verifier or successful Swift fallback.
    static func evaluateRawForTesting(facts: Facts,
        postResultMutation: (Facts, Result) -> Result) throws -> Action {
        try requireLayout()
        let actual = beluga_core_microphone_input_lease_decide(facts)
        return try verified(facts: facts, result: postResultMutation(facts, actual))
    }
#endif

    private static func encode(operation: Operation, disposition: UInt32,
                               attemptCount: Int, maximumAttemptCount: Int) throws -> Facts {
        try requireLayout()
        guard let count = Int64(exactly: attemptCount),
              let maximum = Int64(exactly: maximumAttemptCount) else {
            throw Failure.integerConversion
        }
        return Facts(abi_version: 1, opcode: operation.rawValue, disposition: disposition,
            reserved: 0, attempt_count: count, maximum_attempt_count: maximum)
    }

    private static func verified(facts: Facts, result: Result) throws -> Action {
        guard beluga_core_microphone_input_lease_result_is_valid(facts, result) == 1,
              result.abi_version == 1, result.status == 1,
              result.opcode == facts.opcode, result.reserved == 0,
              let action = Action(rawValue: result.action) else { throw Failure.refused }
        return action
    }

    private static func requireLayout() throws {
        guard layoutIsExact else { throw Failure.layout }
    }
    private static func exact<T>(_ type: T.Type, _ size: Int, _ alignment: Int) -> Bool {
        MemoryLayout<T>.size == size && MemoryLayout<T>.stride == size && MemoryLayout<T>.alignment == alignment
    }
}
