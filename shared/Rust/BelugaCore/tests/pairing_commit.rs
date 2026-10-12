use beluga_core::beluga_core_pairing_commit_step as actual;
use beluga_core::pairing_commit::{RawEvent, RawResult, RawState};
use std::mem::{align_of, offset_of, size_of};

fn state(role: u32, phase: u32, cache: u32) -> RawState {
    RawState { abi_version: 1, reserved: 0, local_role: role,
        pairing_state: phase, recovery_phase: cache, reserved_tail: 0 }
}
fn event(opcode: u32) -> RawEvent {
    RawEvent { opcode, reserved: 0, commit_id_matches: 0, reserved_tail: 0 }
}
fn marked(exact: u32) -> RawEvent { RawEvent { commit_id_matches: exact, ..event(5) } }
fn result(before: RawState, decision: u32, action: u32, auth: u32) -> RawResult {
    RawResult { candidate_state: before, decision, action, auth_phase: auth, reserved: 0 }
}

// Frozen original RemotePairedDevice.swift phase guards and assignments. No
// reducer type, decoder, helper, decision, action or enum is reused here.
fn original_reference(abi: u32, before: RawState, input: RawEvent) -> RawResult {
    if abi != 1 || before.abi_version != 1 || before.reserved != 0 || before.reserved_tail != 0
        || before.local_role > 1 || before.pairing_state > 3 || before.recovery_phase > 4
        || input.reserved != 0 || input.reserved_tail != 0 || input.opcode > 8
        || input.commit_id_matches > 1 || (input.opcode != 5 && input.commit_id_matches != 0) {
        return result(before, 4, 0, 0);
    }
    let mut after = before;
    let host = before.local_role == 0;
    let phase = before.pairing_state;
    let cache = before.recovery_phase;
    match input.opcode {
        0 => {
            if cache != 0 { return result(before, 0, 3, 0); }
            let action = match phase { 0 => if host { 2 } else { 1 }, 1 => 1, 2 => 4, _ => 0 };
            result(before, 0, action, 0)
        }
        1 => {
            if !host || phase != 0 || (cache != 0 && cache != 1) { return result(before, 1, 0, 0); }
            if cache == 1 { return result(before, 0, 3, 0); }
            after.recovery_phase = 1;
            result(after, 0, 5, 0)
        }
        2 => {
            if host || (phase != 0 && phase != 1) { return result(before, 1, 0, 0); }
            if phase == 1 && cache != 0 { return result(before, 0, 3, 1); }
            after.pairing_state = 1;
            after.recovery_phase = 2;
            result(after, 0, 6, 1)
        }
        3 => {
            if !host || (phase != 0 && phase != 2 && phase != 3) { return result(before, 1, 0, 0); }
            if phase == 0 { after.pairing_state = 2; after.recovery_phase = 0; }
            result(after, 0, 0, 2)
        }
        4 => {
            if !host || (phase != 2 && phase != 3) { return result(before, 1, 0, 0); }
            if phase == 3 {
                if cache != 0 { return result(before, 1, 0, 0); }
                return result(before, 0, 7, 0);
            }
            if cache == 3 { return result(before, 0, 3, 0); }
            if cache != 0 { return result(before, 1, 0, 0); }
            after.recovery_phase = 3;
            result(after, 0, 7, 0)
        }
        5 => {
            if !host || input.commit_id_matches != 1
                || !((phase == 2 && cache == 3) || (phase == 3 && cache == 0)) {
                return result(before, 1, 0, 0);
            }
            result(before, 0, 0, 0)
        }
        6 => {
            if host { return result(before, 1, 0, 0); }
            if phase == 3 {
                if cache == 4 { return result(before, 0, 3, 3); }
                return result(before, 2, 0, 3);
            }
            if phase != 1 { return result(before, 1, 0, 0); }
            after.pairing_state = 3;
            after.recovery_phase = 4;
            result(after, 0, 8, 3)
        }
        7 => {
            if !host || (phase != 2 && phase != 3) { return result(before, 1, 0, 0); }
            after.pairing_state = 3;
            after.recovery_phase = 0;
            result(after, 0, 0, 4)
        }
        _ => {
            let valid = if host {
                (phase == 0 && (cache == 0 || cache == 1))
                    || (phase == 2 && (cache == 0 || cache == 3)) || (phase == 3 && cache == 0)
            } else {
                (phase == 0 && cache == 0) || (phase == 1 && cache == 2) || (phase == 3 && cache == 4)
            };
            if !valid { return result(before, 3, 0, 0); }
            result(before, 0, if cache == 0 { 0 } else { 9 }, 0)
        }
    }
}

#[test]
fn pairing_commit_exact_copied_layout_and_export() {
    assert_eq!((size_of::<RawState>(), align_of::<RawState>()), (24, 4));
    assert_eq!((offset_of!(RawState, abi_version), offset_of!(RawState, reserved),
        offset_of!(RawState, local_role), offset_of!(RawState, pairing_state),
        offset_of!(RawState, recovery_phase), offset_of!(RawState, reserved_tail)), (0, 4, 8, 12, 16, 20));
    assert_eq!((size_of::<RawEvent>(), align_of::<RawEvent>()), (16, 4));
    assert_eq!((offset_of!(RawEvent, opcode), offset_of!(RawEvent, reserved),
        offset_of!(RawEvent, commit_id_matches), offset_of!(RawEvent, reserved_tail)), (0, 4, 8, 12));
    assert_eq!((size_of::<RawResult>(), align_of::<RawResult>()), (40, 4));
    assert_eq!((offset_of!(RawResult, candidate_state), offset_of!(RawResult, decision),
        offset_of!(RawResult, action), offset_of!(RawResult, auth_phase), offset_of!(RawResult, reserved)), (0, 24, 28, 32, 36));
    assert_eq!(actual(1, state(0, 0, 0), event(1)), result(state(0, 0, 1), 0, 5, 0));
}

#[test]
fn pairing_commit_all_720_syntactic_cases_match_frozen_original() {
    let mut cases = 0;
    for role in 0..=1 { for phase in 0..=3 { for cache in 0..=4 {
        for opcode in 0..=8 { for exact in 0..=1 {
            let before = state(role, phase, cache);
            let input = RawEvent { commit_id_matches: exact, ..event(opcode) };
            assert_eq!(actual(1, before, input), original_reference(1, before, input),
                "role={role} phase={phase} cache={cache} opcode={opcode} exact={exact}");
            cases += 1;
        }}
    }}}
    assert_eq!(cases, 720);
}

#[test]
fn pairing_commit_recovery_getter_is_not_global_stored_shape_validation() {
    assert_eq!(actual(1, state(0, 0, 0), event(0)), result(state(0, 0, 0), 0, 2, 0));
    assert_eq!(actual(1, state(1, 0, 0), event(0)), result(state(1, 0, 0), 0, 1, 0));
    assert_eq!(actual(1, state(0, 1, 0), event(0)), result(state(0, 1, 0), 0, 1, 0));
    assert_eq!(actual(1, state(1, 2, 0), event(0)), result(state(1, 2, 0), 0, 4, 0));
    assert_eq!(actual(1, state(1, 3, 0), event(0)), result(state(1, 3, 0), 0, 0, 0));
    for role in 0..=1 { for phase in 0..=3 { for cache in 1..=4 {
        let before = state(role, phase, cache);
        assert_eq!(actual(1, before, event(0)), result(before, 0, 3, 0));
    }}}
}

#[test]
fn pairing_commit_proposal_preserves_cache_or_requires_original_constructor() {
    assert_eq!(actual(1, state(0, 0, 0), event(1)), result(state(0, 0, 1), 0, 5, 0));
    assert_eq!(actual(1, state(0, 0, 1), event(1)), result(state(0, 0, 1), 0, 3, 0));
    for cache in 2..=4 {
        let before = state(0, 0, cache);
        assert_eq!(actual(1, before, event(1)), result(before, 1, 0, 0));
    }
}

#[test]
fn pairing_commit_ack_cached_replay_still_authenticates_and_does_not_tighten_cache() {
    for cache in 1..=4 {
        let before = state(1, 1, cache);
        assert_eq!(actual(1, before, event(2)), result(before, 0, 3, 1));
    }
    assert_eq!(actual(1, state(1, 1, 0), event(2)), result(state(1, 1, 2), 0, 6, 1));
    for cache in 0..=4 {
        assert_eq!(actual(1, state(1, 0, cache), event(2)), result(state(1, 1, 2), 0, 6, 1));
    }
}

#[test]
fn pairing_commit_host_ack_replay_reauthenticates_and_preserves_exact_cache() {
    for cache in 0..=4 {
        assert_eq!(actual(1, state(0, 0, cache), event(3)), result(state(0, 2, 0), 0, 0, 2));
        for phase in [2, 3] {
            let before = state(0, phase, cache);
            assert_eq!(actual(1, before, event(3)), result(before, 0, 0, 2));
        }
    }
}

#[test]
fn pairing_commit_active_host_completion_is_ephemeral_not_reopened() {
    assert_eq!(actual(1, state(0, 3, 0), event(4)), result(state(0, 3, 0), 0, 7, 0));
    assert_eq!(actual(1, state(0, 2, 0), event(4)), result(state(0, 2, 3), 0, 7, 0));
    assert_eq!(actual(1, state(0, 2, 3), event(4)), result(state(0, 2, 3), 0, 3, 0));
    for cache in 1..=4 {
        let before = state(0, 3, cache);
        assert_eq!(actual(1, before, event(4)), result(before, 1, 0, 0));
    }
    for cache in [1, 2, 4] {
        let before = state(0, 2, cache);
        assert_eq!(actual(1, before, event(4)), result(before, 1, 0, 0));
    }
}

#[test]
fn pairing_commit_send_success_never_activates_or_retires_completion() {
    assert_eq!(actual(1, state(0, 2, 3), marked(1)), result(state(0, 2, 3), 0, 0, 0));
    assert_eq!(actual(1, state(0, 3, 0), marked(1)), result(state(0, 3, 0), 0, 0, 0));
    for role in 0..=1 { for phase in 0..=3 { for cache in 0..=4 {
        let before = state(role, phase, cache);
        assert_eq!(actual(1, before, marked(0)), result(before, 1, 0, 0));
    }}}
}

#[test]
fn pairing_commit_active_viewer_authenticates_before_missing_cache_refusal() {
    for cache in 0..=3 {
        let before = state(1, 3, cache);
        assert_eq!(actual(1, before, event(6)), result(before, 2, 0, 3));
    }
    assert_eq!(actual(1, state(1, 3, 4), event(6)), result(state(1, 3, 4), 0, 3, 3));
}

#[test]
fn pairing_commit_issued_viewer_requires_completion_auth_and_activation_constructor() {
    for cache in 0..=4 {
        assert_eq!(actual(1, state(1, 1, cache), event(6)), result(state(1, 3, 4), 0, 8, 3));
    }
}

#[test]
fn pairing_commit_activation_ack_authenticates_active_replay_and_retires_cache() {
    for phase in [2, 3] { for cache in 0..=4 {
        assert_eq!(actual(1, state(0, phase, cache), event(7)), result(state(0, 3, 0), 0, 0, 4));
    }}
}

#[test]
fn pairing_commit_role_and_phase_guards_precede_inbound_authentication() {
    for cache in 0..=4 {
        for opcode in [1, 3, 4, 7] {
            let before = state(1, 0, cache);
            assert_eq!(actual(1, before, event(opcode)), result(before, 1, 0, 0));
        }
        for opcode in [2, 6] {
            let before = state(0, 0, cache);
            assert_eq!(actual(1, before, event(opcode)), result(before, 1, 0, 0));
        }
        assert_eq!(actual(1, state(1, 2, cache), event(2)), result(state(1, 2, cache), 1, 0, 0));
        assert_eq!(actual(1, state(0, 1, cache), event(3)), result(state(0, 1, cache), 1, 0, 0));
        assert_eq!(actual(1, state(1, 0, cache), event(6)), result(state(1, 0, cache), 1, 0, 0));
    }
}

#[test]
fn pairing_commit_stored_shape_exactly_matches_original_eight_allowed_shapes() {
    let allowed = [(0, 0, 0), (0, 0, 1), (0, 2, 0), (0, 2, 3),
        (0, 3, 0), (1, 0, 0), (1, 1, 2), (1, 3, 4)];
    let mut admitted = 0;
    for role in 0..=1 { for phase in 0..=3 { for cache in 0..=4 {
        let before = state(role, phase, cache);
        let expected = if allowed.contains(&(role, phase, cache)) {
            admitted += 1;
            result(before, 0, if cache == 0 { 0 } else { 9 }, 0)
        } else { result(before, 3, 0, 0) };
        assert_eq!(actual(1, before, event(8)), expected);
    }}}
    assert_eq!(admitted, 8);
}

#[test]
fn pairing_commit_invalid_abi_domains_and_reserved_fields_preserve_raw_snapshot() {
    let before = state(1, 3, 4);
    for bad in [0, 2, u32::MAX] {
        assert_eq!(actual(bad, before, event(6)), result(before, 4, 0, 0));
        let raw = RawState { abi_version: bad, ..before };
        assert_eq!(actual(1, raw, event(6)), result(raw, 4, 0, 0));
    }
    for bad in [2, 5, 31, u32::MAX] {
        let role = RawState { local_role: bad, ..before };
        assert_eq!(actual(1, role, event(6)), result(role, 4, 0, 0));
    }
    for bad in [4, 5, 31, u32::MAX] {
        let phase = RawState { pairing_state: bad, ..before };
        assert_eq!(actual(1, phase, event(6)), result(phase, 4, 0, 0));
    }
    for bad in [5, 6, 31, u32::MAX] {
        let cache = RawState { recovery_phase: bad, ..before };
        assert_eq!(actual(1, cache, event(6)), result(cache, 4, 0, 0));
    }
    for bad in [9, 10, 31, u32::MAX] {
        assert_eq!(actual(1, before, event(bad)), result(before, 4, 0, 0));
    }
    for bad in [2, 3, 31, u32::MAX] {
        assert_eq!(actual(1, before, marked(bad)), result(before, 4, 0, 0));
    }
    for bit in 0..32 {
        let bad = 1u32 << bit;
        for raw in [RawState { reserved: bad, ..before }, RawState { reserved_tail: bad, ..before }] {
            assert_eq!(actual(1, raw, event(6)), result(raw, 4, 0, 0));
        }
        for input in [RawEvent { reserved: bad, ..event(6) }, RawEvent { reserved_tail: bad, ..event(6) }] {
            assert_eq!(actual(1, before, input), result(before, 4, 0, 0));
        }
    }
}

#[test]
fn pairing_commit_unused_uuid_fact_is_not_an_alternative_authorization() {
    let before = state(0, 2, 3);
    for opcode in [0, 1, 2, 3, 4, 6, 7, 8] {
        let input = RawEvent { commit_id_matches: 1, ..event(opcode) };
        assert_eq!(actual(1, before, input), result(before, 4, 0, 0));
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct OwnedModel { raw: RawState, opaque_cache: Option<u64>, unrelated: u64 }

// Models native ordering only, not real signatures, construction, persistence,
// ownership, transmission or durable readback. No test may label this crypto proof.
fn modeled_call(before: OwnedModel, plan: RawResult, authenticated: bool,
    constructor_succeeds: bool, stored_proof_valid: bool, fresh_tag: u64) -> OwnedModel {
    if plan.auth_phase != 0 && !authenticated { return before; }
    if plan.decision != 0 { return before; }
    if plan.action == 9 && !stored_proof_valid { return before; }
    if (5..=8).contains(&plan.action) && !constructor_succeeds { return before; }
    let opaque_cache = if plan.candidate_state.recovery_phase == 0 { None }
        else if (5..=8).contains(&plan.action) { Some(fresh_tag) } else { before.opaque_cache };
    OwnedModel { raw: plan.candidate_state, opaque_cache, unrelated: before.unrelated }
}

#[test]
fn pairing_commit_proposals_commit_only_after_modeled_authentication_and_constructor() {
    let inputs = [(state(0, 0, 0), event(1)), (state(1, 0, 0), event(2)),
        (state(0, 2, 0), event(4)), (state(1, 1, 2), event(6))];
    for (raw, input) in inputs {
        let before = OwnedModel { raw, opaque_cache: if raw.recovery_phase == 0 { None } else { Some(17) }, unrelated: 89 };
        let plan = actual(1, raw, input);
        assert_eq!(modeled_call(before, plan, true, false, true, 101), before);
        if plan.auth_phase != 0 {
            assert_eq!(modeled_call(before, plan, false, true, true, 101), before);
        }
        let after = modeled_call(before, plan, true, true, true, 101);
        assert_eq!(after.raw, plan.candidate_state);
        assert_eq!(after.unrelated, 89);
        assert_eq!(after.opaque_cache, Some(101));
        assert_eq!(before.raw, raw);
    }
    let ephemeral = OwnedModel { raw: state(0, 3, 0), opaque_cache: None, unrelated: 89 };
    assert_eq!(modeled_call(ephemeral, actual(1, ephemeral.raw, event(4)), true, true, true, 101), ephemeral);
}

#[test]
fn pairing_commit_seeded_bounded_histories_and_value_copies_match_reference() {
    let mut comparisons = 0;
    for seed in 0..100u64 {
        let raw = state((seed % 2) as u32, ((seed / 2) % 4) as u32, ((seed / 8) % 5) as u32);
        let initial = OwnedModel { raw, opaque_cache: if raw.recovery_phase == 0 { None } else { Some(seed + 1) }, unrelated: seed + 701 };
        let mut live = initial;
        let untouched = initial;
        let mut expected = initial;
        let mut random = seed + 97;
        for index in 0..160u64 {
            random = random.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            let opcode = (random % 9) as u32;
            let input = RawEvent { commit_id_matches: if opcode == 5 { ((random >> 8) & 1) as u32 } else { 0 }, ..event(opcode) };
            let auth = random & (1 << 16) != 0;
            let constructor = random & (1 << 24) != 0;
            let stored = random & (1 << 32) != 0;
            let actual_plan = actual(1, live.raw, input);
            let reference_plan = original_reference(1, expected.raw, input);
            assert_eq!(actual_plan, reference_plan);
            live = modeled_call(live, actual_plan, auth, constructor, stored, 10_000 + seed * 160 + index);
            expected = modeled_call(expected, reference_plan, auth, constructor, stored, 10_000 + seed * 160 + index);
            assert_eq!(live, expected);
            assert_eq!(untouched, initial);
            comparisons += 1;
        }
    }
    assert_eq!(comparisons, 16_000);
}

#[test]
fn pairing_commit_all_rejected_plans_preserve_whole_candidate_without_actions() {
    for role in 0..=1 { for phase in 0..=3 { for cache in 0..=4 { for opcode in 0..=8 {
        let before = state(role, phase, cache);
        let input = if opcode == 5 { marked(1) } else { event(opcode) };
        let output = actual(1, before, input);
        if output.decision != 0 {
            assert_eq!(output.candidate_state, before);
            assert_eq!(output.action, 0);
            assert_eq!(output.reserved, 0);
            assert_eq!(output.auth_phase, if output.decision == 2 { 3 } else { 0 });
        }
    }}}}
}

// These are specification-model traces,
// not observed native execution, actual cryptography or durable storage proof.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ModelFailure { Identity, InvalidCommit, Authentication, Canonical, Constructor, StoredRecord, Bridge }

#[derive(Clone, Copy)]
enum ModeledVerification { Valid, InvalidStructure, InvalidAuthentication, CanonicalFailure }

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ModelObservation {
    Authenticate(u32), Construct(u32), VerifyStored, ReturnCached(u64), Commit,
    Throw(ModelFailure),
}

#[derive(Debug, Eq, PartialEq)]
struct ObservedModel { record: OwnedModel, returned_proof: Option<u64>, observations: Vec<ModelObservation> }

// The intended native plan interpreter, independently checked below against
// literal original-method observations. It is not an accepted-state reducer.
fn observe_plan(before: OwnedModel, input: RawEvent, plan: RawResult,
    identity_matches: bool, verification: ModeledVerification,
    constructor_succeeds: bool, stored_proof_valid: bool, fresh_tag: u64) -> ObservedModel {
    let mut output = ObservedModel { record: before, returned_proof: None, observations: Vec::new() };
    let identity_role = match input.opcode { 1 | 4 => Some(0), 2 | 6 => Some(1), _ => None };
    if identity_role.is_some_and(|role| before.raw.local_role != role || !identity_matches) {
        output.observations.push(ModelObservation::Throw(ModelFailure::Identity)); return output;
    }
    if plan.decision == 1 {
        output.observations.push(ModelObservation::Throw(ModelFailure::InvalidCommit)); return output;
    }
    if plan.decision == 3 || plan.decision == 4 {
        output.observations.push(ModelObservation::Throw(if plan.decision == 3 { ModelFailure::StoredRecord } else { ModelFailure::Bridge }));
        return output;
    }
    if plan.auth_phase != 0 {
        output.observations.push(ModelObservation::Authenticate(plan.auth_phase));
        let failure = match verification {
            ModeledVerification::Valid => None,
            ModeledVerification::InvalidStructure => Some(ModelFailure::InvalidCommit),
            ModeledVerification::InvalidAuthentication => Some(ModelFailure::Authentication),
            ModeledVerification::CanonicalFailure => Some(ModelFailure::Canonical),
        };
        if let Some(failure) = failure {
            output.observations.push(ModelObservation::Throw(failure)); return output;
        }
    }
    if plan.decision == 2 {
        output.observations.push(ModelObservation::Throw(ModelFailure::InvalidCommit)); return output;
    }
    if plan.action == 9 {
        output.observations.push(ModelObservation::VerifyStored);
        if !stored_proof_valid {
            output.observations.push(ModelObservation::Throw(ModelFailure::StoredRecord)); return output;
        }
    }
    if (5..=8).contains(&plan.action) {
        output.observations.push(ModelObservation::Construct(plan.action - 4));
        if !constructor_succeeds {
            output.observations.push(ModelObservation::Throw(ModelFailure::Constructor)); return output;
        }
        output.returned_proof = Some(fresh_tag);
    } else if plan.action == 3 {
        output.returned_proof = before.opaque_cache;
        output.observations.push(ModelObservation::ReturnCached(before.opaque_cache.expect("known present cache in modeled record")));
    }
    if plan.candidate_state != before.raw {
        output.observations.push(ModelObservation::Commit);
        output.record.raw = plan.candidate_state;
        output.record.opaque_cache = if plan.candidate_state.recovery_phase == 0 { None }
            else if (5..=8).contains(&plan.action) { Some(fresh_tag) } else { before.opaque_cache };
    }
    output
}

#[test]
fn pairing_commit_every_ready_plan_has_deterministic_modeled_failure_and_cache_custody() {
    for role in 0..=1 { for phase in 0..=3 { for cache in 0..=4 { for opcode in 0..=8 {
        let maximum_exact = if opcode == 5 { 1 } else { 0 };
        for exact in 0..=maximum_exact {
            let raw = state(role, phase, cache);
            let before = OwnedModel { raw, opaque_cache: if cache == 0 { None } else { Some(73) }, unrelated: 809 };
            let input = RawEvent { commit_id_matches: exact, ..event(opcode) };
            let plan = actual(1, raw, input);
            if plan.decision != 0 { continue; }
            if plan.auth_phase != 0 {
                let observed = observe_plan(before, input, plan, true, ModeledVerification::InvalidAuthentication, true, true, 991);
                assert_eq!(observed, ObservedModel { record: before, returned_proof: None,
                    observations: vec![ModelObservation::Authenticate(plan.auth_phase), ModelObservation::Throw(ModelFailure::Authentication)] });
            }
            if (5..=8).contains(&plan.action) {
                let mut expected = Vec::new();
                if plan.auth_phase != 0 { expected.push(ModelObservation::Authenticate(plan.auth_phase)); }
                expected.push(ModelObservation::Construct(plan.action - 4));
                expected.push(ModelObservation::Throw(ModelFailure::Constructor));
                assert_eq!(observe_plan(before, input, plan, true, ModeledVerification::Valid, false, true, 991),
                    ObservedModel { record: before, returned_proof: None, observations: expected });
            }
            if plan.action == 3 {
                let mut expected = Vec::new();
                if plan.auth_phase != 0 { expected.push(ModelObservation::Authenticate(plan.auth_phase)); }
                expected.push(ModelObservation::ReturnCached(73));
                assert_eq!(observe_plan(before, input, plan, true, ModeledVerification::Valid, true, true, 991),
                    ObservedModel { record: before, returned_proof: Some(73), observations: expected });
            }
            if plan.action == 9 {
                assert_eq!(observe_plan(before, input, plan, true, ModeledVerification::Valid, true, false, 991),
                    ObservedModel { record: before, returned_proof: None,
                        observations: vec![ModelObservation::VerifyStored, ModelObservation::Throw(ModelFailure::StoredRecord)] });
            }
        }
    }}}}
}

#[test]
fn pairing_commit_critical_modeled_error_priority_uses_literal_original_traces() {
    // Issued viewer returns an exact existing cache only after the new proposal
    // is verified; constructor failure cannot matter on this cached path.
    for cache in 1..=4 {
        let before = OwnedModel { raw: state(1, 1, cache), opaque_cache: Some(73), unrelated: 809 };
        let plan = actual(1, before.raw, event(2));
        assert_eq!(observe_plan(before, event(2), plan, true,
            ModeledVerification::InvalidAuthentication, false, true, 991),
            ObservedModel { record: before, returned_proof: None,
                observations: vec![ModelObservation::Authenticate(1), ModelObservation::Throw(ModelFailure::Authentication)] });
        assert_eq!(observe_plan(before, event(2), plan, true,
            ModeledVerification::Valid, false, true, 991),
            ObservedModel { record: before, returned_proof: Some(73),
                observations: vec![ModelObservation::Authenticate(1), ModelObservation::ReturnCached(73)] });
    }
    // Host ACK replay must neither skip authentication nor retire the cache.
    for phase in [2, 3] { for cache in 0..=4 {
        let before = OwnedModel { raw: state(0, phase, cache),
            opaque_cache: if cache == 0 { None } else { Some(73) }, unrelated: 809 };
        let plan = actual(1, before.raw, event(3));
        assert_eq!(observe_plan(before, event(3), plan, true,
            ModeledVerification::InvalidAuthentication, false, true, 991),
            ObservedModel { record: before, returned_proof: None,
                observations: vec![ModelObservation::Authenticate(2), ModelObservation::Throw(ModelFailure::Authentication)] });
        assert_eq!(observe_plan(before, event(3), plan, true,
            ModeledVerification::Valid, false, true, 991),
            ObservedModel { record: before, returned_proof: None,
                observations: vec![ModelObservation::Authenticate(2)] });
    }}
    // Active viewer: actual inbound verification outranks absent/wrong cache.
    for cache in 0..=3 {
        let raw = state(1, 3, cache);
        let before = OwnedModel { raw, opaque_cache: if cache == 0 { None } else { Some(73) }, unrelated: 809 };
        let plan = actual(1, raw, event(6));
        for (verification, failure) in [(ModeledVerification::InvalidStructure, ModelFailure::InvalidCommit),
            (ModeledVerification::InvalidAuthentication, ModelFailure::Authentication),
            (ModeledVerification::CanonicalFailure, ModelFailure::Canonical)] {
            assert_eq!(observe_plan(before, event(6), plan, true, verification, false, true, 991),
                ObservedModel { record: before, returned_proof: None,
                    observations: vec![ModelObservation::Authenticate(3), ModelObservation::Throw(failure)] });
        }
        assert_eq!(observe_plan(before, event(6), plan, true, ModeledVerification::Valid, true, true, 991),
            ObservedModel { record: before, returned_proof: None,
                observations: vec![ModelObservation::Authenticate(3), ModelObservation::Throw(ModelFailure::InvalidCommit)] });
    }
    let active_viewer = OwnedModel { raw: state(1, 3, 4), opaque_cache: Some(73), unrelated: 809 };
    let active_plan = actual(1, active_viewer.raw, event(6));
    assert_eq!(observe_plan(active_viewer, event(6), active_plan, true,
        ModeledVerification::InvalidAuthentication, false, true, 991),
        ObservedModel { record: active_viewer, returned_proof: None,
            observations: vec![ModelObservation::Authenticate(3), ModelObservation::Throw(ModelFailure::Authentication)] });
    assert_eq!(observe_plan(active_viewer, event(6), active_plan, true,
        ModeledVerification::Valid, false, true, 991),
        ObservedModel { record: active_viewer, returned_proof: Some(73),
            observations: vec![ModelObservation::Authenticate(3), ModelObservation::ReturnCached(73)] });
    // Identity-taking methods: wrong supplied/local identity precedes state or auth.
    for (raw, opcode) in [(state(1, 3, 0), 1), (state(0, 2, 3), 2),
        (state(1, 0, 0), 4), (state(0, 0, 0), 6), (state(1, 3, 4), 6)] {
        let before = OwnedModel { raw, opaque_cache: if raw.recovery_phase == 0 { None } else { Some(73) }, unrelated: 809 };
        assert_eq!(observe_plan(before, event(opcode), actual(1, raw, event(opcode)), false,
            ModeledVerification::InvalidAuthentication, false, false, 991),
            ObservedModel { record: before, returned_proof: None,
                observations: vec![ModelObservation::Throw(ModelFailure::Identity)] });
    }
    // Non-identity host ACK and viewer invalid phase refuse before verification.
    for (raw, opcode) in [(state(0, 1, 2), 3), (state(1, 0, 0), 6)] {
        let before = OwnedModel { raw, opaque_cache: if raw.recovery_phase == 0 { None } else { Some(73) }, unrelated: 809 };
        assert_eq!(observe_plan(before, event(opcode), actual(1, raw, event(opcode)), true,
            ModeledVerification::InvalidAuthentication, false, false, 991),
            ObservedModel { record: before, returned_proof: None,
                observations: vec![ModelObservation::Throw(ModelFailure::InvalidCommit)] });
    }
    // Active host completion is returned but never persisted as recovery again.
    let before = OwnedModel { raw: state(0, 3, 0), opaque_cache: None, unrelated: 809 };
    assert_eq!(observe_plan(before, event(4), actual(1, before.raw, event(4)), true,
        ModeledVerification::Valid, true, true, 991), ObservedModel { record: before,
        returned_proof: Some(991), observations: vec![ModelObservation::Construct(3)] });
}
