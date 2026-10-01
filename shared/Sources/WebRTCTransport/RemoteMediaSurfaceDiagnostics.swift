import Foundation

/// Configuration readback and command entrypoints, never proof of system-rendered pixels.
public struct WebRTCRemoteMediaSurfaceDiagnostics: Codable, Equatable, Sendable {
    public enum ExpectedState: String, Codable, Equatable, Sendable {
        case playing, paused, stopped
    }

    public enum PlaybackRate: String, Codable, Equatable, Sendable {
        case absent, zero, positive, invalid
    }

    public enum ControlOrigin: String, Codable, Equatable, Sendable {
        case unspecified, nativeCommandCenter, customNotification
    }

    public struct NativeMetadata: Codable, Equatable, Sendable {
        public var expectedRevision: UInt64?
        public var expectedState: ExpectedState?
        public var metadataPresent: Bool
        public var currentItemMatches: Bool?
        public var playbackRate: PlaybackRate
        public var enabledCommandMask: UInt8

        public init(expectedRevision: UInt64? = nil, expectedState: ExpectedState? = nil,
                    metadataPresent: Bool = false, currentItemMatches: Bool? = nil,
                    playbackRate: PlaybackRate = .absent, enabledCommandMask: UInt8 = 0) {
            self.expectedRevision = expectedRevision
            self.expectedState = expectedState
            self.metadataPresent = metadataPresent
            self.currentItemMatches = currentItemMatches
            self.playbackRate = playbackRate
            self.enabledCommandMask = enabledCommandMask
        }

        public var isValid: Bool {
            (expectedRevision.map { $0 > 0 } ?? true)
                && (expectedState == nil || expectedRevision != nil)
                && (currentItemMatches == nil || expectedState != nil)
                && (currentItemMatches != true || metadataPresent)
                && (metadataPresent || playbackRate == .absent)
                && enabledCommandMask <= 63
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case expectedRevision = "r", expectedState = "s", metadataPresent = "p"
            case currentItemMatches = "m", playbackRate = "v", enabledCommandMask = "c"
        }

        public init(from decoder: any Decoder) throws {
            try validateSurfaceKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let values = try decoder.container(keyedBy: CodingKeys.self)
            expectedRevision = try values.decodeIfPresent(UInt64.self, forKey: .expectedRevision)
            expectedState = try values.decodeIfPresent(ExpectedState.self, forKey: .expectedState)
            metadataPresent = try values.decode(Bool.self, forKey: .metadataPresent)
            currentItemMatches = try values.decodeIfPresent(Bool.self, forKey: .currentItemMatches)
            playbackRate = try values.decode(PlaybackRate.self, forKey: .playbackRate)
            enabledCommandMask = try values.decode(UInt8.self, forKey: .enabledCommandMask)
            guard isValid else { throw invalidSurface(decoder) }
        }
    }

    public struct ControlObservation: Codable, Equatable, Sendable {
        public var sequence: UInt64
        public var origin: ControlOrigin
        public var revision: UInt64?
        public var admitted: Bool
        public var ageMilliseconds: UInt32?

        public init(sequence: UInt64, origin: ControlOrigin, revision: UInt64? = nil, admitted: Bool,
                    ageMilliseconds: UInt32? = nil) {
            self.sequence = sequence
            self.origin = origin
            self.revision = revision
            self.admitted = admitted
            self.ageMilliseconds = ageMilliseconds
        }

        public var isValid: Bool {
            sequence > 0 && (revision.map { $0 > 0 } ?? true) && (!admitted || revision != nil)
                && (ageMilliseconds.map { $0 <= 86_400_000 } ?? true)
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case sequence = "q", origin = "o", revision = "r", admitted = "a", ageMilliseconds = "t"
        }

        public init(from decoder: any Decoder) throws {
            try validateSurfaceKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let values = try decoder.container(keyedBy: CodingKeys.self)
            sequence = try values.decode(UInt64.self, forKey: .sequence)
            origin = try values.decode(ControlOrigin.self, forKey: .origin)
            revision = try values.decodeIfPresent(UInt64.self, forKey: .revision)
            admitted = try values.decode(Bool.self, forKey: .admitted)
            ageMilliseconds = try values.decodeIfPresent(UInt32.self, forKey: .ageMilliseconds)
            guard isValid else { throw invalidSurface(decoder) }
        }
    }

    public var nativeMetadata: NativeMetadata?
    public var lastControl: ControlObservation?

    public init(nativeMetadata: NativeMetadata? = nil, lastControl: ControlObservation? = nil) {
        self.nativeMetadata = nativeMetadata
        self.lastControl = lastControl
    }

    public var isValid: Bool { (nativeMetadata?.isValid ?? true) && (lastControl?.isValid ?? true) }

    enum CodingKeys: String, CodingKey, CaseIterable { case nativeMetadata = "n", lastControl = "c" }

    public init(from decoder: any Decoder) throws {
        try validateSurfaceKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        nativeMetadata = try values.decodeIfPresent(NativeMetadata.self, forKey: .nativeMetadata)
        lastControl = try values.decodeIfPresent(ControlObservation.self, forKey: .lastControl)
        guard isValid else { throw invalidSurface(decoder) }
    }
}

private struct SurfaceCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func invalidSurface(_ decoder: any Decoder) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid media-surface diagnostics."))
}

private func validateSurfaceKeys(_ decoder: any Decoder, allowed: [String]) throws {
    let values = try decoder.container(keyedBy: SurfaceCodingKey.self)
    guard Set(values.allKeys.map(\.stringValue)).isSubset(of: Set(allowed)) else {
        throw invalidSurface(decoder)
    }
}
