import Foundation
import XCTest
import WebRTCTransport
@testable import opensteamer

final class YouTubeHandoffOperationTests: XCTestCase {
    private func makeOperation() throws -> YouTubeHandoffOperation {
        let request = try YouTubeHandoffRequest(operationID: UUID(), videoID: "dQw4w9WgXcQ",
            positionSeconds: 20, durationSeconds: 200, playbackRate: 1, deadlineUptime: 40, now: 10)
        var operation = YouTubeHandoffOperation(request: request, now: 10)
        XCTAssertNil(operation.visibilityChanged(true, now: 10))
        return operation
    }

    private func body(_ operation: YouTubeHandoffOperation, _ sequence: Int, kind: String = "sample",
                      position: Double = 20, state: Int = 1, video: String? = nil) -> [String: Any] {
        var result: [String: Any] = ["kind": kind, "operation": operation.request.operationID.uuidString.lowercased(),
            "page": operation.pageID.uuidString.lowercased(), "video": video ?? operation.request.videoID, "sequence": sequence]
        if kind == "sample" {
            result.merge(["state": state, "position": position, "duration": 200, "rate": 1]) { _, new in new }
        }
        return result
    }

    private func send(_ operation: inout YouTubeHandoffOperation, _ sequence: Int, now: Double,
                      kind: String = "sample", position: Double = 20, state: Int = 1,
                      video: String? = nil) throws -> YouTubeHandoffPlayerEvent? {
        let message = try XCTUnwrap(YouTubeHandoffBridgeMessage(body: body(operation, sequence, kind: kind,
            position: position, state: state, video: video)))
        return operation.receive(message, now: now)
    }

    private func confirm(_ operation: inout YouTubeHandoffOperation) throws -> YouTubePhonePlaybackEvidence {
        XCTAssertNil(try send(&operation, 1, now: 10, kind: "ready"))
        XCTAssertNil(try send(&operation, 2, now: 10.1))
        let result = try send(&operation, 3, now: 10.4, position: 20.3)
        guard case .confirmed(let evidence) = result else { throw TestError.noEvidence }
        return evidence
    }
    private enum TestError: Error { case noEvidence }

    func testReadyAndPlayingWithoutProgressDoNotConfirm() throws {
        var operation = try makeOperation()
        XCTAssertNil(try send(&operation, 1, now: 10, kind: "ready"))
        XCTAssertNil(try send(&operation, 2, now: 10.1))
        XCTAssertNil(try send(&operation, 3, now: 10.4))
        XCTAssertNil(operation.evidence)
    }

    func testOnlyAdvancingExactVisiblePlaybackConfirmsOnce() throws {
        var operation = try makeOperation()
        let evidence = try confirm(&operation)
        XCTAssertTrue(operation.isCurrent(evidence, now: 10.5))
        XCTAssertNil(try send(&operation, 4, now: 10.6, position: 20.5))
        XCTAssertEqual(operation.evidence, evidence)
    }

    func testPlayingAtWrongPositionAndPauseCannotConfirm() throws {
        for paused in [true, false] {
            var operation = try makeOperation()
            _ = try send(&operation, 1, now: 10, kind: "ready")
            _ = try send(&operation, 2, now: 10.1, position: paused ? 20 : 80, state: paused ? 2 : 1)
            XCTAssertNil(try send(&operation, 3, now: 10.4, position: paused ? 20.3 : 80.3, state: paused ? 2 : 1))
            XCTAssertNil(operation.evidence)
        }
    }

    func testAutoplayBlockAsksPlayAndDoesNotClaimPlayback() throws {
        var operation = try makeOperation()
        _ = try send(&operation, 1, now: 10, kind: "ready")
        XCTAssertEqual(try send(&operation, 2, now: 10.1, kind: "blocked"), .playRequired)
        XCTAssertEqual(operation.phase, .playRequired)
        XCTAssertNil(operation.evidence)
        _ = try send(&operation, 3, now: 11, position: 20)
        guard case .confirmed = try send(&operation, 4, now: 11.3, position: 20.3) else {
            return XCTFail("A real later user play can confirm within the original deadline")
        }
    }

    func testHiddenDismissedReplacedExpiredAndWrongVideoCannotRevive() throws {
        for reason in [YouTubeHandoffFailure.notVisible, .dismissed, .replaced, .timedOut, .wrongVideo] {
            var operation = try makeOperation()
            let evidence = try confirm(&operation)
            XCTAssertEqual(operation.fail(reason), .failed(reason))
            XCTAssertNil(try send(&operation, 4, now: 10.6, position: 20.5))
            XCTAssertFalse(operation.isCurrent(evidence, now: 10.7))
        }
        var operation = try makeOperation()
        _ = try send(&operation, 1, now: 10, kind: "ready")
        XCTAssertEqual(operation.visibilityChanged(false, now: 10.1), .failed(.notVisible))
        XCTAssertNil(operation.visibilityChanged(true, now: 10.2))
        XCTAssertNil(operation.evidence)
        var expired = try makeOperation()
        XCTAssertEqual(expired.poll(now: 40), .failed(.timedOut))
        var wrong = try makeOperation()
        XCTAssertEqual(try send(&wrong, 1, now: 10.1, video: "aaaaaaaaaaa"), .failed(.wrongVideo))
    }

    func testForeignPageReplayAndBooleanNumbersAreRejected() throws {
        var operation = try makeOperation()
        var foreign = body(operation, 100, kind: "ready")
        foreign["page"] = UUID().uuidString.lowercased()
        XCTAssertNil(operation.receive(try XCTUnwrap(YouTubeHandoffBridgeMessage(body: foreign)), now: 10))
        _ = try send(&operation, 1, now: 10, kind: "ready")
        _ = try send(&operation, 2, now: 10.1)
        XCTAssertNil(try send(&operation, 2, now: 10.4, position: 20.3))
        XCTAssertNil(operation.evidence)
        for key in ["state", "position", "duration", "rate", "sequence"] {
            var malformed = body(operation, 3)
            malformed[key] = true
            XCTAssertNil(YouTubeHandoffBridgeMessage(body: malformed))
        }
        var extra = body(operation, 3); extra["unexpected"] = "data"
        XCTAssertNil(YouTubeHandoffBridgeMessage(body: extra))
    }

    func testOldEvidenceDoesNotRefreshFromLaterSamplesOrSeek() throws {
        var operation = try makeOperation()
        let evidence = try confirm(&operation)
        _ = try send(&operation, 4, now: 11.2, position: 21.1)
        XCTAssertFalse(operation.isCurrent(evidence, now: 11.2))
        var seek = try makeOperation()
        let seekEvidence = try confirm(&seek)
        XCTAssertEqual(try send(&seek, 4, now: 10.5, position: 80), .failed(.positionChanged))
        XCTAssertFalse(seek.isCurrent(seekEvidence, now: 10.6))
    }

    func testPlaybackInterruptionCannotReviveAnEarlierConfirmation() throws {
        for interruption in ["pause", "buffering", "blocked", "duration", "rate"] {
            var operation = try makeOperation()
            let evidence = try confirm(&operation)
            var interrupted = body(operation, 4, kind: interruption == "blocked" ? "blocked" : "sample",
                position: 20.4, state: interruption == "pause" ? 2 : interruption == "buffering" ? 3 : 1)
            if interruption == "duration" { interrupted["duration"] = 100 }
            if interruption == "rate" { interrupted["rate"] = 2 }
            _ = operation.receive(try XCTUnwrap(YouTubeHandoffBridgeMessage(body: interrupted)), now: 10.5)
            XCTAssertFalse(operation.isCurrent(evidence, now: 10.5), interruption)
            _ = try send(&operation, 5, now: 10.6, position: 20.5)
            XCTAssertFalse(operation.isCurrent(evidence, now: 10.6), interruption)
        }
    }

    func testInvalidRequestAndClockRegressionFailClosed() throws {
        XCTAssertThrowsError(try YouTubeHandoffRequest(operationID: UUID(), videoID: "bad/identity",
            positionSeconds: 20, durationSeconds: 200, playbackRate: 1, deadlineUptime: 40, now: 10))
        XCTAssertThrowsError(try YouTubeHandoffRequest(operationID: UUID(), videoID: "dQw4w9WgXcQ",
            positionSeconds: .nan, durationSeconds: 200, playbackRate: 1, deadlineUptime: 40, now: 10))
        var operation = try makeOperation()
        XCTAssertEqual(operation.poll(now: 9), .failed(.clockChanged))
    }

    func testOnlyReservedExactCompletionMovesPlaybackAndCannotBeReplayed() throws {
        var operation = try makeOperation()
        let proof = try confirm(&operation)
        XCTAssertNil(operation.completeMacPause(operationID: operation.request.id, result: .macPaused, now: 10.5))
        XCTAssertEqual(operation.phase, .confirmed)
        XCTAssertTrue(operation.beginMacPause(using: proof, now: 10.5))
        XCTAssertFalse(operation.beginMacPause(using: proof, now: 10.5))
        XCTAssertNil(operation.completeMacPause(operationID: UUID(), result: .macPaused, now: 10.6))
        XCTAssertEqual(operation.phase, .awaitingMacPause)
        XCTAssertEqual(operation.completeMacPause(operationID: operation.request.id, result: .macPaused, now: 10.6), .movedToPhone)
        XCTAssertEqual(operation.macPauseStatus, .paused)
        XCTAssertEqual(operation.phase, .localPlayback)
        XCTAssertNil(operation.evidence)
        XCTAssertFalse(operation.isCurrent(proof, now: 10.7))
        XCTAssertFalse(operation.beginMacPause(using: proof, now: 10.7))
        for result in [WebRTCMediaHandoffResult.macPaused, .notApplied, .outcomeUnknown] {
            XCTAssertNil(operation.completeMacPause(operationID: operation.request.id, result: result, now: 10.7))
            XCTAssertEqual(operation.macPauseStatus, .paused)
            XCTAssertEqual(operation.phase, .localPlayback)
        }
    }

    func testCommittedPlayerAllowsLocalControlsPastOfferDeadlineWithoutNewAuthority() throws {
        var operation = try makeOperation()
        let proof = try confirm(&operation)
        XCTAssertTrue(operation.beginMacPause(using: proof, now: 10.5))
        XCTAssertEqual(operation.completeMacPause(operationID: operation.request.id, result: .macPaused, now: 10.6), .movedToPhone)
        for (index, state) in [2, 1, 3, 0].enumerated() {
            let now = 60.0 + Double(index)
            var sample = body(operation, 4 + index, position: 80, state: state)
            sample["rate"] = 2
            XCTAssertNil(operation.receive(try XCTUnwrap(YouTubeHandoffBridgeMessage(body: sample)), now: now))
            XCTAssertNil(operation.poll(now: now))
            XCTAssertEqual(operation.phase, .localPlayback)
            XCTAssertFalse(operation.isCurrent(proof, now: now))
            XCTAssertFalse(operation.beginMacPause(using: proof, now: now))
        }
        XCTAssertEqual(try send(&operation, 8, now: 64, video: "aaaaaaaaaaa"), .failed(.wrongVideo))
        XCTAssertEqual(operation.macPauseStatus, .paused)
        XCTAssertEqual(operation.phase.statusText(macPause: operation.macPauseStatus),
                       "The Mac source was paused. Playback on this iPhone has stopped.")
    }

    func testPendingPlaybackInterruptionCannotReviveAfterSuccessReply() throws {
        for interruption in ["pause", "buffering", "seek", "blocked", "duration", "rate"] {
            var operation = try makeOperation()
            let proof = try confirm(&operation)
            XCTAssertTrue(operation.beginMacPause(using: proof, now: 10.5))
            var interrupted = body(operation, 4, kind: interruption == "blocked" ? "blocked" : "sample",
                position: interruption == "seek" ? 80 : 20.4,
                state: interruption == "pause" ? 2 : interruption == "buffering" ? 3 : 1)
            if interruption == "duration" { interrupted["duration"] = 100 }
            if interruption == "rate" { interrupted["rate"] = 2 }
            guard case .failed = operation.receive(try XCTUnwrap(YouTubeHandoffBridgeMessage(body: interrupted)), now: 10.6) else {
                XCTFail("Pending playback must fail on \(interruption)"); continue
            }
            XCTAssertEqual(operation.macPauseStatus, .unknown, interruption)
            XCTAssertNil(operation.completeMacPause(operationID: operation.request.id, result: .macPaused, now: 10.7))
            _ = try send(&operation, 5, now: 10.8, position: 20.7)
            XCTAssertFalse(operation.isCurrent(proof, now: 10.8))
            XCTAssertTrue(operation.isTerminal)
        }
    }

    func testCompletionRequiresFreshContinuingPhonePlaybackNotFreshOriginalProof() throws {
        var operation = try makeOperation()
        let proof = try confirm(&operation)
        XCTAssertTrue(operation.beginMacPause(using: proof, now: 10.5))
        _ = try send(&operation, 4, now: 11.4, position: 21.3)
        XCTAssertFalse(operation.isCurrent(proof, now: 11.4), "Old proof must not authorize another send")
        XCTAssertEqual(operation.completeMacPause(operationID: operation.request.id, result: .macPaused, now: 11.5), .movedToPhone)

        var silent = try makeOperation()
        let staleProof = try confirm(&silent)
        XCTAssertTrue(silent.beginMacPause(using: staleProof, now: 10.5))
        XCTAssertEqual(silent.completeMacPause(operationID: silent.request.id, result: .macPaused, now: 11.5), .failed(.playbackInterrupted))
        XCTAssertEqual(silent.macPauseStatus, .paused, "Retain the received native result without claiming continuing phone playback")
        XCTAssertFalse(silent.isCurrent(staleProof, now: 11.5))
    }

    func testMissingCompletionTimesOutUnknownAndDoesNotRenewOriginalDeadline() throws {
        var operation = try makeOperation()
        let proof = try confirm(&operation)
        XCTAssertTrue(operation.beginMacPause(using: proof, now: 10.5))
        XCTAssertNil(operation.poll(now: 13.49))
        XCTAssertEqual(operation.poll(now: 13.5), .failed(.macPauseUnknown))
        XCTAssertEqual(operation.macPauseStatus, .unknown)
        XCTAssertNil(operation.completeMacPause(operationID: operation.request.id, result: .macPaused, now: 13.6))

        let request = try YouTubeHandoffRequest(operationID: UUID(), videoID: "dQw4w9WgXcQ",
            positionSeconds: 20, durationSeconds: 200, playbackRate: 1, deadlineUptime: 10.8, now: 10)
        var short = YouTubeHandoffOperation(request: request, now: 10)
        _ = short.visibilityChanged(true, now: 10)
        let shortProof = try confirm(&short)
        XCTAssertTrue(short.beginMacPause(using: shortProof, now: 10.5))
        XCTAssertEqual(short.poll(now: 10.8), .failed(.macPauseUnknown))
        XCTAssertEqual(short.macPauseStatus, .unknown)

        var neverSent = try makeOperation()
        _ = try confirm(&neverSent)
        XCTAssertEqual(neverSent.poll(now: 40), .failed(.timedOut))
        XCTAssertEqual(neverSent.macPauseStatus, .notRequested)
    }

    func testEveryPendingFailureHasUncertainStatusAndNoAutomaticRecovery() throws {
        for reason in [YouTubeHandoffFailure.dismissed, .replaced, .notVisible, .wrongVideo,
                       .invalidBridge, .playerUnavailable, .clockChanged] {
            var operation = try makeOperation()
            let proof = try confirm(&operation)
            XCTAssertTrue(operation.beginMacPause(using: proof, now: 10.5))
            XCTAssertEqual(operation.fail(reason), .failed(reason))
            XCTAssertEqual(operation.macPauseStatus, .unknown)
            XCTAssertEqual(operation.phase.statusText(macPause: operation.macPauseStatus),
                           "The Mac’s pause status is uncertain. Check the Mac before trying another transfer.")
            XCTAssertNil(operation.completeMacPause(operationID: operation.request.id, result: .macPaused, now: 10.6))
            XCTAssertFalse(operation.beginMacPause(using: proof, now: 10.6))
        }
    }

    func testRejectedAndUnknownResultsStopPlayerWithoutClaimingMacStayedPlaying() throws {
        for result in [WebRTCMediaHandoffResult.notApplied, .outcomeUnknown] {
            var operation = try makeOperation()
            let proof = try confirm(&operation)
            XCTAssertTrue(operation.beginMacPause(using: proof, now: 10.5))
            XCTAssertEqual(operation.completeMacPause(operationID: operation.request.id, result: result, now: 10.6),
                           .failed(result == .notApplied ? .macPauseNotApplied : .macPauseUnknown))
            XCTAssertEqual(operation.macPauseStatus, result == .notApplied ? .notApplied : .unknown)
            XCTAssertFalse(operation.phase.statusText(macPause: operation.macPauseStatus).contains("No Mac pause was requested"))
            XCTAssertFalse(operation.isCurrent(proof, now: 10.6))
            XCTAssertNil(operation.completeMacPause(operationID: operation.request.id, result: .macPaused, now: 10.7))
        }
    }
}
