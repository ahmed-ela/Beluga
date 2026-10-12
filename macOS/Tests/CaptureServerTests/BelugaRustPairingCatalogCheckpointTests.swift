import BelugaCore
import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

/// Real Rust exports and concrete catalog, with only in-memory persistence.
/// Access attempts are counted before a configured backend error is thrown.
final class BelugaRustPairingCatalogCheckpointTests: XCTestCase {
    func testRevokedCheckpointNeverCallsOwnerOrCatalog() throws {
        let f = try fixture()
        f.cursor.revoke()
        f.memory.resetCounts()
        expect(.staleAttempt) { try f.cursor.add(f.pending) }
        expect(.staleAttempt) { try f.cursor.update(f.pending) }
        XCTAssertEqual(f.owner.calls, 0)
        XCTAssertEqual(f.memory.counts, .zero)
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 2)
    }

    func testInvalidProcessOwnerRefusesAllCatalogAccess() throws {
        let f = try fixture()
        f.owner.valid = false
        expect(.staleAttempt) { try f.cursor.add(f.pending) }
        expect(.staleAttempt) { try f.cursor.update(f.pending) }
        XCTAssertEqual(f.owner.calls, 2)
        XCTAssertEqual(f.memory.counts, .zero)
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 0)
        f.owner.valid = true
        try f.cursor.add(f.pending)
        f.owner.valid = false
        f.memory.resetCounts()
        expect(.staleAttempt) { try f.cursor.update(f.proposed) }
        XCTAssertEqual(f.memory.counts, .zero)
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 1)
    }

    func testCheckpointAddsExactlyOnceEvenForDifferentValidPhone() throws {
        let f = try fixture()
        try f.cursor.add(f.pending)
        let second = try pair(host: f.host).pending
        f.memory.resetCounts()
        expect(.staleAttempt) { try f.cursor.add(second) }
        XCTAssertEqual(f.owner.calls, 2) // Bound refusal comes after owner callback.
        XCTAssertEqual(f.memory.counts, .zero)
        XCTAssertEqual(try f.cursor.readback().record, f.pending)
    }

    func testDeviceUUIDMismatchRefusesAllCatalogAccess() throws {
        try mismatch("remoteDeviceID")
    }

    func testPairUUIDMismatchRefusesAllCatalogAccess() throws {
        try mismatch("pairID")
    }

    func testCommitUUIDMismatchRefusesAllCatalogAccess() throws {
        try mismatch("commitID")
    }

    func testThrowingAddAndUpdatePreserveActualCheckpointState() throws {
        let f = try fixture()
        let original = try f.cursor.readback()
        f.memory.failure = .writeBefore
        expectStorage(f.memory.sentinel(.writeBefore)) { try f.cursor.add(f.pending) }
        XCTAssertEqual(f.memory.counts.writes, 1)
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 0)
        f.memory.failure = nil
        XCTAssertEqual(try f.cursor.readback().snapshot, original.snapshot)
        XCTAssertNil(try f.cursor.readback().record)
        try f.cursor.add(f.pending) // Actual failed Add remains retryable.
        let added = try f.cursor.readback()
        f.memory.resetCounts()
        f.memory.failure = .writeBefore
        expectStorage(f.memory.sentinel(.writeBefore)) { try f.cursor.update(f.proposed) }
        XCTAssertEqual(f.memory.counts.writes, 1) // A valid recovery-state advance, not a no-op.
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 1)
        f.memory.failure = nil
        XCTAssertEqual(try f.cursor.readback().snapshot, added.snapshot)
        XCTAssertEqual(try f.cursor.readback().record, f.pending)
        try f.cursor.update(f.proposed)
        XCTAssertEqual(try f.cursor.readback().record, f.proposed)
    }

    func testRevocationRetainsExactPairForInterruptedReadback() throws {
        let f = try fixture()
        try f.cursor.add(f.pending)
        try f.cursor.update(f.proposed)
        let prior = try f.cursor.readback()
        f.cursor.revoke()
        f.cursor.revoke()
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 3)
        XCTAssertEqual(try f.cursor.readback().record, f.proposed)
        XCTAssertEqual(try f.cursor.readback().snapshot, prior.snapshot)
    }

    func testEqualRevisionDifferentSnapshotCannotPassReadback() throws {
        let f = try fixture()
        try f.cursor.add(f.pending)
        let original = try f.cursor.readback().snapshot
        try f.memory.changeCatalog { $0["selectedPhoneID"] = f.pending.remoteDeviceID.uuidString }
        let fresh = try f.store.phoneCatalog.loadOrMigrate(for: f.host)
        XCTAssertEqual(fresh.token, original.token)
        XCTAssertNotEqual(fresh, original)
        expect(.staleAttempt) { _ = try f.cursor.readback() }
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 1)
        XCTAssertFalse(f.cursor.bridgeFaultedForTesting)
    }

    func testMalformedAllowedCandidateCannotAuthorizeNativeWrite() throws {
        let producer = BelugaRustPairingCatalogCheckpointProducer(
            initial: BelugaRustPairingCatalogCheckpointProducer.actual.initial,
            step: { abi, before, event in
                var result = beluga_core_pairing_catalog_checkpoint_step(abi, before, event)
                if event.opcode == 0 { result.candidate_state.flags = 0 }
                return result
            })
        let f = try fixture(producer: producer)
        expect(.invalidCheckpointBridge) { try f.cursor.add(f.pending) }
        XCTAssertEqual(f.memory.counts, .zero)
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 0)
        XCTAssertTrue(f.cursor.bridgeFaultedForTesting)
        let calls = f.owner.calls
        expect(.invalidCheckpointBridge) { try f.cursor.add(f.pending) }
        XCTAssertEqual(f.owner.calls, calls)
        XCTAssertEqual(f.memory.counts, .zero)
    }

    func testReadbackAfterRevokeAndOwnerLossStillReturnsExactPair() throws {
        let f = try fixture()
        try f.cursor.add(f.pending)
        f.owner.valid = false
        f.cursor.revoke()
        let calls = f.owner.calls
        let result = Result { try f.cursor.readback() }
        switch result {
        case .success(let value): XCTAssertEqual(value.record, f.pending)
        case .failure(let error): XCTFail("Readback must not require write authority: \(error)")
        }
        XCTAssertEqual(f.owner.calls, calls)
    }

    func testReadbackLoadErrorPrecedesSnapshotPolicyOrBridgeFault() throws {
        let f = try fixture()
        f.cursor.revoke()
        f.memory.failure = .read
        expectStorage(f.memory.sentinel(.read)) { _ = try f.cursor.readback() }
        XCTAssertEqual(f.memory.counts.reads, 1)
        XCTAssertFalse(f.cursor.bridgeFaultedForTesting)
        let bad = BelugaRustPairingCatalogCheckpointProducer(
            initial: { var s = beluga_core_pairing_catalog_checkpoint_initial(); s.abi_version = 2; return s },
            step: BelugaRustPairingCatalogCheckpointProducer.actual.step)
        let broken = try fixture(producer: bad)
        broken.memory.failure = .read
        expectStorage(broken.memory.sentinel(.read)) { _ = try broken.cursor.readback() }
        XCTAssertEqual(broken.memory.counts.reads, 1)
    }

    func testWriteThenThrowDoesNotInventRollbackOrBindingSuccess() throws {
        let f = try fixture()
        f.memory.failure = .writeAfter
        expectStorage(f.memory.sentinel(.writeAfter)) { try f.cursor.add(f.pending) }
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 0)
        f.memory.failure = nil
        XCTAssertEqual(try f.store.phoneCatalog.loadOrMigrate(for: f.host).records, [f.pending])
        expect(.staleAttempt) { _ = try f.cursor.readback() }
        XCTAssertThrowsError(try f.cursor.add(f.pending)) {
            XCTAssertEqual($0 as? WorldwidePairedPhoneCatalogError, .staleCatalog)
        }
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 0)
    }

    func testNativeAliasesShareRevocationWithoutAffectingAnotherAttempt() throws {
        let f = try fixture()
        let alias = f.cursor
        let independent = WorldwidePairingCatalogCheckpoint(store: f.store, identity: f.host,
            snapshot: try f.store.phoneCatalog.loadOrMigrate(for: f.host), ownerIsValid: { true })
        alias.revoke()
        expect(.staleAttempt) { try f.cursor.add(f.pending) }
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 2)
        XCTAssertEqual(independent.copiedStateForTesting.flags, 0)
        try independent.add(f.pending)
        XCTAssertEqual(independent.copiedStateForTesting.flags, 1)
    }

    func testCatalogGenerationRevisionRecordAndLegacyReceiptAllFenceReadback() throws {
        let variants: [(inout [String: Any]) -> Void] = [
            { $0["catalogID"] = UUID().uuidString },
            { $0["revision"] = UInt64(3) },
            { object in
                var records = object["records"] as! [[String: Any]]
                records[0]["nextOutboundReconnectSequence"] = UInt64(19)
                object["records"] = records
            },
            { object in
                let record = (object["records"] as! [[String: Any]])[0]
                object["legacyImportReceipt"] = [
                    "sourceAccount": WorldwidePairingStore.pairedViewerAccount,
                    "sourceSHA256": Data(repeating: 7, count: 32).base64EncodedString(),
                    "remoteDeviceID": record["remoteDeviceID"]!,
                    "pairID": record["pairID"]!, "commitID": record["commitID"]!,
                ]
            },
        ]
        for change in variants {
            let f = try fixture()
            try f.cursor.add(f.pending)
            let before = try f.cursor.readback().snapshot
            try f.memory.changeCatalog(change)
            let fresh = try f.store.phoneCatalog.loadOrMigrate(for: f.host)
            XCTAssertNotEqual(fresh, before)
            expect(.staleAttempt) { _ = try f.cursor.readback() }
            XCTAssertFalse(f.cursor.bridgeFaultedForTesting)
        }
    }

    func testMalformedRevokeIsStickyWithoutErasingKnownSnapshotOrBinding() throws {
        let producer = BelugaRustPairingCatalogCheckpointProducer(
            initial: BelugaRustPairingCatalogCheckpointProducer.actual.initial,
            step: { abi, before, event in
                var result = beluga_core_pairing_catalog_checkpoint_step(abi, before, event)
                if event.opcode == 2 { result.candidate_state.flags = 0 }
                return result
            })
        let f = try fixture(producer: producer)
        try f.cursor.add(f.pending)
        let saved = try f.cursor.readback().snapshot
        f.cursor.revoke()
        XCTAssertTrue(f.cursor.bridgeFaultedForTesting)
        XCTAssertEqual(f.cursor.copiedStateForTesting.flags, 1)
        f.memory.resetCounts()
        expect(.invalidCheckpointBridge) { try f.cursor.update(f.proposed) }
        XCTAssertEqual(f.memory.counts, .zero)
        XCTAssertEqual(try f.store.phoneCatalog.loadOrMigrate(for: f.host), saved)
        expect(.invalidCheckpointBridge) { _ = try f.cursor.readback() }
    }

    func testMalformedInitialCannotInvokeOwnerOrStore() throws {
        let producer = BelugaRustPairingCatalogCheckpointProducer(
            initial: { var s = beluga_core_pairing_catalog_checkpoint_initial(); s.flags = 1; return s },
            step: BelugaRustPairingCatalogCheckpointProducer.actual.step)
        let f = try fixture(producer: producer)
        expect(.invalidCheckpointBridge) { try f.cursor.add(f.pending) }
        XCTAssertEqual(f.owner.calls, 0)
        XCTAssertEqual(f.memory.counts, .zero)
        f.cursor.revoke()
        XCTAssertTrue(f.cursor.bridgeFaultedForTesting)
    }

    func testActualCopiedBoundaryAndLayoutsPreserveAllValidCases() {
        typealias B = BelugaRustPairingCatalogCheckpointBoundary
        XCTAssertEqual(MemoryLayout<B.State>.size, 8)
        XCTAssertEqual(MemoryLayout<B.Event>.size, 16)
        XCTAssertEqual(MemoryLayout<B.Output>.size, 12)
        for flags: UInt32 in 0..<4 {
            var before = B.State(); before.abi_version = 1; before.flags = flags
            for opcode: UInt32 in 0..<4 {
                for facts: UInt32 in 0..<8 {
                    var event = B.Event(); event.opcode = opcode
                    event.owner_valid = facts & 1
                    event.binding_matches = (facts >> 1) & 1
                    event.snapshot_matches = (facts >> 2) & 1
                    let output = beluga_core_pairing_catalog_checkpoint_step(1, before, event)
                    XCTAssertTrue(B.accepts(before: before, event: event, output: output))
                    var corrupted = output; corrupted.candidate_state.flags ^= 4
                    XCTAssertFalse(B.accepts(before: before, event: event, output: corrupted))
                    corrupted = output; corrupted.decision = 3
                    XCTAssertFalse(B.accepts(before: before, event: event, output: corrupted))
                    for candidateFlags: UInt32 in 0..<4 {
                        for decision: UInt32 in [0, 1, 2, 3, UInt32.max] {
                            if candidateFlags == output.candidate_state.flags && decision == output.decision { continue }
                            corrupted = output
                            corrupted.candidate_state.flags = candidateFlags
                            corrupted.decision = decision
                            XCTAssertFalse(B.accepts(before: before, event: event, output: corrupted))
                        }
                    }
                    for abi: UInt32 in [0, 2, UInt32.max] {
                        corrupted = output; corrupted.candidate_state.abi_version = abi
                        XCTAssertFalse(B.accepts(before: before, event: event, output: corrupted))
                    }
                }
            }
        }
    }

    private func mismatch(_ key: String) throws {
        let f = try fixture()
        try f.cursor.add(f.pending)
        let wrong = try changedRecord(f.pending) { $0[key] = UUID().uuidString }
        f.memory.resetCounts()
        expect(.staleAttempt) { try f.cursor.update(wrong) }
        XCTAssertEqual(f.memory.counts, .zero)
        XCTAssertFalse(f.cursor.bridgeFaultedForTesting)
        XCTAssertEqual(try f.cursor.readback().record, f.pending)
    }

    private func expect(_ expected: WorldwidePhoneCatalogRuntimeError,
                        _ operation: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? WorldwidePhoneCatalogRuntimeError, expected, file: file, line: line)
        }
    }

    private func expectStorage(_ expected: CheckpointMemory.Sentinel,
                               _ operation: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertTrue(($0 as? CheckpointMemory.Sentinel) === expected, file: file, line: line)
        }
    }

    private func fixture(producer: BelugaRustPairingCatalogCheckpointProducer = .actual) throws -> Fixture {
        let host = try RemoteDeviceIdentity.generate(role: .host, displayName: "Offline checkpoint test")
        let memory = CheckpointMemory()
        memory.seed(try JSONEncoder().encode(host), account: WorldwidePairingStore.identityAccount)
        let store = WorldwidePairingStore(dataStore: memory)
        let snapshot = try store.phoneCatalog.loadOrMigrate(for: host)
        let pair = try pair(host: host)
        let owner = CheckpointOwner()
        let cursor = WorldwidePairingCatalogCheckpoint(store: store, identity: host, snapshot: snapshot,
            ownerIsValid: { owner.check() }, producer: producer)
        memory.resetCounts()
        return Fixture(host: host, memory: memory, store: store, owner: owner, cursor: cursor,
                       pending: pair.pending, proposed: pair.proposed)
    }

    private func pair(host: RemoteDeviceIdentity) throws -> (pending: RemotePairedDeviceRecord,
                                                             proposed: RemotePairedDeviceRecord) {
        let viewer = try RemoteDeviceIdentity.generate(role: .viewer)
        let invitation = try RemoteInvitationCode.generate()
        let h = try RemotePairingParticipant(identity: host, invitation: invitation)
        let v = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        let ha = try h.accept(v.hello)
        let va = try v.accept(h.hello)
        var record = try ha.makePendingRecord(peerConfirmation: va.makeConfirmation())
        let pending = record
        _ = try record.prepareProposal(using: host)
        return (pending, record)
    }

    private func changedRecord(_ record: RemotePairedDeviceRecord,
                               _ change: (inout [String: Any]) -> Void) throws -> RemotePairedDeviceRecord {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(RemotePairedDeviceRecord.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
    }

    private struct Fixture {
        let host: RemoteDeviceIdentity
        let memory: CheckpointMemory
        let store: WorldwidePairingStore
        let owner: CheckpointOwner
        let cursor: WorldwidePairingCatalogCheckpoint
        let pending: RemotePairedDeviceRecord
        let proposed: RemotePairedDeviceRecord
    }
}

private final class CheckpointOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = true
    private var count = 0
    var valid: Bool { get { lock.withLock { allowed } } set { lock.withLock { allowed = newValue } } }
    var calls: Int { lock.withLock { count } }
    func check() -> Bool { lock.withLock { count += 1; return allowed } }
}

private final class CheckpointMemory: WorldwidePairingDataStore, @unchecked Sendable {
    enum Failure: Hashable { case read, writeBefore, writeAfter }
    final class Sentinel: Error, @unchecked Sendable {}
    private let errors: [Failure: Sentinel] = [.read: Sentinel(), .writeBefore: Sentinel(), .writeAfter: Sentinel()]
    struct Counts: Equatable {
        var reads = 0
        var writes = 0
        var removes = 0
        static let zero = Self()
    }
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var attempts = Counts.zero
    private var failing: Failure?
    var counts: Counts { lock.withLock { attempts } }
    var failure: Failure? { get { lock.withLock { failing } } set { lock.withLock { failing = newValue } } }
    func sentinel(_ failure: Failure) -> Sentinel { errors[failure]! }
    func resetCounts() { lock.withLock { attempts = .zero } }
    func seed(_ bytes: Data, account: String) { lock.withLock { values[account] = bytes } }
    func changeCatalog(_ change: (inout [String: Any]) -> Void) throws {
        try lock.withLock {
            let key = WorldwidePairedPhoneCatalogStore.catalogAccount
            let bytes = try XCTUnwrap(values[key])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            // JSONSerialization may rewrite floating-point Date spelling. Decode
            // and encode the complete typed wire fixture like the concrete store,
            // so this test reaches full-snapshot policy, not malformed-byte refusal.
            let original = try JSONDecoder().decode(CheckpointCatalogBytes.self, from: bytes)
            XCTAssertEqual(try encoder.encode(original), bytes)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            change(&object)
            let edited = try JSONSerialization.data(withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes])
            let catalog = try JSONDecoder().decode(CheckpointCatalogBytes.self, from: edited)
            values[key] = try encoder.encode(catalog)
        }
    }
    func data(for account: String) throws -> Data? {
        try lock.withLock {
            attempts.reads += 1
            if failing == .read { throw sentinel(.read) }
            return values[account]
        }
    }
    func set(_ data: Data, for account: String) throws {
        try lock.withLock {
            attempts.writes += 1
            if failing == .writeBefore { throw sentinel(.writeBefore) }
            values[account] = data
            if failing == .writeAfter { throw sentinel(.writeAfter) }
        }
    }
    func removeData(for account: String) throws {
        lock.withLock { attempts.removes += 1; values.removeValue(forKey: account) }
    }
}

/// Test-only complete storage schema; no admission, mutation or validation logic.
private struct CheckpointCatalogBytes: Codable {
    let version: UInt8
    let catalogID: UUID
    let revision: UInt64
    let hostDeviceID: UUID
    let hostSigningPublicKey: Data
    let selectedPhoneID: UUID?
    let records: [RemotePairedDeviceRecord]
    let legacyImportReceipt: WorldwidePairedPhoneLegacyReceipt?
}
