import BelugaCore

enum FrozenPinnedPacketSendQueueObservation: Equatable, Sendable {
    case measured(Double)
    case noNewPackets
    case unavailableOrReset
}

struct FrozenPinnedPacketSendQueueProducer: Sendable {
    typealias State = beluga_core_packet_send_queue_state_t
    typealias Event = beluga_core_packet_send_queue_event_t
    typealias Result = beluga_core_packet_send_queue_result_t
    let step: @Sendable (State, Event) -> Result
    static let actual = Self(step: { beluga_core_packet_send_queue_step($0, $1) })
}

enum FrozenPinnedPacketSendQueueBoundary {
    typealias State = FrozenPinnedPacketSendQueueProducer.State
    typealias Event = FrozenPinnedPacketSendQueueProducer.Event
    typealias Result = FrozenPinnedPacketSendQueueProducer.Result

    static var layoutIsExact: Bool {
        MemoryLayout<Int>.size == 8
            && MemoryLayout<State>.size == 48 && MemoryLayout<State>.stride == 48
            && MemoryLayout<State>.alignment == 8
            && MemoryLayout<Event>.size == 64 && MemoryLayout<Event>.stride == 64
            && MemoryLayout<Event>.alignment == 8
            && MemoryLayout<Result>.size == 96 && MemoryLayout<Result>.stride == 96
            && MemoryLayout<Result>.alignment == 8
            && MemoryLayout<State>.offset(of: \State.abi_version) == 0
            && MemoryLayout<State>.offset(of: \State.reserved) == 4
            && MemoryLayout<State>.offset(of: \State.packets_present) == 8
            && MemoryLayout<State>.offset(of: \State.delay_present) == 12
            && MemoryLayout<State>.offset(of: \State.low_present) == 16
            && MemoryLayout<State>.offset(of: \State.soft_present) == 20
            && MemoryLayout<State>.offset(of: \State.packets) == 24
            && MemoryLayout<State>.offset(of: \State.delay_bits) == 32
            && MemoryLayout<State>.offset(of: \State.pressure_count) == 40
            && MemoryLayout<Event>.offset(of: \Event.opcode) == 0
            && MemoryLayout<Event>.offset(of: \Event.packets_present) == 4
            && MemoryLayout<Event>.offset(of: \Event.delay_present) == 8
            && MemoryLayout<Event>.offset(of: \Event.rtt_inflated) == 12
            && MemoryLayout<Event>.offset(of: \Event.packets) == 16
            && MemoryLayout<Event>.offset(of: \Event.delay_bits) == 24
            && MemoryLayout<Event>.offset(of: \Event.low_age_seconds) == 32
            && MemoryLayout<Event>.offset(of: \Event.low_age_attoseconds) == 40
            && MemoryLayout<Event>.offset(of: \Event.soft_age_seconds) == 48
            && MemoryLayout<Event>.offset(of: \Event.soft_age_attoseconds) == 56
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.observation) == 8
            && MemoryLayout<Result>.offset(of: \Result.low_action) == 12
            && MemoryLayout<Result>.offset(of: \Result.soft_action) == 16
            && MemoryLayout<Result>.offset(of: \Result.sample_inflated) == 20
            && MemoryLayout<Result>.offset(of: \Result.immediate) == 24
            && MemoryLayout<Result>.offset(of: \Result.inflated) == 28
            && MemoryLayout<Result>.offset(of: \Result.upgrade) == 32
            && MemoryLayout<Result>.offset(of: \Result.capacity_growth) == 36
            && MemoryLayout<Result>.offset(of: \Result.measured_delay_bits) == 40
            && MemoryLayout<Result>.offset(of: \Result.state) == 48
    }

    static func same(_ lhs: State, _ rhs: State) -> Bool {
        lhs.abi_version == rhs.abi_version && lhs.reserved == rhs.reserved
            && lhs.packets_present == rhs.packets_present && lhs.delay_present == rhs.delay_present
            && lhs.low_present == rhs.low_present && lhs.soft_present == rhs.soft_present
            && lhs.packets == rhs.packets && lhs.delay_bits == rhs.delay_bits
            && lhs.pressure_count == rhs.pressure_count
    }

    private static func fresh(_ seconds: Int64, _ attoseconds: Int64) -> Bool {
        // Exact Duration components; this is rejection-only correlation, not a fallback lease.
        let age = Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
        return age >= .zero && age <= .milliseconds(1_500)
    }

    /// Reject copied results that do not correlate with this exact input. Never synthesize a
    /// successful result when Rust is unavailable or malformed.
    static func accepts(_ before: State, _ event: Event, _ result: Result) -> Bool {
        guard layoutIsExact, before.abi_version == 1, before.reserved == 0,
              result.abi_version == 1, result.status == 1, event.opcode <= 4,
              before.pressure_count <= UInt64(Int.max),
              [before.packets_present, before.delay_present, before.low_present, before.soft_present,
               event.packets_present, event.delay_present, event.rtt_inflated].allSatisfy({ $0 <= 1 }),
              [event.low_age_attoseconds, event.soft_age_attoseconds].allSatisfy({
                  $0 > -1_000_000_000_000_000_000 && $0 < 1_000_000_000_000_000_000
              }),
              before.packets_present == 1 || before.packets == 0,
              before.delay_present == 1 || before.delay_bits == 0,
              event.packets_present == 1 || event.packets == 0,
              event.delay_present == 1 || event.delay_bits == 0,
              before.low_present == 1 || (event.low_age_seconds == 0 && event.low_age_attoseconds == 0),
              before.soft_present == 1 || (event.soft_age_seconds == 0 && event.soft_age_attoseconds == 0)
        else { return false }
        let lowFresh = before.low_present == 1 && fresh(event.low_age_seconds, event.low_age_attoseconds)
        let softFresh = before.soft_present == 1 && fresh(event.soft_age_seconds, event.soft_age_attoseconds)
        var next = before
        var observation: UInt32 = 0
        var lowAction: UInt32 = 0
        var softAction: UInt32 = 0
        var average: Double?
        var sampleInflated = false
        var immediate = false
        var inflated = false
        var upgrade = false
        var capacityGrowth = false
        if event.opcode >= 2 {
            guard event.packets_present == 0, event.delay_present == 0,
                  event.rtt_inflated == 0 else { return false }
            if event.opcode == 4 {
                guard event.soft_age_seconds == 0, event.soft_age_attoseconds == 0 else { return false }
                upgrade = lowFresh
            } else {
                guard event.low_age_seconds == 0, event.low_age_attoseconds == 0,
                      event.soft_age_seconds == 0, event.soft_age_attoseconds == 0 else { return false }
                next.low_present = 0; next.soft_present = 0; next.pressure_count = 0
                lowAction = 1; softAction = 1
                if event.opcode == 3 {
                    next.packets_present = 0; next.delay_present = 0
                    next.packets = 0; next.delay_bits = 0
                }
            }
        } else {
            guard event.opcode == 0 || event.rtt_inflated == 0 else { return false }
            let delay = Double(bitPattern: event.delay_bits)
            if event.packets_present == 1, event.delay_present == 1,
               delay.isFinite, delay >= 0 {
                if before.packets_present == 1, before.delay_present == 1 {
                    let previous = Double(bitPattern: before.delay_bits)
                    if event.packets >= before.packets, delay >= previous {
                        if event.packets > before.packets {
                            observation = 2
                            average = (delay - previous) / Double(event.packets - before.packets)
                        } else if delay == previous {
                            observation = 1
                        }
                    }
                }
                next.packets_present = 1; next.delay_present = 1
                next.packets = event.packets; next.delay_bits = event.delay_bits
            } else {
                next.packets_present = 0; next.delay_present = 0
                next.packets = 0; next.delay_bits = 0
            }
            sampleInflated = average.map { $0 > 0.100 } ?? false
            immediate = average.map { $0 >= 0.200 } ?? false
            if event.opcode == 1 {
                upgrade = average.map { $0 <= 0.020 } ?? (observation == 1 && lowFresh)
                inflated = sampleInflated && (immediate || next.pressure_count >= 2)
                capacityGrowth = lowFresh && upgrade
            } else {
                if observation == 2, sampleInflated, event.rtt_inflated == 0 {
                    next.pressure_count = min(softFresh || before.soft_present == 0 ? before.pressure_count : 0,
                                              UInt64(Int.max) - 1) + 1
                    softAction = 2; next.soft_present = 1
                } else if observation == 1, event.rtt_inflated == 0 {
                    if before.soft_present == 1, !softFresh {
                        next.pressure_count = 0; next.soft_present = 0; softAction = 1
                    }
                } else {
                    next.pressure_count = 0; next.soft_present = 0; softAction = 1
                }
                inflated = sampleInflated && (immediate || next.pressure_count >= 2)
                if let average {
                    upgrade = average <= 0.020
                    next.low_present = upgrade ? 1 : 0; lowAction = upgrade ? 2 : 1
                } else if observation == 1 {
                    upgrade = lowFresh
                    if before.low_present == 1, !lowFresh {
                        next.low_present = 0; lowAction = 1
                    }
                } else {
                    next.low_present = 0; lowAction = 1
                }
            }
        }
        return same(result.state, next) && result.observation == observation
            && result.low_action == lowAction && result.soft_action == softAction
            && result.measured_delay_bits == (average?.bitPattern ?? 0)
            && result.sample_inflated == (sampleInflated ? 1 : 0)
            && result.immediate == (immediate ? 1 : 0)
            && result.inflated == (inflated ? 1 : 0)
            && result.upgrade == (upgrade ? 1 : 0)
            && result.capacity_growth == (capacityGrowth ? 1 : 0)
    }
}

/// Rust owns queue decisions. Swift retains only native clock instants and copied state.
struct FrozenPinnedPacketSendQueue: Equatable, Sendable {
    struct Decision: Equatable, Sendable {
        let observation: FrozenPinnedPacketSendQueueObservation
        let sampleIsInflated: Bool
        let requiresImmediateResponse: Bool
        let isInflated: Bool
        let allowsUpgrade: Bool
        let allowsCapacityGrowth: Bool
        static let unavailable = Self(observation: .unavailableOrReset, sampleIsInflated: false,
            requiresImmediateResponse: false, isInflated: false, allowsUpgrade: false,
            allowsCapacityGrowth: false)
    }

    private(set) var packets: UInt64?
    private(set) var delayBits: UInt64?
    private(set) var pressureCount = 0
    private(set) var lowObservation: ContinuousClock.Instant?
    private(set) var softObservation: ContinuousClock.Instant?
    private(set) var faulted = false

    var raw: FrozenPinnedPacketSendQueueProducer.State {
        .init(abi_version: 1, reserved: 0, packets_present: packets == nil ? 0 : 1,
              delay_present: delayBits == nil ? 0 : 1, low_present: lowObservation == nil ? 0 : 1,
              soft_present: softObservation == nil ? 0 : 1, packets: packets ?? 0,
              delay_bits: delayBits ?? 0, pressure_count: UInt64(pressureCount))
    }

    private func event(_ opcode: UInt32, packets: UInt64?, delay: Double?,
                       rttInflated: Bool, at now: ContinuousClock.Instant) -> FrozenPinnedPacketSendQueueProducer.Event {
        let low = (opcode < 2 || opcode == 4) ? lowObservation?.duration(to: now).components : nil
        let soft = opcode < 2 ? softObservation?.duration(to: now).components : nil
        return .init(opcode: opcode, packets_present: packets == nil ? 0 : 1,
            delay_present: delay == nil ? 0 : 1, rtt_inflated: rttInflated ? 1 : 0,
            packets: packets ?? 0, delay_bits: delay?.bitPattern ?? 0,
            low_age_seconds: low?.seconds ?? 0, low_age_attoseconds: low?.attoseconds ?? 0,
            soft_age_seconds: soft?.seconds ?? 0, soft_age_attoseconds: soft?.attoseconds ?? 0)
    }

    mutating func observe(packets: UInt64?, delay: Double?, rttInflated: Bool,
                          at now: ContinuousClock.Instant,
                          producer: FrozenPinnedPacketSendQueueProducer = .actual) -> Decision {
        apply(raw, event(0, packets: packets, delay: delay, rttInflated: rttInflated, at: now),
              at: now, producer: producer)
    }

    func capacityObservation(previousPackets: UInt64?, previousDelay: Double?,
                             packets: UInt64?, delay: Double?, at now: ContinuousClock.Instant,
                             producer: FrozenPinnedPacketSendQueueProducer = .actual) -> Decision {
        guard !faulted else { return .unavailable }
        var before = raw
        before.packets_present = previousPackets == nil ? 0 : 1
        before.delay_present = previousDelay == nil ? 0 : 1
        before.packets = previousPackets ?? 0; before.delay_bits = previousDelay?.bitPattern ?? 0
        let event = event(1, packets: packets, delay: delay, rttInflated: false, at: now)
        let result = producer.step(before, event)
        guard FrozenPinnedPacketSendQueueBoundary.accepts(before, event, result) else { return .unavailable }
        return Self.decision(result)
    }

    mutating func reset(path: Bool, at now: ContinuousClock.Instant = .now,
                        producer: FrozenPinnedPacketSendQueueProducer = .actual) {
        _ = apply(raw, event(path ? 3 : 2, packets: nil, delay: nil, rttInflated: false, at: now),
                  at: now, producer: producer)
    }

    func lowLeaseIsFresh(at now: ContinuousClock.Instant) -> Bool {
        guard !faulted else { return false }
        let event = event(4, packets: nil, delay: nil, rttInflated: false, at: now)
        let result = FrozenPinnedPacketSendQueueProducer.actual.step(raw, event)
        return FrozenPinnedPacketSendQueueBoundary.accepts(raw, event, result) && result.upgrade == 1
    }

    private mutating func apply(_ before: FrozenPinnedPacketSendQueueProducer.State,
                               _ event: FrozenPinnedPacketSendQueueProducer.Event,
                               at now: ContinuousClock.Instant,
                               producer: FrozenPinnedPacketSendQueueProducer) -> Decision {
        guard !faulted else { return .unavailable }
        let result = producer.step(before, event)
        guard FrozenPinnedPacketSendQueueBoundary.accepts(before, event, result) else {
            packets = nil; delayBits = nil; pressureCount = 0
            lowObservation = nil; softObservation = nil; faulted = true
            return .unavailable
        }
        packets = result.state.packets_present == 1 ? result.state.packets : nil
        delayBits = result.state.delay_present == 1 ? result.state.delay_bits : nil
        pressureCount = Int(result.state.pressure_count)
        if result.low_action == 1 { lowObservation = nil }
        if result.low_action == 2 { lowObservation = now }
        if result.soft_action == 1 { softObservation = nil }
        if result.soft_action == 2 { softObservation = now }
        return Self.decision(result)
    }

    private static func decision(_ result: FrozenPinnedPacketSendQueueProducer.Result) -> Decision {
        let observation: FrozenPinnedPacketSendQueueObservation
        switch result.observation {
        case 2: observation = .measured(Double(bitPattern: result.measured_delay_bits))
        case 1: observation = .noNewPackets
        default: observation = .unavailableOrReset
        }
        return .init(observation: observation, sampleIsInflated: result.sample_inflated == 1,
            requiresImmediateResponse: result.immediate == 1, isInflated: result.inflated == 1,
            allowsUpgrade: result.upgrade == 1, allowsCapacityGrowth: result.capacity_growth == 1)
    }
}
