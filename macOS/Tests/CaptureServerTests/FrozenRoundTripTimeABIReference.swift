import Foundation
import BelugaCore
import WebRTCTransport

/// Test-only DTO projection onto the independently frozen native preimage. ABI canonicality
/// follows CONTRACT v1; semantic decisions are delegated only to the frozen Swift reference.
enum FrozenRoundTripTimeABIReference {
    typealias M = beluga_core_rtt_evidence_measurement_t
    typealias S = beluga_core_rtt_evidence_state_t
    typealias E = beluga_core_rtt_evidence_event_t
    typealias O = beluga_core_rtt_evidence_result_t
    typealias R = FrozenRoundTripTimeReference

    static func initial() -> S {
        var state = S()
        state.abi_version = 1
        state.disposition = 6
        state.permits_initial = 1
        return state
    }

    static func step(_ before: S, _ event: E) -> O {
        var result = O()
        result.abi_version = 1
        result.validation_disposition = 6
        result.state = before
        guard valid(before), valid(event, before: before) else { return result }
        let anchor = ContinuousClock.now
        var reference = decode(before, anchor: anchor)
        let elapsed = Duration(secondsComponent: event.age_seconds,
                               attosecondsComponent: event.age_attoseconds)
        let observes = event.opcode == 0 || event.opcode == 1
        let now = observes && before.advancement_present == 1
            ? anchor.advanced(by: elapsed) : anchor
        let lease = before.advancement_present == 1
            && elapsed >= .zero && elapsed <= .seconds(4)
        var evidence = R.Evidence.unknown
        var validationDisposition: R.Disposition?
        var clockAction: UInt32 = 0
        switch event.opcode {
        case 0:
            evidence = reference.observeOrdinary(current: current(event),
                observation: observation(event), at: now)
            switch reference.disposition {
            case .provisionalHealthy, .freshHealthy, .freshInflated: clockAction = 2
            default: break
            }
        case 1:
            let evaluated = reference.observeCapacity(current: current(event),
                observation: observation(event), routeMatches: event.route_changed == 0,
                permitsSparseRequalification: false, at: now)
            evidence = evaluated.evidence
            validationDisposition = evaluated.validation.disposition
        case 2:
            reference.health = .unknown
            reference.disposition = .unavailable
        case 3: reference.invalidateObservation()
        case 4: reference.resetPath()
        case 5:
            _ = reference.bind(to: 0)
            clockAction = 1
        case 6: reference.hiddenReport(observation: observation(event))
        case 7: reference.permitsInitialReference = true
        case 8: reference.disposition = .reordered
        case 9:
            reference.health = .unknown
            reference.disposition = .unavailable
            reference.usesNativeEvidence = true
        case 10: reference.observationAge = before.advancement_present == 1 ? elapsed : nil
        case 11:
            var observed = R()
            if event.observation_kind == 2 {
                observed.fence = R.Fence(measurement: measurement(event.measurement),
                                         current: current(event))
            }
            reference.retainAdmittedFence(from: observed)
        case 12: break
        default: preconditionFailure("ABI validation admits only operations 0...12")
        }
        result.status = 1
        result.fresh_pressure = evidence.hasFreshPressure ? 1 : 0
        result.allows_upgrade = evidence.allowsUpgrade ? 1 : 0
        result.legacy_missing = evidence.permitsLegacyMissingValue ? 1 : 0
        result.clock_action = clockAction
        result.validation_disposition = disposition(validationDisposition ?? reference.disposition)
        if [UInt32(0), 1, 10, 12].contains(event.opcode) {
            result.primary_lease_current = lease ? 1 : 0
        }
        result.state = encode(reference)
        return result
    }

    static func encodeMeasurement(_ measurement: WebRTCRoundTripTimeMeasurement) -> M {
        var output = M()
        let bytes = Array(measurement.selectedCandidatePairFingerprint.utf8)
        var words = Array(repeating: UInt64(0), count: 8)
        for index in bytes.indices.prefix(64) {
            words[index / 8] |= UInt64(bytes[index]) << UInt64((index % 8) * 8)
        }
        output.fingerprint_words = (words[0], words[1], words[2], words[3],
                                    words[4], words[5], words[6], words[7])
        output.total_bits = measurement.totalRoundTripTimeSeconds.bitPattern
        output.responses = measurement.responsesReceived
        return output
    }

    static func measurement(_ raw: M) -> WebRTCRoundTripTimeMeasurement {
        .init(selectedCandidatePairFingerprint: String(decoding: fingerprintBytes(raw), as: UTF8.self),
              totalRoundTripTimeSeconds: Double(bitPattern: raw.total_bits),
              responsesReceived: raw.responses)
    }

    private static func current(_ event: E) -> Double? {
        event.current_present == 1 ? Double(bitPattern: event.current_bits) : nil
    }

    private static func observation(_ event: E) -> WebRTCRoundTripTimeObservation? {
        switch event.observation_kind {
        case 0: return nil
        case 1: return .unavailable
        default:
            let decoded = measurement(event.measurement)
            // Length is independent evidence: never authenticate a truncated oversize string.
            return .measurement(.init(selectedCandidatePairFingerprint:
                event.fingerprint_length == 64 ? decoded.selectedCandidatePairFingerprint : "",
                totalRoundTripTimeSeconds: decoded.totalRoundTripTimeSeconds,
                responsesReceived: decoded.responsesReceived))
        }
    }

    private static func decode(_ raw: S, anchor: ContinuousClock.Instant) -> R {
        var reference = R()
        reference.baseline = raw.baseline_present == 1 ? Double(bitPattern: raw.baseline_bits) : nil
        let bootstrap = [raw.bootstrap_bits.0, raw.bootstrap_bits.1, raw.bootstrap_bits.2]
        reference.bootstrap = bootstrap.prefix(Int(raw.bootstrap_count)).map(Double.init(bitPattern:))
        reference.disposition = disposition(raw.disposition)
        reference.health = raw.health == 1 ? .healthy : raw.health == 2 ? .inflated : .unknown
        reference.usesNativeEvidence = raw.uses_native == 1
        reference.referenceIsProvisional = raw.provisional == 1
        reference.permitsInitialReference = raw.permits_initial == 1
        reference.distinctHealthyReferenceCount = Int(raw.distinct_count)
        reference.lastMeasured = raw.last_measured_present == 1
            ? Double(bitPattern: raw.last_measured_bits) : nil
        reference.lastAdvancement = raw.advancement_present == 1 ? anchor : nil
        reference.observationAge = raw.age_present == 1
            ? Duration(secondsComponent: raw.age_seconds, attosecondsComponent: raw.age_attoseconds) : nil
        reference.watermark = raw.watermark_present == 1 ? measurement(raw.watermark) : nil
        if raw.fence_present == 1 {
            reference.fence = R.Fence(measurement: measurement(raw.fence), current:
                raw.fence_current_present == 1 ? Double(bitPattern: raw.fence_current_bits) : nil)
        }
        return reference
    }

    private static func encode(_ reference: R) -> S {
        var raw = S()
        raw.abi_version = 1
        raw.baseline_present = reference.baseline == nil ? 0 : 1
        raw.baseline_bits = reference.baseline?.bitPattern ?? 0
        raw.bootstrap_count = UInt32(reference.bootstrap.count)
        let bootstrap = reference.bootstrap.map(\.bitPattern)
            + Array(repeating: UInt64(0), count: 3 - reference.bootstrap.count)
        raw.bootstrap_bits = (bootstrap[0], bootstrap[1], bootstrap[2])
        raw.disposition = disposition(reference.disposition)
        raw.health = reference.health == .healthy ? 1 : reference.health == .inflated ? 2 : 0
        raw.uses_native = reference.usesNativeEvidence ? 1 : 0
        raw.provisional = reference.referenceIsProvisional ? 1 : 0
        raw.permits_initial = reference.permitsInitialReference ? 1 : 0
        raw.distinct_count = UInt32(reference.distinctHealthyReferenceCount)
        raw.last_measured_present = reference.lastMeasured == nil ? 0 : 1
        raw.last_measured_bits = reference.lastMeasured?.bitPattern ?? 0
        raw.advancement_present = reference.lastAdvancement == nil ? 0 : 1
        if let age = reference.observationAge {
            raw.age_present = 1
            raw.age_seconds = age.components.seconds
            raw.age_attoseconds = age.components.attoseconds
        }
        if let watermark = reference.watermark {
            raw.watermark_present = 1
            raw.watermark = encodeMeasurement(watermark)
        }
        if let fence = reference.fence {
            raw.fence_present = 1
            raw.fence = encodeMeasurement(fence.measurement)
            raw.fence_current_present = fence.current == nil ? 0 : 1
            raw.fence_current_bits = fence.current?.bitPattern ?? 0
        }
        return raw
    }

    private static func disposition(_ value: R.Disposition) -> UInt32 {
        switch value {
        case .legacy: return 0
        case .provisionalHealthy: return 1
        case .freshHealthy: return 2
        case .freshInflated: return 3
        case .retainedHealthy: return 4
        case .retainedInflated: return 5
        case .unavailable: return 6
        case .expired: return 7
        case .reseeded: return 8
        case .reordered: return 9
        }
    }

    private static func disposition(_ value: UInt32) -> R.Disposition {
        [.legacy, .provisionalHealthy, .freshHealthy, .freshInflated, .retainedHealthy,
         .retainedInflated, .unavailable, .expired, .reseeded, .reordered][Int(value)]
    }

    private static func fingerprintBytes(_ raw: M) -> [UInt8] {
        let words = [raw.fingerprint_words.0, raw.fingerprint_words.1, raw.fingerprint_words.2,
                     raw.fingerprint_words.3, raw.fingerprint_words.4, raw.fingerprint_words.5,
                     raw.fingerprint_words.6, raw.fingerprint_words.7]
        return words.flatMap { word in (0..<8).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    }

    private static func positive(_ bits: UInt64) -> Bool {
        let value = Double(bitPattern: bits)
        return value.isFinite && value > 0
    }

    private static func valid(_ raw: M) -> Bool {
        let total = Double(bitPattern: raw.total_bits)
        return fingerprintBytes(raw).allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        } && total.isFinite && total >= 0
    }

    private static func zero(_ raw: M) -> Bool {
        fingerprintBytes(raw).allSatisfy { $0 == 0 } && raw.total_bits == 0 && raw.responses == 0
    }

    private static func validAge(_ seconds: Int64, _ attoseconds: Int64) -> Bool {
        attoseconds > -1_000_000_000_000_000_000 && attoseconds < 1_000_000_000_000_000_000
            && !(seconds > 0 && attoseconds < 0) && !(seconds < 0 && attoseconds > 0)
    }

    private static func valid(_ state: S) -> Bool {
        let flags = [state.baseline_present, state.uses_native, state.provisional,
            state.permits_initial, state.last_measured_present, state.advancement_present,
            state.age_present, state.watermark_present, state.fence_present, state.fence_current_present]
        guard state.abi_version == 1, state.reserved == 0, state.reserved2 == 0,
              state.reserved3 == 0, flags.allSatisfy({ $0 <= 1 }), state.bootstrap_count <= 2,
              state.distinct_count <= 3, state.disposition <= 9, state.health <= 2,
              state.baseline_present == 1 ? positive(state.baseline_bits) : state.baseline_bits == 0,
              state.last_measured_present == 1 ? positive(state.last_measured_bits) : state.last_measured_bits == 0 else {
            return false
        }
        let samples = [state.bootstrap_bits.0, state.bootstrap_bits.1, state.bootstrap_bits.2]
        for (index, bits) in samples.enumerated() {
            if index < Int(state.bootstrap_count) { if !positive(bits) { return false } }
            else if bits != 0 { return false }
        }
        guard validAge(state.age_seconds, state.age_attoseconds) else { return false }
        if state.age_present == 0 && (state.age_seconds != 0 || state.age_attoseconds != 0) { return false }
        if state.watermark_present == 1 ? !valid(state.watermark) : !zero(state.watermark) { return false }
        if state.fence_present == 1 ? !valid(state.fence) : !zero(state.fence) { return false }
        if state.fence_present == 0 && state.fence_current_present != 0 { return false }
        if state.fence_current_present == 1 ? !positive(state.fence_current_bits) : state.fence_current_bits != 0 {
            return false
        }
        return true
    }

    private static func valid(_ event: E, before: S) -> Bool {
        guard event.opcode <= 12, event.observation_kind <= 2, event.current_present <= 1,
              event.route_changed <= 1, event.reserved == 0,
              event.current_present == 1 || event.current_bits == 0,
              event.observation_kind == 2 || (event.fingerprint_length == 0 && zero(event.measurement)),
              event.opcode == 1 || event.route_changed == 0,
              validAge(event.age_seconds, event.age_attoseconds) else { return false }
        let ageUsed = [UInt32(0), 1, 10, 12].contains(event.opcode) && before.advancement_present == 1
        if !ageUsed && (event.age_seconds != 0 || event.age_attoseconds != 0) { return false }
        switch event.opcode {
        case 0, 1: return true
        case 6: return event.observation_kind == 1 || event.observation_kind == 2
        case 11:
            if event.observation_kind == 1 { return event.current_present == 0 }
            return event.observation_kind == 2 && event.fingerprint_length == 64
                && valid(event.measurement) && (event.current_present == 0 || positive(event.current_bits))
        default: return event.observation_kind == 0 && event.current_present == 0
        }
    }
}
