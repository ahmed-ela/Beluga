import Foundation

/// Source dimensions used to configure ScreenCaptureKit output.
public struct ScreenVideoPixelDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Logical and framebuffer dimensions read from one authoritative display-mode snapshot.
public struct ScreenVideoDisplayModeSnapshot: Equatable, Sendable {
    public let logicalDimensions: ScreenVideoPixelDimensions
    public let pixelDimensions: ScreenVideoPixelDimensions

    public init(
        logicalDimensions: ScreenVideoPixelDimensions,
        pixelDimensions: ScreenVideoPixelDimensions
    ) {
        self.logicalDimensions = logicalDimensions
        self.pixelDimensions = pixelDimensions
    }
}

/// Resolves a display mode without prescribing whether the caller uses its current process or a
/// fresh helper process. The worldwide host uses a fresh process because the virtual-display
/// owner's CoreGraphics connection can retain an older mode after Display Settings changes it.
public typealias ScreenVideoDisplayModeSnapshotProvider =
    @Sendable (UInt32) async throws -> ScreenVideoDisplayModeSnapshot

/// Immutable identity and topology requirements for a display selected by numeric ID.
///
/// WindowServer may recycle display IDs after a virtual display terminates. Callers that own a
/// display pass this requirement so every capture start proves the ID still names that display.
public struct ScreenVideoDisplayRequirement: Equatable, Sendable {
    public let vendorID: UInt32
    public let productID: UInt32
    public let serialNumber: UInt32
    public let requiresSoleMainDisplay: Bool

    public init(
        vendorID: UInt32,
        productID: UInt32,
        serialNumber: UInt32,
        requiresSoleMainDisplay: Bool
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.requiresSoleMainDisplay = requiresSoleMainDisplay
    }
}

/// Read-only CoreGraphics facts used to reject a stale or recycled display ID.
struct ScreenVideoDisplaySnapshot: Equatable, Sendable {
    let displayID: UInt32
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let isOnline: Bool
    let isActive: Bool
    let mainDisplayID: UInt32
    let onlineDisplayIDs: [UInt32]
}

enum ScreenVideoDisplayRequirementPolicy {
    static func isSatisfied(
        _ requirement: ScreenVideoDisplayRequirement,
        by snapshot: ScreenVideoDisplaySnapshot,
        producer: BelugaRustDisplayAdmissionProducer = .actual
    ) throws -> Bool {
        var input = BelugaRustDisplayAdmissionBoundary.RequirementInput()
        input.abi_version = 1
        input.required_vendor_id = requirement.vendorID
        input.required_product_id = requirement.productID
        input.required_serial_number = requirement.serialNumber
        input.requires_sole_main_display = requirement.requiresSoleMainDisplay ? 1 : 0
        input.display_id = snapshot.displayID
        input.observed_vendor_id = snapshot.vendorID
        input.observed_product_id = snapshot.productID
        input.observed_serial_number = snapshot.serialNumber
        input.is_online = snapshot.isOnline ? 1 : 0
        input.is_active = snapshot.isActive ? 1 : 0
        input.main_display_id = snapshot.mainDisplayID
        input.online_display_count = UInt64(snapshot.onlineDisplayIDs.count)
        input.sole_online_display_id = snapshot.onlineDisplayIDs.count == 1
            ? snapshot.onlineDisplayIDs[0] : 0
        let output = producer.requirement(input)
        guard BelugaRustDisplayAdmissionBoundary.acceptsRequirement(input, output) else {
            throw ScreenVideoDisplayAdmissionBridgeError.invalidBridge
        }
        return output.value == 1
    }
}

/// Chooses which display dimensions preserve established capture behavior.
enum ScreenVideoSourceDimensionKind: Equatable, Sendable {
    case logical
    case framebufferPixels
}

/// Scalar decisions are copied into Rust; providers, native readback and stream effects stay native.
enum ScreenVideoSourceDimensionPolicy {
    static func dimensionKind(
        vendorID: UInt32, productID: UInt32,
        producer: BelugaRustDisplayAdmissionProducer = .actual
    ) throws -> ScreenVideoSourceDimensionKind {
        var input = BelugaRustDisplayAdmissionBoundary.KindInput()
        input.abi_version = 1
        input.vendor_id = vendorID
        input.product_id = productID
        let output = producer.kind(input)
        guard BelugaRustDisplayAdmissionBoundary.acceptsKind(input, output) else {
            // Never fallback to logical: the production caller early-returns for that result.
            throw ScreenVideoDisplayAdmissionBridgeError.invalidBridge
        }
        switch output.kind {
        case 0: return .logical
        case 1: return .framebufferPixels
        default: throw ScreenVideoDisplayAdmissionBridgeError.invalidBridge
        }
    }

    static func sourceDimensions(
        vendorID: UInt32,
        productID: UInt32,
        logicalDimensions: ScreenVideoPixelDimensions,
        filterContentWidth: Double,
        filterContentHeight: Double,
        pointPixelScale: Double,
        coreGraphicsLogicalDimensions: ScreenVideoPixelDimensions,
        coreGraphicsPixelDimensions: ScreenVideoPixelDimensions,
        producer: BelugaRustDisplayAdmissionProducer = .actual
    ) throws -> ScreenVideoPixelDimensions? {
        var input = BelugaRustDisplayAdmissionBoundary.SourceInput()
        input.abi_version = 1
        input.vendor_id = vendorID
        input.product_id = productID
        input.logical_width = Int64(logicalDimensions.width)
        input.logical_height = Int64(logicalDimensions.height)
        input.core_graphics_logical_width = Int64(coreGraphicsLogicalDimensions.width)
        input.core_graphics_logical_height = Int64(coreGraphicsLogicalDimensions.height)
        input.core_graphics_pixel_width = Int64(coreGraphicsPixelDimensions.width)
        input.core_graphics_pixel_height = Int64(coreGraphicsPixelDimensions.height)
        input.filter_content_width = filterContentWidth
        input.filter_content_height = filterContentHeight
        input.point_pixel_scale = pointPixelScale
        let output = producer.source(input)
        guard BelugaRustDisplayAdmissionBoundary.acceptsSource(input, output) else {
            throw ScreenVideoDisplayAdmissionBridgeError.invalidBridge
        }
        guard output.has_dimensions == 1 else { return nil }
        return ScreenVideoPixelDimensions(width: Int(output.width), height: Int(output.height))
    }

    static func isStableAcrossStart(
        before: ScreenVideoPixelDimensions,
        after: ScreenVideoPixelDimensions,
        producer: BelugaRustDisplayAdmissionProducer = .actual
    ) throws -> Bool {
        var input = BelugaRustDisplayAdmissionBoundary.StabilityInput()
        input.abi_version = 1
        input.before_width = Int64(before.width)
        input.before_height = Int64(before.height)
        input.after_width = Int64(after.width)
        input.after_height = Int64(after.height)
        let output = producer.stability(input)
        guard BelugaRustDisplayAdmissionBoundary.acceptsStability(input, output) else {
            throw ScreenVideoDisplayAdmissionBridgeError.invalidBridge
        }
        return output.value == 1
    }
}

/// Converts selected display dimensions into even, aspect-preserving encoder dimensions.
public enum ScreenVideoOutputPolicy {
    public static func outputDimensions(
        source: ScreenVideoPixelDimensions,
        maximumWidth: Int
    ) throws -> ScreenVideoPixelDimensions {
        guard source.width >= 2, source.height >= 2, maximumWidth >= 2 else {
            throw ScreenVideoOutputPolicyError.invalidDimensions
        }

        let cappedWidth = min(source.width, maximumWidth)
        let width = cappedWidth - cappedWidth % 2
        let scaledHeight = Int(
            (Double(source.height) * Double(width) / Double(source.width)).rounded()
        )
        let height = max(2, scaledHeight - scaledHeight % 2)
        return ScreenVideoPixelDimensions(width: width, height: height)
    }
}

public enum ScreenVideoOutputPolicyError: LocalizedError, Equatable {
    case invalidDimensions

    public var errorDescription: String? {
        "Screen video source and maximum dimensions must be at least two pixels"
    }
}
