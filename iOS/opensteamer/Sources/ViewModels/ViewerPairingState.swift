import Combine
import Foundation
import RemoteSessionCore

/// Main-actor projection of the durable iPhone identity and paired Mac.
///
/// Hydration is intentionally synchronous in `init`: SwiftUI never gets an initial empty
/// pairing state that can race a later Keychain read during process or view reconstruction.
@MainActor
final class ViewerPairingState: ObservableObject {
    @Published private(set) var viewerIdentity: RemoteDeviceIdentity?
    @Published private(set) var pairingRecord: RemotePairedDeviceRecord?
    @Published private(set) var savedMacs: [RemotePairedDeviceRecord] = []
    @Published private(set) var storageError: String?

    private let store: any ViewerPairingStoring
    private var hydrationNeedsRetry = false

    init(store: any ViewerPairingStoring = ViewerPairedMacCatalogStore()) {
        self.store = store
        hydrateSynchronously()
    }

    /// Only a role-correct, fully active record is exposed as a usable paired Mac. Earlier
    /// durable states remain available through `pairingRecord` solely for crash recovery.
    var pairedMac: RemotePairedDeviceRecord? {
        guard pairingRecord?.pairingState == .active else { return nil }
        return pairingRecord
    }

    var isPaired: Bool { pairedMac != nil }

    var recoveryAction: RemotePairingRecoveryAction? {
        pairingRecord?.recoveryAction
    }

    /// Retries only a failed Keychain hydration, such as protected data being unavailable
    /// before the first device unlock. Successful state is never redundantly reloaded, and a
    /// failure never rotates an identity, deletes a record, or overwrites either Keychain item.
    func retryHydrationIfNeeded() {
        guard hydrationNeedsRetry else { return }
        hydrateSynchronously()
    }

    /// Persists a role-valid viewer record at any crash-safe pairing phase.
    func savePairingRecord(_ record: RemotePairedDeviceRecord) throws {
        try savePairingRecord(record, bootstrapInvitation: nil)
    }

    /// Record and invitation digest are committed atomically in the multi-Mac catalog. The
    /// one global entry field must never authorize recovery of a different selected Mac.
    func savePairingRecord(_ record: RemotePairedDeviceRecord, bootstrapInvitation: String?) throws {
        guard let viewerIdentity else {
            storageError = "This iPhone's secure pairing identity is unavailable."
            throw ViewerPairingStateError.viewerIdentityUnavailable
        }

        do {
            if let bootstrapInvitation, let catalog = store as? any ViewerPairedMacCatalogStoring {
                try catalog.saveBootstrapPair(record, invitationCode: bootstrapInvitation, for: viewerIdentity)
            } else {
                try store.savePairedMac(record, for: viewerIdentity)
            }
            let saved = try savedRecords(for: viewerIdentity, selected: record)
            pairingRecord = record
            savedMacs = saved
            storageError = nil
        } catch {
            storageError = "The authenticated Mac pairing could not be saved securely."
            throw error
        }
    }

    func recoveryInvitationMatchesSelectedMac(_ invitationCode: String) throws -> Bool {
        guard let viewerIdentity, let pairingRecord else { return false }
        guard let catalog = store as? any ViewerPairedMacCatalogStoring else {
            // Original single-pair embedders retain their established recovery API.
            return true
        }
        return try catalog.recoveryInvitationMatches(invitationCode, record: pairingRecord,
                                                     for: viewerIdentity)
    }

    var boundRecoveryMac: RemotePairedDeviceRecord? {
        store is any ViewerPairedMacCatalogStoring ? pairingRecord : nil
    }

    /// This boundary accepts only a record returned by the authenticated pairing protocol's
    /// final commit. Callers must persist successfully before erasing the one-time invitation.
    func saveAuthenticatedPairing(_ record: RemotePairedDeviceRecord) throws {
        guard record.pairingState == .active else {
            storageError = "The Mac pairing has not completed authentication yet."
            throw ViewerPairingStateError.pairingIsNotActive
        }
        try savePairingRecord(record)
    }

    /// Explicit user revocation. Forgetting a Mac never deletes or rotates this iPhone's
    /// long-lived identity, so a later authenticated pairing can reuse the stable device ID.
    func forgetPairedMac() throws {
        do {
            try store.deletePairedMac()
            pairingRecord = nil
            if let viewerIdentity { savedMacs = try savedRecords(for: viewerIdentity, selected: nil) }
            storageError = nil
        } catch {
            storageError = "The paired Mac could not be forgotten securely."
            throw error
        }
    }

    /// Call only after the prior connection and preparation have been retired.
    func selectMac(_ deviceID: UUID?) throws {
        guard let identity = viewerIdentity,
              let catalog = store as? any ViewerPairedMacCatalogStoring else {
            throw ViewerPairingStateError.viewerIdentityUnavailable
        }
        do {
            try catalog.selectMac(deviceID, for: identity)
            pairingRecord = try store.loadPairedMac(for: identity)
            savedMacs = try catalog.loadSavedMacs(for: identity)
            storageError = nil
        } catch {
            storageError = "The saved Mac selection could not be changed securely."
            throw error
        }
    }

    func forgetMac(_ deviceID: UUID) throws {
        guard let identity = viewerIdentity,
              let catalog = store as? any ViewerPairedMacCatalogStoring else {
            throw ViewerPairingStateError.viewerIdentityUnavailable
        }
        do {
            try catalog.forgetMac(deviceID, for: identity)
            pairingRecord = try store.loadPairedMac(for: identity)
            savedMacs = try catalog.loadSavedMacs(for: identity)
            storageError = nil
        } catch {
            storageError = "The selected Mac could not be forgotten securely."
            throw error
        }
    }

    private func savedRecords(
        for identity: RemoteDeviceIdentity, selected: RemotePairedDeviceRecord?
    ) throws -> [RemotePairedDeviceRecord] {
        if let catalog = store as? any ViewerPairedMacCatalogStoring {
            return try catalog.loadSavedMacs(for: identity)
        }
        return selected.map { [$0] } ?? []
    }

    private func hydrateSynchronously() {
        do {
            let identity = try store.loadOrCreateViewerIdentity()
            viewerIdentity = identity
            pairingRecord = try store.loadPairedMac(for: identity)
            savedMacs = try savedRecords(for: identity, selected: pairingRecord)
            storageError = nil
            hydrationNeedsRetry = false
        } catch {
            // Never replace malformed or temporarily inaccessible Keychain state. Silent
            // regeneration could orphan a valid pairing or change the trusted device ID.
            viewerIdentity = nil
            pairingRecord = nil
            savedMacs = []
            storageError = "This iPhone's secure pairing state could not be loaded."
            hydrationNeedsRetry = true
        }
    }
}

/// Invalid transitions exposed by the main-actor pairing projection.
enum ViewerPairingStateError: Error, Equatable {
    case viewerIdentityUnavailable
    case pairingIsNotActive
}

/// Main-actor projection of the durable consume-once invitation boundary.
///
/// An admission marker is created only after a recoverable pairing record is durable. If its
/// matching saved invitation remains visible after a crash, the app resumes through that record
/// instead of retrying the one-time code. A different valid invitation has a different digest and
/// remains usable. Storage failures fail closed until protected Keychain data can be read.
@MainActor
final class WorldwideInvitationAdmissionState: ObservableObject {
    @Published private(set) var storageError: String?

    private let store: any WorldwideInvitationAdmissionStoring
    private var admittedDigest: Data?
    private var hydrationNeedsRetry = false

    init(
        store: any WorldwideInvitationAdmissionStoring =
            WorldwideInvitationAdmissionKeychainStore()
    ) {
        self.store = store
        hydrateSynchronously()
    }

    var canEvaluateAdmission: Bool { storageError == nil }

    func isAdmitted(_ invitationCode: String) -> Bool {
        guard let admittedDigest,
              let candidate = try? WorldwideInvitationAdmissionKeychainStore.digest(
                  for: invitationCode
              ) else {
            return false
        }
        return admittedDigest == candidate
    }

    /// Any unresolved marker read is treated as blocked, because automatically retrying while
    /// protected data is unavailable could consume or resubmit the wrong one-time credential.
    func blocksPairing(_ invitationCode: String) -> Bool {
        !canEvaluateAdmission || isAdmitted(invitationCode)
    }

    func markAdmitted(_ invitationCode: String) throws {
        let digest = try WorldwideInvitationAdmissionKeychainStore.digest(
            for: invitationCode
        )
        do {
            try store.saveAdmittedInvitationDigest(digest)
            admittedDigest = digest
            storageError = nil
            hydrationNeedsRetry = false
        } catch {
            storageError = "This invitation's one-time admission state could not be saved securely."
            hydrationNeedsRetry = true
            throw error
        }
    }

    @discardableResult
    func clearMarker() -> Bool {
        do {
            try store.deleteAdmittedInvitationDigest()
            admittedDigest = nil
            storageError = nil
            hydrationNeedsRetry = false
            return true
        } catch {
            storageError = "This invitation's one-time admission state could not be cleared securely."
            hydrationNeedsRetry = true
            return false
        }
    }

    func retryHydrationIfNeeded() {
        guard hydrationNeedsRetry else { return }
        hydrateSynchronously()
    }

    private func hydrateSynchronously() {
        do {
            admittedDigest = try store.loadAdmittedInvitationDigest()
            storageError = nil
            hydrationNeedsRetry = false
        } catch {
            admittedDigest = nil
            storageError = "This invitation's one-time admission state could not be loaded securely."
            hydrationNeedsRetry = true
        }
    }
}
