import Foundation

/// Frozen, test-only numeric reference of the pre-migration choice order.
/// This table does not import BelugaCore or call the native projection/decoder.
enum SupportedPlayerArbitrationOriginalReference {
    struct Answer: Equatable {
        let action: UInt32
        let primaryOrHold: UInt32
    }

    // Rows are browser-major (none, available-paused, playing); columns are
    // current hold (none, browser, music). Every entry is a literal original trace.
    private static let nonRetryRows: [[UInt32]] = [
        [0, 0, 0], [2, 2, 2], [2, 2, 2],
        [1, 1, 1], [1, 1, 2], [2, 2, 2],
        [1, 1, 1], [1, 1, 1], [1, 1, 2],
    ]

    static func answer(hold: UInt32, browser: UInt32, music: UInt32) -> Answer {
        precondition(hold <= 2 && browser <= 3 && music <= 3)
        if browser == 3 || music == 3 { return Answer(action: 1, primaryOrHold: hold) }
        return Answer(action: 2, primaryOrHold: nonRetryRows[Int(browser * 3 + music)][Int(hold)])
    }
}
