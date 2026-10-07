import BelugaCore
import Foundation
import Testing
import os
@testable import RemoteSessionCore

/// PRIVATE, UNCOMPILED candidate. Every positive producer call uses the real
/// C exports; corrupted results are injected into the actual native guard.
struct BelugaRustSignalingReplayTests {
    private typealias Boundary = BelugaRustSignalingReplayBoundary
    private typealias State = Boundary.State
    private typealias Output = Boundary.Output

    @Test func actualCopiedABILayoutAndInitialAreExact() {
        #expect(MemoryLayout<State>.size == 24)
        #expect(MemoryLayout<State>.alignment == 8)
        #expect(MemoryLayout<State>.offset(of: \.abi_version) == 0)
        #expect(MemoryLayout<State>.offset(of: \.has_highest) == 4)
        #expect(MemoryLayout<State>.offset(of: \.highest) == 8)
        #expect(MemoryLayout<State>.offset(of: \.bitmap) == 16)
        #expect(MemoryLayout<Output>.size == 32)
        #expect(MemoryLayout<Output>.alignment == 8)
        #expect(MemoryLayout<Output>.offset(of: \.decision) == 24)
        #expect(MemoryLayout<Output>.offset(of: \.reserved) == 28)
        #expect(Boundary.acceptsInitial(beluga_core_signaling_replay_initial()))
        #expect(SignalingReplayGuard.windowSize == 64)
    }

    @Test func actualNativeGuardMatchesIndependentOriginalBoundedTraces() {
        let alphabet: [UInt64] = [0, 1, 2, 63, 64, 65, 127, .max - 63, .max]
        func visit(_ path: [UInt64], depth: Int) {
            var actual = SignalingReplayGuard()
            var reference = FrozenOriginalReplayGuard()
            for sequence in path {
                let expected = reference.accept(sequence)
                #expect(outcome(&actual, sequence) == expected)
                #expect(!actual.bridgeFaultedForTesting)
                let stored = actual.copiedStateForTesting
                #expect(stored.has_highest == (reference.highest == nil ? 0 : 1))
                #expect(stored.highest == (reference.highest ?? 0))
                #expect(stored.bitmap == reference.bits)
            }
            if depth > 0 {
                for sequence in alphabet { visit(path + [sequence], depth: depth - 1) }
            }
        }
        visit([], depth: 4)
    }

    @Test func zeroMaximumAnd63Versus64BoundariesUseActualExports() throws {
        var zero = SignalingReplayGuard()
        try zero.accept(sequence: 0)
        #expect(outcome(&zero, 0) == .duplicate)
        #expect(zero.copiedStateForTesting.has_highest == 1)
        #expect(zero.copiedStateForTesting.highest == 0)
        #expect(zero.copiedStateForTesting.bitmap == 1)

        var maximum = SignalingReplayGuard()
        try maximum.accept(sequence: .max)
        try maximum.accept(sequence: .max - 63)
        #expect(outcome(&maximum, .max - 63) == .duplicate)
        #expect(outcome(&maximum, .max - 64) == .outside)
        #expect(maximum.copiedStateForTesting.bitmap == ((UInt64(1) << 63) | 1))

        var advance63 = SignalingReplayGuard()
        try advance63.accept(sequence: 0)
        try advance63.accept(sequence: 63)
        #expect(advance63.copiedStateForTesting.bitmap == ((UInt64(1) << 63) | 1))
        var advance64 = SignalingReplayGuard()
        try advance64.accept(sequence: 0)
        try advance64.accept(sequence: 64)
        #expect(advance64.copiedStateForTesting.bitmap == 1)
        #expect(outcome(&advance64, 0) == .outside)
    }

    @Test func duplicateAndOutsideRejectionsPreserveEveryStoredFieldWithoutFaulting() throws {
        var guardState = SignalingReplayGuard()
        try guardState.accept(sequence: 100)
        try guardState.accept(sequence: 98)
        let before = guardState.copiedStateForTesting
        #expect(outcome(&guardState, 98) == .duplicate)
        #expect(Boundary.same(before, guardState.copiedStateForTesting))
        #expect(outcome(&guardState, 36) == .outside)
        #expect(Boundary.same(before, guardState.copiedStateForTesting))
        #expect(!guardState.bridgeFaultedForTesting)
        try guardState.accept(sequence: 97)
    }

    @Test func sendableCopiesHaveIndependentStoredWindowsAndFaultLifetimes() throws {
        func requiresSendable<T: Sendable>(_ value: T) { _ = value }
        var original = makeGuard { before, sequence, output in
            var value = output
            if sequence == 12 { value.state.bitmap = 1 }
            _ = before
            return value
        }
        try original.accept(sequence: 10)
        requiresSendable(original)
        var first = original
        var second = original
        try first.accept(sequence: 9)
        try second.accept(sequence: 9)
        #expect(outcome(&first, 9) == .duplicate)
        #expect(outcome(&second, 12) == .bridgeFault)
        #expect(second.bridgeFaultedForTesting)
        #expect(!first.bridgeFaultedForTesting)
        #expect(!original.bridgeFaultedForTesting)
        try first.accept(sequence: 11)
        try original.accept(sequence: 9)
    }

    @Test func malformedInitialCannotCallStepOrManufactureEmptyRecovery() {
        for variant in 0..<5 {
            var bad = beluga_core_signaling_replay_initial()
            switch variant {
            case 0: bad.abi_version = 2
            case 1: bad.has_highest = 2
            case 2: bad.highest = 1
            case 3: bad.bitmap = 1
            default: bad.has_highest = 1; bad.bitmap = 1
            }
            let captured = bad
            let calls = OSAllocatedUnfairLock(initialState: 0)
            let observations = OSAllocatedUnfairLock(initialState: [BelugaRustSignalingReplayObservation]())
            var guardState = SignalingReplayGuard(producer: .init(
                initial: { captured },
                step: { abi, state, sequence in
                    calls.withLock { $0 += 1 }
                    return beluga_core_signaling_replay_step(abi, state, sequence)
                }
            ), observer: { event in observations.withLock { $0.append(event) } })
            #expect(guardState.bridgeFaultedForTesting)
            #expect(outcome(&guardState, 0) == .bridgeFault)
            #expect(outcome(&guardState, .max) == .bridgeFault)
            #expect(calls.withLock { $0 } == 0)
            #expect(Boundary.same(captured, guardState.copiedStateForTesting))
            let events = observations.withLock { $0 }
            #expect(events.count == 3)
            #expect(events.allSatisfy { $0.kind == .faulted && $0.error == .invalidSignalingReplayBridge
                && Boundary.same(captured, $0.stored) })
        }
    }

    @Test func unknownDecisionAndReservedOutputCannotCommit() {
        for corruptCode in [UInt32(3), .max] {
            assertFaultPreservesBefore(makeGuard { _, _, output in
                var value = output; value.decision = corruptCode; return value
            }, sequence: 10)
        }
        assertFaultPreservesBefore(makeGuard { _, _, output in
            var value = output; value.reserved = 1; return value
        }, sequence: 10)
    }

    @Test func canonicalLookingAcceptedDuplicateIsRejectedByActualAdapter() throws {
        var guardState = makeGuard { _, sequence, output in
            var value = output
            if sequence == 8 && value.decision == 1 { value.decision = 0 }
            return value
        }
        try guardState.accept(sequence: 10)
        try guardState.accept(sequence: 8)
        assertFaultPreservesBefore(guardState, sequence: 8)
    }

    @Test func shortAdvanceCannotErasePreviouslyAcceptedHistory() throws {
        var guardState = makeGuard { _, sequence, output in
            var value = output
            if sequence == 11 { value.state.bitmap = 1 }
            return value
        }
        try guardState.accept(sequence: 10)
        try guardState.accept(sequence: 8)
        assertFaultPreservesBefore(guardState, sequence: 11)
    }

    @Test func validOutputForAnotherSequenceCannotCommit() {
        assertFaultPreservesBefore(makeGuard { before, sequence, _ in
            beluga_core_signaling_replay_step(1, before, sequence + 1)
        }, sequence: 10)
    }

    @Test func validOutputForAnotherHistoryCannotCommit() throws {
        var guardState = makeGuard { _, sequence, output in
            guard sequence == 11 else { return output }
            let foreign = beluga_core_signaling_replay_step(1, beluga_core_signaling_replay_initial(), 10).state
            return beluga_core_signaling_replay_step(1, foreign, sequence)
        }
        try guardState.accept(sequence: 10)
        try guardState.accept(sequence: 8)
        assertFaultPreservesBefore(guardState, sequence: 11)
    }

    @Test func unexpectedInitialOrPopulatedPresenceCannotCommit() {
        for presence in [UInt32(0), 2, .max] {
            assertFaultPreservesBefore(makeGuard { _, _, output in
                var value = output; value.state.has_highest = presence; return value
            }, sequence: 10)
        }
    }

    @Test func wrongABIMissingCurrentBitOrNegativeHistoryCannotCommit() {
        for mutation in 0..<4 {
            assertFaultPreservesBefore(makeGuard { _, _, output in
                var value = output
                switch mutation {
                case 0: value.state.abi_version = 2
                case 1: value.state.bitmap = 0
                case 2: value.state.bitmap = 2
                default: value.state.bitmap |= UInt64(1) << 63
                }
                return value
            }, sequence: 10)
        }
    }

    @Test func rejectionCannotMutateAnyStoredHistoryField() throws {
        for rejectedSequence in [UInt64(100), 36] {
            var guardState = makeGuard { before, sequence, output in
                guard sequence == rejectedSequence && output.decision != 0 else { return output }
                var value = output
                value.state = beluga_core_signaling_replay_step(1, before, 101).state
                return value
            }
            try guardState.accept(sequence: 100)
            assertFaultPreservesBefore(guardState, sequence: rejectedSequence)
        }
    }

    @Test func falseDuplicateForUnseenSequenceCannotPreserveThenRejectAsReplay() {
        assertFaultPreservesBefore(makeGuard { before, _, output in
            var value = output; value.decision = 1; value.state = before; return value
        }, sequence: 0)
    }

    @Test func falseOutsideForInWindowUnseenSequenceCannotCommit() throws {
        var guardState = makeGuard { before, sequence, output in
            guard sequence == 9 else { return output }
            var value = output; value.decision = 2; value.state = before; return value
        }
        try guardState.accept(sequence: 10)
        assertFaultPreservesBefore(guardState, sequence: 9)
    }

    @Test func contradictoryHighestOrReorderedExtraBitCannotCommit() throws {
        for mutation in 0..<2 {
            var guardState = makeGuard { _, sequence, output in
                guard sequence == 9 else { return output }
                var value = output
                if mutation == 0 { value.state.highest = 11 }
                else { value.state.bitmap |= UInt64(1) << 2 }
                return value
            }
            try guardState.accept(sequence: 10)
            assertFaultPreservesBefore(guardState, sequence: 9)
        }
    }

    @Test func stickyBridgeFaultStopsAllProducerCallsWithoutRetryOrReset() {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        var guardState = SignalingReplayGuard(producer: .init(
            initial: { beluga_core_signaling_replay_initial() },
            step: { abi, state, sequence in
                calls.withLock { $0 += 1 }
                var value = beluga_core_signaling_replay_step(abi, state, sequence)
                value.reserved = 1
                return value
            }
        ))
        let before = guardState.copiedStateForTesting
        #expect(outcome(&guardState, 0) == .bridgeFault)
        #expect(outcome(&guardState, 1) == .bridgeFault)
        #expect(outcome(&guardState, .max) == .bridgeFault)
        #expect(calls.withLock { $0 } == 1)
        #expect(Boundary.same(before, guardState.copiedStateForTesting))
    }

    @Test func observerReportsOnlyActualStoredStateAfterCommitOrRefusal() throws {
        let observed = OSAllocatedUnfairLock(initialState: [BelugaRustSignalingReplayObservation]())
        var guardState = SignalingReplayGuard(producer: .actual,
            observer: { event in observed.withLock { $0.append(event) } })
        try guardState.accept(sequence: 10)
        try guardState.accept(sequence: 8)
        #expect(outcome(&guardState, 8) == .duplicate)
        let events = observed.withLock { $0 }
        #expect(events.count == 4)
        guard events.count == 4 else { return }
        #expect(events[0].kind == .initialized)
        #expect(events[0].stored.has_highest == 0)
        #expect(events[1].kind == .accepted && events[1].stored.highest == 10 && events[1].stored.bitmap == 1)
        #expect(events[2].kind == .accepted && events[2].stored.bitmap == 5)
        #expect(events[3].kind == .rejected && events[3].error == .replayedSequence)
        #expect(Boundary.same(events[2].stored, events[3].stored))
        #expect(Boundary.same(events[3].stored, guardState.copiedStateForTesting))
    }

    private func makeGuard(
        _ mutate: @escaping @Sendable (State, UInt64, Output) -> Output
    ) -> SignalingReplayGuard {
        SignalingReplayGuard(producer: .init(
            initial: { beluga_core_signaling_replay_initial() },
            step: { abi, before, sequence in
                mutate(before, sequence, beluga_core_signaling_replay_step(abi, before, sequence))
            }
        ))
    }

    private func assertFaultPreservesBefore(_ initial: SignalingReplayGuard, sequence: UInt64) {
        var guardState = initial
        let before = guardState.copiedStateForTesting
        #expect(outcome(&guardState, sequence) == .bridgeFault)
        #expect(guardState.bridgeFaultedForTesting)
        #expect(Boundary.same(before, guardState.copiedStateForTesting))
    }

    private func outcome(_ value: inout SignalingReplayGuard, _ sequence: UInt64) -> ReplayOutcome {
        do { try value.accept(sequence: sequence); return .accepted }
        catch let error as RemoteSessionCoreError {
            switch error {
            case .replayedSequence: return .duplicate
            case .sequenceOutsideReplayWindow: return .outside
            case .invalidSignalingReplayBridge: return .bridgeFault
            default: Issue.record("An unrelated replay error was returned"); return .unrelated
            }
        } catch { Issue.record("A non-core replay error was returned"); return .unrelated }
    }
}

private enum ReplayOutcome: Equatable { case accepted, duplicate, outside, bridgeFault, unrelated }

/// Independent frozen flat reference of the original 41-line Swift reducer.
/// This exists only in tests, never as a production transition fallback.
private struct FrozenOriginalReplayGuard {
    var highest: UInt64?
    var bits: UInt64 = 0

    mutating func accept(_ sequence: UInt64) -> ReplayOutcome {
        guard let highest else { self.highest = sequence; bits = 1; return .accepted }
        if sequence > highest {
            let difference = sequence - highest
            bits = difference >= 64 ? 1 : (bits << difference) | 1
            self.highest = sequence
            return .accepted
        }
        let age = highest - sequence
        if age >= 64 { return .outside }
        let mask = UInt64(1) << age
        if bits & mask != 0 { return .duplicate }
        bits |= mask
        return .accepted
    }
}
