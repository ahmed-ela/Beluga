import Darwin
import Foundation
import XCTest
@testable import BelugaUpdateCore
@testable import CaptureServer

/// All filesystem access is confined to per-test private directories beneath /private/tmp.
final class BelugaUpdateFenceStoreTests: XCTestCase {
    private typealias Operation = BelugaUpdateOperation
    private typealias Store = BelugaUpdateFenceStore

    func testAbsentReadDoesNotCreateDirectoryOrMarker() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        XCTAssertNil(try store.read(expectedTarget: fixture.target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.path))
        let deeper = fixture.directory.appendingPathComponent("missing-parent/fences", isDirectory: true)
        XCTAssertNil(try Store(directoryURL: deeper).read(expectedTarget: fixture.target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: deeper.path))
    }

    func testExclusiveCreateAndReadRestoreBlockedPreparedOperation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let operation = try fixture.prepared()
        let created = try store.create(operation)
        XCTAssertEqual(created.operation.operationID, operation.operationID)
        XCTAssertEqual(created.operation.stage, .prepared)
        XCTAssertEqual(created.recordSHA256.count, 64)
        XCTAssertFalse(created.operation.permitsRuntimeActivation)
        XCTAssertFalse(created.operation.permitsFenceRelease)
        let read = try XCTUnwrap(store.read(expectedTarget: fixture.target))
        XCTAssertEqual(read.recordSHA256, created.recordSHA256)
        XCTAssertEqual(try read.operation.encodedRecord(), try operation.encodedRecord())
        XCTAssertEqual(try Data(contentsOf: fixture.marker), try operation.encodedRecord())
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.marker.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: fixture.directory.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testSecondCreateNeverOverwritesExactOrDifferentOperation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let operation = try fixture.prepared()
        let first = try store.create(operation)
        let original = try Data(contentsOf: fixture.marker)
        expect(.alreadyExists) { _ = try store.create(operation) }
        expect(.alreadyExists) { _ = try store.create(fixture.prepared(operationID: UUID())) }
        XCTAssertEqual(try Data(contentsOf: fixture.marker), original)
        XCTAssertEqual(try store.read(expectedTarget: fixture.target)?.recordSHA256, first.recordSHA256)
    }

    func testReplacementAdvancesSameOperationAndRejectsStaleSnapshot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        var operation = try fixture.prepared()
        let prepared = try store.create(operation)
        XCTAssertTrue(operation.bindCandidate(try fixture.candidate(), operationID: operation.operationID,
                                             target: fixture.target))
        let bound = try store.replace(operation, expected: prepared)
        XCTAssertNotEqual(bound.recordSHA256, prepared.recordSHA256)
        XCTAssertTrue(operation.markPossiblyArmed(operationID: operation.operationID, target: fixture.target))
        let armed = try store.replace(operation, expected: bound)
        XCTAssertEqual(armed.operation.stage, .possiblyArmed)
        expect(.staleRecord) { _ = try store.replace(operation, expected: prepared) }
        XCTAssertEqual(try store.read(expectedTarget: fixture.target)?.recordSHA256, armed.recordSHA256)
        XCTAssertEqual(try store.replace(operation, expected: armed).recordSHA256, armed.recordSHA256)
    }

    func testBrokerBindingCanPublishOnceWhilePreparedAndCannotDisappearOrChange() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        var operation = try fixture.unbound()
        let initial = try store.create(operation)
        XCTAssertTrue(operation.bindBroker(try fixture.broker(), operationID: operation.operationID,
                                          target: fixture.target))
        let bound = try store.replace(operation, expected: initial)
        XCTAssertNotEqual(bound.recordSHA256, initial.recordSHA256)
        XCTAssertEqual(bound.operation.brokerBinding, try fixture.broker())
        let changes: [(inout [String: Any]) -> Void] = [
            { $0.removeValue(forKey: "broker") },
            { object in
                var broker = object["broker"] as! [String: Any]
                broker["nativeCDHash"] = Data(repeating: 8, count: 20).base64EncodedString()
                object["broker"] = broker
            },
            { object in
                var broker = object["broker"] as! [String: Any]
                var artifact = broker["artifact"] as! [String: Any]
                artifact["dependencyClosureSHA256"] = String(repeating: "9", count: 64)
                broker["artifact"] = artifact; object["broker"] = broker
            }
        ]
        for change in changes {
            let changed = try Operation.restoring(from: mutate(operation.encodedRecord(), change),
                                                  expectedTarget: fixture.target)
            XCTAssertNotEqual(changed.brokerBinding, bound.operation.brokerBinding)
            XCTAssertThrowsError(try store.replace(changed, expected: bound))
        }
        XCTAssertEqual(try store.read(expectedTarget: fixture.target)?.recordSHA256, bound.recordSHA256)
    }

    func testInitialBrokerPublicationCannotSkipPreparedStage() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        var operation = try fixture.unbound()
        let initial = try store.create(operation)
        XCTAssertTrue(operation.bindBroker(try fixture.broker(), operationID: operation.operationID,
                                          target: fixture.target))
        XCTAssertTrue(operation.markPossiblyArmed(operationID: operation.operationID, target: fixture.target))
        XCTAssertThrowsError(try store.replace(operation, expected: initial))
        XCTAssertEqual(try store.read(expectedTarget: fixture.target)?.recordSHA256, initial.recordSHA256)
    }

    func testOperationTargetPredecessorAndMenuBindingsCannotChange() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let operation = try fixture.prepared()
        let expected = try store.create(operation)
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["operationID"] = UUID().uuidString },
            { $0["predecessorMenuInstanceID"] = UUID().uuidString },
            { object in
                var predecessor = object["predecessor"] as! [String: Any]
                predecessor["dependencyClosureSHA256"] = String(repeating: "d", count: 64)
                object["predecessor"] = predecessor
            },
        ]
        for change in changes {
            let changed = try Operation.restoring(from: mutate(operation.encodedRecord(), change),
                                                  expectedTarget: fixture.target)
            expect(.unexpectedBinding) { _ = try store.replace(changed, expected: expected) }
        }
        let otherTarget = try Operation.Target(canonicalPath: fixture.root.appendingPathComponent("Other.app").path,
                                               effectiveUID: geteuid())
        let changedTarget = try Operation(operationID: operation.operationID, target: otherTarget,
                                          predecessor: fixture.predecessor(), predecessorMenuInstanceID: UUID())
        expect(.unexpectedBinding) { _ = try store.replace(changedTarget, expected: expected) }
        XCTAssertEqual(try Data(contentsOf: fixture.marker), try operation.encodedRecord())
    }

    func testStagesAndBoundCandidateCannotRegressOrChange() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let prepared = try fixture.prepared()
        let initial = try store.create(prepared)
        var armed = prepared
        XCTAssertTrue(armed.bindCandidate(try fixture.candidate(), operationID: armed.operationID,
                                         target: fixture.target))
        XCTAssertTrue(armed.markPossiblyArmed(operationID: armed.operationID, target: fixture.target))
        let current = try store.replace(armed, expected: initial)
        expect(.nonmonotonicTransition) { _ = try store.replace(prepared, expected: current) }
        let candidateChanged = try Operation.restoring(from: mutate(armed.encodedRecord()) { object in
            var candidate = object["candidate"] as! [String: Any]
            candidate["executableSHA256"] = String(repeating: "e", count: 64)
            object["candidate"] = candidate
        }, expectedTarget: fixture.target)
        expect(.nonmonotonicTransition) { _ = try store.replace(candidateChanged, expected: current) }
        let unbound = try Operation.restoring(from: mutate(armed.encodedRecord()) {
            $0.removeValue(forKey: "candidate")
        }, expectedTarget: fixture.target)
        expect(.nonmonotonicTransition) { _ = try store.replace(unbound, expected: current) }
        XCTAssertEqual(try store.read(expectedTarget: fixture.target)?.recordSHA256, current.recordSHA256)
    }

    func testPreparedMarkerNeverClearsOnIdleCancelFailureOrExit() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let prepared = try fixture.prepared()
        let expected = try store.create(prepared)
        let terminal = try fixture.terminal(from: prepared)
        for event in [Operation.NonTerminalObservation.sessionBecameIdle, .cancelled,
                      .updaterFailed, .brokerExited] {
            var observed = prepared
            observed.observe(event)
            expect(.releaseNotAuthorized) {
                try store.clear(observed, expected: expected, installedCompletion: terminal.completion,
                                readiness: terminal.readiness)
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.marker), try prepared.encodedRecord())
    }

    func testExactFreshCompletionAndReadinessCanClearOnlyCurrentTerminal() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let prepared = try fixture.prepared()
        let initial = try store.create(prepared)
        let terminal = try fixture.terminal(from: prepared)
        let expected = try store.replace(terminal.operation, expected: initial)
        XCTAssertTrue(terminal.operation.permitsFenceRelease)
        let wrongCompletion = Operation.InstalledCompletion(operationID: UUID(), target: fixture.target,
                                                           candidate: terminal.completion.candidate)
        expect(.releaseNotAuthorized) {
            try store.clear(terminal.operation, expected: expected, installedCompletion: wrongCompletion,
                            readiness: terminal.readiness)
        }
        let wrongReadiness = Operation.MenuReadiness(operationID: terminal.readiness.operationID,
            target: terminal.readiness.target, candidate: terminal.readiness.candidate,
            menuInstanceID: terminal.readiness.menuInstanceID, challengeNonce: UUID(), isReady: true)
        expect(.releaseNotAuthorized) {
            try store.clear(terminal.operation, expected: expected, installedCompletion: terminal.completion,
                            readiness: wrongReadiness)
        }
        expect(.releaseNotAuthorized) {
            try store.clear(terminal.operation, expected: initial, installedCompletion: terminal.completion,
                            readiness: terminal.readiness)
        }
        try store.clear(terminal.operation, expected: expected, installedCompletion: terminal.completion,
                        readiness: terminal.readiness)
        XCTAssertNil(try store.read(expectedTarget: fixture.target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.marker.path))
    }

    func testRestoredTerminalCannotBePersistedAsNewAuthorityOrClearFence() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let prepared = try fixture.prepared()
        let initial = try store.create(prepared)
        let terminal = try fixture.terminal(from: prepared)
        let restored = try Operation.restoring(from: terminal.operation.encodedRecord(),
                                               expectedTarget: fixture.target)
        expect(.releaseNotAuthorized) { _ = try store.replace(restored, expected: initial) }
        let current = try store.replace(terminal.operation, expected: initial)
        let read = try XCTUnwrap(store.read(expectedTarget: fixture.target))
        XCTAssertFalse(read.operation.permitsFenceRelease)
        expect(.releaseNotAuthorized) {
            try store.clear(read.operation, expected: current, installedCompletion: terminal.completion,
                            readiness: terminal.readiness)
        }
        XCTAssertNotNil(try store.read(expectedTarget: fixture.target))
    }

    func testMalformedOversizeDuplicateAndTrailingRecordsFailClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let prepared = try fixture.prepared()
        _ = try store.create(prepared)
        let encoded = try prepared.encodedRecord()
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let duplicate = Data(("{\"schema\":\"\(Operation.schema)\"," + String(text.dropFirst())).utf8)
        var trailing = encoded; trailing.append(10)
        for malformed in [Data(), Data("{}".utf8), duplicate, trailing,
                          Data(repeating: 32, count: Operation.maximumRecordBytes + 1)] {
            try fixture.writeMarker(malformed)
            XCTAssertThrowsError(try store.read(expectedTarget: fixture.target))
            XCTAssertEqual(try Data(contentsOf: fixture.marker), malformed)
            XCTAssertThrowsError(try store.create(prepared))
            XCTAssertEqual(try Data(contentsOf: fixture.marker), malformed)
        }
    }

    func testSymlinkHardlinkWrongModeAndNonRegularMarkerAreRejected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let prepared = try fixture.prepared()
        _ = try store.create(prepared)
        let external = fixture.root.appendingPathComponent("original.json")
        try fixture.writeMarker(prepared.encodedRecord())
        try FileManager.default.moveItem(at: fixture.marker, to: external)
        try FileManager.default.createSymbolicLink(at: fixture.marker, withDestinationURL: external)
        expect(.unsafeFile) { _ = try store.read(expectedTarget: fixture.target) }
        try FileManager.default.removeItem(at: fixture.marker)
        XCTAssertEqual(Darwin.link(external.path, fixture.marker.path), 0)
        expect(.unsafeFile) { _ = try store.read(expectedTarget: fixture.target) }
        try FileManager.default.removeItem(at: fixture.marker)
        try fixture.writeMarker(prepared.encodedRecord())
        XCTAssertEqual(Darwin.chmod(fixture.marker.path, 0o644), 0)
        expect(.unsafeFile) { _ = try store.read(expectedTarget: fixture.target) }
        try FileManager.default.removeItem(at: fixture.marker)
        XCTAssertEqual(Darwin.mkfifo(fixture.marker.path, 0o600), 0)
        expect(.unsafeFile) { _ = try store.read(expectedTarget: fixture.target) }
    }

    func testSymlinkOrPublicServiceDirectoryIsNeverFollowedOrRepaired() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let other = fixture.root.appendingPathComponent("other-private", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(at: fixture.directory, withDestinationURL: other)
        expect(.unsafeDirectory) { _ = try store.read(expectedTarget: fixture.target) }
        expect(.unsafeDirectory) { _ = try store.create(fixture.prepared()) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.appendingPathComponent(Store.fileName).path))
        try FileManager.default.removeItem(at: fixture.directory)
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o755])
        expect(.unsafeDirectory) { _ = try store.read(expectedTarget: fixture.target) }
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
    }

    func testSameBytesNewInodeOrNewDirectoryCannotSatisfyOldSnapshot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let prepared = try fixture.prepared()
        let initial = try store.create(prepared)
        var armed = prepared
        XCTAssertTrue(armed.markPossiblyArmed(operationID: armed.operationID, target: fixture.target))
        try fixture.writeMarker(prepared.encodedRecord())
        expect(.staleRecord) { _ = try store.replace(armed, expected: initial) }
        let current = try XCTUnwrap(store.read(expectedTarget: fixture.target))
        let previousDirectory = fixture.root.appendingPathComponent("retained-old-directory", isDirectory: true)
        try FileManager.default.moveItem(at: fixture.directory, to: previousDirectory)
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        try fixture.writeMarker(prepared.encodedRecord())
        expect(.staleRecord) { _ = try store.replace(armed, expected: current) }
        XCTAssertEqual(try Data(contentsOf: fixture.marker), try prepared.encodedRecord())
    }

    func testPureMetadataGuardsRejectForeignOwnersLinksAndSpecialModes() throws {
        var file = stat()
        file.st_uid = geteuid()
        file.st_mode = mode_t(S_IFREG | 0o600)
        file.st_nlink = 1
        file.st_size = 100
        XCTAssertTrue(Store.isSafeFileMetadata(file, expectedOwner: geteuid()))
        XCTAssertFalse(Store.isSafeFileMetadata(file, expectedOwner: geteuid() &+ 1))
        file.st_nlink = 2
        XCTAssertFalse(Store.isSafeFileMetadata(file, expectedOwner: geteuid()))
        file.st_nlink = 1
        file.st_mode = mode_t(S_IFREG | 0o4600)
        XCTAssertFalse(Store.isSafeFileMetadata(file, expectedOwner: geteuid()))
        var directory = stat()
        directory.st_uid = geteuid()
        directory.st_mode = mode_t(S_IFDIR | 0o700)
        directory.st_nlink = 2
        XCTAssertTrue(Store.isSafeDirectoryMetadata(directory, expectedOwner: geteuid()))
        XCTAssertFalse(Store.isSafeDirectoryMetadata(directory, expectedOwner: geteuid() &+ 1))
        directory.st_nlink = 0
        XCTAssertFalse(Store.isSafeDirectoryMetadata(directory, expectedOwner: geteuid()))
    }

    func testWrongEffectiveUIDAndNonPreparedCreatePerformNoWrites() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try Store(directoryURL: fixture.directory)
        let wrongTarget = try Operation.Target(canonicalPath: fixture.target.canonicalPath,
                                               effectiveUID: geteuid() &+ 1)
        expect(.unexpectedBinding) { _ = try store.read(expectedTarget: wrongTarget) }
        let wrongOperation = try Operation(operationID: UUID(), target: wrongTarget,
                                            predecessor: fixture.predecessor(), predecessorMenuInstanceID: UUID())
        expect(.unexpectedBinding) { _ = try store.create(wrongOperation) }
        var armed = try fixture.prepared()
        XCTAssertTrue(armed.markPossiblyArmed(operationID: armed.operationID, target: fixture.target))
        expect(.nonmonotonicTransition) { _ = try store.create(armed) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    private func expect(_ error: Store.Failure, file: StaticString = #filePath, line: UInt = #line,
                        _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { actual in
            XCTAssertEqual(actual as? Store.Failure, error, file: file, line: line)
        }
    }

    private func mutate(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private struct Fixture {
        let root: URL
        let directory: URL
        let target: Operation.Target
        var marker: URL { directory.appendingPathComponent(Store.fileName) }

        init() throws {
            root = URL(fileURLWithPath: "/private/tmp/beluga-update-fence-tests.\(UUID().uuidString)",
                       isDirectory: true)
            directory = root.appendingPathComponent("fences", isDirectory: true)
            target = try Operation.Target(canonicalPath: root.appendingPathComponent("Beluga Host.app").path,
                                           effectiveUID: geteuid())
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        func prepared(operationID: UUID = UUID()) throws -> Operation {
            var value = try unbound(operationID: operationID)
            let expected = try broker()
            guard value.bindBroker(expected, operationID: operationID, target: target) else {
                throw Store.Failure.nonmonotonicTransition
            }
            return value
        }

        func unbound(operationID: UUID = UUID()) throws -> Operation {
            try Operation(operationID: operationID, target: target, predecessor: predecessor(),
                          predecessorMenuInstanceID: UUID())
        }

        func broker() throws -> Operation.BrokerBinding {
            try .init(artifact: .init(version: "1.0.0", build: 100,
                executableSHA256: String(repeating: "e", count: 64),
                dependencyClosureSHA256: String(repeating: "f", count: 64)),
                nativeCDHash: Data(repeating: 7, count: 20))
        }

        func predecessor() throws -> Operation.ArtifactIdentity {
            try Operation.ArtifactIdentity(version: "1.0.0", build: 100,
                executableSHA256: String(repeating: "a", count: 64),
                dependencyClosureSHA256: String(repeating: "c", count: 64))
        }

        func candidate() throws -> Operation.ArtifactIdentity {
            try Operation.ArtifactIdentity(version: "1.0.1", build: 101,
                executableSHA256: String(repeating: "b", count: 64),
                dependencyClosureSHA256: String(repeating: "d", count: 64))
        }

        func terminal(from prepared: Operation) throws -> (
            operation: Operation, completion: Operation.InstalledCompletion,
            readiness: Operation.MenuReadiness
        ) {
            var operation = prepared
            let candidate = try candidate()
            guard operation.bindCandidate(candidate, operationID: operation.operationID, target: target),
                  operation.markPossiblyArmed(operationID: operation.operationID, target: target) else {
                throw Store.Failure.nonmonotonicTransition
            }
            let completion = Operation.InstalledCompletion(operationID: operation.operationID,
                                                           target: target, candidate: candidate)
            guard operation.acceptInstalledCompletion(completion),
                  let challenge = operation.issueReadinessChallenge(menuInstanceID: UUID(), nonce: UUID()) else {
                throw Store.Failure.releaseNotAuthorized
            }
            let readiness = Operation.MenuReadiness(operationID: operation.operationID, target: target,
                candidate: candidate, menuInstanceID: challenge.menuInstanceID,
                challengeNonce: challenge.nonce, isReady: true)
            guard operation.acceptMenuReadiness(readiness) else { throw Store.Failure.releaseNotAuthorized }
            return (operation, completion, readiness)
        }

        func writeMarker(_ bytes: Data) throws {
            try bytes.write(to: marker, options: .atomic)
            guard Darwin.chmod(marker.path, 0o600) == 0 else { throw Store.Failure.io(errno) }
        }
    }
}
