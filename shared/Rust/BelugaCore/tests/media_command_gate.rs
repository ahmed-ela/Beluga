use beluga_core::{beluga_core_media_command_gate_step as step,
    beluga_core_media_command_gate_result_is_valid as verify};
use beluga_core::media_command_gate::{RawState as S, RawEvent as E, RawResult as R};
use std::mem::{align_of, offset_of, size_of};

// Original Swift algebra, expressed independently from the new implementation.
// Widen-before-mask preserves the frozen `&+= 1` without calling Rust wrapping_add.
fn original_increment(value: u64) -> u64 { ((u128::from(value) + 1) & u128::from(u64::MAX)) as u64 }
fn state(open: bool, lifecycle: u64, epoch: u64) -> S {
    S { abi_version: 1, is_open: u32::from(open), lifecycle, command_epoch: epoch }
}
fn event(opcode: u32, context: bool, lifecycle: u64, epoch: u64) -> E {
    E { opcode, context_is_current: u32::from(context), reserved0: 0, reserved1: 0,
        candidate_lifecycle: lifecycle, candidate_command_epoch: epoch }
}
fn mutation(opcode: u32) -> E { event(opcode, false, 0, 0) }
fn canonical_denial() -> R {
    R { abi_version: 1, status: 0, allowed: 0, reserved: 0,
        state: S { abi_version: 1, is_open: 0, lifecycle: 0, command_epoch: 0 } }
}
fn original_valid_step(mut s: S, e: E) -> R {
    let allowed = match e.opcode {
        0 => { s.lifecycle = original_increment(s.lifecycle); s.command_epoch = original_increment(s.command_epoch);
            s.is_open = 1; false },
        1 => { s.lifecycle = original_increment(s.lifecycle); s.command_epoch = original_increment(s.command_epoch);
            s.is_open = 0; false },
        2 => { s.command_epoch = original_increment(s.command_epoch); false },
        3 => s.is_open == 1 && s.lifecycle == e.candidate_lifecycle,
        4 => s.is_open == 1 && e.context_is_current == 1,
        5 => s.is_open == 1 && s.lifecycle == e.candidate_lifecycle
            && s.command_epoch == e.candidate_command_epoch && e.context_is_current == 1,
        _ => panic!("only valid original operations enter this reference"),
    };
    R { abi_version: 1, status: 1, allowed: u32::from(allowed), reserved: 0, state: s }
}
fn checked(s: S, e: E) -> R {
    let actual = step(s, e); // Actual exported C symbol first, never a pure-helper substitute.
    assert_eq!(actual, original_valid_step(s, e));
    assert_eq!(verify(s, e, actual), 1);
    actual
}
fn denied(s: S, e: E) {
    let actual = step(s, e);
    assert_eq!(actual, canonical_denial());
    assert_eq!(verify(s, e, actual), 0);
}

#[test]
fn media_command_gate_layouts_and_all_fifteen_offsets_are_literal() {
    assert_eq!((size_of::<S>(), align_of::<S>()), (24, 8));
    assert_eq!((size_of::<E>(), align_of::<E>()), (32, 8));
    assert_eq!((size_of::<R>(), align_of::<R>()), (40, 8));
    assert_eq!(offset_of!(S, abi_version), 0); assert_eq!(offset_of!(S, is_open), 4);
    assert_eq!(offset_of!(S, lifecycle), 8); assert_eq!(offset_of!(S, command_epoch), 16);
    assert_eq!(offset_of!(E, opcode), 0); assert_eq!(offset_of!(E, context_is_current), 4);
    assert_eq!(offset_of!(E, reserved0), 8); assert_eq!(offset_of!(E, reserved1), 12);
    assert_eq!(offset_of!(E, candidate_lifecycle), 16); assert_eq!(offset_of!(E, candidate_command_epoch), 24);
    assert_eq!(offset_of!(R, abi_version), 0); assert_eq!(offset_of!(R, status), 4);
    assert_eq!(offset_of!(R, allowed), 8); assert_eq!(offset_of!(R, reserved), 12);
    assert_eq!(offset_of!(R, state), 16);
}

#[test]
fn media_command_gate_initial_closed_state_refuses_all_queries_without_fault() {
    let s = state(false, 0, 0);
    for e in [event(3, false, 0, 0), event(4, true, 0, 0), event(5, true, 0, 0)] {
        let result = checked(s, e);
        assert_eq!((result.status, result.allowed, result.state), (1, 0, s));
    }
}

#[test]
fn media_command_gate_open_and_close_literals_increment_both_counters() {
    let opened = checked(state(false, 7, 19), mutation(0));
    assert_eq!(opened, R { abi_version: 1, status: 1, allowed: 0, reserved: 0,
        state: state(true, 8, 20) });
    assert_eq!(checked(opened.state, mutation(0)).state, state(true, 9, 21));
    let closed = checked(opened.state, mutation(1));
    assert_eq!(closed.state, state(false, 9, 21));
    assert_eq!(checked(closed.state, mutation(1)).state, state(false, 10, 22));
}

#[test]
fn media_command_gate_invalidation_changes_only_command_epoch() {
    for open in [false, true] {
        let before = state(open, 21, 39);
        let next = checked(before, mutation(2)).state;
        assert_eq!(next, state(open, 21, 40));
        assert_eq!(checked(next, event(3, false, 21, 0)).allowed, u32::from(open));
        assert_eq!(checked(next, event(5, true, 21, 39)).allowed, 0);
        assert_eq!(checked(next, event(5, true, 21, 40)).allowed, u32::from(open));
    }
}

#[test]
fn media_command_gate_lifecycle_query_ignores_command_epoch() {
    for epoch in [0, 1, u64::MAX] {
        let before = state(true, 41, epoch);
        assert_eq!(checked(before, event(3, false, 41, 0)).allowed, 1);
        assert_eq!(checked(before, event(3, false, 40, 0)).allowed, 0);
    }
}

#[test]
fn media_command_gate_capture_uses_only_open_and_native_membership_fact() {
    for open in [false, true] {
        for membership in [false, true] {
            for (lifecycle, epoch) in [(0, 0), (u64::MAX, 1), (1, u64::MAX)] {
                let before = state(open, lifecycle, epoch);
                let result = checked(before, event(4, membership, 0, 0));
                assert_eq!(result.allowed, u32::from(open && membership));
                assert_eq!(result.state, before);
            }
        }
    }
}

#[test]
fn media_command_gate_admission_requires_all_four_original_conditions() {
    for open in [false, true] {
        for member in [false, true] {
            for lifecycle in [6, 7] {
                for epoch in [10, 11] {
                    let actual = checked(state(open, 7, 11), event(5, member, lifecycle, epoch));
                    assert_eq!(actual.allowed, u32::from(open && member && lifecycle == 7 && epoch == 11));
                }
            }
        }
    }
}

#[test]
fn media_command_gate_accepted_queries_leave_every_state_word_unchanged() {
    for open in [false, true] {
        for lifecycle in [0, 1, u64::MAX] {
            let before = state(open, lifecycle, 0x8000_0000_0000_0011);
            for e in [event(3, false, lifecycle, 0), event(3, false, original_increment(lifecycle), 0),
                event(4, false, 0, 0), event(4, true, 0, 0),
                event(5, true, lifecycle, before.command_epoch), event(5, false, lifecycle, 0)] {
                assert_eq!(checked(before, e).state, before);
            }
        }
    }
}

#[test]
fn media_command_gate_open_wraps_each_full_uint64_counter_independently() {
    for lifecycle in [0, 1, u64::MAX - 1, u64::MAX] {
        for epoch in [0, 1, u64::MAX - 1, u64::MAX] {
            assert_eq!(checked(state(false, lifecycle, epoch), mutation(0)).state,
                state(true, original_increment(lifecycle), original_increment(epoch)));
        }
    }
    assert_eq!(checked(state(false, u64::MAX, u64::MAX), mutation(0)).state, state(true, 0, 0));
}

#[test]
fn media_command_gate_close_wraps_each_full_uint64_counter_independently() {
    for lifecycle in [0, 1, u64::MAX - 1, u64::MAX] {
        for epoch in [0, 1, u64::MAX - 1, u64::MAX] {
            assert_eq!(checked(state(true, lifecycle, epoch), mutation(1)).state,
                state(false, original_increment(lifecycle), original_increment(epoch)));
        }
    }
    assert_eq!(checked(state(true, u64::MAX, u64::MAX), mutation(1)).state, state(false, 0, 0));
}

#[test]
fn media_command_gate_invalidate_wraps_without_rotating_lifecycle_or_open() {
    for open in [false, true] {
        for lifecycle in [0, 1, u64::MAX - 1, u64::MAX] {
            assert_eq!(checked(state(open, lifecycle, u64::MAX), mutation(2)).state,
                state(open, lifecycle, 0));
        }
    }
}

#[test]
fn media_command_gate_full_uint64_equality_and_wrapped_zero_remain_legal() {
    let values = [0, 1, 1_u64 << 53, 1_u64 << 63, u64::MAX - 1, u64::MAX];
    for lifecycle in values {
        for epoch in values {
            let before = state(true, lifecycle, epoch);
            assert_eq!(checked(before, event(3, false, lifecycle, 0)).allowed, 1);
            assert_eq!(checked(before, event(5, true, lifecycle, epoch)).allowed, 1);
            assert_eq!(checked(before, event(5, true, original_increment(lifecycle), epoch)).allowed, 0);
            assert_eq!(checked(before, event(5, true, lifecycle, original_increment(epoch))).allowed, 0);
        }
    }
    let wrapped = checked(state(false, u64::MAX, u64::MAX), mutation(0)).state;
    assert_eq!(checked(wrapped, event(3, false, 0, 0)).allowed, 1);
    assert_eq!(checked(wrapped, event(5, true, 0, 0)).allowed, 1);
}

#[test]
fn media_command_gate_invalid_state_abi_and_boolean_tags_are_canonical_denial() {
    let valid = state(true, 31, 81);
    for abi in [0, 2, u32::MAX] {
        denied(S { abi_version: abi, ..valid }, mutation(0));
        denied(S { abi_version: abi, ..valid }, event(5, true, 31, 81));
    }
    for tag in [2, 3, u32::MAX] {
        denied(S { is_open: tag, ..valid }, mutation(2));
        denied(S { is_open: tag, ..valid }, event(4, true, 0, 0));
    }
    denied(S::default(), mutation(0));
}

#[test]
fn media_command_gate_unknown_opcode_reserved_and_membership_tags_are_denied() {
    let before = state(true, 11, 13);
    for opcode in [6, 7, 255, u32::MAX] { denied(before, mutation(opcode)); }
    for opcode in 0..6 {
        let valid = match opcode {
            3 => event(3, false, 11, 0), 4 => event(4, true, 0, 0),
            5 => event(5, true, 11, 13), _ => mutation(opcode),
        };
        for value in [1, 2, u32::MAX] {
            denied(before, E { reserved0: value, ..valid });
            denied(before, E { reserved1: value, ..valid });
        }
        for value in [2, 3, u32::MAX] { denied(before, E { context_is_current: value, ..valid }); }
    }
}

#[test]
fn media_command_gate_each_opcode_rejects_noncanonical_unused_payload() {
    let before = state(true, 0, u64::MAX);
    for opcode in 0..3 {
        denied(before, E { context_is_current: 1, ..mutation(opcode) });
        denied(before, E { candidate_lifecycle: 1, ..mutation(opcode) });
        denied(before, E { candidate_command_epoch: 1, ..mutation(opcode) });
    }
    denied(before, event(3, true, 0, 0));
    denied(before, event(3, false, 0, 1));
    denied(before, event(4, true, 1, 0));
    denied(before, event(4, true, 0, 1));
    assert_eq!(checked(before, event(3, false, 0, 0)).allowed, 1);
    assert_eq!(checked(before, event(5, true, 0, u64::MAX)).allowed, 1);
}

#[test]
fn media_command_gate_canonical_denial_cannot_be_validated_as_a_reset() {
    let before = state(true, u64::MAX, 171);
    let invalid = E { opcode: 99, ..E::default() };
    assert_eq!(step(before, invalid), canonical_denial());
    assert_eq!(verify(before, invalid, canonical_denial()), 0);
    assert_eq!(verify(before, mutation(0), canonical_denial()), 0);
    assert_eq!(verify(before, event(4, false, 0, 0), canonical_denial()), 0);
}

fn result_bytes(value: R) -> [u8; 40] {
    let mut b = [0; 40];
    b[0..4].copy_from_slice(&value.abi_version.to_le_bytes());
    b[4..8].copy_from_slice(&value.status.to_le_bytes());
    b[8..12].copy_from_slice(&value.allowed.to_le_bytes());
    b[12..16].copy_from_slice(&value.reserved.to_le_bytes());
    b[16..20].copy_from_slice(&value.state.abi_version.to_le_bytes());
    b[20..24].copy_from_slice(&value.state.is_open.to_le_bytes());
    b[24..32].copy_from_slice(&value.state.lifecycle.to_le_bytes());
    b[32..40].copy_from_slice(&value.state.command_epoch.to_le_bytes());
    b
}
fn word32(b: &[u8; 40], o: usize) -> u32 { u32::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]]) }
fn word64(b: &[u8; 40], o: usize) -> u64 {
    u64::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3], b[o + 4], b[o + 5], b[o + 6], b[o + 7]])
}
fn from_result_bytes(b: [u8; 40]) -> R {
    R { abi_version: word32(&b, 0), status: word32(&b, 4), allowed: word32(&b, 8), reserved: word32(&b, 12),
        state: S { abi_version: word32(&b, 16), is_open: word32(&b, 20),
            lifecycle: word64(&b, 24), command_epoch: word64(&b, 32) } }
}

#[test]
fn media_command_gate_verifier_rejects_each_of_all_forty_copied_bytes() {
    for before in [state(false, 0, 0), state(true, 0x8000_0000_0000_0001, u64::MAX)] {
        for e in [mutation(0), mutation(1), mutation(2), event(3, false, before.lifecycle, 0),
            event(4, false, 0, 0), event(4, true, 0, 0),
            event(5, true, before.lifecycle, before.command_epoch), event(5, false, 0, 0)] {
            let actual = checked(before, e);
            let bytes = result_bytes(actual);
            assert_eq!(from_result_bytes(bytes), actual);
            for position in 0..40 {
                let mut corrupt = bytes; corrupt[position] ^= 1;
                assert_eq!(verify(before, e, from_result_bytes(corrupt)), 0, "copied byte {position}");
            }
        }
    }
}

#[test]
fn media_command_gate_verifier_recomputes_exact_successor_and_permission() {
    let before = state(true, 17, 29);
    let grant = event(5, true, 17, 29);
    let actual = checked(before, grant);
    assert_eq!(verify(state(true, 17, 30), grant, actual), 0);
    assert_eq!(verify(before, event(5, false, 17, 29), actual), 0);
    assert_eq!(verify(before, event(5, true, 18, 29), actual), 0);
    assert_eq!(verify(before, event(5, true, 17, 30), actual), 0);
    let captured = checked(before, event(4, true, 0, 0));
    assert_eq!(verify(before, event(4, false, 0, 0), captured), 0);
    let opened = checked(before, mutation(0));
    assert_eq!(verify(before, mutation(1), opened), 0);
    let invalidated = checked(before, mutation(2));
    assert_eq!(verify(before, mutation(0), invalidated), 0);
}

// A bounded independent original owner for context traces. Its context collection is
// represented by two native-equality atoms; Rust receives only current membership facts.
#[derive(Clone, Copy)]
struct Authority { lifecycle: u64, epoch: u64, context: u8 }
struct OriginalTraceOwner {
    lifecycle: u64, epoch: u64, open: bool, contexts: u8,
    first_token: u64, authorities: [Option<Authority>; 2],
}
impl OriginalTraceOwner {
    fn new(lifecycle: u64, epoch: u64, open: bool) -> Self {
        Self { lifecycle, epoch, open, contexts: 0, first_token: lifecycle, authorities: [None, None] }
    }
    fn raw(&self) -> S { state(self.open, self.lifecycle, self.epoch) }
    fn member(&self, context: u8) -> bool { self.contexts & (1_u8 << context) != 0 }
    fn trace(&mut self, action: u32) {
        if action >= 8 {
            self.contexts = match action { 8 => 0, 9 => 1, 10 => 2, _ => 3 };
            // Native setContexts is not a Rust event and changes no scalar counter.
            for context in [0, 1] { self.capture(context, false); }
            return;
        }
        if action == 3 { self.capture(0, true); return; }
        if action == 4 { self.capture(1, true); return; }
        let e = match action {
            0..=2 => mutation(action),
            5 => event(3, false, self.first_token, 0),
            6 | 7 => {
                let context = (action - 6) as u8;
                match self.authorities[usize::from(context)] {
                    Some(a) => event(5, self.member(a.context), a.lifecycle, a.epoch),
                    None => event(5, false, 0, 0),
                }
            }
            _ => unreachable!(),
        };
        let before = self.raw();
        let actual = step(before, e);
        let allowed = match action {
            0 => { self.lifecycle = original_increment(self.lifecycle); self.epoch = original_increment(self.epoch);
                self.open = true; self.contexts = 0; false },
            1 => { self.lifecycle = original_increment(self.lifecycle); self.epoch = original_increment(self.epoch);
                self.open = false; self.contexts = 0; false },
            2 => { self.epoch = original_increment(self.epoch); false },
            5 => self.open && self.lifecycle == self.first_token,
            6 | 7 => self.authorities[(action - 6) as usize].is_some_and(|a|
                self.open && self.lifecycle == a.lifecycle && self.epoch == a.epoch && self.member(a.context)),
            _ => unreachable!(),
        };
        assert_eq!(actual, R { abi_version: 1, status: 1, allowed: u32::from(allowed), reserved: 0, state: self.raw() });
        assert_eq!(verify(before, e, actual), 1);
    }
    fn capture(&mut self, context: u8, save: bool) {
        let before = self.raw();
        let e = event(4, self.member(context), 0, 0);
        let actual = step(before, e);
        let granted = self.open && self.member(context);
        if granted && save {
            self.authorities[usize::from(context)] = Some(Authority {
                lifecycle: self.lifecycle, epoch: self.epoch, context,
            });
        }
        assert_eq!(actual, R { abi_version: 1, status: 1, allowed: u32::from(granted), reserved: 0, state: before });
        assert_eq!(self.raw(), before);
        assert_eq!(verify(before, e, actual), 1);
    }
}

#[test]
fn media_command_gate_native_membership_remove_readd_does_not_invalidate_epochs() {
    let mut owner = OriginalTraceOwner::new(4, 9, true);
    owner.trace(11); owner.trace(3); owner.trace(4); owner.trace(6); owner.trace(7);
    let before = owner.raw();
    owner.trace(8); owner.trace(6); owner.trace(7);
    assert_eq!(owner.raw(), before);
    owner.trace(11); owner.trace(6); owner.trace(7);
    assert_eq!(owner.raw(), before);
    owner.trace(2); owner.trace(6); owner.trace(7);
    owner.trace(3); owner.trace(4); owner.trace(6); owner.trace(7);
    assert_eq!(owner.raw(), state(true, 4, 10));
}

#[test]
fn media_command_gate_fixed_order_original_owner_small_traces_preserve_full_state() {
    // 9^4 literal action traces per each of three original seeds. No nondeterministic corpus.
    const ACTIONS: [u32; 9] = [0, 1, 2, 3, 5, 6, 8, 9, 11];
    for (lifecycle, epoch, open) in [(0, 0, false), (u64::MAX, u64::MAX, true),
        (u64::MAX - 1, 1, true)] {
        for encoded in 0..6_561_u32 {
            let mut owner = OriginalTraceOwner::new(lifecycle, epoch, open);
            let mut remaining = encoded;
            for _ in 0..4 {
                owner.trace(ACTIONS[(remaining % 9) as usize]);
                remaining /= 9;
            }
        }
    }
}

#[test]
fn media_command_gate_fixed_seeded_churn_preserves_both_context_authorities() {
    for (lifecycle, epoch, open) in [(0, 0, false), (u64::MAX, u64::MAX - 1, true),
        (1_u64 << 63, (1_u64 << 53) + 1, false)] {
        let mut owner = OriginalTraceOwner::new(lifecycle, epoch, open);
        let mut seed = 0x52c9_44a1_9107_e3d5_u64;
        for _ in 0..4_096 {
            seed = seed.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_407);
            owner.trace(((seed >> 32) % 12) as u32);
        }
    }
}
