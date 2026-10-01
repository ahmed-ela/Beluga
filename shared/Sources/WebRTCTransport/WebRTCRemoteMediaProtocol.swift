import Foundation

/// Unforgeable binding for one exact offer/answer generation. This remains transport-internal:
/// application code supplies semantic state and commands while `WebRTCPeer` stamps and validates
/// the authorization at the wire boundary.
struct WebRTCRemoteMediaAuthorization: Codable, Equatable, Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Absolute commands for the Mac's current system Now Playing session.
public enum WebRTCRemoteMediaCommand: String, Codable, CaseIterable, Sendable {
    case play
    case pause
    case nextTrack
    case previousTrack
    case seekForward30
    case seekBackward30
    case seekToPosition

    public func accepts(positionSeconds: TimeInterval?) -> Bool {
        if self == .seekToPosition {
            guard let positionSeconds else { return false }
            return positionSeconds.isFinite && (0...31_536_000).contains(positionSeconds)
        }
        return positionSeconds == nil
    }
}

public enum WebRTCRemoteMediaPlaybackState: String, Codable, Sendable {
    case playing
    case paused
    case stopped
}

/// Explicit command support keeps iOS from presenting controls the active Mac player cannot use.
public struct WebRTCRemoteMediaCapabilities: Codable, Equatable, Sendable {
    public let canPlay: Bool
    public let canPause: Bool
    public let canSkipForward: Bool
    public let canSkipBackward: Bool
    public let canSeekForward: Bool
    public let canSeekBackward: Bool
    public let canSeekToPosition: Bool

    public init(
        canPlay: Bool,
        canPause: Bool,
        canSkipForward: Bool,
        canSkipBackward: Bool,
        canSeekForward: Bool = false,
        canSeekBackward: Bool = false,
        canSeekToPosition: Bool = false
    ) {
        self.canPlay = canPlay
        self.canPause = canPause
        self.canSkipForward = canSkipForward
        self.canSkipBackward = canSkipBackward
        self.canSeekForward = canSeekForward
        self.canSeekBackward = canSeekBackward
        self.canSeekToPosition = canSeekToPosition
    }

    private enum CodingKeys: String, CodingKey {
        case canPlay, canPause, canSkipForward, canSkipBackward, canSeekForward, canSeekBackward, canSeekToPosition
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        canPlay = try values.decode(Bool.self, forKey: .canPlay)
        canPause = try values.decode(Bool.self, forKey: .canPause)
        canSkipForward = try values.decode(Bool.self, forKey: .canSkipForward)
        canSkipBackward = try values.decode(Bool.self, forKey: .canSkipBackward)
        canSeekForward = try values.decodeIfPresent(Bool.self, forKey: .canSeekForward) ?? false
        canSeekBackward = try values.decodeIfPresent(Bool.self, forKey: .canSeekBackward) ?? false
        canSeekToPosition = try values.decodeIfPresent(Bool.self, forKey: .canSeekToPosition) ?? false
    }

    public func permits(_ command: WebRTCRemoteMediaCommand) -> Bool {
        switch command {
        case .play: canPlay
        case .pause: canPause
        case .nextTrack: canSkipForward
        case .previousTrack: canSkipBackward
        case .seekForward30: canSeekForward
        case .seekBackward30: canSeekBackward
        case .seekToPosition: canSeekToPosition
        }
    }
}

/// A bounded provider identifier, never a peer-supplied URL or image payload.
public struct WebRTCRemoteMediaArtworkReference: Codable, Equatable, Hashable, Sendable {
    public enum Provider: String, Codable, Hashable, Sendable {
        case youtube
    }

    public let provider: Provider
    public let videoID: String

    public init?(provider: Provider = .youtube, videoID: String) {
        guard videoID.utf8.count == 11,
              videoID.utf8.allSatisfy({ byte in
                  (65...90).contains(byte) || (97...122).contains(byte)
                      || (48...57).contains(byte) || byte == 45 || byte == 95
              }) else { return nil }
        self.provider = provider
        self.videoID = videoID
    }

    public var url: URL {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")!
    }

    private enum CodingKeys: String, CodingKey {
        case provider, videoID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try values.decode(Provider.self, forKey: .provider)
        let videoID = try values.decode(String.self, forKey: .videoID)
        guard let reference = Self(provider: provider, videoID: videoID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .videoID, in: values, debugDescription: "Invalid artwork identifier"
            )
        }
        self = reference
    }
}

/// Bounded metadata for one Mac system Now Playing owner. Only a small artwork reference may
/// accompany it; image bytes never enter the 4 KiB ordered control channel.
public struct WebRTCRemoteMediaItem: Codable, Equatable, Sendable {
    public static let maximumContextIDBytes = 128
    public static let maximumSourceNameBytes = 128
    public static let maximumTitleBytes = 512
    public static let maximumArtistBytes = 256
    public static let maximumAlbumBytes = 256

    public let contextID: String
    public let sourceName: String
    public let title: String
    public let artist: String?
    public let album: String?
    public let playbackState: WebRTCRemoteMediaPlaybackState
    public let elapsedTime: TimeInterval?
    public let duration: TimeInterval?
    public let playbackRate: Double
    public let capabilities: WebRTCRemoteMediaCapabilities
    public let artwork: WebRTCRemoteMediaArtworkReference?

    public init(
        contextID: String,
        sourceName: String,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        playbackState: WebRTCRemoteMediaPlaybackState,
        elapsedTime: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        playbackRate: Double,
        capabilities: WebRTCRemoteMediaCapabilities,
        artwork: WebRTCRemoteMediaArtworkReference? = nil
    ) {
        self.contextID = contextID
        self.sourceName = sourceName
        self.title = title
        self.artist = artist
        self.album = album
        self.playbackState = playbackState
        self.elapsedTime = elapsedTime
        self.duration = duration
        self.playbackRate = playbackRate
        self.capabilities = capabilities
        self.artwork = artwork
    }

    private enum CodingKeys: String, CodingKey {
        case contextID, sourceName, title, artist, album, playbackState
        case elapsedTime, duration, playbackRate, capabilities, artwork
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        contextID = try values.decode(String.self, forKey: .contextID)
        sourceName = try values.decode(String.self, forKey: .sourceName)
        title = try values.decode(String.self, forKey: .title)
        artist = try values.decodeIfPresent(String.self, forKey: .artist)
        album = try values.decodeIfPresent(String.self, forKey: .album)
        playbackState = try values.decode(WebRTCRemoteMediaPlaybackState.self, forKey: .playbackState)
        elapsedTime = try values.decodeIfPresent(TimeInterval.self, forKey: .elapsedTime)
        duration = try values.decodeIfPresent(TimeInterval.self, forKey: .duration)
        playbackRate = try values.decode(Double.self, forKey: .playbackRate)
        capabilities = try values.decode(WebRTCRemoteMediaCapabilities.self, forKey: .capabilities)
        // Optional decoration must not revoke otherwise valid playback controls.
        artwork = try? values.decodeIfPresent(WebRTCRemoteMediaArtworkReference.self, forKey: .artwork)
    }

    public var isValid: Bool {
        Self.validRequired(contextID, maximumBytes: Self.maximumContextIDBytes)
            && Self.validRequired(sourceName, maximumBytes: Self.maximumSourceNameBytes)
            && Self.validRequired(title, maximumBytes: Self.maximumTitleBytes)
            && Self.validOptional(artist, maximumBytes: Self.maximumArtistBytes)
            && Self.validOptional(album, maximumBytes: Self.maximumAlbumBytes)
            && Self.validTime(elapsedTime)
            && Self.validTime(duration)
            && playbackRate.isFinite
            && playbackRate >= 0
            && playbackRate <= 16
    }

    private static func validRequired(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty
            && value.utf8.count <= maximumBytes
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func validOptional(_ value: String?, maximumBytes: Int) -> Bool {
        guard let value else { return true }
        return validRequired(value, maximumBytes: maximumBytes)
    }

    private static func validTime(_ value: TimeInterval?) -> Bool {
        guard let value else { return true }
        return value.isFinite && value >= 0 && value <= 31_536_000
    }
}

/// A nil item explicitly clears a prior Now Playing owner. Revisions are monotonic within one
/// negotiated WebRTC peer generation.
public struct WebRTCRemoteMediaStateUpdate: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let item: WebRTCRemoteMediaItem?
    public let additionalItems: [WebRTCRemoteMediaItem]

    public init(revision: UInt64, item: WebRTCRemoteMediaItem?, additionalItems: [WebRTCRemoteMediaItem] = []) {
        self.revision = revision
        self.item = item
        self.additionalItems = additionalItems
    }

    private enum CodingKeys: String, CodingKey { case revision, item, additionalItems }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        revision = try values.decode(UInt64.self, forKey: .revision)
        item = try values.decodeIfPresent(WebRTCRemoteMediaItem.self, forKey: .item)
        additionalItems = try values.decodeIfPresent([WebRTCRemoteMediaItem].self, forKey: .additionalItems) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(revision, forKey: .revision)
        try values.encodeIfPresent(item, forKey: .item)
        if !additionalItems.isEmpty { try values.encode(additionalItems, forKey: .additionalItems) }
    }

    public var allItems: [WebRTCRemoteMediaItem] {
        item.map { [$0] + additionalItems } ?? []
    }

    public func item(contextID: String) -> WebRTCRemoteMediaItem? {
        allItems.first { $0.contextID == contextID }
    }

    public var isValid: Bool {
        revision > 0 && (item?.isValid ?? true)
            && additionalItems.count <= 1
            && (item != nil || additionalItems.isEmpty)
            && additionalItems.allSatisfy(\.isValid)
            && Set(allItems.map(\.contextID)).count == allItems.count
    }
}

extension WebRTCRemoteMediaPipelineDiagnostics.Stage {
    /// Privacy-reduced observation only; never serializes source identity or media metadata.
    public init?(update: WebRTCRemoteMediaStateUpdate) {
        guard update.isValid else { return nil }
        let items = update.allItems
        self.init(revision: update.revision, itemCount: UInt8(items.count),
                  playingMask: items.enumerated().reduce(UInt8(0)) { mask, entry in
                      entry.element.playbackState == .playing ? mask | (1 << entry.offset) : mask
                  })
    }
}

/// An immutable state received under one exact transport negotiation. Application code may retain
/// it for native controls, but cannot manufacture or replace its transport authority.
public struct WebRTCReceivedRemoteMediaState: Equatable, Sendable {
    public let update: WebRTCRemoteMediaStateUpdate
    public let refreshID: UUID?
    let authorization: WebRTCRemoteMediaAuthorization

    init(envelope: WebRTCRemoteMediaStateEnvelope) {
        update = envelope.update
        refreshID = envelope.refreshID
        authorization = envelope.authorization
    }

    public func isSameNegotiation(as other: Self) -> Bool {
        authorization == other.authorization
    }
}

/// A viewer-ready snapshot request stamped by the receiving transport, never by application code.
public struct WebRTCReceivedRemoteMediaStateRefreshRequest: Equatable, Sendable {
    public let id: UUID
    let authorization: WebRTCRemoteMediaAuthorization

    init(envelope: WebRTCRemoteMediaStateRefreshEnvelope) {
        id = envelope.id
        authorization = envelope.authorization
    }
}

public struct WebRTCRemoteMediaCommandRequest: Codable, Equatable, Sendable {
    public let id: UInt64
    public let contextID: String
    public let observedRevision: UInt64
    public let command: WebRTCRemoteMediaCommand
    public let positionSeconds: TimeInterval?

    public init(
        id: UInt64,
        contextID: String,
        observedRevision: UInt64,
        command: WebRTCRemoteMediaCommand,
        positionSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.contextID = contextID
        self.observedRevision = observedRevision
        self.command = command
        self.positionSeconds = positionSeconds
    }

    public var isValid: Bool {
        id > 0
            && observedRevision > 0
            && !contextID.isEmpty
            && contextID.utf8.count <= WebRTCRemoteMediaItem.maximumContextIDBytes
            && !contextID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && command.accepts(positionSeconds: positionSeconds)
    }
}

/// The application must return this exact received command when completing asynchronous work.
/// A numeric request ID alone is not unique after a same-peer renegotiation.
public struct WebRTCReceivedRemoteMediaCommand: Equatable, Sendable {
    public let request: WebRTCRemoteMediaCommandRequest
    let authorization: WebRTCRemoteMediaAuthorization
    let executionAuthorization: WebRTCControlAuthorization

    public var isValid: Bool { executionAuthorization.isValid }

    init(
        envelope: WebRTCRemoteMediaCommandEnvelope,
        executionAuthorization: WebRTCControlAuthorization
    ) {
        request = envelope.request
        authorization = envelope.authorization
        self.executionAuthorization = executionAuthorization
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request && lhs.authorization == rhs.authorization
            && lhs.executionAuthorization === rhs.executionAuthorization
    }
}

public enum WebRTCRemoteMediaCommandResult: String, Codable, Sendable {
    case applied
    case unsupported
    case staleContext
    case noActiveMedia
    case failed
}

public struct WebRTCRemoteMediaCommandAcknowledgement: Codable, Equatable, Sendable {
    public let id: UInt64
    public let result: WebRTCRemoteMediaCommandResult

    public init(id: UInt64, result: WebRTCRemoteMediaCommandResult) {
        self.id = id
        self.result = result
    }

    public var isValid: Bool { id > 0 }
}

/// Wire-only envelopes make the negotiation authorization mandatory without asking the host media
/// controller or iOS UI to obtain, retain, or manufacture transport authority.
struct WebRTCRemoteMediaStateEnvelope: Codable, Equatable, Sendable {
    let authorization: WebRTCRemoteMediaAuthorization
    let update: WebRTCRemoteMediaStateUpdate
    let refreshID: UUID?

    init(
        authorization: WebRTCRemoteMediaAuthorization,
        update: WebRTCRemoteMediaStateUpdate,
        refreshID: UUID? = nil
    ) {
        self.authorization = authorization
        self.update = update
        self.refreshID = refreshID
    }

    var isValid: Bool { update.isValid }
}

/// Per-field UTF-8 limits do not bound JSON escaping across two sources. Keep command authority
/// intact and shorten display-only metadata against the actual complete control envelope.
enum WebRTCRemoteMediaStateWireEncoding {
    static func encode(_ envelope: WebRTCRemoteMediaStateEnvelope) throws
        -> (data: Data, update: WebRTCRemoteMediaStateUpdate) {
        guard envelope.isValid else { throw WebRTCTransportError.invalidInputRequest }
        let original = try JSONEncoder().encode(ControlChannelMessage.remoteMediaState(envelope))
        if original.count <= WebRTCWireConstants.maximumControlMessageBytes {
            return (original, envelope.update)
        }
        for maximumLabelBytes in [512, 256, 128, 64] {
            func projected(_ item: WebRTCRemoteMediaItem) -> WebRTCRemoteMediaItem {
                .init(contextID: item.contextID,
                      sourceName: shortened(item.sourceName, maximumBytes: min(128, maximumLabelBytes)),
                      title: shortened(item.title, maximumBytes: maximumLabelBytes),
                      playbackState: item.playbackState, elapsedTime: item.elapsedTime,
                      duration: item.duration, playbackRate: item.playbackRate,
                      capabilities: item.capabilities, artwork: item.artwork)
            }
            let update = WebRTCRemoteMediaStateUpdate(revision: envelope.update.revision,
                item: envelope.update.item.map(projected),
                additionalItems: envelope.update.additionalItems.map(projected))
            let projectedEnvelope = WebRTCRemoteMediaStateEnvelope(authorization: envelope.authorization,
                update: update, refreshID: envelope.refreshID)
            let data = try JSONEncoder().encode(ControlChannelMessage.remoteMediaState(projectedEnvelope))
            if data.count <= WebRTCWireConstants.maximumControlMessageBytes {
                return (data, update)
            }
        }
        throw WebRTCTransportError.invalidInputRequest
    }

    private static func shortened(_ value: String, maximumBytes: Int) -> String {
        guard value.utf8.count > maximumBytes else { return value }
        var result = ""
        var count = 0
        for character in value {
            let size = character.utf8.count
            guard count + size <= maximumBytes else { break }
            result.append(character)
            count += size
        }
        return result.isEmpty ? "…" : result
    }
}

struct WebRTCRemoteMediaStateRefreshEnvelope: Codable, Equatable, Sendable {
    let authorization: WebRTCRemoteMediaAuthorization
    let id: UUID
}

struct WebRTCRemoteMediaCommandEnvelope: Codable, Equatable, Sendable {
    let authorization: WebRTCRemoteMediaAuthorization
    let request: WebRTCRemoteMediaCommandRequest

    var isValid: Bool { request.isValid }
}

struct WebRTCRemoteMediaCommandAcknowledgementEnvelope:
    Codable,
    Equatable,
    Sendable
{
    let authorization: WebRTCRemoteMediaAuthorization
    let acknowledgement: WebRTCRemoteMediaCommandAcknowledgement

    var isValid: Bool { acknowledgement.isValid }
}

/// Pure admission rule for relative media commands. A normal elapsed-time refresh may advance the
/// state revision while retaining the same media context, so an older observed revision is safe;
/// a future revision, changed context, or changed capability is not.
public enum WebRTCRemoteMediaCommandAdmission {
    public static func rejection(
        for request: WebRTCRemoteMediaCommandRequest,
        latestSuccessfullySent update: WebRTCRemoteMediaStateUpdate?
    ) -> WebRTCRemoteMediaCommandResult? {
        guard request.isValid else { return .failed }
        guard let update, update.isValid else { return .noActiveMedia }
        guard request.observedRevision <= update.revision else {
            return .staleContext
        }
        guard update.item != nil else { return .noActiveMedia }
        guard let item = update.item(contextID: request.contextID) else {
            return .staleContext
        }
        guard item.capabilities.permits(request.command) else {
            return .unsupported
        }
        if request.command == .seekToPosition {
            guard let duration = item.duration, duration.isFinite, duration > 0 else { return .unsupported }
        }
        return nil
    }
}
