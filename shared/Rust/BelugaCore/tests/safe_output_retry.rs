//! Independent frozen-native reference and literal traces against the *actual*
//! future beluga_core production module. This file is not enrolled or executed.
use beluga_core::safe_output_retry::{initialize, transition, RawConfig, RawState};
use std::mem::{align_of, offset_of, size_of};

fn config(failed: i64, backoff: i64, cooldown: i64) -> RawConfig {
    RawConfig { abi_version: 1, reserved: 0, maximum_failed_attempt_count: failed,
        maximum_backoff_tick_count: backoff, capped_cooldown_tick_count: cooldown }
}
fn state(failed: i64, backoff: i64, cooldown: i64) -> RawState {
    let initialized = initialize(config(failed, backoff, cooldown));
    assert_eq!((initialized.status, initialized.tick_decision), (1, 0));
    initialized.state
}
fn counts(raw: RawState) -> (i64, i64, i64) {
    (raw.failed_attempt_count, raw.backoff_tick_count, raw.cooldown_tick_count)
}

// Independent literal result table for native 3/4/3. Columns:
// event(Tick=1,Failure=2,Reset=3), failed, backoff, cooldown, decision.
const TRACE: [(u32, i64, i64, i64, u32); 19] = [
    (1, 0, 0, 0, 2), (2, 1, 1, 0, 0), (1, 1, 0, 0, 1),
    (1, 1, 0, 0, 2), (2, 2, 2, 0, 0), (1, 2, 1, 0, 1),
    (1, 2, 0, 0, 1), (1, 2, 0, 0, 2), (2, 3, 0, 3, 0),
    (2, 3, 0, 3, 0), (1, 3, 0, 2, 1), (1, 3, 0, 1, 1),
    (1, 3, 0, 0, 1), (1, 0, 0, 0, 2), (2, 1, 1, 0, 0),
    (3, 0, 0, 0, 0), (1, 0, 0, 0, 2), (3, 0, 0, 0, 0),
    (1, 0, 0, 0, 2),
];

#[test]
fn literal_cooldown_does_not_probe_one_tick_early_or_rearm_at_cap() {
    let mut raw = state(3, 4, 3);
    for &(event, failed, backoff, cooldown, decision) in &TRACE {
        let result = transition(raw, event);
        assert_eq!((result.status, result.tick_decision), (1, decision));
        assert_eq!(counts(result.state), (failed, backoff, cooldown));
        raw = result.state;
    }
}

#[test]
fn default_failure_budget_has_exact_literal_delays_and_sixty_tick_cooldown() {
    let mut raw = state(6, 16, 60);
    for expected in [(1, 1, 0), (2, 2, 0), (3, 4, 0), (4, 8, 0), (5, 16, 0), (6, 0, 60)] {
        let result = transition(raw, 2);
        assert_eq!((result.status, result.tick_decision), (1, 0));
        assert_eq!(counts(result.state), expected);
        raw = result.state;
    }
    for _ in 0..60 {
        let result = transition(raw, 1);
        assert_eq!((result.status, result.tick_decision), (1, 1));
        raw = result.state;
    }
    assert_eq!(counts(raw), (6, 0, 0));
    let result = transition(raw, 1);
    assert_eq!((result.status, result.tick_decision, counts(result.state)), (1, 2, (0, 0, 0)));
}

#[test]
fn signed_constructor_preserves_every_limit_domain_and_clamps_to_one() {
    let cases = [(i64::MIN, 1), (-9, 1), (0, 1), (1, 1), (2, 2), (i64::MAX, i64::MAX)];
    for &(failed, expected_failed) in &cases {
        for &(backoff, expected_backoff) in &cases {
            for &(cooldown, expected_cooldown) in &cases {
                let result = initialize(config(failed, backoff, cooldown));
                assert_eq!((result.status, result.tick_decision), (1, 0));
                assert_eq!((result.state.maximum_failed_attempt_count,
                    result.state.maximum_backoff_tick_count, result.state.capped_cooldown_tick_count),
                    (expected_failed, expected_backoff, expected_cooldown));
                assert_eq!(counts(result.state), (0, 0, 0));
            }
        }
    }
}

#[test]
fn one_attempt_budget_and_maximum_counters_do_not_overflow() {
    let raw = state(1, i64::MAX, i64::MAX);
    let capped = transition(raw, 2);
    assert_eq!(counts(capped.state), (1, 0, i64::MAX));
    assert_eq!(transition(capped.state, 2).state, capped.state);
    let waited = transition(capped.state, 1);
    assert_eq!((waited.status, waited.tick_decision, counts(waited.state)),
        (1, 1, (1, 0, i64::MAX - 1)));
    let mut near_cap = state(i64::MAX, i64::MAX, i64::MAX);
    near_cap.failed_attempt_count = i64::MAX - 1;
    let cap = transition(near_cap, 2);
    assert_eq!((cap.status, counts(cap.state)), (1, (i64::MAX, 0, i64::MAX)));
}

#[test]
fn failure_when_exhausted_preserves_partially_elapsed_cooldown() {
    let initial = state(1, 8, 5);
    let capped = transition(initial, 2).state;
    let waited = transition(transition(capped, 1).state, 1).state;
    assert_eq!(counts(waited), (1, 0, 3));
    let failure = transition(waited, 2);
    assert_eq!((failure.status, failure.tick_decision, failure.state), (1, 0, waited));
}

#[test]
fn exponent_caps_at_thirty_without_an_invented_sixty_four_entry_limit() {
    for prior in [30, 31, 32, 64, 999, i64::MAX - 2] {
        let mut raw = state(i64::MAX, i64::MAX, 5);
        raw.failed_attempt_count = prior;
        let result = transition(raw, 2);
        assert_eq!((result.status, result.tick_decision), (1, 0));
        assert_eq!(counts(result.state), (prior + 1, 1_073_741_824, 0));
    }
    let mut raw = state(1000, 7, 5);
    raw.failed_attempt_count = 998;
    assert_eq!(counts(transition(raw, 2).state), (999, 7, 0));
}

#[test]
fn copies_are_independent_and_read_only_ticks_do_not_create_failure_history() {
    let original = state(6, 16, 60);
    let copy = original;
    let failure = transition(original, 2);
    assert_eq!(counts(copy), (0, 0, 0));
    assert_eq!(counts(failure.state), (1, 1, 0));
    assert_eq!(transition(copy, 1).state, copy);
    let reset = transition(failure.state, 3);
    assert_eq!(reset.state, copy);
    assert_eq!(counts(failure.state), (1, 1, 0));
}

#[derive(Clone, Copy)]
struct FrozenNative {
    maximum_failed: i64, maximum_backoff: i64, capped_cooldown: i64,
    failed: i64, backoff: i64, cooldown: i64,
}
impl FrozenNative {
    // A direct frozen transcription of the pinned Swift initializer and methods;
    // it does not call Config, Policy, RawState decoding, or a production helper.
    fn new(maximum_failed: i64, maximum_backoff: i64, capped_cooldown: i64) -> Self {
        Self { maximum_failed: if maximum_failed < 1 { 1 } else { maximum_failed },
            maximum_backoff: if maximum_backoff < 1 { 1 } else { maximum_backoff },
            capped_cooldown: if capped_cooldown < 1 { 1 } else { capped_cooldown },
            failed: 0, backoff: 0, cooldown: 0 }
    }
    fn tick(&mut self) -> bool {
        if self.failed >= self.maximum_failed {
            if self.cooldown != 0 { self.cooldown -= 1; return false; }
            self.failed = 0;
            self.backoff = 0;
        }
        if self.backoff != 0 { self.backoff -= 1; return false; }
        true
    }
    fn failure(&mut self) {
        if self.failed >= self.maximum_failed { return; }
        self.failed += 1;
        if self.failed >= self.maximum_failed {
            self.backoff = 0; self.cooldown = self.capped_cooldown; return;
        }
        let exponent = if self.failed - 1 > 30 { 30 } else { self.failed - 1 };
        let exponential = 1_i64 << exponent;
        self.backoff = if exponential < self.maximum_backoff { exponential } else { self.maximum_backoff };
    }
    fn reset(&mut self) { self.failed = 0; self.backoff = 0; self.cooldown = 0; }
}

#[test]
fn bounded_adversarial_histories_match_frozen_original_not_production_helpers() {
    let configs = [(6, 16, 60), (3, 4, 3), (1, 1, 1), (75, 9, 2),
        (i64::MIN, -2, 0), (i64::MAX, i64::MAX, i64::MAX)];
    for &(f, b, c) in &configs {
        for words in [[2, 2, 2, 1, 1, 3, 1], [1, 1, 2, 1, 2, 1, 1], [2, 2, 2, 2, 2, 2, 2]] {
            let mut original = FrozenNative::new(f, b, c);
            let mut raw = state(f, b, c);
            for index in 0..560 {
                let event = words[index % words.len()];
                let expected_decision = match event {
                    1 => if original.tick() { 2 } else { 1 },
                    2 => { original.failure(); 0 },
                    3 => { original.reset(); 0 },
                    _ => unreachable!(),
                };
                let result = transition(raw, event);
                assert_eq!((result.status, result.tick_decision), (1, expected_decision));
                assert_eq!(counts(result.state), (original.failed, original.backoff, original.cooldown));
                raw = result.state;
            }
        }
    }
}

#[test]
fn invalid_bridge_never_resets_or_normalizes_a_state() {
    let initial = state(3, 4, 3);
    let pending = transition(initial, 2).state;
    let cap = transition(transition(pending, 2).state, 2).state;
    for base in [initial, pending, cap] {
        for event in [0, 4, u32::MAX] {
            let result = transition(base, event);
            assert_eq!((result.status, result.tick_decision, result.state), (0, 0, base));
        }
        let mut malformed = Vec::new();
        for version in [0, 2, u32::MAX] { let mut x = base; x.abi_version = version; malformed.push(x); }
        for reserved in [1, u32::MAX] { let mut x = base; x.reserved = reserved; malformed.push(x); }
        for maximum in [i64::MIN, -1, 0] {
            let mut x = base; x.maximum_failed_attempt_count = maximum; malformed.push(x);
            let mut x = base; x.maximum_backoff_tick_count = maximum; malformed.push(x);
            let mut x = base; x.capped_cooldown_tick_count = maximum; malformed.push(x);
        }
        let mut x = base; x.failed_attempt_count = -1; malformed.push(x);
        let mut x = base; x.failed_attempt_count = 4; malformed.push(x);
        let mut x = base; x.backoff_tick_count = -1; malformed.push(x);
        let mut x = base; x.cooldown_tick_count = -1; malformed.push(x);
        let mut x = base; x.cooldown_tick_count = 4; malformed.push(x);
        for raw in malformed {
            for event in [1, 2, 3] {
                let result = transition(raw, event);
                assert_eq!((result.status, result.tick_decision, result.state), (0, 0, raw));
            }
        }
    }
    for mut raw in [initial, pending, cap] {
        raw.backoff_tick_count = 9;
        assert_eq!(transition(raw, 1).state, raw);
        assert_eq!(transition(raw, 1).status, 0);
    }
    for mut raw in [initial, pending] {
        raw.cooldown_tick_count = 1;
        assert_eq!(transition(raw, 3).state, raw);
        assert_eq!(transition(raw, 3).status, 0);
    }
}

#[test]
fn invalid_constructor_envelope_preserves_requested_values_but_is_not_accepted() {
    for requested in [config(i64::MIN, -7, i64::MAX), config(3, 4, 3)] {
        // Independent envelope faults are required: corrupting both together
        // would not detect replacing the production OR guard with AND.
        for (version, reserved) in [
            (0, 0), (2, 0), (u32::MAX, 0),
            (1, 1), (1, 2), (1, u32::MAX), (9, 17),
        ] {
            let mut raw = requested;
            raw.abi_version = version;
            raw.reserved = reserved;
            // Literal copied-state contract, not production normalization:
            // even Int.min / negative requested limits remain exact on refusal.
            let expected = RawState {
                abi_version: version,
                reserved,
                maximum_failed_attempt_count: requested.maximum_failed_attempt_count,
                maximum_backoff_tick_count: requested.maximum_backoff_tick_count,
                capped_cooldown_tick_count: requested.capped_cooldown_tick_count,
                failed_attempt_count: 0,
                backoff_tick_count: 0,
                cooldown_tick_count: 0,
            };
            let result = initialize(raw);
            assert_eq!((result.status, result.tick_decision), (0, 0));
            assert_eq!(result.state, expected);
        }
    }
}

#[test]
fn copied_abi_layout_and_c_exports_bind_actual_production() {
    assert_eq!((size_of::<RawConfig>(), size_of::<RawState>(), align_of::<RawState>()), (32, 56, 8));
    assert_eq!(offset_of!(RawState, failed_attempt_count), 32);
    assert_eq!(size_of::<beluga_core::safe_output_retry::RawResult>(), 64);
    let input = config(3, 4, 3);
    assert_eq!(beluga_core::beluga_core_safe_output_retry_initialize(input), initialize(input));
    let raw = state(3, 4, 3);
    assert_eq!(beluga_core::beluga_core_safe_output_retry_transition(raw, 2), transition(raw, 2));
}
