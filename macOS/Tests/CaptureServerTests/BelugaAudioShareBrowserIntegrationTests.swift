import AudioToolbox
import CaptureCore
import CoreMedia
import CryptoKit
import Foundation
import Security
import XCTest
@testable import CaptureServer

/// Explicit loopback opt-in; ordinary source suites must not start a browser/native factory.
/// Real coordinator, LiveKit sender and browser decoder; synthetic PCM, not system capture.
final class BelugaAudioShareBrowserIntegrationTests: XCTestCase {
    func testNativeStereoDecodeRejoinRevokeAndExpiry() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let origin = environment["BELUGA_AUDIO_SHARE_ORACLE_URL"],
              let pin = environment["BELUGA_AUDIO_SHARE_ORACLE_CERT_SHA256"] else {
            throw XCTSkip("Requires the explicit isolated native-browser oracle runner")
        }
        guard let endpoint = URL(string: origin), endpoint.scheme == "https", endpoint.host == "127.0.0.1",
              endpoint.port != nil, endpoint.path.isEmpty, endpoint.query == nil, endpoint.fragment == nil,
              pin.count == 64, pin.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw OracleError.invalid }
        let http = OracleHTTP(origin: endpoint, pin: pin)
        let fixture = OraclePCMFixture()
        var dependencies = BelugaAudioShareDependencies()
        dependencies.socket = { OracleSocket(pin: pin) }
        // Keep the default REAL WebRTCAudioShareSender recipient. Only source/socket are injected.
        dependencies.source = { fanout, _ in fixture.makeSource(fanout) }
        let coordinator = BelugaAudioShareCoordinator(endpoint: endpoint, logger: OracleSilentLogger(),
            status: { fixture.record($0) }, dependencies: dependencies)
        do {
            let first = try await coordinator.start(ttlSeconds: 30)
            try await http.command(action: "join", phase: "revoke", url: first.url)
            let original = try await http.wait(timeout: 15) { $0.epochs.first(where: { $0.epoch == 1 && $0.decoded }) }
            checkDecoded(original)
            XCTAssertEqual(fixture.sources.count, 1)
            XCTAssertEqual(fixture.sources.first?.starts, 1)

            try await http.command(action: "rejoin")
            let second = try await http.wait(timeout: 10) { $0.epochs.first(where: { $0.epoch == 2 && $0.decoded }) }
            checkDecoded(second)
            XCTAssertEqual(original.shareID, second.shareID, "Rejoin must use the exact same share capability")
            XCTAssertEqual(fixture.sources.count, 1, "Zero-listener interval must not allocate a second source")
            XCTAssertEqual(fixture.sources.first?.starts, 1)
            XCTAssertEqual(fixture.sources.first?.stops, 0)

            try await http.native(fixture, phase: "before_revoke")
            coordinator.revokeCapture()
            let stopped = await coordinator.stop()
            XCTAssertTrue(stopped, "Native teardown must be confirmed, not merely scheduled")
            let closedSecond = try await http.wait(timeout: 5) { $0.epochs.first(where: { $0.epoch == 2 && $0.closed }) }
            checkDecoded(closedSecond)
            let firstSource = try XCTUnwrap(fixture.sources.first)
            XCTAssertEqual(firstSource.stops, 1)
            XCTAssertEqual(firstSource.attachedListeners, 0)
            let frames = firstSource.deliveries
            firstSource.attemptStaleCallback()
            try await Task.sleep(nanoseconds: 500_000_000)
            XCTAssertEqual(firstSource.deliveries, frames, "Owned fixture clock must stop after teardown")
            let stable = try await http.state()
            XCTAssertEqual(stable.epochs.first(where: { $0.epoch == 2 })?.windows, closedSecond.windows,
                           "Closed browser must not continue decoding fixture audio")
            try await http.native(fixture, phase: "after_revoke")

            let expiring = try await coordinator.start(ttlSeconds: 10)
            try await http.command(action: "join", phase: "expiry", url: expiring.url)
            let third = try await http.wait(timeout: 8) { $0.epochs.first(where: { $0.epoch == 3 && $0.decoded }) }
            checkDecoded(third)
            XCTAssertNotEqual(third.shareID, original.shareID)
            let expired = try await http.wait(timeout: 12) { $0.epochs.first(where: { $0.epoch == 3 && $0.closed }) }
            checkDecoded(expired)
            let confirmed = await coordinator.stop()
            XCTAssertTrue(confirmed)
            XCTAssertEqual(fixture.sources.count, 2)
            let expirySource = try XCTUnwrap(fixture.sources.last)
            XCTAssertEqual(expirySource.stops, 1)
            XCTAssertEqual(expirySource.attachedListeners, 0)
            let expiryFrames = expirySource.deliveries
            expirySource.attemptStaleCallback()
            try await Task.sleep(nanoseconds: 500_000_000)
            XCTAssertEqual(expirySource.deliveries, expiryFrames)
            let final = try await http.state()
            XCTAssertEqual(final.epochs.count, 3)
            XCTAssertTrue(final.epochs.allSatisfy { $0.closed && $0.decoded && $0.topology })
            XCTAssertEqual(final.epochs.last?.windows, expired.windows)
            XCTAssertEqual(final.microphoneCalls, 0)
            XCTAssertNil(final.failure)
            try await http.native(fixture, phase: "after_expiry")
            try await http.native(fixture, phase: "success")
            try await http.command(action: "complete")
            http.close()
        } catch {
            // Snapshot before revoke/cleanup destroys the admission/source evidence.
            try? await http.native(fixture, phase: "failure_before_cleanup")
            coordinator.revokeCapture()
            _ = await coordinator.stop()
            http.close()
            // Do not publish URLSession/native exception payloads that might contain a bearer URL.
            XCTFail("Isolated native-browser audio oracle did not satisfy a bounded phase")
            throw OracleError.invalid
        }
    }

    /// Separate opt-in: real production system capture, never the synthetic source above.
    func testRealSystemSourceStereoRejoinRevokeExpiryAndOwnerLoss() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let permission = environment["BELUGA_AUDIO_SHARE_SYSTEM_SOURCE_PERMISSION"] else {
            throw XCTSkip("Requires separately authorized real-system-source oracle")
        }
        guard #available(macOS 14.2, *), ["confirmed", "one-request-approved"].contains(permission),
              let gate = environment["BELUGA_AUDIO_SHARE_SYSTEM_SOURCE_GATE_SHA256"], gate.count == 64,
              gate.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              let nonce = environment["BELUGA_AUDIO_SHARE_SYSTEM_SOURCE_NONCE"], nonce.count == 32,
              nonce.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              let origin = environment["BELUGA_AUDIO_SHARE_ORACLE_URL"],
              let endpoint = URL(string: origin), endpoint.scheme == "https", endpoint.host == "127.0.0.1",
              endpoint.port != nil, endpoint.path.isEmpty, endpoint.query == nil, endpoint.fragment == nil,
              let pin = environment["BELUGA_AUDIO_SHARE_ORACLE_CERT_SHA256"], pin.count == 64,
              pin.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw OracleError.invalid }
        let http = OracleHTTP(origin: endpoint, pin: pin)
        let fixture = OracleSystemSourceEvidence(http: http)
        var dependencies = BelugaAudioShareDependencies()
        let productionSourceFactory = dependencies.source
        dependencies.socket = { OracleSocket(pin: pin) }
        dependencies.source = { fanout, logger in
            fixture.wrap(productionSourceFactory(fanout, logger), fanout: fanout)
        }
        let coordinator = BelugaAudioShareCoordinator(endpoint: endpoint, logger: OracleSilentLogger(),
            status: { fixture.record($0) }, dependencies: dependencies)
        do {
            let first = try await coordinator.start(ttlSeconds: 40)
            try await http.command(action: "join", phase: "revoke", url: first.url)
            let original = try await http.wait(timeout: 25) { $0.epochs.first(where: { $0.epoch == 1 && $0.decoded }) }
            checkDecoded(original); XCTAssertEqual(original.challengeNonce, nonce)
            XCTAssertEqual(fixture.sources.count, 1)
            try await http.command(action: "rejoin")
            let rejoined = try await http.wait(timeout: 10) { $0.epochs.first(where: { $0.epoch == 2 && $0.decoded }) }
            checkDecoded(rejoined); XCTAssertEqual(rejoined.challengeNonce, nonce)
            XCTAssertEqual(original.shareID, rejoined.shareID)
            XCTAssertEqual(fixture.sources.count, 1)
            XCTAssertEqual(fixture.sources.first?.snapshot()["confirmedStarts"], 1)
            try await http.native(fixture, phase: "before_revoke")
            coordinator.revokeCapture()
            let revoked = await coordinator.stop()
            XCTAssertTrue(revoked, "Real source shutdown must acknowledge, not merely schedule, native teardown")
            let revokedEpoch = try await http.wait(timeout: 5) { $0.epochs.first(where: { $0.epoch == 2 && $0.closed }) }
            checkDecoded(revokedEpoch)
            fixture.checkStopped(count: 1)
            try await http.native(fixture, phase: "after_revoke")

            let expiring = try await coordinator.start(ttlSeconds: 10)
            try await http.command(action: "join", phase: "expiry", url: expiring.url)
            let third = try await http.wait(timeout: 8) { $0.epochs.first(where: { $0.epoch == 3 && $0.decoded }) }
            checkDecoded(third); XCTAssertEqual(third.challengeNonce, nonce)
            XCTAssertNotEqual(third.shareID, original.shareID)
            let expired = try await http.wait(timeout: 12) { $0.epochs.first(where: { $0.epoch == 3 && $0.closed }) }
            checkDecoded(expired)
            // Observe automatic expiry cleanup before any test-induced stop or next start.
            try await fixture.waitForTerminalRetirement(count: 2)
            fixture.checkStopped(count: 2)
            try await http.native(fixture, phase: "after_expiry")

            let losingOwner = try await coordinator.start(ttlSeconds: 30)
            try await http.command(action: "join", phase: "owner_loss", url: losingOwner.url)
            let fourth = try await http.wait(timeout: 10) { $0.epochs.first(where: { $0.epoch == 4 && $0.decoded }) }
            checkDecoded(fourth); XCTAssertEqual(fourth.challengeNonce, nonce)
            XCTAssertNotEqual(fourth.shareID, original.shareID); XCTAssertNotEqual(fourth.shareID, third.shareID)
            try await http.command(action: "lose-owner")
            let lost = try await http.wait(timeout: 5) { $0.epochs.first(where: { $0.epoch == 4 && $0.closed }) }
            checkDecoded(lost)
            try await fixture.waitForTerminalRetirement(count: 3, requiresFailure: true)
            fixture.checkStopped(count: 3)
            try await http.native(fixture, phase: "after_owner_loss")
            try await Task.sleep(nanoseconds: 500_000_000)
            let final = try await http.state()
            XCTAssertEqual(final.epochs.count, 4)
            XCTAssertTrue(final.epochs.allSatisfy { $0.closed && $0.decoded && $0.topology && $0.challengeNonce == nonce })
            XCTAssertEqual(final.epochs.last?.windows, lost.windows, "Closed receiver must not keep decoding actual system audio")
            XCTAssertEqual(final.microphoneCalls, 0); XCTAssertNil(final.failure)
            try await http.native(fixture, phase: "success")
            try await http.command(action: "complete")
            http.close()
        } catch {
            try? await http.native(fixture, phase: "failure_before_cleanup")
            coordinator.revokeCapture()
            _ = await coordinator.stop()
            http.close()
            XCTFail("Real-system-source oracle did not satisfy a bounded phase; no native teardown is inferred from process death")
            throw OracleError.invalid
        }
    }

    private func checkDecoded(_ epoch: OracleEpoch) {
        XCTAssertTrue(epoch.decoded); XCTAssertTrue(epoch.topology)
        XCTAssertGreaterThan(epoch.rmsLeft, 0.01); XCTAssertGreaterThan(epoch.rmsRight, 0.01)
        XCTAssertGreaterThan(epoch.leftRatio, 8); XCTAssertGreaterThan(epoch.rightRatio, 8)
        XCTAssertEqual(epoch.sampleRate, 48_000); XCTAssertEqual(epoch.microphoneCalls, 0)
        XCTAssertNil(epoch.failure)
    }
}

private enum OracleError: Error { case invalid, deadline }
private struct OracleEpoch: Decodable, Sendable {
    let epoch: Int, phase: String, shareID: String
    let decoded: Bool, closed: Bool, topology: Bool
    let rmsLeft: Double, rmsRight: Double, leftRatio: Double, rightRatio: Double
    let sampleRate: Int, windows: Int, microphoneCalls: Int
    let failure: String?
    let challengeNonce: String?
}
private struct OracleState: Decodable, Sendable {
    let epochs: [OracleEpoch], failure: String?, microphoneCalls: Int, complete: Bool
}
private struct OracleSilentLogger: CaptureCore.Logger {
    func debug(_ message: String) { }
    func info(_ message: String) { }
    func error(_ message: String) { }
}

/// Ephemeral trust applies ONLY to this test's exact generated leaf and loopback hostname.
private final class OracleTLSDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let pin: String
    private let lock = NSLock()
    private var result: Result<Void, OracleError>?
    private var waiter: CheckedContinuation<Void, any Error>?
    private let fatal: @Sendable () -> Void
    init(pin: String, fatal: @escaping @Sendable () -> Void = {}) { self.pin = pin; self.fatal = fatal }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == "127.0.0.1", let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              certificates.count == 1, let certificate = certificates.first else {
            completionHandler(.cancelAuthenticationChallenge, nil); fail(); return
        }
        let data = SecCertificateCopyData(certificate) as Data
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == pin else { completionHandler(.cancelAuthenticationChallenge, nil); fail(); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil); fail()
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        if `protocol` == "beluga.audio-share.v1" { resolve(.success(())) } else { fail() }
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { fail() }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if error != nil { fail() }
    }
    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let immediate = lock.withLock { () -> Result<Void, OracleError>? in
                if let result { return result }; waiter = continuation; return nil
            }
            if let immediate { continuation.resume(with: immediate.mapError { $0 as any Error }) }
        }
    }
    func fail() { fatal(); resolve(.failure(.invalid)) }
    private func resolve(_ value: Result<Void, OracleError>) {
        let pending = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            guard result == nil else { return nil }; result = value
            let pending = waiter; waiter = nil; return pending
        }
        pending?.resume(with: value.mapError { $0 as any Error })
    }
}

private func oracleConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil; configuration.urlCredentialStorage = nil
    configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 3; configuration.timeoutIntervalForResource = 60
    return configuration
}
private final class OracleSocket: BelugaAudioShareSocket, @unchecked Sendable {
    private let pin: String, lock = NSLock()
    private var session: URLSession?, task: URLSessionWebSocketTask?, delegate: OracleTLSDelegate?
    init(pin: String) { self.pin = pin }
    func open(url: URL, onFatal: @escaping @Sendable () -> Void) async throws {
        guard url.scheme == "wss", url.host == "127.0.0.1", url.port != nil,
              url.query == nil, url.fragment == nil else { throw OracleError.invalid }
        let delegate = OracleTLSDelegate(pin: pin, fatal: onFatal)
        let session = URLSession(configuration: oracleConfiguration(), delegate: delegate, delegateQueue: nil)
        let task = session.webSocketTask(with: url, protocols: ["beluga.audio-share.v1"])
        task.maximumMessageSize = 90_000
        lock.withLock { self.delegate = delegate; self.session = session; self.task = task }
        task.resume(); try await delegate.wait()
    }
    func send(_ text: String) async throws {
        guard let task = lock.withLock({ task }), text.utf8.count <= 90_000 else { throw OracleError.invalid }
        try await task.send(.string(text))
    }
    func receive() async throws -> String {
        guard let task = lock.withLock({ task }) else { throw OracleError.invalid }
        guard case .string(let text) = try await task.receive(), text.utf8.count <= 90_000 else { throw OracleError.invalid }
        return text
    }
    func cancel() {
        let owned = lock.withLock { () -> (URLSessionWebSocketTask?, URLSession?, OracleTLSDelegate?) in
            let owned = (task, session, delegate); task = nil; session = nil; delegate = nil; return owned
        }
        owned.2?.fail(); owned.0?.cancel(with: .normalClosure, reason: nil); owned.1?.invalidateAndCancel()
    }
}
private final class OracleHTTP: @unchecked Sendable {
    private let origin: URL, session: URLSession
    init(origin: URL, pin: String) {
        self.origin = origin
        session = URLSession(configuration: oracleConfiguration(), delegate: OracleTLSDelegate(pin: pin), delegateQueue: nil)
    }
    func close() { session.invalidateAndCancel() }
    func state() async throws -> OracleState {
        let data = try await request(path: "/oracle/state")
        return try JSONDecoder().decode(OracleState.self, from: data)
    }
    func command(action: String, phase: String? = nil, url: URL? = nil) async throws {
        var value: [String: String] = ["action": action]
        if let phase { value["phase"] = phase }
        if let url { value["url"] = url.absoluteString }
        _ = try await request(path: "/oracle/command", body: JSONSerialization.data(withJSONObject: value))
    }
    func native(_ fixture: OraclePCMFixture, phase: String) async throws {
        _ = try await request(path: "/oracle/native", body: JSONSerialization.data(withJSONObject: fixture.snapshot(phase: phase)))
    }
    func native(_ fixture: OracleSystemSourceEvidence, phase: String) async throws {
        _ = try await request(path: "/oracle/native", body: JSONSerialization.data(withJSONObject: fixture.snapshot(phase: phase)))
    }
    private func request(path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: origin) else { throw OracleError.invalid }
        var request = URLRequest(url: url); request.timeoutInterval = 3
        if let body { request.httpMethod = "POST"; request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 32_768 else { throw OracleError.invalid }
        return data
    }
    func wait(timeout: TimeInterval, predicate: @Sendable (OracleState) -> OracleEpoch?) async throws -> OracleEpoch {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        repeat {
            let state = try await state()
            if state.failure != nil { throw OracleError.invalid }
            if let value = predicate(state) { return value }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while DispatchTime.now().uptimeNanoseconds < deadline
        throw OracleError.deadline
    }
}

/// Counts acknowledged operations without intercepting or manufacturing any source PCM.
private final class OracleSystemSourceEvidence: @unchecked Sendable {
    private let lock = NSLock(), http: OracleHTTP
    private var values: [OracleObservedSystemSource] = []
    private var status = BelugaAudioShareStatus.idle
    init(http: OracleHTTP) { self.http = http }
    var sources: [OracleObservedSystemSource] { lock.withLock { values } }
    func record(_ value: BelugaAudioShareStatus) { lock.withLock { status = value } }
    func wrap(_ source: any BelugaAudioShareSource, fanout: BelugaAudioShareFanout) -> OracleObservedSystemSource {
        let observed = OracleObservedSystemSource(source: source, fanout: fanout, http: http)
        lock.withLock { values.append(observed) }
        return observed
    }
    func waitForTerminalRetirement(count: Int, requiresFailure: Bool = false) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 12_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let (state, observed) = lock.withLock { (status, values) }
            // Expiry cancels its owner socket; that socket's fatal callback can race the
            // .ended publication and publish .failed after the same confirmed cleanup.
            // Neither status alone proves retirement: every real stop must acknowledge.
            let terminal = state == .failed || (!requiresFailure && state == .ended)
            if terminal, observed.count == count, observed.allSatisfy({
                $0.snapshot() == ["starts": 1, "confirmedStarts": 1, "stops": 1,
                    "confirmedStops": 1, "attachedListeners": 0]
            }) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw OracleError.deadline
    }
    func checkStopped(count: Int) {
        XCTAssertEqual(sources.count, count)
        for source in sources {
            XCTAssertEqual(source.snapshot(), ["starts": 1, "confirmedStarts": 1, "stops": 1,
                "confirmedStops": 1, "attachedListeners": 0])
        }
    }
    func snapshot(phase: String) -> [String: Any] {
        let (status, sources) = lock.withLock { (self.status, values) }
        let name: String, listeners: Int
        switch status {
        case .idle: name = "idle"; listeners = 0
        case .starting: name = "starting"; listeners = 0
        case .active(let count): name = "active"; listeners = count
        case .ended: name = "ended"; listeners = 0
        case .failed: name = "failed"; listeners = 0
        }
        return ["phase": phase, "status": name, "activeListeners": listeners, "sources": sources.map { $0.snapshot() }]
    }
}
private final class OracleObservedSystemSource: BelugaAudioShareSource, @unchecked Sendable {
    private let source: any BelugaAudioShareSource, fanout: BelugaAudioShareFanout, http: OracleHTTP
    private let lock = NSLock()
    private var starts = 0, confirmedStarts = 0, stops = 0, confirmedStops = 0
    init(source: any BelugaAudioShareSource, fanout: BelugaAudioShareFanout, http: OracleHTTP) {
        self.source = source; self.fanout = fanout; self.http = http
    }
    func start() async throws {
        lock.withLock { starts += 1 }
        try await source.start()
        lock.withLock { confirmedStarts += 1 }
        try await http.command(action: "start-emitter")
    }
    func revokeStart() { source.revokeStart() }
    func stop() async throws {
        lock.withLock { stops += 1 }
        try await source.stop()
        // A failed/partial startup still stops the real source. No emitter start is fabricated.
        if lock.withLock({ confirmedStarts > 0 }) { try await http.command(action: "stop-emitter") }
        lock.withLock { confirmedStops += 1 }
    }
    func snapshot() -> [String: Int] {
        lock.withLock { ["starts": starts, "confirmedStarts": confirmedStarts, "stops": stops,
            "confirmedStops": confirmedStops, "attachedListeners": fanout.listenerCount] }
    }
}

private final class OraclePCMFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [OraclePCMSource] = []
    private var lastStatus: BelugaAudioShareStatus = .idle
    var sources: [OraclePCMSource] { lock.withLock { values } }
    func record(_ value: BelugaAudioShareStatus) { lock.withLock { lastStatus = value } }
    func snapshot(phase: String) -> [String: Any] {
        let (sources, state) = lock.withLock { (values, lastStatus) }
        let status: String, listeners: Int
        switch state {
        case .idle: status = "idle"; listeners = 0
        case .starting: status = "starting"; listeners = 0
        case .active(let count): status = "active"; listeners = count
        case .ended: status = "ended"; listeners = 0
        case .failed: status = "failed"; listeners = 0
        }
        return ["phase": phase, "status": status, "activeListeners": listeners,
                "sources": sources.map { ["starts": $0.starts, "stops": $0.stops,
                    "deliveries": $0.deliveries, "attachedListeners": $0.attachedListeners] }]
    }
    func makeSource(_ fanout: BelugaAudioShareFanout) -> OraclePCMSource {
        let source = OraclePCMSource(fanout: fanout)
        lock.withLock { values.append(source) }; return source
    }
}
/// Only this opt-in test invents a sample clock; no production timer/PCM source is modified.
private final class OraclePCMSource: BelugaAudioShareSource, @unchecked Sendable {
    private let lock = NSLock(), fanout: BelugaAudioShareFanout
    private var closed = false, task: Task<Void, Never>?
    private var startCount = 0, stopCount = 0, deliveryCount = 0
    init(fanout: BelugaAudioShareFanout) { self.fanout = fanout }
    var starts: Int { lock.withLock { startCount } }
    var stops: Int { lock.withLock { stopCount } }
    var deliveries: Int { lock.withLock { deliveryCount } }
    var attachedListeners: Int { fanout.listenerCount }
    func revokeStart() { lock.withLock { closed = true; task?.cancel() } }
    func start() async throws {
        let accepted = lock.withLock { () -> Bool in
            guard !closed, task == nil else { return false }
            startCount += 1
            task = Task.detached { [self] in
                var sample: Int64 = 0
                while !Task.isCancelled {
                    guard lock.withLock({ !closed }) else { break }
                    deliver(sample: sample); sample += 480
                    do { try await Task.sleep(nanoseconds: 10_000_000) } catch { break }
                }
            }
            return true
        }
        guard accepted else { throw OracleError.invalid }
    }
    func stop() async throws {
        let owned = lock.withLock { () -> Task<Void, Never>? in
            closed = true; stopCount += 1; task?.cancel(); return task
        }
        await owned?.value
    }
    func attemptStaleCallback() { deliver(sample: 0, countDelivery: false) }
    private func deliver(sample: Int64, countDelivery: Bool = true) {
        var frames = [Float](repeating: 0, count: 960)
        for index in 0..<480 {
            let time = Double(sample + Int64(index)) / 48_000
            frames[index * 2] = Float(0.2 * sin(2 * .pi * 440 * time))
            frames[index * 2 + 1] = Float(0.2 * sin(2 * .pi * 880 * time))
        }
        let format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
            mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        frames.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            withUnsafePointer(to: &list) { fanout.consumeSystemAudioFrames($0, format: format,
                frameCount: 480, presentationTime: CMTime(value: sample, timescale: 48_000)) }
        }
        if countDelivery { lock.withLock { deliveryCount += 1 } }
    }
}
