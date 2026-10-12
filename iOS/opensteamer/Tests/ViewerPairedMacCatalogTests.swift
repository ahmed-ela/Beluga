import Foundation
import RemoteSessionCore
import XCTest
@testable import opensteamer

@MainActor
final class ViewerPairedMacCatalogTests: XCTestCase {
    func testPendingMacRecoveryBindsInvitationToExactSelectedPairAcrossRelaunch() throws {
        let identity = try RemoteDeviceIdentity.generate(role: .viewer)
        let first = try makePairedMacRecord(localIdentity: identity, pairingState: .pending)
        let second = try makePairedMacRecord(localIdentity: identity, pairingState: .pending)
        let firstCode = try RemoteInvitationCode.generate().exportedCode
        let secondCode = try RemoteInvitationCode.generate().exportedCode
        let legacy = CatalogCompatibilityStub(identity: identity, record: nil)
        let bytes = CatalogDataStub()
        let store = ViewerPairedMacCatalogStore(compatibilityStore: legacy, dataStore: bytes)
        let state = ViewerPairingState(store: store)
        try state.savePairingRecord(first, bootstrapInvitation: firstCode)
        try state.savePairingRecord(second, bootstrapInvitation: secondCode)
        let rebuilt = ViewerPairingState(store: store)
        XCTAssertTrue(try rebuilt.recoveryInvitationMatchesSelectedMac(secondCode))
        XCTAssertFalse(try rebuilt.recoveryInvitationMatchesSelectedMac(firstCode))
        try rebuilt.selectMac(first.remoteDeviceID)
        XCTAssertFalse(try rebuilt.recoveryInvitationMatchesSelectedMac(secondCode),
                       "The global field for B must never bootstrap B while A is selected")
        XCTAssertTrue(try rebuilt.recoveryInvitationMatchesSelectedMac(firstCode))
        XCTAssertEqual(rebuilt.boundRecoveryMac, first)
        let retained = try XCTUnwrap(bytes.data)
        bytes.failWrite = true
        XCTAssertThrowsError(try rebuilt.savePairingRecord(second, bootstrapInvitation: firstCode))
        XCTAssertEqual(bytes.data, retained)
        XCTAssertEqual(rebuilt.pairingRecord, first)
    }

    func testMigratedPendingMacDoesNotGuessWhichUnboundInvitationBelongsToIt() throws {
        let identity = try RemoteDeviceIdentity.generate(role: .viewer)
        let pending = try makePairedMacRecord(localIdentity: identity, pairingState: .pending)
        let state = ViewerPairingState(store: ViewerPairedMacCatalogStore(
            compatibilityStore: CatalogCompatibilityStub(identity: identity, record: pending),
            dataStore: CatalogDataStub()
        ))
        XCTAssertFalse(try state.recoveryInvitationMatchesSelectedMac(
            RemoteInvitationCode.generate().exportedCode
        ))
        XCTAssertEqual(state.pairingRecord, pending, "Durable authenticated recovery remains available")
    }
    func testInterruptedSecondPairRetainsFirstActiveMacAndPendingSelectionAcrossRelaunch() throws {
        let identity = try RemoteDeviceIdentity.generate(role: .viewer)
        let first = try makePairedMacRecord(localIdentity: identity)
        let pending = try makePairedMacRecord(localIdentity: identity, pairingState: .pending)
        let legacy = CatalogCompatibilityStub(identity: identity, record: first)
        let bytes = CatalogDataStub()
        let state = ViewerPairingState(store: ViewerPairedMacCatalogStore(
            compatibilityStore: legacy, dataStore: bytes
        ))
        try state.selectMac(nil)
        try state.savePairingRecord(pending)
        XCTAssertEqual(state.savedMacs, [first, pending])
        XCTAssertNil(state.pairedMac, "A pending commit must not be media authorization")
        let rebuilt = ViewerPairingState(store: ViewerPairedMacCatalogStore(
            compatibilityStore: legacy, dataStore: bytes
        ))
        XCTAssertEqual(rebuilt.pairingRecord, pending)
        XCTAssertEqual(rebuilt.savedMacs.first, first)
        try rebuilt.selectMac(first.remoteDeviceID)
        XCTAssertEqual(rebuilt.pairedMac, first)
        XCTAssertEqual(rebuilt.savedMacs.last, pending)
    }

    func testSavedMacSwitchWaitsForBothRetirementsAndRejectsEveryStaleBoundary() async {
        var events: [String] = []
        var current = true
        let accepted = await BrowserView.admitSavedMacChange(
            isCurrent: { current }, waitForCancelledTransports: { events.append("transports") },
            admitRetiredMedia: { events.append("media"); return true }
        )
        XCTAssertTrue(accepted)
        XCTAssertEqual(events, ["transports", "media"])
        events = []
        let staleAfterTransports = await BrowserView.admitSavedMacChange(
            isCurrent: { current }, waitForCancelledTransports: {
                events.append("transports"); current = false
            }, admitRetiredMedia: { events.append("media"); return true }
        )
        XCTAssertFalse(staleAfterTransports)
        XCTAssertEqual(events, ["transports"])
        current = true
        let staleAfterMedia = await BrowserView.admitSavedMacChange(
            isCurrent: { current }, waitForCancelledTransports: {},
            admitRetiredMedia: { current = false; return true }
        )
        XCTAssertFalse(staleAfterMedia)
        current = true
        let unretiredMedia = await BrowserView.admitSavedMacChange(
            isCurrent: { current }, waitForCancelledTransports: {},
            admitRetiredMedia: { false }
        )
        XCTAssertFalse(unretiredMedia)
    }

    func testMigrationAndSecondMacPreserveIdentityAndBothIndependentPairsAcrossRelaunch() throws {
        let identity = try RemoteDeviceIdentity.generate(role: .viewer)
        let first = try makePairedMacRecord(localIdentity: identity)
        let legacy = CatalogCompatibilityStub(identity: identity, record: first)
        let bytes = CatalogDataStub()
        let store = ViewerPairedMacCatalogStore(compatibilityStore: legacy, dataStore: bytes)
        let state = ViewerPairingState(store: store)
        XCTAssertEqual(state.pairingRecord, first)
        let second = try makePairedMacRecord(localIdentity: identity)
        try state.saveAuthenticatedPairing(second)
        XCTAssertEqual(state.savedMacs, [first, second])
        XCTAssertEqual(state.pairingRecord, second)
        XCTAssertEqual(legacy.record, first, "Adding a Mac must not replace the legacy compatibility pair")
        XCTAssertEqual(legacy.deleteCount, 0)
        let rebuilt = ViewerPairingState(store: ViewerPairedMacCatalogStore(
            compatibilityStore: legacy, dataStore: bytes
        ))
        XCTAssertEqual(rebuilt.viewerIdentity, identity)
        XCTAssertEqual(rebuilt.savedMacs, [first, second])
        XCTAssertEqual(rebuilt.pairingRecord, second)
        try rebuilt.selectMac(first.remoteDeviceID)
        XCTAssertEqual(rebuilt.pairingRecord, first)
        XCTAssertEqual(rebuilt.savedMacs, [first, second])
    }

    func testAddingAndForgettingMacsNeverDropsOtherPairsOrRotatesIdentity() throws {
        let identity = try RemoteDeviceIdentity.generate(role: .viewer)
        let first = try makePairedMacRecord(localIdentity: identity)
        let second = try makePairedMacRecord(localIdentity: identity)
        let legacy = CatalogCompatibilityStub(identity: identity, record: first)
        let bytes = CatalogDataStub()
        let state = ViewerPairingState(store: ViewerPairedMacCatalogStore(
            compatibilityStore: legacy, dataStore: bytes
        ))
        try state.selectMac(nil)
        XCTAssertNil(state.pairingRecord)
        XCTAssertEqual(state.savedMacs, [first])
        try state.saveAuthenticatedPairing(second)
        try state.forgetMac(first.remoteDeviceID)
        XCTAssertEqual(state.savedMacs, [second])
        XCTAssertEqual(state.pairingRecord, second)
        XCTAssertEqual(legacy.deleteCount, 1)
        try state.forgetMac(second.remoteDeviceID)
        XCTAssertTrue(state.savedMacs.isEmpty)
        XCTAssertNil(state.pairingRecord)
        XCTAssertEqual(state.viewerIdentity, identity)
        let rebuilt = ViewerPairingState(store: ViewerPairedMacCatalogStore(
            compatibilityStore: legacy, dataStore: bytes
        ))
        XCTAssertTrue(rebuilt.savedMacs.isEmpty, "A forgotten legacy copy must not resurrect")
        XCTAssertEqual(rebuilt.viewerIdentity, identity)
    }

    func testCorruptionUnknownSelectionAndWriteFailureFailClosedWithoutDeletingPairs() throws {
        let identity = try RemoteDeviceIdentity.generate(role: .viewer)
        let first = try makePairedMacRecord(localIdentity: identity)
        let legacy = CatalogCompatibilityStub(identity: identity, record: first)
        let bytes = CatalogDataStub()
        let store = ViewerPairedMacCatalogStore(compatibilityStore: legacy, dataStore: bytes)
        let state = ViewerPairingState(store: store)
        let good = try XCTUnwrap(bytes.data)
        XCTAssertThrowsError(try state.selectMac(UUID()))
        XCTAssertEqual(bytes.data, good)
        bytes.failWrite = true
        XCTAssertThrowsError(try state.selectMac(nil))
        XCTAssertEqual(state.pairingRecord, first)
        XCTAssertEqual(bytes.data, good)
        bytes.failWrite = false
        for bad in [Data("invalid".utf8), Data(repeating: 0, count: 256 * 1024 + 1)] {
            bytes.data = bad
            let rebuilt = ViewerPairingState(store: store)
            XCTAssertNil(rebuilt.viewerIdentity)
            XCTAssertTrue(rebuilt.savedMacs.isEmpty)
            XCTAssertNotNil(rebuilt.storageError)
            XCTAssertEqual(bytes.data, bad)
        }
        XCTAssertEqual(legacy.deleteCount, 0)
        XCTAssertEqual(legacy.record, first)
    }

    func testCatalogRejectsIdentityMismatchAndMissingIdentityWithoutManufacturingReplacement() throws {
        let identity = try RemoteDeviceIdentity.generate(role: .viewer)
        let legacy = CatalogCompatibilityStub(identity: identity,
                                             record: try makePairedMacRecord(localIdentity: identity))
        let bytes = CatalogDataStub()
        let store = ViewerPairedMacCatalogStore(compatibilityStore: legacy, dataStore: bytes)
        _ = try store.loadPairedMac(for: identity)
        let good = try XCTUnwrap(bytes.data)
        XCTAssertThrowsError(try store.savePairedMac(
            makePairedMacRecord(), for: identity
        ))
        XCTAssertEqual(bytes.data, good)
        let creations = legacy.creationCalls
        legacy.identity = nil
        XCTAssertThrowsError(try store.loadOrCreateViewerIdentity())
        XCTAssertEqual(legacy.creationCalls, creations)
        XCTAssertEqual(bytes.data, good)
    }
}

private final class CatalogDataStub: ViewerPairedMacCatalogDataStoring {
    var data: Data?
    var failWrite = false
    func loadData() throws -> Data? { data }
    func saveData(_ data: Data) throws {
        if failWrite { throw ViewerPairedMacCatalogError.invalidCatalog }
        self.data = data
    }
}

private final class CatalogCompatibilityStub: ViewerPairingStoring, ViewerPairingIdentityReading {
    var identity: RemoteDeviceIdentity?
    var record: RemotePairedDeviceRecord?
    var creationCalls = 0
    var deleteCount = 0
    init(identity: RemoteDeviceIdentity, record: RemotePairedDeviceRecord?) {
        self.identity = identity
        self.record = record
    }
    func loadExistingViewerIdentity() throws -> RemoteDeviceIdentity? { identity }
    func loadOrCreateViewerIdentity() throws -> RemoteDeviceIdentity {
        creationCalls += 1
        return try XCTUnwrap(identity)
    }
    func loadPairedMac(for identity: RemoteDeviceIdentity) throws -> RemotePairedDeviceRecord? { record }
    func savePairedMac(_ record: RemotePairedDeviceRecord, for identity: RemoteDeviceIdentity) throws {
        self.record = record
    }
    func deletePairedMac() throws { record = nil; deleteCount += 1 }
}
