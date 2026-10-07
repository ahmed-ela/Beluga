// Frozen native policy bodies from BEFORE_PINS; production never calls this reference.
import Foundation
@testable import CaptureCore

enum FrozenDisplayRequirementPolicy {
    static func isSatisfied(
        _ requirement: ScreenVideoDisplayRequirement,
        by snapshot: ScreenVideoDisplaySnapshot
    ) -> Bool {
        guard snapshot.isOnline,
            snapshot.isActive,
            snapshot.vendorID == requirement.vendorID,
            snapshot.productID == requirement.productID,
            snapshot.serialNumber == requirement.serialNumber
        else {
            return false
        }
        guard requirement.requiresSoleMainDisplay else { return true }
        return snapshot.mainDisplayID == snapshot.displayID
            && snapshot.onlineDisplayIDs == [snapshot.displayID]
    }
}

/// Restricts framebuffer-pixel capture to OpenSteamer-owned virtual displays.
enum FrozenSourceDimensionPolicy {
    private static let openSteamerVendorID: UInt32 = 0x6F73
    private static let openSteamerProductIDs: Set<UInt32> = [0x1717, 0x1718]

    static func dimensionKind(vendorID: UInt32, productID: UInt32) -> ScreenVideoSourceDimensionKind
    {
        guard vendorID == openSteamerVendorID,
            openSteamerProductIDs.contains(productID)
        else {
            return .logical
        }
        return .framebufferPixels
    }

    /// Resolves the requested source framebuffer. Ordinary displays preserve the established
    /// logical-size behavior. OpenSteamer-owned displays use Core Graphics' current framebuffer
    /// pixels after proving that ScreenCaptureKit still identifies the same logical display; the
    /// service separately proves the first delivered surface before publishing this format.
    static func sourceDimensions(
        vendorID: UInt32,
        productID: UInt32,
        logicalDimensions: ScreenVideoPixelDimensions,
        filterContentWidth: Double,
        filterContentHeight: Double,
        pointPixelScale: Double,
        coreGraphicsLogicalDimensions: ScreenVideoPixelDimensions,
        coreGraphicsPixelDimensions: ScreenVideoPixelDimensions
    ) -> ScreenVideoPixelDimensions? {
        guard dimensionKind(vendorID: vendorID, productID: productID) == .framebufferPixels else {
            return logicalDimensions
        }

        guard logicalDimensions.width >= 2,
              logicalDimensions.height >= 2,
              logicalDimensions.width <= 32_768,
              logicalDimensions.height <= 32_768,
              filterContentWidth.isFinite,
              filterContentHeight.isFinite,
              pointPixelScale.isFinite,
              (1 ... 4).contains(pointPixelScale),
              coreGraphicsLogicalDimensions.width >= 2,
              coreGraphicsLogicalDimensions.height >= 2,
              coreGraphicsPixelDimensions.width >= 2,
              coreGraphicsPixelDimensions.height >= 2,
              coreGraphicsPixelDimensions.width <= 32_768,
              coreGraphicsPixelDimensions.height <= 32_768,
              logicalDimensions == coreGraphicsLogicalDimensions,
              abs(filterContentWidth - Double(logicalDimensions.width)) <= 0.5,
              abs(filterContentHeight - Double(logicalDimensions.height)) <= 0.5 else {
            return nil
        }

        return coreGraphicsPixelDimensions
    }

    /// A Show transaction may publish its encoder format only if the framebuffer stayed fixed
    /// throughout native SCStream startup.
    static func isStableAcrossStart(
        before: ScreenVideoPixelDimensions,
        after: ScreenVideoPixelDimensions
    ) -> Bool {
        before == after
    }
}

