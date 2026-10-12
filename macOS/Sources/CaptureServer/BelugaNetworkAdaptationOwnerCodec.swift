// Rust proposal boundary is unwired; immutable OwnerValue is the native actor's storage.
// Clocked lifecycle reads are lazy at admitted original cuts, never effect authority.
import BelugaCore
import WebRTCTransport

/// A copied real Swift value, not a second live Rust owner. Dependency producers stay
/// inside `policy`; they are neither queried by capture nor reconstructed from atoms.
struct BelugaNetworkAdaptationOwnerValue {
    enum Lane: UInt64 { case fastSender = 0, ordinaryFallback = 1 }
    let policy: WorldwideScreenVideoAdaptationPolicy
    let revision: UInt64
    let fastStatisticsAvailable: Bool
    let lane: Lane?
    let evidenceTime: ContinuousClock.Instant?
    let minimumCollectionSequence: UInt64?
    let applied: WorldwideScreenVideoEncodingRecommendation?
}

enum BelugaNetworkAdaptationOwnerError: Error {
    case unsupportedLayout, unrepresentableTime, malformedNativeImage
    case reentry, invocationExhausted, refused, invalidResult
}

/// Mechanical signed128 Duration encoding, supported on macOS14/iOS17. No clock read.
private struct OwnerAttoseconds {
    let high: Int64
    let low: UInt64
    init(_ duration: Duration) {
        let p = duration.components
        let scaled = p.seconds.multipliedFullWidth(by: 1_000_000_000_000_000_000)
        let (low, carry) = scaled.low.addingReportingOverflow(UInt64(bitPattern: p.attoseconds))
        self.low = low
        high = Int64(bitPattern: UInt64(bitPattern: scaled.high)
            &+ (p.attoseconds < 0 ? UInt64.max : 0) &+ (carry ? 1 : 0))
    }
    var fitsCodecTime: Bool {
        let unit: UInt64 = 1_000_000_000_000_000_000
        let negative = high < 0
        let magnitude: (high: UInt64, low: UInt64)
        if negative {
            let (l, carry) = (~low).addingReportingOverflow(1)
            magnitude = (~UInt64(bitPattern: high) &+ (carry ? 1 : 0), l)
        } else { magnitude = (UInt64(bitPattern: high), low) }
        guard magnitude.high < unit else { return false }
        let quotient = unit.dividingFullWidth(magnitude).quotient
        return quotient <= UInt64(Int64.max) + (negative ? 1 : 0)
    }
}

/// Only the proposed same-file capture seams use this append-only writer. There is
/// no inverse full179 setter. Signed and IEEE payloads are copied without normalization.
struct BelugaNetworkAdaptationOwnerWriter {
    typealias Atom = beluga_core_adaptation_state_atom_t
    private(set) var atoms: [Atom] = []
    let anchor: ContinuousClock.Instant?
    mutating func word(_ kind: UInt32, _ payload: UInt64?) {
        atoms.append(.init(kind: kind, present: payload == nil ? 0 : 1, high: 0, low: payload ?? 0))
    }
    mutating func integer(_ value: Int?) { word(2, value.map { UInt64(bitPattern: Int64($0)) }) }
    mutating func signed(_ value: Int64) { word(2, UInt64(bitPattern: value)) }
    mutating func unsigned(_ value: UInt64?) { word(1, value) }
    mutating func scalar(_ value: Double?) { word(3, value?.bitPattern) }
    mutating func bits(_ value: UInt64?) { word(3, value) }
    mutating func boolean(_ value: Bool?) { word(4, value.map { $0 ? 1 : 0 }) }
    mutating func byte(_ value: UInt8) { word(5, UInt64(value)) }
    mutating func u32(_ value: UInt32) { word(6, UInt64(value)) }
    mutating func tier(_ value: WorldwideScreenVideoAdaptationTier?) { word(7, value.map { UInt64($0.rawValue) }) }
    mutating func time(_ value: ContinuousClock.Instant?) throws {
        guard let value else { atoms.append(.init(kind: 10, present: 0, high: 0, low: 0)); return }
        guard let anchor else { throw BelugaNetworkAdaptationOwnerError.unrepresentableTime }
        let relative = OwnerAttoseconds(anchor.duration(to: value))
        guard relative.fitsCodecTime else { throw BelugaNetworkAdaptationOwnerError.unrepresentableTime }
        atoms.append(.init(kind: 10, present: 1, high: relative.high, low: relative.low))
    }
    mutating func measurement(_ value: beluga_core_rtt_evidence_measurement_t) {
        let f = value.fingerprint_words
        for word in [f.0, f.1, f.2, f.3, f.4, f.5, f.6, f.7] { unsigned(word) }
        bits(value.total_bits); unsigned(value.responses)
    }
}

/// Captures native custody, not just route presence or relative coordinates.
struct BelugaNetworkAdaptationOwnerSnapshot {
    typealias Atom = beluga_core_adaptation_state_atom_t
    let value: BelugaNetworkAdaptationOwnerValue
    let atoms: [Atom]
    let times: [ContinuousClock.Instant?]
    let anchor: ContinuousClock.Instant?
    let route: WebRTCICERouteDiagnostics?
    private init(value: BelugaNetworkAdaptationOwnerValue, atoms: [Atom],
        times: [ContinuousClock.Instant?], anchor: ContinuousClock.Instant?, route: WebRTCICERouteDiagnostics?) {
        self.value = value; self.atoms = atoms; self.times = times; self.anchor = anchor; self.route = route
    }
    static func capture(_ value: BelugaNetworkAdaptationOwnerValue,
        retainingAnchor: ContinuousClock.Instant? = nil) throws -> Self {
        guard MemoryLayout<Int>.size == 8 else { throw BelugaNetworkAdaptationOwnerError.unsupportedLayout }
        var times = value.policy.networkAdaptationOwnerNativeTimes
        guard times.count == 13, times[9] == nil, times[10] == nil, times[11] == nil, times[12] == nil else {
            throw BelugaNetworkAdaptationOwnerError.malformedNativeImage
        }
        times[12] = value.evidenceTime
        let anchor = retainingAnchor ?? times.compactMap { $0 }.first
        var w = BelugaNetworkAdaptationOwnerWriter(anchor: anchor)
        try value.policy.networkAdaptationOwnerWrite(into: &w)
        guard w.atoms.count == 168 else { throw BelugaNetworkAdaptationOwnerError.malformedNativeImage }
        w.unsigned(value.revision); w.boolean(value.fastStatisticsAvailable); w.word(8, value.lane?.rawValue)
        try w.time(value.evidenceTime); w.unsigned(value.minimumCollectionSequence)
        w.boolean(value.applied != nil)
        w.tier(value.applied?.tier); w.integer(value.applied?.maximumBitrateBps)
        w.integer(value.applied?.maximumTotalRTPBitrateBps); w.integer(value.applied?.maximumFramesPerSecond)
        w.scalar(value.applied?.scaleResolutionDownBy)
        guard w.atoms.count == 179 else { throw BelugaNetworkAdaptationOwnerError.malformedNativeImage }
        return Self(value: value, atoms: w.atoms, times: times, anchor: anchor, route: value.policy.selectedRoute)
    }
    static func equalAtoms(_ a: [Atom], _ b: [Atom]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { pair in
            pair.0.kind == pair.1.kind && pair.0.present == pair.1.present
                && pair.0.high == pair.1.high && pair.0.low == pair.1.low
        }
    }
}

/// Mechanical sender-report capture only. This value grants no entry/clock,
/// producer, Prepared222, actor, or native-effect authority.
struct BelugaNetworkAdaptationOwnerReportSnapshot {
    typealias Wire = beluga_core_adaptation_owner_report_t
    let report: WebRTCScreenVideoStatisticsReport
    let incomingRoute: WebRTCICERouteDiagnostics?
    let retainedRoute: WebRTCICERouteDiagnostics?
    let wire: Wire

    private init(report: WebRTCScreenVideoStatisticsReport,
        incomingRoute: WebRTCICERouteDiagnostics?, retainedRoute: WebRTCICERouteDiagnostics?, wire: Wire) {
        self.report = report; self.incomingRoute = incomingRoute
        self.retainedRoute = retainedRoute; self.wire = wire
    }

    static func capture(_ report: WebRTCScreenVideoStatisticsReport,
        retainingRoute: WebRTCICERouteDiagnostics?) throws -> Self {
        let wire = try captureWire(report.nativeSnapshot,
            timestamp: report.nativeReportTimestampMicroseconds, retainingRoute: retainingRoute)
        return Self(report: report, incomingRoute: report.nativeSnapshot.route,
            retainedRoute: retainingRoute, wire: wire)
    }

    // General501 also consumes ordinary snapshots whose native UTC is genuinely
    // absent. Do not manufacture a fast-report DTO or a timestamp for that lane.
    fileprivate static func captureWire(_ snapshot: WebRTCStatisticsSnapshot,
        timestamp: Double?, retainingRoute: WebRTCICERouteDiagnostics?) throws -> Wire {
        guard MemoryLayout<Wire>.size == 192, MemoryLayout<Wire>.stride == 192,
              MemoryLayout<Wire>.alignment == 8 else {
            throw BelugaNetworkAdaptationOwnerError.unsupportedLayout
        }
        var wire = Wire()
        // Genuine501 replaces peer/capture/automatic-suspension from entry facts.
        // Regular forces strict=true; Capacity retains zero and does not use it.
        // This telemetry copy grants none of that separate entry authority.
        wire.incoming_present = snapshot.route == nil ? 0 : 1
        wire.equal_to_retained = snapshot.route == retainingRoute ? 1 : 0
        wire.collection_sequence_present = snapshot.collectionSequence == nil ? 0 : 1
        wire.collection_sequence = snapshot.collectionSequence ?? 0
        wire.bandwidth_present = snapshot.availableOutgoingBitrate == nil ? 0 : 1
        wire.bandwidth_bits = snapshot.availableOutgoingBitrate?.bitPattern ?? 0
        wire.current_rtt_present = snapshot.currentRoundTripTime == nil ? 0 : 1
        wire.current_rtt_bits = snapshot.currentRoundTripTime?.bitPattern ?? 0
        wire.packets_present = snapshot.outboundVideo?.packets == nil ? 0 : 1
        wire.packets = snapshot.outboundVideo?.packets ?? 0
        wire.delay_present = snapshot.outboundVideo?.totalPacketSendDelay == nil ? 0 : 1
        wire.delay_bits = snapshot.outboundVideo?.totalPacketSendDelay?.bitPattern ?? 0
        // UTC identity is telemetry, not monotonic clock authority. Preserve
        // absent/Some0/IEEE values without freshening or normalizing them.
        wire.native_timestamp_present = timestamp == nil ? 0 : 1
        wire.native_timestamp_bits = timestamp?.bitPattern ?? 0
        if let observation = snapshot.roundTripTimeObservation {
            switch observation {
            case .unavailable:
                wire.observation_kind = 1
            case let .measurement(measurement):
                wire.observation_kind = 2
                let bytes = Array(measurement.selectedCandidatePairFingerprint.utf8)
                wire.fingerprint_length = UInt32(clamping: bytes.count)
                var words = [UInt64](repeating: 0, count: 8)
                // Identical to the retained RTT adapter: overlong UTF8 lengths
                // survive, but no prefix truncation/hash/normalization is admitted.
                if bytes.count <= 64 {
                    for (index, byte) in bytes.enumerated() {
                        words[index / 8] |= UInt64(byte) << UInt64((index % 8) * 8)
                    }
                }
                wire.fingerprint = (words[0], words[1], words[2], words[3],
                    words[4], words[5], words[6], words[7])
                wire.measurement_total_bits = measurement.totalRoundTripTimeSeconds.bitPattern
                wire.measurement_responses = measurement.responsesReceived
            }
        }
        return wire
    }
}

/// Original adaptation input, including nil Expiry and ordinary fallback's nil
/// native UTC. It carries telemetry/Optional-route custody, never entry votes.
struct BelugaNetworkAdaptationGeneralReportSnapshot {
    let snapshot: WebRTCStatisticsSnapshot?
    let timestamp: Double?
    let retainedRoute: WebRTCICERouteDiagnostics?
    let wire: BelugaNetworkAdaptationOwnerReportSnapshot.Wire
    var incomingRoute: WebRTCICERouteDiagnostics? { snapshot?.route }
    fileprivate static func capture(_ snapshot: WebRTCStatisticsSnapshot?, timestamp: Double?,
        retainingRoute: WebRTCICERouteDiagnostics?) throws -> Self {
        guard snapshot != nil || timestamp == nil else { throw BelugaNetworkAdaptationOwnerError.malformedNativeImage }
        let wire = try snapshot.map {
            try BelugaNetworkAdaptationOwnerReportSnapshot.captureWire($0,
                timestamp: timestamp, retainingRoute: retainingRoute)
        } ?? BelugaNetworkAdaptationOwnerReportSnapshot.Wire()
        return .init(snapshot: snapshot, timestamp: timestamp, retainedRoute: retainingRoute, wire: wire)
    }
}
enum BelugaNetworkAdaptationOwnerEvent {
    case stopSampling, activateShow(generation: UInt64, show: UInt64)
    case resumeWithoutRevision, resumeAndAdvance
    case collectorGate(sourcePresent: Bool, resumeContextAbsent: Bool)
    var operation: UInt32 {
        switch self {
        case .stopSampling: 105
        case .activateShow: 106
        case .resumeWithoutRevision: 107
        case .resumeAndAdvance: 108
        case .collectorGate: 109
        }
    }
    func request(invocation: UInt64) -> beluga_core_adaptation_owner_event_request_t {
        var r = beluga_core_adaptation_owner_event_request_t()
        r.abi = 1; r.operation = operation; r.invocation = invocation
        switch self {
        case let .activateShow(generation, show): r.generation = generation; r.show = show
        case let .collectorGate(source, absent): r.capture_source_present = source ? 1 : 0; r.resume_context_absent = absent ? 1 : 0
        default: break
        }
        return r
    }
}

/// No publication capability: even an accepted packet is only a proposed value.
struct BelugaNetworkAdaptationOwnerProposal {
    let source: BelugaNetworkAdaptationOwnerSnapshot
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    let collectorEnabled: Bool
}

/// A synchronous, single-executor scope. It stores only invocation/reentry state,
/// never an Owner. Must not be shared between concurrent executors. Nested entry
/// poisons the outer call even if a test producer swallows the nested rejection.
final class BelugaNetworkAdaptationOwnerBoundary {
    typealias Request = beluga_core_adaptation_owner_event_request_t
    typealias Header = beluga_core_adaptation_state_header_t
    typealias Metadata = beluga_core_adaptation_owner_event_metadata_t
    typealias Edit = beluga_core_adaptation_time_edit_t
    typealias Coordinate = beluga_core_adaptation_time_coordinate_t
    typealias Reply = beluga_core_adaptation_clock_reply_t
    struct RawResult {
        let status: UInt32
        var header: Header
        var atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
        var metadata: Metadata
        var edits: [Edit]
        var coordinates: [Coordinate]
        var reads: [Reply]
        let inputsUnchanged: Bool
        let deniedOutputsUntouched: Bool
    }
    typealias Producer = (Request, BelugaNetworkAdaptationOwnerSnapshot) throws -> RawResult
    private let producer: Producer
    private let clockProvider: () throws -> ContinuousClock.Instant
    private let clockedProducer: ClockedProducer
    private let prepareProducer: PrepareProducer
    private let generalPrepareProducer: GeneralPrepareProducer
    private let inactiveProducer: InactiveProducer
    private let beginActiveProducer: BeginActiveProducer
    private var busy = false
    private var poisoned = false
    private var invocation: UInt64 = 0
    #if DEBUG
    // Closed negative controls apply only to an admitted actual-actor Stop frame.
    // Ordinary proposals and the release adapter cannot enable these controls.
    private var stopPublicationFaults: [WorldwideScreenService.NativeOwnerStopPublicationFault] = []
    private var isPublishingActualStop = false
    private var epochPublicationFault: WorldwideScreenService.NativeOwnerStopPublicationFault.Kind?
    private var isPublishingActualEpoch = false
    private var epochRawCalls = 0
    private var epochClockReads = 0
    private var resetPublicationFault: WorldwideScreenService.NativeOwnerStopPublicationFault.Kind?
    private var isPublishingActualReset = false
    private var resetRawCalls = 0
    private var resetClockReads = 0
    func configureActualResetFault(_ fault: WorldwideScreenService.NativeOwnerStopPublicationFault.Kind?,
        exhaustInvocation: Bool = false) throws {
        guard !busy, !isPublishingActualReset, !isPublishingActualStop, !isPublishingActualEpoch,
              !exhaustInvocation || invocation == 0 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        resetPublicationFault = fault
        if exhaustInvocation { invocation = UInt64.max }
    }
    func actualResetDiagnosticsForTesting() -> (rawCalls: Int, clockReads: Int) {
        (resetRawCalls, resetClockReads)
    }
    func configureActualEpochFault(_ fault: WorldwideScreenService.NativeOwnerStopPublicationFault.Kind?,
        exhaustInvocation: Bool = false) throws {
        guard !busy, !isPublishingActualStop, !isPublishingActualEpoch,
              !exhaustInvocation || invocation == 0 else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        epochPublicationFault = fault
        if exhaustInvocation { invocation = UInt64.max }
    }
    func actualEpochDiagnosticsForTesting() -> (rawCalls: Int, clockReads: Int) {
        (epochRawCalls, epochClockReads)
    }
    func configureActualStopFaults(_ faults: [WorldwideScreenService.NativeOwnerStopPublicationFault]) throws {
        guard !busy, invocation == 0,
              faults.allSatisfy({ [202, 105].contains($0.operation) }),
              Set(faults.map(\.operation)).count == faults.count else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        stopPublicationFaults = faults
    }
    private func actualStopFault(_ operation: UInt32) -> WorldwideScreenService.NativeOwnerStopPublicationFault.Kind? {
        guard isPublishingActualStop else { return nil }
        return stopPublicationFaults.first { $0.operation == operation }?.kind
    }
    private func poisonActualStopBySwallowedReentry(_ value: BelugaNetworkAdaptationOwnerValue,
        operation: UInt32) throws {
        do {
            if operation == 202 {
                _ = try propose(value, event: .stopSampling)
            } else {
                _ = try proposeClocked(value, event: .endShowWithoutRevision)
            }
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        } catch BelugaNetworkAdaptationOwnerError.reentry {
            // Deliberately swallowed; the shared held scope must still reject.
        }
    }
    #endif
    init() {
        producer = Self.actual
        clockProvider = { ContinuousClock().now }
        clockedProducer = Self.actualClocked
        prepareProducer = Self.actualPrepare
        generalPrepareProducer = Self.actualGeneralPrepare
        inactiveProducer = Self.actualInactive
        beginActiveProducer = Self.actualBeginActive
    }
    #if DEBUG
    /// Injection is unavailable in release builds; never a fallback implementation.
    init(testProducer: @escaping Producer) {
        producer = testProducer
        clockProvider = { ContinuousClock().now }
        clockedProducer = Self.actualClocked
        prepareProducer = Self.actualPrepare
        generalPrepareProducer = Self.actualGeneralPrepare
        inactiveProducer = Self.actualInactive
        beginActiveProducer = Self.actualBeginActive
    }
    init(testClock: @escaping () throws -> ContinuousClock.Instant,
         testClockedProducer: @escaping ClockedProducer = BelugaNetworkAdaptationOwnerBoundary.actualClocked) {
        producer = Self.actual
        clockProvider = testClock
        clockedProducer = testClockedProducer
        prepareProducer = Self.actualPrepare
        generalPrepareProducer = Self.actualGeneralPrepare
        inactiveProducer = Self.actualInactive
        beginActiveProducer = Self.actualBeginActive
    }
    init(testClock: @escaping () throws -> ContinuousClock.Instant,
         testPrepareProducer: @escaping PrepareProducer) {
        producer = Self.actual
        clockProvider = testClock
        clockedProducer = Self.actualClocked
        prepareProducer = testPrepareProducer
        generalPrepareProducer = Self.actualGeneralPrepare
        inactiveProducer = Self.actualInactive
        beginActiveProducer = Self.actualBeginActive
    }
    init(testInactiveProducer: @escaping InactiveProducer) {
        producer = Self.actual; clockProvider = { ContinuousClock().now }
        clockedProducer = Self.actualClocked; prepareProducer = Self.actualPrepare
        generalPrepareProducer = Self.actualGeneralPrepare
        inactiveProducer = testInactiveProducer
        beginActiveProducer = Self.actualBeginActive
    }
    init(testClock: @escaping () throws -> ContinuousClock.Instant,
         testGeneralPrepareProducer: @escaping GeneralPrepareProducer) {
        producer = Self.actual; clockProvider = testClock
        clockedProducer = Self.actualClocked; prepareProducer = Self.actualPrepare
        generalPrepareProducer = testGeneralPrepareProducer
        inactiveProducer = Self.actualInactive
        beginActiveProducer = Self.actualBeginActive
    }
    init(testClock: @escaping () throws -> ContinuousClock.Instant,
         testBeginActiveProducer: @escaping BeginActiveProducer) {
        producer = Self.actual; clockProvider = testClock
        clockedProducer = Self.actualClocked; prepareProducer = Self.actualPrepare
        generalPrepareProducer = Self.actualGeneralPrepare; inactiveProducer = Self.actualInactive
        beginActiveProducer = testBeginActiveProducer
    }
    #endif

    // Constructor-sealed to this Boundary. No worker stores or returns a scope;
    // its invocation is consumed once even when the held body throws.
    private struct HeldScope { let invocation: UInt64 }
    private enum GuardedProposal {
        case zeroClock(BelugaNetworkAdaptationOwnerProposal)
        case clocked(BelugaNetworkAdaptationOwnerClockedProposal)
        case prepared(BelugaNetworkAdaptationPreparedReceipt?)
        case generalPrepared(BelugaNetworkAdaptationGeneralPreparedReceipt?)
        case beginActive(BelugaNetworkAdaptationBeginActiveReceipt?)
        case nativeAttempt(BelugaNetworkAdaptationNativeAttempt)
        case retired
        case publication(BelugaNetworkAdaptationOwnerPublicationDisposition)
        #if DEBUG
        case terminalFixture(BelugaNetworkAdaptationTerminalPreparedValue)
        case generalFixture(BelugaNetworkAdaptationGeneralPreparedValue?)
        case inactiveFixture(InactiveProposal)
        case beginActiveFixture(BeginActiveProposal)
        #endif
    }
    // The nonescaping body and closed result cannot export the held scope or a
    // callback frame. Copied proposals still have no live publication authority.
    private func withGuard(_ body: (HeldScope) throws -> GuardedProposal) throws -> GuardedProposal {
        if busy { poisoned = true; throw BelugaNetworkAdaptationOwnerError.reentry }
        busy = true; poisoned = false
        defer { busy = false; poisoned = false }
        guard invocation != UInt64.max else { throw BelugaNetworkAdaptationOwnerError.invocationExhausted }
        invocation += 1
        let result = try body(HeldScope(invocation: invocation))
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        return result
    }

    private func withPreparedGuard(_ use: BelugaNetworkAdaptationPreparedUse,
        _ body: (HeldScope) throws -> GuardedProposal) throws -> GuardedProposal {
        // Even a swallowed replay/wrong-origin spend failure poisons an outer
        // invocation. Consumption still happens before busy/exhaustion refusal.
        if busy { poisoned = true }
        try use.spend(by: self)
        return try withGuard(body)
    }

    func propose(_ value: BelugaNetworkAdaptationOwnerValue, event: BelugaNetworkAdaptationOwnerEvent) throws -> BelugaNetworkAdaptationOwnerProposal {
        let result = try withGuard { scope in
            .zeroClock(try self.proposeHeld(value, event: event, scope: scope))
        }
        guard case let .zeroClock(proposal) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return proposal
    }

    private func proposeHeld(_ value: BelugaNetworkAdaptationOwnerValue,
        event: BelugaNetworkAdaptationOwnerEvent, scope: HeldScope) throws -> BelugaNetworkAdaptationOwnerProposal {
        guard Self.layoutIsExact else { throw BelugaNetworkAdaptationOwnerError.unsupportedLayout }
        let source = try BelugaNetworkAdaptationOwnerSnapshot.capture(value)
        let request = event.request(invocation: scope.invocation)
        var raw: RawResult
        #if DEBUG
        let publicationFault = actualStopFault(event.operation)
            ?? (isPublishingActualReset && event.operation == 107 ? resetPublicationFault : nil)
        if isPublishingActualReset { resetRawCalls += 1 }
        if publicationFault == .refused {
            var denied = request
            denied.abi = 0
            raw = try Self.actual(denied, source)
        } else {
            raw = try producer(request, source)
        }
        if publicationFault == .malformed { raw.header.abi = 0 }
        if publicationFault == .swallowedReentry {
            try poisonActualStopBySwallowedReentry(value, operation: event.operation)
        }
        #else
        raw = try producer(request, source)
        #endif
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard raw.inputsUnchanged else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        if raw.status == 2 {
            guard raw.deniedOutputsUntouched else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        guard raw.status == 1, raw.header.abi == 1, raw.header.domain == 2,
              raw.header.phase == 2, raw.header.count == 179, raw.atoms.count == 179,
              raw.edits.count == 13, raw.coordinates.count == 13, raw.reads.count == 15 else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let revision = [105, 106, 108].contains(event.operation) ? value.revision &+ 1 : value.revision
        let m = raw.metadata
        let enabled: Bool
        if case let .collectorGate(source, absent) = event { enabled = source && absent } else { enabled = false }
        guard m.abi == 1, m.operation == event.operation, m.scope == 2, m.read_count == 0,
              m.invocation == request.invocation, m.revision == revision,
              m.peer_present == (value.policy.peerGeneration == nil ? 0 : 1), m.peer == (value.policy.peerGeneration ?? 0),
              m.bound == 0, m.route == 0, m.sample == 0, m.enabled == (enabled ? 1 : 0), m.lease == 0,
              m.queue_fault == UInt32(source.atoms[41].low), m.rtt_fault == UInt32(source.atoms[89].low),
              raw.reads.allSatisfy({ Self.bytes($0) == Self.bytes(Reply()) }) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let clearSlot: Int? = event.operation == 105 ? 12 : ([107, 108].contains(event.operation) ? 2 : nil)
        for i in 0..<13 {
            let expected = Edit(action: clearSlot == i ? 2 : 0, source: 0, index: 0, ordinal: 0, high: 0, low: 0)
            guard Self.bytes(raw.edits[i]) == Self.bytes(expected),
                  Self.bytes(raw.coordinates[i]) == Self.bytes(Coordinate()) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        // Import only the documented five cuts into the captured native value.
        // All other atoms MUST recapture identically, including opaque inner DTOs.
        var policy = value.policy
        try policy.networkAdaptationOwnerImportZeroClock(event: event, atoms: raw.atoms)
        var fast = value.fastStatisticsAvailable
        if event.operation == 105 { fast = false }
        if case let .collectorGate(source, _) = event, !source { fast = false }
        let native = BelugaNetworkAdaptationOwnerValue(policy: policy, revision: revision,
            fastStatisticsAvailable: fast, lane: event.operation == 105 ? nil : value.lane,
            evidenceTime: event.operation == 105 ? nil : value.evidenceTime,
            minimumCollectionSequence: event.operation == 105 ? nil : value.minimumCollectionSequence, applied: value.applied)
        let replacement = try BelugaNetworkAdaptationOwnerSnapshot.capture(native, retainingAnchor: source.anchor)
        var expectedTimes = source.times
        if let clearSlot { expectedTimes[clearSlot] = nil }
        guard !poisoned, BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(raw.atoms, replacement.atoms),
              replacement.times == expectedTimes, replacement.anchor == source.anchor, replacement.route == source.route else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return .init(source: source, replacement: replacement, collectorEnabled: enabled)
    }

    private static func bytes<T>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value) { Array($0) } }
    private static func arrayBytes<T>(_ values: [T]) -> [UInt8] {
        values.withUnsafeBufferPointer { Array(UnsafeRawBufferPointer(start: $0.baseAddress, count: $0.count * MemoryLayout<T>.stride)) }
    }
    static func actual(_ request: Request, _ source: BelugaNetworkAdaptationOwnerSnapshot) throws -> RawResult {
        var ownedRequest = request
        var ownedHeader = Header(abi: 1, domain: 2, phase: 1, count: 179)
        // map plus a mutable buffer borrow supplies uniquely owned input storage;
        // the C const atoms pointer never borrows the retained source snapshot.
        var ownedAtoms = source.atoms.map { $0 }
        let sourceBefore = arrayBytes(source.atoms)
        var borrowedInputsUnchanged = false
        var outH = Header(abi: 91, domain: 92, phase: 93, count: 94)
        var outA = Array(repeating: BelugaNetworkAdaptationOwnerWriter.Atom(kind: 95, present: 96, high: -97, low: 98), count: 179)
        var m = Metadata(abi: 81, operation: 82, scope: 83, read_count: 84, invocation: 85,
            revision: 86, peer: 87, peer_present: 88, bound: 89, route: 90, sample: 91,
            enabled: 92, lease: 93, queue_fault: 94, rtt_fault: 95)
        var e = Array(repeating: Edit(action: 71, source: 72, index: 73, ordinal: 74, high: -75, low: 76), count: 13)
        var c = Array(repeating: Coordinate(present: 61, reserved: 62, high: -63, low: 64), count: 13)
        var r = Array(repeating: Reply(abi: 51, status: 52, site: 53, ordinal: 54, invocation: 55, high: -56, low: 57, reserved: 58), count: 15)
        let outputsBefore = [bytes(outH), arrayBytes(outA), bytes(m), arrayBytes(e), arrayBytes(c), arrayBytes(r)]
        // All nine borrowed buffers have separate live initialized storage; no pointer escapes.
        let status = withUnsafePointer(to: &ownedRequest) { req in
            withUnsafePointer(to: &ownedHeader) { header in
                ownedAtoms.withUnsafeMutableBufferPointer { atoms in
                    outA.withUnsafeMutableBufferPointer { out in
                        e.withUnsafeMutableBufferPointer { edits in
                            c.withUnsafeMutableBufferPointer { coords in
                                r.withUnsafeMutableBufferPointer { reads in
                                    // Hash the exact C-borrowed addresses, not re-materialized
                                    // immutable value parameters or a different array image.
                                    let before = [Array(UnsafeRawBufferPointer(start: req, count: MemoryLayout<Request>.stride)),
                                        Array(UnsafeRawBufferPointer(start: header, count: MemoryLayout<Header>.stride)),
                                        Array(UnsafeRawBufferPointer(start: atoms.baseAddress!, count: 179 * MemoryLayout<BelugaNetworkAdaptationOwnerWriter.Atom>.stride))]
                                    let result = beluga_core_network_adaptation_owner_zero_clock_event(req, header, atoms.baseAddress!, 179,
                                        &outH, out.baseAddress!, 179, &m, edits.baseAddress!, 13,
                                        coords.baseAddress!, 13, reads.baseAddress!, 15)
                                    borrowedInputsUnchanged = before == [Array(UnsafeRawBufferPointer(start: req, count: MemoryLayout<Request>.stride)),
                                        Array(UnsafeRawBufferPointer(start: header, count: MemoryLayout<Header>.stride)),
                                        Array(UnsafeRawBufferPointer(start: atoms.baseAddress!, count: 179 * MemoryLayout<BelugaNetworkAdaptationOwnerWriter.Atom>.stride))]
                                    return result
                                }
                            }
                        }
                    }
                }
            }
        }
        return RawResult(status: status, header: outH, atoms: outA, metadata: m, edits: e, coordinates: c, reads: r,
            inputsUnchanged: borrowedInputsUnchanged && sourceBefore == arrayBytes(source.atoms),
            deniedOutputsUntouched: outputsBefore == [bytes(outH), arrayBytes(outA), bytes(m), arrayBytes(e), arrayBytes(c), arrayBytes(r)])
    }

    private static func layout<T>(_ type: T.Type, _ size: Int, _ alignment: Int, _ offsets: [Int?], _ expected: [Int]) -> Bool {
        MemoryLayout<T>.size == size && MemoryLayout<T>.stride == size && MemoryLayout<T>.alignment == alignment && offsets == expected.map(Optional.some)
    }
    static var layoutIsExact: Bool {
        typealias A = BelugaNetworkAdaptationOwnerWriter.Atom
        return UInt16(littleEndian: 1) == 1 && MemoryLayout<Int>.size == 8
            && layout(Request.self, 40, 8, [MemoryLayout<Request>.offset(of: \Request.abi), MemoryLayout<Request>.offset(of: \Request.operation), MemoryLayout<Request>.offset(of: \Request.generation), MemoryLayout<Request>.offset(of: \Request.invocation), MemoryLayout<Request>.offset(of: \Request.show), MemoryLayout<Request>.offset(of: \Request.capture_source_present), MemoryLayout<Request>.offset(of: \Request.resume_context_absent)], [0, 4, 8, 16, 24, 32, 36])
            && layout(Header.self, 16, 4, [MemoryLayout<Header>.offset(of: \Header.abi), MemoryLayout<Header>.offset(of: \Header.domain), MemoryLayout<Header>.offset(of: \Header.phase), MemoryLayout<Header>.offset(of: \Header.count)], [0, 4, 8, 12])
            && layout(A.self, 24, 8, [MemoryLayout<A>.offset(of: \A.kind), MemoryLayout<A>.offset(of: \A.present), MemoryLayout<A>.offset(of: \A.high), MemoryLayout<A>.offset(of: \A.low)], [0, 4, 8, 16])
            && layout(Edit.self, 32, 8, [MemoryLayout<Edit>.offset(of: \Edit.action), MemoryLayout<Edit>.offset(of: \Edit.source), MemoryLayout<Edit>.offset(of: \Edit.index), MemoryLayout<Edit>.offset(of: \Edit.ordinal), MemoryLayout<Edit>.offset(of: \Edit.high), MemoryLayout<Edit>.offset(of: \Edit.low)], [0, 4, 8, 12, 16, 24])
            && layout(Coordinate.self, 24, 8, [MemoryLayout<Coordinate>.offset(of: \Coordinate.present), MemoryLayout<Coordinate>.offset(of: \Coordinate.reserved), MemoryLayout<Coordinate>.offset(of: \Coordinate.high), MemoryLayout<Coordinate>.offset(of: \Coordinate.low)], [0, 4, 8, 16])
            && layout(Reply.self, 48, 8, [MemoryLayout<Reply>.offset(of: \Reply.abi), MemoryLayout<Reply>.offset(of: \Reply.status), MemoryLayout<Reply>.offset(of: \Reply.site), MemoryLayout<Reply>.offset(of: \Reply.ordinal), MemoryLayout<Reply>.offset(of: \Reply.invocation), MemoryLayout<Reply>.offset(of: \Reply.high), MemoryLayout<Reply>.offset(of: \Reply.low), MemoryLayout<Reply>.offset(of: \Reply.reserved)], [0, 4, 8, 12, 16, 24, 32, 40])
            && layout(Metadata.self, 72, 8, [MemoryLayout<Metadata>.offset(of: \Metadata.abi), MemoryLayout<Metadata>.offset(of: \Metadata.operation), MemoryLayout<Metadata>.offset(of: \Metadata.scope), MemoryLayout<Metadata>.offset(of: \Metadata.read_count), MemoryLayout<Metadata>.offset(of: \Metadata.invocation), MemoryLayout<Metadata>.offset(of: \Metadata.revision), MemoryLayout<Metadata>.offset(of: \Metadata.peer), MemoryLayout<Metadata>.offset(of: \Metadata.peer_present), MemoryLayout<Metadata>.offset(of: \Metadata.bound), MemoryLayout<Metadata>.offset(of: \Metadata.route), MemoryLayout<Metadata>.offset(of: \Metadata.sample), MemoryLayout<Metadata>.offset(of: \Metadata.enabled), MemoryLayout<Metadata>.offset(of: \Metadata.lease), MemoryLayout<Metadata>.offset(of: \Metadata.queue_fault), MemoryLayout<Metadata>.offset(of: \Metadata.rtt_fault)], [0, 4, 8, 12, 16, 24, 32, 40, 44, 48, 52, 56, 60, 64, 68])
    }
}

// SOURCE-ONLY APPEND BODY: append to BelugaNetworkAdaptationOwnerCodec.swift.
// Do not compile as a separate source: it intentionally shares that file's private
// busy/poison/invocation scope and sealed import constructors. UNWIRED, UNCOMPILED.

enum BelugaNetworkAdaptationOwnerClockedEvent {
    case endShowWithoutRevision, routeInvalidated, endShowAndAdvance
    case visibility(show: Bool, generation: UInt64, epoch: UInt64)
    case hideHealthRevocation, beginPostResumeEpoch(minimum: UInt64?)
    case resumeAccepted, resumeFailedAndAdvance
    var operation: UInt32 {
        switch self {
        case .endShowWithoutRevision: 202
        case .routeInvalidated: 212
        case .endShowAndAdvance: 213
        case .visibility: 214
        case .hideHealthRevocation: 215
        case .beginPostResumeEpoch: 216
        case .resumeAccepted: 217
        case .resumeFailedAndAdvance: 218
        }
    }
    var mask: UInt16 {
        switch self {
        case .endShowWithoutRevision, .endShowAndAdvance, .hideHealthRevocation, .resumeAccepted: 0x00ef
        case .routeInvalidated: 0x10ef
        case let .visibility(show, _, _): show ? 0x01ff : 0x00ef
        case .beginPostResumeEpoch: 0x10cc
        case .resumeFailedAndAdvance: 0x00cf
        }
    }
    fileprivate func request(_ invocation: UInt64) -> beluga_core_adaptation_owner_clocked_event_request_t {
        var r = beluga_core_adaptation_owner_clocked_event_request_t()
        r.abi = 1; r.operation = operation; r.invocation = invocation
        switch self {
        case let .visibility(show, generation, epoch):
            r.flag = show ? 1 : 0
            if show { r.generation = generation; r.show = epoch }
        case let .beginPostResumeEpoch(minimum):
            r.minimum_present = minimum == nil ? 0 : 1; r.minimum = minimum ?? 0
        default: break
        }
        return r
    }
}

struct BelugaNetworkAdaptationOwnerClockedProposal {
    enum RouteAction { case retain, clear }
    let source: BelugaNetworkAdaptationOwnerSnapshot
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    let routeAction: RouteAction
}

/// A synchronous caller-owned frame. No actor reference, foreign buffer reference,
/// eager read, clock cache, or publication capability lives here. Constructor sealed.
final class BelugaNetworkAdaptationOwnerClockFrame {
    typealias Reply = beluga_core_adaptation_clock_reply_t
    struct Receipt { let instant: ContinuousClock.Instant; let reply: Reply }
    fileprivate let invocation: UInt64
    fileprivate let plan: [UInt32]
    fileprivate private(set) var receipts: [Receipt] = []
    fileprivate private(set) var denied = false
    private var active = true
    private var reading = false
    private var anchor: ContinuousClock.Instant?
    private let provider: () throws -> ContinuousClock.Instant
    private let poisoned: () -> Bool
    fileprivate init(invocation: UInt64, plan: [UInt32], anchor: ContinuousClock.Instant?,
        provider: @escaping () throws -> ContinuousClock.Instant, poisoned: @escaping () -> Bool) {
        self.invocation = invocation; self.plan = plan; self.anchor = anchor
        self.provider = provider; self.poisoned = poisoned
    }
    fileprivate func retire() { active = false }
    fileprivate func reply(invocation: UInt64, site: UInt32, ordinal: UInt32,
        destination: UnsafeMutablePointer<Reply>?) -> UInt32 {
        guard active, !reading, !denied, !poisoned(), let destination,
              invocation == self.invocation, Int(ordinal) == receipts.count,
              receipts.count < plan.count, plan.count <= 15,
              site == plan[receipts.count] else { denied = true; return 0 }
        reading = true
        defer { reading = false }
        do {
            let now = try provider()
            // An admitted nested entry may be swallowed by the provider. Its poison
            // MUST still deny this read and the outer draft before any import.
            guard active, !poisoned() else { denied = true; return 0 }
            let coordinateAnchor = anchor ?? now
            let coordinate = OwnerAttoseconds(coordinateAnchor.duration(to: now))
            guard coordinate.fitsCodecTime else { denied = true; return 0 }
            let r = Reply(abi: 1, status: 1, site: site, ordinal: ordinal,
                invocation: invocation, high: coordinate.high, low: coordinate.low, reserved: 0)
            anchor = coordinateAnchor
            receipts.append(.init(instant: now, reply: r))
            destination.pointee = r
            return 1
        } catch { denied = true; return 0 }
    }
    #if DEBUG
    // Test only: probe the exact pre-provider guard; no production constructor.
    func testReply(invocation: UInt64, site: UInt32, ordinal: UInt32) -> UInt32 {
        var r = Reply()
        return reply(invocation: invocation, site: site, ordinal: ordinal, destination: &r)
    }
    #endif
}

/// Typed, immutable subowner imports. Their constructors are sealed to this file;
/// no caller can provide an arbitrary raw setter or manufacture producer provenance.
struct BelugaNetworkAdaptationOwnerQueueImport {
    let packets: UInt64?; let delayBits: UInt64?; let pressure: Int
    let low: ContinuousClock.Instant?; let soft: ContinuousClock.Instant?; let fault: Bool
    fileprivate init(packets: UInt64?, delayBits: UInt64?, pressure: Int,
        low: ContinuousClock.Instant?, soft: ContinuousClock.Instant?, fault: Bool) {
        self.packets = packets; self.delayBits = delayBits; self.pressure = pressure
        self.low = low; self.soft = soft; self.fault = fault
    }
}
struct BelugaNetworkAdaptationOwnerRTTImport {
    let state: BelugaRustRoundTripTimeEvidence.State
    let advancement: ContinuousClock.Instant?; let fault: Bool
    fileprivate init(state: BelugaRustRoundTripTimeEvidence.State,
        advancement: ContinuousClock.Instant?, fault: Bool) {
        self.state = state; self.advancement = advancement; self.fault = fault
    }
}
struct BelugaNetworkAdaptationOwnerDemandImport {
    let fault: Bool
    fileprivate init(fault: Bool) { self.fault = fault }
}

/// CLOSED import packet for eight lifecycle events and validated501 policy only. It cannot be
/// constructed outside this file and cannot publish or replace an actual policy.
/// Indexed getters decode a validated packet, not a general inverse/set179 API.
struct BelugaNetworkAdaptationOwnerClockedImport {
    private let atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
    private let fields: Set<Int>
    let times: [ContinuousClock.Instant?]
    let route: WebRTCICERouteDiagnostics?
    fileprivate init(atoms: [BelugaNetworkAdaptationOwnerWriter.Atom], fields: Set<Int>,
        times: [ContinuousClock.Instant?], route: WebRTCICERouteDiagnostics?) {
        self.atoms = atoms; self.fields = fields; self.times = times; self.route = route
    }
    func permits(_ index: Int) -> Bool { fields.contains(index) }
    private func word(_ index: Int, kind: UInt32, required: Bool = false) throws -> UInt64? {
        guard atoms.indices.contains(index) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        let a = atoms[index]
        guard a.kind == kind, a.present <= 1, a.high == 0,
              a.present != 0 || (!required && a.low == 0) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return a.present == 0 ? nil : a.low
    }
    func unsigned(_ i: Int) throws -> UInt64? { try word(i, kind: 1) }
    func integer(_ i: Int) throws -> Int? { try word(i, kind: 2).map { Int(Int64(bitPattern: $0)) } }
    func requiredInteger(_ i: Int) throws -> Int {
        Int(Int64(bitPattern: try word(i, kind: 2, required: true)!))
    }
    func scalar(_ i: Int) throws -> Double? { try word(i, kind: 3).map(Double.init(bitPattern:)) }
    func bits(_ i: Int) throws -> UInt64? { try word(i, kind: 3) }
    private func requiredBits(_ i: Int) throws -> UInt64 { try word(i, kind: 3, required: true)! }
    private func requiredUnsigned(_ i: Int) throws -> UInt64 { try word(i, kind: 1, required: true)! }
    func boolean(_ i: Int) throws -> Bool {
        let n = try word(i, kind: 4, required: true)!
        guard n <= 1 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return n == 1
    }
    func optionalBoolean(_ i: Int) throws -> Bool? {
        guard let n = try word(i, kind: 4) else { return nil }
        guard n <= 1 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return n == 1
    }
    func tier(_ i: Int) throws -> WorldwideScreenVideoAdaptationTier? {
        guard let n = try word(i, kind: 7) else { return nil }
        guard n <= 7, let t = WorldwideScreenVideoAdaptationTier(rawValue: Int(n)) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return t
    }
    private func u32(_ i: Int) throws -> UInt32 {
        let n = try word(i, kind: 6, required: true)!
        guard n <= UInt64(UInt32.max) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return UInt32(n)
    }
    func queue() throws -> BelugaNetworkAdaptationOwnerQueueImport {
        .init(packets: try unsigned(36), delayBits: try bits(37), pressure: try requiredInteger(38),
            low: times[6], soft: times[7], fault: try boolean(41))
    }
    func rtt() throws -> BelugaNetworkAdaptationOwnerRTTImport {
        var s = BelugaRustRoundTripTimeEvidence.State()
        s.abi_version = try u32(42); s.reserved = try u32(43); s.baseline_present = try u32(44)
        s.bootstrap_count = try u32(45); s.disposition = try u32(46); s.health = try u32(47)
        s.uses_native = try u32(48); s.provisional = try u32(49); s.permits_initial = try u32(50)
        s.distinct_count = try u32(51); s.last_measured_present = try u32(52); s.advancement_present = try u32(53)
        s.age_present = try u32(54); s.watermark_present = try u32(55); s.fence_present = try u32(56)
        s.fence_current_present = try u32(57); s.reserved2 = try u32(58); s.reserved3 = try u32(59)
        s.baseline_bits = try requiredBits(60); s.last_measured_bits = try requiredBits(61)
        s.bootstrap_bits = (try requiredBits(62), try requiredBits(63), try requiredBits(64))
        s.age_seconds = Int64(try requiredInteger(65)); s.age_attoseconds = Int64(try requiredInteger(66))
        s.watermark.fingerprint_words = (try requiredUnsigned(67), try requiredUnsigned(68), try requiredUnsigned(69), try requiredUnsigned(70),
            try requiredUnsigned(71), try requiredUnsigned(72), try requiredUnsigned(73), try requiredUnsigned(74))
        s.watermark.total_bits = try requiredBits(75); s.watermark.responses = try requiredUnsigned(76)
        s.fence.fingerprint_words = (try requiredUnsigned(77), try requiredUnsigned(78), try requiredUnsigned(79), try requiredUnsigned(80),
            try requiredUnsigned(81), try requiredUnsigned(82), try requiredUnsigned(83), try requiredUnsigned(84))
        s.fence.total_bits = try requiredBits(85); s.fence.responses = try requiredUnsigned(86); s.fence_current_bits = try requiredBits(87)
        return .init(state: s, advancement: times[8], fault: try boolean(89))
    }
    func demand() throws -> BelugaNetworkAdaptationOwnerDemandImport {
        .init(fault: try boolean(140))
    }
}

extension BelugaNetworkAdaptationOwnerBoundary {
    typealias ClockedRequest = beluga_core_adaptation_owner_clocked_event_request_t
    typealias ClockedProducer = (ClockedRequest, BelugaNetworkAdaptationOwnerSnapshot,
        BelugaNetworkAdaptationOwnerClockFrame) throws -> RawResult

    // Original helper write families, used solely as a rejection whitelist. No
    // field is successfully calculated here; all imported values come from Rust.
    private static let queueFields = Set(36...41)
    private static let rttFields = Set(42...89)
    private static let witnessFields: Set<Int> = [158, 159, 160]
    private static let promotionFields = Set(25...28)
    private static let capacityFields = Set(145...148)
    private static var transitionFields: Set<Int> { queueFields.union(witnessFields).union(promotionFields).union(capacityFields) }
    private static var revertFields: Set<Int> { transitionFields.union([4, 10, 11, 12, 20, 21, 22, 23, 24, 156, 157]) }
    private static var pathFields: Set<Int> {
        transitionFields.union(rttFields).union(Set(5...24)).union([32, 33, 34, 35, 156, 157])
    }
    private static let startupFields = Set(164...167)
    private static var endFields: Set<Int> { startupFields.union(witnessFields).union([153, 154]) }

    private static func admission(_ source: BelugaNetworkAdaptationOwnerSnapshot,
        event: BelugaNetworkAdaptationOwnerClockedEvent) throws -> (plan: [UInt32], fields: Set<Int>, clearRoute: Bool) {
        let a = source.atoms
        let origin = a[20].present == 1
        let floor = a[157].present == 1 && a[20].present == 1 && a[20].low == 7
        let confirmed = a[22].present == 1
        let endReverts = (floor || confirmed) && origin
        let end = endFields.union(endReverts ? revertFields : [])
        let endPlan: [UInt32] = endReverts ? [2] : []
        var plan: [UInt32]; var fields: Set<Int>; var clearRoute = false
        switch event {
        case .endShowWithoutRevision, .endShowAndAdvance:
            plan = endPlan; fields = end
        case .routeInvalidated:
            plan = (origin ? [2] : []) + [2, 0, 1]
            fields = pathFields.union(origin ? revertFields : []).union([144, 166, 167]); clearRoute = true
        case let .visibility(show, generation, epoch):
            if !show { plan = endPlan; fields = end }
            else if source.value.policy.peerGeneration != generation {
                plan = [2, 0, 1, 0, 1]
                fields = pathFields.union(startupFields).union(Set(152...163)).union(Set(29...31))
                    .union([3, 4, 143, 144, 149, 150])
                clearRoute = true
            } else if epoch > 0 && epoch > (a[152].present == 1 ? a[152].low : 0) {
                plan = endPlan; fields = end.union(startupFields).union([152, 153, 155, 156])
            } else { plan = []; fields = [] }
        case .hideHealthRevocation:
            let fault = try source.value.policy.networkAdaptationOwnerFaultAfterHideRead()
            let initialRevert = confirmed && origin
            let finalRevert = fault && origin && !initialRevert
            plan = (initialRevert ? [2] : []) + [0, 1] + (finalRevert ? [2] : [])
            fields = witnessFields.union(rttFields).union([10, 167])
            if initialRevert || finalRevert { fields.formUnion(revertFields) }
            if fault { fields.formUnion(promotionFields.union([5, 9, 166, 167])) }
        case .beginPostResumeEpoch:
            plan = [2]; fields = transitionFields.union([5, 6, 7, 8, 9, 10, 21])
        case .resumeAccepted:
            plan = endPlan; fields = end.union(promotionFields)
            if a[16].low == 0 { fields.formUnion(Set(13...19).union([9])) }
        case .resumeFailedAndAdvance:
            plan = [2]; fields = transitionFields.union(Set(9...24)).union(Set(29...31)).union([4, 5, 6, 156, 157])
        }
        // Preserve real injected producers where no RTT application is reached.
        // A healthy RTT application is admitted ONLY from its sealed actual init.
        if plan.contains(0) {
            guard source.value.policy.networkAdaptationOwnerRTTApplicationIsAdmitted else {
                throw BelugaNetworkAdaptationOwnerError.malformedNativeImage
            }
        }
        // Existing native Queue.raw converts pressure before its fault short circuit.
        // Negative synthetic fixture pressure has no representable genuine Q cut.
        if plan.contains(2), Int64(bitPattern: a[38].low) < 0 {
            throw BelugaNetworkAdaptationOwnerError.malformedNativeImage
        }
        return (plan, fields, clearRoute)
    }

    func proposeClocked(_ value: BelugaNetworkAdaptationOwnerValue,
        event: BelugaNetworkAdaptationOwnerClockedEvent) throws -> BelugaNetworkAdaptationOwnerClockedProposal {
        let result = try withGuard { scope in
            .clocked(try self.proposeClockedHeld(value, event: event, scope: scope))
        }
        guard case let .clocked(proposal) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return proposal
    }

    private func proposeClockedHeld(_ value: BelugaNetworkAdaptationOwnerValue,
        event: BelugaNetworkAdaptationOwnerClockedEvent, scope: HeldScope) throws -> BelugaNetworkAdaptationOwnerClockedProposal {
        guard Self.clockedLayoutIsExact else { throw BelugaNetworkAdaptationOwnerError.unsupportedLayout }
        let source = try BelugaNetworkAdaptationOwnerSnapshot.capture(value)
        let admission = try Self.admission(source, event: event)
        let request = event.request(scope.invocation)
        let frame = BelugaNetworkAdaptationOwnerClockFrame(invocation: scope.invocation, plan: admission.plan,
            anchor: source.anchor, provider: clockProvider, poisoned: { self.poisoned })
        defer { frame.retire() }
        var raw: RawResult
        #if DEBUG
        let publicationFault = actualStopFault(event.operation)
            ?? (isPublishingActualEpoch && event.operation == 216 ? epochPublicationFault : nil)
            ?? (isPublishingActualReset && event.operation == 218 ? resetPublicationFault : nil)
        if isPublishingActualEpoch { epochRawCalls += 1 }
        if isPublishingActualReset { resetRawCalls += 1 }
        if publicationFault == .refused {
            var denied = request
            denied.abi = 0
            raw = try Self.actualClocked(denied, source, frame)
        } else {
            raw = try clockedProducer(request, source, frame)
        }
        if isPublishingActualEpoch { epochClockReads += frame.receipts.count }
        if isPublishingActualReset { resetClockReads += frame.receipts.count }
        if publicationFault == .malformed { raw.header.abi = 0 }
        if publicationFault == .swallowedReentry {
            try poisonActualStopBySwallowedReentry(value, operation: event.operation)
        }
        #else
        raw = try clockedProducer(request, source, frame)
        #endif
        frame.retire()
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard raw.inputsUnchanged else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        if (2...5).contains(raw.status) {
            guard raw.deniedOutputsUntouched else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        guard raw.status == 1, !frame.denied, frame.receipts.count == admission.plan.count,
              raw.header.abi == 1, raw.header.domain == 2, raw.header.phase == 2, raw.header.count == 179,
              raw.atoms.count == 179, raw.edits.count == 13, raw.coordinates.count == 13, raw.reads.count == 15 else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        // Closed primitive atom shape. Exact full native recapture remains mandatory.
        for (before, after) in zip(source.atoms, raw.atoms) {
            guard before.kind == after.kind, after.present <= 1,
                  after.present != 0 || (after.high == 0 && after.low == 0),
                  after.kind == 10 || after.high == 0 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            if after.present == 1 {
                switch after.kind {
                case 4, 8: guard after.low <= 1 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                case 5: guard after.low <= UInt64(UInt8.max) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                case 6: guard after.low <= UInt64(UInt32.max) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                case 7: guard after.low <= 7 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                default: break
                }
            }
        }
        for i in 0..<15 {
            let expected = i < frame.receipts.count ? frame.receipts[i].reply : Reply()
            guard Self.bytes(raw.reads[i]) == Self.bytes(expected) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        }
        let revision = [202, 215].contains(event.operation) ? value.revision : value.revision &+ 1
        let peer: UInt64?
        if case let .visibility(show, generation, _) = event, show { peer = generation } else { peer = value.policy.peerGeneration }
        let m = raw.metadata
        guard m.abi == 1, m.operation == event.operation, m.scope == (event.operation == 202 ? 1 : 2),
              m.invocation == request.invocation, m.read_count == UInt32(frame.receipts.count),
              m.revision == revision, m.peer_present == (peer == nil ? 0 : 1), m.peer == (peer ?? 0),
              m.bound == 0, m.route == (admission.clearRoute ? 1 : 0), m.sample == 0, m.enabled == 0, m.lease == 0,
              m.queue_fault == UInt32(raw.atoms[41].low), m.rtt_fault == UInt32(raw.atoms[89].low) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        var times = source.times
        let indices: [Int?] = [12, 23, 28, 159, 163, 167, 39, 40, 88, nil, nil, nil, 171]
        for i in 0..<13 {
            let e = raw.edits[i], c = raw.coordinates[i]
            if event.mask & (1 << i) == 0 {
                guard Self.bytes(e) == Self.bytes(Edit()), Self.bytes(c) == Self.bytes(Coordinate()) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
            } else {
                guard e.action == 1 || e.action == 2, e.source == 0, e.index == 0,
                      e.ordinal == 0, e.high == 0, e.low == 0, c.reserved == 0 else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
                let a = source.atoms[indices[i]!]
                let expected = e.action == 1 ? Coordinate(present: a.present, reserved: 0, high: a.high, low: a.low) : Coordinate()
                guard Self.bytes(c) == Self.bytes(expected) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                if e.action == 2 { times[i] = nil }
            }
        }
        // Successful-tail correlations only; no live rollback semantics are invented.
        let lane = [212, 216].contains(event.operation) ? nil : value.lane
        let evidence = [212, 216].contains(event.operation) ? nil : value.evidenceTime
        let minimum: UInt64?
        if case let .beginPostResumeEpoch(n) = event {
            minimum = n.map { max(value.minimumCollectionSequence ?? 0, $0) }
        } else { minimum = value.minimumCollectionSequence }
        var allowed = admission.fields
        allowed.insert(168)
        if [212, 216].contains(event.operation) { allowed.formUnion([170, 171]) }
        if event.operation == 216 { allowed.insert(172) }
        for i in 0..<179 where !allowed.contains(i) {
            guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms([raw.atoms[i]], [source.atoms[i]]) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        let route = admission.clearRoute ? nil : source.route
        let packet = BelugaNetworkAdaptationOwnerClockedImport(atoms: raw.atoms, fields: admission.fields, times: times, route: route)
        var policy = value.policy
        try policy.networkAdaptationOwnerImportClocked(packet)
        let native = BelugaNetworkAdaptationOwnerValue(policy: policy, revision: revision,
            fastStatisticsAvailable: value.fastStatisticsAvailable, lane: lane, evidenceTime: evidence,
            minimumCollectionSequence: minimum, applied: value.applied)
        let replacement = try BelugaNetworkAdaptationOwnerSnapshot.capture(native, retainingAnchor: source.anchor)
        guard !poisoned, BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(raw.atoms, replacement.atoms),
              replacement.times == times, replacement.anchor == source.anchor, replacement.route == route else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return .init(source: source, replacement: replacement, routeAction: admission.clearRoute ? .clear : .retain)
    }

    private static func clockCallback(_ context: UnsafeMutableRawPointer?, _ invocation: UInt64,
        _ site: UInt32, _ ordinal: UInt32, _ reply: UnsafeMutablePointer<Reply>?) -> UInt32 {
        guard let context else { return 0 }
        let frame = Unmanaged<BelugaNetworkAdaptationOwnerClockFrame>.fromOpaque(context).takeUnretainedValue()
        return frame.reply(invocation: invocation, site: site, ordinal: ordinal, destination: reply)
    }
    static func actualClocked(_ request: ClockedRequest, _ source: BelugaNetworkAdaptationOwnerSnapshot,
        _ frame: BelugaNetworkAdaptationOwnerClockFrame) throws -> RawResult {
        var ownedRequest = request
        var ownedHeader = Header(abi: 1, domain: 2, phase: 1, count: 179)
        var ownedAtoms = source.atoms.map { $0 }
        let sourceBefore = arrayBytes(source.atoms)
        var unchanged = false
        var h = Header(abi: 91, domain: 92, phase: 93, count: 94)
        var a = Array(repeating: BelugaNetworkAdaptationOwnerWriter.Atom(kind: 95, present: 96, high: -97, low: 98), count: 179)
        var m = Metadata(abi: 81, operation: 82, scope: 83, read_count: 84, invocation: 85, revision: 86,
            peer: 87, peer_present: 88, bound: 89, route: 90, sample: 91, enabled: 92, lease: 93, queue_fault: 94, rtt_fault: 95)
        var e = Array(repeating: Edit(action: 71, source: 72, index: 73, ordinal: 74, high: -75, low: 76), count: 13)
        var c = Array(repeating: Coordinate(present: 61, reserved: 62, high: -63, low: 64), count: 13)
        var r = Array(repeating: Reply(abi: 51, status: 52, site: 53, ordinal: 54, invocation: 55, high: -56, low: 57, reserved: 58), count: 15)
        let beforeOutputs = [bytes(h), arrayBytes(a), bytes(m), arrayBytes(e), arrayBytes(c), arrayBytes(r)]
        let status = withExtendedLifetime(frame) {
            withUnsafePointer(to: &ownedRequest) { req in
                withUnsafePointer(to: &ownedHeader) { header in
                    ownedAtoms.withUnsafeMutableBufferPointer { atoms in
                        a.withUnsafeMutableBufferPointer { out in
                            e.withUnsafeMutableBufferPointer { edits in
                                c.withUnsafeMutableBufferPointer { coords in
                                    r.withUnsafeMutableBufferPointer { reads in
                                        let before = [Array(UnsafeRawBufferPointer(start: req, count: MemoryLayout<ClockedRequest>.stride)),
                                            Array(UnsafeRawBufferPointer(start: header, count: MemoryLayout<Header>.stride)),
                                            Array(UnsafeRawBufferPointer(start: atoms.baseAddress!, count: 179 * MemoryLayout<BelugaNetworkAdaptationOwnerWriter.Atom>.stride))]
                                        let status = beluga_core_network_adaptation_owner_clocked_event(req, header, atoms.baseAddress!, 179,
                                            { context, invocation, site, ordinal, reply in
                                                BelugaNetworkAdaptationOwnerBoundary.clockCallback(context, invocation, site, ordinal, reply)
                                            }, Unmanaged.passUnretained(frame).toOpaque(),
                                            &h, out.baseAddress!, 179, &m, edits.baseAddress!, 13, coords.baseAddress!, 13, reads.baseAddress!, 15)
                                        unchanged = before == [Array(UnsafeRawBufferPointer(start: req, count: MemoryLayout<ClockedRequest>.stride)),
                                            Array(UnsafeRawBufferPointer(start: header, count: MemoryLayout<Header>.stride)),
                                            Array(UnsafeRawBufferPointer(start: atoms.baseAddress!, count: 179 * MemoryLayout<BelugaNetworkAdaptationOwnerWriter.Atom>.stride))]
                                        return status
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return .init(status: status, header: h, atoms: a, metadata: m, edits: e, coordinates: c, reads: r,
            inputsUnchanged: unchanged && sourceBefore == arrayBytes(source.atoms),
            deniedOutputsUntouched: beforeOutputs == [bytes(h), arrayBytes(a), bytes(m), arrayBytes(e), arrayBytes(c), arrayBytes(r)])
    }
    static var clockedLayoutIsExact: Bool {
        layoutIsExact && layout(ClockedRequest.self, 48, 8,
            [MemoryLayout<ClockedRequest>.offset(of: \ClockedRequest.abi), MemoryLayout<ClockedRequest>.offset(of: \ClockedRequest.operation),
             MemoryLayout<ClockedRequest>.offset(of: \ClockedRequest.generation), MemoryLayout<ClockedRequest>.offset(of: \ClockedRequest.invocation),
             MemoryLayout<ClockedRequest>.offset(of: \ClockedRequest.show), MemoryLayout<ClockedRequest>.offset(of: \ClockedRequest.minimum),
             MemoryLayout<ClockedRequest>.offset(of: \ClockedRequest.flag), MemoryLayout<ClockedRequest>.offset(of: \ClockedRequest.minimum_present)],
            [0, 4, 8, 16, 24, 32, 40, 44])
    }
}

// Append to the existing codec. Boundary field/initializer/closed-result hunks
// are part of the companion enrollment patch. No new guard or actor writer.

/// Sealed lossless reader for the 54 Prepared scalar fields, never a policy setter.
struct BelugaNetworkAdaptationPreparedReader {
    private let atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
    private var cursor = 168
    fileprivate init(_ atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]) { self.atoms = atoms }
    private mutating func word(_ kind: UInt32, required: Bool = false) throws -> UInt64? {
        guard atoms.count == 222, atoms.indices.contains(cursor) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        let a = atoms[cursor]; cursor += 1
        guard a.kind == kind, a.present <= 1, a.high == 0,
              a.present != 0 || (!required && a.low == 0) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return a.present == 0 ? nil : a.low
    }
    mutating func unsigned() throws -> UInt64? { try word(1) }
    mutating func requiredUnsigned() throws -> UInt64 { try word(1, required: true)! }
    mutating func integer() throws -> Int { Int(Int64(bitPattern: try word(2, required: true)!)) }
    mutating func scalar() throws -> Double? { try word(3).map(Double.init(bitPattern:)) }
    mutating func boolean() throws -> Bool {
        let n = try word(4, required: true)!
        guard n <= 1 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }; return n == 1
    }
    mutating func optionalBoolean() throws -> Bool? {
        guard let n = try word(4) else { return nil }
        guard n <= 1 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }; return n == 1
    }
    mutating func choice<T>(_ cases: [T]) throws -> T {
        let n = try word(6, required: true)!
        guard n <= UInt64(UInt32.max), n < UInt64(cases.count) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return cases[Int(n)]
    }
    mutating func optionalChoice<T>(_ cases: [T]) throws -> T? {
        guard let n = try word(6) else { return nil }
        guard n <= UInt64(UInt32.max), n < UInt64(cases.count) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return cases[Int(n)]
    }
    mutating func optionalTier() throws -> WorldwideScreenVideoAdaptationTier? {
        guard let n = try word(7), n <= 7, let tier = WorldwideScreenVideoAdaptationTier(rawValue: Int(n)) else {
            // Nil is represented by an absent canonical atom, not a forged enum.
            if atoms[cursor - 1].present == 0 { return nil }
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return tier
    }
    fileprivate mutating func recommendation() throws -> WorldwideScreenVideoEncodingRecommendation {
        guard let tier = try optionalTier() else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        let video = try integer(), total = try integer(), fps = try integer()
        guard let scale = try scalar() else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return .init(tier: tier, maximumBitrateBps: video, maximumTotalRTPBitrateBps: total,
            maximumFramesPerSecond: fps, scaleResolutionDownBy: scale)
    }
    fileprivate mutating func absent(_ kinds: [UInt32]) throws {
        for kind in kinds { guard try word(kind) == nil else { throw BelugaNetworkAdaptationOwnerError.invalidResult } }
    }
    fileprivate func finished() throws { guard cursor == 222 else { throw BelugaNetworkAdaptationOwnerError.invalidResult } }
}

struct BelugaNetworkAdaptationPreparedTail {
    enum Lane: Equatable { case regular, capacity, expiry }
    enum RouteAction: Equatable { case retain, clear, copyIncoming }
    let generation: UInt64; let expectedRevision: UInt64; let applyingRevision: UInt64
    let lane: Lane; let captureActive: Bool; let capacityOnly: Bool
    let changed: WorldwideScreenVideoEncodingRecommendation?
    let recommendation: WorldwideScreenVideoEncodingRecommendation
    let routeAction: RouteAction
    let floor: WorldwideScreenFloorRecoveryDiagnostics?
    let capacity: WorldwideScreenCapacityProbeDiagnostics?
    private static let floorKinds: [UInt32] = [1,4,4,4,4,2,1,1,1,1,1,3,3,1,2,2,6,6,6,6,1,6,4]
    private static let capacityKinds: [UInt32] = [6,7,1,1,1,2,2,1,1,1,1]
    fileprivate init(atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]) throws {
        var r = BelugaNetworkAdaptationPreparedReader(atoms)
        generation = try r.requiredUnsigned(); expectedRevision = try r.requiredUnsigned()
        applyingRevision = try r.requiredUnsigned(); lane = try r.choice([.regular, .capacity, .expiry])
        captureActive = try r.boolean(); capacityOnly = try r.boolean()
        if try r.boolean() { changed = try r.recommendation() }
        else { try r.absent([7,2,2,2,3]); changed = nil }
        recommendation = try r.recommendation(); routeAction = try r.choice([.retain, .clear, .copyIncoming])
        if try r.boolean() { floor = try .init(networkAdaptationPreparedReader: &r) }
        else { try r.absent(Self.floorKinds); floor = nil }
        if try r.boolean() { capacity = try .init(networkAdaptationPreparedReader: &r) }
        else { try r.absent(Self.capacityKinds); capacity = nil }
        try r.finished()
    }
    fileprivate static func write(_ r: WorldwideScreenVideoEncodingRecommendation,
        into w: inout BelugaNetworkAdaptationOwnerWriter) {
        w.tier(r.tier); w.integer(r.maximumBitrateBps); w.integer(r.maximumTotalRTPBitrateBps)
        w.integer(r.maximumFramesPerSecond); w.scalar(r.scaleResolutionDownBy)
    }
    fileprivate func write(into w: inout BelugaNetworkAdaptationOwnerWriter) {
        w.unsigned(generation); w.unsigned(expectedRevision); w.unsigned(applyingRevision)
        w.u32(lane == .regular ? 0 : (lane == .capacity ? 1 : 2))
        w.boolean(captureActive); w.boolean(capacityOnly); w.boolean(changed != nil)
        if let changed { Self.write(changed, into: &w) } else { for kind: UInt32 in [7,2,2,2,3] { w.word(kind, nil) } }
        Self.write(recommendation, into: &w)
        w.u32(routeAction == .retain ? 0 : (routeAction == .clear ? 1 : 2))
        w.boolean(floor != nil)
        if let floor { floor.networkAdaptationOwnerWritePrepared(into: &w) }
        else { for kind in Self.floorKinds { w.word(kind, nil) } }
        w.boolean(capacity != nil)
        if let capacity { capacity.networkAdaptationOwnerWritePrepared(into: &w) }
        else { for kind in Self.capacityKinds { w.word(kind, nil) } }
    }
}

/// Only the validated terminal Regular501 importer constructs this five-field cut.
struct BelugaNetworkAdaptationTerminalPolicyImport {
    let healthyUpgrades: Int; let limitedUpgrades: Int
    let startupDisproved: Bool; let sparseDeadline: ContinuousClock.Instant?
    fileprivate init(healthy: Int, limited: Int, disproved: Bool, sparse: ContinuousClock.Instant?) {
        healthyUpgrades = healthy; limitedUpgrades = limited
        startupDisproved = disproved; sparseDeadline = sparse
    }
}

/// Validated immutable native draft. No live-owner setter or native effect grant.
struct BelugaNetworkAdaptationTerminalPreparedValue {
    let source: BelugaNetworkAdaptationOwnerSnapshot
    let policy: WorldwideScreenVideoAdaptationPolicy
    let tail: BelugaNetworkAdaptationPreparedTail
    let policyTimes: [ContinuousClock.Instant?]
    let report: BelugaNetworkAdaptationOwnerReportSnapshot
    let observedAt: ContinuousClock.Instant
    let atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
    fileprivate init(source: BelugaNetworkAdaptationOwnerSnapshot, policy: WorldwideScreenVideoAdaptationPolicy,
        tail: BelugaNetworkAdaptationPreparedTail, times: [ContinuousClock.Instant?],
        report: BelugaNetworkAdaptationOwnerReportSnapshot, observed: ContinuousClock.Instant,
        atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]) {
        self.source = source; self.policy = policy; self.tail = tail; policyTimes = times
        self.report = report; observedAt = observed; self.atoms = atoms
    }
}

fileprivate final class BelugaNetworkAdaptationPreparedUse {
    // Retain the exact originating guard; an address token alone can be reused.
    let boundary: BelugaNetworkAdaptationOwnerBoundary; let invocation: UInt64
    private var spent = false
    init(boundary: BelugaNetworkAdaptationOwnerBoundary, invocation: UInt64) { self.boundary = boundary; self.invocation = invocation }
    func spend(by boundary: BelugaNetworkAdaptationOwnerBoundary) throws {
        guard !spent else { throw BelugaNetworkAdaptationOwnerError.refused }
        spent = true // rejection also spends; no replay on a different/current owner
        guard self.boundary === boundary else { throw BelugaNetworkAdaptationOwnerError.refused }
    }
}

/// Constructor sealed to this codec after one held factory/read/raw/import span.
/// A receipt retains ORIGINAL actual resources/report/route/13Instants/anchor.
/// It retains its Boundary identity, not a held scope/frame/lock, and is not Sendable.
/// It cannot publish or supply new entry votes.
final class BelugaNetworkAdaptationPreparedReceipt {
    fileprivate let entry: BelugaNetworkAdaptationNativePrepareEntry
    fileprivate let value: BelugaNetworkAdaptationTerminalPreparedValue
    fileprivate let use: BelugaNetworkAdaptationPreparedUse
    fileprivate init(entry: BelugaNetworkAdaptationNativePrepareEntry,
        value: BelugaNetworkAdaptationTerminalPreparedValue,
        boundary: BelugaNetworkAdaptationOwnerBoundary, invocation: UInt64) {
        self.entry = entry; self.value = value
        use = .init(boundary: boundary, invocation: invocation)
    }
}

/// No provider exists in this frame. ANY requested callback sticky-poisons the
/// outer guard, including null/malformed requests and a swallowed denial.
fileprivate protocol BelugaNetworkAdaptationPrepareClock: AnyObject {
    func reply(invocation: UInt64, site: UInt32, ordinal: UInt32,
        destination: UnsafeMutablePointer<beluga_core_adaptation_clock_reply_t>?) -> UInt32
}

final class BelugaNetworkAdaptationPrepareEmptyClock: BelugaNetworkAdaptationPrepareClock {
    fileprivate private(set) var denied = false
    private var active = true
    private let poison: () -> Void
    fileprivate init(poison: @escaping () -> Void) { self.poison = poison }
    fileprivate func retire() { active = false }
    fileprivate func deny() -> UInt32 { denied = true; if active { poison() }; return 0 }
    fileprivate func reply(invocation: UInt64, site: UInt32, ordinal: UInt32,
        destination: UnsafeMutablePointer<beluga_core_adaptation_clock_reply_t>?) -> UInt32 { deny() }
    #if DEBUG
    func testUnexpectedRequest() -> UInt32 { deny() }
    #endif
}

/// A bounded POSSIBLE-cut capability, not a second policy evaluator. Regular's
/// original call graph permits (QueueReset | RTTEvent,RTTApply)* with at most13
/// reads. Capacity/Expiry can only perform one optional QueueReset. Published
/// lease/CopyFence are not reachable here. The successful actual transcript is
/// checked separately, not used to grant its own read permission.
final class BelugaNetworkAdaptationGeneralPrepareClock: BelugaNetworkAdaptationPrepareClock {
    typealias Reply = beluga_core_adaptation_clock_reply_t
    fileprivate let invocation: UInt64
    fileprivate private(set) var reads: [Reply] = []
    fileprivate private(set) var instants: [ContinuousClock.Instant] = []
    fileprivate private(set) var denied = false
    private let regular: Bool
    private let maximumReads: Int
    private let prefix: [UInt32]
    private let anchor: ContinuousClock.Instant
    private let provider: () throws -> ContinuousClock.Instant
    private let poisoned: () -> Bool
    private var active = true
    private var reading = false
    private var awaitingApply = false
    fileprivate var complete: Bool { !denied && !awaitingApply && reads.count >= prefix.count }
    fileprivate init(invocation: UInt64, source: BelugaNetworkAdaptationOwnerSnapshot,
        generation: UInt64, reportPresent: Bool, capacityOnly: Bool, anchor: ContinuousClock.Instant,
        provider: @escaping () throws -> ContinuousClock.Instant, poisoned: @escaping () -> Bool) {
        self.invocation = invocation; self.anchor = anchor
        let regularLane = reportPresent && !capacityOnly
        let binding = regularLane && source.value.policy.peerGeneration != generation
        let terminal = regularLane && !binding && source.value.policy.hasNativeAdaptationPolicyFault
        regular = regularLane && !terminal
        prefix = binding ? [2, 0, 1, 0, 1] : []
        maximumReads = regular ? 13 : (source.atoms[20].present == 1 ? 1 : 0)
        self.provider = provider; self.poisoned = poisoned
    }
    fileprivate func retire() { active = false }
    fileprivate func reply(invocation: UInt64, site: UInt32, ordinal: UInt32,
        destination: UnsafeMutablePointer<Reply>?) -> UInt32 {
        guard active, !reading, !denied, !poisoned(), let destination,
              UInt(bitPattern: destination) % UInt(MemoryLayout<Reply>.alignment) == 0,
              invocation == self.invocation, Int(ordinal) == reads.count,
              reads.count < maximumReads,
              reads.count >= prefix.count || site == prefix[reads.count],
              (regular ? (awaitingApply ? site == 1 : (site == 0 || site == 2)) : site == 2) else {
            denied = true; return 0
        }
        reading = true
        defer { reading = false }
        do {
            let now = try provider()
            guard active, !poisoned() else { denied = true; return 0 }
            let relative = OwnerAttoseconds(anchor.duration(to: now))
            guard relative.fitsCodecTime else { denied = true; return 0 }
            let reply = Reply(abi: 1, status: 1, site: site, ordinal: ordinal,
                invocation: invocation, high: relative.high, low: relative.low, reserved: 0)
            awaitingApply = site == 0
            instants.append(now)
            reads.append(reply)
            destination.pointee = reply
            return 1
        } catch { denied = true; return 0 }
    }
    #if DEBUG
    func testRequest(invocation: UInt64, site: UInt32, ordinal: UInt32) -> UInt32 {
        var r = Reply()
        return reply(invocation: invocation, site: site, ordinal: ordinal, destination: &r)
    }
    #endif
}

/// An unpublished, fully recaptured501 draft. Scalars cannot manufacture this
/// value or grant native apply authority; producer closures stay in the policy.
struct BelugaNetworkAdaptationGeneralPreparedValue {
    let source: BelugaNetworkAdaptationOwnerSnapshot
    let policy: WorldwideScreenVideoAdaptationPolicy
    let tail: BelugaNetworkAdaptationPreparedTail
    let policyTimes: [ContinuousClock.Instant?]
    let report: BelugaNetworkAdaptationGeneralReportSnapshot
    let observedAt: ContinuousClock.Instant
    let clockInstants: [ContinuousClock.Instant]
    let atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
    fileprivate init(source: BelugaNetworkAdaptationOwnerSnapshot,
        policy: WorldwideScreenVideoAdaptationPolicy, tail: BelugaNetworkAdaptationPreparedTail,
        times: [ContinuousClock.Instant?], report: BelugaNetworkAdaptationGeneralReportSnapshot,
        observed: ContinuousClock.Instant, clockInstants: [ContinuousClock.Instant],
        atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]) {
        self.source = source; self.policy = policy; self.tail = tail; policyTimes = times
        self.report = report; observedAt = observed; self.clockInstants = clockInstants; self.atoms = atoms
    }
}

final class BelugaNetworkAdaptationGeneralPreparedReceipt {
    fileprivate let entry: BelugaNetworkAdaptationNativeGeneralPrepareEntry
    fileprivate let value: BelugaNetworkAdaptationGeneralPreparedValue
    fileprivate let use: BelugaNetworkAdaptationPreparedUse
    fileprivate init(entry: BelugaNetworkAdaptationNativeGeneralPrepareEntry,
        value: BelugaNetworkAdaptationGeneralPreparedValue,
        boundary: BelugaNetworkAdaptationOwnerBoundary, invocation: UInt64) {
        self.entry = entry; self.value = value
        use = .init(boundary: boundary, invocation: invocation)
    }
}

extension BelugaNetworkAdaptationOwnerBoundary {
    typealias GeneralPrepareProducer = (PrepareRequest, BelugaNetworkAdaptationOwnerSnapshot,
        BelugaNetworkAdaptationGeneralReportSnapshot, Coordinate,
        BelugaNetworkAdaptationGeneralPrepareClock) throws -> PrepareRawResult

    // Full501 factory is release-shaped but UNWIRED. Native admission belongs
    // to the original actor; telemetry cannot supply flags or a peer witness.
    func prepareGeneral(on owner: isolated WorldwideScreenService,
        snapshot: WebRTCStatisticsSnapshot?, nativeTimestamp: Double?, sourcePeer: WebRTCPeer,
        generation: UInt64, expectedRevision: UInt64, capacityOnly: Bool,
        allowsResume: Bool) throws -> BelugaNetworkAdaptationGeneralPreparedReceipt? {
        let result = try withGuard { scope in
            guard let entry = owner.networkAdaptationGeneralPrepareEntry(boundary: self,
                snapshot: snapshot, timestamp: nativeTimestamp, sourcePeer: sourcePeer,
                generation: generation, revision: expectedRevision, capacityOnly: capacityOnly,
                allowsResume: allowsResume) else { return .generalPrepared(nil) }
            let initial = try BelugaNetworkAdaptationOwnerSnapshot.capture(entry.value)
            try Self.admitGeneralPrepare(initial, generation: generation, revision: expectedRevision,
                reportPresent: snapshot != nil, capacityOnly: capacityOnly)
            let report = try BelugaNetworkAdaptationGeneralReportSnapshot.capture(snapshot,
                timestamp: nativeTimestamp, retainingRoute: initial.route)
            guard try owner.networkAdaptationGeneralPrepareIsCurrent(entry, original: initial) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            let observed = try clockProvider()
            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
            let source = try BelugaNetworkAdaptationOwnerSnapshot.capture(entry.value,
                retainingAnchor: initial.anchor ?? observed)
            guard try owner.networkAdaptationGeneralPrepareIsCurrent(entry, original: source) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            let draft = try prepareGeneralHeld(source: source, report: report, generation: generation,
                revision: expectedRevision, flags: entry.flags, active: entry.active,
                capacityOnly: capacityOnly, allowsResume: entry.allowsResume, observed: observed, scope: scope)
            guard !poisoned, try owner.networkAdaptationGeneralPrepareIsCurrent(entry, original: source) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            return .generalPrepared(draft.map { .init(entry: entry, value: $0, boundary: self, invocation: scope.invocation) })
        }
        guard case let .generalPrepared(value) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return value
    }

    func retireGeneralPrepared(_ receipt: BelugaNetworkAdaptationGeneralPreparedReceipt,
        on owner: isolated WorldwideScreenService) throws {
        let result = try withPreparedGuard(receipt.use) { _ in
            guard receipt.entry.owner === owner, receipt.entry.boundary === self,
                  try owner.networkAdaptationGeneralPrepareIsCurrent(receipt.entry, original: receipt.value.source),
                  !poisoned else { throw BelugaNetworkAdaptationOwnerError.refused }
            return .retired
        }
        guard case .retired = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
    }

    private static func admitGeneralPrepare(_ source: BelugaNetworkAdaptationOwnerSnapshot,
        generation: UInt64, revision: UInt64, reportPresent: Bool, capacityOnly: Bool) throws {
        guard prepareLayoutIsExact, source.atoms.count == 179, source.value.revision == revision else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        // All lanes may age/apply RTT evidence. Capacity/Expiry skip demand
        // selection, but do not skip the retained RTT producer's provenance.
        guard source.value.policy.networkAdaptationOwnerRTTApplicationIsAdmitted else {
            throw BelugaNetworkAdaptationOwnerError.malformedNativeImage
        }
        if reportPresent && !capacityOnly {
            guard source.value.policy.networkAdaptationOwnerDemandApplicationIsAdmitted else {
                throw BelugaNetworkAdaptationOwnerError.malformedNativeImage
            }
        }
        // Every possible Q cut converts this original native queue pressure.
        let regular = reportPresent && !capacityOnly
        let boundTerminal = regular && source.value.policy.peerGeneration == generation
            && source.value.policy.hasNativeAdaptationPolicyFault
        let mayReset = (regular && !boundTerminal) || source.atoms[20].present == 1
        guard !mayReset || Int64(bitPattern: source.atoms[38].low) >= 0 else {
            throw BelugaNetworkAdaptationOwnerError.malformedNativeImage
        }
    }

    private func prepareGeneralHeld(source: BelugaNetworkAdaptationOwnerSnapshot,
        report: BelugaNetworkAdaptationGeneralReportSnapshot, generation: UInt64,
        revision: UInt64, flags: UInt32, active: Bool, capacityOnly: Bool,
        allowsResume: Bool, observed: ContinuousClock.Instant, scope: HeldScope) throws -> BelugaNetworkAdaptationGeneralPreparedValue? {
        guard let anchor = source.anchor else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        let relative = OwnerAttoseconds(anchor.duration(to: observed))
        guard relative.fitsCodecTime else { throw BelugaNetworkAdaptationOwnerError.unrepresentableTime }
        let q = PrepareRequest(abi: 1, operation: 501, invocation: scope.invocation,
            source_generation: generation, expected_revision: revision, current_generation: generation,
            entry_flags: flags, capacity_only: capacityOnly ? 1 : 0,
            allows_resume: allowsResume ? 1 : 0, report_present: report.snapshot == nil ? 0 : 1)
        let frame = BelugaNetworkAdaptationGeneralPrepareClock(invocation: scope.invocation, source: source,
            generation: generation, reportPresent: report.snapshot != nil, capacityOnly: capacityOnly,
            anchor: anchor, provider: clockProvider, poisoned: { self.poisoned })
        defer { frame.retire() }
        let raw = try generalPrepareProducer(q, source, report,
            .init(present: 1, reserved: 0, high: relative.high, low: relative.low), frame)
        frame.retire()
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard raw.inputsUnchanged else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        if (2...5).contains(raw.status) {
            guard raw.deniedOutputsUntouched else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        guard raw.status == 1, frame.complete, frame.reads.count == frame.instants.count,
              raw.atoms.count == 222, raw.edits.count == 13, raw.coordinates.count == 13, raw.reads.count == 15 else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        for i in 0..<15 {
            guard Self.bytes(raw.reads[i]) == Self.bytes(i < frame.reads.count ? frame.reads[i] : Reply()) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        let m = raw.metadata, o = raw.outcome
        guard o.abi == 1, o.operation == 501, o.invocation == scope.invocation,
              o.prepared_present <= 1, o.reserved == 0,
              m.abi == 1, m.operation == 501, m.scope == 1, m.invocation == scope.invocation,
              m.read_count == UInt32(frame.reads.count), m.revision == revision,
              m.bound == 0, m.sample == 0, m.enabled == 0, m.lease == 0 else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        if o.prepared_present == 0 {
            // Only the original no-report expiry path can return late None from
            // an admitted entry. A real consumed Q is not rolled back or cached.
            guard report.snapshot == nil, Self.bytes(raw.header) == Self.bytes(Header()),
                  raw.atoms.allSatisfy({ Self.bytes($0) == Self.bytes(BelugaNetworkAdaptationOwnerWriter.Atom()) }),
                  raw.edits.allSatisfy({ Self.bytes($0) == Self.bytes(Edit()) }),
                  raw.coordinates.allSatisfy({ Self.bytes($0) == Self.bytes(Coordinate()) }),
                  m.peer_present == source.atoms[3].present, m.peer == source.atoms[3].low,
                  m.route == 0, m.queue_fault == UInt32(source.atoms[41].low), m.rtt_fault == UInt32(source.atoms[89].low) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            return nil
        }
        guard raw.header.abi == 1, raw.header.domain == 4, raw.header.phase == 3, raw.header.count == 222 else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let tail = try BelugaNetworkAdaptationPreparedTail(atoms: raw.atoms)
        let regular = report.snapshot != nil && !capacityOnly
        let lane: BelugaNetworkAdaptationPreparedTail.Lane = report.snapshot == nil ? .expiry : (regular ? .regular : .capacity)
        guard tail.generation == generation, tail.expectedRevision == revision, tail.applyingRevision == revision,
              tail.lane == lane, tail.captureActive == active, tail.capacityOnly == capacityOnly,
              active || tail.changed == nil,
              (tail.floor != nil) == regular, (tail.capacity != nil) == (lane == .capacity),
              m.peer_present == raw.atoms[3].present, m.peer == raw.atoms[3].low,
              UInt64(m.queue_fault) == raw.atoms[41].low, UInt64(m.rtt_fault) == raw.atoms[89].low else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        var fields = regular ? Set(3...89).union([140]).union(Set(143...167))
            : Set([4, 5]).union(Set(9...28)).union(Set(36...89)).union(Set(145...148))
                .union(Set(156...160)).union(Set(164...167))
        if lane == .capacity { fields.formUnion([149, 150, 151]) }
        // An ORIGINAL sticky-denied subowner never writes its opaque stored
        // image, even if another helper performs an original clock cut. A broad
        // mechanical importer must not let forged output replace that image.
        if source.atoms[41].low == 1 { fields.subtract(Set(36...41)) }
        if source.atoms[89].low == 1 { fields.subtract(Set(42...88)) }
        // Original terminal denial returns before demand selection. This is
        // retained dependency custody, not a second recommendation evaluator.
        if source.value.policy.hasNativeAdaptationPolicyFault { fields.remove(140) }
        for i in 0..<168 {
            let a = raw.atoms[i], before = source.atoms[i]
            guard a.kind == before.kind, a.present <= 1,
                  a.present != 0 || (a.high == 0 && a.low == 0), a.kind == 10 || a.high == 0 else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            if !fields.contains(i) {
                guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms([a], [before]) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
            }
        }
        let route: WebRTCICERouteDiagnostics?
        switch tail.routeAction {
        case .retain: route = source.route; guard m.route == 0 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        case .clear: route = nil; guard regular, m.route == 1 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        case .copyIncoming:
            guard regular, let incoming = report.incomingRoute, m.route == 2 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            route = incoming
        }
        let mask = regular ? UInt16(0x01ff) : UInt16(0x00ef)
        var times = source.times
        for i in 0..<13 {
            let edit = raw.edits[i], coordinate = raw.coordinates[i]
            if mask & (1 << i) == 0 {
                guard Self.bytes(edit) == Self.bytes(Edit()), Self.bytes(coordinate) == Self.bytes(Coordinate()) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
                continue
            }
            switch edit.action {
            case 1, 2:
                guard edit.source == 0, edit.index == 0, edit.ordinal == 0, edit.high == 0, edit.low == 0 else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
                if edit.action == 2 { times[i] = nil }
            case 3:
                guard edit.ordinal == 0, edit.high == 0 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                if i == 5 {
                    guard lane != .expiry, edit.source == 1, edit.index == 0, edit.low == 0,
                          let originalDeadline = source.times[0] else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                    times[i] = originalDeadline
                } else {
                    let delta: UInt64 = i == 0 ? 3_500_000_000_000_000_000 : (i == 2 ? 2_000_000_000_000_000_000 : 0)
                    guard regular, edit.source == 3, edit.index == 0, edit.low == delta else {
                        throw BelugaNetworkAdaptationOwnerError.invalidResult
                    }
                    times[i] = observed.advanced(by: i == 0 ? .milliseconds(3_500) : (i == 2 ? .seconds(2) : .zero))
                }
            default: throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            var w = BelugaNetworkAdaptationOwnerWriter(anchor: anchor)
            try w.time(times[i])
            let a = w.atoms[0]
            guard Self.bytes(coordinate) == Self.bytes(Coordinate(present: a.present, reserved: 0, high: a.high, low: a.low)) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        var policy = source.value.policy
        try policy.networkAdaptationOwnerImportClocked(.init(atoms: Array(raw.atoms.prefix(168)),
            fields: fields, times: times, route: route))
        let value = BelugaNetworkAdaptationOwnerValue(policy: policy, revision: source.value.revision,
            fastStatisticsAvailable: source.value.fastStatisticsAvailable, lane: source.value.lane,
            evidenceTime: source.value.evidenceTime, minimumCollectionSequence: source.value.minimumCollectionSequence,
            applied: source.value.applied)
        let native = try BelugaNetworkAdaptationOwnerSnapshot.capture(value, retainingAnchor: anchor)
        var w = BelugaNetworkAdaptationOwnerWriter(anchor: anchor)
        try policy.networkAdaptationOwnerWrite(into: &w); tail.write(into: &w)
        guard !poisoned, BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(w.atoms, raw.atoms),
              native.times == times, native.route == route, native.anchor == anchor else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        func recommendationAtoms(_ r: WorldwideScreenVideoEncodingRecommendation) -> [BelugaNetworkAdaptationOwnerWriter.Atom] {
            var w = BelugaNetworkAdaptationOwnerWriter(anchor: nil)
            BelugaNetworkAdaptationPreparedTail.write(r, into: &w); return w.atoms
        }
        let expected = recommendationAtoms(policy.currentRecommendation)
        guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(recommendationAtoms(tail.recommendation), expected),
              tail.changed == nil || BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(recommendationAtoms(tail.changed!), expected) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return .init(source: source, policy: policy, tail: tail, times: Array(times.prefix(9)), report: report,
            observed: observed, clockInstants: frame.instants, atoms: w.atoms)
    }

    #if DEBUG
    // Pure read-capability assay only. Not an actor entry or Prepared receipt.
    func testGeneralClock(_ value: BelugaNetworkAdaptationOwnerValue, generation: UInt64 = 77,
        reportPresent: Bool = true, capacityOnly: Bool = false) throws -> BelugaNetworkAdaptationGeneralPrepareClock {
        let source = try BelugaNetworkAdaptationOwnerSnapshot.capture(value)
        guard let anchor = source.anchor else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return .init(invocation: 1, source: source, generation: generation,
            reportPresent: reportPresent, capacityOnly: capacityOnly, anchor: anchor,
            provider: clockProvider, poisoned: { self.poisoned })
    }
    func testGeneralPreparedValue(_ value: BelugaNetworkAdaptationOwnerValue,
        snapshot: WebRTCStatisticsSnapshot?, nativeTimestamp: Double? = nil,
        generation: UInt64 = 77, expectedRevision: UInt64 = 57,
        active: Bool = true, capacityOnly: Bool = false) throws -> BelugaNetworkAdaptationGeneralPreparedValue? {
        let result = try withGuard { scope in
            let initial = try BelugaNetworkAdaptationOwnerSnapshot.capture(value)
            try Self.admitGeneralPrepare(initial, generation: generation, revision: expectedRevision,
                reportPresent: snapshot != nil, capacityOnly: capacityOnly)
            let report = try BelugaNetworkAdaptationGeneralReportSnapshot.capture(snapshot,
                timestamp: nativeTimestamp, retainingRoute: initial.route)
            let observed = try clockProvider()
            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
            let source = try BelugaNetworkAdaptationOwnerSnapshot.capture(value, retainingAnchor: initial.anchor ?? observed)
            return .generalFixture(try prepareGeneralHeld(source: source, report: report, generation: generation,
                revision: expectedRevision, flags: active ? 127 : 3, active: active,
                capacityOnly: capacityOnly, allowsResume: !active, observed: observed, scope: scope))
        }
        guard case let .generalFixture(value) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return value
    }
    #endif
}

extension BelugaNetworkAdaptationOwnerBoundary {
    typealias PrepareRequest = beluga_core_adaptation_owner_prepare_request_t
    typealias PrepareOutcome = beluga_core_adaptation_owner_prepare_outcome_t
    struct PrepareRawResult {
        let status: UInt32; var header: Header; var atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
        var metadata: Metadata; var outcome: PrepareOutcome
        var edits: [Edit]; var coordinates: [Coordinate]; var reads: [Reply]
        let inputsUnchanged: Bool; let deniedOutputsUntouched: Bool
    }
    typealias PrepareProducer = (PrepareRequest, BelugaNetworkAdaptationOwnerSnapshot,
        BelugaNetworkAdaptationOwnerReportSnapshot, Coordinate,
        BelugaNetworkAdaptationPrepareEmptyClock) throws -> PrepareRawResult

    /// The actual factory is invoked inside ONE guard on the owner's executor.
    /// No pre-evaluated Owner/entry flags or caller-built native witness is accepted.
    /// Telemetry is not a native collector/adoption receipt; no event is wired yet.
    func prepareTerminalFault(on owner: isolated WorldwideScreenService,
        report: WebRTCScreenVideoStatisticsReport, sourcePeer: WebRTCPeer,
        generation: UInt64, expectedRevision: UInt64, allowsResume: Bool) throws -> BelugaNetworkAdaptationPreparedReceipt? {
        let result = try withGuard { scope in
            guard let entry = owner.networkAdaptationTerminalPrepareEntry(boundary: self, report: report,
                sourcePeer: sourcePeer, generation: generation, revision: expectedRevision,
                allowsResume: allowsResume) else { return .prepared(nil) }
            let initial = try BelugaNetworkAdaptationOwnerSnapshot.capture(entry.value)
            try Self.admitTerminalPrepare(initial, generation: generation, revision: expectedRevision)
            let capturedReport = try BelugaNetworkAdaptationOwnerReportSnapshot.capture(entry.report, retainingRoute: initial.route)
            guard try owner.networkAdaptationTerminalPrepareIsCurrent(entry, original: initial) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            // The one original policy.update default observedAt cut, AFTER entry
            // and local capture/shape admission. [] is NOT zero total clocks.
            let observed = try clockProvider()
            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
            let source = try BelugaNetworkAdaptationOwnerSnapshot.capture(entry.value,
                retainingAnchor: initial.anchor ?? observed)
            guard try owner.networkAdaptationTerminalPrepareIsCurrent(entry, original: source) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            let draft = try prepareTerminalHeld(source: source, report: capturedReport,
                generation: generation, revision: expectedRevision, flags: entry.flags,
                active: entry.active, allowsResume: entry.allowsResume, observed: observed, scope: scope)
            guard !poisoned, try owner.networkAdaptationTerminalPrepareIsCurrent(entry, original: source) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            return .prepared(.init(entry: entry, value: draft,
                boundary: self, invocation: scope.invocation))
        }
        guard case let .prepared(receipt) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return receipt
    }

    /// Consumption precedes guard entry: busy/exhausted/wrong-boundary attempts
    /// cannot leave a receipt usable. No naked copied draft grants native custody.
    func retirePrepared(_ receipt: BelugaNetworkAdaptationPreparedReceipt,
        on owner: isolated WorldwideScreenService) throws {
        let result = try withPreparedGuard(receipt.use) { _ in
            guard receipt.entry.owner === owner, receipt.entry.boundary === self,
                  try owner.networkAdaptationTerminalPrepareIsCurrent(receipt.entry,
                original: receipt.value.source), !poisoned else { throw BelugaNetworkAdaptationOwnerError.refused }
            return .retired
        }
        guard case .retired = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
    }

    private static func admitTerminalPrepare(_ source: BelugaNetworkAdaptationOwnerSnapshot,
        generation: UInt64, revision: UInt64) throws {
        guard prepareLayoutIsExact, source.value.policy.peerGeneration == generation,
              source.value.revision == revision, source.value.policy.hasNativeAdaptationPolicyFault,
              source.value.policy.applicationLimitedProbeOriginTier == nil else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
    }

    private func prepareTerminalHeld(source: BelugaNetworkAdaptationOwnerSnapshot,
        report: BelugaNetworkAdaptationOwnerReportSnapshot, generation: UInt64,
        revision: UInt64, flags: UInt32, active: Bool, allowsResume: Bool,
        observed: ContinuousClock.Instant, scope: HeldScope) throws -> BelugaNetworkAdaptationTerminalPreparedValue {
        guard let anchor = source.anchor else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        let relative = OwnerAttoseconds(anchor.duration(to: observed))
        guard relative.fitsCodecTime else { throw BelugaNetworkAdaptationOwnerError.unrepresentableTime }
        let coordinate = Coordinate(present: 1, reserved: 0, high: relative.high, low: relative.low)
        let request = PrepareRequest(abi: 1, operation: 501, invocation: scope.invocation,
            source_generation: generation, expected_revision: revision, current_generation: generation,
            entry_flags: flags, capacity_only: 0, allows_resume: allowsResume ? 1 : 0, report_present: 1)
        let frame = BelugaNetworkAdaptationPrepareEmptyClock(poison: { self.poisoned = true })
        defer { frame.retire() }
        let raw = try prepareProducer(request, source, report, coordinate, frame)
        frame.retire()
        guard raw.inputsUnchanged else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        if (2...5).contains(raw.status) {
            guard raw.deniedOutputsUntouched else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        guard !poisoned, !frame.denied else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard raw.status == 1, raw.header.abi == 1, raw.header.domain == 4,
              raw.header.phase == 3, raw.header.count == 222, raw.atoms.count == 222,
              raw.edits.count == 13, raw.coordinates.count == 13, raw.reads.count == 15 else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let m = raw.metadata, o = raw.outcome
        guard o.abi == 1, o.operation == 501, o.invocation == scope.invocation,
              o.prepared_present == 1, o.reserved == 0,
              m.abi == 1, m.operation == 501, m.scope == 1, m.read_count == 0,
              m.invocation == scope.invocation, m.revision == revision, m.peer_present == 1,
              m.peer == generation, m.bound == 0, m.route == 0, m.sample == 0,
              m.enabled == 0, m.lease == 0, m.queue_fault == UInt32(source.atoms[41].low),
              m.rtt_fault == UInt32(source.atoms[89].low),
              raw.reads.allSatisfy({ Self.bytes($0) == Self.bytes(Reply()) }) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let tail = try BelugaNetworkAdaptationPreparedTail(atoms: raw.atoms)
        guard tail.generation == generation, tail.expectedRevision == revision,
              tail.applyingRevision == revision, tail.lane == .regular,
              tail.captureActive == active, !tail.capacityOnly, tail.routeAction == .retain,
              tail.floor != nil, tail.capacity == nil else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        // Narrow permission is []. These exact original fault-prefix journals
        // can only Retain/Clear native inputs; no Set or reconstructed Instant.
        // Rejection-only correlation with the ORIGINAL cached native predicate.
        // A draft cannot invent startup disproval or a sparse assignment witness.
        let startupWasActive = source.value.policy.startupSpatialModeIsActive
        let indices = [12,23,28,159,163,167,39,40,88]
        var times = source.times
        for i in 0..<13 {
            let e = raw.edits[i], c = raw.coordinates[i]
            if i >= 9 {
                guard Self.bytes(e) == Self.bytes(Edit()), Self.bytes(c) == Self.bytes(Coordinate()) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
                continue
            }
            guard (e.action == 1 || e.action == 2), e.source == 0, e.index == 0,
                  e.ordinal == 0, e.high == 0, e.low == 0,
                  e.action != 2 || i == 2 || i == 5 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            let a = source.atoms[indices[i]]
            let expected = e.action == 1 ? Coordinate(present: a.present, reserved: 0, high: a.high, low: a.low) : Coordinate()
            guard Self.bytes(c) == Self.bytes(expected) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            if e.action == 2 { times[i] = nil }
        }
        guard raw.edits[2].action == 2, raw.edits[5].action == (startupWasActive ? 2 : 1) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let allowed: Set<Int> = [5,9,25,26,27,28,166,167]
        for i in 0..<168 where !allowed.contains(i) {
            guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms([raw.atoms[i]], [source.atoms[i]]) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        // Shape/value checks for the ONLY mutable prefix. All other168 atoms,
        // native producers, Optional route and evidence sidecars are retained.
        func exact(_ i: Int, _ kind: UInt32, _ payload: UInt64?) -> Bool {
            let expected = BelugaNetworkAdaptationOwnerWriter.Atom(kind: kind,
                present: payload == nil ? 0 : 1, high: 0, low: payload ?? 0)
            return BelugaNetworkAdaptationOwnerSnapshot.equalAtoms([raw.atoms[i]], [expected])
        }
        let expectedDisproved = startupWasActive ? 1 : source.atoms[166].low
        guard exact(5,2,0), exact(9,2,0), exact(25,4,0), exact(26,7,nil),
              exact(27,2,nil), exact(28,10,nil), exact(166,4,expectedDisproved) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        var policy = source.value.policy
        policy.networkAdaptationOwnerImportTerminalPrepared(.init(healthy: 0, limited: 0,
            disproved: raw.atoms[166].low == 1, sparse: times[5]))
        let value = BelugaNetworkAdaptationOwnerValue(policy: policy, revision: source.value.revision,
            fastStatisticsAvailable: source.value.fastStatisticsAvailable, lane: source.value.lane,
            evidenceTime: source.value.evidenceTime, minimumCollectionSequence: source.value.minimumCollectionSequence,
            applied: source.value.applied)
        let native = try BelugaNetworkAdaptationOwnerSnapshot.capture(value, retainingAnchor: source.anchor)
        var w = BelugaNetworkAdaptationOwnerWriter(anchor: source.anchor)
        try policy.networkAdaptationOwnerWrite(into: &w); tail.write(into: &w)
        guard !poisoned, w.atoms.count == 222,
              BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(w.atoms, raw.atoms),
              native.times == times, native.route == source.route, native.anchor == source.anchor else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        // Rejection correlation with actual retained native getters, not a new
        // policy decision/reducer or an input replacing Rust's proposed values.
        func recBits(_ r: WorldwideScreenVideoEncodingRecommendation) -> [BelugaNetworkAdaptationOwnerWriter.Atom] {
            var w = BelugaNetworkAdaptationOwnerWriter(anchor: nil)
            BelugaNetworkAdaptationPreparedTail.write(r, into: &w); return w.atoms
        }
        let proposed = recBits(policy.currentRecommendation)
        guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(recBits(tail.recommendation), proposed),
              tail.changed == nil || BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(recBits(tail.changed!), proposed),
              (tail.changed != nil) == (active && !BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(
                recBits(source.value.policy.currentRecommendation), proposed)) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return .init(source: source, policy: policy, tail: tail, times: Array(times.prefix(9)),
            report: report, observed: observed, atoms: w.atoms)
    }

    static func actualPrepare(_ request: PrepareRequest, _ source: BelugaNetworkAdaptationOwnerSnapshot,
        _ report: BelugaNetworkAdaptationOwnerReportSnapshot, _ observed: Coordinate,
        _ frame: BelugaNetworkAdaptationPrepareEmptyClock) throws -> PrepareRawResult {
        try actualPrepareRaw(request, source, report.wire, observed, frame)
    }

    static func actualGeneralPrepare(_ request: PrepareRequest, _ source: BelugaNetworkAdaptationOwnerSnapshot,
        _ report: BelugaNetworkAdaptationGeneralReportSnapshot, _ observed: Coordinate,
        _ frame: BelugaNetworkAdaptationGeneralPrepareClock) throws -> PrepareRawResult {
        try actualPrepareRaw(request, source, report.wire, observed, frame)
    }

    private static func actualPrepareRaw(_ request: PrepareRequest, _ source: BelugaNetworkAdaptationOwnerSnapshot,
        _ reportWire: BelugaNetworkAdaptationOwnerReportSnapshot.Wire, _ observed: Coordinate,
        _ frame: any BelugaNetworkAdaptationPrepareClock) throws -> PrepareRawResult {
        var q = request, ih = Header(abi: 1, domain: 2, phase: 1, count: 179)
        var ia = source.atoms.map { $0 }, ir = reportWire, it = observed
        var h = Header(abi: 91, domain: 92, phase: 93, count: 94)
        var a = Array(repeating: BelugaNetworkAdaptationOwnerWriter.Atom(kind: 95, present: 96, high: -97, low: 98), count: 222)
        var m = Metadata(abi: 81, operation: 82, scope: 83, read_count: 84, invocation: 85,
            revision: 86, peer: 87, peer_present: 88, bound: 89, route: 90, sample: 91,
            enabled: 92, lease: 93, queue_fault: 94, rtt_fault: 95)
        var o = PrepareOutcome(abi: 41, operation: 42, invocation: 43, prepared_present: 44, reserved: 45)
        var e = Array(repeating: Edit(action: 71, source: 72, index: 73, ordinal: 74, high: -75, low: 76), count: 13)
        var c = Array(repeating: Coordinate(present: 61, reserved: 62, high: -63, low: 64), count: 13)
        var r = Array(repeating: Reply(abi: 51, status: 52, site: 53, ordinal: 54, invocation: 55, high: -56, low: 57, reserved: 58), count: 15)
        let beforeOutputs = [bytes(h), arrayBytes(a), bytes(m), bytes(o), arrayBytes(e), arrayBytes(c), arrayBytes(r)]
        let sourceBefore = arrayBytes(source.atoms), reportBefore = bytes(reportWire)
        var unchanged = false
        let status = withExtendedLifetime(frame) {
            withUnsafePointer(to: &q) { req in withUnsafePointer(to: &ih) { header in
                ia.withUnsafeMutableBufferPointer { input in withUnsafePointer(to: &ir) { report in
                    withUnsafePointer(to: &it) { time in a.withUnsafeMutableBufferPointer { out in
                        e.withUnsafeMutableBufferPointer { edits in c.withUnsafeMutableBufferPointer { coords in
                            r.withUnsafeMutableBufferPointer { reads in
                                func inputs() -> [[UInt8]] {
                                    [Array(UnsafeRawBufferPointer(start: req, count: MemoryLayout<PrepareRequest>.stride)),
                                     Array(UnsafeRawBufferPointer(start: header, count: MemoryLayout<Header>.stride)),
                                     Array(UnsafeRawBufferPointer(start: input.baseAddress!, count: 179 * MemoryLayout<BelugaNetworkAdaptationOwnerWriter.Atom>.stride)),
                                     Array(UnsafeRawBufferPointer(start: report, count: 192)),
                                     Array(UnsafeRawBufferPointer(start: time, count: MemoryLayout<Coordinate>.stride))]
                                }
                                let before = inputs()
                                let status = beluga_core_network_adaptation_owner_prepare_event(req, header, input.baseAddress!, 179,
                                    report, time, { context, invocation, site, ordinal, reply in
                                        guard let context,
                                              let frame = Unmanaged<AnyObject>.fromOpaque(context).takeUnretainedValue()
                                                as? any BelugaNetworkAdaptationPrepareClock else { return 0 }
                                        return frame.reply(invocation: invocation, site: site, ordinal: ordinal, destination: reply)
                                    }, Unmanaged.passUnretained(frame as AnyObject).toOpaque(),
                                    &h, out.baseAddress!, 222, &m, &o, edits.baseAddress!, 13,
                                    coords.baseAddress!, 13, reads.baseAddress!, 15)
                                unchanged = before == inputs(); return status
                            }
                        } }
                    } }
                } }
            } }
        }
        return .init(status: status, header: h, atoms: a, metadata: m, outcome: o,
            edits: e, coordinates: c, reads: r,
            inputsUnchanged: unchanged && sourceBefore == arrayBytes(source.atoms) && reportBefore == bytes(reportWire),
            deniedOutputsUntouched: beforeOutputs == [bytes(h), arrayBytes(a), bytes(m), bytes(o), arrayBytes(e), arrayBytes(c), arrayBytes(r)])
    }

    static var prepareLayoutIsExact: Bool {
        typealias R = PrepareRequest; typealias O = PrepareOutcome
        return clockedLayoutIsExact
            && layout(R.self, 56, 8, [MemoryLayout<R>.offset(of: \R.abi), MemoryLayout<R>.offset(of: \R.operation),
                MemoryLayout<R>.offset(of: \R.invocation), MemoryLayout<R>.offset(of: \R.source_generation),
                MemoryLayout<R>.offset(of: \R.expected_revision), MemoryLayout<R>.offset(of: \R.current_generation),
                MemoryLayout<R>.offset(of: \R.entry_flags), MemoryLayout<R>.offset(of: \R.capacity_only),
                MemoryLayout<R>.offset(of: \R.allows_resume), MemoryLayout<R>.offset(of: \R.report_present)], [0,4,8,16,24,32,40,44,48,52])
            && layout(O.self, 24, 8, [MemoryLayout<O>.offset(of: \O.abi), MemoryLayout<O>.offset(of: \O.operation),
                MemoryLayout<O>.offset(of: \O.invocation), MemoryLayout<O>.offset(of: \O.prepared_present),
                MemoryLayout<O>.offset(of: \O.reserved)], [0,4,8,16,20])
            && MemoryLayout<BelugaNetworkAdaptationOwnerReportSnapshot.Wire>.size == 192
            && MemoryLayout<BelugaNetworkAdaptationOwnerReportSnapshot.Wire>.stride == 192
            && MemoryLayout<BelugaNetworkAdaptationOwnerReportSnapshot.Wire>.alignment == 8
    }

    #if DEBUG
    // Ordinary copied-value/import fixture ONLY, not the actual native factory
    // or a receipt constructor. It exercises the SAME guard/read/raw/import body.
    func testTerminalPreparedValue(_ value: BelugaNetworkAdaptationOwnerValue,
        report: WebRTCScreenVideoStatisticsReport, generation: UInt64 = 77,
        expectedRevision: UInt64 = 57, active: Bool = true) throws -> BelugaNetworkAdaptationTerminalPreparedValue {
        let result = try withGuard { scope in
            let initial = try BelugaNetworkAdaptationOwnerSnapshot.capture(value)
            try Self.admitTerminalPrepare(initial, generation: generation, revision: expectedRevision)
            let capturedReport = try BelugaNetworkAdaptationOwnerReportSnapshot.capture(report, retainingRoute: initial.route)
            let now = try clockProvider()
            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
            let source = try BelugaNetworkAdaptationOwnerSnapshot.capture(value, retainingAnchor: initial.anchor ?? now)
            return .terminalFixture(try prepareTerminalHeld(source: source, report: capturedReport,
                generation: generation, revision: expectedRevision, flags: active ? 127 : 3,
                active: active, allowsResume: !active, observed: now, scope: scope))
        }
        guard case let .terminalFixture(value) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }; return value
    }
    func testPreparedOneUse() -> (BelugaNetworkAdaptationOwnerBoundary, (BelugaNetworkAdaptationOwnerBoundary) throws -> Void) {
        let use = BelugaNetworkAdaptationPreparedUse(boundary: self, invocation: 1)
        return (self, { try use.spend(by: $0) })
    }
    // Pure ledger/shared guard assay, never a native receipt or actor witness.
    func testPreparedGuardUse(exhausted: Bool = false) -> (BelugaNetworkAdaptationOwnerBoundary) throws -> Void {
        if exhausted { invocation = .max }
        let use = BelugaNetworkAdaptationPreparedUse(boundary: self, invocation: 1)
        return { target in _ = try target.withPreparedGuard(use) { _ in .retired } }
    }
    static func testPreparedTailRoundtrip(_ atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]) throws -> [BelugaNetworkAdaptationOwnerWriter.Atom] {
        let tail = try BelugaNetworkAdaptationPreparedTail(atoms: atoms)
        var w = BelugaNetworkAdaptationOwnerWriter(anchor: nil); tail.write(into: &w); return w.atoms
    }
    #endif
}

// Narrow terminal-fault Regular501 -> inactive601 continuation. Still UNWIRED:
// healthy plans, native resume effects and production writer enrollment are separate.
struct BelugaNetworkAdaptationTerminalInactiveCommit {
    let entry: BelugaNetworkAdaptationNativePrepareEntry
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    fileprivate init(entry: BelugaNetworkAdaptationNativePrepareEntry,
        replacement: BelugaNetworkAdaptationOwnerSnapshot) {
        self.entry = entry; self.replacement = replacement
    }
}

extension BelugaNetworkAdaptationOwnerBoundary {
    typealias InactiveRequest = beluga_core_adaptation_owner_inactive_request_t
    typealias InactiveOutcome = beluga_core_adaptation_owner_inactive_outcome_t
    struct InactiveRawResult {
        let status: UInt32; var header: Header; var atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
        var metadata: Metadata; var outcome: InactiveOutcome
        var edits: [Edit]; var coordinates: [Coordinate]; var reads: [Reply]
        let inputsUnchanged: Bool; let deniedOutputsUntouched: Bool
    }
    typealias InactiveProducer = (InactiveRequest, BelugaNetworkAdaptationOwnerSnapshot,
        BelugaNetworkAdaptationTerminalPreparedValue, BelugaNetworkAdaptationPrepareEmptyClock) throws -> InactiveRawResult
    enum InactiveProposal { case superseded, ready(BelugaNetworkAdaptationOwnerSnapshot) }

    func publishPreparedInactive(_ receipt: BelugaNetworkAdaptationPreparedReceipt,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationOwnerPublicationDisposition {
        let result = try withPreparedGuard(receipt.use) { scope in
            let entry = receipt.entry, prepared = receipt.value
            guard entry.owner === owner, entry.boundary === self,
                  !entry.active, !prepared.tail.captureActive, entry.allowsResume,
                  let current = try owner.networkAdaptationTerminalInactiveCapture(entry, original: prepared.source) else {
                return .publication(.refused)
            }
            let proposal = try inactiveTerminalHeld(current: current, prepared: prepared,
                generation: entry.generation, exactPeer: true, suspended: entry.flags & 128 != 0, scope: scope)
            switch proposal {
            case .superseded: return .publication(.superseded)
            case let .ready(replacement):
                guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
                guard try owner.networkAdaptationTerminalPrepareIsCurrent(entry, original: current) else {
                    return .publication(.refused)
                }
                guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
                owner.networkAdaptationTerminalInactiveCommit(.init(entry: entry, replacement: replacement))
                return .publication(.accepted(.init(operation: 601, invocation: scope.invocation, collectorEnabled: false)))
            }
        }
        guard case let .publication(result) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return result
    }

    private func inactiveTerminalHeld(current: BelugaNetworkAdaptationOwnerSnapshot,
        prepared: BelugaNetworkAdaptationTerminalPreparedValue, generation: UInt64,
        exactPeer: Bool, suspended: Bool, scope: HeldScope) throws -> InactiveProposal {
        guard Self.inactiveLayoutIsExact, prepared.tail.lane == .regular,
              !prepared.tail.captureActive, !prepared.tail.capacityOnly,
              prepared.tail.routeAction == .retain, prepared.tail.floor != nil, prepared.tail.capacity == nil,
              prepared.policy.hasNativeAdaptationPolicyFault,
              prepared.policy.applicationLimitedProbeOriginTier == nil,
              current.anchor == prepared.source.anchor, current.route == prepared.source.route else {
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        let stale = !exactPeer || generation != prepared.tail.generation
            || current.value.revision != prepared.tail.expectedRevision
        let request = InactiveRequest(abi: 1, operation: 601, invocation: scope.invocation,
            current_generation: generation, exact_peer: exactPeer ? 1 : 0, suspended: suspended ? 1 : 0)
        let frame = BelugaNetworkAdaptationPrepareEmptyClock(poison: { self.poisoned = true })
        defer { frame.retire() }
        let raw = try inactiveProducer(request, current, prepared, frame)
        frame.retire()
        guard raw.inputsUnchanged else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        guard !poisoned, !frame.denied else { throw BelugaNetworkAdaptationOwnerError.reentry }
        if (2...5).contains(raw.status) {
            guard raw.deniedOutputsUntouched else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        guard raw.status == 1, raw.header.abi == 1, raw.header.domain == 2,
              raw.header.phase == 2, raw.header.count == 179, raw.atoms.count == 179,
              raw.edits.count == 13, raw.coordinates.count == 13, raw.reads.count == 15 else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        var expected = current.atoms
        if !stale {
            expected.replaceSubrange(0..<168, with: prepared.atoms.prefix(168))
            expected[168] = .init(kind: 1, present: 1, high: 0, low: current.value.revision &+ 1)
        }
        let m = raw.metadata, o = raw.outcome
        guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(raw.atoms, expected),
              o.abi == 1, o.operation == 601, o.invocation == scope.invocation,
              o.disposition == (stale ? 0 : 1), o.route == 0,
              m.abi == 1, m.operation == 601, m.scope == 2, m.read_count == 0,
              m.invocation == scope.invocation, m.revision == expected[168].low,
              m.peer_present == expected[3].present, m.peer == expected[3].low,
              m.bound == 0, m.route == 0, m.sample == 0, m.enabled == 0, m.lease == 0,
              m.queue_fault == UInt32(expected[41].low), m.rtt_fault == UInt32(expected[89].low),
              raw.reads.allSatisfy({ Self.bytes($0) == Self.bytes(Reply()) }) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let indices = [12,23,28,159,163,167,39,40,88]
        for i in 0..<13 {
            let e = raw.edits[i], c = raw.coordinates[i]
            if i >= 9 {
                guard Self.bytes(e) == Self.bytes(Edit()), Self.bytes(c) == Self.bytes(Coordinate()) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
                continue
            }
            let a = stale ? current.atoms[indices[i]] : prepared.atoms[indices[i]]
            let action: UInt32 = stale ? 1 : (a.present == 1 ? 3 : 2)
            guard e.action == action, e.source == (action == 3 ? 2 : 0),
                  e.index == (action == 3 ? UInt32(i) : 0), e.ordinal == 0, e.high == 0, e.low == 0,
                  c.present == a.present, c.reserved == 0, c.high == a.high, c.low == a.low else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        if stale { return .superseded }
        // Copy only the already validated native policy from the sealed501 draft;
        // relative coordinates never reconstruct native Instants or route identity.
        let value = BelugaNetworkAdaptationOwnerValue(policy: prepared.policy,
            revision: current.value.revision &+ 1, fastStatisticsAvailable: current.value.fastStatisticsAvailable,
            lane: current.value.lane, evidenceTime: current.value.evidenceTime,
            minimumCollectionSequence: current.value.minimumCollectionSequence, applied: current.value.applied)
        let replacement = try BelugaNetworkAdaptationOwnerSnapshot.capture(value, retainingAnchor: current.anchor)
        var expectedTimes = current.times
        expectedTimes.replaceSubrange(0..<9, with: prepared.policyTimes)
        guard !poisoned, BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(replacement.atoms, raw.atoms),
              replacement.times == expectedTimes, replacement.anchor == current.anchor,
              replacement.route == current.route else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return .ready(replacement)
    }

    static var inactiveLayoutIsExact: Bool {
        typealias R = InactiveRequest; typealias O = InactiveOutcome
        return prepareLayoutIsExact
            && layout(R.self, 32, 8, [MemoryLayout<R>.offset(of: \R.abi), MemoryLayout<R>.offset(of: \R.operation),
                MemoryLayout<R>.offset(of: \R.invocation), MemoryLayout<R>.offset(of: \R.current_generation),
                MemoryLayout<R>.offset(of: \R.exact_peer), MemoryLayout<R>.offset(of: \R.suspended)], [0,4,8,16,24,28])
            && layout(O.self, 24, 8, [MemoryLayout<O>.offset(of: \O.abi), MemoryLayout<O>.offset(of: \O.operation),
                MemoryLayout<O>.offset(of: \O.invocation), MemoryLayout<O>.offset(of: \O.disposition),
                MemoryLayout<O>.offset(of: \O.route)], [0,4,8,16,20])
    }

    static func actualInactive(_ request: InactiveRequest, _ current: BelugaNetworkAdaptationOwnerSnapshot,
        _ prepared: BelugaNetworkAdaptationTerminalPreparedValue,
        _ frame: BelugaNetworkAdaptationPrepareEmptyClock) throws -> InactiveRawResult {
        var q = request, ih = Header(abi: 1, domain: 2, phase: 1, count: 179)
        var ia = current.atoms.map { $0 }, ph = Header(abi: 1, domain: 4, phase: 3, count: 222)
        var pa = prepared.atoms.map { $0 }
        var h = Header(abi: 91, domain: 92, phase: 93, count: 94)
        var a = Array(repeating: BelugaNetworkAdaptationOwnerWriter.Atom(kind: 95, present: 96, high: -97, low: 98), count: 179)
        var m = Metadata(abi: 81, operation: 82, scope: 83, read_count: 84, invocation: 85,
            revision: 86, peer: 87, peer_present: 88, bound: 89, route: 90, sample: 91,
            enabled: 92, lease: 93, queue_fault: 94, rtt_fault: 95)
        var o = InactiveOutcome(abi: 41, operation: 42, invocation: 43, disposition: 44, route: 45)
        var e = Array(repeating: Edit(action: 71, source: 72, index: 73, ordinal: 74, high: -75, low: 76), count: 13)
        var c = Array(repeating: Coordinate(present: 61, reserved: 62, high: -63, low: 64), count: 13)
        var r = Array(repeating: Reply(abi: 51, status: 52, site: 53, ordinal: 54, invocation: 55, high: -56, low: 57, reserved: 58), count: 15)
        let beforeOutputs = [bytes(h), arrayBytes(a), bytes(m), bytes(o), arrayBytes(e), arrayBytes(c), arrayBytes(r)]
        let currentBefore = arrayBytes(current.atoms), preparedBefore = arrayBytes(prepared.atoms)
        var unchanged = false
        let status = withExtendedLifetime(frame) {
            withUnsafePointer(to: &q) { req in withUnsafePointer(to: &ih) { header in
                ia.withUnsafeMutableBufferPointer { input in withUnsafePointer(to: &ph) { preparedHeader in
                    pa.withUnsafeMutableBufferPointer { preparedInput in a.withUnsafeMutableBufferPointer { out in
                        e.withUnsafeMutableBufferPointer { edits in c.withUnsafeMutableBufferPointer { coords in
                            r.withUnsafeMutableBufferPointer { reads in
                                func inputs() -> [[UInt8]] {
                                    [Array(UnsafeRawBufferPointer(start: req, count: MemoryLayout<InactiveRequest>.stride)),
                                     Array(UnsafeRawBufferPointer(start: header, count: MemoryLayout<Header>.stride)),
                                     Array(UnsafeRawBufferPointer(start: input.baseAddress!, count: 179 * MemoryLayout<BelugaNetworkAdaptationOwnerWriter.Atom>.stride)),
                                     Array(UnsafeRawBufferPointer(start: preparedHeader, count: MemoryLayout<Header>.stride)),
                                     Array(UnsafeRawBufferPointer(start: preparedInput.baseAddress!, count: 222 * MemoryLayout<BelugaNetworkAdaptationOwnerWriter.Atom>.stride))]
                                }
                                let before = inputs()
                                let status = beluga_core_network_adaptation_owner_adopt_inactive(req, header, input.baseAddress!, 179,
                                    preparedHeader, preparedInput.baseAddress!, 222, { context, _, _, _, _ in
                                        guard let context else { return 0 }
                                        return Unmanaged<BelugaNetworkAdaptationPrepareEmptyClock>.fromOpaque(context).takeUnretainedValue().deny()
                                    }, Unmanaged.passUnretained(frame).toOpaque(), &h, out.baseAddress!, 179,
                                    &m, &o, edits.baseAddress!, 13, coords.baseAddress!, 13, reads.baseAddress!, 15)
                                unchanged = before == inputs(); return status
                            }
                        } }
                    } }
                } }
            } }
        }
        return .init(status: status, header: h, atoms: a, metadata: m, outcome: o,
            edits: e, coordinates: c, reads: r,
            inputsUnchanged: unchanged && currentBefore == arrayBytes(current.atoms) && preparedBefore == arrayBytes(prepared.atoms),
            deniedOutputsUntouched: beforeOutputs == [bytes(h), arrayBytes(a), bytes(m), bytes(o), arrayBytes(e), arrayBytes(c), arrayBytes(r)])
    }

    #if DEBUG
    // Same held601 import, copied values ONLY: not an actor receipt or store.
    func testInactiveTerminal(_ prepared: BelugaNetworkAdaptationTerminalPreparedValue,
        current: BelugaNetworkAdaptationOwnerSnapshot, generation: UInt64 = 77,
        exactPeer: Bool = true, suspended: Bool = false) throws -> InactiveProposal {
        let result = try withGuard { scope in
            .inactiveFixture(try inactiveTerminalHeld(current: current, prepared: prepared,
                generation: generation, exactPeer: exactPeer, suspended: suspended, scope: scope))
        }
        guard case let .inactiveFixture(result) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return result
    }
    #endif
}

/// A NEW one-use continuation, never the spent501 receipt. The native entry
/// retains real resources; a copied disposition cannot authorize await/FPS/store.
final class BelugaNetworkAdaptationBeginActiveReceipt {
    fileprivate let entry: BelugaNetworkAdaptationNativeBeginActiveEntry
    fileprivate let proposal: BelugaNetworkAdaptationOwnerBoundary.BeginActiveProposal
    fileprivate let use: BelugaNetworkAdaptationPreparedUse
    fileprivate init(entry: BelugaNetworkAdaptationNativeBeginActiveEntry,
        proposal: BelugaNetworkAdaptationOwnerBoundary.BeginActiveProposal,
        boundary: BelugaNetworkAdaptationOwnerBoundary, invocation: UInt64) {
        self.entry = entry; self.proposal = proposal
        use = .init(boundary: boundary, invocation: invocation)
    }
}

// Cross-file readable, but only this codec can construct the held commit packet.
// It never escapes the same guarded call that imported its replacement.
struct BelugaNetworkAdaptationActualBeginActiveCommit {
    let entry: BelugaNetworkAdaptationNativeBeginActiveEntry
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    fileprivate init(entry: BelugaNetworkAdaptationNativeBeginActiveEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary,
        replacement: BelugaNetworkAdaptationOwnerSnapshot) {
        self.entry = entry; self.boundary = boundary; self.replacement = replacement
    }
}

extension BelugaNetworkAdaptationOwnerBoundary {
    typealias BeginActiveRequest = beluga_core_adaptation_owner_begin_active_request_t
    typealias BeginActiveOutcome = beluga_core_adaptation_owner_begin_active_outcome_t
    struct BeginActiveRawResult {
        let status: UInt32
        var header: Header; var atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
        var preparedHeader: Header; var preparedAtoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
        var metadata: Metadata; var outcome: BeginActiveOutcome
        var edits: [Edit]; var coordinates: [Coordinate]; var reads: [Reply]
        let inputsUnchanged: Bool; let deniedOutputsUntouched: Bool
    }
    typealias BeginActiveProducer = (BeginActiveRequest, BelugaNetworkAdaptationOwnerSnapshot,
        BelugaNetworkAdaptationGeneralPreparedValue, BelugaNetworkAdaptationOwnerClockFrame) throws -> BeginActiveRawResult
    struct BeginActiveProposal {
        enum Disposition: UInt32 { case returned = 0, noNativeApply = 1, apply = 2 }
        let replacement: BelugaNetworkAdaptationOwnerSnapshot
        let prepared: BelugaNetworkAdaptationGeneralPreparedValue?
        let disposition: Disposition
        fileprivate init(replacement: BelugaNetworkAdaptationOwnerSnapshot,
            prepared: BelugaNetworkAdaptationGeneralPreparedValue?, disposition: Disposition) {
            self.replacement = replacement; self.prepared = prepared; self.disposition = disposition
        }
    }

    // Unwired prerequisite only. Publish the validated actual701 prefix inside
    // the issuer's guard, including Return's retained negative state. This cut
    // does not repeat501 admission or grant permission for a sender await.
    func beginActive(_ receipt: BelugaNetworkAdaptationGeneralPreparedReceipt,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationBeginActiveReceipt? {
        let result = try withPreparedGuard(receipt.use) { scope in
            guard let entry = owner.networkAdaptationBeginActiveEntry(receipt.entry, boundary: self) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            let current = try BelugaNetworkAdaptationOwnerSnapshot.capture(entry.value,
                retainingAnchor: receipt.value.source.anchor)
            let proposal = try beginActiveHeld(current: current, prepared: receipt.value,
                resourceFlags: entry.resourceFlags, scope: scope)
            let recaptured = try owner.networkAdaptationBeginActiveRecapture(entry, boundary: self,
                retainingAnchor: current.anchor)
            guard Self.samePublicationSource(current, recaptured) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            let successor: BelugaNetworkAdaptationBeginActiveReceipt? = proposal.disposition == .returned ? nil :
                .init(entry: entry, proposal: proposal, boundary: self, invocation: scope.invocation)
            let result = GuardedProposal.beginActive(successor)
            let packet = BelugaNetworkAdaptationActualBeginActiveCommit(entry: entry,
                boundary: self, replacement: proposal.replacement)
            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
            owner.networkAdaptationBeginActiveCommit(packet)
            return result
        }
        switch result {
        case let .beginActive(receipt): return receipt
        default: preconditionFailure("beginActive returned an impossible guarded result")
        }
    }

    private func beginActiveHeld(current: BelugaNetworkAdaptationOwnerSnapshot,
        prepared: BelugaNetworkAdaptationGeneralPreparedValue, resourceFlags: UInt32,
        scope: HeldScope) throws -> BeginActiveProposal {
        guard Self.beginActiveLayoutIsExact, resourceFlags & ~63 == 0,
              current.atoms.count == 179, prepared.atoms.count == 222,
              current.anchor == prepared.source.anchor else { throw BelugaNetworkAdaptationOwnerError.refused }
        let bind = prepared.policy.hasNativeAdaptationPolicyFault
            && current.value.policy.peerGeneration != prepared.tail.generation
        let samePeerFault = prepared.policy.hasNativeAdaptationPolicyFault
            && current.value.policy.peerGeneration != nil
            && current.value.policy.peerGeneration == prepared.policy.peerGeneration
        let startupWasActive = current.value.policy.startupSpatialModeIsActive
        let plan: [UInt32] = !prepared.policy.hasNativeAdaptationPolicyFault ? [] :
            (bind ? [2, 0, 1, 0, 1] : (samePeerFault && current.atoms[20].present == 1 ? [2] : []))
        if plan.contains(0), !current.value.policy.networkAdaptationOwnerRTTApplicationIsAdmitted {
            throw BelugaNetworkAdaptationOwnerError.malformedNativeImage
        }
        if plan.contains(2), Int64(bitPattern: current.atoms[38].low) < 0 {
            throw BelugaNetworkAdaptationOwnerError.malformedNativeImage
        }
        let frame = BelugaNetworkAdaptationOwnerClockFrame(invocation: scope.invocation,
            plan: plan, anchor: current.anchor, provider: clockProvider, poisoned: { self.poisoned })
        defer { frame.retire() }
        let request = BeginActiveRequest(abi: 1, operation: 701, invocation: scope.invocation,
            resource_flags: resourceFlags, reserved: 0)
        let raw = try beginActiveProducer(request, current, prepared, frame)
        frame.retire()
        guard raw.inputsUnchanged else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        if (2...5).contains(raw.status) {
            guard raw.deniedOutputsUntouched else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            throw BelugaNetworkAdaptationOwnerError.refused
        }
        guard raw.status == 1, !frame.denied, frame.receipts.count == plan.count,
              raw.header.abi == 1, raw.header.domain == 2, raw.header.phase == 2, raw.header.count == 179,
              raw.atoms.count == 179, raw.preparedAtoms.count == 222,
              raw.edits.count == 13, raw.coordinates.count == 13, raw.reads.count == 15 else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        for i in 0..<15 {
            guard Self.bytes(raw.reads[i]) == Self.bytes(i < frame.receipts.count ? frame.receipts[i].reply : Reply()) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        let o = raw.outcome, m = raw.metadata
        guard let disposition = BeginActiveProposal.Disposition(rawValue: o.disposition),
              o.abi == 1, o.operation == 701, o.invocation == scope.invocation, o.reserved == 0,
              o.route <= 1, o.prepared_present == (disposition == .returned ? 0 : 1),
              disposition != .apply || resourceFlags == 63,
              disposition != .returned || resourceFlags != 63,
              o.route == 0 || (bind && raw.atoms[144].low == 0),
              m.abi == 1, m.operation == 701, m.scope == 2, m.invocation == scope.invocation,
              m.read_count == UInt32(frame.receipts.count), m.route == o.route,
              m.bound == 0, m.sample == 0, m.enabled == 0, m.lease == 0,
              m.revision == raw.atoms[168].low,
              [current.value.revision, current.value.revision &+ 1, current.value.revision &+ 2].contains(m.revision),
              m.peer_present == raw.atoms[3].present, m.peer == raw.atoms[3].low,
              UInt64(m.queue_fault) == raw.atoms[41].low, UInt64(m.rtt_fault) == raw.atoms[89].low else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        // Rejection-only correlation with the original retained negative facts.
        // A valid-shaped draft cannot silently drop an observed fault. Binding
        // can additionally latch RTT failure at its two reset/application cuts.
        let effectivePeer = bind ? Optional(prepared.tail.generation) : current.value.policy.peerGeneration
        let retainsPreparedFault = effectivePeer != nil
            && effectivePeer == prepared.policy.peerGeneration
            && prepared.policy.hasNativeAdaptationPolicyFault
        let demandFault = current.atoms[140].low == 1
            || (retainsPreparedFault && prepared.atoms[140].low == 1)
        let rttFault = current.atoms[89].low == 1
            || (retainsPreparedFault && prepared.atoms[89].low == 1)
        guard raw.atoms[140].low == (demandFault ? 1 : 0),
              bind ? (!rttFault || raw.atoms[89].low == 1) : raw.atoms[89].low == (rttFault ? 1 : 0) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        if samePeerFault && !bind {
            guard raw.atoms[166].low == (startupWasActive ? 1 : current.atoms[166].low),
                  raw.edits[5].action == (startupWasActive ? 2 : 1) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        // Original write-family whitelist only, never calculate a successor.
        var fields: Set<Int> = disposition == .apply ? [155, 158, 159, 160, 161, 162] : []
        if samePeerFault {
            fields.formUnion(Self.promotionFields.union([5, 9, 89, 140, 166, 167]))
            if current.atoms[20].present == 1 { fields.formUnion(Self.revertFields) }
        }
        if bind {
            fields.formUnion(Set(3...89).union([140]).union(Set(143...150)).union(Set(152...167)))
        }
        // Denied subowner images stay opaque; only original fault latch may grow.
        if current.atoms[41].low == 1 { fields.subtract(Set(36...41)) }
        if current.atoms[89].low == 1 { fields.subtract(Set(42...88)) }
        for i in 0..<179 {
            let a = raw.atoms[i], before = current.atoms[i]
            guard a.kind == before.kind, a.present <= 1, a.kind == 10 || a.high == 0,
                  a.present != 0 || (a.high == 0 && a.low == 0) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            if i != 168 && !fields.contains(i) {
                guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms([a], [before]) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
            }
        }
        let mask: UInt16 = bind ? 0x01ff : 0x00ef
        var reachableClears: UInt16 = disposition == .apply ? 1 << 3 : 0
        if samePeerFault {
            reachableClears |= 1 << 2
            if startupWasActive { reachableClears |= 1 << 5 }
            if current.atoms[20].present == 1 { reachableClears |= 0x00cb }
        }
        if bind { reachableClears = 0x01ff }
        if current.atoms[41].low == 1 { reachableClears &= ~UInt16(0x00c0) }
        if current.atoms[89].low == 1 { reachableClears &= ~UInt16(0x0100) }
        let indices = [12, 23, 28, 159, 163, 167, 39, 40, 88]
        var times = current.times
        for i in 0..<13 {
            let e = raw.edits[i], c = raw.coordinates[i]
            if i >= 9 {
                guard Self.bytes(e) == Self.bytes(Edit()), Self.bytes(c) == Self.bytes(Coordinate()) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
                continue
            }
            guard (e.action == 1 || (e.action == 2 && mask & reachableClears & (1 << i) != 0)),
                  e.source == 0, e.index == 0, e.ordinal == 0, e.high == 0, e.low == 0 else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            let a = current.atoms[indices[i]]
            let expected = e.action == 1 ? Coordinate(present: a.present, reserved: 0, high: a.high, low: a.low) : Coordinate()
            guard Self.bytes(c) == Self.bytes(expected) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            if e.action == 2 { times[i] = nil }
        }
        let route = o.route == 0 ? current.route : nil
        var policy = current.value.policy
        // RTT's existing typed importer is grouped at42. Importing the new
        // fault latch89 still requires42...88 to remain exact when not bound.
        var importFields = fields
        if fields.contains(89), current.atoms[89].low == 0 { importFields.insert(42) }
        try policy.networkAdaptationOwnerImportClocked(.init(atoms: raw.atoms, fields: importFields, times: times, route: route))
        let value = BelugaNetworkAdaptationOwnerValue(policy: policy, revision: m.revision,
            fastStatisticsAvailable: current.value.fastStatisticsAvailable, lane: current.value.lane,
            evidenceTime: current.value.evidenceTime, minimumCollectionSequence: current.value.minimumCollectionSequence,
            applied: current.value.applied)
        let native = try BelugaNetworkAdaptationOwnerSnapshot.capture(value, retainingAnchor: current.anchor)
        guard !poisoned, BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(native.atoms, raw.atoms),
              native.times == times, native.route == route, native.anchor == current.anchor else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let returned: BelugaNetworkAdaptationGeneralPreparedValue?
        if disposition == .returned {
            guard Self.bytes(raw.preparedHeader) == Self.bytes(Header()),
                  raw.preparedAtoms.allSatisfy({ Self.bytes($0) == Self.bytes(BelugaNetworkAdaptationOwnerWriter.Atom()) }) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            returned = nil
        } else {
            guard raw.preparedHeader.abi == 1, raw.preparedHeader.domain == 4,
                  raw.preparedHeader.phase == 3, raw.preparedHeader.count == 222 else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            for i in 0..<222 where i != 170 {
                guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms([raw.preparedAtoms[i]], [prepared.atoms[i]]) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
            }
            let tail = try BelugaNetworkAdaptationPreparedTail(atoms: raw.preparedAtoms)
            guard tail.applyingRevision == (m.revision == current.value.revision ? prepared.tail.applyingRevision : m.revision) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            returned = .init(source: prepared.source, policy: prepared.policy, tail: tail,
                times: prepared.policyTimes, report: prepared.report, observed: prepared.observedAt,
                clockInstants: prepared.clockInstants, atoms: raw.preparedAtoms)
        }
        return .init(replacement: native, prepared: returned, disposition: disposition)
    }

    static var beginActiveLayoutIsExact: Bool {
        typealias R = BeginActiveRequest; typealias O = BeginActiveOutcome
        return layoutIsExact && layout(R.self, 24, 8,
            [MemoryLayout<R>.offset(of: \R.abi), MemoryLayout<R>.offset(of: \R.operation),
                MemoryLayout<R>.offset(of: \R.invocation), MemoryLayout<R>.offset(of: \R.resource_flags),
                MemoryLayout<R>.offset(of: \R.reserved)], [0,4,8,16,20])
            && layout(O.self, 32, 8,
                [MemoryLayout<O>.offset(of: \O.abi), MemoryLayout<O>.offset(of: \O.operation),
                 MemoryLayout<O>.offset(of: \O.invocation), MemoryLayout<O>.offset(of: \O.disposition),
                 MemoryLayout<O>.offset(of: \O.route), MemoryLayout<O>.offset(of: \O.prepared_present),
                 MemoryLayout<O>.offset(of: \O.reserved)], [0,4,8,16,20,24,28])
    }

    static func actualBeginActive(_ request: BeginActiveRequest, _ current: BelugaNetworkAdaptationOwnerSnapshot,
        _ prepared: BelugaNetworkAdaptationGeneralPreparedValue,
        _ frame: BelugaNetworkAdaptationOwnerClockFrame) throws -> BeginActiveRawResult {
        var q = request, ih = Header(abi: 1, domain: 2, phase: 1, count: 179)
        var ia = current.atoms.map { $0 }, ph = Header(abi: 1, domain: 4, phase: 3, count: 222)
        var pa = prepared.atoms.map { $0 }
        var h = Header(abi: 91, domain: 92, phase: 93, count: 94)
        var a = Array(repeating: BelugaNetworkAdaptationOwnerWriter.Atom(kind: 95, present: 96, high: -97, low: 98), count: 179)
        var rh = Header(abi: 31, domain: 32, phase: 33, count: 34)
        var ra = Array(repeating: BelugaNetworkAdaptationOwnerWriter.Atom(kind: 35, present: 36, high: -37, low: 38), count: 222)
        var m = Metadata(abi: 81, operation: 82, scope: 83, read_count: 84, invocation: 85,
            revision: 86, peer: 87, peer_present: 88, bound: 89, route: 90, sample: 91,
            enabled: 92, lease: 93, queue_fault: 94, rtt_fault: 95)
        var o = BeginActiveOutcome(abi: 41, operation: 42, invocation: 43, disposition: 44, route: 45, prepared_present: 46, reserved: 47)
        var e = Array(repeating: Edit(action: 71, source: 72, index: 73, ordinal: 74, high: -75, low: 76), count: 13)
        var c = Array(repeating: Coordinate(present: 61, reserved: 62, high: -63, low: 64), count: 13)
        var r = Array(repeating: Reply(abi: 51, status: 52, site: 53, ordinal: 54, invocation: 55, high: -56, low: 57, reserved: 58), count: 15)
        let beforeOutputs = [bytes(h), arrayBytes(a), bytes(rh), arrayBytes(ra), bytes(m), bytes(o), arrayBytes(e), arrayBytes(c), arrayBytes(r)]
        let currentBefore = arrayBytes(current.atoms), preparedBefore = arrayBytes(prepared.atoms)
        var unchanged = false
        let status = withExtendedLifetime(frame) {
            withUnsafePointer(to: &q) { req in withUnsafePointer(to: &ih) { header in
                ia.withUnsafeMutableBufferPointer { input in withUnsafePointer(to: &ph) { preparedHeader in
                    pa.withUnsafeMutableBufferPointer { preparedInput in a.withUnsafeMutableBufferPointer { out in
                        ra.withUnsafeMutableBufferPointer { returned in e.withUnsafeMutableBufferPointer { edits in
                            c.withUnsafeMutableBufferPointer { coords in r.withUnsafeMutableBufferPointer { reads in
                                func inputs() -> [[UInt8]] {
                                    [Array(UnsafeRawBufferPointer(start: req, count: MemoryLayout<BeginActiveRequest>.stride)),
                                     Array(UnsafeRawBufferPointer(start: header, count: MemoryLayout<Header>.stride)),
                                     Array(UnsafeRawBufferPointer(start: input.baseAddress!, count: 179 * MemoryLayout<BelugaNetworkAdaptationOwnerWriter.Atom>.stride)),
                                     Array(UnsafeRawBufferPointer(start: preparedHeader, count: MemoryLayout<Header>.stride)),
                                     Array(UnsafeRawBufferPointer(start: preparedInput.baseAddress!, count: 222 * MemoryLayout<BelugaNetworkAdaptationOwnerWriter.Atom>.stride))]
                                }
                                let before = inputs()
                                let status = beluga_core_network_adaptation_owner_begin_active(req, header, input.baseAddress!, 179,
                                    preparedHeader, preparedInput.baseAddress!, 222,
                                    { context, invocation, site, ordinal, reply in
                                        BelugaNetworkAdaptationOwnerBoundary.clockCallback(context, invocation, site, ordinal, reply)
                                    },
                                    Unmanaged.passUnretained(frame).toOpaque(), &h, out.baseAddress!, 179,
                                    &rh, returned.baseAddress!, 222, &m, &o,
                                    edits.baseAddress!, 13, coords.baseAddress!, 13, reads.baseAddress!, 15)
                                unchanged = before == inputs(); return status
                            } }
                        } }
                    } }
                } }
            } }
        }
        return .init(status: status, header: h, atoms: a, preparedHeader: rh, preparedAtoms: ra,
            metadata: m, outcome: o, edits: e, coordinates: c, reads: r,
            inputsUnchanged: unchanged && currentBefore == arrayBytes(current.atoms) && preparedBefore == arrayBytes(prepared.atoms),
            deniedOutputsUntouched: beforeOutputs == [bytes(h), arrayBytes(a), bytes(rh), arrayBytes(ra), bytes(m), bytes(o), arrayBytes(e), arrayBytes(c), arrayBytes(r)])
    }

    #if DEBUG
    // Same held importer, copied draft only. Never a genuine native receipt.
    func testBeginActive(_ prepared: BelugaNetworkAdaptationGeneralPreparedValue,
        current: BelugaNetworkAdaptationOwnerSnapshot, resourceFlags: UInt32 = 63) throws -> BeginActiveProposal {
        let result = try withGuard { scope in
            .beginActiveFixture(try beginActiveHeld(current: current, prepared: prepared, resourceFlags: resourceFlags, scope: scope))
        }
        guard case let .beginActiveFixture(proposal) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return proposal
    }
    #endif
}

/// Constructor-sealed bridge from the spent actual701 continuation to the
/// actor's attempt factory. Its snapshots and invocations describe custody;
/// none is independently a permission to await, adapt FPS, or publish an Owner.
struct BelugaNetworkAdaptationNativeAttemptSeed {
    enum Intent { case finalAdoptionOnly, senderApply }
    let entry: BelugaNetworkAdaptationNativeBeginActiveEntry
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let beginActiveInvocation: UInt64
    let consumerInvocation: UInt64
    let published: BelugaNetworkAdaptationOwnerSnapshot
    let prepared: BelugaNetworkAdaptationGeneralPreparedValue
    let intent: Intent
    fileprivate init(entry: BelugaNetworkAdaptationNativeBeginActiveEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary, beginActiveInvocation: UInt64,
        consumerInvocation: UInt64, published: BelugaNetworkAdaptationOwnerSnapshot,
        prepared: BelugaNetworkAdaptationGeneralPreparedValue, intent: Intent) {
        self.entry = entry; self.boundary = boundary
        self.beginActiveInvocation = beginActiveInvocation
        self.consumerInvocation = consumerInvocation
        self.published = published; self.prepared = prepared; self.intent = intent
    }
}

extension BelugaNetworkAdaptationOwnerBoundary {
    /// Unwired prerequisite: burn the NEW actual701 continuation before any
    /// wrong-origin, busy/exhaustion, malformed disposition, or custody refusal.
    /// No second501 vote, clock, producer, publication, native effect, or await.
    func consumeBeginActive(_ receipt: BelugaNetworkAdaptationBeginActiveReceipt,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationNativeAttempt {
        let result = try withPreparedGuard(receipt.use) { scope in
            let intent: BelugaNetworkAdaptationNativeAttemptSeed.Intent
            switch receipt.proposal.disposition {
            case .returned:
                // Actual701 never creates a successor for Return. Refuse a
                // malformed/fault-injected one, rather than deriving permission.
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            case .noNativeApply: intent = .finalAdoptionOnly
            case .apply: intent = .senderApply
            }
            guard let prepared = receipt.proposal.prepared else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            let current = try owner.networkAdaptationBeginActiveRecapture(receipt.entry,
                boundary: self, retainingAnchor: receipt.proposal.replacement.anchor)
            guard Self.samePublicationSource(current, receipt.proposal.replacement) else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            let seed = BelugaNetworkAdaptationNativeAttemptSeed(entry: receipt.entry,
                boundary: self, beginActiveInvocation: receipt.use.invocation,
                consumerInvocation: scope.invocation, published: receipt.proposal.replacement,
                prepared: prepared, intent: intent)
            return .nativeAttempt(try owner.networkAdaptationNativeAttempt(seed))
        }
        guard case let .nativeAttempt(attempt) = result else {
            preconditionFailure("consumeBeginActive returned an impossible guarded result")
        }
        return attempt
    }
}

struct BelugaNetworkAdaptationOwnerPublicationReceipt {
    let operation: UInt32
    let invocation: UInt64
    let collectorEnabled: Bool
    fileprivate init(operation: UInt32, invocation: UInt64, collectorEnabled: Bool) {
        self.operation = operation; self.invocation = invocation
        self.collectorEnabled = collectorEnabled
    }
}

enum BelugaNetworkAdaptationOwnerPublicationDisposition {
    case accepted(BelugaNetworkAdaptationOwnerPublicationReceipt)
    case refused, superseded
}

fileprivate enum OwnerPublicationEvent {
    case zeroClock(BelugaNetworkAdaptationOwnerEvent)
    case clocked(BelugaNetworkAdaptationOwnerClockedEvent)
    var operation: UInt32 {
        switch self { case let .zeroClock(e): e.operation; case let .clocked(e): e.operation }
    }
    var key: [UInt64] {
        switch self {
        case let .zeroClock(e):
            let r = e.request(invocation: 0)
            return [UInt64(r.operation), r.generation, r.show,
                UInt64(r.capture_source_present), UInt64(r.resume_context_absent)]
        case let .clocked(e):
            let r = e.request(0)
            if case let .visibility(show, generation, epoch) = e {
                return [UInt64(r.operation), generation, epoch, 0, show ? 1 : 0, 0]
            }
            return [UInt64(r.operation), r.generation, r.show, r.minimum,
                UInt64(r.flag), UInt64(r.minimum_present)]
        }
    }
}

fileprivate struct OwnerPublicationWitness {
    let slot: ObjectIdentifier
    let key: [UInt64]
    let generation: UInt64
}

// Closed constructor origin: only the held producer/import path creates this
// packet. Neither a caller proposal nor a callback can supply a replacement.
fileprivate struct OwnerPublicationCommit {
    let witness: OwnerPublicationWitness
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    let receipt: BelugaNetworkAdaptationOwnerPublicationReceipt
}

/// The codec alone constructs this packet after Rust validation, witness checks
/// and full native recapture. It never leaves the synchronous publication call.
/// The service has no setter accepting a caller-owned value or snapshot.
struct BelugaNetworkAdaptationActualStopCommit {
    let entry: BelugaNetworkAdaptationActualStopEntry
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let invocation: UInt64
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    fileprivate init(entry: BelugaNetworkAdaptationActualStopEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary, invocation: UInt64,
        replacement: BelugaNetworkAdaptationOwnerSnapshot) {
        self.entry = entry; self.boundary = boundary; self.invocation = invocation
        self.replacement = replacement
    }
}

// No caller can construct a replacement or carry this packet beyond the held
// publication. Its receiver is the mandatory isolated original actor.
struct BelugaNetworkAdaptationActualEpochCommit {
    let entry: BelugaNetworkAdaptationActualEpochEntry
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    fileprivate init(entry: BelugaNetworkAdaptationActualEpochEntry,
        replacement: BelugaNetworkAdaptationOwnerSnapshot) {
        self.entry = entry; self.replacement = replacement
    }
}

struct BelugaNetworkAdaptationActualResetCommit {
    let entry: BelugaNetworkAdaptationActualResetEntry
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    fileprivate init(entry: BelugaNetworkAdaptationActualResetEntry,
        replacement: BelugaNetworkAdaptationOwnerSnapshot) {
        self.entry = entry; self.replacement = replacement
    }
}

struct BelugaNetworkAdaptationCommittedResumeCommit {
    let entry: BelugaNetworkAdaptationCommittedResumeEntry
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let invocation: UInt64
    let replacement: BelugaNetworkAdaptationOwnerSnapshot

    fileprivate init(entry: BelugaNetworkAdaptationCommittedResumeEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary, invocation: UInt64,
        replacement: BelugaNetworkAdaptationOwnerSnapshot) {
        self.entry = entry
        self.boundary = boundary
        self.invocation = invocation
        self.replacement = replacement
    }
}

// Codec-private, closed pre-store admission/read vocabulary. There is no commit
// request or caller-supplied publisher. DEBUG callers author the nonescaping
// switch lexically; actual actor access never derives from an optional binding.
fileprivate enum OwnerPublicationReadRequest {
    case admit(key: [UInt64])
    case capture(retainingAnchor: ContinuousClock.Instant?, initial: Bool)
    case check(OwnerPublicationWitness, final: Bool)
    case matches(OwnerPublicationWitness)
    case precommit
}
fileprivate enum OwnerPublicationReadReply {
    case admission(OwnerPublicationWitness?)
    case snapshot(BelugaNetworkAdaptationOwnerSnapshot)
    case boolean(Bool)
    case precommitDone
}
// This packet can return only to the same codec-authored withGuard closure. The
// informational GuardedProposal result cannot carry it outside the held call.
fileprivate enum OwnerPublicationPrepared {
    case refused
    case superseded
    case ready(OwnerPublicationCommit)
}

extension BelugaNetworkAdaptationOwnerBoundary {
    private static func samePublicationSource(_ a: BelugaNetworkAdaptationOwnerSnapshot,
        _ b: BelugaNetworkAdaptationOwnerSnapshot) -> Bool {
        BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(a.atoms, b.atoms)
            && a.times == b.times && a.anchor == b.anchor && a.route == b.route
    }

    // SAME held scope as zero/clocked/terminal501. All witness reads and fixture
    // callbacks occur after guard admission and before the sole assignment.
    private func preparePublicationHeld(event: OwnerPublicationEvent, scope: HeldScope,
        read: (OwnerPublicationReadRequest) throws -> OwnerPublicationReadReply) throws -> OwnerPublicationPrepared {
        guard case let .admission(witness) = try read(.admit(key: event.key)) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard let witness else { return .refused }
        return try prepareAlreadyAdmittedPublicationHeld(event: event, witness: witness,
            scope: scope, read: read)
    }

    // Old callers retain the original single-admission prefix. Actual216 seals
    // its native payload inside the same guard before entering this remainder.
    private func prepareAlreadyAdmittedPublicationHeld(event: OwnerPublicationEvent,
        witness: OwnerPublicationWitness, scope: HeldScope,
        read: (OwnerPublicationReadRequest) throws -> OwnerPublicationReadReply) throws -> OwnerPublicationPrepared {
        guard case let .snapshot(original) = try read(.capture(retainingAnchor: nil, initial: true)) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard case let .boolean(originalMatches) = try read(.matches(witness)) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard originalMatches else { return .superseded }
        let source: BelugaNetworkAdaptationOwnerSnapshot
        let replacement: BelugaNetworkAdaptationOwnerSnapshot
        let enabled: Bool
        switch event {
        case let .zeroClock(e):
            let p = try proposeHeld(original.value, event: e, scope: scope)
            source = p.source; replacement = p.replacement; enabled = p.collectorEnabled
        case let .clocked(e):
            let p = try proposeClockedHeld(original.value, event: e, scope: scope)
            source = p.source; replacement = p.replacement; enabled = false
        }
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard Self.samePublicationSource(original, source) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        guard case let .boolean(afterImport) = try read(.check(witness, final: false)) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard afterImport else { return .superseded }
        guard case .precommitDone = try read(.precommit) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard case let .boolean(finalWitness) = try read(.check(witness, final: true)) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard finalWitness else { return .superseded }
        guard case let .snapshot(current) = try read(.capture(retainingAnchor: source.anchor, initial: false)) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard case let .boolean(currentMatches) = try read(.matches(witness)) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        guard currentMatches, Self.samePublicationSource(current, source) else { return .superseded }
        let receipt = BelugaNetworkAdaptationOwnerPublicationReceipt(operation: event.operation,
            invocation: scope.invocation, collectorEnabled: enabled)
        let commit = OwnerPublicationCommit(witness: witness, replacement: replacement, receipt: receipt)
        // The private ready packet stays inside this same withGuard closure;
        // its fixed store follows one final poison check, with no provider call.
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        return .ready(commit)
    }

    func publishCommittedResume(_ entry: BelugaNetworkAdaptationCommittedResumeEntry,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationOwnerPublicationDisposition {
        // Includes refusal before the held body (notably invocation exhaustion).
        defer { owner.networkAdaptationCommittedResumeRetire(entry) }
        let result = try withGuard { scope in
            let prepared = try preparePublicationHeld(event: .zeroClock(.resumeAndAdvance), scope: scope) { request in
                switch request {
                case let .admit(key):
                    guard owner.networkAdaptationCommittedResumeAdmit(entry, boundary: self, key: key) else {
                        return .admission(nil)
                    }
                    return .admission(.init(slot: ObjectIdentifier(entry), key: key, generation: entry.generation))
                case let .capture(anchor, _):
                    return .snapshot(try owner.networkAdaptationCommittedResumeCapture(entry, retainingAnchor: anchor))
                case let .check(witness, _), let .matches(witness):
                    return .boolean(owner.networkAdaptationCommittedResumeMatches(entry, slot: witness.slot,
                        key: witness.key, generation: witness.generation))
                case .precommit:
                    guard owner.networkAdaptationCommittedResumeIsCurrent(entry) else {
                        throw BelugaNetworkAdaptationOwnerError.invalidResult
                    }
                    return .precommitDone
                }
            }
            switch prepared {
            case .refused: return .publication(.refused)
            case .superseded: return .publication(.superseded)
            case let .ready(packet):
                guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
                owner.networkAdaptationCommittedResumeCommit(.init(entry: entry,
                    boundary: entry.boundary, invocation: packet.receipt.invocation,
                    replacement: packet.replacement))
                return .publication(.accepted(packet.receipt))
            }
        }
        guard case let .publication(result) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return result
    }

    func publishActualStop(_ entry: BelugaNetworkAdaptationActualStopEntry,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationOwnerPublicationDisposition {
        let result = try withGuard { scope in
            #if DEBUG
            isPublishingActualStop = entry.permitsInertNegativeControls
            defer { isPublishingActualStop = false }
            #endif
            let event: OwnerPublicationEvent
            switch entry.cut {
            case .endShow: event = .clocked(.endShowWithoutRevision)
            case .stopSampling: event = .zeroClock(.stopSampling)
            }
            let prepared = try preparePublicationHeld(event: event, scope: scope) { request in
                switch request {
                case let .admit(key):
                    guard owner.networkAdaptationActualStopAdmit(entry, boundary: self, key: key) else {
                        return .admission(nil)
                    }
                    return .admission(.init(slot: ObjectIdentifier(entry), key: key, generation: entry.generation))
                case let .capture(anchor, _):
                    return .snapshot(try owner.networkAdaptationActualStopCapture(entry, retainingAnchor: anchor))
                case let .check(witness, _), let .matches(witness):
                    return .boolean(owner.networkAdaptationActualStopMatches(entry, slot: witness.slot,
                        key: witness.key, generation: witness.generation))
                case .precommit:
                    guard owner.networkAdaptationActualStopIsCurrent(entry) else {
                        throw BelugaNetworkAdaptationOwnerError.invalidResult
                    }
                    return .precommitDone
                }
            }
            switch prepared {
            case .refused: return .publication(.refused)
            case .superseded: return .publication(.superseded)
            case let .ready(packet):
                guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
                // Direct mandatory isolated receiver; no optional actor, Task,
                // callback, throwing work or recapture follows the fixed store.
                owner.networkAdaptationActualStopCommit(.init(entry: entry,
                    boundary: entry.boundary, invocation: packet.receipt.invocation,
                    replacement: packet.replacement))
                return .publication(.accepted(packet.receipt))
            }
        }
        guard case let .publication(result) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return result
    }

    func publishActualEpoch(_ entry: BelugaNetworkAdaptationActualEpochEntry,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationOwnerPublicationDisposition {
        // Installed before guard entry: busy/exhausted frames must retire too.
        defer { owner.networkAdaptationActualEpochRetire(entry) }
        let result = try withGuard { scope in
            guard owner.networkAdaptationActualEpochAdmit(entry, boundary: self) else {
                return .publication(.refused)
            }
            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
            // The actual optional peer getter is resolved once AFTER admission.
            // A throwing refusal is never conflated with the valid nil payload.
            let minimum = try owner.networkAdaptationActualEpochSealMinimum(entry)
            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
            let event = OwnerPublicationEvent.clocked(.beginPostResumeEpoch(minimum: minimum))
            let witness = OwnerPublicationWitness(slot: ObjectIdentifier(entry), key: event.key,
                generation: entry.generation)
            #if DEBUG
            isPublishingActualEpoch = entry.permitsInertNegativeControls
            defer { isPublishingActualEpoch = false }
            #endif
            let prepared = try prepareAlreadyAdmittedPublicationHeld(event: event,
                witness: witness, scope: scope) { request in
                switch request {
                case .admit: throw BelugaNetworkAdaptationOwnerError.invalidResult
                case let .capture(anchor, _):
                    return .snapshot(try owner.networkAdaptationActualEpochCapture(entry, retainingAnchor: anchor))
                case let .check(witness, _), let .matches(witness):
                    return .boolean(owner.networkAdaptationActualEpochMatches(entry, slot: witness.slot,
                        key: witness.key, generation: witness.generation))
                case .precommit:
                    guard owner.networkAdaptationActualEpochIsCurrent(entry) else {
                        throw BelugaNetworkAdaptationOwnerError.invalidResult
                    }
                    return .precommitDone
                }
            }
            switch prepared {
            case .refused: return .publication(.refused)
            case .superseded: return .publication(.superseded)
            case let .ready(packet):
                guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
                owner.networkAdaptationActualEpochCommit(.init(entry: entry, replacement: packet.replacement))
                return .publication(.accepted(packet.receipt))
            }
        }
        guard case let .publication(result) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return result
    }

    #if DEBUG
    func testSwallowedActualEpochOuterReentry(_ entry: BelugaNetworkAdaptationActualEpochEntry,
        on owner: isolated WorldwideScreenService) throws {
        _ = try withGuard { _ in
            do { _ = try publishActualEpoch(entry, on: owner) }
            catch BelugaNetworkAdaptationOwnerError.reentry { }
            return .retired
        }
    }
    #endif

    func publishActualReset(_ entry: BelugaNetworkAdaptationActualResetEntry,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationOwnerPublicationDisposition {
        defer { owner.networkAdaptationActualResetRetire(entry) }
        let result = try withGuard { scope in
            #if DEBUG
            isPublishingActualReset = entry.permitsInertNegativeControls
            defer { isPublishingActualReset = false }
            #endif
            let event: OwnerPublicationEvent = entry.operation == 218
                ? .clocked(.resumeFailedAndAdvance) : .zeroClock(.resumeWithoutRevision)
            let prepared = try preparePublicationHeld(event: event, scope: scope) { request in
                switch request {
                case let .admit(key):
                    guard owner.networkAdaptationActualResetAdmit(entry, boundary: self, key: key) else {
                        return .admission(nil)
                    }
                    return .admission(.init(slot: ObjectIdentifier(entry), key: key, generation: entry.generation))
                case let .capture(anchor, _):
                    return .snapshot(try owner.networkAdaptationActualResetCapture(entry, retainingAnchor: anchor))
                case let .check(witness, _), let .matches(witness):
                    return .boolean(owner.networkAdaptationActualResetMatches(entry, slot: witness.slot,
                        key: witness.key, generation: witness.generation))
                case .precommit:
                    guard owner.networkAdaptationActualResetIsCurrent(entry) else {
                        throw BelugaNetworkAdaptationOwnerError.invalidResult
                    }
                    return .precommitDone
                }
            }
            switch prepared {
            case .refused: return .publication(.refused)
            case .superseded: return .publication(.superseded)
            case let .ready(packet):
                guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
                owner.networkAdaptationActualResetCommit(.init(entry: entry, replacement: packet.replacement))
                return .publication(.accepted(packet.receipt))
            }
        }
        guard case let .publication(result) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return result
    }

    #if DEBUG
    func testSwallowedActualResetOuterReentry(_ entry: BelugaNetworkAdaptationActualResetEntry,
        on owner: isolated WorldwideScreenService) throws {
        _ = try withGuard { _ in
            do { _ = try publishActualReset(entry, on: owner) }
            catch BelugaNetworkAdaptationOwnerError.reentry { }
            return .retired
        }
    }
    #endif

    #if DEBUG
    private func publishFixtureHeld(_ fixture: BelugaNetworkAdaptationOwnerPublicationFixture,
        event: OwnerPublicationEvent, scope: HeldScope) throws -> BelugaNetworkAdaptationOwnerPublicationDisposition {
        let prepared = try preparePublicationHeld(event: event, scope: scope) { request in
            switch request {
            case let .admit(key): return .admission(try fixture.admit(on: self, key: key))
            case let .capture(anchor, initial):
                return .snapshot(try fixture.capture(retainingAnchor: anchor, initial: initial))
            case let .check(witness, final): return .boolean(try fixture.check(witness, final: final))
            case let .matches(witness): return .boolean(fixture.matches(witness))
            case .precommit: try fixture.precommit(); return .precommitDone
            }
        }
        switch prepared {
        case .refused: return .refused
        case .superseded: return .superseded
        case let .ready(packet):
            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
            fixture.commit(packet)
            return .accepted(packet.receipt)
        }
    }

    func testPublish(_ fixture: BelugaNetworkAdaptationOwnerPublicationFixture,
        event: BelugaNetworkAdaptationOwnerEvent) throws -> BelugaNetworkAdaptationOwnerPublicationDisposition {
        let result = try withGuard { scope in
            .publication(try publishFixtureHeld(fixture, event: .zeroClock(event), scope: scope))
        }
        guard case let .publication(result) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return result
    }
    func testPublishClocked(_ fixture: BelugaNetworkAdaptationOwnerPublicationFixture,
        event: BelugaNetworkAdaptationOwnerClockedEvent) throws -> BelugaNetworkAdaptationOwnerPublicationDisposition {
        let result = try withGuard { scope in
            .publication(try publishFixtureHeld(fixture, event: .clocked(event), scope: scope))
        }
        guard case let .publication(result) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return result
    }
    // Nonoptional actor entry tests the same synchronous fixture path. Its pure
    // pre-store seam never borrows a substitute actor or grants native custody.
    func testPublishIsolated(_ fixture: BelugaNetworkAdaptationOwnerPublicationFixture,
        event: BelugaNetworkAdaptationOwnerEvent, on owner: isolated WorldwideScreenService)
        throws -> BelugaNetworkAdaptationOwnerPublicationDisposition {
        let result = try withGuard { scope in
            .publication(try publishFixtureHeld(fixture, event: .zeroClock(event), scope: scope))
        }
        guard case let .publication(result) = result else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return result
    }
    #endif
}

#if DEBUG
// One simulated slot, NEVER an actual actor/native witness or a second live Owner.
// No raw179 replacement/setter is exposed. The fixed mutation below is deliberately
// fixture-only foreign-writer evidence, not a successful policy implementation.
final class BelugaNetworkAdaptationOwnerPublicationFixture {
    enum Stage: String, CaseIterable { case admission, sourceRead, afterImport, precommit, finalWitness, recapture }
    private let boundary: BelugaNetworkAdaptationOwnerBoundary
    private let key: [UInt64]
    private var value: BelugaNetworkAdaptationOwnerValue
    private var generation: UInt64
    private var eligible: Bool
    private(set) var publications = 0
    private(set) var trace: [Stage] = []
    var testHook: ((Stage) throws -> Void)?
    init(boundary: BelugaNetworkAdaptationOwnerBoundary, value: BelugaNetworkAdaptationOwnerValue,
        event: BelugaNetworkAdaptationOwnerEvent, eligible: Bool = true, generation: UInt64 = 1) {
        self.boundary = boundary; self.value = value; key = OwnerPublicationEvent.zeroClock(event).key
        self.eligible = eligible; self.generation = generation
    }
    init(boundary: BelugaNetworkAdaptationOwnerBoundary, value: BelugaNetworkAdaptationOwnerValue,
        clockedEvent: BelugaNetworkAdaptationOwnerClockedEvent, eligible: Bool = true, generation: UInt64 = 1) {
        self.boundary = boundary; self.value = value; key = OwnerPublicationEvent.clocked(clockedEvent).key
        self.eligible = eligible; self.generation = generation
    }
    var acceptedValue: BelugaNetworkAdaptationOwnerValue { value }
    private func hook(_ stage: Stage) throws { trace.append(stage); try testHook?(stage) }
    fileprivate func admit(on boundary: BelugaNetworkAdaptationOwnerBoundary,
        key: [UInt64]) throws -> OwnerPublicationWitness? {
        // Wrong Boundary/cut is denied before witness callback, read, clock or raw.
        guard self.boundary === boundary, self.key == key else { return nil }
        try hook(.admission)
        guard eligible, generation != UInt64.max else { return nil }
        return .init(slot: ObjectIdentifier(self), key: key, generation: generation)
    }
    fileprivate func capture(retainingAnchor: ContinuousClock.Instant?, initial: Bool) throws -> BelugaNetworkAdaptationOwnerSnapshot {
        try hook(initial ? .sourceRead : .recapture)
        return try .capture(value, retainingAnchor: retainingAnchor)
    }
    fileprivate func matches(_ witness: OwnerPublicationWitness) -> Bool {
        witness.slot == ObjectIdentifier(self) && witness.key == key
            && witness.generation == generation && eligible
    }
    fileprivate func check(_ witness: OwnerPublicationWitness, final: Bool) throws -> Bool {
        try hook(final ? .finalWitness : .afterImport); return matches(witness)
    }
    fileprivate func precommit() throws { try hook(.precommit) }
    fileprivate func commit(_ packet: OwnerPublicationCommit) {
        value = packet.replacement.value
        generation += 1 // admission proved nonmax; no wrapping witness reuse
        publications += 1
    }
    // Monotonic simulated witness invalidation catches even bit-identical ABA.
    func testInvalidateWitness() { if generation == UInt64.max { eligible = false } else { generation += 1 } }
    // Distinguishes complete179 fencing from revision-only fencing while leaving
    // the simulated witness current. Represents an unmigrated external writer.
    func testChangeFastFlagWithoutRevision() {
        value = .init(policy: value.policy, revision: value.revision,
            fastStatisticsAvailable: !value.fastStatisticsAvailable, lane: value.lane,
            evidenceTime: value.evidenceTime, minimumCollectionSequence: value.minimumCollectionSequence, applied: value.applied)
    }
}
#endif

// Actual successful SDK settlement only. Wrong-kind/replay admission throws
// before any effect. Once token custody is admitted, EVERY denial retains a
// sealed cleanup receipt; selected refusal never falls back to Swift policy.
enum BelugaNetworkAdaptationSuccessResult {
    case accepted(BelugaNetworkAdaptationFinalAdoptionReceipt)
    case rollback(BelugaNetworkAdaptationSuccessCleanupReceipt)
    case refused(BelugaNetworkAdaptationSuccessCleanupReceipt, any Error)
    case requiresGuardedRecovery(BelugaNetworkAdaptationSuccessCleanupReceipt)
}

final class BelugaNetworkAdaptationFinalAdoptionReceipt {
    fileprivate let entry: BelugaNetworkAdaptationNativeFinalAdoptionEntry
    fileprivate let use: BelugaNetworkAdaptationPreparedUse
    fileprivate init(entry: BelugaNetworkAdaptationNativeFinalAdoptionEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary, invocation: UInt64) {
        self.entry = entry; use = .init(boundary: boundary, invocation: invocation)
    }
}

struct BelugaNetworkAdaptationSuccessCommit {
    let entry: BelugaNetworkAdaptationNativeSuccessEntry
    let boundary: BelugaNetworkAdaptationOwnerBoundary
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    let outputFPS: Int64?
    fileprivate init(entry: BelugaNetworkAdaptationNativeSuccessEntry,
        boundary: BelugaNetworkAdaptationOwnerBoundary,
        replacement: BelugaNetworkAdaptationOwnerSnapshot, outputFPS: Int64?) {
        self.entry = entry; self.boundary = boundary
        self.replacement = replacement; self.outputFPS = outputFPS
    }
}

extension BelugaNetworkAdaptationOwnerBoundary {
    private typealias SuccessRequest = beluga_core_adaptation_owner_completion_request_t
    private typealias SuccessOutcome = beluga_core_adaptation_owner_completion_outcome_t
    private struct SuccessDecision {
        let result: BelugaNetworkAdaptationSuccessResult
        let commit: BelugaNetworkAdaptationSuccessCommit?
        let output: BelugaNetworkAdaptationNativeSuccessOutput?
        let outputFPS: Int64?
    }
    private final class SuccessFrame {
        let boundary: BelugaNetworkAdaptationOwnerBoundary
        let owner: WorldwideScreenService
        let entry: BelugaNetworkAdaptationNativeSuccessEntry
        let observation: BelugaNetworkAdaptationNativeSuccessObservation
        let invocation: UInt64
        let recovery: BelugaNetworkAdaptationSuccessResult
        #if DEBUG
        // Immutable reference frozen from the sealed entry BEFORE C/FPS.
        let postEffectFixtureRefusal: BelugaNetworkAdaptationPostEffectFixtureRefusal?
        #endif
        // Fixed non-Sendable synchronous actor operations, constructed ONLY in
        // finishSuccess's isolated owner span. No raw C argument crosses them.
        private var prepareOutput: ((BelugaNetworkAdaptationSuccessCommit) throws -> BelugaNetworkAdaptationNativeSuccessOutput?)?
        private var recapture: (() throws -> BelugaNetworkAdaptationNativeSuccessObservation)?
        var active = true, violated = false, effectIssued = false
        var validationCalls: UInt64 = 0, outputCalls: UInt64 = 0
        var decision: SuccessDecision?
        var denial: (any Error)?
        // Caller-owned numeric ranges only, valid during ONE synchronous C call.
        // No private validator argument pointer is retained by this frame.
        var beforeAcceptance: (() -> Bool)?
        init(boundary: BelugaNetworkAdaptationOwnerBoundary, owner: WorldwideScreenService,
            entry: BelugaNetworkAdaptationNativeSuccessEntry,
            observation: BelugaNetworkAdaptationNativeSuccessObservation, invocation: UInt64,
            prepareOutput: @escaping (BelugaNetworkAdaptationSuccessCommit) throws -> BelugaNetworkAdaptationNativeSuccessOutput?,
            recapture: @escaping () throws -> BelugaNetworkAdaptationNativeSuccessObservation) {
            self.boundary = boundary; self.owner = owner; self.entry = entry
            self.observation = observation; self.invocation = invocation
            self.prepareOutput = prepareOutput; self.recapture = recapture
            recovery = .requiresGuardedRecovery(entry.cleanup)
            #if DEBUG
            postEffectFixtureRefusal = entry.postEffectFixtureRefusal
            #endif
        }
        func retire() {
            active = false; beforeAcceptance = nil
            prepareOutput = nil; recapture = nil
        }
        func validate(_ invocation: UInt64, header: UnsafePointer<Header>?, atoms: UnsafePointer<BelugaNetworkAdaptationOwnerWriter.Atom>?,
            atomCount: UInt32, metadata: UnsafePointer<Metadata>?, outcome: UnsafePointer<SuccessOutcome>?,
            edits: UnsafePointer<Edit>?, editCount: UInt32,
            coordinates: UnsafePointer<Coordinate>?, coordinateCount: UInt32) -> UInt32 {
            validationCalls &+= 1
            guard active, validationCalls == 1, !effectIssued, !violated,
                  let prepareOutput, let recapture else { violated = true; return 0 }
            do {
                guard !boundary.poisoned, invocation == self.invocation,
                      atomCount == 179, editCount == 13, coordinateCount == 13,
                      let header, let atoms, let metadata, let outcome, let edits, let coordinates,
                      Self.aligned(header), Self.aligned(atoms), Self.aligned(metadata), Self.aligned(outcome),
                      Self.aligned(edits), Self.aligned(coordinates), beforeAcceptance?() == true else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
                // Copy the ACTUAL private evaluated bundle while borrowed; all
                // allocations/import/correlation below precede acceptance/FPS.
                let h = header.pointee, m = metadata.pointee, o = outcome.pointee
                let a = Array(UnsafeBufferPointer(start: atoms, count: 179))
                let e = Array(UnsafeBufferPointer(start: edits, count: 13))
                let c = Array(UnsafeBufferPointer(start: coordinates, count: 13))
                let source = observation.source, prepared = entry.seed.prepared
                let isCurrent = observation.facts == 511
                    && observation.generation == prepared.tail.generation
                    && source.value.revision == prepared.tail.applyingRevision
                let expectedFPSChanged = isCurrent
                    && source.value.applied?.maximumFramesPerSecond != prepared.tail.recommendation.maximumFramesPerSecond
                guard h.abi == 1, h.domain == 2, h.phase == 2, h.count == 179,
                      o.abi == 1, o.operation == 702, o.invocation == invocation,
                      o.disposition == (isCurrent ? 1 : 0), o.route == 0,
                      o.fps_changed == (expectedFPSChanged ? 1 : 0), o.reserved == 0,
                      m.abi == 1, m.operation == 702, m.scope == 2, m.read_count == 0,
                      m.invocation == invocation, m.revision == source.value.revision,
                      m.peer_present == source.atoms[3].present, m.peer == source.atoms[3].low,
                      m.bound == 0, m.route == 0, m.sample == 0, m.enabled == 0, m.lease == 0,
                      UInt64(m.queue_fault) == source.atoms[41].low,
                      UInt64(m.rtt_fault) == source.atoms[89].low else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
                let timeIndices = [12,23,28,159,163,167,39,40,88]
                for i in 0..<13 {
                    if i < 9 {
                        let old = source.atoms[timeIndices[i]]
                        guard e[i].action == 1, e[i].source == 0, e[i].index == 0, e[i].ordinal == 0,
                              e[i].high == 0, e[i].low == 0,
                              c[i].present == old.present, c[i].reserved == 0,
                              c[i].high == old.high, c[i].low == old.low else {
                            throw BelugaNetworkAdaptationOwnerError.invalidResult
                        }
                    } else {
                        guard e[i].action == 0, e[i].source == 0, e[i].index == 0, e[i].ordinal == 0,
                              e[i].high == 0, e[i].low == 0,
                              c[i].present == 0, c[i].reserved == 0, c[i].high == 0, c[i].low == 0 else {
                            throw BelugaNetworkAdaptationOwnerError.invalidResult
                        }
                    }
                }
                // Typed LIMITED applied import only; policy/revision/all other
                // native fields are retained, never reconstructed from scalar POD.
                let v = source.value
                let replacement: BelugaNetworkAdaptationOwnerSnapshot
                if isCurrent {
                    replacement = try .capture(.init(policy: v.policy, revision: v.revision,
                        fastStatisticsAvailable: v.fastStatisticsAvailable, lane: v.lane,
                        evidenceTime: v.evidenceTime, minimumCollectionSequence: v.minimumCollectionSequence,
                        applied: prepared.tail.recommendation), retainingAnchor: source.anchor)
                } else { replacement = source }
                guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(a, replacement.atoms),
                      replacement.times == source.times, replacement.anchor == source.anchor,
                      replacement.route == source.route else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
                let candidate: SuccessDecision
                if isCurrent {
                    let fps: Int64? = expectedFPSChanged ? Int64(prepared.tail.recommendation.maximumFramesPerSecond) : nil
                    let commit = BelugaNetworkAdaptationSuccessCommit(entry: entry, boundary: boundary,
                        replacement: replacement, outputFPS: fps)
                    let output = try prepareOutput(commit)
                    let final = BelugaNetworkAdaptationFinalAdoptionReceipt(entry: entry.finalEntry,
                        boundary: boundary, invocation: invocation)
                    candidate = .init(result: .accepted(final), commit: commit, output: output, outputFPS: fps)
                } else {
                    candidate = .init(result: .rollback(entry.cleanup), commit: nil, output: nil, outputFPS: nil)
                }
                let fresh = try recapture()
                guard BelugaNetworkAdaptationOwnerBoundary.samePublicationSource(fresh.source, source),
                      fresh.generation == observation.generation, fresh.facts == observation.facts,
                      !boundary.poisoned, !violated, beforeAcceptance?() == true else {
                    throw BelugaNetworkAdaptationOwnerError.refused
                }
                decision = candidate // Everything, including successor/result, is preconstructed.
                return 1
            } catch { denial = error; return 0 }
        }
        private static func aligned<T>(_ pointer: UnsafePointer<T>) -> Bool {
            UInt(bitPattern: pointer) % UInt(MemoryLayout<T>.alignment) == 0
        }
        func output(_ invocation: UInt64, fps: Int64) {
            outputCalls &+= 1
            guard active, outputCalls == 1, !effectIssued, !violated,
                  !boundary.poisoned, validationCalls == 1, denial == nil,
                  invocation == self.invocation, let decision, let output = decision.output,
                  decision.outputFPS == fps else { violated = true; return }
            effectIssued = true
            // Fixed nonthrowing original-capturer action; no allocation/import,
            // actor query, arbitrary callback, Boundary reentry or borrowed POD.
            output.perform()
        }
    }

    func finishSuccess(_ completion: BelugaNetworkAdaptationNativeCompletion,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationSuccessResult {
        // Like Prepared spending, swallowed replay/wrong-origin under a held
        // Boundary poisons its outer invocation BEFORE the spend can throw.
        if busy { poisoned = true }
        let entry = try owner.networkAdaptationSuccessCompletionEntry(completion, boundary: self)
        if busy { return .refused(entry.cleanup, BelugaNetworkAdaptationOwnerError.reentry) }
        busy = true; poisoned = false
        defer { busy = false; poisoned = false }
        guard invocation != UInt64.max else {
            return .refused(entry.cleanup, BelugaNetworkAdaptationOwnerError.invocationExhausted)
        }
        invocation += 1
        let observation: BelugaNetworkAdaptationNativeSuccessObservation
        switch entry.admission {
        case let .ready(value): observation = value
        case let .refused(error): return .refused(entry.cleanup, error)
        }
        guard Self.successLayoutIsExact else {
            return .refused(entry.cleanup, BelugaNetworkAdaptationOwnerError.unsupportedLayout)
        }
        let frame = SuccessFrame(boundary: self, owner: owner, entry: entry,
            observation: observation, invocation: invocation,
            prepareOutput: { packet in try owner.networkAdaptationPrepareSuccessOutput(packet) },
            recapture: { try owner.networkAdaptationSuccessRecapture(entry) })
        defer { frame.retire() }
        let status = Self.callActualValidatedSuccess(frame)
        frame.retire()
        // The old withGuard's fallible post-body check is NOT used here.
        // After an issued FPS, only a sealed fixed store OR the preconstructed
        // mandatory-recovery result remains. Never throw/refuse/import/recheck.
        if frame.effectIssued {
            #if DEBUG
            let admittedStatus: UInt32
            if let fault = frame.postEffectFixtureRefusal {
                // Fixed scalar witness/substitution only. No actor query,
                // callback, allocation, claim, throw or C-pointer access.
                fault.recordActualPostEffectStatus(status)
                admittedStatus = 0
            } else { admittedStatus = status }
            #else
            let admittedStatus = status
            #endif
            guard admittedStatus == 1, !poisoned, !frame.violated, frame.validationCalls == 1,
                  frame.outputCalls == 1, let decision = frame.decision, let commit = decision.commit else {
                return frame.recovery
            }
            owner.networkAdaptationSuccessCommit(commit)
            return decision.result
        }
        guard status == 1, !poisoned, !frame.violated, frame.validationCalls == 1,
              frame.outputCalls == 0, let decision = frame.decision,
              decision.output == nil else {
            return .refused(entry.cleanup, frame.denial ?? BelugaNetworkAdaptationOwnerError.invalidResult)
        }
        if let commit = decision.commit { owner.networkAdaptationSuccessCommit(commit) }
        return decision.result
    }

    private static var successLayoutIsExact: Bool {
        typealias R = SuccessRequest; typealias O = SuccessOutcome
        return beginActiveLayoutIsExact && layout(R.self, 32, 8,
            [MemoryLayout<R>.offset(of: \R.abi),MemoryLayout<R>.offset(of: \R.operation),
             MemoryLayout<R>.offset(of: \R.invocation),MemoryLayout<R>.offset(of: \R.current_generation),
             MemoryLayout<R>.offset(of: \R.facts),MemoryLayout<R>.offset(of: \R.reserved)], [0,4,8,16,24,28])
            && layout(O.self, 32, 8,
            [MemoryLayout<O>.offset(of: \O.abi),MemoryLayout<O>.offset(of: \O.operation),
             MemoryLayout<O>.offset(of: \O.invocation),MemoryLayout<O>.offset(of: \O.disposition),
             MemoryLayout<O>.offset(of: \O.route),MemoryLayout<O>.offset(of: \O.fps_changed),
             MemoryLayout<O>.offset(of: \O.reserved)], [0,4,8,16,20,24,28])
    }
    private static func successValidationCallback(_ context: UnsafeMutableRawPointer?, _ invocation: UInt64,
        _ header: UnsafePointer<Header>?, _ atoms: UnsafePointer<BelugaNetworkAdaptationOwnerWriter.Atom>?, _ atomCount: UInt32,
        _ metadata: UnsafePointer<Metadata>?, _ outcome: UnsafePointer<SuccessOutcome>?,
        _ edits: UnsafePointer<Edit>?, _ editCount: UInt32,
        _ coordinates: UnsafePointer<Coordinate>?, _ coordinateCount: UInt32) -> UInt32 {
        guard let context else { return 0 }
        let frame = Unmanaged<SuccessFrame>.fromOpaque(context).takeUnretainedValue()
        // This is a synchronous callback on the SAME executor, not a transfer
        // into an isolated closure. Validate/copy raw arguments locally before
        // the frame invokes its two closed typed actor operations.
        frame.owner.preconditionIsolated()
        return frame.validate(invocation, header: header, atoms: atoms, atomCount: atomCount,
            metadata: metadata, outcome: outcome, edits: edits, editCount: editCount,
            coordinates: coordinates, coordinateCount: coordinateCount)
    }
    private static func successOutputCallback(_ context: UnsafeMutableRawPointer?, _ invocation: UInt64, _ fps: Int64) {
        guard let context else { return }
        let frame = Unmanaged<SuccessFrame>.fromOpaque(context).takeUnretainedValue()
        frame.owner.preconditionIsolated()
        frame.output(invocation, fps: fps)
    }

    private static func callActualValidatedSuccess(_ frame: SuccessFrame) -> UInt32 {
        let source = frame.observation.source, prepared = frame.entry.seed.prepared
        var q = SuccessRequest(abi: 1, operation: 702, invocation: frame.invocation,
            current_generation: frame.observation.generation, facts: frame.observation.facts, reserved: 0)
        var ih = Header(abi: 1, domain: 2, phase: 1, count: 179), ia = source.atoms.map { $0 }
        var ph = Header(abi: 1, domain: 4, phase: 3, count: 222), pa = prepared.atoms.map { $0 }
        var h = Header(abi: 91, domain: 92, phase: 93, count: 94)
        var a = Array(repeating: BelugaNetworkAdaptationOwnerWriter.Atom(kind: 95, present: 96, high: -97, low: 98), count: 179)
        var m = Metadata(abi: 81, operation: 82, scope: 83, read_count: 84, invocation: 85,
            revision: 86, peer: 87, peer_present: 88, bound: 89, route: 90, sample: 91,
            enabled: 92, lease: 93, queue_fault: 94, rtt_fault: 95)
        var o = SuccessOutcome(abi: 41, operation: 42, invocation: 43, disposition: 44, route: 45, fps_changed: 46, reserved: 47)
        var e = Array(repeating: Edit(action: 71, source: 72, index: 73, ordinal: 74, high: -75, low: 76), count: 13)
        var c = Array(repeating: Coordinate(present: 61, reserved: 62, high: -63, low: 64), count: 13)
        // Fully distinct owned ranges, initialized before C reads or callbacks.
        return withExtendedLifetime(frame) {
            withUnsafePointer(to: &q) { req in withUnsafePointer(to: &ih) { header in
                ia.withUnsafeMutableBufferPointer { input in withUnsafePointer(to: &ph) { preparedHeader in
                    pa.withUnsafeMutableBufferPointer { preparedInput in withUnsafeMutablePointer(to: &h) { outHeader in
                        a.withUnsafeMutableBufferPointer { output in withUnsafeMutablePointer(to: &m) { metadata in
                            withUnsafeMutablePointer(to: &o) { outcome in e.withUnsafeMutableBufferPointer { edits in
                                c.withUnsafeMutableBufferPointer { coords in
                                    let inputBase = input.baseAddress!, preparedBase = preparedInput.baseAddress!
                                    let outputBase = output.baseAddress!, editBase = edits.baseAddress!, coordinateBase = coords.baseAddress!
                                    func raw<T>(_ p: UnsafePointer<T>, _ count: Int) -> [UInt8] {
                                        Array(UnsafeRawBufferPointer(start: p, count: count * MemoryLayout<T>.stride))
                                    }
                                    func inputs() -> [[UInt8]] {
                                        [raw(req,1),raw(header,1),raw(UnsafePointer(inputBase),179),
                                         raw(preparedHeader,1),raw(UnsafePointer(preparedBase),222)]
                                    }
                                    func outputs() -> [[UInt8]] {
                                        [raw(UnsafePointer(outHeader),1),raw(UnsafePointer(outputBase),179),raw(UnsafePointer(metadata),1),
                                         raw(UnsafePointer(outcome),1),raw(UnsafePointer(editBase),13),raw(UnsafePointer(coordinateBase),13)]
                                    }
                                    let beforeInputs = inputs(), beforeOutputs = outputs()
                                    frame.beforeAcceptance = { inputs() == beforeInputs && outputs() == beforeOutputs }
                                    defer { frame.beforeAcceptance = nil }
                                    return beluga_core_network_adaptation_owner_finish_success_validated(
                                        req, header, inputBase, 179, preparedHeader, preparedBase, 222,
                                        { context, invocation, header, atoms, atomCount, metadata, outcome, edits, editCount, coordinates, coordinateCount in
                                            BelugaNetworkAdaptationOwnerBoundary.successValidationCallback(context, invocation,
                                                header, atoms, atomCount, metadata, outcome, edits, editCount, coordinates, coordinateCount)
                                        },
                                        { context, invocation, fps in
                                            BelugaNetworkAdaptationOwnerBoundary.successOutputCallback(context, invocation, fps)
                                        }, Unmanaged.passUnretained(frame).toOpaque(),
                                        outHeader, outputBase, 179, metadata, outcome,
                                        editBase, 13, coordinateBase, 13)
                                }
                            } }
                        } }
                    } }
                } }
            } }
        }
    }
}

struct BelugaNetworkAdaptationFailureRetainedReceipt {
    enum Disposition: UInt32 { case stale = 0, ordinary = 1, fastIdentity = 2, terminalNegative = 3, semanticPrefix = 4 }
    let disposition: Disposition
    let semanticStatus: UInt32 // 0 or 2/3/4; NEVER mistaken for the ABI status.
    let acceptedReads: UInt32
    let attemptedReads: UInt32
    let clockDenial: (any Error)?
    private let entry: BelugaNetworkAdaptationNativeFailureEntry
    var actualSenderError: any Error { entry.senderError }
    fileprivate init(entry: BelugaNetworkAdaptationNativeFailureEntry, disposition: Disposition,
        semanticStatus: UInt32, acceptedReads: UInt32, attemptedReads: UInt32, clockDenial: (any Error)?) {
        self.entry = entry; self.disposition = disposition; self.semanticStatus = semanticStatus
        self.acceptedReads = acceptedReads; self.attemptedReads = attemptedReads; self.clockDenial = clockDenial
    }
}
enum BelugaNetworkAdaptationFailureResult {
    // Includes a semantically denied prefix AFTER it has been fully imported/stored.
    case retained(BelugaNetworkAdaptationFailureRetainedReceipt)
    // No trusted prefix was available. Original SDK error remains retained too.
    case requiresGuardedRecovery(BelugaNetworkAdaptationNativeFailureEntry, any Error)
}
struct BelugaNetworkAdaptationFailureCommit {
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    fileprivate init(replacement: BelugaNetworkAdaptationOwnerSnapshot) { self.replacement = replacement }
}
extension BelugaNetworkAdaptationOwnerBoundary {
    private typealias FailureRequest = beluga_core_adaptation_owner_failure_request_t
    private typealias FailureOutcome = beluga_core_adaptation_owner_failure_outcome_t
    private struct FailureRaw {
        let status: UInt32; let header: Header; let atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
        let metadata: Metadata; let outcome: FailureOutcome
        let edits: [Edit]; let coordinates: [Coordinate]; let reads: [Reply]
        let inputsUnchanged: Bool; let deniedOutputsUntouched: Bool
    }
    private struct FailureAdmission {
        let current: Bool; let terminal: Bool; let fastEligible: Bool; let observedRTTFault: Bool
        let plan: [UInt32]; let firstCutDenial: (any Error)?
    }
    private final class FailureClockFrame {
        let owner: WorldwideScreenService
        let invocation: UInt64; let plan: [UInt32]
        private let anchor: ContinuousClock.Instant
        private let boundary: BelugaNetworkAdaptationOwnerBoundary
        private var provider: (() throws -> ContinuousClock.Instant)?
        private let firstCutDenial: (any Error)?
        private(set) var accepted: [Reply] = []
        private(set) var attempts: UInt32 = 0
        private(set) var denied: (any Error)?
        private(set) var violated = false
        private var active = true, reading = false
        // Own caller ranges, only within the one synchronous actual ABI call.
        var beforeRead: (() -> Bool)?
        init(owner: WorldwideScreenService, boundary: BelugaNetworkAdaptationOwnerBoundary,
            invocation: UInt64, plan: [UInt32], anchor: ContinuousClock.Instant,
            firstCutDenial: (any Error)?, provider: @escaping () throws -> ContinuousClock.Instant) {
            self.owner = owner; self.boundary = boundary; self.invocation = invocation
            self.plan = plan; self.anchor = anchor; self.firstCutDenial = firstCutDenial; self.provider = provider
        }
        func retire() { active = false; provider = nil; beforeRead = nil }
        func reply(_ invocation: UInt64, _ site: UInt32, _ ordinal: UInt32, _ destination: UnsafeMutablePointer<Reply>?) -> UInt32 {
            guard active, !reading, denied == nil, !violated, !boundary.poisoned,
                  let provider, let destination,
                  UInt(bitPattern: destination) % UInt(MemoryLayout<Reply>.alignment) == 0,
                  invocation == self.invocation, Int(ordinal) == accepted.count,
                  Int(attempts) == accepted.count, accepted.count < plan.count,
                  plan.count <= 2, plan[accepted.count] == site, beforeRead?() == true else {
                violated = true; return 0
            }
            attempts += 1; reading = true
            defer { reading = false }
            do {
                if let firstCutDenial { throw firstCutDenial }
                let instant = try provider()
                guard active, !boundary.poisoned, beforeRead?() == true else { violated = true; return 0 }
                let coordinate = OwnerAttoseconds(anchor.duration(to: instant))
                guard coordinate.fitsCodecTime else { throw BelugaNetworkAdaptationOwnerError.unrepresentableTime }
                let value = Reply(abi: 1, status: 1, site: site, ordinal: ordinal,
                    invocation: invocation, high: coordinate.high, low: coordinate.low, reserved: 0)
                accepted.append(value); destination.pointee = value
                return 1
            } catch { denied = error; return 0 }
        }
    }

    // Replay/wrong-kind admission may throw before any prefix exists. Every
    // later refusal is an explicit fail-closed result retaining the SDK error.
    func finishFailure(_ completion: BelugaNetworkAdaptationNativeCompletion,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationFailureResult {
        if busy { poisoned = true }
        let entry = try owner.networkAdaptationFailureCompletionEntry(completion, boundary: self)
        if busy { return .requiresGuardedRecovery(entry, BelugaNetworkAdaptationOwnerError.reentry) }
        busy = true; poisoned = false
        defer { busy = false; poisoned = false }
        do {
            guard invocation != UInt64.max else { throw BelugaNetworkAdaptationOwnerError.invocationExhausted }
            invocation += 1
            guard case let .ready(observation) = entry.admission else {
                if case let .refused(error) = entry.admission { return .requiresGuardedRecovery(entry, error) }
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            guard Self.failureLayoutIsExact, let anchor = observation.source.anchor,
                  observation.source.anchor == entry.seed.prepared.source.anchor else {
                throw BelugaNetworkAdaptationOwnerError.unsupportedLayout
            }
            let admission = Self.failureAdmission(observation, entry.seed.prepared)
            let frame = FailureClockFrame(owner: owner, boundary: self, invocation: invocation,
                plan: admission.plan, anchor: anchor, firstCutDenial: admission.firstCutDenial, provider: clockProvider)
            defer { frame.retire() }
            let raw = Self.callActualFailure(observation, entry.seed.prepared, frame)
            frame.retire()
            guard !poisoned, !frame.violated, raw.inputsUnchanged else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            // These are ABI failures, NOT semantic_error2/3/4 in a valid output.
            guard raw.status == 1 else {
                guard raw.deniedOutputsUntouched else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            let replacement = try Self.importFailure(raw, observation: observation,
                prepared: entry.seed.prepared, admission: admission, frame: frame)
            let disposition = BelugaNetworkAdaptationFailureRetainedReceipt.Disposition(rawValue: raw.outcome.disposition)!
            let result = BelugaNetworkAdaptationFailureResult.retained(.init(entry: entry,
                disposition: disposition, semanticStatus: raw.outcome.semantic_error,
                acceptedReads: raw.metadata.read_count, attemptedReads: raw.outcome.attempted_reads,
                clockDenial: frame.denied))
            let commit = BelugaNetworkAdaptationFailureCommit(replacement: replacement)
            // Fixed typed synchronous capability; nothing crosses an executor.
            let fresh = try owner.networkAdaptationFailureRecapture(entry)
            guard !poisoned, Self.samePublicationSource(fresh.source, observation.source),
                  fresh.generation == observation.generation, fresh.facts == observation.facts else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            if disposition != .stale { owner.networkAdaptationFailureCommit(commit) }
            // NO throw/check/import after publication, including semantic denial.
            return result
        } catch { return .requiresGuardedRecovery(entry, error) }
    }

    private static func failureAdmission(_ observation: BelugaNetworkAdaptationNativeFailureObservation,
        _ p: BelugaNetworkAdaptationGeneralPreparedValue) -> FailureAdmission {
        let a = observation.source.atoms
        let current = observation.facts == 511 && observation.generation == p.tail.generation
            && observation.source.value.revision == p.tail.applyingRevision
        let terminal = current && ((a[157].present == 1 && a[20].present == 1 && a[20].low == 7 && p.atoms[156].low == 1)
            || (p.tail.capacityOnly && a[20].present == 1 && p.atoms[20].present == 0))
        let fast = current && !terminal && p.tail.capacityOnly && p.atoms[150].present == 1
            && a[3].present == p.atoms[3].present && a[3].low == p.atoms[3].low
            && a[20].present == 1 && p.atoms[20].present == 1 && a[20].low == p.atoms[20].low
            && p.atoms[150].low > (a[143].present == 1 ? a[143].low : 0)
            && p.atoms[150].low > (a[150].present == 1 ? a[150].low : 0)
        let observedRTTFault = p.atoms[89].low == 1
        guard fast else { return .init(current: current, terminal: terminal, fastEligible: false,
            observedRTTFault: observedRTTFault, plan: [], firstCutDenial: nil) }
        if observedRTTFault { return .init(current: current, terminal: false, fastEligible: true,
            observedRTTFault: true, plan: [2], firstCutDenial: nil) }
        do {
            let willFault = try observation.source.value.policy.networkAdaptationOwnerFailureCopyFenceWillFault(from: p.policy)
            let queue = willFault || a[140].low == 1 || p.atoms[140].low == 1
            return .init(current: current, terminal: false, fastEligible: true, observedRTTFault: false,
                plan: queue ? [4, 2] : [4], firstCutDenial: nil)
        } catch {
            // Never reject the whole event before it reaches the native pre-F prefix.
            return .init(current: current, terminal: false, fastEligible: true, observedRTTFault: false,
                plan: [4], firstCutDenial: error)
        }
    }

    private static func importFailure(_ raw: FailureRaw,
        observation: BelugaNetworkAdaptationNativeFailureObservation,
        prepared p: BelugaNetworkAdaptationGeneralPreparedValue,
        admission: FailureAdmission, frame: FailureClockFrame) throws -> BelugaNetworkAdaptationOwnerSnapshot {
        let source = observation.source, o = raw.outcome, m = raw.metadata
        guard raw.header.abi == 1, raw.header.domain == 2, raw.header.phase == 2, raw.header.count == 179,
              raw.atoms.count == 179, raw.edits.count == 13, raw.coordinates.count == 13, raw.reads.count == 15,
              o.abi == 1, o.operation == 703, o.invocation == frame.invocation, o.route <= 2,
              [UInt32(0), 2, 3, 4].contains(o.semantic_error), o.attempted_reads == frame.attempts,
              m.abi == 1, m.operation == 703, m.scope == 2, m.invocation == frame.invocation,
              m.read_count == UInt32(frame.accepted.count), m.route == o.route,
              m.bound == 0, m.sample == 0, m.enabled == 0, m.lease == 0,
              m.peer_present == raw.atoms[3].present, m.peer == raw.atoms[3].low,
              UInt64(m.queue_fault) == raw.atoms[41].low, UInt64(m.rtt_fault) == raw.atoms[89].low else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        let semantic = o.semantic_error != 0
        guard semantic ? (admission.current && o.disposition == 4 && o.route == 0) :
            (o.disposition == (admission.current ? (admission.terminal ? 3 : (p.tail.capacityOnly ? 2 : 1)) : 0)),
              semantic || (frame.denied == nil && frame.accepted.count == frame.plan.count),
              frame.denied == nil || (o.semantic_error == 3 && frame.attempts == UInt32(frame.accepted.count + 1)),
              m.revision == (semantic || !admission.current ? source.value.revision : source.value.revision &+ 1),
              raw.atoms[168].low == m.revision,
              BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(Array(raw.atoms[169...]), Array(source.atoms[169...])) else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        for i in 0..<15 {
            guard bytes(raw.reads[i]) == bytes(i < frame.accepted.count ? frame.accepted[i] : Reply()) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        if !admission.current {
            guard frame.attempts == 0, o.route == 0,
                  BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(raw.atoms, source.atoms) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        for (a, before) in zip(raw.atoms, source.atoms) {
            guard a.kind == before.kind, a.present <= 1, a.kind == 10 || a.high == 0,
                  a.present != 0 || (a.high == 0 && a.low == 0) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            if a.present == 1 {
                switch a.kind {
                case 4, 8: guard a.low <= 1 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                case 5: guard a.low <= UInt64(UInt8.max) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                case 6: guard a.low <= UInt64(UInt32.max) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                case 7: guard a.low <= 7 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                default: break
                }
            }
        }
        var times = source.times
        let indices = [12,23,28,159,163,167,39,40,88]
        for i in 0..<13 {
            let e = raw.edits[i], c = raw.coordinates[i]
            if i >= 9 {
                guard bytes(e) == bytes(Edit()), bytes(c) == bytes(Coordinate()) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                continue
            }
            let before = o.disposition == 3 ? p.atoms[indices[i]] : source.atoms[indices[i]]
            let expected = Coordinate(present: before.present, reserved: 0, high: before.high, low: before.low)
            if o.disposition == 3 {
                guard e.action == (before.present == 1 ? 3 : 2), e.source == (before.present == 1 ? 2 : 0),
                      e.index == (before.present == 1 ? UInt32(i) : 0), e.ordinal == 0, e.high == 0, e.low == 0,
                      bytes(c) == bytes(expected) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                times[i] = p.policyTimes[i]
            } else {
                guard (e.action == 1 || (e.action == 2 && UInt16(0x00ef) & (1 << i) != 0)),
                      e.source == 0, e.index == 0, e.ordinal == 0, e.high == 0, e.low == 0,
                      bytes(c) == bytes(e.action == 1 ? expected : Coordinate()) else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                if e.action == 2 { times[i] = nil }
            }
        }
        let route: WebRTCICERouteDiagnostics?
        if o.disposition == 3 {
            switch p.tail.routeAction {
            case .retain: guard o.route == 0 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }; route = source.route
            case .clear: guard o.route == 1 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }; route = nil
            case .copyIncoming: guard o.route == 2 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }; route = p.report.incomingRoute
            }
            guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(Array(raw.atoms.prefix(168)), Array(p.atoms.prefix(168))) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        } else { guard o.route == 0 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }; route = source.route }
        try correlateFailureNegativePrefix(raw, source: source, prepared: p, admission: admission, frame: frame)
        var policy = o.disposition == 3 ? p.policy : source.value.policy
        if o.disposition == 3 {
            // Retain ACTUAL Prepared policy/dependencies/times; route custody still
            // follows the explicit route action, including copy of genuine nil.
            try policy.networkAdaptationOwnerImportClocked(.init(atoms: raw.atoms, fields: [144], times: times, route: route))
        } else {
            // Rejection-only original write families. No successful value is
            // evaluated locally. Complete/partial values are from actual703 only.
            var fields: Set<Int> = admission.current ? [155,158,159,160,161,162,166,167] : []
            if admission.fastEligible { fields.formUnion([149,150]) }
            let copiedRTT = frame.accepted.contains { $0.site == 4 }
            if copiedRTT { fields.formUnion(rttFields) }
            if admission.fastEligible && admission.observedRTTFault { fields.insert(89) }
            if copiedRTT || (admission.fastEligible && admission.observedRTTFault) { fields.insert(140) }
            let attemptedQ = frame.plan.prefix(Int(frame.attempts)).contains(2)
            if attemptedQ { fields.formUnion([4,156,157,158,159,160,145,146,147,148,25,26,27,28]) }
            if frame.accepted.contains(where: { $0.site == 2 }) { fields.formUnion(revertFields.union([5,9,166,167])) }
            if source.atoms[41].low == 1 { fields.subtract(Set(36...41)) }
            if source.atoms[89].low == 1 { fields.subtract(Set(42...88)) }
            for i in 0..<168 where !fields.contains(i) {
                guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms([raw.atoms[i]], [source.atoms[i]]) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
            }
            if fields.contains(89), source.atoms[89].low == 0 { fields.insert(42) }
            try policy.networkAdaptationOwnerImportClocked(.init(atoms: raw.atoms, fields: fields, times: times, route: route))
        }
        let v = source.value
        let value = BelugaNetworkAdaptationOwnerValue(policy: policy, revision: m.revision,
            fastStatisticsAvailable: v.fastStatisticsAvailable, lane: v.lane, evidenceTime: v.evidenceTime,
            minimumCollectionSequence: v.minimumCollectionSequence, applied: v.applied)
        let imported = try BelugaNetworkAdaptationOwnerSnapshot.capture(value, retainingAnchor: source.anchor)
        guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(imported.atoms, raw.atoms),
              imported.times == times, imported.anchor == source.anchor, imported.route == route else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        return imported
    }
    private static func correlateFailureNegativePrefix(_ raw: FailureRaw,
        source: BelugaNetworkAdaptationOwnerSnapshot, prepared p: BelugaNetworkAdaptationGeneralPreparedValue,
        admission: FailureAdmission, frame: FailureClockFrame) throws {
        guard admission.current, raw.outcome.disposition != 3 else { return }
        let a = source.atoms, b = p.atoms, r = raw.atoms
        // Only rejection correlation of mandatory already-observed negatives.
        // These expected words are NEVER used to construct the imported successor.
        let startup = a[164].present == 1 && a[165].present == 1 && a[166].low == 0
            && a[3].present == 1 && a[3].low == a[164].low
            && a[152].present == 1 && a[152].low == a[165].low
            && b[166].low == 1 && b[164].present == 1 && b[164].low == a[164].low
            && b[165].present == 1 && b[165].low == a[165].low
            && b[3].present == 1 && b[3].low == a[164].low
            && b[152].present == 1 && b[152].low == a[165].low
        if startup {
            guard r[166].low == 1, r[167].present == 0, raw.edits[5].action == 2 else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        let attempt = a[3].present == b[3].present && a[3].low == b[3].low
            && a[152].present == 1 && b[152].present == 1 && a[152].low == b[152].low && b[155].low == 1
        if attempt {
            guard r[155].low == 1, r[158].low == 0, r[159].present == 0, r[160].present == 0,
                  raw.edits[3].action == 2 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            if b[161].present == 1 {
                guard r[161].present == 1, r[161].low == max(a[161].present == 1 ? a[161].low : 0, b[161].low) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
            } else {
                guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms([r[161]], [a[161]]) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
            }
            if b[162].present == 1 {
                let oldBits = a[162].present == 1 ? a[162].low : Double(0).bitPattern
                let selectedBits = Double(bitPattern: b[162].low) >= Double(bitPattern: oldBits) ? b[162].low : oldBits
                guard r[162].present == 1, r[162].low == selectedBits else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
            } else {
                guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms([r[162]], [a[162]]) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
            }
        }
        if admission.fastEligible {
            guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms([r[149],r[150]], [b[149],b[150]]) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            if admission.observedRTTFault { guard r[89].low == 1 else { throw BelugaNetworkAdaptationOwnerError.invalidResult } }
        }
        if frame.plan.prefix(Int(frame.attempts)).contains(2) {
            guard r[4].present == 1, r[4].low == a[20].low,
                  r[158].low == 0, r[159].present == 0, r[160].present == 0,
                  r[145].low == 0, r[146].present == 0, r[147].present == 0, r[148].present == 0,
                  r[25].low == 0, r[26].present == 0, r[27].present == 0, r[28].present == 0 else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            if a[157].present == 1 && a[20].low == 7 {
                guard r[156].low == 1, r[157].present == 0 else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            }
        }
    }
    private static func failureClockCallback(_ context: UnsafeMutableRawPointer?, _ invocation: UInt64,
        _ site: UInt32, _ ordinal: UInt32, _ reply: UnsafeMutablePointer<Reply>?) -> UInt32 {
        guard let context else { return 0 }
        let frame = Unmanaged<FailureClockFrame>.fromOpaque(context).takeUnretainedValue()
        frame.owner.preconditionIsolated()
        return frame.reply(invocation, site, ordinal, reply)
    }
    private static func callActualFailure(_ observation: BelugaNetworkAdaptationNativeFailureObservation,
        _ prepared: BelugaNetworkAdaptationGeneralPreparedValue, _ frame: FailureClockFrame) -> FailureRaw {
        var q = FailureRequest(abi: 1, operation: 703, invocation: frame.invocation,
            current_generation: observation.generation, facts: observation.facts, reserved: 0)
        var ih = Header(abi: 1, domain: 2, phase: 1, count: 179), ia = observation.source.atoms.map { $0 }
        var ph = Header(abi: 1, domain: 4, phase: 3, count: 222), pa = prepared.atoms.map { $0 }
        var h = Header(abi: 91, domain: 92, phase: 93, count: 94)
        var a = Array(repeating: BelugaNetworkAdaptationOwnerWriter.Atom(kind: 95, present: 96, high: -97, low: 98), count: 179)
        var m = Metadata(abi: 81, operation: 82, scope: 83, read_count: 84, invocation: 85, revision: 86,
            peer: 87, peer_present: 88, bound: 89, route: 90, sample: 91, enabled: 92, lease: 93, queue_fault: 94, rtt_fault: 95)
        var o = FailureOutcome(abi: 41, operation: 42, invocation: 43, disposition: 44, route: 45, semantic_error: 46, attempted_reads: 47)
        var e = Array(repeating: Edit(action: 71, source: 72, index: 73, ordinal: 74, high: -75, low: 76), count: 13)
        var c = Array(repeating: Coordinate(present: 61, reserved: 62, high: -63, low: 64), count: 13)
        var r = Array(repeating: Reply(abi: 51, status: 52, site: 53, ordinal: 54, invocation: 55, high: -56, low: 57, reserved: 58), count: 15)
        var unchanged = false, untouched = false
        let status = withExtendedLifetime(frame) {
            withUnsafePointer(to: &q) { req in withUnsafePointer(to: &ih) { header in
                ia.withUnsafeMutableBufferPointer { input in withUnsafePointer(to: &ph) { preparedHeader in
                    pa.withUnsafeMutableBufferPointer { preparedInput in withUnsafeMutablePointer(to: &h) { outHeader in
                        a.withUnsafeMutableBufferPointer { output in withUnsafeMutablePointer(to: &m) { metadata in
                            withUnsafeMutablePointer(to: &o) { outcome in e.withUnsafeMutableBufferPointer { edits in
                                c.withUnsafeMutableBufferPointer { coords in r.withUnsafeMutableBufferPointer { reads in
                                    let inputBase = input.baseAddress!, preparedBase = preparedInput.baseAddress!
                                    let outputBase = output.baseAddress!, editBase = edits.baseAddress!
                                    let coordinateBase = coords.baseAddress!, readBase = reads.baseAddress!
                                    func raw<T>(_ pointer: UnsafePointer<T>, _ count: Int) -> [UInt8] {
                                        Array(UnsafeRawBufferPointer(start: pointer, count: count * MemoryLayout<T>.stride))
                                    }
                                    func inputs() -> [[UInt8]] { [raw(req,1),raw(header,1),raw(UnsafePointer(inputBase),179),raw(preparedHeader,1),raw(UnsafePointer(preparedBase),222)] }
                                    func outputs() -> [[UInt8]] { [raw(UnsafePointer(outHeader),1),raw(UnsafePointer(outputBase),179),raw(UnsafePointer(metadata),1),raw(UnsafePointer(outcome),1),raw(UnsafePointer(editBase),13),raw(UnsafePointer(coordinateBase),13),raw(UnsafePointer(readBase),15)] }
                                    let beforeInputs = inputs(), beforeOutputs = outputs()
                                    frame.beforeRead = { inputs() == beforeInputs && outputs() == beforeOutputs }
                                    defer { frame.retire() }
                                    let status = beluga_core_network_adaptation_owner_finish_failure(
                                        req, header, inputBase,179,preparedHeader,preparedBase,222,
                                        { context, invocation, site, ordinal, reply in
                                            BelugaNetworkAdaptationOwnerBoundary.failureClockCallback(context,invocation,site,ordinal,reply)
                                        },Unmanaged.passUnretained(frame).toOpaque(),
                                        outHeader,outputBase,179,metadata,outcome,editBase,13,coordinateBase,13,readBase,15)
                                    unchanged = inputs() == beforeInputs; untouched = outputs() == beforeOutputs
                                    return status
                                } }
                            } }
                        } }
                    } }
                } }
            } }
        }
        return .init(status: status, header: h, atoms: a, metadata: m, outcome: o,
            edits: e, coordinates: c, reads: r, inputsUnchanged: unchanged, deniedOutputsUntouched: untouched)
    }
    private static var failureLayoutIsExact: Bool {
        typealias R = FailureRequest; typealias O = FailureOutcome
        return beginActiveLayoutIsExact && layout(R.self,32,8,
            [MemoryLayout<R>.offset(of: \R.abi),MemoryLayout<R>.offset(of: \R.operation),MemoryLayout<R>.offset(of: \R.invocation),MemoryLayout<R>.offset(of: \R.current_generation),MemoryLayout<R>.offset(of: \R.facts),MemoryLayout<R>.offset(of: \R.reserved)],[0,4,8,16,24,28])
            && layout(O.self,32,8,
            [MemoryLayout<O>.offset(of: \O.abi),MemoryLayout<O>.offset(of: \O.operation),MemoryLayout<O>.offset(of: \O.invocation),MemoryLayout<O>.offset(of: \O.disposition),MemoryLayout<O>.offset(of: \O.route),MemoryLayout<O>.offset(of: \O.semantic_error),MemoryLayout<O>.offset(of: \O.attempted_reads)],[0,4,8,16,20,24,28])
    }
}

enum BelugaNetworkAdaptationFinalAdoptionResult {
    case adopted
    case superseded
    // One-use entry retained for fail-closed diagnostics, not a retry/effect grant.
    case refused(BelugaNetworkAdaptationNativeFinalAdoptionEntry, any Error)
}
struct BelugaNetworkAdaptationFinalAdoptionCommit {
    let entry: BelugaNetworkAdaptationNativeFinalAdoptionEntry
    let replacement: BelugaNetworkAdaptationOwnerSnapshot
    fileprivate init(entry: BelugaNetworkAdaptationNativeFinalAdoptionEntry,
        replacement: BelugaNetworkAdaptationOwnerSnapshot) {
        self.entry = entry; self.replacement = replacement
    }
}

extension BelugaNetworkAdaptationOwnerBoundary {
    private typealias FinalRequest = beluga_core_adaptation_owner_completion_request_t
    private typealias FinalOutcome = beluga_core_adaptation_owner_completion_outcome_t
    private struct FinalRaw {
        let status: UInt32; let header: Header; let atoms: [BelugaNetworkAdaptationOwnerWriter.Atom]
        let metadata: Metadata; let outcome: FinalOutcome
        let edits: [Edit]; let coordinates: [Coordinate]
        let inputsUnchanged: Bool; let deniedOutputsUntouched: Bool
    }

    // This is separate from finishSuccess. Only a genuine separately unspent
    // noApply completion can reach this receipt factory; its constructor stays
    // sealed here. It does not read a sender/capturer or grant effect authority.
    func consumeFinalAdoptionOnly(_ completion: BelugaNetworkAdaptationNativeCompletion,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationFinalAdoptionReceipt {
        if busy { poisoned = true }
        let entry = try owner.networkAdaptationFinalOnlyCompletionEntry(completion, boundary: self)
        guard !busy else { throw BelugaNetworkAdaptationOwnerError.reentry }
        busy = true; poisoned = false
        defer { busy = false; poisoned = false }
        guard invocation != UInt64.max else { throw BelugaNetworkAdaptationOwnerError.invocationExhausted }
        invocation += 1
        let receipt = BelugaNetworkAdaptationFinalAdoptionReceipt(entry: entry,
            boundary: self, invocation: invocation)
        guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
        return receipt
    }

    private func finalRefusal(_ entry: BelugaNetworkAdaptationNativeFinalAdoptionEntry,
        on owner: isolated WorldwideScreenService, error: any Error) -> BelugaNetworkAdaptationFinalAdoptionResult {
        owner.networkAdaptationRetireFinalAdoption(entry)
        return .refused(entry, error)
    }

    func finalAdopt(_ receipt: BelugaNetworkAdaptationFinalAdoptionReceipt,
        on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationFinalAdoptionResult {
        if busy { poisoned = true }
        let entry = receipt.entry
        do {
            try receipt.use.spend(by: self)
        } catch {
            // Consume both non-Sendable records before returning issuer/replay
            // refusal. Disposal has no native resource/Owner effects or hop.
            return finalRefusal(entry, on: owner, error: error)
        }
        if busy {
            return finalRefusal(entry, on: owner, error: BelugaNetworkAdaptationOwnerError.reentry)
        }
        busy = true; poisoned = false
        defer { busy = false; poisoned = false }
        do {
            guard invocation != UInt64.max else { throw BelugaNetworkAdaptationOwnerError.invocationExhausted }
            invocation += 1
            let observation = try owner.networkAdaptationFinalAdoptionEntry(entry, boundary: self)
            guard !poisoned, Self.successLayoutIsExact else {
                throw BelugaNetworkAdaptationOwnerError.unsupportedLayout
            }
            let raw = Self.callActualFinalAdopt(observation, prepared: entry.seed.prepared,
                invocation: invocation)
            guard !poisoned, raw.inputsUnchanged else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
            guard raw.status == 1 else {
                guard raw.deniedOutputsUntouched else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            let replacement = try Self.importFinalAdopt(raw, observation: observation,
                prepared: entry.seed.prepared, invocation: invocation)
            let result: BelugaNetworkAdaptationFinalAdoptionResult
            let packet: BelugaNetworkAdaptationFinalAdoptionCommit?
            if let replacement {
                result = .adopted; packet = .init(entry: entry, replacement: replacement)
            } else { result = .superseded; packet = nil }
            let fresh = try owner.networkAdaptationFinalAdoptionRecapture(entry, boundary: self)
            guard !poisoned, Self.samePublicationSource(fresh.source, observation.source),
                  fresh.exactPeer == observation.exactPeer, fresh.generation == observation.generation else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            if let packet { owner.networkAdaptationFinalAdoptionCommit(packet) }
            return result // No fallible/refusal/retirement work after actual704 store.
        } catch { return finalRefusal(entry, on: owner, error: error) }
    }

    private static func importFinalAdopt(_ raw: FinalRaw,
        observation: BelugaNetworkAdaptationNativeFinalAdoptionObservation,
        prepared p: BelugaNetworkAdaptationGeneralPreparedValue, invocation: UInt64)
        throws -> BelugaNetworkAdaptationOwnerSnapshot? {
        let source = observation.source, o = raw.outcome, m = raw.metadata
        guard source.atoms.count == 179, source.times.count == 13, p.atoms.count == 222,
              p.policyTimes.count == 9, source.anchor == p.source.anchor,
              raw.header.abi == 1, raw.header.domain == 2, raw.header.phase == 2, raw.header.count == 179,
              raw.atoms.count == 179, raw.edits.count == 13, raw.coordinates.count == 13 else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        // Literal original final fence. The owned publication snapshot supplies
        // revision, but no later guard is evaluated as a new permission source.
        let isCurrent = observation.exactPeer && observation.generation == p.tail.generation
            && source.value.revision == p.tail.applyingRevision
        let expectedRoute: UInt32
        if !isCurrent { expectedRoute = 0 }
        else {
            switch p.tail.routeAction {
            case .retain: expectedRoute = 0
            case .clear: expectedRoute = 1
            case .copyIncoming: expectedRoute = 2
            }
        }
        guard o.abi == 1, o.operation == 704, o.invocation == invocation,
              o.disposition == (isCurrent ? 1 : 0), o.route == expectedRoute,
              o.fps_changed == 0, o.reserved == 0,
              m.abi == 1, m.operation == 704, m.scope == 2, m.read_count == 0,
              m.invocation == invocation,
              m.revision == (isCurrent ? source.value.revision &+ 1 : source.value.revision),
              m.peer_present == raw.atoms[3].present, m.peer == raw.atoms[3].low,
              m.bound == 0, m.route == expectedRoute, m.sample == 0, m.enabled == 0, m.lease == 0,
              UInt64(m.queue_fault) == raw.atoms[41].low, UInt64(m.rtt_fault) == raw.atoms[89].low else {
            throw BelugaNetworkAdaptationOwnerError.invalidResult
        }
        if isCurrent {
            guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(Array(raw.atoms.prefix(168)), Array(p.atoms.prefix(168))),
                  raw.atoms[168].kind == 1, raw.atoms[168].present == 1,
                  raw.atoms[168].high == 0, raw.atoms[168].low == m.revision,
                  BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(Array(raw.atoms.suffix(10)), Array(source.atoms.suffix(10))) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        } else {
            guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(raw.atoms, source.atoms) else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
        }
        let indices = [12,23,28,159,163,167,39,40,88]
        var times = source.times
        for i in 0..<13 {
            let e = raw.edits[i], c = raw.coordinates[i]
            if i >= 9 {
                // Unowned sidecars ZERO, not a clear of native Owner tail values.
                guard bytes(e) == bytes(Edit()), bytes(c) == bytes(Coordinate()) else {
                    throw BelugaNetworkAdaptationOwnerError.invalidResult
                }
                continue
            }
            let a = isCurrent ? p.atoms[indices[i]] : source.atoms[indices[i]]
            let action: UInt32 = !isCurrent ? 1 : (a.present == 1 ? 3 : 2)
            guard e.action == action, e.source == (action == 3 ? 2 : 0),
                  e.index == (action == 3 ? UInt32(i) : 0), e.ordinal == 0, e.high == 0, e.low == 0,
                  c.present == a.present, c.reserved == 0, c.high == a.high, c.low == a.low else {
                throw BelugaNetworkAdaptationOwnerError.invalidResult
            }
            // Native Instant custody from corresponding Prepared slot, not
            // coordinate reconstruction, even if values equal current times.
            if isCurrent { times[i] = p.policyTimes[i] }
        }
        guard isCurrent else { return nil }
        let route: WebRTCICERouteDiagnostics?
        switch p.tail.routeAction {
        case .retain: route = source.route
        case .clear: route = nil
        case .copyIncoming: route = p.report.incomingRoute // including genuine nil
        }
        // Corresponding genuine Prepared policy retains its producer/dependency
        // and Optional/Instant custody. This mechanical single-field route copy
        // is not policy replay, demand/RTT evaluation or scalar route recovery.
        var policy = p.policy
        try policy.networkAdaptationOwnerImportClocked(.init(atoms: raw.atoms,
            fields: [144], times: times, route: route))
        let v = source.value
        let replacement = try BelugaNetworkAdaptationOwnerSnapshot.capture(.init(policy: policy,
            revision: m.revision, fastStatisticsAvailable: v.fastStatisticsAvailable, lane: v.lane,
            evidenceTime: v.evidenceTime, minimumCollectionSequence: v.minimumCollectionSequence,
            applied: v.applied), retainingAnchor: source.anchor)
        guard BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(replacement.atoms, raw.atoms),
              replacement.times == times, replacement.anchor == source.anchor,
              replacement.route == route else { throw BelugaNetworkAdaptationOwnerError.invalidResult }
        return replacement
    }

    private static func callActualFinalAdopt(_ observation: BelugaNetworkAdaptationNativeFinalAdoptionObservation,
        prepared p: BelugaNetworkAdaptationGeneralPreparedValue, invocation: UInt64) -> FinalRaw {
        var q = FinalRequest(abi: 1, operation: 704, invocation: invocation,
            current_generation: observation.generation ?? 0, facts: observation.exactPeer ? 1 : 0, reserved: 0)
        var ih = Header(abi: 1, domain: 2, phase: 1, count: 179), ia = observation.source.atoms.map { $0 }
        var ph = Header(abi: 1, domain: 4, phase: 3, count: 222), pa = p.atoms.map { $0 }
        var h = Header(abi: 91, domain: 92, phase: 93, count: 94)
        var a = Array(repeating: BelugaNetworkAdaptationOwnerWriter.Atom(kind: 95, present: 96, high: -97, low: 98), count: 179)
        var m = Metadata(abi: 81, operation: 82, scope: 83, read_count: 84, invocation: 85,
            revision: 86, peer: 87, peer_present: 88, bound: 89, route: 90, sample: 91,
            enabled: 92, lease: 93, queue_fault: 94, rtt_fault: 95)
        var o = FinalOutcome(abi: 41, operation: 42, invocation: 43, disposition: 44, route: 45, fps_changed: 46, reserved: 47)
        var e = Array(repeating: Edit(action: 71, source: 72, index: 73, ordinal: 74, high: -75, low: 76), count: 13)
        var c = Array(repeating: Coordinate(present: 61, reserved: 62, high: -63, low: 64), count: 13)
        var unchanged = false, untouched = false
        // Eleven distinct owned ranges. This actual ABI has NO callback/context,
        // provider/frame/effect authority or pointer retained beyond the call.
        let status = withUnsafePointer(to: &q) { request in withUnsafePointer(to: &ih) { header in
            ia.withUnsafeMutableBufferPointer { input in withUnsafePointer(to: &ph) { preparedHeader in
                pa.withUnsafeMutableBufferPointer { preparedInput in withUnsafeMutablePointer(to: &h) { outHeader in
                    a.withUnsafeMutableBufferPointer { output in withUnsafeMutablePointer(to: &m) { metadata in
                        withUnsafeMutablePointer(to: &o) { outcome in e.withUnsafeMutableBufferPointer { edits in
                            c.withUnsafeMutableBufferPointer { coordinates in
                                let inputBase = input.baseAddress!, preparedBase = preparedInput.baseAddress!
                                let outputBase = output.baseAddress!, editBase = edits.baseAddress!, coordinateBase = coordinates.baseAddress!
                                func raw<T>(_ pointer: UnsafePointer<T>, _ count: Int) -> [UInt8] {
                                    Array(UnsafeRawBufferPointer(start: pointer, count: count * MemoryLayout<T>.stride))
                                }
                                func inputs() -> [[UInt8]] {
                                    [raw(request,1),raw(header,1),raw(UnsafePointer(inputBase),179),raw(preparedHeader,1),raw(UnsafePointer(preparedBase),222)]
                                }
                                func outputs() -> [[UInt8]] {
                                    [raw(UnsafePointer(outHeader),1),raw(UnsafePointer(outputBase),179),raw(UnsafePointer(metadata),1),
                                     raw(UnsafePointer(outcome),1),raw(UnsafePointer(editBase),13),raw(UnsafePointer(coordinateBase),13)]
                                }
                                let beforeInputs = inputs(), beforeOutputs = outputs()
                                let status = beluga_core_network_adaptation_owner_final_adopt(
                                    request,header,inputBase,179,preparedHeader,preparedBase,222,
                                    outHeader,outputBase,179,metadata,outcome,editBase,13,coordinateBase,13)
                                unchanged = inputs() == beforeInputs; untouched = outputs() == beforeOutputs
                                return status
                            }
                        } }
                    } }
                } }
            } }
        } }
        return .init(status: status, header: h, atoms: a, metadata: m, outcome: o,
            edits: e, coordinates: c, inputsUnchanged: unchanged, deniedOutputsUntouched: untouched)
    }
}

// SOURCE-ONLY append in SAME OwnerCodec file, outside historical exact slices.
// Readonly actual one-use state; no admission setter/receipt constructor exposed.
#if DEBUG
extension BelugaNetworkAdaptationPreparedUse {
    fileprivate var spentForFinalFixture: Bool { spent }
}
extension BelugaNetworkAdaptationOwnerBoundary {
    func finalAdoptionReceiptWasSpentForTesting(_ receipt: BelugaNetworkAdaptationFinalAdoptionReceipt) throws -> Bool {
        guard receipt.use.boundary === self else { throw BelugaNetworkAdaptationOwnerError.refused }
        return receipt.use.spentForFinalFixture
    }
}
#endif

// SOURCE-ONLY append in SAME OwnerCodec file under DEBUG. The receipt's entry
// field/use/constructor remain fileprivate; no broader access or mutation.
// Called synchronously ONCE by the isolated actor fixture; never returned from
// that actor or transferred in its Sendable observation.
#if DEBUG
extension BelugaNetworkAdaptationOwnerBoundary {
    func finalAdoptionEntryForTesting(_ receipt: BelugaNetworkAdaptationFinalAdoptionReceipt) throws -> BelugaNetworkAdaptationNativeFinalAdoptionEntry {
        guard receipt.use.boundary === self else { throw BelugaNetworkAdaptationOwnerError.refused }
        return receipt.entry // EXACT retained native entry; no copy/mint/claim/set.
    }
}
#endif
