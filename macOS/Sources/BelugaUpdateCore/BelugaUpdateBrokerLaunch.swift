import Darwin
import Foundation

/// Bounded routing arguments, never authentication or update authority. Both ends
/// independently verify installed/staged code and authenticate the kernel peer.
package struct BelugaUpdateBrokerLaunch: Equatable, Sendable {
    package let operationID: UUID
    package let target: BelugaUpdateOperation.Target

    package enum Failure: Error, Equatable { case invalidArguments, unsuitableInstallation }

    package init(operationID: UUID, target: BelugaUpdateOperation.Target) throws {
        guard operationID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              target.effectiveUID == Darwin.geteuid() else { throw Failure.invalidArguments }
        self.operationID = operationID
        self.target = target
    }

    package init(arguments: [String]) throws {
        guard arguments.count == 5, arguments[1] == "--operation",
              arguments[3] == "--target", let id = UUID(uuidString: arguments[2]),
              id.uuidString == arguments[2] else { throw Failure.invalidArguments }
        do {
            try self.init(operationID: id, target: .init(canonicalPath: arguments[4],
                                                        effectiveUID: Darwin.geteuid()))
        } catch { throw Failure.invalidArguments }
    }

    package var arguments: [String] {
        ["--operation", operationID.uuidString, "--target", target.canonicalPath]
    }

    /// A read-only admission check, not installation proof. We do not silently
    /// elevate, update a mounted read-only image, or use translocation's alias.
    package static func requireWritableInstallation(_ context: BelugaUpdateRuntimeContext) throws {
        try context.revalidate()
        let path = context.target.canonicalPath
        guard !path.split(separator: "/").contains("AppTranslocation"),
              Darwin.access(path, W_OK | X_OK) == 0,
              Darwin.access(URL(fileURLWithPath: path).deletingLastPathComponent().path, W_OK | X_OK) == 0 else {
            throw Failure.unsuitableInstallation
        }
        var filesystem = statfs()
        let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.unsuitableInstallation }
        defer { Darwin.close(descriptor) }
        guard Darwin.fstatfs(descriptor, &filesystem) == 0,
              filesystem.f_flags & UInt32(MNT_RDONLY) == 0 else { throw Failure.unsuitableInstallation }
        try context.revalidate()
    }
}
