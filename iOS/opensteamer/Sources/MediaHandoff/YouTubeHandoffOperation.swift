import Foundation
import CoreFoundation
import WebRTCTransport
import BelugaCore

struct YouTubeHandoffRequest: Equatable, Sendable, Identifiable {
    let operationID: UUID
    let videoID: String
    let positionSeconds: Double
    let durationSeconds: Double
    let playbackRate: Double
    let deadlineUptime: Double
    let positionObservedAtUptime: Double
    var id: UUID { operationID }

    init(operationID: UUID, videoID: String, positionSeconds: Double,
         durationSeconds: Double, playbackRate: Double, deadlineUptime: Double,
         now: Double, positionObservedAtUptime: Double? = nil) throws {
        let observed = positionObservedAtUptime ?? now
        guard Self.validVideoID(videoID), now.isFinite, now >= 0,
              observed.isFinite, observed >= 0, observed <= now,
              positionSeconds.isFinite, positionSeconds >= 0,
              durationSeconds.isFinite, durationSeconds > positionSeconds,
              durationSeconds <= 31_536_000,
              playbackRate.isFinite, playbackRate > 0, playbackRate <= 16,
              deadlineUptime.isFinite, deadlineUptime > now,
              deadlineUptime - now <= 30 else { throw YouTubeHandoffFailure.invalidRequest }
        self.operationID = operationID
        self.videoID = videoID
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.playbackRate = playbackRate
        self.deadlineUptime = deadlineUptime
        self.positionObservedAtUptime = observed
    }

    func expectedPosition(at now: Double) -> Double {
        min(durationSeconds, positionSeconds + max(0, now - positionObservedAtUptime) * playbackRate)
    }

    static func validVideoID(_ value: String) -> Bool {
        value.utf8.count == 11 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0)
                || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

enum YouTubeHandoffFailure: String, Error, Equatable, Sendable {
    case invalidRequest, timedOut, notVisible, dismissed, replaced
    case playerUnavailable, wrongVideo, invalidBridge, clockChanged, unsupportedRate, positionChanged
    case playbackInterrupted, macPauseNotApplied, macPauseUnknown
}

enum YouTubeHandoffPhase: Equatable, Sendable {
    case preparing, ready, playRequired, verifying, confirmed
    case awaitingMacPause, localPlayback
    case failed(YouTubeHandoffFailure)

    func statusText(macPause: YouTubeHandoffMacPauseStatus) -> String {
        switch self {
        case .preparing: return "Loading YouTube…"
        case .ready: return "Waiting for playback at the Mac’s position…"
        case .playRequired: return "Tap Play in the YouTube player to continue."
        case .verifying: return "Confirming playback on this iPhone…"
        case .confirmed: return "Playback detected on this iPhone. The Mac has not been asked to pause yet."
        case .awaitingMacPause: return "Waiting for the Mac to confirm its pause…"
        case .localPlayback: return "Playback moved to this iPhone. The Mac source was paused."
        case .failed:
            switch macPause {
            case .pending, .unknown:
                return "The Mac’s pause status is uncertain. Check the Mac before trying another transfer."
            case .paused:
                return "The Mac source was paused. Playback on this iPhone has stopped."
            case .notApplied:
                return "The Mac did not apply the handoff pause. Playback on this iPhone has stopped."
            case .notRequested:
                return "Handoff stopped. No Mac pause was requested."
            }
        }
    }
}

enum YouTubeHandoffMacPauseStatus: Equatable, Sendable {
    case notRequested, pending, paused, notApplied, unknown
}

/// Provider playback observations, not WebRTC/offer authority or proof of acoustic output.
struct YouTubePhonePlaybackEvidence: Equatable, Sendable {
    let operationID: UUID
    let videoID: String
    let requestedPositionSeconds: Double
    let positionSeconds: Double
    let playbackRate: Double
    let observedAtUptime: Double
    fileprivate let evidenceID: UUID
}

enum YouTubeHandoffPlayerEvent: Equatable, Sendable {
    case playRequired
    case confirmed(YouTubePhonePlaybackEvidence)
    case movedToPhone
    case failed(YouTubeHandoffFailure)
}

struct YouTubeHandoffBridgeMessage: Equatable, Sendable {
    enum Kind: String, Sendable { case ready, blocked, sample, error, unsupportedRate }
    let kind: Kind
    let operationID: UUID
    let pageID: UUID
    let videoID: String
    let sequence: UInt32
    let state: Int?
    let position: Double?
    let duration: Double?
    let rate: Double?

    init?(body: Any) {
        guard let fields = body as? [String: Any],
              let rawKind = fields["kind"] as? String,
              let kind = Kind(rawValue: rawKind) else { return nil }
        let base: Set<String> = ["kind", "operation", "page", "video", "sequence"]
        let expected = kind == .sample ? base.union(["state", "position", "duration", "rate"]) : base
        guard Set(fields.keys) == expected,
              let rawOperation = fields["operation"] as? String,
              let rawPage = fields["page"] as? String,
              rawOperation.utf8.count == 36, rawPage.utf8.count == 36,
              let operation = UUID(uuidString: rawOperation),
              let page = UUID(uuidString: rawPage),
              operation.uuidString.lowercased() == rawOperation,
              page.uuidString.lowercased() == rawPage,
              let video = fields["video"] as? String,
              YouTubeHandoffRequest.validVideoID(video),
              let sequence = Self.number(fields["sequence"]),
              sequence.rounded(.towardZero) == sequence,
              sequence > 0, sequence <= Double(UInt32.max) else { return nil }
        var state: Int?
        var position: Double?
        var duration: Double?
        var rate: Double?
        if kind == .sample {
            guard let s = Self.number(fields["state"]), [-1.0, 0, 1, 2, 3, 5].contains(s),
                  let p = Self.number(fields["position"]), p >= 0, p <= 31_536_000,
                  let d = Self.number(fields["duration"]), d >= 0, d <= 31_536_000,
                  let r = Self.number(fields["rate"]), r > 0, r <= 16 else { return nil }
            state = Int(s); position = p; duration = d; rate = r
        }
        self.kind = kind; operationID = operation; pageID = page; videoID = video
        self.sequence = UInt32(sequence)
        self.state = state; self.position = position; self.duration = duration; self.rate = rate
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}

// Native exact-identity custody around the copied Rust phone-operation policy.
struct YouTubeHandoffOperation {
    typealias State = beluga_core_youtube_handoff_operation_state_t
    typealias Event = beluga_core_youtube_handoff_operation_event_t
    typealias Output = beluga_core_youtube_handoff_operation_result_t
    let request: YouTubeHandoffRequest
    let pageID: UUID
    private var core: State
    private var nextEvidenceToken: UInt64
    private var binding: (token: UInt64, proof: YouTubePhonePlaybackEvidence)?

    init(request: YouTubeHandoffRequest, pageID: UUID = UUID(), now: Double,
         nextEvidenceToken: UInt64 = 1) {
        self.request = request; self.pageID = pageID
        self.nextEvidenceToken = nextEvidenceToken
        let raw = beluga_core_youtube_handoff_operation_request_t(
            position: request.positionSeconds.bitPattern, duration: request.durationSeconds.bitPattern,
            rate: request.playbackRate.bitPattern, deadline: request.deadlineUptime.bitPattern,
            position_observed_at: request.positionObservedAtUptime.bitPattern)
        core = beluga_core_youtube_handoff_operation_initial(raw, now.bitPattern)
        if !BelugaRustYouTubeHandoffOperationBoundary.valid(core)
            || BelugaRustYouTubeHandoffOperationBoundary.requestWords(core.request)
                != BelugaRustYouTubeHandoffOperationBoundary.requestWords(raw)
            || core.last_now != now.bitPattern || core.phase != 0 || core.flags != 0
            || core.presence != 0 || core.mac_pause != 0 || core.sequence != 0 {
            core = State(); core.abi = 1; core.request = raw; core.last_now = now.bitPattern
            closeInvalidBoundary()
        }
    }

    var phase: YouTubeHandoffPhase {
        switch core.phase {
        case 0: .preparing
        case 1: .ready
        case 2: .playRequired
        case 3: .verifying
        case 4: .confirmed
        case 5: .awaitingMacPause
        case 6: .localPlayback
        default: .failed(Self.failure(core.failure) ?? .invalidBridge)
        }
    }
    var isVisible: Bool { core.flags & 1 != 0 }
    var evidence: YouTubePhonePlaybackEvidence? { binding?.proof }
    var isTerminal: Bool { core.phase == 7 }
    var macPauseStatus: YouTubeHandoffMacPauseStatus {
        switch core.mac_pause {
        case 0: .notRequested
        case 1: .pending
        case 2: .paused
        case 3: .notApplied
        default: .unknown
        }
    }

    mutating func visibilityChanged(_ visible: Bool, now: Double) -> YouTubeHandoffPlayerEvent? {
        var event = Event(); event.opcode = 0; event.flags = visible ? 1 : 0
        event.now = now.bitPattern
        return apply(event).event
    }
    mutating func poll(now: Double) -> YouTubeHandoffPlayerEvent? {
        var event = Event(); event.opcode = 1; event.now = now.bitPattern
        return apply(event).event
    }
    mutating func receive(_ message: YouTubeHandoffBridgeMessage,
                          now: Double) -> YouTubeHandoffPlayerEvent? {
        var event = Event(); event.opcode = 2; event.now = now.bitPattern
        event.sequence = message.sequence; event.candidate_token = nextEvidenceToken
        if message.operationID == request.operationID { event.flags |= 2 }
        if message.pageID == pageID { event.flags |= 4 }
        if message.videoID == request.videoID { event.flags |= 8 }
        switch message.kind {
        case .ready: event.kind = 0
        case .blocked: event.kind = 1
        case .sample: event.kind = 2
        case .error: event.kind = 3
        case .unsupportedRate: event.kind = 4
        }
        if let value = message.state { event.presence |= 1; event.sample_state = Int32(value) }
        if let value = message.position { event.presence |= 2; event.sample_position = value.bitPattern }
        if let value = message.duration { event.presence |= 4; event.sample_duration = value.bitPattern }
        if let value = message.rate { event.presence |= 8; event.sample_rate = value.bitPattern }
        return apply(event).event
    }
    mutating func isCurrent(_ proof: YouTubePhonePlaybackEvidence, now: Double) -> Bool {
        apply(proofEvent(opcode: 3, proof: proof, now: now)).accepted
    }
    mutating func beginMacPause(using proof: YouTubePhonePlaybackEvidence, now: Double) -> Bool {
        apply(proofEvent(opcode: 4, proof: proof, now: now)).accepted
    }
    mutating func completeMacPause(operationID: UUID, result: WebRTCMediaHandoffResult,
                                   now: Double) -> YouTubeHandoffPlayerEvent? {
        var event = Event(); event.opcode = 5; event.now = now.bitPattern
        event.flags = operationID == request.operationID ? 32 : 0
        switch result {
        case .macPaused: event.completion = 1
        case .notApplied: event.completion = 2
        case .outcomeUnknown: event.completion = 3
        }
        return apply(event).event
    }
    mutating func fail(_ failure: YouTubeHandoffFailure) -> YouTubeHandoffPlayerEvent? {
        var event = Event(); event.opcode = 6; event.failure = Self.failureCode(failure)
        return apply(event).event
    }

    private func proofEvent(opcode: UInt32, proof: YouTubePhonePlaybackEvidence, now: Double) -> Event {
        var event = Event(); event.opcode = opcode; event.now = now.bitPattern
        // The whole synthesized native equality includes the private evidence UUID.
        // Double equality admits signed-zero aliases; scalar storage keeps original bits.
        if let binding, binding.proof == proof {
            event.flags = 16; event.proof_token = binding.token
        }
        return event
    }

    private mutating func apply(_ event: Event) -> (event: YouTubeHandoffPlayerEvent?, accepted: Bool) {
        let output = beluga_core_youtube_handoff_operation_step(1, core, event)
        return accept(event, output: output)
    }

    // Copied-output custody is validated before a UUID, callback or new proof is produced.
    private mutating func accept(_ event: Event, output: Output)
        -> (event: YouTubeHandoffPlayerEvent?, accepted: Bool) {
        guard BelugaRustYouTubeHandoffOperationBoundary.accepts(before: core, event: event, output: output),
              (binding?.token ?? 0) == core.evidence.token else {
            let wasTerminal = isTerminal
            // A current correlated native reply is still a known Mac outcome
            // even when the foreign copied result fails integrity checks.
            if let outcome = BelugaRustYouTubeHandoffOperationBoundary.trustedCompletionOutcome(before: core, event: event) {
                core.mac_pause = outcome
            }
            closeInvalidBoundary()
            return (wasTerminal || [3, 4].contains(event.opcode) ? nil : .failed(.invalidBridge), false)
        }
        core = output.state
        if output.event == 2 {
            let raw = core.evidence
            let proof = YouTubePhonePlaybackEvidence(operationID: request.operationID,
                videoID: request.videoID, requestedPositionSeconds: request.positionSeconds,
                positionSeconds: Double(bitPattern: raw.position), playbackRate: Double(bitPattern: raw.rate),
                observedAtUptime: Double(bitPattern: raw.observed_at), evidenceID: UUID())
            binding = (raw.token, proof)
            nextEvidenceToken = raw.token == UInt64.max ? 0 : raw.token + 1
            return (.confirmed(proof), false)
        }
        if core.presence & 8 == 0 { binding = nil }
        switch output.event {
        case 1: return (.playRequired, false)
        case 3: return (.movedToPhone, false)
        case 4: return (.failed(Self.failure(output.failure)!), false)
        default: return (nil, output.accepted == 1)
        }
    }

    /// Integrity failure is not a second playback reducer. It only revokes this
    /// owner and preserves the last trustworthy Mac outcome for native cleanup.
    private mutating func closeInvalidBoundary() {
        core.phase = 7; core.failure = 8
        core.flags = (core.flags | 8) & ~1
        core.presence &= 8
        core.first_position = 0; core.first_at = 0; core.latest_playing_at = 0
        core.latest_state = 0; core.latest_state_reserved = 0; core.reply_deadline = 0
        if core.mac_pause == 1 { core.mac_pause = 4 }
        nextEvidenceToken = 0
    }

    static func failureCode(_ value: YouTubeHandoffFailure) -> UInt32 {
        switch value {
        case .invalidRequest: 1
        case .timedOut: 2
        case .notVisible: 3
        case .dismissed: 4
        case .replaced: 5
        case .playerUnavailable: 6
        case .wrongVideo: 7
        case .invalidBridge: 8
        case .clockChanged: 9
        case .unsupportedRate: 10
        case .positionChanged: 11
        case .playbackInterrupted: 12
        case .macPauseNotApplied: 13
        case .macPauseUnknown: 14
        }
    }
    static func failure(_ value: UInt32) -> YouTubeHandoffFailure? {
        switch value {
        case 1: .invalidRequest
        case 2: .timedOut
        case 3: .notVisible
        case 4: .dismissed
        case 5: .replaced
        case 6: .playerUnavailable
        case 7: .wrongVideo
        case 8: .invalidBridge
        case 9: .clockChanged
        case 10: .unsupportedRate
        case 11: .positionChanged
        case 12: .playbackInterrupted
        case 13: .macPauseNotApplied
        case 14: .macPauseUnknown
        default: nil
        }
    }

    #if DEBUG
    mutating func acceptCopiedResultForTesting(_ event: Event, output: Output)
        -> (event: YouTubeHandoffPlayerEvent?, accepted: Bool) { accept(event, output: output) }
    var copiedStateForTesting: State { core }
    #endif
}

#if DEBUG
extension YouTubePhonePlaybackEvidence {
    /// Value-copy fixture preserves the private UUID; it never mints a proof or token.
    func copiedForBoundaryTesting(operationID: UUID? = nil, videoID: String? = nil,
        requestedPosition: Double? = nil, position: Double? = nil,
        rate: Double? = nil, observedAt: Double? = nil) -> Self {
        .init(operationID: operationID ?? self.operationID, videoID: videoID ?? self.videoID,
            requestedPositionSeconds: requestedPosition ?? requestedPositionSeconds,
            positionSeconds: position ?? positionSeconds, playbackRate: rate ?? playbackRate,
            observedAtUptime: observedAt ?? observedAtUptime, evidenceID: evidenceID)
    }
}
#endif

// Validates copied native custody, not a second playback-threshold reducer.
enum BelugaRustYouTubeHandoffOperationBoundary {
    typealias Request = beluga_core_youtube_handoff_operation_request_t
    typealias Evidence = beluga_core_youtube_handoff_operation_evidence_t
    typealias State = beluga_core_youtube_handoff_operation_state_t
    typealias Event = beluga_core_youtube_handoff_operation_event_t
    typealias Output = beluga_core_youtube_handoff_operation_result_t

    static func requestWords(_ value: Request) -> [UInt64] {
        [value.position, value.duration, value.rate, value.deadline, value.position_observed_at]
    }
    static func proofWords(_ value: Evidence) -> [UInt64] {
        [value.token, value.position, value.rate, value.observed_at]
    }
    static func stateWords(_ value: State) -> [UInt64] {
        [UInt64(value.abi), UInt64(value.phase), UInt64(value.failure), UInt64(value.mac_pause),
         UInt64(value.flags), UInt64(value.presence), UInt64(value.sequence), UInt64(value.reserved)]
        + requestWords(value.request)
        + [value.last_now, value.first_position, value.first_at, value.latest_playing_at,
           UInt64(UInt32(bitPattern: value.latest_state)), UInt64(value.latest_state_reserved)]
        + proofWords(value.evidence) + [value.reply_deadline]
    }
    private static func number(_ bits: UInt64) -> Double { Double(bitPattern: bits) }
    private static func finite(_ bits: UInt64) -> Bool { number(bits).isFinite }
    private static func boundedPosition(_ bits: UInt64) -> Bool {
        let value = number(bits)
        return value.isFinite && value >= 0 && value <= 31_536_000
    }
    private static func boundedRate(_ bits: UInt64) -> Bool {
        let value = number(bits)
        return value.isFinite && value > 0 && value <= 16
    }
    private static func valid(_ value: Request) -> Bool {
        let position = number(value.position), duration = number(value.duration)
        let observed = number(value.position_observed_at), deadline = number(value.deadline)
        return boundedPosition(value.position) && boundedPosition(value.duration)
            && duration > position && boundedRate(value.rate)
            && observed.isFinite && observed >= 0 && deadline.isFinite && deadline > observed
    }
    static func valid(_ value: State) -> Bool {
        guard value.abi == 1, value.phase <= 7, value.mac_pause <= 4,
              value.flags & ~UInt32(15) == 0, value.presence & ~UInt32(31) == 0,
              value.reserved == 0, value.latest_state_reserved == 0, valid(value.request),
              value.phase == 7 ? (1...14).contains(value.failure) : value.failure == 0 else { return false }
        if value.flags & 1 != 0 && value.flags & 2 == 0 { return false }
        if value.presence & 1 != 0 {
            guard boundedPosition(value.first_position), finite(value.first_at) else { return false }
        } else if value.first_position != 0 || value.first_at != 0 { return false }
        if value.presence & 2 != 0 {
            if !finite(value.latest_playing_at) { return false }
        } else if value.latest_playing_at != 0 { return false }
        if value.presence & 4 != 0 {
            if ![-1, 0, 1, 2, 3, 5].contains(value.latest_state) { return false }
        } else if value.latest_state != 0 { return false }
        if value.presence & 8 != 0 {
            guard value.evidence.token != 0, boundedPosition(value.evidence.position),
                  boundedRate(value.evidence.rate), finite(value.evidence.observed_at) else { return false }
        } else if proofWords(value.evidence) != [0, 0, 0, 0] { return false }
        if value.presence & 16 != 0 {
            if !finite(value.reply_deadline) || value.mac_pause != 1 { return false }
        } else if value.reply_deadline != 0 || value.mac_pause == 1 { return false }
        // Untouched constructors and direct failure retain arbitrary clock bits.
        if value.phase != 0 && value.phase != 7 && !finite(value.last_now) { return false }
        switch value.phase {
        case 4:
            return value.presence & 8 != 0 && value.mac_pause == 0
        case 5:
            return value.mac_pause == 1 && value.presence & 24 == 24
        case 6:
            return value.mac_pause == 2 && value.presence & 25 == 0 && value.flags & 8 != 0
        case 7:
            return value.flags & 9 == 8 && value.mac_pause != 1 && value.presence & ~UInt32(8) == 0
        default:
            return value.mac_pause == 0 && value.presence & 8 == 0
        }
    }

    static func valid(_ event: Event) -> Bool {
        guard event.opcode <= 6, event.flags & ~UInt32(63) == 0,
              event.presence & ~UInt32(15) == 0 else { return false }
        let allowed: UInt32
        switch event.opcode {
        case 0: allowed = 1
        case 2: allowed = 14
        case 3, 4: allowed = 16
        case 5: allowed = 32
        default: allowed = 0
        }
        guard event.flags & ~allowed == 0,
              event.opcode == 2 ? (event.kind <= 4 && event.sequence > 0) : (event.kind == 0 && event.sequence == 0),
              event.opcode == 5 ? (1...3).contains(event.completion) : event.completion == 0,
              event.opcode == 6 ? (1...14).contains(event.failure) : event.failure == 0,
              [3, 4].contains(event.opcode) || event.proof_token == 0,
              event.flags & 16 != 0 ? event.proof_token != 0 : event.proof_token == 0,
              event.opcode == 2 || event.candidate_token == 0 else { return false }
        if event.opcode != 2 || event.kind != 2 {
            return event.presence == 0 && event.sample_state == 0 && event.sample_position == 0
                && event.sample_duration == 0 && event.sample_rate == 0
        }
        guard event.presence & 1 != 0 ? [-1, 0, 1, 2, 3, 5].contains(event.sample_state) : event.sample_state == 0,
              event.presence & 2 != 0 ? boundedPosition(event.sample_position) : event.sample_position == 0,
              event.presence & 4 != 0 ? boundedPosition(event.sample_duration) : event.sample_duration == 0,
              event.presence & 8 != 0 ? boundedRate(event.sample_rate) : event.sample_rate == 0 else { return false }
        return true
    }

    static func accepts(before: State, event: Event, output: Output) -> Bool {
        let after = output.state
        guard valid(before), valid(after), valid(event), output.status == 0,
              output.event <= 4, output.accepted <= 1,
              output.event == 4 ? (1...14).contains(output.failure) : output.failure == 0,
              requestWords(before.request) == requestWords(after.request) else { return false }
        if before.phase == 7 {
            return stateWords(before) == stateWords(after) && output.event == 0 && output.accepted == 0
        }
        if event.opcode == 6 && (after.phase != 7 || after.failure != event.failure || output.event != 4) {
            return false
        }
        // Domain guards that return before observation must preserve every state bit.
        let earlyNoChange = event.opcode == 2 && event.flags & 6 != 6
            || event.opcode == 4 && before.mac_pause != 0
            || event.opcode == 5 && (event.flags & 32 == 0 || before.mac_pause != 1)
        if earlyNoChange {
            return stateWords(before) == stateWords(after) && output.event == 0 && output.accepted == 0
        }

        let clockObserved = event.opcode != 6
        if clockObserved {
            let time = number(event.now), old = number(before.last_now)
            let admittedTime = time.isFinite && time >= old
            if after.last_now != (admittedTime ? event.now : before.last_now) { return false }
            if !admittedTime && (after.phase != 7 || after.failure != 9) { return false }
            if !admittedTime && after.sequence != before.sequence { return false }
        } else if after.last_now != before.last_now { return false }
        if event.opcode == 2 && after.phase != 7 {
            let expected = max(before.sequence, event.sequence)
            if after.sequence != expected { return false }
        } else if event.opcode != 2 && after.sequence != before.sequence { return false }
        if event.opcode == 2 && after.sequence != before.sequence
            && (event.sequence <= before.sequence || after.sequence != event.sequence) { return false }
        if after.phase != 7 {
            let expectedVisibility = event.opcode == 0 ? event.flags & 1 : before.flags & 1
            if after.flags & 1 != expectedVisibility { return false }
        }

        let admittedSample = event.opcode == 2 && event.flags == 14 && event.kind == 2
            && event.presence == 15 && event.sequence > before.sequence
            && before.flags & 5 == 5 && before.phase != 6 && after.phase != 7
        if after.presence & 1 != 0 {
            if before.presence & 1 != 0 {
                if after.first_position != before.first_position || after.first_at != before.first_at { return false }
            } else if !admittedSample || after.first_position != event.sample_position || after.first_at != event.now {
                return false
            }
        }
        if after.presence & 2 != 0
            && (before.presence & 2 == 0 || after.latest_playing_at != before.latest_playing_at)
            && (!admittedSample || after.latest_playing_at != event.now) { return false }
        if after.presence & 4 != 0
            && (before.presence & 4 == 0 || after.latest_state != before.latest_state)
            && (!admittedSample || after.latest_state != event.sample_state) { return false }

        let minted = before.evidence.token == 0 && after.evidence.token != 0
        let cleared = before.evidence.token != 0 && after.evidence.token == 0
        if minted {
            guard output.event == 2, output.accepted == 0, event.opcode == 2,
                  event.flags == 14, event.kind == 2, event.presence == 15,
                  event.sequence > before.sequence, before.flags & 5 == 5,
                  before.presence & 1 != 0,
                  event.sample_state == 1, event.candidate_token != 0,
                  after.evidence.token == event.candidate_token,
                  after.evidence.position == event.sample_position,
                  after.evidence.rate == event.sample_rate,
                  after.evidence.observed_at == event.now,
                  after.phase == 4, after.mac_pause == 0, after.flags & 8 == 0,
                  after.latest_playing_at == event.now, after.latest_state == 1 else { return false }
        } else {
            if output.event == 2 { return false }
            if !cleared && proofWords(after.evidence) != proofWords(before.evidence) { return false }
        }
        if cleared {
            guard output.event == 3, event.opcode == 5, event.flags == 32,
                  event.completion == 1, before.mac_pause == 1,
                  after.mac_pause == 2, after.phase == 6, after.flags & 8 != 0,
                  before.flags & 9 == 1, before.presence & 6 == 6, before.latest_state == 1,
                  fresh(event.now, after: before.latest_playing_at),
                  number(event.now) < number(before.reply_deadline),
                  number(event.now) < number(before.request.deadline) else { return false }
        }
        if before.flags & 8 != 0 && after.flags & 8 == 0 { return false }
        if after.evidence.token != 0 && (after.presence & 6 != 6 || after.latest_state != 1)
            && after.flags & 8 == 0 { return false }
        if event.opcode == 2 && event.flags == 14 && event.kind == 1
            && event.sequence > before.sequence && before.phase != 6 && after.phase != 7 {
            guard after.presence & 7 == 0,
                  before.evidence.token == 0 || after.flags & 8 != 0 else { return false }
        }
        if before.flags & 2 != 0 && after.flags & 2 == 0 { return false }
        if before.flags & 4 != 0 && after.flags & 4 == 0 { return false }
        if after.flags & 2 != before.flags & 2
            && !(event.opcode == 0 && event.flags == 1 && after.flags & 2 != 0) { return false }
        if after.flags & 4 != before.flags & 4
            && !(event.opcode == 2 && event.flags == 14 && event.kind == 0) { return false }

        if event.opcode == 5 && event.flags == 32 && before.mac_pause == 1 {
            // Observation happens before applying a reply; an expired reply is
            // unknown, while an admitted reply retains its actual known outcome.
            let expected = trustedCompletionOutcome(before: before, event: event) ?? 4
            if after.mac_pause != expected { return false }
        }
        switch (before.mac_pause, after.mac_pause) {
        case (0, 1):
            guard event.opcode == 4, output.accepted == 1, output.event == 0,
                  event.flags == 16, event.proof_token == before.evidence.token,
                  after.phase == 5 else { return false }
        case (1, 2), (1, 3):
            guard trustedCompletionOutcome(before: before, event: event) == after.mac_pause else { return false }
        case (1, 4):
            if after.phase != 7 { return false }
        default:
            if before.mac_pause != after.mac_pause { return false }
        }
        if output.accepted == 1 {
            guard [3, 4].contains(event.opcode), output.event == 0, after.phase != 7,
                  event.flags == 16, event.proof_token == before.evidence.token,
                  before.evidence.token != 0, before.flags & 9 == 1,
                  after.flags & 9 == 1, before.presence & 6 == 6, before.latest_state == 1,
                  fresh(event.now, after: before.evidence.observed_at),
                  fresh(event.now, after: before.latest_playing_at),
                  number(event.now) < number(before.request.deadline),
                  after.evidence.token == before.evidence.token else { return false }
            var allowed = before; allowed.last_now = event.now
            if event.opcode == 4 {
                allowed.mac_pause = 1; allowed.phase = 5; allowed.presence |= 16
                allowed.reply_deadline = min(number(before.request.deadline), number(event.now) + 3).bitPattern
            }
            if stateWords(allowed) != stateWords(after) { return false }
        }
        if ![3, 4].contains(event.opcode) && output.accepted != 0 { return false }
        if after.phase == 7 {
            guard output.accepted == 0, !cleared, after.failure != 0,
                  output.event == ([3, 4].contains(event.opcode) ? 0 : 4) else { return false }
            if output.event == 4 && output.failure != after.failure { return false }
            if event.opcode == 6 && after.failure != event.failure { return false }
        } else if output.event == 4 { return false }
        if output.event == 1 && !(event.opcode == 2 && event.flags == 14 && event.kind == 1) { return false }
        if output.event == 3 && !(event.opcode == 5 && event.flags == 32 && event.completion == 1
            && before.mac_pause == 1 && after.mac_pause == 2 && after.phase == 6) { return false }
        if after.phase == 6 && before.phase != 6 && output.event != 3 { return false }
        if before.phase == 6 && after.phase != 6 && after.phase != 7 { return false }
        return true
    }

    // An affirmative foreign result cannot override these native proof-age and
    // continuing-playback prerequisites for crossing the pause boundary.
    private static func fresh(_ now: UInt64, after observed: UInt64) -> Bool {
        let time = number(now), sample = number(observed)
        return time.isFinite && sample.isFinite && time >= sample && time - sample <= 0.75
    }

    static func trustedCompletionOutcome(before: State, event: Event) -> UInt32? {
        guard valid(before), valid(event), event.opcode == 5, event.flags == 32,
              before.mac_pause == 1, before.phase == 5,
              finite(event.now), number(event.now) >= number(before.last_now),
              number(event.now) < number(before.reply_deadline),
              number(event.now) < number(before.request.deadline) else { return nil }
        switch event.completion {
        case 1: return 2
        case 2: return 3
        case 3: return 4
        default: return nil
        }
    }
}
