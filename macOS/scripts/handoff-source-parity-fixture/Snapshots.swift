// Foundation-only snapshot shape fixtures for copied-value parity.
// NOT production replacements or evidence of native snapshot/permission behavior.
#if BELUGA_HANDOFF_PURE_STUB_FIXTURE
import Foundation

struct MacChromePlayerIdentity: Equatable, Hashable, Sendable {
    let processID: Int32
    let launchDate: Date
}
struct MacChromeTabIdentity: Equatable, Hashable, Sendable {
    let owner: MacChromePlayerIdentity
    let windowID: String
    let tabID: String
}
struct MacChromeScriptSnapshot: Codable, Equatable, Sendable {
    let documentID: String
    let itemID: String
    let itemGeneration: Int64
    let videoID: String
    let title: String
    let artist: String?
    let duration: Double?
    let elapsedTime: Double?
    let playbackRate: Double
    let paused: Bool
    let observedAtUnixMilliseconds: Double
    let observedAtPageMilliseconds: Double
    let canPlay: Bool
    let canPause: Bool
    let canNext: Bool
    let canPrevious: Bool
    var canSeek: Bool? = nil
    var playbackContinuityID: String? = nil
}
struct MacChromePlayerSnapshot: Sendable {
    let tab: MacChromeTabIdentity
    let media: MacChromeScriptSnapshot
    let receivedAtUptime: TimeInterval
}

enum MacChromeAppleEventsBackend {
    // Exact parser preimage copied from canonical backend lines 482-491.
    // No Apple Events, AppKit/CoreServices/WebRTC or native command is included.
    static func videoID(from value: String) -> String? {
        guard value.utf8.count <= 8_192, let url = URLComponents(string: value),
              url.scheme == "https", url.host == "www.youtube.com", url.path == "/watch",
              url.port == nil, url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        let values = (url.queryItems ?? []).filter { $0.name == "v" }
        guard values.count == 1, let id = values.first?.value, id.utf8.count == 11,
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return id
    }
}
#endif
