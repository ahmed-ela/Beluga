// SOURCE-ONLY, UNCOMPILED tests. No private assay/reducer/reference imports.
import Foundation
import BelugaCore
@testable import WebRTCTransport
@testable import CaptureServer
import XCTest

final class BelugaNetworkAdaptationOwnerCodecTests: XCTestCase {
    typealias Value = BelugaNetworkAdaptationOwnerValue
    typealias Snapshot = BelugaNetworkAdaptationOwnerSnapshot
    typealias Boundary = BelugaNetworkAdaptationOwnerBoundary
    typealias Atom = BelugaNetworkAdaptationOwnerWriter.Atom

    private func fixture(revision: UInt64 = 57) -> Value {
        let anchor = ContinuousClock().now // fixture construction, never the event boundary
        let route = WebRTCICERouteDiagnostics(kind: .relayed,
            local: .init(type: .host, transport: "udp", networkType: "ethernet"),
            remote: .init(type: .relay, transport: "udp", relayProtocol: "tls"))
        var policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000, baseFramesPerSecond: 60)
        policy.networkAdaptationOwnerSeedRegression(at: anchor, route: route)
        return .init(policy: policy, revision: revision, fastStatisticsAvailable: true, lane: .ordinaryFallback,
            evidenceTime: anchor.advanced(by: .milliseconds(-625)), minimumCollectionSequence: 201,
            applied: .init(tier: .critical, maximumBitrateBps: -21, maximumTotalRTPBitrateBps: 765_432,
                maximumFramesPerSecond: 13, scaleResolutionDownBy: Double(bitPattern: 0x7ff8000000000099)))
    }
    private func atom(_ kind: UInt32, _ payload: UInt64?) -> Atom {
        .init(kind: kind, present: payload == nil ? 0 : 1, high: 0, low: payload ?? 0)
    }
    private func assertWhole(_ actual: Snapshot, _ expected: [Atom], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.atoms.count, 179, file: file, line: line)
        XCTAssertEqual(expected.count, 179, file: file, line: line)
        for (index, pair) in zip(actual.atoms, expected).enumerated() {
            XCTAssertTrue(Snapshot.equalAtoms([pair.0], [pair.1]),
                "Owner atom \(index) differs: actual(kind=\(pair.0.kind), present=\(pair.0.present), high=\(pair.0.high), low=\(pair.0.low)); expected(kind=\(pair.1.kind), present=\(pair.1.present), high=\(pair.1.high), low=\(pair.1.low))",
                file: file, line: line)
        }
    }
    private func assertRetainedSidecars(_ output: Snapshot, _ source: Snapshot, clearing: Int? = nil,
        file: StaticString = #filePath, line: UInt = #line) {
        var times = source.times
        if let clearing { times[clearing] = nil }
        XCTAssertEqual(output.times, times, file: file, line: line)
        XCTAssertEqual(output.anchor, source.anchor, file: file, line: line)
        XCTAssertEqual(output.route, source.route, file: file, line: line)
    }
    private func resumeExpected(_ source: Snapshot, revision: UInt64) -> [Atom] {
        var expected = source.atoms
        expected[16] = atom(4, 0); expected[17] = atom(4, nil)
        expected[18] = atom(2, nil); expected[19] = atom(2, nil)
        expected[25] = atom(4, 0); expected[26] = atom(7, nil)
        expected[27] = atom(2, nil); expected[28] = atom(10, nil)
        expected[168] = atom(1, revision)
        return expected
    }
    private func alteredEvidence(_ r: Boundary.RawResult, status: UInt32? = nil,
        inputs: Bool? = nil, denied: Bool? = nil) -> Boundary.RawResult {
        .init(status: status ?? r.status, header: r.header, atoms: r.atoms, metadata: r.metadata,
            edits: r.edits, coordinates: r.coordinates, reads: r.reads,
            inputsUnchanged: inputs ?? r.inputsUnchanged, deniedOutputsUntouched: denied ?? r.deniedOutputsUntouched)
    }

    func testActualSwiftCaptureNamedLedgerAndNativeCustody() throws {
        let s = try Snapshot.capture(fixture())
        XCTAssertTrue(Boundary.layoutIsExact)
        XCTAssertEqual(s.atoms[0].kind, 2); XCTAssertEqual(s.atoms[0].low, 12_000_000)
        XCTAssertEqual(s.atoms[3].low, 77); XCTAssertEqual(s.atoms[5].low, UInt64(bitPattern: -3))
        XCTAssertEqual(s.atoms[18].low, UInt64(bitPattern: -7))
        XCTAssertEqual(s.atoms[27].low, 6_765_432)
        XCTAssertEqual(s.atoms[35].low, 0x7ff8000000000042)
        XCTAssertEqual(s.atoms[139].kind, 5); XCTAssertEqual(s.atoms[139].low, 8)
        XCTAssertEqual(s.atoms[144].low, 1); XCTAssertEqual(s.atoms[147].low, 0x8000000000000000)
        XCTAssertEqual(s.atoms[152].low, 88); XCTAssertEqual(s.atoms[162].low, 0x8000000000000000)
        XCTAssertEqual(s.atoms[169].low, 1); XCTAssertEqual(s.atoms[170].low, 1)
        XCTAssertEqual(s.atoms[175].low, UInt64(bitPattern: -21)); XCTAssertEqual(s.atoms[178].low, 0x7ff8000000000099)
        XCTAssertEqual(s.times.count, 13); XCTAssertNil(s.times[9]); XCTAssertNil(s.times[10]); XCTAssertNil(s.times[11])
        XCTAssertEqual(s.route?.remote?.relayProtocol, "tls")
        XCTAssertEqual(s.anchor, s.times[0])
        // Anchor is the first actual native time, not an independently sampled clock.
        XCTAssertEqual(s.atoms[12].high, 0); XCTAssertEqual(s.atoms[12].low, 0)
        let recaptured = try Snapshot.capture(s.value, retainingAnchor: s.anchor)
        assertWhole(recaptured, s.atoms); assertRetainedSidecars(recaptured, s)
    }

    func testComplete179HandwrittenCaptureGoldenWithAllNativeTimes() throws {
        let a = ContinuousClock().now
        let route = WebRTCICERouteDiagnostics(kind: .relayed,
            local: .init(type: .host, transport: "udp", networkType: "ethernet"),
            remote: .init(type: .relay, transport: "udp", relayProtocol: "tls"))
        var policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000, baseFramesPerSecond: 60)
        policy.networkAdaptationOwnerSeedCompleteRegression(at: a, route: route)
        let value = Value(policy: policy, revision: 57, fastStatisticsAvailable: true, lane: .ordinaryFallback,
            evidenceTime: a.advanced(by: .milliseconds(-625)), minimumCollectionSequence: 201,
            applied: .init(tier: .critical, maximumBitrateBps: -21, maximumTotalRTPBitrateBps: 765_432,
                maximumFramesPerSecond: 13, scaleResolutionDownBy: Double(bitPattern: 0x7ff8000000000099)))
        func i(_ v: Int64?) -> Atom { atom(2, v.map { UInt64(bitPattern: $0) }) }
        func u(_ v: UInt64?) -> Atom { atom(1, v) }
        func d(_ v: Double) -> Atom { atom(3, v.bitPattern) }
        // Independent literal coordinates from the fixed native offsets and the
        // original anchor a+4 seconds; no production writer/Duration codec call.
        func t(_ signedAttoseconds: Int64) -> Atom {
            .init(kind: 10, present: 1, high: signedAttoseconds < 0 ? -1 : 0,
                low: UInt64(bitPattern: signedAttoseconds))
        }
        let golden: [Atom] = [
            // 0–15: scalar identities/counters, distinct same-kind values.
            i(12_000_000), i(9_344_000), i(60), u(77), atom(7, 2), i(-3), i(5), i(7),
            i(11), i(13), i(17), i(19), t(0), i(23), i(29), atom(4, 1),
            // 16–28: restoration and promotion whole optional bodies.
            atom(4, 1), atom(4, 1), i(-7), i(9), atom(7, 5), atom(7, 1), atom(7, 0),
            t(-4_375_000_000_000_000_000), i(1_234_567), atom(4, 1), atom(7, 1), i(6_765_432), t(-2_000_000_000_000_000_000),
            // 29–41: queue stored image, including signed/IEEE payloads and native times.
            i(31), i(37), i(41), atom(4, 1), atom(4, 0), atom(4, 1), atom(3, 0x7ff8000000000042),
            u(301), atom(3, 0x7ff80000000000bb), i(-13), t(-3_750_000_000_000_000_000),
            t(-4_250_000_000_000_000_000), atom(4, 1),
            // 42–59: opaque RTT words (not inferred from presence or normalized).
            atom(6, 101), atom(6, 102), atom(6, 103), atom(6, 104), atom(6, 105), atom(6, 106),
            atom(6, 107), atom(6, 108), atom(6, 109), atom(6, 110), atom(6, 111), atom(6, 112),
            atom(6, 113), atom(6, 114), atom(6, 115), atom(6, 116), atom(6, 117), atom(6, 118),
            // 60–89: all unclaimed RTT bodies survive, not just semantic getters.
            atom(3, 0x7ff8000000000001), atom(3, 0x8000000000000000), atom(3, 0x3ff0000000000000),
            atom(3, 0x4000000000000000), atom(3, 0x4008000000000000), i(-31), i(-375_000_000_000_000_000),
            u(1001), u(1002), u(1003), u(1004), u(1005), u(1006), u(1007), u(1008), atom(3, 0x7ff8000000000002), u(1009),
            u(2001), u(2002), u(2003), u(2004), u(2005), u(2006), u(2007), u(2008), atom(3, 0x7ff8000000000003), u(2009),
            atom(3, 0x7ff8000000000004), t(-4_875_000_000_000_000_000), atom(4, 1),
            // 90–142: independently literal12Mbps profiles, not values copied from source.atoms.
            atom(6, 12_000_000),
            i(9_344_000), i(9_344_000), i(12_000_000), i(12_000_000), d(12_000_000), i(nil),
            i(6_260_480), i(6_260_480), i(10_996_560), i(8_145_600), d(8_145_600), i(12_000_000),
            i(3_924_480), i(3_924_480), i(7_054_560), i(5_225_600), d(5_225_600), i(10_182_000),
            i(1_962_240), i(1_962_240), i(3_743_281), i(2_772_800), d(2_772_800), i(6_532_000),
            i(747_520), i(747_520), i(1_693_440), i(1_254_400), d(1_254_400), i(3_466_000),
            i(280_320), i(280_320), i(905_041), i(670_400), d(670_400), i(1_568_000),
            i(93_440), i(93_440), i(589_680), i(436_800), d(436_800), i(838_000),
            i(32_000), i(32_000), i(486_001), i(360_000), d(360_000), i(546_000),
            atom(5, 8), atom(4, 0), atom(5, 5), i(9_344_000),
            // 143–167: route presence plus native sidecar, capacity/floor/startup.
            u(193), atom(4, 1), atom(4, 1), u(31), atom(3, 0x8000000000000000), d(4_321_000), d(17.25), u(191),
            atom(4, 1), u(88), atom(4, 1), atom(4, 0), atom(4, 1), atom(4, 1), d(765_000),
            atom(4, 1), t(-3_875_000_000_000_000_000), d(1_234_567), u(190), atom(3, 0x8000000000000000),
            t(-6_000_000_000_000_000_000), u(77), u(88), atom(4, 1), t(-1_000_000_000_000_000_000),
            // 168–178: full Owner tail including exact applied signed/NaN bodies.
            u(57), atom(4, 1), atom(8, 1), t(-4_625_000_000_000_000_000), u(201), atom(4, 1),
            atom(7, 4), i(-21), i(765_432), i(13), atom(3, 0x7ff8000000000099)
        ]
        XCTAssertEqual(golden.count, 179)
        let p = try Boundary().propose(value, event: .stopSampling)
        assertWhole(p.source, golden)
        let originalTimes: [ContinuousClock.Instant?] = [a.advanced(by: .seconds(4)),
            a.advanced(by: .milliseconds(-375)), a.advanced(by: .seconds(2)),
            a.advanced(by: .milliseconds(125)), a.advanced(by: .seconds(-2)), a.advanced(by: .seconds(3)),
            a.advanced(by: .milliseconds(250)), a.advanced(by: .milliseconds(-250)),
            a.advanced(by: .milliseconds(-875)), nil, nil, nil, a.advanced(by: .milliseconds(-625))]
        XCTAssertEqual(p.source.times, originalTimes); XCTAssertEqual(p.source.anchor, a.advanced(by: .seconds(4)))
        XCTAssertEqual(p.source.route, route)
        var after = golden
        after[168] = u(58); after[169] = atom(4, 0); after[170] = atom(8, nil)
        after[171] = atom(10, nil); after[172] = u(nil)
        assertWhole(p.replacement, after); assertRetainedSidecars(p.replacement, p.source, clearing: 12)
        // At12Mbps baseline and maximum video happen to be equal. A second
        // immutable actual initializer separates those same-kind fields without
        // inventing or mutating admitted demand profiles through a DEBUG setter.
        let larger = Value(policy: .init(configuredTotalRTPBitrateBps: 24_000_000, baseFramesPerSecond: 60),
            revision: 0, fastStatisticsAvailable: false, lane: nil, evidenceTime: nil,
            minimumCollectionSequence: nil, applied: nil)
        let largerImage = try Snapshot.capture(larger)
        let largerProfiles: [Atom] = [
            i(9_344_000), i(18_944_000), i(16_200_001), i(12_000_000), d(12_000_000), i(nil),
            i(6_260_480), i(12_692_480), i(10_996_560), i(8_145_600), d(8_145_600), i(15_000_000),
            i(3_924_480), i(7_956_480), i(7_054_560), i(5_225_600), d(5_225_600), i(10_182_000),
            i(1_962_240), i(3_978_240), i(3_743_281), i(2_772_800), d(2_772_800), i(6_532_000),
            i(747_520), i(1_515_520), i(1_693_440), i(1_254_400), d(1_254_400), i(3_466_000),
            i(280_320), i(568_320), i(905_041), i(670_400), d(670_400), i(1_568_000),
            i(93_440), i(189_440), i(589_680), i(436_800), d(436_800), i(838_000),
            i(32_000), i(47_360), i(486_001), i(360_000), d(360_000), i(546_000)
        ]
        XCTAssertEqual(largerProfiles.count, 48)
        XCTAssertTrue(Snapshot.equalAtoms(Array(largerImage.atoms[91..<139]), largerProfiles))
    }

    func testStopSamplingFull179HandwrittenDelta() throws {
        let value = fixture()
        let p = try Boundary().propose(value, event: .stopSampling)
        var expected = p.source.atoms
        expected[168] = atom(1, 58); expected[169] = atom(4, 0); expected[170] = atom(8, nil)
        expected[171] = atom(10, nil); expected[172] = atom(1, nil)
        assertWhole(p.replacement, expected); assertRetainedSidecars(p.replacement, p.source, clearing: 12)
        assertWhole(try Snapshot.capture(value, retainingAnchor: p.source.anchor), p.source.atoms)
        XCTAssertFalse(p.collectorEnabled)
    }

    func testActivateShowExactGuardAndRevisionEvenOnRejection() throws {
        let pairs: [(UInt64, UInt64, UInt64)] = [(77, 88, 1), (78, 88, 0), (77, 89, 0)]
        for pair in pairs {
            let p = try Boundary().propose(fixture(), event: .activateShow(generation: pair.0, show: pair.1))
            var expected = p.source.atoms
            expected[154] = atom(4, pair.2); expected[168] = atom(1, 58)
            assertWhole(p.replacement, expected); assertRetainedSidecars(p.replacement, p.source)
        }
    }

    func testBothResumeCutsClearOnlyTheirFieldsAndWrapOnce() throws {
        let a = try Boundary().propose(fixture(), event: .resumeWithoutRevision)
        assertWhole(a.replacement, resumeExpected(a.source, revision: 57))
        assertRetainedSidecars(a.replacement, a.source, clearing: 2)
        let b = try Boundary().propose(fixture(revision: UInt64.max), event: .resumeAndAdvance)
        assertWhole(b.replacement, resumeExpected(b.source, revision: 0))
        assertRetainedSidecars(b.replacement, b.source, clearing: 2)

        // Model the current tuple after a route event while ACK was pending. This is value/
        // publication coverage, not an actual service ACK scheduling or native-resource test.
        let beforeAwait = fixture()
        let beforeSource = try Snapshot.capture(beforeAwait)
        var currentPolicy = beforeAwait.policy
        currentPolicy.invalidateSelectedRoute()
        let current = Value(policy: currentPolicy, revision: beforeAwait.revision &+ 1,
            fastStatisticsAvailable: beforeAwait.fastStatisticsAvailable, lane: nil,
            evidenceTime: nil, minimumCollectionSequence: beforeAwait.minimumCollectionSequence,
            applied: beforeAwait.applied)
        let currentSource = try Snapshot.capture(current, retainingAnchor: beforeSource.anchor)
        XCTAssertNil(currentSource.route)
        XCTAssertFalse(Snapshot.equalAtoms(currentSource.atoms, beforeSource.atoms))
        let event = BelugaNetworkAdaptationOwnerEvent.resumeAndAdvance
        let boundary = Boundary(), slot = Slot(boundary: boundary, value: current, event: event)
        publicationAccepted(try boundary.testPublish(slot, event: event), operation: 108)
        let accepted = try Snapshot.capture(slot.acceptedValue, retainingAnchor: currentSource.anchor)
        assertWhole(accepted, resumeExpected(currentSource, revision: 59))
        assertRetainedSidecars(accepted, currentSource, clearing: 2)
        XCTAssertEqual(slot.publications, 1)

        // A valid old result with the new revision forged into it must still be rejected by
        // complete-state/native-sidecar correlation, not merely a revision comparison.
        let staleBoundary = Boundary(testProducer: { request, _ in
            var stale = try Boundary.actual(request, beforeSource)
            XCTAssertEqual(stale.status, 1)
            stale.metadata.revision = 59
            stale.atoms[168] = self.atom(1, 59)
            return stale
        })
        let staleSlot = Slot(boundary: staleBoundary, value: current, event: event)
        XCTAssertThrowsError(try staleBoundary.testPublish(staleSlot, event: event)) { error in
            guard let ownerError = error as? BelugaNetworkAdaptationOwnerError,
                  case .invalidResult = ownerError else {
                return XCTFail("wrong stale-result classification")
            }
        }
        try publicationUnchanged(staleSlot, currentSource)
    }

    func testCollectorGateTruthTableRetainsEverythingExceptAbsentSourceFastFlag() throws {
        for source in [false, true] {
            for absent in [false, true] {
                let p = try Boundary().propose(fixture(), event: .collectorGate(sourcePresent: source, resumeContextAbsent: absent))
                var expected = p.source.atoms
                if !source { expected[169] = atom(4, 0) }
                assertWhole(p.replacement, expected); assertRetainedSidecars(p.replacement, p.source)
                XCTAssertEqual(p.collectorEnabled, source && absent)
            }
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = 0
        func increment() { lock.lock(); defer { lock.unlock() }; stored += 1 }
        var value: Int { lock.lock(); defer { lock.unlock() }; return stored }
    }
    func testDependencyFaultAndProducerCopiesAreNotResetOrRequeried() throws {
        let demandCalls = Counter(), rttCalls = Counter()
        var policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000, baseFramesPerSecond: 60,
            roundTripTimeProducer: { _, _ in rttCalls.increment(); return BelugaRustRoundTripTimeEvidence.Result() },
            tierDemandProducer: { _ in demandCalls.increment(); return BelugaRustTierDemand.Projection() })
        policy.bind(toPeerGeneration: 77) // fixture setup establishes actual terminal RTT denial
        policy.networkAdaptationOwnerSeedRegression(at: ContinuousClock().now, route: .init(kind: .direct))
        let value = Value(policy: policy, revision: 57, fastStatisticsAvailable: true, lane: .fastSender,
            evidenceTime: nil, minimumCollectionSequence: nil, applied: nil)
        let beforeDemand = demandCalls.value, beforeRTT = rttCalls.value
        let p = try Boundary().propose(value, event: .stopSampling)
        XCTAssertEqual(demandCalls.value, beforeDemand); XCTAssertEqual(rttCalls.value, beforeRTT)
        XCTAssertEqual(p.source.atoms[89].low, 1); XCTAssertEqual(p.replacement.atoms[89].low, 1)
        XCTAssertEqual(p.source.atoms[139].low, 0); XCTAssertEqual(p.replacement.atoms[140].low, 1)
        for i in 91..<139 { XCTAssertEqual(p.source.atoms[i].low, 0) }
        var retained = p.replacement.value.policy
        retained.bind(toPeerGeneration: 78)
        XCTAssertEqual(rttCalls.value, beforeRTT) // terminal denial must not query even the retained producer
        XCTAssertTrue(retained.hasNativeRoundTripTimeFault); XCTAssertTrue(retained.hasNativeTierDemandFault)
        let healthyRTTCalls = Counter(), healthyDemandCalls = Counter()
        var healthy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000, baseFramesPerSecond: 60,
            roundTripTimeProducer: { state, event in healthyRTTCalls.increment(); return beluga_core_rtt_evidence_step(state, event) },
            tierDemandProducer: { facts in healthyDemandCalls.increment(); return beluga_core_tier_demand_project(facts) })
        healthy.networkAdaptationOwnerSeedRegression(at: ContinuousClock().now, route: .init(kind: .direct))
        let healthyValue = Value(policy: healthy, revision: 57, fastStatisticsAvailable: false, lane: nil,
            evidenceTime: nil, minimumCollectionSequence: nil, applied: nil)
        let copied = try Boundary().propose(healthyValue, event: .stopSampling)
        XCTAssertEqual(healthyRTTCalls.value, 0); XCTAssertEqual(healthyDemandCalls.value, 8)
        var copiedPolicy = copied.replacement.value.policy
        copiedPolicy.bind(toPeerGeneration: 78)
        XCTAssertGreaterThan(healthyRTTCalls.value, 0) // original closure remains, not a fresh default producer
        XCTAssertFalse(copiedPolicy.hasNativeRoundTripTimeFault)
    }

    func testMalformedResultCannotEscapeAsReplacement() throws {
        let value = fixture(), before = try Snapshot.capture(value)
        for corruption in 0..<54 {
            let boundary = Boundary(testProducer: { request, snapshot in
                var r = try Boundary.actual(request, snapshot)
                switch corruption {
                case 0: r.atoms[42].low ^= 1 // opaque inner ABI, outside this operation
                case 1: r.atoms[178].low ^= 1 // applied NaN payload, not Swift floating equality
                case 2: r.atoms[144].low = 0 // may not drop actual retained route custody
                case 3: r.edits[12].action = 0 // even already-absent owned slot requires Clear
                case 4: r.metadata.revision &+= 1
                case 5: r.reads[0].status = 1
                case 6: return self.alteredEvidence(r, status: 99)
                case 7: r.header.abi = 2
                case 8: r.header.domain = 1
                case 9: r.header.phase = 1
                case 10: r.header.count = 178
                case 11: r.atoms.removeLast()
                case 12: r.metadata.operation = 106
                case 13: r.metadata.scope = 1
                case 14: r.metadata.invocation &+= 1
                case 15: r.metadata.peer &+= 1
                case 16: r.metadata.peer_present = 0
                case 17: r.metadata.queue_fault ^= 1
                case 18: r.metadata.rtt_fault ^= 1
                case 19: r.metadata.bound = 1
                case 20: r.metadata.route = 1
                case 21: r.metadata.sample = 1
                case 22: r.metadata.enabled = 1
                case 23: r.metadata.lease = 1
                case 24: r.metadata.read_count = 1
                case 25: r.edits.removeLast()
                case 26: r.coordinates.removeLast()
                case 27: r.reads.removeLast()
                case 28: r.coordinates[12].present = 1
                case 29: r.coordinates[12].reserved = 1
                case 30: r.coordinates[12].high = -1
                case 31: r.coordinates[12].low = 1
                case 32: r.edits[12].source = 1
                case 33: r.edits[12].index = 1
                case 34: r.edits[12].ordinal = 1
                case 35: r.edits[12].high = -1
                case 36: r.edits[12].low = 1
                case 37: r.reads[0].reserved = 1
                case 38: return self.alteredEvidence(r, inputs: false)
                case 39: return self.alteredEvidence(r, status: 2, denied: false)
                case 40: r.metadata.abi = 2
                case 41: r.reads[0].abi = 1
                case 42: r.reads[0].site = 1
                case 43: r.reads[0].ordinal = 1
                case 44: r.reads[0].invocation = 1
                case 45: r.reads[0].high = -1
                case 46: r.reads[0].low = 1
                case 47: r.edits[0].action = 1 // unowned slot must be zero, not inferred Retain
                case 48: return self.alteredEvidence(r, status: 0)
                case 49: r.header.count = 180
                case 50: r.atoms.append(r.atoms[0])
                case 51: r.edits.append(r.edits[0])
                case 52: r.coordinates.append(r.coordinates[0])
                default: r.reads.append(r.reads[0])
                }
                return r
            })
            XCTAssertThrowsError(try boundary.propose(value, event: .stopSampling))
            assertWhole(try Snapshot.capture(value, retainingAnchor: before.anchor), before.atoms)
        }
        enum Sentry: Error { case thrownByProducer }
        var throwNext = true
        let throwing = Boundary(testProducer: { request, snapshot in
            if throwNext { throwNext = false; throw Sentry.thrownByProducer }
            return try Boundary.actual(request, snapshot)
        })
        XCTAssertThrowsError(try throwing.propose(value, event: .stopSampling)) { error in
            XCTAssertTrue(error is Sentry)
        }
        let recovered = try throwing.propose(value, event: .stopSampling)
        assertWhole(recovered.source, before.atoms)
        XCTAssertEqual(recovered.replacement.value.revision, 58)
    }

    func testSwallowedNestedEntryPoisonsOuterBeforeReplacement() throws {
        let value = fixture(), before = try Snapshot.capture(value)
        var calls = 0
        var nestedNext = true
        var boundary: Boundary!
        boundary = Boundary(testProducer: { request, snapshot in
            calls += 1
            if nestedNext {
                nestedNext = false
                XCTAssertThrowsError(try boundary.propose(value, event: .stopSampling))
            }
            return try Boundary.actual(request, snapshot)
        })
        XCTAssertThrowsError(try boundary.propose(value, event: .stopSampling))
        XCTAssertEqual(calls, 1) // rejected nested entry never invokes its provider
        assertWhole(try Snapshot.capture(value, retainingAnchor: before.anchor), before.atoms)
        let recovered = try boundary.propose(value, event: .stopSampling)
        XCTAssertEqual(calls, 2); XCTAssertEqual(recovered.replacement.value.revision, 58)
        assertWhole(recovered.source, before.atoms)
    }

    func testAbsentOwnedTimeStillClearsAndOriginalAnchorIsRetained() throws {
        let time = ContinuousClock().now
        let policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000, baseFramesPerSecond: 60)
        let value = Value(policy: policy, revision: 8, fastStatisticsAvailable: true, lane: nil,
            evidenceTime: time, minimumCollectionSequence: nil, applied: nil)
        let boundary = Boundary()
        let first = try boundary.propose(value, event: .stopSampling)
        XCTAssertEqual(first.source.anchor, time); XCTAssertEqual(first.replacement.anchor, time)
        XCTAssertTrue(first.replacement.times.allSatisfy { $0 == nil })
        let second = try boundary.propose(first.replacement.value, event: .resumeWithoutRevision)
        XCTAssertNil(second.source.anchor); XCTAssertNil(second.replacement.anchor)
        assertWhole(second.replacement, second.source.atoms) // no changes, but owned journal still Clear
    }

    func testPublicRefusalLeavesAllSixOutputsUntouchedAndNoProposal() throws {
        let value = fixture(), before = try Snapshot.capture(value)
        let boundary = Boundary(testProducer: { request, snapshot in
            var unsupported = request; unsupported.operation = 202
            let r = try Boundary.actual(unsupported, snapshot)
            XCTAssertEqual(r.status, 2); XCTAssertTrue(r.inputsUnchanged); XCTAssertTrue(r.deniedOutputsUntouched)
            return r
        })
        XCTAssertThrowsError(try boundary.propose(value, event: .stopSampling))
        assertWhole(try Snapshot.capture(value, retainingAnchor: before.anchor), before.atoms)
    }
}

// Additive report-copy tests only; no event callback, read-plan or Prepared authority.
extension BelugaNetworkAdaptationOwnerCodecTests {
    private typealias ReportCapture = BelugaNetworkAdaptationOwnerReportSnapshot
    private func report192Words(_ w: ReportCapture.Wire) -> [UInt64] {
        let f = w.fingerprint
        return [w.peer, UInt64(w.capture_active), UInt64(w.automatically_suspended), UInt64(w.strict),
            UInt64(w.incoming_present), UInt64(w.equal_to_retained), UInt64(w.observation_kind),
            UInt64(w.collection_sequence_present), UInt64(w.bandwidth_present), UInt64(w.current_rtt_present),
            UInt64(w.packets_present), UInt64(w.delay_present), UInt64(w.native_timestamp_present),
            UInt64(w.fingerprint_length), UInt64(w.reserved), w.collection_sequence, w.bandwidth_bits,
            w.current_rtt_bits, w.packets, w.delay_bits, w.native_timestamp_bits,
            f.0, f.1, f.2, f.3, f.4, f.5, f.6, f.7, w.measurement_total_bits, w.measurement_responses]
    }
    private func report192(_ snapshot: WebRTCStatisticsSnapshot, timestamp: Double = -0.0) -> WebRTCScreenVideoStatisticsReport {
        .init(snapshot: snapshot, nativeReportTimestampMicroseconds: timestamp)
    }
    private func report192Route(_ transport: String? = "udp", network: String? = "wifi",
        relay: String? = "tls", kind: WebRTCICERouteKind = .relayed,
        localRelay: String? = nil, remoteTransport: String? = "udp", remoteNetwork: String? = nil,
        localType: WebRTCCandidateType = .host, remoteType: WebRTCCandidateType = .relay
    ) -> WebRTCICERouteDiagnostics {
        .init(kind: kind, local: .init(type: localType, transport: transport, networkType: network, relayProtocol: localRelay),
            remote: .init(type: remoteType, transport: remoteTransport, networkType: remoteNetwork, relayProtocol: relay))
    }

    func testReport192FullHandwrittenLedgerPreservesNativeTelemetry() throws {
        let incoming = report192Route(), retained = report192Route(network: "ethernet")
        let snapshot = WebRTCStatisticsSnapshot(collectedAt: Date(timeIntervalSince1970: 123),
            collectionSequence: UInt64.max, route: incoming,
            currentRoundTripTime: Double(bitPattern: 0x8000000000000000),
            roundTripTimeObservation: .measurement(.init(selectedCandidatePairFingerprint: "abcdefghZ",
                totalRoundTripTimeSeconds: Double(bitPattern: 0x7ff8000000000044), responsesReceived: 91)),
            availableOutgoingBitrate: Double(bitPattern: 0x7ff8000000000011),
            outboundVideo: .init(packets: UInt64.max, totalPacketSendDelay: Double(bitPattern: 0xfff0000000000000)))
        let report = report192(snapshot, timestamp: Double(bitPattern: 0x7ff8000000000033))
        let c = try ReportCapture.capture(report, retainingRoute: retained)
        // All31 logical fields cover the whole192 bytes in declared POD order.
        // Genuine501 replaces three entry fields; only Regular forces strict=true.
        let expected: [UInt64] = [
            0,0,0,0, 1,0,2,1,1,1,1,1,1,9,0,
            UInt64.max,0x7ff8000000000011,0x8000000000000000,UInt64.max,
            0xfff0000000000000,0x7ff8000000000033,
            0x6867666564636261,0x5a,0,0,0,0,0,0,0x7ff8000000000044,91
        ]
        XCTAssertEqual(report192Words(c.wire), expected)
        XCTAssertEqual(MemoryLayout<ReportCapture.Wire>.size, 192)
        XCTAssertEqual(MemoryLayout<ReportCapture.Wire>.stride, 192)
        XCTAssertEqual(MemoryLayout<ReportCapture.Wire>.alignment, 8)
        XCTAssertEqual(c.incomingRoute, incoming); XCTAssertEqual(c.retainedRoute, retained)
        XCTAssertEqual(c.report.nativeSnapshot.collectedAt, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(c.report.nativeSnapshot.availableOutgoingBitrate?.bitPattern, 0x7ff8000000000011)
        XCTAssertEqual(c.report.nativeReportTimestampMicroseconds.bitPattern, 0x7ff8000000000033)
        // Repeated capture does not normalize NaN, signed zero or source values.
        XCTAssertEqual(report192Words(try ReportCapture.capture(report, retainingRoute: retained).wire), expected)
    }

    func testReport192AbsentAndNonmeasurementOptionalsStayCanonical() throws {
        for (observation, kind) in [(Optional<WebRTCRoundTripTimeObservation>.none, UInt64(0)),
            (Optional<WebRTCRoundTripTimeObservation>.some(.unavailable), UInt64(1))] {
            let snapshot = WebRTCStatisticsSnapshot(collectedAt: Date(timeIntervalSince1970: 0),
                roundTripTimeObservation: observation, outboundVideo: .init())
            let c = try ReportCapture.capture(report192(snapshot), retainingRoute: nil)
            var expected = [UInt64](repeating: 0, count: 31)
            expected[5] = 1 // whole Optional nil equals nil
            expected[6] = kind
            expected[12] = 1 // sender DTO's UTC identity is nonoptional
            expected[20] = 0x8000000000000000
            XCTAssertEqual(report192Words(c.wire), expected)
            XCTAssertNil(c.incomingRoute); XCTAssertNil(c.retainedRoute)
        }
        let presentZero = WebRTCStatisticsSnapshot(collectedAt: Date(timeIntervalSince1970: 0),
            collectionSequence: 0, currentRoundTripTime: 0, availableOutgoingBitrate: 0,
            outboundVideo: .init(packets: 0, totalPacketSendDelay: 0))
        let zero = try ReportCapture.capture(report192(presentZero, timestamp: 0), retainingRoute: nil)
        var expected = [UInt64](repeating: 0, count: 31)
        expected[5] = 1
        for index in 7...12 { expected[index] = 1 }
        XCTAssertEqual(report192Words(zero.wire), expected) // present zero is not absent
    }

    func testReport192UsesNativeRouteNotEnrichedDiagnostics() throws {
        let cached = report192Route()
        let original = report192(.init(collectedAt: Date(timeIntervalSince1970: 5),
            collectionSequence: 7, route: nil))
        let enriched = original.restoringRouteIfNeeded(cached)
        XCTAssertNil(enriched.nativeSnapshot.route); XCTAssertEqual(enriched.snapshot.route, cached)
        let c = try ReportCapture.capture(enriched, retainingRoute: cached)
        XCTAssertEqual(c.wire.incoming_present, 0); XCTAssertEqual(c.wire.equal_to_retained, 0)
        XCTAssertNil(c.incomingRoute); XCTAssertEqual(c.retainedRoute, cached)
        XCTAssertNil(c.report.nativeSnapshot.route); XCTAssertEqual(c.report.snapshot.route, cached)
        let nilRetained = try ReportCapture.capture(enriched, retainingRoute: nil)
        XCTAssertEqual(nilRetained.wire.incoming_present, 0); XCTAssertEqual(nilRetained.wire.equal_to_retained, 1)
    }

    func testReport192WholeOptionalRouteEqualityIncludesEveryMetadataField() throws {
        let route = report192Route()
        let cases: [(WebRTCICERouteDiagnostics?, WebRTCICERouteDiagnostics?, UInt32, UInt32)] = [
            (nil,nil,0,1), (nil,route,0,0), (route,nil,1,0), (route,route,1,1),
            (route,report192Route(kind: .direct),1,0),
            (route,report192Route(localType: .serverReflexive),1,0),
            (route,report192Route(remoteType: .host),1,0),
            (route,report192Route("tcp"),1,0), (route,report192Route(nil),1,0),
            (route,report192Route(network: "ethernet"),1,0), (route,report192Route(network: nil),1,0),
            (route,report192Route(relay: "udp"),1,0), (route,report192Route(relay: nil),1,0),
            (route,report192Route(localRelay: "udp"),1,0),
            (route,report192Route(remoteTransport: "tcp"),1,0), (route,report192Route(remoteTransport: nil),1,0),
            (route,report192Route(remoteNetwork: "wifi"),1,0),
            (route,WebRTCICERouteDiagnostics(kind: .relayed, local: nil, remote: route.remote),1,0),
            (route,WebRTCICERouteDiagnostics(kind: .relayed, local: route.local, remote: nil),1,0)
        ]
        for (incoming, retained, presence, equality) in cases {
            let report = report192(.init(collectedAt: Date(timeIntervalSince1970: 9), route: incoming))
            let c = try ReportCapture.capture(report, retainingRoute: retained)
            XCTAssertEqual(c.wire.incoming_present, presence); XCTAssertEqual(c.wire.equal_to_retained, equality)
            XCTAssertEqual(c.incomingRoute, incoming); XCTAssertEqual(c.retainedRoute, retained)
        }
    }

    func testReport192UTF8PackingBoundariesAndOverlongNotTruncated() throws {
        let zero = [UInt64](repeating: 0, count: 8)
        let cases: [(String, UInt32, [UInt64])] = [
            ("",0,zero),
            ("abcdefg",7,[0x0067666564636261,0,0,0,0,0,0,0]),
            ("abcdefgh",8,[0x6867666564636261,0,0,0,0,0,0,0]),
            (String(repeating: "ABCDEFGH", count: 8),64,[UInt64](repeating: 0x4847464544434241, count: 8)),
            (String(repeating: "é", count: 32),64,[UInt64](repeating: 0xa9c3a9c3a9c3a9c3, count: 8)),
            (String(repeating: "x", count: 65),65,zero),
            (String(repeating: "é", count: 33),66,zero)
        ]
        for (fingerprint, length, expected) in cases {
            let snapshot = WebRTCStatisticsSnapshot(collectedAt: Date(timeIntervalSince1970: 10),
                roundTripTimeObservation: .measurement(.init(selectedCandidatePairFingerprint: fingerprint,
                    totalRoundTripTimeSeconds: Double(bitPattern: 0x8000000000000000), responsesReceived: UInt64.max)))
            let c = try ReportCapture.capture(report192(snapshot), retainingRoute: nil)
            XCTAssertEqual(c.wire.observation_kind, 2); XCTAssertEqual(c.wire.fingerprint_length, length)
            XCTAssertEqual(Array(report192Words(c.wire)[21..<29]), expected)
            XCTAssertEqual(c.wire.measurement_total_bits, 0x8000000000000000)
            XCTAssertEqual(c.wire.measurement_responses, UInt64.max)
        }
    }

    func testReport192UTCIdentityIsCopiedWithoutDateOrMonotonicSubstitution() throws {
        let identities: [UInt64] = [0,0x8000000000000000,0x7ff0000000000000,
            0xfff0000000000000,0x7ff8000000001234,0x4031400000000000]
        for bits in identities {
            let a = report192(.init(collectedAt: Date(timeIntervalSince1970: 20)), timestamp: Double(bitPattern: bits))
            let b = report192(.init(collectedAt: Date(timeIntervalSince1970: 21)), timestamp: Double(bitPattern: bits))
            let ca = try ReportCapture.capture(a, retainingRoute: nil)
            let cb = try ReportCapture.capture(b, retainingRoute: nil)
            XCTAssertEqual(ca.wire.native_timestamp_present, 1)
            XCTAssertEqual(ca.wire.native_timestamp_bits, bits)
            XCTAssertEqual(report192Words(ca.wire), report192Words(cb.wire))
            XCTAssertEqual(ca.report.nativeSnapshot.collectedAt, Date(timeIntervalSince1970: 20))
            XCTAssertEqual(cb.report.nativeSnapshot.collectedAt, Date(timeIntervalSince1970: 21))
        }
    }
}

// Append to the existing Owner codec XCTest file. No test runner or native fixture
// admission is created here. Copied-value tests do not certify an actor entry.
extension BelugaNetworkAdaptationOwnerCodecTests {
    private func terminalFixture(at anchor: ContinuousClock.Instant, fault: Bool = true) -> Value {
        var policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000,
            baseFramesPerSecond: 60)
        policy.bind(toPeerGeneration: 77)
        if fault { policy.networkAdaptationOwnerSeedClockedRetainedRTTFault() }
        return .init(policy: policy, revision: 57, fastStatisticsAvailable: true,
            lane: .ordinaryFallback, evidenceTime: anchor, minimumCollectionSequence: 80,
            applied: .init(tier: .critical, maximumBitrateBps: -21,
                maximumTotalRTPBitrateBps: 765_432, maximumFramesPerSecond: 13,
                scaleResolutionDownBy: Double(bitPattern: 0x7ff8000000000099)))
    }
    private func terminalReport() -> WebRTCScreenVideoStatisticsReport {
        let route = WebRTCICERouteDiagnostics(kind: .relayed,
            local: .init(type: .host, transport: "udp", networkType: "ethernet"),
            remote: .init(type: .relay, transport: "udp", relayProtocol: "tls"))
        return .init(snapshot: WebRTCStatisticsSnapshot(collectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            collectionSequence: 88, route: route, availableOutgoingBitrate: 4_000_000),
            nativeReportTimestampMicroseconds: 17.25)
    }
    private func terminalRaw(_ raw: Boundary.PrepareRawResult, status: UInt32? = nil,
        inputs: Bool? = nil, denied: Bool? = nil) -> Boundary.PrepareRawResult {
        .init(status: status ?? raw.status, header: raw.header, atoms: raw.atoms,
            metadata: raw.metadata, outcome: raw.outcome, edits: raw.edits,
            coordinates: raw.coordinates, reads: raw.reads,
            inputsUnchanged: inputs ?? raw.inputsUnchanged,
            deniedOutputsUntouched: denied ?? raw.deniedOutputsUntouched)
    }
    // Literal full54 tail, independent of both the result encoder and reducer.
    private func terminalExpectedTail(active: Bool = true) -> [Atom] {
        [atom(1,77), atom(1,57), atom(1,57), atom(6,0), atom(4,active ? 1 : 0), atom(4,0),
         atom(4,0), atom(7,nil), atom(2,nil), atom(2,nil), atom(2,nil), atom(3,nil),
         atom(7,5), atom(2,280_320), atom(2,905_041), atom(2,5), atom(3,4.0.bitPattern), atom(6,0),
         atom(4,1), atom(1,nil), atom(4,0), atom(4,0), atom(4,0), atom(4,0), atom(2,0),
         atom(1,88), atom(1,nil), atom(1,nil), atom(1,nil), atom(1,17),
         atom(3,4_000_000.0.bitPattern), atom(3,nil), atom(1,nil), atom(2,905_041), atom(2,905_041),
         atom(6,0), atom(6,0), atom(6,0), atom(6,0), atom(1,nil), atom(6,nil), atom(4,nil),
         atom(4,0), atom(6,nil), atom(7,nil), atom(1,nil), atom(1,nil), atom(1,nil),
         atom(2,nil), atom(2,nil), atom(1,nil), atom(1,nil), atom(1,nil), atom(1,nil)]
    }

    func testTerminalPrepareFull222ManualGoldenAndRetainedNativeTuple() throws {
        let anchor = ContinuousClock().now
        let value = terminalFixture(at: anchor), report = terminalReport()
        let before = try Snapshot.capture(value)
        var clocks = 0, calls = 0
        let boundary = Boundary(testClock: { clocks += 1; return anchor.advanced(by: .milliseconds(5)) },
            testPrepareProducer: { q,s,r,t,c in calls += 1; return try Boundary.actualPrepare(q,s,r,t,c) })
        let draft = try boundary.testTerminalPreparedValue(value, report: report)
        var expected = Array(before.atoms.prefix(168))
        expected[5] = atom(2,0); expected[9] = atom(2,0)
        expected[25] = atom(4,0); expected[26] = atom(7,nil)
        expected[27] = atom(2,nil); expected[28] = atom(10,nil)
        expected.append(contentsOf: terminalExpectedTail())
        XCTAssertEqual(expected.count, 222)
        XCTAssertTrue(Snapshot.equalAtoms(draft.atoms, expected))
        XCTAssertEqual(clocks, 1); XCTAssertEqual(calls, 1)
        XCTAssertEqual(draft.source.times, before.times)
        var expectedTimes = Array(before.times.prefix(9)); expectedTimes[2] = nil
        XCTAssertEqual(draft.policyTimes, expectedTimes)
        XCTAssertEqual(draft.source.anchor, before.anchor)
        XCTAssertEqual(draft.source.route, before.route)
        XCTAssertEqual(draft.report.incomingRoute, report.nativeSnapshot.route)
        XCTAssertEqual(draft.report.retainedRoute, before.route)
        XCTAssertEqual(draft.report.report.nativeSnapshot.collectedAt, report.nativeSnapshot.collectedAt)
        XCTAssertEqual(draft.report.wire.native_timestamp_bits, 17.25.bitPattern)
        XCTAssertEqual(draft.source.value.revision, 57)
        XCTAssertEqual(draft.source.value.applied?.scaleResolutionDownBy.bitPattern, 0x7ff8000000000099)
        let after = try Snapshot.capture(value, retainingAnchor: before.anchor)
        XCTAssertTrue(Snapshot.equalAtoms(after.atoms, before.atoms))
        assertRetainedSidecars(after, before)
        try assertInactiveTerminalGolden()
        try assertGeneralPrepareOriginalReferenceParity()
        try assertGeneralPrepareClosedControls()
        try assertGeneralPrepareReadBearingNoneAndClockFailures()
        try assertBeginActiveGoldenAndNativeCustody()
    }

    func testTerminalPrepareClosedAdmissionConsumesNoClockOrRawCall() throws {
        let anchor = ContinuousClock().now
        let report = terminalReport(), terminal = terminalFixture(at: anchor)
        let healthy = terminalFixture(at: anchor, fault: false).policy
        var origin = terminal.policy; origin.networkAdaptationOwnerSeedClockedProbe()
        let values = [Value(policy: healthy, revision: 57, fastStatisticsAvailable: false,
            lane: nil, evidenceTime: anchor, minimumCollectionSequence: nil, applied: nil),
            Value(policy: origin, revision: 57, fastStatisticsAvailable: false,
            lane: nil, evidenceTime: anchor, minimumCollectionSequence: nil, applied: nil), terminal, terminal]
        var clocks = 0, calls = 0
        let boundary = Boundary(testClock: { clocks += 1; return anchor },
            testPrepareProducer: { q,s,r,t,c in calls += 1; return try Boundary.actualPrepare(q,s,r,t,c) })
        for i in 0..<values.count {
            XCTAssertThrowsError(try boundary.testTerminalPreparedValue(values[i], report: report,
                generation: i == 2 ? 78 : 77, expectedRevision: i == 3 ? 58 : 57))
        }
        XCTAssertEqual(clocks, 0); XCTAssertEqual(calls, 0)
        // The untouched healthy input has no surprise binding or producer call.
        XCTAssertFalse(healthy.hasNativeAdaptationPolicyFault)
    }

    func testTerminalPrepareDemandOnlySucceedsButQueueOnlyUsesNoClockOrRawCall() throws {
        let anchor = ContinuousClock().now, report = terminalReport()
        let demandCalls = Counter()
        var demand = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000,
            baseFramesPerSecond: 60, tierDemandProducer: { facts in
                demandCalls.increment()
                var actual = beluga_core_tier_demand_project(facts)
                actual.status ^= 1 // deliberately rejected, never represented as valid authority
                return actual
            })
        demand.bind(toPeerGeneration: 77)
        XCTAssertTrue(demand.hasNativeTierDemandFault)
        XCTAssertFalse(demand.hasNativeRoundTripTimeFault)
        let value = Value(policy: demand, revision: 57, fastStatisticsAvailable: false,
            lane: nil, evidenceTime: anchor, minimumCollectionSequence: 80, applied: nil)
        let before = try Snapshot.capture(value), initialCalls = demandCalls.value
        XCTAssertEqual(before.atoms[140].low, 1); XCTAssertEqual(before.atoms[89].low, 0)
        XCTAssertEqual(before.atoms[139].low, 0)
        var clocks = 0, rawCalls = 0
        let boundary = Boundary(testClock: { clocks += 1; return anchor },
            testPrepareProducer: { q,s,r,t,c in rawCalls += 1; return try Boundary.actualPrepare(q,s,r,t,c) })
        let draft = try boundary.testTerminalPreparedValue(value, report: report)
        XCTAssertEqual(clocks, 1); XCTAssertEqual(rawCalls, 1)
        XCTAssertEqual(demandCalls.value, initialCalls)
        XCTAssertEqual(draft.atoms[140].low, 1); XCTAssertEqual(draft.atoms[89].low, 0)
        XCTAssertEqual(draft.tail.recommendation.tier, .audioPriority)
        XCTAssertEqual(draft.tail.recommendation.maximumBitrateBps, 1)
        XCTAssertEqual(draft.tail.recommendation.maximumTotalRTPBitrateBps, 1)
        var queue = terminalFixture(at: anchor, fault: false).policy
        queue.networkAdaptationOwnerSeedClockedRetainedQueueFault()
        XCTAssertFalse(queue.hasNativeTierDemandFault); XCTAssertFalse(queue.hasNativeRoundTripTimeFault)
        let queueOnly = Value(policy: queue, revision: 57, fastStatisticsAvailable: false,
            lane: nil, evidenceTime: anchor, minimumCollectionSequence: 80, applied: nil)
        XCTAssertEqual(try Snapshot.capture(queueOnly).atoms[41].low, 1)
        XCTAssertThrowsError(try boundary.testTerminalPreparedValue(queueOnly, report: report))
        XCTAssertEqual(clocks, 1); XCTAssertEqual(rawCalls, 1) // zero additional calls
        let inactiveDemand = try Boundary().testTerminalPreparedValue(value, report: report, active: false)
        guard case let .ready(adopted) = try Boundary().testInactiveTerminal(inactiveDemand, current: before,
            suspended: true) else { return XCTFail("terminal demand must adopt, never resume") }
        XCTAssertEqual(adopted.value.revision, 58)
        XCTAssertEqual(demandCalls.value, initialCalls)
    }

    func testTerminalPrepareAllSevenDeniedOutputsMustRemainUntouched() throws {
        try assertInactiveTerminalDenials()
        try assertBeginActiveClosedControls()
        let anchor = ContinuousClock().now, value = terminalFixture(at: ContinuousClock().now)
        let report = terminalReport()
        let boundary = Boundary(testClock: { anchor }, testPrepareProducer: { q,s,r,t,c in
            var malformed = q; malformed.abi = 0
            let raw = try Boundary.actualPrepare(malformed,s,r,t,c)
            XCTAssertEqual(raw.status, 2); XCTAssertTrue(raw.deniedOutputsUntouched)
            XCTAssertTrue(raw.inputsUnchanged)
            return raw
        })
        XCTAssertThrowsError(try boundary.testTerminalPreparedValue(value, report: report))
        for status: UInt32 in [2,3,4,5] {
            for untouched in [false, true] {
                let b = Boundary(testClock: { anchor }, testPrepareProducer: { q,s,r,t,c in
                    let raw = try Boundary.actualPrepare(q,s,r,t,c)
                    return self.terminalRaw(raw, status: status, denied: untouched)
                })
                XCTAssertThrowsError(try b.testTerminalPreparedValue(value, report: report)) { error in
                    guard let error = error as? BelugaNetworkAdaptationOwnerError else { return XCTFail("wrong error") }
                    switch (untouched, error) {
                    case (true, .refused), (false, .invalidResult): break
                    default: XCTFail("wrong seven-output denial classification")
                    }
                }
            }
        }
    }

    func testTerminalPrepareRejectsMalformedSevenObjectsAndRecoversFreshly() throws {
        try assertInactiveTerminalMalformed()
        let anchor = ContinuousClock().now, value = terminalFixture(at: ContinuousClock().now)
        let report = terminalReport()
        for mode in 0..<24 {
            var call = 0
            let b = Boundary(testClock: { anchor }, testPrepareProducer: { q,s,r,t,c in
                call += 1
                var raw = try Boundary.actualPrepare(q,s,r,t,c)
                if call == 2 { XCTAssertEqual(q.invocation, 2); return raw }
                switch mode {
                case 0: raw.header.abi = 0
                case 1: raw.header.domain = 2
                case 2: raw.header.phase = 2
                case 3: raw.header.count = 223
                case 4: raw.atoms.append(raw.atoms[0])
                case 5: raw.metadata.revision = 58
                case 6: raw.metadata.invocation = q.invocation + 1
                case 7: raw.metadata.peer = 78
                case 8: raw.metadata.read_count = 1
                case 9: raw.metadata.rtt_fault = 0
                case 10: raw.metadata.scope = 2
                case 11: raw.outcome.prepared_present = 0
                case 12: raw.outcome.reserved = 1
                case 13: raw.outcome.invocation = q.invocation + 1
                case 14: raw.edits.removeLast()
                case 15: raw.coordinates.append(.init())
                case 16: raw.reads.removeLast()
                case 17: raw.reads[0].abi = 1
                case 18: raw.atoms[168].low = 78
                case 19: raw.atoms[169].low = 58
                case 20: raw.atoms[170].low = 58
                case 21: raw.atoms[171].low = 1
                case 22: raw.atoms[185].low = 2
                default: return self.terminalRaw(raw, inputs: false)
                }
                return raw
            })
            XCTAssertThrowsError(try b.testTerminalPreparedValue(value, report: report), "mode=\(mode)")
            XCTAssertNoThrow(try b.testTerminalPreparedValue(value, report: report), "recovery mode=\(mode)")
        }
    }

    func testTerminalPrepareRejectsInventedClockOriginsOpaqueChangesAndRoutePresence() throws {
        let anchor = ContinuousClock().now, value = terminalFixture(at: ContinuousClock().now)
        let report = terminalReport()
        for mode in 0..<11 {
            let b = Boundary(testClock: { anchor }, testPrepareProducer: { q,s,r,t,c in
                var raw = try Boundary.actualPrepare(q,s,r,t,c)
                switch mode {
                case 0: raw.edits[0].action = 3
                case 1: raw.edits[0].source = 1
                case 2: raw.edits[2].action = 1
                case 3: raw.coordinates[0].reserved = 1
                case 4: raw.edits[12].action = 1
                case 5: raw.atoms[144].low = 1
                case 6: raw.atoms[42].low ^= 1
                case 7: raw.atoms[5].low = 1
                case 8: raw.atoms[89].low = 0
                case 9: raw.atoms[166].low = 1 // original startup is inactive
                default: raw.edits[5].action = 2; raw.coordinates[5] = .init()
                }
                return raw
            })
            XCTAssertThrowsError(try b.testTerminalPreparedValue(value, report: report), "mode=\(mode)")
        }
    }

    func testPreparedNative54TailLosslesslyRoundtripsEveryFieldAndIEEEPayload() throws {
        let anchor = ContinuousClock().now
        let prefix = Array(try Snapshot.capture(terminalFixture(at: anchor)).atoms.prefix(168))
        // Deliberately distinct full54 values. Nil versus IEEE NaN/signed zero,
        // UInt64.max UTC microseconds and negative signed counters stay exact.
        let tail: [Atom] = [
            atom(1,55), atom(1,.max), atom(1,8), atom(6,1), atom(4,0), atom(4,1),
            atom(4,1), atom(7,2), atom(2,UInt64(bitPattern: -31)), atom(2,32), atom(2,33), atom(3,0x7ff80000000000a1),
            atom(7,3), atom(2,41), atom(2,42), atom(2,43), atom(3,0x8000000000000000), atom(6,2),
            atom(4,1), atom(1,101), atom(4,1), atom(4,0), atom(4,1), atom(4,0), atom(2,UInt64(bitPattern: -102)),
            atom(1,103), atom(1,104), atom(1,.max), atom(1,106), atom(1,107),
            atom(3,0x7ff80000000000b2), atom(3,0x8000000000000000), atom(1,110), atom(2,111), atom(2,112),
            atom(6,3), atom(6,3), atom(6,19), atom(6,3), atom(1,117), atom(6,9), atom(4,0),
            atom(4,1), atom(6,13), atom(7,7), atom(1,203), atom(1,204), atom(1,205),
            atom(2,UInt64(bitPattern: -206)), atom(2,207), atom(1,208), atom(1,209), atom(1,210), atom(1,211)]
        XCTAssertEqual(tail.count, 54)
        XCTAssertTrue(Snapshot.equalAtoms(try Boundary.testPreparedTailRoundtrip(prefix + tail), tail))
        for index in [171,174,175,185,186,204,206,208,210,211,212] {
            var malformed = prefix + tail
            malformed[index].low = .max
            XCTAssertThrowsError(try Boundary.testPreparedTailRoundtrip(malformed), "index=\(index)")
        }
        var absent = prefix + terminalExpectedTail()
        absent[187].low = 1 // hidden absent payload is not a valid Optional.
        XCTAssertThrowsError(try Boundary.testPreparedTailRoundtrip(absent))
    }

    func testTerminalPrepareNestedAPIsPoisonEvenWhenCaughtAndConsumeInvocation() throws {
        let anchor = ContinuousClock().now, value = terminalFixture(at: ContinuousClock().now)
        let report = terminalReport()
        for mode in 0..<3 {
            var clocks = 0, calls = 0
            var b: Boundary!
            b = Boundary(testClock: {
                clocks += 1
                if clocks == 1 {
                    switch mode {
                    case 0: _ = try? b.propose(value, event: .stopSampling)
                    case 1: _ = try? b.proposeClocked(value, event: .endShowWithoutRevision)
                    default: _ = try? b.testTerminalPreparedValue(value, report: report)
                    }
                }
                return anchor
            }, testPrepareProducer: { q,s,r,t,c in
                calls += 1; XCTAssertEqual(q.invocation, 2)
                return try Boundary.actualPrepare(q,s,r,t,c)
            })
            XCTAssertThrowsError(try b.testTerminalPreparedValue(value, report: report))
            XCTAssertEqual(calls, 0)
            XCTAssertNoThrow(try b.testTerminalPreparedValue(value, report: report))
            XCTAssertEqual(calls, 1); XCTAssertEqual(clocks, 2)
        }
    }

    func testTerminalPrepareUnexpectedCallbackStickyPoisonsEvenValidReturnedDraft() throws {
        try assertInactiveTerminalReentry()
        try assertBeginActiveClockDenialAndReentry()
        let anchor = ContinuousClock().now, value = terminalFixture(at: ContinuousClock().now)
        let report = terminalReport()
        var calls = 0, clocks = 0
        let b = Boundary(testClock: { clocks += 1; return anchor }, testPrepareProducer: { q,s,r,t,c in
            calls += 1
            let raw = try Boundary.actualPrepare(q,s,r,t,c)
            if calls == 1 { XCTAssertEqual(c.testUnexpectedRequest(), 0) }
            return raw
        })
        XCTAssertThrowsError(try b.testTerminalPreparedValue(value, report: report))
        XCTAssertNoThrow(try b.testTerminalPreparedValue(value, report: report))
        XCTAssertEqual(calls, 2); XCTAssertEqual(clocks, 2)
    }

    func testPreparedUseWrongBoundaryBurnsAndPureLedgerRejectsReplay() throws {
        let b = Boundary(), other = Boundary()
        let (identity, consume) = b.testPreparedOneUse()
        XCTAssertNoThrow(try consume(identity))
        XCTAssertThrowsError(try consume(identity))
        let (_, rejected) = b.testPreparedOneUse()
        XCTAssertThrowsError(try rejected(other))
        XCTAssertThrowsError(try rejected(identity))
        // Pure private-use ledger only: this cannot construct an actual receipt.
        let exhausted = Boundary(), consumeExhausted = exhausted.testPreparedGuardUse(exhausted: true)
        XCTAssertThrowsError(try consumeExhausted(exhausted)) { error in
            guard case BelugaNetworkAdaptationOwnerError.invocationExhausted = error else {
                return XCTFail("first call must reach exhausted guard")
            }
        }
        XCTAssertThrowsError(try consumeExhausted(exhausted)) { error in
            guard case BelugaNetworkAdaptationOwnerError.refused = error else {
                return XCTFail("receipt must already be spent before exhaustion")
            }
        }
        var busy: Boundary!, consumeBusy: ((Boundary) throws -> Void)!
        busy = Boundary(testProducer: { q,s in
            do { try consumeBusy(busy) } catch BelugaNetworkAdaptationOwnerError.reentry { }
            return try Boundary.actual(q,s)
        })
        consumeBusy = busy.testPreparedGuardUse()
        XCTAssertThrowsError(try busy.propose(fixture(), event: .stopSampling))
        XCTAssertThrowsError(try consumeBusy(busy)) // nested guard denial burns too
        for foreign in [false, true] {
            var outer: Boundary!, nested: ((Boundary) throws -> Void)!
            outer = Boundary(testProducer: { q,s in
                do { try nested(outer) } catch BelugaNetworkAdaptationOwnerError.refused { }
                return try Boundary.actual(q,s)
            })
            let origin = foreign ? Boundary() : outer!
            nested = origin.testPreparedGuardUse()
            if !foreign { try nested(origin) } // already spent on nested entry
            XCTAssertThrowsError(try outer.propose(fixture(), event: .stopSampling)) { error in
                guard case BelugaNetworkAdaptationOwnerError.reentry = error else {
                    return XCTFail("swallowed spent/foreign entry must poison outer")
                }
            }
            XCTAssertThrowsError(try nested(origin)) // wrong-origin nested attempt also burned
        }
    }

    func testTerminalPrepareClockThrowConsumesInvocationAndReleasesGuard() throws {
        enum Denial: Error { case denied }
        let anchor = ContinuousClock().now, value = terminalFixture(at: ContinuousClock().now)
        let report = terminalReport()
        var clocks = 0, calls = 0
        let b = Boundary(testClock: {
            clocks += 1; if clocks == 1 { throw Denial.denied }; return anchor
        }, testPrepareProducer: { q,s,r,t,c in
            calls += 1; XCTAssertEqual(q.invocation, 2)
            return try Boundary.actualPrepare(q,s,r,t,c)
        })
        XCTAssertThrowsError(try b.testTerminalPreparedValue(value, report: report))
        XCTAssertEqual(calls, 0)
        XCTAssertNoThrow(try b.testTerminalPreparedValue(value, report: report))
        XCTAssertEqual(calls, 1); XCTAssertEqual(clocks, 2)
    }
}

extension BelugaNetworkAdaptationOwnerCodecTests {
    // ORIGINAL native Swift policy is the independent decision reference here,
    // not a candidate Owner reducer/result decoder. Implicit helper cuts in
    // these fixtures clear/retain absent RTT stamps; all assigned stamps use
    // the separately scheduled explicit observedAt below. Native-resource/actor
    // authority is deliberately outside this copied-value fixture's scope.
    private func assertGeneralPrepareOriginalReferenceParity() throws {
        let anchor = ContinuousClock().now, observed = anchor.advanced(by: .milliseconds(500))
        let report = terminalReport()
        for mode in 0..<7 {
            var policy = terminalFixture(at: anchor, fault: false).policy
            if mode == 1 { policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000, baseFramesPerSecond: 60) }
            if mode == 3 || mode == 5 { policy.networkAdaptationOwnerSeedClockedProbe() }
            if mode == 4 || mode == 6 { policy.networkAdaptationOwnerSeedClockedRetainedRTTFault() }
            let capacity = mode == 2 || mode == 3
            let expiry = mode >= 4
            let snapshot: WebRTCStatisticsSnapshot? = expiry ? nil : report.nativeSnapshot
            let timestamp: Double? = mode == 0 || expiry ? nil : (mode == 2 ? 0 : 17.25)
            let revision: UInt64 = mode == 6 ? .max : 57
            let value = Value(policy: policy, revision: revision, fastStatisticsAvailable: true,
                lane: .ordinaryFallback, evidenceTime: anchor, minimumCollectionSequence: 80,
                applied: mode == 5 ? policy.currentRecommendation : terminalFixture(at: anchor).applied)
            let before = try Snapshot.capture(value)
            XCTAssertNil(before.times[8], "fixture implicit cuts must not retain an unclocked RTT advancement")
            var reference = policy
            var floor: WorldwideScreenFloorRecoveryDiagnostics?
            var capacityDiagnostics: WorldwideScreenCapacityProbeDiagnostics?
            let changed: WorldwideScreenVideoEncodingRecommendation?
            if let snapshot, capacity {
                changed = reference.updateCapacityProbe(peerGeneration: 77, isCaptureActive: true,
                    availableOutgoingBitrateBps: snapshot.availableOutgoingBitrate,
                    currentRoundTripTimeSeconds: snapshot.currentRoundTripTime,
                    roundTripTimeObservation: snapshot.roundTripTimeObservation,
                    collectionSequence: snapshot.collectionSequence, nativeReportTimestampMicroseconds: timestamp,
                    selectedRoute: snapshot.route, outboundVideoPacketsSent: snapshot.outboundVideo?.packets,
                    outboundVideoTotalPacketSendDelaySeconds: snapshot.outboundVideo?.totalPacketSendDelay,
                    observedAt: observed, diagnostics: { capacityDiagnostics = $0 })
            } else if let snapshot {
                changed = reference.update(peerGeneration: 77, isCaptureActive: true,
                    availableOutgoingBitrateBps: snapshot.availableOutgoingBitrate,
                    currentRoundTripTimeSeconds: snapshot.currentRoundTripTime,
                    roundTripTimeObservation: snapshot.roundTripTimeObservation,
                    collectionSequence: snapshot.collectionSequence, requireRoundTripTimeObservation: true,
                    selectedRoute: snapshot.route, outboundVideoPacketsSent: snapshot.outboundVideo?.packets,
                    outboundVideoTotalPacketSendDelaySeconds: snapshot.outboundVideo?.totalPacketSendDelay,
                    nativeReportTimestampMicroseconds: timestamp, observedAt: observed, diagnostics: { floor = $0 })
            } else {
                changed = reference.expireApplicationLimitedProbeWithoutReport(peerGeneration: 77,
                    isCaptureActive: true, observedAt: observed)
            }
            var clockCount = 0, sites: [UInt32] = []
            let b = Boundary(testClock: { clockCount += 1; return observed }, testGeneralPrepareProducer: { q,s,r,t,c in
                let result = try Boundary.actualGeneralPrepare(q,s,r,t,c)
                sites = Array(result.reads.prefix(Int(result.metadata.read_count))).map(\.site)
                return result
            })
            let draft = try b.testGeneralPreparedValue(value, snapshot: snapshot, nativeTimestamp: timestamp,
                expectedRevision: revision, capacityOnly: capacity)
            let shouldPrepare = !expiry || changed != nil || value.applied != reference.currentRecommendation
                || (reference.hasNativeAdaptationPolicyFault && !policy.hasNativeAdaptationPolicyFault)
            XCTAssertEqual(draft != nil, shouldPrepare, "mode=\(mode)")
            XCTAssertEqual(clockCount, sites.count + 1)
            if mode == 1 { XCTAssertEqual(Array(sites.prefix(5)), [2, 0, 1, 0, 1]) }
            if capacity || expiry { XCTAssertTrue(sites.isEmpty || sites == [2]) }
            guard let draft else { continue }
            XCTAssertEqual(draft.clockInstants, Array(repeating: observed, count: sites.count))
            XCTAssertEqual(draft.report.timestamp?.bitPattern, timestamp?.bitPattern)
            XCTAssertEqual(draft.report.wire.native_timestamp_present, timestamp == nil ? 0 : 1)
            XCTAssertEqual(draft.report.incomingRoute, snapshot?.route)
            XCTAssertEqual(draft.report.retainedRoute, before.route)
            XCTAssertEqual(draft.source.times, before.times); XCTAssertEqual(draft.source.route, before.route)
            var expected = BelugaNetworkAdaptationOwnerWriter(anchor: draft.source.anchor)
            try reference.networkAdaptationOwnerWrite(into: &expected)
            // Independently constructed full54 continuation, from the original
            // reference's native diagnostics/getters, never the candidate tail.
            expected.unsigned(77); expected.unsigned(revision); expected.unsigned(revision)
            expected.u32(expiry ? 2 : (capacity ? 1 : 0)); expected.boolean(true); expected.boolean(capacity)
            expected.boolean(changed != nil)
            func recommendation(_ r: WorldwideScreenVideoEncodingRecommendation?, into w: inout BelugaNetworkAdaptationOwnerWriter) {
                w.tier(r?.tier); w.integer(r?.maximumBitrateBps); w.integer(r?.maximumTotalRTPBitrateBps)
                w.integer(r?.maximumFramesPerSecond); w.scalar(r?.scaleResolutionDownBy)
            }
            recommendation(changed, into: &expected)
            recommendation(changed ?? reference.currentRecommendation, into: &expected)
            let routeCode: UInt32 = (!expiry && !capacity && (reference.selectedRoute != before.route || policy.peerGeneration != 77))
                ? (reference.selectedRoute == nil ? 1 : 2) : 0
            expected.u32(routeCode); expected.boolean(floor != nil)
            if let floor { floor.networkAdaptationOwnerWritePrepared(into: &expected) }
            else { for kind: UInt32 in [1,4,4,4,4,2,1,1,1,1,1,3,3,1,2,2,6,6,6,6,1,6,4] { expected.word(kind, nil) } }
            expected.boolean(capacityDiagnostics != nil)
            if let capacityDiagnostics { capacityDiagnostics.networkAdaptationOwnerWritePrepared(into: &expected) }
            else { for kind: UInt32 in [6,7,1,1,1,2,2,1,1,1,1] { expected.word(kind, nil) } }
            XCTAssertEqual(expected.atoms.count, 222)
            XCTAssertTrue(Snapshot.equalAtoms(draft.atoms, expected.atoms), "full222 parity mode=\(mode)")
            XCTAssertEqual(draft.policyTimes, Array(reference.networkAdaptationOwnerNativeTimes.prefix(9)))
            let after = try Snapshot.capture(value, retainingAnchor: before.anchor)
            XCTAssertTrue(Snapshot.equalAtoms(after.atoms, before.atoms)); assertRetainedSidecars(after, before)
        }
        // A second, literal full222 reference checks the shared native serializer
        // as well as the general bridge; it does not depend on original.update.
        let terminal = terminalFixture(at: anchor)
        let original = try Snapshot.capture(terminal)
        let draft = try XCTUnwrap(Boundary(testClock: { observed }, testGeneralPrepareProducer: Boundary.actualGeneralPrepare)
            .testGeneralPreparedValue(terminal, snapshot: report.nativeSnapshot, nativeTimestamp: 17.25))
        var literal = Array(original.atoms.prefix(168))
        literal[5] = atom(2, 0); literal[9] = atom(2, 0); literal[25] = atom(4, 0)
        literal[26] = atom(7, nil); literal[27] = atom(2, nil); literal[28] = atom(10, nil)
        literal.append(contentsOf: terminalExpectedTail())
        XCTAssertTrue(Snapshot.equalAtoms(draft.atoms, literal))
    }

    private func assertGeneralPrepareClosedControls() throws {
        let anchor = ContinuousClock().now, report = terminalReport()
        let terminal = terminalFixture(at: anchor)
        for mode in 0..<22 {
            var calls = 0
            let b = Boundary(testClock: { anchor }, testGeneralPrepareProducer: { q,s,r,t,c in
                calls += 1
                var raw = try Boundary.actualGeneralPrepare(q,s,r,t,c)
                if calls == 2 { return raw }
                switch mode {
                case 0: raw.header.domain = 2
                case 1: raw.metadata.invocation &+= 1
                case 2: raw.metadata.read_count = 1
                case 3: raw.metadata.route = 1
                case 4: raw.atoms[90].low &+= 1
                case 5: raw.atoms[60].low ^= 1 // ORIGINAL sticky-fault RTT remains opaque
                case 6: raw.atoms[89].low = 0
                case 7: raw.atoms[140].low = 1 // ORIGINAL terminal branch skips demand selection
                case 8: raw.edits[2].source = 3
                case 9: raw.edits[2].action = 3
                case 10: raw.edits[9].action = 1
                case 11: raw.coordinates[9].present = 1
                case 12: raw.reads[0].abi = 1
                case 13: raw.atoms[171].low = 1
                case 14: raw.atoms[172].low = 0
                case 15: raw.atoms[185].low = 2
                case 16: raw.atoms[168].low &+= 1
                case 17: raw.outcome.prepared_present = 0
                case 18: raw.outcome.reserved = 1
                case 19: raw.atoms[41].low = .max // malformed fault must reject, never narrow/trap
                case 20: raw.atoms[89].low = .max
                default: return self.terminalRaw(raw, inputs: false)
                }
                return raw
            })
            XCTAssertThrowsError(try b.testGeneralPreparedValue(terminal, snapshot: report.nativeSnapshot, nativeTimestamp: 17.25), "mode=\(mode)")
            XCTAssertNoThrow(try b.testGeneralPreparedValue(terminal, snapshot: report.nativeSnapshot, nativeTimestamp: 17.25), "recovery mode=\(mode)")
        }
        var inactiveCalls = 0
        let inactive = Boundary(testClock: { anchor }, testGeneralPrepareProducer: { q,s,r,t,c in
            inactiveCalls += 1
            var raw = try Boundary.actualGeneralPrepare(q,s,r,t,c)
            if inactiveCalls == 1 {
                XCTAssertEqual(raw.atoms[174].low, 0)
                raw.atoms[174].low = 1
                // Forge an otherwise shaped changed recommendation equal to
                // the actual current getter. Inactive cannot publish changed.
                for i in 0..<5 { raw.atoms[175 + i] = raw.atoms[180 + i] }
            }
            return raw
        })
        XCTAssertThrowsError(try inactive.testGeneralPreparedValue(terminal,
            snapshot: report.nativeSnapshot, nativeTimestamp: 17.25, active: false))
        XCTAssertNoThrow(try inactive.testGeneralPreparedValue(terminal,
            snapshot: report.nativeSnapshot, nativeTimestamp: 17.25, active: false))
        // Healthy injected dependencies may be individually valid yet cannot
        // borrow the canonical producer's Owner501 application authority.
        for lane in 0..<3 {
            let p = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000,
                baseFramesPerSecond: 60, roundTripTimeProducer: { beluga_core_rtt_evidence_step($0, $1) })
            let value = Value(policy: p, revision: 57, fastStatisticsAvailable: true, lane: nil,
                evidenceTime: anchor, minimumCollectionSequence: nil, applied: nil)
            var clocks = 0, calls = 0
            let b = Boundary(testClock: { clocks += 1; return anchor }, testGeneralPrepareProducer: { q,s,r,t,c in
                calls += 1; return try Boundary.actualGeneralPrepare(q,s,r,t,c)
            })
            XCTAssertThrowsError(try b.testGeneralPreparedValue(value, snapshot: lane == 2 ? nil : report.nativeSnapshot,
                capacityOnly: lane == 1))
            XCTAssertEqual(clocks, 0); XCTAssertEqual(calls, 0)
        }
        let injected = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000,
            baseFramesPerSecond: 60, tierDemandProducer: { beluga_core_tier_demand_project($0) })
        let v = Value(policy: injected, revision: 57, fastStatisticsAvailable: true, lane: nil,
            evidenceTime: anchor, minimumCollectionSequence: nil, applied: nil)
        XCTAssertFalse(injected.networkAdaptationOwnerDemandApplicationIsAdmitted)
        XCTAssertThrowsError(try Boundary().testGeneralPreparedValue(v, snapshot: report.nativeSnapshot))

        let healthy = terminalFixture(at: anchor, fault: false)
        for sequence: [UInt32] in [[3], [4], [1], [0, 0], [0, 2]] {
            var clocks = 0
            let f = try Boundary(testClock: { clocks += 1; return anchor }).testGeneralClock(healthy)
            for (ordinal, site) in sequence.enumerated() {
                let result = f.testRequest(invocation: 1, site: site, ordinal: UInt32(ordinal))
                XCTAssertEqual(result, ordinal == sequence.count - 1 ? 0 : 1)
            }
            XCTAssertEqual(clocks, sequence.count - 1)
        }
        var clocks = 0
        let capacity = try Boundary(testClock: { clocks += 1; return anchor }).testGeneralClock(healthy, capacityOnly: true)
        XCTAssertEqual(capacity.testRequest(invocation: 1, site: 2, ordinal: 0), 0)
        XCTAssertEqual(clocks, 0, "no ORIGINAL probe origin grants no Capacity Q")
        let wrongInvocation = try Boundary(testClock: { clocks += 1; return anchor }).testGeneralClock(healthy)
        XCTAssertEqual(wrongInvocation.testRequest(invocation: 2, site: 2, ordinal: 0), 0)
        XCTAssertEqual(clocks, 0)
    }

    private func assertGeneralPrepareReadBearingNoneAndClockFailures() throws {
        let anchor = ContinuousClock().now, observed = anchor.advanced(by: .seconds(1))
        var p = terminalFixture(at: anchor, fault: false).policy
        p.networkAdaptationOwnerSeedClockedExpiredProbe(at: anchor)
        let v = Value(policy: p, revision: 57, fastStatisticsAvailable: true, lane: nil,
            evidenceTime: anchor, minimumCollectionSequence: nil, applied: p.currentRecommendation)
        var original = p
        XCTAssertNil(original.expireApplicationLimitedProbeWithoutReport(peerGeneration: 77,
            isCaptureActive: true, observedAt: observed))
        XCTAssertNil(original.networkAdaptationOwnerNativeTimes[0])
        let before = try Snapshot.capture(v)
        var clocks = 0, sites: [UInt32] = []
        let none = Boundary(testClock: { clocks += 1; return observed }, testGeneralPrepareProducer: { q,s,r,t,c in
            let raw = try Boundary.actualGeneralPrepare(q,s,r,t,c)
            XCTAssertEqual(raw.status, 1); XCTAssertEqual(raw.outcome.prepared_present, 0)
            XCTAssertTrue(raw.inputsUnchanged)
            sites = Array(raw.reads.prefix(Int(raw.metadata.read_count))).map(\.site)
            return raw
        })
        XCTAssertNil(try none.testGeneralPreparedValue(v, snapshot: nil))
        XCTAssertEqual(sites, [2]); XCTAssertEqual(clocks, 2)
        let after = try Snapshot.capture(v, retainingAnchor: before.anchor)
        XCTAssertTrue(Snapshot.equalAtoms(before.atoms, after.atoms)); assertRetainedSidecars(before, after)

        var queue = terminalFixture(at: anchor, fault: false).policy
        queue.networkAdaptationOwnerSeedClockedOpaqueQueueAndRTTFault(at: anchor)
        let opaque = Value(policy: queue, revision: 57, fastStatisticsAvailable: true, lane: nil,
            evidenceTime: anchor, minimumCollectionSequence: nil, applied: nil)
        let qBefore = try Snapshot.capture(opaque)
        XCTAssertLessThan(Int64(bitPattern: qBefore.atoms[38].low), 0)
        let qDraft = try XCTUnwrap(Boundary(testClock: { observed }).testGeneralPreparedValue(opaque,
            snapshot: terminalReport().nativeSnapshot))
        XCTAssertTrue(qDraft.clockInstants.isEmpty, "bound terminal/no origin has no Q capability")
        XCTAssertTrue(Snapshot.equalAtoms(Array(qBefore.atoms[36...41]), Array(qDraft.atoms[36...41])))

        let fresh = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000,
            baseFramesPerSecond: 60)
        let unbound = Value(policy: fresh, revision: 57, fastStatisticsAvailable: true, lane: nil,
            evidenceTime: anchor, minimumCollectionSequence: nil, applied: nil)
        for phase in 1...6 { // explicit observedAt plus genuine Q,E,A,E,A prefix
            var clockCalls = 0, producerCalls = 0, fail = true
            let b = Boundary(testClock: {
                clockCalls += 1
                if fail && clockCalls == phase { throw BelugaNetworkAdaptationOwnerError.refused }
                return observed
            }, testGeneralPrepareProducer: { q,s,r,t,c in
                producerCalls += 1
                let raw = try Boundary.actualGeneralPrepare(q,s,r,t,c)
                if fail {
                    XCTAssertEqual(raw.status, 3)
                    XCTAssertTrue(raw.inputsUnchanged); XCTAssertTrue(raw.deniedOutputsUntouched)
                }
                return raw
            })
            XCTAssertThrowsError(try b.testGeneralPreparedValue(unbound, snapshot: terminalReport().nativeSnapshot))
            XCTAssertEqual(clockCalls, phase); XCTAssertEqual(producerCalls, phase == 1 ? 0 : 1)
            fail = false
            XCTAssertNoThrow(try b.testGeneralPreparedValue(unbound, snapshot: terminalReport().nativeSnapshot))
        }
        var b: Boundary!
        var clockCalls = 0, reenter = true
        let nestedTerminal = terminalFixture(at: anchor)
        b = Boundary(testClock: {
            clockCalls += 1
            if reenter && clockCalls == 2 {
                // Even a swallowed cross-family nested error poisons the
                // original clock span before the first read can be granted.
                XCTAssertThrowsError(try b.testTerminalPreparedValue(nestedTerminal, report: self.terminalReport()))
            }
            return observed
        })
        XCTAssertThrowsError(try b.testGeneralPreparedValue(unbound, snapshot: terminalReport().nativeSnapshot))
        XCTAssertEqual(clockCalls, 2)
        reenter = false
        XCTAssertNoThrow(try b.testGeneralPreparedValue(unbound, snapshot: terminalReport().nativeSnapshot))
    }
}

// Actual imported701 plus handwritten whole-state expectations. These remain
// in the ordinary registry; copied drafts are not native actor/await authority.
extension BelugaNetworkAdaptationOwnerCodecTests {
    private func beginFixture() throws -> (BelugaNetworkAdaptationGeneralPreparedValue, Value) {
        let anchor = ContinuousClock().now
        let prepared = try XCTUnwrap(Boundary(testClock: { anchor }).testGeneralPreparedValue(
            terminalFixture(at: anchor), snapshot: terminalReport().nativeSnapshot, nativeTimestamp: 17.25))
        return (prepared, terminalFixture(at: anchor, fault: false))
    }
    private func beginRaw(_ r: Boundary.BeginActiveRawResult, status: UInt32? = nil,
        inputs: Bool? = nil, untouched: Bool? = nil) -> Boundary.BeginActiveRawResult {
        .init(status: status ?? r.status, header: r.header, atoms: r.atoms,
            preparedHeader: r.preparedHeader, preparedAtoms: r.preparedAtoms,
            metadata: r.metadata, outcome: r.outcome, edits: r.edits, coordinates: r.coordinates,
            reads: r.reads, inputsUnchanged: inputs ?? r.inputsUnchanged,
            deniedOutputsUntouched: untouched ?? r.deniedOutputsUntouched)
    }
    private func assertBeginActiveGoldenAndNativeCustody() throws {
        let (prepared, value) = try beginFixture()
        let current = try Snapshot.capture(value, retainingAnchor: prepared.source.anchor)
        XCTAssertTrue(Boundary.beginActiveLayoutIsExact)
        // Original same-peer fault latch only: no Q without a probe origin.
        // Resource denial happens AFTER the restrictive negative draft.
        for missing in 0..<6 {
            var clocks = 0
            let b = Boundary(testClock: { clocks += 1; return prepared.observedAt },
                testBeginActiveProducer: Boundary.actualBeginActive)
            let out = try b.testBeginActive(prepared, current: current, resourceFlags: 63 ^ (1 << missing))
            XCTAssertEqual(out.disposition, .returned); XCTAssertNil(out.prepared)
            var expected = current.atoms; expected[89] = atom(4, 1); expected[168] = atom(1, 58)
            assertWhole(out.replacement, expected); assertRetainedSidecars(out.replacement, current)
            XCTAssertEqual(clocks, 0)
        }
        for appliedMatches in [false, true] {
            let v = Value(policy: value.policy, revision: .max, fastStatisticsAvailable: value.fastStatisticsAvailable,
                lane: value.lane, evidenceTime: value.evidenceTime, minimumCollectionSequence: value.minimumCollectionSequence,
                applied: appliedMatches ? prepared.tail.recommendation : value.applied)
            let s = try Snapshot.capture(v, retainingAnchor: prepared.source.anchor)
            var clocks = 0
            let b = Boundary(testClock: { clocks += 1; return prepared.observedAt },
                testBeginActiveProducer: Boundary.actualBeginActive)
            let out = try b.testBeginActive(prepared, current: s, resourceFlags: appliedMatches ? 0 : 63)
            XCTAssertEqual(out.disposition, appliedMatches ? .noNativeApply : .apply)
            var expected = s.atoms; expected[89] = atom(4, 1); expected[168] = atom(1, 0)
            assertWhole(out.replacement, expected); assertRetainedSidecars(out.replacement, s)
            let p = try XCTUnwrap(out.prepared)
            var expectedPrepared = prepared.atoms; expectedPrepared[170] = atom(1, 0)
            XCTAssertTrue(Snapshot.equalAtoms(p.atoms, expectedPrepared))
            XCTAssertTrue(Snapshot.equalAtoms(p.source.atoms, prepared.source.atoms))
            XCTAssertEqual(p.source.route, prepared.source.route); XCTAssertEqual(p.source.times, prepared.source.times)
            XCTAssertEqual(p.source.anchor, prepared.source.anchor); XCTAssertEqual(p.policyTimes, prepared.policyTimes)
            XCTAssertEqual(p.clockInstants, prepared.clockInstants); XCTAssertEqual(p.observedAt, prepared.observedAt)
            XCTAssertEqual(p.report.retainedRoute, prepared.report.retainedRoute)
            XCTAssertEqual(p.report.incomingRoute, prepared.report.incomingRoute)
            XCTAssertEqual(clocks, 0)
        }
        // A current same-peer probe allows precisely ONE Q; binding a new
        // lifetime permits Q,E,A,E,A. No eager observedAt is added to701.
        for newPeer in [false, true] {
            var policy = value.policy
            if newPeer { policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000, baseFramesPerSecond: 60) }
            else { policy.networkAdaptationOwnerSeedClockedProbe() }
            let v = Value(policy: policy, revision: 57, fastStatisticsAvailable: true, lane: value.lane,
                evidenceTime: value.evidenceTime, minimumCollectionSequence: value.minimumCollectionSequence, applied: value.applied)
            let s = try Snapshot.capture(v, retainingAnchor: prepared.source.anchor)
            var clocks = 0, sites: [UInt32] = []
            let b = Boundary(testClock: { clocks += 1; return prepared.observedAt }, testBeginActiveProducer: { q,s,p,c in
                let raw = try Boundary.actualBeginActive(q,s,p,c)
                XCTAssertEqual(raw.status, 1); XCTAssertTrue(raw.inputsUnchanged)
                sites = Array(raw.reads.prefix(Int(raw.metadata.read_count))).map(\.site)
                let clearMask: UInt16 = newPeer ? 0x01ff : 0x00cf
                for i in 0..<13 {
                    XCTAssertEqual(raw.edits[i].action, i < 9 ? (clearMask & (1 << i) != 0 ? 2 : 1) : 0)
                }
                return raw
            })
            let out = try b.testBeginActive(prepared, current: s)
            XCTAssertEqual(out.disposition, .apply)
            XCTAssertEqual(sites, newPeer ? [2,0,1,0,1] : [2]); XCTAssertEqual(clocks, sites.count)
            var expected = s.atoms
            if newPeer { expected[3] = atom(1,77) }
            else {
                // The seeded probe reverts to its audioPriority origin (wire7), not survival (wire5).
                expected[4] = atom(7,7); expected[11] = atom(2,0)
                expected[20] = atom(7,nil); expected[22] = atom(7,nil)
                expected[156] = atom(4,1); expected[157] = atom(3,nil)
            }
            expected[89] = atom(4,1); expected[168] = atom(1,58)
            assertWhole(out.replacement, expected); assertRetainedSidecars(out.replacement, s)
            let p = try XCTUnwrap(out.prepared)
            var expectedPrepared = prepared.atoms; expectedPrepared[170] = atom(1,58)
            XCTAssertTrue(Snapshot.equalAtoms(p.atoms, expectedPrepared))
            XCTAssertEqual(p.policyTimes, prepared.policyTimes)
            XCTAssertEqual(p.source.route, prepared.source.route); XCTAssertEqual(p.source.times, prepared.source.times)
            XCTAssertEqual(p.source.anchor, prepared.source.anchor); XCTAssertEqual(p.clockInstants, prepared.clockInstants)
            XCTAssertEqual(p.observedAt, prepared.observedAt)
            XCTAssertEqual(p.report.retainedRoute, prepared.report.retainedRoute)
            XCTAssertEqual(p.report.incomingRoute, prepared.report.incomingRoute)
        }
        // Healthy Prepared does not transfer its route/timers into CURRENT.
        // CURRENT's stored NaN is nonreflexive under original Swift equality:
        // an otherwise byte-identical attempt advances revision exactly once.
        // The complete fixture supplies all nine native policy timers plus
        // a whole Optional route and an independently retained evidence time.
        let healthyPrepared = try XCTUnwrap(Boundary(testClock: { prepared.observedAt }).testGeneralPreparedValue(
            value, snapshot: terminalReport().nativeSnapshot, nativeTimestamp: 17.25))
        XCTAssertEqual(healthyPrepared.atoms[89].low, 0); XCTAssertEqual(healthyPrepared.atoms[140].low, 0)
        XCTAssertEqual(healthyPrepared.atoms[152].present, 0)
        let route = WebRTCICERouteDiagnostics(kind: .relayed,
            local: .init(type: .host, transport: "udp", networkType: "ethernet"),
            remote: .init(type: .relay, transport: "udp", relayProtocol: "tls"))
        var completePolicy = value.policy
        completePolicy.networkAdaptationOwnerSeedCompleteRegression(at: prepared.observedAt, route: route)
        let completeValue = Value(policy: completePolicy, revision: 57, fastStatisticsAvailable: false,
            lane: nil, evidenceTime: prepared.observedAt.advanced(by: .milliseconds(-625)),
            minimumCollectionSequence: .max, applied: value.applied)
        let complete = try Snapshot.capture(completeValue, retainingAnchor: healthyPrepared.source.anchor)
        XCTAssertTrue(complete.times.prefix(9).allSatisfy { $0 != nil }); XCTAssertNotNil(complete.route)
        var calls = 0
        let completeBoundary = Boundary(testClock: { XCTFail("nonterminal701 cannot sample a clock"); return prepared.observedAt },
            testBeginActiveProducer: { q,s,p,c in
                calls += 1
                var r = try Boundary.actualBeginActive(q,s,p,c)
                if calls == 1 {
                    r.edits[0].action = 2; r.coordinates[0] = .init()
                    r.atoms[12].present = 0; r.atoms[12].high = 0; r.atoms[12].low = 0
                }
                return r
            })
        XCTAssertThrowsError(try completeBoundary.testBeginActive(healthyPrepared, current: complete))
        let completeOut = try completeBoundary.testBeginActive(healthyPrepared, current: complete)
        XCTAssertEqual(completeOut.disposition, .apply)
        var expectedComplete = complete.atoms; expectedComplete[168] = atom(1, 58)
        assertWhole(completeOut.replacement, expectedComplete); assertRetainedSidecars(completeOut.replacement, complete)
        let completePrepared = try XCTUnwrap(completeOut.prepared)
        var expectedPrepared = healthyPrepared.atoms; expectedPrepared[170] = atom(1, 58)
        XCTAssertTrue(Snapshot.equalAtoms(completePrepared.atoms, expectedPrepared))
        XCTAssertEqual(completePrepared.policyTimes, healthyPrepared.policyTimes)
        XCTAssertEqual(completePrepared.source.route, healthyPrepared.source.route)
        XCTAssertEqual(completePrepared.source.times, healthyPrepared.source.times)
        XCTAssertEqual(completePrepared.clockInstants, healthyPrepared.clockInstants)
        XCTAssertEqual(calls, 2)
        // Distinct fault-retention and attempt-consumption revision cuts wrap
        // MAX -> 0 -> 1. The genuine501 Prepared carries the same Show-bound
        // consumed allowance, while CURRENT still retains a first witness.
        var wrapPolicy = value.policy
        wrapPolicy.networkAdaptationOwnerSeedRegression(at: prepared.observedAt, route: route)
        let attemptValue = Value(policy: wrapPolicy, revision: 57, fastStatisticsAvailable: true,
            lane: value.lane, evidenceTime: value.evidenceTime,
            minimumCollectionSequence: value.minimumCollectionSequence, applied: value.applied)
        let attemptPrepared = try XCTUnwrap(Boundary(testClock: { prepared.observedAt }).testGeneralPreparedValue(
            attemptValue, snapshot: terminalReport().nativeSnapshot, nativeTimestamp: 17.25))
        XCTAssertEqual(attemptPrepared.atoms[89].low, 0); XCTAssertEqual(attemptPrepared.atoms[140].low, 0)
        XCTAssertEqual(attemptPrepared.atoms[152].low, 88); XCTAssertEqual(attemptPrepared.atoms[155].low, 1)
        let attempt = try Snapshot.capture(attemptValue, retainingAnchor: attemptPrepared.source.anchor)
        let attemptBoundary = Boundary(testClock: { XCTFail("nonterminal attempt701 has zero clocks"); return prepared.observedAt },
            testBeginActiveProducer: { q,s,p,c in
                let r = try Boundary.actualBeginActive(q,s,p,c)
                for i in 0..<13 { XCTAssertEqual(r.edits[i].action, i < 9 ? (i == 3 ? 2 : 1) : 0) }
                return r
            })
        let attempted = try attemptBoundary.testBeginActive(attemptPrepared, current: attempt)
        XCTAssertEqual(attempted.disposition, .apply)
        var expectedAttempt = attempt.atoms
        expectedAttempt[158] = atom(4,0); expectedAttempt[159] = atom(10,nil)
        expectedAttempt[160] = atom(3,nil); expectedAttempt[168] = atom(1,58)
        assertWhole(attempted.replacement, expectedAttempt); assertRetainedSidecars(attempted.replacement, attempt, clearing: 3)
        let attemptReturned = try XCTUnwrap(attempted.prepared)
        var expectedAttemptPrepared = attemptPrepared.atoms; expectedAttemptPrepared[170] = atom(1,58)
        XCTAssertTrue(Snapshot.equalAtoms(attemptReturned.atoms, expectedAttemptPrepared))
        XCTAssertEqual(attemptReturned.policyTimes, attemptPrepared.policyTimes)
        XCTAssertEqual(attemptReturned.source.route, attemptPrepared.source.route)
        XCTAssertEqual(attemptReturned.source.times, attemptPrepared.source.times)
        XCTAssertEqual(attemptReturned.clockInstants, attemptPrepared.clockInstants)
        var faultPolicy = wrapPolicy; faultPolicy.networkAdaptationOwnerSeedClockedRetainedRTTFault()
        let wrapSource = Value(policy: faultPolicy, revision: .max, fastStatisticsAvailable: true,
            lane: value.lane, evidenceTime: value.evidenceTime,
            minimumCollectionSequence: value.minimumCollectionSequence, applied: value.applied)
        let wrapPrepared = try XCTUnwrap(Boundary(testClock: { prepared.observedAt }).testGeneralPreparedValue(
            wrapSource, snapshot: terminalReport().nativeSnapshot, nativeTimestamp: 17.25, expectedRevision: .max))
        let wrapValue = Value(policy: wrapPolicy, revision: .max, fastStatisticsAvailable: false,
            lane: nil, evidenceTime: value.evidenceTime, minimumCollectionSequence: .max, applied: value.applied)
        let wrap = try Snapshot.capture(wrapValue, retainingAnchor: wrapPrepared.source.anchor)
        XCTAssertEqual(wrapPrepared.atoms[89].low, 1); XCTAssertEqual(wrapPrepared.atoms[20].present, 0)
        XCTAssertEqual(wrapPrepared.atoms[152].low, 88); XCTAssertEqual(wrapPrepared.atoms[155].low, 1)
        XCTAssertEqual(wrapPrepared.atoms[161].low, 190); XCTAssertEqual(wrapPrepared.atoms[162].low, (-0.0).bitPattern)
        XCTAssertEqual(wrap.atoms[89].low, 0); XCTAssertEqual(wrap.atoms[20].present, 0)
        XCTAssertEqual(wrap.atoms[158].low, 1)
        let wrapBoundary = Boundary(testClock: { XCTFail("same-peer wrap701 has no clock cuts"); return prepared.observedAt },
            testBeginActiveProducer: { q,s,p,c in
                let r = try Boundary.actualBeginActive(q,s,p,c)
                for i in 0..<13 { XCTAssertEqual(r.edits[i].action, i < 9 ? (i == 2 || i == 3 ? 2 : 1) : 0) }
                return r
            })
        let wrapped = try wrapBoundary.testBeginActive(wrapPrepared, current: wrap)
        XCTAssertEqual(wrapped.disposition, .apply)
        var expectedWrap = wrap.atoms
        expectedWrap[5] = atom(2,0); expectedWrap[25] = atom(4,0)
        expectedWrap[26] = atom(7,nil); expectedWrap[27] = atom(2,nil); expectedWrap[28] = atom(10,nil)
        expectedWrap[89] = atom(4,1); expectedWrap[158] = atom(4,0)
        expectedWrap[159] = atom(10,nil); expectedWrap[160] = atom(3,nil); expectedWrap[168] = atom(1,1)
        assertWhole(wrapped.replacement, expectedWrap)
        var wrapTimes = wrap.times; wrapTimes[2] = nil; wrapTimes[3] = nil
        XCTAssertEqual(wrapped.replacement.times, wrapTimes); XCTAssertEqual(wrapped.replacement.route, wrap.route)
        XCTAssertEqual(wrapped.replacement.anchor, wrap.anchor)
        let wrapReturned = try XCTUnwrap(wrapped.prepared)
        var expectedWrapPrepared = wrapPrepared.atoms; expectedWrapPrepared[170] = atom(1,1)
        XCTAssertTrue(Snapshot.equalAtoms(wrapReturned.atoms, expectedWrapPrepared))
        XCTAssertEqual(wrapReturned.policyTimes, wrapPrepared.policyTimes)
        XCTAssertEqual(wrapReturned.source.route, wrapPrepared.source.route)
        XCTAssertEqual(wrapReturned.source.times, wrapPrepared.source.times)
        XCTAssertEqual(wrapReturned.clockInstants, wrapPrepared.clockInstants)
        let after = try Snapshot.capture(value, retainingAnchor: current.anchor)
        assertWhole(after, current.atoms); assertRetainedSidecars(after, current)
    }

    private func assertBeginActiveClosedControls() throws {
        let (prepared, value) = try beginFixture()
        let s = try Snapshot.capture(value, retainingAnchor: prepared.source.anchor)
        for mode in 0..<46 {
            var calls = 0, clocks = 0
            let b = Boundary(testClock: { clocks += 1; return prepared.observedAt }, testBeginActiveProducer: { q,s,p,c in
                calls += 1
                var r = try Boundary.actualBeginActive(q,s,p,c)
                if calls == 2 { return r }
                switch mode {
                case 0: return self.beginRaw(r, status: 9)
                case 1: r.header.phase = 1
                case 2: r.metadata.invocation &+= 1
                case 3: r.metadata.read_count = 1
                case 4: r.metadata.bound = 1
                case 5: r.outcome.reserved = 1
                case 6: r.outcome.prepared_present = 0
                case 7: r.outcome.disposition = 3
                case 8: r.outcome.route = 1
                case 9: r.preparedHeader.domain = 2
                case 10: r.preparedAtoms[170].low &+= 1
                case 11: r.preparedAtoms[0].low &+= 1
                case 12: r.preparedAtoms[221].low ^= 1
                case 13: r.atoms[169].low ^= 1
                case 14: r.atoms[178].low ^= 1
                case 15: r.atoms[151].low ^= 1
                case 16: r.atoms[60].low ^= 1
                case 17: r.atoms[38].low &+= 1
                case 18: r.edits[0].action = 3
                case 19: r.edits[4].action = 2
                case 20: r.edits[9].action = 1
                case 21: r.coordinates[12].present = 1
                case 22: r.coordinates[0].low = 1
                case 23: r.reads[14].abi = 1
                case 24: r.atoms[168].low &+= 3; r.metadata.revision = r.atoms[168].low
                case 25: return self.beginRaw(r, inputs: false)
                case 26: return self.beginRaw(r, status: 3, untouched: false)
                case 27: r.atoms[89].low = .max; r.metadata.rtt_fault = .max
                case 28: r.outcome.disposition = 0; r.outcome.prepared_present = 0
                // Preserve output/meta agreement: these must be rejected by
                // original negative-fact and no-op journal correlations.
                case 29: r.atoms[89].low = 0; r.metadata.rtt_fault = 0
                case 30: r.atoms[140].low = 1
                case 31: r.atoms[166].low = 1
                case 32: r.edits[5].action = 2
                case 33: r.header.count = 178
                case 34: r.preparedHeader.count = 221
                case 35: r.atoms.removeLast()
                case 36: r.preparedAtoms.removeLast()
                case 37: r.edits.removeLast()
                case 38: r.coordinates.removeLast()
                case 39: r.reads.removeLast()
                case 40: r.metadata.queue_fault = 1
                case 41: r.metadata.peer &+= 1
                case 42: r.metadata.peer_present = 0
                case 43: r.outcome.invocation &+= 1
                case 44: r.metadata.revision &+= 1
                default: r.outcome.operation = 702
                }
                return r
            })
            XCTAssertThrowsError(try b.testBeginActive(prepared, current: s), "701 malformed mode=\(mode)")
            XCTAssertNoThrow(try b.testBeginActive(prepared, current: s), "701 recovery mode=\(mode)")
            XCTAssertEqual(calls, 2); XCTAssertEqual(clocks, 0)
        }
        // A real rejected Demand producer supplies a demand-only Prepared.
        // Its fault must be retained by701 even while CURRENT is healthy; no
        // arbitrary inverse policy or valid-looking authority is fabricated.
        var demand = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000,
            baseFramesPerSecond: 60, tierDemandProducer: { facts in
                var actual = beluga_core_tier_demand_project(facts)
                actual.status ^= 1
                return actual
            })
        demand.bind(toPeerGeneration: 77)
        let demandSource = Value(policy: demand, revision: 57, fastStatisticsAvailable: true,
            lane: value.lane, evidenceTime: prepared.source.anchor,
            minimumCollectionSequence: value.minimumCollectionSequence, applied: value.applied)
        let demandPrepared = try XCTUnwrap(Boundary(testClock: { prepared.observedAt }).testGeneralPreparedValue(
            demandSource, snapshot: terminalReport().nativeSnapshot, nativeTimestamp: 17.25))
        XCTAssertEqual(demandPrepared.atoms[140].low, 1); XCTAssertEqual(demandPrepared.atoms[89].low, 0)
        var calls = 0
        let demandBoundary = Boundary(testClock: { XCTFail("same-peer demand-only retention has zero clocks"); return prepared.observedAt },
            testBeginActiveProducer: { q,s,p,c in
                calls += 1
                var r = try Boundary.actualBeginActive(q,s,p,c)
                XCTAssertEqual(r.atoms[140].low, 1)
                if calls == 1 { r.atoms[140].low = 0 }
                return r
            })
        XCTAssertThrowsError(try demandBoundary.testBeginActive(demandPrepared, current: s))
        XCTAssertNoThrow(try demandBoundary.testBeginActive(demandPrepared, current: s))
        XCTAssertEqual(calls, 2)
        for status: UInt32 in 2...5 {
            let b = Boundary(testClock: { XCTFail("denial has zero clock"); return prepared.observedAt },
                testBeginActiveProducer: { q,s,p,c in
                    var denied = q; denied.abi = 0
                    let r = try Boundary.actualBeginActive(denied,s,p,c)
                    XCTAssertTrue(r.deniedOutputsUntouched); XCTAssertTrue(r.inputsUnchanged)
                    return self.beginRaw(r, status: status)
                })
            XCTAssertThrowsError(try b.testBeginActive(prepared, current: s))
        }
    }

    private func assertBeginActiveClockDenialAndReentry() throws {
        let (prepared, value) = try beginFixture()
        let fresh = Value(policy: .init(configuredTotalRTPBitrateBps: 12_000_000, baseFramesPerSecond: 60),
            revision: 57, fastStatisticsAvailable: true, lane: value.lane, evidenceTime: value.evidenceTime,
            minimumCollectionSequence: value.minimumCollectionSequence, applied: value.applied)
        let current = try Snapshot.capture(fresh, retainingAnchor: prepared.source.anchor)
        for denial in 1...5 {
            var clocks = 0, fail = true
            let b = Boundary(testClock: {
                clocks += 1
                if fail && clocks == denial { throw BelugaNetworkAdaptationOwnerError.refused }
                return prepared.observedAt
            }, testBeginActiveProducer: { q,s,p,c in
                let r = try Boundary.actualBeginActive(q,s,p,c)
                if fail { XCTAssertEqual(r.status, 3); XCTAssertTrue(r.deniedOutputsUntouched); XCTAssertTrue(r.inputsUnchanged) }
                return r
            })
            XCTAssertThrowsError(try b.testBeginActive(prepared, current: current))
            XCTAssertEqual(clocks, denial); fail = false
            XCTAssertNoThrow(try b.testBeginActive(prepared, current: current))
            XCTAssertEqual(clocks, denial + 5)
        }
        var b: Boundary!, nested = true, clocks = 0
        b = Boundary(testClock: {
            clocks += 1
            if nested { XCTAssertThrowsError(try b.testBeginActive(prepared, current: current)) }
            return prepared.observedAt
        }, testBeginActiveProducer: Boundary.actualBeginActive)
        XCTAssertThrowsError(try b.testBeginActive(prepared, current: current))
        XCTAssertEqual(clocks, 1, "swallowed nested entry denies before later clocks")
        nested = false
        XCTAssertNoThrow(try b.testBeginActive(prepared, current: current))
        XCTAssertEqual(clocks, 6)
    }
}

// Literal601/copied-native import checks remain inside the existing registry.
// These do NOT construct a real actor receipt or prove a production store.
extension BelugaNetworkAdaptationOwnerCodecTests {
    private func inactiveFixture(revision: UInt64 = 57) throws -> (BelugaNetworkAdaptationTerminalPreparedValue, Snapshot) {
        let anchor = ContinuousClock().now
        let route = WebRTCICERouteDiagnostics(kind: .relayed,
            local: .init(type: .host, transport: "udp", networkType: "ethernet"),
            remote: .init(type: .relay, transport: "udp", relayProtocol: "tls"))
        var policy = terminalFixture(at: anchor).policy
        policy.networkAdaptationOwnerSeedRegression(at: anchor, route: route)
        let original = Value(policy: policy, revision: revision, fastStatisticsAvailable: true,
            lane: .ordinaryFallback, evidenceTime: anchor, minimumCollectionSequence: 80,
            applied: terminalFixture(at: anchor).applied)
        let prepared = try Boundary().testTerminalPreparedValue(original, report: terminalReport(),
            expectedRevision: revision, active: false)
        // Deliberately different current tail: adoption must retain current values,
        // not the prepared source's statistics/IEEE payload/minimum/evidence.
        let current = Value(policy: policy, revision: revision, fastStatisticsAvailable: false,
            lane: nil, evidenceTime: anchor.advanced(by: .milliseconds(-500)), minimumCollectionSequence: .max,
            applied: .init(tier: .high, maximumBitrateBps: -32, maximumTotalRTPBitrateBps: 654_321,
                maximumFramesPerSecond: 17, scaleResolutionDownBy: -0.0))
        return (prepared, try Snapshot.capture(current, retainingAnchor: prepared.source.anchor))
    }
    private func assertInactiveTerminalGolden() throws {
        XCTAssertTrue(Boundary.inactiveLayoutIsExact)
        for revision: UInt64 in [57, .max] {
            let (prepared, current) = try inactiveFixture(revision: revision)
            var calls = 0
            let b = Boundary(testInactiveProducer: { q,s,p,c in
                calls += 1
                let raw = try Boundary.actualInactive(q,s,p,c)
                XCTAssertEqual(raw.status, 1); XCTAssertTrue(raw.inputsUnchanged)
                let indices = [12,23,28,159,163,167,39,40,88]
                for i in 0..<13 {
                    let e = raw.edits[i], coordinate = raw.coordinates[i]
                    if i < 9 {
                        let a = p.atoms[indices[i]], present = a.present == 1
                        XCTAssertEqual(e.action, present ? 3 : 2)
                        XCTAssertEqual(e.source, present ? 2 : 0)
                        XCTAssertEqual(e.index, present ? UInt32(i) : 0)
                        XCTAssertEqual(coordinate.present, a.present)
                        XCTAssertEqual(coordinate.high, a.high); XCTAssertEqual(coordinate.low, a.low)
                    } else {
                        XCTAssertEqual(e.action, 0); XCTAssertEqual(e.source, 0); XCTAssertEqual(e.index, 0)
                        XCTAssertEqual(coordinate.present, 0); XCTAssertEqual(coordinate.high, 0); XCTAssertEqual(coordinate.low, 0)
                    }
                    XCTAssertEqual(e.ordinal, 0); XCTAssertEqual(e.high, 0); XCTAssertEqual(e.low, 0)
                    XCTAssertEqual(coordinate.reserved, 0)
                }
                XCTAssertEqual(raw.metadata.read_count, 0); XCTAssertEqual(raw.outcome.disposition, 1)
                return raw
            })
            guard case let .ready(adopted) = try b.testInactiveTerminal(prepared, current: current, suspended: true) else {
                return XCTFail("terminal fault cannot request native resume")
            }
            var expected = current.atoms
            expected.replaceSubrange(0..<168, with: prepared.atoms.prefix(168))
            expected[168] = atom(1, revision &+ 1)
            assertWhole(adopted, expected)
            var times = current.times; times.replaceSubrange(0..<9, with: prepared.policyTimes)
            XCTAssertEqual(adopted.times, times); XCTAssertEqual(adopted.anchor, current.anchor)
            XCTAssertEqual(adopted.route, current.route); XCTAssertEqual(calls, 1)
            XCTAssertEqual(adopted.value.applied?.scaleResolutionDownBy.bitPattern, 0x8000000000000000)
        }
        let (prepared, current) = try inactiveFixture()
        for (generation, exactPeer, revision) in [(UInt64(78), true, UInt64(57)), (77, false, 57), (77, true, 58)] {
            let v = current.value
            let changed = try Snapshot.capture(.init(policy: v.policy, revision: revision,
                fastStatisticsAvailable: v.fastStatisticsAvailable, lane: v.lane, evidenceTime: v.evidenceTime,
                minimumCollectionSequence: v.minimumCollectionSequence, applied: v.applied), retainingAnchor: current.anchor)
            let b = Boundary(testInactiveProducer: { q,s,p,c in
                let raw = try Boundary.actualInactive(q,s,p,c)
                XCTAssertEqual(raw.status, 1); XCTAssertEqual(raw.outcome.disposition, 0)
                XCTAssertTrue(Snapshot.equalAtoms(raw.atoms, s.atoms)); XCTAssertEqual(raw.metadata.revision, revision)
                for i in 0..<9 {
                    XCTAssertEqual(raw.edits[i].action, 1); XCTAssertEqual(raw.edits[i].source, 0)
                }
                return raw
            })
            guard case .superseded = try b.testInactiveTerminal(prepared, current: changed,
                generation: generation, exactPeer: exactPeer) else { return XCTFail("stale must not publish") }
            assertWhole(changed, changed.atoms); assertRetainedSidecars(changed, current)
        }
    }
    private func inactiveRaw(_ r: Boundary.InactiveRawResult, status: UInt32? = nil,
        inputs: Bool? = nil, denied: Bool? = nil) -> Boundary.InactiveRawResult {
        .init(status: status ?? r.status, header: r.header, atoms: r.atoms, metadata: r.metadata,
            outcome: r.outcome, edits: r.edits, coordinates: r.coordinates, reads: r.reads,
            inputsUnchanged: inputs ?? r.inputsUnchanged, deniedOutputsUntouched: denied ?? r.deniedOutputsUntouched)
    }
    private func assertInactiveTerminalDenials() throws {
        let (p,s) = try inactiveFixture()
        let malformed = Boundary(testInactiveProducer: { q,s,p,c in
            var denied = q; denied.abi = 0
            let raw = try Boundary.actualInactive(denied,s,p,c)
            XCTAssertEqual(raw.status, 2); XCTAssertTrue(raw.deniedOutputsUntouched); XCTAssertTrue(raw.inputsUnchanged)
            return raw
        })
        XCTAssertThrowsError(try malformed.testInactiveTerminal(p, current: s))
        for status: UInt32 in [2,3,4,5] {
            for untouched in [false, true] {
                let b = Boundary(testInactiveProducer: { q,s,p,c in
                    self.inactiveRaw(try Boundary.actualInactive(q,s,p,c), status: status, denied: untouched)
                })
                XCTAssertThrowsError(try b.testInactiveTerminal(p, current: s)) { error in
                    switch (untouched, error as? BelugaNetworkAdaptationOwnerError) {
                    case (true, .refused?), (false, .invalidResult?): break
                    default: XCTFail("wrong601 seven-output denial")
                    }
                }
            }
        }
    }
    private func assertInactiveTerminalMalformed() throws {
        let (p,s) = try inactiveFixture()
        for mode in 0..<32 {
            var calls = 0
            let b = Boundary(testInactiveProducer: { q,s,p,c in
                calls += 1; var r = try Boundary.actualInactive(q,s,p,c)
                if calls == 2 { XCTAssertEqual(q.invocation, 2); return r }
                switch mode {
                case 0: r.header.abi = 0
                case 1: r.header.domain = 4
                case 2: r.header.phase = 1
                case 3: r.header.count = 178
                case 4: r.atoms.removeLast()
                case 5: r.metadata.revision &+= 1
                case 6: r.metadata.invocation &+= 1
                case 7: r.metadata.peer = 78
                case 8: r.metadata.read_count = 1
                case 9: r.metadata.rtt_fault ^= 1
                case 10: r.metadata.scope = 1
                case 11: r.outcome.disposition = 2
                case 12: r.outcome.route = 1
                case 13: r.outcome.invocation &+= 1
                case 14: r.edits.removeLast()
                case 15: r.coordinates.append(.init())
                case 16: r.reads.removeLast()
                case 17: r.reads[0].abi = 1
                case 18: r.atoms[168].low &+= 1
                case 19: r.atoms[169].low ^= 1
                case 20: r.atoms[175].low &+= 1
                case 21: r.edits[0].action = 1 // equal native time is NOT corresponding-prepared custody
                case 22: r.edits[0].source = 1
                case 23: r.edits[0].index = 1
                case 24: r.coordinates[0].reserved = 1
                case 25: r.coordinates[0].low &+= 1
                case 26: r.edits[12].action = 1
                case 27: r.metadata.bound = 1
                case 28: r.metadata.queue_fault ^= 1
                case 29: r.metadata.route = 2
                case 30: return self.inactiveRaw(r, status: 0)
                default: return self.inactiveRaw(r, inputs: false)
                }
                return r
            })
            XCTAssertThrowsError(try b.testInactiveTerminal(p, current: s), "601 mode=\(mode)")
            XCTAssertNoThrow(try b.testInactiveTerminal(p, current: s), "601 recovery=\(mode)")
        }
    }
    private func assertInactiveTerminalReentry() throws {
        let (p,s) = try inactiveFixture()
        for mode in 0..<3 {
            var b: Boundary!, calls = 0
            b = Boundary(testInactiveProducer: { q,s,p,c in
                calls += 1
                if calls == 1 {
                    switch mode {
                    case 0: do { _ = try b.propose(s.value, event: .stopSampling) } catch BelugaNetworkAdaptationOwnerError.reentry { }
                    case 1: do { _ = try b.testInactiveTerminal(p, current: s) } catch BelugaNetworkAdaptationOwnerError.reentry { }
                    default: XCTAssertEqual(c.testUnexpectedRequest(), 0)
                    }
                }
                return try Boundary.actualInactive(q,s,p,c)
            })
            XCTAssertThrowsError(try b.testInactiveTerminal(p, current: s))
            XCTAssertNoThrow(try b.testInactiveTerminal(p, current: s)); XCTAssertEqual(calls, 2)
        }
    }
}

// Additive ordinary XCTest source. Simulated slot/witness only; no actor/ACK,
// cleanup, native-resource, discovery or execution permission is introduced.
extension BelugaNetworkAdaptationOwnerCodecTests {
    private typealias Slot = BelugaNetworkAdaptationOwnerPublicationFixture
    private func publicationAccepted(_ result: BelugaNetworkAdaptationOwnerPublicationDisposition,
        operation: UInt32, invocation: UInt64 = 1, enabled: Bool = false,
        file: StaticString = #filePath, line: UInt = #line) {
        guard case let .accepted(receipt) = result else { return XCTFail("not accepted", file: file, line: line) }
        XCTAssertEqual(receipt.operation, operation, file: file, line: line)
        XCTAssertEqual(receipt.invocation, invocation, file: file, line: line)
        XCTAssertEqual(receipt.collectorEnabled, enabled, file: file, line: line)
    }
    private func publicationUnchanged(_ slot: Slot, _ source: Snapshot,
        file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(slot.publications, 0, file: file, line: line)
        let current = try Snapshot.capture(slot.acceptedValue, retainingAnchor: source.anchor)
        assertWhole(current, source.atoms, file: file, line: line)
        assertRetainedSidecars(current, source, file: file, line: line)
    }

    func testPublicationFiveZeroClockCutsUseOneHeldStoreAndManual179() throws {
        let events: [BelugaNetworkAdaptationOwnerEvent] = [.stopSampling,
            .activateShow(generation: 77, show: 88), .resumeWithoutRevision,
            .resumeAndAdvance, .collectorGate(sourcePresent: false, resumeContextAbsent: true)]
        for event in events {
            let value = fixture(revision: event.operation == 108 ? .max : 57)
            let source = try Snapshot.capture(value), b = Boundary()
            let slot = Slot(boundary: b, value: value, event: event)
            let result = try b.testPublish(slot, event: event)
            publicationAccepted(result, operation: event.operation)
            var expected = source.atoms, times = source.times
            switch event {
            case .stopSampling:
                expected[168] = atom(1,58); expected[169] = atom(4,0)
                expected[170] = atom(8,nil); expected[171] = atom(10,nil); expected[172] = atom(1,nil)
                times[12] = nil
            case .activateShow: expected[154] = atom(4,1); expected[168] = atom(1,58)
            case .resumeWithoutRevision, .resumeAndAdvance:
                expected = resumeExpected(source, revision: event.operation == 108 ? 0 : 57); times[2] = nil
            case .collectorGate: expected[169] = atom(4,0)
            }
            let after = try Snapshot.capture(slot.acceptedValue, retainingAnchor: source.anchor)
            assertWhole(after, expected); XCTAssertEqual(after.times, times)
            XCTAssertEqual(after.anchor, source.anchor); XCTAssertEqual(after.route, source.route)
            XCTAssertEqual(slot.publications, 1); XCTAssertEqual(slot.trace, Slot.Stage.allCases)
        }
        let b = Boundary(), value = fixture()
        let event = BelugaNetworkAdaptationOwnerEvent.collectorGate(sourcePresent: true, resumeContextAbsent: true)
        let slot = Slot(boundary: b, value: value, event: event)
        publicationAccepted(try b.testPublish(slot, event: event), operation: 109, enabled: true)
        assertWhole(try Snapshot.capture(slot.acceptedValue), try Snapshot.capture(value).atoms)
        XCTAssertEqual(slot.publications, 1) // a no-op still requires admitted publication
    }

    func testPublicationClocked202And216UseLiteralFull179AndLazyReads() throws {
        let now = ContinuousClock().now
        for operation in [UInt32(202),216] {
            var p = fixture().policy
            if operation == 216 { p.networkAdaptationOwnerSeedClockedRetainedQueueFault() }
            let value = Value(policy: p, revision: 57, fastStatisticsAvailable: true, lane: .ordinaryFallback,
                evidenceTime: now, minimumCollectionSequence: 201, applied: fixture().applied)
            let source = try Snapshot.capture(value)
            var clocks = 0, sites: [UInt32] = []
            let b = Boundary(testClock: { clocks += 1; return now }, testClockedProducer: { q,s,f in
                let raw = try Boundary.actualClocked(q,s,f)
                sites = raw.reads.prefix(Int(raw.metadata.read_count)).map(\.site); return raw
            })
            let event = operation == 202 ? BelugaNetworkAdaptationOwnerClockedEvent.endShowWithoutRevision : .beginPostResumeEpoch(minimum: nil)
            let slot = Slot(boundary: b, value: value, clockedEvent: event)
            publicationAccepted(try b.testPublishClocked(slot, event: event), operation: operation)
            var expected = source.atoms, times = source.times
            if operation == 202 {
                for i in [153,154,158,166] { expected[i] = atom(4,0) }
                for i in [164,165] { expected[i] = atom(1,nil) }
                for i in [159,167] { expected[i] = atom(10,nil) }
                expected[160] = atom(3,nil); times[3] = nil; times[5] = nil
            } else {
                for i in [5,6,7,8,9,10] { expected[i] = atom(2,0) }
                expected[21] = atom(7,nil); expected[25] = atom(4,0); expected[26] = atom(7,nil)
                expected[27] = atom(2,nil); expected[28] = atom(10,nil)
                expected[145] = atom(4,0); expected[146] = atom(1,nil)
                expected[147] = atom(3,nil); expected[148] = atom(3,nil)
                expected[158] = atom(4,0); expected[159] = atom(10,nil); expected[160] = atom(3,nil)
                expected[168] = atom(1,58); expected[170] = atom(8,nil)
                expected[171] = atom(10,nil); expected[172] = atom(1,nil)
                times[2] = nil; times[3] = nil; times[12] = nil
            }
            let current = try Snapshot.capture(slot.acceptedValue, retainingAnchor: source.anchor)
            assertWhole(current, expected); XCTAssertEqual(current.times, times)
            XCTAssertEqual(current.anchor, source.anchor); XCTAssertEqual(current.route, source.route)
            XCTAssertEqual(sites, operation == 202 ? [] : [2]); XCTAssertEqual(clocks, sites.count)
            XCTAssertEqual(slot.publications, 1); XCTAssertEqual(slot.trace, Slot.Stage.allCases)
        }
    }

    func testPublicationWrongBoundaryPayloadAndExhaustionDenyBeforeReads() throws {
        let value = fixture(); var clocks = 0, calls = 0
        let b = Boundary(testClock: { clocks += 1; return ContinuousClock().now }, testClockedProducer: { q,s,f in
            calls += 1; return try Boundary.actualClocked(q,s,f)
        })
        let foreign = Boundary()
        let own = Slot(boundary: foreign, value: value, event: .stopSampling)
        if case .refused = try b.testPublish(own, event: .stopSampling) {} else { XCTFail("wrong-boundary admitted") }
        XCTAssertTrue(own.trace.isEmpty)
        let zeroPairs: [(BelugaNetworkAdaptationOwnerEvent,BelugaNetworkAdaptationOwnerEvent)] = [
            (.activateShow(generation: 77,show: 88),.activateShow(generation: 78,show: 88)),
            (.activateShow(generation: 77,show: 88),.activateShow(generation: 77,show: 89)),
            (.collectorGate(sourcePresent: true,resumeContextAbsent: true),.collectorGate(sourcePresent: false,resumeContextAbsent: true)),
            (.collectorGate(sourcePresent: true,resumeContextAbsent: true),.collectorGate(sourcePresent: true,resumeContextAbsent: false))]
        for (original,changed) in zeroPairs {
            let slot = Slot(boundary: b, value: value, event: original)
            if case .refused = try b.testPublish(slot,event: changed) {} else { XCTFail("payload admitted") }
            XCTAssertTrue(slot.trace.isEmpty); XCTAssertEqual(slot.publications,0)
        }
        let clockPairs: [(BelugaNetworkAdaptationOwnerClockedEvent,BelugaNetworkAdaptationOwnerClockedEvent)] = [
            (.visibility(show: true,generation: 77,epoch: 88),.visibility(show: false,generation: 77,epoch: 88)),
            (.visibility(show: true,generation: 77,epoch: 88),.visibility(show: true,generation: 78,epoch: 88)),
            (.visibility(show: true,generation: 77,epoch: 88),.visibility(show: true,generation: 77,epoch: 89)),
            (.visibility(show: false,generation: 77,epoch: 88),.visibility(show: false,generation: 78,epoch: 88)),
            (.visibility(show: false,generation: 77,epoch: 88),.visibility(show: false,generation: 77,epoch: 89)),
            (.beginPostResumeEpoch(minimum: nil),.beginPostResumeEpoch(minimum: 0)),
            (.beginPostResumeEpoch(minimum: 3),.beginPostResumeEpoch(minimum: 4))]
        for (original,changed) in clockPairs {
            let slot = Slot(boundary: b, value: value, clockedEvent: original)
            if case .refused = try b.testPublishClocked(slot,event: changed) {} else { XCTFail("clock payload admitted") }
            XCTAssertTrue(slot.trace.isEmpty); XCTAssertEqual(slot.publications,0)
        }
        let exhausted = Slot(boundary: b,value: value,clockedEvent: .beginPostResumeEpoch(minimum: nil),generation: .max)
        if case .refused = try b.testPublishClocked(exhausted,event: .beginPostResumeEpoch(minimum: nil)) {} else { XCTFail("exhaustion admitted") }
        XCTAssertEqual(exhausted.trace,[.admission]); XCTAssertEqual(exhausted.publications,0)
        XCTAssertEqual(clocks,0); XCTAssertEqual(calls,0)
        let final = Slot(boundary: b,value: value,clockedEvent: .endShowWithoutRevision,generation: UInt64.max - 1)
        guard case .accepted = try b.testPublishClocked(final,event: .endShowWithoutRevision) else { return XCTFail("last generation denied") }
        guard case .refused = try b.testPublishClocked(final,event: .endShowWithoutRevision) else { return XCTFail("generation recycled") }
        XCTAssertEqual(final.publications,1); XCTAssertEqual(calls,1); XCTAssertEqual(clocks,0)
    }

    func testPublicationCurrentnessRejectsBitIdenticalABAAndNonrevisionWriter() throws {
        let initialValue = fixture(), initialSource = try Snapshot.capture(initialValue)
        var rawCalls = 0
        let initialBoundary = Boundary(testProducer: { q,s in rawCalls += 1; return try Boundary.actual(q,s) })
        let early = Slot(boundary: initialBoundary,value: initialValue,event: .stopSampling)
        early.testHook = { stage in if stage == .sourceRead { early.testInvalidateWitness() } }
        guard case .superseded = try initialBoundary.testPublish(early,event: .stopSampling) else { return XCTFail("stale pre-provider witness") }
        XCTAssertEqual(rawCalls,0); try publicationUnchanged(early,initialSource)
        for stage in [Slot.Stage.afterImport,.precommit,.finalWitness,.recapture] {
            for aba in [false,true] {
                let value = fixture(), source = try Snapshot.capture(value), b = Boundary()
                let slot = Slot(boundary: b,value: value,event: .stopSampling)
                slot.testHook = { current in
                    if current == stage {
                        if aba { slot.testInvalidateWitness() } else { slot.testChangeFastFlagWithoutRevision() }
                    }
                }
                if case .superseded = try b.testPublish(slot,event: .stopSampling) {} else { XCTFail("superseded accepted") }
                XCTAssertEqual(slot.publications,0)
                var expected = source.atoms
                if !aba { expected[169] = atom(4,0) }
                assertWhole(try Snapshot.capture(slot.acceptedValue,retainingAnchor: source.anchor),expected)
                XCTAssertEqual(slot.acceptedValue.revision,57)
            }
        }
    }

    func testPublicationEveryObservableHookRejectsSwallowedCrossFamilyReentry() throws {
        for clocked in [false,true] {
            for stage in Slot.Stage.allCases {
                let value = fixture(), source = try Snapshot.capture(value), b = Boundary()
                let slot = clocked ? Slot(boundary: b,value: value,clockedEvent: .endShowWithoutRevision)
                    : Slot(boundary: b,value: value,event: .stopSampling)
                slot.testHook = { current in
                    guard current == stage else { return }
                    _ = try? b.propose(value,event: .stopSampling)
                    _ = try? b.proposeClocked(value,event: .endShowWithoutRevision)
                    _ = try? b.testTerminalPreparedValue(value,report: self.terminalReport())
                }
                if clocked { XCTAssertThrowsError(try b.testPublishClocked(slot,event: .endShowWithoutRevision)) }
                else { XCTAssertThrowsError(try b.testPublish(slot,event: .stopSampling)) }
                try publicationUnchanged(slot,source)
                slot.testHook = nil
                let result = clocked ? try b.testPublishClocked(slot,event: .endShowWithoutRevision)
                    : try b.testPublish(slot,event: .stopSampling)
                publicationAccepted(result,operation: clocked ? 202 : 105,invocation: 2)
                XCTAssertEqual(slot.publications,1)
            }
        }
    }

    func testPublicationProducerAndClockReentryShareOriginalGuard() throws {
        let value = fixture(), source = try Snapshot.capture(value)
        var b: Boundary!
        b = Boundary(testProducer: { q,s in
            _ = try? b.proposeClocked(value,event: .endShowWithoutRevision)
            return try Boundary.actual(q,s)
        })
        let slot = Slot(boundary: b,value: value,event: .stopSampling)
        XCTAssertThrowsError(try b.testPublish(slot,event: .stopSampling)); try publicationUnchanged(slot,source)
        var clockPolicy = value.policy; clockPolicy.networkAdaptationOwnerSeedClockedRetainedQueueFault()
        let clockValue = Value(policy: clockPolicy,revision: value.revision,
            fastStatisticsAvailable: value.fastStatisticsAvailable,lane: value.lane,
            evidenceTime: value.evidenceTime,minimumCollectionSequence: value.minimumCollectionSequence,applied: value.applied)
        let clockSource = try Snapshot.capture(clockValue)
        var clockCalls = 0
        b = Boundary(testClock: {
            clockCalls += 1; _ = try? b.propose(value,event: .stopSampling)
            return ContinuousClock().now
        })
        let clockSlot = Slot(boundary: b,value: clockValue,clockedEvent: .beginPostResumeEpoch(minimum: nil))
        XCTAssertThrowsError(try b.testPublishClocked(clockSlot,event: .beginPostResumeEpoch(minimum: nil)))
        XCTAssertEqual(clockCalls,1); try publicationUnchanged(clockSlot,clockSource)
    }

    func testPublicationGenuinePublicDenialMalformedAndThrowHaveZeroStores() throws {
        let value = fixture(), source = try Snapshot.capture(value)
        for malformed in [false,true] {
            let b = Boundary(testProducer: { q,s in
                var input = q; if !malformed { input.abi = 0 }
                var raw = try Boundary.actual(input,s)
                if malformed { raw.metadata.invocation &+= 1 }
                else { XCTAssertEqual(raw.status,2); XCTAssertTrue(raw.deniedOutputsUntouched) }
                return raw
            })
            let slot = Slot(boundary: b,value: value,event: .stopSampling)
            XCTAssertThrowsError(try b.testPublish(slot,event: .stopSampling)); try publicationUnchanged(slot,source)
            let cb = Boundary(testClock: { ContinuousClock().now },testClockedProducer: { q,s,f in
                var input = q; if !malformed { input.abi = 0 }
                var raw = try Boundary.actualClocked(input,s,f)
                if malformed { raw.metadata.invocation &+= 1 }
                else { XCTAssertEqual(raw.status,2); XCTAssertTrue(raw.deniedOutputsUntouched) }
                return raw
            })
            let cs = Slot(boundary: cb,value: value,clockedEvent: .endShowWithoutRevision)
            XCTAssertThrowsError(try cb.testPublishClocked(cs,event: .endShowWithoutRevision)); try publicationUnchanged(cs,source)
        }
        enum Denied: Error { case clock, witness }
        var clockPolicy = value.policy; clockPolicy.networkAdaptationOwnerSeedClockedRetainedQueueFault()
        let clockValue = Value(policy: clockPolicy,revision: value.revision,
            fastStatisticsAvailable: value.fastStatisticsAvailable,lane: value.lane,
            evidenceTime: value.evidenceTime,minimumCollectionSequence: value.minimumCollectionSequence,applied: value.applied)
        let clockSource = try Snapshot.capture(clockValue)
        var clockCalls = 0
        let b = Boundary(testClock: { clockCalls += 1; throw Denied.clock })
        let slot = Slot(boundary: b,value: clockValue,clockedEvent: .beginPostResumeEpoch(minimum: nil))
        XCTAssertThrowsError(try b.testPublishClocked(slot,event: .beginPostResumeEpoch(minimum: nil)))
        XCTAssertEqual(clockCalls,1); try publicationUnchanged(slot,clockSource)
        let zero = Boundary(), zs = Slot(boundary: zero,value: value,event: .stopSampling)
        zs.testHook = { _ in throw Denied.witness }
        XCTAssertThrowsError(try zero.testPublish(zs,event: .stopSampling)); try publicationUnchanged(zs,source)
        zs.testHook = nil
        publicationAccepted(try zero.testPublish(zs,event: .stopSampling),operation: 105,invocation: 2)
    }

    func testPublicationRetainsOriginalDependencyProducersWithoutRecallingThem() throws {
        let rtt = Counter(), demand = Counter()
        var policy = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000,baseFramesPerSecond: 60,
            roundTripTimeProducer: { state,event in rtt.increment(); return beluga_core_rtt_evidence_step(state,event) },
            tierDemandProducer: { facts in demand.increment(); return beluga_core_tier_demand_project(facts) })
        policy.networkAdaptationOwnerSeedRegression(at: ContinuousClock().now,route: .init(kind: .direct))
        let value = Value(policy: policy,revision: 0,fastStatisticsAvailable: true,lane: nil,
            evidenceTime: nil,minimumCollectionSequence: nil,applied: nil)
        let b = Boundary(), slot = Slot(boundary: b,value: value,event: .stopSampling)
        let beforeRTT = rtt.value, beforeDemand = demand.value
        publicationAccepted(try b.testPublish(slot,event: .stopSampling),operation: 105)
        XCTAssertEqual(rtt.value,beforeRTT); XCTAssertEqual(demand.value,beforeDemand)
        var retained = slot.acceptedValue.policy; retained.bind(toPeerGeneration: 78)
        XCTAssertGreaterThan(rtt.value,beforeRTT); XCTAssertEqual(demand.value,beforeDemand)
        XCTAssertEqual(slot.publications,1) // invocation origin, not equality of closures
    }

    func testPreparedLedgerAndPublicationSlotRetainExactOriginatingBoundary() throws {
        weak var ledgerOrigin: Boundary?
        var consume: ((Boundary) throws -> Void)?
        do {
            let origin = Boundary(); ledgerOrigin = origin
            consume = origin.testPreparedOneUse().1
        }
        XCTAssertNotNil(ledgerOrigin)
        let wrong = Boundary()
        XCTAssertThrowsError(try consume!(wrong)) // still burns before identity rejection
        XCTAssertThrowsError(try consume!(ledgerOrigin!))
        XCTAssertNotNil(ledgerOrigin)
        consume = nil; XCTAssertNil(ledgerOrigin)
        weak var slotOrigin: Boundary?
        var slot: Slot?
        do {
            let origin = Boundary(); slotOrigin = origin
            slot = Slot(boundary: origin,value: fixture(),event: .stopSampling)
        }
        XCTAssertNotNil(slotOrigin); XCTAssertEqual(slot?.publications,0)
        slot = nil; XCTAssertNil(slotOrigin)
        // This pure ledger/slot assay cannot construct an actual native receipt.
    }
}
