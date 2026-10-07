import Foundation
import XCTest
import WebRTCTransport
@testable import opensteamer

// Tests the actual production adapter against an independent frozen reference.
// No provider, WebView, phone, host, audio or transport is run.
final class BelugaRustYouTubeHandoffOperationTests: XCTestCase {
    private struct Pair {
        var actual: YouTubeHandoffOperation
        var original: FrozenYouTubeHandoffOperation
        var actualProof: YouTubePhonePlaybackEvidence?
        var originalProof: FrozenYouTubePlaybackEvidence?
    }
    private enum Action {
        case visibility(Bool, Double), poll(Double)
        case receive(YouTubeHandoffBridgeMessage, Double)
        case current(Double), begin(Double)
        case complete(UUID, WebRTCMediaHandoffResult, Double)
        case fail(YouTubeHandoffFailure)
    }
    private typealias Event = YouTubeHandoffOperation.Event
    private typealias Output = YouTubeHandoffOperation.Output
    private typealias Boundary = BelugaRustYouTubeHandoffOperationBoundary
    private enum FixtureError: Error { case noEvidence }

    private func request(position: Double = 20, observed: Double = 10,
                         deadline: Double = 40) throws -> YouTubeHandoffRequest {
        try .init(operationID: UUID(), videoID: "dQw4w9WgXcQ", positionSeconds: position,
                  durationSeconds: 200, playbackRate: 1, deadlineUptime: deadline,
                  now: 10, positionObservedAtUptime: observed)
    }
    private func pair(now: Double = 10, position: Double = 20,
                      observed: Double = 10, deadline: Double = 40,
                      nextToken: UInt64 = 1) throws -> Pair {
        let request = try request(position: position, observed: observed, deadline: deadline)
        let page = UUID()
        return Pair(actual: .init(request: request, pageID: page, now: now,
                                  nextEvidenceToken: nextToken),
                    original: .init(request: request, pageID: page, now: now))
    }
    private func message(_ pair: Pair, sequence: UInt32, kind: String = "sample",
                         position: Double = 20, state: Int = 1,
                         duration: Double = 200, rate: Double = 1,
                         operation: UUID? = nil, page: UUID? = nil,
                         video: String? = nil) throws -> YouTubeHandoffBridgeMessage {
        var body: [String: Any] = ["kind": kind,
            "operation": (operation ?? pair.actual.request.operationID).uuidString.lowercased(),
            "page": (page ?? pair.actual.pageID).uuidString.lowercased(),
            "video": video ?? pair.actual.request.videoID, "sequence": NSNumber(value: sequence)]
        if kind == "sample" {
            body["state"] = NSNumber(value: state); body["position"] = NSNumber(value: position)
            body["duration"] = NSNumber(value: duration); body["rate"] = NSNumber(value: rate)
        }
        return try XCTUnwrap(YouTubeHandoffBridgeMessage(body: body))
    }
    private func assertProof(_ actual: YouTubePhonePlaybackEvidence?,
                             _ original: FrozenYouTubePlaybackEvidence?,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual == nil, original == nil, file: file, line: line)
        guard let actual, let original else { return }
        // Fresh UUIDs are intentionally not compared across implementations.
        // Each implementation retains its own original proof and private UUID.
        XCTAssertEqual(actual.operationID, original.operationID, file: file, line: line)
        XCTAssertEqual(actual.videoID, original.videoID, file: file, line: line)
        XCTAssertEqual(actual.requestedPositionSeconds.bitPattern,
                       original.requestedPositionSeconds.bitPattern, file: file, line: line)
        XCTAssertEqual(actual.positionSeconds.bitPattern, original.positionSeconds.bitPattern, file: file, line: line)
        XCTAssertEqual(actual.playbackRate.bitPattern, original.playbackRate.bitPattern, file: file, line: line)
        XCTAssertEqual(actual.observedAtUptime.bitPattern, original.observedAtUptime.bitPattern, file: file, line: line)
    }
    private func assertEvent(_ actual: YouTubeHandoffPlayerEvent?, _ original: FrozenYouTubePlayerEvent?,
                             file: StaticString = #filePath, line: UInt = #line) {
        switch (actual, original) {
        case (nil, nil), (.playRequired?, .playRequired?), (.movedToPhone?, .movedToPhone?): break
        case (.failed(let a)?, .failed(let b)?): XCTAssertEqual(a, b, file: file, line: line)
        case (.confirmed(let a)?, .confirmed(let b)?): assertProof(a, b, file: file, line: line)
        default: XCTFail("Event differs: \(String(describing: actual)) / \(String(describing: original))", file: file, line: line)
        }
    }
    private func assertState(_ pair: Pair, file: StaticString = #filePath, line: UInt = #line) {
        let a = pair.actual, b = pair.original, raw = a.copiedStateForTesting
        XCTAssertEqual(a.phase, b.phase, file: file, line: line)
        XCTAssertEqual(a.macPauseStatus, b.macPauseStatus, file: file, line: line)
        XCTAssertEqual(a.isVisible, b.isVisible, file: file, line: line)
        XCTAssertEqual(a.isTerminal, b.isTerminal, file: file, line: line)
        assertProof(a.evidence, b.evidence, file: file, line: line)
        XCTAssertEqual(raw.last_now, b.lastNow.bitPattern, file: file, line: line)
        XCTAssertEqual(raw.sequence, b.sequence, file: file, line: line)
        let flags: UInt32 = (b.isVisible ? 1 : 0) | (b.hasBeenVisible ? 2 : 0)
            | (b.isReady ? 4 : 0) | (b.evidenceRevoked ? 8 : 0)
        let presence: UInt32 = (b.firstPlaying != nil ? 1 : 0) | (b.latestPlayingAt != nil ? 2 : 0)
            | (b.latestState != nil ? 4 : 0) | (b.evidence != nil ? 8 : 0)
            | (b.replyDeadlineUptime != nil ? 16 : 0)
        XCTAssertEqual(raw.flags, flags, file: file, line: line)
        XCTAssertEqual(raw.presence, presence, file: file, line: line)
        XCTAssertEqual(raw.first_position, b.firstPlaying?.position.bitPattern ?? 0, file: file, line: line)
        XCTAssertEqual(raw.first_at, b.firstPlaying?.now.bitPattern ?? 0, file: file, line: line)
        XCTAssertEqual(raw.latest_playing_at, b.latestPlayingAt?.bitPattern ?? 0, file: file, line: line)
        XCTAssertEqual(raw.latest_state, Int32(b.latestState ?? 0), file: file, line: line)
        XCTAssertEqual(raw.reply_deadline, b.replyDeadlineUptime?.bitPattern ?? 0, file: file, line: line)
        XCTAssertEqual(raw.request.position, b.request.positionSeconds.bitPattern, file: file, line: line)
        XCTAssertEqual(raw.request.duration, b.request.durationSeconds.bitPattern, file: file, line: line)
        XCTAssertEqual(raw.request.rate, b.request.playbackRate.bitPattern, file: file, line: line)
        XCTAssertEqual(raw.request.deadline, b.request.deadlineUptime.bitPattern, file: file, line: line)
        XCTAssertEqual(raw.request.position_observed_at, b.request.positionObservedAtUptime.bitPattern, file: file, line: line)
        if let evidence = b.evidence {
            XCTAssertNotEqual(raw.evidence.token, 0, file: file, line: line)
            XCTAssertEqual(raw.evidence.position, evidence.positionSeconds.bitPattern, file: file, line: line)
            XCTAssertEqual(raw.evidence.rate, evidence.playbackRate.bitPattern, file: file, line: line)
            XCTAssertEqual(raw.evidence.observed_at, evidence.observedAtUptime.bitPattern, file: file, line: line)
        } else { XCTAssertEqual(Boundary.proofWords(raw.evidence), [0, 0, 0, 0], file: file, line: line) }
    }
    @discardableResult
    private func apply(_ action: Action, to pair: inout Pair,
                       file: StaticString = #filePath, line: UInt = #line) -> YouTubeHandoffPlayerEvent? {
        var actual: YouTubeHandoffPlayerEvent?, original: FrozenYouTubePlayerEvent?
        switch action {
        case .visibility(let value, let now):
            actual = pair.actual.visibilityChanged(value, now: now)
            original = pair.original.visibilityChanged(value, now: now)
        case .poll(let now): actual = pair.actual.poll(now: now); original = pair.original.poll(now: now)
        case .receive(let value, let now):
            actual = pair.actual.receive(value, now: now); original = pair.original.receive(value, now: now)
        case .current(let now):
            if let a = pair.actualProof, let b = pair.originalProof {
                XCTAssertEqual(pair.actual.isCurrent(a, now: now), pair.original.isCurrent(b, now: now), file: file, line: line)
            }
        case .begin(let now):
            if let a = pair.actualProof, let b = pair.originalProof {
                XCTAssertEqual(pair.actual.beginMacPause(using: a, now: now),
                               pair.original.beginMacPause(using: b, now: now), file: file, line: line)
            }
        case .complete(let id, let result, let now):
            actual = pair.actual.completeMacPause(operationID: id, result: result, now: now)
            original = pair.original.completeMacPause(operationID: id, result: result, now: now)
        case .fail(let failure): actual = pair.actual.fail(failure); original = pair.original.fail(failure)
        }
        if case .confirmed(let proof) = actual { pair.actualProof = proof }
        if case .confirmed(let proof) = original { pair.originalProof = proof }
        assertEvent(actual, original, file: file, line: line)
        assertState(pair, file: file, line: line)
        return actual
    }
    private func prepare(_ pair: inout Pair, stage: Int = 2) throws {
        if stage == 0 { return }
        apply(.visibility(true, 10), to: &pair)
        apply(.receive(try message(pair, sequence: 1, kind: "ready"), 10), to: &pair)
        if stage == 1 { return }
        apply(.receive(try message(pair, sequence: 2), 10.1), to: &pair)
        let confirmed = apply(.receive(try message(pair, sequence: 3, position: 20.3), 10.4), to: &pair)
        guard case .confirmed = confirmed else { throw FixtureError.noEvidence }
        if stage >= 3 { apply(.begin(10.5), to: &pair) }
        if stage == 4 {
            apply(.complete(pair.actual.request.id, .macPaused, 10.6), to: &pair)
        } else if stage == 5 { apply(.fail(.dismissed), to: &pair) }
    }
    private func copiedOutput(_ operation: YouTubeHandoffOperation,
                              event: YouTubeHandoffPlayerEvent? = nil, accepted: Bool = false) -> Output {
        var output = Output(); output.state = operation.copiedStateForTesting
        output.status = 0; output.accepted = accepted ? 1 : 0
        switch event {
        case nil: break
        case .playRequired?: output.event = 1
        case .confirmed?: output.event = 2
        case .movedToPhone?: output.event = 3
        case .failed(let failure)?: output.event = 4; output.failure = failureCode(failure)
        }
        return output
    }
    private func failureCode(_ failure: YouTubeHandoffFailure) -> UInt32 {
        switch failure {
        case .invalidRequest: 1
        case .timedOut: 2
        case .notVisible: 3
        case .dismissed: 4
        case .replaced: 5
        case .playerUnavailable: 6
        case .wrongVideo: 7
        case .invalidBridge: 8
        case .clockChanged: 9
        case .unsupportedRate: 10
        case .positionChanged: 11
        case .playbackInterrupted: 12
        case .macPauseNotApplied: 13
        case .macPauseUnknown: 14
        }
    }
    private func rawReceive(_ pair: Pair, sequence: UInt32, now: Double,
                            kind: UInt32 = 2, position: Double = 20.3,
                            state: Int32 = 1, duration: Double = 200, rate: Double = 1) -> Event {
        var event = Event(); event.opcode = 2; event.flags = 14; event.kind = kind
        event.sequence = sequence; event.now = now.bitPattern; event.candidate_token = 1
        if kind == 2 {
            event.presence = 15; event.sample_state = state
            event.sample_position = position.bitPattern; event.sample_duration = duration.bitPattern
            event.sample_rate = rate.bitPattern
        }
        return event
    }
    private func assertRejected(_ source: YouTubeHandoffOperation, event: Event, output: Output,
                                expectedStatus: YouTubeHandoffMacPauseStatus? = nil,
                                file: StaticString = #filePath, line: UInt = #line) {
        let before = source.copiedStateForTesting, oldProof = source.evidence
        XCTAssertFalse(Boundary.accepts(before: before, event: event, output: output), file: file, line: line)
        var copy = source
        let response = copy.acceptCopiedResultForTesting(event, output: output)
        XCTAssertFalse(response.accepted, file: file, line: line)
        if source.isTerminal || event.opcode == 3 || event.opcode == 4 { XCTAssertNil(response.event, file: file, line: line) }
        else { XCTAssertEqual(response.event, .failed(.invalidBridge), file: file, line: line) }
        XCTAssertEqual(copy.phase, .failed(.invalidBridge), file: file, line: line)
        XCTAssertFalse(copy.isVisible, file: file, line: line)
        XCTAssertEqual(copy.evidence, oldProof, file: file, line: line)
        // Independent fallback oracle: a current correlated completion is an
        // already received native fact, even if the copied foreign result is bad.
        var honestStatus = source.macPauseStatus == .pending ? YouTubeHandoffMacPauseStatus.unknown : source.macPauseStatus
        let time = Double(bitPattern: event.now)
        if source.macPauseStatus == .pending, event.opcode == 5, event.flags == 32,
           time.isFinite, time >= Double(bitPattern: before.last_now),
           time < Double(bitPattern: before.reply_deadline), time < source.request.deadlineUptime {
            switch event.completion {
            case 1: honestStatus = .paused
            case 2: honestStatus = .notApplied
            case 3: honestStatus = .unknown
            default: break
            }
        }
        XCTAssertEqual(copy.macPauseStatus,
                       expectedStatus ?? honestStatus,
                       file: file, line: line)
        XCTAssertEqual(copy.copiedStateForTesting.last_now, before.last_now, file: file, line: line)
        XCTAssertEqual(copy.copiedStateForTesting.sequence, before.sequence, file: file, line: line)
    }

    func testFrozenOriginalConfirmationAndAllCompletionOutcomesMatch() throws {
        for outcome in [WebRTCMediaHandoffResult.macPaused, .notApplied, .outcomeUnknown] {
            var pair = try pair(); try prepare(&pair, stage: 3)
            apply(.complete(pair.actual.request.id, outcome, 10.6), to: &pair)
            apply(.complete(pair.actual.request.id, .macPaused, .nan), to: &pair)
            apply(.fail(.replaced), to: &pair)
            apply(.poll(.infinity), to: &pair)
        }
    }
    func testNativeMessageDomainsAndSequenceObservationOrderingMatch() throws {
        var pair = try pair(); try prepare(&pair, stage: 1)
        let before = Boundary.stateWords(pair.actual.copiedStateForTesting)
        for domain in 0..<3 {
            let foreign = try message(pair, sequence: .max, kind: "ready",
                operation: domain == 0 ? UUID() : domain == 2 ? pair.actual.pageID : nil,
                page: domain == 1 ? UUID() : domain == 2 ? pair.actual.request.id : nil)
            apply(.receive(foreign, .nan), to: &pair)
            XCTAssertEqual(Boundary.stateWords(pair.actual.copiedStateForTesting), before)
        }
        apply(.receive(try message(pair, sequence: 1, kind: "ready"), 9), to: &pair)
        XCTAssertEqual(pair.actual.phase, .failed(.clockChanged), "A stale matching message still observes time")
        var wrong = try self.pair(); try prepare(&wrong, stage: 1)
        apply(.receive(try message(wrong, sequence: .max, video: "aaaaaaaaaaa"), 10.1), to: &wrong)
        XCTAssertEqual(wrong.actual.copiedStateForTesting.sequence, .max, "Fresh wrong-video sequence burns before failure")
    }
    func testWholeNativeProofEqualityRejectsEveryPublicFieldMutation() throws {
        var base = try pair(); try prepare(&base)
        let a = try XCTUnwrap(base.actualProof), b = try XCTUnwrap(base.originalProof)
        let mutations: [(YouTubePhonePlaybackEvidence, FrozenYouTubePlaybackEvidence)] = [
            (a.copiedForBoundaryTesting(operationID: UUID()), b.copied(operationID: UUID())),
            (a.copiedForBoundaryTesting(videoID: "aaaaaaaaaaa"), b.copied(videoID: "aaaaaaaaaaa")),
            (a.copiedForBoundaryTesting(requestedPosition: 21), b.copied(requestedPosition: 21)),
            (a.copiedForBoundaryTesting(position: a.positionSeconds.nextUp), b.copied(position: b.positionSeconds.nextUp)),
            (a.copiedForBoundaryTesting(rate: 2), b.copied(rate: 2)),
            (a.copiedForBoundaryTesting(observedAt: a.observedAtUptime.nextDown), b.copied(observedAt: b.observedAtUptime.nextDown)),
            (a.copiedForBoundaryTesting(position: .nan), b.copied(position: .nan)),
            (a.copiedForBoundaryTesting(rate: .infinity), b.copied(rate: .infinity))]
        for (actualProof, originalProof) in mutations {
            var copy = base
            XCTAssertFalse(copy.actual.isCurrent(actualProof, now: 10.5))
            XCTAssertFalse(copy.original.isCurrent(originalProof, now: 10.5))
            XCTAssertFalse(copy.actual.beginMacPause(using: actualProof, now: 10.5))
            XCTAssertFalse(copy.original.beginMacPause(using: originalProof, now: 10.5))
            assertState(copy)
            XCTAssertTrue(copy.actual.isCurrent(a, now: 10.5), "Counterfeit cannot revoke an otherwise current owned proof")
        }
    }
    func testSignedZeroProofAliasUsesSwiftEqualityAndRetainsOriginalBits() throws {
        var pair = try pair(now: 0, position: -0.0, observed: -0.0)
        apply(.visibility(true, 0), to: &pair)
        apply(.receive(try message(pair, sequence: 1, kind: "ready"), 0), to: &pair)
        apply(.receive(try message(pair, sequence: 2, position: -0.0), 0), to: &pair)
        apply(.receive(try message(pair, sequence: 3, position: 0.3), 0.3), to: &pair)
        let a = try XCTUnwrap(pair.actualProof), b = try XCTUnwrap(pair.originalProof)
        XCTAssertEqual(a.requestedPositionSeconds.bitPattern, (-0.0).bitPattern)
        let alias = a.copiedForBoundaryTesting(requestedPosition: 0.0)
        XCTAssertEqual(alias, a)
        XCTAssertTrue(pair.actual.isCurrent(alias, now: 0.4))
        XCTAssertTrue(pair.original.isCurrent(b.copied(requestedPosition: 0.0), now: 0.4))
        assertState(pair)
        XCTAssertEqual(pair.actual.evidence?.requestedPositionSeconds.bitPattern, (-0.0).bitPattern)
    }
    func testArbitraryConstructorClockBitsPreserveOriginalObservationSemantics() throws {
        for initial in [-Double.infinity, -10, -0.0, 0, Double.infinity,
                        Double(bitPattern: 0x7ff8_0000_0000_0093)] {
            var pair = try pair(now: initial)
            assertState(pair)
            apply(.receive(try message(pair, sequence: .max, kind: "ready", page: UUID()), .nan), to: &pair)
            XCTAssertEqual(pair.actual.copiedStateForTesting.last_now, initial.bitPattern)
            apply(.visibility(true, initial == -Double.infinity ? -1 : 0), to: &pair)
            apply(.poll(0), to: &pair)
            apply(.fail(.dismissed), to: &pair)
            apply(.poll(.nan), to: &pair)
        }
        var negative = try pair(now: -Double.infinity)
        apply(.visibility(true, -1), to: &negative)
        apply(.receive(try message(negative, sequence: 1, kind: "ready"), -1), to: &negative)
        apply(.receive(try message(negative, sequence: 2), -1), to: &negative)
        apply(.receive(try message(negative, sequence: 3, position: 20.3), -0.7), to: &negative)
        XCTAssertEqual(negative.actual.evidence?.observedAtUptime, -0.7)
        apply(.current(-0.6), to: &negative)
    }
    func testAdjacentThresholdsAndUnrenewedProofAgeMatchFrozenArithmetic() throws {
        for elapsed in [Double(0.2).nextDown, 0.2, Double(0.2).nextUp,
                        Double(1.5).nextDown, 1.5, Double(1.5).nextUp] {
            // Zero origin keeps adjacent elapsed inputs distinct; adding a tiny
            // nextUp/nextDown to 10 first would round some into the same clock.
            var pair = try pair(now: 0)
            apply(.visibility(true, 0), to: &pair)
            apply(.receive(try message(pair, sequence: 1, kind: "ready"), 0), to: &pair)
            apply(.receive(try message(pair, sequence: 2, position: 20), 0), to: &pair)
            apply(.receive(try message(pair, sequence: 3, position: 20 + elapsed), elapsed), to: &pair)
        }
        for direction in -1...1 {
            var pair = try pair(); try prepare(&pair)
            let originalProof = try XCTUnwrap(pair.actualProof)
            let threshold = originalProof.observedAtUptime + 0.75
            let now = direction < 0 ? threshold.nextDown : direction > 0 ? threshold.nextUp : threshold
            let age = now - originalProof.observedAtUptime
            apply(.receive(try message(pair, sequence: 4, position: originalProof.positionSeconds + age), now), to: &pair)
            XCTAssertEqual(pair.actual.evidence, originalProof)
            apply(.current(now), to: &pair)
        }
        for now in [Double(13.5).nextDown, 13.5, Double(13.5).nextUp, 40] {
            var pair = try pair(); try prepare(&pair, stage: 3)
            apply(.poll(now), to: &pair)
        }
        for duration in [Double(201).nextDown, 201, Double(201).nextUp] {
            var pair = try pair(); try prepare(&pair, stage: 1)
            apply(.receive(try message(pair, sequence: 2, duration: duration), 10.1), to: &pair)
        }
        for rate in [Double(1.01).nextDown, 1.01, Double(1.01).nextUp] {
            var pair = try pair(); try prepare(&pair, stage: 1)
            apply(.receive(try message(pair, sequence: 2, rate: rate), 10.1), to: &pair)
        }
    }
    func testCopiesBeforeMintProduceNonSubstitutablePrivateEvidenceUUIDs() throws {
        var base = try pair(); try prepare(&base, stage: 1)
        apply(.receive(try message(base, sequence: 2), 10.1), to: &base)
        var first = base, second = base
        let sample = try message(base, sequence: 3, position: 20.3)
        apply(.receive(sample, 10.4), to: &first); apply(.receive(sample, 10.4), to: &second)
        let a = try XCTUnwrap(first.actualProof), a2 = try XCTUnwrap(second.actualProof)
        let b = try XCTUnwrap(first.originalProof), b2 = try XCTUnwrap(second.originalProof)
        XCTAssertNotEqual(a, a2, "Equal scalar tokens in two value copies cannot replace the private UUID")
        XCTAssertNotEqual(b, b2)
        XCTAssertFalse(first.actual.isCurrent(a2, now: 10.5))
        XCTAssertFalse(first.original.isCurrent(b2, now: 10.5))
        XCTAssertTrue(first.actual.isCurrent(a, now: 10.5))
        XCTAssertTrue(first.original.isCurrent(b, now: 10.5))
        XCTAssertTrue(second.actual.isCurrent(a2, now: 10.5))
        XCTAssertTrue(second.original.isCurrent(b2, now: 10.5))
        assertState(first); assertState(second)
    }
    func testCopiesWithExistingProofRevokeIndependentlyWithoutReminting() throws {
        var base = try pair(); try prepare(&base)
        var retired = base, continuing = base
        apply(.fail(.dismissed), to: &retired)
        apply(.current(10.5), to: &continuing)
        XCTAssertFalse(retired.actual.isCurrent(try XCTUnwrap(base.actualProof), now: 10.5))
        XCTAssertTrue(continuing.actual.isCurrent(try XCTUnwrap(base.actualProof), now: 10.5))
        XCTAssertEqual(retired.actual.evidence, continuing.actual.evidence)
        apply(.begin(10.5), to: &continuing)
        apply(.complete(continuing.actual.request.id, .macPaused, 10.6), to: &continuing)
        XCTAssertEqual(retired.actual.evidence, base.actual.evidence)
        XCTAssertNil(continuing.actual.evidence)
    }
    func testInterruptedOrStalePhonePlaybackPreservesTruthfulMacOutcome() throws {
        let failures: [YouTubeHandoffFailure] = [.invalidRequest, .timedOut, .notVisible, .dismissed,
            .replaced, .playerUnavailable, .wrongVideo, .invalidBridge, .clockChanged,
            .unsupportedRate, .positionChanged, .playbackInterrupted, .macPauseNotApplied, .macPauseUnknown]
        for stage in [0, 2, 3, 4] {
            for failure in failures {
                var pair = try pair(); try prepare(&pair, stage: stage)
                apply(.fail(failure), to: &pair)
                XCTAssertEqual(pair.actual.macPauseStatus,
                               stage == 3 ? .unknown : stage == 4 ? .paused : .notRequested)
                apply(.visibility(true, .nan), to: &pair)
            }
        }
        for pending in [false, true] {
            for interruption in ["blocked", "pause", "buffering", "duration", "rate", "seek"] {
                var pair = try pair(); try prepare(&pair, stage: pending ? 3 : 2)
                let kind = interruption == "blocked" ? "blocked" : "sample"
                let message = try message(pair, sequence: 4, kind: kind,
                    position: interruption == "seek" ? 80 : 20.4,
                    state: interruption == "pause" ? 2 : interruption == "buffering" ? 3 : 1,
                    duration: interruption == "duration" ? 100 : 200,
                    rate: interruption == "rate" ? 2 : 1)
                apply(.receive(message, 10.6), to: &pair)
                apply(.current(10.6), to: &pair)
                apply(.complete(pair.actual.request.id, .macPaused, 10.7), to: &pair)
                XCTAssertEqual(pair.actual.macPauseStatus, pending ? .unknown : .notRequested)
            }
        }
        var stale = try pair(); try prepare(&stale, stage: 3)
        apply(.complete(stale.actual.request.id, .macPaused, 11.5), to: &stale)
        XCTAssertEqual(stale.actual.phase, .failed(.playbackInterrupted))
        XCTAssertEqual(stale.actual.macPauseStatus, .paused)
        XCTAssertNotNil(stale.actual.evidence)
    }
    func testBooleanClockFailureIsSilentButRevokesAndRepeatBeginIsEarlyNoop() throws {
        var pair = try pair(); try prepare(&pair)
        apply(.current(9), to: &pair)
        XCTAssertEqual(pair.actual.phase, .failed(.clockChanged))
        var pending = try self.pair(); try prepare(&pending, stage: 3)
        let rawBefore = Boundary.stateWords(pending.actual.copiedStateForTesting)
        apply(.begin(.nan), to: &pending)
        apply(.complete(UUID(), .macPaused, .infinity), to: &pending)
        XCTAssertEqual(Boundary.stateWords(pending.actual.copiedStateForTesting), rawBefore)
        apply(.current(.nan), to: &pending)
        XCTAssertEqual(pending.actual.macPauseStatus, .unknown)
    }
    func testZeroCandidateDoesNotChangeBranchesThatCannotMint() throws {
        var pair = try pair(nextToken: 0)
        apply(.receive(try message(pair, sequence: .max, kind: "ready", operation: UUID()), .nan), to: &pair)
        apply(.visibility(true, 10), to: &pair)
        apply(.receive(try message(pair, sequence: 1, kind: "ready"), 10), to: &pair)
        apply(.receive(try message(pair, sequence: 1, kind: "ready"), 10.05), to: &pair)
        apply(.receive(try message(pair, sequence: 2, kind: "blocked"), 10.1), to: &pair)
        apply(.receive(try message(pair, sequence: 3, state: 2), 10.2), to: &pair)
        apply(.receive(try message(pair, sequence: 4), 10.3), to: &pair)
        apply(.receive(try message(pair, sequence: 5, position: 20), 10.31), to: &pair)
        XCTAssertFalse(pair.actual.isTerminal)
        XCTAssertNil(pair.actual.evidence)
    }
    func testMaximumTokenMintsOnceAndExistingProofPendingAndLocalBranchesRemainUsable() throws {
        var pair = try pair(nextToken: .max); try prepare(&pair)
        XCTAssertEqual(pair.actual.copiedStateForTesting.evidence.token, .max)
        apply(.receive(try message(pair, sequence: 4, position: 20.4), 10.5), to: &pair)
        apply(.begin(10.5), to: &pair)
        apply(.receive(try message(pair, sequence: 5, position: 20.5), 10.6), to: &pair)
        apply(.complete(pair.actual.request.id, .macPaused, 10.7), to: &pair)
        apply(.receive(try message(pair, sequence: 6, kind: "blocked"), 100), to: &pair)
        apply(.receive(try message(pair, sequence: .max, position: 80, state: 2, rate: 2), 101), to: &pair)
        XCTAssertEqual(pair.actual.phase, .localPlayback)
        XCTAssertEqual(pair.actual.macPauseStatus, .paused)
    }
    func testZeroCandidateOnlyEligibleMintFailsClosedAfterClockAndSequenceBurn() throws {
        var pair = try pair(nextToken: 0)
        apply(.visibility(true, 10), to: &pair)
        apply(.receive(try message(pair, sequence: 1, kind: "ready"), 10), to: &pair)
        apply(.receive(try message(pair, sequence: 2), 10.1), to: &pair)
        let final = try message(pair, sequence: 3, position: 20.3)
        XCTAssertEqual(pair.actual.receive(final, now: 10.4), .failed(.invalidBridge))
        guard case .confirmed = pair.original.receive(final, now: 10.4) else {
            return XCTFail("Fixture must be an eligible original mint, not an ignored branch")
        }
        XCTAssertEqual(pair.actual.phase, .failed(.invalidBridge))
        XCTAssertEqual(pair.actual.macPauseStatus, .notRequested)
        XCTAssertNil(pair.actual.evidence)
        XCTAssertEqual(pair.actual.copiedStateForTesting.sequence, 3)
        XCTAssertEqual(pair.actual.copiedStateForTesting.last_now, Double(10.4).bitPattern)
        XCTAssertNil(pair.actual.receive(final, now: 10.4))
    }
    func testLocalPlaybackNeverReopensHandoffAuthorityAndRetainsPausedOutcome() throws {
        var pair = try pair(); try prepare(&pair, stage: 4)
        for (index, state) in [2, 1, 3, 0, 5, -1].enumerated() {
            let now = Double(100 + index)
            apply(.receive(try message(pair, sequence: UInt32(4 + index), position: 80, state: state, rate: 2), now), to: &pair)
            apply(.poll(now), to: &pair); apply(.current(now), to: &pair); apply(.begin(.nan), to: &pair)
        }
        apply(.receive(try message(pair, sequence: 10, kind: "blocked"), 107), to: &pair)
        XCTAssertEqual(pair.actual.phase, .localPlayback)
        apply(.receive(try message(pair, sequence: 11, kind: "error"), 108), to: &pair)
        XCTAssertEqual(pair.actual.macPauseStatus, .paused)
    }
    private func alphabet(_ pair: Pair, now: Double = 10.6) throws -> [Action] {
        [.visibility(true, now), .visibility(false, now), .poll(now), .poll(9),
         .receive(try message(pair, sequence: 4, kind: "ready"), now),
         .receive(try message(pair, sequence: 4, kind: "blocked"), now),
         .receive(try message(pair, sequence: 4, position: 20.5), now),
         .receive(try message(pair, sequence: 4, state: 2), now),
         .receive(try message(pair, sequence: 4, kind: "error"), now),
         .receive(try message(pair, sequence: .max, kind: "unsupportedRate"), now),
         .receive(try message(pair, sequence: 1, kind: "ready"), now),
         .receive(try message(pair, sequence: .max, kind: "ready", page: UUID()), .nan),
         .current(now), .begin(now), .complete(pair.actual.request.id, .macPaused, now),
         .complete(pair.actual.request.id, .notApplied, now),
         .complete(UUID(), .outcomeUnknown, .nan), .fail(.replaced)]
    }
    func testBoundedReachableTraceParityChecksEveryCopiedScalarAndPublicEffect() throws {
        var traces = 0
        for stage in 0...5 {
            var base = try pair(); try prepare(&base, stage: stage)
            let actions = try alphabet(base)
            for first in actions {
                for second in actions {
                    var copy = base
                    apply(first, to: &copy); apply(second, to: &copy); traces += 1
                }
            }
        }
        XCTAssertEqual(traces, 1_944)
    }
    func testSeededLongTraceParityUsesFrozenOriginalWithoutDelegatingPolicy() throws {
        var seed: UInt64 = 0x4d_6f_76_65_50_68_6f_6e
        var steps = 0
        for trace in 0..<64 {
            var pair = try pair(); try prepare(&pair, stage: trace % 6)
            for index in 0..<128 {
                if index > 0 && index % 32 == 0 {
                    pair = try self.pair(); try prepare(&pair, stage: (trace + index / 32) % 6)
                }
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let now = 10.6 + Double(index % 32) * 0.125
                let actions = try alphabet(pair, now: now)
                apply(actions[Int(seed % UInt64(actions.count))], to: &pair); steps += 1
            }
        }
        XCTAssertEqual(steps, 8_192)
    }
    func testCopiedBoundaryAcceptsLegitimateMintFailureClearAndSilentBooleanResults() throws {
        var preparing = try pair(); try prepare(&preparing, stage: 1)
        apply(.receive(try message(preparing, sequence: 2), 10.1), to: &preparing)
        var afterMint = preparing.actual
        let minted = afterMint.receive(try message(preparing, sequence: 3, position: 20.3), now: 10.4)
        let mintEvent = rawReceive(preparing, sequence: 3, now: 10.4)
        XCTAssertTrue(Boundary.accepts(before: preparing.actual.copiedStateForTesting,
                                      event: mintEvent, output: copiedOutput(afterMint, event: minted)))
        var owned = try pair(); try prepare(&owned)
        let proof = try XCTUnwrap(owned.actualProof)
        var boolEvent = Event(); boolEvent.opcode = 3; boolEvent.flags = 16
        boolEvent.proof_token = owned.actual.copiedStateForTesting.evidence.token; boolEvent.now = Double(9).bitPattern
        var silent = owned.actual; XCTAssertFalse(silent.isCurrent(proof, now: 9))
        let silentOutput = copiedOutput(silent)
        XCTAssertTrue(Boundary.accepts(before: owned.actual.copiedStateForTesting, event: boolEvent, output: silentOutput))
        let response = owned.actual.acceptCopiedResultForTesting(boolEvent, output: silentOutput)
        XCTAssertNil(response.event); XCTAssertFalse(response.accepted)
        XCTAssertEqual(owned.actual.phase, .failed(.clockChanged))
        var pending = try pair(); try prepare(&pending, stage: 3)
        var complete = Event(); complete.opcode = 5; complete.flags = 32; complete.completion = 1
        complete.now = Double(10.6).bitPattern
        var success = pending.actual
        let moved = success.completeMacPause(operationID: success.request.id, result: .macPaused, now: 10.6)
        XCTAssertTrue(Boundary.accepts(before: pending.actual.copiedStateForTesting,
                                      event: complete, output: copiedOutput(success, event: moved)))
        complete.now = Double(11.5).bitPattern
        var stale = pending.actual
        let failure = stale.completeMacPause(operationID: stale.request.id, result: .macPaused, now: 11.5)
        XCTAssertTrue(Boundary.accepts(before: pending.actual.copiedStateForTesting,
                                      event: complete, output: copiedOutput(stale, event: failure)))
        XCTAssertEqual(stale.macPauseStatus, .paused)
        XCTAssertEqual(stale.evidence, pending.actual.evidence)
    }
    func testCopiedBoundaryRejectsForgedMintRetainedProofRewriteAndCleanup() throws {
        var base = try pair(); try prepare(&base, stage: 1)
        apply(.receive(try message(base, sequence: 2), 10.1), to: &base)
        var minted = base.actual
        let callback = minted.receive(try message(base, sequence: 3, position: 20.3), now: 10.4)
        let event = rawReceive(base, sequence: 3, now: 10.4)
        let legitimate = copiedOutput(minted, event: callback)
        let mintMutations: [(String, (inout Output) -> Void)] = [
            ("zero token", { $0.state.evidence.token = 0 }),
            ("foreign token", { $0.state.evidence.token = 2 }),
            ("wrong sample position", { $0.state.evidence.position = Double(30).bitPattern }),
            ("wrong sample rate", { $0.state.evidence.rate = Double(2).bitPattern }),
            ("renewed sample clock", { $0.state.evidence.observed_at = Double(10.5).bitPattern }),
            ("missing callback", { $0.event = 0 }),
            ("fabricated moved callback", { $0.event = 3 }),
            ("request rewrite", { $0.state.request.deadline = Double(41).bitPattern }),
            ("false-hidden mint", { $0.state.flags &= ~UInt32(1) }),
            ("visibility/ready authority invented", { $0.state.flags &= ~UInt32(4) })]
        for (_, mutation) in mintMutations {
            var malformed = legitimate; mutation(&malformed)
            assertRejected(base.actual, event: event, output: malformed)
        }
        var zeroCandidate = event; zeroCandidate.candidate_token = 0
        assertRejected(base.actual, event: zeroCandidate, output: legitimate)
        var foreign = event; foreign.flags = 6
        assertRejected(base.actual, event: foreign, output: legitimate)
        var firstSampleOwner = try pair(); try prepare(&firstSampleOwner, stage: 1)
        let firstSample = rawReceive(firstSampleOwner, sequence: 2, now: 10.4)
        var forgedFirstMint = legitimate
        forgedFirstMint.state.request = firstSampleOwner.actual.copiedStateForTesting.request
        forgedFirstMint.state.sequence = 2
        forgedFirstMint.state.first_position = firstSample.sample_position
        forgedFirstMint.state.first_at = firstSample.now
        XCTAssertEqual(firstSampleOwner.actual.copiedStateForTesting.presence & 1, 0)
        XCTAssertTrue(Boundary.valid(forgedFirstMint.state))
        assertRejected(firstSampleOwner.actual, event: firstSample, output: forgedFirstMint)
        var owned = try pair(); try prepare(&owned)
        var poll = Event(); poll.opcode = 1; poll.now = Double(10.5).bitPattern
        var retained = owned.actual; XCTAssertNil(retained.poll(now: 10.5))
        let validRetain = copiedOutput(retained)
        let retainMutations: [(inout Output) -> Void] = [
            { $0.state.evidence.token = 2 },
            { $0.state.evidence.position = Double(20.4).bitPattern },
            { $0.state.evidence.rate = Double(2).bitPattern },
            { $0.state.evidence.observed_at = Double(10.5).bitPattern },
            { $0.state.evidence = Boundary.Evidence(); $0.state.presence &= ~UInt32(8); $0.state.phase = 1 },
            { $0.state.sequence = 0 }, { $0.state.last_now = Double(10.4).bitPattern },
            { $0.state.flags &= ~UInt32(1) },
            { $0.state.request.position = Double(21).bitPattern }]
        for mutation in retainMutations { var output = validRetain; mutation(&output); assertRejected(owned.actual, event: poll, output: output) }
    }
    func testCopiedBoundaryRejectsMissingRevocationFictionalOutcomesAndReplay() throws {
        var owned = try pair(); try prepare(&owned)
        let blocked = rawReceive(owned, sequence: 4, now: 10.5, kind: 1)
        var blockedState = owned.actual
        let blockedCallback = blockedState.receive(try message(owned, sequence: 4, kind: "blocked"), now: 10.5)
        var unrevoked = copiedOutput(blockedState, event: blockedCallback)
        unrevoked.state.flags &= ~UInt32(8)
        assertRejected(owned.actual, event: blocked, output: unrevoked)
        for invalid in ["duration", "rate", "paused"] {
            let duration: Double = invalid == "duration" ? 100 : 200
            let rate: Double = invalid == "rate" ? 2 : 1
            let state: Int = invalid == "paused" ? 2 : 1
            var native = owned.actual
            let nativeEvent = native.receive(try message(owned, sequence: 4, position: 20.4,
                state: state, duration: duration, rate: rate), now: 10.5)
            var bad = copiedOutput(native, event: nativeEvent); bad.state.flags &= ~UInt32(8)
            assertRejected(owned.actual, event: rawReceive(owned, sequence: 4, now: 10.5,
                position: 20.4, state: Int32(state), duration: duration, rate: rate), output: bad)
        }
        var pending = try pair(); try prepare(&pending, stage: 3)
        var completion = Event(); completion.opcode = 5; completion.flags = 32
        completion.completion = 1; completion.now = Double(10.6).bitPattern
        var success = pending.actual
        let moved = success.completeMacPause(operationID: success.request.id, result: .macPaused, now: 10.6)
        let validSuccess = copiedOutput(success, event: moved)
        var falseHiddenSuccess = validSuccess; falseHiddenSuccess.state.flags &= ~UInt32(1)
        assertRejected(pending.actual, event: completion, output: falseHiddenSuccess, expectedStatus: .paused)
        var retainedSuccess = validSuccess
        retainedSuccess.state.evidence = pending.actual.copiedStateForTesting.evidence
        retainedSuccess.state.presence |= 8
        assertRejected(pending.actual, event: completion, output: retainedSuccess)
        var wrongResult = completion; wrongResult.completion = 2
        assertRejected(pending.actual, event: wrongResult, output: validSuccess)
        var foreign = completion; foreign.flags = 0
        assertRejected(pending.actual, event: foreign, output: validSuccess)
        var poll = Event(); poll.opcode = 1; poll.now = completion.now
        assertRejected(pending.actual, event: poll, output: validSuccess)
        assertRejected(success, event: completion, output: validSuccess, expectedStatus: .paused)
        var fictionalNotApplied = validSuccess; fictionalNotApplied.state.mac_pause = 3
        assertRejected(pending.actual, event: completion, output: fictionalNotApplied)
        var staleCompletion = completion; staleCompletion.now = Double(11.5).bitPattern
        var forgedStaleSuccess = validSuccess; forgedStaleSuccess.state.last_now = staleCompletion.now
        assertRejected(pending.actual, event: staleCompletion, output: forgedStaleSuccess, expectedStatus: .paused)
        var lateCompletion = completion; lateCompletion.now = Double(13.5).bitPattern
        var forgedLateSuccess = validSuccess; forgedLateSuccess.state.last_now = lateCompletion.now
        assertRejected(pending.actual, event: lateCompletion, output: forgedLateSuccess, expectedStatus: .unknown)
        // Retained-proof terminal outputs avoid the moved/clear prerequisites:
        // the completion outcome correlation itself must reject these fictions.
        for lateNow in [13.5, 40.0] {
            for (code, nativeResult, fictionalStatus) in [
                (UInt32(1), WebRTCMediaHandoffResult.macPaused, UInt32(2)),
                (UInt32(2), .notApplied, UInt32(3))] {
                var late = pending.actual
                _ = late.completeMacPause(operationID: late.request.id, result: nativeResult, now: lateNow)
                var expiredReply = completion; expiredReply.now = lateNow.bitPattern; expiredReply.completion = code
                var fictional = copiedOutput(late, event: .failed(.playbackInterrupted))
                fictional.state.failure = 12; fictional.state.mac_pause = fictionalStatus
                XCTAssertNotNil(late.evidence)
                XCTAssertEqual(fictional.state.presence, 8)
                XCTAssertTrue(Boundary.valid(fictional.state), "Well-shaped retained failure must fail correlation, not shape")
                assertRejected(pending.actual, event: expiredReply, output: fictional, expectedStatus: .unknown)
            }
        }
        for (code, honestStatus) in [(UInt32(1), YouTubeHandoffMacPauseStatus.paused), (2, .notApplied)] {
            var interrupted = pending.actual
            _ = interrupted.fail(.playbackInterrupted)
            var freshlyAdmitted = completion; freshlyAdmitted.completion = code
            var fictionalUnknown = copiedOutput(interrupted, event: .failed(.playbackInterrupted))
            fictionalUnknown.state.last_now = freshlyAdmitted.now
            XCTAssertEqual(fictionalUnknown.state.mac_pause, 4)
            XCTAssertEqual(fictionalUnknown.state.presence, 8)
            XCTAssertTrue(Boundary.valid(fictionalUnknown.state))
            assertRejected(pending.actual, event: freshlyAdmitted, output: fictionalUnknown, expectedStatus: honestStatus)
        }
        var pausedPoll = Event(); pausedPoll.opcode = 1; pausedPoll.now = Double(10.7).bitPattern
        var legitimatePaused = success; XCTAssertNil(legitimatePaused.poll(now: 10.7))
        var fictionalUnknown = copiedOutput(legitimatePaused); fictionalUnknown.state.mac_pause = 4
        assertRejected(success, event: pausedPoll, output: fictionalUnknown, expectedStatus: .paused)
    }
    func testMalformedCopiedOutputFailsClosedWithHonestStatusAndSilentBoolFallback() throws {
        let initial = try pair()
        var becameVisible = initial.actual
        XCTAssertNil(becameVisible.visibilityChanged(true, now: 10.1))
        var visibility = Event(); visibility.opcode = 0; visibility.flags = 1; visibility.now = Double(10.1).bitPattern
        var neverWasVisible = copiedOutput(becameVisible); neverWasVisible.state.flags = 1
        assertRejected(initial.actual, event: visibility, output: neverWasVisible)
        for stage in [0, 2, 3, 4, 5] {
            var pair = try pair(); try prepare(&pair, stage: stage)
            var poll = Event(); poll.opcode = 1; poll.now = Double(10.7).bitPattern
            var after = pair.actual
            let callback = after.poll(now: 10.7)
            let valid = copiedOutput(after, event: callback)
            let mutations: [(inout Output) -> Void] = [
                { $0.state.abi = 2 }, { $0.status = 1 }, { $0.event = 99 },
                { $0.accepted = 2 }, { $0.failure = 99 }, { $0.state.reserved = 1 },
                { $0.state.latest_state_reserved = 1 }, { $0.state.flags |= 16 },
                { $0.state.presence |= 32 }, { $0.state.phase = 99 }, { $0.state.mac_pause = 99 }]
            for mutation in mutations { var bad = valid; mutation(&bad); assertRejected(pair.actual, event: poll, output: bad) }
        }
        var owned = try pair(); try prepare(&owned)
        var query = Event(); query.opcode = 3; query.flags = 16
        query.proof_token = owned.actual.copiedStateForTesting.evidence.token; query.now = Double(10.5).bitPattern
        var checked = owned.actual; let accepted = checked.isCurrent(try XCTUnwrap(owned.actualProof), now: 10.5)
        var forgedCallback = copiedOutput(checked, accepted: accepted)
        forgedCallback.event = 4; forgedCallback.failure = 8
        assertRejected(owned.actual, event: query, output: forgedCallback)
        var falseCallback = copiedOutput(checked); falseCallback.event = 1
        assertRejected(owned.actual, event: query, output: falseCallback)
        var revokedAccepted = copiedOutput(checked, accepted: true); revokedAccepted.state.flags |= 8
        assertRejected(owned.actual, event: query, output: revokedAccepted)
        var hiddenAccepted = copiedOutput(checked, accepted: true); hiddenAccepted.state.flags &= ~UInt32(1)
        assertRejected(owned.actual, event: query, output: hiddenAccepted)
        var wrongProof = query; wrongProof.proof_token += 1
        assertRejected(owned.actual, event: wrongProof, output: copiedOutput(checked, accepted: true))
        var wrongOpcode = query; wrongOpcode.opcode = 99
        assertRejected(owned.actual, event: wrongOpcode, output: copiedOutput(checked, accepted: true))
        var extraProjection = query; extraProjection.flags |= 32
        assertRejected(owned.actual, event: extraProjection, output: copiedOutput(checked, accepted: true))
        var extraneousSample = query; extraneousSample.presence = 1; extraneousSample.sample_state = 1
        assertRejected(owned.actual, event: extraneousSample, output: copiedOutput(checked, accepted: true))
        var fail = Event(); fail.opcode = 6; fail.failure = 4
        assertRejected(owned.actual, event: fail, output: copiedOutput(owned.actual))
        var pending = try pair(); try prepare(&pending, stage: 3)
        for (completion, status) in [(UInt32(1), YouTubeHandoffMacPauseStatus.paused),
                                      (2, .notApplied), (3, .unknown)] {
            var nativeReply = Event(); nativeReply.opcode = 5; nativeReply.flags = 32
            nativeReply.completion = completion; nativeReply.now = Double(10.6).bitPattern
            var corrupted = copiedOutput(pending.actual); corrupted.status = 99
            assertRejected(pending.actual, event: nativeReply, output: corrupted, expectedStatus: status)
        }
        var beforeTerminal = owned.actual; XCTAssertEqual(beforeTerminal.fail(.dismissed), .failed(.dismissed))
        var terminal = copiedOutput(beforeTerminal); terminal.state.last_now = Double(11).bitPattern
        assertRejected(beforeTerminal, event: query, output: terminal)
        var resurrected = copiedOutput(owned.actual, accepted: true)
        assertRejected(beforeTerminal, event: query, output: resurrected)
    }
}
