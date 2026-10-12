import BelugaCore
import Foundation
import WebRTCTransport
import XCTest
@testable import CaptureServer

private final class ScreenSuspensionTestBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func update(_ body: (inout Value) -> Void) { lock.withLock { body(&value) } }
}

private struct ScreenSuspensionMutationControl {
    var armed = false
    var opcode: UInt32 = 0
    var byte = 8
    var calls: [UInt32] = []
}

private func suspensionMutation(_ control: ScreenSuspensionTestBox<ScreenSuspensionMutationControl>)
    -> BelugaRustScreenSuspension.ResultMutation {
    { _, event, actual in
        var byte: Int?
        control.update {
            $0.calls.append(event.opcode)
            if $0.armed && $0.opcode == event.opcode { byte = $0.byte }
        }
        guard let byte else { return actual }
        var copied = actual
        withUnsafeMutableBytes(of: &copied) { $0[byte] ^= 1 }
        return copied
    }
}

/// No native service, viewer, capture, browser, phone, or audio effect is performed.
/// Every expected successor comes from the pre-Rust frozen native owner.
final class BelugaRustScreenSuspensionTranscriptTests: XCTestCase {
    private typealias State = beluga_core_screen_suspension_state_t
    private typealias Event = beluga_core_screen_suspension_event_t
    private typealias Result = beluga_core_screen_suspension_result_t
    private typealias Reference = FrozenScreenMediaSuspensionReference

    private struct Binding: Equatable {
        var peer: UInt64 = 3
        var visibility: UInt64 = 7
        var recovery: UInt64 = 11
        var reference: Reference.Binding {
            .init(peerGeneration: peer, visibilityCommandEpoch: visibility, recoveryEpoch: recovery)
        }
        var native: WorldwideScreenMediaSuspensionCoordinator.Binding {
            .init(peerGeneration: peer, visibilityCommandEpoch: visibility, recoveryEpoch: recovery)
        }
    }

    private enum Input {
        case projection
        case activate(UInt64, Binding)
        case retire
        case abort(Binding)
        case begin(Bool, Binding)
        case cover(WebRTCScreenMediaCoveredAcknowledgement, Binding)
        case inactive(WebRTCScreenMediaSuspensionNotice, Binding)
        case beginResume(UUID, Binding)
        case markerReady(WebRTCScreenMediaMarkerReady, Binding)
        case markerPresentation(WebRTCScreenMediaMarkerPresentation, Binding)
        case resumeReady(WebRTCScreenMediaResumeReady, Binding)
        case resumeRequest(WebRTCScreenMediaResumeRequest, Binding)
        case commit(WebRTCScreenMediaResumeRequest, Binding)
        case rollback(WebRTCScreenMediaSuspensionNotice, Binding)
        case cancel(Binding, Bool)
        case owns(Binding)
        case authorize(WebRTCScreenMediaResumeRequest, Binding)
        case binding(Binding)

        var opcode: UInt32 {
            switch self {
            case .projection: 0
            case .activate: 1
            case .retire: 2
            case .abort: 3
            case .begin: 4
            case .cover: 5
            case .inactive: 6
            case .beginResume: 7
            case .markerReady: 8
            case .markerPresentation: 9
            case .resumeReady: 10
            case .resumeRequest: 11
            case .commit: 12
            case .rollback: 13
            case .cancel: 14
            case .owns: 15
            case .authorize: 16
            case .binding: 17
            }
        }
    }

    private struct Payloads {
        var notice: WebRTCScreenMediaSuspensionNotice?
        var prior: WebRTCScreenMediaSuspensionNotice?
        var attempt: UUID?
        var markerReady: WebRTCScreenMediaMarkerReady?
        var markerPresentation: WebRTCScreenMediaMarkerPresentation?
        var resumeReady: WebRTCScreenMediaResumeReady?
        var request: WebRTCScreenMediaResumeRequest?
    }

    private struct Lifecycle {
        let notice: WebRTCScreenMediaSuspensionNotice
        let ready: WebRTCScreenMediaMarkerReady
        let marker: WebRTCScreenMediaMarkerPresentation
        let resume: WebRTCScreenMediaResumeReady
        let request: WebRTCScreenMediaResumeRequest
    }

    private let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    private let attempt = UUID(uuidString: "A1B2C3D4-E5F6-4718-89AB-CDEF01234567")!

    private func bytes<T>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value) { Array($0) }
    }

    private func initialState(next: UInt64 = 1) -> State {
        State(abi_version: 1, phase: 0, next_generation: next,
              screen_request_id: 0, suspension_generation: 0, peer_generation: 0,
              visibility_epoch: 0, recovery_epoch: 0, prior_screen_request_id: 0,
              prior_suspension_generation: 0, cover_confirmed: 0,
              inactive_confirmed: 0, custody_mask: 0, reserved: 0)
    }

    private func emptyEvent(_ opcode: UInt32) -> Event {
        Event(opcode: opcode, flags: 0, native_facts: 0, reserved: 0,
              screen_request_id: 0, peer_generation: 0, visibility_epoch: 0,
              recovery_epoch: 0, notice_screen_request_id: 0, notice_generation: 0)
    }

    /// This is serialization of the independent native snapshot, not a second reducer.
    private func raw(_ reference: Reference) -> (State, Payloads) {
        var state = initialState(next: reference.frozenSnapshot.nextSuspensionGeneration)
        var payload = Payloads()
        func bind(_ binding: Reference.Binding) {
            state.peer_generation = binding.peerGeneration
            state.visibility_epoch = binding.visibilityCommandEpoch
            state.recovery_epoch = binding.recoveryEpoch
        }
        func notice(_ value: WebRTCScreenMediaSuspensionNotice) {
            payload.notice = value
            state.screen_request_id = value.screenRequestID
            state.suspension_generation = value.suspensionGeneration
        }
        func resume(_ value: Reference.ResumeAttempt) {
            notice(value.notice); bind(value.binding); payload.attempt = value.attemptID
        }
        switch reference.frozenSnapshot.phase {
        case .idle: break
        case .active(let screen, let binding, let completed):
            state.phase = 1; state.screen_request_id = screen; bind(binding)
            if let completed { notice(completed); state.custody_mask = 1 }
        case .suspending(let value):
            state.phase = 2; notice(value.notice); bind(value.binding)
            state.cover_confirmed = value.coverWasConfirmed ? 1 : 0
            state.inactive_confirmed = value.inactiveWasConfirmed ? 1 : 0
            state.custody_mask = 1
            if let prior = value.priorResumedSuspension {
                payload.prior = prior; state.custody_mask = 3
                state.prior_screen_request_id = prior.screenRequestID
                state.prior_suspension_generation = prior.suspensionGeneration
            }
        case .suspended(let value, let binding):
            state.phase = 3; state.custody_mask = 1; notice(value); bind(binding)
        case .awaitingMarker(let value):
            state.phase = 4; state.custody_mask = 5; resume(value)
        case .awaitingMarkerPresentation(let value, let ready):
            state.phase = 5; state.custody_mask = 13; resume(value); payload.markerReady = ready
        case .awaitingRealFrame(let value, let presentation):
            state.phase = 6; state.custody_mask = 21; resume(value); payload.markerPresentation = presentation
        case .awaitingRealPresentation(let value, let ready):
            state.phase = 7; state.custody_mask = 37; resume(value); payload.resumeReady = ready
        case .awaitingFinalization(let value, let request):
            state.phase = 8; state.custody_mask = 69; resume(value); payload.request = request
        }
        return (state, payload)
    }

    private func event(_ input: Input, before: Reference) -> Event {
        var value = emptyEvent(input.opcode)
        let (_, held) = raw(before)
        func bind(_ binding: Binding) {
            value.peer_generation = binding.peer
            value.visibility_epoch = binding.visibility
            value.recovery_epoch = binding.recovery
        }
        func pair(_ screen: UInt64, _ generation: UInt64) {
            value.notice_screen_request_id = screen; value.notice_generation = generation
        }
        func fact(_ bit: UInt32, _ condition: Bool) {
            if condition { value.native_facts |= 1 << bit }
        }
        switch input {
        case .projection, .retire: break
        case .activate(let screen, let binding): value.screen_request_id = screen; bind(binding)
        case .abort(let binding), .owns(let binding), .binding(let binding): bind(binding)
        case .begin(let negotiated, let binding): bind(binding); value.flags = negotiated ? 1 : 0
        case .cover(let ack, let binding):
            bind(binding); pair(ack.suspension.screenRequestID, ack.suspension.suspensionGeneration)
            fact(1, held.notice.map { ack.isExactEcho(of: $0) } ?? false)
        case .inactive(let notice, let binding):
            bind(binding); pair(notice.screenRequestID, notice.suspensionGeneration)
            fact(0, held.notice == notice)
        case .beginResume(let id, let binding): bind(binding); fact(2, id != zeroUUID)
        case .markerReady(let ready, let binding):
            bind(binding); pair(ready.screenRequestID, ready.suspensionGeneration)
            fact(3, held.attempt == ready.attemptID)
            fact(4, held.notice.map { ready.belongs(to: $0) } ?? false)
        case .markerPresentation(let presentation, let binding):
            bind(binding); pair(presentation.markerReady.screenRequestID, presentation.markerReady.suspensionGeneration)
            fact(5, held.markerReady.map { presentation.isExactEcho(of: $0) } ?? false)
        case .resumeReady(let ready, let binding):
            bind(binding); pair(ready.screenRequestID, ready.suspensionGeneration)
            fact(3, held.attempt == ready.attemptID); fact(6, ready.isValid)
            fact(7, held.markerPresentation == ready.markerPresentation)
        case .resumeRequest(let request, let binding):
            bind(binding); pair(request.presentation.resumeReady.screenRequestID, request.presentation.resumeReady.suspensionGeneration)
            fact(3, held.attempt == request.presentation.resumeReady.attemptID)
            fact(8, request.isValid); fact(9, held.resumeReady == request.presentation.resumeReady)
        case .commit(let request, let binding):
            bind(binding); pair(request.presentation.resumeReady.screenRequestID, request.presentation.resumeReady.suspensionGeneration)
            fact(10, held.request == request)
        case .rollback(let notice, let binding):
            bind(binding); pair(notice.screenRequestID, notice.suspensionGeneration)
            fact(0, held.notice == notice); fact(11, notice.isValid)
        case .cancel(let binding, let logical): bind(binding); value.flags = logical ? 1 : 0
        case .authorize(let request, let binding):
            bind(binding); pair(request.presentation.resumeReady.screenRequestID, request.presentation.resumeReady.suspensionGeneration)
            fact(3, held.attempt == request.presentation.resumeReady.attemptID)
            fact(10, held.request == request)
        }
        return value
    }

    private func apply(_ input: Input, to reference: inout Reference) -> (Bool, UInt32, WebRTCScreenMediaSuspensionNotice?) {
        switch input {
        case .projection: return (true, 0, nil)
        case .activate(let screen, let binding):
            let accepted = reference.activate(screenRequestID: screen, binding: binding.reference)
            return (accepted, accepted ? 1 : 0, nil)
        case .retire: reference.retire(); return (true, 2, nil)
        case .abort(let binding):
            let accepted = reference.abortSuspensionBeforeInactive(binding: binding.reference)
            return (accepted, accepted ? 4 : 0, nil)
        case .begin(let negotiated, let binding):
            let notice = reference.beginSuspensionIfNegotiated(negotiated: negotiated, binding: binding.reference)
            return (notice != nil, notice != nil ? 3 : 0, notice)
        case .cover(let ack, let binding):
            let accepted = reference.confirmCover(ack, binding: binding.reference)
            return (accepted, accepted && reference.isAutomaticallySuspended ? 5 : 0, nil)
        case .inactive(let notice, let binding):
            let accepted = reference.confirmInactive(for: notice, binding: binding.reference)
            return (accepted, accepted && reference.isAutomaticallySuspended ? 5 : 0, nil)
        case .beginResume(let id, let binding):
            let accepted = reference.beginResumeAttempt(attemptID: id, binding: binding.reference)
            return (accepted, accepted ? 6 : 0, nil)
        case .markerReady(let ready, let binding):
            let accepted = reference.acceptMarkerReady(ready, binding: binding.reference)
            return (accepted, accepted ? 7 : 0, nil)
        case .markerPresentation(let presentation, let binding):
            let accepted = reference.acceptMarkerPresentation(presentation, binding: binding.reference)
            return (accepted, accepted ? 8 : 0, nil)
        case .resumeReady(let ready, let binding):
            let accepted = reference.acceptResumeReady(ready, binding: binding.reference)
            return (accepted, accepted ? 9 : 0, nil)
        case .resumeRequest(let request, let binding):
            let accepted = reference.acceptResumeRequest(request, binding: binding.reference)
            return (accepted, accepted ? 10 : 0, nil)
        case .commit(let request, let binding):
            let accepted = reference.commitFinalization(of: request, binding: binding.reference)
            return (accepted, accepted ? 11 : 0, nil)
        case .rollback(let notice, let binding):
            let accepted = reference.rollbackFinalizationBeforeAcknowledgement(notice: notice, binding: binding.reference)
            return (accepted, accepted ? 14 : 0, nil)
        case .cancel(let binding, let logical):
            let accepted = reference.currentSuspensionNotice != nil && reference.owns(binding.reference)
            reference.cancelResume(binding: binding.reference, logicalScreenIsStillRequested: logical)
            return (accepted, accepted ? (logical ? 12 : 13) : 0, nil)
        case .owns(let binding): return (reference.owns(binding.reference), 0, nil)
        case .authorize(let request, let binding): return (reference.authorizesFinalization(of: request, binding: binding.reference), 0, nil)
        case .binding(let binding): return (binding.reference.isValid, 0, nil)
        }
    }

    private func projection(_ reference: Reference) -> UInt32 {
        var result: UInt32 = 0
        let diagnostic = reference.diagnosticSnapshot
        let facts = [reference.isAutomaticallySuspended, reference.suspensionIsInFlight,
                     reference.isResumeProbeInFlight, reference.activeScreenRequestID != nil,
                     reference.currentSuspensionNotice != nil, diagnostic.suspensionGeneration != nil,
                     diagnostic.binding != nil, diagnostic.requiresFreshMediaSessionAfterInvalidation]
        for (index, fact) in facts.enumerated() where fact { result |= 1 << UInt32(index) }
        return result
    }

    /// Actual C producer FIRST; only then advance the independent frozen native reference.
    @discardableResult
    private func assertRawParity(_ input: Input, reference: inout Reference,
                                 file: StaticString = #filePath, line: UInt = #line) -> Result {
        let before = raw(reference).0
        let value = event(input, before: reference)
        let actual = beluga_core_screen_suspension_step(before, value)
        let (accepted, action, notice) = apply(input, to: &reference)
        let expected = Result(abi_version: 1, status: 1, accepted: accepted ? 1 : 0,
                              custody_action: action, state: raw(reference).0,
                              query_flags: projection(reference), reserved: 0,
                              produced_notice_screen_request_id: notice?.screenRequestID ?? 0,
                              produced_notice_generation: notice?.suspensionGeneration ?? 0)
        XCTAssertEqual(bytes(actual), bytes(expected), file: file, line: line)
        XCTAssertEqual(beluga_core_screen_suspension_result_is_valid(before, value, actual), 1, file: file, line: line)
        return actual
    }

    private func lifecycle(notice: WebRTCScreenMediaSuspensionNotice, receiver: String = "receiver-1",
                           attemptID: UUID? = nil, requestID: UInt64 = 55) -> Lifecycle {
        let geometry = WebRTCScreenMediaGeometry(geometryRevision: 23, captureWidth: 3_024, captureHeight: 1_964)
        let ready = WebRTCScreenMediaMarkerReady(attemptID: attemptID ?? attempt,
            screenRequestID: notice.screenRequestID, suspensionGeneration: notice.suspensionGeneration,
            encoderGeneration: 19, encoderMarkerRTPTimestamp: .max - 2,
            boundaryRevision: geometry.geometryRevision, geometry: geometry)
        let marker = WebRTCScreenMediaMarkerPresentation(markerReady: ready,
            receiverMarkerRTPTimestamp: 1_000, receiverID: receiver, sourceID: 77,
            presentedWidth: 1_280, presentedHeight: 832)
        let resume = WebRTCScreenMediaResumeReady(markerPresentation: marker,
            encoderMarkerRTPTimestamp: ready.encoderMarkerRTPTimestamp, encoderRealFrameRTPTimestamp: 5,
            receiverMarkerRTPTimestamp: marker.receiverMarkerRTPTimestamp,
            receiverRealFrameFloorRTPTimestamp: 1_008, geometry: geometry)
        let presentation = WebRTCScreenMediaPresentation(resumeReady: resume,
            presentedRTPTimestamp: resume.receiverRealFrameFloorRTPTimestamp, receiverID: receiver,
            sourceID: marker.sourceID, presentedWidth: marker.presentedWidth, presentedHeight: marker.presentedHeight)
        return Lifecycle(notice: notice, ready: ready, marker: marker, resume: resume,
            request: .init(id: requestID, presentation: presentation))
    }

    private func referencesByPhase(next: UInt64 = 1) -> [(Reference, Binding, Lifecycle)] {
        let active = Binding()
        let hidden = Binding(visibility: 8)
        let notice = WebRTCScreenMediaSuspensionNotice(screenRequestID: 42, suspensionGeneration: next)
        let life = lifecycle(notice: notice)
        var reference = Reference(nextSuspensionGeneration: next)
        var result: [(Reference, Binding, Lifecycle)] = [(reference, active, life)]
        assertRawParity(.activate(42, active), reference: &reference); result.append((reference, active, life))
        assertRawParity(.begin(true, active), reference: &reference); result.append((reference, active, life))
        assertRawParity(.cover(.init(suspension: notice), active), reference: &reference)
        assertRawParity(.inactive(notice, hidden), reference: &reference); result.append((reference, hidden, life))
        assertRawParity(.beginResume(attempt, hidden), reference: &reference); result.append((reference, hidden, life))
        assertRawParity(.markerReady(life.ready, hidden), reference: &reference); result.append((reference, hidden, life))
        assertRawParity(.markerPresentation(life.marker, hidden), reference: &reference); result.append((reference, hidden, life))
        assertRawParity(.resumeReady(life.resume, hidden), reference: &reference); result.append((reference, hidden, life))
        assertRawParity(.resumeRequest(life.request, hidden), reference: &reference); result.append((reference, hidden, life))
        return result
    }

    func testActualCLayoutsAndEveryThirtyThreeFieldOffsets() {
        XCTAssertEqual(MemoryLayout<State>.size, 88); XCTAssertEqual(MemoryLayout<State>.stride, 88)
        XCTAssertEqual(MemoryLayout<State>.alignment, 8)
        XCTAssertEqual(MemoryLayout<Event>.size, 64); XCTAssertEqual(MemoryLayout<Event>.stride, 64)
        XCTAssertEqual(MemoryLayout<Event>.alignment, 8)
        XCTAssertEqual(MemoryLayout<Result>.size, 128); XCTAssertEqual(MemoryLayout<Result>.stride, 128)
        XCTAssertEqual(MemoryLayout<Result>.alignment, 8)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.abi_version), 0)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.phase), 4)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.next_generation), 8)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.screen_request_id), 16)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.suspension_generation), 24)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.peer_generation), 32)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.visibility_epoch), 40)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.recovery_epoch), 48)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.prior_screen_request_id), 56)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.prior_suspension_generation), 64)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.cover_confirmed), 72)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.inactive_confirmed), 76)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.custody_mask), 80)
        XCTAssertEqual(MemoryLayout<State>.offset(of: \.reserved), 84)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.opcode), 0)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.flags), 4)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.native_facts), 8)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.reserved), 12)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.screen_request_id), 16)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.peer_generation), 24)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.visibility_epoch), 32)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.recovery_epoch), 40)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.notice_screen_request_id), 48)
        XCTAssertEqual(MemoryLayout<Event>.offset(of: \.notice_generation), 56)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.abi_version), 0)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.status), 4)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.accepted), 8)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.custody_action), 12)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.state), 16)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.query_flags), 104)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.reserved), 108)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.produced_notice_screen_request_id), 112)
        XCTAssertEqual(MemoryLayout<Result>.offset(of: \.produced_notice_generation), 120)
        XCTAssertTrue(BelugaRustScreenSuspension.layoutIsExact)
    }

    func testActualCCompleteNinePhaseTranscriptAndProjection() {
        let phases = referencesByPhase()
        XCTAssertEqual(phases.count, 9)
        for (var reference, binding, _) in phases {
            let predecessor = reference.frozenSnapshot
            assertRawParity(.projection, reference: &reference)
            assertRawParity(.owns(binding), reference: &reference)
            XCTAssertEqual(reference.frozenSnapshot, predecessor)
        }
        var (reference, binding, life) = phases[8]
        assertRawParity(.authorize(life.request, binding), reference: &reference)
        assertRawParity(.commit(life.request, binding), reference: &reference)
        XCTAssertEqual(reference.currentSuspensionNotice, life.notice)
        XCTAssertTrue(reference.diagnosticSnapshot.requiresFreshMediaSessionAfterInvalidation)
        assertRawParity(.rollback(life.notice, binding), reference: &reference)
        XCTAssertTrue(reference.isAutomaticallySuspended)
    }

    func testActualCBothConfirmationOrdersSameEpochAndRebinding() {
        for coverFirst in [false, true] {
            for visibility in [UInt64(7), 8, .max] {
                let active = Binding()
                let hidden = Binding(visibility: visibility)
                var reference = Reference()
                assertRawParity(.activate(42, active), reference: &reference)
                let notice = assertRawParity(.begin(true, active), reference: &reference)
                let value = WebRTCScreenMediaSuspensionNotice(screenRequestID: notice.produced_notice_screen_request_id,
                    suspensionGeneration: notice.produced_notice_generation)
                let cover = WebRTCScreenMediaCoveredAcknowledgement(suspension: value)
                if coverFirst { assertRawParity(.cover(cover, active), reference: &reference) }
                assertRawParity(.inactive(value, hidden), reference: &reference)
                if !coverFirst {
                    if active != hidden {
                        let denied = assertRawParity(.cover(cover, active), reference: &reference)
                        XCTAssertEqual(denied.accepted, 0)
                    }
                    assertRawParity(.cover(cover, hidden), reference: &reference)
                }
                XCTAssertTrue(reference.isAutomaticallySuspended)
                XCTAssertTrue(reference.owns(hidden.reference))
                XCTAssertEqual(assertRawParity(.cover(cover, hidden), reference: &reference).accepted, 0)
                XCTAssertEqual(assertRawParity(.inactive(value, hidden), reference: &reference).accepted, 0)
            }
        }
    }

    func testActualCUnnegotiatedAndInvalidBindingsPreserveWholeState() {
        var reference = Reference(nextSuspensionGeneration: .max)
        let binding = Binding(recovery: 0)
        assertRawParity(.activate(42, binding), reference: &reference)
        let before = reference.frozenSnapshot
        for input in [Input.begin(false, binding), .begin(true, Binding(peer: 0)),
                      .begin(true, Binding(visibility: 0)), .begin(true, Binding(recovery: 1)),
                      .activate(0, binding), .activate(42, Binding(peer: 0)),
                      .activate(42, Binding(visibility: 0))] {
            XCTAssertEqual(assertRawParity(input, reference: &reference).accepted, 0)
            XCTAssertEqual(reference.frozenSnapshot, before)
        }
        for value in [Binding(recovery: 0), Binding(peer: .max, visibility: .max, recovery: .max),
                      Binding(peer: 0), Binding(visibility: 0)] {
            assertRawParity(.binding(value), reference: &reference)
        }
        XCTAssertEqual(reference.frozenSnapshot, before)
    }

    func testActualCStaleBindingRefusalMatrixAcrossEveryPhase() {
        for (baseline, binding, life) in referencesByPhase() {
            let stale = Binding(peer: binding.peer, visibility: binding.visibility, recovery: binding.recovery &+ 1)
            let inputs: [Input] = [.abort(stale), .begin(true, stale),
                .cover(.init(suspension: life.notice), stale), .inactive(life.notice, stale),
                .beginResume(attempt, stale), .markerReady(life.ready, stale),
                .markerPresentation(life.marker, stale), .resumeReady(life.resume, stale),
                .resumeRequest(life.request, stale), .commit(life.request, stale),
                .rollback(life.notice, stale), .cancel(stale, true), .cancel(stale, false),
                .owns(stale), .authorize(life.request, stale)]
            for input in inputs {
                var reference = baseline
                XCTAssertEqual(assertRawParity(input, reference: &reference).accepted, 0)
                XCTAssertEqual(reference.frozenSnapshot, baseline.frozenSnapshot)
            }
        }
    }

    private func conditionalInputs(binding: Binding, life: Lifecycle) -> [Input] {
        [.abort(binding), .begin(true, binding), .cover(.init(suspension: life.notice), binding),
         .inactive(life.notice, binding), .beginResume(attempt, binding),
         .markerReady(life.ready, binding), .markerPresentation(life.marker, binding),
         .resumeReady(life.resume, binding), .resumeRequest(life.request, binding),
         .commit(life.request, binding), .rollback(life.notice, binding),
         .cancel(binding, true), .cancel(binding, false), .owns(binding),
         .authorize(life.request, binding)]
    }

    func testActualCWholePhaseEventAdmissionAndRefusalMatrix() {
        var phases = referencesByPhase()
        var (completed, binding, life) = phases[8]
        assertRawParity(.commit(life.request, binding), reference: &completed)
        phases.append((completed, binding, life))
        for (baseline, binding, life) in phases {
            for input in conditionalInputs(binding: binding, life: life) {
                var reference = baseline
                let actual = assertRawParity(input, reference: &reference)
                if actual.accepted == 0 {
                    XCTAssertEqual(reference.frozenSnapshot, baseline.frozenSnapshot)
                    XCTAssertEqual(bytes(actual.state), bytes(raw(baseline).0))
                    XCTAssertEqual(actual.custody_action, 0)
                }
            }
        }
    }

    func testActualCGenerationWrapAndRetireActivateNeverRewind() {
        let binding = Binding(peer: .max, visibility: .max, recovery: 0)
        var reference = Reference(nextSuspensionGeneration: .max)
        assertRawParity(.activate(.max, binding), reference: &reference)
        let first = assertRawParity(.begin(true, binding), reference: &reference)
        XCTAssertEqual(first.produced_notice_generation, .max)
        XCTAssertEqual(first.state.next_generation, 1)
        assertRawParity(.abort(binding), reference: &reference)
        assertRawParity(.retire, reference: &reference)
        assertRawParity(.activate(.max, binding), reference: &reference)
        let second = assertRawParity(.begin(true, binding), reference: &reference)
        XCTAssertEqual(second.produced_notice_generation, 1)
        XCTAssertEqual(second.state.next_generation, 2)
        assertRawParity(.retire, reference: &reference)
        assertRawParity(.retire, reference: &reference)
        XCTAssertEqual(reference.frozenSnapshot.nextSuspensionGeneration, 2)
    }

    func testActualCAbortRestoresPriorCompletedProvenanceWithOrWithoutCover() {
        for cover in [false, true] {
            var (reference, binding, life) = referencesByPhase()[8]
            assertRawParity(.commit(life.request, binding), reference: &reference)
            let began = assertRawParity(.begin(true, binding), reference: &reference)
            let nextNotice = WebRTCScreenMediaSuspensionNotice(screenRequestID: began.produced_notice_screen_request_id,
                suspensionGeneration: began.produced_notice_generation)
            if cover { assertRawParity(.cover(.init(suspension: nextNotice), binding), reference: &reference) }
            assertRawParity(.abort(binding), reference: &reference)
            XCTAssertEqual(reference.currentSuspensionNotice, life.notice)
            XCTAssertTrue(reference.diagnosticSnapshot.requiresFreshMediaSessionAfterInvalidation)
            XCTAssertEqual(reference.frozenSnapshot.nextSuspensionGeneration, 3)
        }
        var reference = Reference()
        let binding = Binding()
        assertRawParity(.activate(42, binding), reference: &reference)
        let began = assertRawParity(.begin(true, binding), reference: &reference)
        let notice = WebRTCScreenMediaSuspensionNotice(screenRequestID: began.produced_notice_screen_request_id,
            suspensionGeneration: began.produced_notice_generation)
        assertRawParity(.inactive(notice, binding), reference: &reference)
        XCTAssertEqual(assertRawParity(.abort(binding), reference: &reference).accepted, 0)
    }

    func testActualCCancelAllOwnedPhasesButNeverOrdinaryActive() {
        var phases = referencesByPhase()
        var (completed, binding, life) = phases[8]
        assertRawParity(.commit(life.request, binding), reference: &completed)
        phases.append((completed, binding, life))
        for (baseline, binding, life) in phases {
            for logical in [false, true] {
                var reference = baseline
                let hadOwnership = reference.currentSuspensionNotice != nil
                let actual = assertRawParity(.cancel(binding, logical), reference: &reference)
                XCTAssertEqual(actual.accepted, hadOwnership ? 1 : 0)
                if hadOwnership && logical {
                    XCTAssertEqual(reference.currentSuspensionNotice, life.notice)
                    XCTAssertTrue(reference.isAutomaticallySuspended)
                } else if hadOwnership {
                    XCTAssertNil(reference.activeScreenRequestID)
                } else {
                    XCTAssertEqual(reference.frozenSnapshot, baseline.frozenSnapshot)
                }
                XCTAssertEqual(reference.frozenSnapshot.nextSuspensionGeneration,
                               baseline.frozenSnapshot.nextSuspensionGeneration)
            }
        }
    }

    func testActualCReplacementShowProtectsAgainstStaleCleanupAndRollback() {
        var (reference, old, life) = referencesByPhase()[8]
        assertRawParity(.commit(life.request, old), reference: &reference)
        let current = Binding(visibility: old.visibility &+ 1)
        assertRawParity(.activate(84, current), reference: &reference)
        let replacement = reference.frozenSnapshot
        for input in [Input.rollback(life.notice, old), .rollback(life.notice, current),
                      .cancel(old, true), .cancel(old, false), .cancel(current, false)] {
            XCTAssertEqual(assertRawParity(input, reference: &reference).accepted, 0)
            XCTAssertEqual(reference.frozenSnapshot, replacement)
        }
    }

    func testActualCVerifierRejectsEveryOneHundredTwentyEightCopiedResultBytes() {
        for (reference, binding, life) in referencesByPhase() {
            let before = raw(reference).0
            let input: Input = before.phase == 8 ? .authorize(life.request, binding) : .projection
            let value = event(input, before: reference)
            let actual = beluga_core_screen_suspension_step(before, value)
            XCTAssertEqual(beluga_core_screen_suspension_result_is_valid(before, value, actual), 1)
            for byte in 0..<128 {
                var copied = actual
                withUnsafeMutableBytes(of: &copied) { $0[byte] ^= 1 }
                XCTAssertEqual(beluga_core_screen_suspension_result_is_valid(before, value, copied), 0,
                               "phase=\(before.phase), corruptedByte=\(byte)")
            }
        }
    }

    private func assertDenied(_ before: State, _ value: Event,
                              file: StaticString = #filePath, line: UInt = #line) {
        let actual = beluga_core_screen_suspension_step(before, value)
        let expected = Result(abi_version: 1, status: 0, accepted: 0, custody_action: 0,
                              state: initialState(), query_flags: 0, reserved: 0,
                              produced_notice_screen_request_id: 0, produced_notice_generation: 0)
        XCTAssertEqual(bytes(actual), bytes(expected), file: file, line: line)
        XCTAssertEqual(beluga_core_screen_suspension_result_is_valid(before, value, actual), 0,
                       file: file, line: line)
    }

    func testActualCMalformedStateAndUnusedEventFieldsAreCanonicalDenials() {
        for (reference, binding, life) in referencesByPhase() {
            let before = raw(reference).0
            let value = event(.projection, before: reference)
            var malformed = before; malformed.abi_version = 0; assertDenied(malformed, value)
            malformed = before; malformed.reserved = 1; assertDenied(malformed, value)
            malformed = before; malformed.phase = 9; assertDenied(malformed, value)
            malformed = before; malformed.next_generation = 0; assertDenied(malformed, value)
            malformed = before; malformed.custody_mask |= 128; assertDenied(malformed, value)
            malformed = before; malformed.cover_confirmed = 2; assertDenied(malformed, value)
            malformed = before; malformed.inactive_confirmed = 2; assertDenied(malformed, value)
            var badEvent = value; badEvent.opcode = 18; assertDenied(before, badEvent)
            badEvent = value; badEvent.flags = 1; assertDenied(before, badEvent)
            badEvent = value; badEvent.native_facts = 1; assertDenied(before, badEvent)
            badEvent = value; badEvent.reserved = 1; assertDenied(before, badEvent)
            badEvent = value; badEvent.screen_request_id = 1; assertDenied(before, badEvent)
            badEvent = value; badEvent.peer_generation = 1; assertDenied(before, badEvent)
            badEvent = value; badEvent.visibility_epoch = 1; assertDenied(before, badEvent)
            badEvent = value; badEvent.recovery_epoch = 1; assertDenied(before, badEvent)
            badEvent = value; badEvent.notice_screen_request_id = 1; assertDenied(before, badEvent)
            badEvent = value; badEvent.notice_generation = 1; assertDenied(before, badEvent)
            for opcode in UInt32(0)..<18 {
                var input = emptyEvent(opcode)
                input.native_facts = 1 << 12; assertDenied(before, input)
                input = emptyEvent(opcode); input.flags = 2; assertDenied(before, input)
            }
            _ = binding; _ = life
        }
    }

    private func apply(_ input: Input, to owner: inout WorldwideScreenMediaSuspensionCoordinator)
        -> (Bool?, WebRTCScreenMediaSuspensionNotice?) {
        switch input {
        case .projection: return (nil, nil)
        case .activate(let screen, let binding): return (owner.activate(screenRequestID: screen, binding: binding.native), nil)
        case .retire: owner.retire(); return (nil, nil)
        case .abort(let binding): return (owner.abortSuspensionBeforeInactive(binding: binding.native), nil)
        case .begin(let negotiated, let binding):
            let notice = owner.beginSuspensionIfNegotiated(negotiated: negotiated, binding: binding.native)
            return (notice != nil, notice)
        case .cover(let ack, let binding): return (owner.confirmCover(ack, binding: binding.native), nil)
        case .inactive(let notice, let binding): return (owner.confirmInactive(for: notice, binding: binding.native), nil)
        case .beginResume(let id, let binding): return (owner.beginResumeAttempt(attemptID: id, binding: binding.native), nil)
        case .markerReady(let ready, let binding): return (owner.acceptMarkerReady(ready, binding: binding.native), nil)
        case .markerPresentation(let presentation, let binding): return (owner.acceptMarkerPresentation(presentation, binding: binding.native), nil)
        case .resumeReady(let ready, let binding): return (owner.acceptResumeReady(ready, binding: binding.native), nil)
        case .resumeRequest(let request, let binding): return (owner.acceptResumeRequest(request, binding: binding.native), nil)
        case .commit(let request, let binding): return (owner.commitFinalization(of: request, binding: binding.native), nil)
        case .rollback(let notice, let binding): return (owner.rollbackFinalizationBeforeAcknowledgement(notice: notice, binding: binding.native), nil)
        case .cancel(let binding, let logical): owner.cancelResume(binding: binding.native, logicalScreenIsStillRequested: logical); return (nil, nil)
        case .owns(let binding): return (owner.owns(binding.native), nil)
        case .authorize(let request, let binding): return (owner.authorizesFinalization(of: request, binding: binding.native), nil)
        case .binding(let binding): return (binding.native.isValid, nil)
        }
    }

    private func assertSnapshot(_ owner: WorldwideScreenMediaSuspensionCoordinator, matches reference: Reference,
                                file: StaticString = #filePath, line: UInt = #line) {
        let snapshot = owner.snapshot
        let (expected, held) = raw(reference)
        XCTAssertEqual(bytes(snapshot.rawState), bytes(expected), file: file, line: line)
        XCTAssertEqual(snapshot.queryFlags, projection(reference), file: file, line: line)
        XCTAssertFalse(snapshot.hasNativeFault, file: file, line: line)
        XCTAssertFalse(owner.hasNativeFault, file: file, line: line)
        XCTAssertEqual(snapshot.custody.currentNotice, held.notice, file: file, line: line)
        XCTAssertEqual(snapshot.custody.priorResumedNotice, held.prior, file: file, line: line)
        XCTAssertEqual(snapshot.custody.attemptID, held.attempt, file: file, line: line)
        XCTAssertEqual(snapshot.custody.markerReady, held.markerReady, file: file, line: line)
        XCTAssertEqual(snapshot.custody.markerPresentation, held.markerPresentation, file: file, line: line)
        XCTAssertEqual(snapshot.custody.resumeReady, held.resumeReady, file: file, line: line)
        XCTAssertEqual(snapshot.custody.resumeRequest, held.request, file: file, line: line)
        XCTAssertTrue(WorldwideScreenMediaSuspensionCoordinator.custodyIsConsistent(snapshot.custody,
            with: snapshot.rawState), file: file, line: line)
        XCTAssertEqual(owner.isAutomaticallySuspended, reference.isAutomaticallySuspended, file: file, line: line)
        XCTAssertEqual(owner.suspensionIsInFlight, reference.suspensionIsInFlight, file: file, line: line)
        XCTAssertEqual(owner.isResumeProbeInFlight, reference.isResumeProbeInFlight, file: file, line: line)
        XCTAssertEqual(owner.activeScreenRequestID, reference.activeScreenRequestID, file: file, line: line)
        XCTAssertEqual(owner.currentSuspensionNotice, reference.currentSuspensionNotice, file: file, line: line)
        XCTAssertEqual(owner.diagnosticSnapshot.phase.rawValue, reference.diagnosticSnapshot.phase.rawValue,
                       file: file, line: line)
        XCTAssertEqual(owner.diagnosticSnapshot.screenRequestID, reference.diagnosticSnapshot.screenRequestID,
                       file: file, line: line)
        XCTAssertEqual(owner.diagnosticSnapshot.suspensionGeneration, reference.diagnosticSnapshot.suspensionGeneration,
                       file: file, line: line)
        XCTAssertEqual(owner.diagnosticSnapshot.binding?.peerGeneration, reference.diagnosticSnapshot.binding?.peerGeneration,
                       file: file, line: line)
        XCTAssertEqual(owner.diagnosticSnapshot.binding?.visibilityCommandEpoch,
                       reference.diagnosticSnapshot.binding?.visibilityCommandEpoch, file: file, line: line)
        XCTAssertEqual(owner.diagnosticSnapshot.binding?.recoveryEpoch, reference.diagnosticSnapshot.binding?.recoveryEpoch,
                       file: file, line: line)
        XCTAssertEqual(owner.diagnosticSnapshot.requiresFreshMediaSessionAfterInvalidation,
                       reference.diagnosticSnapshot.requiresFreshMediaSessionAfterInvalidation, file: file, line: line)
    }

    /// Raw actual C precedes both the production facade and native-reference expectation.
    @discardableResult
    private func assertNativeParity(_ input: Input, owner: inout WorldwideScreenMediaSuspensionCoordinator,
                                    reference: inout Reference, file: StaticString = #filePath,
                                    line: UInt = #line) -> Result {
        let before = raw(reference).0
        let value = event(input, before: reference)
        let rawActual = beluga_core_screen_suspension_step(before, value)
        let outcome = apply(input, to: &owner)
        let (accepted, action, notice) = apply(input, to: &reference)
        let expected = Result(abi_version: 1, status: 1, accepted: accepted ? 1 : 0,
            custody_action: action, state: raw(reference).0, query_flags: projection(reference), reserved: 0,
            produced_notice_screen_request_id: notice?.screenRequestID ?? 0,
            produced_notice_generation: notice?.suspensionGeneration ?? 0)
        XCTAssertEqual(bytes(rawActual), bytes(expected), file: file, line: line)
        XCTAssertEqual(beluga_core_screen_suspension_result_is_valid(before, value, rawActual), 1,
                       file: file, line: line)
        if let actualAccepted = outcome.0 { XCTAssertEqual(actualAccepted, accepted, file: file, line: line) }
        XCTAssertEqual(outcome.1, notice, file: file, line: line)
        assertSnapshot(owner, matches: reference, file: file, line: line)
        return rawActual
    }

    private struct NativePhase {
        var owner: WorldwideScreenMediaSuspensionCoordinator
        var reference: Reference
        let binding: Binding
        let life: Lifecycle
    }

    private func nativePhases(mutation: BelugaRustScreenSuspension.ResultMutation? = nil) -> [NativePhase] {
        let active = Binding()
        let hidden = Binding(visibility: 8)
        let life = lifecycle(notice: .init(screenRequestID: 42, suspensionGeneration: 1))
        var owner = WorldwideScreenMediaSuspensionCoordinator(resultMutation: mutation)
        var reference = Reference()
        assertSnapshot(owner, matches: reference)
        var result = [NativePhase(owner: owner, reference: reference, binding: active, life: life)]
        let steps: [(Input, Binding)] = [(.activate(42, active), active), (.begin(true, active), active),
            (.cover(.init(suspension: life.notice), active), active), (.inactive(life.notice, hidden), hidden),
            (.beginResume(attempt, hidden), hidden), (.markerReady(life.ready, hidden), hidden),
            (.markerPresentation(life.marker, hidden), hidden), (.resumeReady(life.resume, hidden), hidden),
            (.resumeRequest(life.request, hidden), hidden)]
        for (input, binding) in steps {
            assertNativeParity(input, owner: &owner, reference: &reference)
            if input.opcode != 5 { result.append(.init(owner: owner, reference: reference, binding: binding, life: life)) }
        }
        return result
    }

    func testNativeWholeTranscriptAndDeepCustodyMatchFrozenReference() {
        var phases = nativePhases()
        XCTAssertEqual(phases.count, 9)
        for var value in phases {
            let baseline = value.owner.snapshot
            assertNativeParity(.projection, owner: &value.owner, reference: &value.reference)
            assertNativeParity(.owns(value.binding), owner: &value.owner, reference: &value.reference)
            XCTAssertEqual(value.owner.snapshot, baseline)
        }
        var final = phases.removeLast()
        assertNativeParity(.authorize(final.life.request, final.binding), owner: &final.owner, reference: &final.reference)
        assertNativeParity(.commit(final.life.request, final.binding), owner: &final.owner, reference: &final.reference)
        XCTAssertEqual(final.owner.currentSuspensionNotice, final.life.notice)
        XCTAssertTrue(final.owner.diagnosticSnapshot.requiresFreshMediaSessionAfterInvalidation)
        assertNativeParity(.rollback(final.life.notice, final.binding), owner: &final.owner, reference: &final.reference)
    }

    func testNativePhaseEventRefusalAndFullWidthBindingsMatchFrozenReference() {
        for baseline in nativePhases() {
            for stale in [Binding(peer: baseline.binding.peer &+ 1, visibility: baseline.binding.visibility,
                                 recovery: baseline.binding.recovery),
                          Binding(peer: baseline.binding.peer, visibility: baseline.binding.visibility &+ 1,
                                  recovery: baseline.binding.recovery &+ 1),
                          Binding(peer: 0, visibility: 0, recovery: 0)] {
                let life = baseline.life
                let inputs: [Input] = [.abort(stale), .begin(true, stale), .cover(.init(suspension: life.notice), stale),
                    .inactive(life.notice, stale), .beginResume(attempt, stale), .markerReady(life.ready, stale),
                    .markerPresentation(life.marker, stale), .resumeReady(life.resume, stale),
                    .resumeRequest(life.request, stale), .commit(life.request, stale), .rollback(life.notice, stale),
                    .cancel(stale, true), .cancel(stale, false), .owns(stale), .authorize(life.request, stale)]
                for input in inputs {
                    var value = baseline
                    XCTAssertEqual(assertNativeParity(input, owner: &value.owner, reference: &value.reference).accepted, 0)
                    XCTAssertEqual(value.owner, baseline.owner)
                }
            }
        }
        var owner = WorldwideScreenMediaSuspensionCoordinator()
        var reference = Reference()
        let full = Binding(peer: .max, visibility: .max, recovery: 0)
        assertNativeParity(.activate(.max, full), owner: &owner, reference: &reference)
        assertNativeParity(.begin(true, full), owner: &owner, reference: &reference)
        let notice = WebRTCScreenMediaSuspensionNotice(screenRequestID: .max, suspensionGeneration: 1)
        assertNativeParity(.inactive(notice, full), owner: &owner, reference: &reference)
        assertNativeParity(.cover(.init(suspension: notice), full), owner: &owner, reference: &reference)
        assertNativeParity(.retire, owner: &owner, reference: &reference)
        assertNativeParity(.activate(.max, full), owner: &owner, reference: &reference)
        XCTAssertEqual(owner.snapshot.rawState.next_generation, 2)
    }

    func testNativeWholePhaseEventAdmissionAndRefusalMatrix() {
        var phases = nativePhases()
        var completed = phases[8]
        assertNativeParity(.commit(completed.life.request, completed.binding),
                           owner: &completed.owner, reference: &completed.reference)
        phases.append(completed)
        for baseline in phases {
            for input in conditionalInputs(binding: baseline.binding, life: baseline.life) {
                var value = baseline
                let actual = assertNativeParity(input, owner: &value.owner, reference: &value.reference)
                if actual.accepted == 0 {
                    XCTAssertEqual(value.owner, baseline.owner)
                    XCTAssertEqual(value.reference.frozenSnapshot, baseline.reference.frozenSnapshot)
                }
            }
        }
    }

    func testNativeFixedSeededChurnUsesFrozenExpectationsWithoutNativeEffects() {
        for seed in [UInt64(1), 0x1234_5678_ABCD_EF01, .max] {
            var random = seed
            var owner = WorldwideScreenMediaSuspensionCoordinator()
            var reference = Reference()
            for index in 0..<512 {
                random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let diagnostic = reference.diagnosticSnapshot
                let current = Binding(peer: diagnostic.binding?.peerGeneration ?? 3,
                    visibility: diagnostic.binding?.visibilityCommandEpoch ?? 7,
                    recovery: diagnostic.binding?.recoveryEpoch ?? 0)
                let binding = random & 0x100 == 0 ? current : Binding(peer: current.peer,
                    visibility: current.visibility, recovery: current.recovery &+ 1)
                let notice = reference.currentSuspensionNotice
                    ?? WebRTCScreenMediaSuspensionNotice(screenRequestID: 42, suspensionGeneration: 1)
                let life = lifecycle(notice: notice)
                let input: Input
                switch random % 18 {
                case 0: input = .projection
                case 1: input = .activate(index & 1 == 0 ? 42 : 84, binding)
                case 2: input = .retire
                case 3: input = .abort(binding)
                case 4: input = .begin(random & 0x200 != 0, binding)
                case 5: input = .cover(.init(suspension: notice), binding)
                case 6: input = .inactive(notice, binding)
                case 7: input = .beginResume(random & 0x400 == 0 ? attempt : zeroUUID, binding)
                case 8: input = .markerReady(life.ready, binding)
                case 9: input = .markerPresentation(life.marker, binding)
                case 10: input = .resumeReady(life.resume, binding)
                case 11: input = .resumeRequest(life.request, binding)
                case 12: input = .commit(life.request, binding)
                case 13: input = .rollback(notice, binding)
                case 14: input = .cancel(binding, random & 0x800 != 0)
                case 15: input = .owns(binding)
                case 16: input = .authorize(life.request, binding)
                default: input = .binding(binding)
                }
                assertNativeParity(input, owner: &owner, reference: &reference)
            }
        }
    }

    func testNativeBothJoinOrdersPublishPartialNoneActionAndReboundBinding() {
        for coverFirst in [false, true] {
            for visibility in [UInt64(7), 8, .max] {
                let active = Binding()
                let hidden = Binding(visibility: visibility)
                var owner = WorldwideScreenMediaSuspensionCoordinator()
                var reference = Reference()
                assertNativeParity(.activate(42, active), owner: &owner, reference: &reference)
                let began = assertNativeParity(.begin(true, active), owner: &owner, reference: &reference)
                let notice = WebRTCScreenMediaSuspensionNotice(screenRequestID: began.produced_notice_screen_request_id,
                    suspensionGeneration: began.produced_notice_generation)
                let beforeOlderInactive = owner.snapshot
                let olderVisibility = Binding(peer: active.peer, visibility: active.visibility - 1,
                                              recovery: active.recovery)
                XCTAssertEqual(assertNativeParity(.inactive(notice, olderVisibility),
                    owner: &owner, reference: &reference).accepted, 0)
                XCTAssertEqual(owner.snapshot, beforeOlderInactive)
                if coverFirst {
                    let partial = assertNativeParity(.cover(.init(suspension: notice), active), owner: &owner, reference: &reference)
                    XCTAssertEqual(partial.custody_action, 0); XCTAssertEqual(owner.snapshot.rawState.cover_confirmed, 1)
                }
                let inactive = assertNativeParity(.inactive(notice, hidden), owner: &owner, reference: &reference)
                if !coverFirst {
                    XCTAssertEqual(inactive.custody_action, 0)
                    XCTAssertEqual(owner.snapshot.rawState.inactive_confirmed, 1)
                    XCTAssertEqual(owner.snapshot.rawState.visibility_epoch, visibility)
                    if active != hidden {
                        XCTAssertEqual(assertNativeParity(.cover(.init(suspension: notice), active),
                            owner: &owner, reference: &reference).accepted, 0)
                    }
                    assertNativeParity(.cover(.init(suspension: notice), hidden), owner: &owner, reference: &reference)
                }
                XCTAssertTrue(owner.isAutomaticallySuspended)
            }
        }
    }

    func testNativeProvenanceAbortCancelRollbackAndReplacementIsolation() {
        for coverFirst in [false, true] {
            var value = nativePhases()[8]
            assertNativeParity(.commit(value.life.request, value.binding), owner: &value.owner, reference: &value.reference)
            let completed = value.owner
            let began = assertNativeParity(.begin(true, value.binding), owner: &value.owner, reference: &value.reference)
            let next = WebRTCScreenMediaSuspensionNotice(screenRequestID: began.produced_notice_screen_request_id,
                suspensionGeneration: began.produced_notice_generation)
            if coverFirst { assertNativeParity(.cover(.init(suspension: next), value.binding), owner: &value.owner, reference: &value.reference) }
            assertNativeParity(.abort(value.binding), owner: &value.owner, reference: &value.reference)
            XCTAssertEqual(value.owner.currentSuspensionNotice, completed.currentSuspensionNotice)
            assertNativeParity(.cancel(value.binding, true), owner: &value.owner, reference: &value.reference)
            XCTAssertTrue(value.owner.isAutomaticallySuspended)
        }
        for baseline in nativePhases() {
            for logical in [false, true] {
                var value = baseline
                assertNativeParity(.cancel(value.binding, logical), owner: &value.owner, reference: &value.reference)
            }
        }
        var final = nativePhases()[8]
        assertNativeParity(.commit(final.life.request, final.binding), owner: &final.owner, reference: &final.reference)
        let replacement = Binding(visibility: 9)
        assertNativeParity(.activate(84, replacement), owner: &final.owner, reference: &final.reference)
        let before = final.owner
        for input in [Input.rollback(final.life.notice, final.binding), .rollback(final.life.notice, replacement),
                      .cancel(final.binding, false), .cancel(replacement, true)] {
            XCTAssertEqual(assertNativeParity(input, owner: &final.owner, reference: &final.reference).accepted, 0)
            XCTAssertEqual(final.owner, before)
        }
    }

    private func marker(_ value: WebRTCScreenMediaMarkerReady, id: UUID? = nil, version: Int? = nil,
                        screen: UInt64? = nil, generation: UInt64? = nil, encoder: UInt64? = nil,
                        boundary: UInt64? = nil, geometry: WebRTCScreenMediaGeometry? = nil) -> WebRTCScreenMediaMarkerReady {
        .init(attemptID: id ?? value.attemptID, screenRequestID: screen ?? value.screenRequestID,
              suspensionGeneration: generation ?? value.suspensionGeneration,
              encoderGeneration: encoder ?? value.encoderGeneration,
              encoderMarkerRTPTimestamp: value.encoderMarkerRTPTimestamp,
              boundaryRevision: boundary ?? value.boundaryRevision, geometry: geometry ?? value.geometry,
              protocolVersion: version ?? value.protocolVersion)
    }

    private func markerPresentation(_ value: WebRTCScreenMediaMarkerPresentation,
                                    ready: WebRTCScreenMediaMarkerReady? = nil, version: Int? = nil,
                                    receiver: String? = nil, source: UInt32? = nil,
                                    width: Int? = nil, height: Int? = nil) -> WebRTCScreenMediaMarkerPresentation {
        .init(markerReady: ready ?? value.markerReady, receiverMarkerRTPTimestamp: value.receiverMarkerRTPTimestamp,
              receiverID: receiver ?? value.receiverID, sourceID: source ?? value.sourceID,
              presentedWidth: width ?? value.presentedWidth, presentedHeight: height ?? value.presentedHeight,
              protocolVersion: version ?? value.protocolVersion)
    }

    private func resume(_ value: WebRTCScreenMediaResumeReady, presentation: WebRTCScreenMediaMarkerPresentation? = nil,
                        encoderMarker: UInt32? = nil, encoderReal: UInt32? = nil, receiverMarker: UInt32? = nil,
                        receiverFloor: UInt32? = nil, geometry: WebRTCScreenMediaGeometry? = nil,
                        version: Int? = nil) -> WebRTCScreenMediaResumeReady {
        .init(markerPresentation: presentation ?? value.markerPresentation,
              encoderMarkerRTPTimestamp: encoderMarker ?? value.encoderMarkerRTPTimestamp,
              encoderRealFrameRTPTimestamp: encoderReal ?? value.encoderRealFrameRTPTimestamp,
              receiverMarkerRTPTimestamp: receiverMarker ?? value.receiverMarkerRTPTimestamp,
              receiverRealFrameFloorRTPTimestamp: receiverFloor ?? value.receiverRealFrameFloorRTPTimestamp,
              geometry: geometry ?? value.geometry, protocolVersion: version ?? value.protocolVersion)
    }

    private func request(_ value: WebRTCScreenMediaResumeRequest, ready: WebRTCScreenMediaResumeReady? = nil,
                         timestamp: UInt32? = nil, receiver: String? = nil, source: UInt32? = nil,
                         width: Int? = nil, height: Int? = nil, id: UInt64? = nil,
                         version: Int? = nil) -> WebRTCScreenMediaResumeRequest {
        let old = value.presentation
        let presentation = WebRTCScreenMediaPresentation(resumeReady: ready ?? old.resumeReady,
            presentedRTPTimestamp: timestamp ?? old.presentedRTPTimestamp,
            receiverID: receiver ?? old.receiverID, sourceID: source ?? old.sourceID,
            presentedWidth: width ?? old.presentedWidth, presentedHeight: height ?? old.presentedHeight,
            protocolVersion: old.protocolVersion)
        return .init(id: id ?? value.id, presentation: presentation, protocolVersion: version ?? value.protocolVersion)
    }

    func testNativeMarkerReadyAndExactEchoKeepEntirePayloadDomain() {
        let before = nativePhases()[4]
        let ready = before.life.ready
        let altered: [WebRTCScreenMediaMarkerReady] = [marker(ready, id: zeroUUID),
            marker(ready, id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!),
            marker(ready, version: 2), marker(ready, screen: ready.screenRequestID &+ 1),
            marker(ready, generation: ready.suspensionGeneration &+ 1), marker(ready, encoder: 0),
            marker(ready, boundary: 0), marker(ready, geometry: .init(geometryRevision: 0, captureWidth: 3_024, captureHeight: 1_964)),
            marker(ready, geometry: .init(geometryRevision: 23, captureWidth: 1, captureHeight: 32_769))]
        for input in altered {
            var value = before
            XCTAssertEqual(assertNativeParity(.markerReady(input, value.binding), owner: &value.owner, reference: &value.reference).accepted, 0)
        }
        var changedValid = before
        let differentEncoder = marker(ready, encoder: ready.encoderGeneration &+ 1)
        // The original owner accepts a first nonzero encoder-generation proof; the service's
        // concrete encoder check remains outside this reducer. Never silently tighten it here.
        XCTAssertEqual(assertNativeParity(.markerReady(differentEncoder, changedValid.binding),
            owner: &changedValid.owner, reference: &changedValid.reference).accepted, 1)
        XCTAssertEqual(changedValid.owner.snapshot.custody.markerReady, differentEncoder)
        XCTAssertEqual(assertNativeParity(.markerPresentation(before.life.marker, changedValid.binding),
            owner: &changedValid.owner, reference: &changedValid.reference).accepted, 0)
    }

    func testNativeMarkerPresentationRejectsInvalidReceiverSourceShapeAndDeepEcho() {
        let baseline = nativePhases()[5]
        let value = baseline.life.marker
        let changed = [markerPresentation(value, version: 2), markerPresentation(value, receiver: ""),
            markerPresentation(value, receiver: String(repeating: "é", count: 129)),
            markerPresentation(value, receiver: "receiver\n1"), markerPresentation(value, source: 0),
            markerPresentation(value, width: 0), markerPresentation(value, width: 832, height: 1_280),
            markerPresentation(value, width: 6_048, height: 3_928),
            markerPresentation(value, ready: marker(value.markerReady, boundary: value.markerReady.boundaryRevision &+ 1))]
        for proof in changed {
            var owner = baseline
            XCTAssertEqual(assertNativeParity(.markerPresentation(proof, owner.binding), owner: &owner.owner, reference: &owner.reference).accepted, 0)
        }
    }

    func testNativeResumeReadyPreservesSeparateRTPDomainsAndSerialLimits() {
        let baseline = nativePhases()[6]
        let value = baseline.life.resume
        let wrongReceiver = markerPresentation(value.markerPresentation, receiver: "receiver-2")
        let changed = [resume(value, version: 2), resume(value, encoderMarker: value.encoderMarkerRTPTimestamp &+ 1),
            resume(value, encoderReal: value.encoderMarkerRTPTimestamp),
            resume(value, encoderReal: value.encoderMarkerRTPTimestamp &+ 0x8000_0000),
            resume(value, receiverMarker: value.receiverMarkerRTPTimestamp &+ 1),
            resume(value, receiverFloor: value.receiverRealFrameFloorRTPTimestamp &+ 1),
            resume(value, geometry: .init(geometryRevision: 24, captureWidth: 3_024, captureHeight: 1_964)),
            resume(value, presentation: wrongReceiver)]
        for proof in changed {
            var owner = baseline
            XCTAssertEqual(assertNativeParity(.resumeReady(proof, owner.binding), owner: &owner.owner, reference: &owner.reference).accepted, 0)
        }
        var owner = baseline
        XCTAssertEqual(assertNativeParity(.resumeReady(value, owner.binding), owner: &owner.owner, reference: &owner.reference).accepted, 1)
        XCTAssertEqual(owner.owner.snapshot.custody.resumeReady?.encoderRealFrameRTPTimestamp, 5)
        XCTAssertEqual(owner.owner.snapshot.custody.resumeReady?.receiverRealFrameFloorRTPTimestamp, 1_008)
    }

    func testNativeResumeRequestAndFinalizationRequireFullNestedEquality() {
        let baseline = nativePhases()[7]
        let value = baseline.life.request
        let ready = value.presentation.resumeReady
        let changed = [request(value, id: 0), request(value, version: 2),
            request(value, timestamp: ready.receiverMarkerRTPTimestamp),
            request(value, timestamp: ready.receiverRealFrameFloorRTPTimestamp &+ 0x8000_0000),
            request(value, receiver: "receiver-2"), request(value, source: 78),
            request(value, width: 640, height: 416),
            request(value, ready: resume(ready, receiverFloor: ready.receiverRealFrameFloorRTPTimestamp &+ 1))]
        for proof in changed {
            var owner = baseline
            XCTAssertEqual(assertNativeParity(.resumeRequest(proof, owner.binding), owner: &owner.owner, reference: &owner.reference).accepted, 0)
        }
        var later = baseline
        let laterRequest = request(value, timestamp: ready.receiverRealFrameFloorRTPTimestamp &+ 90_000)
        XCTAssertEqual(assertNativeParity(.resumeRequest(laterRequest, later.binding), owner: &later.owner, reference: &later.reference).accepted, 1)
        XCTAssertEqual(assertNativeParity(.commit(value, later.binding), owner: &later.owner, reference: &later.reference).accepted, 0)
        XCTAssertEqual(assertNativeParity(.authorize(value, later.binding), owner: &later.owner, reference: &later.reference).accepted, 0)
        let alternateID = request(laterRequest, id: laterRequest.id &+ 1)
        XCTAssertEqual(assertNativeParity(.authorize(alternateID, later.binding), owner: &later.owner, reference: &later.reference).accepted, 0)
        XCTAssertEqual(assertNativeParity(.commit(alternateID, later.binding), owner: &later.owner, reference: &later.reference).accepted, 0)
        assertNativeParity(.commit(laterRequest, later.binding), owner: &later.owner, reference: &later.reference)
    }

    func testNativeUnicodeEqualityPreservesIncomingReceiverSpelling() {
        var value = nativePhases()[5]
        let composed = lifecycle(notice: value.life.notice, receiver: "caf\u{00e9}")
        let decomposed = lifecycle(notice: value.life.notice, receiver: "cafe\u{0301}")
        XCTAssertEqual(composed.marker, decomposed.marker)
        XCTAssertNotEqual(Array(composed.marker.receiverID.utf8), Array(decomposed.marker.receiverID.utf8))
        assertNativeParity(.markerPresentation(composed.marker, value.binding), owner: &value.owner, reference: &value.reference)
        assertNativeParity(.resumeReady(decomposed.resume, value.binding), owner: &value.owner, reference: &value.reference)
        XCTAssertEqual(Array(value.owner.snapshot.custody.resumeReady!.markerPresentation.receiverID.utf8),
                       Array(decomposed.marker.receiverID.utf8))
        assertNativeParity(.resumeRequest(composed.request, value.binding), owner: &value.owner, reference: &value.reference)
        XCTAssertEqual(Array(value.owner.snapshot.custody.resumeRequest!.presentation.receiverID.utf8),
                       Array(composed.marker.receiverID.utf8))
    }

    func testNativeValueCopiesRemainIndependentAcrossEveryPhase() {
        for baseline in nativePhases() {
            var changed = baseline
            let unchanged = baseline.owner
            let before = unchanged.snapshot
            assertNativeParity(.retire, owner: &changed.owner, reference: &changed.reference)
            assertNativeParity(.activate(84, Binding(peer: 9, visibility: 19, recovery: 0)),
                               owner: &changed.owner, reference: &changed.reference)
            XCTAssertEqual(unchanged.snapshot, before)
            assertSnapshot(unchanged, matches: baseline.reference)
            XCTAssertNotEqual(changed.owner, unchanged)
        }
    }

    func testNativeDeepCustodyValidatorRejectsForeignUUIDNoticeAndExtraStandaloneProofs() {
        typealias Custody = WorldwideScreenMediaSuspensionCoordinator.NativeCustody
        let phases = nativePhases()
        for value in phases {
            let snapshot = value.owner.snapshot
            XCTAssertTrue(WorldwideScreenMediaSuspensionCoordinator.custodyIsConsistent(snapshot.custody, with: snapshot.rawState))
            let held = snapshot.custody
            let extra = Custody(currentNotice: held.currentNotice, priorResumedNotice: held.priorResumedNotice,
                attemptID: held.attemptID, markerReady: value.life.ready,
                markerPresentation: value.life.marker, resumeReady: value.life.resume, resumeRequest: value.life.request)
            XCTAssertFalse(WorldwideScreenMediaSuspensionCoordinator.custodyIsConsistent(extra, with: snapshot.rawState))
        }
        for index in 4...8 {
            let value = phases[index]
            let held = value.owner.snapshot.custody
            let wrongAttempt = Custody(currentNotice: held.currentNotice, priorResumedNotice: held.priorResumedNotice,
                attemptID: zeroUUID, markerReady: held.markerReady, markerPresentation: held.markerPresentation,
                resumeReady: held.resumeReady, resumeRequest: held.resumeRequest)
            XCTAssertFalse(WorldwideScreenMediaSuspensionCoordinator.custodyIsConsistent(wrongAttempt, with: value.owner.snapshot.rawState))
        }
        let alternate = lifecycle(notice: phases[8].life.notice,
            attemptID: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!)
        let proofByPhase: [Custody] = [
            .init(currentNotice: phases[5].life.notice, attemptID: attempt, markerReady: alternate.ready),
            .init(currentNotice: phases[6].life.notice, attemptID: attempt, markerPresentation: alternate.marker),
            .init(currentNotice: phases[7].life.notice, attemptID: attempt, resumeReady: alternate.resume),
            .init(currentNotice: phases[8].life.notice, attemptID: attempt, resumeRequest: alternate.request)]
        for (offset, custody) in proofByPhase.enumerated() {
            XCTAssertFalse(WorldwideScreenMediaSuspensionCoordinator.custodyIsConsistent(custody,
                with: phases[offset + 5].owner.snapshot.rawState))
        }
        let foreign = lifecycle(notice: .init(screenRequestID: 84, suspensionGeneration: 1))
        let foreignReady = Custody(currentNotice: phases[5].life.notice, attemptID: attempt, markerReady: foreign.ready)
        XCTAssertFalse(WorldwideScreenMediaSuspensionCoordinator.custodyIsConsistent(foreignReady, with: phases[5].owner.snapshot.rawState))
        let invalidNotice = WebRTCScreenMediaSuspensionNotice(screenRequestID: 42, suspensionGeneration: 1, protocolVersion: 2)
        let invalid = Custody(currentNotice: invalidNotice)
        XCTAssertFalse(WorldwideScreenMediaSuspensionCoordinator.custodyIsConsistent(invalid, with: phases[3].owner.snapshot.rawState))
        // The seam examines copied values only. None of these invalid examples alter an owner.
        for value in phases { assertSnapshot(value.owner, matches: value.reference) }
    }

    func testNativeDeepCustodyValidatorRejectsInvalidNestedLeafAndPriorProvenance() {
        typealias Custody = WorldwideScreenMediaSuspensionCoordinator.NativeCustody
        let phases = nativePhases()
        let invalidProofs: [(Int, Custody)] = [
            (5, .init(currentNotice: phases[5].life.notice, attemptID: attempt,
                      markerReady: marker(phases[5].life.ready, encoder: 0))),
            (6, .init(currentNotice: phases[6].life.notice, attemptID: attempt,
                      markerPresentation: markerPresentation(phases[6].life.marker, receiver: "receiver\n1"))),
            (7, .init(currentNotice: phases[7].life.notice, attemptID: attempt,
                      resumeReady: resume(phases[7].life.resume, receiverFloor: 1_009))),
            (8, .init(currentNotice: phases[8].life.notice, attemptID: attempt,
                      resumeRequest: request(phases[8].life.request, id: 0)))]
        for (index, custody) in invalidProofs {
            XCTAssertFalse(WorldwideScreenMediaSuspensionCoordinator.custodyIsConsistent(custody,
                with: phases[index].owner.snapshot.rawState))
            assertSnapshot(phases[index].owner, matches: phases[index].reference)
        }
        var value = phases[8]
        assertNativeParity(.commit(value.life.request, value.binding), owner: &value.owner, reference: &value.reference)
        assertNativeParity(.begin(true, value.binding), owner: &value.owner, reference: &value.reference)
        let before = value.owner.snapshot
        XCTAssertEqual(before.rawState.custody_mask, 3)
        let invalidPrior = WebRTCScreenMediaSuspensionNotice(screenRequestID: 42, suspensionGeneration: 1, protocolVersion: 2)
        let badPrior = Custody(currentNotice: before.custody.currentNotice, priorResumedNotice: invalidPrior)
        XCTAssertFalse(WorldwideScreenMediaSuspensionCoordinator.custodyIsConsistent(badPrior, with: before.rawState))
        let wrongPair = Custody(currentNotice: .init(screenRequestID: 84, suspensionGeneration: 2),
                               priorResumedNotice: before.custody.priorResumedNotice)
        XCTAssertFalse(WorldwideScreenMediaSuspensionCoordinator.custodyIsConsistent(wrongPair, with: before.rawState))
        XCTAssertEqual(value.owner.snapshot, before)
    }

    private func faultInput(_ opcode: UInt32, phases: [NativePhase]) -> (NativePhase, Input) {
        switch opcode {
        case 1: return (phases[0], .activate(42, phases[0].binding))
        case 2: return (phases[1], .retire)
        case 3: return (phases[2], .abort(phases[2].binding))
        case 4: return (phases[1], .begin(true, phases[1].binding))
        case 5: return (phases[2], .cover(.init(suspension: phases[2].life.notice), phases[2].binding))
        case 6: return (phases[2], .inactive(phases[2].life.notice, Binding(visibility: 8)))
        case 7: return (phases[3], .beginResume(attempt, phases[3].binding))
        case 8: return (phases[4], .markerReady(phases[4].life.ready, phases[4].binding))
        case 9: return (phases[5], .markerPresentation(phases[5].life.marker, phases[5].binding))
        case 10: return (phases[6], .resumeReady(phases[6].life.resume, phases[6].binding))
        case 11: return (phases[7], .resumeRequest(phases[7].life.request, phases[7].binding))
        case 12: return (phases[8], .commit(phases[8].life.request, phases[8].binding))
        case 13:
            var value = phases[8]
            assertNativeParity(.commit(value.life.request, value.binding), owner: &value.owner, reference: &value.reference)
            return (value, .rollback(value.life.notice, value.binding))
        case 14: return (phases[4], .cancel(phases[4].binding, true))
        default:
            XCTFail("Invalid mutating-opcode fixture")
            return (phases[0], .activate(42, phases[0].binding))
        }
    }

    private func assertRetainedAfterFault(_ owner: WorldwideScreenMediaSuspensionCoordinator,
                                         before: WorldwideScreenMediaSuspensionCoordinator.Snapshot,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(owner.hasNativeFault, file: file, line: line)
        XCTAssertTrue(owner.snapshot.hasNativeFault, file: file, line: line)
        XCTAssertEqual(bytes(owner.snapshot.rawState), bytes(before.rawState), file: file, line: line)
        XCTAssertEqual(owner.snapshot.queryFlags, before.queryFlags, file: file, line: line)
        XCTAssertEqual(owner.snapshot.custody, before.custody, file: file, line: line)
        XCTAssertEqual(owner.isAutomaticallySuspended, before.queryFlags & 1 != 0, file: file, line: line)
        XCTAssertEqual(owner.suspensionIsInFlight, before.queryFlags & 2 != 0, file: file, line: line)
        XCTAssertEqual(owner.isResumeProbeInFlight, before.queryFlags & 4 != 0, file: file, line: line)
        XCTAssertEqual(owner.diagnosticSnapshot.requiresFreshMediaSessionAfterInvalidation,
                       before.queryFlags & 128 != 0, file: file, line: line)
    }

    func testNativeEveryMutatingOpcodeRejectsCopiedResultWithoutPartialPublication() {
        for opcode in UInt32(1)...14 {
            let control = ScreenSuspensionTestBox(ScreenSuspensionMutationControl())
            let phases = nativePhases(mutation: suspensionMutation(control))
            var (value, input) = faultInput(opcode, phases: phases)
            let sibling = value.owner
            let before = value.owner.snapshot
            let calls = control.get().calls.count
            control.update { $0.armed = true; $0.opcode = opcode }
            let outcome = apply(input, to: &value.owner)
            if let accepted = outcome.0 { XCTAssertFalse(accepted) }
            XCTAssertNil(outcome.1)
            XCTAssertEqual(control.get().calls.count, calls + 1)
            assertRetainedAfterFault(value.owner, before: before)
            XCTAssertEqual(sibling.snapshot, before)
            control.update { $0.armed = false }
            let faultedCalls = control.get().calls.count
            XCTAssertFalse(value.owner.activate(screenRequestID: 84, binding: Binding(peer: 9, visibility: 19).native))
            value.owner.retire()
            value.owner.cancelResume(binding: value.binding.native, logicalScreenIsStillRequested: false)
            XCTAssertNil(value.owner.beginSuspensionIfNegotiated(negotiated: true, binding: value.binding.native))
            XCTAssertFalse(value.owner.owns(value.binding.native))
            XCTAssertFalse(value.owner.authorizesFinalization(of: value.life.request, binding: value.binding.native))
            XCTAssertEqual(control.get().calls.count, faultedCalls)
            assertRetainedAfterFault(value.owner, before: before)
            XCTAssertEqual(sibling.snapshot, before)
        }
    }

    func testNativeBeginRejectsEveryCopiedResultByteAndRetainsGenerator() {
        for byte in 0..<128 {
            let control = ScreenSuspensionTestBox(ScreenSuspensionMutationControl())
            var owner = WorldwideScreenMediaSuspensionCoordinator(resultMutation: suspensionMutation(control))
            XCTAssertTrue(owner.activate(screenRequestID: 42, binding: Binding().native))
            let before = owner.snapshot
            control.update { $0.armed = true; $0.opcode = 4; $0.byte = byte }
            XCTAssertNil(owner.beginSuspensionIfNegotiated(negotiated: true, binding: Binding().native))
            assertRetainedAfterFault(owner, before: before)
            XCTAssertEqual(owner.snapshot.rawState.next_generation, 1)
        }
    }

    func testNativeNonmutatingQueryDenialNeverPoisonsOwnerOrCopy() {
        for opcode in [UInt32(15), 16] {
            let control = ScreenSuspensionTestBox(ScreenSuspensionMutationControl())
            let phases = nativePhases(mutation: suspensionMutation(control))
            let value = opcode == 15 ? phases[1] : phases[8]
            let owner = value.owner
            let sibling = owner
            let before = owner.snapshot
            let calls = control.get().calls.count
            control.update { $0.armed = true; $0.opcode = opcode }
            if opcode == 15 { XCTAssertFalse(owner.owns(value.binding.native)) }
            else { XCTAssertFalse(owner.authorizesFinalization(of: value.life.request, binding: value.binding.native)) }
            XCTAssertEqual(control.get().calls.count, calls + 1)
            XCTAssertEqual(owner.snapshot, before)
            XCTAssertEqual(sibling.snapshot, before)
            XCTAssertFalse(owner.hasNativeFault)
            control.update { $0.armed = false }
            if opcode == 15 { XCTAssertTrue(owner.owns(value.binding.native)) }
            else { XCTAssertTrue(owner.authorizesFinalization(of: value.life.request, binding: value.binding.native)) }
            XCTAssertEqual(control.get().calls.count, calls + 2)
            XCTAssertEqual(owner.snapshot, before)
            XCTAssertEqual(sibling.snapshot, before)
        }
    }

    func testNativeNonmutatingCopiedRefusalCannotForgeAuthorityGrant() {
        for opcode in [UInt32(15), 16] {
            let control = ScreenSuspensionTestBox(ScreenSuspensionMutationControl())
            let value = nativePhases(mutation: suspensionMutation(control))[8]
            let owner = value.owner
            let before = owner.snapshot
            let stale = Binding(peer: value.binding.peer, visibility: value.binding.visibility,
                                recovery: value.binding.recovery &+ 1)
            let foreignRequest = request(value.life.request, id: value.life.request.id &+ 1)
            // Each actual producer result is an ordinary false query. Flipping its
            // accepted byte would grant authority if the actual verifier were bypassed.
            if opcode == 15 { XCTAssertFalse(owner.owns(stale.native)) }
            else { XCTAssertFalse(owner.authorizesFinalization(of: foreignRequest, binding: value.binding.native)) }
            control.update { $0.armed = true; $0.opcode = opcode; $0.byte = 8 }
            if opcode == 15 { XCTAssertFalse(owner.owns(stale.native)) }
            else { XCTAssertFalse(owner.authorizesFinalization(of: foreignRequest, binding: value.binding.native)) }
            XCTAssertEqual(owner.snapshot, before)
            XCTAssertFalse(owner.hasNativeFault)
            control.update { $0.armed = false }
            XCTAssertTrue(owner.authorizesFinalization(of: value.life.request, binding: value.binding.native))
            XCTAssertEqual(owner.snapshot, before)
        }
    }

    func testNativeFaultInOneCopyCannotPoisonHealthySiblingOrClearRetainedDiagnostic() {
        let control = ScreenSuspensionTestBox(ScreenSuspensionMutationControl())
        let phases = nativePhases(mutation: suspensionMutation(control))
        var value = phases[8]
        let sibling = value.owner
        let before = value.owner.snapshot
        control.update { $0.armed = true; $0.opcode = 12 }
        XCTAssertFalse(value.owner.commitFinalization(of: value.life.request, binding: value.binding.native))
        assertRetainedAfterFault(value.owner, before: before)
        control.update { $0.armed = false }
        XCTAssertTrue(sibling.authorizesFinalization(of: value.life.request, binding: value.binding.native))
        XCTAssertEqual(sibling.snapshot, before)
        XCTAssertNotEqual(value.owner, sibling)
        XCTAssertEqual(value.owner.currentSuspensionNotice, sibling.currentSuspensionNotice)
        XCTAssertEqual(value.owner.diagnosticSnapshot, sibling.diagnosticSnapshot)
        value.owner.retire()
        assertRetainedAfterFault(value.owner, before: before)
    }

    func testNativeInitialProjectionCopiedResultFailureLatchesWithoutGrant() {
        let control = ScreenSuspensionTestBox(ScreenSuspensionMutationControl(armed: true, opcode: 0))
        var owner = WorldwideScreenMediaSuspensionCoordinator(resultMutation: suspensionMutation(control))
        XCTAssertEqual(control.get().calls, [0])
        XCTAssertTrue(owner.hasNativeFault)
        XCTAssertEqual(bytes(owner.snapshot.rawState), bytes(initialState()))
        XCTAssertEqual(owner.snapshot.queryFlags, 0)
        XCTAssertNil(owner.currentSuspensionNotice)
        XCTAssertFalse(owner.activate(screenRequestID: 42, binding: Binding().native))
        owner.retire()
        XCTAssertFalse(owner.owns(Binding().native))
        XCTAssertEqual(control.get().calls, [0])
    }
}
