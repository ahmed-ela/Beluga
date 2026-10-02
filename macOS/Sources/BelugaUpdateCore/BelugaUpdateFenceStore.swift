import CryptoKit
import Darwin
import Foundation

/// Durable storage only: the broker still owns the ordinary shared host lock, authenticates
/// installation/readiness, and must not start updater machinery until create returns success.
/// Every extant or malformed marker denies activation. Restoring it never restores fresh proof.
package struct BelugaUpdateFenceStore: Sendable {
    static let fileName = "update-operation-v1.json"
    private static let serialization = Serialization()
    private let directoryURL: URL

    /// Composition supplies a private service directory, never an app bundle or public path.
    /// This initializer performs no filesystem access and read does not create the namespace.
    package init(directoryURL: URL) throws {
        let path = directoryURL.path
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard directoryURL.isFileURL, path.utf8.count <= 4_096, path.hasPrefix("/"),
              components.count > 1, components.dropFirst().allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }), path.utf8.allSatisfy({ $0 >= 32 && $0 != 127 }) else {
            throw Failure.unsafeDirectory
        }
        self.directoryURL = directoryURL
    }

    package struct Snapshot: Equatable, Sendable {
        package let operation: BelugaUpdateOperation
        package let recordSHA256: String
        fileprivate let bytes: Data
        fileprivate let file: FileFingerprint
        fileprivate let directory: NodeIdentity
        fileprivate let parent: NodeIdentity
    }

    package enum Failure: Error, Equatable {
        case unsafeDirectory, unsafeFile, invalidRecord, unexpectedBinding
        case alreadyExists, staleRecord, nonmonotonicTransition, releaseNotAuthorized
        case io(Int32), durabilityUncertain(Int32)
    }

    /// Absent parent/directory/marker means absent; no mkdir, chmod, or write is performed.
    package func read(expectedTarget: BelugaUpdateOperation.Target) throws -> Snapshot? {
        try serialized {
            try validateOwner(expectedTarget)
            guard let directory = try openDirectory(create: false) else { return nil }
            defer { directory.close() }
            let result = try readRecord(directory, expectedTarget: expectedTarget)
            try revalidateDirectory(directory)
            return result
        }
    }

    /// Exclusive initial publication. A prepared marker is never retired on cancellation.
    package func create(_ operation: BelugaUpdateOperation) throws -> Snapshot {
        try serialized {
            try validateOwner(operation.target)
            guard operation.stage == .prepared else { throw Failure.nonmonotonicTransition }
            let bytes = try validatedBytes(operation)
            guard let directory = try openDirectory(create: true) else { throw Failure.unsafeDirectory }
            defer { directory.close() }
            guard try readRecord(directory, expectedTarget: operation.target) == nil else {
                throw Failure.alreadyExists
            }
            let temporary = try writeTemporary(bytes, directory: directory)
            defer { Darwin.close(temporary.descriptor) }
            try revalidateDirectory(directory)
            guard try readRecord(directory, expectedTarget: operation.target) == nil else {
                throw Failure.alreadyExists
            }
            try revalidateTemporary(temporary, directory: directory)
            guard Darwin.renameatx_np(directory.descriptor, temporary.name,
                                      directory.descriptor, Self.fileName, UInt32(RENAME_EXCL)) == 0 else {
                if errno == EEXIST { throw Failure.alreadyExists }
                throw Failure.io(errno)
            }
            try syncDirectory(directory.descriptor)
            try revalidateDirectory(directory)
            guard let committed = try readRecord(directory, expectedTarget: operation.target),
                  committed.bytes == bytes else { throw Failure.staleRecord }
            return committed
        }
    }

    /// Compare-before-replace binds bytes and inode generation, not merely a stage or nonce.
    /// All instances serialize in this process; this is NOT cross-process/filesystem CAS.
    /// The unchanged shared host lock must exclude other legitimate writers throughout.
    package func replace(_ operation: BelugaUpdateOperation, expected: Snapshot) throws -> Snapshot {
        try serialized {
            try validateOwner(operation.target)
            let bytes = try validatedBytes(operation)
            try validateTransition(from: expected.operation, to: operation)
            guard let directory = try openDirectory(create: false) else { throw Failure.staleRecord }
            defer { directory.close() }
            _ = try requireCurrent(expected, directory: directory)
            if bytes == expected.bytes { return expected }
            let temporary = try writeTemporary(bytes, directory: directory)
            defer { Darwin.close(temporary.descriptor) }
            try revalidateDirectory(directory)
            _ = try requireCurrent(expected, directory: directory)
            try revalidateTemporary(temporary, directory: directory)
            guard Darwin.renameat(directory.descriptor, temporary.name,
                                  directory.descriptor, Self.fileName) == 0 else {
                throw Failure.io(errno)
            }
            try syncDirectory(directory.descriptor)
            try revalidateDirectory(directory)
            guard let committed = try readRecord(directory, expectedTarget: operation.target),
                  committed.bytes == bytes else { throw Failure.staleRecord }
            return committed
        }
    }

    /// Only a fresh operation plus exact installed completion and its accepted menu response
    /// may remove the exact current marker. These values authenticate nothing themselves;
    /// supported installer/readback and authenticated IPC remain the broker's responsibility.
    /// If final directory sync fails, retain the host lock and report failure. Power-loss
    /// durability cannot be promised on a failed sync: restored evidence blocks conservatively;
    /// absence after crash is safe only because fresh clearance was authorized before unlink.
    package func clear(
        _ operation: BelugaUpdateOperation,
        expected: Snapshot,
        installedCompletion: BelugaUpdateOperation.InstalledCompletion,
        readiness: BelugaUpdateOperation.MenuReadiness
    ) throws {
        try serialized {
            try validateOwner(operation.target)
            let bytes = try validatedBytes(operation)
            guard operation.permitsFenceRelease, bytes == expected.bytes,
                  installedCompletion.operationID == operation.operationID,
                  installedCompletion.target == operation.target,
                  installedCompletion.candidate == operation.candidate,
                  readiness.isReady, readiness.operationID == operation.operationID,
                  readiness.target == operation.target, readiness.candidate == operation.candidate,
                  try recordedReadiness(bytes) == readiness else {
                throw Failure.releaseNotAuthorized
            }
            guard let directory = try openDirectory(create: false) else { throw Failure.staleRecord }
            defer { directory.close() }
            _ = try requireCurrent(expected, directory: directory)
            try revalidateDirectory(directory)
            _ = try requireCurrent(expected, directory: directory)
            guard Darwin.unlinkat(directory.descriptor, Self.fileName, 0) == 0 else {
                throw Failure.io(errno)
            }
            try syncDirectory(directory.descriptor)
            try revalidateDirectory(directory)
            guard try readRecord(directory, expectedTarget: operation.target) == nil else {
                throw Failure.staleRecord
            }
        }
    }

    /// Module-private: only BrokerSession's live controlled-history/SDK/predecessor gate
    /// may call this. Decoded prepared JSON alone is never clearance authority.
    func retireFreshPrepared(_ operation: BelugaUpdateOperation, expected: Snapshot,
                             reason: BelugaUpdateUnarmedCompletion.Reason) throws {
        try serialized {
            try validateOwner(operation.target)
            let bytes = try validatedBytes(operation)
            guard operation.stage == .prepared, reason.matches(candidate: operation.candidate),
                  !operation.installerMayRemainArmed, bytes == expected.bytes else {
                throw Failure.releaseNotAuthorized
            }
            guard let directory = try openDirectory(create: false) else { throw Failure.staleRecord }
            defer { directory.close() }
            _ = try requireCurrent(expected, directory: directory)
            try revalidateDirectory(directory)
            _ = try requireCurrent(expected, directory: directory)
            guard Darwin.unlinkat(directory.descriptor, Self.fileName, 0) == 0 else {
                throw Failure.io(errno)
            }
            try syncDirectory(directory.descriptor)
            try revalidateDirectory(directory)
            guard try readRecord(directory, expectedTarget: operation.target) == nil else {
                throw Failure.staleRecord
            }
        }
    }

    private func serialized<Value>(_ body: () throws -> Value) rethrows -> Value {
        Self.serialization.lock.lock()
        defer { Self.serialization.lock.unlock() }
        return try body()
    }

    private func validateOwner(_ target: BelugaUpdateOperation.Target) throws {
        guard target.effectiveUID == Darwin.geteuid() else { throw Failure.unexpectedBinding }
    }

    private func validatedBytes(_ operation: BelugaUpdateOperation) throws -> Data {
        do {
            let bytes = try operation.encodedRecord()
            _ = try BelugaUpdateOperation.restoring(from: bytes, expectedTarget: operation.target,
                                                   expectedOperationID: operation.operationID)
            return bytes
        } catch { throw Failure.invalidRecord }
    }

    private func validateTransition(from previous: BelugaUpdateOperation,
                                    to next: BelugaUpdateOperation) throws {
        guard previous.operationID == next.operationID, previous.target == next.target,
              previous.predecessor == next.predecessor,
              try immutableFields(previous) == immutableFields(next) else {
            throw Failure.unexpectedBinding
        }
        guard rank(next.stage) >= rank(previous.stage),
              previous.candidate == nil || next.candidate == previous.candidate,
              previous.brokerBinding == nil || next.brokerBinding == previous.brokerBinding else {
            throw Failure.nonmonotonicTransition
        }
        if previous.brokerBinding == nil, next.brokerBinding != nil {
            guard previous.stage == .prepared, next.stage == .prepared else {
                throw Failure.nonmonotonicTransition
            }
        }
        if next.stage != .prepared, next.brokerBinding == nil { throw Failure.nonmonotonicTransition }
        // Persisting a new terminal record requires fresh policy authority, not restored JSON.
        if next.stage == .readyToRelease, try next.encodedRecord() != previous.encodedRecord(),
           !next.permitsFenceRelease { throw Failure.releaseNotAuthorized }
    }

    private func rank(_ stage: BelugaUpdateOperation.Stage) -> Int {
        switch stage {
        case .prepared: 0
        case .possiblyArmed: 1
        case .installedVerified: 2
        case .readyToRelease: 3
        }
    }

    private func immutableFields(_ operation: BelugaUpdateOperation) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: operation.encodedRecord())
            as? [String: Any] else { throw Failure.invalidRecord }
        for name in ["candidate", "stage", "readiness", "broker"] { object.removeValue(forKey: name) }
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func recordedReadiness(_ bytes: Data) throws -> BelugaUpdateOperation.MenuReadiness? {
        struct TerminalProjection: Decodable { let readiness: BelugaUpdateOperation.MenuReadiness? }
        return try JSONDecoder().decode(TerminalProjection.self, from: bytes).readiness
    }

    private func requireCurrent(_ expected: Snapshot,
                                directory: OpenedDirectory) throws -> Snapshot {
        guard try nodeIdentity(directory.descriptor) == expected.directory,
              try nodeIdentity(directory.parentDescriptor) == expected.parent,
              let current = try readRecord(directory, expectedTarget: expected.operation.target),
              current.file == expected.file, current.bytes == expected.bytes,
              current.recordSHA256 == expected.recordSHA256 else { throw Failure.staleRecord }
        return current
    }

    private func readRecord(_ directory: OpenedDirectory,
                            expectedTarget: BelugaUpdateOperation.Target) throws -> Snapshot? {
        var named = stat()
        if Darwin.fstatat(directory.descriptor, Self.fileName, &named, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return nil }
            throw Failure.io(errno)
        }
        guard Self.isSafeFileMetadata(named, expectedOwner: Darwin.geteuid()) else {
            throw Failure.unsafeFile
        }
        let descriptor = Darwin.openat(directory.descriptor, Self.fileName,
                                        O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw Failure.unsafeFile }
        defer { Darwin.close(descriptor) }
        try rejectAllowACL(descriptor)
        let before = try fileFingerprint(descriptor)
        guard before == FileFingerprint(named) else { throw Failure.staleRecord }
        var buffer = [UInt8](repeating: 0, count: BelugaUpdateOperation.maximumRecordBytes + 1)
        var used = 0
        var interruptions = 0
        while used < buffer.count {
            let remaining = buffer.count - used
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress!.advanced(by: used), remaining)
            }
            if count < 0, errno == EINTR, interruptions < 16 { interruptions += 1; continue }
            guard count >= 0 else { throw Failure.io(errno) }
            if count == 0 { break }
            used += count
        }
        guard used == Int(named.st_size), used <= BelugaUpdateOperation.maximumRecordBytes,
              try fileFingerprint(descriptor) == before else { throw Failure.staleRecord }
        var after = stat()
        guard Darwin.fstatat(directory.descriptor, Self.fileName, &after, AT_SYMLINK_NOFOLLOW) == 0,
              Self.isSafeFileMetadata(after, expectedOwner: Darwin.geteuid()),
              FileFingerprint(after) == before else { throw Failure.staleRecord }
        let bytes = Data(buffer.prefix(used))
        let operation: BelugaUpdateOperation
        do { operation = try BelugaUpdateOperation.restoring(from: bytes, expectedTarget: expectedTarget) }
        catch { throw Failure.invalidRecord }
        return Snapshot(operation: operation,
                        recordSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                        bytes: bytes, file: before, directory: try nodeIdentity(directory.descriptor),
                        parent: try nodeIdentity(directory.parentDescriptor))
    }

    /// Temp artifacts are kept on ANY failure as private evidence; they are never read as
    /// markers or silently cleaned. Successful rename consumes only this operation's temp.
    private func writeTemporary(_ bytes: Data, directory: OpenedDirectory) throws -> Temporary {
        let name = ".update-operation-v1.\(UUID().uuidString).tmp"
        let descriptor = Darwin.openat(directory.descriptor, name,
                                        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Failure.io(errno) }
        do {
            guard Darwin.fchmod(descriptor, 0o600) == 0 else { throw Failure.io(errno) }
            try rejectAllowACL(descriptor)
            var interruptions = 0
            try bytes.withUnsafeBytes { buffer in
                var used = 0
                while used < buffer.count {
                    let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: used), buffer.count - used)
                    if count < 0, errno == EINTR, interruptions < 16 { interruptions += 1; continue }
                    guard count > 0 else { throw Failure.io(errno) }
                    used += count
                }
            }
            let fingerprint = try fileFingerprint(descriptor)
            guard fingerprint.size == Int64(bytes.count) else { throw Failure.unsafeFile }
            guard Darwin.fsync(descriptor) == 0 else { throw Failure.durabilityUncertain(errno) }
            // F_FULLFSYNC asks Darwin to flush drive caches as well as filesystem buffers.
            // Unsupported/failed durability is an error, not an optimistic fallback.
            guard Darwin.fcntl(descriptor, F_FULLFSYNC) == 0 else { throw Failure.durabilityUncertain(errno) }
            return Temporary(name: name, descriptor: descriptor, file: fingerprint)
        } catch { Darwin.close(descriptor); throw error }
    }

    private func revalidateTemporary(_ temporary: Temporary, directory: OpenedDirectory) throws {
        var named = stat()
        guard try fileFingerprint(temporary.descriptor) == temporary.file,
              Darwin.fstatat(directory.descriptor, temporary.name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              Self.isSafeFileMetadata(named, expectedOwner: Darwin.geteuid()),
              FileFingerprint(named) == temporary.file else { throw Failure.unsafeFile }
    }

    private func syncDirectory(_ descriptor: Int32) throws {
        guard Darwin.fsync(descriptor) == 0 else { throw Failure.durabilityUncertain(errno) }
    }

    private func openDirectory(create: Bool) throws -> OpenedDirectory? {
        let components = directoryURL.pathComponents.dropFirst()
        guard let leaf = components.last else { throw Failure.unsafeDirectory }
        var parent = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parent >= 0 else { throw Failure.io(errno) }
        do {
            for component in components.dropLast() {
                let next = Darwin.openat(parent, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                if next < 0 {
                    if errno == ENOENT, !create { Darwin.close(parent); return nil }
                    throw Failure.unsafeDirectory
                }
                Darwin.close(parent)
                parent = next
                try validateAncestor(parent)
            }
            var created = false
            if create {
                if Darwin.mkdirat(parent, leaf, 0o700) == 0 { created = true }
                else if errno != EEXIST { throw Failure.io(errno) }
            }
            let descriptor = Darwin.openat(parent, leaf, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            if descriptor < 0 {
                if errno == ENOENT, !create { Darwin.close(parent); return nil }
                throw Failure.unsafeDirectory
            }
            do {
                if created, Darwin.fchmod(descriptor, 0o700) != 0 { throw Failure.io(errno) }
                try validatePrivateDirectory(descriptor)
                let opened = OpenedDirectory(parentDescriptor: parent, descriptor: descriptor, name: leaf)
                try validateDirectoryEntry(opened)
                if created { try syncDirectory(parent) }
                return opened
            } catch { Darwin.close(descriptor); throw error }
        } catch { Darwin.close(parent); throw error }
    }

    private func revalidateDirectory(_ expected: OpenedDirectory) throws {
        try validatePrivateDirectory(expected.descriptor)
        try validateDirectoryEntry(expected)
        guard let reopened = try openDirectory(create: false) else { throw Failure.unsafeDirectory }
        defer { reopened.close() }
        guard try nodeIdentity(reopened.descriptor) == nodeIdentity(expected.descriptor),
              try nodeIdentity(reopened.parentDescriptor) == nodeIdentity(expected.parentDescriptor) else {
            throw Failure.unsafeDirectory
        }
    }

    private func validateDirectoryEntry(_ opened: OpenedDirectory) throws {
        var named = stat()
        guard Darwin.fstatat(opened.parentDescriptor, opened.name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              Self.isSafeDirectoryMetadata(named, expectedOwner: Darwin.geteuid()),
              try NodeIdentity(named) == nodeIdentity(opened.descriptor) else {
            throw Failure.unsafeDirectory
        }
    }

    private func validateAncestor(_ descriptor: Int32) throws {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0,
              value.st_mode & S_IFMT == S_IFDIR, value.st_nlink >= 1,
              value.st_uid == Darwin.geteuid() || value.st_uid == 0,
              value.st_mode & 0o022 == 0 || (value.st_uid == 0 && value.st_mode & S_ISVTX != 0) else {
            throw Failure.unsafeDirectory
        }
        try rejectAllowACL(descriptor)
    }

    private func validatePrivateDirectory(_ descriptor: Int32) throws {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0,
              Self.isSafeDirectoryMetadata(value, expectedOwner: Darwin.geteuid()) else {
            throw Failure.unsafeDirectory
        }
        try rejectAllowACL(descriptor)
    }

    /// Pure metadata guards also let tests cover foreign UID without privileged chown.
    static func isSafeDirectoryMetadata(_ value: stat, expectedOwner: uid_t) -> Bool {
        value.st_mode & S_IFMT == S_IFDIR && value.st_uid == expectedOwner &&
            value.st_mode & 0o7777 == 0o700 && value.st_nlink >= 1
    }

    static func isSafeFileMetadata(_ value: stat, expectedOwner: uid_t) -> Bool {
        value.st_mode & S_IFMT == S_IFREG && value.st_uid == expectedOwner &&
            value.st_mode & 0o7777 == 0o600 && value.st_nlink == 1 &&
            value.st_size > 0 && value.st_size <= BelugaUpdateOperation.maximumRecordBytes
    }

    private func rejectAllowACL(_ descriptor: Int32) throws {
        do { try BelugaDescriptorACL.rejectAllowACL(descriptor) }
        catch { throw Failure.unsafeDirectory }
    }

    private func nodeIdentity(_ descriptor: Int32) throws -> NodeIdentity {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0 else { throw Failure.io(errno) }
        return NodeIdentity(value)
    }

    private func fileFingerprint(_ descriptor: Int32) throws -> FileFingerprint {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0,
              Self.isSafeFileMetadata(value, expectedOwner: Darwin.geteuid()) else {
            throw Failure.unsafeFile
        }
        return FileFingerprint(value)
    }

    fileprivate struct NodeIdentity: Equatable, Sendable {
        let device: Int64
        let inode: UInt64
        init(_ value: stat) { device = Int64(value.st_dev); inode = UInt64(value.st_ino) }
    }

    fileprivate struct FileFingerprint: Equatable, Sendable {
        let node: NodeIdentity
        let mode: UInt32
        let owner: UInt32
        let links: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
        init(_ value: stat) {
            node = NodeIdentity(value)
            mode = UInt32(value.st_mode)
            owner = UInt32(value.st_uid)
            links = UInt64(value.st_nlink)
            size = Int64(value.st_size)
            modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
            changedSeconds = Int64(value.st_ctimespec.tv_sec)
            changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
        }
    }

    private struct OpenedDirectory {
        let parentDescriptor: Int32
        let descriptor: Int32
        let name: String
        func close() { Darwin.close(descriptor); Darwin.close(parentDescriptor) }
    }

    private struct Temporary {
        let name: String
        let descriptor: Int32
        let file: FileFingerprint
    }

    private final class Serialization: @unchecked Sendable { let lock = NSLock() }
}
