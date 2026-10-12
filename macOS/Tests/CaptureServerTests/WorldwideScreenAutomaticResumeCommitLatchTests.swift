import Foundation
import XCTest
@testable import CaptureServer

final class WorldwideScreenAutomaticResumeCommitLatchTests: XCTestCase {
    func testCommittedAcknowledgementAtomicallyWinsConcurrentCleanup() {
        let latch = WorldwideScreenAutomaticResumeCommitLatch()
        let operationStarted = DispatchSemaphore(value: 0)
        let releaseOperation = DispatchSemaphore(value: 0)
        let commitFinished = DispatchSemaphore(value: 0)
        let cleanupStarted = DispatchSemaphore(value: 0)
        let cleanupFinished = DispatchSemaphore(value: 0)
        let commitFailed = LockedTestValue(false)
        let cleanupClaimedFailure = LockedTestValue<Bool?>(nil)

        DispatchQueue.global(qos: .userInitiated).async {
            defer { commitFinished.signal() }
            do {
                try latch.commit {
                    operationStarted.signal()
                    _ = releaseOperation.wait(timeout: .now() + 2)
                }
            } catch {
                commitFailed.set(true)
            }
        }
        XCTAssertEqual(operationStarted.wait(timeout: .now() + 1), .success)

        DispatchQueue.global(qos: .userInitiated).async {
            cleanupStarted.signal()
            cleanupClaimedFailure.set(latch.claimFailure())
            cleanupFinished.signal()
        }
        XCTAssertEqual(cleanupStarted.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(cleanupFinished.wait(timeout: .now() + 0.05), .timedOut)

        releaseOperation.signal()
        XCTAssertEqual(commitFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(cleanupFinished.wait(timeout: .now() + 1), .success)
        XCTAssertFalse(commitFailed.get())
        XCTAssertEqual(cleanupClaimedFailure.get(), false)
        XCTAssertTrue(latch.isCommitted)
    }

    func testCleanupClaimAtomicallyPreventsIrreversibleAcknowledgement() {
        let latch = WorldwideScreenAutomaticResumeCommitLatch()
        var operationWasInvoked = false

        XCTAssertTrue(latch.claimFailure())
        XCTAssertThrowsError(
            try latch.commit {
                operationWasInvoked = true
            }
        )
        XCTAssertFalse(operationWasInvoked)
        XCTAssertFalse(latch.isCommitted)
        XCTAssertFalse(latch.claimFailure())
    }

    func testServiceResetClaimsLatchBeforePolicyClassificationAndContextClear() throws {
        let source = try serviceSource()
        let start = try XCTUnwrap(
            source.range(
                of: "    private func resetAutomaticScreenMediaSuspensionState() {"
            )?.upperBound
        )
        let end = try XCTUnwrap(
            source.range(
                of: "    private func retireAutomaticScreenMediaResumeNativeContext()",
                range: start..<source.endIndex
            )?.lowerBound
        )
        let helperEnd = try XCTUnwrap(source.range(
            of: "    private func resetScreenClientDiagnosticsFreshness()",
            range: end..<source.endIndex
        )?.lowerBound)
        let method = sourceTokens(String(source[start..<end]))
        let helper = sourceTokens(String(source[end..<helperEnd]))
        let claim = try XCTUnwrap(
            method.range(of: "context.finalAcknowledgementCommit.claimFailure()")
        )
        let failed = try XCTUnwrap(
            method.range(of: policyTransactionTokens("automaticResumeAttemptFailed()"))
        )
        let succeeded = try XCTUnwrap(
            method.range(of: policyTransactionTokens("automaticResumeAttemptSucceeded()"))
        )
        let failedRevisionPublication = try XCTUnwrap(
            method.range(
                of: ownerPublicationTokens(revision: "screenVideoAdaptationPolicyRevision &+ 1"),
                range: failed.upperBound..<succeeded.lowerBound
            )
        )
        let succeededEpoch = try XCTUnwrap(
            method.range(of: "beginPostResumeScreenVideoAdaptationEpoch()",
                range: succeeded.upperBound..<method.endIndex)
        )
        let contextRetirement = try XCTUnwrap(
            method.range(of: "retireAutomaticScreenMediaResumeNativeContext()")
        )

        XCTAssertLessThan(claim.lowerBound, failed.lowerBound)
        XCTAssertLessThan(claim.lowerBound, succeeded.lowerBound)
        XCTAssertLessThan(failed.upperBound, failedRevisionPublication.lowerBound)
        XCTAssertLessThan(failedRevisionPublication.upperBound, contextRetirement.lowerBound)
        XCTAssertLessThan(succeeded.upperBound, succeededEpoch.lowerBound)
        XCTAssertLessThan(succeededEpoch.upperBound, contextRetirement.lowerBound)
        XCTAssertLessThan(failed.lowerBound, contextRetirement.lowerBound)
        XCTAssertLessThan(succeeded.lowerBound, contextRetirement.lowerBound)
        XCTAssertFalse(method.contains("finalAcknowledgementCommit.isCommitted"))
        XCTAssertTrue(resetRetirementIsValid(method, helper: helper))
        for statement in [
            "automaticScreenMediaResumeContext?.probeAuthorization?.revoke()",
            "automaticScreenMediaResumeContext?.forwardingAuthorization?.revoke()",
            "automaticScreenMediaResumeContext = nil", "screenMediaSuspension.retire()",
        ] {
            XCTAssertFalse(resetRetirementIsValid(method,
                helper: helper.replacingOccurrences(of: statement, with: "")), statement)
        }
        for extra in ["screenVideoAdaptationOwner = foreignOwner",
                      "beginPostResumeScreenVideoAdaptationEpoch()", "await stop()"] {
            XCTAssertFalse(resetRetirementIsValid(method, helper: helper + " " + extra))
        }
        let call = "retireAutomaticScreenMediaResumeNativeContext()"
        XCTAssertFalse(resetRetirementIsValid(method.replacingOccurrences(of: call, with: ""), helper: helper))
        XCTAssertFalse(resetRetirementIsValid(call + " " + method.replacingOccurrences(of: call, with: ""), helper: helper))
        XCTAssertFalse(resetRetirementIsValid(method + " " + call, helper: helper))
    }


    func testPolicyTransactionNeedleRejectsMissingOrReorderedOwnerPublication() throws {
        let copy = "var updatedPolicy = screenVideoAdaptationPolicy"
        let mutation = "updatedPolicy.automaticResumeAttemptSucceeded()"
        let publication = sourceTokens("""
        screenVideoAdaptationOwner = .init(policy: updatedPolicy,
            revision: screenVideoAdaptationPolicyRevision,
            fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane,
            evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence,
            applied: appliedScreenVideoRecommendation)
        """)
        let needle = policyTransactionTokens("automaticResumeAttemptSucceeded()")
        XCTAssertNotNil(sourceTokens(copy + " " + mutation + " " + publication).range(of: needle))
        XCTAssertNil(sourceTokens(copy + " " + mutation).range(of: needle))
        XCTAssertNil(sourceTokens(publication + " " + copy + " " + mutation).range(of: needle))

        let source = try serviceSource()
        let start = try XCTUnwrap(source.range(
            of: "    private func handleAutomaticScreenMediaResumeRequest("
        )?.lowerBound)
        let end = try XCTUnwrap(source.range(
            of: "    // MARK: - Screen control protocol",
            range: start..<source.endIndex
        )?.lowerBound)
        XCTAssertTrue(postAcknowledgementOrderingIsValid(String(source[start..<end])))

        // Source-order controls only, not an execution of the actor's ACK schedule.
        let ack = "try await sourcePeer.acknowledgeScreenMediaResumedIfTransportHealthy( )"
        let transportCatch = postAcknowledgementTransportCatchTokens()
        let guardTokens = postAcknowledgementOwnershipTokens()
        let revision = ownerPublicationTokens(revision: "screenVideoAdaptationPolicyRevision &+ 1")
        let writes = "do { " + needle + " } " + revision
        let recommendation = "let recommendation = screenVideoAdaptationPolicy.currentRecommendation"
        let valid = [ack, transportCatch, guardTokens, writes, recommendation].joined(separator: " ")
        XCTAssertTrue(postAcknowledgementOrderingIsValid(valid))
        let invalid = [
            [ack, writes, transportCatch, guardTokens, recommendation].joined(separator: " "),
            [ack, revision, transportCatch, guardTokens, "do { " + needle + " }", recommendation].joined(separator: " "),
            valid.replacingOccurrences(of: guardTokens, with: ""),
            [ack, transportCatch, writes, guardTokens, recommendation].joined(separator: " "),
            valid.replacingOccurrences(of: "var updatedPolicy = screenVideoAdaptationPolicy", with: "var updatedPolicy = preAckOwner.policy"),
            valid.replacingOccurrences(of: "lane: screenVideoAdaptationOwner.lane", with: "lane: preAckOwner.lane"),
            valid.replacingOccurrences(of: " } " + revision, with: " }"),
            [ack, transportCatch, guardTokens, revision, "do { " + needle + " }", recommendation].joined(separator: " "),
        ]
        for mutant in invalid {
            XCTAssertFalse(postAcknowledgementOrderingIsValid(mutant))
        }
        for clause in [
            "!isStopped,", "currentPeer === sourcePeer,",
            "peerGeneration == sourcePeerGeneration,",
            "context.binding.peerGeneration == sourcePeerGeneration,",
            "screenVisibilityCommandEpoch == context.binding.visibilityCommandEpoch,",
            "recoveryProofEpoch == context.binding.recoveryEpoch,",
            "activeScreenRequestID == context.notice.screenRequestID,",
            "currentSink === sink,", "currentForwarding === forwardingAuthorization,",
            "completed.attemptID == context.attemptID,", "completed.binding == context.binding,",
            "completed.notice == context.notice,",
            "completed.finalAcknowledgementCommit === context.finalAcknowledgementCommit,",
            "completed.finalAcknowledgementCommit.isCommitted,",
            "completedBoundary == boundary,", "completed.markerReady == context.markerReady,",
            "completed.markerPresentation == context.markerPresentation,",
            "completedProbe === probeAuthorization,",
            "completedForwarding === forwardingAuthorization,",
        ] {
            XCTAssertFalse(postAcknowledgementOrderingIsValid(
                valid.replacingOccurrences(of: clause, with: "")
            ), clause)
        }
        // These health gates would reject expected probe revocation or a legitimate display
        // transition. Original committed identity, not a frozen pre-ACK tuple, admits success.
        for healthGate in ["probeAuthorization.isValid", "forwardingAuthorization.isValid",
                           "sink.allowsActiveUse(authorizedBy: forwardingAuthorization)"] {
            XCTAssertFalse(guardTokens.contains(healthGate))
        }

        // Additive source-shape controls; the production ACK handler is still unwired.
        let codec = try codecSource()
        XCTAssertTrue(committedResumeSeamIsValid(service: source, codec: codec))
        for (old, replacement) in [
            ("allNetworkAdaptationOwnerWritersAreEnrolled = false", "allNetworkAdaptationOwnerWritersAreEnrolled = true"),
            ("ownedStopPublicationIsEnrolled = false", "ownedStopPublicationIsEnrolled = true"),
            ("Self.allNetworkAdaptationOwnerWritersAreEnrolled,", ""),
            ("Self.ownedStopPublicationIsEnrolled,", ""),
            ("current.ownerCompletionEntryID == nil", "true"),
            ("completed.ownerCompletionEntryID == ObjectIdentifier(entry),", ""),
            ("automaticScreenMediaResumeContext?.ownerCompletionClaim = .refused", ""),
            ("claim == .unclaimed || claim == .admitted", "true"),
            ("let fresh = entry.phase == .fresh\n        entry.phase = .retired", "let fresh = entry.phase == .fresh"),
            ("key == [108, 0, 0, 0, 0]", "key == [107, 0, 0, 0, 0]"),
            ("automaticScreenMediaResumeContext?.ownerCompletionClaim = .terminalClaimed", ""),
            ("return beginStop()", "return nil"),
            ("networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry),", ""),
            ("cancelAutomaticScreenMediaResumeTimeout()\n        retireAutomaticScreenMediaResumeNativeContext()", "retireAutomaticScreenMediaResumeNativeContext()\n        cancelAutomaticScreenMediaResumeTimeout()"),
            ("entry.phase = .published", "entry.phase = .retired"),
            ("await finishStop(consume plan)", "return"),
            ("case .superseded:\n                guard networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry) else { return false }", "case .superseded: return false"),
            ("case .superseded:\n                guard networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry) else { return false }", "case .superseded: await stopAfterCommittedResumeRefusal(entry); return false"),
            ("screenVideoAdaptationOwner = packet.replacement.value", "screenVideoAdaptationOwner = packet.replacement.value; callback()"),
        ] {
            XCTAssertFalse(committedResumeSeamIsValid(
                service: source.replacingOccurrences(of: old, with: replacement), codec: codec), old)
        }
        let witnessStart = try XCTUnwrap(source.range(of:
            "    private func networkAdaptationCommittedResumeNativeWitnessIsCurrent(")?.lowerBound)
        let witnessEnd = try XCTUnwrap(source.range(of:
            "    func networkAdaptationCommittedResumeAdmit(",
            range: witnessStart..<source.endIndex)?.lowerBound)
        for gate in ["              peerGeneration == entry.generation,\n",
                     "              entry.binding.peerGeneration == entry.generation,\n"] {
            XCTAssertNotNil(source.range(of: gate, range: witnessStart..<witnessEnd), gate)
            for replacement in ["", gate + gate] {
                XCTAssertFalse(committedResumeSeamIsValid(service: source.replacingOccurrences(
                    of: gate, with: replacement, range: witnessStart..<witnessEnd), codec: codec), gate)
            }
        }
        for (start, end) in [
            ("    func networkAdaptationCommittedResumeAdmit(", "    func networkAdaptationCommittedResumeIsCurrent("),
            ("    private func claimCommittedResumeRefusalStop(", "    private func stopAfterCommittedResumeRefusal("),
        ] {
            let lower = try XCTUnwrap(source.range(of: start)?.lowerBound)
            let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
            for clause in ["Self.allNetworkAdaptationOwnerWritersAreEnrolled,",
                           "Self.ownedStopPublicationIsEnrolled,",
                           "networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry),"] {
                XCTAssertFalse(committedResumeSeamIsValid(service: source.replacingOccurrences(
                    of: clause, with: "", range: lower..<upper), codec: codec), start + clause)
            }
        }
        for (old, replacement) in [
            ("defer { owner.networkAdaptationCommittedResumeRetire(entry) }", ""),
            ("let result = try withGuard { scope in", "let result = try withGuard { scope in defer { owner.networkAdaptationCommittedResumeRetire(entry) }"),
            (".zeroClock(.resumeAndAdvance)", ".zeroClock(.resumeFailureWithoutRevision)"),
            ("retainingAnchor: anchor", "retainingAnchor: nil"),
            ("owner.networkAdaptationCommittedResumeCommit(.init(entry: entry,", "callback(); owner.networkAdaptationCommittedResumeCommit(.init(entry: entry,"),
        ] {
            XCTAssertFalse(committedResumeSeamIsValid(service: source,
                codec: codec.replacingOccurrences(of: old, with: replacement)), old)
        }
    }

    func testPolicyTransactionNeedleRejectsDroppedOrForeignUntouchedOwnerFields() {
        let source = sourceTokens("""
        var updatedPolicy = screenVideoAdaptationPolicy
        updatedPolicy.automaticResumeAttemptSucceeded()
        screenVideoAdaptationOwner = .init(policy: updatedPolicy,
            revision: screenVideoAdaptationPolicyRevision,
            fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,
            lane: screenVideoAdaptationOwner.lane,
            evidenceTime: screenVideoAdaptationLastEvidenceTime,
            minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence,
            applied: appliedScreenVideoRecommendation)
        """)
        let needle = policyTransactionTokens("automaticResumeAttemptSucceeded()")
        XCTAssertNotNil(source.range(of: needle))
        for field in [
            "policy: updatedPolicy,", "revision: screenVideoAdaptationPolicyRevision,",
            "fastStatisticsAvailable: screenVideoAdaptationFastStatisticsAreAvailable,",
            "lane: screenVideoAdaptationOwner.lane,",
            "evidenceTime: screenVideoAdaptationLastEvidenceTime,",
            "minimumCollectionSequence: screenVideoAdaptationOwner.minimumCollectionSequence,",
            "applied: appliedScreenVideoRecommendation",
        ] {
            XCTAssertNil(source.replacingOccurrences(of: field, with: "").range(of: needle), field)
            XCTAssertNil(source.replacingOccurrences(of: field, with: field + "Foreign").range(of: needle), field)
        }
    }

    private func sourceTokens(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func resetRetirementIsValid(_ reset: String, helper: String) -> Bool {
        guard helper == sourceTokens("""
            private func retireAutomaticScreenMediaResumeNativeContext() {
                automaticScreenMediaResumeContext?.probeAuthorization?.revoke()
                automaticScreenMediaResumeContext?.forwardingAuthorization?.revoke()
                automaticScreenMediaResumeContext = nil
                screenMediaSuspension.retire()
            }
            """),
            reset.components(separatedBy: "retireAutomaticScreenMediaResumeNativeContext()").count == 2,
            let call = reset.range(of: "retireAutomaticScreenMediaResumeNativeContext()"),
            let claim = reset.range(of: "context.finalAcknowledgementCommit.claimFailure()"),
            let failed = reset.range(of: policyTransactionTokens("automaticResumeAttemptFailed()")),
            let succeeded = reset.range(of: policyTransactionTokens("automaticResumeAttemptSucceeded()")),
            let epoch = reset.range(of: "beginPostResumeScreenVideoAdaptationEpoch()"),
            claim.upperBound < failed.lowerBound,
            failed.upperBound < succeeded.lowerBound,
            succeeded.upperBound < epoch.lowerBound,
            epoch.upperBound < call.lowerBound else { return false }
        return !reset.contains("automaticScreenMediaResumeContext = nil")
    }

    private func committedResumeSeamIsValid(service: String, codec: String) -> Bool {
        func slice(_ text: String, _ start: String, _ end: String) -> String? {
            guard let a = text.range(of: start),
                  let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return nil }
            return sourceTokens(String(text[a.lowerBound..<b.lowerBound]))
        }
        guard service.contains("private static let allNetworkAdaptationOwnerWritersAreEnrolled = false"),
              service.contains("private static let ownedStopPublicationIsEnrolled = false"),
              let factory = slice(service, "    private func networkAdaptationCommittedResumeEntry(",
                  "    private func networkAdaptationCommittedResumeNativeWitnessIsCurrent("),
              let witness = slice(service, "    private func networkAdaptationCommittedResumeNativeWitnessIsCurrent(",
                  "    func networkAdaptationCommittedResumeAdmit("),
              let admit = slice(service, "    func networkAdaptationCommittedResumeAdmit(",
                  "    func networkAdaptationCommittedResumeIsCurrent("),
              let commit = slice(service, "    func networkAdaptationCommittedResumeCommit(",
                  "    private func claimCommittedResumeRefusalStop("),
              let retirement = slice(service, "    func networkAdaptationCommittedResumeRetire(",
                  "    func networkAdaptationCommittedResumeCommit("),
              let refusal = slice(service, "    private func claimCommittedResumeRefusalStop(",
                  "    private func stopAfterCommittedResumeRefusal("),
              let stop = slice(service, "    private func stopAfterCommittedResumeRefusal(",
                  "    private func publishCommittedResumeOwner("),
              let caller = slice(service, "    private func publishCommittedResumeOwner(", "private extension NSLock"),
              let adapter = slice(codec, "    func publishCommittedResume(", "    func publishActualStop("),
              factory.contains("guard Self.allNetworkAdaptationOwnerWritersAreEnrolled, Self.ownedStopPublicationIsEnrolled,"),
              factory.contains("current.ownerCompletionClaim == .unclaimed, current.ownerCompletionEntryID == nil"),
              factory.contains("automaticScreenMediaResumeContext?.ownerCompletionEntryID = ObjectIdentifier(entry) return entry"),
              factory.contains("owner: self, boundary: screenVideoAdaptationOwnerBoundary"),
              admit == sourceTokens("""
                func networkAdaptationCommittedResumeAdmit(_ entry: BelugaNetworkAdaptationCommittedResumeEntry,
                    boundary: BelugaNetworkAdaptationOwnerBoundary, key: [UInt64]) -> Bool {
                    let fresh = entry.phase == .fresh
                    entry.phase = .retired
                    guard fresh, Self.allNetworkAdaptationOwnerWritersAreEnrolled,
                          Self.ownedStopPublicationIsEnrolled,
                          entry.boundary === boundary, key == [108, 0, 0, 0, 0],
                          networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry),
                          automaticScreenMediaResumeContext?.ownerCompletionClaim == .unclaimed else { return false }
                    automaticScreenMediaResumeContext?.ownerCompletionClaim = .admitted
                    entry.phase = .admitted
                    return true
                }
                """),
              commit == sourceTokens("""
                func networkAdaptationCommittedResumeCommit(_ packet: BelugaNetworkAdaptationCommittedResumeCommit) {
                    packet.entry.phase = .published
                    automaticScreenMediaResumeContext?.ownerCompletionClaim = .published
                    screenVideoAdaptationOwner = packet.replacement.value
                }
                """),
              stop.contains("guard let plan = claimCommittedResumeRefusalStop(entry) else { return } await finishStop(consume plan)"),
              refusal == sourceTokens("""
                private func claimCommittedResumeRefusalStop(
                    _ entry: BelugaNetworkAdaptationCommittedResumeEntry
                ) -> ServiceStopPlan? {
                    guard Self.allNetworkAdaptationOwnerWritersAreEnrolled,
                          Self.ownedStopPublicationIsEnrolled,
                          networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry),
                          let claim = automaticScreenMediaResumeContext?.ownerCompletionClaim,
                          claim != .published, claim != .terminalClaimed else { return nil }
                    automaticScreenMediaResumeContext?.ownerCompletionClaim = .terminalClaimed
                    entry.phase = .retired
                    cancelAutomaticScreenMediaResumeTimeout()
                    retireAutomaticScreenMediaResumeNativeContext()
                    return beginStop()
                }
                """),
              caller.contains("switch try screenVideoAdaptationOwnerBoundary.publishCommittedResume(entry, on: self)"),
              caller.contains("case .accepted: return true case .superseded: guard networkAdaptationCommittedResumeNativeWitnessIsCurrent(entry) else { return false } case .refused: break"),
              caller.contains("await stopAfterCommittedResumeRefusal(entry) return false"),
              adapter.contains("defer { owner.networkAdaptationCommittedResumeRetire(entry) } let result = try withGuard { scope in let prepared = try preparePublicationHeld(event: .zeroClock(.resumeAndAdvance), scope: scope)"),
              adapter.contains("owner.networkAdaptationCommittedResumeCapture(entry, retainingAnchor: anchor)"),
              adapter.contains("guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry } owner.networkAdaptationCommittedResumeCommit(.init(entry: entry,"),
              !caller.contains("try?"), !factory.contains("screenVideoAdaptationOwner,"),
              retirement.contains("guard entry.phase != .published else { return } entry.phase = .retired"),
              retirement.contains("completed.ownerCompletionEntryID == ObjectIdentifier(entry),"),
              retirement.contains("completed.finalAcknowledgementCommit === entry.latch,"),
              retirement.contains("claim == .unclaimed || claim == .admitted else { return } automaticScreenMediaResumeContext?.ownerCompletionClaim = .refused }"),
              !retirement.contains("networkAdaptationCommittedResumeNativeWitnessIsCurrent("),
              !retirement.contains(".isCommitted"), !retirement.contains("screenMediaSuspension."),
              !retirement.contains("await "),
              !witness.contains(".isValid"), !witness.contains("allowsActiveUse"),
              !witness.contains("screenVideoAdaptationPolicyRevision") else { return false }
        for clause in [
            "entry.owner === self,", "entry.boundary === screenVideoAdaptationOwnerBoundary,",
            // The leading token boundary distinguishes actor generation from
            // entry.binding.peerGeneration; each independent gate occurs once.
            "!isStopped,", "currentPeer === entry.sourcePeer,", " peerGeneration == entry.generation,",
            "entry.binding.peerGeneration == entry.generation,",
            "screenVisibilityCommandEpoch == entry.binding.visibilityCommandEpoch,",
            "recoveryProofEpoch == entry.binding.recoveryEpoch,",
            "activeScreenRequestID == entry.notice.screenRequestID,", "currentSink === entry.sink,",
            "currentForwarding === entry.forwardingAuthorization,",
            "completed.ownerCompletionEntryID == ObjectIdentifier(entry),",
            "completed.attemptID == entry.attemptID,", "completed.binding == entry.binding,",
            "completed.notice == entry.notice,", "completed.finalAcknowledgementCommit === entry.latch,",
            "completed.finalAcknowledgementCommit.isCommitted,",
            "completedBoundary == entry.markerBoundary,", "completed.markerReady == entry.markerReady,",
            "completed.markerPresentation == entry.markerPresentation,",
            "completedProbe === entry.probeAuthorization,",
            "completedForwarding === entry.forwardingAuthorization,",
            "screenMediaSuspension.owns(entry.binding)",
        ] {
            guard witness.components(separatedBy: clause).count == 2 else { return false }
        }
        return true
    }

    private func postAcknowledgementOrderingIsValid(_ handler: String) -> Bool {
        let tokens = sourceTokens(handler)
        let ack = "try await sourcePeer.acknowledgeScreenMediaResumedIfTransportHealthy("
        let transportCatch = postAcknowledgementTransportCatchTokens()
        let ownership = postAcknowledgementOwnershipTokens()
        let writes = "do { " + policyTransactionTokens("automaticResumeAttemptSucceeded()")
            + " } " + ownerPublicationTokens(revision: "screenVideoAdaptationPolicyRevision &+ 1")
        let recommendation = "let recommendation = screenVideoAdaptationPolicy.currentRecommendation"
        guard [ack, transportCatch, ownership, writes, recommendation].allSatisfy({
            tokens.components(separatedBy: $0).count == 2
        }), let ackRange = tokens.range(of: ack),
            let catchRange = tokens.range(of: transportCatch),
            let ownershipRange = tokens.range(of: ownership),
            let writesRange = tokens.range(of: writes),
            let recommendationRange = tokens.range(of: recommendation),
            ackRange.upperBound < catchRange.lowerBound,
            catchRange.upperBound < ownershipRange.lowerBound,
            ownershipRange.upperBound < writesRange.lowerBound,
            writesRange.upperBound < recommendationRange.lowerBound else { return false }
        let beforeAdmission = tokens[ackRange.lowerBound..<ownershipRange.lowerBound]
        let throughRecommendation = tokens[ackRange.lowerBound..<recommendationRange.lowerBound]
        return !beforeAdmission.contains("screenVideoAdaptationOwner =")
            && throughRecommendation.components(separatedBy: "screenVideoAdaptationOwner =").count == 3
    }

    private func postAcknowledgementTransportCatchTokens() -> String {
        sourceTokens(#"""
        } catch {
            await failAutomaticScreenMediaResume(
                peer: sourcePeer,
                attemptID: context.attemptID,
                reason: "resume finalization failed: \(error.localizedDescription)"
            )
            return
        }
        """#)
    }

    private func postAcknowledgementOwnershipTokens() -> String {
        sourceTokens("""
        guard !isStopped,
              let currentPeer = peer,
              currentPeer === sourcePeer,
              peerGeneration == sourcePeerGeneration,
              context.binding.peerGeneration == sourcePeerGeneration,
              screenVisibilityCommandEpoch == context.binding.visibilityCommandEpoch,
              recoveryProofEpoch == context.binding.recoveryEpoch,
              let activeScreenRequestID = screenMediaSuspension.activeScreenRequestID,
              activeScreenRequestID == context.notice.screenRequestID,
              let currentSink = captureSink,
              currentSink === sink,
              let currentForwarding = captureForwardingAuthorization,
              currentForwarding === forwardingAuthorization,
              let completed = automaticScreenMediaResumeContext,
              completed.attemptID == context.attemptID,
              completed.binding == context.binding,
              completed.notice == context.notice,
              completed.finalAcknowledgementCommit === context.finalAcknowledgementCommit,
              completed.finalAcknowledgementCommit.isCommitted,
              let completedBoundary = completed.boundary,
              completedBoundary == boundary,
              completed.markerReady == context.markerReady,
              completed.markerPresentation == context.markerPresentation,
              let completedProbe = completed.probeAuthorization,
              completedProbe === probeAuthorization,
              let completedForwarding = completed.forwardingAuthorization,
              completedForwarding === forwardingAuthorization,
              screenMediaSuspension.owns(context.binding) else {
            return
        }
        """)
    }

    private func ownerPublicationTokens(
        policy: String = "screenVideoAdaptationPolicy",
        revision: String = "screenVideoAdaptationPolicyRevision",
        fast: String = "screenVideoAdaptationFastStatisticsAreAvailable",
        lane: String = "screenVideoAdaptationOwner.lane",
        evidence: String = "screenVideoAdaptationLastEvidenceTime",
        minimum: String = "screenVideoAdaptationOwner.minimumCollectionSequence",
        applied: String = "appliedScreenVideoRecommendation"
    ) -> String {
        sourceTokens("""
        screenVideoAdaptationOwner = .init(policy: \(policy),
            revision: \(revision), fastStatisticsAvailable: \(fast),
            lane: \(lane), evidenceTime: \(evidence),
            minimumCollectionSequence: \(minimum), applied: \(applied))
        """)
    }

    private func policyTransactionTokens(_ mutation: String) -> String {
        sourceTokens("var updatedPolicy = screenVideoAdaptationPolicy updatedPolicy.\(mutation)")
            + " " + ownerPublicationTokens(policy: "updatedPolicy")
    }

    private func serviceSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "macOS/Sources/CaptureServer/WorldwideScreenService.swift"
            ),
            encoding: .utf8
        )
    }

    private func codecSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/BelugaNetworkAdaptationOwnerCodec.swift"), encoding: .utf8)
    }
}

private final class LockedTestValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ value: Value) {
        lock.withLock {
            self.value = value
        }
    }

    func get() -> Value {
        lock.withLock { value }
    }
}
