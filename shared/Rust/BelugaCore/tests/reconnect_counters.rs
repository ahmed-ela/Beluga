use beluga_core::beluga_core_reconnect_counters_step as actual;
use beluga_core::reconnect_counters::{RawEvent, RawResult, RawState};
use std::mem::{align_of, offset_of, size_of};

fn state(next: u64, highest: u64) -> RawState {
    RawState { abi_version: 1, reserved: 0, next_outbound: next, highest_accepted: highest }
}

fn reserve() -> RawEvent { RawEvent { opcode: 0, reserved: 0, request_sequence: 0 } }
fn inbound(sequence: u64) -> RawEvent { RawEvent { opcode: 1, reserved: 0, request_sequence: sequence } }

// Frozen literal numeric guards from RemotePairedDevice.swift 163..223.
// This reference does not reuse the reducer, its domain types or its decisions.
fn original_numeric(before: RawState, event: RawEvent) -> RawResult {
    let mut candidate = before;
    let decision;
    if event.opcode == 0 {
        if before.next_outbound < u64::MAX {
            candidate.next_outbound = before.next_outbound + 1;
            decision = 0;
        } else {
            decision = 1;
        }
    } else if event.request_sequence > before.highest_accepted {
        candidate.highest_accepted = event.request_sequence;
        decision = 0;
    } else {
        decision = 2;
    }
    RawResult { candidate_state: candidate, decision, reserved: 0 }
}

fn assert_invalid(abi: u32, before: RawState, event: RawEvent) {
    assert_eq!(actual(abi, before, event), RawResult {
        candidate_state: before, decision: 3, reserved: 0,
    });
}

#[test]
fn reconnect_copied_layout_and_export_are_exact() {
    assert_eq!((size_of::<RawState>(), align_of::<RawState>()), (24, 8));
    assert_eq!((offset_of!(RawState, abi_version), offset_of!(RawState, reserved),
                offset_of!(RawState, next_outbound), offset_of!(RawState, highest_accepted)), (0, 4, 8, 16));
    assert_eq!((size_of::<RawEvent>(), align_of::<RawEvent>()), (16, 8));
    assert_eq!((offset_of!(RawEvent, opcode), offset_of!(RawEvent, reserved),
                offset_of!(RawEvent, request_sequence)), (0, 4, 8));
    assert_eq!((size_of::<RawResult>(), align_of::<RawResult>()), (32, 8));
    assert_eq!((offset_of!(RawResult, candidate_state), offset_of!(RawResult, decision),
                offset_of!(RawResult, reserved)), (0, 24, 28));
    let before = state(7, 11);
    assert_eq!(actual(1, before, reserve()), RawResult {
        candidate_state: state(8, 11), decision: 0, reserved: 0,
    });
    assert_eq!(before, state(7, 11));
}

#[test]
fn reconnect_all_bounded_numeric_inputs_match_original() {
    for next in 0..=12 {
        for highest in 0..=12 {
            let before = state(next, highest);
            assert_eq!(actual(1, before, reserve()), original_numeric(before, reserve()));
            for sequence in 0..=13 {
                assert_eq!(actual(1, before, inbound(sequence)), original_numeric(before, inbound(sequence)));
            }
        }
    }
}

#[test]
fn reconnect_outbound_zero_and_maximum_preserve_native_ordering() {
    for highest in [0, 1, 71, u64::MAX] {
        let zero = state(0, highest);
        assert_eq!(actual(1, zero, reserve()), RawResult {
            candidate_state: state(1, highest), decision: 0, reserved: 0,
        });
        let last = state(u64::MAX - 1, highest);
        assert_eq!(actual(1, last, reserve()), RawResult {
            candidate_state: state(u64::MAX, highest), decision: 0, reserved: 0,
        });
        let exhausted = state(u64::MAX, highest);
        assert_eq!(actual(1, exhausted, reserve()), RawResult {
            candidate_state: exhausted, decision: 1, reserved: 0,
        });
    }
}

#[test]
fn reconnect_inbound_strict_newer_includes_authenticated_maximum() {
    for highest in [0, 1, 19, (1u64 << 53) + 1, u64::MAX - 1, u64::MAX] {
        let before = state(41, highest);
        assert_eq!(actual(1, before, inbound(highest)), RawResult {
            candidate_state: before, decision: 2, reserved: 0,
        });
        assert_eq!(actual(1, before, inbound(0)), RawResult {
            candidate_state: before, decision: 2, reserved: 0,
        });
        if highest > 0 {
            assert_eq!(actual(1, before, inbound(highest - 1)), RawResult {
                candidate_state: before, decision: 2, reserved: 0,
            });
        }
        if highest < u64::MAX {
            assert_eq!(actual(1, before, inbound(highest + 1)), RawResult {
                candidate_state: state(41, highest + 1), decision: 0, reserved: 0,
            });
            assert_eq!(actual(1, before, inbound(u64::MAX)), RawResult {
                candidate_state: state(41, u64::MAX), decision: 0, reserved: 0,
            });
        }
    }
}

#[test]
fn reconnect_opposite_counters_never_change() {
    for next in [0, 1, 97, (1u64 << 63) + 1, u64::MAX - 1, u64::MAX] {
        for highest in [0, 1, 53, (1u64 << 63) + 7, u64::MAX - 1, u64::MAX] {
            let before = state(next, highest);
            assert_eq!(actual(1, before, reserve()).candidate_state.highest_accepted, highest);
            for sequence in [0, 1, u64::MAX - 1, u64::MAX] {
                assert_eq!(actual(1, before, inbound(sequence)).candidate_state.next_outbound, next);
            }
        }
    }
}

#[test]
fn reconnect_large_u64_values_never_round_through_float() {
    let values = [(1u64 << 53) - 1, 1u64 << 53, (1u64 << 53) + 1,
        (1u64 << 53) + 2, (1u64 << 63) + 1, u64::MAX - 2, u64::MAX - 1, u64::MAX];
    for next in values {
        for highest in values {
            let before = state(next, highest);
            assert_eq!(actual(1, before, reserve()), original_numeric(before, reserve()));
            for sequence in values {
                assert_eq!(actual(1, before, inbound(sequence)), original_numeric(before, inbound(sequence)));
            }
        }
    }
}

#[test]
fn reconnect_rejected_events_preserve_exact_snapshot() {
    for next in [0, 1, u64::MAX - 1, u64::MAX] {
        for highest in [0, 1, (1u64 << 53) + 1, u64::MAX] {
            let before = state(next, highest);
            for sequence in [0, highest] {
                let result = actual(1, before, inbound(sequence));
                assert_eq!(result, RawResult { candidate_state: before, decision: 2, reserved: 0 });
            }
            if next == u64::MAX {
                assert_eq!(actual(1, before, reserve()), RawResult {
                    candidate_state: before, decision: 1, reserved: 0,
                });
            }
        }
    }
}

#[test]
fn reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed() {
    for outer in [0, 1, 2, u32::MAX] {
        for inner in [0, 1, 2, u32::MAX] {
            for state_reserved in [0, 1, u32::MAX] {
                for event_reserved in [0, 1, u32::MAX] {
                    for opcode in [0, 1, 2, u32::MAX] {
                        for sequence in [0, 1, (1u64 << 53) + 1, u64::MAX] {
                            let before = RawState { abi_version: inner, reserved: state_reserved,
                                next_outbound: (1u64 << 63) + 17, highest_accepted: 97 };
                            let event = RawEvent { opcode, reserved: event_reserved, request_sequence: sequence };
                            let valid = outer == 1 && inner == 1 && state_reserved == 0 && event_reserved == 0
                                && (opcode == 1 || (opcode == 0 && sequence == 0));
                            if valid {
                                assert_eq!(actual(outer, before, event), original_numeric(before, event));
                            } else {
                                assert_invalid(outer, before, event);
                            }
                        }
                    }
                }
            }
        }
    }
    for bit in 0..32 {
        let before = state(7, 17);
        assert_invalid(1, RawState { reserved: 1u32 << bit, ..before }, reserve());
        assert_invalid(1, before, RawEvent { reserved: 1u32 << bit, ..reserve() });
        assert_invalid(1, before, RawEvent { opcode: (1u32 << bit) | 2, ..reserve() });
    }
}

#[test]
fn reconnect_outbound_unused_request_sequence_is_rejected() {
    let before = state(23, 47);
    for sequence in (1..=127).chain([(1u64 << 53) + 1, u64::MAX - 1, u64::MAX]) {
        assert_invalid(1, before, RawEvent { request_sequence: sequence, ..reserve() });
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TraceEvent { Outbound(bool), Inbound(u64, bool) }

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Effects { attempted: u64, succeeded: u64, failed: u64 }
impl Effects { fn empty() -> Self { Self { attempted: 0, succeeded: 0, failed: 0 } } }

// Independent frozen caller-order model. "Succeeds" models only a constructor
// return; it does not prove a real signature, role, key or durable storage effect.
fn original_constructor_order(before: RawState, event: TraceEvent, effects: &mut Effects) -> RawState {
    let mut after = before;
    match event {
        TraceEvent::Outbound(succeeds) => {
            if before.next_outbound == u64::MAX { return before; }
            effects.attempted += 1;
            if !succeeds || before.next_outbound == 0 {
                effects.failed += 1;
                return before;
            }
            effects.succeeded += 1;
            after.next_outbound += 1;
        }
        TraceEvent::Inbound(sequence, succeeds) => {
            if sequence <= before.highest_accepted { return before; }
            effects.attempted += 1;
            if !succeeds {
                effects.failed += 1;
                return before;
            }
            effects.succeeded += 1;
            after.highest_accepted = sequence;
        }
    }
    after
}

fn copied_candidate_caller(before: RawState, event: TraceEvent, effects: &mut Effects) -> RawState {
    let (projection, succeeds) = match event {
        TraceEvent::Outbound(ok) => (reserve(), ok),
        TraceEvent::Inbound(sequence, ok) => (inbound(sequence), ok),
    };
    let output = actual(1, before, projection);
    assert_eq!(output, original_numeric(before, projection));
    if output.decision != 0 { return before; }
    effects.attempted += 1;
    if !succeeds || (projection.opcode == 0 && before.next_outbound == 0) {
        effects.failed += 1;
        before
    } else {
        effects.succeeded += 1;
        output.candidate_state
    }
}

#[test]
fn reconnect_candidate_is_committed_only_after_modeled_constructor_success() {
    for before in [state(0, 0), state(1, 0), state(u64::MAX - 1, u64::MAX - 1), state(u64::MAX, u64::MAX)] {
        for event in [TraceEvent::Outbound(false), TraceEvent::Outbound(true),
            TraceEvent::Inbound(u64::MAX, false), TraceEvent::Inbound(u64::MAX, true)] {
            let mut actual_effects = Effects::empty();
            let mut expected_effects = Effects::empty();
            assert_eq!(copied_candidate_caller(before, event, &mut actual_effects),
                original_constructor_order(before, event, &mut expected_effects));
            assert_eq!(actual_effects, expected_effects);
        }
    }
}

#[test]
fn reconnect_bounded_effect_success_and_failure_traces_match_original() {
    let alphabet = [TraceEvent::Outbound(false), TraceEvent::Outbound(true),
        TraceEvent::Inbound(0, false), TraceEvent::Inbound(0, true),
        TraceEvent::Inbound(1, false), TraceEvent::Inbound(1, true),
        TraceEvent::Inbound(2, false), TraceEvent::Inbound(2, true),
        TraceEvent::Inbound(3, false), TraceEvent::Inbound(3, true),
        TraceEvent::Inbound((1u64 << 53) + 1, false), TraceEvent::Inbound((1u64 << 53) + 1, true),
        TraceEvent::Inbound((1u64 << 53) + 2, false), TraceEvent::Inbound((1u64 << 53) + 2, true),
        TraceEvent::Inbound(u64::MAX - 1, false), TraceEvent::Inbound(u64::MAX - 1, true),
        TraceEvent::Inbound(u64::MAX, false), TraceEvent::Inbound(u64::MAX, true)];
    let seeds = [state(0, 0), state(1, 0), state(1, 1),
        state((1u64 << 53) + 1, (1u64 << 53) + 1),
        state(u64::MAX - 1, u64::MAX - 2), state(u64::MAX, u64::MAX)];
    let mut count = 0;
    for seed in seeds {
        for length in 0..=3u32 {
            for mut index in 0..(alphabet.len() as u64).pow(length) {
                let mut stored = seed;
                let mut reference = seed;
                let mut actual_effects = Effects::empty();
                let mut expected_effects = Effects::empty();
                for _ in 0..length {
                    let event = alphabet[(index % alphabet.len() as u64) as usize];
                    index /= alphabet.len() as u64;
                    stored = copied_candidate_caller(stored, event, &mut actual_effects);
                    reference = original_constructor_order(reference, event, &mut expected_effects);
                    assert_eq!(stored, reference);
                    assert_eq!(actual_effects, expected_effects);
                }
                count += 1;
            }
        }
    }
    assert_eq!(count, 37_050);
}

#[test]
fn reconnect_raw_value_copies_remain_independent() {
    let original = state(17, 91);
    let first = original;
    let second = original;
    let outbound = actual(1, first, reserve()).candidate_state;
    let incoming = actual(1, second, inbound(93)).candidate_state;
    assert_eq!(original, state(17, 91));
    assert_eq!(first, original);
    assert_eq!(second, original);
    assert_eq!(outbound, state(18, 91));
    assert_eq!(incoming, state(17, 93));
    assert_eq!(actual(1, outbound, reserve()).candidate_state, state(19, 91));
    assert_eq!(incoming, state(17, 93));
}
