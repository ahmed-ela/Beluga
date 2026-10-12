import CryptoKit
import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

/// Persistence-only tests: no production Keychain, device, host, network, or audio actions.
final class WorldwidePairedPhoneCatalogTests: XCTestCase {
    func testMigrationRetainsExactLegacyBytesAndInterruptedCommit() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host, displayName: "Saved Mac")
        let pair = try makePair(host: host)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let original = try encoder.encode(pair.completion)
        let dataStore = try memoryStore(host: host, legacyBytes: original)
        let identityBytes = try dataStore.data(for: WorldwidePairingStore.identityAccount)
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)

        let migrated = try store.loadOrMigrate(for: host)
        XCTAssertEqual(migrated.records, [pair.completion])
        XCTAssertEqual(migrated.selectedRecord, pair.completion)
        XCTAssertEqual(migrated.legacyImportReceipt?.sourceAccount,
                       WorldwidePairingStore.pairedViewerAccount)
        XCTAssertEqual(migrated.legacyImportReceipt?.sourceSHA256,
                       Data(SHA256.hash(data: original)))
        XCTAssertEqual(migrated.legacyImportReceipt?.remoteDeviceID, pair.active.remoteDeviceID)
        XCTAssertEqual(migrated.legacyImportReceipt?.pairID, pair.active.pairID)
        XCTAssertEqual(migrated.legacyImportReceipt?.commitID, pair.active.commitID)
        XCTAssertEqual(migrated.records.first?.pairingState, .acceptedReceived)
        XCTAssertEqual(migrated.records.first?.recoveryAction, pair.completion.recoveryAction)
        XCTAssertEqual(dataStore.writtenAccounts, [WorldwidePairedPhoneCatalogStore.catalogAccount])
        XCTAssertTrue(dataStore.removedAccounts.isEmpty)
        XCTAssertEqual(try dataStore.data(for: WorldwidePairingStore.pairedViewerAccount), original)
        XCTAssertEqual(try dataStore.data(for: WorldwidePairingStore.identityAccount), identityBytes)

        let recreated = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        XCTAssertEqual(try recreated.loadOrMigrate(for: host), migrated)
        XCTAssertEqual(dataStore.writtenAccounts.count, 1)
        XCTAssertFalse(migrated.description.contains("pairRootKey"))
    }

    func testMigrationRetainsBothReconnectCountersAndIgnoresLaterLegacyChanges() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let advanced = try changedRecord(pair.active) {
            $0["nextOutboundReconnectSequence"] = UInt64(14)
            $0["highestAcceptedReconnectSequence"] = UInt64(23)
        }
        let dataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(advanced))
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        let migrated = try store.loadOrMigrate(for: host)
        XCTAssertEqual(migrated.selectedRecord?.nextOutboundReconnectSequence, 14)
        XCTAssertEqual(migrated.selectedRecord?.highestAcceptedReconnectSequence, 23)

        dataStore.seed(Data("corrupt former record".utf8), for: WorldwidePairingStore.pairedViewerAccount)
        XCTAssertEqual(try store.loadOrMigrate(for: host), migrated)
        XCTAssertEqual(dataStore.writtenAccounts.count, 1)
    }

    func testEmptyCatalogIsAuthoritativeAndNeverImportsFutureLegacyRecord() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let dataStore = try memoryStore(host: host)
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        let empty = try store.loadOrMigrate(for: host)
        XCTAssertTrue(empty.records.isEmpty)
        XCTAssertNil(empty.selectedPhoneID)
        let pair = try makePair(host: host)
        dataStore.seed(try JSONEncoder().encode(pair.active), for: WorldwidePairingStore.pairedViewerAccount)
        XCTAssertEqual(try store.loadOrMigrate(for: host), empty)
        XCTAssertEqual(dataStore.writtenAccounts.count, 1)
    }

    func testIndependentAddExplicitSelectionForgetAndRestart() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let first = try makePair(host: host)
        let second = try makePair(host: host)
        let original = try JSONEncoder().encode(first.active)
        let dataStore = try memoryStore(host: host, legacyBytes: original)
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        var snapshot = try store.loadOrMigrate(for: host)
        snapshot = try store.addPairedPhone(second.active, for: host, expectedToken: snapshot.token)
        XCTAssertEqual(snapshot.selectedPhoneID, first.active.remoteDeviceID)
        XCTAssertEqual(snapshot.records, [first.active, second.active])
        snapshot = try store.selectPhone(second.active.remoteDeviceID, for: host,
                                        expectedToken: snapshot.token)
        XCTAssertEqual(snapshot.selectedRecord, second.active)
        XCTAssertEqual(try WorldwidePairedPhoneCatalogStore(dataStore: dataStore).loadOrMigrate(for: host),
                       snapshot)
        snapshot = try store.forgetPhone(second.active.remoteDeviceID, for: host,
                                        expectedToken: snapshot.token)
        XCTAssertEqual(snapshot.records, [first.active])
        XCTAssertNil(snapshot.selectedPhoneID)
        snapshot = try store.forgetPhone(first.active.remoteDeviceID, for: host,
                                        expectedToken: snapshot.token)
        XCTAssertTrue(snapshot.records.isEmpty)
        XCTAssertNotNil(snapshot.legacyImportReceipt)
        XCTAssertEqual(try dataStore.data(for: WorldwidePairingStore.pairedViewerAccount), original)
        XCTAssertEqual(try store.loadOrMigrate(for: host), snapshot)
        XCTAssertTrue(dataStore.removedAccounts.isEmpty)
    }

    func testFirstNewPhoneIsNotSelectedImplicitlyAndSelectionCanBeCleared() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let dataStore = try memoryStore(host: host)
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        var snapshot = try store.loadOrMigrate(for: host)
        let pair = try makePair(host: host)
        snapshot = try store.addPairedPhone(pair.active, for: host, expectedToken: snapshot.token)
        XCTAssertNil(snapshot.selectedPhoneID)
        snapshot = try store.selectPhone(pair.active.remoteDeviceID, for: host,
                                        expectedToken: snapshot.token)
        snapshot = try store.selectPhone(nil, for: host, expectedToken: snapshot.token)
        XCTAssertNil(snapshot.selectedPhoneID)
        XCTAssertEqual(snapshot.records, [pair.active])
        let writes = dataStore.writtenAccounts.count
        XCTAssertEqual(try store.selectPhone(nil, for: host, expectedToken: snapshot.token), snapshot)
        XCTAssertEqual(dataStore.writtenAccounts.count, writes)
    }

    func testStaleTokenRejectsEveryMutationWithoutChangingBytes() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let first = try makePair(host: host)
        let second = try makePair(host: host)
        let dataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(first.active))
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        let initial = try store.loadOrMigrate(for: host)
        let current = try store.addPairedPhone(second.active, for: host, expectedToken: initial.token)
        let bytes = try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount)
        expect(.staleCatalog) {
            _ = try store.addPairedPhone(second.active, for: host, expectedToken: initial.token)
        }
        expect(.staleCatalog) {
            _ = try store.updatePairedPhone(first.active, for: host, expectedToken: initial.token)
        }
        expect(.staleCatalog) {
            _ = try store.selectPhone(nil, for: host, expectedToken: initial.token)
        }
        expect(.staleCatalog) {
            _ = try store.forgetPhone(first.active.remoteDeviceID, for: host, expectedToken: initial.token)
        }
        expect(.staleCatalog) {
            _ = try store.selectPhone(nil, for: host, expectedToken: .init(catalogID: UUID(),
                                                                       revision: current.token.revision))
        }
        XCTAssertEqual(try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount), bytes)
        XCTAssertEqual(try store.loadOrMigrate(for: host), current)
    }

    func testUpdateCannotResurrectForgottenPhoneEvenWithFreshToken() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let dataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(pair.active))
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        let initial = try store.loadOrMigrate(for: host)
        let forgotten = try store.forgetPhone(pair.active.remoteDeviceID, for: host,
                                             expectedToken: initial.token)
        expect(.unknownPhone) {
            _ = try store.updatePairedPhone(pair.active, for: host, expectedToken: forgotten.token)
        }
        expect(.unknownPhone) {
            _ = try store.selectPhone(pair.active.remoteDeviceID, for: host,
                                      expectedToken: forgotten.token)
        }
        XCTAssertEqual(try store.loadOrMigrate(for: host), forgotten)
    }

    func testCounterAdvanceRetainsSiblingAndSelectionButRegressionFails() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let sibling = try makePair(host: host)
        let dataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(pair.active))
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        var snapshot = try store.loadOrMigrate(for: host)
        snapshot = try store.addPairedPhone(sibling.active, for: host, expectedToken: snapshot.token)
        var viewer = pair.viewerActive
        var advanced = pair.active
        let reconnect = try viewer.beginReconnect(using: pair.viewerIdentity)
        _ = try advanced.respond(to: reconnect.request, using: host)
        advanced = try changedRecord(advanced) { $0["nextOutboundReconnectSequence"] = UInt64(2) }
        snapshot = try store.updatePairedPhone(advanced, for: host, expectedToken: snapshot.token)
        XCTAssertEqual(snapshot.records, [advanced, sibling.active])
        XCTAssertEqual(snapshot.selectedPhoneID, pair.active.remoteDeviceID)
        expect(.staleRecord) {
            _ = try store.updatePairedPhone(pair.active, for: host, expectedToken: snapshot.token)
        }
        let oldOutbound = try changedRecord(advanced) { $0["nextOutboundReconnectSequence"] = UInt64(1) }
        expect(.staleRecord) {
            _ = try store.updatePairedPhone(oldOutbound, for: host, expectedToken: snapshot.token)
        }
        let oldAccepted = try changedRecord(advanced) { $0["highestAcceptedReconnectSequence"] = UInt64(0) }
        expect(.staleRecord) {
            _ = try store.updatePairedPhone(oldAccepted, for: host, expectedToken: snapshot.token)
        }
        XCTAssertEqual(try store.loadOrMigrate(for: host), snapshot)
    }

    func testPendingCommitProgressAndSamePhaseRecoveryCannotRegress() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let dataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(pair.pending))
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        var snapshot = try store.loadOrMigrate(for: host)
        for record in [pair.proposal, pair.accepted, pair.completion, pair.active] {
            snapshot = try store.updatePairedPhone(record, for: host, expectedToken: snapshot.token)
        }
        expect(.staleRecord) {
            _ = try store.updatePairedPhone(pair.completion, for: host, expectedToken: snapshot.token)
        }
        let stable = try store.updatePairedPhone(pair.active, for: host, expectedToken: snapshot.token)
        XCTAssertEqual(stable, snapshot)

        let secondDataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(pair.proposal))
        let secondStore = WorldwidePairedPhoneCatalogStore(dataStore: secondDataStore)
        let proposed = try secondStore.loadOrMigrate(for: host)
        expect(.staleRecord) {
            _ = try secondStore.updatePairedPhone(pair.pending, for: host, expectedToken: proposed.token)
        }
        let thirdDataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(pair.completion))
        let thirdStore = WorldwidePairedPhoneCatalogStore(dataStore: thirdDataStore)
        let completed = try thirdStore.loadOrMigrate(for: host)
        expect(.staleRecord) {
            _ = try thirdStore.updatePairedPhone(pair.accepted, for: host, expectedToken: completed.token)
        }
    }

    func testImmutableBindingCannotBeChangedByUpdate() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let dataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(pair.active))
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        let snapshot = try store.loadOrMigrate(for: host)
        let otherKey = try RemoteDeviceIdentity.generate(role: .viewer).signingPublicKey
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["pairID"] = UUID().uuidString },
            { $0["commitID"] = UUID().uuidString },
            { $0["remoteSigningPublicKey"] = otherKey.base64EncodedString() },
            { $0["pairRootKey"] = Data(repeating: 11, count: 32).base64EncodedString() },
            { $0["pairingTranscriptHash"] = Data(repeating: 12, count: 32).base64EncodedString() },
            { $0["createdAt"] = 1.0 },
        ]
        for change in changes {
            let changed = try changedRecord(pair.active, change)
            expect(.bindingConflict) {
                _ = try store.updatePairedPhone(changed, for: host, expectedToken: snapshot.token)
            }
        }
        XCTAssertEqual(try store.loadOrMigrate(for: host), snapshot)
    }

    func testDuplicateRemoteIDKeyPairAndCommitAreRejected() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let first = try makePair(host: host)
        let second = try makePair(host: host)
        let dataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(first.active))
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        let snapshot = try store.loadOrMigrate(for: host)
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["remoteDeviceID"] = first.active.remoteDeviceID.uuidString },
            { $0["remoteSigningPublicKey"] = first.active.remoteSigningPublicKey.base64EncodedString() },
            { $0["pairID"] = first.active.pairID.uuidString },
            { $0["commitID"] = first.active.commitID.uuidString },
        ]
        for change in changes {
            let duplicate = try changedRecord(second.active, change)
            expect(.duplicatePhone) {
                _ = try store.addPairedPhone(duplicate, for: host, expectedToken: snapshot.token)
            }
        }
        XCTAssertEqual(try store.loadOrMigrate(for: host), snapshot)
    }

    func testMaximumEightPhonesNeverEvictsAnExistingRecord() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let dataStore = try memoryStore(host: host)
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        var snapshot = try store.loadOrMigrate(for: host)
        var expected: [RemotePairedDeviceRecord] = []
        for _ in 0..<WorldwidePairedPhoneCatalogStore.maximumPhoneCount {
            let record = try makePair(host: host).active
            expected.append(record)
            snapshot = try store.addPairedPhone(record, for: host, expectedToken: snapshot.token)
        }
        let ninth = try makePair(host: host).active
        let bytes = try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount)
        expect(.capacityReached) {
            _ = try store.addPairedPhone(ninth, for: host, expectedToken: snapshot.token)
        }
        XCTAssertEqual(snapshot.records, expected)
        XCTAssertEqual(try store.loadOrMigrate(for: host), snapshot)
        XCTAssertEqual(try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount), bytes)
        XCTAssertEqual(WorldwidePairedPhoneCatalogStore.maximumCatalogBytes, 64 * 1_024)
    }

    func testCorruptCurrentCatalogNeverFallsBackOrOverwrites() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let legacy = try JSONEncoder().encode(makePair(host: host).active)
        for bytes in [Data(), Data("{}".utf8), Data("not json".utf8),
                      Data(repeating: 32, count: WorldwidePairedPhoneCatalogStore.maximumCatalogBytes + 1)] {
            let dataStore = try memoryStore(host: host, legacyBytes: legacy)
            dataStore.seed(bytes, for: WorldwidePairedPhoneCatalogStore.catalogAccount)
            let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
            XCTAssertThrowsError(try store.loadOrMigrate(for: host))
            XCTAssertTrue(dataStore.writtenAccounts.isEmpty)
            XCTAssertEqual(try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount), bytes)
            XCTAssertEqual(try dataStore.data(for: WorldwidePairingStore.pairedViewerAccount), legacy)
        }
    }

    func testCorruptWrapperSchemaSelectionAndIdentityFailClosed() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let dataStore = try memoryStore(host: host)
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        _ = try store.loadOrMigrate(for: host)
        let original = try XCTUnwrap(dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount))
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["version"] = 2 },
            { $0["catalogID"] = "00000000-0000-0000-0000-000000000000" },
            { $0["revision"] = 0 },
            { $0["selectedPhoneID"] = UUID().uuidString },
            { $0["hostDeviceID"] = UUID().uuidString },
            { $0["hostSigningPublicKey"] = Data(repeating: 1, count: 32).base64EncodedString() },
            { $0["unexpectedAuthorization"] = true },
        ]
        for change in changes {
            let corrupt = try changedJSON(original, change)
            dataStore.seed(corrupt, for: WorldwidePairedPhoneCatalogStore.catalogAccount)
            XCTAssertThrowsError(try store.loadOrMigrate(for: host))
            XCTAssertEqual(try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount), corrupt)
        }
        XCTAssertEqual(dataStore.writtenAccounts.count, 1)
    }

    func testPersistedDuplicateRecordsAndMalformedMigrationReceiptFailClosed() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let dataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(pair.active))
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        _ = try store.loadOrMigrate(for: host)
        let original = try XCTUnwrap(dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount))
        // Preserve the exact JSONEncoder number spelling (including paired dates).
        // JSONSerialization may reformat valid numbers and hit canonical rejection
        // before the duplicate-binding validation this test is intended to exercise.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let recordText = try XCTUnwrap(String(data: encoder.encode(pair.active), encoding: .utf8))
        let originalText = try XCTUnwrap(String(data: original, encoding: .utf8))
        let recordsField = "\"records\":[\(recordText)]"
        XCTAssertTrue(originalText.contains(recordsField))
        let duplicate = Data(originalText.replacingOccurrences(
            of: recordsField, with: "\"records\":[\(recordText),\(recordText)]"
        ).utf8)
        dataStore.seed(duplicate, for: WorldwidePairedPhoneCatalogStore.catalogAccount)
        expect(.duplicatePhone) { _ = try store.loadOrMigrate(for: host) }
        for field in ["sourceAccount", "sourceSHA256", "remoteDeviceID", "extra"] {
            let corrupt = try changedJSON(original) { object in
                var receipt = object["legacyImportReceipt"] as! [String: Any]
                switch field {
                case "sourceAccount": receipt[field] = "some-other-service"
                case "sourceSHA256": receipt[field] = Data([1]).base64EncodedString()
                case "remoteDeviceID": receipt[field] = "00000000-0000-0000-0000-000000000000"
                default: receipt[field] = true
                }
                object["legacyImportReceipt"] = receipt
            }
            dataStore.seed(corrupt, for: WorldwidePairedPhoneCatalogStore.catalogAccount)
            expect(.invalidCatalog) { _ = try store.loadOrMigrate(for: host) }
        }
        XCTAssertEqual(dataStore.writtenAccounts.count, 1)
    }

    func testNewCatalogRequiresExactCanonicalBytesIncludingNestedRecords() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let dataStore = try memoryStore(host: host, legacyBytes: JSONEncoder().encode(pair.active))
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        _ = try store.loadOrMigrate(for: host)
        let original = try XCTUnwrap(dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount))
        let text = try XCTUnwrap(String(data: original, encoding: .utf8))
        // The duplicate value is identical, so semantic JSON decoding alone would accept it.
        let duplicateRevision = Data(("{\"revision\":1," + String(text.dropFirst())).utf8)
        let explicitNull = try changedJSON(original) { $0["selectedPhoneID"] = NSNull() }
        let nestedUnknown = try changedJSON(original) { object in
            var records = object["records"] as! [[String: Any]]
            records[0]["ignoredAuthority"] = true
            object["records"] = records
        }
        var trailingWhitespace = original
        trailingWhitespace.append(10)
        for malformed in [duplicateRevision, explicitNull, nestedUnknown, trailingWhitespace] {
            dataStore.seed(malformed, for: WorldwidePairedPhoneCatalogStore.catalogAccount)
            expect(.invalidCatalog) { _ = try store.loadOrMigrate(for: host) }
            XCTAssertEqual(try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount), malformed)
        }
        XCTAssertEqual(dataStore.writtenAccounts.count, 1)
    }

    func testIdentityMissingChangedOrCorruptNeverCreatesCatalog() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let missing = CatalogMemoryDataStore()
        expect(.identityMismatch) {
            _ = try WorldwidePairedPhoneCatalogStore(dataStore: missing).loadOrMigrate(for: host)
        }
        XCTAssertTrue(missing.writtenAccounts.isEmpty)
        let otherHost = try RemoteDeviceIdentity.generate(role: .host)
        let changed = try memoryStore(host: otherHost)
        expect(.identityMismatch) {
            _ = try WorldwidePairedPhoneCatalogStore(dataStore: changed).loadOrMigrate(for: host)
        }
        let corrupt = try memoryStore(host: host)
        corrupt.seed(Data("{}".utf8), for: WorldwidePairingStore.identityAccount)
        expect(.invalidCatalog) {
            _ = try WorldwidePairedPhoneCatalogStore(dataStore: corrupt).loadOrMigrate(for: host)
        }
        XCTAssertTrue(changed.writtenAccounts.isEmpty)
        XCTAssertTrue(corrupt.writtenAccounts.isEmpty)
    }

    func testCorruptOrWrongHostLegacyRecordDoesNotCreateCatalog() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let otherHost = try RemoteDeviceIdentity.generate(role: .host)
        let wrong = try JSONEncoder().encode(makePair(host: otherHost).active)
        for legacy in [Data("{}".utf8), wrong] {
            let dataStore = try memoryStore(host: host, legacyBytes: legacy)
            let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
            XCTAssertThrowsError(try store.loadOrMigrate(for: host))
            XCTAssertNil(try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount))
            XCTAssertEqual(try dataStore.data(for: WorldwidePairingStore.pairedViewerAccount), legacy)
            XCTAssertTrue(dataStore.writtenAccounts.isEmpty)
        }
    }

    func testStorageFailureLeavesCatalogAndLegacyUnchanged() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let pair = try makePair(host: host)
        let legacy = try JSONEncoder().encode(pair.active)
        let dataStore = try memoryStore(host: host, legacyBytes: legacy)
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        let snapshot = try store.loadOrMigrate(for: host)
        let original = try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount)
        dataStore.rejectWrites = true
        XCTAssertThrowsError(try store.selectPhone(nil, for: host, expectedToken: snapshot.token))
        XCTAssertEqual(try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount), original)
        XCTAssertEqual(try dataStore.data(for: WorldwidePairingStore.pairedViewerAccount), legacy)
        XCTAssertEqual(try store.loadOrMigrate(for: host), snapshot)
    }

    func testRevisionExhaustionDoesNotMutateCatalog() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let dataStore = try memoryStore(host: host)
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        _ = try store.loadOrMigrate(for: host)
        let original = try XCTUnwrap(dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount))
        let exhausted = try changedJSON(original) { $0["revision"] = NSNumber(value: UInt64.max) }
        dataStore.seed(exhausted, for: WorldwidePairedPhoneCatalogStore.catalogAccount)
        let snapshot = try store.loadOrMigrate(for: host)
        let pair = try makePair(host: host)
        expect(.revisionExhausted) {
            _ = try store.addPairedPhone(pair.active, for: host, expectedToken: snapshot.token)
        }
        XCTAssertEqual(try dataStore.data(for: WorldwidePairedPhoneCatalogStore.catalogAccount), exhausted)
    }

    func testConcurrentSameRevisionMutationsHaveOneWinnerAcrossStoreInstances() throws {
        let host = try RemoteDeviceIdentity.generate(role: .host)
        let first = try makePair(host: host).active
        let second = try makePair(host: host).active
        let dataStore = try memoryStore(host: host)
        let store = WorldwidePairedPhoneCatalogStore(dataStore: dataStore)
        let snapshot = try store.loadOrMigrate(for: host)
        let group = DispatchGroup()
        let outcomes = CatalogMutationOutcomes()
        for record in [first, second] {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    _ = try WorldwidePairedPhoneCatalogStore(dataStore: dataStore).addPairedPhone(
                        record, for: host, expectedToken: snapshot.token
                    )
                    outcomes.append(nil)
                } catch { outcomes.append(error as? WorldwidePairedPhoneCatalogError ?? .invalidCatalog) }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(outcomes.values.filter { $0 == nil }.count, 1)
        XCTAssertEqual(outcomes.values.filter { $0 == .staleCatalog }.count, 1)
        let current = try store.loadOrMigrate(for: host)
        XCTAssertEqual(current.records.count, 1)
        XCTAssertEqual(current.token.revision, snapshot.token.revision + 1)
    }

    private func expect(
        _ expected: WorldwidePairedPhoneCatalogError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? WorldwidePairedPhoneCatalogError, expected, file: file, line: line)
        }
    }

    private func memoryStore(
        host: RemoteDeviceIdentity,
        legacyBytes: Data? = nil
    ) throws -> CatalogMemoryDataStore {
        let store = CatalogMemoryDataStore()
        store.seed(try JSONEncoder().encode(host), for: WorldwidePairingStore.identityAccount)
        if let legacyBytes { store.seed(legacyBytes, for: WorldwidePairingStore.pairedViewerAccount) }
        return store
    }

    private func changedRecord(
        _ record: RemotePairedDeviceRecord,
        _ change: (inout [String: Any]) -> Void
    ) throws -> RemotePairedDeviceRecord {
        try JSONDecoder().decode(RemotePairedDeviceRecord.self,
                                 from: changedJSON(JSONEncoder().encode(record), change))
    }

    private func changedJSON(
        _ bytes: Data,
        _ change: (inout [String: Any]) -> Void
    ) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func makePair(host: RemoteDeviceIdentity) throws -> CatalogPairFixture {
        let viewer = try RemoteDeviceIdentity.generate(role: .viewer)
        let invitation = try RemoteInvitationCode.generate()
        let hostParticipant = try RemotePairingParticipant(identity: host, invitation: invitation)
        let viewerParticipant = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        let hostAgreement = try hostParticipant.accept(viewerParticipant.hello)
        let viewerAgreement = try viewerParticipant.accept(hostParticipant.hello)
        var hostRecord = try hostAgreement.makePendingRecord(peerConfirmation: viewerAgreement.makeConfirmation())
        var viewerRecord = try viewerAgreement.makePendingRecord(peerConfirmation: hostAgreement.makeConfirmation())
        let pending = hostRecord
        let proposal = try hostRecord.prepareProposal(using: host)
        let proposed = hostRecord
        let acknowledgement = try viewerRecord.prepareAcknowledgement(after: proposal, using: viewer)
        try hostRecord.acceptAcknowledgement(acknowledgement)
        let accepted = hostRecord
        let completion = try hostRecord.prepareCompletion(using: host)
        try hostRecord.markCompletionSent(commitID: completion.commitID)
        let completing = hostRecord
        let activation = try viewerRecord.acceptCompletion(completion, using: viewer)
        try hostRecord.acceptActivationAcknowledgement(activation)
        return CatalogPairFixture(viewerIdentity: viewer, pending: pending, proposal: proposed,
                                  accepted: accepted, completion: completing,
                                  active: hostRecord, viewerActive: viewerRecord)
    }
}

private struct CatalogPairFixture {
    let viewerIdentity: RemoteDeviceIdentity
    let pending: RemotePairedDeviceRecord
    let proposal: RemotePairedDeviceRecord
    let accepted: RemotePairedDeviceRecord
    let completion: RemotePairedDeviceRecord
    let active: RemotePairedDeviceRecord
    let viewerActive: RemotePairedDeviceRecord
}

/// Only opaque in-memory bytes; replacement is atomic and can fail before modification.
private final class CatalogMemoryDataStore: WorldwidePairingDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var writes: [String] = []
    private var removals: [String] = []
    private var rejecting = false
    var writtenAccounts: [String] { lock.withLock { writes } }
    var removedAccounts: [String] { lock.withLock { removals } }
    var rejectWrites: Bool {
        get { lock.withLock { rejecting } }
        set { lock.withLock { rejecting = newValue } }
    }
    func seed(_ data: Data, for account: String) { lock.withLock { items[account] = data } }
    func data(for account: String) throws -> Data? { lock.withLock { items[account] } }
    func set(_ data: Data, for account: String) throws {
        try lock.withLock {
            if rejecting { throw CatalogMemoryError.rejected }
            items[account] = data
            writes.append(account)
        }
    }
    func removeData(for account: String) throws {
        lock.withLock {
            items.removeValue(forKey: account)
            removals.append(account)
        }
    }
}

private enum CatalogMemoryError: Error { case rejected }

private final class CatalogMutationOutcomes: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [WorldwidePairedPhoneCatalogError?] = []
    var values: [WorldwidePairedPhoneCatalogError?] { lock.withLock { outcomes } }
    func append(_ value: WorldwidePairedPhoneCatalogError?) { lock.withLock { outcomes.append(value) } }
}
