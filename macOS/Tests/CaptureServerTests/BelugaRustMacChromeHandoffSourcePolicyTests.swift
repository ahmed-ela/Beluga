// Independent original Swift parity against the production Rust bridge.
import BelugaCore
import Foundation
import XCTest
#if !BELUGA_HANDOFF_PURE_STUB_FIXTURE
@testable import CaptureServer
#endif

// Frozen independent original 43-line reducer below. Only its type identifier
// is renamed for test coexistence; all original fields/guards/formulas remain.
// Canonical preimage SHA256: 5cb21bdd689af1c86375eebca95ce0b741c30fc6687d142efdc2270bc2fee8d6.
// Test reference only, never a production fallback.
// BEGIN ORIGINAL 43-LINE REDUCER
import Foundation

/// Native renderer precondition, not a network authorization or an offer lease. Only the exact
/// source transaction may supply it; the browser rechecks it adjacent to its native pause call.
struct FrozenOriginalMacChromeHandoffPauseCondition: Encodable, Equatable, Sendable {
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
// END ORIGINAL REDUCER

final class BelugaRustMacChromeHandoffSourcePolicyTests: XCTestCase {
    private typealias Bridge = BelugaRustMacChromeHandoffSourcePolicy
    private let continuity = "12345678-abcd-1234-abcd-123456789abc"

    private var corpus: [Double] {
        [.nan, Double(bitPattern: 0x7ff8_0000_0000_0037),
         Double(bitPattern: 0xfff8_0000_0000_0037), .infinity, -.infinity,
         -.greatestFiniteMagnitude, -1, -.leastNormalMagnitude,
         -.leastNonzeroMagnitude, -0.0, 0.0, .leastNonzeroMagnitude,
         .leastNormalMagnitude, 1, 2, 10, 15, (16.0).nextDown, 16,
         (16.0).nextUp, 29, 30, 100, 31_536_000, (31_536_000.0).nextUp,
         9_007_199_254_740_991, 9_007_199_254_740_992, .greatestFiniteMagnitude]
    }

    private func media(continuity: String? = "12345678-abcd-1234-abcd-123456789abc",
                       video: String = "abcdefghijk", position: Double? = 10,
                       duration: Double? = 100, rate: Double = 1, page: Double = 0,
                       paused: Bool = false, canPause: Bool = true,
                       canSeek: Bool? = true) -> MacChromeScriptSnapshot {
        .init(documentID: "synthetic-document", itemID: "synthetic-item", itemGeneration: 1,
              videoID: video, title: "Source-only fixture", artist: nil,
              duration: duration, elapsedTime: position, playbackRate: rate, paused: paused,
              observedAtUnixMilliseconds: 0, observedAtPageMilliseconds: page,
              canPlay: true, canPause: canPause, canNext: false, canPrevious: false,
              canSeek: canSeek, playbackContinuityID: continuity)
    }

    private func player(_ media: MacChromeScriptSnapshot) -> MacChromePlayerSnapshot {
        .init(tab: .init(owner: .init(processID: 123, launchDate: Date(timeIntervalSince1970: 0)),
                        windowID: "synthetic-window", tabID: "synthetic-tab"),
              media: media, receivedAtUptime: 0)
    }

    private func assertPrepareParity(_ media: MacChromeScriptSnapshot, phone: Double = 10,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let source = player(media)
        let original = FrozenOriginalMacChromeHandoffPauseCondition(source: source, phonePositionSeconds: phone)
        let proposal = MacChromeHandoffPauseCondition(source: source, phonePositionSeconds: phone)
        XCTAssertEqual(proposal != nil, original != nil, file: file, line: line)
        XCTAssertEqual(Bridge.prepare(source: source, phonePositionSeconds: phone), original != nil,
                       file: file, line: line)
        let facts = Bridge.prepareFacts(source: source, phonePositionSeconds: phone)
        XCTAssertEqual(facts.position, (media.elapsedTime ?? 0).bitPattern, file: file, line: line)
        XCTAssertEqual(facts.duration, (media.duration ?? 0).bitPattern, file: file, line: line)
        XCTAssertEqual(facts.rate, media.playbackRate.bitPattern, file: file, line: line)
        XCTAssertEqual(facts.observed_at_page_ms, media.observedAtPageMilliseconds.bitPattern, file: file, line: line)
        XCTAssertEqual(facts.phone_position, phone.bitPattern, file: file, line: line)
        guard let original, let proposal else { return }
        XCTAssertEqual(proposal.continuityID, original.continuityID, file: file, line: line)
        XCTAssertEqual(proposal.videoID, original.videoID, file: file, line: line)
        XCTAssertEqual(proposal.positionSeconds.bitPattern, original.positionSeconds.bitPattern, file: file, line: line)
        XCTAssertEqual(proposal.durationSeconds.bitPattern, original.durationSeconds.bitPattern, file: file, line: line)
        XCTAssertEqual(proposal.playbackRate.bitPattern, original.playbackRate.bitPattern, file: file, line: line)
        XCTAssertEqual(proposal.observedAtPageMilliseconds.bitPattern, original.observedAtPageMilliseconds.bitPattern,
                       file: file, line: line)
        XCTAssertEqual(proposal.phonePositionSeconds.bitPattern, original.phonePositionSeconds.bitPattern,
                       file: file, line: line)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(proposal), try encoder.encode(original), file: file, line: line)
    }

    private func assertMatchParity(anchor media: MacChromeScriptSnapshot, phone: Double,
                                   current: MacChromeScriptSnapshot,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let source = player(media)
        let original = try XCTUnwrap(FrozenOriginalMacChromeHandoffPauseCondition(
            source: source, phonePositionSeconds: phone), file: file, line: line)
        let proposal = try XCTUnwrap(MacChromeHandoffPauseCondition(
            source: source, phonePositionSeconds: phone), file: file, line: line)
        XCTAssertEqual(proposal.matches(current), original.matches(current), file: file, line: line)
        let raw = Bridge.matchFacts(anchor: proposal, current: current)
        XCTAssertEqual(Bridge.evaluateMatches(raw), original.matches(current), file: file, line: line)
        XCTAssertEqual(raw.anchor_position, original.positionSeconds.bitPattern, file: file, line: line)
        XCTAssertEqual(raw.anchor_duration, original.durationSeconds.bitPattern, file: file, line: line)
        XCTAssertEqual(raw.anchor_rate, original.playbackRate.bitPattern, file: file, line: line)
        XCTAssertEqual(raw.anchor_observed_at_page_ms, original.observedAtPageMilliseconds.bitPattern,
                       file: file, line: line)
        XCTAssertEqual(raw.phone_position, phone.bitPattern, file: file, line: line)
        XCTAssertEqual(raw.current_position, (current.elapsedTime ?? 0).bitPattern, file: file, line: line)
        XCTAssertEqual(raw.current_duration, (current.duration ?? 0).bitPattern, file: file, line: line)
        XCTAssertEqual(raw.current_rate, current.playbackRate.bitPattern, file: file, line: line)
        XCTAssertEqual(raw.current_observed_at_page_ms, current.observedAtPageMilliseconds.bitPattern,
                       file: file, line: line)
    }

    func testImportedLayoutsAndEveryNumericPrepareAxisAgainstFrozenNativeReducer() throws {
        XCTAssertTrue(Bridge.layoutIsExact)
        for axis in 0..<5 {
            for value in corpus {
                var values: [Double] = [10, 100, 1, 0, 10]; values[axis] = value
                try assertPrepareParity(media(position: values[0], duration: values[1],
                    rate: values[2], page: values[3]), phone: values[4])
            }
        }
        try assertPrepareParity(media(position: -0.0, duration: 31_536_000,
            rate: 16, page: 9_007_199_254_740_991), phone: -0.0)
        for duration in [(1.0).nextDown, 1.0, (1.0).nextUp, (31_536_000.0).nextDown,
                         31_536_000.0, (31_536_000.0).nextUp] {
            for position in [duration.nextDown, duration, duration.nextUp] {
                try assertPrepareParity(media(position: position, duration: duration), phone: position)
            }
        }
    }

    func testOptionalPresenceAndNativeCapabilityAdmissionRemainExact() throws {
        for source in [media(position: nil), media(duration: nil),
                       media(position: nil, duration: nil), media(paused: true),
                       media(canPause: false), media(canSeek: false), media(canSeek: nil)] {
            try assertPrepareParity(source)
        }
        let continuities: [String?] = [nil, "", "bad", self.continuity.uppercased(),
            "12345678abcd1234abcd123456789abc", "{" + self.continuity + "}",
            "12345678-abcd-1234-abcd-123456789abz",
            "12345678-abcd-1234-abcd-123456789abé"]
        for continuity in continuities {
            try assertPrepareParity(media(continuity: continuity))
        }
        for video in ["abcdefghijk", "ABC_def-012", "", "short", "abcdefghijkl",
                      "%61bcdefghijk", "abcdefghijk&v=lmnopqrstuv", "abcdefghijk#fragment",
                      "abcdefghijé", String(repeating: "a", count: 8_193)] {
            try assertPrepareParity(media(video: video))
        }
        let missing = Bridge.prepareFacts(source: player(media(position: nil, duration: nil)),
                                          phonePositionSeconds: -0.0)
        XCTAssertEqual(missing.flags, 31); XCTAssertEqual(missing.position, 0)
        XCTAssertEqual(missing.duration, 0); XCTAssertEqual(missing.phone_position, (-0.0).bitPattern)
    }

    func testEveryCurrentNumericMatchAxisAndNilAgainstFrozenNativeReducer() throws {
        for axis in 0..<4 {
            for value in corpus {
                var values: [Double] = [10, 100, 1, 0]; values[axis] = value
                try assertMatchParity(anchor: media(), phone: 10,
                    current: media(position: values[0], duration: values[1], rate: values[2], page: values[3]))
            }
        }
        try assertMatchParity(anchor: media(), phone: 10, current: media(position: nil))
        try assertMatchParity(anchor: media(), phone: 10, current: media(duration: nil))
        try assertMatchParity(anchor: media(), phone: 10, current: media(position: nil, duration: nil))
    }

    func testNativeMatchStringFactsAreExactNotUUIDNormalizationOrHashAuthority() throws {
        for current in [media(continuity: nil), media(continuity: continuity.uppercased()),
                        media(continuity: "22345678-abcd-1234-abcd-123456789abc"),
                        media(video: "lmnopqrstuv"), media(paused: true), media(canPause: false),
                        media(canSeek: false), media(canSeek: nil)] {
            try assertMatchParity(anchor: media(), phone: 10, current: current)
        }
        let uppercaseAnchor = media(continuity: continuity.uppercased())
        try assertMatchParity(anchor: uppercaseAnchor, phone: 10,
                              current: media(continuity: continuity.uppercased()))
        try assertMatchParity(anchor: uppercaseAnchor, phone: 10, current: media())
    }

    func testMatchToleranceBoundariesAndNoConstructorRevalidation() throws {
        for elapsedMs in [-Double.leastNonzeroMagnitude, -0.0, 0,
                          29_999.999999, (30_000.0).nextDown, 30_000, (30_000.0).nextUp] {
            let predicted = 10 + elapsedMs / 1000
            try assertMatchParity(anchor: media(), phone: predicted,
                                  current: media(position: predicted, page: elapsedMs))
        }
        for offset in [(-1.0).nextDown, -1, (-1.0).nextUp, 0,
                       (1.0).nextDown, 1, (1.0).nextUp] {
            try assertMatchParity(anchor: media(position: 0), phone: 0,
                                  current: media(position: offset))
        }
        for position in [(12.0).nextDown, 12, (12.0).nextUp] {
            try assertMatchParity(anchor: media(), phone: 10,
                                  current: media(position: position, page: 2_000))
        }
        for phone in [(12.0).nextDown, 12, (12.0).nextUp] {
            // Other phone-distance edge: current stays at10, exactly on the
            // Mac prediction, while phone is the value2 seconds ahead.
            try assertMatchParity(anchor: media(), phone: phone, current: media())
        }
        // The original matches predicate does not require current >=0 or <duration.
        // These are actual admitted native anchors, not fabricated production objects.
        for (anchor, phone, current) in [
            (media(position: 0), 0.0, media(position: -1)),
            (media(position: 99), 99.0, media(position: 100)),
            (media(position: 99), 99.0, media(position: (100.0).nextUp, page: 1_000)),
            (media(position: -0.0, page: -0.0), -0.0, media(position: -0.0, page: -0.0)),
            (media(page: 9_007_199_254_740_991), 10.0,
             media(position: 10.001, page: 9_007_199_254_740_992))] {
            try assertMatchParity(anchor: anchor, phone: phone, current: current)
        }
    }

    func testAdmittedAnchorNumericAxesRemainUnrewrittenAtMatchesBoundary() throws {
        for axis in 0..<5 {
            for value in corpus {
                var values: [Double] = [10, 100, 1, 0, 10]; values[axis] = value
                let anchor = media(position: values[0], duration: values[1], rate: values[2], page: values[3])
                guard FrozenOriginalMacChromeHandoffPauseCondition(
                    source: player(anchor), phonePositionSeconds: values[4]) != nil else { continue }
                try assertMatchParity(anchor: anchor, phone: values[4], current: anchor)
                try assertMatchParity(anchor: anchor, phone: values[4],
                    current: media(position: values[0] + values[2], duration: values[1],
                                   rate: values[2], page: values[3] + 1_000))
            }
        }
    }

    func testRawMatchPredicateHasNoExtraAnchorCapturePolicyOrFusedArithmetic() {
        // Pure copied predicate cases only. These unissuable anchors do NOT
        // prove a native condition/transaction can be created with these values.
        func raw(_ anchor: [Double], _ current: [Double]) -> Bridge.MatchFacts {
            var input = Bridge.MatchFacts(); input.abi_version = 1; input.flags = 127
            input.anchor_position = anchor[0].bitPattern; input.anchor_duration = anchor[1].bitPattern
            input.anchor_rate = anchor[2].bitPattern; input.anchor_observed_at_page_ms = anchor[3].bitPattern
            input.phone_position = anchor[4].bitPattern
            input.current_position = current[0].bitPattern; input.current_duration = current[1].bitPattern
            input.current_rate = current[2].bitPattern; input.current_observed_at_page_ms = current[3].bitPattern
            return input
        }
        // Independent original matches numeric formula, with all exact native
        // identity/capability/presence facts stipulated true for this raw seam.
        func original(_ anchor: [Double], _ current: [Double]) -> Bool {
            let elapsed = (current[3] - anchor[3]) / 1000
            guard elapsed.isFinite, elapsed >= 0, elapsed < 30,
                  current[1] == anchor[1], current[2] == anchor[2],
                  current[0].isFinite else { return false }
            return abs(current[0] - (anchor[0] + elapsed * anchor[2])) <= 1
                && abs(current[0] - anchor[4]) <= 2
        }
        for (anchor, current) in [
            ([10.0, Double.infinity, 0.0, 0.0, 10.0], [10.0, Double.infinity, -0.0, -0.0]),
            ([-1.0, 100.0, 1.0, 0.0, -1.0], [-1.0, 100.0, 1.0, 0.0]),
            ([100.0, 100.0, 1.0, 0.0, 100.0], [100.0, 100.0, 1.0, 0.0])] {
            XCTAssertTrue(original(anchor, current))
            XCTAssertEqual(Bridge.evaluateMatches(raw(anchor, current)), original(anchor, current))
        }
        // The original separately rounded product is128; adding-128 gives0.
        // Fusing the multiply/add would retain-2^-47 and incorrectly deny1.
        let fraction = 1.0 / 134_217_728.0
        let elapsed = (1 + fraction) * 8, rate = (1 - fraction) * 16
        let anchor: [Double] = [-128, 500, rate, 0, 1]
        let current: [Double] = [1, 500, rate, elapsed * 1_000]
        XCTAssertTrue(original(anchor, current))
        XCTAssertEqual(Bridge.evaluateMatches(raw(anchor, current)), true)
    }

    func testMalformedABIReservedAndUnknownFlagsFailClosedButMissingFactsAreOrdinaryRefusal() throws {
        let prepare = Bridge.prepareFacts(source: player(media()), phonePositionSeconds: 10)
        let anchor = try XCTUnwrap(MacChromeHandoffPauseCondition(source: player(media()), phonePositionSeconds: 10))
        let matches = Bridge.matchFacts(anchor: anchor, current: media())
        for bad: UInt32 in [0, 2, .max] {
            var input = prepare; input.abi_version = bad; XCTAssertNil(Bridge.evaluatePrepare(input))
            var current = matches; current.abi_version = bad; XCTAssertNil(Bridge.evaluateMatches(current))
        }
        for reserved: UInt32 in [1, .max] {
            var input = prepare; input.reserved = reserved; XCTAssertNil(Bridge.evaluatePrepare(input))
            var current = matches; current.reserved = reserved; XCTAssertNil(Bridge.evaluateMatches(current))
        }
        for bit in 7..<64 {
            var input = prepare; input.flags |= UInt64(1) << bit; XCTAssertNil(Bridge.evaluatePrepare(input))
            var current = matches; current.flags |= UInt64(1) << bit; XCTAssertNil(Bridge.evaluateMatches(current))
        }
        for bit in 0..<7 {
            var input = prepare; input.flags &= ~(UInt64(1) << bit)
            XCTAssertEqual(Bridge.evaluatePrepare(input), false)
            var current = matches; current.flags &= ~(UInt64(1) << bit)
            XCTAssertEqual(Bridge.evaluateMatches(current), false)
        }
        // Missing optional presence is valid denied input regardless of ignored
        // payload bits. Rust must not invent an absent-payload validation policy.
        for payload: UInt64 in [0, 1, (-0.0).bitPattern, Double.nan.bitPattern, .max] {
            var input = prepare; input.flags &= ~UInt64(96)
            input.position = payload; input.duration = payload
            XCTAssertEqual(Bridge.evaluatePrepare(input), false)
            var current = matches; current.flags &= ~UInt64(96)
            current.current_position = payload; current.current_duration = payload
            XCTAssertEqual(Bridge.evaluateMatches(current), false)
        }
    }

    func testForeignResultsAndEveryCopiedResultFieldUseActualRustValidators() throws {
        let prepareTrue = Bridge.prepareFacts(source: player(media()), phonePositionSeconds: 10)
        let prepareFalse = Bridge.prepareFacts(source: player(media(paused: true)), phonePositionSeconds: 10)
        let anchor = try XCTUnwrap(MacChromeHandoffPauseCondition(source: player(media()), phonePositionSeconds: 10))
        let matchTrue = Bridge.matchFacts(anchor: anchor, current: media())
        let matchFalse = Bridge.matchFacts(anchor: anchor, current: media(position: 80))
        for input in [prepareTrue, prepareFalse] {
            let actual = beluga_core_handoff_source_prepare(input)
            XCTAssertEqual(beluga_core_handoff_source_prepare_result_is_valid(input, actual), 1)
            for field in 0..<5 {
                XCTAssertNil(Bridge.evaluatePrepare(input, resultMutation: { _, result in
                    var changed = result
                    switch field {
                    case 0: changed.abi_version = 2
                    case 1: changed.status = 0
                    case 2: changed.allowed ^= 1
                    case 3: changed.reserved = 1
                    default: changed.allowed = 2
                    }
                    return changed
                }))
            }
            XCTAssertNil(Bridge.evaluatePrepare(input, resultMutation: { _, actual in
                .init(abi_version: 1, status: 1, allowed: actual.allowed ^ 1, reserved: 0)
            }))
        }
        for input in [matchTrue, matchFalse] {
            let actual = beluga_core_handoff_source_matches(input)
            XCTAssertEqual(beluga_core_handoff_source_matches_result_is_valid(input, actual), 1)
            for field in 0..<5 {
                XCTAssertNil(Bridge.evaluateMatches(input, resultMutation: { _, result in
                    var changed = result
                    switch field {
                    case 0: changed.abi_version = 2
                    case 1: changed.status = 0
                    case 2: changed.allowed ^= 1
                    case 3: changed.reserved = 1
                    default: changed.allowed = 2
                    }
                    return changed
                }))
            }
            XCTAssertNil(Bridge.evaluateMatches(input, resultMutation: { _, actual in
                .init(abi_version: 1, status: 1, allowed: actual.allowed ^ 1, reserved: 0)
            }))
        }
        // A genuine result for another copied input cannot authorize this one.
        let foreignPrepare = beluga_core_handoff_source_prepare(prepareTrue)
        XCTAssertNil(Bridge.evaluatePrepare(prepareFalse, resultMutation: { _, _ in foreignPrepare }))
        let foreignMatch = beluga_core_handoff_source_matches(matchTrue)
        XCTAssertNil(Bridge.evaluateMatches(matchFalse, resultMutation: { _, _ in foreignMatch }))
    }
}
