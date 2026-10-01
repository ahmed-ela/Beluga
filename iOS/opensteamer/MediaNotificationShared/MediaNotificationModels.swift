import Foundation

enum MediaNotificationAction: String, Codable, Sendable {
    case play, pause, previousTrack, nextTrack, seekBackward30, seekForward30, seekToPosition
}

struct MediaNotificationCapabilities: Codable, Equatable, Sendable {
    let canPlay: Bool
    let canPause: Bool
    let canSeekBackward: Bool
    let canSeekForward: Bool
    let canNext: Bool
    let canPrevious: Bool
    let canSeekToPosition: Bool

    init(canPlay: Bool, canPause: Bool, canSeekBackward: Bool, canSeekForward: Bool,
         canNext: Bool = false, canPrevious: Bool = false, canSeekToPosition: Bool = false) {
        self.canPlay = canPlay
        self.canPause = canPause
        self.canSeekBackward = canSeekBackward
        self.canSeekForward = canSeekForward
        self.canNext = canNext
        self.canPrevious = canPrevious
        self.canSeekToPosition = canSeekToPosition
    }

    private enum CodingKeys: String, CodingKey {
        case canPlay, canPause, canSeekBackward, canSeekForward, canNext, canPrevious, canSeekToPosition
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        canPlay = try values.decode(Bool.self, forKey: .canPlay)
        canPause = try values.decode(Bool.self, forKey: .canPause)
        canSeekBackward = try values.decode(Bool.self, forKey: .canSeekBackward)
        canSeekForward = try values.decode(Bool.self, forKey: .canSeekForward)
        canNext = try values.decodeIfPresent(Bool.self, forKey: .canNext) ?? false
        canPrevious = try values.decodeIfPresent(Bool.self, forKey: .canPrevious) ?? false
        canSeekToPosition = try values.decodeIfPresent(Bool.self, forKey: .canSeekToPosition) ?? false
    }

    func permits(_ action: MediaNotificationAction) -> Bool {
        switch action {
        case .play: canPlay
        case .pause: canPause
        case .nextTrack: canNext
        case .previousTrack: canPrevious
        case .seekBackward30: canSeekBackward
        case .seekForward30: canSeekForward
        case .seekToPosition: canSeekToPosition
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

    func permits(_ action: MediaNotificationAction, positionSeconds: Double? = nil,
                 expectedDurationSeconds: Double? = nil) -> Bool {
        guard isValid, capabilities.permits(action) else { return false }
        guard action == .seekToPosition else { return positionSeconds == nil && expectedDurationSeconds == nil }
        guard let positionSeconds, MediaNotificationValidation.time(positionSeconds),
              let position, position.isFinite, position >= 0,
              let duration, duration.isFinite, duration > 0,
              expectedDurationSeconds == duration else { return false }
        return positionSeconds <= duration
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

    var playingMask: UInt8 {
        entries.prefix(2).enumerated().reduce(0) { mask, entry in
            entry.element.isPlaying ? mask | (UInt8(1) << entry.offset) : mask
        }
    }
}

/// A last-read receipt, not proof of rendered pixels or command authority.
struct MediaNotificationExtensionReadReceipt: Codable, Equatable, Sendable {
    enum ReadStatus: String, Codable, Sendable { case current, unavailable, busy, failed }
    static let minimumWriteInterval: Double = 1
    static let maximumAge: Double = 5

    let epoch: UUID
    let revision: UInt64?
    let itemCount: UInt8
    let playingMask: UInt8
    let readStatus: ReadStatus
    let selectedItemIndex: UInt8?
    let sampledAtUptime: Double

    var isValid: Bool {
        guard sampledAtUptime.isFinite, sampledAtUptime >= 0, itemCount <= 2,
              playingMask < (UInt8(1) << itemCount),
              selectedItemIndex.map({ $0 < itemCount }) ?? true else { return false }
        if readStatus == .current { return revision.map { $0 > 0 } == true && itemCount > 0 }
        return revision == nil && itemCount == 0 && playingMask == 0 && selectedItemIndex == nil
    }

    func isFresh(at now: Double) -> Bool {
        isValid && now.isFinite && now >= sampledAtUptime && now - sampledAtUptime <= Self.maximumAge
    }

    func hasSameObservation(as other: Self) -> Bool {
        epoch == other.epoch && revision == other.revision && itemCount == other.itemCount
            && playingMask == other.playingMask && readStatus == other.readStatus
            && selectedItemIndex == other.selectedItemIndex
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
    let positionSeconds: Double?
    let expectedDurationSeconds: Double?

    init(id: UUID, epoch: UUID, revision: UInt64, contextID: String,
         action: MediaNotificationAction, deadlineUptime: Double, positionSeconds: Double? = nil,
         expectedDurationSeconds: Double? = nil) {
        self.id = id
        self.epoch = epoch
        self.revision = revision
        self.contextID = contextID
        self.action = action
        self.deadlineUptime = deadlineUptime
        self.positionSeconds = positionSeconds
        self.expectedDurationSeconds = expectedDurationSeconds
    }

    func isValid(at now: Double) -> Bool {
        revision > 0 && MediaNotificationValidation.text(contextID, bytes: 128)
            && now.isFinite && now >= 0 && deadlineUptime.isFinite
            && deadlineUptime > now && deadlineUptime - now <= Self.maximumLifetime
            && (action == .seekToPosition
                ? positionSeconds != nil && MediaNotificationValidation.time(positionSeconds)
                    && expectedDurationSeconds.map { $0 > 0 && MediaNotificationValidation.time($0) } == true
                : positionSeconds == nil && expectedDurationSeconds == nil)
    }

    func isAdmitted(by snapshot: MediaNotificationSnapshot, at now: Double) -> Bool {
        isValid(at: now) && snapshot.isFresh(at: now) && snapshot.ready
            && epoch == snapshot.epoch && revision <= snapshot.revision
            && snapshot.entries.contains {
                $0.contextID == contextID && $0.permits(action, positionSeconds: positionSeconds,
                    expectedDurationSeconds: expectedDurationSeconds)
            }
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
