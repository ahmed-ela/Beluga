import Foundation
@testable import WebRTCTransport
import XCTest

private enum RemoteMediaFlowMilestone: Hashable, Sendable {
    case hostConnected
    case viewerConnected
    case hostDataChannelOpen
    case viewerDataChannelOpen
    case stateReceived
    case commandReceived
    case acknowledgementReceived
}

private actor RemoteMediaFlowRecorder {
    private var milestones: Set<RemoteMediaFlowMilestone> = []
    private(set) var states: [WebRTCRemoteMediaStateUpdate] = []
    private(set) var commands: [WebRTCRemoteMediaCommandRequest] = []
    private(set) var receivedStates: [WebRTCReceivedRemoteMediaState] = []
    private(set) var receivedCommands: [WebRTCReceivedRemoteMediaCommand] = []
    private(set) var refreshRequests: [WebRTCReceivedRemoteMediaStateRefreshRequest] = []
    private(set) var acknowledgements:
        [WebRTCRemoteMediaCommandAcknowledgement] = []
    private(set) var forwardingErrors: [String] = []
    private(set) var handoffOffers: [WebRTCReceivedMediaHandoffOffer] = []
    private(set) var handoffCommits: [WebRTCReceivedMediaHandoffCommit] = []
    private(set) var handoffCompletions: [WebRTCMediaHandoffCompletion] = []

    func record(_ offer: WebRTCReceivedMediaHandoffOffer) { handoffOffers.append(offer) }
    func record(_ commit: WebRTCReceivedMediaHandoffCommit) { handoffCommits.append(commit) }
    func record(_ completion: WebRTCMediaHandoffCompletion) { handoffCompletions.append(completion) }

    func mark(_ milestone: RemoteMediaFlowMilestone) -> Bool {
        milestones.insert(milestone).inserted
    }

    func record(_ state: WebRTCReceivedRemoteMediaState) -> Bool {
        receivedStates.append(state)
        states.append(state.update)
        return mark(.stateReceived)
    }

    func record(_ command: WebRTCReceivedRemoteMediaCommand) -> Bool {
        receivedCommands.append(command)
        commands.append(command.request)
        return mark(.commandReceived)
    }

    func record(_ refresh: WebRTCReceivedRemoteMediaStateRefreshRequest) {
        refreshRequests.append(refresh)
    }

    func record(
        _ acknowledgement: WebRTCRemoteMediaCommandAcknowledgement
    ) -> Bool {
        acknowledgements.append(acknowledgement)
        return mark(.acknowledgementReceived)
    }

    func recordForwardingError(_ error: any Error) {
        forwardingErrors.append(String(describing: error))
    }

    func snapshot() -> (
        states: [WebRTCRemoteMediaStateUpdate],
        commands: [WebRTCRemoteMediaCommandRequest],
        acknowledgements: [WebRTCRemoteMediaCommandAcknowledgement],
        forwardingErrors: [String],
        receivedStates: [WebRTCReceivedRemoteMediaState],
        receivedCommands: [WebRTCReceivedRemoteMediaCommand],
        refreshRequests: [WebRTCReceivedRemoteMediaStateRefreshRequest],
        handoffOffers: [WebRTCReceivedMediaHandoffOffer],
        handoffCommits: [WebRTCReceivedMediaHandoffCommit],
        handoffCompletions: [WebRTCMediaHandoffCompletion]
    ) {
        (states, commands, acknowledgements, forwardingErrors,
         receivedStates, receivedCommands, refreshRequests, handoffOffers, handoffCommits, handoffCompletions)
    }
}

private final class RemoteMediaFlowExpectations: @unchecked Sendable {
    let hostConnected = XCTestExpectation(description: "host connected")
    let viewerConnected = XCTestExpectation(description: "viewer connected")
    let hostDataChannelOpen = XCTestExpectation(
        description: "host control channel opened"
    )
    let viewerDataChannelOpen = XCTestExpectation(
        description: "viewer control channel opened"
    )
    let stateReceived = XCTestExpectation(
        description: "viewer received remote-media state"
    )
    let commandReceived = XCTestExpectation(
        description: "host received remote-media command"
    )
    let acknowledgementReceived = XCTestExpectation(
        description: "viewer received remote-media acknowledgement"
    )

    func fulfill(_ milestone: RemoteMediaFlowMilestone) {
        switch milestone {
        case .hostConnected: hostConnected.fulfill()
        case .viewerConnected: viewerConnected.fulfill()
        case .hostDataChannelOpen: hostDataChannelOpen.fulfill()
        case .viewerDataChannelOpen: viewerDataChannelOpen.fulfill()
        case .stateReceived: stateReceived.fulfill()
        case .commandReceived: commandReceived.fulfill()
        case .acknowledgementReceived: acknowledgementReceived.fulfill()
        }
    }
}

private final class RemoteMediaCallbackResults: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [WebRTCRemoteMediaCommandResult] = []
    func append(_ value: WebRTCRemoteMediaCommandResult) { lock.withLock { values.append(value) } }
    func read() -> [WebRTCRemoteMediaCommandResult] { lock.withLock { values } }
}

final class RemoteMediaControlsProtocolTests: XCTestCase {
    func testRealPeerHandoffCommitAndExactNativeResultAreSeparateFromOrdinaryPause() async throws {
        try await exerciseHandoffCommit(boundary: "success")
    }

    func testRealPeerHandoffCancellationRevokesUnexecutedNativeReceipt() async throws {
        try await exerciseHandoffCommit(boundary: "cancel")
    }

    func testRealPeerHandoffMissingHostReplyIsUnknownNotSuccess() async throws {
        try await exerciseHandoffCommit(boundary: "timeout")
    }

    func testMalformedOrderedControlRevokesAdmittedHandoffExecution() async throws {
        try await exerciseHandoffCommit(boundary: "malformed")
    }

    func testHandoffRevokedDuringValidationCannotReachSynchronousNativeSend() async throws {
        try await exerciseHandoffCommit(boundary: "revoked-during-validation")
    }

    private func exerciseHandoffCommit(boundary: String) async throws {
        let (host, viewer, recorder, _, hostTask, viewerTask) = try makeRemoteMediaFlow(supportsMediaHandoff: true)
        do {
            try await host.start()
            try await waitForRemoteMediaCondition {
                let h = await host.isTransportHealthyForMediaForTesting
                let v = await viewer.isTransportHealthyForMediaForTesting
                return h && v
            }
            let item = WebRTCRemoteMediaItem(contextID: "handoff-source", sourceName: "YouTube", title: "Test",
                playbackState: .playing, elapsedTime: 20, duration: 200, playbackRate: 1,
                capabilities: .init(canPlay: true, canPause: true, canSkipForward: false,
                    canSkipBackward: false, canSeekToPosition: true), artwork: .init(videoID: "dQw4w9WgXcQ"))
            try await host.sendRemoteMediaState(.init(revision: 1, item: item))
            let id = try await host.sendMediaHandoffOffer(contextID: item.contextID)
            try await waitForRemoteMediaCondition { await recorder.snapshot().handoffOffers.count == 1 }
            let initial = await recorder.snapshot(), offer = try XCTUnwrap(initial.handoffOffers.first)
            do {
                try await viewer.requestMediaHandoffCommit(offer, phonePositionSeconds: 20,
                    observedAtUptime: ProcessInfo.processInfo.systemUptime,
                    playbackAuthorization: WebRTCControlAuthorization(), playbackIsCurrent: { false })
                XCTFail("Revoked player evidence sent a commit")
            } catch let error as WebRTCTransportError { XCTAssertEqual(error, .controlAuthorizationRevoked) }
            if boundary == "revoked-during-validation" {
                let authorization = WebRTCControlAuthorization()
                do {
                    try await viewer.requestMediaHandoffCommit(offer, phonePositionSeconds: 20,
                        observedAtUptime: ProcessInfo.processInfo.systemUptime,
                        playbackAuthorization: authorization, playbackIsCurrent: {
                            authorization.revoke(); return true
                        })
                    XCTFail("A player retired after initial admission reached native send")
                } catch let error as WebRTCTransportError { XCTAssertEqual(error, .controlAuthorizationRevoked) }
                // Same ordered channel barrier proves that no earlier handoff commit arrived.
                try await viewer.requestRemoteMediaStateRefresh(id: UUID())
                try await waitForRemoteMediaCondition { await recorder.snapshot().refreshRequests.count == 1 }
                let final = await recorder.snapshot()
                XCTAssertTrue(final.handoffCommits.isEmpty)
                XCTAssertTrue(final.commands.isEmpty)
                hostTask.cancel(); viewerTask.cancel()
                let h = await host.close(reason: .normal), v = await viewer.close(reason: .normal)
                _ = await hostTask.value; _ = await viewerTask.value
                XCTAssertTrue(h); XCTAssertTrue(v)
                return
            }
            try await viewer.requestMediaHandoffCommit(offer, phonePositionSeconds: 20,
                observedAtUptime: ProcessInfo.processInfo.systemUptime,
                playbackAuthorization: WebRTCControlAuthorization(), playbackIsCurrent: { true })
            try await waitForRemoteMediaCondition { await recorder.snapshot().handoffCommits.count == 1 }
            let admitted = await recorder.snapshot(), commit = try XCTUnwrap(admitted.handoffCommits.first)
            XCTAssertEqual(commit.id, id); XCTAssertTrue(commit.isValid)
            XCTAssertTrue(admitted.commands.isEmpty)
            do {
                try await viewer.requestMediaHandoffCommit(offer, phonePositionSeconds: 20,
                    observedAtUptime: ProcessInfo.processInfo.systemUptime,
                    playbackAuthorization: WebRTCControlAuthorization(), playbackIsCurrent: { true })
                XCTFail("A duplicate receipt sent another commit")
            } catch let error as WebRTCTransportError { XCTAssertEqual(error, .controlAuthorizationRevoked) }
            if boundary == "success" {
                // Boundary double supplies a result: this proves transport, not real Mac pause.
                try await host.acknowledgeMediaHandoffCommit(commit, result: .macPaused)
                try await host.acknowledgeMediaHandoffCommit(commit, result: .macPaused)
            } else if boundary == "cancel" {
                await viewer.cancelMediaHandoffCommit(id: id)
            } else if boundary == "malformed" {
                await host.receiveMalformedControlMessageForTesting()
                XCTAssertFalse(commit.isValid)
                do {
                    try await host.acknowledgeMediaHandoffCommit(commit, result: .macPaused)
                    XCTFail("An invalidated execution fabricated a completion")
                } catch let error as WebRTCTransportError { XCTAssertEqual(error, .controlAuthorizationRevoked) }
            }
            try await waitForRemoteMediaCondition { await recorder.snapshot().handoffCompletions.count == 1 }
            try await viewer.requestRemoteMediaStateRefresh(id: UUID())
            try await waitForRemoteMediaCondition { await recorder.snapshot().refreshRequests.count == 1 }
            let final = await recorder.snapshot()
            XCTAssertEqual(final.handoffCompletions, [.init(id: id,
                result: boundary == "success" ? .macPaused : .outcomeUnknown)])
            XCTAssertEqual(final.handoffCommits.count, 1)
            XCTAssertFalse(commit.isValid)
            XCTAssertTrue(final.commands.isEmpty); XCTAssertTrue(final.forwardingErrors.isEmpty)
        } catch {
            hostTask.cancel(); viewerTask.cancel()
            _ = await host.close(reason: .protocolError); _ = await viewer.close(reason: .protocolError)
            _ = await hostTask.value; _ = await viewerTask.value
            throw error
        }
        hostTask.cancel(); viewerTask.cancel()
        let h = await host.close(reason: .normal), v = await viewer.close(reason: .normal)
        _ = await hostTask.value; _ = await viewerTask.value
        XCTAssertTrue(h); XCTAssertTrue(v)
    }

    func testRealPeerHandoffOfferIsOneUseNonAuthorizingAndExactSourceBound() async throws {
        try await exerciseHandoffReceipt(malformedControlBeforeConsumption: false)
    }

    func testMalformedOrderedControlRevokesPendingHandoffReceipt() async throws {
        try await exerciseHandoffReceipt(malformedControlBeforeConsumption: true)
    }

    private func exerciseHandoffReceipt(malformedControlBeforeConsumption: Bool) async throws {
        let (host, viewer, recorder, _, hostTask, viewerTask) = try makeRemoteMediaFlow(supportsMediaHandoff: true)
        do {
            try await host.start()
            try await waitForRemoteMediaCondition {
                let hostReady = await host.isTransportHealthyForMediaForTesting
                let viewerReady = await viewer.isTransportHealthyForMediaForTesting
                return hostReady && viewerReady
            }
            let negotiated = await viewer.mediaHandoffIsNegotiated()
            XCTAssertTrue(negotiated)
            let item = WebRTCRemoteMediaItem(contextID: "same-video", sourceName: "YouTube", title: "Test",
                playbackState: .playing, elapsedTime: 20, duration: 200, playbackRate: 1,
                capabilities: .init(canPlay: true, canPause: true, canSkipForward: false,
                    canSkipBackward: false, canSeekToPosition: true), artwork: .init(videoID: "dQw4w9WgXcQ"))
            try await host.sendRemoteMediaState(.init(revision: 1, item: item))
            let id = try await host.sendMediaHandoffOffer(contextID: item.contextID)
            try await waitForRemoteMediaCondition { await recorder.snapshot().handoffOffers.count == 1 }
            let snapshot = await recorder.snapshot()
            let offer = try XCTUnwrap(snapshot.handoffOffers.first)
            XCTAssertEqual(offer.id, id)
            if malformedControlBeforeConsumption {
                // Exercises the actual receiver parser, not a test-only offer-state clear.
                await viewer.receiveMalformedControlMessageForTesting()
            } else {
                let received = try await viewer.consumeMediaHandoffOffer(offer)
                XCTAssertEqual(received.update.item, item)
            }
            do {
                _ = try await viewer.consumeMediaHandoffOffer(offer)
                XCTFail("A consumed or protocol-invalidated receipt cannot authorize consumption")
            } catch let error as WebRTCTransportError { XCTAssertEqual(error, .controlAuthorizationRevoked) }
            // Ordered refresh is a delivery barrier; offer consumption sends no Pause command.
            try await viewer.requestRemoteMediaStateRefresh(id: UUID())
            try await waitForRemoteMediaCondition { await recorder.snapshot().refreshRequests.count == 1 }
            let final = await recorder.snapshot()
            XCTAssertTrue(final.commands.isEmpty)
            XCTAssertTrue(final.forwardingErrors.isEmpty)
        } catch {
            hostTask.cancel(); viewerTask.cancel()
            _ = await host.close(reason: .protocolError); _ = await viewer.close(reason: .protocolError)
            _ = await hostTask.value; _ = await viewerTask.value
            throw error
        }
        hostTask.cancel(); viewerTask.cancel()
        let hostClosed = await host.close(reason: .normal), viewerClosed = await viewer.close(reason: .normal)
        _ = await hostTask.value; _ = await viewerTask.value
        XCTAssertTrue(hostClosed); XCTAssertTrue(viewerClosed)
    }

    func testPipelineStagePreservesOrderedPlaybackBitsWithoutSourceMetadata() throws {
        let playing = WebRTCRemoteMediaItem(contextID: "private-first-source", sourceName: "private-app",
            title: "private-title", playbackState: .playing, elapsedTime: 10, duration: 50,
            playbackRate: 1, capabilities: .init(canPlay: false, canPause: true,
                canSkipForward: false, canSkipBackward: false))
        let paused = WebRTCRemoteMediaItem(contextID: "private-second-source", sourceName: "private-app",
            title: "private-title", playbackState: .paused, elapsedTime: 10, duration: 50,
            playbackRate: 0, capabilities: .init(canPlay: true, canPause: false,
                canSkipForward: false, canSkipBackward: false))
        let first = try XCTUnwrap(WebRTCRemoteMediaPipelineDiagnostics.Stage(update:
            .init(revision: 17, item: playing, additionalItems: [paused])))
        XCTAssertEqual(first.revision, 17)
        XCTAssertEqual(first.itemCount, 2)
        XCTAssertEqual(first.playingMask, 1)
        let reversed = try XCTUnwrap(WebRTCRemoteMediaPipelineDiagnostics.Stage(update:
            .init(revision: 18, item: paused, additionalItems: [playing])))
        XCTAssertEqual(reversed.playingMask, 2)
        let bytes = try JSONEncoder().encode(first)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("private"))
        XCTAssertEqual(WebRTCRemoteMediaPipelineDiagnostics.Stage(update: .init(revision: 19, item: nil))?.itemCount, 0)
        XCTAssertNil(WebRTCRemoteMediaPipelineDiagnostics.Stage(update: .init(revision: 0, item: playing)))
    }

    func testCatalogNegotiationRequiresExactAdditiveEchoAndPreservesLegacyBase() {
        let authority = WebRTCRemoteMediaAuthorization()
        let legacy = "v=0\r\n" + RemoteMediaControlsSDP.attributeLine(for: authority) + "\r\nm=audio 9 RTP/AVP 0\r\n"
        let offer = RemoteMediaControlsSDP.advertisingHostSupport(in: legacy, authorization: authority)
        let answer = RemoteMediaControlsSDP.advertisingViewerSupport(in: "v=0\r\nm=audio 9 RTP/AVP 0\r\n", remoteOfferSDP: offer)
        XCTAssertTrue(RemoteMediaCatalogSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: answer))
        XCTAssertNotNil(RemoteMediaControlsSDP.negotiatedAuthorization(hostOfferSDP: offer, viewerAnswerSDP: legacy))
        XCTAssertFalse(RemoteMediaCatalogSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: legacy))
        let line = RemoteMediaCatalogSDP.attributePrefix + "1:" + authority.id.uuidString.lowercased()
        XCTAssertFalse(RemoteMediaCatalogSDP.negotiated(hostOfferSDP: offer, viewerAnswerSDP: line + "\r\n" + answer))
        XCTAssertFalse(RemoteMediaCatalogSDP.negotiated(hostOfferSDP: offer,
            viewerAnswerSDP: answer.replacingOccurrences(of: line, with: RemoteMediaCatalogSDP.attributePrefix + "1:" + UUID().uuidString.lowercased())))
        let legacyAnswer = RemoteMediaControlsSDP.advertisingViewerSupport(in: "v=0\r\n", remoteOfferSDP: legacy)
        XCTAssertNil(RemoteMediaCatalogSDP.advertisedAuthorization(in: legacyAnswer))
    }

    func testCatalogValidationLegacyDecodeAndExactSecondaryAdmission() throws {
        let primary = Self.catalogItem("primary"), secondary = Self.catalogItem("secondary")
        let state = WebRTCRemoteMediaStateUpdate(revision: 9, item: primary, additionalItems: [secondary])
        XCTAssertTrue(state.isValid)
        XCTAssertEqual(state.allItems.map(\.contextID), ["primary", "secondary"])
        let envelope = ControlChannelMessage.remoteMediaState(.init(authorization: .init(), update: state))
        let bytes = try JSONEncoder().encode(envelope)
        XCTAssertLessThanOrEqual(bytes.count, 4096)
        XCTAssertEqual(try JSONDecoder().decode(ControlChannelMessage.self, from: bytes), envelope)
        let legacyBytes = try JSONEncoder().encode(WebRTCRemoteMediaStateUpdate(revision: 1, item: primary))
        XCTAssertFalse(String(decoding: legacyBytes, as: UTF8.self).contains("additionalItems"))
        XCTAssertEqual(try JSONDecoder().decode(WebRTCRemoteMediaStateUpdate.self, from: legacyBytes).additionalItems, [])
        XCTAssertFalse(WebRTCRemoteMediaStateUpdate(revision: 1, item: primary, additionalItems: [primary]).isValid)
        XCTAssertFalse(WebRTCRemoteMediaStateUpdate(revision: 1, item: nil, additionalItems: [secondary]).isValid)
        XCTAssertFalse(WebRTCRemoteMediaStateUpdate(revision: 1, item: primary, additionalItems: [secondary, Self.catalogItem("third")]).isValid)
        let command = WebRTCRemoteMediaCommandRequest(id: 1, contextID: "secondary", observedRevision: 9, command: .seekForward30)
        XCTAssertNil(WebRTCRemoteMediaCommandAdmission.rejection(for: command, latestSuccessfullySent: state))
        XCTAssertEqual(WebRTCRemoteMediaCommandAdmission.rejection(for: command,
            latestSuccessfullySent: .init(revision: 10, item: primary, additionalItems: [Self.catalogItem("replacement")])) , .staleContext)
        XCTAssertEqual(WebRTCRemoteMediaCommandAdmission.rejection(for: command,
            latestSuccessfullySent: .init(revision: 8, item: primary, additionalItems: [secondary])), .staleContext)
    }

    private static func catalogItem(_ context: String) -> WebRTCRemoteMediaItem {
        .init(contextID: context, sourceName: context, title: "Track", playbackState: .playing,
              elapsedTime: 40, duration: 200, playbackRate: 1,
              capabilities: .init(canPlay: true, canPause: true, canSkipForward: true,
                  canSkipBackward: true, canSeekForward: true, canSeekBackward: true, canSeekToPosition: true))
    }

    private static func oversizedCatalog() -> WebRTCRemoteMediaStateUpdate {
        func item(_ context: String) -> WebRTCRemoteMediaItem {
            .init(contextID: context, sourceName: String(repeating: "\\", count: 128),
                  title: String(repeating: "\"", count: 512), artist: String(repeating: "\\", count: 256),
                  album: String(repeating: "\"", count: 256), playbackState: .playing,
                  elapsedTime: 40, duration: 200, playbackRate: 1,
                  capabilities: .init(canPlay: true, canPause: true, canSkipForward: true,
                      canSkipBackward: true, canSeekForward: true, canSeekBackward: true, canSeekToPosition: true),
                  artwork: .init(videoID: "dQw4w9WgXcQ"))
        }
        return .init(revision: 1, item: item("primary"), additionalItems: [item("secondary")])
    }

    func testEscapedCatalogFitsActualEnvelopeWithoutChangingAuthority() throws {
        let update = Self.oversizedCatalog()
        let original = WebRTCRemoteMediaStateEnvelope(authorization: .init(), update: update, refreshID: UUID())
        XCTAssertTrue(original.isValid)
        XCTAssertGreaterThan(try JSONEncoder().encode(ControlChannelMessage.remoteMediaState(original)).count, 4096)
        let encoded = try WebRTCRemoteMediaStateWireEncoding.encode(original)
        XCTAssertLessThanOrEqual(encoded.data.count, 4096)
        guard case .remoteMediaState(let decoded) = try JSONDecoder().decode(ControlChannelMessage.self, from: encoded.data) else {
            return XCTFail("Expected media state")
        }
        XCTAssertTrue(decoded.isValid)
        XCTAssertEqual(decoded.authorization, original.authorization)
        XCTAssertEqual(decoded.refreshID, original.refreshID)
        XCTAssertEqual(decoded.update, encoded.update)
        XCTAssertEqual(decoded.update.revision, update.revision)
        XCTAssertEqual(decoded.update.allItems.count, 2)
        for (source, projected) in zip(update.allItems, decoded.update.allItems) {
            XCTAssertEqual(projected.contextID, source.contextID)
            XCTAssertEqual(projected.capabilities, source.capabilities)
            XCTAssertEqual(projected.playbackState, source.playbackState)
            XCTAssertEqual(projected.elapsedTime, source.elapsedTime)
            XCTAssertEqual(projected.duration, source.duration)
            XCTAssertEqual(projected.playbackRate, source.playbackRate)
            XCTAssertEqual(projected.artwork, source.artwork)
            XCTAssertTrue(source.title.hasPrefix(projected.title))
            XCTAssertFalse(projected.title.isEmpty)
        }
        let repeated = try WebRTCRemoteMediaStateWireEncoding.encode(original)
        XCTAssertEqual(repeated.update, encoded.update)
    }

    func testSmallAndLegacyMediaEnvelopesDoNotLoseDecoration() throws {
        for update in [WebRTCRemoteMediaStateUpdate(revision: 1, item: nil),
                       .init(revision: 2, item: Self.catalogItem("primary")),
                       .init(revision: 3, item: Self.catalogItem("primary"), additionalItems: [Self.catalogItem("secondary")])] {
            let original = WebRTCRemoteMediaStateEnvelope(authorization: .init(), update: update, refreshID: UUID())
            let encoded = try WebRTCRemoteMediaStateWireEncoding.encode(original)
            XCTAssertEqual(encoded.update, original.update)
            XCTAssertEqual(try JSONDecoder().decode(ControlChannelMessage.self, from: encoded.data), .remoteMediaState(original))
        }
        let invalid = WebRTCRemoteMediaStateUpdate(revision: 1, item: nil, additionalItems: [Self.catalogItem("secondary")])
        XCTAssertThrowsError(try WebRTCRemoteMediaStateWireEncoding.encode(.init(authorization: .init(), update: invalid)))
    }

    func testCatalogCommandImmediateAcknowledgementCompletesOnce() async throws {
        let (host, viewer, recorder, expectations, hostForwarder, viewerForwarder) = try makeRemoteMediaFlow(automaticallyAcknowledge: true)
        do {
            try await host.start()
            await fulfillment(of: [expectations.hostConnected, expectations.viewerConnected,
                expectations.hostDataChannelOpen, expectations.viewerDataChannelOpen], timeout: 10)
            let oversized = Self.oversizedCatalog()
            try await host.sendRemoteMediaState(oversized)
            await fulfillment(of: [expectations.stateReceived], timeout: 3)
            let received = await recorder.snapshot()
            let state = try XCTUnwrap(received.receivedStates.last)
            XCTAssertEqual(state.update.additionalItems.map(\.contextID), ["secondary"])
            XCTAssertNotEqual(state.update, oversized, "Oversized display metadata must be shortened before actual transport")
            let rejectedResults = RemoteMediaCallbackResults()
            for deadline in [ProcessInfo.processInfo.systemUptime - 1, .nan, .infinity,
                             ProcessInfo.processInfo.systemUptime + 60] {
                do {
                    _ = try await viewer.requestRemoteMediaCommand(.seekToPosition, state: state,
                        authorization: WebRTCControlAuthorization(), contextID: "secondary", positionSeconds: 47.125,
                        deadlineUptime: deadline, acknowledgementHandler: { rejectedResults.append($0) })
                    XCTFail("Expired or malformed local authority must not send")
                } catch {
                    XCTAssertEqual(error as? WebRTCTransportError, .controlAuthorizationRevoked)
                }
            }
            let heldAuthorization = WebRTCControlAuthorization()
            let lockHeld = XCTestExpectation(description: "presentation lock held across deadline")
            let lockReleased = XCTestExpectation(description: "presentation lock released")
            DispatchQueue.global().async {
                try? heldAuthorization.withValidAuthorization {
                    lockHeld.fulfill()
                    Thread.sleep(forTimeInterval: 0.25)
                }
                lockReleased.fulfill()
            }
            await fulfillment(of: [lockHeld], timeout: 1)
            do {
                _ = try await viewer.requestRemoteMediaCommand(.seekToPosition, state: state,
                    authorization: heldAuthorization, contextID: "secondary", positionSeconds: 47.125,
                    deadlineUptime: ProcessInfo.processInfo.systemUptime + 0.05,
                    expectedDurationSeconds: 200)
                XCTFail("Local authority expiring while the send lock is held must not send")
            } catch {
                XCTAssertEqual(error as? WebRTCTransportError, .controlAuthorizationRevoked)
            }
            await fulfillment(of: [lockReleased], timeout: 1)
            let results = RemoteMediaCallbackResults()
            let id = try await viewer.requestRemoteMediaCommand(.seekToPosition, state: state,
                authorization: WebRTCControlAuthorization(), contextID: "secondary", positionSeconds: 57.125,
                deadlineUptime: ProcessInfo.processInfo.systemUptime + 2,
                expectedDurationSeconds: 200,
                acknowledgementHandler: { results.append($0) })
            XCTAssertEqual(id, 1, "Rejected local authority must not consume a command ID")
            try await waitForRemoteMediaCondition { results.read() == [.applied] }
            let commands = await recorder.snapshot()
            let command = try XCTUnwrap(commands.receivedCommands.last)
            XCTAssertEqual(command.request.contextID, "secondary")
            XCTAssertEqual(command.request.id, id)
            XCTAssertEqual(command.request.command, .seekToPosition)
            XCTAssertEqual(command.request.positionSeconds, 57.125)
            try await host.acknowledgeRemoteMediaCommand(command, result: .applied)
            try await viewer.sendRemoteMediaCommandForTesting(command.request, state: state)
            let conflicting = WebRTCRemoteMediaCommandRequest(id: id, contextID: "secondary",
                observedRevision: state.update.revision, command: .seekToPosition, positionSeconds: 58.125)
            try await viewer.sendRemoteMediaCommandForTesting(conflicting, state: state)
            try await viewer.requestRemoteMediaStateRefresh(id: UUID())
            try await waitForRemoteMediaCondition { await recorder.snapshot().refreshRequests.count == 1 }
            XCTAssertEqual(results.read(), [.applied])
            let final = await recorder.snapshot()
            XCTAssertEqual(final.commands.count, 1)
            XCTAssertTrue(rejectedResults.read().isEmpty)
            let relativeResults = RemoteMediaCallbackResults()
            _ = try await viewer.requestRemoteMediaCommand(.seekForward30, state: state,
                authorization: WebRTCControlAuthorization(), contextID: "secondary",
                acknowledgementHandler: { relativeResults.append($0) })
            try await waitForRemoteMediaCondition { relativeResults.read() == [.applied] }
            let relative = await recorder.snapshot()
            XCTAssertEqual(relative.commands.count, 2)
            XCTAssertEqual(relative.commands.last?.command, .seekForward30)
            XCTAssertNil(relative.commands.last?.positionSeconds)
            for (offset, duration) in [100.0, 300.0].enumerated() {
                let secondary = WebRTCRemoteMediaItem(contextID: "secondary", sourceName: "secondary", title: "Track",
                    playbackState: .playing, elapsedTime: 40, duration: duration, playbackRate: 1,
                    capabilities: Self.catalogItem("secondary").capabilities)
                try await host.sendRemoteMediaState(.init(revision: UInt64(offset + 2),
                    item: Self.catalogItem("primary"), additionalItems: [secondary]))
                try await waitForRemoteMediaCondition { await recorder.snapshot().states.count == offset + 2 }
                do {
                    _ = try await viewer.requestRemoteMediaCommand(.seekToPosition, state: state,
                        authorization: WebRTCControlAuthorization(), contextID: "secondary", positionSeconds: 57.125,
                        deadlineUptime: ProcessInfo.processInfo.systemUptime + 2, expectedDurationSeconds: 200)
                    XCTFail("A newer same-context duration invalidates the captured timeline")
                } catch {
                    XCTAssertEqual(error as? WebRTCTransportError, .controlAuthorizationRevoked)
                }
            }
            let afterTimelineChanges = await recorder.snapshot()
            XCTAssertEqual(afterTimelineChanges.commands.count, 2)
        } catch {
            hostForwarder.cancel(); viewerForwarder.cancel()
            _ = await host.close(reason: .protocolError); _ = await viewer.close(reason: .protocolError)
            throw error
        }
        hostForwarder.cancel(); viewerForwarder.cancel()
        _ = await host.close(reason: .normal); _ = await viewer.close(reason: .normal)
    }

    func testCommandCallbackTimeoutAndTransportRetirementDoNotReplay() async throws {
        let (host, viewer, recorder, expectations, hostForwarder, viewerForwarder) = try makeRemoteMediaFlow()
        do {
            try await host.start()
            await fulfillment(of: [expectations.hostConnected, expectations.viewerConnected,
                expectations.hostDataChannelOpen, expectations.viewerDataChannelOpen], timeout: 10)
            try await host.sendRemoteMediaState(.init(revision: 1, item: Self.catalogItem("primary")))
            await fulfillment(of: [expectations.stateReceived], timeout: 3)
            let received = await recorder.snapshot()
            let state = try XCTUnwrap(received.receivedStates.last)
            let timed = RemoteMediaCallbackResults()
            _ = try await viewer.requestRemoteMediaCommand(.seekBackward30, state: state,
                authorization: WebRTCControlAuthorization(), acknowledgementHandler: { timed.append($0) })
            await fulfillment(of: [expectations.commandReceived], timeout: 3)
            try await Task.sleep(for: .milliseconds(3200))
            XCTAssertEqual(timed.read(), [.failed])
            let before = await recorder.snapshot()
            try await host.acknowledgeRemoteMediaCommand(try XCTUnwrap(before.receivedCommands.last), result: .applied)
            await fulfillment(of: [expectations.acknowledgementReceived], timeout: 3)
            XCTAssertEqual(timed.read(), [.failed])
            let retired = RemoteMediaCallbackResults()
            _ = try await viewer.requestRemoteMediaCommand(.pause, state: state,
                authorization: WebRTCControlAuthorization(), acknowledgementHandler: { retired.append($0) })
            _ = await viewer.close(reason: .normal)
            XCTAssertEqual(retired.read(), [.staleContext])
            XCTAssertEqual(timed.read(), [.failed])
            XCTAssertEqual(before.commands.count, 1)
        } catch {
            hostForwarder.cancel(); viewerForwarder.cancel()
            _ = await host.close(reason: .protocolError); _ = await viewer.close(reason: .protocolError)
            throw error
        }
        hostForwarder.cancel(); viewerForwarder.cancel()
        _ = await host.close(reason: .normal); _ = await viewer.close(reason: .normal)
    }
    func testCapabilityRequiresExactBidirectionalSessionLevelAuthorizationEcho() {
        let authorization = WebRTCRemoteMediaAuthorization(
            id: UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!
        )
        let otherAuthorization = WebRTCRemoteMediaAuthorization(
            id: UUID(uuidString: "fedcba98-7654-3210-fedc-ba9876543210")!
        )
        let offer = "v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"
        let advertised = RemoteMediaControlsSDP.advertisingHostSupport(
            in: offer,
            authorization: authorization
        )
        let answer = RemoteMediaControlsSDP.advertisingViewerSupport(
            in: offer,
            remoteOfferSDP: advertised
        )

        XCTAssertEqual(
            RemoteMediaControlsSDP.negotiatedAuthorization(
                hostOfferSDP: advertised,
                viewerAnswerSDP: answer
            ),
            authorization
        )
        let attributeLine = RemoteMediaControlsSDP.attributeLine(for: authorization)
        XCTAssertEqual(
            advertised.components(separatedBy: attributeLine).count,
            2
        )
        XCTAssertEqual(
            RemoteMediaControlsSDP.advertisingHostSupport(
                in: advertised,
                authorization: authorization
            ),
            advertised
        )

        let unsupportedOffers = [
            offer,
            "v=0\r\na=x-opensteamer-remote-media-controls:2:"
                + authorization.id.uuidString.lowercased()
                + "\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n",
            "v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"
                + attributeLine + "\r\n",
            "v=0\r\n" + attributeLine + "\r\n" + attributeLine
                + "\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n",
        ]
        for unsupported in unsupportedOffers {
            XCTAssertNil(
                RemoteMediaControlsSDP.negotiatedAuthorization(
                    hostOfferSDP: unsupported,
                    viewerAnswerSDP: answer
                )
            )
        }
        let mismatchedAnswer = RemoteMediaControlsSDP.advertisingHostSupport(
            in: offer,
            authorization: otherAuthorization
        )
        XCTAssertNil(
            RemoteMediaControlsSDP.negotiatedAuthorization(
                hostOfferSDP: advertised,
                viewerAnswerSDP: mismatchedAnswer
            )
        )
    }

    func testStateCommandAndAcknowledgementRoundTripUnderWireLimit() throws {
        let authorization = WebRTCRemoteMediaAuthorization(
            id: UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!
        )
        let capabilities = WebRTCRemoteMediaCapabilities(
            canPlay: true,
            canPause: true,
            canSkipForward: true,
            canSkipBackward: true,
            canSeekForward: true,
            canSeekBackward: true,
            canSeekToPosition: true
        )
        let item = WebRTCRemoteMediaItem(
            contextID: UUID().uuidString,
            sourceName: "Music",
            title: "You Say Run",
            artist: "RichaadEB",
            album: "You Say Run - Single",
            playbackState: .playing,
            elapsedTime: 12.5,
            duration: 224.6,
            playbackRate: 1,
            capabilities: capabilities
        )
        let update = WebRTCRemoteMediaStateUpdate(revision: 7, item: item)
        let request = WebRTCRemoteMediaCommandRequest(
            id: 9,
            contextID: item.contextID,
            observedRevision: update.revision,
            command: .nextTrack
        )
        let acknowledgement = WebRTCRemoteMediaCommandAcknowledgement(
            id: request.id,
            result: .applied
        )
        let messages: [ControlChannelMessage] = [
            .remoteMediaState(
                WebRTCRemoteMediaStateEnvelope(
                    authorization: authorization,
                    update: update,
                    refreshID: UUID()
                )
            ),
            .remoteMediaStateRefresh(
                WebRTCRemoteMediaStateRefreshEnvelope(
                    authorization: authorization,
                    id: UUID()
                )
            ),
            .remoteMediaCommand(
                WebRTCRemoteMediaCommandEnvelope(
                    authorization: authorization,
                    request: request
                )
            ),
            .remoteMediaCommandAcknowledgement(
                WebRTCRemoteMediaCommandAcknowledgementEnvelope(
                    authorization: authorization,
                    acknowledgement: acknowledgement
                )
            ),
        ]

        for message in messages {
            let data = try JSONEncoder().encode(message)
            XCTAssertLessThanOrEqual(data.count, 4_096)
            XCTAssertEqual(
                try JSONDecoder().decode(ControlChannelMessage.self, from: data),
                message
            )
        }
        XCTAssertTrue(update.isValid)
        XCTAssertTrue(request.isValid)
        XCTAssertTrue(acknowledgement.isValid)
        for command in WebRTCRemoteMediaCommand.allCases {
            XCTAssertTrue(capabilities.permits(command))
        }
    }

    func testMalformedOrUnboundedMediaValuesAreRejected() {
        let capabilities = WebRTCRemoteMediaCapabilities(
            canPlay: true,
            canPause: true,
            canSkipForward: false,
            canSkipBackward: false
        )
        let invalidItem = WebRTCRemoteMediaItem(
            contextID: "context",
            sourceName: "Music",
            title: String(repeating: "x", count: 513),
            playbackState: .playing,
            elapsedTime: .infinity,
            duration: -1,
            playbackRate: .nan,
            capabilities: capabilities
        )
        XCTAssertFalse(invalidItem.isValid)
        XCTAssertFalse(
            WebRTCRemoteMediaStateUpdate(revision: 0, item: nil).isValid
        )
        XCTAssertFalse(
            WebRTCRemoteMediaCommandRequest(
                id: 0,
                contextID: "context",
                observedRevision: 1,
                command: .pause
            ).isValid
        )
        XCTAssertFalse(
            WebRTCRemoteMediaCommandRequest(
                id: 1,
                contextID: "bad\ncontext",
                observedRevision: 1,
                command: .pause
            ).isValid
        )
    }

    func testAbsoluteSeekParameterAndLegacyCapabilityFailClosed() throws {
        let legacy = Data(#"{"canPlay":true,"canPause":true,"canSkipForward":true,"canSkipBackward":true}"#.utf8)
        let capabilities = try JSONDecoder().decode(WebRTCRemoteMediaCapabilities.self, from: legacy)
        XCTAssertFalse(capabilities.canSeekToPosition)
        XCTAssertFalse(capabilities.permits(.seekToPosition))
        for position in [nil, -1.0, .infinity, .nan, 31_536_001.0] as [Double?] {
            let request = WebRTCRemoteMediaCommandRequest(id: 1, contextID: "primary", observedRevision: 1,
                command: .seekToPosition, positionSeconds: position)
            XCTAssertFalse(request.isValid)
            XCTAssertEqual(WebRTCRemoteMediaCommandAdmission.rejection(for: request,
                latestSuccessfullySent: .init(revision: 1, item: Self.catalogItem("primary"))), .failed)
        }
        for command in WebRTCRemoteMediaCommand.allCases where command != .seekToPosition {
            XCTAssertFalse(WebRTCRemoteMediaCommandRequest(id: 1, contextID: "primary", observedRevision: 1,
                command: command, positionSeconds: 25).isValid)
        }
        for position in [0.0, 57.125, 31_536_000.0] {
            let request = WebRTCRemoteMediaCommandRequest(id: 1, contextID: "primary", observedRevision: 1,
                command: .seekToPosition, positionSeconds: position)
            XCTAssertTrue(request.isValid)
            let bytes = try JSONEncoder().encode(request)
            XCTAssertLessThan(bytes.count, 4096)
            XCTAssertEqual(try JSONDecoder().decode(WebRTCRemoteMediaCommandRequest.self, from: bytes), request)
            XCTAssertNil(WebRTCRemoteMediaCommandAdmission.rejection(for: request,
                latestSuccessfullySent: .init(revision: 1, item: Self.catalogItem("primary"))))
        }
    }

    func testCommandAdmissionAllowsOlderRevisionOnlyForCurrentContextAndCapability() {
        let capabilities = WebRTCRemoteMediaCapabilities(
            canPlay: true,
            canPause: true,
            canSkipForward: true,
            canSkipBackward: false
        )
        let item = WebRTCRemoteMediaItem(
            contextID: "current-context",
            sourceName: "Music",
            title: "Track",
            playbackState: .playing,
            playbackRate: 1,
            capabilities: capabilities
        )
        let latest = WebRTCRemoteMediaStateUpdate(revision: 11, item: item)
        let sameContextAfterRefresh = WebRTCRemoteMediaCommandRequest(
            id: 1,
            contextID: item.contextID,
            observedRevision: 10,
            command: .nextTrack
        )

        XCTAssertNil(
            WebRTCRemoteMediaCommandAdmission.rejection(
                for: sameContextAfterRefresh,
                latestSuccessfullySent: latest
            )
        )
        XCTAssertEqual(
            WebRTCRemoteMediaCommandAdmission.rejection(
                for: WebRTCRemoteMediaCommandRequest(
                    id: 2,
                    contextID: item.contextID,
                    observedRevision: 12,
                    command: .nextTrack
                ),
                latestSuccessfullySent: latest
            ),
            .staleContext
        )
        XCTAssertEqual(
            WebRTCRemoteMediaCommandAdmission.rejection(
                for: WebRTCRemoteMediaCommandRequest(
                    id: 3,
                    contextID: "retired-context",
                    observedRevision: 11,
                    command: .nextTrack
                ),
                latestSuccessfullySent: latest
            ),
            .staleContext
        )
        XCTAssertEqual(
            WebRTCRemoteMediaCommandAdmission.rejection(
                for: WebRTCRemoteMediaCommandRequest(
                    id: 4,
                    contextID: item.contextID,
                    observedRevision: 11,
                    command: .previousTrack
                ),
                latestSuccessfullySent: latest
            ),
            .unsupported
        )
        XCTAssertEqual(
            WebRTCRemoteMediaCommandAdmission.rejection(
                for: sameContextAfterRefresh,
                latestSuccessfullySent: nil
            ),
            .noActiveMedia
        )
    }

    func testRemoteMediaCapabilityDefaultsOffAndRequiresExplicitLocalOptIn() {
        let defaultConfiguration = WebRTCTransportConfiguration(
            role: .host,
            iceServers: []
        )
        let enabledConfiguration = WebRTCTransportConfiguration(
            role: .viewer,
            iceServers: [],
            supportsRemoteMediaControls: true
        )

        XCTAssertFalse(defaultConfiguration.supportsRemoteMediaControls)
        XCTAssertTrue(enabledConfiguration.supportsRemoteMediaControls)
    }

    func testPeerNegotiationRequiresBothOptInsAndPublishesAnswerBeforeAvailability()
        async throws {
        let host = try WebRTCPeer(
            configuration: WebRTCTransportConfiguration(
                role: .host,
                iceServers: [],
                supportsRemoteMediaControls: true
            )
        )
        let viewer = try WebRTCPeer.makeHeadlessViewerForTesting(
            configuration: WebRTCTransportConfiguration(
                role: .viewer,
                iceServers: [],
                supportsRemoteMediaControls: true
            )
        )
        do {
            try await host.start()
            var offeredValue: String?
            for await event in host.events {
                if case .outboundSignal(.offer(let sdp)) = event {
                    offeredValue = sdp
                    break
                }
            }
            let offered = try XCTUnwrap(offeredValue)
            let offeredAuthorization = try XCTUnwrap(
                RemoteMediaControlsSDP.advertisedAuthorization(in: offered)
            )

            try await viewer.handle(.offer(sdp: offered))
            var answer: String?
            var eventOrder: [String] = []
            for await event in viewer.events {
                switch event {
                case .outboundSignal(.answer(let sdp)):
                    answer = sdp
                    eventOrder.append("answer")
                case .remoteMediaControlsAvailabilityChanged(true):
                    eventOrder.append("available")
                    break
                default:
                    continue
                }
                if eventOrder.last == "available" { break }
            }
            let answered = try XCTUnwrap(answer)

            XCTAssertEqual(eventOrder, ["answer", "available"])
            XCTAssertEqual(
                RemoteMediaControlsSDP.advertisedAuthorization(in: answered),
                offeredAuthorization
            )
            let viewerNegotiated = await viewer.remoteMediaControlsAreNegotiated()
            XCTAssertTrue(viewerNegotiated)

            try await host.handle(.answer(sdp: answered))
            let hostNegotiated = await host.remoteMediaControlsAreNegotiated()
            XCTAssertTrue(hostNegotiated)
        } catch {
            _ = await host.close(reason: .protocolError)
            _ = await viewer.close(reason: .protocolError)
            throw error
        }
        let hostRetired = await host.close(reason: .normal)
        let viewerRetired = await viewer.close(reason: .normal)
        XCTAssertTrue(hostRetired)
        XCTAssertTrue(viewerRetired)
    }

    func testLegacyViewerDoesNotNegotiateOrPermitRemoteMediaMessages()
        async throws {
        let host = try WebRTCPeer(
            configuration: WebRTCTransportConfiguration(
                role: .host,
                iceServers: [],
                supportsRemoteMediaControls: true
            )
        )
        let viewer = try WebRTCPeer.makeHeadlessViewerForTesting(
            configuration: WebRTCTransportConfiguration(
                role: .viewer,
                iceServers: []
            )
        )
        do {
            try await host.start()
            var offeredValue: String?
            for await event in host.events {
                if case .outboundSignal(.offer(let sdp)) = event {
                    offeredValue = sdp
                    break
                }
            }
            let offered = try XCTUnwrap(offeredValue)
            XCTAssertNotNil(
                RemoteMediaControlsSDP.advertisedAuthorization(in: offered)
            )

            try await viewer.handle(.offer(sdp: offered))
            var answeredValue: String?
            for await event in viewer.events {
                if case .outboundSignal(.answer(let sdp)) = event {
                    answeredValue = sdp
                    break
                }
            }
            let answered = try XCTUnwrap(answeredValue)
            XCTAssertNil(
                RemoteMediaControlsSDP.advertisedAuthorization(in: answered)
            )
            try await host.handle(.answer(sdp: answered))

            let hostNegotiated = await host.remoteMediaControlsAreNegotiated()
            let viewerNegotiated = await viewer.remoteMediaControlsAreNegotiated()
            XCTAssertFalse(hostNegotiated)
            XCTAssertFalse(viewerNegotiated)

            let update = WebRTCRemoteMediaStateUpdate(revision: 1, item: nil)
            do {
                try await host.sendRemoteMediaState(update)
                XCTFail("A host must not send a new wire kind to a legacy viewer.")
            } catch let error as WebRTCTransportError {
                XCTAssertEqual(error, .transportNotHealthy)
            }
            do {
                _ = try await viewer.requestRemoteMediaCommand(
                    .pause,
                    state: WebRTCReceivedRemoteMediaState(envelope: .init(
                        authorization: .init(),
                        update: update
                    )),
                    authorization: WebRTCControlAuthorization()
                )
                XCTFail("A legacy viewer must not send a remote-media command.")
            } catch let error as WebRTCTransportError {
                XCTAssertEqual(error, .transportNotHealthy)
            }
        } catch {
            _ = await host.close(reason: .protocolError)
            _ = await viewer.close(reason: .protocolError)
            throw error
        }
        let hostRetired = await host.close(reason: .normal)
        let viewerRetired = await viewer.close(reason: .normal)
        XCTAssertTrue(hostRetired)
        XCTAssertTrue(viewerRetired)
    }

    func testNegotiatedPeersRetryFailedAcknowledgementWithoutRepeatingCommand()
        async throws {
        let (host, viewer, recorder, expectations, hostForwarder, viewerForwarder) =
            try makeRemoteMediaFlow()

        do {
            try await host.start()
            await fulfillment(
                of: [
                    expectations.hostConnected,
                    expectations.viewerConnected,
                    expectations.hostDataChannelOpen,
                    expectations.viewerDataChannelOpen,
                ],
                timeout: 10
            )
            let hostHealthy = await host.isTransportHealthyForMediaForTesting
            let viewerHealthy = await viewer.isTransportHealthyForMediaForTesting
            guard hostHealthy, viewerHealthy else {
                throw WebRTCTransportError.transportNotHealthy
            }
            let hostNegotiated = await host.remoteMediaControlsAreNegotiated()
            let viewerNegotiated = await viewer.remoteMediaControlsAreNegotiated()
            XCTAssertTrue(hostNegotiated)
            XCTAssertTrue(viewerNegotiated)

            let capabilities = WebRTCRemoteMediaCapabilities(
                canPlay: true,
                canPause: true,
                canSkipForward: true,
                canSkipBackward: true
            )
            let item = WebRTCRemoteMediaItem(
                contextID: "end-to-end-context",
                sourceName: "Music",
                title: "End-to-End Track",
                playbackState: .playing,
                elapsedTime: 12,
                duration: 180,
                playbackRate: 1,
                capabilities: capabilities
            )
            let update = WebRTCRemoteMediaStateUpdate(
                revision: 1,
                item: item
            )
            try await host.sendRemoteMediaState(update)
            await fulfillment(of: [expectations.stateReceived], timeout: 3)
            let firstStateSnapshot = await recorder.snapshot()
            let firstState = try XCTUnwrap(firstStateSnapshot.receivedStates.first)

            let commandID = try await viewer.requestRemoteMediaCommand(
                .pause,
                state: firstState,
                authorization: WebRTCControlAuthorization()
            )
            await fulfillment(of: [expectations.commandReceived], timeout: 3)
            let firstCommandSnapshot = await recorder.snapshot()
            let firstCommand = try XCTUnwrap(firstCommandSnapshot.receivedCommands.first)

            await host.setRemoteMediaAcknowledgementRetryDelayForTesting(
                .milliseconds(1)
            )
            await host.failNextRemoteMediaAcknowledgementSendsForTesting(100)
            do {
                try await host.acknowledgeRemoteMediaCommand(
                    firstCommand,
                    result: .applied
                )
                XCTFail("The deterministic first acknowledgement send must fail.")
            } catch let error as WebRTCTransportError {
                XCTAssertEqual(error, .dataChannelBackpressured)
            }
            let pendingRetry = await host
                .remoteMediaAcknowledgementRetryStateForTesting()
            XCTAssertEqual(pendingRetry.pendingCount, 1)
            XCTAssertTrue(pendingRetry.isScheduled)

            var observedRepeatedFailures = false
            for _ in 0..<200 {
                let retry = await host
                    .remoteMediaAcknowledgementRetryStateForTesting()
                if retry.forcedFailuresRemaining <= 90 {
                    observedRepeatedFailures = true
                    break
                }
                try await Task.sleep(for: .milliseconds(2))
            }
            XCTAssertTrue(
                observedRepeatedFailures,
                "The test must cross the old bounded-attempt shutdown threshold."
            )
            let hostIsClosed = await host.isClosedForTesting
            let stayedNegotiated = await host.remoteMediaControlsAreNegotiated()
            XCTAssertFalse(hostIsClosed)
            XCTAssertTrue(stayedNegotiated)

            await host.failNextRemoteMediaAcknowledgementSendsForTesting(0)
            await fulfillment(
                of: [expectations.acknowledgementReceived],
                timeout: 3
            )
            let flushedRetry = await host
                .remoteMediaAcknowledgementRetryStateForTesting()
            XCTAssertEqual(flushedRetry.pendingCount, 0)
            XCTAssertFalse(flushedRetry.isScheduled)
            XCTAssertEqual(flushedRetry.forcedFailuresRemaining, 0)
            await host.setRemoteMediaAcknowledgementRetryDelayForTesting(nil)

            let snapshot = await recorder.snapshot()
            XCTAssertEqual(snapshot.states, [update])
            XCTAssertEqual(
                snapshot.commands,
                [
                    WebRTCRemoteMediaCommandRequest(
                        id: commandID,
                        contextID: item.contextID,
                        observedRevision: update.revision,
                        command: .pause
                    )
                ]
            )
            XCTAssertEqual(
                snapshot.acknowledgements,
                [
                    WebRTCRemoteMediaCommandAcknowledgement(
                        id: commandID,
                        result: .applied
                    )
                ]
            )
            XCTAssertTrue(snapshot.forwardingErrors.isEmpty)

            // A second terminal result remains intentionally unsent. ICE restart must synchronously
            // cancel and erase its retry so the old authorization cannot acknowledge a new epoch.
            let secondUpdate = WebRTCRemoteMediaStateUpdate(
                revision: 2,
                item: item
            )
            try await host.sendRemoteMediaState(secondUpdate)
            var receivedSecondState = false
            for _ in 0..<100 {
                if await recorder.snapshot().states.count == 2 {
                    receivedSecondState = true
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(receivedSecondState)
            let secondStateSnapshot = await recorder.snapshot()
            let secondState = try XCTUnwrap(secondStateSnapshot.receivedStates.last)

            let secondCommandID = try await viewer.requestRemoteMediaCommand(
                .nextTrack,
                state: secondState,
                authorization: WebRTCControlAuthorization()
            )
            var receivedSecondCommand = false
            for _ in 0..<100 {
                if await recorder.snapshot().commands.count == 2 {
                    receivedSecondCommand = true
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(receivedSecondCommand)
            let secondCommandSnapshot = await recorder.snapshot()
            let secondCommand = try XCTUnwrap(secondCommandSnapshot.receivedCommands.last)
            XCTAssertEqual(secondCommand.request.id, secondCommandID)

            await host.failNextRemoteMediaAcknowledgementSendsForTesting(100)
            do {
                try await host.acknowledgeRemoteMediaCommand(
                    secondCommand,
                    result: .applied
                )
                XCTFail("The pre-restart acknowledgement send must remain pending.")
            } catch let error as WebRTCTransportError {
                XCTAssertEqual(error, .dataChannelBackpressured)
            }
            let preRestartRetry = await host
                .remoteMediaAcknowledgementRetryStateForTesting()
            XCTAssertEqual(preRestartRetry.pendingCount, 1)
            XCTAssertTrue(preRestartRetry.isScheduled)

            try await host.restartICE()
            let postRestartRetry = await host
                .remoteMediaAcknowledgementRetryStateForTesting()
            XCTAssertEqual(postRestartRetry.pendingCount, 0)
            XCTAssertFalse(postRestartRetry.isScheduled)
            XCTAssertEqual(postRestartRetry.forcedFailuresRemaining, 0)
            try await Task.sleep(for: .milliseconds(150))
            let postRestartSnapshot = await recorder.snapshot()
            XCTAssertEqual(
                postRestartSnapshot.acknowledgements,
                snapshot.acknowledgements,
                "A cached acknowledgement from the retired authorization must not replay."
            )
        } catch {
            hostForwarder.cancel()
            viewerForwarder.cancel()
            _ = await host.close(reason: .protocolError)
            _ = await viewer.close(reason: .protocolError)
            _ = await hostForwarder.value
            _ = await viewerForwarder.value
            throw error
        }

        hostForwarder.cancel()
        viewerForwarder.cancel()
        let hostRetired = await host.close(reason: .normal)
        let viewerRetired = await viewer.close(reason: .normal)
        _ = await hostForwarder.value
        _ = await viewerForwarder.value
        XCTAssertTrue(hostRetired)
        XCTAssertTrue(viewerRetired)
    }

    func testDelayedApplicationTokensCannotCrossRenegotiationWithReusedCommandID()
        async throws {
        let (host, viewer, recorder, expectations, hostForwarder, viewerForwarder) =
            try makeRemoteMediaFlow()
        do {
            try await host.start()
            await fulfillment(of: [
                expectations.hostConnected, expectations.viewerConnected,
                expectations.hostDataChannelOpen, expectations.viewerDataChannelOpen,
            ], timeout: 10)
            let item = WebRTCRemoteMediaItem(
                contextID: "unchanged-paused-context",
                sourceName: "Music",
                title: "Unchanged Paused Track",
                playbackState: .paused,
                playbackRate: 0,
                capabilities: .init(
                    canPlay: true, canPause: true,
                    canSkipForward: true, canSkipBackward: true
                )
            )
            let update = WebRTCRemoteMediaStateUpdate(revision: 1, item: item)
            try await host.sendRemoteMediaState(update)
            await fulfillment(of: [expectations.stateReceived], timeout: 3)
            let initial = await recorder.snapshot()
            let oldState = try XCTUnwrap(initial.receivedStates.first)
            let oldID = try await viewer.requestRemoteMediaCommand(
                .play, state: oldState, authorization: WebRTCControlAuthorization()
            )
            XCTAssertEqual(oldID, 1)
            await fulfillment(of: [expectations.commandReceived], timeout: 3)
            let oldCommandSnapshot = await recorder.snapshot()
            let oldCommand = try XCTUnwrap(oldCommandSnapshot.receivedCommands.first)
            try await viewer.requestRemoteMediaStateRefresh(id: UUID())
            try await waitForRemoteMediaCondition {
                await recorder.snapshot().refreshRequests.count == 1
            }
            let oldRefreshSnapshot = await recorder.snapshot()
            let oldRefresh = try XCTUnwrap(oldRefreshSnapshot.refreshRequests.first)

            try await host.restartICE()
            try await waitForRemoteMediaCondition {
                let hostReady = await host.remoteMediaControlsAreNegotiated()
                let viewerReady = await viewer.remoteMediaControlsAreNegotiated()
                let hostHealthy = await host.isTransportHealthyForMediaForTesting
                let viewerHealthy = await viewer.isTransportHealthyForMediaForTesting
                return hostReady && viewerReady && hostHealthy && viewerHealthy
            }
            // The semantic snapshot and numeric ID are deliberately identical. Only the opaque
            // negotiated authority distinguishes this command from suspended application work.
            try await host.sendRemoteMediaState(update)
            try await waitForRemoteMediaCondition {
                await recorder.snapshot().receivedStates.count == 2
            }
            let current = await recorder.snapshot()
            let currentState = try XCTUnwrap(current.receivedStates.last)
            XCTAssertEqual(currentState.update, oldState.update)
            XCTAssertFalse(currentState.isSameNegotiation(as: oldState))
            do {
                _ = try await viewer.requestRemoteMediaCommand(
                    .play, state: oldState, authorization: WebRTCControlAuthorization()
                )
                XCTFail("An old native presentation must not borrow the current negotiation.")
            } catch let error as WebRTCTransportError {
                XCTAssertEqual(error, .transportNotHealthy)
            }
            let revokedPresentation = WebRTCControlAuthorization()
            revokedPresentation.revoke()
            do {
                _ = try await viewer.requestRemoteMediaCommand(
                    .play, state: currentState, authorization: revokedPresentation
                )
                XCTFail("A revoked native presentation must not send after its actor hop.")
            } catch let error as WebRTCTransportError {
                XCTAssertEqual(error, .controlAuthorizationRevoked)
            }
            let currentID = try await viewer.requestRemoteMediaCommand(
                .play, state: currentState, authorization: WebRTCControlAuthorization()
            )
            XCTAssertEqual(currentID, oldID)
            try await waitForRemoteMediaCondition {
                await recorder.snapshot().receivedCommands.count == 2
            }
            let currentCommandSnapshot = await recorder.snapshot()
            let currentCommand = try XCTUnwrap(currentCommandSnapshot.receivedCommands.last)
            XCTAssertEqual(currentCommand.request, oldCommand.request)
            XCTAssertFalse(oldCommand.isValid)
            XCTAssertTrue(currentCommand.isValid)
            do {
                try await host.acknowledgeRemoteMediaCommand(oldCommand, result: .failed)
                XCTFail("A delayed old completion must not acknowledge the new ID 1.")
            } catch let error as WebRTCTransportError {
                XCTAssertEqual(error, .unexpectedSignal)
            }
            let wrongNegotiation = WebRTCReceivedRemoteMediaCommand(
                envelope: .init(
                    authorization: oldCommand.authorization,
                    request: currentCommand.request
                ),
                executionAuthorization: currentCommand.executionAuthorization
            )
            do {
                try await host.acknowledgeRemoteMediaCommand(wrongNegotiation, result: .failed)
                XCTFail("A live execution gate cannot substitute for the original negotiation.")
            } catch let error as WebRTCTransportError {
                XCTAssertEqual(error, .unexpectedSignal)
            }
            let changedRequest = WebRTCRemoteMediaCommandRequest(
                id: currentID, contextID: item.contextID, observedRevision: 1,
                command: .nextTrack
            )
            let mismatchedCommand = WebRTCReceivedRemoteMediaCommand(
                envelope: .init(authorization: currentCommand.authorization, request: changedRequest),
                executionAuthorization: currentCommand.executionAuthorization
            )
            do {
                try await host.acknowledgeRemoteMediaCommand(mismatchedCommand, result: .failed)
                XCTFail("Even current authority must acknowledge the exact original request.")
            } catch let error as WebRTCTransportError {
                XCTAssertEqual(error, .unexpectedSignal)
            }
            try await host.acknowledgeRemoteMediaCommand(currentCommand, result: .applied)
            await fulfillment(of: [expectations.acknowledgementReceived], timeout: 3)
            let acknowledged = await recorder.snapshot()
            XCTAssertEqual(acknowledged.acknowledgements, [.init(id: 1, result: .applied)])
            XCTAssertEqual(acknowledged.commands.count, 2)

            let refreshedUpdate = WebRTCRemoteMediaStateUpdate(revision: 2, item: item)
            do {
                try await host.sendRemoteMediaState(refreshedUpdate, respondingTo: oldRefresh)
                XCTFail("A stale queued refresh must not echo into the new negotiation.")
            } catch let error as WebRTCTransportError {
                XCTAssertEqual(error, .transportNotHealthy)
            }
            let refreshID = UUID()
            try await viewer.requestRemoteMediaStateRefresh(id: refreshID)
            try await waitForRemoteMediaCondition {
                await recorder.snapshot().refreshRequests.count == 2
            }
            let refreshSnapshot = await recorder.snapshot()
            let refresh = try XCTUnwrap(refreshSnapshot.refreshRequests.last)
            XCTAssertEqual(refresh.id, refreshID)
            try await host.sendRemoteMediaState(refreshedUpdate, respondingTo: refresh)
            try await waitForRemoteMediaCondition {
                await recorder.snapshot().receivedStates.count == 3
            }
            let final = await recorder.snapshot()
            let refreshed = try XCTUnwrap(final.receivedStates.last)
            XCTAssertEqual(refreshed.update.item, oldState.update.item)
            XCTAssertEqual(refreshed.update.revision, 2)
            XCTAssertEqual(refreshed.refreshID, refreshID)
            XCTAssertTrue(refreshed.isSameNegotiation(as: currentState))
            XCTAssertTrue(final.forwardingErrors.isEmpty)

            // Exercise relative-command duplicate handling over the real ordered data channel.
            // A later refresh is the receive-order barrier, avoiding silence-based assertions.
            for command in [WebRTCRemoteMediaCommand.nextTrack, .previousTrack] {
                let before = await recorder.snapshot()
                let acknowledgementsBefore = await viewer
                    .remoteMediaAcknowledgementsReceivedForTesting
                let id = try await viewer.requestRemoteMediaCommand(
                    command, state: refreshed, authorization: WebRTCControlAuthorization()
                )
                try await waitForRemoteMediaCondition {
                    await recorder.snapshot().commands.count == before.commands.count + 1
                }
                let delivered = await recorder.snapshot()
                let received = try XCTUnwrap(delivered.receivedCommands.last)
                XCTAssertEqual(received.request.id, id)
                XCTAssertEqual(received.request.command, command)
                try await host.acknowledgeRemoteMediaCommand(received, result: .applied)
                try await waitForRemoteMediaCondition {
                    await recorder.snapshot().acknowledgements.count
                        == before.acknowledgements.count + 1
                }
                try await viewer.sendRemoteMediaCommandForTesting(received.request, state: refreshed)
                let conflict = WebRTCRemoteMediaCommandRequest(
                    id: id, contextID: item.contextID, observedRevision: 2,
                    command: command == .nextTrack ? .previousTrack : .nextTrack
                )
                try await viewer.sendRemoteMediaCommandForTesting(conflict, state: refreshed)
                try await viewer.requestRemoteMediaStateRefresh(id: UUID())
                try await waitForRemoteMediaCondition {
                    let snapshot = await recorder.snapshot()
                    let acknowledgementCount = await viewer
                        .remoteMediaAcknowledgementsReceivedForTesting
                    return snapshot.refreshRequests.count == before.refreshRequests.count + 1
                        && acknowledgementCount == acknowledgementsBefore + 2
                }
                let replayed = await recorder.snapshot()
                XCTAssertEqual(replayed.commands.count, before.commands.count + 1)
                XCTAssertEqual(replayed.acknowledgements.count, before.acknowledgements.count + 1)
                XCTAssertEqual(replayed.commands.last?.command, command)
                XCTAssertEqual(replayed.acknowledgements.last, .init(id: id, result: .applied))
            }
        } catch {
            hostForwarder.cancel()
            viewerForwarder.cancel()
            _ = await host.close(reason: .protocolError)
            _ = await viewer.close(reason: .protocolError)
            _ = await hostForwarder.value
            _ = await viewerForwarder.value
            throw error
        }
        hostForwarder.cancel()
        viewerForwarder.cancel()
        let hostRetired = await host.close(reason: .normal)
        let viewerRetired = await viewer.close(reason: .normal)
        _ = await hostForwarder.value
        _ = await viewerForwarder.value
        XCTAssertTrue(hostRetired)
        XCTAssertTrue(viewerRetired)
    }

    func testNativeMediaCommandGateCannotReviveBeforeActorEventsAreDrained() {
        let boundaries: [(WebRTCDelegateProxy) -> Void] = [
            { $0.receivePeerStateForTesting(.disconnected) },
            { $0.receiveICEStateForTesting(.checking) },
            { $0.receiveDataChannelStateForTesting(.closing) },
            { $0.receiveControlProtocolFailureForTesting() },
        ]
        for boundary in boundaries {
            let proxy = WebRTCDelegateProxy()
            proxy.markNativeTransportHealthyForTesting()
            let gate = WebRTCControlAuthorization()
            XCTAssertTrue(proxy.installMediaCommandAuthorization(gate))
            let command = WebRTCReceivedRemoteMediaCommand(
                envelope: .init(authorization: .init(), request: .init(
                    id: 1, contextID: "same-context", observedRevision: 1, command: .nextTrack
                )),
                executionAuthorization: gate
            )
            XCTAssertTrue(command.isValid)
            // No task drains proxy.events. Native recovery must not resurrect the prior token.
            boundary(proxy)
            proxy.markNativeTransportHealthyForTesting()
            XCTAssertFalse(command.isValid)
            XCTAssertFalse(proxy.installMediaCommandAuthorization(gate))
            let freshGate = WebRTCControlAuthorization()
            XCTAssertTrue(proxy.installMediaCommandAuthorization(freshGate))
            XCTAssertTrue(freshGate.isValid)
            XCTAssertFalse(command.isValid)
            proxy.close()
            XCTAssertFalse(freshGate.isValid)
        }
    }

    private func makeRemoteMediaFlow(automaticallyAcknowledge: Bool = false, supportsMediaHandoff: Bool = false) throws -> (
        WebRTCPeer, WebRTCPeer, RemoteMediaFlowRecorder, RemoteMediaFlowExpectations,
        Task<Void, Never>, Task<Void, Never>
    ) {
        let host = try WebRTCPeer(
            configuration: WebRTCTransportConfiguration(
                role: .host,
                iceServers: [],
                supportsRemoteMediaControls: true,
                supportsMediaHandoff: supportsMediaHandoff
            )
        )
        let viewer = try WebRTCPeer.makeHeadlessViewerForTesting(
            configuration: WebRTCTransportConfiguration(
                role: .viewer,
                iceServers: [],
                supportsRemoteMediaControls: true,
                supportsMediaHandoff: supportsMediaHandoff
            )
        )
        let recorder = RemoteMediaFlowRecorder()
        let expectations = RemoteMediaFlowExpectations()

        let hostForwarder = Task<Void, Never> {
            do {
                for await event in host.events {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .peerStateChanged(.connected):
                        if await recorder.mark(.hostConnected) {
                            expectations.fulfill(.hostConnected)
                        }
                    case .dataChannelStateChanged(.open):
                        if await recorder.mark(.hostDataChannelOpen) {
                            expectations.fulfill(.hostDataChannelOpen)
                        }
                    case .remoteMediaStateRefreshRequested(let refresh):
                        await recorder.record(refresh)
                    case .mediaHandoffCommitReceived(let commit):
                        await recorder.record(commit)
                    case .remoteMediaCommandReceived(let request):
                        if await recorder.record(request) {
                            expectations.fulfill(.commandReceived)
                        }
                        if automaticallyAcknowledge { try await host.acknowledgeRemoteMediaCommand(request, result: .applied) }
                    default:
                        break
                    }
                    if case .outboundSignal(let payload) = event {
                        try await viewer.handle(payload)
                    }
                }
            } catch {
                await recorder.recordForwardingError(error)
            }
        }
        let viewerForwarder = Task<Void, Never> {
            do {
                for await event in viewer.events {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .peerStateChanged(.connected):
                        if await recorder.mark(.viewerConnected) {
                            expectations.fulfill(.viewerConnected)
                        }
                    case .dataChannelStateChanged(.open):
                        if await recorder.mark(.viewerDataChannelOpen) {
                            expectations.fulfill(.viewerDataChannelOpen)
                        }
                    case .remoteMediaStateChanged(let update):
                        if await recorder.record(update) {
                            expectations.fulfill(.stateReceived)
                        }
                    case .mediaHandoffOfferReceived(let offer):
                        await recorder.record(offer)
                    case .mediaHandoffCompleted(let completion):
                        await recorder.record(completion)
                    case .remoteMediaCommandAcknowledgementReceived(
                        let acknowledgement
                    ):
                        if await recorder.record(acknowledgement) {
                            expectations.fulfill(.acknowledgementReceived)
                        }
                    default:
                        break
                    }
                    if case .outboundSignal(let payload) = event {
                        try await host.handle(payload)
                    }
                }
            } catch {
                await recorder.recordForwardingError(error)
            }
        }

        return (host, viewer, recorder, expectations, hostForwarder, viewerForwarder)
    }

    private func waitForRemoteMediaCondition(
        _ condition: () async -> Bool
    ) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The bounded real-peer media condition was not observed.")
        throw WebRTCTransportError.transportNotHealthy
    }
}
