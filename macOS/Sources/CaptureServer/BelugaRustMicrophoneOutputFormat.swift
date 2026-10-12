import BelugaCore

/// Copied-value decision only; native reads and queue ownership never cross FFI.
enum BelugaRustMicrophoneOutputFormat {
    typealias Facts = beluga_core_microphone_output_format_facts_t
    typealias RawObservation = beluga_core_microphone_output_format_observation_t
    typealias RawResult = beluga_core_microphone_output_format_result_t
    typealias Decision = Swift.Result<
        BlackHoleMicrophoneOutputFormatObservation,
        BlackHoleMicrophoneOutputFormatRejection
    >

    enum Failure: Error, Equatable { case layout, refused }

    static var layoutIsExact: Bool {
        UInt16(littleEndian: 1) == 1
            && exact(Facts.self, 80, 8)
            && exact(RawObservation.self, 56, 8)
            && exact(RawResult.self, 96, 8)
            && MemoryLayout<Facts>.offset(of: \Facts.abi_version) == 0
            && MemoryLayout<Facts>.offset(of: \Facts.wire_reserved) == 4
            && MemoryLayout<Facts>.offset(of: \Facts.stream_description_status) == 8
            && MemoryLayout<Facts>.offset(of: \Facts.device_sample_rate_status) == 12
            && MemoryLayout<Facts>.offset(of: \Facts.device_channel_count_status) == 16
            && MemoryLayout<Facts>.offset(of: \Facts.converter_error_read_status) == 20
            && MemoryLayout<Facts>.offset(of: \Facts.stream_sample_rate_bits) == 24
            && MemoryLayout<Facts>.offset(of: \Facts.stream_format_id) == 32
            && MemoryLayout<Facts>.offset(of: \Facts.stream_format_flags) == 36
            && MemoryLayout<Facts>.offset(of: \Facts.stream_bytes_per_packet) == 40
            && MemoryLayout<Facts>.offset(of: \Facts.stream_frames_per_packet) == 44
            && MemoryLayout<Facts>.offset(of: \Facts.stream_bytes_per_frame) == 48
            && MemoryLayout<Facts>.offset(of: \Facts.stream_channels_per_frame) == 52
            && MemoryLayout<Facts>.offset(of: \Facts.stream_bits_per_channel) == 56
            && MemoryLayout<Facts>.offset(of: \Facts.stream_reserved) == 60
            && MemoryLayout<Facts>.offset(of: \Facts.device_sample_rate_bits) == 64
            && MemoryLayout<Facts>.offset(of: \Facts.device_channel_count) == 72
            && MemoryLayout<Facts>.offset(of: \Facts.converter_error) == 76
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.sample_rate_bits) == 0
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.format_id) == 8
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.format_flags) == 12
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.bytes_per_packet) == 16
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.frames_per_packet) == 20
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.bytes_per_frame) == 24
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.channels_per_frame) == 28
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.bits_per_channel) == 32
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.stream_reserved) == 36
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.device_sample_rate_bits) == 40
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.device_channel_count) == 48
            && MemoryLayout<RawObservation>.offset(of: \RawObservation.converter_error) == 52
            && MemoryLayout<RawResult>.offset(of: \RawResult.abi_version) == 0
            && MemoryLayout<RawResult>.offset(of: \RawResult.status) == 4
            && MemoryLayout<RawResult>.offset(of: \RawResult.accepted) == 8
            && MemoryLayout<RawResult>.offset(of: \RawResult.reason) == 12
            && MemoryLayout<RawResult>.offset(of: \RawResult.actual_core_audio_status) == 16
            && MemoryLayout<RawResult>.offset(of: \RawResult.actual_u32) == 20
            && MemoryLayout<RawResult>.offset(of: \RawResult.actual_rate_bits) == 24
            && MemoryLayout<RawResult>.offset(of: \RawResult.observation) == 32
            && MemoryLayout<RawResult>.offset(of: \RawResult.wire_reserved) == 88
    }

    static func evaluate(_ evidence: BlackHoleMicrophoneOutputFormatEvidence) throws -> Decision {
        let facts = try encode(evidence)
        let actual = beluga_core_microphone_output_format_decide(facts)
        return try verified(facts: facts, result: actual)
    }

#if DEBUG
    /// Corruption occurs only after the genuine producer; verification is fixed.
    static func evaluateRawForTesting(
        facts: Facts,
        postResultMutation: (Facts, RawResult) -> RawResult
    ) throws -> Decision {
        try requireLayout()
        let actual = beluga_core_microphone_output_format_decide(facts)
        return try verified(facts: facts, result: postResultMutation(facts, actual))
    }
#endif

    static func encode(_ evidence: BlackHoleMicrophoneOutputFormatEvidence) throws -> Facts {
        try requireLayout()
        let stream = evidence.streamDescription
        return Facts(
            abi_version: 1, wire_reserved: 0,
            stream_description_status: evidence.streamDescriptionStatus,
            device_sample_rate_status: evidence.deviceSampleRateStatus,
            device_channel_count_status: evidence.deviceChannelCountStatus,
            converter_error_read_status: evidence.converterErrorReadStatus,
            stream_sample_rate_bits: stream.mSampleRate.bitPattern,
            stream_format_id: stream.mFormatID,
            stream_format_flags: stream.mFormatFlags,
            stream_bytes_per_packet: stream.mBytesPerPacket,
            stream_frames_per_packet: stream.mFramesPerPacket,
            stream_bytes_per_frame: stream.mBytesPerFrame,
            stream_channels_per_frame: stream.mChannelsPerFrame,
            stream_bits_per_channel: stream.mBitsPerChannel,
            stream_reserved: stream.mReserved,
            device_sample_rate_bits: evidence.deviceSampleRate.bitPattern,
            device_channel_count: evidence.deviceChannelCount,
            converter_error: evidence.converterError
        )
    }

    private static func verified(facts: Facts, result: RawResult) throws -> Decision {
        guard beluga_core_microphone_output_format_result_is_valid(facts, result) == 1,
              result.abi_version == 1, result.status == 1,
              result.wire_reserved == 0 else { throw Failure.refused }

        if result.accepted == 1, result.reason == 0 {
            let value = result.observation
            return .success(BlackHoleMicrophoneOutputFormatObservation(
                sampleRate: Double(bitPattern: value.sample_rate_bits),
                formatID: value.format_id, formatFlags: value.format_flags,
                bytesPerPacket: value.bytes_per_packet, framesPerPacket: value.frames_per_packet,
                bytesPerFrame: value.bytes_per_frame, channelsPerFrame: value.channels_per_frame,
                bitsPerChannel: value.bits_per_channel, reserved: value.stream_reserved,
                deviceSampleRate: Double(bitPattern: value.device_sample_rate_bits),
                deviceChannelCount: value.device_channel_count, converterError: value.converter_error
            ))
        }
        guard result.accepted == 0 else { throw Failure.refused }
        let rejection: BlackHoleMicrophoneOutputFormatRejection
        switch result.reason {
        case 1: rejection = .streamDescriptionCoreAudioStatus(result.actual_core_audio_status)
        case 2: rejection = .deviceSampleRateCoreAudioStatus(result.actual_core_audio_status)
        case 3: rejection = .deviceChannelCountCoreAudioStatus(result.actual_core_audio_status)
        case 4: rejection = .converterErrorCoreAudioStatus(result.actual_core_audio_status)
        case 5: rejection = .unexpectedStreamSampleRate(actual: Double(bitPattern: result.actual_rate_bits))
        case 6: rejection = .unexpectedStreamFormatID(actual: result.actual_u32)
        case 7: rejection = .unexpectedStreamFormatFlags(actual: result.actual_u32)
        case 8: rejection = .unexpectedStreamBytesPerPacket(actual: result.actual_u32)
        case 9: rejection = .unexpectedStreamFramesPerPacket(actual: result.actual_u32)
        case 10: rejection = .unexpectedStreamBytesPerFrame(actual: result.actual_u32)
        case 11: rejection = .unexpectedStreamChannelsPerFrame(actual: result.actual_u32)
        case 12: rejection = .unexpectedStreamBitsPerChannel(actual: result.actual_u32)
        case 13: rejection = .unexpectedStreamReserved(actual: result.actual_u32)
        case 14: rejection = .unexpectedDeviceSampleRate(actual: Double(bitPattern: result.actual_rate_bits))
        case 15: rejection = .unexpectedDeviceChannelCount(actual: result.actual_u32)
        case 16: rejection = .converterError(actual: result.actual_u32)
        default: throw Failure.refused
        }
        return .failure(rejection)
    }

    private static func requireLayout() throws {
        guard layoutIsExact else { throw Failure.layout }
    }

    private static func exact<T>(_ type: T.Type, _ size: Int, _ alignment: Int) -> Bool {
        MemoryLayout<T>.size == size && MemoryLayout<T>.stride == size
            && MemoryLayout<T>.alignment == alignment
    }
}
