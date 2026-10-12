import BelugaCore

/// Copied, verified codec-demand decisions. Clocks, native effects and tier mutation remain
/// with the policy owner. Immutable profiles are admitted once; getters never query a producer.
struct FrozenPinnedTierDemand: Equatable, Sendable {
    typealias Facts = beluga_core_tier_demand_facts_t
    typealias Projection = beluga_core_tier_demand_projection_t
    typealias Producer = @Sendable (Facts) -> Projection
    typealias Tier = FrozenWorldwideScreenVideoAdaptationTier

    struct Profile: Equatable, Sendable {
        let baselineVideoBitrateBps: Int
        let maximumVideoBitrateBps: Int
        let maximumTotalRTPBitrateBps: Int
        let minimumSustainableBitrateBps: Int
        let requiredOutgoingBitrateBps: Double
        let nextHigherTierMinimumDirectUpgradeBitrateBps: Int?
    }

    struct Selection: Equatable, Sendable {
        let sustainableTier: Tier
        let highestQualifiedUpgradeTier: Tier?
    }

    private let configuredCap: UInt32
    private let producer: Producer
    private var profiles: [Profile] = []
    private(set) var hasNativeFault = false
    private(set) var initialTier: Tier = .audioPriority
    // Explicit denied startup limits, not a replacement implementation of the Rust algorithm.
    private(set) var maximumTierVideoBitrateBps = 1

    init(configuredCap: Int, producer: @escaping Producer = { beluga_core_tier_demand_project($0) }) {
        self.configuredCap = UInt32(clamping: max(1, configuredCap))
        self.producer = producer
        guard Self.layoutIsExact else { hasNativeFault = true; return }
        var admitted: [Profile] = []
        var admittedInitial: Tier = .audioPriority
        var admittedMaximum = 1
        for tier in Tier.allCases {
            let facts = facts(for: tier, bandwidth: nil)
            let result = producer(facts)
            guard beluga_core_tier_demand_projection_is_valid(facts, result) == 1,
                  let initial = Tier(rawValue: Int(result.initial_tier)) else {
                hasNativeFault = true
                return
            }
            admitted.append(Profile(
                baselineVideoBitrateBps: Int(result.baseline_video),
                maximumVideoBitrateBps: Int(result.maximum_video),
                maximumTotalRTPBitrateBps: Int(result.maximum_total_rtp),
                minimumSustainableBitrateBps: Int(result.minimum_sustainable),
                requiredOutgoingBitrateBps: Double(bitPattern: result.required_bitrate_bits),
                nextHigherTierMinimumDirectUpgradeBitrateBps: result.direct_threshold_present == 1
                    ? Int(result.direct_threshold_minimum) : nil))
            admittedInitial = initial
            admittedMaximum = Int(result.maximum_tier_video)
        }
        profiles = admitted
        initialTier = admittedInitial
        maximumTierVideoBitrateBps = admittedMaximum
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.configuredCap == rhs.configuredCap && lhs.profiles == rhs.profiles
            && lhs.hasNativeFault == rhs.hasNativeFault && lhs.initialTier == rhs.initialTier
            && lhs.maximumTierVideoBitrateBps == rhs.maximumTierVideoBitrateBps
    }

    static var layoutIsExact: Bool {
        UInt16(littleEndian: 1) == 1
            && MemoryLayout<Facts>.size == 24 && MemoryLayout<Facts>.stride == 24
            && MemoryLayout<Facts>.alignment == 8
            && MemoryLayout<Projection>.size == 80 && MemoryLayout<Projection>.stride == 80
            && MemoryLayout<Projection>.alignment == 8
            && MemoryLayout<Facts>.offset(of: \Facts.abi_version) == 0
            && MemoryLayout<Facts>.offset(of: \Facts.configured_cap) == 4
            && MemoryLayout<Facts>.offset(of: \Facts.current_tier) == 8
            && MemoryLayout<Facts>.offset(of: \Facts.bandwidth_present) == 12
            && MemoryLayout<Facts>.offset(of: \Facts.bandwidth_bits) == 16
            && MemoryLayout<Projection>.offset(of: \Projection.abi_version) == 0
            && MemoryLayout<Projection>.offset(of: \Projection.status) == 4
            && MemoryLayout<Projection>.offset(of: \Projection.current_tier) == 8
            && MemoryLayout<Projection>.offset(of: \Projection.reserved) == 12
            && MemoryLayout<Projection>.offset(of: \Projection.basis_points) == 16
            && MemoryLayout<Projection>.offset(of: \Projection.baseline_video) == 20
            && MemoryLayout<Projection>.offset(of: \Projection.maximum_tier_video) == 24
            && MemoryLayout<Projection>.offset(of: \Projection.maximum_video) == 28
            && MemoryLayout<Projection>.offset(of: \Projection.maximum_total_rtp) == 32
            && MemoryLayout<Projection>.offset(of: \Projection.minimum_sustainable) == 36
            && MemoryLayout<Projection>.offset(of: \Projection.initial_tier) == 40
            && MemoryLayout<Projection>.offset(of: \Projection.sustainable_tier) == 44
            && MemoryLayout<Projection>.offset(of: \Projection.upgrade_present) == 48
            && MemoryLayout<Projection>.offset(of: \Projection.upgrade_tier) == 52
            && MemoryLayout<Projection>.offset(of: \Projection.direct_threshold_present) == 56
            && MemoryLayout<Projection>.offset(of: \Projection.direct_threshold_minimum) == 60
            && MemoryLayout<Projection>.offset(of: \Projection.required_bitrate_bits) == 64
            && MemoryLayout<Projection>.offset(of: \Projection.direct_threshold_bits) == 72
    }

    private func facts(for tier: Tier, bandwidth: Double?) -> Facts {
        var facts = Facts()
        facts.abi_version = 1
        facts.configured_cap = configuredCap
        facts.current_tier = UInt32(tier.rawValue)
        facts.bandwidth_present = bandwidth == nil ? 0 : 1
        facts.bandwidth_bits = bandwidth?.bitPattern ?? 0
        return facts
    }

    func profile(for tier: Tier) -> Profile? {
        profiles.indices.contains(tier.rawValue) ? profiles[tier.rawValue] : nil
    }

    mutating func selection(for tier: Tier, availableBandwidth: Double) -> Selection? {
        guard !hasNativeFault else { return nil }
        let facts = facts(for: tier, bandwidth: availableBandwidth)
        let result = producer(facts)
        guard Self.layoutIsExact,
              beluga_core_tier_demand_projection_is_valid(facts, result) == 1,
              let sustainable = Tier(rawValue: Int(result.sustainable_tier)) else {
            hasNativeFault = true
            return nil
        }
        let upgrade = result.upgrade_present == 1 ? Tier(rawValue: Int(result.upgrade_tier)) : nil
        return Selection(sustainableTier: sustainable, highestQualifiedUpgradeTier: upgrade)
    }

    /// Import only a terminal denial. Verified immutable profiles and producer never transfer.
    mutating func retainFault(from other: Self) {
        if other.hasNativeFault { hasNativeFault = true }
    }
}
