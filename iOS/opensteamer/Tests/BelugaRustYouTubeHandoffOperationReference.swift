import Foundation
import WebRTCTransport
@testable import opensteamer

// Independent reference frozen from the original Swift reducer at
// c81566c; original file SHA256 26f5f3473c070cd987509fdf14358aa20983d072208d3e5e33a287bc13e33bdf.
// Native request/codec admission remains outside the migrated seam. The policy,
// equality, arithmetic and order below do not call the Rust core or new adapter.
struct FrozenYouTubePlaybackEvidence: Equatable {
    let operationID: UUID
    let videoID: String
    let requestedPositionSeconds: Double
    let positionSeconds: Double
    let playbackRate: Double
    let observedAtUptime: Double
    private let evidenceID: UUID

    init(operationID: UUID, videoID: String, requestedPositionSeconds: Double,
         positionSeconds: Double, playbackRate: Double, observedAtUptime: Double) {
        self.operationID = operationID; self.videoID = videoID
        self.requestedPositionSeconds = requestedPositionSeconds
        self.positionSeconds = positionSeconds; self.playbackRate = playbackRate
        self.observedAtUptime = observedAtUptime; evidenceID = UUID()
    }
    private init(operationID: UUID, videoID: String, requestedPositionSeconds: Double,
                 positionSeconds: Double, playbackRate: Double, observedAtUptime: Double,
                 evidenceID: UUID) {
        self.operationID = operationID; self.videoID = videoID
        self.requestedPositionSeconds = requestedPositionSeconds
        self.positionSeconds = positionSeconds; self.playbackRate = playbackRate
        self.observedAtUptime = observedAtUptime; self.evidenceID = evidenceID
    }
    func copied(operationID: UUID? = nil, videoID: String? = nil,
                requestedPosition: Double? = nil, position: Double? = nil,
                rate: Double? = nil, observedAt: Double? = nil) -> Self {
        .init(operationID: operationID ?? self.operationID, videoID: videoID ?? self.videoID,
            requestedPositionSeconds: requestedPosition ?? requestedPositionSeconds,
            positionSeconds: position ?? positionSeconds, playbackRate: rate ?? playbackRate,
            observedAtUptime: observedAt ?? observedAtUptime, evidenceID: evidenceID)
    }
}

enum FrozenYouTubePlayerEvent: Equatable {
    case playRequired, confirmed(FrozenYouTubePlaybackEvidence), movedToPhone
    case failed(YouTubeHandoffFailure)
}

struct FrozenYouTubeHandoffOperation {
    let request: YouTubeHandoffRequest
    let pageID: UUID
    private(set) var phase: YouTubeHandoffPhase = .preparing
    private(set) var isVisible = false
    private(set) var evidence: FrozenYouTubePlaybackEvidence?
    private(set) var macPauseStatus: YouTubeHandoffMacPauseStatus = .notRequested
    private(set) var hasBeenVisible = false
    private(set) var isReady = false
    private(set) var lastNow: Double
    private(set) var sequence: UInt32 = 0
    private(set) var firstPlaying: (position: Double, now: Double)?
    private(set) var latestPlayingAt: Double?
    private(set) var latestState: Int?
    private(set) var evidenceRevoked = false
    private(set) var replyDeadlineUptime: Double?

    init(request: YouTubeHandoffRequest, pageID: UUID, now: Double) {
        self.request = request; self.pageID = pageID; lastNow = now
    }
    var isTerminal: Bool {
        if case .failed = phase { return true }
        return false
    }
    mutating func visibilityChanged(_ visible: Bool, now: Double) -> FrozenYouTubePlayerEvent? {
        guard let failure = observeTime(now) else {
            guard !isTerminal else { return nil }
            isVisible = visible
            if visible { hasBeenVisible = true; return nil }
            firstPlaying = nil; latestPlayingAt = nil
            return hasBeenVisible ? fail(.notVisible) : nil
        }
        return fail(failure)
    }
    mutating func poll(now: Double) -> FrozenYouTubePlayerEvent? {
        observeTime(now).flatMap { fail($0) }
    }
    mutating func receive(_ message: YouTubeHandoffBridgeMessage,
                          now: Double) -> FrozenYouTubePlayerEvent? {
        guard message.operationID == request.operationID, message.pageID == pageID else { return nil }
        if let failure = observeTime(now) { return fail(failure) }
        guard !isTerminal, message.sequence > sequence else { return nil }
        sequence = message.sequence
        guard message.videoID == request.videoID else { return fail(.wrongVideo) }
        if phase == .localPlayback {
            switch message.kind {
            case .error: return fail(.playerUnavailable)
            case .unsupportedRate: return fail(.unsupportedRate)
            case .blocked: return .playRequired
            case .ready, .sample: return nil
            }
        }
        switch message.kind {
        case .error: return fail(.playerUnavailable)
        case .unsupportedRate: return fail(.unsupportedRate)
        case .ready:
            isReady = true
            if evidence == nil { phase = .ready }
        case .blocked:
            firstPlaying = nil; latestPlayingAt = nil; latestState = nil
            if evidence != nil { evidenceRevoked = true }
            if macPauseStatus == .pending { return fail(.playbackInterrupted) }
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
                if evidence != nil { evidenceRevoked = true }
                if macPauseStatus == .pending { return fail(.playbackInterrupted) }
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
                if abs(position - request.expectedPosition(at: now)) <= 2 {
                    firstPlaying = (position, now); phase = .verifying
                }
                return nil
            }
            let elapsed = now - first.now
            let advance = position - first.position
            guard elapsed <= 1.5,
                  abs(position - request.expectedPosition(at: now)) <= 2 else {
                firstPlaying = nil; phase = .ready
                return nil
            }
            guard elapsed >= 0.2, advance > 0.02,
                  abs(advance - elapsed * rate) <= max(0.15, elapsed * rate * 0.5) else { return nil }
            let proof = FrozenYouTubePlaybackEvidence(operationID: request.operationID,
                videoID: request.videoID, requestedPositionSeconds: request.positionSeconds,
                positionSeconds: position, playbackRate: rate, observedAtUptime: now)
            evidence = proof; phase = .confirmed
            return .confirmed(proof)
        }
        return nil
    }
    mutating func isCurrent(_ proof: FrozenYouTubePlaybackEvidence, now: Double) -> Bool {
        if let failure = observeTime(now) { _ = fail(failure) }
        guard !isTerminal, macPauseStatus == .notRequested || macPauseStatus == .pending,
              isVisible, !evidenceRevoked, evidence == proof, now < request.deadlineUptime,
              now >= proof.observedAtUptime, now - proof.observedAtUptime <= 0.75,
              latestState == 1, let last = latestPlayingAt,
              now >= last, now - last <= 0.75 else { return false }
        return true
    }
    mutating func beginMacPause(using proof: FrozenYouTubePlaybackEvidence, now: Double) -> Bool {
        guard macPauseStatus == .notRequested, isCurrent(proof, now: now) else { return false }
        macPauseStatus = .pending
        replyDeadlineUptime = min(request.deadlineUptime, now + 3)
        phase = .awaitingMacPause
        return true
    }
    mutating func completeMacPause(operationID: UUID, result: WebRTCMediaHandoffResult,
                                   now: Double) -> FrozenYouTubePlayerEvent? {
        guard operationID == request.operationID, macPauseStatus == .pending else { return nil }
        if let failure = observeTime(now) { return fail(failure) }
        replyDeadlineUptime = nil
        switch result {
        case .macPaused:
            macPauseStatus = .paused
            guard isVisible, !evidenceRevoked, latestState == 1,
                  let last = latestPlayingAt, now >= last, now - last <= 0.75 else {
                return fail(.playbackInterrupted)
            }
            evidenceRevoked = true; evidence = nil; firstPlaying = nil
            phase = .localPlayback
            return .movedToPhone
        case .notApplied:
            macPauseStatus = .notApplied
            return fail(.macPauseNotApplied)
        case .outcomeUnknown:
            macPauseStatus = .unknown
            return fail(.macPauseUnknown)
        }
    }
    mutating func fail(_ failure: YouTubeHandoffFailure) -> FrozenYouTubePlayerEvent? {
        guard !isTerminal else { return nil }
        if macPauseStatus == .pending { macPauseStatus = .unknown }
        replyDeadlineUptime = nil; evidenceRevoked = true
        phase = .failed(failure); isVisible = false
        firstPlaying = nil; latestPlayingAt = nil; latestState = nil
        return .failed(failure)
    }
    private mutating func observeTime(_ now: Double) -> YouTubeHandoffFailure? {
        guard !isTerminal else { return nil }
        guard now.isFinite, now >= lastNow else { return .clockChanged }
        lastNow = now
        if let replyDeadlineUptime, now >= replyDeadlineUptime { return .macPauseUnknown }
        return phase != .localPlayback && now >= request.deadlineUptime ? .timedOut : nil
    }
}
