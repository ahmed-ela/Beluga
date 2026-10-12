import CryptoKit
import Darwin
import Foundation

/// Read-only finite observations of app bytes, not code-signing, ownership policy,
/// installed-callback, or freshness proof. The caller must retain update ownership
/// and independently verify those authorities. This is not an atomic filesystem snapshot.
package enum BelugaUpdateBundleTree {
    package static let algorithm = "beluga.bundle-tree-json-v1"
    package enum Executable: Equatable, Sendable {
        case host, broker

        fileprivate var relativePath: Data {
            Data((self == .host ? "/Contents/MacOS/CaptureServer" : "/Contents/MacOS/BelugaUpdater").utf8)
        }
    }
    package struct Snapshot: Equatable, Sendable {
        package let executableSHA256: String
        package let bundleTreeSHA256: String
    }

    package enum Failure: Error, Equatable {
        case invalidRoot, unsafeNode, unsupportedName, changedTree, missingExecutable
        case limitExceeded, io(Int32)
    }

    /// Exactly the producer's beluga.bundle-tree-json-v1 stream: UTF-8 byte-ordered
    /// depth-first preorder; compact [relative, mode & 0777, ftype] JSON, then raw
    /// link target bytes or lowercase ASCII SHA-256(file bytes). Root relative is
    /// empty and child paths start with '/'. Symlinks are hashed, never followed.
    package static func inspect(bundleURL: URL, executable: Executable = .host) throws -> Snapshot {
        try inspect(bundleURL: bundleURL, executable: executable, limits: .standard, hooks: .init())
    }

    // Internal source-only bounded fixture seams; production has no limit overrides.
    struct Limits: Sendable {
        var maximumNodes = 100_000
        var maximumTotalBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024
        var maximumFileBytes: UInt64 = 8 * 1_024 * 1_024 * 1_024
        var maximumDepth = 128
        var maximumPathBytes = 4_096
        var maximumLinkBytes = 4_096
        var maximumSeconds: TimeInterval = 120
        static let standard = Self()
    }

    struct Hooks {
        var afterNodeRead: ((String) throws -> Void)? = nil
        var beforeValidation: (() throws -> Void)? = nil
    }

    static func inspect(bundleURL: URL, executable: Executable = .host,
                        limits: Limits, hooks: Hooks = .init()) throws -> Snapshot {
        let standard = Limits.standard
        guard limits.maximumNodes > 0, limits.maximumNodes <= standard.maximumNodes,
              limits.maximumTotalBytes > 0, limits.maximumTotalBytes <= standard.maximumTotalBytes,
              limits.maximumFileBytes > 0, limits.maximumFileBytes <= standard.maximumFileBytes,
              limits.maximumDepth > 0, limits.maximumDepth <= standard.maximumDepth,
              limits.maximumPathBytes > 0, limits.maximumPathBytes <= standard.maximumPathBytes,
              limits.maximumLinkBytes > 0, limits.maximumLinkBytes <= standard.maximumLinkBytes,
              limits.maximumSeconds > 0, limits.maximumSeconds <= standard.maximumSeconds,
              limits.maximumSeconds.isFinite else {
            throw Failure.limitExceeded
        }
        let root = try Root(bundleURL: bundleURL, limits: limits)
        defer { root.close() }
        let walker = Walker(executable: executable, limits: limits, hooks: hooks)
        try walker.hashDirectory(root.descriptor, relative: Data(), depth: 0)
        try hooks.beforeValidation?()
        try root.revalidate()
        try walker.validateDirectory(root.descriptor, relative: Data(), depth: 0)
        try root.revalidate()
        guard let executable = walker.executableSHA256 else { throw Failure.missingExecutable }
        return Snapshot(executableSHA256: executable,
                        bundleTreeSHA256: hex(walker.tree.finalize()))
    }

    private struct Name: Equatable {
        let bytes: Data
        let text: String
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }
    }

    private struct Fingerprint: Equatable {
        let device: Int64
        let inode: UInt64
        let mode: UInt32
        let owner: UInt32
        let group: UInt32
        let links: UInt64
        let size: Int64
        let flags: UInt32
        let generation: UInt32
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
        init(_ value: stat) {
            device = Int64(value.st_dev); inode = UInt64(value.st_ino)
            mode = UInt32(value.st_mode); owner = value.st_uid; group = value.st_gid
            links = UInt64(value.st_nlink); size = Int64(value.st_size)
            flags = value.st_flags; generation = value.st_gen
            modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
            changedSeconds = Int64(value.st_ctimespec.tv_sec)
            changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
        }
        var type: UInt32 { mode & UInt32(S_IFMT) }
    }

    /// Ancestor identity excludes directory timestamps/membership: unrelated sibling
    /// changes must not invalidate this exact app, but replacement of an ancestor must.
    private struct DirectoryIdentity: Equatable {
        let device: Int64
        let inode: UInt64
        let mode: UInt32
        let owner: UInt32
        let group: UInt32
        let generation: UInt32
        init(_ value: Fingerprint) {
            device = value.device; inode = value.inode; mode = value.mode
            owner = value.owner; group = value.group; generation = value.generation
        }
    }

    private struct Root {
        let path: String
        let ancestors: [Ancestor]
        var descriptor: Int32 { ancestors.last!.descriptor }

        struct Ancestor {
            let descriptor: Int32
            let name: String?
            let identity: DirectoryIdentity
        }

        init(bundleURL: URL, limits: Limits) throws {
            let path = bundleURL.path
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard bundleURL.isFileURL, path.utf8.count < Int(MAXPATHLEN),
                  path.utf8.count <= limits.maximumPathBytes, parts.count > 1,
                  parts.count <= limits.maximumDepth + 1, parts.first == "",
                  parts.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !path.utf8.contains(0) else { throw Failure.invalidRoot }
            var opened = [Ancestor]()
            do {
                let first = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                guard first >= 0 else { throw Failure.io(errno) }
                let firstMetadata: Fingerprint
                do { firstMetadata = try BelugaUpdateBundleTree.fingerprint(first) }
                catch { Darwin.close(first); throw error }
                opened.append(Ancestor(descriptor: first, name: nil,
                                       identity: DirectoryIdentity(firstMetadata)))
                for part in parts.dropFirst() {
                    let name = String(part)
                    let parent = opened.last!.descriptor
                    let named = try BelugaUpdateBundleTree.namedFingerprint(parent, name)
                    guard named.type == UInt32(S_IFDIR) else { throw Failure.invalidRoot }
                    let child = try BelugaUpdateBundleTree.openDirectory(parent, name)
                    do {
                        let held = try BelugaUpdateBundleTree.fingerprint(child)
                        guard held == named else { throw Failure.changedTree }
                        opened.append(Ancestor(descriptor: child, name: name,
                                               identity: DirectoryIdentity(held)))
                    } catch { Darwin.close(child); throw error }
                }
                self.path = path
                ancestors = opened
                try revalidate()
            } catch {
                for node in opened.reversed() { Darwin.close(node.descriptor) }
                throw error
            }
        }

        func close() { for node in ancestors.reversed() { Darwin.close(node.descriptor) } }

        func revalidate() throws {
            for (index, node) in ancestors.enumerated() {
                guard DirectoryIdentity(try BelugaUpdateBundleTree.fingerprint(node.descriptor)) == node.identity else {
                    throw Failure.changedTree
                }
                if let name = node.name {
                    guard DirectoryIdentity(try BelugaUpdateBundleTree.namedFingerprint(ancestors[index - 1].descriptor, name)) == node.identity else {
                        throw Failure.changedTree
                    }
                }
            }
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let resolved: Data? = buffer.withUnsafeMutableBufferPointer { bytes in
                guard let base = bytes.baseAddress, Darwin.fcntl(descriptor, F_GETPATH, base) == 0,
                      let nul = bytes.firstIndex(of: 0), nul > 0 else { return nil }
                return Data(bytes.prefix(nul).map { UInt8(bitPattern: $0) })
            }
            guard resolved == Data(path.utf8) else { throw Failure.invalidRoot }
        }
    }

    private final class Walker {
        struct Record {
            let metadata: Fingerprint
            let children: [Name]?
            let link: Data?
        }
        let limits: Limits
        let hooks: Hooks
        let executable: Executable
        let deadline: TimeInterval
        var tree = SHA256()
        var executableSHA256: String?
        var records = [Data: Record]()
        var totalBytes: UInt64 = 0

        init(executable: Executable, limits: Limits, hooks: Hooks) {
            self.executable = executable; self.limits = limits; self.hooks = hooks
            deadline = ProcessInfo.processInfo.systemUptime + limits.maximumSeconds
        }

        func checkBudget() throws {
            guard ProcessInfo.processInfo.systemUptime <= deadline else { throw Failure.limitExceeded }
        }

        func add(_ metadata: Fingerprint, relative: Data, type: String,
                 children: [Name]? = nil, link: Data? = nil) throws {
            try checkBudget()
            guard records.count < limits.maximumNodes, records[relative] == nil,
                  relative.count <= limits.maximumPathBytes else { throw Failure.limitExceeded }
            records[relative] = Record(metadata: metadata, children: children, link: link)
            tree.update(data: BelugaUpdateBundleTree.tuple(relative: relative, mode: metadata.mode & 0o777, type: type))
        }

        func childPath(_ parent: Data, _ name: Name) throws -> Data {
            var result = parent; result.append(47); result.append(name.bytes)
            guard result.count <= limits.maximumPathBytes else { throw Failure.limitExceeded }
            return result
        }

        func hashDirectory(_ descriptor: Int32, relative: Data, depth: Int) throws {
            try checkBudget()
            guard depth <= limits.maximumDepth else { throw Failure.limitExceeded }
            let before = try BelugaUpdateBundleTree.fingerprint(descriptor)
            guard before.type == UInt32(S_IFDIR) else { throw Failure.unsafeNode }
            let names = try children(descriptor)
            try add(before, relative: relative, type: "directory", children: names)
            for name in names {
                try checkBudget()
                let child = try childPath(relative, name)
                let named = try BelugaUpdateBundleTree.namedFingerprint(descriptor, name.text)
                switch named.type {
                case UInt32(S_IFDIR):
                    let opened = try BelugaUpdateBundleTree.openDirectory(descriptor, name.text)
                    defer { Darwin.close(opened) }
                    guard try BelugaUpdateBundleTree.fingerprint(opened) == named else { throw Failure.changedTree }
                    try hashDirectory(opened, relative: child, depth: depth + 1)
                case UInt32(S_IFREG):
                    try add(named, relative: child, type: "file")
                    let hash = try fileHash(descriptor, name, expected: named)
                    tree.update(data: Data(hash.utf8))
                    if child == executable.relativePath { executableSHA256 = hash }
                    try hooks.afterNodeRead?(nameForHook(child))
                case UInt32(S_IFLNK):
                    let target = try linkBytes(descriptor, name, expected: named)
                    try add(named, relative: child, type: "link", link: target)
                    tree.update(data: target)
                    try hooks.afterNodeRead?(nameForHook(child))
                default: throw Failure.unsafeNode
                }
                guard try BelugaUpdateBundleTree.namedFingerprint(descriptor, name.text) == named else { throw Failure.changedTree }
            }
            guard try BelugaUpdateBundleTree.fingerprint(descriptor) == before, try children(descriptor) == names else {
                throw Failure.changedTree
            }
            try hooks.afterNodeRead?(nameForHook(relative))
        }

        func validateDirectory(_ descriptor: Int32, relative: Data, depth: Int) throws {
            try checkBudget()
            guard depth <= limits.maximumDepth, let record = records[relative],
                  let names = record.children, try BelugaUpdateBundleTree.fingerprint(descriptor) == record.metadata,
                  try children(descriptor) == names else { throw Failure.changedTree }
            for name in names {
                try checkBudget()
                let child = try childPath(relative, name)
                guard let expected = records[child],
                      try BelugaUpdateBundleTree.namedFingerprint(descriptor, name.text) == expected.metadata else {
                    throw Failure.changedTree
                }
                switch expected.metadata.type {
                case UInt32(S_IFDIR):
                    let opened = try BelugaUpdateBundleTree.openDirectory(descriptor, name.text)
                    defer { Darwin.close(opened) }
                    try validateDirectory(opened, relative: child, depth: depth + 1)
                case UInt32(S_IFREG):
                    let opened = name.text.withCString {
                        Darwin.openat(descriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
                    }
                    guard opened >= 0 else { throw Failure.changedTree }
                    defer { Darwin.close(opened) }
                    guard try BelugaUpdateBundleTree.fingerprint(opened) == expected.metadata else { throw Failure.changedTree }
                case UInt32(S_IFLNK):
                    guard try linkBytes(descriptor, name, expected: expected.metadata) == expected.link else {
                        throw Failure.changedTree
                    }
                default: throw Failure.unsafeNode
                }
                guard try BelugaUpdateBundleTree.namedFingerprint(descriptor, name.text) == expected.metadata else {
                    throw Failure.changedTree
                }
            }
            guard try BelugaUpdateBundleTree.fingerprint(descriptor) == record.metadata, try children(descriptor) == names else {
                throw Failure.changedTree
            }
        }

        func children(_ descriptor: Int32) throws -> [Name] {
            let copied = Darwin.openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            guard copied >= 0 else { throw Failure.io(errno) }
            guard let stream = Darwin.fdopendir(copied) else {
                let error = errno; Darwin.close(copied); throw Failure.io(error)
            }
            defer { Darwin.closedir(stream) }
            var names = [Name]()
            var seen = Set<Data>()
            var interruptions = 0
            while true {
                try checkBudget()
                errno = 0
                guard let entry = Darwin.readdir(stream) else {
                    if errno == EINTR, interruptions < 16 { interruptions += 1; continue }
                    guard errno == 0 else { throw Failure.io(errno) }
                    break
                }
                let length = Int(entry.pointee.d_namlen)
                let bytes: Data? = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                    guard length > 0, length < raw.count, raw[length] == 0 else { return nil }
                    return Data(raw.prefix(length))
                }
                guard let bytes, !bytes.contains(0), !bytes.contains(47),
                      let text = String(data: bytes, encoding: .utf8) else { throw Failure.unsupportedName }
                if bytes == Data(".".utf8) || bytes == Data("..".utf8) { continue }
                guard names.count < limits.maximumNodes, seen.insert(bytes).inserted else {
                    throw Failure.limitExceeded
                }
                names.append(Name(bytes: bytes, text: text))
            }
            return names.sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }
        }

        func fileHash(_ parent: Int32, _ name: Name, expected: Fingerprint) throws -> String {
            guard expected.size >= 0, UInt64(expected.size) <= limits.maximumFileBytes,
                  UInt64(expected.size) <= limits.maximumTotalBytes - totalBytes else {
                throw Failure.limitExceeded
            }
            totalBytes += UInt64(expected.size)
            let descriptor = name.text.withCString {
                Darwin.openat(parent, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            }
            guard descriptor >= 0 else { throw Failure.unsafeNode }
            defer { Darwin.close(descriptor) }
            guard try BelugaUpdateBundleTree.fingerprint(descriptor) == expected else { throw Failure.changedTree }
            var hash = SHA256()
            var buffer = [UInt8](repeating: 0, count: 1_024 * 1_024)
            var remaining = UInt64(expected.size)
            var interruptions = 0
            while remaining > 0 {
                try checkBudget()
                let requested = Int(min(remaining, UInt64(buffer.count)))
                let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, requested) }
                if count < 0, errno == EINTR, interruptions < 16 { interruptions += 1; continue }
                guard count > 0, count <= requested else { throw Failure.changedTree }
                remaining -= UInt64(count)
                hash.update(data: Data(buffer.prefix(count)))
            }
            var extra: UInt8 = 0
            var count: Int
            repeat {
                try checkBudget()
                count = Darwin.read(descriptor, &extra, 1)
                if count < 0, errno == EINTR, interruptions < 16 { interruptions += 1 }
                else { break }
            } while true
            guard count == 0, try BelugaUpdateBundleTree.fingerprint(descriptor) == expected,
                  try BelugaUpdateBundleTree.namedFingerprint(parent, name.text) == expected else { throw Failure.changedTree }
            return BelugaUpdateBundleTree.hex(hash.finalize())
        }

        func linkBytes(_ parent: Int32, _ name: Name, expected: Fingerprint) throws -> Data {
            try checkBudget()
            guard expected.size > 0, expected.size <= Int64(limits.maximumLinkBytes) else {
                throw Failure.limitExceeded
            }
            var buffer = [UInt8](repeating: 0, count: limits.maximumLinkBytes + 1)
            let count = name.text.withCString { name in
                buffer.withUnsafeMutableBytes {
                    Darwin.readlinkat(parent, name, $0.baseAddress!.assumingMemoryBound(to: CChar.self), $0.count)
                }
            }
            guard count == Int(expected.size), count < buffer.count,
                  try BelugaUpdateBundleTree.namedFingerprint(parent, name.text) == expected else { throw Failure.changedTree }
            return Data(buffer.prefix(count))
        }

        private func nameForHook(_ relative: Data) -> String {
            String(decoding: relative, as: UTF8.self)
        }
    }

    private static func fingerprint(_ descriptor: Int32) throws -> Fingerprint {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0 else { throw Failure.io(errno) }
        return Fingerprint(value)
    }

    private static func namedFingerprint(_ parent: Int32, _ name: String) throws -> Fingerprint {
        var value = stat()
        guard name.withCString({ Darwin.fstatat(parent, $0, &value, AT_SYMLINK_NOFOLLOW) }) == 0 else {
            throw Failure.io(errno)
        }
        return Fingerprint(value)
    }

    private static func openDirectory(_ parent: Int32, _ name: String) throws -> Int32 {
        let descriptor = name.withCString {
            Darwin.openat(parent, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else { throw Failure.unsafeNode }
        return descriptor
    }

    private static func tuple(relative: Data, mode: UInt32, type: String) -> Data {
        var bytes = Data("[\"".utf8)
        let hexDigits = Array("0123456789abcdef".utf8)
        for byte in relative {
            switch byte {
            case 34: bytes.append(contentsOf: [92, 34])
            case 92: bytes.append(contentsOf: [92, 92])
            case 8: bytes.append(contentsOf: [92, 98])
            case 9: bytes.append(contentsOf: [92, 116])
            case 10: bytes.append(contentsOf: [92, 110])
            case 12: bytes.append(contentsOf: [92, 102])
            case 13: bytes.append(contentsOf: [92, 114])
            case 0...31: bytes.append(contentsOf: [92, 117, 48, 48, hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 15)]])
            default: bytes.append(byte)
            }
        }
        bytes.append(contentsOf: "\",\(mode),\"\(type)\"]".utf8)
        return bytes
    }

    private static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
