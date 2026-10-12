import BelugaCore
import Foundation
import WebRTCTransport
import XCTest
@testable import CaptureServer

private final class MediaGateTestBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ value: Value) { lock.withLock { self.value = value } }
    func update(_ body: (inout Value) -> Void) { lock.withLock { body(&value) } }
}

private struct MediaGateMutationControl {
    var armed = false
    var opcode: UInt32 = 0
    var occurrence = 0
    var corruptOccurrence = 1
    var byte = 8
    var calls: [UInt32] = []
}

private func mediaGateMutation(_ control: MediaGateTestBox<MediaGateMutationControl>)
    -> BelugaRustMediaCommandGate.ResultMutation {
    { _, event, actual in
        var corruption: Int?
        control.update {
            $0.calls.append(event.opcode)
            if $0.armed && event.opcode == $0.opcode {
                $0.occurrence += 1
                if $0.occurrence == $0.corruptOccurrence { corruption = $0.byte }
            }
        }
        guard let corruption else { return actual }
        var copied = actual
        withUnsafeMutableBytes(of: &copied) { $0[corruption] ^= 1 }
        return copied
    }
}

/// Holds only synthetic native work. An actual controller must supply a current
/// authorization when this callback is released; stale work cannot record an effect.
private final class MediaGateHeldRuntime: MacSystemNowPlayingRuntime, @unchecked Sendable {
    struct Counters {
        var fetches = 0
        var commandAttempts = 0
        var pauseAttempts = 0
        var commandEffects = 0
        var pauseEffects = 0
    }
    let value: MacNowPlayingRuntimeSnapshot
    let admitted: (@Sendable () -> Void)?
    private let counters = MediaGateTestBox(Counters())
    private let pending = MediaGateTestBox<(@Sendable () -> Void)?>(nil)
    var isAvailable: Bool { true }
    var snapshot: Counters { counters.get() }

    init(_ value: MacNowPlayingRuntimeSnapshot, admitted: (@Sendable () -> Void)? = nil) {
        self.value = value
        self.admitted = admitted
    }

    func fetchSnapshot(completion: @escaping @Sendable (MacNowPlayingRuntimeSnapshotResult) -> Void) {
        counters.update { $0.fetches += 1 }
        completion(.snapshot(value))
    }

    func send(rawCommand: Int, snapshot: MacNowPlayingRuntimeSnapshot,
              isAuthorized: @escaping @Sendable () -> Bool,
              completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        counters.update { $0.commandAttempts += 1 }
        pending.set { [self] in
            guard snapshot.client === value.client, isAuthorized() else {
                completion(.staleContext); return
            }
            counters.update { $0.commandEffects += 1 }
            completion(.applied)
        }
        admitted?()
    }

    func sendHandoffPause(source: MacYouTubeHandoffSource, phonePositionSeconds: Double,
                          snapshot: MacNowPlayingRuntimeSnapshot,
                          isAuthorized: @escaping @Sendable () -> Bool,
                          completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        counters.update { $0.pauseAttempts += 1 }
        pending.set { [self] in
            guard snapshot.client === value.client, source === value.handoffSource,
                  phonePositionSeconds == 15, isAuthorized() else {
                completion(.staleContext); return
            }
            counters.update { $0.pauseEffects += 1 }
            completion(.applied)
        }
        admitted?()
    }

    func release() {
        var action: (@Sendable () -> Void)?
        pending.update { action = $0; $0 = nil }
        action?()
    }
    func stop() {}
}

/// The actual Chrome runtime may create its opaque native source only from this
/// synthetic snapshot. No Apple Events, browser, permissions or native command runs.
private struct MediaGateFixtureChromeBackend: MacChromeNowPlayingBackend {
    let player: MacChromePlayerSnapshot
    func readSnapshots(deadline: TimeInterval) throws -> [MacChromePlayerSnapshot] { [player] }
    func readSelection(preferred: MacChromePlayerSnapshot?, deadline: TimeInterval) -> MacChromeSelectionRead {
        .selected(player)
    }
    func requestAutomationPermission() throws {
        XCTFail("Media gate tests must not request desktop permission")
        throw MacChromeBackendError.unavailable
    }
    func send(_ command: MacChromeCommand, positionSeconds: TimeInterval?,
              expected: MacChromePlayerSnapshot, deadline: TimeInterval,
              isAuthorized: @escaping @Sendable () -> Bool) throws -> WebRTCRemoteMediaCommandResult {
        XCTFail("Source construction must not perform a native command")
        return .failed
    }
}

final class BelugaRustMediaCommandGateTests: XCTestCase {
    private typealias State = beluga_core_media_command_gate_state_t
    private typealias Event = beluga_core_media_command_gate_event_t
    private typealias Result = beluga_core_media_command_gate_result_t
    private typealias Reference = FrozenMediaCommandGateReference

    private func bytes<T>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value) { Array($0) }
    }

    private func state(_ lifecycle: UInt64 = 0, _ epoch: UInt64 = 0, open: Bool = false) -> State {
        State(abi_version: 1, is_open: open ? 1 : 0, lifecycle: lifecycle, command_epoch: epoch)
    }

    private func event(_ opcode: UInt32, membership: Bool = false,
                       lifecycle: UInt64 = 0, epoch: UInt64 = 0) -> Event {
        Event(opcode: opcode, context_is_current: membership ? 1 : 0,
              reserved0: 0, reserved1: 0, candidate_lifecycle: lifecycle,
              candidate_command_epoch: epoch)
    }

    /// Actual C is invoked FIRST. Expected decisions and successors then come only
    /// from the unchanged frozen native methods, not a copied Rust/facade algorithm.
    @discardableResult
    private func assertParity(_ before: State, _ input: Event,
                              file: StaticString = #filePath, line: UInt = #line) throws -> Result {
        let actual = beluga_core_media_command_gate_step(before, input)
        let reference = Reference(lifecycle: before.lifecycle, commandEpoch: before.command_epoch,
            isOpen: before.is_open == 1,
            contextIDs: input.context_is_current == 1 ? ["source"] : [])
        let allowed: Bool
        switch input.opcode {
        case 0: _ = reference.open(); allowed = false
        case 1: reference.close(); allowed = false
        case 2: reference.invalidateCommands(); allowed = false
        case 3:
            let candidate = Reference(lifecycle: input.candidate_lifecycle).currentLifecycleToken
            allowed = reference.lifecycleIsCurrent(candidate)
        case 4: allowed = reference.capture(contextID: "source") != nil
        case 5:
            let candidateOwner = Reference(lifecycle: input.candidate_lifecycle,
                commandEpoch: input.candidate_command_epoch, isOpen: true, contextIDs: ["source"])
            let captured = try XCTUnwrap(candidateOwner.capture(contextID: "source"), file: file, line: line)
            allowed = reference.admits(captured)
        default: XCTFail("Parity helper received an invalid opcode", file: file, line: line); return actual
        }
        let expected = reference.snapshot
        let result = Result(abi_version: 1, status: 1, allowed: allowed ? 1 : 0, reserved: 0,
            state: state(expected.lifecycle, expected.commandEpoch, open: expected.isOpen))
        XCTAssertEqual(bytes(actual), bytes(result), file: file, line: line)
        XCTAssertEqual(beluga_core_media_command_gate_result_is_valid(before, input, actual), 1,
                       file: file, line: line)
        return actual
    }

    private func assertDenied(_ before: State, _ input: Event,
                              file: StaticString = #filePath, line: UInt = #line) {
        let actual = beluga_core_media_command_gate_step(before, input)
        let canonical = Result(abi_version: 1, status: 0, allowed: 0, reserved: 0, state: state())
        XCTAssertEqual(bytes(actual), bytes(canonical), file: file, line: line)
        XCTAssertEqual(beluga_core_media_command_gate_result_is_valid(before, input, actual), 0,
                       file: file, line: line)
    }

    func testActualCThreeLayoutsAndAllFifteenOffsets() {
        XCTAssertTrue(UInt16(littleEndian: 1) == 1)
        XCTAssertEqual(MemoryLayout<State>.size, 24); XCTAssertEqual(MemoryLayout<State>.stride, 24)
        XCTAssertEqual(MemoryLayout<State>.alignment, 8)
        XCTAssertEqual(MemoryLayout<Event>.size, 32); XCTAssertEqual(MemoryLayout<Event>.stride, 32)
        XCTAssertEqual(MemoryLayout<Event>.alignment, 8)
        XCTAssertEqual(MemoryLayout<Result>.size, 40); XCTAssertEqual(MemoryLayout<Result>.stride, 40)
        XCTAssertEqual(MemoryLayout<Result>.alignment, 8)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.abi_version), 0)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.is_open), 4)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.lifecycle), 8)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.command_epoch), 16)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.opcode), 0)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.context_is_current), 4)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.reserved0), 8)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.reserved1), 12)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.candidate_lifecycle), 16)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.candidate_command_epoch), 24)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.abi_version), 0)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.status), 4)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.allowed), 8)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.reserved), 12)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.state), 16)
        XCTAssertTrue(BelugaRustMediaCommandGate.layoutIsExact)
        let actual = beluga_core_media_command_gate_step(state(), event(0))
        XCTAssertEqual(actual.status, 1)
    }

    func testActualCInitialOpenCloseAndRepeatedTransitionsMatchFrozenOriginal() throws {
        var raw = state()
        for opcode in [UInt32(3), 4, 5, 0, 0, 3, 1, 1, 2, 0, 4, 5, 1] {
            let input = event(opcode, membership: opcode >= 4,
                lifecycle: opcode == 3 || opcode == 5 ? raw.lifecycle : 0,
                epoch: opcode == 5 ? raw.command_epoch : 0)
            raw = try assertParity(raw, input).state
        }
    }

    func testActualCInvalidationAndNativeRemoveReaddMatchOriginalOwner() throws {
        let gate = MacRemoteMediaCommandGate(), reference = Reference()
        _ = gate.open(); _ = reference.open()
        gate.setContexts(["source", "other"]); reference.setContexts(["source", "other"])
        let captured = try XCTUnwrap(gate.capture(contextID: "source"))
        let original = try XCTUnwrap(reference.capture(contextID: "source"))
        let before = gate.snapshot
        gate.setContexts(["other"]); reference.setContexts(["other"])
        XCTAssertEqual(gate.admits(captured), reference.admits(original))
        XCTAssertFalse(gate.admits(captured))
        gate.setContexts(["other", "source"]); reference.setContexts(["other", "source"])
        XCTAssertEqual(gate.admits(captured), reference.admits(original))
        XCTAssertTrue(gate.admits(captured))
        XCTAssertEqual(bytes(gate.snapshot.rawState), bytes(before.rawState))
        gate.invalidateCommands(); reference.invalidateCommands()
        XCTAssertEqual(gate.admits(captured), reference.admits(original))
        XCTAssertFalse(gate.admits(captured))
        XCTAssertEqual(gate.snapshot.rawState.lifecycle, reference.snapshot.lifecycle)
        XCTAssertEqual(gate.snapshot.rawState.command_epoch, reference.snapshot.commandEpoch)
        let fresh = try XCTUnwrap(gate.capture(contextID: "source"))
        XCTAssertTrue(gate.admits(fresh))
        _ = try assertParity(state(42, 99), event(2))
        _ = try assertParity(state(42, 99, open: true), event(2))
    }

    func testNativeMembershipUsesSwiftEqualityAndPreservesCapturedUTF8Spelling() throws {
        let gate = MacRemoteMediaCommandGate(), reference = Reference()
        let composed = "\u{e9}", decomposed = "e\u{301}"
        XCTAssertEqual(composed, decomposed)
        XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))
        _ = gate.open(); _ = reference.open()
        let contexts: Set<String> = [composed, "", "zero\u{0}context", "👩🏾‍🚀", String(repeating: "x", count: 20_000)]
        gate.setContexts(contexts); reference.setContexts(contexts)
        for candidate in [decomposed, "", "zero\u{0}context", "👩🏾‍🚀", String(repeating: "x", count: 20_000)] {
            let actual = try XCTUnwrap(gate.capture(contextID: candidate))
            let expected = try XCTUnwrap(reference.capture(contextID: candidate))
            let observed = MacRemoteMediaCommandGate.authorizationSnapshot(actual)
            let frozen = Reference.authorizationSnapshot(expected)
            XCTAssertEqual(observed.lifecycle, frozen.lifecycle)
            XCTAssertEqual(observed.commandEpoch, frozen.commandEpoch)
            XCTAssertEqual(Array(observed.contextID.utf8), Array(frozen.contextID.utf8))
            XCTAssertEqual(Array(observed.contextID.utf8), Array(candidate.utf8))
            XCTAssertEqual(gate.admits(actual), reference.admits(expected))
        }
        XCTAssertNil(gate.capture(contextID: "E\u{301}"))
        XCTAssertNil(gate.capture(contextID: "zero"))
        XCTAssertFalse(gate.snapshot.hasNativeFault)
    }

    func testActualCFullUInt64WrapAndIndependentCountersMatchFrozenOriginal() throws {
        let counters: [UInt64] = [0, 1, UInt64.max - 1, UInt64.max]
        for lifecycle in counters {
            for epoch in counters {
                for open in [false, true] {
                    for opcode in [UInt32(0), 1, 2] {
                        let before = state(lifecycle, epoch, open: open)
                        let result = try assertParity(before, event(opcode))
                        _ = try assertParity(result.state, event(3, lifecycle: result.state.lifecycle))
                        _ = try assertParity(result.state, event(5, membership: true,
                            lifecycle: result.state.lifecycle, epoch: result.state.command_epoch))
                        _ = try assertParity(before, event(5, membership: true,
                            lifecycle: lifecycle ^ 1, epoch: epoch))
                        _ = try assertParity(before, event(5, membership: true,
                            lifecycle: lifecycle, epoch: epoch ^ 1))
                    }
                }
            }
        }
    }

    func testEveryMalformedStateEventAndUnusedWordReturnsCanonicalDenial() {
        let before = state(UInt64.max, 17, open: true)
        for abi in [UInt32(0), 2, UInt32.max] {
            var invalid = before; invalid.abi_version = abi
            assertDenied(invalid, event(0))
        }
        for tag in [UInt32(2), UInt32.max] {
            var invalid = before; invalid.is_open = tag
            assertDenied(invalid, event(5, membership: true, lifecycle: UInt64.max, epoch: 17))
        }
        for opcode in [UInt32(6), UInt32.max] { assertDenied(before, event(opcode)) }
        for opcode in UInt32(0)...UInt32(5) {
            var reserved = event(opcode); reserved.reserved0 = 1; assertDenied(before, reserved)
            reserved = event(opcode); reserved.reserved1 = UInt32.max; assertDenied(before, reserved)
            reserved = event(opcode); reserved.context_is_current = 2; assertDenied(before, reserved)
            reserved.context_is_current = UInt32.max; assertDenied(before, reserved)
            if opcode <= 3 {
                reserved = event(opcode, membership: true); assertDenied(before, reserved)
            }
            if opcode <= 2 || opcode == 4 {
                reserved = event(opcode, lifecycle: UInt64.max); assertDenied(before, reserved)
            }
            if opcode <= 4 {
                reserved = event(opcode, epoch: UInt64.max); assertDenied(before, reserved)
            }
        }
    }

    func testActualVerifierRejectsEveryCopiedResultByteIncludingQueryState() {
        let before = state(UInt64.max, 19, open: true)
        for opcode in UInt32(0)...UInt32(5) {
            let input = event(opcode, membership: opcode >= 4,
                lifecycle: opcode == 3 || opcode == 5 ? UInt64.max : 0,
                epoch: opcode == 5 ? 19 : 0)
            let actual = beluga_core_media_command_gate_step(before, input)
            XCTAssertEqual(beluga_core_media_command_gate_result_is_valid(before, input, actual), 1)
            for byte in 0..<40 {
                var changed = actual
                withUnsafeMutableBytes(of: &changed) { $0[byte] ^= 1 }
                XCTAssertEqual(beluga_core_media_command_gate_result_is_valid(before, input, changed), 0,
                               "opcode \(opcode), copied byte \(byte)")
            }
        }
    }

    private func call(_ opcode: UInt32, facade: inout BelugaRustMediaCommandGate) -> Bool {
        switch opcode {
        case 0: return facade.open()
        case 1: return facade.close()
        case 2: return facade.invalidateCommands()
        case 3: return facade.lifecycleIsCurrent(facade.rawState.lifecycle)
        case 4: return facade.capture(contextIsCurrent: true)
        default: return facade.admits(lifecycle: facade.rawState.lifecycle,
            commandEpoch: facade.rawState.command_epoch, contextIsCurrent: true)
        }
    }

    func testActualFacadeEveryOpcodeDenialRetainsStateAndLatchesWithoutFurtherCalls() {
        for opcode in UInt32(0)...UInt32(5) {
            for byte in 0..<40 {
                let control = MediaGateTestBox(MediaGateMutationControl(opcode: opcode, byte: byte))
                var facade = BelugaRustMediaCommandGate(resultMutation: mediaGateMutation(control))
                XCTAssertTrue(facade.open()); XCTAssertTrue(facade.invalidateCommands())
                let before = bytes(facade.rawState)
                control.update { $0.armed = true }
                XCTAssertFalse(call(opcode, facade: &facade))
                XCTAssertTrue(facade.hasNativeFault)
                XCTAssertEqual(bytes(facade.rawState), before)
                let calls = control.get().calls
                for denied in UInt32(0)...UInt32(5) { XCTAssertFalse(call(denied, facade: &facade)) }
                XCTAssertEqual(control.get().calls, calls)
                XCTAssertEqual(bytes(facade.rawState), before)
            }
        }
        var independent = BelugaRustMediaCommandGate()
        XCTAssertTrue(independent.open())
        XCTAssertTrue(independent.capture(contextIsCurrent: true))
        XCTAssertFalse(independent.hasNativeFault)
    }

    func testActualLockedOwnerEveryOpcodeDenialRetainsContextAndNoAuthorityCanResume() throws {
        for opcode in UInt32(0)...UInt32(5) {
            let control = MediaGateTestBox(MediaGateMutationControl(opcode: opcode, byte: 32))
            let gate = MacRemoteMediaCommandGate(resultMutation: mediaGateMutation(control))
            let token = gate.open()
            gate.setContexts(["source", "other"])
            let authorization = try XCTUnwrap(gate.capture(contextID: "source"))
            let before = gate.snapshot
            control.update { $0.armed = true }
            switch opcode {
            case 0: XCTAssertEqual(MacRemoteMediaCommandGate.lifecycleValue(gate.open()), before.rawState.lifecycle)
            case 1: gate.close()
            case 2: gate.invalidateCommands()
            case 3: XCTAssertFalse(gate.lifecycleIsCurrent(token))
            case 4: XCTAssertNil(gate.capture(contextID: "source"))
            default: XCTAssertFalse(gate.admits(authorization))
            }
            let rejected = gate.snapshot
            XCTAssertTrue(rejected.hasNativeFault)
            XCTAssertEqual(bytes(rejected.rawState), bytes(before.rawState))
            XCTAssertEqual(rejected.contextIDs, before.contextIDs)
            let calls = control.get().calls
            gate.setContexts(["source", "replacement"])
            _ = gate.open(); gate.invalidateCommands()
            XCTAssertFalse(gate.lifecycleIsCurrent(token))
            XCTAssertNil(gate.capture(contextID: "source"))
            XCTAssertFalse(gate.admits(authorization))
            XCTAssertEqual(control.get().calls, calls)
            XCTAssertEqual(bytes(gate.snapshot.rawState), bytes(before.rawState))
            gate.close()
            XCTAssertTrue(gate.snapshot.contextIDs.isEmpty)
            XCTAssertTrue(gate.snapshot.hasNativeFault)
            XCTAssertEqual(bytes(gate.snapshot.rawState), bytes(before.rawState))
            XCTAssertEqual(control.get().calls, calls)
        }
        let healthy = MacRemoteMediaCommandGate()
        let token = healthy.open(); healthy.setContext("source")
        let authorization = try XCTUnwrap(healthy.capture(contextID: "source"))
        XCTAssertTrue(healthy.lifecycleIsCurrent(token)); XCTAssertTrue(healthy.admits(authorization))
        XCTAssertFalse(healthy.snapshot.hasNativeFault)
    }

    func testFirstDeniedClosePreservesSetAndLaterFaultedCloseClearsOnlySet() {
        let control = MediaGateTestBox(MediaGateMutationControl(opcode: 1))
        let gate = MacRemoteMediaCommandGate(resultMutation: mediaGateMutation(control))
        _ = gate.open(); gate.setContexts(["source", "other"])
        let before = gate.snapshot
        control.update { $0.armed = true }
        gate.close()
        XCTAssertTrue(gate.snapshot.hasNativeFault)
        XCTAssertEqual(gate.snapshot.contextIDs, before.contextIDs)
        XCTAssertEqual(bytes(gate.snapshot.rawState), bytes(before.rawState))
        let calls = control.get().calls
        gate.close()
        XCTAssertTrue(gate.snapshot.contextIDs.isEmpty)
        XCTAssertEqual(bytes(gate.snapshot.rawState), bytes(before.rawState))
        XCTAssertEqual(control.get().calls, calls)
        gate.setContexts(["later"]); gate.close()
        XCTAssertTrue(gate.snapshot.contextIDs.isEmpty)
        XCTAssertTrue(gate.snapshot.hasNativeFault)
        XCTAssertEqual(control.get().calls, calls)
        let healthy = MacRemoteMediaCommandGate()
        _ = healthy.open(); healthy.setContext("source")
        healthy.close()
        XCTAssertFalse(healthy.snapshot.hasNativeFault)
        XCTAssertTrue(healthy.snapshot.contextIDs.isEmpty)
        XCTAssertEqual(healthy.snapshot.rawState.lifecycle, 2)
        XCTAssertEqual(healthy.snapshot.rawState.command_epoch, 2)
        XCTAssertEqual(healthy.snapshot.rawState.is_open, 0)
    }

    func testOrdinaryNativeRefusalAndUnchangedContextAssignmentsNeverFaultOrRotate() throws {
        let gate = MacRemoteMediaCommandGate()
        let closed = gate.snapshot
        gate.setContexts(["closed-context"])
        XCTAssertNil(gate.capture(contextID: "closed-context"))
        XCTAssertFalse(gate.snapshot.hasNativeFault)
        XCTAssertEqual(bytes(gate.snapshot.rawState), bytes(closed.rawState))
        let token = gate.open(); gate.setContexts(["source", "other"])
        let authorization = try XCTUnwrap(gate.capture(contextID: "source"))
        let before = gate.snapshot
        gate.setContexts(["other", "source"]); gate.setContext("source")
        XCTAssertEqual(bytes(gate.snapshot.rawState), bytes(before.rawState))
        XCTAssertTrue(gate.admits(authorization)); XCTAssertTrue(gate.lifecycleIsCurrent(token))
        XCTAssertNil(gate.capture(contextID: "missing"))
        gate.setContexts([])
        XCTAssertFalse(gate.admits(authorization))
        XCTAssertFalse(gate.snapshot.hasNativeFault)
        gate.setContext("source")
        XCTAssertTrue(gate.admits(authorization))
        XCTAssertEqual(bytes(gate.snapshot.rawState), bytes(before.rawState))
    }

    private func ordinarySnapshot() -> MacNowPlayingRuntimeSnapshot {
        MacNowPlayingRuntimeSnapshot(client: MacNowPlayingClientToken(object: NSObject(), clientIdentity: "synthetic:gate"),
            sourceName: "Synthetic", metadata: MacNowPlayingMetadata(title: "Synthetic source", artist: nil, album: nil,
                duration: 120, elapsedTime: 15, playbackRate: 1, timestamp: nil,
                contentIdentifier: "synthetic-item", uniqueIdentifier: nil), enabledCommands: [0, 1, 4, 5])
    }

    private func handoffSnapshot() async throws -> MacNowPlayingRuntimeSnapshot {
        let media = MacChromeScriptSnapshot(documentID: "00000000-0000-4000-8000-000000000001",
            itemID: "00000000-0000-4000-8000-000000000002", itemGeneration: 1,
            videoID: "abcdefghijk", title: "Synthetic handoff", artist: "Synthetic",
            duration: 120, elapsedTime: 15, playbackRate: 1, paused: false,
            observedAtUnixMilliseconds: 1_000_000, observedAtPageMilliseconds: 50_000,
            canPlay: false, canPause: true, canNext: true, canPrevious: true, canSeek: true,
            playbackContinuityID: "00000000-0000-4000-8000-000000000003")
        let player = MacChromePlayerSnapshot(tab: MacChromeTabIdentity(
            owner: MacChromePlayerIdentity(processID: 42, launchDate: Date(timeIntervalSince1970: 100)),
            windowID: "1", tabID: "2"), media: media, receivedAtUptime: 10)
        let runtime = MacChromeNowPlayingRuntime(backend: MediaGateFixtureChromeBackend(player: player), now: { 10 })
        defer { runtime.stop() }
        let value: MacNowPlayingRuntimeSnapshotResult = await withCheckedContinuation { continuation in
            runtime.fetchSnapshot { continuation.resume(returning: $0) }
        }
        guard case .snapshot(let result) = value else {
            XCTFail("Synthetic source construction failed")
            throw MacChromeBackendError.unavailable
        }
        XCTAssertNotNil(result.handoffSource)
        return result
    }

    private func publishedItem(_ controller: MacSystemNowPlayingController) async throws -> WebRTCRemoteMediaItem {
        let ready = expectation(description: "synthetic controller source published")
        let item = MediaGateTestBox<WebRTCRemoteMediaItem?>(nil)
        controller.start { update in
            if let value = update.item, item.get() == nil { item.set(value); ready.fulfill() }
        }
        await fulfillment(of: [ready], timeout: 3)
        return try XCTUnwrap(item.get())
    }

    func testControllerMalformedOpenCannotStartPollingOrGrantPreparedWork() async {
        let control = MediaGateTestBox(MediaGateMutationControl(armed: true, opcode: 0))
        let runtime = MediaGateHeldRuntime(ordinarySnapshot())
        let controller = MacSystemNowPlayingController(runtime: runtime, stateDiagnostics: { _ in },
            commandGateResultMutation: mediaGateMutation(control))
        let published = expectation(description: "faulted open never publishes")
        published.isInverted = true
        controller.start { _ in published.fulfill() }
        defer { controller.stop() }
        await fulfillment(of: [published], timeout: 0.2)
        XCTAssertEqual(runtime.snapshot.fetches, 0)
        XCTAssertTrue(controller.commandGateSnapshot.hasNativeFault)
        XCTAssertEqual(controller.commandGateSnapshot.rawState.lifecycle, 0)
        XCTAssertEqual(controller.commandGateSnapshot.rawState.command_epoch, 0)
        XCTAssertNil(controller.prepareCommand(.pause, contextID: "synthetic", isAuthorized: { true }))
        let calls = control.get().calls
        XCTAssertEqual(calls, [0])
        controller.refresh()
        XCTAssertEqual(control.get().calls, calls)
    }

    func testControllerMalformedCaptureCannotPrepareACommandOrHandoff() async throws {
        for handoff in [false, true] {
            let snapshot: MacNowPlayingRuntimeSnapshot
            if handoff { snapshot = try await handoffSnapshot() }
            else { snapshot = ordinarySnapshot() }
            let runtime = MediaGateHeldRuntime(snapshot)
            let control = MediaGateTestBox(MediaGateMutationControl(opcode: 4))
            let controller = MacSystemNowPlayingController(runtime: runtime, stateDiagnostics: { _ in },
                uptime: { 10 }, commandGateResultMutation: mediaGateMutation(control))
            defer { controller.stop() }
            let item = try await publishedItem(controller)
            if handoff {
                let healthy = await controller.prepareHandoff(contextID: item.contextID, isAuthorized: { true })
                XCTAssertNotNil(healthy)
            } else {
                XCTAssertNotNil(controller.prepareCommand(.pause, contextID: item.contextID, isAuthorized: { true }))
            }
            let before = controller.commandGateSnapshot
            control.update { $0.armed = true }
            if handoff {
                let rejected = await controller.prepareHandoff(contextID: item.contextID, isAuthorized: { true })
                XCTAssertNil(rejected)
            } else {
                XCTAssertNil(controller.prepareCommand(.pause, contextID: item.contextID, isAuthorized: { true }))
            }
            XCTAssertTrue(controller.commandGateSnapshot.hasNativeFault)
            XCTAssertEqual(bytes(controller.commandGateSnapshot.rawState), bytes(before.rawState))
            XCTAssertEqual(controller.commandGateSnapshot.contextIDs, before.contextIDs)
            XCTAssertEqual(runtime.snapshot.commandAttempts, 0)
            XCTAssertEqual(runtime.snapshot.pauseAttempts, 0)
        }
    }

    func testControllerMalformedQueuedOrFinalAdmissionCannotDispatchNativeCommand() async throws {
        for occurrence in [2, 3] {
            let admitted: XCTestExpectation? = occurrence == 3
                ? expectation(description: "synthetic command held after admission") : nil
            let runtime = MediaGateHeldRuntime(ordinarySnapshot(), admitted: { admitted?.fulfill() })
            let control = MediaGateTestBox(MediaGateMutationControl(opcode: 5, corruptOccurrence: occurrence))
            let controller = MacSystemNowPlayingController(runtime: runtime, stateDiagnostics: { _ in },
                commandGateResultMutation: mediaGateMutation(control))
            defer { controller.stop(); runtime.release() }
            let item = try await publishedItem(controller)
            let prepared = try XCTUnwrap(controller.prepareCommand(.pause, contextID: item.contextID, isAuthorized: { true }))
            let before = controller.commandGateSnapshot
            control.update { $0.armed = true }
            let task = Task { await controller.perform(prepared) }
            if let admitted {
                await fulfillment(of: [admitted], timeout: 3)
                runtime.release()
            }
            let result = await task.value
            XCTAssertEqual(result, .staleContext)
            XCTAssertEqual(runtime.snapshot.commandAttempts, occurrence == 2 ? 0 : 1)
            XCTAssertEqual(runtime.snapshot.commandEffects, 0)
            XCTAssertEqual(runtime.snapshot.pauseAttempts, 0)
            XCTAssertTrue(controller.commandGateSnapshot.hasNativeFault)
            XCTAssertEqual(bytes(controller.commandGateSnapshot.rawState), bytes(before.rawState))
            let calls = control.get().calls
            XCTAssertNil(controller.prepareCommand(.pause, contextID: item.contextID, isAuthorized: { true }))
            let copied = await controller.perform(prepared)
            XCTAssertEqual(copied, .staleContext)
            XCTAssertEqual(control.get().calls, calls)
        }
    }

    func testControllerMalformedQueuedOrFinalHandoffAdmissionCannotAttemptNativePause() async throws {
        for occurrence in [2, 3] {
            let admitted: XCTestExpectation? = occurrence == 3
                ? expectation(description: "synthetic handoff held after admission") : nil
            let runtime = MediaGateHeldRuntime(try await handoffSnapshot(), admitted: { admitted?.fulfill() })
            let control = MediaGateTestBox(MediaGateMutationControl(opcode: 5, corruptOccurrence: occurrence))
            let controller = MacSystemNowPlayingController(runtime: runtime, stateDiagnostics: { _ in },
                uptime: { 10 }, commandGateResultMutation: mediaGateMutation(control))
            defer { controller.stop(); runtime.release() }
            let item = try await publishedItem(controller)
            let preparedValue = await controller.prepareHandoff(contextID: item.contextID, isAuthorized: { true })
            let prepared = try XCTUnwrap(preparedValue)
            let before = controller.commandGateSnapshot
            control.update { $0.armed = true }
            let task = Task { await controller.performHandoffPause(prepared, phonePositionSeconds: 15) }
            if let admitted {
                await fulfillment(of: [admitted], timeout: 3)
                runtime.release()
            }
            let result = await task.value
            XCTAssertEqual(result, .staleContext)
            XCTAssertEqual(runtime.snapshot.pauseAttempts, occurrence == 2 ? 0 : 1)
            XCTAssertEqual(runtime.snapshot.pauseEffects, 0)
            XCTAssertEqual(runtime.snapshot.commandAttempts, 0)
            XCTAssertTrue(controller.commandGateSnapshot.hasNativeFault)
            XCTAssertEqual(bytes(controller.commandGateSnapshot.rawState), bytes(before.rawState))
            let calls = control.get().calls
            let rejected = await controller.prepareHandoff(contextID: item.contextID, isAuthorized: { true })
            XCTAssertNil(rejected)
            let copied = await controller.performHandoffPause(prepared, phonePositionSeconds: 15)
            XCTAssertEqual(copied, .staleContext)
            XCTAssertEqual(control.get().calls, calls)
        }
    }
}
