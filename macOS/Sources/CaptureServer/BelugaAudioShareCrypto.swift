import CryptoKit
import Foundation

enum BelugaAudioShareProtocolError: Error { case invalidMessage, unavailable }

enum BelugaAudioShareEncoding {
    static let domain = "Beluga.AudioShare.v1"
    static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ string: String, count: ClosedRange<Int>) throws -> Data {
        guard string.utf8.count <= (count.upperBound * 4 + 2) / 3,
              !string.isEmpty, string.utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                    || $0 == 45 || $0 == 95
              }) else { throw BelugaAudioShareProtocolError.invalidMessage }
        let base = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let bytes = Data(base64Encoded: base + String(repeating: "=", count: (4 - base.count % 4) % 4)),
              count.contains(bytes.count), encode(bytes) == string else {
            throw BelugaAudioShareProtocolError.invalidMessage
        }
        return bytes
    }
    static func derive(root: Data, shareID: String, label: String) throws -> SymmetricKey {
        guard root.count == 32 else { throw BelugaAudioShareProtocolError.invalidMessage }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: root),
            salt: try decode(shareID, count: 16...16),
            info: Data("\(domain)\0\(label)".utf8), outputByteCount: 32)
    }
}

/// Independent in-memory roots. Neither is put in request URLs or diagnostics; only the
/// listener root is deliberately exposed when the user copies the fragment-bearing link.
struct BelugaAudioShareMaterial: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let shareID: String
    let ownerSecret: Data
    let listenerSecret: Data
    init(now: Date = Date()) throws {
        let seconds = floor(now.timeIntervalSince1970)
        guard seconds.isFinite, seconds > 0, seconds <= Double(UInt32.max) else {
            throw BelugaAudioShareProtocolError.unavailable
        }
        // A public creation fence permits bounded server tombstone retention without reviving
        // expired links. The 96 random locator bits are not authorization: each independent
        // capability still has 256 secret bits. The server bounds allowed creation-clock skew.
        let born = UInt32(seconds)
        let locator = Data([UInt8(truncatingIfNeeded: born >> 24),
                            UInt8(truncatingIfNeeded: born >> 16),
                            UInt8(truncatingIfNeeded: born >> 8), UInt8(truncatingIfNeeded: born)])
            + Self.random(count: 12)
        shareID = BelugaAudioShareEncoding.encode(locator)
        ownerSecret = Self.random(count: 32)
        var listener = Self.random(count: 32)
        while listener == ownerSecret { listener = Self.random(count: 32) }
        listenerSecret = listener
    }
    private static func random(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
    func admissionProof(owner: Bool) throws -> String {
        try Self.admissionProof(root: owner ? ownerSecret : listenerSecret, shareID: shareID,
                                role: owner ? "owner" : "listener")
    }
    static func admissionProof(root: Data, shareID: String, role: String) throws -> String {
        guard role == "owner" || role == "listener" else { throw BelugaAudioShareProtocolError.invalidMessage }
        let key = try BelugaAudioShareEncoding.derive(root: root, shareID: shareID,
                                                     label: "admission\0\(role)")
        return key.withUnsafeBytes { BelugaAudioShareEncoding.encode(Data($0)) }
    }
    func listenerURL(origin: URL) throws -> URL {
        guard var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host != nil, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw BelugaAudioShareProtocolError.invalidMessage }
        parts.path = "/audio-share"
        parts.fragment = "v=1&id=\(shareID)&k=\(BelugaAudioShareEncoding.encode(listenerSecret))"
        guard let url = parts.url else { throw BelugaAudioShareProtocolError.invalidMessage }
        return url
    }
    var description: String { "<redacted audio-share material>" }
    var debugDescription: String { description }
}

struct BelugaAudioShareSignalContext: Equatable, Sendable {
    let shareID: String
    let generation: String
    let listenerID: String
    let expiresAt: Int64
    func validate() throws {
        for id in [shareID, generation, listenerID] { _ = try BelugaAudioShareEncoding.decode(id, count: 16...16) }
        guard expiresAt > 0, expiresAt <= 9_007_199_254_740_991 else {
            throw BelugaAudioShareProtocolError.invalidMessage
        }
    }
}

struct BelugaAudioShareSignalEnvelope: Codable, Sendable {
    let type: String
    let v: Int
    let listenerID: String
    let seq: UInt32
    let ciphertext: String
    var from: String?
}

/// AES-GCM directional keys bind the absolute expiry and exact listener generation. A lock
/// serializes nonce consumption; malformed/replayed inbound messages permanently retire it.
final class BelugaAudioShareSignalCipher: @unchecked Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    private let lock = NSLock()
    private let context: BelugaAudioShareSignalContext
    private let role: String
    private let outboundDirection: String
    private let inboundDirection: String
    private var outboundKey: SymmetricKey?
    private var inboundKey: SymmetricKey?
    private var sendSequence: UInt32 = 0
    private var receiveSequence: UInt32 = 0

    init(root: Data, context: BelugaAudioShareSignalContext, role: String = "owner") throws {
        try context.validate()
        guard role == "owner" || role == "listener" else { throw BelugaAudioShareProtocolError.invalidMessage }
        self.context = context
        self.role = role
        outboundDirection = role == "owner" ? "ownerToListener" : "listenerToOwner"
        inboundDirection = role == "owner" ? "listenerToOwner" : "ownerToListener"
        let label = "signal\0\(context.generation)\0\(context.listenerID)\0\(context.expiresAt)\0"
        outboundKey = try BelugaAudioShareEncoding.derive(root: root, shareID: context.shareID,
                                                         label: label + outboundDirection)
        inboundKey = try BelugaAudioShareEncoding.derive(root: root, shareID: context.shareID,
                                                        label: label + inboundDirection)
    }

    func seal(_ plaintext: Data) throws -> BelugaAudioShareSignalEnvelope {
        try lock.withLock {
            guard let outboundKey, sendSequence <= 2_147_483_647,
                  !plaintext.isEmpty, plaintext.count <= 49_152 else {
                throw BelugaAudioShareProtocolError.invalidMessage
            }
            let sequence = sendSequence
            sendSequence += 1
            let box = try AES.GCM.seal(plaintext, using: outboundKey, nonce: nonce(sequence),
                                       authenticating: aad(outboundDirection, sequence))
            return .init(type: "signal", v: 1, listenerID: context.listenerID, seq: sequence,
                         ciphertext: BelugaAudioShareEncoding.encode(box.ciphertext + box.tag))
        }
    }

    func open(_ message: BelugaAudioShareSignalEnvelope) throws -> Data {
        try lock.withLock {
            do {
                guard let inboundKey, message.type == "signal", message.v == 1,
                      message.from == (role == "owner" ? "listener" : "owner"),
                      message.listenerID == context.listenerID, message.seq == receiveSequence,
                      message.seq <= 2_147_483_647 else { throw BelugaAudioShareProtocolError.invalidMessage }
                let bytes = try BelugaAudioShareEncoding.decode(message.ciphertext, count: 17...65_536)
                receiveSequence += 1
                let box = try AES.GCM.SealedBox(nonce: nonce(message.seq),
                                                ciphertext: bytes.dropLast(16), tag: bytes.suffix(16))
                let plaintext = try AES.GCM.open(box, using: inboundKey,
                                                 authenticating: aad(inboundDirection, message.seq))
                guard plaintext.count <= 49_152 else { throw BelugaAudioShareProtocolError.invalidMessage }
                return plaintext
            } catch {
                outboundKey = nil; inboundKey = nil
                throw BelugaAudioShareProtocolError.invalidMessage
            }
        }
    }
    func close() { lock.withLock { outboundKey = nil; inboundKey = nil } }
    private func nonce(_ sequence: UInt32) throws -> AES.GCM.Nonce {
        var bigEndian = sequence.bigEndian
        let suffix = withUnsafeBytes(of: &bigEndian) { Data($0) }
        return try AES.GCM.Nonce(data: Data(repeating: 0, count: 8) + suffix)
    }
    private func aad(_ direction: String, _ sequence: UInt32) -> Data {
        Data("\(BelugaAudioShareEncoding.domain)\0\(context.shareID)\0\(context.generation)\0\(context.listenerID)\0\(context.expiresAt)\0\(direction)\0\(sequence)".utf8)
    }
    var description: String { "<redacted audio-share cipher>" }
    var debugDescription: String { description }
}
