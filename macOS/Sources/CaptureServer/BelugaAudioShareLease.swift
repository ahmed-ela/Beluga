import Foundation

/// Callback-visible owner liveness. Wall-clock jumps and a stalled signaling actor cannot grant
/// PCM after the monotonic deadline. A closed lease cannot be revived by a late nonce ACK.
final class BelugaAudioShareLease: @unchecked Sendable {
    private let lock = NSLock()
    private let now: @Sendable () -> UInt64
    private let absoluteDeadline: UInt64
    private var deadline: UInt64
    private var terminal = false
    private var pending: (nonce: String, sentAt: UInt64)?

    init(absoluteDeadline: UInt64, authenticationDeadline: UInt64,
         now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.absoluteDeadline = absoluteDeadline
        deadline = min(authenticationDeadline, absoluteDeadline)
        self.now = now
    }

    var isValid: Bool { lock.withLock { validLocked() } }

    func expectAcknowledgement(nonce: String) -> Bool {
        lock.withLock {
            guard validLocked(), pending == nil,
                  (try? BelugaAudioShareEncoding.decode(nonce, count: 16...16)) != nil else { return false }
            pending = (nonce, now())
            return true
        }
    }

    /// Controller supplies an authenticated exact-schema ACK; time mapping starts at request
    /// transmission, not response receipt, so RTT or processing delay never extends the lease.
    func acknowledge(nonce: String, leaseMilliseconds: UInt64) -> Bool {
        lock.withLock {
            guard validLocked(), let pending, pending.nonce == nonce,
                  (1...15_000).contains(leaseMilliseconds) else { return false }
            let proposed = pending.sentAt.addingReportingOverflow(leaseMilliseconds * 1_000_000)
            guard !proposed.overflow, proposed.partialValue > now() else {
                terminal = true; return false
            }
            deadline = min(absoluteDeadline, proposed.partialValue)
            self.pending = nil
            return true
        }
    }

    func revoke() { lock.withLock { terminal = true; pending = nil } }

    private func validLocked() -> Bool {
        if now() >= deadline { terminal = true; pending = nil }
        return !terminal
    }
}
