import BelugaUpdateCore
import Foundation
import Sparkle

/// Feed identity is a pre-install expectation, not proof of archive or installed bytes.
package enum BelugaUpdateCandidateMetadata {
    package enum Failure: Error, Equatable {
        case unverifiedFeed, unsupportedInstallation, invalidDictionary
        case oversizedMetadata, unexpectedMetadata, invalidVersion, invalidBuild
        case inconsistentItem, invalidSchema, invalidAlgorithm, invalidDigest
    }

    static let schema = "beluga.update-candidate.v1"
    static let treeAlgorithm = BelugaUpdateBundleTree.algorithm
    static let customKeys: Set<String> = [
        "beluga:artifactSchema", "beluga:executableSHA256",
        "beluga:bundleTreeSHA256", "beluga:bundleTreeAlgorithm"
    ]
    static let maximumItemFields = 64
    static let maximumEnclosureFields = 16
    static let maximumKeyBytes = 128

    /// Caller supplies the current native feed-callback item, not a decoded saved item.
    package static func parse(_ item: SUAppcastItem) throws -> BelugaUpdateOperation.ArtifactIdentity {
        // Sparkle can expose items from its failed-signature fallback mode.
        guard item.signingValidationStatus == .succeeded else { throw Failure.unverifiedFeed }
        return try parse(Input(signingStatus: item.signingValidationStatus.rawValue,
                               installationType: item.installationType,
                               isDelta: item.isDeltaUpdate,
                               hasDeltaUpdates: !(item.deltaUpdates?.isEmpty ?? true),
                               isInformationOnly: item.isInformationOnlyUpdate,
                               versionString: item.versionString,
                               displayVersionString: item.displayVersionString,
                               properties: item.propertiesDictionary))
    }

    /// Pure fixture seam; only the package entrypoint accepts real Sparkle items.
    struct Input {
        var signingStatus: Int
        var installationType: String
        var isDelta: Bool
        var hasDeltaUpdates = false
        var isInformationOnly = false
        var versionString: String
        var displayVersionString: String
        var properties: Any
    }

    static func parse(_ input: Input) throws -> BelugaUpdateOperation.ArtifactIdentity {
        guard input.signingStatus == SPUAppcastSigningValidationStatus.succeeded.rawValue else {
            throw Failure.unverifiedFeed
        }
        guard input.installationType == "application", !input.isDelta,
              !input.hasDeltaUpdates, !input.isInformationOnly else {
            throw Failure.unsupportedInstallation
        }
        let properties = try dictionary(input.properties, maximumFields: maximumItemFields)
        guard !properties.keys.contains(where: { $0.hasPrefix("beluga:") }),
              properties["sparkle:deltas"] == nil else { throw Failure.unexpectedMetadata }
        guard let rawEnclosure = properties["enclosure"] else { throw Failure.invalidDictionary }
        let enclosure = try dictionary(rawEnclosure, maximumFields: maximumEnclosureFields)
        // Public Sparkle dictionaries retain lexical custom keys, but not namespace URIs.
        let presentCustomKeys = Set(enclosure.keys.filter { $0.hasPrefix("beluga:") })
        guard presentCustomKeys == customKeys else { throw Failure.unexpectedMetadata }
        // Pin the producer's single version location; do not borrow Sparkle's fallbacks.
        guard enclosure["sparkle:version"] == nil,
              enclosure["sparkle:shortVersionString"] == nil,
              !enclosure.keys.contains(where: { $0.hasPrefix("sparkle:delta") }) else {
            throw Failure.unexpectedMetadata
        }
        if let declaredType = enclosure["sparkle:installationType"] {
            guard declaredType as? String == "application" else {
                throw Failure.unsupportedInstallation
            }
        }
        let version = try string(properties["sparkle:shortVersionString"], maximumBytes: 64)
        guard isCanonicalVersion(version) else { throw Failure.invalidVersion }
        let rawBuild = try string(properties["sparkle:version"], maximumBytes: 20)
        guard let build = UInt64(rawBuild), build > 0, String(build) == rawBuild else {
            throw Failure.invalidBuild
        }
        guard input.versionString == rawBuild, input.displayVersionString == version else {
            throw Failure.inconsistentItem
        }
        guard try string(enclosure["beluga:artifactSchema"], maximumBytes: 64) == schema else {
            throw Failure.invalidSchema
        }
        guard try string(enclosure["beluga:bundleTreeAlgorithm"], maximumBytes: 64) == treeAlgorithm else {
            throw Failure.invalidAlgorithm
        }
        let executable = try string(enclosure["beluga:executableSHA256"], maximumBytes: 64)
        let tree = try string(enclosure["beluga:bundleTreeSHA256"], maximumBytes: 64)
        guard isCanonicalDigest(executable), isCanonicalDigest(tree) else {
            throw Failure.invalidDigest
        }
        // v1 deliberately binds the full app tree, including all bundled code/resources.
        return try BelugaUpdateOperation.ArtifactIdentity(version: version, build: build,
            executableSHA256: executable, dependencyClosureSHA256: tree)
    }

    private static func dictionary(_ value: Any, maximumFields: Int) throws -> [String: Any] {
        guard let raw = value as? NSDictionary else { throw Failure.invalidDictionary }
        guard raw.count <= maximumFields else { throw Failure.oversizedMetadata }
        var result = [String: Any]()
        for (key, value) in raw {
            guard let key = key as? String, !key.isEmpty else { throw Failure.invalidDictionary }
            guard key.utf8.count <= maximumKeyBytes else { throw Failure.oversizedMetadata }
            guard result[key] == nil else { throw Failure.invalidDictionary }
            result[key] = value
        }
        return result
    }

    private static func string(_ value: Any?, maximumBytes: Int) throws -> String {
        guard let result = value as? String else { throw Failure.invalidDictionary }
        guard result.utf8.count <= maximumBytes else { throw Failure.oversizedMetadata }
        return result
    }

    private static func isCanonicalVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 3 && components.allSatisfy {
            guard let component = UInt32($0) else { return false }
            return String(component) == $0
        }
    }

    private static func isCanonicalDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}
