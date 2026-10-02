import BelugaUpdateCore
import Foundation
import XCTest
@testable import CaptureServer

final class BelugaUpdateControllerTests: XCTestCase {
    private enum Failure: Error { case refused }
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        func add(_ value: String) { lock.lock(); defer { lock.unlock() }; values.append(value) }
        var snapshot: [String] { lock.lock(); defer { lock.unlock() }; return values }
    }

    private func bundle() throws -> (Bundle, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("beluga-menu-controller-" + UUID().uuidString)
        let app = root.appendingPathComponent("Fixture.app"), contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.private-updater-controller-test",
            "CFBundlePackageType": "APPL", "CFBundleVersion": "100", "CFBundleShortVersionString": "0.2.0",
            "SUFeedURL": "https://example.org/appcast.xml", "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
            "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true, "SUAllowsAutomaticUpdates": false]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return (try XCTUnwrap(Bundle(url: app)), root)
    }

    private var idle: BelugaUpdateAdmission {
        .init(isInteractiveApplication: true, teardownComplete: true)
    }

    @MainActor func testIdleCheckIsExplicitSerialAndReenablesOnlyAfterWorkerCompletion() async throws {
        let (bundle, root) = try bundle(); defer { try? FileManager.default.removeItem(at: root) }
        let calls = Calls()
        let controller = BelugaUpdateController(bundle: bundle, operations: .init(
            hasFence: { _ in calls.add("fence"); return false }, begin: { _, _ in calls.add("check") },
            ready: { _, _ in calls.add("unexpected-readiness") }))
        XCTAssertEqual(calls.snapshot, ["fence"])
        XCTAssertFalse(controller.canCheckForUpdates)
        controller.updateAdmission(idle)
        controller.checkForUpdates(); controller.checkForUpdates()
        XCTAssertTrue(controller.isUpdateInProgress)
        XCTAssertFalse(controller.canCheckForUpdates)
        await controller.waitForCurrentOperation()
        XCTAssertEqual(calls.snapshot, ["fence", "check"])
        XCTAssertTrue(controller.canCheckForUpdates)
        XCTAssertFalse(controller.isUpdateInProgress)
    }

    @MainActor func testPendingMarkerBlocksBeforeUIAndReadinessRunsExactlyOnce() async throws {
        let (bundle, root) = try bundle(); defer { try? FileManager.default.removeItem(at: root) }
        let calls = Calls()
        let controller = BelugaUpdateController(bundle: bundle, operations: .init(
            hasFence: { _ in true }, begin: { _, _ in calls.add("unexpected-check") },
            ready: { _, _ in calls.add("ready") }))
        controller.updateAdmission(idle)
        XCTAssertTrue(controller.isUpdateInProgress)
        controller.checkForUpdates()
        controller.menuDidBecomeReady(); controller.menuDidBecomeReady()
        await controller.waitForCurrentOperation()
        controller.menuDidBecomeReady()
        XCTAssertEqual(calls.snapshot, ["ready"])
        XCTAssertFalse(controller.isUpdateInProgress)
        XCTAssertTrue(controller.canCheckForUpdates)
    }

    @MainActor func testReadinessAndCheckFailureStayBlockedWithoutAutomaticRetry() async throws {
        for pending in [true, false] {
            let (bundle, root) = try bundle(); defer { try? FileManager.default.removeItem(at: root) }
            let calls = Calls()
            let controller = BelugaUpdateController(bundle: bundle, operations: .init(
                hasFence: { _ in pending }, begin: { _, _ in calls.add("attempt"); throw Failure.refused },
                ready: { _, _ in calls.add("attempt"); throw Failure.refused }))
            controller.updateAdmission(idle)
            if pending { controller.menuDidBecomeReady() } else { controller.checkForUpdates() }
            await controller.waitForCurrentOperation()
            controller.updateAdmission(idle)
            controller.menuDidBecomeReady(); controller.checkForUpdates()
            XCTAssertEqual(calls.snapshot, ["attempt"])
            XCTAssertTrue(controller.isUpdateInProgress)
            XCTAssertFalse(controller.canCheckForUpdates)
        }
    }

    @MainActor func testActiveMediaPairingSharingAndTeardownDenyCheckWithoutWorker() async throws {
        let (bundle, root) = try bundle(); defer { try? FileManager.default.removeItem(at: root) }
        let calls = Calls()
        let controller = BelugaUpdateController(bundle: bundle, operations: .init(
            hasFence: { _ in false }, begin: { _, _ in calls.add("unexpected") }, ready: { _, _ in }))
        for state in [BelugaUpdateAdmission(),
                      .init(isInteractiveApplication: true, hasActiveMedia: true, teardownComplete: true),
                      .init(isInteractiveApplication: true, hasPendingPairing: true, teardownComplete: true),
                      .init(isInteractiveApplication: true, hasAudioShares: true, teardownComplete: true),
                      .init(isInteractiveApplication: true, teardownComplete: false)] {
            controller.updateAdmission(state)
            controller.checkForUpdates()
            XCTAssertFalse(controller.canCheckForUpdates)
        }
        XCTAssertEqual(calls.snapshot, [])
    }
}
