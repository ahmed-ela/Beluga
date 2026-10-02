import BelugaUpdateCore
import Foundation
import Sparkle
import XCTest
@testable import BelugaUpdateDriver

final class BelugaUpdateCandidateMetadataTests: XCTestCase {
    private typealias Metadata = BelugaUpdateCandidateMetadata
    private let executable = String(repeating: "a", count: 64)
    private let tree = String(repeating: "b", count: 64)

    func testExactSignedApplicationIdentityUsesFullAppTreeAsClosure() throws {
        let identity = try Metadata.parse(input())
        XCTAssertEqual(identity, try BelugaUpdateOperation.ArtifactIdentity(version: "1.2.3", build: 102,
            executableSHA256: executable, dependencyClosureSHA256: tree))
        XCTAssertNotEqual(identity.executableSHA256, identity.dependencyClosureSHA256)
    }

    func testOnlyPositiveSignatureStatusAdmitsMetadata() {
        for status in [SPUAppcastSigningValidationStatus.skipped.rawValue,
                       SPUAppcastSigningValidationStatus.failed.rawValue, -1, 3, Int.max] {
            var fixture = input()
            fixture.signingStatus = status
            rejects(fixture, .unverifiedFeed)
        }
    }

    func testActualPublicEmptyItemIsNotSignedMetadataAuthority() {
        XCTAssertThrowsError(try Metadata.parse(SUAppcastItem.empty())) { error in
            XCTAssertEqual(error as? Metadata.Failure, .unverifiedFeed)
        }
    }

    func testPackageDeltaAndUnknownInstallationKindsAreRejected() {
        for kind in ["package", "guided-package", "interactive-package", "Application", "", "application "] {
            var fixture = input()
            fixture.installationType = kind
            rejects(fixture, .unsupportedInstallation)
        }
        var delta = input()
        delta.isDelta = true
        rejects(delta, .unsupportedInstallation)
        delta = input()
        delta.hasDeltaUpdates = true
        rejects(delta, .unsupportedInstallation)
        var informational = input()
        informational.isInformationOnly = true
        rejects(informational, .unsupportedInstallation)
    }

    func testEveryCustomAttributeIsMandatoryAndUnknownBelugaAttributesAreRejected() {
        for key in Metadata.customKeys {
            var values = enclosure()
            values.removeValue(forKey: key)
            rejects(input(enclosure: values), .unexpectedMetadata)
        }
        for key in ["beluga:futureAuthority", "beluga:ArtifactSchema", "beluga:"] {
            var values = enclosure()
            values[key] = "anything"
            rejects(input(enclosure: values), .unexpectedMetadata)
        }
    }

    func testMetadataCannotBeMovedToItemOrUnsignedSidecarLocation() {
        var properties = properties()
        properties["beluga:artifactSchema"] = Metadata.schema
        rejects(input(properties: properties), .unexpectedMetadata)
        properties = self.properties()
        properties.removeValue(forKey: "enclosure")
        properties["package.json"] = enclosure()
        rejects(input(properties: properties), .invalidDictionary)
    }

    func testLexicalNamespaceAliasesCannotSupplyMissingPinnedAttribute() {
        for prefix in ["alternate:", "", "Beluga:"] {
            var values = enclosure()
            values.removeValue(forKey: "beluga:artifactSchema")
            values[prefix + "artifactSchema"] = Metadata.schema
            rejects(input(enclosure: values), .unexpectedMetadata)
        }
    }

    func testMetadataTypesAreStringsNotNumbersNullContainersOrData() {
        let replacements: [Any] = [NSNumber(value: 102), NSNull(), [], ["value": "x"], Data([0x61])]
        for key in Metadata.customKeys {
            for replacement in replacements {
                var values = enclosure()
                values[key] = replacement
                rejects(input(enclosure: values), .invalidDictionary)
            }
        }
        for key in ["sparkle:version", "sparkle:shortVersionString"] {
            var properties = properties()
            properties[key] = NSNumber(value: 102)
            rejects(input(properties: properties), .invalidDictionary)
        }
    }

    func testSchemaAndAlgorithmAreExactNotVersionGuessed() {
        for schema in ["", "beluga.update-candidate.v1", "beluga.update-candidate.v3", "beluga.update-candidate.v2 "] {
            var values = enclosure()
            values["beluga:artifactSchema"] = schema
            rejects(input(enclosure: values), .invalidSchema)
        }
        for algorithm in ["", "sha256", "beluga.bundle-tree-json-v2", "beluga.bundle-tree-json-v1\n"] {
            var values = enclosure()
            values["beluga:bundleTreeAlgorithm"] = algorithm
            rejects(input(enclosure: values), .invalidAlgorithm)
        }
    }

    func testSignedSingleViewerSchemaIsRejectedEvenWithAHigherOrMaximumBuild() throws {
        for rawBuild in ["1000000", String(UInt64.max)] {
            var properties = self.properties()
            properties["sparkle:version"] = rawBuild
            var old = enclosure()
            old["beluga:artifactSchema"] = "beluga.update-candidate.v1"
            properties["enclosure"] = old
            var fixture = input(properties: properties)
            fixture.versionString = rawBuild
            rejects(fixture, .invalidSchema)

            old["beluga:artifactSchema"] = "beluga.update-candidate.v2"
            properties["enclosure"] = old
            fixture.properties = properties
            XCTAssertEqual(try Metadata.parse(fixture).build, try XCTUnwrap(UInt64(rawBuild)))
        }
    }

    func testDigestsAreExactlyLowercaseHex64() {
        for key in ["beluga:executableSHA256", "beluga:bundleTreeSHA256"] {
            for digest in ["", String(repeating: "a", count: 63), String(repeating: "A", count: 64),
                           String(repeating: "g", count: 64), String(repeating: "á", count: 32)] {
                var values = enclosure()
                values[key] = digest
                rejects(input(enclosure: values), .invalidDigest)
            }
            var values = enclosure()
            values[key] = String(repeating: "a", count: 65)
            rejects(input(enclosure: values), .oversizedMetadata)
        }
    }

    func testCanonicalPositiveUInt64BuildAndExactItemAgreement() {
        for build in ["", "0", "0102", "+102", "-102", "102 ", "102\n", "1.02", "١٠٢",
                      "18446744073709551616"] {
            var properties = properties()
            properties["sparkle:version"] = build
            rejects(input(properties: properties), .invalidBuild)
        }
        var fixture = input()
        fixture.versionString = "103"
        rejects(fixture, .inconsistentItem)
        var properties = properties()
        properties["sparkle:version"] = String(UInt64.max)
        fixture = input(properties: properties)
        fixture.versionString = String(UInt64.max)
        XCTAssertEqual(try? Metadata.parse(fixture).build, UInt64.max)
    }

    func testCanonicalSemanticVersionAndExactDisplayAgreement() {
        for version in ["", "1", "1.2", "1.2.3.4", "01.2.3", "1.02.3", "1.2.03", "1.2.3-beta",
                        "v1.2.3", "1.2.3 ", "1.2.3\n", "4294967296.2.3"] {
            var properties = properties()
            properties["sparkle:shortVersionString"] = version
            rejects(input(properties: properties), .invalidVersion)
        }
        var fixture = input()
        fixture.displayVersionString = "1.2.4"
        rejects(fixture, .inconsistentItem)
    }

    func testFallbackOrConflictingVersionLocationsAndDeltaGraphAreRejected() {
        for key in ["sparkle:version", "sparkle:shortVersionString", "sparkle:deltaFrom",
                    "sparkle:deltaFromSparkleExecutableSize"] {
            var values = enclosure()
            values[key] = "102"
            rejects(input(enclosure: values), .unexpectedMetadata)
        }
        for key in ["sparkle:version", "sparkle:shortVersionString"] {
            var properties = properties()
            properties.removeValue(forKey: key)
            rejects(input(properties: properties), .invalidDictionary)
        }
        var properties = properties()
        properties["sparkle:deltas"] = []
        rejects(input(properties: properties), .unexpectedMetadata)
    }

    func testExplicitApplicationTypeCannotDisagreeWithPublicItem() {
        var values = enclosure()
        values["sparkle:installationType"] = "application"
        XCTAssertNoThrow(try Metadata.parse(input(enclosure: values)))
        let kinds: [Any] = ["package", "application ", NSNumber(value: 1)]
        for kind in kinds {
            values["sparkle:installationType"] = kind
            rejects(input(enclosure: values), .unsupportedInstallation)
        }
    }

    func testDictionaryCountKeyAndRequiredValueBoundsFailClosed() {
        var properties = properties()
        for index in 0..<Metadata.maximumItemFields { properties["field-\(index)"] = "x" }
        rejects(input(properties: properties), .oversizedMetadata)
        var values = enclosure()
        for index in 0..<Metadata.maximumEnclosureFields { values["field-\(index)"] = "x" }
        rejects(input(enclosure: values), .oversizedMetadata)
        values = enclosure()
        values[String(repeating: "x", count: Metadata.maximumKeyBytes + 1)] = "x"
        rejects(input(enclosure: values), .oversizedMetadata)
        for key in ["sparkle:version", "sparkle:shortVersionString"] {
            properties = self.properties()
            properties[key] = String(repeating: "9", count: 65)
            rejects(input(properties: properties), .oversizedMetadata)
        }
        for key in ["beluga:artifactSchema", "beluga:bundleTreeAlgorithm"] {
            values = enclosure()
            values[key] = String(repeating: "x", count: 65)
            rejects(input(enclosure: values), .oversizedMetadata)
        }
    }

    func testWrongDictionaryShapesAndNonStringKeysAreRejected() {
        var fixture = input()
        fixture.properties = ["enclosure"]
        rejects(fixture, .invalidDictionary)
        var properties = properties()
        properties["enclosure"] = NSNull()
        rejects(input(properties: properties), .invalidDictionary)
        var mixed: [AnyHashable: Any] = enclosure().reduce(into: [:]) { $0[$1.key] = $1.value }
        mixed[NSNumber(value: 7)] = "x"
        properties["enclosure"] = mixed
        rejects(input(properties: properties), .invalidDictionary)
    }

    private func rejects(_ input: Metadata.Input, _ expected: Metadata.Failure,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try Metadata.parse(input), file: file, line: line) {
            XCTAssertEqual($0 as? Metadata.Failure, expected, file: file, line: line)
        }
    }

    private func input(properties: Any? = nil, enclosure: [String: Any]? = nil) -> Metadata.Input {
        Metadata.Input(signingStatus: SPUAppcastSigningValidationStatus.succeeded.rawValue,
                       installationType: "application", isDelta: false, versionString: "102",
                       displayVersionString: "1.2.3",
                       properties: properties ?? self.properties(enclosure: enclosure))
    }

    private func properties(enclosure: [String: Any]? = nil) -> [String: Any] {
        ["sparkle:version": "102", "sparkle:shortVersionString": "1.2.3",
         "enclosure": enclosure ?? self.enclosure()]
    }

    private func enclosure() -> [String: Any] {
        ["url": "https://github.com/ahmed-ela/Beluga/releases/download/mac-v1.2.3/Beluga-Mac-1.2.3-102.dmg",
         "length": "12345", "type": "application/octet-stream", "sparkle:edSignature": "archive-signature",
         "beluga:artifactSchema": Metadata.schema, "beluga:executableSHA256": executable,
         "beluga:bundleTreeSHA256": tree, "beluga:bundleTreeAlgorithm": Metadata.treeAlgorithm]
    }
}
