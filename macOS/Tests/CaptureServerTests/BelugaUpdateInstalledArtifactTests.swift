import Darwin
import Foundation
import Security
import XCTest
@testable import BelugaUpdateCore

final class BelugaUpdateInstalledArtifactTests: XCTestCase {
    private typealias Reader = BelugaUpdateInstalledArtifact
    private typealias Identity = BelugaUpdateOperation.ArtifactIdentity

    private struct Fixture {
        let root: URL
        let app: URL
        let executable: URL
        let context: BelugaUpdateRuntimeContext
        let info: [String: Any]

        func evidence() -> Reader.SignatureEvidence {
            .init(identifier: BelugaUpdateOperation.expectedBundleIdentifier,
                  teamIdentifier: BelugaUpdateOperation.expectedTeamIdentifier,
                  flags: SecCodeSignatureFlags.runtime.rawValue, mainExecutableURL: executable,
                  securedInfo: info, nativeCDHash: Data(repeating: 0x19, count: 20))
        }
    }

    private func metadata() -> [String: Any] {
        ["CFBundleIdentifier": BelugaUpdateOperation.expectedBundleIdentifier,
         "CFBundleExecutable": "CaptureServer", "CFBundleName": "Beluga Host",
         "CFBundleDisplayName": "Beluga Host", "CFBundleIconFile": "AppIcon.icns",
         "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "14.0",
         "LSUIElement": true, "OpensteamerMediaIntegrationVersion": 1,
         "BelugaPairedPhoneCatalogVersion": 1,
         "CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "100",
         "SUFeedURL": "https://updates.example.org/appcast.xml",
         "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
         "SUVerifyUpdateBeforeExtraction": true, "SURequireSignedFeed": true,
         "SUAllowsAutomaticUpdates": false]
    }

    private func fixture(prefix: String = "beluga-installed-artifact-fixture-") throws -> Fixture {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            let app = root.appendingPathComponent("Beluga.app", isDirectory: true)
            let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
            let home = root.appendingPathComponent("account-home", isDirectory: true)
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            let executable = macOS.appendingPathComponent("CaptureServer")
            try Data("unsigned-private-fixture\n".utf8).write(to: executable)
            let info = metadata()
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            let context = try XCTUnwrap(BelugaUpdateRuntimeContext.resolve(
                bundleIdentifier: BelugaUpdateOperation.expectedBundleIdentifier, bundleURL: app,
                inputs: .init(effectiveUID: Darwin.geteuid(), accountHomeDirectory: { _ in home })))
            return Fixture(root: root, app: app, executable: executable, context: context, info: info)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private func read(_ fixture: Fixture, expected: Identity? = nil,
                      evidence: Reader.SignatureEvidence? = nil) throws -> Identity {
        try Reader.verifyFixture(context: fixture.context, expected: expected) { url in
            XCTAssertEqual(url, fixture.app)
            return evidence ?? fixture.evidence()
        }
    }

    func testFixtureReadbackBindsSecuredVersionsActualExecutableAndFullTree() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let tree = try BelugaUpdateBundleTree.inspect(bundleURL: f.app)
        let expected = try Identity(version: "0.2.0", build: 100,
                                    executableSHA256: tree.executableSHA256,
                                    dependencyClosureSHA256: tree.bundleTreeSHA256)
        XCTAssertEqual(try read(f), expected)
        XCTAssertEqual(try read(f, expected: expected), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.context.fenceDirectoryURL.path))
    }

    func testReadbackCarriesTheSameSealedConfigurationAndNativeCodeHash() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let value = try Reader.readbackFixture(context: f.context) { _ in f.evidence() }
        XCTAssertEqual(value.identity, try read(f))
        XCTAssertEqual(value.configuration, try BelugaReleaseConfiguration(info: f.info))
        XCTAssertEqual(value.nativeCDHash, Data(repeating: 0x19, count: 20))
        for count in [0, 19, 21, 32] {
            var evidence = f.evidence()
            evidence.nativeCDHash = Data(repeating: 0x19, count: count)
            XCTAssertThrowsError(try read(f, evidence: evidence)) {
                XCTAssertEqual($0 as? Reader.Failure, .invalidSignatureEvidence)
            }
        }
        var zero = f.evidence()
        zero.nativeCDHash = Data(repeating: 0, count: 20)
        XCTAssertThrowsError(try read(f, evidence: zero)) {
            XCTAssertEqual($0 as? Reader.Failure, .invalidSignatureEvidence)
        }
    }

    func testExpectedCandidateRequiresAllFourIdentityFields() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let actual = try read(f)
        let wrong = [
            try Identity(version: "0.2.1", build: actual.build, executableSHA256: actual.executableSHA256,
                         dependencyClosureSHA256: actual.dependencyClosureSHA256),
            try Identity(version: actual.version, build: 101, executableSHA256: actual.executableSHA256,
                         dependencyClosureSHA256: actual.dependencyClosureSHA256),
            try Identity(version: actual.version, build: actual.build,
                         executableSHA256: String(repeating: "a", count: 64),
                         dependencyClosureSHA256: actual.dependencyClosureSHA256),
            try Identity(version: actual.version, build: actual.build, executableSHA256: actual.executableSHA256,
                         dependencyClosureSHA256: String(repeating: "b", count: 64))
        ]
        for candidate in wrong {
            XCTAssertThrowsError(try read(f, expected: candidate)) {
                XCTAssertEqual($0 as? Reader.Failure, .unexpectedArtifact)
            }
        }
    }

    func testOwnershipProtocolMustBeExplicitSealedKnownIntegerNotInferredFromHighBuild() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let old = try Reader.readbackFixture(context: f.context) { _ in f.evidence() }
        XCTAssertNil(old.updateOwnershipProtocol)
        var known = f.evidence()
        known.securedInfo["BelugaUpdateOwnershipProtocol"] = 1
        XCTAssertEqual(try Reader.readbackFixture(context: f.context) { _ in known }.updateOwnershipProtocol, 1)
        let invalidValues: [Any] = [true, "1", 0, 2, -1, 1.5, [1]]
        for invalid in invalidValues {
            var changed = f.evidence()
            changed.securedInfo["BelugaUpdateOwnershipProtocol"] = invalid
            XCTAssertThrowsError(try Reader.readbackFixture(context: f.context) { _ in changed }) {
                XCTAssertEqual($0 as? Reader.Failure, .invalidProductMetadata)
            }
        }
    }

    func testCatalogVersionMustBePresentExactIntegerNotInferredFromOwnershipOrHighBuild() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var evidence = f.evidence()
        evidence.securedInfo["BelugaUpdateOwnershipProtocol"] = 1
        evidence.securedInfo["CFBundleVersion"] = "1000000"
        XCTAssertEqual(try read(f, evidence: evidence).build, 1_000_000)
        evidence.securedInfo.removeValue(forKey: "BelugaPairedPhoneCatalogVersion")
        XCTAssertThrowsError(try read(f, evidence: evidence)) {
            XCTAssertEqual($0 as? Reader.Failure, .invalidProductMetadata)
        }
        let invalidValues: [Any] = [true, false, "1", 0, 2, -1, 1.0, Float(1), 1.5, [1], NSNull()]
        for invalid in invalidValues {
            evidence.securedInfo["BelugaPairedPhoneCatalogVersion"] = invalid
            XCTAssertThrowsError(try read(f, evidence: evidence)) {
                XCTAssertEqual($0 as? Reader.Failure, .invalidProductMetadata)
            }
        }
    }

    func testCatalogMarkerIsCoveredByFullTreeAndTamperingCannotVerifyCandidate() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let expected = try read(f)
        var changed = f.info
        changed["BelugaPairedPhoneCatalogVersion"] = 2
        try PropertyListSerialization.data(fromPropertyList: changed, format: .xml, options: 0)
            .write(to: f.app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertNotEqual(try BelugaUpdateBundleTree.inspect(bundleURL: f.app).bundleTreeSHA256,
                          expected.dependencyClosureSHA256)
        var evidence = f.evidence()
        evidence.securedInfo = changed
        XCTAssertThrowsError(try read(f, expected: expected, evidence: evidence)) {
            XCTAssertEqual($0 as? Reader.Failure, .invalidProductMetadata)
        }
    }

    func testSigningIdentityHardenedRuntimeAndNonAdHocAreRequired() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let changes: [(inout Reader.SignatureEvidence) -> Void] = [
            { $0.identifier = "other.identifier" }, { $0.teamIdentifier = "OTHERTEAM1" },
            { $0.flags = 0 }, { $0.flags |= SecCodeSignatureFlags.adhoc.rawValue },
            { $0.flags |= SecCodeSignatureFlags.linkerSigned.rawValue },
            { $0.mainExecutableURL = f.app.appendingPathComponent("Contents/MacOS/Other") },
            { $0.mainExecutableURL = URL(string: "https://example.org/CaptureServer")! }
        ]
        for change in changes {
            var evidence = f.evidence(); change(&evidence)
            XCTAssertThrowsError(try read(f, evidence: evidence)) {
                XCTAssertEqual($0 as? Reader.Failure, .invalidSignatureEvidence)
            }
        }
    }

    func testProductMetadataCannotChangeExecutableBundleOrPresentationIdentity() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let changes: [(String, Any)] = [
            ("CFBundleIdentifier", "wrong"), ("CFBundleExecutable", "../Other"),
            ("CFBundleName", "Other"), ("CFBundleDisplayName", "Other"),
            ("CFBundleIconFile", "Other.icns"), ("CFBundlePackageType", "BNDL"),
            ("LSMinimumSystemVersion", "13.0"), ("LSUIElement", false),
            ("LSUIElement", 1), ("OpensteamerMediaIntegrationVersion", true),
            ("OpensteamerMediaIntegrationVersion", 2)
        ]
        for (key, value) in changes {
            var evidence = f.evidence(); evidence.securedInfo[key] = value
            XCTAssertThrowsError(try read(f, evidence: evidence)) {
                XCTAssertEqual($0 as? Reader.Failure, .invalidProductMetadata)
            }
        }
    }

    func testCompleteCanonicalSignedUpdateConfigurationIsRequired() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let changes: [(String, Any)] = [
            ("CFBundleShortVersionString", "00.2.0"), ("CFBundleVersion", "0100"),
            ("CFBundleVersion", 100), ("SUFeedURL", "http://updates.example.org/appcast.xml"),
            ("SUFeedURL", "https://updates.example.org/appcast.xml?credential=x"),
            ("SUPublicEDKey", Data(repeating: 0, count: 32).base64EncodedString()),
            ("SURequireSignedFeed", false), ("SUVerifyUpdateBeforeExtraction", false),
            ("SUAllowsAutomaticUpdates", true), ("SURequireSignedFeed", 1)
        ]
        for (key, value) in changes {
            var evidence = f.evidence(); evidence.securedInfo[key] = value
            XCTAssertThrowsError(try read(f, evidence: evidence)) {
                XCTAssertEqual($0 as? Reader.Failure, .invalidUpdateConfiguration)
            }
        }
        var missing = f.evidence(); missing.securedInfo.removeValue(forKey: "SUPublicEDKey")
        XCTAssertThrowsError(try read(f, evidence: missing))
    }

    func testMetadataLimitsIncludeUnknownKeysNestedValuesAndRequiredStrings() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var oversized = f.evidence()
        oversized.securedInfo["Unrelated"] = String(repeating: "x", count: 65_537)
        XCTAssertThrowsError(try read(f, evidence: oversized)) {
            XCTAssertEqual($0 as? Reader.Failure, .metadataLimitExceeded)
        }
        var wide = f.evidence(); wide.securedInfo["Extra"] = Array(repeating: "x", count: 129)
        XCTAssertThrowsError(try read(f, evidence: wide))
        var deep: Any = "x"
        for _ in 0..<9 { deep = [deep] }
        var nested = f.evidence(); nested.securedInfo["Extra"] = deep
        XCTAssertThrowsError(try read(f, evidence: nested))
        var longVersion = f.evidence()
        longVersion.securedInfo["CFBundleShortVersionString"] = String(repeating: "1", count: 65)
        XCTAssertThrowsError(try read(f, evidence: longVersion)) {
            XCTAssertEqual($0 as? Reader.Failure, .invalidUpdateConfiguration)
        }
    }

    func testSecuredMetadataIsNotReadFromAConvenienceBundleCache() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var evidence = f.evidence(); evidence.securedInfo["CFBundleVersion"] = "101"
        XCTAssertEqual(try read(f, evidence: evidence).build, 101)
        // The injected dictionary represents native Security's sealed result; the
        // fixture seam does not pretend that these unsigned bytes are signed.
        let disk = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: f.app.appendingPathComponent("Contents/Info.plist")),
            options: [], format: nil) as? [String: Any]
        XCTAssertEqual(disk?["CFBundleVersion"] as? String, "100")
    }

    func testExecutableOrOtherBundleBytesChangingDuringVerificationAreRejected() throws {
        for changeExecutable in [true, false] {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            XCTAssertThrowsError(try Reader.verifyFixture(context: f.context) { _ in
                let changed = changeExecutable ? f.executable : f.app.appendingPathComponent("Contents/Extra.txt")
                try Data("changed\n".utf8).write(to: changed)
                return f.evidence()
            }) {
                XCTAssertEqual($0 as? Reader.Failure, .artifactChanged)
            }
        }
    }

    func testReplacedAppContextCannotAuthenticateTheNewDirectory() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        XCTAssertThrowsError(try Reader.verifyFixture(context: f.context) { _ in
            let displaced = f.root.appendingPathComponent("old.app")
            try FileManager.default.moveItem(at: f.app, to: displaced)
            try FileManager.default.copyItem(at: displaced, to: f.app)
            return f.evidence()
        }) {
            XCTAssertEqual($0 as? BelugaUpdateRuntimeContext.ResolutionError, .directoryIdentityChanged)
        }
    }

    func testInjectedVerifierIsLimitedToExactPrivateOwnedFixtureNamespace() throws {
        let f = try fixture(prefix: "beluga-other-fixture-")
        defer { try? FileManager.default.removeItem(at: f.root) }
        var invoked = false
        XCTAssertThrowsError(try Reader.verifyFixture(context: f.context) { _ in
            invoked = true; return f.evidence()
        }) {
            XCTAssertEqual($0 as? Reader.Failure, .unsafeFixture)
        }
        XCTAssertFalse(invoked)
    }

    func testFixtureRootMustRemainPrivateAndUnreplaced() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.root.path)
        XCTAssertThrowsError(try read(f)) {
            XCTAssertEqual($0 as? Reader.Failure, .unsafeFixture)
        }
    }

    func testActualNativeVerifierRejectsUnsignedPrivateBundleWithoutSigning() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        XCTAssertThrowsError(try Reader.verify(context: f.context)) {
            guard case Reader.Failure.signature = $0 else {
                return XCTFail("Unsigned fixture did not fail native Security validation: \($0)")
            }
        }
    }

    func testNativeRequirementPinsDeveloperIDAndUsesOfflineStrictNestedValidation() throws {
        XCTAssertTrue(Reader.signingRequirement.contains("identifier \"com.elamin.AudioStreamer.CaptureServer\""))
        XCTAssertTrue(Reader.signingRequirement.contains("certificate leaf[subject.OU] = \"MSMG8CJLB3\""))
        XCTAssertTrue(Reader.signingRequirement.contains("certificate leaf[field.1.2.840.113635.100.6.1.13] exists"))
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(Reader.signingRequirement as CFString, [], &requirement),
                       errSecSuccess)
        var rendered: CFString?
        XCTAssertEqual(SecRequirementCopyString(try XCTUnwrap(requirement), [], &rendered), errSecSuccess)
        XCTAssertTrue((try XCTUnwrap(rendered) as String).contains("1.2.840.113635.100.6.1.13"))
        XCTAssertEqual(Reader.validationFlags.rawValue,
                       kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate |
                           SecCSFlags.noNetworkAccess.rawValue)
    }
}
