import Foundation
import XCTest
@testable import WebRTCTransport

final class BelugaRustHandoffTransactionTests: XCTestCase {
    func testEveryReachableSmallTransactionStateAndEventMatchesOriginalReference() {
        var traces: [[TransactionEvent]] = [[]]
        var seen: Set<TransactionSnapshot> = [TransactionFixture().referenceSnapshot]
        var index = 0
        while index < traces.count {
            let prefix = traces[index]
            for event in Self.smallEvents {
                let fixture = TransactionFixture()
                for prior in prefix { fixture.step(prior, checking: false) }
                fixture.step(event)
                if seen.insert(fixture.referenceSnapshot).inserted {
                    traces.append(prefix + [event])
                }
            }
            index += 1
            guard traces.count <= 512 else {
                XCTFail("The finite receipt/envelope model escaped its expected state space")
                return
            }
        }
        XCTAssertGreaterThan(seen.count, 100, "Explore both owners, completed replies and real revocations")
    }

    func testSeededTransactionChurnMatchesStateResultsAndNativeRevocations() {
        for seed in UInt64(1)...UInt64(16) {
            let fixture = TransactionFixture()
            var random = seed
            for _ in 0..<512 {
                random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                fixture.step(Self.smallEvents[Int((random >> 32) % UInt64(Self.smallEvents.count))])
            }
            fixture.step(.clear)
            XCTAssertNil(fixture.actual.hostCommit)
            XCTAssertNil(fixture.actual.viewerCommit)
        }
    }

    func testHostAndViewerSlotsRemainIndependentAcrossFinishExpireAndReplacement() {
        let fixture = TransactionFixture()
        fixture.step(.admit(0))
        fixture.step(.begin(1))
        fixture.step(.finish(0, .macPaused))
        XCTAssertEqual(fixture.actual.viewerCommit, fixture.envelopes[1])
        fixture.step(.admit(2))
        fixture.step(.expire(Self.offerA))
        XCTAssertTrue(fixture.actual.hostIsBusy)
        XCTAssertEqual(fixture.actual.viewerCommit, fixture.envelopes[1])
        fixture.step(.expire(Self.offerB))
        XCTAssertTrue(fixture.actual.hostIsBusy)
        XCTAssertNil(fixture.actual.viewerCommit)
        XCTAssertTrue(fixture.actualReceipts[2].execution.isValid)
        fixture.step(.begin(0))
        fixture.step(.completion(1, .notApplied))
        XCTAssertEqual(fixture.actual.viewerCommit, fixture.envelopes[0])
        fixture.step(.completion(0, .notApplied))
        XCTAssertTrue(fixture.actual.hostIsBusy)
        XCTAssertTrue(fixture.actualReceipts[2].execution.isValid)
    }

    func testSameEnvelopeDifferentReceiptCannotFinishOrReplaceBusyHost() {
        let fixture = TransactionFixture()
        XCTAssertEqual(fixture.actualReceipts[0].envelope, fixture.actualReceipts[1].envelope)
        XCTAssertNotEqual(fixture.actualReceipts[0].receiptID, fixture.actualReceipts[1].receiptID)
        fixture.step(.admit(0))
        fixture.step(.admit(1))
        fixture.step(.finish(1, .macPaused))
        XCTAssertEqual(fixture.actual.hostCommit?.receiptID, fixture.actualReceipts[0].receiptID)
        XCTAssertNil(fixture.actual.hostReply)
        XCTAssertTrue(fixture.actualReceipts[0].execution.isValid)
        XCTAssertTrue(fixture.actualReceipts[1].execution.isValid)
        fixture.step(.finish(0, .notApplied))
        fixture.step(.admit(1))
        fixture.step(.finish(0, .macPaused))
        XCTAssertEqual(fixture.actual.hostCommit?.receiptID, fixture.actualReceipts[1].receiptID)
        XCTAssertNil(fixture.actual.hostReply)
        XCTAssertTrue(fixture.actualReceipts[1].execution.isValid)
    }

    func testEveryResultIsIdempotentAndConflictingReplyDoesNotChangeLedger() {
        for result in Self.results {
            let fixture = TransactionFixture()
            fixture.step(.admit(0))
            fixture.step(.finish(0, result))
            let storedReply = fixture.actual.hostReply
            XCTAssertEqual(storedReply?.result, result)
            XCTAssertFalse(fixture.actualReceipts[0].execution.isValid)
            fixture.step(.finish(0, result))
            XCTAssertEqual(fixture.actual.hostReply, storedReply)
            for conflict in Self.results where conflict != result {
                fixture.step(.finish(0, conflict))
                XCTAssertEqual(fixture.actual.hostReply, storedReply)
            }
            fixture.step(.begin(0))
            fixture.step(.completion(0, result))
            fixture.step(.completion(0, result))
            XCTAssertNil(fixture.actual.viewerCommit)
        }
    }

    func testClearAndReplacementRetireExactNativeReceiptWithoutRevokingAnother() {
        let fixture = TransactionFixture()
        fixture.step(.admit(0))
        fixture.step(.begin(1))
        fixture.step(.clear)
        XCTAssertFalse(fixture.actualReceipts[0].execution.isValid)
        XCTAssertTrue(fixture.actualReceipts[1].execution.isValid)
        XCTAssertTrue(fixture.actualReceipts[2].execution.isValid)
        fixture.step(.finish(0, .macPaused))
        fixture.step(.completion(1, .macPaused))
        fixture.step(.clear)
        fixture.step(.admit(2))
        fixture.step(.finish(2, .outcomeUnknown))
        fixture.step(.admit(1))
        fixture.step(.finish(2, .macPaused))
        XCTAssertEqual(fixture.actual.hostCommit?.receiptID, fixture.actualReceipts[1].receiptID)
        XCTAssertTrue(fixture.actualReceipts[1].execution.isValid)
        fixture.step(.clear)
        XCTAssertFalse(fixture.actualReceipts[1].execution.isValid)
    }

    func testClosedExpiredAndLostContinuityReceiptsPreserveCallerBoundaryBehavior() {
        for boundary in ["revoked", "expired", "continuity"] {
            let envelope = Self.envelope()
            let deadline = ProcessInfo.processInfo.systemUptime + (boundary == "expired" ? -1 : 3_600)
            let current = boundary != "continuity"
            let receipt = WebRTCReceivedMediaHandoffCommit(envelope: envelope, deadlineUptime: deadline,
                continuityIsCurrent: { current })
            if boundary == "revoked" { receipt.execution.revoke() }
            XCTAssertFalse(receipt.isValid, boundary)
            var actual = MediaHandoffTransactions()
            XCTAssertTrue(actual.admitHost(receipt), "Native validity belongs to the caller, not this ledger: \(boundary)")
            XCTAssertTrue(actual.hostIsBusy)
            XCTAssertEqual(actual.finishHost(receipt, result: .notApplied),
                .init(commit: envelope, result: .notApplied))
            XCTAssertFalse(receipt.execution.isValid)
            XCTAssertFalse(actual.hostIsBusy)
        }
    }

    func testMalformedViewerEnvelopeNeverAdmitsAndMismatchedCompletionNeverClears() {
        let invalid = [
            Self.envelope(sequence: 0), Self.envelope(context: ""), Self.envelope(context: "a\0b"),
            Self.envelope(context: String(repeating: "x", count: WebRTCRemoteMediaItem.maximumContextIDBytes + 1)),
            Self.envelope(videoID: "invalid!"), Self.envelope(position: -.infinity),
            Self.envelope(position: .nan), Self.envelope(position: -1), Self.envelope(position: 200),
            Self.envelope(duration: 0), Self.envelope(duration: .nan), Self.envelope(duration: .infinity),
            Self.envelope(duration: 31_536_001), Self.envelope(rate: 0), Self.envelope(rate: .nan),
            Self.envelope(rate: .infinity), Self.envelope(rate: 17)
        ]
        for envelope in invalid {
            XCTAssertFalse(envelope.isValid)
            var actual = MediaHandoffTransactions(), reference = TransactionReference()
            XCTAssertEqual(actual.beginViewer(envelope), reference.beginViewer(envelope))
            XCTAssertNil(actual.viewerCommit)
        }

        let valid = Self.envelope()
        let mismatches = [
            Self.envelope(authority: .init(id: Self.offerB)), Self.envelope(sequence: 2),
            Self.envelope(id: Self.offerB), Self.envelope(context: "other"),
            Self.envelope(videoID: "abcdefghijk"), Self.envelope(position: 21),
            Self.envelope(duration: 201), Self.envelope(rate: 2)
        ] + invalid
        for mismatch in mismatches {
            var actual = MediaHandoffTransactions(), reference = TransactionReference()
            XCTAssertTrue(actual.beginViewer(valid))
            XCTAssertTrue(reference.beginViewer(valid))
            for result in Self.results {
                let reply = WebRTCMediaHandoffCompletionEnvelope(commit: mismatch, result: result)
                XCTAssertEqual(actual.receiveCompletion(reply), reference.receiveCompletion(reply))
                XCTAssertEqual(actual.viewerCommit, valid)
            }
            XCTAssertEqual(actual.receiveCompletion(.init(commit: valid, result: .notApplied)),
                .init(id: valid.id, result: .notApplied))
        }
    }

    func testMalformedHostEnvelopeRetainsOriginalAdmissionAndEqualitySemantics() {
        for envelope in [Self.envelope(sequence: 0), Self.envelope(context: ""),
                         Self.envelope(position: .nan), Self.envelope(duration: .nan), Self.envelope(rate: .nan)] {
            let fixture = TransactionFixture(envelopes: [envelope], receiptEnvelopeIndices: [0])
            fixture.step(.admit(0))
            XCTAssertTrue(fixture.actual.hostIsBusy)
            fixture.step(.finish(0, .notApplied))
            if envelope == envelope {
                XCTAssertEqual(fixture.actual.hostReply?.result, .notApplied)
                XCTAssertFalse(fixture.actualReceipts[0].execution.isValid)
            } else {
                XCTAssertNil(fixture.actual.hostReply, "NaN preserves non-reflexive Swift envelope equality")
                XCTAssertTrue(fixture.actualReceipts[0].execution.isValid)
            }
            fixture.step(.clear)
            XCTAssertFalse(fixture.actualReceipts[0].execution.isValid)
        }
    }

    func testCanonicalEquivalentEnvelopeMatchesPreserveOriginalBytesAndNoSecondValidityGate() {
        for count in [1, WebRTCRemoteMediaItem.maximumContextIDBytes / 2] {
            let composed = Self.envelope(context: String(repeating: "é", count: count))
            let decomposed = Self.envelope(context: String(repeating: "e\u{301}", count: count))
            XCTAssertEqual(composed, decomposed)
            XCTAssertNotEqual(Array(composed.contextID.utf8), Array(decomposed.contextID.utf8))
            XCTAssertTrue(composed.isValid)
            if count > 1 { XCTAssertFalse(decomposed.isValid) }
            let fixture = TransactionFixture(envelopes: [composed, decomposed], receiptEnvelopeIndices: [0, 1])
            fixture.step(.admit(0))
            fixture.step(.begin(0))
            XCTAssertEqual(fixture.actual.viewerCommit.map { Array($0.contextID.utf8) }, Array(composed.contextID.utf8))
            fixture.step(.completion(1, .macPaused))
            XCTAssertNil(fixture.actual.viewerCommit, "Matching completion has no second envelope validity gate")
            fixture.step(.finish(0, .macPaused))
            XCTAssertEqual(fixture.actual.hostReply.map { Array($0.commit.contextID.utf8) }, Array(composed.contextID.utf8))
            fixture.step(.admit(1))
            fixture.step(.finish(0, .macPaused))
            XCTAssertNil(fixture.actual.hostReply, "Canonical equality is not receipt identity")
            fixture.step(.finish(1, .notApplied))
            XCTAssertEqual(fixture.actual.hostReply.map { Array($0.commit.contextID.utf8) }, Array(decomposed.contextID.utf8))
        }
    }

    func testValueCopiesKeepIndependentSlotsButShareNativeRevocation() {
        let fixture = TransactionFixture()
        fixture.step(.admit(0))
        fixture.step(.begin(1))
        var copy = fixture.actual
        XCTAssertEqual(copy.clear(), .init(id: Self.offerB, result: .outcomeUnknown))
        XCTAssertNil(copy.hostCommit)
        XCTAssertNil(copy.viewerCommit)
        XCTAssertTrue(fixture.actual.hostIsBusy)
        XCTAssertEqual(fixture.actual.viewerCommit, fixture.envelopes[1])
        XCTAssertFalse(fixture.actualReceipts[0].execution.isValid, "A copied ledger retains the exact native object")
        XCTAssertEqual(fixture.actual.finishHost(fixture.actualReceipts[0], result: .notApplied)?.result, .notApplied)
        XCTAssertEqual(fixture.actual.receiveCompletion(.init(commit: fixture.envelopes[1], result: .notApplied)),
            .init(id: Self.offerB, result: .notApplied))

        XCTAssertTrue(fixture.actual.admitHost(fixture.actualReceipts[2]))
        var finishingCopy = fixture.actual
        XCTAssertEqual(finishingCopy.finishHost(fixture.actualReceipts[2], result: .macPaused)?.result, .macPaused)
        XCTAssertFalse(fixture.actualReceipts[2].execution.isValid)
        XCTAssertNil(fixture.actual.hostReply, "Copied scalar state must not mutate the original slots")
        XCTAssertTrue(fixture.actual.hostIsBusy)
        XCTAssertEqual(fixture.actual.finishHost(fixture.actualReceipts[2], result: .outcomeUnknown)?.result, .outcomeUnknown)
        XCTAssertEqual(finishingCopy.hostReply?.result, .macPaused)
    }

    func testCopiedScalarBoundaryRejectsMissingRetirementEffectsAndReplay() {
        let empty = scalarState()
        let admitted = scalarState(hostPhase: 1, receipt: 11, envelope: 12)
        let replied = scalarState(hostPhase: 2, receipt: 11, envelope: 12, result: 1)
        var pending = admitted
        pending.viewer_envelope = 21; pending.viewer_offer = 22
        let finish = scalarEvent(1, receipt: 11, envelope: 12, result: 1)
        let complete = scalarEvent(3, envelope: 21, result: 1)
        let clear = scalarEvent(5)
        let legitimateFinish = scalarOutput(replied, effects: 3, revoked: 11)
        let legitimateCompletion = scalarOutput(admitted, effects: 4, completed: 22, result: 1)
        var cases: [(String, BelugaRustHandoffBoundary.State, BelugaRustHandoffBoundary.Event,
                     BelugaRustHandoffBoundary.Output)] = [
            ("clear drops host and viewer with no retirement effects", pending, clear, scalarOutput(empty)),
            ("first finish omits native revocation", admitted, finish, scalarOutput(replied, effects: 2)),
            ("completion replay claims no change and retains viewer", pending, complete,
             scalarOutput(pending, status: 2, effects: 4, completed: 22, result: 1)),
            ("clear retires viewer but omits host revocation", pending, clear,
             scalarOutput(empty, effects: 4, completed: 22, result: 3)),
            ("clear retires host but omits viewer outcome", pending, clear,
             scalarOutput(empty, effects: 1, revoked: 11)),
            ("wrong receipt borrows current host reply", admitted,
             scalarEvent(1, receipt: 31, envelope: 12, result: 1), legitimateFinish),
            ("wrong envelope borrows current host reply", admitted,
             scalarEvent(1, receipt: 11, envelope: 32, result: 1), legitimateFinish),
            ("wrong completion envelope retires current viewer", pending,
             scalarEvent(3, envelope: 31, result: 1), legitimateCompletion),
            ("wrong expiry offer retires current viewer", pending, scalarEvent(4, offer: 31),
             scalarOutput(admitted, effects: 4, completed: 22, result: 3)),
            ("clear falsely claims no change with live owners", pending, clear, scalarOutput(pending, status: 2)),
            ("clear is rejected while retaining live owners", pending, clear, scalarOutput(pending, status: 1)),
            ("arbitrary completion opcode fabricates no-change", pending, complete, scalarOutput(pending, status: 2)),
            ("completion emits another offer", pending, complete,
             scalarOutput(admitted, effects: 4, completed: 31, result: 1)),
            ("completion substitutes another result", pending, complete,
             scalarOutput(admitted, effects: 4, completed: 22, result: 2)),
            ("completion emits invalid result", pending, complete,
             scalarOutput(admitted, effects: 4, completed: 22, result: 4))
        ]
        var beginSuccess = scalarOutput(pending, effects: 1, revoked: 11)
        cases.append(("begin unexpectedly revokes independent host", admitted,
                      scalarEvent(2, envelope: 21, offer: 22, argument: 1), beginSuccess))
        beginSuccess = scalarOutput(pending, effects: 2)
        cases.append(("begin fabricates host reply", admitted,
                      scalarEvent(2, envelope: 21, offer: 22, argument: 1), beginSuccess))
        var malformed = legitimateFinish
        malformed.state.host_result = 2
        cases.append(("finish substitutes cached result", admitted, finish, malformed))
        malformed = legitimateFinish; malformed.revoked_receipt = 31
        cases.append(("revocation targets another native receipt", admitted, finish, malformed))
        malformed = legitimateFinish; malformed.status = 99
        cases.append(("unknown status", admitted, finish, malformed))
        malformed = legitimateFinish; malformed.state.abi_version = 2
        cases.append(("unknown successor ABI", admitted, finish, malformed))
        malformed = legitimateFinish; malformed.effects |= 8
        cases.append(("unknown effect", admitted, finish, malformed))
        malformed = legitimateFinish; malformed.reserved = 1
        cases.append(("nonzero output reserved", admitted, finish, malformed))
        malformed = legitimateFinish; malformed.state.reserved = 1
        cases.append(("nonzero state reserved", admitted, finish, malformed))
        malformed = legitimateFinish; malformed.status = 1
        cases.append(("rejected output changes state and effects", admitted, finish, malformed))
        malformed = legitimateFinish; malformed.status = 2
        cases.append(("no-change output changes host phase", admitted, finish, malformed))
        for (label, before, event, output) in cases {
            XCTAssertFalse(BelugaRustHandoffBoundary.accepts(before: before, event: event, output: output), label)
        }
    }

    func testCopiedScalarBoundaryAcceptsLegitimateCustodyTransitions() {
        let empty = scalarState()
        let admitted = scalarState(hostPhase: 1, receipt: 11, envelope: 12)
        let replied = scalarState(hostPhase: 2, receipt: 11, envelope: 12, result: 1)
        let replacement = scalarState(hostPhase: 1, receipt: 31, envelope: 32)
        var pending = admitted
        pending.viewer_envelope = 21; pending.viewer_offer = 22
        var viewerOnly = empty
        viewerOnly.viewer_envelope = 21; viewerOnly.viewer_offer = 22
        let cases: [(String, BelugaRustHandoffBoundary.State, BelugaRustHandoffBoundary.Event,
                     BelugaRustHandoffBoundary.Output)] = [
            ("initial admission", empty, scalarEvent(0, receipt: 11, envelope: 12), scalarOutput(admitted)),
            ("busy rejects replacement without effects", admitted, scalarEvent(0, receipt: 31, envelope: 32),
             scalarOutput(admitted, status: 1)),
            ("first finish revokes and returns exact reply", admitted,
             scalarEvent(1, receipt: 11, envelope: 12, result: 1), scalarOutput(replied, effects: 3, revoked: 11)),
            ("cached exact reply is the only changed-free reply effect", replied,
             scalarEvent(1, receipt: 11, envelope: 12, result: 1), scalarOutput(replied, status: 2, effects: 2)),
            ("conflicting finish has no effects", replied, scalarEvent(1, receipt: 11, envelope: 12, result: 2),
             scalarOutput(replied, status: 1)),
            ("replacement retires old receipt", replied, scalarEvent(0, receipt: 31, envelope: 32),
             scalarOutput(replacement, effects: 1, revoked: 11)),
            ("readmission of same receipt still retires old admission", replied,
             scalarEvent(0, receipt: 11, envelope: 12), scalarOutput(admitted, effects: 1, revoked: 11)),
            ("viewer admission preserves host", admitted, scalarEvent(2, envelope: 21, offer: 22, argument: 1),
             scalarOutput(pending)),
            ("invalid viewer admission is unchanged", admitted,
             scalarEvent(2, envelope: 21, offer: 22, argument: 0), scalarOutput(admitted, status: 1)),
            ("completion consumes viewer only", pending, scalarEvent(3, envelope: 21, result: 2),
             scalarOutput(admitted, effects: 4, completed: 22, result: 2)),
            ("expiry consumes viewer only as unknown", pending, scalarEvent(4, offer: 22),
             scalarOutput(admitted, effects: 4, completed: 22, result: 3)),
            ("clear retires both independent owners", pending, scalarEvent(5),
             scalarOutput(empty, effects: 5, revoked: 11, completed: 22, result: 3)),
            ("clear retires completed host receipt", replied, scalarEvent(5), scalarOutput(empty, effects: 1, revoked: 11)),
            ("clear reports pending viewer unknown", viewerOnly, scalarEvent(5),
             scalarOutput(empty, effects: 4, completed: 22, result: 3)),
            ("empty clear is unchanged without effects", empty, scalarEvent(5), scalarOutput(empty, status: 2))
        ]
        for (label, before, event, output) in cases {
            XCTAssertTrue(BelugaRustHandoffBoundary.accepts(before: before, event: event, output: output), label)
        }
    }

    private func scalarState(hostPhase: UInt32 = 0, receipt: UInt64 = 0, envelope: UInt64 = 0,
                             result: UInt32 = 0) -> BelugaRustHandoffBoundary.State {
        var value = BelugaRustHandoffBoundary.State()
        value.abi_version = 1; value.host_phase = hostPhase; value.host_receipt = receipt
        value.host_envelope = envelope; value.host_result = result
        return value
    }

    private func scalarEvent(_ opcode: UInt32, receipt: UInt64 = 0, envelope: UInt64 = 0,
                             offer: UInt64 = 0, result: UInt32 = 0, argument: UInt32 = 0)
        -> BelugaRustHandoffBoundary.Event {
        var value = BelugaRustHandoffBoundary.Event()
        value.opcode = opcode; value.argument = argument; value.receipt_token = receipt
        value.envelope_token = envelope; value.offer_token = offer; value.result = result
        return value
    }

    private func scalarOutput(_ state: BelugaRustHandoffBoundary.State, status: UInt32 = 0,
                              effects: UInt32 = 0, revoked: UInt64 = 0, completed: UInt64 = 0,
                              result: UInt32 = 0) -> BelugaRustHandoffBoundary.Output {
        var value = BelugaRustHandoffBoundary.Output()
        value.state = state; value.status = status; value.effects = effects
        value.revoked_receipt = revoked; value.completed_offer = completed; value.completed_result = result
        return value
    }

    fileprivate static let offerA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    fileprivate static let offerB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    fileprivate static let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    fileprivate static let results: [WebRTCMediaHandoffResult] = [.macPaused, .notApplied, .outcomeUnknown]

    fileprivate static func envelope(authority: WebRTCRemoteMediaAuthorization = .init(id: otherID),
                                     sequence: UInt64 = 1, id: UUID = offerA, context: String = "selected",
                                     videoID: String = "dQw4w9WgXcQ", position: Double = 20,
                                     duration: Double = 200, rate: Double = 1) -> WebRTCMediaHandoffCommitEnvelope {
        .init(offer: .init(authorization: authority, sequence: sequence, id: id, observedRevision: 1,
            contextID: context, videoID: videoID, positionSeconds: 20, durationSeconds: duration,
            playbackRate: rate, validForSeconds: 30), phonePositionSeconds: position)
    }

    private static var smallEvents: [TransactionEvent] {
        var values: [TransactionEvent] = [.clear, .expire(offerA), .expire(offerB), .expire(otherID)]
        for index in 0..<3 {
            values += [.admit(index), .begin(index), .revoke(index)]
            for result in results { values += [.finish(index, result), .completion(index, result)] }
        }
        return values
    }
}

private enum TransactionEvent {
    case admit(Int), finish(Int, WebRTCMediaHandoffResult), begin(Int)
    case completion(Int, WebRTCMediaHandoffResult), expire(UUID), clear, revoke(Int)
}

private enum TransactionOutcome: Equatable {
    case admitted(Bool), reply(ReplyProjection?), completion(WebRTCMediaHandoffCompletion?), noReturn
}

private final class TransactionFixture {
    var actual = MediaHandoffTransactions()
    private var reference = TransactionReference()
    let envelopes: [WebRTCMediaHandoffCommitEnvelope]
    let actualReceipts: [WebRTCReceivedMediaHandoffCommit]
    private let referenceReceipts: [WebRTCReceivedMediaHandoffCommit]

    init(envelopes: [WebRTCMediaHandoffCommitEnvelope] = [
        BelugaRustHandoffTransactionTests.envelope(),
        BelugaRustHandoffTransactionTests.envelope(id: BelugaRustHandoffTransactionTests.offerB, context: "other"),
        BelugaRustHandoffTransactionTests.envelope(context: "")
    ], receiptEnvelopeIndices: [Int] = [0, 0, 1]) {
        self.envelopes = envelopes
        let deadline = ProcessInfo.processInfo.systemUptime + 3_600
        actualReceipts = receiptEnvelopeIndices.map {
            .init(envelope: envelopes[$0], deadlineUptime: deadline, continuityIsCurrent: { true })
        }
        referenceReceipts = receiptEnvelopeIndices.map {
            .init(envelope: envelopes[$0], deadlineUptime: deadline, continuityIsCurrent: { true })
        }
    }

    var referenceSnapshot: TransactionSnapshot {
        snapshot(host: reference.hostCommit, reply: reference.hostReply, viewer: reference.viewerCommit,
                 busy: reference.hostIsBusy, receipts: referenceReceipts)
    }

    func step(_ event: TransactionEvent, checking: Bool = true,
              file: StaticString = #filePath, line: UInt = #line) {
        let actualOutcome: TransactionOutcome
        let referenceOutcome: TransactionOutcome
        switch event {
        case .admit(let index):
            actualOutcome = .admitted(actual.admitHost(actualReceipts[index]))
            referenceOutcome = .admitted(reference.admitHost(referenceReceipts[index]))
        case .finish(let index, let result):
            actualOutcome = .reply(actual.finishHost(actualReceipts[index], result: result).map(ReplyProjection.init))
            referenceOutcome = .reply(reference.finishHost(referenceReceipts[index], result: result).map(ReplyProjection.init))
        case .begin(let index):
            actualOutcome = .admitted(actual.beginViewer(envelopes[index]))
            referenceOutcome = .admitted(reference.beginViewer(envelopes[index]))
        case .completion(let index, let result):
            let reply = WebRTCMediaHandoffCompletionEnvelope(commit: envelopes[index], result: result)
            actualOutcome = .completion(actual.receiveCompletion(reply))
            referenceOutcome = .completion(reference.receiveCompletion(reply))
        case .expire(let id):
            actualOutcome = .completion(actual.expireViewer(id: id))
            referenceOutcome = .completion(reference.expireViewer(id: id))
        case .clear:
            actualOutcome = .completion(actual.clear())
            referenceOutcome = .completion(reference.clear())
        case .revoke(let index):
            actualReceipts[index].execution.revoke()
            referenceReceipts[index].execution.revoke()
            actualOutcome = .noReturn; referenceOutcome = .noReturn
        }
        guard checking else { return }
        XCTAssertEqual(actualOutcome, referenceOutcome, String(describing: event), file: file, line: line)
        XCTAssertEqual(snapshot(host: actual.hostCommit, reply: actual.hostReply, viewer: actual.viewerCommit,
                                busy: actual.hostIsBusy, receipts: actualReceipts),
                       referenceSnapshot, String(describing: event), file: file, line: line)
    }

    private func snapshot(host: WebRTCReceivedMediaHandoffCommit?, reply: WebRTCMediaHandoffCompletionEnvelope?,
                          viewer: WebRTCMediaHandoffCommitEnvelope?, busy: Bool,
                          receipts: [WebRTCReceivedMediaHandoffCommit]) -> TransactionSnapshot {
        .init(hostReceipt: host.flatMap { value in receipts.firstIndex { $0.receiptID == value.receiptID } },
              hostEnvelope: host.map { EnvelopeProjection($0.envelope) }, reply: reply.map(ReplyProjection.init),
              viewer: viewer.map(EnvelopeProjection.init), busy: busy,
              nativeValidity: receipts.map { $0.execution.isValid }, receiptValidity: receipts.map(\.isValid))
    }
}

private struct TransactionSnapshot: Hashable {
    let hostReceipt: Int?
    let hostEnvelope: EnvelopeProjection?
    let reply: ReplyProjection?
    let viewer: EnvelopeProjection?
    let busy: Bool
    let nativeValidity: [Bool]
    let receiptValidity: [Bool]
}

private struct ReplyProjection: Hashable {
    let commit: EnvelopeProjection
    let result: String
    init(_ reply: WebRTCMediaHandoffCompletionEnvelope) {
        commit = EnvelopeProjection(reply.commit); result = reply.result.rawValue
    }
}

private struct EnvelopeProjection: Hashable {
    let authority: UUID
    let sequence: UInt64
    let id: UUID
    let contextBytes: [UInt8]
    let videoBytes: [UInt8]
    let position: UInt64
    let duration: UInt64
    let rate: UInt64
    init(_ value: WebRTCMediaHandoffCommitEnvelope) {
        authority = value.authorization.id; sequence = value.sequence; id = value.id
        contextBytes = Array(value.contextID.utf8); videoBytes = Array(value.videoID.utf8)
        position = value.phonePositionSeconds.bitPattern; duration = value.durationSeconds.bitPattern
        rate = value.playbackRate.bitPattern
    }
}

/// Preserves the original Swift ledger, with independent native objects so reference revocation
/// cannot conceal a missing production FFI effect. Raw projections are only test observations.
private struct TransactionReference {
    private(set) var hostCommit: WebRTCReceivedMediaHandoffCommit?
    private(set) var hostReply: WebRTCMediaHandoffCompletionEnvelope?
    private(set) var viewerCommit: WebRTCMediaHandoffCommitEnvelope?
    var hostIsBusy: Bool { hostCommit != nil && hostReply == nil }

    mutating func admitHost(_ commit: WebRTCReceivedMediaHandoffCommit) -> Bool {
        guard !hostIsBusy else { return false }
        hostCommit?.execution.revoke()
        hostCommit = commit; hostReply = nil
        return true
    }

    mutating func finishHost(_ commit: WebRTCReceivedMediaHandoffCommit,
                             result: WebRTCMediaHandoffResult) -> WebRTCMediaHandoffCompletionEnvelope? {
        guard hostCommit?.receiptID == commit.receiptID, hostCommit?.envelope == commit.envelope else { return nil }
        if let hostReply { return hostReply.result == result ? hostReply : nil }
        commit.execution.revoke()
        let reply = WebRTCMediaHandoffCompletionEnvelope(commit: commit.envelope, result: result)
        hostReply = reply
        return reply
    }

    mutating func beginViewer(_ commit: WebRTCMediaHandoffCommitEnvelope) -> Bool {
        guard viewerCommit == nil, commit.isValid else { return false }
        viewerCommit = commit
        return true
    }

    mutating func receiveCompletion(_ reply: WebRTCMediaHandoffCompletionEnvelope) -> WebRTCMediaHandoffCompletion? {
        guard reply.commit == viewerCommit else { return nil }
        viewerCommit = nil
        return .init(id: reply.commit.id, result: reply.result)
    }

    mutating func expireViewer(id: UUID) -> WebRTCMediaHandoffCompletion? {
        guard viewerCommit?.id == id else { return nil }
        viewerCommit = nil
        return .init(id: id, result: .outcomeUnknown)
    }

    mutating func clear() -> WebRTCMediaHandoffCompletion? {
        let lost = viewerCommit.map { WebRTCMediaHandoffCompletion(id: $0.id, result: .outcomeUnknown) }
        hostCommit?.execution.revoke()
        hostCommit = nil; hostReply = nil; viewerCommit = nil
        return lost
    }
}
