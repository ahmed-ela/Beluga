import BelugaCore

/// Copied, stateless policy plans. Opaque commits, identities and crypto never cross this ABI.
internal enum BelugaRustPairingCommitBoundary {
    typealias State = beluga_core_pairing_commit_state_t
    typealias Event = beluga_core_pairing_commit_event_t
    typealias Output = beluga_core_pairing_commit_result_t

    enum Operation: UInt32, Sendable {
        case recoveryAction = 0, prepareProposal, prepareAcknowledgement
        case acceptAcknowledgement, prepareCompletion, markCompletionSent
        case acceptCompletion, acceptActivationAcknowledgement, validateStoredShape
    }

    enum Decision: UInt32, Sendable {
        case ready = 0, preAuthRejected, postAuthRejected, invalidStoredShape, invalidInput
    }

    enum Action: UInt32, Sendable {
        case none = 0, awaitProposal, issueProposal, exactCachedCommit, issueCompletion
        case mintProposal, mintAcknowledgement, mintCompletion, mintActivation
        case verifyStoredRecovery
    }

    enum Auth: UInt32, Sendable {
        case none = 0, proposal, acknowledgement, completion, activation
    }

    struct Plan: Sendable {
        let decision: Decision
        let action: Action
        let auth: Auth
        let candidatePairingState: RemotePairingPersistenceState
        let candidateRecoveryPhase: RemotePairingCommitPhase?
    }

    static func state(
        role: RemotePeerRole,
        pairingState: RemotePairingPersistenceState,
        recoveryPhase: RemotePairingCommitPhase?
    ) -> State {
        var value = State()
        value.abi_version = 1
        value.local_role = switch role {
        case .host: 0
        case .viewer: 1
        }
        value.pairing_state = switch pairingState {
        case .pending: 0
        case .acceptedIssued: 1
        case .acceptedReceived: 2
        case .active: 3
        }
        value.recovery_phase = switch recoveryPhase {
        case nil: 0
        case .proposal?: 1
        case .acknowledgement?: 2
        case .completion?: 3
        case .activationAcknowledgement?: 4
        }
        return value
    }

    static func event(_ operation: Operation, commitIDMatches: Bool = false) -> Event {
        var value = Event()
        value.opcode = operation.rawValue
        value.commit_id_matches = commitIDMatches ? 1 : 0
        return value
    }

    static func plan(
        before: State,
        event: Event,
        producer: BelugaRustPairingCommitProducer
    ) throws -> Plan {
        guard MemoryLayout<State>.size == 24, MemoryLayout<State>.stride == 24,
              MemoryLayout<State>.alignment == 4,
              MemoryLayout<Event>.size == 16, MemoryLayout<Event>.stride == 16,
              MemoryLayout<Event>.alignment == 4,
              MemoryLayout<Output>.size == 40, MemoryLayout<Output>.stride == 40,
              MemoryLayout<Output>.alignment == 4 else {
            throw RemoteSessionCoreError.invalidPairingCommitBridge
        }
        let output = producer.step(1, before, event)
        guard accepts(before: before, event: event, output: output),
              let decision = Decision(rawValue: output.decision),
              let action = Action(rawValue: output.action),
              let auth = Auth(rawValue: output.auth_phase),
              let phase = pairingState(output.candidate_state.pairing_state) else {
            throw RemoteSessionCoreError.invalidPairingCommitBridge
        }
        // Even an exactly correlated ABI/domain refusal is not an ordinary pairing refusal.
        guard decision != .invalidInput else {
            throw RemoteSessionCoreError.invalidPairingCommitBridge
        }
        return Plan(
            decision: decision,
            action: action,
            auth: auth,
            candidatePairingState: phase,
            candidateRecoveryPhase: recoveryPhase(output.candidate_state.recovery_phase)
        )
    }

    /// Rejection-only custody check. This never produces an accepted plan or fallback.
    /// It correlates the copied native snapshot with the operation, action, required
    /// authentication and candidate. Stored-shape constraints apply ONLY to opcode8.
    static func accepts(before: State, event: Event, output: Output) -> Bool {
        guard output.reserved == 0,
              let decision = Decision(rawValue: output.decision),
              let action = Action(rawValue: output.action),
              let auth = Auth(rawValue: output.auth_phase) else { return false }

        let unchanged = equal(before, output.candidate_state)
        guard valid(before), valid(event) else {
            return decision == .invalidInput && action == .none
                && auth == .none && unchanged
        }
        guard valid(output.candidate_state),
              output.candidate_state.local_role == before.local_role,
              let operation = Operation(rawValue: event.opcode) else { return false }
        if decision == .invalidInput {
            return action == .none && auth == .none && unchanged
        }

        let host = before.local_role == 0
        let phase = before.pairing_state
        let cache = before.recovery_phase
        let after = output.candidate_state
        func candidate(_ newPhase: UInt32, _ newCache: UInt32) -> Bool {
            after.pairing_state == newPhase && after.recovery_phase == newCache
        }
        func ready(_ expectedAction: Action, _ expectedAuth: Auth) -> Bool {
            decision == .ready && action == expectedAction && auth == expectedAuth
        }
        func refused() -> Bool {
            decision == .preAuthRejected && action == .none && auth == .none && unchanged
        }

        switch operation {
        case .recoveryAction:
            guard unchanged, decision == .ready, auth == .none else { return false }
            if cache != 0 { return action == .exactCachedCommit }
            switch phase {
            case 0: return action == (host ? .issueProposal : .awaitProposal)
            case 1: return action == .awaitProposal
            case 2: return action == .issueCompletion
            case 3: return action == .none
            default: return false
            }
        case .prepareProposal:
            guard host, phase == 0, cache == 0 || cache == 1 else { return refused() }
            if cache == 1 {
                return unchanged && ready(.exactCachedCommit, .none)
            }
            return candidate(0, 1) && ready(.mintProposal, .none)
        case .prepareAcknowledgement:
            guard !host, phase == 0 || phase == 1 else { return refused() }
            if phase == 1 && cache != 0 {
                // Original issued replay permits any known cached phase after actual proposal auth.
                return unchanged && ready(.exactCachedCommit, .proposal)
            }
            return candidate(1, 2) && ready(.mintAcknowledgement, .proposal)
        case .acceptAcknowledgement:
            guard host, phase == 0 || phase == 2 || phase == 3 else { return refused() }
            guard ready(.none, .acknowledgement) else { return false }
            return phase == 0 ? candidate(2, 0) : unchanged
        case .prepareCompletion:
            guard host, phase == 2 || phase == 3 else { return refused() }
            if phase == 3 {
                guard cache == 0 else { return refused() }
                // The native completion is ephemeral: do not reopen active recovery.
                return unchanged && ready(.mintCompletion, .none)
            }
            if cache == 3 { return unchanged && ready(.exactCachedCommit, .none) }
            guard cache == 0 else { return refused() }
            return candidate(2, 3) && ready(.mintCompletion, .none)
        case .markCompletionSent:
            guard host, event.commit_id_matches == 1,
                  (phase == 2 && cache == 3) || (phase == 3 && cache == 0) else {
                return refused()
            }
            return unchanged && ready(.none, .none)
        case .acceptCompletion:
            guard !host else { return refused() }
            if phase == 3 {
                if cache == 4 {
                    return unchanged && ready(.exactCachedCommit, .completion)
                }
                return unchanged && decision == .postAuthRejected
                    && action == .none && auth == .completion
            }
            guard phase == 1 else { return refused() }
            return candidate(3, 4) && ready(.mintActivation, .completion)
        case .acceptActivationAcknowledgement:
            guard host, phase == 2 || phase == 3 else { return refused() }
            return candidate(3, 0) && ready(.none, .activation)
        case .validateStoredShape:
            let admitted: Bool
            switch (before.local_role, phase, cache) {
            case (0, 0, 0), (0, 0, 1), (0, 2, 0), (0, 2, 3),
                 (0, 3, 0), (1, 0, 0), (1, 1, 2), (1, 3, 4):
                admitted = true
            default: admitted = false
            }
            guard unchanged, auth == .none else { return false }
            if !admitted { return decision == .invalidStoredShape && action == .none }
            return ready(cache == 0 ? .none : .verifyStoredRecovery, .none)
        }
    }

    static func equal(_ left: State, _ right: State) -> Bool {
        left.abi_version == right.abi_version && left.reserved == right.reserved
            && left.local_role == right.local_role && left.pairing_state == right.pairing_state
            && left.recovery_phase == right.recovery_phase && left.reserved_tail == right.reserved_tail
    }

    private static func valid(_ value: State) -> Bool {
        value.abi_version == 1 && value.reserved == 0 && value.reserved_tail == 0
            && value.local_role <= 1 && value.pairing_state <= 3 && value.recovery_phase <= 4
    }

    private static func valid(_ value: Event) -> Bool {
        value.reserved == 0 && value.reserved_tail == 0 && value.opcode <= 8
            && value.commit_id_matches <= 1 && (value.opcode == 5 || value.commit_id_matches == 0)
    }

    private static func pairingState(_ value: UInt32) -> RemotePairingPersistenceState? {
        switch value {
        case 0: .pending
        case 1: .acceptedIssued
        case 2: .acceptedReceived
        case 3: .active
        default: nil
        }
    }

    private static func recoveryPhase(_ value: UInt32) -> RemotePairingCommitPhase? {
        switch value {
        case 1: .proposal
        case 2: .acknowledgement
        case 3: .completion
        case 4: .activationAcknowledgement
        default: nil
        }
    }
}

/// Injection is per call, never encoded or retained by the paired record.
internal struct BelugaRustPairingCommitProducer: Sendable {
    typealias State = BelugaRustPairingCommitBoundary.State
    typealias Event = BelugaRustPairingCommitBoundary.Event
    typealias Output = BelugaRustPairingCommitBoundary.Output
    typealias Step = @Sendable (_ abiVersion: UInt32, _ state: State, _ event: Event) -> Output

    let step: Step

    static let actual = Self(step: { beluga_core_pairing_commit_step($0, $1, $2) })
}
