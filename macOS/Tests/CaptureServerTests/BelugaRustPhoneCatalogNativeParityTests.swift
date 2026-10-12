import CryptoKit
import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

// PRIVATE packet only. Authored from the original 434-line Swift owner and its 21 tests,
// plus the copied-value ABI. No new phone-catalog Rust source was read for expectations.
// The production call always runs before FrozenWorldwidePairedPhoneCatalogStore.
final class BelugaRustPhoneCatalogNativeParityTests: XCTestCase {
    private static let catalogID = UUID(uuidString: "00000000-0000-4000-8000-000000000087")!

    func testNativeGoldenAllCountsOccupiedSlotsAndSelectionsPreserveCompleteCustody() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host, displayName: "Native oracle host")
        let pairs = try (0..<9).map { _ in try makePair(host: host) }
        let allRecords = pairs.map(\.active)
        let receipt = try legacyReceipt(pairs[0].completion)
        for count in 0...8 {
            let records = Array(allRecords.prefix(count))
            let selections: [Int?] = [nil] + (0..<count).map(Optional.some)
            for selectedSlot in selections {
                let selected = selectedSlot.map { records[$0].remoteDeviceID }
                let initial = catalog(host: host, records: records, selected: selected, receipt: receipt)
                let add = Operation.add(allRecords[8])
                if count == 8 {
                    try compare(host: host, initial: initial, operation: add,
                                expected: .catalog(.capacityReached), expectedWrites: 0)
                } else {
                    var expected = initial
                    expected.records.append(allRecords[8])
                    expected.revision += 1
                    try compare(host: host, initial: initial, operation: add,
                                expected: .success(expected.snapshot), expectedWrites: 1)
                }

                var cleared = initial
                cleared.selectedPhoneID = nil
                if selected != nil { cleared.revision += 1 }
                try compare(host: host, initial: initial, operation: .select(nil),
                            expected: .success(cleared.snapshot), expectedWrites: selected == nil ? 0 : 1)

                for target in 0..<count {
                    var selectedCatalog = initial
                    selectedCatalog.selectedPhoneID = records[target].remoteDeviceID
                    if selected != records[target].remoteDeviceID { selectedCatalog.revision += 1 }
                    try compare(host: host, initial: initial, operation: .select(records[target].remoteDeviceID),
                                expected: .success(selectedCatalog.snapshot),
                                expectedWrites: selected == records[target].remoteDeviceID ? 0 : 1)

                    let advanced = try counters(records[target], outbound: UInt64(20 + target),
                                                accepted: UInt64(30 + target))
                    var updated = initial
                    updated.records[target] = advanced
                    updated.revision += 1
                    try compare(host: host, initial: initial, operation: .update(advanced),
                                expected: .success(updated.snapshot), expectedWrites: 1)
                    try compare(host: host, initial: initial, operation: .update(records[target]),
                                expected: .success(initial.snapshot), expectedWrites: 0)

                    var forgotten = initial
                    forgotten.records.remove(at: target)
                    if selected == records[target].remoteDeviceID { forgotten.selectedPhoneID = nil }
                    forgotten.revision += 1
                    try compare(host: host, initial: initial, operation: .forget(records[target].remoteDeviceID),
                                expected: .success(forgotten.snapshot), expectedWrites: 1)
                }
            }
        }
    }

    func testNativeMaximumRevisionAllowsExactNoopAndOperationErrorsBeatExhaustion() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let first = try makePair(host: host)
        let sibling = try makePair(host: host)
        let initial = catalog(host: host, records: [first.active, sibling.active],
                              selected: first.active.remoteDeviceID, revision: .max,
                              receipt: try legacyReceipt(first.completion))
        try compare(host: host, initial: initial, operation: .update(first.active),
                    expected: .success(initial.snapshot), expectedWrites: 0)
        try compare(host: host, initial: initial, operation: .select(first.active.remoteDeviceID),
                    expected: .success(initial.snapshot), expectedWrites: 0)
        var deselected = initial
        deselected.selectedPhoneID = nil
        try compare(host: host, initial: deselected, operation: .select(nil),
                    expected: .success(deselected.snapshot), expectedWrites: 0)
        let changed = try counters(first.active, outbound: 2, accepted: 1)
        for operation in [Operation.update(changed), .select(nil), .forget(first.active.remoteDeviceID)] {
            try compare(host: host, initial: initial, operation: operation,
                        expected: .catalog(.revisionExhausted), expectedWrites: 0)
        }
        try compare(host: host, initial: initial, operation: .add(first.active),
                    expected: .catalog(.duplicatePhone), expectedWrites: 0)
        let absent = try makePair(host: host).active
        for operation in [Operation.update(absent), .select(absent.remoteDeviceID), .forget(absent.remoteDeviceID)] {
            try compare(host: host, initial: initial, operation: operation,
                        expected: .catalog(.unknownPhone), expectedWrites: 0)
        }
    }

    func testNativeDualUInt64CountersAndRevisionSuccessorRemainExactAboveSignedRange() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let boundaries: [UInt64] = [1, 2, (1 << 63) - 1, 1 << 63, (1 << 63) + 1, .max - 1, .max]
        for outbound in boundaries {
            for accepted in [UInt64(0), UInt64(1), UInt64(1) << 63, UInt64.max] {
                let previous = try counters(pair.active, outbound: outbound, accepted: accepted)
                let initial = catalog(host: host, records: [previous], selected: previous.remoteDeviceID,
                                      revision: .max - 1)
                try compare(host: host, initial: initial, operation: .update(previous),
                            expected: .success(initial.snapshot), expectedWrites: 0)
                let nextOutbound = outbound == .max ? outbound : outbound + 1
                let nextAccepted = accepted == .max ? accepted : accepted + 1
                let candidate = try counters(previous, outbound: nextOutbound, accepted: nextAccepted)
                var expected = initial
                expected.records = [candidate]
                if candidate != previous { expected.revision += 1 }
                try compare(host: host, initial: initial, operation: .update(candidate),
                            expected: .success(expected.snapshot), expectedWrites: candidate == previous ? 0 : 1)
                if outbound > 1 {
                    let regressed = try counters(previous, outbound: outbound - 1, accepted: accepted)
                    try compare(host: host, initial: initial, operation: .update(regressed),
                                expected: .catalog(.staleRecord), expectedWrites: 0)
                }
                if accepted > 0 {
                    let regressed = try counters(previous, outbound: outbound, accepted: accepted - 1)
                    try compare(host: host, initial: initial, operation: .update(regressed),
                                expected: .catalog(.staleRecord), expectedWrites: 0)
                }
            }
        }
    }

    func testNativeActualCryptoRecoveryStatesMatchOriginalTransitionAndCachedCommitRules() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let states = [pair.pending, pair.proposal, pair.accepted, pair.completion, pair.active]
        // Original rank and exact resend retention, derived from the frozen original Swift.
        let accepted: [[Bool]] = [
            [true, true, true, true, true],
            [false, true, true, true, true],
            [false, false, true, true, true],
            [false, false, false, true, true],
            [false, false, false, false, true],
        ]
        for previous in states.indices {
            for candidate in states.indices {
                let initial = catalog(host: host, records: [states[previous]],
                                      selected: states[previous].remoteDeviceID)
                if accepted[previous][candidate] {
                    var expected = initial
                    expected.records = [states[candidate]]
                    if states[previous] != states[candidate] { expected.revision += 1 }
                    try compare(host: host, initial: initial, operation: .update(states[candidate]),
                                expected: .success(expected.snapshot),
                                expectedWrites: states[previous] == states[candidate] ? 0 : 1)
                } else {
                    try compare(host: host, initial: initial, operation: .update(states[candidate]),
                                expected: .catalog(.staleRecord), expectedWrites: 0)
                }
            }
        }
    }

    func testNativeDuplicateAxesBeatCapacityAndBindingBeatsBothCounterRegressions() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pairs = try (0..<9).map { _ in try makePair(host: host) }
        let first = pairs[0].active
        let initial = catalog(host: host, records: Array(pairs.prefix(8).map(\.active)), revision: .max)
        let duplicateChanges: [(inout [String: Any]) -> Void] = [
            { $0["remoteDeviceID"] = first.remoteDeviceID.uuidString },
            { $0["remoteSigningPublicKey"] = first.remoteSigningPublicKey.base64EncodedString() },
            { $0["pairID"] = first.pairID.uuidString },
            { $0["commitID"] = first.commitID.uuidString },
        ]
        for change in duplicateChanges {
            let duplicate = try changedRecord(pairs[8].active, change)
            try compare(host: host, initial: initial, operation: .add(duplicate),
                        expected: .catalog(.duplicatePhone), expectedWrites: 0)
        }
        let previous = try counters(first, outbound: .max, accepted: .max)
        let bound = catalog(host: host, records: [previous], revision: .max)
        let bindingChanges: [(inout [String: Any]) -> Void] = [
            { $0["pairID"] = UUID().uuidString },
            { $0["commitID"] = UUID().uuidString },
            { $0["pairRootKey"] = Data(repeating: 11, count: 32).base64EncodedString() },
            { $0["pairingTranscriptHash"] = Data(repeating: 12, count: 32).base64EncodedString() },
            { $0["createdAt"] = 1.0 },
        ]
        for change in bindingChanges {
            let candidate = try changedRecord(first, change)
            try compare(host: host, initial: bound, operation: .update(candidate),
                        expected: .catalog(.bindingConflict), expectedWrites: 0)
        }
    }

    func testNativeBadCurrentPrecedesStaleTokenAndStaleTokenSuppressesCandidateValidation() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let wrongHost = try RemoteDeviceIdentity.generate(role: .host)
        let invalidCandidate = try makePair(host: wrongHost).active
        let initial = catalog(host: host, records: [pair.active])
        let staleTokens = [
            WorldwidePairedPhoneCatalogToken(catalogID: initial.catalogID, revision: initial.revision + 1),
            WorldwidePairedPhoneCatalogToken(catalogID: UUID(), revision: initial.revision),
        ]
        for token in staleTokens {
            for operation in [Operation.add(invalidCandidate), .update(invalidCandidate),
                              .select(UUID()), .forget(UUID())] {
                try compare(host: host, initial: initial, operation: operation, token: token,
                            expected: .catalog(.staleCatalog), expectedWrites: 0)
            }
            for corrupt in [Data(), Data("{}".utf8), Data("not json".utf8)] {
                try compare(host: host, initial: initial, operation: .add(invalidCandidate), token: token,
                            catalogBytes: corrupt, expected: .catalog(.invalidCatalog), expectedWrites: 0)
            }
        }
        let wrongIdentityDuplicate = try changedRecord(invalidCandidate) {
            $0["remoteDeviceID"] = pair.active.remoteDeviceID.uuidString
        }
        for operation in [Operation.add(wrongIdentityDuplicate), .update(invalidCandidate)] {
            try compare(host: host, initial: initial, operation: operation,
                        expected: .catalog(.identityMismatch), expectedWrites: 0)
        }
    }

    func testNativeLoadedAdmissionOrderingReceiptLifetimeAndDecodeBridgePropagation() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let other = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let base = catalog(host: host, records: [pair.active], receipt: try legacyReceipt(pair.completion))
        var schemaAndHost = base
        schemaAndHost.version = 2
        schemaAndHost.hostDeviceID = other.deviceID
        try compare(host: host, initial: base, operation: .select(nil), catalogBytes: encode(schemaAndHost),
                    expected: .catalog(.invalidCatalog), expectedWrites: 0)
        var hostAndCapacity = base
        hostAndCapacity.hostDeviceID = other.deviceID
        hostAndCapacity.records = Array(repeating: pair.active, count: 9)
        try compare(host: host, initial: base, operation: .select(nil), catalogBytes: encode(hostAndCapacity),
                    expected: .catalog(.identityMismatch), expectedWrites: 0)
        var capacityAndDuplicate = base
        capacityAndDuplicate.records = Array(repeating: pair.active, count: 9)
        try compare(host: host, initial: base, operation: .select(nil), catalogBytes: encode(capacityAndDuplicate),
                    expected: .catalog(.capacityReached), expectedWrites: 0)
        var duplicateAndSelection = base
        duplicateAndSelection.records = [pair.active, pair.active]
        duplicateAndSelection.selectedPhoneID = other.deviceID
        try compare(host: host, initial: base, operation: .select(nil), catalogBytes: encode(duplicateAndSelection),
                    expected: .catalog(.duplicatePhone), expectedWrites: 0)
        // A genuine retained migration receipt need not name any remaining record.
        let empty = catalog(host: host, records: [], receipt: base.legacyImportReceipt)
        try compare(host: host, initial: empty, operation: .select(nil),
                    expected: .success(empty.snapshot), expectedWrites: 0)
        // Existing native decoder denial happens before token admission and keeps its error type.
        let stale = WorldwidePairedPhoneCatalogToken(catalogID: base.catalogID, revision: 0)
        try compare(host: host, initial: base, operation: .select(nil), token: stale,
                    decodeFault: 1, expected: .core(.invalidPairingCommitBridge), expectedWrites: 0)
    }

    func testNativeBeforeWriteFailureRetainsBytesAndOldTokenCanRetry() throws {
        try exerciseStorageFailure(.beforeWrite)
    }

    func testNativeWriteThenThrowLeavesDurableSuccessorAndOldTokenRetryIsStale() throws {
        try exerciseStorageFailure(.writeThenThrow)
    }

    func testNativeActualProducerStageTraceKeepsOriginalLazyCuts() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pairs = try (0..<3).map { _ in try makePair(host: host) }
        let initial = catalog(host: host, records: [pairs[0].active, pairs[1].active])
        let common: [UInt32] = [0, 1, 1, 2, 3]
        let final: [UInt32] = [0, 1, 1, 2]
        let advanced = try counters(pairs[0].active, outbound: 2, accepted: 1)
        let scenarios: [(Operation, [UInt32])] = [
            (.add(pairs[2].active), common + [4, 10, 11, 0, 1, 1, 1, 2]),
            (.update(advanced), common + [5, 6, 7, 10, 11] + final),
            (.update(pairs[0].active), common + [5, 6, 7, 10, 11]),
            (.select(pairs[0].active.remoteDeviceID), common + [8, 10, 11] + final),
            (.select(nil), common + [8, 10, 11]),
            (.forget(pairs[0].active.remoteDeviceID), common + [9, 10, 11, 0, 1, 2]),
            (.add(pairs[0].active), common + [4]),
            (.update(pairs[2].active), common + [5]),
            (.select(pairs[2].active.remoteDeviceID), common + [8]),
            (.forget(pairs[2].active.remoteDeviceID), common + [9]),
        ]
        for (operation, expectedStages) in scenarios {
            let memory = try memoryStore(host: host, catalogBytes: encode(initial))
            let trace = NativeCatalogTrace()
            let production = WorldwidePairedPhoneCatalogStore(dataStore: memory, resultMutation: { input, result in
                trace.record(input.stage)
                return result
            })
            _ = observe { try operation.apply(to: production, host: host, token: initial.snapshot.token) }
            XCTAssertEqual(trace.stages, expectedStages)
        }
        let memory = try memoryStore(host: host, catalogBytes: encode(initial))
        let trace = NativeCatalogTrace()
        let production = WorldwidePairedPhoneCatalogStore(dataStore: memory, resultMutation: { input, result in
            trace.record(input.stage)
            return result
        })
        let stale = WorldwidePairedPhoneCatalogToken(catalogID: initial.catalogID, revision: 0)
        XCTAssertEqual(observe { try production.addPairedPhone(pairs[2].active, for: host, expectedToken: stale) },
                       .catalog(.staleCatalog))
        XCTAssertEqual(trace.stages, common)
        XCTAssertEqual(memory.attemptedWrites.count, 0)
    }

    func testNativeEveryByteOfActualCopiedResultRejectsAtEveryUsedStageWithZeroWrites() throws {
        XCTAssertEqual(MemoryLayout<BelugaRustPhoneCatalog.Result>.size, 72)
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pairs = try (0..<3).map { _ in try makePair(host: host) }
        let initial = catalog(host: host, records: [pairs[0].active, pairs[1].active],
                              selected: pairs[1].active.remoteDeviceID,
                              receipt: try legacyReceipt(pairs[0].completion))
        let advanced = try counters(pairs[0].active, outbound: 2, accepted: 1)
        for stage in UInt32(0)...UInt32(11) {
            let operation: Operation
            switch stage {
            case 5...7: operation = .update(advanced)
            case 8: operation = .select(pairs[0].active.remoteDeviceID)
            case 9: operation = .forget(pairs[0].active.remoteDeviceID)
            default: operation = .add(pairs[2].active)
            }
            for byte in 0..<72 {
                let originalBytes = try encode(initial)
                let memory = try memoryStore(host: host, catalogBytes: originalBytes)
                let originalItems = memory.items
                let trace = NativeCatalogTrace()
                let production = WorldwidePairedPhoneCatalogStore(dataStore: memory, resultMutation: { input, actual in
                    trace.record(input.stage)
                    guard input.stage == stage, trace.takeFirstMutation() else { return actual }
                    var copied = actual
                    withUnsafeMutableBytes(of: &copied) { bytes in bytes[byte] ^= 1 }
                    return copied
                })
                XCTAssertEqual(observe { try operation.apply(to: production, host: host, token: initial.snapshot.token) },
                               .catalog(.invalidCatalog), "stage \(stage), output byte \(byte)")
                XCTAssertEqual(trace.mutationCount, 1)
                XCTAssertTrue(trace.stages.contains(stage))
                XCTAssertEqual(memory.attemptedWrites.count, 0)
                XCTAssertEqual(memory.writtenAccounts.count, 0)
                XCTAssertEqual(memory.items, originalItems)
                XCTAssertTrue(memory.removedAccounts.isEmpty)
                // The seam corrupts one copied result only. The same value instance can retry;
                // denial cannot introduce global poison or require reset by recreation.
                let referenceMemory = try memoryStore(host: host, catalogBytes: originalBytes)
                let reference = FrozenWorldwidePairedPhoneCatalogStore(dataStore: referenceMemory)
                let actualRetry = observe { try operation.apply(to: production, host: host, token: initial.snapshot.token) }
                let nativeExpected = observe { try operation.apply(to: reference, host: host, token: initial.snapshot.token) }
                XCTAssertEqual(actualRetry, nativeExpected)
                XCTAssertEqual(memory.items, referenceMemory.items)
                XCTAssertEqual(memory.writtenAccounts, [WorldwidePairedPhoneCatalogStore.catalogAccount])
                XCTAssertEqual(try WorldwidePairedPhoneCatalogStore(dataStore: memory).loadOrMigrate(for: host),
                               try reference.loadOrMigrate(for: host))
            }
        }
    }

    func testNativeMalformedInputTagsAndUnusedFieldsCannotBecomeCheckedBusinessResults() throws {
        let adapter = BelugaRustPhoneCatalog()
        var header = BelugaRustPhoneCatalog.input(0)
        header.flags = 3
        _ = try adapter.checked(header)
        let mutations: [(inout BelugaRustPhoneCatalog.Input) -> Void] = [
            { $0.abi_version = 0 }, { $0.abi_version = 2 }, { $0.stage = 12 },
            { $0.operation = 1 }, { $0.flags = 4 }, { $0.count = 10 },
            { $0.selected_slot = 1 }, { $0.target_slot = 1 }, { $0.duplicate_axes = 1 },
            { $0.previous_phase = 1 }, { $0.candidate_phase = 1 },
            { $0.previous_recovery = 1 }, { $0.candidate_recovery = 1 },
            { $0.reserved0 = 1 }, { $0.reserved1 = 1 }, { $0.revision = 1 },
            { $0.previous_outbound = 1 }, { $0.candidate_outbound = 1 },
            { $0.previous_accepted = 1 }, { $0.candidate_accepted = 1 }, { $0.reserved2 = 1 },
        ]
        for mutation in mutations {
            var copied = header
            mutation(&copied)
            XCTAssertThrowsError(try adapter.checked(copied)) { error in
                XCTAssertEqual(error as? WorldwidePairedPhoneCatalogError, .invalidCatalog)
            }
        }
    }

    func testNativeConcurrentSameTokenHasExactlyOneWinnerAcrossTwoInstances() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let first = try makePair(host: host).active
        let second = try makePair(host: host).active
        let initial = catalog(host: host, records: [], revision: (1 << 63) + 87)
        let memory = try memoryStore(host: host, catalogBytes: encode(initial))
        let outcomes = NativeCatalogConcurrentOutcomes()
        let group = DispatchGroup()
        for record in [first, second] {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let snapshot = try WorldwidePairedPhoneCatalogStore(dataStore: memory).addPairedPhone(
                        record, for: host, expectedToken: initial.snapshot.token
                    )
                    outcomes.append(.success(snapshot))
                } catch let error as WorldwidePairedPhoneCatalogError {
                    outcomes.append(.catalog(error))
                } catch { outcomes.append(.other(String(reflecting: type(of: error)))) }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        let successes = outcomes.values.compactMap { outcome -> WorldwidePairedPhoneCatalogSnapshot? in
            if case let .success(value) = outcome { return value }
            return nil
        }
        XCTAssertEqual(successes.count, 1)
        XCTAssertEqual(outcomes.values.filter { $0 == .catalog(.staleCatalog) }.count, 1)
        XCTAssertEqual(memory.attemptedWrites, [WorldwidePairedPhoneCatalogStore.catalogAccount])
        XCTAssertEqual(memory.writtenAccounts, [WorldwidePairedPhoneCatalogStore.catalogAccount])
        let decoded = try decodeCatalog(XCTUnwrap(memory.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount)))
        XCTAssertEqual(decoded.revision, initial.revision + 1)
        XCTAssertEqual(decoded.records.count, 1)
        XCTAssertTrue(decoded.records == [first] || decoded.records == [second])
        XCTAssertNil(decoded.selectedPhoneID)
        XCTAssertEqual(successes.first, decoded.snapshot)
        XCTAssertTrue(memory.removedAccounts.isEmpty)
    }

    // This mirror is the original full Codable custody, not a copied Rust model or slot oracle.
    private struct NativeCatalog: Codable, Equatable, Sendable {
        var version: UInt8
        var catalogID: UUID
        var revision: UInt64
        var hostDeviceID: UUID
        var hostSigningPublicKey: Data
        var selectedPhoneID: UUID?
        var records: [RemotePairedDeviceRecord]
        var legacyImportReceipt: WorldwidePairedPhoneLegacyReceipt?
        var snapshot: WorldwidePairedPhoneCatalogSnapshot {
            .init(token: .init(catalogID: catalogID, revision: revision), selectedPhoneID: selectedPhoneID,
                  records: records, legacyImportReceipt: legacyImportReceipt)
        }
    }

    private enum Operation: Sendable {
        case add(RemotePairedDeviceRecord), update(RemotePairedDeviceRecord), select(UUID?), forget(UUID)
        func apply(to store: WorldwidePairedPhoneCatalogStore, host: RemoteDeviceIdentity,
                   token: WorldwidePairedPhoneCatalogToken) throws -> WorldwidePairedPhoneCatalogSnapshot {
            switch self {
            case let .add(record): try store.addPairedPhone(record, for: host, expectedToken: token)
            case let .update(record): try store.updatePairedPhone(record, for: host, expectedToken: token)
            case let .select(id): try store.selectPhone(id, for: host, expectedToken: token)
            case let .forget(id): try store.forgetPhone(id, for: host, expectedToken: token)
            }
        }
        func apply(to store: FrozenWorldwidePairedPhoneCatalogStore, host: RemoteDeviceIdentity,
                   token: WorldwidePairedPhoneCatalogToken) throws -> WorldwidePairedPhoneCatalogSnapshot {
            switch self {
            case let .add(record): try store.addPairedPhone(record, for: host, expectedToken: token)
            case let .update(record): try store.updatePairedPhone(record, for: host, expectedToken: token)
            case let .select(id): try store.selectPhone(id, for: host, expectedToken: token)
            case let .forget(id): try store.forgetPhone(id, for: host, expectedToken: token)
            }
        }
    }

    private enum Outcome: Equatable, Sendable {
        case success(WorldwidePairedPhoneCatalogSnapshot)
        case catalog(WorldwidePairedPhoneCatalogError)
        case core(RemoteSessionCoreError)
        case storage(NativeCatalogStorageError)
        case other(String)
    }

    private func observe(_ body: () throws -> WorldwidePairedPhoneCatalogSnapshot) -> Outcome {
        do { return .success(try body()) }
        catch let error as WorldwidePairedPhoneCatalogError { return .catalog(error) }
        catch let error as RemoteSessionCoreError { return .core(error) }
        catch let error as NativeCatalogStorageError { return .storage(error) }
        catch { return .other(String(reflecting: type(of: error))) }
    }

    private func compare(host: RemoteDeviceIdentity, initial: NativeCatalog, operation: Operation,
                         token: WorldwidePairedPhoneCatalogToken? = nil, catalogBytes: Data? = nil,
                         decodeFault: UInt32? = nil, expected: Outcome, expectedWrites: Int,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        let initialBytes = try catalogBytes ?? encode(initial)
        let productionMemory = try memoryStore(host: host, catalogBytes: initialBytes)
        let referenceMemory = try memoryStore(host: host, catalogBytes: initialBytes)
        let production = WorldwidePairedPhoneCatalogStore(dataStore: productionMemory,
                                                          pairedRecordDecodeFault: decodeFault)
        let reference = FrozenWorldwidePairedPhoneCatalogStore(dataStore: referenceMemory,
                                                               pairedRecordDecodeFault: decodeFault)
        let expectedToken = token ?? initial.snapshot.token
        let actual = observe { try operation.apply(to: production, host: host, token: expectedToken) }
        let original = observe { try operation.apply(to: reference, host: host, token: expectedToken) }
        XCTAssertEqual(actual, original, file: file, line: line)
        XCTAssertEqual(original, expected, file: file, line: line)
        XCTAssertEqual(productionMemory.items, referenceMemory.items, file: file, line: line)
        XCTAssertEqual(productionMemory.attemptedWrites.count, expectedWrites, file: file, line: line)
        XCTAssertEqual(productionMemory.writtenAccounts, referenceMemory.writtenAccounts, file: file, line: line)
        XCTAssertEqual(productionMemory.writtenAccounts.count, expectedWrites, file: file, line: line)
        XCTAssertTrue(productionMemory.removedAccounts.isEmpty, file: file, line: line)
        if case let .success(snapshot) = actual {
            let bytes = try XCTUnwrap(productionMemory.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount),
                                      file: file, line: line)
            let decoded = try decodeCatalog(bytes)
            XCTAssertEqual(decoded.snapshot, snapshot, file: file, line: line)
            XCTAssertEqual(decoded.hostDeviceID, host.deviceID, file: file, line: line)
            XCTAssertEqual(decoded.hostSigningPublicKey, host.signingPublicKey, file: file, line: line)
            XCTAssertEqual(decoded.catalogID, initial.catalogID, file: file, line: line)
            XCTAssertEqual(decoded.legacyImportReceipt, initial.legacyImportReceipt, file: file, line: line)
            XCTAssertEqual(try encode(decoded), bytes, file: file, line: line)
        } else {
            XCTAssertEqual(try productionMemory.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount),
                           initialBytes, file: file, line: line)
        }
    }

    private func exerciseStorageFailure(_ failure: NativeCatalogStorageError) throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pairs = try (0..<3).map { _ in try makePair(host: host) }
        let initial = catalog(host: host, records: [pairs[0].completion, pairs[1].active],
                              selected: pairs[0].completion.remoteDeviceID,
                              receipt: try legacyReceipt(pairs[0].completion))
        let initialBytes = try encode(initial)
        let productionMemory = try memoryStore(host: host, catalogBytes: initialBytes)
        let referenceMemory = try memoryStore(host: host, catalogBytes: initialBytes)
        let unchangedIdentity = try productionMemory.data(for: WorldwidePairingStore.identityAccount)
        let unchangedLegacy = try productionMemory.data(for: WorldwidePairingStore.pairedViewerAccount)
        productionMemory.failure = failure
        referenceMemory.failure = failure
        let production = WorldwidePairedPhoneCatalogStore(dataStore: productionMemory)
        let reference = FrozenWorldwidePairedPhoneCatalogStore(dataStore: referenceMemory)
        let operation = Operation.add(pairs[2].active)
        let actual = observe { try operation.apply(to: production, host: host, token: initial.snapshot.token) }
        let original = observe { try operation.apply(to: reference, host: host, token: initial.snapshot.token) }
        XCTAssertEqual(actual, .storage(failure))
        XCTAssertEqual(actual, original)
        XCTAssertEqual(productionMemory.items, referenceMemory.items)
        XCTAssertEqual(productionMemory.attemptedWrites.count, 1)
        XCTAssertEqual(productionMemory.writtenAccounts.count, failure == .beforeWrite ? 0 : 1)
        if failure == .beforeWrite {
            XCTAssertEqual(try productionMemory.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount), initialBytes)
        } else {
            var expected = initial
            expected.records.append(pairs[2].active)
            expected.revision += 1
            XCTAssertEqual(try productionMemory.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount), try encode(expected))
        }
        productionMemory.failure = nil
        referenceMemory.failure = nil
        // Retry from a fresh instance with exactly the previous token: original storage semantics.
        let retry = WorldwidePairedPhoneCatalogStore(dataStore: productionMemory)
        let nativeRetry = FrozenWorldwidePairedPhoneCatalogStore(dataStore: referenceMemory)
        let retryActual = observe { try operation.apply(to: retry, host: host, token: initial.snapshot.token) }
        let retryExpected = observe { try operation.apply(to: nativeRetry, host: host, token: initial.snapshot.token) }
        XCTAssertEqual(retryActual, retryExpected)
        if failure == .writeThenThrow { XCTAssertEqual(retryActual, .catalog(.staleCatalog)) }
        else {
            var expected = initial
            expected.records.append(pairs[2].active)
            expected.revision += 1
            XCTAssertEqual(retryActual, .success(expected.snapshot))
        }
        XCTAssertEqual(productionMemory.items, referenceMemory.items)
        let coldActual = try retry.loadOrMigrate(for: host)
        let coldOriginal = try nativeRetry.loadOrMigrate(for: host)
        XCTAssertEqual(coldActual, coldOriginal)
        XCTAssertEqual(coldActual.records, [pairs[0].completion, pairs[1].active, pairs[2].active])
        XCTAssertEqual(coldActual.selectedPhoneID, initial.selectedPhoneID)
        XCTAssertEqual(coldActual.legacyImportReceipt, initial.legacyImportReceipt)
        XCTAssertEqual(coldActual.token.revision, initial.revision + 1)
        XCTAssertEqual(productionMemory.attemptedWrites, referenceMemory.attemptedWrites)
        XCTAssertEqual(productionMemory.attemptedWrites.count, failure == .beforeWrite ? 2 : 1)
        XCTAssertEqual(productionMemory.writtenAccounts.count, 1)
        XCTAssertEqual(try productionMemory.data(for: WorldwidePairingStore.identityAccount), unchangedIdentity)
        XCTAssertEqual(try productionMemory.data(for: WorldwidePairingStore.pairedViewerAccount), unchangedLegacy)
        XCTAssertTrue(productionMemory.removedAccounts.isEmpty)
    }

    private func catalog(host: RemoteDeviceIdentity, records: [RemotePairedDeviceRecord], selected: UUID? = nil,
                         revision: UInt64 = 87, receipt: WorldwidePairedPhoneLegacyReceipt? = nil) -> NativeCatalog {
        .init(version: 1, catalogID: Self.catalogID, revision: revision, hostDeviceID: host.deviceID,
              hostSigningPublicKey: host.signingPublicKey, selectedPhoneID: selected,
              records: records, legacyImportReceipt: receipt)
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func decodeCatalog(_ bytes: Data) throws -> NativeCatalog {
        // Use the actual original native paired-record decoder, including crypto verification.
        try belugaPairingRecordDecoder(faultSelection: nil).decode(NativeCatalog.self, from: bytes)
    }

    private func legacyReceipt(_ record: RemotePairedDeviceRecord) throws -> WorldwidePairedPhoneLegacyReceipt {
        .init(sourceAccount: WorldwidePairingStore.pairedViewerAccount,
              sourceSHA256: Data(SHA256.hash(data: try encode(record))), remoteDeviceID: record.remoteDeviceID,
              pairID: record.pairID, commitID: record.commitID)
    }

    private func memoryStore(host: RemoteDeviceIdentity, catalogBytes: Data) throws -> NativeCatalogMemoryDataStore {
        let memory = NativeCatalogMemoryDataStore()
        memory.seed(try encode(host), for: WorldwidePairingStore.identityAccount)
        memory.seed(catalogBytes, for: WorldwidePairedPhoneCatalogStore.catalogAccount)
        // Deliberately opaque retained legacy data; an existing catalog must never consult it.
        memory.seed(Data("retained opaque legacy bytes".utf8), for: WorldwidePairingStore.pairedViewerAccount)
        return memory
    }

    private func counters(_ record: RemotePairedDeviceRecord, outbound: UInt64,
                          accepted: UInt64) throws -> RemotePairedDeviceRecord {
        try changedRecord(record) {
            $0["nextOutboundReconnectSequence"] = outbound
            $0["highestAcceptedReconnectSequence"] = accepted
        }
    }

    private func changedRecord(_ record: RemotePairedDeviceRecord,
                               _ change: (inout [String: Any]) -> Void) throws -> RemotePairedDeviceRecord {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(record)) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(RemotePairedDeviceRecord.self, from: JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
        ))
    }

    private func makePair(host: RemoteDeviceIdentity) throws -> NativeCatalogPair {
        let viewer = try RemoteDeviceIdentity.generate(role: .viewer)
        let invitation = try RemoteInvitationCode.generate()
        let hostParticipant = try RemotePairingParticipant(identity: host, invitation: invitation)
        let viewerParticipant = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        let hostAgreement = try hostParticipant.accept(viewerParticipant.hello)
        let viewerAgreement = try viewerParticipant.accept(hostParticipant.hello)
        var hostRecord = try hostAgreement.makePendingRecord(peerConfirmation: viewerAgreement.makeConfirmation())
        var viewerRecord = try viewerAgreement.makePendingRecord(peerConfirmation: hostAgreement.makeConfirmation())
        let pending = hostRecord
        let proposalCommit = try hostRecord.prepareProposal(using: host)
        let proposal = hostRecord
        let acknowledgement = try viewerRecord.prepareAcknowledgement(after: proposalCommit, using: viewer)
        try hostRecord.acceptAcknowledgement(acknowledgement)
        let accepted = hostRecord
        let completionCommit = try hostRecord.prepareCompletion(using: host)
        try hostRecord.markCompletionSent(commitID: completionCommit.commitID)
        let completion = hostRecord
        let activation = try viewerRecord.acceptCompletion(completionCommit, using: viewer)
        try hostRecord.acceptActivationAcknowledgement(activation)
        return .init(pending: pending, proposal: proposal, accepted: accepted,
                     completion: completion, active: hostRecord)
    }

    private struct NativeCatalogPair {
        let pending: RemotePairedDeviceRecord
        let proposal: RemotePairedDeviceRecord
        let accepted: RemotePairedDeviceRecord
        let completion: RemotePairedDeviceRecord
        let active: RemotePairedDeviceRecord
    }

    private final class NativeCatalogConcurrentOutcomes: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [Outcome] = []
        var values: [Outcome] { lock.withLock { results } }
        func append(_ value: Outcome) { lock.withLock { results.append(value) } }
    }
}

private enum NativeCatalogStorageError: Error, Equatable, Sendable { case beforeWrite, writeThenThrow }

private final class NativeCatalogMemoryDataStore: WorldwidePairingDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var attempts: [String] = []
    private var writes: [String] = []
    private var removals: [String] = []
    private var writeFailure: NativeCatalogStorageError?
    var items: [String: Data] { lock.withLock { storage } }
    var attemptedWrites: [String] { lock.withLock { attempts } }
    var writtenAccounts: [String] { lock.withLock { writes } }
    var removedAccounts: [String] { lock.withLock { removals } }
    var failure: NativeCatalogStorageError? {
        get { lock.withLock { writeFailure } }
        set { lock.withLock { writeFailure = newValue } }
    }
    func seed(_ data: Data, for account: String) { lock.withLock { storage[account] = data } }
    func data(for account: String) throws -> Data? { lock.withLock { storage[account] } }
    func set(_ data: Data, for account: String) throws {
        try lock.withLock {
            attempts.append(account)
            if writeFailure == .beforeWrite { throw NativeCatalogStorageError.beforeWrite }
            storage[account] = data
            writes.append(account)
            if writeFailure == .writeThenThrow { throw NativeCatalogStorageError.writeThenThrow }
        }
    }
    func removeData(for account: String) throws {
        lock.withLock {
            storage.removeValue(forKey: account)
            removals.append(account)
        }
    }
}

private final class NativeCatalogTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var observed: [UInt32] = []
    private var mutations = 0
    var stages: [UInt32] { lock.withLock { observed } }
    var mutationCount: Int { lock.withLock { mutations } }
    func record(_ stage: UInt32) { lock.withLock { observed.append(stage) } }
    func takeFirstMutation() -> Bool {
        lock.withLock {
            guard mutations == 0 else { return false }
            mutations += 1
            return true
        }
    }
}
