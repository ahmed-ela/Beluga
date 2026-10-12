import BelugaCore

/// By-value scalar transcript. The coordinator retains immutable native proofs;
/// Rust alone decides phase, binding, generation, projections and custody actions.
struct BelugaRustScreenSuspension: Equatable, Sendable {
    typealias State = beluga_core_screen_suspension_state_t
    typealias Event = beluga_core_screen_suspension_event_t
    typealias Result = beluga_core_screen_suspension_result_t
    // Only the copied output AFTER the actual export can be changed by this seam.
    // Neither the actual producer nor its recomputing verifier is injectable.
    typealias ResultMutation = @Sendable (State, Event, Result) -> Result

    private(set) var rawState = Self.initialState
    private(set) var queryFlags: UInt32 = 0
    private(set) var hasNativeFault = false
    private let resultMutation: ResultMutation?

    /// A verified result is not yet published. Native custody must first be
    /// constructed and checked against its successor in a temporary value.
    struct VerifiedStep: Sendable {
        let result: Result
        fileprivate let before: State
        fileprivate let event: Event
        fileprivate init(result: Result, before: State, event: Event) {
            self.result = result
            self.before = before
            self.event = event
        }
    }

    init(resultMutation: ResultMutation? = nil) {
        self.resultMutation = resultMutation
        guard let initial = evaluated(Self.event(0)) else {
            hasNativeFault = true
            return
        }
        _ = publish(initial)
    }

    static var initialState: State {
        State(abi_version: 1, phase: 0, next_generation: 1,
              screen_request_id: 0, suspension_generation: 0,
              peer_generation: 0, visibility_epoch: 0, recovery_epoch: 0,
              prior_screen_request_id: 0, prior_suspension_generation: 0,
              cover_confirmed: 0, inactive_confirmed: 0, custody_mask: 0,
              reserved: 0)
    }

    static var layoutIsExact: Bool {
        UInt16(littleEndian: 1) == 1
            && MemoryLayout<State>.size == 88 && MemoryLayout<State>.stride == 88
            && MemoryLayout<State>.alignment == 8
            && MemoryLayout<Event>.size == 64 && MemoryLayout<Event>.stride == 64
            && MemoryLayout<Event>.alignment == 8
            && MemoryLayout<Result>.size == 128 && MemoryLayout<Result>.stride == 128
            && MemoryLayout<Result>.alignment == 8
            && MemoryLayout<State>.offset(of: \State.abi_version) == 0
            && MemoryLayout<State>.offset(of: \State.phase) == 4
            && MemoryLayout<State>.offset(of: \State.next_generation) == 8
            && MemoryLayout<State>.offset(of: \State.screen_request_id) == 16
            && MemoryLayout<State>.offset(of: \State.suspension_generation) == 24
            && MemoryLayout<State>.offset(of: \State.peer_generation) == 32
            && MemoryLayout<State>.offset(of: \State.visibility_epoch) == 40
            && MemoryLayout<State>.offset(of: \State.recovery_epoch) == 48
            && MemoryLayout<State>.offset(of: \State.prior_screen_request_id) == 56
            && MemoryLayout<State>.offset(of: \State.prior_suspension_generation) == 64
            && MemoryLayout<State>.offset(of: \State.cover_confirmed) == 72
            && MemoryLayout<State>.offset(of: \State.inactive_confirmed) == 76
            && MemoryLayout<State>.offset(of: \State.custody_mask) == 80
            && MemoryLayout<State>.offset(of: \State.reserved) == 84
            && MemoryLayout<Event>.offset(of: \Event.opcode) == 0
            && MemoryLayout<Event>.offset(of: \Event.flags) == 4
            && MemoryLayout<Event>.offset(of: \Event.native_facts) == 8
            && MemoryLayout<Event>.offset(of: \Event.reserved) == 12
            && MemoryLayout<Event>.offset(of: \Event.screen_request_id) == 16
            && MemoryLayout<Event>.offset(of: \Event.peer_generation) == 24
            && MemoryLayout<Event>.offset(of: \Event.visibility_epoch) == 32
            && MemoryLayout<Event>.offset(of: \Event.recovery_epoch) == 40
            && MemoryLayout<Event>.offset(of: \Event.notice_screen_request_id) == 48
            && MemoryLayout<Event>.offset(of: \Event.notice_generation) == 56
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.accepted) == 8
            && MemoryLayout<Result>.offset(of: \Result.custody_action) == 12
            && MemoryLayout<Result>.offset(of: \Result.state) == 16
            && MemoryLayout<Result>.offset(of: \Result.query_flags) == 104
            && MemoryLayout<Result>.offset(of: \Result.reserved) == 108
            && MemoryLayout<Result>.offset(of: \Result.produced_notice_screen_request_id) == 112
            && MemoryLayout<Result>.offset(of: \Result.produced_notice_generation) == 120
    }

    /// Temporary evaluation serves both the mutating coordinator and its
    /// deliberately nonmutating queries. A caller chooses whether denial latches.
    func evaluated(_ event: Event) -> VerifiedStep? {
        guard !hasNativeFault, Self.layoutIsExact else { return nil }
        let before = rawState
        let actual = beluga_core_screen_suspension_step(before, event)
        let result = resultMutation?(before, event, actual) ?? actual
        guard beluga_core_screen_suspension_result_is_valid(before, event, result) == 1 else {
            return nil
        }
        return VerifiedStep(result: result, before: before, event: event)
    }

    /// Called only on a temporary core after the matching native-custody proposal
    /// has passed. A stale proof cannot be transplanted to another scalar state.
    mutating func publish(_ step: VerifiedStep) -> Bool {
        guard !hasNativeFault, Self.layoutIsExact,
              Self.statesEqual(rawState, step.before),
              beluga_core_screen_suspension_result_is_valid(
                step.before, step.event, step.result
              ) == 1 else {
            hasNativeFault = true
            return false
        }
        rawState = step.result.state
        queryFlags = step.result.query_flags
        return true
    }

    mutating func latchFault() {
        // Fault changes no verified scalar, cached projection or native custody.
        hasNativeFault = true
    }

    static func bindingIsValid(peer: UInt64, visibility: UInt64, recovery: UInt64) -> Bool {
        guard layoutIsExact else { return false }
        let before = initialState
        let event = Event(opcode: 17, flags: 0, native_facts: 0, reserved: 0,
                          screen_request_id: 0, peer_generation: peer,
                          visibility_epoch: visibility, recovery_epoch: recovery,
                          notice_screen_request_id: 0, notice_generation: 0)
        let result = beluga_core_screen_suspension_step(before, event)
        return beluga_core_screen_suspension_result_is_valid(before, event, result) == 1
            && result.accepted == 1
    }

    static func event(_ opcode: UInt32) -> Event {
        Event(opcode: opcode, flags: 0, native_facts: 0, reserved: 0,
              screen_request_id: 0, peer_generation: 0, visibility_epoch: 0,
              recovery_epoch: 0, notice_screen_request_id: 0, notice_generation: 0)
    }

    static func statesEqual(_ lhs: State, _ rhs: State) -> Bool {
        lhs.abi_version == rhs.abi_version && lhs.phase == rhs.phase
            && lhs.next_generation == rhs.next_generation
            && lhs.screen_request_id == rhs.screen_request_id
            && lhs.suspension_generation == rhs.suspension_generation
            && lhs.peer_generation == rhs.peer_generation
            && lhs.visibility_epoch == rhs.visibility_epoch
            && lhs.recovery_epoch == rhs.recovery_epoch
            && lhs.prior_screen_request_id == rhs.prior_screen_request_id
            && lhs.prior_suspension_generation == rhs.prior_suspension_generation
            && lhs.cover_confirmed == rhs.cover_confirmed
            && lhs.inactive_confirmed == rhs.inactive_confirmed
            && lhs.custody_mask == rhs.custody_mask && lhs.reserved == rhs.reserved
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        statesEqual(lhs.rawState, rhs.rawState)
            && lhs.queryFlags == rhs.queryFlags
            && lhs.hasNativeFault == rhs.hasNativeFault
        // The immutable test callback is not transcript state or native custody.
    }
}
