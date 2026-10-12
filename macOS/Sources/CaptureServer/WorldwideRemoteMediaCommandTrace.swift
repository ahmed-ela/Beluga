import Foundation
import WebRTCTransport

enum WorldwideRemoteMediaCommandTrace {
    enum Stage: String, CaseIterable {
        case serviceReceived, capacityRejected, executionRetired, resultResolved
        case acknowledgementRetired, acknowledgementSent, acknowledgementFailed, queueCancelled
    }

    static func message(
        stage: Stage,
        session: UUID,
        processID: Int32,
        peerGeneration: UInt64,
        request: WebRTCRemoteMediaCommandRequest,
        publishedRevision: UInt64?,
        contextMatches: Bool,
        authorized: Bool,
        transportReady: Bool,
        result: WebRTCRemoteMediaCommandResult?,
        uptime: TimeInterval
    ) -> String {
        // Never log item metadata, opaque context IDs, signaling, or pairing material.
        "remote-media-command stage=\(stage.rawValue) session=\(session.uuidString.lowercased()) "
            + "pid=\(processID) peer=\(peerGeneration) id=\(request.id) command=\(request.command.rawValue) "
            + "observedRevision=\(request.observedRevision) publishedRevision=\(publishedRevision ?? 0) "
            + "contextMatches=\(contextMatches) authorized=\(authorized) transportReady=\(transportReady) "
            + "result=\(result?.rawValue ?? "none") uptime=\(uptime)"
    }
}

/// A semantic diagnostic signature, not publication or command authority. Opaque item
/// identities are retained only for change detection and never appear in a message.
struct RemoteMediaStateTraceSummary: Equatable, Sendable {
    private let identities: [String]
    let itemCount: Int
    let playingMask: UInt8

    private init(identities: [String], playing: [Bool]) {
        self.identities = Array(identities.prefix(2))
        itemCount = self.identities.count
        playingMask = playing.prefix(2).enumerated().reduce(0) {
            $1.element ? $0 | (UInt8(1) << $1.offset) : $0
        }
    }

    init(item: WebRTCRemoteMediaItem?, additionalItems: [WebRTCRemoteMediaItem] = []) {
        let items = item.map { [$0] + additionalItems } ?? []
        self.init(identities: items.map(\.contextID),
                  playing: items.map { $0.playbackState == .playing })
    }

    init(result: MacNowPlayingRuntimeCatalogResult) {
        if case .snapshot(let catalog) = result {
            let snapshots = [catalog.primary] + catalog.additional
            self.init(identities: snapshots.map(\.identityKey),
                      playing: snapshots.map { $0.metadata.playbackRate > 0 })
        } else {
            self.init(identities: [], playing: [])
        }
    }
}

enum RemoteMediaStateTrace {
    enum Stage: String, CaseIterable, Hashable, Sendable {
        case observerAccepted, observerRejected, observerTimedOut, controllerPublished
        case serviceDesired, serviceRejected, nativeSent, nativeRetired, nativeFailed

        var summaryScope: String {
            switch self {
            case .observerAccepted, .observerRejected, .observerTimedOut: "runtimeResult"
            case .controllerPublished: "controller"
            case .serviceDesired: "desired"
            case .serviceRejected: "received"
            // sendRemoteMediaState may project a catalog for a primary-only peer.
            // This diagnostic observes the attempt, not the encoded wire projection.
            case .nativeSent, .nativeRetired, .nativeFailed: "attempt"
            }
        }
    }

    enum Reason: String, Equatable, Sendable {
        case snapshot, empty, retry, watchdog, supersededRefresh, retiredLifecycle
        case state, invalidState, staleRevision, sendFailed, peerRetired
    }

    struct Gate: Sendable {
        private struct Entry: Sendable {
            let epoch: UInt64
            let summary: RemoteMediaStateTraceSummary
            let failure: Bool
            let uptime: TimeInterval
        }
        private var last: [Stage: Entry] = [:]

        mutating func shouldReport(stage: Stage, summary: RemoteMediaStateTraceSummary,
                                   epoch: UInt64, failure: Bool = false,
                                   uptime: TimeInterval) -> Bool {
            guard uptime.isFinite, uptime >= 0 else { return false }
            let previous = last[stage]
            let changed = previous?.epoch != epoch || previous?.summary != summary
                || previous?.failure != failure
            // Successful position/metadata ticks are silent. Repeated failures are
            // bounded even when each rejected callback contains a different item.
            if failure, let previous, previous.epoch == epoch, previous.failure {
                guard uptime - previous.uptime >= 15 else { return false }
            } else if !changed {
                return false
            }
            last[stage] = Entry(epoch: epoch, summary: summary, failure: failure, uptime: uptime)
            return true
        }
    }

    static func message(stage: Stage, session: UUID, processID: Int32,
                        generation: UInt64 = 0, peerGeneration: UInt64 = 0,
                        refreshID: UInt64 = 0, activeRefreshID: UInt64 = 0,
                        controllerRevision: UInt64, wireRevision: UInt64 = 0,
                        lastSuccessfullySentRevision: UInt64 = 0,
                        summary: RemoteMediaStateTraceSummary, reason: Reason,
                        uptime: TimeInterval) -> String {
        "remote-media-state stage=\(stage.rawValue) trace=\(session.uuidString.lowercased()) "
            + "pid=\(processID) generation=\(generation) peer=\(peerGeneration) "
            + "refresh=\(refreshID) activeRefresh=\(activeRefreshID) "
            + "controllerRevision=\(controllerRevision) wireRevision=\(wireRevision) "
            + "lastSentRevision=\(lastSuccessfullySentRevision) summaryScope=\(stage.summaryScope) "
            + "itemCount=\(summary.itemCount) "
            + "playingMask=\(summary.playingMask) reason=\(reason.rawValue) uptime=\(uptime)"
    }
}
