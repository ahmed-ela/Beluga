import Foundation
import XCTest
@testable import BelugaUpdateCore
@testable import CaptureServer

final class BelugaUpdateOperationTests: XCTestCase {
    private typealias Operation = BelugaUpdateOperation
    private let operationID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let predecessorMenu = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
    private let newMenu = UUID(uuidString: "30000000-0000-4000-8000-000000000003")!
    private let nonce = UUID(uuidString: "40000000-0000-4000-8000-000000000004")!
    private let other = UUID(uuidString: "50000000-0000-4000-8000-000000000005")!

    private func target(path: String = "/Applications/Beluga Host.app", uid: UInt32 = 501) throws -> Operation.Target {
        try Operation.Target(canonicalPath: path, effectiveUID: uid)
    }

    private func artifact(build: UInt64 = 100, hash: String = "a") throws -> Operation.ArtifactIdentity {
        try Operation.ArtifactIdentity(version: "1.0.0", build: build,
                                       executableSHA256: String(repeating: hash, count: 64),
                                       dependencyClosureSHA256: String(repeating: "c", count: 64))
    }

    private func prepared() throws -> Operation {
        var value = try unbound()
        XCTAssertTrue(value.bindBroker(try broker(), operationID: operationID, target: try target()))
        return value
    }

    private func unbound() throws -> Operation {
        try Operation(operationID: operationID, target: target(), predecessor: artifact(),
                      predecessorMenuInstanceID: predecessorMenu)
    }

    private func broker(build: UInt64 = 100, version: String = "1.0.0",
                        cdHash: Data = Data(repeating: 7, count: 20)) throws -> Operation.BrokerBinding {
        try .init(artifact: .init(version: version, build: build,
                                 executableSHA256: String(repeating: "d", count: 64),
                                 dependencyClosureSHA256: String(repeating: "e", count: 64)),
                  nativeCDHash: cdHash)
    }

    private func armed() throws -> Operation {
        var value = try prepared()
        XCTAssertTrue(value.bindCandidate(try artifact(build: 101, hash: "b"),
                                          operationID: operationID, target: try target()))
        XCTAssertTrue(value.markPossiblyArmed(operationID: operationID, target: try target()))
        return value
    }

    private func completion(candidate: Operation.ArtifactIdentity? = nil,
                            operation: UUID? = nil, target: Operation.Target? = nil) throws -> Operation.InstalledCompletion {
        try Operation.InstalledCompletion(operationID: operation ?? operationID,
                                         target: target ?? self.target(),
                                         candidate: candidate ?? artifact(build: 101, hash: "b"))
    }

    private func readiness(_ challenge: Operation.ReadinessChallenge, ready: Bool = true) -> Operation.MenuReadiness {
        Operation.MenuReadiness(operationID: challenge.operationID, target: challenge.target,
                                candidate: challenge.candidate, menuInstanceID: challenge.menuInstanceID,
                                challengeNonce: challenge.nonce, isReady: ready)
    }

    private func released() throws -> Operation {
        var value = try armed()
        XCTAssertTrue(value.acceptInstalledCompletion(try completion()))
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        XCTAssertTrue(value.acceptMenuReadiness(readiness(challenge)))
        return value
    }

    private func mutated(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    func testExactFreshTerminalAndNewMenuProofPermitOnlyFenceRelease() throws {
        var value = try prepared()
        XCTAssertEqual(value.stage, .prepared)
        XCTAssertFalse(value.permitsFenceRelease)
        XCTAssertFalse(value.permitsRuntimeActivation)
        XCTAssertTrue(value.bindCandidate(try artifact(build: 101, hash: "b"),
                                          operationID: operationID, target: try target()))
        XCTAssertTrue(value.markPossiblyArmed(operationID: operationID, target: try target()))
        XCTAssertTrue(value.installerMayRemainArmed)
        XCTAssertFalse(value.permitsFenceRelease)
        XCTAssertTrue(value.acceptInstalledCompletion(try completion()))
        XCTAssertEqual(value.stage, .installedVerified)
        XCTAssertFalse(value.permitsFenceRelease)
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        XCTAssertTrue(value.acceptMenuReadiness(readiness(challenge)))
        XCTAssertEqual(value.stage, .readyToRelease)
        XCTAssertTrue(value.permitsFenceRelease)
        XCTAssertFalse(value.permitsRuntimeActivation, "Durable clearance and host-lock acquisition remain separate")
    }

    func testBrokerIsExactOneTimePreparedBindingAndCannotChangeAfterArming() throws {
        var value = try unbound()
        let expected = try broker()
        XCTAssertNil(value.brokerBinding)
        XCTAssertFalse(value.bindBroker(expected, operationID: other, target: try target()))
        XCTAssertFalse(value.bindBroker(expected, operationID: operationID, target: try target(uid: 502)))
        XCTAssertFalse(value.bindBroker(try broker(build: 99), operationID: operationID, target: try target()))
        XCTAssertFalse(value.bindBroker(try broker(build: 101), operationID: operationID, target: try target()))
        XCTAssertFalse(value.bindBroker(try broker(version: "1.0.1"), operationID: operationID, target: try target()))
        XCTAssertTrue(value.bindBroker(expected, operationID: operationID, target: try target()))
        XCTAssertEqual(value.brokerBinding, expected)
        let bound = try value.encodedRecord()
        XCTAssertFalse(value.bindBroker(expected, operationID: operationID, target: try target()))
        XCTAssertFalse(value.bindBroker(try broker(cdHash: Data(repeating: 9, count: 20)),
                                        operationID: operationID, target: try target()))
        XCTAssertEqual(try value.encodedRecord(), bound)
        XCTAssertTrue(value.markPossiblyArmed(operationID: operationID, target: try target()))
        XCTAssertFalse(value.bindBroker(expected, operationID: operationID, target: try target()))
        XCTAssertEqual(value.brokerBinding, expected)
    }

    func testMissingHistoricalBrokerBindingStaysFencedWithoutInventingFreshAuthority() throws {
        var value = try unbound()
        XCTAssertFalse(value.markPossiblyArmed(operationID: operationID, target: try target()))
        XCTAssertFalse(value.permitsFenceRelease)
        XCTAssertFalse(value.permitsRuntimeActivation)
        for prior in [try unbound(), try armed(), try released()] {
            let legacy = try mutated(prior.encodedRecord()) { $0.removeValue(forKey: "broker") }
            var restored = try Operation.restoring(from: legacy, expectedTarget: target())
            XCTAssertNil(restored.brokerBinding)
            XCTAssertEqual(try restored.encodedRecord(), legacy)
            XCTAssertFalse(restored.permitsFenceRelease)
            XCTAssertFalse(restored.permitsRuntimeActivation)
            XCTAssertFalse(restored.acceptInstalledCompletion(try completion()))
            XCTAssertNil(restored.issueReadinessChallenge(menuInstanceID: newMenu, nonce: other))
        }
    }

    func testBrokerCDHashAndRestoredNestedBindingAreStrictlyValidated() throws {
        for invalid in [Data(), Data(repeating: 7, count: 19), Data(repeating: 7, count: 21),
                        Data(repeating: 0, count: 20)] {
            XCTAssertThrowsError(try broker(cdHash: invalid))
        }
        let bytes = try prepared().encodedRecord()
        let invalidBindings: [(inout [String: Any]) -> Void] = [
            { $0["nativeCDHash"] = Data(repeating: 0, count: 20).base64EncodedString() },
            { $0["nativeCDHash"] = Data(repeating: 7, count: 21).base64EncodedString() },
            { $0["nativeCDHash"] = 7 },
            { $0["extra"] = true },
            { $0.removeValue(forKey: "artifact") },
            { object in
                var nested = object["artifact"] as? [String: Any] ?? [:]
                nested["version"] = "1.0.1"; object["artifact"] = nested
            },
            { object in
                var nested = object["artifact"] as? [String: Any] ?? [:]
                nested["build"] = 101; object["artifact"] = nested
            },
            { object in
                var nested = object["artifact"] as? [String: Any] ?? [:]
                nested["executableSHA256"] = String(repeating: "A", count: 64)
                object["artifact"] = nested
            }
        ]
        for change in invalidBindings {
            let invalid = try mutated(bytes) { object in
                var nested = object["broker"] as? [String: Any] ?? [:]
                change(&nested); object["broker"] = nested
            }
            XCTAssertThrowsError(try Operation.restoring(from: invalid, expectedTarget: target()))
        }
        XCTAssertThrowsError(try Operation.restoring(from: mutated(bytes) { $0["broker"] = NSNull() },
                                                    expectedTarget: target()))
    }

    func testArmingMayPrecedeCandidateDiscoveryButUnknownCandidateCannotFinish() throws {
        var value = try prepared()
        XCTAssertTrue(value.markPossiblyArmed(operationID: operationID, target: try target()))
        XCTAssertFalse(value.acceptInstalledCompletion(try completion()))
        XCTAssertNil(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        XCTAssertTrue(value.bindCandidate(try artifact(build: 101, hash: "b"),
                                          operationID: operationID, target: try target()))
        XCTAssertTrue(value.acceptInstalledCompletion(try completion()))
    }

    func testWrongOperationTargetAndUIDCannotAdvanceAnyAuthority() throws {
        var value = try prepared()
        let candidate = try artifact(build: 101, hash: "b")
        XCTAssertFalse(value.bindCandidate(candidate, operationID: other, target: try target()))
        XCTAssertFalse(value.bindCandidate(candidate, operationID: operationID,
                                           target: try target(path: "/Applications/Other.app")))
        XCTAssertFalse(value.markPossiblyArmed(operationID: operationID, target: try target(uid: 502)))
        XCTAssertEqual(value.stage, .prepared)
        value = try armed()
        XCTAssertFalse(value.acceptInstalledCompletion(try completion(operation: other)))
        XCTAssertFalse(value.acceptInstalledCompletion(try completion(target: target(uid: 502))))
        XCTAssertFalse(value.acceptInstalledCompletion(try completion(target: target(path: "/Applications/Other.app"))))
        XCTAssertEqual(value.stage, .possiblyArmed)
    }

    func testCandidateIsOnceBoundAndRejectsRegressionsOrChangedInstalledBytes() throws {
        var value = try prepared()
        XCTAssertFalse(value.bindCandidate(try artifact(build: 99, hash: "b"), operationID: operationID, target: try target()))
        XCTAssertFalse(value.bindCandidate(try artifact(build: 100, hash: "b"), operationID: operationID, target: try target()))
        XCTAssertFalse(value.bindCandidate(try artifact(build: 101), operationID: operationID, target: try target()))
        let candidate = try artifact(build: 101, hash: "b")
        XCTAssertTrue(value.bindCandidate(candidate, operationID: operationID, target: try target()))
        XCTAssertFalse(value.bindCandidate(candidate, operationID: operationID, target: try target()))
        XCTAssertTrue(value.markPossiblyArmed(operationID: operationID, target: try target()))
        XCTAssertFalse(value.acceptInstalledCompletion(try completion(candidate: artifact(build: 102, hash: "b"))))
        XCTAssertFalse(value.acceptInstalledCompletion(try completion(candidate: artifact(build: 101, hash: "d"))))
        let wrongClosure = try Operation.ArtifactIdentity(version: "1.0.0", build: 101,
            executableSHA256: String(repeating: "b", count: 64), dependencyClosureSHA256: String(repeating: "d", count: 64))
        XCTAssertFalse(value.acceptInstalledCompletion(try completion(candidate: wrongClosure)))
        XCTAssertFalse(value.permitsFenceRelease)
    }

    func testNonTerminalEventsNeverClearTheStickyArmingStage() throws {
        for event in [Operation.NonTerminalObservation.sessionBecameIdle, .cancelled, .updaterFailed, .brokerExited] {
            var value = try armed()
            let before = try value.encodedRecord()
            value.observe(event)
            XCTAssertEqual(try value.encodedRecord(), before)
            XCTAssertTrue(value.installerMayRemainArmed)
            XCTAssertFalse(value.permitsFenceRelease)
            XCTAssertFalse(value.permitsRuntimeActivation)
        }
        var completed = try released()
        completed.observe(.brokerExited)
        XCTAssertEqual(completed.stage, .readyToRelease)
        XCTAssertFalse(completed.permitsFenceRelease)
    }

    func testPreparedOrReplayedTerminalAndReadinessCannotSkipStages() throws {
        var value = try prepared()
        XCTAssertFalse(value.acceptInstalledCompletion(try completion()))
        XCTAssertNil(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        value = try armed()
        XCTAssertFalse(value.markPossiblyArmed(operationID: operationID, target: try target()))
        XCTAssertTrue(value.acceptInstalledCompletion(try completion()))
        XCTAssertFalse(value.acceptInstalledCompletion(try completion()))
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        XCTAssertNil(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: other))
        XCTAssertTrue(value.acceptMenuReadiness(readiness(challenge)))
        XCTAssertFalse(value.acceptMenuReadiness(readiness(challenge)))
        XCTAssertFalse(value.acceptInstalledCompletion(try completion()))
        XCTAssertFalse(value.markPossiblyArmed(operationID: operationID, target: try target()))
        XCTAssertEqual(value.stage, .readyToRelease)
    }

    func testFreshReadinessRequiresDifferentMenuAndExactOneUseChallenge() throws {
        var value = try armed()
        XCTAssertTrue(value.acceptInstalledCompletion(try completion()))
        XCTAssertNil(value.issueReadinessChallenge(menuInstanceID: predecessorMenu, nonce: nonce))
        XCTAssertNil(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: operationID))
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        let invalid: [Operation.MenuReadiness] = [
            readiness(challenge, ready: false),
            Operation.MenuReadiness(operationID: other, target: challenge.target, candidate: challenge.candidate,
                                    menuInstanceID: newMenu, challengeNonce: nonce, isReady: true),
            Operation.MenuReadiness(operationID: operationID, target: try target(uid: 502), candidate: challenge.candidate,
                                    menuInstanceID: newMenu, challengeNonce: nonce, isReady: true),
            Operation.MenuReadiness(operationID: operationID, target: challenge.target, candidate: try artifact(build: 102, hash: "b"),
                                    menuInstanceID: newMenu, challengeNonce: nonce, isReady: true),
            Operation.MenuReadiness(operationID: operationID, target: challenge.target, candidate: challenge.candidate,
                                    menuInstanceID: other, challengeNonce: nonce, isReady: true),
            Operation.MenuReadiness(operationID: operationID, target: challenge.target, candidate: challenge.candidate,
                                    menuInstanceID: newMenu, challengeNonce: other, isReady: true)
        ]
        for wrong in invalid {
            XCTAssertFalse(value.acceptMenuReadiness(wrong))
            XCTAssertFalse(value.permitsFenceRelease)
        }
        XCTAssertTrue(value.acceptMenuReadiness(readiness(challenge)))
    }

    func testEveryRestoredStageIsBlockedAndOldReadinessCannotAuthorizeRecovery() throws {
        var values = [try prepared(), try armed()]
        var installed = try armed()
        XCTAssertTrue(installed.acceptInstalledCompletion(try completion()))
        values.append(installed)
        values.append(try released())
        for value in values {
            let bytes = try value.encodedRecord()
            let restored = try Operation.restoring(from: bytes, expectedTarget: target(), expectedOperationID: operationID)
            XCTAssertEqual(restored.stage, value.stage)
            XCTAssertEqual(try restored.encodedRecord(), bytes)
            XCTAssertFalse(restored.permitsFenceRelease)
            XCTAssertFalse(restored.permitsRuntimeActivation)
        }
        var restored = try Operation.restoring(from: released().encodedRecord(), expectedTarget: target())
        XCTAssertNil(restored.issueReadinessChallenge(menuInstanceID: newMenu, nonce: other))
        XCTAssertTrue(restored.acceptInstalledCompletion(try completion()))
        XCTAssertEqual(restored.stage, .readyToRelease, "Recovery re-proves without stage regression")
        XCTAssertNil(restored.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce), "Old nonce must never revive saved readiness")
        let fresh = try XCTUnwrap(restored.issueReadinessChallenge(menuInstanceID: newMenu, nonce: other))
        let old = Operation.MenuReadiness(operationID: operationID, target: try target(),
            candidate: try artifact(build: 101, hash: "b"), menuInstanceID: newMenu,
            challengeNonce: nonce, isReady: true)
        XCTAssertFalse(restored.acceptMenuReadiness(old))
        XCTAssertFalse(restored.permitsFenceRelease)
        XCTAssertTrue(restored.acceptMenuReadiness(readiness(fresh)))
        XCTAssertTrue(restored.permitsFenceRelease)
    }

    func testRestoreRejectsWrongExpectedBindingsAndUnknownOrIncompleteSchema() throws {
        let bytes = try armed().encodedRecord()
        XCTAssertThrowsError(try Operation.restoring(from: bytes, expectedTarget: target(uid: 502)))
        XCTAssertThrowsError(try Operation.restoring(from: bytes, expectedTarget: target(), expectedOperationID: other))
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["schema"] = "beluga.update-operation.v2" },
            { $0["stage"] = "idle" },
            { $0["stage"] = "readyToRelease" },
            { $0.removeValue(forKey: "predecessorMenuInstanceID") },
            { $0["extra"] = true },
            { $0["candidate"] = NSNull() },
            { $0["operationID"] = "00000000-0000-0000-0000-000000000000" }
        ]
        for mutation in mutations {
            XCTAssertThrowsError(try Operation.restoring(from: mutated(bytes, mutation), expectedTarget: target()))
        }
    }

    func testBoundedCanonicalRecordRejectsOversizeWhitespaceAndDuplicateKeys() throws {
        let bytes = try armed().encodedRecord()
        XCTAssertLessThan(bytes.count, Operation.maximumRecordBytes)
        XCTAssertThrowsError(try Operation.restoring(from: Data(repeating: 32, count: Operation.maximumRecordBytes + 1), expectedTarget: target()))
        XCTAssertThrowsError(try Operation.restoring(from: Data(), expectedTarget: target()))
        var padded = bytes; padded.append(10)
        XCTAssertThrowsError(try Operation.restoring(from: padded, expectedTarget: target()))
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let duplicate = Data(("{\"schema\":\"\(Operation.schema)\"," + text.dropFirst()).utf8)
        XCTAssertThrowsError(try Operation.restoring(from: duplicate, expectedTarget: target()))
    }

    func testDecoderRevalidatesNestedIdentitiesInsteadOfTrustingSynthesizedCodable() throws {
        let bytes = try armed().encodedRecord()
        let nestedMutations: [(inout [String: Any]) -> Void] = [
            { $0["canonicalPath"] = "/Applications/../Beluga Host.app" },
            { $0["bundleIdentifier"] = "other" },
            { $0["teamIdentifier"] = "OTHERTEAM1" }
        ]
        for mutation in nestedMutations {
            let invalid = try mutated(bytes) { object in
                var nested = object["target"] as? [String: Any] ?? [:]
                mutation(&nested)
                object["target"] = nested
            }
            XCTAssertThrowsError(try Operation.restoring(from: invalid, expectedTarget: target()))
        }
        for (field, bad) in [("version", "01.0.0"), ("executableSHA256", String(repeating: "A", count: 64)),
                             ("dependencyClosureSHA256", String(repeating: "0", count: 64))] {
            let invalid = try mutated(bytes) { object in
                var nested = object["candidate"] as? [String: Any] ?? [:]
                nested[field] = bad
                object["candidate"] = nested
            }
            XCTAssertThrowsError(try Operation.restoring(from: invalid, expectedTarget: target()))
        }
    }

    func testUnserializableOversizedTerminalRecordCannotGrantRelease() throws {
        let largeTarget = try target(path: "/" + String(repeating: "\\", count: 4_080) + ".app")
        var value = try Operation(operationID: operationID, target: largeTarget,
                                  predecessor: artifact(), predecessorMenuInstanceID: predecessorMenu)
        XCTAssertTrue(value.bindBroker(try broker(), operationID: operationID, target: largeTarget))
        let candidate = try artifact(build: 101, hash: "b")
        XCTAssertTrue(value.bindCandidate(candidate, operationID: operationID, target: largeTarget))
        XCTAssertTrue(value.markPossiblyArmed(operationID: operationID, target: largeTarget))
        XCTAssertTrue(value.acceptInstalledCompletion(Operation.InstalledCompletion(
            operationID: operationID, target: largeTarget, candidate: candidate)))
        let challenge = try XCTUnwrap(value.issueReadinessChallenge(menuInstanceID: newMenu, nonce: nonce))
        XCTAssertFalse(value.acceptMenuReadiness(readiness(challenge)))
        XCTAssertEqual(value.stage, .installedVerified)
        XCTAssertFalse(value.permitsFenceRelease)
        XCTAssertLessThanOrEqual(try value.encodedRecord().count, Operation.maximumRecordBytes)
    }

    func testTargetAndArtifactValidationAreLexicalNotFilesystemOperations() throws {
        for path in ["relative.app", "/Applications//Beluga.app", "/Applications/../Beluga.app",
                     "/Applications/./Beluga.app", "/Applications/Beluga.app/", "/Applications/Beluga\n.app",
                     "/" + String(repeating: "a", count: 4_096) + ".app"] {
            XCTAssertThrowsError(try target(path: path))
        }
        XCTAssertThrowsError(try Operation.Target(canonicalPath: "/Applications/Beluga.app", effectiveUID: 501, bundleIdentifier: "other"))
        XCTAssertThrowsError(try Operation.Target(canonicalPath: "/Applications/Beluga.app", effectiveUID: 501, teamIdentifier: "OTHERTEAM1"))
        for hash in ["0", "A", "g", ""] { XCTAssertThrowsError(try artifact(hash: hash)) }
        XCTAssertThrowsError(try artifact(build: 0))
        XCTAssertThrowsError(try Operation.ArtifactIdentity(version: "01.0.0", build: 100,
            executableSHA256: String(repeating: "a", count: 64), dependencyClosureSHA256: String(repeating: "c", count: 64)))
    }
}
