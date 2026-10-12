import BelugaCore
import Foundation

/// Pure state machine for invitation, availability, and media exchange ownership.
///
/// Exchange identifiers are scoped independently: availability may reconnect while
/// an already authorized media exchange finishes. Invalid ownership transitions fail
/// closed rather than silently replacing an active peer.
struct WorldwideHostLifecycle: Equatable, Sendable {
    /// Durable high-level state of the worldwide host process.
    enum RunState: Equatable, Sendable {
        case idle
        case inviting
        case pairedAvailable
        case stopped
    }

    private var core = beluga_core_host_lifecycle_initial()
    private var exchangeValues: [UInt64: String] = [:]
    private var activeExchangeValue: String?
    private var mediaExchangeValue: String?
    private var nextExchangeToken: UInt64 = 1

    var runState: RunState {
        guard core.abi_version == 1 else { return .stopped }
        switch core.run_state {
        case 0: return .idle
        case 1: return .inviting
        case 2: return .pairedAvailable
        default: return .stopped
        }
    }
    var activeExchangeID: String? {
        runState == .pairedAvailable && core.active_token != 0 ? activeExchangeValue : nil
    }
    var mediaExchangeID: String? {
        runState == .pairedAvailable && core.media_token != 0 ? mediaExchangeValue : nil
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.runState == rhs.runState && lhs.activeExchangeID == rhs.activeExchangeID
            && lhs.mediaExchangeID == rhs.mediaExchangeID
    }

    /// Begins invitation or durable availability according to persisted pairing state.
    mutating func start(hasPairedViewer: Bool) throws {
        try requireTransition(opcode: 0, argument: hasPairedViewer ? 1 : 0)
    }

    /// Crosses from one-time invitation into reusable paired availability.
    mutating func durablePairingRecordAvailable() throws {
        try requireTransition(opcode: 1)
    }

    /// Claims one bounded, nonempty Worker exchange as the active availability peer.
    mutating func availabilityReady(exchangeID: String) throws {
        try requireTransition(opcode: 2, exchangeID: exchangeID)
    }

    /// Marks media active only for the exchange that currently owns availability.
    mutating func mediaStarted(exchangeID: String) throws {
        try requireTransition(opcode: 3, exchangeID: exchangeID)
    }

    /// Releases availability only when the departing exchange still owns it.
    mutating func availabilityPeerLeft(exchangeID: String) {
        _ = transition(opcode: 4, exchangeID: exchangeID)
    }

    /// Releases media only when the ending exchange still owns it.
    mutating func mediaEnded(exchangeID: String) {
        _ = transition(opcode: 5, exchangeID: exchangeID)
    }

    /// Enters the terminal state and clears all ephemeral exchange ownership.
    mutating func stop() {
        _ = transition(opcode: 6)
    }

    private mutating func requireTransition(opcode: UInt32, argument: UInt32 = 0,
                                           exchangeID: String? = nil) throws {
        guard transition(opcode: opcode, argument: argument, exchangeID: exchangeID) else {
            throw WorldwideHostLifecycleError.invalidTransition
        }
    }

    private mutating func transition(opcode: UInt32, argument: UInt32 = 0,
                                     exchangeID: String? = nil) -> Bool {
        var event = beluga_core_host_lifecycle_event_t()
        event.opcode = opcode
        event.argument = argument
        if let exchangeID {
            event.original_utf8_length = UInt64(exchangeID.utf8.count)
            // Swift String equality includes canonical Unicode equivalence. Preserve that
            // native value contract; Rust receives only bounded, nonzero ownership tokens.
            if let existing = exchangeValues.first(where: { $0.value == exchangeID }) {
                event.exchange_token = existing.key
            } else {
                guard nextExchangeToken != 0 else { return false }
                event.exchange_token = nextExchangeToken
                exchangeValues[nextExchangeToken] = exchangeID
                let successor = nextExchangeToken.addingReportingOverflow(1)
                nextExchangeToken = successor.overflow ? 0 : successor.partialValue
            }
        }
        let result = beluga_core_host_lifecycle_step(1, core, event)
        let successor = result.state
        let ownerTokens = [successor.active_token, successor.media_token].filter { $0 != 0 }
        guard successor.abi_version == 1, successor.run_state <= 3, result.status <= 3,
              successor.run_state == 2 || ownerTokens.isEmpty,
              ownerTokens.allSatisfy({ exchangeValues[$0] != nil }) else {
            core.abi_version = 1
            core.run_state = 3
            core.active_token = 0
            core.media_token = 0
            exchangeValues.removeAll()
            activeExchangeValue = nil
            mediaExchangeValue = nil
            return false
        }
        if successor.active_token == 0 {
            activeExchangeValue = nil
        } else if successor.active_token != core.active_token {
            activeExchangeValue = exchangeID
        }
        if successor.media_token == 0 {
            mediaExchangeValue = nil
        } else if successor.media_token != core.media_token {
            mediaExchangeValue = exchangeID
        }
        core = successor
        exchangeValues = exchangeValues.filter { ownerTokens.contains($0.key) }
        return result.status == 0 || result.status == 2
    }
}


/// Signals an attempted transition that violates worldwide-host ownership rules.
enum WorldwideHostLifecycleError: LocalizedError, Equatable {
    case invalidTransition

    var errorDescription: String? {
        "The worldwide host lifecycle transition is invalid."
    }
}
