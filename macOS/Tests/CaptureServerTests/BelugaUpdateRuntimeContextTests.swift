import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import BelugaUpdateCore
@testable import CaptureServer

final class BelugaUpdateRuntimeContextTests: XCTestCase {
    private typealias Context = BelugaUpdateRuntimeContext

    private func fixture() throws -> (root: URL, app: URL, home: URL) {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("beluga-runtime-context-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let app = root.appendingPathComponent("Beluga Host.app", isDirectory: true)
        let home = root.appendingPathComponent("account-home", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
        return (root, app, home)
    }

    private func resolve(_ app: URL, home: URL,
                         uid: UInt32 = Darwin.geteuid(),
                         afterOpen: (() throws -> Void)? = nil) throws -> Context {
        let resolved = try Context.resolve(bundleIdentifier: BelugaUpdateOperation.expectedBundleIdentifier,
            bundleURL: app, inputs: .init(effectiveUID: uid, accountHomeDirectory: { _ in home },
                                          afterTargetOpenForTesting: afterOpen))
        return try XCTUnwrap(resolved)
    }

    func testOtherBundleBareCLIAndTestBundleDoNotLookupAnAccountOrCreateState() throws {
        var lookedUpHome = false
        let inputs = Context.ResolverInputs(effectiveUID: Darwin.geteuid(), accountHomeDirectory: { _ in
            lookedUpHome = true
            throw Context.ResolutionError.unavailableAccountHome
        })
        let cases: [(String?, String)] = [(nil, "/tmp/CaptureServer"),
                                         ("Other", "/tmp/Other.app"),
                                         ("CaptureServerTests", "/tmp/CaptureServerTests.xctest")]
        for (identifier, path) in cases {
            XCTAssertNil(try Context.resolve(bundleIdentifier: identifier,
                bundleURL: URL(fileURLWithPath: path), inputs: inputs))
        }
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        XCTAssertNil(try Context.resolve(bundleIdentifier: BelugaUpdateOperation.expectedBundleIdentifier,
                                         bundleURL: f.root, inputs: inputs))
        XCTAssertFalse(lookedUpHome)
    }

    func testExactTargetDoesNotDependOnSparkleMetadataAndDoesNotCreateFenceDirectory() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let context = try resolve(f.app, home: f.home)
        XCTAssertEqual(context.target.bundleIdentifier, BelugaUpdateOperation.expectedBundleIdentifier)
        XCTAssertEqual(context.target.teamIdentifier, BelugaUpdateOperation.expectedTeamIdentifier)
        XCTAssertEqual(context.target.effectiveUID, Darwin.geteuid())
        // F_GETPATH preserves /private; Foundation's resolvingSymlinksInPath may
        // shorten it back to /tmp. The fixture is already at its physical path.
        XCTAssertEqual(context.target.canonicalPath, f.app.path)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(context.target))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(context.fenceDirectoryURL,
            f.home.appendingPathComponent("Library/Application Support/Beluga/UpdateFences")
                .appendingPathComponent(digest, isDirectory: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.fenceDirectoryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.home.appendingPathComponent("Library").path))
        try context.revalidate()
    }

    func testAppAndAccountHomeAliasesConvergeToTheSameTargetAndFence() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let appAlias = f.root.appendingPathComponent("Alias.app", isDirectory: true)
        let homeAlias = f.root.appendingPathComponent("home-alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: appAlias, withDestinationURL: f.app)
        try FileManager.default.createSymbolicLink(at: homeAlias, withDestinationURL: f.home)
        let original = try resolve(f.app, home: f.home)
        let alias = try resolve(appAlias, home: homeAlias)
        XCTAssertEqual(alias, original)
        try alias.revalidate()
    }

    func testExtensionlessAndUppercaseAppAliasesCannotBypassTheTargetFence() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try resolve(f.app, home: f.home)
        for name in ["Beluga-alias", "UppercaseAlias.APP"] {
            let aliasURL = f.root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: f.app)
            let alias = try resolve(aliasURL, home: f.home)
            XCTAssertEqual(alias, original)
            XCTAssertEqual(alias.fenceDirectoryURL, original.fenceDirectoryURL)
            try alias.revalidate()
        }
    }

    func testDistinctInstalledAppPathsAndUIDsHaveSeparateTargetNamespaces() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let other = f.root.appendingPathComponent("Other Beluga.app", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
        let a = try resolve(f.app, home: f.home)
        let b = try resolve(other, home: f.home)
        let c = try resolve(f.app, home: f.home, uid: Darwin.geteuid() ^ 1)
        XCTAssertNotEqual(a.target, b.target)
        XCTAssertNotEqual(a.fenceDirectoryURL, b.fenceDirectoryURL)
        XCTAssertNotEqual(a.fenceDirectoryURL, c.fenceDirectoryURL)
        XCTAssertThrowsError(try c.revalidate()) {
            XCTAssertEqual($0 as? Context.ResolutionError, .effectiveUIDChanged)
        }
    }

    func testMatchedMalformedMissingOrNondirectoryAppFailsClosed() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let inputs = Context.ResolverInputs(effectiveUID: Darwin.geteuid(), accountHomeDirectory: { _ in f.home })
        for malformed in [URL(string: "https://example.invalid/Beluga.app")!,
                          f.root.appendingPathComponent("Missing.app"),
                          f.root.appendingPathComponent("Bad\n.app")] {
            XCTAssertThrowsError(try Context.resolve(bundleIdentifier: BelugaUpdateOperation.expectedBundleIdentifier,
                                                     bundleURL: malformed, inputs: inputs))
        }
        let file = f.root.appendingPathComponent("File.app")
        try Data().write(to: file)
        XCTAssertThrowsError(try Context.resolve(bundleIdentifier: BelugaUpdateOperation.expectedBundleIdentifier,
                                                 bundleURL: file, inputs: inputs))
        let notApp = f.root.appendingPathComponent("not-an-app", isDirectory: true)
        try FileManager.default.createDirectory(at: notApp, withIntermediateDirectories: false)
        let alias = f.root.appendingPathComponent("Misleading.app", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: notApp)
        XCTAssertThrowsError(try resolve(alias, home: f.home))
    }

    func testDirectoryReplacementDuringResolutionCannotChangeItsBinding() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let displaced = f.root.appendingPathComponent("Displaced.app", isDirectory: true)
        XCTAssertThrowsError(try resolve(f.app, home: f.home, afterOpen: {
            try FileManager.default.moveItem(at: f.app, to: displaced)
            try FileManager.default.createDirectory(at: f.app, withIntermediateDirectories: false)
        })) {
            XCTAssertEqual($0 as? Context.ResolutionError, .directoryIdentityChanged)
        }
    }

    func testLockedReadRevalidationRejectsReplacedAppAndHomeDirectories() throws {
        for replaceHome in [false, true] {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            let context = try resolve(f.app, home: f.home)
            let original = replaceHome ? f.home : f.app
            let displaced = f.root.appendingPathComponent("displaced", isDirectory: true)
            try FileManager.default.moveItem(at: original, to: displaced)
            try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
            XCTAssertThrowsError(try context.revalidate()) {
                XCTAssertEqual($0 as? Context.ResolutionError, .directoryIdentityChanged)
            }
        }
    }

    func testInvalidOrUnavailableAccountHomeCannotRedirectFence() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        for home in [URL(fileURLWithPath: "/", isDirectory: true),
                     URL(string: "https://example.invalid/home")!,
                     f.root.appendingPathComponent("missing-home", isDirectory: true)] {
            XCTAssertThrowsError(try resolve(f.app, home: home))
        }
        XCTAssertThrowsError(try Context.resolve(bundleIdentifier: BelugaUpdateOperation.expectedBundleIdentifier,
            bundleURL: f.app, inputs: .init(effectiveUID: Darwin.geteuid(), accountHomeDirectory: { _ in
                throw Context.ResolutionError.unavailableAccountHome
            })))
    }
}
