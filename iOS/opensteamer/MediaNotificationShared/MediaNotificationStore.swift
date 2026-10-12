import Foundation
import Darwin

/// A single bounded mailbox. Only the containing app publishes snapshots and claims/acknowledges
/// commands. The extension submits intent; neither process treats shared metadata as transport authority.
final class MediaNotificationStore: @unchecked Sendable {
    enum StoreError: Error { case busy, invalid, capacity, io(Int32) }
    static let maximumFileBytes = 262_144
    static let maximumConsumedRequests = 1_024
    static let maximumExtensionReceiptBytes = 1_024
    let directoryURL: URL

    private struct Record<Value: Codable>: Codable {
        let version: Int
        let value: Value
    }

    private struct Journal: Codable {
        let epoch: UUID
        var acknowledgements: [MediaNotificationAcknowledgement]
    }

    init(directoryURL: URL) {
        self.directoryURL = directoryURL.resolvingSymlinksInPath().standardizedFileURL
    }

    static func configured(bundle: Bundle = .main) -> MediaNotificationStore? {
        guard let group = bundle.object(forInfoDictionaryKey: MediaNotificationConfiguration.groupKey) as? String,
              ["group.org.example.AudioStreamer.dev.media", "group.com.elamin.opensteamer.media"].contains(group),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return MediaNotificationStore(directoryURL: container.appendingPathComponent("MediaControls-v1", isDirectory: true))
    }

    func publishSnapshot(_ snapshot: MediaNotificationSnapshot) throws {
        guard snapshot.isValid else { throw StoreError.invalid }
        try locked {
            let previous: MediaNotificationSnapshot? = try read("snapshot.json")
            if let previous, previous.epoch == snapshot.epoch {
                guard snapshot.revision >= previous.revision,
                      snapshot.publishedAtUptime >= previous.publishedAtUptime else { throw StoreError.invalid }
                // A heartbeat may refresh time but must not silently reuse a semantic revision.
                if snapshot.revision == previous.revision {
                    guard snapshot.ready == previous.ready, snapshot.entries == previous.entries else { throw StoreError.invalid }
                }
            }
            if previous?.epoch != snapshot.epoch {
                try write(Journal(epoch: snapshot.epoch, acknowledgements: []), to: "journal.json")
            }
            try write(snapshot, to: "snapshot.json")
        }
    }

    func readSnapshot(now: Double = ProcessInfo.processInfo.systemUptime) throws -> MediaNotificationSnapshot? {
        try locked {
            guard let value: MediaNotificationSnapshot = try read("snapshot.json"), value.isFresh(at: now) else { return nil }
            return value
        }
    }

    /// Diagnostic I/O must not hold the authoritative snapshot/command mailbox lock.
    @discardableResult
    func recordExtensionReadReceipt(_ receipt: MediaNotificationExtensionReadReceipt) throws -> Bool {
        guard receipt.isValid else { throw StoreError.invalid }
        return try locked(lockName: "diagnostics.lock") {
            let previous: MediaNotificationExtensionReadReceipt? =
                try read("extension-read.json", maximumBytes: Self.maximumExtensionReceiptBytes)
            if let previous, previous.isValid, receipt.hasSameObservation(as: previous),
               receipt.sampledAtUptime >= previous.sampledAtUptime,
               receipt.sampledAtUptime - previous.sampledAtUptime <
                    MediaNotificationExtensionReadReceipt.minimumWriteInterval { return false }
            try write(receipt, to: "extension-read.json")
            return true
        }
    }

    func readExtensionReadReceipt() throws -> MediaNotificationExtensionReadReceipt? {
        try locked(lockName: "diagnostics.lock") {
            guard let receipt: MediaNotificationExtensionReadReceipt =
                try read("extension-read.json", maximumBytes: Self.maximumExtensionReceiptBytes) else { return nil }
            guard receipt.isValid else { throw StoreError.invalid }
            return receipt
        }
    }

    @discardableResult
    func submit(_ request: MediaNotificationRequest, now: Double = ProcessInfo.processInfo.systemUptime) throws -> Bool {
        try locked {
            guard let snapshot: MediaNotificationSnapshot = try read("snapshot.json"),
                  request.isAdmitted(by: snapshot, at: now),
                  let journal = try journal(for: request.epoch),
                  !journal.acknowledgements.contains(where: { $0.id == request.id }) else { return false }
            guard journal.acknowledgements.count < Self.maximumConsumedRequests else { throw StoreError.capacity }
            if let pending: MediaNotificationRequest = try read("request.json"), pending.epoch == request.epoch {
                if pending.id == request.id { return false }
                let result = journal.acknowledgements.first { $0.id == pending.id }?.result
                if pending.deadlineUptime > now && (result == nil || result == .pending) { return false }
            }
            try write(request, to: "request.json")
            return true
        }
    }

    /// Durably consume before returning: a crashed owner may lose a command, but cannot replay it.
    func claimPendingRequest(epoch: UUID, now: Double = ProcessInfo.processInfo.systemUptime) throws -> MediaNotificationRequest? {
        try locked {
            guard let request: MediaNotificationRequest = try read("request.json"), request.epoch == epoch,
                  let snapshot: MediaNotificationSnapshot = try read("snapshot.json"), snapshot.epoch == epoch,
                  var journal = try journal(for: epoch),
                  !journal.acknowledgements.contains(where: { $0.id == request.id }) else { return nil }
            guard journal.acknowledgements.count < Self.maximumConsumedRequests else { throw StoreError.capacity }
            let admitted = request.isAdmitted(by: snapshot, at: now)
            let result: MediaNotificationResult = admitted ? .pending
                : (request.deadlineUptime <= now ? .expired : .stale)
            journal.acknowledgements.append(.init(id: request.id, epoch: epoch, result: result))
            try write(journal, to: "journal.json")
            return admitted ? request : nil
        }
    }

    @discardableResult
    func acknowledge(_ acknowledgement: MediaNotificationAcknowledgement) throws -> Bool {
        guard acknowledgement.result != .pending else { return false }
        return try locked {
            guard let request: MediaNotificationRequest = try read("request.json"),
                  request.id == acknowledgement.id, request.epoch == acknowledgement.epoch,
                  let snapshot: MediaNotificationSnapshot = try read("snapshot.json"), snapshot.epoch == request.epoch,
                  var journal = try journal(for: request.epoch),
                  let index = journal.acknowledgements.firstIndex(where: { $0.id == request.id }),
                  journal.acknowledgements[index].result == .pending else { return false }
            journal.acknowledgements[index] = acknowledgement
            try write(journal, to: "journal.json")
            return true
        }
    }

    func acknowledgement(for request: MediaNotificationRequest) throws -> MediaNotificationAcknowledgement? {
        try locked { try journal(for: request.epoch)?.acknowledgements.first { $0.id == request.id } }
    }

    /// The owner may retire a full journal only after the last request's admission deadline and
    /// transport acknowledgement window have elapsed. IDs are never evicted inside an epoch.
    func needsIdleEpochRotation(epoch: UUID, now: Double = ProcessInfo.processInfo.systemUptime) throws -> Bool {
        try locked {
            guard now.isFinite, let journal = try journal(for: epoch),
                  journal.acknowledgements.count == Self.maximumConsumedRequests else { return false }
            if let request: MediaNotificationRequest = try read("request.json"), request.epoch == epoch {
                guard request.deadlineUptime.isFinite, now >= request.deadlineUptime + 3 else { return false }
            }
            return true
        }
    }

    private func journal(for epoch: UUID) throws -> Journal? {
        guard let value: Journal = try read("journal.json"), value.epoch == epoch,
              value.acknowledgements.count <= Self.maximumConsumedRequests,
              value.acknowledgements.allSatisfy({ $0.epoch == epoch }),
              Set(value.acknowledgements.map(\.id)).count == value.acknowledgements.count else { return nil }
        return value
    }

    private func locked<Value>(lockName: String = "mailbox.lock", _ body: () throws -> Value) throws -> Value {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        guard directoryURL.standardizedFileURL == directoryURL.resolvingSymlinksInPath().standardizedFileURL else {
            throw StoreError.invalid
        }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: directoryURL.path)
        #endif
        let descriptor = Darwin.open(directoryURL.appendingPathComponent(lockName).path,
                                     O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw StoreError.io(errno) }
        defer { Darwin.close(descriptor) }
        _ = try validate(descriptor, maximumBytes: 0)
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { throw StoreError.busy }
            throw StoreError.io(errno)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func validate(_ descriptor: Int32, maximumBytes: Int) throws -> Int {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw StoreError.io(errno) }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1,
              info.st_uid == getuid(), info.st_size >= 0, info.st_size <= maximumBytes else { throw StoreError.invalid }
        return Int(info.st_size)
    }

    private func read<Value: Codable>(_ name: String,
                                      maximumBytes: Int = MediaNotificationStore.maximumFileBytes) throws -> Value? {
        let descriptor = Darwin.open(directoryURL.appendingPathComponent(name).path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw StoreError.io(errno)
        }
        defer { Darwin.close(descriptor) }
        let expectedSize = try validate(descriptor, maximumBytes: maximumBytes)
        var bytes = [UInt8](repeating: 0, count: expectedSize + 1)
        let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
        guard count >= 0 else { throw StoreError.io(errno) }
        guard count == expectedSize else { throw StoreError.invalid }
        let record = try JSONDecoder().decode(Record<Value>.self, from: Data(bytes.prefix(count)))
        guard record.version == 1 else { throw StoreError.invalid }
        return record.value
    }

    private func write<Value: Codable>(_ value: Value, to name: String) throws {
        let data = try JSONEncoder().encode(Record(version: 1, value: value))
        guard data.count <= Self.maximumFileBytes else { throw StoreError.capacity }
        let temporary = directoryURL.appendingPathComponent("write-" + UUID().uuidString)
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw StoreError.io(errno) }
        defer { Darwin.close(descriptor); unlink(temporary.path) }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: temporary.path)
        #endif
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw StoreError.io(errno) }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw StoreError.io(errno) }
        guard rename(temporary.path, directoryURL.appendingPathComponent(name).path) == 0 else { throw StoreError.io(errno) }
    }
}
