import BelugaCore
import WebRTCTransport

/// Rust owns RTT evidence. The adapter only copies telemetry, retains native clock instants,
/// verifies the actual exported result, and applies its clock action. There is no Swift fallback.
struct BelugaRustRoundTripTimeEvidence: Equatable, Sendable {
    typealias State = beluga_core_rtt_evidence_state_t
    typealias Event = beluga_core_rtt_evidence_event_t
    typealias Result = beluga_core_rtt_evidence_result_t
    typealias Measurement = beluga_core_rtt_evidence_measurement_t
    typealias Producer = @Sendable (State, Event) -> Result

    struct Evidence: Equatable, Sendable {
        let hasFreshPressure: Bool
        let allowsUpgrade: Bool
        let permitsLegacyMissingValue: Bool
        let validationDisposition: Int
        let primaryLeaseCurrent: Bool
        static let unavailable = Self(hasFreshPressure: false, allowsUpgrade: false,
            permitsLegacyMissingValue: false, validationDisposition: 6, primaryLeaseCurrent: false)
    }

    private(set) var rawState: State
    private(set) var lastAdvancement: ContinuousClock.Instant?
    private(set) var hasNativeFault = false
    private let producer: Producer
    // Immutable construction provenance, not a caller-supplied permission bit.
    // Ordinary copies and clocked imports retain this and the original closure.
    private let constructedWithCanonicalProducer: Bool

    init() {
        self.init(producer: { beluga_core_rtt_evidence_step($0, $1) }, canonicalOrigin: true)
    }
    init(producer: @escaping Producer) {
        self.init(producer: producer, canonicalOrigin: false)
    }
    private init(producer: @escaping Producer, canonicalOrigin: Bool) {
        var state = State()
        state.abi_version = 1
        state.disposition = 6
        state.permits_initial = 1
        rawState = state
        self.producer = producer
        constructedWithCanonicalProducer = canonicalOrigin
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        bytes(lhs.rawState) == bytes(rhs.rawState)
            && lhs.lastAdvancement == rhs.lastAdvancement
            && lhs.hasNativeFault == rhs.hasNativeFault
    }

    static func bytes<T>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value) { Array($0) }
    }

    static var layoutIsExact: Bool {
        MemoryLayout<UInt64>.size == 8 && UInt16(littleEndian: 1) == 1
            && MemoryLayout<Measurement>.size == 80 && MemoryLayout<Measurement>.stride == 80
            && MemoryLayout<Measurement>.alignment == 8
            && MemoryLayout<State>.size == 296 && MemoryLayout<State>.stride == 296
            && MemoryLayout<State>.alignment == 8
            && MemoryLayout<Event>.size == 128 && MemoryLayout<Event>.stride == 128
            && MemoryLayout<Event>.alignment == 8
            && MemoryLayout<Result>.size == 336 && MemoryLayout<Result>.stride == 336
            && MemoryLayout<Result>.alignment == 8
            && MemoryLayout<Measurement>.offset(of: \Measurement.fingerprint_words) == 0
            && MemoryLayout<Measurement>.offset(of: \Measurement.total_bits) == 64
            && MemoryLayout<Measurement>.offset(of: \Measurement.responses) == 72
            && MemoryLayout<State>.offset(of: \State.abi_version) == 0
            && MemoryLayout<State>.offset(of: \State.reserved) == 4
            && MemoryLayout<State>.offset(of: \State.baseline_present) == 8
            && MemoryLayout<State>.offset(of: \State.bootstrap_count) == 12
            && MemoryLayout<State>.offset(of: \State.disposition) == 16
            && MemoryLayout<State>.offset(of: \State.health) == 20
            && MemoryLayout<State>.offset(of: \State.uses_native) == 24
            && MemoryLayout<State>.offset(of: \State.provisional) == 28
            && MemoryLayout<State>.offset(of: \State.permits_initial) == 32
            && MemoryLayout<State>.offset(of: \State.distinct_count) == 36
            && MemoryLayout<State>.offset(of: \State.last_measured_present) == 40
            && MemoryLayout<State>.offset(of: \State.advancement_present) == 44
            && MemoryLayout<State>.offset(of: \State.age_present) == 48
            && MemoryLayout<State>.offset(of: \State.watermark_present) == 52
            && MemoryLayout<State>.offset(of: \State.fence_present) == 56
            && MemoryLayout<State>.offset(of: \State.fence_current_present) == 60
            && MemoryLayout<State>.offset(of: \State.reserved2) == 64
            && MemoryLayout<State>.offset(of: \State.reserved3) == 68
            && MemoryLayout<State>.offset(of: \State.baseline_bits) == 72
            && MemoryLayout<State>.offset(of: \State.last_measured_bits) == 80
            && MemoryLayout<State>.offset(of: \State.bootstrap_bits) == 88
            && MemoryLayout<State>.offset(of: \State.age_seconds) == 112
            && MemoryLayout<State>.offset(of: \State.age_attoseconds) == 120
            && MemoryLayout<State>.offset(of: \State.watermark) == 128
            && MemoryLayout<State>.offset(of: \State.fence) == 208
            && MemoryLayout<State>.offset(of: \State.fence_current_bits) == 288
            && MemoryLayout<Event>.offset(of: \Event.opcode) == 0
            && MemoryLayout<Event>.offset(of: \Event.observation_kind) == 4
            && MemoryLayout<Event>.offset(of: \Event.current_present) == 8
            && MemoryLayout<Event>.offset(of: \Event.fingerprint_length) == 12
            && MemoryLayout<Event>.offset(of: \Event.route_changed) == 16
            && MemoryLayout<Event>.offset(of: \Event.reserved) == 20
            && MemoryLayout<Event>.offset(of: \Event.current_bits) == 24
            && MemoryLayout<Event>.offset(of: \Event.measurement) == 32
            && MemoryLayout<Event>.offset(of: \Event.age_seconds) == 112
            && MemoryLayout<Event>.offset(of: \Event.age_attoseconds) == 120
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.fresh_pressure) == 8
            && MemoryLayout<Result>.offset(of: \Result.allows_upgrade) == 12
            && MemoryLayout<Result>.offset(of: \Result.legacy_missing) == 16
            && MemoryLayout<Result>.offset(of: \Result.clock_action) == 20
            && MemoryLayout<Result>.offset(of: \Result.validation_disposition) == 24
            && MemoryLayout<Result>.offset(of: \Result.primary_lease_current) == 28
            && MemoryLayout<Result>.offset(of: \Result.reserved) == 32
            && MemoryLayout<Result>.offset(of: \Result.reserved2) == 36
            && MemoryLayout<Result>.offset(of: \Result.state) == 40
    }

    var disposition: Int { hasNativeFault ? 6 : Int(rawState.disposition) }
    var health: Int { hasNativeFault ? 0 : Int(rawState.health) }
    var usesNative: Bool { hasNativeFault || rawState.uses_native == 1 }
    var baseline: Double? { hasNativeFault || rawState.baseline_present == 0 ? nil : Double(bitPattern: rawState.baseline_bits) }
    var bootstrap: [Double] {
        let values = rawState.bootstrap_bits
        return [values.0, values.1, values.2].prefix(Int(rawState.bootstrap_count)).map(Double.init(bitPattern:))
    }
    var provisional: Bool { !hasNativeFault && rawState.provisional == 1 }
    var distinctCount: Int { hasNativeFault ? 0 : Int(rawState.distinct_count) }
    var permitsInitial: Bool { !hasNativeFault && rawState.permits_initial == 1 }
    var watermark: Measurement? { rawState.watermark_present == 1 ? rawState.watermark : nil }
    var lastMeasured: Double? { rawState.last_measured_present == 1 ? Double(bitPattern: rawState.last_measured_bits) : nil }
    var observationAge: Duration? {
        rawState.age_present == 1
            ? Duration(secondsComponent: rawState.age_seconds, attosecondsComponent: rawState.age_attoseconds) : nil
    }

    private func event(_ opcode: UInt32, current: Double? = nil,
                       observation: WebRTCRoundTripTimeObservation? = nil,
                       routeChanged: Bool = false, at now: ContinuousClock.Instant) -> Event {
        var event = Event()
        event.opcode = opcode
        event.route_changed = routeChanged ? 1 : 0
        event.current_present = current == nil ? 0 : 1
        event.current_bits = current?.bitPattern ?? 0
        if let observation {
            switch observation {
            case .unavailable: event.observation_kind = 1
            case let .measurement(value):
                event.observation_kind = 2
                let bytes = Array(value.selectedCandidatePairFingerprint.utf8)
                event.fingerprint_length = UInt32(clamping: bytes.count)
                var words = [UInt64](repeating: 0, count: 8)
                if bytes.count <= 64 {
                    for (index, byte) in bytes.enumerated() {
                        words[index / 8] |= UInt64(byte) << UInt64((index % 8) * 8)
                    }
                }
                event.measurement.fingerprint_words = (words[0], words[1], words[2], words[3], words[4], words[5], words[6], words[7])
                event.measurement.total_bits = value.totalRoundTripTimeSeconds.bitPattern
                event.measurement.responses = value.responsesReceived
            }
        }
        if opcode == 0 || opcode == 1 || opcode == 10 || opcode == 12 {
            let age = lastAdvancement?.duration(to: now).components
            event.age_seconds = age?.seconds ?? 0
            event.age_attoseconds = age?.attoseconds ?? 0
        }
        return event
    }

    @discardableResult
    private mutating func apply(_ event: Event, at now: ContinuousClock.Instant) -> Evidence {
        guard !hasNativeFault else { return .unavailable }
        guard Self.layoutIsExact,
              rawState.advancement_present == (lastAdvancement == nil ? 0 : 1) else {
            hasNativeFault = true
            return .unavailable
        }
        let result = producer(rawState, event)
        guard beluga_core_rtt_evidence_result_is_valid(rawState, event, result) == 1 else {
            hasNativeFault = true
            return .unavailable
        }
        let stamp: ContinuousClock.Instant?
        switch result.clock_action {
        case 0: stamp = lastAdvancement
        case 1: stamp = nil
        case 2: stamp = now
        default: hasNativeFault = true; return .unavailable
        }
        guard result.state.advancement_present == (stamp == nil ? 0 : 1) else {
            hasNativeFault = true
            return .unavailable
        }
        rawState = result.state
        lastAdvancement = stamp
        return Evidence(hasFreshPressure: result.fresh_pressure == 1,
            allowsUpgrade: result.allows_upgrade == 1, permitsLegacyMissingValue: result.legacy_missing == 1,
            validationDisposition: Int(result.validation_disposition), primaryLeaseCurrent: result.primary_lease_current == 1)
    }

    mutating func observe(current: Double?, observation: WebRTCRoundTripTimeObservation?,
                          at now: ContinuousClock.Instant, fast: Bool = false,
                          routeChanged: Bool = false) -> Evidence {
        apply(event(fast ? 1 : 0, current: current, observation: fast ? (observation ?? .unavailable) : observation,
                    routeChanged: routeChanged, at: now), at: now)
    }

    mutating func age(at now: ContinuousClock.Instant) { apply(event(10, at: now), at: now) }
    mutating func revoke(hide: Bool = false) { apply(event(hide ? 3 : 2, at: .now), at: .now) }
    mutating func resetPath() { apply(event(4, at: .now), at: .now) }
    mutating func resetPeer() { apply(event(5, at: .now), at: .now) }
    mutating func inactive(observation: WebRTCRoundTripTimeObservation?) {
        apply(event(6, observation: observation ?? .unavailable, at: .now), at: .now)
    }
    mutating func allowInitial() { apply(event(7, at: .now), at: .now) }
    mutating func reordered() { apply(event(8, at: .now), at: .now) }
    mutating func strictUnordered() { apply(event(9, at: .now), at: .now) }

    /// Copies only a terminal denial; no result, clock or measurement can be imported here.
    mutating func retainFault(from other: Self) {
        if other.hasNativeFault { hasNativeFault = true }
    }

    mutating func copyFence(from other: Self) {
        guard !other.hasNativeFault else { hasNativeFault = true; return }
        var event = Event()
        event.opcode = 11
        event.observation_kind = other.rawState.fence_present == 1 ? 2 : 1
        if event.observation_kind == 2 {
            event.fingerprint_length = 64
            event.measurement = other.rawState.fence
            event.current_present = other.rawState.fence_current_present
            event.current_bits = other.rawState.fence_current_bits
        }
        apply(event, at: .now)
    }

    mutating func primaryLeaseIsCurrent(at now: ContinuousClock.Instant) -> Bool {
        apply(event(12, at: now), at: now).primaryLeaseCurrent
    }

    var publishedLeaseIsCurrent: Bool {
        mutating get {
            guard !hasNativeFault, rawState.age_present == 1 else { return false }
            var query = Event()
            query.opcode = 12
            query.age_seconds = rawState.age_seconds
            query.age_attoseconds = rawState.age_attoseconds
            return apply(query, at: .now).primaryLeaseCurrent
        }
    }
}

// Closed copied-value clocked import; no producer replacement or live publication.
extension BelugaRustRoundTripTimeEvidence {
    var networkAdaptationOwnerClockedApplicationIsAdmitted: Bool {
        hasNativeFault || constructedWithCanonicalProducer
    }
    // Pure pre-read admission for Hide's optional terminal-fault Q cut. Opcode3
    // has no time-dependent age. Do not call an arbitrary retained producer here.
    func networkAdaptationOwnerFaultAfterHideRead() throws -> Bool {
        if hasNativeFault { return true }
        guard constructedWithCanonicalProducer else { throw BelugaNetworkAdaptationOwnerError.malformedNativeImage }
        guard Self.layoutIsExact, rawState.advancement_present == (lastAdvancement == nil ? 0 : 1) else { return true }
        var e = Event(); e.opcode = 3
        let r = beluga_core_rtt_evidence_step(rawState, e)
        guard beluga_core_rtt_evidence_result_is_valid(rawState, e, r) == 1 else { return true }
        let present: UInt32
        switch r.clock_action {
        case 0: present = lastAdvancement == nil ? 0 : 1
        case 1: present = 0
        case 2: present = 1
        default: return true
        }
        return r.state.advancement_present != present
    }
    mutating func networkAdaptationOwnerImportClocked(_ p: BelugaNetworkAdaptationOwnerRTTImport) throws {
        guard !hasNativeFault || p.fault else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        if !p.fault {
            guard Self.layoutIsExact, p.state.advancement_present == (p.advancement == nil ? 0 : 1) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            // Reuse the canonical time-free RTT contract only as a healthy-domain
            // predicate. Discard its transformed state; never query the retained
            // producer, sample a clock, or normalize opaque sticky-fault words.
            var admission = Event(); admission.opcode = 3
            let checked = beluga_core_rtt_evidence_step(p.state, admission)
            guard beluga_core_rtt_evidence_result_is_valid(p.state, admission, checked) == 1 else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        // Opaque words are retained even under a sticky fault; no normalization.
        rawState = p.state; lastAdvancement = p.advancement; hasNativeFault = p.fault
    }
    #if DEBUG
    mutating func networkAdaptationOwnerSeedClockedMalformedRTT() { rawState.reserved = 1 }
    mutating func networkAdaptationOwnerSeedClockedRTTFault() { hasNativeFault = true }
    #endif
}

#if DEBUG
extension BelugaRustRoundTripTimeEvidence {
    // Fixed opaque words are deliberately not normalized through semantic getters.
    // This test-only stored image does not assert real producer reachability.
    mutating func networkAdaptationOwnerSeedFixedRegression(at anchor: ContinuousClock.Instant) {
        var r = rawState
        r.abi_version = 101; r.reserved = 102; r.baseline_present = 103; r.bootstrap_count = 104
        r.disposition = 105; r.health = 106; r.uses_native = 107; r.provisional = 108
        r.permits_initial = 109; r.distinct_count = 110; r.last_measured_present = 111
        r.advancement_present = 112; r.age_present = 113; r.watermark_present = 114
        r.fence_present = 115; r.fence_current_present = 116; r.reserved2 = 117; r.reserved3 = 118
        r.baseline_bits = 0x7ff8000000000001; r.last_measured_bits = 0x8000000000000000
        r.bootstrap_bits = (0x3ff0000000000000, 0x4000000000000000, 0x4008000000000000)
        r.age_seconds = -31; r.age_attoseconds = -375_000_000_000_000_000
        r.watermark.fingerprint_words = (1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008)
        r.watermark.total_bits = 0x7ff8000000000002; r.watermark.responses = 1009
        r.fence.fingerprint_words = (2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008)
        r.fence.total_bits = 0x7ff8000000000003; r.fence.responses = 2009
        r.fence_current_bits = 0x7ff8000000000004
        rawState = r; lastAdvancement = anchor.advanced(by: .milliseconds(-875)); hasNativeFault = true
    }
}
#endif

extension BelugaRustRoundTripTimeEvidence {
    // Read-only canonical-dependency admission, NOT replay of the policy reducer.
    // Opcode11 has no time-dependent age. No clock/producer call or mutation.
    // Unsupported retained producers are denied AT F, after the real703 prefix.
    func networkAdaptationOwnerFailureCopyFenceWillFault(from other: Self) throws -> Bool {
        if other.hasNativeFault || hasNativeFault { return true }
        guard constructedWithCanonicalProducer else { throw BelugaNetworkAdaptationOwnerError.malformedNativeImage }
        guard Self.layoutIsExact, rawState.advancement_present == (lastAdvancement == nil ? 0 : 1) else { return true }
        var event = Event(); event.opcode = 11
        event.observation_kind = other.rawState.fence_present == 1 ? 2 : 1
        if event.observation_kind == 2 {
            event.fingerprint_length = 64; event.measurement = other.rawState.fence
            event.current_present = other.rawState.fence_current_present
            event.current_bits = other.rawState.fence_current_bits
        }
        let result = beluga_core_rtt_evidence_step(rawState, event)
        guard beluga_core_rtt_evidence_result_is_valid(rawState, event, result) == 1 else { return true }
        let present: UInt32
        switch result.clock_action {
        case 0: present = lastAdvancement == nil ? 0 : 1
        case 1: present = 0
        case 2: present = 1
        default: return true
        }
        return result.state.advancement_present != present
    }
}
