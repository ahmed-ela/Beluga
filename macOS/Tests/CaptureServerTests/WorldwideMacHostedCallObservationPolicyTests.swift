import Foundation
@testable import CaptureCore
@testable import CaptureServer
@testable import WebRTCTransport
import XCTest

final class WorldwideMacHostedCallObservationPolicyTests: XCTestCase {
    func testWireEvidenceStateDistinguishesProspectiveArmFromPoison() throws {
        XCTAssertEqual(
            try WorldwideMacHostedCallEvidenceStatePolicy.state(
                isCausallyBoundActive: false,
                isCausallyArmed: true
            ),
            .preflightArmed
        )
        XCTAssertEqual(
            try WorldwideMacHostedCallEvidenceStatePolicy.state(
                isCausallyBoundActive: true,
                isCausallyArmed: false
            ),
            .active
        )
        XCTAssertEqual(
            try WorldwideMacHostedCallEvidenceStatePolicy.state(
                isCausallyBoundActive: false,
                isCausallyArmed: false
            ),
            .inactive
        )
        XCTAssertNil(
            try WorldwideMacHostedCallEvidenceStatePolicy.state(
                isCausallyBoundActive: true,
                isCausallyArmed: true
            )
        )
    }

    func testRejectsReorderedObservationEvenWhenChallengeMatches() throws {
        let challenge = WebRTCMacHostedCallChallenge(
            sequence: 1,
            callEpochNonce: UUID()
        )

        XCTAssertTrue(
            try WorldwideMacHostedCallObservationPolicy.admits(
                observationSequence: 11,
                highestAdmittedSequence: 10,
                observationChallenge: nativeChallenge(challenge),
                currentChallenge: challenge
            )
        )
        XCTAssertFalse(
            try WorldwideMacHostedCallObservationPolicy.admits(
                observationSequence: 10,
                highestAdmittedSequence: 11,
                observationChallenge: nativeChallenge(challenge),
                currentChallenge: challenge
            )
        )
    }

    func testRejectsObservationFromPriorChallenge() throws {
        let callEpochNonce = UUID()
        let prior = WebRTCMacHostedCallChallenge(
            sequence: 1,
            callEpochNonce: callEpochNonce
        )
        let current = WebRTCMacHostedCallChallenge(
            sequence: 2,
            callEpochNonce: callEpochNonce
        )

        XCTAssertFalse(
            try WorldwideMacHostedCallObservationPolicy.admits(
                observationSequence: 12,
                highestAdmittedSequence: 11,
                observationChallenge: nativeChallenge(prior),
                currentChallenge: current
            )
        )
        XCTAssertTrue(
            try WorldwideMacHostedCallObservationPolicy.admits(
                observationSequence: 12,
                highestAdmittedSequence: 11,
                observationChallenge: nativeChallenge(current),
                currentChallenge: current
            )
        )
    }

    func testRejectsPriorSequenceWhenNonceIsReused() throws {
        let nonce = UUID()
        let callEpochNonce = UUID()
        let prior = WebRTCMacHostedCallChallenge(
            sequence: 1,
            callEpochNonce: callEpochNonce,
            nonce: nonce
        )
        let current = WebRTCMacHostedCallChallenge(
            sequence: 2,
            callEpochNonce: callEpochNonce,
            nonce: nonce
        )

        XCTAssertFalse(
            try WorldwideMacHostedCallObservationPolicy.admits(
                observationSequence: 12,
                highestAdmittedSequence: 11,
                observationChallenge: nativeChallenge(prior),
                currentChallenge: current
            )
        )
        XCTAssertTrue(
            try WorldwideMacHostedCallObservationPolicy.admits(
                observationSequence: 13,
                highestAdmittedSequence: 11,
                observationChallenge: nativeChallenge(current),
                currentChallenge: current
            )
        )
    }

    func testRejectsWrongCallEpochEvenWhenSequenceAndNonceMatch() throws {
        let nonce = UUID()
        let current = WebRTCMacHostedCallChallenge(
            sequence: 7,
            callEpochNonce: UUID(),
            nonce: nonce
        )
        let wrongEpochObservation =
            SystemAudioMacFaceTimeActivityChallenge(
                sequence: current.sequence,
                nonce: nonce,
                callEpochNonce: UUID()
            )

        XCTAssertFalse(
            try WorldwideMacHostedCallObservationPolicy.admits(
                observationSequence: 1,
                highestAdmittedSequence: 0,
                observationChallenge: wrongEpochObservation,
                currentChallenge: current
            )
        )
    }

    func testRejectsMissingOrInvalidChallenge() throws {
        let invalid = WebRTCMacHostedCallChallenge(
            sequence: 0,
            callEpochNonce: UUID()
        )

        XCTAssertFalse(
            try WorldwideMacHostedCallObservationPolicy.admits(
                observationSequence: 1,
                highestAdmittedSequence: 0,
                observationChallenge: nativeChallenge(invalid),
                currentChallenge: invalid
            )
        )
        XCTAssertFalse(
            try WorldwideMacHostedCallObservationPolicy.admits(
                observationSequence: 1,
                highestAdmittedSequence: 0,
                observationChallenge: nil,
                currentChallenge: nil
            )
        )
    }

    func testPeerGenerationFenceRejectsStaleSourceOrChallenge() throws {
        XCTAssertTrue(
            try WorldwideMacHostedCallPeerGenerationPolicy.admits(
                audioPeerGeneration: 7,
                challengePeerGeneration: 7,
                currentPeerGeneration: 7
            )
        )
        XCTAssertFalse(
            try WorldwideMacHostedCallPeerGenerationPolicy.admits(
                audioPeerGeneration: 6,
                challengePeerGeneration: 7,
                currentPeerGeneration: 7
            )
        )
        XCTAssertFalse(
            try WorldwideMacHostedCallPeerGenerationPolicy.admits(
                audioPeerGeneration: 7,
                challengePeerGeneration: 6,
                currentPeerGeneration: 7
            )
        )
        XCTAssertFalse(
            try WorldwideMacHostedCallPeerGenerationPolicy.admits(
                audioPeerGeneration: 0,
                challengePeerGeneration: 0,
                currentPeerGeneration: 0
            )
        )
    }

    private func nativeChallenge(
        _ challenge: WebRTCMacHostedCallChallenge
    ) -> SystemAudioMacFaceTimeActivityChallenge {
        SystemAudioMacFaceTimeActivityChallenge(
            sequence: challenge.sequence,
            nonce: challenge.nonce,
            callEpochNonce: challenge.callEpochNonce
        )
    }
}
