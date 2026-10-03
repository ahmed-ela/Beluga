import Foundation
import CoreFoundation

struct YouTubeHandoffRequest: Equatable, Sendable, Identifiable {
    let operationID: UUID
    let videoID: String
    let positionSeconds: Double
    let durationSeconds: Double
    let playbackRate: Double
    let deadlineUptime: Double
    var id: UUID { operationID }

    init(operationID: UUID, videoID: String, positionSeconds: Double,
         durationSeconds: Double, playbackRate: Double, deadlineUptime: Double,
         now: Double) throws {
        guard Self.validVideoID(videoID), now.isFinite, now >= 0,
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
}

enum YouTubeHandoffPhase: Equatable, Sendable {
    case preparing, ready, playRequired, verifying, confirmed
    case failed(YouTubeHandoffFailure)
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

struct YouTubeHandoffOperation {
    let request: YouTubeHandoffRequest
    let pageID: UUID
    private(set) var phase: YouTubeHandoffPhase = .preparing
    private(set) var isVisible = false
    private(set) var evidence: YouTubePhonePlaybackEvidence?
    private var hasBeenVisible = false
    private var isReady = false
    private var lastNow: Double
    private var sequence: UInt32 = 0
    private var firstPlaying: (position: Double, now: Double)?
    private var latestPlayingAt: Double?
    private var latestState: Int?
    private var evidenceRevoked = false

    init(request: YouTubeHandoffRequest, pageID: UUID = UUID(), now: Double) {
        self.request = request; self.pageID = pageID; lastNow = now
    }

    var isTerminal: Bool {
        if case .failed = phase { return true }
        return false
    }

    mutating func visibilityChanged(_ visible: Bool, now: Double) -> YouTubeHandoffPlayerEvent? {
        guard let failure = observeTime(now) else {
            guard !isTerminal else { return nil }
            isVisible = visible
            if visible { hasBeenVisible = true; return nil }
            firstPlaying = nil; latestPlayingAt = nil
            return hasBeenVisible ? fail(.notVisible) : nil
        }
        return fail(failure)
    }

    mutating func poll(now: Double) -> YouTubeHandoffPlayerEvent? {
        observeTime(now).flatMap { fail($0) }
    }

    mutating func receive(_ message: YouTubeHandoffBridgeMessage,
                          now: Double) -> YouTubeHandoffPlayerEvent? {
        guard message.operationID == request.operationID, message.pageID == pageID else { return nil }
        if let failure = observeTime(now) { return fail(failure) }
        guard !isTerminal, message.sequence > sequence else { return nil }
        sequence = message.sequence
        guard message.videoID == request.videoID else { return fail(.wrongVideo) }
        switch message.kind {
        case .error: return fail(.playerUnavailable)
        case .unsupportedRate: return fail(.unsupportedRate)
        case .ready:
            isReady = true
            if evidence == nil { phase = .ready }
        case .blocked:
            firstPlaying = nil; latestPlayingAt = nil; latestState = nil
            if evidence != nil { evidenceRevoked = true }
            if evidence == nil { phase = .playRequired }
            return .playRequired
        case .sample:
            guard isVisible, isReady, let state = message.state,
                  let position = message.position, let duration = message.duration,
                  let rate = message.rate else { return nil }
            latestState = state
            guard state == 1,
                  abs(duration - request.durationSeconds) <= max(1, request.durationSeconds * 0.002),
                  abs(rate - request.playbackRate) <= 0.01,
                  position <= duration else {
                firstPlaying = nil; latestPlayingAt = nil
                // Recovery cannot turn an earlier confirmation back into Pause authority.
                // A fresh handoff must produce its own new playback observation.
                if evidence != nil { evidenceRevoked = true }
                if evidence == nil { phase = .ready }
                return nil
            }
            if let proof = evidence,
               abs(position - (proof.positionSeconds + (now - proof.observedAtUptime) * rate)) > 2 {
                return fail(.positionChanged)
            }
            latestPlayingAt = now
            guard evidence == nil else { return nil }
            guard let first = firstPlaying else {
                if abs(position - request.positionSeconds) <= 2 {
                    firstPlaying = (position, now); phase = .verifying
                }
                return nil
            }
            let elapsed = now - first.now
            let advance = position - first.position
            guard elapsed <= 1.5,
                  abs(position - (request.positionSeconds + elapsed * rate)) <= 2 else {
                firstPlaying = nil; phase = .ready
                return nil
            }
            guard elapsed >= 0.2, advance > 0.02,
                  abs(advance - elapsed * rate) <= max(0.15, elapsed * rate * 0.5) else { return nil }
            let proof = YouTubePhonePlaybackEvidence(
                operationID: request.operationID, videoID: request.videoID,
                requestedPositionSeconds: request.positionSeconds, positionSeconds: position,
                playbackRate: rate, observedAtUptime: now, evidenceID: UUID()
            )
            evidence = proof; phase = .confirmed
            return .confirmed(proof)
        }
        return nil
    }

    /// Recheck before the caller consumes its separate one-shot transport offer. This local
    /// observation is revocable, not itself an offer-consumption or Mac-pause authority.
    mutating func isCurrent(_ proof: YouTubePhonePlaybackEvidence, now: Double) -> Bool {
        if let failure = observeTime(now) { _ = fail(failure) }
        guard !isTerminal, isVisible, !evidenceRevoked, evidence == proof, now < request.deadlineUptime,
              now >= proof.observedAtUptime, now - proof.observedAtUptime <= 0.75,
              latestState == 1, let last = latestPlayingAt,
              now >= last, now - last <= 0.75 else { return false }
        return true
    }

    mutating func fail(_ failure: YouTubeHandoffFailure) -> YouTubeHandoffPlayerEvent? {
        guard !isTerminal else { return nil }
        phase = .failed(failure); isVisible = false
        firstPlaying = nil; latestPlayingAt = nil; latestState = nil
        return .failed(failure)
    }

    private mutating func observeTime(_ now: Double) -> YouTubeHandoffFailure? {
        guard !isTerminal else { return nil }
        guard now.isFinite, now >= lastNow else { return .clockChanged }
        lastNow = now
        return evidence == nil && now >= request.deadlineUptime ? .timedOut : nil
    }
}
