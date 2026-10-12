import Foundation

// Test-only extraction of the pre-Rust queue algorithm, not a production fallback.
// Source: WorldwideScreenVideoAdaptationPolicy.swift SHA-256
// 6ce0ed8fd7a6010ce329aa36bcc9f4ce795f3a08e0ed3cf39a8d9ff4d0c30301.
enum FrozenPacketSendQueueReference {
    struct State: Equatable {
        var abi_version: UInt32 = 1
        var reserved: UInt32 = 0
        var packets_present: UInt32 = 0
        var delay_present: UInt32 = 0
        var low_present: UInt32 = 0
        var soft_present: UInt32 = 0
        var packets: UInt64 = 0
        var delay_bits: UInt64 = 0
        var pressure_count: UInt64 = 0
    }

    struct Event {
        var opcode: UInt32 = 0
        var packets_present: UInt32 = 0
        var delay_present: UInt32 = 0
        var rtt_inflated: UInt32 = 0
        var packets: UInt64 = 0
        var delay_bits: UInt64 = 0
        var low_age_seconds: Int64 = 0
        var low_age_attoseconds: Int64 = 0
        var soft_age_seconds: Int64 = 0
        var soft_age_attoseconds: Int64 = 0
    }

    struct Result: Equatable {
        var abi_version: UInt32 = 1
        var status: UInt32 = 0
        var observation: UInt32 = 0
        var low_action: UInt32 = 0
        var soft_action: UInt32 = 0
        var sample_inflated: UInt32 = 0
        var immediate: UInt32 = 0
        var inflated: UInt32 = 0
        var upgrade: UInt32 = 0
        var capacity_growth: UInt32 = 0
        var measured_delay_bits: UInt64 = 0
        var state = State()
    }

    private enum Observation {
        case unavailableOrReset
        case noNewPackets
        case measured(Double)

        var tag: UInt32 {
            switch self {
            case .unavailableOrReset: return 0
            case .noNewPackets: return 1
            case .measured: return 2
            }
        }

        var average: Double? {
            if case let .measured(delay) = self { return delay }
            return nil
        }
    }

    private static func fresh(seconds: Int64, attoseconds: Int64) -> Bool {
        let age = Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
        return age >= .zero && age <= .milliseconds(1_500)
    }

    private static func admitted(_ state: State, _ event: Event) -> Bool {
        guard state.abi_version == 1, state.reserved == 0,
              state.pressure_count <= UInt64(Int.max),
              [state.packets_present, state.delay_present, state.low_present, state.soft_present,
               event.packets_present, event.delay_present, event.rtt_inflated].allSatisfy({ $0 <= 1 }),
              state.packets_present == 1 || state.packets == 0,
              state.delay_present == 1 || state.delay_bits == 0,
              event.packets_present == 1 || event.packets == 0,
              event.delay_present == 1 || event.delay_bits == 0,
              event.opcode <= 4,
              event.low_age_attoseconds > -1_000_000_000_000_000_000,
              event.low_age_attoseconds < 1_000_000_000_000_000_000,
              event.soft_age_attoseconds > -1_000_000_000_000_000_000,
              event.soft_age_attoseconds < 1_000_000_000_000_000_000,
              state.low_present == 1 || (event.low_age_seconds == 0 && event.low_age_attoseconds == 0),
              state.soft_present == 1 || (event.soft_age_seconds == 0 && event.soft_age_attoseconds == 0)
        else { return false }
        switch event.opcode {
        case 0: return true
        case 1: return event.rtt_inflated == 0
        case 2, 3:
            return event.packets_present == 0 && event.delay_present == 0
                && event.rtt_inflated == 0 && event.low_age_seconds == 0
                && event.low_age_attoseconds == 0 && event.soft_age_seconds == 0
                && event.soft_age_attoseconds == 0
        case 4:
            return event.packets_present == 0 && event.delay_present == 0
                && event.rtt_inflated == 0 && event.soft_age_seconds == 0
                && event.soft_age_attoseconds == 0
        default: return false
        }
    }

    static func step(_ before: State, _ event: Event) -> Result {
        guard admitted(before, event) else { return Result() }
        var result = Result()
        result.status = 1
        result.state = before
        let lowFresh = before.low_present == 1
            && fresh(seconds: event.low_age_seconds, attoseconds: event.low_age_attoseconds)
        if event.opcode == 4 {
            result.upgrade = lowFresh ? 1 : 0
            return result
        }
        if event.opcode == 2 || event.opcode == 3 {
            result.state.pressure_count = 0
            result.state.low_present = 0
            result.state.soft_present = 0
            result.low_action = 1
            result.soft_action = 1
            if event.opcode == 3 {
                result.state.packets_present = 0
                result.state.delay_present = 0
                result.state.packets = 0
                result.state.delay_bits = 0
            }
            return result
        }

        let currentPackets: UInt64? = event.packets_present == 1 ? event.packets : nil
        let currentDelay: Double? = event.delay_present == 1 ? Double(bitPattern: event.delay_bits) : nil
        var previousPackets: UInt64? = before.packets_present == 1 ? before.packets : nil
        var previousDelay: Double? = before.delay_present == 1 ? Double(bitPattern: before.delay_bits) : nil
        let observation = observeCounters(packetsSent: currentPackets, totalDelay: currentDelay,
                                          previousPackets: &previousPackets, previousDelay: &previousDelay)
        result.state.packets_present = previousPackets == nil ? 0 : 1
        result.state.delay_present = previousDelay == nil ? 0 : 1
        result.state.packets = previousPackets ?? 0
        result.state.delay_bits = previousDelay?.bitPattern ?? 0
        result.observation = observation.tag
        let average = observation.average
        result.measured_delay_bits = average?.bitPattern ?? 0
        let sampleInflated = average.map { $0 > 0.100 } ?? false
        let immediate = average.map { $0 >= 0.200 } ?? false
        result.sample_inflated = sampleInflated ? 1 : 0
        result.immediate = immediate ? 1 : 0

        if event.opcode == 1 {
            let upgrade = average.map { $0 <= 0.020 } ?? (observation.tag == 1 && lowFresh)
            result.inflated = sampleInflated && (immediate || before.pressure_count >= 2) ? 1 : 0
            result.upgrade = upgrade ? 1 : 0
            result.capacity_growth = upgrade && lowFresh ? 1 : 0
            return result
        }

        let softFresh = before.soft_present == 1
            && fresh(seconds: event.soft_age_seconds, attoseconds: event.soft_age_attoseconds)
        switch observation {
        case .measured where sampleInflated && event.rtt_inflated == 0:
            if before.soft_present == 1 && !softFresh { result.state.pressure_count = 0 }
            if result.state.pressure_count < UInt64(Int.max) { result.state.pressure_count += 1 }
            result.state.soft_present = 1
            result.soft_action = 2
        case .noNewPackets where event.rtt_inflated == 0:
            if before.soft_present == 1 && !softFresh {
                result.state.pressure_count = 0
                result.state.soft_present = 0
                result.soft_action = 1
            }
        case .measured, .unavailableOrReset, .noNewPackets:
            result.state.pressure_count = 0
            result.state.soft_present = 0
            result.soft_action = 1
        }
        result.inflated = sampleInflated && (immediate || result.state.pressure_count >= 2) ? 1 : 0
        switch observation {
        case let .measured(delay):
            let low = delay <= 0.020
            result.state.low_present = low ? 1 : 0
            result.low_action = low ? 2 : 1
            result.upgrade = low ? 1 : 0
        case .noNewPackets:
            if before.low_present == 1 && !lowFresh {
                result.state.low_present = 0
                result.low_action = 1
            }
            result.upgrade = lowFresh ? 1 : 0
        case .unavailableOrReset:
            result.state.low_present = 0
            result.low_action = 1
        }
        return result
    }

    // The original validates the CURRENT value only. A fast baseline is deliberately raw.
    private static func observeCounters(packetsSent: UInt64?, totalDelay: Double?,
                                        previousPackets: inout UInt64?, previousDelay: inout Double?) -> Observation {
        guard let packetsSent, let totalDelay, totalDelay.isFinite, totalDelay >= 0 else {
            previousPackets = nil
            previousDelay = nil
            return .unavailableOrReset
        }
        defer {
            previousPackets = packetsSent
            previousDelay = totalDelay
        }
        guard let oldPackets = previousPackets, let oldDelay = previousDelay else {
            return .unavailableOrReset
        }
        guard packetsSent >= oldPackets, totalDelay >= oldDelay else { return .unavailableOrReset }
        guard packetsSent > oldPackets else {
            return totalDelay == oldDelay ? .noNewPackets : .unavailableOrReset
        }
        return .measured((totalDelay - oldDelay) / Double(packetsSent - oldPackets))
    }
}
