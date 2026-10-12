import BelugaCore
import Foundation

/// Copied scalar policy only. Native UUID/URL/String semantics remain Swift
/// facts; source one-use ownership, authorization, Apple Events, and final live
/// JavaScript checks remain in their unchanged native callers.
enum BelugaRustMacChromeHandoffSourcePolicy {
    typealias PrepareFacts = beluga_core_handoff_source_prepare_facts_t
    typealias MatchFacts = beluga_core_handoff_source_match_facts_t
    typealias Result = beluga_core_handoff_source_result_t
    typealias PrepareResultMutation = @Sendable (PrepareFacts, Result) -> Result
    typealias MatchResultMutation = @Sendable (MatchFacts, Result) -> Result

    static var layoutIsExact: Bool {
        UInt16(littleEndian: 1) == 1
            && MemoryLayout<PrepareFacts>.size == 56
            && MemoryLayout<PrepareFacts>.stride == 56
            && MemoryLayout<PrepareFacts>.alignment == 8
            && MemoryLayout<PrepareFacts>.offset(of: \PrepareFacts.abi_version) == 0
            && MemoryLayout<PrepareFacts>.offset(of: \PrepareFacts.reserved) == 4
            && MemoryLayout<PrepareFacts>.offset(of: \PrepareFacts.flags) == 8
            && MemoryLayout<PrepareFacts>.offset(of: \PrepareFacts.position) == 16
            && MemoryLayout<PrepareFacts>.offset(of: \PrepareFacts.duration) == 24
            && MemoryLayout<PrepareFacts>.offset(of: \PrepareFacts.rate) == 32
            && MemoryLayout<PrepareFacts>.offset(of: \PrepareFacts.observed_at_page_ms) == 40
            && MemoryLayout<PrepareFacts>.offset(of: \PrepareFacts.phone_position) == 48
            && MemoryLayout<MatchFacts>.size == 88
            && MemoryLayout<MatchFacts>.stride == 88
            && MemoryLayout<MatchFacts>.alignment == 8
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.abi_version) == 0
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.reserved) == 4
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.flags) == 8
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.anchor_position) == 16
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.anchor_duration) == 24
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.anchor_rate) == 32
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.anchor_observed_at_page_ms) == 40
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.phone_position) == 48
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.current_position) == 56
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.current_duration) == 64
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.current_rate) == 72
            && MemoryLayout<MatchFacts>.offset(of: \MatchFacts.current_observed_at_page_ms) == 80
            && MemoryLayout<Result>.size == 16
            && MemoryLayout<Result>.stride == 16
            && MemoryLayout<Result>.alignment == 4
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.allowed) == 8
            && MemoryLayout<Result>.offset(of: \Result.reserved) == 12
    }

    private static func flags(_ facts: [Bool]) -> UInt64 {
        facts.enumerated().reduce(UInt64(0)) { mask, fact in
            fact.element ? mask | (UInt64(1) << fact.offset) : mask
        }
    }

    static func prepareFacts(source: MacChromePlayerSnapshot,
                             phonePositionSeconds: Double) -> PrepareFacts {
        let media = source.media
        let continuityValid = media.playbackContinuityID.map {
            $0.count == 36 && UUID(uuidString: $0) != nil
        } ?? false
        let videoValid = MacChromeAppleEventsBackend.videoID(
            from: "https://www.youtube.com/watch?v=" + media.videoID) == media.videoID
        var input = PrepareFacts()
        input.abi_version = 1; input.reserved = 0
        input.flags = flags([continuityValid, videoValid, media.canSeek == true,
                             !media.paused, media.canPause,
                             media.duration != nil, media.elapsedTime != nil])
        input.position = (media.elapsedTime ?? 0).bitPattern
        input.duration = (media.duration ?? 0).bitPattern
        input.rate = media.playbackRate.bitPattern
        input.observed_at_page_ms = media.observedAtPageMilliseconds.bitPattern
        input.phone_position = phonePositionSeconds.bitPattern
        return input
    }

    static func matchFacts(anchor: MacChromeHandoffPauseCondition,
                           current media: MacChromeScriptSnapshot) -> MatchFacts {
        var input = MatchFacts()
        input.abi_version = 1; input.reserved = 0
        input.flags = flags([media.playbackContinuityID == anchor.continuityID,
                             media.videoID == anchor.videoID, !media.paused,
                             media.canPause, media.canSeek == true,
                             media.duration != nil, media.elapsedTime != nil])
        input.anchor_position = anchor.positionSeconds.bitPattern
        input.anchor_duration = anchor.durationSeconds.bitPattern
        input.anchor_rate = anchor.playbackRate.bitPattern
        input.anchor_observed_at_page_ms = anchor.observedAtPageMilliseconds.bitPattern
        input.phone_position = anchor.phonePositionSeconds.bitPattern
        input.current_position = (media.elapsedTime ?? 0).bitPattern
        input.current_duration = (media.duration ?? 0).bitPattern
        input.current_rate = media.playbackRate.bitPattern
        input.current_observed_at_page_ms = media.observedAtPageMilliseconds.bitPattern
        return input
    }

    static func prepare(source: MacChromePlayerSnapshot,
                        phonePositionSeconds: Double) -> Bool? {
        evaluatePrepare(prepareFacts(source: source, phonePositionSeconds: phonePositionSeconds))
    }

    static func matches(anchor: MacChromeHandoffPauseCondition,
                        current media: MacChromeScriptSnapshot) -> Bool? {
        evaluateMatches(matchFacts(anchor: anchor, current: media))
    }

    // Mutation seams may alter only a result AFTER the actual Rust export.
    // Authoritative copied-input Rust validators cannot be injected/replaced.
    static func evaluatePrepare(_ input: PrepareFacts,
                                resultMutation: PrepareResultMutation? = nil) -> Bool? {
        guard layoutIsExact else { return nil }
        let actual = beluga_core_handoff_source_prepare(input)
        let result = resultMutation?(input, actual) ?? actual
        guard beluga_core_handoff_source_prepare_result_is_valid(input, result) == 1 else { return nil }
        return result.allowed == 1
    }

    static func evaluateMatches(_ input: MatchFacts,
                                resultMutation: MatchResultMutation? = nil) -> Bool? {
        guard layoutIsExact else { return nil }
        let actual = beluga_core_handoff_source_matches(input)
        let result = resultMutation?(input, actual) ?? actual
        guard beluga_core_handoff_source_matches_result_is_valid(input, result) == 1 else { return nil }
        return result.allowed == 1
    }
}
