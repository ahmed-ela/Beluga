import Foundation
import XCTest
import BelugaCore
import WebRTCTransport
@testable import CaptureServer

/// Original-owner differential baseline, not evidence of a Rust replacement passing.
/// Each event compares every stored field, nested authority and exact return/diagnostic value.
/// The seven frozen production copies link only the pinned, PREEXISTING three subowners.
final class FrozenWorldwideScreenVideoAdaptationTraceTests: XCTestCase {
    func testFrozenInitialProfilesAllTiersCapsAndFrameRates() throws {
        let scales = [1.0, 1.25, 1.5, 2, 3, 4, 8, 12]
        let frames = [60, 45, 30, 20, 10, 5, 2, 1]
        for cap in [-1, 1, 319_999, 320_000, 500_000, 10_000_000, 50_000_000, Int.max] {
            for fps in [0, 1, 3, 10, 60, 120] {
                let pair = AdaptationTracePair(cap: cap, fps: fps)
                try pair.check("initial cap=\(cap) fps=\(fps)")
                XCTAssertEqual(pair.actual.configuredTotalRTPBitrateBps,
                               min(Int(UInt32.max), max(1, cap)))
                for tier in WorldwideScreenVideoAdaptationTier.allCases {
                    let actual = pair.actual.recommendation(for: tier)
                    let expected = pair.reference.recommendation(
                        for: FrozenWorldwideScreenVideoAdaptationTier(rawValue: tier.rawValue)!)
                    try pair.equal(actual, expected, "profile \(tier)")
                    XCTAssertEqual(actual.maximumFramesPerSecond, min(max(1, fps), frames[tier.rawValue]))
                    XCTAssertEqual(actual.scaleResolutionDownBy.bitPattern, scales[tier.rawValue].bitPattern)
                    XCTAssertGreaterThanOrEqual(actual.maximumBitrateBps, 1)
                    XCTAssertLessThanOrEqual(actual.maximumTotalRTPBitrateBps,
                                             pair.actual.configuredTotalRTPBitrateBps)
                }
            }
        }
    }

    func testFrozenPeerBindingPrecedesRejectedShowEpochAndRetainsSamePeerTombstone() throws {
        var pair = AdaptationTracePair()
        try pair.begin(peer: 1, show: 1)
        try pair.activate(peer: 1, show: 1)
        try pair.coldFloorTrial()
        let spent = pair.actual.currentRecommendation
        try pair.begin(peer: 1, show: 1)
        XCTAssertTrue(pair.actual.floorRecoveryAttemptConsumed)
        XCTAssertEqual(pair.actual.currentRecommendation, spent)
        try pair.begin(peer: 2, show: 0)
        XCTAssertEqual(pair.actual.peerGeneration, 2)
        XCTAssertFalse(pair.actual.floorRecoveryAttemptConsumed)
        XCTAssertFalse(pair.actual.startupSpatialModeIsActive)
        try pair.activate(peer: 1, show: 1)
        XCTAssertFalse(pair.actual.startupSpatialModeIsActive)
        try pair.begin(peer: 2, show: UInt64.max)
        try pair.activate(peer: 2, show: UInt64.max)
        try pair.end()
        try pair.begin(peer: 2, show: UInt64.max)
        XCTAssertFalse(pair.actual.startupSpatialModeIsActive, "A retired equal Show cannot be rearmed")
    }

    func testFrozenColdPlateauLiteralFloorAndOneUseProbeDeadline() throws {
        var pair = AdaptationTracePair()
        try pair.begin(peer: 1, show: 1)
        try pair.activate(peer: 1, show: 1)
        try pair.coldFloorTrial()
        let recommendation = pair.actual.currentRecommendation
        XCTAssertEqual(recommendation.tier, .audioPriority)
        XCTAssertEqual(recommendation.maximumTotalRTPBitrateBps, 612_000)
        XCTAssertEqual(recommendation.maximumFramesPerSecond, 1)
        XCTAssertEqual(recommendation.scaleResolutionDownBy, 12)
        XCTAssertTrue(pair.actual.floorRecoveryAttemptConsumed)
        XCTAssertEqual(pair.actual.applicationLimitedProbeDeadline,
                       pair.anchor.advanced(by: .milliseconds(5_000)))
        try pair.expire(at: .milliseconds(5_000) - attosecond)
        XCTAssertTrue(pair.actual.floorRecoveryProbeIsActive)
        try pair.expire(at: .milliseconds(5_000))
        XCTAssertFalse(pair.actual.floorRecoveryProbeIsActive)
        XCTAssertTrue(pair.actual.floorRecoveryAttemptConsumed)
        XCTAssertEqual(pair.actual.currentRecommendation.maximumFramesPerSecond, 1)
        XCTAssertEqual(pair.actual.currentRecommendation.scaleResolutionDownBy, 12)
        try pair.begin(peer: 1, show: 1)
        XCTAssertTrue(pair.actual.floorRecoveryAttemptConsumed)
    }

    func testFrozenFloorWitnessExactSignedDurationEdges() throws {
        for elapsed in [.milliseconds(500) - attosecond, .milliseconds(500),
                        .milliseconds(1_500), .milliseconds(1_500) + attosecond,
                        Duration.zero - attosecond] as [Duration] {
            var pair = AdaptationTracePair()
            try pair.begin(peer: 1, show: 1)
            try pair.activate(peer: 1, show: 1)
            try pair.firstColdWitness()
            _ = try pair.regular(at: .milliseconds(1_000) + elapsed)
            let admits = elapsed >= .milliseconds(500) && elapsed <= .milliseconds(1_500)
            XCTAssertEqual(pair.actual.floorRecoveryProbeIsActive, admits, "elapsed=\(elapsed)")
            XCTAssertEqual(pair.actual.floorRecoveryAttemptConsumed, admits)
        }
    }

    func testFrozenMissingOrderTimestampAndCachedReportsAgeWithoutAuthority() throws {
        var seed = AdaptationTracePair()
        try seed.begin(peer: 1, show: 1)
        try seed.activate(peer: 1, show: 1)
        try seed.firstColdWitness()
        for identity in 0..<6 {
            var pair = seed
            let previousSequence = pair.actual.lastConsumedCollectionSequence
            let snapshot = try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor)
            var report = pair.report(at: .milliseconds(1_500))
            switch identity {
            case 0: report.sequence = nil
            case 1: report.sequence = previousSequence
            case 2: report.timestamp = nil
            case 3: report.timestamp = 3_000_000
            case 4: report.timestamp = .nan
            default: report.timestamp = -0.0
            }
            _ = try pair.regular(report)
            XCTAssertFalse(pair.actual.floorRecoveryAttemptConsumed)
            XCTAssertFalse(pair.actual.floorRecoveryProbeIsActive)
            XCTAssertEqual(pair.actual.currentTier, .audioPriority)
            XCTAssertEqual(pair.actual.roundTripTimeObservationAge, .milliseconds(1_500))
            let after = try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor)
            XCTAssertNotEqual(snapshot, after, "Rejected reports must still age existing evidence")
        }
    }

    func testFrozenCapacityWrongPeerOrInactiveDoesNotEvenAgeExpiredOwner() throws {
        var seed = AdaptationTracePair()
        try seed.begin(peer: 1, show: 1)
        try seed.activate(peer: 1, show: 1)
        try seed.coldFloorTrial()
        for wrongPeer in [false, true] {
            var pair = seed
            let before = try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor)
            var report = pair.report(at: .seconds(20), bandwidth: 340_000)
            report.peer = wrongPeer ? 2 : 1
            report.active = wrongPeer
            XCTAssertNil(try pair.capacity(report))
            XCTAssertEqual(try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor), before)
        }
    }

    func testFrozenFailedPositiveCapacityApplyRetainsIdentityNotBudgetOrHealth() throws {
        var pair = AdaptationTracePair()
        try pair.begin(peer: 1, show: 1)
        try pair.activate(peer: 1, show: 1)
        try pair.coldFloorTrial()
        let before = pair.actual.currentRecommendation
        let deadline = pair.actual.applicationLimitedProbeDeadline
        let primarySequence = pair.actual.lastConsumedCollectionSequence
        let primaryAge = pair.actual.roundTripTimeObservationAge
        var proposed = pair
        let capacityReport = proposed.report(at: .milliseconds(1_700), bandwidth: 340_000)
        XCTAssertNotNil(try proposed.capacity(capacityReport))
        pair.actual.retainCapacityProbeObservationIdentity(from: proposed.actual)
        pair.reference.retainCapacityProbeObservationIdentity(from: proposed.reference)
        try pair.check("failed positive apply identity-only retention")
        XCTAssertEqual(pair.actual.currentRecommendation, before)
        XCTAssertEqual(pair.actual.applicationLimitedProbeDeadline, deadline)
        XCTAssertEqual(pair.actual.lastConsumedCollectionSequence, primarySequence)
        XCTAssertEqual(pair.actual.roundTripTimeObservationAge, primaryAge)
        let once = try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor)
        pair.actual.retainCapacityProbeObservationIdentity(from: proposed.actual)
        pair.reference.retainCapacityProbeObservationIdentity(from: proposed.reference)
        try pair.check("repeat identity retention")
        XCTAssertEqual(try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor), once)
    }

    func testFrozenFailedNativeApplyRetainsExactShowTerminalDisproofNotProposedTier() throws {
        var pair = AdaptationTracePair()
        try pair.begin(peer: 1, show: 1)
        try pair.activate(peer: 1, show: 1)
        XCTAssertTrue(pair.actual.startupSpatialModeIsActive)
        var proposed = pair
        _ = try proposed.regular(at: .zero, bandwidth: 100_000)
        _ = try proposed.regular(at: .milliseconds(500), bandwidth: 100_000)
        XCTAssertTrue(proposed.actual.startupSpatialModeIsDisproved)
        pair.actual.retainStartupSpatialModeTerminalState(from: proposed.actual)
        pair.reference.retainStartupSpatialModeTerminalState(from: proposed.reference)
        try pair.check("same Show terminal failure")
        XCTAssertEqual(pair.actual.currentTier, .survival)
        XCTAssertTrue(pair.actual.startupSpatialModeIsDisproved)
        XCTAssertEqual(pair.actual.currentRecommendation.scaleResolutionDownBy, 4)
        try pair.begin(peer: 1, show: 2)
        XCTAssertTrue(pair.actual.startupSpatialModeIsActive)
        let successor = try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor)
        pair.actual.retainStartupSpatialModeTerminalState(from: proposed.actual)
        pair.reference.retainStartupSpatialModeTerminalState(from: proposed.reference)
        try pair.check("predecessor cannot disprove successor Show")
        XCTAssertEqual(try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor), successor)
    }

    func testFrozenIEEEUnavailableTelemetryPreservesBitsWithoutFalseFaultAuthority() throws {
        let values: [Double?] = [nil, -0.0, 0.0, -1, Double.leastNonzeroMagnitude,
            Double.leastNormalMagnitude, 306_000, 50_000_000, Double.greatestFiniteMagnitude,
            Double(bitPattern: 0x7ff8_0000_0000_0001),
            Double(bitPattern: 0x7ff8_0000_0000_0042), .infinity, -.infinity]
        for bandwidth in values {
            for telemetry in values {
                var pair = AdaptationTracePair()
                try pair.begin(peer: 1, show: 1)
                try pair.activate(peer: 1, show: 1)
                var report = pair.report(at: .zero)
                report.bandwidth = bandwidth
                report.rtt = telemetry
                report.delay = telemetry
                _ = try pair.regular(report)
                report = pair.report(at: .milliseconds(500))
                report.bandwidth = bandwidth
                report.rtt = telemetry
                report.delay = telemetry
                _ = try pair.regular(report)
                XCTAssertFalse(pair.actual.hasNativeAdaptationPolicyFault)
                XCTAssertGreaterThanOrEqual(pair.actual.currentRecommendation.maximumFramesPerSecond, 1)
                let decision = pair.actual.automaticSuspensionDecision(
                    isCaptureActive: true, isAutomaticallySuspended: false)
                let expected = pair.reference.automaticSuspensionDecision(
                    isCaptureActive: true, isAutomaticallySuspended: false)
                try pair.equal(decision, expected, "active capture never opaque")
                XCTAssertNil(decision)
                try pair.check("unavailable IEEE event")
            }
        }
    }

    func testFrozenFullWidthCounterAndMeasurementIdentityOrdering() throws {
        var pair = AdaptationTracePair()
        try pair.begin(peer: UInt64.max, show: UInt64.max)
        try pair.activate(peer: UInt64.max, show: UInt64.max)
        for sequence in [UInt64(1) << 53, (UInt64(1) << 53) + 1, UInt64.max, UInt64.max, 0] {
            var report = pair.report(at: .milliseconds(500), bandwidth: 306_000)
            report.peer = UInt64.max
            report.sequence = sequence
            report.packets = sequence
            report.observation = .measurement(.init(
                selectedCandidatePairFingerprint: String(repeating: "a", count: 64),
                totalRoundTripTimeSeconds: 1, responsesReceived: sequence))
            _ = try pair.regular(report)
        }
        XCTAssertEqual(pair.actual.lastConsumedCollectionSequence, UInt64.max)
        try pair.invalidateRoute()
        XCTAssertEqual(pair.actual.lastConsumedCollectionSequence, UInt64.max)
        try pair.resetIncomplete()
        XCTAssertEqual(pair.actual.lastConsumedCollectionSequence, UInt64.max)
        try pair.bind(peer: UInt64.max - 1)
        XCTAssertNil(pair.actual.lastConsumedCollectionSequence)
    }

    func testFrozenHideRouteAndCadenceResetKeepPeerOwnedMeasurementTombstones() throws {
        var pair = AdaptationTracePair()
        try pair.begin(peer: 1, show: 1)
        try pair.activate(peer: 1, show: 1)
        try pair.firstColdWitness()
        let sequence = pair.actual.lastConsumedCollectionSequence
        try pair.end()
        pair.actual.invalidateRoundTripTimeObservation()
        pair.reference.invalidateRoundTripTimeObservation()
        try pair.check("Hide synchronous RTT revocation")
        XCTAssertEqual(pair.actual.roundTripTimeDisposition, .unavailable)
        XCTAssertEqual(pair.actual.lastConsumedCollectionSequence, sequence)
        try pair.resetIncomplete()
        try pair.invalidateRoute()
        XCTAssertEqual(pair.actual.lastConsumedCollectionSequence, sequence)
        try pair.begin(peer: 1, show: 2)
        try pair.activate(peer: 1, show: 2)
        var cached = pair.report(at: .milliseconds(1_500))
        cached.sequence = sequence
        XCTAssertNil(try pair.regular(cached))
        XCTAssertFalse(pair.actual.floorRecoveryAttemptConsumed)
        try pair.resetInactive()
        XCTAssertEqual(pair.actual.lastConsumedCollectionSequence, sequence)
    }

    func testFrozenRoundTripTimeLeaseExactFourSecondDurationEdges() throws {
        for elapsed in [.seconds(4) - attosecond, .seconds(4), .seconds(4) + attosecond, Duration.zero - attosecond] as [Duration] {
            var pair = AdaptationTracePair()
            try pair.firstColdWitness()
            try pair.expire(at: elapsed)
            XCTAssertEqual(pair.actual.roundTripTimeObservationAge, elapsed)
            let actual = pair.actual.automaticSuspensionDecision(
                isCaptureActive: false, isAutomaticallySuspended: true)
            let expected = pair.reference.automaticSuspensionDecision(
                isCaptureActive: false, isAutomaticallySuspended: true)
            try pair.equal(actual, expected, "four-second lease boundary")
            XCTAssertEqual(pair.actual.stableSuspensionResumeProbeSampleCount,
                           elapsed >= .zero && elapsed <= .seconds(4) ? 1 : 0)
            try pair.check("query mutates only exact existing state")
        }
    }

    func testFrozenResumeRestorationRetainsBackoffAndVisibleFloor() throws {
        var pair = AdaptationTracePair()
        try pair.begin(peer: 1, show: 1)
        try pair.activate(peer: 1, show: 1)
        try pair.coldFloorTrial()
        try pair.expire(at: .milliseconds(5_000))
        let backoff = pair.actual.applicationLimitedProbeCooldownSamplesRemaining
        XCTAssertGreaterThan(backoff, 0)
        pair.actual.automaticResumeAttemptBegan()
        pair.reference.automaticResumeAttemptBegan()
        try pair.check("accepted exact legacy resume begin")
        XCTAssertEqual(pair.actual.applicationLimitedProbeCooldownSamplesRemaining, 0)
        pair.actual.automaticResumeAttemptFailed()
        pair.reference.automaticResumeAttemptFailed()
        try pair.check("legacy resume failure restoration")
        XCTAssertEqual(pair.actual.applicationLimitedProbeCooldownSamplesRemaining, backoff)
        XCTAssertEqual(pair.actual.currentRecommendation.maximumFramesPerSecond, 1)
        pair.actual.automaticResumeAttemptBegan()
        pair.reference.automaticResumeAttemptBegan()
        pair.actual.automaticResumeAttemptSucceeded()
        pair.reference.automaticResumeAttemptSucceeded()
        try pair.check("legacy resume success restoration discarded")
    }

    func testFrozenNativeFaultRetentionIsStickyAndCannotDenySuccessorPeer() throws {
        let rtt: BelugaRustRoundTripTimeEvidence.Producer = { state, event in
            var result = beluga_core_rtt_evidence_step(state, event)
            if event.opcode == 0 { result.abi_version ^= 1 }
            return result
        }
        let tier: BelugaRustTierDemand.Producer = { facts in
            var result = beluga_core_tier_demand_project(facts)
            if facts.bandwidth_present == 1 { result.abi_version ^= 1 }
            return result
        }
        for fault in 0..<2 {
            var pair = AdaptationTracePair(rtt: fault == 0 ? rtt : nil, tier: fault == 1 ? tier : nil)
            try pair.begin(peer: 1, show: 1)
            try pair.activate(peer: 1, show: 1)
            var proposed = pair
            _ = try proposed.regular(at: .zero, bandwidth: 306_000)
            XCTAssertTrue(proposed.actual.hasNativeAdaptationPolicyFault)
            pair.actual.retainNativeAdaptationPolicyFault(from: proposed.actual)
            pair.reference.retainNativeAdaptationPolicyFault(from: proposed.reference)
            try pair.check("native rejection retained before effects")
            XCTAssertTrue(pair.actual.hasNativeAdaptationPolicyFault)
            try pair.bind(peer: 2)
            XCTAssertTrue(pair.actual.hasNativeAdaptationPolicyFault, "Same owner poison is sticky across bind")
            var clean = AdaptationTracePair()
            try clean.bind(peer: 2)
            let before = try FrozenAdaptationAllState.policy(clean.actual, anchor: clean.anchor)
            clean.actual.retainNativeAdaptationPolicyFault(from: proposed.actual)
            clean.reference.retainNativeAdaptationPolicyFault(from: proposed.reference)
            try clean.check("old peer fault cannot deny distinct successor owner")
            XCTAssertEqual(try FrozenAdaptationAllState.policy(clean.actual, anchor: clean.anchor), before)
        }
    }

    func testFrozenNativeEqualityNaNIsNotAllStateBitEqualityOrAnIntendedFieldVote() throws {
        var pair = AdaptationTracePair()
        try pair.begin(peer: 1, show: 1)
        try pair.activate(peer: 1, show: 1)
        try pair.coldFloorTrial()
        var report = pair.report(at: .milliseconds(1_700), bandwidth: 340_000)
        report.delay = Double(bitPattern: 0x7ff8_0000_0000_0042)
        _ = try pair.capacity(report)
        // Fast baseline retains the raw optional IEEE value even when growth is withheld.
        // Synthesized policy equality is numerical for this Double: NaN is non-reflexive.
        XCTAssertFalse(pair.actual == pair.actual)
        XCTAssertFalse(pair.reference == pair.reference)
        var nativeRetention = pair.actual
        var frozenRetention = pair.reference
        nativeRetention.retainNativeAdaptationPolicyFault(from: pair.actual)
        frozenRetention.retainNativeAdaptationPolicyFault(from: pair.reference)
        XCTAssertFalse(nativeRetention == pair.actual)
        XCTAssertFalse(frozenRetention == pair.reference)
        // No fault was imported, yet the original service's != revision predicate is true.
        XCTAssertEqual(try FrozenAdaptationAllState.policy(nativeRetention, anchor: pair.anchor),
                       try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor))
        try pair.equal(nativeRetention, frozenRetention, "native equality versus all-state observation")
        XCTAssertEqual(Optional(-0.0), Optional(0.0))
    }

    func testFrozenSamplingCadenceEveryPrivateFieldAndNoCatchupPermutations() throws {
        let anchor = ContinuousClock.now
        var actual = WorldwideScreenVideoSamplingCadence(startedAt: anchor)
        var expected = FrozenWorldwideScreenVideoSamplingCadence(startedAt: anchor)
        func check(_ event: String) throws {
            XCTAssertEqual(try FrozenAdaptationAllState.cadence(actual, anchor: anchor),
                           try FrozenAdaptationAllState.cadence(expected, anchor: anchor), event)
            XCTAssertEqual(actual.nextDeadline, expected.nextDeadline, event)
        }
        try check("initial")
        for enabled in [true, true, false, true] {
            actual.setCapacityProbeEnabled(enabled, at: anchor)
            expected.setCapacityProbeEnabled(enabled, at: anchor)
            try check("eligibility \(enabled)")
        }
        for elapsed in [.milliseconds(200) - attosecond, .milliseconds(200),
                        .milliseconds(500), .seconds(2), .milliseconds(2_300),
                        .milliseconds(2_500), .milliseconds(2_800), .seconds(-1)] as [Duration] {
            let now = anchor.advanced(by: elapsed)
            let slot = actual.takeDueSample(at: now)
            let frozen = expected.takeDueSample(at: now)
            XCTAssertEqual(slot.map { String(describing: $0) }, frozen.map { String(describing: $0) })
            try check("take \(elapsed)")
            if elapsed == .milliseconds(500) {
                actual.setCapacityProbeEnabled(false, at: now)
                expected.setCapacityProbeEnabled(false, at: now)
                try check("disable while in flight")
            }
            if elapsed >= .milliseconds(2_300) {
                actual.didFinishSample(at: now)
                expected.didFinishSample(at: now)
                try check("completion \(elapsed)")
            }
        }
        actual.didFinishSample(at: anchor.advanced(by: .seconds(5)))
        expected.didFinishSample(at: anchor.advanced(by: .seconds(5)))
        try check("duplicate completion advances scheduling instant but no deadline")
    }

    func testFrozenAllStateObservationRejectsHiddenFieldAndPreservesIEEEAndAttoseconds() throws {
        let anchor = ContinuousClock.now
        let values: [Double] = [-0.0, 0.0, Double(bitPattern: 0x7ff8_0000_0000_0001),
                                Double(bitPattern: 0x7ff8_0000_0000_0002)]
        let seen = try values.map { try FrozenAdaptationAllState.result($0, anchor: anchor) }
        XCTAssertEqual(Set(seen.map { $0.description }).count, 4)
        XCTAssertNotEqual(try FrozenAdaptationAllState.result(Duration.zero, anchor: anchor),
                          try FrozenAdaptationAllState.result(attosecond, anchor: anchor))
        let scalar = try FrozenAdaptationAllState.result(1.0, anchor: anchor)
        let some = try FrozenAdaptationAllState.result(Optional(1.0) as Any, anchor: anchor)
        let nestedSome = try FrozenAdaptationAllState.result(Optional(Optional(1.0)) as Any, anchor: anchor)
        let none = try FrozenAdaptationAllState.result(Optional<Double>.none as Any, anchor: anchor)
        let nestedNone = try FrozenAdaptationAllState.result(Optional(Optional<Double>.none) as Any, anchor: anchor)
        XCTAssertNotEqual(scalar, some)
        XCTAssertNotEqual(some, nestedSome)
        XCTAssertNotEqual(none, nestedNone)
        struct IncompleteState { let currentTier = 7 }
        XCTAssertThrowsError(try FrozenAdaptationAllState.policy(IncompleteState(), anchor: anchor))
        var pair = AdaptationTracePair()
        try pair.begin(peer: 1, show: 1)
        let before = try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor)
        try pair.activate(peer: 1, show: 1)
        XCTAssertNotEqual(try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor), before,
                          "Hidden visibility admission must be observable even with unchanged recommendation")
    }

    func testFrozenAttemptConsumptionCopiesOnlySameShowMonotoneFences() throws {
        var pair = AdaptationTracePair()
        try pair.begin(peer: 1, show: 1)
        try pair.activate(peer: 1, show: 1)
        try pair.firstColdWitness()
        let unappliedRecommendation = pair.actual.currentRecommendation
        let unappliedRTTAge = pair.actual.roundTripTimeObservationAge
        var proposed = pair
        _ = try proposed.regular(at: .milliseconds(1_500))
        XCTAssertTrue(proposed.actual.floorRecoveryAttemptConsumed)
        pair.actual.retainFloorRecoveryAttemptConsumption(from: proposed.actual)
        pair.reference.retainFloorRecoveryAttemptConsumption(from: proposed.reference)
        try pair.check("consume exact Show before an apply can await")
        XCTAssertTrue(pair.actual.floorRecoveryAttemptConsumed)
        XCTAssertEqual(pair.actual.currentRecommendation, unappliedRecommendation)
        XCTAssertEqual(pair.actual.roundTripTimeObservationAge, unappliedRTTAge)
        XCTAssertFalse(pair.actual.floorRecoveryProbeIsActive, "Consumption imports no speculative budget")
        _ = try pair.regular(at: .milliseconds(2_000))
        let monotone = try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor)
        pair.actual.retainFloorRecoveryAttemptConsumption(from: proposed.actual)
        pair.reference.retainFloorRecoveryAttemptConsumption(from: proposed.reference)
        try pair.check("older retained fences never regress current identity")
        XCTAssertEqual(try FrozenAdaptationAllState.policy(pair.actual, anchor: pair.anchor), monotone)
        for successorPeer in [false, true] {
            var successor = pair
            if successorPeer { try successor.bind(peer: 2) }
            else { try successor.begin(peer: 1, show: 2) }
            let before = try FrozenAdaptationAllState.policy(successor.actual, anchor: successor.anchor)
            successor.actual.retainFloorRecoveryAttemptConsumption(from: proposed.actual)
            successor.reference.retainFloorRecoveryAttemptConsumption(from: proposed.reference)
            try successor.check("predecessor cannot consume new peer or Show")
            XCTAssertEqual(try FrozenAdaptationAllState.policy(successor.actual, anchor: successor.anchor), before)
            XCTAssertFalse(successor.actual.floorRecoveryAttemptConsumed)
        }
    }

    func testFrozenStrictFallbackMissingTimestampIsNotLegacyNilObservationAuthority() throws {
        var startup = AdaptationTracePair()
        try startup.begin(peer: 1, show: 1)
        try startup.activate(peer: 1, show: 1)
        for milliseconds in [0, 500, 1_000] {
            var report = startup.report(at: .milliseconds(milliseconds), bandwidth: 50_000_000)
            report.timestamp = nil // Exact ordinary fallback shape: strict order, no native timestamp.
            _ = try startup.regular(report)
            XCTAssertEqual(startup.actual.currentTier, .survival)
            XCTAssertNil(startup.actual.roundTripTimeBaselineSeconds)
            XCTAssertEqual(startup.actual.roundTripTimeDisposition, .unavailable)
            XCTAssertFalse(startup.actual.floorRecoveryAttemptConsumed)
        }

        // Outside the speculative startup Show, missing timestamp is not a universal BWE veto.
        // It still cannot furnish the strictly native, Show-bound floor witnesses.
        var ordinaryFallback = AdaptationTracePair()
        for milliseconds in [0, 500] {
            var report = ordinaryFallback.report(at: .milliseconds(milliseconds), bandwidth: 50_000_000)
            report.timestamp = nil
            _ = try ordinaryFallback.regular(report)
        }
        XCTAssertEqual(ordinaryFallback.actual.currentTier, .full)
        XCTAssertFalse(ordinaryFallback.actual.floorRecoveryAttemptConsumed)

        var legacy = AdaptationTracePair()
        for milliseconds in [0, 500, 1_000] {
            var report = legacy.report(at: .milliseconds(milliseconds), bandwidth: 50_000_000)
            report.strict = false
            report.observation = nil
            report.rtt = nil
            report.timestamp = nil
            report.sequence = nil
            _ = try legacy.regular(report)
            XCTAssertEqual(legacy.actual.roundTripTimeDisposition, .legacy)
        }
        XCTAssertEqual(legacy.actual.currentTier, .full, "Advancing low queue may qualify legacy nil RTT")
        XCTAssertNil(legacy.actual.roundTripTimeBaselineSeconds)
        XCTAssertFalse(legacy.actual.floorRecoveryAttemptConsumed)

        var strictUnavailable = AdaptationTracePair()
        for milliseconds in [0, 500, 1_000] {
            var report = strictUnavailable.report(at: .milliseconds(milliseconds), bandwidth: 50_000_000)
            report.observation = nil
            report.rtt = nil
            report.timestamp = nil
            _ = try strictUnavailable.regular(report)
        }
        XCTAssertEqual(strictUnavailable.actual.currentTier, .survival)
        XCTAssertEqual(strictUnavailable.actual.roundTripTimeDisposition, .unavailable)
    }

    func testFrozenPromotionContinuityShrinksOnlyAndExpiresAtExactTwoSeconds() throws {
        var pair = AdaptationTracePair()
        var totalDelay = 0.0
        func legacyReport(_ elapsed: Duration, _ bandwidth: Double, _ queue: Double) -> AdaptationTraceReport {
            var report = pair.report(at: elapsed, bandwidth: bandwidth)
            totalDelay += queue * 10
            report.strict = false
            report.sequence = nil
            report.timestamp = nil
            report.route = nil
            report.rtt = 0.003
            report.observation = nil
            report.delay = totalDelay
            return report
        }
        for (index, bandwidth) in [100_000.0, 400_000, 400_000, 688_500, 1_073_000].enumerated() {
            let report = legacyReport(.milliseconds(index * 500), bandwidth, 0.001)
            _ = try pair.regular(report)
        }
        XCTAssertEqual(pair.actual.currentTier, .survival)
        XCTAssertEqual(pair.actual.currentRecommendation.maximumTotalRTPBitrateBps, 1_073_000)
        let deadline = try XCTUnwrap(pair.actual.promotionCapacityContinuity?.deadline)
        XCTAssertEqual(deadline, pair.anchor.advanced(by: .seconds(4)))
        for (milliseconds, bandwidth, cap) in [(2_500, 1_200_000.0, 1_073_000),
                                                (3_000, 980_000.0, 980_000),
                                                (3_500, 1_200_000.0, 980_000)] {
            let report = legacyReport(.milliseconds(milliseconds), bandwidth, 0.050)
            _ = try pair.regular(report)
            XCTAssertEqual(pair.actual.currentRecommendation.maximumTotalRTPBitrateBps, cap)
            XCTAssertEqual(pair.actual.promotionCapacityContinuity?.deadline, deadline)
        }
        try pair.expire(at: .seconds(4) - attosecond)
        XCTAssertEqual(pair.actual.currentRecommendation.maximumTotalRTPBitrateBps, 980_000)
        try pair.expire(at: .seconds(4))
        XCTAssertNil(pair.actual.promotionCapacityContinuity)
        XCTAssertEqual(pair.actual.currentRecommendation.maximumTotalRTPBitrateBps, 905_041)
        XCTAssertEqual(pair.actual.currentTier, .survival)
        XCTAssertEqual(pair.actual.applicationLimitedProbeFailureCount, 0)
    }

    func testFrozenSeededMixedLanesRouteABARetainAllStateBeforeAndAfterEveryEvent() throws {
        let bandwidths: [Double?] = [nil, 100_000, 306_000, 400_000, 688_500,
            1_073_000, 16_200_000, .nan, .infinity]
        for initialSeed in [UInt64(0x1357), 0xc0ffee, 0xfeedface] {
            var seed = initialSeed
            var pair = AdaptationTracePair()
            var elapsed: Duration = .zero
            var show: UInt64 = 1
            try pair.begin(peer: 1, show: show)
            try pair.activate(peer: 1, show: show)
            for index in 0..<128 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                elapsed += .milliseconds(Int((seed >> 16) % 700))
                try pair.check("seed \(initialSeed) before event \(index)")
                let operation = Int(seed % 12)
                switch operation {
                case 0...3:
                    var report = pair.report(at: elapsed, bandwidth: bandwidths[Int((seed >> 32) % UInt64(bandwidths.count))])
                    report.peer = pair.actual.peerGeneration ?? 1
                    report.route = .init(kind: index % 3 == 0 ? .relayed : .direct)
                    if index % 7 == 0 { report.sequence = pair.actual.lastConsumedCollectionSequence }
                    if index % 11 == 0 { report.observation = .unavailable; report.rtt = nil }
                    _ = try pair.regular(report)
                case 4...5:
                    var report = pair.report(at: elapsed, bandwidth: bandwidths[Int((seed >> 32) % UInt64(bandwidths.count))])
                    report.peer = pair.actual.peerGeneration ?? 1
                    report.route = .init(kind: index % 3 == 0 ? .relayed : .direct)
                    _ = try pair.capacity(report)
                case 6:
                    let now = pair.anchor.advanced(by: elapsed)
                    let actual = pair.actual.expireApplicationLimitedProbeWithoutReport(
                        peerGeneration: pair.actual.peerGeneration ?? 1, isCaptureActive: true, observedAt: now)
                    let expected = pair.reference.expireApplicationLimitedProbeWithoutReport(
                        peerGeneration: pair.reference.peerGeneration ?? 1, isCaptureActive: true, observedAt: now)
                    try pair.equal(actual, expected, "mixed no-report")
                case 7: try pair.invalidateRoute()
                case 8: try pair.resetIncomplete()
                case 9:
                    try pair.end()
                    pair.actual.invalidateRoundTripTimeObservation()
                    pair.reference.invalidateRoundTripTimeObservation()
                    show += 1
                    let peer = pair.actual.peerGeneration ?? 1
                    try pair.begin(peer: peer, show: show)
                    try pair.activate(peer: peer, show: show)
                case 10:
                    let actual = pair.actual.automaticSuspensionDecision(isCaptureActive: true, isAutomaticallySuspended: false)
                    let expected = pair.reference.automaticSuspensionDecision(isCaptureActive: true, isAutomaticallySuspended: false)
                    try pair.equal(actual, expected, "mixed active suspension query")
                    XCTAssertNil(actual)
                default:
                    try pair.bind(peer: pair.actual.peerGeneration == 1 ? 2 : 1)
                }
                try pair.check("seed \(initialSeed) after event \(index)")
                XCTAssertGreaterThanOrEqual(pair.actual.currentRecommendation.maximumFramesPerSecond, 1)
            }
        }
        var aba = AdaptationTracePair()
        try aba.begin(peer: 1, show: 1)
        try aba.activate(peer: 1, show: 1)
        try aba.coldFloorTrial()
        for (index, kind) in [WebRTCICERouteKind.direct, .relayed, .direct].enumerated() {
            var report = aba.report(at: .milliseconds(1_700 + index * 500))
            report.route = .init(kind: kind)
            report.observation = .measurement(.init(
                selectedCandidatePairFingerprint: String(repeating: index == 1 ? "b" : "a", count: 64),
                totalRoundTripTimeSeconds: 0.004, responsesReceived: 1))
            try aba.check("before explicit selected route ABA \(index)")
            _ = try aba.regular(report)
            try aba.check("after explicit selected route ABA \(index)")
            XCTAssertTrue(aba.actual.floorRecoveryAttemptConsumed, "Route ABA cannot refund the exact Show")
        }
        XCTAssertEqual(aba.actual.selectedRoute?.kind, .direct)
    }


    private var attosecond: Duration {
        Duration(secondsComponent: 0, attosecondsComponent: 1)
    }
}

private struct AdaptationTraceReport {
    var at: Duration
    var peer: UInt64 = 1
    var active = true
    var suspended = false
    var bandwidth: Double? = 306_000
    var rtt: Double? = 0.004
    var observation: WebRTCRoundTripTimeObservation? = .measurement(.init(
        selectedCandidatePairFingerprint: String(repeating: "a", count: 64),
        totalRoundTripTimeSeconds: 0.004, responsesReceived: 1))
    var sequence: UInt64?
    var strict = true
    var route: WebRTCICERouteDiagnostics? = .init(kind: .direct)
    var packets: UInt64?
    var delay: Double? = 0
    var timestamp: Double?
}

private struct AdaptationTracePair {
    let anchor: ContinuousClock.Instant
    var actual: WorldwideScreenVideoAdaptationPolicy
    var reference: FrozenWorldwideScreenVideoAdaptationPolicy
    private var sequence: UInt64 = 0
    private var packets: UInt64 = 0

    init(cap: Int = 50_000_000, fps: Int = 60,
         rtt: BelugaRustRoundTripTimeEvidence.Producer? = nil,
         tier: BelugaRustTierDemand.Producer? = nil) {
        anchor = .now
        actual = .init(configuredTotalRTPBitrateBps: cap, baseFramesPerSecond: fps,
                       roundTripTimeProducer: rtt, tierDemandProducer: tier)
        reference = .init(configuredTotalRTPBitrateBps: cap, baseFramesPerSecond: fps,
                          roundTripTimeProducer: rtt, tierDemandProducer: tier)
    }

    func check(_ event: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(actual == actual, reference == reference,
                       event + " native self-equality", file: file, line: line)
        XCTAssertEqual(try FrozenAdaptationAllState.policy(actual, anchor: anchor),
                       try FrozenAdaptationAllState.policy(reference, anchor: anchor),
                       event, file: file, line: line)
        try equal(actual.currentRecommendation, reference.currentRecommendation, event, file: file, line: line)
    }

    func equal(_ actual: Any, _ expected: Any, _ event: String,
               file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try FrozenAdaptationAllState.result(actual, anchor: anchor),
                       try FrozenAdaptationAllState.result(expected, anchor: anchor),
                       event, file: file, line: line)
    }

    mutating func report(at: Duration, bandwidth: Double? = 306_000) -> AdaptationTraceReport {
        sequence += 1
        packets += 10
        return AdaptationTraceReport(at: at, bandwidth: bandwidth, sequence: sequence,
                                     packets: packets, timestamp: 1_000_000 + Double(sequence) * 1_000_000)
    }

    @discardableResult
    mutating func regular(at: Duration, bandwidth: Double? = 306_000) throws
        -> WorldwideScreenVideoEncodingRecommendation? {
        let entry = report(at: at, bandwidth: bandwidth)
        return try regular(entry)
    }

    @discardableResult
    mutating func regular(_ report: AdaptationTraceReport) throws
        -> WorldwideScreenVideoEncodingRecommendation? {
        var actualDiagnostics: [WorldwideScreenFloorRecoveryDiagnostics] = []
        var referenceDiagnostics: [FrozenWorldwideScreenFloorRecoveryDiagnostics] = []
        let now = anchor.advanced(by: report.at)
        let got = actual.update(peerGeneration: report.peer, isCaptureActive: report.active,
            isAutomaticallySuspended: report.suspended, availableOutgoingBitrateBps: report.bandwidth,
            currentRoundTripTimeSeconds: report.rtt, roundTripTimeObservation: report.observation,
            collectionSequence: report.sequence, requireRoundTripTimeObservation: report.strict,
            selectedRoute: report.route, outboundVideoPacketsSent: report.packets,
            outboundVideoTotalPacketSendDelaySeconds: report.delay,
            nativeReportTimestampMicroseconds: report.timestamp, observedAt: now) { actualDiagnostics.append($0) }
        let expected = reference.update(peerGeneration: report.peer, isCaptureActive: report.active,
            isAutomaticallySuspended: report.suspended, availableOutgoingBitrateBps: report.bandwidth,
            currentRoundTripTimeSeconds: report.rtt, roundTripTimeObservation: report.observation,
            collectionSequence: report.sequence, requireRoundTripTimeObservation: report.strict,
            selectedRoute: report.route, outboundVideoPacketsSent: report.packets,
            outboundVideoTotalPacketSendDelaySeconds: report.delay,
            nativeReportTimestampMicroseconds: report.timestamp, observedAt: now) { referenceDiagnostics.append($0) }
        try equal(got, expected, "regular return at \(report.at)")
        try equal(actualDiagnostics, referenceDiagnostics, "regular diagnostics at \(report.at)")
        XCTAssertEqual(actualDiagnostics.count, 1)
        try check("regular state at \(report.at)")
        return got
    }

    @discardableResult
    mutating func capacity(_ report: AdaptationTraceReport) throws
        -> WorldwideScreenVideoEncodingRecommendation? {
        var actualDiagnostics: [WorldwideScreenCapacityProbeDiagnostics] = []
        var referenceDiagnostics: [FrozenWorldwideScreenCapacityProbeDiagnostics] = []
        let now = anchor.advanced(by: report.at)
        let got = actual.updateCapacityProbe(peerGeneration: report.peer, isCaptureActive: report.active,
            availableOutgoingBitrateBps: report.bandwidth, currentRoundTripTimeSeconds: report.rtt,
            roundTripTimeObservation: report.observation, collectionSequence: report.sequence,
            nativeReportTimestampMicroseconds: report.timestamp, selectedRoute: report.route,
            outboundVideoPacketsSent: report.packets, outboundVideoTotalPacketSendDelaySeconds: report.delay,
            observedAt: now) { actualDiagnostics.append($0) }
        let expected = reference.updateCapacityProbe(peerGeneration: report.peer, isCaptureActive: report.active,
            availableOutgoingBitrateBps: report.bandwidth, currentRoundTripTimeSeconds: report.rtt,
            roundTripTimeObservation: report.observation, collectionSequence: report.sequence,
            nativeReportTimestampMicroseconds: report.timestamp, selectedRoute: report.route,
            outboundVideoPacketsSent: report.packets, outboundVideoTotalPacketSendDelaySeconds: report.delay,
            observedAt: now) { referenceDiagnostics.append($0) }
        try equal(got, expected, "capacity return at \(report.at)")
        try equal(actualDiagnostics, referenceDiagnostics, "capacity diagnostics at \(report.at)")
        XCTAssertEqual(actualDiagnostics.count, 1)
        try check("capacity state at \(report.at)")
        return got
    }

    mutating func bind(peer: UInt64) throws {
        XCTAssertEqual(actual.bind(toPeerGeneration: peer), reference.bind(toPeerGeneration: peer))
        try check("bind peer \(peer)")
    }
    mutating func begin(peer: UInt64, show: UInt64) throws {
        actual.beginFloorRecoveryVisibility(peerGeneration: peer, showEpoch: show)
        reference.beginFloorRecoveryVisibility(peerGeneration: peer, showEpoch: show)
        try check("reserve peer \(peer) Show \(show)")
    }
    mutating func activate(peer: UInt64, show: UInt64) throws {
        actual.activateFloorRecoveryVisibility(peerGeneration: peer, showEpoch: show)
        reference.activateFloorRecoveryVisibility(peerGeneration: peer, showEpoch: show)
        try check("activate peer \(peer) Show \(show)")
    }
    mutating func end() throws {
        actual.endFloorRecoveryVisibility()
        reference.endFloorRecoveryVisibility()
        try check("end visibility")
    }
    mutating func invalidateRoute() throws {
        actual.invalidateSelectedRoute()
        reference.invalidateSelectedRoute()
        try check("invalidate route")
    }
    mutating func resetIncomplete() throws {
        actual.resetIncompleteEvidenceWindow()
        reference.resetIncompleteEvidenceWindow()
        try check("reset incomplete window")
    }
    mutating func resetInactive() throws {
        actual.resetForInactiveCapture()
        reference.resetForInactiveCapture()
        try check("reset inactive capture")
    }
    mutating func expire(at elapsed: Duration) throws {
        let now = anchor.advanced(by: elapsed)
        let got = actual.expireApplicationLimitedProbeWithoutReport(peerGeneration: 1,
            isCaptureActive: true, observedAt: now)
        let expected = reference.expireApplicationLimitedProbeWithoutReport(peerGeneration: 1,
            isCaptureActive: true, observedAt: now)
        try equal(got, expected, "expiry at \(elapsed)")
        try check("expiry state at \(elapsed)")
    }
    mutating func firstColdWitness() throws {
        for milliseconds in [0, 500, 1_000] {
            _ = try regular(at: .milliseconds(milliseconds))
        }
        XCTAssertEqual(actual.currentTier, .audioPriority)
        XCTAssertEqual(actual.currentRecommendation.maximumTotalRTPBitrateBps, 486_001)
        XCTAssertFalse(actual.floorRecoveryAttemptConsumed)
    }
    mutating func coldFloorTrial() throws {
        try firstColdWitness()
        _ = try regular(at: .milliseconds(1_500))
        XCTAssertTrue(actual.floorRecoveryProbeIsActive)
    }
}
