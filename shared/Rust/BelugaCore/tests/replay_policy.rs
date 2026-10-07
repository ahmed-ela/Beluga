use beluga_core::{beluga_core_signaling_replay_initial, beluga_core_signaling_replay_step};
use beluga_core::replay_policy::{initial, step, Decision, RawResult, RawState};

/// Independent flat freeze of the original Swift's four branches. This is
/// test-only expected output, not a fallback or raw-state parser for the core.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct FrozenSwift {
    highest: Option<u64>,
    received: u64,
}

impl FrozenSwift {
    fn empty() -> Self { Self { highest: None, received: 0 } }
    fn accept(&mut self, sequence: u64) -> Decision {
        let Some(highest) = self.highest else {
            self.highest = Some(sequence);
            self.received = 1;
            return Decision::Accepted;
        };
        if sequence > highest {
            let advance = sequence - highest;
            self.received = if advance >= 64 { 1 } else { (self.received << advance) | 1 };
            self.highest = Some(sequence);
            return Decision::Accepted;
        }
        let age = highest - sequence;
        if age >= 64 { return Decision::OutsideWindow; }
        let mask = 1_u64 << age;
        if self.received & mask != 0 { return Decision::Duplicate; }
        self.received |= mask;
        Decision::Accepted
    }
    fn raw(self) -> RawState {
        RawState { abi_version: 1, has_highest: if self.highest.is_some() { 1 } else { 0 },
                   highest: self.highest.unwrap_or(0), bitmap: self.received }
    }
}

/// Independent rejection-only boundary specification. It checks every copied
/// claim against exact input and returns only a bool; it never manufactures a
/// successful native state or mutates/retries/reset a native owner.
fn correlated(before: RawState, sequence: u64, out: RawResult) -> bool {
    if before.abi_version != 1 || out.reserved != 0 || out.state.abi_version != 1 {
        return false;
    }
    if before.has_highest == 0 {
        return before.highest == 0 && before.bitmap == 0 && out.decision == 0 &&
            out.state == RawState { abi_version: 1, has_highest: 1, highest: sequence, bitmap: 1 };
    }
    if before.has_highest != 1 || before.bitmap & 1 != 1 { return false; }
    if before.highest < 63 && before.bitmap >> (before.highest + 1) != 0 { return false; }
    if sequence > before.highest {
        let advance = sequence - before.highest;
        let bits = if advance >= 64 { 1 } else { (before.bitmap << advance) | 1 };
        return out.decision == 0 && out.state == RawState {
            abi_version: 1, has_highest: 1, highest: sequence, bitmap: bits };
    }
    let age = before.highest - sequence;
    if age >= 64 { return out.decision == 2 && out.state == before; }
    let mask = 1_u64 << age;
    if before.bitmap & mask != 0 { return out.decision == 1 && out.state == before; }
    out.decision == 0 && out.state == RawState {
        abi_version: 1, has_highest: 1, highest: before.highest, bitmap: before.bitmap | mask }
}

fn apply(state: &mut RawState, input: u64) -> Decision {
    let out = step(1, *state, input);
    assert!(correlated(*state, input, out));
    *state = out.state;
    match out.decision {
        0 => Decision::Accepted, 1 => Decision::Duplicate,
        2 => Decision::OutsideWindow, _ => panic!("legitimate state cannot become malformed"),
    }
}

#[test]
fn zero_is_valid_then_duplicate_is_unchanged() {
    let mut state = initial();
    assert_eq!(apply(&mut state, 0), Decision::Accepted);
    assert_eq!(state, RawState { abi_version: 1, has_highest: 1, highest: 0, bitmap: 1 });
    let before = state;
    assert_eq!(apply(&mut state, 0), Decision::Duplicate);
    assert_eq!(state, before);
}

#[test]
fn first_maximum_sequence_is_valid_without_allocation() {
    let mut state = initial();
    assert_eq!(apply(&mut state, u64::MAX), Decision::Accepted);
    assert_eq!(state.highest, u64::MAX);
    assert_eq!(state.bitmap, 1);
}

#[test]
fn age_63_is_admitted_and_age_64_rejects_without_change() {
    let mut state = initial(); apply(&mut state, 64);
    assert_eq!(apply(&mut state, 1), Decision::Accepted);
    assert_eq!(state.bitmap, (1_u64 << 63) | 1);
    let before = state;
    assert_eq!(apply(&mut state, 0), Decision::OutsideWindow);
    assert_eq!(state, before);
}

#[test]
fn advance_63_retains_only_in_window_history() {
    let mut state = initial(); apply(&mut state, 0); apply(&mut state, 63);
    assert_eq!(state.bitmap, (1_u64 << 63) | 1);
    assert_eq!(apply(&mut state, 0), Decision::Duplicate);
}

#[test]
fn advance_64_does_not_shift_by_64_and_retires_history() {
    let mut state = initial(); apply(&mut state, 0); apply(&mut state, 64);
    assert_eq!(state.bitmap, 1);
    assert_eq!(apply(&mut state, 0), Decision::OutsideWindow);
}

#[test]
fn advance_above_window_remains_one_bit() {
    let mut state = initial(); apply(&mut state, 8); apply(&mut state, 100);
    assert_eq!(state.bitmap, 1);
    assert_eq!(apply(&mut state, 36), Decision::OutsideWindow);
    assert_eq!(apply(&mut state, 37), Decision::Accepted);
}

#[test]
fn maximum_adjacent_arithmetic_never_wraps() {
    let mut state = initial(); apply(&mut state, u64::MAX - 64);
    apply(&mut state, u64::MAX - 1); apply(&mut state, u64::MAX);
    assert_eq!(state.highest, u64::MAX);
    assert_eq!(state.bitmap, 3);
    assert_eq!(apply(&mut state, u64::MAX - 63), Decision::Accepted);
    let before = state;
    assert_eq!(apply(&mut state, u64::MAX - 64), Decision::OutsideWindow);
    assert_eq!(state, before);
}

#[test]
fn reordered_packets_accumulate_without_erasing_seen_bits() {
    let mut state = initial(); apply(&mut state, 10);
    for input in [8, 9, 7, 1, 0] { assert_eq!(apply(&mut state, input), Decision::Accepted); }
    let before = state;
    for input in [10, 8, 9, 7, 1, 0] {
        assert_eq!(apply(&mut state, input), Decision::Duplicate);
        assert_eq!(state, before);
    }
}

#[test]
fn value_copies_are_independent_and_reset_is_a_fresh_value() {
    let mut original = initial(); apply(&mut original, 8);
    let mut copy = original;
    apply(&mut copy, 9);
    assert_eq!(original.highest, 8);
    assert_eq!(copy.highest, 9);
    let mut replacement_owner = initial();
    assert_eq!(apply(&mut replacement_owner, 8), Decision::Accepted);
    assert_eq!(apply(&mut original, 8), Decision::Duplicate);
}

#[test]
fn bounded_event_traces_match_frozen_original_at_every_step() {
    const INPUTS: [u64; 9] = [0, 1, 2, 62, 63, 64, 65, u64::MAX - 1, u64::MAX];
    fn walk(state: RawState, reference: FrozenSwift, remaining: u8) {
        if remaining == 0 { return; }
        for sequence in INPUTS {
            let before = state;
            let mut next_ref = reference;
            let decision = next_ref.accept(sequence);
            let out = step(1, state, sequence);
            assert_eq!(out.decision, decision as u32);
            assert_eq!(out.state, next_ref.raw());
            assert!(correlated(before, sequence, out));
            if decision != Decision::Accepted { assert_eq!(out.state, before); }
            walk(out.state, next_ref, remaining - 1);
        }
    }
    walk(initial(), FrozenSwift::empty(), 5);
}

#[test]
fn all_boundary_sequence_pairs_match_reference() {
    let inputs = [0, 1, 2, 31, 32, 62, 63, 64, 65, 127, 128,
                  u64::MAX - 65, u64::MAX - 64, u64::MAX - 63, u64::MAX - 1, u64::MAX];
    for highest in inputs {
        for sequence in inputs {
            let mut expected = FrozenSwift::empty(); expected.accept(highest);
            let before = step(1, initial(), highest).state;
            let out = step(1, before, sequence);
            assert_eq!(out.decision, expected.accept(sequence) as u32);
            assert_eq!(out.state, expected.raw());
            assert!(correlated(before, sequence, out));
        }
    }
}

#[test]
fn malformed_raw_state_is_unchanged_and_never_accepted() {
    for before in [
        RawState { abi_version: 0, has_highest: 0, highest: 0, bitmap: 0 },
        RawState { abi_version: 1, has_highest: 2, highest: 0, bitmap: 0 },
        RawState { abi_version: 1, has_highest: 0, highest: 1, bitmap: 0 },
        RawState { abi_version: 1, has_highest: 0, highest: 0, bitmap: 1 },
        RawState { abi_version: 1, has_highest: 1, highest: 10, bitmap: 0 },
        RawState { abi_version: 1, has_highest: 1, highest: 10, bitmap: 2 },
        RawState { abi_version: 1, has_highest: 1, highest: 0, bitmap: 3 },
    ] {
        let out = step(1, before, 7);
        assert_eq!(out, RawResult { state: before, decision: 3, reserved: 0 });
        assert!(!correlated(before, 7, out));
    }
}

#[test]
fn unknown_abi_rejects_without_canonicalizing_or_resetting() {
    let before = step(1, initial(), 99).state;
    for abi in [0, 2, u32::MAX] {
        assert_eq!(step(abi, before, 100), RawResult { state: before, decision: 3, reserved: 0 });
    }
}

#[test]
fn copied_scalar_layout_is_24_and_32_bytes() {
    assert_eq!(std::mem::size_of::<RawState>(), 24);
    assert_eq!(std::mem::align_of::<RawState>(), 8);
    assert_eq!(std::mem::size_of::<RawResult>(), 32);
    assert_eq!(std::mem::align_of::<RawResult>(), 8);
    assert_eq!(std::mem::offset_of!(RawState, abi_version), 0);
    assert_eq!(std::mem::offset_of!(RawState, has_highest), 4);
    assert_eq!(std::mem::offset_of!(RawState, highest), 8);
    assert_eq!(std::mem::offset_of!(RawState, bitmap), 16);
    assert_eq!(std::mem::offset_of!(RawResult, state), 0);
    assert_eq!(std::mem::offset_of!(RawResult, decision), 24);
    assert_eq!(std::mem::offset_of!(RawResult, reserved), 28);
    assert_eq!(beluga_core::ABI_VERSION, 1);
    assert_eq!(beluga_core_signaling_replay_initial(), initial());
    for sequence in [0, 1, 63, 64, u64::MAX - 64, u64::MAX] {
        let before = beluga_core_signaling_replay_initial();
        let output = beluga_core_signaling_replay_step(1, before, sequence);
        assert_eq!(output, step(1, before, sequence));
        assert_eq!(beluga_core_signaling_replay_step(2, output.state, sequence),
                   step(2, output.state, sequence));
    }
}

#[test]
fn canonical_looking_accepted_duplicate_is_rejected_by_boundary() {
    let before = step(1, initial(), 9).state;
    let forged = RawResult { state: before, decision: 0, reserved: 0 };
    assert!(!correlated(before, 9, forged));
    assert!(correlated(before, 9, step(1, before, 9)));
}

#[test]
fn canonical_looking_history_clearing_accepted_output_is_rejected() {
    let mut before = initial(); apply(&mut before, 9); apply(&mut before, 8);
    let forged = RawResult {
        state: RawState { abi_version: 1, has_highest: 1, highest: 10, bitmap: 1 },
        decision: 0, reserved: 0,
    };
    assert!(!correlated(before, 10, forged));
    assert!(correlated(before, 10, step(1, before, 10)));
}

#[test]
fn output_for_different_input_cannot_authorize_current_packet() {
    let before = step(1, initial(), 100).state;
    let unrelated = step(1, before, 101);
    assert!(!correlated(before, 102, unrelated));
    assert!(!correlated(before, 100, unrelated));
}

#[test]
fn rejected_outputs_cannot_mutate_history_or_change_error_class() {
    let before = step(1, initial(), 100).state;
    let rejected = step(1, before, 100);
    let cleared = RawResult { state: initial(), ..rejected };
    assert!(!correlated(before, 100, cleared));
    assert!(!correlated(before, 100, RawResult { decision: 2, ..rejected }));
    assert!(!correlated(before, 0, RawResult { decision: 1, state: before, reserved: 0 }));
}

#[test]
fn unknown_disposition_and_reserved_output_are_never_committed() {
    let before = initial(); let good = step(1, before, 0);
    assert!(correlated(before, 0, good));
    for decision in [3, 4, u32::MAX] {
        assert!(!correlated(before, 0, RawResult { decision, ..good }));
    }
    assert!(!correlated(before, 0, RawResult { reserved: 1, ..good }));
}

#[test]
fn initial_output_must_not_invent_populated_or_stale_owner_history() {
    assert_eq!(initial(), FrozenSwift::empty().raw());
    let before = initial();
    assert!(!correlated(before, 0, RawResult { state: initial(), decision: 0, reserved: 0 }));
    let stale = step(1, initial(), 99);
    assert!(!correlated(before, 0, stale));
}

#[test]
fn scalar_call_order_model_opens_first_but_burns_before_post_decode_semantic_validation() {
    // This freezes caller ordering only; booleans are NOT real authentication.
    fn receive(state: &mut RawState, opened: bool, payload_semantically_valid: bool, seq: u64)
        -> Result<(), &'static str> {
        // The native cipher.open includes AEAD authentication AND JSON decoding.
        if !opened { return Err("open"); }
        let out = step(1, *state, seq);
        if out.decision != 0 { return Err("replay"); }
        *state = out.state;
        if !payload_semantically_valid { return Err("payload-semantic"); }
        Ok(())
    }
    let mut state = initial();
    assert_eq!(receive(&mut state, false, true, 0), Err("open"));
    assert_eq!(state, initial());
    assert_eq!(receive(&mut state, true, false, 0), Err("payload-semantic"));
    assert_eq!(state, step(1, initial(), 0).state);
    assert_eq!(receive(&mut state, true, true, 0), Err("replay"));
}
