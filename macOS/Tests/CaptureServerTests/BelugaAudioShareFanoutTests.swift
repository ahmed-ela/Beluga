import AudioToolbox
import CaptureCore
import CoreMedia
import Foundation
import XCTest
@testable import CaptureServer

final class BelugaAudioShareFanoutTests: XCTestCase {
    func testReentrantRevocationDoesNotHoldFanoutMutexAcrossNativeDelivery() {
        let fanout = BelugaAudioShareFanout(deadlineUptimeNanoseconds: 100, now: { 1 })
        let completed = ShareClock()
        completed.set(0)
        let sink = ShareSink()
        sink.onCapture = {
            let returned = DispatchSemaphore(value: 0)
            DispatchQueue.global().async { fanout.revoke(); returned.signal() }
            if returned.wait(timeout: .now() + 1) == .success { completed.set(1) }
        }
        XCTAssertTrue(fanout.attach(sink, listenerID: UUID()))
        deliver(fanout)
        XCTAssertEqual(completed.read(), 1)
        XCTAssertEqual(fanout.listenerCount, 0)
    }

    func testExpiryAndOwnerLeaseAreCheckedBeforeEveryListener() {
        let clock = ShareClock()
        let lease = BelugaAudioShareLease(absoluteDeadline: 1_000, authenticationDeadline: 100,
                                         now: clock.read)
        let fanout = BelugaAudioShareFanout(deadlineUptimeNanoseconds: 1_000, now: clock.read, lease: lease)
        let first = ShareSink(), second = ShareSink()
        first.onCapture = { clock.set(100) }
        XCTAssertTrue(fanout.attach(first, listenerID: UUID()))
        XCTAssertTrue(fanout.attach(second, listenerID: UUID()))
        deliver(fanout)
        XCTAssertEqual(first.frames, [480])
        XCTAssertTrue(second.frames.isEmpty, "Slow earlier delivery must not extend a later listener's lease")
        XCTAssertEqual(first.revocations, 1)
        XCTAssertEqual(second.revocations, 1)
    }
    func testBoundedIndependentListenersReceiveExactBorrowedCallback() {
        let clock = ShareClock()
        let fanout = BelugaAudioShareFanout(deadlineUptimeNanoseconds: 100, now: clock.read)
        let sinks = (0..<8).map { _ in ShareSink() }
        for sink in sinks { XCTAssertTrue(fanout.attach(sink, listenerID: UUID())) }
        XCTAssertFalse(fanout.attach(ShareSink(), listenerID: UUID()))
        deliver(fanout)
        XCTAssertEqual(fanout.listenerCount, 8)
        XCTAssertTrue(sinks.allSatisfy { $0.frames == [480] && $0.revocations == 0 })
        fanout.revoke()
        deliver(fanout)
        XCTAssertEqual(fanout.listenerCount, 0)
        XCTAssertTrue(sinks.allSatisfy { $0.frames == [480] && $0.revocations == 1 })
        XCTAssertFalse(fanout.attach(ShareSink(), listenerID: UUID()))
    }

    func testDuplicateIDAndDetachmentCannotDisplaceAnotherListener() {
        let fanout = BelugaAudioShareFanout(deadlineUptimeNanoseconds: 100, now: { 1 })
        let id = UUID(), otherID = UUID()
        let first = ShareSink(), second = ShareSink(), replacement = ShareSink()
        XCTAssertTrue(fanout.attach(first, listenerID: id))
        XCTAssertFalse(fanout.attach(replacement, listenerID: id))
        XCTAssertTrue(fanout.attach(second, listenerID: otherID))
        fanout.detach(listenerID: id)
        deliver(fanout)
        XCTAssertEqual(first.revocations, 1)
        XCTAssertTrue(first.frames.isEmpty)
        XCTAssertTrue(replacement.frames.isEmpty)
        XCTAssertEqual(second.frames, [480])
        XCTAssertEqual(second.revocations, 0)
    }

    func testDeadlineClosesCaptureEvenIfSignalingAndMediaRemainConnected() {
        let clock = ShareClock()
        let fanout = BelugaAudioShareFanout(deadlineUptimeNanoseconds: 100, now: clock.read)
        let sink = ShareSink()
        XCTAssertTrue(fanout.attach(sink, listenerID: UUID()))
        clock.set(99); deliver(fanout)
        clock.set(100); deliver(fanout)
        clock.set(1); deliver(fanout)
        XCTAssertEqual(sink.frames, [480])
        XCTAssertEqual(sink.revocations, 1, "Expired authorization never reopens")
        XCTAssertFalse(fanout.attach(ShareSink(), listenerID: UUID()))
    }

    private func deliver(_ fanout: BelugaAudioShareFanout) {
        var list = AudioBufferList(mNumberBuffers: 0, mBuffers: AudioBuffer())
        withUnsafePointer(to: &list) {
            fanout.consumeSystemAudioFrames($0, format: AudioStreamBasicDescription(),
                                             frameCount: 480, presentationTime: .zero)
        }
    }
}

private final class ShareClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 1
    func read() -> UInt64 { lock.withLock { value } }
    func set(_ value: UInt64) { lock.withLock { self.value = value } }
}

private final class ShareSink: BelugaAudioShareSink, @unchecked Sendable {
    var onCapture: @Sendable () -> Void = {}
    private(set) var frames: [UInt32] = []
    private(set) var revocations = 0
    func capture(sampleBuffer: CMSampleBuffer) { frames.append(UInt32(CMSampleBufferGetNumSamples(sampleBuffer))) }
    func capture(audioBufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription,
                 frameCount: UInt32, presentationTime: CMTime) { frames.append(frameCount); onCapture() }
    func revokeCapture() { revocations += 1 }
}
