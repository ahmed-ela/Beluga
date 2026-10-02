import Foundation

/// Bounded wire syntax and replay ordering only. Each channel must authenticate its
/// kernel peer before decoding and revalidate it before performing an action. No
/// message (including `released`) grants native runtime or fence-clear authority.
package enum BelugaUpdateIPCProtocol {
    package static let schema = "beluga.update-ipc.v1"
    package static let maximumFrameBytes = 24_576

    package enum Failure: Error, Equatable {
        case invalidBinding, invalidFrame, oversizedFrame, noncanonicalFrame
        case unexpectedBinding, wrongDirection, wrongSequence, retiredTranscript
    }

    package struct Binding: Codable, Equatable, Sendable {
        package let operationID: UUID
        package let target: BelugaUpdateOperation.Target
        /// Fresh per-connection challenge chosen by the initiating menu. It is not
        /// a credential and cannot replace code identity or the readiness nonce.
        package let channelNonce: UUID

        package init(operationID: UUID, target: BelugaUpdateOperation.Target,
                     channelNonce: UUID) throws {
            guard validNonce(operationID), validNonce(channelNonce), operationID != channelNonce else {
                throw Failure.invalidBinding
            }
            self.operationID = operationID
            self.target = target
            self.channelNonce = channelNonce
        }
    }

    package enum Sender: String, Codable, Equatable, Sendable { case menu, broker }
    package enum Refusal: String, Codable, Equatable, Sendable {
        case admissionDenied, identityChanged, unresolvedOperation, installationUncertain
    }

    package enum Message: Codable, Equatable, Sendable {
        case beginCheck(menuInstanceID: UUID)
        case checkAccepted
        case waiting
        case requestReadiness(menuInstanceID: UUID)
        case readinessChallenge(menuInstanceID: UUID, candidate: BelugaUpdateOperation.ArtifactIdentity,
                                nonce: UUID)
        case menuReady(BelugaUpdateOperation.MenuReadiness)
        case releaseObserved
        case released
        case refused(Refusal)

        fileprivate var sender: Sender {
            switch self {
            case .beginCheck, .requestReadiness, .menuReady, .releaseObserved: .menu
            case .checkAccepted, .waiting, .readinessChallenge, .released, .refused: .broker
            }
        }

        fileprivate func validate(binding: Binding) throws {
            switch self {
            case .beginCheck(let menu), .requestReadiness(let menu):
                guard validNonce(menu), menu != binding.operationID,
                      menu != binding.channelNonce else { throw Failure.invalidFrame }
            case .readinessChallenge(let menu, let candidate, let nonce):
                guard validNonce(menu), validNonce(nonce), menu != binding.operationID,
                      menu != binding.channelNonce, nonce != binding.operationID,
                      nonce != binding.channelNonce, nonce != menu else { throw Failure.invalidFrame }
                try validateArtifact(candidate)
            case .menuReady(let value):
                guard value.operationID == binding.operationID, value.target == binding.target,
                      value.isReady, validNonce(value.menuInstanceID), validNonce(value.challengeNonce),
                      value.menuInstanceID != binding.operationID,
                      value.menuInstanceID != binding.channelNonce,
                      value.challengeNonce != binding.operationID,
                      value.challengeNonce != binding.channelNonce,
                      value.challengeNonce != value.menuInstanceID else { throw Failure.invalidFrame }
                try validateArtifact(value.candidate)
            case .checkAccepted, .waiting, .released, .releaseObserved, .refused: break
            }
        }
    }

    private struct Frame: Codable {
        let schema: String
        let binding: Binding
        let sender: Sender
        let sequence: UInt64
        let message: Message
    }

    /// Bootstrap only after authenticating the socket's native main-app peer. The
    /// menu chooses a fresh connection nonce; operation and target remain local
    /// authority. Decode the same first frame through Transcript before using it.
    package static func initialBinding(_ data: Data, operationID: UUID,
                                       target: BelugaUpdateOperation.Target) throws -> Binding {
        guard !data.isEmpty, data.count <= maximumFrameBytes else { throw Failure.oversizedFrame }
        let frame: Frame
        do { frame = try JSONDecoder().decode(Frame.self, from: data) }
        catch { throw Failure.invalidFrame }
        guard frame.binding.operationID == operationID, frame.binding.target == target else {
            throw Failure.unexpectedBinding
        }
        let binding = try Binding(operationID: operationID, target: target,
                                  channelNonce: frame.binding.channelNonce)
        var transcript = Transcript(binding: binding, localRole: .broker)
        switch try transcript.decode(data) {
        case .beginCheck, .requestReadiness: return binding
        default: throw Failure.invalidFrame
        }
    }

    /// Single-owner transcript. Sequence numbers advance only after full validation;
    /// any error retires it permanently, preventing retry after partial I/O or replay.
    package struct Transcript {
        package let binding: Binding
        package let localRole: Sender
        private var outgoing: UInt64 = 0
        private var incoming: UInt64 = 0
        private var retired = false

        package init(binding: Binding, localRole: Sender) {
            self.binding = binding
            self.localRole = localRole
        }

        package mutating func encode(_ message: Message) throws -> Data {
            do {
                guard !retired else { throw Failure.retiredTranscript }
                guard message.sender == localRole else { throw Failure.wrongDirection }
                guard outgoing < UInt64.max else { throw Failure.wrongSequence }
                try message.validate(binding: binding)
                let data = try canonical(Frame(schema: schema, binding: binding, sender: localRole,
                                               sequence: outgoing, message: message))
                guard data.count <= maximumFrameBytes else { throw Failure.oversizedFrame }
                outgoing += 1
                return data
            } catch { retired = true; throw error }
        }

        package mutating func decode(_ data: Data) throws -> Message {
            do {
                guard !retired else { throw Failure.retiredTranscript }
                guard !data.isEmpty, data.count <= maximumFrameBytes else { throw Failure.oversizedFrame }
                let frame: Frame
                do { frame = try JSONDecoder().decode(Frame.self, from: data) }
                catch { throw Failure.invalidFrame }
                guard frame.schema == schema else { throw Failure.invalidFrame }
                guard frame.binding == binding else { throw Failure.unexpectedBinding }
                guard frame.sender != localRole, frame.message.sender == frame.sender else {
                    throw Failure.wrongDirection
                }
                guard incoming < UInt64.max, frame.sequence == incoming else { throw Failure.wrongSequence }
                try frame.message.validate(binding: binding)
                guard try canonical(frame) == data else { throw Failure.noncanonicalFrame }
                incoming += 1
                return frame.message
            } catch { retired = true; throw error }
        }

        package mutating func retire() { retired = true }
    }

    private static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func validNonce(_ value: UUID) -> Bool {
        value != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }

    private static func validateArtifact(_ value: BelugaUpdateOperation.ArtifactIdentity) throws {
        _ = try BelugaUpdateOperation.ArtifactIdentity(
            version: value.version, build: value.build, executableSHA256: value.executableSHA256,
            dependencyClosureSHA256: value.dependencyClosureSHA256)
    }
}
