import Darwin
import Foundation

/// Private local transport only. Returned descriptors are owned by the caller;
/// they are not authenticated peers until IPCChannel verifies native identity.
/// Disposal closes descriptors but never unlinks/reuses retained endpoint evidence.
package enum BelugaUpdateIPCEndpoint {
    package enum Purpose: String, Sendable {
        case control, readiness
        fileprivate var filename: String { rawValue + ".sock" }
    }
    package enum Failure: Error, Equatable {
        case invalidOperation, wrongUser, pathTooLong, unsafeFixture
        case unsafeDirectory, directoryChanged, unsafeSocket, socketChanged, collision
        case invalidTimeout, closed, busy, timeout, io(Int32)
    }

    package static func create(operationID: UUID, effectiveUID: UInt32,
                               purpose: Purpose = .control) throws -> Listener {
        try create(locator: .production(operationID: operationID, effectiveUID: effectiveUID, purpose: purpose))
    }

    /// Noncreating namespace readback for staged broker inspection. This is a
    /// finite path/inode observation, not a retained lease or peer authentication.
    package static func directoryURL(operationID: UUID, effectiveUID: UInt32) throws -> URL {
        try directoryURL(locator: .production(operationID: operationID, effectiveUID: effectiveUID,
                                              purpose: .control))
    }

    /// Noncreating. Revalidates the existing namespace/socket around connect; the
    /// caller must then transfer this exact descriptor to IPCChannel with its
    /// independently verified PeerIdentity expectation.
    package static func connect(operationID: UUID, effectiveUID: UInt32,
                                purpose: Purpose = .control,
                                timeout: TimeInterval = 5) throws -> Int32 {
        try connect(locator: .production(operationID: operationID, effectiveUID: effectiveUID, purpose: purpose),
                    timeout: timeout)
    }

    package final class Listener: @unchecked Sendable {
        package let endpointURL: URL
        package let directoryURL: URL
        private let serialization = NSLock()
        private let cancellationLock = NSLock()
        private var cancelled = false
        private var descriptor: Int32
        private let namespace: Namespace

        fileprivate init(descriptor: Int32, namespace: Namespace) {
            self.descriptor = descriptor; self.namespace = namespace
            endpointURL = namespace.locator.endpointURL
            directoryURL = namespace.locator.namespaceURL
        }

        deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

        /// One owner only. A competing call fails immediately; any other failure
        /// retires this listener, preserving its directory and socket as evidence.
        package func accept(timeout: TimeInterval = 5) throws -> Int32 {
            guard serialization.try() else { throw Failure.busy }
            defer { serialization.unlock() }
            var accepted: Int32 = -1
            do {
                try requireOpen()
                let deadline = try BelugaUpdateIPCEndpoint.deadline(timeout)
                try namespace.revalidate()
                while accepted < 0 {
                    try wait(descriptor, event: Int16(POLLIN), deadline: deadline,
                             cancellation: { try self.requireOpen() })
                    accepted = Darwin.accept(descriptor, nil, nil)
                    if accepted < 0 {
                        if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                        throw Failure.io(errno)
                    }
                }
                try configure(accepted)
                try requireOpen(); try namespace.revalidate()
                try requireOpen()
                guard DispatchTime.now().uptimeNanoseconds < deadline else { throw Failure.timeout }
                return accepted
            } catch {
                if accepted >= 0 { Darwin.close(accepted) }
                closeLocked()
                throw error
            }
        }

        /// Non-joining cancellation. An active accept owns and closes its fd after
        /// noticing cancellation in bounded poll slices; no other thread recycles it.
        package func close() {
            requestCancellation()
            guard serialization.try() else { return }
            defer { serialization.unlock() }
            closeLocked()
        }

        private func requestCancellation() {
            cancellationLock.lock(); cancelled = true; cancellationLock.unlock()
        }

        private func requireOpen() throws {
            cancellationLock.lock(); let requested = cancelled; cancellationLock.unlock()
            guard descriptor >= 0, !requested else { throw Failure.closed }
        }

        private func closeLocked() {
            requestCancellation()
            if descriptor >= 0 {
                Darwin.shutdown(descriptor, SHUT_RDWR)
                Darwin.close(descriptor); descriptor = -1
            }
        }
    }

    fileprivate struct Locator {
        let parentURL: URL
        let namespaceName: String
        let effectiveUID: UInt32
        let fixture: Bool
        let purpose: Purpose
        var namespaceURL: URL { parentURL.appendingPathComponent(namespaceName, isDirectory: true) }
        var endpointURL: URL { namespaceURL.appendingPathComponent(purpose.filename) }

        static func production(operationID: UUID, effectiveUID: UInt32, purpose: Purpose) throws -> Self {
            try validate(operationID: operationID, effectiveUID: effectiveUID)
            let value = Self(parentURL: URL(fileURLWithPath: "/private/tmp", isDirectory: true),
                             namespaceName: "beluga-update-\(effectiveUID)-\(operationID.uuidString)",
                             effectiveUID: effectiveUID, fixture: false, purpose: purpose)
            _ = try address(value.endpointURL.path)
            return value
        }

        static func fixture(root: URL, operationID: UUID, purpose: Purpose) throws -> Self {
            try validate(operationID: operationID, effectiveUID: Darwin.geteuid())
            guard root.isFileURL, root.deletingLastPathComponent().path == "/private/tmp",
                  root.lastPathComponent == "beluga-update-endpoint-fixture-" + operationID.uuidString else {
                throw Failure.unsafeFixture
            }
            // The dedicated fixture root already binds the UUID. A short child
            // preserves the real Darwin 104-byte AF_UNIX path limit.
            let value = Self(parentURL: root, namespaceName: "e",
                             effectiveUID: Darwin.geteuid(), fixture: true, purpose: purpose)
            _ = try address(value.endpointURL.path)
            return value
        }

        private static func validate(operationID: UUID, effectiveUID: UInt32) throws {
            guard operationID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
                throw Failure.invalidOperation
            }
            guard effectiveUID == Darwin.geteuid() else { throw Failure.wrongUser }
        }
    }

    fileprivate final class Directory {
        private(set) var descriptor: Int32 = -1
        let path: String
        let identity: NodeIdentity
        let expectedOwner: UInt32
        let expectedMode: mode_t

        init(url: URL, owner: UInt32, mode: mode_t) throws {
            guard url.isFileURL, url.path.hasPrefix("/"), !url.path.hasSuffix("/"),
                  url.path.utf8.count < Int(MAXPATHLEN),
                  url.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
                    .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw Failure.unsafeDirectory
            }
            path = url.path; expectedOwner = owner; expectedMode = mode
            let opened = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard opened >= 0 else { throw Failure.io(errno) }
            do {
                let initial = try metadata(opened)
                guard initial.st_mode & S_IFMT == S_IFDIR, initial.st_uid == owner,
                      initial.st_mode & 0o7777 == mode else { throw Failure.unsafeDirectory }
                descriptor = opened; identity = NodeIdentity(initial)
                try revalidate()
            } catch { descriptor = -1; Darwin.close(opened); throw error }
        }

        deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

        func revalidate() throws {
            let held = try metadata(descriptor)
            var named = stat()
            guard Darwin.lstat(path, &named) == 0,
                  NodeIdentity(held) == identity, NodeIdentity(named) == identity,
                  held.st_mode & S_IFMT == S_IFDIR, held.st_uid == expectedOwner,
                  held.st_mode & 0o7777 == expectedMode else { throw Failure.directoryChanged }
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let resolved = buffer.withUnsafeMutableBufferPointer { bytes -> String? in
                guard let base = bytes.baseAddress, Darwin.fcntl(descriptor, F_GETPATH, base) == 0 else { return nil }
                return String(validatingCString: base)
            }
            guard resolved == path else { throw Failure.directoryChanged }
            do { try BelugaDescriptorACL.rejectAllowACL(descriptor) }
            catch { throw Failure.unsafeDirectory }
        }
    }

    fileprivate struct NodeIdentity: Equatable {
        let device: Int64
        let inode: UInt64
        let owner: UInt32
        let mode: mode_t
        init(_ value: stat) {
            device = Int64(value.st_dev); inode = UInt64(value.st_ino)
            owner = value.st_uid; mode = value.st_mode
        }
    }

    fileprivate struct Namespace {
        let locator: Locator
        let parent: Directory
        let directory: Directory
        let socketIdentity: NodeIdentity
        let controlIdentity: NodeIdentity?

        func revalidate() throws {
            try parent.revalidate(); try directory.revalidate()
            let current = try socketMetadata(directory.descriptor, name: locator.purpose.filename,
                                             effectiveUID: locator.effectiveUID)
            guard NodeIdentity(current) == socketIdentity else { throw Failure.socketChanged }
            if let controlIdentity {
                let control = try socketMetadata(directory.descriptor, name: Purpose.control.filename,
                                                 effectiveUID: locator.effectiveUID)
                guard NodeIdentity(control) == controlIdentity else { throw Failure.socketChanged }
            }
        }
    }

    private static func create(locator: Locator) throws -> Listener {
        let parent = try openParent(locator)
        if locator.purpose == .control {
            guard Darwin.mkdirat(parent.descriptor, locator.namespaceName, 0o700) == 0 else {
                if errno == EEXIST { throw Failure.collision }
                throw Failure.io(errno)
            }
        }
        // All failures retain this fresh namespace; they never authorize reuse.
        let directory = try Directory(url: locator.namespaceURL, owner: locator.effectiveUID, mode: 0o700)
        try parent.revalidate()
        let controlIdentity = locator.purpose == .readiness
            ? NodeIdentity(try socketMetadata(directory.descriptor, name: Purpose.control.filename,
                                             effectiveUID: locator.effectiveUID)) : nil
        var existing = stat()
        let present = Darwin.fstatat(directory.descriptor, locator.purpose.filename, &existing, AT_SYMLINK_NOFOLLOW)
        guard present < 0, errno == ENOENT else {
            if present == 0 { throw Failure.collision }
            throw Failure.io(errno)
        }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure.io(errno) }
        do {
            try configure(descriptor)
            var endpoint = try address(locator.endpointURL.path)
            let addressSize = socklen_t(endpoint.sun_len)
            let bound = withUnsafePointer(to: &endpoint) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, addressSize)
                }
            }
            guard bound == 0 else {
                if errno == EADDRINUSE { throw Failure.collision }
                throw Failure.io(errno)
            }
            var original = stat()
            guard Darwin.fstatat(directory.descriptor, locator.purpose.filename, &original, AT_SYMLINK_NOFOLLOW) == 0,
                  original.st_mode & S_IFMT == S_IFSOCK, original.st_uid == locator.effectiveUID,
                  original.st_nlink == 1 else { throw Failure.unsafeSocket }
            guard Darwin.fchmodat(directory.descriptor, locator.purpose.filename, 0o600, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw Failure.io(errno)
            }
            let sealed = try socketMetadata(directory.descriptor, name: locator.purpose.filename,
                                            effectiveUID: locator.effectiveUID)
            guard sealed.st_dev == original.st_dev, sealed.st_ino == original.st_ino else {
                throw Failure.socketChanged
            }
            guard Darwin.listen(descriptor, 4) == 0 else { throw Failure.io(errno) }
            let namespace = Namespace(locator: locator, parent: parent, directory: directory,
                                      socketIdentity: NodeIdentity(sealed), controlIdentity: controlIdentity)
            try namespace.revalidate()
            guard Darwin.fsync(directory.descriptor) == 0, Darwin.fsync(parent.descriptor) == 0 else {
                throw Failure.io(errno)
            }
            try namespace.revalidate()
            return Listener(descriptor: descriptor, namespace: namespace)
        } catch { Darwin.close(descriptor); throw error }
    }

    private static func connect(locator: Locator, timeout: TimeInterval) throws -> Int32 {
        let limit = try deadline(timeout)
        let parent = try openParent(locator)
        let directory = try Directory(url: locator.namespaceURL, owner: locator.effectiveUID, mode: 0o700)
        let initial = try socketMetadata(directory.descriptor, name: locator.purpose.filename,
                                         effectiveUID: locator.effectiveUID)
        let controlIdentity = locator.purpose == .readiness
            ? NodeIdentity(try socketMetadata(directory.descriptor, name: Purpose.control.filename,
                                             effectiveUID: locator.effectiveUID)) : nil
        let namespace = Namespace(locator: locator, parent: parent, directory: directory,
                                  socketIdentity: NodeIdentity(initial), controlIdentity: controlIdentity)
        try namespace.revalidate()
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure.io(errno) }
        do {
            try configure(descriptor)
            var endpoint = try address(locator.endpointURL.path)
            let addressSize = socklen_t(endpoint.sun_len)
            let connected = withUnsafePointer(to: &endpoint) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, addressSize)
                }
            }
            if connected < 0 {
                guard errno == EINPROGRESS || errno == EINTR else { throw Failure.io(errno) }
                try wait(descriptor, event: Int16(POLLOUT), deadline: limit)
                var failure: Int32 = 0
                var size = socklen_t(MemoryLayout<Int32>.size)
                guard Darwin.getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &failure, &size) == 0,
                      size == MemoryLayout<Int32>.size else { throw Failure.io(errno) }
                guard failure == 0 else { throw Failure.io(failure) }
            }
            try peerAddress(descriptor, expected: locator.endpointURL.path)
            try namespace.revalidate()
            guard DispatchTime.now().uptimeNanoseconds < limit else { throw Failure.timeout }
            return descriptor
        } catch { Darwin.close(descriptor); throw error }
    }

    private static func openParent(_ locator: Locator) throws -> Directory {
        try Directory(url: locator.parentURL, owner: locator.fixture ? locator.effectiveUID : 0,
                      mode: locator.fixture ? 0o700 : 0o1777)
    }

    private static func directoryURL(locator: Locator) throws -> URL {
        let parent = try openParent(locator)
        let directory = try Directory(url: locator.namespaceURL, owner: locator.effectiveUID, mode: 0o700)
        let control = try socketMetadata(directory.descriptor, name: Purpose.control.filename,
                                         effectiveUID: locator.effectiveUID)
        let namespace = Namespace(locator: locator, parent: parent, directory: directory,
                                  socketIdentity: NodeIdentity(control), controlIdentity: nil)
        try namespace.revalidate()
        return locator.namespaceURL
    }

    private static func socketMetadata(_ directory: Int32, name: String, effectiveUID: UInt32) throws -> stat {
        var value = stat()
        guard Darwin.fstatat(directory, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw Failure.io(errno)
        }
        guard value.st_mode & S_IFMT == S_IFSOCK, value.st_uid == effectiveUID,
              value.st_mode & 0o7777 == 0o600, value.st_nlink == 1 else { throw Failure.unsafeSocket }
        return value
    }

    private static func metadata(_ descriptor: Int32) throws -> stat {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0 else { throw Failure.io(errno) }
        return value
    }

    private static func address(_ path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        var value = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: value.sun_path)
        guard !bytes.isEmpty, bytes.count < capacity, !bytes.contains(0), capacity == 104,
              let offset = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path),
              offset + bytes.count + 1 <= Int(UInt8.max) else { throw Failure.pathTooLong }
        value.sun_family = sa_family_t(AF_UNIX)
        value.sun_len = UInt8(offset + bytes.count + 1)
        withUnsafeMutableBytes(of: &value.sun_path) { destination in
            _ = destination.initializeMemory(as: UInt8.self, repeating: 0)
            destination.copyBytes(from: bytes)
        }
        return value
    }

    private static func peerAddress(_ descriptor: Int32, expected: String) throws {
        var value = sockaddr_un()
        var size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafeMutablePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getpeername(descriptor, $0, &size)
            }
        }
        guard result == 0, value.sun_family == AF_UNIX else { throw Failure.unsafeSocket }
        let actual = withUnsafeBytes(of: value.sun_path) { bytes -> String? in
            guard let end = bytes.firstIndex(of: 0) else { return nil }
            return String(data: Data(bytes.prefix(end)), encoding: .utf8)
        }
        guard actual == expected else { throw Failure.socketChanged }
    }

    private static func configure(_ descriptor: Int32) throws {
        let flags = Darwin.fcntl(descriptor, F_GETFL), fdFlags = Darwin.fcntl(descriptor, F_GETFD)
        var enabled: Int32 = 1
        guard flags >= 0, fdFlags >= 0,
              Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0,
              Darwin.fcntl(descriptor, F_SETFD, fdFlags | FD_CLOEXEC) == 0,
              Darwin.setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled,
                                socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw Failure.io(errno) }
    }

    private static func deadline(_ timeout: TimeInterval) throws -> UInt64 {
        guard timeout.isFinite, timeout > 0, timeout <= 30 else { throw Failure.invalidTimeout }
        let (result, overflow) = DispatchTime.now().uptimeNanoseconds
            .addingReportingOverflow(UInt64(timeout * 1_000_000_000))
        guard !overflow else { throw Failure.invalidTimeout }
        return result
    }

    private static func wait(_ descriptor: Int32, event: Int16, deadline: UInt64,
                             cancellation: () throws -> Void = {}) throws {
        while true {
            try cancellation()
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw Failure.timeout }
            var value = pollfd(fd: descriptor, events: event, revents: 0)
            let milliseconds = Int32(min((deadline - now + 999_999) / 1_000_000, 50))
            let ready = Darwin.poll(&value, 1, milliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                throw Failure.io(errno)
            }
            if ready == 0 { continue }
            guard value.revents & Int16(POLLNVAL) == 0 else { throw Failure.closed }
            if value.revents & (event | Int16(POLLHUP) | Int16(POLLERR)) != 0 { return }
        }
    }

    // Internal source-only path seam. It is never a native authentication override
    // and refuses every parent except a fresh, exact private fixture namespace.
    static func createFixture(root: URL, operationID: UUID, purpose: Purpose = .control) throws -> Listener {
        try create(locator: .fixture(root: root, operationID: operationID, purpose: purpose))
    }

    static func connectFixture(root: URL, operationID: UUID, purpose: Purpose = .control,
                               timeout: TimeInterval = 5) throws -> Int32 {
        try connect(locator: .fixture(root: root, operationID: operationID, purpose: purpose), timeout: timeout)
    }

    static func directoryFixture(root: URL, operationID: UUID) throws -> URL {
        try directoryURL(locator: .fixture(root: root, operationID: operationID, purpose: .control))
    }
}
