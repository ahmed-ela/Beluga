@preconcurrency import AppKit
import CoreServices
import WebRTCTransport

struct MacChromePlayerIdentity: Equatable, Hashable, Sendable {
    let processID: Int32
    let launchDate: Date
}

struct MacChromeTabIdentity: Equatable, Hashable, Sendable {
    let owner: MacChromePlayerIdentity
    let windowID: String
    let tabID: String
}

struct MacChromeMediaIdentity: Codable, Equatable, Sendable {
    let documentID: String
    let itemID: String
    let itemGeneration: Int64
}

struct MacChromeScriptSnapshot: Codable, Equatable, Sendable {
    let documentID: String
    let itemID: String
    let itemGeneration: Int64
    let videoID: String
    let title: String
    let artist: String?
    let duration: Double?
    let elapsedTime: Double?
    let playbackRate: Double
    let paused: Bool
    let observedAtUnixMilliseconds: Double
    let observedAtPageMilliseconds: Double
    let canPlay: Bool
    let canPause: Bool
    let canNext: Bool
    let canPrevious: Bool
    var canSeek: Bool? = nil

    var identity: MacChromeMediaIdentity {
        .init(documentID: documentID, itemID: itemID, itemGeneration: itemGeneration)
    }

    var enabledCommands: Set<Int> {
        var commands = Set<Int>()
        if canPlay && paused { commands.insert(0) }
        if canPause && !paused { commands.insert(1) }
        if canNext { commands.insert(4) }
        if canPrevious { commands.insert(5) }
        if canSeek == true, let duration, let elapsedTime,
           duration.isFinite, duration > 0, duration <= 31_536_000,
           elapsedTime.isFinite, (0...duration).contains(elapsedTime) {
            commands.formUnion([6, 7, MacChromeCommand.seekToPosition.rawValue])
        }
        return commands
    }
}

struct MacChromePlayerSnapshot: Sendable {
    let tab: MacChromeTabIdentity
    let media: MacChromeScriptSnapshot
    let receivedAtUptime: TimeInterval

    func hasSameItem(as other: Self) -> Bool {
        tab == other.tab && media.identity == other.media.identity && media.videoID == other.media.videoID
    }
}

enum MacChromeBackendError: Error, Equatable {
    case permissionRequired, permissionDenied, javascriptPermissionRequired, timedOut
    case staleItem, retiredItem, invalidData, unavailable, ambiguousPlayers
}

enum MacChromeDiscoveryStatus: String, Sendable {
    case idle, available, noPlayer, ambiguousPlayers, permissionRequired, permissionDenied
    case javascriptPermissionRequired, timedOut, staleItem, invalidData, unavailable

    init(error: Error) {
        guard let error = error as? MacChromeBackendError else { self = .unavailable; return }
        switch error {
        case .permissionRequired: self = .permissionRequired
        case .permissionDenied: self = .permissionDenied
        case .javascriptPermissionRequired: self = .javascriptPermissionRequired
        case .timedOut: self = .timedOut
        case .staleItem, .retiredItem: self = .staleItem
        case .invalidData: self = .invalidData
        case .unavailable: self = .unavailable
        case .ambiguousPlayers: self = .ambiguousPlayers
        }
    }
}

enum MacChromeCommand: Int, Sendable {
    case play = 0, pause = 1, next = 4, previous = 5
    case seekForward30 = 6, seekBackward30 = 7
    case seekToPosition = 10_000
    var changesTrack: Bool { self == .next || self == .previous }
    var isSeek: Bool { self == .seekForward30 || self == .seekBackward30 || self == .seekToPosition }
    var isRelative: Bool { changesTrack || isSeek }
    func accepts(positionSeconds: TimeInterval?) -> Bool {
        (self == .seekToPosition ? WebRTCRemoteMediaCommand.seekToPosition : .play)
            .accepts(positionSeconds: positionSeconds)
    }
    var scriptName: String {
        switch self {
        case .play: return "play"
        case .pause: return "pause"
        case .next: return "next"
        case .previous: return "previous"
        case .seekForward30: return "seekForward30"
        case .seekBackward30: return "seekBackward30"
        case .seekToPosition: return "seekToPosition"
        }
    }
}

enum MacChromeSelectionRead: Sendable {
    case selected(MacChromePlayerSnapshot)
    case noPlayer
    // A hint is an ownership hold, never command authority or cached metadata.
    case incomplete(MacChromeBackendError, holding: MacChromePlayerSnapshot?)
}

protocol MacChromeNowPlayingBackend: Sendable {
    func readSnapshots(deadline: TimeInterval) throws -> [MacChromePlayerSnapshot]
    func readSelection(preferred: MacChromePlayerSnapshot?, deadline: TimeInterval) -> MacChromeSelectionRead
    func requestAutomationPermission() throws
    func send(_ command: MacChromeCommand, positionSeconds: TimeInterval?, expected: MacChromePlayerSnapshot,
              deadline: TimeInterval, isAuthorized: @escaping @Sendable () -> Bool) throws
        -> WebRTCRemoteMediaCommandResult
}

extension MacChromeNowPlayingBackend {
    func readSelection(preferred: MacChromePlayerSnapshot?, deadline: TimeInterval) -> MacChromeSelectionRead {
        var holding = preferred
        do {
            let snapshots = try readSnapshots(deadline: deadline)
            holding = preferred.flatMap { old in snapshots.first { $0.hasSameItem(as: old) } }
            if let selected = try MacChromeAppleEventsBackend.select(snapshots, preferred: holding) {
                return .selected(selected)
            }
            return .noPlayer
        } catch {
            return .incomplete(error as? MacChromeBackendError ?? .unavailable, holding: holding)
        }
    }
}

protocol MacChromeAppleEventsClient: Sendable {
    func runningOwner() -> MacChromePlayerIdentity?
    func automationPermission(owner: MacChromePlayerIdentity, askUser: Bool) -> OSStatus
    func sendEvent(_ event: NSAppleEventDescriptor, options: NSAppleEventDescriptor.SendOptions,
                   timeout: TimeInterval) throws -> NSAppleEventDescriptor
}

private struct MacChromeSystemAppleEventsClient: MacChromeAppleEventsClient {
    func runningOwner() -> MacChromePlayerIdentity? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
            .filter { !$0.isTerminated && $0.bundleURL?.path == "/Applications/Google Chrome.app" }
        guard apps.count == 1, let app = apps.first, app.processIdentifier > 0,
              let launchDate = app.launchDate else { return nil }
        return .init(processID: app.processIdentifier, launchDate: launchDate)
    }

    func automationPermission(owner: MacChromePlayerIdentity, askUser: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(processIdentifier: owner.processID)
        guard let address = target.aeDesc else { return OSStatus(errAEWrongDataType) }
        return AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, askUser)
    }

    func sendEvent(_ event: NSAppleEventDescriptor, options: NSAppleEventDescriptor.SendOptions,
                   timeout: TimeInterval) throws -> NSAppleEventDescriptor {
        try event.sendEvent(options: options, timeout: timeout)
    }
}

/// Ordinary public Chrome Apple Events only; it neither launches nor activates a browser.
final class MacChromeAppleEventsBackend: MacChromeNowPlayingBackend, @unchecked Sendable {
    static let sendOptions = NSAppleEventDescriptor.SendOptions(rawValue:
        UInt(kAEWaitReply | kAENeverInteract | kAEDontRecord | kAEDoNotPromptForUserConsent))
    static let maximumSnapshotAge: TimeInterval = 3
    private let client: any MacChromeAppleEventsClient
    private let now: @Sendable () -> TimeInterval
    private let wallNow: @Sendable () -> TimeInterval
    private let cursorLock = NSLock()
    private var nextDiscoveryTab: MacChromeTabIdentity?

    init(client: any MacChromeAppleEventsClient = MacChromeSystemAppleEventsClient(),
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wallNow: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.client = client; self.now = now; self.wallNow = wallNow
    }

    func requestAutomationPermission() throws {
        guard let owner = client.runningOwner() else { throw MacChromeBackendError.unavailable }
        try Self.checkStatus(client.automationPermission(owner: owner, askUser: true))
        guard client.runningOwner() == owner else { throw MacChromeBackendError.staleItem }
    }

    private func inventory(owner: MacChromePlayerIdentity, deadline: TimeInterval)
        throws -> [(MacChromeTabIdentity, String)] {
        try check(owner: owner, deadline: deadline)
        try Self.checkStatus(client.automationPermission(owner: owner, askUser: false))
        let windows = try identifiers(get(property(0x49442020, of: all(0x6377696E)),
                                          owner: owner, deadline: deadline), maximum: 32)
        var tabCount = 0
        var candidates: [(MacChromeTabIdentity, String)] = []
        for windowID in windows {
            let window = try byID(0x6377696E, id: windowID)
            guard try boundedText(get(property(0x6D6F6465, of: window), owner: owner,
                                       deadline: deadline)) == "normal" else { continue }
            let tabs = try all(0x43725462, in: window)
            let tabIDs = try identifiers(get(property(0x49442020, of: tabs), owner: owner,
                                             deadline: deadline), maximum: 512)
            tabCount += tabIDs.count
            guard tabCount <= 512 else { throw MacChromeBackendError.invalidData }
            let urls = try list(get(property(0x55524C20, of: tabs), owner: owner,
                                    deadline: deadline), maximum: 512).map { try boundedText($0) }
            guard urls.count == tabIDs.count else { throw MacChromeBackendError.staleItem }
            for (tabID, url) in zip(tabIDs, urls) where Self.videoID(from: url) != nil {
                candidates.append((.init(owner: owner, windowID: windowID, tabID: tabID), url))
            }
        }
        guard Set(candidates.map(\.0)).count == candidates.count else { throw MacChromeBackendError.invalidData }
        return candidates
    }

    private func readPlayer(_ tab: MacChromeTabIdentity, url: String? = nil, deadline: TimeInterval)
        throws -> MacChromePlayerSnapshot? {
        let url = try url ?? currentURL(tab, deadline: deadline, isAuthorized: { true })
        let response = try execute(.init(operation: "read"), tab: tab, expectedURL: url,
                                   deadline: deadline, isAuthorized: { true })
        switch response.status {
        case "ok":
            guard let media = response.snapshot else { throw MacChromeBackendError.invalidData }
            try validate(media, url: url)
            return .init(tab: tab, media: media, receivedAtUptime: now())
        case "noMedia": return nil
        case "staleContext": throw MacChromeBackendError.staleItem
        default: throw MacChromeBackendError.invalidData
        }
    }

    func readSnapshots(deadline: TimeInterval) throws -> [MacChromePlayerSnapshot] {
        guard let owner = client.runningOwner() else { return [] }
        let candidates = try inventory(owner: owner, deadline: deadline)
        var snapshots: [MacChromePlayerSnapshot] = []
        for (tab, url) in candidates {
            if let player = try readPlayer(tab, url: url, deadline: deadline) { snapshots.append(player) }
        }
        try check(owner: owner, deadline: deadline)
        return snapshots
    }

    /// Bootstrap chooses the first freshly confirmed playing tab, not an unknowable global
    /// start chronology. Unknown unrelated tabs remain unknown and cannot starve discovery.
    func readSelection(preferred: MacChromePlayerSnapshot?, deadline: TimeInterval) -> MacChromeSelectionRead {
        guard let owner = client.runningOwner() else { return .noPlayer }
        var holding = preferred.flatMap { $0.tab.owner == owner ? $0 : nil }
        do {
            try check(owner: owner, deadline: deadline)
            try Self.checkStatus(client.automationPermission(owner: owner, askUser: false))
            var candidates: [(MacChromeTabIdentity, String)]?
            var observed: [MacChromePlayerSnapshot] = []
            if let previous = holding {
                do {
                    if let fresh = try readPlayer(previous.tab, deadline: deadline), fresh.hasSameItem(as: previous) {
                        holding = fresh
                        if Self.isPlaying(fresh) { return .selected(fresh) }
                    } else {
                        // A positive absent/replaced item retires the ownership hold.
                        holding = nil
                    }
                } catch {
                    // A closed/navigated target may be positively disproved by inventory;
                    // an unknown selected renderer must never fall through to bootstrap.
                    let current = try inventory(owner: owner, deadline: deadline)
                    candidates = current
                    if let entry = current.first(where: { $0.0 == previous.tab }),
                       Self.videoID(from: entry.1) == previous.media.videoID {
                        throw error
                    }
                    holding = nil
                }
            }
            let census = try candidates ?? inventory(owner: owner, deadline: deadline)
            if let held = holding, !census.contains(where: { $0.0 == held.tab && Self.videoID(from: $0.1) == held.media.videoID }) {
                holding = nil
            }
            let next = cursorLock.withLock { nextDiscoveryTab }
            let start = next.flatMap { hint in census.firstIndex(where: { $0.0 == hint }) } ?? 0
            var complete = true
            var firstFailure: MacChromeBackendError?
            // Preserve command/readback and paused-owner promotion headroom. This is a
            // work slice within (never an extension of) the caller's absolute deadline.
            let scanDeadline = min(deadline, now() + 0.75)
            for offset in census.indices {
                guard now() < scanDeadline else { complete = false; firstFailure = firstFailure ?? .timedOut; break }
                let index = (start + offset) % census.count
                let (tab, url) = census[index]
                cursorLock.withLock { nextDiscoveryTab = census[(index + 1) % census.count].0 }
                let fresh: MacChromePlayerSnapshot?
                do {
                    fresh = try holding.flatMap { $0.tab == tab ? $0 : nil }
                        ?? readPlayer(tab, url: url, deadline: scanDeadline)
                } catch {
                    let failure = error as? MacChromeBackendError ?? .unavailable
                    if failure == .permissionDenied || failure == .permissionRequired || failure == .javascriptPermissionRequired {
                        throw error
                    }
                    try check(owner: owner, deadline: deadline)
                    complete = false; firstFailure = firstFailure ?? failure
                    if offset > 0, failure == .timedOut, scanDeadline - now() < 0.35 {
                        // Give a clipped tail candidate one fresh-slice retry. A first
                        // candidate must advance on failure, even with slow URL checks.
                        cursorLock.withLock { nextDiscoveryTab = tab }
                        break
                    }
                    continue
                }
                guard let fresh else { continue }
                observed.append(fresh)
                guard Self.isPlaying(fresh) else { continue }
                if let held = holding {
                    // The selected owner may have resumed during the successor scan.
                    // Revalidate it immediately before a handoff; uncertainty blocks it.
                    if let final = try readPlayer(held.tab, deadline: deadline), final.hasSameItem(as: held) {
                        holding = final
                        if Self.isPlaying(final) { return .selected(final) }
                    } else { holding = nil }
                }
                try check(owner: owner, deadline: deadline)
                return .selected(fresh)
            }
            try check(owner: owner, deadline: deadline)
            if let held = holding {
                // Freshly verified paused owners remain explicitly controllable during
                // an incomplete successor search; this does not assert that all tabs paused.
                return .selected(held)
            }
            guard complete else { return .incomplete(firstFailure ?? .timedOut, holding: nil) }
            if let paused = try Self.select(observed, preferred: nil) { return .selected(paused) }
            return .noPlayer
        } catch {
            return .incomplete(error as? MacChromeBackendError ?? .unavailable, holding: holding)
        }
    }

    private static func isPlaying(_ snapshot: MacChromePlayerSnapshot) -> Bool {
        !snapshot.media.paused && snapshot.media.playbackRate > 0
    }

    func send(_ command: MacChromeCommand, positionSeconds: TimeInterval? = nil, expected: MacChromePlayerSnapshot,
              deadline: TimeInterval, isAuthorized: @escaping @Sendable () -> Bool) throws
        -> WebRTCRemoteMediaCommandResult {
        guard command.accepts(positionSeconds: positionSeconds) else { return .failed }
        let deadline = min(deadline, expected.receivedAtUptime + Self.maximumSnapshotAge)
        try check(owner: expected.tab.owner, deadline: deadline, isAuthorized: isAuthorized)
        // The current publication/epoch authorizes this exact selected item. Automatic
        // handoff belongs to readSelection; unrelated renderers cannot delay a command.
        try Self.checkStatus(client.automationPermission(owner: expected.tab.owner, askUser: false))
        guard let selected = try readPlayer(expected.tab, deadline: deadline), selected.hasSameItem(as: expected)
        else { throw MacChromeBackendError.retiredItem }
        guard selected.media.enabledCommands.contains(command.rawValue) else { return .unsupported }
        let remainingFromObservation = (deadline - expected.receivedAtUptime) * 1000
        guard remainingFromObservation > 0 else { throw MacChromeBackendError.timedOut }
        let commandID = UUID().uuidString
        let request = ScriptRequest(
            operation: "command", commandID: commandID, expected: expected.media.identity,
            command: command.scriptName,
            positionSeconds: positionSeconds,
            expiresAtUnixMilliseconds: min(wallNow() * 1000 + (deadline - now()) * 1000,
                expected.media.observedAtUnixMilliseconds + remainingFromObservation),
            expiresAtPageMilliseconds: expected.media.observedAtPageMilliseconds + remainingFromObservation)
        let url = try currentURL(expected.tab, deadline: deadline, isAuthorized: isAuthorized)
        guard Self.videoID(from: url) == expected.media.videoID else { throw MacChromeBackendError.retiredItem }
        var response = try execute(request, tab: expected.tab, expectedURL: url,
                                   deadline: deadline, isAuthorized: isAuthorized,
                                   allowSuccessor: command.changesTrack)
        // Only result lookups repeat. A command Apple Event is never resent after timeout.
        var polls = 0
        while response.status == "pending", polls < 24 {
            polls += 1
            try check(owner: expected.tab.owner, deadline: deadline, isAuthorized: isAuthorized)
            Thread.sleep(forTimeInterval: min(0.025, max(0, deadline - now())))
            response = try execute(.init(operation: "result", commandID: commandID,
                                        expected: expected.media.identity),
                                   tab: expected.tab, expectedURL: nil, deadline: deadline,
                                   isAuthorized: isAuthorized, allowSuccessor: command.changesTrack)
        }
        try check(owner: expected.tab.owner, deadline: deadline, isAuthorized: isAuthorized)
        switch response.status {
        case "ok":
            guard let media = response.snapshot else { return .failed }
            let finalURL = try currentURL(expected.tab, deadline: deadline, isAuthorized: isAuthorized)
            try validate(media, url: finalURL)
            guard media.documentID == expected.media.documentID else { throw MacChromeBackendError.retiredItem }
            if command.changesTrack {
                return media.videoID != expected.media.videoID && media.identity != expected.media.identity
                    ? .applied : .failed
            }
            guard media.identity == expected.media.identity else { throw MacChromeBackendError.retiredItem }
            if command.isSeek {
                guard let origin = response.seekFrom, let target = response.seekTarget,
                      let duration = media.duration, let elapsed = media.elapsedTime,
                      origin.isFinite, target.isFinite, duration > 0,
                      (0...duration).contains(origin), (0...duration).contains(target),
                      abs(target - min(duration, max(0, positionSeconds ??
                        (origin + (command == .seekForward30 ? 30 : -30))))) < 0.001,
                      abs(elapsed - target) <= 0.25 else { return .failed }
                return .applied
            }
            return (command == .play && !media.paused) || (command == .pause && media.paused) ? .applied : .failed
        case "staleContext":
            if let media = response.snapshot {
                let finalURL = try currentURL(expected.tab, deadline: deadline, isAuthorized: isAuthorized)
                try validate(media, url: finalURL)
                if media.identity != expected.media.identity || media.videoID != expected.media.videoID {
                    throw MacChromeBackendError.retiredItem
                }
            }
            return .staleContext
        case "unsupported": return .unsupported
        case "noMedia": throw MacChromeBackendError.retiredItem
        default: return .failed
        }
    }

    static func select(_ snapshots: [MacChromePlayerSnapshot], preferred: MacChromePlayerSnapshot?) throws
        -> MacChromePlayerSnapshot? {
        let playing = snapshots.filter { !$0.media.paused && $0.media.playbackRate > 0 }
        if let preferred, let retained = playing.first(where: { $0.hasSameItem(as: preferred) }) { return retained }
        if let unique = playing.first { return unique }
        if let preferred, let sticky = snapshots.first(where: { $0.hasSameItem(as: preferred) }) { return sticky }
        guard snapshots.count <= 1 else { throw MacChromeBackendError.ambiguousPlayers }
        return snapshots.first
    }

    static func videoID(from value: String) -> String? {
        guard value.utf8.count <= 8_192, let url = URLComponents(string: value),
              url.scheme == "https", url.host == "www.youtube.com", url.path == "/watch",
              url.port == nil, url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        let values = (url.queryItems ?? []).filter { $0.name == "v" }
        guard values.count == 1, let id = values.first?.value, id.utf8.count == 11,
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return id
    }

    private struct ScriptRequest: Encodable {
        let schemaVersion = 1
        let operation: String
        var commandID: String? = nil
        var expected: MacChromeMediaIdentity? = nil
        var command: String? = nil
        var positionSeconds: Double? = nil
        var expiresAtUnixMilliseconds: Double? = nil
        var expiresAtPageMilliseconds: Double? = nil
    }

    private struct ScriptResponse: Decodable {
        let schemaVersion: Int
        let status: String
        let snapshot: MacChromeScriptSnapshot?
        let seekFrom: Double?
        let seekTarget: Double?
    }

    private func execute(_ request: ScriptRequest, tab: MacChromeTabIdentity, expectedURL: String?,
                         deadline: TimeInterval, isAuthorized: @escaping @Sendable () -> Bool,
                         allowSuccessor: Bool = false) throws -> ScriptResponse {
        let beforeURL = try currentURL(tab, deadline: deadline, isAuthorized: isAuthorized)
        guard Self.videoID(from: beforeURL) != nil, expectedURL == nil || beforeURL == expectedURL else {
            throw MacChromeBackendError.staleItem
        }
        let data = try JSONEncoder().encode(request)
        guard data.count <= 2_048 else { throw MacChromeBackendError.invalidData }
        let script = "(" + MacChromeMediaScript.source + "\n)(" + String(decoding: data, as: UTF8.self) + ")"
        let event = NSAppleEventDescriptor(eventClass: 0x43725375, eventID: 0x45784A61,
            targetDescriptor: .init(processIdentifier: tab.owner.processID),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(try tabReference(tab), forKeyword: keyDirectObject)
        event.setParam(.init(string: script), forKeyword: 0x4A765363)
        let result = try sendEvent(event, owner: tab.owner, deadline: deadline, isAuthorized: isAuthorized)
        let afterURL = try currentURL(tab, deadline: deadline, isAuthorized: isAuthorized)
        guard Self.videoID(from: afterURL) != nil, allowSuccessor || beforeURL == afterURL else {
            throw MacChromeBackendError.staleItem
        }
        let responseText = try boundedText(result, maximum: 16_384)
        let response = try JSONDecoder().decode(ScriptResponse.self, from: Data(responseText.utf8))
        guard response.schemaVersion == 1 else { throw MacChromeBackendError.invalidData }
        return response
    }

    private func validate(_ media: MacChromeScriptSnapshot, url: String) throws {
        guard UUID(uuidString: media.documentID) != nil, media.documentID.count == 36,
              UUID(uuidString: media.itemID) != nil, media.itemID.count == 36,
              media.itemGeneration > 0, media.itemGeneration <= 9_007_199_254_740_991,
              Self.videoID(from: url) == media.videoID,
              !media.title.isEmpty, media.title.utf8.count <= 8_192,
              (media.artist?.utf8.count ?? 0) <= 8_192,
              media.playbackRate.isFinite, (0...16).contains(media.playbackRate),
              media.observedAtUnixMilliseconds.isFinite,
              abs(wallNow() * 1000 - media.observedAtUnixMilliseconds) <= 5_000,
              media.observedAtPageMilliseconds.isFinite, media.observedAtPageMilliseconds >= 0,
              media.observedAtPageMilliseconds <= 9_007_199_254_740_991,
              [media.duration, media.elapsedTime].allSatisfy({ value in
                  value.map { $0.isFinite && $0 >= 0 && $0 <= 31_536_000 } ?? true
              }) else { throw MacChromeBackendError.invalidData }
    }

    private func currentURL(_ tab: MacChromeTabIdentity, deadline: TimeInterval,
                            isAuthorized: @escaping @Sendable () -> Bool) throws -> String {
        let window = try byID(0x6377696E, id: tab.windowID)
        guard try boundedText(get(property(0x6D6F6465, of: window), owner: tab.owner,
                                  deadline: deadline, isAuthorized: isAuthorized)) == "normal" else {
            throw MacChromeBackendError.staleItem
        }
        return try boundedText(get(property(0x55524C20, of: tabReference(tab)), owner: tab.owner,
                                   deadline: deadline, isAuthorized: isAuthorized))
    }

    private func tabReference(_ tab: MacChromeTabIdentity) throws -> NSAppleEventDescriptor {
        try byID(0x43725462, id: tab.tabID, in: byID(0x6377696E, id: tab.windowID))
    }

    private func get(_ reference: NSAppleEventDescriptor, owner: MacChromePlayerIdentity,
                     deadline: TimeInterval, isAuthorized: @escaping @Sendable () -> Bool = { true }) throws
        -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: kAEGetData,
            targetDescriptor: .init(processIdentifier: owner.processID),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(reference, forKeyword: keyDirectObject)
        return try sendEvent(event, owner: owner, deadline: deadline, isAuthorized: isAuthorized)
    }

    private func sendEvent(_ event: NSAppleEventDescriptor, owner: MacChromePlayerIdentity,
                           deadline: TimeInterval, isAuthorized: @escaping @Sendable () -> Bool) throws
        -> NSAppleEventDescriptor {
        let timeout = try dispatchTimeout(owner: owner, deadline: deadline, isAuthorized: isAuthorized)
        do {
            let reply = try client.sendEvent(event, options: Self.sendOptions, timeout: timeout)
            try check(owner: owner, deadline: deadline, isAuthorized: isAuthorized)
            if let error = reply.paramDescriptor(forKeyword: keyErrorNumber), error.int32Value != 0 {
                let message = reply.paramDescriptor(forKeyword: keyErrorString)?.stringValue ?? ""
                if error.int32Value == -10000, message.utf8.count <= 8_192,
                   message.lowercased().contains("javascript"), message.lowercased().contains("turned off") {
                    throw MacChromeBackendError.javascriptPermissionRequired
                }
                try Self.checkStatus(error.int32Value)
            }
            guard let result = reply.paramDescriptor(forKeyword: keyDirectObject), result.data.count <= 262_144 else {
                throw MacChromeBackendError.invalidData
            }
            return result
        } catch let error as MacChromeBackendError { throw error }
        catch { try Self.checkStatus(OSStatus((error as NSError).code)); throw MacChromeBackendError.unavailable }
    }

    private func dispatchTimeout(owner: MacChromePlayerIdentity, deadline: TimeInterval,
                                 isAuthorized: () -> Bool) throws -> TimeInterval {
        guard client.runningOwner() == owner else { throw MacChromeBackendError.staleItem }
        let remaining = deadline - now()
        guard deadline.isFinite, remaining > 0 else { throw MacChromeBackendError.timedOut }
        guard isAuthorized() else { throw MacChromeBackendError.staleItem }
        return min(0.35, remaining)
    }

    private func check(owner: MacChromePlayerIdentity, deadline: TimeInterval,
                       isAuthorized: () -> Bool = { true }) throws {
        guard client.runningOwner() == owner, isAuthorized() else { throw MacChromeBackendError.staleItem }
        guard deadline.isFinite, now() < deadline else { throw MacChromeBackendError.timedOut }
    }

    private static func checkStatus(_ status: OSStatus) throws {
        switch status {
        case noErr: return
        case -1744: throw MacChromeBackendError.permissionRequired
        case -1743: throw MacChromeBackendError.permissionDenied
        case OSStatus(errAETimeout): throw MacChromeBackendError.timedOut
        case -1728: throw MacChromeBackendError.staleItem
        default: throw MacChromeBackendError.unavailable
        }
    }

    private func object(_ kind: OSType, container: NSAppleEventDescriptor = .null(),
                        form: OSType, selector: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: kind), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        record.setDescriptor(.init(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(selector, forKeyword: AEKeyword(keyAEKeyData))
        guard let result = record.coerce(toDescriptorType: typeObjectSpecifier) else {
            throw MacChromeBackendError.invalidData
        }
        return result
    }

    private func all(_ kind: OSType, in container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        var ordinal = UInt32(kAEAll)
        guard let selector = withUnsafeBytes(of: &ordinal, {
            NSAppleEventDescriptor(descriptorType: typeAbsoluteOrdinal, data: Data($0))
        }) else { throw MacChromeBackendError.invalidData }
        return try object(kind, container: container, form: OSType(formAbsolutePosition), selector: selector)
    }

    private func byID(_ kind: OSType, id: String, in container: NSAppleEventDescriptor = .null()) throws
        -> NSAppleEventDescriptor {
        guard Self.validIdentifier(id) else { throw MacChromeBackendError.invalidData }
        return try object(kind, container: container, form: OSType(formUniqueID), selector: .init(string: id))
    }

    private func property(_ code: OSType, of container: NSAppleEventDescriptor = .null()) throws
        -> NSAppleEventDescriptor {
        try object(typeProperty, container: container, form: OSType(formPropertyID), selector: .init(typeCode: code))
    }

    private func list(_ descriptor: NSAppleEventDescriptor, maximum: Int) throws -> [NSAppleEventDescriptor] {
        guard descriptor.descriptorType == typeAEList, descriptor.numberOfItems <= maximum else {
            throw MacChromeBackendError.invalidData
        }
        guard descriptor.numberOfItems > 0 else { return [] }
        return try (1...descriptor.numberOfItems).map {
            guard let value = descriptor.atIndex($0) else { throw MacChromeBackendError.invalidData }
            return value
        }
    }

    private func identifiers(_ descriptor: NSAppleEventDescriptor, maximum: Int) throws -> [String] {
        let ids = try list(descriptor, maximum: maximum).map { try boundedText($0) }
        guard ids.allSatisfy(Self.validIdentifier), Set(ids).count == ids.count else {
            throw MacChromeBackendError.invalidData
        }
        return ids
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 20 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private func boundedText(_ descriptor: NSAppleEventDescriptor, maximum: Int = 8_192) throws -> String {
        guard let text = descriptor.stringValue, text.utf8.count <= maximum else { throw MacChromeBackendError.invalidData }
        return text
    }
}
