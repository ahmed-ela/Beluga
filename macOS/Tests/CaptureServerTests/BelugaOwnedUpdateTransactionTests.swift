import Dispatch
import Foundation
import XCTest
@testable import BelugaUpdateCore
@testable import CaptureServer

/// Kernel-lock regressions operate only on fresh UUID temporary directories. No updater,
/// app launch, user runtime namespace, compiler, signing, audio route or device is used.
final class BelugaOwnedUpdateTransactionTests: XCTestCase {
    private var idleAdmission: BelugaUpdateAdmission {
        BelugaUpdateAdmission(isInteractiveApplication: true, teardownComplete: true)
    }

    @MainActor
    func testOtherHostRefusesManualAndBackgroundChecksWithoutChangingItsGeneration() throws {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
        defer { host.release() }
        let record = directory.appendingPathComponent("worldwide-host.lock")
        let before = try Data(contentsOf: record)
        let update = makeTransaction(directory: directory)
        XCTAssertFalse(update.reserveInteractiveCheck(admission: idleAdmission,
                                                       sparkleSessionInProgress: false))
        XCTAssertFalse(update.admitCheck(.background, admission: idleAdmission))
        XCTAssertFalse(update.hasRuntimeOwnership)
        XCTAssertTrue(update.ownershipWasRefused)
        XCTAssertFalse(update.admitInstallation(admission: idleAdmission,
                                                sparkleSessionInProgress: true))
        XCTAssertEqual(try Data(contentsOf: record), before)
    }

    @MainActor
    func testBusyAdmissionDoesNotCreateOrAcquireAnyRuntimeNamespace() {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let update = makeTransaction(directory: directory)
        var busy = idleAdmission
        busy.hasActiveMedia = true
        XCTAssertFalse(update.reserveInteractiveCheck(admission: busy,
                                                       sparkleSessionInProgress: false))
        XCTAssertFalse(update.admitCheck(.background, admission: busy))
        XCTAssertFalse(update.hasRuntimeOwnership)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    func testManualReservationRetainsExactKernelOwnershipThroughFinalAdmission() throws {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let update = makeTransaction(directory: directory)
        defer { update.finishCycle(.interactive, sparkleSessionInProgress: false) }
        XCTAssertTrue(update.reserveInteractiveCheck(admission: idleAdmission,
                                                      sparkleSessionInProgress: false))
        let record = directory.appendingPathComponent("worldwide-host.lock")
        let before = try Data(contentsOf: record)
        XCTAssertTrue(update.hasRuntimeOwnership)
        XCTAssertTrue(update.isUpdateInProgress(sparkleSessionInProgress: false))
        assertHostCannotAcquire(directory)
        XCTAssertTrue(update.admitCheck(.interactive, admission: idleAdmission))
        XCTAssertTrue(update.admitInstallation(admission: idleAdmission,
                                               sparkleSessionInProgress: true))
        assertHostCannotAcquire(directory)
        XCTAssertEqual(try Data(contentsOf: record), before,
                       "Final installation must retain the same lease, not reacquire a new generation")
        update.finishCycle(.interactive, sparkleSessionInProgress: true)
        XCTAssertTrue(update.hasRuntimeOwnership)
        assertHostCannotAcquire(directory)
        update.finishCycle(.interactive, sparkleSessionInProgress: false)
        XCTAssertFalse(update.hasRuntimeOwnership)
        XCTAssertFalse(update.isUpdateInProgress(sparkleSessionInProgress: false))
        let nextHost = try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
        nextHost.release()
    }

    @MainActor
    func testWrongOrPrematureCompletionCannotReleaseManualReservation() throws {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let update = makeTransaction(directory: directory)
        defer { update.finishCycle(.interactive, sparkleSessionInProgress: false) }
        XCTAssertTrue(update.reserveInteractiveCheck(admission: idleAdmission,
                                                      sparkleSessionInProgress: false))
        update.finishCycle(.background, sparkleSessionInProgress: false)
        XCTAssertTrue(update.hasRuntimeOwnership)
        assertHostCannotAcquire(directory)
        XCTAssertFalse(update.admitCheck(.background, admission: idleAdmission))
        XCTAssertTrue(update.hasRuntimeOwnership)
        XCTAssertTrue(update.admitCheck(.interactive, admission: idleAdmission))
        update.finishCycle(.information, sparkleSessionInProgress: false)
        update.finishCycle(.interactive, sparkleSessionInProgress: true)
        assertHostCannotAcquire(directory)
        XCTAssertTrue(update.hasRuntimeOwnership)
    }

    @MainActor
    func testSerialBackgroundContinuationAndDeniedInstallRetainExactLease() throws {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let update = makeTransaction(directory: directory)
        defer { update.finishCycle(.interactive, sparkleSessionInProgress: false) }
        XCTAssertTrue(update.admitCheck(.background, admission: idleAdmission))
        let record = directory.appendingPathComponent("worldwide-host.lock")
        let before = try Data(contentsOf: record)
        var busy = idleAdmission
        busy.hasAudioShares = true
        XCTAssertFalse(update.admitCheck(.interactive, admission: busy))
        XCTAssertFalse(update.admitInstallation(admission: busy,
                                                sparkleSessionInProgress: true))
        update.finishCycle(.background, sparkleSessionInProgress: false)
        XCTAssertTrue(update.hasRuntimeOwnership)
        assertHostCannotAcquire(directory)
        XCTAssertEqual(try Data(contentsOf: record), before)
        update.finishCycle(.interactive, sparkleSessionInProgress: false)
        XCTAssertFalse(update.hasRuntimeOwnership)
        let nextHost = try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
        nextHost.release()
    }

    @MainActor
    func testCompletionReleaseCannotServeAsFreshFinalInstallAuthority() throws {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let update = makeTransaction(directory: directory)
        XCTAssertTrue(update.admitCheck(.background, admission: idleAdmission))
        update.finishCycle(.background, sparkleSessionInProgress: false)
        XCTAssertFalse(update.hasRuntimeOwnership)
        let nextHost = try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
        defer { nextHost.release() }
        let before = try Data(contentsOf: directory.appendingPathComponent("worldwide-host.lock"))
        XCTAssertFalse(update.admitInstallation(admission: idleAdmission,
                                                sparkleSessionInProgress: true))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("worldwide-host.lock")), before)
    }

    @MainActor
    func testUnsafeLockNamespaceRefusesCheckAndNeverAdmitsInstallation() throws {
        let root = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
        let update = makeTransaction(directory: alias)
        XCTAssertFalse(update.admitCheck(.background, admission: idleAdmission))
        XCTAssertFalse(update.hasRuntimeOwnership)
        XCTAssertFalse(update.admitInstallation(admission: idleAdmission,
                                                sparkleSessionInProgress: true))
    }

    @MainActor
    func testRetainedKernelLeaseAlsoRejectsAnActualSeparateProcess() throws {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let update = makeTransaction(directory: directory)
        defer { update.finishCycle(.interactive, sparkleSessionInProgress: false) }
        XCTAssertTrue(update.reserveInteractiveCheck(admission: idleAdmission,
                                                      sparkleSessionInProgress: false))
        let path = directory.appendingPathComponent("worldwide-host.lock").path
        XCTAssertEqual(try separateProcessLockResult(path), 23)
        XCTAssertTrue(update.admitCheck(.interactive, admission: idleAdmission))
        XCTAssertTrue(update.admitInstallation(admission: idleAdmission,
                                               sparkleSessionInProgress: true))
        XCTAssertEqual(try separateProcessLockResult(path), 23)
        update.finishCycle(.interactive, sparkleSessionInProgress: false)
        XCTAssertEqual(try separateProcessLockResult(path), 17)
    }

    @MainActor
    func testPossiblyArmedInstallerKeepsExactLeaseAfterCompletionCancellationOrError() throws {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try withTransaction(directory: directory) { update in
            XCTAssertTrue(update.admitCheck(.interactive, admission: idleAdmission))
            let record = directory.appendingPathComponent("worldwide-host.lock")
            let before = try Data(contentsOf: record)
            XCTAssertTrue(update.markInstallerMayRemainArmed())
            XCTAssertTrue(update.installerMayRemainArmed)
            XCTAssertFalse(update.installerArmingWasUnowned)
            XCTAssertTrue(update.admitInstallation(admission: idleAdmission,
                                                   sparkleSessionInProgress: true))
            // Every didFinish path has this same input, including dismiss/cancel/error.
            // None of those callbacks proves the external installer has gone away.
            update.finishCycle(.interactive, sparkleSessionInProgress: false)
            update.finishCycle(.interactive, sparkleSessionInProgress: false)
            update.finishCycle(.background, sparkleSessionInProgress: false)
            XCTAssertTrue(update.hasRuntimeOwnership)
            XCTAssertTrue(update.isUpdateInProgress(sparkleSessionInProgress: false),
                          "Start must remain fenced even after Sparkle's UI/session ends")
            XCTAssertFalse(update.reserveInteractiveCheck(admission: idleAdmission,
                                                           sparkleSessionInProgress: false))
            assertHostCannotAcquire(directory)
            XCTAssertEqual(try separateProcessLockResult(record.path), 23)
            XCTAssertEqual(try Data(contentsOf: record), before)
        }
        // Object lifetime ending simulates the actual process-exit limit of the lease.
        // It is not evidence that Sparkle's external installation has finished.
        let nextHost = try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
        nextHost.release()
    }

    @MainActor
    func testRepeatedExtractionAndFailedPreparationNeverRenewOrClearArmedOwnership() throws {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try withTransaction(directory: directory) { update in
            XCTAssertTrue(update.admitCheck(.background, admission: idleAdmission))
            let record = directory.appendingPathComponent("worldwide-host.lock")
            let before = try Data(contentsOf: record)
            XCTAssertTrue(update.markInstallerMayRemainArmed())
            XCTAssertTrue(update.markInstallerMayRemainArmed())
            update.finishCycle(.background, sparkleSessionInProgress: false)
            XCTAssertTrue(update.installerMayRemainArmed)
            XCTAssertTrue(update.hasRuntimeOwnership)
            XCTAssertTrue(update.isUpdateInProgress(sparkleSessionInProgress: false))
            assertHostCannotAcquire(directory)
            XCTAssertEqual(try Data(contentsOf: record), before)
        }
    }

    @MainActor
    func testUnexpectedUnownedArmingFailsClosedWithoutCreatingOrAcquiringNamespace() {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let update = makeTransaction(directory: directory)
        XCTAssertFalse(update.markInstallerMayRemainArmed())
        XCTAssertTrue(update.installerMayRemainArmed)
        XCTAssertTrue(update.installerArmingWasUnowned)
        XCTAssertTrue(update.isUpdateInProgress(sparkleSessionInProgress: false))
        XCTAssertFalse(update.reserveInteractiveCheck(admission: idleAdmission,
                                                       sparkleSessionInProgress: false))
        XCTAssertFalse(update.admitCheck(.interactive, admission: idleAdmission))
        XCTAssertFalse(update.admitInstallation(admission: idleAdmission,
                                                sparkleSessionInProgress: true))
        update.finishCycle(.interactive, sparkleSessionInProgress: false)
        XCTAssertTrue(update.isUpdateInProgress(sparkleSessionInProgress: false))
        XCTAssertFalse(update.hasRuntimeOwnership)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    func testLateUnownedArmingCannotReacquireOrTouchNewHostGeneration() throws {
        let directory = makeLockDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        var acquisitions = 0
        let update = BelugaOwnedUpdateTransaction {
            acquisitions += 1
            return try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
        }
        XCTAssertTrue(update.admitCheck(.background, admission: idleAdmission))
        update.finishCycle(.background, sparkleSessionInProgress: false)
        let host = try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
        defer { host.release() }
        let record = directory.appendingPathComponent("worldwide-host.lock")
        let before = try Data(contentsOf: record)
        XCTAssertFalse(update.markInstallerMayRemainArmed())
        XCTAssertFalse(update.admitCheck(.background, admission: idleAdmission))
        XCTAssertFalse(update.admitInstallation(admission: idleAdmission,
                                                sparkleSessionInProgress: true))
        update.finishCycle(.background, sparkleSessionInProgress: false)
        XCTAssertTrue(update.isUpdateInProgress(sparkleSessionInProgress: false))
        XCTAssertEqual(acquisitions, 1, "An arming invariant violation must never seek fresh authority")
        XCTAssertEqual(try Data(contentsOf: record), before)
    }

    @MainActor
    private func makeTransaction(directory: URL) -> BelugaOwnedUpdateTransaction {
        BelugaOwnedUpdateTransaction {
            try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory)
        }
    }

    @MainActor
    private func withTransaction(directory: URL,
                                 body: (BelugaOwnedUpdateTransaction) throws -> Void) rethrows {
        let update = makeTransaction(directory: directory)
        try body(update)
    }

    private func makeLockDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "belugaOwnedUpdateTests-\(UUID().uuidString)", isDirectory: true
        )
    }

    private func assertHostCannotAcquire(_ directory: URL,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try WorldwideHostProcessLock.acquire(lockDirectoryURL: directory),
                             file: file, line: line) { error in
            XCTAssertEqual(error as? WorldwideHostProcessLockError, .alreadyRunning,
                           file: file, line: line)
        }
    }

    private func separateProcessLockResult(_ path: String) throws -> Int32 {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        child.arguments = ["-e", "file = File.open(ARGV.fetch(0), File::RDWR); acquired = file.flock(File::LOCK_EX | File::LOCK_NB); exit(acquired ? 17 : 23)", path]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        let completed = DispatchSemaphore(value: 0)
        child.terminationHandler = { _ in completed.signal() }
        try child.run()
        guard completed.wait(timeout: .now() + 5) == .success else {
            child.terminate()
            throw ChildFailure.timeout
        }
        return child.terminationStatus
    }

    private enum ChildFailure: Error { case timeout }
}
