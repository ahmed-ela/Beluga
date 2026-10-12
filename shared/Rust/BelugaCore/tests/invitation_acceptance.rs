//! Exact copied-value policy tests; native UUID, callbacks and persistence remain separately tested.
//! The flat reference below independently follows the frozen original Swift method order.
//! Real native UUID/record/closure behavior is separately covered by the private native tests.
use beluga_core::invitation_acceptance as policy;
use policy::{RawEvent, RawOutput, RawState};
use std::collections::BTreeSet;

fn event(opcode: u32) -> RawEvent {
    RawEvent { opcode, generation_matches: 0, phase: 0, admission_callback_present: 0,
        prepared_kind: 0, prepared_flags: 0, owner_matches: 0, callback_outcome: 0 }
}
fn raw(flags: u32) -> RawState { RawState { abi_version: 1, flags } }
fn call(state: RawState, e: RawEvent) -> RawOutput { beluga_core::beluga_core_invitation_acceptance_step(1, state, e) }
fn armed(admission: bool) -> RawState {
    let mut e = event(0); e.admission_callback_present = admission as u32;
    call(raw(0), e).state
}
fn prepare(state: RawState, op: u32, matches: bool, phase: u32) -> RawOutput {
    let mut e = event(op); e.generation_matches = matches as u32; e.phase = phase;
    call(state, e)
}
fn ack(state: RawState, plan: RawOutput, succeeded: bool) -> RawOutput {
    let mut e = event(3); e.prepared_kind = plan.callback_kind; e.prepared_flags = plan.prepared_flags;
    e.owner_matches = 1; e.callback_outcome = if succeeded { 1 } else { 2 };
    call(state, e)
}
fn no_callback(result: RawOutput) {
    assert_eq!(result.callback_kind, 0); assert_eq!(result.prepared_flags, 0);
    assert_eq!(result.completion_succeeded, 0);
    assert_eq!(result.callback_success_state, result.state);
}

#[test]
fn initial_is_canonical_and_owns_nothing() {
    assert_eq!(beluga_core::beluga_core_invitation_acceptance_initial(), raw(0));
}
#[test]
fn arm_replaces_optional_callback_and_resets_consumed() {
    for before in [0, 5, 7, 13, 15] {
        for present in [false, true] {
            let mut e = event(0); e.admission_callback_present = present as u32;
            let r = call(raw(before), e);
            assert_eq!(r.status, 0); assert_eq!(r.state, raw(if present { 7 } else { 5 }));
            no_callback(r);
        }
    }
}
#[test]
fn foreign_admission_ignores_phase_before_any_error() {
    for state in [0, 5, 7, 13, 15] {
        for phase in [0, 1, 2, u32::MAX] {
            let r = prepare(raw(state), 1, false, phase);
            assert_eq!(r.status, 1); assert_eq!(r.state, raw(state)); no_callback(r);
        }
    }
}
#[test]
fn already_consumed_admission_ignores_invalid_phase() {
    for state in [13, 15] {
        for phase in [0, 1, 2, u32::MAX] {
            let r = prepare(raw(state), 1, true, phase);
            assert_eq!(r.status, 1); assert_eq!(r.state, raw(state)); no_callback(r);
        }
    }
}
#[test]
fn matched_admission_rejects_nonrecoverable_native_phases() {
    for state in [5, 7] {
        for phase in [0, 2] {
            let r = prepare(raw(state), 1, true, phase);
            assert_eq!(r.status, 3); assert_eq!(r.state, raw(state)); no_callback(r);
        }
    }
}
#[test]
fn nil_admission_callback_still_consumes_after_accepted_issued() {
    let r = prepare(armed(false), 1, true, 1);
    assert_eq!(r.status, 0); assert_eq!(r.state, raw(13)); no_callback(r);
    assert_eq!(prepare(r.state, 1, true, 0).status, 1);
}
#[test]
fn callback_preparation_never_consumes_before_native_success() {
    let before = armed(true); let plan = prepare(before, 1, true, 1);
    assert_eq!(plan.status, 2); assert_eq!(plan.state, before);
    assert_eq!(plan.callback_kind, 1); assert_eq!(plan.prepared_flags, 7);
    assert_eq!(plan.callback_success_state, raw(15)); assert_eq!(plan.completion_succeeded, 0);
}
#[test]
fn thrown_admission_callback_remains_armed_retryable() {
    let before = armed(true); let plan = prepare(before, 1, true, 1);
    let failed = ack(before, plan, false);
    assert_eq!(failed.status, 5); assert_eq!(failed.state, before); no_callback(failed);
    let retried = prepare(failed.state, 1, true, 1);
    assert_eq!(retried.status, 2);
    assert_eq!(ack(failed.state, retried, true).state, raw(15));
}
#[test]
fn successful_admission_is_consumed_once() {
    let before = armed(true); let plan = prepare(before, 1, true, 1);
    let done = ack(before, plan, true);
    assert_eq!(done.status, 0); assert_eq!(done.state, plan.callback_success_state); no_callback(done);
    assert_eq!(prepare(done.state, 1, true, 1).status, 1);
}
#[test]
fn active_completion_does_not_require_admission() {
    for state in [5, 7, 13, 15] {
        let plan = prepare(raw(state), 2, true, 2);
        assert_eq!(plan.status, 2); assert_eq!(plan.state, raw(state)); assert_eq!(plan.callback_kind, 2);
        assert_eq!(plan.callback_success_state, raw(0)); assert_eq!(plan.completion_succeeded, 0);
        let done = ack(raw(state), plan, true);
        assert_eq!(done.status, 0); assert_eq!(done.state, raw(0)); assert_eq!(done.completion_succeeded, 1);
        assert_eq!(done.callback_kind, 0); assert_eq!(done.prepared_flags, 0);
    }
}
#[test]
fn idle_and_foreign_completion_ignore_phase() {
    for phase in [0, 1, 2, u32::MAX] {
        let idle = prepare(raw(0), 2, true, phase);
        assert_eq!(idle.status, 1); no_callback(idle);
        for state in [5, 7, 13, 15] {
            let r = prepare(raw(state), 2, false, phase);
            assert_eq!(r.status, 1); assert_eq!(r.state, raw(state)); no_callback(r);
        }
    }
}
#[test]
fn matched_completion_checks_active_only_after_owner_guard() {
    for state in [5, 7, 13, 15] {
        for phase in [0, 1] {
            let r = prepare(raw(state), 2, true, phase);
            assert_eq!(r.status, 4); assert_eq!(r.state, raw(state)); no_callback(r);
        }
    }
}
#[test]
fn thrown_completion_preserves_every_owned_field() {
    for state in [5, 7, 13, 15] {
        let plan = prepare(raw(state), 2, true, 2);
        let failed = ack(raw(state), plan, false);
        assert_eq!(failed.status, 5); assert_eq!(failed.state, raw(state)); no_callback(failed);
        assert_eq!(prepare(failed.state, 2, true, 2).status, 2);
    }
}
#[test]
fn successful_completion_clears_owner_callbacks_and_consumed() {
    let plan = prepare(raw(15), 2, true, 2);
    let done = ack(raw(15), plan, true);
    assert_eq!(done.state, raw(0)); assert_eq!(done.callback_success_state, raw(0));
    assert_eq!(done.completion_succeeded, 1);
    assert_eq!(prepare(done.state, 2, true, 2).status, 1);
}
#[test]
fn cancellation_is_exact_and_rearm_cannot_be_cancelled_by_foreign_owner() {
    for flags in [0, 5, 7, 13, 15] {
        let mut foreign = event(4); foreign.generation_matches = 0;
        assert_eq!(call(raw(flags), foreign).state, raw(flags));
        let mut exact = event(4); exact.generation_matches = 1;
        let r = call(raw(flags), exact);
        assert_eq!(r.status, if flags == 0 { 1 } else { 0 }); assert_eq!(r.state, raw(0)); no_callback(r);
    }
}
#[test]
fn stale_callback_ack_rejects_same_flags_rearm_native_owner_mismatch() {
    let before = raw(7); let plan = prepare(before, 1, true, 1);
    let mut e = event(3); e.prepared_kind = plan.callback_kind; e.prepared_flags = plan.prepared_flags;
    e.callback_outcome = 1; e.owner_matches = 0;
    let r = call(before, e); assert_eq!(r.status, 6); assert_eq!(r.state, before); no_callback(r);
    e.owner_matches = 1; e.prepared_flags = 5;
    assert_eq!(call(before, e).status, 6);
}
#[test]
fn copied_states_are_independent_and_do_not_share_consumption() {
    let original = raw(7); let copy = original;
    let admitted = ack(copy, prepare(copy, 1, true, 1), true).state;
    assert_eq!(admitted, raw(15)); assert_eq!(original, raw(7));
    assert_eq!(prepare(original, 1, true, 1).status, 2);
    let ended = ack(admitted, prepare(admitted, 2, true, 2), true).state;
    assert_eq!(ended, raw(0)); assert_eq!(admitted, raw(15));
}
#[test]
fn malformed_inputs_never_invite_callback_or_clear_existing_owner() {
    let before = raw(15);
    for flags in (0..=31).filter(|flags| ![0, 5, 7, 13, 15].contains(flags)).chain([u32::MAX]) {
        let corrupt = raw(flags); let r = call(corrupt, event(0));
        assert_eq!(r.status, 7); assert_eq!(r.state, corrupt); no_callback(r);
    }
    let invalid_version = beluga_core::beluga_core_invitation_acceptance_step(2, before, event(4));
    assert_eq!(invalid_version.status, 7); assert_eq!(invalid_version.state, before); no_callback(invalid_version);
    let invalid_state_version = RawState { abi_version: 2, flags: 15 };
    let rejected_state = call(invalid_state_version, event(0));
    assert_eq!(rejected_state.status, 7); assert_eq!(rejected_state.state, invalid_state_version); no_callback(rejected_state);
    for owner_matches in [2, u32::MAX] {
        let mut bad_ack = event(3); bad_ack.prepared_kind = 2; bad_ack.prepared_flags = 15;
        bad_ack.callback_outcome = 1; bad_ack.owner_matches = owner_matches;
        let rejected_ack = call(before, bad_ack);
        assert_eq!(rejected_ack.status, 7); assert_eq!(rejected_ack.state, before); no_callback(rejected_ack);
    }
    let mut invalid = event(99);
    assert_eq!(call(before, invalid).status, 7);
    invalid = event(0); invalid.admission_callback_present = 2;
    assert_eq!(call(before, invalid).status, 7);
    invalid = event(2); invalid.generation_matches = 2;
    assert_eq!(call(before, invalid).status, 7);
    assert_eq!(prepare(raw(7), 1, true, u32::MAX).status, 7);
}
#[test]
fn forged_callback_ack_without_an_eligible_prepared_shape_is_invalid() {
    for (flags, kind, outcome) in [(5, 1, 1), (15, 1, 1), (7, 0, 1), (7, 3, 1), (7, 1, 0), (7, 1, 3)] {
        let mut e = event(3); e.prepared_flags = flags; e.prepared_kind = kind;
        e.owner_matches = 1; e.callback_outcome = outcome;
        let r = call(raw(flags), e); assert_eq!(r.status, 7); assert_eq!(r.state, raw(flags)); no_callback(r);
    }
}
#[test]
fn exact_raw_layout_is_copy_only_and_has_no_native_pointer() {
    use std::mem::{align_of, offset_of, size_of};
    assert_eq!(size_of::<RawState>(), 8); assert_eq!(align_of::<RawState>(), 4);
    assert_eq!(size_of::<RawEvent>(), 32); assert_eq!(align_of::<RawEvent>(), 4);
    assert_eq!(size_of::<RawOutput>(), 32); assert_eq!(align_of::<RawOutput>(), 4);
    assert_eq!(offset_of!(RawOutput, callback_success_state), 8);
    assert_eq!(offset_of!(RawOutput, status), 16); assert_eq!(offset_of!(RawOutput, completion_succeeded), 20);
    assert_eq!(offset_of!(RawOutput, callback_kind), 24); assert_eq!(offset_of!(RawOutput, prepared_flags), 28);
}

// This independent original-order reference does not call policy functions or reuse its predicates.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum NativePhase { Pending, AcceptedIssued, AcceptedReceived, Active }
impl NativePhase {
    fn wire(self) -> u32 {
        match self { Self::AcceptedIssued => 1, Self::Active => 2, Self::Pending | Self::AcceptedReceived => 0 }
    }
}
#[derive(Clone, Copy, Debug)]
enum Operation {
    Arm(u8, bool),
    Admit(u8, NativePhase, bool),
    Complete(u8, NativePhase, bool),
    Cancel(u8),
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Return { Unit, False, True, NotRecoverable, NotActive, CallbackError }
#[derive(Clone, Debug, Eq, PartialEq)]
struct Reference { generation: Option<u8>, admission: bool, completion: bool, consumed: bool }
impl Reference {
    fn initial() -> Self { Self { generation: None, admission: false, completion: false, consumed: false } }
    fn scalar(&self) -> RawState {
        raw(if self.generation.is_none() { 0 } else {
            1 | if self.admission { 2 } else { 0 } | if self.completion { 4 } else { 0 } | if self.consumed { 8 } else { 0 }
        })
    }
    fn apply(&mut self, op: Operation, callbacks: &mut Vec<u32>) -> Return {
        match op {
            Operation::Arm(generation, admission) => {
                self.generation = Some(generation); self.admission = admission; self.completion = true; self.consumed = false;
                Return::Unit
            }
            Operation::Admit(generation, phase, fails) => {
                if self.generation != Some(generation) || self.consumed { return Return::Unit; }
                if phase != NativePhase::AcceptedIssued { return Return::NotRecoverable; }
                if self.admission {
                    callbacks.push(1);
                    if fails { return Return::CallbackError; }
                }
                self.consumed = true; Return::Unit
            }
            Operation::Complete(generation, phase, fails) => {
                if self.generation != Some(generation) || !self.completion { return Return::False; }
                if phase != NativePhase::Active { return Return::NotActive; }
                callbacks.push(2);
                if fails { return Return::CallbackError; }
                *self = Self::initial(); Return::True
            }
            Operation::Cancel(generation) => {
                if self.generation == Some(generation) { *self = Self::initial(); }
                Return::Unit
            }
        }
    }
}
#[derive(Clone, Debug)]
struct Caller { state: RawState, generation: Option<u8> }
impl Caller {
    fn initial() -> Self { Self { state: raw(0), generation: None } }
    fn apply(&mut self, op: Operation, callbacks: &mut Vec<u32>) -> Return {
        let mut e;
        match op {
            Operation::Arm(generation, present) => {
                e = event(0); e.admission_callback_present = present as u32;
                self.state = call(self.state, e).state; self.generation = Some(generation); return Return::Unit;
            }
            Operation::Admit(generation, phase, _) => {
                e = event(1); e.generation_matches = (self.generation == Some(generation)) as u32; e.phase = phase.wire();
            }
            Operation::Complete(generation, phase, _) => {
                e = event(2); e.generation_matches = (self.generation == Some(generation)) as u32; e.phase = phase.wire();
            }
            Operation::Cancel(generation) => {
                e = event(4); e.generation_matches = (self.generation == Some(generation)) as u32;
            }
        }
        let mut r = call(self.state, e);
        if r.status == 2 {
            assert_eq!(r.state, self.state); assert_eq!(r.completion_succeeded, 0);
            callbacks.push(r.callback_kind);
            let fails = match op { Operation::Admit(_, _, fails) | Operation::Complete(_, _, fails) => fails, _ => unreachable!() };
            let prior = r; r = ack(self.state, prior, !fails);
            if !fails { assert_eq!(r.state, prior.callback_success_state); }
        }
        self.state = r.state;
        if self.state.flags == 0 { self.generation = None; }
        match r.status {
            0 if r.completion_succeeded == 1 => Return::True,
            0 => Return::Unit,
            1 if matches!(op, Operation::Complete(..)) => Return::False,
            1 => Return::Unit,
            3 => Return::NotRecoverable,
            4 => Return::NotActive,
            5 => Return::CallbackError,
            _ => panic!("unexpected bridge result in valid reference trace: {r:?}"),
        }
    }
}
fn operations() -> Vec<Operation> {
    let mut ops = vec![];
    for generation in [1, 2] {
        for present in [false, true] { ops.push(Operation::Arm(generation, present)); }
        for phase in [NativePhase::Pending, NativePhase::AcceptedIssued, NativePhase::AcceptedReceived, NativePhase::Active] {
            for fails in [false, true] {
                ops.push(Operation::Admit(generation, phase, fails));
                ops.push(Operation::Complete(generation, phase, fails));
            }
        }
        ops.push(Operation::Cancel(generation));
    }
    ops
}
fn compare(reference: &mut Reference, caller: &mut Caller, op: Operation) {
    let mut native_calls = vec![]; let mut core_calls = vec![];
    let expected = reference.apply(op, &mut native_calls); let actual = caller.apply(op, &mut core_calls);
    assert_eq!(actual, expected, "return mismatch for {op:?}");
    assert_eq!(core_calls, native_calls, "callback order/count mismatch for {op:?}");
    assert_eq!(caller.generation, reference.generation);
    assert_eq!(caller.state, reference.scalar());
}
#[test]
fn all_reachable_original_states_and_events_match_independent_flat_reference() {
    let ops = operations(); assert_eq!(ops.len(), 38);
    let mut pending = vec![(Reference::initial(), Caller::initial())];
    let mut seen = BTreeSet::new(); let mut edges = 0;
    while let Some((reference, caller)) = pending.pop() {
        let key = (reference.generation, reference.admission, reference.completion, reference.consumed);
        if !seen.insert(key) { continue; }
        for op in &ops {
            let mut ref_copy = reference.clone(); let mut core_copy = caller.clone();
            compare(&mut ref_copy, &mut core_copy, *op); edges += 1;
            pending.push((ref_copy, core_copy));
        }
    }
    assert_eq!(seen.len(), 9); assert_eq!(edges, 342);
}
#[test]
fn seeded_original_trace_with_rearm_cancellation_and_value_copies_matches() {
    let ops = operations(); let mut seed = 0x75df_02b8_aa3e_6119u64;
    let mut reference = Reference::initial(); let mut caller = Caller::initial();
    for index in 0..2_000 {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        compare(&mut reference, &mut caller, ops[(seed as usize) % ops.len()]);
        if index % 11 == 0 {
            let before_ref = reference.clone(); let before_core = caller.clone();
            let mut copied_ref = reference.clone(); let mut copied_core = caller.clone();
            compare(&mut copied_ref, &mut copied_core, ops[((seed >> 32) as usize) % ops.len()]);
            assert_eq!(reference, before_ref); assert_eq!(caller.state, before_core.state);
            assert_eq!(caller.generation, before_core.generation);
        }
    }
}
