#if os(macOS)
import Foundation
import XCTest
@testable import WebRTCTransport

final class WebRTCAudioShareSenderTests: XCTestCase {
    /// Uses only the caller-fed custom ADM: no physical microphone, speaker, HAL driver or phone.
    func testNativeOfferHasExactlyOneSendOnlyStereoAudioTrackAndNoReceiveOrControlTopology() async throws {
        let sender = try WebRTCAudioShareSender(iceServers: [], expiresAt: Date().addingTimeInterval(60))
        do {
            let offer = try await sender.createOffer()
            XCTAssertEqual(try AudioShareSDP.validate(offer, direction: "sendonly"), "0")
            XCTAssertEqual(offer.components(separatedBy: "m=audio").count - 1, 1)
            XCTAssertFalse(offer.contains("m=video"))
            XCTAssertFalse(offer.contains("m=application"))
            XCTAssertFalse(offer.contains("a=recvonly"))
            XCTAssertFalse(offer.contains("a=sendrecv"))
            XCTAssertTrue(offer.contains("stereo=1"))
            XCTAssertTrue(offer.contains("maxaveragebitrate=192000"))
            await sender.close()
        } catch {
            await sender.close()
            throw error
        }
    }

    func testOfferAndReceiveOnlyAnswerHaveOneStereoOpusSection() throws {
        XCTAssertEqual(try AudioShareSDP.validate(sdp(direction: "sendonly"), direction: "sendonly"), "0")
        XCTAssertEqual(try AudioShareSDP.validate(sdp(direction: "recvonly"), direction: "recvonly"), "0")
    }

    func testSDPRejectsEveryUnexpectedMediaAndControlTopology() {
        let answer = sdp(direction: "recvonly")
        let bad = [
            answer + "\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=rtpmap:96 H264/90000",
            answer + "\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel",
            answer + "\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111",
            answer + "\r\na=sctp-port:5000",
            answer + "\r\na=dcmap:0 label=control",
            answer + "\r\na=opensteamer.screen-diagnostics:v1",
            answer.replacingOccurrences(of: "a=recvonly", with: "a=sendrecv"),
            answer.replacingOccurrences(of: "a=recvonly", with: "a=sendonly"),
            answer.replacingOccurrences(of: "a=recvonly", with: "a=inactive"),
            answer.replacingOccurrences(of: "a=recvonly\r\n", with: ""),
            answer + "\r\na=sendonly",
            answer.replacingOccurrences(of: "m=audio 9", with: "m=audio 0")
        ]
        for candidate in bad {
            XCTAssertThrowsError(try AudioShareSDP.validate(candidate, direction: "recvonly"))
        }
    }

    func testSDPRejectsAmbiguousMidBundleAndNonOpusCodec() {
        let answer = sdp(direction: "recvonly")
        for candidate in [
            answer + "\r\na=mid:other",
            answer.replacingOccurrences(of: "a=group:BUNDLE 0", with: "a=group:BUNDLE 0 other"),
            answer.replacingOccurrences(of: "opus/48000/2", with: "opus/48000/1"),
            answer.replacingOccurrences(of: "opus/48000/2", with: "PCMU/8000"),
            answer.replacingOccurrences(of: "SAVPF 111", with: "SAVPF 111 111"),
            answer.replacingOccurrences(of: "a=ice-ufrag:remote\r\n", with: ""),
            answer + "\r\na=ice-ufrag:different",
            answer + "\0",
            String(repeating: "v=0\r\n", count: 60_000)
        ] {
            XCTAssertThrowsError(try AudioShareSDP.validate(candidate, direction: "recvonly"))
        }
    }

    func testRevocationIsTerminalEvenWhileNativeTransportRemainsConnected() throws {
        let probe = ShareGateProbe()
        let gate = makeGate(probe)
        gate.observe(peerConnected: true, iceConnected: true)
        let epoch = try gate.beginAdmission {}
        try gate.commit(epoch) {}
        gate.capture { probe.capture() }
        XCTAssertEqual(probe.captures, 1)
        gate.revoke()
        gate.capture { probe.capture() }
        gate.observe(peerConnected: true, iceConnected: true)
        XCTAssertThrowsError(try gate.beginAdmission {})
        XCTAssertThrowsError(try gate.commit(epoch) {})
        XCTAssertEqual(probe.captures, 1)
    }

    func testDeadlineRejectsCaptureAndAdmissionWithoutWaitingForEventLoopTimer() throws {
        let probe = ShareGateProbe()
        let gate = makeGate(probe)
        gate.observe(peerConnected: true, iceConnected: true)
        let epoch = try gate.beginAdmission {}
        try gate.commit(epoch) {}
        probe.time = 100
        gate.capture { probe.capture() }
        XCTAssertEqual(probe.captures, 0)
        XCTAssertThrowsError(try gate.requireLive())
        probe.time = 1 // A wall-clock/clock fixture rollback cannot revive terminal admission.
        XCTAssertThrowsError(try gate.beginAdmission {})
    }

    func testTransportUncertaintyInvalidatesExactPendingAndActiveAdmission() throws {
        for peerLoss in [true, false] {
            let probe = ShareGateProbe()
            let gate = makeGate(probe)
            gate.observe(peerConnected: true, iceConnected: true)
            let old = try gate.beginAdmission {}
            if peerLoss { gate.observe(peerConnected: false) }
            else { gate.observe(iceConnected: false) }
            XCTAssertThrowsError(try gate.commit(old) {})
            gate.capture { probe.capture() }
            gate.observe(peerConnected: true, iceConnected: true)
            XCTAssertThrowsError(try gate.commit(old) {})
            let fresh = try gate.beginAdmission {}
            try gate.commit(fresh) {}
            gate.capture { probe.capture() }
            XCTAssertEqual(probe.captures, 1)
            gate.observe(iceConnected: false)
            gate.capture { probe.capture() }
            XCTAssertEqual(probe.captures, 1)
        }
    }

    func testLateFailedAdmissionCannotDisableSuccessor() throws {
        let probe = ShareGateProbe()
        let gate = makeGate(probe)
        gate.observe(peerConnected: true, iceConnected: true)
        let old = try gate.beginAdmission {}
        let current = try gate.beginAdmission {}
        try gate.commit(current) {}
        let baseline = probe.disables
        gate.cancelAdmission(old)
        gate.capture { probe.capture() }
        XCTAssertEqual(probe.captures, 1)
        XCTAssertEqual(probe.disables, baseline)
    }

    func testFailedNativeGenerationApprovalDoesNotAdmitPCM() throws {
        let probe = ShareGateProbe()
        let gate = makeGate(probe)
        gate.observe(peerConnected: true, iceConnected: true)
        let epoch = try gate.beginAdmission {}
        XCTAssertThrowsError(try gate.commit(epoch) {
            throw WebRTCAudioShareSenderError.recordingAdmissionFailed
        })
        gate.capture { probe.capture() }
        XCTAssertEqual(probe.captures, 0)
    }

    /// A held-mutex version deadlocks here: delivery synchronously enters a different native
    /// callback queue whose revocation must return before delivery can exit.
    func testForeignQueueReentrantRevokeReturnsAndCleansOnlyAfterNativeDeliveryExits() async throws {
        let probe = ShareGateProbe()
        let gate = makeGate(probe)
        gate.observe(peerConnected: true, iceConnected: true)
        let epoch = try gate.beginAdmission {}
        try gate.commit(epoch) {}
        let baseline = probe.disables
        let finished = expectation(description: "foreign-queue revoke returned and delivery drained")
        DispatchQueue.global().async {
            gate.capture {
                probe.beginDelivery()
                DispatchQueue(label: "beluga.share.reentrant-revoke").sync {
                    gate.revoke()
                    gate.capture { probe.capture() }
                }
                probe.endDelivery()
            }
            finished.fulfill()
        }
        let waitResult = await XCTWaiter.fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(waitResult, .completed, "A reentrant callback must not wait on a delivery-held mutex")
        guard waitResult == .completed else { return }
        await gate.waitForQuiescence()
        XCTAssertEqual(probe.disables, baseline + 1)
        XCTAssertEqual(probe.cleanupInsideDelivery, 0)
        XCTAssertEqual(probe.captures, 0)
        XCTAssertThrowsError(try gate.beginAdmission {})
    }

    func testReentrantTransportRecoveryCannotGrantUntilPriorLeaseAndNativeCleanupRetire() async throws {
        let probe = ShareGateProbe()
        let gate = makeGate(probe)
        gate.observe(peerConnected: true, iceConnected: true)
        let epoch = try gate.beginAdmission {}
        try gate.commit(epoch) {}
        let finished = expectation(description: "transport callback cannot reopen inside delivery")
        DispatchQueue.global().async {
            gate.capture {
                probe.beginDelivery()
                DispatchQueue(label: "beluga.share.reentrant-recovery").sync {
                    gate.observe(iceConnected: false)
                    gate.observe(iceConnected: true)
                    do {
                        _ = try gate.beginAdmission {}
                        XCTFail("Reentrant recovery must not grant during an active native lease")
                    } catch { /* Expected until delivery and cleanup have retired. */ }
                    gate.capture { probe.capture() }
                }
                probe.endDelivery()
            }
            finished.fulfill()
        }
        let waitResult = await XCTWaiter.fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(waitResult, .completed, "Recovery callbacks must return before native delivery exits")
        guard waitResult == .completed else { return }
        await gate.waitForQuiescence()
        XCTAssertEqual(probe.cleanupInsideDelivery, 0)
        XCTAssertEqual(probe.captures, 0)
        let fresh = try gate.beginAdmission {}
        try gate.commit(fresh) {}
        gate.capture { probe.capture() }
        XCTAssertEqual(probe.captures, 1)
    }

    func testNativeCleanupItselfMayReenterWithoutLockInversionOrAdmission() throws {
        let box = ShareGateBox()
        let probe = ShareGateProbe()
        let gate = AudioShareCaptureGate(deadline: 100, now: { probe.time }) {
            probe.disable()
            box.value?.observe(iceConnected: false)
        }
        box.value = gate
        gate.observe(peerConnected: true, iceConnected: true)
        // The cleanup callback invalidates this exact attempt; it never grants on a setter ACK.
        XCTAssertThrowsError(try gate.beginAdmission {})
        XCTAssertEqual(probe.cleanupInsideDelivery, 0)
        gate.revoke()
        box.value = nil
    }

    private func makeGate(_ probe: ShareGateProbe) -> AudioShareCaptureGate {
        AudioShareCaptureGate(deadline: 100, now: { probe.time }, disable: { probe.disable() })
    }

    private func sdp(direction: String) -> String {
        ["v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=-", "t=0 0", "a=group:BUNDLE 0",
         "m=audio 9 UDP/TLS/RTP/SAVPF 111", "c=IN IP4 0.0.0.0", "a=mid:0",
         "a=ice-ufrag:remote", "a=ice-pwd:abcdefghijklmnopqrstuv", "a=rtcp-mux",
         "a=\(direction)", "a=rtpmap:111 opus/48000/2", "a=fmtp:111 stereo=1;sprop-stereo=1;maxaveragebitrate=192000", ""]
            .joined(separator: "\r\n")
    }
}

private final class ShareGateProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var timestamp: UInt64 = 1
    private var captureCount = 0
    private var disableCount = 0
    private var deliveryActive = false
    private var cleanupDuringDelivery = 0
    var time: UInt64 {
        get { lock.withLock { timestamp } }
        set { lock.withLock { timestamp = newValue } }
    }
    var captures: Int { lock.withLock { captureCount } }
    var disables: Int { lock.withLock { disableCount } }
    var cleanupInsideDelivery: Int { lock.withLock { cleanupDuringDelivery } }
    func capture() { lock.withLock { captureCount += 1 } }
    func disable() {
        lock.withLock {
            disableCount += 1
            if deliveryActive { cleanupDuringDelivery += 1 }
        }
    }
    func beginDelivery() { lock.withLock { deliveryActive = true } }
    func endDelivery() { lock.withLock { deliveryActive = false } }
}

private final class ShareGateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AudioShareCaptureGate?
    var value: AudioShareCaptureGate? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
#endif
