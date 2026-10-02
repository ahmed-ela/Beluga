import Darwin
import Foundation

/// One owned, serialized, bounded local stream. Call from a dedicated worker, not
/// the main/UI actor. No listener, process launch, native update, or fence mutation
/// occurs here. Every message authenticates the same kernel peer before and after I/O.
/// Deadlines bound socket waits; synchronous offline Security calls are not cancellable.
package final class BelugaUpdateIPCChannel: @unchecked Sendable {
    package enum Failure: Error, Equatable {
        case invalidSocket, invalidTimeout, closed, timeout, eof, invalidLength, io(Int32), unsafeFixture
        case unexpectedPeerRole, busy
    }

    private let lock = NSLock()
    private let cancellationLock = NSLock()
    private var cancellationRequested = false
    private var descriptor: Int32
    private var transcript: BelugaUpdateIPCProtocol.Transcript
    private let authenticate: () throws -> Void
    private let peer: BelugaUpdatePeerIdentity.Peer?
    private var initialMessage: BelugaUpdateIPCProtocol.Message?

    // Written only during construction/bootstrap, before publication to any worker.
    // Do not read the mutable transcript concurrently with send/receive.
    package private(set) var binding: BelugaUpdateIPCProtocol.Binding

    /// Ownership transfers even if construction throws. The caller must not close,
    /// alias, or use this descriptor after calling this initializer.
    package convenience init(takingOwnedSocket descriptor: Int32,
                             binding: BelugaUpdateIPCProtocol.Binding,
                             localRole: BelugaUpdateIPCProtocol.Sender,
                             expectedPeer: BelugaUpdatePeerIdentity.Expectation) throws {
        do {
            guard (localRole == .menu && expectedPeer.role == .broker) ||
                    (localRole == .broker && expectedPeer.role == .main) else {
                throw Failure.unexpectedPeerRole
            }
            try Self.configure(descriptor)
            let peer = try BelugaUpdatePeerIdentity.authenticate(connectedSocket: descriptor,
                                                                 expectation: expectedPeer)
            self.init(configuredSocket: descriptor, binding: binding, localRole: localRole,
                      peer: peer,
                      authenticate: { try peer.revalidate(connectedSocket: descriptor) })
        } catch {
            if descriptor >= 0 { Darwin.close(descriptor) }
            throw error
        }
    }

    private init(configuredSocket: Int32, binding: BelugaUpdateIPCProtocol.Binding,
                 localRole: BelugaUpdateIPCProtocol.Sender,
                 peer: BelugaUpdatePeerIdentity.Peer? = nil,
                 authenticate: @escaping () throws -> Void) {
        descriptor = configuredSocket
        self.binding = binding
        transcript = .init(binding: binding, localRole: localRole)
        self.peer = peer
        self.authenticate = authenticate
    }

    /// Broker-side bootstrap. Authentication precedes the first byte read. The
    /// caller's exact operation/target are never learned from the incoming frame.
    /// Ownership transfers on both success and failure, as with the initializer.
    package static func acceptingOwnedSocket(
        _ descriptor: Int32, operationID: UUID, target: BelugaUpdateOperation.Target,
        expectedPeer: BelugaUpdatePeerIdentity.Expectation, timeout: TimeInterval = 5
    ) throws -> BelugaUpdateIPCChannel {
        var ownedByChannel = false
        do {
            guard expectedPeer.role == .main else { throw Failure.unexpectedPeerRole }
            try configure(descriptor)
            let peer = try BelugaUpdatePeerIdentity.authenticate(connectedSocket: descriptor,
                                                                 expectation: expectedPeer)
            // This local temporary transcript cannot accept a message. It exists
            // only to reuse the channel's bounded, authenticated framing reader.
            let provisional = try BelugaUpdateIPCProtocol.Binding(
                operationID: operationID, target: target, channelNonce: UUID())
            let channel = BelugaUpdateIPCChannel(configuredSocket: descriptor,
                binding: provisional, localRole: .broker, peer: peer,
                authenticate: { try peer.revalidate(connectedSocket: descriptor) })
            ownedByChannel = true
            try channel.acceptInitial(operationID: operationID, target: target, timeout: timeout)
            return channel
        } catch {
            if !ownedByChannel, descriptor >= 0 { Darwin.close(descriptor) }
            throw error
        }
    }

    private func acceptInitial(operationID: UUID, target: BelugaUpdateOperation.Target,
                               timeout: TimeInterval) throws {
        try perform(timeout: timeout) { deadline in
            let payload = try readFrame(until: deadline)
            let binding = try BelugaUpdateIPCProtocol.initialBinding(payload,
                operationID: operationID, target: target)
            transcript = .init(binding: binding, localRole: .broker)
            self.binding = binding
            initialMessage = try transcript.decode(payload)
        }
    }

    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

    package func send(_ message: BelugaUpdateIPCProtocol.Message, timeout: TimeInterval = 5) throws {
        try perform(timeout: timeout) { deadline in
            let payload = try transcript.encode(message)
            var length = UInt32(payload.count).bigEndian
            let header = withUnsafeBytes(of: &length) { Data($0) }
            try write(header, until: deadline)
            try write(payload, until: deadline)
        }
    }

    package func receive(timeout: TimeInterval = 5) throws -> BelugaUpdateIPCProtocol.Message {
        try perform(timeout: timeout) { deadline in
            if let message = initialMessage {
                initialMessage = nil
                return message
            }
            return try transcript.decode(readFrame(until: deadline))
        }
    }

    private func readFrame(until deadline: UInt64) throws -> Data {
        let header = try read(count: 4, until: deadline)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= BelugaUpdateIPCProtocol.maximumFrameBytes else {
            throw Failure.invalidLength
        }
        return try read(count: Int(length), until: deadline)
    }

    /// Requests cancellation without blocking behind an active call. The caller
    /// must drain its worker before claiming teardown; this is not a join barrier.
    package func close() {
        requestCancellation()
        // Never wait behind a read. The active owner notices cancellation between
        // bounded poll slices and is the only thread allowed to close/recycle its fd.
        guard lock.try() else { return }
        defer { lock.unlock() }
        closeLocked()
    }

    /// Fresh native identity for binding a menu UUID to a real process incarnation.
    /// Fixture channels cannot manufacture this authority.
    package func authenticatedPeer() throws -> BelugaUpdatePeerIdentity.Peer {
        guard lock.try() else { throw Failure.busy }
        defer { lock.unlock() }
        do {
            try requireOpen()
            guard let peer else { throw Failure.invalidSocket }
            try peer.revalidate(connectedSocket: descriptor)
            try requireOpen()
            return peer
        } catch { closeLocked(); throw error }
    }

    /// Terminal transport drain only, after clearance and an authenticated receipt.
    /// The peer closes only after its ack send/post-authentication returns. Waiting
    /// for EOF avoids exiting during that check (an endless ack-of-ack would not).
    /// EOF is NOT installation, readiness, cancellation, or fence-clear authority.
    package func waitForPeerClosure(timeout: TimeInterval = 5) throws {
        guard lock.try() else { throw Failure.busy }
        defer { closeLocked(); lock.unlock() }
        try requireOpen()
        guard timeout.isFinite, timeout > 0, timeout <= 30 else { throw Failure.invalidTimeout }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        try authenticate()
        do {
            _ = try read(count: 1, until: deadline)
            throw Failure.invalidLength
        } catch Failure.eof {
            // There can be no useful native peer revalidation after expected exit.
            return
        }
    }

    private func closeLocked() {
        requestCancellation()
        transcript.retire()
        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    private func perform<T>(timeout: TimeInterval, body: (UInt64) throws -> T) throws -> T {
        // No unbounded queueing time is hidden outside the I/O deadline. A competing
        // call is refused rather than blocking behind another reader or an auth call.
        guard lock.try() else { throw Failure.busy }
        defer { lock.unlock() }
        do {
            try requireOpen()
            guard timeout.isFinite, timeout > 0, timeout <= 30 else { throw Failure.invalidTimeout }
            let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
            try authenticate()
            try requireOpen()
            let result = try body(deadline)
            try authenticate()
            try requireOpen()
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw Failure.timeout }
            return result
        } catch { closeLocked(); throw error }
    }

    private func wait(_ event: Int16, until deadline: UInt64) throws {
        while true {
            try requireOpen()
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw Failure.timeout }
            let milliseconds = Int32(min((deadline - now + 999_999) / 1_000_000, 50))
            var value = pollfd(fd: descriptor, events: event, revents: 0)
            let result = Darwin.poll(&value, 1, milliseconds)
            if result < 0 {
                if errno == EINTR { continue }
                throw Failure.io(errno)
            }
            if result == 0 { continue }
            guard value.revents & Int16(POLLNVAL) == 0 else { throw Failure.invalidSocket }
            // POLLHUP may accompany the final readable frame. Let recv consume it;
            // an early peer close is EOF, never a zero-filled or partial message.
            if value.revents & (event | Int16(POLLHUP) | Int16(POLLERR)) != 0 {
                try requireOpen()
                return
            }
        }
    }

    private func requestCancellation() {
        cancellationLock.lock()
        cancellationRequested = true
        cancellationLock.unlock()
    }

    private func requireOpen() throws {
        cancellationLock.lock()
        let cancelled = cancellationRequested
        cancellationLock.unlock()
        guard descriptor >= 0, !cancelled else { throw Failure.closed }
    }

    private func read(count: Int, until deadline: UInt64) throws -> Data {
        var value = Data(count: count)
        try value.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                try wait(Int16(POLLIN), until: deadline)
                let received = Darwin.recv(descriptor, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                if received < 0 {
                    if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                    throw Failure.io(errno)
                }
                guard received > 0 else { throw Failure.eof }
                offset += received
            }
        }
        return value
    }

    private func write(_ value: Data, until deadline: UInt64) throws {
        try value.withUnsafeBytes { bytes in
            var offset = 0
            while offset < value.count {
                try wait(Int16(POLLOUT), until: deadline)
                let sent = Darwin.send(descriptor, bytes.baseAddress!.advanced(by: offset), value.count - offset, 0)
                if sent < 0 {
                    if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                    throw Failure.io(errno)
                }
                guard sent > 0 else { throw Failure.eof }
                offset += sent
            }
        }
    }

    private static func configure(_ descriptor: Int32) throws {
        guard descriptor >= 0 else { throw Failure.invalidSocket }
        var address = sockaddr_un()
        var addressSize = socklen_t(MemoryLayout<sockaddr_un>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &addressSize)
            }
        }
        var type: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard named == 0, address.sun_family == AF_UNIX,
              Darwin.getsockopt(descriptor, SOL_SOCKET, SO_TYPE, &type, &size) == 0,
              size == MemoryLayout<Int32>.size, type == SOCK_STREAM else { throw Failure.invalidSocket }
        var enabled: Int32 = 1
        let flags = Darwin.fcntl(descriptor, F_GETFL)
        let fdFlags = Darwin.fcntl(descriptor, F_GETFD)
        guard flags >= 0, fdFlags >= 0,
              Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0,
              Darwin.fcntl(descriptor, F_SETFD, fdFlags | FD_CLOEXEC) == 0,
              Darwin.setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled,
                                socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw Failure.io(errno) }
    }

    /// Native I/O fixture only, never a production authentication override. The
    /// caller supplies a dedicated private namespace and a local connected socket.
    static func fixture(takingOwnedSocket descriptor: Int32, root: URL,
                        binding: BelugaUpdateIPCProtocol.Binding,
                        localRole: BelugaUpdateIPCProtocol.Sender,
                        authenticate: @escaping () throws -> Void = {}) throws -> BelugaUpdateIPCChannel {
        do {
            let prefix = "beluga-ipc-channel-fixture-"
            let name = root.lastPathComponent
            guard root.isFileURL, root.deletingLastPathComponent().path == "/private/tmp",
                  name.hasPrefix(prefix), let uuid = UUID(uuidString: String(name.dropFirst(prefix.count))),
                  name == prefix + uuid.uuidString else { throw Failure.unsafeFixture }
            var metadata = stat()
            guard Darwin.lstat(root.path, &metadata) == 0, metadata.st_uid == Darwin.geteuid(),
                  metadata.st_mode & S_IFMT == S_IFDIR, metadata.st_mode & 0o7777 == 0o700 else {
                throw Failure.unsafeFixture
            }
            let directory = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directory >= 0 else { throw Failure.unsafeFixture }
            defer { Darwin.close(directory) }
            var held = stat()
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let canonical = buffer.withUnsafeMutableBufferPointer { bytes -> String? in
                guard let base = bytes.baseAddress, Darwin.fcntl(directory, F_GETPATH, base) == 0 else { return nil }
                return String(validatingCString: base)
            }
            guard Darwin.fstat(directory, &held) == 0,
                  held.st_dev == metadata.st_dev, held.st_ino == metadata.st_ino,
                  held.st_mode == metadata.st_mode, held.st_uid == metadata.st_uid,
                  canonical == root.path else { throw Failure.unsafeFixture }
            try BelugaDescriptorACL.rejectAllowACL(directory)
            try configure(descriptor)
            return .init(configuredSocket: descriptor, binding: binding, localRole: localRole,
                         authenticate: authenticate)
        } catch {
            if descriptor >= 0 { Darwin.close(descriptor) }
            throw error
        }
    }

    static func acceptingFixtureSocket(_ descriptor: Int32, root: URL,
                                       operationID: UUID, target: BelugaUpdateOperation.Target,
                                       timeout: TimeInterval = 5,
                                       authenticate: @escaping () throws -> Void = {}) throws -> BelugaUpdateIPCChannel {
        let binding: BelugaUpdateIPCProtocol.Binding
        do { binding = try .init(operationID: operationID, target: target, channelNonce: UUID()) }
        catch { if descriptor >= 0 { Darwin.close(descriptor) }; throw error }
        let channel = try fixture(takingOwnedSocket: descriptor, root: root, binding: binding,
                                  localRole: .broker, authenticate: authenticate)
        try channel.acceptInitial(operationID: operationID, target: target, timeout: timeout)
        return channel
    }
}
