import BelugaCore

/// Copied-scalar validation only. This never constructs an accepted successor,
/// grants reset authority, or retries a rejected output from an empty window.
internal enum BelugaRustSignalingReplayBoundary {
    typealias State = beluga_core_signaling_replay_state_t
    typealias Output = beluga_core_signaling_replay_result_t

    static func acceptsInitial(_ state: State) -> Bool {
        state.abi_version == 1 && state.has_highest == 0
            && state.highest == 0 && state.bitmap == 0
    }

    static func accepts(before: State, sequence: UInt64, output: Output) -> Bool {
        guard valid(before), valid(output.state), output.reserved == 0,
              output.decision <= 2 else { return false }
        let after = output.state
        if before.has_highest == 0 {
            return output.decision == 0 && after.has_highest == 1
                && after.highest == sequence && after.bitmap == 1
        }
        if sequence > before.highest {
            let advance = sequence - before.highest
            let expectedBits: UInt64 = advance >= SignalingReplayGuard.windowSize
                ? 1 : (before.bitmap << advance) | 1
            return output.decision == 0 && after.has_highest == 1
                && after.highest == sequence && after.bitmap == expectedBits
        }
        let age = before.highest - sequence
        if age >= SignalingReplayGuard.windowSize {
            return output.decision == 2 && same(before, after)
        }
        let mask = UInt64(1) << age
        if before.bitmap & mask != 0 {
            return output.decision == 1 && same(before, after)
        }
        return output.decision == 0 && after.has_highest == 1
            && after.highest == before.highest && after.bitmap == (before.bitmap | mask)
    }

    static func same(_ lhs: State, _ rhs: State) -> Bool {
        lhs.abi_version == rhs.abi_version && lhs.has_highest == rhs.has_highest
            && lhs.highest == rhs.highest && lhs.bitmap == rhs.bitmap
    }

    private static func valid(_ state: State) -> Bool {
        guard state.abi_version == 1 else { return false }
        switch state.has_highest {
        case 0: return state.highest == 0 && state.bitmap == 0
        case 1:
            guard state.bitmap & 1 == 1 else { return false }
            return state.highest >= 63 || state.bitmap >> (state.highest + 1) == 0
        default: return false
        }
    }
}

/// The bounded test seam exchanges only copied scalar values. Defaults always
/// call the built Rust exports; it cannot authenticate, reset a client, or persist.
internal struct BelugaRustSignalingReplayProducer: Sendable {
    typealias State = BelugaRustSignalingReplayBoundary.State
    typealias Output = BelugaRustSignalingReplayBoundary.Output
    typealias Initial = @Sendable () -> State
    typealias Step = @Sendable (_ abiVersion: UInt32, _ state: State, _ sequence: UInt64) -> Output

    let initial: Initial
    let step: Step

    static let actual = Self(
        initial: { beluga_core_signaling_replay_initial() },
        step: { beluga_core_signaling_replay_step($0, $1, $2) }
    )
}

/// Internal, synchronous read-only evidence of the guard's actual stored value.
/// It carries no owner identifiers, ciphertext, credentials or reset capability.
internal struct BelugaRustSignalingReplayObservation: Sendable {
    enum Kind: Equatable, Sendable { case initialized, accepted, rejected, faulted }
    typealias Observer = @Sendable (BelugaRustSignalingReplayObservation) -> Void

    let kind: Kind
    let stored: BelugaRustSignalingReplayBoundary.State
    let sequence: UInt64?
    let error: RemoteSessionCoreError?
}

/// A bounded sliding replay window permitting limited network reordering.
/// Only Rust produces successor state. A malformed bridge result stays closed
/// until the native session owner explicitly constructs a genuinely new guard.
public struct SignalingReplayGuard: Sendable {
    public static let windowSize: UInt64 = 64

    private var core: BelugaRustSignalingReplayBoundary.State
    private var bridgeFaulted: Bool
    private let producer: BelugaRustSignalingReplayProducer
    private let observer: BelugaRustSignalingReplayObservation.Observer?

    public init() {
        self.init(producer: .actual)
    }

    internal init(
        producer: BelugaRustSignalingReplayProducer,
        observer: BelugaRustSignalingReplayObservation.Observer? = nil
    ) {
        self.producer = producer
        self.observer = observer
        let initial = producer.initial()
        core = initial
        bridgeFaulted = !BelugaRustSignalingReplayBoundary.acceptsInitial(initial)
        observe(bridgeFaulted ? .faulted : .initialized, sequence: nil,
                error: bridgeFaulted ? .invalidSignalingReplayBridge : nil)
    }

    /// Duplicate and outside-window rejection preserve the exact prior state.
    public mutating func accept(sequence: UInt64) throws {
        guard !bridgeFaulted else {
            observe(.faulted, sequence: sequence, error: .invalidSignalingReplayBridge)
            throw RemoteSessionCoreError.invalidSignalingReplayBridge
        }
        let output = producer.step(1, core, sequence)
        guard BelugaRustSignalingReplayBoundary.accepts(before: core, sequence: sequence, output: output) else {
            bridgeFaulted = true
            observe(.faulted, sequence: sequence, error: .invalidSignalingReplayBridge)
            throw RemoteSessionCoreError.invalidSignalingReplayBridge
        }
        switch output.decision {
        case 0:
            core = output.state
            observe(.accepted, sequence: sequence, error: nil)
        case 1:
            observe(.rejected, sequence: sequence, error: .replayedSequence)
            throw RemoteSessionCoreError.replayedSequence
        case 2:
            observe(.rejected, sequence: sequence, error: .sequenceOutsideReplayWindow)
            throw RemoteSessionCoreError.sequenceOutsideReplayWindow
        default:
            bridgeFaulted = true
            observe(.faulted, sequence: sequence, error: .invalidSignalingReplayBridge)
            throw RemoteSessionCoreError.invalidSignalingReplayBridge
        }
    }

    internal var copiedStateForTesting: BelugaRustSignalingReplayBoundary.State { core }
    internal var bridgeFaultedForTesting: Bool { bridgeFaulted }

    private func observe(
        _ kind: BelugaRustSignalingReplayObservation.Kind,
        sequence: UInt64?, error: RemoteSessionCoreError?
    ) {
        observer?(.init(kind: kind, stored: core, sequence: sequence, error: error))
    }
}
