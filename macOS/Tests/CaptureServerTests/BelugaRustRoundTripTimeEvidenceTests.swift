import Foundation
import XCTest
import BelugaCore
import WebRTCTransport
@testable import CaptureServer

final class BelugaRustRoundTripTimeEvidenceTests: XCTestCase {
    private typealias M = beluga_core_rtt_evidence_measurement_t
    private typealias S = beluga_core_rtt_evidence_state_t
    private typealias E = beluga_core_rtt_evidence_event_t
    private typealias O = beluga_core_rtt_evidence_result_t
    private typealias F = BelugaRustRoundTripTimeEvidence
    private typealias R = FrozenRoundTripTimeABIReference

    func testActualCFourLayoutsFiftyOffsetsAndArrayWidths() {
        let actual = checked(R.initial(), observation(current: 0.1, total: 1, responses: 1))
        XCTAssertEqual(actual.status, 1)
        XCTAssertEqual(MemoryLayout<M>.size, 80); XCTAssertEqual(MemoryLayout<M>.stride, 80)
        XCTAssertEqual(MemoryLayout<S>.size, 296); XCTAssertEqual(MemoryLayout<S>.stride, 296)
        XCTAssertEqual(MemoryLayout<E>.size, 128); XCTAssertEqual(MemoryLayout<E>.stride, 128)
        XCTAssertEqual(MemoryLayout<O>.size, 336); XCTAssertEqual(MemoryLayout<O>.stride, 336)
        XCTAssertEqual(MemoryLayout<M>.alignment, 8); XCTAssertEqual(MemoryLayout<S>.alignment, 8)
        XCTAssertEqual(MemoryLayout<E>.alignment, 8); XCTAssertEqual(MemoryLayout<O>.alignment, 8)
        let offsets: [(Int?, Int)] = [
            (MemoryLayout<M>.offset(of: \M.fingerprint_words), 0),
            (MemoryLayout<M>.offset(of: \M.total_bits), 64), (MemoryLayout<M>.offset(of: \M.responses), 72),
            (MemoryLayout<S>.offset(of: \S.abi_version), 0), (MemoryLayout<S>.offset(of: \S.reserved), 4),
            (MemoryLayout<S>.offset(of: \S.baseline_present), 8), (MemoryLayout<S>.offset(of: \S.bootstrap_count), 12),
            (MemoryLayout<S>.offset(of: \S.disposition), 16), (MemoryLayout<S>.offset(of: \S.health), 20),
            (MemoryLayout<S>.offset(of: \S.uses_native), 24), (MemoryLayout<S>.offset(of: \S.provisional), 28),
            (MemoryLayout<S>.offset(of: \S.permits_initial), 32), (MemoryLayout<S>.offset(of: \S.distinct_count), 36),
            (MemoryLayout<S>.offset(of: \S.last_measured_present), 40),
            (MemoryLayout<S>.offset(of: \S.advancement_present), 44), (MemoryLayout<S>.offset(of: \S.age_present), 48),
            (MemoryLayout<S>.offset(of: \S.watermark_present), 52), (MemoryLayout<S>.offset(of: \S.fence_present), 56),
            (MemoryLayout<S>.offset(of: \S.fence_current_present), 60), (MemoryLayout<S>.offset(of: \S.reserved2), 64),
            (MemoryLayout<S>.offset(of: \S.reserved3), 68), (MemoryLayout<S>.offset(of: \S.baseline_bits), 72),
            (MemoryLayout<S>.offset(of: \S.last_measured_bits), 80), (MemoryLayout<S>.offset(of: \S.bootstrap_bits), 88),
            (MemoryLayout<S>.offset(of: \S.age_seconds), 112), (MemoryLayout<S>.offset(of: \S.age_attoseconds), 120),
            (MemoryLayout<S>.offset(of: \S.watermark), 128), (MemoryLayout<S>.offset(of: \S.fence), 208),
            (MemoryLayout<S>.offset(of: \S.fence_current_bits), 288),
            (MemoryLayout<E>.offset(of: \E.opcode), 0), (MemoryLayout<E>.offset(of: \E.observation_kind), 4),
            (MemoryLayout<E>.offset(of: \E.current_present), 8), (MemoryLayout<E>.offset(of: \E.fingerprint_length), 12),
            (MemoryLayout<E>.offset(of: \E.route_changed), 16), (MemoryLayout<E>.offset(of: \E.reserved), 20),
            (MemoryLayout<E>.offset(of: \E.current_bits), 24), (MemoryLayout<E>.offset(of: \E.measurement), 32),
            (MemoryLayout<E>.offset(of: \E.age_seconds), 112), (MemoryLayout<E>.offset(of: \E.age_attoseconds), 120),
            (MemoryLayout<O>.offset(of: \O.abi_version), 0), (MemoryLayout<O>.offset(of: \O.status), 4),
            (MemoryLayout<O>.offset(of: \O.fresh_pressure), 8), (MemoryLayout<O>.offset(of: \O.allows_upgrade), 12),
            (MemoryLayout<O>.offset(of: \O.legacy_missing), 16), (MemoryLayout<O>.offset(of: \O.clock_action), 20),
            (MemoryLayout<O>.offset(of: \O.validation_disposition), 24),
            (MemoryLayout<O>.offset(of: \O.primary_lease_current), 28), (MemoryLayout<O>.offset(of: \O.reserved), 32),
            (MemoryLayout<O>.offset(of: \O.reserved2), 36), (MemoryLayout<O>.offset(of: \O.state), 40),
        ]
        XCTAssertEqual(offsets.count, 50)
        for (offset, expected) in offsets { XCTAssertEqual(offset, expected) }
        XCTAssertEqual(MemoryLayout.size(ofValue: M().fingerprint_words), 64)
        XCTAssertEqual(MemoryLayout.size(ofValue: S().bootstrap_bits), 24)
        XCTAssertTrue(F.layoutIsExact)
    }

    func testLegacyBootstrapMissingAndStrictUnavailableKeepOriginalDistinction() {
        var state = R.initial()
        for (index, value) in [0.3, 0.1, 0.2].enumerated() {
            let actual = checked(state, legacy(current: value))
            XCTAssertEqual(actual.state.bootstrap_count, index < 2 ? UInt32(index + 1) : 0)
            XCTAssertEqual(actual.allows_upgrade, index == 2 ? 1 : 0)
            XCTAssertEqual(actual.clock_action, 0)
            XCTAssertEqual(actual.state.uses_native, 0)
            state = actual.state
        }
        XCTAssertEqual(state.baseline_bits, Double(0.2).bitPattern, "Original sorted median, not last sample")
        let missing = checked(state, legacy(current: nil))
        XCTAssertEqual(missing.legacy_missing, 1); XCTAssertEqual(missing.allows_upgrade, 0)
        XCTAssertEqual(missing.state.disposition, 0)
        let strict = checked(state, unavailable(current: nil))
        XCTAssertEqual(strict.legacy_missing, 0); XCTAssertEqual(strict.allows_upgrade, 0)
        XCTAssertEqual(strict.state.disposition, 6); XCTAssertEqual(strict.state.uses_native, 1)
        let afterNative = healthy()
        let agedLegacy = checked(afterNative, legacy(current: nil, age: (2, 1)))
        XCTAssertEqual(agedLegacy.state.age_seconds, 2); XCTAssertEqual(agedLegacy.state.age_attoseconds, 1)
        XCTAssertEqual(agedLegacy.state.watermark.responses, afterNative.watermark.responses)
        XCTAssertEqual(agedLegacy.state.advancement_present, 1)
        XCTAssertEqual(agedLegacy.state.last_measured_bits, afterNative.last_measured_bits)
    }

    func testNativeDistinctReferenceLearningNeverLearnsDuplicatesOrInflation() {
        var state = checked(R.initial(), observation(current: 0.100, total: 1, responses: 1)).state
        XCTAssertEqual(state.baseline_bits, Double(0.100).bitPattern)
        XCTAssertEqual(state.distinct_count, 1); XCTAssertEqual(state.provisional, 1)
        XCTAssertEqual(state.disposition, 1)
        state = checked(state, observation(current: 0.020, total: 1.020, responses: 2, age: (1, 0))).state
        XCTAssertEqual(state.baseline_bits, Double(0.100 - 0.010).bitPattern)
        XCTAssertEqual(state.distinct_count, 2); XCTAssertEqual(state.provisional, 1)
        for _ in 0..<3 {
            let duplicate = checked(state, observation(current: 0.020, total: 1.020, responses: 2, age: (2, 0)))
            XCTAssertEqual(duplicate.state.baseline_bits, state.baseline_bits)
            XCTAssertEqual(duplicate.state.distinct_count, 2); XCTAssertEqual(duplicate.clock_action, 0)
            state = duplicate.state
        }
        state = checked(state, observation(current: 0.300, total: 1.320, responses: 3, age: (3, 0))).state
        XCTAssertEqual(state.distinct_count, 2); XCTAssertEqual(state.provisional, 1)
        state = checked(state, observation(current: 0.020, total: 1.340, responses: 4, age: (1, 0))).state
        XCTAssertEqual(state.baseline_bits, Double((0.100 - 0.010) - 0.010).bitPattern)
        XCTAssertEqual(state.distinct_count, 3); XCTAssertEqual(state.provisional, 0)
        XCTAssertEqual(state.bootstrap_count, 0)
    }

    func testInclusiveInflationAndFloatBoundariesPreservePreAndPostLearning() {
        for baseline in [0.005, 0.1, 1.0, Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude] {
            let before = healthy(current: baseline)
            let threshold = max(baseline * 1.5, baseline + 0.050)
            if threshold.isFinite {
                for current in [threshold.nextDown, threshold, threshold.nextUp] {
                    let actual = checked(before, observation(current: current,
                        total: max(2, current), responses: 2, age: (1, 0)))
                    XCTAssertEqual(actual.fresh_pressure, current > threshold ? 1 : 0)
                    XCTAssertEqual(actual.allows_upgrade, current <= threshold ? 1 : 0)
                    XCTAssertEqual(actual.state.health, current > threshold ? 2 : 1)
                }
            } else {
                let actual = checked(before, observation(current: baseline,
                    total: baseline, responses: 2, age: (1, 0)))
                XCTAssertEqual(actual.fresh_pressure, 0); XCTAssertEqual(actual.allows_upgrade, 1)
            }
        }
        var before = R.initial()
        before.baseline_present = 1; before.baseline_bits = Double(0.1).bitPattern
        let reduced = checked(before, legacy(current: 0.01))
        XCTAssertEqual(reduced.state.baseline_bits, Double(0.1 - 0.010).bitPattern)
        XCTAssertEqual(reduced.fresh_pressure, 0); XCTAssertEqual(reduced.allows_upgrade, 1)
        let inflated = checked(before, legacy(current: 0.2))
        XCTAssertEqual(inflated.fresh_pressure, 1); XCTAssertEqual(inflated.state.baseline_bits, before.baseline_bits)
    }

    func testFullCountersAndIndependentAdvancementRetainExactUInt64() {
        let values: [UInt64] = [0, 1, 9_007_199_254_740_991, 9_007_199_254_740_992,
            9_007_199_254_740_993, UInt64.max - 1, UInt64.max]
        for responses in values {
            let before = healthy(responses: responses)
            let totalOnly = checked(before, observation(current: 0.005, total: 1.005,
                responses: responses, age: (1, 0)))
            XCTAssertEqual(totalOnly.clock_action, 2)
            XCTAssertEqual(totalOnly.state.watermark.responses, responses)
            if responses != .max {
                let countOnly = checked(before, observation(current: 0.005, total: 1,
                    responses: responses + 1, age: (1, 0)))
                XCTAssertEqual(countOnly.clock_action, 2)
                XCTAssertEqual(countOnly.state.watermark.responses, responses + 1)
            }
            let duplicate = checked(before, observation(current: 0.005, total: 1,
                responses: responses, age: (1, 0)))
            XCTAssertEqual(duplicate.clock_action, 0); XCTAssertEqual(duplicate.state.disposition, 4)
        }
        let zero = checked(R.initial(), observation(current: 0, total: 0, responses: 0))
        XCTAssertEqual(zero.state.baseline_present, 0); XCTAssertEqual(zero.state.watermark_present, 1)
        let piggyback = checked(zero.state, observation(current: 0.005, total: 0.005, responses: 0))
        XCTAssertEqual(piggyback.clock_action, 2); XCTAssertEqual(piggyback.state.disposition, 2)
        XCTAssertEqual(piggyback.state.provisional, 1)
        var signedZero = observation(current: nil, total: -0.0, responses: .max)
        let seeded = checked(R.initial(), signedZero)
        signedZero.measurement.total_bits = Double(0.0).bitPattern
        let same = checked(seeded.state, signedZero)
        XCTAssertEqual(same.state.disposition, 6, "Numeric +0/-0 identity must not manufacture reseeding")
        XCTAssertEqual(same.state.watermark.total_bits, Double(0.0).bitPattern)
    }

    func testInvalidTelemetryAndExplicitFingerprintLengthAreUnknownNotABIRejection() {
        let before = healthy()
        let scalars: [Double?] = [nil, 0, -0.0, -1, .nan, .infinity, -.infinity, 2]
        for current in scalars {
            let event = observation(current: current, total: 1.005, responses: 2, age: (1, 0))
            let actual = checked(before, event)
            XCTAssertEqual(actual.status, 1); XCTAssertEqual(actual.fresh_pressure, 0)
            XCTAssertEqual(actual.allows_upgrade, 0); XCTAssertEqual(actual.state.health, 0)
            XCTAssertEqual(actual.state.watermark.responses, 2)
            let repaired = checked(actual.state, observation(current: 0.005, total: 1.005,
                responses: 2, age: (2, 0)))
            XCTAssertEqual(repaired.allows_upgrade, 0)
        }
        for total in [Double.nan, .infinity, -.infinity, -1] {
            let actual = checked(before, observation(current: 0.005, total: total,
                responses: 2, age: (1, 0)))
            XCTAssertEqual(actual.status, 1); XCTAssertEqual(actual.state.health, 0)
            XCTAssertEqual(actual.state.watermark.responses, before.fence.responses)
        }
        for pair in ["", "bad", String(repeating: "A", count: 64), String(repeating: "g", count: 64),
                     String(repeating: "a", count: 63), String(repeating: "a", count: 65),
                     String(repeating: "é", count: 32)] {
            let actual = checked(before, observation(current: 0.005, pair: pair,
                total: 1.005, responses: 2, age: (1, 0)))
            XCTAssertEqual(actual.status, 1); XCTAssertEqual(actual.allows_upgrade, 0)
            XCTAssertEqual(actual.state.watermark.responses, before.watermark.responses)
        }
        for length in [UInt32(0), 1, 63, 65, .max] {
            var event = observation(current: 0.005, total: 1.005, responses: 2, age: (1, 0))
            event.fingerprint_length = length
            let actual = checked(before, event)
            XCTAssertEqual(actual.status, 1); XCTAssertEqual(actual.allows_upgrade, 0)
        }
    }

    func testPairABARegressionAndScalarContradictionConsumeIdentityOnce() {
        let before = healthy()
        let pairB = String(repeating: "b", count: 64)
        let replacement = checked(before, observation(current: 0.060, pair: pairB,
            total: 2, responses: 20, age: (1, 0)))
        XCTAssertEqual(replacement.state.disposition, 8); XCTAssertEqual(replacement.state.baseline_present, 0)
        let aba = checked(replacement.state, observation(current: 0.005,
            total: 1, responses: 1, age: (2, 0)))
        XCTAssertEqual(aba.state.disposition, 8); XCTAssertEqual(aba.allows_upgrade, 0)
        let repeated = checked(aba.state, observation(current: 0.005,
            total: 1, responses: 1, age: (3, 0)))
        XCTAssertEqual(repeated.state.disposition, 6)
        let newPing = checked(repeated.state, observation(current: 0.005,
            total: 1.005, responses: 2, age: (4, 0)))
        XCTAssertEqual(newPing.clock_action, 2); XCTAssertEqual(newPing.allows_upgrade, 1)
        for (total, responses) in [(0.5, UInt64(2)), (2, UInt64(0))] {
            let regressed = checked(before, observation(current: 0.060,
                total: total, responses: responses, age: (1, 0)))
            XCTAssertEqual(regressed.state.disposition, 8)
            XCTAssertEqual(regressed.state.baseline_bits, before.baseline_bits)
            XCTAssertEqual(regressed.fresh_pressure, 0)
        }
        let contradiction = checked(before, observation(current: 0.060,
            total: 1, responses: 1, age: (1, 0)))
        XCTAssertEqual(contradiction.state.disposition, 6); XCTAssertEqual(contradiction.clock_action, 0)
        XCTAssertEqual(contradiction.state.fence_current_bits, Double(0.060).bitPattern)
        let restored = checked(contradiction.state, observation(current: 0.005,
            total: 1, responses: 1, age: (2, 0)))
        XCTAssertEqual(restored.allows_upgrade, 0)
    }

    func testSignedExactAgeBoundariesAndDuplicateLeasesNeverRenew() {
        let before = healthy()
        let ages: [(Int64, Int64, Bool)] = [(-1, 0, false), (0, -1, false), (0, 0, true),
            (3, 999_999_999_999_999_999, true), (4, 0, true), (4, 1, false), (5, 0, false)]
        for (seconds, attoseconds, current) in ages {
            let actual = checked(before, observation(current: 0.005, total: 1,
                responses: 1, age: (seconds, attoseconds)))
            XCTAssertEqual(actual.primary_lease_current, current ? 1 : 0)
            XCTAssertEqual(actual.allows_upgrade, current ? 1 : 0)
            XCTAssertEqual(actual.clock_action, 0)
            XCTAssertEqual(actual.state.age_seconds, seconds)
            XCTAssertEqual(actual.state.age_attoseconds, attoseconds)
            let query = checked(before, pure(12, age: (seconds, attoseconds)))
            XCTAssertEqual(query.primary_lease_current, current ? 1 : 0)
            XCTAssertEqual(bytes(query.state), bytes(before))
        }
        for seconds in [Int64.min, Int64.max] {
            let query = checked(before, pure(12, age: (seconds, 0)))
            XCTAssertEqual(query.primary_lease_current, 0)
            let aged = checked(before, pure(10, age: (seconds, 0)))
            XCTAssertEqual(aged.state.age_seconds, seconds)
            XCTAssertEqual(aged.clock_action, 0)
        }
        let regression = checked(before, observation(current: 0.005,
            total: 1.005, responses: 2, age: (0, -1)))
        XCTAssertEqual(regression.state.watermark.responses, 2)
        XCTAssertEqual(regression.clock_action, 0); XCTAssertEqual(regression.allows_upgrade, 0)
        let unavailableThenSame = checked(checked(before, unavailable(age: (1, 0))).state,
            observation(current: 0.005, total: 1, responses: 1, age: (2, 0)))
        XCTAssertEqual(unavailableThenSame.allows_upgrade, 0)
        let inflated = checked(before, observation(current: 0.060,
            total: 1.060, responses: 2, age: (1, 0))).state
        let retained = checked(inflated, observation(current: 0.060,
            total: 1.060, responses: 2, age: (5, 0)))
        XCTAssertEqual(retained.state.disposition, 5); XCTAssertEqual(retained.fresh_pressure, 0)
    }

    func testLifecycleAndRejectedIdentityOperationsPreserveDistinctOriginalState() {
        var before = healthy()
        before.age_seconds = 2; before.age_attoseconds = 1
        for op in UInt32(2)...12 {
            let event: E
            switch op {
            case 6: event = observation(op: 6, current: nil, pair: String(repeating: "b", count: 64), total: 2, responses: 20)
            case 10, 12: event = pure(op, age: (3, 1))
            case 11: event = unavailable(op: 11)
            default: event = pure(op)
            }
            let actual = checked(before, event)
            XCTAssertEqual(actual.status, 1)
            XCTAssertEqual(actual.fresh_pressure, 0); XCTAssertEqual(actual.allows_upgrade, 0)
            XCTAssertEqual(actual.legacy_missing, 0)
            XCTAssertEqual(actual.validation_disposition, actual.state.disposition)
            if op != 5 {
                XCTAssertEqual(actual.state.advancement_present, before.advancement_present)
                XCTAssertEqual(actual.state.last_measured_bits, before.last_measured_bits)
                if op != 10 { XCTAssertEqual(actual.state.age_attoseconds, before.age_attoseconds) }
            }
            if [UInt32(4), 5, 6].contains(op) {
                XCTAssertEqual(actual.state.baseline_present, 0); XCTAssertEqual(actual.state.bootstrap_count, 0)
                XCTAssertEqual(actual.state.distinct_count, 0); XCTAssertEqual(actual.state.provisional, 0)
            }
            if op == 5 {
                XCTAssertEqual(actual.clock_action, 1); XCTAssertEqual(actual.state.age_present, 0)
                XCTAssertEqual(actual.state.watermark_present, 0); XCTAssertEqual(actual.state.fence_present, 0)
                XCTAssertEqual(actual.state.permits_initial, 1); XCTAssertEqual(actual.state.uses_native, 1)
            }
            if op == 4 || op == 6 {
                XCTAssertEqual(actual.state.permits_initial, 0)
                XCTAssertEqual(bytes(actual.state.fence), bytes(before.fence))
            }
            if op == 2 { XCTAssertEqual(actual.state.permits_initial, before.permits_initial) }
        }
        let initial = R.initial()
        XCTAssertEqual(checked(initial, pure(9)).state.permits_initial, 1)
        XCTAssertEqual(checked(initial, pure(3)).state.permits_initial, 0)
        var mixed = R.initial()
        mixed.age_present = 1; mixed.age_seconds = 1
        mixed.health = 1; mixed.provisional = 1; mixed.distinct_count = 3
        XCTAssertEqual(checked(mixed, pure(2)).status, 1,
                       "Do not invent semantic relations for valid legacy/native mixtures")
    }

    func testFastPositiveAndAdmittedFailedApplyCopyOnlyFenceWithoutRenewal() {
        var before = healthy(current: 0.100)
        before.age_seconds = 2; before.age_attoseconds = 1
        let fresh = observation(op: 1, current: 0.020, total: 1.020,
            responses: 2, age: (3, 0))
        let actual = checked(before, fresh)
        XCTAssertEqual(actual.allows_upgrade, 1); XCTAssertEqual(actual.clock_action, 0)
        XCTAssertEqual(actual.validation_disposition, 2)
        var expected = before
        expected.fence = fresh.measurement
        expected.fence_current_bits = fresh.current_bits
        XCTAssertEqual(bytes(actual.state), bytes(expected), "Fast success changes exactly the fence")
        let copied = checked(before, observation(op: 11, current: 0.020, total: 1.020, responses: 2))
        XCTAssertEqual(bytes(copied.state), bytes(expected), "Failed native apply retains no positive state")
        let regressedOrdinary = checked(copied.state,
            observation(current: 0.100, total: 1, responses: 1, age: (3, 0)))
        XCTAssertEqual(regressedOrdinary.state.disposition, 8)
        XCTAssertEqual(regressedOrdinary.allows_upgrade, 0)
        let clear = checked(before, unavailable(op: 11))
        XCTAssertEqual(clear.state.fence_present, 0); XCTAssertEqual(clear.state.fence_current_present, 0)
        XCTAssertEqual(bytes(clear.state.watermark), bytes(before.watermark))
        XCTAssertEqual(clear.state.age_seconds, before.age_seconds)
    }

    func testFastNegativeTombstonesPoisonButFreshPressureRemainsForOrdinaryOnce() {
        let before = healthy()
        let spike = observation(op: 1, current: 0.060, total: 1.060, responses: 2, age: (1, 0))
        let fast = checked(before, spike)
        XCTAssertEqual(fast.fresh_pressure, 1); XCTAssertEqual(fast.clock_action, 0)
        XCTAssertEqual(fast.state.health, 0); XCTAssertEqual(fast.state.disposition, 6)
        XCTAssertEqual(bytes(fast.state.watermark), bytes(before.watermark))
        XCTAssertEqual(fast.state.baseline_bits, before.baseline_bits)
        var ordinary = spike; ordinary.opcode = 0
        let consumed = checked(fast.state, ordinary)
        XCTAssertEqual(consumed.fresh_pressure, 1); XCTAssertEqual(consumed.clock_action, 2)
        ordinary.age_seconds = 1
        let repeated = checked(consumed.state, ordinary)
        XCTAssertEqual(repeated.fresh_pressure, 0); XCTAssertEqual(repeated.state.disposition, 5)
        let pairChanged = checked(before, observation(op: 1, current: 0.005,
            pair: String(repeating: "b", count: 64), total: 2, responses: 2, age: (1, 0)))
        XCTAssertEqual(pairChanged.state.disposition, 8); XCTAssertEqual(pairChanged.state.baseline_present, 0)
        XCTAssertEqual(pairChanged.state.watermark.responses, 2)
        let poisoned = checked(pairChanged.state,
            observation(current: 0.005, total: 1, responses: 1, age: (2, 0)))
        XCTAssertEqual(poisoned.allows_upgrade, 0)
        let malformed = checked(before, observation(op: 1, current: 0.005,
            pair: "bad", total: 2, responses: 2, age: (1, 0)))
        XCTAssertEqual(malformed.state.health, 0); XCTAssertEqual(malformed.state.baseline_bits, before.baseline_bits)
        let missing = checked(before, legacy(op: 1, current: 0.005, age: (1, 0)))
        XCTAssertEqual(missing.allows_upgrade, 0); XCTAssertEqual(missing.legacy_missing, 0)
    }

    func testFastRouteAndPrimaryLeaseAreEvaluatedBeforeCloneAdvancement() {
        let before = healthy()
        var changed = observation(op: 1, current: 0.005, total: 1.005, responses: 2, age: (1, 0))
        changed.route_changed = 1
        let actual = checked(before, changed)
        XCTAssertEqual(actual.allows_upgrade, 1, "Clone evidence remains separate from route rejection")
        XCTAssertEqual(actual.state.health, 0); XCTAssertEqual(actual.state.permits_initial, 0)
        XCTAssertEqual(actual.state.watermark.responses, 2)
        XCTAssertEqual(actual.state.baseline_bits, before.baseline_bits)
        XCTAssertEqual(actual.clock_action, 0)
        let expiredFast = checked(before, observation(op: 1, current: 0.005,
            total: 1.005, responses: 2, age: (4, 1)))
        XCTAssertEqual(expiredFast.allows_upgrade, 1); XCTAssertEqual(expiredFast.primary_lease_current, 0)
        XCTAssertEqual(expiredFast.clock_action, 0)
        XCTAssertEqual(expiredFast.state.age_seconds, before.age_seconds)
        let freshOrdinary = checked(before, observation(current: 0.005,
            total: 1.005, responses: 2, age: (4, 1)))
        XCTAssertEqual(freshOrdinary.clock_action, 2); XCTAssertEqual(freshOrdinary.primary_lease_current, 0)
        var sparse = before; sparse.health = 0; sparse.disposition = 6
        let bridge = checked(sparse, observation(op: 1, current: 0.005,
            total: 1.005, responses: 2, age: (1, 0)))
        XCTAssertEqual(bridge.validation_disposition, 2); XCTAssertEqual(bridge.primary_lease_current, 1)
        XCTAssertEqual(bridge.state.health, 0); XCTAssertEqual(bridge.state.disposition, 6)
    }

    func testInvalidABIStateAndEventRejectWithExactBeforeStateAndZeroAuthority() {
        let before = healthy()
        let event = observation(current: 0.005, total: 1.005, responses: 2, age: (1, 0))
        let invalidStates: [(String, (inout S) -> Void)] = [
            ("abi", { $0.abi_version = 2 }), ("reserved", { $0.reserved = 1 }),
            ("reserved2", { $0.reserved2 = 1 }), ("reserved3", { $0.reserved3 = 1 }),
            ("baseline flag", { $0.baseline_present = 2 }), ("bootstrap count", { $0.bootstrap_count = 3 }),
            ("disposition", { $0.disposition = 10 }), ("health", { $0.health = 3 }),
            ("uses native", { $0.uses_native = 2 }), ("provisional", { $0.provisional = 2 }),
            ("initial", { $0.permits_initial = 2 }), ("distinct", { $0.distinct_count = 4 }),
            ("scalar flag", { $0.last_measured_present = 2 }), ("advance flag", { $0.advancement_present = 2 }),
            ("age flag", { $0.age_present = 2 }), ("watermark flag", { $0.watermark_present = 2 }),
            ("fence flag", { $0.fence_present = 2 }), ("fence scalar flag", { $0.fence_current_present = 2 }),
            ("baseline NaN", { $0.baseline_bits = Double.nan.bitPattern }),
            ("absent baseline payload", { $0.baseline_present = 0 }),
            ("last scalar zero", { $0.last_measured_bits = 0 }),
            ("unused bootstrap", { $0.bootstrap_bits.2 = 1 }),
            ("bootstrap invalid", { $0.bootstrap_count = 1; $0.bootstrap_bits.0 = Double.infinity.bitPattern }),
            ("age magnitude", { $0.age_attoseconds = 1_000_000_000_000_000_000 }),
            ("age opposite signs", { $0.age_seconds = 1; $0.age_attoseconds = -1 }),
            ("absent age", { $0.age_present = 0; $0.age_seconds = 1 }),
            ("absent watermark", { $0.watermark_present = 0 }),
            ("bad watermark", { $0.watermark.fingerprint_words.7 = 0 }),
            ("bad total", { $0.fence.total_bits = Double.nan.bitPattern }),
            ("absent fence", { $0.fence_present = 0 }),
            ("absent fence scalar", { $0.fence_current_present = 0 }),
            ("fence scalar zero", { $0.fence_current_bits = 0 }),
        ]
        for (name, mutate) in invalidStates {
            var changed = before; mutate(&changed)
            assertRejected(checked(changed, event), before: changed, name: name)
        }
        let invalidEvents: [(String, (inout E) -> Void)] = [
            ("opcode", { $0.opcode = 13 }), ("observation tag", { $0.observation_kind = 3 }),
            ("current tag", { $0.current_present = 2 }), ("route tag", { $0.route_changed = 2 }),
            ("route ordinary", { $0.route_changed = 1 }), ("reserved", { $0.reserved = 1 }),
            ("absent current", { $0.current_present = 0 }),
            ("kind1 measurement", { $0.observation_kind = 1 }),
            ("age magnitude", { $0.age_attoseconds = -1_000_000_000_000_000_000 }),
            ("opposite signs", { $0.age_seconds = -1; $0.age_attoseconds = 1 }),
            ("pure observation", { $0.opcode = 2 }),
        ]
        for (name, mutate) in invalidEvents {
            var changed = event; mutate(&changed)
            assertRejected(checked(before, changed), before: before, name: name)
        }
        for op in UInt32(2)...12 where ![UInt32(10), 12].contains(op) {
            var changed = pure(op, age: (1, 0))
            if op == 6 || op == 11 { changed.observation_kind = 1 }
            assertRejected(checked(before, changed), before: before, name: "unused age \(op)")
        }
        assertRejected(checked(R.initial(), pure(12, age: (0, 1))), before: R.initial(), name: "no clock")
        let malformedFence = observation(op: 11, current: 0.005, pair: "bad", total: 1, responses: 1)
        assertRejected(checked(before, malformedFence), before: before, name: "typed fence invalid")
        assertRejected(checked(before, unavailable(op: 11, current: 0.005)), before: before, name: "clear fence current")
    }

    func testEveryCopiedResultWordIsDeniedAndFacadeFaultIsSticky() {
        // Insert within testEveryCopiedResultWordIsDeniedAndFacadeFaultIsSticky.
        // Public update APIs reproduce the existing confirmedProbeFixture sequence;
        // no private policy state or manufactured qualification is installed.
        struct ConfirmedProbeFaultFixture {
            var policy: WorldwideScreenVideoAdaptationPolicy
            var now = ContinuousClock.now
            var milliseconds = 0
            var sequence: UInt64 = 0
            var packets: UInt64 = 0
            var delay = 0.0
            var totalRTT = 1.0
            var responses: UInt64 = 10
            let route = WebRTCICERouteDiagnostics(kind: .direct)

            var observation: WebRTCRoundTripTimeObservation {
                .measurement(.init(selectedCandidatePairFingerprint: String(repeating: "a", count: 64),
                    totalRoundTripTimeSeconds: totalRTT, responsesReceived: responses))
            }
            var timestamp: Double { 1_000_000 + Double(milliseconds) * 1_000 }

            init(producer: @escaping BelugaRustRoundTripTimeEvidence.Producer, floorOrigin: Bool) {
                policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 50_000_000,
                    baseFramesPerSecond: 60, roundTripTimeProducer: producer)
                if !floorOrigin {
                    _ = normal(100_000, after: 0)
                    XCTAssertEqual(policy.currentTier, .survival)
                    _ = normal(100_000)
                    XCTAssertEqual(policy.currentTier, .audioPriority)
                    _ = normal(486_001)
                    XCTAssertEqual(policy.applicationLimitedProbeOriginTier, .audioPriority)
                }
                policy.beginFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 1)
                policy.activateFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 1)
                if floorOrigin {
                    _ = normal(100_000, after: 0)
                    for (bandwidth, queueDelay) in [(100_000.0, 0.001), (251_000, 0.001),
                        (262_000, 0.492), (276_000, 0.943), (292_000, 0.470),
                        (304_000, 0.001), (331_000, 0.001)] {
                        advanceRTT()
                        _ = normal(bandwidth, queueDelay: queueDelay)
                    }
                    XCTAssertTrue(policy.floorRecoveryProbeIsActive)
                    XCTAssertTrue(policy.floorRecoveryAttemptConsumed)
                } else {
                    _ = normal(950_000)
                    _ = normal(950_000)
                    XCTAssertEqual(policy.currentTier, .survival)
                    for _ in 0..<3 where policy.applicationLimitedProbeOriginTier == nil {
                        advanceRTT()
                        _ = normal(900_000)
                    }
                    XCTAssertEqual(policy.applicationLimitedProbeOriginTier, .survival)
                }
                _ = fast(floorOrigin ? 600_000 : 1_700_000)
                advanceRTT()
                _ = normal(floorOrigin ? 1_179_360 : 2_111_466)
                advanceRTT()
                _ = normal(floorOrigin ? 2_111_466 : 4_222_932)
                XCTAssertEqual(policy.applicationLimitedProbeConfirmedTier, floorOrigin ? .survival : .critical)
                XCTAssertEqual(policy.currentTier, floorOrigin ? .survival : .critical)
                XCTAssertEqual(policy.floorRecoveryProbeIsActive, floorOrigin)
                XCTAssertFalse(policy.hasNativeRoundTripTimeFault)
            }

            mutating func advanceRTT() { totalRTT += 0.005; responses += 1 }

            mutating func prepare(after: Int, queueDelay: Double) {
                milliseconds += after
                now = now.advanced(by: .milliseconds(after))
                sequence += 1; packets += 100; delay += queueDelay * 100
            }

            mutating func normal(_ bandwidth: Double, after: Int = 500, queueDelay: Double = 0.001)
                -> WorldwideScreenVideoEncodingRecommendation? {
                prepare(after: after, queueDelay: queueDelay)
                return policy.update(peerGeneration: 1, isCaptureActive: true,
                    availableOutgoingBitrateBps: bandwidth, currentRoundTripTimeSeconds: 0.005,
                    roundTripTimeObservation: observation, collectionSequence: sequence,
                    requireRoundTripTimeObservation: true, selectedRoute: route,
                    outboundVideoPacketsSent: packets, outboundVideoTotalPacketSendDelaySeconds: delay,
                    nativeReportTimestampMicroseconds: timestamp, observedAt: now)
            }

            mutating func fast(_ bandwidth: Double) -> WorldwideScreenVideoEncodingRecommendation? {
                prepare(after: 200, queueDelay: 0.001)
                return policy.updateCapacityProbe(peerGeneration: 1, isCaptureActive: true,
                    availableOutgoingBitrateBps: bandwidth, currentRoundTripTimeSeconds: 0.005,
                    roundTripTimeObservation: observation, collectionSequence: sequence,
                    nativeReportTimestampMicroseconds: timestamp, selectedRoute: route,
                    outboundVideoPacketsSent: packets, outboundVideoTotalPacketSendDelaySeconds: delay,
                    observedAt: now)
            }
        }

        for opcode in [UInt32(10), 8, 9] {
            for floorOrigin in [false, true] {
                let producer: BelugaRustRoundTripTimeEvidence.Producer = { state, event in
                    var actual = beluga_core_rtt_evidence_step(state, event)
                    // op10 setup ages remain below five seconds. Only the real expired
                    // timeout is forged; op8/op9 never occur in the admitted fixture.
                    if event.opcode == opcode && (opcode != 10 || event.age_seconds >= 5) {
                        actual.primary_lease_current ^= 1
                    }
                    return actual
                }
                var fixture = ConfirmedProbeFaultFixture(producer: producer, floorOrigin: floorOrigin)
                guard let origin = fixture.policy.applicationLimitedProbeOriginTier,
                      let confirmed = fixture.policy.applicationLimitedProbeConfirmedTier,
                      let deadline = fixture.policy.applicationLimitedProbeDeadline else {
                    XCTFail("The public report sequence must retain a confirmed active probe")
                    continue
                }
                XCTAssertLessThan(confirmed.rawValue, origin.rawValue)
                XCTAssertNotNil(fixture.policy.applicationLimitedProbeBestQualifiedTier)
                XCTAssertGreaterThan(fixture.policy.applicationLimitedProbeMaximumTotalRTPBitrateBps ?? 0,
                    fixture.policy.recommendation(for: origin).maximumTotalRTPBitrateBps)
                let pristine = fixture.policy
                let changed: WorldwideScreenVideoEncodingRecommendation?
                if opcode == 10 {
                    fixture.now = deadline.advanced(by: .seconds(5))
                    changed = fixture.policy.expireApplicationLimitedProbeWithoutReport(peerGeneration: 1,
                        isCaptureActive: true, observedAt: fixture.now)
                } else {
                    fixture.now = fixture.now.advanced(by: .milliseconds(500))
                    fixture.milliseconds += 500
                    changed = fixture.policy.update(peerGeneration: 1, isCaptureActive: true,
                        availableOutgoingBitrateBps: 50_000_000, currentRoundTripTimeSeconds: 0.005,
                        roundTripTimeObservation: fixture.observation,
                        collectionSequence: opcode == 8 ? fixture.sequence : nil,
                        requireRoundTripTimeObservation: true, selectedRoute: fixture.route,
                        outboundVideoPacketsSent: fixture.packets,
                        outboundVideoTotalPacketSendDelaySeconds: fixture.delay,
                        nativeReportTimestampMicroseconds: fixture.timestamp,
                        observedAt: fixture.now)
                }
                XCTAssertTrue(fixture.policy.hasNativeRoundTripTimeFault, "opcode \(opcode)")
                XCTAssertEqual(changed, fixture.policy.currentRecommendation,
                    "A rejected native result must apply restrictive retirement, never confirmed geometry")
                XCTAssertEqual(fixture.policy.currentTier, origin)
                XCTAssertEqual(fixture.policy.currentRecommendation, fixture.policy.recommendation(for: origin))
                XCTAssertNil(fixture.policy.applicationLimitedProbeOriginTier)
                XCTAssertNil(fixture.policy.applicationLimitedProbeConfirmedTier)
                XCTAssertNil(fixture.policy.applicationLimitedProbeBestQualifiedTier)
                XCTAssertNil(fixture.policy.applicationLimitedProbeMaximumTotalRTPBitrateBps)
                XCTAssertNil(fixture.policy.applicationLimitedProbeDeadline)
                XCTAssertEqual(fixture.policy.applicationLimitedProbeHealthySampleCount, 0)
                XCTAssertEqual(fixture.policy.applicationLimitedProbeGraceSamplesRemaining, 0)
                XCTAssertNil(fixture.policy.promotionCapacityContinuity)
                XCTAssertFalse(fixture.policy.floorRecoveryProbeIsActive)
                XCTAssertFalse(fixture.policy.startupSpatialModeIsActive)
                XCTAssertEqual(fixture.policy.applicationLimitedProbeFailureCount, pristine.applicationLimitedProbeFailureCount,
                    "Native denial is not fabricated network congestion")
                XCTAssertEqual(fixture.policy.applicationLimitedProbeCooldownSamplesRemaining,
                    pristine.applicationLimitedProbeCooldownSamplesRemaining)
                if floorOrigin {
                    XCTAssertTrue(fixture.policy.floorRecoveryAttemptConsumed)
                    XCTAssertTrue(fixture.policy.floorRecoveryProbeWasCancelled)
                }
                let retired = fixture.policy
                XCTAssertNil(fixture.policy.expireApplicationLimitedProbeWithoutReport(peerGeneration: 1,
                    isCaptureActive: true, observedAt: fixture.now.advanced(by: .seconds(1))))
                XCTAssertEqual(fixture.policy, retired, "A retired fault must not emit the same sender change repeatedly")

                // Native application may await. Import only a terminal same-peer denial
                // into the prior applied value, without copying a proposal's clocks/identity.
                var samePeer = pristine
                let priorAge = samePeer.roundTripTimeObservationAge
                samePeer.retainRoundTripTimeFault(from: fixture.policy)
                XCTAssertTrue(samePeer.hasNativeRoundTripTimeFault)
                XCTAssertEqual(samePeer.currentTier, origin)
                XCTAssertEqual(samePeer.currentRecommendation, fixture.policy.currentRecommendation)
                XCTAssertNil(samePeer.applicationLimitedProbeOriginTier)
                XCTAssertNil(samePeer.applicationLimitedProbeMaximumTotalRTPBitrateBps)
                XCTAssertNil(samePeer.promotionCapacityContinuity)
                XCTAssertEqual(samePeer.roundTripTimeObservationAge, priorAge)
                XCTAssertEqual(samePeer.lastConsumedCollectionSequence, pristine.lastConsumedCollectionSequence)
                XCTAssertEqual(samePeer.selectedRoute, pristine.selectedRoute)
                var foreignPeer = pristine
                _ = foreignPeer.bind(toPeerGeneration: 2)
                let foreignBefore = foreignPeer
                foreignPeer.retainRoundTripTimeFault(from: fixture.policy)
                XCTAssertFalse(foreignPeer.hasNativeRoundTripTimeFault)
                XCTAssertEqual(foreignPeer, foreignBefore, "A predecessor's denial cannot fault a successor peer")

                // Positive ordinary/fast reports and another Show cannot re-arm an owner
                // whose native verifier has rejected a result.
                fixture.policy.beginFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 2)
                fixture.policy.activateFloorRecoveryVisibility(peerGeneration: 1, showEpoch: 2)
                XCTAssertFalse(fixture.policy.startupSpatialModeIsActive)
                for _ in 0..<3 {
                    fixture.advanceRTT()
                    XCTAssertNil(fixture.normal(50_000_000))
                    XCTAssertNil(fixture.fast(50_000_000))
                    XCTAssertTrue(fixture.policy.hasNativeRoundTripTimeFault)
                    XCTAssertEqual(fixture.policy.currentTier, origin)
                    XCTAssertNil(fixture.policy.applicationLimitedProbeOriginTier)
                    XCTAssertNil(fixture.policy.applicationLimitedProbeMaximumTotalRTPBitrateBps)
                    XCTAssertNil(fixture.policy.promotionCapacityContinuity)
                    XCTAssertFalse(fixture.policy.startupSpatialModeIsActive)
                }
            }
        }
        for published in [false, true] {
            var queryOwner = F(producer: { state, event in
                var result = beluga_core_rtt_evidence_step(state, event)
                if event.opcode == 12 { result.primary_lease_current ^= 1 }
                return result
            })
            let start = ContinuousClock.now
            _ = queryOwner.observe(current: 0.005, observation: native(total: 1, responses: 1), at: start)
            let primed = queryOwner
            if published { XCTAssertFalse(queryOwner.publishedLeaseIsCurrent) }
            else { XCTAssertFalse(queryOwner.primaryLeaseIsCurrent(at: start)) }
            XCTAssertTrue(queryOwner.hasNativeFault, "Rejected queries must fault the owner, not a disposable copy")
            XCTAssertEqual(bytes(queryOwner.rawState), bytes(primed.rawState))
            XCTAssertEqual(queryOwner.lastAdvancement, primed.lastAdvancement)
            XCTAssertEqual(queryOwner.observe(current: 0.005, observation: native(total: 2, responses: 2), at: start), .unavailable)
        }
        let before = healthy()
        let facts = observation(current: 0.005, total: 1.005, responses: 2, age: (1, 0))
        let actual = checked(before, facts)
        XCTAssertEqual(beluga_core_rtt_evidence_result_is_valid(before, facts, actual), 1)
        XCTAssertEqual(MemoryLayout<O>.size / 4, 84)
        for word in 0..<84 {
            var forged = actual
            Self.corrupt(&forged, word: word)
            XCTAssertEqual(beluga_core_rtt_evidence_result_is_valid(before, facts, forged), 0, "word \(word)")
            let start = ContinuousClock.now
            var owner = F(producer: { state, event in
                var output = beluga_core_rtt_evidence_step(state, event)
                if event.opcode == 0 && event.observation_kind == 2 && event.measurement.responses == 2 {
                    Self.corrupt(&output, word: word)
                } else if state.watermark_present == 1 {
                    XCTFail("A faulted owner must not consult its producer again")
                }
                return output
            })
            _ = owner.observe(current: 0.005, observation: native(total: 1, responses: 1), at: start)
            let primed = owner
            XCTAssertEqual(owner.observe(current: 0.005, observation: native(total: 1.005, responses: 2),
                at: start.advanced(by: .seconds(1))), .unavailable, "word \(word)")
            XCTAssertTrue(owner.hasNativeFault)
            XCTAssertEqual(bytes(owner.rawState), bytes(primed.rawState))
            XCTAssertEqual(owner.lastAdvancement, primed.lastAdvancement)
            XCTAssertEqual(owner.observe(current: 0.005, observation: native(total: 1.010, responses: 3),
                at: start.advanced(by: .seconds(2))), .unavailable)
            owner.age(at: start); owner.revoke(); owner.resetPath(); owner.resetPeer()
            owner.inactive(observation: .unavailable); owner.allowInitial(); owner.reordered(); owner.strictUnordered()
            owner.copyFence(from: F())
            XCTAssertFalse(owner.primaryLeaseIsCurrent(at: start)); XCTAssertTrue(owner.hasNativeFault)
            XCTAssertFalse(owner.publishedLeaseIsCurrent)
            XCTAssertEqual(bytes(owner.rawState), bytes(primed.rawState))
            XCTAssertEqual(owner.health, 0); XCTAssertEqual(owner.disposition, 6)
            XCTAssertFalse(owner.permitsInitial); XCTAssertNil(owner.baseline); XCTAssertTrue(owner.usesNative)
        }
    }

    func testFacadeNamedClockOperationsFastProjectionAndReplacementMatchActualC() {
        let start = ContinuousClock.now
        var owner = F()
        assertFacadeObserve(&owner, current: 0.100, observation: native(total: 1, responses: 1), at: start)
        let firstStamp = owner.lastAdvancement
        assertFacadeObserve(&owner, current: 0.020, observation: native(total: 1.020, responses: 2),
            at: start.advanced(by: .seconds(1)))
        XCTAssertNotEqual(owner.lastAdvancement, firstStamp)
        let baseline = owner.baseline
        let ordinaryStamp = owner.lastAdvancement
        let ordinaryAge = owner.observationAge
        assertFacadeObserve(&owner, current: 0.020, observation: native(total: 1.040, responses: 3),
            at: start.advanced(by: .seconds(2)), fast: true)
        XCTAssertEqual(owner.baseline, baseline); XCTAssertEqual(owner.lastAdvancement, ordinaryStamp)
        XCTAssertEqual(owner.observationAge, ordinaryAge); XCTAssertEqual(owner.distinctCount, 2)
        let proposed = owner
        var prior = F()
        assertFacadeObserve(&prior, current: 0.100, observation: native(total: 1, responses: 1), at: start)
        let copyFacts = observation(op: 11, current: 0.020, total: 1.040, responses: 3)
        assertFacadeOperation(&prior, facts: copyFacts, at: start) { $0.copyFence(from: proposed) }
        XCTAssertEqual(prior.lastAdvancement, start); XCTAssertEqual(prior.distinctCount, 1)
        assertFacadeObserve(&prior, current: 0.100, observation: native(total: 1, responses: 1),
            at: start.advanced(by: .seconds(1)))
        XCTAssertEqual(prior.disposition, 8)
        let ageTime = start.advanced(by: .seconds(3))
        let ageFacts = clockEvent(10, owner: owner, at: ageTime)
        assertFacadeOperation(&owner, facts: ageFacts, at: ageTime) { $0.age(at: ageTime) }
        let query = checked(owner.rawState, clockEvent(12, owner: owner, at: ageTime))
        let beforeQuery = owner
        XCTAssertEqual(owner.primaryLeaseIsCurrent(at: ageTime), query.primary_lease_current == 1)
        XCTAssertEqual(owner, beforeQuery)
        let publishedQuery = checked(owner.rawState, pure(12,
            age: (owner.rawState.age_seconds, owner.rawState.age_attoseconds)))
        XCTAssertEqual(owner.publishedLeaseIsCurrent, publishedQuery.primary_lease_current == 1)
        XCTAssertEqual(owner, beforeQuery, "Published-age query cannot mutate the owner")
        guard let stamp = owner.lastAdvancement else { XCTFail("Expected ordinary stamp"); return }
        let boundary = stamp.advanced(by: .seconds(4))
        let boundaryFacts = clockEvent(10, owner: owner, at: boundary)
        assertFacadeOperation(&owner, facts: boundaryFacts, at: boundary) { $0.age(at: boundary) }
        XCTAssertEqual(owner.observationAge, .seconds(4))
        let inclusiveQuery = checked(owner.rawState, pure(12, age: (4, 0)))
        let inclusiveOwner = owner
        XCTAssertEqual(inclusiveQuery.primary_lease_current, 1)
        XCTAssertTrue(owner.publishedLeaseIsCurrent)
        XCTAssertEqual(owner, inclusiveOwner)
        let pastBoundary = boundary.advanced(by: Duration(secondsComponent: 0, attosecondsComponent: 1))
        let expiredFacts = clockEvent(10, owner: owner, at: pastBoundary)
        assertFacadeOperation(&owner, facts: expiredFacts, at: pastBoundary) { $0.age(at: pastBoundary) }
        XCTAssertEqual(owner.observationAge, Duration(secondsComponent: 4, attosecondsComponent: 1))
        let exclusiveQuery = checked(owner.rawState, pure(12, age: (4, 1)))
        let expiredOwner = owner
        XCTAssertEqual(exclusiveQuery.primary_lease_current, 0)
        XCTAssertFalse(owner.publishedLeaseIsCurrent)
        XCTAssertEqual(owner, expiredOwner)
        assertFacadeOperation(&owner, facts: pure(2), at: start) { $0.revoke() }
        assertFacadeOperation(&owner, facts: pure(3), at: start) { $0.revoke(hide: true) }
        assertFacadeOperation(&owner, facts: pure(4), at: start) { $0.resetPath() }
        assertFacadeOperation(&owner, facts: observation(op: 6, current: nil, total: 2, responses: 20), at: start) {
            $0.inactive(observation: self.native(total: 2, responses: 20))
        }
        assertFacadeOperation(&owner, facts: pure(7), at: start) { $0.allowInitial() }
        assertFacadeOperation(&owner, facts: pure(8), at: start) { $0.reordered() }
        assertFacadeOperation(&owner, facts: pure(9), at: start) { $0.strictUnordered() }
        assertFacadeOperation(&owner, facts: pure(5), at: start) { $0.resetPeer() }
        XCTAssertNil(owner.lastAdvancement); XCTAssertNil(owner.observationAge)
        XCTAssertTrue(owner.permitsInitial); XCTAssertFalse(owner.hasNativeFault)
        assertFacadeObserve(&owner, current: 0.005, observation: native(total: 1, responses: .max), at: start)
        XCTAssertEqual(owner.watermark?.responses, UInt64.max)
        var replacement = F()
        assertFacadeObserve(&replacement, current: 0.005, observation: native(total: 0.005, responses: 0), at: start)
        XCTAssertEqual(replacement.health, 1); XCTAssertFalse(replacement.hasNativeFault)
        var denyCopy = F(producer: { state, event in
            var actual = beluga_core_rtt_evidence_step(state, event)
            actual.status = 0
            return actual
        })
        denyCopy.copyFence(from: proposed)
        XCTAssertTrue(denyCopy.hasNativeFault)
        XCTAssertEqual(bytes(denyCopy.rawState), bytes(R.initial()))
        var copyFaultedOwner = F()
        copyFaultedOwner.copyFence(from: denyCopy)
        XCTAssertTrue(copyFaultedOwner.hasNativeFault)
    }

    private func healthy(current: Double = 0.005, responses: UInt64 = 1) -> S {
        checked(R.initial(), observation(current: current, total: max(1, current), responses: responses)).state
    }

    private func native(pair: String = String(repeating: "a", count: 64), total: Double, responses: UInt64)
        -> WebRTCRoundTripTimeObservation {
        .measurement(.init(selectedCandidatePairFingerprint: pair,
            totalRoundTripTimeSeconds: total, responsesReceived: responses))
    }

    private func observation(op: UInt32 = 0, current: Double?,
        pair: String = String(repeating: "a", count: 64), total: Double, responses: UInt64,
        age: (Int64, Int64) = (0, 0)) -> E {
        var event = E()
        event.opcode = op; event.observation_kind = 2
        event.current_present = current == nil ? 0 : 1; event.current_bits = current?.bitPattern ?? 0
        event.fingerprint_length = UInt32(pair.utf8.count)
        event.measurement = R.encodeMeasurement(.init(selectedCandidatePairFingerprint: pair,
            totalRoundTripTimeSeconds: total, responsesReceived: responses))
        event.age_seconds = age.0; event.age_attoseconds = age.1
        return event
    }

    private func legacy(op: UInt32 = 0, current: Double?, age: (Int64, Int64) = (0, 0)) -> E {
        var event = pure(op, age: age)
        event.current_present = current == nil ? 0 : 1; event.current_bits = current?.bitPattern ?? 0
        return event
    }

    private func unavailable(op: UInt32 = 0, current: Double? = nil, age: (Int64, Int64) = (0, 0)) -> E {
        var event = legacy(op: op, current: current, age: age)
        event.observation_kind = 1
        return event
    }

    private func pure(_ op: UInt32, age: (Int64, Int64) = (0, 0)) -> E {
        var event = E(); event.opcode = op
        event.age_seconds = age.0; event.age_attoseconds = age.1
        return event
    }

    private func clockEvent(_ op: UInt32, owner: F, at now: ContinuousClock.Instant) -> E {
        let age = owner.lastAdvancement?.duration(to: now).components
        return pure(op, age: (age?.seconds ?? 0, age?.attoseconds ?? 0))
    }

    private func bytes<T>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value) { Array($0) } }

    @discardableResult
    private func checked(_ before: S, _ event: E, file: StaticString = #filePath, line: UInt = #line) -> O {
        let actual = beluga_core_rtt_evidence_step(before, event)
        let expected = R.step(before, event)
        XCTAssertEqual(bytes(actual), bytes(expected), file: file, line: line)
        XCTAssertEqual(beluga_core_rtt_evidence_result_is_valid(before, event, actual),
            actual.status == 1 ? 1 : 0, file: file, line: line)
        return actual
    }

    private func assertRejected(_ result: O, before: S, name: String,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.abi_version, 1, name, file: file, line: line)
        XCTAssertEqual(result.status, 0, name, file: file, line: line)
        XCTAssertEqual(bytes(result.state), bytes(before), name, file: file, line: line)
        XCTAssertEqual(result.fresh_pressure, 0, name, file: file, line: line)
        XCTAssertEqual(result.allows_upgrade, 0, name, file: file, line: line)
        XCTAssertEqual(result.legacy_missing, 0, name, file: file, line: line)
        XCTAssertEqual(result.clock_action, 0, name, file: file, line: line)
        XCTAssertEqual(result.validation_disposition, 6, name, file: file, line: line)
        XCTAssertEqual(result.primary_lease_current, 0, name, file: file, line: line)
    }

    private static func corrupt(_ result: inout O, word: Int) {
        withUnsafeMutableBytes(of: &result) { $0[word * 4] ^= 1 }
    }

    private func assertFacadeObserve(_ owner: inout F, current: Double?,
        observation: WebRTCRoundTripTimeObservation?, at now: ContinuousClock.Instant,
        fast: Bool = false, routeChanged: Bool = false,
        file: StaticString = #filePath, line: UInt = #line) {
        var facts = clockEvent(fast ? 1 : 0, owner: owner, at: now)
        facts.current_present = current == nil ? 0 : 1; facts.current_bits = current?.bitPattern ?? 0
        facts.route_changed = routeChanged ? 1 : 0
        if let observation {
            switch observation {
            case .unavailable: facts.observation_kind = 1
            case let .measurement(value):
                facts.observation_kind = 2; facts.fingerprint_length = UInt32(value.selectedCandidatePairFingerprint.utf8.count)
                facts.measurement = R.encodeMeasurement(value)
            }
        } else if fast { facts.observation_kind = 1 }
        let beforeStamp = owner.lastAdvancement
        let actual = checked(owner.rawState, facts, file: file, line: line)
        let returned = owner.observe(current: current, observation: observation, at: now,
            fast: fast, routeChanged: routeChanged)
        XCTAssertEqual(returned.hasFreshPressure, actual.fresh_pressure == 1, file: file, line: line)
        XCTAssertEqual(returned.allowsUpgrade, actual.allows_upgrade == 1, file: file, line: line)
        XCTAssertEqual(returned.permitsLegacyMissingValue, actual.legacy_missing == 1, file: file, line: line)
        XCTAssertEqual(returned.validationDisposition, Int(actual.validation_disposition), file: file, line: line)
        XCTAssertEqual(returned.primaryLeaseCurrent, actual.primary_lease_current == 1, file: file, line: line)
        assertFacadeState(owner, actual: actual, beforeStamp: beforeStamp, at: now, file: file, line: line)
    }

    private func assertFacadeOperation(_ owner: inout F, facts: E, at now: ContinuousClock.Instant,
        action: (inout F) -> Void, file: StaticString = #filePath, line: UInt = #line) {
        let beforeStamp = owner.lastAdvancement
        let actual = checked(owner.rawState, facts, file: file, line: line)
        action(&owner)
        assertFacadeState(owner, actual: actual, beforeStamp: beforeStamp, at: now, file: file, line: line)
    }

    private func assertFacadeState(_ owner: F, actual: O, beforeStamp: ContinuousClock.Instant?,
        at now: ContinuousClock.Instant, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(bytes(owner.rawState), bytes(actual.state), file: file, line: line)
        XCTAssertEqual(owner.lastAdvancement,
            actual.clock_action == 2 ? now : actual.clock_action == 1 ? nil : beforeStamp, file: file, line: line)
        XCTAssertFalse(owner.hasNativeFault, file: file, line: line)
        XCTAssertEqual(owner.disposition, Int(actual.state.disposition), file: file, line: line)
        XCTAssertEqual(owner.health, Int(actual.state.health), file: file, line: line)
        XCTAssertEqual(owner.provisional, actual.state.provisional == 1, file: file, line: line)
        XCTAssertEqual(owner.distinctCount, Int(actual.state.distinct_count), file: file, line: line)
    }
}
