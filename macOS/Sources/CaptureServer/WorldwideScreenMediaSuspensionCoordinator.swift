import Foundation
import WebRTCTransport

/// Actor-owned value transcript. Rust owns its scalar lifecycle; Swift keeps
/// complete immutable protocol proofs and native equality/validity only. Concrete
/// source/sink authorization and asynchronous effects remain in the service.
struct WorldwideScreenMediaSuspensionCoordinator: Equatable, Sendable {
    enum DiagnosticPhase: String, Equatable, Sendable {
        case idle, active, suspending, suspended, awaitingMarker
        case awaitingMarkerPresentation, awaitingRealFrame
        case awaitingRealPresentation, awaitingFinalization
    }

    struct DiagnosticSnapshot: Equatable, Sendable {
        let phase: DiagnosticPhase
        let screenRequestID: UInt64?
        let suspensionGeneration: UInt64?
        let binding: Binding?
        // This is a cached, verified Rust projection, not a native phase policy.
        let requiresFreshMediaSessionAfterInvalidation: Bool
    }

    struct Binding: Equatable, Sendable {
        let peerGeneration: UInt64
        let visibilityCommandEpoch: UInt64
        let recoveryEpoch: UInt64

        var isValid: Bool {
            BelugaRustScreenSuspension.bindingIsValid(
                peer: peerGeneration, visibility: visibilityCommandEpoch,
                recovery: recoveryEpoch
            )
        }
    }

    /// Copied-value inspection/validation seam only. It cannot seed or change a
    /// coordinator. Every nested proof and original receiver String is retained.
    struct NativeCustody: Equatable, Sendable {
        let currentNotice: WebRTCScreenMediaSuspensionNotice?
        let priorResumedNotice: WebRTCScreenMediaSuspensionNotice?
        let attemptID: UUID?
        let markerReady: WebRTCScreenMediaMarkerReady?
        let markerPresentation: WebRTCScreenMediaMarkerPresentation?
        let resumeReady: WebRTCScreenMediaResumeReady?
        let resumeRequest: WebRTCScreenMediaResumeRequest?

        init(currentNotice: WebRTCScreenMediaSuspensionNotice? = nil,
             priorResumedNotice: WebRTCScreenMediaSuspensionNotice? = nil,
             attemptID: UUID? = nil,
             markerReady: WebRTCScreenMediaMarkerReady? = nil,
             markerPresentation: WebRTCScreenMediaMarkerPresentation? = nil,
             resumeReady: WebRTCScreenMediaResumeReady? = nil,
             resumeRequest: WebRTCScreenMediaResumeRequest? = nil) {
            self.currentNotice = currentNotice
            self.priorResumedNotice = priorResumedNotice
            self.attemptID = attemptID
            self.markerReady = markerReady
            self.markerPresentation = markerPresentation
            self.resumeReady = resumeReady
            self.resumeRequest = resumeRequest
        }

        fileprivate var presenceMask: UInt32 {
            (currentNotice == nil ? 0 : 1) | (priorResumedNotice == nil ? 0 : 2)
                | (attemptID == nil ? 0 : 4) | (markerReady == nil ? 0 : 8)
                | (markerPresentation == nil ? 0 : 16)
                | (resumeReady == nil ? 0 : 32) | (resumeRequest == nil ? 0 : 64)
        }
    }

    struct Snapshot: Equatable, Sendable {
        let rawState: BelugaRustScreenSuspension.State
        let queryFlags: UInt32
        let hasNativeFault: Bool
        let custody: NativeCustody

        static func == (lhs: Self, rhs: Self) -> Bool {
            BelugaRustScreenSuspension.statesEqual(lhs.rawState, rhs.rawState)
                && lhs.queryFlags == rhs.queryFlags
                && lhs.hasNativeFault == rhs.hasNativeFault
                && lhs.custody == rhs.custody
        }
    }

    private var core: BelugaRustScreenSuspension
    private var custody = NativeCustody()

    init(resultMutation: BelugaRustScreenSuspension.ResultMutation? = nil) {
        core = BelugaRustScreenSuspension(resultMutation: resultMutation)
    }

    var snapshot: Snapshot {
        Snapshot(rawState: core.rawState, queryFlags: core.queryFlags,
                 hasNativeFault: core.hasNativeFault, custody: custody)
    }

    var hasNativeFault: Bool { core.hasNativeFault }

    var diagnosticSnapshot: DiagnosticSnapshot {
        // Tag decoding is representation only; all optional presence/provenance
        // comes from the verified Rust projection, including completed Active.
        let phase: DiagnosticPhase
        switch core.rawState.phase {
        case 0: phase = .idle
        case 1: phase = .active
        case 2: phase = .suspending
        case 3: phase = .suspended
        case 4: phase = .awaitingMarker
        case 5: phase = .awaitingMarkerPresentation
        case 6: phase = .awaitingRealFrame
        case 7: phase = .awaitingRealPresentation
        case 8: phase = .awaitingFinalization
        default: phase = .idle // Unreachable after verified publication.
        }
        return DiagnosticSnapshot(
            phase: phase,
            screenRequestID: hasProjection(3) ? core.rawState.screen_request_id : nil,
            suspensionGeneration: hasProjection(5) ? core.rawState.suspension_generation : nil,
            binding: hasProjection(6) ? Binding(
                peerGeneration: core.rawState.peer_generation,
                visibilityCommandEpoch: core.rawState.visibility_epoch,
                recoveryEpoch: core.rawState.recovery_epoch
            ) : nil,
            requiresFreshMediaSessionAfterInvalidation: hasProjection(7)
        )
    }

    var isAutomaticallySuspended: Bool { hasProjection(0) }
    var suspensionIsInFlight: Bool { hasProjection(1) }
    var isResumeProbeInFlight: Bool { hasProjection(2) }
    var activeScreenRequestID: UInt64? {
        hasProjection(3) ? core.rawState.screen_request_id : nil
    }
    var currentSuspensionNotice: WebRTCScreenMediaSuspensionNotice? {
        hasProjection(4) ? custody.currentNotice : nil
    }

    mutating func activate(screenRequestID: UInt64, binding: Binding) -> Bool {
        perform(Self.event(1, binding: binding, screenRequestID: screenRequestID))?.accepted == 1
    }

    mutating func retire() {
        _ = perform(Self.event(2))
    }

    mutating func abortSuspensionBeforeInactive(binding: Binding) -> Bool {
        perform(Self.event(3, binding: binding))?.accepted == 1
    }

    /// Old/unnegotiated viewers preserve their established nonzero-floor state.
    /// The dormant service entry boundary is unchanged by this scalar extraction.
    mutating func beginSuspensionIfNegotiated(
        negotiated: Bool, binding: Binding
    ) -> WebRTCScreenMediaSuspensionNotice? {
        guard perform(Self.event(4, binding: binding,
                                 flags: negotiated ? 1 : 0))?.accepted == 1 else { return nil }
        return custody.currentNotice
    }

    mutating func confirmCover(
        _ acknowledgement: WebRTCScreenMediaCoveredAcknowledgement, binding: Binding
    ) -> Bool {
        let exact = custody.currentNotice.map { acknowledgement.isExactEcho(of: $0) } ?? false
        return perform(Self.event(5, binding: binding,
                                  noticeScreen: acknowledgement.suspension.screenRequestID,
                                  noticeGeneration: acknowledgement.suspension.suspensionGeneration,
                                  facts: Self.fact(exact, 1)))?.accepted == 1
    }

    mutating func confirmInactive(
        for notice: WebRTCScreenMediaSuspensionNotice, binding: Binding
    ) -> Bool {
        perform(Self.event(6, binding: binding, noticeScreen: notice.screenRequestID,
                           noticeGeneration: notice.suspensionGeneration,
                           facts: Self.fact(custody.currentNotice == notice, 0)))?.accepted == 1
    }

    mutating func beginResumeAttempt(attemptID: UUID, binding: Binding) -> Bool {
        perform(Self.event(7, binding: binding,
                           facts: Self.fact(attemptID != Self.zeroUUID, 2)),
                input: .attempt(attemptID))?.accepted == 1
    }

    mutating func acceptMarkerReady(_ ready: WebRTCScreenMediaMarkerReady,
                                    binding: Binding) -> Bool {
        let belongs = custody.currentNotice.map { ready.belongs(to: $0) } ?? false
        return perform(Self.event(8, binding: binding, noticeScreen: ready.screenRequestID,
                                  noticeGeneration: ready.suspensionGeneration,
                                  facts: Self.fact(custody.attemptID == ready.attemptID, 3)
                                    | Self.fact(belongs, 4)),
                       input: .markerReady(ready))?.accepted == 1
    }

    mutating func acceptMarkerPresentation(_ presentation: WebRTCScreenMediaMarkerPresentation,
                                           binding: Binding) -> Bool {
        let exact = custody.markerReady.map { presentation.isExactEcho(of: $0) } ?? false
        return perform(Self.event(9, binding: binding,
                                  noticeScreen: presentation.markerReady.screenRequestID,
                                  noticeGeneration: presentation.markerReady.suspensionGeneration,
                                  facts: Self.fact(exact, 5)),
                       input: .markerPresentation(presentation))?.accepted == 1
    }

    mutating func acceptResumeReady(_ ready: WebRTCScreenMediaResumeReady,
                                    binding: Binding) -> Bool {
        perform(Self.event(10, binding: binding, noticeScreen: ready.screenRequestID,
                           noticeGeneration: ready.suspensionGeneration,
                           facts: Self.fact(custody.attemptID == ready.attemptID, 3)
                             | Self.fact(ready.isValid, 6)
                             | Self.fact(custody.markerPresentation == ready.markerPresentation, 7)),
                input: .resumeReady(ready))?.accepted == 1
    }

    mutating func acceptResumeRequest(_ request: WebRTCScreenMediaResumeRequest,
                                      binding: Binding) -> Bool {
        let ready = request.presentation.resumeReady
        return perform(Self.event(11, binding: binding, noticeScreen: ready.screenRequestID,
                                  noticeGeneration: ready.suspensionGeneration,
                                  facts: Self.fact(custody.attemptID == ready.attemptID, 3)
                                    | Self.fact(request.isValid, 8)
                                    | Self.fact(custody.resumeReady == ready, 9)),
                       input: .resumeRequest(request))?.accepted == 1
    }

    func authorizesFinalization(of request: WebRTCScreenMediaResumeRequest,
                                binding: Binding) -> Bool {
        let ready = request.presentation.resumeReady
        return query(Self.event(16, binding: binding, noticeScreen: ready.screenRequestID,
                                noticeGeneration: ready.suspensionGeneration,
                                facts: Self.fact(custody.attemptID == ready.attemptID, 3)
                                  | Self.fact(custody.resumeRequest == request, 10)))
    }

    mutating func commitFinalization(of request: WebRTCScreenMediaResumeRequest,
                                     binding: Binding) -> Bool {
        let ready = request.presentation.resumeReady
        // No new explicit UUID/validity admission is added to the original commit.
        return perform(Self.event(12, binding: binding, noticeScreen: ready.screenRequestID,
                                  noticeGeneration: ready.suspensionGeneration,
                                  facts: Self.fact(custody.resumeRequest == request, 10)))?.accepted == 1
    }

    mutating func rollbackFinalizationBeforeAcknowledgement(
        notice: WebRTCScreenMediaSuspensionNotice, binding: Binding
    ) -> Bool {
        perform(Self.event(13, binding: binding, noticeScreen: notice.screenRequestID,
                           noticeGeneration: notice.suspensionGeneration,
                           facts: Self.fact(custody.currentNotice == notice, 0)
                             | Self.fact(notice.isValid, 11)))?.accepted == 1
    }

    mutating func cancelResume(binding: Binding, logicalScreenIsStillRequested: Bool) {
        _ = perform(Self.event(14, binding: binding,
                               flags: logicalScreenIsStillRequested ? 1 : 0))
    }

    func owns(_ binding: Binding) -> Bool {
        query(Self.event(15, binding: binding))
    }

    /// Native consistency only, never an alternate phase/admission reducer. The
    /// actual Rust verifier owns scalar validity and exact phase-specific masks.
    /// Tests may pass inconsistent copied values here without mutating an owner.
    static func custodyIsConsistent(_ custody: NativeCustody,
                                    with state: BelugaRustScreenSuspension.State) -> Bool {
        guard custody.presenceMask == state.custody_mask else { return false }
        if let notice = custody.currentNotice {
            guard notice.isValid, notice.screenRequestID == state.screen_request_id,
                  notice.suspensionGeneration == state.suspension_generation else { return false }
        } else if state.suspension_generation != 0 {
            return false
        }
        if let prior = custody.priorResumedNotice {
            guard prior.isValid, prior.screenRequestID == state.prior_screen_request_id,
                  prior.suspensionGeneration == state.prior_suspension_generation else { return false }
        } else if state.prior_screen_request_id != 0 || state.prior_suspension_generation != 0 {
            return false
        }
        if let attempt = custody.attemptID, attempt == zeroUUID { return false }
        func belongs(_ ready: WebRTCScreenMediaMarkerReady) -> Bool {
            guard let notice = custody.currentNotice, let attempt = custody.attemptID else {
                return false
            }
            return ready.belongs(to: notice) && ready.attemptID == attempt
        }
        if let ready = custody.markerReady {
            guard ready.isValid, belongs(ready) else { return false }
        }
        if let presentation = custody.markerPresentation {
            guard presentation.isValid, belongs(presentation.markerReady) else { return false }
        }
        if let ready = custody.resumeReady {
            guard ready.isValid, belongs(ready.markerPresentation.markerReady) else { return false }
        }
        if let request = custody.resumeRequest {
            guard request.isValid,
                  belongs(request.presentation.resumeReady.markerPresentation.markerReady) else {
                return false
            }
        }
        return true
    }

    private enum Input {
        case none
        case attempt(UUID)
        case markerReady(WebRTCScreenMediaMarkerReady)
        case markerPresentation(WebRTCScreenMediaMarkerPresentation)
        case resumeReady(WebRTCScreenMediaResumeReady)
        case resumeRequest(WebRTCScreenMediaResumeRequest)
    }

    private mutating func perform(_ event: BelugaRustScreenSuspension.Event,
                                  input: Input = .none) -> BelugaRustScreenSuspension.Result? {
        guard !core.hasNativeFault else { return nil }
        guard Self.custodyIsConsistent(custody, with: core.rawState),
              let step = core.evaluated(event),
              let proposedCustody = candidateCustody(for: step.result, input: input),
              Self.custodyIsConsistent(proposedCustody, with: step.result.state) else {
            core.latchFault()
            return nil
        }
        var proposedCore = core
        guard proposedCore.publish(step) else {
            core.latchFault()
            return nil
        }
        // Publish the complete verified transcript atomically, with no native effect.
        core = proposedCore
        custody = proposedCustody
        return step.result
    }

    private func query(_ event: BelugaRustScreenSuspension.Event) -> Bool {
        guard !core.hasNativeFault,
              Self.custodyIsConsistent(custody, with: core.rawState),
              let step = core.evaluated(event),
              step.result.custody_action == 0,
              BelugaRustScreenSuspension.statesEqual(step.result.state, core.rawState),
              step.result.query_flags == core.queryFlags,
              Self.custodyIsConsistent(custody, with: step.result.state) else { return false }
        // The existing nonmutating signature deliberately cannot latch a new
        // owner fault. Denial changes neither this value nor any sibling copy.
        return step.result.accepted == 1
    }

    private func candidateCustody(for result: BelugaRustScreenSuspension.Result,
                                  input: Input) -> NativeCustody? {
        // Actions come exclusively from the actual verified Rust result. NONE
        // retains native custody but still permits partial-join scalar publication.
        switch result.custody_action {
        case 0:
            return custody
        case 1, 2, 13:
            return NativeCustody()
        case 3:
            let notice = WebRTCScreenMediaSuspensionNotice(
                screenRequestID: result.produced_notice_screen_request_id,
                suspensionGeneration: result.produced_notice_generation
            )
            guard notice.isValid else { return nil }
            return NativeCustody(currentNotice: notice,
                                 priorResumedNotice: custody.currentNotice)
        case 4:
            return NativeCustody(currentNotice: custody.priorResumedNotice)
        case 5, 11, 12, 14:
            return NativeCustody(currentNotice: custody.currentNotice)
        case 6:
            guard case .attempt(let attempt) = input else { return nil }
            return NativeCustody(currentNotice: custody.currentNotice, attemptID: attempt)
        case 7:
            guard case .markerReady(let ready) = input else { return nil }
            return NativeCustody(currentNotice: custody.currentNotice,
                                 attemptID: custody.attemptID, markerReady: ready)
        case 8:
            guard case .markerPresentation(let presentation) = input else { return nil }
            return NativeCustody(currentNotice: custody.currentNotice,
                                 attemptID: custody.attemptID, markerPresentation: presentation)
        case 9:
            guard case .resumeReady(let ready) = input else { return nil }
            return NativeCustody(currentNotice: custody.currentNotice,
                                 attemptID: custody.attemptID, resumeReady: ready)
        case 10:
            guard case .resumeRequest(let request) = input else { return nil }
            return NativeCustody(currentNotice: custody.currentNotice,
                                 attemptID: custody.attemptID, resumeRequest: request)
        default:
            return nil
        }
    }

    private func hasProjection(_ bit: UInt32) -> Bool {
        core.queryFlags & (UInt32(1) << bit) != 0
    }

    private static func fact(_ value: Bool, _ bit: UInt32) -> UInt32 {
        value ? UInt32(1) << bit : 0
    }

    private static func event(_ opcode: UInt32, binding: Binding? = nil,
                              screenRequestID: UInt64 = 0, flags: UInt32 = 0,
                              noticeScreen: UInt64 = 0, noticeGeneration: UInt64 = 0,
                              facts: UInt32 = 0) -> BelugaRustScreenSuspension.Event {
        BelugaRustScreenSuspension.Event(
            opcode: opcode, flags: flags, native_facts: facts, reserved: 0,
            screen_request_id: screenRequestID,
            peer_generation: binding?.peerGeneration ?? 0,
            visibility_epoch: binding?.visibilityCommandEpoch ?? 0,
            recovery_epoch: binding?.recoveryEpoch ?? 0,
            notice_screen_request_id: noticeScreen, notice_generation: noticeGeneration
        )
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}
