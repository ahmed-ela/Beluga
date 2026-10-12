// Rejection-only custody for copied scalar decisions; never a successful Swift fallback.
import BelugaCore

enum ScreenVideoDisplayAdmissionBridgeError: Error, Equatable, Sendable {
    case invalidBridge
}

enum BelugaRustDisplayAdmissionBoundary {
    typealias RequirementInput = beluga_core_display_requirement_facts_t
    typealias BooleanOutput = beluga_core_display_boolean_decision_t
    typealias KindInput = beluga_core_source_dimension_kind_facts_t
    typealias KindOutput = beluga_core_source_dimension_kind_decision_t
    typealias SourceInput = beluga_core_source_dimensions_facts_t
    typealias SourceOutput = beluga_core_source_dimensions_decision_t
    typealias StabilityInput = beluga_core_source_dimensions_stability_facts_t

    static var layoutIsExact: Bool {
        MemoryLayout<Int>.size == 8
            && MemoryLayout<RequirementInput>.size == 64 && MemoryLayout<RequirementInput>.stride == 64
            && MemoryLayout<RequirementInput>.alignment == 8
            && MemoryLayout<BooleanOutput>.size == 16 && MemoryLayout<BooleanOutput>.stride == 16
            && MemoryLayout<BooleanOutput>.alignment == 4
            && MemoryLayout<KindInput>.size == 16 && MemoryLayout<KindInput>.stride == 16
            && MemoryLayout<KindInput>.alignment == 4
            && MemoryLayout<KindOutput>.size == 16 && MemoryLayout<KindOutput>.stride == 16
            && MemoryLayout<KindOutput>.alignment == 4
            && MemoryLayout<SourceInput>.size == 88 && MemoryLayout<SourceInput>.stride == 88
            && MemoryLayout<SourceInput>.alignment == 8
            && MemoryLayout<SourceOutput>.size == 32 && MemoryLayout<SourceOutput>.stride == 32
            && MemoryLayout<SourceOutput>.alignment == 8
            && MemoryLayout<StabilityInput>.size == 40 && MemoryLayout<StabilityInput>.stride == 40
            && MemoryLayout<StabilityInput>.alignment == 8
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.abi_version) == 0
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.reserved) == 4
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.required_vendor_id) == 8
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.required_product_id) == 12
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.required_serial_number) == 16
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.requires_sole_main_display) == 20
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.display_id) == 24
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.observed_vendor_id) == 28
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.observed_product_id) == 32
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.observed_serial_number) == 36
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.is_online) == 40
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.is_active) == 44
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.main_display_id) == 48
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.sole_online_display_id) == 52
            && MemoryLayout<RequirementInput>.offset(of: \RequirementInput.online_display_count) == 56
            && MemoryLayout<BooleanOutput>.offset(of: \BooleanOutput.abi_version) == 0
            && MemoryLayout<BooleanOutput>.offset(of: \BooleanOutput.status) == 4
            && MemoryLayout<BooleanOutput>.offset(of: \BooleanOutput.value) == 8
            && MemoryLayout<BooleanOutput>.offset(of: \BooleanOutput.reserved) == 12
            && MemoryLayout<KindInput>.offset(of: \KindInput.abi_version) == 0
            && MemoryLayout<KindInput>.offset(of: \KindInput.reserved) == 4
            && MemoryLayout<KindInput>.offset(of: \KindInput.vendor_id) == 8
            && MemoryLayout<KindInput>.offset(of: \KindInput.product_id) == 12
            && MemoryLayout<KindOutput>.offset(of: \KindOutput.abi_version) == 0
            && MemoryLayout<KindOutput>.offset(of: \KindOutput.status) == 4
            && MemoryLayout<KindOutput>.offset(of: \KindOutput.kind) == 8
            && MemoryLayout<KindOutput>.offset(of: \KindOutput.reserved) == 12
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.abi_version) == 0
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.reserved) == 4
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.vendor_id) == 8
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.product_id) == 12
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.logical_width) == 16
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.logical_height) == 24
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.core_graphics_logical_width) == 32
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.core_graphics_logical_height) == 40
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.core_graphics_pixel_width) == 48
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.core_graphics_pixel_height) == 56
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.filter_content_width) == 64
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.filter_content_height) == 72
            && MemoryLayout<SourceInput>.offset(of: \SourceInput.point_pixel_scale) == 80
            && MemoryLayout<SourceOutput>.offset(of: \SourceOutput.abi_version) == 0
            && MemoryLayout<SourceOutput>.offset(of: \SourceOutput.status) == 4
            && MemoryLayout<SourceOutput>.offset(of: \SourceOutput.kind) == 8
            && MemoryLayout<SourceOutput>.offset(of: \SourceOutput.has_dimensions) == 12
            && MemoryLayout<SourceOutput>.offset(of: \SourceOutput.width) == 16
            && MemoryLayout<SourceOutput>.offset(of: \SourceOutput.height) == 24
            && MemoryLayout<StabilityInput>.offset(of: \StabilityInput.abi_version) == 0
            && MemoryLayout<StabilityInput>.offset(of: \StabilityInput.reserved) == 4
            && MemoryLayout<StabilityInput>.offset(of: \StabilityInput.before_width) == 8
            && MemoryLayout<StabilityInput>.offset(of: \StabilityInput.before_height) == 16
            && MemoryLayout<StabilityInput>.offset(of: \StabilityInput.after_width) == 24
            && MemoryLayout<StabilityInput>.offset(of: \StabilityInput.after_height) == 32
    }

    private static func envelope(_ version: UInt32, _ reserved: UInt32) -> Bool {
        layoutIsExact && version == 1 && reserved == 0
    }
    private static func owned(_ vendor: UInt32, _ product: UInt32) -> Bool {
        vendor == 0x6F73 && (product == 0x1717 || product == 0x1718)
    }
    private static func booleanOutput(_ output: BooleanOutput) -> Bool {
        output.abi_version == 1 && output.status == 1 && output.value <= 1 && output.reserved == 0
    }

    static func acceptsRequirement(_ input: RequirementInput, _ output: BooleanOutput) -> Bool {
        guard envelope(input.abi_version, input.reserved), input.requires_sole_main_display <= 1,
              input.is_online <= 1, input.is_active <= 1, booleanOutput(output) else { return false }
        let identity = input.is_online == 1 && input.is_active == 1
            && input.required_vendor_id == input.observed_vendor_id
            && input.required_product_id == input.observed_product_id
            && input.required_serial_number == input.observed_serial_number
        let topology = input.requires_sole_main_display == 0
            || (input.main_display_id == input.display_id && input.online_display_count == 1
                && input.sole_online_display_id == input.display_id)
        return output.value == (identity && topology ? 1 : 0)
    }

    static func acceptsKind(_ input: KindInput, _ output: KindOutput) -> Bool {
        guard envelope(input.abi_version, input.reserved), output.abi_version == 1,
              output.status == 1, output.kind <= 1, output.reserved == 0 else { return false }
        return output.kind == (owned(input.vendor_id, input.product_id) ? 1 : 0)
    }

    static func acceptsSource(_ input: SourceInput, _ output: SourceOutput) -> Bool {
        guard envelope(input.abi_version, input.reserved), output.abi_version == 1,
              output.status == 1, output.kind <= 1, output.has_dimensions <= 1 else { return false }
        let isOwned = owned(input.vendor_id, input.product_id)
        guard output.kind == (isOwned ? 1 : 0) else { return false }
        // Original priority: do not validate irrelevant metadata or clamp ordinary signed dimensions.
        if !isOwned {
            return output.has_dimensions == 1 && output.width == input.logical_width
                && output.height == input.logical_height
        }
        let valid = input.logical_width >= 2 && input.logical_height >= 2
            && input.logical_width <= 32_768 && input.logical_height <= 32_768
            && input.filter_content_width.isFinite && input.filter_content_height.isFinite
            && input.point_pixel_scale.isFinite && (1 ... 4).contains(input.point_pixel_scale)
            && input.core_graphics_logical_width >= 2 && input.core_graphics_logical_height >= 2
            && input.core_graphics_pixel_width >= 2 && input.core_graphics_pixel_height >= 2
            && input.core_graphics_pixel_width <= 32_768 && input.core_graphics_pixel_height <= 32_768
            && input.logical_width == input.core_graphics_logical_width
            && input.logical_height == input.core_graphics_logical_height
            && abs(input.filter_content_width - Double(input.logical_width)) <= 0.5
            && abs(input.filter_content_height - Double(input.logical_height)) <= 0.5
        if valid {
            return output.has_dimensions == 1 && output.width == input.core_graphics_pixel_width
                && output.height == input.core_graphics_pixel_height
        }
        return output.has_dimensions == 0 && output.width == 0 && output.height == 0
    }

    static func acceptsStability(_ input: StabilityInput, _ output: BooleanOutput) -> Bool {
        guard envelope(input.abi_version, input.reserved), booleanOutput(output) else { return false }
        let equal = input.before_width == input.after_width && input.before_height == input.after_height
        return output.value == (equal ? 1 : 0)
    }
}

struct BelugaRustDisplayAdmissionProducer: Sendable {
    typealias Boundary = BelugaRustDisplayAdmissionBoundary
    let requirement: @Sendable (Boundary.RequirementInput) -> Boundary.BooleanOutput
    let kind: @Sendable (Boundary.KindInput) -> Boundary.KindOutput
    let source: @Sendable (Boundary.SourceInput) -> Boundary.SourceOutput
    let stability: @Sendable (Boundary.StabilityInput) -> Boundary.BooleanOutput
    static let actual = Self(
        requirement: { beluga_core_display_requirement_admission($0) },
        kind: { beluga_core_source_dimension_kind($0) },
        source: { beluga_core_source_dimensions($0) },
        stability: { beluga_core_source_dimensions_stable($0) }
    )
}
