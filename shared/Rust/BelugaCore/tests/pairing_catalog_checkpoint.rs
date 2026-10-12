//! Independent tests, using a flat original-branch reference rather than
//! the typed reducer as the expected result. The effect harness below is a MODEL:
//! it does not exercise Keychain, catalog serialization, callbacks, locks or CAS.
use beluga_core::{beluga_core_pairing_catalog_checkpoint_initial,
                  beluga_core_pairing_catalog_checkpoint_step};
use beluga_core::pairing_catalog_checkpoint::{initial, step, Decision, RawEvent, RawResult, RawState};
use std::mem::{align_of, offset_of, size_of};

fn event(opcode: u32, owner: u32, binding: u32, snapshot: u32) -> RawEvent {
    RawEvent { opcode, owner_valid: owner, binding_matches: binding, snapshot_matches: snapshot }
}

// Independent frozen projection of the original Swift guard branches. Wire
// numbers are literal on purpose; no production enum/helper drives this oracle.
fn original_flat(before: RawState, e: RawEvent) -> RawResult {
    let bound = before.flags & 1 != 0;
    let revoked = before.flags & 2 != 0;
    let allowed = match e.opcode {
        0 => !revoked && e.owner_valid == 1 && !bound,
        1 => !revoked && e.owner_valid == 1 && bound && e.binding_matches == 1,
        2 => true,
        3 => e.snapshot_matches == 1,
        _ => panic!("reference called outside its valid original operation domain"),
    };
    let flags = if !allowed { before.flags } else {
        match e.opcode { 0 => before.flags | 1, 2 => before.flags | 2, _ => before.flags }
    };
    RawResult {
        candidate_state: RawState { abi_version: 1, flags },
        decision: if allowed { 0 } else { 1 },
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct NativeTuple { device: [u8; 16], pair: [u8; 16], commit: [u8; 16] }

const ZERO: NativeTuple = NativeTuple { device: [0; 16], pair: [0; 16], commit: [0; 16] };
const MAX: NativeTuple = NativeTuple { device: [255; 16], pair: [255; 16], commit: [255; 16] };
const OTHER_DEVICE: NativeTuple = NativeTuple { device: [255; 16], ..ZERO };
const OTHER_PAIR: NativeTuple = NativeTuple { pair: [255; 16], ..ZERO };
const OTHER_COMMIT: NativeTuple = NativeTuple { commit: [255; 16], ..ZERO };

// Opaque complete modeled snapshot, not a catalog schema or UUID truncation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct NativeSnapshot { generation: [u8; 16], revision: u64, selection: [u8; 16], body: u64 }

const EMPTY_SNAPSHOT: NativeSnapshot = NativeSnapshot {
    generation: [0; 16], revision: 0, selection: [0; 16], body: 0,
};

#[derive(Clone, Copy, Debug)]
enum Effect { ReturnSuccess, ThrowBefore, WriteThenThrow }

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Outcome { Success, StaleAttempt, OriginalStoreFailure, OriginalTokenFailure }

#[derive(Clone, Copy, Debug)]
enum Action {
    Add { record: NativeTuple, owner: bool, effect: Effect },
    Update { record: NativeTuple, owner: bool, effect: Effect },
    Revoke,
    Readback { owner: bool, effect: Effect },
}

// A shared modeled EFFECT primitive is not the expected policy oracle. Attempt
// accounting happens at entry, even when the primitive immediately throws.
fn store_effect(durable: &mut NativeSnapshot, attempts: &mut u32,
                expected: NativeSnapshot, effect: Effect) -> Result<NativeSnapshot, Outcome> {
    *attempts += 1;
    if *durable != expected { return Err(Outcome::OriginalTokenFailure); }
    if matches!(effect, Effect::ThrowBefore) { return Err(Outcome::OriginalStoreFailure); }
    let updated = NativeSnapshot { revision: durable.revision + 1, body: durable.body + 1, ..*durable };
    *durable = updated;
    if matches!(effect, Effect::WriteThenThrow) { Err(Outcome::OriginalStoreFailure) } else { Ok(updated) }
}

fn load_effect(durable: NativeSnapshot, attempts: &mut u32,
               effect: Effect) -> Result<NativeSnapshot, Outcome> {
    *attempts += 1;
    if matches!(effect, Effect::ReturnSuccess) { Ok(durable) } else { Err(Outcome::OriginalStoreFailure) }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct View {
    bound: Option<NativeTuple>, revoked: bool, snapshot: NativeSnapshot, durable: NativeSnapshot,
    owner_calls: u32, store_attempts: u32, load_attempts: u32,
}

impl View {
    fn empty() -> Self {
        Self { bound: None, revoked: false, snapshot: EMPTY_SNAPSHOT, durable: EMPTY_SNAPSHOT,
               owner_calls: 0, store_attempts: 0, load_attempts: 0 }
    }
}

// Flat frozen-original native ordering. This never calls step/original_flat.
fn original_native_model(v: &mut View, action: Action) -> Outcome {
    match action {
        Action::Revoke => { v.revoked = true; Outcome::Success }
        Action::Readback { owner: _ignored_owner, effect } => {
            let fresh = match load_effect(v.durable, &mut v.load_attempts, effect) {
                Ok(value) => value, Err(error) => return error,
            };
            if fresh != v.snapshot { Outcome::StaleAttempt } else { Outcome::Success }
        }
        Action::Add { record, owner, effect } => {
            if v.revoked { return Outcome::StaleAttempt; }
            v.owner_calls += 1;
            if !owner || v.bound.is_some() { return Outcome::StaleAttempt; }
            let saved = match store_effect(&mut v.durable, &mut v.store_attempts, v.snapshot, effect) {
                Ok(value) => value, Err(error) => return error,
            };
            v.snapshot = saved;
            v.bound = Some(record);
            Outcome::Success
        }
        Action::Update { record, owner, effect } => {
            if v.revoked { return Outcome::StaleAttempt; }
            v.owner_calls += 1;
            if !owner { return Outcome::StaleAttempt; }
            let Some(binding) = v.bound else { return Outcome::StaleAttempt; };
            if binding.device != record.device || binding.pair != record.pair || binding.commit != record.commit {
                return Outcome::StaleAttempt;
            }
            let saved = match store_effect(&mut v.durable, &mut v.store_attempts, v.snapshot, effect) {
                Ok(value) => value, Err(error) => return error,
            };
            v.snapshot = saved;
            Outcome::Success
        }
    }
}

#[derive(Clone, Copy)]
struct RustNativeModel { core: RawState, native: View }

impl RustNativeModel {
    fn empty() -> Self { Self { core: initial(), native: View::empty() } }

    fn apply(&mut self, action: Action) -> Outcome {
        match action {
            Action::Revoke => {
                let result = step(1, self.core, event(2, 0, 0, 0));
                assert_eq!(result.decision, Decision::Allowed as u32);
                self.core = result.candidate_state;
                self.native.revoked = self.core.flags & 2 != 0;
                Outcome::Success
            }
            Action::Readback { owner: _ignored_owner, effect } => {
                // Native load precedes policy and its error preserves precedence.
                let fresh = match load_effect(self.native.durable, &mut self.native.load_attempts, effect) {
                    Ok(value) => value, Err(error) => return error,
                };
                let result = step(1, self.core, event(3, 0, 0, (fresh == self.native.snapshot) as u32));
                assert_eq!(result.candidate_state, self.core);
                if result.decision == 0 { Outcome::Success } else { Outcome::StaleAttempt }
            }
            Action::Add { record, owner, effect } | Action::Update { record, owner, effect } => {
                // This is required primitive native callback ordering, not a
                // native success reducer. Actual flags must first be validated.
                let owner_fact = if self.core.flags & 2 == 0 {
                    self.native.owner_calls += 1; owner
                } else { false };
                let opcode = if matches!(action, Action::Add { .. }) { 0 } else { 1 };
                let matches = self.native.bound == Some(record);
                let result = step(1, self.core, event(opcode, owner_fact as u32, matches as u32, 0));
                if result.decision != 0 {
                    assert_eq!(result.candidate_state, self.core);
                    return Outcome::StaleAttempt;
                }
                // Candidate is captured, but NOT committed before store success.
                let saved = match store_effect(&mut self.native.durable, &mut self.native.store_attempts,
                                               self.native.snapshot, effect) {
                    Ok(value) => value, Err(error) => return error,
                };
                self.native.snapshot = saved;
                if opcode == 0 { self.native.bound = Some(record); }
                self.core = result.candidate_state;
                self.native.revoked = self.core.flags & 2 != 0;
                Outcome::Success
            }
        }
    }
}

fn assert_trace(actions: &[Action]) {
    let mut original = View::empty();
    let mut migrated = RustNativeModel::empty();
    for (index, action) in actions.iter().copied().enumerate() {
        assert_eq!(migrated.apply(action), original_native_model(&mut original, action), "outcome {index}: {action:?}");
        assert_eq!(migrated.native, original, "native model {index}: {action:?}");
        let original_flags = original.bound.is_some() as u32 | ((original.revoked as u32) << 1);
        assert_eq!(migrated.core, RawState { abi_version: 1, flags: original_flags }, "stored candidate {index}");
    }
}

#[test]
fn checkpoint_initial_and_copied_layout_are_exact() {
    assert_eq!(size_of::<RawState>(), 8); assert_eq!(align_of::<RawState>(), 4);
    assert_eq!(offset_of!(RawState, abi_version), 0); assert_eq!(offset_of!(RawState, flags), 4);
    assert_eq!(size_of::<RawEvent>(), 16); assert_eq!(align_of::<RawEvent>(), 4);
    assert_eq!(offset_of!(RawEvent, opcode), 0); assert_eq!(offset_of!(RawEvent, owner_valid), 4);
    assert_eq!(offset_of!(RawEvent, binding_matches), 8); assert_eq!(offset_of!(RawEvent, snapshot_matches), 12);
    assert_eq!(size_of::<RawResult>(), 12); assert_eq!(align_of::<RawResult>(), 4);
    assert_eq!(offset_of!(RawResult, candidate_state), 0); assert_eq!(offset_of!(RawResult, decision), 8);
    assert_eq!(initial(), RawState { abi_version: 1, flags: 0 });
    assert_eq!(beluga_core_pairing_catalog_checkpoint_initial(), initial());
    let e = event(0, 1, 0, 0);
    assert_eq!(beluga_core_pairing_catalog_checkpoint_step(1, initial(), e), step(1, initial(), e));
}

#[test]
fn checkpoint_all_valid_states_and_boolean_facts_match_original() {
    let mut cases = 0;
    for flags in 0..4 { for opcode in 0..4 { for owner in 0..2 { for binding in 0..2 { for snapshot in 0..2 {
        let before = RawState { abi_version: 1, flags };
        let e = event(opcode, owner, binding, snapshot);
        assert_eq!(step(1, before, e), original_flat(before, e), "flags={flags}, event={e:?}");
        cases += 1;
    }}}}}
    assert_eq!(cases, 128);
}

#[test]
fn checkpoint_bounded_committed_and_failed_effect_traces_match_original() {
    let alphabet = [
        Action::Add { record: ZERO, owner: true, effect: Effect::ReturnSuccess },
        Action::Add { record: MAX, owner: true, effect: Effect::ReturnSuccess },
        Action::Add { record: ZERO, owner: false, effect: Effect::ReturnSuccess },
        Action::Add { record: ZERO, owner: true, effect: Effect::ThrowBefore },
        Action::Add { record: ZERO, owner: true, effect: Effect::WriteThenThrow },
        Action::Update { record: ZERO, owner: true, effect: Effect::ReturnSuccess },
        Action::Update { record: OTHER_DEVICE, owner: true, effect: Effect::ReturnSuccess },
        Action::Update { record: OTHER_PAIR, owner: true, effect: Effect::ReturnSuccess },
        Action::Update { record: OTHER_COMMIT, owner: true, effect: Effect::ReturnSuccess },
        Action::Update { record: ZERO, owner: false, effect: Effect::ReturnSuccess },
        Action::Update { record: ZERO, owner: true, effect: Effect::ThrowBefore },
        Action::Update { record: ZERO, owner: true, effect: Effect::WriteThenThrow },
        Action::Revoke,
        Action::Readback { owner: false, effect: Effect::ReturnSuccess },
        Action::Readback { owner: true, effect: Effect::ThrowBefore },
    ];
    // All 0...4-event traces over this finite, explicitly declared alphabet.
    // No unbounded map, random seed or scheduling-dependent effect is required.
    for length in 0..=4_u32 {
        for ordinal in 0..alphabet.len().pow(length) {
            let mut value = ordinal;
            let mut trace = [Action::Revoke; 4];
            for item in trace.iter_mut().take(length as usize) {
                *item = alphabet[value % alphabet.len()]; value /= alphabet.len();
            }
            assert_trace(&trace[..length as usize]);
        }
    }
    // Error after an actual modeled write does not invent rollback or bind the
    // cursor. Fresh readback detects divergence, including after revocation.
    let mut model = RustNativeModel::empty();
    assert_eq!(model.apply(Action::Add { record: ZERO, owner: true, effect: Effect::WriteThenThrow }), Outcome::OriginalStoreFailure);
    assert_eq!(model.core, initial()); assert_eq!(model.native.bound, None);
    assert_eq!(model.native.store_attempts, 1); assert_ne!(model.native.snapshot, model.native.durable);
    assert_eq!(model.apply(Action::Revoke), Outcome::Success);
    assert_eq!(model.apply(Action::Readback { owner: false, effect: Effect::ReturnSuccess }), Outcome::StaleAttempt);
}

#[test]
fn checkpoint_revocation_is_terminal_without_erasing_binding() {
    for flags in 0..4 {
        let before = RawState { abi_version: 1, flags };
        let revoked = step(1, before, event(2, 0, 0, 0));
        assert_eq!(revoked.decision, 0); assert_eq!(revoked.candidate_state.flags, flags | 2);
        assert_eq!(step(1, revoked.candidate_state, event(2, 1, 1, 1)), revoked);
        for opcode in 0..2 {
            // owner=1 ensures a removed Rust revocation guard cannot hide behind
            // the native lazy callback projection's normal owner=0 after revoke.
            let rejected = step(1, revoked.candidate_state, event(opcode, 1, 1, 1));
            assert_eq!(rejected.decision, 1); assert_eq!(rejected.candidate_state, revoked.candidate_state);
        }
    }
    assert_trace(&[
        Action::Add { record: MAX, owner: true, effect: Effect::ReturnSuccess }, Action::Revoke,
        Action::Update { record: MAX, owner: true, effect: Effect::ReturnSuccess },
        Action::Readback { owner: false, effect: Effect::ReturnSuccess },
    ]);
}

#[test]
fn checkpoint_readback_ignores_revocation_and_owner_but_requires_snapshot() {
    for flags in 0..4 { for owner in 0..2 { for binding in 0..2 {
        let before = RawState { abi_version: 1, flags };
        assert_eq!(step(1, before, event(3, owner, binding, 1)), RawResult { candidate_state: before, decision: 0 });
        assert_eq!(step(1, before, event(3, owner, binding, 0)), RawResult { candidate_state: before, decision: 1 });
    }}}
    let mut migrated = RustNativeModel::empty();
    assert_eq!(migrated.apply(Action::Revoke), Outcome::Success);
    assert_eq!(migrated.apply(Action::Readback { owner: false, effect: Effect::ReturnSuccess }), Outcome::Success);
    assert_eq!(migrated.native.owner_calls, 0); assert_eq!(migrated.native.load_attempts, 1);
    // Entire modeled native values, not only revision, contribute to equality.
    for different in [
        NativeSnapshot { generation: [255; 16], ..EMPTY_SNAPSHOT },
        NativeSnapshot { selection: [255; 16], ..EMPTY_SNAPSHOT },
        NativeSnapshot { body: 1, ..EMPTY_SNAPSHOT },
        NativeSnapshot { revision: 1, ..EMPTY_SNAPSHOT },
    ] {
        let mut model = RustNativeModel::empty(); model.native.durable = different;
        assert_eq!(model.apply(Action::Readback { owner: true, effect: Effect::ThrowBefore }), Outcome::OriginalStoreFailure);
        assert_eq!(model.apply(Action::Readback { owner: true, effect: Effect::ReturnSuccess }), Outcome::StaleAttempt);
        assert_eq!(model.core, initial()); assert_eq!(model.native.owner_calls, 0);
    }
}

#[test]
fn checkpoint_rejected_input_preserves_exact_state() {
    let mut rejected = 0;
    for flags in 0..4 { for opcode in 0..4 { for owner in 0..2 { for binding in 0..2 { for snapshot in 0..2 {
        let before = RawState { abi_version: 1, flags };
        let output = step(1, before, event(opcode, owner, binding, snapshot));
        if output.decision == 1 { assert_eq!(output.candidate_state, before); rejected += 1; }
    }}}}}
    assert_eq!(rejected, 74);
    let mut model = RustNativeModel::empty();
    assert_eq!(model.apply(Action::Add { record: ZERO, owner: true, effect: Effect::ThrowBefore }), Outcome::OriginalStoreFailure);
    assert_eq!(model.core, initial()); assert_eq!(model.native.bound, None);
    assert_eq!(model.native.store_attempts, 1);
    assert_eq!(model.apply(Action::Add { record: ZERO, owner: true, effect: Effect::ReturnSuccess }), Outcome::Success);
    let saved = model.core; let native_saved = model.native.snapshot;
    assert_eq!(model.apply(Action::Update { record: ZERO, owner: true, effect: Effect::ThrowBefore }), Outcome::OriginalStoreFailure);
    assert_eq!(model.core, saved); assert_eq!(model.native.snapshot, native_saved); assert_eq!(model.native.bound, Some(ZERO));
}

#[test]
fn checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed() {
    let assert_invalid = |abi, before, e| {
        assert_eq!(step(abi, before, e), RawResult { candidate_state: before, decision: 3 }, "ABI={abi}, input={before:?}, event={e:?}");
    };
    for flags in 0..4 { for opcode in 0..4 {
        let before = RawState { abi_version: 1, flags };
        let e = event(opcode, 1, 1, 1);
        for abi in [0, 2, 3, 31, u32::MAX] {
            assert_invalid(abi, before, e);
            assert_invalid(1, RawState { abi_version: abi, flags }, e);
        }
        // Exhaust every single unknown state flag, combined with each known
        // state; all-ones verifies multi-bit copied-state preservation too.
        for bit in 2..32 { assert_invalid(1, RawState { abi_version: 1, flags: flags | (1 << bit) }, e); }
        assert_invalid(1, RawState { abi_version: 1, flags: u32::MAX }, e);
        for bad in (2..=31).chain([u32::MAX]) {
            assert_invalid(1, before, event(opcode, bad, 1, 1));
            assert_invalid(1, before, event(opcode, 1, bad, 1));
            assert_invalid(1, before, event(opcode, 1, 1, bad));
        }
        // Exhaust the finite valid-plus-invalid Boolean domain, including
        // combinations that must not be hidden by an earlier policy refusal.
        for owner in 0..3 { for binding in 0..3 { for snapshot in 0..3 {
            if owner == 2 || binding == 2 || snapshot == 2 {
                assert_invalid(1, before, event(opcode, owner, binding, snapshot));
            }
        }}}
        for bad_op in (4..=63).chain([u32::MAX]) { assert_invalid(1, before, event(bad_op, 1, 1, 1)); }
    }}
}

#[test]
fn checkpoint_raw_value_copies_do_not_share_mutation() {
    let untouched = initial(); let first_copy = untouched; let second_copy = untouched;
    let bound_first = step(1, first_copy, event(0, 1, 0, 0)).candidate_state;
    assert_eq!(untouched.flags, 0); assert_eq!(second_copy.flags, 0); assert_eq!(bound_first.flags, 1);
    let revoked_first = step(1, bound_first, event(2, 0, 0, 0)).candidate_state;
    assert_eq!(bound_first.flags, 1); assert_eq!(revoked_first.flags, 3);
    assert_eq!(step(1, second_copy, event(0, 1, 0, 0)).decision, 0);
    // All-zero and all-ones UUID tuples are legitimate native values, never
    // scalar missing-token sentinels. The raw ABI sees only the full Eq fact.
    for record in [ZERO, MAX] {
        assert_trace(&[
            Action::Add { record, owner: true, effect: Effect::ReturnSuccess },
            Action::Update { record, owner: true, effect: Effect::ReturnSuccess },
            Action::Revoke, Action::Readback { owner: false, effect: Effect::ReturnSuccess },
        ]);
    }
    // A returned but discarded Add candidate cannot mutate the original value
    // or prove that a native catalog effect happened.
    assert_eq!(step(1, untouched, event(0, 1, 0, 0)).candidate_state.flags, 1);
    assert_eq!(untouched, initial());
}
