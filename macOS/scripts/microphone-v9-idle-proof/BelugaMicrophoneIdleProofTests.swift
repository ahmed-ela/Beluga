import CoreAudio
import Foundation

// This test executable injects offline native-header fixtures at the actual
// production CFProperty boundary. It never calls LiveEndpoints or the CLI's
// CoreAudio callback, and contains no driver/route/host mutation facilities.
private struct TestFailure: Error { let message: String }
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(message: message) }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 1_000
    func next() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
    func peek() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

private struct NativeFixtures: Sendable {
    let v1: String
    let v2: String
    let pristine: String
    func payload(_ family: String, _ mode: String, _ sequence: UInt64, _ ticks: UInt64) throws -> Data {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: family == "v1" ? v1 : (family == "v2" ? v2 : pristine))
        task.arguments = [mode, String(sequence), String(ticks)]
        let output = Pipe()
        task.standardOutput = output
        try task.run()
        // Maximum normal native fixture is 9,664 bytes, well below pipe bounds.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw TestFailure(message: "native fixture failed") }
        return data
    }
}

private func setting(_ source: Data, _ offset: Int, _ value: UInt64, _ width: Int = 8) -> Data {
    var result = source
    for index in 0..<width { result[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
    return result
}

private final class PropertyHarness: @unchecked Sendable {
    private let lock = NSLock()
    let clock: TestClock
    let fixtures: NativeFixtures
    let family: String
    let mode: String
    var v2Status: OSStatus
    var sizeOverride: UInt32?
    var wrongType = false
    var nilValue = false
    var sequenceFrozen = false
    var ticksFrozen = false
    var staleTicks = false
    var mutate: (@Sendable (Data, Int) -> Data)?
    private(set) var calls: [(AudioDeviceID, AudioObjectPropertySelector)] = []
    private var count = 0
    private var failure: String?

    init(_ fixtures: NativeFixtures, _ family: String = "v2", _ mode: String = "idle-overflow") {
        self.fixtures = fixtures
        self.family = family
        self.mode = mode
        clock = TestClock()
        v2Status = family == "v1" ? kAudioHardwareUnknownPropertyError : noErr
    }

    func read(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress,
              _ size: inout UInt32, _ value: inout Unmanaged<CFPropertyList>?) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        calls.append((device, address.mSelector))
        guard address.mScope == kAudioObjectPropertyScopeGlobal,
              address.mElement == kAudioObjectPropertyElementMain,
              size == MemoryLayout<Unmanaged<CFPropertyList>?>.size else {
            failure = "production property address/size changed"
            return kAudioHardwareIllegalOperationError
        }
        if address.mSelector == WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.v2Property && v2Status != noErr {
            return v2Status
        }
        count += 1
        do {
            let tick = staleTicks ? 1 : (ticksFrozen ? 1_003 : clock.peek() + 1)
            var data = try fixtures.payload(family, mode, sequenceFrozen ? 1 : UInt64(count), tick)
            if let mutate { data = mutate(data, count) }
            size = sizeOverride ?? UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size)
            if nilValue { value = nil }
            else if wrongType {
                value = Unmanaged.passRetained(CFStringCreateWithCString(kCFAllocatorDefault, "not data", 0x08000100)!)
            } else {
                value = data.withUnsafeBytes { bytes in
                    Unmanaged.passRetained(CFDataCreate(kCFAllocatorDefault, bytes.bindMemory(to: UInt8.self).baseAddress, data.count)!)
                }
            }
            return noErr
        } catch {
            failure = String(describing: error)
            return kAudioHardwareUnspecifiedError
        }
    }

    func assertBoundary() throws {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw TestFailure(message: failure) }
    }
}

private final class EndpointHarness: @unchecked Sendable {
    private let lock = NSLock()
    var invalid = false
    var changedAt: Int?
    private var count = 0
    func resolve() -> BelugaMicrophoneEndpoints {
        lock.lock(); defer { lock.unlock() }
        count += 1
        if invalid { return .init(visible: 31, writer: 31, visibleStream: 101, writerStream: 107) }
        return .init(visible: changedAt == count ? 32 : 31, writer: 47, visibleStream: 101, writerStream: 107)
    }
}

private func request(_ phase: BelugaMicrophoneIdlePhase = .afterProbe, instance: String = "77") throws -> BelugaMicrophoneIdleRequest {
    try .init(arguments: [phase == .afterReload ? "--observe-initial-idle" : "--verify-idle",
                          "--phase", phase.rawValue, "--schema", String(phase.schema),
                          "--nonce", String(repeating: "a", count: 64), "--expected-instance", instance])
}

private func collect(_ properties: PropertyHarness, _ phase: BelugaMicrophoneIdlePhase = .afterProbe,
                     _ endpoints: EndpointHarness = EndpointHarness(), instance: String = "77", uid: UInt32 = 501,
                     bootstrap: Bool = false, priorBootstrap: Bool = false) throws -> BelugaMicrophoneIdleResult {
    let proof = BelugaMicrophoneIdleProof(
        readProperty: { device, address, size, value in properties.read(device, address, &size, &value) },
        hostTicks: { properties.clock.next() }, resolveEndpoints: { endpoints.resolve() }, betweenReads: {}
    )
    let configured = priorBootstrap ? try BelugaMicrophoneIdleRequest(arguments: ["--bootstrap-prior-instance", "--phase", "after-rollback", "--schema", "1", "--nonce", String(repeating: "a", count: 64)]) :
        bootstrap ? try BelugaMicrophoneIdleRequest(arguments: ["--bootstrap-instance", "--phase", "after-reload", "--schema", "2", "--nonce", String(repeating: "a", count: 64)]) : try request(phase, instance: instance)
    let result = try proof.collect(configured, effectiveUID: uid)
    try properties.assertBoundary()
    return result
}

private func refused(_ properties: PropertyHarness, _ expected: BelugaMicrophoneIdleFailure? = nil,
                     phase: BelugaMicrophoneIdlePhase = .afterProbe,
                     endpoints: EndpointHarness = EndpointHarness(), instance: String = "77", uid: UInt32 = 501) throws {
    do {
        _ = try collect(properties, phase, endpoints, instance: instance, uid: uid)
        throw TestFailure(message: "accepted a forbidden observation")
    } catch let error as BelugaMicrophoneIdleFailure {
        if let expected { try require(error == expected, "wrong refusal: \(error), expected \(expected)") }
    }
    try properties.assertBoundary()
}

@main private struct BelugaMicrophoneIdleTests {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else { throw TestFailure(message: "three native fixture paths required") }
        let fixtures = NativeFixtures(v1: CommandLine.arguments[1], v2: CommandLine.arguments[2], pristine: CommandLine.arguments[3])
        let tests: [(String, () throws -> Void)] = [
            ("v1 actual absent-v2 fallback and four mirrored complete reads", {
                let harness = PropertyHarness(fixtures, "v1", "idle")
                let result = try collect(harness, .beforePublish)
                try require(result.exitCode == 0 && result.schema == 1 && result.observations.count == 4, "v1 proof incomplete")
                try require(harness.calls.map(\.0) == [31, 31, 47, 47, 31, 31, 47, 47], "fallback endpoint ordering changed")
                try require(harness.calls.map(\.1) == [0x6f734432, 0x6f734453, 0x6f734432, 0x6f734453,
                                                       0x6f734432, 0x6f734453, 0x6f734432, 0x6f734453], "fallback selector ordering changed")
            }),
            ("prior rollback bootstrap requires genuine unknown-v2 full-v1 and stays non-green", {
                let harness = PropertyHarness(fixtures, "v1", "idle")
                let result = try collect(harness, .afterRollback, priorBootstrap: true)
                try require(result.kind == "PRIOR_INSTANCE_REQUIRES_FRESH_MIRRORED_IDLE" && result.exitCode == 75 &&
                            !result.idleAcceptance && !result.requiresPublicProbe && result.requiresFreshMirroredIdle &&
                            result.observations.count == 1 && result.expectedInstance == 77 && result.schema == 1 &&
                            result.phase == .afterRollback && !result.initialPristine, "prior bootstrap became green or lost identity")
                try require(harness.calls.map(\.1) == [0x6f734432, 0x6f734453] && harness.calls.map(\.0) == [31, 31],
                            "prior bootstrap did not use the unchanged normal ABI fallback")
                let fresh = try collect(PropertyHarness(fixtures, "v1", "idle"), .afterRollback)
                try require(fresh.kind == "NORMAL_IDLE" && fresh.exitCode == 0 && fresh.observations.count == 4 &&
                            fresh.expectedInstance == result.expectedInstance, "fresh mirrored rollback idle not proven")
                let initialized = PropertyHarness(fixtures, "v1", "idle")
                initialized.mutate = { source, _ in
                    var data = setting(source, 40, 1)
                    for offset in [48, 88, 96, 248, 264, 272, 280] { data = setting(data, offset, 0) }
                    return data
                }
                let initializedProof = try collect(initialized, .afterRollback)
                try require(initializedProof.observations.allSatisfy { $0.epoch.lastIssuedSeed == 0 && $0.epoch.lastIssuedSessionID == 0 } &&
                            initializedProof.exitCode == 0, "rollback invented positive post-probe history after initialization")
            }),
            ("prior rollback bootstrap rejects v2 nonunknown errors malformed stale active and wrong phase", {
                for variant in 0..<6 {
                    let harness = variant == 0 ? PropertyHarness(fixtures) : PropertyHarness(fixtures, "v1", variant == 5 ? "active" : "idle")
                    if variant == 1 { harness.v2Status = kAudioHardwareIllegalOperationError }
                    if variant == 2 { harness.sizeOverride = 3 }
                    if variant == 3 { harness.staleTicks = true }
                    if variant == 4 { harness.mutate = { data, _ in setting(data, 144, 1) } }
                    do { _ = try collect(harness, .afterRollback, priorBootstrap: true); throw TestFailure(message: "invalid prior bootstrap accepted") }
                    catch is BelugaMicrophoneIdleFailure {}
                    try harness.assertBoundary()
                    if variant == 1 { try require(harness.calls.count == 1, "nonunknown error allowed legacy fallback") }
                }
                for phase in ["before-publish", "after-reload", "after-probe"] {
                    do {
                        _ = try BelugaMicrophoneIdleRequest(arguments: ["--bootstrap-prior-instance", "--phase", phase,
                            "--schema", phase == "before-publish" ? "1" : "2", "--nonce", String(repeating: "a", count: 64)])
                        throw TestFailure(message: "prior bootstrap accepted wrong phase")
                    } catch is BelugaMicrophoneIdleFailure {}
                }
            }),
            ("normal v2 overflow inventory is complete and stable", {
                let harness = PropertyHarness(fixtures)
                let result = try collect(harness)
                try require(result.exitCode == 0 && result.idleAcceptance && !result.requiresPublicProbe, "normal idle not accepted")
                try require(result.observations.map(\.deviceID) == [31, 47, 31, 47], "mirror ordering changed")
                try require(result.observations.allSatisfy { $0.registeredCount == 70 && $0.byteCount == 9664 && $0.payloadSHA256.count == 64 }, "overflow inventory lost")
                try require(harness.calls.count == 4 && harness.calls.allSatisfy { $0.1 == 0x6f734432 }, "v2 attempted legacy fallback")
                let encoded = try JSONEncoder().encode(result)
                let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
                try require(object["nonce"] as? String == String(repeating: "a", count: 64), "nonce missing")
            }),
            ("full 64 registered v1 bank needs no invented 62-client headroom", {
                let harness = PropertyHarness(fixtures, "v1", "idle")
                harness.mutate = { source, _ in
                    var data = source
                    data = setting(data, 144, 64); data = setting(data, 160, 32); data = setting(data, 168, 32)
                    data = setting(data, 192, UInt64.max)
                    for index in 0..<64 {
                        let base = 1312 + index * 80
                        data = setting(data, base, UInt64(index + 1)); data = setting(data, base + 8, 1)
                        data = setting(data, base + 48, 1, 4)
                        data = setting(data, base + 52, index % 2 == 0 ? 2 : 6, 4)
                        data = setting(data, base + 56, UInt64(index + 1000), 4)
                        data = setting(data, base + 64, index % 2 == 0 ? 1 : 2, 4)
                        data = setting(data, base + 68, UInt64(UInt32.max), 4)
                    }
                    return data
                }
                let result = try collect(harness, .beforePublish)
                try require(result.observations.allSatisfy { $0.registeredCount == 64 }, "full bank refused")
            }),
            ("initialized pristine is distinct non-success, not post-probe proof", {
                let initial = try collect(PropertyHarness(fixtures, "pristine", "pristine"), .afterReload)
                try require(initial.exitCode == 75 && !initial.idleAcceptance && initial.requiresPublicProbe && initial.initialPristine, "pristine became green")
                try require(initial.kind == "INITIAL_COMPLETE_IDLE_REQUIRES_PUBLIC_PROBE", "initial result kind changed")
                try refused(PropertyHarness(fixtures, "pristine", "pristine"), .probeHistoryMissing)
            }),
            ("initial registered idle is safe non-success, not empty-only", {
                let initial = try collect(PropertyHarness(fixtures), .afterReload)
                try require(initial.exitCode == 75 && !initial.idleAcceptance && initial.requiresPublicProbe && !initial.initialPristine, "registered initial idle mishandled")
                for mode in ["history", "revision", "retired-core", "io-history"] {
                    let result = try collect(PropertyHarness(fixtures, "pristine", mode), .afterReload)
                    try require(!result.initialPristine && result.exitCode == 75, "non-pristine subtype admitted as pristine")
                }
            }),
            ("production decoder is not bypassed for initial state", {
                try refused(PropertyHarness(fixtures, "pristine", "life-zero"), phase: .afterReload)
                try refused(PropertyHarness(fixtures, "pristine", "reserved"), phase: .afterReload)
            }),
            ("only genuine UnknownProperty permits v1 fallback", {
                for status in [kAudioHardwareUnspecifiedError, kAudioHardwareBadObjectError, kAudioHardwareIllegalOperationError] {
                    let harness = PropertyHarness(fixtures, "v1", "idle")
                    harness.v2Status = status
                    try refused(harness, .propertyRead(0, .property(status)), phase: .beforePublish)
                    try require(harness.calls.count == 1, "failed v2 fell back")
                }
            }),
            ("wrong CF boundary refuses without fallback", {
                for variant in 0..<4 {
                    let harness = PropertyHarness(fixtures)
                    if variant == 0 { harness.sizeOverride = 0 }
                    if variant == 1 { harness.wrongType = true }
                    if variant == 2 { harness.nilValue = true }
                    if variant == 3 { harness.mutate = { source, _ in Data(source.dropLast()) } }
                    try refused(harness)
                    try require(harness.calls.count == 1, "malformed v2 fell back")
                }
            }),
            ("stale ticks and frozen observation sequence refuse", {
                let stale = PropertyHarness(fixtures); stale.staleTicks = true
                try refused(stale, .propertyRead(0, .staleObservation))
                let frozen = PropertyHarness(fixtures); frozen.sequenceFrozen = true
                try refused(frozen, .unstableOrActive)
                let frozenTicks = PropertyHarness(fixtures); frozenTicks.ticksFrozen = true
                try refused(frozenTicks)
            }),
            ("active overflow and lease/work-loop retention refuse", {
                try refused(PropertyHarness(fixtures, "v2", "active-overflow"), .unstableOrActive)
                for offset in [104, 112, 120, 1392 + 63 * 32, 1208, 1280] {
                    let harness = PropertyHarness(fixtures)
                    harness.mutate = { source, _ in setting(source, offset, 1) }
                    try refused(harness)
                }
            }),
            ("complete last-record malformed/duplicate/partial inventory refuses", {
                let last = 3504 + 69 * 88
                for (offset, value, width) in [(16, UInt64(69), 8), (16, UInt64.max, 8),
                                              (last, 68, 8), (last + 8, 1, 8),
                                              (last + 64, 1001, 4), (last + 84, 1, 4), (3440, 1, 8)] {
                    let harness = PropertyHarness(fixtures)
                    harness.mutate = { source, _ in setting(source, offset, value, width) }
                    try refused(harness)
                    try require(harness.calls.count == 1, "malformed tail fell back")
                }
            }),
            ("registration and retired-core identity churn refuses", {
                for offset in [32, 3504 + 69 * 88 + 68, 1400 + 63 * 32] {
                    let harness = PropertyHarness(fixtures)
                    harness.mutate = { source, index in index == 3 ? setting(source, offset, 99, offset == 3504 + 69 * 88 + 68 ? 4 : 8) : source }
                    try refused(harness, .unstableOrActive)
                }
            }),
            ("schema pin instance pin and UID501 admission refuse before proof", {
                try refused(PropertyHarness(fixtures), .schemaMismatch, phase: .beforePublish)
                try refused(PropertyHarness(fixtures, "v1", "idle"), .schemaMismatch)
                try refused(PropertyHarness(fixtures), .instanceMismatch, instance: "78")
                let wrongUID = PropertyHarness(fixtures)
                try refused(wrongUID, .callerIdentity, uid: 0)
                try require(wrongUID.calls.isEmpty, "root caller opened diagnostics")
            }),
            ("exact endpoints distinct and remap fenced before after and final", {
                let invalid = EndpointHarness(); invalid.invalid = true
                try refused(PropertyHarness(fixtures), .endpointIdentity, endpoints: invalid)
                for boundary in [2, 3, 6, 9, 10] {
                    let endpoints = EndpointHarness(); endpoints.changedAt = boundary
                    try refused(PropertyHarness(fixtures), .endpointsChanged, endpoints: endpoints)
                }
            }),
            ("truthful failure evidence survives complete normal idle proof", {
                let result = try collect(PropertyHarness(fixtures, "v2", "failure-evidence"))
                try require(result.idleAcceptance && result.observations.allSatisfy { $0.registeredCount == 70 }, "failure history erased/refused")
            }),
            ("post-probe requires positive issued identities and successful balanced lifecycle", {
                for offset in [80, 88, 128, 136, 272, 288, 296, 304] {
                    let harness = PropertyHarness(fixtures)
                    harness.mutate = { source, _ in setting(source, offset, offset == 80 ? 1 : 0) }
                    try refused(harness)
                }
            }),
            ("CLI request has no fixture skip path and exact phase schema nonce", {
                let valid = ["--verify-idle", "--phase", "after-probe", "--schema", "2", "--nonce", String(repeating: "a", count: 64), "--expected-instance", "77"]
                _ = try BelugaMicrophoneIdleRequest(arguments: valid)
                var variants = [valid + ["--skip"], Array(valid.dropLast()), ["--fixture", "/tmp/data"]]
                for (index, text) in [(0, "--classify-pristine"), (2, "before-publish"), (4, "02"),
                                      (6, String(repeating: "A", count: 64)), (6, "abc"), (8, "0"), (8, "077")] {
                    var changed = valid; changed[index] = text; variants.append(changed)
                }
                for arguments in variants {
                    do {
                        _ = try BelugaMicrophoneIdleRequest(arguments: arguments)
                        throw TestFailure(message: "accepted alternate CLI")
                    } catch BelugaMicrophoneIdleFailure.arguments { }
                }
            }),
            ("bootstrap instance comes from one actual complete fresh v2 read and is never green", {
                let harness = PropertyHarness(fixtures)
                let result = try collect(harness, .afterReload, bootstrap: true)
                try require(result.kind == "BOOTSTRAP_INSTANCE_REQUIRES_FRESH_IDLE_AND_PUBLIC_PROBE" && result.exitCode == 75,
                            "bootstrap became idle acceptance")
                try require(result.expectedInstance == 77 && result.observations.count == 1 && result.requiresFreshMirroredIdle &&
                            result.requiresPublicProbe && !result.idleAcceptance && harness.calls.count == 1, "bootstrap boundary incomplete")
                let changed = PropertyHarness(fixtures)
                changed.mutate = { source, _ in setting(source, 64, 78) }
                try refused(changed, .instanceMismatch, phase: .afterReload, instance: String(result.expectedInstance))
            }),
            ("bootstrap malformed stale active or absent v2 cannot create an instance receipt", {
                for kind in 0..<5 {
                    let harness = PropertyHarness(fixtures, kind == 4 ? "v1" : "v2", kind == 4 ? "idle" : (kind == 3 ? "active-overflow" : "idle-overflow"))
                    if kind == 0 { harness.mutate = { source, _ in setting(source, 16, UInt64.max) } }
                    if kind == 1 { harness.staleTicks = true }
                    if kind == 2 { harness.mutate = { source, _ in setting(source, 64, 0) } }
                    do {
                        _ = try collect(harness, .afterReload, bootstrap: true)
                        throw TestFailure(message: "bootstrap accepted invalid v2")
                    } catch is BelugaMicrophoneIdleFailure { }
                    try require(harness.calls.count == 1 && harness.calls[0].1 == 0x6f734432, "bootstrap tried more than one actual property read")
                }
            }),
            ("native endpoint format fields and stream-config ABI are exact", {
                let format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
                    mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
                try require(BelugaMicrophoneNativeFormat(format).isCanonical, "canonical native ASBD refused")
                for field in 0..<9 {
                    var changed = format
                    switch field {
                    case 0: changed.mSampleRate = 44100
                    case 1: changed.mFormatID = 0
                    case 2: changed.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
                    case 3: changed.mBytesPerPacket = 8
                    case 4: changed.mFramesPerPacket = 2
                    case 5: changed.mBytesPerFrame = 8
                    case 6: changed.mChannelsPerFrame = 2
                    case 7: changed.mBitsPerChannel = 16
                    default: changed.mReserved = 1
                    }
                    try require(!BelugaMicrophoneNativeFormat(changed).isCanonical, "native format mutant accepted")
                }
                let header = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!
                var empty = Data(count: header)
                let emptyCount = try BelugaMicrophoneEndpointContract.decodeChannels(empty)
                try require(emptyCount == 0, "empty inactive scope refused")
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
                let mono = withUnsafeBytes(of: &list) { Data($0) }
                let monoCount = try BelugaMicrophoneEndpointContract.decodeChannels(mono)
                try require(monoCount == 1, "native mono config refused")
                empty[0] = 2
                for malformed in [empty, Data(mono.dropLast()), mono + Data([0]), setting(mono, header + 4, 1, 4)] {
                    do { _ = try BelugaMicrophoneEndpointContract.decodeChannels(malformed); throw TestFailure(message: "bad native config accepted") }
                    catch BelugaMicrophoneIdleFailure.endpointIdentity { }
                }
            }),
            ("endpoint model liveness visibility role sample clock and native formats fail closed", {
                let asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
                    mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
                let format = BelugaMicrophoneNativeFormat(asbd)
                var changed = asbd; changed.mChannelsPerFrame = 2
                let badFormat = BelugaMicrophoneNativeFormat(changed)
                for visible in [true, false] {
                    for mutation in -1..<10 {
                        let state = BelugaMicrophoneEndpointState(
                            model: mutation == 0 ? "wrong" : "com.elamin.opensteamer.virtual-microphone.model",
                            alive: mutation == 1 ? 0 : 1, hidden: mutation == 2 ? (visible ? 1 : 0) : (visible ? 0 : 1),
                            inputChannels: mutation == 3 ? 2 : (visible ? 1 : 0),
                            outputChannels: mutation == 4 ? 2 : (visible ? 0 : 1),
                            inputStreams: mutation == 5 ? [101, 102] : (visible ? [101] : []),
                            outputStreams: mutation == 6 ? [107, 108] : (visible ? [] : [107]),
                            nominalRate: mutation == 7 ? 44100 : 48000, clockDomain: mutation == 8 ? 0 : 0x6f73564d,
                            virtualFormat: mutation == 9 ? badFormat : format, physicalFormat: format)
                        try require(state.satisfies(visible: visible) == (mutation == -1), "endpoint mutant admitted")
                    }
                }
            }),
        ]
        var passed = 0
        for (name, test) in tests {
            do { try test(); passed += 1; print("PASS \(name)") }
            catch { FileHandle.standardError.write(Data("FAIL \(name): \(error)\n".utf8)); exit(1) }
        }
        print("PASS \(passed)/\(tests.count) native offline tests; no live CoreAudio query performed")
    }
}
