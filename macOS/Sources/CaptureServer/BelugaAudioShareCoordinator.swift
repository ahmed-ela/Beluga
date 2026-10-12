import AudioToolbox
import CaptureCore
import CoreFoundation
import CoreMedia
import Foundation
import RemoteSessionCore
import WebRTCTransport

enum BelugaAudioShareStatus: Equatable, Sendable {
    case idle, starting, active(listeners: Int), ended, failed
}

struct BelugaAudioShareStarted: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let url: URL
    let expiresAt: Date
    var description: String { "<redacted audio-share capability>" }
    var debugDescription: String { description }
}

enum BelugaAudioShareCoordinatorError: Error, Equatable, Sendable, LocalizedError {
    case invalidConfiguration, busy, unavailable, invalidMessage, quarantined
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Audio sharing is not configured correctly."
        case .busy: "An audio share is already starting, active, or stopping."
        case .unavailable: "Audio sharing is temporarily unavailable."
        case .invalidMessage: "The audio-share connection could not be verified."
        case .quarantined: "The previous audio source did not confirm shutdown. Restart the host before sharing again."
        }
    }
}

// These narrow injected boundaries let tests prove ownership without opening a socket,
// initializing a WebRTC factory, acquiring native capture, or touching audio routes.
protocol BelugaAudioShareSocket: AnyObject, Sendable {
    func open(url: URL, onFatal: @escaping @Sendable () -> Void) async throws
    func send(_ text: String) async throws
    func receive() async throws -> String
    func cancel()
}

protocol BelugaAudioShareRecipient: AnyObject, Sendable {
    var events: AsyncStream<WebRTCAudioShareEvent> { get }
    var sink: any BelugaAudioShareSink { get }
    func createOffer() async throws -> String
    func setAnswer(_ sdp: String) async throws
    func addICE(_ candidate: RemoteICECandidate) async throws
    func admitCapture() async throws
    func revokeCapture()
    func close() async
}

protocol BelugaAudioShareSource: AnyObject, Sendable {
    func start() async throws
    func revokeStart()
    func stop() async throws
}

struct BelugaAudioShareDependencies: Sendable {
    var now: @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    var teardownTimeoutNanoseconds: UInt64 = 10_000_000_000
    var socket: @Sendable () -> any BelugaAudioShareSocket = { NativeAudioShareSocket() }
    var recipient: @Sendable ([RemoteICEServer], Date) throws -> any BelugaAudioShareRecipient = {
        try NativeAudioShareRecipient(iceServers: $0, expiresAt: $1)
    }
    var source: @Sendable (BelugaAudioShareFanout, any CaptureCore.Logger) -> any BelugaAudioShareSource = {
        NativeAudioShareSource(consumer: $0, logger: $1)
    }
}

/// An uncooperative native boundary cannot hold up the host's shutdown indefinitely.
/// The owned cleanup task continues, but timeout never declares success or releases ownership.
private final class AudioShareCleanupCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    func resolve(_ result: Bool) {
        let pending = lock.withLock { () -> [CheckedContinuation<Bool, Never>] in
            guard self.result == nil else { return [] }
            self.result = result
            let pending = Array(waiters.values); waiters.removeAll(); return pending
        }
        for waiter in pending { waiter.resume(returning: result) }
    }
    func wait(timeout: UInt64) async -> Bool {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            let immediate = lock.withLock { () -> Bool? in
                if let result { return result }
                waiters[id] = continuation; return nil
            }
            if let immediate { continuation.resume(returning: immediate); return }
            Task.detached { [self] in
                do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                let waiter = lock.withLock { waiters.removeValue(forKey: id) }
                waiter?.resume(returning: false)
            }
        }
    }
}

/// The delegate can close every callback-visible gate without waiting for this actor.
/// Attempt identity prevents a late close from an old socket from revoking a new share.
private final class AudioShareRevocation: @unchecked Sendable {
    private let lock = NSLock()
    private var attempt: UUID?
    private var revoked = true
    private var lease: BelugaAudioShareLease?
    private var fanout: BelugaAudioShareFanout?
    private var source: (any BelugaAudioShareSource)?
    private var recipients: [UUID: any BelugaAudioShareRecipient] = [:]

    func begin(_ id: UUID) {
        lock.withLock {
            attempt = id; revoked = false
            lease = nil; fanout = nil; source = nil; recipients.removeAll()
        }
    }
    func isCurrent(_ id: UUID) -> Bool {
        lock.withLock { attempt == id && !revoked && (lease?.isValid ?? true) }
    }
    func install(lease: BelugaAudioShareLease, fanout: BelugaAudioShareFanout, id: UUID) -> Bool {
        let installed = lock.withLock { () -> Bool in
            guard attempt == id, !revoked, lease.isValid else { return false }
            self.lease = lease; self.fanout = fanout
            return true
        }
        if !installed { lease.revoke(); fanout.revoke() }
        return installed
    }
    func install(source: any BelugaAudioShareSource, id: UUID) -> Bool {
        let installed = lock.withLock { () -> Bool in
            guard attempt == id, !revoked, lease?.isValid == true else { return false }
            self.source = source; return true
        }
        if !installed { source.revokeStart() }
        return installed
    }
    func install(recipient: any BelugaAudioShareRecipient, slot: UUID, id: UUID) -> Bool {
        let installed = lock.withLock { () -> Bool in
            guard attempt == id, !revoked, lease?.isValid == true,
                  recipients.count < 8, recipients[slot] == nil else { return false }
            recipients[slot] = recipient; return true
        }
        if !installed { recipient.revokeCapture() }
        return installed
    }
    func remove(slot: UUID, id: UUID) {
        let retired = lock.withLock { attempt == id ? recipients.removeValue(forKey: slot) : nil }
        retired?.revokeCapture()
    }
    func revoke(_ id: UUID? = nil) {
        let retired = lock.withLock { () -> (BelugaAudioShareLease?, BelugaAudioShareFanout?,
                                            (any BelugaAudioShareSource)?, [any BelugaAudioShareRecipient])? in
            guard !revoked, id == nil || id == attempt else { return nil }
            revoked = true
            return (lease, fanout, source, Array(recipients.values))
        }
        guard let retired else { return }
        retired.0?.revoke()
        retired.2?.revokeStart()
        retired.1?.revoke()
        for recipient in retired.3 { recipient.revokeCapture() }
    }
}

actor BelugaAudioShareCoordinator {
    private struct Recipient {
        let slot: UUID
        let peer: any BelugaAudioShareRecipient
        let cipher: BelugaAudioShareSignalCipher
        var task: Task<Void, Never>?
        var offerReady = false
        var pendingLocalICE: [RemoteICECandidate] = []
        var answerApplied = false
        var answerPending = false
        var inbound: [QueuedPayload] = []
        var inboundBytes = 0
        var signalOperation: UUID?
        var peerConnected = false
        var iceConnected = false
        var admitting = false
        var admitted = false
    }
    private struct Operation { let slot: UUID; let task: Task<Void, Never> }
    private final class Session {
        let id = UUID()
        let material: BelugaAudioShareMaterial
        let socket: any BelugaAudioShareSocket
        var generation = ""
        var serverExpiry: Int64 = 0
        var serverTime: Int64 = 0
        var deadline: UInt64 = 0
        var lease: BelugaAudioShareLease?
        var fanout: BelugaAudioShareFanout?
        var source: (any BelugaAudioShareSource)?
        var sourceStart: Task<Void, any Error>?
        var sourceRunning = false
        var sourceStarting = false
        var recipients: [String: Recipient] = [:]
        var retiring: [UUID: Task<Void, Never>] = [:]
        var operations: [UUID: Operation] = [:]
        var admittedIDs: Set<String> = []
        var receiveTask: Task<Void, Never>?
        var heartbeatTask: Task<Void, Never>?
        var deadlineTask: Task<Void, Never>?
        var handshakeTask: Task<Void, Never>?
        var sendTask: Task<Void, Never>?
        var cleanupTask: Task<Bool, Never>?
        let cleanupCompletion = AudioShareCleanupCompletion()
        var outbox: [Outbound] = []
        var outboxBytes = 0
        var closing = false
        init(socket: any BelugaAudioShareSocket) throws {
            self.socket = socket; material = try BelugaAudioShareMaterial()
        }
    }
    private enum Outbound: Sendable {
        case text(String)
        case signal(id: String, slot: UUID, plaintext: Data)
        var size: Int {
            switch self { case .text(let text): text.utf8.count
            case .signal(_, _, let data): data.count + 256 }
        }
    }

    private let endpoint: URL
    private let logger: any CaptureCore.Logger
    private let status: @Sendable (BelugaAudioShareStatus) -> Void
    private let dependencies: BelugaAudioShareDependencies
    private let ownerIsValid: @Sendable () -> Bool
    private nonisolated let revocation = AudioShareRevocation()
    private var session: Session?
    private var quarantined = false
    private var latestAttempt: UUID?

    init(endpoint: URL, logger: any CaptureCore.Logger,
         status: @escaping @Sendable (BelugaAudioShareStatus) -> Void = { _ in },
         ownerIsValid: @escaping @Sendable () -> Bool = { true },
         dependencies: BelugaAudioShareDependencies = .init()) {
        self.endpoint = endpoint; self.logger = logger; self.status = status
        self.dependencies = dependencies
        self.ownerIsValid = ownerIsValid
    }

    nonisolated func revokeCapture() { revocation.revoke() }

    func start(ttlSeconds: Int) async throws -> BelugaAudioShareStarted {
        guard !quarantined else { throw BelugaAudioShareCoordinatorError.quarantined }
        guard ownerIsValid() else { throw BelugaAudioShareCoordinatorError.unavailable }
        guard session == nil else { throw BelugaAudioShareCoordinatorError.busy }
        guard (1...86_400).contains(ttlSeconds) else { throw BelugaAudioShareCoordinatorError.invalidConfiguration }
        let current = try Session(socket: dependencies.socket())
        let (socketURL, origin) = try Self.urls(endpoint: endpoint, shareID: current.material.shareID)
        session = current; latestAttempt = current.id; revocation.begin(current.id); status(.starting)
        let id = current.id, socket = current.socket, lifetime = revocation
        current.handshakeTask = Task.detached { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            lifetime.revoke(id); socket.cancel()
            await self?.fail(id)
        }
        do {
            try await socket.open(url: socketURL) { lifetime.revoke(id) }
            try requireCurrent(current)
            let sentAt = dependencies.now()
            try await socket.send(try Self.encode([
                "type": "register", "v": 1, "ownerProof": current.material.admissionProof(owner: true),
                "listenerProof": current.material.admissionProof(owner: false), "ttlSeconds": ttlSeconds,
                "maxListeners": 8,
            ]))
            try requireCurrent(current)
            let registered = try Self.parse(try await socket.receive())
            try requireCurrent(current)
            guard case .registered(let grant) = registered,
                  grant.shareID == current.material.shareID else {
                throw BelugaAudioShareCoordinatorError.invalidMessage
            }
            // Reservation/storage consumes part of the requested lifetime. A grant may
            // shorten it, never extend it. Keep the local deadline anchored BEFORE send,
            // so response latency cannot add time to the server's absolute expiry.
            let grantedRemaining = grant.expiresAt.subtractingReportingOverflow(grant.serverTime)
            guard !grantedRemaining.overflow, (1...(Int64(ttlSeconds) * 1_000)).contains(grantedRemaining.partialValue) else {
                throw BelugaAudioShareCoordinatorError.invalidMessage
            }
            let deadline = try Self.deadline(sentAt: sentAt, milliseconds: grantedRemaining.partialValue)
            let authentication = try Self.deadline(sentAt: sentAt, milliseconds: grant.leaseExpiresAt - grant.serverTime)
            let lease = BelugaAudioShareLease(absoluteDeadline: deadline,
                authenticationDeadline: authentication, now: dependencies.now)
            let fanout = BelugaAudioShareFanout(deadlineUptimeNanoseconds: deadline,
                now: dependencies.now, lease: lease, ownerIsValid: ownerIsValid) { [weak self] in
                    lifetime.revoke(id)
                    Task { await self?.fail(id) }
                }
            current.generation = grant.generation; current.serverExpiry = grant.expiresAt
            current.serverTime = grant.serverTime; current.deadline = deadline
            current.lease = lease; current.fanout = fanout
            guard revocation.install(lease: lease, fanout: fanout, id: id) else {
                throw BelugaAudioShareCoordinatorError.unavailable
            }
            try requireCurrent(current)
            current.handshakeTask?.cancel(); current.handshakeTask = nil
            current.receiveTask = Task { [weak self] in await self?.receiveLoop(id) }
            current.heartbeatTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    guard await self?.probe(id) == true else { return }
                }
            }
            let now = dependencies.now()
            guard now < deadline else { throw BelugaAudioShareCoordinatorError.unavailable }
            let remaining = deadline - now
            current.deadlineTask = Task.detached { [weak self] in
                do { try await Task.sleep(nanoseconds: remaining) } catch { return }
                lifetime.revoke(id); socket.cancel()
                await self?.end(id)
            }
            guard probe(id) else { throw BelugaAudioShareCoordinatorError.unavailable }
            status(.active(listeners: 0))
            return .init(url: try current.material.listenerURL(origin: origin),
                         expiresAt: Date(timeIntervalSince1970: Double(grant.expiresAt) / 1_000))
        } catch {
            revocation.revoke(id)
            _ = await cleanUp(current)
            publishTerminal(.failed, current)
            throw quarantined ? BelugaAudioShareCoordinatorError.quarantined : BelugaAudioShareCoordinatorError.unavailable
        }
    }

    /// Logical gates close synchronously before any awaited native teardown. A failed stop
    /// retains this exact source and permanently forbids a replacement capture source.
    func stop() async -> Bool {
        revocation.revoke()
        guard let current = session else { return !quarantined }
        let result = await cleanUp(current)
        publishTerminal(result ? .ended : .failed, current)
        return result
    }

    private func requireCurrent(_ current: Session) throws {
        guard ownerIsValid(), session === current, !current.closing,
              revocation.isCurrent(current.id), !Task.isCancelled else {
            throw BelugaAudioShareCoordinatorError.unavailable
        }
    }

    private func receiveLoop(_ id: UUID) async {
        guard let current = session, current.id == id else { return }
        do {
            while !Task.isCancelled {
                let text = try await current.socket.receive()
                try requireCurrent(current)
                try await handle(try Self.parse(text), current)
                try requireCurrent(current)
            }
        } catch {
            revocation.revoke(id)
            await fail(id)
        }
    }

    private func handle(_ message: ServerMessage, _ current: Session) async throws {
        switch message {
        case .registered: throw BelugaAudioShareCoordinatorError.invalidMessage
        case .error:
            revocation.revoke(current.id); await fail(current.id)
        case .ended:
            revocation.revoke(current.id); await end(current.id)
        case .probe(let nonce, let time, let expiry):
            guard time >= current.serverTime, expiry <= current.serverExpiry,
                  current.lease?.acknowledge(nonce: nonce, leaseMilliseconds: UInt64(expiry - time)) == true else {
                throw BelugaAudioShareCoordinatorError.invalidMessage
            }
            current.serverTime = time
        case .left(let listener): retire(listener, current)
        case .ready(let ready): try await addRecipient(ready, current)
        case .signal(let envelope):
            guard let recipient = current.recipients[envelope.listenerID] else { return }
            do {
                let plaintext = try recipient.cipher.open(envelope)
                let payload = try Self.payload(plaintext)
                guard recipient.inbound.count < 64,
                      recipient.inboundBytes + plaintext.count <= 524_288 else {
                    throw BelugaAudioShareCoordinatorError.invalidMessage
                }
                if case .answer = payload {
                    guard !recipient.answerApplied, !recipient.answerPending else {
                        throw BelugaAudioShareCoordinatorError.invalidMessage
                    }
                    current.recipients[envelope.listenerID]?.answerPending = true
                }
                current.recipients[envelope.listenerID]?.inbound.append(.init(payload: payload, bytes: plaintext.count))
                current.recipients[envelope.listenerID]?.inboundBytes += plaintext.count
                scheduleSignals(envelope.listenerID, current)
            } catch { retire(envelope.listenerID, current) }
        }
    }

    private func addRecipient(_ ready: Ready, _ current: Session) async throws {
        guard ready.shareID == current.material.shareID, ready.generation == current.generation,
              ready.expiresAt == current.serverExpiry, ready.serverTime >= current.serverTime,
              current.recipients.count + current.retiring.count < 8,
              !current.admittedIDs.contains(ready.listenerID),
              current.admittedIDs.count < 1_024 else { throw BelugaAudioShareCoordinatorError.invalidMessage }
        try requireCurrent(current)
        current.admittedIDs.insert(ready.listenerID)
        let slot = UUID()
        let now = dependencies.now()
        guard now < current.deadline else { throw BelugaAudioShareCoordinatorError.unavailable }
        let remaining = current.deadline - now
        let context = BelugaAudioShareSignalContext(shareID: ready.shareID, generation: ready.generation,
            listenerID: ready.listenerID, expiresAt: ready.expiresAt)
        let cipher = try BelugaAudioShareSignalCipher(root: current.material.listenerSecret, context: context)
        let peer = try dependencies.recipient(ready.iceServers,
            Date().addingTimeInterval(Double(remaining) / 1_000_000_000))
        guard revocation.install(recipient: peer, slot: slot, id: current.id) else {
            trackRetirement(peer, slot: slot, current)
            throw BelugaAudioShareCoordinatorError.unavailable
        }
        current.recipients[ready.listenerID] = Recipient(slot: slot, peer: peer, cipher: cipher)
        let id = current.id, listenerID = ready.listenerID
        current.recipients[listenerID]?.task = Task { [weak self] in
            for await event in peer.events {
                guard !Task.isCancelled else { break }
                await self?.event(event, id: id, listenerID: listenerID, slot: slot)
            }
        }
        let operation = UUID()
        let task = Task<Void, Never> { [weak self] in
            await self?.makeOffer(id: id, listenerID: listenerID, slot: slot, operation: operation)
        }
        current.operations[operation] = .init(slot: slot, task: task)
    }

    private func makeOffer(id: UUID, listenerID: String, slot: UUID, operation: UUID) async {
        guard let current = session, current.id == id else { return }
        defer { current.operations.removeValue(forKey: operation) }
        guard let recipient = current.recipients[listenerID], recipient.slot == slot else { return }
        do {
            try requireCurrent(current)
            let offer = try await recipient.peer.createOffer()
            try requireCurrent(current)
            guard current.recipients[listenerID]?.slot == slot else { return }
            try enqueue(.signal(id: listenerID, slot: slot,
                plaintext: Self.data(["kind": "offer", "sdp": offer])), current)
            let candidates = current.recipients[listenerID]?.pendingLocalICE ?? []
            current.recipients[listenerID]?.pendingLocalICE.removeAll()
            current.recipients[listenerID]?.offerReady = true
            for candidate in candidates { try enqueueCandidate(candidate, listenerID: listenerID, slot: slot, current) }
            scheduleSignals(listenerID, current)
        } catch { retire(listenerID, current) }
    }

    private func scheduleSignals(_ listenerID: String, _ current: Session) {
        guard let recipient = current.recipients[listenerID], recipient.offerReady,
              !recipient.inbound.isEmpty, recipient.signalOperation == nil, !current.closing else { return }
        let operation = UUID(), id = current.id, slot = recipient.slot
        current.recipients[listenerID]?.signalOperation = operation
        let task = Task<Void, Never> { [weak self] in
            await self?.processSignals(id: id, listenerID: listenerID, slot: slot, operation: operation)
        }
        current.operations[operation] = .init(slot: slot, task: task)
    }

    private func processSignals(id: UUID, listenerID: String, slot: UUID, operation: UUID) async {
        guard let current = session, current.id == id else { return }
        defer {
            current.operations.removeValue(forKey: operation)
            if current.recipients[listenerID]?.slot == slot {
                current.recipients[listenerID]?.signalOperation = nil
            }
        }
        do {
            while let recipient = current.recipients[listenerID], recipient.slot == slot,
                  !recipient.inbound.isEmpty {
                try requireCurrent(current)
                let queued = recipient.inbound[0]
                current.recipients[listenerID]?.inbound.removeFirst()
                current.recipients[listenerID]?.inboundBytes -= queued.bytes
                switch queued.payload {
                case .answer(let sdp):
                    try await recipient.peer.setAnswer(sdp)
                    try requireCurrent(current)
                    guard current.recipients[listenerID]?.slot == slot else { return }
                    current.recipients[listenerID]?.answerPending = false
                    current.recipients[listenerID]?.answerApplied = true
                    scheduleAdmission(listenerID, current)
                case .ice(let candidate):
                    try await recipient.peer.addICE(candidate)
                    try requireCurrent(current)
                }
            }
        } catch { retire(listenerID, current) }
    }

    private func event(_ event: WebRTCAudioShareEvent, id: UUID, listenerID: String, slot: UUID) async {
        guard let current = session, current.id == id, !current.closing,
              current.recipients[listenerID]?.slot == slot else { return }
        guard ownerIsValid(), revocation.isCurrent(id) else { await fail(id); return }
        do {
            switch event {
            case .localCandidate(let candidate):
                guard let recipient = current.recipients[listenerID], candidate.sdpMid != nil,
                      candidate.usernameFragment != nil, candidate.sdpMLineIndex == 0 else {
                    throw BelugaAudioShareCoordinatorError.invalidMessage
                }
                if recipient.offerReady { try enqueueCandidate(candidate, listenerID: listenerID, slot: slot, current) }
                else {
                    guard recipient.pendingLocalICE.count < 64 else { throw BelugaAudioShareCoordinatorError.invalidMessage }
                    current.recipients[listenerID]?.pendingLocalICE.append(candidate)
                }
            case .peerStateChanged(let state):
                if [.disconnected, .failed, .closed].contains(state) ||
                    (state != .connected && current.recipients[listenerID].map({ $0.admitted || $0.admitting }) == true) {
                    retire(listenerID, current); return
                }
                current.recipients[listenerID]?.peerConnected = state == .connected
                scheduleAdmission(listenerID, current)
            case .iceStateChanged(let state):
                let healthy = state == .connected || state == .completed
                if [.disconnected, .failed, .closed, .unknown].contains(state) ||
                    (!healthy && current.recipients[listenerID].map({ $0.admitted || $0.admitting }) == true) {
                    retire(listenerID, current); return
                }
                current.recipients[listenerID]?.iceConnected = healthy
                scheduleAdmission(listenerID, current)
            case .captureRevoked, .failure: retire(listenerID, current)
            case .iceGatheringStateChanged: break
            }
        } catch { retire(listenerID, current) }
    }

    private func enqueueCandidate(_ candidate: RemoteICECandidate, listenerID: String, slot: UUID, _ current: Session) throws {
        guard let mid = candidate.sdpMid, let fragment = candidate.usernameFragment,
              let line = candidate.sdpMLineIndex, line == 0 else { throw BelugaAudioShareCoordinatorError.invalidMessage }
        try enqueue(.signal(id: listenerID, slot: slot, plaintext: Self.data([
            "kind": "ice", "candidate": ["candidate": candidate.sdp, "sdpMid": mid,
                "sdpMLineIndex": Int(line), "usernameFragment": fragment],
        ])), current)
    }

    private func scheduleAdmission(_ listenerID: String, _ current: Session) {
        guard let recipient = current.recipients[listenerID], recipient.answerApplied,
              recipient.peerConnected, recipient.iceConnected, !recipient.admitting, !recipient.admitted,
              current.fanout != nil, !current.closing else { return }
        current.recipients[listenerID]?.admitting = true
        let operation = UUID(), id = current.id, slot = recipient.slot
        let task = Task<Void, Never> { [weak self] in
            await self?.admitRecipient(id: id, listenerID: listenerID, slot: slot, operation: operation)
        }
        current.operations[operation] = .init(slot: slot, task: task)
    }

    private func admitRecipient(id: UUID, listenerID: String, slot: UUID, operation: UUID) async {
        guard let current = session, current.id == id else { return }
        defer { current.operations.removeValue(forKey: operation) }
        guard let recipient = current.recipients[listenerID], recipient.slot == slot,
              let fanout = current.fanout else { return }
        do {
            try requireCurrent(current)
            try await recipient.peer.admitCapture()
            try requireCurrent(current)
            guard current.recipients[listenerID]?.slot == recipient.slot,
                  fanout.attach(recipient.peer.sink, listenerID: recipient.slot) else {
                recipient.peer.revokeCapture(); retire(listenerID, current); return
            }
            current.recipients[listenerID]?.admitting = false
            current.recipients[listenerID]?.admitted = true
            if current.source == nil {
                let source = dependencies.source(fanout, logger)
                current.source = source
                guard revocation.install(source: source, id: current.id) else {
                    source.revokeStart(); throw BelugaAudioShareCoordinatorError.unavailable
                }
                current.sourceStarting = true
                let task = Task { try await source.start() }
                current.sourceStart = task
                try await task.value
                try requireCurrent(current)
                current.sourceStarting = false; current.sourceRunning = true
            }
            try requireCurrent(current)
            status(.active(listeners: current.recipients.values.filter(\.admitted).count))
        } catch {
            if current.source != nil, !current.sourceRunning {
                revocation.revoke(id); Task { await fail(id) }
            } else { retire(listenerID, current) }
        }
    }

    private func retire(_ listenerID: String, _ current: Session) {
        guard let recipient = current.recipients.removeValue(forKey: listenerID) else { return }
        recipient.cipher.close()
        revocation.remove(slot: recipient.slot, id: current.id)
        current.fanout?.detach(listenerID: recipient.slot)
        recipient.peer.revokeCapture()
        trackRetirement(recipient.peer, slot: recipient.slot, current)
        if !current.closing, revocation.isCurrent(current.id), ownerIsValid() {
            do { try enqueue(.text(Self.encode(["type": "retire-listener", "v": 1, "listenerID": listenerID])), current) }
            catch { revocation.revoke(current.id); Task { await fail(current.id) } }
        }
        // This may be that very event-consumer task. Cancel only after the synchronous
        // targeted retirement frame has passed requireCurrent's cancellation guard.
        recipient.task?.cancel()
    }

    private func trackRetirement(_ peer: any BelugaAudioShareRecipient, slot: UUID, _ current: Session) {
        peer.revokeCapture()
        let pending = current.operations.values.filter { $0.slot == slot }.map(\.task)
        let sessionID = current.id
        // This task cannot call cleanup or await its caller. It is included in the native budget.
        current.retiring[slot] = Task { [weak self] in
            await peer.close()
            for operation in pending { await operation.value }
            await self?.finishedRetirement(sessionID, slot: slot)
        }
    }

    private func finishedRetirement(_ id: UUID, slot: UUID) {
        guard let current = session, current.id == id else { return }
        current.retiring.removeValue(forKey: slot)
        guard session === current, !current.closing, ownerIsValid(), revocation.isCurrent(current.id) else { return }
        // Keep this one owned source (with empty, non-buffering fanout) until the user-selected
        // expiry. Rejoining listeners reuse it; no source restart or authorization extension occurs.
        status(.active(listeners: current.recipients.values.filter(\.admitted).count))
    }

    @discardableResult private func probe(_ id: UUID) -> Bool {
        guard let current = session, current.id == id, !current.closing else { return false }
        guard ownerIsValid(), let lease = current.lease, revocation.isCurrent(id) else {
            revocation.revoke(id); Task { await fail(id) }; return false
        }
        var bytes = UUID().uuid
        let nonce = BelugaAudioShareEncoding.encode(withUnsafeBytes(of: &bytes) { Data($0) })
        // The nonce is opaque and unique to this one outstanding request; no overlap is allowed.
        guard lease.expectAcknowledgement(nonce: nonce) else { revocation.revoke(id); Task { await fail(id) }; return false }
        do { try enqueue(.text(Self.encode(["type": "probe", "v": 1, "nonce": nonce])), current); return true }
        catch { revocation.revoke(id); Task { await fail(id) }; return false }
    }

    private func enqueue(_ message: Outbound, _ current: Session) throws {
        try requireCurrent(current)
        guard current.outbox.count < 64, current.outboxBytes + message.size <= 524_288 else {
            revocation.revoke(current.id)
            Task { await fail(current.id) }
            throw BelugaAudioShareCoordinatorError.unavailable
        }
        current.outbox.append(message); current.outboxBytes += message.size
        if current.sendTask == nil {
            let sessionID = current.id
            current.sendTask = Task { [weak self] in await self?.sendLoop(sessionID) }
        }
    }

    private func sendLoop(_ id: UUID) async {
        guard let current = session, current.id == id else { return }
        defer { current.sendTask = nil }
        do {
            while !current.outbox.isEmpty {
                try requireCurrent(current)
                let message = current.outbox.removeFirst(); current.outboxBytes -= message.size
                let text: String
                switch message {
                case .text(let value): text = value
                case .signal(let listenerID, let slot, let plaintext):
                    guard let recipient = current.recipients[listenerID], recipient.slot == slot else { continue }
                    text = String(decoding: try JSONEncoder().encode(recipient.cipher.seal(plaintext)), as: UTF8.self)
                }
                guard text.utf8.count <= 90_000 else { throw BelugaAudioShareCoordinatorError.invalidMessage }
                try await current.socket.send(text)
                try requireCurrent(current)
            }
        } catch { revocation.revoke(id); await fail(id) }
    }

    private func fail(_ id: UUID) async {
        guard let current = session, current.id == id else { return }
        revocation.revoke(id)
        _ = await cleanUp(current)
        publishTerminal(.failed, current)
    }
    private func end(_ id: UUID) async {
        guard let current = session, current.id == id else { return }
        revocation.revoke(id)
        let confirmed = await cleanUp(current)
        publishTerminal(confirmed ? .ended : .failed, current)
    }
    private func publishTerminal(_ value: BelugaAudioShareStatus, _ current: Session) {
        guard latestAttempt == current.id else { return }
        status(value)
    }
    private func cleanUp(_ current: Session) async -> Bool {
        if current.cleanupTask != nil {
            let confirmed = await current.cleanupCompletion.wait(timeout: dependencies.teardownTimeoutNanoseconds)
            finishCleanup(current, confirmed: confirmed)
            return confirmed
        }
        current.closing = true
        revocation.revoke(current.id); current.socket.cancel()
        current.receiveTask?.cancel(); current.heartbeatTask?.cancel(); current.deadlineTask?.cancel()
        current.handshakeTask?.cancel(); current.sendTask?.cancel()
        current.outbox.removeAll(); current.outboxBytes = 0
        let recipients = Array(current.recipients.values)
        let retiring = Array(current.retiring.values)
        let operations = current.operations.values.map(\.task)
        for operation in operations { operation.cancel() }
        current.recipients.removeAll()
        for recipient in recipients {
            recipient.task?.cancel(); recipient.cipher.close(); recipient.peer.revokeCapture()
        }
        let source = current.source, sourceStart = current.sourceStart
        let completion = current.cleanupCompletion
        source?.revokeStart(); sourceStart?.cancel()
        let cleanup = Task { () -> Bool in
            for recipient in recipients { await recipient.peer.close() }
            for retirement in retiring { await retirement.value }
            do {
                // Stop the owned source even if start threw: native startup may be partial.
                try await source?.stop()
                _ = try? await sourceStart?.value
                for operation in operations { await operation.value }
                completion.resolve(true); return true
            } catch { completion.resolve(false); return false }
        }
        current.cleanupTask = cleanup
        let confirmed = await completion.wait(timeout: dependencies.teardownTimeoutNanoseconds)
        finishCleanup(current, confirmed: confirmed)
        return confirmed
    }
    private func finishCleanup(_ current: Session, confirmed: Bool) {
        guard session === current else { return }
        if confirmed { session = nil }
        else { quarantined = true }
    }
}

private extension BelugaAudioShareCoordinator {
    struct Registered: Sendable {
        let shareID: String, generation: String
        let expiresAt: Int64, serverTime: Int64, leaseExpiresAt: Int64
    }
    struct Ready: Sendable {
        let shareID: String, generation: String, listenerID: String
        let expiresAt: Int64, serverTime: Int64
        let iceServers: [RemoteICEServer]
    }
    enum ServerMessage: Sendable {
        case registered(Registered), ready(Ready), probe(nonce: String, time: Int64, expiry: Int64)
        case left(String), signal(BelugaAudioShareSignalEnvelope), ended, error
    }
    enum Payload: Sendable { case answer(String), ice(RemoteICECandidate) }
    struct QueuedPayload: Sendable { let payload: Payload; let bytes: Int }
    static func urls(endpoint: URL, shareID: String) throws -> (URL, URL) {
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              parts.scheme == "https" || parts.scheme == "wss", parts.host != nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw BelugaAudioShareCoordinatorError.invalidConfiguration }
        parts.scheme = "https"; parts.path = ""
        guard let origin = parts.url else { throw BelugaAudioShareCoordinatorError.invalidConfiguration }
        parts.scheme = "wss"; parts.path = "/v3/audio-share/\(shareID)"
        guard let socket = parts.url else { throw BelugaAudioShareCoordinatorError.invalidConfiguration }
        return (socket, origin)
    }
    static func deadline(sentAt: UInt64, milliseconds: Int64) throws -> UInt64 {
        guard (1...86_400_000).contains(milliseconds) else { throw BelugaAudioShareCoordinatorError.invalidMessage }
        let proposed = sentAt.addingReportingOverflow(UInt64(milliseconds) * 1_000_000)
        guard !proposed.overflow else { throw BelugaAudioShareCoordinatorError.invalidMessage }
        return proposed.partialValue
    }
    static func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    static func encode(_ object: [String: Any]) throws -> String { String(decoding: try data(object), as: UTF8.self) }
    static func object(_ text: String, maximum: Int = 90_000) throws -> [String: Any] {
        guard !text.isEmpty, text.utf8.count <= maximum,
              let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw BelugaAudioShareCoordinatorError.invalidMessage
        }
        return value
    }
    static func exact(_ value: [String: Any], _ keys: [String]) throws {
        guard Set(value.keys) == Set(keys) else { throw BelugaAudioShareCoordinatorError.invalidMessage }
    }
    static func integer(_ value: Any?) throws -> Int64 {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              abs(number.doubleValue) <= 9_007_199_254_740_991 else { throw BelugaAudioShareCoordinatorError.invalidMessage }
        return number.int64Value
    }
    static func string(_ value: Any?, max: Int = 256) throws -> String {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= max,
              !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw BelugaAudioShareCoordinatorError.invalidMessage
        }
        return value
    }
    static func id(_ value: Any?) throws -> String {
        let value = try string(value, max: 22)
        _ = try BelugaAudioShareEncoding.decode(value, count: 16...16)
        return value
    }
    static func parse(_ text: String) throws -> ServerMessage {
        let object = try object(text)
        guard try integer(object["v"]) == 1, let type = object["type"] as? String else {
            throw BelugaAudioShareCoordinatorError.invalidMessage
        }
        switch type {
        case "registered":
            try exact(object, ["type", "v", "shareID", "generation", "expiresAt", "serverTime", "leaseExpiresAt", "maxListeners"])
            let time = try integer(object["serverTime"]), expiry = try integer(object["expiresAt"])
            let lease = try integer(object["leaseExpiresAt"])
            guard time > 0, (1...86_400_000).contains(expiry - time),
                  (1...15_000).contains(lease - time), lease <= expiry,
                  try integer(object["maxListeners"]) == 8 else { throw BelugaAudioShareCoordinatorError.invalidMessage }
            return .registered(.init(shareID: try id(object["shareID"]), generation: try id(object["generation"]),
                expiresAt: expiry, serverTime: time, leaseExpiresAt: lease))
        case "listener-ready":
            try exact(object, ["type", "v", "role", "shareID", "generation", "listenerID", "expiresAt", "serverTime", "iceServers"])
            let time = try integer(object["serverTime"]), expiry = try integer(object["expiresAt"])
            guard object["role"] as? String == "owner", time > 0,
                  (1...86_400_000).contains(expiry - time) else { throw BelugaAudioShareCoordinatorError.invalidMessage }
            return .ready(.init(shareID: try id(object["shareID"]), generation: try id(object["generation"]),
                listenerID: try id(object["listenerID"]), expiresAt: expiry, serverTime: time,
                iceServers: try iceServers(object["iceServers"])))
        case "probe-ack":
            try exact(object, ["type", "v", "nonce", "serverTime", "leaseExpiresAt"])
            let time = try integer(object["serverTime"]), expiry = try integer(object["leaseExpiresAt"])
            guard time > 0, (1...15_000).contains(expiry - time) else { throw BelugaAudioShareCoordinatorError.invalidMessage }
            return .probe(nonce: try id(object["nonce"]), time: time, expiry: expiry)
        case "listener-left":
            try exact(object, ["type", "v", "listenerID"]); return .left(try id(object["listenerID"]))
        case "signal":
            try exact(object, ["type", "v", "from", "listenerID", "seq", "ciphertext"])
            let sequence = try integer(object["seq"]), ciphertext = try string(object["ciphertext"], max: 87_382)
            guard object["from"] as? String == "listener", (0...2_147_483_647).contains(sequence) else {
                throw BelugaAudioShareCoordinatorError.invalidMessage
            }
            _ = try BelugaAudioShareEncoding.decode(ciphertext, count: 17...65_536)
            return .signal(.init(type: type, v: 1, listenerID: try id(object["listenerID"]), seq: UInt32(sequence),
                                ciphertext: ciphertext, from: "listener"))
        case "ended":
            try exact(object, ["type", "v", "reason"])
            guard ["expired", "revoked", "owner_lost"].contains(object["reason"] as? String ?? "") else {
                throw BelugaAudioShareCoordinatorError.invalidMessage
            }
            return .ended
        case "error":
            try exact(object, ["type", "v", "error"]); _ = try string(object["error"], max: 64); return .error
        default: throw BelugaAudioShareCoordinatorError.invalidMessage
        }
    }
    static func iceServers(_ value: Any?) throws -> [RemoteICEServer] {
        guard let servers = value as? [[String: Any]], servers.count <= 16 else {
            throw BelugaAudioShareCoordinatorError.invalidMessage
        }
        return try servers.map { server in
            let raw = server["urls"] as? [String] ?? (server["urls"] as? String).map { [$0] }
            guard let urls = raw, (1...8).contains(urls.count), urls.allSatisfy({ url in
                url.utf8.count <= 2_048 && !url.contains(where: { $0.isWhitespace || $0 == "@" }) &&
                    ["stun:", "stuns:", "turn:", "turns:"].contains(where: url.hasPrefix)
            }) else { throw BelugaAudioShareCoordinatorError.invalidMessage }
            let turn = urls.contains(where: { $0.hasPrefix("turn:") || $0.hasPrefix("turns:") })
            if turn {
                guard Set(server.keys) == Set(["urls", "username", "credential"]) ||
                        Set(server.keys) == Set(["urls", "username", "credential", "credentialType"]),
                      server["credentialType"] == nil || server["credentialType"] as? String == "password" else {
                    throw BelugaAudioShareCoordinatorError.invalidMessage
                }
                return RemoteICEServer(urls: urls, username: try string(server["username"], max: 1_024),
                    credential: try string(server["credential"], max: 1_024))
            }
            try exact(server, ["urls"]); return RemoteICEServer(urls: urls)
        }
    }
    static func payload(_ data: Data) throws -> Payload {
        guard data.count <= 49_152, let text = String(data: data, encoding: .utf8) else {
            throw BelugaAudioShareCoordinatorError.invalidMessage
        }
        let value = try object(text, maximum: 49_152)
        if value["kind"] as? String == "answer" {
            try exact(value, ["kind", "sdp"])
            guard let sdp = value["sdp"] as? String, !sdp.isEmpty, sdp.utf8.count <= 49_152 else {
                throw BelugaAudioShareCoordinatorError.invalidMessage
            }
            return .answer(sdp)
        }
        try exact(value, ["kind", "candidate"])
        guard value["kind"] as? String == "ice", let candidate = value["candidate"] as? [String: Any] else {
            throw BelugaAudioShareCoordinatorError.invalidMessage
        }
        try exact(candidate, ["candidate", "sdpMid", "sdpMLineIndex", "usernameFragment"])
        let sdp = try string(candidate["candidate"], max: 2_048)
        guard sdp.hasPrefix("candidate:"), try integer(candidate["sdpMLineIndex"]) == 0 else {
            throw BelugaAudioShareCoordinatorError.invalidMessage
        }
        return .ice(.init(sdp: sdp, sdpMid: try string(candidate["sdpMid"], max: 64), sdpMLineIndex: 0,
                         usernameFragment: try string(candidate["usernameFragment"], max: 256)))
    }
}

private final class NativeAudioShareRecipient: BelugaAudioShareRecipient, @unchecked Sendable {
    let sender: WebRTCAudioShareSender
    let sink: any BelugaAudioShareSink
    var events: AsyncStream<WebRTCAudioShareEvent> { sender.events }
    init(iceServers: [RemoteICEServer], expiresAt: Date) throws {
        sender = try WebRTCAudioShareSender(iceServers: iceServers, expiresAt: expiresAt)
        sink = NativeAudioShareSink(sender: sender)
    }
    func createOffer() async throws -> String { try await sender.createOffer() }
    func setAnswer(_ sdp: String) async throws { try await sender.setAnswer(sdp) }
    func addICE(_ candidate: RemoteICECandidate) async throws { try await sender.addICE(candidate) }
    func admitCapture() async throws { try await sender.admitCapture() }
    func revokeCapture() { sender.revokeCapture() }
    func close() async { await sender.close() }
}
private final class NativeAudioShareSink: BelugaAudioShareSink, @unchecked Sendable {
    private let sender: WebRTCAudioShareSender
    init(sender: WebRTCAudioShareSender) { self.sender = sender }
    func capture(sampleBuffer: CMSampleBuffer) { sender.audioInput.capture(sampleBuffer: sampleBuffer) }
    func capture(audioBufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription,
                 frameCount: UInt32, presentationTime: CMTime) {
        sender.audioInput.capture(audioBufferList: audioBufferList, format: format,
                                  frameCount: frameCount, presentationTime: presentationTime)
    }
    func revokeCapture() { sender.revokeCapture() }
}

private final class NativeAudioShareSource: BelugaAudioShareSource, @unchecked Sendable {
    private let source: SystemAudioCaptureSource
    private let lock = NSLock()
    private var closed = false
    private var starting = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(consumer: BelugaAudioShareFanout, logger: any CaptureCore.Logger) {
        source = SystemAudioCaptureSource(displayID: nil, consumer: consumer, logger: logger)
    }
    func revokeStart() { lock.withLock { closed = true } }
    func start() async throws {
        guard lock.withLock({ () -> Bool in
            guard !closed, !starting else { return false }; starting = true; return true
        }) else { throw BelugaAudioShareCoordinatorError.unavailable }
        defer {
            let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                starting = false; let pending = waiters; waiters.removeAll(); return pending
            }
            pending.forEach { $0.resume() }
        }
        let format = try await source.start()
        guard format.sampleRate == 48_000, format.channelCount == 2,
              lock.withLock({ !closed }) else { throw BelugaAudioShareCoordinatorError.unavailable }
    }
    func stop() async throws {
        revokeStart()
        await withCheckedContinuation { continuation in
            let immediate = lock.withLock { () -> Bool in
                guard starting else { return true }; waiters.append(continuation); return false
            }
            if immediate { continuation.resume() }
        }
        try await source.stop()
    }
}

private final class NativeAudioShareSocket: BelugaAudioShareSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var delegate: AudioShareSocketDelegate?
    private var closed = false
    private var fatal: (@Sendable () -> Void)?

    func open(url: URL, onFatal: @escaping @Sendable () -> Void) async throws {
        let delegate = AudioShareSocketDelegate(fatal: onFatal)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 86_400
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.setValue("beluga.audio-share.v1", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 90_000
        guard lock.withLock({ () -> Bool in
            guard !closed, self.task == nil else { return false }
            self.delegate = delegate; self.session = session; self.task = task; fatal = onFatal
            return true
        }) else { task.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel(); throw BelugaAudioShareCoordinatorError.unavailable }
        task.resume()
        try await withTaskCancellationHandler { try await delegate.wait() } onCancel: { self.cancel() }
    }
    func send(_ text: String) async throws {
        guard text.utf8.count <= 90_000, let task = lock.withLock({ closed ? nil : task }) else {
            throw BelugaAudioShareCoordinatorError.unavailable
        }
        do { try await task.send(.string(text)) }
        catch { cancel(); throw BelugaAudioShareCoordinatorError.unavailable }
    }
    func receive() async throws -> String {
        guard let task = lock.withLock({ closed ? nil : task }) else { throw BelugaAudioShareCoordinatorError.unavailable }
        do {
            guard case .string(let text) = try await task.receive(), text.utf8.count <= 90_000 else {
                throw BelugaAudioShareCoordinatorError.invalidMessage
            }
            return text
        } catch { cancel(); throw BelugaAudioShareCoordinatorError.unavailable }
    }
    func cancel() {
        let retired = lock.withLock { () -> (URLSessionWebSocketTask?, URLSession?, AudioShareSocketDelegate?, (@Sendable () -> Void)?) in
            closed = true; return (task, session, delegate, fatal)
        }
        retired.3?(); retired.2?.fail()
        retired.0?.cancel(with: .normalClosure, reason: nil); retired.1?.invalidateAndCancel()
    }
}

private final class AudioShareSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let fatal: @Sendable () -> Void
    private var result: Result<Void, BelugaAudioShareCoordinatorError>?
    private var waiter: CheckedContinuation<Void, any Error>?
    init(fatal: @escaping @Sendable () -> Void) { self.fatal = fatal }
    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let result = lock.withLock { () -> Result<Void, BelugaAudioShareCoordinatorError>? in
                if let result = self.result { return result }; waiter = continuation; return nil
            }
            if let result { continuation.resume(with: result.mapError { $0 as any Error }) }
        }
    }
    private func resolve(_ value: Result<Void, BelugaAudioShareCoordinatorError>) {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            guard result == nil else { return nil }; result = value
            let pending = self.waiter; self.waiter = nil; return pending
        }
        waiter?.resume(with: value.mapError { $0 as any Error })
    }
    func fail() { fatal(); resolve(.failure(.unavailable)) }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard `protocol` == "beluga.audio-share.v1" else { fail(); webSocketTask.cancel(with: .protocolError, reason: nil); return }
        resolve(.success(()))
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { fail() }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) { fail() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil); fail()
    }
}
