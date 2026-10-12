import Foundation
import RemoteSessionCore
@testable import CaptureServer

/// ORIGINAL-only native ordered comparator, frozen before any next-owner Rust/ABI read.
/// It deliberately does not simulate tasks, transport returns, or actor scheduling.
enum FrozenRuntimeCatalogAdmissionReference {
    struct QuietFacts {
        var started = true
        var stopped = false
        var actionPresent = false
        var retirementPresent = false
        var bootstrapPresent = false
        var pairingTaskPresent = false
        var mediaPresent = false
        var mediaCompletionTaskPresent = false
        var pairedRecordPresent = false
        var validatedWaiting = false
        var activeExchange: String?
        var mediaExchange: String?
    }

    struct PostDrainFacts {
        var stopped = false
        var operationMatches = true
        var retirementPresent = false
        var mediaPresent = false
        var activeExchange: String?
        var mediaExchange: String?
    }

    struct FirstPairIntent {
        let attemptID: UUID
        let epoch: UUID
        let admitted: WorldwidePairedPhoneCatalogSnapshot
    }

    enum CompletionSelection: Equatable {
        case retainReadback
        case select(UUID, WorldwidePairedPhoneCatalogToken)
    }

    static func requireQuiet(
        _ facts: QuietFacts, identityPresent: Bool,
        cached: WorldwidePairedPhoneCatalogSnapshot?,
        owner: () -> Bool, authorization: () -> Bool,
        fresh: () throws -> WorldwidePairedPhoneCatalogSnapshot
    ) throws {
        // Preserve ORIGINAL evaluation cuts; never precompute later native callbacks.
        guard facts.started, !facts.stopped, !facts.actionPresent, !facts.retirementPresent,
              !facts.bootstrapPresent, !facts.pairingTaskPresent, !facts.mediaPresent,
              !facts.mediaCompletionTaskPresent,
              (!facts.pairedRecordPresent || facts.validatedWaiting),
              facts.activeExchange == nil, facts.mediaExchange == nil else {
            throw WorldwidePhoneCatalogRuntimeError.notQuiet
        }
        guard owner(), authorization() else {
            throw WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized
        }
        guard let cached, identityPresent else {
            throw WorldwideHostCoordinatorError.invalidLifecycle
        }
        guard try fresh() == cached else { throw WorldwidePhoneCatalogRuntimeError.staleSelection }
    }

    static func admitTicket(
        _ ticket: WorldwidePhoneCatalogAction, epoch: UUID,
        facts: QuietFacts, identityPresent: Bool,
        cached: WorldwidePairedPhoneCatalogSnapshot?,
        owner: () -> Bool, authorization: () -> Bool,
        fresh: () throws -> WorldwidePairedPhoneCatalogSnapshot
    ) throws {
        try requireQuiet(facts, identityPresent: identityPresent, cached: cached,
                         owner: owner, authorization: authorization, fresh: fresh)
        guard cached?.token == ticket.token, epoch == ticket.selectionEpoch else {
            throw WorldwidePhoneCatalogRuntimeError.staleSelection
        }
        // Exact handles/epoch rotation before await remain assertions through the actual actor.
    }

    static func revalidateAfterDrain(
        _ facts: PostDrainFacts, expected: WorldwidePairedPhoneCatalogToken,
        identityPresent: Bool, cached: WorldwidePairedPhoneCatalogSnapshot?,
        owner: () -> Bool, authorization: () -> Bool,
        fresh: () throws -> WorldwidePairedPhoneCatalogSnapshot
    ) throws {
        guard !facts.stopped, facts.operationMatches, !facts.retirementPresent,
              !facts.mediaPresent, facts.activeExchange == nil, facts.mediaExchange == nil,
              cached?.token == expected else { throw WorldwidePhoneCatalogRuntimeError.staleSelection }
        guard owner(), authorization() else {
            throw WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized
        }
        guard let cached, identityPresent else {
            throw WorldwideHostCoordinatorError.invalidLifecycle
        }
        guard try fresh() == cached else { throw WorldwidePhoneCatalogRuntimeError.staleSelection }
    }

    static func mayRecover(
        stopped: Bool, operationMatches: Bool, retirementPresent: Bool,
        identityPresent: Bool, cached: WorldwidePairedPhoneCatalogSnapshot?,
        owner: () -> Bool, fresh: () throws -> WorldwidePairedPhoneCatalogSnapshot
    ) -> Bool {
        guard !stopped, operationMatches, !retirementPresent, owner(), identityPresent,
              let cached, let current = try? fresh(), current == cached else { return false }
        return true // ORIGINAL has no mutation-authorization callback here.
    }

    static func firstPairEligible(reset: Bool, snapshot: WorldwidePairedPhoneCatalogSnapshot) -> Bool {
        !reset && snapshot.records.isEmpty && snapshot.selectedPhoneID == nil
            && snapshot.token.revision == 1 && snapshot.legacyImportReceipt == nil
    }

    /// ORIGINAL pairingDidCommit takes and clears intent synchronously before bootstrap.stop.
    static func takeIntent(_ stored: inout FirstPairIntent?) -> FirstPairIntent? {
        let taken = stored
        stored = nil
        return taken
    }

    static func selectionAfterReadback(
        record: RemotePairedDeviceRecord,
        readback: (snapshot: WorldwidePairedPhoneCatalogSnapshot, record: RemotePairedDeviceRecord?),
        intent: FirstPairIntent?, currentAttempt: UUID, epoch: UUID,
        cached: WorldwidePairedPhoneCatalogSnapshot?, identityPresent: Bool,
        authorization: () -> Bool
    ) throws -> CompletionSelection {
        guard readback.record == record else { throw WorldwidePhoneCatalogRuntimeError.staleAttempt }
        guard let intent else { return .retainReadback }
        guard authorization(), identityPresent, intent.attemptID == currentAttempt,
              intent.epoch == epoch, cached == intent.admitted,
              intent.admitted.records.isEmpty, intent.admitted.selectedPhoneID == nil,
              intent.admitted.token.revision == 1, intent.admitted.legacyImportReceipt == nil,
              readback.snapshot.token.catalogID == intent.admitted.token.catalogID,
              readback.snapshot.records == [record], readback.snapshot.selectedPhoneID == nil,
              readback.snapshot.legacyImportReceipt == nil else {
            throw WorldwidePhoneCatalogRuntimeError.staleAttempt
        }
        return .select(record.remoteDeviceID, readback.snapshot.token)
    }
}
