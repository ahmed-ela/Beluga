import Foundation

/// Optional heartbeat fields require an exact echo of the already negotiated diagnostics nonce.
enum RemoteMediaPipelineDiagnosticsSDP {
    static let attributePrefix = "a=x-opensteamer-remote-media-pipeline-diagnostics:"

    static func advertisingHostSupport(in sdp: String) -> String {
        guard let authorization = AudioClientDiagnosticsSDP.authorization(in: sdp) else { return sdp }
        return advertising(in: sdp, authorization: authorization)
    }

    static func advertisingViewerSupport(in sdp: String, hostOfferSDP: String) -> String {
        guard let authorization = advertisedAuthorization(in: hostOfferSDP),
              AudioClientDiagnosticsSDP.authorization(in: hostOfferSDP) == authorization,
              AudioClientDiagnosticsSDP.authorization(in: sdp) == authorization else { return sdp }
        return advertising(in: sdp, authorization: authorization)
    }

    static func negotiated(hostOfferSDP: String, viewerAnswerSDP: String) -> Bool {
        guard let authorization = AudioClientDiagnosticsSDP.negotiatedAuthorization(
            hostOfferSDP: hostOfferSDP, viewerAnswerSDP: viewerAnswerSDP
        ) else { return false }
        return advertisedAuthorization(in: hostOfferSDP) == authorization
            && advertisedAuthorization(in: viewerAnswerSDP) == authorization
    }

    static func advertisedAuthorization(in sdp: String) -> UUID? {
        let lines = sdp.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let markers = lines.filter { $0.hasPrefix(attributePrefix) }
        let session = lines.prefix { !$0.hasPrefix("m=") }
        guard markers.count == 1, session.contains(markers[0]) else { return nil }
        let parts = markers[0].dropFirst(attributePrefix.count)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "1" else { return nil }
        let raw = String(parts[1])
        guard raw.count == 36, let authorization = UUID(uuidString: raw),
              authorization.uuidString.lowercased() == raw else { return nil }
        return authorization
    }

    private static func advertising(in sdp: String, authorization: UUID) -> String {
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"
        var lines = sdp.components(separatedBy: separator)
        guard !lines.contains(where: { $0.hasPrefix(attributePrefix) }) else { return sdp }
        let index = lines.firstIndex { $0.hasPrefix("m=") } ?? lines.endIndex
        lines.insert(attributePrefix + "1:" + authorization.uuidString.lowercased(), at: index)
        return lines.joined(separator: separator)
    }
}
