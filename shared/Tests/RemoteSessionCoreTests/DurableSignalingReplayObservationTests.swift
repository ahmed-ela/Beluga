import CryptoKit
import Foundation
import Testing
import os
@testable import RemoteSessionCore

/// PRIVATE, UNCOMPILED. The socket is injected; encryption, JSON decoding,
/// native client parsing and actual stored Rust-backed replay state are real.
struct DurableSignalingReplayObservationTests {
    private let endpoint = URL(string: "wss://rendezvous.example.test")!

    @Test(.timeLimit(.minutes(1))) func pairingSemanticFailureFollowsActualStoredReplayCommit() async throws {
        let invitation = try RemoteInvitationCode(secret: Data(repeating: 81, count: 20))
        let trace = ReplayTrace()
        let socket = ReplaySocket()
        let client = try PairingBootstrapSignalingClient(endpoint: endpoint,
            invitation: invitation, role: .host, transport: socket, replayObserver: { trace.record($0) })
        do {
            var iterator = try await client.connect().makeAsyncIterator()
            // A genuine, structurally valid host hello encrypted as the viewer
            // is decoded, then rejected by the native sender-role validation.
            let payload = try hello(invitation: invitation, role: .host)
            let envelope = try sealPairing(payload, invitation: invitation, role: .viewer, sequence: 0)
            await socket.push(try pairingWire(envelope, from: .viewer))
            do { _ = try await iterator.next(); Issue.record("Wrong-sender hello was delivered") }
            catch { #expect(error as? RemoteSessionCoreError == .invalidSignalPayload); trace.terminal() }
            let entries = trace.entries()
            #expect(entries.count == 3)
            if entries.count == 3 {
                #expect(entries[0].kind == .initialized)
                #expect(entries[1].kind == .accepted)
                #expect(entries[1].hasHighest == 1 && entries[1].highest == 0 && entries[1].bitmap == 1)
                #expect(entries[2].kind == .terminal)
            }
            await client.close()
        } catch { await client.close(); throw error }
    }

    @Test(.timeLimit(.minutes(1))) func availabilitySemanticFailureFollowsActualStoredReplayCommit() async throws {
        let locator = try locator(role: .viewer)
        let exchange = try exchange(0)
        let trace = ReplayTrace()
        let socket = ReplaySocket()
        let client = try PairedAvailabilitySignalingClient(endpoint: endpoint, locator: locator,
            role: .viewer, transport: socket, replayObserver: { trace.record($0) })
        do {
            var iterator = try await client.connect().makeAsyncIterator()
            await socket.push(ready(exchange, role: .viewer))
            #expect(try await iterator.next() == .ready(role: .viewer, exchangeID: exchange))
            let hostLocator = try self.locator(role: .host)
            let cipher = RemoteAvailabilityCipher(credential: try hostLocator.credential(exchangeID: exchange),
                exchangeID: exchange, role: .host)
            // AEAD is genuine. The bounded reconnect fields satisfy structure;
            // signatures are not verified by this parser and are not claimed here.
            let envelope = try cipher.seal(.reconnectRequest(structuralRequest()), sequence: 0)
            await socket.push(try availabilityWire(envelope, from: .host))
            do { _ = try await iterator.next(); Issue.record("Host-origin request was delivered") }
            catch { #expect(error as? RemoteSessionCoreError == .invalidSignalPayload); trace.terminal() }
            let entries = trace.entries()
            #expect(entries.count == 4)
            if entries.count == 4 {
                #expect(entries[0].kind == .initialized && entries[1].kind == .initialized)
                #expect(entries[2].kind == .accepted && entries[2].highest == 0 && entries[2].bitmap == 1)
                #expect(entries[3].kind == .terminal)
            }
            await client.close()
        } catch { await client.close(); throw error }
    }

    @Test(.timeLimit(.minutes(1))) func validatedPairingDepartureResetsOnceAndAllowsFreshZero() async throws {
        let invitation = try RemoteInvitationCode(secret: Data(repeating: 82, count: 20))
        let trace = ReplayTrace()
        let socket = ReplaySocket()
        let client = try PairingBootstrapSignalingClient(endpoint: endpoint,
            invitation: invitation, role: .host, transport: socket, replayObserver: { trace.record($0) })
        do {
            var iterator = try await client.connect().makeAsyncIterator()
            let payload = try hello(invitation: invitation, role: .viewer)
            await socket.push(try pairingWire(sealPairing(payload, invitation: invitation,
                role: .viewer, sequence: 0), from: .viewer))
            #expect(try await iterator.next() == .signal(payload))
            #expect(trace.initializations() == 1)
            await socket.push(#"{"type":"peer-left","role":"viewer"}"#)
            #expect(try await iterator.next() == .peerLeft(.viewer))
            #expect(trace.initializations() == 2)
            #expect(trace.entries().last?.hasHighest == 0)
            await socket.push(try pairingWire(sealPairing(payload, invitation: invitation,
                role: .viewer, sequence: 0), from: .viewer))
            #expect(try await iterator.next() == .signal(payload))
            #expect(trace.acceptances() == 2 && trace.initializations() == 2)
            await client.close()
        } catch { await client.close(); throw error }
    }

    @Test(.timeLimit(.minutes(1))) func availabilityExactDepartureAndRepeatedReadyPreserveOriginalResetOrder() async throws {
        let hostLocator = try locator(role: .host)
        let viewerLocator = try locator(role: .viewer)
        let first = try exchange(0)
        let second = try exchange(16)
        let trace = ReplayTrace()
        let socket = ReplaySocket()
        let client = try PairedAvailabilitySignalingClient(endpoint: endpoint, locator: hostLocator,
            role: .host, transport: socket, replayObserver: { trace.record($0) })
        do {
            var iterator = try await client.connect().makeAsyncIterator()
            let payload = RemoteAvailabilityPayload.reconnectRequest(structuralRequest())
            for current in [first, first] {
                await socket.push(ready(current, role: .host))
                #expect(try await iterator.next() == .ready(role: .host, exchangeID: current))
                let cipher = RemoteAvailabilityCipher(credential: try viewerLocator.credential(exchangeID: current),
                    exchangeID: current, role: .viewer)
                await socket.push(try availabilityWire(cipher.seal(payload, sequence: 0), from: .viewer))
                #expect(try await iterator.next() == .signal(payload))
            }
            #expect(trace.initializations() == 3 && trace.acceptances() == 2)
            await socket.push(#"{"type":"availability-peer-left","role":"viewer","exchangeID":"\#(first.wireValue)"}"#)
            #expect(try await iterator.next() == .peerLeft(role: .viewer, exchangeID: first))
            #expect(trace.initializations() == 4)
            await socket.push(ready(second, role: .host))
            #expect(try await iterator.next() == .ready(role: .host, exchangeID: second))
            let cipher = RemoteAvailabilityCipher(credential: try viewerLocator.credential(exchangeID: second),
                exchangeID: second, role: .viewer)
            await socket.push(try availabilityWire(cipher.seal(payload, sequence: 0), from: .viewer))
            #expect(try await iterator.next() == .signal(payload))
            #expect(trace.initializations() == 5 && trace.acceptances() == 3)
            await client.close()
        } catch { await client.close(); throw error }
    }

    @Test(.timeLimit(.minutes(1))) func wrongRolePairingDepartureCannotResetStoredReplayOwner() async throws {
        let invitation = try RemoteInvitationCode(secret: Data(repeating: 83, count: 20))
        let trace = ReplayTrace()
        let socket = ReplaySocket()
        let client = try PairingBootstrapSignalingClient(endpoint: endpoint,
            invitation: invitation, role: .host, transport: socket, replayObserver: { trace.record($0) })
        do {
            var iterator = try await client.connect().makeAsyncIterator()
            let payload = try hello(invitation: invitation, role: .viewer)
            await socket.push(try pairingWire(sealPairing(payload, invitation: invitation,
                role: .viewer, sequence: 0), from: .viewer))
            #expect(try await iterator.next() == .signal(payload))
            let before = trace.entries()
            await socket.push(#"{"type":"peer-left","role":"host"}"#)
            do { _ = try await iterator.next(); Issue.record("Foreign-role departure was delivered") }
            catch { #expect(error as? RendezvousSignalingError == .invalidServerMessage) }
            #expect(trace.entries() == before)
            #expect(trace.initializations() == 1 && trace.acceptances() == 1)
            await client.close()
        } catch { await client.close(); throw error }
    }

    @Test(.timeLimit(.minutes(1))) func foreignAvailabilityDepartureOrReadyCannotResetStoredReplayOwner() async throws {
        let hostLocator = try locator(role: .host)
        let viewerLocator = try locator(role: .viewer)
        let current = try exchange(0)
        let foreign = try exchange(16)
        let invalidMessages = [
            #"{"type":"availability-peer-left","role":"host","exchangeID":"\#(current.wireValue)"}"#,
            #"{"type":"availability-peer-left","role":"viewer","exchangeID":"\#(foreign.wireValue)"}"#,
            ready(foreign, role: .viewer)
        ]
        for invalid in invalidMessages {
            let trace = ReplayTrace()
            let socket = ReplaySocket()
            let client = try PairedAvailabilitySignalingClient(endpoint: endpoint, locator: hostLocator,
                role: .host, transport: socket, replayObserver: { trace.record($0) })
            do {
                var iterator = try await client.connect().makeAsyncIterator()
                await socket.push(ready(current, role: .host))
                #expect(try await iterator.next() == .ready(role: .host, exchangeID: current))
                let cipher = RemoteAvailabilityCipher(credential: try viewerLocator.credential(exchangeID: current),
                    exchangeID: current, role: .viewer)
                let payload = RemoteAvailabilityPayload.reconnectRequest(structuralRequest())
                await socket.push(try availabilityWire(cipher.seal(payload, sequence: 0), from: .viewer))
                #expect(try await iterator.next() == .signal(payload))
                let before = trace.entries()
                await socket.push(invalid)
                do { _ = try await iterator.next(); Issue.record("Foreign availability owner was delivered") }
                catch { #expect(error as? RendezvousSignalingError == .invalidServerMessage) }
                #expect(trace.entries() == before)
                #expect(trace.initializations() == 2 && trace.acceptances() == 1)
                await client.close()
            } catch { await client.close(); throw error }
        }
    }

    private func hello(invitation: RemoteInvitationCode, role: RemotePeerRole) throws -> RemotePairingPayload {
        let identity = try RemoteDeviceIdentity(deviceID: UUID(), role: role, displayName: "Replay fixture",
            signingPrivateKeyRawRepresentation: Data(repeating: role == .host ? 0x31 : 0x32, count: 32))
        return .hello(try RemotePairingParticipant(identity: identity, invitation: invitation,
            ephemeralPrivateKeyRawRepresentation: Data(repeating: 0x41, count: 32),
            nonce: Data(repeating: 0x51, count: 32)).hello)
    }

    private func sealPairing(_ payload: RemotePairingPayload, invitation: RemoteInvitationCode,
                             role: RemotePeerRole, sequence: UInt64) throws -> SealedSignalingEnvelope {
        let credential = RemoteRendezvousCredential(invitation: invitation)
        let direction: RemoteSignalDirection = role == .host ? .hostToViewer : .viewerToHost
        let header = SealedSignalingEnvelope(channelID: credential.channelID, direction: direction,
            sequence: sequence, ciphertext: Data())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let key = role == .host ? credential.hostToViewer : credential.viewerToHost
        let box = try ChaChaPoly.seal(encoder.encode(payload), using: SymmetricKey(data: key),
            authenticating: header.additionalAuthenticatedData)
        return .init(channelID: header.channelID, direction: direction,
                     sequence: sequence, ciphertext: box.combined)
    }

    private func pairingWire(_ envelope: SealedSignalingEnvelope, from: RemotePeerRole) throws -> String {
        try wire(["type": "signal", "from": from.rawValue, "seq": envelope.sequence,
                  "envelope": base64URL(JSONEncoder().encode(envelope))])
    }

    private func availabilityWire(_ envelope: SealedAvailabilityEnvelope, from: RemotePeerRole) throws -> String {
        try wire(["type": "availability-signal", "from": from.rawValue, "seq": envelope.sequence,
                  "exchangeID": envelope.exchangeID.wireValue,
                  "envelope": base64URL(JSONEncoder().encode(envelope))])
    }

    private func wire(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func ready(_ exchange: RemoteAvailabilityExchangeID, role: RemotePeerRole) -> String {
        #"{"type":"availability-ready","role":"\#(role.rawValue)","exchangeID":"\#(exchange.wireValue)"}"#
    }

    private func locator(role: RemotePeerRole) throws -> RemoteAvailabilityLocator {
        try .init(pairRootKey: Data(repeating: 0xA1, count: 32),
            pairID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            pairingTranscriptHash: Data(repeating: 0xB2, count: 32), localRole: role)
    }

    private func exchange(_ first: UInt8) throws -> RemoteAvailabilityExchangeID {
        try .init(rawValue: Data((0..<16).map { first + UInt8($0) }))
    }

    private func structuralRequest() -> RemoteReconnectRequest {
        .init(protocolVersion: RemoteReconnectRequest.currentProtocolVersion,
            pairID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            requesterDeviceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            requesterRole: .viewer, targetDeviceID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            sequence: 1, ephemeralKeyAgreementPublicKey: Data(repeating: 1, count: 32),
            nonce: Data(repeating: 2, count: 32), signature: Data(repeating: 3, count: 64))
    }
}

private struct ReplayTrace: Sendable {
    enum Kind: Equatable, Sendable { case initialized, accepted, rejected, faulted, terminal }
    struct Snapshot: Equatable, Sendable {
        let abiVersion: UInt32
        let hasHighest: UInt32
        let highest: UInt64
        let bitmap: UInt64
    }
    struct Entry: Equatable, Sendable {
        let kind: Kind
        let stored: Snapshot?
        let sequence: UInt64?
        let error: RemoteSessionCoreError?
        var hasHighest: UInt32? { stored?.hasHighest }
        var highest: UInt64? { stored?.highest }
        var bitmap: UInt64? { stored?.bitmap }
    }
    private let values = OSAllocatedUnfairLock(initialState: [Entry]())
    func record(_ observation: BelugaRustSignalingReplayObservation) {
        let kind: Kind
        switch observation.kind {
        case .initialized: kind = .initialized
        case .accepted: kind = .accepted
        case .rejected: kind = .rejected
        case .faulted: kind = .faulted
        }
        values.withLock { $0.append(.init(kind: kind,
            stored: .init(abiVersion: observation.stored.abi_version,
                hasHighest: observation.stored.has_highest, highest: observation.stored.highest,
                bitmap: observation.stored.bitmap), sequence: observation.sequence, error: observation.error)) }
    }
    func terminal() {
        values.withLock { $0.append(.init(kind: .terminal, stored: nil, sequence: nil, error: nil)) }
    }
    func entries() -> [Entry] { values.withLock { $0 } }
    func initializations() -> Int { entries().filter { $0.kind == .initialized }.count }
    func acceptances() -> Int { entries().filter { $0.kind == .accepted }.count }
}

private enum ReplaySocketError: Error { case closed }
private actor ReplaySocket: RendezvousSocketTransport {
    private var queued = [RendezvousSocketMessage]()
    private var waiter: CheckedContinuation<RendezvousSocketMessage, any Error>?
    private var closed = false

    func connect(to _: URL, channelID _: RendezvousChannelID, role _: RemotePeerRole,
                 admissionProof _: RendezvousAdmissionProof, viewerAdmissionProof _: RendezvousAdmissionProof?,
                 mode _: RemoteRendezvousMode) async throws {}
    func send(text _: String) async throws {}
    func sendPing(timeoutNanoseconds _: UInt64) async throws {}
    func receive() async throws -> RendezvousSocketMessage {
        if !queued.isEmpty { return queued.removeFirst() }
        if closed { throw ReplaySocketError.closed }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }
    func close() async {
        closed = true
        waiter?.resume(throwing: ReplaySocketError.closed)
        waiter = nil
        queued.removeAll()
    }
    func push(_ text: String) {
        guard !closed else { return }
        let message = RendezvousSocketMessage.text(text)
        if let waiter { self.waiter = nil; waiter.resume(returning: message) }
        else { queued.append(message) }
    }
}
