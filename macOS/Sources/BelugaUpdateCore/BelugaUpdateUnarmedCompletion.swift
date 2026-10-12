import Foundation

/// Positive completion of one fresh manual SDK cycle, never installer-absence proof.
/// The real driver supplies it only after paired native callbacks. These fields alone
/// authenticate nothing, cannot be restored from a marker, and grant no runtime authority.
package struct BelugaUpdateUnarmedCompletion: Equatable, Sendable {
    /// Bounded initial appcast failures, not arbitrary SDK or installer errors.
    package enum FailedInitialCheck: Equatable, Sendable {
        case feedFetch
        case feedParseOrSignature
    }

    package enum Reason: Equatable, Sendable {
        case noUpdate
        case cancelledCheck
        case declinedCandidate(BelugaUpdateOperation.ArtifactIdentity)
        case failedInitialCheck(FailedInitialCheck)

        func matches(candidate: BelugaUpdateOperation.ArtifactIdentity?) -> Bool {
            switch self {
            case .noUpdate, .cancelledCheck, .failedInitialCheck: candidate == nil
            case .declinedCandidate(let expected): candidate == expected
            }
        }
    }

    package let operationID: UUID
    package let cycleNonce: UUID
    package let reason: Reason

    package init(operationID: UUID, cycleNonce: UUID, reason: Reason) {
        self.operationID = operationID
        self.cycleNonce = cycleNonce
        self.reason = reason
    }
}

/// Caller-owned release-lineage admission, not a build-number or absent-marker inference.
/// The verifier must prove that every SDK startup in this exact lineage was fenced and
/// that no pre-marker installer history is unknown. A throwing verifier denies retirement.
package struct BelugaUpdateControlledHistoryAdmission {
    private let verifier: (UUID, BelugaUpdateOperation.Target,
                           BelugaUpdateOperation.ArtifactIdentity) throws -> Void

    package init(verify: @escaping (UUID, BelugaUpdateOperation.Target,
                                   BelugaUpdateOperation.ArtifactIdentity) throws -> Void) {
        verifier = verify
    }

    func revalidate(operationID: UUID, target: BelugaUpdateOperation.Target,
                    predecessor: BelugaUpdateOperation.ArtifactIdentity) throws {
        try verifier(operationID, target, predecessor)
    }
}
