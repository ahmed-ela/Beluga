// PRIVATE UNCOMPILED COPY-ONLY TEST SUPPORT. Never enrolled/executed by this agent.
import BelugaCore
import CoreAudio
import Foundation
import XCTest
@testable import CaptureCore
@testable import CaptureServer
@testable import WebRTCTransport

final class BatchAInertTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func record(_ value: String) { lock.withLock { values.append(value) } }
    var events: [String] { lock.withLock { values } }
    func count(_ value: String) -> Int { events.filter { $0 == value }.count }
}

/// Implements only the existing native IO operation protocols. All route state
/// is local memory. Actual monitor, lease, invariant, and gate remain production.
final class BatchAInertHAL: BlackHoleDeviceAvailabilityMonitoringOperations,
    BlackHoleDefaultInputLeaseOperations, WorldwideSafeOutputInvariantOperations,
    @unchecked Sendable
{
    struct Listener: @unchecked Sendable {
        var address: AudioObjectPropertyAddress
        let queue: DispatchQueue
        let registration: CoreAudioPropertyListenerRegistration
    }
    let trace: BatchAInertTrace
    private let lock = NSLock()
    private var inputID: AudioDeviceID = 1
    private var inputListener: Listener?
    private var deviceListener: Listener?
    struct OutputListener: @unchecked Sendable {
        let queue: DispatchQueue
        let registration: CoreAudioPropertyListenerRegistration
    }
    private var outputListeners: [BlackHoleDefaultOutputKind: OutputListener] = [:]
    private var writtenInputIDs: [AudioDeviceID] = []
    private let uidByID: [AudioDeviceID: String] = [
        1: "BuiltInMic_UID",
        2: WorldwideVirtualMicrophoneEndpointContract.visibleDefaultInputDeviceUID,
        3: WorldwideVirtualMicrophoneEndpointContract.hiddenMirrorSinkDeviceUID,
        4: "BuiltInSpeakerDevice"
    ]
    init(trace: BatchAInertTrace) { self.trace = trace }
    var inputWrites: [AudioDeviceID] { lock.withLock { writtenInputIDs } }
    var inputUID: String { lock.withLock { uidByID[inputID]! } }
    var listenerCount: Int {
        lock.withLock {
            (inputListener == nil ? 0 : 1) + (deviceListener == nil ? 0 : 1)
                + outputListeners.count
        }
    }

    func addDevicesListener(address: inout AudioObjectPropertyAddress,
                            queue: DispatchQueue,
                            listener: CoreAudioPropertyListenerRegistration) -> OSStatus {
        trace.record("devices.add")
        return lock.withLock {
            guard deviceListener == nil,
                  address.mSelector == kAudioHardwarePropertyDevices else {
                return kAudio_ParamError
            }
            deviceListener = .init(address: address, queue: queue, registration: listener)
            return noErr
        }
    }
    func removeDevicesListener(address: inout AudioObjectPropertyAddress,
                               queue: DispatchQueue,
                               listener: CoreAudioPropertyListenerRegistration) -> OSStatus {
        trace.record("devices.remove")
        return lock.withLock {
            guard let exact = deviceListener, exact.registration === listener,
                  exact.queue === queue, sameAddress(exact.address, address) else {
                return kAudio_ParamError
            }
            deviceListener = nil
            return noErr
        }
    }
    func resolveBlackHole2ChannelEndpointPair() throws -> BlackHoleDeviceEndpointPair {
        trace.record("devices.read")
        return .init(defaultInputEndpoint: .init(deviceID: 2,
                    deviceUID: uidByID[2]!),
                    hiddenMirrorSinkEndpoint: .init(deviceID: 3,
                    deviceUID: uidByID[3]!))
    }
    func addDefaultInputListener(address: inout AudioObjectPropertyAddress,
                                queue: DispatchQueue,
                                listener: CoreAudioPropertyListenerRegistration) -> OSStatus {
        trace.record("input.add")
        return lock.withLock {
            guard inputListener == nil,
                  address.mSelector == kAudioHardwarePropertyDefaultInputDevice else {
                return kAudio_ParamError
            }
            inputListener = .init(address: address, queue: queue, registration: listener)
            return noErr
        }
    }
    func removeDefaultInputListener(address: inout AudioObjectPropertyAddress,
                                   queue: DispatchQueue,
                                   listener: CoreAudioPropertyListenerRegistration) -> OSStatus {
        trace.record("input.remove")
        return lock.withLock {
            guard let exact = inputListener, exact.registration === listener,
                  exact.queue === queue, sameAddress(exact.address, address) else {
                return kAudio_ParamError
            }
            inputListener = nil
            return noErr
        }
    }
    func currentDefaultInputUID() throws -> String {
        trace.record("input.readUID")
        return inputUID
    }
    func currentDefaultInputDeviceID() throws -> AudioDeviceID {
        trace.record("input.readID")
        return lock.withLock { inputID }
    }
    func resolveDeviceID(uid: String) throws -> AudioDeviceID {
        trace.record("input.resolve")
        guard let entry = uidByID.first(where: { $0.value == uid }) else {
            throw CaptureError.audioDeviceNotFound("inert fixture UID")
        }
        return entry.key
    }
    func compareAndSetDefaultInputDevice(_ deviceID: AudioDeviceID,
                                         expectedCurrentUID: String)
        -> BlackHoleDefaultInputMutationResult {
        let result: (BlackHoleDefaultInputMutationResult, Listener?) = lock.withLock {
            guard uidByID[inputID] == expectedCurrentUID else {
                return (.currentInputMismatch, nil)
            }
            guard uidByID[deviceID] != nil else { return (.readFailed, nil) }
            inputID = deviceID
            writtenInputIDs.append(deviceID)
            return (.written(noErr), inputListener)
        }
        if result.0 == .written(noErr) {
            trace.record("input.write.\(deviceID)")
            if let listener = result.1 {
                // Same exact owned-listener mechanism used by existing lease tests.
                listener.queue.sync {
                    var address = listener.address
                    withUnsafePointer(to: &address) {
                        listener.registration.block(1, $0)
                    }
                }
            }
        }
        return result.0
    }
    func addDefaultOutputListener(kind: BlackHoleDefaultOutputKind,
                                  queue: DispatchQueue,
                                  listener: CoreAudioPropertyListenerRegistration) -> OSStatus {
        trace.record("output.add")
        return lock.withLock {
            guard outputListeners[kind] == nil else { return kAudio_ParamError }
            outputListeners[kind] = .init(queue: queue, registration: listener)
            return noErr
        }
    }
    func removeDefaultOutputListener(kind: BlackHoleDefaultOutputKind,
                                     queue: DispatchQueue,
                                     listener: CoreAudioPropertyListenerRegistration) -> OSStatus {
        trace.record("output.remove")
        return lock.withLock {
            guard let exact = outputListeners[kind], exact.queue === queue,
                  exact.registration === listener else { return kAudio_ParamError }
            outputListeners[kind] = nil
            return noErr
        }
    }
    func currentDefaultOutputRoute(_ kind: BlackHoleDefaultOutputKind) throws
        -> WorldwideSafeOutputRouteObservation {
        trace.record("output.read")
        return .init(uid: "BuiltInSpeakerDevice", usableDeviceID: 4)
    }
    func resolveUsableOutputDeviceID(uid: String) throws -> AudioDeviceID {
        trace.record("output.resolve")
        guard uid == "BuiltInSpeakerDevice" else {
            throw WorldwideSafeOutputInvariantError.safeOutputUnavailable
        }
        return 4
    }
    func compareAndSetDefaultOutputDevice(_ deviceID: AudioDeviceID,
                                          kind: BlackHoleDefaultOutputKind,
                                          expectedCurrentUID: String)
        -> BlackHoleDefaultOutputMutationResult {
        // This fixture starts with both outputs safe; any requested output write
        // is a real caller regression, not an operation to silently permit.
        trace.record("output.write.UNEXPECTED")
        return .readFailed
    }
    private func sameAddress(_ a: AudioObjectPropertyAddress,
                             _ b: AudioObjectPropertyAddress) -> Bool {
        a.mSelector == b.mSelector && a.mScope == b.mScope && a.mElement == b.mElement
    }
}

final class BatchARejectUnexpectedCleanupScheduler:
    BlackHoleDeferredCleanupRetryScheduling, @unchecked Sendable {
    let trace: BatchAInertTrace
    init(trace: BatchAInertTrace) { self.trace = trace }
    func schedule(after _: TimeInterval, work _: @escaping @Sendable () -> Void) {
        // No retry should exist with exact successful fake removals. Never run it
        // later or enlist shared cleanup; test asserts this event stays absent.
        trace.record("cleanup.schedule.UNEXPECTED")
    }
}

final class BatchAInertMediaController: MacRemoteMediaControlling, @unchecked Sendable {
    let trace: BatchAInertTrace
    init(trace: BatchAInertTrace) { self.trace = trace }
    var isAvailable: Bool { false }
    func start(onStateChanged _: @escaping @Sendable (WebRTCRemoteMediaStateUpdate) -> Void) {
        trace.record("media.start.UNEXPECTED")
    }
    func stop() { trace.record("media.stop") }
    func invalidateCommands() { trace.record("media.invalidate") }
    func prepareCommand(_ command: WebRTCRemoteMediaCommand, contextID: String,
                        positionSeconds: TimeInterval?,
                        isAuthorized: @escaping @Sendable () -> Bool)
        -> MacPreparedRemoteMediaCommand? { nil }
    func perform(_ prepared: MacPreparedRemoteMediaCommand) async
        -> WebRTCRemoteMediaCommandResult { .unsupported }
    func refresh() { trace.record("media.refresh.UNEXPECTED") }
}

final class BatchACopiedFaults: @unchecked Sendable {
    private let lock = NSLock()
    var initialCorruption = false // Set during single-threaded test setup only.
    private var retryOpcode: UInt32?
    private var observationCorruption = false
    private var evidenceCorruption = false
    let trace: BatchAInertTrace
    let gate: BlackHoleMicrophoneOutputAuthorizationGate
    init(trace: BatchAInertTrace, gate: BlackHoleMicrophoneOutputAuthorizationGate) {
        self.trace = trace; self.gate = gate
    }
    func armRetry(_ opcode: UInt32?) { lock.withLock { retryOpcode = opcode } }
    func armObservation(_ armed: Bool) { lock.withLock { observationCorruption = armed } }
    func armEvidence(_ armed: Bool) { lock.withLock { evidenceCorruption = armed } }
    var retryProducer: BelugaRustSafeOutputRetryProducer {
        .init(initial: { [self] input in
            var output = beluga_core_safe_output_retry_initialize(input)
            trace.record("C.retry.initial")
            if initialCorruption { output.status = 0 }
            return output
        }, transition: { [self] input, opcode in
            var output = beluga_core_safe_output_retry_transition(input, opcode)
            trace.record("C.retry.\(opcode)")
            if lock.withLock({ retryOpcode == opcode }) {
                if opcode == 3 && gate.isOpen { trace.record("reset.sawCommittedGateOpen") }
                output.status = 0
            }
            return output
        })
    }
    var hostedProducer: BelugaRustMacHostedCallProducer {
        .init(observation: { [self] input in
            var output = beluga_core_hosted_call_observation(input)
            trace.record("C.hosted.observation")
            if lock.withLock({ observationCorruption }) { output.status = 0 }
            return output
        }, evidence: { [self] input in
            var output = beluga_core_hosted_call_evidence(input)
            trace.record("C.hosted.evidence")
            if lock.withLock({ evidenceCorruption }) { output.status = 0 }
            return output
        }, peerGeneration: { [self] input in
            trace.record("C.hosted.peer")
            return beluga_core_hosted_call_peer_generation(input)
        })
    }
}

struct BatchAActualServiceFixture {
    let trace: BatchAInertTrace
    let hal: BatchAInertHAL
    let gate: BlackHoleMicrophoneOutputAuthorizationGate
    let faults: BatchACopiedFaults
    let service: WorldwideScreenService
    let listenerCleanup: BlackHoleDeviceAvailabilityListenerCleanupRetainer
    let inputCleanup: BlackHoleDefaultInputLeaseDeferredCleanupRetainer
    let serviceCleanup: WorldwideBlackHoleAudioRoutingCleanupRetainer

    init(profile: WorldwideScreenServiceFeatureProfile = .fullPrimary,
         initiallyFaulted: Bool = false) throws {
        let trace = BatchAInertTrace()
        let hal = BatchAInertHAL(trace: trace)
        let gate = try XCTUnwrap(BlackHoleMicrophoneOutputAuthorizationGate())
        let faults = BatchACopiedFaults(trace: trace, gate: gate)
        faults.initialCorruption = initiallyFaulted
        let scheduler = BatchARejectUnexpectedCleanupScheduler(trace: trace)
        let listenerCleanup = BlackHoleDeviceAvailabilityListenerCleanupRetainer(
            retryScheduler: scheduler)
        let inputCleanup = BlackHoleDefaultInputLeaseDeferredCleanupRetainer(
            retryScheduler: scheduler)
        let serviceCleanup = WorldwideBlackHoleAudioRoutingCleanupRetainer()
        let monitor = BlackHoleDeviceAvailabilityMonitor(operations: hal,
            callbackQueue: .init(label: "test.batchA.inventory"), makeEpoch: { UUID() },
            scheduleInventoryRetry: { _ in trace.record("inventory.retry.UNEXPECTED") },
            listenerCleanupRetainer: listenerCleanup,
            listenerQueue: .init(label: "test.batchA.inventory.listener"))
        let lease = BlackHoleDefaultInputLease(operations: hal,
            operationQueue: .init(label: "test.batchA.input"),
            listenerQueue: .init(label: "test.batchA.input.listener"), proofTimeout: 0.05,
            deferredCleanupRetainer: inputCleanup)
        let invariant = WorldwideSafeOutputInvariant(operations: hal,
            operationQueue: .init(label: "test.batchA.output"),
            listenerQueue: .init(label: "test.batchA.output.listener"), proofTimeout: 0.05,
            listenerCleanupRetainer: listenerCleanup)
        let dependencies = WorldwideScreenServiceAudioRoutingDependencies(
            monitor: monitor, lease: lease, invariant: invariant, writerGate: gate,
            cleanupRetainer: serviceCleanup,
            deferredInputCleanup: { count in
                trace.record("cleanup.startup")
                return inputCleanup.redriveRetained(maximumAttemptCount: count) == 0
            }, makeDiagnosticsWriter: {
                .init(write: { _ in trace.record("diagnostics.memoryWrite") })
            }, isInertPolicyFixture: true)
        let service = try WorldwideScreenService(
            endpoint: URL(string: "wss://example.invalid")!, forceRelay: false,
            screenDisplayID: nil, systemAudioDisplayID: nil,
            maximumWidth: 1_280, framesPerSecond: 30, maximumVideoBitrate: 8_000_000,
            featureProfile: profile,
            remoteInputController: MacRemoteInputController(allowRemoteControl: false),
            remoteMediaController: BatchAInertMediaController(trace: trace),
            audioRoutingDependencies: dependencies,
            safeOutputRetryPolicy: .init(producer: faults.retryProducer),
            hostedCallPolicyProducer: faults.hostedProducer,
            logger: ConsoleLogger(verbose: false))
        self.trace = trace; self.hal = hal; self.gate = gate; self.faults = faults
        self.service = service; self.listenerCleanup = listenerCleanup
        self.inputCleanup = inputCleanup; self.serviceCleanup = serviceCleanup
    }
}
