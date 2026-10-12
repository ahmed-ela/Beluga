import Foundation

// Independent test-only preimage, frozen before any new Rust implementation.
// Source: WorldwideScreenVideoAdaptationPolicy.swift at SHA-256
// f3e52067738cc16c3eb2768fbccac8be5ac0ce96579a967bee91cd7360445aca.
// This file imports neither CaptureServer nor BelugaCore and does not call a
// production adapter. Native enum/time/effect ownership is outside this model.
struct FrozenTierDemandReference {
    enum Tier: Int, CaseIterable, Equatable {
        case full
        case high
        case balanced
        case constrained
        case critical
        case survival
        case emergency
        case audioPriority

        var bitrateBasisPoints: Int {
            switch self {
            case .full: 10_000
            case .high: 6_700
            case .balanced: 4_200
            case .constrained: 2_100
            case .critical: 800
            case .survival: 300
            case .emergency: 100
            case .audioPriority: 25
            }
        }

        var nextHigherQuality: Self? { Self(rawValue: rawValue - 1) }
    }

    struct Projection: Equatable {
        let currentTier: Tier
        let basisPoints: Int
        let baselineVideoBitrateBps: Int
        let maximumTierVideoBitrateBps: Int
        let maximumVideoBitrateBps: Int
        let maximumTotalRTPBitrateBps: Int
        let minimumSustainableBitrateBps: Int
        let initialTier: Tier
        // The old helpers are never called with missing bandwidth. Preserve
        // that absence rather than choosing a new scalar ABI placeholder here.
        let sustainableTier: Tier?
        let highestQualifiedUpgradeTier: Tier?
        let nextHigherTierMinimumDirectUpgradeBitrateBps: Int?
        let requiredOutgoingBitrateBps: Double
        let nextHigherTierDirectUpgradeThresholdBps: Double?
    }

    static let minimumVideoBitrateBps = 32_000
    static let audioAndControlReserveBps = 320_000.0
    static let baselineReferenceMaximumVideoBitrateBps = 9_344_000
    static let downgradeHeadroomMultiplier = 1.25
    static let upgradeMarginMultiplier = 1.25
    static let totalRTPHeadroomMultiplier = 1.35

    let configuredTotalRTPBitrateBps: Int
    let maximumTierVideoBitrateBps: Int
    let currentTier: Tier

    init(configuredTotalRTPBitrateBps: Int, currentTier: Tier) {
        self.configuredTotalRTPBitrateBps = min(
            Int(UInt32.max), max(1, configuredTotalRTPBitrateBps))
        let videoBudget = max(
            0, Double(self.configuredTotalRTPBitrateBps) - Self.audioAndControlReserveBps
        ) / Self.downgradeHeadroomMultiplier
        maximumTierVideoBitrateBps = min(
            self.configuredTotalRTPBitrateBps,
            max(Self.minimumVideoBitrateBps, Int(videoBudget.rounded(.down))))
        self.currentTier = currentTier
    }

    func sustainableTier(for availableOutgoingBitrateBps: Double) -> Tier {
        Tier.allCases.first { tier in
            let requiredBitrate = requiredOutgoingBitrateBps(for: tier)
            return requiredBitrate <= Double(configuredTotalRTPBitrateBps)
                && availableOutgoingBitrateBps >= requiredBitrate
        } ?? .audioPriority
    }

    func highestQualifiedUpgradeTier(for availableOutgoingBitrateBps: Double) -> Tier? {
        Tier.allCases.first { tier in
            guard tier.rawValue < currentTier.rawValue else { return false }
            let requiredBitrate = requiredOutgoingBitrateBps(for: tier)
            guard requiredBitrate <= Double(configuredTotalRTPBitrateBps) else { return false }
            let upgradeThreshold = min(
                Double(configuredTotalRTPBitrateBps), requiredBitrate * Self.upgradeMarginMultiplier)
            return availableOutgoingBitrateBps >= upgradeThreshold
        }
    }

    func requiredOutgoingBitrateBps(for tier: Tier) -> Double {
        Double(Self.baselineReferenceVideoBitrateBps(for: tier))
            * Self.downgradeHeadroomMultiplier + Self.audioAndControlReserveBps
    }

    func maximumTotalRTPBitrateBps(for tier: Tier) -> Int {
        Int(min(Double(configuredTotalRTPBitrateBps),
            requiredOutgoingBitrateBps(for: tier) * Self.totalRTPHeadroomMultiplier).rounded(.up))
    }

    static func initialTier(configuredTotalRTPBitrateBps: Int) -> Tier {
        let configuredQualityCeiling = Tier.allCases.first { tier in
            let referenceVideoBitrate = baselineReferenceVideoBitrateBps(for: tier)
            let required = Double(referenceVideoBitrate)
                * downgradeHeadroomMultiplier + audioAndControlReserveBps
            return required <= Double(configuredTotalRTPBitrateBps)
        } ?? .audioPriority
        return Tier(rawValue: max(Tier.survival.rawValue, configuredQualityCeiling.rawValue)) ?? .audioPriority
    }

    func referenceVideoBitrateBps(for tier: Tier) -> Int {
        let referenceMaximumVideoBitrateBps = max(
            Self.baselineReferenceMaximumVideoBitrateBps, maximumTierVideoBitrateBps)
        return max(Self.minimumVideoBitrateBps,
            referenceMaximumVideoBitrateBps * tier.bitrateBasisPoints / 10_000)
    }

    static func baselineReferenceVideoBitrateBps(for tier: Tier) -> Int {
        max(minimumVideoBitrateBps,
            baselineReferenceMaximumVideoBitrateBps * tier.bitrateBasisPoints / 10_000)
    }

    var currentTierMinimumSustainableBitrateBps: Int {
        Int(requiredOutgoingBitrateBps(for: currentTier).rounded(.up))
    }

    var nextHigherTierMinimumDirectUpgradeBitrateBps: Int? {
        guard let nextHigherTier = currentTier.nextHigherQuality else { return nil }
        let requiredBitrate = requiredOutgoingBitrateBps(for: nextHigherTier)
        guard requiredBitrate <= Double(configuredTotalRTPBitrateBps) else { return nil }
        return Int(min(Double(configuredTotalRTPBitrateBps),
            requiredBitrate * Self.upgradeMarginMultiplier).rounded(.up))
    }

    // This additionally retains the unrounded value already used by the
    // original upgrade predicate; it is not recomputed from the rounded Int.
    var nextHigherTierDirectUpgradeThresholdBps: Double? {
        guard let nextHigherTier = currentTier.nextHigherQuality else { return nil }
        let requiredBitrate = requiredOutgoingBitrateBps(for: nextHigherTier)
        guard requiredBitrate <= Double(configuredTotalRTPBitrateBps) else { return nil }
        return min(Double(configuredTotalRTPBitrateBps), requiredBitrate * Self.upgradeMarginMultiplier)
    }

    func projection(bandwidth: Double?) -> Projection {
        Projection(currentTier: currentTier,
            basisPoints: currentTier.bitrateBasisPoints,
            baselineVideoBitrateBps: Self.baselineReferenceVideoBitrateBps(for: currentTier),
            maximumTierVideoBitrateBps: maximumTierVideoBitrateBps,
            maximumVideoBitrateBps: min(maximumTierVideoBitrateBps, referenceVideoBitrateBps(for: currentTier)),
            maximumTotalRTPBitrateBps: maximumTotalRTPBitrateBps(for: currentTier),
            minimumSustainableBitrateBps: currentTierMinimumSustainableBitrateBps,
            initialTier: Self.initialTier(configuredTotalRTPBitrateBps: configuredTotalRTPBitrateBps),
            sustainableTier: bandwidth.map(sustainableTier(for:)),
            highestQualifiedUpgradeTier: bandwidth.flatMap(highestQualifiedUpgradeTier(for:)),
            nextHigherTierMinimumDirectUpgradeBitrateBps: nextHigherTierMinimumDirectUpgradeBitrateBps,
            requiredOutgoingBitrateBps: requiredOutgoingBitrateBps(for: currentTier),
            nextHigherTierDirectUpgradeThresholdBps: nextHigherTierDirectUpgradeThresholdBps)
    }
}
