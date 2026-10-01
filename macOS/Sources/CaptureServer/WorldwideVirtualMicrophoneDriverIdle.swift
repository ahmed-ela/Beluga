import CoreAudio
import Darwin
import Foundation

enum WorldwideVirtualMicrophoneDriverDiagnosticError: Error, Equatable, Sendable {
    case property(OSStatus)
    case propertySize(UInt32)
    case propertyType
    case snapshotSize(Int)
    case unsupportedSchema
    case incoherentSnapshot
    case staleObservation
}

struct WorldwideVirtualMicrophoneDriverDiagnosticSnapshot: Equatable, Sendable {
    // OSVADiagnosticSnapshot in OpensteamerVirtualMicrophoneDriver.h pins this
    // little-endian POD ABI for both supported Mac architectures.
    static let property: AudioObjectPropertySelector = 0x6F73_4453
    static let v2Property: AudioObjectPropertySelector = 0x6F73_4432
    static let byteCount = 8_608
    static let v2HeaderByteCount = 3_504
    static let v2RecordByteCount = 88
    static let maximumV2ByteCount = 1_048_576
    private static let requiredFlags: UInt64 = 0x3_FF01
    private static let timelineActiveFlag: UInt64 = 2

    struct Epoch: Equatable, Sendable {
        let instance: UInt64
        let driverLifecycle: UInt64
        let coreLifecycle: UInt64
        let timelineSeed: UInt64
        let seedGeneration: UInt64
        let anchorHostTicks: UInt64
        let lastIssuedSeed: UInt64
        let lastIssuedSessionID: UInt64
    }

    let sequence: UInt64
    let capturedHostTicks: UInt64
    let epoch: Epoch
    let isIdle: Bool
    let schemaVersion: UInt32

    private struct InventoryIdentity: Equatable, Sendable {
        let revision: UInt64?
        let registrations: Data
        let coreSlots: Data
    }
    private let inventoryIdentity: InventoryIdentity

    static func decode(_ data: Data) -> Result<Self, WorldwideVirtualMicrophoneDriverDiagnosticError> {
        guard data.count == byteCount else {
            return .failure(.snapshotSize(data.count))
        }
        func u32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }
        func u64(_ offset: Int) -> UInt64 {
            data.withUnsafeBytes {
                UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            }
        }
        guard u32(0) == 1, u32(4) == UInt32(byteCount) else {
            return .failure(.unsupportedSchema)
        }
        let flags = u64(32)
        let knownFlags = requiredFlags | timelineActiveFlag
        let sequence = u64(8)
        let capturedHostTicks = u64(16)
        let epoch = Epoch(
            instance: u64(24),
            driverLifecycle: u64(40),
            coreLifecycle: u64(48),
            timelineSeed: u64(64),
            seedGeneration: u64(72),
            anchorHostTicks: u64(80),
            lastIssuedSeed: u64(88),
            lastIssuedSessionID: u64(96)
        )
        let active = u64(104)
        let visible = u64(112)
        let hidden = u64(120)
        let coreSlots = u64(128)
        let registered = u64(144)
        let started = u64(152)
        let visibleRegistered = u64(160)
        let hiddenRegistered = u64(168)
        let visibleStarted = u64(176)
        let hiddenStarted = u64(184)
        let counts = [active, visible, hidden, coreSlots, registered, started,
                      visibleRegistered, hiddenRegistered, visibleStarted, hiddenStarted]
        guard sequence > 0, capturedHostTicks > 0, epoch.instance > 0,
              epoch.driverLifecycle > 0, epoch.coreLifecycle % 2 == 0,
              u64(56) > 0, u32(328) == 64, u32(332) == 0,
              flags & requiredFlags == requiredFlags,
              flags & ~knownFlags == 0,
              counts.allSatisfy({ $0 <= 64 }),
              visible + hidden == active, coreSlots == active,
              visibleRegistered + hiddenRegistered == registered,
              visibleStarted + hiddenStarted == started,
              started == active, visibleStarted == visible, hiddenStarted == hidden,
              visibleStarted <= visibleRegistered, hiddenStarted <= hiddenRegistered,
              u64(136).nonzeroBitCount == Int(coreSlots),
              u64(192).nonzeroBitCount == Int(registered),
              u64(200).nonzeroBitCount == Int(started) else {
            return .failure(.incoherentSnapshot)
        }
        let timelineActive = flags & timelineActiveFlag != 0
        let isIdle = active == 0
        if isIdle {
            guard !timelineActive, epoch.timelineSeed == 0,
                  epoch.seedGeneration == 0, epoch.anchorHostTicks == 0,
                  u64(248) == u64(264), u64(272) == u64(280),
                  u64(1_192) == 0, u64(1_264) == 0,
                  legacyIdleInventoryIsExact(data, registered: registered,
                                             visible: visibleRegistered, hidden: hiddenRegistered) else {
                return .failure(.incoherentSnapshot)
            }
        } else {
            guard timelineActive, epoch.timelineSeed > 0,
                  epoch.seedGeneration == epoch.timelineSeed,
                  epoch.anchorHostTicks > 0 else {
                return .failure(.incoherentSnapshot)
            }
        }
        return .success(Self(
            sequence: sequence,
            capturedHostTicks: capturedHostTicks,
            epoch: epoch,
            isIdle: isIdle,
            schemaVersion: 1,
            inventoryIdentity: InventoryIdentity(
                revision: nil, registrations: Data(data[1_312..<6_432]),
                coreSlots: Data(data[6_432..<8_480])
            )
        ))
    }

    private struct Bytes {
        let data: Data
        func u32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }
        func u64(_ offset: Int) -> UInt64 {
            data.withUnsafeBytes {
                UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            }
        }
        func isZero(_ range: Range<Int>) -> Bool { data[range].allSatisfy { $0 == 0 } }
    }

    private static func legacyIdleInventoryIsExact(
        _ data: Data, registered: UInt64, visible: UInt64, hidden: UInt64
    ) -> Bool {
        let bytes = Bytes(data: data)
        var counts: [UInt64] = [0, 0]
        var bitmap: UInt64 = 0
        var keys = Set<UInt64>()
        for index in 0..<64 {
            let base = 1_312 + index * 80
            let flags = bytes.u32(base + 48)
            guard bytes.u64(6_432 + index * 32) == 0,
                  bytes.u32(base + 76) == 0,
                  bytes.u64(base + 32) == 0, bytes.u64(base + 40) == 0,
                  bytes.u32(base + 72) == 0, flags == 0 || flags == 1 else { return false }
            if flags == 0 { continue }
            let device = bytes.u32(base + 52), role = bytes.u32(base + 64)
            guard bytes.u64(base) > 0, bytes.u64(base + 8) > 0,
                  device == 2 || device == 6, role == (device == 2 ? 1 : 2),
                  bytes.u32(base + 68) == UInt32.max,
                  keys.insert(UInt64(device) << 32 | UInt64(bytes.u32(base + 56))).inserted else { return false }
            counts[Int(role - 1)] += 1
            bitmap |= UInt64(1) << index
        }
        return counts[0] == visible && counts[1] == hidden &&
            counts[0] + counts[1] == registered && bitmap == bytes.u64(192) &&
            bytes.isZero(8_480..<8_608)
    }

    static func decodeV2(_ data: Data) -> Result<Self, WorldwideVirtualMicrophoneDriverDiagnosticError> {
        guard data.count >= v2HeaderByteCount, data.count <= maximumV2ByteCount else {
            return .failure(.snapshotSize(data.count))
        }
        let bytes = Bytes(data: data)
        guard bytes.u32(0) == 2, bytes.u32(4) == UInt32(v2HeaderByteCount),
              bytes.u64(24) == UInt64(v2RecordByteCount), bytes.u32(40) == 64 else {
            return .failure(.unsupportedSchema)
        }
        let count = bytes.u64(16)
        // Bound count before converting to Int, multiplying, or reading a record.
        guard count <= UInt64((maximumV2ByteCount - v2HeaderByteCount) / v2RecordByteCount),
              bytes.u64(8) == UInt64(data.count),
              v2HeaderByteCount + Int(count) * v2RecordByteCount == data.count,
              bytes.u32(44) == 0, bytes.isZero(3_440..<3_504) else {
            return .failure(.incoherentSnapshot)
        }
        let sequence = bytes.u64(48), captured = bytes.u64(56)
        let flags = bytes.u64(72), v2RequiredFlags = requiredFlags | UInt64(1 << 18)
        let epoch = Epoch(instance: bytes.u64(64), driverLifecycle: bytes.u64(80),
                          coreLifecycle: bytes.u64(88), timelineSeed: bytes.u64(104),
                          seedGeneration: bytes.u64(112), anchorHostTicks: bytes.u64(120),
                          lastIssuedSeed: bytes.u64(128), lastIssuedSessionID: bytes.u64(136))
        let active = bytes.u64(144), visible = bytes.u64(152), hidden = bytes.u64(160)
        let coreCount = bytes.u64(168), registered = bytes.u64(184), started = bytes.u64(192)
        let visibleRegistered = bytes.u64(200), hiddenRegistered = bytes.u64(208)
        let visibleStarted = bytes.u64(216), hiddenStarted = bytes.u64(224)
        guard sequence > 0, captured > 0, epoch.instance > 0, epoch.driverLifecycle > 0,
              epoch.coreLifecycle % 2 == 0, bytes.u64(96) > 0,
              flags & v2RequiredFlags == v2RequiredFlags,
              flags & ~(v2RequiredFlags | timelineActiveFlag) == 0,
              [active, visible, hidden, coreCount, started, visibleStarted, hiddenStarted].allSatisfy({ $0 <= 64 }),
              registered == count, visibleRegistered <= count, hiddenRegistered <= count,
              visibleRegistered + hiddenRegistered == registered,
              visible + hidden == active, coreCount == active, started == active,
              visibleStarted + hiddenStarted == started,
              visibleStarted == visible, hiddenStarted == hidden,
              visibleStarted <= visibleRegistered, hiddenStarted <= hiddenRegistered,
              validateV2Metadata(bytes) else { return .failure(.incoherentSnapshot) }

        var derivedCore: [UInt64] = [0, 0], coreBitmap: UInt64 = 0
        var sessions = Set<UInt64>()
        for index in 0..<64 {
            let base = 1_392 + index * 32
            let session = bytes.u64(base), role = bytes.u32(base + 24)
            guard role <= 2, bytes.u32(base + 28) == 0 else { return .failure(.incoherentSnapshot) }
            if session == 0 { continue } // A retired slot retains non-active metadata.
            guard role > 0, bytes.u64(base + 16) == epoch.timelineSeed,
                  sessions.insert(session).inserted else { return .failure(.incoherentSnapshot) }
            derivedCore[Int(role - 1)] += 1
            coreBitmap |= UInt64(1) << index
        }
        var derivedRegistered: [UInt64] = [0, 0], derivedStarted: [UInt64] = [0, 0]
        var references: UInt64 = 0
        var previousIndex: UInt64?
        var generations = Set<UInt64>(), keys = Set<UInt64>()
        for index in 0..<Int(count) {
            let record = v2HeaderByteCount + index * v2RecordByteCount
            let registryIndex = bytes.u64(record), base = record + 8
            let generation = bytes.u64(base), clientFlags = bytes.u32(base + 48)
            let device = bytes.u32(base + 52), clientID = bytes.u32(base + 56)
            let role = bytes.u32(base + 64), coreSlot = bytes.u32(base + 68)
            let key = UInt64(device) << 32 | UInt64(clientID)
            guard registryIndex != UInt64.max, previousIndex.map({ $0 < registryIndex }) ?? true,
                  generation > 0, generations.insert(generation).inserted,
                  bytes.u64(base + 8) > 0, bytes.u64(base + 24) > 0,
                  clientFlags == 1 || clientFlags == 7,
                  device == 2 || device == 6, role == (device == 2 ? 1 : 2),
                  bytes.u32(base + 76) == 0, keys.insert(key).inserted else {
                return .failure(.incoherentSnapshot)
            }
            previousIndex = registryIndex
            derivedRegistered[Int(role - 1)] += 1
            if clientFlags == 1 {
                guard bytes.u64(base + 32) == 0, bytes.u64(base + 40) == 0,
                      coreSlot == UInt32.max, bytes.u32(base + 72) == 0 else {
                    return .failure(.incoherentSnapshot)
                }
                continue
            }
            guard coreSlot < 64, bytes.u64(base + 16) > 0, bytes.u32(base + 72) == 1,
                  bytes.u64(base + 32) > 0, bytes.u64(base + 40) == epoch.timelineSeed else {
                return .failure(.incoherentSnapshot)
            }
            let core = 1_392 + Int(coreSlot) * 32, bit = UInt64(1) << coreSlot
            guard references & bit == 0, bytes.u64(core) == bytes.u64(base + 32),
                  bytes.u64(core + 8) == key, bytes.u64(core + 16) == bytes.u64(base + 40),
                  bytes.u32(core + 24) == role else { return .failure(.incoherentSnapshot) }
            references |= bit
            derivedStarted[Int(role - 1)] += 1
        }
        guard derivedCore == [visible, hidden], coreBitmap == bytes.u64(176),
              references == coreBitmap, derivedRegistered == [visibleRegistered, hiddenRegistered],
              derivedStarted == [visibleStarted, hiddenStarted] else { return .failure(.incoherentSnapshot) }
        let idle = active == 0, timelineActive = flags & timelineActiveFlag != 0
        if idle {
            guard !timelineActive, epoch.timelineSeed == 0, epoch.seedGeneration == 0,
                  epoch.anchorHostTicks == 0, bytes.u64(272) == bytes.u64(288),
                  bytes.u64(296) == bytes.u64(304), bytes.u64(1_208) == 0,
                  bytes.u64(1_280) == 0,
                  bytes.u64(1_216) == bytes.u64(1_224),
                  bytes.u64(1_288) == bytes.u64(1_296) else { return .failure(.incoherentSnapshot) }
        } else {
            guard timelineActive, epoch.timelineSeed > 0, epoch.seedGeneration == epoch.timelineSeed,
                  epoch.anchorHostTicks > 0 else { return .failure(.incoherentSnapshot) }
        }
        return .success(Self(sequence: sequence, capturedHostTicks: captured, epoch: epoch, isIdle: idle,
                             schemaVersion: 2, inventoryIdentity: InventoryIdentity(
                                revision: bytes.u64(32), registrations: Data(data[v2HeaderByteCount..<data.count]),
                                coreSlots: Data(data[1_392..<3_440])
                             )))
    }

    private static func validateV2Metadata(_ bytes: Bytes) -> Bool {
        for base in [352, 424] {
            let index = bytes.u32(base + 64)
            guard bytes.u64(base + 48) == 0, bytes.u32(base + 56) <= 6,
                  bytes.u32(base + 60) <= 2, index < 64 || index == UInt32.max else { return false }
        }
        for index in 0..<2 {
            let zero = 496 + index * 136, io = 768 + index * 208, loop = 1_184 + index * 72
            // Lifetime failure counters are evidence, not malformed geometry.
            guard bytes.u32(zero + 132) == 0, bytes.u32(io + 204) == 0,
                  bytes.u32(zero + 128) & ~UInt32(31) == 0,
                  bytes.u32(io + 200) & ~UInt32(31) == 0,
                  bytes.u32(loop + 68) & ~UInt32(5) == 0,
                  bytes.u64(zero + 8) % 2 == 0, bytes.u64(io + 8) % 2 == 0,
                  bytes.u64(loop + 8) % 2 == 0 else { return false }
        }
        let failure = 1_328
        if bytes.u64(failure) == 0 { return bytes.isZero(failure..<1_392) }
        let operation = bytes.u32(failure + 32), reason = bytes.u32(failure + 36)
        let device = bytes.u32(failure + 40), index = bytes.u64(failure + 16)
        let generation = bytes.u64(failure + 24), status = bytes.u32(failure + 52)
        let coreStatus = bytes.u32(failure + 56)
        guard bytes.u64(failure + 8) > 0, (1...4).contains(operation), (1...9).contains(reason),
              device == 2 || device == 6, bytes.u32(failure + 60) == 0,
              (index == UInt64.max) == (generation == 0), status != 0 else { return false }
        if reason == 9 {
            let illegal = [UInt32(1), 4, 5, 7, 8, 9, 10].contains(coreStatus)
            return (operation == 3 || operation == 4) && index != UInt64.max &&
                (1...15).contains(coreStatus) && status == UInt32(bitPattern:
                    illegal ? kAudioHardwareIllegalOperationError : kAudioHardwareUnspecifiedError)
        }
        guard coreStatus == 0 else { return false }
        if reason == 3 || reason == 4 {
            return operation == 1 && index == UInt64.max &&
                status == UInt32(bitPattern: kAudioHardwareUnspecifiedError)
        }
        guard status == UInt32(bitPattern: kAudioHardwareIllegalOperationError) else { return false }
        switch reason {
        case 2: return operation == 1 && index != UInt64.max
        case 5: return operation != 1 && index == UInt64.max
        case 6: return operation == 3 && index != UInt64.max
        case 7: return operation == 4 && index != UInt64.max
        case 8: return operation == 2 && index != UInt64.max
        default: return true
        }
    }

    static func provesMirroredIdle(_ observations: [Self]) -> Bool {
        guard observations.count == 4, let first = observations.first,
              observations.allSatisfy({ $0.isIdle && $0.epoch == first.epoch &&
                  $0.schemaVersion == first.schemaVersion && $0.inventoryIdentity == first.inventoryIdentity }) else {
            return false
        }
        return zip(observations, observations.dropFirst()).allSatisfy {
            $0.sequence < $1.sequence && $0.capturedHostTicks < $1.capturedHostTicks
        }
    }
}

struct WorldwideVirtualMicrophoneDriverDiagnosticReader: Sendable {
    typealias PropertyRead = @Sendable (
        AudioDeviceID, AudioObjectPropertyAddress,
        inout UInt32, inout Unmanaged<CFPropertyList>?
    ) -> OSStatus
    private let readProperty: PropertyRead
    private let hostTicks: @Sendable () -> UInt64

    init(
        readProperty: @escaping PropertyRead = { deviceID, address, size, value in
            var address = address
            return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        },
        hostTicks: @escaping @Sendable () -> UInt64 = { mach_absolute_time() }
    ) {
        self.readProperty = readProperty
        self.hostTicks = hostTicks
    }

    func read(_ deviceID: AudioDeviceID) -> Result<
        WorldwideVirtualMicrophoneDriverDiagnosticSnapshot,
        WorldwideVirtualMicrophoneDriverDiagnosticError
    > {
        let v2 = read(deviceID, selector: WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.v2Property)
        // An unavailable, malformed, stale, or failed v2 observation may not be
        // replaced by the frozen bank's incomplete view. Only genuine absence
        // on an old driver grants the legacy read.
        guard case .failure(.property(kAudioHardwareUnknownPropertyError)) = v2 else { return v2 }
        return read(deviceID, selector: WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.property)
    }

    private func read(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> Result<
        WorldwideVirtualMicrophoneDriverDiagnosticSnapshot,
        WorldwideVirtualMicrophoneDriverDiagnosticError
    > {
        var size = UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size)
        var value: Unmanaged<CFPropertyList>?
        let address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let before = hostTicks()
        let status = readProperty(deviceID, address, &size, &value)
        let after = hostTicks()
        defer { value?.release() }
        guard status == noErr else { return .failure(.property(status)) }
        guard size == UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size) else {
            return .failure(.propertySize(size))
        }
        guard let property = value?.takeUnretainedValue(),
              CFGetTypeID(property) == CFDataGetTypeID() else {
            return .failure(.propertyType)
        }
        let data = unsafeDowncast(property, to: CFData.self)
        let length = CFDataGetLength(data)
        let isV2 = selector == WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.v2Property
        guard isV2 ?
            (length >= WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.v2HeaderByteCount &&
             length <= WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.maximumV2ByteCount) :
            length == WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.byteCount else {
            return .failure(.snapshotSize(length))
        }
        guard let bytes = CFDataGetBytePtr(data) else { return .failure(.propertyType) }
        let payload = Data(bytes: bytes, count: length)
        let decoded = isV2 ? WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decodeV2(payload) :
            WorldwideVirtualMicrophoneDriverDiagnosticSnapshot.decode(payload)
        guard case .success(let snapshot) = decoded else { return decoded }
        guard before <= snapshot.capturedHostTicks, snapshot.capturedHostTicks <= after else {
            return .failure(.staleObservation)
        }
        return decoded
    }
}
