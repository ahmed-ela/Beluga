import Combine
import Foundation
import XCTest
@testable import CaptureServer

final class BelugaPhoneCatalogMenuTests: XCTestCase {
    func testPhoneNamesFlattenWhitespaceAndRemoveControlAndBidiScalars() {
        let dirty = "  First\n\t\u{202E}Phone\u{2066}\u{2069}\u{0000}\rSecond\u{2028}Third\u{2029}End  "
        let phone = row(name: dirty)
        XCTAssertEqual(phone.name, "First Phone Second Third End")
        XCTAssertFalse(phone.name.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: return true
            default: return false
            }
        })
        XCTAssertFalse(phone.label.contains("\n"))
        XCTAssertFalse(phone.label.contains("\u{202E}"))
    }

    func testEmptyOrEntirelyInvisiblePhoneNameUsesFixedFallback() {
        let names: [String?] = [nil, "", " \n\t\u{202E}\u{2067}\u{0000}\u{2029}"]
        for name in names {
            let phone = row(name: name)
            XCTAssertEqual(phone.name, "Phone")
            XCTAssertEqual(phone.label, "Phone · 000011")
        }
    }

    func testPhoneNameAndLabelAreBoundedForASCIIEmojiAndCombiningSequences() {
        let names = [
            String(repeating: "A", count: 10_000),
            String(repeating: "🐳", count: 1_000),
            "a" + String(repeating: "\u{0301}", count: 10_000),
            String(repeating: "e\u{0301}", count: 1_000)
        ]
        for name in names {
            let phone = row(name: name)
            XCTAssertLessThanOrEqual(phone.name.count, 64)
            XCTAssertLessThanOrEqual(phone.name.utf8.count, 256)
            XCTAssertLessThanOrEqual(phone.label.count, 64 + 3 + 6)
            XCTAssertLessThanOrEqual(phone.label.utf8.count, 256 + " · ".utf8.count + 6)
            XCTAssertFalse(phone.name.isEmpty)
        }
    }

    func testSafeUnicodeAndStableIDSuffixDisambiguateDuplicateNames() {
        let first = row(name: "Téléphone 日本語 🐳")
        let second = row(id: phoneB, name: "Téléphone 日本語 🐳", needsRecovery: true)
        XCTAssertEqual(first.name, "Téléphone 日本語 🐳")
        XCTAssertEqual(first.label, "Téléphone 日本語 🐳 · 000011")
        XCTAssertEqual(second.label, "Téléphone 日本語 🐳 · 000022")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.label, second.label)
        XCTAssertTrue(second.needsPairingRecovery)
    }

    func testCatalogDiagnosticDescriptionsDoNotExposeNamesIDsOrTickets() {
        let item = row(name: "TESTONLY private phone name")
        let snapshot = catalog(items: [item], ticket: ticket())
        for description in [String(describing: snapshot), String(reflecting: snapshot)] {
            XCTAssertFalse(description.contains(item.name))
            XCTAssertFalse(description.contains(item.id.uuidString))
            XCTAssertFalse(description.contains(ticket().selectionEpoch.uuidString))
        }
    }

    @MainActor
    func testCommandsNeedStartedRuntimeInstalledBridgeAndCurrentQuietTicket() {
        let model = BelugaMenuBarModel()
        let action = ticket()
        model.apply(presentation(revision: 1, ticket: action))
        XCTAssertFalse(model.canChangePhone)
        model.start = { true }
        model.begin()
        XCTAssertFalse(model.canChangePhone)
        let probe = CatalogMenuCommandProbe()
        model.installPhoneCommands(probe.commands)
        XCTAssertTrue(model.canChangePhone)
        model.apply(presentation(revision: 2, ticket: nil, phase: .sessionPrepared))
        XCTAssertFalse(model.canChangePhone)
        XCTAssertNil(model.changePhone(.select(phoneA), ticket: action))
        XCTAssertEqual(probe.invocations, [])
    }

    @MainActor
    func testCommandBridgeInvalidatesObservedMenuWhenQuietPresentationArrivesFirst() {
        let model = BelugaMenuBarModel()
        let action = ticket()
        model.start = { true }
        model.begin()
        model.apply(presentation(revision: 1, ticket: action))
        XCTAssertFalse(model.canChangePhone)

        var observedReadiness: [Bool] = []
        let observation = model.objectWillChange.sink {
            observedReadiness.append(model.canChangePhone)
        }
        defer { observation.cancel() }

        let probe = CatalogMenuCommandProbe()
        model.installPhoneCommands(probe.commands)

        XCTAssertEqual(observedReadiness, [false],
            "Installing the late command bridge must invalidate SwiftUI before pairing becomes ready.")
        XCTAssertTrue(model.canChangePhone)
        XCTAssertEqual(model.presentation.phones.action, action)
        XCTAssertEqual(probe.invocations, [])
    }

    @MainActor
    func testCommandBridgeBeforeQuietPresentationDoesNotEnablePairingPrematurely() {
        let model = BelugaMenuBarModel()
        model.start = { true }
        model.begin()
        let probe = CatalogMenuCommandProbe()

        var observedReadiness: [Bool] = []
        let observation = model.objectWillChange.sink {
            observedReadiness.append(model.canChangePhone)
        }
        defer { observation.cancel() }

        model.installPhoneCommands(probe.commands)
        XCTAssertFalse(model.canChangePhone)
        XCTAssertEqual(observedReadiness, [false])

        let action = ticket()
        model.apply(presentation(revision: 1, ticket: action))

        XCTAssertEqual(observedReadiness, [false, false])
        XCTAssertTrue(model.canChangePhone)
        XCTAssertEqual(model.presentation.phones.action, action)
        XCTAssertEqual(probe.invocations, [])
    }

    @MainActor
    func testExactPresentedTicketAndPhoneIDReachCommandWithoutReplacement() async throws {
        let probe = CatalogMenuCommandProbe()
        let action = ticket()
        let model = startedModel(probe: probe, ticket: action)
        let task = try XCTUnwrap(model.changePhone(.select(phoneA), ticket: action))
        await task.value
        XCTAssertEqual(probe.invocations, [.init(command: .select(phoneA), ticket: action)])
        XCTAssertFalse(model.isChangingPhone)
        XCTAssertNil(model.phoneChangeMessage)
    }

    @MainActor
    func testPresentedConfirmationTicketIsStaleAfterCatalogRevisionChanges() {
        let probe = CatalogMenuCommandProbe()
        let original = ticket(revision: 1)
        let model = startedModel(probe: probe, ticket: original)
        let successor = ticket(revision: 2)
        model.apply(presentation(revision: 2, ticket: successor))
        XCTAssertNil(model.changePhone(.forget(phoneA), ticket: original))
        XCTAssertEqual(probe.invocations, [])
        XCTAssertFalse(model.isChangingPhone)
        XCTAssertNotNil(model.phoneChangeMessage)
        XCTAssertEqual(model.presentation.phones.action, successor)
    }

    @MainActor
    func testCatalogGenerationAndSelectionEpochChangesAlsoInvalidatePresentedTickets() {
        for changed in [
            ticket(catalogID: UUID(uuidString: "00000000-0000-0000-0000-000000000044")!),
            ticket(epoch: UUID(uuidString: "00000000-0000-0000-0000-000000000055")!)
        ] {
            let probe = CatalogMenuCommandProbe()
            let original = ticket()
            let model = startedModel(probe: probe, ticket: original)
            model.apply(presentation(revision: 2, ticket: changed))
            XCTAssertNil(model.changePhone(.select(phoneA), ticket: original))
            XCTAssertEqual(probe.invocations, [])
            XCTAssertFalse(model.isChangingPhone)
        }
    }

    @MainActor
    func testUnknownSelectAndForgetTargetsCannotReachCommand() {
        let unknown = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        for command in [BelugaPhoneCatalogCommand.select(unknown), .forget(unknown)] {
            let probe = CatalogMenuCommandProbe()
            let action = ticket()
            let model = startedModel(probe: probe, ticket: action)
            XCTAssertNil(model.changePhone(command, ticket: action))
            XCTAssertEqual(probe.invocations, [])
            XCTAssertFalse(model.isChangingPhone)
        }
    }

    @MainActor
    func testPresentedRemovedTargetCannotBeForgottenEvenWithCurrentTicket() {
        let probe = CatalogMenuCommandProbe()
        let action = ticket()
        let model = startedModel(probe: probe, ticket: action)
        let successor = ticket(revision: 2)
        model.apply(presentation(revision: 2, ticket: successor, items: [row(id: phoneB)]))
        XCTAssertNil(model.changePhone(.forget(phoneA), ticket: successor))
        XCTAssertEqual(probe.invocations, [])
    }

    @MainActor
    func testCapacityDeniesOnlyPairAnotherWithoutEvictingOrChangingSelection() async throws {
        let probe = CatalogMenuCommandProbe()
        let action = ticket()
        let model = startedModel(probe: probe, ticket: action, canAdd: false, selected: phoneA)
        XCTAssertNil(model.changePhone(.pairAnother, ticket: action))
        XCTAssertEqual(probe.invocations, [])
        XCTAssertEqual(model.presentation.phones.selectedPhoneID, phoneA)
        XCTAssertEqual(model.presentation.phones.items.map(\.id), [phoneA, phoneB])
        let task = try XCTUnwrap(model.changePhone(.select(phoneB), ticket: action))
        await task.value
        XCTAssertEqual(probe.invocations, [.init(command: .select(phoneB), ticket: action)])
    }

    @MainActor
    func testOnlyOnePendingCommandIsAdmittedAndOwnedTaskIsDrained() async throws {
        let probe = CatalogMenuCommandProbe(holdsCompletion: true)
        defer { probe.release() }
        let action = ticket()
        let model = startedModel(probe: probe, ticket: action)
        let task = try XCTUnwrap(model.changePhone(.select(phoneB), ticket: action))
        XCTAssertTrue(model.isChangingPhone)
        XCTAssertFalse(model.canChangePhone)
        XCTAssertNil(model.changePhone(.pairAnother, ticket: action))
        XCTAssertNil(model.changePhone(.forget(phoneA), ticket: action))
        let entered = await probe.waitForEntry()
        XCTAssertTrue(entered)
        XCTAssertEqual(probe.invocations, [.init(command: .select(phoneB), ticket: action)])
        probe.release()
        await task.value
        XCTAssertFalse(model.isChangingPhone)
    }

    @MainActor
    func testSuccessWaitsForAuthoritativePresentationInsteadOfOptimisticSelection() async throws {
        let probe = CatalogMenuCommandProbe()
        let action = ticket()
        let model = startedModel(probe: probe, ticket: action, selected: phoneA)
        let task = try XCTUnwrap(model.changePhone(.select(phoneB), ticket: action))
        await task.value
        XCTAssertEqual(model.presentation.phones.selectedPhoneID, phoneA)
        XCTAssertEqual(model.presentation.phones.action, action)
        let committed = ticket(revision: 2)
        model.apply(presentation(revision: 2, ticket: committed, selected: phoneB))
        XCTAssertEqual(model.presentation.phones.selectedPhoneID, phoneB)
        XCTAssertEqual(model.presentation.phones.action, committed)
    }

    @MainActor
    func testFailureKeepsCatalogAndUsesFixedMessageRatherThanUnderlyingError() async throws {
        let probe = CatalogMenuCommandProbe(shouldFail: true)
        let action = ticket()
        let model = startedModel(probe: probe, ticket: action, selected: phoneA)
        let task = try XCTUnwrap(model.changePhone(.forget(phoneA), ticket: action))
        await task.value
        XCTAssertFalse(model.isChangingPhone)
        XCTAssertEqual(model.presentation.phones.selectedPhoneID, phoneA)
        XCTAssertEqual(model.presentation.phones.items.map(\.id), [phoneA, phoneB])
        XCTAssertEqual(model.phoneChangeMessage,
            "Phone change was not applied. Wait until the current connection is idle, then try again.")
        XCTAssertFalse(model.phoneChangeMessage?.contains("TESTONLY") ?? true)
    }

    @MainActor
    func testExplicitNilSelectionIsForwardedWithoutForgettingAnyPhone() async throws {
        let probe = CatalogMenuCommandProbe()
        let action = ticket()
        let model = startedModel(probe: probe, ticket: action, selected: phoneA)
        let task = try XCTUnwrap(model.changePhone(.select(nil), ticket: action))
        await task.value
        XCTAssertEqual(probe.invocations, [.init(command: .select(nil), ticket: action)])
        XCTAssertEqual(model.presentation.phones.items.map(\.id), [phoneA, phoneB])
        XCTAssertEqual(model.presentation.phones.selectedPhoneID, phoneA)
    }

    @MainActor
    func testOlderOrEqualPresentationCannotRestoreSupersededCatalogTicket() {
        let probe = CatalogMenuCommandProbe()
        let original = ticket()
        let model = startedModel(probe: probe, ticket: original)
        let successor = ticket(revision: 2)
        model.apply(presentation(revision: 2, ticket: successor, selected: phoneB))
        model.apply(presentation(revision: 1, ticket: original, selected: phoneA))
        model.apply(presentation(revision: 2, ticket: original, selected: phoneA))
        XCTAssertEqual(model.presentation.phones.action, successor)
        XCTAssertEqual(model.presentation.phones.selectedPhoneID, phoneB)
        XCTAssertNil(model.changePhone(.forget(phoneA), ticket: original))
        XCTAssertEqual(probe.invocations, [])
    }

    @MainActor
    func testShutdownRejectsLateCommandBridgeAndActionWithoutChangingStoppedModel() {
        let probe = CatalogMenuCommandProbe()
        let action = ticket()
        let model = startedModel(probe: probe, ticket: action)
        model.finished()

        var lateUpdateCount = 0
        let observation = model.objectWillChange.sink { lateUpdateCount += 1 }
        defer { observation.cancel() }

        model.installPhoneCommands(probe.commands)
        model.apply(presentation(revision: 2, ticket: action))
        XCTAssertNil(model.changePhone(.pairAnother, ticket: action))
        XCTAssertEqual(lateUpdateCount, 0)
        XCTAssertEqual(probe.invocations, [])
        XCTAssertEqual(model.presentation.phase, .stopped)
        XCTAssertNil(model.presentation.phones.action)
        XCTAssertFalse(model.canChangePhone)
        XCTAssertFalse(model.isChangingPhone)
        XCTAssertNil(model.phoneChangeMessage)
    }

    @MainActor
    func testShutdownDropsLateSuccessAndFailureFromNonCooperativeCommand() async throws {
        for shouldFail in [false, true] {
            let probe = CatalogMenuCommandProbe(holdsCompletion: true, shouldFail: shouldFail)
            defer { probe.release() }
            let action = ticket()
            let model = startedModel(probe: probe, ticket: action)
            let task = try XCTUnwrap(model.changePhone(.forget(phoneA), ticket: action))
            let entered = await probe.waitForEntry()
            XCTAssertTrue(entered)
            model.finished()
            model.installPhoneCommands(probe.commands)
            model.apply(presentation(revision: 2, ticket: action, selected: phoneB))
            probe.release()
            await task.value
            XCTAssertEqual(probe.invocations.count, 1)
            XCTAssertEqual(model.presentation.phase, .stopped)
            XCTAssertNil(model.presentation.phones.action)
            XCTAssertFalse(model.canChangePhone)
            XCTAssertFalse(model.isChangingPhone)
            XCTAssertNil(model.phoneChangeMessage)
        }
    }

    private var phoneA: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000011")! }
    private var phoneB: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000022")! }

    private func row(id: UUID? = nil, name: String? = "Test Phone",
                     needsRecovery: Bool = false) -> BelugaPairedPhonePresentation {
        BelugaPairedPhonePresentation(id: id ?? phoneA, name: name,
                                     needsPairingRecovery: needsRecovery)
    }

    private func ticket(revision: UInt64 = 1,
                        catalogID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000033")!,
                        epoch: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000066")!)
        -> WorldwidePhoneCatalogAction {
        WorldwidePhoneCatalogAction(
            token: WorldwidePairedPhoneCatalogToken(catalogID: catalogID, revision: revision),
            selectionEpoch: epoch
        )
    }

    private func catalog(items: [BelugaPairedPhonePresentation]? = nil,
                         ticket: WorldwidePhoneCatalogAction?, canAdd: Bool = true,
                         selected: UUID? = nil) -> BelugaPhoneCatalogPresentation {
        BelugaPhoneCatalogPresentation(items: items ?? [row(), row(id: phoneB)],
            selectedPhoneID: selected, action: ticket, canAddPhone: canAdd)
    }

    private func presentation(revision: UInt64, ticket: WorldwidePhoneCatalogAction?,
                              items: [BelugaPairedPhonePresentation]? = nil, canAdd: Bool = true,
                              selected: UUID? = nil, phase: BelugaHostPresentationPhase = .unselected)
        -> BelugaHostPresentation {
        BelugaHostPresentation(revision: revision, phase: phase, pairedPhoneName: nil,
            invitation: nil, phones: catalog(items: items, ticket: ticket,
                                             canAdd: canAdd, selected: selected))
    }

    @MainActor
    private func startedModel(probe: CatalogMenuCommandProbe,
                              ticket: WorldwidePhoneCatalogAction,
                              canAdd: Bool = true, selected: UUID? = nil) -> BelugaMenuBarModel {
        let model = BelugaMenuBarModel()
        model.start = { true }
        model.begin()
        model.installPhoneCommands(probe.commands)
        model.apply(presentation(revision: 1, ticket: ticket, canAdd: canAdd, selected: selected))
        return model
    }
}

private final class CatalogMenuCommandProbe: @unchecked Sendable {
    struct Invocation: Equatable, Sendable {
        let command: BelugaPhoneCatalogCommand
        let ticket: WorldwidePhoneCatalogAction
    }

    private let lock = NSLock()
    private let holdsCompletion: Bool
    private let shouldFail: Bool
    private var calls: [Invocation] = []
    private var completion: CheckedContinuation<Void, Never>?
    private var isReleased = false

    init(holdsCompletion: Bool = false, shouldFail: Bool = false) {
        self.holdsCompletion = holdsCompletion
        self.shouldFail = shouldFail
    }

    var commands: BelugaPhoneCatalogCommands {
        BelugaPhoneCatalogCommands { [self] command, ticket in
            lock.withLock { calls.append(Invocation(command: command, ticket: ticket)) }
            if holdsCompletion {
                await withCheckedContinuation { continuation in
                    let resumeNow = lock.withLock { () -> Bool in
                        guard !isReleased else { return true }
                        completion = continuation
                        return false
                    }
                    if resumeNow { continuation.resume() }
                }
            }
            if shouldFail { throw CatalogMenuProbeFailure.refused }
        }
    }

    var invocations: [Invocation] { lock.withLock { calls } }

    // Observe committed state; avoid the runner's nested MainActor XCTWaiter path.
    func waitForEntry() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if !invocations.isEmpty { return true }
            do { try await Task.sleep(for: .milliseconds(1)) } catch { return false }
        }
        return !invocations.isEmpty
    }

    func release() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            isReleased = true
            let pending = completion
            completion = nil
            return pending
        }
        pending?.resume()
    }
}

private enum CatalogMenuProbeFailure: Error, LocalizedError {
    case refused
    var errorDescription: String? { "TESTONLY private failure detail must not become UI text" }
}
