import BelugaCore

/// Copied menu policy only. Native code retains the bundle, task and broker owners.
package enum BelugaRustUpdateAvailability {
    package typealias Request = beluga_core_update_admission_request_t
    package typealias Result = beluga_core_update_admission_result_t
    package typealias ResultMutation = @Sendable (Request, Result) -> Result

    package enum Status: UInt32, Sendable {
        case development = 0, recovery, owned, ready, unavailable
    }

    package struct Snapshot: Equatable, Sendable {
        package let permitsUpdate: Bool
        package let isUpdateInProgress: Bool
        package let canCheckForUpdates: Bool
        package let status: Status

        package init(permitsUpdate: Bool, isUpdateInProgress: Bool,
                     canCheckForUpdates: Bool, status: Status) {
            self.permitsUpdate = permitsUpdate
            self.isUpdateInProgress = isUpdateInProgress
            self.canCheckForUpdates = canCheckForUpdates
            self.status = status
        }
    }

    package static var layoutIsExact: Bool {
        MemoryLayout<Request>.size == 8 && MemoryLayout<Request>.stride == 8
            && MemoryLayout<Request>.alignment == 4
            && MemoryLayout<Request>.offset(of: \Request.abi_version) == 0
            && MemoryLayout<Request>.offset(of: \Request.flags) == 4
            && MemoryLayout<Result>.size == 24 && MemoryLayout<Result>.stride == 24
            && MemoryLayout<Result>.alignment == 4
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.permits_update) == 8
            && MemoryLayout<Result>.offset(of: \Result.is_in_progress) == 12
            && MemoryLayout<Result>.offset(of: \Result.can_check) == 16
            && MemoryLayout<Result>.offset(of: \Result.status_kind) == 20
    }

    package static func evaluate(_ admission: BelugaUpdateAdmission,
                                 isRelease: Bool = false, taskInProgress: Bool = false,
                                 needsReadiness: Bool = false, failed: Bool = false,
                                 resultMutation: ResultMutation? = nil) -> Snapshot? {
        let facts = [admission.isInteractiveApplication, admission.hasActiveMedia,
                     admission.hasPendingPairing, admission.hasAudioShares,
                     admission.teardownComplete, isRelease, taskInProgress,
                     needsReadiness, failed]
        let flags = facts.enumerated().reduce(UInt32(0)) { value, entry in
            value | (entry.element ? UInt32(1) << entry.offset : 0)
        }
        return evaluate(Request(abi_version: 1, flags: flags), resultMutation: resultMutation)
    }

    // The test seam changes only a result from the actual export, never its verifier.
    package static func evaluate(_ request: Request,
                                 resultMutation: ResultMutation? = nil) -> Snapshot? {
        guard layoutIsExact else { return nil }
        let actual = beluga_core_update_admission_decide(request)
        let result = resultMutation?(request, actual) ?? actual
        guard beluga_core_update_admission_result_is_valid(request, result) == 1,
              result.abi_version == 1, result.status == 0,
              result.permits_update <= 1, result.is_in_progress <= 1,
              result.can_check <= 1, let status = Status(rawValue: result.status_kind) else {
            return nil
        }
        return Snapshot(permitsUpdate: result.permits_update == 1,
                        isUpdateInProgress: result.is_in_progress == 1,
                        canCheckForUpdates: result.can_check == 1, status: status)
    }
}
