import Darwin
import Foundation
import XCTest
@testable import BelugaUpdateCore
@testable import CaptureServer

final class BelugaUpdateRuntimeAdmissionTests: XCTestCase {
    func testNonTargetNonexclusiveModeDoesNotAcquireOrRead() throws {
        let owner = try BelugaUpdateRuntimeAdmission.acquire(
            requiresExclusiveOwnership: false, validateUpdateTarget: nil,
            acquireOwnership: { throw TestFailure.unexpectedAcquire }
        )
        XCTAssertNil(owner)
    }

    func testLegacyExclusiveModeRetainsExistingLeaseWithoutTargetRead() throws {
        try withDirectory { directory in
            let owner = try XCTUnwrap(BelugaUpdateRuntimeAdmission.acquire(
                requiresExclusiveOwnership: true, validateUpdateTarget: nil,
                acquireOwnership: { try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory) }
            ))
            defer { owner.release() }
            XCTAssertThrowsError(try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory))
        }
    }

    func testTargetLANModeReadsOnlyWhileOwningAndReturnsSameUninterruptedLease() throws {
        try withDirectory { directory in
            var reads = 0
            var admittedNonce: String?
            let owner = try XCTUnwrap(BelugaUpdateRuntimeAdmission.acquire(
                requiresExclusiveOwnership: false,
                validateUpdateTarget: {
                    reads += 1
                    XCTAssertThrowsError(try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory))
                },
                acquireOwnership: {
                    let acquired = try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
                    admittedNonce = acquired.generationNonce
                    return acquired
                }
            ))
            defer { owner.release() }
            XCTAssertEqual(reads, 1)
            XCTAssertEqual(owner.generationNonce, admittedNonce)
            XCTAssertThrowsError(try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory))
        }
    }

    func testBusyHostNeverReadsTargetFenceOrChangesCurrentGeneration() throws {
        try withDirectory { directory in
            let active = try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
            defer { active.release() }
            let record = directory.appendingPathComponent("worldwide-host.lock")
            let before = try Data(contentsOf: record)
            var reads = 0
            XCTAssertThrowsError(try BelugaUpdateRuntimeAdmission.acquire(
                requiresExclusiveOwnership: false,
                validateUpdateTarget: { reads += 1 },
                acquireOwnership: { try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory) }
            ))
            XCTAssertEqual(reads, 0)
            XCTAssertEqual(try Data(contentsOf: record), before)
        }
    }

    func testPendingOrUnreadableFenceRejectsBeforeRuntimeAndReleasesUnusedLease() throws {
        try withDirectory { directory in
            let failures: [Error] = [BelugaUpdateRuntimeAdmission.Failure.unresolvedUpdate,
                                     TestFailure.unreadableFence]
            for failure in failures {
                XCTAssertThrowsError(try BelugaUpdateRuntimeAdmission.acquire(
                    requiresExclusiveOwnership: true,
                    validateUpdateTarget: { throw failure },
                    acquireOwnership: { try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory) }
                ))
                let subsequent = try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
                subsequent.release()
            }
        }
    }

    func testFreshTargetWithoutNamespaceCanStartWithoutCreatingFenceDirectories() throws {
        try withTarget { context, lockDirectory in
            XCTAssertFalse(FileManager.default.fileExists(atPath: context.fenceDirectoryURL.path))
            let owner = try XCTUnwrap(BelugaUpdateRuntimeAdmission.acquire(
                requiresExclusiveOwnership: false,
                validateUpdateTarget: { try BelugaUpdateRuntimeAdmission.validateTarget(context) },
                acquireOwnership: { try WorldwideHostProcessLock.acquire(lockDirectoryURL: lockDirectory) }
            ))
            defer { owner.release() }
            XCTAssertFalse(FileManager.default.fileExists(atPath: context.fenceDirectoryURL.path))
        }
    }

    func testPersistedFenceStillBlocksTargetAfterUpdaterLeaseEnds() throws {
        try withTarget { context, lockDirectory in
            try FileManager.default.createDirectory(
                at: context.fenceDirectoryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            let broker = try WorldwideHostProcessLock.acquire(lockDirectoryURL: lockDirectory)
            defer { broker.release() }
            let operation = try BelugaUpdateOperation(
                operationID: UUID(), target: context.target,
                predecessor: .init(version: "0.2.0", build: 100,
                                   executableSHA256: String(repeating: "a", count: 64),
                                   dependencyClosureSHA256: String(repeating: "b", count: 64)),
                predecessorMenuInstanceID: UUID()
            )
            let store = try BelugaUpdateFenceStore(directoryURL: context.fenceDirectoryURL)
            let persisted = try store.create(operation)
            broker.release() // Models the process-lease loss, not installer completion.
            XCTAssertThrowsError(try BelugaUpdateRuntimeAdmission.acquire(
                requiresExclusiveOwnership: false,
                validateUpdateTarget: { try BelugaUpdateRuntimeAdmission.validateTarget(context) },
                acquireOwnership: { try WorldwideHostProcessLock.acquire(lockDirectoryURL: lockDirectory) }
            )) { error in
                XCTAssertTrue(error is BelugaUpdateRuntimeAdmission.Failure)
            }
            XCTAssertEqual(try store.read(expectedTarget: context.target)?.recordSHA256,
                           persisted.recordSHA256)
        }
    }

    private func withTarget(_ body: (BelugaUpdateRuntimeContext, URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("beluga-runtime-target-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Beluga.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
        let context = try XCTUnwrap(BelugaUpdateRuntimeContext.resolve(
            bundleIdentifier: BelugaUpdateOperation.expectedBundleIdentifier, bundleURL: app,
            inputs: .init(effectiveUID: Darwin.geteuid(), accountHomeDirectory: { _ in root })
        ))
        try body(context, root.appendingPathComponent("runtime-lock", isDirectory: true))
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("beluga-runtime-admission-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private enum TestFailure: Error { case unexpectedAcquire, unreadableFence }
}
