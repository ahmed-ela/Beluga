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
    package var installerMayRemainArmed: Bool { stage != .prepared }

    /// Authorizes only the caller's exact durable-fence clearance, not native installation.
    package var permitsFenceRelease: Bool {
        record.broker != nil && stage == .readyToRelease &&
            installedCompletionIsFresh && readinessIsFresh
    }

    /// An extant operation never grants host activation. The caller must clear its exact
    /// durable fence and independently acquire the ordinary shared runtime lock afterward.
    package var permitsRuntimeActivation: Bool { false }

    package init(operationID: UUID, target: Target, predecessor: ArtifactIdentity,
         predecessorMenuInstanceID: UUID) throws {
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
                                predecessorMenuInstanceID: record.predecessorMenuInstanceID)
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
        guard matches(operationID, target), stage == .prepared, record.broker == nil,
              broker.isValid, broker.artifact.version == predecessor.version,
              broker.artifact.build == predecessor.build else { return false }
        record.broker = broker
        return true
    }

    @discardableResult
    package mutating func bindCandidate(_ candidate: ArtifactIdentity, operationID: UUID,
                                target: Target) -> Bool {
        guard matches(operationID, target), record.candidate == nil,
              stage == .prepared || stage == .possiblyArmed,
              candidate.isValid, candidate.build > predecessor.build,
              candidate.executableSHA256 != predecessor.executableSHA256 else { return false }
        record.candidate = candidate
        return true
    }

    @discardableResult
    package mutating func markPossiblyArmed(operationID: UUID, target: Target) -> Bool {
        guard matches(operationID, target), stage == .prepared, record.broker != nil else { return false }
        record.stage = .possiblyArmed
        return true
    }

    /// Caller supplies this only from the supported positive installation callback plus
    /// fresh exact installed-artifact readback. The value itself authenticates nothing.
    @discardableResult
    package mutating func acceptInstalledCompletion(_ completion: InstalledCompletion) -> Bool {
        guard matches(completion.operationID, completion.target), installerMayRemainArmed,
              record.broker != nil, !installedCompletionIsFresh, let candidate,
              completion.candidate == candidate else { return false }
        if stage == .possiblyArmed { record.stage = .installedVerified }
        installedCompletionIsFresh = true
        readinessIsFresh = false
        challenge = nil
        return true
    }

    /// The owner generates the nonce after authenticating a newly launched menu process.
    /// Previously persisted readiness cannot satisfy a new owner's recovery challenge.
    package mutating func issueReadinessChallenge(menuInstanceID: UUID, nonce: UUID) -> ReadinessChallenge? {
        guard installedCompletionIsFresh, !readinessIsFresh, challenge == nil, let candidate,
              Self.isNonce(menuInstanceID), Self.isNonce(nonce),
              menuInstanceID != record.predecessorMenuInstanceID,
              nonce != operationID, nonce != record.predecessorMenuInstanceID,
              nonce != record.readiness?.challengeNonce else { return nil }
        let issued = ReadinessChallenge(operationID: operationID, target: target,
                                        candidate: candidate, menuInstanceID: menuInstanceID,
                                        nonce: nonce)
        challenge = issued
        return issued
    }

    @discardableResult
    package mutating func acceptMenuReadiness(_ readiness: MenuReadiness) -> Bool {
        guard installedCompletionIsFresh, let challenge, readiness.isReady,
              readiness.operationID == challenge.operationID,
              readiness.target == challenge.target, readiness.candidate == challenge.candidate,
              readiness.menuInstanceID == challenge.menuInstanceID,
              readiness.challengeNonce == challenge.nonce else { return false }
        var next = record
        next.readiness = readiness
        next.stage = .readyToRelease
        guard let encoded = try? Self.encode(next), encoded.count <= Self.maximumRecordBytes else {
            return false
        }
        self.challenge = nil
        record = next
        readinessIsFresh = true
        return true
    }

    package mutating func observe(_ observation: NonTerminalObservation) {
        switch observation {
        case .sessionBecameIdle, .cancelled:
            break
        case .updaterFailed, .brokerExited:
            installedCompletionIsFresh = false
            readinessIsFresh = false
            challenge = nil
        }
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
