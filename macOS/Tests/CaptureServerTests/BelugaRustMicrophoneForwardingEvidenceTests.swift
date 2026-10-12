import BelugaCore
import XCTest
@testable import CaptureServer

#if DEBUG

/// Copied values only: no driver, peer, track, output queue, device or clock is
/// constructed. Reference predicates below are the original Swift test oracle.
final class BelugaRustMicrophoneForwardingEvidenceTests: XCTestCase {
    private typealias Bridge = BelugaRustMicrophoneForwardingEvidence
    private typealias NativeMark = WorldwideIPhoneMicrophoneInboundMediaWatermark

    private func progress(_ flags: Int, callbacks: UInt64, frames: UInt64) -> BlackHoleMicrophoneOutputProgressSnapshot {
        BlackHoleMicrophoneOutputProgressSnapshot(queueRunning: flags & 1 != 0,
            postStartCallbackCount: callbacks, requestedFrameCount: 777,
            successfulPullCount: flags & 4 != 0 ? 1 : 0,
            successfulFrameCount: flags & 8 != 0 ? frames : 0,
            silenceFallbackCount: 7, silenceFrameCount: 9,
            enqueueFailureCount: flags & 2 != 0 ? 0 : 1, lastEnqueueStatus: 123)
    }
    private func mark(_ values: [UInt64?]) -> NativeMark {
        precondition(values.count == 4)
        return NativeMark(packetsReceived: values[0], bytesReceived: values[1],
            jitterBufferEmittedCount: values[2], totalSamplesReceived: values[3])
    }
    private func bytes<T>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value) { Array($0) } }
    private func flip<T>(_ value: T, at byte: Int) -> T {
        var copy = value
        withUnsafeMutableBytes(of: &copy) { $0[byte] ^= 1 }
        return copy
    }
    private enum SampledFreshness {
        case decided(Bool)
        case needsDecision(Bridge.FreshnessSnapshot, UInt64)
    }
    // Test-only counted scalar clock orchestration. No inout bridge or native
    // owner borrow spans this callback; both production adapter calls are fixed.
    private func sample(_ plan: Bridge.FreshnessPlan, readNow: () -> UInt64) -> SampledFreshness {
        switch plan {
        case .decided(let value): return .decided(value)
        case .needsNow(let snapshot): return .needsDecision(snapshot, readNow())
        }
    }
    private func assertRefused<T>(_ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? Bridge.Failure, .refused, file: file, line: line)
        }
    }

    func testReadinessMatchesBothOriginalIndependentVotes() throws {
        XCTAssertTrue(Bridge.layoutIsExact)
        for beforeFlags in 0..<16 {
            for afterFlags in 0..<16 {
                let previous = progress(beforeFlags, callbacks: 10, frames: 100)
                for (callbacks, frames): (UInt64, UInt64) in [(9, 99), (10, 100), (11, 101)] {
                    let current = progress(afterFlags, callbacks: callbacks, frames: frames)
                    var bridge = Bridge()
                    let decision = try bridge.readiness(current: current, previous: previous)
                    XCTAssertEqual(decision.ready, WorldwideIPhoneMicrophoneForwardingProgressEvaluator.isReady(current))
                    XCTAssertEqual(decision.continuing, WorldwideIPhoneMicrophoneForwardingProgressEvaluator.provesContinuingHealth(
                        previous: previous, current: current))
                    XCTAssertFalse(bridge.hasNativeFault)
                }
            }
        }
        var bridge = Bridge()
        XCTAssertEqual(try bridge.readiness(current: progress(15, callbacks: .max, frames: .max), previous: nil),
            Bridge.ReadinessDecision(ready: true, continuing: false))
    }

    func testWatermarkMatchesOriginalGuardedTransitionAndOptionalHistories() throws {
        let history: [NativeMark?] = [nil, mark([nil, nil, nil, nil]), mark([0, 0, 0, 0]),
            mark([.max, .max, .max, .max]), mark([10, 100, 20, 200]), mark([nil, 101, nil, nil]),
            mark([9, 102, nil, nil]), mark([11, 103, 21, 201]), mark([10, 100, 21, 680])]
        for previous in history {
            for current in history {
                let continuous = current?.isContinuous(from: previous) ?? false
                let advanced = continuous && (current?.advances(from: previous) ?? false)
                let retained = continuous ? current?.preservingMaximums(from: previous) : previous
                var bridge = Bridge()
                XCTAssertEqual(try bridge.watermark(previous: previous, current: current),
                    Bridge.WatermarkDecision(retained: retained, continuous: continuous, didAdvance: advanced))
                XCTAssertFalse(bridge.hasNativeFault)
            }
        }
        var bridge = Bridge()
        let old = mark([10, 100, 20, 200])
        let gap = try bridge.watermark(previous: old, current: mark([nil, 101, nil, nil]))
        XCTAssertEqual(gap.retained, mark([10, 101, 20, 200]))
        let lower = try bridge.watermark(previous: gap.retained, current: mark([9, 102, nil, nil]))
        XCTAssertEqual(lower, Bridge.WatermarkDecision(retained: gap.retained, continuous: false, didAdvance: false))
        let greater = try bridge.watermark(previous: lower.retained, current: mark([11, 103, 21, 201]))
        XCTAssertEqual(greater, Bridge.WatermarkDecision(retained: mark([11, 103, 21, 201]), continuous: true, didAdvance: true))
        // Present(all nil) is not whole None; production Service intentionally
        // constructs the former when inboundAudio is absent.
        XCTAssertEqual(try bridge.watermark(previous: nil, current: mark([nil, nil, nil, nil])).retained,
            mark([nil, nil, nil, nil]))
        XCTAssertNil(try bridge.watermark(previous: nil, current: nil).retained)
    }

    func testFreshnessMatchesOriginalConditionalClockAndExactDeadline() throws {
        for deadline: UInt64? in [nil, 0, 100, .max] {
            for advancement: UInt64 in [0, 1, .max] {
                for stale in [-1, 0, 2, 3, Int.max] {
                    for maximum in [1, 3] {
                        for now: UInt64 in [0, 99, 100, .max] {
                            var reads = 0
                            var bridge = Bridge()
                            let plan = try bridge.planFreshness(advancementCount: advancement,
                                consecutiveStaleSamples: stale, maximumStaleSamples: maximum,
                                deadlineNanoseconds: deadline)
                            let result: Bool
                            switch sample(plan, readNow: { reads += 1; return now }) {
                            case .decided(let value): result = value
                            case .needsDecision(let snapshot, let clock):
                                result = try bridge.finishFreshness(snapshot, now: clock)
                            }
                            let reachesClock = deadline != nil && advancement > 0 && stale < maximum
                            XCTAssertEqual(reads, reachesClock ? 1 : 0)
                            XCTAssertEqual(result, reachesClock && deadline.map({ now < $0 }) == true)
                            XCTAssertFalse(bridge.hasNativeFault)
                        }
                    }
                }
            }
        }
    }

    func testReadinessRejectsEveryReturnedByteAndLatchesWithoutFallback() {
        let previous = progress(15, callbacks: 10, frames: 100)
        let current = progress(15, callbacks: 11, frames: 101)
        for byte in 0..<MemoryLayout<Bridge.ReadinessResult>.size {
            var calls = 0
            var bridge = Bridge(mutations: .init(readiness: { _, actual in calls += 1; return self.flip(actual, at: byte) }))
            assertRefused(try bridge.readiness(current: current, previous: previous))
            XCTAssertTrue(bridge.hasNativeFault)
            XCTAssertThrowsError(try bridge.readiness(current: current, previous: previous)) { error in
                XCTAssertEqual(error as? Bridge.Failure, .faulted)
            }
            XCTAssertEqual(calls, 1)
        }
    }

    func testWatermarkRejectsEveryReturnedByteWithoutChangingNativeHistory() {
        let previous = mark([10, 100, 20, 200]), current = mark([11, 101, nil, nil])
        for byte in 0..<MemoryLayout<Bridge.WatermarkResult>.size {
            var bridge = Bridge(mutations: .init(watermark: { _, _, actual in self.flip(actual, at: byte) }))
            assertRefused(try bridge.watermark(previous: previous, current: current))
            XCTAssertTrue(bridge.hasNativeFault)
            XCTAssertEqual(previous, mark([10, 100, 20, 200]))
        }
        // Coherent, shape-valid foreign successor and forged growth are denied,
        // not accepted just because reserved fields and booleans are in range.
        var bridge = Bridge(mutations: .init(watermark: { _, _, actual in
            var copy = actual; copy.state.retained.fields.0.value = 999; return copy
        }))
        assertRefused(try bridge.watermark(previous: previous, current: current))
        bridge = Bridge(mutations: .init(watermark: { _, _, actual in
            var copy = actual; copy.did_advance = 1; return copy
        }))
        assertRefused(try bridge.watermark(previous: previous, current: mark([10, 100, 21, 680])))
    }

    func testCorruptedFirstFreshnessResultNeverReadsNativeClock() {
        for byte in 0..<MemoryLayout<Bridge.FreshnessResult>.size {
            var reads = 0
            var bridge = Bridge(mutations: .init(freshness: { _, _, actual in self.flip(actual, at: byte) }))
            func decision() throws -> Bool {
                let plan = try bridge.planFreshness(advancementCount: 1, consecutiveStaleSamples: 0,
                    maximumStaleSamples: 3, deadlineNanoseconds: 100)
                switch sample(plan, readNow: { reads += 1; return 99 }) {
                case .decided(let value): return value
                case .needsDecision(let snapshot, let now): return try bridge.finishFreshness(snapshot, now: now)
                }
            }
            assertRefused(try decision())
            XCTAssertEqual(reads, 0); XCTAssertTrue(bridge.hasNativeFault)
        }
        var reads = 0
        var bridge = Bridge(mutations: .init(freshness: { _, _, _ in
            // A coherent request cannot manufacture even a pure clock plan.
            Bridge.FreshnessResult(abi_version: 1, status: 2, fresh: 0, reserved: 0)
        }))
        func decision() throws -> Bool {
            let plan = try bridge.planFreshness(advancementCount: 0, consecutiveStaleSamples: 0,
                maximumStaleSamples: 3, deadlineNanoseconds: 100)
            switch sample(plan, readNow: { reads += 1; return 99 }) {
            case .decided(let value): return value
            case .needsDecision(let snapshot, let now): return try bridge.finishFreshness(snapshot, now: now)
            }
        }
        assertRefused(try decision())
        XCTAssertEqual(reads, 0)
    }

    func testCorruptedSecondFreshnessResultReadsOnceButPublishesNoDecision() {
        for byte in 0..<MemoryLayout<Bridge.FreshnessResult>.size {
            var reads = 0, calls = 0
            var states: [[UInt8]] = []
            var nowPresence: [UInt32] = []
            var bridge = Bridge(mutations: .init(freshness: { before, event, actual in
                calls += 1; states.append(self.bytes(before)); nowPresence.append(event.now.present)
                return event.now.present == 1 ? self.flip(actual, at: byte) : actual
            }))
            func decision() throws -> Bool {
                let plan = try bridge.planFreshness(advancementCount: 1, consecutiveStaleSamples: 0,
                    maximumStaleSamples: 3, deadlineNanoseconds: 100)
                switch sample(plan, readNow: { reads += 1; return 99 }) {
                case .decided(let value): return value
                case .needsDecision(let snapshot, let now): return try bridge.finishFreshness(snapshot, now: now)
                }
            }
            assertRefused(try decision())
            XCTAssertEqual(reads, 1); XCTAssertEqual(calls, 2)
            XCTAssertEqual(nowPresence, [0, 1]); XCTAssertEqual(states.count, 2)
            XCTAssertEqual(states[0], states[1]); XCTAssertTrue(bridge.hasNativeFault)
        }
    }

    func testInvalidStatusZeroNeverBecomesLegitimateFalseAcrossFamilies() {
        let current = progress(0, callbacks: 0, frames: 0)
        var bridge = Bridge(mutations: .init(readiness: { _, actual in
            var copy = actual; copy.status = 0; return copy
        }))
        assertRefused(try bridge.readiness(current: current, previous: nil))
        bridge = Bridge(mutations: .init(readiness: { _, actual in
            var copy = actual; copy.ready = 1; copy.continuing = 1; return copy
        }))
        assertRefused(try bridge.readiness(current: current, previous: nil))
        bridge = Bridge(mutations: .init(watermark: { _, _, actual in
            var copy = actual; copy.status = 0; return copy
        }))
        assertRefused(try bridge.watermark(previous: nil, current: nil))
        var reads = 0
        bridge = Bridge(mutations: .init(freshness: { _, _, actual in
            var copy = actual; copy.status = 0; return copy
        }))
        func decision() throws -> Bool {
            let plan = try bridge.planFreshness(advancementCount: 0, consecutiveStaleSamples: 0,
                maximumStaleSamples: 3, deadlineNanoseconds: nil)
            switch sample(plan, readNow: { reads += 1; return 99 }) {
            case .decided(let value): return value
            case .needsDecision(let snapshot, let now): return try bridge.finishFreshness(snapshot, now: now)
            }
        }
        assertRefused(try decision())
        XCTAssertEqual(reads, 0)
    }
}

#endif
