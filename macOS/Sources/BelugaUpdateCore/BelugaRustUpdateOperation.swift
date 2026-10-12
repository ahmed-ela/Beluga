import BelugaCore

/// Internal copied-result seam, not proof acquisition, authority, or persisted state.
struct BelugaRustUpdateOperationProducer: Sendable {
    typealias State = BelugaUpdateOperationState
    typealias Event = BelugaUpdateOperationEvent
    typealias Result = BelugaUpdateOperationResult
    typealias Step = @Sendable (UInt32, State, Event) -> Result

    let step: Step

    static let actual = Self(step: { abi, before, event in
        beluga_core_update_operation_step(abi, before, event)
    })
}

/// Closed copied-result decoding only. The native operation owns a value-field fault;
/// nonmutating queries cannot latch a fault or mutate copies of an operation.
enum BelugaRustUpdateOperationBridge {
    enum Opcode: UInt32 {
        case bindBroker = 0, bindCandidate, markPossiblyArmed, installedCompletion
        case issueChallenge, prepareReadinessEncoding, acceptReadiness
        case idle, cancelled, updaterFailed, brokerExited
        case queryInstallerMayRemainArmed, queryPermitsFenceRelease, queryPermitsRuntimeActivation

        var isQuery: Bool { rawValue >= Self.queryInstallerMayRemainArmed.rawValue }

        var requiresAcceptedResponse: Bool {
            switch self {
            case .idle, .cancelled, .updaterFailed, .brokerExited,
                 .queryInstallerMayRemainArmed, .queryPermitsFenceRelease, .queryPermitsRuntimeActivation:
                return true
            default: return false
            }
        }
    }

    enum Action: UInt32 {
        case none = 0, publishBroker, publishCandidate, markPossiblyArmed
        case acceptInstalledCompletion, publishChallenge, prepareReadinessEncoding
        case acceptReadiness, invalidateFreshness
    }

    struct Snapshot: Equatable, Sendable {
        let stage: UInt32
        let brokerPresent: Bool
        let candidatePresent: Bool
        let recordedReadinessPresent: Bool
        let installedFresh: Bool
        let readinessFresh: Bool
        let challengePresent: Bool

        var raw: BelugaRustUpdateOperationProducer.State {
            .init(abi_version: 1, reserved: 0, stage: stage,
                  broker_present: brokerPresent ? 1 : 0,
                  candidate_present: candidatePresent ? 1 : 0,
                  recorded_readiness_present: recordedReadinessPresent ? 1 : 0,
                  installed_fresh: installedFresh ? 1 : 0,
                  readiness_fresh: readinessFresh ? 1 : 0,
                  challenge_present: challengePresent ? 1 : 0, reserved_tail: 0)
        }

        init(stage: UInt32, brokerPresent: Bool, candidatePresent: Bool,
             recordedReadinessPresent: Bool, installedFresh: Bool, readinessFresh: Bool,
             challengePresent: Bool) {
            self.stage = stage
            self.brokerPresent = brokerPresent
            self.candidatePresent = candidatePresent
            self.recordedReadinessPresent = recordedReadinessPresent
            self.installedFresh = installedFresh
            self.readinessFresh = readinessFresh
            self.challengePresent = challengePresent
        }

        init?(_ value: BelugaRustUpdateOperationProducer.State) {
            guard value.abi_version == 1, value.reserved == 0, value.reserved_tail == 0,
                  value.stage <= 3, value.broker_present <= 1, value.candidate_present <= 1,
                  value.recorded_readiness_present <= 1, value.installed_fresh <= 1,
                  value.readiness_fresh <= 1, value.challenge_present <= 1 else { return nil }
            self.init(stage: value.stage, brokerPresent: value.broker_present == 1,
                      candidatePresent: value.candidate_present == 1,
                      recordedReadinessPresent: value.recorded_readiness_present == 1,
                      installedFresh: value.installed_fresh == 1,
                      readinessFresh: value.readiness_fresh == 1,
                      challengePresent: value.challenge_present == 1)
        }
    }

    struct Event {
        let opcode: Opcode
        let raw: BelugaRustUpdateOperationProducer.Event

        init(_ opcode: Opcode, _ fact0: Bool = false, _ fact1: Bool = false,
             _ fact2: Bool = false, _ fact3: Bool = false, _ fact4: Bool = false,
             _ fact5: Bool = false, _ fact6: Bool = false) {
            self.opcode = opcode
            raw = .init(opcode: opcode.rawValue, reserved: 0,
                        fact0: fact0 ? 1 : 0, fact1: fact1 ? 1 : 0,
                        fact2: fact2 ? 1 : 0, fact3: fact3 ? 1 : 0,
                        fact4: fact4 ? 1 : 0, fact5: fact5 ? 1 : 0,
                        fact6: fact6 ? 1 : 0, reserved_tail: 0)
        }
    }

    enum Decision {
        case accepted(Snapshot)
        case denied
        case unavailable
    }

    private enum Checked {
        case accepted(Snapshot, Bool)
        case denied
        case unavailable
    }

    static func plan(before: Snapshot, event: Event, expectedAction: Action,
                     producer: BelugaRustUpdateOperationProducer) -> Decision {
        guard !event.opcode.isQuery else { return .unavailable }
        switch checked(before: before, event: event, expectedAction: expectedAction,
                       producer: producer) {
        case let .accepted(candidate, _): return .accepted(candidate)
        case .denied: return .denied
        case .unavailable: return .unavailable
        }
    }

    /// nil is unavailable, not false. The native caller maps the hazard query to true
    /// and permission queries to false; treating unknown armedness as false is unsafe.
    static func query(before: Snapshot, opcode: Opcode,
                      producer: BelugaRustUpdateOperationProducer) -> Bool? {
        guard opcode.isQuery else { return nil }
        guard case let .accepted(_, predicate) = checked(
            before: before, event: Event(opcode), expectedAction: .none, producer: producer
        ) else { return nil }
        return predicate
    }

    private static func checked(before: Snapshot, event: Event, expectedAction: Action,
                                producer: BelugaRustUpdateOperationProducer) -> Checked {
        let result = producer.step(1, before.raw, event.raw)
        guard result.reserved == 0, result.decision <= 2, result.predicate <= 1,
              let action = Action(rawValue: result.action),
              let candidate = Snapshot(result.candidate_state) else {
            return .unavailable
        }
        if result.decision != 0 {
            guard action == .none, result.predicate == 0, candidate == before else {
                return .unavailable
            }
            // Well-shaped ordinary mutation denial does not poison the operation.
            // Typed observations and queries have no ordinary denial result. A denied
            // void invalidation cannot silently retain previously fresh release proof.
            return result.decision == 2 || event.opcode.requiresAcceptedResponse ? .unavailable : .denied
        }
        guard action == expectedAction,
              (event.opcode.isQuery ? candidate == before : result.predicate == 0) else {
            return .unavailable
        }
        // Rejection-only architectural custody fence: an extant operation never grants
        // native runtime activation, even if a corrupted result contains a closed true.
        guard event.opcode != .queryPermitsRuntimeActivation || result.predicate == 0 else {
            return .unavailable
        }
        return .accepted(candidate, result.predicate == 1)
    }
}
