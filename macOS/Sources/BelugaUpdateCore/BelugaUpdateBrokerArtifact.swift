import CoreFoundation
import Darwin
import Foundation
import Security

/// Static broker staging only. The caller retains update ownership and has already verified
/// the parent. Returned bytes are not launch, live-peer, installer or readiness authority.
/// Extended metadata is deliberately not propagated; this is not Gatekeeper/notary proof.
package enum BelugaUpdateBrokerArtifact {
    package static let bundleIdentifier = "com.elamin.beluga.Updater"
    package static let embeddedRelativePath = "Contents/Helpers/BelugaUpdater.app"
    package static let executableName = "BelugaUpdater"
    static let signingRequirement = "anchor apple generic and identifier \"com.elamin.beluga.Updater\" and certificate leaf[subject.OU] = \"MSMG8CJLB3\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    static let validationFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures |
        kSecCSCheckNestedCode | kSecCSStrictValidate).union(.noNetworkAccess)

    package struct Staged: Sendable {
        package let operationID: UUID
        package let bundleURL: URL
        package let executableURL: URL
        package let identity: BelugaUpdateOperation.ArtifactIdentity
        package let nativeCDHash: Data
        fileprivate let parentURL: URL
        fileprivate let parentIdentity: DirectoryIdentity
        fileprivate let operationDirectoryIdentity: DirectoryIdentity
        fileprivate let bundleDirectoryIdentity: DirectoryIdentity
        fileprivate let targetPath: String
    }

    /// Fresh static observation only. The caller still authenticates the connected native
    /// process and binds that incarnation to its exact operation/readiness challenge.
    package struct Verification: Equatable, Sendable {
        package let executableURL: URL
        package let nativeCDHash: Data
        package let identity: BelugaUpdateOperation.ArtifactIdentity
    }

    package enum Failure: Error, Equatable {
        case signature(OSStatus), invalidSignature, invalidMetadata, configurationMismatch
        case metadataLimitExceeded, artifactChanged, unsafeDirectory, directoryChanged
        case collision, limitExceeded, unsafeFixture, io(Int32)
    }

    package static func stage(context: BelugaUpdateRuntimeContext,
                              parentConfiguration: BelugaReleaseConfiguration,
                              operationID: UUID, stagingParentURL: URL) throws -> Staged {
        try stageBound(context: context, parentConfiguration: parentConfiguration,
                       operationID: operationID, stagingParentURL: stagingParentURL,
                       signatureVerifier: nativeSignature, hooks: .init())
    }

    /// Re-read immediately before a later launch boundary. This still authenticates no process.
    package static func verifyStaged(context: BelugaUpdateRuntimeContext,
                                     parentConfiguration: BelugaReleaseConfiguration,
                                     staged: Staged) throws {
        try verifyStagedBound(context: context, parentConfiguration: parentConfiguration,
                              staged: staged, signatureVerifier: nativeSignature)
    }

    /// The initial broker derives its authority from the independently verified installed
    /// parent, not hash arguments or a menu message. This captures its actual embedded bytes.
    package static func readbackEmbedded(context: BelugaUpdateRuntimeContext,
                                         configuration: BelugaReleaseConfiguration) throws -> Verification {
        try readbackEmbeddedBound(context: context, configuration: configuration,
                                  signatureVerifier: nativeSignature)
    }

    /// A newly installed menu cannot use its predecessor's old app vnode or infer that
    /// predecessor's embedded broker from the new app tree. Read the fixed retained copy
    /// against the exact binding durably published before SDK startup. Configuration is
    /// explicitly predecessor version/build plus the caller's verified feed/key policy.
    package static func readbackExistingStaged(
        operationID: UUID, target: BelugaUpdateOperation.Target,
        expectedBroker: BelugaUpdateOperation.BrokerBinding,
        configuration: BelugaReleaseConfiguration, stagingParentURL: URL
    ) throws -> Verification {
        try readbackExistingStagedBound(operationID: operationID, target: target,
            expectedBroker: expectedBroker, configuration: configuration,
            stagingParentURL: stagingParentURL, signatureVerifier: nativeSignature)
    }

    struct SignatureEvidence {
        var identifier: String
        var teamIdentifier: String
        var flags: UInt32
        var executableURL: URL
        var cdHash: Data
        var securedInfo: [String: Any]
    }

    struct Hooks {
        var afterCopy: (() throws -> Void)? = nil
        var beforePublication: (() throws -> Void)? = nil
    }

    static func stageFixture(context: BelugaUpdateRuntimeContext,
                             parentConfiguration: BelugaReleaseConfiguration,
                             operationID: UUID, stagingParentURL: URL,
                             signatureVerifier: (URL) throws -> SignatureEvidence,
                             hooks: Hooks = .init()) throws -> Staged {
        try withFixture(context: context, stagingParentURL: stagingParentURL) {
            try stageBound(context: context, parentConfiguration: parentConfiguration,
                           operationID: operationID, stagingParentURL: stagingParentURL,
                           signatureVerifier: signatureVerifier, hooks: hooks)
        }
    }

    static func verifyStagedFixture(context: BelugaUpdateRuntimeContext,
                                    parentConfiguration: BelugaReleaseConfiguration,
                                    staged: Staged,
                                    signatureVerifier: (URL) throws -> SignatureEvidence) throws {
        try withFixture(context: context, stagingParentURL: staged.parentURL) {
            try verifyStagedBound(context: context, parentConfiguration: parentConfiguration,
                                  staged: staged, signatureVerifier: signatureVerifier)
        }
    }

    static func readbackEmbeddedFixture(
        context: BelugaUpdateRuntimeContext, configuration: BelugaReleaseConfiguration,
        signatureVerifier: (URL) throws -> SignatureEvidence
    ) throws -> Verification {
        let staging = URL(fileURLWithPath: context.target.canonicalPath).deletingLastPathComponent()
            .appendingPathComponent("staging", isDirectory: true)
        return try withFixture(context: context, stagingParentURL: staging) {
            try readbackEmbeddedBound(context: context, configuration: configuration,
                                      signatureVerifier: signatureVerifier)
        }
    }

    static func readbackExistingStagedFixture(
        operationID: UUID, target: BelugaUpdateOperation.Target,
        expectedBroker: BelugaUpdateOperation.BrokerBinding,
        configuration: BelugaReleaseConfiguration, stagingParentURL: URL,
        signatureVerifier: (URL) throws -> SignatureEvidence
    ) throws -> Verification {
        try withFixture(target: target, stagingParentURL: stagingParentURL) {
            try readbackExistingStagedBound(operationID: operationID, target: target,
                expectedBroker: expectedBroker, configuration: configuration,
                stagingParentURL: stagingParentURL, signatureVerifier: signatureVerifier)
        }
    }

    private struct Verified: Equatable {
        let identity: BelugaUpdateOperation.ArtifactIdentity
        let nativeCDHash: Data
    }

    private static func readbackEmbeddedBound(
        context: BelugaUpdateRuntimeContext, configuration: BelugaReleaseConfiguration,
        signatureVerifier: (URL) throws -> SignatureEvidence
    ) throws -> Verification {
        try context.revalidate()
        let sourceURL = URL(fileURLWithPath: context.target.canonicalPath, isDirectory: true)
            .appendingPathComponent(embeddedRelativePath, isDirectory: true)
        let source = try HeldDirectory(sourceURL)
        defer { source.close() }
        let verified = try verifyBroker(sourceURL, parentConfiguration: configuration,
                                        signatureVerifier: signatureVerifier)
        try source.revalidate(); try context.revalidate()
        return Verification(executableURL: sourceURL.appendingPathComponent("Contents/MacOS/BelugaUpdater"),
                            nativeCDHash: verified.nativeCDHash, identity: verified.identity)
    }

    private static func readbackExistingStagedBound(
        operationID: UUID, target: BelugaUpdateOperation.Target,
        expectedBroker: BelugaUpdateOperation.BrokerBinding,
        configuration: BelugaReleaseConfiguration, stagingParentURL: URL,
        signatureVerifier: (URL) throws -> SignatureEvidence
    ) throws -> Verification {
        // Revalidate synthesized Codable input; a typed value is not by itself trusted.
        _ = try BelugaUpdateOperation.Target(canonicalPath: target.canonicalPath,
            effectiveUID: target.effectiveUID, bundleIdentifier: target.bundleIdentifier,
            teamIdentifier: target.teamIdentifier)
        _ = try BelugaUpdateOperation.BrokerBinding(artifact: expectedBroker.artifact,
                                                   nativeCDHash: expectedBroker.nativeCDHash)
        guard target.effectiveUID == Darwin.geteuid(),
              operationID.uuidString != "00000000-0000-0000-0000-000000000000",
              !stagingParentURL.path.hasPrefix(target.canonicalPath + "/"),
              stagingParentURL.path != target.canonicalPath else { throw Failure.unsafeDirectory }
        guard configuration.version == expectedBroker.artifact.version,
              configuration.build == expectedBroker.artifact.build else {
            throw Failure.configurationMismatch
        }
        let parent = try HeldDirectory(stagingParentURL, privateLeaf: true)
        defer { parent.close() }
        let operationURL = stagingParentURL.appendingPathComponent("broker-" + operationID.uuidString,
                                                                   isDirectory: true)
        let operation = try HeldDirectory(operationURL, privateLeaf: true)
        defer { operation.close() }
        let bundleURL = operationURL.appendingPathComponent("BelugaUpdater.app", isDirectory: true)
        let bundle = try HeldDirectory(bundleURL)
        defer { bundle.close() }
        guard bundle.leafIdentity.owner == target.effectiveUID else { throw Failure.unsafeDirectory }
        let verified = try verifyBroker(bundleURL, parentConfiguration: configuration,
                                        signatureVerifier: signatureVerifier)
        guard verified.identity == expectedBroker.artifact,
              verified.nativeCDHash == expectedBroker.nativeCDHash else { throw Failure.artifactChanged }
        try bundle.revalidate(); try operation.revalidate(); try parent.revalidate()
        return Verification(executableURL: bundleURL.appendingPathComponent("Contents/MacOS/BelugaUpdater"),
                            nativeCDHash: verified.nativeCDHash, identity: verified.identity)
    }

    private static func stageBound(context: BelugaUpdateRuntimeContext,
                                   parentConfiguration: BelugaReleaseConfiguration,
                                   operationID: UUID, stagingParentURL: URL,
                                   signatureVerifier: (URL) throws -> SignatureEvidence,
                                   hooks: Hooks) throws -> Staged {
        try context.revalidate()
        let parent = try HeldDirectory(stagingParentURL, privateLeaf: true)
        defer { parent.close() }
        guard !parent.path.hasPrefix(context.target.canonicalPath + "/"),
              parent.path != context.target.canonicalPath else { throw Failure.unsafeDirectory }
        let sourceURL = URL(fileURLWithPath: context.target.canonicalPath, isDirectory: true)
            .appendingPathComponent(embeddedRelativePath, isDirectory: true)
        let source = try HeldDirectory(sourceURL)
        defer { source.close() }
        let original = try verifyBroker(sourceURL, parentConfiguration: parentConfiguration,
                                        signatureVerifier: signatureVerifier)
        try source.revalidate(); try parent.revalidate(); try context.revalidate()
        let operationName = "broker-" + operationID.uuidString
        guard Darwin.mkdirat(parent.descriptor, operationName, 0o700) == 0 else {
            if errno == EEXIST { throw Failure.collision }
            throw Failure.io(errno)
        }
        // A failed attempt retains this exact private directory; it is never reused or erased.
        let operationURL = stagingParentURL.appendingPathComponent(operationName, isDirectory: true)
        let operation = try HeldDirectory(operationURL, privateLeaf: true)
        defer { operation.close() }
        try parent.revalidate(); try source.revalidate(); try context.revalidate()
        guard Darwin.mkdirat(operation.descriptor, "BelugaUpdater.app", 0o700) == 0 else {
            throw Failure.io(errno)
        }
        let copiedURL = operationURL.appendingPathComponent("BelugaUpdater.app", isDirectory: true)
        let copiedDescriptor = Darwin.openat(operation.descriptor, "BelugaUpdater.app",
                                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard copiedDescriptor >= 0 else { throw Failure.io(errno) }
        defer { Darwin.close(copiedDescriptor) }
        let copyRoot = try metadata(copiedDescriptor)
        guard copyRoot.st_uid == Darwin.geteuid(), copyRoot.st_mode & 0o7777 == 0o700 else {
            throw Failure.unsafeDirectory
        }
        try Copier().copyDirectory(source.descriptor, into: copiedDescriptor, depth: 0)
        let namedCopy = try namedMetadata(operation.descriptor, "BelugaUpdater.app")
        let heldCopy = try metadata(copiedDescriptor)
        guard namedCopy.st_dev == copyRoot.st_dev, namedCopy.st_ino == copyRoot.st_ino,
              heldCopy.st_dev == copyRoot.st_dev, heldCopy.st_ino == copyRoot.st_ino,
              heldCopy.st_uid == Darwin.geteuid() else { throw Failure.directoryChanged }
        let copied = try HeldDirectory(copiedURL)
        defer { copied.close() }
        try hooks.afterCopy?()
        try parent.revalidate(); try operation.revalidate(); try source.revalidate()
        try context.revalidate()
        let sourceAfter = try verifyBroker(sourceURL, parentConfiguration: parentConfiguration,
                                          signatureVerifier: signatureVerifier)
        let copy = try verifyBroker(copiedURL, parentConfiguration: parentConfiguration,
                                   signatureVerifier: signatureVerifier)
        guard original == sourceAfter, original == copy else { throw Failure.artifactChanged }
        try hooks.beforePublication?()
        try parent.revalidate(); try operation.revalidate(); try source.revalidate()
        try copied.revalidate(); try context.revalidate()
        guard try verifyBroker(copiedURL, parentConfiguration: parentConfiguration,
                               signatureVerifier: signatureVerifier) == original else {
            throw Failure.artifactChanged
        }
        guard Darwin.fsync(operation.descriptor) == 0, Darwin.fsync(parent.descriptor) == 0 else {
            throw Failure.io(errno)
        }
        try copied.revalidate(); try parent.revalidate(); try operation.revalidate(); try context.revalidate()
        return Staged(operationID: operationID, bundleURL: copiedURL,
                      executableURL: copiedURL.appendingPathComponent("Contents/MacOS/BelugaUpdater"),
                      identity: original.identity, nativeCDHash: original.nativeCDHash,
                      parentURL: stagingParentURL, parentIdentity: parent.leafIdentity,
                      operationDirectoryIdentity: operation.leafIdentity,
                      bundleDirectoryIdentity: copied.leafIdentity,
                      targetPath: context.target.canonicalPath)
    }

    private static func verifyStagedBound(context: BelugaUpdateRuntimeContext,
                                          parentConfiguration: BelugaReleaseConfiguration,
                                          staged: Staged,
                                          signatureVerifier: (URL) throws -> SignatureEvidence) throws {
        try context.revalidate()
        guard staged.targetPath == context.target.canonicalPath,
              staged.bundleURL.path == staged.parentURL.path + "/broker-" +
                staged.operationID.uuidString + "/BelugaUpdater.app",
              staged.executableURL.path == staged.bundleURL.path + "/Contents/MacOS/BelugaUpdater" else {
            throw Failure.directoryChanged
        }
        let parent = try HeldDirectory(staged.parentURL, privateLeaf: true)
        defer { parent.close() }
        let operation = try HeldDirectory(staged.bundleURL.deletingLastPathComponent(), privateLeaf: true)
        defer { operation.close() }
        let bundle = try HeldDirectory(staged.bundleURL)
        defer { bundle.close() }
        guard parent.leafIdentity == staged.parentIdentity,
              operation.leafIdentity == staged.operationDirectoryIdentity,
              bundle.leafIdentity == staged.bundleDirectoryIdentity else { throw Failure.directoryChanged }
        let actual = try verifyBroker(staged.bundleURL, parentConfiguration: parentConfiguration,
                                      signatureVerifier: signatureVerifier)
        guard actual.identity == staged.identity, actual.nativeCDHash == staged.nativeCDHash else {
            throw Failure.artifactChanged
        }
        try bundle.revalidate(); try operation.revalidate(); try parent.revalidate(); try context.revalidate()
    }

    private static func verifyBroker(_ url: URL, parentConfiguration: BelugaReleaseConfiguration,
                                      signatureVerifier: (URL) throws -> SignatureEvidence) throws -> Verified {
        let before = try BelugaUpdateBundleTree.inspect(bundleURL: url, executable: .broker)
        let evidence = try signatureVerifier(url)
        guard evidence.identifier == bundleIdentifier,
              evidence.teamIdentifier == BelugaUpdateOperation.expectedTeamIdentifier,
              evidence.flags & SecCodeSignatureFlags.runtime.rawValue != 0,
              evidence.flags & (SecCodeSignatureFlags.adhoc.rawValue | SecCodeSignatureFlags.linkerSigned.rawValue) == 0,
              evidence.executableURL.isFileURL,
              evidence.executableURL.path == url.path + "/Contents/MacOS/BelugaUpdater",
              evidence.cdHash.count == 20, evidence.cdHash.contains(where: { $0 != 0 }) else {
            throw Failure.invalidSignature
        }
        try metadataBudget(evidence.securedInfo)
        let fixed = ["CFBundleIdentifier": bundleIdentifier, "CFBundleExecutable": executableName,
                     "CFBundleName": "Beluga Updater", "CFBundleDisplayName": "Beluga Updater",
                     "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "14.0",
                     "CFBundleDevelopmentRegion": "en", "CFBundleInfoDictionaryVersion": "6.0"]
        guard fixed.allSatisfy({ evidence.securedInfo[$0.key] as? String == $0.value }),
              exactBoolean(evidence.securedInfo["LSUIElement"], true),
              exactBoolean(evidence.securedInfo["SUVerifyUpdateBeforeExtraction"], true),
              exactBoolean(evidence.securedInfo["SURequireSignedFeed"], true),
              exactBoolean(evidence.securedInfo["SUAllowsAutomaticUpdates"], false) else {
            throw Failure.invalidMetadata
        }
        let configuration: BelugaReleaseConfiguration
        do { configuration = try BelugaReleaseConfiguration(info: evidence.securedInfo) }
        catch { throw Failure.invalidMetadata }
        guard configuration == parentConfiguration,
              evidence.securedInfo["SUFeedURL"] as? String == parentConfiguration.feedURL.absoluteString,
              evidence.securedInfo["SUPublicEDKey"] as? String == parentConfiguration.publicKey.base64EncodedString() else {
            throw Failure.configurationMismatch
        }
        let after = try BelugaUpdateBundleTree.inspect(bundleURL: url, executable: .broker)
        guard before == after else { throw Failure.artifactChanged }
        return Verified(identity: try .init(version: configuration.version, build: configuration.build,
            executableSHA256: after.executableSHA256, dependencyClosureSHA256: after.bundleTreeSHA256),
            nativeCDHash: evidence.cdHash)
    }

    private static func nativeSignature(_ url: URL) throws -> SignatureEvidence {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard created == errSecSuccess, let code else { throw Failure.signature(created) }
        var requirement: SecRequirement?
        let compiled = SecRequirementCreateWithString(signingRequirement as CFString, [], &requirement)
        guard compiled == errSecSuccess, let requirement else { throw Failure.signature(compiled) }
        let checked = SecStaticCodeCheckValidity(code, validationFlags, requirement)
        guard checked == errSecSuccess else { throw Failure.signature(checked) }
        var dictionary: CFDictionary?
        let copied = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &dictionary)
        guard copied == errSecSuccess else { throw Failure.signature(copied) }
        guard let info = dictionary as? [String: Any],
              let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              let number = info[kSecCodeInfoFlags as String] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let flags = UInt32(number.stringValue), String(flags) == number.stringValue,
              let executable = info[kSecCodeInfoMainExecutable as String] as? URL,
              let cdHash = info[kSecCodeInfoUnique as String] as? Data,
              let secured = info[kSecCodeInfoPList as String] as? [String: Any] else {
            throw Failure.invalidSignature
        }
        return .init(identifier: identifier, teamIdentifier: team, flags: flags,
                     executableURL: executable, cdHash: cdHash, securedInfo: secured)
    }

    private static func exactBoolean(_ value: Any?, _ expected: Bool) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue == expected
    }

    private static func metadataBudget(_ value: [String: Any]) throws {
        var nodes = 0; var bytes = 0
        func visit(_ item: Any, depth: Int) throws {
            nodes += 1
            guard nodes <= 512, depth <= 8 else { throw Failure.metadataLimitExceeded }
            if let string = item as? String {
                guard string.utf8.count <= 65_536 - bytes else { throw Failure.metadataLimitExceeded }
                bytes += string.utf8.count
            } else if let dictionary = item as? [String: Any] {
                guard dictionary.count <= 64 else { throw Failure.metadataLimitExceeded }
                for (key, child) in dictionary {
                    guard key.utf8.count <= 128, key.utf8.count <= 65_536 - bytes else {
                        throw Failure.metadataLimitExceeded
                    }
                    bytes += key.utf8.count; try visit(child, depth: depth + 1)
                }
            } else if let array = item as? [Any] {
                guard array.count <= 128 else { throw Failure.metadataLimitExceeded }
                for child in array { try visit(child, depth: depth + 1) }
            } else if let data = item as? Data {
                guard data.count <= 65_536 - bytes else { throw Failure.metadataLimitExceeded }
                bytes += data.count
            } else if item is NSNumber || item is Date {
                guard bytes <= 65_520 else { throw Failure.metadataLimitExceeded }; bytes += 16
            } else { throw Failure.invalidMetadata }
        }
        try visit(value, depth: 0)
    }

    fileprivate struct DirectoryIdentity: Equatable, Sendable {
        let device: Int64; let inode: UInt64; let owner: UInt32; let mode: UInt16
        init(_ value: stat) {
            device = Int64(value.st_dev); inode = UInt64(value.st_ino)
            owner = value.st_uid; mode = value.st_mode
        }
    }

    private struct HeldDirectory {
        struct Node { let descriptor: Int32; let name: String?; let identity: DirectoryIdentity }
        let nodes: [Node]
        let path: String
        let privateLeaf: Bool
        var descriptor: Int32 { nodes.last!.descriptor }
        var leafIdentity: DirectoryIdentity { nodes.last!.identity }

        init(_ url: URL, privateLeaf: Bool = false) throws {
            let path = url.path
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard url.isFileURL, path.utf8.count < Int(MAXPATHLEN), parts.first == "",
                  parts.count > 1, parts.count <= 128,
                  parts.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  path.utf8.allSatisfy({ $0 >= 32 && $0 != 127 }) else { throw Failure.unsafeDirectory }
            var opened = [Node]()
            do {
                let root = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                guard root >= 0 else { throw Failure.io(errno) }
                do { opened.append(Node(descriptor: root, name: nil, identity: DirectoryIdentity(try metadata(root)))) }
                catch { Darwin.close(root); throw error }
                for part in parts.dropFirst() {
                    let name = String(part)
                    let parent = opened.last!.descriptor
                    let named = try namedMetadata(parent, name)
                    guard named.st_mode & S_IFMT == S_IFDIR else { throw Failure.unsafeDirectory }
                    let child = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                    guard child >= 0 else { throw Failure.io(errno) }
                    do {
                        let held = try metadata(child)
                        guard DirectoryIdentity(named) == DirectoryIdentity(held) else { throw Failure.directoryChanged }
                        opened.append(Node(descriptor: child, name: name, identity: DirectoryIdentity(held)))
                    } catch { Darwin.close(child); throw error }
                }
                self.nodes = opened; self.path = path; self.privateLeaf = privateLeaf
                try revalidate()
            } catch { for node in opened.reversed() { Darwin.close(node.descriptor) }; throw error }
        }

        func close() { for node in nodes.reversed() { Darwin.close(node.descriptor) } }

        func revalidate() throws {
            for (index, node) in nodes.enumerated() {
                guard DirectoryIdentity(try metadata(node.descriptor)) == node.identity else {
                    throw Failure.directoryChanged
                }
                if let name = node.name {
                    guard DirectoryIdentity(try namedMetadata(nodes[index - 1].descriptor, name)) == node.identity else {
                        throw Failure.directoryChanged
                    }
                }
            }
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let resolved = buffer.withUnsafeMutableBufferPointer { bytes -> String? in
                guard let base = bytes.baseAddress, Darwin.fcntl(descriptor, F_GETPATH, base) == 0 else {
                    return nil
                }
                return String(validatingCString: base)
            }
            guard resolved == path else { throw Failure.directoryChanged }
            if privateLeaf {
                let held = try metadata(descriptor)
                guard held.st_uid == Darwin.geteuid(), held.st_mode & 0o7777 == 0o700 else {
                    throw Failure.unsafeDirectory
                }
                do { try BelugaDescriptorACL.rejectAllowACL(descriptor) }
                catch { throw Failure.unsafeDirectory }
            }
        }
    }

    private struct Fingerprint: Equatable {
        let identity: DirectoryIdentity
        let links: UInt16; let size: Int64; let flags: UInt32
        let modified: Int64; let modifiedNanos: Int64; let changed: Int64; let changedNanos: Int64
        init(_ value: stat) {
            identity = DirectoryIdentity(value); links = value.st_nlink; size = value.st_size; flags = value.st_flags
            modified = Int64(value.st_mtimespec.tv_sec); modifiedNanos = Int64(value.st_mtimespec.tv_nsec)
            changed = Int64(value.st_ctimespec.tv_sec); changedNanos = Int64(value.st_ctimespec.tv_nsec)
        }
    }

    private final class Copier {
        private let deadline = ProcessInfo.processInfo.systemUptime + 120
        private var nodes = 0
        private var bytes: UInt64 = 0

        private func budget() throws {
            guard ProcessInfo.processInfo.systemUptime <= deadline, nodes <= 10_000,
                  bytes <= 2 * 1_024 * 1_024 * 1_024 else { throw Failure.limitExceeded }
        }

        func copyDirectory(_ source: Int32, into destination: Int32, depth: Int) throws {
            nodes += 1; try budget()
            guard depth <= 64 else { throw Failure.limitExceeded }
            let before = try metadata(source)
            guard before.st_mode & S_IFMT == S_IFDIR, before.st_mode & 0o7777 == 0o755 else {
                throw Failure.unsafeDirectory
            }
            try noAllowACL(source); try noAllowACL(destination)
            let names = try children(source)
            for name in names {
                try budget()
                let named = try namedMetadata(source, name)
                switch named.st_mode & S_IFMT {
                case S_IFDIR:
                    guard Darwin.mkdirat(destination, name, 0o700) == 0 else { throw Failure.io(errno) }
                    let from = Darwin.openat(source, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                    guard from >= 0 else { throw Failure.io(errno) }
                    defer { Darwin.close(from) }
                    let to = Darwin.openat(destination, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                    guard to >= 0 else { throw Failure.io(errno) }
                    defer { Darwin.close(to) }
                    guard Fingerprint(try metadata(from)) == Fingerprint(named) else { throw Failure.artifactChanged }
                    try copyDirectory(from, into: to, depth: depth + 1)
                case S_IFREG:
                    nodes += 1; try budget()
                    try copyFile(source, destination, name, named)
                case S_IFLNK:
                    nodes += 1; try budget()
                    try copyLink(source, destination, name, named)
                default: throw Failure.unsafeDirectory
                }
                guard Fingerprint(try namedMetadata(source, name)) == Fingerprint(named) else {
                    throw Failure.artifactChanged
                }
            }
            guard Fingerprint(try metadata(source)) == Fingerprint(before), try children(source) == names else {
                throw Failure.artifactChanged
            }
            guard Darwin.fchmod(destination, before.st_mode & 0o777) == 0, Darwin.fsync(destination) == 0 else {
                throw Failure.io(errno)
            }
            try noAllowACL(destination)
        }

        private func copyFile(_ source: Int32, _ destination: Int32, _ name: String, _ expected: stat) throws {
            guard expected.st_nlink == 1, expected.st_size >= 0,
                  UInt64(expected.st_size) <= 512 * 1_024 * 1_024,
                  [mode_t(0o644), mode_t(0o755)].contains(expected.st_mode & 0o7777),
                  UInt64(expected.st_size) <= 2 * 1_024 * 1_024 * 1_024 - bytes else {
                throw Failure.limitExceeded
            }
            bytes += UInt64(expected.st_size)
            let from = Darwin.openat(source, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            guard from >= 0 else { throw Failure.io(errno) }
            defer { Darwin.close(from) }
            guard Fingerprint(try metadata(from)) == Fingerprint(expected) else { throw Failure.artifactChanged }
            try noAllowACL(from)
            let to = Darwin.openat(destination, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard to >= 0 else { throw Failure.io(errno) }
            defer { Darwin.close(to) }
            try noAllowACL(to)
            var buffer = [UInt8](repeating: 0, count: 1_024 * 1_024)
            var remaining = UInt64(expected.st_size); var interruptions = 0
            while remaining > 0 {
                try budget()
                let wanted = Int(min(remaining, UInt64(buffer.count)))
                let read = buffer.withUnsafeMutableBytes { Darwin.read(from, $0.baseAddress, wanted) }
                if read < 0, errno == EINTR, interruptions < 16 { interruptions += 1; continue }
                guard read > 0, read <= wanted else { throw Failure.artifactChanged }
                var written = 0
                while written < read {
                    try budget()
                    let amount = buffer.withUnsafeBytes { Darwin.write(to, $0.baseAddress!.advanced(by: written), read - written) }
                    if amount < 0, errno == EINTR, interruptions < 16 { interruptions += 1; continue }
                    guard amount > 0, amount <= read - written else { throw Failure.io(errno) }
                    written += amount
                }
                remaining -= UInt64(read)
            }
            var extra: UInt8 = 0
            guard Darwin.read(from, &extra, 1) == 0,
                  Fingerprint(try metadata(from)) == Fingerprint(expected) else { throw Failure.artifactChanged }
            guard Darwin.fchmod(to, expected.st_mode & 0o777) == 0, Darwin.fsync(to) == 0 else {
                throw Failure.io(errno)
            }
            let copied = try metadata(to)
            guard copied.st_uid == Darwin.geteuid(), copied.st_nlink == 1,
                  copied.st_mode & 0o7777 == expected.st_mode & 0o777,
                  copied.st_size == expected.st_size else { throw Failure.artifactChanged }
        }

        private func copyLink(_ source: Int32, _ destination: Int32, _ name: String, _ expected: stat) throws {
            guard expected.st_size > 0, expected.st_size <= 4_096 else { throw Failure.limitExceeded }
            var buffer = [CChar](repeating: 0, count: 4_097)
            let count = buffer.withUnsafeMutableBufferPointer {
                Darwin.readlinkat(source, name, $0.baseAddress!, 4_096)
            }
            guard count == Int(expected.st_size), !buffer.prefix(count).contains(0),
                  Fingerprint(try namedMetadata(source, name)) == Fingerprint(expected) else {
                throw Failure.artifactChanged
            }
            guard buffer.withUnsafeBufferPointer({ Darwin.symlinkat($0.baseAddress!, destination, name) }) == 0,
                  Darwin.fchmodat(destination, name, expected.st_mode & 0o777, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw Failure.io(errno)
            }
        }

        private func children(_ directory: Int32) throws -> [String] {
            let copied = Darwin.openat(directory, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            guard copied >= 0 else { throw Failure.io(errno) }
            guard let stream = Darwin.fdopendir(copied) else {
                let error = errno; Darwin.close(copied); throw Failure.io(error)
            }
            defer { Darwin.closedir(stream) }
            var names = [(Data, String)](); var seen = Set<Data>()
            while true {
                try budget(); errno = 0
                guard let entry = Darwin.readdir(stream) else {
                    guard errno == 0 else { throw Failure.io(errno) }; break
                }
                let length = Int(entry.pointee.d_namlen)
                let bytes: Data? = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                    guard length > 0, length <= 255, length < raw.count, raw[length] == 0 else { return nil }
                    return Data(raw.prefix(length))
                }
                guard let raw = bytes, !raw.contains(0), !raw.contains(47),
                      let name = String(data: raw, encoding: .utf8) else { throw Failure.unsafeDirectory }
                if name == "." || name == ".." { continue }
                guard names.count < 10_000, seen.insert(raw).inserted else { throw Failure.limitExceeded }
                names.append((raw, name))
            }
            return names.sorted { $0.0.lexicographicallyPrecedes($1.0) }.map { $0.1 }
        }
    }

    private static func metadata(_ descriptor: Int32) throws -> stat {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0 else { throw Failure.io(errno) }
        return value
    }

    private static func namedMetadata(_ parent: Int32, _ name: String) throws -> stat {
        var value = stat()
        guard Darwin.fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else { throw Failure.io(errno) }
        return value
    }

    private static func noAllowACL(_ descriptor: Int32) throws {
        do { try BelugaDescriptorACL.rejectAllowACL(descriptor) }
        catch { throw Failure.unsafeDirectory }
    }

    private static func withFixture<T>(context: BelugaUpdateRuntimeContext, stagingParentURL: URL,
                                       _ body: () throws -> T) throws -> T {
        try withFixture(target: context.target, stagingParentURL: stagingParentURL, body)
    }

    private static func withFixture<T>(target: BelugaUpdateOperation.Target, stagingParentURL: URL,
                                       _ body: () throws -> T) throws -> T {
        let root = URL(fileURLWithPath: target.canonicalPath).deletingLastPathComponent()
        let prefix = "beluga-broker-artifact-fixture-"
        guard root.deletingLastPathComponent().path == "/private/tmp",
              root.lastPathComponent.hasPrefix(prefix),
              let uuid = UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))),
              root.lastPathComponent == prefix + uuid.uuidString,
              stagingParentURL.path == root.path + "/staging",
              target.effectiveUID == Darwin.geteuid() else { throw Failure.unsafeFixture }
        let held = try HeldDirectory(root, privateLeaf: true)
        defer { held.close() }
        do { let value = try body(); try held.revalidate(); return value }
        catch { let original = error; try held.revalidate(); throw original }
    }
}
