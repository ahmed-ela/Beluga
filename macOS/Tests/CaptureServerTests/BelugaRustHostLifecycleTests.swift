import Foundation
import XCTest
@testable import CaptureServer

/// The reference is the pre-migration behavioral contract, not the Rust implementation.
/// These tests call the production Swift API so they cover the FFI adapter as well as the core.
final class BelugaRustHostLifecycleTests: XCTestCase {
    func testEveryReachableSmallStateAndEventMatchesIndependentReference() {
        typealias Node = (actual: WorldwideHostLifecycle, reference: LifecycleReference)
        var nodes: [Node] = [(WorldwideHostLifecycle(), LifecycleReference())]
        var seen: Set<LifecycleReference> = [LifecycleReference()]
        var index = 0
        while index < nodes.count {
            let node = nodes[index]
            for event in Self.events {
                var actual = node.actual, reference = node.reference
                assertStep(event, actual: &actual, reference: &reference)
                if seen.insert(reference).inserted { nodes.append((actual, reference)) }
            }
            index += 1
            guard nodes.count <= 32 else {
                XCTFail("The bounded reference exploration unexpectedly escaped its state space")
                return
            }
        }
        XCTAssertEqual(seen.count, 12, "Idle, inviting, stopped, and nine independent paired owners")
    }

    func testSeededLifecycleChurnHasTraceParityWithoutCollapsingAvailabilityAndMedia() {
        let events = Self.events.filter { if case .stop = $0 { return false }; return true }
        for seed in UInt64(1)...UInt64(16) {
            var actual = WorldwideHostLifecycle(), reference = LifecycleReference()
            var random = seed
            assertStep(.start(seed & 1 == 0), actual: &actual, reference: &reference)
            for _ in 0..<256 {
                random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let event = events[Int((random >> 32) % UInt64(events.count))]
                assertStep(event, actual: &actual, reference: &reference)
            }
            assertStep(.stop, actual: &actual, reference: &reference)
            XCTAssertEqual(actual.runState, .stopped)
            XCTAssertNil(actual.activeExchangeID)
            XCTAssertNil(actual.mediaExchangeID)
        }
    }

    func testDelayedDepartureCannotClearReplacementOrEndAnotherMediaOwner() {
        var actual = WorldwideHostLifecycle(), reference = LifecycleReference()
        for event in [LifecycleEvent.start(true), .availability("old"), .media("old"),
                      .peerLeft("old"), .availability("new"), .peerLeft("old"), .mediaEnded("new")] {
            assertStep(event, actual: &actual, reference: &reference)
        }
        XCTAssertEqual(actual.activeExchangeID, "new")
        XCTAssertEqual(actual.mediaExchangeID, "old")
        assertStep(.media("new"), actual: &actual, reference: &reference)
        XCTAssertEqual(actual.mediaExchangeID, "old", "A new availability owner cannot replace active media")
        assertStep(.mediaEnded("old"), actual: &actual, reference: &reference)
        assertStep(.media("new"), actual: &actual, reference: &reference)
        assertStep(.mediaEnded("old"), actual: &actual, reference: &reference)
        XCTAssertEqual(actual.activeExchangeID, "new")
        XCTAssertEqual(actual.mediaExchangeID, "new")
    }

    func testExchangeAdmissionCountsUtf8BytesAndPreservesOpaqueStringContents() {
        let cases: [(String, Bool)] = [
            ("", false),
            (String(repeating: "a", count: 64), true),
            (String(repeating: "a", count: 65), false),
            (String(repeating: "é", count: 32), true),
            (String(repeating: "é", count: 33), false),
            (String(repeating: "e\u{301}", count: 21), true),
            (String(repeating: "e\u{301}", count: 22), false),
            (String(repeating: "🧪", count: 16), true),
            (String(repeating: "🧪", count: 17), false),
            ("\0", true),
            (String(repeating: "a", count: 63) + "\0", true),
            (String(repeating: "\0", count: 65), false)
        ]
        for (id, admitted) in cases {
            var actual = WorldwideHostLifecycle(), reference = LifecycleReference()
            assertStep(.start(true), actual: &actual, reference: &reference)
            assertStep(.availability(id), actual: &actual, reference: &reference)
            XCTAssertEqual(actual.activeExchangeID, admitted ? id : nil)
            if admitted {
                XCTAssertEqual(actual.activeExchangeID.map { Array($0.utf8) }, Array(id.utf8), "Do not truncate or normalize stored IDs")
                assertStep(.media(id + "x"), actual: &actual, reference: &reference)
                XCTAssertNil(actual.mediaExchangeID)
                assertStep(.media(id), actual: &actual, reference: &reference)
                XCTAssertEqual(actual.mediaExchangeID.map { Array($0.utf8) }, Array(id.utf8))
                assertStep(.peerLeft(id + "x"), actual: &actual, reference: &reference)
                assertStep(.mediaEnded(id + "x"), actual: &actual, reference: &reference)
                XCTAssertEqual(actual.activeExchangeID, id)
                XCTAssertEqual(actual.mediaExchangeID, id)
            }
        }
    }

    func testCanonicalEquivalentStringsRetainExistingSwiftEqualityButNotRewriteStoredBytes() {
        for count in [1, 32] {
            let composed = String(repeating: "é", count: count)
            let decomposed = String(repeating: "e\u{301}", count: count)
            XCTAssertEqual(composed, decomposed)
            XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))
            var actual = WorldwideHostLifecycle(), reference = LifecycleReference()
            assertStep(.start(true), actual: &actual, reference: &reference)
            assertStep(.availability(composed), actual: &actual, reference: &reference)
            // The original mediaStarted checks String equality, not a second byte-size gate.
            // At count 32 the matching media ID is 96 bytes, versus the admitted 64-byte ID.
            assertStep(.media(decomposed), actual: &actual, reference: &reference)
            XCTAssertEqual(actual.activeExchangeID.map { Array($0.utf8) }, Array(composed.utf8))
            XCTAssertEqual(actual.mediaExchangeID.map { Array($0.utf8) }, Array(decomposed.utf8))
            assertStep(.peerLeft(decomposed), actual: &actual, reference: &reference)
            XCTAssertNil(actual.activeExchangeID)
            XCTAssertNotNil(actual.mediaExchangeID)
            assertStep(.mediaEnded(composed), actual: &actual, reference: &reference)
            XCTAssertNil(actual.mediaExchangeID)
        }
    }

    func testStopIsTerminalIdempotentAndClearsBothIndependentOwners() {
        var actual = WorldwideHostLifecycle(), reference = LifecycleReference()
        for event in [LifecycleEvent.start(true), .availability("old"), .media("old"),
                      .peerLeft("old"), .availability("new"), .stop] {
            assertStep(event, actual: &actual, reference: &reference)
        }
        let stopped = actual
        for event in Self.events {
            assertStep(event, actual: &actual, reference: &reference)
            XCTAssertEqual(actual, stopped)
        }
    }

    func testValueCopiesAndEqualityPreserveIndependentLifecycleAuthority() throws {
        var original = WorldwideHostLifecycle()
        XCTAssertEqual(original, WorldwideHostLifecycle())
        try original.start(hasPairedViewer: true)
        try original.availabilityReady(exchangeID: "old")
        try original.mediaStarted(exchangeID: "old")
        var copy = original
        XCTAssertEqual(copy, original)
        copy.availabilityPeerLeft(exchangeID: "old")
        XCTAssertNotEqual(copy, original)
        XCTAssertEqual(original.activeExchangeID, "old")
        XCTAssertEqual(copy.mediaExchangeID, "old")
        copy.stop()
        XCTAssertEqual(original.runState, .pairedAvailable)
        XCTAssertEqual(original.activeExchangeID, "old")
        XCTAssertEqual(original.mediaExchangeID, "old")
    }

    func testEqualityDependsOnPublicStateNotPrivateTokenAllocationHistory() throws {
        var churned = WorldwideHostLifecycle(), fresh = WorldwideHostLifecycle()
        try churned.start(hasPairedViewer: true)
        try fresh.start(hasPairedViewer: true)
        try churned.availabilityReady(exchangeID: "old")
        try churned.mediaStarted(exchangeID: "old")
        churned.availabilityPeerLeft(exchangeID: "old")
        churned.mediaEnded(exchangeID: "old")
        XCTAssertEqual(churned, fresh)

        try churned.availabilityReady(exchangeID: "é")
        try fresh.availabilityReady(exchangeID: "e\u{301}")
        XCTAssertEqual(churned, fresh, "Preserve Swift String equality across separate token allocation histories")
        XCTAssertThrowsError(try churned.mediaStarted(exchangeID: "wrong"))
        XCTAssertEqual(churned, fresh, "A refused event must not change public value equality")
    }

    private static let events: [LifecycleEvent] = [
        .start(false), .start(true), .durable,
        .availability("old"), .availability("new"), .availability(""),
        .media("old"), .media("new"), .media(""),
        .peerLeft("old"), .peerLeft("new"), .peerLeft(""),
        .mediaEnded("old"), .mediaEnded("new"), .mediaEnded(""), .stop
    ]

    private func assertStep(_ event: LifecycleEvent, actual: inout WorldwideHostLifecycle,
                            reference: inout LifecycleReference,
                            file: StaticString = #filePath, line: UInt = #line) {
        let previousActual = actual, previousReference = reference
        let expectedAccepted = reference.apply(event)
        let accepted: Bool
        do { try event.apply(to: &actual); accepted = true }
        catch {
            accepted = false
            XCTAssertEqual(error as? WorldwideHostLifecycleError, .invalidTransition, file: file, line: line)
        }
        XCTAssertEqual(accepted, expectedAccepted, file: file, line: line)
        XCTAssertEqual(actual.runState, reference.expectedRunState, file: file, line: line)
        XCTAssertEqual(actual.activeExchangeID, reference.active, file: file, line: line)
        XCTAssertEqual(actual.mediaExchangeID, reference.media, file: file, line: line)
        if !expectedAccepted {
            XCTAssertEqual(actual, previousActual, "Rejected transitions must not partially mutate", file: file, line: line)
            XCTAssertEqual(reference, previousReference, file: file, line: line)
        }
    }
}

private enum LifecycleEvent {
    case start(Bool), durable, availability(String), media(String), peerLeft(String), mediaEnded(String), stop

    func apply(to lifecycle: inout WorldwideHostLifecycle) throws {
        switch self {
        case .start(let paired): try lifecycle.start(hasPairedViewer: paired)
        case .durable: try lifecycle.durablePairingRecordAvailable()
        case .availability(let id): try lifecycle.availabilityReady(exchangeID: id)
        case .media(let id): try lifecycle.mediaStarted(exchangeID: id)
        case .peerLeft(let id): lifecycle.availabilityPeerLeft(exchangeID: id)
        case .mediaEnded(let id): lifecycle.mediaEnded(exchangeID: id)
        case .stop: lifecycle.stop()
        }
    }
}

private struct LifecycleReference: Hashable {
    private enum Phase: Hashable { case idle, inviting, paired, stopped }
    private var phase: Phase = .idle
    private(set) var active: String?
    private(set) var media: String?

    var expectedRunState: WorldwideHostLifecycle.RunState {
        switch phase {
        case .idle: .idle
        case .inviting: .inviting
        case .paired: .pairedAvailable
        case .stopped: .stopped
        }
    }

    mutating func apply(_ event: LifecycleEvent) -> Bool {
        switch event {
        case .start(let paired):
            guard phase == .idle else { return false }
            phase = paired ? .paired : .inviting
        case .durable:
            guard phase == .inviting else { return false }
            phase = .paired
        case .availability(let id):
            guard phase == .paired, active == nil, !id.isEmpty, id.utf8.count <= 64 else { return false }
            active = id
        case .media(let id):
            guard phase == .paired, active == id, media == nil else { return false }
            media = id
        case .peerLeft(let id):
            if active == id { active = nil }
        case .mediaEnded(let id):
            if media == id { media = nil }
        case .stop:
            phase = .stopped; active = nil; media = nil
        }
        return true
    }
}
