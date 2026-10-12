import CaptureCore
import Foundation
@testable import RemoteSessionCore
import XCTest
@testable import CaptureServer

/// Private/uncompiled additions. ORIGINAL coordinator APIs only; no candidate ABI or producer.
@MainActor
final class WorldwideRuntimeCatalogAdmissionActorTests: XCTestCase {
    func testFrozenQuietOwnerFreshCatalogTicketOrderingKeepsNativeCallbacksLazy() throws {
        let pair = try RuntimeCatalogPair.make()
        let snapshot = try pair.snapshot(), epoch = UUID()
        let ticket = WorldwidePhoneCatalogAction(token: snapshot.token, selectionEpoch: epoch)
        let trace = RuntimeCatalogTrace()
        var facts = FrozenRuntimeCatalogAdmissionReference.QuietFacts()
        facts.pairedRecordPresent = true
        facts.validatedWaiting = true
        facts.started = false
        expect(.notQuiet) {
            try FrozenRuntimeCatalogAdmissionReference.admitTicket(ticket, epoch: epoch,
                facts: facts, identityPresent: true, cached: snapshot,
                owner: { trace.add("owner"); return false },
                authorization: { trace.add("authorization"); return false },
                fresh: { trace.add("fresh"); return snapshot })
        }
        XCTAssertEqual(trace.values, [])
        facts.started = true
        expect(.ownerNotAuthorized) {
            try FrozenRuntimeCatalogAdmissionReference.admitTicket(ticket, epoch: epoch,
                facts: facts, identityPresent: true, cached: snapshot,
                owner: { trace.add("owner"); return false },
                authorization: { trace.add("authorization"); return true },
                fresh: { trace.add("fresh"); return snapshot })
        }
        XCTAssertEqual(trace.values, ["owner"])
        trace.clear()
        let sentinel = RuntimeCatalogStorageSentinel()
        XCTAssertThrowsError(try FrozenRuntimeCatalogAdmissionReference.admitTicket(
            ticket, epoch: UUID(), facts: facts, identityPresent: true, cached: snapshot,
            owner: { trace.add("owner"); return true },
            authorization: { trace.add("authorization"); return true },
            fresh: { trace.add("fresh"); throw sentinel })) {
            XCTAssertTrue(($0 as? RuntimeCatalogStorageSentinel) === sentinel)
        }
        XCTAssertEqual(trace.values, ["owner", "authorization", "fresh"])
    }

    func testFrozenFirstPairReferenceConsumesIntentOnceAndKeepsReadbackAuthoritySeparate() throws {
        let memory = RuntimeCatalogMemory(), store = WorldwidePairingStore(dataStore: memory)
        let host = try store.loadOrCreateHostIdentity(displayName: "Private frozen intent witness")
        let admitted = try store.phoneCatalog.loadOrMigrate(for: host)
        let record = try RuntimeCatalogPair.activeRecord(host: host)
        let readback = WorldwidePairedPhoneCatalogSnapshot(token: .init(
            catalogID: admitted.token.catalogID, revision: 7), selectedPhoneID: nil,
            records: [record], legacyImportReceipt: nil)
        let attempt = UUID(), epoch = UUID()
        var stored: FrozenRuntimeCatalogAdmissionReference.FirstPairIntent? = .init(
            attemptID: attempt, epoch: epoch, admitted: admitted)
        let taken = FrozenRuntimeCatalogAdmissionReference.takeIntent(&stored)
        XCTAssertNil(stored)
        XCTAssertNil(FrozenRuntimeCatalogAdmissionReference.takeIntent(&stored))
        XCTAssertEqual(try FrozenRuntimeCatalogAdmissionReference.selectionAfterReadback(
            record: record, readback: (readback, record), intent: taken, currentAttempt: attempt,
            epoch: epoch, cached: admitted, identityPresent: true, authorization: { true }),
            .select(record.remoteDeviceID, readback.token))
        expect(.staleAttempt) {
            _ = try FrozenRuntimeCatalogAdmissionReference.selectionAfterReadback(record: record,
                readback: (readback, record), intent: taken, currentAttempt: UUID(), epoch: epoch,
                cached: admitted, identityPresent: true, authorization: { true })
        }
        let trace = RuntimeCatalogTrace()
        XCTAssertEqual(try FrozenRuntimeCatalogAdmissionReference.selectionAfterReadback(
            record: record, readback: (readback, record), intent: nil, currentAttempt: attempt,
            epoch: epoch, cached: admitted, identityPresent: false,
            authorization: { trace.add("authorization"); return false }), .retainReadback)
        XCTAssertEqual(trace.values, [], "Interrupted readback does not acquire first-pair write authority")
        // This is explicitly a native-value reference test, not injection into actor-private intent.
    }

    func testDefaultMutationCapabilityRefusesBeforeRetiringWaitingClient() async throws {
        let pair = try RuntimeCatalogPair.make(), client = RuntimeCatalogAvailabilityProbe()
        let owner = WorldwideHostCoordinator(endpoint: URL(string: "wss://example.invalid")!,
            forceRelay: false, screenDisplayID: nil, systemAudioDisplayID: nil,
            maximumWidth: 1_280, framesPerSecond: 30, maximumVideoBitrate: 4_000_000,
            remoteInputController: MacRemoteInputController(allowRemoteControl: false), store: pair.store,
            availabilityClientFactory: { _, _ in client }, logger: RuntimeCatalogLogger())
        addTeardownBlock { _ = await owner.stop() }
        _ = try await owner.start(resetPairing: false)
        try await waitUntil { client.connected }
        // Owner denial is witnessed only after the actor's actual quiet boundary, not socket-open alone.
        var denialWitnessed = false
        for _ in 0..<4_000 {
            do { _ = try await owner.phoneCatalogAction(); XCTFail("Default must deny mutation"); break }
            catch WorldwidePhoneCatalogRuntimeError.notQuiet {
                try await Task.sleep(for: .milliseconds(1)); continue
            } catch WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized { denialWitnessed = true; break }
        }
        XCTAssertTrue(denialWitnessed, "Default refusal must be observed at the actual quiet boundary")
        let before = try pair.snapshot(), bytes = try XCTUnwrap(pair.memory.catalogBytes)
        let writes = pair.memory.catalogWrites
        let fabricated = WorldwidePhoneCatalogAction(token: before.token, selectionEpoch: UUID())
        do { try await owner.selectPhone(nil, action: fabricated); XCTFail("Default mutation callback must refuse") }
        catch WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized { }
        XCTAssertEqual(client.closeReturns, 0)
        XCTAssertTrue(pair.memory.catalogBytes == bytes)
        XCTAssertEqual(pair.memory.catalogWrites, writes)
    }

    func testSelectionWaitsForReturnedExactOldCloseAndIndependentlyHeldAvailabilityTask() async throws {
        let h = try await heldAcknowledgementOwner()
        let before = try h.pair.snapshot(), bytes = try XCTUnwrap(h.pair.memory.catalogBytes)
        let writes = h.pair.memory.catalogWrites
        let action = try await h.coordinator.phoneCatalogAction()
        let returned = RuntimeCatalogFlag()
        let selection = Task {
            defer { returned.set() }
            try await h.coordinator.selectPhone(nil, action: action)
        }
        addTeardownBlock { h.send.open(); _ = await selection.result }
        try await waitUntil { h.old.closeReturns == 1 }
        try await assertStillDraining(h, before: before, bytes: bytes, writes: writes, returned: returned)
        h.send.open()
        try await selection.value
        XCTAssertEqual(h.old.completionReturns, 1)
        XCTAssertEqual(h.workerEnds.value, 1)
        XCTAssertEqual(h.factory.calls, 1, "Deselection must not create a replacement transport")
        let after = try await h.coordinator.pairedPhones()
        XCTAssertEqual(after.records, before.records)
        XCTAssertEqual(after.legacyImportReceipt, before.legacyImportReceipt)
        XCTAssertNil(after.selectedPhoneID)
        XCTAssertEqual(after.token.catalogID, before.token.catalogID)
        XCTAssertEqual(after.token.revision, before.token.revision + 1)
        XCTAssertEqual(h.pair.memory.catalogWrites, writes + 1)
        XCTAssertEqual(h.pair.memory.endCountAtLastWrite, 1,
            "Actual worker termination must precede the command's durable effect")
        let next = try await h.coordinator.phoneCatalogAction()
        XCTAssertNotEqual(next.selectionEpoch, action.selectionEpoch)
        XCTAssertNil(h.presentations.latest?.connectedMediaTarget)
    }

    func testForeignDurableWriteWhileExactOldTaskIsHeldPreventsMutationAndRecovery() async throws {
        let h = try await heldAcknowledgementOwner()
        let action = try await h.coordinator.phoneCatalogAction(), before = try h.pair.snapshot()
        let returned = RuntimeCatalogFlag()
        let selection = Task {
            defer { returned.set() }
            try await h.coordinator.selectPhone(nil, action: action)
        }
        addTeardownBlock { h.send.open(); _ = await selection.result }
        try await waitUntil { h.old.closeReturns == 1 }
        XCTAssertFalse(returned.value)
        let foreignRecord = try RuntimeCatalogPair.activeRecord(host: h.pair.host)
        let foreign = try h.pair.store.phoneCatalog.addPairedPhone(foreignRecord,
            for: h.pair.host, expectedToken: before.token)
        let foreignBytes = try XCTUnwrap(h.pair.memory.catalogBytes)
        let writes = h.pair.memory.catalogWrites
        h.send.open()
        do { try await selection.value; XCTFail("Foreign complete snapshot must not be adopted") }
        catch WorldwidePhoneCatalogRuntimeError.staleSelection { }
        XCTAssertEqual(h.workerEnds.value, 1)
        XCTAssertEqual(try h.pair.snapshot(), foreign)
        XCTAssertTrue(h.pair.memory.catalogBytes == foreignBytes)
        XCTAssertEqual(h.pair.memory.catalogWrites, writes)
        XCTAssertEqual(h.factory.calls, 1, "Foreign state cannot resume a guessed predecessor")
        do { _ = try await h.coordinator.pairedPhones(); XCTFail("Cached actor snapshot must remain fenced") }
        catch WorldwidePhoneCatalogRuntimeError.staleSelection { }
    }

    func testCancelledSelectStillDrainsThenAppliesOriginalSelectionSemantics() async throws {
        let h = try await heldAcknowledgementOwner()
        let before = try h.pair.snapshot(), bytes = try XCTUnwrap(h.pair.memory.catalogBytes)
        let writes = h.pair.memory.catalogWrites, action = try await h.coordinator.phoneCatalogAction()
        let returned = RuntimeCatalogFlag()
        let selection = Task {
            defer { returned.set() }
            try await h.coordinator.selectPhone(nil, action: action)
        }
        addTeardownBlock { h.send.open(); _ = await selection.result }
        try await waitUntil { h.old.closeReturns == 1 }
        selection.cancel()
        try await assertStillDraining(h, before: before, bytes: bytes, writes: writes, returned: returned)
        h.send.open()
        try await selection.value // ORIGINAL Select/Forget do not check caller cancellation.
        let after = try await h.coordinator.pairedPhones()
        XCTAssertNil(after.selectedPhoneID)
        XCTAssertEqual(after.records, before.records)
        XCTAssertEqual(h.pair.memory.catalogWrites, writes + 1)
        XCTAssertEqual(h.workerEnds.value, 1)
    }

    func testCancelledPairAnotherRecoversOnlyAfterExactOldTaskTerminalBoundary() async throws {
        let h = try await heldAcknowledgementOwner()
        let before = try h.pair.snapshot(), bytes = try XCTUnwrap(h.pair.memory.catalogBytes)
        let writes = h.pair.memory.catalogWrites, action = try await h.coordinator.phoneCatalogAction()
        let returned = RuntimeCatalogFlag()
        let pairing = Task {
            defer { returned.set() }
            return try await h.coordinator.pairAnotherPhone(action: action)
        }
        addTeardownBlock { h.send.open(); _ = await pairing.result }
        try await waitUntil { h.old.closeReturns == 1 }
        pairing.cancel()
        try await assertStillDraining(h, before: before, bytes: bytes, writes: writes, returned: returned)
        h.send.open()
        do { _ = try await pairing.value; XCTFail("Pair Another rechecks caller cancellation after drain") }
        catch is CancellationError { }
        try await waitUntil { h.factory.calls == 2 && h.successor.connected }
        let next = try await awaitAction(h.coordinator)
        XCTAssertNotEqual(next.selectionEpoch, action.selectionEpoch)
        XCTAssertEqual(next.token, action.token)
        XCTAssertEqual(try h.pair.snapshot(), before)
        XCTAssertTrue(h.pair.memory.catalogBytes == bytes)
        XCTAssertEqual(h.pair.memory.catalogWrites, writes)
        XCTAssertEqual(h.workerEnds.value, 1)
        XCTAssertEqual(h.pairingCalls.value, 0)
        XCTAssertEqual(h.successor.closeReturns, 0)
    }

    func testStopJoinsRetainedAvailabilityTaskAndPreventsLateSelection() async throws {
        let h = try await heldAcknowledgementOwner()
        let before = try h.pair.snapshot(), bytes = try XCTUnwrap(h.pair.memory.catalogBytes)
        let writes = h.pair.memory.catalogWrites, action = try await h.coordinator.phoneCatalogAction()
        let selectionReturned = RuntimeCatalogFlag(), stopReturned = RuntimeCatalogFlag()
        let selection = Task {
            defer { selectionReturned.set() }
            try await h.coordinator.selectPhone(nil, action: action)
        }
        addTeardownBlock { h.send.open(); _ = await selection.result }
        try await waitUntil { h.old.closeReturns == 1 }
        let stopping = Task {
            defer { stopReturned.set() }
            return await h.coordinator.stop()
        }
        addTeardownBlock { h.send.open(); _ = await stopping.result }
        try await waitUntil { h.presentations.latest?.phase == .stopped && h.old.closeReturns == 2 }
        XCTAssertFalse(stopReturned.value)
        XCTAssertFalse(selectionReturned.value)
        XCTAssertEqual(h.workerEnds.value, 0)
        XCTAssertTrue(h.pair.memory.catalogBytes == bytes)
        h.send.open()
        let clean = await stopping.value
        XCTAssertTrue(clean)
        do { try await selection.value; XCTFail("Stopped operation cannot select after late task drain") }
        catch is CancellationError { }
        XCTAssertEqual(h.workerEnds.value, 1)
        XCTAssertEqual(try h.pair.snapshot(), before)
        XCTAssertEqual(h.pair.memory.catalogWrites, writes)
        XCTAssertEqual(h.factory.calls, 1)
        XCTAssertNil(h.presentations.latest?.phones.action)
    }

    func testPostDrainMutationDenialResumesUnchangedSelectionWithoutGrantingMutationTicket() async throws {
        let h = try await heldAcknowledgementOwner()
        let action = try await h.coordinator.phoneCatalogAction(), before = try h.pair.snapshot()
        let writes = h.pair.memory.catalogWrites
        let selection = Task { try await h.coordinator.selectPhone(nil, action: action) }
        addTeardownBlock { h.send.open(); _ = await selection.result }
        try await waitUntil { h.old.closeReturns == 1 }
        h.permission.authorization = false
        h.send.open()
        do { try await selection.value; XCTFail("Post-drain mutation callback must refuse") }
        catch WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized { }
        try await waitUntil { h.factory.calls == 2 && h.presentations.latest?.phase == .pairedWaiting }
        XCTAssertEqual(try h.pair.snapshot(), before)
        XCTAssertEqual(h.pair.memory.catalogWrites, writes)
        do { _ = try await h.coordinator.phoneCatalogAction(); XCTFail("Resume is not mutation authority") }
        catch WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized { }
        XCTAssertNil(h.presentations.latest?.phones.action)
        XCTAssertEqual(h.workerEnds.value, 1)
    }

    func testSelectionWriteFailureRecoversOnlyExactUnchangedDurablePredecessor() async throws {
        for writeThenThrow in [false, true] {
            let h = try await heldAcknowledgementOwner()
            let before = try h.pair.snapshot(), bytes = try XCTUnwrap(h.pair.memory.catalogBytes)
            let writes = h.pair.memory.catalogWrites, action = try await h.coordinator.phoneCatalogAction()
            let selection = Task { try await h.coordinator.selectPhone(nil, action: action) }
            addTeardownBlock { h.send.open(); _ = await selection.result }
            try await waitUntil { h.old.closeReturns == 1 }
            let sentinel = RuntimeCatalogStorageSentinel()
            h.pair.memory.failNextCatalogWrite(writeThenThrow: writeThenThrow, error: sentinel)
            h.send.open()
            do { try await selection.value; XCTFail("Configured native write must throw its exact error") }
            catch { XCTAssertTrue((error as? RuntimeCatalogStorageSentinel) === sentinel) }
            XCTAssertEqual(h.workerEnds.value, 1)
            XCTAssertEqual(h.pair.memory.catalogWrites, writes + 1)
            let durable = try h.pair.snapshot()
            if writeThenThrow {
                XCTAssertNil(durable.selectedPhoneID)
                XCTAssertEqual(durable.records, before.records)
                XCTAssertEqual(durable.token.revision, before.token.revision + 1)
                XCTAssertEqual(h.factory.calls, 1, "Actual changed bytes forbid guessed predecessor recovery")
                do { _ = try await h.coordinator.pairedPhones(); XCTFail("Actor memory cannot publish a thrown write") }
                catch WorldwidePhoneCatalogRuntimeError.staleSelection { }
            } else {
                XCTAssertEqual(durable, before)
                XCTAssertTrue(h.pair.memory.catalogBytes == bytes)
                _ = try await awaitAction(h.coordinator)
                XCTAssertEqual(h.factory.calls, 2)
                XCTAssertEqual(h.successor.closeReturns, 0)
            }
            _ = await h.coordinator.stop()
        }
    }

    func testFirstPairSelectionUsesExactActiveReadbackOnlyAfterOwnedBootstrapTeardown() async throws {
        let h = try await firstPairOwner()
        let before = try h.store.phoneCatalog.loadOrMigrate(for: h.host)
        let record = try XCTUnwrap(before.records.first)
        XCTAssertEqual(record.pairingState, .active)
        XCTAssertEqual(before.records.count, 1)
        XCTAssertNil(before.selectedPhoneID)
        XCTAssertEqual(h.availabilityCalls.value, 0)
        let writes = h.memory.catalogWrites
        do { _ = try await h.coordinator.phoneCatalogAction(); XCTFail("Held bootstrap still owns the attempt") }
        catch WorldwidePhoneCatalogRuntimeError.notQuiet { }
        await h.close.release()
        _ = try await awaitAction(h.coordinator)
        let after = try await h.coordinator.pairedPhones()
        XCTAssertEqual(after.records, before.records)
        XCTAssertEqual(after.selectedPhoneID, record.remoteDeviceID)
        XCTAssertEqual(after.token.catalogID, before.token.catalogID)
        XCTAssertEqual(after.token.revision, before.token.revision + 1)
        XCTAssertEqual(h.memory.catalogWrites, writes + 1)
        XCTAssertEqual(h.availabilityCalls.value, 1)
        XCTAssertTrue(h.memory.identityBytes == h.identityBytes)
        XCTAssertNil(h.memory.legacyBytes)
    }

    func testFirstPairOwnerAndMutationRevalidationPreserveDistinctPostTeardownCuts() async throws {
        for ownerLoss in [true, false] {
            let h = try await firstPairOwner()
            let before = try h.store.phoneCatalog.loadOrMigrate(for: h.host)
            let bytes = try XCTUnwrap(h.memory.catalogBytes), writes = h.memory.catalogWrites
            if ownerLoss { h.permission.owner = false }
            else { h.permission.authorization = false }
            await h.close.release()
            try await waitUntil { ownerLoss ? h.permission.ownerDenials > 0 : h.presentations.latest?.phase == .stopped }
            XCTAssertEqual(try h.store.phoneCatalog.loadOrMigrate(for: h.host), before)
            XCTAssertTrue(h.memory.catalogBytes == bytes)
            XCTAssertEqual(h.memory.catalogWrites, writes)
            XCTAssertEqual(h.availabilityCalls.value, 0)
            if ownerLoss {
                XCTAssertNotEqual(h.presentations.latest?.phase, .stopped,
                    "Original post-stop owner refusal returns silently rather than invoking owned failure")
            }
            _ = await h.coordinator.stop()
        }
    }

    func testFirstPairHeldTeardownRejectsSameTokenDifferentCompleteNativeCheckpoint() async throws {
        for change in RuntimeCatalogMemory.SnapshotChange.allCases {
            let h = try await firstPairOwner()
            let before = try h.store.phoneCatalog.loadOrMigrate(for: h.host)
            try h.memory.changeCompleteCatalog(change)
            let foreign = try h.store.phoneCatalog.loadOrMigrate(for: h.host)
            XCTAssertEqual(foreign.token, before.token)
            XCTAssertNotEqual(foreign, before)
            let bytes = try XCTUnwrap(h.memory.catalogBytes), writes = h.memory.catalogWrites
            await h.close.release()
            try await waitUntil { h.presentations.latest?.phase == .stopped }
            XCTAssertEqual(try h.store.phoneCatalog.loadOrMigrate(for: h.host), foreign)
            XCTAssertTrue(h.memory.catalogBytes == bytes)
            XCTAssertEqual(h.memory.catalogWrites, writes)
            XCTAssertEqual(h.availabilityCalls.value, 0)
            // This reaches checkpoint full-snapshot refusal, not each later private intent guard.
        }
    }

    func testStoppedFirstPairLateOwnedCallbackCannotSelectIntoFreshCoordinator() async throws {
        let h = try await firstPairOwner()
        let before = try h.store.phoneCatalog.loadOrMigrate(for: h.host)
        let writes = h.memory.catalogWrites
        let stopped = await h.coordinator.stop()
        XCTAssertTrue(stopped, "Stop does not join the separately held pairingDidCommit task")
        XCTAssertEqual(h.logger.completionEnds, 0)
        let fresh = coordinator(store: h.store, permission: RuntimeCatalogPermission(),
            availabilityFactory: { _, _ in throw RuntimeCatalogFixtureError.unexpectedEffect },
            pairingFactory: { _, _ in throw RuntimeCatalogFixtureError.unexpectedEffect })
        addTeardownBlock { _ = await fresh.stop() }
        let started = try await fresh.start(resetPairing: false)
        XCTAssertEqual(started, .unselected)
        await h.close.release()
        try await waitUntil { h.logger.completionEnds == 1 }
        let afterLateReturn = try await fresh.pairedPhones()
        XCTAssertEqual(afterLateReturn, before)
        XCTAssertEqual(h.memory.catalogWrites, writes)
        XCTAssertEqual(h.availabilityCalls.value, 0)
    }

    // MARK: ORIGINAL-only actor fixture orchestration

    private func heldAcknowledgementOwner() async throws -> RuntimeCatalogHeldOwner {
        let pair = try RuntimeCatalogPair.make(), send = RuntimeCatalogGate()
        let old = RuntimeCatalogAvailabilityProbe(completionGate: send)
        let successor = RuntimeCatalogAvailabilityProbe()
        let factory = RuntimeCatalogAvailabilityFactory([old, successor])
        let permission = RuntimeCatalogPermission(), presentations = RuntimeCatalogPresentations()
        let workerEnds = RuntimeCatalogCounter(), pairingCalls = RuntimeCatalogCounter()
        pair.memory.observeWorkerEnds = { workerEnds.value }
        let owner = coordinator(store: pair.store, permission: permission,
            availabilityFactory: { _, _ in try factory.next() },
            pairingFactory: { _, _ in pairingCalls.increment(); throw RuntimeCatalogFixtureError.unexpectedEffect },
            workerEnded: { workerEnds.increment() }, presentations: presentations)
        addTeardownBlock { send.open(); _ = await owner.stop() }
        _ = try await owner.start(resetPairing: false)
        _ = try await awaitAction(owner)
        let before = try pair.snapshot(), writes = pair.memory.catalogWrites
        // Injected actor-boundary sequence, not a production-valid no-ready wire sequence.
        old.emit(.signal(.pairingCommit(pair.acknowledgement)))
        try await waitUntil { old.completions.count == 1 }
        let after = try pair.snapshot()
        XCTAssertEqual(after.token.revision, before.token.revision + 2)
        XCTAssertEqual(pair.memory.catalogWrites, writes + 2)
        let selected = try XCTUnwrap(after.selectedRecord)
        XCTAssertEqual(selected.pairingState, .acceptedReceived)
        XCTAssertEqual(selected.recoveryAction, .resend(try XCTUnwrap(old.completions.first)))
        XCTAssertEqual(old.completionReturns, 0)
        _ = try await owner.phoneCatalogAction() // NEW ticket, after both actual durable cuts.
        return .init(pair: pair, coordinator: owner, old: old, successor: successor,
            factory: factory, send: send, permission: permission, presentations: presentations,
            workerEnds: workerEnds, pairingCalls: pairingCalls)
    }

    private func firstPairOwner() async throws -> RuntimeCatalogFirstOwner {
        let memory = RuntimeCatalogMemory(), store = WorldwidePairingStore(dataStore: memory)
        let host = try store.loadOrCreateHostIdentity(displayName: "Private runtime fixture Mac")
        let admitted = try store.phoneCatalog.loadOrMigrate(for: host)
        let identityBytes = try XCTUnwrap(memory.identityBytes)
        let close = CatalogPairingCloseGate(), permission = RuntimeCatalogPermission()
        let calls = RuntimeCatalogCounter(), presentations = RuntimeCatalogPresentations()
        let logger = RuntimeCatalogLogger()
        let owner = coordinator(store: store, permission: permission,
            availabilityFactory: { _, _ in calls.increment(); return RuntimeCatalogAvailabilityProbe() },
            pairingFactory: { _, invitation in try CatalogPairingTransport(invitation: invitation, holdSecondClose: close) },
            presentations: presentations, logger: logger)
        addTeardownBlock { await close.release(); _ = await owner.stop() }
        _ = try await owner.start(resetPairing: false)
        let action = try await owner.phoneCatalogAction()
        XCTAssertTrue(FrozenRuntimeCatalogAdmissionReference.firstPairEligible(reset: false, snapshot: admitted))
        _ = try await owner.pairAnotherPhone(action: action)
        try await waitUntil { await close.entered }
        return .init(memory: memory, store: store, host: host, admitted: admitted,
            identityBytes: identityBytes, coordinator: owner, close: close, permission: permission,
            availabilityCalls: calls, presentations: presentations, logger: logger)
    }

    private func coordinator(
        store: WorldwidePairingStore, permission: RuntimeCatalogPermission,
        availabilityFactory: @escaping @Sendable (URL, RemoteAvailabilityLocator) throws
            -> any WorldwideHostAvailabilityTransport,
        pairingFactory: @escaping @Sendable (URL, RemoteInvitationCode) throws
            -> any WorldwideHostPairingTransport,
        workerEnded: @escaping @Sendable () -> Void = {},
        presentations: RuntimeCatalogPresentations = RuntimeCatalogPresentations(),
        logger: RuntimeCatalogLogger = RuntimeCatalogLogger()
    ) -> WorldwideHostCoordinator {
        WorldwideHostCoordinator(endpoint: URL(string: "wss://example.invalid")!, forceRelay: false,
            screenDisplayID: nil, systemAudioDisplayID: nil, maximumWidth: 1_280,
            framesPerSecond: 30, maximumVideoBitrate: 4_000_000,
            remoteInputController: MacRemoteInputController(allowRemoteControl: false), store: store,
            availabilityClientFactory: availabilityFactory,
            availabilityRetrySleep: { _ in throw RuntimeCatalogFixtureError.unexpectedEffect },
            availabilityLoopDidEndObserver: workerEnded,
            presentation: { presentations.append($0) },
            catalogMutationIsAuthorized: { permission.checkAuthorization() },
            catalogOwnerIsValid: { permission.checkOwner() }, pairingClientFactory: pairingFactory,
            mediaServiceFactory: { _ in throw RuntimeCatalogFixtureError.unexpectedEffect }, logger: logger)
    }

    private func assertStillDraining(_ h: RuntimeCatalogHeldOwner,
        before: WorldwidePairedPhoneCatalogSnapshot, bytes: Data, writes: Int,
        returned: RuntimeCatalogFlag
    ) async throws {
        // Repeated real actor turns after a witnessed close return; gate still independently holds its task.
        for _ in 0..<16 {
            XCTAssertFalse(returned.value)
            XCTAssertEqual(h.old.completionReturns, 0)
            XCTAssertEqual(h.workerEnds.value, 0)
            XCTAssertEqual(h.factory.calls, 1)
            XCTAssertEqual(h.pair.memory.catalogWrites, writes)
            XCTAssertTrue(h.pair.memory.catalogBytes == bytes)
            let current = try await h.coordinator.pairedPhones()
            XCTAssertEqual(current, before)
            do { _ = try await h.coordinator.phoneCatalogAction(); XCTFail("Retained exact task is not quiet") }
            catch WorldwidePhoneCatalogRuntimeError.notQuiet { }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private func awaitAction(_ owner: WorldwideHostCoordinator) async throws -> WorldwidePhoneCatalogAction {
        for _ in 0..<4_000 {
            if let action = try? await owner.phoneCatalogAction() { return action }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw RuntimeCatalogFixtureError.observationExpired
    }

    private func waitUntil(_ condition: @escaping @MainActor () async throws -> Bool) async throws {
        for _ in 0..<4_000 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw RuntimeCatalogFixtureError.observationExpired
    }

    private func expect(_ error: WorldwidePhoneCatalogRuntimeError, _ body: () throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? WorldwidePhoneCatalogRuntimeError, error, file: file, line: line)
        }
    }
}

private struct RuntimeCatalogHeldOwner: Sendable {
    let pair: RuntimeCatalogPair
    let coordinator: WorldwideHostCoordinator
    let old: RuntimeCatalogAvailabilityProbe
    let successor: RuntimeCatalogAvailabilityProbe
    let factory: RuntimeCatalogAvailabilityFactory
    let send: RuntimeCatalogGate
    let permission: RuntimeCatalogPermission
    let presentations: RuntimeCatalogPresentations
    let workerEnds: RuntimeCatalogCounter
    let pairingCalls: RuntimeCatalogCounter
}

private struct RuntimeCatalogFirstOwner: Sendable {
    let memory: RuntimeCatalogMemory
    let store: WorldwidePairingStore
    let host: RemoteDeviceIdentity
    let admitted: WorldwidePairedPhoneCatalogSnapshot
    let identityBytes: Data
    let coordinator: WorldwideHostCoordinator
    let close: CatalogPairingCloseGate
    let permission: RuntimeCatalogPermission
    let availabilityCalls: RuntimeCatalogCounter
    let presentations: RuntimeCatalogPresentations
    let logger: RuntimeCatalogLogger
}

private struct RuntimeCatalogPair: Sendable {
    let memory: RuntimeCatalogMemory
    let store: WorldwidePairingStore
    let host: RemoteDeviceIdentity
    let acknowledgement: RemotePairingCommit

    static func make() throws -> Self {
        let memory = RuntimeCatalogMemory(), store = WorldwidePairingStore(dataStore: memory)
        let host = try store.loadOrCreateHostIdentity(displayName: "Private runtime ACK Mac")
        let pair = try transcript(host: host)
        try store.savePairedViewer(pair.host, for: host)
        _ = try store.phoneCatalog.loadOrMigrate(for: host)
        return .init(memory: memory, store: store, host: host, acknowledgement: pair.acknowledgement)
    }

    func snapshot() throws -> WorldwidePairedPhoneCatalogSnapshot {
        try store.phoneCatalog.loadOrMigrate(for: host)
    }

    static func activeRecord(host: RemoteDeviceIdentity) throws -> RemotePairedDeviceRecord {
        let pair = try transcript(host: host)
        var record = pair.host, viewer = pair.viewer
        try record.acceptAcknowledgement(pair.acknowledgement)
        let completion = try record.prepareCompletion(using: host)
        let activation = try viewer.acceptCompletion(completion, using: pair.viewerIdentity)
        try record.acceptActivationAcknowledgement(activation)
        return record
    }

    private static func transcript(host: RemoteDeviceIdentity) throws
        -> (host: RemotePairedDeviceRecord, viewer: RemotePairedDeviceRecord,
            viewerIdentity: RemoteDeviceIdentity, acknowledgement: RemotePairingCommit) {
        let viewer = try RemoteDeviceIdentity.generate(role: .viewer, displayName: "Private runtime phone")
        let invitation = try RemoteInvitationCode.generate()
        let hp = try RemotePairingParticipant(identity: host, invitation: invitation)
        let vp = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        let ha = try hp.accept(vp.hello), va = try vp.accept(hp.hello)
        var hr = try ha.makePendingRecord(peerConfirmation: va.makeConfirmation())
        var vr = try va.makePendingRecord(peerConfirmation: ha.makeConfirmation())
        let proposal = try hr.prepareProposal(using: host)
        let acknowledgement = try vr.prepareAcknowledgement(after: proposal, using: viewer)
        return (hr, vr, viewer, acknowledgement)
    }
}

private final class RuntimeCatalogGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        await withCheckedContinuation { continuation in
            let immediate = lock.withLock {
                if opened { return true }
                waiters.append(continuation)
                return false
            }
            if immediate { continuation.resume() }
        }
    }
    func open() {
        let pending = lock.withLock {
            opened = true
            defer { waiters.removeAll() }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}

private final class RuntimeCatalogAvailabilityProbe: WorldwideHostAvailabilityTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let completionGate: RuntimeCatalogGate?
    private var stream: PairedAvailabilitySignalingClient.EventStream.Continuation?
    private var commits: [RemotePairingCommit] = []
    private var completionReturnCount = 0
    private var closeReturnCount = 0
    init(completionGate: RuntimeCatalogGate? = nil) { self.completionGate = completionGate }
    func connect() async throws -> PairedAvailabilitySignalingClient.EventStream {
        let events = PairedAvailabilitySignalingClient.EventStream.makeStream()
        lock.withLock { stream = events.continuation }
        events.continuation.yield(.waiting)
        return events.stream
    }
    func send(_ payload: RemoteAvailabilityPayload) async throws {
        guard case let .pairingCommit(commit) = payload, commit.phase == .completion else {
            throw RuntimeCatalogFixtureError.unexpectedEffect
        }
        lock.withLock { commits.append(commit) }
        await completionGate?.wait() // Intentionally noncooperative with owner/caller cancellation.
        lock.withLock { completionReturnCount += 1 }
    }
    func close() async {
        let old = lock.withLock {
            let old = stream
            stream = nil
            return old
        }
        old?.finish()
        lock.withLock { closeReturnCount += 1 }
    }
    func emit(_ event: PairedAvailabilitySignalingEvent) { lock.withLock { stream }?.yield(event) }
    var completions: [RemotePairingCommit] { lock.withLock { commits } }
    var completionReturns: Int { lock.withLock { completionReturnCount } }
    var closeReturns: Int { lock.withLock { closeReturnCount } }
    var connected: Bool { lock.withLock { stream != nil } }
}

private final class RuntimeCatalogAvailabilityFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [RuntimeCatalogAvailabilityProbe]
    private var count = 0
    init(_ clients: [RuntimeCatalogAvailabilityProbe]) { self.clients = clients }
    func next() throws -> any WorldwideHostAvailabilityTransport {
        try lock.withLock {
            count += 1
            guard !clients.isEmpty else { throw RuntimeCatalogFixtureError.unexpectedEffect }
            return clients.removeFirst()
        }
    }
    var calls: Int { lock.withLock { count } }
}

private final class RuntimeCatalogPermission: @unchecked Sendable {
    private let lock = NSLock()
    private var ownerValid = true, authorized = true, deniedOwner = 0
    var owner: Bool { get { lock.withLock { ownerValid } } set { lock.withLock { ownerValid = newValue } } }
    var authorization: Bool { get { lock.withLock { authorized } } set { lock.withLock { authorized = newValue } } }
    var ownerDenials: Int { lock.withLock { deniedOwner } }
    func checkOwner() -> Bool { lock.withLock { if !ownerValid { deniedOwner += 1 }; return ownerValid } }
    func checkAuthorization() -> Bool { lock.withLock { authorized } }
}

private final class RuntimeCatalogCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class RuntimeCatalogFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var value: Bool { lock.withLock { flag } }
}

private final class RuntimeCatalogTrace {
    private(set) var values: [String] = []
    func add(_ value: String) { values.append(value) }
    func clear() { values = [] }
}

private final class RuntimeCatalogPresentations: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [BelugaHostPresentation] = []
    func append(_ value: BelugaHostPresentation) { lock.withLock { stored.append(value) } }
    var latest: BelugaHostPresentation? { lock.withLock { stored.last } }
}

private final class RuntimeCatalogLogger: Logger, @unchecked Sendable {
    private let lock = NSLock()
    private var endings = 0
    func info(_ message: String) {
        if message == "Worldwide pairing completion task finished" { lock.withLock { endings += 1 } }
    }
    func debug(_: String) { }
    func error(_: String) { }
    var completionEnds: Int { lock.withLock { endings } }
}

private final class RuntimeCatalogMemory: WorldwidePairingDataStore, @unchecked Sendable {
    enum SnapshotChange: CaseIterable { case selected, recordCounter, receipt }
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var writes = 0, lastEndCount = 0
    private var observer: (@Sendable () -> Int)?
    private var nextFailure: (writeThenThrow: Bool, error: RuntimeCatalogStorageSentinel)?
    var observeWorkerEnds: (@Sendable () -> Int)? {
        get { lock.withLock { observer } }
        set { lock.withLock { observer = newValue } }
    }
    func data(for account: String) throws -> Data? { lock.withLock { values[account] } }
    func set(_ data: Data, for account: String) throws {
        try lock.withLock {
            if account == WorldwidePairedPhoneCatalogStore.catalogAccount {
                writes += 1
                lastEndCount = observer?() ?? 0
                if let failure = nextFailure {
                    nextFailure = nil
                    if failure.writeThenThrow { values[account] = data }
                    throw failure.error
                }
            }
            values[account] = data
        }
    }
    func failNextCatalogWrite(writeThenThrow: Bool, error: RuntimeCatalogStorageSentinel) {
        lock.withLock { nextFailure = (writeThenThrow, error) }
    }
    func removeData(for account: String) throws { _ = lock.withLock { values.removeValue(forKey: account) } }
    var catalogWrites: Int { lock.withLock { writes } }
    var endCountAtLastWrite: Int { lock.withLock { lastEndCount } }
    var catalogBytes: Data? { lock.withLock { values[WorldwidePairedPhoneCatalogStore.catalogAccount] } }
    var identityBytes: Data? { lock.withLock { values[WorldwidePairingStore.identityAccount] } }
    var legacyBytes: Data? { lock.withLock { values[WorldwidePairingStore.pairedViewerAccount] } }

    func changeCompleteCatalog(_ change: SnapshotChange) throws {
        try lock.withLock {
            let key = WorldwidePairedPhoneCatalogStore.catalogAccount
            let bytes = try XCTUnwrap(values[key])
            var envelope = try JSONDecoder().decode(RuntimeCatalogEnvelope.self, from: bytes)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            XCTAssertEqual(try encoder.encode(envelope), bytes)
            let record = try XCTUnwrap(envelope.records.first)
            switch change {
            case .selected: envelope.selectedPhoneID = record.remoteDeviceID
            case .recordCounter: envelope.records[0].nextOutboundReconnectSequence += 1
            case .receipt:
                envelope.legacyImportReceipt = .init(sourceAccount: WorldwidePairingStore.pairedViewerAccount,
                    sourceSHA256: Data(repeating: 7, count: 32), remoteDeviceID: record.remoteDeviceID,
                    pairID: record.pairID, commitID: record.commitID)
            }
            // External TEST writer; retains exact token and canonical full typed storage.
            values[key] = try encoder.encode(envelope)
            writes += 1
        }
    }
}

private struct RuntimeCatalogEnvelope: Codable {
    let version: UInt8
    let catalogID: UUID
    let revision: UInt64
    let hostDeviceID: UUID
    let hostSigningPublicKey: Data
    var selectedPhoneID: UUID?
    var records: [RemotePairedDeviceRecord]
    var legacyImportReceipt: WorldwidePairedPhoneLegacyReceipt?
}

private final class RuntimeCatalogStorageSentinel: Error, @unchecked Sendable { }
private enum RuntimeCatalogFixtureError: Error { case unexpectedEffect, observationExpired }
