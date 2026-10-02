import Foundation

/// Distribution metadata is admitted only as a complete signed-update configuration.
package struct BelugaReleaseConfiguration: Equatable, Sendable {
    package let version: String
    package let build: UInt64
    package let feedURL: URL
    package let publicKey: Data

    /// Only for comparing the retained predecessor broker after replacement.
    /// Feed and verification key are preserved; this does not attest provenance.
    package func predecessor(version: String, build: UInt64) throws -> Self {
        try Self(info: ["CFBundleShortVersionString": version, "CFBundleVersion": String(build),
            "SUFeedURL": feedURL.absoluteString, "SUPublicEDKey": publicKey.base64EncodedString(),
            "SUVerifyUpdateBeforeExtraction": true, "SURequireSignedFeed": true,
            "SUAllowsAutomaticUpdates": false])
    }

    package init(info: [String: Any]) throws {
        guard let version = info["CFBundleShortVersionString"] as? String,
              Self.isSemanticVersion(version),
              let buildString = info["CFBundleVersion"] as? String,
              let build = UInt64(buildString), build > 0,
              String(build) == buildString,
              let rawFeed = info["SUFeedURL"] as? String,
              let components = URLComponents(string: rawFeed),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port == nil || components.port == 443,
              !host.hasSuffix(".invalid"), !host.hasSuffix(".example"),
              host != "localhost", components.path.hasSuffix("/appcast.xml"),
              let feedURL = components.url,
              let keyString = info["SUPublicEDKey"] as? String,
              let key = Data(base64Encoded: keyString), key.count == 32,
              key.base64EncodedString() == keyString,
              key.contains(where: { $0 != 0 }),
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SURequireSignedFeed"] as? Bool == true,
              info["SUAllowsAutomaticUpdates"] as? Bool == false else {
            throw ConfigurationError.invalidDistributionConfiguration
        }
        self.version = version
        self.build = build
        self.feedURL = feedURL
        publicKey = key
    }

    static func isSemanticVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy {
            guard let number = UInt32($0) else { return false }
            return String(number) == $0
        }
    }

    enum ConfigurationError: Error {
        case invalidDistributionConfiguration
    }
}

/// A stream, pending invitation, or incomplete teardown cannot be interrupted by an update.
package struct BelugaUpdateAdmission: Equatable, Sendable {
    package var isInteractiveApplication = false
    package var hasActiveMedia = false
    package var hasPendingPairing = false
    package var hasAudioShares = false
    package var teardownComplete = false

    package init(isInteractiveApplication: Bool = false, hasActiveMedia: Bool = false,
                 hasPendingPairing: Bool = false, hasAudioShares: Bool = false,
                 teardownComplete: Bool = false) {
        self.isInteractiveApplication = isInteractiveApplication
        self.hasActiveMedia = hasActiveMedia
        self.hasPendingPairing = hasPendingPairing
        self.hasAudioShares = hasAudioShares
        self.teardownComplete = teardownComplete
    }

    package var permitsUpdate: Bool {
        isInteractiveApplication && teardownComplete &&
            !hasActiveMedia && !hasPendingPairing && !hasAudioShares
    }
}
