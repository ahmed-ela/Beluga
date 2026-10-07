import BelugaCore

enum ScreenVideoOutputDimensionsBridgeError: Error, Equatable, Sendable {
    case invalidBridge
}

enum BelugaRustOutputDimensionsBoundary {
    typealias Input = beluga_core_output_dimensions_facts_t
    typealias Output = beluga_core_output_dimensions_decision_t

    static var layoutIsExact: Bool {
        MemoryLayout<Int>.size == 8
            && MemoryLayout<Input>.size == 32 && MemoryLayout<Input>.stride == 32
            && MemoryLayout<Input>.alignment == 8
            && MemoryLayout<Output>.size == 40 && MemoryLayout<Output>.stride == 40
            && MemoryLayout<Output>.alignment == 8
            && MemoryLayout<Input>.offset(of: \Input.abi_version) == 0
            && MemoryLayout<Input>.offset(of: \Input.reserved) == 4
            && MemoryLayout<Input>.offset(of: \Input.source_width) == 8
            && MemoryLayout<Input>.offset(of: \Input.source_height) == 16
            && MemoryLayout<Input>.offset(of: \Input.maximum_width) == 24
            && MemoryLayout<Output>.offset(of: \Output.abi_version) == 0
            && MemoryLayout<Output>.offset(of: \Output.status) == 4
            && MemoryLayout<Output>.offset(of: \Output.decision) == 8
            && MemoryLayout<Output>.offset(of: \Output.reserved) == 12
            && MemoryLayout<Output>.offset(of: \Output.width) == 16
            && MemoryLayout<Output>.offset(of: \Output.height) == 24
            && MemoryLayout<Output>.offset(of: \Output.rounded_height_bits) == 32
    }

    // Rejection-only correlation. This cannot create a successful fallback result.
    static func accepts(_ input: Input, _ output: Output) -> Bool {
        guard layoutIsExact, input.abi_version == 1, input.reserved == 0,
              output.abi_version == 1, output.status == 1,
              output.decision <= 2, output.reserved == 0 else { return false }
        guard input.source_width >= 2, input.source_height >= 2,
              input.maximum_width >= 2 else {
            return output.decision == 0 && output.width == 0 && output.height == 0
                && output.rounded_height_bits == 0
        }
        let cappedWidth = min(input.source_width, input.maximum_width)
        let width = cappedWidth - cappedWidth % 2
        let roundedHeight = (Double(input.source_height) * Double(width)
            / Double(input.source_width)).rounded()
        guard output.width == width,
              output.rounded_height_bits == roundedHeight.bitPattern else { return false }
        // An exact upper-exclusive check prevents the old native conversion trap.
        guard roundedHeight.isFinite, roundedHeight >= 0,
              roundedHeight < 9_223_372_036_854_775_808.0 else {
            return output.decision == 2 && output.height == 0
        }
        let scaledHeight = Int64(roundedHeight)
        let height = max(2, scaledHeight - scaledHeight % 2)
        return output.decision == 1 && output.height == height
    }
}

struct BelugaRustOutputDimensionsProducer: Sendable {
    typealias Boundary = BelugaRustOutputDimensionsBoundary
    let output: @Sendable (Boundary.Input) -> Boundary.Output

    static let actual = Self(output: { beluga_core_output_dimensions($0) })
}
