// Copied ownership projection; no source/sink/auth/transport ownership crosses C.
import BelugaCore

enum WorldwideSystemAudioStartBridgeError: Error, Equatable, Sendable {
    case invalidBridge
}

enum BelugaRustSystemAudioStartBoundary {
    typealias Input = beluga_core_system_audio_start_facts_t
    typealias Output = beluga_core_system_audio_start_decision_t

    static var layoutIsExact: Bool {
        MemoryLayout<Input>.size == 32 && MemoryLayout<Input>.stride == 32
            && MemoryLayout<Input>.alignment == 4
            && MemoryLayout<Output>.size == 16 && MemoryLayout<Output>.stride == 16
            && MemoryLayout<Output>.alignment == 4
    }
    static func accepts(_ input: Input, _ output: Output) -> Bool {
        guard layoutIsExact, input.abi_version == 1, input.reserved == 0,
              input.is_live <= 1, input.is_paused_for_recovery <= 1,
              input.has_source <= 1, input.has_sink <= 1,
              input.has_valid_authorization <= 1, input.peer_generation_matches <= 1,
              output.abi_version == 1, output.reserved == 0, output.status == 1 else { return false }
        // Rejection-only custody: no successful Swift fallback is produced.
        let live = input.is_live == 1 && input.is_paused_for_recovery == 0
            && input.has_source == 1 && input.has_sink == 1
            && input.has_valid_authorization == 1 && input.peer_generation_matches == 1
        let resume = input.is_live == 0 && input.is_paused_for_recovery == 1
            && input.has_source == 1 && input.has_sink == 1
            && input.has_valid_authorization == 0 && input.peer_generation_matches == 1
        let new = input.is_live == 0 && input.is_paused_for_recovery == 0
            && input.has_source == 0 && input.has_sink == 0 && input.has_valid_authorization == 0
        switch output.mode {
        case 0: return !live && !resume && !new
        case 1: return live
        case 2: return resume
        case 3: return new
        default: return false
        }
    }
}

struct BelugaRustSystemAudioStartProducer: Sendable {
    typealias Boundary = BelugaRustSystemAudioStartBoundary
    let decide: @Sendable (Boundary.Input) -> Boundary.Output
    static let actual = Self(decide: { beluga_core_system_audio_start($0) })
}

/// Selects whether a healthy transport should publish, resume, or create system audio.
enum WorldwideSystemAudioStartMode: Equatable {
    case alreadyLive
    case resumeExisting
    case startNew
}

enum WorldwideSystemAudioRecoveryPolicy {
    static func startMode(isLive: Bool, isPausedForRecovery: Bool, hasSource: Bool,
                          hasSink: Bool, hasValidAuthorization: Bool,
                          peerGenerationMatches: Bool,
                          producer: BelugaRustSystemAudioStartProducer = .actual) throws
        -> WorldwideSystemAudioStartMode? {
        var input = BelugaRustSystemAudioStartBoundary.Input()
        input.abi_version = 1
        input.is_live = isLive ? 1 : 0
        input.is_paused_for_recovery = isPausedForRecovery ? 1 : 0
        input.has_source = hasSource ? 1 : 0
        input.has_sink = hasSink ? 1 : 0
        input.has_valid_authorization = hasValidAuthorization ? 1 : 0
        input.peer_generation_matches = peerGenerationMatches ? 1 : 0
        let output = producer.decide(input)
        guard BelugaRustSystemAudioStartBoundary.accepts(input, output) else {
            throw WorldwideSystemAudioStartBridgeError.invalidBridge
        }
        switch output.mode {
        case 0: return nil
        case 1: return .alreadyLive
        case 2: return .resumeExisting
        case 3: return .startNew
        default: throw WorldwideSystemAudioStartBridgeError.invalidBridge
        }
    }
}
