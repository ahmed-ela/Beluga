import CryptoKit
import Foundation
import Testing
@testable import RemoteSessionCore

/// PRIVATE, UNCOMPILED. These use real AEAD and the actual receiver actor.
/// Every credential and plaintext is generated solely inside this test file.
struct RemoteSignalingReplayAuthenticationTests {
    @Test func receiverAuthenticationFailureDoesNotConsumeSequenceOrAdvanceHistory() async throws {
        let invitation = try code(71)
        let sender = RemoteSignalingCipher(invitation: invitation, role: .host)
        let receiver = RemoteSignalingReceiver(cipher: .init(invitation: invitation, role: .viewer))
        let first = try sender.seal(.control(.showScreen), sequence: 10)
        #expect(try await receiver.open(first) == .control(.showScreen))
        let next = try sender.seal(.control(.hideScreen), sequence: 100)
        var corruptBytes = next.ciphertext
        corruptBytes[corruptBytes.index(before: corruptBytes.endIndex)] ^= 1
        let tampered = SealedSignalingEnvelope(
            channelID: next.channelID, direction: next.direction,
            sequence: next.sequence, ciphertext: corruptBytes
        )
        await #expect(throws: RemoteSessionCoreError.authenticationFailed) { try await receiver.open(tampered) }
        let reordered = try sender.seal(.control(.requestKeyFrame), sequence: 9)
        #expect(try await receiver.open(reordered) == .control(.requestKeyFrame))
        #expect(try await receiver.open(next) == .control(.hideScreen))
        await #expect(throws: RemoteSessionCoreError.replayedSequence) { try await receiver.open(next) }
    }

    @Test func authenticatedUndecodablePlaintextDoesNotConsumeSequence() async throws {
        let invitation = try code(72)
        let credential = RemoteRendezvousCredential(invitation: invitation)
        let receiver = RemoteSignalingReceiver(cipher: .init(credential: credential, role: .viewer))
        let malformed = try encryptedUndecodableEnvelope(credential: credential, sequence: 0)
        await #expect(throws: RemoteSessionCoreError.invalidSignalPayload) { try await receiver.open(malformed) }
        let valid = try RemoteSignalingCipher(credential: credential, role: .host)
            .seal(.control(.showScreen), sequence: 0)
        #expect(try await receiver.open(valid) == .control(.showScreen))
        await #expect(throws: RemoteSessionCoreError.replayedSequence) { try await receiver.open(valid) }
    }

    @Test func authenticatedHeaderTamperCannotConsumeMaximumDirectReceiverSequence() async throws {
        let invitation = try code(73)
        let sender = RemoteSignalingCipher(invitation: invitation, role: .host)
        let receiver = RemoteSignalingReceiver(cipher: .init(invitation: invitation, role: .viewer))
        let original = try sender.seal(.control(.showScreen), sequence: .max - 1)
        let changedHeader = SealedSignalingEnvelope(
            channelID: original.channelID, direction: original.direction,
            sequence: .max, ciphertext: original.ciphertext
        )
        await #expect(throws: RemoteSessionCoreError.authenticationFailed) { try await receiver.open(changedHeader) }
        let maximum = try sender.seal(.control(.hideScreen), sequence: .max)
        #expect(try await receiver.open(maximum) == .control(.hideScreen))
        await #expect(throws: RemoteSessionCoreError.replayedSequence) { try await receiver.open(maximum) }
    }

    private func code(_ byte: UInt8) throws -> RemoteInvitationCode {
        try .init(secret: Data(repeating: byte, count: 20))
    }

    private func encryptedUndecodableEnvelope(
        credential: RemoteRendezvousCredential, sequence: UInt64
    ) throws -> SealedSignalingEnvelope {
        let header = SealedSignalingEnvelope(
            channelID: credential.channelID, direction: .hostToViewer,
            sequence: sequence, ciphertext: Data()
        )
        // Deliberate test-only sequence reuse follows a rejected decoded payload;
        // no production sender, runtime credential, or user payload is involved.
        let box = try ChaChaPoly.seal(
            Data("{".utf8), using: SymmetricKey(data: credential.hostToViewer),
            authenticating: header.additionalAuthenticatedData
        )
        return .init(channelID: header.channelID, direction: header.direction,
                     sequence: header.sequence, ciphertext: box.combined)
    }
}
