import BelugaCore

enum BelugaMediaHandoffDisabledReason: UInt32, Sendable {
    case ready = 0
    case stopped = 1
    case notStarted = 2
    case changingPhone = 3
    case requestInFlight = 4
    case waitingForSession = 5
    case targetUnavailable = 6
    case commandUnavailable = 7
    case incompatibleCore = 8

    var message: String? {
        switch self {
        case .ready: nil
        case .stopped: "Beluga is stopped. Restart it to move media."
        case .notStarted: "Start Beluga on this Mac first."
        case .changingPhone: "Wait for the phone selection to finish."
        case .requestInFlight: "Requesting playback on the phone…"
        case .waitingForSession: "Waiting for confirmed phone-session readiness."
        case .targetUnavailable: "Connect the selected phone before moving media."
        case .commandUnavailable: "Media handoff is not ready on this host."
        case .incompatibleCore: "Media handoff is unavailable in this build."
        }
    }
}

struct BelugaMediaHandoffControlState: Sendable, Equatable {
    let visible: Bool
    let enabled: Bool
    let reason: BelugaMediaHandoffDisabledReason
}

enum BelugaRustHandoffPolicy {
    static func evaluate(hasStarted: Bool, finished: Bool, changingPhone: Bool,
                         requestInFlight: Bool, sessionReady: Bool, targetPresent: Bool,
                         commandInstalled: Bool) -> BelugaMediaHandoffControlState {
        let values = [hasStarted, finished, changingPhone, requestInFlight,
                      sessionReady, targetPresent, commandInstalled]
        let flags = values.enumerated().reduce(UInt32(0)) { bits, entry in
            entry.element ? bits | (UInt32(1) << entry.offset) : bits
        }
        let result = beluga_core_handoff_menu_policy(1, flags)
        return decode(result, hasStarted: hasStarted)
    }

    static func decode(_ result: beluga_core_handoff_menu_policy_t,
                       hasStarted: Bool) -> BelugaMediaHandoffControlState {
        guard result.abi_version == 1, result.visible == (hasStarted ? 1 : 0), result.enabled <= 1,
              let reason = BelugaMediaHandoffDisabledReason(rawValue: result.reason),
              (result.enabled == 1) == (reason == .ready),
              result.enabled == 0 || result.visible == 1 else {
            return .init(visible: hasStarted, enabled: false, reason: .incompatibleCore)
        }
        return .init(visible: result.visible == 1, enabled: result.enabled == 1, reason: reason)
    }
}
