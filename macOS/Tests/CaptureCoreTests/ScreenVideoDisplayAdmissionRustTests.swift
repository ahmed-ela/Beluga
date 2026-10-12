// PRIVATE authored regression draft; no physical/native stream is started by these tests.
import XCTest
import Foundation
import BelugaCore
@testable import CaptureCore

final class ScreenVideoDisplayAdmissionRustTests: XCTestCase {
    private typealias B = BelugaRustDisplayAdmissionBoundary
    private typealias Producer = BelugaRustDisplayAdmissionProducer

    func testCopiedABIHasSevenExactLayoutsAndAllFiftyTwoOffsets() {
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.size, 64)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.stride, 64)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.alignment, 8)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.abi_version), 0)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.reserved), 4)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.required_vendor_id), 8)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.required_product_id), 12)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.required_serial_number), 16)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.requires_sole_main_display), 20)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.display_id), 24)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.observed_vendor_id), 28)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.observed_product_id), 32)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.observed_serial_number), 36)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.is_online), 40)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.is_active), 44)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.main_display_id), 48)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.sole_online_display_id), 52)
        XCTAssertEqual(MemoryLayout<B.RequirementInput>.offset(of: \B.RequirementInput.online_display_count), 56)
        XCTAssertEqual(MemoryLayout<B.BooleanOutput>.size, 16)
        XCTAssertEqual(MemoryLayout<B.BooleanOutput>.stride, 16)
        XCTAssertEqual(MemoryLayout<B.BooleanOutput>.alignment, 4)
        XCTAssertEqual(MemoryLayout<B.BooleanOutput>.offset(of: \B.BooleanOutput.abi_version), 0)
        XCTAssertEqual(MemoryLayout<B.BooleanOutput>.offset(of: \B.BooleanOutput.status), 4)
        XCTAssertEqual(MemoryLayout<B.BooleanOutput>.offset(of: \B.BooleanOutput.value), 8)
        XCTAssertEqual(MemoryLayout<B.BooleanOutput>.offset(of: \B.BooleanOutput.reserved), 12)
        XCTAssertEqual(MemoryLayout<B.KindInput>.size, 16)
        XCTAssertEqual(MemoryLayout<B.KindInput>.stride, 16)
        XCTAssertEqual(MemoryLayout<B.KindInput>.alignment, 4)
        XCTAssertEqual(MemoryLayout<B.KindInput>.offset(of: \B.KindInput.abi_version), 0)
        XCTAssertEqual(MemoryLayout<B.KindInput>.offset(of: \B.KindInput.reserved), 4)
        XCTAssertEqual(MemoryLayout<B.KindInput>.offset(of: \B.KindInput.vendor_id), 8)
        XCTAssertEqual(MemoryLayout<B.KindInput>.offset(of: \B.KindInput.product_id), 12)
        XCTAssertEqual(MemoryLayout<B.KindOutput>.size, 16)
        XCTAssertEqual(MemoryLayout<B.KindOutput>.stride, 16)
        XCTAssertEqual(MemoryLayout<B.KindOutput>.alignment, 4)
        XCTAssertEqual(MemoryLayout<B.KindOutput>.offset(of: \B.KindOutput.abi_version), 0)
        XCTAssertEqual(MemoryLayout<B.KindOutput>.offset(of: \B.KindOutput.status), 4)
        XCTAssertEqual(MemoryLayout<B.KindOutput>.offset(of: \B.KindOutput.kind), 8)
        XCTAssertEqual(MemoryLayout<B.KindOutput>.offset(of: \B.KindOutput.reserved), 12)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.size, 88)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.stride, 88)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.alignment, 8)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.abi_version), 0)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.reserved), 4)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.vendor_id), 8)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.product_id), 12)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.logical_width), 16)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.logical_height), 24)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.core_graphics_logical_width), 32)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.core_graphics_logical_height), 40)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.core_graphics_pixel_width), 48)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.core_graphics_pixel_height), 56)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.filter_content_width), 64)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.filter_content_height), 72)
        XCTAssertEqual(MemoryLayout<B.SourceInput>.offset(of: \B.SourceInput.point_pixel_scale), 80)
        XCTAssertEqual(MemoryLayout<B.SourceOutput>.size, 32)
        XCTAssertEqual(MemoryLayout<B.SourceOutput>.stride, 32)
        XCTAssertEqual(MemoryLayout<B.SourceOutput>.alignment, 8)
        XCTAssertEqual(MemoryLayout<B.SourceOutput>.offset(of: \B.SourceOutput.abi_version), 0)
        XCTAssertEqual(MemoryLayout<B.SourceOutput>.offset(of: \B.SourceOutput.status), 4)
        XCTAssertEqual(MemoryLayout<B.SourceOutput>.offset(of: \B.SourceOutput.kind), 8)
        XCTAssertEqual(MemoryLayout<B.SourceOutput>.offset(of: \B.SourceOutput.has_dimensions), 12)
        XCTAssertEqual(MemoryLayout<B.SourceOutput>.offset(of: \B.SourceOutput.width), 16)
        XCTAssertEqual(MemoryLayout<B.SourceOutput>.offset(of: \B.SourceOutput.height), 24)
        XCTAssertEqual(MemoryLayout<B.StabilityInput>.size, 40)
        XCTAssertEqual(MemoryLayout<B.StabilityInput>.stride, 40)
        XCTAssertEqual(MemoryLayout<B.StabilityInput>.alignment, 8)
        XCTAssertEqual(MemoryLayout<B.StabilityInput>.offset(of: \B.StabilityInput.abi_version), 0)
        XCTAssertEqual(MemoryLayout<B.StabilityInput>.offset(of: \B.StabilityInput.reserved), 4)
        XCTAssertEqual(MemoryLayout<B.StabilityInput>.offset(of: \B.StabilityInput.before_width), 8)
        XCTAssertEqual(MemoryLayout<B.StabilityInput>.offset(of: \B.StabilityInput.before_height), 16)
        XCTAssertEqual(MemoryLayout<B.StabilityInput>.offset(of: \B.StabilityInput.after_width), 24)
        XCTAssertEqual(MemoryLayout<B.StabilityInput>.offset(of: \B.StabilityInput.after_height), 32)
        XCTAssertTrue(B.layoutIsExact)
        let requirement = requirementInput()
        let requirementOutput = beluga_core_display_requirement_admission(requirement)
        XCTAssertTrue(B.acceptsRequirement(requirement, requirementOutput))
        let kind = kindInput()
        let kindOutput = beluga_core_source_dimension_kind(kind)
        XCTAssertTrue(B.acceptsKind(kind, kindOutput))
        let source = sourceInput()
        let sourceOutput = beluga_core_source_dimensions(source)
        XCTAssertTrue(B.acceptsSource(source, sourceOutput))
        let stable = stabilityInput()
        let stableOutput = beluga_core_source_dimensions_stable(stable)
        XCTAssertTrue(B.acceptsStability(stable, stableOutput))
    }

    func testDisplayRequirementActualCMatchesFrozenIdentityAndExactTopology() throws {
        let ids: [[UInt32]] = [[], [42], [99], [42, 99], [99, 42], [42, 42]]
        for sole in [false, true] {
            for online in [false, true] {
                for active in [false, true] {
                    for matchingVendor in [false, true] {
                        for matchingProduct in [false, true] {
                            for matchingSerial in [false, true] {
                                for main in [UInt32(42), 99] {
                                    for list in ids {
                                        let requirement = ScreenVideoDisplayRequirement(
                                            vendorID: 0x6F73, productID: 0x1718,
                                            serialNumber: 1, requiresSoleMainDisplay: sole
                                        )
                                        let snapshot = ScreenVideoDisplaySnapshot(
                                            displayID: 42, vendorID: matchingVendor ? 0x6F73 : 0xFFFF,
                                            productID: matchingProduct ? 0x1718 : 0x1717,
                                            serialNumber: matchingSerial ? 1 : 2,
                                            isOnline: online, isActive: active,
                                            mainDisplayID: main, onlineDisplayIDs: list
                                        )
                                        // The adapter invokes the real C export before the reference.
                                        let actual = try ScreenVideoDisplayRequirementPolicy.isSatisfied(
                                            requirement, by: snapshot
                                        )
                                        let frozen = FrozenDisplayRequirementPolicy.isSatisfied(
                                            requirement, by: snapshot
                                        )
                                        XCTAssertEqual(actual, frozen)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        for value in [UInt32(0), .max] {
            let requirement = ScreenVideoDisplayRequirement(
                vendorID: value, productID: value, serialNumber: value,
                requiresSoleMainDisplay: true
            )
            let snapshot = ScreenVideoDisplaySnapshot(
                displayID: value, vendorID: value, productID: value, serialNumber: value,
                isOnline: true, isActive: true, mainDisplayID: value,
                onlineDisplayIDs: [value]
            )
            XCTAssertTrue(try ScreenVideoDisplayRequirementPolicy.isSatisfied(requirement, by: snapshot))
            XCTAssertTrue(FrozenDisplayRequirementPolicy.isSatisfied(requirement, by: snapshot))
        }
    }

    func testRawTopologyPreservesU64CountAndIgnoresAbsentSingletonOnlyWhenOptional() {
        for count in [UInt64(0), 1, 2, 0x0000_0001_0000_0001, .max] {
            for singleton in [UInt32(0), 42, .max] {
                var input = requirementInput()
                input.online_display_count = count
                input.sole_online_display_id = singleton
                let actual = beluga_core_display_requirement_admission(input)
                assertBoolean(actual, status: 1, value: count == 1 && singleton == 42 ? 1 : 0)
                XCTAssertTrue(B.acceptsRequirement(input, actual))
                input.requires_sole_main_display = 0
                input.main_display_id = .max
                let optional = beluga_core_display_requirement_admission(input)
                assertBoolean(optional, status: 1, value: 1)
                XCTAssertTrue(B.acceptsRequirement(input, optional))
            }
        }
        for bad in [UInt32(2), 3, .max] {
            for field in [0, 1, 2] {
                var input = requirementInput()
                switch field {
                case 0: input.requires_sole_main_display = bad
                case 1: input.is_online = bad
                default: input.is_active = bad
                }
                let actual = beluga_core_display_requirement_admission(input)
                assertBoolean(actual, status: 0, value: 0)
                XCTAssertFalse(B.acceptsRequirement(input, actual))
            }
        }
    }

    func testDimensionKindActualCMatchesFrozenIdentityWithoutIDNormalization() throws {
        for vendor in [UInt32(0), 0x610, 0x6F72, 0x6F73, 0x6F74, 0xFFFF, .max] {
            for product in [UInt32(0), 0x1716, 0x1717, 0x1718, 0x1719, 0xA0E1, .max] {
                let actual = try ScreenVideoSourceDimensionPolicy.dimensionKind(
                    vendorID: vendor, productID: product
                )
                let frozen = FrozenSourceDimensionPolicy.dimensionKind(vendorID: vendor, productID: product)
                XCTAssertEqual(actual, frozen)
            }
        }
    }

    func testOrdinarySourceActualCPreservesSignedEndpointsAndIrrelevantNaNs() throws {
        let domain = [Int.min, -1, 0, 1, 2, 32_768, 32_769, Int.max]
        let metadata = [Double(bitPattern: 0x7ff8_1234_5678_9abc), -.infinity,
                        .infinity, -0.0, 0.0, 4.1]
        let vendorProducts: [(UInt32, UInt32)] = [(0x610, 0xA0E1), (0xFFFF, 0x1717), (0x6F73, 0x1719)]
        for vendorProduct in vendorProducts {
            for width in domain {
                for height in domain {
                    for ignored in metadata {
                        var input = sourceInput()
                        input.vendor_id = vendorProduct.0
                        input.product_id = vendorProduct.1
                        input.logical_width = Int64(width)
                        input.logical_height = Int64(height)
                        input.core_graphics_logical_width = .min
                        input.core_graphics_logical_height = .max
                        input.core_graphics_pixel_width = 0
                        input.core_graphics_pixel_height = -1
                        input.filter_content_width = ignored
                        input.filter_content_height = ignored
                        input.point_pixel_scale = ignored
                        let actual = try source(input)
                        let frozen = frozenSource(input)
                        let literal = ScreenVideoPixelDimensions(width: width, height: height)
                        XCTAssertEqual(actual, literal)
                        XCTAssertEqual(frozen, literal)
                    }
                }
            }
        }
    }

    func testOwnedSourceActualCMatchesFrozenAdjacentFloatAndIntegerBoundaries() throws {
        var inputs: [B.SourceInput] = [sourceInput()]
        for field in [0, 1, 2, 3] {
            for value in [Int64.min, -1, 0, 1, 2, 32_768, 32_769, .max] {
                var input = sourceInput()
                switch field {
                case 0:
                    input.logical_width = value
                    input.core_graphics_logical_width = value
                    input.filter_content_width = Double(value)
                case 1:
                    input.logical_height = value
                    input.core_graphics_logical_height = value
                    input.filter_content_height = Double(value)
                case 2: input.core_graphics_pixel_width = value
                default: input.core_graphics_pixel_height = value
                }
                inputs.append(input)
            }
        }
        for value in [Double.nan, -.infinity, .infinity, 539.5.nextDown, 539.5,
                      539.5.nextUp, 540.5.nextDown, 540.5, 540.5.nextUp] {
            var input = sourceInput(); input.filter_content_width = value; inputs.append(input)
        }
        for value in [Double.nan, -.infinity, .infinity, 1_169.5.nextDown, 1_169.5,
                      1_169.5.nextUp, 1_170.5.nextDown, 1_170.5, 1_170.5.nextUp] {
            var input = sourceInput(); input.filter_content_height = value; inputs.append(input)
        }
        for value in [Double.nan, -.infinity, .infinity, -0.0, 0.0, 1.0.nextDown,
                      1.0, 1.0.nextUp, 4.0.nextDown, 4.0, 4.0.nextUp] {
            var input = sourceInput(); input.point_pixel_scale = value; inputs.append(input)
        }
        var wrongWidth = sourceInput(); wrongWidth.core_graphics_logical_width += 1
        var wrongHeight = sourceInput(); wrongHeight.core_graphics_logical_height += 1
        inputs += [wrongWidth, wrongHeight]
        for input in inputs {
            let actual = try source(input)
            let frozen = frozenSource(input)
            XCTAssertEqual(actual, frozen)
        }
        for scale in [1.0, 2.0, 4.0] {
            var input = sourceInput()
            input.point_pixel_scale = scale
            input.core_graphics_pixel_width = 603
            input.core_graphics_pixel_height = 1_311
            let actual = try source(input)
            XCTAssertEqual(actual, .init(width: 603, height: 1_311))
            XCTAssertEqual(frozenSource(input), .init(width: 603, height: 1_311))
        }
        var exact = sourceInput()
        exact.filter_content_width = 539.5; exact.filter_content_height = 1_170.5
        XCTAssertEqual(try source(exact), .init(width: 1_080, height: 2_340))
        exact.filter_content_width = 539.5.nextDown
        XCTAssertNil(try source(exact))
        exact = sourceInput(); exact.point_pixel_scale = 4.0.nextUp
        XCTAssertNil(try source(exact))
    }

    func testLegitimateOwnedAbsenceIsNilWhileMalformedBridgeThrows() throws {
        var input = sourceInput(); input.filter_content_width = .nan
        let output = beluga_core_source_dimensions(input)
        XCTAssertEqual(output.abi_version, 1)
        XCTAssertEqual(output.status, 1)
        XCTAssertEqual(output.kind, 1)
        XCTAssertEqual(output.has_dimensions, 0)
        XCTAssertEqual(output.width, 0); XCTAssertEqual(output.height, 0)
        XCTAssertTrue(B.acceptsSource(input, output))
        XCTAssertNil(try source(input))
        XCTAssertNil(frozenSource(input))
        let bad = Producer(
            requirement: Producer.actual.requirement, kind: Producer.actual.kind,
            source: { raw in
                var copied = beluga_core_source_dimensions(raw)
                copied.status = 0
                return copied
            }, stability: Producer.actual.stability
        )
        XCTAssertThrowsError(try source(input, producer: bad)) {
            XCTAssertEqual($0 as? ScreenVideoDisplayAdmissionBridgeError, .invalidBridge)
        }
        XCTAssertNil(try source(input)) // No sticky/global fallback or state is introduced.
    }

    func testStabilityActualCMatchesFrozenSignedDomainAndSingleAxisDrift() throws {
        for width in [Int.min, -1, 0, 1, 2, 1_206, 32_768, Int.max] {
            for height in [Int.min, -1, 0, 1, 2, 2_622, 32_768, Int.max] {
                let before = ScreenVideoPixelDimensions(width: width, height: height)
                for after in [before, .init(width: width ^ 1, height: height),
                              .init(width: width, height: height ^ 1)] {
                    let actual = try ScreenVideoSourceDimensionPolicy.isStableAcrossStart(
                        before: before, after: after
                    )
                    let frozen = FrozenSourceDimensionPolicy.isStableAcrossStart(before: before, after: after)
                    XCTAssertEqual(actual, frozen)
                }
            }
        }
    }

    func testAllFourRawExportsHaveIndependentCanonicalEnvelopeRefusals() {
        for invalid in [UInt32(0), 2, .max] {
            assertRawEnvelopeRefusal(version: invalid, reserved: 0)
        }
        for invalid in [UInt32(1), .max] {
            assertRawEnvelopeRefusal(version: 1, reserved: invalid)
        }
    }

    func testRequirementCopiedCResultCorruptionThrowsRatherThanFalseOrTrueFallback() throws {
        let mutations: [@Sendable (inout B.BooleanOutput) -> Void] = [
            { $0.abi_version = 0 }, { $0.abi_version = 2 }, { $0.abi_version = .max },
            { $0.status = 0 }, { $0.status = 2 }, { $0.status = .max },
            { $0.value = 2 }, { $0.value = .max }, { $0.reserved = 1 },
            { $0.value = 0 },
        ]
        for mutate in mutations {
            let producer = Producer(
                requirement: { raw in
                    var copied = beluga_core_display_requirement_admission(raw)
                    mutate(&copied)
                    return copied
                }, kind: Producer.actual.kind, source: Producer.actual.source,
                stability: Producer.actual.stability
            )
            XCTAssertThrowsError(try ScreenVideoDisplayRequirementPolicy.isSatisfied(
                requirement(), by: snapshot(), producer: producer
            )) { XCTAssertEqual($0 as? ScreenVideoDisplayAdmissionBridgeError, .invalidBridge) }
        }
        let wrongTrue = Producer(
            requirement: { raw in
                var copied = beluga_core_display_requirement_admission(raw)
                copied.value = 1
                return copied
            }, kind: Producer.actual.kind, source: Producer.actual.source,
            stability: Producer.actual.stability
        )
        XCTAssertThrowsError(try ScreenVideoDisplayRequirementPolicy.isSatisfied(
            requirement(), by: snapshot(online: false), producer: wrongTrue
        )) { XCTAssertEqual($0 as? ScreenVideoDisplayAdmissionBridgeError, .invalidBridge) }
        XCTAssertTrue(try ScreenVideoDisplayRequirementPolicy.isSatisfied(requirement(), by: snapshot()))
    }

    func testKindCopiedCResultCorruptionThrowsBeforeAnyLogicalEarlyReturn() throws {
        let mutations: [@Sendable (inout B.KindOutput) -> Void] = [
            { $0.abi_version = 0 }, { $0.abi_version = 2 }, { $0.abi_version = .max },
            { $0.status = 0 }, { $0.status = 2 }, { $0.kind = 2 },
            { $0.kind = .max }, { $0.reserved = 1 }, { $0.kind = 0 },
        ]
        for mutate in mutations {
            let producer = Producer(
                requirement: Producer.actual.requirement,
                kind: { raw in
                    var copied = beluga_core_source_dimension_kind(raw)
                    mutate(&copied)
                    return copied
                }, source: Producer.actual.source, stability: Producer.actual.stability
            )
            XCTAssertThrowsError(try ScreenVideoSourceDimensionPolicy.dimensionKind(
                vendorID: 0x6F73, productID: 0x1718, producer: producer
            )) { XCTAssertEqual($0 as? ScreenVideoDisplayAdmissionBridgeError, .invalidBridge) }
        }
        let wrongFramebuffer = Producer(
            requirement: Producer.actual.requirement,
            kind: { raw in
                var copied = beluga_core_source_dimension_kind(raw)
                copied.kind = 1
                return copied
            }, source: Producer.actual.source, stability: Producer.actual.stability
        )
        XCTAssertThrowsError(try ScreenVideoSourceDimensionPolicy.dimensionKind(
            vendorID: 0x610, productID: 0xA0E1, producer: wrongFramebuffer
        )) { XCTAssertEqual($0 as? ScreenVideoDisplayAdmissionBridgeError, .invalidBridge) }
        XCTAssertEqual(try ScreenVideoSourceDimensionPolicy.dimensionKind(
            vendorID: 0x6F73, productID: 0x1718
        ), .framebufferPixels)
    }

    func testSourceCopiedCResultCorruptionThrowsRatherThanNilOrLogicalFallback() throws {
        let mutations: [@Sendable (inout B.SourceOutput) -> Void] = [
            { $0.abi_version = 0 }, { $0.abi_version = 2 }, { $0.abi_version = .max },
            { $0.status = 0 }, { $0.status = 2 }, { $0.kind = 2 },
            { $0.kind = .max }, { $0.kind = 0 }, { $0.has_dimensions = 2 },
            { $0.has_dimensions = .max }, { $0.has_dimensions = 0 },
            { $0.width += 1 }, { $0.height += 1 },
        ]
        for mutate in mutations {
            let producer = Producer(
                requirement: Producer.actual.requirement, kind: Producer.actual.kind,
                source: { raw in
                    var copied = beluga_core_source_dimensions(raw)
                    mutate(&copied)
                    return copied
                }, stability: Producer.actual.stability
            )
            XCTAssertThrowsError(try source(sourceInput(), producer: producer)) {
                XCTAssertEqual($0 as? ScreenVideoDisplayAdmissionBridgeError, .invalidBridge)
            }
        }
        var absent = sourceInput(); absent.point_pixel_scale = 0
        for axis in [0, 1, 2] {
            let producer = Producer(
                requirement: Producer.actual.requirement, kind: Producer.actual.kind,
                source: { raw in
                    var copied = beluga_core_source_dimensions(raw)
                    if axis == 0 { copied.width = 1 }
                    else if axis == 1 { copied.height = 1 }
                    else {
                        copied.has_dimensions = 1
                        copied.width = raw.core_graphics_pixel_width
                        copied.height = raw.core_graphics_pixel_height
                    }
                    return copied
                }, stability: Producer.actual.stability
            )
            XCTAssertThrowsError(try source(absent, producer: producer)) {
                XCTAssertEqual($0 as? ScreenVideoDisplayAdmissionBridgeError, .invalidBridge)
            }
        }
        var ordinary = sourceInput()
        ordinary.vendor_id = 0x610
        ordinary.logical_width = .min; ordinary.logical_height = .max
        ordinary.point_pixel_scale = .nan
        let ordinaryMutations: [@Sendable (inout B.SourceOutput) -> Void] = [
            { $0.kind = 1 }, { $0.has_dimensions = 0 },
            { $0.width = 0 }, { $0.height = 0 },
        ]
        for mutate in ordinaryMutations {
            let producer = Producer(
                requirement: Producer.actual.requirement, kind: Producer.actual.kind,
                source: { raw in
                    var copied = beluga_core_source_dimensions(raw)
                    mutate(&copied)
                    return copied
                }, stability: Producer.actual.stability
            )
            XCTAssertThrowsError(try source(ordinary, producer: producer)) {
                XCTAssertEqual($0 as? ScreenVideoDisplayAdmissionBridgeError, .invalidBridge)
            }
        }
        XCTAssertEqual(try source(ordinary), .init(width: .min, height: .max))
        XCTAssertNil(try source(absent))
        XCTAssertEqual(try source(sourceInput()), .init(width: 1_080, height: 2_340))
    }

    func testStabilityCopiedCResultCorruptionThrowsRatherThanFalseFallback() throws {
        let mutations: [@Sendable (inout B.BooleanOutput) -> Void] = [
            { $0.abi_version = 0 }, { $0.abi_version = 2 }, { $0.abi_version = .max },
            { $0.status = 0 }, { $0.status = 2 }, { $0.value = 2 },
            { $0.value = .max }, { $0.reserved = 1 }, { $0.value = 0 },
        ]
        for mutate in mutations {
            let producer = Producer(
                requirement: Producer.actual.requirement, kind: Producer.actual.kind,
                source: Producer.actual.source,
                stability: { raw in
                    var copied = beluga_core_source_dimensions_stable(raw)
                    mutate(&copied)
                    return copied
                }
            )
            XCTAssertThrowsError(try ScreenVideoSourceDimensionPolicy.isStableAcrossStart(
                before: .init(width: .min, height: .max), after: .init(width: .min, height: .max),
                producer: producer
            )) { XCTAssertEqual($0 as? ScreenVideoDisplayAdmissionBridgeError, .invalidBridge) }
        }
        let wrongTrue = Producer(
            requirement: Producer.actual.requirement, kind: Producer.actual.kind,
            source: Producer.actual.source,
            stability: { raw in
                var copied = beluga_core_source_dimensions_stable(raw)
                copied.value = 1
                return copied
            }
        )
        XCTAssertThrowsError(try ScreenVideoSourceDimensionPolicy.isStableAcrossStart(
            before: .init(width: 1_206, height: 2_622),
            after: .init(width: 1_205, height: 2_622), producer: wrongTrue
        )) { XCTAssertEqual($0 as? ScreenVideoDisplayAdmissionBridgeError, .invalidBridge) }
        XCTAssertTrue(try ScreenVideoSourceDimensionPolicy.isStableAcrossStart(
            before: .init(width: .min, height: .max), after: .init(width: .min, height: .max)
        ))
    }

    func testActualCInputsStayBitExactIncludingAbsentMetadataNaNAndSignedZero() {
        var requirement = requirementInput()
        let requirementBefore = bytes(requirement)
        _ = beluga_core_display_requirement_admission(requirement)
        XCTAssertEqual(bytes(requirement), requirementBefore)
        requirement.reserved = 1
        let invalidRequirementBefore = bytes(requirement)
        _ = beluga_core_display_requirement_admission(requirement)
        XCTAssertEqual(bytes(requirement), invalidRequirementBefore)
        var kind = kindInput()
        let kindBefore = bytes(kind)
        _ = beluga_core_source_dimension_kind(kind)
        XCTAssertEqual(bytes(kind), kindBefore)
        kind.reserved = 1
        let invalidKindBefore = bytes(kind)
        _ = beluga_core_source_dimension_kind(kind)
        XCTAssertEqual(bytes(kind), invalidKindBefore)
        var stable = stabilityInput()
        let stableBefore = bytes(stable)
        _ = beluga_core_source_dimensions_stable(stable)
        XCTAssertEqual(bytes(stable), stableBefore)
        stable.reserved = 1
        let invalidStableBefore = bytes(stable)
        _ = beluga_core_source_dimensions_stable(stable)
        XCTAssertEqual(bytes(stable), invalidStableBefore)
        for vendor in [UInt32(0x610), 0x6F73] {
            let bitTriples: [(UInt64, UInt64, UInt64)] = [
                (0x7ff8_1234_5678_9abc, 0xfff8_8765_4321_abcd, 0x7ff0_0000_0000_0001),
                (0x8000_0000_0000_0000, 0, 0x7ff0_0000_0000_0000),
                (540.0.bitPattern, 1_170.0.bitPattern, 2.0.bitPattern),
            ]
            for bits in bitTriples {
                var input = sourceInput()
                input.vendor_id = vendor
                input.filter_content_width = Double(bitPattern: bits.0)
                input.filter_content_height = Double(bitPattern: bits.1)
                input.point_pixel_scale = Double(bitPattern: bits.2)
                let before = bytes(input)
                _ = beluga_core_source_dimensions(input)
                XCTAssertEqual(bytes(input), before)
                input.reserved = 1
                let invalidBefore = bytes(input)
                _ = beluga_core_source_dimensions(input)
                XCTAssertEqual(bytes(input), invalidBefore)
                XCTAssertEqual(input.filter_content_width.bitPattern, bits.0)
                XCTAssertEqual(input.filter_content_height.bitPattern, bits.1)
                XCTAssertEqual(input.point_pixel_scale.bitPattern, bits.2)
            }
        }
    }

    func testTypedFacadePreservesHighBitIdentityTopologyKindAndOrdinarySourceAliases() throws {
        let identityPairs: [(low: UInt32, alias: UInt32)] = [
            (0x6F73, 0x0001_6F73), (0x1718, 0x0001_1718), (1, 0x0001_0001),
        ]
        for field in 0 ..< 3 {
            for requiredHasAlias in [false, true] {
                var required: [UInt32] = [0x6F73, 0x1718, 1]
                var observed: [UInt32] = [0x6F73, 0x1718, 1]
                if requiredHasAlias { required[field] = identityPairs[field].alias }
                else { observed[field] = identityPairs[field].alias }
                let requirement = ScreenVideoDisplayRequirement(
                    vendorID: required[0], productID: required[1], serialNumber: required[2],
                    requiresSoleMainDisplay: true
                )
                let snapshot = ScreenVideoDisplaySnapshot(
                    displayID: 42, vendorID: observed[0], productID: observed[1],
                    serialNumber: observed[2], isOnline: true, isActive: true,
                    mainDisplayID: 42, onlineDisplayIDs: [42]
                )
                let actual = try ScreenVideoDisplayRequirementPolicy.isSatisfied(requirement, by: snapshot)
                XCTAssertFalse(actual, "required/observed high-bit mismatch field \(field)")
                XCTAssertFalse(FrozenDisplayRequirementPolicy.isSatisfied(requirement, by: snapshot))
            }
            var identities: [UInt32] = [0x6F73, 0x1718, 1]
            identities[field] = identityPairs[field].alias
            let requirement = ScreenVideoDisplayRequirement(
                vendorID: identities[0], productID: identities[1], serialNumber: identities[2],
                requiresSoleMainDisplay: true
            )
            let snapshot = ScreenVideoDisplaySnapshot(
                displayID: 42, vendorID: identities[0], productID: identities[1],
                serialNumber: identities[2], isOnline: true, isActive: true,
                mainDisplayID: 42, onlineDisplayIDs: [42]
            )
            let actual = try ScreenVideoDisplayRequirementPolicy.isSatisfied(requirement, by: snapshot)
            XCTAssertTrue(actual, "matching full-width high-bit identity field \(field)")
            XCTAssertTrue(FrozenDisplayRequirementPolicy.isSatisfied(requirement, by: snapshot))
        }
        let topology: [(id: UInt32, main: UInt32, ids: [UInt32], literal: Bool)] = [
            (42, 0x0001_002A, [42], false),
            (42, 42, [0x0001_002A], false),
            (0x0001_002A, 42, [0x0001_002A], false),
            (0x0001_002A, 0x0001_002A, [42], false),
            (0x0001_002A, 0x0001_002A, [0x0001_002A], true),
            (42, 42, [42, 0x0001_002A], false),
            (0x0001_002A, 0x0001_002A, [0x0001_002A, 0x0001_002A], false),
        ]
        for row in topology {
            let snapshot = ScreenVideoDisplaySnapshot(
                displayID: row.id, vendorID: 0x6F73, productID: 0x1718, serialNumber: 1,
                isOnline: true, isActive: true, mainDisplayID: row.main, onlineDisplayIDs: row.ids
            )
            let actual = try ScreenVideoDisplayRequirementPolicy.isSatisfied(requirement(), by: snapshot)
            XCTAssertEqual(actual, row.literal)
            XCTAssertEqual(FrozenDisplayRequirementPolicy.isSatisfied(requirement(), by: snapshot), row.literal)
        }
        let aliases: [(UInt32, UInt32)] = [
            (0x0001_6F73, 0x1717), (0x0001_6F73, 0x1718),
            (0x6F73, 0x0001_1717), (0x6F73, 0x0001_1718),
            (0x0001_6F73, 0x0001_1717), (0x0001_6F73, 0x0001_1718),
        ]
        for (vendor, product) in aliases {
            let actualKind = try ScreenVideoSourceDimensionPolicy.dimensionKind(
                vendorID: vendor, productID: product
            )
            XCTAssertEqual(actualKind, .logical)
            XCTAssertEqual(FrozenSourceDimensionPolicy.dimensionKind(vendorID: vendor, productID: product), .logical)
            var input = sourceInput()
            input.vendor_id = vendor; input.product_id = product
            input.logical_width = .min; input.logical_height = .max
            input.core_graphics_logical_width = 0; input.core_graphics_logical_height = -1
            input.core_graphics_pixel_width = 0; input.core_graphics_pixel_height = -1
            input.filter_content_width = Double(bitPattern: 0x7ff8_1234_5678_9abc)
            input.filter_content_height = -0.0; input.point_pixel_scale = .nan
            let actualSource = try source(input)
            XCTAssertEqual(actualSource, .init(width: .min, height: .max))
            XCTAssertEqual(frozenSource(input), .init(width: .min, height: .max))
        }
    }

    func testTypedFacadeProjectsEveryRawInputBitAfterCallingActualC() throws {
        // Expected word arrays are literal and never reconstructed by a production helper.
        let topology: [(ids: [UInt32], sole: Bool, rawSole: UInt64,
                        count: UInt64, singleton: UInt64, literal: Bool)] = [
            ([], true, 1, 0, 0, false),
            ([0x0001_002A], true, 1, 1, 0x0001_002A, true),
            ([0x0001_002A, 0x0001_002A], true, 1, 2, 0, false),
            ([3, 4, 5], false, 0, 3, 0, true),
        ]
        for row in topology {
            let recorder = DisplayAdmissionRawRecorder()
            let producer = recordingProducer(recorder)
            let requirement = ScreenVideoDisplayRequirement(
                vendorID: 0x0001_6F73, productID: 0x0001_1718, serialNumber: 0x0001_0001,
                requiresSoleMainDisplay: row.sole
            )
            let snapshot = ScreenVideoDisplaySnapshot(
                displayID: 0x0001_002A, vendorID: 0x0001_6F73, productID: 0x0001_1718,
                serialNumber: 0x0001_0001, isOnline: true, isActive: true,
                mainDisplayID: 0x0001_002A, onlineDisplayIDs: row.ids
            )
            let actual = try ScreenVideoDisplayRequirementPolicy.isSatisfied(
                requirement, by: snapshot, producer: producer
            )
            XCTAssertEqual(actual, row.literal)
            XCTAssertEqual(recorder.snapshot(), [.init(family: "requirement", words: [
                1, 0, 0x0001_6F73, 0x0001_1718, 0x0001_0001, row.rawSole,
                0x0001_002A, 0x0001_6F73, 0x0001_1718, 0x0001_0001,
                1, 1, 0x0001_002A, row.singleton, row.count,
            ])])
        }
        let liveness: [(online: Bool, active: Bool, rawOnline: UInt64,
                        rawActive: UInt64, literal: Bool)] = [
            (false, false, 0, 0, false), (false, true, 0, 1, false),
            (true, false, 1, 0, false), (true, true, 1, 1, true),
        ]
        for row in liveness {
            let recorder = DisplayAdmissionRawRecorder()
            let snapshot = ScreenVideoDisplaySnapshot(
                displayID: 42, vendorID: 0x6F73, productID: 0x1718, serialNumber: 1,
                isOnline: row.online, isActive: row.active, mainDisplayID: 42,
                onlineDisplayIDs: [42]
            )
            let actual = try ScreenVideoDisplayRequirementPolicy.isSatisfied(
                requirement(), by: snapshot, producer: recordingProducer(recorder)
            )
            XCTAssertEqual(actual, row.literal)
            XCTAssertEqual(recorder.snapshot(), [.init(family: "requirement", words: [
                1, 0, 0x6F73, 0x1718, 1, 1, 42, 0x6F73, 0x1718, 1,
                row.rawOnline, row.rawActive, 42, 42, 1,
            ])])
        }
        let kinds: [(vendor: UInt32, product: UInt32, literal: ScreenVideoSourceDimensionKind)] = [
            (0x0001_6F73, 0x0001_1717, .logical), (0x6F73, 0x1718, .framebufferPixels),
        ]
        for row in kinds {
            let recorder = DisplayAdmissionRawRecorder()
            let actual = try ScreenVideoSourceDimensionPolicy.dimensionKind(
                vendorID: row.vendor, productID: row.product, producer: recordingProducer(recorder)
            )
            XCTAssertEqual(actual, row.literal)
            XCTAssertEqual(recorder.snapshot(), [.init(family: "kind", words: [
                1, 0, UInt64(row.vendor), UInt64(row.product),
            ])])
        }
        let metadata: [(UInt64, UInt64, UInt64)] = [
            (0x7ff8_1234_5678_9abc, 0x8000_0000_0000_0000, 0x0000_0000_0000_0000),
            (0x0000_0000_0000_0000, 0xfff8_8765_4321_abcd, 0x8000_0000_0000_0000),
            (0x8000_0000_0000_0000, 0x0000_0000_0000_0000, 0x7ff8_2468_1357_abcd),
        ]
        for bits in metadata {
            let recorder = DisplayAdmissionRawRecorder()
            let actual = try ScreenVideoSourceDimensionPolicy.sourceDimensions(
                vendorID: 0x0001_6F73, productID: 0x0001_1717,
                logicalDimensions: .init(width: .min, height: .max),
                filterContentWidth: Double(bitPattern: bits.0),
                filterContentHeight: Double(bitPattern: bits.1),
                pointPixelScale: Double(bitPattern: bits.2),
                coreGraphicsLogicalDimensions: .init(width: -1, height: 0),
                coreGraphicsPixelDimensions: .init(width: 1, height: 2),
                producer: recordingProducer(recorder)
            )
            XCTAssertEqual(actual, .init(width: .min, height: .max))
            XCTAssertEqual(recorder.snapshot(), [.init(family: "source", words: [
                1, 0, 0x0001_6F73, 0x0001_1717,
                0x8000_0000_0000_0000, 0x7fff_ffff_ffff_ffff,
                0xffff_ffff_ffff_ffff, 0, 1, 2, bits.0, bits.1, bits.2,
            ])])
        }
        let dimensions: [(before: ScreenVideoPixelDimensions, after: ScreenVideoPixelDimensions,
                          words: [UInt64])] = [
            (.init(width: .min, height: .max), .init(width: -1, height: 0),
             [1, 0, 0x8000_0000_0000_0000, 0x7fff_ffff_ffff_ffff, 0xffff_ffff_ffff_ffff, 0]),
            (.init(width: 1, height: 2), .init(width: .min, height: .max),
             [1, 0, 1, 2, 0x8000_0000_0000_0000, 0x7fff_ffff_ffff_ffff]),
        ]
        for row in dimensions {
            let recorder = DisplayAdmissionRawRecorder()
            let actual = try ScreenVideoSourceDimensionPolicy.isStableAcrossStart(
                before: row.before, after: row.after, producer: recordingProducer(recorder)
            )
            XCTAssertFalse(actual)
            XCTAssertEqual(recorder.snapshot(), [.init(family: "stability", words: row.words)])
        }
    }

    private func recordingProducer(_ recorder: DisplayAdmissionRawRecorder) -> Producer {
        Producer(
            requirement: { raw in
                let actual = beluga_core_display_requirement_admission(raw)
                recorder.append(.init(family: "requirement", words: [
                    UInt64(raw.abi_version), UInt64(raw.reserved),
                    UInt64(raw.required_vendor_id), UInt64(raw.required_product_id),
                    UInt64(raw.required_serial_number), UInt64(raw.requires_sole_main_display),
                    UInt64(raw.display_id), UInt64(raw.observed_vendor_id),
                    UInt64(raw.observed_product_id), UInt64(raw.observed_serial_number),
                    UInt64(raw.is_online), UInt64(raw.is_active), UInt64(raw.main_display_id),
                    UInt64(raw.sole_online_display_id), raw.online_display_count,
                ]))
                return actual
            },
            kind: { raw in
                let actual = beluga_core_source_dimension_kind(raw)
                recorder.append(.init(family: "kind", words: [
                    UInt64(raw.abi_version), UInt64(raw.reserved),
                    UInt64(raw.vendor_id), UInt64(raw.product_id),
                ]))
                return actual
            },
            source: { raw in
                let actual = beluga_core_source_dimensions(raw)
                recorder.append(.init(family: "source", words: [
                    UInt64(raw.abi_version), UInt64(raw.reserved),
                    UInt64(raw.vendor_id), UInt64(raw.product_id),
                    UInt64(bitPattern: raw.logical_width), UInt64(bitPattern: raw.logical_height),
                    UInt64(bitPattern: raw.core_graphics_logical_width),
                    UInt64(bitPattern: raw.core_graphics_logical_height),
                    UInt64(bitPattern: raw.core_graphics_pixel_width),
                    UInt64(bitPattern: raw.core_graphics_pixel_height),
                    raw.filter_content_width.bitPattern, raw.filter_content_height.bitPattern,
                    raw.point_pixel_scale.bitPattern,
                ]))
                return actual
            },
            stability: { raw in
                let actual = beluga_core_source_dimensions_stable(raw)
                recorder.append(.init(family: "stability", words: [
                    UInt64(raw.abi_version), UInt64(raw.reserved),
                    UInt64(bitPattern: raw.before_width), UInt64(bitPattern: raw.before_height),
                    UInt64(bitPattern: raw.after_width), UInt64(bitPattern: raw.after_height),
                ]))
                return actual
            }
        )
    }

    private func requirement() -> ScreenVideoDisplayRequirement {
        .init(vendorID: 0x6F73, productID: 0x1718, serialNumber: 1, requiresSoleMainDisplay: true)
    }
    private func snapshot(online: Bool = true) -> ScreenVideoDisplaySnapshot {
        .init(displayID: 42, vendorID: 0x6F73, productID: 0x1718, serialNumber: 1,
              isOnline: online, isActive: true, mainDisplayID: 42, onlineDisplayIDs: [42])
    }
    private func requirementInput() -> B.RequirementInput {
        var input = B.RequirementInput()
        input.abi_version = 1
        input.required_vendor_id = 0x6F73; input.required_product_id = 0x1718
        input.required_serial_number = 1; input.requires_sole_main_display = 1
        input.display_id = 42; input.observed_vendor_id = 0x6F73
        input.observed_product_id = 0x1718; input.observed_serial_number = 1
        input.is_online = 1; input.is_active = 1; input.main_display_id = 42
        input.sole_online_display_id = 42; input.online_display_count = 1
        return input
    }
    private func kindInput() -> B.KindInput {
        var input = B.KindInput(); input.abi_version = 1
        input.vendor_id = 0x6F73; input.product_id = 0x1718
        return input
    }
    private func sourceInput() -> B.SourceInput {
        var input = B.SourceInput(); input.abi_version = 1
        input.vendor_id = 0x6F73; input.product_id = 0x1718
        input.logical_width = 540; input.logical_height = 1_170
        input.core_graphics_logical_width = 540; input.core_graphics_logical_height = 1_170
        input.core_graphics_pixel_width = 1_080; input.core_graphics_pixel_height = 2_340
        input.filter_content_width = 540; input.filter_content_height = 1_170
        input.point_pixel_scale = 2
        return input
    }
    private func stabilityInput() -> B.StabilityInput {
        var input = B.StabilityInput(); input.abi_version = 1
        input.before_width = .min; input.before_height = .max
        input.after_width = .min; input.after_height = .max
        return input
    }
    private func source(_ input: B.SourceInput, producer: Producer = .actual) throws -> ScreenVideoPixelDimensions? {
        try ScreenVideoSourceDimensionPolicy.sourceDimensions(
            vendorID: input.vendor_id, productID: input.product_id,
            logicalDimensions: .init(width: Int(input.logical_width), height: Int(input.logical_height)),
            filterContentWidth: input.filter_content_width, filterContentHeight: input.filter_content_height,
            pointPixelScale: input.point_pixel_scale,
            coreGraphicsLogicalDimensions: .init(
                width: Int(input.core_graphics_logical_width), height: Int(input.core_graphics_logical_height)
            ),
            coreGraphicsPixelDimensions: .init(
                width: Int(input.core_graphics_pixel_width), height: Int(input.core_graphics_pixel_height)
            ), producer: producer
        )
    }
    private func frozenSource(_ input: B.SourceInput) -> ScreenVideoPixelDimensions? {
        FrozenSourceDimensionPolicy.sourceDimensions(
            vendorID: input.vendor_id, productID: input.product_id,
            logicalDimensions: .init(width: Int(input.logical_width), height: Int(input.logical_height)),
            filterContentWidth: input.filter_content_width, filterContentHeight: input.filter_content_height,
            pointPixelScale: input.point_pixel_scale,
            coreGraphicsLogicalDimensions: .init(
                width: Int(input.core_graphics_logical_width), height: Int(input.core_graphics_logical_height)
            ),
            coreGraphicsPixelDimensions: .init(
                width: Int(input.core_graphics_pixel_width), height: Int(input.core_graphics_pixel_height)
            )
        )
    }
    private func bytes<T>(_ input: T) -> [UInt8] {
        withUnsafeBytes(of: input) { Array($0) }
    }
    private func assertBoolean(_ output: B.BooleanOutput, status: UInt32, value: UInt32,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(output.abi_version, 1, file: file, line: line)
        XCTAssertEqual(output.status, status, file: file, line: line)
        XCTAssertEqual(output.value, value, file: file, line: line)
        XCTAssertEqual(output.reserved, 0, file: file, line: line)
    }
    private func assertRawEnvelopeRefusal(version: UInt32, reserved: UInt32,
                                         file: StaticString = #filePath, line: UInt = #line) {
        var requirement = requirementInput(); requirement.abi_version = version; requirement.reserved = reserved
        let requirementOutput = beluga_core_display_requirement_admission(requirement)
        assertBoolean(requirementOutput, status: 0, value: 0, file: file, line: line)
        XCTAssertFalse(B.acceptsRequirement(requirement, requirementOutput), file: file, line: line)
        var kind = kindInput(); kind.abi_version = version; kind.reserved = reserved
        let kindOutput = beluga_core_source_dimension_kind(kind)
        XCTAssertEqual(kindOutput.abi_version, 1, file: file, line: line)
        XCTAssertEqual(kindOutput.status, 0, file: file, line: line)
        XCTAssertEqual(kindOutput.kind, 0, file: file, line: line)
        XCTAssertEqual(kindOutput.reserved, 0, file: file, line: line)
        XCTAssertFalse(B.acceptsKind(kind, kindOutput), file: file, line: line)
        for vendor in [UInt32(0x610), 0x6F73] {
            var source = sourceInput(); source.abi_version = version; source.reserved = reserved
            source.vendor_id = vendor
            let sourceOutput = beluga_core_source_dimensions(source)
            XCTAssertEqual(sourceOutput.abi_version, 1, file: file, line: line)
            XCTAssertEqual(sourceOutput.status, 0, file: file, line: line)
            XCTAssertEqual(sourceOutput.kind, 0, file: file, line: line)
            XCTAssertEqual(sourceOutput.has_dimensions, 0, file: file, line: line)
            XCTAssertEqual(sourceOutput.width, 0, file: file, line: line)
            XCTAssertEqual(sourceOutput.height, 0, file: file, line: line)
            XCTAssertFalse(B.acceptsSource(source, sourceOutput), file: file, line: line)
        }
        var stable = stabilityInput(); stable.abi_version = version; stable.reserved = reserved
        let stableOutput = beluga_core_source_dimensions_stable(stable)
        assertBoolean(stableOutput, status: 0, value: 0, file: file, line: line)
        XCTAssertFalse(B.acceptsStability(stable, stableOutput), file: file, line: line)
    }
}

// Test-only synchronized copy observation; no input/output mutation or policy fallback.
private struct DisplayAdmissionRawRecord: Equatable, Sendable {
    let family: String
    let words: [UInt64]
}
private final class DisplayAdmissionRawRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [DisplayAdmissionRawRecord] = []
    func append(_ record: DisplayAdmissionRawRecord) {
        lock.lock(); defer { lock.unlock() }
        records.append(record)
    }
    func snapshot() -> [DisplayAdmissionRawRecord] {
        lock.lock(); defer { lock.unlock() }
        return records
    }
}
