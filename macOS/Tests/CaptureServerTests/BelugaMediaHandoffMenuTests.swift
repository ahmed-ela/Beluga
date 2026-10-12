import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import CaptureServer

@MainActor
final class BelugaMediaHandoffMenuTests: XCTestCase {
    private var renderedWindows: [ObjectIdentifier: NSWindow] = [:]
    private var renderedPopovers: [ObjectIdentifier: NSPopover] = [:]
    private static var renderedApplicationPrepared = false
    func testControlStaysVisibleAcrossDisconnectReconnectAndUnavailablePresentation() {
        let original = target(), probe = HandoffMenuProbe()
        let model = started(probe, target: original)
        assertControl(model, reason: .ready, enabled: true)

        let waitingPhases: [BelugaHostPresentationPhase] = [
            .pairedConnecting, .pairedWaiting, .preparingSession, .unavailable
        ]
        for (index, phase) in waitingPhases.enumerated() {
            model.apply(presentation(UInt64(index + 2), target: nil, phase: phase))
            assertControl(model, reason: .waitingForSession)
            XCTAssertNil(model.moveMedia(to: original))
        }
        model.apply(presentation(6, target: nil))
        // A generic availability phase cannot manufacture prepared media admission.
        assertControl(model, reason: .waitingForSession)
        XCTAssertNil(model.moveMedia(to: original))

        let replacement = target()
        model.apply(presentation(7, target: replacement))
        assertControl(model, reason: .ready, enabled: true)
        XCTAssertNil(model.moveMedia(to: original), "A visible control cannot retarget an old click")
        XCTAssertEqual(probe.targets, [])
    }

    func testStartCommandAvailabilityAndStopHaveTruthfulDisabledReasons() {
        let model = BelugaMenuBarModel(), current = target(), probe = HandoffMenuProbe()
        assertControl(model, reason: .notStarted, visible: false)
        model.apply(presentation(1, target: current))
        model.start = { false }; model.begin()
        assertControl(model, reason: .notStarted, visible: false)

        model.start = { true }; model.begin()
        assertControl(model, reason: .commandUnavailable)
        model.installPhoneCommands(.init { _, _ in XCTFail("No catalog action expected") })
        assertControl(model, reason: .commandUnavailable)
        model.installPhoneCommands(probe.commands)
        assertControl(model, reason: .ready, enabled: true)
        model.installPhoneCommands(.init { _, _ in XCTFail("No catalog action expected") })
        assertControl(model, reason: .commandUnavailable)
        XCTAssertNil(model.moveMedia(to: current))

        model.finished()
        assertControl(model, reason: .stopped)
        model.installPhoneCommands(probe.commands)
        model.apply(presentation(2, target: current))
        assertControl(model, reason: .stopped)
        XCTAssertNil(model.moveMedia(to: current))
        XCTAssertEqual(probe.targets, [])
    }

    func testPreparedTargetAndInFlightRequestSurviveAvailabilityPresentationChanges() async throws {
        let current = target(), probe = HandoffMenuProbe(holds: true)
        defer { probe.release() }
        let model = started(probe, target: current)
        model.apply(presentation(2, target: current, phase: .unavailable))
        assertControl(model, reason: .ready, enabled: true)
        model.apply(presentation(3, target: current, phase: .preparingSession))
        assertControl(model, reason: .ready, enabled: true)

        let task = try XCTUnwrap(model.moveMedia(to: current))
        let entered = await probe.waitForEntry()
        XCTAssertTrue(entered)
        for (offset, phase) in [BelugaHostPresentationPhase.unavailable, .preparingSession].enumerated() {
            model.apply(presentation(UInt64(offset + 4), target: current, phase: phase))
            assertControl(model, reason: .requestInFlight)
            XCTAssertTrue(model.isRequestingMediaHandoff)
            XCTAssertEqual(model.presentation.connectedMediaTarget, current)
            XCTAssertFalse(task.isCancelled, "Availability is not retirement of the media owner")
        }
        probe.release()
        await task.value
        assertControl(model, reason: .ready, enabled: true)
        XCTAssertEqual(probe.targets, [current])
        XCTAssertNotNil(model.mediaHandoffMessage)

        model.apply(presentation(6, target: nil, phase: .preparingSession))
        assertControl(model, reason: .waitingForSession)
        XCTAssertNil(model.moveMedia(to: current))
    }

    func testChangingPhoneKeepsControlVisibleButCannotDispatch() async throws {
        let current = target(), probe = HandoffMenuProbe()
        let model = started(probe, target: current)
        let ticket = WorldwidePhoneCatalogAction(
            token: WorldwidePairedPhoneCatalogToken(catalogID: UUID(), revision: 1),
            selectionEpoch: current.selectionEpoch
        )
        model.installPhoneCommands(.init(moveMedia: probe.commands.moveMedia, perform: { _, _ in }))
        model.apply(.init(revision: 2, phase: .sessionPrepared, pairedPhoneName: "Test Phone",
            invitation: nil,
            phones: .init(items: [.init(id: current.phoneID, name: "Test Phone", needsPairingRecovery: false)],
                selectedPhoneID: current.phoneID, action: ticket, canAddPhone: true),
            connectedMediaTarget: current))
        assertControl(model, reason: .ready, enabled: true)

        let change = try XCTUnwrap(model.changePhone(.select(nil), ticket: ticket))
        XCTAssertTrue(model.isChangingPhone)
        assertControl(model, reason: .changingPhone)
        XCTAssertNil(model.moveMedia(to: current))
        XCTAssertEqual(probe.targets, [])
        await change.value
        assertControl(model, reason: .ready, enabled: true)
    }

    func testDisconnectRetiresInFlightRequestWithoutHidingControlOrPublishingLateResult() async throws {
        let original = target(), probe = HandoffMenuProbe(holds: true)
        defer { probe.release() }
        let model = started(probe, target: original)
        let request = try XCTUnwrap(model.moveMedia(to: original))
        let entered = await probe.waitForEntry()
        XCTAssertTrue(entered)
        assertControl(model, reason: .requestInFlight)

        model.apply(presentation(2, target: nil, phase: .pairedWaiting))
        assertControl(model, reason: .waitingForSession)
        XCTAssertFalse(model.isRequestingMediaHandoff)
        let replacement = target()
        model.apply(presentation(3, target: replacement))
        assertControl(model, reason: .ready, enabled: true)
        XCTAssertNil(model.moveMedia(to: original))
        probe.release(); await request.value
        assertControl(model, reason: .ready, enabled: true)
        XCTAssertNil(model.mediaHandoffMessage)
        XCTAssertEqual(probe.targets, [original])
    }

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
            BelugaConnectedPhoneMediaTarget(phoneID: UUID(), selectionEpoch: target.selectionEpoch,
                exchangeID: target.exchangeID, mediaOwnerID: target.mediaOwnerID),
            BelugaConnectedPhoneMediaTarget(phoneID: target.phoneID, selectionEpoch: UUID(),
                exchangeID: target.exchangeID, mediaOwnerID: target.mediaOwnerID),
            BelugaConnectedPhoneMediaTarget(phoneID: target.phoneID, selectionEpoch: target.selectionEpoch,
                exchangeID: "other", mediaOwnerID: target.mediaOwnerID),
            BelugaConnectedPhoneMediaTarget(phoneID: target.phoneID, selectionEpoch: target.selectionEpoch,
                exchangeID: target.exchangeID, mediaOwnerID: UUID())
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

    func testRenderedControlObservesStartupDisconnectReconnectOnSameHostingView() throws {
        try runRenderedScenario { try await self.renderedStartupDisconnectReconnect() }
    }

    func testRenderedPressKeepsExactTargetAndObservesInFlightCompletion() throws {
        try runRenderedScenario { try await self.renderedPressAndCompletion() }
    }

    func testRenderedUpdaterDisablesWithoutHidingOrDispatchingOnSameHost() throws {
        try runRenderedScenario { try await self.renderedUpdaterAdmission() }
    }

    func testRenderedControlKeepsObservationAfterSameHostDetachReattach() throws {
        try runRenderedScenario { try await self.renderedDetachReattach() }
    }

    func testActualMenuPopoverReopensWithCurrentSessionWithoutReplacingContent() throws {
        try runRenderedScenario {
            let original = self.target(), probe = HandoffMenuProbe()
            let model = self.started(probe, target: original)
            defer { model.finished() }
            try await self.withActualMenuPopover(model) { context in
                try await self.showActualPopover(context)
                _ = try await self.actualPopoverButton(context, enabled: true)
                try await self.closeActualPopover(context)
                model.apply(self.presentation(2, target: nil, phase: .pairedWaiting))
                try await self.showActualPopover(context)
                _ = try await self.actualPopoverButton(context, enabled: false,
                    reason: BelugaMediaHandoffDisabledReason.waitingForSession.message)
                try await self.closeActualPopover(context)
                let successor = self.target()
                model.apply(self.presentation(3, target: successor))
                try await self.showActualPopover(context)
                let buttonNode = try await self.actualPopoverButton(context, enabled: true)
                let button = try XCTUnwrap(buttonNode)
                XCTAssertTrue(try button.press())
                XCTAssertTrue(model.isRequestingMediaHandoff)
                let entered = await probe.waitForEntry()
                XCTAssertTrue(entered)
                _ = try await self.actualPopoverButton(context, enabled: true,
                    message: "Handoff requested. Open Beluga on the phone and tap Play if asked. Check the phone for confirmation.")
                XCTAssertEqual(probe.targets, [successor])
                XCTAssertNil(model.moveMedia(to: original))
                XCTAssertEqual(probe.targets, [successor])
            }
        }
    }

    func testActualMenuPopoverCompositorShowsPersistentControlAcrossReconnect() throws {
        try runRenderedScenario {
            guard #available(macOS 15.2, *) else {
                XCTFail("Owned compositor pixel proof requires the pinned ScreenCaptureKit API")
                throw HandoffRenderedFailure.unavailableCompositor
            }
            let matcherControls = try BelugaOwnedPopoverPixels.verifyExactOccurrencesControls()
            XCTAssertEqual(matcherControls.accepted, 2)
            XCTAssertEqual(matcherControls.refused, 5)
            FileHandle.standardOutput.write(Data(
                "ACTUAL_POPOVER_EXACT_MATCHER_CONTROLS accepted=\(matcherControls.accepted) refused=\(matcherControls.refused) fixture_only=true same_matcher=true\n".utf8))
            let probe = HandoffMenuProbe(), model = self.started(probe, target: self.target())
            let waitingReason = try XCTUnwrap(BelugaMediaHandoffDisabledReason.waitingForSession.message)
            defer { model.finished() }
            try await self.withActualMenuPopover(model) { context in
                try await self.showActualPopover(context)
                _ = try await self.actualPopoverButton(context, enabled: true)
                try await self.captureActualPopover(context, expectedTexts: ["Move media to phone"],
                    name: "actual-popover-ready")
                try await self.closeActualPopover(context)
                model.apply(self.presentation(2, target: nil, phase: .pairedWaiting))
                try await self.showActualPopover(context)
                _ = try await self.actualPopoverButton(context, enabled: false,
                    reason: BelugaMediaHandoffDisabledReason.waitingForSession.message)
                try await self.captureActualPopover(context,
                    expectedTexts: ["Move media to phone", waitingReason],
                    name: "actual-popover-waiting")
                try await self.closeActualPopover(context)
                model.apply(self.presentation(3, target: self.target()))
                try await self.showActualPopover(context)
                _ = try await self.actualPopoverButton(context, enabled: true)
                try await self.captureActualPopover(context, expectedTexts: ["Move media to phone"],
                    name: "actual-popover-reconnected")
                XCTAssertEqual(probe.targets, [])
            }
        }
    }

    private func withActualMenuPopover(_ model: BelugaMenuBarModel,
        scenario: @MainActor (HandoffActualPopoverContext) async throws -> Void) async throws {
        // Never use native updater operations, even if the test bundle later gains release metadata.
        let updater = BelugaUpdateController(operations: .init(
            hasFence: { _ in false },
            begin: { _, _ in XCTFail("Isolated menu must not begin an updater operation") },
            ready: { _, _ in XCTFail("Isolated menu must not acknowledge native updater readiness") }))
        let share = BelugaAudioShareModel()
        let popover = BelugaMenuPopoverFactory.make(model: model, updater: updater, share: share,
            hasEndpoint: true,
            quit: { XCTFail("Isolated menu must not quit the installed application") },
            startShare: { XCTFail("Isolated menu must not start sharing") },
            contentModifier: HandoffActualPopoverAXEnvironment())
        let controller = try XCTUnwrap(popover.contentViewController), host = controller.view
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 32))
        let window = NSPanel(contentRect: anchor.frame, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = anchor
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 40,
                                     y: screen.visibleFrame.minY + 40))
        let lifecycle = HandoffActualPopoverLifecycle()
        popover.delegate = lifecycle
        let context = HandoffActualPopoverContext(popover: popover, controller: controller,
            host: host, anchor: anchor, window: window, lifecycle: lifecycle,
            foreground: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        renderedWindows[ObjectIdentifier(host)] = window
        renderedPopovers[ObjectIdentifier(host)] = popover
        window.orderFront(nil)
        var outcome: Result<Void, Error>
        do { try await scenario(context); outcome = .success(()) }
        catch { outcome = .failure(error) }
        // Forced close is owned cleanup, not the behavioral performClose assertion above.
        let expectedClosed = lifecycle.requestedShows
        if popover.isShown { popover.close() }
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(2))
        while (popover.isShown || lifecycle.closed != expectedClosed) && clock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch { fatalError("Owned popover cleanup was cancelled before native close settled") }
        }
        guard !popover.isShown, lifecycle.closed == expectedClosed else {
            fatalError("Owned actual popover did not settle before application-loop retirement")
        }
        XCTAssertTrue(popover.contentViewController === controller)
        XCTAssertTrue(controller.view === host)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, context.foreground)
        popover.delegate = nil
        popover.contentViewController = nil
        window.contentView = nil
        window.close()
        renderedPopovers.removeValue(forKey: ObjectIdentifier(host))
        renderedWindows.removeValue(forKey: ObjectIdentifier(host))
        try outcome.get()
    }

    private func showActualPopover(_ context: HandoffActualPopoverContext) async throws {
        guard !context.popover.isShown, context.anchor.window === context.window,
              context.window.isVisible else { throw HandoffRenderedFailure.unavailablePopover }
        let count = context.lifecycle.shown + 1
        context.lifecycle.recordShowSubmission()
        context.popover.show(relativeTo: context.anchor.bounds, of: context.anchor, preferredEdge: .maxY)
        try await waitActualPopover(context, shown: true, eventCount: count)
    }

    private func closeActualPopover(_ context: HandoffActualPopoverContext) async throws {
        guard context.popover.isShown else { throw HandoffRenderedFailure.unavailablePopover }
        let count = context.lifecycle.closed + 1
        context.popover.performClose(nil)
        try await waitActualPopover(context, shown: false, eventCount: count)
    }

    private func waitActualPopover(_ context: HandoffActualPopoverContext,
                                   shown: Bool, eventCount: Int) async throws {
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(2))
        repeat {
            XCTAssertTrue(context.popover.contentViewController === context.controller)
            XCTAssertTrue(context.controller.view === context.host)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == context.foreground else {
                throw HandoffRenderedFailure.foregroundChanged
            }
            NSApplication.shared.updateWindows()
            let observed = shown ? context.lifecycle.shown : context.lifecycle.closed
            if context.popover.isShown == shown && observed == eventCount {
                if shown {
                    let window = try XCTUnwrap(context.host.window)
                    guard window.isVisible else { throw HandoffRenderedFailure.unavailablePopover }
                }
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        } while clock.now < deadline
        XCTFail("Actual NSPopover did not reach its own native show/close event")
        throw HandoffRenderedFailure.unavailablePopover
    }

    private func actualPopoverButton(_ context: HandoffActualPopoverContext, enabled: Bool,
        reason: String? = nil, message: String? = nil) async throws -> HandoffRenderedAXNode? {
        // This full-menu projection does not query an optional identifier on
        // unrelated controls. Every selected caption must still expose its exact
        // ID/role/state; denied or malformed selected reads remain terminal.
        // The original child-tree all-role identifier checks remain unchanged.
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(2))
        let reasons = Set([BelugaMediaHandoffDisabledReason.stopped, .notStarted,
            .changingPhone, .requestInFlight, .waitingForSession, .targetUnavailable,
            .commandUnavailable, .incompatibleCore].compactMap(\.message))
        let messages: Set<String> = [
            "Handoff requested. Open Beluga on the phone and tap Play if asked. Check the phone for confirmation.",
            "Handoff unavailable. Keep a supported YouTube video playing and Beluga open on the connected phone, then try again."
        ]
        var lastCaptions: [String] = []
        repeat {
            try actualPopoverContextFence(context)
            pumpRenderedContext(context.host)
            try actualPopoverContextFence(context)
            let rows = try renderedAXNodes(context.host).map { node -> HandoffActualPopoverCaption in
                let role = try node.role()
                let caption: String?
                switch role {
                case .button: caption = try node.label()
                case .staticText: caption = try node.textValue()
                default: caption = nil
                }
                return HandoffActualPopoverCaption(node: node, role: role, text: caption)
            }
            lastCaptions = rows.map { "role=\($0.role.rawValue) caption=\($0.text.map { String($0.prefix(256)) } ?? "not-a-text-role")" }
            do {
                let buttons = rows.filter { $0.role == .button && $0.text == "Move media to phone" }
                guard buttons.count == 1, let button = buttons.first else {
                    throw HandoffRenderedAXFailure.unexpectedState
                }
                guard try button.node.identifier() == "beluga.move-media-to-phone",
                      try button.node.enabled() == enabled else {
                    throw HandoffRenderedAXFailure.unexpectedState
                }
                try exactActualPopoverText(rows, vocabulary: ["Beluga"], expected: "Beluga",
                                           identifier: "beluga.menu-title")
                try exactActualPopoverText(rows, vocabulary: reasons, expected: reason,
                                           identifier: "beluga.media-handoff-disabled-reason")
                try exactActualPopoverText(rows, vocabulary: messages, expected: message,
                                           identifier: "beluga.media-handoff-message")
                try actualPopoverContextFence(context)
                return button.node
            } catch HandoffRenderedAXFailure.unexpectedState {
                // Only valid intermediate presentation can settle. Getter refusal
                // is never converted into absence or retried as a healthy state.
            }
            try await Task.sleep(for: .milliseconds(10))
        } while clock.now < deadline
        print("ACTUAL_POPOVER_CAPTION_EXPECTED enabled=\(enabled) reason=\(reason ?? "nil") message=\(message ?? "nil")")
        print("ACTUAL_POPOVER_CAPTION_OBSERVED " + lastCaptions.joined(separator: " | "))
        XCTFail("Actual-menu caption-scoped AX state did not reach exact selected IDs and state")
        throw HandoffRenderedFailure.unavailableAX
    }

    private func exactActualPopoverText(_ rows: [HandoffActualPopoverCaption],
        vocabulary: Set<String>, expected: String?, identifier: String) throws {
        // A known stale caption with the wrong textual role is still present.
        let matches = rows.filter { $0.text.map(vocabulary.contains) == true }
        guard let expected else {
            guard matches.isEmpty else { throw HandoffRenderedAXFailure.unexpectedState }
            return
        }
        guard vocabulary.contains(expected), matches.count == 1, let match = matches.first,
              match.role == .staticText, match.text == expected,
              try match.node.identifier() == identifier else {
            throw HandoffRenderedAXFailure.unexpectedState
        }
    }

    private func actualPopoverContextFence(_ context: HandoffActualPopoverContext) throws {
        guard Thread.isMainThread, NSApplication.shared.isRunning,
              context.popover.contentViewController === context.controller,
              context.controller.view === context.host, context.popover.isShown,
              let window = context.host.window, window.isVisible,
              window.occlusionState.contains(.visible),
              NSApplication.shared.windows.contains(where: { $0 === window }) else {
            throw HandoffRenderedFailure.unavailablePopover
        }
        guard context.foreground != nil,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == context.foreground else {
            throw HandoffRenderedFailure.foregroundChanged
        }
    }

    @available(macOS 15.2, *)
    private func captureActualPopover(_ context: HandoffActualPopoverContext,
                                     expectedTexts: [String], name: String) async throws {
        let window = try XCTUnwrap(context.host.window)
        let evidence = try await BelugaOwnedPopoverPixels.capture(window, expectedTexts: expectedTexts)
        XCTAssertEqual(evidence.processID, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(evidence.windowID, CGWindowID(window.windowNumber))
        XCTAssertEqual(evidence.ocrPixelScale, 3)
        XCTAssertEqual(evidence.ocrImage.width, evidence.width * 3)
        XCTAssertEqual(evidence.ocrImage.height, evidence.height * 3)
        XCTAssertEqual(evidence.exactTextOccurrences, Dictionary(uniqueKeysWithValues: expectedTexts.map { ($0, 1) }))
        print("ACTUAL_POPOVER_PIXELS name=\(name) window=\(evidence.windowID) size=\(evidence.width)x\(evidence.height) opaque=\(evidence.opaquePixels) contrast=\(evidence.luminanceRange) exactTexts=\(evidence.exactTextOccurrences.count) ocrScale=\(evidence.ocrPixelScale) ocrSize=\(evidence.ocrImage.width)x\(evidence.ocrImage.height)")
        let bitmap = NSBitmapImageRep(cgImage: evidence.image)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        if let directory = ProcessInfo.processInfo.environment["BELUGA_RENDERED_MENU_DIAGNOSTIC_DIR"] {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"),
                          options: .withoutOverwriting)
            let ocrBitmap = NSBitmapImageRep(cgImage: evidence.ocrImage)
            let ocrPNG = try XCTUnwrap(ocrBitmap.representation(using: .png, properties: [:]))
            try ocrPNG.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + "-ocr-3x.png"),
                             options: .withoutOverwriting)
        }
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name; attachment.lifetime = .keepAlways; activity.add(attachment)
        }
    }

    private func renderedStartupDisconnectReconnect() async throws {
        let probe = HandoffMenuProbe(), model = BelugaMenuBarModel()
        defer { model.finished() }
        let updates = HandoffRenderedUpdateProbe()
        let host = try makeRenderedHost(model, updates: updates)
        defer { releaseRenderedContext(host) }
        let identity = ObjectIdentifier(host)
        _ = try await renderedButton(in: host, present: false)
        model.start = { true }; model.begin(); model.installPhoneCommands(probe.commands)
        _ = try await renderedButton(in: host, enabled: false,
            reason: BelugaMediaHandoffDisabledReason.waitingForSession.message)
        let original = target()
        model.apply(presentation(1, target: original))
        _ = try await renderedButton(in: host, enabled: true)
        for (offset, phase) in [BelugaHostPresentationPhase.pairedConnecting,
            .pairedWaiting, .preparingSession, .unavailable].enumerated() {
            model.apply(presentation(UInt64(offset + 2), target: nil, phase: phase))
            _ = try await renderedButton(in: host, enabled: false,
                reason: BelugaMediaHandoffDisabledReason.waitingForSession.message)
        }
        let successor = target()
        model.apply(presentation(6, target: successor))
        _ = try await renderedButton(in: host, enabled: true)
        XCTAssertEqual(ObjectIdentifier(host), identity)
        XCTAssertEqual(probe.targets, [])
        try attachRenderedBitmap(host, name: "same-host-reconnected")
    }

    private func renderedPressAndCompletion() async throws {
        let original = target(), probe = HandoffMenuProbe(holds: true)
        defer { probe.release() }
        let model = started(probe, target: original), updates = HandoffRenderedUpdateProbe()
        defer { model.finished() }
        let host = try makeRenderedHost(model, updates: updates)
        defer { releaseRenderedContext(host) }
        let identity = ObjectIdentifier(host)
        let firstNode = try await renderedButton(in: host, enabled: true)
        let first = try XCTUnwrap(firstNode)
        let firstAccepted = try first.press()
        XCTAssertTrue(firstAccepted)
        XCTAssertTrue(model.isRequestingMediaHandoff,
            "An AX acknowledgement alone is not accepted command dispatch")
        // Change the target before the MainActor task gets a turn: no old click may retarget.
        let successor = target()
        model.apply(presentation(2, target: successor))
        _ = try await renderedButton(in: host, enabled: true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(probe.targets, [])
        let nextNode = try await renderedButton(in: host, enabled: true)
        let next = try XCTUnwrap(nextNode)
        let nextAccepted = try next.press()
        XCTAssertTrue(nextAccepted)
        let entered = await probe.waitForEntry()
        XCTAssertTrue(entered)
        _ = try await renderedButton(in: host, enabled: false,
            reason: BelugaMediaHandoffDisabledReason.requestInFlight.message)
        XCTAssertEqual(probe.targets, [successor])
        model.apply(presentation(3, target: successor, phase: .unavailable))
        _ = try await renderedButton(in: host, enabled: false,
            reason: BelugaMediaHandoffDisabledReason.requestInFlight.message)
        probe.release()
        _ = try await renderedButton(in: host, enabled: true,
            message: "Handoff requested. Open Beluga on the phone and tap Play if asked. Check the phone for confirmation.")
        XCTAssertEqual(ObjectIdentifier(host), identity)
        XCTAssertEqual(probe.targets, [successor])
        try attachRenderedBitmap(host, name: "same-host-request-finished")
    }

    private func renderedUpdaterAdmission() async throws {
        let current = target(), probe = HandoffMenuProbe()
        let model = started(probe, target: current), updates = HandoffRenderedUpdateProbe()
        let host = try makeRenderedHost(model, updates: updates)
        defer { releaseRenderedContext(host) }
        defer { model.finished() }
        let identity = ObjectIdentifier(host)
        _ = try await renderedButton(in: host, enabled: true)
        for _ in 0..<2 {
            updates.inProgress = true
            let disabledNode = try await renderedButton(in: host, enabled: false)
            let disabled = try XCTUnwrap(disabledNode)
            do {
                _ = try disabled.press()
            } catch HandoffRenderedAXFailure.bridge(let status) where status == .deniedSelector {
                // Explicit refusal of this action is legitimate for a disabled button.
                // Getter errors are never interpreted as a disabled state.
            }
            XCTAssertFalse(model.isRequestingMediaHandoff)
            let entered = await probe.waitForEntry()
            XCTAssertFalse(entered, "Disabled rendered control reached its fake command")
            XCTAssertEqual(probe.targets, [])
            updates.inProgress = false
            _ = try await renderedButton(in: host, enabled: true)
        }
        XCTAssertEqual(ObjectIdentifier(host), identity)
        try attachRenderedBitmap(host, name: "same-host-updater-returned")
    }

    private func renderedDetachReattach() async throws {
        let current = target(), probe = HandoffMenuProbe()
        let model = started(probe, target: current), updates = HandoffRenderedUpdateProbe()
        defer { model.finished() }
        let host = try makeRenderedHost(model, updates: updates)
        defer { releaseRenderedContext(host) }
        let identity = ObjectIdentifier(host)
        let parent = try XCTUnwrap(host.superview)
        _ = try await renderedButton(in: host, enabled: true)
        host.removeFromSuperview()
        model.apply(presentation(2, target: nil, phase: .pairedWaiting))
        parent.addSubview(host)
        _ = try await renderedButton(in: host, enabled: false,
            reason: BelugaMediaHandoffDisabledReason.waitingForSession.message)
        model.apply(presentation(3, target: target()))
        _ = try await renderedButton(in: host, enabled: true)
        XCTAssertTrue(host.superview === parent)
        XCTAssertEqual(ObjectIdentifier(host), identity)
        XCTAssertEqual(probe.targets, [])
        try attachRenderedBitmap(host, name: "same-host-reattached")
        host.removeFromSuperview()
    }

    private func runRenderedScenario(_ scenario: @escaping @MainActor () async throws -> Void) throws {
        guard Thread.isMainThread else {
            XCTFail("AppKit rendering requires the native main thread")
            throw HandoffRenderedFailure.offMainThread
        }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let application = NSApplication.shared
        guard !application.isRunning, application.delegate == nil else {
            XCTFail("Rendered tests may own only an idle application with no delegate")
            throw HandoffRenderedFailure.unownedApplicationLoop
        }
        if !Self.renderedApplicationPrepared {
            application.setActivationPolicy(.accessory)
            Self.renderedApplicationPrepared = true
        }
        let wake = try XCTUnwrap(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 0, data1: 0, data2: 0))
        print("RENDERED_MENU_APPLICATION_LOOP before=\(application.isRunning) mainThread=\(Thread.isMainThread)")
        var result: Result<Void, Error>?
        let task = Task { @MainActor in
            do {
                try await scenario()
                result = .success(())
            } catch {
                result = .failure(error)
            }
            application.stop(nil)
            application.postEvent(wake, atStart: true)
        }
        application.run()
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmostPID)
        guard let result else {
            task.cancel()
            // Cancellation is not joined retirement. Abort this owned XCTest process
            // so a late completion cannot stop a later scenario's application loop.
            fatalError("Application loop returned before the owned scenario settled")
        }
        XCTAssertFalse(application.isRunning)
        XCTAssertTrue(renderedWindows.isEmpty, "The scenario must release its owned UI before stopping")
        XCTAssertTrue(renderedPopovers.isEmpty, "The scenario must release its actual popovers before stopping")
        try result.get()
    }

    private func makeRenderedHost(_ model: BelugaMenuBarModel,
                                  updates: HandoffRenderedUpdateProbe) throws -> NSView {
        guard Thread.isMainThread, NSApplication.shared.isRunning else {
            XCTFail("Rendered host requires the native main thread and running AppKit event loop")
            throw HandoffRenderedFailure.unownedApplicationLoop
        }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // This is the sole root construction. Never assign rootView, resize or reconstruct
        // it after a model mutation: doing so would mask a missing @ObservedObject.
        let controller = NSHostingController(rootView: HandoffRenderedRoot(model: model, updates: updates)
            .environment(\.accessibilityEnabled, true))
        let host = controller.view
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 220)
        let window = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentViewController = controller
        renderedWindows[ObjectIdentifier(host)] = window
        XCTAssertTrue(host.window === window)
        XCTAssertTrue(window.contentViewController === controller)
        let screen = NSScreen.main ?? NSScreen.screens.first
        XCTAssertNotNil(screen, "Rendered UI requires a real display context")
        if let screen {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 20,
                                          y: screen.visibleFrame.minY + 20))
            window.orderFront(nil)
            XCTAssertTrue(screen.visibleFrame.contains(window.frame))
        }
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(window.isMainWindow)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmostPID)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func releaseRenderedContext(_ host: NSView) {
        guard let window = renderedWindows.removeValue(forKey: ObjectIdentifier(host)) else { return }
        host.removeFromSuperview()
        window.contentViewController = nil
        window.close()
    }

    private func renderedButton(in host: NSView,
                                present: Bool = true, enabled: Bool = false,
                                reason: String? = nil, message: String? = nil,
                                sentinelIdentifier: String = "beluga.render-test-sentinel",
                                sentinelText: String = "Rendered menu test host") async throws -> HandoffRenderedAXNode? {
        let identity = ObjectIdentifier(host), clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        repeat {
            pumpRenderedContext(host)
            let nodes = try renderedAXNodes(host)
            do {
                let button = try exactRenderedButton(nodes, present: present, enabled: enabled)
                let validReason = try hasExactRenderedText(nodes,
                    identifier: "beluga.media-handoff-disabled-reason", expected: reason)
                let validMessage = try hasExactRenderedText(nodes,
                    identifier: "beluga.media-handoff-message", expected: message)
                let initializedHost = try hasExactRenderedText(nodes,
                    identifier: sentinelIdentifier, expected: sentinelText)
                if initializedHost && validReason && validMessage {
                    XCTAssertEqual(ObjectIdentifier(host), identity)
                    return button
                }
            } catch HandoffRenderedAXFailure.unexpectedState {
                // A valid intermediate UI state may settle on this same host.
                // Denied, malformed, oversized or unsupported AX reads are terminal.
            }
            try await Task.sleep(for: .milliseconds(10))
        } while clock.now < deadline
        // No model-derived substitute or skip if the real offscreen AX tree is unavailable.
        let observed = try renderedAXNodes(host).map { node in
            let role = try node.role()
            let text = role == .staticText ? try node.textValue()
                : role == .button ? try node.label() : nil
            let enabled = role == .button ? String(try node.enabled()) : "not-applicable"
            return "role=\(role.rawValue) "
                + "id=\(try node.identifier() ?? "nil") "
                + "text=\(text ?? "nil") "
                + "enabled=\(enabled)"
        }
        print("RENDERED_MENU_AX_EXPECTED present=\(present) enabled=\(enabled) reason=\(reason ?? "nil") message=\(message ?? "nil")")
        print("RENDERED_MENU_AX_OBSERVED " + observed.joined(separator: " | "))
        print(renderedContextDescription(host))
        try attachRenderedBitmap(host, name: "failed-ax")
        XCTFail("Same-host rendered AX state did not reach the exact expected button/text state")
        throw HandoffRenderedFailure.unavailableAX
    }

    private func pumpRenderedContext(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        NSApplication.shared.updateWindows()
        host.displayIfNeeded()
    }

    private func renderedContextDescription(_ host: NSView) -> String {
        "RENDERED_MENU_CONTEXT navigationChildren=\(host.accessibilityChildrenInNavigationOrder()?.count ?? 0) subviews=\(host.subviews.count) mainThread=\(Thread.isMainThread) applicationRunning=\(NSApplication.shared.isRunning) frame=\(host.frame) bounds=\(host.bounds) hidden=\(host.isHiddenOrHasHiddenAncestor) superviewFrame=\(String(describing: host.superview?.frame)) windowVisible=\(host.window?.isVisible ?? false) windowOcclusion=\(host.window?.occlusionState.rawValue ?? 0) viewType=\(String(describing: type(of: host))) layerBacked=\(host.wantsLayer)"
    }

    private func attachRenderedBitmap(_ host: NSView, name: String) throws {
        host.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        XCTAssertGreaterThan(image.pixelsWide, 0)
        XCTAssertGreaterThan(image.pixelsHigh, 0)
        let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        XCTAssertFalse(png.isEmpty)
        XCTAssertLessThan(png.count, 2 * 1024 * 1024)
        if let directory = ProcessInfo.processInfo.environment["BELUGA_RENDERED_MENU_DIAGNOSTIC_DIR"] {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
            try png.write(to: path, options: .withoutOverwriting)
        }
        // Diagnostic paint output only: nonempty PNG bytes do not prove nonblank pixels.
        // The pass/fail correctness assertions above come from real same-host AX state.
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func assertControl(_ model: BelugaMenuBarModel,
                               reason: BelugaMediaHandoffDisabledReason,
                               enabled: Bool = false, visible: Bool = true,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.mediaHandoffControl.visible, visible, file: file, line: line)
        XCTAssertEqual(model.mediaHandoffControl.enabled, enabled, file: file, line: line)
        XCTAssertEqual(model.mediaHandoffControl.reason, reason, file: file, line: line)
        XCTAssertEqual(model.canMoveMedia, enabled, file: file, line: line)
    }

    private func target() -> BelugaConnectedPhoneMediaTarget {
        .init(phoneID: UUID(), selectionEpoch: UUID(), exchangeID: UUID().uuidString,
              mediaOwnerID: UUID())
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

@MainActor
private final class HandoffRenderedUpdateProbe: ObservableObject {
    @Published var inProgress = false
}

@MainActor
private struct HandoffRenderedRoot: View {
    // Intentionally NOT @ObservedObject: only the production child may observe model.
    let model: BelugaMenuBarModel
    @ObservedObject var updates: HandoffRenderedUpdateProbe
    @Environment(\.accessibilityEnabled) private var accessibilityEnabled
    var body: some View {
        let _ = print("RENDERED_MENU_ROOT_BODY mainThread=\(Thread.isMainThread) started=\(model.hasStarted) accessibilityEnabled=\(accessibilityEnabled)")
        VStack(alignment: .leading) {
            Text("Rendered menu test host")
                .accessibilityIdentifier("beluga.render-test-sentinel")
            BelugaMediaHandoffControlsView(model: model, isUpdateInProgress: updates.inProgress)
        }
        .padding(18).frame(width: 360, height: 220, alignment: .topLeading)
    }
}

private enum HandoffRenderedFailure: Error {
    case unavailableAX, offMainThread, unownedApplicationLoop
    case unavailablePopover, unavailableCompositor, foregroundChanged
}

@MainActor
private struct HandoffActualPopoverAXEnvironment: ViewModifier {
    func body(content: Content) -> some View { content.environment(\.accessibilityEnabled, true) }
}

@MainActor
private final class HandoffActualPopoverLifecycle: NSObject, NSPopoverDelegate {
    private(set) var requestedShows = 0
    private(set) var shown = 0
    private(set) var closed = 0
    func recordShowSubmission() { requestedShows += 1 }
    func popoverDidShow(_ notification: Notification) { shown += 1 }
    func popoverDidClose(_ notification: Notification) { closed += 1 }
}

@MainActor
private struct HandoffActualPopoverContext {
    let popover: NSPopover
    let controller: NSViewController
    let host: NSView
    let anchor: NSView
    let window: NSWindow
    let lifecycle: HandoffActualPopoverLifecycle
    let foreground: pid_t?
}

@MainActor
private struct HandoffActualPopoverCaption {
    let node: HandoffRenderedAXNode
    let role: NSAccessibility.Role
    let text: String?
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
