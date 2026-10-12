import BelugaCore
import Foundation

enum ICERecoveryBridgeError: Error, Equatable, Sendable { case invalidResult }

struct BelugaRustICERecoveryProducer: Sendable {
    typealias Config = beluga_core_ice_recovery_config_t
    typealias State = beluga_core_ice_recovery_state_t
    typealias Event = beluga_core_ice_recovery_event_t
    typealias Initial = beluga_core_ice_recovery_init_result_t
    typealias Output = beluga_core_ice_recovery_result_t
    let initialize: @Sendable (UInt32, Config) -> Initial
    let step: @Sendable (UInt32, State, Event) -> Output
    static let actual = Self(
        initialize: { beluga_core_ice_recovery_initialize($0, $1) },
        step: { beluga_core_ice_recovery_step($0, $1, $2) }
    )
}

enum BelugaRustICERecoveryBoundary {
    typealias Config = BelugaRustICERecoveryProducer.Config
    typealias State = BelugaRustICERecoveryProducer.State
    typealias Event = BelugaRustICERecoveryProducer.Event
    typealias Initial = BelugaRustICERecoveryProducer.Initial
    typealias Output = BelugaRustICERecoveryProducer.Output

    static func stateWords(_ s: State) -> [UInt64] {
        [UInt64(s.abi_version), UInt64(s.phase), s.epoch, UInt64(bitPattern: s.attempts),
         UInt64(bitPattern: s.maximum_attempts), UInt64(s.exhaustion_delivered),
         UInt64(s.grace_positive), UInt64(s.cursor), UInt64(s.reserved)]
    }
    static func eventWords(_ e: Event) -> [UInt64] {
        [UInt64(e.abi_version), UInt64(e.opcode), e.workflow_epoch, UInt64(e.task_cancelled),
         UInt64(e.succeeded), UInt64(e.wait_kind), UInt64(e.reserved)]
    }
    static func layoutsAreExact() -> Bool {
        MemoryLayout<Config>.size == 16 && MemoryLayout<Config>.stride == 16
            && MemoryLayout<Config>.alignment == 8
            && MemoryLayout<State>.size == 48 && MemoryLayout<State>.stride == 48
            && MemoryLayout<State>.alignment == 8
            && MemoryLayout<Event>.size == 32 && MemoryLayout<Event>.stride == 32
            && MemoryLayout<Event>.alignment == 8
            && MemoryLayout<Initial>.size == 72 && MemoryLayout<Initial>.stride == 72
            && MemoryLayout<Initial>.alignment == 8
            && MemoryLayout<Output>.size == 152 && MemoryLayout<Output>.stride == 152
            && MemoryLayout<Output>.alignment == 8
    }
    /// Closed representation only, not recovery admission or a successor reducer.
    static func isClosed(_ s: State) -> Bool {
        guard s.abi_version == 1, s.maximum_attempts > 0, s.attempts >= 0,
              s.attempts <= s.maximum_attempts, s.exhaustion_delivered <= 1,
              s.grace_positive <= 1, s.reserved == 0 else { return false }
        switch s.phase {
        case 0: return s.attempts == 0 && s.exhaustion_delivered == 0 && s.cursor == 0
        case 1: return s.attempts == 0 && s.exhaustion_delivered == 0 && s.grace_positive == 1
            && [UInt32(1), 2, 4, 5].contains(s.cursor)
        case 2: return s.exhaustion_delivered == 0 && ((s.attempts == 0 && [UInt32(1), 2].contains(s.cursor))
            || (s.attempts > 0 && ([UInt32(3), 6].contains(s.cursor)
                || (s.cursor == 7 && s.attempts == s.maximum_attempts))))
        case 3: return s.attempts > 0 && s.exhaustion_delivered == 0
            && ([UInt32(4), 5, 6].contains(s.cursor)
                || (s.cursor == 7 && s.attempts == s.maximum_attempts))
        case 4: return s.attempts > 0 && s.attempts < s.maximum_attempts && s.exhaustion_delivered == 0
            && [UInt32(4), 5, 2].contains(s.cursor)
        case 5: return s.attempts == s.maximum_attempts && s.exhaustion_delivered == 1
            && [UInt32(8), 0].contains(s.cursor)
        case 6: return s.attempts == 0 && s.cursor == 0
        default: return false
        }
    }
    static func accepts(config: Config, output: Initial) -> Bool {
        let c = output.copied_config, s = output.candidate_state
        return layoutsAreExact() && config.maximum_attempts > 0 && config.grace_positive <= 1
            && config.reserved == 0 && output.status == 0 && output.reserved == 0
            && c.maximum_attempts == config.maximum_attempts && c.grace_positive == config.grace_positive
            && c.reserved == config.reserved && isClosed(s) && s.phase == 0 && s.epoch == 0
            && s.attempts == 0 && s.exhaustion_delivered == 0 && s.cursor == 0
            && s.maximum_attempts == config.maximum_attempts && s.grace_positive == config.grace_positive
    }
    /// Rejection-only custody. The arithmetic checks below correlate epoch/effect ownership;
    /// they never choose a recovery successor or return a successful native policy fallback.
    static func accepts(before: State, event: Event, output: Output) -> Bool {
        let after = output.candidate_state
        guard layoutsAreExact(), isClosed(before), isClosed(after), eventIsClosed(event), output.abi_version == 1,
              output.status == 0, output.reserved == 0, output.effect <= 14, output.flags <= 1,
              stateWords(output.copied_before) == stateWords(before),
              eventWords(output.copied_event) == eventWords(event),
              after.maximum_attempts == before.maximum_attempts,
              after.grace_positive == before.grace_positive else { return false }
        if output.flags == 1 {
            guard event.opcode <= 9, [UInt32(2), 3, 4, 5, 6, 8, 9].contains(event.opcode),
                  after.epoch == before.epoch &+ 1 else { return false }
        } else if after.epoch != before.epoch { return false }
        if event.opcode <= 9 {
            let mustAdvance = event.opcode == 9 || (before.phase != 6 && (
                [UInt32(2), 3, 6].contains(event.opcode)
                || (event.opcode == 4 && before.phase == 0)
                || ([UInt32(5), 8].contains(event.opcode) && [UInt32(0), 1].contains(before.phase))))
            guard output.flags == (mustAdvance ? 1 : 0) else { return false }
            if output.flags == 0 {
                return output.effect == 0 && stateWords(after) == stateWords(before)
            }
            guard event.opcode == 9 || before.phase != 6 else { return false }
            if event.opcode == 4 && before.phase != 0 { return false }
            if [UInt32(5), 8].contains(event.opcode) && ![UInt32(0), 1].contains(before.phase) { return false }
            guard after.attempts == 0, after.cursor == (output.effect == 1 ? 1 : 0) else { return false }
            switch event.opcode {
            case 2, 3: return output.effect == 0 && after.phase == 0 && after.exhaustion_delivered == 0
            case 4: return output.effect == 1 && after.phase == (before.grace_positive == 1 ? 1 : 2)
                && after.exhaustion_delivered == 0
            case 5, 8: return output.effect == 1 && after.phase == 2 && after.exhaustion_delivered == 0
            case 6, 9: return output.effect == 0 && after.phase == 6
                && after.exhaustion_delivered == before.exhaustion_delivered
            default: return false
            }
        }
        guard output.flags == 0 else { return false }
        if event.opcode == 17 {
            if event.workflow_epoch != before.epoch {
                return output.effect == 0 && stateWords(after) == stateWords(before)
            }
            return output.effect == 14 && after.cursor == 0
                && after.exhaustion_delivered == before.exhaustion_delivered
                && after.phase == ([UInt32(5), 6].contains(before.phase) ? before.phase : 0)
                && after.attempts == ([UInt32(5), 6].contains(before.phase) ? before.attempts : 0)
        }
        let current = event.workflow_epoch == before.epoch && event.task_cancelled == 0 && before.phase != 6
        if !current { return output.effect == 13 && stateWords(after) == stateWords(before) }
        // These relations reject corrupted effect/state custody before native I/O.
        // They never produce a successor, and the independent raw-C tests do not use this decoder.
        guard after.attempts == before.attempts || event.opcode == 11,
              after.exhaustion_delivered == before.exhaustion_delivered || event.opcode == 16 else { return false }
        switch event.opcode {
        case 10:
            return before.cursor == 1 && after.phase == before.phase && after.cursor == (before.phase == 1 ? 4 : 2)
                && output.effect == (before.phase == 1 ? 4 : 2)
        case 11:
            return before.cursor == 2 && before.attempts < before.maximum_attempts
                && after.attempts == before.attempts + 1 && after.phase == 2 && after.cursor == 3 && output.effect == 3
        case 12:
            return before.cursor == 3 && after.phase == (event.succeeded == 1 ? 3 : 2)
                && after.cursor == (event.succeeded == 1 ? 4 : 6) && output.effect == (event.succeeded == 1 ? 5 : 10)
        case 13:
            return before.cursor == 4 && after.phase == before.phase && after.cursor == 5
                && event.wait_kind == waitKind(before.phase) && output.effect == event.wait_kind + 6
        case 14:
            guard before.cursor == 5, event.wait_kind == waitKind(before.phase) else { return false }
            if event.succeeded == 0 { return output.effect == 13 && stateWords(after) == stateWords(before) }
            return after.phase == before.phase
                && after.cursor == (before.phase == 3 ? 6 : 2) && output.effect == (before.phase == 3 ? 10 : 2)
        case 15:
            return before.cursor == 6 && after.phase == (before.attempts == before.maximum_attempts ? before.phase : 4)
                && after.cursor == (before.attempts == before.maximum_attempts ? 7 : 4)
                && output.effect == (before.attempts == before.maximum_attempts ? 11 : 6)
        case 16:
            return before.cursor == 7 && before.attempts == before.maximum_attempts
                && before.exhaustion_delivered == 0 && after.phase == 5 && after.cursor == 8
                && after.exhaustion_delivered == 1 && output.effect == 12
        default: return false
        }
    }
    private static func waitKind(_ phase: UInt32) -> UInt32 {
        switch phase { case 1: return 1; case 3: return 2; case 4: return 3; default: return 0 }
    }
    private static func eventIsClosed(_ e: Event) -> Bool {
        guard e.abi_version == 1, e.opcode <= 17, e.task_cancelled <= 1, e.succeeded <= 1,
              e.reserved == 0 else { return false }
        if e.opcode <= 9 {
            return e.workflow_epoch == 0 && e.task_cancelled == 0 && e.succeeded == 0 && e.wait_kind == 0
        }
        if ![UInt32(12), 14].contains(e.opcode) && e.succeeded != 0 { return false }
        return [UInt32(13), 14].contains(e.opcode) ? (1...3).contains(e.wait_kind) : e.wait_kind == 0
    }
}

struct BelugaRustICERecoveryPolicy: Sendable {
    typealias State = BelugaRustICERecoveryProducer.State
    typealias Event = BelugaRustICERecoveryProducer.Event
    typealias Output = BelugaRustICERecoveryProducer.Output
    private(set) var state: State
    private(set) var faulted = false
    let producer: BelugaRustICERecoveryProducer

    init(policy: ICERecoveryCoordinator.Policy, producer: BelugaRustICERecoveryProducer = .actual) throws {
        let config = BelugaRustICERecoveryProducer.Config(maximum_attempts: Int64(policy.maximumAttempts),
            grace_positive: policy.disconnectedGrace > .zero ? 1 : 0, reserved: 0)
        let output = producer.initialize(1, config)
        guard BelugaRustICERecoveryBoundary.accepts(config: config, output: output) else {
            throw ICERecoveryBridgeError.invalidResult
        }
        self.producer = producer; state = output.candidate_state
    }

    mutating func transition(_ event: Event) throws -> Output {
        guard !faulted else { throw ICERecoveryBridgeError.invalidResult }
        let before = state
        let output = producer.step(1, before, event)
        guard BelugaRustICERecoveryBoundary.accepts(before: before, event: event, output: output) else {
            faulted = true // Leave the last accepted state intact; never synthesize idle/exhaustion.
            throw ICERecoveryBridgeError.invalidResult
        }
        state = output.candidate_state
        return output
    }
}
