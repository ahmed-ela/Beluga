import CryptoKit
import Darwin
import Foundation

/// Target scope only: signature, writable-install and installer admission proofs belong to
/// the broker. Resolution neither creates a fence directory nor reads an operation record.
package struct BelugaUpdateRuntimeContext: Equatable, Sendable {
    package let target: BelugaUpdateOperation.Target
    package let fenceDirectoryURL: URL
    private let targetDirectoryIdentity: DirectoryIdentity
    private let homeDirectoryURL: URL
    private let homeDirectoryIdentity: DirectoryIdentity

    enum ResolutionError: Error, Equatable {
        case invalidBundle, invalidAccountHome, unavailableAccountHome
        case unavailableDirectory, directoryIdentityChanged, effectiveUIDChanged
    }

    /// Internal, source-only test seam; production accepts no environment/path overrides.
    struct ResolverInputs {
        let effectiveUID: UInt32
        let accountHomeDirectory: (UInt32) throws -> URL
        var afterTargetOpenForTesting: (() throws -> Void)? = nil

        static var live: Self {
            Self(effectiveUID: Darwin.geteuid(),
                 accountHomeDirectory: BelugaUpdateRuntimeContext.accountHome(for:))
        }
    }

    package static func resolve(bundle: Bundle = .main) throws -> Self? {
        try resolve(bundleIdentifier: bundle.bundleIdentifier, bundleURL: bundle.bundleURL,
                    inputs: .live)
    }

    static func resolve(bundleIdentifier: String?, bundleURL: URL,
                        inputs: ResolverInputs) throws -> Self? {
        guard bundleIdentifier == BelugaUpdateOperation.expectedBundleIdentifier else { return nil }
        guard bundleURL.isFileURL, isAbsolutePath(bundleURL.path) else {
            throw ResolutionError.invalidBundle
        }
        let app = try resolveDirectory(bundleURL, afterOpen: inputs.afterTargetOpenForTesting)
        // Alias spelling is not authority: an extensionless/.APP alias may name this same
        // installed target. A true bare CLI directory has no app-replacement target.
        guard app.url.path.hasSuffix(".app") else {
            if bundleURL.pathExtension.lowercased() == "app" {
                throw ResolutionError.invalidBundle
            }
            return nil
        }
        let target = try BelugaUpdateOperation.Target(canonicalPath: app.url.path,
                                                     effectiveUID: inputs.effectiveUID)
        let suppliedHome = try inputs.accountHomeDirectory(inputs.effectiveUID)
        guard suppliedHome.isFileURL, isAbsolutePath(suppliedHome.path), suppliedHome.path != "/" else {
            throw ResolutionError.invalidAccountHome
        }
        let home = try resolveDirectory(suppliedHome)
        guard home.url.path != "/" else { throw ResolutionError.invalidAccountHome }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let targetDigest = SHA256.hash(data: try encoder.encode(target))
            .map { String(format: "%02x", $0) }.joined()
        let directory = home.url.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Beluga", isDirectory: true)
            .appendingPathComponent("UpdateFences", isDirectory: true)
            .appendingPathComponent(targetDigest, isDirectory: true)
        return Self(target: target, fenceDirectoryURL: directory,
                    targetDirectoryIdentity: app.identity, homeDirectoryURL: home.url,
                    homeDirectoryIdentity: home.identity)
    }

    /// Call after acquiring the shared runtime lock, immediately before noncreating fence
    /// read. Keeping the same lock through runtime prevents an admitted broker from racing it.
    package func revalidate() throws {
        guard Darwin.geteuid() == target.effectiveUID else {
            throw ResolutionError.effectiveUIDChanged
        }
        let app = try Self.resolveDirectory(URL(fileURLWithPath: target.canonicalPath,
                                               isDirectory: true))
        let home = try Self.resolveDirectory(homeDirectoryURL)
        guard app.url.path == target.canonicalPath, app.identity == targetDirectoryIdentity,
              home.url == homeDirectoryURL, home.identity == homeDirectoryIdentity else {
            throw ResolutionError.directoryIdentityChanged
        }
    }

    /// Broker-only namespace preparation borrows this descriptor synchronously. The body
    /// must not close, retain, or transfer it; Context owns its lifetime and exact identity.
    package func withValidatedAccountHomeDirectory(_ body: (Int32) throws -> Void) throws {
        try revalidate()
        let descriptor = try Self.openDirectory(homeDirectoryURL.path, noFollow: true)
        defer { Darwin.close(descriptor) }
        func validateBorrowedHome() throws {
            guard Darwin.geteuid() == target.effectiveUID,
                  try Self.directoryIdentity(descriptor) == homeDirectoryIdentity,
                  try Self.descriptorPath(descriptor) == homeDirectoryURL.path else {
                throw ResolutionError.directoryIdentityChanged
            }
        }
        try validateBorrowedHome()
        do {
            try body(descriptor)
            try validateBorrowedHome()
            try revalidate()
        } catch {
            let originalError = error
            try validateBorrowedHome()
            try revalidate()
            throw originalError
        }
    }

    private struct DirectoryIdentity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        init(_ value: stat) { device = value.st_dev; inode = value.st_ino }
    }

    private struct ResolvedDirectory {
        let url: URL
        let identity: DirectoryIdentity
    }

    /// F_GETPATH resolves aliases from the opened vnode. Both the supplied and resolved paths
    /// are reopened and compared; rename/replacement cannot silently change the target scope.
    private static func resolveDirectory(_ url: URL,
                                         afterOpen: (() throws -> Void)? = nil) throws -> ResolvedDirectory {
        guard url.isFileURL, isAbsolutePath(url.path) else { throw ResolutionError.unavailableDirectory }
        let descriptor = try openDirectory(url.path, noFollow: false)
        defer { Darwin.close(descriptor) }
        let identity = try directoryIdentity(descriptor)
        let canonicalPath = try descriptorPath(descriptor)
        try afterOpen?()
        let suppliedAgain = try openDirectory(url.path, noFollow: false)
        defer { Darwin.close(suppliedAgain) }
        let canonicalAgain = try openDirectory(canonicalPath, noFollow: true)
        defer { Darwin.close(canonicalAgain) }
        guard try directoryIdentity(suppliedAgain) == identity,
              try directoryIdentity(canonicalAgain) == identity,
              try directoryIdentity(descriptor) == identity,
              try descriptorPath(suppliedAgain) == canonicalPath,
              try descriptorPath(canonicalAgain) == canonicalPath,
              try descriptorPath(descriptor) == canonicalPath else {
            throw ResolutionError.directoryIdentityChanged
        }
        return ResolvedDirectory(url: URL(fileURLWithPath: canonicalPath, isDirectory: true),
                                 identity: identity)
    }

    private static func openDirectory(_ path: String, noFollow: Bool) throws -> Int32 {
        let flags = O_RDONLY | O_DIRECTORY | O_CLOEXEC | (noFollow ? O_NOFOLLOW : 0)
        let descriptor = path.withCString { Darwin.open($0, flags) }
        guard descriptor >= 0 else { throw ResolutionError.unavailableDirectory }
        return descriptor
    }

    private static func directoryIdentity(_ descriptor: Int32) throws -> DirectoryIdentity {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else {
            throw ResolutionError.unavailableDirectory
        }
        return DirectoryIdentity(value)
    }

    private static func descriptorPath(_ descriptor: Int32) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let path: String? = buffer.withUnsafeMutableBufferPointer { bytes in
            guard let base = bytes.baseAddress, Darwin.fcntl(descriptor, F_GETPATH, base) == 0,
                  let nul = bytes.firstIndex(of: 0), nul > 0 else { return nil }
            return String(bytes: bytes.prefix(nul).map { UInt8(bitPattern: $0) }, encoding: .utf8)
        }
        guard let path, isAbsolutePath(path) else { throw ResolutionError.unavailableDirectory }
        return path
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.utf8.count < Int(MAXPATHLEN) &&
            path.utf8.allSatisfy { $0 >= 32 && $0 != 127 }
    }

    /// The passwd directory is account authority. HOME and Foundation's environment-sensitive
    /// home conveniences cannot redirect a marker into an empty alternate namespace.
    private static func accountHome(for uid: UInt32) throws -> URL {
        var size = 4_096
        while size <= 65_536 {
            var buffer = [CChar](repeating: 0, count: size)
            var value = passwd()
            var found: UnsafeMutablePointer<passwd>?
            var home: String?
            let status = buffer.withUnsafeMutableBufferPointer { bytes in
                let status = Darwin.getpwuid_r(uid, &value, bytes.baseAddress, bytes.count, &found)
                if status == 0, found != nil, value.pw_uid == uid, let directory = value.pw_dir {
                    home = String(validatingCString: directory)
                }
                return status
            }
            if status == ERANGE { size *= 2; continue }
            guard status == 0, let home, isAbsolutePath(home), home != "/" else {
                throw ResolutionError.unavailableAccountHome
            }
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        throw ResolutionError.unavailableAccountHome
    }
}
