import BelugaCore
import Foundation

/// Validates custody across the copied-scalar ABI. This does not choose a
/// transition or provide a fallback ledger: only the Rust reducer does that.
/// A foreign result cannot discard native authority without its exact cleanup.
enum BelugaRustHandoffBoundary {
    typealias State = beluga_core_handoff_transactions_state_t
    typealias Event = beluga_core_handoff_transactions_event_t
    typealias Output = beluga_core_handoff_transactions_result_t

    static func accepts(before: State, event: Event, output: Output) -> Bool {
        let after = output.state
        guard valid(before), valid(after), event.reserved == 0,
              output.status <= 2, output.reserved == 0,
              output.effects & ~UInt32(7) == 0 else { return false }
        let unchanged = sameState(before, after)
        if output.status == 1 {
            return event.opcode != 5 && unchanged && output.effects == 0 && output.revoked_receipt == 0
                && output.completed_offer == 0 && output.completed_result == 0
        }
        guard output.status == 2 ? unchanged : !unchanged else { return false }

        let changedHost = before.host_phase != after.host_phase
            || before.host_receipt != after.host_receipt
            || before.host_envelope != after.host_envelope
            || before.host_result != after.host_result
        let changedViewer = before.viewer_envelope != after.viewer_envelope
            || before.viewer_offer != after.viewer_offer
        let retiresHost = before.host_phase != 0 && changedHost
        let retiresViewer = before.viewer_envelope != 0 && changedViewer
        let revokesHost = output.effects & 1 != 0
        let returnsReply = output.effects & 2 != 0
        let completesViewer = output.effects & 4 != 0
        if output.status == 2 && !returnsReply {
            guard event.opcode == 5, before.host_phase == 0,
                  before.viewer_envelope == 0, output.effects == 0 else { return false }
        }
        guard revokesHost == retiresHost,
              output.revoked_receipt == (retiresHost ? before.host_receipt : 0),
              completesViewer == retiresViewer,
              !changedHost || event.opcode == 0 || event.opcode == 1 || event.opcode == 5,
              !changedViewer || event.opcode == 2 || event.opcode == 3 || event.opcode == 4 || event.opcode == 5
        else { return false }

        if returnsReply {
            guard event.opcode == 1, after.host_phase == 2,
                  before.host_phase != 0,
                  before.host_receipt == event.receipt_token,
                  before.host_envelope == event.envelope_token,
                  after.host_receipt == before.host_receipt,
                  after.host_envelope == before.host_envelope,
                  after.host_result == event.result,
                  (output.status == 0 && before.host_phase == 1)
                    || (output.status == 2 && before.host_phase == 2) else { return false }
        } else if event.opcode == 1 && output.status == 0 {
            return false
        }

        if completesViewer {
            guard after.viewer_envelope == 0, after.viewer_offer == 0,
                  output.completed_offer == before.viewer_offer else { return false }
            switch event.opcode {
            case 3:
                guard event.envelope_token == before.viewer_envelope,
                      (1...3).contains(event.result),
                      output.completed_result == event.result else { return false }
            case 4:
                guard event.offer_token == before.viewer_offer,
                      output.completed_result == 3 else { return false }
            case 5:
                guard output.completed_result == 3 else { return false }
            default: return false
            }
        } else if output.completed_offer != 0 || output.completed_result != 0 {
            return false
        }

        // Newly admitted native values must be the exact values offered by the
        // adapter, and cannot already carry a fabricated cached result.
        if output.status == 0 && event.opcode == 0 {
            guard after.host_phase == 1, after.host_receipt == event.receipt_token,
                  after.host_envelope == event.envelope_token else { return false }
        }
        if output.status == 0 && event.opcode == 2 {
            guard before.viewer_envelope == 0, event.argument == 1,
                  after.viewer_envelope == event.envelope_token,
                  after.viewer_offer == event.offer_token else { return false }
        }
        if output.status == 0 && event.opcode == 5 {
            guard after.host_phase == 0, after.viewer_envelope == 0 else { return false }
        }
        return true
    }

    private static func valid(_ state: State) -> Bool {
        guard state.abi_version == 1, state.reserved == 0,
              (state.viewer_envelope == 0) == (state.viewer_offer == 0) else { return false }
        switch state.host_phase {
        case 0: return state.host_receipt == 0 && state.host_envelope == 0 && state.host_result == 0
        case 1: return state.host_receipt != 0 && state.host_envelope != 0 && state.host_result == 0
        case 2: return state.host_receipt != 0 && state.host_envelope != 0 && (1...3).contains(state.host_result)
        default: return false
        }
    }

    private static func sameState(_ lhs: State, _ rhs: State) -> Bool {
        lhs.abi_version == rhs.abi_version && lhs.host_phase == rhs.host_phase
            && lhs.host_receipt == rhs.host_receipt && lhs.host_envelope == rhs.host_envelope
            && lhs.host_result == rhs.host_result && lhs.reserved == rhs.reserved
            && lhs.viewer_envelope == rhs.viewer_envelope && lhs.viewer_offer == rhs.viewer_offer
    }
}

/// The peer actor retains native values; Rust owns the independent transaction slots.
/// Copied scalar effects may revoke an exact receipt or return a correlated outcome,
/// never perform a native Pause. Native String/UUID equality is not replaced by hashes.
struct MediaHandoffTransactions {
    private struct HostBinding {
        let receipt: UInt64
        let envelope: UInt64
        let commit: WebRTCReceivedMediaHandoffCommit
    }
    private struct ViewerBinding {
        let envelope: UInt64
        let offer: UInt64
        let commit: WebRTCMediaHandoffCommitEnvelope
    }

    private var core = beluga_core_handoff_transactions_initial()
    private var host: HostBinding?
    private var viewer: ViewerBinding?
    private var nextToken: UInt64 = 1

    var hostCommit: WebRTCReceivedMediaHandoffCommit? { host?.commit }
    var viewerCommit: WebRTCMediaHandoffCommitEnvelope? { viewer?.commit }
    var hostIsBusy: Bool { core.host_phase == 1 }
    var hostReply: WebRTCMediaHandoffCompletionEnvelope? {
        guard core.host_phase == 2, let host,
              let result = Self.nativeResult(core.host_result) else { return nil }
        return .init(commit: host.commit.envelope, result: result)
    }

    mutating func admitHost(_ commit: WebRTCReceivedMediaHandoffCommit) -> Bool {
        guard let receipt = receiptToken(commit.receiptID),
              let envelope = envelopeToken(commit.envelope) else { return false }
        var event = beluga_core_handoff_transactions_event_t()
        event.opcode = 0; event.receipt_token = receipt; event.envelope_token = envelope
        return step(event, newHost: .init(receipt: receipt, envelope: envelope, commit: commit))?.status == 0
    }

    mutating func finishHost(_ commit: WebRTCReceivedMediaHandoffCommit,
                             result: WebRTCMediaHandoffResult) -> WebRTCMediaHandoffCompletionEnvelope? {
        guard let receipt = receiptToken(commit.receiptID),
              let envelope = envelopeToken(commit.envelope) else { return nil }
        var event = beluga_core_handoff_transactions_event_t()
        event.opcode = 1; event.receipt_token = receipt; event.envelope_token = envelope
        event.result = Self.coreResult(result)
        guard let output = step(event), output.effects & 2 != 0 else { return nil }
        return hostReply
    }

    mutating func beginViewer(_ commit: WebRTCMediaHandoffCommitEnvelope) -> Bool {
        guard let envelope = envelopeToken(commit), let offer = offerToken(commit.id) else { return false }
        var event = beluga_core_handoff_transactions_event_t()
        event.opcode = 2; event.argument = commit.isValid ? 1 : 0
        event.envelope_token = envelope; event.offer_token = offer
        return step(event, newViewer: .init(envelope: envelope, offer: offer, commit: commit))?.status == 0
    }

    mutating func receiveCompletion(_ reply: WebRTCMediaHandoffCompletionEnvelope) -> WebRTCMediaHandoffCompletion? {
        guard let envelope = envelopeToken(reply.commit) else { return nil }
        var event = beluga_core_handoff_transactions_event_t()
        event.opcode = 3; event.envelope_token = envelope; event.result = Self.coreResult(reply.result)
        let original = viewer?.commit
        let output = step(event)
        return Self.completedViewer(output, original: original)
    }

    mutating func expireViewer(id: UUID) -> WebRTCMediaHandoffCompletion? {
        guard let offer = offerToken(id) else { return nil }
        var event = beluga_core_handoff_transactions_event_t()
        event.opcode = 4; event.offer_token = offer
        let original = viewer?.commit
        let output = step(event)
        return Self.completedViewer(output, original: original)
    }

    mutating func clear() -> WebRTCMediaHandoffCompletion? {
        var event = beluga_core_handoff_transactions_event_t()
        event.opcode = 5
        let original = viewer?.commit
        let output = step(event)
        return Self.completedViewer(output, original: original)
    }

    // An effect consumes only the viewer value present at the exact step. It cannot
    // borrow a replacement viewer or manufacture a successful native outcome.
    private static func completedViewer(_ output: beluga_core_handoff_transactions_result_t?,
                                        original: WebRTCMediaHandoffCommitEnvelope?) -> WebRTCMediaHandoffCompletion? {
        guard let output, output.effects & 4 != 0, let original,
              let result = Self.nativeResult(output.completed_result) else { return nil }
        return .init(id: original.id, result: result)
    }

    private mutating func token() -> UInt64? {
        guard nextToken != 0 else { return nil }
        let value = nextToken
        let successor = nextToken.addingReportingOverflow(1)
        nextToken = successor.overflow ? 0 : successor.partialValue
        return value
    }

    private mutating func receiptToken(_ value: UUID) -> UInt64? {
        if let host, host.commit.receiptID == value { return host.receipt }
        return token()
    }

    private mutating func offerToken(_ value: UUID) -> UInt64? {
        if let viewer, viewer.commit.id == value { return viewer.offer }
        return token()
    }

    private mutating func envelopeToken(_ value: WebRTCMediaHandoffCommitEnvelope) -> UInt64? {
        if let host, host.commit.envelope == value { return host.envelope }
        if let viewer, viewer.commit == value { return viewer.envelope }
        return token()
    }

    private mutating func step(_ event: beluga_core_handoff_transactions_event_t,
                               newHost: HostBinding? = nil, newViewer: ViewerBinding? = nil)
        -> beluga_core_handoff_transactions_result_t? {
        let output = beluga_core_handoff_transactions_step(1, core, event)
        let successor = output.state
        let hostBinding = [host, newHost].compactMap { $0 }.first {
            $0.receipt == successor.host_receipt && $0.envelope == successor.host_envelope
        }
        let viewerBinding = [viewer, newViewer].compactMap { $0 }.first {
            $0.envelope == successor.viewer_envelope && $0.offer == successor.viewer_offer
        }
        let revokesHost = output.effects & 1 != 0
        guard BelugaRustHandoffBoundary.accepts(before: core, event: event, output: output),
              (successor.host_phase == 0
                ? successor.host_receipt == 0 && successor.host_envelope == 0 && successor.host_result == 0
                : hostBinding != nil && (successor.host_phase == 1
                    ? successor.host_result == 0 : Self.nativeResult(successor.host_result) != nil)),
              (successor.viewer_envelope == 0 && successor.viewer_offer == 0) || viewerBinding != nil else {
            host?.commit.execution.revoke()
            host = nil; viewer = nil
            core = beluga_core_handoff_transactions_initial()
            return nil
        }
        if revokesHost { host?.commit.execution.revoke() }
        host = successor.host_phase == 0 ? nil : hostBinding
        viewer = successor.viewer_envelope == 0 ? nil : viewerBinding
        core = successor
        return output
    }

    private static func coreResult(_ result: WebRTCMediaHandoffResult) -> UInt32 {
        switch result {
        case .macPaused: 1
        case .notApplied: 2
        case .outcomeUnknown: 3
        }
    }

    private static func nativeResult(_ value: UInt32) -> WebRTCMediaHandoffResult? {
        switch value {
        case 1: .macPaused
        case 2: .notApplied
        case 3: .outcomeUnknown
        default: nil
        }
    }
}
