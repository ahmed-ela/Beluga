// PRIVATE authored actual-C-first coverage; no native stream or platform IO is exercised.
import Foundation
import XCTest
import BelugaCore
@testable import CaptureCore

final class ScreenVideoOutputDimensionsRustTests: XCTestCase {
    private typealias B = BelugaRustOutputDimensionsBoundary
    private typealias Producer = BelugaRustOutputDimensionsProducer

    func testActualCOutputHasTwoExactLayoutsAndAllTwelveOffsets() {
        let actual = beluga_core_output_dimensions(input(4, 7, 2))
        assertOutput(actual, decision: 1, width: 2, height: 4, rounded: 4)
        XCTAssertEqual(MemoryLayout<B.Input>.size, 32)
        XCTAssertEqual(MemoryLayout<B.Input>.stride, 32)
        XCTAssertEqual(MemoryLayout<B.Input>.alignment, 8)
        XCTAssertEqual(MemoryLayout<B.Output>.size, 40)
        XCTAssertEqual(MemoryLayout<B.Output>.stride, 40)
        XCTAssertEqual(MemoryLayout<B.Output>.alignment, 8)
        XCTAssertEqual(MemoryLayout<B.Input>.offset(of: \B.Input.abi_version), 0)
        XCTAssertEqual(MemoryLayout<B.Input>.offset(of: \B.Input.reserved), 4)
        XCTAssertEqual(MemoryLayout<B.Input>.offset(of: \B.Input.source_width), 8)
        XCTAssertEqual(MemoryLayout<B.Input>.offset(of: \B.Input.source_height), 16)
        XCTAssertEqual(MemoryLayout<B.Input>.offset(of: \B.Input.maximum_width), 24)
        XCTAssertEqual(MemoryLayout<B.Output>.offset(of: \B.Output.abi_version), 0)
        XCTAssertEqual(MemoryLayout<B.Output>.offset(of: \B.Output.status), 4)
        XCTAssertEqual(MemoryLayout<B.Output>.offset(of: \B.Output.decision), 8)
        XCTAssertEqual(MemoryLayout<B.Output>.offset(of: \B.Output.reserved), 12)
        XCTAssertEqual(MemoryLayout<B.Output>.offset(of: \B.Output.width), 16)
        XCTAssertEqual(MemoryLayout<B.Output>.offset(of: \B.Output.height), 24)
        XCTAssertEqual(MemoryLayout<B.Output>.offset(of: \B.Output.rounded_height_bits), 32)
        XCTAssertTrue(B.layoutIsExact)
    }

    func testActualCAndTypedOutputMatchIndependentLiteralModesAndFrozenOriginal() throws {
        let cases: [(Int, Int, Int, Int, Int, Double)] = [
            (1_206, 2_622, 1_920, 1_206, 2_622, 2_622),
            (3_840, 2_160, 1_920, 1_920, 1_080, 1_080),
            (1_205, 2_621, 1_920, 1_204, 2_618, 2_619),
            (603, 1_312, 1_920, 602, 1_310, 1_310),
            (7, 11, 5, 4, 6, 6), (4, 7, 2, 2, 4, 4), (4, 5, 2, 2, 2, 3),
            (100, 99, 20, 20, 20, 20), (100, 91, 20, 20, 18, 18),
            (100, 96, 20, 20, 18, 19), (100, 11, 2, 2, 2, 0),
        ]
        for (sw, sh, cap, width, height, rounded) in cases {
            let facts = input(sw, sh, cap)
            let actual = beluga_core_output_dimensions(facts)
            assertOutput(actual, decision: 1, width: width, height: height, rounded: rounded)
            XCTAssertTrue(B.accepts(facts, actual))
            let source = ScreenVideoPixelDimensions(width: sw, height: sh)
            let typed = try ScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: cap)
            let reference = try FrozenScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: cap)
            XCTAssertEqual(typed, .init(width: width, height: height))
            XCTAssertEqual(typed, reference)
            XCTAssertEqual(actual.rounded_height_bits,
                try FrozenScreenVideoOutputPrefix.roundedHeightBits(source: source, maximumWidth: cap))
        }
    }

    func testRepresentableSignedMatrixMatchesFrozenOriginalWithoutNewCaps() throws {
        let widths = [2, 3, 4, 5, 7, 100, 603, 1_205, 32_769, 65_538, 4_294_967_298, Int.max]
        let heights = [2, 3, 5, 7, 11, 99, 1_312, 32_769, 4_294_967_297]
        let caps = [2, 3, 5, 200, 1_920, 65_538, 4_294_967_298, Int.max]
        for width in widths {
            for height in heights {
                for cap in caps {
                    let source = ScreenVideoPixelDimensions(width: width, height: height)
                    let facts = input(width, height, cap)
                    let raw = beluga_core_output_dimensions(facts)
                    let referenceBits = try FrozenScreenVideoOutputPrefix.roundedHeightBits(source: source, maximumWidth: cap)
                    XCTAssertEqual(raw.abi_version, 1)
                    XCTAssertEqual(raw.status, 1)
                    XCTAssertEqual(raw.decision, 1)
                    XCTAssertEqual(raw.reserved, 0)
                    XCTAssertEqual(raw.rounded_height_bits, referenceBits)
                    XCTAssertTrue(B.accepts(facts, raw))
                    let actual = try ScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: cap)
                    let frozen = try FrozenScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: cap)
                    XCTAssertEqual(raw.width, Int64(frozen.width))
                    XCTAssertEqual(raw.height, Int64(frozen.height))
                    XCTAssertEqual(actual, frozen)
                }
            }
        }
    }

    func testEachInvalidSignedSlotKeepsOriginalErrorAndCanonicalNoArithmeticPayload() {
        for bad in [Int.min, -4_294_967_296, -1, 0, 1] {
            for slot in 0..<3 {
                var values = [2, 2, 2]
                values[slot] = bad
                let facts = input(values[0], values[1], values[2])
                let actual = beluga_core_output_dimensions(facts)
                assertOutput(actual, decision: 0, width: 0, height: 0, rounded: 0)
                XCTAssertTrue(B.accepts(facts, actual))
                XCTAssertThrowsError(try ScreenVideoOutputPolicy.outputDimensions(
                    source: .init(width: values[0], height: values[1]), maximumWidth: values[2])) {
                    XCTAssertEqual($0 as? ScreenVideoOutputPolicyError, .invalidDimensions)
                }
                XCTAssertThrowsError(try FrozenScreenVideoOutputPolicy.outputDimensions(
                    source: .init(width: values[0], height: values[1]), maximumWidth: values[2])) {
                    XCTAssertEqual($0 as? ScreenVideoOutputPolicyError, .invalidDimensions)
                }
            }
        }
        XCTAssertEqual(ScreenVideoOutputPolicyError.invalidDimensions.errorDescription,
            "Screen video source and maximum dimensions must be at least two pixels")
    }

    func testNearestPositiveTiesAndMinimumHeightRemainOriginal() throws {
        let cases = [(4, 7, 2, 4), (4, 5, 2, 2), (400, 699, 200, 350),
                     (100, 11, 2, 2), (100, 26, 2, 2), (Int.max, 2, 2, 2)]
        for (sw, sh, cap, expectedHeight) in cases {
            let source = ScreenVideoPixelDimensions(width: sw, height: sh)
            let facts = input(sw, sh, cap)
            let raw = beluga_core_output_dimensions(facts)
            XCTAssertEqual(raw.abi_version, 1)
            XCTAssertEqual(raw.status, 1)
            XCTAssertEqual(raw.decision, 1)
            XCTAssertEqual(raw.reserved, 0)
            XCTAssertEqual(raw.height, Int64(expectedHeight))
            XCTAssertEqual(raw.rounded_height_bits,
                try FrozenScreenVideoOutputPrefix.roundedHeightBits(source: source, maximumWidth: cap))
            XCTAssertTrue(B.accepts(facts, raw))
            let actual = try ScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: cap)
            let frozen = try FrozenScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: cap)
            XCTAssertEqual(raw.width, Int64(frozen.width))
            XCTAssertEqual(actual.height, expectedHeight)
            XCTAssertEqual(actual, frozen)
        }
    }

    func testOriginalFloatingPrecisionLossAndRepresentableUpperNeighborRemainExact() throws {
        let cases = [
            (9_007_199_254_740_993, 9_007_199_254_740_992),
            (9_007_199_254_740_995, 9_007_199_254_740_996),
            (Int.max - 1024, 9_223_372_036_854_774_784),
            (Int.max - 512, 9_223_372_036_854_774_784),
            (Int.max - 1023, 9_223_372_036_854_774_784),
        ]
        for (sourceHeight, expectedHeight) in cases {
            let source = ScreenVideoPixelDimensions(width: 2, height: sourceHeight)
            let facts = input(2, sourceHeight, 2)
            let raw = beluga_core_output_dimensions(facts)
            assertOutput(raw, decision: 1, width: 2, height: expectedHeight, rounded: Double(expectedHeight))
            XCTAssertEqual(raw.rounded_height_bits,
                try FrozenScreenVideoOutputPrefix.roundedHeightBits(source: source, maximumWidth: 2))
            XCTAssertTrue(B.accepts(facts, raw))
            let actual = try ScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: 2)
            let frozen = try FrozenScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: 2)
            XCTAssertEqual(actual, .init(width: 2, height: expectedHeight))
            XCTAssertEqual(actual, frozen)
        }
    }

    func testFormerTwoToSixtyThreeConversionTrapIsDistinctTypedErrorNotDimensions() throws {
        for source in [ScreenVideoPixelDimensions(width: 2, height: Int.max),
                       .init(width: 2, height: Int.max - 511),
                       .init(width: Int.max, height: Int.max)] {
            let cap = source.width
            let facts = input(source.width, source.height, cap)
            let actual = beluga_core_output_dimensions(facts)
            XCTAssertEqual(actual.abi_version, 1)
            XCTAssertEqual(actual.status, 1)
            XCTAssertEqual(actual.decision, 2)
            XCTAssertEqual(actual.reserved, 0)
            XCTAssertEqual(actual.width, source.width == 2 ? 2 : Int64(Int.max - 1))
            XCTAssertEqual(actual.height, 0)
            XCTAssertEqual(actual.rounded_height_bits, 0x43e0_0000_0000_0000)
            XCTAssertTrue(B.accepts(facts, actual))
            // The frozen full reference would trap: only its independent prefix is called here.
            XCTAssertEqual(actual.rounded_height_bits,
                try FrozenScreenVideoOutputPrefix.roundedHeightBits(source: source, maximumWidth: cap))
            XCTAssertThrowsError(try ScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: cap)) {
                XCTAssertEqual($0 as? ScreenVideoOutputPolicyError, .unrepresentableScaledHeight)
                XCTAssertNotEqual($0 as? ScreenVideoOutputPolicyError, .invalidDimensions)
            }
        }
    }

    func testMaximumSignedHeightCanRemainRepresentableAfterWidthCapping() throws {
        let source = ScreenVideoPixelDimensions(width: 3, height: Int.max)
        let facts = input(3, Int.max, 2)
        let actual = beluga_core_output_dimensions(facts)
        XCTAssertEqual(actual.abi_version, 1)
        XCTAssertEqual(actual.status, 1)
        XCTAssertEqual(actual.decision, 1)
        XCTAssertEqual(actual.reserved, 0)
        XCTAssertEqual(actual.width, 2)
        XCTAssertEqual(actual.height, 6_148_914_691_236_516_864)
        XCTAssertEqual(actual.rounded_height_bits, 0x43d5_5555_5555_5555)
        XCTAssertTrue(B.accepts(facts, actual))
        let typed = try ScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: 2)
        let frozen = try FrozenScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: 2)
        XCTAssertEqual(typed, .init(width: 2, height: 6_148_914_691_236_516_864))
        XCTAssertEqual(typed, frozen)
        XCTAssertEqual(actual.rounded_height_bits,
            try FrozenScreenVideoOutputPrefix.roundedHeightBits(source: source, maximumWidth: 2))
    }

    func testTypedFacadeRecordsFullSignedInputWordsOnlyAfterActualC() throws {
        let domain: [(Int, Int, Int)] = [
            (Int.min, Int.max, -1), (2, 2, 2), (65_538, 6, 2),
            (4_294_967_298, 6, 2), (2, 4_294_967_297, 2),
            (8, 16, 4_294_967_298), (Int.max, 2, Int.max), (2, Int.max, 2),
        ]
        for (width, height, cap) in domain {
            let recorder = OutputInputRecorder()
            let producer = Producer(output: { facts in
                let actual = beluga_core_output_dimensions(facts)
                recorder.append([UInt64(facts.abi_version), UInt64(facts.reserved),
                    UInt64(bitPattern: facts.source_width), UInt64(bitPattern: facts.source_height),
                    UInt64(bitPattern: facts.maximum_width)])
                return actual
            })
            let source = ScreenVideoPixelDimensions(width: width, height: height)
            do {
                _ = try ScreenVideoOutputPolicy.outputDimensions(source: source, maximumWidth: cap, producer: producer)
            } catch {
                XCTAssertTrue(error is ScreenVideoOutputPolicyError)
                XCTAssertFalse(error is ScreenVideoOutputDimensionsBridgeError)
            }
            XCTAssertEqual(recorder.snapshot(), [[1, 0, UInt64(bitPattern: Int64(width)),
                UInt64(bitPattern: Int64(height)), UInt64(bitPattern: Int64(cap))]])
        }
    }

    func testMalformedRawInputEnvelopeIsRefusedWithoutLegitimateOutcome() {
        for bad in [UInt32(0), 2, 0x8000_0001, .max] {
            var facts = input(2, 2, 2)
            facts.abi_version = bad
            let actual = beluga_core_output_dimensions(facts)
            XCTAssertEqual(actual.status, 0)
            XCTAssertEqual(actual.decision, 0)
            XCTAssertEqual(actual.width, 0)
            XCTAssertEqual(actual.height, 0)
            XCTAssertEqual(actual.rounded_height_bits, 0)
            XCTAssertFalse(B.accepts(facts, actual))
        }
        for bad in [UInt32(1), 2, 0x8000_0000, .max] {
            var facts = input(2, 2, 2)
            facts.reserved = bad
            let actual = beluga_core_output_dimensions(facts)
            XCTAssertEqual(actual.status, 0)
            XCTAssertFalse(B.accepts(facts, actual))
        }
    }

    func testEveryCopiedResultFieldCorruptionThrowsBridgeErrorAfterActualC() {
        let mutations: [@Sendable (inout B.Output) -> Void] = [
            { $0.abi_version = 0 }, { $0.abi_version = .max },
            { $0.status = 0 }, { $0.status = 2 }, { $0.status = .max },
            { $0.decision = 0 }, { $0.decision = 2 }, { $0.decision = .max },
            { $0.reserved = 1 }, { $0.width += 2 }, { $0.height += 2 },
            { $0.rounded_height_bits ^= 1 }, { $0.rounded_height_bits = 0x7ff8_1234_5678_9abc },
            { $0.rounded_height_bits = Double.infinity.bitPattern },
            { $0.rounded_height_bits = (-Double.infinity).bitPattern },
        ]
        for mutate in mutations {
            let producer = Producer(output: { facts in
                var actual = beluga_core_output_dimensions(facts)
                mutate(&actual)
                return actual
            })
            XCTAssertThrowsError(try ScreenVideoOutputPolicy.outputDimensions(
                source: .init(width: 4, height: 7), maximumWidth: 2, producer: producer)) {
                XCTAssertEqual($0 as? ScreenVideoOutputDimensionsBridgeError, .invalidBridge)
            }
        }
    }

    func testInvalidAndOutOfRangeResultsCannotForgeDimensionsOrOtherErrors() {
        let invalidSource = ScreenVideoPixelDimensions(width: 1, height: Int.max)
        let invalidMutations: [@Sendable (inout B.Output) -> Void] = [
            { $0.decision = 1 }, { $0.decision = 2 }, { $0.width = 2 },
            { $0.height = 2 }, { $0.rounded_height_bits = 1 },
        ]
        for mutate in invalidMutations {
            XCTAssertThrowsError(try ScreenVideoOutputPolicy.outputDimensions(
                source: invalidSource, maximumWidth: 2, producer: corrupting(mutate))) {
                XCTAssertEqual($0 as? ScreenVideoOutputDimensionsBridgeError, .invalidBridge)
            }
        }
        let trapMutations: [@Sendable (inout B.Output) -> Void] = [
            { $0.decision = 0 }, { $0.decision = 1 }, { $0.width = 0 },
            { $0.height = Int64.max - 1 }, { $0.rounded_height_bits = 0 },
            { $0.rounded_height_bits = 0x43df_ffff_ffff_ffff },
        ]
        for mutate in trapMutations {
            XCTAssertThrowsError(try ScreenVideoOutputPolicy.outputDimensions(
                source: .init(width: 2, height: Int.max), maximumWidth: 2, producer: corrupting(mutate))) {
                XCTAssertEqual($0 as? ScreenVideoOutputDimensionsBridgeError, .invalidBridge)
            }
        }
    }

    func testRoundedPositiveZeroCannotBeSilentlyNormalizedToNegativeZero() {
        let facts = input(100, 11, 2)
        let actual = beluga_core_output_dimensions(facts)
        XCTAssertEqual(actual.rounded_height_bits, 0)
        XCTAssertTrue(B.accepts(facts, actual))
        let producer = corrupting { $0.rounded_height_bits = 0x8000_0000_0000_0000 }
        XCTAssertThrowsError(try ScreenVideoOutputPolicy.outputDimensions(
            source: .init(width: 100, height: 11), maximumWidth: 2, producer: producer)) {
            XCTAssertEqual($0 as? ScreenVideoOutputDimensionsBridgeError, .invalidBridge)
        }
    }

    private func input(_ width: Int, _ height: Int, _ cap: Int) -> B.Input {
        var facts = B.Input()
        facts.abi_version = 1
        facts.source_width = Int64(width)
        facts.source_height = Int64(height)
        facts.maximum_width = Int64(cap)
        return facts
    }

    private func assertOutput(_ output: B.Output, decision: UInt32, width: Int,
                              height: Int, rounded: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(output.abi_version, 1, file: file, line: line)
        XCTAssertEqual(output.status, 1, file: file, line: line)
        XCTAssertEqual(output.decision, decision, file: file, line: line)
        XCTAssertEqual(output.reserved, 0, file: file, line: line)
        XCTAssertEqual(output.width, Int64(width), file: file, line: line)
        XCTAssertEqual(output.height, Int64(height), file: file, line: line)
        XCTAssertEqual(output.rounded_height_bits, rounded.bitPattern, file: file, line: line)
    }

    private func corrupting(_ mutate: @escaping @Sendable (inout B.Output) -> Void) -> Producer {
        Producer(output: { facts in
            var actual = beluga_core_output_dimensions(facts)
            mutate(&actual)
            return actual
        })
    }
}

private final class OutputInputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [[UInt64]] = []
    func append(_ record: [UInt64]) { lock.lock(); defer { lock.unlock() }; records.append(record) }
    func snapshot() -> [[UInt64]] { lock.lock(); defer { lock.unlock() }; return records }
}
