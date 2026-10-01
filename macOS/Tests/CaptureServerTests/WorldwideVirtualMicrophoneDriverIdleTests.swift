import CoreAudio
import Foundation
import XCTest
@testable import CaptureServer

@MainActor
final class WorldwideVirtualMicrophoneDriverIdleTests: XCTestCase {
    func testNativeHeaderFixtureDistinguishesIdleFromRetainedClientLease() throws {
        let idle = try snapshot()
        let active = try snapshot("active")
        XCTAssertTrue(idle.isIdle)
        XCTAssertFalse(active.isIdle)
        XCTAssertEqual(active.epoch.timelineSeed, 7)
        XCTAssertEqual(active.epoch.lastIssuedSessionID, 11)
    }

    func testDecoderRejectsNativeHeaderMutations() throws {
        for mode in ["schema", "struct-size", "missing-invariant", "unknown-flag",
                     "retained-seed", "retained-slot", "count-mismatch", "count-overflow",
                     "unbalanced-stop", "work-loop-active"] {
            let data = try VirtualMicrophoneDiagnosticFixture.data(mode)
            if case .success = WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decode(data) {
                XCTFail("Accepted invalid diagnostic fixture: \(mode)")
            }
        }
        let data = try VirtualMicrophoneDiagnosticFixture.data()
        for malformed in [Data(), Data(data.dropLast()), data + Data([0])] {
            XCTAssertEqual(
                WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decode(malformed),
                .failure(.snapshotSize(malformed.count))
            )
        }
    }

    func testMirroredReadsRequireOneIdleEpochWithFreshObservations() throws {
        let idle = try (1...4).map { try snapshot(sequence: UInt64($0)) }
        XCTAssertTrue(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(idle))
        for mode in ["active", "new-instance", "new-lifecycle", "new-session", "new-seed"] {
            var replaced = idle
            replaced[2] = try snapshot(mode, sequence: 3)
            XCTAssertFalse(
                WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(replaced),
                "Accepted changed or active epoch: \(mode)"
            )
        }
        XCTAssertFalse(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(Array(idle.prefix(3))))
        XCTAssertFalse(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(Array(repeating: idle[0], count: 4)))
        XCTAssertFalse(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(Array(idle.reversed())))
    }

    func testProductionCFPropertyBoundaryValidatesAddressTypeAndFreshness() throws {
        let data = try VirtualMicrophoneDiagnosticFixture.data(capturedHostTicks: 1_000)
        let properties = LockedDiagnosticProperty(data: data)
        let reader = WorldwideVirtualMicrophoneDriverDiagnosticReader(
            readProperty: { deviceID, address, size, value in
                properties.read(deviceID, address, &size, &value)
            },
            hostTicks: { 1_000 }
        )
        XCTAssertTrue(try reader.read(31).get().isIdle)
        XCTAssertEqual(properties.lastDeviceID, 31)
        XCTAssertEqual(properties.lastSelector, 0x6F73_4453)
        XCTAssertEqual(properties.lastScope, kAudioObjectPropertyScopeGlobal)
        XCTAssertEqual(properties.lastElement, kAudioObjectPropertyElementMain)
        XCTAssertEqual(properties.requestedSize, UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size))
        let stale = WorldwideVirtualMicrophoneDriverDiagnosticReader(
            readProperty: { deviceID, address, size, value in
                properties.read(deviceID, address, &size, &value)
            },
            hostTicks: { 2_000 }
        )
        XCTAssertEqual(stale.read(31), .failure(.staleObservation))
    }

    func testProductionCFPropertyBoundaryFailsClosedOnReadErrorsAndWrongTypes() throws {
        let data = try VirtualMicrophoneDiagnosticFixture.data()
        let cases: [(OSStatus, UInt32, Bool, WorldwideVirtualMicrophoneDriverDiagnosticError)] = [
            (kAudioHardwareUnknownPropertyError, 8, false, .property(kAudioHardwareUnknownPropertyError)),
            (noErr, 0, false, .propertySize(0)),
            (noErr, 8, true, .propertyType),
        ]
        for (status, size, wrongType, expected) in cases {
            let properties = LockedDiagnosticProperty(data: data, status: status, size: size, wrongType: wrongType)
            let reader = WorldwideVirtualMicrophoneDriverDiagnosticReader(
                readProperty: { deviceID, address, size, value in
                    properties.read(deviceID, address, &size, &value)
                }
            )
            XCTAssertEqual(reader.read(31), .failure(expected))
        }
    }

    func testCompleteV2IdleOverflowInventoryProvesMirroredIdle() throws {
        let observations = try (1...4).map { sequence in
            try v2Snapshot(sequence: UInt64(sequence))
        }
        XCTAssertTrue(observations.allSatisfy { $0.isIdle && $0.schemaVersion == 2 })
        XCTAssertTrue(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(observations))
        XCTAssertEqual(try VirtualMicrophoneDiagnosticFixture.dataV2().count, 3_504 + 70 * 88)
    }

    func testActiveV2OverflowLeaseCannotProveIdle() throws {
        let observations = try (1...4).map { try v2Snapshot("active-overflow", sequence: UInt64($0)) }
        XCTAssertTrue(observations.allSatisfy { !$0.isIdle })
        XCTAssertEqual(observations[0].epoch.timelineSeed, 7)
        XCTAssertFalse(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(observations))
    }

    func testV2DecoderRejectsMalformedDuplicateStaleAndIncompleteInventories() throws {
        let idle = try VirtualMicrophoneDiagnosticFixture.dataV2()
        let last = 3_504 + 69 * 88
        let mutations: [(Int, UInt64, Int)] = [
            (0, 1, 4), (4, 3_496, 4), (8, UInt64.max, 8), (16, UInt64.max, 8),
            (16, 69, 8), (24, 80, 8), (40, 65, 4), (44, 1, 4), (3_440, 1, 8),
            (72, 0x3_FF01, 8), (72, 0x7_DF01, 8), (72, UInt64(1) << 63, 8),
            (80, 0, 8), (88, 9, 8), (96, 0, 8), (104, 7, 8), (112, 7, 8),
            (144, 1, 8), (184, 69, 8), (200, 34, 8), (1_392, 11, 8),
            (last, 68, 8), (last, UInt64.max, 8), (last + 8, 0, 8), (last + 8, 1, 8),
            (last + 16, 0, 8), (last + 32, 0, 8), (last + 56, 7, 4),
            (last + 60, 2, 4), (last + 64, 1_001, 4), (last + 72, 1, 4),
            (last + 40, 11, 8), (last + 76, 0, 4), (last + 80, 1, 4),
            (last + 84, 1, 4), (1_328, 1, 8), (624, 32, 4),
            (1_208, 1, 8), (1_216, 1, 8),
        ]
        for (offset, value, width) in mutations {
            assertV2Rejected(setting(idle, offset: offset, value: value, width: width), "offset \(offset)")
        }
        for malformed in [Data(), Data(idle.prefix(3_503)), Data(idle.dropLast()),
                          idle + Data([0]), Data(count: 1_048_577)] {
            assertV2Rejected(malformed, "size \(malformed.count)")
        }
        let active = try VirtualMicrophoneDiagnosticFixture.dataV2("active-overflow")
        for (offset, value, width) in [(last + 40, UInt64(10), 8), (last + 48, 6, 8),
                                     (last + 76, 64, 4), (1_408, 6, 8), (112, 8, 8)] {
            assertV2Rejected(setting(active, offset: offset, value: value, width: width), "active offset \(offset)")
        }
    }

    func testV2MirroredProofRejectsRegistryChurnAndMixedFormats() throws {
        let idle = try (1...4).map { try v2Snapshot(sequence: UInt64($0)) }
        for mode in ["new-registry-revision", "new-registry-identity"] {
            var changed = idle
            changed[2] = try v2Snapshot(mode, sequence: 3)
            XCTAssertEqual(changed[2].epoch, idle[2].epoch)
            XCTAssertFalse(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(changed), mode)
        }
        var changed = idle
        // Match the legacy epoch exactly: mixed format alone must reject proof.
        let legacy = setting(try VirtualMicrophoneDiagnosticFixture.data(sequence: 3, capturedHostTicks: 103),
                             offset: 40, value: idle[0].epoch.driverLifecycle)
        changed[2] = try WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decode(legacy).get()
        XCTAssertEqual(changed[2].epoch, idle[2].epoch)
        XCTAssertFalse(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(changed))
        let base = try VirtualMicrophoneDiagnosticFixture.dataV2(sequence: 3, capturedHostTicks: 103)
        changed[2] = try WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decodeV2(
            setting(base, offset: 1_400, value: 123)
        ).get() // A retired core record is part of complete identity too.
        XCTAssertFalse(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(changed))
        var evolvingRecords = idle
        for index in 0..<4 {
            var data = try VirtualMicrophoneDiagnosticFixture.dataV2(sequence: UInt64(index + 1), capturedHostTicks: UInt64(index + 101))
            data = setting(data, offset: 520, value: UInt64(index)) // Historical zero-timestamp failure evidence.
            data = setting(data, offset: 1_032, value: UInt64(index)) // Historical writer I/O epoch failures.
            evolvingRecords[index] = try WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decodeV2(data).get()
        }
        XCTAssertTrue(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(evolvingRecords))
    }

    func testReaderFallsBackToFrozenV1OnlyWhenV2PropertyIsAbsent() throws {
        let data = try VirtualMicrophoneDiagnosticFixture.data(capturedHostTicks: 1_000)
        let properties = LockedDiagnosticProperty(data: data)
        let reader = diagnosticReader(properties)
        XCTAssertTrue(try reader.read(31).get().isIdle)
        XCTAssertEqual(try reader.read(31).get().schemaVersion, 1)
        XCTAssertEqual(properties.selectors, [0x6F73_4432, 0x6F73_4453, 0x6F73_4432, 0x6F73_4453])
        let invalid = LockedDiagnosticProperty(data: try VirtualMicrophoneDiagnosticFixture.data("count-overflow"))
        XCTAssertEqual(diagnosticReader(invalid).read(31), .failure(.incoherentSnapshot))
        var hiddenLease = data
        hiddenLease = setting(hiddenLease, offset: 1_344, value: 10)
        XCTAssertEqual(diagnosticReader(LockedDiagnosticProperty(data: hiddenLease)).read(31), .failure(.incoherentSnapshot))
    }

    func testReaderRejectsUnavailableOrMalformedV2WithoutV1Fallback() throws {
        let legacy = try VirtualMicrophoneDiagnosticFixture.data(capturedHostTicks: 1_000)
        let v2 = try VirtualMicrophoneDiagnosticFixture.dataV2()
        let cases = [
            LockedDiagnosticProperty(data: legacy, v2Status: kAudioHardwareUnspecifiedError),
            LockedDiagnosticProperty(data: legacy, v2Status: kAudioHardwareBadObjectError),
            LockedDiagnosticProperty(data: legacy, v2Data: legacy),
            LockedDiagnosticProperty(data: legacy, v2Data: v2, v2Size: 0),
            LockedDiagnosticProperty(data: legacy, v2Data: v2, v2WrongType: true),
            LockedDiagnosticProperty(data: legacy, v2Data: setting(v2, offset: 16, value: UInt64.max)),
        ]
        for properties in cases {
            if case .success = diagnosticReader(properties).read(31) { XCTFail("Invalid v2 fell back to v1") }
            XCTAssertEqual(properties.selectors, [0x6F73_4432])
        }
    }

    func testV2PropertyBoundaryRejectsOversizedAndStaleObservations() throws {
        let legacy = try VirtualMicrophoneDiagnosticFixture.data()
        let v2 = try VirtualMicrophoneDiagnosticFixture.dataV2()
        let valid = LockedDiagnosticProperty(data: legacy, v2Data: v2)
        XCTAssertEqual(try diagnosticReader(valid).read(31).get().schemaVersion, 2)
        XCTAssertEqual(valid.selectors, [0x6F73_4432])
        let stale = LockedDiagnosticProperty(data: legacy, v2Data: v2)
        XCTAssertEqual(diagnosticReader(stale, ticks: 2_000).read(31), .failure(.staleObservation))
        XCTAssertEqual(stale.selectors, [0x6F73_4432])
        let oversized = LockedDiagnosticProperty(data: legacy, v2Data: Data(count: 1_048_577))
        XCTAssertEqual(diagnosticReader(oversized).read(31), .failure(.snapshotSize(1_048_577)))
        XCTAssertEqual(oversized.selectors, [0x6F73_4432])
    }

    func testV2FailureCountersDoNotInvalidateTruthfulIdleInventory() throws {
        let observations = try (1...4).map { try v2Snapshot("failure-evidence", sequence: UInt64($0)) }
        XCTAssertTrue(observations.allSatisfy(\.isIdle))
        XCTAssertTrue(WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.provesMirroredIdle(observations))
    }

    private func diagnosticReader(_ properties: LockedDiagnosticProperty, ticks: UInt64 = 1_000)
        -> WorldwideVirtualMicrophoneDriverDiagnosticReader {
        WorldwideVirtualMicrophoneDriverDiagnosticReader(
            readProperty: { deviceID, address, size, value in properties.read(deviceID, address, &size, &value) },
            hostTicks: { ticks }
        )
    }

    private func v2Snapshot(_ mode: String = "idle-overflow", sequence: UInt64 = 1) throws
        -> WorldwideVirtualMicrophoneDriverDiagnosticSnapshot {
        try WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decodeV2(
            VirtualMicrophoneDiagnosticFixture.dataV2(mode, sequence: sequence, capturedHostTicks: 100 + sequence)
        ).get()
    }

    private func setting(_ data: Data, offset: Int, value: UInt64, width: Int = 8) -> Data {
        var result = data
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { result.replaceSubrange(offset..<(offset + width), with: $0.prefix(width)) }
        return result
    }

    private func assertV2Rejected(_ data: Data, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        if case .success = WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decodeV2(data) {
            XCTFail("Accepted malformed complete v2 inventory: \(context)", file: file, line: line)
        }
    }

    private func snapshot(
        _ mode: String = "idle", sequence: UInt64 = 1
    ) throws -> WorldwideVirtualMicrophoneDriverDiagnosticSnapshot {
        try WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decode(
            VirtualMicrophoneDiagnosticFixture.data(mode, sequence: sequence, capturedHostTicks: 100 + sequence)
        ).get()
    }
}

@MainActor
enum VirtualMicrophoneDiagnosticFixture {
    private static let binary: Result<URL, Error> = Result { try compile("VirtualMicrophoneDiagnosticFixture.c") }
    private static let v2Binary: Result<URL, Error> = Result { try compile("VirtualMicrophoneDiagnosticV2Fixture.c") }

    private static func compile(_ name: String) throws -> URL {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let macOS = tests.deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensteamer-diagnostic-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let executable = directory.appendingPathComponent("fixture")
        _ = try run(
            URL(fileURLWithPath: "/usr/bin/clang"),
            [macOS.appendingPathComponent("VirtualAudioDriver/tests/\(name)").path,
             "-I", macOS.appendingPathComponent("VirtualAudioDriver/include").path,
             "-framework", "CoreAudio", "-framework", "CoreFoundation", "-o", executable.path]
        )
        return executable
    }

    static func data(
        _ mode: String = "idle", sequence: UInt64 = 1, capturedHostTicks: UInt64 = 1_000
    ) throws -> Data {
        try run(binary.get(), [mode, String(sequence), String(capturedHostTicks)])
    }

    static func dataV2(
        _ mode: String = "idle-overflow", sequence: UInt64 = 1, capturedHostTicks: UInt64 = 1_000
    ) throws -> Data {
        try run(v2Binary.get(), [mode, String(sequence), String(capturedHostTicks)])
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "VirtualMicrophoneDiagnosticFixture", code: Int(process.terminationStatus))
        }
        return data
    }
}

private final class LockedDiagnosticProperty: @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data
    private let status: OSStatus
    private let size: UInt32
    private let wrongType: Bool
    private let v2Data: Data?
    private let v2Status: OSStatus?
    private let v2Size: UInt32?
    private let v2WrongType: Bool
    private var observedSelectors: [AudioObjectPropertySelector] = []
    private var address: AudioObjectPropertyAddress?
    private var deviceID: AudioDeviceID?
    private var inputSize: UInt32?

    init(data: Data, status: OSStatus = noErr, size: UInt32 = 8, wrongType: Bool = false,
         v2Data: Data? = nil, v2Status: OSStatus? = nil, v2Size: UInt32? = nil, v2WrongType: Bool = false) {
        self.data = data
        self.status = status
        self.size = size
        self.wrongType = wrongType
        self.v2Data = v2Data
        self.v2Status = v2Status
        self.v2Size = v2Size
        self.v2WrongType = v2WrongType
    }

    func read(
        _ deviceID: AudioDeviceID, _ address: AudioObjectPropertyAddress,
        _ size: inout UInt32, _ value: inout Unmanaged<CFPropertyList>?
    ) -> OSStatus {
        lock.withLock {
            self.address = address
            self.deviceID = deviceID
            inputSize = size
            observedSelectors.append(address.mSelector)
        }
        let isV2 = address.mSelector == 0x6F73_4432
        if isV2 && v2Data == nil && v2Status == nil { return kAudioHardwareUnknownPropertyError }
        size = isV2 ? (v2Size ?? self.size) : self.size
        if isV2 ? v2WrongType : wrongType {
            value = Unmanaged.passRetained("invalid" as CFString)
        } else {
            value = Unmanaged.passRetained((isV2 ? (v2Data ?? data) : data) as CFData)
        }
        return isV2 ? (v2Status ?? noErr) : status
    }

    var lastDeviceID: AudioDeviceID? { lock.withLock { deviceID } }
    var lastSelector: AudioObjectPropertySelector? { lock.withLock { address?.mSelector } }
    var lastScope: AudioObjectPropertyScope? { lock.withLock { address?.mScope } }
    var lastElement: AudioObjectPropertyElement? { lock.withLock { address?.mElement } }
    var requestedSize: UInt32? { lock.withLock { inputSize } }
    var selectors: [AudioObjectPropertySelector] { lock.withLock { observedSelectors } }
}
