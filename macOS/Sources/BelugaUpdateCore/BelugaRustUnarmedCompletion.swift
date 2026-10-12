import BelugaCore

/// Copied inner reason classifier only. Native eligibility and all authority,
/// SDK/error/item identities, candidate payload and retirement remain native.
package enum BelugaRustUnarmedCompletion {
    package typealias Request = beluga_core_update_unarmed_completion_request_t
    package typealias Result = beluga_core_update_unarmed_completion_result_t
    package typealias ResultMutation = @Sendable (Request, Result) -> Result

    package enum FailureKind: UInt32, Sendable {
        case absent = 0, feedFetch, feedParseOrSignature
    }
    package enum Reason: UInt32, Sendable {
        case noCompletion = 0, noUpdate, feedFetchFailure, feedParseFailure
        case cancelledCheck, declinedCandidate
    }

    package static var layoutIsExact: Bool {
        MemoryLayout<Request>.size == 12 && MemoryLayout<Request>.stride == 12
            && MemoryLayout<Request>.alignment == 4
            && MemoryLayout<Request>.offset(of: \Request.abi_version) == 0
            && MemoryLayout<Request>.offset(of: \Request.flags) == 4
            && MemoryLayout<Request>.offset(of: \Request.failure_kind) == 8
            && MemoryLayout<Result>.size == 12 && MemoryLayout<Result>.stride == 12
            && MemoryLayout<Result>.alignment == 4
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.reason) == 8
    }

    package static func classify(
        noUpdatePresent: Bool, noUpdateIsFinished: Bool,
        boundCandidatePresent: Bool, admittedItemPresent: Bool, declinePresent: Bool,
        cancelledInitialCheck: Bool, failureAcknowledged: Bool, failureAbortObserved: Bool,
        failureIsFinished: Bool, initialPresentationPresent: Bool,
        candidateAdmissionAttempted: Bool, candidatePresentationObserved: Bool,
        candidateBindingInProgress: Bool, foundItemPresent: Bool, finishedErrorPresent: Bool,
        declineSDKChoiceObserved: Bool, boundMatchesDecline: Bool,
        admittedMatchesDecline: Bool, foundMatchesDecline: Bool,
        failureKind: FailureKind
    ) -> Reason? {
        var flags: UInt32 = 0
        if noUpdatePresent { flags |= 1 << 0 }
        if noUpdateIsFinished { flags |= 1 << 1 }
        if boundCandidatePresent { flags |= 1 << 2 }
        if admittedItemPresent { flags |= 1 << 3 }
        if declinePresent { flags |= 1 << 4 }
        if cancelledInitialCheck { flags |= 1 << 5 }
        if failureAcknowledged { flags |= 1 << 6 }
        if failureAbortObserved { flags |= 1 << 7 }
        if failureIsFinished { flags |= 1 << 8 }
        if initialPresentationPresent { flags |= 1 << 9 }
        if candidateAdmissionAttempted { flags |= 1 << 10 }
        if candidatePresentationObserved { flags |= 1 << 11 }
        if candidateBindingInProgress { flags |= 1 << 12 }
        if foundItemPresent { flags |= 1 << 13 }
        if finishedErrorPresent { flags |= 1 << 14 }
        if declineSDKChoiceObserved { flags |= 1 << 15 }
        if boundMatchesDecline { flags |= 1 << 16 }
        if admittedMatchesDecline { flags |= 1 << 17 }
        if foundMatchesDecline { flags |= 1 << 18 }
        return evaluate(Request(abi_version: 1, flags: flags, failure_kind: failureKind.rawValue))
    }

    /// This seam changes only copied results in direct bridge tests. The actual
    /// session uses classify's fixed callback-free C producer, with no mutation.
    package static func evaluate(_ request: Request,
                                 resultMutation: ResultMutation? = nil) -> Reason? {
        guard layoutIsExact else { return nil }
        let actual = beluga_core_update_unarmed_completion_decide(request)
        let result = resultMutation?(request, actual) ?? actual
        guard beluga_core_update_unarmed_completion_result_is_valid(request, result) == 1,
              result.abi_version == 1, result.status == 0,
              let reason = Reason(rawValue: result.reason) else { return nil }
        return reason
    }
}
