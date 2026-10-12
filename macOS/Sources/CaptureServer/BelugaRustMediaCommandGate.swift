import BelugaCore

/// Copied scalar policy for one native media-command owner. The caller owns its
/// NSLock, String/Set membership and all actual command/handoff effects.
struct BelugaRustMediaCommandGate: Sendable {
    typealias State = beluga_core_media_command_gate_state_t
    typealias Event = beluga_core_media_command_gate_event_t
    typealias Result = beluga_core_media_command_gate_result_t
    // This seam can only alter a result AFTER the actual Rust export was called.
    // The authoritative verifier is never injectable or replaced.
    typealias ResultMutation = @Sendable (State, Event, Result) -> Result

    private(set) var rawState = State(
        abi_version: 1, is_open: 0, lifecycle: 0, command_epoch: 0
    )
    private(set) var hasNativeFault = false
    private let resultMutation: ResultMutation?

    init(resultMutation: ResultMutation? = nil) {
        self.resultMutation = resultMutation
        hasNativeFault = !Self.layoutIsExact
    }

    static var layoutIsExact: Bool {
        UInt16(littleEndian: 1) == 1
            && MemoryLayout<State>.size == 24 && MemoryLayout<State>.stride == 24
            && MemoryLayout<State>.alignment == 8
            && MemoryLayout<Event>.size == 32 && MemoryLayout<Event>.stride == 32
            && MemoryLayout<Event>.alignment == 8
            && MemoryLayout<Result>.size == 40 && MemoryLayout<Result>.stride == 40
            && MemoryLayout<Result>.alignment == 8
            && MemoryLayout<State>.offset(of: \State.abi_version) == 0
            && MemoryLayout<State>.offset(of: \State.is_open) == 4
            && MemoryLayout<State>.offset(of: \State.lifecycle) == 8
            && MemoryLayout<State>.offset(of: \State.command_epoch) == 16
            && MemoryLayout<Event>.offset(of: \Event.opcode) == 0
            && MemoryLayout<Event>.offset(of: \Event.context_is_current) == 4
            && MemoryLayout<Event>.offset(of: \Event.reserved0) == 8
            && MemoryLayout<Event>.offset(of: \Event.reserved1) == 12
            && MemoryLayout<Event>.offset(of: \Event.candidate_lifecycle) == 16
            && MemoryLayout<Event>.offset(of: \Event.candidate_command_epoch) == 24
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.allowed) == 8
            && MemoryLayout<Result>.offset(of: \Result.reserved) == 12
            && MemoryLayout<Result>.offset(of: \Result.state) == 16
    }

    mutating func open() -> Bool {
        apply(Self.event(0)) != nil
    }

    mutating func close() -> Bool {
        apply(Self.event(1)) != nil
    }

    mutating func invalidateCommands() -> Bool {
        apply(Self.event(2)) != nil
    }

    mutating func lifecycleIsCurrent(_ candidate: UInt64) -> Bool {
        apply(Self.event(3, lifecycle: candidate))?.allowed == 1
    }

    mutating func capture(contextIsCurrent: Bool) -> Bool {
        apply(Self.event(4, contextIsCurrent: contextIsCurrent))?.allowed == 1
    }

    mutating func admits(lifecycle: UInt64, commandEpoch: UInt64,
                         contextIsCurrent: Bool) -> Bool {
        apply(Self.event(5, contextIsCurrent: contextIsCurrent,
                         lifecycle: lifecycle, commandEpoch: commandEpoch))?.allowed == 1
    }

    private static func event(_ opcode: UInt32, contextIsCurrent: Bool = false,
                              lifecycle: UInt64 = 0, commandEpoch: UInt64 = 0) -> Event {
        Event(opcode: opcode, context_is_current: contextIsCurrent ? 1 : 0,
              reserved0: 0, reserved1: 0, candidate_lifecycle: lifecycle,
              candidate_command_epoch: commandEpoch)
    }

    private mutating func apply(_ event: Event) -> Result? {
        guard !hasNativeFault else { return nil }
        guard Self.layoutIsExact else {
            hasNativeFault = true
            return nil
        }
        let before = rawState
        let actual = beluga_core_media_command_gate_step(before, event)
        let result = resultMutation?(before, event, actual) ?? actual
        guard beluga_core_media_command_gate_result_is_valid(before, event, result) == 1 else {
            // Keep the last verified scalars, including legal zero-after-wrap values.
            // Canonical ABI denial is never a reset or replacement-owner grant.
            hasNativeFault = true
            return nil
        }
        rawState = result.state
        return result
    }
}
