import Foundation

/// Additive source-catalog support must echo the exact base media authorization. Legacy peers
/// still negotiate their single-item lane and never receive secondary-source authority.
enum RemoteMediaCatalogSDP {
    static let attributePrefix = "a=x-opensteamer-remote-media-catalog:"

    static func advertising(in sdp: String, authorization: WebRTCRemoteMediaAuthorization) -> String {
        if advertisedAuthorization(in: sdp) == authorization { return sdp }
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"
        var lines = sdp.components(separatedBy: separator)
        let index = lines.firstIndex(where: { $0.hasPrefix("m=") }) ?? lines.endIndex
        lines.insert(attributePrefix + "1:" + authorization.id.uuidString.lowercased(), at: index)
        return lines.joined(separator: separator)
    }

    static func advertisedAuthorization(in sdp: String) -> WebRTCRemoteMediaAuthorization? {
        var value: String?
        for line in sdp.components(separatedBy: .newlines) {
            if line.hasPrefix("m=") { break }
            guard line.hasPrefix(attributePrefix) else { continue }
            guard value == nil else { return nil }
            value = String(line.dropFirst(attributePrefix.count))
        }
        guard let value else { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "1" else { return nil }
        let raw = String(parts[1])
        guard raw.count == 36, let id = UUID(uuidString: raw), id.uuidString.lowercased() == raw else { return nil }
        return WebRTCRemoteMediaAuthorization(id: id)
    }

    static func negotiated(hostOfferSDP: String, viewerAnswerSDP: String) -> Bool {
        guard let base = RemoteMediaControlsSDP.negotiatedAuthorization(
            hostOfferSDP: hostOfferSDP, viewerAnswerSDP: viewerAnswerSDP
        ) else { return false }
        return advertisedAuthorization(in: hostOfferSDP) == base
            && advertisedAuthorization(in: viewerAnswerSDP) == base
    }
}
