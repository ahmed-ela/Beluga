import Foundation

/// Native renderer precondition, not a network authorization or an offer lease. Only the exact
/// source transaction may supply it; the browser rechecks it adjacent to its native pause call.
struct MacChromeHandoffPauseCondition: Encodable, Equatable, Sendable {
    let continuityID: String
    let videoID: String
    let positionSeconds: Double
    let durationSeconds: Double
    let playbackRate: Double
    let observedAtPageMilliseconds: Double
    let phonePositionSeconds: Double

    init?(source: MacChromePlayerSnapshot, phonePositionSeconds: Double) {
        let media = source.media
        guard let continuity = media.playbackContinuityID, continuity.count == 36,
              UUID(uuidString: continuity) != nil, media.canSeek == true,
              !media.paused, media.canPause, media.playbackRate.isFinite,
              media.playbackRate > 0, media.playbackRate <= 16,
              let duration = media.duration, duration.isFinite, duration > 0, duration <= 31_536_000,
              let position = media.elapsedTime, position.isFinite, position >= 0, position < duration,
              phonePositionSeconds.isFinite, phonePositionSeconds >= 0, phonePositionSeconds < duration,
              media.observedAtPageMilliseconds.isFinite, media.observedAtPageMilliseconds >= 0,
              media.observedAtPageMilliseconds <= 9_007_199_254_740_991,
              MacChromeAppleEventsBackend.videoID(from: "https://www.youtube.com/watch?v=" + media.videoID) == media.videoID
        else { return nil }
        continuityID = continuity; videoID = media.videoID
        positionSeconds = position; durationSeconds = duration; playbackRate = media.playbackRate
        observedAtPageMilliseconds = media.observedAtPageMilliseconds
        self.phonePositionSeconds = phonePositionSeconds
    }

    func matches(_ media: MacChromeScriptSnapshot) -> Bool {
        let elapsed = (media.observedAtPageMilliseconds - observedAtPageMilliseconds) / 1000
        guard elapsed.isFinite, elapsed >= 0, elapsed < 30,
              media.playbackContinuityID == continuityID, media.videoID == videoID,
              !media.paused, media.canPause, media.canSeek == true,
              media.duration == durationSeconds, media.playbackRate == playbackRate,
              let position = media.elapsedTime, position.isFinite else { return false }
        return abs(position - (positionSeconds + elapsed * playbackRate)) <= 1
            && abs(position - phonePositionSeconds) <= 2
    }
}
