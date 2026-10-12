// Rust-owned copied retry policy; native output custody can only reject.
import BelugaCore

enum WorldwideSafeOutputInvariantRetryBridgeError: Error, Equatable, Sendable {
    case invalidInitial
    case invalidTransition(opcode: UInt32)
}

/// Rejection-only copied-result custody. Never returns a Swift-derived successor.
enum BelugaRustSafeOutputRetryBoundary {
    typealias Config = beluga_core_safe_output_retry_config_t
    typealias State = beluga_core_safe_output_retry_state_t
    typealias Output = beluga_core_safe_output_retry_result_t

    static var layoutIsExact: Bool {
        MemoryLayout<Int>.size == 8
            && MemoryLayout<Config>.size == 32 && MemoryLayout<Config>.stride == 32
            && MemoryLayout<Config>.alignment == 8
            && MemoryLayout<State>.size == 56 && MemoryLayout<State>.stride == 56
            && MemoryLayout<State>.alignment == 8
            && MemoryLayout<Output>.size == 64 && MemoryLayout<Output>.stride == 64
            && MemoryLayout<Output>.alignment == 8
    }

    static func validState(_ state: State) -> Bool {
        guard layoutIsExact, state.abi_version == 1, state.reserved == 0,
              state.maximum_failed_attempt_count > 0, state.maximum_backoff_tick_count > 0,
              state.capped_cooldown_tick_count > 0, state.failed_attempt_count >= 0,
              state.failed_attempt_count <= state.maximum_failed_attempt_count,
              state.backoff_tick_count >= 0, state.cooldown_tick_count >= 0,
              state.cooldown_tick_count <= state.capped_cooldown_tick_count else { return false }
        if state.failed_attempt_count == state.maximum_failed_attempt_count {
            return state.backoff_tick_count == 0
        }
        guard state.cooldown_tick_count == 0 else { return false }
        if state.failed_attempt_count == 0 { return state.backoff_tick_count == 0 }
        let shift = min(state.failed_attempt_count - 1, 30)
        return state.backoff_tick_count <= min(Int64(1) << shift, state.maximum_backoff_tick_count)
    }

    static func same(_ left: State, _ right: State) -> Bool {
        left.abi_version == right.abi_version && left.reserved == right.reserved
            && sameConfiguration(left, right)
            && left.failed_attempt_count == right.failed_attempt_count
            && left.backoff_tick_count == right.backoff_tick_count
            && left.cooldown_tick_count == right.cooldown_tick_count
    }
    static func sameConfiguration(_ left: State, _ right: State) -> Bool {
        left.maximum_failed_attempt_count == right.maximum_failed_attempt_count
            && left.maximum_backoff_tick_count == right.maximum_backoff_tick_count
            && left.capped_cooldown_tick_count == right.capped_cooldown_tick_count
    }

    static func acceptsInitial(request: Config, output: Output) -> Bool {
        let state = output.state
        return request.abi_version == 1 && request.reserved == 0
            && validState(state) && output.status == 1 && output.tick_decision == 0
            && state.maximum_failed_attempt_count == max(1, request.maximum_failed_attempt_count)
            && state.maximum_backoff_tick_count == max(1, request.maximum_backoff_tick_count)
            && state.capped_cooldown_tick_count == max(1, request.capped_cooldown_tick_count)
            && state.failed_attempt_count == 0 && state.backoff_tick_count == 0
            && state.cooldown_tick_count == 0
    }

    /// This validates a proposal after the actual C call. It can only reject a
    /// corrupted copied result. It cannot manufacture a successful transition.
    static func accepts(before: State, opcode: UInt32, output: Output) -> Bool {
        let state = output.state
        guard validState(before), validState(state), sameConfiguration(before, state),
              output.status == 1 else { return false }
        switch opcode {
        case 1:
            if before.failed_attempt_count == before.maximum_failed_attempt_count {
                if before.cooldown_tick_count > 0 {
                    return output.tick_decision == 1
                        && state.failed_attempt_count == before.failed_attempt_count
                        && state.backoff_tick_count == 0
                        && state.cooldown_tick_count == before.cooldown_tick_count - 1
                }
                return output.tick_decision == 2 && state.failed_attempt_count == 0
                    && state.backoff_tick_count == 0 && state.cooldown_tick_count == 0
            }
            if before.backoff_tick_count > 0 {
                return output.tick_decision == 1
                    && state.failed_attempt_count == before.failed_attempt_count
                    && state.backoff_tick_count == before.backoff_tick_count - 1
                    && state.cooldown_tick_count == 0
            }
            return output.tick_decision == 2 && same(before, state)
        case 2:
            guard output.tick_decision == 0 else { return false }
            if before.failed_attempt_count == before.maximum_failed_attempt_count {
                return same(before, state)
            }
            // Valid before-state + strictly below its Int64 maximum makes this
            // addition representable. No saturating numeric semantics are added.
            let nextFailure = before.failed_attempt_count + 1
            guard state.failed_attempt_count == nextFailure else { return false }
            if nextFailure == before.maximum_failed_attempt_count {
                return state.backoff_tick_count == 0
                    && state.cooldown_tick_count == before.capped_cooldown_tick_count
            }
            return state.backoff_tick_count == min(Int64(1) << min(nextFailure - 1, 30),
                    before.maximum_backoff_tick_count)
                && state.cooldown_tick_count == 0
        case 3:
            return output.tick_decision == 0 && state.failed_attempt_count == 0
                && state.backoff_tick_count == 0 && state.cooldown_tick_count == 0
        default: return false
        }
    }
}

struct BelugaRustSafeOutputRetryProducer: Sendable {
    typealias Boundary = BelugaRustSafeOutputRetryBoundary
    let initial: @Sendable (Boundary.Config) -> Boundary.Output
    let transition: @Sendable (Boundary.State, UInt32) -> Boundary.Output
    static let actual = Self(
        initial: { beluga_core_safe_output_retry_initialize($0) },
        transition: { beluga_core_safe_output_retry_transition($0, $1) }
    )
}

/// Copied scalar facade. All ordinary-domain
/// semantics remain Rust-owned; invalid copied results create a sticky error.
struct WorldwideSafeOutputInvariantRetryPolicy: Equatable, Sendable {
    private var core: BelugaRustSafeOutputRetryBoundary.State
    private let producer: BelugaRustSafeOutputRetryProducer
    private(set) var bridgeFault: WorldwideSafeOutputInvariantRetryBridgeError?

    var maximumFailedAttemptCount: Int { Int(core.maximum_failed_attempt_count) }
    var maximumBackoffTickCount: Int { Int(core.maximum_backoff_tick_count) }
    var cappedCooldownTickCount: Int { Int(core.capped_cooldown_tick_count) }
    var failedAttemptCount: Int { Int(core.failed_attempt_count) }
    var backoffTickCount: Int { Int(core.backoff_tick_count) }
    var cooldownTickCount: Int { Int(core.cooldown_tick_count) }
    var hasBridgeFault: Bool { bridgeFault != nil }

    init(maximumFailedAttemptCount: Int = 6, maximumBackoffTickCount: Int = 16,
         cappedCooldownTickCount: Int = 60,
         producer: BelugaRustSafeOutputRetryProducer = .actual) {
        self.producer = producer
        var request = BelugaRustSafeOutputRetryBoundary.Config()
        request.abi_version = 1
        request.maximum_failed_attempt_count = Int64(maximumFailedAttemptCount)
        request.maximum_backoff_tick_count = Int64(maximumBackoffTickCount)
        request.capped_cooldown_tick_count = Int64(cappedCooldownTickCount)

        // A property initializer cannot throw. Retain the original intended zero
        // counters/config as NONAUTHORIZING diagnostic custody if C initial fails.
        // The sticky fault prevents every transition; this is not a Swift fallback
        // initial policy, is never allowed to grant an attempt, and cannot reset.
        var intended = BelugaRustSafeOutputRetryBoundary.State()
        intended.abi_version = 1
        intended.maximum_failed_attempt_count = max(1, request.maximum_failed_attempt_count)
        intended.maximum_backoff_tick_count = max(1, request.maximum_backoff_tick_count)
        intended.capped_cooldown_tick_count = max(1, request.capped_cooldown_tick_count)
        core = intended
        guard BelugaRustSafeOutputRetryBoundary.layoutIsExact else {
            bridgeFault = .invalidInitial
            return
        }
        let output = producer.initial(request)
        guard BelugaRustSafeOutputRetryBoundary.acceptsInitial(request: request, output: output) else {
            bridgeFault = .invalidInitial
            return
        }
        core = output.state
        bridgeFault = nil
    }

    static func == (left: Self, right: Self) -> Bool {
        BelugaRustSafeOutputRetryBoundary.same(left.core, right.core)
            && left.bridgeFault == right.bridgeFault
    }
    mutating func shouldAttemptOnCurrentTick() throws -> Bool {
        try requireTransition(opcode: 1).tick_decision == 2
    }
    mutating func recordFailure() throws { _ = try requireTransition(opcode: 2) }
    mutating func reset() throws { _ = try requireTransition(opcode: 3) }

    private mutating func requireTransition(opcode: UInt32) throws
        -> BelugaRustSafeOutputRetryBoundary.Output {
        if let bridgeFault { throw bridgeFault }
        let output = producer.transition(core, opcode)
        guard BelugaRustSafeOutputRetryBoundary.accepts(before: core, opcode: opcode, output: output) else {
            let fault = WorldwideSafeOutputInvariantRetryBridgeError.invalidTransition(opcode: opcode)
            bridgeFault = fault
            // Last exact native-owned configuration and counters remain unchanged.
            throw fault
        }
        core = output.state
        return output
    }
}
