import Foundation

/// A drag previews a position; it grants no authority until the current mailbox is rechecked.
struct MediaNotificationScrub {
    let epoch: UUID
    let contextID: String
    let initialRevision: UInt64
    let duration: Double
    private(set) var position: Double
    private var active = true

    init?(snapshot: MediaNotificationSnapshot, contextID: String, now: Double) {
        guard snapshot.ready, snapshot.isFresh(at: now),
              let entry = snapshot.entries.first(where: { $0.contextID == contextID }),
              let duration = Self.timelineDuration(entry), let position = entry.position else { return nil }
        self.epoch = snapshot.epoch
        self.contextID = contextID
        self.initialRevision = snapshot.revision
        self.duration = duration
        self.position = min(position, duration)
    }

    static func timelineDuration(_ entry: MediaNotificationEntry) -> Double? {
        guard entry.isValid, entry.capabilities.canSeekToPosition,
              let duration = entry.duration, duration > 0,
              let position = entry.position, position.isFinite, position >= 0 else { return nil }
        return duration
    }

    func matches(_ snapshot: MediaNotificationSnapshot, selectedContextID: String?, now: Double) -> Bool {
        active && snapshot.ready && snapshot.isFresh(at: now) && snapshot.epoch == epoch
            && snapshot.revision >= initialRevision && selectedContextID == contextID
            && snapshot.entries.contains { $0.contextID == contextID && Self.timelineDuration($0) == duration }
    }

    mutating func update(position: Double) {
        guard active, position.isFinite else { return }
        self.position = min(max(0, position), duration)
    }

    mutating func finish(snapshot: MediaNotificationSnapshot, selectedContextID: String?, now: Double) -> MediaNotificationRequest? {
        let admitted = matches(snapshot, selectedContextID: selectedContextID, now: now)
        active = false
        guard admitted else { return nil }
        let request = MediaNotificationRequest(id: UUID(), epoch: epoch, revision: snapshot.revision,
            contextID: contextID, action: .seekToPosition,
            deadlineUptime: now + MediaNotificationRequest.maximumLifetime, positionSeconds: position,
            expectedDurationSeconds: duration)
        return request.isAdmitted(by: snapshot, at: now) ? request : nil
    }
}
