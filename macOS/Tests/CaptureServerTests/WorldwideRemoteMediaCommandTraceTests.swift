import Foundation
import WebRTCTransport
import XCTest
@testable import CaptureServer

final class WorldwideRemoteMediaCommandTraceTests: XCTestCase {
    func testTraceCorrelatesBoundariesWithoutOpaqueContextOrMediaMetadata() {
        let session = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let request = WebRTCRemoteMediaCommandRequest(id: 7,
            contextID: "PRIVATE-CONTEXT\ninjected=true", observedRevision: 11, command: .play)
        for stage in WorldwideRemoteMediaCommandTrace.Stage.allCases {
            let message = WorldwideRemoteMediaCommandTrace.message(stage: stage, session: session,
                processID: 42, peerGeneration: 3, request: request, publishedRevision: 12,
                contextMatches: false, authorized: false, transportReady: true,
                result: .staleContext, uptime: 123.5)
            XCTAssertEqual(message, "remote-media-command stage=\(stage.rawValue) "
                + "session=11111111-1111-1111-1111-111111111111 pid=42 peer=3 id=7 command=play "
                + "observedRevision=11 publishedRevision=12 contextMatches=false authorized=false "
                + "transportReady=true result=staleContext uptime=123.5")
            XCTAssertFalse(message.contains(request.contextID))
            XCTAssertFalse(message.contains("\n"))
        }
    }

    func testReceiveTraceDoesNotImplyExecutionOrAcknowledgement() {
        let message = WorldwideRemoteMediaCommandTrace.message(stage: .serviceReceived, session: UUID(),
            processID: 42, peerGeneration: 3,
            request: .init(id: 1, contextID: "private", observedRevision: 2, command: .pause),
            publishedRevision: nil, contextMatches: true, authorized: true,
            transportReady: false, result: nil, uptime: 1)
        XCTAssertTrue(message.contains("stage=serviceReceived"))
        XCTAssertTrue(message.contains("publishedRevision=0"))
        XCTAssertTrue(message.contains("result=none"))
        XCTAssertTrue(message.contains("transportReady=false"))
    }
}

final class RemoteMediaStateTraceTests: XCTestCase {
    func testStateTraceMasksOrderedCatalogAndNeverIncludesLibraryIdentitiesOrMetadata() {
        let item = Self.item(context: "PRIVATE-CONTEXT\ninjected=true", title: "PRIVATE-TITLE",
                             playing: false)
        let other = Self.item(context: "PRIVATE-OTHER", title: "https://private.invalid/watch",
                              playing: true)
        let summary = RemoteMediaStateTraceSummary(item: item, additionalItems: [other])
        XCTAssertEqual(summary.itemCount, 2)
        XCTAssertEqual(summary.playingMask, 2)
        for stage in RemoteMediaStateTrace.Stage.allCases {
            let message = RemoteMediaStateTrace.message(stage: stage,
                session: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                processID: 42, generation: 2, peerGeneration: 3, refreshID: 4,
                activeRefreshID: 4, controllerRevision: 5, wireRevision: 6,
                lastSuccessfullySentRevision: 6, summary: summary, reason: .state, uptime: 123.5)
            XCTAssertTrue(message.contains("controllerRevision=5 wireRevision=6 lastSentRevision=6"))
            XCTAssertTrue(message.contains("itemCount=2 playingMask=2 reason=state uptime=123.5"))
            XCTAssertFalse(message.contains("PRIVATE"))
            XCTAssertFalse(message.contains("https://"))
            XCTAssertFalse(message.contains("\n"))
        }
        XCTAssertEqual(RemoteMediaStateTraceSummary(item: nil).itemCount, 0)
        XCTAssertEqual(RemoteMediaStateTraceSummary(item: nil).playingMask, 0)
    }

    func testSemanticGateSilencesPositionAndMetadataButReportsPauseOwnerAndPeerChanges() {
        var gate = RemoteMediaStateTrace.Gate()
        let playing = RemoteMediaStateTraceSummary(item: Self.item(context: "a", playing: true))
        let metadataOnly = RemoteMediaStateTraceSummary(item:
            Self.item(context: "a", title: "changed private metadata", playing: true, position: 50))
        let paused = RemoteMediaStateTraceSummary(item: Self.item(context: "a", playing: false))
        let newOwner = RemoteMediaStateTraceSummary(item: Self.item(context: "b", playing: false))
        XCTAssertTrue(gate.shouldReport(stage: .nativeSent, summary: playing, epoch: 1, uptime: 1))
        XCTAssertFalse(gate.shouldReport(stage: .nativeSent, summary: metadataOnly, epoch: 1, uptime: 2))
        XCTAssertTrue(gate.shouldReport(stage: .nativeSent, summary: paused, epoch: 1, uptime: 3))
        XCTAssertFalse(gate.shouldReport(stage: .nativeSent, summary: paused, epoch: 1, uptime: 99))
        XCTAssertTrue(gate.shouldReport(stage: .nativeSent, summary: newOwner, epoch: 1, uptime: 100))
        XCTAssertTrue(gate.shouldReport(stage: .nativeSent, summary: newOwner, epoch: 2, uptime: 101))
    }

    func testFailuresAreBoundedEvenWhenRejectedSamplesChangeAndSuccessStagesAreIndependent() {
        var gate = RemoteMediaStateTrace.Gate()
        let first = RemoteMediaStateTraceSummary(item: Self.item(context: "a", playing: true))
        let changed = RemoteMediaStateTraceSummary(item: Self.item(context: "b", playing: false))
        XCTAssertTrue(gate.shouldReport(stage: .observerRejected, summary: first, epoch: 1,
                                       failure: true, uptime: 10))
        XCTAssertFalse(gate.shouldReport(stage: .observerRejected, summary: changed, epoch: 1,
                                        failure: true, uptime: 24.999))
        XCTAssertTrue(gate.shouldReport(stage: .observerRejected, summary: changed, epoch: 1,
                                       failure: true, uptime: 25))
        XCTAssertTrue(gate.shouldReport(stage: .observerAccepted, summary: changed, epoch: 1, uptime: 25))
        XCTAssertTrue(gate.shouldReport(stage: .controllerPublished, summary: changed, epoch: 1, uptime: 25))
        XCTAssertFalse(gate.shouldReport(stage: .nativeSent, summary: changed, epoch: 1, uptime: .nan))
    }

    func testNativeSuccessTraceUsesTheSentAttemptRatherThanNewerDesiredState() throws {
        var publication = WorldwideRemoteMediaPublicationMachine()
        publication.setRemoteMediaAvailable(true)
        publication.applyControllerUpdate(.init(revision: 10, item: Self.item(context: "a", playing: true)))
        let playingAttempt = try XCTUnwrap(publication.beginIfPossible(transportIsReady: true))
        let capturedControllerRevision = try XCTUnwrap(publication.desiredControllerRevision)
        publication.applyControllerUpdate(.init(revision: 11, item: Self.item(context: "a", playing: false)))
        XCTAssertEqual(publication.complete(playingAttempt, succeeded: true), .publishNewest)
        let message = RemoteMediaStateTrace.message(stage: .nativeSent, session: UUID(), processID: 42,
            peerGeneration: 1, controllerRevision: capturedControllerRevision,
            wireRevision: playingAttempt.update.revision,
            lastSuccessfullySentRevision: publication.lastSuccessfullySent?.revision ?? 0,
            summary: .init(item: playingAttempt.update.item), reason: .state, uptime: 1)
        XCTAssertTrue(message.contains("controllerRevision=10 wireRevision=1 lastSentRevision=1"))
        XCTAssertTrue(message.contains("itemCount=1 playingMask=1"))
        XCTAssertEqual(publication.desiredItem?.playbackState, .paused)
    }

    func testNativeCatalogCountsAreExplicitlyAttemptScopedForPrimaryOnlyPeers() {
        let primary = Self.item(context: "private-primary", playing: false)
        let additional = Self.item(context: "private-additional", playing: true)
        let attempt = WebRTCRemoteMediaStateUpdate(revision: 12, item: primary, additionalItems: [additional])
        // This is the peer's legacy projection; the service must not label its
        // two-item attempted catalog as this effective one-item wire payload.
        let legacyProjection = WebRTCRemoteMediaStateUpdate(revision: 12, item: primary)
        XCTAssertEqual(legacyProjection.allItems.count, 1)
        for stage in [RemoteMediaStateTrace.Stage.nativeSent, .nativeRetired, .nativeFailed] {
            let message = RemoteMediaStateTrace.message(stage: stage, session: UUID(), processID: 42,
                peerGeneration: 1, controllerRevision: 10, wireRevision: attempt.revision,
                summary: .init(item: attempt.item, additionalItems: attempt.additionalItems),
                reason: .state, uptime: 1)
            XCTAssertTrue(message.contains("summaryScope=attempt itemCount=2 playingMask=2"))
            XCTAssertFalse(message.contains("summaryScope=wire"))
        }
        XCTAssertEqual(RemoteMediaStateTrace.Stage.serviceDesired.summaryScope, "desired")
    }

    func testRetiredNativeTraceRetainsSourcePeerAndPriorRevisionInsteadOfReplacementPublication() {
        var currentPeerGeneration: UInt64 = 1
        var publication = WorldwideRemoteMediaPublicationMachine()
        publication.setRemoteMediaAvailable(true)
        publication.applyControllerUpdate(.init(revision: 10, item: Self.item(context: "a", playing: true)))
        let sent = publication.beginIfPossible(transportIsReady: true)!
        XCTAssertEqual(publication.complete(sent, succeeded: true), .finished)
        let traceSourcePeerGeneration = currentPeerGeneration
        let tracePriorLastSentRevision = publication.lastSuccessfullySent?.revision ?? 0
        // A peer replacement can happen across the availability actor await.
        currentPeerGeneration = 2
        publication.startNewPeer()
        let lastSent = traceSourcePeerGeneration == currentPeerGeneration
            ? publication.lastSuccessfullySent?.revision ?? 0 : tracePriorLastSentRevision
        let message = RemoteMediaStateTrace.message(stage: .nativeRetired, session: UUID(), processID: 42,
            peerGeneration: traceSourcePeerGeneration, controllerRevision: 10, wireRevision: sent.update.revision,
            lastSuccessfullySentRevision: lastSent, summary: .init(item: sent.update.item),
            reason: .peerRetired, uptime: 1)
        XCTAssertTrue(message.contains("peer=1"))
        XCTAssertTrue(message.contains("lastSentRevision=1 summaryScope=attempt"))
        XCTAssertNil(publication.lastSuccessfullySent)
    }

    private static func item(context: String, title: String = "Private title", playing: Bool,
                             position: TimeInterval = 10) -> WebRTCRemoteMediaItem {
        .init(contextID: context, sourceName: "Private source", title: title,
              playbackState: playing ? .playing : .paused, elapsedTime: position, duration: 120,
              playbackRate: playing ? 1 : 0,
              capabilities: .init(canPlay: !playing, canPause: playing,
                                  canSkipForward: true, canSkipBackward: true))
    }
}
