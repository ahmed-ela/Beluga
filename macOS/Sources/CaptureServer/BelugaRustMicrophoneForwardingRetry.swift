import BelugaCore

/// Copied scalars only. The native driver owns the existing frame, sticky fault,
/// exact row/key custody and publication; this type owns none of those.
enum BelugaRustMicrophoneForwardingRetry {
    typealias Config = beluga_core_microphone_forwarding_retry_config_t
    typealias State = beluga_core_microphone_forwarding_retry_state_t
    typealias Event = beluga_core_microphone_forwarding_retry_event_t
    typealias Result = beluga_core_microphone_forwarding_retry_result_t

    enum Failure: Error, Equatable { case layout, integerConversion, refused }
    enum Operation: UInt32, Equatable, Sendable {
        case eligible = 1, recordAttempt = 2, retryFailure = 3, exhaust = 4
    }
    enum FailureCategory: UInt32, Equatable, Sendable {
        case monitoringFailed = 1, outputUnavailable = 2, startFailed = 3
        case admissionFailed = 4, readinessFailed = 5, sourceMediaStalled = 6
        case formatUnsafe = 7, sharedClockUnsafe = 8, runtimeEnqueueFailed = 9
        case runtimeProgressStalled = 10, evidenceBridgeRefused = 11
    }
    enum RedriveAction: UInt32, Equatable, Sendable {
        case retain = 0, clear = 1, request = 2
    }
    struct Row: Equatable, Sendable {
        let count: Int
        let mayRetry: Bool
    }
    struct Evaluation {
        let config: Config
        let original: State
        let event: Event
        let result: Result
        let operation: Operation
        let originalRow: Row?
        let row: Row?
        let decision: Bool
        let redrive: RedriveAction

        fileprivate init(config: Config, original: State, event: Event, result: Result,
                         operation: Operation, originalRow: Row?, row: Row?,
                         decision: Bool, redrive: RedriveAction) {
            self.config = config; self.original = original; self.event = event; self.result = result
            self.operation = operation; self.originalRow = originalRow; self.row = row
            self.decision = decision; self.redrive = redrive
        }
    }

    /// No healthy vote is exposed by this fixed operation-four entry.
    /// This copied result neither admits a held driver frame nor retires resources.
    struct ExhaustBookkeeping {
        let config: Config
        let original: State
        let event: Event
        let result: Result
        let originalRow: Row?
        let row: Row?
        let redrive: RedriveAction

        fileprivate init(_ evaluation: Evaluation) {
            config = evaluation.config; original = evaluation.original
            event = evaluation.event; result = evaluation.result
            originalRow = evaluation.originalRow; row = evaluation.row
            redrive = evaluation.redrive
        }
    }

    static var layoutIsExact: Bool {
        MemoryLayout<Int>.size == 8 && UInt16(littleEndian: 1) == 1
            && exact(Config.self, 16, 8) && exact(State.self, 24, 8)
            && exact(Event.self, 16, 4) && exact(Result.self, 40, 8)
            && MemoryLayout<Config>.offset(of: \Config.abi_version) == 0
            && MemoryLayout<Config>.offset(of: \Config.reserved) == 4
            && MemoryLayout<Config>.offset(of: \Config.maximum_attempt_count) == 8
            && MemoryLayout<State>.offset(of: \State.abi_version) == 0
            && MemoryLayout<State>.offset(of: \State.present) == 4
            && MemoryLayout<State>.offset(of: \State.may_retry) == 8
            && MemoryLayout<State>.offset(of: \State.reserved) == 12
            && MemoryLayout<State>.offset(of: \State.count) == 16
            && MemoryLayout<Event>.offset(of: \Event.opcode) == 0
            && MemoryLayout<Event>.offset(of: \Event.failure_category) == 4
            && MemoryLayout<Event>.offset(of: \Event.bridge_faulted) == 8
            && MemoryLayout<Event>.offset(of: \Event.reserved) == 12
            && MemoryLayout<Result>.offset(of: \Result.state) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 24
            && MemoryLayout<Result>.offset(of: \Result.decision) == 28
            && MemoryLayout<Result>.offset(of: \Result.redrive_action) == 32
            && MemoryLayout<Result>.offset(of: \Result.reserved) == 36
    }

    /// bridgeFaulted is the caller's captured scalar, not an admission grant.
    /// Unused category/fault values still go through the fixed Rust validator.
    static func evaluate(maximumAttemptCount: Int, before: Row?, operation: Operation,
                         failureCategory: FailureCategory? = nil, bridgeFaulted: Bool) throws -> Evaluation {
        let input = try encode(maximumAttemptCount: maximumAttemptCount, before: before,
                               operation: operation, failureCategory: failureCategory,
                               bridgeFaulted: bridgeFaulted)
        let actual = beluga_core_microphone_forwarding_retry_step(input.config, input.before, input.event)
        return try verified(config: input.config, before: input.before, event: input.event, result: actual)
    }

    /// Cleanup-only pure bookkeeping remains callable after an unrelated evidence
    /// adapter faults. No stored evidenceBridge borrow, fault reset or fallback.
    static func exhaustBookkeeping(maximumAttemptCount: Int, before: Row?) throws -> ExhaustBookkeeping {
        ExhaustBookkeeping(try evaluate(maximumAttemptCount: maximumAttemptCount, before: before,
            operation: .exhaust, bridgeFaulted: false))
    }

#if DEBUG
    typealias PostResultMutation = (Config, State, Event, Result) -> Result

    /// Rejection-only fixture seam AFTER the genuine producer. Neither the
    /// production producer nor authoritative verifier can be injected.
    static func evaluateForTesting(maximumAttemptCount: Int, before: Row?, operation: Operation,
                                   failureCategory: FailureCategory? = nil, bridgeFaulted: Bool,
                                   postResultMutation: PostResultMutation) throws -> Evaluation {
        let input = try encode(maximumAttemptCount: maximumAttemptCount, before: before,
                               operation: operation, failureCategory: failureCategory,
                               bridgeFaulted: bridgeFaulted)
        return try evaluateRawForTesting(config: input.config, before: input.before, event: input.event,
                                         postResultMutation: postResultMutation)
    }

    /// Malformed copied input fixtures only; no native resource/guard constructor.
    static func evaluateRawForTesting(config: Config, before: State, event: Event,
                                      postResultMutation: PostResultMutation) throws -> Evaluation {
        try requireLayout()
        let actual = beluga_core_microphone_forwarding_retry_step(config, before, event)
        let result = postResultMutation(config, before, event, actual)
        return try verified(config: config, before: before, event: event, result: result)
    }
#endif

    private static func encode(maximumAttemptCount: Int, before: Row?, operation: Operation,
                               failureCategory: FailureCategory?, bridgeFaulted: Bool)
        throws -> (config: Config, before: State, event: Event) {
        try requireLayout()
        guard let maximum = Int64(exactly: maximumAttemptCount) else { throw Failure.integerConversion }
        let raw: State
        if let before {
            guard let count = Int64(exactly: before.count) else { throw Failure.integerConversion }
            raw = State(abi_version: 1, present: 1, may_retry: before.mayRetry ? 1 : 0,
                        reserved: 0, count: count)
        } else {
            raw = State(abi_version: 1, present: 0, may_retry: 0, reserved: 0, count: 0)
        }
        return (Config(abi_version: 1, reserved: 0, maximum_attempt_count: maximum), raw,
                Event(opcode: operation.rawValue, failure_category: failureCategory?.rawValue ?? 0,
                      bridge_faulted: bridgeFaulted ? 1 : 0, reserved: 0))
    }

    private static func verified(config: Config, before: State, event: Event, result: Result) throws -> Evaluation {
        guard beluga_core_microphone_forwarding_retry_result_is_valid(config, before, event, result) == 1,
              result.status == 1, result.reserved == 0, result.decision <= 1,
              let operation = Operation(rawValue: event.opcode),
              let redrive = RedriveAction(rawValue: result.redrive_action) else {
            throw Failure.refused
        }
        return Evaluation(config: config, original: before, event: event, result: result,
            operation: operation, originalRow: try decode(before), row: try decode(result.state),
            decision: result.decision == 1, redrive: redrive)
    }

    private static func decode(_ value: State) throws -> Row? {
        guard value.abi_version == 1, value.reserved == 0, value.may_retry <= 1 else {
            throw Failure.refused
        }
        if value.present == 0 {
            guard value.count == 0, value.may_retry == 0 else { throw Failure.refused }
            return nil
        }
        guard value.present == 1, value.count >= 1 else { throw Failure.refused }
        guard let count = Int(exactly: value.count) else { throw Failure.integerConversion }
        return Row(count: count, mayRetry: value.may_retry == 1)
    }

    private static func requireLayout() throws {
        guard layoutIsExact else { throw Failure.layout }
    }
    private static func exact<T>(_ type: T.Type, _ size: Int, _ alignment: Int) -> Bool {
        MemoryLayout<T>.size == size && MemoryLayout<T>.stride == size && MemoryLayout<T>.alignment == alignment
    }
}
