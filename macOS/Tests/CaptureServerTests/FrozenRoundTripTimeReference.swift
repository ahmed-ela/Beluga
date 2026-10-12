import Foundation
import WebRTCTransport

/// Independent, test-only preimage of the Swift RTT reducer and its selective projections.
/// Frozen before reading the replacement Rust module or ABI. Never import the production
/// Rust adapter, invoke its helpers, or derive expected values from its results here.
/// Preimage: WorldwideScreenVideoAdaptationPolicy.swift SHA-256
/// 943b4aeb41c0a428b2ca5223145b1650189a2c2d963ce87b5d4d7af81e398f2c.
struct FrozenRoundTripTimeReference: Equatable {
    enum Disposition: Equatable {
        case legacy, provisionalHealthy, freshHealthy, freshInflated
        case retainedHealthy, retainedInflated, unavailable, expired, reseeded, reordered
    }

    enum Health: Equatable { case unknown, healthy, inflated }

    struct Evidence: Equatable {
        var hasFreshPressure: Bool
        var allowsUpgrade: Bool
        var permitsLegacyMissingValue: Bool

        static let unknown = Self(hasFreshPressure: false, allowsUpgrade: false,
                                  permitsLegacyMissingValue: false)
    }

    struct Fence: Equatable {
        var measurement: WebRTCRoundTripTimeMeasurement
        var current: Double?
    }

    struct CapacityResult: Equatable {
        var evidence: Evidence
        var validation: FrozenRoundTripTimeReference
        var primaryLeaseIsCurrent: Bool
        var awaitsOrdinaryRequalification: Bool
        var routeWasRejected: Bool
    }

    var peerGeneration: UInt64?
    var baseline: Double?
    var bootstrap: [Double] = []
    var disposition: Disposition = .unavailable
    var observationAge: Duration?
    var referenceIsProvisional = false
    var watermark: WebRTCRoundTripTimeMeasurement?
    var fence: Fence?
    var health: Health = .unknown
    var usesNativeEvidence = false
    var lastAdvancement: ContinuousClock.Instant?
    var lastMeasured: Double?
    var permitsInitialReference = true
    var distinctHealthyReferenceCount = 0

    /// The outer policy owns peer identity, request order, native timestamp admission, route
    /// identity, and probe lifetime. This reference models only the RTT effect after admission.
    @discardableResult
    mutating func bind(to generation: UInt64) -> Bool {
        guard peerGeneration != generation else { return false }
        peerGeneration = generation
        resetPath()
        watermark = nil
        fence = nil
        lastAdvancement = nil
        lastMeasured = nil
        observationAge = nil
        permitsInitialReference = true
        return true
    }

    mutating func resetPath() {
        baseline = nil
        bootstrap = []
        revokeHealth()
        permitsInitialReference = false
        referenceIsProvisional = false
        distinctHealthyReferenceCount = 0
    }

    mutating func invalidateObservation() {
        revokeHealth()
        permitsInitialReference = false
    }

    mutating func routeChanged(previousRouteWasAbsent: Bool) {
        let isInitialRoute = previousRouteWasAbsent && watermark == nil
            && permitsInitialReference
        resetPath()
        if isInitialRoute { permitsInitialReference = true }
    }

    mutating func hiddenReport(observation: WebRTCRoundTripTimeObservation?) {
        resetPath()
        if case let .measurement(measurement) = observation, valid(measurement) {
            watermark = measurement
        }
    }

    /// Cadence/geometry/tier resets do not modify any RTT-owned state.
    mutating func resetIncompleteWindowOrTier() {}

    mutating func age(at now: ContinuousClock.Instant) {
        observationAge = lastAdvancement.map { $0.duration(to: now) }
    }

    mutating func ageWithoutReport(peer generation: UInt64,
                                  at now: ContinuousClock.Instant) {
        if peerGeneration == generation { age(at: now) }
    }

    /// Unlike invalidation, the source's missing-order rejection does not revoke the initial
    /// reference privilege. It rejects metadata before consuming the watermark or scalar.
    mutating func rejectMissingStrictOrder(at now: ContinuousClock.Instant) {
        age(at: now)
        revokeHealth()
        usesNativeEvidence = true
    }

    mutating func rejectReorderedOrdinary(at now: ContinuousClock.Instant) {
        age(at: now)
        disposition = .reordered
    }

    /// Capacity-order rejection and native-timestamp rejection only age an existing lease.
    mutating func rejectOtherReportIdentity(at now: ContinuousClock.Instant) {
        age(at: now)
    }

    var allowsStableSuspendedResume: Bool {
        !usesNativeEvidence || (health == .healthy && observationAge.map {
            $0 >= .zero && $0 <= .seconds(4)
        } == true)
    }

    func leaseIsCurrent(at now: ContinuousClock.Instant) -> Bool {
        lastAdvancement.map {
            let elapsed = $0.duration(to: now)
            return elapsed >= .zero && elapsed <= .seconds(4)
        } ?? false
    }

    /// The service's strict boundary substitutes .unavailable for legacy nil before entry;
    /// scalar sanitization belongs to the original native caller in either lane.
    mutating func observeOrdinary(current rawCurrent: Double?,
                                 observation: WebRTCRoundTripTimeObservation?,
                                 at now: ContinuousClock.Instant) -> Evidence {
        // Ordinary update ages even legacy evidence before route/visibility/order admission.
        // The private consume helper ages native evidence again without changing the result.
        age(at: now)
        return consume(current: sanitize(rawCurrent), observation: observation, at: now)
    }

    /// The fast lane validates on a value copy, and projects only the exact permitted fields.
    /// Its primary age, advancement, scalar, bootstrap, positive reference, and health are never
    /// renewed by a positive fast observation. Probe/queue/BWE decisions remain outside RTT.
    mutating func observeCapacity(current rawCurrent: Double?,
                                 observation: WebRTCRoundTripTimeObservation?,
                                 routeMatches: Bool,
                                 permitsSparseRequalification: Bool,
                                 at now: ContinuousClock.Instant) -> CapacityResult {
        let lease = leaseIsCurrent(at: now)
        var validation = self
        let evidence = validation.consume(current: sanitize(rawCurrent),
                                          observation: observation ?? .unavailable,
                                          at: now)
        fence = validation.fence
        var routeRejected = false
        if !evidence.allowsUpgrade {
            revokeHealth()
            permitsInitialReference = false
            if !evidence.hasFreshPressure {
                watermark = validation.watermark
                disposition = validation.disposition
                if validation.baseline == nil {
                    baseline = nil
                    bootstrap = []
                    distinctHealthyReferenceCount = 0
                    referenceIsProvisional = false
                }
            }
        } else if !routeMatches {
            revokeHealth()
            permitsInitialReference = false
            watermark = validation.watermark
            routeRejected = true
        }
        let awaitsOrdinary = evidence.allowsUpgrade && routeMatches
            && permitsSparseRequalification && health == .unknown
            && disposition == .unavailable && validation.disposition == .freshHealthy
            && lease
        return CapacityResult(evidence: evidence, validation: validation,
                              primaryLeaseIsCurrent: lease,
                              awaitsOrdinaryRequalification: awaitsOrdinary,
                              routeWasRejected: routeRejected)
    }

    /// Called only after the original outer peer, active-origin, and advancing sequence guards.
    /// A failed native cap application retains observation identity, not health or budgets.
    mutating func retainAdmittedFence(from observed: Self) { fence = observed.fence }

    private func sanitize(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private mutating func revokeHealth() {
        health = .unknown
        disposition = .unavailable
    }

    private func valid(_ measurement: WebRTCRoundTripTimeMeasurement) -> Bool {
        let bytes = measurement.selectedCandidatePairFingerprint.utf8
        return bytes.count == 64 && bytes.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        } && measurement.totalRoundTripTimeSeconds.isFinite
            && measurement.totalRoundTripTimeSeconds >= 0
    }

    private mutating func consume(current: Double?,
                                  observation: WebRTCRoundTripTimeObservation?,
                                  at now: ContinuousClock.Instant) -> Evidence {
        usesNativeEvidence = observation != nil
        guard let observation else {
            disposition = .legacy
            let pressure = isInflated(current)
            if let current { updateBaseline(current) }
            return Evidence(hasFreshPressure: pressure,
                            allowsUpgrade: allowsUpgrade(current),
                            permitsLegacyMissingValue: current == nil)
        }

        age(at: now)
        guard case let .measurement(measurement) = observation, valid(measurement) else {
            if let fence {
                watermark = fence.measurement
                permitsInitialReference = false
            }
            revokeHealth()
            return .unknown
        }

        let previousFence = fence
        fence = Fence(measurement: measurement, current: current)
        if let previousFence {
            let replaced = measurement.selectedCandidatePairFingerprint
                != previousFence.measurement.selectedCandidatePairFingerprint
            let regressed = measurement.totalRoundTripTimeSeconds
                    < previousFence.measurement.totalRoundTripTimeSeconds
                || measurement.responsesReceived < previousFence.measurement.responsesReceived
            let contradictory = measurement == previousFence.measurement
                && current != previousFence.current
            if replaced || regressed || contradictory {
                watermark = measurement
                permitsInitialReference = false
                revokeHealth()
                disposition = contradictory ? .unavailable : .reseeded
                if replaced { clearReference() }
                return .unknown
            }
        }

        let previous = watermark
        let first = previous == nil && permitsInitialReference
        permitsInitialReference = false
        watermark = measurement
        if let previous {
            let replaced = measurement.selectedCandidatePairFingerprint
                != previous.selectedCandidatePairFingerprint
            let regressed = measurement.totalRoundTripTimeSeconds
                    < previous.totalRoundTripTimeSeconds
                || measurement.responsesReceived < previous.responsesReceived
            if replaced || regressed {
                revokeHealth()
                disposition = .reseeded
                if replaced { clearReference() }
                return .unknown
            }
        } else if !first {
            revokeHealth()
            disposition = .reseeded
            return .unknown
        }

        guard let current, measurement.totalRoundTripTimeSeconds >= current,
              observationAge.map({ $0 >= .zero }) ?? true else {
            revokeHealth()
            return .unknown
        }
        let advanced = previous.map {
            measurement.totalRoundTripTimeSeconds > $0.totalRoundTripTimeSeconds
                || measurement.responsesReceived > $0.responsesReceived
        } ?? first
        guard advanced else {
            guard current == lastMeasured else {
                revokeHealth()
                return .unknown
            }
            switch health {
            case .healthy:
                guard let observationAge, observationAge <= .seconds(4) else {
                    health = .unknown
                    disposition = .expired
                    return .unknown
                }
                disposition = .retainedHealthy
                return Evidence(hasFreshPressure: false, allowsUpgrade: true,
                                permitsLegacyMissingValue: false)
            case .inflated: disposition = .retainedInflated
            case .unknown: disposition = .unavailable
            }
            return .unknown
        }

        lastAdvancement = now
        lastMeasured = current
        observationAge = .zero
        if baseline == nil {
            baseline = current
            bootstrap = []
            distinctHealthyReferenceCount = 1
            referenceIsProvisional = true
        } else if !isInflated(current) {
            updateBaseline(current)
            distinctHealthyReferenceCount = min(3, distinctHealthyReferenceCount + 1)
            referenceIsProvisional = distinctHealthyReferenceCount < 3
        }
        let pressure = isInflated(current)
        health = pressure ? .inflated : .healthy
        disposition = pressure ? .freshInflated : (first ? .provisionalHealthy : .freshHealthy)
        return Evidence(hasFreshPressure: pressure, allowsUpgrade: !pressure,
                        permitsLegacyMissingValue: false)
    }

    private mutating func clearReference() {
        baseline = nil
        bootstrap = []
        distinctHealthyReferenceCount = 0
        referenceIsProvisional = false
    }

    private mutating func updateBaseline(_ current: Double) {
        guard let baseline else {
            bootstrap.append(current)
            guard bootstrap.count >= 3 else { return }
            self.baseline = bootstrap.sorted()[bootstrap.count / 2]
            bootstrap = []
            return
        }
        if current < baseline { self.baseline = max(current, baseline - 0.010) }
    }

    private func isInflated(_ current: Double?) -> Bool {
        guard let current, let baseline else { return false }
        return current > max(baseline * 1.5, baseline + 0.050)
    }

    private func allowsUpgrade(_ current: Double?) -> Bool {
        guard let current, let baseline else { return false }
        return current <= max(baseline * 1.5, baseline + 0.050)
    }
}
