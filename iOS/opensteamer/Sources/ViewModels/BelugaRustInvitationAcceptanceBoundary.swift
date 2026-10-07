import BelugaCore

enum BelugaRustInvitationAcceptanceBoundary {
    typealias State = beluga_core_invitation_acceptance_state_t
    typealias Event = beluga_core_invitation_acceptance_event_t
    typealias Output = beluga_core_invitation_acceptance_result_t
    typealias CopiedResultProvider = @MainActor (UInt32, State, Event) -> Output

    static var idle: State { State(abi_version: 1, flags: 0) }
    static func words(_ state: State) -> [UInt32] { [state.abi_version, state.flags] }
    static func same(_ lhs: State, _ rhs: State) -> Bool { words(lhs) == words(rhs) }
    static func valid(_ state: State) -> Bool {
        state.abi_version == 1 && [0, 5, 7, 13, 15].contains(state.flags)
    }

    static func coreOutput(_ abi: UInt32, _ state: State, _ event: Event) -> Output {
        beluga_core_invitation_acceptance_step(abi, state, event)
    }

    private static func noCallback(_ output: Output) -> Bool {
        output.callback_kind == 0 && output.prepared_flags == 0 && output.completion_succeeded == 0
            && same(output.state, output.callback_success_state)
    }

    private static func validNativeEvent(_ event: Event) -> Bool {
        guard [0, 1, 2, 4].contains(event.opcode),
              event.prepared_kind == 0, event.prepared_flags == 0,
              event.owner_matches == 0, event.callback_outcome == 0 else { return false }
        switch event.opcode {
        case 0:
            return event.generation_matches == 0 && event.phase == 0
                && event.admission_callback_present <= 1
        case 1, 2:
            return event.generation_matches <= 1 && event.admission_callback_present == 0
        case 4:
            return event.generation_matches <= 1 && event.phase == 0
                && event.admission_callback_present == 0
        default:
            return false
        }
    }

    /// Validates a copied result's permission and ownership correlations.
    /// It never chooses a disposition or invokes an effect; Rust remains the policy authority.
    /// Ack opcode3 is deliberately unavailable in this native path: success uses the prevalidated candidate.
    static func accepts(before: State, event: Event, output: Output) -> Bool {
        guard valid(before), valid(output.state), valid(output.callback_success_state),
              validNativeEvent(event), output.completion_succeeded == 0 else { return false }
        let unchanged = same(before, output.state)
        let armed = before.flags & 1 != 0
        let current = armed && event.generation_matches == 1
        let admissionOpen = current && before.flags & 8 == 0

        switch output.status {
        case 0: // Applied: only arm, exact cancellation, or a nil admission's consumption.
            guard noCallback(output) else { return false }
            switch event.opcode {
            case 0:
                let presence: UInt32 = event.admission_callback_present == 1 ? 7 : 5
                return output.state.flags == presence
            case 1:
                return admissionOpen && event.phase == 1 && before.flags & 2 == 0
                    && output.state.flags == (before.flags | 8)
            case 4:
                return current && same(output.state, idle)
            default:
                return false
            }
        case 1: // Ignored claims cannot hide an eligible operation or lose any native authority.
            guard unchanged, noCallback(output) else { return false }
            switch event.opcode {
            case 1: return !admissionOpen
            case 2, 4: return !current
            default: return false
            }
        case 2: // NeedsCallback preserves before and offers an exact candidate, not early success.
            guard unchanged, output.prepared_flags == before.flags else { return false }
            switch output.callback_kind {
            case 1:
                return event.opcode == 1 && admissionOpen && event.phase == 1 && before.flags & 2 != 0
                    && output.callback_success_state.flags == (before.flags | 8)
            case 2:
                return event.opcode == 2 && current && event.phase == 2 && before.flags & 4 != 0
                    && same(output.callback_success_state, idle)
            default:
                return false
            }
        case 3: // Original pairingIsNotRecoverable, only after the actual current admission guard.
            return event.opcode == 1 && admissionOpen && [0, 2].contains(event.phase)
                && unchanged && noCallback(output)
        case 4: // Original pairingIsNotActive, only after the current completion owner/action guard.
            return event.opcode == 2 && current && [0, 1].contains(event.phase)
                && unchanged && noCallback(output)
        default: // No ack outcomes, unknown ABI/status, or manufactured bridge success.
            return false
        }
    }
}
