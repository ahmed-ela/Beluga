import Foundation
import XCTest
@testable import CaptureServer

final class BelugaAudioShareCryptoTests: XCTestCase {
    private let root = Data(0..<32)
    private let context = BelugaAudioShareSignalContext(shareID: "AAAAAAAAAAAAAAAAAAAAAA",
        generation: "AQEBAQEBAQEBAQEBAQEBAQ", listenerID: "AgICAgICAgICAgICAgICAg", expiresAt: 1_800_000_000_000)

    func testMatchesIndependentBrowserHKDFAndAESGCMVector() throws {
        XCTAssertEqual(try BelugaAudioShareMaterial.admissionProof(root: root, shareID: context.shareID,
            role: "listener"), "ztdcAgQb_Fbd8WAiEAka4nBJRr-5LGkUf5dhCmHmo0c")
        let cipher = try BelugaAudioShareSignalCipher(root: root, context: context)
        let payload = Data(#"{"kind":"offer","sdp":"test vector"}"#.utf8)
        var envelope = try cipher.seal(payload)
        XCTAssertEqual(envelope.ciphertext,
            "lngWKN2fHK-lloIhiUDHavf7IcJMvOZQDC6N8P9hXEsZhdTfxEsmZRhb6pP9udon8GVGDQ")
        envelope.from = "owner"
        let browser = try BelugaAudioShareSignalCipher(root: root, context: context, role: "listener")
        XCTAssertEqual(try browser.open(envelope), payload)
        XCTAssertThrowsError(try browser.open(envelope), "Replay must retire the channel")
        XCTAssertThrowsError(try browser.seal(payload))
    }

    func testGenerationListenerExpiryDirectionAndKeyAreAuthenticated() throws {
        let payload = Data("valid nonempty plaintext".utf8)
        var envelope = try BelugaAudioShareSignalCipher(root: root, context: context).seal(payload)
        envelope.from = "owner"
        let alternatives = [
            BelugaAudioShareSignalContext(shareID: context.shareID, generation: context.listenerID,
                listenerID: context.listenerID, expiresAt: context.expiresAt),
            BelugaAudioShareSignalContext(shareID: context.shareID, generation: context.generation,
                listenerID: context.generation, expiresAt: context.expiresAt),
            BelugaAudioShareSignalContext(shareID: context.shareID, generation: context.generation,
                listenerID: context.listenerID, expiresAt: context.expiresAt + 1)
        ]
        for other in alternatives {
            XCTAssertThrowsError(try BelugaAudioShareSignalCipher(root: root, context: other,
                                                                 role: "listener").open(envelope))
        }
        XCTAssertThrowsError(try BelugaAudioShareSignalCipher(root: Data(repeating: 9, count: 32),
            context: context, role: "listener").open(envelope))
        XCTAssertThrowsError(try BelugaAudioShareSignalCipher(root: root, context: context).open(envelope))
    }

    func testCapabilityOnlyInFragmentAndSecretsAreRedacted() throws {
        let material = try BelugaAudioShareMaterial()
        let url = try material.listenerURL(origin: XCTUnwrap(URL(string: "https://host.test")))
        XCTAssertNil(url.query)
        XCTAssertEqual(url.path, "/audio-share")
        XCTAssertTrue(url.fragment?.contains("k=") == true)
        XCTAssertFalse(String(reflecting: material).contains(BelugaAudioShareEncoding.encode(material.listenerSecret)))
        XCTAssertNotEqual(material.ownerSecret, material.listenerSecret)
        XCTAssertNotEqual(try material.admissionProof(owner: true), try material.admissionProof(owner: false))
        XCTAssertThrowsError(try material.listenerURL(origin: XCTUnwrap(URL(string: "http://host.test"))))
        for value in ["AA==", "AA+_", String(repeating: "a", count: 99), ""] {
            XCTAssertThrowsError(try BelugaAudioShareEncoding.decode(value, count: 16...16))
        }
    }

    func testShareLocatorContainsBigEndianCreationFenceAndIndependentRandomTail() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000.875)
        let first = try BelugaAudioShareMaterial(now: date)
        let second = try BelugaAudioShareMaterial(now: date)
        let bytes = try BelugaAudioShareEncoding.decode(first.shareID, count: 16...16)
        XCTAssertEqual(bytes.prefix(4), Data([0x6b, 0x49, 0xd2, 0x00]))
        XCTAssertNotEqual(first.shareID, second.shareID)
        XCTAssertThrowsError(try BelugaAudioShareMaterial(now: Date(timeIntervalSince1970: 0)))
        XCTAssertThrowsError(try BelugaAudioShareMaterial(now: Date(timeIntervalSince1970: .infinity)))
        XCTAssertThrowsError(try BelugaAudioShareMaterial(now: Date(timeIntervalSince1970: 4_294_967_296)))
    }
}
