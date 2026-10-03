import Foundation
import WebRTCTransport

/// Opaque native source binding. Metadata/artwork cannot manufacture this descriptor.
/// It is single-use for a later native Pause, not proof of playback on the receiving phone.
final class MacYouTubeHandoffSource: @unchecked Sendable {
    fileprivate let ownerID: UUID
    fileprivate let client: MacNowPlayingClientToken
    fileprivate let native: MacChromePlayerSnapshot
    private let lock = NSLock()
    private var consumed = false
    let deadlineUptime: Double
    var videoID: String { native.media.videoID }
    var positionSeconds: Double { native.media.elapsedTime! }
    var durationSeconds: Double { native.media.duration! }
    var playbackRate: Double { native.media.playbackRate }
    var observedAtUptime: Double { native.receivedAtUptime }

    fileprivate init?(ownerID: UUID, client: MacNowPlayingClientToken, native: MacChromePlayerSnapshot) {
        guard native.receivedAtUptime.isFinite, native.receivedAtUptime >= 0,
              let position = native.media.elapsedTime,
              MacChromeHandoffPauseCondition(source: native, phonePositionSeconds: position) != nil else { return nil }
        self.ownerID = ownerID; self.client = client; self.native = native
        deadlineUptime = native.receivedAtUptime + 30
    }

    func isFreshForOffer(now: Double) -> Bool {
        lock.withLock {
            !consumed && now.isFinite && now >= observedAtUptime && now - observedAtUptime < 2
        }
    }

    fileprivate func claim(now: Double) -> Bool {
        lock.withLock {
            guard !consumed else { return false }
            consumed = true
            return now.isFinite && now >= observedAtUptime && now < deadlineUptime
        }
    }
}

final class MacChromeNowPlayingRuntime: MacSystemNowPlayingRuntime, @unchecked Sendable {
    private let backend: any MacChromeNowPlayingBackend
    private let queue: DispatchQueue
    private let permissionQueue = DispatchQueue(label: "com.elamin.opensteamer.chrome-permission", qos: .userInitiated)
    private let now: @Sendable () -> TimeInterval
    private let lock = NSLock()
    private let handoffOwnerID = UUID()
    private var epoch: UInt64 = 0
    private var lifecycle: UInt64 = 0
    private var fetchPending = false
    private var commandPending = false
    private var permissionPending = false
    private var relativeConsumed = false
    private var confirmedSameItemSeek = false
    private var current: (player: MacChromePlayerSnapshot, token: MacNowPlayingClientToken)?
    // Selection only: an uncertain read always retires current command authority.
    private var selectionHint: MacChromePlayerSnapshot?
    private var discoveryStatus: MacChromeDiscoveryStatus = .idle
    var isAvailable: Bool { true }
    var lastDiscoveryStatus: MacChromeDiscoveryStatus { lock.withLock { discoveryStatus } }

    init(backend: any MacChromeNowPlayingBackend = MacChromeAppleEventsBackend(),
         queue: DispatchQueue = DispatchQueue(label: "com.elamin.opensteamer.chrome-events", qos: .utility),
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.backend = backend; self.queue = queue; self.now = now
    }

    func fetchSnapshot(completion: @escaping @Sendable (MacNowPlayingRuntimeSnapshotResult) -> Void) {
        let admitted = lock.withLock { () -> UInt64? in
            guard !fetchPending else { return nil }
            fetchPending = true
            return epoch
        }
        guard let admitted else { completion(.retry); return }
        let deadline = now() + 1.5
        queue.async { [self] in
            let preferred = lock.withLock { selectionHint }
            var read: MacChromeSelectionRead = .incomplete(.timedOut, holding: preferred)
            if lock.withLock({ epoch == admitted }), now() < deadline {
                read = backend.readSelection(preferred: preferred, deadline: deadline)
                if now() >= deadline {
                    switch read {
                    case .selected(let player): read = .incomplete(.timedOut, holding: player)
                    case .noPlayer: read = .incomplete(.timedOut, holding: nil)
                    case .incomplete(_, let holding): read = .incomplete(.timedOut, holding: holding)
                    }
                }
            }
            let result: MacNowPlayingRuntimeSnapshotResult = lock.withLock {
                fetchPending = false
                guard epoch == admitted else { return .retry }
                let selected: MacChromePlayerSnapshot?
                switch read {
                case .selected(let player): selected = player
                case .noPlayer: selected = nil
                case .incomplete(let failure, let holding):
                    epoch &+= 1; current = nil; relativeConsumed = false; confirmedSameItemSeek = false
                    selectionHint = holding
                    discoveryStatus = MacChromeDiscoveryStatus(error: failure)
                    // Uncertain selected ownership survives only as a hold, never authority.
                    return .retry
                }
                guard let selected else {
                    epoch &+= 1; current = nil; selectionHint = nil; relativeConsumed = false; confirmedSameItemSeek = false
                    discoveryStatus = .noPlayer
                    return .noActiveMedia
                }
                guard let metadata = Self.metadata(selected) else {
                    epoch &+= 1; current = nil; selectionHint = selected; relativeConsumed = false; confirmedSameItemSeek = false
                    discoveryStatus = .invalidData
                    return .retry
                }
                let token: MacNowPlayingClientToken
                if let current, current.player.hasSameItem(as: selected),
                   !relativeConsumed || commandPending || confirmedSameItemSeek {
                    token = current.token
                } else {
                    epoch &+= 1
                    token = MacNowPlayingClientToken(object: NSObject(), clientIdentity: "chrome:" + UUID().uuidString)
                }
                if !commandPending || current?.player.hasSameItem(as: selected) != true {
                    relativeConsumed = false
                    confirmedSameItemSeek = false
                }
                current = (selected, token); selectionHint = selected; discoveryStatus = .available
                return .snapshot(.init(client: token, sourceName: "YouTube", metadata: metadata,
                    enabledCommands: selected.media.enabledCommands,
                    handoffSource: MacYouTubeHandoffSource(ownerID: handoffOwnerID, client: token, native: selected)))
            }
            completion(result)
        }
    }

    /// Explicit host onboarding only; ordinary polling never requests consent.
    func requestAutomationPermission(completion: @escaping @Sendable (Bool) -> Void) {
        let admitted = lock.withLock { () -> UInt64? in
            guard !permissionPending else { return nil }
            permissionPending = true
            return lifecycle
        }
        guard let admitted else { completion(false); return }
        permissionQueue.async { [self] in
            var success = false
            if lock.withLock({ lifecycle == admitted }) {
                do { try backend.requestAutomationPermission(); success = true } catch {}
            }
            let accepted = lock.withLock {
                permissionPending = false
                return success && lifecycle == admitted
            }
            completion(accepted)
        }
    }

    func send(rawCommand: Int, snapshot: MacNowPlayingRuntimeSnapshot,
              isAuthorized: @escaping @Sendable () -> Bool,
              completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        send(rawCommand: rawCommand, positionSeconds: nil, snapshot: snapshot,
             isAuthorized: isAuthorized, completion: completion)
    }

    func send(rawCommand: Int, positionSeconds: TimeInterval?, snapshot: MacNowPlayingRuntimeSnapshot,
              isAuthorized: @escaping @Sendable () -> Bool,
              completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        guard let command = MacChromeCommand(rawValue: rawCommand),
              command.accepts(positionSeconds: positionSeconds),
              snapshot.enabledCommands.contains(rawCommand) else { completion(.unsupported); return }
        guard isAuthorized() else { completion(.staleContext); return }
        let admission = lock.withLock { () -> (MacChromePlayerSnapshot, UInt64)? in
            guard !commandPending, !relativeConsumed, let current, current.token === snapshot.client,
                  Self.metadata(current.player)?.identityComponent == snapshot.metadata.identityComponent else { return nil }
            commandPending = true
            if command.isRelative { relativeConsumed = true; confirmedSameItemSeek = false }
            return (current.player, epoch)
        }
        guard let (expected, admitted) = admission else { completion(.staleContext); return }
        let deadline = min(now() + 1.5, expected.receivedAtUptime + MacChromeAppleEventsBackend.maximumSnapshotAge)
        let authorized: @Sendable () -> Bool = { [weak self] in
            guard let self, isAuthorized() else { return false }
            return self.lock.withLock {
                self.epoch == admitted && self.current?.token === snapshot.client
                    && self.current?.player.hasSameItem(as: expected) == true
            }
        }
        queue.async { [self] in
            let result: WebRTCRemoteMediaCommandResult
            var retiredItem = false
            if !authorized() || now() >= deadline { result = .staleContext }
            else {
                do { result = try backend.send(command, positionSeconds: positionSeconds,
                                               expected: expected, deadline: deadline, isAuthorized: authorized) }
                catch {
                    retiredItem = error as? MacChromeBackendError == .retiredItem
                    result = retiredItem || error as? MacChromeBackendError == .staleItem ? .staleContext : .failed
                }
            }
            let confirmedSeek = command.isSeek && result == .applied && authorized()
            lock.withLock {
                if epoch == admitted, current?.token === snapshot.client {
                    // Fresh same-item readback may preserve selection after a confirmed seek.
                    // Ambiguous relative results still consume and rotate the old authority.
                    confirmedSameItemSeek = confirmedSeek
                    if result == .failed || result == .staleContext || result == .noActiveMedia {
                        // Unknown command/readback outcomes revoke even absolute Play/Pause.
                        // Only a fresh exact-owner read may create replacement authority.
                        epoch &+= 1; current = nil; relativeConsumed = false; confirmedSameItemSeek = false
                        if retiredItem || result == .noActiveMedia { selectionHint = nil }
                    }
                }
                commandPending = false
            }
            completion(result)
        }
    }

    func stop() {
        lock.withLock {
            epoch &+= 1; lifecycle &+= 1; current = nil; selectionHint = nil; relativeConsumed = false
            confirmedSameItemSeek = false; discoveryStatus = .idle
        }
    }

    func sendHandoffPause(source: MacYouTubeHandoffSource, phonePositionSeconds: Double,
                          snapshot: MacNowPlayingRuntimeSnapshot,
                          isAuthorized: @escaping @Sendable () -> Bool,
                          completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        guard source.ownerID == handoffOwnerID, source.client === snapshot.client,
              isAuthorized(), let condition = MacChromeHandoffPauseCondition(
                source: source.native, phonePositionSeconds: phonePositionSeconds) else {
            completion(.staleContext); return
        }
        let admission = lock.withLock { () -> (MacChromePlayerSnapshot, UInt64)? in
            guard !commandPending, !relativeConsumed, let current,
                  current.token === source.client, current.player.hasSameItem(as: source.native),
                  condition.matches(current.player.media), source.claim(now: now()) else { return nil }
            commandPending = true
            return (current.player, epoch)
        }
        guard let (expected, admitted) = admission else { completion(.staleContext); return }
        let deadline = min(source.deadlineUptime, now() + 1.5,
                           expected.receivedAtUptime + MacChromeAppleEventsBackend.maximumSnapshotAge)
        let authorized: @Sendable () -> Bool = { [weak self] in
            guard let self, isAuthorized(), self.now() < deadline else { return false }
            return self.lock.withLock {
                self.epoch == admitted && self.current?.token === source.client
                    && self.current?.player.hasSameItem(as: source.native) == true
            }
        }
        queue.async { [self] in
            var result: WebRTCRemoteMediaCommandResult = .staleContext
            if authorized() {
                do { result = try backend.sendHandoffPause(expected: expected, condition: condition,
                    deadline: deadline, isAuthorized: authorized) }
                catch { result = .failed }
            }
            lock.withLock {
                if epoch == admitted, current?.token === source.client,
                   result == .failed || result == .staleContext || result == .noActiveMedia {
                    epoch &+= 1; current = nil; relativeConsumed = false; confirmedSameItemSeek = false
                }
                commandPending = false
            }
            completion(result)
        }
    }

    static func metadata(_ snapshot: MacChromePlayerSnapshot) -> MacNowPlayingMetadata? {
        let media = snapshot.media
        guard snapshot.tab.owner.processID > 0, snapshot.tab.owner.launchDate.timeIntervalSince1970.isFinite,
              UUID(uuidString: media.documentID) != nil, UUID(uuidString: media.itemID) != nil,
              media.itemGeneration > 0, media.itemGeneration <= 9_007_199_254_740_991,
              media.playbackRate.isFinite, (0...16).contains(media.playbackRate),
              MacChromeAppleEventsBackend.videoID(from: "https://www.youtube.com/watch?v=" + media.videoID) == media.videoID,
              media.observedAtUnixMilliseconds.isFinite,
              let title = boundedText(media.title, maximum: WebRTCRemoteMediaItem.maximumTitleBytes) else { return nil }
        let duration = validTime(media.duration).flatMap { $0 > 0 ? $0 : nil }
        let elapsed = validTime(media.elapsedTime).map { min($0, duration ?? $0) }
        return .init(title: title, artist: boundedText(media.artist, maximum: WebRTCRemoteMediaItem.maximumArtistBytes),
                     album: nil, duration: duration, elapsedTime: elapsed,
                     playbackRate: media.paused ? 0 : media.playbackRate,
                     timestamp: Date(timeIntervalSince1970: media.observedAtUnixMilliseconds / 1000),
                     contentIdentifier: media.itemID + ":" + String(media.itemGeneration),
                     uniqueIdentifier: nil,
                     artwork: WebRTCRemoteMediaArtworkReference(videoID: media.videoID))
    }

    private static func boundedText(_ value: String?, maximum: Int) -> String? {
        guard let value, value.utf8.count <= 8_192 else { return nil }
        let clean = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        var result = ""
        for character in String(String.UnicodeScalarView(clean)).trimmingCharacters(in: .whitespacesAndNewlines) {
            guard result.utf8.count + character.utf8.count <= maximum else { break }
            result.append(character)
        }
        return result.isEmpty ? nil : result
    }

    private static func validTime(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 31_536_000 else { return nil }
        return value
    }
}
