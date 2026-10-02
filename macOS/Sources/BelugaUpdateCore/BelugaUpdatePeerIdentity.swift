import Darwin
import Darwin.bsm.libbsm
import Darwin.libproc
import Foundation
import Security

/// Kernel-bound, local peer observations, not an operation/readiness assertion.
/// Expectations come only from trusted verified composition, never from wire claims.
/// The channel owner retains its connected descriptor and must revalidate at each
/// authority-bearing message; this value does not own/close a socket or remain valid
/// after process exit/exec, descriptor replacement, or a later code-validity change.
package enum BelugaUpdatePeerIdentity {
    package enum Role: String, Equatable, Sendable {
        case main, broker

        var bundleIdentifier: String {
            switch self {
            case .main: return BelugaUpdateOperation.expectedBundleIdentifier
            case .broker: return "com.elamin.beluga.Updater"
            }
        }

        var executable: String { self == .main ? "CaptureServer" : "BelugaUpdater" }
    }

    package struct Expectation: Equatable, Sendable {
        package let role: Role
        package let canonicalExecutablePath: String
        package let effectiveUID: UInt32
        package let nativeCDHash: Data

        /// The canonical path and native architecture's CDHash must already have
        /// been obtained from trusted installed-artifact/staged-broker validation.
        /// This initializer validates shape; it does not supply that prior authority.
        package init(role: Role, canonicalExecutablePath: String, effectiveUID: UInt32,
                     nativeCDHash: Data) throws {
            let parts = canonicalExecutablePath.split(separator: "/", omittingEmptySubsequences: false)
            guard canonicalExecutablePath.utf8.count < Int(MAXPATHLEN), parts.count >= 5,
                  parts.first == "", parts.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  canonicalExecutablePath.utf8.allSatisfy({ $0 >= 32 && $0 != 127 }),
                  canonicalExecutablePath.hasSuffix(".app/Contents/MacOS/" + role.executable),
                  nativeCDHash.count == 20, nativeCDHash.contains(where: { $0 != 0 }) else {
                throw Failure.invalidExpectation
            }
            self.role = role
            self.canonicalExecutablePath = canonicalExecutablePath
            self.effectiveUID = effectiveUID
            self.nativeCDHash = nativeCDHash
        }

        // Only fixed role/team text and exact lowercase hex are inserted into syntax.
        var requirementSource: String {
            let hex = nativeCDHash.map { String(format: "%02x", $0) }.joined()
            return "anchor apple generic and identifier \"\(role.bundleIdentifier)\" and certificate leaf[subject.OU] = \"MSMG8CJLB3\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and cdhash H\"\(hex)\""
        }
    }

    package struct Peer: Equatable, Sendable {
        package var processIdentifier: Int32 { observation.token.processIdentifier }
        package var processVersion: Int32 { observation.token.processVersion }
        private let descriptor: Int32
        private let expectation: Expectation
        private let observation: Observation

        fileprivate init(descriptor: Int32, expectation: Expectation, observation: Observation) {
            self.descriptor = descriptor
            self.expectation = expectation
            self.observation = observation
        }

        package func revalidate(connectedSocket: Int32) throws {
            try revalidateBound(connectedSocket: connectedSocket, inputs: .live)
        }

        private func revalidateBound(connectedSocket: Int32, inputs: Inputs) throws {
            guard connectedSocket == descriptor else { throw Failure.changedPeer }
            let current = try BelugaUpdatePeerIdentity.authenticateBound(
                connectedSocket: connectedSocket, expectation: expectation, inputs: inputs)
            guard current.observation == observation else { throw Failure.changedPeer }
        }

        // Internal source-only seam; authenticateFixture applied the same namespace guard.
        func revalidateFixture(connectedSocket: Int32, inputs: Inputs) throws {
            try BelugaUpdatePeerIdentity.withOwnedFixture(expectation: expectation) {
                try revalidateBound(connectedSocket: connectedSocket, inputs: inputs)
            }
        }
    }

    package enum Failure: Error, Equatable {
        case invalidExpectation, invalidSocket, invalidToken, wrongUser
        case unexpectedExecutable, changedPeer, unsafeFixture
        case kernel(Int32), signature(OSStatus)
    }

    package static func authenticate(connectedSocket: Int32, expectation: Expectation) throws -> Peer {
        try authenticateBound(connectedSocket: connectedSocket, expectation: expectation, inputs: .live)
    }

    // The native token is opaque. Only public BSM routines decode its credentials;
    // tests supply synthetic observations, not a fabricated token to native Security.
    struct Token: Equatable, Sendable {
        var bytes: Data
        var effectiveUID: UInt32
        var processIdentifier: Int32
        var processVersion: Int32
    }

    struct SocketIdentity: Equatable, Sendable {
        var device: Int64
        var inode: UInt64
    }

    struct Observation: Equatable, Sendable {
        var socket: SocketIdentity
        var token: Token
    }

    struct Inputs {
        var readKernelPeer: (Int32) throws -> Observation
        var executablePath: (Token) throws -> String
        var validateDynamicCode: (Token, Expectation) throws -> Void

        static var live: Self {
            .init(readKernelPeer: kernelPeer, executablePath: nativeExecutablePath,
                  validateDynamicCode: nativeDynamicValidation)
        }
    }

    static func authenticateFixture(connectedSocket: Int32, expectation: Expectation,
                                    inputs: Inputs) throws -> Peer {
        try withOwnedFixture(expectation: expectation) {
            try authenticateBound(connectedSocket: connectedSocket, expectation: expectation, inputs: inputs)
        }
    }

    private static func authenticateBound(connectedSocket: Int32, expectation: Expectation,
                                          inputs: Inputs) throws -> Peer {
        guard connectedSocket >= 0 else { throw Failure.invalidSocket }
        guard expectation.effectiveUID == Darwin.geteuid() else { throw Failure.wrongUser }
        let before = try inputs.readKernelPeer(connectedSocket)
        try validateToken(before.token, expectation: expectation)
        guard try inputs.executablePath(before.token) == expectation.canonicalExecutablePath else {
            throw Failure.unexpectedExecutable
        }
        try inputs.validateDynamicCode(before.token, expectation)
        let after = try inputs.readKernelPeer(connectedSocket)
        guard before == after else { throw Failure.changedPeer }
        try validateToken(after.token, expectation: expectation)
        guard try inputs.executablePath(after.token) == expectation.canonicalExecutablePath else {
            throw Failure.unexpectedExecutable
        }
        return Peer(descriptor: connectedSocket, expectation: expectation, observation: after)
    }

    private static func validateToken(_ token: Token, expectation: Expectation) throws {
        guard token.bytes.count == MemoryLayout<audit_token_t>.size,
              token.processIdentifier > 0 else { throw Failure.invalidToken }
        guard token.effectiveUID == expectation.effectiveUID else { throw Failure.wrongUser }
    }

    private static func kernelPeer(_ descriptor: Int32) throws -> Observation {
        let before = try socketIdentity(descriptor)
        var type: Int32 = 0
        var typeSize = socklen_t(MemoryLayout<Int32>.size)
        guard Darwin.getsockopt(descriptor, SOL_SOCKET, SO_TYPE, &type, &typeSize) == 0 else {
            throw Failure.kernel(errno)
        }
        guard typeSize == MemoryLayout<Int32>.size, type == SOCK_STREAM else { throw Failure.invalidSocket }
        try requireUnixAddress(descriptor, peer: false)
        try requireUnixAddress(descriptor, peer: true) // An unconnected listener cannot authenticate.
        var token = audit_token_t()
        var size = socklen_t(MemoryLayout<audit_token_t>.size)
        guard Darwin.getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) == 0 else {
            throw Failure.kernel(errno)
        }
        guard size == MemoryLayout<audit_token_t>.size else { throw Failure.invalidToken }
        let value = Token(bytes: withUnsafeBytes(of: token) { Data($0) },
                          effectiveUID: audit_token_to_euid(token),
                          processIdentifier: audit_token_to_pid(token),
                          processVersion: audit_token_to_pidversion(token))
        guard try socketIdentity(descriptor) == before else { throw Failure.changedPeer }
        return Observation(socket: before, token: value)
    }

    private static func socketIdentity(_ descriptor: Int32) throws -> SocketIdentity {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0 else { throw Failure.kernel(errno) }
        guard value.st_mode & S_IFMT == S_IFSOCK else { throw Failure.invalidSocket }
        return SocketIdentity(device: Int64(value.st_dev), inode: UInt64(value.st_ino))
    }

    private static func requireUnixAddress(_ descriptor: Int32, peer: Bool) throws {
        var address = sockaddr_storage()
        var size = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let status = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                peer ? Darwin.getpeername(descriptor, raw, &size) : Darwin.getsockname(descriptor, raw, &size)
            }
        }
        guard status == 0 else { throw Failure.kernel(errno) }
        guard size >= MemoryLayout<sa_family_t>.size + 1,
              size <= MemoryLayout<sockaddr_storage>.size, address.ss_family == AF_UNIX else {
            throw Failure.invalidSocket
        }
    }

    private static func decodedToken(_ value: Token) throws -> audit_token_t {
        guard value.bytes.count == MemoryLayout<audit_token_t>.size else { throw Failure.invalidToken }
        return value.bytes.withUnsafeBytes { $0.loadUnaligned(as: audit_token_t.self) }
    }

    private static func nativeExecutablePath(_ value: Token) throws -> String {
        var token = try decodedToken(value)
        // sys/proc_info.h defines PROC_PIDPATHINFO_MAXSIZE as (4 * MAXPATHLEN),
        // but Swift cannot import that compound C macro from the pinned SDK.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = buffer.withUnsafeMutableBytes { bytes in
            proc_pidpath_audittoken(&token, bytes.baseAddress, UInt32(bytes.count))
        }
        guard count > 0 else { throw Failure.kernel(errno) }
        guard count < buffer.count, let nul = buffer.firstIndex(of: 0), nul > 0,
              let path = String(bytes: buffer.prefix(nul).map { UInt8(bitPattern: $0) }, encoding: .utf8),
              path.hasPrefix("/"), path.utf8.count < Int(MAXPATHLEN),
              path.utf8.allSatisfy({ $0 >= 32 && $0 != 127 }) else { throw Failure.unexpectedExecutable }
        return path
    }

    private static func nativeDynamicValidation(_ token: Token, _ expectation: Expectation) throws {
        // No PID lookup or filesystem-only SecStaticCode substitution. The full
        // kernel token selects the exact running process generation.
        let attributes = [kSecGuestAttributeAudit as String: token.bytes as CFData] as CFDictionary
        var code: SecCode?
        let lookup = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard lookup == errSecSuccess, let code else { throw Failure.signature(lookup) }
        var requirement: SecRequirement?
        let compilation = SecRequirementCreateWithString(expectation.requirementSource as CFString,
                                                        [], &requirement)
        guard compilation == errSecSuccess, let requirement else { throw Failure.signature(compilation) }
        // Public kernel matching binds the requirement to running code, not a
        // possibly replaced static origin. Refusal has no weaker fallback.
        let flags: SecCSFlags = [.noNetworkAccess, .matchGuestRequirementInKernel]
        let validation = SecCodeCheckValidity(code, flags, requirement)
        guard validation == errSecSuccess else { throw Failure.signature(validation) }
    }

    private static func withOwnedFixture<T>(expectation: Expectation, _ body: () throws -> T) throws -> T {
        let executable = URL(fileURLWithPath: expectation.canonicalExecutablePath)
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = app.deletingLastPathComponent()
        let prefix = "beluga-peer-identity-fixture-"
        guard root.deletingLastPathComponent().path == "/private/tmp", root.lastPathComponent.hasPrefix(prefix),
              let uuid = UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))),
              root.lastPathComponent == prefix + uuid.uuidString else { throw Failure.unsafeFixture }
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure.unsafeFixture }
        defer { Darwin.close(descriptor) }
        var original = stat()
        guard Darwin.fstat(descriptor, &original) == 0, original.st_mode & S_IFMT == S_IFDIR,
              original.st_mode & 0o777 == 0o700, original.st_uid == Darwin.geteuid() else {
            throw Failure.unsafeFixture
        }
        func revalidate() throws {
            var held = stat(); var named = stat()
            guard Darwin.fstat(descriptor, &held) == 0, Darwin.lstat(root.path, &named) == 0,
                  held.st_dev == original.st_dev, held.st_ino == original.st_ino,
                  named.st_dev == original.st_dev, named.st_ino == original.st_ino,
                  held.st_mode == original.st_mode, named.st_mode == original.st_mode,
                  held.st_uid == original.st_uid, named.st_uid == original.st_uid else {
                throw Failure.unsafeFixture
            }
        }
        try revalidate()
        do { let result = try body(); try revalidate(); return result }
        catch { let originalError = error; try revalidate(); throw originalError }
    }
}
