import BelugaCore
import Foundation

/// Copied scalar retry proposals only. Native owns the socket.
struct BelugaRustAvailabilityRetryProducer: Sendable {
    typealias State = beluga_core_availability_retry_state_t
    typealias Event = beluga_core_availability_retry_event_t
    typealias Output = beluga_core_availability_retry_result_t
    let step: @Sendable (UInt32, State, Event) -> Output

    static let actual = Self { beluga_core_availability_retry_step($0, $1, $2) }
}

enum BelugaRustAvailabilityRetryBoundary {
    typealias State = BelugaRustAvailabilityRetryProducer.State
    typealias Event = BelugaRustAvailabilityRetryProducer.Event
    typealias Output = BelugaRustAvailabilityRetryProducer.Output

    static func isClosed(_ state: State) -> Bool {
        state.abi_version == 1 && state.reserved == 0
            && [UInt32(1), 2, 4, 8, 16, 30].contains(state.next_delay_seconds)
            && (state.has_validated_connection == 0
                || (state.has_validated_connection == 1 && state.next_delay_seconds == 1))
    }

    /// Rejection-only correlation; never constructs a successful successor/delay.
    static func accepts(before: State, event: Event, output: Output) -> Bool {
        guard MemoryLayout<State>.size == 16, MemoryLayout<State>.stride == 16,
              MemoryLayout<State>.alignment == 4,
              MemoryLayout<Event>.size == 8, MemoryLayout<Event>.stride == 8,
              MemoryLayout<Event>.alignment == 4,
              MemoryLayout<Output>.size == 32, MemoryLayout<Output>.stride == 32,
              MemoryLayout<Output>.alignment == 4,
              isClosed(before), isClosed(output.candidate_state), event.reserved == 0,
              output.reserved == 0, output.became_validated <= 1,
              output.decision == event.opcode else { return false }
        switch event.opcode {
        case 0:
            return output.candidate_state.next_delay_seconds == 1
                && output.candidate_state.has_validated_connection == 1
                && output.became_validated == (before.has_validated_connection == 0 ? 1 : 0)
                && output.retry_delay_seconds == 0
        case 1:
            return output.candidate_state.next_delay_seconds == min(before.next_delay_seconds * 2, 30)
                && output.candidate_state.has_validated_connection == 0
                && output.became_validated == 0
                && output.retry_delay_seconds == before.next_delay_seconds
        default:
            return false
        }
    }
}

/// Rust-backed replacement of the original two-scalar value policy.
/// The new throws disposition is explicit: invalid output has no honest Int/Bool result.
struct WorldwideAvailabilityRetryPolicy: Equatable, Sendable {
    typealias State = BelugaRustAvailabilityRetryProducer.State
    private var core: State
    private var bridgeFaulted = false

    init() {
        // Preserve the literal original initial state; no initializer export/reset effect exists.
        core = State(abi_version: 1, next_delay_seconds: 1, has_validated_connection: 0, reserved: 0)
    }

    var nextDelaySeconds: Int { Int(core.next_delay_seconds) }
    var hasValidatedConnection: Bool { core.has_validated_connection == 1 }
    var copiedStateForTesting: State { core }
    var bridgeFaultedForTesting: Bool { bridgeFaulted }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.core.abi_version == rhs.core.abi_version
            && lhs.core.next_delay_seconds == rhs.core.next_delay_seconds
            && lhs.core.has_validated_connection == rhs.core.has_validated_connection
            && lhs.core.reserved == rhs.core.reserved
            && lhs.bridgeFaulted == rhs.bridgeFaulted
    }

    /// Only parsed waiting/ready after successful native handling/current-client checks qualifies.
    mutating func observedValidAvailabilityState(
        using producer: BelugaRustAvailabilityRetryProducer = .actual
    ) throws -> Bool {
        try transition(opcode: 0, using: producer).became_validated == 1
    }

    /// Return the actual Rust-proposed prior delay, committing only its validated successor.
    mutating func delayAfterFailure(
        using producer: BelugaRustAvailabilityRetryProducer = .actual
    ) throws -> Int {
        Int(try transition(opcode: 1, using: producer).retry_delay_seconds)
    }

    private mutating func transition(opcode: UInt32, using producer: BelugaRustAvailabilityRetryProducer)
        throws -> BelugaRustAvailabilityRetryProducer.Output {
        guard !bridgeFaulted else { throw WorldwideAvailabilityRetryError.invalidBridge }
        let event = BelugaRustAvailabilityRetryProducer.Event(opcode: opcode, reserved: 0)
        let before = core
        let output = producer.step(1, before, event)
        guard BelugaRustAvailabilityRetryBoundary.accepts(before: before, event: event, output: output) else {
            // Preserve the actual prior scalars; fault is terminal, never replace them with a reset.
            bridgeFaulted = true
            throw WorldwideAvailabilityRetryError.invalidBridge
        }
        core = output.candidate_state
        return output
    }
}

enum WorldwideAvailabilityRetryError: LocalizedError, Equatable, Sendable {
    case invalidBridge
    var errorDescription: String? { "The worldwide availability retry policy bridge is invalid." }
}
