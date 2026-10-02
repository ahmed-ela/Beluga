import Darwin
import Foundation
import XCTest
@testable import BelugaUpdateCore

final class BelugaUpdateNamespaceTests: XCTestCase {
    func testMissingKnownParentsBecomePrivateWithoutCreatingFenceLeaf() throws {
        try withFixture { fixture in
            try BelugaUpdateNamespace.prepare(context: fixture.context)
            for directory in fixture.parents {
                XCTAssertEqual(try metadata(directory).st_mode & 0o7777, 0o700)
                XCTAssertEqual(try metadata(directory).st_uid, geteuid())
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.context.fenceDirectoryURL.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.updateFences.path), [])
        }
    }

    func testExistingNormalParentsAreIdempotentAndNeverChmodded() throws {
        try withFixture { fixture in
            try fixture.makeParents()
            for directory in [fixture.home, fixture.library, fixture.applicationSupport] {
                XCTAssertEqual(Darwin.chmod(directory.path, 0o755), 0)
            }
            let before = try fixture.parents.map { try metadata($0).st_ino }
            try BelugaUpdateNamespace.prepare(context: fixture.context)
            try BelugaUpdateNamespace.prepare(context: fixture.context)
            XCTAssertEqual(try fixture.parents.map { try metadata($0).st_ino }, before)
            for directory in [fixture.home, fixture.library, fixture.applicationSupport] {
                XCTAssertEqual(try metadata(directory).st_mode & 0o7777, 0o755)
            }
        }
    }

    func testStoreAloneCreatesFinalDigestLeafAfterPreparation() throws {
        try withFixture { fixture in
            try BelugaUpdateNamespace.prepare(context: fixture.context)
            let operation = try BelugaUpdateOperation(
                operationID: UUID(), target: fixture.context.target,
                predecessor: .init(version: "0.2.0", build: 100,
                                   executableSHA256: String(repeating: "a", count: 64),
                                   dependencyClosureSHA256: String(repeating: "b", count: 64)),
                predecessorMenuInstanceID: UUID()
            )
            let store = try BelugaUpdateFenceStore(directoryURL: fixture.context.fenceDirectoryURL)
            let saved = try store.create(operation)
            XCTAssertEqual(saved.operation, operation)
            XCTAssertEqual(try metadata(fixture.context.fenceDirectoryURL).st_mode & 0o7777, 0o700)
        }
    }

    func testPublicProductParentsAreRejectedWithoutRepair() throws {
        for targetIndex in [2, 3] {
            try withFixture { fixture in
                try fixture.makeParents(through: targetIndex)
                let target = fixture.parents[targetIndex]
                XCTAssertEqual(Darwin.chmod(target.path, 0o755), 0)
                XCTAssertThrowsError(try BelugaUpdateNamespace.prepare(context: fixture.context))
                XCTAssertEqual(try metadata(target).st_mode & 0o7777, 0o755)
                if targetIndex == 2 {
                    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.updateFences.path))
                }
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.context.fenceDirectoryURL.path))
            }
        }
    }

    func testWritableNormalParentIsRejectedBeforeFurtherCreation() throws {
        try withFixture { fixture in
            try fixture.makeParents(through: 0)
            XCTAssertEqual(Darwin.chmod(fixture.library.path, 0o775), 0)
            XCTAssertThrowsError(try BelugaUpdateNamespace.prepare(context: fixture.context))
            XCTAssertEqual(try metadata(fixture.library).st_mode & 0o7777, 0o775)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.applicationSupport.path))
        }
    }

    func testSymlinkNormalAndProductParentsAreNeverFollowed() throws {
        for targetIndex in [0, 2] {
            try withFixture { fixture in
                if targetIndex > 0 { try fixture.makeParents(through: targetIndex - 1) }
                let outside = fixture.root.appendingPathComponent("untouched", isDirectory: true)
                try makeDirectory(outside)
                try FileManager.default.createSymbolicLink(at: fixture.parents[targetIndex],
                                                            withDestinationURL: outside)
                XCTAssertThrowsError(try BelugaUpdateNamespace.prepare(context: fixture.context))
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
                var named = stat()
                XCTAssertEqual(Darwin.lstat(fixture.parents[targetIndex].path, &named), 0)
                XCTAssertEqual(named.st_mode & S_IFMT, S_IFLNK)
            }
        }
    }

    func testRegularFileAtKnownParentIsRejectedWithoutReplacement() throws {
        try withFixture { fixture in
            try fixture.makeParents(through: 0)
            let bytes = Data("retained".utf8)
            try bytes.write(to: fixture.applicationSupport)
            XCTAssertThrowsError(try BelugaUpdateNamespace.prepare(context: fixture.context))
            XCTAssertEqual(try Data(contentsOf: fixture.applicationSupport), bytes)
        }
    }

    func testAllowACLOnNormalOrPrivateParentIsRejectedEvenWithPrivateMode() throws {
        for targetIndex in [0, 2] {
            try withFixture { fixture in
                try fixture.makeParents(through: targetIndex)
                let target = fixture.parents[targetIndex]
                try addACL("everyone allow read,write", to: target)
                XCTAssertEqual(try metadata(target).st_mode & 0o7777, 0o700)
                XCTAssertThrowsError(try BelugaUpdateNamespace.prepare(context: fixture.context))
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.parents[targetIndex + 1].path))
            }
        }
    }

    func testUnsafeCapturedHomeIsRejectedBeforeAnyProvisioning() throws {
        for useACL in [false, true] {
            try withFixture { fixture in
                if useACL { try addACL("everyone allow read,write", to: fixture.home) }
                else { XCTAssertEqual(Darwin.chmod(fixture.home.path, 0o775), 0) }
                XCTAssertThrowsError(try BelugaUpdateNamespace.prepare(context: fixture.context))
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.home.path), [])
                XCTAssertEqual(try metadata(fixture.home).st_mode & 0o7777, useACL ? 0o700 : 0o775)
            }
        }
    }

    func testDenyOnlyACLDoesNotRequireRepair() throws {
        try withFixture { fixture in
            try fixture.makeParents()
            try addACL("everyone deny chown", to: fixture.library)
            try addACL("everyone deny chown", to: fixture.beluga)
            XCTAssertNoThrow(try BelugaUpdateNamespace.prepare(context: fixture.context))
        }
    }

    func testNamedDirectoryReplacementAfterOpenIsRejectedBeforeNextMkdir() throws {
        try withFixture { fixture in
            let retained = fixture.home.appendingPathComponent("retained-Library", isDirectory: true)
            XCTAssertThrowsError(try BelugaUpdateNamespace.prepare(
                context: fixture.context,
                afterDirectoryOpenedForTesting: { name in
                    if name == "Library" {
                        try FileManager.default.moveItem(at: fixture.library, to: retained)
                        try self.makeDirectory(fixture.library)
                    }
                }
            ))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.library.path), [])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: retained.path), [])
        }
    }

    func testACLChangedAfterOpenIsRejectedBeforePrivateDescendantCreation() throws {
        try withFixture { fixture in
            XCTAssertThrowsError(try BelugaUpdateNamespace.prepare(
                context: fixture.context,
                afterDirectoryOpenedForTesting: { name in
                    if name == "Beluga" { try self.addACL("everyone allow read", to: fixture.beluga) }
                }
            ))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.updateFences.path))
        }
    }

    func testCapturedHomeReplacementRejectsBeforeAnyProvisioning() throws {
        try withFixture { fixture in
            let retained = fixture.root.appendingPathComponent("retained-home", isDirectory: true)
            try FileManager.default.moveItem(at: fixture.home, to: retained)
            try makeDirectory(fixture.home)
            XCTAssertThrowsError(try BelugaUpdateNamespace.prepare(context: fixture.context))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.home.path), [])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: retained.path), [])
        }
    }

    func testCapturedAppReplacementRejectsBeforeAnyProvisioning() throws {
        try withFixture { fixture in
            let retained = fixture.root.appendingPathComponent("retained.app", isDirectory: true)
            try FileManager.default.moveItem(at: fixture.app, to: retained)
            try makeDirectory(fixture.app)
            XCTAssertThrowsError(try BelugaUpdateNamespace.prepare(context: fixture.context))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.home.path), [])
        }
    }

    func testPureMetadataChecksRejectForeignOwnerSpecialModesAndWrongNodeKind() {
        var value = stat()
        value.st_mode = mode_t(S_IFDIR | 0o755)
        value.st_uid = geteuid()
        value.st_nlink = 2
        XCTAssertTrue(BelugaUpdateNamespace.isSafeMetadata(value, privateOnly: false, expectedOwner: geteuid()))
        XCTAssertFalse(BelugaUpdateNamespace.isSafeMetadata(value, privateOnly: true, expectedOwner: geteuid()))
        XCTAssertFalse(BelugaUpdateNamespace.isSafeMetadata(value, privateOnly: false, expectedOwner: geteuid() &+ 1))
        value.st_mode = mode_t(S_IFDIR | 0o700)
        XCTAssertTrue(BelugaUpdateNamespace.isSafeMetadata(value, privateOnly: true, expectedOwner: geteuid()))
        value.st_mode = mode_t(S_IFDIR | 0o4700)
        XCTAssertFalse(BelugaUpdateNamespace.isSafeMetadata(value, privateOnly: true, expectedOwner: geteuid()))
        value.st_mode = mode_t(S_IFREG | 0o700)
        XCTAssertFalse(BelugaUpdateNamespace.isSafeMetadata(value, privateOnly: true, expectedOwner: geteuid()))
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("beluga-update-namespace-" + UUID().uuidString, isDirectory: true)
        try makeDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("account-home", isDirectory: true)
        let app = root.appendingPathComponent("Beluga.app", isDirectory: true)
        try makeDirectory(home)
        try makeDirectory(app)
        let context = try XCTUnwrap(BelugaUpdateRuntimeContext.resolve(
            bundleIdentifier: BelugaUpdateOperation.expectedBundleIdentifier, bundleURL: app,
            inputs: .init(effectiveUID: geteuid(), accountHomeDirectory: { _ in home })
        ))
        try body(Fixture(root: root, home: home, app: app, context: context))
    }

    private struct Fixture {
        let root: URL
        let home: URL
        let app: URL
        let context: BelugaUpdateRuntimeContext
        var library: URL { home.appendingPathComponent("Library", isDirectory: true) }
        var applicationSupport: URL { library.appendingPathComponent("Application Support", isDirectory: true) }
        var beluga: URL { applicationSupport.appendingPathComponent("Beluga", isDirectory: true) }
        var updateFences: URL { beluga.appendingPathComponent("UpdateFences", isDirectory: true) }
        var parents: [URL] { [library, applicationSupport, beluga, updateFences] }

        func makeParents(through index: Int = 3) throws {
            for directory in parents.prefix(index + 1) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])
            }
        }
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
    }

    private func metadata(_ url: URL) throws -> stat {
        var value = stat()
        guard Darwin.lstat(url.path, &value) == 0 else { throw FixtureFailure.io(errno) }
        return value
    }

    private func addACL(_ entry: String, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", entry, url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FixtureFailure.aclFailed }
    }

    private enum FixtureFailure: Error { case io(Int32), aclFailed }
}
