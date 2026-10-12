import AudioToolbox
import CaptureCore
import CoreMedia
import Foundation

/// Borrowed source-clock input only. Browser sinks have no microphone, route, or control API.
protocol BelugaAudioShareSink: AnyObject, Sendable {
    func capture(sampleBuffer: CMSampleBuffer)
    func capture(audioBufferList: UnsafePointer<AudioBufferList>,
                 format: AudioStreamBasicDescription, frameCount: UInt32, presentationTime: CMTime)
    func revokeCapture()
}

/// One independent browser tap feeds at most eight input-only peers. Logical retirement closes
/// each sink's one-way admission gate; already admitted native callbacks drain in its owner.
/// No fanout mutex spans native code. No PCM is retained, queued, logged, or clocked here.
/// The existing phone source, FaceTime challenge, and microphone leases are not shared.
final class BelugaAudioShareFanout: SystemAudioSampleConsumer, @unchecked Sendable {
    static let maximumListeners = 8
    private let lock = NSLock()
    private let deadline: UInt64
    private let now: @Sendable () -> UInt64
    private let onFailure: @Sendable () -> Void
    private let lease: BelugaAudioShareLease?
    private let ownerIsValid: @Sendable () -> Bool
    private struct Slot { let id: UUID; let sink: any BelugaAudioShareSink }
    private var sinks: [Slot] = []
    private var terminal = false

    init(deadlineUptimeNanoseconds: UInt64,
         now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
         lease: BelugaAudioShareLease? = nil,
         ownerIsValid: @escaping @Sendable () -> Bool = { true },
         onFailure: @escaping @Sendable () -> Void = {}) {
        deadline = deadlineUptimeNanoseconds
        self.now = now
        self.onFailure = onFailure
        self.lease = lease
        self.ownerIsValid = ownerIsValid
    }

    /// Duplicate IDs, overflow, a passed absolute deadline, and closed shares fail closed.
    func attach(_ sink: any BelugaAudioShareSink, listenerID: UUID) -> Bool {
        lock.withLock {
            guard validLocked(), !sinks.contains(where: { $0.id == listenerID }),
                  sinks.count < Self.maximumListeners else { return false }
            sinks.append(Slot(id: listenerID, sink: sink))
            return true
        }
    }

    func detach(listenerID: UUID) {
        let retired = lock.withLock { () -> Slot? in
            guard let index = sinks.firstIndex(where: { $0.id == listenerID }) else { return nil }
            return sinks.remove(at: index)
        }
        retired?.sink.revokeCapture()
    }

    func revoke() {
        let retired = lock.withLock { retireLocked() }
        for slot in retired { slot.sink.revokeCapture() }
    }

    var listenerCount: Int { lock.withLock { sinks.count } }

    func consumeSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
        for slot in snapshot() {
            guard snapshot().contains(where: { $0.id == slot.id }) else { continue }
            slot.sink.capture(sampleBuffer: sampleBuffer)
        }
    }

    func consumeSystemAudioFrames(_ audioBufferList: UnsafePointer<AudioBufferList>,
                                  format: AudioStreamBasicDescription, frameCount: UInt32,
                                  presentationTime: CMTime) {
        for slot in snapshot() {
            guard snapshot().contains(where: { $0.id == slot.id }) else { continue }
            slot.sink.capture(audioBufferList: audioBufferList, format: format,
                              frameCount: frameCount, presentationTime: presentationTime)
        }
    }

    func systemAudioCaptureSource(_ source: SystemAudioCaptureSource,
                                  didStopWithErrorDescription errorDescription: String) {
        // No native error payload (which may contain application identity) enters signaling.
        revoke()
        onFailure()
    }

    func systemAudioCaptureSource(_ source: SystemAudioCaptureSource,
                                  didObserveMacFaceTimeActivity observation:
                                    SystemAudioMacFaceTimeActivityObservation) {
        // Browser listeners have no phone/call observation authority.
    }

    private func validLocked() -> Bool {
        !terminal && ownerIsValid() && now() < deadline && (lease?.isValid ?? true)
    }

    private func snapshot() -> [Slot] {
        let (active, retired): ([Slot], [Slot]) = lock.withLock {
            validLocked() ? (sinks, []) : ([], retireLocked())
        }
        for slot in retired { slot.sink.revokeCapture() }
        return active
    }

    private func retireLocked() -> [Slot] {
        guard !terminal else { return [] }
        terminal = true
        let retired = sinks
        sinks.removeAll()
        return retired
    }
}
