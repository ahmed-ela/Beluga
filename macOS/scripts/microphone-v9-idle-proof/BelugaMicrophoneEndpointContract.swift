import CoreAudio
import Foundation

// Narrow passive equivalent of the product's canonical endpoint contract.
// The native helper never installs a monitor or writes a property.
struct BelugaMicrophoneNativeFormat: Equatable, Sendable {
    let rate: Double
    let formatID: UInt32
    let flags: UInt32
    let bytesPerPacket: UInt32
    let framesPerPacket: UInt32
    let bytesPerFrame: UInt32
    let channels: UInt32
    let bits: UInt32
    let reserved: UInt32

    init(_ value: AudioStreamBasicDescription) {
        rate = value.mSampleRate; formatID = value.mFormatID; flags = value.mFormatFlags
        bytesPerPacket = value.mBytesPerPacket; framesPerPacket = value.mFramesPerPacket
        bytesPerFrame = value.mBytesPerFrame; channels = value.mChannelsPerFrame
        bits = value.mBitsPerChannel; reserved = value.mReserved
    }

    var isCanonical: Bool {
        rate == 48_000 && formatID == kAudioFormatLinearPCM &&
        flags == (kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked) &&
        bytesPerPacket == 4 && framesPerPacket == 1 && bytesPerFrame == 4 && channels == 1 && bits == 32 && reserved == 0
    }
}

struct BelugaMicrophoneEndpointState: Sendable {
    let model: String
    let alive: UInt32
    let hidden: UInt32
    let inputChannels: UInt32
    let outputChannels: UInt32
    let inputStreams: [AudioStreamID]
    let outputStreams: [AudioStreamID]
    let nominalRate: Double
    let clockDomain: UInt32
    let virtualFormat: BelugaMicrophoneNativeFormat
    let physicalFormat: BelugaMicrophoneNativeFormat

    func satisfies(visible: Bool) -> Bool {
        model == "com.elamin.opensteamer.virtual-microphone.model" && alive == 1 && hidden == (visible ? 0 : 1) &&
        inputChannels == (visible ? 1 : 0) && outputChannels == (visible ? 0 : 1) &&
        inputStreams.count == (visible ? 1 : 0) && outputStreams.count == (visible ? 0 : 1) &&
        nominalRate == 48_000 && clockDomain == 0x6f73_564d &&
        virtualFormat.isCanonical && physicalFormat.isCanonical && virtualFormat == physicalFormat &&
        (visible ? inputStreams : outputStreams).allSatisfy { $0 != kAudioObjectUnknown }
    }
}

enum BelugaMicrophoneEndpointContract {
    static func validate(device: AudioDeviceID, visible: Bool) throws -> AudioStreamID {
        let input = try streams(device, scope: kAudioDevicePropertyScopeInput)
        let output = try streams(device, scope: kAudioDevicePropertyScopeOutput)
        let roleStreams = visible ? input : output
        guard roleStreams.count == 1 else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        let stream = roleStreams[0]
        let state = BelugaMicrophoneEndpointState(
            model: try string(device, kAudioDevicePropertyModelUID),
            alive: try scalar(device, kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0)),
            hidden: try scalar(device, kAudioDevicePropertyIsHidden, initial: UInt32(0)),
            inputChannels: try channels(device, scope: kAudioDevicePropertyScopeInput),
            outputChannels: try channels(device, scope: kAudioDevicePropertyScopeOutput),
            inputStreams: input, outputStreams: output,
            nominalRate: try scalar(device, kAudioDevicePropertyNominalSampleRate, initial: Double(0)),
            clockDomain: try scalar(device, kAudioDevicePropertyClockDomain, initial: UInt32(0)),
            virtualFormat: .init(try scalar(stream, kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())),
            physicalFormat: .init(try scalar(stream, kAudioStreamPropertyPhysicalFormat, initial: AudioStreamBasicDescription()))
        )
        guard state.satisfies(visible: visible) else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        return stream
    }

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) throws -> T {
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        var property = address(selector)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
        }
        guard status == noErr, size == MemoryLayout<T>.size else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        return value
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var property = address(selector)
        let status = AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value)
        defer { value?.release() }
        guard status == noErr, size == MemoryLayout<Unmanaged<CFString>?>.size,
              let found = value?.takeUnretainedValue(), CFGetTypeID(found) == CFStringGetTypeID() else {
            throw BelugaMicrophoneIdleFailure.endpointIdentity
        }
        return found as String
    }

    private static func bytes(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                              scope: AudioObjectPropertyScope, maximum: UInt32) throws -> Data {
        var property = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr,
              size <= maximum else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        if size == 0 { return Data() }
        let expected = size
        var data = Data(count: Int(size))
        let status = data.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr, size == expected else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        return data
    }

    private static func streams(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> [AudioStreamID] {
        let data = try bytes(device, kAudioDevicePropertyStreams, scope: scope, maximum: 4)
        guard data.count == 0 || data.count == MemoryLayout<AudioStreamID>.size else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        return data.isEmpty ? [] : [data.withUnsafeBytes { $0.loadUnaligned(as: AudioStreamID.self) }]
    }

    private static func channels(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> UInt32 {
        let data = try bytes(device, kAudioDevicePropertyStreamConfiguration, scope: scope, maximum: UInt32(MemoryLayout<AudioBufferList>.size))
        return try decodeChannels(data)
    }

    static func decodeChannels(_ data: Data) throws -> UInt32 {
        let header = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!
        guard data.count >= header else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        guard data[4..<header].allSatisfy({ $0 == 0 }) else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        let count = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard count <= 1, data.count == header + Int(count) * MemoryLayout<AudioBuffer>.size else {
            throw BelugaMicrophoneIdleFailure.endpointIdentity
        }
        if count == 0 { return 0 }
        let buffer = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: header, as: AudioBuffer.self) }
        // StreamConfiguration may report buffer capacity, but must not expose PCM storage.
        guard buffer.mData == nil else { throw BelugaMicrophoneIdleFailure.endpointIdentity }
        return buffer.mNumberChannels
    }
}
