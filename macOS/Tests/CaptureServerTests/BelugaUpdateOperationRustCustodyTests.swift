import Foundation
import XCTest
@testable import BelugaUpdateCore

/// Offline copied-result and native value/wire custody only. No installer, filesystem,
/// IPC, signing, host lock, phone, cache, or proof-acquisition path is invoked here.
final class BelugaUpdateOperationRustCustodyTests: XCTestCase {
    private typealias Operation = BelugaUpdateOperation
    private typealias Producer = BelugaRustUpdateOperationProducer
    private let operationID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let predecessorMenu = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
    private let newMenu = UUID(uuidString: "30000000-0000-4000-8000-000000000003")!
    private let nonce = UUID(uuidString: "40000000-0000-4000-8000-000000000004")!
    private let other = UUID(uuidString: "50000000-0000-4000-8000-000000000005")!

    private enum Corruption: CaseIterable, Sendable {
        case decisionDomain, actionDomain, wrongAction, predicateDomain, mutationPredicate
        case resultReserved, stateABI, stateReserved, stateReservedTail, stageDomain
        case brokerDomain, candidateDomain, recordedReadinessDomain, installedFreshDomain
        case readinessFreshDomain, challengeDomain
        case stageMismatch, brokerMismatch, candidateMismatch, recordedReadinessMismatch
        case installedFreshMismatch, readinessFreshMismatch, challengeMismatch
        case invalidInput, deniedPublication, deniedAction, deniedPredicate

        func apply(_ result: inout Producer.Result, before: Producer.State) {
            switch self {
            case .decisionDomain: result.decision = 3
            case .actionDomain: result.action = 9
            case .wrongAction: result.action = 2
            case .predicateDomain: result.predicate = 2
            case .mutationPredicate: result.predicate = 1
            case .resultReserved: result.reserved = 1
            case .stateABI: result.candidate_state.abi_version = 2
            case .stateReserved: result.candidate_state.reserved = 1
            case .stateReservedTail: result.candidate_state.reserved_tail = 1
            case .stageDomain: result.candidate_state.stage = 4
            case .brokerDomain: result.candidate_state.broker_present = 2
            case .candidateDomain: result.candidate_state.candidate_present = 2
            case .recordedReadinessDomain: result.candidate_state.recorded_readiness_present = 2
            case .installedFreshDomain: result.candidate_state.installed_fresh = 2
            case .readinessFreshDomain: result.candidate_state.readiness_fresh = 2
            case .challengeDomain: result.candidate_state.challenge_present = 2
            case .stageMismatch: result.candidate_state.stage = (result.candidate_state.stage + 1) % 4
            case .brokerMismatch: result.candidate_state.broker_present ^= 1
            case .candidateMismatch: result.candidate_state.candidate_present ^= 1
            case .recordedReadinessMismatch: result.candidate_state.recorded_readiness_present ^= 1
            case .installedFreshMismatch: result.candidate_state.installed_fresh ^= 1
            case .readinessFreshMismatch: result.candidate_state.readiness_fresh ^= 1
            case .challengeMismatch: result.candidate_state.challenge_present ^= 1
            case .invalidInput:
                result.candidate_state = before; result.decision = 2
                result.action = 0; result.predicate = 0
            case .deniedPublication:
                result.decision = 1; result.action = 0; result.predicate = 0
            case .deniedAction:
                result.candidate_state = before; result.decision = 1; result.predicate = 0
            case .deniedPredicate:
                result.candidate_state = before; result.decision = 1
                result.action = 0; result.predicate = 1
            }
        }
    }

    private struct Call: Equatable, Sendable {
        let abi: UInt32
        let before: [UInt32]
        let event: [UInt32]
    }

    /// Test-only result corrupter. It calls the actual C producer first and changes only
    /// the selected copied result. Its lock protects instrumentation, not policy proof.
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private let opcode: UInt32?
        private let corruption: Corruption?
        private let ordinaryDenial: Bool
        private var enabled = true
        private var observed: [Call] = []

        init(opcode: UInt32? = nil, corruption: Corruption? = nil, ordinaryDenial: Bool = false) {
            self.opcode = opcode
            self.corruption = corruption
            self.ordinaryDenial = ordinaryDenial
        }

        var producer: Producer {
            Producer(step: { [self] abi, before, event in
                var result = Producer.actual.step(abi, before, event)
                lock.lock()
                defer { lock.unlock() }
                observed.append(Call(abi: abi,
                    before: [before.abi_version, before.reserved, before.stage,
                             before.broker_present, before.candidate_present,
                             before.recorded_readiness_present, before.installed_fresh,
                             before.readiness_fresh, before.challenge_present, before.reserved_tail],
                    event: [event.opcode, event.reserved, event.fact0, event.fact1, event.fact2,
                            event.fact3, event.fact4, event.fact5, event.fact6, event.reserved_tail]))
                if enabled, opcode == event.opcode {
                    if ordinaryDenial {
                        result.candidate_state = before; result.decision = 1
                        result.action = 0; result.predicate = 0; result.reserved = 0
                    } else {
                        corruption?.apply(&result, before: before)
                    }
                }
                return result
            })
        }

        var calls: [Call] {
            lock.lock(); defer { lock.unlock() }
            return observed
        }

        func disableCorruption() {
            lock.lock(); defer { lock.unlock() }
            enabled = false
        }

        func clearCalls() {
            lock.lock(); defer { lock.unlock() }
            observed.removeAll()
        }
    }

    private func target(path: String = "/Applications/Beluga Host.app") throws -> Operation.Target {
        try .init(canonicalPath: path, effectiveUID: 501)
    }

    /// Independent ordering recorder. Every policy entry follows the actual C call;
    /// no result is replaced or corrupted. Only the pre-encoder boundary can throw.
    private final class EncodingTrace: @unchecked Sendable {
        private enum BoundaryFailure: Error { case injectedBeforeEncoder }
        private let lock = NSLock()
        private var observed: [Call] = []
        private var ordered: [String] = []
        private var completedCounts: [Int] = []

        var producer: Producer {
            Producer(step: { [self] abi, before, event in
                let result = Producer.actual.step(abi, before, event)
                lock.lock(); defer { lock.unlock() }
                observed.append(Call(abi: abi,
                    before: [before.abi_version, before.reserved, before.stage,
                             before.broker_present, before.candidate_present,
                             before.recorded_readiness_present, before.installed_fresh,
                             before.readiness_fresh, before.challenge_present, before.reserved_tail],
                    event: [event.opcode, event.reserved, event.fact0, event.fact1, event.fact2,
                            event.fact3, event.fact4, event.fact5, event.fact6, event.reserved_tail]))
                ordered.append("C\(event.opcode)")
                return result
            })
        }

        func encodingProbe(throwsBeforeEncoder: Bool = false) -> Operation.ReadinessEncodingBoundaryProbe {
            .init(before: { [self] in
                lock.lock(); ordered.append("encoder-boundary-entry"); lock.unlock()
                if throwsBeforeEncoder { throw BoundaryFailure.injectedBeforeEncoder }
            }, completed: { [self] count in
                lock.lock(); defer { lock.unlock() }
                ordered.append("foundation-encode-completed")
                completedCounts.append(count)
            })
        }

        var calls: [Call] { lock.lock(); defer { lock.unlock() }; return observed }
        var order: [String] { lock.lock(); defer { lock.unlock() }; return ordered }
        var byteCounts: [Int] { lock.lock(); defer { lock.unlock() }; return completedCounts }
        func clear() {
            lock.lock(); defer { lock.unlock() }
            observed.removeAll(); ordered.removeAll(); completedCounts.removeAll()
        }
    }

    private func artifact(build: UInt64 = 100, hash: String = "a") throws -> Operation.ArtifactIdentity {
        try .init(version: "1.0.0", build: build,
                  executableSHA256: String(repeating: hash, count: 64),
                  dependencyClosureSHA256: String(repeating: "c", count: 64))
    }

    private func broker() throws -> Operation.BrokerBinding {
        try .init(artifact: .init(version: "1.0.0", build: 100,
                                 executableSHA256: String(repeating: "d", count: 64),
                                 dependencyClosureSHA256: String(repeating: "e", count: 64)),
                  nativeCDHash: Data(repeating: 7, count: 20))
    }

    private func unbound(_ producer: Producer = .actual,
                         at selectedTarget: Operation.Target? = nil) throws -> Operation {
        try Operation(operationID: operationID, target: selectedTarget ?? target(),
                      predecessor: artifact(), predecessorMenuInstanceID: predecessorMenu,
                      policyProducer: producer)
    }

    private func armed(_ producer: Producer = .actual,
                       at selectedTarget: Operation.Target? = nil) throws -> Operation {
        let bound = try selectedTarget ?? target()
        var value = try unbound(producer, at: bound)
        XCTAssertTrue(value.bindBroker(try broker(), operationID: operationID, target: bound))
        XCTAssertTrue(value.bindCandidate(try artifact(build: 101, hash: "b"),
                                          operationID: operationID, target: bound))
        XCTAssertTrue(value.markPossiblyArmed(operationID: operationID, target: bound))
        return value
    }

    private func installed(_ producer: Producer = .actual,
                           at selectedTarget: Operation.Target? = nil) throws -> Operation {
        var value = try armed(producer, at: selectedTarget)
        XCTAssertTrue(value.acceptInstalledCompletion(.init(operationID: operationID,
            target: value.target, candidate: try artifact(build: 101, hash: "b"))))
        return value
    }

    private func readiness(_ challenge: Operation.ReadinessChallenge,
                           ready: Bool = true) -> Operation.MenuReadiness {
        .init(operationID: challenge.operationID, target: challenge.target,
              candidate: challenge.candidate, menuInstanceID: challenge.menuInstanceID,
              challengeNonce: challenge.nonce, isReady: ready)
    }

    private func released(_ producer: Producer = .actual) throws -> Operation {
        var value = try installed(producer)
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        XCTAssertTrue(value.acceptMenuReadiness(readiness(challenge)))
        return value
    }

    private func mutated(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    func testMutationResultCorruptionsPublishNoNativeValueOrWireAndLatchLocalFault() throws {
        for corruption in Corruption.allCases {
            let probe = Probe(opcode: 0, corruption: corruption)
            var value = try unbound(probe.producer)
            let before = value
            let wire = try value.encodedRecord()
            XCTAssertFalse(value.bindBroker(try broker(), operationID: operationID, target: try target()),
                           "\(corruption)")
            XCTAssertEqual(value.stage, before.stage, "\(corruption)")
            XCTAssertEqual(value.brokerBinding, before.brokerBinding, "\(corruption)")
            XCTAssertEqual(value.candidate, before.candidate, "\(corruption)")
            XCTAssertEqual(try value.encodedRecord(), wire, "\(corruption)")
            XCTAssertNotEqual(value, before, "Only the local ephemeral fault changes: \(corruption)")
            XCTAssertTrue(value.installerMayRemainArmed, "Unknown armedness is never unarmed proof")
            XCTAssertFalse(value.permitsFenceRelease)
            XCTAssertFalse(value.permitsRuntimeActivation)
            probe.disableCorruption()
            let calls = probe.calls.count
            XCTAssertFalse(value.bindBroker(try broker(), operationID: operationID, target: try target()))
            XCTAssertFalse(value.markPossiblyArmed(operationID: operationID, target: try target()))
            value.observe(.cancelled)
            XCTAssertEqual(probe.calls.count, calls, "Latched value invokes no later producer")
            XCTAssertEqual(try value.encodedRecord(), wire)
        }
    }

    func testOrdinaryClosedMutationDenialIsNotABridgeFaultAndCanRetry() throws {
        let probe = Probe(opcode: 0, ordinaryDenial: true)
        var value = try unbound(probe.producer)
        let before = value
        XCTAssertFalse(value.bindBroker(try broker(), operationID: operationID, target: try target()))
        XCTAssertEqual(value, before)
        XCTAssertFalse(value.installerMayRemainArmed)
        probe.disableCorruption()
        XCTAssertTrue(value.bindBroker(try broker(), operationID: operationID, target: try target()))
        XCTAssertEqual(value.brokerBinding, try broker())
    }

    func testMalformedVoidObserveDeniesFreshReleaseWithoutPublishingOrPoisoningCopies() throws {
        let probe = Probe(opcode: 9, corruption: .resultReserved)
        var value = try released(probe.producer)
        let before = value
        let wire = try value.encodedRecord()
        value.observe(.updaterFailed)
        XCTAssertEqual(try value.encodedRecord(), wire)
        XCTAssertEqual(value.stage, .readyToRelease)
        XCTAssertFalse(value.permitsFenceRelease)
        XCTAssertFalse(value.permitsRuntimeActivation)
        XCTAssertTrue(value.installerMayRemainArmed)
        XCTAssertNotEqual(value, before)
        probe.disableCorruption()
        XCTAssertTrue(before.permitsFenceRelease, "Value copy retains its own available fault field")
        XCTAssertFalse(value.permitsFenceRelease)
        let calls = probe.calls.count
        value.observe(.sessionBecameIdle)
        XCTAssertNil(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: other))
        XCTAssertEqual(probe.calls.count, calls)
    }

    func testDeniedVoidObservationsAreBoundaryFaultsNotSilentRetentionOfFreshProof() throws {
        for opcode in UInt32(7)...UInt32(10) {
            let probe = Probe(opcode: opcode, ordinaryDenial: true)
            var value = try released(probe.producer)
            let before = value
            let wire = try value.encodedRecord()
            switch opcode {
            case 7: value.observe(.sessionBecameIdle)
            case 8: value.observe(.cancelled)
            case 9: value.observe(.updaterFailed)
            default: value.observe(.brokerExited)
            }
            XCTAssertEqual(try value.encodedRecord(), wire)
            XCTAssertNotEqual(value, before)
            XCTAssertTrue(value.installerMayRemainArmed)
            XCTAssertFalse(value.permitsFenceRelease)
            probe.disableCorruption()
            XCTAssertFalse(value.permitsFenceRelease)
            XCTAssertTrue(before.permitsFenceRelease)
        }
    }

    func testMalformedQueriesDenyImmediatelyButDoNotMutateOrLatchAnOperationValue() throws {
        for opcode in UInt32(11)...UInt32(13) {
            for corruption in [Corruption.decisionDomain, .actionDomain, .predicateDomain,
                               .resultReserved, .stageMismatch, .invalidInput] {
                let probe = Probe(opcode: opcode, corruption: corruption)
                let value = try released(probe.producer)
                let copy = value
                let wire = try value.encodedRecord()
                switch opcode {
                case 11: XCTAssertTrue(value.installerMayRemainArmed)
                case 12: XCTAssertFalse(value.permitsFenceRelease)
                default: XCTAssertFalse(value.permitsRuntimeActivation)
                }
                XCTAssertEqual(value, copy)
                XCTAssertEqual(try value.encodedRecord(), wire)
                probe.disableCorruption()
                XCTAssertTrue(value.installerMayRemainArmed)
                XCTAssertTrue(value.permitsFenceRelease, "A query-only failure is not a sticky mutation")
                XCTAssertFalse(value.permitsRuntimeActivation)
            }
        }
        let denied = Probe(opcode: 11, ordinaryDenial: true)
        let prepared = try unbound(denied.producer)
        XCTAssertTrue(prepared.installerMayRemainArmed, "Denied query cannot authorize prepared retirement")
        denied.disableCorruption()
        XCTAssertFalse(prepared.installerMayRemainArmed)
    }

    func testNewValidatedInstanceIsOnlyMutationFaultRecoveryAndNeverRestoresFreshProof() throws {
        let probe = Probe(opcode: 10, corruption: .decisionDomain)
        var value = try released(probe.producer)
        let wire = try value.encodedRecord()
        value.observe(.brokerExited)
        probe.disableCorruption()
        XCTAssertFalse(value.permitsFenceRelease)
        var restored = try Operation.restoring(from: wire, expectedTarget: try target(),
            expectedOperationID: operationID, policyProducer: probe.producer)
        XCTAssertEqual(try restored.encodedRecord(), wire)
        XCTAssertEqual(restored.stage, .readyToRelease)
        XCTAssertFalse(restored.permitsFenceRelease)
        XCTAssertNil(restored.issueReadinessChallenge(menuInstanceID: newMenu, nonce: other))
        XCTAssertTrue(restored.acceptInstalledCompletion(.init(operationID: operationID,
            target: try target(), candidate: try artifact(build: 101, hash: "b"))))
        XCTAssertNil(restored.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce),
                     "The recorded old challenge nonce cannot reprove release")
        let challenge = try XCTUnwrap(restored.issueReadinessChallenge(menuInstanceID: newMenu, nonce: other))
        XCTAssertTrue(restored.acceptMenuReadiness(readiness(challenge)))
        XCTAssertTrue(restored.permitsFenceRelease)
        XCTAssertFalse(restored.permitsRuntimeActivation)
        XCTAssertFalse(value.permitsFenceRelease, "Recovering a new value cannot reset the old one")
    }

    func testClosedTrueRuntimePredicateIsRejectedAfterActualCResultWithoutGrantingActivation() throws {
        let probe = Probe(opcode: 13, corruption: .mutationPredicate)
        let value = try released(probe.producer)
        let before = value
        let wire = try value.encodedRecord()
        probe.clearCalls()
        XCTAssertFalse(value.permitsRuntimeActivation,
                       "Extant operation cannot grant activation from a closed but forbidden true")
        XCTAssertEqual(probe.calls.map { $0.event[0] }, [13])
        XCTAssertEqual(value, before, "The rejection is a nonmutating query")
        XCTAssertEqual(try value.encodedRecord(), wire)
        probe.disableCorruption()
        XCTAssertFalse(value.permitsRuntimeActivation)
        XCTAssertTrue(value.permitsFenceRelease, "No query-only fault is persisted or latched")
    }

    func testEqualityIgnoresProducerClosureButIncludesEveryEphemeralProofAndValueFault() throws {
        let probe = Probe(opcode: 0, corruption: .predicateDomain)
        var injected = try unbound(probe.producer)
        let actual = try unbound()
        XCTAssertEqual(injected, actual)
        XCTAssertEqual(try injected.encodedRecord(), try actual.encodedRecord())
        XCTAssertFalse(injected.bindBroker(try broker(), operationID: operationID, target: try target()))
        XCTAssertNotEqual(injected, actual)
        let restored = try Operation.restoring(from: injected.encodedRecord(), expectedTarget: try target())
        XCTAssertEqual(restored, actual, "Fault and producer do not enter the canonical record")
        let fresh = try released()
        let historical = try Operation.restoring(from: fresh.encodedRecord(), expectedTarget: try target())
        XCTAssertNotEqual(fresh, historical, "Native freshness remains part of equality")
        let installedValue = try installed()
        var challenged = installedValue
        XCTAssertNotNil(challenged.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        XCTAssertNotEqual(challenged, installedValue, "Native one-use challenge remains part of equality")
    }

    func testReadinessUsesTwoCallsOnOriginalSnapshotAndExactNativeEncodingBoundFact() throws {
        let probe = Probe()
        var value = try installed(probe.producer)
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        probe.clearCalls()
        XCTAssertTrue(value.acceptMenuReadiness(readiness(challenge)))
        let calls = probe.calls
        XCTAssertEqual(calls.count, 2)
        let preflight = try XCTUnwrap(calls.first)
        let commit = try XCTUnwrap(calls.count == 2 ? calls.last : nil)
        XCTAssertEqual(calls.map { $0.abi }, [1, 1])
        XCTAssertEqual(calls.map { $0.event[0] }, [5, 6])
        XCTAssertEqual(preflight.before, [1, 0, 2, 1, 1, 0, 1, 0, 1, 0])
        XCTAssertEqual(commit.before, preflight.before)
        XCTAssertEqual(Array(preflight.event[2...7]), [1, 1, 1, 1, 1, 1])
        XCTAssertEqual(Array(commit.event[2...7]), Array(preflight.event[2...7]))
        XCTAssertEqual(preflight.event[8], 0)
        XCTAssertEqual(commit.event[8], 1)
        XCTAssertEqual(value.stage, .readyToRelease)
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: value.encodedRecord()) as? [String: Any])
        XCTAssertEqual(record["stage"] as? String, "readyToRelease")
        let terminal = try XCTUnwrap(record["readiness"] as? [String: Any])
        XCTAssertEqual(terminal["challengeNonce"] as? String, nonce.uuidString)
    }

    func testDeniedReadinessPreflightHasZeroEncoderBoundaryEntriesAndNoPublication() throws {
        let trace = EncodingTrace()
        var value = try installed(trace.producer)
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        let before = value
        let wire = try value.encodedRecord()
        trace.clear()
        XCTAssertFalse(value.acceptMenuReadiness(readiness(challenge, ready: false),
                                               encodingProbe: trace.encodingProbe()))
        XCTAssertEqual(trace.order, ["C5"])
        XCTAssertEqual(trace.byteCounts, [])
        XCTAssertEqual(trace.calls.map { $0.abi }, [1])
        XCTAssertEqual(trace.calls.map { $0.event }, [[5, 0, 0, 1, 1, 1, 1, 1, 0, 0]])
        XCTAssertEqual(value, before, "Record, challenge, freshness and value fault are unchanged")
        XCTAssertEqual(try value.encodedRecord(), wire)
        XCTAssertFalse(value.permitsFenceRelease)
        XCTAssertFalse(value.permitsRuntimeActivation)
    }

    func testReadinessRunsSingleActualFoundationEncodingBetweenOriginalSnapshotC5AndC6() throws {
        let trace = EncodingTrace()
        var value = try installed(trace.producer)
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        trace.clear()
        XCTAssertTrue(value.acceptMenuReadiness(readiness(challenge), encodingProbe: trace.encodingProbe()))
        XCTAssertEqual(trace.order, ["C5", "encoder-boundary-entry", "foundation-encode-completed", "C6"])
        let calls = trace.calls
        XCTAssertEqual(calls.map { $0.abi }, [1, 1])
        XCTAssertEqual(calls.map { $0.event[0] }, [5, 6])
        let preflight = try XCTUnwrap(calls.first)
        let commit = try XCTUnwrap(calls.count == 2 ? calls.last : nil)
        XCTAssertEqual(preflight.before, [1, 0, 2, 1, 1, 0, 1, 0, 1, 0])
        XCTAssertEqual(commit.before, preflight.before)
        XCTAssertEqual(preflight.event, [5, 0, 1, 1, 1, 1, 1, 1, 0, 0])
        XCTAssertEqual(commit.event, [6, 0, 1, 1, 1, 1, 1, 1, 1, 0])
        XCTAssertEqual(trace.byteCounts, [try value.encodedRecord().count])
        XCTAssertEqual(value.stage, .readyToRelease)
        XCTAssertTrue(value.permitsFenceRelease)
        XCTAssertFalse(value.permitsRuntimeActivation)
    }

    func testInjectedPreEncoderThrowDeniesC6WithoutLosingFreshChallengeAndRetryWorks() throws {
        let trace = EncodingTrace()
        var value = try installed(trace.producer)
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        let readiness = readiness(challenge)
        let before = value
        let wire = try value.encodedRecord()
        trace.clear()
        XCTAssertFalse(value.acceptMenuReadiness(readiness,
            encodingProbe: trace.encodingProbe(throwsBeforeEncoder: true)))
        XCTAssertEqual(trace.order, ["C5", "encoder-boundary-entry", "C6"])
        XCTAssertEqual(trace.byteCounts, [], "The injected pre-encoder boundary throw never completed Foundation encoding")
        let calls = trace.calls
        XCTAssertEqual(calls.map { $0.abi }, [1, 1])
        XCTAssertEqual(calls.map { $0.event[0] }, [5, 6])
        let preflight = try XCTUnwrap(calls.first)
        let commit = try XCTUnwrap(calls.count == 2 ? calls.last : nil)
        XCTAssertEqual(preflight.before, [1, 0, 2, 1, 1, 0, 1, 0, 1, 0])
        XCTAssertEqual(commit.before, preflight.before)
        XCTAssertEqual(preflight.event, [5, 0, 1, 1, 1, 1, 1, 1, 0, 0])
        XCTAssertEqual(commit.event, [6, 0, 1, 1, 1, 1, 1, 1, 0, 0])
        XCTAssertEqual(value, before, "Ordinary C6 denial preserves challenge, native freshness and no bridge fault")
        XCTAssertEqual(try value.encodedRecord(), wire)
        XCTAssertFalse(value.permitsFenceRelease)
        XCTAssertFalse(value.permitsRuntimeActivation)
        trace.clear()
        XCTAssertTrue(value.acceptMenuReadiness(readiness, encodingProbe: trace.encodingProbe()),
                      "Retry must use the same original challenge, not issue a new one")
        XCTAssertEqual(trace.order, ["C5", "encoder-boundary-entry", "foundation-encode-completed", "C6"])
        XCTAssertEqual(trace.calls.map { $0.event[0] }, [5, 6])
        XCTAssertEqual(trace.calls.first?.before, preflight.before)
        XCTAssertEqual(trace.calls.last?.before, preflight.before)
        XCTAssertEqual(trace.calls.last?.event, [6, 0, 1, 1, 1, 1, 1, 1, 1, 0])
        XCTAssertEqual(trace.byteCounts, [try value.encodedRecord().count])
        XCTAssertTrue(value.permitsFenceRelease)
        XCTAssertFalse(value.permitsRuntimeActivation)
    }

    func testReadinessPreflightDenialNeverCommitsAndCommitCorruptionNeverPublishes() throws {
        for opcode in [UInt32(5), UInt32(6)] {
            let probe = Probe(opcode: opcode, corruption: .candidateMismatch)
            var value = try installed(probe.producer)
            let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
            let before = value
            let wire = try value.encodedRecord()
            probe.clearCalls()
            XCTAssertFalse(value.acceptMenuReadiness(readiness(challenge)))
            XCTAssertEqual(try value.encodedRecord(), wire)
            XCTAssertEqual(value.stage, before.stage)
            XCTAssertNotEqual(value, before)
            XCTAssertEqual(probe.calls.map { $0.event[0] }, opcode == 5 ? [5] : [5, 6])
            XCTAssertFalse(value.permitsFenceRelease)
        }
        let probe = Probe()
        var value = try installed(probe.producer)
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        let before = value
        probe.clearCalls()
        XCTAssertFalse(value.acceptMenuReadiness(readiness(challenge, ready: false)))
        XCTAssertEqual(value, before)
        XCTAssertEqual(probe.calls.map { $0.event[0] }, [5])
    }

    func testOversizedTerminalEncodingDeniesCommitWithoutLosingOriginalFreshChallenge() throws {
        let probe = Probe()
        let largeTarget = try target(path: "/" + String(repeating: "\\", count: 4_080) + ".app")
        var value = try installed(probe.producer, at: largeTarget)
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        let before = value
        let wire = try value.encodedRecord()
        probe.clearCalls()
        XCTAssertFalse(value.acceptMenuReadiness(readiness(challenge)))
        XCTAssertEqual(value, before)
        XCTAssertEqual(try value.encodedRecord(), wire)
        let calls = probe.calls
        XCTAssertEqual(calls.map { $0.event[0] }, [5, 6])
        let preflight = try XCTUnwrap(calls.first)
        let commit = try XCTUnwrap(calls.count == 2 ? calls.last : nil)
        XCTAssertEqual(preflight.before, commit.before)
        XCTAssertEqual(commit.event[8], 0)
        XCTAssertFalse(value.permitsFenceRelease)
    }

    func testCanonicalWireAndAsymmetricHistoricalRecordShapesAreUnchanged() throws {
        let initial = try unbound()
        let wire = try initial.encodedRecord()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["schema", "operationID", "target", "predecessor",
                                             "predecessorMenuInstanceID", "stage"]))
        XCTAssertEqual(object["schema"] as? String, "beluga.update-operation.v1")
        XCTAssertThrowsError(try Operation.restoring(from: Data(" ".utf8) + wire, expectedTarget: try target()))
        let extra = try mutated(wire) { $0["policyUnavailable"] = false }
        XCTAssertThrowsError(try Operation.restoring(from: extra, expectedTarget: try target()))
        let explicitNull = try mutated(wire) { $0["broker"] = NSNull() }
        XCTAssertThrowsError(try Operation.restoring(from: explicitNull, expectedTarget: try target()))
        XCTAssertEqual(try Operation.restoring(from: wire, expectedTarget: try target()), initial)

        // Prepared/armed restoration does not require a historical broker. Installed
        // restoration requires candidate, not broker; method admission still does.
        let armedWithoutBroker = try mutated(wire) { $0["stage"] = "possiblyArmed" }
        let prepared = try Operation.restoring(from: wire, expectedTarget: try target())
        let armed = try Operation.restoring(from: armedWithoutBroker, expectedTarget: try target())
        XCTAssertFalse(prepared.installerMayRemainArmed)
        XCTAssertTrue(armed.installerMayRemainArmed)
        XCTAssertFalse(armed.permitsFenceRelease)
        let installedWire = try mutated(installed().encodedRecord()) { $0.removeValue(forKey: "broker") }
        var historical = try Operation.restoring(from: installedWire, expectedTarget: try target())
        XCTAssertEqual(historical.stage, .installedVerified)
        XCTAssertNil(historical.brokerBinding)
        XCTAssertEqual(try historical.encodedRecord(), installedWire)
        XCTAssertFalse(historical.acceptInstalledCompletion(.init(operationID: operationID,
            target: try target(), candidate: try artifact(build: 101, hash: "b"))))
        XCTAssertFalse(historical.permitsFenceRelease)
        let missingCandidate = try mutated(installedWire) { $0.removeValue(forKey: "candidate") }
        XCTAssertThrowsError(try Operation.restoring(from: missingCandidate, expectedTarget: try target()))
        let readyWire = try mutated(released().encodedRecord()) { $0.removeValue(forKey: "broker") }
        let readyWithoutBroker = try Operation.restoring(from: readyWire, expectedTarget: try target())
        XCTAssertEqual(readyWithoutBroker.stage, .readyToRelease)
        XCTAssertEqual(try readyWithoutBroker.encodedRecord(), readyWire)
        XCTAssertFalse(readyWithoutBroker.permitsFenceRelease)
    }

    func testCopiedABILayoutUsesOnlyExactWordStructs() {
        XCTAssertEqual(MemoryLayout<Producer.State>.size, 40)
        XCTAssertEqual(MemoryLayout<Producer.State>.alignment, 4)
        XCTAssertEqual(MemoryLayout<Producer.Event>.size, 40)
        XCTAssertEqual(MemoryLayout<Producer.Event>.alignment, 4)
        XCTAssertEqual(MemoryLayout<Producer.Result>.size, 56)
        XCTAssertEqual(MemoryLayout<Producer.Result>.alignment, 4)
    }

    func testExactNativeBindingNonceAndReadinessFactsAreCopiedNotBroadAuthority() throws {
        let probe = Probe()
        var value = try unbound(probe.producer)
        XCTAssertFalse(value.bindBroker(try broker(), operationID: other, target: try target()))
        XCTAssertEqual(probe.calls.last?.event, [0, 0, 0, 1, 1, 1, 0, 0, 0, 0])
        XCTAssertTrue(value.bindBroker(try broker(), operationID: operationID, target: try target()))
        XCTAssertFalse(value.bindCandidate(try artifact(), operationID: operationID, target: try target()))
        XCTAssertEqual(probe.calls.last?.event, [1, 0, 1, 1, 0, 0, 0, 0, 0, 0])
        XCTAssertTrue(value.bindCandidate(try artifact(build: 101, hash: "b"),
                                          operationID: operationID, target: try target()))
        XCTAssertEqual(probe.calls.last?.event, [1, 0, 1, 1, 1, 1, 0, 0, 0, 0])
        XCTAssertTrue(value.markPossiblyArmed(operationID: operationID, target: try target()))
        XCTAssertEqual(probe.calls.last?.event, [2, 0, 1, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertFalse(value.acceptInstalledCompletion(.init(operationID: operationID,
            target: try target(path: "/Applications/Other.app"), candidate: try artifact(build: 101, hash: "b"))))
        XCTAssertEqual(probe.calls.last?.event, [3, 0, 0, 1, 0, 0, 0, 0, 0, 0])
        XCTAssertTrue(value.acceptInstalledCompletion(.init(operationID: operationID,
            target: try target(), candidate: try artifact(build: 101, hash: "b"))))
        XCTAssertNil(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: operationID))
        XCTAssertEqual(probe.calls.last?.event, [4, 0, 1, 1, 1, 0, 1, 1, 0, 0])
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        let before = value
        probe.clearCalls()
        let wrongMenu = Operation.MenuReadiness(operationID: challenge.operationID, target: challenge.target,
            candidate: challenge.candidate, menuInstanceID: other, challengeNonce: challenge.nonce, isReady: true)
        XCTAssertFalse(value.acceptMenuReadiness(wrongMenu))
        XCTAssertEqual(value, before)
        XCTAssertEqual(probe.calls.map { $0.event }, [[5, 0, 1, 1, 1, 1, 0, 1, 0, 0]])
    }
}
