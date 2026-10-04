import CaptureCore
import Darwin
import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

/// Specifies supervision of the long-lived worldwide availability loop.
///
/// The coordinator must distinguish a transport-shaped `CancellationError` from cancellation of
/// its owning task, retry the former with telemetry, and fail its completion stream if a supervised
/// child returns unexpectedly. Explicit shutdown is the sole path where child cancellation and a
/// normal completion event are accepted.
final class WorldwideHostCoordinatorTests: XCTestCase {
    func testMediaHandoffCannotUseFabricatedTargetWithoutExactActiveMediaOwner() async throws {
        let memory = CoordinatorMemoryPairingDataStore()
        let presentations = LockedValues<BelugaHostPresentation>()
        let coordinator = makeCoordinator(store: WorldwidePairingStore(dataStore: memory),
            catalogMutationIsAuthorized: { true }, presentation: { presentations.append($0) })
        let target = BelugaConnectedPhoneMediaTarget(phoneID: UUID(), selectionEpoch: UUID(), exchangeID: "TESTONLY")
        for stage in 0..<3 {
            if stage == 1 { _ = try await coordinator.start(resetPairing: false) }
            if stage == 2 { await coordinator.stop() }
            do { _ = try await coordinator.moveMediaToConnectedPhone(target: target); XCTFail("No active media owner") }
            catch { XCTAssertTrue(error is WorldwidePhoneCatalogRuntimeError) }
            XCTAssertNil(presentations.values.last?.connectedMediaTarget)
        }
    }

    func testUnselectedPresentationCarriesFreshTicketAgainAfterExplicitSelectionChange() async throws {
        let memory = CoordinatorMemoryPairingDataStore()
        let presentations = LockedValues<BelugaHostPresentation>()
        let coordinator = makeCoordinator(store: WorldwidePairingStore(dataStore: memory),
            catalogMutationIsAuthorized: { true }, presentation: { presentations.append($0) })
        _ = try await coordinator.start(resetPairing: false)
        let first = try XCTUnwrap(presentations.values.last)
        XCTAssertEqual(first.phase, .unselected)
        XCTAssertTrue(first.phones.items.isEmpty)
        XCTAssertTrue(first.phones.canAddPhone)
        let ticket = try XCTUnwrap(first.phones.action)
        try await coordinator.selectPhone(nil, action: ticket)
        let second = try XCTUnwrap(presentations.values.last)
        XCTAssertEqual(second.phase, .unselected)
        XCTAssertNotNil(second.phones.action)
        XCTAssertNotEqual(second.phones.action, ticket)
        XCTAssertGreaterThan(second.revision, first.revision)
        await coordinator.stop()
        XCTAssertNil(presentations.values.last?.phones.action)
    }

    func testMissingProcessOwnerCannotCreateOrMigrateIdentity() async throws {
        let memory = CoordinatorMemoryPairingDataStore()
        let coordinator = makeCoordinator(store: WorldwidePairingStore(dataStore: memory),
                                          catalogOwnerIsValid: { false })
        do {
            _ = try await coordinator.start(resetPairing: false)
            XCTFail("Missing runtime owner must fail before persistence")
        } catch WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized { }
        XCTAssertNil(try memory.data(for: WorldwidePairingStore.identityAccount))
        XCTAssertNil(try memory.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount))
        await coordinator.stop()
    }

    func testQuietProtocolBoundarySurvivesExactMediaTeardownButNotNewReady() throws {
        var lifecycle = WorldwideHostLifecycle()
        try lifecycle.start(hasPairedViewer: true)
        var waitingBoundary = true
        func quiet(_ hasMediaOwner: Bool) -> Bool {
            worldwidePhoneCatalogHasQuietBoundary(validatedWaiting: waitingBoundary,
                activeExchangeID: lifecycle.activeExchangeID, mediaExchangeID: lifecycle.mediaExchangeID,
                hasMediaOwner: hasMediaOwner)
        }
        XCTAssertTrue(quiet(false))
        waitingBoundary = false
        try lifecycle.availabilityReady(exchangeID: "first")
        try lifecycle.mediaStarted(exchangeID: "first")
        XCTAssertFalse(quiet(true))
        lifecycle.availabilityPeerLeft(exchangeID: "first")
        waitingBoundary = lifecycle.activeExchangeID == nil
        XCTAssertFalse(quiet(true))
        lifecycle.mediaEnded(exchangeID: "first")
        XCTAssertTrue(quiet(false))
        waitingBoundary = false
        try lifecycle.availabilityReady(exchangeID: "second")
        // A delayed first-session teardown cannot revive its old quiet proof.
        lifecycle.mediaEnded(exchangeID: "first")
        XCTAssertFalse(quiet(false))
    }
    func testFreshAndEmptyCatalogStayIdleUntilExplicitPairing() async throws {
        let memory = CoordinatorMemoryPairingDataStore()
        let store = WorldwidePairingStore(dataStore: memory)
        let factoryCalls = LockedValues<Int>()
        let coordinator = makeCoordinator(store: store, availabilityClientFactory: { _, _ in
            factoryCalls.append(1)
            throw CoordinatorTestError.noClient
        })
        let started = try await coordinator.start(resetPairing: false)
        XCTAssertEqual(started, .unselected)
        let empty = try await coordinator.pairedPhones()
        XCTAssertTrue(empty.records.isEmpty)
        XCTAssertNil(empty.selectedPhoneID)
        XCTAssertTrue(factoryCalls.values.isEmpty)
        await coordinator.stop()
        let restarted = makeCoordinator(store: store)
        let reset = try await restarted.start(resetPairing: true)
        XCTAssertEqual(reset, .unselected)
        let restartedEmpty = try await restarted.pairedPhones()
        XCTAssertEqual(restartedEmpty, empty)
        await restarted.stop()
    }

    func testResetForgetsOnlySelectedPhoneAndNeverFallsBack() async throws {
        let fixture = try makeCatalogFixture()
        var snapshot = try fixture.store.phoneCatalog.loadOrMigrate(for: fixture.host)
        let second = try makeActiveRecord(hostIdentity: fixture.host)
        snapshot = try fixture.store.phoneCatalog.addPairedPhone(
            second, for: fixture.host, expectedToken: snapshot.token
        )
        let original = try fixture.memory.data(for: WorldwidePairingStore.pairedViewerAccount)
        let identityBytes = try fixture.memory.data(for: WorldwidePairingStore.identityAccount)
        let coordinator = makeCoordinator(store: fixture.store, catalogMutationIsAuthorized: { true })
        let started = try await coordinator.start(resetPairing: true)
        XCTAssertEqual(started, .unselected)
        let remaining = try await coordinator.pairedPhones()
        XCTAssertEqual(remaining.records, [second])
        XCTAssertNil(remaining.selectedPhoneID)
        XCTAssertEqual(remaining.legacyImportReceipt, snapshot.legacyImportReceipt)
        XCTAssertEqual(try fixture.memory.data(for: WorldwidePairingStore.pairedViewerAccount), original)
        XCTAssertEqual(try fixture.memory.data(for: WorldwidePairingStore.identityAccount), identityBytes)
        await coordinator.stop()
        let restarted = makeCoordinator(store: fixture.store, catalogMutationIsAuthorized: { true })
        let resetAgain = try await restarted.start(resetPairing: true)
        XCTAssertEqual(resetAgain, .unselected)
        let restartedRemaining = try await restarted.pairedPhones()
        XCTAssertEqual(restartedRemaining, remaining)
        await restarted.stop()
    }

    func testLegacyReadersAndWritersRefuseAfterMigrationIncludingEmptyTombstone() throws {
        let fixture = try makeCatalogFixture()
        var snapshot = try fixture.store.phoneCatalog.loadOrMigrate(for: fixture.host)
        let original = try fixture.memory.data(for: WorldwidePairingStore.pairedViewerAccount)
        snapshot = try fixture.store.phoneCatalog.forgetPhone(
            fixture.record.remoteDeviceID, for: fixture.host, expectedToken: snapshot.token
        )
        XCTAssertTrue(snapshot.records.isEmpty)
        let operations: [() throws -> Void] = [
            { _ = try fixture.store.loadPairedViewer(for: fixture.host) },
            { try fixture.store.savePairedViewer(fixture.record, for: fixture.host) },
            { try fixture.store.resetPairedViewer() },
        ]
        for operation in operations {
            XCTAssertThrowsError(try operation()) {
                XCTAssertEqual($0 as? WorldwidePairingStoreError, .catalogIsAuthoritative)
            }
        }
        XCTAssertEqual(try fixture.memory.data(for: WorldwidePairingStore.pairedViewerAccount), original)
        XCTAssertEqual(try fixture.store.phoneCatalog.loadOrMigrate(for: fixture.host), snapshot)
    }

    func testAttemptCursorAddsOnceUpdatesExactPairAndCannotResurrectAfterForget() throws {
        let fixture = try makeCatalogFixture()
        let snapshot = try fixture.store.phoneCatalog.loadOrMigrate(for: fixture.host)
        let second = try makeActiveRecord(hostIdentity: fixture.host)
        let cursor = WorldwidePairingCatalogCheckpoint(
            store: fixture.store, identity: fixture.host, snapshot: snapshot, ownerIsValid: { true }
        )
        XCTAssertNil(try cursor.readback().record)
        XCTAssertThrowsError(try cursor.update(second))
        try cursor.add(second)
        try cursor.update(second)
        XCTAssertThrowsError(try cursor.add(second))
        XCTAssertThrowsError(try cursor.update(fixture.record))
        let added = try cursor.readback()
        XCTAssertEqual(added.record, second)
        XCTAssertEqual(added.snapshot.selectedRecord, fixture.record)
        _ = try fixture.store.phoneCatalog.forgetPhone(
            second.remoteDeviceID, for: fixture.host, expectedToken: added.snapshot.token
        )
        XCTAssertThrowsError(try cursor.update(second))
        XCTAssertThrowsError(try cursor.readback())
        XCTAssertEqual(try fixture.store.phoneCatalog.loadOrMigrate(for: fixture.host).records, [fixture.record])
    }

    func testRevokedAttemptAndLostOwnerCannotAdvanceCheckpoint() throws {
        let fixture = try makeCatalogFixture()
        let snapshot = try fixture.store.phoneCatalog.loadOrMigrate(for: fixture.host)
        let second = try makeActiveRecord(hostIdentity: fixture.host)
        let lost = LockedFlag()
        let cursor = WorldwidePairingCatalogCheckpoint(
            store: fixture.store, identity: fixture.host, snapshot: snapshot, ownerIsValid: { !lost.value }
        )
        try cursor.add(second)
        let saved = try cursor.readback()
        lost.set()
        XCTAssertThrowsError(try cursor.update(second))
        XCTAssertEqual(try cursor.readback().snapshot, saved.snapshot)
        cursor.revoke()
        XCTAssertThrowsError(try cursor.update(second))
        XCTAssertEqual(try cursor.readback().record, second)
    }

    func testQuietSelectionRetiresOldClientAndPreservesBothTrustBindings() async throws {
        let fixture = try makeCatalogFixture()
        var snapshot = try fixture.store.phoneCatalog.loadOrMigrate(for: fixture.host)
        let second = try makeActiveRecord(hostIdentity: fixture.host)
        snapshot = try fixture.store.phoneCatalog.addPairedPhone(second, for: fixture.host, expectedToken: snapshot.token)
        let old = HostAvailabilityClientStub(behavior: .validatedWaiting)
        let successor = HostAvailabilityClientStub(behavior: .validatedWaiting)
        let factory = HostAvailabilityClientFactoryStub(clients: [old, successor])
        let coordinator = makeCoordinator(store: fixture.store,
            availabilityClientFactory: { _, _ in try factory.next() }, catalogMutationIsAuthorized: { true })
        _ = try await coordinator.start(resetPairing: false)
        let action = try await awaitCatalogAction(coordinator)
        try await coordinator.selectPhone(second.remoteDeviceID, action: action)
        XCTAssertEqual(old.closeCount, 1)
        let selected = try await coordinator.pairedPhones()
        XCTAssertEqual(selected.records, [fixture.record, second])
        XCTAssertEqual(selected.selectedRecord, second)
        XCTAssertEqual(selected.legacyImportReceipt, snapshot.legacyImportReceipt)
        let next = try await awaitCatalogAction(coordinator)
        do {
            try await coordinator.forgetPhone(second.remoteDeviceID, action: action)
            XCTFail("Old selection ticket must not mutate a successor")
        } catch WorldwidePhoneCatalogRuntimeError.staleSelection {}
        let afterStale = try await coordinator.pairedPhones()
        XCTAssertEqual(afterStale, selected)
        try await coordinator.forgetPhone(second.remoteDeviceID, action: next)
        let forgotten = try await coordinator.pairedPhones()
        XCTAssertEqual(forgotten.records, [fixture.record])
        XCTAssertNil(forgotten.selectedPhoneID)
        XCTAssertEqual(successor.closeCount, 1)
        await coordinator.stop()
    }

    func testSelectionWaitsForExactOldCloseAndRechecksOwnerBeforeMutation() async throws {
        let fixture = try makeCatalogFixture()
        let release = AsyncStream<Void>.makeStream()
        let old = HostAvailabilityClientStub(behavior: .validatedWaiting, closeBarrier: release.stream)
        let lost = LockedFlag()
        let coordinator = makeCoordinator(store: fixture.store, availabilityClientFactory: { _, _ in old },
            catalogMutationIsAuthorized: { true }, catalogOwnerIsValid: { !lost.value })
        _ = try await coordinator.start(resetPairing: false)
        let action = try await awaitCatalogAction(coordinator)
        let previous = try await coordinator.pairedPhones()
        let selecting = Task { try await coordinator.selectPhone(nil, action: action) }
        let closeStarted = await eventually { old.closeCount == 1 }
        XCTAssertTrue(closeStarted)
        let whileClosing = try await coordinator.pairedPhones()
        XCTAssertEqual(whileClosing, previous)
        do { _ = try await coordinator.phoneCatalogAction(); XCTFail("Retirement must remain owned") }
        catch WorldwidePhoneCatalogRuntimeError.notQuiet {}
        lost.set()
        release.continuation.yield(())
        release.continuation.finish()
        do { try await selecting.value; XCTFail("Lost owner must not write after transport drain") }
        catch WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized {}
        let afterOwnerLoss = try await coordinator.pairedPhones()
        XCTAssertEqual(afterOwnerLoss, previous)
        await coordinator.stop()
    }

    func testActivePeerAndUnvalidatedSocketCannotAuthorizeCatalogActions() async throws {
        let fixture = try makeCatalogFixture()
        let client = HostAvailabilityClientStub(behavior: .wait)
        let telemetry = RecordingConnectionTelemetry()
        let coordinator = makeCoordinator(store: fixture.store, availabilityClientFactory: { _, _ in client },
            connectionTelemetry: telemetry, catalogMutationIsAuthorized: { true })
        _ = try await coordinator.start(resetPairing: false)
        _ = await eventually { telemetry.snapshot().events.contains { $0.stage == .availabilitySocketOpened } }
        do { _ = try await coordinator.phoneCatalogAction(); XCTFail("HTTP/socket open is not quiet proof") }
        catch WorldwidePhoneCatalogRuntimeError.notQuiet {}
        client.emit(.waiting)
        _ = try await awaitCatalogAction(coordinator)
        let exchange = try RemoteAvailabilityExchangeID(wireValue: "AAECAwQFBgcICQoLDA0ODw")
        client.emit(.ready(role: .host, exchangeID: exchange))
        _ = await eventually { telemetry.snapshot().events.contains { $0.stage == .availabilityReady } }
        do { _ = try await coordinator.phoneCatalogAction(); XCTFail("Must not disconnect an authenticated peer") }
        catch WorldwidePhoneCatalogRuntimeError.notQuiet {}
        XCTAssertEqual(client.closeCount, 0)
        await coordinator.stop()
    }

    func testDefaultAdmissionDeniesMutationAndUnknownPhoneDoesNotCloseCurrentSocket() async throws {
        let fixture = try makeCatalogFixture()
        let deniedClient = HostAvailabilityClientStub(behavior: .validatedWaiting)
        let telemetry = RecordingConnectionTelemetry()
        let denied = makeCoordinator(store: fixture.store, availabilityClientFactory: { _, _ in deniedClient },
            connectionTelemetry: telemetry)
        _ = try await denied.start(resetPairing: false)
        _ = await eventually { telemetry.snapshot().events.contains { $0.stage == .hostWorkerWaitingForViewer } }
        do { _ = try await denied.phoneCatalogAction(); XCTFail("No implicit owner/mutation admission") }
        catch WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized {}
        XCTAssertEqual(deniedClient.closeCount, 0)
        await denied.stop()

        let allowedClient = HostAvailabilityClientStub(behavior: .validatedWaiting)
        let allowed = makeCoordinator(store: fixture.store, availabilityClientFactory: { _, _ in allowedClient },
            catalogMutationIsAuthorized: { true })
        _ = try await allowed.start(resetPairing: false)
        let action = try await awaitCatalogAction(allowed)
        do { try await allowed.selectPhone(UUID(), action: action); XCTFail("Unknown phone must be rejected") }
        catch WorldwidePairedPhoneCatalogError.unknownPhone {}
        XCTAssertEqual(allowedClient.closeCount, 0)
        let stillCurrent = try await allowed.phoneCatalogAction()
        XCTAssertEqual(stillCurrent, action)
        await allowed.stop()
    }

    func testStopDuringRecoverySendCannotPersistLateCompletionSent() async throws {
        let fixture = try makeCatalogFixture()
        let pendingCompletion = try makeActiveRecord(hostIdentity: fixture.host, completionOnly: true)
        try fixture.store.savePairedViewer(pendingCompletion, for: fixture.host)
        let release = AsyncStream<Void>.makeStream()
        let client = HostAvailabilityClientStub(behavior: .validatedWaiting, sendBarrier: release.stream)
        let coordinator = makeCoordinator(store: fixture.store, availabilityClientFactory: { _, _ in client },
            catalogMutationIsAuthorized: { true })
        _ = try await coordinator.start(resetPairing: false)
        _ = try await awaitCatalogAction(coordinator)
        let previous = try await coordinator.pairedPhones()
        let exchange = try RemoteAvailabilityExchangeID(wireValue: "AAECAwQFBgcICQoLDA0ODw")
        client.emit(.ready(role: .host, exchangeID: exchange))
        let sending = await eventually { client.sendCount == 1 }
        XCTAssertTrue(sending)
        await coordinator.stop()
        release.continuation.yield(())
        release.continuation.finish()
        _ = await eventually { client.sendReturns == 1 }
        XCTAssertEqual(try fixture.store.phoneCatalog.loadOrMigrate(for: fixture.host), previous)
    }

    func testPairAnotherDoesNotOverwriteOrSelectAndFailedAttemptDoesNotRecoverOldPair() async throws {
        for failAfterProposal in [false, true] {
            let fixture = try makeCatalogFixture()
            let original = try fixture.memory.data(for: WorldwidePairingStore.pairedViewerAccount)
            let clients = HostAvailabilityClientFactoryStub(clients: [
                HostAvailabilityClientStub(behavior: .validatedWaiting),
                HostAvailabilityClientStub(behavior: .validatedWaiting),
            ])
            let coordinator = makeCoordinator(store: fixture.store,
                availabilityClientFactory: { _, _ in try clients.next() },
                catalogMutationIsAuthorized: { true }, pairingClientFactory: { _, invitation in
                    try CatalogPairingTransport(invitation: invitation, failAfterProposal: failAfterProposal)
                })
            _ = try await coordinator.start(resetPairing: false)
            let action = try await awaitCatalogAction(coordinator)
            let result = try await coordinator.pairAnotherPhone(action: action)
            guard case .invitation = result else { return XCTFail("Explicit pairing should return its invitation") }
            _ = try await awaitCatalogAction(coordinator)
            let paired = try await coordinator.pairedPhones()
            XCTAssertEqual(paired.records.count, 2)
            XCTAssertEqual(paired.selectedRecord, fixture.record)
            let second = try XCTUnwrap(paired.records.first { $0.remoteDeviceID != fixture.record.remoteDeviceID })
            XCTAssertEqual(second.pairingState, failAfterProposal ? .pending : .active)
            XCTAssertNotEqual(second.pairID, fixture.record.pairID)
            XCTAssertEqual(try fixture.memory.data(for: WorldwidePairingStore.pairedViewerAccount), original)
            await coordinator.stop()
        }
    }

    func testExplicitFirstPairSelectsExactActivePhoneOnlyAfterBootstrapTeardown() async throws {
        let memory = CoordinatorMemoryPairingDataStore()
        let store = WorldwidePairingStore(dataStore: memory)
        let host = try store.loadOrCreateHostIdentity(displayName: "Test Mac")
        let identityBytes = try memory.data(for: WorldwidePairingStore.identityAccount)
        let gate = CatalogPairingCloseGate()
        let locators = LockedValues<RemoteAvailabilityLocator>()
        let coordinator = makeCoordinator(store: store, availabilityClientFactory: { _, locator in
            locators.append(locator)
            return HostAvailabilityClientStub(behavior: .validatedWaiting)
        }, catalogMutationIsAuthorized: { true }, pairingClientFactory: { _, invitation in
            try CatalogPairingTransport(invitation: invitation, holdSecondClose: gate)
        })
        _ = try await coordinator.start(resetPairing: false)
        let action = try await awaitCatalogAction(coordinator)
        _ = try await coordinator.pairAnotherPhone(action: action)
        try await awaitPairingClose(gate)
        let beforeClose = try store.phoneCatalog.loadOrMigrate(for: host)
        let active = try XCTUnwrap(beforeClose.records.only)
        XCTAssertEqual(active.pairingState, .active)
        XCTAssertNil(beforeClose.selectedPhoneID)
        XCTAssertTrue(locators.values.isEmpty, "No availability before confirmed bootstrap retirement")
        do { _ = try await coordinator.phoneCatalogAction(); XCTFail("Bootstrap still owns the attempt") }
        catch WorldwidePhoneCatalogRuntimeError.notQuiet {}
        await gate.release()
        _ = try await awaitCatalogAction(coordinator)
        let afterClose = try await coordinator.pairedPhones()
        XCTAssertEqual(afterClose.records, [active])
        XCTAssertEqual(afterClose.selectedRecord, active)
        XCTAssertEqual(afterClose.token.revision, beforeClose.token.revision + 1)
        XCTAssertEqual(locators.values, [try active.availabilityLocator()])
        XCTAssertEqual(try memory.data(for: WorldwidePairingStore.identityAccount), identityBytes)
        XCTAssertNil(try memory.data(for: WorldwidePairingStore.pairedViewerAccount))
        await coordinator.stop()
    }

    func testPriorCatalogExplicitDeselectAndResetNeverAcquireFirstPairIntent() async throws {
        for scenario in 0..<4 {
            let store = WorldwidePairingStore(dataStore: CoordinatorMemoryPairingDataStore())
            let host = try store.loadOrCreateHostIdentity(displayName: "Test Mac")
            var initial = try store.phoneCatalog.loadOrMigrate(for: host)
            if scenario == 1 || scenario == 2 {
                let previous = try makeActiveRecord(hostIdentity: host)
                initial = try store.phoneCatalog.addPairedPhone(previous, for: host, expectedToken: initial.token)
                if scenario == 1 {
                    initial = try store.phoneCatalog.forgetPhone(previous.remoteDeviceID, for: host,
                                                               expectedToken: initial.token)
                }
            }
            let calls = LockedValues<Int>()
            let coordinator = makeCoordinator(store: store, availabilityClientFactory: { _, _ in
                calls.append(1)
                return HostAvailabilityClientStub(behavior: .validatedWaiting)
            }, catalogMutationIsAuthorized: { true }, pairingClientFactory: { _, invitation in
                try CatalogPairingTransport(invitation: invitation)
            })
            _ = try await coordinator.start(resetPairing: scenario == 3)
            if scenario == 0 {
                let deselect = try await awaitCatalogAction(coordinator)
                try await coordinator.selectPhone(nil, action: deselect)
            }
            let action = try await awaitCatalogAction(coordinator)
            _ = try await coordinator.pairAnotherPhone(action: action)
            _ = try await awaitCatalogAction(coordinator)
            let afterPairing = try await coordinator.pairedPhones()
            XCTAssertEqual(afterPairing.records.count, initial.records.count + 1)
            XCTAssertTrue(afterPairing.records.allSatisfy { $0.pairingState == .active })
            XCTAssertNil(afterPairing.selectedPhoneID, "No first-pair intent for scenario \(scenario)")
            XCTAssertTrue(calls.values.isEmpty)
            await coordinator.stop()
        }
    }

    func testInterruptedFirstPairRemainsUnselectedAcrossRestartAndAnotherPairing() async throws {
        let store = WorldwidePairingStore(dataStore: CoordinatorMemoryPairingDataStore())
        let first = makeCoordinator(store: store, catalogMutationIsAuthorized: { true },
            pairingClientFactory: { _, invitation in
                try CatalogPairingTransport(invitation: invitation, failAfterProposal: true)
            })
        _ = try await first.start(resetPairing: false)
        let firstAction = try await awaitCatalogAction(first)
        _ = try await first.pairAnotherPhone(action: firstAction)
        _ = try await awaitCatalogAction(first)
        let interrupted = try await first.pairedPhones()
        XCTAssertEqual(interrupted.records.only?.pairingState, .pending)
        XCTAssertNil(interrupted.selectedPhoneID)
        await first.stop()
        let calls = LockedValues<Int>()
        let restarted = makeCoordinator(store: store, availabilityClientFactory: { _, _ in
            calls.append(1)
            return HostAvailabilityClientStub(behavior: .validatedWaiting)
        }, catalogMutationIsAuthorized: { true }, pairingClientFactory: { _, invitation in
            try CatalogPairingTransport(invitation: invitation)
        })
        let started = try await restarted.start(resetPairing: false)
        XCTAssertEqual(started, .unselected)
        let afterRestart = try await restarted.pairedPhones()
        XCTAssertEqual(afterRestart, interrupted)
        let next = try await awaitCatalogAction(restarted)
        _ = try await restarted.pairAnotherPhone(action: next)
        _ = try await awaitCatalogAction(restarted)
        let afterRetry = try await restarted.pairedPhones()
        XCTAssertEqual(afterRetry.records.count, 2)
        XCTAssertEqual(afterRetry.records.first, interrupted.records.first)
        XCTAssertEqual(afterRetry.records.last?.pairingState, .active)
        XCTAssertNil(afterRetry.selectedPhoneID)
        XCTAssertTrue(calls.values.isEmpty)
        await restarted.stop()
    }

    func testFailedFirstPairBeforeCheckpointDoesNotTransferIntentToRetry() async throws {
        let store = WorldwidePairingStore(dataStore: CoordinatorMemoryPairingDataStore())
        let attempts = LockedValues<Int>()
        let coordinator = makeCoordinator(store: store, catalogMutationIsAuthorized: { true },
            pairingClientFactory: { _, invitation in
                attempts.append(1)
                if attempts.values.count == 1 { throw CoordinatorTestError.noClient }
                return try CatalogPairingTransport(invitation: invitation)
            })
        _ = try await coordinator.start(resetPairing: false)
        let first = try await awaitCatalogAction(coordinator)
        do { _ = try await coordinator.pairAnotherPhone(action: first); XCTFail("Injected failure expected") }
        catch CoordinatorTestError.noClient {}
        let unchanged = try await coordinator.pairedPhones()
        XCTAssertTrue(unchanged.records.isEmpty)
        XCTAssertEqual(unchanged.token.revision, 1)
        let retry = try await awaitCatalogAction(coordinator)
        _ = try await coordinator.pairAnotherPhone(action: retry)
        _ = try await awaitCatalogAction(coordinator)
        let paired = try await coordinator.pairedPhones()
        XCTAssertEqual(paired.records.only?.pairingState, .active)
        XCTAssertNil(paired.selectedPhoneID)
        await coordinator.stop()
    }

    func testFirstPairRechecksOwnerAndMutationAdmissionAfterHeldTeardown() async throws {
        for loseOwner in [false, true] {
            let store = WorldwidePairingStore(dataStore: CoordinatorMemoryPairingDataStore())
            let host = try store.loadOrCreateHostIdentity(displayName: "Test Mac")
            let gate = CatalogPairingCloseGate()
            let lost = LockedFlag()
            let denied = LockedFlag()
            let calls = LockedValues<Int>()
            let coordinator = makeCoordinator(store: store, availabilityClientFactory: { _, _ in
                calls.append(1)
                return HostAvailabilityClientStub(behavior: .validatedWaiting)
            }, catalogMutationIsAuthorized: {
                if !loseOwner && lost.value { denied.set(); return false }
                return true
            }, catalogOwnerIsValid: {
                if loseOwner && lost.value { denied.set(); return false }
                return true
            }, pairingClientFactory: { _, invitation in
                try CatalogPairingTransport(invitation: invitation, holdSecondClose: gate)
            })
            _ = try await coordinator.start(resetPairing: false)
            let action = try await awaitCatalogAction(coordinator)
            _ = try await coordinator.pairAnotherPhone(action: action)
            try await awaitPairingClose(gate)
            let before = try store.phoneCatalog.loadOrMigrate(for: host)
            XCTAssertEqual(before.records.only?.pairingState, .active)
            lost.set()
            await gate.release()
            let rechecked = await eventually { denied.value }
            XCTAssertTrue(rechecked, "Admission must be read again after teardown")
            await coordinator.stop()
            XCTAssertEqual(try store.phoneCatalog.loadOrMigrate(for: host), before)
            XCTAssertTrue(calls.values.isEmpty)
        }
    }

    func testCancelledFirstPairStartCannotActivateOrTransferIntentToRetry() async throws {
        let store = WorldwidePairingStore(dataStore: CoordinatorMemoryPairingDataStore())
        let connectGate = CatalogPairingCloseGate()
        let attempts = LockedValues<Int>()
        let coordinator = makeCoordinator(store: store, catalogMutationIsAuthorized: { true },
            pairingClientFactory: { _, invitation in
                attempts.append(1)
                return try CatalogPairingTransport(invitation: invitation,
                    holdConnect: attempts.values.count == 1 ? connectGate : nil)
            })
        _ = try await coordinator.start(resetPairing: false)
        let action = try await awaitCatalogAction(coordinator)
        let starting = Task { try await coordinator.pairAnotherPhone(action: action) }
        try await awaitPairingClose(connectGate)
        starting.cancel()
        await connectGate.release()
        do { _ = try await starting.value; XCTFail("Cancelled start must not return an invitation") }
        catch is CancellationError {}
        let afterCancellation = try await coordinator.pairedPhones()
        XCTAssertTrue(afterCancellation.records.isEmpty)
        XCTAssertNil(afterCancellation.selectedPhoneID)
        let retry = try await awaitCatalogAction(coordinator)
        _ = try await coordinator.pairAnotherPhone(action: retry)
        _ = try await awaitCatalogAction(coordinator)
        let afterRetry = try await coordinator.pairedPhones()
        XCTAssertEqual(afterRetry.records.only?.pairingState, .active)
        XCTAssertNil(afterRetry.selectedPhoneID)
        await coordinator.stop()
    }

    func testCancelledPairAnotherResumesOnlyUnchangedPredecessorAfterConfirmedDrain() async throws {
        for scenario in 0..<3 {
            let fixture = try makeCatalogFixture()
            let gate = CatalogPairingCloseGate()
            let old = HostAvailabilityClientStub(behavior: .validatedWaiting, confirmedCloseGate: gate)
            let successor = HostAvailabilityClientStub(behavior: .validatedWaiting)
            let clients = HostAvailabilityClientFactoryStub(clients: [old, successor])
            let lostOwner = LockedFlag()
            let returned = LockedFlag()
            let pairingCalls = LockedValues<Int>()
            let coordinator = makeCoordinator(store: fixture.store,
                availabilityClientFactory: { _, _ in try clients.next() },
                catalogMutationIsAuthorized: { true }, catalogOwnerIsValid: { !lostOwner.value },
                pairingClientFactory: { _, invitation in
                    pairingCalls.append(1)
                    return try CatalogPairingTransport(invitation: invitation)
                })
            _ = try await coordinator.start(resetPairing: false)
            let action = try await awaitCatalogAction(coordinator)
            let previous = try await coordinator.pairedPhones()
            let pairing = Task {
                defer { returned.set() }
                return try await coordinator.pairAnotherPhone(action: action)
            }
            try await awaitPairingClose(gate)
            pairing.cancel()
            XCTAssertFalse(returned.value, "Cancellation alone cannot stand in for transport drain")
            XCTAssertEqual(clients.attemptCount, 1)
            XCTAssertTrue(pairingCalls.values.isEmpty)
            var expected = previous
            if scenario == 1 {
                let foreign = try makeActiveRecord(hostIdentity: fixture.host)
                expected = try fixture.store.phoneCatalog.addPairedPhone(
                    foreign, for: fixture.host, expectedToken: previous.token
                )
            } else if scenario == 2 {
                lostOwner.set()
            }
            await gate.release()
            do {
                _ = try await pairing.value
                XCTFail("Cancelled or invalidated admission must not create an invitation")
            } catch is CancellationError {
                XCTAssertEqual(scenario, 0)
            } catch WorldwidePhoneCatalogRuntimeError.staleSelection {
                XCTAssertEqual(scenario, 1)
            } catch WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized {
                XCTAssertEqual(scenario, 2)
            }
            if scenario == 0 {
                let recovered = try await awaitCatalogAction(coordinator)
                XCTAssertNotEqual(recovered.selectionEpoch, action.selectionEpoch)
                XCTAssertEqual(clients.attemptCount, 2, "Unchanged selected phone regains availability")
                let current = try await coordinator.pairedPhones()
                XCTAssertEqual(current, previous)
            } else {
                XCTAssertEqual(clients.attemptCount, 1, "Foreign catalog/owner must never resume")
            }
            XCTAssertEqual(try fixture.store.phoneCatalog.loadOrMigrate(for: fixture.host), expected)
            XCTAssertTrue(pairingCalls.values.isEmpty)
            XCTAssertEqual(old.closeCount, 1)
            await coordinator.stop()
        }
    }

    func testFirstPairRejectsForeignRevisionSelectionAndCatalogGenerationDuringTeardown() async throws {
        for scenario in 0..<3 {
            let memory = CoordinatorMemoryPairingDataStore()
            let store = WorldwidePairingStore(dataStore: memory)
            let host = try store.loadOrCreateHostIdentity(displayName: "Test Mac")
            let gate = CatalogPairingCloseGate()
            let calls = LockedValues<Int>()
            let presentations = LockedValues<BelugaHostPresentation>()
            let coordinator = makeCoordinator(store: store, availabilityClientFactory: { _, _ in
                calls.append(1)
                return HostAvailabilityClientStub(behavior: .validatedWaiting)
            }, catalogMutationIsAuthorized: { true }, pairingClientFactory: { _, invitation in
                try CatalogPairingTransport(invitation: invitation, holdSecondClose: gate)
            }, presentation: { presentations.append($0) })
            _ = try await coordinator.start(resetPairing: false)
            let action = try await awaitCatalogAction(coordinator)
            _ = try await coordinator.pairAnotherPhone(action: action)
            try await awaitPairingClose(gate)
            var foreign = try store.phoneCatalog.loadOrMigrate(for: host)
            let first = try XCTUnwrap(foreign.records.only)
            if scenario == 0 {
                // Same visible shape after an explicit select/deselect is still a foreign revision.
                foreign = try store.phoneCatalog.selectPhone(first.remoteDeviceID, for: host,
                                                            expectedToken: foreign.token)
                foreign = try store.phoneCatalog.selectPhone(nil, for: host, expectedToken: foreign.token)
            } else {
                if scenario == 2 {
                    try memory.removeData(for: WorldwidePairedPhoneCatalogStore.catalogAccount)
                    foreign = try store.phoneCatalog.loadOrMigrate(for: host)
                }
                let other = try makeActiveRecord(hostIdentity: host)
                foreign = try store.phoneCatalog.addPairedPhone(other, for: host, expectedToken: foreign.token)
                foreign = try store.phoneCatalog.selectPhone(other.remoteDeviceID, for: host,
                                                            expectedToken: foreign.token)
            }
            await gate.release()
            let stopped = await eventually { presentations.values.last?.phase == .stopped }
            XCTAssertTrue(stopped, "A foreign checkpoint must fail closed")
            await coordinator.stop()
            XCTAssertEqual(try store.phoneCatalog.loadOrMigrate(for: host), foreign)
            XCTAssertTrue(calls.values.isEmpty)
        }
    }

    func testStoppedFirstPairCannotSelectAfterLateTeardownOrOnRestart() async throws {
        let store = WorldwidePairingStore(dataStore: CoordinatorMemoryPairingDataStore())
        let host = try store.loadOrCreateHostIdentity(displayName: "Test Mac")
        let gate = CatalogPairingCloseGate()
        let oldTaskLogger = RecordingLogger()
        let taskEndMarker = "Worldwide pairing completion task finished"
        let calls = LockedValues<Int>()
        let coordinator = makeCoordinator(store: store, availabilityClientFactory: { _, _ in
            calls.append(1)
            return HostAvailabilityClientStub(behavior: .validatedWaiting)
        }, catalogMutationIsAuthorized: { true }, pairingClientFactory: { _, invitation in
            try CatalogPairingTransport(invitation: invitation, holdSecondClose: gate)
        }, logger: oldTaskLogger)
        _ = try await coordinator.start(resetPairing: false)
        let action = try await awaitCatalogAction(coordinator)
        _ = try await coordinator.pairAnotherPhone(action: action)
        try await awaitPairingClose(gate)
        let activeButUnselected = try store.phoneCatalog.loadOrMigrate(for: host)
        XCTAssertEqual(activeButUnselected.records.only?.pairingState, .active)
        // Shutdown cancels (but does not join) pairingTask. Its separate bootstrap.stop()
        // performs close #3 and joins the already-finished signaling consumer, not the
        // held close #2 in pairingDidCommit. Bound this assertion so a join regression
        // fails instead of hanging this test indefinitely.
        let shutdownReturned = LockedFlag()
        let stopping = Task { await coordinator.stop(); shutdownReturned.set() }
        let stoppedBeforeLateClose = await eventually { shutdownReturned.value }
        if !stoppedBeforeLateClose { await gate.release() }
        await stopping.value
        XCTAssertTrue(stoppedBeforeLateClose)
        let restarted = makeCoordinator(store: store, catalogMutationIsAuthorized: { true })
        let started = try await restarted.start(resetPairing: false)
        XCTAssertEqual(started, .unselected)
        XCTAssertFalse(oldTaskLogger.informationMessages.contains(taskEndMarker))
        await gate.release()
        // Only the old coordinator has this recorder and it owned exactly one attempt.
        // Its defer receipt follows the entire late pairingDidCommit return, unlike a
        // transport close counter that can advance before the stale callback resumes.
        let oldTaskFinished = await eventually {
            oldTaskLogger.informationMessages.contains(taskEndMarker)
        }
        XCTAssertTrue(oldTaskFinished)
        XCTAssertEqual(oldTaskLogger.informationMessages.filter { $0 == taskEndMarker }.count, 1)
        let afterLateClose = try await restarted.pairedPhones()
        XCTAssertEqual(afterLateClose, activeButUnselected)
        XCTAssertTrue(calls.values.isEmpty)
        await restarted.stop()
    }

    private func awaitPairingClose(_ gate: CatalogPairingCloseGate) async throws {
        for _ in 0..<1_000 {
            if await gate.entered { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        // Do not strand a later close if the expectation times out.
        await gate.release()
        throw CoordinatorTestError.noClient
    }

    private func awaitCatalogAction(_ coordinator: WorldwideHostCoordinator) async throws -> WorldwidePhoneCatalogAction {
        for _ in 0..<1_000 {
            if let action = try? await coordinator.phoneCatalogAction() { return action }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw CoordinatorTestError.noClient
    }

    func testAvailabilityOnlineMarkerBindsProcessAndGenerationNonce() async throws {
        let store = try makeActivePairingStore()
        let client = HostAvailabilityClientStub(behavior: .validatedWaiting)
        let logger = RecordingLogger()
        let expectedPID: Int32 = 42_424
        let expectedNonce = String(repeating: "a", count: 64)
        let expectedMarker =
            "Worldwide paired-device availability is online " +
            "pid=\(expectedPID) nonce=\(expectedNonce)"
        let coordinator = makeCoordinator(
            store: store,
            availabilityClientFactory: { _, _ in client },
            availabilityMarkerProcessIdentifier: expectedPID,
            availabilityMarkerGenerationNonce: expectedNonce,
            logger: logger
        )

        let startResult = try await coordinator.start(resetPairing: false)
        guard case .paired = startResult else {
            return XCTFail("Expected the persisted pair to start availability")
        }

        let markerWasLogged = await eventually {
            logger.informationMessages.contains(expectedMarker)
        }
        XCTAssertTrue(markerWasLogged)
        XCTAssertEqual(
            logger.informationMessages.filter { $0.hasPrefix(
                "Worldwide paired-device availability is online"
            ) },
            [expectedMarker]
        )
        await coordinator.stop()
    }

    func testTransportCancellationFromAvailabilityConnectRetriesWithoutCancellingHostLoop() async throws {
        let store = try makeActivePairingStore()
        let cancelledClient = HostAvailabilityClientStub(behavior: .transportCancellation)
        let waitingClient = HostAvailabilityClientStub(behavior: .wait)
        let factory = HostAvailabilityClientFactoryStub(
            clients: [cancelledClient, waitingClient]
        )
        let retryDelays = LockedValues<Int>()
        let telemetry = RecordingConnectionTelemetry()
        let coordinator = makeCoordinator(
            store: store,
            availabilityClientFactory: { _, _ in try factory.next() },
            availabilityRetrySleep: { retryDelays.append($0) },
            connectionTelemetry: telemetry
        )

        let startResult = try await coordinator.start(resetPairing: false)
        guard case .paired = startResult else {
            return XCTFail("Expected the persisted pair to start availability")
        }

        let retried = await eventually {
            factory.attemptCount == 2
                && telemetry.snapshot().events.last?.stage == .availabilitySocketOpened
        }
        if !retried {
            await coordinator.stop()
            return XCTFail("A transport-shaped CancellationError killed the host loop")
        }

        XCTAssertEqual(cancelledClient.connectObservedOwnerCancellation, false)
        XCTAssertEqual(cancelledClient.closeCount, 1)
        XCTAssertEqual(retryDelays.values, [1])
        XCTAssertEqual(
            telemetry.snapshot().events.map(\.stage),
            [
                .availabilityLoopStarted,
                .availabilitySocketOpening,
                .retryScheduled,
                .availabilitySocketOpening,
                .availabilitySocketOpened,
            ]
        )
        XCTAssertEqual(
            telemetry.snapshot().events.first(where: { $0.stage == .retryScheduled })?.failure,
            .transportCancellation
        )
        await coordinator.stop()
    }

    func testUnexpectedAvailabilityLoopReturnFailsCoordinatorCompletion() async throws {
        let store = try makeActivePairingStore()
        let telemetry = RecordingConnectionTelemetry()
        let coordinator = makeCoordinator(
            store: store,
            availabilityLoopOverride: {},
            connectionTelemetry: telemetry
        )
        let completion = CompletionOutcomeProbe()
        let observer = Task {
            do {
                for try await _ in coordinator.completion {}
                completion.set(.normal)
            } catch WorldwideHostCoordinatorError.availabilityLoopEndedUnexpectedly {
                completion.set(.unexpectedLoopEnd)
            } catch {
                completion.set(.otherError)
            }
        }

        _ = try await coordinator.start(resetPairing: false)
        let failedClosed = await eventually {
            completion.value != nil
        }
        if !failedClosed {
            await coordinator.stop()
            observer.cancel()
            return XCTFail("An unsupervised availability child returned without failing the host")
        }

        XCTAssertEqual(completion.value, .unexpectedLoopEnd)
        XCTAssertEqual(
            telemetry.snapshot().events.map(\.stage),
            [.availabilityLoopStarted, .availabilityLoopUnexpectedlyEnded]
        )
        XCTAssertEqual(telemetry.snapshot().events.last?.terminal, .failed)
        _ = await observer.result
    }

    func testExplicitStopDoesNotReportUnexpectedAvailabilityLoopEnd() async throws {
        let store = try makeActivePairingStore()
        let overrideStarted = LockedFlag()
        let telemetry = RecordingConnectionTelemetry()
        let coordinator = makeCoordinator(
            store: store,
            availabilityLoopOverride: {
                overrideStarted.set()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    // The coordinator owns this child and cancellation is a normal stop.
                }
            },
            connectionTelemetry: telemetry
        )
        let completion = CompletionOutcomeProbe()
        let observer = Task {
            do {
                var yielded = 0
                for try await _ in coordinator.completion { yielded += 1 }
                completion.set(yielded == 1 ? .normal : .otherError)
            } catch {
                completion.set(.otherError)
            }
        }

        _ = try await coordinator.start(resetPairing: false)
        let didStartOverride = await eventually { overrideStarted.value }
        XCTAssertTrue(didStartOverride)
        await coordinator.stop()
        let didFinishNormally = await eventually { completion.value != nil }
        XCTAssertTrue(didFinishNormally)
        XCTAssertEqual(completion.value, .normal)
        XCTAssertEqual(
            telemetry.snapshot().events.map(\.stage),
            [.availabilityLoopStarted, .hostStopped]
        )
        XCTAssertFalse(
            telemetry.snapshot().events.contains {
                $0.stage == .availabilityLoopUnexpectedlyEnded
            }
        )
        _ = await observer.result
    }

    func testConcurrentStopJoinsOwningCoordinatorShutdown() async throws {
        let telemetry = SuspendedFlushConnectionTelemetry()
        let teardownDidBegin = LockedFlag()
        let coordinator = makeCoordinator(
            store: try makeActivePairingStore(),
            connectionTelemetry: telemetry,
            teardownDidBegin: { teardownDidBegin.set() }
        )
        let firstFinished = LockedFlag()
        let secondFinished = LockedFlag()

        let firstStop = Task {
            await coordinator.stop()
            firstFinished.set()
        }
        for await _ in telemetry.flushStarted { break }
        XCTAssertTrue(teardownDidBegin.value)

        let secondStop = Task {
            await coordinator.stop()
            secondFinished.set()
        }
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertFalse(firstFinished.value)
        XCTAssertFalse(secondFinished.value)

        telemetry.releaseFlush()
        await firstStop.value
        await secondStop.value
        XCTAssertTrue(firstFinished.value)
        XCTAssertTrue(secondFinished.value)
    }

    func testCoexistencePropagatesWorldwideSupervisorFailureBeforeLANEnds() async throws {
        let coordinator = makeCoordinator(
            store: try makeActivePairingStore(),
            availabilityLoopOverride: {}
        )
        _ = try await coordinator.start(resetPairing: false)

        do {
            _ = try await CaptureServerMain.runCoexistingLANAndWorldwide(
                coordinator: coordinator
            ) {
                try await Task.sleep(for: .milliseconds(250))
                throw CoordinatorTestError.noClient
            }
            XCTFail("Coexistence must not outlive the failed worldwide supervisor")
        } catch WorldwideHostCoordinatorError.availabilityLoopEndedUnexpectedly {
            // This typed error reaches main, which exits nonzero for launchd replacement.
        } catch {
            XCTFail("Expected worldwide supervisor failure, got \(error)")
        }
    }

    func testWorldwideFailureCannotHideCanceledLANNativeStopUncertainty() async throws {
        let coordinator = makeCoordinator(
            store: try makeActivePairingStore(),
            availabilityLoopOverride: {}
        )
        _ = try await coordinator.start(resetPairing: false)

        do {
            _ = try await CaptureServerMain.runCoexistingLANAndWorldwide(
                coordinator: coordinator
            ) {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    throw TestCoexistenceNativeScreenStopUnconfirmedError()
                }
                throw CoordinatorTestError.noClient
            }
            XCTFail("The retained LAN native-stop error must outrank worldwide failure")
        } catch {
            XCTAssertTrue(
                StreamingCaptureManager.hasUnconfirmedNativeScreenCaptureStop(error)
            )
        }
    }

    func testCoexistenceSignalWaitsForLANCancellationCleanup() async throws {
        let coordinator = makeCoordinator(
            store: try makeActivePairingStore(),
            availabilityLoopOverride: {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        )
        _ = try await coordinator.start(resetPairing: false)
        let signals = AsyncStream<Int32>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let lanStarted = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let lanCleanupFinished = LockedFlag()
        let run = Task {
            try await CaptureServerMain.runCoexistingLANAndWorldwide(
                coordinator: coordinator,
                terminationSignals: signals.stream
            ) {
                lanStarted.continuation.yield(())
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    lanCleanupFinished.set()
                    throw error
                }
                throw CoordinatorTestError.noClient
            }
        }

        for await _ in lanStarted.stream { break }
        signals.continuation.yield(SIGTERM)
        signals.continuation.finish()
        do {
            _ = try await run.value
            XCTFail("The signal must reach Main only after LAN cancellation is drained")
        } catch let request as ProcessTerminationRequest {
            XCTAssertEqual(request.signalNumber, SIGTERM)
            XCTAssertTrue(lanCleanupFinished.value)
        } catch {
            XCTFail("Expected an orderly termination request, got \(error)")
        }
        _ = await coordinator.stop()
    }

    private func makeCoordinator(
        store: WorldwidePairingStore,
        availabilityClientFactory: @escaping @Sendable (
            URL,
            RemoteAvailabilityLocator
        ) throws -> any WorldwideHostAvailabilityTransport = { _, _ in
            HostAvailabilityClientStub(behavior: .wait)
        },
        availabilityRetrySleep: @escaping @Sendable (Int) async throws -> Void = { _ in },
        availabilityLoopOverride: (@Sendable () async -> Void)? = nil,
        connectionTelemetry: any ConnectionTelemetryRecording =
            NoopConnectionTelemetryRecorder(),
        teardownDidBegin: @escaping @Sendable () -> Void = {},
        availabilityMarkerProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        availabilityMarkerGenerationNonce: String = String(repeating: "0", count: 64),
        catalogMutationIsAuthorized: @escaping @Sendable () -> Bool = { false },
        catalogOwnerIsValid: @escaping @Sendable () -> Bool = { true },
        pairingClientFactory: @escaping @Sendable (URL, RemoteInvitationCode) throws
            -> any WorldwideHostPairingTransport = { _, _ in throw CoordinatorTestError.noClient },
        presentation: @escaping @Sendable (BelugaHostPresentation) -> Void = { _ in },
        logger: any Logger = SilentLogger()
    ) -> WorldwideHostCoordinator {
        WorldwideHostCoordinator(
            // Reserved `.invalid` prevents accidental external I/O if a test reaches the default
            // transport path instead of one of the injected stubs.
            endpoint: URL(string: "wss://example.invalid")!,
            forceRelay: false,
            screenDisplayID: nil,
            systemAudioDisplayID: nil,
            maximumWidth: 1_280,
            framesPerSecond: 30,
            maximumVideoBitrate: 4_000_000,
            remoteInputController: MacRemoteInputController(allowRemoteControl: false),
            store: store,
            hostDisplayName: "Test Mac",
            availabilityMarkerProcessIdentifier: availabilityMarkerProcessIdentifier,
            availabilityMarkerGenerationNonce: availabilityMarkerGenerationNonce,
            availabilityClientFactory: availabilityClientFactory,
            availabilityRetrySleep: availabilityRetrySleep,
            availabilityLoopOverride: availabilityLoopOverride,
            connectionTelemetry: connectionTelemetry,
            teardownDidBegin: teardownDidBegin,
            presentation: presentation,
            catalogMutationIsAuthorized: catalogMutationIsAuthorized,
            catalogOwnerIsValid: catalogOwnerIsValid,
            pairingClientFactory: pairingClientFactory,
            logger: logger
        )
    }

    private func makeActivePairingStore() throws -> WorldwidePairingStore {
        try makeCatalogFixture().store
    }

    private func makeCatalogFixture() throws -> (store: WorldwidePairingStore,
        memory: CoordinatorMemoryPairingDataStore, host: RemoteDeviceIdentity, record: RemotePairedDeviceRecord) {
        // Build a genuinely active cryptographic record through the complete pairing transcript;
        // hand-authored serialized state could bypass invariants used by coordinator startup.
        let dataStore = CoordinatorMemoryPairingDataStore()
        let store = WorldwidePairingStore(dataStore: dataStore)
        let hostIdentity = try store.loadOrCreateHostIdentity(displayName: "Test Mac")
        let hostRecord = try makeActiveRecord(hostIdentity: hostIdentity)
        try store.savePairedViewer(hostRecord, for: hostIdentity)
        return (store, dataStore, hostIdentity, hostRecord)
    }

    private func makeActiveRecord(hostIdentity: RemoteDeviceIdentity,
                                  completionOnly: Bool = false) throws -> RemotePairedDeviceRecord {
        let viewerIdentity = try RemoteDeviceIdentity.generate(
            role: .viewer,
            displayName: "Test iPhone"
        )
        let invitation = try RemoteInvitationCode.generate()
        let hostParticipant = try RemotePairingParticipant(
            identity: hostIdentity,
            invitation: invitation
        )
        let viewerParticipant = try RemotePairingParticipant(
            identity: viewerIdentity,
            invitation: invitation
        )
        let hostAgreement = try hostParticipant.accept(viewerParticipant.hello)
        let viewerAgreement = try viewerParticipant.accept(hostParticipant.hello)
        var hostRecord = try hostAgreement.makePendingRecord(
            peerConfirmation: viewerAgreement.makeConfirmation()
        )
        var viewerRecord = try viewerAgreement.makePendingRecord(
            peerConfirmation: hostAgreement.makeConfirmation()
        )
        let proposal = try hostRecord.prepareProposal(using: hostIdentity)
        let acknowledgement = try viewerRecord.prepareAcknowledgement(
            after: proposal,
            using: viewerIdentity
        )
        try hostRecord.acceptAcknowledgement(acknowledgement)
        let completion = try hostRecord.prepareCompletion(using: hostIdentity)
        if completionOnly { return hostRecord }
        let activation = try viewerRecord.acceptCompletion(
            completion,
            using: viewerIdentity
        )
        try hostRecord.acceptActivationAcknowledgement(activation)
        return hostRecord
    }

    private func eventually(
        attempts: Int = 1_000,
        condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        // One thousand one-millisecond yields bound asynchronous observation to roughly one second
        // while allowing the coordinator and its child tasks to make progress under CI load.
        for _ in 0..<attempts {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }
}

private struct TestCoexistenceNativeScreenStopUnconfirmedError:
    NativeScreenCaptureStopUnconfirmedError
{}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

/// Availability transport with two intentional behaviors: a transport-originated cancellation,
/// or an open event stream that remains alive until `close`. Locking models cross-task callbacks.
private final class HostAvailabilityClientStub:
    WorldwideHostAvailabilityTransport,
    @unchecked Sendable
{
    enum Behavior: Sendable {
        case transportCancellation
        case validatedWaiting
        case wait
    }

    private let behavior: Behavior
    private let closeBarrier: AsyncStream<Void>?
    private let confirmedCloseGate: CatalogPairingCloseGate?
    private let sendBarrier: AsyncStream<Void>?
    private let lock = NSLock()
    private var continuation: PairedAvailabilitySignalingClient.EventStream.Continuation?
    private var observedOwnerCancellation: Bool?
    private var closes = 0
    private var sends = 0
    private var sendCompletions = 0

    init(behavior: Behavior, closeBarrier: AsyncStream<Void>? = nil, sendBarrier: AsyncStream<Void>? = nil,
         confirmedCloseGate: CatalogPairingCloseGate? = nil) {
        self.behavior = behavior
        self.closeBarrier = closeBarrier
        self.sendBarrier = sendBarrier
        self.confirmedCloseGate = confirmedCloseGate
    }

    func connect() async throws -> PairedAvailabilitySignalingClient.EventStream {
        if behavior == .transportCancellation {
            lock.withLock { observedOwnerCancellation = Task.isCancelled }
            throw CancellationError()
        }
        let pair = PairedAvailabilitySignalingClient.EventStream.makeStream()
        lock.withLock { continuation = pair.continuation }
        if behavior == .validatedWaiting {
            pair.continuation.yield(.waiting)
        }
        return pair.stream
    }

    func send(_: RemoteAvailabilityPayload) async throws {
        lock.withLock { sends += 1 }
        if let sendBarrier { for await _ in sendBarrier { break } }
        lock.withLock { sendCompletions += 1 }
    }

    var sendCount: Int { lock.withLock { sends } }
    var sendReturns: Int { lock.withLock { sendCompletions } }

    func close() async {
        let streamContinuation = lock.withLock { () -> PairedAvailabilitySignalingClient.EventStream.Continuation? in
            closes += 1
            defer { continuation = nil }
            return continuation
        }
        streamContinuation?.finish()
        if let closeBarrier { for await _ in closeBarrier { break } }
        await confirmedCloseGate?.wait()
    }

    func emit(_ event: PairedAvailabilitySignalingEvent) {
        let target = lock.withLock { continuation }
        target?.yield(event)
    }

    var connectObservedOwnerCancellation: Bool? {
        lock.withLock { observedOwnerCancellation }
    }

    var closeCount: Int {
        lock.withLock { closes }
    }
}

/// Ordered, thread-safe client supplier used to prove that retry creates a fresh transport.
private final class HostAvailabilityClientFactoryStub: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [HostAvailabilityClientStub]
    private var attempts = 0

    init(clients: [HostAvailabilityClientStub]) {
        self.clients = clients
    }

    func next() throws -> any WorldwideHostAvailabilityTransport {
        try lock.withLock {
            attempts += 1
            guard !clients.isEmpty else { throw CoordinatorTestError.noClient }
            return clients.removeFirst()
        }
    }

    var attemptCount: Int {
        lock.withLock { attempts }
    }
}

private enum CompletionOutcome: Equatable, Sendable {
    case normal
    case unexpectedLoopEnd
    case otherError
}

private final class CompletionOutcomeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: CompletionOutcome?

    func set(_ newValue: CompletionOutcome) {
        lock.withLock { outcome = newValue }
    }

    var value: CompletionOutcome? {
        lock.withLock { outcome }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    func set() {
        lock.withLock { storage = true }
    }

    var value: Bool {
        lock.withLock { storage }
    }
}

private final class LockedValues<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ value: Element) {
        lock.withLock { storage.append(value) }
    }

    var values: [Element] {
        lock.withLock { storage }
    }
}

private final class CoordinatorMemoryPairingDataStore:
    WorldwidePairingDataStore,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func data(for account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    func set(_ data: Data, for account: String) throws {
        lock.withLock { values[account] = data }
    }

    func removeData(for account: String) throws {
        _ = lock.withLock { values.removeValue(forKey: account) }
    }
}

private struct SilentLogger: Logger {
    func info(_: String) {}
    func debug(_: String) {}
    func error(_: String) {}
}

private final class RecordingLogger: Logger, @unchecked Sendable {
    private let lock = NSLock()
    private var information: [String] = []

    func info(_ message: String) {
        lock.withLock { information.append(message) }
    }

    func debug(_: String) {}
    func error(_: String) {}

    var informationMessages: [String] {
        lock.withLock { information }
    }
}

private enum CoordinatorTestError: Error {
    case noClient
}

private final class RecordingConnectionTelemetry:
    ConnectionTelemetryRecording,
    @unchecked Sendable
{
    // Fixed wall-clock and monotonic values keep assertions focused on event ordering and fields;
    // timing behavior is exercised separately through the injected retry sleeper.
    private let lock = NSLock()
    private var events: [ConnectionTelemetryEvent] = []

    func record(_ draft: ConnectionTelemetryDraft) -> ConnectionTelemetrySnapshot {
        lock.withLock {
            events.append(
                ConnectionTelemetryEvent(
                    id: UInt64(events.count + 1),
                    timestamp: Date(timeIntervalSince1970: 0),
                    monotonicNanoseconds: UInt64(events.count),
                    role: draft.role,
                    stage: draft.stage,
                    attemptReference: draft.attemptReference,
                    pairReference: draft.pairReference,
                    exchangeReference: draft.exchangeReference,
                    retryOrdinal: draft.retryOrdinal,
                    delayMilliseconds: draft.delayMilliseconds,
                    failure: draft.failure,
                    terminal: draft.terminal
                )
            )
            return snapshotLocked()
        }
    }

    func snapshot() -> ConnectionTelemetrySnapshot {
        lock.withLock { snapshotLocked() }
    }

    private func snapshotLocked() -> ConnectionTelemetrySnapshot {
        ConnectionTelemetrySnapshot(
            events: events,
            droppedEventCount: 0,
            persistenceHealthy: true
        )
    }
}

private final class SuspendedFlushConnectionTelemetry:
    ConnectionTelemetryRecording,
    @unchecked Sendable
{
    let flushStarted: AsyncStream<Void>

    private let flushStartedContinuation: AsyncStream<Void>.Continuation
    private let flushRelease: AsyncStream<Void>
    private let flushReleaseContinuation: AsyncStream<Void>.Continuation

    init() {
        let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        flushStarted = started.stream
        flushStartedContinuation = started.continuation
        let release = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        flushRelease = release.stream
        flushReleaseContinuation = release.continuation
    }

    func record(_: ConnectionTelemetryDraft) -> ConnectionTelemetrySnapshot {
        .empty
    }

    func snapshot() -> ConnectionTelemetrySnapshot {
        .empty
    }

    func flush() async -> ConnectionTelemetrySnapshot {
        flushStartedContinuation.yield(())
        flushStartedContinuation.finish()
        for await _ in flushRelease { break }
        return .empty
    }

    func releaseFlush() {
        flushReleaseContinuation.yield(())
        flushReleaseContinuation.finish()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
