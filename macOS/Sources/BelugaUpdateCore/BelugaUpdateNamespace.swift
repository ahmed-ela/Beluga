import Darwin
import Foundation

/// Broker preparation only. The caller must already retain the ordinary shared host lease.
/// Runtime admission remains noncreating; the fence store alone creates the digest leaf.
package enum BelugaUpdateNamespace {
    private static let serialization = Serialization()
    private static let components = ["Library", "Application Support", "Beluga", "UpdateFences"]

    package enum Failure: Error, Equatable {
        case unsafeDirectory, directoryIdentityChanged
        case io(Int32), durabilityUncertain(Int32)
    }

    package static func prepare(context: BelugaUpdateRuntimeContext) throws {
        try prepare(context: context, afterDirectoryOpenedForTesting: nil)
    }

    /// Internal race seam only; production accepts no account, path, or environment override.
    static func prepare(
        context: BelugaUpdateRuntimeContext,
        afterDirectoryOpenedForTesting: ((String) throws -> Void)?
    ) throws {
        serialization.lock.lock()
        defer { serialization.lock.unlock() }
        try context.withValidatedAccountHomeDirectory { home in
            let homeMetadata = try metadata(home)
            try validateMetadata(homeMetadata, privateOnly: false)
            try rejectAllowACL(home)
            var nodes = [Node(descriptor: home, identity: Identity(homeMetadata),
                              name: nil, privateOnly: false)]
            var ownedDescriptors: [Int32] = []
            defer { for descriptor in ownedDescriptors.reversed() { Darwin.close(descriptor) } }

            for (index, name) in components.enumerated() {
                try revalidate(nodes, context: context)
                let parent = nodes[nodes.count - 1].descriptor
                var named = stat()
                var created = false
                if Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) != 0 {
                    guard errno == ENOENT else { throw Failure.io(errno) }
                    // Only this fixed child may be created. Existing unsafe children are
                    // never chmodded, removed, or repaired, including interrupted prefixes.
                    if Darwin.mkdirat(parent, name, 0o700) == 0 { created = true }
                    else if errno != EEXIST { throw Failure.io(errno) }
                    guard Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else {
                        throw Failure.io(errno)
                    }
                }
                let privateOnly = index >= 2
                try validateMetadata(named, privateOnly: privateOnly)
                let descriptor = Darwin.openat(parent, name,
                                                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                guard descriptor >= 0 else { throw Failure.unsafeDirectory }
                ownedDescriptors.append(descriptor)
                let opened = try metadata(descriptor)
                try validateMetadata(opened, privateOnly: privateOnly)
                try rejectAllowACL(descriptor)
                guard Identity(named) == Identity(opened) else {
                    throw Failure.directoryIdentityChanged
                }
                nodes.append(Node(descriptor: descriptor, identity: Identity(opened),
                                  name: name, privateOnly: privateOnly))
                try afterDirectoryOpenedForTesting?(name)
                try revalidate(nodes, context: context)
                if created {
                    try sync(descriptor)
                    try sync(parent)
                    try revalidate(nodes, context: context)
                }
            }
            // Also sync previously existing safe prefixes. A prior failed preparation
            // cannot turn an unsynced mkdir into an optimistic idempotent success.
            for node in nodes.reversed() { try sync(node.descriptor) }
            try revalidate(nodes, context: context)
        }
    }

    private static func revalidate(_ nodes: [Node], context: BelugaUpdateRuntimeContext) throws {
        try context.revalidate()
        for (index, node) in nodes.enumerated() {
            let current = try metadata(node.descriptor)
            try validateMetadata(current, privateOnly: node.privateOnly)
            try rejectAllowACL(node.descriptor)
            guard Identity(current) == node.identity else { throw Failure.directoryIdentityChanged }
            if index > 0, let name = node.name {
                var named = stat()
                guard Darwin.fstatat(nodes[index - 1].descriptor, name, &named,
                                     AT_SYMLINK_NOFOLLOW) == 0 else {
                    throw Failure.directoryIdentityChanged
                }
                try validateMetadata(named, privateOnly: node.privateOnly)
                guard Identity(named) == node.identity else { throw Failure.directoryIdentityChanged }
            }
        }
    }

    private static func metadata(_ descriptor: Int32) throws -> stat {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0 else { throw Failure.io(errno) }
        return value
    }

    /// Normal account parents may be 0755/0700; only product-owned parents require 0700.
    static func isSafeMetadata(_ value: stat, privateOnly: Bool, expectedOwner: uid_t) -> Bool {
        value.st_mode & S_IFMT == S_IFDIR && value.st_uid == expectedOwner &&
            value.st_nlink >= 1 && value.st_mode & 0o7000 == 0 &&
            (privateOnly ? value.st_mode & 0o777 == 0o700 : value.st_mode & 0o022 == 0)
    }

    private static func validateMetadata(_ value: stat, privateOnly: Bool) throws {
        guard isSafeMetadata(value, privateOnly: privateOnly, expectedOwner: Darwin.geteuid()) else {
            throw Failure.unsafeDirectory
        }
    }

    private static func rejectAllowACL(_ descriptor: Int32) throws {
        do { try BelugaDescriptorACL.rejectAllowACL(descriptor) }
        catch { throw Failure.unsafeDirectory }
    }

    private static func sync(_ descriptor: Int32) throws {
        guard Darwin.fsync(descriptor) == 0 else { throw Failure.durabilityUncertain(errno) }
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        init(_ value: stat) { device = value.st_dev; inode = value.st_ino }
    }

    private struct Node {
        let descriptor: Int32
        let identity: Identity
        let name: String?
        let privateOnly: Bool
    }

    private final class Serialization: @unchecked Sendable { let lock = NSLock() }
}
