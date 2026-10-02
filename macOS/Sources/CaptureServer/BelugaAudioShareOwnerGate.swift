import Foundation

/// Independent, callback-safe host authority. Revocation performs no native work and never
/// calls back into the host lifetime. No async completion can reactivate a retired owner.
final class BelugaAudioShareOwnerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activated = false
    private var retired = false

    var isValid: Bool { lock.withLock { activated && !retired } }

    @discardableResult
    func activate() -> Bool {
        lock.withLock {
            guard !retired, !activated else { return false }
            activated = true
            return true
        }
    }

    func revoke() { lock.withLock { retired = true } }
}

/// Menu-only auxiliary capture ownership. The default CLI has no additional service.
/// Only metadata gates may run synchronously; native retirement is awaited separately.
struct CaptureAdditionalMediaLifetime: Sendable {
    let gate: BelugaAudioShareOwnerGate
    let becameOwned: @Sendable () -> Void
    let shutdown: @Sendable () async -> Bool
}
