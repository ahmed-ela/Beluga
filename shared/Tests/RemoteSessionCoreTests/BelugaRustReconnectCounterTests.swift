import BelugaCore
import CryptoKit
import Foundation
import Testing
@testable import RemoteSessionCore

/// Positive native calls use the actual C export;
/// corrupted copied outputs exercise the same production rejection boundary.
struct BelugaRustReconnectCounterTests {
    private typealias Boundary = BelugaRustReconnectCounterBoundary
    private typealias State = Boundary.State
    private typealias Event = Boundary.Event
    private typealias Output = Boundary.Output

    @Test func actualCopiedABIHasExactLayoutsAndNoInitialState() {
        #expect(MemoryLayout<State>.size == 24)
        #expect(MemoryLayout<State>.alignment == 8)
        #expect(MemoryLayout<State>.offset(of: \.abi_version) == 0)
        #expect(MemoryLayout<State>.offset(of: \.reserved) == 4)
        #expect(MemoryLayout<State>.offset(of: \.next_outbound) == 8)
        #expect(MemoryLayout<State>.offset(of: \.highest_accepted) == 16)
        #expect(MemoryLayout<Event>.size == 16)
        #expect(MemoryLayout<Event>.alignment == 8)
        #expect(MemoryLayout<Event>.offset(of: \.opcode) == 0)
        #expect(MemoryLayout<Event>.offset(of: \.reserved) == 4)
        #expect(MemoryLayout<Event>.offset(of: \.request_sequence) == 8)
        #expect(MemoryLayout<Output>.size == 32)
        #expect(MemoryLayout<Output>.alignment == 8)
        #expect(MemoryLayout<Output>.offset(of: \.candidate_state) == 0)
        #expect(MemoryLayout<Output>.offset(of: \.decision) == 24)
        #expect(MemoryLayout<Output>.offset(of: \.reserved) == 28)
        let original = Boundary.state(nextOutbound: 91, highestAccepted: 29)
        let output = beluga_core_reconnect_counters_step(
            1, original, Boundary.event(opcode: 0, requestSequence: 0)
        )
        #expect(output.candidate_state.next_outbound == 92)
        #expect(output.candidate_state.highest_accepted == 29)
    }

    @Test func actualExportMatchesIndependentNumericOracleForEntireBoundaryAlphabet() {
        let values: [UInt64] = [0, 1, 2, 62, 63, 64, 65, .max - 64, .max - 63, .max - 1, .max]
        for next in values {
            for highest in values {
                let before = Boundary.state(nextOutbound: next, highestAccepted: highest)
                for input in [Boundary.event(opcode: 0, requestSequence: 0)]
                    + values.map({ Boundary.event(opcode: 1, requestSequence: $0) }) {
                    let output = beluga_core_reconnect_counters_step(1, before, input)
                    let expected = frozenNumericReference(next: next, highest: highest, input: input)
                    #expect(output.decision == expected.decision)
                    #expect(output.candidate_state.next_outbound == expected.next)
                    #expect(output.candidate_state.highest_accepted == expected.highest)
                    #expect(output.candidate_state.abi_version == 1)
                    #expect(output.candidate_state.reserved == 0)
                    #expect(output.reserved == 0)
                    #expect(Boundary.accepts(before: before, event: input, output: output))
                }
            }
        }
    }

    @Test func invalidABIAndReservedInputsRemainUnchangedAtActualExport() {
        let good = Boundary.state(nextOutbound: 9, highestAccepted: 4)
        let goodEvent = Boundary.event(opcode: 0, requestSequence: 0)
        var badABI = good; badABI.abi_version = 2
        var badReserved = good; badReserved.reserved = 1
        var eventReserved = goodEvent; eventReserved.reserved = 1
        let cases: [(UInt32, State, Event)] = [
            (0, good, goodEvent), (2, good, goodEvent),
            (1, badABI, goodEvent), (1, badReserved, goodEvent),
            (1, good, eventReserved), (1, good, Boundary.event(opcode: 2, requestSequence: 0)),
            (1, good, Boundary.event(opcode: 0, requestSequence: 1))
        ]
        for (abi, before, input) in cases {
            let output = beluga_core_reconnect_counters_step(abi, before, input)
            #expect(output.decision == 3)
            #expect(output.reserved == 0)
            #expect(Boundary.same(output.candidate_state, before))
            #expect(!Boundary.accepts(before: before, event: input, output: output))
        }
    }

    @Test func actualOutboundZeroProposalDoesNotBypassNativeRequestValidation() throws {
        let pair = try makeActivePair()
        var record = pair.viewer
        record.nextOutboundReconnectSequence = 0
        let before = record
        let probe = Probe()
        #expect(throws: RemoteSessionCoreError.invalidReconnectMessage) {
            try begin(&record, identity: pair.viewerIdentity, producer: probe.actual)
        }
        #expect(probe.calls == 1)
        #expect(probe.last?.state.next_outbound == 0)
        #expect(record == before)
    }

    @Test func outboundMaximumMinusOneIssuesOnceAndThenExhaustsWithoutMutation() throws {
        let pair = try makeActivePair()
        var record = pair.viewer
        record.nextOutboundReconnectSequence = .max - 1
        record.highestAcceptedReconnectSequence = 63
        let request = try begin(&record, identity: pair.viewerIdentity).request
        #expect(request.sequence == UInt64.max - 1)
        #expect(record.nextOutboundReconnectSequence == .max)
        #expect(record.highestAcceptedReconnectSequence == 63)
        let before = record
        #expect(throws: RemoteSessionCoreError.sequenceExhausted) {
            try begin(&record, identity: pair.viewerIdentity)
        }
        #expect(record == before)
    }

    @Test func outboundMaximumRefusesBeforeInvalidConstructorInputs() throws {
        let pair = try makeActivePair()
        var record = pair.viewer
        record.nextOutboundReconnectSequence = .max
        let before = record
        let probe = Probe()
        #expect(throws: RemoteSessionCoreError.sequenceExhausted) {
            try begin(&record, identity: pair.viewerIdentity,
                      key: Data(), nonce: Data(), producer: probe.actual)
        }
        #expect(probe.calls == 1)
        #expect(record == before)
    }

    @Test func inboundMaximumIsAcceptedOnceThenStaleWithoutMutation() throws {
        let pair = try makeActivePair()
        let request = try signedRequest(record: pair.viewer, identity: pair.viewerIdentity, sequence: .max)
        var record = pair.host
        record.nextOutboundReconnectSequence = 64
        let response = try respond(&record, to: request, identity: pair.hostIdentity).response
        #expect(response.requestSequence == .max)
        #expect(record.highestAcceptedReconnectSequence == .max)
        #expect(record.nextOutboundReconnectSequence == 64)
        let before = record
        #expect(throws: RemoteSessionCoreError.staleReconnectSequence) {
            try respond(&record, to: request, identity: pair.hostIdentity)
        }
        #expect(record == before)
    }

    @Test func inboundStrictlyNewerSequencesPreserveOutboundCounter() throws {
        let pair = try makeActivePair()
        var record = pair.host
        record.nextOutboundReconnectSequence = .max
        let sequences: [UInt64] = [1, 63, 64, .max - 1, .max]
        for sequence in sequences {
            let request = try signedRequest(record: pair.viewer, identity: pair.viewerIdentity, sequence: sequence)
            _ = try respond(&record, to: request, identity: pair.hostIdentity)
            #expect(record.highestAcceptedReconnectSequence == sequence)
            #expect(record.nextOutboundReconnectSequence == .max)
            let before = record
            #expect(throws: RemoteSessionCoreError.staleReconnectSequence) {
                try respond(&record, to: request, identity: pair.hostIdentity)
            }
            #expect(record == before)
        }
    }

    @Test func outboundActiveGuardPrecedesIdentityExhaustionAndProducer() throws {
        let pair = try makeActivePair()
        var record = pair.viewer
        record.pairingState = .acceptedIssued
        record.nextOutboundReconnectSequence = .max
        let before = record
        let probe = Probe()
        #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
            try begin(&record, identity: pair.hostIdentity, key: Data(), nonce: Data(), producer: probe.actual)
        }
        #expect(probe.calls == 0)
        #expect(record == before)
    }

    @Test func outboundIdentityGuardPrecedesExhaustionAndProducer() throws {
        let pair = try makeActivePair()
        var record = pair.viewer
        record.nextOutboundReconnectSequence = .max
        let before = record
        let probe = Probe()
        #expect(throws: RemoteSessionCoreError.deviceIdentityMismatch) {
            try begin(&record, identity: pair.hostIdentity, key: Data(), nonce: Data(), producer: probe.actual)
        }
        #expect(probe.calls == 0)
        #expect(record == before)
    }

    @Test func inboundActiveAndIdentityGuardsPrecedeAuthenticationAndProducer() throws {
        let pair = try makeActivePair()
        let request = try tamperedSignature(signedRequest(record: pair.viewer, identity: pair.viewerIdentity, sequence: 1))
        for active in [false, true] {
            var record = pair.host
            if !active { record.pairingState = .acceptedReceived }
            let before = record
            let probe = Probe()
            let expected: RemoteSessionCoreError = active ? .deviceIdentityMismatch : .invalidPairingCommit
            #expect(throws: expected) {
                try respond(&record, to: request, identity: pair.viewerIdentity,
                            key: Data(), nonce: Data(), producer: probe.actual)
            }
            #expect(probe.calls == 0)
            #expect(record == before)
        }
    }

    @Test func inboundProtocolAndStructureGuardsPrecedeProducer() throws {
        let pair = try makeActivePair()
        let request = try signedRequest(record: pair.viewer, identity: pair.viewerIdentity, sequence: 1)
        let variants: [(RemoteReconnectRequest, RemoteSessionCoreError)] = [
            (replacing(request, protocolVersion: 0), .unsupportedReconnectVersion),
            (replacing(request, sequence: 0), .invalidReconnectMessage),
            (replacing(request, publicKey: Data()), .invalidReconnectMessage),
            (replacing(request, nonce: Data()), .invalidReconnectMessage),
            (replacing(request, signature: Data()), .invalidReconnectMessage)
        ]
        for (invalid, expected) in variants {
            var record = pair.host
            let before = record
            let probe = Probe()
            #expect(throws: expected) {
                try respond(&record, to: invalid, identity: pair.hostIdentity, producer: probe.actual)
            }
            #expect(probe.calls == 0)
            #expect(record == before)
        }
    }

    @Test func tamperedStaleAuthenticationPrecedesNumericAdmission() throws {
        let pair = try makeActivePair()
        let request = try signedRequest(record: pair.viewer, identity: pair.viewerIdentity, sequence: 63)
        var record = pair.host
        record.highestAcceptedReconnectSequence = 64
        let before = record
        let probe = Probe()
        let tampered = try tamperedSignature(request)
        #expect(throws: RemoteSessionCoreError.authenticationFailed) {
            try respond(&record, to: tampered, identity: pair.hostIdentity,
                        key: Data(), nonce: Data(), producer: probe.actual)
        }
        #expect(probe.calls == 0)
        #expect(record == before)
    }

    @Test func authenticatedStaleRefusesBeforeInvalidConstructorInputs() throws {
        let pair = try makeActivePair()
        let request = try signedRequest(record: pair.viewer, identity: pair.viewerIdentity, sequence: 64)
        var record = pair.host
        record.highestAcceptedReconnectSequence = 64
        let before = record
        let probe = Probe()
        #expect(throws: RemoteSessionCoreError.staleReconnectSequence) {
            try respond(&record, to: request, identity: pair.hostIdentity,
                        key: Data(), nonce: Data(), producer: probe.actual)
        }
        #expect(probe.calls == 1)
        #expect(record == before)
    }

    @Test func outboundConstructorFailuresPreserveEntireOriginalRecord() throws {
        let pair = try makeActivePair()
        let cases = [(Data(), bytes(0x61)), (Data(repeating: 0x51, count: 31), bytes(0x61)),
                     (Data(repeating: 0x51, count: 33), bytes(0x61)),
                     (bytes(0x51), Data()), (bytes(0x51), Data(repeating: 0x61, count: 31)),
                     (bytes(0x51), Data(repeating: 0x61, count: 33))]
        for (key, nonce) in cases {
            var record = pair.viewer
            record.nextOutboundReconnectSequence = 64
            record.highestAcceptedReconnectSequence = 63
            let before = record
            let probe = Probe()
            #expect(throws: RemoteSessionCoreError.invalidReconnectMessage) {
                try begin(&record, identity: pair.viewerIdentity, key: key, nonce: nonce, producer: probe.actual)
            }
            #expect(probe.calls == 1)
            #expect(record == before)
        }
    }

    @Test func inboundConstructorFailuresPreserveEntireOriginalRecord() throws {
        let pair = try makeActivePair()
        let request = try signedRequest(record: pair.viewer, identity: pair.viewerIdentity, sequence: 64)
        let cases = [(Data(), bytes(0x62)), (Data(repeating: 0x52, count: 31), bytes(0x62)),
                     (Data(repeating: 0x52, count: 33), bytes(0x62)),
                     (bytes(0x52), Data()), (bytes(0x52), Data(repeating: 0x62, count: 31)),
                     (bytes(0x52), Data(repeating: 0x62, count: 33))]
        for (key, nonce) in cases {
            var record = pair.host
            record.nextOutboundReconnectSequence = 63
            record.highestAcceptedReconnectSequence = 1
            let before = record
            let probe = Probe()
            #expect(throws: RemoteSessionCoreError.invalidReconnectMessage) {
                try respond(&record, to: request, identity: pair.hostIdentity,
                            key: key, nonce: nonce, producer: probe.actual)
            }
            #expect(probe.calls == 1)
            #expect(record == before)
        }
    }

    @Test func signedZeroAgreementKeyFailurePreservesEntireOriginalRecord() throws {
        let pair = try makeActivePair()
        let request = try signedRequest(record: pair.viewer, identity: pair.viewerIdentity,
                                        sequence: 64, publicKey: Data(repeating: 0, count: 32))
        var record = pair.host
        record.nextOutboundReconnectSequence = 63
        record.highestAcceptedReconnectSequence = 1
        let before = record
        let probe = Probe()
        #expect(throws: RemoteSessionCoreError.authenticationFailed) {
            try respond(&record, to: request, identity: pair.hostIdentity, producer: probe.actual)
        }
        #expect(probe.calls == 1)
        #expect(record == before)
    }

    @Test func nativeConstructorsUseOriginalSequenceAndUnmodifiedRecord() throws {
        let pair = try makeActivePair()
        var viewer = pair.viewer
        viewer.nextOutboundReconnectSequence = 64
        viewer.highestAcceptedReconnectSequence = 29
        let original = viewer
        let expected = try RemoteReconnectInitiator(record: original, identity: pair.viewerIdentity,
            sequence: 64, ephemeralPrivateKeyRawRepresentation: bytes(0x51), nonce: bytes(0x61))
        let initiator = try begin(&viewer, identity: pair.viewerIdentity)
        // CryptoKit randomizes Ed25519 signatures. Bind every unsigned field and
        // authenticate each separately signed transcript, not its signature bytes.
        #expect(try remoteCanonicalData(initiator.request.unsigned) == remoteCanonicalData(expected.request.unsigned))
        try expectValidSignature(initiator.request, identity: pair.viewerIdentity)
        try expectValidSignature(expected.request, identity: pair.viewerIdentity)
        var host = pair.host
        let expectedResponder = try RemoteReconnectResponder(record: host, identity: pair.hostIdentity,
            request: initiator.request, ephemeralPrivateKeyRawRepresentation: bytes(0x52), nonce: bytes(0x62))
        let responder = try respond(&host, to: initiator.request, identity: pair.hostIdentity)
        #expect(try remoteCanonicalData(responder.response.unsigned) == remoteCanonicalData(expectedResponder.response.unsigned))
        try expectValidSignature(responder.response, identity: pair.hostIdentity)
        try expectValidSignature(expectedResponder.response, identity: pair.hostIdentity)
        #expect(try initiator.complete(with: responder.response) == responder.credential)
        #expect(try initiator.complete(with: expectedResponder.response) == expectedResponder.credential)
        let referenceResponder = try RemoteReconnectResponder(record: pair.host, identity: pair.hostIdentity,
            request: expected.request, ephemeralPrivateKeyRawRepresentation: bytes(0x52), nonce: bytes(0x62))
        #expect(try expected.complete(with: referenceResponder.response) == referenceResponder.credential)
        #expect(viewer.nextOutboundReconnectSequence == 65)
        #expect(viewer.highestAcceptedReconnectSequence == 29)
        #expect(host.highestAcceptedReconnectSequence == 64)
    }

    @Test func genuineReconnectCompletesMatchingCredentialsAndSignals() throws {
        let pair = try makeActivePair()
        var viewer = pair.viewer
        var host = pair.host
        let initiator = try begin(&viewer, identity: pair.viewerIdentity)
        let responder = try respond(&host, to: initiator.request, identity: pair.hostIdentity)
        let credential = try initiator.complete(with: responder.response)
        #expect(credential == responder.credential)
        let outbound = RemoteSignalingCipher(credential: credential, role: .viewer)
        let inbound = RemoteSignalingCipher(credential: responder.credential, role: .host)
        let envelope = try outbound.seal(.control(.showScreen), sequence: 0)
        #expect(try inbound.open(envelope) == .control(.showScreen))
        #expect(viewer.nextOutboundReconnectSequence == 2)
        #expect(host.highestAcceptedReconnectSequence == 1)
    }

    @Test func copiedOutputValidationRejectsEveryFieldAndDecisionMismatch() {
        let before = Boundary.state(nextOutbound: 63, highestAccepted: 29)
        let input = Boundary.event(opcode: 0, requestSequence: 0)
        let good = beluga_core_reconnect_counters_step(1, before, input)
        #expect(Boundary.accepts(before: before, event: input, output: good))
        let mutations: [(inout Output) -> Void] = [
            { $0.candidate_state.abi_version = 0 }, { $0.candidate_state.abi_version = 2 },
            { $0.candidate_state.reserved = 1 }, { $0.reserved = 1 },
            { $0.decision = 1 }, { $0.decision = 2 }, { $0.decision = 3 }, { $0.decision = .max },
            { $0.candidate_state.next_outbound = 63 }, { $0.candidate_state.next_outbound = 65 },
            { $0.candidate_state.next_outbound = 0 }, { $0.candidate_state.highest_accepted = 30 }
        ]
        for mutate in mutations {
            var output = good; mutate(&output)
            #expect(!Boundary.accepts(before: before, event: input, output: output))
        }
        let inbound = Boundary.event(opcode: 1, requestSequence: 64)
        let accepted = beluga_core_reconnect_counters_step(1, before, inbound)
        let inboundMutations: [(inout Output) -> Void] = [
            { $0.candidate_state.abi_version = 0 }, { $0.candidate_state.reserved = 1 },
            { $0.reserved = 1 }, { $0.decision = 1 }, { $0.decision = 2 }, { $0.decision = 3 },
            { $0.candidate_state.next_outbound = 64 }, { $0.candidate_state.highest_accepted = 63 },
            { $0.candidate_state.highest_accepted = 65 }
        ]
        for mutate in inboundMutations {
            var output = accepted; mutate(&output)
            #expect(!Boundary.accepts(before: before, event: inbound, output: output))
        }
        var badBefore = before; badBefore.abi_version = 2
        #expect(!Boundary.accepts(before: badBefore, event: input, output: good))
        badBefore = before; badBefore.reserved = 1
        #expect(!Boundary.accepts(before: badBefore, event: input, output: good))
        var badEvent = input; badEvent.reserved = 1
        #expect(!Boundary.accepts(before: before, event: badEvent, output: good))
        badEvent = input; badEvent.opcode = 2
        #expect(!Boundary.accepts(before: before, event: badEvent, output: good))
        badEvent = input; badEvent.request_sequence = 1
        #expect(!Boundary.accepts(before: before, event: badEvent, output: good))
    }

    @Test func canonicalLookingProposalCannotAdmitExhaustedOrStaleRequests() throws {
        let exhausted = Boundary.state(nextOutbound: .max, highestAccepted: 63)
        let outbound = Boundary.event(opcode: 0, requestSequence: 0)
        var forged = beluga_core_reconnect_counters_step(1, exhausted, outbound)
        forged.decision = 0
        forged.candidate_state.next_outbound = 0
        #expect(!Boundary.accepts(before: exhausted, event: outbound, output: forged))
        let before = Boundary.state(nextOutbound: 1, highestAccepted: 64)
        let sequences: [UInt64] = [0, 1, 63, 64]
        for sequence in sequences {
            let input = Boundary.event(opcode: 1, requestSequence: sequence)
            var proposed = beluga_core_reconnect_counters_step(1, before, input)
            proposed.decision = 0
            proposed.candidate_state.highest_accepted = sequence
            #expect(!Boundary.accepts(before: before, event: input, output: proposed))
        }
        let pair = try makeActivePair()
        let dishonest = BelugaRustReconnectCounterProducer(step: { abi, state, input in
            var output = beluga_core_reconnect_counters_step(abi, state, input)
            output.decision = 0
            if input.opcode == 0 { output.candidate_state.next_outbound = state.next_outbound &+ 1 }
            else { output.candidate_state.highest_accepted = input.request_sequence }
            return output
        })
        var viewer = pair.viewer
        viewer.nextOutboundReconnectSequence = .max
        let originalViewer = viewer
        #expect(throws: RemoteSessionCoreError.invalidReconnectCounterBridge) {
            try begin(&viewer, identity: pair.viewerIdentity, producer: dishonest)
        }
        #expect(viewer == originalViewer)
        var host = pair.host
        host.highestAcceptedReconnectSequence = 64
        let originalHost = host
        let request = try signedRequest(record: pair.viewer, identity: pair.viewerIdentity, sequence: 63)
        #expect(throws: RemoteSessionCoreError.invalidReconnectCounterBridge) {
            try respond(&host, to: request, identity: pair.hostIdentity, producer: dishonest)
        }
        #expect(host == originalHost)
    }

    @Test func copiedRefusalCannotResetOrAdvanceEitherCounter() {
        let cases = [
            (Boundary.state(nextOutbound: .max, highestAccepted: 64), Boundary.event(opcode: 0, requestSequence: 0)),
            (Boundary.state(nextOutbound: 63, highestAccepted: 64), Boundary.event(opcode: 1, requestSequence: 63))
        ]
        for (before, input) in cases {
            let good = beluga_core_reconnect_counters_step(1, before, input)
            #expect(Boundary.accepts(before: before, event: input, output: good))
            let mutations: [(inout Output) -> Void] = [
                { $0.candidate_state.next_outbound = 0 },
                { $0.candidate_state.highest_accepted = 0 },
                { $0.candidate_state.next_outbound = 64 },
                { $0.candidate_state.highest_accepted = 65 },
                { $0.candidate_state.abi_version = 2 },
                { $0.candidate_state.reserved = 1 }, { $0.reserved = 1 }
            ]
            for mutate in mutations {
                var output = good; mutate(&output)
                #expect(!Boundary.accepts(before: before, event: input, output: output))
            }
        }
    }

    @Test func malformedProducerResultFailsBeforeConstructorAndPreservesRecord() throws {
        let pair = try makeActivePair()
        let producer = BelugaRustReconnectCounterProducer(step: { abi, before, input in
            var output = beluga_core_reconnect_counters_step(abi, before, input)
            output.reserved = 1
            return output
        })
        var viewer = pair.viewer
        let originalViewer = viewer
        #expect(throws: RemoteSessionCoreError.invalidReconnectCounterBridge) {
            try begin(&viewer, identity: pair.viewerIdentity, key: Data(), nonce: Data(), producer: producer)
        }
        #expect(viewer == originalViewer)
        let request = try signedRequest(record: pair.viewer, identity: pair.viewerIdentity, sequence: 1)
        var host = pair.host
        let originalHost = host
        #expect(throws: RemoteSessionCoreError.invalidReconnectCounterBridge) {
            try respond(&host, to: request, identity: pair.hostIdentity,
                        key: Data(), nonce: Data(), producer: producer)
        }
        #expect(host == originalHost)
    }

    @Test func copiedOutputCannotCommitOtherSlotOrUncorrelatedSequence() throws {
        let pair = try makeActivePair()
        let wrongOtherSlot = BelugaRustReconnectCounterProducer(step: { abi, before, input in
            var output = beluga_core_reconnect_counters_step(abi, before, input)
            if input.opcode == 0 { output.candidate_state.highest_accepted = before.highest_accepted &+ 1 }
            else { output.candidate_state.next_outbound = before.next_outbound &+ 1 }
            return output
        })
        var viewer = pair.viewer
        let originalViewer = viewer
        #expect(throws: RemoteSessionCoreError.invalidReconnectCounterBridge) {
            try begin(&viewer, identity: pair.viewerIdentity, producer: wrongOtherSlot)
        }
        #expect(viewer == originalViewer)
        let request = try signedRequest(record: pair.viewer, identity: pair.viewerIdentity, sequence: 64)
        var host = pair.host
        let originalHost = host
        #expect(throws: RemoteSessionCoreError.invalidReconnectCounterBridge) {
            try respond(&host, to: request, identity: pair.hostIdentity, producer: wrongOtherSlot)
        }
        #expect(host == originalHost)
        let wrongSequence = BelugaRustReconnectCounterProducer(step: { abi, before, input in
            var output = beluga_core_reconnect_counters_step(abi, before, input)
            output.candidate_state.highest_accepted = input.request_sequence &+ 1
            return output
        })
        #expect(throws: RemoteSessionCoreError.invalidReconnectCounterBridge) {
            try respond(&host, to: request, identity: pair.hostIdentity, producer: wrongSequence)
        }
        #expect(host == originalHost)
    }

    @Test func freshProjectionUsesCurrentRecordWithoutStoredProducerOrShadowState() throws {
        let pair = try makeActivePair()
        var record = pair.viewer
        let probe = Probe()
        _ = try begin(&record, identity: pair.viewerIdentity, producer: probe.actual)
        #expect(probe.calls == 1)
        #expect(probe.last?.abi == 1)
        #expect(probe.last?.state.next_outbound == 1)
        #expect(probe.last?.state.highest_accepted == 0)
        #expect(probe.last?.event.opcode == 0)
        #expect(probe.last?.event.request_sequence == 0)
        record = try roundTrip(record)
        record.nextOutboundReconnectSequence = 63
        record.highestAcceptedReconnectSequence = .max
        _ = try begin(&record, identity: pair.viewerIdentity, producer: probe.actual)
        #expect(probe.calls == 2)
        #expect(probe.last?.state.next_outbound == 63)
        #expect(probe.last?.state.highest_accepted == UInt64.max)
        #expect(record.nextOutboundReconnectSequence == 64)
        #expect(record.highestAcceptedReconnectSequence == .max)
    }

    @Test func valueCopiesAndCodableKeepIndependentWholeRecordSemantics() throws {
        func requiresSendable<T: Sendable>(_ value: T) { _ = value }
        let pair = try makeActivePair()
        var first = pair.viewer
        var second = first
        requiresSendable(first)
        let original = first
        let requestA = try begin(&first, identity: pair.viewerIdentity).request
        #expect(second == original)
        let requestB = try begin(&second, identity: pair.viewerIdentity).request
        #expect(try remoteCanonicalData(requestA.unsigned) == remoteCanonicalData(requestB.unsigned))
        try expectValidSignature(requestA, identity: pair.viewerIdentity)
        try expectValidSignature(requestB, identity: pair.viewerIdentity)
        #expect(first == second)
        #expect(try roundTrip(first) == first)
        var hostA = pair.host
        var hostB = hostA
        _ = try respond(&hostA, to: requestA, identity: pair.hostIdentity)
        #expect(hostB == pair.host)
        _ = try respond(&hostB, to: requestA, identity: pair.hostIdentity)
        #expect(hostA == hostB)
        #expect(try roundTrip(hostA) == hostA)
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) is [String: Any])
    }

    @Test func redactedErrorsAndRecordNeverExposeCountersOrCredentials() throws {
        let pair = try makeActivePair()
        #expect(RemoteSessionCoreError.invalidReconnectCounterBridge.errorDescription
                == "The reconnect counter proposal could not be verified.")
        #expect(pair.viewer.description == "<redacted paired remote device>")
        #expect(!pair.viewer.description.contains(pair.viewer.pairID.uuidString))
        #expect(!pair.host.description.contains(pair.host.commitID.uuidString))
    }

    // This deliberately independent flat oracle is test-only. Native production
    // never selects its proposed state, retries the export, or resets a record.
    private func frozenNumericReference(next: UInt64, highest: UInt64, input: Event)
        -> (decision: UInt32, next: UInt64, highest: UInt64) {
        if input.opcode == 0 {
            if next == .max { return (1, next, highest) }
            return (0, next + 1, highest)
        }
        if input.request_sequence <= highest { return (2, next, highest) }
        return (0, next, input.request_sequence)
    }

    private func bytes(_ byte: UInt8) -> Data { Data(repeating: byte, count: 32) }

    private func expectValidSignature(_ request: RemoteReconnectRequest,
                                      identity: RemoteDeviceIdentity) throws {
        #expect(request.isStructurallyValid)
        #expect(remoteVerifySignature(request.signature, for: remoteDomainSeparated(
            "AudioStreamer.Reconnect.Request.Signature.v1", try remoteCanonicalData(request.unsigned)),
            publicKey: identity.signingPublicKey))
    }

    private func expectValidSignature(_ response: RemoteReconnectResponse,
                                      identity: RemoteDeviceIdentity) throws {
        #expect(response.isStructurallyValid)
        #expect(remoteVerifySignature(response.signature, for: remoteDomainSeparated(
            "AudioStreamer.Reconnect.Response.Signature.v1", try remoteCanonicalData(response.unsigned)),
            publicKey: identity.signingPublicKey))
    }

    private func begin(_ record: inout RemotePairedDeviceRecord, identity: RemoteDeviceIdentity,
                       key: Data = Data(repeating: 0x51, count: 32),
                       nonce: Data = Data(repeating: 0x61, count: 32),
                       producer: BelugaRustReconnectCounterProducer = .actual) throws -> RemoteReconnectInitiator {
        try record.beginReconnect(using: identity, ephemeralPrivateKeyRawRepresentation: key,
                                  nonce: nonce, counterProducer: producer)
    }

    private func respond(_ record: inout RemotePairedDeviceRecord, to request: RemoteReconnectRequest,
                         identity: RemoteDeviceIdentity,
                         key: Data = Data(repeating: 0x52, count: 32),
                         nonce: Data = Data(repeating: 0x62, count: 32),
                         producer: BelugaRustReconnectCounterProducer = .actual) throws -> RemoteReconnectResponder {
        try record.respond(to: request, using: identity, ephemeralPrivateKeyRawRepresentation: key,
                           nonce: nonce, counterProducer: producer)
    }

    private func signedRequest(record: RemotePairedDeviceRecord, identity: RemoteDeviceIdentity,
                               sequence: UInt64, publicKey: Data? = nil) throws -> RemoteReconnectRequest {
        let agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes(0x51))
        let unsigned = RemoteReconnectRequestUnsigned(protocolVersion: RemoteReconnectRequest.currentProtocolVersion,
            pairID: record.pairID, requesterDeviceID: record.localDeviceID, requesterRole: .viewer,
            targetDeviceID: record.remoteDeviceID, sequence: sequence,
            ephemeralKeyAgreementPublicKey: publicKey ?? agreement.publicKey.rawRepresentation,
            nonce: bytes(0x61))
        let signature = try identity.signature(for: remoteDomainSeparated(
            "AudioStreamer.Reconnect.Request.Signature.v1", try remoteCanonicalData(unsigned)))
        return RemoteReconnectRequest(protocolVersion: unsigned.protocolVersion, pairID: unsigned.pairID,
            requesterDeviceID: unsigned.requesterDeviceID, requesterRole: unsigned.requesterRole,
            targetDeviceID: unsigned.targetDeviceID, sequence: unsigned.sequence,
            ephemeralKeyAgreementPublicKey: unsigned.ephemeralKeyAgreementPublicKey,
            nonce: unsigned.nonce, signature: signature)
    }

    private func replacing(_ request: RemoteReconnectRequest, protocolVersion: UInt8? = nil,
                           sequence: UInt64? = nil, publicKey: Data? = nil,
                           nonce: Data? = nil, signature: Data? = nil) -> RemoteReconnectRequest {
        RemoteReconnectRequest(protocolVersion: protocolVersion ?? request.protocolVersion,
            pairID: request.pairID, requesterDeviceID: request.requesterDeviceID,
            requesterRole: request.requesterRole, targetDeviceID: request.targetDeviceID,
            sequence: sequence ?? request.sequence,
            ephemeralKeyAgreementPublicKey: publicKey ?? request.ephemeralKeyAgreementPublicKey,
            nonce: nonce ?? request.nonce, signature: signature ?? request.signature)
    }

    private func tamperedSignature(_ request: RemoteReconnectRequest) throws -> RemoteReconnectRequest {
        var signature = request.signature
        #expect(signature.count == 64)
        signature[0] ^= 1
        return replacing(request, signature: signature)
    }

    private func roundTrip(_ record: RemotePairedDeviceRecord) throws -> RemotePairedDeviceRecord {
        try JSONDecoder().decode(RemotePairedDeviceRecord.self, from: JSONEncoder().encode(record))
    }

    private struct ActivePair {
        let hostIdentity: RemoteDeviceIdentity
        let viewerIdentity: RemoteDeviceIdentity
        let host: RemotePairedDeviceRecord
        let viewer: RemotePairedDeviceRecord
    }

    /// Uses the unchanged real authenticated pairing transcript and activation,
    /// not a fabricated active record or a mocked signature-verification result.
    private func makeActivePair() throws -> ActivePair {
        let hostIdentity = try RemoteDeviceIdentity(
            deviceID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            role: .host, displayName: "Synthetic host",
            signingPrivateKeyRawRepresentation: bytes(0x11))
        let viewerIdentity = try RemoteDeviceIdentity(
            deviceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            role: .viewer, displayName: "Synthetic viewer",
            signingPrivateKeyRawRepresentation: bytes(0x12))
        let invitation = try RemoteInvitationCode(secret: Data(0..<20))
        let host = try RemotePairingParticipant(identity: hostIdentity, invitation: invitation,
            ephemeralPrivateKeyRawRepresentation: bytes(0x31), nonce: bytes(0x41))
        let viewer = try RemotePairingParticipant(identity: viewerIdentity, invitation: invitation,
            ephemeralPrivateKeyRawRepresentation: bytes(0x32), nonce: bytes(0x42))
        let hostAgreement = try host.accept(viewer.hello)
        let viewerAgreement = try viewer.accept(host.hello)
        let hostConfirmation = try hostAgreement.makeConfirmation()
        let viewerConfirmation = try viewerAgreement.makeConfirmation()
        let acknowledgement = try viewerAgreement.makeCommit(phase: .acknowledgement)
        let completion = try hostAgreement.makeCommit(phase: .completion)
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        var hostRecord = try hostAgreement.finalize(peerConfirmation: viewerConfirmation,
            finalPeerCommit: acknowledgement, createdAt: createdAt)
        let persisted = try hostRecord.prepareCompletion(using: hostIdentity)
        try hostRecord.markCompletionSent(commitID: persisted.commitID)
        let viewerRecord = try viewerAgreement.finalize(peerConfirmation: hostConfirmation,
            finalPeerCommit: completion, createdAt: createdAt)
        guard case .resend(let activation) = viewerRecord.recoveryAction else {
            throw RemoteSessionCoreError.invalidPairingCommit
        }
        try hostRecord.acceptActivationAcknowledgement(activation)
        return ActivePair(hostIdentity: hostIdentity, viewerIdentity: viewerIdentity,
                          host: hostRecord, viewer: viewerRecord)
    }

    private final class Probe: @unchecked Sendable {
        struct Call { let abi: UInt32; let state: State; let event: Event }
        private let lock = NSLock()
        private var recorded: [Call] = []
        var calls: Int { lock.lock(); defer { lock.unlock() }; return recorded.count }
        var last: Call? { lock.lock(); defer { lock.unlock() }; return recorded.last }
        var actual: BelugaRustReconnectCounterProducer {
            BelugaRustReconnectCounterProducer(step: { [self] abi, state, event in
                lock.lock(); recorded.append(Call(abi: abi, state: state, event: event)); lock.unlock()
                return beluga_core_reconnect_counters_step(abi, state, event)
            })
        }
    }
}
