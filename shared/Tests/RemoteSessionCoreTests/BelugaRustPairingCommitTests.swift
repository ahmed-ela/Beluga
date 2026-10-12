import Foundation
import Testing
@testable import RemoteSessionCore

/// Actual Rust-plan and native cryptographic composition. Keys are deterministic synthetic fixtures.
struct BelugaRustPairingCommitTests {
    private typealias Boundary = BelugaRustPairingCommitBoundary
    private typealias Producer = BelugaRustPairingCommitProducer
    private typealias Mutation = @Sendable (inout Boundary.Output) -> Void

    @Test func decodedFaultContextIsClosedAndOriginalImmutableGuardWins() throws {
        let stages = try stages()
        let bytes = try remoteCanonicalData(stages.viewerIssued)
        let key = BelugaPairingCommitDecodeSelection.key
        let exact = BelugaPairingCommitDecodeSelection.reservedResultMatching(
            role: .viewer, state: .acceptedIssued, cache: .acknowledgement)
        #expect(key.rawValue == "com.elamin.beluga.testing.pairing-commit-decode-v1")
        #expect(exact == UInt32(0x8000_0112), "Pin the independently literal closed encoding")
        let invalidContexts: [any Sendable] = [
            "1", Int(1), true, NSNumber(value: 1), UInt64(1),
            UInt32(0), UInt32.max, UInt32(0x8000_0008), UInt32(0x8000_0115)
        ]
        for context in invalidContexts + [UInt32(1), exact] {
            let decoder = JSONDecoder()
            decoder.userInfo[key] = context
            #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
                try decoder.decode(RemotePairedDeviceRecord.self, from: bytes)
            }
        }
        // The fault does not bypass the unchanged immutable native initializer guard.
        var malformed = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        malformed["nextOutboundReconnectSequence"] = UInt64(0)
        let malformedBytes = try JSONSerialization.data(withJSONObject: malformed)
        let immutableGuardContexts: [any Sendable] = [UInt32(1), "wrong-type", UInt32.max]
        for context in immutableGuardContexts {
            let decoder = JSONDecoder()
            decoder.userInfo[key] = context
            #expect(throws: RemoteSessionCoreError.invalidPairedDeviceRecord) {
                try decoder.decode(RemotePairedDeviceRecord.self, from: malformedBytes)
            }
        }
        #expect(try JSONDecoder().decode(RemotePairedDeviceRecord.self, from: bytes) == stages.viewerIssued)
    }

    @Test func absentAndNonmatchingDecodeUseActualPlanAndRetainNoContext() throws {
        let stages = try stages()
        let bytes = try remoteCanonicalData(stages.viewerIssued)
        let absent = try JSONDecoder().decode(RemotePairedDeviceRecord.self, from: bytes)
        let decoder = JSONDecoder()
        decoder.userInfo[BelugaPairingCommitDecodeSelection.key] = UInt32(0x8000_0000)
        var nonmatching = try decoder.decode(RemotePairedDeviceRecord.self, from: bytes)
        #expect(absent == stages.viewerIssued)
        #expect(nonmatching == stages.viewerIssued)
        #expect(try remoteCanonicalData(nonmatching) == bytes)
        #expect(nonmatching.recoveryAction == .resend(stages.acknowledgement))
        #expect(try nonmatching.prepareAcknowledgement(
            after: stages.proposal, using: stages.fixture.viewerIdentity) == stages.acknowledgement)
        #expect(nonmatching == stages.viewerIssued)
        // Clearing or changing this decoder cannot change a previously decoded value.
        decoder.userInfo[BelugaPairingCommitDecodeSelection.key] = UInt32(1)
        #expect(nonmatching.recoveryAction == .resend(stages.acknowledgement))
        #expect(try remoteCanonicalData(nonmatching) == bytes)
        #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
            try decoder.decode(RemotePairedDeviceRecord.self, from: bytes)
        }
        #expect(try JSONDecoder().decode(RemotePairedDeviceRecord.self, from: bytes) == absent)
    }

    @Test func fourGenuineMintSitesPreserveOriginalInjectedErrorAndWholePredecessor() throws {
        let stages = try stages()
        let cases: [(RemotePairingCommitPhase, RemotePairedDeviceRecord)] = [
            (.proposal, stages.fixture.host), (.acknowledgement, stages.fixture.viewer),
            (.completion, stages.hostReceived), (.activationAcknowledgement, stages.viewerIssued)
        ]
        for (phase, predecessor) in cases {
            var record = predecessor
            let before = try remoteCanonicalData(record)
            let sentinel = PairingConstructionProbeSentinel()
            let calls = CallCounter()
            let probe = BelugaPairingCommitConstructionProbe(before: { observed in
                #expect(observed == phase)
                calls.increment()
                throw sentinel
            })
            do {
                _ = try invokeMint(phase, record: &record, stages: stages, probe: probe)
                Issue.record("The throwing preconstructor probe must abort the admitted mint")
            } catch {
                #expect((error as? PairingConstructionProbeSentinel) === sentinel,
                    "Propagate the exact injected error, not a normalized bridge/auth error")
            }
            #expect(calls.value == 1)
            #expect(record == predecessor)
            #expect(try remoteCanonicalData(record) == before)
            #expect(record.recoveryAction == predecessor.recoveryAction)
            #expect(calls.value == 1, "Getter has no retained per-call probe")
        }
    }

    @Test func cachedReturnsActualAuthenticationAndRefusalsNeverInvokeConstructionProbe() throws {
        let stages = try stages()
        let calls = CallCounter()
        let sentinel = PairingConstructionProbeSentinel()
        let probe = BelugaPairingCommitConstructionProbe(before: { _ in
            calls.increment(); throw sentinel
        })
        let cached: [(RemotePairingCommitPhase, RemotePairedDeviceRecord, RemotePairingCommit)] = [
            (.proposal, stages.hostProposed, stages.proposal),
            (.acknowledgement, stages.viewerIssued, stages.acknowledgement),
            (.completion, stages.hostCompleted, stages.completion),
            (.activationAcknowledgement, stages.viewerActive, stages.activation)
        ]
        for (phase, predecessor, expected) in cached {
            var record = predecessor
            #expect(try invokeMint(phase, record: &record, stages: stages, probe: probe) == expected)
            #expect(record == predecessor)
        }
        for predecessor in [stages.fixture.viewer, stages.viewerIssued] {
            var record = predecessor
            #expect(throws: RemoteSessionCoreError.authenticationFailed) {
                try record.prepareAcknowledgement(after: tamperedSignature(stages.proposal),
                    using: stages.fixture.viewerIdentity, commitProducer: .actual,
                    constructionProbe: probe)
            }
            #expect(record == predecessor)
        }
        for predecessor in [stages.viewerIssued, stages.viewerActive] {
            var record = predecessor
            #expect(throws: RemoteSessionCoreError.authenticationFailed) {
                try record.acceptCompletion(tamperedSignature(stages.completion),
                    using: stages.fixture.viewerIdentity, commitProducer: .actual,
                    constructionProbe: probe)
            }
            #expect(record == predecessor)
        }
        var premature = stages.fixture.host
        #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
            try premature.prepareCompletion(using: stages.fixture.hostIdentity,
                commitProducer: .actual, constructionProbe: probe)
        }
        #expect(premature == stages.fixture.host)
        var missingCache = stages.fixture.viewer
        missingCache.pairingState = .active
        let beforeMissing = missingCache
        #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
            try missingCache.acceptCompletion(stages.completion,
                using: stages.fixture.viewerIdentity, commitProducer: .actual,
                constructionProbe: probe)
        }
        #expect(missingCache == beforeMissing)
        var wrongIdentity = stages.fixture.host
        #expect(throws: RemoteSessionCoreError.deviceIdentityMismatch) {
            try wrongIdentity.prepareProposal(using: stages.fixture.viewerIdentity,
                commitProducer: .actual, constructionProbe: probe)
        }
        #expect(wrongIdentity == stages.fixture.host)
        var badPlan = stages.fixture.host
        #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
            try badPlan.prepareProposal(using: stages.fixture.hostIdentity,
                commitProducer: corrupting { $0.reserved = 1 }, constructionProbe: probe)
        }
        #expect(badPlan == stages.fixture.host)
        // Getter and nonmint operations have no probe parameter or retained closure.
        #expect(stages.hostActive.recoveryAction == .none)
        var acceptOnly = stages.hostProposed
        try acceptOnly.acceptAcknowledgement(stages.acknowledgement)
        #expect(acceptOnly.pairingState == .acceptedReceived)
        var sentOnly = stages.hostCompleted
        try sentOnly.markCompletionSent(commitID: stages.completion.commitID)
        #expect(sentOnly == stages.hostCompleted)
        var activationOnly = stages.hostCompleted
        try activationOnly.acceptActivationAcknowledgement(stages.activation)
        #expect(activationOnly == stages.hostActive)
        #expect(calls.value == 0)
    }

    /// Only test dispatch; each branch calls the genuine existing operation with actual C.
    private func invokeMint(_ phase: RemotePairingCommitPhase, record: inout RemotePairedDeviceRecord,
                            stages: Stages, probe: BelugaPairingCommitConstructionProbe) throws -> RemotePairingCommit {
        switch phase {
        case .proposal:
            return try record.prepareProposal(using: stages.fixture.hostIdentity,
                commitProducer: .actual, constructionProbe: probe)
        case .acknowledgement:
            return try record.prepareAcknowledgement(after: stages.proposal,
                using: stages.fixture.viewerIdentity, commitProducer: .actual,
                constructionProbe: probe)
        case .completion:
            return try record.prepareCompletion(using: stages.fixture.hostIdentity,
                commitProducer: .actual, constructionProbe: probe)
        case .activationAcknowledgement:
            return try record.acceptCompletion(stages.completion,
                using: stages.fixture.viewerIdentity, commitProducer: .actual,
                constructionProbe: probe)
        }
    }

    private final class PairingConstructionProbeSentinel: Error, Sendable {}

    @Test func actualCopiedLayoutsAndAll720PlansMatchFrozenOriginal() throws {
        #expect(MemoryLayout<Boundary.State>.size == 24)
        #expect(MemoryLayout<Boundary.State>.stride == 24)
        #expect(MemoryLayout<Boundary.State>.alignment == 4)
        #expect(MemoryLayout<Boundary.State>.offset(of: \.abi_version) == 0)
        #expect(MemoryLayout<Boundary.State>.offset(of: \.reserved) == 4)
        #expect(MemoryLayout<Boundary.State>.offset(of: \.local_role) == 8)
        #expect(MemoryLayout<Boundary.State>.offset(of: \.pairing_state) == 12)
        #expect(MemoryLayout<Boundary.State>.offset(of: \.recovery_phase) == 16)
        #expect(MemoryLayout<Boundary.State>.offset(of: \.reserved_tail) == 20)
        #expect(MemoryLayout<Boundary.Event>.size == 16)
        #expect(MemoryLayout<Boundary.Event>.alignment == 4)
        #expect(MemoryLayout<Boundary.Event>.stride == 16)
        #expect(MemoryLayout<Boundary.Event>.offset(of: \.opcode) == 0)
        #expect(MemoryLayout<Boundary.Event>.offset(of: \.reserved) == 4)
        #expect(MemoryLayout<Boundary.Event>.offset(of: \.commit_id_matches) == 8)
        #expect(MemoryLayout<Boundary.Event>.offset(of: \.reserved_tail) == 12)
        #expect(MemoryLayout<Boundary.Output>.size == 40)
        #expect(MemoryLayout<Boundary.Output>.alignment == 4)
        #expect(MemoryLayout<Boundary.Output>.stride == 40)
        #expect(MemoryLayout<Boundary.Output>.offset(of: \.candidate_state) == 0)
        #expect(MemoryLayout<Boundary.Output>.offset(of: \.decision) == 24)
        #expect(MemoryLayout<Boundary.Output>.offset(of: \.action) == 28)
        #expect(MemoryLayout<Boundary.Output>.offset(of: \.auth_phase) == 32)
        #expect(MemoryLayout<Boundary.Output>.offset(of: \.reserved) == 36)
        var cases = 0
        for role in UInt32(0)...1 {
            for phase in UInt32(0)...3 {
                for cache in UInt32(0)...4 {
                    for opcode in UInt32(0)...8 {
                        for exact in UInt32(0)...1 {
                            var before = Boundary.State()
                            before.abi_version = 1
                            before.local_role = role
                            before.pairing_state = phase
                            before.recovery_phase = cache
                            var event = Boundary.Event()
                            event.opcode = opcode
                            event.commit_id_matches = exact
                            let output = Producer.actual.step(1, before, event)
                            let expected = OriginalPairingCommitPlan.evaluate(
                                role: role, phase: phase, cache: cache, opcode: opcode, exact: exact
                            )
                            #expect(output.candidate_state.abi_version == 1)
                            #expect(output.candidate_state.reserved == 0)
                            #expect(output.candidate_state.local_role == role)
                            #expect(output.candidate_state.pairing_state == expected.phase)
                            #expect(output.candidate_state.recovery_phase == expected.cache)
                            #expect(output.candidate_state.reserved_tail == 0)
                            #expect(output.decision == expected.decision)
                            #expect(output.action == expected.action)
                            #expect(output.auth_phase == expected.auth)
                            #expect(output.reserved == 0)
                            #expect(Boundary.accepts(before: before, event: event, output: output))
                            cases += 1
                        }
                    }
                }
            }
        }
        #expect(cases == 720)
    }

    @Test func genuineSevenTransitionsAndEveryCachedReturnRetainWholeCommit() throws {
        let fixture = try fixture()
        var host = fixture.host
        var viewer = fixture.viewer
        host.nextOutboundReconnectSequence = UInt64.max
        host.highestAcceptedReconnectSequence = UInt64.max - 17
        viewer.nextOutboundReconnectSequence = UInt64.max - 1
        viewer.highestAcceptedReconnectSequence = UInt64.max - 33
        #expect(host.recoveryAction == .issueProposal)
        #expect(viewer.recoveryAction == .awaitProposal)
        let proposal = try host.prepareProposal(using: fixture.hostIdentity)
        #expect(try host.prepareProposal(using: fixture.hostIdentity) == proposal)
        #expect(host.recoveryAction == .resend(proposal))
        #expect(proposal.phase == .proposal)
        let acknowledgement = try viewer.prepareAcknowledgement(
            after: proposal, using: fixture.viewerIdentity
        )
        #expect(try viewer.prepareAcknowledgement(
            after: proposal, using: fixture.viewerIdentity
        ) == acknowledgement)
        #expect(viewer.recoveryAction == .resend(acknowledgement))
        try host.acceptAcknowledgement(acknowledgement)
        #expect(host.pairingState == .acceptedReceived)
        #expect(host.recoveryAction == .issueCompletion)
        let completion = try host.prepareCompletion(using: fixture.hostIdentity)
        #expect(try host.prepareCompletion(using: fixture.hostIdentity) == completion)
        #expect(host.recoveryAction == .resend(completion))
        let beforeSend = host
        try host.markCompletionSent(commitID: completion.commitID)
        #expect(host == beforeSend)
        let activation = try viewer.acceptCompletion(completion, using: fixture.viewerIdentity)
        #expect(try viewer.acceptCompletion(
            completion, using: fixture.viewerIdentity
        ) == activation)
        #expect(viewer.recoveryAction == .resend(activation))
        try host.acceptActivationAcknowledgement(activation)
        #expect(host.pairingState == .active)
        #expect(viewer.pairingState == .active)
        #expect(host.recoveryAction == .none)
        try host.acceptActivationAcknowledgement(activation)
        #expect(host.recoveryAction == .none)
        #expect(host.nextOutboundReconnectSequence == UInt64.max)
        #expect(host.highestAcceptedReconnectSequence == UInt64.max - 17)
        #expect(viewer.nextOutboundReconnectSequence == UInt64.max - 1)
        #expect(viewer.highestAcceptedReconnectSequence == UInt64.max - 33)
        for (commit, identity) in [
            (proposal, fixture.hostIdentity), (acknowledgement, fixture.viewerIdentity),
            (completion, fixture.hostIdentity), (activation, fixture.viewerIdentity)
        ] {
            let unsigned = try remoteCanonicalData(commit.unsigned)
            #expect(remoteVerifySignature(
                commit.signature,
                for: remoteDomainSeparated(
                    "AudioStreamer.Pairing.Commit.Signature.v1", unsigned, commit.commitTag
                ),
                publicKey: identity.signingPublicKey
            ))
        }
    }

    @Test func genuineEveryCommitOperationPreservesAllOtherFieldsAndNontrivialExactCounters() throws {
        let fixture = try fixture()
        var host = fixture.host
        var viewer = fixture.viewer
        host.nextOutboundReconnectSequence = UInt64.max
        host.highestAcceptedReconnectSequence = UInt64(0x0020_0000_0000_0123)
        viewer.nextOutboundReconnectSequence = UInt64(0x0020_0000_0000_0457)
        viewer.highestAcceptedReconnectSequence = UInt64.max
        // Initial snapshots are actually accepted by the stored native decoder/default C.
        host = try roundTrip(host)
        viewer = try roundTrip(viewer)
        let originalHost = host
        let originalViewer = viewer

        let proposal = try host.prepareProposal(using: fixture.hostIdentity)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)
        #expect(host.pairingState == .pending)
        #expect(host.recoveryAction == .resend(proposal))
        #expect(try host.prepareProposal(using: fixture.hostIdentity) == proposal)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)

        let acknowledgement = try viewer.prepareAcknowledgement(
            after: proposal, using: fixture.viewerIdentity
        )
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)
        #expect(viewer.pairingState == .acceptedIssued)
        #expect(viewer.recoveryAction == .resend(acknowledgement))
        #expect(try viewer.prepareAcknowledgement(
            after: proposal, using: fixture.viewerIdentity
        ) == acknowledgement)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)

        try host.acceptAcknowledgement(acknowledgement)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)
        #expect(host.pairingState == .acceptedReceived)
        #expect(host.recoveryAction == .issueCompletion)
        try host.acceptAcknowledgement(acknowledgement)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)

        let completion = try host.prepareCompletion(using: fixture.hostIdentity)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)
        #expect(host.pairingState == .acceptedReceived)
        #expect(host.recoveryAction == .resend(completion))
        #expect(try host.prepareCompletion(using: fixture.hostIdentity) == completion)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)

        let sentPredecessor = host
        try host.markCompletionSent(commitID: completion.commitID)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)
        #expect(host == sentPredecessor)
        #expect(host.pairingState == .acceptedReceived)

        let activation = try viewer.acceptCompletion(completion, using: fixture.viewerIdentity)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)
        #expect(viewer.pairingState == .active)
        #expect(viewer.recoveryAction == .resend(activation))
        #expect(try viewer.acceptCompletion(
            completion, using: fixture.viewerIdentity
        ) == activation)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)

        try host.acceptActivationAcknowledgement(activation)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)
        #expect(host.pairingState == .active)
        #expect(host.recoveryAction == .none)
        try host.acceptActivationAcknowledgement(activation)
        try assertOnlyCommitFieldsChanged(host, from: originalHost)
        try assertOnlyCommitFieldsChanged(viewer, from: originalViewer)
        #expect(try roundTrip(host) == host)
        #expect(try roundTrip(viewer) == viewer)
    }

    @Test func coldValueRoundTripsKeepBothHostAcknowledgementCutsAndSendNonactivation() throws {
        let stages = try stages()
        let firstCut = try roundTrip(stages.hostReceived)
        #expect(firstCut == stages.hostReceived)
        #expect(firstCut.pairingState == .acceptedReceived)
        #expect(firstCut.recoveryAction == .issueCompletion)
        var restored = firstCut
        let completion = try restored.prepareCompletion(using: stages.fixture.hostIdentity)
        let secondCut = try roundTrip(restored)
        #expect(secondCut == restored)
        #expect(secondCut.recoveryAction == .resend(completion))
        var afterDeliveryLoss = secondCut
        try afterDeliveryLoss.markCompletionSent(commitID: completion.commitID)
        #expect(afterDeliveryLoss == secondCut)
        try afterDeliveryLoss.acceptAcknowledgement(stages.acknowledgement)
        #expect(afterDeliveryLoss == secondCut)
        #expect(try afterDeliveryLoss.prepareCompletion(
            using: stages.fixture.hostIdentity
        ) == completion)
        // These are real Codable cold-value boundaries, not a Keychain/durable-write oracle.
    }

    @Test func identityMismatchWinsBeforePolicyAndProducerForEveryIdentityTakingMethod() throws {
        let stages = try stages()
        let counter = CallCounter()
        let counted = counting(counter)
        var host = stages.fixture.host
        let hostBefore = host
        #expect(throws: RemoteSessionCoreError.deviceIdentityMismatch) {
            try host.prepareProposal(using: stages.fixture.viewerIdentity, commitProducer: counted)
        }
        #expect(host == hostBefore)
        var viewer = stages.fixture.viewer
        let viewerBefore = viewer
        #expect(throws: RemoteSessionCoreError.deviceIdentityMismatch) {
            try viewer.prepareAcknowledgement(
                after: stages.proposal, using: stages.fixture.hostIdentity, commitProducer: counted
            )
        }
        #expect(viewer == viewerBefore)
        var received = stages.hostReceived
        let receivedBefore = received
        #expect(throws: RemoteSessionCoreError.deviceIdentityMismatch) {
            try received.prepareCompletion(
                using: stages.fixture.viewerIdentity, commitProducer: counted
            )
        }
        #expect(received == receivedBefore)
        var issued = stages.viewerIssued
        let issuedBefore = issued
        #expect(throws: RemoteSessionCoreError.deviceIdentityMismatch) {
            try issued.acceptCompletion(
                stages.completion, using: stages.fixture.hostIdentity, commitProducer: counted
            )
        }
        #expect(issued == issuedBefore)
        #expect(counter.value == 0)
    }

    @Test func originalRoleAndPhaseRefusalPrecedesBadInboundAuthentication() throws {
        let stages = try stages()
        let badAck = try tamperedSignature(stages.acknowledgement)
        var wrongRole = stages.fixture.viewer
        let beforeRole = wrongRole
        #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
            try wrongRole.acceptAcknowledgement(badAck)
        }
        #expect(wrongRole == beforeRole)
        var wrongHostPhase = stages.fixture.host
        wrongHostPhase.pairingState = .acceptedIssued
        let beforeHostPhase = wrongHostPhase
        #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
            try wrongHostPhase.acceptAcknowledgement(badAck)
        }
        #expect(wrongHostPhase == beforeHostPhase)
        var wrongViewerPhase = stages.fixture.viewer
        let beforeViewerPhase = wrongViewerPhase
        #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
            try wrongViewerPhase.acceptCompletion(
                try tamperedSignature(stages.completion), using: stages.fixture.viewerIdentity
            )
        }
        #expect(wrongViewerPhase == beforeViewerPhase)
        var wrongActivationPhase = stages.fixture.host
        let beforeActivation = wrongActivationPhase
        #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
            try wrongActivationPhase.acceptActivationAcknowledgement(
                try tamperedSignature(stages.activation)
            )
        }
        #expect(wrongActivationPhase == beforeActivation)
        var eligibleViewer = stages.fixture.viewer
        let eligibleBefore = eligibleViewer
        #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
            // Genuine signature, but wrong supplied message phase: native structure wins.
            try eligibleViewer.prepareAcknowledgement(
                after: stages.completion, using: stages.fixture.viewerIdentity
            )
        }
        #expect(eligibleViewer == eligibleBefore)
    }

    @Test func cachedIssuedAcknowledgementAuthenticatesActualNewProposalBeforeExactReturn() throws {
        let stages = try stages()
        var viewer = stages.viewerIssued
        let before = viewer
        #expect(throws: RemoteSessionCoreError.authenticationFailed) {
            try viewer.prepareAcknowledgement(
                after: try tamperedSignature(stages.proposal), using: stages.fixture.viewerIdentity
            )
        }
        #expect(viewer == before)
        #expect(try viewer.prepareAcknowledgement(
            after: stages.proposal, using: stages.fixture.viewerIdentity
        ) == stages.acknowledgement)
        #expect(viewer == before)
    }

    @Test func hostAcknowledgementReplayReauthenticatesAndPreservesKnownUnusualCache() throws {
        let stages = try stages()
        var host = stages.hostProposed
        host.pairingState = .acceptedReceived
        let before = host
        #expect(host.recoveryAction == .resend(stages.proposal))
        #expect(throws: RemoteSessionCoreError.authenticationFailed) {
            try host.acceptAcknowledgement(try tamperedSignature(stages.acknowledgement))
        }
        #expect(host == before)
        try host.acceptAcknowledgement(stages.acknowledgement)
        #expect(host == before)
        host.pairingState = .active
        let activeBefore = host
        try host.acceptAcknowledgement(stages.acknowledgement)
        #expect(host == activeBefore)
        #expect(host.recoveryAction == .resend(stages.proposal))
    }

    @Test func activeViewerAuthenticatesCompletionBeforeMissingOrWrongCacheRefusal() throws {
        let stages = try stages()
        for source in [stages.fixture.viewer, stages.viewerIssued] {
            var viewer = source
            viewer.pairingState = .active
            let before = viewer
            #expect(throws: RemoteSessionCoreError.authenticationFailed) {
                try viewer.acceptCompletion(
                    try tamperedSignature(stages.completion), using: stages.fixture.viewerIdentity
                )
            }
            #expect(viewer == before)
            #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
                try viewer.acceptCompletion(stages.completion, using: stages.fixture.viewerIdentity)
            }
            #expect(viewer == before)
        }
    }

    @Test func activeHostCompletionIsGenuineEphemeralAndDoesNotReopenRecovery() throws {
        let stages = try stages()
        var host = stages.hostActive
        let before = host
        try host.acceptAcknowledgement(stages.acknowledgement)
        let completion = try host.prepareCompletion(using: stages.fixture.hostIdentity)
        try expectEquivalentFreshCommit(
            completion, stages.completion, signedBy: stages.fixture.hostIdentity
        )
        #expect(host == before)
        #expect(host.recoveryAction == .none)
        try host.markCompletionSent(commitID: completion.commitID)
        #expect(host == before)
        #expect(try roundTrip(host) == before)
        var viewer = stages.viewerActive
        #expect(try viewer.acceptCompletion(
            completion, using: stages.fixture.viewerIdentity
        ) == stages.activation)
    }

    @Test func markCompletionSentRequiresExactNativeUUIDAndNeverActivatesOrRetires() throws {
        let stages = try stages()
        for source in [stages.hostCompleted, stages.hostActive] {
            var host = source
            let before = host
            #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
                try host.markCompletionSent(commitID: UUID())
            }
            #expect(host == before)
            try host.markCompletionSent(commitID: stages.completion.commitID)
            try host.markCompletionSent(commitID: stages.completion.commitID)
            #expect(host == before)
        }
        var noPreparedCompletion = stages.hostReceived
        let before = noPreparedCompletion
        #expect(throws: RemoteSessionCoreError.invalidPairingCommit) {
            try noPreparedCompletion.markCompletionSent(commitID: stages.completion.commitID)
        }
        #expect(noPreparedCompletion == before)
    }

    @Test func genuineAuthenticationFailurePreservesWholeRecordAtAllInboundOperations() throws {
        let stages = try stages()
        var viewerPending = stages.fixture.viewer
        let pendingBefore = viewerPending
        #expect(throws: RemoteSessionCoreError.authenticationFailed) {
            try viewerPending.prepareAcknowledgement(
                after: try tamperedSignature(stages.proposal), using: stages.fixture.viewerIdentity
            )
        }
        #expect(viewerPending == pendingBefore)
        var host = stages.hostProposed
        let hostBefore = host
        #expect(throws: RemoteSessionCoreError.authenticationFailed) {
            try host.acceptAcknowledgement(try tamperedSignature(stages.acknowledgement))
        }
        #expect(host == hostBefore)
        var viewer = stages.viewerIssued
        let viewerBefore = viewer
        #expect(throws: RemoteSessionCoreError.authenticationFailed) {
            try viewer.acceptCompletion(
                try tamperedSignature(stages.completion), using: stages.fixture.viewerIdentity
            )
        }
        #expect(viewer == viewerBefore)
        var completed = stages.hostCompleted
        let completedBefore = completed
        #expect(throws: RemoteSessionCoreError.authenticationFailed) {
            try completed.acceptActivationAcknowledgement(try tamperedSignature(stages.activation))
        }
        #expect(completed == completedBefore)
    }

    @Test func knownWeirdTypedStatesKeepOriginalGetterWithoutGlobalStoredShapeGate() throws {
        let stages = try stages()
        let sources = [
            stages.fixture.host, stages.hostProposed, stages.hostCompleted,
            stages.fixture.viewer, stages.viewerIssued, stages.viewerActive
        ]
        var cases = 0
        for source in sources {
            let cache = try encodedRecovery(source)
            for phase in RemotePairingPersistenceState.allCases {
                var record = source
                record.pairingState = phase
                let before = record
                #expect(record.recoveryAction == originalRecovery(
                    role: record.localRole, state: phase, cache: cache
                ))
                #expect(record == before)
                cases += 1
            }
        }
        #expect(cases == 24)
    }

    @Test func pendingViewerCanReplaceKnownCacheOnlyAfterActualProposalAuthentication() throws {
        let stages = try stages()
        var viewer = stages.viewerActive
        viewer.pairingState = .pending
        let before = viewer
        #expect(throws: RemoteSessionCoreError.authenticationFailed) {
            try viewer.prepareAcknowledgement(
                after: try tamperedSignature(stages.proposal), using: stages.fixture.viewerIdentity
            )
        }
        #expect(viewer == before)
        let acknowledgement = try viewer.prepareAcknowledgement(
            after: stages.proposal, using: stages.fixture.viewerIdentity
        )
        try expectEquivalentFreshCommit(
            acknowledgement, stages.acknowledgement, signedBy: stages.fixture.viewerIdentity
        )
        #expect(viewer.pairingState == .acceptedIssued)
        #expect(viewer.recoveryAction == .resend(acknowledgement))
    }

    @Test func issuedViewerReplaysUnusualKnownCacheAfterAuthenticatingActualProposal() throws {
        let stages = try stages()
        var viewer = stages.viewerActive
        viewer.pairingState = .acceptedIssued
        let before = viewer
        #expect(throws: RemoteSessionCoreError.authenticationFailed) {
            try viewer.prepareAcknowledgement(
                after: try tamperedSignature(stages.proposal), using: stages.fixture.viewerIdentity
            )
        }
        #expect(viewer == before)
        #expect(try viewer.prepareAcknowledgement(
            after: stages.proposal, using: stages.fixture.viewerIdentity
        ) == stages.activation)
        #expect(viewer == before)
    }

    @Test func storedShapeValidationRemainsSeparateAndVerifiesActualOpaqueCacheProof() throws {
        let stages = try stages()
        for record in [
            stages.fixture.host, stages.hostProposed, stages.hostReceived, stages.hostCompleted,
            stages.hostActive, stages.fixture.viewer, stages.viewerIssued, stages.viewerActive
        ] {
            try record.validatePersistenceState()
            #expect(try roundTrip(record) == record)
        }
        var unusual = stages.hostProposed
        unusual.pairingState = .active
        #expect(unusual.recoveryAction == .resend(stages.proposal))
        #expect(throws: RemoteSessionCoreError.invalidPairedDeviceRecord) {
            try unusual.validatePersistenceState()
        }
        let bytes = try JSONEncoder().encode(stages.viewerIssued)
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var recovery = try #require(object["recoveryCommit"] as? [String: Any])
        let encodedSignature = try #require(recovery["signature"] as? String)
        var signature = try #require(Data(base64Encoded: encodedSignature))
        signature[0] ^= 1
        recovery["signature"] = signature.base64EncodedString()
        object["recoveryCommit"] = recovery
        let corrupt = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: RemoteSessionCoreError.invalidPairedDeviceRecord) {
            try JSONDecoder().decode(RemotePairedDeviceRecord.self, from: corrupt)
        }
    }

    @Test func malformedGetterIsExplicitInvalidBridgeNeverLegitimateNoneOrRecordMutation() throws {
        let stages = try stages()
        let record = stages.hostActive
        #expect(record.recoveryAction == .none)
        let badOutputs: [Mutation] = [
            { $0.action = 1 },
            { $0.decision = 1 },
            { $0.auth_phase = 1 },
            { $0.candidate_state.abi_version = 0 },
            { $0.candidate_state.pairing_state = 0 },
            { $0.candidate_state.recovery_phase = 1 },
            { $0.reserved = 1 }
        ]
        for mutation in badOutputs {
            #expect(record.recoveryAction(using: corrupting(mutation)) == .invalidBridge)
            #expect(record == stages.hostActive)
        }
        #expect(record.recoveryAction == .none)
    }

    @Test func malformedMintOutputCannotCreateOrCommitARecoveryObject() throws {
        let fixture = try fixture()
        let badOutputs: [Mutation] = [
            { $0.candidate_state.abi_version = 2 },
            { $0.candidate_state.reserved = 1 },
            { $0.candidate_state.reserved_tail = 1 },
            { $0.candidate_state.local_role = 1 },
            { $0.candidate_state.pairing_state = 3 },
            { $0.candidate_state.recovery_phase = 0 },
            { $0.candidate_state.recovery_phase = 4 },
            { $0.decision = 1 },
            { $0.decision = 2 },
            { $0.decision = 3 },
            { $0.decision = 99 },
            { $0.action = 0 },
            { $0.action = 3 },
            { $0.action = 8 },
            { $0.action = 99 },
            { $0.auth_phase = 1 },
            { $0.auth_phase = 99 },
            { $0.reserved = 1 }
        ]
        for mutation in badOutputs {
            var record = fixture.host
            #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
                try record.prepareProposal(using: fixture.hostIdentity, commitProducer: corrupting(mutation))
            }
            #expect(record == fixture.host)
            #expect(record.recoveryAction == .issueProposal)
        }
    }

    @Test func malformedAuthPlansCannotBypassActualPeerProofOrReplaceCachedValue() throws {
        let stages = try stages()
        let mutations: [Mutation] = [
            { $0.auth_phase = 0 }, { $0.auth_phase = 2 }, { $0.action = 6 },
            { $0.candidate_state.recovery_phase = 4 }, { $0.candidate_state.pairing_state = 3 }
        ]
        for mutation in mutations {
            var viewer = stages.viewerIssued
            let before = viewer
            #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
                try viewer.prepareAcknowledgement(
                    after: stages.proposal, using: stages.fixture.viewerIdentity,
                    commitProducer: corrupting(mutation)
                )
            }
            #expect(viewer == before)
        }
    }

    @Test func allSevenOperationsRejectMalformedCopiedOutputWithoutWholeRecordMutation() throws {
        let stages = try stages()
        let poisoned = corrupting { $0.reserved = 1 }
        var hostProposal = stages.fixture.host
        #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
            try hostProposal.prepareProposal(using: stages.fixture.hostIdentity, commitProducer: poisoned)
        }
        #expect(hostProposal == stages.fixture.host)
        var viewerAck = stages.fixture.viewer
        #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
            try viewerAck.prepareAcknowledgement(
                after: stages.proposal, using: stages.fixture.viewerIdentity, commitProducer: poisoned
            )
        }
        #expect(viewerAck == stages.fixture.viewer)
        var hostAck = stages.hostProposed
        #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
            try hostAck.acceptAcknowledgement(stages.acknowledgement, commitProducer: poisoned)
        }
        #expect(hostAck == stages.hostProposed)
        var hostCompletion = stages.hostReceived
        #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
            try hostCompletion.prepareCompletion(
                using: stages.fixture.hostIdentity, commitProducer: poisoned
            )
        }
        #expect(hostCompletion == stages.hostReceived)
        var sent = stages.hostCompleted
        #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
            try sent.markCompletionSent(commitID: stages.completion.commitID, commitProducer: poisoned)
        }
        #expect(sent == stages.hostCompleted)
        var viewerCompletion = stages.viewerIssued
        #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
            try viewerCompletion.acceptCompletion(
                stages.completion, using: stages.fixture.viewerIdentity, commitProducer: poisoned
            )
        }
        #expect(viewerCompletion == stages.viewerIssued)
        var hostActivation = stages.hostCompleted
        #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
            try hostActivation.acceptActivationAcknowledgement(
                stages.activation, commitProducer: poisoned
            )
        }
        #expect(hostActivation == stages.hostCompleted)
    }

    @Test func copiedOutputCannotConvertPostAuthRefusalIntoPrematureRefusalOrSuccess() throws {
        let stages = try stages()
        var viewer = stages.fixture.viewer
        viewer.pairingState = .active
        let before = viewer
        let mutations: [Mutation] = [
            { $0.decision = 1; $0.auth_phase = 0 },
            { $0.decision = 0 },
            { $0.decision = 0; $0.action = 3 },
            { $0.decision = 0; $0.action = 8; $0.candidate_state.recovery_phase = 4 }
        ]
        for mutation in mutations {
            var record = before
            #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
                try record.acceptCompletion(
                    stages.completion, using: stages.fixture.viewerIdentity,
                    commitProducer: corrupting(mutation)
                )
            }
            #expect(record == before)
        }
    }

    @Test func valueCopiesRemainIndependentWithNoSharedProducerOrNativeCommitLedger() throws {
        let fixture = try fixture()
        var first = fixture.host
        var copy = first
        let copyBefore = copy
        let proposal = try first.prepareProposal(using: fixture.hostIdentity)
        #expect(copy == copyBefore)
        #expect(copy.recoveryAction == .issueProposal)
        #expect(first.recoveryAction == .resend(proposal))
        let copiedProposal = try copy.prepareProposal(using: fixture.hostIdentity)
        try expectEquivalentFreshCommit(copiedProposal, proposal, signedBy: fixture.hostIdentity)
        #expect(copy.recoveryAction == .resend(copiedProposal))
        #expect(try allFieldsExceptRecovery(copy) == allFieldsExceptRecovery(first))
        var firstViewer = fixture.viewer
        var secondViewer = firstViewer
        let ack = try firstViewer.prepareAcknowledgement(after: proposal, using: fixture.viewerIdentity)
        #expect(secondViewer == fixture.viewer)
        let copiedAck = try secondViewer.prepareAcknowledgement(
            after: proposal, using: fixture.viewerIdentity
        )
        try expectEquivalentFreshCommit(copiedAck, ack, signedBy: fixture.viewerIdentity)
        #expect(firstViewer.recoveryAction == .resend(ack))
        #expect(secondViewer.recoveryAction == .resend(copiedAck))
        #expect(try allFieldsExceptRecovery(firstViewer) == allFieldsExceptRecovery(secondViewer))
    }

    @Test func producerIsCalledExactlyOnceWithNoPostEffectAcknowledgement() throws {
        let fixture = try fixture()
        let counter = CallCounter()
        let producer = counting(counter)
        var host = fixture.host
        let proposal = try host.prepareProposal(using: fixture.hostIdentity, commitProducer: producer)
        #expect(counter.value == 1)
        #expect(host.recoveryAction == .resend(proposal))
        #expect(try host.prepareProposal(
            using: fixture.hostIdentity, commitProducer: producer
        ) == proposal)
        #expect(counter.value == 2)
        var viewer = fixture.viewer
        _ = try viewer.prepareAcknowledgement(
            after: proposal, using: fixture.viewerIdentity, commitProducer: producer
        )
        #expect(counter.value == 3)
        // No provider acknowledgement, deferred callback, or stored per-record producer exists.
    }

    @Test func invalidAbiClosedDomainsReservedAndUnusedFactsRefuseExactRawSnapshot() throws {
        let before = Boundary.state(role: .viewer, pairingState: .active, recoveryPhase: .activationAcknowledgement)
        let event = Boundary.event(.acceptCompletion)
        for abi in [UInt32(0), UInt32(2), UInt32.max] {
            let output = Producer.actual.step(abi, before, event)
            #expect(Boundary.equal(output.candidate_state, before))
            #expect(output.decision == 4 && output.action == 0 && output.auth_phase == 0)
            #expect(output.reserved == 0)
        }
        var states: [Boundary.State] = []
        for field in 0..<6 {
            var invalid = before
            switch field {
            case 0: invalid.abi_version = 0
            case 1: invalid.reserved = 1
            case 2: invalid.local_role = 2
            case 3: invalid.pairing_state = 4
            case 4: invalid.recovery_phase = 5
            default: invalid.reserved_tail = 1
            }
            states.append(invalid)
        }
        for invalid in states {
            let output = Producer.actual.step(1, invalid, event)
            #expect(Boundary.equal(output.candidate_state, invalid))
            #expect(output.decision == 4 && output.action == 0 && output.auth_phase == 0)
            #expect(Boundary.accepts(before: invalid, event: event, output: output))
        }
        for field in 0..<5 {
            var invalid = event
            switch field {
            case 0: invalid.opcode = 9
            case 1: invalid.reserved = 1
            case 2: invalid.commit_id_matches = 2
            case 3: invalid.reserved_tail = 1
            default: invalid.commit_id_matches = 1 // Unused outside mark-sent.
            }
            let output = Producer.actual.step(1, before, invalid)
            #expect(Boundary.equal(output.candidate_state, before))
            #expect(output.decision == 4 && output.action == 0 && output.auth_phase == 0)
            #expect(Boundary.accepts(before: before, event: invalid, output: output))
        }
    }

    @Test func storedShapeBridgeFailureRemainsDistinctAndCannotAlterTrustworthyBytes() throws {
        let stages = try stages()
        let record = stages.viewerActive
        let encodedBefore = try remoteCanonicalData(record)
        #expect(throws: RemoteSessionCoreError.invalidPairingCommitBridge) {
            try record.validatePersistenceState(commitProducer: corrupting { $0.reserved = 1 })
        }
        #expect(record == stages.viewerActive)
        #expect(try remoteCanonicalData(record) == encodedBefore)
        try record.validatePersistenceState()
    }

    private struct Fixture {
        let hostIdentity: RemoteDeviceIdentity
        let viewerIdentity: RemoteDeviceIdentity
        let host: RemotePairedDeviceRecord
        let viewer: RemotePairedDeviceRecord
    }

    private struct Stages {
        let fixture: Fixture
        let hostProposed: RemotePairedDeviceRecord
        let viewerIssued: RemotePairedDeviceRecord
        let hostReceived: RemotePairedDeviceRecord
        let hostCompleted: RemotePairedDeviceRecord
        let viewerActive: RemotePairedDeviceRecord
        let hostActive: RemotePairedDeviceRecord
        let proposal: RemotePairingCommit
        let acknowledgement: RemotePairingCommit
        let completion: RemotePairingCommit
        let activation: RemotePairingCommit
    }

    private func fixture() throws -> Fixture {
        let hostIdentity = try RemoteDeviceIdentity(
            deviceID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            role: .host, displayName: "Synthetic Mac",
            signingPrivateKeyRawRepresentation: Data(repeating: 0x11, count: 32)
        )
        let viewerIdentity = try RemoteDeviceIdentity(
            deviceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            role: .viewer, displayName: "Synthetic Phone",
            signingPrivateKeyRawRepresentation: Data(repeating: 0x22, count: 32)
        )
        let invitation = try RemoteInvitationCode(secret: Data(0..<20))
        let host = try RemotePairingParticipant(
            identity: hostIdentity, invitation: invitation,
            ephemeralPrivateKeyRawRepresentation: Data(repeating: 0x31, count: 32),
            nonce: Data(repeating: 0x41, count: 32)
        )
        let viewer = try RemotePairingParticipant(
            identity: viewerIdentity, invitation: invitation,
            ephemeralPrivateKeyRawRepresentation: Data(repeating: 0x32, count: 32),
            nonce: Data(repeating: 0x42, count: 32)
        )
        let hostAgreement = try host.accept(viewer.hello)
        let viewerAgreement = try viewer.accept(host.hello)
        let hostRecord = try hostAgreement.makePendingRecord(
            peerConfirmation: viewerAgreement.makeConfirmation(),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let viewerRecord = try viewerAgreement.makePendingRecord(
            peerConfirmation: hostAgreement.makeConfirmation(),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        return Fixture(
            hostIdentity: hostIdentity, viewerIdentity: viewerIdentity,
            host: hostRecord, viewer: viewerRecord
        )
    }

    private func stages() throws -> Stages {
        let fixture = try fixture()
        var host = fixture.host
        var viewer = fixture.viewer
        let proposal = try host.prepareProposal(using: fixture.hostIdentity)
        let hostProposed = host
        let acknowledgement = try viewer.prepareAcknowledgement(
            after: proposal, using: fixture.viewerIdentity
        )
        let viewerIssued = viewer
        try host.acceptAcknowledgement(acknowledgement)
        let hostReceived = host
        let completion = try host.prepareCompletion(using: fixture.hostIdentity)
        let hostCompleted = host
        let activation = try viewer.acceptCompletion(completion, using: fixture.viewerIdentity)
        let viewerActive = viewer
        try host.acceptActivationAcknowledgement(activation)
        return Stages(
            fixture: fixture, hostProposed: hostProposed, viewerIssued: viewerIssued,
            hostReceived: hostReceived, hostCompleted: hostCompleted,
            viewerActive: viewerActive, hostActive: host,
            proposal: proposal, acknowledgement: acknowledgement,
            completion: completion, activation: activation
        )
    }

    private func roundTrip(_ record: RemotePairedDeviceRecord) throws -> RemotePairedDeviceRecord {
        try JSONDecoder().decode(RemotePairedDeviceRecord.self, from: JSONEncoder().encode(record))
    }

    /// Positive success oracle ONLY: omit exactly the two policy-authorized commit fields.
    /// Whole-record failure assertions above never use this projection.
    private func assertOnlyCommitFieldsChanged(
        _ record: RemotePairedDeviceRecord, from predecessor: RemotePairedDeviceRecord
    ) throws {
        #expect(record.nextOutboundReconnectSequence == predecessor.nextOutboundReconnectSequence)
        #expect(record.highestAcceptedReconnectSequence == predecessor.highestAcceptedReconnectSequence)
        #expect(try allFieldsExceptPairingStateAndRecovery(record)
            == allFieldsExceptPairingStateAndRecovery(predecessor))
    }

    private func allFieldsExceptPairingStateAndRecovery(
        _ record: RemotePairedDeviceRecord
    ) throws -> Data {
        var object = try #require(
            JSONSerialization.jsonObject(with: remoteCanonicalData(record)) as? [String: Any]
        )
        object.removeValue(forKey: "pairingState")
        object.removeValue(forKey: "recoveryCommit")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Fresh signatures may differ. Only exact cache replay demands proof-byte equality.
    private func expectEquivalentFreshCommit(
        _ actual: RemotePairingCommit,
        _ prior: RemotePairingCommit,
        signedBy identity: RemoteDeviceIdentity
    ) throws {
        #expect(try remoteCanonicalData(actual.unsigned) == remoteCanonicalData(prior.unsigned))
        #expect(actual.commitTag == prior.commitTag)
        for commit in [actual, prior] {
            let unsigned = try remoteCanonicalData(commit.unsigned)
            #expect(remoteVerifySignature(
                commit.signature,
                for: remoteDomainSeparated(
                    "AudioStreamer.Pairing.Commit.Signature.v1", unsigned, commit.commitTag
                ),
                publicKey: identity.signingPublicKey
            ))
        }
    }

    /// Used ONLY after separate fresh-cache unsigned/tag/signature assertions above.
    /// Every other encoded record field must stay exact; each own opaque cache is retained.
    private func allFieldsExceptRecovery(_ record: RemotePairedDeviceRecord) throws -> Data {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        )
        object.removeValue(forKey: "recoveryCommit")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func tamperedSignature(_ commit: RemotePairingCommit) throws -> RemotePairingCommit {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(commit)) as? [String: Any]
        )
        let encodedSignature = try #require(object["signature"] as? String)
        var signature = try #require(Data(base64Encoded: encodedSignature))
        signature[0] ^= 1
        object["signature"] = signature.base64EncodedString()
        return try JSONDecoder().decode(
            RemotePairingCommit.self, from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func encodedRecovery(_ record: RemotePairedDeviceRecord) throws -> RemotePairingCommit? {
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        )
        guard let recovery = object["recoveryCommit"] else { return nil }
        return try JSONDecoder().decode(
            RemotePairingCommit.self, from: JSONSerialization.data(withJSONObject: recovery)
        )
    }

    /// Frozen original getter, not a call to the new core/boundary/native getter.
    private func originalRecovery(
        role: RemotePeerRole, state: RemotePairingPersistenceState, cache: RemotePairingCommit?
    ) -> RemotePairingRecoveryAction {
        switch state {
        case .pending:
            if let cache { return .resend(cache) }
            return role == .host ? .issueProposal : .awaitProposal
        case .acceptedIssued: return cache.map(RemotePairingRecoveryAction.resend) ?? .awaitProposal
        case .acceptedReceived: return cache.map(RemotePairingRecoveryAction.resend) ?? .issueCompletion
        case .active: return cache.map(RemotePairingRecoveryAction.resend) ?? .none
        }
    }

    private func corrupting(_ mutate: @escaping Mutation) -> Producer {
        Producer(step: { abi, state, event in
            var output = Producer.actual.step(abi, state, event)
            mutate(&output)
            return output
        })
    }

    private func counting(_ counter: CallCounter) -> Producer {
        Producer(step: { abi, state, event in
            counter.increment()
            return Producer.actual.step(abi, state, event)
        })
    }

    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    }
}
