import Foundation
import BelugaCore
import WebRTCTransport
@testable import CaptureServer

/// Test-only observation, not an oracle algorithm. No candidate producer/verifier is called.
/// Every root field and every nested child is retained, apart from the two producer closures.
/// Double/Float payloads are observed as IEEE bits; clocks use exact Duration components.
enum FrozenAdaptationAllState {
    struct Entry: Equatable, CustomStringConvertible {
        let path: String
        let value: String
        var description: String { "\(path)=\(value)" }
    }

    enum ObservationError: Error {
        case rootFields(expected: [String], actual: [String])
        case unsupportedLeaf(path: String, type: String)
    }

    static let policyFields = [
        "configuredTotalRTPBitrateBps",
        "maximumTierVideoBitrateBps",
        "baseFramesPerSecond",
        "peerGeneration",
        "currentTier",
        "healthyUpgradeSampleCount",
        "bandwidthOnlyDowngradeSampleCount",
        "unavailableBandwidthSampleCount",
        "positiveBandwidthBootstrapSampleCount",
        "applicationLimitedUpgradeSampleCount",
        "applicationLimitedProbeHealthySampleCount",
        "applicationLimitedProbeGraceSamplesRemaining",
        "applicationLimitedProbeDeadline",
        "applicationLimitedProbeCooldownSamplesRemaining",
        "applicationLimitedProbeFailureCount",
        "belowReserveProbeDisprovedSenderLimitation",
        "automaticResumeProbeRestoration",
        "applicationLimitedProbeOriginTier",
        "applicationLimitedProbeBestQualifiedTier",
        "applicationLimitedProbeConfirmedTier",
        "applicationLimitedProbeQualificationObservedAt",
        "applicationLimitedProbeMaximumTotalRTPBitrateBps",
        "promotionCapacityContinuity",
        "automaticSuspensionPressureSampleCount",
        "stableSuspensionResumeProbeSampleCount",
        "maximumSuspensionResumeProbeSampleCount",
        "bandwidthEstimateIsUnavailable",
        "lastSampleHasLatencyPressure",
        "lastSampleHasPositiveSuspensionPressure",
        "lastAveragePacketSendDelaySeconds",
        "packetQueue",
        "roundTripTime",
        "tierDemand",
        "lastConsumedCollectionSequence",
        "selectedRoute",
        "capacityProbeSample",
        "capacityProbeBandwidthHighWatermark",
        "capacityProbeNativeReportTimestamp",
        "lastCapacityProbeCollectionSequence",
        "capacityProbeGrowthIsVetoed",
        "floorRecoveryShowEpoch",
        "floorRecoveryVisibilityIsReserved",
        "floorRecoveryVisibilityIsActive",
        "floorRecoveryAttemptConsumed",
        "floorRecoveryProbeWasCancelled",
        "floorRecoveryProbeSeedBandwidthBps",
        "floorRecoveryFirstWitness",
        "floorRecoveryLastRegularSequence",
        "floorRecoveryLastRegularTimestamp",
        "floorRecoveryLastCooldownObservation",
        "startupSpatialModePeerGeneration",
        "startupSpatialModeShowEpoch",
        "startupSpatialModeIsDisproved",
        "startupSparseProbeDeadline",
    ]
    static let cadenceFields = [
        "nextRegularDeadline", "nextCapacityDeadline", "capacityProbeEnabled",
        "inFlightSample", "latestSchedulingInstant",
    ]

    static func policy(_ value: Any, anchor: ContinuousClock.Instant) throws -> [Entry] {
        try checked(value, fields: policyFields, anchor: anchor)
    }

    static func cadence(_ value: Any, anchor: ContinuousClock.Instant) throws -> [Entry] {
        try checked(value, fields: cadenceFields, anchor: anchor)
    }

    static func result(_ value: Any, anchor: ContinuousClock.Instant) throws -> [Entry] {
        var entries: [Entry] = []
        try visit(value, path: "", anchor: anchor, into: &entries)
        return entries
    }

    private static func checked(_ value: Any, fields: [String],
                                anchor: ContinuousClock.Instant) throws -> [Entry] {
        let actual = Mirror(reflecting: value).children.map { $0.label ?? "<unlabelled>" }
        guard actual == fields else {
            throw ObservationError.rootFields(expected: fields, actual: actual)
        }
        return try result(value, anchor: anchor)
    }

    private static func duration(_ value: Duration) -> String {
        let parts = value.components
        return "duration:\(parts.seconds):\(parts.attoseconds)"
    }

    private static func visit(_ value: Any, path: String,
                              anchor: ContinuousClock.Instant, into entries: inout [Entry]) throws {
        func append(_ value: String) { entries.append(Entry(path: path, value: value)) }
        // Swift dynamic casts transparently unwrap Optional.some. Preserve the complete
        // optional tree BEFORE casting to a typed leaf, including nested nil/some shapes.
        let mirror = Mirror(reflecting: value)
        let children = Array(mirror.children)
        if mirror.displayStyle == .optional {
            append(children.isEmpty ? "optional:none" : "optional:some")
            for (index, child) in children.enumerated() {
                let label = child.label ?? "[\(index)]"
                let childPath = path.isEmpty ? label : path + "." + label
                try visit(child.value, path: childPath, anchor: anchor, into: &entries)
            }
            return
        }
        // Native clock instants are compared by exact signed duration from the SAME test anchor.
        if let value = value as? ContinuousClock.Instant {
            append("instant:" + duration(anchor.duration(to: value))); return
        }
        if let value = value as? Duration { append(duration(value)); return }
        if let value = value as? Double { append("double:" + String(value.bitPattern, radix: 16)); return }
        if let value = value as? Float { append("float:" + String(value.bitPattern, radix: 16)); return }
        if let value = value as? Bool { append(value ? "bool:1" : "bool:0"); return }
        if let value = value as? Int { append("int:\(value)"); return }
        if let value = value as? UInt64 { append("u64:\(value)"); return }
        if let value = value as? UInt32 { append("u32:\(value)"); return }
        if let value = value as? Int64 { append("i64:\(value)"); return }
        if let value = value as? String { append("utf8:" + value.utf8.map { String($0, radix: 16) }.joined(separator: ",")); return }
        // This is the separately pinned EXISTING RTT DTO, including reserved bytes and fields.
        if let value = value as? beluga_core_rtt_evidence_state_t {
            append("existing-rtt-state:" + withUnsafeBytes(of: value) {
                $0.map { String($0, radix: 16) }.joined(separator: ",")
            }); return
        }
        if path == "roundTripTime.producer" || path == "tierDemand.producer" {
            append("opaque-existing-producer"); return
        }

        if mirror.displayStyle == .enum {
            // No numeric payload is serialized through this tag; associated fields recurse.
            append("enum:" + (children.first?.label ?? String(describing: value)))
        } else if mirror.displayStyle == .collection || mirror.displayStyle == .tuple {
            append("ordered-count:\(children.count)")
        } else if mirror.displayStyle == .struct {
            append("struct-fields:" + children.map { $0.label ?? "<unlabelled>" }.joined(separator: ","))
        } else if children.isEmpty {
            throw ObservationError.unsupportedLeaf(path: path, type: String(reflecting: type(of: value)))
        } else {
            throw ObservationError.unsupportedLeaf(path: path, type: String(reflecting: type(of: value)))
        }
        for (index, child) in children.enumerated() {
            let label = child.label ?? "[\(index)]"
            let childPath = path.isEmpty ? label : path + "." + label
            try visit(child.value, path: childPath, anchor: anchor, into: &entries)
        }
    }
}
