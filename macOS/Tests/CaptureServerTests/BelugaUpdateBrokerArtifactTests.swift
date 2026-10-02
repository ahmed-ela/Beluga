import CryptoKit
import Darwin
import Foundation
import Security
import XCTest
@testable import BelugaUpdateCore

/// Private unsigned fixtures only. Native signature rejection is tested without signing,
/// and positive fake-boundary cases never launch an app or access an installed target.
final class BelugaUpdateBrokerArtifactTests: XCTestCase {
    private typealias Artifact = BelugaUpdateBrokerArtifact

    func testCopiesWholeTreeModesRawLinksAndReturnsStaticIdentity() throws {
        let f = try Fixture(); defer { f.remove() }
        let original = try BelugaUpdateBundleTree.inspect(bundleURL: f.broker, executable: .broker)
        let staged = try stage(f)
        XCTAssertEqual(staged.operationID, f.operationID)
        XCTAssertEqual(staged.bundleURL.path,
                       f.staging.path + "/broker-" + f.operationID.uuidString + "/BelugaUpdater.app")
        XCTAssertEqual(staged.executableURL.path, staged.bundleURL.path + "/Contents/MacOS/BelugaUpdater")
        XCTAssertEqual(staged.identity.executableSHA256, original.executableSHA256)
        XCTAssertEqual(staged.identity.dependencyClosureSHA256, original.bundleTreeSHA256)
        XCTAssertEqual(staged.nativeCDHash, Data(repeating: 7, count: 20))
        XCTAssertEqual(try BelugaUpdateBundleTree.inspect(bundleURL: staged.bundleURL, executable: .broker), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(
            atPath: staged.bundleURL.appendingPathComponent("Contents/Resources/alias").path), "signed-resource")
        try Artifact.verifyStagedFixture(context: f.context, parentConfiguration: f.configuration,
                                          staged: staged, signatureVerifier: f.evidence)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.context.fenceDirectoryURL.path))
    }

    func testFreshOperationDirectoryIsExclusiveAndNeverReused() throws {
        let f = try Fixture(); defer { f.remove() }
        let first = try stage(f)
        XCTAssertThrowsError(try stage(f)) {
            XCTAssertEqual($0 as? Artifact.Failure, .collision)
        }
        XCTAssertEqual(try Data(contentsOf: first.executableURL), Fixture.executableBytes)
        XCTAssertEqual(try Data(contentsOf: f.broker.appendingPathComponent("Contents/MacOS/BelugaUpdater")),
                       Fixture.executableBytes)
    }

    func testEmbeddedReadbackAndRetainedCopyMatchExactPreStartupBinding() throws {
        let f = try Fixture(); defer { f.remove() }
        let embedded = try Artifact.readbackEmbeddedFixture(context: f.context,
            configuration: f.configuration, signatureVerifier: f.evidence)
        let staged = try stage(f)
        XCTAssertEqual(embedded.identity, staged.identity)
        XCTAssertEqual(embedded.nativeCDHash, staged.nativeCDHash)
        XCTAssertEqual(embedded.executableURL.path, f.broker.path + "/Contents/MacOS/BelugaUpdater")
        let readback = try retained(f, staged: staged)
        XCTAssertEqual(readback.identity, staged.identity)
        XCTAssertEqual(readback.nativeCDHash, staged.nativeCDHash)
        XCTAssertEqual(readback.executableURL, staged.executableURL)
    }

    func testRetainedReadbackDoesNotRequireRemovedPredecessorAppInodeOrInferNewEmbeddedBroker() throws {
        let f = try Fixture(); defer { f.remove() }
        let staged = try stage(f)
        let old = f.root.appendingPathComponent("old-main.app", isDirectory: true)
        try FileManager.default.moveItem(at: f.app, to: old)
        try FileManager.default.createDirectory(at: f.app, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o755])
        XCTAssertThrowsError(try f.context.revalidate())
        let readback = try retained(f, staged: staged)
        XCTAssertEqual(readback.identity, staged.identity)
        XCTAssertEqual(readback.executableURL, staged.executableURL)
    }

    func testRetainedReadbackRejectsWrongImmutableBrokerExpectationsAndConfiguration() throws {
        let f = try Fixture(); defer { f.remove() }
        let staged = try stage(f)
        let mismatches = [
            try BelugaUpdateOperation.BrokerBinding(artifact: staged.identity,
                                                    nativeCDHash: Data(repeating: 9, count: 20)),
            try BelugaUpdateOperation.BrokerBinding(artifact: .init(version: staged.identity.version,
                build: staged.identity.build, executableSHA256: String(repeating: "a", count: 64),
                dependencyClosureSHA256: staged.identity.dependencyClosureSHA256), nativeCDHash: staged.nativeCDHash),
            try BelugaUpdateOperation.BrokerBinding(artifact: .init(version: staged.identity.version,
                build: staged.identity.build, executableSHA256: staged.identity.executableSHA256,
                dependencyClosureSHA256: String(repeating: "b", count: 64)), nativeCDHash: staged.nativeCDHash)
        ]
        for mismatch in mismatches {
            XCTAssertThrowsError(try retained(f, staged: staged, expected: mismatch)) {
                XCTAssertEqual($0 as? Artifact.Failure, .artifactChanged)
            }
        }
        for (key, value) in [("CFBundleVersion", "101"), ("CFBundleShortVersionString", "0.2.1"),
                             ("SUFeedURL", "https://other.example.org/appcast.xml"),
                             ("SUPublicEDKey", Data(repeating: 8, count: 32).base64EncodedString())] {
            var info = f.info; info[key] = value
            let configuration = try BelugaReleaseConfiguration(info: info)
            XCTAssertThrowsError(try retained(f, staged: staged, configuration: configuration)) {
                XCTAssertEqual($0 as? Artifact.Failure, .configurationMismatch)
            }
        }
    }

    func testRetainedReadbackRejectsTamperingWrongSignatureAndChangedCDHash() throws {
        for mode in 0..<4 {
            let f = try Fixture(); defer { f.remove() }
            let staged = try stage(f)
            if mode == 0 { try Data("changed executable".utf8).write(to: staged.executableURL) }
            if mode == 1 {
                try Data("changed resource".utf8).write(to: staged.bundleURL
                    .appendingPathComponent("Contents/Resources/signed-resource"))
            }
            XCTAssertThrowsError(try retained(f, staged: staged, evidence: { url in
                if mode == 2 { throw Artifact.Failure.signature(errSecCSUnsigned) }
                var value = try f.evidence(url)
                if mode == 3 { value.cdHash = Data(repeating: 9, count: 20) }
                return value
            }))
        }
    }

    func testRetainedReadbackDetectsDirectoryReplacementDuringSignatureRead() throws {
        let f = try Fixture(); defer { f.remove() }
        let staged = try stage(f)
        var replaced = false
        XCTAssertThrowsError(try retained(f, staged: staged, evidence: { url in
            if !replaced {
                replaced = true
                let operation = staged.bundleURL.deletingLastPathComponent()
                let moved = f.staging.appendingPathComponent("old-operation")
                try FileManager.default.moveItem(at: operation, to: moved)
                try FileManager.default.copyItem(at: moved, to: operation)
            }
            return try f.evidence(url)
        })) {
            XCTAssertEqual($0 as? Artifact.Failure, .directoryChanged)
        }
    }

    func testRetainedReadbackRejectsUnsafeOperationParentAliasesAndMissingOrZeroOperation() throws {
        for mode in 0..<4 {
            let f = try Fixture(); defer { f.remove() }
            let staged = try stage(f)
            let operation = staged.bundleURL.deletingLastPathComponent()
            if mode == 0 { XCTAssertEqual(Darwin.chmod(operation.path, 0o755), 0) }
            if mode == 1 {
                let moved = f.staging.appendingPathComponent("alias-operation")
                try FileManager.default.moveItem(at: operation, to: moved)
                try FileManager.default.createSymbolicLink(atPath: operation.path, withDestinationPath: moved.path)
            }
            let operationID = mode == 2 ? UUID() : mode == 3
                ? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! : f.operationID
            XCTAssertThrowsError(try retained(f, staged: staged, operationID: operationID))
        }
    }

    func testEmbeddedReadbackRevalidatesPredecessorContextAfterStaticSignatureObservation() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertThrowsError(try Artifact.readbackEmbeddedFixture(context: f.context,
            configuration: f.configuration, signatureVerifier: { url in
                let evidence = try f.evidence(url)
                let moved = f.root.appendingPathComponent("moved-main.app")
                try FileManager.default.moveItem(at: f.app, to: moved)
                try FileManager.default.copyItem(at: moved, to: f.app)
                return evidence
            }))
    }

    func testRetainedNativeReadbackRejectsUnsignedCopyWithoutLaunchingOrChangingIt() throws {
        let f = try Fixture(); defer { f.remove() }
        let staged = try stage(f)
        XCTAssertThrowsError(try Artifact.readbackExistingStaged(operationID: f.operationID,
            target: f.context.target, expectedBroker: binding(staged), configuration: f.configuration,
            stagingParentURL: f.staging)) {
            guard case Artifact.Failure.signature = $0 else {
                return XCTFail("Unsigned retained broker did not fail actual native signature validation")
            }
        }
        XCTAssertEqual(try Data(contentsOf: staged.executableURL), Fixture.executableBytes)
    }

    func testRetainedFakeReadbackRefusesUnapprovedFixtureNamespaceBeforeVerifier() throws {
        let f = try Fixture(prefix: "beluga-other-fixture-"); defer { f.remove() }
        let identity = try BelugaUpdateOperation.ArtifactIdentity(version: "0.2.0", build: 100,
            executableSHA256: String(repeating: "a", count: 64),
            dependencyClosureSHA256: String(repeating: "b", count: 64))
        let expected = try BelugaUpdateOperation.BrokerBinding(artifact: identity,
                                                              nativeCDHash: Data(repeating: 7, count: 20))
        var invoked = false
        XCTAssertThrowsError(try Artifact.readbackExistingStagedFixture(operationID: f.operationID,
            target: f.context.target, expectedBroker: expected, configuration: f.configuration,
            stagingParentURL: f.staging, signatureVerifier: { url in
                invoked = true; return try f.evidence(url)
            })) {
            XCTAssertEqual($0 as? Artifact.Failure, .unsafeFixture)
        }
        XCTAssertFalse(invoked)
    }

    func testBrokerIdentityRuntimeFlagsExecutableAndCDHashAreRequiredBeforeCopy() throws {
        let changes: [(inout Artifact.SignatureEvidence) -> Void] = [
            { $0.identifier = BelugaUpdateOperation.expectedBundleIdentifier },
            { $0.teamIdentifier = "OTHERTEAM1" }, { $0.flags = 0 },
            { $0.flags |= SecCodeSignatureFlags.adhoc.rawValue },
            { $0.flags |= SecCodeSignatureFlags.linkerSigned.rawValue },
            { $0.executableURL = $0.executableURL.deletingLastPathComponent().appendingPathComponent("CaptureServer") },
            { $0.cdHash = Data() }, { $0.cdHash = Data(repeating: 1, count: 19) },
            { $0.cdHash = Data(repeating: 1, count: 21) }, { $0.cdHash = Data(repeating: 0, count: 20) }
        ]
        for change in changes {
            let f = try Fixture(); defer { f.remove() }
            XCTAssertThrowsError(try stage(f, evidence: { url in
                var evidence = try f.evidence(url); change(&evidence); return evidence
            })) {
                XCTAssertEqual($0 as? Artifact.Failure, .invalidSignature)
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.staging.path).isEmpty)
        }
    }

    func testBrokerMetadataAndExactParentReleaseConfigurationCannotDrift() throws {
        let changes: [(String, Any)] = [
            ("CFBundleIdentifier", "other"), ("CFBundleExecutable", "../Other"),
            ("CFBundleName", "Other"), ("CFBundleDisplayName", "Other"),
            ("CFBundlePackageType", "BNDL"), ("LSMinimumSystemVersion", "13.0"),
            ("CFBundleDevelopmentRegion", "fr"), ("CFBundleInfoDictionaryVersion", "5.0"),
            ("LSUIElement", 1), ("SURequireSignedFeed", 1),
            ("SUAllowsAutomaticUpdates", true), ("CFBundleVersion", "101"),
            ("CFBundleShortVersionString", "0.2.1"),
            ("SUFeedURL", "https://other.example.org/appcast.xml"),
            ("SUPublicEDKey", Data(repeating: 8, count: 32).base64EncodedString())
        ]
        for (key, value) in changes {
            let f = try Fixture(); defer { f.remove() }
            XCTAssertThrowsError(try stage(f, evidence: { url in
                var result = try f.evidence(url); result.securedInfo[key] = value; return result
            }))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.staging.path).isEmpty)
        }
    }

    func testUnknownMetadataCannotBypassBoundedDictionaryBudget() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertThrowsError(try stage(f, evidence: { url in
            var result = try f.evidence(url)
            result.securedInfo["Extra"] = String(repeating: "x", count: 65_537)
            return result
        })) {
            XCTAssertEqual($0 as? Artifact.Failure, .metadataLimitExceeded)
        }
    }

    func testSourceOrCopiedBytesMutationRetainsFailureAndCannotReturnStagedAuthority() throws {
        for sourceChanged in [true, false] {
            let f = try Fixture(); defer { f.remove() }
            let expected = f.staging.appendingPathComponent("broker-" + f.operationID.uuidString)
                .appendingPathComponent("BelugaUpdater.app/Contents/MacOS/BelugaUpdater")
            XCTAssertThrowsError(try stage(f, hooks: .init(afterCopy: {
                let changed = sourceChanged ? f.broker.appendingPathComponent("Contents/MacOS/BelugaUpdater") : expected
                try Data("changed bytes".utf8).write(to: changed)
            }))) {
                XCTAssertEqual($0 as? Artifact.Failure, .artifactChanged)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
            XCTAssertThrowsError(try stage(f)) {
                XCTAssertEqual($0 as? Artifact.Failure, .collision)
            }
        }
    }

    func testCopiedSignatureMustValidateIndependently() throws {
        let f = try Fixture(); defer { f.remove() }
        var copiedChecks = 0
        XCTAssertThrowsError(try stage(f, evidence: { url in
            if url.path.hasPrefix(f.staging.path + "/") {
                copiedChecks += 1
                throw Artifact.Failure.signature(errSecCSUnsigned)
            }
            return try f.evidence(url)
        })) {
            XCTAssertEqual($0 as? Artifact.Failure, .signature(errSecCSUnsigned))
        }
        XCTAssertEqual(copiedChecks, 1)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: f.staging.path).isEmpty)
    }

    func testPublicationRechecksCopiedBytesAfterEarlierVerification() throws {
        let f = try Fixture(); defer { f.remove() }
        let copied = f.staging.appendingPathComponent("broker-" + f.operationID.uuidString)
            .appendingPathComponent("BelugaUpdater.app/Contents/Resources/signed-resource")
        XCTAssertThrowsError(try stage(f, hooks: .init(beforePublication: {
            try Data("changed sealed resource".utf8).write(to: copied)
        }))) {
            XCTAssertEqual($0 as? Artifact.Failure, .artifactChanged)
        }
    }

    func testFreshVerificationRejectsTamperedBytesCDHashAndDirectoryReplacement() throws {
        for mode in 0..<4 {
            let f = try Fixture(); defer { f.remove() }
            let staged = try stage(f)
            if mode == 0 { try Data("tampered".utf8).write(to: staged.executableURL) }
            if mode == 2 {
                let operation = staged.bundleURL.deletingLastPathComponent()
                let moved = f.staging.appendingPathComponent("old-operation")
                try FileManager.default.moveItem(at: operation, to: moved)
                try FileManager.default.copyItem(at: moved, to: operation)
            }
            if mode == 3 {
                let moved = staged.bundleURL.deletingLastPathComponent().appendingPathComponent("old-broker.app")
                try FileManager.default.moveItem(at: staged.bundleURL, to: moved)
                try FileManager.default.copyItem(at: moved, to: staged.bundleURL)
            }
            XCTAssertThrowsError(try Artifact.verifyStagedFixture(context: f.context,
                parentConfiguration: f.configuration, staged: staged) { url in
                    var value = try f.evidence(url)
                    if mode == 1 { value.cdHash = Data(repeating: 9, count: 20) }
                    return value
                })
        }
    }

    func testUnsafeStagingModeAliasOrParentInsideMainAppRefusesBeforeCopy() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertEqual(Darwin.chmod(f.staging.path, 0o755), 0)
        XCTAssertThrowsError(try stage(f))
        XCTAssertEqual(Darwin.chmod(f.staging.path, 0o700), 0)
        let alias = f.root.appendingPathComponent("staging-alias")
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: f.staging.path)
        XCTAssertThrowsError(try Artifact.stage(context: f.context, parentConfiguration: f.configuration,
            operationID: f.operationID, stagingParentURL: alias))
        let inside = f.app.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        XCTAssertThrowsError(try Artifact.stage(context: f.context, parentConfiguration: f.configuration,
            operationID: f.operationID, stagingParentURL: inside)) {
            XCTAssertEqual($0 as? Artifact.Failure, .unsafeDirectory)
        }
    }

    func testSourceSymlinkHardlinkAndSpecialFileCannotBeCopiedAsBrokerCode() throws {
        for mode in 0..<3 {
            let f = try Fixture(); defer { f.remove() }
            let path = f.broker.appendingPathComponent("Contents/MacOS/BelugaUpdater")
            if mode == 0 {
                try FileManager.default.removeItem(at: path)
                try FileManager.default.createSymbolicLink(atPath: path.path, withDestinationPath: "../Resources/signed-resource")
            } else if mode == 1 {
                XCTAssertEqual(Darwin.link(path.path, f.broker.appendingPathComponent("other-link").path), 0)
            } else {
                XCTAssertEqual(Darwin.mkfifo(f.broker.appendingPathComponent("fifo").path, 0o600), 0)
            }
            XCTAssertThrowsError(try stage(f))
        }
    }

    func testUnsignedNativeBrokerRejectedWithoutCreatingOperationDirectory() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertThrowsError(try Artifact.stage(context: f.context, parentConfiguration: f.configuration,
            operationID: f.operationID, stagingParentURL: f.staging)) {
            guard case Artifact.Failure.signature = $0 else {
                return XCTFail("Unsigned private broker did not fail actual native signature validation")
            }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.staging.path).isEmpty)
    }

    func testFakeSignatureSeamRejectsUnapprovedFixtureNamespace() throws {
        let f = try Fixture(prefix: "beluga-other-fixture-"); defer { f.remove() }
        var invoked = false
        XCTAssertThrowsError(try stage(f, evidence: { url in invoked = true; return try f.evidence(url) })) {
            XCTAssertEqual($0 as? Artifact.Failure, .unsafeFixture)
        }
        XCTAssertFalse(invoked)
    }

    func testFixedNativeRequirementAndValidationFlagsAreSupported() {
        XCTAssertEqual(Artifact.bundleIdentifier, "com.elamin.beluga.Updater")
        XCTAssertEqual(Artifact.embeddedRelativePath, "Contents/Helpers/BelugaUpdater.app")
        XCTAssertTrue(Artifact.signingRequirement.contains("certificate leaf[field.1.2.840.113635.100.6.1.13] exists"))
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(Artifact.signingRequirement as CFString, [], &requirement), errSecSuccess)
        XCTAssertNotNil(requirement)
        for flag in [kSecCSCheckAllArchitectures, kSecCSCheckNestedCode, kSecCSStrictValidate] {
            XCTAssertNotEqual(Artifact.validationFlags.rawValue & flag, 0)
        }
        XCTAssertTrue(Artifact.validationFlags.contains(.noNetworkAccess))
    }

    private func stage(_ f: Fixture,
                       evidence: ((URL) throws -> Artifact.SignatureEvidence)? = nil,
                       hooks: Artifact.Hooks = .init()) throws -> Artifact.Staged {
        try Artifact.stageFixture(context: f.context, parentConfiguration: f.configuration,
                                  operationID: f.operationID, stagingParentURL: f.staging,
                                  signatureVerifier: evidence ?? f.evidence, hooks: hooks)
    }

    private func binding(_ staged: Artifact.Staged) throws -> BelugaUpdateOperation.BrokerBinding {
        try .init(artifact: staged.identity, nativeCDHash: staged.nativeCDHash)
    }

    private func retained(_ f: Fixture, staged: Artifact.Staged,
                          expected: BelugaUpdateOperation.BrokerBinding? = nil,
                          configuration: BelugaReleaseConfiguration? = nil, operationID: UUID? = nil,
                          evidence: ((URL) throws -> Artifact.SignatureEvidence)? = nil) throws -> Artifact.Verification {
        try Artifact.readbackExistingStagedFixture(operationID: operationID ?? f.operationID,
            target: f.context.target, expectedBroker: expected ?? binding(staged),
            configuration: configuration ?? f.configuration, stagingParentURL: f.staging,
            signatureVerifier: evidence ?? f.evidence)
    }

    private struct Fixture {
        static let executableBytes = Data("unsigned broker private fixture".utf8)
        let root: URL; let app: URL; let broker: URL; let staging: URL
        let context: BelugaUpdateRuntimeContext; let configuration: BelugaReleaseConfiguration
        let operationID = UUID()
        let info: [String: Any]

        init(prefix: String = "beluga-broker-artifact-fixture-") throws {
            let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            do {
                let app = root.appendingPathComponent("Beluga Host.app", isDirectory: true)
                let broker = app.appendingPathComponent(Artifact.embeddedRelativePath, isDirectory: true)
                let staging = root.appendingPathComponent("staging", isDirectory: true)
                let home = root.appendingPathComponent("account-home", isDirectory: true)
                for path in [broker.appendingPathComponent("Contents/MacOS"),
                             broker.appendingPathComponent("Contents/Resources"),
                             broker.appendingPathComponent("Contents/_CodeSignature")] {
                    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true,
                                                           attributes: [.posixPermissions: 0o755])
                }
                for path in [staging, home] {
                    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false,
                                                           attributes: [.posixPermissions: 0o700])
                }
                let info: [String: Any] = [
                    "CFBundleIdentifier": Artifact.bundleIdentifier, "CFBundleExecutable": "BelugaUpdater",
                    "CFBundleName": "Beluga Updater", "CFBundleDisplayName": "Beluga Updater",
                    "CFBundleDevelopmentRegion": "en", "CFBundleInfoDictionaryVersion": "6.0",
                    "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "14.0", "LSUIElement": true,
                    "CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "100",
                    "SUFeedURL": "https://updates.example.org/appcast.xml",
                    "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
                    "SUVerifyUpdateBeforeExtraction": true, "SURequireSignedFeed": true,
                    "SUAllowsAutomaticUpdates": false
                ]
                try Self.executableBytes.write(to: broker.appendingPathComponent("Contents/MacOS/BelugaUpdater"))
                try Data("signed resource".utf8).write(to: broker.appendingPathComponent("Contents/Resources/signed-resource"))
                try Data("signature fixture".utf8).write(to: broker.appendingPathComponent("Contents/_CodeSignature/CodeResources"))
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                    .write(to: broker.appendingPathComponent("Contents/Info.plist"))
                for relative in ["Contents/Resources/signed-resource", "Contents/_CodeSignature/CodeResources",
                                 "Contents/Info.plist"] {
                    guard Darwin.chmod(broker.appendingPathComponent(relative).path, 0o644) == 0 else {
                        throw Artifact.Failure.io(errno)
                    }
                }
                guard Darwin.chmod(broker.appendingPathComponent("Contents/MacOS/BelugaUpdater").path, 0o755) == 0 else {
                    throw Artifact.Failure.io(errno)
                }
                let alias = broker.appendingPathComponent("Contents/Resources/alias")
                try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: "signed-resource")
                guard Darwin.lchmod(alias.path, 0o755) == 0 else { throw Artifact.Failure.io(errno) }
                let context = try XCTUnwrap(BelugaUpdateRuntimeContext.resolve(
                    bundleIdentifier: BelugaUpdateOperation.expectedBundleIdentifier, bundleURL: app,
                    inputs: .init(effectiveUID: Darwin.geteuid(), accountHomeDirectory: { _ in home })))
                self.root = root; self.app = app; self.broker = broker; self.staging = staging
                self.context = context; self.info = info
                configuration = try BelugaReleaseConfiguration(info: info)
            } catch { try? FileManager.default.removeItem(at: root); throw error }
        }

        func evidence(_ url: URL) throws -> Artifact.SignatureEvidence {
            .init(identifier: Artifact.bundleIdentifier, teamIdentifier: BelugaUpdateOperation.expectedTeamIdentifier,
                  flags: SecCodeSignatureFlags.runtime.rawValue,
                  executableURL: url.appendingPathComponent("Contents/MacOS/BelugaUpdater"),
                  cdHash: Data(repeating: 7, count: 20), securedInfo: info)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
