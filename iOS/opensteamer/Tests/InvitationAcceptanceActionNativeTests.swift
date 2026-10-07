import Foundation
import RemoteSessionCore
import XCTest
@testable import opensteamer

// Independent frozen native reference; not an implementation or copied-result validator.
// Frozen source: InvitationAcceptanceAction.swift SHA ed62b5fdee54b2676a45e6d98038cd4b971f377d0835f675e7399a261005759e.
@MainActor
private struct FrozenInvitationAcceptanceReference {
    private struct Armed {
        let generation: UUID
        let admission: (@MainActor () throws -> Void)?
        let completion: @MainActor (RemotePairedDeviceRecord) throws -> Void
        var admissionPersisted: Bool
    }
    private var armed: Armed?

    mutating func arm(
        generation: UUID,
        admission: (@MainActor () throws -> Void)?,
        completion: @escaping @MainActor (RemotePairedDeviceRecord) throws -> Void
    ) {
        armed = Armed(generation: generation, admission: admission,
                      completion: completion, admissionPersisted: false)
    }

    mutating func admit(_ record: RemotePairedDeviceRecord, generation: UUID) throws {
        guard let current = armed, current.generation == generation,
              !current.admissionPersisted else { return }
        guard record.pairingState == .acceptedIssued else {
            throw InvitationAcceptanceError.pairingIsNotRecoverable
        }
        try current.admission?()
        armed?.admissionPersisted = true
    }

    mutating func complete(_ record: RemotePairedDeviceRecord, generation: UUID) throws -> Bool {
        guard let current = armed, current.generation == generation else { return false }
        guard record.pairingState == .active else {
            throw InvitationAcceptanceError.pairingIsNotActive
        }
        try current.completion(record)
        armed = nil
        return true
    }

    mutating func cancel(_ generation: UUID) {
        guard armed?.generation == generation else { return }
        armed = nil
    }
}

@MainActor
private final class InvitationCallbackRecorder {
    enum Failure: Error, Equatable { case admission, completion }
    var failAdmission = false
    var failCompletion = false
    var events: [String] = []
    var deliveredRecords: [RemotePairedDeviceRecord] = []

    func admit(_ label: String) throws {
        events.append(label + ".admission")
        if failAdmission { throw Failure.admission }
    }

    func complete(_ record: RemotePairedDeviceRecord, label: String) throws {
        events.append(label + ".completion")
        deliveredRecords.append(record)
        if failCompletion { throw Failure.completion }
    }
}

private enum InvitationOutcome: Equatable {
    case returnedVoid
    case completed(Bool)
    case pairingError(InvitationAcceptanceError)
    case callbackFailure(InvitationCallbackRecorder.Failure)
    case unexpectedError
}

@MainActor
private struct InvitationActionProbe {
    private var subject = InvitationAcceptanceAction()
    private var original = FrozenInvitationAcceptanceReference()
    let actual = InvitationCallbackRecorder()
    let expected = InvitationCallbackRecorder()

    mutating func arm(_ generation: UUID, admission: Bool = true, label: String = "owner") {
        let actual = actual
        let expected = expected
        let actualAdmission: (@MainActor () throws -> Void)?
        let expectedAdmission: (@MainActor () throws -> Void)?
        if admission {
            actualAdmission = { try actual.admit(label) }
            expectedAdmission = { try expected.admit(label) }
        } else {
            actualAdmission = nil
            expectedAdmission = nil
        }
        subject.arm(generation: generation, onAdmitted: actualAdmission) {
            try actual.complete($0, label: label)
        }
        original.arm(generation: generation, admission: expectedAdmission) {
            try expected.complete($0, label: label)
        }
    }

    func setFailures(admission: Bool = false, completion: Bool = false) {
        actual.failAdmission = admission
        expected.failAdmission = admission
        actual.failCompletion = completion
        expected.failCompletion = completion
    }

    mutating func admit(_ record: RemotePairedDeviceRecord, _ generation: UUID,
                        file: StaticString = #filePath, line: UInt = #line) -> InvitationOutcome {
        let got: InvitationOutcome
        do {
            try subject.persistAdmissionAfterRecoverablePairing(record, generation: generation)
            got = .returnedVoid
        } catch { got = Self.classify(error) }
        let want: InvitationOutcome
        do { try original.admit(record, generation: generation); want = .returnedVoid }
        catch { want = Self.classify(error) }
        check(got, want, file: file, line: line)
        return got
    }

    mutating func complete(_ record: RemotePairedDeviceRecord, _ generation: UUID,
                           file: StaticString = #filePath, line: UInt = #line) -> InvitationOutcome {
        let got: InvitationOutcome
        do { got = .completed(try subject.completeAuthenticatedPairing(record, generation: generation)) }
        catch { got = Self.classify(error) }
        let want: InvitationOutcome
        do { want = .completed(try original.complete(record, generation: generation)) }
        catch { want = Self.classify(error) }
        check(got, want, file: file, line: line)
        return got
    }

    mutating func cancel(_ generation: UUID, file: StaticString = #filePath, line: UInt = #line) {
        subject.cancel(generation: generation)
        original.cancel(generation)
        check(.returnedVoid, .returnedVoid, file: file, line: line)
    }

    private func check(_ got: InvitationOutcome, _ want: InvitationOutcome,
                       file: StaticString, line: UInt) {
        XCTAssertEqual(got, want, file: file, line: line)
        XCTAssertEqual(actual.events, expected.events, file: file, line: line)
        XCTAssertEqual(actual.deliveredRecords, expected.deliveredRecords, file: file, line: line)
    }

    private static func classify(_ error: Error) -> InvitationOutcome {
        if let value = error as? InvitationAcceptanceError { return .pairingError(value) }
        if let value = error as? InvitationCallbackRecorder.Failure { return .callbackFailure(value) }
        return .unexpectedError
    }
}

// Native cryptographic value construction only; no store, transport, Keychain or live owner.
private struct InvitationNativeRecords {
    let pending: RemotePairedDeviceRecord
    let recoverable: RemotePairedDeviceRecord
    let active: RemotePairedDeviceRecord
    let hostAccepted: RemotePairedDeviceRecord

    static func make() throws -> Self {
        let invitation = try RemoteInvitationCode.generate()
        let host = try RemoteDeviceIdentity.generate(role: .host, displayName: "Private test Mac")
        let viewer = try RemoteDeviceIdentity.generate(role: .viewer)
        let hostParticipant = try RemotePairingParticipant(identity: host, invitation: invitation)
        let viewerParticipant = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        let hostAgreement = try hostParticipant.accept(viewerParticipant.hello)
        let viewerAgreement = try viewerParticipant.accept(hostParticipant.hello)
        let pending = try viewerAgreement.makePendingRecord(peerConfirmation: hostAgreement.makeConfirmation())
        var hostRecord = try hostAgreement.makePendingRecord(peerConfirmation: viewerAgreement.makeConfirmation())
        let proposal = try hostRecord.prepareProposal(using: host)
        var recoverable = pending
        let acknowledgement = try recoverable.prepareAcknowledgement(after: proposal, using: viewer)
        try hostRecord.acceptAcknowledgement(acknowledgement)
        let completion = try hostRecord.prepareCompletion(using: host)
        let hostAccepted = hostRecord
        var active = recoverable
        _ = try active.acceptCompletion(completion, using: viewer)
        return Self(pending: pending, recoverable: recoverable, active: active, hostAccepted: hostAccepted)
    }
}

@MainActor
final class BelugaRustInvitationAcceptanceActionTests: XCTestCase {
    private let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let foreign = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    func testUnarmedCallsReturnBeforeEveryPairingPhaseGuard() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe()
        for record in [f.pending, f.recoverable, f.hostAccepted, f.active] {
            XCTAssertEqual(p.admit(record, owner), .returnedVoid)
            XCTAssertEqual(p.complete(record, owner), .completed(false))
        }
        XCTAssertEqual(p.actual.events, [])
    }

    func testForeignGenerationReturnsBeforeRecoverableAndActiveValidation() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner)
        for record in [f.pending, f.recoverable, f.hostAccepted, f.active] {
            XCTAssertEqual(p.admit(record, foreign), .returnedVoid)
            XCTAssertEqual(p.complete(record, foreign), .completed(false))
        }
        XCTAssertEqual(p.actual.events, [])
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
    }

    func testExactGenerationRejectsEveryNonRecoverablePhaseWithoutCallback() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner)
        for record in [f.pending, f.hostAccepted, f.active] {
            XCTAssertEqual(p.admit(record, owner), .pairingError(.pairingIsNotRecoverable))
        }
        XCTAssertEqual(p.actual.events, [])
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        XCTAssertEqual(p.actual.events, ["owner.admission"])
    }

    func testExactGenerationRejectsEveryNonActivePhaseWithoutCallback() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner)
        for record in [f.pending, f.recoverable, f.hostAccepted] {
            XCTAssertEqual(p.complete(record, owner), .pairingError(.pairingIsNotActive))
        }
        XCTAssertEqual(p.actual.events, [])
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
    }

    func testSuccessfulAdmissionRunsOnceAndDuplicateReturnsBeforePhaseCheck() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner)
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        for record in [f.recoverable, f.pending, f.hostAccepted, f.active] {
            XCTAssertEqual(p.admit(record, owner), .returnedVoid)
        }
        XCTAssertEqual(p.actual.events, ["owner.admission"])
    }

    func testAbsentAdmissionCallbackStillConsumesTheAcceptedIssuedBoundary() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner, admission: false)
        XCTAssertEqual(p.admit(f.pending, owner), .pairingError(.pairingIsNotRecoverable))
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        XCTAssertEqual(p.admit(f.pending, owner), .returnedVoid)
        XCTAssertEqual(p.actual.events, [])
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
    }

    func testThrowingAdmissionPreservesRetryAndConsumesOnlyAfterSuccess() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner); p.setFailures(admission: true)
        XCTAssertEqual(p.admit(f.recoverable, owner), .callbackFailure(.admission))
        XCTAssertEqual(p.admit(f.pending, owner), .pairingError(.pairingIsNotRecoverable))
        XCTAssertEqual(p.admit(f.recoverable, owner), .callbackFailure(.admission))
        p.setFailures()
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        XCTAssertEqual(p.admit(f.pending, owner), .returnedVoid)
        XCTAssertEqual(p.actual.events, Array(repeating: "owner.admission", count: 3))
    }

    func testCompletionDoesNotRequireAnAdmissionCallOrSuccessfulAdmission() throws {
        let f = try InvitationNativeRecords.make()
        var fresh = InvitationActionProbe(); fresh.arm(owner)
        XCTAssertEqual(fresh.complete(f.active, owner), .completed(true))
        XCTAssertEqual(fresh.actual.events, ["owner.completion"])
        var failedAdmission = InvitationActionProbe(); failedAdmission.arm(owner)
        failedAdmission.setFailures(admission: true)
        XCTAssertEqual(failedAdmission.admit(f.recoverable, owner), .callbackFailure(.admission))
        XCTAssertEqual(failedAdmission.complete(f.active, owner), .completed(true))
        XCTAssertEqual(failedAdmission.actual.events, ["owner.admission", "owner.completion"])
    }

    func testThrowingCompletionDoesNotRetireEitherCallback() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner); p.setFailures(completion: true)
        XCTAssertEqual(p.complete(f.active, owner), .callbackFailure(.completion))
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        XCTAssertEqual(p.complete(f.pending, owner), .pairingError(.pairingIsNotActive))
        p.setFailures()
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
        XCTAssertEqual(p.actual.events, ["owner.completion", "owner.admission", "owner.completion"])
    }

    func testThrowingCompletionPreservesAlreadyConsumedAdmission() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner)
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        p.setFailures(completion: true)
        XCTAssertEqual(p.complete(f.active, owner), .callbackFailure(.completion))
        XCTAssertEqual(p.admit(f.pending, owner), .returnedVoid)
        p.setFailures()
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
        XCTAssertEqual(p.actual.events, ["owner.admission", "owner.completion", "owner.completion"])
    }

    func testSuccessfulCompletionRetiresAllGatesBeforeAnyLatePhaseCheck() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner)
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
        for record in [f.pending, f.recoverable, f.hostAccepted, f.active] {
            XCTAssertEqual(p.admit(record, owner), .returnedVoid)
            XCTAssertEqual(p.complete(record, owner), .completed(false))
        }
        XCTAssertEqual(p.actual.events, ["owner.admission", "owner.completion"])
    }

    func testForeignCancelCannotRetireOrResetTheCurrentOwner() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner)
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        p.cancel(foreign)
        XCTAssertEqual(p.admit(f.pending, owner), .returnedVoid)
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
        XCTAssertEqual(p.actual.events, ["owner.admission", "owner.completion"])
    }

    func testExactCancelRetiresAllGatesAndIsIdempotent() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner); p.cancel(owner); p.cancel(owner)
        XCTAssertEqual(p.admit(f.pending, owner), .returnedVoid)
        XCTAssertEqual(p.complete(f.pending, owner), .completed(false))
        XCTAssertEqual(p.complete(f.active, owner), .completed(false))
        XCTAssertEqual(p.actual.events, [])
    }

    func testRearmWithDifferentGenerationReplacesClosuresAndRejectsTheOldOwner() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner, label: "old")
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        p.arm(foreign, label: "new")
        XCTAssertEqual(p.complete(f.active, owner), .completed(false))
        p.cancel(owner)
        XCTAssertEqual(p.admit(f.recoverable, foreign), .returnedVoid)
        XCTAssertEqual(p.complete(f.active, foreign), .completed(true))
        XCTAssertEqual(p.actual.events, ["old.admission", "new.admission", "new.completion"])
    }

    func testSameUUIDRearmResetsConsumptionAndInstallsOnlyNewClosures() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner, label: "old")
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        p.arm(owner, label: "new")
        XCTAssertEqual(p.admit(f.pending, owner), .pairingError(.pairingIsNotRecoverable))
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
        XCTAssertEqual(p.actual.events, ["old.admission", "new.admission", "new.completion"])
    }

    func testRearmAfterCompletionOrCancellationCreatesFreshAuthority() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner)
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
        p.arm(owner, label: "after-complete"); p.cancel(owner)
        p.arm(owner, label: "after-cancel")
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
        XCTAssertEqual(p.actual.events, ["owner.completion", "after-cancel.admission", "after-cancel.completion"])
    }

    func testCallbackReceivesExactSuppliedRecordWithoutInventedPairBinding() throws {
        let first = try InvitationNativeRecords.make()
        let second = try InvitationNativeRecords.make()
        XCTAssertNotEqual(first.active.pairID, second.active.pairID)
        var p = InvitationActionProbe(); p.arm(owner)
        XCTAssertEqual(p.admit(first.recoverable, owner), .returnedVoid)
        XCTAssertEqual(p.complete(second.active, owner), .completed(true))
        XCTAssertEqual(p.actual.deliveredRecords, [second.active])
    }

    func testCopiesBeforeAdmissionHaveIndependentOnceOnlyGates() throws {
        let f = try InvitationNativeRecords.make()
        var first = InvitationActionProbe(); first.arm(owner)
        var copy = first
        XCTAssertEqual(first.admit(f.recoverable, owner), .returnedVoid)
        XCTAssertEqual(copy.admit(f.recoverable, owner), .returnedVoid)
        XCTAssertEqual(first.complete(f.active, owner), .completed(true))
        XCTAssertEqual(copy.complete(f.active, owner), .completed(true))
        XCTAssertEqual(first.actual.events, ["owner.admission", "owner.admission", "owner.completion", "owner.completion"])
    }

    func testCopiesAfterAdmissionPreserveConsumptionButRetireIndependently() throws {
        let f = try InvitationNativeRecords.make()
        var first = InvitationActionProbe(); first.arm(owner)
        XCTAssertEqual(first.admit(f.recoverable, owner), .returnedVoid)
        var copy = first
        first.cancel(owner)
        XCTAssertEqual(first.complete(f.active, owner), .completed(false))
        XCTAssertEqual(copy.admit(f.pending, owner), .returnedVoid)
        XCTAssertEqual(copy.complete(f.active, owner), .completed(true))
        XCTAssertEqual(first.actual.events, ["owner.admission", "owner.completion"])
    }

    func testRearmingOneValueCopyCannotReplaceAnotherCopiesClosure() throws {
        let f = try InvitationNativeRecords.make()
        var first = InvitationActionProbe(); first.arm(owner, label: "original")
        var copy = first
        first.arm(owner, label: "replacement")
        XCTAssertEqual(copy.complete(f.active, owner), .completed(true))
        XCTAssertEqual(first.complete(f.active, owner), .completed(true))
        XCTAssertEqual(first.actual.events, ["original.completion", "replacement.completion"])
    }

    func testThrowingCallbacksRetainActualEffectsButPermitRetry() throws {
        let f = try InvitationNativeRecords.make()
        var p = InvitationActionProbe(); p.arm(owner)
        p.setFailures(admission: true, completion: true)
        XCTAssertEqual(p.admit(f.recoverable, owner), .callbackFailure(.admission))
        XCTAssertEqual(p.complete(f.active, owner), .callbackFailure(.completion))
        p.setFailures()
        XCTAssertEqual(p.admit(f.recoverable, owner), .returnedVoid)
        XCTAssertEqual(p.complete(f.active, owner), .completed(true))
        XCTAssertEqual(p.actual.events, ["owner.admission", "owner.completion", "owner.admission", "owner.completion"])
        XCTAssertEqual(p.actual.deliveredRecords, [f.active, f.active])
    }

    func testSeededTracePreservesFrozenOrderingOutcomesCallbacksAndRecords() throws {
        let f = try InvitationNativeRecords.make()
        let records = [f.pending, f.recoverable, f.hostAccepted, f.active]
        var p = InvitationActionProbe()
        var seed: UInt64 = 0x5a1706
        for ordinal in 0..<2_000 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let generation = (seed & 16) == 0 ? owner : foreign
            let record = records[Int((seed >> 8) & 3)]
            switch seed & 7 {
            case 0: p.arm(generation, admission: (seed & 32) != 0, label: "g\(ordinal)")
            case 1, 2: _ = p.admit(record, generation)
            case 3, 4: _ = p.complete(record, generation)
            case 5: p.cancel(generation)
            case 6: p.setFailures(admission: (seed & 64) != 0, completion: (seed & 128) != 0)
            default:
                var copy = p
                _ = copy.admit(record, generation)
                _ = copy.complete(record, generation)
            }
        }
    }
}
