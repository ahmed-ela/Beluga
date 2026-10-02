import BelugaUpdateCore

/// Couples Sparkle's serial lifecycle policy to the same kernel lock used by every
/// legacy/rebranded host. No process enumeration, second namespace, or lock-format change.
///
/// Ownership is retained from check reservation through the matching actual completion,
/// including a background-to-interactive continuation and final installer admission. Once
/// extraction can arm an external installer, completion/cancellation cannot release it.
/// This is NOT an installer handoff: exiting this process closes its descriptor. The
/// interval after menu exit and before Sparkle finishes replacement/relaunch remains
/// outside this lease and must not be presented as fully protected self-update.
@MainActor
final class BelugaOwnedUpdateTransaction {
    private var transaction = BelugaUpdateTransaction()
    private var ownership: WorldwideHostProcessLock?
    private let acquireOwnership: () throws -> WorldwideHostProcessLock
    private(set) var ownershipWasRefused = false
    private(set) var installerMayRemainArmed = false
    private(set) var installerArmingWasUnowned = false

    init(acquireOwnership: @escaping () throws -> WorldwideHostProcessLock = {
        try WorldwideHostProcessLock.acquire()
    }) {
        self.acquireOwnership = acquireOwnership
    }

    var hasRuntimeOwnership: Bool { ownership != nil }

    func isUpdateInProgress(sparkleSessionInProgress: Bool) -> Bool {
        installerMayRemainArmed || ownership != nil || transaction.isUpdateInProgress(
            sparkleSessionInProgress: sparkleSessionInProgress
        )
    }

    /// Sparkle calls public willExtractUpdate synchronously before launching Autoupdate.
    /// Even extraction failure or UI cancellation cannot prove that external installer is
    /// gone. An unexpected callback without ownership is a permanent fail-closed invariant
    /// violation for this process: the callback cannot throw or cancel the native operation.
    @discardableResult
    func markInstallerMayRemainArmed() -> Bool {
        installerMayRemainArmed = true
        guard ownership != nil else {
            installerArmingWasUnowned = true
            return false
        }
        return !installerArmingWasUnowned
    }

    func reserveInteractiveCheck(
        admission: BelugaUpdateAdmission, sparkleSessionInProgress: Bool
    ) -> Bool {
        guard admission.permitsUpdate,
              !isUpdateInProgress(sparkleSessionInProgress: sparkleSessionInProgress),
              ensureOwnership() else { return false }
        let allowed = transaction.reserveInteractiveCheck(
            admission: admission, sparkleSessionInProgress: sparkleSessionInProgress
        )
        releaseOnlyAfterActualCompletion(sparkleSessionInProgress: sparkleSessionInProgress)
        return allowed
    }

    func admitCheck(_ check: BelugaUpdateTransaction.Check,
                    admission: BelugaUpdateAdmission) -> Bool {
        // A denied serial continuation must still update the policy's matching check:
        // otherwise its actual completion could never release the retained ownership.
        guard !installerArmingWasUnowned,
              ownership != nil || (admission.permitsUpdate && ensureOwnership()) else {
            return false
        }
        let allowed = transaction.admitCheck(check, admission: admission)
        releaseOnlyAfterActualCompletion(sparkleSessionInProgress: false)
        return allowed
    }

    func admitInstallation(
        admission: BelugaUpdateAdmission, sparkleSessionInProgress: Bool
    ) -> Bool {
        // Never reacquire here: a final install is valid only under the exact lease
        // retained from the admitted check, not a new incidental quiet boundary.
        guard !installerArmingWasUnowned, ownership != nil else { return false }
        return transaction.admitInstallation(
            admission: admission, sparkleSessionInProgress: sparkleSessionInProgress
        )
    }

    func finishCycle(_ check: BelugaUpdateTransaction.Check,
                     sparkleSessionInProgress: Bool) {
        transaction.finishCycle(check, sparkleSessionInProgress: sparkleSessionInProgress)
        releaseOnlyAfterActualCompletion(sparkleSessionInProgress: sparkleSessionInProgress)
    }

    private func ensureOwnership() -> Bool {
        guard ownership == nil else { return true }
        do {
            ownership = try acquireOwnership()
            ownershipWasRefused = false
            return true
        } catch {
            ownershipWasRefused = true
            return false
        }
    }

    private func releaseOnlyAfterActualCompletion(sparkleSessionInProgress: Bool) {
        guard !installerMayRemainArmed, !transaction.isUpdateInProgress(
            sparkleSessionInProgress: sparkleSessionInProgress
        ) else { return }
        ownership?.release()
        ownership = nil
    }
}
