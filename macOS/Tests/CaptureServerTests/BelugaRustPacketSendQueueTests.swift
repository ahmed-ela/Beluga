import Foundation
import XCTest
import BelugaCore
@testable import CaptureServer

final class BelugaRustPacketSendQueueTests: XCTestCase {
    private typealias S = beluga_core_packet_send_queue_state_t
    private typealias E = beluga_core_packet_send_queue_event_t
    private typealias O = beluga_core_packet_send_queue_result_t
    private typealias R = FrozenPacketSendQueueReference
    private typealias B = BelugaRustPacketSendQueueBoundary
    private typealias P = BelugaRustPacketSendQueueProducer

    func testActualCThreeLayoutsAndAllThirtyOneOffsets() {
        let actual = beluga_core_packet_send_queue_step(state(), event(packets: 1, delay: 0))
        XCTAssertEqual(actual.status, 1)
        XCTAssertEqual(MemoryLayout<S>.size, 48)
        XCTAssertEqual(MemoryLayout<S>.stride, 48)
        XCTAssertEqual(MemoryLayout<S>.alignment, 8)
        XCTAssertEqual(MemoryLayout<E>.size, 64)
        XCTAssertEqual(MemoryLayout<E>.stride, 64)
        XCTAssertEqual(MemoryLayout<E>.alignment, 8)
        XCTAssertEqual(MemoryLayout<O>.size, 96)
        XCTAssertEqual(MemoryLayout<O>.stride, 96)
        XCTAssertEqual(MemoryLayout<O>.alignment, 8)
        let offsets: [(Int?, Int)] = [
            (MemoryLayout<S>.offset(of: \S.abi_version), 0),
            (MemoryLayout<S>.offset(of: \S.reserved), 4),
            (MemoryLayout<S>.offset(of: \S.packets_present), 8),
            (MemoryLayout<S>.offset(of: \S.delay_present), 12),
            (MemoryLayout<S>.offset(of: \S.low_present), 16),
            (MemoryLayout<S>.offset(of: \S.soft_present), 20),
            (MemoryLayout<S>.offset(of: \S.packets), 24),
            (MemoryLayout<S>.offset(of: \S.delay_bits), 32),
            (MemoryLayout<S>.offset(of: \S.pressure_count), 40),
            (MemoryLayout<E>.offset(of: \E.opcode), 0),
            (MemoryLayout<E>.offset(of: \E.packets_present), 4),
            (MemoryLayout<E>.offset(of: \E.delay_present), 8),
            (MemoryLayout<E>.offset(of: \E.rtt_inflated), 12),
            (MemoryLayout<E>.offset(of: \E.packets), 16),
            (MemoryLayout<E>.offset(of: \E.delay_bits), 24),
            (MemoryLayout<E>.offset(of: \E.low_age_seconds), 32),
            (MemoryLayout<E>.offset(of: \E.low_age_attoseconds), 40),
            (MemoryLayout<E>.offset(of: \E.soft_age_seconds), 48),
            (MemoryLayout<E>.offset(of: \E.soft_age_attoseconds), 56),
            (MemoryLayout<O>.offset(of: \O.abi_version), 0),
            (MemoryLayout<O>.offset(of: \O.status), 4),
            (MemoryLayout<O>.offset(of: \O.observation), 8),
            (MemoryLayout<O>.offset(of: \O.low_action), 12),
            (MemoryLayout<O>.offset(of: \O.soft_action), 16),
            (MemoryLayout<O>.offset(of: \O.sample_inflated), 20),
            (MemoryLayout<O>.offset(of: \O.immediate), 24),
            (MemoryLayout<O>.offset(of: \O.inflated), 28),
            (MemoryLayout<O>.offset(of: \O.upgrade), 32),
            (MemoryLayout<O>.offset(of: \O.capacity_growth), 36),
            (MemoryLayout<O>.offset(of: \O.measured_delay_bits), 40),
            (MemoryLayout<O>.offset(of: \O.state), 48),
        ]
        XCTAssertEqual(offsets.count, 31)
        for (actual, expected) in offsets { XCTAssertEqual(actual, expected) }
        XCTAssertTrue(B.layoutIsExact)
    }

    func testOrdinaryCounterAndPartialBaselineMatrixMatchesFrozenOriginal() {
        let packets: [UInt64?] = [nil, 0, 1, 9_007_199_254_740_991,
            9_007_199_254_740_992, 9_007_199_254_740_993, UInt64.max - 1, UInt64.max]
        let delays: [Double?] = [nil, 0, 0.5]
        for previousPackets in packets {
            for currentPackets in packets {
                for previousDelay in delays {
                    for currentDelay in delays {
                        let before = state(packets: previousPackets, delay: previousDelay)
                        let actual = checked(before, event(packets: currentPackets, delay: currentDelay))
                        XCTAssertEqual(actual.status, 1)
                    }
                }
            }
        }
        let equal = checked(state(packets: 10, delay: 1), event(packets: 10, delay: 1))
        XCTAssertEqual(equal.observation, 1)
        let unaccountedDelay = checked(state(packets: 10, delay: 1), event(packets: 10, delay: 2))
        XCTAssertEqual(unaccountedDelay.observation, 0)
        XCTAssertEqual(unaccountedDelay.state.delay_bits, Double(2).bitPattern)
        let reset = checked(state(packets: 10, delay: 1), event(packets: 1, delay: 0))
        XCTAssertEqual(reset.observation, 0)
        let reseeded = checked(reset.state, event(packets: 2, delay: 0.01))
        XCTAssertEqual(reseeded.observation, 2)
        XCTAssertEqual(reseeded.measured_delay_bits, Double(0.01).bitPattern)
    }

    func testCurrentFloatAndOptionalRejectionsClearWithoutLosingValidSignedZero() {
        let invalid: [Double?] = [nil, .nan, .infinity, -.infinity, -1, -Double.leastNonzeroMagnitude]
        for delay in invalid {
            let rejected = checked(state(packets: 100, delay: 1, low: true, soft: true, count: 2),
                                   event(packets: 101, delay: delay))
            XCTAssertEqual(rejected.status, 1)
            XCTAssertEqual(rejected.observation, 0)
            XCTAssertEqual(stateWords(rejected.state), stateWords(state()))
            XCTAssertEqual(rejected.low_action, 1)
            XCTAssertEqual(rejected.soft_action, 1)
            XCTAssertEqual(rejected.upgrade, 0)
            let seed = checked(rejected.state, event(packets: 102, delay: 2))
            XCTAssertEqual(seed.observation, 0)
        }
        let missingPackets = checked(state(packets: 1, delay: 0), event(packets: nil, delay: 1))
        XCTAssertEqual(stateWords(missingPackets.state), stateWords(state()))
        for zero in [0.0, -0.0] {
            let actual = checked(state(packets: 0, delay: 0), event(packets: 1, delay: zero))
            XCTAssertEqual(actual.observation, 2)
            XCTAssertEqual(actual.measured_delay_bits, zero.bitPattern)
            XCTAssertEqual(actual.state.delay_bits, zero.bitPattern)
            XCTAssertEqual(actual.upgrade, 1)
        }
        let extreme = checked(state(packets: 0, delay: 0), event(packets: 1, delay: .greatestFiniteMagnitude))
        XCTAssertEqual(extreme.observation, 2)
        XCTAssertEqual(extreme.measured_delay_bits, Double.greatestFiniteMagnitude.bitPattern)
        XCTAssertEqual(extreme.immediate, 1)
    }

    func testThresholdNeighborsKeepOriginalInclusiveAndExclusiveDecisions() {
        let low = 0.020, soft = 0.100, immediate = 0.200
        let values = [low.nextDown, low, low.nextUp,
                      soft.nextDown, soft, soft.nextUp,
                      immediate.nextDown, immediate, immediate.nextUp]
        for value in values {
            for count in [UInt64(0), 1, UInt64(Int.max)] {
                for rtt in [false, true] {
                    let before = state(packets: 0, delay: 0, count: count)
                    let actual = checked(before, event(packets: 1, delay: value, rtt: rtt))
                    XCTAssertEqual(actual.measured_delay_bits, value.bitPattern)
                    XCTAssertEqual(actual.sample_inflated, value > 0.100 ? 1 : 0)
                    XCTAssertEqual(actual.immediate, value >= 0.200 ? 1 : 0)
                    XCTAssertEqual(actual.upgrade, value <= 0.020 ? 1 : 0)
                    XCTAssertEqual(actual.low_action, value <= 0.020 ? 2 : 1)
                    let expectedCount = value > 0.100 && !rtt ? min(count, UInt64(Int.max) - 1) + 1 : 0
                    XCTAssertEqual(actual.state.pressure_count, expectedCount)
                    XCTAssertEqual(actual.inflated,
                        value > 0.100 && (value >= 0.200 || expectedCount >= 2) ? 1 : 0)
                }
            }
        }
    }

    func testExactLeaseAgesIncludeBoundaryButNotOneAttosecondBeyondOrBeforeZero() {
        let ages: [(Int64, Int64, Bool)] = [
            (0, -1, false), (-1, 999_999_999_999_999_999, false),
            (0, 0, true), (1, 499_999_999_999_999_999, true),
            (1, 500_000_000_000_000_000, true), (2, -500_000_000_000_000_000, true),
            (1, 500_000_000_000_000_001, false), (Int64.min, 0, false), (Int64.max, 0, false),
        ]
        let before = state(packets: 100, delay: 1, low: true, soft: true, count: 1)
        for (seconds, attoseconds, fresh) in ages {
            let actual = checked(before, event(packets: 100, delay: 1,
                lowAge: (seconds, attoseconds), softAge: (seconds, attoseconds)))
            XCTAssertEqual(actual.observation, 1)
            XCTAssertEqual(actual.upgrade, fresh ? 1 : 0)
            XCTAssertEqual(actual.state.pressure_count, fresh ? 1 : 0)
            XCTAssertEqual(actual.low_action, fresh ? 0 : 1)
            XCTAssertEqual(actual.soft_action, fresh ? 0 : 1)
            let query = checked(before, event(op: 4, lowAge: (seconds, attoseconds)))
            XCTAssertEqual(query.upgrade, fresh ? 1 : 0)
            XCTAssertEqual(stateWords(query.state), stateWords(before))
            XCTAssertEqual(query.low_action, 0)
            XCTAssertEqual(query.soft_action, 0)
        }
    }

    func testSoftPressureSaturatesAndFreshRTTDoesNotCountQueuePressureTwice() {
        for count in [UInt64(0), 1, 2, UInt64(Int.max) - 1, UInt64(Int.max)] {
            for softPresent in [false, true] {
                let before = state(packets: 10, delay: 0, soft: softPresent, count: count)
                for rtt in [false, true] {
                    let actual = checked(before, event(packets: 11, delay: 0.105, rtt: rtt))
                    XCTAssertEqual(actual.state.pressure_count,
                        rtt ? 0 : min(count, UInt64(Int.max) - 1) + 1)
                    XCTAssertEqual(actual.soft_action, rtt ? 1 : 2)
                    XCTAssertEqual(actual.state.soft_present, rtt ? 0 : 1)
                }
            }
        }
        let stale = checked(state(packets: 10, delay: 0, soft: true, count: UInt64(Int.max)),
                            event(packets: 11, delay: 0.105, softAge: (2, 0)))
        XCTAssertEqual(stale.state.pressure_count, 1)
        let noPacketsWithRTT = checked(state(packets: 10, delay: 0, low: true, soft: true, count: 1),
                                      event(packets: 10, delay: 0, rtt: true))
        XCTAssertEqual(noPacketsWithRTT.state.pressure_count, 0)
        XCTAssertEqual(noPacketsWithRTT.soft_action, 1)
        XCTAssertEqual(noPacketsWithRTT.upgrade, 1)
    }

    func testCapacityRawBaselineKeepsOriginalNonfiniteAndPartialSemantics() {
        let previousDelays: [Double?] = [nil, .nan, .infinity, -.infinity, -1, -0.0, 0, 0.2]
        let previousPacketCounts: [UInt64?] = [nil, 0, 100, UInt64.max]
        for previousPackets in previousPacketCounts {
            for previousDelay in previousDelays {
                let before = state(packets: previousPackets, delay: previousDelay,
                                   low: true, soft: true, count: 2)
                let actual = checked(before, event(op: 1, packets: 101, delay: 0.2))
                XCTAssertEqual(actual.status, 1)
                XCTAssertEqual(actual.state.pressure_count, 2)
                XCTAssertEqual(actual.state.low_present, 1)
                XCTAssertEqual(actual.state.soft_present, 1)
                XCTAssertEqual(actual.low_action, 0)
                XCTAssertEqual(actual.soft_action, 0)
                XCTAssertEqual(actual.state.packets, 101)
                XCTAssertEqual(actual.state.delay_bits, Double(0.2).bitPattern)
            }
        }
        let negativeInfinity = checked(state(packets: 100, delay: -.infinity, low: true),
                                       event(op: 1, packets: 101, delay: 0.2))
        XCTAssertEqual(negativeInfinity.observation, 2)
        XCTAssertEqual(negativeInfinity.measured_delay_bits, Double.infinity.bitPattern)
        XCTAssertEqual(negativeInfinity.immediate, 1)
        XCTAssertEqual(negativeInfinity.capacity_growth, 0)
        for invalidPrevious in [Double.nan, Double.infinity] {
            let actual = checked(state(packets: 100, delay: invalidPrevious),
                                 event(op: 1, packets: 101, delay: 0.2))
            XCTAssertEqual(actual.observation, 0)
        }
    }

    func testCapacityCannotStampRenewOrConsumeOrdinaryLeasesAndPressure() {
        let before = state(packets: 100, delay: 1, low: true, soft: true, count: 1)
        let ages: [(Int64, Int64)] = [(0, 0), (1, 500_000_000_000_000_000),
                                    (1, 500_000_000_000_000_001), (0, -1)]
        for currentDelay in [1.0, 1.01, 1.11, 1.20] {
            for age in ages {
                let actual = checked(before, event(op: 1, packets: currentDelay == 1 ? 100 : 101,
                    delay: currentDelay, lowAge: age, softAge: age))
                XCTAssertEqual(actual.low_action, 0)
                XCTAssertEqual(actual.soft_action, 0)
                XCTAssertEqual(actual.state.low_present, before.low_present)
                XCTAssertEqual(actual.state.soft_present, before.soft_present)
                XCTAssertEqual(actual.state.pressure_count, before.pressure_count)
                if age == (1, 500_000_000_000_000_001) || age == (0, -1) {
                    XCTAssertEqual(actual.capacity_growth, 0)
                }
            }
        }
        let noPrimaryLease = checked(state(packets: 100, delay: 1),
                                     event(op: 1, packets: 101, delay: 1.01))
        XCTAssertEqual(noPrimaryLease.upgrade, 1)
        XCTAssertEqual(noPrimaryLease.capacity_growth, 0)
    }

    func testTierResetRetainsCounterBaselineWhilePathResetRetiresIt() {
        for before in [state(packets: 100, delay: 1, low: true, soft: true, count: 2),
                       state(packets: 100, delay: nil, soft: true, count: 1),
                       state(packets: nil, delay: -.infinity, low: true, count: UInt64(Int.max))] {
            let tier = checked(before, event(op: 2))
            XCTAssertEqual(tier.state.packets_present, before.packets_present)
            XCTAssertEqual(tier.state.delay_present, before.delay_present)
            XCTAssertEqual(tier.state.packets, before.packets)
            XCTAssertEqual(tier.state.delay_bits, before.delay_bits)
            XCTAssertEqual(tier.state.low_present, 0)
            XCTAssertEqual(tier.state.soft_present, 0)
            XCTAssertEqual(tier.state.pressure_count, 0)
            XCTAssertEqual(tier.low_action, 1)
            XCTAssertEqual(tier.soft_action, 1)
            let path = checked(before, event(op: 3))
            XCTAssertEqual(stateWords(path.state), stateWords(state()))
            XCTAssertEqual(path.low_action, 1)
            XCTAssertEqual(path.soft_action, 1)
        }
        let before = state(packets: 10, delay: 1)
        let tier = checked(before, event(op: 2))
        XCTAssertEqual(checked(tier.state, event(packets: 11, delay: 1.01)).observation, 2)
        let path = checked(before, event(op: 3))
        XCTAssertEqual(checked(path.state, event(packets: 11, delay: 1.01)).observation, 0)
    }

    func testMalformedABIFieldsRejectWithCanonicalEmptyResultForEveryOpcode() {
        let valid = state(packets: 10, delay: 1, low: true, soft: true, count: 1)
        let ordinary = event(packets: 11, delay: 1.01)
        let badStates: [(inout S) -> Void] = [
            { $0.abi_version = 0 }, { $0.abi_version = 2 }, { $0.reserved = 1 },
            { $0.packets_present = 2 }, { $0.delay_present = 2 },
            { $0.low_present = 2 }, { $0.soft_present = 2 },
            { $0.pressure_count = UInt64(Int.max) + 1 },
            { $0.packets_present = 0 }, { $0.delay_present = 0 },
        ]
        for mutate in badStates {
            var bad = valid; mutate(&bad)
            assertRejected(checked(bad, ordinary))
        }
        let badEvents: [(inout E) -> Void] = [
            { $0.opcode = 5 }, { $0.opcode = UInt32.max },
            { $0.packets_present = 2 }, { $0.delay_present = 2 }, { $0.rtt_inflated = 2 },
            { $0.packets_present = 0 }, { $0.delay_present = 0 },
            { $0.low_age_attoseconds = 1_000_000_000_000_000_000 },
            { $0.low_age_attoseconds = -1_000_000_000_000_000_000 },
            { $0.soft_age_attoseconds = 1_000_000_000_000_000_000 },
            { $0.soft_age_attoseconds = -1_000_000_000_000_000_000 },
        ]
        for mutate in badEvents {
            var bad = ordinary; mutate(&bad)
            assertRejected(checked(valid, bad))
        }
        for op in [UInt32(0), 1, 2, 3, 4] {
            var badAge = event(op: op)
            badAge.low_age_attoseconds = 1
            assertRejected(checked(state(), badAge))
            var badPayload = event(op: op)
            badPayload.delay_bits = 1
            assertRejected(checked(state(), badPayload))
        }
        assertRejected(checked(valid, event(op: 1, packets: 11, delay: 1.01, rtt: true)))
        for op in [UInt32(2), 3] {
            assertRejected(checked(valid, event(op: op, lowAge: (0, 1))))
            assertRejected(checked(valid, event(op: op, softAge: (0, 1))))
            assertRejected(checked(valid, event(op: op, packets: 11, delay: 1.01)))
        }
        assertRejected(checked(valid, event(op: 4, softAge: (0, 1))))
        assertRejected(checked(valid, event(op: 4, packets: 11, delay: 1.01)))
    }

    func testFacadeOrdinarySequencePublishesOnlyActualCStateAndExactNativeStamps() {
        var queue = BelugaRustPacketSendQueue()
        let start = ContinuousClock.now
        let samples: [(UInt64, Double, Int)] = [
            (100, 0.5, 0), (110, 0.6, 500), (110, 0.6, 1_000),
            (120, 1.65, 1_500), (120, 1.65, 2_000), (130, 2.7, 2_500), (140, 2.8, 3_000),
        ]
        for (packets, delay, milliseconds) in samples {
            let now = start.advanced(by: .milliseconds(milliseconds))
            let before = queue.raw
            let oldLow = queue.lowObservation
            let oldSoft = queue.softObservation
            let facts = clockEvent(op: 0, queue: queue, packets: packets, delay: delay, at: now)
            let actual = checked(before, facts)
            let decision = queue.observe(packets: packets, delay: delay, rttInflated: false, at: now)
            assertDecision(decision, actual)
            XCTAssertEqual(stateWords(queue.raw), stateWords(actual.state))
            XCTAssertEqual(queue.lowObservation,
                actual.low_action == 1 ? nil : (actual.low_action == 2 ? now : oldLow))
            XCTAssertEqual(queue.softObservation,
                actual.soft_action == 1 ? nil : (actual.soft_action == 2 ? now : oldSoft))
            XCTAssertFalse(queue.faulted)
        }
    }

    func testFacadeResetUsesEmptyEventAfterAdvancingNativeLowOrSoftLease() {
        let start = ContinuousClock.now
        for sampleDelay in [0.010, 0.105] {
            var queue = BelugaRustPacketSendQueue()
            _ = queue.observe(packets: 100, delay: 0, rttInflated: false, at: start)
            _ = queue.observe(packets: 101, delay: sampleDelay, rttInflated: false,
                              at: start.advanced(by: .milliseconds(500)))
            XCTAssertNotNil(sampleDelay <= 0.020 ? queue.lowObservation : queue.softObservation)
            let before = queue.raw
            let actual = checked(before, event(op: 2))
            queue.reset(path: false, at: start.advanced(by: .milliseconds(1_000)))
            XCTAssertFalse(queue.faulted)
            XCTAssertEqual(stateWords(queue.raw), stateWords(actual.state))
            XCTAssertNil(queue.lowObservation)
            XCTAssertNil(queue.softObservation)
            let actualPath = checked(queue.raw, event(op: 3))
            queue.reset(path: true, at: start.advanced(by: .milliseconds(1_500)))
            XCTAssertFalse(queue.faulted)
            XCTAssertEqual(stateWords(queue.raw), stateWords(actualPath.state))
        }
        var low = BelugaRustPacketSendQueue()
        _ = low.observe(packets: 100, delay: 0, rttInflated: false, at: start)
        _ = low.observe(packets: 101, delay: 0.010, rttInflated: false, at: start)
        let raw = low.raw
        XCTAssertTrue(low.lowLeaseIsFresh(at: start.advanced(by: .milliseconds(1_500))))
        XCTAssertFalse(low.lowLeaseIsFresh(at: start.advanced(by: .milliseconds(1_500))
            .advanced(by: Duration(secondsComponent: 0, attosecondsComponent: 1))))
        XCTAssertFalse(low.lowLeaseIsFresh(at: start.advanced(by: Duration(secondsComponent: 0, attosecondsComponent: -1))))
        XCTAssertEqual(stateWords(low.raw), stateWords(raw))
    }

    func testFacadeEveryForgedResultWordAfterActualCRejectsAndLatchesClosed() {
        let start = ContinuousClock.now
        for (name, mutate) in resultMutations {
            var queue = primedQueue(at: start)
            let producer = P(step: { before, event in
                var actual = beluga_core_packet_send_queue_step(before, event)
                mutate(&actual)
                return actual
            })
            let result = queue.observe(packets: 102, delay: 0.02, rttInflated: false,
                                       at: start.advanced(by: .milliseconds(1_000)), producer: producer)
            XCTAssertEqual(result, .unavailable, name)
            XCTAssertTrue(queue.faulted, name)
            XCTAssertEqual(stateWords(queue.raw), stateWords(state()), name)
            XCTAssertNil(queue.lowObservation, name)
            XCTAssertNil(queue.softObservation, name)
            XCTAssertFalse(queue.lowLeaseIsFresh(at: start), name)
        }
    }

    func testFacadeFaultCannotResumeByResetCounterRepairOrCapacityFallback() {
        let start = ContinuousClock.now
        var queue = primedQueue(at: start)
        let deny = P(step: { before, event in
            var actual = beluga_core_packet_send_queue_step(before, event)
            actual.status = 0
            return actual
        })
        XCTAssertEqual(queue.observe(packets: 102, delay: 0.02, rttInflated: false,
            at: start.advanced(by: .milliseconds(1_000)), producer: deny), .unavailable)
        let mustNotRun = P(step: { before, event in
            XCTFail("A retired queue must not ask a producer for new permission")
            return beluga_core_packet_send_queue_step(before, event)
        })
        XCTAssertEqual(queue.observe(packets: 103, delay: 0.03, rttInflated: false,
            at: start.advanced(by: .milliseconds(1_500)), producer: mustNotRun), .unavailable)
        queue.reset(path: false, at: start, producer: mustNotRun)
        queue.reset(path: true, at: start, producer: mustNotRun)
        XCTAssertEqual(queue.capacityObservation(previousPackets: 101, previousDelay: 0.01,
            packets: 103, delay: 0.03, at: start, producer: mustNotRun), .unavailable)
        XCTAssertTrue(queue.faulted)
        XCTAssertFalse(queue.lowLeaseIsFresh(at: start))
        XCTAssertEqual(stateWords(queue.raw), stateWords(state()))
        var replacement = BelugaRustPacketSendQueue()
        _ = replacement.observe(packets: 100, delay: 0, rttInflated: false, at: start)
        XCTAssertTrue(replacement.observe(packets: 101, delay: 0.01, rttInflated: false, at: start).allowsUpgrade)
        XCTAssertFalse(replacement.faulted)
    }

    func testFacadeCapacityUsesActualTemporaryBaselineAndRejectsForgeryWithoutOrdinaryMutation() {
        let start = ContinuousClock.now
        let queue = primedQueue(at: start)
        let before = queue
        for previousDelay in [Double(0.01), -1, -.infinity, .nan, .infinity] {
            let now = start.advanced(by: .milliseconds(1_000))
            var temporary = queue.raw
            temporary.packets_present = 1; temporary.packets = 101
            temporary.delay_present = 1; temporary.delay_bits = previousDelay.bitPattern
            let facts = clockEvent(op: 1, queue: queue, packets: 102, delay: 0.02, at: now)
            let actual = checked(temporary, facts)
            assertDecision(queue.capacityObservation(previousPackets: 101, previousDelay: previousDelay,
                packets: 102, delay: 0.02, at: now), actual)
            XCTAssertEqual(queue, before)
        }
        for (name, mutate) in resultMutations {
            let producer = P(step: { before, event in
                var actual = beluga_core_packet_send_queue_step(before, event)
                mutate(&actual)
                return actual
            })
            let denied = queue.capacityObservation(previousPackets: 101, previousDelay: 0.01,
                packets: 102, delay: 0.02, at: start.advanced(by: .milliseconds(1_000)), producer: producer)
            XCTAssertEqual(denied, .unavailable, name)
            XCTAssertEqual(queue, before, name)
        }
    }

    private var resultMutations: [(String, @Sendable (inout O) -> Void)] {
        [
            ("abi", { $0.abi_version ^= 1 }), ("status", { $0.status ^= 1 }),
            ("observation", { $0.observation ^= 1 }), ("lowAction", { $0.low_action ^= 1 }),
            ("softAction", { $0.soft_action ^= 1 }), ("sampleInflated", { $0.sample_inflated ^= 1 }),
            ("immediate", { $0.immediate ^= 1 }), ("inflated", { $0.inflated ^= 1 }),
            ("upgrade", { $0.upgrade ^= 1 }), ("capacityGrowth", { $0.capacity_growth ^= 1 }),
            ("measuredBits", { $0.measured_delay_bits ^= 1 }),
            ("stateABI", { $0.state.abi_version ^= 1 }), ("stateReserved", { $0.state.reserved ^= 1 }),
            ("packetsPresence", { $0.state.packets_present ^= 1 }),
            ("delayPresence", { $0.state.delay_present ^= 1 }),
            ("lowPresence", { $0.state.low_present ^= 1 }), ("softPresence", { $0.state.soft_present ^= 1 }),
            ("packets", { $0.state.packets ^= 1 }), ("delayBits", { $0.state.delay_bits ^= 1 }),
            ("pressureCount", { $0.state.pressure_count ^= 1 }),
        ]
    }

    private func primedQueue(at start: ContinuousClock.Instant) -> BelugaRustPacketSendQueue {
        var queue = BelugaRustPacketSendQueue()
        _ = queue.observe(packets: 100, delay: 0, rttInflated: false, at: start)
        _ = queue.observe(packets: 101, delay: 0.01, rttInflated: false,
                          at: start.advanced(by: .milliseconds(500)))
        return queue
    }

    private func clockEvent(op: UInt32, queue: BelugaRustPacketSendQueue,
                            packets: UInt64?, delay: Double?, at now: ContinuousClock.Instant) -> E {
        let low = queue.lowObservation?.duration(to: now).components
        let soft = queue.softObservation?.duration(to: now).components
        return event(op: op, packets: packets, delay: delay,
            lowAge: (low?.seconds ?? 0, low?.attoseconds ?? 0),
            softAge: (soft?.seconds ?? 0, soft?.attoseconds ?? 0))
    }

    private func state(packets: UInt64? = nil, delay: Double? = nil,
                       low: Bool = false, soft: Bool = false, count: UInt64 = 0) -> S {
        .init(abi_version: 1, reserved: 0, packets_present: packets == nil ? 0 : 1,
            delay_present: delay == nil ? 0 : 1, low_present: low ? 1 : 0, soft_present: soft ? 1 : 0,
            packets: packets ?? 0, delay_bits: delay?.bitPattern ?? 0, pressure_count: count)
    }

    private func event(op: UInt32 = 0, packets: UInt64? = nil, delay: Double? = nil, rtt: Bool = false,
                       lowAge: (Int64, Int64) = (0, 0), softAge: (Int64, Int64) = (0, 0)) -> E {
        .init(opcode: op, packets_present: packets == nil ? 0 : 1, delay_present: delay == nil ? 0 : 1,
            rtt_inflated: rtt ? 1 : 0, packets: packets ?? 0, delay_bits: delay?.bitPattern ?? 0,
            low_age_seconds: lowAge.0, low_age_attoseconds: lowAge.1,
            soft_age_seconds: softAge.0, soft_age_attoseconds: softAge.1)
    }

    @discardableResult
    private func checked(_ before: S, _ facts: E, file: StaticString = #filePath, line: UInt = #line) -> O {
        let actual = beluga_core_packet_send_queue_step(before, facts)
        let frozen = R.step(reference(before), reference(facts))
        XCTAssertEqual(resultWords(actual), resultWords(frozen), file: file, line: line)
        if actual.status == 1 {
            XCTAssertTrue(B.accepts(before, facts, actual), file: file, line: line)
        } else {
            XCTAssertFalse(B.accepts(before, facts, actual), file: file, line: line)
        }
        return actual
    }

    private func assertRejected(_ actual: O, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.abi_version, 1, file: file, line: line)
        XCTAssertEqual(actual.status, 0, file: file, line: line)
        XCTAssertEqual(resultWords(actual), resultWords(R.Result()), file: file, line: line)
    }

    private func assertDecision(_ decision: BelugaRustPacketSendQueue.Decision, _ raw: O,
                                file: StaticString = #filePath, line: UInt = #line) {
        switch raw.observation {
        case 2:
            guard case let .measured(value) = decision.observation else {
                XCTFail("Expected actual C measured observation", file: file, line: line); return
            }
            XCTAssertEqual(value.bitPattern, raw.measured_delay_bits, file: file, line: line)
        case 1: XCTAssertEqual(decision.observation, .noNewPackets, file: file, line: line)
        default: XCTAssertEqual(decision.observation, .unavailableOrReset, file: file, line: line)
        }
        XCTAssertEqual(decision.sampleIsInflated, raw.sample_inflated == 1, file: file, line: line)
        XCTAssertEqual(decision.requiresImmediateResponse, raw.immediate == 1, file: file, line: line)
        XCTAssertEqual(decision.isInflated, raw.inflated == 1, file: file, line: line)
        XCTAssertEqual(decision.allowsUpgrade, raw.upgrade == 1, file: file, line: line)
        XCTAssertEqual(decision.allowsCapacityGrowth, raw.capacity_growth == 1, file: file, line: line)
    }

    private func reference(_ raw: S) -> R.State {
        .init(abi_version: raw.abi_version, reserved: raw.reserved,
            packets_present: raw.packets_present, delay_present: raw.delay_present,
            low_present: raw.low_present, soft_present: raw.soft_present,
            packets: raw.packets, delay_bits: raw.delay_bits, pressure_count: raw.pressure_count)
    }

    private func reference(_ raw: E) -> R.Event {
        .init(opcode: raw.opcode, packets_present: raw.packets_present, delay_present: raw.delay_present,
            rtt_inflated: raw.rtt_inflated, packets: raw.packets, delay_bits: raw.delay_bits,
            low_age_seconds: raw.low_age_seconds, low_age_attoseconds: raw.low_age_attoseconds,
            soft_age_seconds: raw.soft_age_seconds, soft_age_attoseconds: raw.soft_age_attoseconds)
    }

    private func stateWords(_ raw: S) -> [UInt64] {
        [UInt64(raw.abi_version), UInt64(raw.reserved), UInt64(raw.packets_present), UInt64(raw.delay_present),
         UInt64(raw.low_present), UInt64(raw.soft_present), raw.packets, raw.delay_bits, raw.pressure_count]
    }

    private func stateWords(_ raw: R.State) -> [UInt64] {
        [UInt64(raw.abi_version), UInt64(raw.reserved), UInt64(raw.packets_present), UInt64(raw.delay_present),
         UInt64(raw.low_present), UInt64(raw.soft_present), raw.packets, raw.delay_bits, raw.pressure_count]
    }

    private func resultWords(_ raw: O) -> [UInt64] {
        [UInt64(raw.abi_version), UInt64(raw.status), UInt64(raw.observation), UInt64(raw.low_action),
         UInt64(raw.soft_action), UInt64(raw.sample_inflated), UInt64(raw.immediate), UInt64(raw.inflated),
         UInt64(raw.upgrade), UInt64(raw.capacity_growth), raw.measured_delay_bits] + stateWords(raw.state)
    }

    private func resultWords(_ raw: R.Result) -> [UInt64] {
        [UInt64(raw.abi_version), UInt64(raw.status), UInt64(raw.observation), UInt64(raw.low_action),
         UInt64(raw.soft_action), UInt64(raw.sample_inflated), UInt64(raw.immediate), UInt64(raw.inflated),
         UInt64(raw.upgrade), UInt64(raw.capacity_growth), raw.measured_delay_bits] + stateWords(raw.state)
    }
}
