//! Pure calibrated tier arithmetic; copied facts contain no platform ownership or clocks.
//! Integer scaling precedes floating conversion. Deliberately keep the original binary64
//! operation order, including the independently configured cap and ceiling artifacts.

pub const ABI_VERSION: u32 = 1;
const BASELINE_MAXIMUM_VIDEO: u64 = 9_344_000;
const MINIMUM_VIDEO: u64 = 32_000;
const AUDIO_CONTROL_RESERVE: f64 = 320_000.0;
const DEMAND_HEADROOM: f64 = 1.25;
const UPGRADE_MARGIN: f64 = 1.25;
const TOTAL_RTP_HEADROOM: f64 = 1.35;
const BASIS_POINTS: [u32; 8] = [10_000, 6_700, 4_200, 2_100, 800, 300, 100, 25];

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawTierDemandFacts {
    pub abi_version: u32,
    pub configured_cap: u32,
    pub current_tier: u32,
    pub bandwidth_present: u32,
    pub bandwidth_bits: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawTierDemandProjection {
    pub abi_version: u32,
    pub status: u32,
    pub current_tier: u32,
    pub reserved: u32,
    pub basis_points: u32,
    pub baseline_video: u32,
    pub maximum_tier_video: u32,
    pub maximum_video: u32,
    pub maximum_total_rtp: u32,
    pub minimum_sustainable: u32,
    pub initial_tier: u32,
    pub sustainable_tier: u32,
    pub upgrade_present: u32,
    pub upgrade_tier: u32,
    pub direct_threshold_present: u32,
    pub direct_threshold_minimum: u32,
    pub required_bitrate_bits: u64,
    pub direct_threshold_bits: u64,
}

impl RawTierDemandProjection {
    pub const fn rejected() -> Self {
        Self { abi_version: ABI_VERSION, status: 0, current_tier: 0, reserved: 0,
            basis_points: 0, baseline_video: 0, maximum_tier_video: 0,
            maximum_video: 0, maximum_total_rtp: 0, minimum_sustainable: 0,
            initial_tier: 0, sustainable_tier: 0, upgrade_present: 0,
            upgrade_tier: 0, direct_threshold_present: 0, direct_threshold_minimum: 0,
            required_bitrate_bits: 0, direct_threshold_bits: 0 }
    }
}

#[derive(Clone, Copy)]
struct Tier(u8);

impl Tier {
    const ALL: [Self; 8] = [Self(0), Self(1), Self(2), Self(3), Self(4), Self(5), Self(6), Self(7)];
    const AUDIO_PRIORITY: Self = Self(7);

    fn checked(value: u32) -> Option<Self> {
        if value <= 7 { Some(Self(value as u8)) } else { None }
    }

    fn ordinal(self) -> u32 { u32::from(self.0) }
    fn basis_points(self) -> u32 { BASIS_POINTS[usize::from(self.0)] }

    fn baseline_video(self) -> u32 {
        // At most 9344000 * 10000. Preserve integer division before Double conversion.
        (BASELINE_MAXIMUM_VIDEO * u64::from(self.basis_points()) / 10_000)
            .max(MINIMUM_VIDEO) as u32
    }

    fn required(self) -> f64 {
        f64::from(self.baseline_video()) * DEMAND_HEADROOM + AUDIO_CONTROL_RESERVE
    }

    fn adjacent_higher(self) -> Option<Self> {
        if self.0 == 0 { None } else { Some(Self(self.0 - 1)) }
    }
}

struct Facts {
    configured_cap: u32,
    current_tier: Tier,
    bandwidth: Option<f64>,
}

impl Facts {
    fn checked(raw: RawTierDemandFacts) -> Option<Self> {
        if raw.abi_version != ABI_VERSION || raw.configured_cap == 0 { return None; }
        let current_tier = Tier::checked(raw.current_tier)?;
        let bandwidth = match raw.bandwidth_present {
            0 if raw.bandwidth_bits == 0 => None,
            1 => {
                let value = f64::from_bits(raw.bandwidth_bits);
                if !value.is_finite() || value <= 0.0 { return None; }
                Some(value)
            }
            _ => return None,
        };
        Some(Self { configured_cap: raw.configured_cap, current_tier, bandwidth })
    }

    fn maximum_tier_video(&self) -> u32 {
        let budget = (f64::from(self.configured_cap) - AUDIO_CONTROL_RESERVE).max(0.0)
            / DEMAND_HEADROOM;
        // This floor fits u32 and the final value cannot exceed the configured cap.
        (budget.floor() as u64).max(MINIMUM_VIDEO)
            .min(u64::from(self.configured_cap)) as u32
    }

    fn initial_tier(&self) -> Tier {
        let ceiling = Tier::ALL.into_iter().find(|tier|
            tier.required() <= f64::from(self.configured_cap))
            .unwrap_or(Tier::AUDIO_PRIORITY);
        Tier(ceiling.0.max(5))
    }

    fn sustainable_tier(&self) -> Tier {
        let Some(bandwidth) = self.bandwidth else { return Tier::AUDIO_PRIORITY; };
        Tier::ALL.into_iter().find(|tier|
            tier.required() <= f64::from(self.configured_cap)
                && bandwidth >= tier.required())
            .unwrap_or(Tier::AUDIO_PRIORITY)
    }

    fn upgrade_tier(&self) -> Option<Tier> {
        let bandwidth = self.bandwidth?;
        Tier::ALL.into_iter().find(|tier| {
            if tier.ordinal() >= self.current_tier.ordinal() { return false; }
            let required = tier.required();
            if required > f64::from(self.configured_cap) { return false; }
            let threshold = (required * UPGRADE_MARGIN).min(f64::from(self.configured_cap));
            bandwidth >= threshold
        })
    }
}

pub fn project(raw: RawTierDemandFacts) -> RawTierDemandProjection {
    let Some(facts) = Facts::checked(raw) else { return RawTierDemandProjection::rejected(); };
    let tier = facts.current_tier;
    let required = tier.required();
    let maximum_tier_video = facts.maximum_tier_video();
    // Reference scaling uses full-width arithmetic even at UInt32.max configured caps.
    let reference_maximum = BASELINE_MAXIMUM_VIDEO.max(u64::from(maximum_tier_video));
    let scaled_video = (reference_maximum * u64::from(tier.basis_points()) / 10_000)
        .max(MINIMUM_VIDEO);
    let maximum_video = scaled_video.min(u64::from(maximum_tier_video)) as u32;
    let maximum_total_rtp = (required * TOTAL_RTP_HEADROOM)
        .min(f64::from(facts.configured_cap)).ceil() as u32;
    let direct_threshold = tier.adjacent_higher().and_then(|next| {
        let next_required = next.required();
        if next_required > f64::from(facts.configured_cap) { return None; }
        Some((next_required * UPGRADE_MARGIN).min(f64::from(facts.configured_cap)))
    });
    let upgrade = facts.upgrade_tier();
    RawTierDemandProjection {
        abi_version: ABI_VERSION, status: 1, current_tier: tier.ordinal(), reserved: 0,
        basis_points: tier.basis_points(), baseline_video: tier.baseline_video(),
        maximum_tier_video, maximum_video, maximum_total_rtp,
        minimum_sustainable: required.ceil() as u32,
        initial_tier: facts.initial_tier().ordinal(),
        sustainable_tier: facts.sustainable_tier().ordinal(),
        upgrade_present: u32::from(upgrade.is_some()),
        upgrade_tier: upgrade.map(Tier::ordinal).unwrap_or(0),
        direct_threshold_present: u32::from(direct_threshold.is_some()),
        direct_threshold_minimum: direct_threshold.map(|value| value.ceil() as u32).unwrap_or(0),
        required_bitrate_bits: required.to_bits(),
        direct_threshold_bits: direct_threshold.map(f64::to_bits).unwrap_or(0),
    }
}

/// Exact raw-field recomputation is rejection-only authority, never a fallback policy.
pub fn projection_is_valid(facts: RawTierDemandFacts, result: RawTierDemandProjection) -> u32 {
    let expected = project(facts);
    u32::from(expected.status == 1 && expected == result)
}
