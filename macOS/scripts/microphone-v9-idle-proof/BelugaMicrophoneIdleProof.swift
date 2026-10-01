import CoreAudio
import CryptoKit
import Darwin
import Foundation

// Compile with the unchanged product WorldwideVirtualMicrophoneDriverIdle.swift.
// This component has no active-consumer, route-write, listener, or restart API.
enum BelugaMicrophoneIdlePhase: String, Codable, Sendable {
    case beforePublish = "before-publish"
    case afterReload = "after-reload"
    case afterProbe = "after-probe"
    case afterRollback = "after-rollback"

    var schema: UInt32 { self == .beforePublish || self == .afterRollback ? 1 : 2 }
}

enum BelugaMicrophoneIdleFailure: Error, Equatable, Sendable {
    case arguments
    case callerIdentity
    case endpointIdentity
    case endpointsChanged
    case propertyRead(Int, WorldwideVirtualMicrophoneDriverDiagnosticError)
    case captureBoundary
    case schemaMismatch
    case instanceMismatch
    case unstableOrActive
    case probeHistoryMissing

    var code: String {
        switch self {
        case .arguments: return "ARGUMENTS"
        case .callerIdentity: return "CALLER_IDENTITY"
        case .endpointIdentity: return "ENDPOINT_IDENTITY"
        case .endpointsChanged: return "ENDPOINTS_CHANGED"
        case .propertyRead: return "PROPERTY_READ"
        case .captureBoundary: return "CAPTURE_BOUNDARY"
        case .schemaMismatch: return "SCHEMA_MISMATCH"
        case .instanceMismatch: return "INSTANCE_MISMATCH"
        case .unstableOrActive: return "UNSTABLE_OR_ACTIVE"
        case .probeHistoryMissing: return "PROBE_HISTORY_MISSING"
        }
    }
}

struct BelugaMicrophoneIdleRequest: Sendable {
    let phase: BelugaMicrophoneIdlePhase
    let schema: UInt32
    let nonce: String
    let expectedInstance: UInt64?
    let isBootstrap: Bool
    let isPriorBootstrap: Bool

    init(arguments: [String]) throws {
        guard arguments.count == 7 || arguments.count == 9,
              arguments[1] == "--phase", arguments[3] == "--schema",
              arguments[5] == "--nonce",
              let phase = BelugaMicrophoneIdlePhase(rawValue: arguments[2]),
              let schema = UInt32(arguments[4]), arguments[4] == String(schema),
              arguments[6].utf8.count == 64,
              arguments[6].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              schema == phase.schema else {
            throw BelugaMicrophoneIdleFailure.arguments
        }
        let priorBootstrap = arguments[0] == "--bootstrap-prior-instance"
        let bootstrap = arguments[0] == "--bootstrap-instance" || priorBootstrap
        let instance: UInt64?
        if bootstrap {
            guard arguments.count == 7, phase == (priorBootstrap ? .afterRollback : .afterReload) else {
                throw BelugaMicrophoneIdleFailure.arguments
            }
            instance = nil
        } else {
            guard arguments.count == 9, arguments[7] == "--expected-instance",
                  let parsed = UInt64(arguments[8]), parsed > 0, arguments[8] == String(parsed),
                  arguments[0] == (phase == .afterReload ? "--observe-initial-idle" : "--verify-idle") else {
                throw BelugaMicrophoneIdleFailure.arguments
            }
            instance = parsed
        }
        self.phase = phase
        self.schema = schema
        self.nonce = arguments[6]
        self.expectedInstance = instance
        self.isBootstrap = bootstrap
        self.isPriorBootstrap = priorBootstrap
    }
}

struct BelugaMicrophoneEndpoints: Equatable, Sendable {
    static let visibleUID = "com.elamin.opensteamer.virtual-microphone.input"
    static let writerUID = "com.elamin.opensteamer.virtual-microphone.writer"
    let visible: AudioDeviceID
    let writer: AudioDeviceID
    let visibleStream: AudioStreamID
    let writerStream: AudioStreamID

    init(visible: AudioDeviceID, writer: AudioDeviceID, visibleStream: AudioStreamID = 0, writerStream: AudioStreamID = 0) {
        self.visible = visible; self.writer = writer
        self.visibleStream = visibleStream; self.writerStream = writerStream
    }

    var isValid: Bool {
        visible != kAudioObjectUnknown && writer != kAudioObjectUnknown && visible != writer &&
        visibleStream != kAudioObjectUnknown && writerStream != kAudioObjectUnknown && visibleStream != writerStream
    }
}

struct BelugaMicrophoneIdleEpoch: Encodable, Sendable {
    let instance: UInt64
    let driverLifecycle: UInt64
    let coreLifecycle: UInt64
    let timelineSeed: UInt64
    let seedGeneration: UInt64
    let anchorHostTicks: UInt64
    let lastIssuedSeed: UInt64
    let lastIssuedSessionID: UInt64

    init(_ value: WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.Epoch) {
        instance = value.instance
        driverLifecycle = value.driverLifecycle
        coreLifecycle = value.coreLifecycle
        timelineSeed = value.timelineSeed
        seedGeneration = value.seedGeneration
        anchorHostTicks = value.anchorHostTicks
        lastIssuedSeed = value.lastIssuedSeed
        lastIssuedSessionID = value.lastIssuedSessionID
    }
}

struct BelugaMicrophoneIdleObservation: Encodable, Sendable {
    let deviceUID: String
    let deviceID: AudioDeviceID
    let selector: String
    let sequence: UInt64
    let capturedHostTicks: UInt64
    let beforeHostTicks: UInt64
    let afterHostTicks: UInt64
    let byteCount: Int
    let payloadSHA256: String
    let registeredCount: UInt64
    let registryRevision: UInt64?
    let epoch: BelugaMicrophoneIdleEpoch
}

struct BelugaMicrophoneIdleResult: Encodable, Sendable {
    let contract = "beluga.microphone.passive-idle.v1"
    let kind: String
    let idleAcceptance: Bool
    let requiresPublicProbe: Bool
    let requiresFreshMirroredIdle: Bool
    let initialPristine: Bool
    let phase: BelugaMicrophoneIdlePhase
    let schema: UInt32
    let nonce: String
    let effectiveUID: UInt32
    let expectedInstance: UInt64
    let visibleUID = BelugaMicrophoneEndpoints.visibleUID
    let writerUID = BelugaMicrophoneEndpoints.writerUID
    let visibleDeviceID: AudioDeviceID
    let writerDeviceID: AudioDeviceID
    let endpointContract = "exact-product-model-role-native-f32-mono-48000-clock-6f73564d.v1"
    let visibleStreamID: AudioStreamID
    let writerStreamID: AudioStreamID
    let observations: [BelugaMicrophoneIdleObservation]

    // The distinct initialized-state classification is deliberately non-green.
    var exitCode: Int32 { idleAcceptance ? 0 : 75 }
}

private struct BelugaMicrophoneCapturedProperty: Sendable {
    let deviceID: AudioDeviceID
    let selector: AudioObjectPropertySelector
    let before: UInt64
    let after: UInt64
    let payload: Data?
}

// Synchronous native reads, not an actor. Lock protects injected callbacks and
// makes capture ownership explicit without changing the production decoder.
private final class BelugaMicrophonePropertyCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var last: BelugaMicrophoneCapturedProperty?
    private let rawRead: WorldwideVirtualMicrophoneDriverDiagnosticReader.PropertyRead
    private let ticks: @Sendable () -> UInt64

    init(rawRead: @escaping WorldwideVirtualMicrophoneDriverDiagnosticReader.PropertyRead,
         ticks: @escaping @Sendable () -> UInt64) {
        self.rawRead = rawRead
        self.ticks = ticks
    }

    func read(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress,
              _ size: inout UInt32, _ value: inout Unmanaged<CFPropertyList>?) -> OSStatus {
        let before = ticks()
        let status = rawRead(device, address, &size, &value)
        let after = ticks()
        var payload: Data?
        if status == noErr,
           size == UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size),
           let property = value?.takeUnretainedValue(), CFGetTypeID(property) == CFDataGetTypeID() {
            let data = unsafeDowncast(property, to: CFData.self)
            let count = CFDataGetLength(data)
            if count > 0, count <= WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.maximumV2ByteCount,
               let bytes = CFDataGetBytePtr(data) {
                payload = Data(bytes: bytes, count: count)
            }
        }
        lock.lock()
        last = .init(deviceID: device, selector: address.mSelector, before: before, after: after, payload: payload)
        lock.unlock()
        return status
    }

    func take() -> BelugaMicrophoneCapturedProperty? {
        lock.lock()
        defer { lock.unlock() }
        let result = last
        last = nil
        return result
    }

    // Bootstrap cannot try the frozen v1 property. The production decoder and
    // its exact CF IPC/freshness contract still govern this single v2 read.
    func readV2Only(_ device: AudioDeviceID) -> Result<WorldwideVirtualMicrophoneDriverDiagnosticSnapshot, WorldwideVirtualMicrophoneDriverDiagnosticError> {
        var size = UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size)
        var value: Unmanaged<CFPropertyList>?
        let address = AudioObjectPropertyAddress(mSelector: WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.v2Property,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let before = ticks()
        let status = read(device, address, &size, &value)
        let after = ticks()
        defer { value?.release() }
        guard status == noErr else { return .failure(.property(status)) }
        guard size == MemoryLayout<Unmanaged<CFPropertyList>?>.size else { return .failure(.propertySize(size)) }
        guard let property = value?.takeUnretainedValue(), CFGetTypeID(property) == CFDataGetTypeID() else {
            return .failure(.propertyType)
        }
        let data = unsafeDowncast(property, to: CFData.self)
        let count = CFDataGetLength(data)
        guard count >= WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.v2HeaderByteCount,
              count <= WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.maximumV2ByteCount else {
            return .failure(.snapshotSize(count))
        }
        guard let bytes = CFDataGetBytePtr(data) else { return .failure(.propertyType) }
        let result = WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decodeV2(Data(bytes: bytes, count: count))
        guard case .success(let snapshot) = result else { return result }
        guard before <= snapshot.capturedHostTicks, snapshot.capturedHostTicks <= after else {
            return .failure(.staleObservation)
        }
        return result
    }
}

struct BelugaMicrophoneIdleProof: Sendable {
    typealias EndpointResolver = @Sendable () throws -> BelugaMicrophoneEndpoints
    private let rawRead: WorldwideVirtualMicrophoneDriverDiagnosticReader.PropertyRead
    private let ticks: @Sendable () -> UInt64
    private let endpoints: EndpointResolver
    private let betweenReads: @Sendable () -> Void

    init(readProperty: @escaping WorldwideVirtualMicrophoneDriverDiagnosticReader.PropertyRead,
         hostTicks: @escaping @Sendable () -> UInt64,
         resolveEndpoints: @escaping EndpointResolver,
         betweenReads: @escaping @Sendable () -> Void) {
        rawRead = readProperty
        ticks = hostTicks
        endpoints = resolveEndpoints
        self.betweenReads = betweenReads
    }

    func collect(_ request: BelugaMicrophoneIdleRequest, effectiveUID: UInt32) throws -> BelugaMicrophoneIdleResult {
        guard effectiveUID == 501 else { throw BelugaMicrophoneIdleFailure.callerIdentity }
        let initial = try endpoints()
        guard initial.isValid else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        let capture = BelugaMicrophonePropertyCapture(rawRead: rawRead, ticks: ticks)
        let reader = WorldwideVirtualMicrophoneDriverDiagnosticReader(
            readProperty: { device, address, size, value in capture.read(device, address, &size, &value) },
            hostTicks: ticks
        )
        var decoded: [WorldwideVirtualMicrophoneDriverDiagnosticSnapshot] = []
        var payloads: [Data] = []
        var evidence: [BelugaMicrophoneIdleObservation] = []
        let observationCount = request.isBootstrap ? 1 : 4
        for index in 0..<observationCount {
            guard try endpoints() == initial else { throw BelugaMicrophoneIdleFailure.endpointsChanged }
            let visible = index % 2 == 0
            let device = visible ? initial.visible : initial.writer
            let snapshot: WorldwideVirtualMicrophoneDriverDiagnosticSnapshot
            switch request.isBootstrap && !request.isPriorBootstrap ? capture.readV2Only(device) : reader.read(device) {
            case .failure(let failure): throw BelugaMicrophoneIdleFailure.propertyRead(index, failure)
            case .success(let value): snapshot = value
            }
            guard let captured = capture.take(), let data = captured.payload,
                  captured.deviceID == device,
                  captured.selector == (snapshot.schemaVersion == 2 ?
                    WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.v2Property :
                    WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.property),
                  captured.before <= snapshot.capturedHostTicks,
                  snapshot.capturedHostTicks <= captured.after else {
                throw BelugaMicrophoneIdleFailure.captureBoundary
            }
            guard snapshot.schemaVersion == request.schema else { throw BelugaMicrophoneIdleFailure.schemaMismatch }
            if let expected = request.expectedInstance, snapshot.epoch.instance != expected {
                throw BelugaMicrophoneIdleFailure.instanceMismatch
            }
            guard try endpoints() == initial else { throw BelugaMicrophoneIdleFailure.endpointsChanged }
            decoded.append(snapshot)
            payloads.append(data)
            evidence.append(.init(
                deviceUID: visible ? BelugaMicrophoneEndpoints.visibleUID : BelugaMicrophoneEndpoints.writerUID,
                deviceID: device, selector: snapshot.schemaVersion == 2 ? "osD2" : "osDS",
                sequence: snapshot.sequence, capturedHostTicks: snapshot.capturedHostTicks,
                beforeHostTicks: captured.before, afterHostTicks: captured.after,
                byteCount: data.count, payloadSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                registeredCount: Self.u64(data, snapshot.schemaVersion == 2 ? 184 : 144),
                registryRevision: snapshot.schemaVersion == 2 ? Self.u64(data, 32) : nil,
                epoch: .init(snapshot.epoch)
            ))
            if index != observationCount - 1 { betweenReads() }
        }
        guard try endpoints() == initial else { throw BelugaMicrophoneIdleFailure.endpointsChanged }
        guard request.isBootstrap ? decoded.count == 1 && decoded[0].isIdle :
                WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(decoded) else {
            throw BelugaMicrophoneIdleFailure.unstableOrActive
        }
        if request.phase == .afterProbe {
            guard zip(decoded, payloads).allSatisfy({ snapshot, payload in
                snapshot.epoch.driverLifecycle > 1 && snapshot.epoch.coreLifecycle > 0 &&
                snapshot.epoch.lastIssuedSeed > 0 && snapshot.epoch.lastIssuedSessionID > 0 &&
                Self.u64(payload, 272) > 0 && Self.u64(payload, 288) > 0 &&
                Self.u64(payload, 296) > 0 && Self.u64(payload, 304) > 0
            }) else { throw BelugaMicrophoneIdleFailure.probeHistoryMissing }
        }
        let initialIdle = request.phase == .afterReload
        return .init(kind: request.isPriorBootstrap ? "PRIOR_INSTANCE_REQUIRES_FRESH_MIRRORED_IDLE" :
                     request.isBootstrap ? "BOOTSTRAP_INSTANCE_REQUIRES_FRESH_IDLE_AND_PUBLIC_PROBE" :
                     (initialIdle ? "INITIAL_COMPLETE_IDLE_REQUIRES_PUBLIC_PROBE" : "NORMAL_IDLE"),
                     idleAcceptance: !initialIdle && !request.isPriorBootstrap, requiresPublicProbe: initialIdle,
                     requiresFreshMirroredIdle: request.isBootstrap,
                     initialPristine: initialIdle && payloads.allSatisfy(Self.isExactInitializedPristineV2),
                     phase: request.phase, schema: request.schema, nonce: request.nonce,
                     effectiveUID: effectiveUID, expectedInstance: decoded[0].epoch.instance,
                     visibleDeviceID: initial.visible, writerDeviceID: initial.writer,
                     visibleStreamID: initial.visibleStream, writerStreamID: initial.writerStream, observations: evidence)
    }

    private static func u64(_ data: Data, _ offset: Int) -> UInt64 {
        data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
    }

    // More restrictive than normal idle. Initializer sets driver lifecycle 1
    // and core lifecycle 0; no registrations, attempts, retired cores, I/O or
    // issued seed/session may have appeared. This never substitutes for PCM.
    private static func isExactInitializedPristineV2(_ data: Data) -> Bool {
        guard data.count == WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.v2HeaderByteCount,
              case .success(let snapshot) = WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decodeV2(data),
              snapshot.isIdle, snapshot.epoch.driverLifecycle == 1,
              snapshot.epoch.coreLifecycle == 0, u64(data, 72) == 0x7_FF01,
              u64(data, 96) > 0 else { return false }
        var remaining = data
        // Exact ABI fields already checked by production decode or predicates.
        for range in [0..<16, 24..<32, 40..<44, 48..<88, 96..<104] {
            remaining.replaceSubrange(range, with: repeatElement(UInt8(0), count: range.count))
        }
        return remaining.allSatisfy { $0 == 0 }
    }
}

enum BelugaMicrophoneLiveEndpoints {
    static func resolve() throws -> BelugaMicrophoneEndpoints {
        let visible = try translate(BelugaMicrophoneEndpoints.visibleUID)
        let writer = try translate(BelugaMicrophoneEndpoints.writerUID)
        let visibleStream = try BelugaMicrophoneEndpointContract.validate(device: visible, visible: true)
        let writerStream = try BelugaMicrophoneEndpointContract.validate(device: writer, visible: false)
        let result = BelugaMicrophoneEndpoints(visible: visible, writer: writer,
                                              visibleStream: visibleStream, writerStream: writerStream)
        guard result.isValid else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        return result
    }

    private static func translate(_ uid: String) throws -> AudioDeviceID {
        guard let expected = CFStringCreateWithCString(kCFAllocatorDefault, uid, CFStringBuiltInEncodings.UTF8.rawValue) else {
            throw BelugaMicrophoneIdleFailure.endpointIdentity
        }
        // C ABI expects a pointer to one CFStringRef, not the Swift reference
        // container's storage. Keep expected alive through translation/readback.
        var qualifier = UnsafeRawPointer(Unmanaged.passUnretained(expected).toOpaque())
        var device: AudioDeviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                               UInt32(MemoryLayout<UnsafeRawPointer>.size), &qualifier, &size, &device)
        guard status == noErr, size == MemoryLayout<AudioDeviceID>.size, device != kAudioObjectUnknown else {
            throw BelugaMicrophoneIdleFailure.endpointIdentity
        }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var actual: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let uidStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &actual)
        defer { actual?.release() }
        guard uidStatus == noErr, size == MemoryLayout<Unmanaged<CFString>?>.size,
              let found = actual?.takeUnretainedValue(), CFGetTypeID(found) == CFStringGetTypeID(),
              CFEqual(found, expected) else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        return device
    }
}
