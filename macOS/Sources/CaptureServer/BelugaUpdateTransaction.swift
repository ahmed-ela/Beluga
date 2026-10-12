import BelugaUpdateCore

/// Pure lifecycle policy for Sparkle's serial update driver. A check reservation fences new
/// runtime admission before Sparkle begins its asynchronous installer probe. Only its actual
/// matching completion releases that reservation; download/cancel/UI callbacks do not.
struct BelugaUpdateTransaction: Equatable, Sendable {
    enum Check: Equatable, Sendable {
        case interactive, background, information
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case requested
        case checking(Check)
        case installing(Check)
    }

    private var phase = Phase.idle

    func isUpdateInProgress(sparkleSessionInProgress: Bool) -> Bool {
        phase != .idle || sparkleSessionInProgress
    }

    mutating func reserveInteractiveCheck(
        admission: BelugaUpdateAdmission, sparkleSessionInProgress: Bool
    ) -> Bool {
        guard !isUpdateInProgress(sparkleSessionInProgress: sparkleSessionInProgress),
              admission.permitsUpdate else { return false }
        phase = .requested
        return true
    }

    mutating func admitCheck(_ check: Check, admission: BelugaUpdateAdmission) -> Bool {
        switch phase {
        case .idle:
            guard admission.permitsUpdate else { return false }
        case .requested:
            guard check == .interactive else { return false }
        case .checking:
            // Sparkle can immediately replace a finished background driver with a user-facing
            // one without a didFinishUpdateCycle callback. Retain the fence across that serial
            // continuation, including a denied new check, until its matching completion.
            break
        case .installing:
            return false
        }
        phase = .checking(check)
        return admission.permitsUpdate
    }

    mutating func admitInstallation(
        admission: BelugaUpdateAdmission, sparkleSessionInProgress: Bool
    ) -> Bool {
        let check: Check
        switch phase {
        case .checking(let active), .installing(let active): check = active
        case .idle, .requested: return false
        }
        guard check != .information, sparkleSessionInProgress,
              admission.permitsUpdate else { return false }
        phase = .installing(check)
        return true
    }

    mutating func finishCycle(_ check: Check, sparkleSessionInProgress: Bool) {
        guard !sparkleSessionInProgress else { return }
        switch phase {
        case .requested where check == .interactive:
            phase = .idle
        case .checking(let active), .installing(let active):
            if active == check { phase = .idle }
        default:
            break
        }
    }
}
