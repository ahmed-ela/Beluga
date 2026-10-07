import CaptureCore
import Foundation

/// Native mechanism dependencies. No route proof or transport authority is supplied.
struct WorldwideScreenServiceAudioRoutingDependencies: Sendable {
    let monitor: BlackHoleDeviceAvailabilityMonitor
    let lease: BlackHoleDefaultInputLease
    let invariant: WorldwideSafeOutputInvariant
    let writerGate: BlackHoleMicrophoneOutputAuthorizationGate?
    let cleanupRetainer: any WorldwideBlackHoleAudioRoutingCleanupRetaining
    let deferredInputCleanup: @Sendable (Int) -> Bool
    let makeDiagnosticsWriter: @Sendable () -> WorldwideAudioClientDiagnosticsReportWriter
    #if DEBUG
    let isInertPolicyFixture: Bool
    #endif

    static func live() -> Self {
        #if DEBUG
        return Self(monitor: .init(), lease: .init(), invariant: .init(), writerGate: .init(),
            cleanupRetainer: WorldwideBlackHoleAudioRoutingCleanupRetainer.shared,
            deferredInputCleanup: {
                BlackHoleDefaultInputLease.redriveRetainedDeferredCleanup(maximumAttemptCount: $0)
            }, makeDiagnosticsWriter: { .init() }, isInertPolicyFixture: false)
        #else
        return Self(monitor: .init(), lease: .init(), invariant: .init(), writerGate: .init(),
            cleanupRetainer: WorldwideBlackHoleAudioRoutingCleanupRetainer.shared,
            deferredInputCleanup: {
                BlackHoleDefaultInputLease.redriveRetainedDeferredCleanup(maximumAttemptCount: $0)
            }, makeDiagnosticsWriter: { .init() })
        #endif
    }
}
