import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import BelugaUpdateCore

/// Only unique private filesystem fixtures: no signatures, SDK, app/host launch,
/// actual installed app, account data, network, or audio routes are accessed.
final class BelugaUpdateBundleTreeTests: XCTestCase {
    private typealias Tree = BelugaUpdateBundleTree

    func testKnownRubyCompatiblePreorderTupleFileAndRawLinkVector() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // Creation order intentionally differs from the required UTF-8 lexical order.
        try fixture.file("z", bytes: Data("last".utf8))
        try fixture.link("link", target: "Contents/MacOS/CaptureServer")
        let snapshot = try Tree.inspect(bundleURL: fixture.app)
        let expectedStream = fixture.baseStream +
            #"["/link",493,"link"]Contents/MacOS/CaptureServer"# +
            #"["/z",420,"file"]"# + sha(Data("last".utf8))
        XCTAssertEqual(Tree.algorithm, "beluga.bundle-tree-json-v1")
        XCTAssertEqual(snapshot.executableSHA256, sha(Fixture.executableBytes))
        XCTAssertEqual(snapshot.bundleTreeSHA256, sha(Data(expectedStream.utf8)))
        XCTAssertEqual(snapshot.bundleTreeSHA256,
                       "7a90e35f6fc6738675da31e3710e017589e94ae890a0839e73d7683c9854bc3b")
    }

    func testLiteralUnicodeQuoteBackslashAndNewlineNamesUseCompactUnescapedSlashJSON() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let quoted = "quoted\"\\\nπ"
        for name in ["🦈", "中", "π", quoted, "Z"] {
            try fixture.file(name, bytes: Data("value".utf8))
        }
        let hash = sha(Data("value".utf8))
        let expectedStream = fixture.baseStream +
            #"["/Z",420,"file"]"# + hash +
            #"["/quoted\"\\\nπ",420,"file"]"# + hash +
            #"["/π",420,"file"]"# + hash +
            #"["/中",420,"file"]"# + hash +
            #"["/🦈",420,"file"]"# + hash
        XCTAssertEqual(try Tree.inspect(bundleURL: fixture.app).bundleTreeSHA256,
                       sha(Data(expectedStream.utf8)))
        // Same independent Ruby JSON/SHA vector is asserted by the package tool's tests.
        XCTAssertEqual(try Tree.inspect(bundleURL: fixture.app).bundleTreeSHA256,
                       "e68bcee4217c4f0b0899fe10a45f77f3daa719d0d8daa14f535ed2ad8f7654dd")
    }

    func testExecutableBytesAndPermissionsAreIndependentDigestInputs() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let initial = try Tree.inspect(bundleURL: fixture.app)
        try Data("different bytes".utf8).write(to: fixture.executable)
        let changedBytes = try Tree.inspect(bundleURL: fixture.app)
        XCTAssertNotEqual(initial.executableSHA256, changedBytes.executableSHA256)
        XCTAssertNotEqual(initial.bundleTreeSHA256, changedBytes.bundleTreeSHA256)
        XCTAssertEqual(Darwin.chmod(fixture.executable.path, 0o644), 0)
        let changedMode = try Tree.inspect(bundleURL: fixture.app)
        XCTAssertEqual(changedBytes.executableSHA256, changedMode.executableSHA256)
        XCTAssertNotEqual(changedBytes.bundleTreeSHA256, changedMode.bundleTreeSHA256)
    }

    func testExplicitBrokerSelectorChangesOnlyExecutableIdentityNotTreeDigest() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let brokerBytes = Data("broker executable".utf8)
        try fixture.file("Contents/MacOS/BelugaUpdater", bytes: brokerBytes, mode: 0o755)
        let host = try Tree.inspect(bundleURL: fixture.app)
        let broker = try Tree.inspect(bundleURL: fixture.app, executable: .broker)
        XCTAssertEqual(host.executableSHA256, sha(Fixture.executableBytes))
        XCTAssertEqual(broker.executableSHA256, sha(brokerBytes))
        XCTAssertEqual(host.bundleTreeSHA256, broker.bundleTreeSHA256)
    }

    func testBrokerSelectorNeverBorrowsHostOrFollowsBrokerExecutableSymlink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, executable: .broker))
        try fixture.link("Contents/MacOS/BelugaUpdater", target: "CaptureServer")
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, executable: .broker))
    }

    func testBrokerOnlyBundleRequiresExplicitBrokerSelector() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.executable)
        let bytes = Data("broker only".utf8)
        try fixture.file("Contents/MacOS/BelugaUpdater", bytes: bytes, mode: 0o755)
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app))
        XCTAssertEqual(try Tree.inspect(bundleURL: fixture.app, executable: .broker).executableSHA256,
                       sha(bytes))
    }

    func testSignatureResourcesAndEmbeddedFilesAreInTheFullTree() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.directory("Contents/_CodeSignature")
        try fixture.file("Contents/_CodeSignature/CodeResources", bytes: Data("signed resources".utf8))
        let initial = try Tree.inspect(bundleURL: fixture.app)
        try fixture.file("Contents/_CodeSignature/CodeResources", bytes: Data("other resources".utf8))
        let changed = try Tree.inspect(bundleURL: fixture.app)
        XCTAssertEqual(initial.executableSHA256, changed.executableSHA256)
        XCTAssertNotEqual(initial.bundleTreeSHA256, changed.bundleTreeSHA256)
    }

    func testSymlinkHashesOnlyRawTargetNeverExternalContents() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("not-in-app")
        try Data("outside first".utf8).write(to: outside)
        try fixture.link("external", target: outside.path)
        let initial = try Tree.inspect(bundleURL: fixture.app)
        try Data("outside replaced contents".utf8).write(to: outside)
        XCTAssertEqual(initial, try Tree.inspect(bundleURL: fixture.app))
        try FileManager.default.removeItem(at: fixture.app.appendingPathComponent("external"))
        try fixture.link("external", target: "../not-in-app")
        let changed = try Tree.inspect(bundleURL: fixture.app)
        XCTAssertEqual(initial.executableSHA256, changed.executableSHA256)
        XCTAssertNotEqual(initial.bundleTreeSHA256, changed.bundleTreeSHA256)
    }

    func testCanonicalRootRefusesRootAndAncestorSymlinks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let alias = fixture.root.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: fixture.app.path)
        XCTAssertThrowsError(try Tree.inspect(bundleURL: alias))
        let ancestor = fixture.root.appendingPathComponent("alias-parent")
        try FileManager.default.createSymbolicLink(atPath: ancestor.path, withDestinationPath: fixture.root.path)
        XCTAssertThrowsError(try Tree.inspect(bundleURL: ancestor.appendingPathComponent("Beluga.app")))
        XCTAssertThrowsError(try Tree.inspect(bundleURL: URL(string: "https://example.invalid/Beluga.app")!))
    }

    func testMissingOrSymlinkExecutableNeverProducesExecutableIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.executable)
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app))
        try FileManager.default.createSymbolicLink(atPath: fixture.executable.path,
                                                  withDestinationPath: "/not-an-executable")
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app))
    }

    func testSpecialFileRefusesWithoutOpeningOrWaitingForFIFO() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pipe = fixture.app.appendingPathComponent("fifo").path
        XCTAssertEqual(Darwin.mkfifo(pipe, 0o600), 0)
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app))
    }

    func testFixedChunkStreamingHandlesMultipleChunksAndEmptyFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = Data(repeating: 173, count: 2 * 1_024 * 1_024 + 19)
        try bytes.write(to: fixture.executable)
        try fixture.file("empty", bytes: Data())
        let snapshot = try Tree.inspect(bundleURL: fixture.app)
        XCTAssertEqual(snapshot.executableSHA256, sha(bytes))
        XCTAssertEqual(snapshot.bundleTreeSHA256.count, 64)
    }

    func testGlobalNodeByteFileAndDepthLimitsRefuse() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var limit = Tree.Limits.standard
        limit.maximumNodes = 2
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, limits: limit))
        limit = .standard; limit.maximumTotalBytes = UInt64(Fixture.executableBytes.count - 1)
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, limits: limit))
        limit = .standard; limit.maximumFileBytes = UInt64(Fixture.executableBytes.count - 1)
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, limits: limit))
        try fixture.directory((0..<16).map { "d\($0)" }.joined(separator: "/"))
        limit = .standard; limit.maximumDepth = 10
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, limits: limit))
        limit = .standard; limit.maximumSeconds = .infinity
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, limits: limit))
    }

    func testMutationImmediatelyAfterFileReadRefuses() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var mutated = false
        let hooks = Tree.Hooks(afterNodeRead: { path in
            if path == "/Contents/MacOS/CaptureServer", !mutated {
                mutated = true
                try Data("mutated".utf8).write(to: fixture.executable)
            }
        })
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, limits: .standard, hooks: hooks))
        XCTAssertTrue(mutated)
    }

    func testSameBytesNewFileInodeRefuses() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let hooks = Tree.Hooks(beforeValidation: {
            let replacement = fixture.executable.deletingLastPathComponent().appendingPathComponent("replacement")
            try Fixture.executableBytes.write(to: replacement)
            XCTAssertEqual(Darwin.chmod(replacement.path, 0o755), 0)
            XCTAssertEqual(Darwin.rename(replacement.path, fixture.executable.path), 0)
        })
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, limits: .standard, hooks: hooks))
    }

    func testEarlierFileMutationIsCaughtByFinalMetadataPass() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("z", bytes: Data("last".utf8))
        let hooks = Tree.Hooks(afterNodeRead: { path in
            if path == "/z" { try Data("later change".utf8).write(to: fixture.executable) }
        })
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, limits: .standard, hooks: hooks))
    }

    func testDirectoryMembershipAndLinkReplacementBeforeValidationRefuse() throws {
        for changeLink in [false, true] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            try fixture.link("link", target: "Contents/MacOS/CaptureServer")
            let hooks = Tree.Hooks(beforeValidation: {
                if changeLink {
                    try FileManager.default.removeItem(at: fixture.app.appendingPathComponent("link"))
                    try fixture.link("link", target: "elsewhere")
                } else { try fixture.file("new-file", bytes: Data("new".utf8)) }
            })
            XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, limits: .standard, hooks: hooks))
        }
    }

    func testRootRenameAndReplacementBeforeValidationRefuse() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let hooks = Tree.Hooks(beforeValidation: {
            try FileManager.default.moveItem(at: fixture.app, to: fixture.root.appendingPathComponent("Old.app"))
            try FileManager.default.createDirectory(at: fixture.app, withIntermediateDirectories: false)
            XCTAssertEqual(Darwin.chmod(fixture.app.path, 0o755), 0)
        })
        XCTAssertThrowsError(try Tree.inspect(bundleURL: fixture.app, limits: .standard, hooks: hooks))
    }

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct Fixture {
        static let executableBytes = Data("fixture bytes".utf8)
        let root: URL
        let app: URL
        var executable: URL { app.appendingPathComponent("Contents/MacOS/CaptureServer") }
        var baseStream: String {
            #"["",493,"directory"]["/Contents",493,"directory"]["/Contents/MacOS",493,"directory"]["/Contents/MacOS/CaptureServer",493,"file"]"# +
                SHA256.hash(data: Self.executableBytes).map { String(format: "%02x", $0) }.joined()
        }
        init() throws {
            root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("beluga-bundle-tree-" + UUID().uuidString, isDirectory: true)
            app = root.appendingPathComponent("Beluga.app", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            try directory("Contents/MacOS")
            try file("Contents/MacOS/CaptureServer", bytes: Self.executableBytes, mode: 0o755)
        }
        func directory(_ relative: String) throws {
            let destination = app.appendingPathComponent(relative, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o755])
            var current = app
            guard Darwin.chmod(current.path, 0o755) == 0 else { throw Failure.io }
            for component in relative.split(separator: "/") {
                current.appendPathComponent(String(component), isDirectory: true)
                guard Darwin.chmod(current.path, 0o755) == 0 else { throw Failure.io }
            }
        }
        func file(_ relative: String, bytes: Data, mode: mode_t = 0o644) throws {
            let destination = app.appendingPathComponent(relative)
            try bytes.write(to: destination)
            guard Darwin.chmod(destination.path, mode) == 0 else { throw Failure.io }
        }
        func link(_ relative: String, target: String) throws {
            let destination = app.appendingPathComponent(relative).path
            try FileManager.default.createSymbolicLink(atPath: destination, withDestinationPath: target)
            guard Darwin.lchmod(destination, 0o755) == 0 else { throw Failure.io }
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
        private enum Failure: Error { case io }
    }
}
