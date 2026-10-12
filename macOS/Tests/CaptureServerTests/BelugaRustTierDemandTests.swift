import Foundation
import XCTest
import BelugaCore
import WebRTCTransport
@testable import CaptureServer

final class BelugaRustTierDemandTests: XCTestCase {
    private typealias I = beluga_core_tier_demand_facts_t
    private typealias O = beluga_core_tier_demand_projection_t
    private typealias R = FrozenTierDemandReference
    private typealias F = BelugaRustTierDemand
    private typealias T = WorldwideScreenVideoAdaptationTier

    func testActualCTwoLayoutsAndAllTwentyThreeOffsets() {
        XCTAssertEqual(checked(facts(cap: 50_000_000, tier: .full)).status, 1)
        XCTAssertEqual(MemoryLayout<I>.size, 24); XCTAssertEqual(MemoryLayout<I>.stride, 24)
        XCTAssertEqual(MemoryLayout<I>.alignment, 8)
        XCTAssertEqual(MemoryLayout<O>.size, 80); XCTAssertEqual(MemoryLayout<O>.stride, 80)
        XCTAssertEqual(MemoryLayout<O>.alignment, 8)
        let offsets: [(Int?, Int)] = [
            (MemoryLayout<I>.offset(of: \I.abi_version), 0),
            (MemoryLayout<I>.offset(of: \I.configured_cap), 4),
            (MemoryLayout<I>.offset(of: \I.current_tier), 8),
            (MemoryLayout<I>.offset(of: \I.bandwidth_present), 12),
            (MemoryLayout<I>.offset(of: \I.bandwidth_bits), 16),
            (MemoryLayout<O>.offset(of: \O.abi_version), 0),
            (MemoryLayout<O>.offset(of: \O.status), 4),
            (MemoryLayout<O>.offset(of: \O.current_tier), 8),
            (MemoryLayout<O>.offset(of: \O.reserved), 12),
            (MemoryLayout<O>.offset(of: \O.basis_points), 16),
            (MemoryLayout<O>.offset(of: \O.baseline_video), 20),
            (MemoryLayout<O>.offset(of: \O.maximum_tier_video), 24),
            (MemoryLayout<O>.offset(of: \O.maximum_video), 28),
            (MemoryLayout<O>.offset(of: \O.maximum_total_rtp), 32),
            (MemoryLayout<O>.offset(of: \O.minimum_sustainable), 36),
            (MemoryLayout<O>.offset(of: \O.initial_tier), 40),
            (MemoryLayout<O>.offset(of: \O.sustainable_tier), 44),
            (MemoryLayout<O>.offset(of: \O.upgrade_present), 48),
            (MemoryLayout<O>.offset(of: \O.upgrade_tier), 52),
            (MemoryLayout<O>.offset(of: \O.direct_threshold_present), 56),
            (MemoryLayout<O>.offset(of: \O.direct_threshold_minimum), 60),
            (MemoryLayout<O>.offset(of: \O.required_bitrate_bits), 64),
            (MemoryLayout<O>.offset(of: \O.direct_threshold_bits), 72),
        ]
        XCTAssertEqual(offsets.count, 23)
        for (actual, expected) in offsets { XCTAssertEqual(actual, expected) }
    }

    func testAbsentBandwidthProfilesMatchFrozenReferenceForAllTiersAndBoundaryCaps() {
        for cap in boundaryCaps() {
            for tier in R.Tier.allCases {
                let actual = checked(facts(cap: cap, tier: tier))
                XCTAssertEqual(actual.status, 1)
                XCTAssertEqual(actual.sustainable_tier, 7, "Missing telemetry is not capacity evidence")
                XCTAssertEqual(actual.upgrade_present, 0); XCTAssertEqual(actual.upgrade_tier, 0)
                XCTAssertLessThanOrEqual(actual.maximum_video, cap)
                XCTAssertLessThanOrEqual(actual.maximum_total_rtp, cap)
            }
        }
    }

    func testSustainableTierEveryDemandBoundaryAndAdjacentDoubles() {
        for cap in boundaryCaps() {
            let reference = R(configuredTotalRTPBitrateBps: Int(cap), currentTier: .full)
            for target in R.Tier.allCases {
                let demand = reference.requiredOutgoingBitrateBps(for: target)
                for bandwidth in [demand.nextDown, demand, demand.nextUp] {
                    for current in R.Tier.allCases {
                        let actual = checked(facts(cap: cap, tier: current, bandwidth: bandwidth))
                        XCTAssertEqual(actual.status, 1)
                        XCTAssertEqual(actual.sustainable_tier,
                            UInt32(reference.sustainableTier(for: bandwidth).rawValue))
                    }
                }
            }
        }
        for bandwidth in [Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude] {
            for tier in R.Tier.allCases {
                XCTAssertEqual(checked(facts(cap: .max, tier: tier, bandwidth: bandwidth)).status, 1)
            }
        }
    }

    func testUpgradeAdmissionEveryMarginAndConfiguredClampBoundary() {
        for cap in boundaryCaps() {
            for current in R.Tier.allCases {
                let reference = R(configuredTotalRTPBitrateBps: Int(cap), currentTier: current)
                for target in R.Tier.allCases {
                    let demand = reference.requiredOutgoingBitrateBps(for: target)
                    let threshold = min(Double(cap), demand * 1.25)
                    for bandwidth in [threshold.nextDown, threshold, threshold.nextUp] {
                        let actual = checked(facts(cap: cap, tier: current, bandwidth: bandwidth))
                        let expected = reference.highestQualifiedUpgradeTier(for: bandwidth)
                        XCTAssertEqual(actual.upgrade_present, expected == nil ? 0 : 1)
                        XCTAssertEqual(actual.upgrade_tier, expected.map { UInt32($0.rawValue) } ?? 0)
                    }
                }
            }
        }
    }

    func testConfiguredVideoBudgetFlooringAndFullUInt32CapRange() {
        let caps = boundaryCaps() + Array(UInt32(320_000)...320_040)
            + Array((UInt32.max - 16)...UInt32.max)
        for cap in caps {
            for tier in R.Tier.allCases {
                let reference = R(configuredTotalRTPBitrateBps: Int(cap), currentTier: tier)
                let actual = checked(facts(cap: cap, tier: tier))
                XCTAssertEqual(actual.maximum_tier_video, UInt32(reference.maximumTierVideoBitrateBps))
                XCTAssertEqual(actual.maximum_video,
                    UInt32(min(reference.maximumTierVideoBitrateBps, reference.referenceVideoBitrateBps(for: tier))))
            }
        }
        XCTAssertEqual(checked(facts(cap: 1, tier: .full)).maximum_tier_video, 1)
        XCTAssertEqual(checked(facts(cap: .max, tier: .full)).maximum_tier_video, 3_435_717_836)
    }

    func testLiteralCeilingArtifactsAndCalibratedDemandAreNotRationalized() {
        let cases: [(R.Tier, UInt32, UInt32, Double, Double?)] = [
            (.full, 9_344_000, 16_200_001, 12_000_000, nil),
            (.high, 6_260_480, 10_996_560, 8_145_600, 15_000_000),
            (.balanced, 3_924_480, 7_054_560, 5_225_600, 10_182_000),
            (.constrained, 1_962_240, 3_743_281, 2_772_800, 6_532_000),
            (.critical, 747_520, 1_693_440, 1_254_400, 3_466_000),
            (.survival, 280_320, 905_041, 670_400, 1_568_000),
            (.emergency, 93_440, 589_680, 436_800, 838_000),
            (.audioPriority, 32_000, 486_001, 360_000, 546_000),
        ]
        for (tier, baseline, rtp, demand, direct) in cases {
            let actual = checked(facts(cap: 50_000_000, tier: tier))
            XCTAssertEqual(actual.baseline_video, baseline)
            XCTAssertEqual(actual.maximum_total_rtp, rtp)
            XCTAssertEqual(actual.required_bitrate_bits, demand.bitPattern)
            XCTAssertEqual(actual.direct_threshold_bits, direct?.bitPattern ?? 0)
            XCTAssertEqual(actual.direct_threshold_minimum, direct.map { UInt32($0.rounded(.up)) } ?? 0)
        }
        let clamped = checked(facts(cap: 700_000, tier: .emergency))
        XCTAssertEqual(clamped.direct_threshold_present, 1)
        XCTAssertEqual(clamped.direct_threshold_bits, Double(700_000).bitPattern)
        XCTAssertEqual(clamped.direct_threshold_minimum, 700_000)
    }

    func testInitialTierPreservesSurvivalCeilingAtEveryConfiguredDemandBoundary() {
        for cap in boundaryCaps() {
            let expected = R.initialTier(configuredTotalRTPBitrateBps: Int(cap))
            for tier in R.Tier.allCases {
                let actual = checked(facts(cap: cap, tier: tier))
                XCTAssertEqual(actual.initial_tier, UInt32(expected.rawValue))
                XCTAssertGreaterThanOrEqual(actual.initial_tier, 5)
            }
        }
        XCTAssertEqual(checked(facts(cap: 50_000_000, tier: .full)).initial_tier, 5)
        XCTAssertEqual(checked(facts(cap: 1, tier: .full)).initial_tier, 7)
    }

    func testMalformedFactDomainsReturnCanonicalDenialAndVerifierRefusesIt() {
        let base = facts(cap: 50_000_000, tier: .critical, bandwidth: 2_262_000)
        let changes: [(String, (inout I) -> Void)] = [
            ("ABI zero", { $0.abi_version = 0 }), ("ABI unknown", { $0.abi_version = .max }),
            ("cap zero", { $0.configured_cap = 0 }),
            ("tier eight", { $0.current_tier = 8 }), ("tier max", { $0.current_tier = .max }),
            ("present tag", { $0.bandwidth_present = 2 }),
            ("absent nonzero", { $0.bandwidth_present = 0 }),
        ]
        for (name, change) in changes {
            var input = base; change(&input)
            XCTAssertEqual(bytes(checked(input)), bytes(rejected()), name)
        }
        for bandwidth in [0.0, -0.0, -1, -Double.leastNonzeroMagnitude, Double.nan,
            Double(bitPattern: 0x7ff0_0000_0000_0001), .infinity, -.infinity] {
            XCTAssertEqual(bytes(checked(facts(cap: 50_000_000, tier: .critical, bandwidth: bandwidth))),
                bytes(rejected()))
        }
        var absentNegativeZero = facts(cap: 50_000_000, tier: .full)
        absentNegativeZero.bandwidth_bits = (-0.0).bitPattern
        XCTAssertEqual(bytes(checked(absentNegativeZero)), bytes(rejected()))
    }

    func testEveryCopiedProjectionByteIsRejectedByActualExportedVerifier() {
        let inputs = [facts(cap: 1, tier: .full), facts(cap: .max, tier: .audioPriority),
            facts(cap: 50_000_000, tier: .critical, bandwidth: 2_262_000)]
        for input in inputs {
            let actual = checked(input)
            XCTAssertEqual(beluga_core_tier_demand_projection_is_valid(input, actual), 1)
            for byte in 0..<80 {
                var forged = actual; Self.corrupt(&forged, byte: byte)
                XCTAssertEqual(beluga_core_tier_demand_projection_is_valid(input, forged), 0, "byte \(byte)")
            }
        }
    }

    func testFacadeCachesOnlyVerifiedImmutableProfilesAndUsesOneActualDynamicProjection() {
        // The actual public policy must consume these admitted profiles, not retain
        // a parallel Swift bitrate algorithm while unused Rust happens to agree.
        let fps = [60, 45, 30, 20, 10, 5, 2, 1]
        let scales = [1.0, 1.25, 1.5, 2, 3, 4, 8, 12]
        for configuredCap in boundaryCaps().map(Int.init) + [-1, 0, Int.max] {
            for baseFPS in [0, 30, 60] {
                let policy = WorldwideScreenVideoAdaptationPolicy(
                    configuredTotalRTPBitrateBps: configuredCap, baseFramesPerSecond: baseFPS)
                let initial = R.initialTier(configuredTotalRTPBitrateBps:
                    min(Int(UInt32.max), max(1, configuredCap)))
                let initialReference = R(configuredTotalRTPBitrateBps: configuredCap,
                    currentTier: initial)
                XCTAssertFalse(policy.hasNativeTierDemandFault)
                XCTAssertEqual(policy.configuredTotalRTPBitrateBps,
                    initialReference.configuredTotalRTPBitrateBps)
                XCTAssertEqual(policy.maximumTierVideoBitrateBps,
                    initialReference.maximumTierVideoBitrateBps)
                XCTAssertEqual(policy.currentTier.rawValue, initial.rawValue)
                XCTAssertEqual(policy.currentTierMinimumSustainableBitrateBps,
                    initialReference.currentTierMinimumSustainableBitrateBps)
                XCTAssertEqual(policy.nextHigherTierMinimumDirectUpgradeBitrateBps,
                    initialReference.nextHigherTierMinimumDirectUpgradeBitrateBps)
                XCTAssertEqual(policy.currentRecommendation, policy.recommendation(for: policy.currentTier))
                for tier in R.Tier.allCases {
                    let projection = R(configuredTotalRTPBitrateBps: configuredCap,
                        currentTier: tier).projection(bandwidth: nil)
                    let nativeTier = T(rawValue: tier.rawValue)!
                    let expected = WorldwideScreenVideoEncodingRecommendation(
                        tier: nativeTier,
                        maximumBitrateBps: projection.maximumVideoBitrateBps,
                        maximumTotalRTPBitrateBps: projection.maximumTotalRTPBitrateBps,
                        maximumFramesPerSecond: min(max(1, baseFPS), fps[tier.rawValue]),
                        scaleResolutionDownBy: scales[tier.rawValue])
                    XCTAssertEqual(policy.recommendation(for: nativeTier), expected,
                        "configured cap \(configuredCap), tier \(tier.rawValue), base FPS \(baseFPS)")
                }
            }
        }
        let calls = TierDemandCallCount()
        var owner = F(configuredCap: 50_000_000, producer: { input in
            calls.record()
            return beluga_core_tier_demand_project(input)
        })
        XCTAssertFalse(owner.hasNativeFault)
        let initialCalls = calls.value
        XCTAssertGreaterThan(initialCalls, 0)
        for _ in 0..<3 {
            for tier in R.Tier.allCases {
                assertProfile(owner.profile(for: T(rawValue: tier.rawValue)!), cap: 50_000_000, tier: tier)
            }
        }
        XCTAssertEqual(calls.value, initialCalls, "A profile read must use only the verified immutable cache")
        let reference = R(configuredTotalRTPBitrateBps: 50_000_000, currentTier: .survival)
        let selected = owner.selection(for: .survival, availableBandwidth: 8_200_000)
        XCTAssertEqual(selected?.sustainableTier.rawValue, reference.sustainableTier(for: 8_200_000).rawValue)
        XCTAssertEqual(selected?.highestQualifiedUpgradeTier?.rawValue,
            reference.highestQualifiedUpgradeTier(for: 8_200_000)?.rawValue)
        XCTAssertEqual(calls.value, initialCalls + 1)
        XCTAssertFalse(owner.hasNativeFault)
    }

    func testFacadeDynamicFailureIsStickyWithoutFallbackOrFurtherProducerCalls() {
        let calls = TierDemandCallCount()
        var owner = F(configuredCap: 50_000_000, producer: { input in
            calls.record()
            var actual = beluga_core_tier_demand_project(input)
            if input.bandwidth_present == 1 { actual.upgrade_present ^= 1 }
            return actual
        })
        XCTAssertFalse(owner.hasNativeFault)
        XCTAssertNil(owner.selection(for: .survival, availableBandwidth: 50_000_000))
        XCTAssertTrue(owner.hasNativeFault)
        let faultCalls = calls.value
        for tier in T.allCases {
            XCTAssertNil(owner.selection(for: tier, availableBandwidth: 50_000_000))
            assertProfile(owner.profile(for: tier), cap: 50_000_000,
                tier: R.Tier(rawValue: tier.rawValue)!)
        }
        XCTAssertEqual(calls.value, faultCalls)
        var copied = F(configuredCap: 50_000_000)
        copied.retainFault(from: owner)
        XCTAssertTrue(copied.hasNativeFault)
        XCTAssertNil(copied.selection(for: .survival, availableBandwidth: 50_000_000))
        var replacement = F(configuredCap: 50_000_000)
        XCTAssertNotNil(replacement.selection(for: .survival, availableBandwidth: 50_000_000))
        XCTAssertFalse(replacement.hasNativeFault)
    }

    func testPublicPolicyInitializationDenialCannotArmAnySpeculativePermission() {
        // Denial after any amount of valid prefix must not publish a partial cache.
        // Exercise each cache position independently, with actual C invoked first.
        for cachePosition in UInt32(0)..<8 {
            let producer: F.Producer = { input in
                var actual = beluga_core_tier_demand_project(input)
                if input.current_tier == cachePosition { actual.status ^= 1 }
                return actual
            }
            var owner = F(configuredCap: 50_000_000, producer: producer)
            XCTAssertTrue(owner.hasNativeFault, "cache position \(cachePosition)")
            XCTAssertEqual(owner.initialTier, .audioPriority)
            XCTAssertEqual(owner.maximumTierVideoBitrateBps, 1)
            for tier in T.allCases {
                XCTAssertNil(owner.profile(for: tier), "cache position \(cachePosition)")
            }
            XCTAssertNil(owner.selection(for: .audioPriority, availableBandwidth: 50_000_000))
            var policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 50_000_000,
                baseFramesPerSecond: 60, tierDemandProducer: producer)
            XCTAssertTrue(policy.hasNativeTierDemandFault)
            XCTAssertEqual(policy.currentTier, .audioPriority)
            XCTAssertEqual(policy.maximumTierVideoBitrateBps, 1)
            policy.beginFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 1)
            policy.activateFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 1)
            _ = policy.update(peerGeneration: 1, isCaptureActive: true,
                availableOutgoingBitrateBps: 50_000_000, currentRoundTripTimeSeconds: 0.005)
            XCTAssertTrue(policy.hasNativeAdaptationPolicyFault)
            XCTAssertNil(policy.applicationLimitedProbeOriginTier)
            XCTAssertNil(policy.applicationLimitedProbeMaximumTotalRTPBitrateBps)
            XCTAssertNil(policy.promotionCapacityContinuity)
            XCTAssertFalse(policy.startupSpatialModeIsActive)
        }
        for byte in 0..<80 {
            var owner = F(configuredCap: 50_000_000, producer: { input in
                var actual = beluga_core_tier_demand_project(input)
                Self.corrupt(&actual, byte: byte)
                return actual
            })
            XCTAssertTrue(owner.hasNativeFault, "byte \(byte)")
            for tier in T.allCases { XCTAssertNil(owner.profile(for: tier), "byte \(byte)") }
            XCTAssertNil(owner.selection(for: .audioPriority, availableBandwidth: 50_000_000))
            var policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 50_000_000,
                baseFramesPerSecond: 60, tierDemandProducer: { input in
                    var actual = beluga_core_tier_demand_project(input)
                    Self.corrupt(&actual, byte: byte)
                    return actual
                })
            XCTAssertTrue(policy.hasNativeTierDemandFault)
            XCTAssertTrue(policy.hasNativeAdaptationPolicyFault)
            policy.beginFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 1)
            policy.activateFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 1)
            XCTAssertFalse(policy.startupSpatialModeIsActive)
            _ = policy.update(peerGeneration: 1, isCaptureActive: true,
                availableOutgoingBitrateBps: 50_000_000, currentRoundTripTimeSeconds: 0.005)
            XCTAssertTrue(policy.hasNativeTierDemandFault)
            XCTAssertNil(policy.applicationLimitedProbeOriginTier)
            XCTAssertNil(policy.applicationLimitedProbeMaximumTotalRTPBitrateBps)
            XCTAssertNil(policy.promotionCapacityContinuity)
            XCTAssertEqual(policy.healthyUpgradeSampleCount, 0)
            XCTAssertEqual(policy.applicationLimitedUpgradeSampleCount, 0)
            XCTAssertNil(policy.automaticSuspensionDecision(isCaptureActive: true, isAutomaticallySuspended: true))
        }
    }

    func testPublicPolicyDynamicDenialRetiresConfirmedProbeAndCannotRearm() {
        for floorOrigin in [false, true] {
            var fixture = ConfirmedTierFaultFixture(floorOrigin: floorOrigin)
            guard let origin = fixture.policy.applicationLimitedProbeOriginTier,
                  let confirmed = fixture.policy.applicationLimitedProbeConfirmedTier else {
                XCTFail("Public reports must establish the real confirmed probe"); continue
            }
            XCTAssertLessThan(confirmed.rawValue, origin.rawValue)
            let before = fixture.policy
            fixture.advanceRTT()
            let change = fixture.normal(50_000_000)
            XCTAssertTrue(fixture.policy.hasNativeTierDemandFault)
            XCTAssertTrue(fixture.policy.hasNativeAdaptationPolicyFault)
            XCTAssertNotNil(change, "The sender must receive the restrictive retirement")
            XCTAssertEqual(change, fixture.policy.currentRecommendation)
            assertRetired(fixture.policy, origin: origin)
            XCTAssertEqual(fixture.policy.applicationLimitedProbeFailureCount, before.applicationLimitedProbeFailureCount)
            XCTAssertEqual(fixture.policy.applicationLimitedProbeCooldownSamplesRemaining,
                before.applicationLimitedProbeCooldownSamplesRemaining)
            let retired = fixture.policy
            XCTAssertNil(fixture.policy.expireApplicationLimitedProbeWithoutReport(peerGeneration: 1,
                isCaptureActive: true, observedAt: fixture.now.advanced(by: .seconds(10))))
            XCTAssertEqual(fixture.policy, retired)
            fixture.policy.beginFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 2)
            fixture.policy.activateFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 2)
            XCTAssertFalse(fixture.policy.startupSpatialModeIsActive)
            let deniedAfterShow = fixture.policy
            for _ in 0..<3 {
                fixture.advanceRTT()
                XCTAssertNil(fixture.normal(50_000_000))
                XCTAssertEqual(fixture.policy, deniedAfterShow)
                XCTAssertNil(fixture.fast(50_000_000))
                XCTAssertEqual(fixture.policy, deniedAfterShow)
                assertRetired(fixture.policy, origin: origin)
            }
        }
    }

    func testPublicPolicySamePeerFaultCustodyCannotPoisonForeignPeerOrImportPositiveState() {
        for floorOrigin in [false, true] {
            var fixture = ConfirmedTierFaultFixture(floorOrigin: floorOrigin)
            guard let origin = fixture.policy.applicationLimitedProbeOriginTier else {
                XCTFail("Missing real probe origin"); continue
            }
            let pristine = fixture.policy
            fixture.advanceRTT()
            _ = fixture.normal(50_000_000)
            XCTAssertTrue(fixture.policy.hasNativeTierDemandFault)
            var retained = pristine
            let priorAge = retained.roundTripTimeObservationAge
            retained.retainNativeAdaptationPolicyFault(from: fixture.policy)
            XCTAssertTrue(retained.hasNativeTierDemandFault)
            assertRetired(retained, origin: origin)
            XCTAssertEqual(retained.roundTripTimeObservationAge, priorAge)
            XCTAssertEqual(retained.lastConsumedCollectionSequence, pristine.lastConsumedCollectionSequence)
            XCTAssertEqual(retained.selectedRoute, pristine.selectedRoute)
            var successor = pristine
            _ = successor.bind(toPeerGeneration: 2)
            let successorBefore = successor
            successor.retainNativeAdaptationPolicyFault(from: fixture.policy)
            XCTAssertFalse(successor.hasNativeTierDemandFault)
            XCTAssertEqual(successor, successorBefore)
            var noPeer = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 50_000_000,
                baseFramesPerSecond: 60)
            let noPeerBefore = noPeer
            noPeer.retainNativeAdaptationPolicyFault(from: fixture.policy)
            XCTAssertEqual(noPeer, noPeerBefore)
        }
    }

    private func facts(cap: UInt32, tier: R.Tier, bandwidth: Double? = nil) -> I {
        var input = I()
        input.abi_version = 1; input.configured_cap = cap; input.current_tier = UInt32(tier.rawValue)
        input.bandwidth_present = bandwidth == nil ? 0 : 1
        input.bandwidth_bits = bandwidth?.bitPattern ?? 0
        return input
    }

    private func rejected() -> O { var output = O(); output.abi_version = 1; return output }

    private func expected(_ input: I) -> O {
        let bandwidth = input.bandwidth_present == 1 ? Double(bitPattern: input.bandwidth_bits) : nil
        guard input.abi_version == 1, input.configured_cap > 0,
              let tier = R.Tier(rawValue: Int(input.current_tier)), input.bandwidth_present <= 1,
              input.bandwidth_present == 1 || input.bandwidth_bits == 0,
              bandwidth.map({ $0.isFinite && $0 > 0 }) ?? true else { return rejected() }
        let projection = R(configuredTotalRTPBitrateBps: Int(input.configured_cap),
            currentTier: tier).projection(bandwidth: bandwidth)
        var output = O()
        output.abi_version = 1; output.status = 1; output.current_tier = input.current_tier
        output.basis_points = UInt32(projection.basisPoints)
        output.baseline_video = UInt32(projection.baselineVideoBitrateBps)
        output.maximum_tier_video = UInt32(projection.maximumTierVideoBitrateBps)
        output.maximum_video = UInt32(projection.maximumVideoBitrateBps)
        output.maximum_total_rtp = UInt32(projection.maximumTotalRTPBitrateBps)
        output.minimum_sustainable = UInt32(projection.minimumSustainableBitrateBps)
        output.initial_tier = UInt32(projection.initialTier.rawValue)
        output.sustainable_tier = UInt32(projection.sustainableTier?.rawValue ?? 7)
        output.upgrade_present = projection.highestQualifiedUpgradeTier == nil ? 0 : 1
        output.upgrade_tier = UInt32(projection.highestQualifiedUpgradeTier?.rawValue ?? 0)
        output.direct_threshold_present = projection.nextHigherTierMinimumDirectUpgradeBitrateBps == nil ? 0 : 1
        output.direct_threshold_minimum = UInt32(projection.nextHigherTierMinimumDirectUpgradeBitrateBps ?? 0)
        output.required_bitrate_bits = projection.requiredOutgoingBitrateBps.bitPattern
        output.direct_threshold_bits = projection.nextHigherTierDirectUpgradeThresholdBps?.bitPattern ?? 0
        return output
    }

    @discardableResult
    private func checked(_ input: I, file: StaticString = #filePath, line: UInt = #line) -> O {
        let actual = beluga_core_tier_demand_project(input)
        XCTAssertEqual(bytes(actual), bytes(expected(input)), file: file, line: line)
        XCTAssertEqual(beluga_core_tier_demand_projection_is_valid(input, actual),
            actual.status == 1 ? 1 : 0, file: file, line: line)
        return actual
    }

    private func bytes<A>(_ value: A) -> [UInt8] { withUnsafeBytes(of: value) { Array($0) } }
    private static func corrupt(_ value: inout O, byte: Int) {
        withUnsafeMutableBytes(of: &value) { $0[byte] ^= 1 }
    }

    private func boundaryCaps() -> [UInt32] {
        var values: Set<UInt32> = [1, 2, 31_999, 32_000, 32_001, 319_999, 320_000, 320_001,
            359_999, 360_000, 360_001, 999_999, 1_000_000, 2_000_000, 4_000_000,
            11_999_999, 12_000_000, 12_000_001, 12_000_002, 50_000_000, .max - 1, .max]
        let reference = R(configuredTotalRTPBitrateBps: 50_000_000, currentTier: .full)
        for tier in R.Tier.allCases {
            let thresholds = [reference.requiredOutgoingBitrateBps(for: tier),
                reference.requiredOutgoingBitrateBps(for: tier) * 1.25,
                Double(reference.maximumTotalRTPBitrateBps(for: tier))]
            for threshold in thresholds {
                let integer = Int(threshold.rounded(.up))
                for delta in -1...1 { values.insert(UInt32(integer + delta)) }
            }
        }
        return values.sorted()
    }

    private func assertProfile(_ profile: F.Profile?, cap: Int, tier: R.Tier,
        file: StaticString = #filePath, line: UInt = #line) {
        guard let profile else { XCTFail("Missing verified profile", file: file, line: line); return }
        let expected = R(configuredTotalRTPBitrateBps: cap, currentTier: tier).projection(bandwidth: nil)
        XCTAssertEqual(profile.baselineVideoBitrateBps, expected.baselineVideoBitrateBps, file: file, line: line)
        XCTAssertEqual(profile.maximumVideoBitrateBps, expected.maximumVideoBitrateBps, file: file, line: line)
        XCTAssertEqual(profile.maximumTotalRTPBitrateBps, expected.maximumTotalRTPBitrateBps, file: file, line: line)
        XCTAssertEqual(profile.minimumSustainableBitrateBps, expected.minimumSustainableBitrateBps, file: file, line: line)
        XCTAssertEqual(profile.requiredOutgoingBitrateBps.bitPattern, expected.requiredOutgoingBitrateBps.bitPattern,
            file: file, line: line)
        XCTAssertEqual(profile.nextHigherTierMinimumDirectUpgradeBitrateBps,
            expected.nextHigherTierMinimumDirectUpgradeBitrateBps, file: file, line: line)
    }

    private func assertRetired(_ policy: WorldwideScreenVideoAdaptationPolicy, origin: T,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(policy.hasNativeTierDemandFault, file: file, line: line)
        XCTAssertEqual(policy.currentTier, origin, file: file, line: line)
        XCTAssertEqual(policy.currentRecommendation, policy.recommendation(for: origin), file: file, line: line)
        XCTAssertNil(policy.applicationLimitedProbeOriginTier, file: file, line: line)
        XCTAssertNil(policy.applicationLimitedProbeConfirmedTier, file: file, line: line)
        XCTAssertNil(policy.applicationLimitedProbeBestQualifiedTier, file: file, line: line)
        XCTAssertNil(policy.applicationLimitedProbeMaximumTotalRTPBitrateBps, file: file, line: line)
        XCTAssertNil(policy.applicationLimitedProbeDeadline, file: file, line: line)
        XCTAssertEqual(policy.applicationLimitedProbeHealthySampleCount, 0, file: file, line: line)
        XCTAssertEqual(policy.applicationLimitedProbeGraceSamplesRemaining, 0, file: file, line: line)
        XCTAssertNil(policy.promotionCapacityContinuity, file: file, line: line)
        XCTAssertFalse(policy.floorRecoveryProbeIsActive, file: file, line: line)
        XCTAssertFalse(policy.startupSpatialModeIsActive, file: file, line: line)
    }
}

private final class TierDemandCallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private struct ConfirmedTierFaultFixture {
    var policy: WorldwideScreenVideoAdaptationPolicy
    var now = ContinuousClock.now
    var milliseconds = 0
    var sequence: UInt64 = 0
    var packets: UInt64 = 0
    var delay = 0.0
    var totalRTT = 1.0
    var responses: UInt64 = 10
    let route = WebRTCICERouteDiagnostics(kind: .direct)
    var observation: WebRTCRoundTripTimeObservation {
        .measurement(.init(selectedCandidatePairFingerprint: String(repeating: "a", count: 64),
            totalRoundTripTimeSeconds: totalRTT, responsesReceived: responses))
    }
    var timestamp: Double { 1_000_000 + Double(milliseconds) * 1_000 }

    init(floorOrigin: Bool) {
        policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 50_000_000,
            baseFramesPerSecond: 60, tierDemandProducer: { input in
                var actual = beluga_core_tier_demand_project(input)
                if input.bandwidth_present == 1 && input.bandwidth_bits == Double(50_000_000).bitPattern {
                    actual.sustainable_tier = 7 // A structurally valid but false copied candidate.
                }
                return actual
            })
        if !floorOrigin {
            _ = normal(100_000, after: 0); XCTAssertEqual(policy.currentTier, .survival)
            _ = normal(100_000); XCTAssertEqual(policy.currentTier, .audioPriority)
            _ = normal(486_001); XCTAssertEqual(policy.applicationLimitedProbeOriginTier, .audioPriority)
        }
        policy.beginFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 1)
        policy.activateFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 1)
        if floorOrigin {
            _ = normal(100_000, after: 0)
            for (bandwidth, queueDelay) in [(100_000.0, 0.001), (251_000, 0.001),
                (262_000, 0.492), (276_000, 0.943), (292_000, 0.470),
                (304_000, 0.001), (331_000, 0.001)] {
                advanceRTT(); _ = normal(bandwidth, queueDelay: queueDelay)
            }
            XCTAssertTrue(policy.floorRecoveryProbeIsActive)
            XCTAssertTrue(policy.floorRecoveryAttemptConsumed)
        } else {
            _ = normal(950_000); _ = normal(950_000)
            XCTAssertEqual(policy.currentTier, .survival)
            for _ in 0..<3 where policy.applicationLimitedProbeOriginTier == nil {
                advanceRTT(); _ = normal(900_000)
            }
            XCTAssertEqual(policy.applicationLimitedProbeOriginTier, .survival)
        }
        _ = fast(floorOrigin ? 600_000 : 1_700_000)
        advanceRTT(); _ = normal(floorOrigin ? 1_179_360 : 2_111_466)
        advanceRTT(); _ = normal(floorOrigin ? 2_111_466 : 4_222_932)
        XCTAssertEqual(policy.applicationLimitedProbeConfirmedTier, floorOrigin ? .survival : .critical)
        XCTAssertEqual(policy.currentTier, floorOrigin ? .survival : .critical)
        XCTAssertGreaterThan(policy.applicationLimitedProbeMaximumTotalRTPBitrateBps ?? 0,
            policy.recommendation(for: policy.applicationLimitedProbeOriginTier!).maximumTotalRTPBitrateBps)
        XCTAssertFalse(policy.hasNativeTierDemandFault)
    }

    mutating func advanceRTT() { totalRTT += 0.005; responses += 1 }
    mutating func prepare(after: Int, queueDelay: Double) {
        milliseconds += after; now = now.advanced(by: .milliseconds(after))
        sequence += 1; packets += 100; delay += queueDelay * 100
    }
    mutating func normal(_ bandwidth: Double, after: Int = 500, queueDelay: Double = 0.001)
        -> WorldwideScreenVideoEncodingRecommendation? {
        prepare(after: after, queueDelay: queueDelay)
        return policy.update(peerGeneration: 1, isCaptureActive: true,
            availableOutgoingBitrateBps: bandwidth, currentRoundTripTimeSeconds: 0.005,
            roundTripTimeObservation: observation, collectionSequence: sequence,
            requireRoundTripTimeObservation: true, selectedRoute: route,
            outboundVideoPacketsSent: packets, outboundVideoTotalPacketSendDelaySeconds: delay,
            nativeReportTimestampMicroseconds: timestamp, observedAt: now)
    }
    mutating func fast(_ bandwidth: Double) -> WorldwideScreenVideoEncodingRecommendation? {
        prepare(after: 200, queueDelay: 0.001)
        return policy.updateCapacityProbe(peerGeneration: 1, isCaptureActive: true,
            availableOutgoingBitrateBps: bandwidth, currentRoundTripTimeSeconds: 0.005,
            roundTripTimeObservation: observation, collectionSequence: sequence,
            nativeReportTimestampMicroseconds: timestamp, selectedRoute: route,
            outboundVideoPacketsSent: packets, outboundVideoTotalPacketSendDelaySeconds: delay,
            observedAt: now)
    }
}
