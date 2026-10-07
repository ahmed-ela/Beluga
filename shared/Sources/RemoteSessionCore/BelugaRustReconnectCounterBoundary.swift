import BelugaCore

/// Stateless copied-output validation. Only the built core proposes a successor;
/// this boundary cannot construct a fallback, reset a counter, or perform effects.
internal enum BelugaRustReconnectCounterBoundary {
    typealias State = beluga_core_reconnect_counters_state_t
    typealias Event = beluga_core_reconnect_counters_event_t
    typealias Output = beluga_core_reconnect_counters_result_t

    static func state(nextOutbound: UInt64, highestAccepted: UInt64) -> State {
        var state = State()
        state.abi_version = 1
        state.reserved = 0
        state.next_outbound = nextOutbound
        state.highest_accepted = highestAccepted
        return state
    }

    static func event(opcode: UInt32, requestSequence: UInt64) -> Event {
        var event = Event()
        event.opcode = opcode
        event.reserved = 0
        event.request_sequence = requestSequence
        return event
    }

    static func same(_ lhs: State, _ rhs: State) -> Bool {
        lhs.abi_version == rhs.abi_version && lhs.reserved == rhs.reserved
            && lhs.next_outbound == rhs.next_outbound
            && lhs.highest_accepted == rhs.highest_accepted
    }

    /// Correlates an output with the complete original input, without trusting
    /// a plausible decision label or allowing a producer to write the other slot.
    static func accepts(before: State, event: Event, output: Output) -> Bool {
        guard before.abi_version == 1, before.reserved == 0,
              event.reserved == 0,
              event.opcode == 1 || (event.opcode == 0 && event.request_sequence == 0),
              output.reserved == 0,
              output.candidate_state.abi_version == 1,
              output.candidate_state.reserved == 0 else { return false }
        let candidate = output.candidate_state
        switch output.decision {
        case 0:
            if event.opcode == 0 {
                guard before.next_outbound < UInt64.max else { return false }
                return candidate.next_outbound == before.next_outbound + 1
                    && candidate.highest_accepted == before.highest_accepted
            }
            return event.request_sequence > before.highest_accepted
                && candidate.highest_accepted == event.request_sequence
                && candidate.next_outbound == before.next_outbound
        case 1:
            return event.opcode == 0 && before.next_outbound == UInt64.max
                && same(before, candidate)
        case 2:
            return event.opcode == 1 && event.request_sequence <= before.highest_accepted
                && same(before, candidate)
        default:
            // Invalid or unknown output cannot be valid for these native inputs.
            return false
        }
    }

    /// Called only after native activation, role/identity and request-authentication
    /// checks. The candidate is not committed until the native constructor succeeds.
    static func propose(
        nextOutbound: UInt64,
        highestAccepted: UInt64,
        opcode: UInt32,
        requestSequence: UInt64,
        producer: BelugaRustReconnectCounterProducer
    ) throws -> State {
        let before = state(nextOutbound: nextOutbound, highestAccepted: highestAccepted)
        let input = event(opcode: opcode, requestSequence: requestSequence)
        guard opcode == 1 || (opcode == 0 && requestSequence == 0) else {
            throw RemoteSessionCoreError.invalidReconnectCounterBridge
        }
        let output = producer.step(1, before, input)
        guard accepts(before: before, event: input, output: output) else {
            throw RemoteSessionCoreError.invalidReconnectCounterBridge
        }
        switch output.decision {
        case 0: return output.candidate_state
        case 1: throw RemoteSessionCoreError.sequenceExhausted
        case 2: throw RemoteSessionCoreError.staleReconnectSequence
        default: throw RemoteSessionCoreError.invalidReconnectCounterBridge
        }
    }
}

/// A copied scalar test seam, never stored in a Codable native record. Production
/// defaults always call the actual built C export and no initial function exists.
internal struct BelugaRustReconnectCounterProducer: Sendable {
    typealias State = BelugaRustReconnectCounterBoundary.State
    typealias Event = BelugaRustReconnectCounterBoundary.Event
    typealias Output = BelugaRustReconnectCounterBoundary.Output
    typealias Step = @Sendable (_ abiVersion: UInt32, _ state: State, _ event: Event) -> Output

    let step: Step

    static let actual = Self(step: { beluga_core_reconnect_counters_step($0, $1, $2) })
}
