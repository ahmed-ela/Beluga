//! Copied diagnostics only. Text rendering stays native and is not policy authority.
use super::dependencies::{RelativeTime, Scalar, ATTO};
use super::policy::{Policy, Report, Tier};

pub fn bounded_integer(value: Option<f64>) -> Option<u64> {
    let value = value?;
    if !value.is_finite() || value < 0.0 { return None; }
    let rounded = value.round();
    if rounded < 18_446_744_073_709_551_616.0 { Some(rounded as u64) } else { None }
}
pub fn bounded_microseconds(value: Option<Scalar>) -> Option<u64> {
    let seconds = value?.value();
    if !seconds.is_finite() || seconds < 0.0 { return None; }
    bounded_integer(Some(seconds * 1_000_000.0))
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FloorIdentity { NotChecked, Fresh, RejectedOrder, RejectedTimestamp }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FloorReason { NotEvaluated, RejectedOrder, RejectedTimestamp, InactiveVisibility,
    Consumed, Disproved, NotFloor, ExistingProbe, RttBlocked, InvalidBandwidth,
    OrdinaryProbeEligible, NoHeadroom, NoNewPackets, QueueBlocked, Cooldown,
    FirstWitness, TooEarly, BandwidthFalling, Qualified, Admitted }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum QueueKind { NotChecked, Measured, NoNewPackets, UnavailableOrReset }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Trend { Unknown, Falling, Flat, Rising }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FloorDiagnostics {
    pub show_epoch: Option<u64>, pub reserved: bool, pub active: bool, pub consumed: bool,
    pub disproved: bool, pub cooldown_remaining: i64, pub collection_sequence: Option<u64>,
    pub previous_regular_sequence: Option<u64>, pub previous_regular_report_microseconds: Option<u64>,
    pub capacity_report_microseconds: Option<u64>, pub native_report_microseconds: Option<u64>,
    pub current_bandwidth: Option<Scalar>, pub first_bandwidth: Option<Scalar>,
    pub witness_age_microseconds: Option<u64>, pub before_total: i64, pub proposed_total: i64,
    pub trend: Trend, pub identity: FloorIdentity, pub reason: FloorReason, pub queue_kind: QueueKind,
    pub queue_microseconds: Option<u64>, pub rtt_disposition: Option<u32>, pub rtt_allows_upgrade: Option<bool>,
}
impl FloorDiagnostics {
    pub fn new(policy: &Policy, report: Report, now: RelativeTime) -> Self {
        let current = report.bandwidth.filter(|v| v.positive());
        let first = policy.floor_first_witness.map(|v| v.bandwidth).filter(|v| v.positive());
        let trend = match (current, first) {
            (Some(current), Some(first)) => if current.value() < first.value() { Trend::Falling }
                else if current == first { Trend::Flat } else { Trend::Rising },
            _ => Trend::Unknown,
        };
        let age = policy.floor_first_witness.map(|v| now - v.observed_at).filter(|v| *v >= 0);
        let age_microseconds = age.and_then(|v| bounded_integer(Some(
            (v / ATTO) as f64 * 1_000_000.0 + (v % ATTO) as f64 / 1_000_000_000_000.0)));
        let cap = policy.current_recommendation().maximum_total;
        Self { show_epoch: policy.floor_show, reserved: policy.floor_reserved, active: policy.floor_active,
            consumed: policy.floor_attempt_consumed, disproved: policy.below_reserve_disproved,
            cooldown_remaining: policy.probe_cooldown, collection_sequence: report.collection_sequence,
            previous_regular_sequence: policy.floor_regular_sequence,
            previous_regular_report_microseconds: bounded_integer(policy.floor_regular_timestamp.map(|v| v.value())),
            capacity_report_microseconds: bounded_integer(policy.capacity_timestamp.map(|v| v.value())),
            native_report_microseconds: bounded_integer(report.native_timestamp.map(|v| v.value())),
            current_bandwidth: current, first_bandwidth: first, witness_age_microseconds: age_microseconds,
            before_total: cap, proposed_total: cap, trend, identity: FloorIdentity::NotChecked,
            reason: FloorReason::NotEvaluated, queue_kind: QueueKind::NotChecked, queue_microseconds: None,
            rtt_disposition: None, rtt_allows_upgrade: None }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CapacityReason { Inactive, Expired, RejectedReport, RoundTripTime, RouteChanged,
    MissingPrimaryEvidence, ImmediateQueue, MissingBandwidth, BandwidthCollapse,
    QueueWithheld, GrowthVetoed, BandwidthNotAdvanced, AtCeiling, Increased }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CapacityDiagnostics {
    pub reason: CapacityReason, pub origin: Option<Tier>, pub collection_sequence: Option<u64>,
    pub previous_native_microseconds: Option<u64>, pub native_microseconds: Option<u64>,
    pub before_total: i64, pub proposed_total: i64, pub collapse_threshold: Option<u64>,
    pub delta_packets: Option<u64>, pub delta_delay_microseconds: Option<u64>,
    pub average_queue_microseconds: Option<u64>,
}
impl CapacityDiagnostics {
    pub fn new(policy: &Policy, report: Report) -> Self {
        let cap = policy.current_recommendation().maximum_total;
        Self { reason: CapacityReason::RejectedReport, origin: policy.probe_origin,
            collection_sequence: report.collection_sequence,
            previous_native_microseconds: bounded_integer(policy.capacity_timestamp.map(|v| v.value())),
            native_microseconds: bounded_integer(report.native_timestamp.map(|v| v.value())),
            before_total: cap, proposed_total: cap, collapse_threshold: None, delta_packets: None,
            delta_delay_microseconds: None, average_queue_microseconds: None }
    }
    pub fn record_queue(&mut self, previous_packets: Option<u64>, previous_delay: Option<Scalar>,
                        packets: Option<u64>, delay: Option<Scalar>) {
        let (Some(previous_packets), Some(packets), Some(previous_delay), Some(delay)) =
            (previous_packets, packets, previous_delay, delay) else { return; };
        let previous_delay = previous_delay.value(); let delay = delay.value();
        if packets < previous_packets || !previous_delay.is_finite() || previous_delay < 0.0
            || !delay.is_finite() || delay < previous_delay { return; }
        let count = packets - previous_packets;
        self.delta_packets = Some(count);
        self.delta_delay_microseconds = bounded_integer(Some((delay - previous_delay) * 1_000_000.0));
        if count > 0 {
            self.average_queue_microseconds = bounded_integer(Some((delay - previous_delay) / count as f64 * 1_000_000.0));
        }
    }
}
