import Foundation
import RemoteSessionCore
import BelugaCore

/// Gates invitation admission and cleanup behind durably persisted native pairing boundaries.
/// Rust owns the copied policy; native UUIDs, records, closures and effects never cross the ABI.
@MainActor
struct InvitationAcceptanceAction {
    typealias Boundary = BelugaRustInvitationAcceptanceBoundary
    typealias State = Boundary.State
    private var generation: UUID?
    private var nativeOwner: UUID?
    private var admissionAction: (@MainActor () throws -> Void)?
    private var action: (@MainActor (RemotePairedDeviceRecord) throws -> Void)?
    private var core = Boundary.idle
    private let copiedResultProvider: Boundary.CopiedResultProvider
    private var bridgeFaulted = false

    init() {
        copiedResultProvider = { abi, state, event in Boundary.coreOutput(abi, state, event) }
        acceptInitial(beluga_core_invitation_acceptance_initial())
    }

    init(
        copiedResultProvider: @escaping Boundary.CopiedResultProvider,
        initialStateForTesting: State? = nil
    ) {
        self.copiedResultProvider = copiedResultProvider
        acceptInitial(initialStateForTesting ?? beluga_core_invitation_acceptance_initial())
    }

    private mutating func acceptInitial(_ initial: State) {
        // A malformed initial result cannot create a generation, closure or active owner.
        guard Boundary.valid(initial), Boundary.same(initial, Boundary.idle) else {
            core = Boundary.idle; bridgeFaulted = true
            return
        }
        core = initial
    }

    // Readonly copied observations, never a setter or a callback/record export.
    var copiedStateForTesting: Boundary.State { core }
    var nativeOwnerForTesting: UUID? { nativeOwner }
    var hasNativeCallbacksForTesting: Bool { admissionAction != nil || action != nil }
    var bridgeFaultedForTesting: Bool { bridgeFaulted }

    mutating func arm(
        generation: UUID,
        onAdmitted admissionAction: (@MainActor () throws -> Void)? = nil,
        action: @escaping @MainActor (RemotePairedDeviceRecord) throws -> Void
    ) {
        // Original arm replaces the old attempt; never send corrupt previous scalar state onward.
        releaseOwnership()
        bridgeFaulted = false
        var event = Boundary.Event()
        event.opcode = 0
        event.admission_callback_present = admissionAction == nil ? 0 : 1
        let output = copiedResultProvider(1, core, event)
        guard Boundary.accepts(before: core, event: event, output: output) else {
            bridgeFaulted = true // API remains nonthrowing; the new attempt stays entirely empty.
            return
        }
        core = output.state
        self.generation = generation
        nativeOwner = UUID() // Distinct custody even if the same public generation is rearmed.
        self.admissionAction = admissionAction
        self.action = action
    }

    mutating func persistAdmissionAfterRecoverablePairing(
        _ record: RemotePairedDeviceRecord,
        generation: UUID
    ) throws {
        // Exact native UUID early guard; a foreign scalar reply cannot grant this invocation custody.
        guard self.generation == generation else { return }
        guard nativeCustodyMatchesCore else { throw invalidBridge() }
        guard core.flags & 8 == 0 else { return }
        guard let snapshot = snapshot() else { throw invalidBridge() }
        let callback = admissionAction
        var event = Boundary.Event()
        event.opcode = 1; event.generation_matches = 1
        event.phase = Self.phase(record)
        let output = copiedResultProvider(1, core, event)
        guard owns(snapshot), Boundary.accepts(before: snapshot.before, event: event, output: output) else {
            throw invalidBridge()
        }
        switch output.status {
        case 0: // Validated nil callback consumption; no native callback may be invented.
            core = output.state
        case 2:
            guard let callback else { throw invalidBridge() }
            var invocation = PreparedInvocation(snapshot: snapshot, success: output.callback_success_state)
            guard owns(invocation.snapshot), invocation.claimOnce() else { throw invalidBridge() }
            try callback() // ORIGINAL thrown error propagates; no state/binding changes on throw.
            core = invocation.success // Commit already validated Rust candidate, with no post-effect FFI.
        case 3:
            throw InvitationAcceptanceError.pairingIsNotRecoverable
        default:
            throw invalidBridge()
        }
    }

    @discardableResult
    mutating func completeAuthenticatedPairing(
        _ record: RemotePairedDeviceRecord,
        generation: UUID
    ) throws -> Bool {
        guard self.generation == generation, let callback = action else { return false }
        guard nativeCustodyMatchesCore, let snapshot = snapshot() else { throw invalidBridge() }
        var event = Boundary.Event()
        event.opcode = 2; event.generation_matches = 1
        event.phase = Self.phase(record)
        let output = copiedResultProvider(1, core, event)
        guard owns(snapshot), Boundary.accepts(before: snapshot.before, event: event, output: output) else {
            throw invalidBridge()
        }
        switch output.status {
        case 2:
            var invocation = PreparedInvocation(snapshot: snapshot, success: output.callback_success_state)
            guard owns(invocation.snapshot), invocation.claimOnce() else { throw invalidBridge() }
            try callback(record) // Exact supplied native record and captured closure; original error unchanged.
            core = invocation.success
            generationAndCallbacksReleased()
            return true // Actual synchronous native completion success, not copied completion_succeeded.
        case 4:
            throw InvitationAcceptanceError.pairingIsNotActive
        default:
            throw invalidBridge()
        }
    }

    mutating func cancel(generation: UUID) {
        guard self.generation == generation else { return }
        var event = Boundary.Event()
        event.opcode = 4; event.generation_matches = 1
        let validCustody = nativeCustodyMatchesCore
        let output = copiedResultProvider(1, core, event)
        let accepted = validCustody && Boundary.accepts(before: core, event: event, output: output)
        // Exact native cancellation authority cannot be held hostage by a malformed copied result.
        releaseOwnership()
        if !accepted { bridgeFaulted = true }
    }

    private static func phase(_ record: RemotePairedDeviceRecord) -> UInt32 {
        switch record.pairingState {
        case .acceptedIssued: return 1
        case .active: return 2
        default: return 0
        }
    }

    private var nativeCustodyMatchesCore: Bool {
        guard Boundary.valid(core) else { return false }
        if core.flags == 0 {
            return generation == nil && nativeOwner == nil && admissionAction == nil && action == nil
        }
        return generation != nil && nativeOwner != nil && action != nil
            && ((core.flags & 2 != 0) == (admissionAction != nil))
    }

    private struct NativeSnapshot {
        let owner: UUID
        let generation: UUID
        let before: State
    }
    private func snapshot() -> NativeSnapshot? {
        guard nativeCustodyMatchesCore, let nativeOwner, let generation else { return nil }
        return NativeSnapshot(owner: nativeOwner, generation: generation, before: core)
    }
    private func owns(_ snapshot: NativeSnapshot) -> Bool {
        nativeCustodyMatchesCore && nativeOwner == snapshot.owner && generation == snapshot.generation
            && Boundary.same(core, snapshot.before)
    }

    // Stack-local only. Never stored on the gate, passed across await, exposed, or globally registered.
    private struct PreparedInvocation {
        let snapshot: NativeSnapshot
        let success: State
        private var used = false
        init(snapshot: NativeSnapshot, success: State) { self.snapshot = snapshot; self.success = success }
        mutating func claimOnce() -> Bool {
            guard !used else { return false }
            used = true; return true
        }
    }

    private mutating func generationAndCallbacksReleased() {
        generation = nil; nativeOwner = nil; admissionAction = nil; action = nil
    }
    private mutating func releaseOwnership() {
        generationAndCallbacksReleased()
        core = Boundary.idle
    }
    private mutating func invalidBridge() -> InvitationAcceptanceBridgeError {
        bridgeFaulted = true
        return .invalidBridge
    }
}

enum InvitationAcceptanceError: Error, Equatable {
    case pairingIsNotRecoverable
    case pairingIsNotActive
}
enum InvitationAcceptanceBridgeError: Error, Equatable {
    case invalidBridge
}
