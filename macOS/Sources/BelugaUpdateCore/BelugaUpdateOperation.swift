import Foundation

/// Pure policy only. Durable I/O, authenticated IPC, signature/closure verification, the
/// supported installer callback and continuous host-lock ownership belong to its caller.
package struct BelugaUpdateOperation: Equatable, Sendable {
    package static let schema = "beluga.update-operation.v1"
    package static let maximumRecordBytes = 16_384
    package static let expectedBundleIdentifier = "com.elamin.AudioStreamer.CaptureServer"
    package static let expectedTeamIdentifier = "MSMG8CJLB3"

    package struct Target: Codable, Equatable, Sendable {
        package let canonicalPath: String
        package let bundleIdentifier: String
        package let teamIdentifier: String
        package let effectiveUID: UInt32

        /// Canonical filesystem identity/writability must already have been verified.
        package init(canonicalPath: String, effectiveUID: UInt32,
             bundleIdentifier: String = BelugaUpdateOperation.expectedBundleIdentifier,
             teamIdentifier: String = BelugaUpdateOperation.expectedTeamIdentifier) throws {
            self.canonicalPath = canonicalPath
            self.bundleIdentifier = bundleIdentifier
            self.teamIdentifier = teamIdentifier
            self.effectiveUID = effectiveUID
            guard isValid else { throw PolicyError.invalidTarget }
        }

        fileprivate var isValid: Bool {
            let components = canonicalPath.split(separator: "/", omittingEmptySubsequences: false)
            return canonicalPath.utf8.count <= 4_096 && canonicalPath.hasPrefix("/") &&
                canonicalPath.hasSuffix(".app") && components.count > 1 &&
                components.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." } &&
                canonicalPath.utf8.allSatisfy { $0 >= 32 && $0 != 127 } &&
                bundleIdentifier == BelugaUpdateOperation.expectedBundleIdentifier &&
                teamIdentifier == BelugaUpdateOperation.expectedTeamIdentifier
        }
    }

    package struct ArtifactIdentity: Codable, Equatable, Sendable {
        package let version: String
        package let build: UInt64
        package let executableSHA256: String
        package let dependencyClosureSHA256: String

        package init(version: String, build: UInt64, executableSHA256: String,
             dependencyClosureSHA256: String) throws {
            self.version = version
            self.build = build
            self.executableSHA256 = executableSHA256
            self.dependencyClosureSHA256 = dependencyClosureSHA256
            guard isValid else { throw PolicyError.invalidArtifact }
        }

        fileprivate var isValid: Bool {
            version.utf8.count <= 64 && BelugaReleaseConfiguration.isSemanticVersion(version) &&
                build > 0 && BelugaUpdateOperation.isSHA256(executableSHA256) &&
                BelugaUpdateOperation.isSHA256(dependencyClosureSHA256)
        }
    }

    /// Exact staged broker expectation captured before SDK startup. Static readback and
    /// the connected process's native audit-token identity remain separate obligations.
    package struct BrokerBinding: Codable, Equatable, Sendable {
        package let artifact: ArtifactIdentity
        package let nativeCDHash: Data

        package init(artifact: ArtifactIdentity, nativeCDHash: Data) throws {
            self.artifact = artifact
            self.nativeCDHash = nativeCDHash
            guard isValid else { throw PolicyError.invalidArtifact }
        }

        fileprivate var isValid: Bool {
            artifact.isValid && nativeCDHash.count == 20 &&
                nativeCDHash.contains(where: { $0 != 0 })
        }
    }

    package enum Stage: String, Codable, Equatable, Sendable {
        case prepared, possiblyArmed, installedVerified, readyToRelease
    }

    package struct InstalledCompletion: Equatable, Sendable {
        package let operationID: UUID
        package let target: Target
        package let candidate: ArtifactIdentity

        package init(operationID: UUID, target: Target, candidate: ArtifactIdentity) {
            self.operationID = operationID
            self.target = target
            self.candidate = candidate
        }
    }

    package struct ReadinessChallenge: Equatable, Sendable {
        package let operationID: UUID
        package let target: Target
        package let candidate: ArtifactIdentity
        package let menuInstanceID: UUID
        package let nonce: UUID
    }

    package struct MenuReadiness: Codable, Equatable, Sendable {
        package let operationID: UUID
        package let target: Target
        package let candidate: ArtifactIdentity
        package let menuInstanceID: UUID
        package let challengeNonce: UUID
        package let isReady: Bool

        package init(operationID: UUID, target: Target, candidate: ArtifactIdentity,
                     menuInstanceID: UUID, challengeNonce: UUID, isReady: Bool) {
            self.operationID = operationID
            self.target = target
            self.candidate = candidate
            self.menuInstanceID = menuInstanceID
            self.challengeNonce = challengeNonce
            self.isReady = isReady
        }
    }

    package enum NonTerminalObservation: Sendable {
        case sessionBecameIdle, cancelled, updaterFailed, brokerExited
    }

    package enum PolicyError: Error, Equatable {
        case invalidTarget, invalidArtifact, invalidOperation, invalidRecord
        case oversizedRecord, noncanonicalRecord, unexpectedBinding
    }

    private struct Record: Codable, Equatable, Sendable {
        let schema: String
        let operationID: UUID
        let target: Target
        let predecessor: ArtifactIdentity
        let predecessorMenuInstanceID: UUID
        var broker: BrokerBinding?
        var candidate: ArtifactIdentity?
        var stage: Stage
        var readiness: MenuReadiness?
    }

    private typealias Policy = BelugaRustUpdateOperationBridge
    private let policyProducer: BelugaRustUpdateOperationProducer
    private var policyUnavailable = false
    private var record: Record
    // These cannot be restored from disk; a serialized terminal record is not fresh proof.
    private var installedCompletionIsFresh = false
    private var readinessIsFresh = false
    private var challenge: ReadinessChallenge?

    package var operationID: UUID { record.operationID }
    package var target: Target { record.target }
    package var predecessor: ArtifactIdentity { record.predecessor }
    package var brokerBinding: BrokerBinding? { record.broker }
    package var candidate: ArtifactIdentity? { record.candidate }
    package var stage: Stage { record.stage }
    package var installerMayRemainArmed: Bool {
        policyQuery(.queryInstallerMayRemainArmed) ?? true
    }

    /// Authorizes only the caller's exact durable-fence clearance, not native installation.
    package var permitsFenceRelease: Bool {
        policyQuery(.queryPermitsFenceRelease) ?? false
    }

    /// An extant operation never grants host activation. The caller must clear its exact
    /// durable fence and independently acquire the ordinary shared runtime lock afterward.
    package var permitsRuntimeActivation: Bool {
        policyQuery(.queryPermitsRuntimeActivation) ?? false
    }

    /// The injected producer is not persisted or compared as authority. Fault state is
    /// an ephemeral value field; a nonmutating query cannot poison another value copy.
    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.record == rhs.record &&
            lhs.installedCompletionIsFresh == rhs.installedCompletionIsFresh &&
            lhs.readinessIsFresh == rhs.readinessIsFresh && lhs.challenge == rhs.challenge &&
            lhs.policyUnavailable == rhs.policyUnavailable
    }

    package init(operationID: UUID, target: Target, predecessor: ArtifactIdentity,
         predecessorMenuInstanceID: UUID) throws {
        try self.init(operationID: operationID, target: target, predecessor: predecessor,
                      predecessorMenuInstanceID: predecessorMenuInstanceID, policyProducer: .actual)
    }

    /// Internal per-value copied-result seam used by focused boundary-custody tests.
    init(operationID: UUID, target: Target, predecessor: ArtifactIdentity,
         predecessorMenuInstanceID: UUID, policyProducer: BelugaRustUpdateOperationProducer) throws {
        self.policyProducer = policyProducer
        guard target.isValid else { throw PolicyError.invalidTarget }
        guard predecessor.isValid else { throw PolicyError.invalidArtifact }
        guard Self.isNonce(operationID), Self.isNonce(predecessorMenuInstanceID),
              operationID != predecessorMenuInstanceID else { throw PolicyError.invalidOperation }
        record = Record(schema: Self.schema, operationID: operationID, target: target,
                        predecessor: predecessor, predecessorMenuInstanceID: predecessorMenuInstanceID,
                        broker: nil, candidate: nil, stage: .prepared, readiness: nil)
    }

    /// Only this bounded canonical-JSON seam exposes the private Codable record. Re-encoding
    /// equality rejects unknown/duplicate keys, aliases, explicit nulls and trailing bytes.
    package static func restoring(from data: Data, expectedTarget: Target,
                          expectedOperationID: UUID? = nil) throws -> Self {
        try restoring(from: data, expectedTarget: expectedTarget,
                      expectedOperationID: expectedOperationID, policyProducer: .actual)
    }

    static func restoring(from data: Data, expectedTarget: Target,
                          expectedOperationID: UUID? = nil,
                          policyProducer: BelugaRustUpdateOperationProducer) throws -> Self {
        guard !data.isEmpty, data.count <= maximumRecordBytes else { throw PolicyError.oversizedRecord }
        let record: Record
        do { record = try JSONDecoder().decode(Record.self, from: data) }
        catch { throw PolicyError.invalidRecord }
        guard isValid(record) else { throw PolicyError.invalidRecord }
        guard record.target == expectedTarget,
              expectedOperationID == nil || record.operationID == expectedOperationID else {
            throw PolicyError.unexpectedBinding
        }
        guard try encode(record) == data else { throw PolicyError.noncanonicalRecord }
        var restored = try Self(operationID: record.operationID, target: record.target,
                                predecessor: record.predecessor,
                                predecessorMenuInstanceID: record.predecessorMenuInstanceID,
                                policyProducer: policyProducer)
        restored.record = record
        return restored
    }

    package func encodedRecord() throws -> Data {
        guard Self.isValid(record) else { throw PolicyError.invalidRecord }
        let data = try Self.encode(record)
        guard data.count <= Self.maximumRecordBytes else { throw PolicyError.oversizedRecord }
        return data
    }

    /// One-time publication while prepared. A replacement target must never infer this
    /// identity from whatever same-version broker happens to exist after installation.
    @discardableResult
    package mutating func bindBroker(_ broker: BrokerBinding, operationID: UUID,
                                    target: Target) -> Bool {
        let before = self
        let event = Policy.Event(.bindBroker, matches(operationID, target), broker.isValid,
                                 broker.artifact.version == predecessor.version,
                                 broker.artifact.build == predecessor.build)
        guard let expected = plan(before: before, event: event, action: .publishBroker) else {
            return false
        }
        var next = before
        next.record.broker = broker
        return publish(next, expected: expected)
    }

    @discardableResult
    package mutating func bindCandidate(_ candidate: ArtifactIdentity, operationID: UUID,
                                target: Target) -> Bool {
        let before = self
        let event = Policy.Event(.bindCandidate, matches(operationID, target), candidate.isValid,
                                 candidate.build > predecessor.build,
                                 candidate.executableSHA256 != predecessor.executableSHA256)
        guard let expected = plan(before: before, event: event, action: .publishCandidate) else {
            return false
        }
        var next = before
        next.record.candidate = candidate
        return publish(next, expected: expected)
    }

    @discardableResult
    package mutating func markPossiblyArmed(operationID: UUID, target: Target) -> Bool {
        let before = self
        guard let expected = plan(before: before,
                                  event: Policy.Event(.markPossiblyArmed, matches(operationID, target)),
                                  action: .markPossiblyArmed) else { return false }
        var next = before
        next.record.stage = .possiblyArmed
        return publish(next, expected: expected)
    }

    /// Caller supplies this only from the supported positive installation callback plus
    /// fresh exact installed-artifact readback. The value itself authenticates nothing.
    @discardableResult
    package mutating func acceptInstalledCompletion(_ completion: InstalledCompletion) -> Bool {
        let before = self
        let event = Policy.Event(.installedCompletion,
                                 matches(completion.operationID, completion.target),
                                 completion.candidate == record.candidate)
        guard let expected = plan(before: before, event: event, action: .acceptInstalledCompletion) else {
            return false
        }
        var next = before
        // Assignment projection, not a second admission guard. Restored ready stage stays ready.
        if next.stage == .possiblyArmed { next.record.stage = .installedVerified }
        next.installedCompletionIsFresh = true
        next.readinessIsFresh = false
        next.challenge = nil
        return publish(next, expected: expected)
    }

    /// The owner generates the nonce after authenticating a newly launched menu process.
    /// Previously persisted readiness cannot satisfy a new owner's recovery challenge.
    package mutating func issueReadinessChallenge(menuInstanceID: UUID, nonce: UUID) -> ReadinessChallenge? {
        let before = self
        let event = Policy.Event(.issueChallenge, Self.isNonce(menuInstanceID), Self.isNonce(nonce),
                                 menuInstanceID != record.predecessorMenuInstanceID,
                                 nonce != operationID, nonce != record.predecessorMenuInstanceID,
                                 nonce != record.readiness?.challengeNonce)
        guard let expected = plan(before: before, event: event, action: .publishChallenge) else {
            return nil
        }
        // The action must copy the existing native candidate, never invent a payload.
        guard let candidate = before.candidate else { policyUnavailable = true; return nil }
        let issued = ReadinessChallenge(operationID: before.operationID, target: before.target,
                                        candidate: candidate, menuInstanceID: menuInstanceID,
                                        nonce: nonce)
        var next = before
        next.challenge = issued
        return publish(next, expected: expected) ? issued : nil
    }

    @discardableResult
    package mutating func acceptMenuReadiness(_ readiness: MenuReadiness) -> Bool {
        acceptMenuReadiness(readiness, encodingProbe: nil)
    }

    /// Internal per-call instrumentation only. The probe cannot supply encoded bytes,
    /// a policy decision, or a successor; it is never stored or compared as authority.
    struct ReadinessEncodingBoundaryProbe: Sendable {
        let before: @Sendable () throws -> Void
        let completed: @Sendable (Int) -> Void
    }

    @discardableResult
    mutating func acceptMenuReadiness(_ readiness: MenuReadiness,
                                     encodingProbe: ReadinessEncodingBoundaryProbe?) -> Bool {
        let before = self
        let preflight = before.readinessEvent(.prepareReadinessEncoding, readiness: readiness)
        guard let prepared = plan(before: before, event: preflight,
                                  action: .prepareReadinessEncoding) else { return false }
        guard prepared == before.policySnapshot else { policyUnavailable = true; return false }

        // Preserve original Foundation encoding order: no encode on denied preflight,
        // one local record encode, then a commit decision on the original snapshot.
        var nextRecord = before.record
        nextRecord.readiness = readiness
        nextRecord.stage = .readyToRelease
        let encoded: Data?
        do {
            // A throwing probe is a pre-encoder boundary failure, not evidence that
            // Foundation naturally threw. Production passes nil and always uses encode.
            try encodingProbe?.before()
            let data = try Self.encode(nextRecord)
            encodingProbe?.completed(data.count)
            encoded = data
        } catch {
            encoded = nil
        }
        let withinBound = encoded.map { $0.count <= Self.maximumRecordBytes } ?? false
        let commit = before.readinessEvent(.acceptReadiness, readiness: readiness,
                                          encodedWithinBound: withinBound)
        guard let expected = plan(before: before, event: commit, action: .acceptReadiness) else {
            return false
        }
        var next = before
        next.record = nextRecord
        next.challenge = nil
        next.readinessIsFresh = true
        return publish(next, expected: expected)
    }

    package mutating func observe(_ observation: NonTerminalObservation) {
        let before = self
        let opcode: Policy.Opcode
        let action: Policy.Action
        switch observation {
        case .sessionBecameIdle: opcode = .idle; action = .none
        case .cancelled: opcode = .cancelled; action = .none
        case .updaterFailed: opcode = .updaterFailed; action = .invalidateFreshness
        case .brokerExited: opcode = .brokerExited; action = .invalidateFreshness
        }
        guard let expected = plan(before: before, event: Policy.Event(opcode), action: action) else {
            return
        }
        var next = before
        if action == .invalidateFreshness {
            next.installedCompletionIsFresh = false
            next.readinessIsFresh = false
            next.challenge = nil
        }
        _ = publish(next, expected: expected)
    }

    private var policySnapshot: Policy.Snapshot {
        let stageWord: UInt32
        switch record.stage {
        case .prepared: stageWord = 0
        case .possiblyArmed: stageWord = 1
        case .installedVerified: stageWord = 2
        case .readyToRelease: stageWord = 3
        }
        return .init(stage: stageWord, brokerPresent: record.broker != nil,
                     candidatePresent: record.candidate != nil,
                     recordedReadinessPresent: record.readiness != nil,
                     installedFresh: installedCompletionIsFresh, readinessFresh: readinessIsFresh,
                     challengePresent: challenge != nil)
    }

    private func readinessEvent(_ opcode: Policy.Opcode, readiness: MenuReadiness,
                                encodedWithinBound: Bool = false) -> Policy.Event {
        Policy.Event(opcode, readiness.isReady,
                     challenge.map { readiness.operationID == $0.operationID } ?? false,
                     challenge.map { readiness.target == $0.target } ?? false,
                     challenge.map { readiness.candidate == $0.candidate } ?? false,
                     challenge.map { readiness.menuInstanceID == $0.menuInstanceID } ?? false,
                     challenge.map { readiness.challengeNonce == $0.nonce } ?? false,
                     encodedWithinBound)
    }

    private func policyQuery(_ opcode: Policy.Opcode) -> Bool? {
        guard !policyUnavailable else { return nil }
        return Policy.query(before: policySnapshot, opcode: opcode, producer: policyProducer)
    }

    private mutating func plan(before: Self, event: Policy.Event,
                               action: Policy.Action) -> Policy.Snapshot? {
        guard !policyUnavailable else { return nil }
        switch Policy.plan(before: before.policySnapshot, event: event,
                           expectedAction: action, producer: policyProducer) {
        case let .accepted(expected): return expected
        case .denied: return nil
        case .unavailable: policyUnavailable = true; return nil
        }
    }

    private mutating func publish(_ next: Self, expected: Policy.Snapshot) -> Bool {
        guard !policyUnavailable else { return false }
        guard next.policySnapshot == expected else { policyUnavailable = true; return false }
        self = next
        return true
    }

    private func matches(_ operationID: UUID, _ target: Target) -> Bool {
        record.operationID == operationID && record.target == target
    }

    private static func encode(_ record: Record) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(record)
    }

    private static func isValid(_ record: Record) -> Bool {
        guard record.schema == schema, record.target.isValid, record.predecessor.isValid,
              isNonce(record.operationID), isNonce(record.predecessorMenuInstanceID),
              record.operationID != record.predecessorMenuInstanceID else { return false }
        if let broker = record.broker {
            guard broker.isValid, broker.artifact.version == record.predecessor.version,
                  broker.artifact.build == record.predecessor.build else { return false }
        }
        if let candidate = record.candidate {
            guard candidate.isValid, candidate.build > record.predecessor.build,
                  candidate.executableSHA256 != record.predecessor.executableSHA256 else { return false }
        }
        switch record.stage {
        case .prepared, .possiblyArmed:
            return record.readiness == nil
        case .installedVerified:
            return record.candidate != nil && record.readiness == nil
        case .readyToRelease:
            guard let candidate = record.candidate, let readiness = record.readiness else { return false }
            return readiness.isReady && readiness.operationID == record.operationID &&
                readiness.target == record.target && readiness.candidate == candidate &&
                isNonce(readiness.menuInstanceID) && isNonce(readiness.challengeNonce) &&
                readiness.menuInstanceID != record.predecessorMenuInstanceID &&
                readiness.challengeNonce != record.operationID &&
                readiness.challengeNonce != record.predecessorMenuInstanceID
        }
    }

    private static func isNonce(_ value: UUID) -> Bool {
        value.uuidString != "00000000-0000-0000-0000-000000000000"
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        } && value.contains(where: { $0 != "0" })
    }
}
