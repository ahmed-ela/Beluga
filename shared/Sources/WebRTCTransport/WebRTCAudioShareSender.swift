#if os(macOS)
@preconcurrency import LiveKitWebRTC
import AVFoundation
import CoreMedia
import Dispatch
import Foundation
import MacWebRTCAudioDeviceShim
import RemoteSessionCore

/// Audio sharing has no phone microphone, screen, command channel, or pairing authority.
public enum WebRTCAudioShareEvent: Sendable {
    case localCandidate(RemoteICECandidate)
    case peerStateChanged(WebRTCPeerState)
    case iceStateChanged(WebRTCICEState)
    case iceGatheringStateChanged(WebRTCICEGatheringState)
    case captureRevoked
    case failure(String)
}

public enum WebRTCAudioShareSenderError: Error, Equatable, Sendable {
    case invalidLifetime
    case closed
    case invalidNegotiation
    case invalidSessionDescription
    case invalidCandidate
    case transportNotHealthy
    case recordingAdmissionFailed
    case nativeCallbackTimedOut
}

/// Metadata-only lock plus exact native-operation leases. No mutex spans queue.sync, native
/// delivery, track setters or ADM revoke. Reentrant native callbacks revoke logical admission
/// immediately; the last already-admitted operation performs cleanup after native delivery exits.
/// A new grant cannot begin while a lease or cleanup remains, and close awaits that exact barrier.
final class AudioShareCaptureGate: @unchecked Sendable {
    private let lock = NSLock()
    private let deadline: UInt64
    private let now: @Sendable () -> UInt64
    private let disable: @Sendable () -> Void
    private var terminal = false
    private var admitted = false
    private var peerConnected = false
    private var iceConnected = false
    private var epoch: UInt64 = 0
    private var inFlight = 0
    private var cleanupRequired = false
    private var cleanupInProgress = false
    private var retirementWaiters: [CheckedContinuation<Void, Never>] = []

    init(deadline: UInt64, now: @escaping @Sendable () -> UInt64 = {
        DispatchTime.now().uptimeNanoseconds
    }, disable: @escaping @Sendable () -> Void) {
        self.deadline = deadline
        self.now = now
        self.disable = disable
    }

    private func isLiveLocked() -> Bool {
        if !terminal, now() >= deadline {
            terminal = true
            admitted = false
            epoch &+= 1
            cleanupRequired = true
        }
        return !terminal
    }

    func requireLive() throws {
        let live = lock.withLock { isLiveLocked() }
        drainNativeCleanup()
        guard live else { throw WebRTCAudioShareSenderError.closed }
    }

    func beginAdmission(enableTrack: () -> Void) throws -> UInt64 {
        let selected: UInt64? = lock.withLock {
            guard isLiveLocked(), peerConnected, iceConnected, inFlight == 0,
                  !cleanupRequired, !cleanupInProgress else { return nil }
            epoch &+= 1
            admitted = false
            return epoch
        }
        guard let selected else {
            drainNativeCleanup()
            throw WebRTCAudioShareSenderError.transportNotHealthy
        }
        try withAdmissionAttempt(selected) {
            disable()
            enableTrack()
        }
        return selected
    }

    func withAdmissionAttempt<T>(_ expected: UInt64, _ operation: () throws -> T) throws -> T {
        try takeAdmissionLease(expected)
        let result = Result { try operation() }
        let failed: Bool
        if case .failure = result { failed = true } else { failed = false }
        let stillCurrent = finishAdmissionLease(expected, commit: false, failed: failed)
        switch result {
        case .failure(let error): throw error
        case .success(let value):
            guard stillCurrent else { throw WebRTCAudioShareSenderError.transportNotHealthy }
            return value
        }
    }

    func commit(_ expected: UInt64, approve: () throws -> Void) throws {
        try takeAdmissionLease(expected)
        let result = Result { try approve() }
        let failed: Bool
        if case .failure = result { failed = true } else { failed = false }
        let stillCurrent = finishAdmissionLease(expected, commit: true, failed: failed)
        try result.get()
        guard stillCurrent else { throw WebRTCAudioShareSenderError.transportNotHealthy }
    }

    private func takeAdmissionLease(_ expected: UInt64) throws {
        let acquired = lock.withLock {
            guard isLiveLocked(), epoch == expected, peerConnected, iceConnected,
                  inFlight == 0, !cleanupRequired, !cleanupInProgress else { return false }
            inFlight = 1
            return true
        }
        guard acquired else {
            drainNativeCleanup()
            throw WebRTCAudioShareSenderError.transportNotHealthy
        }
    }

    private func finishAdmissionLease(_ expected: UInt64, commit: Bool, failed: Bool) -> Bool {
        let current = lock.withLock {
            let current = isLiveLocked() && epoch == expected && peerConnected && iceConnected
                && !cleanupRequired && !cleanupInProgress && !failed
            if current, commit { admitted = true }
            if !current {
                admitted = false
                cleanupRequired = true
                if epoch == expected { epoch &+= 1 }
            }
            inFlight -= 1
            return current
        }
        drainNativeCleanup()
        return current
    }

    func cancelAdmission(_ expected: UInt64) {
        lock.withLock {
            guard epoch == expected else { return }
            epoch &+= 1
            admitted = false
            cleanupRequired = true
        }
        drainNativeCleanup()
    }

    func observe(peerConnected: Bool? = nil, iceConnected: Bool? = nil) {
        lock.withLock {
            guard !terminal else { return }
            let changed = (peerConnected != nil && peerConnected != self.peerConnected)
                || (iceConnected != nil && iceConnected != self.iceConnected)
            if let peerConnected { self.peerConnected = peerConnected }
            if let iceConnected { self.iceConnected = iceConnected }
            if changed, !self.peerConnected || !self.iceConnected {
                epoch &+= 1
                admitted = false
                cleanupRequired = true
            }
        }
        drainNativeCleanup()
    }

    func capture(_ operation: () -> Void) {
        let acquired = lock.withLock {
            // One borrowed callback only: concurrent producers cannot build a hidden queue.
            guard isLiveLocked(), admitted, peerConnected, iceConnected, inFlight == 0,
                  !cleanupRequired, !cleanupInProgress else { return false }
            inFlight = 1
            return true
        }
        guard acquired else { drainNativeCleanup(); return }
        operation()
        lock.withLock { inFlight -= 1 }
        drainNativeCleanup()
    }

    func revoke() {
        lock.withLock {
            guard !terminal else { return }
            terminal = true
            admitted = false
            epoch &+= 1
            cleanupRequired = true
        }
        drainNativeCleanup()
    }

    /// This is retirement proof, unlike the synchronous logical revoke acknowledgement.
    func waitForQuiescence() async {
        await withCheckedContinuation { continuation in
            let immediate = lock.withLock {
                guard inFlight != 0 || cleanupRequired || cleanupInProgress else { return true }
                retirementWaiters.append(continuation)
                return false
            }
            if immediate { continuation.resume() }
            else { drainNativeCleanup() }
        }
    }

    private func drainNativeCleanup() {
        while true {
            let claimed = lock.withLock {
                guard inFlight == 0, cleanupRequired, !cleanupInProgress else { return false }
                cleanupRequired = false
                cleanupInProgress = true
                return true
            }
            guard claimed else { break }
            // Never called inside an active native lease, including a reentrant delivery callback.
            disable()
            lock.withLock { cleanupInProgress = false }
        }
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard inFlight == 0, !cleanupRequired, !cleanupInProgress else { return [] }
            let ready = retirementWaiters
            retirementWaiters.removeAll()
            return ready
        }
        waiters.forEach { $0.resume() }
    }
}

/// Only this wrapper, not the underlying capturer, is exposed to source fanout owners.
/// PCM and borrowed buffers are neither stored nor allowed to escape a capture callback.
public final class WebRTCAudioShareInput: @unchecked Sendable {
    private let gate: AudioShareCaptureGate
    private let capturer: MacExternalAudioCapturer

    fileprivate init(gate: AudioShareCaptureGate, capturer: MacExternalAudioCapturer) {
        self.gate = gate
        self.capturer = capturer
    }

    public func capture(sampleBuffer: CMSampleBuffer) {
        gate.capture { capturer.capture(sampleBuffer: sampleBuffer) }
    }

    public func capture(
        audioBufferList: UnsafePointer<AudioBufferList>,
        format: AudioStreamBasicDescription,
        frameCount: UInt32,
        presentationTime: CMTime
    ) {
        gate.capture {
            capturer.capture(audioBufferList: audioBufferList, format: format,
                             frameCount: frameCount, presentationTime: presentationTime)
        }
    }
}

/// Native objects are confined to the sender actor for signaling/admission and the capture gate
/// for synchronous revoke. ASMacStereoAudioDevice already fences its generation state with native
/// lifecycle/state mutexes; the capturer owns one serial queue. This wrapper grants no standalone
/// Sendable conformance to native objects and is retained only by their one sender/gate lifetime.
private final class AudioShareNativeRecordingResources: @unchecked Sendable {
    let device: ASMacStereoAudioDevice
    let capturer: MacExternalAudioCapturer
    let track: LKRTCAudioTrack

    init(device: ASMacStereoAudioDevice, capturer: MacExternalAudioCapturer, track: LKRTCAudioTrack) {
        self.device = device
        self.capturer = capturer
        self.track = track
    }

    func disable() {
        capturer.setEnabled(false)
        device.revokeRecordingAdmission()
        track.isEnabled = false
    }
}

/// An immutable handle to SDK signaling commands. LKRTCPeerConnection serializes these public
/// commands on its native signaling threads and invokes asynchronous completions; our actor
/// alone decides operation order/epochs, while bounded callback closures capture this handle,
/// not actor-isolated peer storage. Only explicit close/retirement may race a pending command.
private final class AudioShareNativeSignaling: @unchecked Sendable {
    private let peer: LKRTCPeerConnection
    init(peer: LKRTCPeerConnection) { self.peer = peer }

    func offer(_ completion: @escaping @Sendable (AudioShareNativeDescription) -> Void) {
        peer.offer(for: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { description, error in
            completion(AudioShareNativeDescription(sdp: description?.sdp as String?, failed: error != nil))
        }
    }
    func setLocalOffer(_ sdp: String, completion: @escaping @Sendable (Bool) -> Void) {
        peer.setLocalDescription(LKRTCSessionDescription(type: .offer, sdp: sdp)) { completion($0 == nil) }
    }
    func setRemoteAnswer(_ sdp: String, completion: @escaping @Sendable (Bool) -> Void) {
        peer.setRemoteDescription(LKRTCSessionDescription(type: .answer, sdp: sdp)) { completion($0 == nil) }
    }
    func add(_ candidate: RemoteICECandidate, completion: @escaping @Sendable (Bool) -> Void) {
        peer.add(LKRTCIceCandidate(sdp: candidate.sdp, sdpMLineIndex: 0, sdpMid: candidate.sdpMid)) {
            completion($0 == nil)
        }
    }
    func close() { peer.close() }
}

/// A deliberately separate, one-off sender: one 48 kHz stereo Opus transceiver, send-only.
/// The owner must revoke synchronously on its authenticated signaling socket loss or link revoke,
/// then close asynchronously. No SDP message can allocate a receive/control/video topology.
public actor WebRTCAudioShareSender {
    public nonisolated let events: AsyncStream<WebRTCAudioShareEvent>
    public nonisolated let audioInput: WebRTCAudioShareInput
    private nonisolated let gate: AudioShareCaptureGate
    private let continuation: AsyncStream<WebRTCAudioShareEvent>.Continuation
    private let factory: LKRTCPeerConnectionFactory
    private let peer: LKRTCPeerConnection
    private let signaling: AudioShareNativeSignaling
    private let proxy: AudioShareDelegate
    private let device: ASMacStereoAudioDevice
    private let capturer: MacExternalAudioCapturer
    private let track: LKRTCAudioTrack
    private let transceiver: LKRTCRtpTransceiver
    private var expiryTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var offerStarted = false
    private var answerStarted = false
    private var answerApplied = false
    private var closed = false
    private var remoteMap: ICEUsernameFragmentMap?
    private var localMID: String?
    private var pendingCandidates: [RemoteICECandidate] = []

    public init(iceServers: [RemoteICEServer],
                icePolicy: WebRTCICEPolicy = .directPreferred,
                expiresAt: Date) throws {
        let remaining = expiresAt.timeIntervalSinceNow
        guard remaining.isFinite, remaining > 0, remaining <= 86_400 else {
            throw WebRTCAudioShareSenderError.invalidLifetime
        }
        guard WebRTCRuntime.isInitialized else {
            throw WebRTCTransportError.nativeFailure("WebRTC SSL initialization failed.")
        }
        if icePolicy == .relayOnly,
           !iceServers.flatMap(\.urls).contains(where: {
               $0.hasPrefix("turn:") || $0.hasPrefix("turns:")
           }) { throw WebRTCTransportError.relayPolicyRequiresTURN }
        var nativeError: NSError?
        guard ASMacWebRTCAudioDevicePreflight(&nativeError) else {
            throw WebRTCTransportError.nativeFailure("The pinned stereo audio ABI is unavailable.")
        }
        let nativeDevice = ASMacStereoAudioDevice()
        guard let nativeFactory = ASCreateMacStereoPeerConnectionFactory(
            nil, nil, nativeDevice, &nativeError
        ), let nativeCapturer = MacExternalAudioCapturer(stereoAudioDevice: nativeDevice) else {
            throw WebRTCTransportError.audioTrackCreationFailed
        }
        let source = nativeFactory.audioSource(with: nil)
        let nativeTrack = nativeFactory.audioTrack(with: source, trackId: "system-audio")
        nativeTrack.isEnabled = false
        nativeCapturer.setEnabled(false)
        let recordingResources = AudioShareNativeRecordingResources(
            device: nativeDevice, capturer: nativeCapturer, track: nativeTrack
        )
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(remaining * 1_000_000_000)
        let captureGate = AudioShareCaptureGate(deadline: deadline) {
            // Close source delivery before any native track setter or asynchronous teardown.
            recordingResources.disable()
        }
        let pair = AsyncStream<WebRTCAudioShareEvent>.makeStream(bufferingPolicy: .bufferingNewest(128))
        let delegate = AudioShareDelegate(gate: captureGate, continuation: pair.continuation)
        let config = LKRTCConfiguration()
        config.iceServers = iceServers.map {
            LKRTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential)
        }
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.iceTransportPolicy = icePolicy == .relayOnly ? .relay : .all
        config.continualGatheringPolicy = .gatherContinually
        guard let nativePeer = nativeFactory.peerConnection(
            with: config, constraints: LKRTCMediaConstraints(mandatoryConstraints: nil,
                                                          optionalConstraints: nil), delegate: delegate
        ) else { throw WebRTCTransportError.peerConnectionCreationFailed }
        let settings = LKRTCRtpTransceiverInit()
        settings.direction = .sendOnly
        settings.streamIds = ["audio-share"]
        guard let nativeTransceiver = nativePeer.addTransceiver(with: nativeTrack, init: settings) else {
            nativePeer.close()
            throw WebRTCTransportError.audioTrackCreationFailed
        }
        do {
            let codecs = nativeFactory.rtpSenderCapabilities(forKind: kLKRTCMediaStreamTrackKindAudio)
                .codecs.filter { ($0.mimeType as String).caseInsensitiveCompare("audio/opus") == .orderedSame }
            guard !codecs.isEmpty,
                  nativeTrack.setAudioProcessingOptions(.raw()).isSuccess else {
                throw WebRTCTransportError.audioTrackCreationFailed
            }
            _ = try nativeTransceiver.setCodecPreferences(codecs, error: ())
            try Self.applyBitrate(nativeTransceiver.sender)
        } catch {
            captureGate.revoke()
            nativePeer.close()
            throw error
        }
        events = pair.stream
        continuation = pair.continuation
        gate = captureGate
        audioInput = WebRTCAudioShareInput(gate: captureGate, capturer: nativeCapturer)
        factory = nativeFactory
        peer = nativePeer
        signaling = AudioShareNativeSignaling(peer: nativePeer)
        proxy = delegate
        device = nativeDevice
        capturer = nativeCapturer
        track = nativeTrack
        transceiver = nativeTransceiver
        expiryTask = Task.detached {
            do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            catch { return }
            captureGate.revoke()
            pair.continuation.yield(.captureRevoked)
        }
    }

    deinit {
        gate.revoke()
        expiryTask?.cancel()
        if closeTask == nil {
            let retiringGate = gate
            let retiringSignaling = signaling
            let retiringContinuation = continuation
            Task.detached {
                await retiringGate.waitForQuiescence()
                retiringSignaling.close()
                retiringContinuation.finish()
            }
        }
    }

    public nonisolated func revokeCapture() { gate.revoke() }

    public func createOffer() async throws -> String {
        try requireOpen()
        guard !offerStarted else { throw WebRTCAudioShareSenderError.invalidNegotiation }
        offerStarted = true
        let commands = signaling
        do {
            let reply: AudioShareNativeDescription? = await WebRTCBoundedCallback.value(timeout: .seconds(8)) { resolve in
                commands.offer(resolve)
            }
            try requireOpen()
            guard let reply else { throw WebRTCAudioShareSenderError.nativeCallbackTimedOut }
            guard !reply.failed, let raw = reply.sdp else { throw WebRTCAudioShareSenderError.invalidSessionDescription }
            let sdp = OpusStereoSDP.applyingHighFidelityPolicy(to: raw)
            localMID = try AudioShareSDP.validate(sdp, direction: "sendonly")
            guard let localMapping = ICEUsernameFragmentParser.mapping(inSessionDescription: sdp) else {
                throw WebRTCAudioShareSenderError.invalidSessionDescription
            }
            proxy.installLocalMapping(localMapping)
            let set: Bool? = await WebRTCBoundedCallback.value(timeout: .seconds(8)) { resolve in
                commands.setLocalOffer(sdp, completion: resolve)
            }
            try requireOpen()
            guard set == true else { throw WebRTCAudioShareSenderError.invalidSessionDescription }
            return sdp
        } catch { gate.revoke(); throw error }
    }

    public func setAnswer(_ sdp: String) async throws {
        try requireOpen()
        guard offerStarted, localMID != nil, !answerStarted else {
            gate.revoke()
            throw WebRTCAudioShareSenderError.invalidNegotiation
        }
        answerStarted = true
        let commands = signaling
        do {
            guard try AudioShareSDP.validate(sdp, direction: "recvonly") == localMID,
                  let mapping = ICEUsernameFragmentParser.mapping(inSessionDescription: sdp),
                  mapping.mediaSections.count == 1, !mapping.declaredFragments.isEmpty else {
                throw WebRTCAudioShareSenderError.invalidSessionDescription
            }
            let applied: Bool? = await WebRTCBoundedCallback.value(timeout: .seconds(8)) { resolve in
                commands.setRemoteAnswer(sdp, completion: resolve)
            }
            try requireOpen()
            var direction: LKRTCRtpTransceiverDirection = .stopped
            guard applied == true, peer.transceivers.count == 1,
                  transceiver.currentDirection(&direction), direction == .sendOnly else {
                throw WebRTCAudioShareSenderError.invalidNegotiation
            }
            remoteMap = mapping
            answerApplied = true
            let candidates = pendingCandidates
            pendingCandidates.removeAll()
            for candidate in candidates { try await addICE(candidate) }
            try requireOpen()
        } catch { gate.revoke(); throw error }
    }

    public func addICE(_ candidate: RemoteICECandidate) async throws {
        try requireOpen()
        let commands = signaling
        do {
            guard candidate.sdp.utf8.count <= 2_048,
                  !candidate.sdp.contains(where: { $0.isNewline || $0 == "\0" }),
                  candidate.sdp.hasPrefix("candidate:"), candidate.sdpMLineIndex == 0,
                  candidate.sdpMid == localMID else { throw WebRTCAudioShareSenderError.invalidCandidate }
            guard let mapping = remoteMap else {
                guard offerStarted, pendingCandidates.count < 64 else {
                    throw WebRTCAudioShareSenderError.invalidCandidate
                }
                pendingCandidates.append(candidate)
                return
            }
            guard let validated = ICECandidateUsernameFragmentValidator.validatedCandidate(
                candidate, against: mapping, requiresExplicitFragment: true
            ) else { throw WebRTCAudioShareSenderError.invalidCandidate }
            let applied: Bool? = await WebRTCBoundedCallback.value(timeout: .seconds(8)) { resolve in
                commands.add(validated, completion: resolve)
            }
            try requireOpen()
            guard applied == true else { throw WebRTCAudioShareSenderError.invalidCandidate }
        } catch { gate.revoke(); throw error }
    }

    /// No source PCM flows before healthy native transport, raw live APM, and exact-generation
    /// approval. A later native StartRecording changes the generation and rejects delivery.
    public func admitCapture() async throws {
        try requireOpen()
        guard answerApplied else { throw WebRTCAudioShareSenderError.invalidNegotiation }
        let epoch = try gate.beginAdmission { track.isEnabled = true }
        do {
            for attempt in 0...20 {
                try Task.checkCancellation()
                let generation: UInt64? = try gate.withAdmissionAttempt(epoch) {
                    guard track.setAudioProcessingOptions(.raw()).isSuccess else {
                        throw WebRTCAudioShareSenderError.recordingAdmissionFailed
                    }
                    let snapshot = device.diagnostics
                    return Self.rawProcessingIsLive(factory) && snapshot.recording
                        && snapshot.recordingGeneration != 0 ? snapshot.recordingGeneration : nil
                }
                if let generation {
                    try gate.commit(epoch) {
                        let snapshot = device.diagnostics
                        guard Self.rawProcessingIsLive(factory), snapshot.recording,
                              snapshot.recordingGeneration == generation,
                              snapshot.approvedRecordingGeneration == 0,
                              device.approveRecordingGeneration(generation) else {
                            throw WebRTCAudioShareSenderError.recordingAdmissionFailed
                        }
                        let approved = device.diagnostics
                        guard approved.recordingGeneration == generation,
                              approved.approvedRecordingGeneration == generation else {
                            throw WebRTCAudioShareSenderError.recordingAdmissionFailed
                        }
                        capturer.setEnabled(true)
                    }
                    return
                }
                guard attempt < 20 else { throw WebRTCAudioShareSenderError.recordingAdmissionFailed }
                try await Task.sleep(for: .milliseconds(10))
                try requireOpen()
            }
        } catch { gate.cancelAdmission(epoch); throw error }
    }

    public func close() async {
        gate.revoke()
        if let closeTask { await closeTask.value; return }
        closed = true
        expiryTask?.cancel()
        expiryTask = nil
        pendingCandidates.removeAll()
        let retiringGate = gate
        let retiringSignaling = signaling
        let retiringContinuation = continuation
        let retirement = Task.detached {
            await retiringGate.waitForQuiescence()
            retiringSignaling.close()
            retiringContinuation.finish()
        }
        closeTask = retirement
        await retirement.value
    }

    private func requireOpen() throws {
        try gate.requireLive()
        guard !closed else { throw WebRTCAudioShareSenderError.closed }
        try Task.checkCancellation()
    }

    private static func rawProcessingIsLive(_ factory: LKRTCPeerConnectionFactory) -> Bool {
        let state = factory.audioProcessingState
        return [state.echoCancellation, state.noiseSuppression, state.autoGainControl, state.highPassFilter]
            .allSatisfy { $0.requested?.isEnabled == false && !$0.isSoftwareActive && !$0.isPlatformActive }
    }

    private static func applyBitrate(_ sender: LKRTCRtpSender) throws {
        let parameters = sender.parameters
        guard !parameters.encodings.isEmpty else { throw WebRTCTransportError.audioTrackCreationFailed }
        for encoding in parameters.encodings {
            encoding.maxBitrateBps = NSNumber(value: 192_000)
            encoding.minBitrateBps = nil
            encoding.networkPriority = .low
        }
        sender.parameters = parameters
        guard sender.parameters.encodings.count == parameters.encodings.count,
              sender.parameters.encodings.allSatisfy({ $0.maxBitrateBps?.intValue == 192_000 && $0.minBitrateBps == nil }) else {
            throw WebRTCTransportError.audioTrackCreationFailed
        }
    }
}

private struct AudioShareNativeDescription: Sendable {
    let sdp: String?
    let failed: Bool
}

/// Restricts SDP before the native parser can allocate any unexpected topology.
enum AudioShareSDP {
    static func validate(_ sdp: String, direction: String) throws -> String {
        guard sdp.utf8.count <= 49_152, !sdp.contains("\0") else {
            throw WebRTCAudioShareSenderError.invalidSessionDescription
        }
        let lines = sdp.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "v=0", let mediaIndex = lines.firstIndex(where: { $0.hasPrefix("m=") }),
              lines.filter({ $0.hasPrefix("m=") }).count == 1 else {
            throw WebRTCAudioShareSenderError.invalidSessionDescription
        }
        let fields = lines[mediaIndex].split(separator: " ").map(String.init)
        let media = Array(lines[(mediaIndex + 1)...])
        let mids = media.filter { $0.hasPrefix("a=mid:") }
        let directions = lines.filter { ["a=sendonly", "a=recvonly", "a=sendrecv", "a=inactive"].contains($0) }
        guard fields.count >= 4, fields[0] == "m=audio", let port = UInt16(fields[1]), port != 0,
              fields[2] == "UDP/TLS/RTP/SAVPF", mids.count == 1,
              directions == ["a=\(direction)"], media.contains("a=\(direction)"),
              media.filter({ $0 == "a=rtcp-mux" }).count == 1,
              !lines.contains(where: {
                  $0.hasPrefix("a=sctp") || $0.hasPrefix("a=dcmap") || $0.hasPrefix("a=dcsa")
                      || $0.hasPrefix("a=audiostreamer") || $0.hasPrefix("a=opensteamer")
              }) else { throw WebRTCAudioShareSenderError.invalidSessionDescription }
        let mid = String(mids[0].dropFirst(6))
        guard !mid.isEmpty, !mid.contains(where: \.isWhitespace),
              lines.filter({ $0.hasPrefix("a=group:") }) == ["a=group:BUNDLE \(mid)"] else {
            throw WebRTCAudioShareSenderError.invalidSessionDescription
        }
        let payloads = Array(fields.dropFirst(3))
        guard Set(payloads).count == payloads.count, payloads.allSatisfy({ UInt8($0) != nil }),
              media.filter({ $0.hasPrefix("a=rtpmap:") }).count == payloads.count,
              payloads.allSatisfy({ payload in
                  media.filter { $0.lowercased() == "a=rtpmap:\(payload) opus/48000/2" }.count == 1
              }), let mapping = ICEUsernameFragmentParser.mapping(inSessionDescription: sdp),
              mapping.mediaSections.count == 1, mapping.mediaSections[0].mid == mid,
              mapping.mediaSections[0].effectiveFragment != nil else {
            throw WebRTCAudioShareSenderError.invalidSessionDescription
        }
        return mid
    }
}

/// Native callbacks fail-close capture before emitting asynchronously consumed UI/events.
private final class AudioShareDelegate: NSObject, LKRTCPeerConnectionDelegate, @unchecked Sendable {
    private let gate: AudioShareCaptureGate
    private let continuation: AsyncStream<WebRTCAudioShareEvent>.Continuation
    private let mappingLock = NSLock()
    private var localMapping: ICEUsernameFragmentMap?

    init(gate: AudioShareCaptureGate, continuation: AsyncStream<WebRTCAudioShareEvent>.Continuation) {
        self.gate = gate
        self.continuation = continuation
    }

    func installLocalMapping(_ mapping: ICEUsernameFragmentMap) {
        mappingLock.withLock { localMapping = mapping }
    }

    private func emit(_ event: WebRTCAudioShareEvent) {
        if case .dropped = continuation.yield(event) { gate.revoke() }
    }

    private func reject() {
        gate.revoke()
        emit(.failure("Unexpected receive/control topology rejected."))
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {
        guard stream.audioTracks.isEmpty && stream.videoTracks.isEmpty else {
            stream.audioTracks.forEach { $0.isEnabled = false }
            stream.videoTracks.forEach { $0.isEnabled = false }
            reject(); return
        }
    }
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {
        dataChannel.close(); reject()
    }
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd rtpReceiver: LKRTCRtpReceiver,
                        streams mediaStreams: [LKRTCMediaStream]) {
        if let track = rtpReceiver.track { track.isEnabled = false; reject() }
    }
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        let sdp = candidate.sdp as String
        let value = RemoteICECandidate(sdp: sdp, sdpMid: candidate.sdpMid as String?,
            sdpMLineIndex: candidate.sdpMLineIndex,
            usernameFragment: ICEUsernameFragmentParser.fragment(inCandidateSDP: sdp))
        guard let mapping = mappingLock.withLock({ localMapping }),
              let bound = ICECandidateUsernameFragmentValidator.validatedCandidate(
                value, against: mapping, requiresExplicitFragment: false
              ) else { gate.revoke(); emit(.failure("Unbound local ICE candidate rejected.")); return }
        emit(.localCandidate(bound))
    }
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCPeerConnectionState) {
        let value: WebRTCPeerState
        switch newState {
        case .new: value = .new
        case .connecting: value = .connecting
        case .connected: value = .connected
        case .disconnected: value = .disconnected
        case .failed: value = .failed
        case .closed: value = .closed
        @unknown default: gate.revoke(); value = .failed
        }
        gate.observe(peerConnected: value == .connected)
        emit(.peerStateChanged(value))
    }
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {
        let value: WebRTCICEState
        switch newState {
        case .new: value = .new
        case .checking: value = .checking
        case .connected: value = .connected
        case .completed: value = .completed
        case .disconnected: value = .disconnected
        case .failed: value = .failed
        case .closed: value = .closed
        case .count: value = .unknown
        @unknown default: value = .unknown
        }
        gate.observe(iceConnected: value == .connected || value == .completed)
        emit(.iceStateChanged(value))
    }
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {
        let value: WebRTCICEGatheringState
        switch newState {
        case .new: value = .new
        case .gathering: value = .gathering
        case .complete: value = .complete
        @unknown default: gate.revoke(); value = .new
        }
        emit(.iceGatheringStateChanged(value))
    }
}

#endif
