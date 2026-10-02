import CoreFoundation
import Darwin
import Foundation
import Security

/// Static, local installed-byte readback only. The caller retains update ownership;
/// this does not authenticate a running menu, prove installer completion/readiness,
/// or replace the writable-install, closure-layout, Gatekeeper/notarization and
/// online revocation release gates. Equal tree observations are not an atomic
/// filesystem snapshot and do not promise protection against malicious ABA writes.
package enum BelugaUpdateInstalledArtifact {
    // Match the distribution verifier's Developer ID Application certificate class,
    // not any Apple-issued development certificate belonging to the same team.
    static let signingRequirement = "anchor apple generic and identifier \"com.elamin.AudioStreamer.CaptureServer\" and certificate leaf[subject.OU] = \"MSMG8CJLB3\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    static let validationFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures |
        kSecCSCheckNestedCode | kSecCSStrictValidate).union(.noNetworkAccess)

    package enum Failure: Error, Equatable {
        case signature(OSStatus)
        case invalidSignatureEvidence, invalidProductMetadata, invalidUpdateConfiguration
        case metadataLimitExceeded, artifactChanged, unexpectedArtifact, unsafeFixture
    }

    /// One coherent static readback. `nativeCDHash` is only an expectation for the
    /// separate kernel-token-bound live-code check; it is not running-code proof.
    package struct Verification: Equatable, Sendable {
        package let identity: BelugaUpdateOperation.ArtifactIdentity
        package let configuration: BelugaReleaseConfiguration
        package let nativeCDHash: Data
        /// Signed producer contract, not inferred from build number or missing
        /// state. Release admission must establish the first-shipped lineage.
        package let updateOwnershipProtocol: UInt64?
    }

    package static func verify(
        context: BelugaUpdateRuntimeContext,
        expected: BelugaUpdateOperation.ArtifactIdentity? = nil
    ) throws -> BelugaUpdateOperation.ArtifactIdentity {
        try readback(context: context, expected: expected).identity
    }

    package static func readback(
        context: BelugaUpdateRuntimeContext,
        expected: BelugaUpdateOperation.ArtifactIdentity? = nil
    ) throws -> Verification {
        try verifyBound(context: context, expected: expected, signatureVerifier: nativeSignature)
    }

    // Internal source-only injection: there is no package-visible verifier override.
    // The seam refuses every target except an exact, private, owned temporary fixture.
    struct SignatureEvidence {
        var identifier: String
        var teamIdentifier: String
        var flags: UInt32
        var mainExecutableURL: URL
        var securedInfo: [String: Any]
        var nativeCDHash: Data
    }

    static func verifyFixture(
        context: BelugaUpdateRuntimeContext,
        expected: BelugaUpdateOperation.ArtifactIdentity? = nil,
        signatureVerifier: (URL) throws -> SignatureEvidence
    ) throws -> BelugaUpdateOperation.ArtifactIdentity {
        try withOwnedFixture(context: context) {
            try verifyBound(context: context, expected: expected, signatureVerifier: signatureVerifier).identity
        }
    }

    static func readbackFixture(
        context: BelugaUpdateRuntimeContext,
        signatureVerifier: (URL) throws -> SignatureEvidence
    ) throws -> Verification {
        try withOwnedFixture(context: context) {
            try verifyBound(context: context, expected: nil, signatureVerifier: signatureVerifier)
        }
    }

    private static func verifyBound(
        context: BelugaUpdateRuntimeContext,
        expected: BelugaUpdateOperation.ArtifactIdentity?,
        signatureVerifier: (URL) throws -> SignatureEvidence
    ) throws -> Verification {
        try context.revalidate()
        let bundleURL = URL(fileURLWithPath: context.target.canonicalPath, isDirectory: true)
        do {
            let before = try BelugaUpdateBundleTree.inspect(bundleURL: bundleURL)
            let evidence = try signatureVerifier(bundleURL)
            guard evidence.identifier == context.target.bundleIdentifier,
                  evidence.teamIdentifier == context.target.teamIdentifier,
                  evidence.flags & SecCodeSignatureFlags.runtime.rawValue != 0,
                  evidence.flags & (SecCodeSignatureFlags.adhoc.rawValue | SecCodeSignatureFlags.linkerSigned.rawValue) == 0,
                  evidence.nativeCDHash.count == 20, evidence.nativeCDHash.contains(where: { $0 != 0 }),
                  evidence.mainExecutableURL.isFileURL,
                  evidence.mainExecutableURL.path == bundleURL.path + "/Contents/MacOS/CaptureServer" else {
                throw Failure.invalidSignatureEvidence
            }
            let configuration = try configuration(from: evidence.securedInfo)
            let ownershipProtocol: UInt64?
            if let value = evidence.securedInfo["BelugaUpdateOwnershipProtocol"] {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      let parsed = UInt64(number.stringValue), parsed == 1 else {
                    throw Failure.invalidProductMetadata
                }
                ownershipProtocol = parsed
            } else { ownershipProtocol = nil }
            let after = try BelugaUpdateBundleTree.inspect(bundleURL: bundleURL)
            try context.revalidate()
            guard before == after else { throw Failure.artifactChanged }
            let identity = try BelugaUpdateOperation.ArtifactIdentity(
                version: configuration.version, build: configuration.build,
                executableSHA256: after.executableSHA256,
                dependencyClosureSHA256: after.bundleTreeSHA256)
            if let expected, expected != identity { throw Failure.unexpectedArtifact }
            return Verification(identity: identity, configuration: configuration,
                                nativeCDHash: evidence.nativeCDHash, updateOwnershipProtocol: ownershipProtocol)
        } catch {
            let originalError = error
            try context.revalidate()
            throw originalError
        }
    }

    private static func nativeSignature(_ bundleURL: URL) throws -> SignatureEvidence {
        var code: SecStaticCode?
        let creation = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code)
        guard creation == errSecSuccess, let code else { throw Failure.signature(creation) }
        // Fixed requirement syntax; no caller-controlled values are interpolated.
        var requirement: SecRequirement?
        let compilation = SecRequirementCreateWithString(signingRequirement as CFString, [], &requirement)
        guard compilation == errSecSuccess, let requirement else { throw Failure.signature(compilation) }
        let validation = SecStaticCodeCheckValidity(code, validationFlags, requirement)
        guard validation == errSecSuccess else { throw Failure.signature(validation) }
        var dictionary: CFDictionary?
        let copy = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &dictionary)
        guard copy == errSecSuccess else { throw Failure.signature(copy) }
        guard let values = dictionary as? [String: Any],
              let identifier = values[kSecCodeInfoIdentifier as String] as? String,
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              let number = values[kSecCodeInfoFlags as String] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let rawFlags = UInt32(number.stringValue), String(rawFlags) == number.stringValue,
              let executable = values[kSecCodeInfoMainExecutable as String] as? URL,
              let info = values[kSecCodeInfoPList as String] as? [String: Any],
              let cdHash = values[kSecCodeInfoUnique as String] as? Data,
              cdHash.count == 20 else {
            throw Failure.invalidSignatureEvidence
        }
        // Security returns the sealed plist, not CFBundle's mutable/cached dictionary.
        return SignatureEvidence(identifier: identifier, teamIdentifier: team, flags: rawFlags,
                                 mainExecutableURL: executable, securedInfo: info, nativeCDHash: cdHash)
    }

    private static func configuration(from info: [String: Any]) throws -> BelugaReleaseConfiguration {
        try metadataBudget(info)
        let product: [String: String] = [
            "CFBundleIdentifier": BelugaUpdateOperation.expectedBundleIdentifier,
            "CFBundleExecutable": "CaptureServer", "CFBundleName": "Beluga Host",
            "CFBundleDisplayName": "Beluga Host", "CFBundleIconFile": "AppIcon.icns",
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "14.0"
        ]
        guard product.allSatisfy({ info[$0.key] as? String == $0.value }),
              exactBoolean(info["LSUIElement"], expected: true),
              let integration = info["OpensteamerMediaIntegrationVersion"] as? NSNumber,
              CFGetTypeID(integration) != CFBooleanGetTypeID(), integration.stringValue == "1" else {
            throw Failure.invalidProductMetadata
        }
        // The signed v2 producer requires catalog1; neither updater ownership nor
        // a high build number proves that an app can preserve migrated phone records.
        guard let catalog = info["BelugaPairedPhoneCatalogVersion"] as? NSNumber,
              CFGetTypeID(catalog) != CFBooleanGetTypeID(),
              ["c", "C", "s", "S", "i", "I", "l", "L", "q", "Q"]
                .contains(String(cString: catalog.objCType)), catalog.stringValue == "1" else {
            throw Failure.invalidProductMetadata
        }
        let limits = ["CFBundleShortVersionString": 64, "CFBundleVersion": 20,
                      "SUFeedURL": 2_048, "SUPublicEDKey": 44]
        guard limits.allSatisfy({ key, limit in
            guard let value = info[key] as? String else { return false }
            return !value.isEmpty && value.utf8.count <= limit &&
                value.utf8.allSatisfy { $0 >= 32 && $0 < 127 }
        }), exactBoolean(info["SUVerifyUpdateBeforeExtraction"], expected: true),
            exactBoolean(info["SURequireSignedFeed"], expected: true),
            exactBoolean(info["SUAllowsAutomaticUpdates"], expected: false) else {
            throw Failure.invalidUpdateConfiguration
        }
        do { return try BelugaReleaseConfiguration(info: info) }
        catch { throw Failure.invalidUpdateConfiguration }
    }

    private static func exactBoolean(_ value: Any?, expected: Bool) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue == expected
    }

    /// Bound the sealed dictionary before interpreting metadata. Normal plist shapes
    /// are accepted; unknown keys do not grant authority or evade the total budget.
    private static func metadataBudget(_ info: [String: Any]) throws {
        var nodes = 0
        var bytes = 0
        func charge(_ count: Int) throws {
            guard count <= 65_536 - bytes else { throw Failure.metadataLimitExceeded }
            bytes += count
        }
        func visit(_ value: Any, depth: Int) throws {
            nodes += 1
            guard nodes <= 512, depth <= 8 else { throw Failure.metadataLimitExceeded }
            if let string = value as? String {
                try charge(string.utf8.count)
            } else if let dictionary = value as? [String: Any] {
                guard dictionary.count <= 64 else { throw Failure.metadataLimitExceeded }
                for (key, child) in dictionary {
                    guard key.utf8.count <= 128 else { throw Failure.metadataLimitExceeded }
                    try charge(key.utf8.count)
                    try visit(child, depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                guard array.count <= 128 else { throw Failure.metadataLimitExceeded }
                for child in array { try visit(child, depth: depth + 1) }
            } else if let data = value as? Data {
                try charge(data.count)
            } else if value is NSNumber || value is Date {
                try charge(16)
            } else { throw Failure.invalidProductMetadata }
        }
        try visit(info, depth: 0)
    }

    private static func withOwnedFixture<T>(context: BelugaUpdateRuntimeContext,
                                            _ body: () throws -> T) throws -> T {
        let app = URL(fileURLWithPath: context.target.canonicalPath, isDirectory: true)
        let root = app.deletingLastPathComponent()
        let prefix = "beluga-installed-artifact-fixture-"
        guard app.lastPathComponent == "Beluga.app", root.deletingLastPathComponent().path == "/private/tmp",
              root.lastPathComponent.hasPrefix(prefix),
              let uuid = UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))),
              root.lastPathComponent == prefix + uuid.uuidString,
              context.target.effectiveUID == Darwin.geteuid() else { throw Failure.unsafeFixture }
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure.unsafeFixture }
        defer { Darwin.close(descriptor) }
        var original = stat()
        guard Darwin.fstat(descriptor, &original) == 0, original.st_uid == Darwin.geteuid(),
              original.st_mode & S_IFMT == S_IFDIR, original.st_mode & 0o777 == 0o700 else {
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
        do {
            let result = try body()
            try revalidate()
            return result
        } catch {
            let originalError = error
            try revalidate()
            throw originalError
        }
    }
}
