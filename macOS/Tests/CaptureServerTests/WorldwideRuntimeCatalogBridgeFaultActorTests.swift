import CaptureCore
import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

/// PRIVATE uncompiled actor additions. Actual C producer first, then copied-result mutation only.
/// These expectations follow native custody/order and the approved corruption contract.
@MainActor
final class WorldwideRuntimeCatalogBridgeFaultActorTests: XCTestCase {
    func testStartupInstalledFaultRejectsBeforeActorAdoptionAndRemainsSticky() async throws {
        for selected in [false, true] {
            let seed: RuntimeBridgeSeed
            if selected { seed = try RuntimeBridgeSeed.paired(active: true) }
            else { seed = try RuntimeBridgeSeed.empty() }
            let fault = RuntimeBridgeFault(), effects = RuntimeBridgeEffects()
            let presentations = RuntimeBridgePresentations()
            fault.arm(.startupInstalled)
            let owner = coordinator(seed: seed, fault: fault, effects: effects,
                presentations: presentations)
            addTeardownBlock { _ = await owner.stop() }
            let before = try seed.snapshot(), bytes = try XCTUnwrap(seed.memory.catalogBytes)
            let writes = seed.memory.catalogWrites
            do { _ = try await owner.start(resetPairing: false); XCTFail("Corrupt startup must not return an adopted owner") }
            catch { assertBridge(error) }
            XCTAssertEqual(fault.hits, 1)
            XCTAssertEqual(fault.faultInput?.phase, 0)
            XCTAssertEqual(effects.availabilityFactories, 0)
            XCTAssertEqual(effects.pairingFactories, 0)
            XCTAssertEqual(effects.mediaFactories, 0)
            XCTAssertNil(presentations.latest)
            XCTAssertEqual(try seed.snapshot(), before)
            XCTAssertTrue(seed.memory.catalogBytes == bytes)
            XCTAssertEqual(seed.memory.catalogWrites, writes)
            let calls = fault.calls, ownerChecks = effects.ownerChecks, mutationChecks = effects.mutationChecks
            let reads = seed.memory.catalogReads
            do { _ = try await owner.start(resetPairing: false); XCTFail("Same poisoned owner cannot retry startup") }
            catch { assertBridge(error) }
            do { _ = try await owner.pairedPhones(); XCTFail("No snapshot may be adopted by retry after corruption") }
            catch { assertBridge(error) }
            XCTAssertEqual(fault.calls, calls, "Sticky denial does not invoke a replacement C proposal")
            XCTAssertEqual(effects.ownerChecks, ownerChecks)
            XCTAssertEqual(effects.mutationChecks, mutationChecks)
            XCTAssertEqual(seed.memory.catalogReads, reads)
            let clean = await owner.stop()
            XCTAssertTrue(clean, "Native cleanup remains callable on a poisoned bridge")
            XCTAssertEqual(try seed.snapshot(), before)
            XCTAssertEqual(seed.memory.catalogWrites, writes)
        }
    }

    func testCorruptFinalEndDeniesSelectSuccessWithoutRollingBackActualDurableWrite() async throws {
        let h = try await waitingOwner()
        let before = try h.seed.snapshot(), writes = h.seed.memory.catalogWrites
        let action = try await h.owner.phoneCatalogAction()
        h.fault.arm(.end)
        do { try await h.owner.selectPhone(nil, action: action); XCTFail("End corruption is not successful Select") }
        catch { assertBridge(error) }
        XCTAssertEqual(h.fault.hits, 1)
        XCTAssertEqual(h.fault.faultInput?.phase, 2)
        XCTAssertEqual(h.fault.faultInput?.operation, 1)
        let durable = try h.seed.snapshot(), bytes = try XCTUnwrap(h.seed.memory.catalogBytes)
        XCTAssertNil(durable.selectedPhoneID)
        XCTAssertEqual(durable.records, before.records)
        XCTAssertEqual(durable.legacyImportReceipt, before.legacyImportReceipt)
        XCTAssertEqual(durable.token.catalogID, before.token.catalogID)
        XCTAssertEqual(durable.token.revision, before.token.revision + 1)
        XCTAssertEqual(h.seed.memory.catalogWrites, writes + 1)
        XCTAssertEqual(h.old.closeReturns, 1)
        XCTAssertEqual(h.effects.availabilityFactories, 1)
        try await assertSticky(h.owner, fault: h.fault, seed: h.seed, bytes: bytes, writes: writes + 1)
        let clean = await h.owner.stop()
        XCTAssertTrue(clean)
        XCTAssertEqual(try h.seed.snapshot(), durable)
    }

    func testCorruptFinalEndDeniesForgetSuccessWithoutRestoringDeletedTrust() async throws {
        let h = try await waitingOwner()
        let before = try h.seed.snapshot(), writes = h.seed.memory.catalogWrites
        let selected = try XCTUnwrap(before.selectedPhoneID), action = try await h.owner.phoneCatalogAction()
        h.fault.arm(.end)
        do { try await h.owner.forgetPhone(selected, action: action); XCTFail("End corruption is not successful Forget") }
        catch { assertBridge(error) }
        XCTAssertEqual(h.fault.hits, 1)
        XCTAssertEqual(h.fault.faultInput?.phase, 2)
        XCTAssertEqual(h.fault.faultInput?.operation, 2)
        let durable = try h.seed.snapshot(), bytes = try XCTUnwrap(h.seed.memory.catalogBytes)
        XCTAssertNil(durable.selectedPhoneID)
        XCTAssertEqual(durable.records, [])
        XCTAssertEqual(durable.legacyImportReceipt, before.legacyImportReceipt)
        XCTAssertEqual(durable.token.catalogID, before.token.catalogID)
        XCTAssertEqual(durable.token.revision, before.token.revision + 1)
        XCTAssertEqual(h.seed.memory.catalogWrites, writes + 1)
        XCTAssertEqual(h.old.closeReturns, 1)
        XCTAssertEqual(h.effects.availabilityFactories, 1)
        try await assertSticky(h.owner, fault: h.fault, seed: h.seed, bytes: bytes, writes: writes + 1)
        let clean = await h.owner.stop()
        XCTAssertTrue(clean)
        XCTAssertEqual(try h.seed.snapshot(), durable, "Failed success proof cannot fabricate rollback trust")
    }

    func testCorruptFinalEndDeniesPairInvitationSuccessAndClosesExactBootstrap() async throws {
        let seed = try RuntimeBridgeSeed.empty(), fault = RuntimeBridgeFault(), effects = RuntimeBridgeEffects()
        let pairing = RuntimeBridgeIdlePairingProbe()
        let owner = coordinator(seed: seed, fault: fault, effects: effects, pairing: pairing)
        addTeardownBlock { _ = await owner.stop() }
        _ = try await owner.start(resetPairing: false)
        let before = try seed.snapshot(), bytes = try XCTUnwrap(seed.memory.catalogBytes)
        let writes = seed.memory.catalogWrites, action = try await owner.phoneCatalogAction()
        fault.arm(.end)
        do { _ = try await owner.pairAnotherPhone(action: action); XCTFail("End corruption must not export successful invitation") }
        catch { assertBridge(error) }
        XCTAssertEqual(fault.hits, 1)
        XCTAssertEqual(fault.faultInput?.phase, 2)
        XCTAssertEqual(fault.faultInput?.operation, 3)
        XCTAssertEqual(effects.pairingFactories, 1)
        XCTAssertEqual(pairing.connects, 1)
        XCTAssertGreaterThanOrEqual(pairing.closeReturns, 1)
        XCTAssertEqual(effects.availabilityFactories, 0)
        XCTAssertEqual(effects.mediaFactories, 0)
        XCTAssertEqual(try seed.snapshot(), before)
        XCTAssertTrue(seed.memory.catalogBytes == bytes)
        XCTAssertEqual(seed.memory.catalogWrites, writes)
        try await assertSticky(owner, fault: fault, seed: seed, bytes: bytes, writes: writes)
        let closes = pairing.closeReturns
        let clean = await owner.stop()
        XCTAssertTrue(clean)
        XCTAssertEqual(pairing.closeReturns, closes, "Already owned cleanup must not reopen or replace bootstrap")
    }

    func testMalformedAdmissionKeepsLiveNativeClientUntilAuthorizedStopAndNeverReproposes() async throws {
        let h = try await waitingOwner()
        let before = try h.seed.snapshot(), bytes = try XCTUnwrap(h.seed.memory.catalogBytes)
        let writes = h.seed.memory.catalogWrites
        h.fault.arm(.quietStructural)
        do { _ = try await h.owner.phoneCatalogAction(); XCTFail("Malformed copied admission is not a business refusal or ticket") }
        catch { assertBridge(error) }
        XCTAssertEqual(h.fault.hits, 1)
        let calls = h.fault.calls, ownerChecks = h.effects.ownerChecks, mutationChecks = h.effects.mutationChecks
        let reads = h.seed.memory.catalogReads
        for _ in 0..<16 {
            do { _ = try await h.owner.phoneCatalogAction(); XCTFail("Same bridge must stay poisoned") }
            catch { assertBridge(error) }
            XCTAssertEqual(h.old.closeReturns, 0, "Admission rejection does not discard exact live client custody")
            XCTAssertTrue(h.old.connected)
            XCTAssertEqual(h.ends.value, 0)
            XCTAssertEqual(h.effects.availabilityFactories, 1)
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(h.fault.calls, calls)
        XCTAssertEqual(h.effects.ownerChecks, ownerChecks, "Earlier malformed structural cut must not evaluate owner")
        XCTAssertEqual(h.effects.mutationChecks, mutationChecks)
        XCTAssertEqual(h.seed.memory.catalogReads, reads)
        XCTAssertTrue(h.seed.memory.catalogBytes == bytes)
        XCTAssertEqual(h.seed.memory.catalogWrites, writes)
        let clean = await h.owner.stop()
        XCTAssertTrue(clean)
        try await waitUntil { h.old.closeReturns == 1 && h.ends.value == 1 }
        XCTAssertEqual(try h.seed.snapshot(), before)
        XCTAssertEqual(h.seed.memory.catalogWrites, writes)
        XCTAssertEqual(h.effects.availabilityFactories, 1)
    }

    func testMalformedWhileRetirementHeldRetainsExactTaskForStopDrainWithoutWriteOrSuccessor() async throws {
        let h = try await heldAcknowledgementOwner()
        let before = try h.seed.snapshot(), bytes = try XCTUnwrap(h.seed.memory.catalogBytes)
        let writes = h.seed.memory.catalogWrites, action = try await h.owner.phoneCatalogAction()
        let commandReturned = RuntimeBridgeFlag(), stopReturned = RuntimeBridgeFlag()
        let selecting = Task {
            defer { commandReturned.set() }
            try await h.owner.selectPhone(nil, action: action)
        }
        addTeardownBlock { h.send.open(); _ = await selecting.result }
        try await waitUntil { h.old.closeReturns == 1 }
        h.fault.arm(.quietStructural)
        do { _ = try await h.owner.phoneCatalogAction(); XCTFail("Corrupt busy cut must poison, not merely return notQuiet") }
        catch { assertBridge(error) }
        XCTAssertEqual(h.fault.faultInput?.phase, 1)
        let calls = h.fault.calls
        let stopping = Task {
            defer { stopReturned.set() }
            return await h.owner.stop()
        }
        addTeardownBlock { h.send.open(); _ = await stopping.result }
        try await waitUntil { h.old.closeReturns == 2 && h.presentations.latest?.phase == .stopped }
        for _ in 0..<16 {
            XCTAssertFalse(stopReturned.value, "Poison cannot make unfinished native task drain count as success")
            XCTAssertFalse(commandReturned.value)
            XCTAssertEqual(h.old.completionReturns, 0)
            XCTAssertEqual(h.ends.value, 0)
            XCTAssertEqual(h.effects.availabilityFactories, 1)
            XCTAssertEqual(h.seed.memory.catalogWrites, writes)
            XCTAssertTrue(h.seed.memory.catalogBytes == bytes)
            XCTAssertNil(h.presentations.latest?.phones.action)
            do { _ = try await h.owner.phoneCatalogAction(); XCTFail("Poison must remain sticky during cleanup") }
            catch { assertBridge(error) }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(h.fault.calls, calls, "Native cleanup may not reset the poisoned copied owner")
        h.send.open()
        let clean = await stopping.value
        XCTAssertTrue(clean)
        do { try await selecting.value; XCTFail("Poisoned retained command cannot apply after late completion") }
        catch { assertBridge(error) }
        XCTAssertEqual(h.old.completionReturns, 1)
        XCTAssertEqual(h.ends.value, 1)
        XCTAssertEqual(try h.seed.snapshot(), before)
        XCTAssertEqual(h.seed.memory.catalogWrites, writes)
        XCTAssertEqual(h.effects.availabilityFactories, 1)
    }

    func testRetiredGenerationTerminalDoesNotConsumeArmedFaultOrTearDownSuccessor() async throws {
        let h = try await heldAcknowledgementOwner()
        let before = try h.seed.snapshot(), writes = h.seed.memory.catalogWrites
        let selected = try XCTUnwrap(before.selectedPhoneID), action = try await h.owner.phoneCatalogAction()
        let selecting = Task { try await h.owner.selectPhone(selected, action: action) }
        addTeardownBlock { h.send.open(); _ = await selecting.result }
        try await waitUntil { h.old.closeReturns == 1 }
        h.fault.arm(.availabilityEnded)
        h.send.open()
        try await selecting.value
        _ = try await awaitAction(h.owner)
        XCTAssertEqual(h.ends.value, 1)
        XCTAssertEqual(h.old.completionReturns, 1)
        XCTAssertEqual(h.fault.hits, 0,
            "Old generation is fenced natively before a corrupted policy query can own cleanup")
        XCTAssertEqual(h.fault.stageCalls(.availabilityEnded), 0)
        XCTAssertEqual(h.effects.availabilityFactories, 2)
        XCTAssertTrue(h.successor.connected)
        XCTAssertEqual(h.successor.closeReturns, 0)
        let current = try await h.owner.pairedPhones()
        XCTAssertEqual(current, before)
        XCTAssertEqual(h.seed.memory.catalogWrites, writes, "Re-selecting same native ID is a durable no-op")
        for _ in 0..<16 {
            _ = try await h.owner.phoneCatalogAction()
            XCTAssertEqual(h.successor.closeReturns, 0)
            XCTAssertEqual(h.fault.hits, 0)
            XCTAssertNil(h.presentations.latest?.connectedMediaTarget)
            try await Task.sleep(for: .milliseconds(1))
        }
        let clean = await h.owner.stop()
        XCTAssertTrue(clean)
        try await waitUntil { h.ends.value == 2 }
        XCTAssertEqual(h.fault.hits, 0, "Stop revokes native generation before its late terminal boundary")
    }

    // MARK: Private copied-output seam and original native fixture orchestration

    private func waitingOwner() async throws -> RuntimeBridgeOwner {
        let seed = try RuntimeBridgeSeed.paired(active: true)
        return try await installOwner(seed: seed, send: RuntimeBridgeGate())
    }

    private func heldAcknowledgementOwner() async throws -> RuntimeBridgeOwner {
        let seed = try RuntimeBridgeSeed.paired(active: false), send = RuntimeBridgeGate()
        let h = try await installOwner(seed: seed, send: send, holdCompletion: true)
        let before = try seed.snapshot(), writes = seed.memory.catalogWrites
        // Injected authenticated ACK-before-ready safety case, not production-valid initial wire sequence.
        h.old.emit(.signal(.pairingCommit(try XCTUnwrap(seed.acknowledgement))))
        try await waitUntil { h.old.completions.count == 1 }
        let after = try seed.snapshot()
        XCTAssertEqual(after.token.revision, before.token.revision + 2)
        XCTAssertEqual(seed.memory.catalogWrites, writes + 2)
        XCTAssertEqual(after.selectedRecord?.pairingState, .acceptedReceived)
        XCTAssertEqual(h.old.completionReturns, 0)
        _ = try await h.owner.phoneCatalogAction() // Only the newly current ticket is admitted.
        return h
    }

    private func installOwner(seed: RuntimeBridgeSeed, send: RuntimeBridgeGate,
                              holdCompletion: Bool = false) async throws -> RuntimeBridgeOwner {
        let old = RuntimeBridgeAvailabilityProbe(send: holdCompletion ? send : nil)
        let successor = RuntimeBridgeAvailabilityProbe()
        let factory = RuntimeBridgeAvailabilityFactory([old, successor])
        let fault = RuntimeBridgeFault(), effects = RuntimeBridgeEffects()
        let presentations = RuntimeBridgePresentations(), ends = RuntimeBridgeCounter()
        let owner = coordinator(seed: seed, fault: fault, effects: effects,
            presentations: presentations, availability: { try factory.next() }, ended: { ends.increment() })
        addTeardownBlock { send.open(); _ = await owner.stop() }
        _ = try await owner.start(resetPairing: false)
        _ = try await awaitAction(owner)
        // This existing receipt follows the worker's post-event current-client validation.
        // There is no await between that receipt and suspension for its next stream event.
        try await waitUntil { effects.onlineReceipts == 1 }
        return .init(seed: seed, owner: owner, fault: fault, effects: effects,
            presentations: presentations, old: old, successor: successor, send: send, ends: ends)
    }

    private func coordinator(seed: RuntimeBridgeSeed, fault: RuntimeBridgeFault,
        effects: RuntimeBridgeEffects,
        presentations: RuntimeBridgePresentations = RuntimeBridgePresentations(),
        availability: @escaping @Sendable () throws -> any WorldwideHostAvailabilityTransport = {
            throw RuntimeBridgeFixtureError.unexpectedEffect
        },
        pairing: RuntimeBridgeIdlePairingProbe? = nil,
        ended: @escaping @Sendable () -> Void = {}
    ) -> WorldwideHostCoordinator {
        WorldwideHostCoordinator(endpoint: URL(string: "wss://example.invalid")!, forceRelay: false,
            screenDisplayID: nil, systemAudioDisplayID: nil, maximumWidth: 1_280, framesPerSecond: 30,
            maximumVideoBitrate: 4_000_000,
            remoteInputController: MacRemoteInputController(allowRemoteControl: false), store: seed.store,
            availabilityClientFactory: { _, _ in effects.availabilityFactory(); return try availability() },
            availabilityRetrySleep: { _ in throw RuntimeBridgeFixtureError.unexpectedEffect },
            availabilityLoopDidEndObserver: ended, presentation: { presentations.append($0) },
            catalogMutationIsAuthorized: { effects.mutationCheck(); return true },
            catalogOwnerIsValid: { effects.ownerCheck(); return true },
            runtimeCatalogResultMutation: { state, event, result in fault.mutate(state, event, result) },
            pairingClientFactory: { _, _ in
                effects.pairingFactory()
                guard let pairing else { throw RuntimeBridgeFixtureError.unexpectedEffect }
                return pairing
            },
            mediaServiceFactory: { _ in effects.mediaFactory(); throw RuntimeBridgeFixtureError.unexpectedEffect },
            logger: RuntimeBridgeLogger(effects: effects))
    }

    private func assertSticky(_ owner: WorldwideHostCoordinator, fault: RuntimeBridgeFault,
        seed: RuntimeBridgeSeed, bytes: Data, writes: Int
    ) async throws {
        let calls = fault.calls
        for _ in 0..<4 {
            do { _ = try await owner.phoneCatalogAction(); XCTFail("Poisoned owner must not mint replacement ticket") }
            catch { assertBridge(error) }
            do { _ = try await owner.pairedPhones(); XCTFail("Poisoned query cannot adopt a fallback catalog") }
            catch { assertBridge(error) }
        }
        XCTAssertEqual(fault.calls, calls)
        XCTAssertTrue(seed.memory.catalogBytes == bytes)
        XCTAssertEqual(seed.memory.catalogWrites, writes)
    }

    private func assertBridge(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(error as? WorldwidePhoneCatalogRuntimeError, .invalidRuntimeCatalogBridge,
                       file: file, line: line)
    }

    private func awaitAction(_ owner: WorldwideHostCoordinator) async throws -> WorldwidePhoneCatalogAction {
        for _ in 0..<4_000 {
            if let action = try? await owner.phoneCatalogAction() { return action }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw RuntimeBridgeFixtureError.observationExpired
    }

    private func waitUntil(_ condition: @escaping @MainActor () async throws -> Bool) async throws {
        for _ in 0..<4_000 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw RuntimeBridgeFixtureError.observationExpired
    }
}

private struct RuntimeBridgeOwner: Sendable {
    let seed: RuntimeBridgeSeed
    let owner: WorldwideHostCoordinator
    let fault: RuntimeBridgeFault
    let effects: RuntimeBridgeEffects
    let presentations: RuntimeBridgePresentations
    let old: RuntimeBridgeAvailabilityProbe
    let successor: RuntimeBridgeAvailabilityProbe
    let send: RuntimeBridgeGate
    let ends: RuntimeBridgeCounter
}

private struct RuntimeBridgeSeed: Sendable {
    let memory: RuntimeBridgeMemory
    let store: WorldwidePairingStore
    let host: RemoteDeviceIdentity
    let acknowledgement: RemotePairingCommit?

    static func empty() throws -> Self {
        let memory = RuntimeBridgeMemory(), store = WorldwidePairingStore(dataStore: memory)
        let host = try store.loadOrCreateHostIdentity(displayName: "Private bridge fixture Mac")
        _ = try store.phoneCatalog.loadOrMigrate(for: host)
        return .init(memory: memory, store: store, host: host, acknowledgement: nil)
    }

    static func paired(active: Bool) throws -> Self {
        let memory = RuntimeBridgeMemory(), store = WorldwidePairingStore(dataStore: memory)
        let host = try store.loadOrCreateHostIdentity(displayName: "Private bridge fixture Mac")
        let viewer = try RemoteDeviceIdentity.generate(role: .viewer, displayName: "Private bridge fixture phone")
        let invitation = try RemoteInvitationCode.generate()
        let hp = try RemotePairingParticipant(identity: host, invitation: invitation)
        let vp = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        let ha = try hp.accept(vp.hello), va = try vp.accept(hp.hello)
        var hr = try ha.makePendingRecord(peerConfirmation: va.makeConfirmation())
        var vr = try va.makePendingRecord(peerConfirmation: ha.makeConfirmation())
        let proposal = try hr.prepareProposal(using: host)
        let acknowledgement = try vr.prepareAcknowledgement(after: proposal, using: viewer)
        if active {
            try hr.acceptAcknowledgement(acknowledgement)
            let completion = try hr.prepareCompletion(using: host)
            let activation = try vr.acceptCompletion(completion, using: viewer)
            try hr.acceptActivationAcknowledgement(activation)
        }
        try store.savePairedViewer(hr, for: host)
        _ = try store.phoneCatalog.loadOrMigrate(for: host)
        return .init(memory: memory, store: store, host: host, acknowledgement: acknowledgement)
    }

    func snapshot() throws -> WorldwidePairedPhoneCatalogSnapshot {
        try store.phoneCatalog.loadOrMigrate(for: host)
    }
}

private final class RuntimeBridgeFault: @unchecked Sendable {
    private let lock = NSLock()
    private var armed: UInt32?
    private var opcodes: [UInt32] = []
    private var count = 0
    private var before: BelugaRustRuntimeCatalog.State?
    func arm(_ stage: BelugaRustRuntimeCatalog.Stage) { lock.withLock { armed = stage.rawValue } }
    func mutate(_ state: BelugaRustRuntimeCatalog.State, _ event: BelugaRustRuntimeCatalog.Event,
                _ actual: BelugaRustRuntimeCatalog.Result) -> BelugaRustRuntimeCatalog.Result {
        lock.withLock {
            opcodes.append(event.opcode)
            guard armed == event.opcode else { return actual }
            armed = nil
            count += 1
            before = state
            var copied = actual
            copied.value ^= 1 // One actual copied-result field; no fabricated producer or new state.
            return copied
        }
    }
    var hits: Int { lock.withLock { count } }
    var calls: Int { lock.withLock { opcodes.count } }
    var faultInput: BelugaRustRuntimeCatalog.State? { lock.withLock { before } }
    func stageCalls(_ stage: BelugaRustRuntimeCatalog.Stage) -> Int {
        lock.withLock { opcodes.filter { $0 == stage.rawValue }.count }
    }
}

private final class RuntimeBridgeEffects: @unchecked Sendable {
    private let lock = NSLock()
    private var a = 0, p = 0, m = 0, o = 0, u = 0, online = 0
    func availabilityFactory() { lock.withLock { a += 1 } }
    func pairingFactory() { lock.withLock { p += 1 } }
    func mediaFactory() { lock.withLock { m += 1 } }
    func ownerCheck() { lock.withLock { o += 1 } }
    func mutationCheck() { lock.withLock { u += 1 } }
    func onlineReceipt() { lock.withLock { online += 1 } }
    var availabilityFactories: Int { lock.withLock { a } }
    var pairingFactories: Int { lock.withLock { p } }
    var mediaFactories: Int { lock.withLock { m } }
    var ownerChecks: Int { lock.withLock { o } }
    var mutationChecks: Int { lock.withLock { u } }
    var onlineReceipts: Int { lock.withLock { online } }
}

private final class RuntimeBridgeGate: @unchecked Sendable {
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
        let pending = lock.withLock { opened = true; defer { waiters.removeAll() }; return waiters }
        pending.forEach { $0.resume() }
    }
}

private final class RuntimeBridgeAvailabilityProbe: WorldwideHostAvailabilityTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let sendGate: RuntimeBridgeGate?
    private var stream: PairedAvailabilitySignalingClient.EventStream.Continuation?
    private var commits: [RemotePairingCommit] = []
    private var sendReturns = 0, closes = 0
    init(send: RuntimeBridgeGate? = nil) { sendGate = send }
    func connect() async throws -> PairedAvailabilitySignalingClient.EventStream {
        let events = PairedAvailabilitySignalingClient.EventStream.makeStream()
        lock.withLock { stream = events.continuation }
        events.continuation.yield(.waiting)
        return events.stream
    }
    func send(_ payload: RemoteAvailabilityPayload) async throws {
        guard case let .pairingCommit(commit) = payload, commit.phase == .completion else {
            throw RuntimeBridgeFixtureError.unexpectedEffect
        }
        lock.withLock { commits.append(commit) }
        await sendGate?.wait()
        lock.withLock { sendReturns += 1 }
    }
    func close() async {
        let old = lock.withLock { let old = stream; stream = nil; return old }
        old?.finish()
        lock.withLock { closes += 1 }
    }
    func emit(_ event: PairedAvailabilitySignalingEvent) { lock.withLock { stream }?.yield(event) }
    var completions: [RemotePairingCommit] { lock.withLock { commits } }
    var completionReturns: Int { lock.withLock { sendReturns } }
    var closeReturns: Int { lock.withLock { closes } }
    var connected: Bool { lock.withLock { stream != nil } }
}

private final class RuntimeBridgeAvailabilityFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [RuntimeBridgeAvailabilityProbe]
    init(_ clients: [RuntimeBridgeAvailabilityProbe]) { self.clients = clients }
    func next() throws -> any WorldwideHostAvailabilityTransport {
        try lock.withLock {
            guard !clients.isEmpty else { throw RuntimeBridgeFixtureError.unexpectedEffect }
            return clients.removeFirst()
        }
    }
}

private final class RuntimeBridgeIdlePairingProbe: WorldwideHostPairingTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var stream: PairingBootstrapSignalingClient.EventStream.Continuation?
    private var connections = 0, closes = 0
    func connect() async throws -> PairingBootstrapSignalingClient.EventStream {
        let events = PairingBootstrapSignalingClient.EventStream.makeStream()
        lock.withLock { stream = events.continuation; connections += 1 }
        // No peer handshake or durable checkpoint is invented while End authority is being tested.
        return events.stream
    }
    func send(_: RemotePairingPayload) async throws { throw RuntimeBridgeFixtureError.unexpectedEffect }
    func close() async {
        let old = lock.withLock { let old = stream; stream = nil; return old }
        old?.finish()
        lock.withLock { closes += 1 }
    }
    var connects: Int { lock.withLock { connections } }
    var closeReturns: Int { lock.withLock { closes } }
}

private final class RuntimeBridgeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class RuntimeBridgeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    func set() { lock.withLock { stored = true } }
    var value: Bool { lock.withLock { stored } }
}

private final class RuntimeBridgePresentations: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [BelugaHostPresentation] = []
    func append(_ value: BelugaHostPresentation) { lock.withLock { stored.append(value) } }
    var latest: BelugaHostPresentation? { lock.withLock { stored.last } }
}

private final class RuntimeBridgeMemory: WorldwidePairingDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var writes = 0, reads = 0
    func data(for account: String) throws -> Data? {
        lock.withLock {
            if account == WorldwidePairedPhoneCatalogStore.catalogAccount { reads += 1 }
            return values[account]
        }
    }
    func set(_ data: Data, for account: String) throws {
        lock.withLock {
            if account == WorldwidePairedPhoneCatalogStore.catalogAccount { writes += 1 }
            values[account] = data
        }
    }
    func removeData(for account: String) throws { _ = lock.withLock { values.removeValue(forKey: account) } }
    var catalogWrites: Int { lock.withLock { writes } }
    var catalogReads: Int { lock.withLock { reads } }
    var catalogBytes: Data? { lock.withLock { values[WorldwidePairedPhoneCatalogStore.catalogAccount] } }
}

private struct RuntimeBridgeLogger: Logger {
    let effects: RuntimeBridgeEffects
    func info(_ message: String) {
        if message.hasPrefix("Worldwide paired-device availability is online ") { effects.onlineReceipt() }
    }
    func debug(_: String) { }
    func error(_: String) { }
}

private enum RuntimeBridgeFixtureError: Error { case unexpectedEffect, observationExpired }
