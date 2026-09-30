import Foundation

enum MediaNotificationAction: String, Codable, Sendable {
    case play, pause, seekBackward30, seekForward30
}

struct MediaNotificationCapabilities: Codable, Equatable, Sendable {
    let canPlay: Bool
    let canPause: Bool
    let canSeekBackward: Bool
    let canSeekForward: Bool

    func permits(_ action: MediaNotificationAction) -> Bool {
        switch action {
        case .play: canPlay
        case .pause: canPause
        case .seekBackward30: canSeekBackward
        case .seekForward30: canSeekForward
        }
    }
}

struct MediaNotificationEntry: Codable, Equatable, Identifiable, Sendable {
    let contextID: String
    let sourceName: String
    let title: String
    let isPlaying: Bool
    let position: Double?
    let duration: Double?
    let capabilities: MediaNotificationCapabilities
    var id: String { contextID }

    var isValid: Bool {
        MediaNotificationValidation.text(contextID, bytes: 128)
            && MediaNotificationValidation.text(sourceName, bytes: 128)
            && MediaNotificationValidation.text(title, bytes: 512)
            && MediaNotificationValidation.time(position)
            && MediaNotificationValidation.time(duration)
    }
}

struct MediaNotificationSnapshot: Codable, Equatable, Sendable {
    static let maximumAge: Double = 5
    let epoch: UUID
    let revision: UInt64
    let publishedAtUptime: Double
    let ready: Bool
    let entries: [MediaNotificationEntry]

    var isValid: Bool {
        revision > 0 && publishedAtUptime.isFinite && publishedAtUptime >= 0
            && entries.count <= 2 && entries.allSatisfy(\.isValid)
            && Set(entries.map(\.contextID)).count == entries.count
            && (!ready || !entries.isEmpty)
    }

    func isFresh(at now: Double) -> Bool {
        isValid && now.isFinite && now >= publishedAtUptime
            && now - publishedAtUptime <= Self.maximumAge
    }
}

struct MediaNotificationRequest: Codable, Equatable, Sendable {
    static let maximumLifetime: Double = 2
    let id: UUID
    let epoch: UUID
    let revision: UInt64
    let contextID: String
    let action: MediaNotificationAction
    let deadlineUptime: Double

    func isValid(at now: Double) -> Bool {
        revision > 0 && MediaNotificationValidation.text(contextID, bytes: 128)
            && now.isFinite && now >= 0 && deadlineUptime.isFinite
            && deadlineUptime > now && deadlineUptime - now <= Self.maximumLifetime
    }

    func isAdmitted(by snapshot: MediaNotificationSnapshot, at now: Double) -> Bool {
        isValid(at: now) && snapshot.isFresh(at: now) && snapshot.ready
            && epoch == snapshot.epoch && revision <= snapshot.revision
            && snapshot.entries.contains { $0.contextID == contextID && $0.capabilities.permits(action) }
    }
}

enum MediaNotificationResult: String, Codable, Sendable {
    case pending, applied, rejected, unavailable, stale, failed, expired
}

struct MediaNotificationAcknowledgement: Codable, Equatable, Sendable {
    let id: UUID
    let epoch: UUID
    let result: MediaNotificationResult
}

enum MediaNotificationConfiguration {
    static let category = "BelugaMediaControls"
    static let epochKey = "belugaMediaEpoch"
    static let groupKey = "BelugaMediaAppGroup"
}

/// Presentation choice is not command authority. Retiring a chosen context must never silently
/// redirect the shared buttons to another player. Only the first catalog gets a default choice.
struct MediaNotificationSelection {
    private(set) var contextID: String?
    private var hasChosenInitialSource = false

    mutating func refresh(contextIDs: [String]) {
        if !hasChosenInitialSource, let first = contextIDs.first {
            contextID = first
            hasChosenInitialSource = true
        } else if let contextID, !contextIDs.contains(contextID) {
            self.contextID = nil
        }
    }

    mutating func select(_ contextID: String, available: [String]) {
        guard available.contains(contextID) else { return }
        self.contextID = contextID
        hasChosenInitialSource = true
    }
}

private enum MediaNotificationValidation {
    static func text(_ value: String, bytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= bytes
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    static func time(_ value: Double?) -> Bool {
        value.map { $0.isFinite && $0 >= 0 && $0 <= 31_536_000 } ?? true
    }
}
