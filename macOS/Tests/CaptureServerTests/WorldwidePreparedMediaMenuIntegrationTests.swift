import CaptureCore
import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

/// Runs the real coordinator and menu command bridge,
/// but replaces only network/capture effects with bounded, exact-owner probes.
@MainActor
final class WorldwidePreparedMediaMenuIntegrationTests: XCTestCase {
    func testTargetIsAbsentUntilStartupAndAuthenticatedResponseBothReturn() async throws {
        let start = PreparedMediaGate(), send = PreparedMediaGate()
        let media = PreparedMediaServiceProbe(startGate: start)
        let client = PreparedMediaAvailabilityProbe(responseGate: send)
        let h = try await harness(media: [media], clients: [client])
        let request = try h.nextReconnect()
        client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { media.startCount == 1 }
        XCTAssertNil(h.presentations.latest?.connectedMediaTarget)
        XCTAssertEqual(try h.savedHost().highestAcceptedReconnectSequence, request.request.sequence,
            "Authentic replay admission must be durable before startup/send finishes")
        start.open()
        try await waitUntil { client.responses.count == 1 }
        XCTAssertNil(h.presentations.latest?.connectedMediaTarget)
        let response = try XCTUnwrap(client.responses.first)
        XCTAssertEqual(try request.complete(with: response), try XCTUnwrap(h.media.credentials.first))
        send.open()
        let target = try await preparedTarget(h)
        XCTAssertEqual(target.phoneID, h.pair.viewerIdentity.deviceID)
        XCTAssertEqual(target.exchangeID, h.exchangeA.wireValue)
        XCTAssertEqual(media.startCount, 1)
        XCTAssertEqual(client.responseReturns, 1)
    }

    func testPeerLeftThenReadyBRetainsPreparedAAndActualMenuDispatch() async throws {
        let service = PreparedMediaServiceProbe()
        let h = try await harness(media: [service])
        let original = try await connectMedia(h)
        let model = startedMenu(h, target: original)
        h.client.emit(.peerLeft(role: .viewer, exchangeID: h.exchangeA))
        try await waitUntil { h.presentations.latest?.phase == .sessionPrepared }
        h.client.emit(.ready(role: .host, exchangeID: h.exchangeB))
        try await waitUntil { h.presentations.latest?.phase == .preparingSession }
        model.apply(try XCTUnwrap(h.presentations.latest))
        XCTAssertEqual(model.presentation.connectedMediaTarget, original)
        XCTAssertTrue(model.canMoveMedia)
        XCTAssertEqual(model.mediaHandoffControl.reason, .ready)
        let task = try XCTUnwrap(model.moveMedia(to: original))
        await task.value
        XCTAssertEqual(service.moveCount, 1)
        XCTAssertNotNil(model.mediaHandoffMessage)
        XCTAssertEqual(service.stopCount, 0)
        XCTAssertEqual(h.media.count, 1)
    }

    func testDirectReadyBRetainsPreparedAUntilAuthenticatedReconnectReplacesIt() async throws {
        let replacementStart = PreparedMediaGate()
        defer { replacementStart.open() }
        let first = PreparedMediaServiceProbe()
        let second = PreparedMediaServiceProbe(startGate: replacementStart)
        let h = try await harness(media: [first, second])
        let original = try await connectMedia(h), model = startedMenu(h, target: nil)
        model.apply(try XCTUnwrap(h.presentations.latest))
        let originalRevision = try XCTUnwrap(h.presentations.latest).revision
        let before = try h.savedHost(), responseCount = h.client.responses.count

        // Deliberately omit peerLeft and a transport failure. A fresh availability
        // exchange is not itself an authenticated request to replace media A.
        h.client.emit(.ready(role: .host, exchangeID: h.exchangeB))
        try await waitUntil { h.presentations.latest?.phase == .preparingSession &&
            (h.presentations.latest?.revision ?? 0) > originalRevision }
        model.apply(try XCTUnwrap(h.presentations.latest))
        XCTAssertEqual(model.presentation.connectedMediaTarget, original)
        XCTAssertTrue(model.mediaHandoffControl.visible)
        XCTAssertTrue(model.canMoveMedia)
        XCTAssertEqual(first.stopCount, 0, "Availability readiness must not retire an authenticated media owner")
        XCTAssertEqual(h.media.count, 1)
        XCTAssertEqual(h.client.responses.count, responseCount)
        XCTAssertEqual(try h.savedHost(), before, "Readiness alone cannot burn a signed reconnect sequence")
        let moveA = model.moveMedia(to: original)
        XCTAssertNotNil(moveA)
        await moveA?.value
        XCTAssertEqual(first.moveCount, 1)

        // The genuine signed request is the replacement boundary. Hold B's native
        // startup to observe revoked A admission before B can publish readiness.
        let request = try h.nextReconnect()
        h.client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { second.startCount == 1 }
        model.apply(try XCTUnwrap(h.presentations.latest))
        XCTAssertNil(model.presentation.connectedMediaTarget)
        XCTAssertTrue(model.mediaHandoffControl.visible)
        XCTAssertFalse(model.canMoveMedia)
        XCTAssertNil(model.moveMedia(to: original))
        await assertStale(h.coordinator, original)
        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(h.media.count, 2)
        XCTAssertEqual(h.client.responses.count, responseCount)
        XCTAssertEqual(try h.savedHost().highestAcceptedReconnectSequence, request.request.sequence)

        replacementStart.open()
        let replacement = try await preparedTarget(h)
        model.apply(try XCTUnwrap(h.presentations.latest))
        XCTAssertEqual(replacement.phoneID, original.phoneID)
        XCTAssertEqual(replacement.selectionEpoch, original.selectionEpoch)
        XCTAssertEqual(replacement.exchangeID, h.exchangeB.wireValue)
        XCTAssertNotEqual(replacement.mediaOwnerID, original.mediaOwnerID)
        XCTAssertTrue(model.canMoveMedia)
        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(second.startCount, 1)
        XCTAssertEqual(try request.complete(with: try XCTUnwrap(h.client.responses.last)),
            try XCTUnwrap(h.media.credentials.last))
        await assertStale(h.coordinator, original)
        let offer = try await h.coordinator.moveMediaToConnectedPhone(target: replacement)
        XCTAssertEqual(offer, second.offerID)
        XCTAssertEqual(first.moveCount, 1)
        XCTAssertEqual(second.moveCount, 1)
    }

    func testTransportRetryAndReadyBRetainAWithoutStartingOrStoppingMedia() async throws {
        let service = PreparedMediaServiceProbe()
        let retry = PreparedMediaGate()
        let first = PreparedMediaAvailabilityProbe(), second = PreparedMediaAvailabilityProbe()
        let h = try await harness(media: [service], clients: [first, second], retryGate: retry)
        let original = try await connectMedia(h)
        first.failStream()
        try await waitUntil { h.presentations.latest?.phase == .unavailable }
        XCTAssertEqual(h.presentations.latest?.connectedMediaTarget, original)
        let model = startedMenu(h, target: original)
        model.apply(try XCTUnwrap(h.presentations.latest))
        XCTAssertTrue(model.canMoveMedia)
        retry.open()
        try await waitUntil { second.isConnected }
        second.emit(.ready(role: .host, exchangeID: h.exchangeB))
        try await waitUntil { h.presentations.latest?.phase == .preparingSession }
        model.apply(try XCTUnwrap(h.presentations.latest))
        let task = try XCTUnwrap(model.moveMedia(to: original))
        await task.value
        XCTAssertEqual(service.moveCount, 1)
        XCTAssertEqual(service.stopCount, 0)
        XCTAssertEqual(service.startCount, 1)
        XCTAssertEqual(h.media.count, 1)
    }

    func testInFlightARequestSurvivesAvailabilityOnlyReadyB() async throws {
        let move = PreparedMediaGate(), service = PreparedMediaServiceProbe(moveGate: move)
        let h = try await harness(media: [service])
        let original = try await connectMedia(h), model = startedMenu(h, target: nil)
        model.apply(try XCTUnwrap(h.presentations.latest))
        let task = try XCTUnwrap(model.moveMedia(to: original))
        try await waitUntil { service.moveCount == 1 }
        h.client.emit(.peerLeft(role: .viewer, exchangeID: h.exchangeA))
        h.client.emit(.ready(role: .host, exchangeID: h.exchangeB))
        try await waitUntil { h.presentations.latest?.phase == .preparingSession }
        model.apply(try XCTUnwrap(h.presentations.latest))
        XCTAssertEqual(model.presentation.connectedMediaTarget, original)
        XCTAssertTrue(model.isRequestingMediaHandoff)
        XCTAssertFalse(task.isCancelled)
        move.open(); await task.value
        XCTAssertFalse(model.isRequestingMediaHandoff)
        XCTAssertNotNil(model.mediaHandoffMessage)
        XCTAssertEqual(service.stopCount, 0)
    }

    func testActualReconnectBRevokesAAdmissionBeforeAwaitedNativeStop() async throws {
        let stop = PreparedMediaGate(), completionQuery = PreparedMediaGate()
        let first = PreparedMediaServiceProbe(
            stopGate: stop, firstNativeQueryGate: completionQuery)
        let second = PreparedMediaServiceProbe()
        let h = try await harness(media: [first, second])
        let original = try await connectMedia(h), model = startedMenu(h, target: nil)
        model.apply(try XCTUnwrap(h.presentations.latest))
        h.client.emit(.peerLeft(role: .viewer, exchangeID: h.exchangeA))
        h.client.emit(.ready(role: .host, exchangeID: h.exchangeB))
        try await waitUntil { h.presentations.latest?.phase == .preparingSession }
        let request = try h.nextReconnect()
        h.client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { first.stopCount == 1 }
        try await waitUntil { first.nativeQueryCount == 1 }
        model.apply(try XCTUnwrap(h.presentations.latest))
        XCTAssertNil(model.presentation.connectedMediaTarget)
        XCTAssertFalse(model.canMoveMedia)
        XCTAssertNil(model.moveMedia(to: original))
        await assertStale(h.coordinator, original)
        XCTAssertEqual(first.moveCount, 0)
        XCTAssertEqual(h.media.count, 1, "Replacement must not bypass uncertain native stop")
        XCTAssertEqual(try h.savedHost().highestAcceptedReconnectSequence, request.request.sequence)
        completionQuery.open()
        stop.open()
        let replacement = try await preparedTarget(h)
        XCTAssertNotEqual(replacement, original)
        XCTAssertEqual(replacement.exchangeID, h.exchangeB.wireValue)
        XCTAssertNotEqual(replacement.mediaOwnerID, original.mediaOwnerID)
        XCTAssertEqual(second.startCount, 1)
        XCTAssertEqual(try request.complete(with: try XCTUnwrap(h.client.responses.last)),
            try XCTUnwrap(h.media.credentials.last))
        await assertStale(h.coordinator, original)
    }

    func testSameExchangeReplacementRequiresFreshOwnerNonce() async throws {
        let first = PreparedMediaServiceProbe(), second = PreparedMediaServiceProbe()
        let h = try await harness(media: [first, second])
        let original = try await connectMedia(h)
        let originalRevision = try XCTUnwrap(h.presentations.latest).revision
        let originalResponses = h.client.responseReturns
        let request = try h.nextReconnect()
        h.client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { h.client.responseReturns == originalResponses + 1 &&
            h.presentations.latest?.phase == .sessionPrepared &&
            (h.presentations.latest?.revision ?? 0) > originalRevision &&
            h.presentations.latest?.connectedMediaTarget != nil }
        let replacement = try XCTUnwrap(h.presentations.latest?.connectedMediaTarget)
        XCTAssertEqual(replacement.phoneID, original.phoneID)
        XCTAssertEqual(replacement.selectionEpoch, original.selectionEpoch)
        XCTAssertEqual(replacement.exchangeID, original.exchangeID)
        XCTAssertNotEqual(replacement.mediaOwnerID, original.mediaOwnerID)
        await assertStale(h.coordinator, original)
        let id = try await h.coordinator.moveMediaToConnectedPhone(target: replacement)
        XCTAssertEqual(id, second.offerID)
        XCTAssertEqual(first.moveCount, 0)
        XCTAssertEqual(second.moveCount, 1)
    }

    func testActualReplacementRejectsLateInFlightAResultAndMenuPublication() async throws {
        let move = PreparedMediaGate(), first = PreparedMediaServiceProbe(moveGate: move)
        let second = PreparedMediaServiceProbe()
        let h = try await harness(media: [first, second])
        let original = try await connectMedia(h), model = startedMenu(h, target: nil)
        model.apply(try XCTUnwrap(h.presentations.latest))
        let task = try XCTUnwrap(model.moveMedia(to: original))
        // Independent of the menu's cancellation: this task has no menu owner
        // and remains uncancelled across the actual replacement.
        let direct = Task { try await h.coordinator.moveMediaToConnectedPhone(target: original) }
        try await waitUntil { first.moveCount == 2 }
        let request = try h.nextReconnect()
        h.client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { h.presentations.latest?.connectedMediaTarget?.mediaOwnerID != original.mediaOwnerID &&
            h.presentations.latest?.connectedMediaTarget != nil }
        let replacement = try XCTUnwrap(h.presentations.latest?.connectedMediaTarget)
        model.apply(try XCTUnwrap(h.presentations.latest))
        XCTAssertFalse(model.isRequestingMediaHandoff)
        XCTAssertFalse(direct.isCancelled)
        move.open(); await task.value
        do { _ = try await direct.value; XCTFail("Uncancelled old request must fail the coordinator's post-await exact-owner guard") }
        catch WorldwidePhoneCatalogRuntimeError.staleSelection { }
        XCTAssertFalse(direct.isCancelled)
        XCTAssertEqual(model.presentation.connectedMediaTarget, replacement)
        XCTAssertNil(model.mediaHandoffMessage)
        XCTAssertEqual(first.moveCount, 2)
        XCTAssertEqual(second.moveCount, 0)
    }

    func testLateOldCompletionDoesNotRetirePreparedReplacement() async throws {
        let oldQuery = PreparedMediaGate()
        let first = PreparedMediaServiceProbe(firstNativeQueryGate: oldQuery)
        let second = PreparedMediaServiceProbe()
        let h = try await harness(media: [first, second])
        let original = try await connectMedia(h)
        // Start A's actual completion consumer before replacing A. Its native
        // stop read suspends inside mediaDidEnd while the actor admits B.
        first.complete()
        try await waitUntil { first.nativeQueryCount == 1 }
        XCTAssertNil(h.presentations.latest?.connectedMediaTarget)
        let request = try h.nextReconnect()
        h.client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { h.presentations.latest?.connectedMediaTarget?.mediaOwnerID != original.mediaOwnerID &&
            h.presentations.latest?.connectedMediaTarget != nil }
        let replacement = try XCTUnwrap(h.presentations.latest?.connectedMediaTarget)
        oldQuery.open()
        // This existing logger boundary is emitted by the coordinator's exact
        // post-await stale-owner branch. A query-return count alone precedes
        // the actor resumption and cannot satisfy this fence.
        try await waitUntil { h.logger.debugMessages.contains("A retired media completion was ignored") }
        XCTAssertEqual(first.nativeQueryReturns, 2)
        let offer = try await h.coordinator.moveMediaToConnectedPhone(target: replacement)
        XCTAssertEqual(offer, second.offerID)
        XCTAssertEqual(h.presentations.latest?.connectedMediaTarget, replacement)
        XCTAssertEqual(second.stopCount, 0)
    }

    func testAuthenticatedReplayDoesNotRevokePreparedAOrAttemptNewMedia() async throws {
        let service = PreparedMediaServiceProbe(), retry = PreparedMediaGate()
        let h = try await harness(media: [service], retryGate: retry)
        let request = try h.nextReconnect()
        h.client.emit(.signal(.reconnectRequest(request.request)))
        _ = try await preparedTarget(h)
        XCTAssertEqual(try request.complete(with: try XCTUnwrap(h.client.responses.last)),
            try XCTUnwrap(h.media.credentials.last))
        try await assertRejectedRequestPreservesOwner(h, service: service, request: request.request)
    }

    func testGenuineForeignPairRequestDoesNotRevokePreparedAOrAttemptNewMedia() async throws {
        let service = PreparedMediaServiceProbe(), retry = PreparedMediaGate()
        let h = try await harness(media: [service], retryGate: retry)
        _ = try await connectMedia(h)
        var foreign = try PreparedMediaPair.make()
        let request = try foreign.nextReconnect()
        XCTAssertNotEqual(request.request.pairID, try h.savedHost().pairID)
        try await assertRejectedRequestPreservesOwner(h, service: service, request: request.request)
    }

    func testHigherCurrentPairRequestWithForgedSignatureCannotRevokeOrConstructMedia() async throws {
        let service = PreparedMediaServiceProbe(), retry = PreparedMediaGate()
        let h = try await harness(media: [service], retryGate: retry)
        _ = try await connectMedia(h)
        let genuine = try h.nextReconnect().request
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(genuine))
            as? [String: Any])
        let signature = try XCTUnwrap(encoded["signature"] as? String)
        var bytes = try XCTUnwrap(Data(base64Encoded: signature))
        XCTAssertFalse(bytes.isEmpty)
        bytes[bytes.startIndex] ^= 1
        encoded["signature"] = bytes.base64EncodedString()
        let forged = try JSONDecoder().decode(RemoteReconnectRequest.self,
            from: JSONSerialization.data(withJSONObject: encoded, options: [.sortedKeys]))
        XCTAssertEqual(forged.sequence, genuine.sequence)
        XCTAssertEqual(forged.pairID, genuine.pairID)
        XCTAssertNotEqual(forged.signature, genuine.signature)
        try await assertRejectedRequestPreservesOwner(h, service: service, request: forged)
    }

    func testFailedStartupNeverMintsTargetOrSendsReconnectResponse() async throws {
        let first = PreparedMediaServiceProbe(failStart: true)
        let retry = PreparedMediaGate()
        let h = try await harness(media: [first], retryGate: retry)
        let request = try h.nextReconnect()
        h.client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { h.presentations.latest?.phase == .unavailable }
        XCTAssertNil(h.presentations.latest?.connectedMediaTarget)
        XCTAssertTrue(h.presentations.values.allSatisfy { $0.connectedMediaTarget == nil })
        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(h.client.responses.count, 0)
        XCTAssertEqual(try h.savedHost().highestAcceptedReconnectSequence, request.request.sequence)
    }

    func testFailedResponseNeverMintsPreparedTarget() async throws {
        let first = PreparedMediaServiceProbe(), retry = PreparedMediaGate()
        let client = PreparedMediaAvailabilityProbe(failResponse: true)
        let h = try await harness(media: [first], clients: [client], retryGate: retry)
        let request = try h.nextReconnect()
        client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { h.presentations.latest?.phase == .unavailable }
        XCTAssertEqual(first.startCount, 1)
        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(client.responseReturns, 0)
        XCTAssertTrue(h.presentations.values.allSatisfy { $0.connectedMediaTarget == nil })
        XCTAssertEqual(try h.savedHost().highestAcceptedReconnectSequence, request.request.sequence)
    }

    func testUnconfirmedNativeStopRetainsServiceButRevokesMenuAndCatalogAuthority() async throws {
        let first = PreparedMediaServiceProbe(unconfirmedStop: true)
        let second = PreparedMediaServiceProbe()
        let h = try await harness(media: [first, second])
        let original = try await connectMedia(h)
        let request = try h.nextReconnect()
        h.client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { h.presentations.latest?.phase == .stopped }
        XCTAssertNil(h.presentations.latest?.connectedMediaTarget)
        XCTAssertEqual(h.media.count, 1)
        await assertStale(h.coordinator, original)
        let quiet = await h.coordinator.stop()
        XCTAssertFalse(quiet)
        let snapshot = await h.coordinator.iPhoneMicrophoneForwardingSnapshot()
        XCTAssertEqual(snapshot, first.snapshot, "Native ownership remains observable until confirmed")
        do { _ = try await h.coordinator.phoneCatalogAction(); XCTFail("Retained native source is not a quiet catalog boundary") }
        catch { }
        first.setUnconfirmedStop(false)
        let confirmed = await h.coordinator.stop()
        XCTAssertTrue(confirmed)
    }

    func testOwnerLossDuringResponseSuspensionNeverGrantsPreparedCapability() async throws {
        let owner = PreparedMediaOwnerGate(), response = PreparedMediaGate()
        let service = PreparedMediaServiceProbe()
        let client = PreparedMediaAvailabilityProbe(responseGate: response)
        let h = try await harness(media: [service], clients: [client], owner: owner)
        let request = try h.nextReconnect()
        client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { client.responses.count == 1 }
        owner.revoke(); response.open()
        try await waitUntil { service.stopCount == 1 }
        XCTAssertTrue(h.presentations.values.allSatisfy { $0.connectedMediaTarget == nil })
        XCTAssertEqual(h.media.count, 1)
        XCTAssertEqual(service.moveCount, 0)
    }

    func testShutdownRevokesBeforeSuspendedNativeStopAndRejectsLateMove() async throws {
        let stop = PreparedMediaGate(), move = PreparedMediaGate()
        let service = PreparedMediaServiceProbe(stopGate: stop, moveGate: move)
        let h = try await harness(media: [service])
        let original = try await connectMedia(h)
        let request = Task { try await h.coordinator.moveMediaToConnectedPhone(target: original) }
        try await waitUntil { service.moveCount == 1 }
        let shutdown = Task { await h.coordinator.stop() }
        try await waitUntil { service.stopCount == 1 }
        XCTAssertEqual(h.presentations.latest?.phase, .stopped)
        XCTAssertNil(h.presentations.latest?.connectedMediaTarget)
        await assertStale(h.coordinator, original)
        move.open()
        do { _ = try await request.value; XCTFail("A stopped owner's late offer cannot count as current success") }
        catch WorldwidePhoneCatalogRuntimeError.staleSelection { }
        stop.open()
        let clean = await shutdown.value
        XCTAssertTrue(clean)
    }

    func testMicrophoneSnapshotForwarderUsesExactRetainedServiceAcrossAvailabilityLoss() async throws {
        let service = PreparedMediaServiceProbe()
        let h = try await harness(media: [service])
        let original = try await connectMedia(h)
        h.client.emit(.peerLeft(role: .viewer, exchangeID: h.exchangeA))
        h.client.emit(.ready(role: .host, exchangeID: h.exchangeB))
        try await waitUntil { h.presentations.latest?.phase == .preparingSession }
        let snapshot = await h.coordinator.iPhoneMicrophoneForwardingSnapshot()
        XCTAssertEqual(snapshot, service.snapshot)
        XCTAssertEqual(service.snapshotCount, 1)
        XCTAssertEqual(h.presentations.latest?.connectedMediaTarget, original)
        let clean = await h.coordinator.stop()
        XCTAssertTrue(clean)
        let inactive = await h.coordinator.iPhoneMicrophoneForwardingSnapshot()
        XCTAssertEqual(inactive, .inactive(policy: .enabled))
    }

    func testReconnectCounterWriteFailureBlocksEffectsAndRetryUsesDurablePredecessor() async throws {
        let retry = PreparedMediaGate(), first = PreparedMediaAvailabilityProbe(),
            second = PreparedMediaAvailabilityProbe(), service = PreparedMediaServiceProbe()
        let h = try await harness(media: [service], clients: [first, second], retryGate: retry)
        let before = try h.savedHost()
        let beforeBytes = try XCTUnwrap(h.pair.dataStore.catalogBytes)
        let beforeAttempts = h.pair.dataStore.catalogWriteAttempts
        let sentinel = PreparedMediaStorageSentinel()
        h.pair.dataStore.failNextCatalogWrite(writeThenThrow: false, error: sentinel)
        let request = try h.nextReconnect()
        first.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { h.presentations.latest?.phase == .unavailable }
        XCTAssertEqual(h.pair.dataStore.catalogWriteAttempts, beforeAttempts + 1)
        XCTAssertTrue(h.pair.dataStore.lastThrown === sentinel)
        XCTAssertEqual(h.pair.dataStore.catalogBytes, beforeBytes)
        XCTAssertEqual(try h.savedHost(), before)
        XCTAssertEqual(h.media.attemptCount, 0, "A failed counter save must precede even factory admission")
        XCTAssertEqual(service.startCount, 0)
        XCTAssertEqual(service.stopCount, 0)
        XCTAssertEqual(first.responses.count, 0)
        XCTAssertNil(h.presentations.latest?.connectedMediaTarget)

        // The stored predecessor did not burn this authenticated sequence. Its
        // exact request can safely be admitted by the real availability retry.
        retry.open()
        try await waitUntil { second.isConnected }
        second.emit(.ready(role: .host, exchangeID: h.exchangeA))
        try await waitUntil { h.presentations.latest?.phase == .preparingSession }
        second.emit(.signal(.reconnectRequest(request.request)))
        _ = try await preparedTarget(h)
        XCTAssertEqual(h.pair.dataStore.catalogWriteAttempts, beforeAttempts + 2)
        XCTAssertEqual(try h.savedHost().highestAcceptedReconnectSequence, request.request.sequence)
        XCTAssertNotEqual(h.pair.dataStore.catalogBytes, beforeBytes)
        XCTAssertEqual(first.responses.count, 0)
        XCTAssertEqual(second.responses.count, 1)
        XCTAssertEqual(h.media.attemptCount, 1)
        XCTAssertEqual(service.startCount, 1)
        XCTAssertEqual(try request.complete(with: try XCTUnwrap(second.responses.first)),
            try XCTUnwrap(h.media.credentials.first))
    }

    func testReconnectCounterWriteThenThrowRetainsActualDurableBurnWithoutEffects() async throws {
        let retry = PreparedMediaGate(), client = PreparedMediaAvailabilityProbe(),
            service = PreparedMediaServiceProbe()
        let h = try await harness(media: [service], clients: [client], retryGate: retry)
        let before = try h.savedHost()
        let beforeBytes = try XCTUnwrap(h.pair.dataStore.catalogBytes)
        let beforeAttempts = h.pair.dataStore.catalogWriteAttempts
        let sentinel = PreparedMediaStorageSentinel()
        h.pair.dataStore.failNextCatalogWrite(writeThenThrow: true, error: sentinel)
        let request = try h.nextReconnect()
        client.emit(.signal(.reconnectRequest(request.request)))
        try await waitUntil { h.presentations.latest?.phase == .unavailable }
        XCTAssertEqual(h.pair.dataStore.catalogWriteAttempts, beforeAttempts + 1)
        XCTAssertTrue(h.pair.dataStore.lastThrown === sentinel)
        XCTAssertNotEqual(h.pair.dataStore.catalogBytes, beforeBytes)
        var durable = try h.savedHost()
        XCTAssertEqual(durable.highestAcceptedReconnectSequence, request.request.sequence)
        XCTAssertEqual(durable.nextOutboundReconnectSequence, before.nextOutboundReconnectSequence)
        XCTAssertNotEqual(durable, before, "A backend write-then-throw is not a successful rollback")
        let burned = durable
        XCTAssertThrowsError(try durable.respond(to: request.request, using: h.pair.hostIdentity)) { error in
            XCTAssertEqual(error as? RemoteSessionCoreError, .staleReconnectSequence)
        }
        XCTAssertEqual(durable, burned, "Cold record admission must honor the actual burned bytes")
        XCTAssertEqual(h.media.attemptCount, 0)
        XCTAssertEqual(service.startCount, 0)
        XCTAssertEqual(service.stopCount, 0)
        XCTAssertEqual(client.responses.count, 0)
        XCTAssertNil(h.presentations.latest?.connectedMediaTarget)
        XCTAssertEqual(h.pair.dataStore.catalogBytes, try XCTUnwrap(h.pair.dataStore.lastAttemptedCatalogBytes))
        // Teardown, not this test, owns the paused availability retry. No second
        // response may be invented from the stale in-memory success publication.
    }

    // MARK: - Genuine pairing and real coordinator/menu composition

    private func harness(media services: [PreparedMediaServiceProbe],
                         clients: [PreparedMediaAvailabilityProbe] = [PreparedMediaAvailabilityProbe()],
                         retryGate: PreparedMediaGate? = nil,
                         owner: PreparedMediaOwnerGate = PreparedMediaOwnerGate()) async throws -> PreparedMediaHarness {
        let pair = try PreparedMediaPair.make(), transports = PreparedMediaTransportFactory(clients),
            media = PreparedMediaServiceFactory(services), presentations = PreparedMediaPresentations(),
            logger = PreparedMediaLogProbe()
        let coordinator = WorldwideHostCoordinator(endpoint: URL(string: "wss://example.invalid")!,
            forceRelay: false, screenDisplayID: nil, systemAudioDisplayID: nil,
            maximumWidth: 1_280, framesPerSecond: 30, maximumVideoBitrate: 4_000_000,
            remoteInputController: MacRemoteInputController(allowRemoteControl: false),
            store: pair.store, hostDisplayName: "Private fixture Mac",
            availabilityClientFactory: { _, _ in try transports.next() },
            availabilityRetrySleep: { _ in
                if let retryGate { await retryGate.wait() }
                try Task.checkCancellation()
            }, presentation: { presentations.append($0) },
            catalogMutationIsAuthorized: { true }, catalogOwnerIsValid: { owner.isValid },
            pairingClientFactory: { _, _ in throw PreparedMediaFixtureError.unexpectedEffect },
            mediaServiceFactory: { credential in try media.next(credential) },
            logger: logger)
        addTeardownBlock {
            retryGate?.open()
            clients.forEach { $0.releaseAll() }
            services.forEach { $0.releaseAll(); $0.setUnconfirmedStop(false) }
            _ = await coordinator.stop()
        }
        _ = try await coordinator.start(resetPairing: false)
        let h = try PreparedMediaHarness(pair: pair, coordinator: coordinator,
            media: media, client: XCTUnwrap(clients.first), presentations: presentations, logger: logger)
        try await waitUntil { h.client.isConnected }
        h.client.emit(.ready(role: .host, exchangeID: h.exchangeA))
        try await waitUntil { presentations.latest?.phase == .preparingSession }
        return h
    }

    private func connectMedia(_ h: PreparedMediaHarness) async throws -> BelugaConnectedPhoneMediaTarget {
        let request = try h.nextReconnect()
        h.client.emit(.signal(.reconnectRequest(request.request)))
        let target = try await preparedTarget(h)
        XCTAssertEqual(try request.complete(with: try XCTUnwrap(h.client.responses.last)),
            try XCTUnwrap(h.media.credentials.last))
        XCTAssertEqual(try h.savedHost().highestAcceptedReconnectSequence, request.request.sequence)
        return target
    }

    private func preparedTarget(_ h: PreparedMediaHarness) async throws -> BelugaConnectedPhoneMediaTarget {
        try await waitUntil { h.presentations.latest?.connectedMediaTarget != nil }
        return try XCTUnwrap(h.presentations.latest?.connectedMediaTarget)
    }

    private func startedMenu(_ h: PreparedMediaHarness, target: BelugaConnectedPhoneMediaTarget?) -> BelugaMenuBarModel {
        let model = BelugaMenuBarModel()
        model.start = { true }; model.begin()
        model.installPhoneCommands(.owned(by: h.coordinator))
        if target != nil, let latest = h.presentations.latest { model.apply(latest) }
        return model
    }

    private func assertStale(_ coordinator: WorldwideHostCoordinator,
                             _ target: BelugaConnectedPhoneMediaTarget,
                             file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await coordinator.moveMediaToConnectedPhone(target: target)
            XCTFail("A retired exact owner must not dispatch", file: file, line: line)
        } catch WorldwidePhoneCatalogRuntimeError.staleSelection { }
        catch { XCTFail("Unexpected stale-owner refusal: \(error)", file: file, line: line) }
    }

    private func assertRejectedRequestPreservesOwner(_ h: PreparedMediaHarness,
                                                     service: PreparedMediaServiceProbe,
                                                     request: RemoteReconnectRequest) async throws {
        let original = try XCTUnwrap(h.presentations.latest?.connectedMediaTarget)
        let record = try h.savedHost()
        let attempts = h.media.attemptCount, successful = h.media.count,
            responses = h.client.responses.count, stops = service.stopCount
        h.client.emit(.signal(.reconnectRequest(request)))
        try await waitUntil { h.presentations.latest?.phase == .unavailable }
        XCTAssertEqual(try h.savedHost(), record, "Authentication/replay rejection cannot burn accepted host state")
        XCTAssertEqual(h.presentations.latest?.connectedMediaTarget, original)
        XCTAssertEqual(h.media.attemptCount, attempts, "Even an exhausted rejected factory call is forbidden")
        XCTAssertEqual(h.media.count, successful)
        XCTAssertEqual(service.stopCount, stops)
        XCTAssertEqual(service.startCount, 1)
        XCTAssertEqual(h.client.responses.count, responses)
        XCTAssertEqual(service.moveCount, 0)
    }

    private func waitUntil(_ condition: @escaping @MainActor () async -> Bool) async throws {
        for _ in 0..<2_500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw PreparedMediaFixtureError.boundedObservationExpired
    }
}

@MainActor
private final class PreparedMediaHarness {
    var pair: PreparedMediaPair
    let coordinator: WorldwideHostCoordinator
    let media: PreparedMediaServiceFactory
    let client: PreparedMediaAvailabilityProbe
    let presentations: PreparedMediaPresentations
    let logger: PreparedMediaLogProbe
    let exchangeA: RemoteAvailabilityExchangeID
    let exchangeB: RemoteAvailabilityExchangeID

    init(pair: PreparedMediaPair, coordinator: WorldwideHostCoordinator,
         media: PreparedMediaServiceFactory, client: PreparedMediaAvailabilityProbe,
         presentations: PreparedMediaPresentations, logger: PreparedMediaLogProbe) throws {
        self.pair = pair; self.coordinator = coordinator; self.media = media
        self.client = client; self.presentations = presentations; self.logger = logger
        exchangeA = try .init(wireValue: "AAAAAAAAAAAAAAAAAAAAAA")
        exchangeB = try .init(wireValue: "AQEBAQEBAQEBAQEBAQEBAQ")
    }

    func nextReconnect() throws -> RemoteReconnectInitiator {
        try pair.nextReconnect()
    }

    func savedHost() throws -> RemotePairedDeviceRecord {
        try XCTUnwrap(pair.store.phoneCatalog.loadOrMigrate(for: pair.hostIdentity).selectedRecord)
    }
}

private struct PreparedMediaPair {
    let store: WorldwidePairingStore
    let dataStore: PreparedMediaMemoryStore
    let hostIdentity: RemoteDeviceIdentity
    let viewerIdentity: RemoteDeviceIdentity
    var viewerRecordData: Data

    mutating func nextReconnect() throws -> RemoteReconnectInitiator {
        // Reserve and persist before transmitting; no handcrafted positive request.
        var viewer = try JSONDecoder().decode(RemotePairedDeviceRecord.self, from: viewerRecordData)
        let request = try viewer.beginReconnect(using: viewerIdentity)
        viewerRecordData = try JSONEncoder().encode(viewer)
        let durable = try JSONDecoder().decode(RemotePairedDeviceRecord.self, from: viewerRecordData)
        precondition(durable == viewer)
        return request
    }

    static func make() throws -> Self {
        let dataStore = PreparedMediaMemoryStore()
        let store = WorldwidePairingStore(dataStore: dataStore)
        let host = try store.loadOrCreateHostIdentity(displayName: "Private fixture Mac")
        let viewer = try RemoteDeviceIdentity.generate(role: .viewer, displayName: "Private fixture phone")
        let invitation = try RemoteInvitationCode.generate()
        let hp = try RemotePairingParticipant(identity: host, invitation: invitation)
        let vp = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        let ha = try hp.accept(vp.hello), va = try vp.accept(hp.hello)
        var hr = try ha.makePendingRecord(peerConfirmation: va.makeConfirmation())
        var vr = try va.makePendingRecord(peerConfirmation: ha.makeConfirmation())
        let proposal = try hr.prepareProposal(using: host)
        let acknowledgement = try vr.prepareAcknowledgement(after: proposal, using: viewer)
        try hr.acceptAcknowledgement(acknowledgement)
        let completion = try hr.prepareCompletion(using: host)
        let activation = try vr.acceptCompletion(completion, using: viewer)
        try hr.acceptActivationAcknowledgement(activation)
        try store.savePairedViewer(hr, for: host)
        return .init(store: store, dataStore: dataStore, hostIdentity: host, viewerIdentity: viewer,
                     viewerRecordData: try JSONEncoder().encode(vr))
    }
}

private final class PreparedMediaGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        await withCheckedContinuation { continuation in
            let immediate = lock.withLock {
                if opened { return true }
                waiters.append(continuation); return false
            }
            if immediate { continuation.resume() }
        }
    }
    func open() {
        let pending = lock.withLock {
            opened = true; defer { waiters.removeAll() }; return waiters
        }
        pending.forEach { $0.resume() }
    }
}

private final class PreparedMediaServiceProbe: WorldwideHostMediaService, @unchecked Sendable {
    let completion: AsyncStream<Void>
    private let completionContinuation: AsyncStream<Void>.Continuation
    let offerID = UUID()
    let snapshot = WorldwideIPhoneMicrophoneForwardingHostSnapshot.inactive(policy: .suppressedForLANCoexistence)
    private let startGate: PreparedMediaGate?, stopGate: PreparedMediaGate?, moveGate: PreparedMediaGate?
    private let firstNativeQueryGate: PreparedMediaGate?
    private let failStart: Bool
    private let lock = NSLock()
    private var starts = 0, stops = 0, moves = 0, snapshots = 0, nativeQueries = 0, nativeReturns = 0
    private var unconfirmed: Bool
    init(startGate: PreparedMediaGate? = nil, stopGate: PreparedMediaGate? = nil,
         moveGate: PreparedMediaGate? = nil, firstNativeQueryGate: PreparedMediaGate? = nil,
         failStart: Bool = false, unconfirmedStop: Bool = false) {
        let stream = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        completion = stream.stream; completionContinuation = stream.continuation
        self.startGate = startGate; self.stopGate = stopGate; self.moveGate = moveGate
        self.firstNativeQueryGate = firstNativeQueryGate
        self.failStart = failStart; unconfirmed = unconfirmedStop
    }
    func startPairedSession() async throws {
        lock.withLock { starts += 1 }; await startGate?.wait()
        if failStart { throw PreparedMediaFixtureError.startFailed }
    }
    func stop() async { lock.withLock { stops += 1 }; await stopGate?.wait() }
    func hasUnconfirmedNativeCaptureStop() async -> Bool {
        let ordinal = lock.withLock { nativeQueries += 1; return nativeQueries }
        if ordinal == 1 { await firstNativeQueryGate?.wait() }
        return lock.withLock { nativeReturns += 1; return unconfirmed }
    }
    func moveMediaToConnectedPhone() async throws -> UUID {
        lock.withLock { moves += 1 }; await moveGate?.wait(); return offerID
    }
    func iPhoneMicrophoneForwardingSnapshot() async -> WorldwideIPhoneMicrophoneForwardingHostSnapshot {
        lock.withLock { snapshots += 1 }; return snapshot
    }
    func complete() { completionContinuation.yield(()); completionContinuation.finish() }
    func releaseAll() {
        startGate?.open(); stopGate?.open(); moveGate?.open(); firstNativeQueryGate?.open()
        completionContinuation.finish()
    }
    func setUnconfirmedStop(_ value: Bool) { lock.withLock { unconfirmed = value } }
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    var moveCount: Int { lock.withLock { moves } }
    var snapshotCount: Int { lock.withLock { snapshots } }
    var nativeQueryCount: Int { lock.withLock { nativeQueries } }
    var nativeQueryReturns: Int { lock.withLock { nativeReturns } }
}

private final class PreparedMediaAvailabilityProbe: WorldwideHostAvailabilityTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let responseGate: PreparedMediaGate?
    private let failResponse: Bool
    private var continuation: PairedAvailabilitySignalingClient.EventStream.Continuation?
    private var sentResponses: [RemoteReconnectResponse] = []
    private var returns = 0
    init(responseGate: PreparedMediaGate? = nil, failResponse: Bool = false) {
        self.responseGate = responseGate; self.failResponse = failResponse
    }
    func connect() async throws -> PairedAvailabilitySignalingClient.EventStream {
        let pair = PairedAvailabilitySignalingClient.EventStream.makeStream()
        lock.withLock { continuation = pair.continuation }
        return pair.stream
    }
    func send(_ payload: RemoteAvailabilityPayload) async throws {
        guard case .reconnectResponse(let response) = payload else {
            throw PreparedMediaFixtureError.unexpectedEffect
        }
        lock.withLock { sentResponses.append(response) }
        await responseGate?.wait()
        if failResponse { throw PreparedMediaFixtureError.responseFailed }
        lock.withLock { returns += 1 }
    }
    func close() async {
        let current = lock.withLock { let value = continuation; continuation = nil; return value }
        current?.finish()
    }
    func emit(_ event: PairedAvailabilitySignalingEvent) { lock.withLock { continuation }?.yield(event) }
    func failStream() { lock.withLock { continuation }?.finish(throwing: PreparedMediaFixtureError.transportFailed) }
    func releaseAll() { responseGate?.open() }
    var isConnected: Bool { lock.withLock { continuation != nil } }
    var responses: [RemoteReconnectResponse] { lock.withLock { sentResponses } }
    var responseReturns: Int { lock.withLock { returns } }
}

private final class PreparedMediaTransportFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [PreparedMediaAvailabilityProbe]
    init(_ clients: [PreparedMediaAvailabilityProbe]) { self.clients = clients }
    func next() throws -> any WorldwideHostAvailabilityTransport {
        try lock.withLock {
            guard !clients.isEmpty else { throw PreparedMediaFixtureError.unexpectedEffect }
            return clients.removeFirst()
        }
    }
}

private final class PreparedMediaServiceFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var services: [PreparedMediaServiceProbe]
    private var admittedCredentials: [RemoteRendezvousCredential] = []
    private var attempts = 0
    init(_ services: [PreparedMediaServiceProbe]) { self.services = services }
    func next(_ credential: RemoteRendezvousCredential) throws -> any WorldwideHostMediaService {
        try lock.withLock {
            attempts += 1
            guard !services.isEmpty else { throw PreparedMediaFixtureError.unexpectedEffect }
            admittedCredentials.append(credential); return services.removeFirst()
        }
    }
    var count: Int { lock.withLock { admittedCredentials.count } }
    var attemptCount: Int { lock.withLock { attempts } }
    var credentials: [RemoteRendezvousCredential] { lock.withLock { admittedCredentials } }
}

private final class PreparedMediaPresentations: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BelugaHostPresentation] = []
    func append(_ value: BelugaHostPresentation) { lock.withLock { storage.append(value) } }
    var latest: BelugaHostPresentation? { lock.withLock { storage.last } }
    var values: [BelugaHostPresentation] { lock.withLock { storage } }
}

private final class PreparedMediaOwnerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    var isValid: Bool { lock.withLock { valid } }
    func revoke() { lock.withLock { valid = false } }
}

private final class PreparedMediaMemoryStore: WorldwidePairingDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var failure: (writeThenThrow: Bool, error: PreparedMediaStorageSentinel)?
    private var attempts = 0
    private var attemptedBytes: Data?
    private var thrown: PreparedMediaStorageSentinel?
    var catalogWriteAttempts: Int { lock.withLock { attempts } }
    var lastAttemptedCatalogBytes: Data? { lock.withLock { attemptedBytes } }
    var lastThrown: PreparedMediaStorageSentinel? { lock.withLock { thrown } }
    var catalogBytes: Data? { lock.withLock { storage[WorldwidePairedPhoneCatalogStore.catalogAccount] } }
    func failNextCatalogWrite(writeThenThrow: Bool, error: PreparedMediaStorageSentinel) {
        lock.withLock { failure = (writeThenThrow, error) }
    }
    func data(for account: String) throws -> Data? { lock.withLock { storage[account] } }
    func set(_ value: Data, for account: String) throws {
        try lock.withLock {
            if account == WorldwidePairedPhoneCatalogStore.catalogAccount {
                attempts += 1
                attemptedBytes = value
                if let rejected = failure {
                    failure = nil
                    if rejected.writeThenThrow { storage[account] = value }
                    thrown = rejected.error
                    throw rejected.error
                }
            }
            storage[account] = value
        }
    }
    func removeData(for account: String) throws { _ = lock.withLock { storage.removeValue(forKey: account) } }
}

private final class PreparedMediaLogProbe: Logger, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    func info(_: String) { }
    func debug(_ message: String) { lock.withLock { messages.append(message) } }
    func error(_: String) { }
    var debugMessages: [String] { lock.withLock { messages } }
}

private enum PreparedMediaFixtureError: Error {
    case unexpectedEffect, boundedObservationExpired, startFailed, responseFailed, transportFailed
}

private final class PreparedMediaStorageSentinel: Error, @unchecked Sendable {}
