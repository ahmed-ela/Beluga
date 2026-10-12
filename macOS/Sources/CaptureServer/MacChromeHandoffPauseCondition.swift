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
        guard BelugaRustMacChromeHandoffSourcePolicy.prepare(
            source: source, phonePositionSeconds: phonePositionSeconds) == true,
              let continuity = media.playbackContinuityID,
              let duration = media.duration, let position = media.elapsedTime else { return nil }
        // Retain native strings and admitted Double bits, not foreign output payloads.
        continuityID = continuity; videoID = media.videoID
        positionSeconds = position; durationSeconds = duration; playbackRate = media.playbackRate
        observedAtPageMilliseconds = media.observedAtPageMilliseconds
        self.phonePositionSeconds = phonePositionSeconds
    }

    func matches(_ media: MacChromeScriptSnapshot) -> Bool {
        BelugaRustMacChromeHandoffSourcePolicy.matches(anchor: self, current: media) == true
    }
}
