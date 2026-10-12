import Foundation

/// A content-free admission proposal, never evidence that native sender limits were applied.
struct WorldwideScreenFloorRecoveryDiagnostics: Equatable, Sendable {
    enum Identity: String, CaseIterable, Equatable, Sendable {
        case notChecked, fresh, rejectedOrder, rejectedTimestamp
    }
    enum Reason: String, CaseIterable, Equatable, Sendable {
        case notEvaluated, rejectedOrder, rejectedTimestamp, inactiveVisibility
        case consumed, disproved, notFloor, existingProbe, rttBlocked, invalidBandwidth
        case ordinaryProbeEligible, noHeadroom, noNewPackets, queueBlocked, cooldown
        case firstWitness, tooEarly, bandwidthFalling, qualified, admitted
    }
    enum QueueKind: String, CaseIterable, Equatable, Sendable {
        case notChecked, measured, noNewPackets, unavailableOrReset
    }
    enum Trend: String, CaseIterable, Equatable, Sendable {
        case unknown, falling, flat, rising
    }

    let showEpoch: UInt64?
    let reserved: Bool
    let active: Bool
    let consumed: Bool
    let disproved: Bool
    let cooldownRemaining: Int
    let collectionSequence: UInt64?
    let previousRegularSequence: UInt64?
    let previousRegularReportMicroseconds: UInt64?
    let capacityReportMicroseconds: UInt64?
    let nativeReportMicroseconds: UInt64?
    let currentBandwidthBps: Double?
    let firstBandwidthBps: Double?
    let witnessAgeMicroseconds: UInt64?
    let beforeTotalCapBps: Int
    let trend: Trend
    var proposedTotalCapBps: Int
    var identity: Identity = .notChecked
    var reason: Reason = .notEvaluated
    var queueKind: QueueKind = .notChecked
    var queueMicroseconds: UInt64?
    var roundTripTimeDisposition: WorldwideScreenVideoAdaptationPolicy.RoundTripTimeDisposition?
    var roundTripTimeAllowsUpgrade: Bool?

    init(
        showEpoch: UInt64?, reserved: Bool, active: Bool, consumed: Bool, disproved: Bool,
        cooldownRemaining: Int, collectionSequence: UInt64?, previousRegularSequence: UInt64?,
        previousRegularTimestamp: Double?, capacityTimestamp: Double?, nativeReportTimestamp: Double?,
        currentBandwidthBps: Double?, firstBandwidthBps: Double?, witnessAge: Duration?,
        beforeTotalCapBps: Int
    ) {
        self.showEpoch = showEpoch
        self.reserved = reserved
        self.active = active
        self.consumed = consumed
        self.disproved = disproved
        self.cooldownRemaining = cooldownRemaining
        self.collectionSequence = collectionSequence
        self.previousRegularSequence = previousRegularSequence
        previousRegularReportMicroseconds = Self.boundedInteger(previousRegularTimestamp)
        capacityReportMicroseconds = Self.boundedInteger(capacityTimestamp)
        nativeReportMicroseconds = Self.boundedInteger(nativeReportTimestamp)
        self.currentBandwidthBps = Self.positiveBandwidth(currentBandwidthBps)
        self.firstBandwidthBps = Self.positiveBandwidth(firstBandwidthBps)
        if let current = self.currentBandwidthBps, let first = self.firstBandwidthBps {
            trend = current < first ? .falling : (current == first ? .flat : .rising)
        } else {
            trend = .unknown
        }
        if let witnessAge, witnessAge >= .zero {
            let components = witnessAge.components
            witnessAgeMicroseconds = Self.boundedInteger(
                Double(components.seconds) * 1_000_000
                    + Double(components.attoseconds) / 1_000_000_000_000
            )
        } else {
            witnessAgeMicroseconds = nil
        }
        self.beforeTotalCapBps = beforeTotalCapBps
        proposedTotalCapBps = beforeTotalCapBps
    }

    static func boundedInteger(_ value: Double?) -> UInt64? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return UInt64(exactly: value.rounded())
    }

    static func boundedMicroseconds(seconds: Double?) -> UInt64? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        return boundedInteger(seconds * 1_000_000)
    }

    private static func positiveBandwidth(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Format only from the service's regular statistics lane, never a media callback.
    var logFields: String {
        [
            "floorReason=\(reason.rawValue)", "floorIdentity=\(identity.rawValue)",
            "floorShowEpoch=\(showEpoch.map(String.init) ?? "unknown")",
            "floorReserved=\(reserved)", "floorActive=\(active)",
            "floorConsumed=\(consumed)", "floorDisproved=\(disproved)",
            "floorCooldownRemaining=\(cooldownRemaining >= 0 ? String(cooldownRemaining) : "unknown")",
            "collectionSeq=\(collectionSequence.map(String.init) ?? "unknown")",
            "previousRegularSeq=\(previousRegularSequence.map(String.init) ?? "unknown")",
            "previousRegularReportMicros=\(previousRegularReportMicroseconds.map(String.init) ?? "unknown")",
            "capacityReportMicros=\(capacityReportMicroseconds.map(String.init) ?? "unknown")",
            "nativeReportMicros=\(nativeReportMicroseconds.map(String.init) ?? "unknown")",
            "currentBweBps=\(currentBandwidthBps.map { String($0) } ?? "unknown")",
            "firstBweBps=\(firstBandwidthBps.map { String($0) } ?? "unknown")",
            "witnessAgeMicros=\(witnessAgeMicroseconds.map(String.init) ?? "unknown")",
            "beforeTotalCapBps=\(beforeTotalCapBps >= 0 ? String(beforeTotalCapBps) : "unknown")",
            "proposedTotalCapBps=\(proposedTotalCapBps >= 0 ? String(proposedTotalCapBps) : "unknown")",
            "floorQueueKind=\(queueKind.rawValue)",
            "floorQueueMicros=\(queueMicroseconds.map(String.init) ?? "unknown")",
            "rttObservation=\(roundTripTimeDisposition?.rawValue ?? "unknown")",
            "rttAllowsUpgrade=\(roundTripTimeAllowsUpgrade.map(String.init) ?? "unknown")",
            "bandwidthTrend=\(trend.rawValue)",
        ].joined(separator: " ")
    }
}

// Each extension is appended to its existing respective diagnostic source file.
// Reader construction is sealed to the validated codec output, not a caller DTO.
extension WorldwideScreenFloorRecoveryDiagnostics {
    init(networkAdaptationPreparedReader r: inout BelugaNetworkAdaptationPreparedReader) throws {
        showEpoch = try r.unsigned(); reserved = try r.boolean(); active = try r.boolean()
        consumed = try r.boolean(); disproved = try r.boolean(); cooldownRemaining = try r.integer()
        collectionSequence = try r.unsigned(); previousRegularSequence = try r.unsigned()
        previousRegularReportMicroseconds = try r.unsigned(); capacityReportMicroseconds = try r.unsigned()
        nativeReportMicroseconds = try r.unsigned(); currentBandwidthBps = try r.scalar()
        firstBandwidthBps = try r.scalar(); witnessAgeMicroseconds = try r.unsigned()
        beforeTotalCapBps = try r.integer(); proposedTotalCapBps = try r.integer()
        trend = try r.choice([.unknown, .falling, .flat, .rising])
        identity = try r.choice([.notChecked, .fresh, .rejectedOrder, .rejectedTimestamp])
        reason = try r.choice([.notEvaluated, .rejectedOrder, .rejectedTimestamp, .inactiveVisibility,
            .consumed, .disproved, .notFloor, .existingProbe, .rttBlocked, .invalidBandwidth,
            .ordinaryProbeEligible, .noHeadroom, .noNewPackets, .queueBlocked, .cooldown,
            .firstWitness, .tooEarly, .bandwidthFalling, .qualified, .admitted])
        queueKind = try r.choice([.notChecked, .measured, .noNewPackets, .unavailableOrReset])
        queueMicroseconds = try r.unsigned()
        let dispositions: [WorldwideScreenVideoAdaptationPolicy.RoundTripTimeDisposition] = [
            .legacy, .provisionalHealthy, .freshHealthy, .freshInflated, .retainedHealthy,
            .retainedInflated, .unavailable, .expired, .reseeded, .reordered]
        roundTripTimeDisposition = try r.optionalChoice(dispositions)
        roundTripTimeAllowsUpgrade = try r.optionalBoolean()
    }

    func networkAdaptationOwnerWritePrepared(into w: inout BelugaNetworkAdaptationOwnerWriter) {
        w.unsigned(showEpoch); w.boolean(reserved); w.boolean(active); w.boolean(consumed); w.boolean(disproved)
        w.integer(cooldownRemaining); w.unsigned(collectionSequence); w.unsigned(previousRegularSequence)
        w.unsigned(previousRegularReportMicroseconds); w.unsigned(capacityReportMicroseconds)
        w.unsigned(nativeReportMicroseconds); w.scalar(currentBandwidthBps); w.scalar(firstBandwidthBps)
        w.unsigned(witnessAgeMicroseconds); w.integer(beforeTotalCapBps); w.integer(proposedTotalCapBps)
        w.u32(UInt32([Trend.unknown, .falling, .flat, .rising].firstIndex(of: trend)!))
        w.u32(UInt32([Identity.notChecked, .fresh, .rejectedOrder, .rejectedTimestamp].firstIndex(of: identity)!))
        w.u32(UInt32([Reason.notEvaluated, .rejectedOrder, .rejectedTimestamp, .inactiveVisibility,
            .consumed, .disproved, .notFloor, .existingProbe, .rttBlocked, .invalidBandwidth,
            .ordinaryProbeEligible, .noHeadroom, .noNewPackets, .queueBlocked, .cooldown,
            .firstWitness, .tooEarly, .bandwidthFalling, .qualified, .admitted].firstIndex(of: reason)!))
        w.u32(UInt32([QueueKind.notChecked, .measured, .noNewPackets, .unavailableOrReset].firstIndex(of: queueKind)!))
        w.unsigned(queueMicroseconds)
        let dispositions: [WorldwideScreenVideoAdaptationPolicy.RoundTripTimeDisposition] = [
            .legacy, .provisionalHealthy, .freshHealthy, .freshInflated, .retainedHealthy,
            .retainedInflated, .unavailable, .expired, .reseeded, .reordered]
        w.word(6, roundTripTimeDisposition.map { UInt64(dispositions.firstIndex(of: $0)!) })
        w.boolean(roundTripTimeAllowsUpgrade)
    }
}
