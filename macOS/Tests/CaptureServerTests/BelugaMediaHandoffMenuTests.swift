import Foundation
import XCTest
@testable import CaptureServer

@MainActor
final class BelugaMediaHandoffMenuTests: XCTestCase {
    func testNeedsStartedRuntimeCurrentConnectedTargetAndInstalledCommand() {
        let model = BelugaMenuBarModel(), target = target()
        model.apply(presentation(1, target: target))
        XCTAssertFalse(model.canMoveMedia)
        model.start = { true }; model.begin()
        XCTAssertFalse(model.canMoveMedia)
        model.installPhoneCommands(.init { _, _ in XCTFail("Not a catalog mutation") })
        XCTAssertFalse(model.canMoveMedia)
        let probe = HandoffMenuProbe()
        model.installPhoneCommands(probe.commands)
        XCTAssertTrue(model.canMoveMedia)
        model.apply(presentation(2, target: nil, phase: .pairedWaiting))
        XCTAssertFalse(model.canMoveMedia)
        XCTAssertNil(model.moveMedia(to: target))
        XCTAssertEqual(probe.targets, [])
    }

    func testClickSendsExactTargetOnceAndDoesNotClaimTransferCompletion() async throws {
        let target = target(), probe = HandoffMenuProbe(holds: true)
        defer { probe.release() }
        let model = started(probe, target: target)
        let task = try XCTUnwrap(model.moveMedia(to: target))
        let entered = await probe.waitForEntry()
        XCTAssertTrue(entered)
        XCTAssertTrue(model.isRequestingMediaHandoff)
        XCTAssertFalse(model.canMoveMedia)
        XCTAssertNil(model.moveMedia(to: target))
        probe.release(); await task.value
        XCTAssertEqual(probe.targets, [target])
        XCTAssertFalse(model.isRequestingMediaHandoff)
        XCTAssertEqual(model.mediaHandoffMessage,
            "Handoff requested. Open Beluga on the phone and tap Play if asked. Check the phone for confirmation.")
    }

    func testStalePhoneSelectionAndSessionTargetsCannotReachCommand() {
        let target = target(), probe = HandoffMenuProbe()
        let model = started(probe, target: target)
        for stale in [
            BelugaConnectedPhoneMediaTarget(phoneID: UUID(), selectionEpoch: target.selectionEpoch, exchangeID: target.exchangeID),
            BelugaConnectedPhoneMediaTarget(phoneID: target.phoneID, selectionEpoch: UUID(), exchangeID: target.exchangeID),
            BelugaConnectedPhoneMediaTarget(phoneID: target.phoneID, selectionEpoch: target.selectionEpoch, exchangeID: "other")
        ] { XCTAssertNil(model.moveMedia(to: stale)) }
        XCTAssertEqual(probe.targets, [])
        XCTAssertTrue(model.canMoveMedia)
    }

    func testSessionChangeBeforeTaskRunsPreventsDispatch() async throws {
        let target = target(), probe = HandoffMenuProbe()
        let model = started(probe, target: target)
        let task = try XCTUnwrap(model.moveMedia(to: target))
        let successor = self.target()
        model.apply(presentation(2, target: successor))
        await task.value
        XCTAssertEqual(probe.targets, [])
        XCTAssertNil(model.mediaHandoffMessage)
        XCTAssertFalse(model.isRequestingMediaHandoff)
        XCTAssertTrue(model.canMoveMedia)
    }

    func testLateOldResultCannotPublishIntoReplacementSession() async throws {
        for fails in [false, true] {
            let target = target(), probe = HandoffMenuProbe(holds: true, fails: fails)
            defer { probe.release() }
            let model = started(probe, target: target)
            let task = try XCTUnwrap(model.moveMedia(to: target))
            let entered = await probe.waitForEntry()
            XCTAssertTrue(entered)
            let successor = self.target()
            model.apply(presentation(2, target: successor))
            probe.release(); await task.value
            XCTAssertEqual(model.presentation.connectedMediaTarget, successor)
            XCTAssertNil(model.mediaHandoffMessage)
            XCTAssertTrue(model.canMoveMedia)
        }
    }

    func testShutdownClearsTargetAndIgnoresLateCompletionAndCallbacks() async throws {
        let target = target(), probe = HandoffMenuProbe(holds: true)
        defer { probe.release() }
        let model = started(probe, target: target)
        let task = try XCTUnwrap(model.moveMedia(to: target))
        let entered = await probe.waitForEntry()
        XCTAssertTrue(entered)
        model.finished()
        model.installPhoneCommands(probe.commands)
        model.apply(presentation(2, target: target))
        probe.release(); await task.value
        XCTAssertNil(model.presentation.connectedMediaTarget)
        XCTAssertNil(model.mediaHandoffMessage)
        XCTAssertFalse(model.canMoveMedia)
        XCTAssertFalse(model.isRequestingMediaHandoff)
    }

    func testRefusalIsSanitizedAndCannotClaimNoMacEffectOrSuccess() async throws {
        let target = target(), probe = HandoffMenuProbe(fails: true)
        let model = started(probe, target: target)
        let task = try XCTUnwrap(model.moveMedia(to: target)); await task.value
        XCTAssertEqual(model.mediaHandoffMessage,
            "Handoff unavailable. Keep a supported YouTube video playing and Beluga open on the connected phone, then try again.")
        XCTAssertFalse(model.mediaHandoffMessage!.contains("TESTONLY"))
        XCTAssertFalse(model.isRequestingMediaHandoff)
    }

    func testTargetDescriptionsDoNotDiscloseSessionOrPhoneIdentifiers() {
        let target = target()
        for value in [String(describing: target), String(reflecting: target)] {
            XCTAssertFalse(value.contains(target.exchangeID))
            XCTAssertFalse(value.contains(target.phoneID.uuidString))
            XCTAssertFalse(value.contains(target.selectionEpoch.uuidString))
        }
    }

    private func target() -> BelugaConnectedPhoneMediaTarget {
        .init(phoneID: UUID(), selectionEpoch: UUID(), exchangeID: UUID().uuidString)
    }
    private func presentation(_ revision: UInt64, target: BelugaConnectedPhoneMediaTarget?,
                              phase: BelugaHostPresentationPhase = .sessionPrepared) -> BelugaHostPresentation {
        .init(revision: revision, phase: phase, pairedPhoneName: "Test Phone", invitation: nil,
              connectedMediaTarget: target)
    }
    private func started(_ probe: HandoffMenuProbe, target: BelugaConnectedPhoneMediaTarget) -> BelugaMenuBarModel {
        let model = BelugaMenuBarModel()
        model.start = { true }; model.begin(); model.installPhoneCommands(probe.commands)
        model.apply(presentation(1, target: target))
        return model
    }
}

private final class HandoffMenuProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let holds: Bool
    private let fails: Bool
    private var invocations: [BelugaConnectedPhoneMediaTarget] = []
    private var waiter: CheckedContinuation<Void, Never>?
    private var released = false
    var targets: [BelugaConnectedPhoneMediaTarget] { lock.withLock { invocations } }

    init(holds: Bool = false, fails: Bool = false) { self.holds = holds; self.fails = fails }
    var commands: BelugaPhoneCatalogCommands {
        .init(moveMedia: { [self] target in
            lock.withLock { invocations.append(target) }
            if holds {
                await withCheckedContinuation { continuation in
                    let resume = lock.withLock {
                        if released { return true }
                        waiter = continuation; return false
                    }
                    if resume { continuation.resume() }
                }
            }
            if fails { throw Failure.refused }
            return UUID()
        }, perform: { _, _ in XCTFail("Handoff cannot mutate the paired-phone catalog") })
    }
    func release() {
        let pending = lock.withLock {
            released = true
            let pending = waiter; waiter = nil; return pending
        }
        pending?.resume()
    }
    func waitForEntry() async -> Bool {
        for _ in 0..<2_000 {
            if !targets.isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
    private enum Failure: Error, LocalizedError {
        case refused
        var errorDescription: String? { "TESTONLY private backend failure" }
    }
}
