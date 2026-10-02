import Foundation
import XCTest
@testable import CaptureServer

final class BelugaAudioShareModelTests: XCTestCase {
    @MainActor
    func testNoStartDuringUpdateOrWithoutOwnedRuntime() async {
        let probe = ShareUIProbe()
        let model = configured(probe)
        model.start(ownerIsValid: false, updateInProgress: false)
        model.start(ownerIsValid: true, updateInProgress: true)
        await Task.yield()
        let count = await probe.starts
        XCTAssertEqual(count, 0)
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.url)
    }

    @MainActor
    func testFailedStopQuarantinesNewStartAndUpdaterAdmission() async throws {
        let probe = ShareUIProbe(stopConfirmed: false)
        let model = configured(probe)
        model.stop()
        // Observe committed actor state, not @Published's pre-assignment notification.
        // The bounded async wait avoids XCTest's nested waiter/async-observation runtime path.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.isWorking, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertFalse(model.isWorking, "UI stop must reach its terminal result within two seconds")
        XCTAssertTrue(model.isQuarantined)
        XCTAssertTrue(model.hasPendingOrActiveShare)
        model.start(ownerIsValid: true, updateInProgress: false)
        let count = await probe.starts
        XCTAssertEqual(count, 0)
        model.ownerStopped()
        XCTAssertFalse(model.isQuarantined)
        XCTAssertFalse(model.hasPendingOrActiveShare)
    }

    @MainActor
    func testOwnerRetirementRejectsLateStatusAndCannotRecreateShare() async {
        let probe = ShareUIProbe()
        let model = configured(probe)
        model.ownerStopped()
        model.apply(.active(listeners: 8), revision: 9)
        model.apply(.failed, revision: 10)
        model.start(ownerIsValid: true, updateInProgress: false)
        model.stop()
        await Task.yield()
        let starts = await probe.starts, stops = await probe.stops
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(stops, 0)
        XCTAssertEqual(model.listenerCount, 0)
        XCTAssertFalse(model.hasPendingOrActiveShare)
    }

    @MainActor
    private func configured(_ probe: ShareUIProbe) -> BelugaAudioShareModel {
        let model = BelugaAudioShareModel()
        model.configure(start: { try await probe.start($0) }, stop: { await probe.stop() }, revoke: {})
        return model
    }
}

private actor ShareUIProbe {
    var starts = 0
    var stops = 0
    let stopConfirmed: Bool
    init(stopConfirmed: Bool = true) { self.stopConfirmed = stopConfirmed }
    func start(_ seconds: Int) throws -> BelugaAudioShareStarted {
        starts += 1
        throw BelugaAudioShareCoordinatorError.unavailable
    }
    func stop() -> Bool { stops += 1; return stopConfirmed }
}
