import CryptoKit
import Foundation

// Compatibility ABI: pre-rebrand `AudioStreamer.*` labels are signed/MACed v1 transcript bytes.
// They intentionally remain unchanged so saved pairs can reconnect across the product rename.

/// Crash-recoverable durable states for the multi-message pairing commit.
public enum RemotePairingPersistenceState: String, Codable, CaseIterable, Sendable {
    /// Pair root is persisted, but the three-way commit is not durably accepted yet.
    case pending
    /// Viewer durably stored its acknowledgement before sending or resending it.
    case acceptedIssued
    /// Host durably stored the viewer acknowledgement before issuing completion.
    case acceptedReceived
    /// The role-specific commit completion condition has been reached.
    case active
}

/// The next idempotent action implied by a persisted pairing state.
public enum RemotePairingRecoveryAction: Equatable, Sendable {
    case awaitProposal
    case issueProposal
    case resend(RemotePairingCommit)
    case issueCompletion
    case none
    /// The native record is retained, but its copied recovery plan could not be verified.
    /// Authority callers must surface invalidPairingCommitBridge, never treat this as none.
    case invalidBridge
}

/// Durable state created only after an authenticated pairing commit.
///
/// The encoded form contains the pair root key and monotonic reconnect counters. Persist it
/// atomically in a stable, this-device-only Keychain item; never write it to logs or defaults.
public struct RemotePairedDeviceRecord: Codable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    public static let currentVersion: UInt8 = 1

    public let version: UInt8
    public let pairID: UUID
    public let commitID: UUID
    public let localDeviceID: UUID
    public let localRole: RemotePeerRole
    public let localSigningPublicKey: Data
    public let remoteDeviceID: UUID
    public let remoteRole: RemotePeerRole
    public let remoteSigningPublicKey: Data
    public let remoteDisplayName: String?
    public let createdAt: Date
    public internal(set) var pairingState: RemotePairingPersistenceState
    public internal(set) var nextOutboundReconnectSequence: UInt64
    public internal(set) var highestAcceptedReconnectSequence: UInt64

    private let pairingTranscriptHash: Data
    private let pairRootKey: Data
    private var recoveryCommit: RemotePairingCommit?

    internal init(
        pairID: UUID,
        commitID: UUID,
        localDeviceID: UUID,
        localRole: RemotePeerRole,
        localSigningPublicKey: Data,
        remoteDeviceID: UUID,
        remoteRole: RemotePeerRole,
        remoteSigningPublicKey: Data,
        remoteDisplayName: String?,
        pairingTranscriptHash: Data,
        pairRootKey: Data,
        createdAt: Date,
        pairingState: RemotePairingPersistenceState = .active,
        recoveryCommit: RemotePairingCommit? = nil,
        nextOutboundReconnectSequence: UInt64 = 1,
        highestAcceptedReconnectSequence: UInt64 = 0,
        version: UInt8 = RemotePairedDeviceRecord.currentVersion,
        decodeSelection: BelugaPairingCommitDecodeSelection = .actual
    ) throws {
        guard version == Self.currentVersion,
              !remoteUUIDIsZero(pairID),
              !remoteUUIDIsZero(commitID),
              !remoteUUIDIsZero(localDeviceID),
              !remoteUUIDIsZero(remoteDeviceID),
              localDeviceID != remoteDeviceID,
              localRole != remoteRole,
              localSigningPublicKey.count == 32,
              remoteSigningPublicKey.count == 32,
              !remoteConstantTimeEqual(localSigningPublicKey, remoteSigningPublicKey),
              remoteValidDisplayName(remoteDisplayName),
              pairingTranscriptHash.count == 32,
              pairRootKey.count == 32,
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              nextOutboundReconnectSequence > 0 else {
            throw RemoteSessionCoreError.invalidPairedDeviceRecord
        }

        self.version = version
        self.pairID = pairID
        self.commitID = commitID
        self.localDeviceID = localDeviceID
        self.localRole = localRole
        self.localSigningPublicKey = localSigningPublicKey
        self.remoteDeviceID = remoteDeviceID
        self.remoteRole = remoteRole
        self.remoteSigningPublicKey = remoteSigningPublicKey
        self.remoteDisplayName = remoteDisplayName
        self.pairingTranscriptHash = pairingTranscriptHash
        self.pairRootKey = pairRootKey
        self.createdAt = createdAt
        self.pairingState = pairingState
        self.recoveryCommit = recoveryCommit
        self.nextOutboundReconnectSequence = nextOutboundReconnectSequence
        self.highestAcceptedReconnectSequence = highestAcceptedReconnectSequence
        try validatePersistenceState(commitProducer: decodeSelection.producer(
            role: localRole, state: pairingState, cache: recoveryCommit?.phase
        ))
    }

    /// Stable, pair-scoped credential for exchanging only signed reconnect control messages.
    /// WebRTC SDP/ICE/media must use the fresh session credential from a reconnect handshake.
    public func availabilityLocator() throws -> RemoteAvailabilityLocator {
        // Availability is the authenticated recovery path for interrupted commits. Media and
        // reconnect APIs remain gated on `.active` below.
        return try RemoteAvailabilityLocator(
            pairRootKey: pairRootKey,
            pairID: pairID,
            pairingTranscriptHash: pairingTranscriptHash,
            localRole: localRole
        )
    }

    /// Derives the AEAD credential for one server-issued availability exchange.
    public func availabilityCredential(
        exchangeID: RemoteAvailabilityExchangeID
    ) throws -> RemoteRendezvousCredential {
        try availabilityLocator().credential(exchangeID: exchangeID)
    }

    public var description: String { "<redacted paired remote device>" }
    public var debugDescription: String { description }

    /// The safe resumption step for this record's persisted commit state.
    /// An invalid bridge does not mean an absent record or permission to reset pairing.
    public var recoveryAction: RemotePairingRecoveryAction {
        recoveryAction(using: .actual)
    }

    internal func recoveryAction(
        using producer: BelugaRustPairingCommitProducer
    ) -> RemotePairingRecoveryAction {
        do {
            let plan = try pairingCommitPlan(.recoveryAction, producer: producer)
            guard plan.decision == .ready else { return .invalidBridge }
            switch plan.action {
            case .none: return .none
            case .awaitProposal: return .awaitProposal
            case .issueProposal: return .issueProposal
            case .issueCompletion: return .issueCompletion
            case .exactCachedCommit:
                guard let recoveryCommit else { return .invalidBridge }
                return .resend(recoveryCommit)
            case .mintProposal, .mintAcknowledgement, .mintCompletion,
                 .mintActivation, .verifyStoredRecovery:
                return .invalidBridge
            }
        } catch {
            return .invalidBridge
        }
    }

    /// Reserves and signs a fresh viewer reconnect request. Persist the mutated record before
    /// transmitting `request`; that prevents a crash from reusing the same monotonic sequence.
    public mutating func beginReconnect(
        using identity: RemoteDeviceIdentity
    ) throws -> RemoteReconnectInitiator {
        try beginReconnect(
            using: identity,
            ephemeralPrivateKeyRawRepresentation: Curve25519.KeyAgreement.PrivateKey()
                .rawRepresentation,
            nonce: remoteRandomBytes(count: 32)
        )
    }

    internal mutating func beginReconnect(
        using identity: RemoteDeviceIdentity,
        ephemeralPrivateKeyRawRepresentation: Data,
        nonce: Data,
        counterProducer: BelugaRustReconnectCounterProducer = .actual
    ) throws -> RemoteReconnectInitiator {
        guard pairingState == .active else {
            throw RemoteSessionCoreError.invalidPairingCommit
        }
        try validateLocalIdentity(identity, expectedRole: .viewer)
        let proposal = try BelugaRustReconnectCounterBoundary.propose(
            nextOutbound: nextOutboundReconnectSequence,
            highestAccepted: highestAcceptedReconnectSequence,
            opcode: 0,
            requestSequence: 0,
            producer: counterProducer
        )
        let initiator = try RemoteReconnectInitiator(
            record: self,
            identity: identity,
            sequence: nextOutboundReconnectSequence,
            ephemeralPrivateKeyRawRepresentation: ephemeralPrivateKeyRawRepresentation,
            nonce: nonce
        )
        nextOutboundReconnectSequence = proposal.next_outbound
        return initiator
    }

    /// Authenticates a strictly newer viewer request and creates the matching host response.
    /// Persist the mutated record before sending the response so a replay remains rejected.
    public mutating func respond(
        to request: RemoteReconnectRequest,
        using identity: RemoteDeviceIdentity
    ) throws -> RemoteReconnectResponder {
        try respond(
            to: request,
            using: identity,
            ephemeralPrivateKeyRawRepresentation: Curve25519.KeyAgreement.PrivateKey()
                .rawRepresentation,
            nonce: remoteRandomBytes(count: 32)
        )
    }

    internal mutating func respond(
        to request: RemoteReconnectRequest,
        using identity: RemoteDeviceIdentity,
        ephemeralPrivateKeyRawRepresentation: Data,
        nonce: Data,
        counterProducer: BelugaRustReconnectCounterProducer = .actual
    ) throws -> RemoteReconnectResponder {
        guard pairingState == .active else {
            throw RemoteSessionCoreError.invalidPairingCommit
        }
        try validateLocalIdentity(identity, expectedRole: .host)
        try validate(request: request)
        let proposal = try BelugaRustReconnectCounterBoundary.propose(
            nextOutbound: nextOutboundReconnectSequence,
            highestAccepted: highestAcceptedReconnectSequence,
            opcode: 1,
            requestSequence: request.sequence,
            producer: counterProducer
        )
        let responder = try RemoteReconnectResponder(
            record: self,
            identity: identity,
            request: request,
            ephemeralPrivateKeyRawRepresentation: ephemeralPrivateKeyRawRepresentation,
            nonce: nonce
        )
        highestAcceptedReconnectSequence = proposal.highest_accepted
        return responder
    }

    /// Host-side, crash-safe proposal preparation. Persist this mutated record before send.
    public mutating func prepareProposal(
        using identity: RemoteDeviceIdentity
    ) throws -> RemotePairingCommit {
        try prepareProposal(using: identity, commitProducer: .actual)
    }

    internal mutating func prepareProposal(
        using identity: RemoteDeviceIdentity,
        commitProducer: BelugaRustPairingCommitProducer,
        constructionProbe: BelugaPairingCommitConstructionProbe = .none
    ) throws -> RemotePairingCommit {
        try validateLocalIdentity(identity, expectedRole: .host)
        let plan = try checkedPairingCommitPlan(.prepareProposal, producer: commitProducer)
        if plan.action == .exactCachedCommit { return try exactRecoveryCommit() }
        guard plan.action == .mintProposal else {
            throw RemoteSessionCoreError.invalidPairingCommitBridge
        }
        try constructionProbe.before(.proposal)
        let commit = try makeLocalCommit(phase: .proposal, identity: identity)
        try applyPairingCommitPlan(plan, mintedCommit: commit)
        return commit
    }

    /// Viewer-side, crash-safe acknowledgement preparation. The returned ACK is idempotent.
    /// Persist this mutated record before sending it.
    public mutating func prepareAcknowledgement(
        after proposal: RemotePairingCommit,
        using identity: RemoteDeviceIdentity
    ) throws -> RemotePairingCommit {
        try prepareAcknowledgement(after: proposal, using: identity, commitProducer: .actual)
    }

    internal mutating func prepareAcknowledgement(
        after proposal: RemotePairingCommit,
        using identity: RemoteDeviceIdentity,
        commitProducer: BelugaRustPairingCommitProducer,
        constructionProbe: BelugaPairingCommitConstructionProbe = .none
    ) throws -> RemotePairingCommit {
        try validateLocalIdentity(identity, expectedRole: .viewer)
        let plan = try checkedPairingCommitPlan(
            .prepareAcknowledgement, incoming: proposal, producer: commitProducer
        )
        // Issued replay retains the exact opaque cache, even an unusual known phase.
        // The actual supplied proposal has already been authenticated above.
        if plan.action == .exactCachedCommit { return try exactRecoveryCommit() }
        guard plan.action == .mintAcknowledgement else {
            throw RemoteSessionCoreError.invalidPairingCommitBridge
        }
        try constructionProbe.before(.acknowledgement)
        let acknowledgement = try makeLocalCommit(phase: .acknowledgement, identity: identity)
        try applyPairingCommitPlan(plan, mintedCommit: acknowledgement)
        return acknowledgement
    }

    /// Host persists the high-water commit state before preparing a completion.
    public mutating func acceptAcknowledgement(_ acknowledgement: RemotePairingCommit) throws {
        try acceptAcknowledgement(acknowledgement, commitProducer: .actual)
    }

    internal mutating func acceptAcknowledgement(
        _ acknowledgement: RemotePairingCommit,
        commitProducer: BelugaRustPairingCommitProducer
    ) throws {
        let plan = try checkedPairingCommitPlan(
            .acceptAcknowledgement, incoming: acknowledgement, producer: commitProducer
        )
        guard plan.action == .none else {
            throw RemoteSessionCoreError.invalidPairingCommitBridge
        }
        try applyPairingCommitPlan(plan)
    }

    /// Host prepares an idempotent completion. Persist this state before transmitting it.
    public mutating func prepareCompletion(
        using identity: RemoteDeviceIdentity
    ) throws -> RemotePairingCommit {
        try prepareCompletion(using: identity, commitProducer: .actual)
    }

    internal mutating func prepareCompletion(
        using identity: RemoteDeviceIdentity,
        commitProducer: BelugaRustPairingCommitProducer,
        constructionProbe: BelugaPairingCommitConstructionProbe = .none
    ) throws -> RemotePairingCommit {
        try validateLocalIdentity(identity, expectedRole: .host)
        let plan = try checkedPairingCommitPlan(.prepareCompletion, producer: commitProducer)
        if plan.action == .exactCachedCommit { return try exactRecoveryCommit() }
        guard plan.action == .mintCompletion else {
            throw RemoteSessionCoreError.invalidPairingCommitBridge
        }
        try constructionProbe.before(.completion)
        let completion = try makeLocalCommit(phase: .completion, identity: identity)
        // Active host replay remains ephemeral: the candidate is active/nil.
        try applyPairingCommitPlan(plan, mintedCommit: completion)
        return completion
    }

    /// Records a successful send, but deliberately does not activate the host. Only the
    /// viewer's signed activation acknowledgement can do that.
    public mutating func markCompletionSent(commitID: UUID) throws {
        try markCompletionSent(commitID: commitID, commitProducer: .actual)
    }

    internal mutating func markCompletionSent(
        commitID: UUID,
        commitProducer: BelugaRustPairingCommitProducer
    ) throws {
        _ = try checkedPairingCommitPlan(
            .markCompletionSent,
            commitIDMatches: self.commitID == commitID,
            producer: commitProducer
        )
        // Boundary requires an exact unchanged candidate. Send never activates or retires.
    }

    /// Viewer authenticates completion, persists active state, and returns an idempotent signed
    /// activation acknowledgement. Persist the record before sending the returned value.
    public mutating func acceptCompletion(
        _ completion: RemotePairingCommit,
        using identity: RemoteDeviceIdentity
    ) throws -> RemotePairingCommit {
        try acceptCompletion(completion, using: identity, commitProducer: .actual)
    }

    internal mutating func acceptCompletion(
        _ completion: RemotePairingCommit,
        using identity: RemoteDeviceIdentity,
        commitProducer: BelugaRustPairingCommitProducer,
        constructionProbe: BelugaPairingCommitConstructionProbe = .none
    ) throws -> RemotePairingCommit {
        try validateLocalIdentity(identity, expectedRole: .viewer)
        let plan = try checkedPairingCommitPlan(
            .acceptCompletion, incoming: completion, producer: commitProducer
        )
        // Active/missing-cache refusal is post-auth, not a pre-auth cache check.
        if plan.action == .exactCachedCommit { return try exactRecoveryCommit() }
        guard plan.action == .mintActivation else {
            throw RemoteSessionCoreError.invalidPairingCommitBridge
        }
        try constructionProbe.before(.activationAcknowledgement)
        let acknowledgement = try makeLocalCommit(
            phase: .activationAcknowledgement,
            identity: identity
        )
        try applyPairingCommitPlan(plan, mintedCommit: acknowledgement)
        return acknowledgement
    }

    /// Host becomes active only after the viewer proves durable receipt of completion.
    public mutating func acceptActivationAcknowledgement(
        _ acknowledgement: RemotePairingCommit
    ) throws {
        try acceptActivationAcknowledgement(acknowledgement, commitProducer: .actual)
    }

    internal mutating func acceptActivationAcknowledgement(
        _ acknowledgement: RemotePairingCommit,
        commitProducer: BelugaRustPairingCommitProducer
    ) throws {
        let plan = try checkedPairingCommitPlan(
            .acceptActivationAcknowledgement, incoming: acknowledgement, producer: commitProducer
        )
        guard plan.action == .none else {
            throw RemoteSessionCoreError.invalidPairingCommitBridge
        }
        try applyPairingCommitPlan(plan)
    }

    private func pairingCommitPlan(
        _ operation: BelugaRustPairingCommitBoundary.Operation,
        commitIDMatches: Bool = false,
        producer: BelugaRustPairingCommitProducer
    ) throws -> BelugaRustPairingCommitBoundary.Plan {
        try BelugaRustPairingCommitBoundary.plan(
            before: BelugaRustPairingCommitBoundary.state(
                role: localRole,
                pairingState: pairingState,
                recoveryPhase: recoveryCommit?.phase
            ),
            event: BelugaRustPairingCommitBoundary.event(
                operation, commitIDMatches: commitIDMatches
            ),
            producer: producer
        )
    }

    private func checkedPairingCommitPlan(
        _ operation: BelugaRustPairingCommitBoundary.Operation,
        incoming: RemotePairingCommit? = nil,
        commitIDMatches: Bool = false,
        producer: BelugaRustPairingCommitProducer
    ) throws -> BelugaRustPairingCommitBoundary.Plan {
        let plan = try pairingCommitPlan(
            operation, commitIDMatches: commitIDMatches, producer: producer
        )
        switch plan.decision {
        case .preAuthRejected: throw RemoteSessionCoreError.invalidPairingCommit
        case .invalidStoredShape: throw RemoteSessionCoreError.invalidPairedDeviceRecord
        case .invalidInput: throw RemoteSessionCoreError.invalidPairingCommitBridge
        case .ready, .postAuthRejected: break
        }
        switch plan.auth {
        case .none: break
        case .proposal, .acknowledgement, .completion, .activation:
            guard let incoming else { throw RemoteSessionCoreError.invalidPairingCommitBridge }
            let expectedPhase: RemotePairingCommitPhase = switch plan.auth {
            case .proposal: .proposal
            case .acknowledgement: .acknowledgement
            case .completion: .completion
            case .activation: .activationAcknowledgement
            case .none: throw RemoteSessionCoreError.invalidPairingCommitBridge
            }
            try verifyPeerCommit(incoming, expectedPhase: expectedPhase)
        }
        if plan.decision == .postAuthRejected {
            throw RemoteSessionCoreError.invalidPairingCommit
        }
        return plan
    }

    private func exactRecoveryCommit() throws -> RemotePairingCommit {
        guard let recoveryCommit else {
            throw RemoteSessionCoreError.invalidPairingCommitBridge
        }
        return recoveryCommit
    }

    /// Commits only the prevalidated candidate after real auth/constructor success.
    /// No FFI call occurs here; counters, immutable fields and encoding are untouched.
    private mutating func applyPairingCommitPlan(
        _ plan: BelugaRustPairingCommitBoundary.Plan,
        mintedCommit: RemotePairingCommit? = nil
    ) throws {
        let nextRecovery: RemotePairingCommit?
        if let mintedCommit {
            let expectedMintPhase: RemotePairingCommitPhase
            switch plan.action {
            case .mintProposal: expectedMintPhase = .proposal
            case .mintAcknowledgement: expectedMintPhase = .acknowledgement
            case .mintCompletion: expectedMintPhase = .completion
            case .mintActivation: expectedMintPhase = .activationAcknowledgement
            case .none, .awaitProposal, .issueProposal, .exactCachedCommit,
                 .issueCompletion, .verifyStoredRecovery:
                throw RemoteSessionCoreError.invalidPairingCommitBridge
            }
            guard mintedCommit.phase == expectedMintPhase else {
                throw RemoteSessionCoreError.invalidPairingCommitBridge
            }
            if let candidatePhase = plan.candidateRecoveryPhase {
                guard mintedCommit.phase == candidatePhase else {
                    throw RemoteSessionCoreError.invalidPairingCommitBridge
                }
                nextRecovery = mintedCommit
            } else {
                // The sole admitted ephemeral mint is active-host completion replay.
                nextRecovery = nil
            }
        } else if let candidatePhase = plan.candidateRecoveryPhase {
            guard let recoveryCommit, recoveryCommit.phase == candidatePhase else {
                throw RemoteSessionCoreError.invalidPairingCommitBridge
            }
            nextRecovery = recoveryCommit
        } else {
            nextRecovery = nil
        }
        pairingState = plan.candidatePairingState
        recoveryCommit = nextRecovery
    }

    internal var rootKeyMaterial: Data { pairRootKey }

    private func makeLocalCommit(
        phase: RemotePairingCommitPhase,
        identity: RemoteDeviceIdentity
    ) throws -> RemotePairingCommit {
        let validRole = switch phase {
        case .proposal, .completion: localRole == .host
        case .acknowledgement, .activationAcknowledgement: localRole == .viewer
        }
        guard validRole else { throw RemoteSessionCoreError.invalidPairingCommit }
        let unsigned = RemotePairingCommitUnsigned(
            protocolVersion: RemotePairingCommit.currentProtocolVersion,
            pairID: pairID,
            commitID: commitID,
            senderDeviceID: localDeviceID,
            senderRole: localRole,
            recipientDeviceID: remoteDeviceID,
            transcriptHash: pairingTranscriptHash,
            phase: phase
        )
        let canonical = try remoteCanonicalData(unsigned)
        let tag = remoteHMAC(
            key: commitKey(senderRole: localRole, phase: phase),
            data: remoteDomainSeparated(
                "AudioStreamer.Pairing.Commit.MAC.v1",
                canonical
            )
        )
        return RemotePairingCommit(
            protocolVersion: unsigned.protocolVersion,
            pairID: unsigned.pairID,
            commitID: unsigned.commitID,
            senderDeviceID: unsigned.senderDeviceID,
            senderRole: unsigned.senderRole,
            recipientDeviceID: unsigned.recipientDeviceID,
            transcriptHash: unsigned.transcriptHash,
            phase: unsigned.phase,
            commitTag: tag,
            signature: try identity.signature(
                for: remoteDomainSeparated(
                    "AudioStreamer.Pairing.Commit.Signature.v1",
                    canonical,
                    tag
                )
            )
        )
    }

    private func verifyPeerCommit(
        _ commit: RemotePairingCommit,
        expectedPhase: RemotePairingCommitPhase
    ) throws {
        guard commit.isStructurallyValid,
              commit.pairID == pairID,
              commit.commitID == commitID,
              commit.senderDeviceID == remoteDeviceID,
              commit.senderRole == remoteRole,
              commit.recipientDeviceID == localDeviceID,
              commit.phase == expectedPhase,
              remoteConstantTimeEqual(commit.transcriptHash, pairingTranscriptHash) else {
            throw RemoteSessionCoreError.invalidPairingCommit
        }
        let canonical = try remoteCanonicalData(commit.unsigned)
        let expectedTag = remoteHMAC(
            key: commitKey(senderRole: remoteRole, phase: expectedPhase),
            data: remoteDomainSeparated(
                "AudioStreamer.Pairing.Commit.MAC.v1",
                canonical
            )
        )
        guard remoteConstantTimeEqual(commit.commitTag, expectedTag),
              remoteVerifySignature(
                commit.signature,
                for: remoteDomainSeparated(
                    "AudioStreamer.Pairing.Commit.Signature.v1",
                    canonical,
                    commit.commitTag
                ),
                publicKey: remoteSigningPublicKey
              ) else {
            throw RemoteSessionCoreError.authenticationFailed
        }
    }

    private func commitKey(
        senderRole: RemotePeerRole,
        phase: RemotePairingCommitPhase
    ) -> Data {
        remoteHKDF(
            input: pairRootKey,
            salt: pairingTranscriptHash,
            label: "AudioStreamer.Pairing.Commit.\(senderRole.rawValue).\(phase.rawValue).v1"
        )
    }

    internal func validatePersistenceState(
        commitProducer: BelugaRustPairingCommitProducer = .actual
    ) throws {
        let plan = try checkedPairingCommitPlan(.validateStoredShape, producer: commitProducer)
        guard let recoveryCommit else { return }
        guard plan.action == .verifyStoredRecovery,
              let expectedRecoveryPhase = plan.candidateRecoveryPhase,
              recoveryCommit.protocolVersion == RemotePairingCommit.currentProtocolVersion,
              recoveryCommit.isStructurallyValid,
              recoveryCommit.phase == expectedRecoveryPhase,
              recoveryCommit.pairID == pairID,
              recoveryCommit.commitID == commitID,
              recoveryCommit.senderDeviceID == localDeviceID,
              recoveryCommit.senderRole == localRole,
              recoveryCommit.recipientDeviceID == remoteDeviceID,
              remoteConstantTimeEqual(
                recoveryCommit.transcriptHash,
                pairingTranscriptHash
              ) else {
            throw RemoteSessionCoreError.invalidPairedDeviceRecord
        }
        let canonical: Data
        do {
            canonical = try remoteCanonicalData(recoveryCommit.unsigned)
        } catch {
            throw RemoteSessionCoreError.invalidPairedDeviceRecord
        }
        let expectedTag = remoteHMAC(
            key: commitKey(senderRole: localRole, phase: expectedRecoveryPhase),
            data: remoteDomainSeparated(
                "AudioStreamer.Pairing.Commit.MAC.v1",
                canonical
            )
        )
        guard remoteConstantTimeEqual(recoveryCommit.commitTag, expectedTag),
              remoteVerifySignature(
                recoveryCommit.signature,
                for: remoteDomainSeparated(
                    "AudioStreamer.Pairing.Commit.Signature.v1",
                    canonical,
                    recoveryCommit.commitTag
                ),
                publicKey: localSigningPublicKey
              ) else {
            throw RemoteSessionCoreError.invalidPairedDeviceRecord
        }
    }

    internal func validateLocalIdentity(
        _ identity: RemoteDeviceIdentity,
        expectedRole: RemotePeerRole
    ) throws {
        guard localRole == expectedRole,
              identity.matches(
                deviceID: localDeviceID,
                role: localRole,
                publicKey: localSigningPublicKey
              ) else {
            throw RemoteSessionCoreError.deviceIdentityMismatch
        }
    }

    internal func validate(request: RemoteReconnectRequest) throws {
        guard request.protocolVersion == RemoteReconnectRequest.currentProtocolVersion else {
            throw RemoteSessionCoreError.unsupportedReconnectVersion
        }
        guard request.isStructurallyValid,
              request.pairID == pairID,
              request.requesterDeviceID == remoteDeviceID,
              request.requesterRole == remoteRole,
              request.targetDeviceID == localDeviceID,
              remoteRole == .viewer,
              localRole == .host else {
            throw RemoteSessionCoreError.invalidReconnectMessage
        }
        let unsigned = try remoteCanonicalData(request.unsigned)
        guard remoteVerifySignature(
            request.signature,
            for: remoteDomainSeparated(
                "AudioStreamer.Reconnect.Request.Signature.v1",
                unsigned
            ),
            publicKey: remoteSigningPublicKey
        ) else {
            throw RemoteSessionCoreError.authenticationFailed
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case pairID
        case commitID
        case localDeviceID
        case localRole
        case localSigningPublicKey
        case remoteDeviceID
        case remoteRole
        case remoteSigningPublicKey
        case remoteDisplayName
        case pairingTranscriptHash
        case pairRootKey
        case createdAt
        case pairingState
        case recoveryCommit
        case nextOutboundReconnectSequence
        case highestAcceptedReconnectSequence
    }

    public init(from decoder: any Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                pairID: container.decode(UUID.self, forKey: .pairID),
                commitID: container.decode(UUID.self, forKey: .commitID),
                localDeviceID: container.decode(UUID.self, forKey: .localDeviceID),
                localRole: container.decode(RemotePeerRole.self, forKey: .localRole),
                localSigningPublicKey: container.decode(Data.self, forKey: .localSigningPublicKey),
                remoteDeviceID: container.decode(UUID.self, forKey: .remoteDeviceID),
                remoteRole: container.decode(RemotePeerRole.self, forKey: .remoteRole),
                remoteSigningPublicKey: container.decode(Data.self, forKey: .remoteSigningPublicKey),
                remoteDisplayName: container.decodeIfPresent(String.self, forKey: .remoteDisplayName),
                pairingTranscriptHash: container.decode(Data.self, forKey: .pairingTranscriptHash),
                pairRootKey: container.decode(Data.self, forKey: .pairRootKey),
                createdAt: container.decode(Date.self, forKey: .createdAt),
                pairingState: container.decode(
                    RemotePairingPersistenceState.self,
                    forKey: .pairingState
                ),
                recoveryCommit: container.decodeIfPresent(
                    RemotePairingCommit.self,
                    forKey: .recoveryCommit
                ),
                nextOutboundReconnectSequence: container.decode(
                    UInt64.self,
                    forKey: .nextOutboundReconnectSequence
                ),
                highestAcceptedReconnectSequence: container.decode(
                    UInt64.self,
                    forKey: .highestAcceptedReconnectSequence
                ),
                version: container.decode(UInt8.self, forKey: .version),
                decodeSelection: BelugaPairingCommitDecodeSelection.capture(from: decoder)
            )
        } catch let error as RemoteSessionCoreError {
            throw error
        } catch {
            throw RemoteSessionCoreError.invalidPairedDeviceRecord
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(pairID, forKey: .pairID)
        try container.encode(commitID, forKey: .commitID)
        try container.encode(localDeviceID, forKey: .localDeviceID)
        try container.encode(localRole, forKey: .localRole)
        try container.encode(localSigningPublicKey, forKey: .localSigningPublicKey)
        try container.encode(remoteDeviceID, forKey: .remoteDeviceID)
        try container.encode(remoteRole, forKey: .remoteRole)
        try container.encode(remoteSigningPublicKey, forKey: .remoteSigningPublicKey)
        try container.encodeIfPresent(remoteDisplayName, forKey: .remoteDisplayName)
        try container.encode(pairingTranscriptHash, forKey: .pairingTranscriptHash)
        try container.encode(pairRootKey, forKey: .pairRootKey)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(pairingState, forKey: .pairingState)
        try container.encodeIfPresent(recoveryCommit, forKey: .recoveryCommit)
        try container.encode(nextOutboundReconnectSequence, forKey: .nextOutboundReconnectSequence)
        try container.encode(
            highestAcceptedReconnectSequence,
            forKey: .highestAcceptedReconnectSequence
        )
    }
}

/// A signed, monotonic request carrying the initiator's ephemeral key and replay nonce.
public struct RemoteReconnectRequest: Codable, Equatable, Sendable {
    public static let currentProtocolVersion: UInt8 = 1

    public let protocolVersion: UInt8
    public let pairID: UUID
    public let requesterDeviceID: UUID
    public let requesterRole: RemotePeerRole
    public let targetDeviceID: UUID
    public let sequence: UInt64
    public let ephemeralKeyAgreementPublicKey: Data
    public let nonce: Data
    public let signature: Data

    internal var unsigned: RemoteReconnectRequestUnsigned {
        RemoteReconnectRequestUnsigned(
            protocolVersion: protocolVersion,
            pairID: pairID,
            requesterDeviceID: requesterDeviceID,
            requesterRole: requesterRole,
            targetDeviceID: targetDeviceID,
            sequence: sequence,
            ephemeralKeyAgreementPublicKey: ephemeralKeyAgreementPublicKey,
            nonce: nonce
        )
    }

    internal var isStructurallyValid: Bool {
        protocolVersion == Self.currentProtocolVersion
            && !remoteUUIDIsZero(pairID)
            && !remoteUUIDIsZero(requesterDeviceID)
            && !remoteUUIDIsZero(targetDeviceID)
            && requesterDeviceID != targetDeviceID
            && requesterRole == .viewer
            && sequence > 0
            && ephemeralKeyAgreementPublicKey.count == 32
            && nonce.count == 32
            && signature.count == 64
    }
}

/// A signed response bound to the exact reconnect request and responder ephemeral key.
public struct RemoteReconnectResponse: Codable, Equatable, Sendable {
    public static let currentProtocolVersion: UInt8 = 1

    public let protocolVersion: UInt8
    public let pairID: UUID
    public let requesterDeviceID: UUID
    public let responderDeviceID: UUID
    public let responderRole: RemotePeerRole
    public let requestSequence: UInt64
    public let requestDigest: Data
    public let ephemeralKeyAgreementPublicKey: Data
    public let nonce: Data
    public let signature: Data

    internal var unsigned: RemoteReconnectResponseUnsigned {
        RemoteReconnectResponseUnsigned(
            protocolVersion: protocolVersion,
            pairID: pairID,
            requesterDeviceID: requesterDeviceID,
            responderDeviceID: responderDeviceID,
            responderRole: responderRole,
            requestSequence: requestSequence,
            requestDigest: requestDigest,
            ephemeralKeyAgreementPublicKey: ephemeralKeyAgreementPublicKey,
            nonce: nonce
        )
    }

    internal var isStructurallyValid: Bool {
        protocolVersion == Self.currentProtocolVersion
            && !remoteUUIDIsZero(pairID)
            && !remoteUUIDIsZero(requesterDeviceID)
            && !remoteUUIDIsZero(responderDeviceID)
            && requesterDeviceID != responderDeviceID
            && responderRole == .host
            && requestSequence > 0
            && requestDigest.count == 32
            && ephemeralKeyAgreementPublicKey.count == 32
            && nonce.count == 32
            && signature.count == 64
    }
}

/// Ephemeral initiator state retained only until a reconnect response is verified.
public struct RemoteReconnectInitiator: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible {
    public let request: RemoteReconnectRequest

    private let record: RemotePairedDeviceRecord
    private let ephemeralPrivateKey: Data

    internal init(
        record: RemotePairedDeviceRecord,
        identity: RemoteDeviceIdentity,
        sequence: UInt64,
        ephemeralPrivateKeyRawRepresentation: Data,
        nonce: Data
    ) throws {
        guard record.localRole == .viewer,
              record.remoteRole == .host,
              sequence > 0,
              ephemeralPrivateKeyRawRepresentation.count == 32,
              nonce.count == 32 else {
            throw RemoteSessionCoreError.invalidReconnectMessage
        }
        let ephemeral: Curve25519.KeyAgreement.PrivateKey
        do {
            ephemeral = try Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: ephemeralPrivateKeyRawRepresentation
            )
        } catch {
            throw RemoteSessionCoreError.invalidReconnectMessage
        }
        let unsigned = RemoteReconnectRequestUnsigned(
            protocolVersion: RemoteReconnectRequest.currentProtocolVersion,
            pairID: record.pairID,
            requesterDeviceID: record.localDeviceID,
            requesterRole: .viewer,
            targetDeviceID: record.remoteDeviceID,
            sequence: sequence,
            ephemeralKeyAgreementPublicKey: ephemeral.publicKey.rawRepresentation,
            nonce: nonce
        )
        let canonical = try remoteCanonicalData(unsigned)
        request = RemoteReconnectRequest(
            protocolVersion: unsigned.protocolVersion,
            pairID: unsigned.pairID,
            requesterDeviceID: unsigned.requesterDeviceID,
            requesterRole: unsigned.requesterRole,
            targetDeviceID: unsigned.targetDeviceID,
            sequence: unsigned.sequence,
            ephemeralKeyAgreementPublicKey: unsigned.ephemeralKeyAgreementPublicKey,
            nonce: unsigned.nonce,
            signature: try identity.signature(
                for: remoteDomainSeparated(
                    "AudioStreamer.Reconnect.Request.Signature.v1",
                    canonical
                )
            )
        )
        self.record = record
        ephemeralPrivateKey = ephemeralPrivateKeyRawRepresentation
    }

    public var description: String { "<redacted remote reconnect initiator>" }
    public var debugDescription: String { description }

    /// Verifies the response and derives a fresh session-only rendezvous credential.
    public func complete(
        with response: RemoteReconnectResponse
    ) throws -> RemoteRendezvousCredential {
        guard response.protocolVersion == RemoteReconnectResponse.currentProtocolVersion else {
            throw RemoteSessionCoreError.unsupportedReconnectVersion
        }
        let expectedRequestDigest = remoteSHA256(try remoteCanonicalData(request))
        guard response.isStructurallyValid,
              response.pairID == record.pairID,
              response.requesterDeviceID == record.localDeviceID,
              response.responderDeviceID == record.remoteDeviceID,
              response.responderRole == .host,
              response.requestSequence == request.sequence,
              remoteConstantTimeEqual(response.requestDigest, expectedRequestDigest) else {
            throw RemoteSessionCoreError.invalidReconnectMessage
        }
        let canonicalResponse = try remoteCanonicalData(response.unsigned)
        guard remoteVerifySignature(
            response.signature,
            for: remoteDomainSeparated(
                "AudioStreamer.Reconnect.Response.Signature.v1",
                canonicalResponse
            ),
            publicKey: record.remoteSigningPublicKey
        ) else {
            throw RemoteSessionCoreError.authenticationFailed
        }

        let privateKey: Curve25519.KeyAgreement.PrivateKey
        let publicKey: Curve25519.KeyAgreement.PublicKey
        do {
            privateKey = try Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: ephemeralPrivateKey
            )
            publicKey = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: response.ephemeralKeyAgreementPublicKey
            )
        } catch {
            throw RemoteSessionCoreError.invalidReconnectMessage
        }
        let shared: SharedSecret
        do {
            shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        } catch {
            throw RemoteSessionCoreError.authenticationFailed
        }
        guard !remoteIsAllZero(shared.withUnsafeBytes { Data($0) }) else {
            throw RemoteSessionCoreError.authenticationFailed
        }
        return try remoteSessionCredential(
            record: record,
            request: request,
            response: response,
            sharedSecret: shared
        )
    }
}

/// A verified reconnect response paired with the fresh session-only credential it derives.
public struct RemoteReconnectResponder: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible {
    public let response: RemoteReconnectResponse
    public let credential: RemoteRendezvousCredential

    internal init(
        record: RemotePairedDeviceRecord,
        identity: RemoteDeviceIdentity,
        request: RemoteReconnectRequest,
        ephemeralPrivateKeyRawRepresentation: Data,
        nonce: Data
    ) throws {
        guard record.localRole == .host,
              record.remoteRole == .viewer,
              ephemeralPrivateKeyRawRepresentation.count == 32,
              nonce.count == 32 else {
            throw RemoteSessionCoreError.invalidReconnectMessage
        }
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        let requesterPublicKey: Curve25519.KeyAgreement.PublicKey
        do {
            privateKey = try Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: ephemeralPrivateKeyRawRepresentation
            )
            requesterPublicKey = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: request.ephemeralKeyAgreementPublicKey
            )
        } catch {
            throw RemoteSessionCoreError.invalidReconnectMessage
        }
        let requestDigest = remoteSHA256(try remoteCanonicalData(request))
        let unsigned = RemoteReconnectResponseUnsigned(
            protocolVersion: RemoteReconnectResponse.currentProtocolVersion,
            pairID: record.pairID,
            requesterDeviceID: request.requesterDeviceID,
            responderDeviceID: record.localDeviceID,
            responderRole: .host,
            requestSequence: request.sequence,
            requestDigest: requestDigest,
            ephemeralKeyAgreementPublicKey: privateKey.publicKey.rawRepresentation,
            nonce: nonce
        )
        let canonical = try remoteCanonicalData(unsigned)
        let builtResponse = RemoteReconnectResponse(
            protocolVersion: unsigned.protocolVersion,
            pairID: unsigned.pairID,
            requesterDeviceID: unsigned.requesterDeviceID,
            responderDeviceID: unsigned.responderDeviceID,
            responderRole: unsigned.responderRole,
            requestSequence: unsigned.requestSequence,
            requestDigest: unsigned.requestDigest,
            ephemeralKeyAgreementPublicKey: unsigned.ephemeralKeyAgreementPublicKey,
            nonce: unsigned.nonce,
            signature: try identity.signature(
                for: remoteDomainSeparated(
                    "AudioStreamer.Reconnect.Response.Signature.v1",
                    canonical
                )
            )
        )
        let shared: SharedSecret
        do {
            shared = try privateKey.sharedSecretFromKeyAgreement(with: requesterPublicKey)
        } catch {
            throw RemoteSessionCoreError.authenticationFailed
        }
        guard !remoteIsAllZero(shared.withUnsafeBytes { Data($0) }) else {
            throw RemoteSessionCoreError.authenticationFailed
        }
        response = builtResponse
        credential = try remoteSessionCredential(
            record: record,
            request: request,
            response: builtResponse,
            sharedSecret: shared
        )
    }

    public var description: String { "<redacted remote reconnect responder>" }
    public var debugDescription: String { description }
}

/// Canonical request fields covered by the initiator's signature.
internal struct RemoteReconnectRequestUnsigned: Codable {
    let protocolVersion: UInt8
    let pairID: UUID
    let requesterDeviceID: UUID
    let requesterRole: RemotePeerRole
    let targetDeviceID: UUID
    let sequence: UInt64
    let ephemeralKeyAgreementPublicKey: Data
    let nonce: Data
}

/// Canonical response fields covered by the responder's signature.
internal struct RemoteReconnectResponseUnsigned: Codable {
    let protocolVersion: UInt8
    let pairID: UUID
    let requesterDeviceID: UUID
    let responderDeviceID: UUID
    let responderRole: RemotePeerRole
    let requestSequence: UInt64
    let requestDigest: Data
    let ephemeralKeyAgreementPublicKey: Data
    let nonce: Data
}

private struct RemoteReconnectTranscript: Codable {
    let request: RemoteReconnectRequest
    let response: RemoteReconnectResponse
}

private func remoteSessionCredential(
    record: RemotePairedDeviceRecord,
    request: RemoteReconnectRequest,
    response: RemoteReconnectResponse,
    sharedSecret: SharedSecret
) throws -> RemoteRendezvousCredential {
    let transcript = RemoteReconnectTranscript(request: request, response: response)
    let transcriptHash = remoteSHA256(
        remoteDomainSeparated(
            "AudioStreamer.Reconnect.Transcript.v1",
            try remoteCanonicalData(transcript)
        )
    )
    var keyMaterial = Data()
    keyMaterial.append(record.rootKeyMaterial)
    keyMaterial.append(sharedSecret.withUnsafeBytes { Data($0) })
    let sessionRoot = remoteHKDF(
        input: keyMaterial,
        salt: transcriptHash,
        label: "AudioStreamer.Reconnect.SessionRoot.v1"
    )
    return try RemoteRendezvousCredential(
        keyMaterial: sessionRoot,
        salt: transcriptHash,
        context: "session"
    )
}
