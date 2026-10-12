import AudioToolbox
import BelugaCore
import CoreAudio
import XCTest
@testable import CaptureServer

#if DEBUG
final class BelugaRustMicrophoneOutputFormatTests: XCTestCase {
    private typealias Bridge = BelugaRustMicrophoneOutputFormat

    func testOutputFormatLiteralLayoutsAndEveryFieldOffset() {
        XCTAssertTrue(Bridge.layoutIsExact)
        XCTAssertEqual([MemoryLayout<Bridge.Facts>.size, MemoryLayout<Bridge.Facts>.stride,
            MemoryLayout<Bridge.Facts>.alignment], [80, 80, 8])
        XCTAssertEqual([MemoryLayout<Bridge.RawObservation>.size, MemoryLayout<Bridge.RawObservation>.stride,
            MemoryLayout<Bridge.RawObservation>.alignment], [56, 56, 8])
        XCTAssertEqual([MemoryLayout<Bridge.RawResult>.size, MemoryLayout<Bridge.RawResult>.stride,
            MemoryLayout<Bridge.RawResult>.alignment], [96, 96, 8])
        let factsOffsets = [
            MemoryLayout<Bridge.Facts>.offset(of: \.abi_version),
            MemoryLayout<Bridge.Facts>.offset(of: \.wire_reserved),
            MemoryLayout<Bridge.Facts>.offset(of: \.stream_description_status),
            MemoryLayout<Bridge.Facts>.offset(of: \.device_sample_rate_status),
            MemoryLayout<Bridge.Facts>.offset(of: \.device_channel_count_status),
            MemoryLayout<Bridge.Facts>.offset(of: \.converter_error_read_status),
            MemoryLayout<Bridge.Facts>.offset(of: \.stream_sample_rate_bits),
            MemoryLayout<Bridge.Facts>.offset(of: \.stream_format_id),
            MemoryLayout<Bridge.Facts>.offset(of: \.stream_format_flags),
            MemoryLayout<Bridge.Facts>.offset(of: \.stream_bytes_per_packet),
            MemoryLayout<Bridge.Facts>.offset(of: \.stream_frames_per_packet),
            MemoryLayout<Bridge.Facts>.offset(of: \.stream_bytes_per_frame),
            MemoryLayout<Bridge.Facts>.offset(of: \.stream_channels_per_frame),
            MemoryLayout<Bridge.Facts>.offset(of: \.stream_bits_per_channel),
            MemoryLayout<Bridge.Facts>.offset(of: \.stream_reserved),
            MemoryLayout<Bridge.Facts>.offset(of: \.device_sample_rate_bits),
            MemoryLayout<Bridge.Facts>.offset(of: \.device_channel_count),
            MemoryLayout<Bridge.Facts>.offset(of: \.converter_error),
        ]
        XCTAssertEqual(factsOffsets, [0, 4, 8, 12, 16, 20, 24, 32, 36, 40, 44, 48, 52, 56, 60, 64, 72, 76])
        let observationOffsets = [
            MemoryLayout<Bridge.RawObservation>.offset(of: \.sample_rate_bits),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.format_id),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.format_flags),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.bytes_per_packet),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.frames_per_packet),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.bytes_per_frame),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.channels_per_frame),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.bits_per_channel),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.stream_reserved),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.device_sample_rate_bits),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.device_channel_count),
            MemoryLayout<Bridge.RawObservation>.offset(of: \.converter_error),
        ]
        XCTAssertEqual(observationOffsets, [0, 8, 12, 16, 20, 24, 28, 32, 36, 40, 48, 52])
        let resultOffsets = [
            MemoryLayout<Bridge.RawResult>.offset(of: \.abi_version),
            MemoryLayout<Bridge.RawResult>.offset(of: \.status),
            MemoryLayout<Bridge.RawResult>.offset(of: \.accepted),
            MemoryLayout<Bridge.RawResult>.offset(of: \.reason),
            MemoryLayout<Bridge.RawResult>.offset(of: \.actual_core_audio_status),
            MemoryLayout<Bridge.RawResult>.offset(of: \.actual_u32),
            MemoryLayout<Bridge.RawResult>.offset(of: \.actual_rate_bits),
            MemoryLayout<Bridge.RawResult>.offset(of: \.observation),
            MemoryLayout<Bridge.RawResult>.offset(of: \.wire_reserved),
        ]
        XCTAssertEqual(resultOffsets, [0, 4, 8, 12, 16, 20, 24, 32, 88])
    }

    func testOutputFormatExactSuccessAndSDKLiteralParity() throws {
        XCTAssertEqual(kAudioFormatLinearPCM, 0x6c70_636d)
        XCTAssertEqual(kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 12)
        XCTAssertEqual(Double(48_000).bitPattern, 0x40e7_7000_0000_0000)
        let evidence = valid()
        try assertParity(evidence)
        let facts = try Bridge.encode(evidence)
        let raw = try actualResult(facts)
        XCTAssertEqual([raw.abi_version, raw.status, raw.accepted, raw.reason], [1, 1, 1, 0])
        XCTAssertEqual(raw.actual_core_audio_status, 0)
        XCTAssertEqual(raw.actual_u32, 0)
        XCTAssertEqual(raw.actual_rate_bits, 0)
        XCTAssertEqual(raw.wire_reserved, 0)
        XCTAssertEqual(raw.observation.sample_rate_bits, evidence.streamDescription.mSampleRate.bitPattern)
        XCTAssertEqual(raw.observation.device_sample_rate_bits, evidence.deviceSampleRate.bitPattern)
        XCTAssertEqual([raw.observation.format_id, raw.observation.format_flags,
            raw.observation.bytes_per_packet, raw.observation.frames_per_packet,
            raw.observation.bytes_per_frame, raw.observation.channels_per_frame,
            raw.observation.bits_per_channel, raw.observation.stream_reserved,
            raw.observation.device_channel_count, raw.observation.converter_error],
            [0x6c70_636d, 12, 2, 1, 2, 1, 16, 0, 1, 0])
    }

    func testOutputFormatAllSixteenKnownRejectionsMatchOriginalSwift() throws {
        for reason in UInt32(1)...16 {
            let evidence = changed(valid(), reason, badValue(reason))
            try assertParity(evidence)
            let raw = try actualResult(Bridge.encode(evidence))
            XCTAssertEqual([raw.status, raw.accepted, raw.reason], [1, 0, reason])
            assertZeroObservation(raw.observation)
        }
    }

    func testOutputFormatEverySimultaneousErrorPairKeepsOriginalFirstGuard() throws {
        for first in UInt32(1)...16 {
            for second in (first + 1)...17 where second <= 16 {
                let evidence = changed(changed(valid(), second, badValue(second)), first, badValue(first))
                try assertParity(evidence)
                XCTAssertEqual(try actualResult(Bridge.encode(evidence)).reason, first)
            }
            var allLaterWrong = valid()
            for reason in first...16 { allLaterWrong = changed(allLaterWrong, reason, badValue(reason)) }
            try assertParity(allLaterWrong)
            XCTAssertEqual(try actualResult(Bridge.encode(allLaterWrong)).reason, first)
        }
    }

    func testOutputFormatAllFourSignedStatusExtremesPreserveOriginalDiagnostics() throws {
        for reason in UInt32(1)...4 {
            for status in [Int32.min, Int32.min + 1, -50, -1, 1, Int32.max] {
                let evidence = changed(valid(), reason, UInt64(UInt32(bitPattern: status)))
                try assertParity(evidence)
                let raw = try actualResult(Bridge.encode(evidence))
                XCTAssertEqual(raw.reason, reason)
                XCTAssertEqual(raw.actual_core_audio_status, status)
                XCTAssertEqual(raw.actual_u32, 0)
                XCTAssertEqual(raw.actual_rate_bits, 0)
            }
        }
    }

    func testOutputFormatAllUInt32DomainsStayExactAndFullWidth() throws {
        for reason in [UInt32(6), 7, 8, 9, 10, 11, 12, 13, 15, 16] {
            for word in [UInt32(0), 1, 2, 3, 4, 8, 12, 16, 0x0001_0000, 0x8000_0000, UInt32.max] {
                let evidence = changed(valid(), reason, UInt64(word))
                try assertParity(evidence)
                let raw = try actualResult(Bridge.encode(evidence))
                if raw.accepted == 0 {
                    XCTAssertEqual(raw.reason, reason)
                    XCTAssertEqual(raw.actual_u32, word)
                }
            }
        }
        for bit in 0..<32 {
            let word = UInt32(12) ^ (UInt32(1) << bit)
            let evidence = changed(valid(), 7, UInt64(word))
            try assertParity(evidence)
            XCTAssertEqual(try actualResult(Bridge.encode(evidence)).actual_u32, word)
        }
    }

    func testOutputFormatRateEdgeCasesAndNaNPayloadsMatchOriginalBits() throws {
        let required = Double(48_000).bitPattern
        let bits: [UInt64] = [required, required - 1, required + 1, 0, 1, UInt64(1) << 63,
            Double(44_100).bitPattern, Double(-48_000).bitPattern,
            Double.leastNormalMagnitude.bitPattern, Double.greatestFiniteMagnitude.bitPattern,
            (-Double.greatestFiniteMagnitude).bitPattern, Double.infinity.bitPattern,
            (-Double.infinity).bitPattern, 0x7ff8_0000_0000_0001, 0x7ff0_0000_0000_0001,
            0xfff8_1234_5678_9abc, UInt64.max]
        for reason in [UInt32(5), 14] {
            for rateBits in bits {
                let evidence = changed(valid(), reason, rateBits)
                try assertParity(evidence)
                let raw = try actualResult(Bridge.encode(evidence))
                if rateBits == required { XCTAssertEqual(raw.accepted, 1) }
                else {
                    XCTAssertEqual(raw.reason, reason)
                    XCTAssertEqual(raw.actual_rate_bits, rateBits)
                }
            }
        }
        let first = try actualResult(Bridge.encode(changed(valid(), 5, 0x7ff8_0000_0000_0001)))
        let second = try actualResult(Bridge.encode(changed(valid(), 5, 0x7ff8_0000_0000_0002)))
        XCTAssertNotEqual(first.actual_rate_bits, second.actual_rate_bits)
    }

    func testOutputFormatCopiesAllNativeReadValuesWithoutNormalization() throws {
        var evidence = valid()
        evidence.streamDescriptionStatus = Int32.min
        evidence.deviceSampleRateStatus = Int32.max
        evidence.deviceChannelCountStatus = -50
        evidence.converterErrorReadStatus = -1
        evidence.streamDescription = AudioStreamBasicDescription(mSampleRate: Double(bitPattern: 0x7ff0_0000_0000_0001),
            mFormatID: UInt32.max, mFormatFlags: 0x8000_0000, mBytesPerPacket: 0x0001_0000,
            mFramesPerPacket: 7, mBytesPerFrame: 9, mChannelsPerFrame: 4,
            mBitsPerChannel: 32, mReserved: UInt32.max)
        evidence.deviceSampleRate = Double(bitPattern: 0xfff8_1234_5678_9abc)
        evidence.deviceChannelCount = UInt32.max
        evidence.converterError = 0x8000_0000
        let facts = try Bridge.encode(evidence)
        XCTAssertEqual([facts.stream_description_status, facts.device_sample_rate_status,
            facts.device_channel_count_status, facts.converter_error_read_status], [Int32.min, Int32.max, -50, -1])
        XCTAssertEqual(facts.stream_sample_rate_bits, 0x7ff0_0000_0000_0001)
        XCTAssertEqual(facts.device_sample_rate_bits, 0xfff8_1234_5678_9abc)
        XCTAssertEqual([facts.stream_format_id, facts.stream_format_flags, facts.stream_bytes_per_packet,
            facts.stream_frames_per_packet, facts.stream_bytes_per_frame, facts.stream_channels_per_frame,
            facts.stream_bits_per_channel, facts.stream_reserved, facts.device_channel_count, facts.converter_error],
            [UInt32.max, 0x8000_0000, 0x0001_0000, 7, 9, 4, 32, UInt32.max, UInt32.max, 0x8000_0000])
        try assertParity(evidence)
        _ = try actualResult(facts)
    }

    func testOutputFormatWholeResultRejectsAllTwentyFieldCorruptions() throws {
        var evidenceRows = [valid()]
        evidenceRows += (UInt32(1)...16).map { changed(valid(), $0, badValue($0)) }
        evidenceRows.append(changed(valid(), 5, 0x7ff8_0000_0000_0001))
        for evidence in evidenceRows {
            let facts = try Bridge.encode(evidence)
            for field in 0..<20 {
                var calls = 0
                assertRefused {
                    try Bridge.evaluateRawForTesting(facts: facts) { actualFacts, result in
                        calls += 1
                        self.assertSameFacts(actualFacts, facts)
                        return self.corrupted(result, field)
                    }
                }
                XCTAssertEqual(calls, 1)
            }
        }
    }

    func testOutputFormatWholeResultRejectsCoherentWrongDecision() throws {
        var evidenceRows = [valid()]
        evidenceRows += (UInt32(1)...16).map { changed(valid(), $0, badValue($0)) }
        let factsRows = try evidenceRows.map(Bridge.encode)
        let coherentResults = try factsRows.map(actualResult)
        for (inputIndex, facts) in factsRows.enumerated() {
            for (resultIndex, coherent) in coherentResults.enumerated() where inputIndex != resultIndex {
                assertRefused { try Bridge.evaluateRawForTesting(facts: facts) { _, _ in coherent } }
            }
        }
        let bothBad = changed(changed(valid(), 5, badValue(5)), 14, badValue(14))
        let laterFailure = try actualResult(Bridge.encode(changed(valid(), 14, badValue(14))))
        assertRefused {
            try Bridge.evaluateRawForTesting(facts: Bridge.encode(bothBad)) { _, _ in laterFailure }
        }
    }

    func testOutputFormatMalformedWireThrowsWithoutSwiftFallback() throws {
        for evidence in [valid(), changed(valid(), 1, UInt64(UInt32.max)),
            changed(valid(), 5, 0x7ff8_0000_0000_0001)] {
            let original = try Bridge.encode(evidence)
            let coherent = try actualResult(original)
            var malformed: [Bridge.Facts] = []
            for version in [UInt32(0), 2, UInt32.max] {
                var input = original; input.abi_version = version; malformed.append(input)
            }
            for reserved in [UInt32(1), UInt32.max] {
                var input = original; input.wire_reserved = reserved; malformed.append(input)
            }
            for input in malformed {
                var calls = 0
                assertRefused {
                    try Bridge.evaluateRawForTesting(facts: input) { actualFacts, result in
                        calls += 1
                        self.assertSameFacts(actualFacts, input)
                        XCTAssertEqual(result.status, 0)
                        XCTAssertEqual(result.accepted, 0)
                        XCTAssertEqual(result.reason, 0)
                        return result
                    }
                }
                XCTAssertEqual(calls, 1)
                assertRefused { try Bridge.evaluateRawForTesting(facts: input) { _, _ in coherent } }
            }
        }
    }

    private func valid() -> BlackHoleMicrophoneOutputFormatEvidence {
        FrozenMicrophoneOutputFormatReference.validEvidence
    }

    private func badValue(_ reason: UInt32) -> UInt64 {
        reason == 5 || reason == 14 ? Double(44_100).bitPattern : UInt64(UInt32.max)
    }

    private func changed(_ original: BlackHoleMicrophoneOutputFormatEvidence,
                         _ reason: UInt32, _ bits: UInt64) -> BlackHoleMicrophoneOutputFormatEvidence {
        var value = original
        let word = UInt32(truncatingIfNeeded: bits)
        switch reason {
        case 1: value.streamDescriptionStatus = Int32(bitPattern: word)
        case 2: value.deviceSampleRateStatus = Int32(bitPattern: word)
        case 3: value.deviceChannelCountStatus = Int32(bitPattern: word)
        case 4: value.converterErrorReadStatus = Int32(bitPattern: word)
        case 5: value.streamDescription.mSampleRate = Double(bitPattern: bits)
        case 6: value.streamDescription.mFormatID = word
        case 7: value.streamDescription.mFormatFlags = word
        case 8: value.streamDescription.mBytesPerPacket = word
        case 9: value.streamDescription.mFramesPerPacket = word
        case 10: value.streamDescription.mBytesPerFrame = word
        case 11: value.streamDescription.mChannelsPerFrame = word
        case 12: value.streamDescription.mBitsPerChannel = word
        case 13: value.streamDescription.mReserved = word
        case 14: value.deviceSampleRate = Double(bitPattern: bits)
        case 15: value.deviceChannelCount = word
        case 16: value.converterError = word
        default: XCTFail("Unknown original guard")
        }
        return value
    }

    private func assertParity(_ evidence: BlackHoleMicrophoneOutputFormatEvidence,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = FrozenMicrophoneOutputFormatReference().evaluate(evidence)
        let bridged = try Bridge.evaluate(evidence)
        assertSameDecision(bridged, expected, file: file, line: line)
        assertSameDecision(BlackHoleMicrophoneOutputFormatPolicy().evaluate(evidence), expected, file: file, line: line)
    }

    private func assertSameDecision(
        _ actual: Swift.Result<BlackHoleMicrophoneOutputFormatObservation, BlackHoleMicrophoneOutputFormatRejection>,
        _ expected: Swift.Result<BlackHoleMicrophoneOutputFormatObservation, FrozenMicrophoneOutputFormatRejection>,
        file: StaticString, line: UInt
    ) {
        switch (actual, expected) {
        case let (.success(a), .success(b)):
            XCTAssertEqual(a.sampleRate.bitPattern, b.sampleRate.bitPattern, file: file, line: line)
            XCTAssertEqual(a.deviceSampleRate.bitPattern, b.deviceSampleRate.bitPattern, file: file, line: line)
            XCTAssertEqual([a.formatID, a.formatFlags, a.bytesPerPacket, a.framesPerPacket,
                a.bytesPerFrame, a.channelsPerFrame, a.bitsPerChannel, a.reserved,
                a.deviceChannelCount, a.converterError],
                [b.formatID, b.formatFlags, b.bytesPerPacket, b.framesPerPacket,
                b.bytesPerFrame, b.channelsPerFrame, b.bitsPerChannel, b.reserved,
                b.deviceChannelCount, b.converterError], file: file, line: line)
        case let (.failure(a), .failure(b)):
            XCTAssertEqual(rejectionKey(a), rejectionKey(b), file: file, line: line)
            XCTAssertEqual(a.coreAudioStatus, b.coreAudioStatus, file: file, line: line)
            XCTAssertEqual(a.description, b.description, file: file, line: line)
        default: XCTFail("Original Swift and actual Rust decision differ", file: file, line: line)
        }
    }

    private func rejectionKey(_ value: BlackHoleMicrophoneOutputFormatRejection) -> [UInt64] {
        switch value {
        case .streamDescriptionCoreAudioStatus(let v): return [1, UInt64(UInt32(bitPattern: v))]
        case .deviceSampleRateCoreAudioStatus(let v): return [2, UInt64(UInt32(bitPattern: v))]
        case .deviceChannelCountCoreAudioStatus(let v): return [3, UInt64(UInt32(bitPattern: v))]
        case .converterErrorCoreAudioStatus(let v): return [4, UInt64(UInt32(bitPattern: v))]
        case .unexpectedStreamSampleRate(let v): return [5, v.bitPattern]
        case .unexpectedStreamFormatID(let v): return [6, UInt64(v)]
        case .unexpectedStreamFormatFlags(let v): return [7, UInt64(v)]
        case .unexpectedStreamBytesPerPacket(let v): return [8, UInt64(v)]
        case .unexpectedStreamFramesPerPacket(let v): return [9, UInt64(v)]
        case .unexpectedStreamBytesPerFrame(let v): return [10, UInt64(v)]
        case .unexpectedStreamChannelsPerFrame(let v): return [11, UInt64(v)]
        case .unexpectedStreamBitsPerChannel(let v): return [12, UInt64(v)]
        case .unexpectedStreamReserved(let v): return [13, UInt64(v)]
        case .unexpectedDeviceSampleRate(let v): return [14, v.bitPattern]
        case .unexpectedDeviceChannelCount(let v): return [15, UInt64(v)]
        case .converterError(let v): return [16, UInt64(v)]
        default: return [UInt64.max]
        }
    }

    private func rejectionKey(_ value: FrozenMicrophoneOutputFormatRejection) -> [UInt64] {
        switch value {
        case .streamDescriptionCoreAudioStatus(let v): return [1, UInt64(UInt32(bitPattern: v))]
        case .deviceSampleRateCoreAudioStatus(let v): return [2, UInt64(UInt32(bitPattern: v))]
        case .deviceChannelCountCoreAudioStatus(let v): return [3, UInt64(UInt32(bitPattern: v))]
        case .converterErrorCoreAudioStatus(let v): return [4, UInt64(UInt32(bitPattern: v))]
        case .unexpectedStreamSampleRate(let v): return [5, v.bitPattern]
        case .unexpectedStreamFormatID(let v): return [6, UInt64(v)]
        case .unexpectedStreamFormatFlags(let v): return [7, UInt64(v)]
        case .unexpectedStreamBytesPerPacket(let v): return [8, UInt64(v)]
        case .unexpectedStreamFramesPerPacket(let v): return [9, UInt64(v)]
        case .unexpectedStreamBytesPerFrame(let v): return [10, UInt64(v)]
        case .unexpectedStreamChannelsPerFrame(let v): return [11, UInt64(v)]
        case .unexpectedStreamBitsPerChannel(let v): return [12, UInt64(v)]
        case .unexpectedStreamReserved(let v): return [13, UInt64(v)]
        case .unexpectedDeviceSampleRate(let v): return [14, v.bitPattern]
        case .unexpectedDeviceChannelCount(let v): return [15, UInt64(v)]
        case .converterError(let v): return [16, UInt64(v)]
        }
    }

    private func actualResult(_ facts: Bridge.Facts) throws -> Bridge.RawResult {
        var captured: Bridge.RawResult?
        var calls = 0
        _ = try Bridge.evaluateRawForTesting(facts: facts) { actualFacts, actual in
            calls += 1
            self.assertSameFacts(actualFacts, facts)
            captured = actual
            return actual
        }
        XCTAssertEqual(calls, 1)
        return try XCTUnwrap(captured)
    }

    private func assertSameFacts(_ actual: Bridge.Facts, _ expected: Bridge.Facts) {
        XCTAssertEqual([actual.abi_version, actual.wire_reserved, actual.stream_format_id,
            actual.stream_format_flags, actual.stream_bytes_per_packet, actual.stream_frames_per_packet,
            actual.stream_bytes_per_frame, actual.stream_channels_per_frame, actual.stream_bits_per_channel,
            actual.stream_reserved, actual.device_channel_count, actual.converter_error],
            [expected.abi_version, expected.wire_reserved, expected.stream_format_id,
            expected.stream_format_flags, expected.stream_bytes_per_packet, expected.stream_frames_per_packet,
            expected.stream_bytes_per_frame, expected.stream_channels_per_frame, expected.stream_bits_per_channel,
            expected.stream_reserved, expected.device_channel_count, expected.converter_error])
        XCTAssertEqual([actual.stream_description_status, actual.device_sample_rate_status,
            actual.device_channel_count_status, actual.converter_error_read_status],
            [expected.stream_description_status, expected.device_sample_rate_status,
            expected.device_channel_count_status, expected.converter_error_read_status])
        XCTAssertEqual(actual.stream_sample_rate_bits, expected.stream_sample_rate_bits)
        XCTAssertEqual(actual.device_sample_rate_bits, expected.device_sample_rate_bits)
    }

    private func assertZeroObservation(_ value: Bridge.RawObservation) {
        XCTAssertEqual(value.sample_rate_bits, 0)
        XCTAssertEqual(value.device_sample_rate_bits, 0)
        XCTAssertEqual([value.format_id, value.format_flags, value.bytes_per_packet, value.frames_per_packet,
            value.bytes_per_frame, value.channels_per_frame, value.bits_per_channel, value.stream_reserved,
            value.device_channel_count, value.converter_error], Array(repeating: UInt32(0), count: 10))
    }

    private func corrupted(_ original: Bridge.RawResult, _ field: Int) -> Bridge.RawResult {
        var value = original
        switch field {
        case 0: value.abi_version ^= 1
        case 1: value.status ^= 1
        case 2: value.accepted ^= 1
        case 3: value.reason ^= 1
        case 4: value.actual_core_audio_status ^= 1
        case 5: value.actual_u32 ^= 1
        case 6: value.actual_rate_bits ^= 1
        case 7: value.observation.sample_rate_bits ^= 1
        case 8: value.observation.format_id ^= 1
        case 9: value.observation.format_flags ^= 1
        case 10: value.observation.bytes_per_packet ^= 1
        case 11: value.observation.frames_per_packet ^= 1
        case 12: value.observation.bytes_per_frame ^= 1
        case 13: value.observation.channels_per_frame ^= 1
        case 14: value.observation.bits_per_channel ^= 1
        case 15: value.observation.stream_reserved ^= 1
        case 16: value.observation.device_sample_rate_bits ^= 1
        case 17: value.observation.device_channel_count ^= 1
        case 18: value.observation.converter_error ^= 1
        case 19: value.wire_reserved ^= 1
        default: XCTFail("Unknown result field")
        }
        return value
    }

    private func assertRefused<T>(_ body: () throws -> T,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? Bridge.Failure, .refused, file: file, line: line)
        }
    }
}
#endif
