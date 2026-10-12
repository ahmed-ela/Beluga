// SOURCE-ONLY, UNCOMPILED ordinary XCTest packet. No private reducer/reference.
import Foundation
import BelugaCore
import WebRTCTransport
@testable import CaptureServer
import XCTest

final class BelugaNetworkAdaptationOwnerClockedCodecTests: XCTestCase {
    typealias Value = BelugaNetworkAdaptationOwnerValue
    typealias Snapshot = BelugaNetworkAdaptationOwnerSnapshot
    typealias Boundary = BelugaNetworkAdaptationOwnerBoundary
    typealias Event = BelugaNetworkAdaptationOwnerClockedEvent
    private enum FixtureError: Error { case denied }
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
    private let t = ContinuousClock().now // fixture-only, NOT adapter admission
    private func fixture(revision: UInt64 = 57, producer: BelugaRustRoundTripTimeEvidence.Producer? = nil,
        probe: Bool = false, faultTail: Bool = false, faulted: Bool = false, queueFaulted: Bool = false) -> Value {
        let route = WebRTCICERouteDiagnostics(kind: .relayed,
            local: .init(type: .host, transport: "udp", networkType: "ethernet"),
            remote: .init(type: .relay, transport: "udp", relayProtocol: "tls"))
        var p = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000,
            baseFramesPerSecond: 60, roundTripTimeProducer: producer)
        p.networkAdaptationOwnerSeedRegression(at: t, route: route)
        if probe { p.networkAdaptationOwnerSeedClockedProbe() }
        if faultTail { p.networkAdaptationOwnerSeedClockedFaultTail() }
        if faulted { p.networkAdaptationOwnerSeedClockedRetainedRTTFault() }
        if queueFaulted { p.networkAdaptationOwnerSeedClockedRetainedQueueFault() }
        return .init(policy: p, revision: revision, fastStatisticsAvailable: true,
            lane: .ordinaryFallback, evidenceTime: t.advanced(by: .milliseconds(-625)),
            minimumCollectionSequence: 201,
            applied: .init(tier: .critical, maximumBitrateBps: -21, maximumTotalRTPBitrateBps: 765_432,
                maximumFramesPerSecond: 13, scaleResolutionDownBy: Double(bitPattern: 0x7ff8000000000099)))
    }
    private func identical(_ a: Snapshot, _ b: Snapshot, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(Snapshot.equalAtoms(a.atoms, b.atoms), file: file, line: line)
        XCTAssertEqual(a.times, b.times, file: file, line: line)
        XCTAssertEqual(a.anchor, b.anchor, file: file, line: line)
        XCTAssertEqual(a.route, b.route, file: file, line: line)
    }
    private func expect(_ a: Snapshot, _ index: Int, _ kind: UInt32, _ value: UInt64?,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.atoms[index].kind, kind, file: file, line: line)
        XCTAssertEqual(a.atoms[index].present, value == nil ? 0 : 1, file: file, line: line)
        XCTAssertEqual(a.atoms[index].high, 0, file: file, line: line)
        XCTAssertEqual(a.atoms[index].low, value ?? 0, file: file, line: line)
    }
    func testClockedAllEightCutsHaveLiteralReadPlansAndClosedTail() throws {
        let cases: [(Event, [UInt32], UInt64)] = [
            (.endShowWithoutRevision, [], 57), (.routeInvalidated, [2, 0, 1], 58),
            (.endShowAndAdvance, [], 58), (.visibility(show: false, generation: 999, epoch: 999), [], 58),
            (.hideHealthRevocation, [0, 1], 57), (.beginPostResumeEpoch(minimum: 300), [2], 58),
            (.resumeAccepted, [], 58), (.resumeFailedAndAdvance, [2], 58)]
        for (event, expectedPlan, revision) in cases {
            let v = fixture(); let source = try Snapshot.capture(v)
            var count = 0, sites: [UInt32] = []
            let b = Boundary(testClock: { count += 1; return self.t.advanced(by: .milliseconds(count)) },
                testClockedProducer: { request, source, frame in
                    let r = try Boundary.actualClocked(request, source, frame)
                    sites = r.reads.prefix(Int(r.metadata.read_count)).map(\.site)
                    return r
                })
            let r = try b.proposeClocked(v, event: event)
            XCTAssertEqual(sites, expectedPlan); XCTAssertEqual(count, expectedPlan.count)
            expect(r.replacement, 168, 1, revision); expect(r.replacement, 169, 4, 1)
            expect(r.replacement, 173, 4, 1); expect(r.replacement, 174, 7, 4)
            expect(r.replacement, 175, 2, UInt64(bitPattern: -21)); expect(r.replacement, 178, 3, 0x7ff8000000000099)
            XCTAssertEqual(r.replacement.anchor, source.anchor)
            XCTAssertNil(r.replacement.times[9]); XCTAssertNil(r.replacement.times[10]); XCTAssertNil(r.replacement.times[11])
            for i in [0, 1, 2] + Array(90...142) {
                XCTAssertTrue(Snapshot.equalAtoms([r.replacement.atoms[i]], [source.atoms[i]]))
            }
            identical(try Snapshot.capture(v), source) // no source mutation during draft
        }
    }

    func testClockedVisibilityRejectBindAndWrappingAreOriginal() throws {
        let v = fixture(revision: UInt64.max); let s = try Snapshot.capture(v)
        var count = 0
        let b = Boundary(testClock: { count += 1; return self.t })
        let rejected = try b.proposeClocked(v, event: .visibility(show: true, generation: 77, epoch: 88))
        XCTAssertEqual(count, 0); expect(rejected.replacement, 168, 1, 0)
        expect(rejected.replacement, 152, 1, 88); XCTAssertEqual(rejected.replacement.route, s.route)
        let fresh = try b.proposeClocked(v, event: .visibility(show: true, generation: 77, epoch: 89))
        expect(fresh.replacement, 152, 1, 89); expect(fresh.replacement, 153, 4, 1)
        expect(fresh.replacement, 154, 4, 0); expect(fresh.replacement, 155, 4, 0)
        XCTAssertEqual(count, 0); XCTAssertEqual(fresh.replacement.route, s.route)
        let boundThenRejected = try b.proposeClocked(v, event: .visibility(show: true, generation: 78, epoch: 0))
        XCTAssertEqual(count, 5); expect(boundThenRejected.replacement, 3, 1, 78)
        expect(boundThenRejected.replacement, 4, 7, 5); expect(boundThenRejected.replacement, 152, 1, nil)
        expect(boundThenRejected.replacement, 143, 1, nil); XCTAssertNil(boundThenRejected.replacement.route)
        expect(boundThenRejected.replacement, 144, 4, 0); expect(boundThenRejected.replacement, 168, 1, 0)
    }

    func testClockedConditionalRevertAndHideTerminalFaultTail() throws {
        for event in [Event.endShowWithoutRevision, .endShowAndAdvance, .resumeAccepted,
            .visibility(show: false, generation: 0, epoch: 0)] {
            var sites: [UInt32] = []
            let b = Boundary(testClock: { self.t }, testClockedProducer: { request, source, frame in
                let r = try Boundary.actualClocked(request, source, frame)
                sites = r.reads.prefix(Int(r.metadata.read_count)).map(\.site); return r
            })
            let r = try b.proposeClocked(fixture(probe: true), event: event)
            XCTAssertEqual(sites, [2]); expect(r.replacement, 4, 7, 7)
            expect(r.replacement, 20, 7, nil); expect(r.replacement, 22, 7, nil)
            expect(r.replacement, 156, 4, 1); XCTAssertNil(r.replacement.times[0]); XCTAssertNil(r.replacement.times[1])
        }
        var sites: [UInt32] = []
        let b = Boundary(testClock: { self.t }, testClockedProducer: { request, source, frame in
            let r = try Boundary.actualClocked(request, source, frame)
            sites = r.reads.prefix(Int(r.metadata.read_count)).map(\.site); return r
        })
        let r = try b.proposeClocked(fixture(faultTail: true), event: .hideHealthRevocation)
        XCTAssertEqual(sites, [0, 1, 2]); expect(r.replacement, 89, 4, 1)
        expect(r.replacement, 4, 7, 7); expect(r.replacement, 20, 7, nil)
        expect(r.replacement, 5, 2, 0); expect(r.replacement, 9, 2, 0)
    }

    func testClockedRetainsExactNativeTimesAndWholeRoute() throws {
        let v = fixture(); let s = try Snapshot.capture(v)
        let r = try Boundary(testClock: { self.t }).proposeClocked(v, event: .endShowWithoutRevision)
        var times = s.times; times[3] = nil; times[5] = nil
        XCTAssertEqual(r.replacement.times, times); XCTAssertEqual(r.replacement.anchor, s.anchor)
        XCTAssertEqual(r.replacement.route, s.route)
        expect(r.replacement, 12, 10, 0) // exact original anchor, not a fresh sampled time
        XCTAssertEqual(r.replacement.atoms[23].high, -1)
        XCTAssertEqual(r.replacement.atoms[23].low, UInt64.max - 4_374_999_999_999_999_999)
        let cleared = try Boundary(testClock: { self.t }).proposeClocked(v, event: .routeInvalidated)
        XCTAssertNil(cleared.replacement.route); XCTAssertEqual(cleared.replacement.anchor, s.anchor)
        XCTAssertNil(cleared.replacement.times[12]); expect(cleared.replacement, 170, 8, nil)
        // Evidence/lane clear is distinct from the unchanged freshness minimum.
        expect(cleared.replacement, 172, 1, 201)
    }

    func testClockedMinimumAndResumeRestorationUseLiteralFields() throws {
        let v = fixture()
        let b = Boundary(testClock: { self.t })
        let less = try b.proposeClocked(v, event: .beginPostResumeEpoch(minimum: 100))
        expect(less.replacement, 172, 1, 201); expect(less.replacement, 170, 8, nil)
        let absent = try b.proposeClocked(v, event: .beginPostResumeEpoch(minimum: nil))
        expect(absent.replacement, 172, 1, nil)
        let minima: [(UInt64, UInt64)] = [(0, 201), (201, 201), (300, 300), (UInt64.max, UInt64.max)]
        for (minimum, expected) in minima {
            var clocks = 0, sites: [UInt32] = []
            let boundary = Boundary(testClock: { clocks += 1; return self.t }, testClockedProducer: { request, source, frame in
                XCTAssertEqual(request.minimum_present, 1)
                XCTAssertEqual(request.minimum, minimum)
                let raw = try Boundary.actualClocked(request, source, frame)
                sites = raw.reads.prefix(Int(raw.metadata.read_count)).map(\.site)
                return raw
            })
            let result = try boundary.proposeClocked(fixture(revision: UInt64.max),
                event: .beginPostResumeEpoch(minimum: minimum))
            expect(result.replacement, 172, 1, expected)
            expect(result.replacement, 168, 1, 0)
            XCTAssertEqual(clocks, 1); XCTAssertEqual(sites, [2])
            let original = try Snapshot.capture(fixture(revision: UInt64.max))
            XCTAssertEqual(result.replacement.route, original.route)
            XCTAssertEqual(result.replacement.anchor, original.anchor)
        }
        var zeroMinimum = fixture()
        zeroMinimum = .init(policy: zeroMinimum.policy, revision: zeroMinimum.revision,
            fastStatisticsAvailable: zeroMinimum.fastStatisticsAvailable, lane: zeroMinimum.lane,
            evidenceTime: zeroMinimum.evidenceTime, minimumCollectionSequence: nil, applied: zeroMinimum.applied)
        let presentZero = try b.proposeClocked(zeroMinimum, event: .beginPostResumeEpoch(minimum: 0))
        expect(presentZero.replacement, 172, 1, 0)
        let reset = try b.proposeClocked(presentZero.replacement.value, event: .beginPostResumeEpoch(minimum: nil))
        expect(reset.replacement, 172, 1, nil)
        let failed = try b.proposeClocked(v, event: .resumeFailedAndAdvance)
        expect(failed.replacement, 4, 7, 7); expect(failed.replacement, 13, 2, UInt64(bitPattern: -7))
        expect(failed.replacement, 14, 2, 9); expect(failed.replacement, 15, 4, 1)
        expect(failed.replacement, 16, 4, 0); expect(failed.replacement, 17, 4, nil)
        expect(failed.replacement, 18, 2, nil); expect(failed.replacement, 19, 2, nil)
    }

    func testClockedRTTProvenanceIsSealedAndFaultsRetainProducer() throws {
        let calls = Counter(); var clocks = 0
        let injected: BelugaRustRoundTripTimeEvidence.Producer = { state, event in
            calls.increment(); return beluga_core_rtt_evidence_step(state, event)
        }
        let v = fixture(producer: injected); let s = try Snapshot.capture(v)
        let b = Boundary(testClock: { clocks += 1; return self.t })
        XCTAssertThrowsError(try b.proposeClocked(v, event: .routeInvalidated))
        XCTAssertEqual(calls.value, 0); XCTAssertEqual(clocks, 0); identical(try Snapshot.capture(v), s)
        let noRTT = try b.proposeClocked(v, event: .endShowWithoutRevision)
        XCTAssertEqual(calls.value, 0); XCTAssertEqual(clocks, 0)
        XCTAssertThrowsError(try b.proposeClocked(noRTT.replacement.value, event: .routeInvalidated))
        let faulted = fixture(producer: injected, faulted: true)
        let retired = try b.proposeClocked(faulted, event: .hideHealthRevocation)
        XCTAssertEqual(calls.value, 0); XCTAssertEqual(clocks, 2); expect(retired.replacement, 89, 4, 1)
        // Copied injected producer and sticky fault survive the full import.
        let again = try b.proposeClocked(retired.replacement.value, event: .hideHealthRevocation)
        XCTAssertEqual(calls.value, 0); XCTAssertEqual(clocks, 4); expect(again.replacement, 89, 4, 1)
        let queueFaulted = try b.proposeClocked(fixture(queueFaulted: true), event: .beginPostResumeEpoch(minimum: nil))
        XCTAssertEqual(clocks, 5); expect(queueFaulted.replacement, 41, 4, 1)
    }

    func testClockedHealthyRTTImportRejectsInvalidOriginalDomainButRetainsFaultedWords() throws {
        let v = fixture(); let source = try Snapshot.capture(v)
        let invalid: [(Int, UInt64)] = [(43, 1), (44, 2), (45, 3), (46, UInt64.max),
            (47, UInt64.max), (48, 2), (51, 4), (54, 2), (58, 1), (60, 0x7ff8000000000042)]
        for (index, word) in invalid {
            let boundary = Boundary(testClock: { self.t }, testClockedProducer: { request, source, frame in
                var result = try Boundary.actualClocked(request, source, frame)
                // RTT belongs to this cut; shape/full recapture alone would accept
                // these raw words as healthy. The original RTT domain must refuse.
                XCTAssertEqual(result.atoms[89].low, 0)
                result.atoms[index].low = word
                return result
            })
            XCTAssertThrowsError(try boundary.proposeClocked(v, event: .routeInvalidated))
            identical(try Snapshot.capture(v), source)
        }
        // The same malformed reserved word is retained as opaque native custody
        // when the source is already faulted. The guard must not normalize it.
        let faulted = fixture(faultTail: true, faulted: true)
        let before = try Snapshot.capture(faulted)
        expect(before, 43, 6, 1); expect(before, 89, 4, 1)
        let accepted = try Boundary(testClock: { self.t }).proposeClocked(faulted, event: .hideHealthRevocation)
        expect(accepted.replacement, 43, 6, 1); expect(accepted.replacement, 89, 4, 1)
        identical(try Snapshot.capture(faulted), before)
    }

    func testClockedIllegalCallbackRequestsDenyBeforeClock() throws {
        let probes: [(UInt64, UInt32, UInt32)] = [(999, 2, 0), (1, 3, 0), (1, 4, 0), (1, 2, 1), (1, 0, 0)]
        for (invocation, site, ordinal) in probes {
            var clocks = 0
            let b = Boundary(testClock: { clocks += 1; return self.t }, testClockedProducer: { request, source, frame in
                XCTAssertEqual(frame.testReply(invocation: invocation, site: site, ordinal: ordinal), 0)
                return try Boundary.actualClocked(request, source, frame)
            })
            XCTAssertThrowsError(try b.proposeClocked(fixture(), event: .beginPostResumeEpoch(minimum: nil)))
            XCTAssertEqual(clocks, 0)
        }
    }

    func testClockedEveryProviderPhaseSwallowedCrossFamilyReentryPoisons() throws {
        let v = fixture(); let s = try Snapshot.capture(v)
        for family in 0..<2 { for fail in 0..<5 {
            var b: Boundary!; var reads = 0
            b = Boundary(testClock: {
                let ordinal = reads; reads += 1
                if ordinal == fail {
                    if family == 0 { _ = try? b.propose(v, event: .collectorGate(sourcePresent: true, resumeContextAbsent: true)) }
                    else { _ = try? b.proposeClocked(v, event: .endShowWithoutRevision) }
                }
                return self.t
            })
            XCTAssertThrowsError(try b.proposeClocked(v, event: .visibility(show: true, generation: 78, epoch: 89)))
            XCTAssertEqual(reads, fail + 1); identical(try Snapshot.capture(v), s)
            // Shared guard resets after refusal; no nested call was issued to Rust.
            let healthy = try b.propose(v, event: .collectorGate(sourcePresent: true, resumeContextAbsent: true))
            XCTAssertTrue(healthy.collectorEnabled); identical(healthy.replacement, s)
        } }
        var b: Boundary!
        b = Boundary(testProducer: { request, source in
            _ = try? b.proposeClocked(v, event: .endShowWithoutRevision)
            return try Boundary.actual(request, source)
        })
        XCTAssertThrowsError(try b.propose(v, event: .collectorGate(sourcePresent: true, resumeContextAbsent: true)))
        identical(try Snapshot.capture(v), s)
    }

    func testClockedProviderThrowDeniesPrefixAndNextCallRecovers() throws {
        let v = fixture(); let s = try Snapshot.capture(v)
        var fail = true, reads = 0
        let b = Boundary(testClock: { reads += 1; if fail { throw FixtureError.denied }; return self.t })
        XCTAssertThrowsError(try b.proposeClocked(v, event: .routeInvalidated))
        XCTAssertEqual(reads, 1); identical(try Snapshot.capture(v), s)
        fail = false
        let r = try b.proposeClocked(v, event: .routeInvalidated)
        XCTAssertEqual(reads, 4); expect(r.replacement, 168, 1, 58); XCTAssertNil(r.replacement.route)
    }

    func testClockedMalformedPacketsNeverProduceReplacement() throws {
        let v = fixture(); let s = try Snapshot.capture(v)
        let changes: [(inout Boundary.RawResult) -> Void] = [
            { $0.header.abi = 2 }, { $0.header.phase = 1 }, { $0.header.domain = 1 },
            { $0.header.count = 178 }, { $0.atoms.removeLast() }, { $0.atoms.append($0.atoms[0]) },
            { $0.metadata.operation = 202 }, { $0.metadata.scope = 1 }, { $0.metadata.invocation = 999 },
            { $0.metadata.peer = 78 }, { $0.metadata.peer_present = 0 }, { $0.metadata.bound = 1 },
            { $0.metadata.route = 1 }, { $0.metadata.sample = 1 }, { $0.metadata.enabled = 1 },
            { $0.metadata.lease = 1 }, { $0.metadata.queue_fault = 1 }, { $0.metadata.rtt_fault = 1 },
            { $0.metadata.revision = 59 }, { $0.metadata.read_count = 2 },
            { $0.edits[2].action = 3 }, { $0.edits[2].source = 1 }, { $0.edits[2].ordinal = 1 },
            { $0.edits[2].high = 1 }, { $0.coordinates[2].reserved = 1 }, { $0.coordinates[2].present = 1 },
            { $0.reads[0].invocation = 999 }, { $0.reads[0].ordinal = 1 }, { $0.reads[0].site = 0 },
            { $0.reads[0].status = 0 }, { $0.reads[0].abi = 2 }, { $0.reads[0].reserved = 1 },
            { $0.reads[0].low ^= 1 }, { $0.reads[1].abi = 1 }, { $0.atoms[90].low ^= 1 },
            { $0.atoms[144].low = 0 }, { $0.atoms[169].low = 0 }, { $0.atoms[173].low = 0 },
            { $0.edits.removeLast() }, { $0.coordinates.append(.init()) }, { $0.reads.removeLast() }]
        for change in changes {
            let b = Boundary(testClock: { self.t }, testClockedProducer: { request, source, frame in
                var r = try Boundary.actualClocked(request, source, frame); change(&r); return r
            })
            XCTAssertThrowsError(try b.proposeClocked(v, event: .beginPostResumeEpoch(minimum: nil)))
            identical(try Snapshot.capture(v), s)
        }
        for status: UInt32 in [0, 2, 3, 4, 5] {
            let b = Boundary(testClock: { self.t }, testClockedProducer: { request, source, frame in
                let r = try Boundary.actualClocked(request, source, frame)
                return .init(status: status, header: r.header, atoms: r.atoms, metadata: r.metadata,
                    edits: r.edits, coordinates: r.coordinates, reads: r.reads, inputsUnchanged: true,
                    deniedOutputsUntouched: false)
            })
            XCTAssertThrowsError(try b.proposeClocked(v, event: .beginPostResumeEpoch(minimum: nil)))
            identical(try Snapshot.capture(v), s)
        }
        let changedInput = Boundary(testClock: { self.t }, testClockedProducer: { request, source, frame in
            let r = try Boundary.actualClocked(request, source, frame)
            return .init(status: r.status, header: r.header, atoms: r.atoms, metadata: r.metadata,
                edits: r.edits, coordinates: r.coordinates, reads: r.reads, inputsUnchanged: false,
                deniedOutputsUntouched: r.deniedOutputsUntouched)
        })
        XCTAssertThrowsError(try changedInput.proposeClocked(v, event: .beginPostResumeEpoch(minimum: nil)))
        identical(try Snapshot.capture(v), s)
    }

    func testClockedNoStoredAnchorIsLatchedOnlyAtAdmittedRead() throws {
        let p = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000, baseFramesPerSecond: 60)
        let v = Value(policy: p, revision: 0, fastStatisticsAvailable: false, lane: nil,
            evidenceTime: nil, minimumCollectionSequence: nil, applied: nil)
        let s = try Snapshot.capture(v); XCTAssertNil(s.anchor); XCTAssertTrue(s.times.allSatisfy { $0 == nil })
        var reads = 0
        let b = Boundary(testClock: { reads += 1; return self.t }, testClockedProducer: { request, source, frame in
            let r = try Boundary.actualClocked(request, source, frame)
            if r.metadata.read_count == 1 {
                XCTAssertEqual(r.reads[0].high, 0); XCTAssertEqual(r.reads[0].low, 0)
                XCTAssertEqual(r.reads[0].site, 2)
            }
            return r
        })
        let end = try b.proposeClocked(v, event: .endShowWithoutRevision)
        XCTAssertEqual(reads, 0); XCTAssertNil(end.replacement.anchor)
        let reset = try b.proposeClocked(v, event: .beginPostResumeEpoch(minimum: nil))
        XCTAssertEqual(reads, 1); XCTAssertNil(reset.replacement.anchor)
        XCTAssertTrue(reset.replacement.times.allSatisfy { $0 == nil })
    }

    func testClockedUnrepresentableNativeQueueImageRefusesBeforeRead() throws {
        var p = WorldwideScreenVideoAdaptationPolicy(configuredTotalRTPBitrateBps: 12_000_000, baseFramesPerSecond: 60)
        p.networkAdaptationOwnerSeedCompleteRegression(at: t, route: .init(kind: .direct))
        let v = Value(policy: p, revision: 57, fastStatisticsAvailable: false, lane: nil,
            evidenceTime: nil, minimumCollectionSequence: nil, applied: nil)
        let s = try Snapshot.capture(v); expect(s, 38, 2, UInt64(bitPattern: -13))
        var reads = 0
        let b = Boundary(testClock: { reads += 1; return self.t })
        XCTAssertThrowsError(try b.proposeClocked(v, event: .beginPostResumeEpoch(minimum: nil)))
        XCTAssertEqual(reads, 0); identical(try Snapshot.capture(v), s)
    }
}
