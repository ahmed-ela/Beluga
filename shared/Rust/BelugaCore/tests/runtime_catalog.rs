//! Expected values are independent ORIGINAL coordinator cuts plus approved ABI
//! 419829a330c03550c1d6948d291699293cca95120adf98da5a9ddfd7f9dc125e.
//! Every checked transition calls the real C export before constructing its oracle.
use beluga_core::runtime_catalog::{RawRuntimeCatalogState as S, RawRuntimeCatalogEvent as E,
    RawRuntimeCatalogResult as R};
use beluga_core::{beluga_core_runtime_catalog_step as call,
    beluga_core_runtime_catalog_result_is_valid as verify};

const MASKS: [u32; 58] = [
    3,31,0,2047,1,1,3,1,3,3,1,3,127,3,7,1,3,1,1,1,1,1,0,1,7,3,1,7,3,
    3,1,3,2047,1,7,1,3,3,7,1,1023,3,1,63,3,1023,31,15,0,3,1,3,1,3,3,7,7,1,
];
const DENIALS: [u32; 58] = [
    2,0,0,5,6,6,2,7,7,7,1,8,7,1,1,1,1,1,1,1,5,0,0,0,8,8,1,1,1,
    1,9,9,9,1,1,1,1,1,1,1,1,1,1,7,1,1,8,8,0,1,1,1,1,1,7,1,8,7,
];
fn idle() -> S { S { abi_version: 1, ..S::default() } }
fn at(phase: u32, operation: u32, eligible: u32, intent: u32, first_grant: u32) -> S {
    S { abi_version: 1, phase, operation, eligible, intent, first_grant }
}
fn event(opcode: u32, operation: u32, facts: u32) -> E {
    E { opcode, operation, facts, reserved: 0 }
}
fn out(state: S, status: u32, decision: u32, effect: u32, value: u32) -> R {
    R { state, status, decision, effect, value }
}
fn denied(s: S, decision: u32) -> R { out(s, 1, decision, 0, 0) }
fn malformed_result(s: S) -> R { out(s, 0, 0, 0, 0) }
fn known_mask(e: E) -> u32 {
    if e.opcode == 2 {
        match e.operation { 1 => 3, 2 => 2, 3 => 28, _ => panic!("bad oracle operation") }
    } else { MASKS[e.opcode as usize] }
}
fn states() -> Vec<S> {
    // Independent native-custody legal snapshots, not derived from producer acceptance.
    let mut all = vec![idle(), at(0,0,1,0,0), at(0,0,0,1,0), at(3,0,0,0,0)];
    for op in 1..=3 {
        all.push(at(1,op,0,0,0));
        all.push(at(2,op,0,0,0));
        all.push(at(2,op,0,1,0));
    }
    all.push(at(1,3,0,0,1));
    all.push(at(2,3,0,0,1));
    all
}
fn check(s: S, e: E, expected: impl FnOnce() -> R) -> R {
    let actual = call(s, e); // Real C export FIRST, never an adapter/self-comparison.
    let expected = expected();
    assert_eq!(actual, expected, "state={s:?} event={e:?}");
    assert_eq!(verify(s, e, actual), u32::from(expected.status == 1));
    actual
}
fn malformed(s: S, e: E) { check(s, e, || malformed_result(s)); }

// ORIGINAL's imperative branches expressed independently as a test oracle.
// No production enum/helper/step/verifier computes these expected values.
fn original_cut(s: S, e: E) -> R {
    let all = e.facts == known_mask(e);
    let revoked = s.phase == 3;
    match e.opcode {
        0 => denied(s, if !revoked && e.facts == 0 { 0 } else { 2 }),
        1 => if s.phase != 0 || s.intent != 0 || s.first_grant != 0 {
            malformed_result(s)
        } else { out(S { eligible: u32::from(all), ..s }, 1, 0, 1, 0) },
        2 => {
            let d = match e.operation {
                1 => if e.facts & 1 != 0 && e.facts & 2 == 0 { 3 } else { 0 },
                2 => if e.facts & 2 == 0 { 3 } else { 0 },
                3 => if e.facts & 4 != 0 { 8 } else if e.facts & 24 != 24 { 4 } else { 0 },
                _ => panic!("bad oracle operation"),
            };
            denied(s, d)
        }
        3 => denied(s, if s.phase == 0 && all { 0 } else { 5 }),
        6 | 7 | 55 => denied(s, if all { 0 } else { DENIALS[e.opcode as usize] }),
        8 => {
            if s.phase != 0 { return denied(s, 7); }
            if s.intent != 0 || s.first_grant != 0 { return malformed_result(s); }
            if !all { return denied(s, 7); }
            let grant = if e.operation == 3 { s.eligible } else { 0 };
            out(S { phase: 1, operation: e.operation, eligible: 0, first_grant: grant, ..s }, 1,0,2,grant)
        }
        9 => denied(s, if (s.phase == 1 || revoked) && all { 0 } else { 7 }),
        10 => if !all { denied(s,1) } else if s.phase == 1 {
            out(S { phase: 2, ..s },1,0,3,1)
        } else if revoked { out(s,1,0,0,1) } else { malformed_result(s) },
        11 => denied(s, if s.phase == 2 && all { 0 } else { 8 }),
        12 => denied(s, if s.phase == 2 && all { 0 } else { 7 }),
        13 => if e.facts & 1 == 0 { denied(s,1) } else if s.phase != 2 {
            malformed_result(s)
        } else { out(S { phase: 0, operation: 0, first_grant: 0, ..s },1,0,4,(e.facts >> 1) & 1) },
        14 => denied(s, if s.phase == 2 && all { 0 } else { 1 }),
        21 => if s.phase != 2 || s.operation != 3 || s.intent != 0 || e.facts != s.first_grant {
            malformed_result(s)
        } else { out(S { intent: s.first_grant, first_grant: 0, ..s },1,0,5,s.first_grant) },
        22 => out(S { intent: 0, ..s },1,0,6,0),
        23 => if e.facts != s.intent { malformed_result(s) }
            else { out(S { intent: 0, ..s },1,0,7,s.intent) },
        24 => denied(s, if s.phase == 2 && s.operation == 3 && all { 0 } else { 8 }),
        48 => out(at(3,0,0,0,0),1,0,8,0),
        _ => denied(s, if !revoked && all { 0 } else { DENIALS[e.opcode as usize] }),
    }
}
fn subsets(mask: u32) -> impl Iterator<Item=u32> {
    (0..=mask).filter(move |facts| facts & !mask == 0)
}
fn matrix(rows: &[u32]) {
    for s in states() {
        for &opcode in rows {
            let operations: &[u32] = if opcode == 2 || opcode == 8 { &[1,2,3] } else { &[0] };
            for &operation in operations {
                let base = event(opcode,operation,0);
                for facts in subsets(known_mask(base)) {
                    let e = E { facts, ..base };
                    check(s,e,||original_cut(s,e));
                }
            }
        }
    }
}
fn positive(opcode: u32, s: S) -> R {
    let operation = if opcode == 2 || opcode == 8 { 3 } else { 0 };
    let mut e = event(opcode,operation,0);
    e.facts = known_mask(e);
    check(s,e,||original_cut(s,e))
}
fn s_field(mut s: S, field: usize, value: u32) -> S {
    match field { 0 => s.abi_version=value, 1 => s.phase=value, 2 => s.operation=value,
        3 => s.eligible=value, 4 => s.intent=value, 5 => s.first_grant=value,
        _ => panic!("unknown state field") }
    s
}
fn e_field(mut e: E, field: usize, value: u32) -> E {
    match field { 0 => e.opcode=value, 1 => e.operation=value, 2 => e.facts=value,
        3 => e.reserved=value, _ => panic!("unknown event field") }
    e
}
fn r_word(r: R, field: usize) -> u32 {
    match field { 0 => r.state.abi_version, 1 => r.state.phase, 2 => r.state.operation,
        3 => r.state.eligible, 4 => r.state.intent, 5 => r.state.first_grant,
        6 => r.status, 7 => r.decision, 8 => r.effect, 9 => r.value,
        _ => panic!("unknown result field") }
}
fn r_field(mut r: R, field: usize, value: u32) -> R {
    match field { 0..=5 => r.state=s_field(r.state,field,value), 6 => r.status=value,
        7 => r.decision=value, 8 => r.effect=value, 9 => r.value=value,
        _ => panic!("unknown result field") }
    r
}

#[test]
fn runtime_catalog_all_layouts_and_offsets() {
    use std::mem::{align_of,size_of,offset_of};
    assert_eq!((size_of::<S>(),align_of::<S>()),(24,4));
    assert_eq!((size_of::<E>(),align_of::<E>()),(16,4));
    assert_eq!((size_of::<R>(),align_of::<R>()),(40,4));
    assert_eq!([offset_of!(S,abi_version),offset_of!(S,phase),offset_of!(S,operation),
        offset_of!(S,eligible),offset_of!(S,intent),offset_of!(S,first_grant)],[0,4,8,12,16,20]);
    assert_eq!([offset_of!(E,opcode),offset_of!(E,operation),offset_of!(E,facts),
        offset_of!(E,reserved)],[0,4,8,12]);
    assert_eq!([offset_of!(R,state),offset_of!(R,status),offset_of!(R,decision),
        offset_of!(R,effect),offset_of!(R,value)],[0,24,28,32,36]);
}
#[test]
fn runtime_catalog_startup_guard_stopped_precedence() { matrix(&[0]); }
#[test]
fn runtime_catalog_startup_eligibility_five_native_facts() { matrix(&[1]); }
#[test]
fn runtime_catalog_preflight_unknown_and_cancel_capacity_precedence() { matrix(&[2]); }
#[test]
fn runtime_catalog_quiet_every_structural_axis() { matrix(&[3]); }
#[test]
fn runtime_catalog_ordered_authority_presence_freshness() {
    matrix(&[4,5,6,7]);
    // Copied-cut transcript only: native actor/backend counts need separate Swift tests.
    for first_failure in 0..=6usize {
        let facts = [if first_failure == 0 { 1 } else { 3 },
            if first_failure == 1 { 2046 } else { 2047 },
            if first_failure == 2 { 0 } else { 1 },
            if first_failure == 3 { 0 } else { 1 },
            3, if first_failure == 4 { 0 } else { 1 },
            if first_failure == 5 { 2 } else { 3 }];
        let rows = [2,3,4,5,6,7,8];
        let mut visited = Vec::new();
        for (index,&opcode) in rows.iter().enumerate() {
            let e = event(opcode,if opcode == 2 || opcode == 8 { 1 } else { 0 },facts[index]);
            visited.push(opcode);
            let r = check(idle(),e,||original_cut(idle(),e));
            if r.decision != 0 { break; }
        }
        let expected_len = match first_failure { 0 => 1, 1 => 2, 2 => 3, 3 => 4,
            4 => 6, _ => 7 };
        assert_eq!(visited,rows[..expected_len]);
    }
}
#[test]
fn runtime_catalog_begin_consumes_only_historical_pair_grant() { matrix(&[8]); }
#[test]
fn runtime_catalog_idle_intent_malformed_before_bad_ticket() {
    for operation in 1..=3 { for facts in 0..=3 {
        malformed(at(0,0,0,1,0),event(8,operation,facts));
    } }
}
#[test]
fn runtime_catalog_retirement_exact_phase_and_finish() { matrix(&[9,10,11,12]); }
#[test]
fn runtime_catalog_end_preserves_intent_and_publish_value() { matrix(&[13]); }
#[test]
fn runtime_catalog_recovery_and_resume_separate_native_callbacks() { matrix(&[14,15,16,17,18,19,20]); }
#[test]
fn runtime_catalog_install_intent_rejects_counterfeit_grant() { matrix(&[21]); }
#[test]
fn runtime_catalog_clear_and_take_intent_presence_match() { matrix(&[22,23]); }
#[test]
fn runtime_catalog_bootstrap_start_phase_owner_identity() { matrix(&[24,25]); }
#[test]
fn runtime_catalog_commit_before_after_stop_callback_cuts() { matrix(&[26,27,28,29,30]); }
#[test]
fn runtime_catalog_activation_every_admitted_and_readback_axis() { matrix(&[31,32]); }
#[test]
fn runtime_catalog_bootstrap_end_has_no_cancellation_fact() {
    matrix(&[33,34,35,36]);
    // Bit1 here would smuggle commit-style cancellation into ordinary recovery.
    malformed(idle(),event(35,0,2));
}
#[test]
fn runtime_catalog_availability_start_and_full_generation_binding() { matrix(&[37,38,39,40]); }
#[test]
fn runtime_catalog_current_client_and_persist_full_tuple() { matrix(&[41,42,43]); }
#[test]
fn runtime_catalog_prepared_target_every_service_record_axis() { matrix(&[44,45,46,47]); }
#[test]
fn runtime_catalog_prepared_lifecycle_prefix_before_owner_capable_client() {
    matrix(&[56]);
    let mut owner_queries = 0;
    for facts in 0..7 {
        let prefix = check(idle(),event(56,0,facts),||denied(idle(),8));
        if prefix.decision == 0 { owner_queries += 1; positive(46,idle()); }
    }
    assert_eq!(owner_queries,0);
    check(idle(),event(56,0,7),||denied(idle(),0));
    owner_queries += 1;
    check(idle(),event(46,0,31),||denied(idle(),0));
    assert_eq!(owner_queries,1);
    malformed(idle(),event(46,0,32)); // Old eager lifecycle fact placement forbidden.
}
#[test]
fn runtime_catalog_media_move_cancel_prefix_before_target_owner_query() {
    matrix(&[54,57]);
    let prefix = check(idle(),event(57,0,0),||denied(idle(),7));
    let mut target_queries = 0;
    if prefix.decision == 0 { target_queries += 1; positive(54,idle()); }
    assert_eq!(target_queries,0);
    check(idle(),event(57,0,1),||denied(idle(),0));
    target_queries += 1;
    check(idle(),event(54,0,3),||denied(idle(),0));
    assert_eq!(target_queries,1);
    malformed(idle(),event(54,0,4)); // Cancellation does not belong in the target cut.
}
#[test]
fn runtime_catalog_revoke_denies_new_but_retains_teardown_custody() {
    matrix(&[48,55]);
    let dead = at(3,0,0,0,0);
    check(dead,event(9,0,3),||denied(dead,0));
    check(dead,event(10,0,1),||out(dead,1,0,0,1));
    check(dead,event(11,0,3),||denied(dead,8));
    check(dead,event(55,0,7),||denied(dead,0));
    for opcode in [3,4,5,20,24,25,26,27,30,31,32,37,38,40,42,43,44,45,46,47,54,56,57] {
        let r = positive(opcode,dead);
        assert_ne!(r.decision,0,"revoked opcode {opcode} created authority");
        assert_eq!(r.state,dead);
        assert_eq!((r.effect,r.value),(0,0));
    }
}
#[test]
fn runtime_catalog_pair_catch_notifications_and_terminal_axes() { matrix(&[49,50,51,52,53]); }
#[test]
fn runtime_catalog_all_15_legal_states_58_rows_every_fact_subset() {
    assert_eq!(states().len(),15);
    matrix(&(0..58).collect::<Vec<_>>());
}
#[test]
fn runtime_catalog_malformed_every_state_field_and_shape() {
    let legal = states();
    for phase in 0..=3 { for operation in 0..=3 { for eligible in 0..=1 {
        for intent in 0..=1 { for grant in 0..=1 {
            let s = at(phase,operation,eligible,intent,grant);
            if !legal.contains(&s) { for opcode in 0..58 {
                let op = if opcode == 2 || opcode == 8 { 3 } else { 0 };
                malformed(s,event(opcode,op,0));
            } }
        } }
    } } }
    for &s in &legal { for field in 0..6 {
        let invalid: &[u32] = match field {
            0 => &[0,2,3,u32::MAX], 1 => &[4,5,31,u32::MAX],
            2 => &[4,5,31,u32::MAX], _ => &[2,3,31,u32::MAX],
        };
        for &value in invalid {
            let raw = s_field(s,field,value);
            for opcode in [0,1,8,22,23,48,55] {
                malformed(raw,event(opcode,if opcode == 8 { 3 } else { 0 },0));
            }
        }
        for byte in 0..4 { for delta in 1..=255u32 {
            let original = r_word(out(s,1,0,0,0),field);
            let raw = s_field(s,field,original ^ (delta << (8*byte)));
            if !legal.contains(&raw) { malformed(raw,event(48,0,0)); }
        } }
    } }
}
#[test]
fn runtime_catalog_malformed_every_event_field_and_unused_bit() {
    for s in states() { for opcode in 0..58 {
        let operations: &[u32] = if opcode == 2 || opcode == 8 { &[1,2,3] } else { &[0] };
        for &operation in operations {
            let e = event(opcode,operation,0);
            for value in [58,59,63,u32::MAX] { malformed(s,e_field(e,0,value)); }
            let invalid: &[u32] = if opcode == 2 || opcode == 8 { &[0,4,u32::MAX] }
                else { &[1,2,3,4,u32::MAX] };
            for &value in invalid { malformed(s,e_field(e,1,value)); }
            for bit in 0..32 {
                if known_mask(e) & (1u32 << bit) == 0 { malformed(s,e_field(e,2,1u32 << bit)); }
            }
            for bit in 0..32 { malformed(s,e_field(e,3,1u32 << bit)); }
            malformed(s,e_field(e,3,u32::MAX));
        }
    } }
}
#[test]
fn runtime_catalog_verifier_rejects_every_output_byte_change() {
    // Safe field projection covers every one of the 40 bytes; no unsafe cast needed.
    for s in states() { for opcode in 0..58 {
        let op = if opcode == 2 || opcode == 8 { 3 } else { 0 };
        let mut e = event(opcode,op,0);
        e.facts = known_mask(e);
        let actual = call(s,e); // First, before the independent expected branch.
        let expected = original_cut(s,e);
        assert_eq!(actual,expected);
        assert_eq!(verify(s,e,actual),u32::from(expected.status == 1));
        for field in 0..10 { for byte in 0..4 { for delta in 1..=255u32 {
            let altered = r_field(actual,field,r_word(actual,field) ^ (delta << (8*byte)));
            assert_eq!(verify(s,e,altered),0,"field={field} byte={byte} delta={delta} s={s:?} e={e:?}");
        } } }
    } }
}
#[test]
fn runtime_catalog_verifier_does_not_accept_foreign_context_or_status_zero() {
    let s = at(0,0,1,0,0);
    let e = event(8,3,3);
    let actual = check(s,e,||out(at(1,3,0,0,1),1,0,2,1));
    assert_eq!(verify(idle(),e,actual),0);
    assert_eq!(verify(s,event(8,1,3),actual),0);
    assert_eq!(verify(s,event(8,3,2),actual),0);
    assert_eq!(verify(s,e,R { status: 0, ..actual }),0);
    let bad = S { abi_version: u32::MAX, ..s };
    let malformed = call(bad,e);
    assert_eq!(malformed,malformed_result(bad));
    assert_eq!(verify(bad,e,malformed),0);
    assert_eq!(verify(bad,e,R { status: 1, ..malformed }),0);
}
#[test]
fn runtime_catalog_lifetime_first_pair_grant_single_consumption() {
    let mut s = check(idle(),event(1,0,31),||out(at(0,0,1,0,0),1,0,1,0)).state;
    s = check(s,event(8,3,3),||out(at(1,3,0,0,1),1,0,2,1)).state;
    // Historical eligibility cannot be reinstalled after Begin consumes it.
    malformed(s,event(1,0,31));
    s = check(s,event(10,0,1),||out(at(2,3,0,0,1),1,0,3,1)).state;
    malformed(s,event(21,0,0));
    s = check(s,event(21,0,1),||out(at(2,3,0,1,0),1,0,5,1)).state;
    malformed(s,event(21,0,1));
    s = check(s,event(23,0,1),||out(at(2,3,0,0,0),1,0,7,1)).state;
    malformed(s,event(23,0,1));
    s = check(s,event(13,0,3),||out(idle(),1,0,4,1)).state;
    s = check(s,event(8,3,3),||out(at(1,3,0,0,0),1,0,2,0)).state;
    s = check(s,event(10,0,1),||out(at(2,3,0,0,0),1,0,3,1)).state;
    malformed(s,event(21,0,1));
    check(s,event(21,0,0),||out(at(2,3,0,0,0),1,0,5,0));
}
#[test]
fn runtime_catalog_lifetime_shutdown_retained_exact_drain_not_new_admission() {
    let mut s = check(idle(),event(8,1,3),||out(at(1,1,0,0,0),1,0,2,0)).state;
    s = check(s,event(48,0,0),||out(at(3,0,0,0,0),1,0,8,0)).state;
    check(s,event(9,0,3),||denied(s,0));
    // Native close and exact task.value must return before this cut is sent.
    check(s,event(10,0,1),||out(s,1,0,0,1));
    check(s,event(11,0,3),||denied(s,8));
    check(s,event(12,0,127),||denied(s,7));
    check(s,event(55,0,7),||denied(s,0));
    malformed(s,event(13,0,3));
}
#[test]
fn runtime_catalog_lifetime_end_before_commit_keeps_intent_until_take() {
    let mut s = at(2,3,0,1,0);
    s = check(s,event(13,0,3),||out(at(0,0,0,1,0),1,0,4,1)).state;
    check(s,event(26,0,1),||denied(s,0));
    check(s,event(27,0,7),||denied(s,0));
    s = check(s,event(23,0,1),||out(idle(),1,0,7,1)).state;
    check(s,event(28,0,3),||denied(s,0));
    check(s,event(29,0,3),||denied(s,0));
    check(s,event(30,0,1),||denied(s,0));
    check(s,event(31,0,3),||denied(s,0));
    check(s,event(32,0,2047),||denied(s,0));
    // No readback-revision bit exists; native full records and real writes remain outside.
    malformed(s,event(32,0,2048));
}
