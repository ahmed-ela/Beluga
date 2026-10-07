// Rust-owned scalar projection; UUID tuple bytes are correlation values only.
import BelugaCore
import CaptureCore
import Foundation
import WebRTCTransport

enum WorldwideMacHostedCallBridgeError: Error, Equatable, Sendable {
    case observation
    case evidence
    case peerGeneration
}

enum BelugaRustMacHostedCallBoundary {
    typealias Observation = beluga_core_hosted_call_observation_facts_t
    typealias Evidence = beluga_core_hosted_call_evidence_facts_t
    typealias Peer = beluga_core_hosted_call_peer_facts_t
    typealias Output = beluga_core_hosted_call_decision_t
    typealias UUIDBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    static let zeroUUID: UUIDBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    static var layoutIsExact: Bool {
        MemoryLayout<Observation>.size == 120 && MemoryLayout<Observation>.stride == 120
            && MemoryLayout<Observation>.alignment == 8
            && MemoryLayout<Evidence>.size == 16 && MemoryLayout<Evidence>.stride == 16
            && MemoryLayout<Evidence>.alignment == 4
            && MemoryLayout<Peer>.size == 40 && MemoryLayout<Peer>.stride == 40
            && MemoryLayout<Peer>.alignment == 8
            && MemoryLayout<Output>.size == 16 && MemoryLayout<Output>.stride == 16
            && MemoryLayout<Output>.alignment == 4
    }

    static func sameBytes(_ a: UUIDBytes, _ b: UUIDBytes) -> Bool {
        a.0 == b.0 && a.1 == b.1 && a.2 == b.2 && a.3 == b.3
            && a.4 == b.4 && a.5 == b.5 && a.6 == b.6 && a.7 == b.7
            && a.8 == b.8 && a.9 == b.9 && a.10 == b.10 && a.11 == b.11
            && a.12 == b.12 && a.13 == b.13 && a.14 == b.14 && a.15 == b.15
    }
    static func acceptsEnvelope(_ output: Output, maximumValue: UInt32) -> Bool {
        layoutIsExact && output.abi_version == 1 && output.status == 1
            && output.reserved == 0 && output.value <= maximumValue
    }
    static func acceptsObservation(_ input: Observation, _ output: Output) -> Bool {
        guard input.abi_version == 1, input.reserved == 0,
              input.observation_challenge_present <= 1, input.current_challenge_present <= 1,
              acceptsEnvelope(output, maximumValue: 1) else { return false }
        // Existing native protocol-v3 semantics, used only to reject a copied
        // result after actual C. No token, native binder, or privilege is minted.
        let admitted = input.observation_sequence > input.highest_admitted_sequence
            && input.observation_challenge_present == 1 && input.current_challenge_present == 1
            && input.current_protocol_version == 3 && input.current_challenge_sequence > 0
            && !sameBytes(input.current_nonce, zeroUUID)
            && !sameBytes(input.current_call_epoch_nonce, zeroUUID)
            && !sameBytes(input.current_nonce, input.current_call_epoch_nonce)
            && input.observation_challenge_sequence == input.current_challenge_sequence
            && sameBytes(input.observation_nonce, input.current_nonce)
            && sameBytes(input.observation_call_epoch_nonce, input.current_call_epoch_nonce)
        return output.value == (admitted ? 1 : 0)
    }
    static func acceptsEvidence(_ input: Evidence, _ output: Output) -> Bool {
        guard input.abi_version == 1, input.reserved == 0, input.active <= 1,
              input.armed <= 1, acceptsEnvelope(output, maximumValue: 3) else { return false }
        switch (input.active, input.armed, output.value) {
        case (0, 0, 1), (0, 1, 2), (1, 0, 3), (1, 1, 0): return true
        default: return false
        }
    }
    static func acceptsPeer(_ input: Peer, _ output: Output) -> Bool {
        guard input.abi_version == 1, input.reserved == 0, input.audio_present <= 1,
              input.challenge_present <= 1, acceptsEnvelope(output, maximumValue: 1) else { return false }
        let admitted = input.current_generation > 0 && input.audio_present == 1
            && input.challenge_present == 1 && input.audio_generation == input.current_generation
            && input.challenge_generation == input.current_generation
        return output.value == (admitted ? 1 : 0)
    }
}

struct BelugaRustMacHostedCallProducer: Sendable {
    typealias Boundary = BelugaRustMacHostedCallBoundary
    let observation: @Sendable (Boundary.Observation) -> Boundary.Output
    let evidence: @Sendable (Boundary.Evidence) -> Boundary.Output
    let peerGeneration: @Sendable (Boundary.Peer) -> Boundary.Output
    static let actual = Self(
        observation: { beluga_core_hosted_call_observation($0) },
        evidence: { beluga_core_hosted_call_evidence($0) },
        peerGeneration: { beluga_core_hosted_call_peer_generation($0) }
    )
}

enum WorldwideMacHostedCallObservationPolicy {
    static func admits(observationSequence: UInt64, highestAdmittedSequence: UInt64,
                       observationChallenge: SystemAudioMacFaceTimeActivityChallenge?,
                       currentChallenge: WebRTCMacHostedCallChallenge?,
                       producer: BelugaRustMacHostedCallProducer = .actual) throws -> Bool {
        var input = BelugaRustMacHostedCallBoundary.Observation()
        input.abi_version = 1
        input.observation_sequence = observationSequence
        input.highest_admitted_sequence = highestAdmittedSequence
        input.observation_challenge_present = observationChallenge == nil ? 0 : 1
        input.current_challenge_present = currentChallenge == nil ? 0 : 1
        input.current_protocol_version = Int64(currentChallenge?.protocolVersion ?? 0)
        input.observation_challenge_sequence = observationChallenge?.sequence ?? 0
        input.current_challenge_sequence = currentChallenge?.sequence ?? 0
        input.observation_nonce = observationChallenge?.nonce.uuid ?? BelugaRustMacHostedCallBoundary.zeroUUID
        input.observation_call_epoch_nonce = observationChallenge?.callEpochNonce.uuid ?? BelugaRustMacHostedCallBoundary.zeroUUID
        input.current_nonce = currentChallenge?.nonce.uuid ?? BelugaRustMacHostedCallBoundary.zeroUUID
        input.current_call_epoch_nonce = currentChallenge?.callEpochNonce.uuid ?? BelugaRustMacHostedCallBoundary.zeroUUID
        let output = producer.observation(input)
        guard BelugaRustMacHostedCallBoundary.acceptsObservation(input, output) else {
            throw WorldwideMacHostedCallBridgeError.observation
        }
        return output.value == 1
    }
}

enum WorldwideMacHostedCallEvidenceStatePolicy {
    static func state(isCausallyBoundActive: Bool, isCausallyArmed: Bool,
                      producer: BelugaRustMacHostedCallProducer = .actual) throws
        -> WebRTCMacHostedCallEvidence.State? {
        var input = BelugaRustMacHostedCallBoundary.Evidence()
        input.abi_version = 1
        input.active = isCausallyBoundActive ? 1 : 0
        input.armed = isCausallyArmed ? 1 : 0
        let output = producer.evidence(input)
        guard BelugaRustMacHostedCallBoundary.acceptsEvidence(input, output) else {
            throw WorldwideMacHostedCallBridgeError.evidence
        }
        switch output.value {
        case 0: return nil
        case 1: return .inactive
        case 2: return .preflightArmed
        case 3: return .active
        default: throw WorldwideMacHostedCallBridgeError.evidence
        }
    }
}

enum WorldwideMacHostedCallPeerGenerationPolicy {
    static func admits(audioPeerGeneration: UInt64?, challengePeerGeneration: UInt64?,
                       currentPeerGeneration: UInt64,
                       producer: BelugaRustMacHostedCallProducer = .actual) throws -> Bool {
        var input = BelugaRustMacHostedCallBoundary.Peer()
        input.abi_version = 1
        input.audio_present = audioPeerGeneration == nil ? 0 : 1
        input.challenge_present = challengePeerGeneration == nil ? 0 : 1
        input.audio_generation = audioPeerGeneration ?? 0
        input.challenge_generation = challengePeerGeneration ?? 0
        input.current_generation = currentPeerGeneration
        let output = producer.peerGeneration(input)
        guard BelugaRustMacHostedCallBoundary.acceptsPeer(input, output) else {
            throw WorldwideMacHostedCallBridgeError.peerGeneration
        }
        return output.value == 1
    }
}
