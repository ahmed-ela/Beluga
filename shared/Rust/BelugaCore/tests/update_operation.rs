use beluga_core::beluga_core_update_operation_step as actual;
use beluga_core::update_operation::{RawEvent, RawResult, RawState};
use std::mem::{align_of, offset_of, size_of};

// Raw DTO construction only. No production decoder/enum/guard is used in expected results.
fn state(stage: u32, mask: u32) -> RawState {
    RawState { abi_version: 1, reserved: 0, stage,
        broker_present: mask & 1, candidate_present: (mask >> 1) & 1,
        recorded_readiness_present: (mask >> 2) & 1, installed_fresh: (mask >> 3) & 1,
        readiness_fresh: (mask >> 4) & 1, challenge_present: (mask >> 5) & 1, reserved_tail: 0 }
}
fn event(opcode: u32, facts: [u32; 7]) -> RawEvent {
    RawEvent { opcode, reserved: 0, fact0: facts[0], fact1: facts[1], fact2: facts[2],
        fact3: facts[3], fact4: facts[4], fact5: facts[5], fact6: facts[6], reserved_tail: 0 }
}
fn allowed(opcode: u32) -> RawEvent {
    let facts = match opcode {
        0 | 1 => [1,1,1,1,0,0,0], 2 => [1,0,0,0,0,0,0], 3 => [1,1,0,0,0,0,0],
        4 | 5 => [1,1,1,1,1,1,0], 6 => [1,1,1,1,1,1,1], _ => [0;7],
    };
    event(opcode, facts)
}
fn result(before: RawState, decision: u32, action: u32, predicate: u32) -> RawResult {
    RawResult { candidate_state: before, decision, action, predicate, reserved: 0 }
}

// Frozen original BelugaUpdateOperation.swift guards/assignments, scalar projection only.
// This independent oracle uses literal numeric domains and original Swift clauses. It does
// not call the Rust reducer, decoder, typed enums, helpers, or its predicate implementation.
fn original_reference(abi: u32, before: RawState, input: RawEvent) -> RawResult {
    let f = [input.fact0,input.fact1,input.fact2,input.fact3,input.fact4,input.fact5,input.fact6];
    if abi != 1 || before.abi_version != 1 || before.reserved != 0 || before.reserved_tail != 0
        || before.stage > 3 || before.broker_present > 1 || before.candidate_present > 1
        || before.recorded_readiness_present > 1 || before.installed_fresh > 1
        || before.readiness_fresh > 1 || before.challenge_present > 1
        || input.reserved != 0 || input.reserved_tail != 0 || input.opcode > 13
        || f.iter().any(|value| *value > 1) {
        return result(before,2,0,0);
    }
    let used = match input.opcode { 0|1 => 4, 2 => 1, 3 => 2, 4|5 => 6, 6 => 7, _ => 0 };
    if f[used..].iter().any(|value| *value != 0) { return result(before,2,0,0); }
    let mut after = before;
    match input.opcode {
        0 => {
            if f[0] == 0 || before.stage != 0 || before.broker_present != 0
                || f[1] == 0 || f[2] == 0 || f[3] == 0 { return result(before,1,0,0); }
            after.broker_present = 1;
            result(after,0,1,0)
        }
        1 => {
            if f[0] == 0 || before.candidate_present != 0 || (before.stage != 0 && before.stage != 1)
                || f[1] == 0 || f[2] == 0 || f[3] == 0 { return result(before,1,0,0); }
            after.candidate_present = 1;
            result(after,0,2,0)
        }
        2 => {
            if f[0] == 0 || before.stage != 0 || before.broker_present != 1 { return result(before,1,0,0); }
            after.stage = 1;
            result(after,0,3,0)
        }
        3 => {
            if f[0] == 0 || before.stage == 0 || before.broker_present != 1
                || before.installed_fresh != 0 || before.candidate_present != 1 || f[1] == 0 {
                return result(before,1,0,0);
            }
            if before.stage == 1 { after.stage = 2; }
            after.installed_fresh = 1;
            after.readiness_fresh = 0;
            after.challenge_present = 0;
            result(after,0,4,0)
        }
        4 => {
            if before.installed_fresh != 1 || before.readiness_fresh != 0
                || before.challenge_present != 0 || before.candidate_present != 1
                || f[0] == 0 || f[1] == 0 || f[2] == 0 || f[3] == 0 || f[4] == 0 || f[5] == 0 {
                return result(before,1,0,0);
            }
            after.challenge_present = 1;
            result(after,0,5,0)
        }
        5 | 6 => {
            if before.installed_fresh != 1 || before.challenge_present != 1
                || f[0] == 0 || f[1] == 0 || f[2] == 0 || f[3] == 0 || f[4] == 0 || f[5] == 0 {
                return result(before,1,0,0);
            }
            if input.opcode == 5 { return result(before,0,6,0); }
            if f[6] == 0 { return result(before,1,0,0); }
            after.challenge_present = 0;
            after.recorded_readiness_present = 1;
            after.stage = 3;
            after.readiness_fresh = 1;
            result(after,0,7,0)
        }
        7 | 8 => result(before,0,0,0),
        9 | 10 => {
            after.installed_fresh = 0;
            after.readiness_fresh = 0;
            after.challenge_present = 0;
            result(after,0,8,0)
        }
        11 => result(before,0,0,if before.stage != 0 {1} else {0}),
        12 => result(before,0,0,if before.broker_present == 1 && before.stage == 3
            && before.installed_fresh == 1 && before.readiness_fresh == 1 {1} else {0}),
        _ => result(before,0,0,0),
    }
}

#[test]
fn updater_operation_exact_copied_layout_and_export() {
    assert_eq!((size_of::<RawState>(),align_of::<RawState>()),(40,4));
    assert_eq!([offset_of!(RawState,abi_version),offset_of!(RawState,reserved),offset_of!(RawState,stage),
        offset_of!(RawState,broker_present),offset_of!(RawState,candidate_present),offset_of!(RawState,recorded_readiness_present),
        offset_of!(RawState,installed_fresh),offset_of!(RawState,readiness_fresh),offset_of!(RawState,challenge_present),offset_of!(RawState,reserved_tail)],
        [0,4,8,12,16,20,24,28,32,36]);
    assert_eq!((size_of::<RawEvent>(),align_of::<RawEvent>()),(40,4));
    assert_eq!([offset_of!(RawEvent,opcode),offset_of!(RawEvent,reserved),offset_of!(RawEvent,fact0),offset_of!(RawEvent,fact1),
        offset_of!(RawEvent,fact2),offset_of!(RawEvent,fact3),offset_of!(RawEvent,fact4),offset_of!(RawEvent,fact5),offset_of!(RawEvent,fact6),offset_of!(RawEvent,reserved_tail)],
        [0,4,8,12,16,20,24,28,32,36]);
    assert_eq!((size_of::<RawResult>(),align_of::<RawResult>()),(56,4));
    assert_eq!([offset_of!(RawResult,candidate_state),offset_of!(RawResult,decision),offset_of!(RawResult,action),offset_of!(RawResult,predicate),offset_of!(RawResult,reserved)],
        [0,40,44,48,52]);
    assert_eq!(actual(1,state(0,0),allowed(0)),result(state(0,1),0,1,0));
}

#[test]
fn updater_operation_all_458752_closed_scalar_cases_match_original() {
    let mut cases = 0;
    for stage in 0..=3 { for flags in 0..64 { for opcode in 0..=13 { for facts in 0..128 {
        let input = event(opcode,[facts&1,(facts>>1)&1,(facts>>2)&1,(facts>>3)&1,(facts>>4)&1,(facts>>5)&1,(facts>>6)&1]);
        let before = state(stage,flags);
        assert_eq!(actual(1,before,input),original_reference(1,before,input),"stage={stage} flags={flags} opcode={opcode} facts={facts}");
        cases += 1;
    }}}}
    assert_eq!(cases,458_752);
}

#[test]
fn updater_operation_literal_broker_binding_is_once_prepared_and_exact() {
    assert_eq!(actual(1,state(0,0),allowed(0)),result(state(0,1),0,1,0));
    for stage in 1..=3 { assert_eq!(actual(1,state(stage,0),allowed(0)),result(state(stage,0),1,0,0)); }
    assert_eq!(actual(1,state(0,1),allowed(0)),result(state(0,1),1,0,0));
    for index in 0..4 {
        let mut facts=[1,1,1,1,0,0,0]; facts[index]=0;
        assert_eq!(actual(1,state(0,0),event(0,facts)),result(state(0,0),1,0,0));
    }
}

#[test]
fn updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage() {
    for stage in 0..=1 { assert_eq!(actual(1,state(stage,1),allowed(1)),result(state(stage,3),0,2,0)); }
    for stage in 2..=3 { assert_eq!(actual(1,state(stage,1),allowed(1)),result(state(stage,1),1,0,0)); }
    assert_eq!(actual(1,state(0,3),allowed(1)),result(state(0,3),1,0,0));
    for index in 0..4 {
        let mut facts=[1,1,1,1,0,0,0]; facts[index]=0;
        assert_eq!(actual(1,state(0,1),event(1,facts)),result(state(0,1),1,0,0));
    }
}

#[test]
fn updater_operation_literal_arming_requires_exact_binding_and_bound_broker() {
    assert_eq!(actual(1,state(0,1),allowed(2)),result(state(1,1),0,3,0));
    assert_eq!(actual(1,state(0,0),allowed(2)),result(state(0,0),1,0,0));
    assert_eq!(actual(1,state(0,1),event(2,[0;7])),result(state(0,1),1,0,0));
    for stage in 1..=3 { assert_eq!(actual(1,state(stage,1),allowed(2)),result(state(stage,1),1,0,0)); }
}

#[test]
fn updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion() {
    assert_eq!(actual(1,state(1,3),allowed(3)),result(state(2,11),0,4,0));
    for before in [state(0,3),state(1,2),state(1,1),state(2,11)] {
        assert_eq!(actual(1,before,allowed(3)),result(before,1,0,0));
    }
    for input in [event(3,[0,1,0,0,0,0,0]),event(3,[1,0,0,0,0,0,0])] {
        assert_eq!(actual(1,state(1,3),input),result(state(1,3),1,0,0));
    }
}

#[test]
fn updater_operation_literal_restored_terminal_needs_fresh_proof_but_retains_recorded_stage() {
    assert_eq!(actual(1,state(3,7),allowed(12)),result(state(3,7),0,0,0));
    assert_eq!(actual(1,state(3,7),allowed(3)),result(state(3,15),0,4,0));
    assert_eq!(actual(1,state(3,15),allowed(4)),result(state(3,47),0,5,0));
    assert_eq!(actual(1,state(3,47),allowed(6)),result(state(3,31),0,7,0));
    assert_eq!(actual(1,state(3,31),allowed(12)),result(state(3,31),0,0,1));
}

#[test]
fn updater_operation_literal_install_clears_only_ephemeral_readiness_and_challenge() {
    assert_eq!(actual(1,state(1,55),allowed(3)),result(state(2,15),0,4,0));
    assert_eq!(actual(1,state(2,55),allowed(3)),result(state(2,15),0,4,0));
    assert_eq!(actual(1,state(3,55),allowed(3)),result(state(3,15),0,4,0));
}

#[test]
fn updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards() {
    assert_eq!(actual(1,state(2,11),allowed(4)),result(state(2,43),0,5,0));
    for before in [state(2,3),state(2,27),state(2,43),state(2,9)] {
        assert_eq!(actual(1,before,allowed(4)),result(before,1,0,0));
    }
    for index in 0..6 {
        let mut facts=[1,1,1,1,1,1,0]; facts[index]=0;
        assert_eq!(actual(1,state(2,11),event(4,facts)),result(state(2,11),1,0,0));
    }
}

#[test]
fn updater_operation_literal_readiness_preflight_changes_no_state_before_encoding() {
    assert_eq!(actual(1,state(2,43),allowed(5)),result(state(2,43),0,6,0));
    for before in [state(2,35),state(2,11)] {
        assert_eq!(actual(1,before,allowed(5)),result(before,1,0,0));
    }
    for index in 0..6 {
        let mut facts=[1,1,1,1,1,1,0]; facts[index]=0;
        assert_eq!(actual(1,state(2,43),event(5,facts)),result(state(2,43),1,0,0));
    }
}

#[test]
fn updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding() {
    assert_eq!(actual(1,state(2,43),allowed(6)),result(state(3,31),0,7,0));
    for before in [state(2,35),state(2,11)] {
        assert_eq!(actual(1,before,allowed(6)),result(before,1,0,0));
    }
    for index in 0..7 {
        let mut facts=[1;7]; facts[index]=0;
        assert_eq!(actual(1,state(2,43),event(6,facts)),result(state(2,43),1,0,0));
    }
}

#[test]
fn updater_operation_literal_cancellation_and_idle_never_release_fresh_or_armed_state() {
    for opcode in [7,8] { for before in [state(0,0),state(1,3),state(2,43),state(3,31)] {
        assert_eq!(actual(1,before,allowed(opcode)),result(before,0,0,0));
    }}
}

#[test]
fn updater_operation_literal_failure_revokes_only_ephemeral_proof_and_challenge() {
    for opcode in [9,10] {
        assert_eq!(actual(1,state(3,63),allowed(opcode)),result(state(3,7),0,8,0));
        assert_eq!(actual(1,state(1,3),allowed(opcode)),result(state(1,3),0,8,0));
    }
}

#[test]
fn updater_operation_literal_release_requires_broker_terminal_and_both_fresh_proofs() {
    assert_eq!(actual(1,state(3,31),allowed(12)),result(state(3,31),0,0,1));
    for before in [state(2,31),state(3,30),state(3,23),state(3,15)] {
        assert_eq!(actual(1,before,allowed(12)),result(before,0,0,0));
    }
    // Exact original getter has no new candidate/readiness-shape requirement.
    assert_eq!(actual(1,state(3,25),allowed(12)),result(state(3,25),0,0,1));
}

#[test]
fn updater_operation_literal_runtime_never_activates_and_armed_getter_is_stage_only() {
    for stage in 0..=3 { for mask in 0..64 {
        let before=state(stage,mask);
        assert_eq!(actual(1,before,allowed(11)),result(before,0,0,if stage==0 {0} else {1}));
        assert_eq!(actual(1,before,allowed(13)),result(before,0,0,0));
    }}
}

#[test]
fn updater_operation_literal_complete_accepted_trace_is_not_runtime_authority() {
    let mut before=state(0,0);
    for (opcode,expected) in [
        (0,result(state(0,1),0,1,0)),(1,result(state(0,3),0,2,0)),
        (2,result(state(1,3),0,3,0)),(3,result(state(2,11),0,4,0)),
        (4,result(state(2,43),0,5,0)),(5,result(state(2,43),0,6,0)),
        (6,result(state(3,31),0,7,0)),(12,result(state(3,31),0,0,1)),
        (13,result(state(3,31),0,0,0))] {
        let output=actual(1,before,allowed(opcode)); assert_eq!(output,expected); before=output.candidate_state;
    }
}

#[test]
fn updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all() {
    let grant=state(3,31);
    for abi in [0,2,u32::MAX] { assert_eq!(actual(abi,grant,allowed(12)),result(grant,2,0,0)); }
    for index in 0..10 { for value in [2,u32::MAX] {
        let mut malformed=grant;
        match index { 0=>malformed.abi_version=value,1=>malformed.reserved=value,2=>malformed.stage=if value==2 {4} else {value},
            3=>malformed.broker_present=value,4=>malformed.candidate_present=value,5=>malformed.recorded_readiness_present=value,
            6=>malformed.installed_fresh=value,7=>malformed.readiness_fresh=value,8=>malformed.challenge_present=value,_=>malformed.reserved_tail=value }
        assert_eq!(actual(1,malformed,allowed(12)),result(malformed,2,0,0));
    }}
    for input in [RawEvent{reserved:1,..allowed(12)},RawEvent{reserved_tail:1,..allowed(12)}] {
        assert_eq!(actual(1,grant,input),result(grant,2,0,0));
    }
}

#[test]
fn updater_operation_malformed_event_domains_unknown_opcodes_and_unused_facts_preserve_state() {
    let grant=state(3,31);
    for opcode in [14,15,u32::MAX] { assert_eq!(actual(1,grant,event(opcode,[0;7])),result(grant,2,0,0)); }
    for opcode in 0..=13 { for index in 0..7 { for value in [2,u32::MAX] {
        let mut facts=[0;7]; facts[index]=value;
        assert_eq!(actual(1,grant,event(opcode,facts)),result(grant,2,0,0));
    }}}
    for opcode in 0..=13 {
        let used=match opcode {0|1=>4,2=>1,3=>2,4|5=>6,6=>7,_=>0};
        for index in used..7 {
            let mut facts=[0;7]; facts[index]=1;
            assert_eq!(actual(1,grant,event(opcode,facts)),result(grant,2,0,0));
        }
    }
}
