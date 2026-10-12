// Frozen original output body, enum name only changed. Never called by production.
import Foundation
@testable import CaptureCore

enum FrozenScreenVideoOutputPolicy {
    static func outputDimensions(
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

// Independent prefix of the frozen original, stopping before its trapping Int conversion.
// This projects reference bits for the repaired domain without calling that domain in-process.
enum FrozenScreenVideoOutputPrefix {
    static func roundedHeightBits(source: ScreenVideoPixelDimensions, maximumWidth: Int) throws -> UInt64 {
        guard source.width >= 2, source.height >= 2, maximumWidth >= 2 else {
            throw ScreenVideoOutputPolicyError.invalidDimensions
        }
        let cappedWidth = min(source.width, maximumWidth)
        let width = cappedWidth - cappedWidth % 2
        return (Double(source.height) * Double(width) / Double(source.width)).rounded().bitPattern
    }
}
