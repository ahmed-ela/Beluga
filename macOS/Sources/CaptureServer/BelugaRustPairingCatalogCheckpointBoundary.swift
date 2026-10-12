import BelugaCore

/// Rejection-only copied-value custody. Native UUIDs, persisted snapshots,
/// process ownership and successful storage returns never cross this boundary.
enum BelugaRustPairingCatalogCheckpointBoundary {
    typealias State = beluga_core_pairing_catalog_checkpoint_state_t
    typealias Event = beluga_core_pairing_catalog_checkpoint_event_t
    typealias Output = beluga_core_pairing_catalog_checkpoint_result_t

    static func acceptsInitial(_ state: State) -> Bool {
        state.abi_version == 1 && state.flags == 0
    }

    static func valid(_ state: State, bindingPresent: Bool) -> Bool {
        state.abi_version == 1 && state.flags & ~UInt32(3) == 0
            && (state.flags & 1 != 0) == bindingPresent
    }

    static func same(_ lhs: State, _ rhs: State) -> Bool {
        lhs.abi_version == rhs.abi_version && lhs.flags == rhs.flags
    }

    static func accepts(before: State, event: Event, output: Output) -> Bool {
        guard before.abi_version == 1, before.flags & ~UInt32(3) == 0,
              event.opcode <= 3, event.owner_valid <= 1,
              event.binding_matches <= 1, event.snapshot_matches <= 1,
              output.candidate_state.abi_version == 1 else { return false }
        let bound = before.flags & 1 != 0
        let revoked = before.flags & 2 != 0
        let admitted: Bool
        let candidateFlags: UInt32
        switch event.opcode {
        case 0:
            admitted = !revoked && event.owner_valid == 1 && !bound
            candidateFlags = before.flags | 1
        case 1:
            admitted = !revoked && event.owner_valid == 1 && bound && event.binding_matches == 1
            candidateFlags = before.flags
        case 2:
            admitted = true
            candidateFlags = before.flags | 2
        case 3:
            admitted = event.snapshot_matches == 1
            candidateFlags = before.flags
        default: return false
        }
        // These checks can only reject a Rust proposal. They never produce an
        // admitted candidate, reset state or fall back to a native reducer.
        if admitted {
            return output.decision == 0 && output.candidate_state.flags == candidateFlags
        }
        return output.decision == 1 && same(before, output.candidate_state)
    }
}

/// Internal test seam contains copied scalars only, not storage or owner authority.
struct BelugaRustPairingCatalogCheckpointProducer: Sendable {
    typealias Boundary = BelugaRustPairingCatalogCheckpointBoundary
    typealias Initial = @Sendable () -> Boundary.State
    typealias Step = @Sendable (UInt32, Boundary.State, Boundary.Event) -> Boundary.Output
    let initial: Initial
    let step: Step

    static let actual = Self(
        initial: { beluga_core_pairing_catalog_checkpoint_initial() },
        step: { beluga_core_pairing_catalog_checkpoint_step($0, $1, $2) }
    )
}
