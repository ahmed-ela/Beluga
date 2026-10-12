//! Full selected-source to encoder-dimension policy; no native capture or ownership.
//! The formerly trapping rounded-height conversion is a distinct typed refusal.
#![forbid(unsafe_code)]

use core::mem::{align_of, size_of};

pub const ABI_VERSION: u32 = 1;
pub const DOUBLE_I64_UPPER_EXCLUSIVE: f64 = 9_223_372_036_854_775_808.0;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawOutputFacts {
    pub abi_version: u32,
    pub reserved: u32,
    pub source_width: i64,
    pub source_height: i64,
    pub maximum_width: i64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawOutputDecision {
    pub abi_version: u32,
    /// 0 = malformed copied input; 1 = a legitimate policy outcome.
    pub status: u32,
    /// 0 = original invalidDimensions; 1 = dimensions; 2 = unrepresentableScaledHeight.
    pub decision: u32,
    pub reserved: u32,
    pub width: i64,
    /// Zero when no dimensions are returned. Not a saturated conversion.
    pub height: i64,
    /// Exact bits of the original rounded f64, or canonical zero before arithmetic.
    pub rounded_height_bits: u64,
}

const _: [(); 32] = [(); size_of::<RawOutputFacts>()];
const _: [(); 8] = [(); align_of::<RawOutputFacts>()];
const _: [(); 40] = [(); size_of::<RawOutputDecision>()];
const _: [(); 8] = [(); align_of::<RawOutputDecision>()];

fn empty(status: u32) -> RawOutputDecision {
    RawOutputDecision { abi_version: ABI_VERSION, status, decision: 0,
        reserved: 0, width: 0, height: 0, rounded_height_bits: 0 }
}

pub fn output_dimensions(raw: RawOutputFacts) -> RawOutputDecision {
    if raw.abi_version != ABI_VERSION || raw.reserved != 0 {
        return empty(0);
    }
    // Original three guards precede every conversion and arithmetic operation.
    if raw.source_width < 2 || raw.source_height < 2 || raw.maximum_width < 2 {
        return empty(1);
    }
    let capped_width = raw.source_width.min(raw.maximum_width);
    let width = capped_width - capped_width % 2;
    // Keep the original conversion and left-to-right multiply/divide order.
    let rounded_height = ((raw.source_height as f64) * (width as f64)
        / (raw.source_width as f64)).round();
    if !rounded_height.is_finite() || rounded_height < 0.0
        || rounded_height >= DOUBLE_I64_UPPER_EXCLUSIVE {
        return RawOutputDecision { abi_version: ABI_VERSION, status: 1,
            decision: 2, reserved: 0, width, height: 0,
            rounded_height_bits: rounded_height.to_bits() };
    }
    // Rust's saturating float cast is used only after exact representability admission.
    let scaled_height = rounded_height as i64;
    let height = 2.max(scaled_height - scaled_height % 2);
    RawOutputDecision { abi_version: ABI_VERSION, status: 1, decision: 1,
        reserved: 0, width, height, rounded_height_bits: rounded_height.to_bits() }
}
