import BelugaCore
import Foundation
import RemoteSessionCore
import XCTest
@testable import opensteamer

// Injection calls the actual Rust export before corrupting its copied result.
// Tests exercise the real native adapter and boundary, not a reference validator.
@MainActor
private final class InvitationOutputInjection {
    typealias Boundary = BelugaRustInvitationAcceptanceBoundary
    typealias State = Boundary.State
    typealias Event = Boundary.Event
    typealias Output = Boundary.Output
    typealias Mutation = @MainActor (State, Event, inout Output) -> Void

    var mutation: Mutation?
    var inputs: [(UInt32, State, Event)] = []
    var effectHasRun = false
    var callsAfterEffect = 0

    var provider: Boundary.CopiedResultProvider {
        { [self] abi, state, event in
            inputs.append((abi, state, event))
            if effectHasRun { callsAfterEffect += 1 }
            var output = beluga_core_invitation_acceptance_step(abi, state, event)
            mutation?(state, event, &output)
            return output
        }
    }

    func resetCalls() {
        inputs.removeAll()
        effectHasRun = false
        callsAfterEffect = 0
    }
}

@MainActor
private final class InvitationNativeEffects {
    final class Failure: Error {}
    let deliberatePartialEffect = Failure()
    var admissionWrites = 0
    var completionWrites = 0
    var records: [RemotePairedDeviceRecord] = []
    var labels: [String] = []
    var throwAdmission = false
    var throwCompletion = false
}

private struct InvitationBoundaryRecords {
    let pending: RemotePairedDeviceRecord
    let recoverable: RemotePairedDeviceRecord
    let active: RemotePairedDeviceRecord

    static func make() throws -> Self {
        let invitation = try RemoteInvitationCode.generate()
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let viewer = try RemoteDeviceIdentity.generate(role: .viewer)
        let hp = try RemotePairingParticipant(identity: host, invitation: invitation)
        let vp = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        let ha = try hp.accept(vp.hello)
        let va = try vp.accept(hp.hello)
        let pending = try va.makePendingRecord(peerConfirmation: ha.makeConfirmation())
        var hostRecord = try ha.makePendingRecord(peerConfirmation: va.makeConfirmation())
        let proposal = try hostRecord.prepareProposal(using: host)
        var recoverable = pending
        let ack = try recoverable.prepareAcknowledgement(after: proposal, using: viewer)
        try hostRecord.acceptAcknowledgement(ack)
        let completion = try hostRecord.prepareCompletion(using: host)
        var active = recoverable
        _ = try active.acceptCompletion(completion, using: viewer)
        return Self(pending: pending, recoverable: recoverable, active: active)
    }
}

@MainActor
final class BelugaRustInvitationAcceptanceTests: XCTestCase {
    private typealias Boundary = BelugaRustInvitationAcceptanceBoundary
    private typealias State = Boundary.State
    private typealias Event = Boundary.Event
    private typealias Output = Boundary.Output
    private typealias Mutation = InvitationOutputInjection.Mutation
    private let owner = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private let foreign = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

    private func words(_ state: State) -> [UInt32] { [state.abi_version, state.flags] }

    private func arm(_ action: inout InvitationAcceptanceAction,
                     effects: InvitationNativeEffects, generation: UUID,
                     admission: Bool = true, label: String = "owner",
                     duringEffect: (@MainActor () -> Void)? = nil) {
        let admissionBody: (@MainActor () throws -> Void)?
        if admission {
            admissionBody = {
                effects.admissionWrites += 1
                effects.labels.append(label + ".admission")
                duringEffect?()
                if effects.throwAdmission { throw effects.deliberatePartialEffect }
            }
        } else {
            admissionBody = nil
        }
        action.arm(generation: generation, onAdmitted: admissionBody) { record in
            effects.completionWrites += 1
            effects.records.append(record)
            effects.labels.append(label + ".completion")
            duringEffect?()
            if effects.throwCompletion { throw effects.deliberatePartialEffect }
        }
    }

    private func assertInvalidBridge(_ body: () throws -> Void,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard let bridge = error as? InvitationAcceptanceBridgeError else {
                return XCTFail("Expected the actual adapter's invalid copied-result error", file: file, line: line)
            }
            switch bridge {
            case .invalidBridge: break
            }
        }
    }

    private func assertPreserved(_ action: InvitationAcceptanceAction, before: [UInt32],
                                 marker: UUID?, effects: InvitationNativeEffects,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(words(action.copiedStateForTesting), before, file: file, line: line)
        XCTAssertEqual(action.nativeOwnerForTesting, marker, file: file, line: line)
        XCTAssertTrue(action.hasNativeCallbacksForTesting, file: file, line: line)
        XCTAssertTrue(action.bridgeFaultedForTesting, file: file, line: line)
        XCTAssertEqual(effects.admissionWrites, 0, file: file, line: line)
        XCTAssertEqual(effects.completionWrites, 0, file: file, line: line)
    }

    private func rejectAdmission(_ fixture: InvitationBoundaryRecords, record: RemotePairedDeviceRecord? = nil,
                                 mutation: @escaping Mutation,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let injection = InvitationOutputInjection()
        let effects = InvitationNativeEffects()
        var action = InvitationAcceptanceAction(copiedResultProvider: injection.provider)
        arm(&action, effects: effects, generation: owner)
        let before = words(action.copiedStateForTesting)
        let marker = action.nativeOwnerForTesting
        injection.resetCalls(); injection.mutation = mutation
        assertInvalidBridge({ try action.persistAdmissionAfterRecoverablePairing(record ?? fixture.recoverable, generation: owner) }, file: file, line: line)
        XCTAssertEqual(injection.inputs.count, 1, file: file, line: line)
        assertPreserved(action, before: before, marker: marker, effects: effects, file: file, line: line)
        injection.mutation = nil
        try action.persistAdmissionAfterRecoverablePairing(fixture.recoverable, generation: owner)
        XCTAssertEqual(effects.admissionWrites, 1, file: file, line: line)
        XCTAssertTrue(try action.completeAuthenticatedPairing(fixture.active, generation: owner), file: file, line: line)
        XCTAssertEqual(effects.completionWrites, 1, file: file, line: line)
    }

    private func rejectCompletion(_ fixture: InvitationBoundaryRecords, record: RemotePairedDeviceRecord? = nil,
                                  mutation: @escaping Mutation,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let injection = InvitationOutputInjection()
        let effects = InvitationNativeEffects()
        var action = InvitationAcceptanceAction(copiedResultProvider: injection.provider)
        arm(&action, effects: effects, generation: owner)
        let before = words(action.copiedStateForTesting)
        let marker = action.nativeOwnerForTesting
        injection.resetCalls(); injection.mutation = mutation
        assertInvalidBridge({ _ = try action.completeAuthenticatedPairing(record ?? fixture.active, generation: owner) }, file: file, line: line)
        XCTAssertEqual(injection.inputs.count, 1, file: file, line: line)
        assertPreserved(action, before: before, marker: marker, effects: effects, file: file, line: line)
        injection.mutation = nil
        XCTAssertTrue(try action.completeAuthenticatedPairing(fixture.active, generation: owner), file: file, line: line)
        XCTAssertEqual(effects.completionWrites, 1, file: file, line: line)
        XCTAssertEqual(effects.records, [fixture.active], file: file, line: line)
    }

    func testBoundaryRejectsForgedCallbackPermissionForForeignUUID() throws {
        let f = try InvitationBoundaryRecords.make()
        let injection = InvitationOutputInjection()
        let effects = InvitationNativeEffects()
        var action = InvitationAcceptanceAction(copiedResultProvider: injection.provider)
        arm(&action, effects: effects, generation: owner)
        let before = action.copiedStateForTesting
        injection.resetCalls()
        injection.mutation = { state, event, output in
            output.status = 2; output.callback_kind = event.opcode == 1 ? 1 : 2
            output.prepared_flags = state.flags
            output.callback_success_state.flags = event.opcode == 1 ? 15 : 0
        }
        try action.persistAdmissionAfterRecoverablePairing(f.pending, generation: foreign)
        XCTAssertFalse(try action.completeAuthenticatedPairing(f.pending, generation: foreign))
        XCTAssertEqual(injection.inputs.count, 0, "The exact native UUID guard must precede the provider")
        XCTAssertEqual(effects.admissionWrites + effects.completionWrites, 0)
        XCTAssertEqual(words(action.copiedStateForTesting), words(before))
        var event = Event(); event.opcode = 1; event.generation_matches = 0; event.phase = 0
        var forged = beluga_core_invitation_acceptance_step(1, before, event)
        forged.status = 2; forged.callback_kind = 1; forged.prepared_flags = before.flags
        forged.callback_success_state.flags = 15
        XCTAssertFalse(Boundary.accepts(before: before, event: event, output: forged))
        injection.mutation = nil
        XCTAssertTrue(try action.completeAuthenticatedPairing(f.active, generation: owner))
    }

    func testBoundaryRejectsForgedAdmissionPermissionForWrongPhase() throws {
        let f = try InvitationBoundaryRecords.make()
        try rejectAdmission(f, record: f.pending) { before, _, output in
            output.status = 2; output.callback_kind = 1; output.prepared_flags = before.flags
            output.callback_success_state.flags = before.flags | 8
        }
    }

    func testBoundaryRejectsForgedCompletionPermissionForWrongPhase() throws {
        let f = try InvitationBoundaryRecords.make()
        try rejectCompletion(f, record: f.recoverable) { before, _, output in
            output.status = 2; output.callback_kind = 2; output.prepared_flags = before.flags
            output.callback_success_state.flags = 0
        }
    }

    func testBoundaryRejectsPreEffectAdmissionConsumption() throws {
        try rejectAdmission(InvitationBoundaryRecords.make()) { _, _, output in output.state.flags |= 8 }
    }

    func testBoundaryRejectsPreEffectCompletionRetirement() throws {
        try rejectCompletion(InvitationBoundaryRecords.make()) { _, _, output in output.state.flags = 0 }
    }

    func testBoundaryRejectsWrongStatusAndFabricatedCompletionBoolean() throws {
        let f = try InvitationBoundaryRecords.make()
        let mutations: [Mutation] = [
            { _, _, output in output.completion_succeeded = 1 },
            { _, _, output in output.status = 0 },
            { _, _, output in output.status = 1 },
            { _, _, output in output.status = 5 }
        ]
        for mutation in mutations { try rejectAdmission(f, mutation: mutation) }
        try rejectCompletion(f) { _, _, output in output.completion_succeeded = 1 }
    }

    func testBoundaryRejectsAdmissionPlanThatClearsCompletionAuthority() throws {
        let f = try InvitationBoundaryRecords.make()
        for flags in [UInt32(0), 3, 11, 7] {
            try rejectAdmission(f) { _, _, output in output.callback_success_state.flags = flags }
        }
    }

    func testBoundaryRejectsCompletionPlanThatLosesRetirement() throws {
        let f = try InvitationBoundaryRecords.make()
        for flags in [UInt32(5), 7, 13, 15] {
            try rejectCompletion(f) { _, _, output in output.callback_success_state.flags = flags }
        }
    }

    func testBoundaryRejectsCallbackKindAndPreparedFlagsSwaps() throws {
        let f = try InvitationBoundaryRecords.make()
        let mutations: [Mutation] = [
            { _, _, output in output.callback_kind = 2 },
            { before, _, output in output.prepared_flags = before.flags ^ 2 },
            { _, _, output in output.prepared_flags |= 32 },
            { _, _, output in output.callback_kind = UInt32.max }
        ]
        for mutation in mutations { try rejectAdmission(f, mutation: mutation) }
        try rejectCompletion(f) { _, _, output in output.callback_kind = 1 }
    }

    func testSameUUIDRearmRotatesOwnerAndOnlyReplacementClosuresCanRun() throws {
        let f = try InvitationBoundaryRecords.make()
        let injection = InvitationOutputInjection()
        let effects = InvitationNativeEffects()
        var action = InvitationAcceptanceAction(copiedResultProvider: injection.provider)
        arm(&action, effects: effects, generation: owner, label: "old")
        let oldMarker = action.nativeOwnerForTesting
        try action.persistAdmissionAfterRecoverablePairing(f.recoverable, generation: owner)
        arm(&action, effects: effects, generation: owner, label: "new")
        XCTAssertNotNil(oldMarker)
        XCTAssertNotEqual(action.nativeOwnerForTesting, oldMarker)
        XCTAssertEqual(action.copiedStateForTesting.flags, 7)
        try action.persistAdmissionAfterRecoverablePairing(f.recoverable, generation: owner)
        XCTAssertTrue(try action.completeAuthenticatedPairing(f.active, generation: owner))
        XCTAssertEqual(effects.labels, ["old.admission", "new.admission", "new.completion"])
        XCTAssertEqual(action.nativeOwnerForTesting, nil)
    }

    func testDifferentGenerationAndCancelledCallsCannotUseRetiredNativeOwner() throws {
        let f = try InvitationBoundaryRecords.make()
        let injection = InvitationOutputInjection()
        let effects = InvitationNativeEffects()
        var action = InvitationAcceptanceAction(copiedResultProvider: injection.provider)
        arm(&action, effects: effects, generation: owner, label: "old")
        arm(&action, effects: effects, generation: foreign, label: "replacement")
        injection.resetCalls()
        XCTAssertFalse(try action.completeAuthenticatedPairing(f.active, generation: owner))
        action.cancel(generation: owner)
        XCTAssertEqual(injection.inputs.count, 0)
        XCTAssertTrue(action.hasNativeCallbacksForTesting)
        action.cancel(generation: foreign)
        let cancelledProviderCalls = injection.inputs.count
        try action.persistAdmissionAfterRecoverablePairing(f.pending, generation: foreign)
        XCTAssertFalse(try action.completeAuthenticatedPairing(f.active, generation: foreign))
        XCTAssertEqual(injection.inputs.count, cancelledProviderCalls)
        XCTAssertEqual(effects.labels, [])
        XCTAssertEqual(words(action.copiedStateForTesting), [1, 0])
    }

    func testPartialEffectCallbackFailurePropagatesAndExactRetryRemainsPossible() throws {
        let f = try InvitationBoundaryRecords.make()
        let injection = InvitationOutputInjection()
        let effects = InvitationNativeEffects()
        var action = InvitationAcceptanceAction(copiedResultProvider: injection.provider)
        arm(&action, effects: effects, generation: owner)
        let marker = action.nativeOwnerForTesting
        effects.throwAdmission = true
        XCTAssertThrowsError(try action.persistAdmissionAfterRecoverablePairing(f.recoverable, generation: owner)) {
            XCTAssertTrue(($0 as? InvitationNativeEffects.Failure) === effects.deliberatePartialEffect)
        }
        XCTAssertEqual(effects.admissionWrites, 1)
        XCTAssertEqual(action.copiedStateForTesting.flags, 7)
        XCTAssertEqual(action.nativeOwnerForTesting, marker)
        effects.throwAdmission = false
        try action.persistAdmissionAfterRecoverablePairing(f.recoverable, generation: owner)
        XCTAssertEqual(effects.admissionWrites, 2)
        XCTAssertEqual(action.copiedStateForTesting.flags, 15)
        effects.throwCompletion = true
        XCTAssertThrowsError(try action.completeAuthenticatedPairing(f.active, generation: owner)) {
            XCTAssertTrue(($0 as? InvitationNativeEffects.Failure) === effects.deliberatePartialEffect)
        }
        XCTAssertEqual(effects.completionWrites, 1)
        XCTAssertEqual(action.copiedStateForTesting.flags, 15)
        XCTAssertEqual(action.nativeOwnerForTesting, marker)
        effects.throwCompletion = false
        XCTAssertTrue(try action.completeAuthenticatedPairing(f.active, generation: owner))
        XCTAssertEqual(effects.completionWrites, 2)
        XCTAssertEqual(effects.records, [f.active, f.active])
        XCTAssertFalse(try action.completeAuthenticatedPairing(f.active, generation: owner))
    }

    func testPrevalidatedCandidateCommitsFromActualSuccessWithNoPostEffectFFIOrReplay() throws {
        let f = try InvitationBoundaryRecords.make()
        let injection = InvitationOutputInjection()
        let effects = InvitationNativeEffects()
        var action = InvitationAcceptanceAction(copiedResultProvider: injection.provider)
        arm(&action, effects: effects, generation: owner, duringEffect: {
            injection.effectHasRun = true
            injection.mutation = { _, _, output in output.status = UInt32.max }
        })
        injection.resetCalls()
        try action.persistAdmissionAfterRecoverablePairing(f.recoverable, generation: owner)
        XCTAssertEqual(injection.inputs.count, 1)
        XCTAssertEqual(injection.callsAfterEffect, 0)
        XCTAssertEqual(effects.admissionWrites, 1)
        XCTAssertEqual(action.copiedStateForTesting.flags, 15)
        injection.mutation = nil; injection.resetCalls()
        XCTAssertTrue(try action.completeAuthenticatedPairing(f.active, generation: owner))
        XCTAssertEqual(injection.inputs.count, 1)
        XCTAssertEqual(injection.callsAfterEffect, 0)
        XCTAssertEqual(effects.completionWrites, 1)
        XCTAssertEqual(words(action.copiedStateForTesting), [1, 0])
        XCTAssertFalse(try action.completeAuthenticatedPairing(f.active, generation: owner))
        XCTAssertEqual(injection.inputs.count, 1)
    }

    func testBoundaryCannotLoseExactCancelRetirementOnMalformedOutput() throws {
        let f = try InvitationBoundaryRecords.make()
        let injection = InvitationOutputInjection()
        let effects = InvitationNativeEffects()
        var action = InvitationAcceptanceAction(copiedResultProvider: injection.provider)
        arm(&action, effects: effects, generation: owner)
        injection.resetCalls()
        injection.mutation = { before, _, output in
            output.state = before; output.callback_success_state = before; output.status = 1
        }
        action.cancel(generation: owner)
        XCTAssertEqual(injection.inputs.count, 1)
        XCTAssertEqual(words(action.copiedStateForTesting), [1, 0])
        XCTAssertNil(action.nativeOwnerForTesting)
        XCTAssertFalse(action.hasNativeCallbacksForTesting)
        XCTAssertTrue(action.bridgeFaultedForTesting)
        try action.persistAdmissionAfterRecoverablePairing(f.pending, generation: owner)
        XCTAssertFalse(try action.completeAuthenticatedPairing(f.active, generation: owner))
        XCTAssertEqual(injection.inputs.count, 1)
        XCTAssertEqual(effects.admissionWrites + effects.completionWrites, 0)
    }

    func testBoundaryRejectsMalformedVersionsStatusesBooleansAndImpossibleStates() throws {
        let f = try InvitationBoundaryRecords.make()
        let mutations: [Mutation] = [
            { _, _, output in output.state.abi_version = 2 },
            { _, _, output in output.callback_success_state.abi_version = 2 },
            { _, _, output in output.state.flags = 2 },
            { _, _, output in output.callback_success_state.flags = 8 },
            { _, _, output in output.status = UInt32.max },
            { _, _, output in output.completion_succeeded = 2 }
        ]
        for mutation in mutations { try rejectAdmission(f, mutation: mutation) }
        for initial in [State(abi_version: 2, flags: 0), State(abi_version: 1, flags: 7),
                        State(abi_version: 1, flags: 8)] {
            let untouchedProvider = InvitationOutputInjection()
            var empty = InvitationAcceptanceAction(copiedResultProvider: untouchedProvider.provider,
                                                    initialStateForTesting: initial)
            XCTAssertEqual(words(empty.copiedStateForTesting), [1, 0])
            XCTAssertNil(empty.nativeOwnerForTesting)
            XCTAssertFalse(empty.hasNativeCallbacksForTesting)
            XCTAssertTrue(empty.bridgeFaultedForTesting)
            XCTAssertFalse(try empty.completeAuthenticatedPairing(f.active, generation: owner))
            XCTAssertEqual(untouchedProvider.inputs.count, 0)
        }
        let injection = InvitationOutputInjection()
        let effects = InvitationNativeEffects()
        var action = InvitationAcceptanceAction(copiedResultProvider: injection.provider)
        arm(&action, effects: effects, generation: owner, label: "old")
        injection.mutation = { _, _, output in output.state.flags = 13 }
        arm(&action, effects: effects, generation: owner, label: "malformed-new")
        XCTAssertEqual(words(action.copiedStateForTesting), [1, 0])
        XCTAssertNil(action.nativeOwnerForTesting)
        XCTAssertFalse(action.hasNativeCallbacksForTesting)
        XCTAssertTrue(action.bridgeFaultedForTesting)
        injection.mutation = nil
        XCTAssertFalse(try action.completeAuthenticatedPairing(f.active, generation: owner))
        XCTAssertEqual(effects.labels, [])
    }

    func testControlsAcceptEveryLegitimateStateGuardAndIndependentValueCopy() throws {
        let f = try InvitationBoundaryRecords.make()
        for admission in [false, true] {
            for consume in [false, true] {
                let injection = InvitationOutputInjection()
                let effects = InvitationNativeEffects()
                injection.mutation = { before, event, output in
                    XCTAssertTrue(Boundary.accepts(before: before, event: event, output: output))
                }
                var action = InvitationAcceptanceAction(copiedResultProvider: injection.provider)
                XCTAssertEqual(action.copiedStateForTesting.flags, 0)
                arm(&action, effects: effects, generation: owner, admission: admission)
                XCTAssertEqual(action.copiedStateForTesting.flags, admission ? 7 : 5)
                injection.resetCalls()
                try action.persistAdmissionAfterRecoverablePairing(f.pending, generation: foreign)
                XCTAssertFalse(try action.completeAuthenticatedPairing(f.pending, generation: foreign))
                XCTAssertEqual(injection.inputs.count, 0)
                XCTAssertThrowsError(try action.persistAdmissionAfterRecoverablePairing(f.pending, generation: owner)) {
                    XCTAssertEqual($0 as? InvitationAcceptanceError, .pairingIsNotRecoverable)
                }
                XCTAssertThrowsError(try action.completeAuthenticatedPairing(f.recoverable, generation: owner)) {
                    XCTAssertEqual($0 as? InvitationAcceptanceError, .pairingIsNotActive)
                }
                XCTAssertEqual(action.copiedStateForTesting.flags, admission ? 7 : 5)
                XCTAssertEqual(effects.admissionWrites + effects.completionWrites, 0)
                if consume {
                    try action.persistAdmissionAfterRecoverablePairing(f.recoverable, generation: owner)
                    XCTAssertEqual(action.copiedStateForTesting.flags, admission ? 15 : 13)
                    let calls = injection.inputs.count
                    try action.persistAdmissionAfterRecoverablePairing(f.pending, generation: owner)
                    XCTAssertEqual(injection.inputs.count, calls)
                }
                var copy = action
                let copiedOwner = action.nativeOwnerForTesting
                XCTAssertEqual(copy.nativeOwnerForTesting, copiedOwner)
                XCTAssertTrue(try action.completeAuthenticatedPairing(f.active, generation: owner))
                XCTAssertNil(action.nativeOwnerForTesting)
                XCTAssertEqual(copy.nativeOwnerForTesting, copiedOwner)
                XCTAssertTrue(copy.hasNativeCallbacksForTesting)
                XCTAssertTrue(try copy.completeAuthenticatedPairing(f.active, generation: owner))
                XCTAssertNil(copy.nativeOwnerForTesting)
                XCTAssertEqual(effects.completionWrites, 2)
                XCTAssertEqual(effects.admissionWrites, admission && consume ? 1 : 0)
                XCTAssertFalse(try action.completeAuthenticatedPairing(f.pending, generation: owner))
                XCTAssertFalse(try copy.completeAuthenticatedPairing(f.pending, generation: owner))
            }
        }
    }
}
