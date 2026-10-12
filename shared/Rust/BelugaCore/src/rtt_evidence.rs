//! Copied RTT evidence reducer. Native code owns Instant storage, not evidence authority.
//! Thresholds and selective fast projection are the frozen native policy, not new tuning.

pub const ABI_VERSION: u32 = 1;
const ATTOSECONDS_PER_SECOND: i128 = 1_000_000_000_000_000_000;
const LEASE_ATTOSECONDS: i128 = 4_000_000_000_000_000_000;
const LEGACY: u32 = 0;
const PROVISIONAL_HEALTHY: u32 = 1;
const FRESH_HEALTHY: u32 = 2;
const FRESH_INFLATED: u32 = 3;
const RETAINED_HEALTHY: u32 = 4;
const RETAINED_INFLATED: u32 = 5;
const UNAVAILABLE: u32 = 6;
const EXPIRED: u32 = 7;
const RESEEDED: u32 = 8;
const REORDERED: u32 = 9;
const UNKNOWN: u32 = 0;
const HEALTHY: u32 = 1;
const INFLATED: u32 = 2;
const CLOCK_RETAIN: u32 = 0;
const CLOCK_CLEAR: u32 = 1;
const CLOCK_STAMP_NOW: u32 = 2;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawMeasurement {
    pub fingerprint_words: [u64; 8],
    pub total_bits: u64,
    pub responses: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RawState {
    pub abi_version: u32,
    pub reserved: u32,
    pub baseline_present: u32,
    pub bootstrap_count: u32,
    pub disposition: u32,
    pub health: u32,
    pub uses_native: u32,
    pub provisional: u32,
    pub permits_initial: u32,
    pub distinct_count: u32,
    pub last_measured_present: u32,
    pub advancement_present: u32,
    pub age_present: u32,
    pub watermark_present: u32,
    pub fence_present: u32,
    pub fence_current_present: u32,
    pub reserved2: u32,
    pub reserved3: u32,
    pub baseline_bits: u64,
    pub last_measured_bits: u64,
    pub bootstrap_bits: [u64; 3],
    pub age_seconds: i64,
    pub age_attoseconds: i64,
    pub watermark: RawMeasurement,
    pub fence: RawMeasurement,
    pub fence_current_bits: u64,
}

impl RawState {
    pub const fn initial() -> Self {
        Self {
            abi_version: ABI_VERSION, reserved: 0, baseline_present: 0,
            bootstrap_count: 0, disposition: UNAVAILABLE, health: UNKNOWN,
            uses_native: 0, provisional: 0, permits_initial: 1, distinct_count: 0,
            last_measured_present: 0, advancement_present: 0, age_present: 0,
            watermark_present: 0, fence_present: 0, fence_current_present: 0,
            reserved2: 0, reserved3: 0, baseline_bits: 0, last_measured_bits: 0,
            bootstrap_bits: [0; 3], age_seconds: 0, age_attoseconds: 0,
            watermark: RawMeasurement { fingerprint_words: [0; 8], total_bits: 0, responses: 0 },
            fence: RawMeasurement { fingerprint_words: [0; 8], total_bits: 0, responses: 0 },
            fence_current_bits: 0,
        }
    }
}

impl Default for RawState {
    fn default() -> Self { Self::initial() }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawEvent {
    pub opcode: u32,
    pub observation_kind: u32,
    pub current_present: u32,
    pub fingerprint_length: u32,
    pub route_changed: u32,
    pub reserved: u32,
    pub current_bits: u64,
    pub measurement: RawMeasurement,
    pub age_seconds: i64,
    pub age_attoseconds: i64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RawResult {
    pub abi_version: u32,
    pub status: u32,
    pub fresh_pressure: u32,
    pub allows_upgrade: u32,
    pub legacy_missing: u32,
    pub clock_action: u32,
    pub validation_disposition: u32,
    pub primary_lease_current: u32,
    pub reserved: u32,
    pub reserved2: u32,
    pub state: RawState,
}

impl RawResult {
    fn rejected(before: RawState) -> Self {
        Self { abi_version: ABI_VERSION, status: 0, fresh_pressure: 0,
            allows_upgrade: 0, legacy_missing: 0, clock_action: CLOCK_RETAIN,
            validation_disposition: UNAVAILABLE, primary_lease_current: 0,
            reserved: 0, reserved2: 0, state: before }
    }

    fn accepted(before: RawState) -> Self {
        Self { status: 1, validation_disposition: before.disposition,
            ..Self::rejected(before) }
    }
}

fn positive(bits: u64) -> bool {
    let value = f64::from_bits(bits);
    value.is_finite() && value > 0.0
}

fn duration_valid(seconds: i64, attoseconds: i64) -> bool {
    (attoseconds as i128).abs() < ATTOSECONDS_PER_SECOND
        && !(seconds > 0 && attoseconds < 0)
        && !(seconds < 0 && attoseconds > 0)
}

fn duration_total(seconds: i64, attoseconds: i64) -> i128 {
    (seconds as i128) * ATTOSECONDS_PER_SECOND + attoseconds as i128
}

fn lease_current(before: RawState, event: RawEvent) -> bool {
    let age = duration_total(event.age_seconds, event.age_attoseconds);
    before.advancement_present != 0 && (0..=LEASE_ATTOSECONDS).contains(&age)
}

fn measurement_valid(value: RawMeasurement) -> bool {
    let total = f64::from_bits(value.total_bits);
    total.is_finite() && total >= 0.0 && value.fingerprint_words.iter().all(|word| {
        word.to_le_bytes().iter().all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(byte))
    })
}

// Native Equatable compares the Double total numerically. Do not confuse that identity
// comparison with the raw copied-result equality used by the independent verifier.
fn measurement_equal(left: RawMeasurement, right: RawMeasurement) -> bool {
    left.fingerprint_words == right.fingerprint_words
        && f64::from_bits(left.total_bits) == f64::from_bits(right.total_bits)
        && left.responses == right.responses
}

fn optional_scalar_equal(lp: u32, lb: u64, rp: u32, rb: u64) -> bool {
    lp == rp && (lp == 0 || f64::from_bits(lb) == f64::from_bits(rb))
}

fn state_valid(state: RawState) -> bool {
    if state.abi_version != ABI_VERSION || state.reserved != 0
        || state.reserved2 != 0 || state.reserved3 != 0
        || state.bootstrap_count > 2 || state.distinct_count > 3
        || state.disposition > REORDERED || state.health > INFLATED {
        return false;
    }
    if [state.baseline_present, state.uses_native, state.provisional, state.permits_initial,
        state.last_measured_present, state.advancement_present, state.age_present,
        state.watermark_present, state.fence_present, state.fence_current_present]
        .iter().any(|flag| *flag > 1) { return false; }
    for (present, bits) in [(state.baseline_present, state.baseline_bits),
        (state.last_measured_present, state.last_measured_bits),
        (state.fence_current_present, state.fence_current_bits)] {
        if (present == 0 && bits != 0) || (present != 0 && !positive(bits)) { return false; }
    }
    for (index, bits) in state.bootstrap_bits.iter().enumerate() {
        if index < state.bootstrap_count as usize {
            if !positive(*bits) { return false; }
        } else if *bits != 0 { return false; }
    }
    if state.age_present == 0 {
        if state.age_seconds != 0 || state.age_attoseconds != 0 { return false; }
    } else if !duration_valid(state.age_seconds, state.age_attoseconds) { return false; }
    for (present, measurement) in [(state.watermark_present, state.watermark),
        (state.fence_present, state.fence)] {
        if (present == 0 && measurement != RawMeasurement::default())
            || (present != 0 && !measurement_valid(measurement)) { return false; }
    }
    // Nil fence has no attached scalar. Other mixed legacy/native combinations are allowed.
    state.fence_present != 0 || state.fence_current_present == 0
}

fn event_valid(before: RawState, event: RawEvent) -> bool {
    if event.opcode > 12 || event.observation_kind > 2 || event.current_present > 1
        || event.route_changed > 1 || event.reserved != 0
        || (event.current_present == 0 && event.current_bits != 0)
        || (event.opcode != 1 && event.route_changed != 0) { return false; }
    if event.observation_kind != 2
        && (event.fingerprint_length != 0 || event.measurement != RawMeasurement::default()) {
        return false;
    }
    let ages_used = matches!(event.opcode, 0 | 1 | 10 | 12) && before.advancement_present != 0;
    if ages_used {
        if !duration_valid(event.age_seconds, event.age_attoseconds) { return false; }
    } else if event.age_seconds != 0 || event.age_attoseconds != 0 { return false; }
    match event.opcode {
        0 | 1 => true,
        6 => event.observation_kind == 1 || event.observation_kind == 2,
        11 => match event.observation_kind {
            1 => event.current_present == 0,
            2 => event.fingerprint_length == 64 && measurement_valid(event.measurement)
                && (event.current_present == 0 || positive(event.current_bits)),
            _ => false,
        },
        _ => event.observation_kind == 0 && event.current_present == 0,
    }
}

fn refresh_age(state: &mut RawState, event: RawEvent) {
    state.age_present = state.advancement_present;
    state.age_seconds = if state.age_present != 0 { event.age_seconds } else { 0 };
    state.age_attoseconds = if state.age_present != 0 { event.age_attoseconds } else { 0 };
}

fn revoke(state: &mut RawState) {
    state.health = UNKNOWN;
    state.disposition = UNAVAILABLE;
}

fn clear_reference(state: &mut RawState) {
    state.baseline_present = 0;
    state.baseline_bits = 0;
    state.bootstrap_count = 0;
    state.bootstrap_bits = [0; 3];
    state.distinct_count = 0;
    state.provisional = 0;
}

fn path_reset(state: &mut RawState) {
    clear_reference(state);
    revoke(state);
    state.permits_initial = 0;
}

fn inflated(state: RawState, current: Option<u64>) -> bool {
    match current {
        Some(bits) if state.baseline_present != 0 => {
            let baseline = f64::from_bits(state.baseline_bits);
            let threshold = (baseline * 1.5).max(baseline + 0.050);
            f64::from_bits(bits) > threshold
        }
        _ => false,
    }
}

fn allows_upgrade(state: RawState, current: Option<u64>) -> bool {
    match current {
        Some(bits) if state.baseline_present != 0 => {
            let baseline = f64::from_bits(state.baseline_bits);
            let threshold = (baseline * 1.5).max(baseline + 0.050);
            f64::from_bits(bits) <= threshold
        }
        _ => false,
    }
}

fn update_baseline(state: &mut RawState, current_bits: u64) {
    if state.baseline_present == 0 {
        let index = state.bootstrap_count as usize;
        state.bootstrap_bits[index] = current_bits;
        if index + 1 < 3 {
            state.bootstrap_count += 1;
            return;
        }
        let mut values = state.bootstrap_bits;
        for i in 0..3 {
            for j in (i + 1)..3 {
                if f64::from_bits(values[i]) > f64::from_bits(values[j]) { values.swap(i, j); }
            }
        }
        state.baseline_present = 1;
        state.baseline_bits = values[1];
        state.bootstrap_count = 0;
        state.bootstrap_bits = [0; 3];
    } else {
        let current = f64::from_bits(current_bits);
        let baseline = f64::from_bits(state.baseline_bits);
        if current < baseline {
            state.baseline_bits = current.max(baseline - 0.010).to_bits();
        }
    }
}

fn consume(before: RawState, event: RawEvent) -> RawResult {
    let mut result = RawResult::accepted(before);
    refresh_age(&mut result.state, event);
    let current = if event.current_present != 0 && positive(event.current_bits) {
        Some(event.current_bits)
    } else { None };
    result.state.uses_native = u32::from(event.observation_kind != 0);
    if event.observation_kind == 0 {
        result.state.disposition = LEGACY;
        result.fresh_pressure = u32::from(inflated(result.state, current));
        if let Some(bits) = current { update_baseline(&mut result.state, bits); }
        result.allows_upgrade = u32::from(allows_upgrade(result.state, current));
        result.legacy_missing = u32::from(current.is_none());
        result.validation_disposition = result.state.disposition;
        return result;
    }
    if event.observation_kind != 2 || event.fingerprint_length != 64
        || !measurement_valid(event.measurement) {
        if result.state.fence_present != 0 {
            result.state.watermark_present = 1;
            result.state.watermark = result.state.fence;
            result.state.permits_initial = 0;
        }
        revoke(&mut result.state);
        return result;
    }
    let previous_fence = result.state.fence;
    let had_fence = result.state.fence_present != 0;
    let previous_current_present = result.state.fence_current_present;
    let previous_current_bits = result.state.fence_current_bits;
    result.state.fence_present = 1;
    result.state.fence = event.measurement;
    result.state.fence_current_present = u32::from(current.is_some());
    result.state.fence_current_bits = current.unwrap_or(0);
    if had_fence {
        let replaced_pair = event.measurement.fingerprint_words != previous_fence.fingerprint_words;
        let regressed = f64::from_bits(event.measurement.total_bits) < f64::from_bits(previous_fence.total_bits)
            || event.measurement.responses < previous_fence.responses;
        let contradictory_scalar = measurement_equal(event.measurement, previous_fence)
            && !optional_scalar_equal(u32::from(current.is_some()), current.unwrap_or(0),
                previous_current_present, previous_current_bits);
        if replaced_pair || regressed || contradictory_scalar {
            result.state.watermark_present = 1;
            result.state.watermark = event.measurement;
            result.state.permits_initial = 0;
            revoke(&mut result.state);
            result.state.disposition = if contradictory_scalar { UNAVAILABLE } else { RESEEDED };
            if replaced_pair { clear_reference(&mut result.state); }
            result.validation_disposition = result.state.disposition;
            return result;
        }
    }
    let previous = result.state.watermark;
    let had_watermark = result.state.watermark_present != 0;
    let first_for_peer = !had_watermark && result.state.permits_initial != 0;
    result.state.permits_initial = 0;
    result.state.watermark_present = 1;
    result.state.watermark = event.measurement;
    if had_watermark {
        let replaced_pair = event.measurement.fingerprint_words != previous.fingerprint_words;
        let regressed = f64::from_bits(event.measurement.total_bits) < f64::from_bits(previous.total_bits)
            || event.measurement.responses < previous.responses;
        if replaced_pair || regressed {
            revoke(&mut result.state);
            result.state.disposition = RESEEDED;
            if replaced_pair { clear_reference(&mut result.state); }
            result.validation_disposition = result.state.disposition;
            return result;
        }
    } else if !first_for_peer {
        revoke(&mut result.state);
        result.state.disposition = RESEEDED;
        result.validation_disposition = result.state.disposition;
        return result;
    }
    if current.is_none()
        || f64::from_bits(event.measurement.total_bits) < f64::from_bits(current.unwrap_or(0))
        || (result.state.age_present != 0
            && duration_total(result.state.age_seconds, result.state.age_attoseconds) < 0) {
        revoke(&mut result.state);
        return result;
    }
    let current_bits = current.unwrap_or(0);
    let advanced = if had_watermark {
        f64::from_bits(event.measurement.total_bits) > f64::from_bits(previous.total_bits)
            || event.measurement.responses > previous.responses
    } else { first_for_peer };
    if !advanced {
        if !optional_scalar_equal(1, current_bits,
            result.state.last_measured_present, result.state.last_measured_bits) {
            revoke(&mut result.state);
            return result;
        }
        match result.state.health {
            HEALTHY => {
                if result.state.age_present == 0
                    || duration_total(result.state.age_seconds, result.state.age_attoseconds) > LEASE_ATTOSECONDS {
                    result.state.health = UNKNOWN;
                    result.state.disposition = EXPIRED;
                } else {
                    result.state.disposition = RETAINED_HEALTHY;
                    result.allows_upgrade = 1;
                }
            }
            INFLATED => result.state.disposition = RETAINED_INFLATED,
            _ => result.state.disposition = UNAVAILABLE,
        }
        result.validation_disposition = result.state.disposition;
        return result;
    }
    result.clock_action = CLOCK_STAMP_NOW;
    result.state.advancement_present = 1;
    result.state.last_measured_present = 1;
    result.state.last_measured_bits = current_bits;
    result.state.age_present = 1;
    result.state.age_seconds = 0;
    result.state.age_attoseconds = 0;
    if result.state.baseline_present == 0 {
        result.state.baseline_present = 1;
        result.state.baseline_bits = current_bits;
        result.state.bootstrap_count = 0;
        result.state.bootstrap_bits = [0; 3];
        result.state.distinct_count = 1;
        result.state.provisional = 1;
    } else if !inflated(result.state, Some(current_bits)) {
        update_baseline(&mut result.state, current_bits);
        result.state.distinct_count = (result.state.distinct_count + 1).min(3);
        result.state.provisional = u32::from(result.state.distinct_count < 3);
    }
    let pressure = inflated(result.state, Some(current_bits));
    result.state.health = if pressure { INFLATED } else { HEALTHY };
    result.state.disposition = if pressure { FRESH_INFLATED }
        else if first_for_peer { PROVISIONAL_HEALTHY } else { FRESH_HEALTHY };
    result.fresh_pressure = u32::from(pressure);
    result.allows_upgrade = u32::from(!pressure);
    result.validation_disposition = result.state.disposition;
    result
}

pub fn transition(before: RawState, event: RawEvent) -> RawResult {
    if !state_valid(before) || !event_valid(before, event) { return RawResult::rejected(before); }
    let primary = matches!(event.opcode, 0 | 1 | 10 | 12) && lease_current(before, event);
    if event.opcode == 0 {
        let mut result = consume(before, event);
        result.validation_disposition = result.state.disposition;
        result.primary_lease_current = u32::from(primary);
        return result;
    }
    if event.opcode == 1 {
        let mut facts = event;
        // Fast native callers explicitly map a nil observation to unavailable, never legacy.
        if facts.observation_kind == 0 { facts.observation_kind = 1; }
        let validation = consume(before, facts);
        let mut result = RawResult::accepted(before);
        result.state.fence_present = validation.state.fence_present;
        result.state.fence = validation.state.fence;
        result.state.fence_current_present = validation.state.fence_current_present;
        result.state.fence_current_bits = validation.state.fence_current_bits;
        if validation.allows_upgrade == 0 {
            revoke(&mut result.state);
            result.state.permits_initial = 0;
            if validation.fresh_pressure == 0 {
                result.state.watermark_present = validation.state.watermark_present;
                result.state.watermark = validation.state.watermark;
                result.state.disposition = validation.state.disposition;
                if validation.state.baseline_present == 0 { clear_reference(&mut result.state); }
            }
        } else if event.route_changed != 0 {
            revoke(&mut result.state);
            result.state.permits_initial = 0;
            result.state.watermark_present = validation.state.watermark_present;
            result.state.watermark = validation.state.watermark;
        }
        result.fresh_pressure = validation.fresh_pressure;
        result.allows_upgrade = validation.allows_upgrade;
        result.legacy_missing = validation.legacy_missing;
        result.validation_disposition = validation.state.disposition;
        result.primary_lease_current = u32::from(primary);
        return result;
    }
    let mut result = RawResult::accepted(before);
    match event.opcode {
        2 => revoke(&mut result.state),
        3 => { revoke(&mut result.state); result.state.permits_initial = 0; }
        4 => path_reset(&mut result.state),
        5 => {
            path_reset(&mut result.state);
            result.state.watermark_present = 0;
            result.state.watermark = RawMeasurement::default();
            result.state.fence_present = 0;
            result.state.fence = RawMeasurement::default();
            result.state.fence_current_present = 0;
            result.state.fence_current_bits = 0;
            result.state.advancement_present = 0;
            result.state.last_measured_present = 0;
            result.state.last_measured_bits = 0;
            result.state.age_present = 0;
            result.state.age_seconds = 0;
            result.state.age_attoseconds = 0;
            result.state.permits_initial = 1;
            result.clock_action = CLOCK_CLEAR;
        }
        6 => {
            path_reset(&mut result.state);
            if event.observation_kind == 2 && event.fingerprint_length == 64
                && measurement_valid(event.measurement) {
                result.state.watermark_present = 1;
                result.state.watermark = event.measurement;
            }
        }
        7 => result.state.permits_initial = 1,
        8 => result.state.disposition = REORDERED,
        9 => { revoke(&mut result.state); result.state.uses_native = 1; }
        10 => refresh_age(&mut result.state, event),
        11 => {
            let present = u32::from(event.observation_kind == 2);
            result.state.fence_present = present;
            result.state.fence = if present != 0 { event.measurement } else { RawMeasurement::default() };
            result.state.fence_current_present = event.current_present;
            result.state.fence_current_bits = event.current_bits;
        }
        12 => {}
        _ => unreachable!(),
    }
    result.validation_disposition = result.state.disposition;
    result.primary_lease_current = u32::from(primary);
    result
}

pub fn result_is_valid(before: RawState, event: RawEvent, result: RawResult) -> u32 {
    u32::from(result.status == 1 && transition(before, event) == result)
}
