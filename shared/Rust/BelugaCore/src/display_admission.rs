//! Copied display identity/source-dimension decisions, without native IO or ownership.
//! ABI validity is separate from a legitimate false/nil policy outcome.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawDisplayFacts {
    pub abi_version: u32,
    pub reserved: u32,
    pub required_vendor_id: u32,
    pub required_product_id: u32,
    pub required_serial_number: u32,
    pub requires_sole_main_display: u32,
    pub display_id: u32,
    pub observed_vendor_id: u32,
    pub observed_product_id: u32,
    pub observed_serial_number: u32,
    pub is_online: u32,
    pub is_active: u32,
    pub main_display_id: u32,
    /// Meaningful only when online_display_count == 1. Zero is a valid ID.
    pub sole_online_display_id: u32,
    pub online_display_count: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawBooleanDecision {
    pub abi_version: u32,
    /// 0 = invalid bridge input; 1 = accepted, including legitimate false.
    pub status: u32,
    pub value: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawKindFacts {
    pub abi_version: u32,
    pub reserved: u32,
    pub vendor_id: u32,
    pub product_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawKindDecision {
    pub abi_version: u32,
    pub status: u32,
    /// 0 = ordinary logical dimensions; 1 = owned framebuffer dimensions.
    pub kind: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RawSourceFacts {
    pub abi_version: u32,
    pub reserved: u32,
    pub vendor_id: u32,
    pub product_id: u32,
    pub logical_width: i64,
    pub logical_height: i64,
    pub core_graphics_logical_width: i64,
    pub core_graphics_logical_height: i64,
    pub core_graphics_pixel_width: i64,
    pub core_graphics_pixel_height: i64,
    pub filter_content_width: f64,
    pub filter_content_height: f64,
    pub point_pixel_scale: f64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawSourceDecision {
    pub abi_version: u32,
    pub status: u32,
    pub kind: u32,
    /// Presence is not status: valid owned refusal is status=1, presence=0.
    pub has_dimensions: u32,
    /// Canonical zero payload when absent; otherwise exact native i64 values.
    pub width: i64,
    pub height: i64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawStabilityFacts {
    pub abi_version: u32,
    pub reserved: u32,
    pub before_width: i64,
    pub before_height: i64,
    pub after_width: i64,
    pub after_height: i64,
}

const _: [(); 64] = [(); size_of::<RawDisplayFacts>()];
const _: [(); 8] = [(); align_of::<RawDisplayFacts>()];
const _: [(); 16] = [(); size_of::<RawBooleanDecision>()];
const _: [(); 4] = [(); align_of::<RawBooleanDecision>()];
const _: [(); 16] = [(); size_of::<RawKindFacts>()];
const _: [(); 4] = [(); align_of::<RawKindFacts>()];
const _: [(); 16] = [(); size_of::<RawKindDecision>()];
const _: [(); 4] = [(); align_of::<RawKindDecision>()];
const _: [(); 88] = [(); size_of::<RawSourceFacts>()];
const _: [(); 8] = [(); align_of::<RawSourceFacts>()];
const _: [(); 32] = [(); size_of::<RawSourceDecision>()];
const _: [(); 8] = [(); align_of::<RawSourceDecision>()];
const _: [(); 40] = [(); size_of::<RawStabilityFacts>()];
const _: [(); 8] = [(); align_of::<RawStabilityFacts>()];

fn envelope(version: u32, reserved: u32) -> bool {
    version == ABI_VERSION && reserved == 0
}

fn source_kind(vendor: u32, product: u32) -> u32 {
    if vendor == 0x6f73 && (product == 0x1717 || product == 0x1718) { 1 } else { 0 }
}

fn boolean_decision(valid: bool, value: bool) -> RawBooleanDecision {
    RawBooleanDecision { abi_version: ABI_VERSION, status: u32::from(valid),
        value: if valid { u32::from(value) } else { 0 }, reserved: 0 }
}

pub fn requirement_admission(raw: RawDisplayFacts) -> RawBooleanDecision {
    if !envelope(raw.abi_version, raw.reserved)
        || raw.requires_sole_main_display > 1 || raw.is_online > 1 || raw.is_active > 1 {
        return boolean_decision(false, false);
    }
    if raw.is_online == 0 || raw.is_active == 0
        || raw.observed_vendor_id != raw.required_vendor_id
        || raw.observed_product_id != raw.required_product_id
        || raw.observed_serial_number != raw.required_serial_number {
        return boolean_decision(true, false);
    }
    if raw.requires_sole_main_display == 0 {
        return boolean_decision(true, true);
    }
    boolean_decision(true, raw.main_display_id == raw.display_id
        && raw.online_display_count == 1 && raw.sole_online_display_id == raw.display_id)
}

pub fn dimension_kind(raw: RawKindFacts) -> RawKindDecision {
    if !envelope(raw.abi_version, raw.reserved) {
        return RawKindDecision { abi_version: ABI_VERSION, status: 0, kind: 0, reserved: 0 };
    }
    RawKindDecision { abi_version: ABI_VERSION, status: 1,
        kind: source_kind(raw.vendor_id, raw.product_id), reserved: 0 }
}

pub fn source_dimensions(raw: RawSourceFacts) -> RawSourceDecision {
    if !envelope(raw.abi_version, raw.reserved) {
        return RawSourceDecision { abi_version: ABI_VERSION, status: 0, kind: 0,
            has_dimensions: 0, width: 0, height: 0 };
    }
    let kind = source_kind(raw.vendor_id, raw.product_id);
    // Preserve the original branch priority: irrelevant NaN/Infinity/zero
    // metadata and the ENTIRE signed native dimension domain are untouched.
    if kind == 0 {
        return RawSourceDecision { abi_version: ABI_VERSION, status: 1, kind,
            has_dimensions: 1, width: raw.logical_width, height: raw.logical_height };
    }
    let refused = RawSourceDecision { abi_version: ABI_VERSION, status: 1, kind,
        has_dimensions: 0, width: 0, height: 0 };
    if raw.logical_width < 2 || raw.logical_height < 2
        || raw.logical_width > 32_768 || raw.logical_height > 32_768
        || !raw.filter_content_width.is_finite() || !raw.filter_content_height.is_finite()
        || !raw.point_pixel_scale.is_finite()
        || !(1.0..=4.0).contains(&raw.point_pixel_scale)
        || raw.core_graphics_logical_width < 2 || raw.core_graphics_logical_height < 2
        || raw.core_graphics_pixel_width < 2 || raw.core_graphics_pixel_height < 2
        || raw.core_graphics_pixel_width > 32_768 || raw.core_graphics_pixel_height > 32_768
        || raw.logical_width != raw.core_graphics_logical_width
        || raw.logical_height != raw.core_graphics_logical_height
        || (raw.filter_content_width - raw.logical_width as f64).abs() > 0.5
        || (raw.filter_content_height - raw.logical_height as f64).abs() > 0.5 {
        return refused;
    }
    RawSourceDecision { abi_version: ABI_VERSION, status: 1, kind, has_dimensions: 1,
        width: raw.core_graphics_pixel_width, height: raw.core_graphics_pixel_height }
}

pub fn dimensions_stable(raw: RawStabilityFacts) -> RawBooleanDecision {
    if !envelope(raw.abi_version, raw.reserved) {
        return boolean_decision(false, false);
    }
    boolean_decision(true, raw.before_width == raw.after_width
        && raw.before_height == raw.after_height)
}
