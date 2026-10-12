//! Expectations follow the frozen ORIGINAL Swift branches and approved ABI,
//! independently of the Rust producer and verifier. Every check calls C first.
use beluga_core::phone_catalog::{RawPhoneCatalogInput as I, RawPhoneCatalogResult as R};
use beluga_core::{beluga_core_phone_catalog_decide as call, beluga_core_phone_catalog_result_is_valid as verify};

fn input(stage: u32, operation: u32) -> I {
    I { abi_version: 1, stage, operation, ..I::default() }
}
fn empty(status: u32, error: u32) -> R {
    R { abi_version: 1, status, error, ..R::default() }
}
fn check(i: I, expected: impl FnOnce() -> R) -> R {
    let actual = call(i); // MUST precede independent expected construction.
    assert_eq!(actual, expected());
    assert_eq!(verify(i, actual), 1);
    actual
}
fn admission(i: I, error: u32) { check(i, || empty(1, error)); }
fn malformed(i: I) {
    let actual = call(i);
    assert_eq!(actual, empty(0, 0));
    assert_eq!(verify(i, actual), 0);
}
fn slots(r: R) -> [u32; 8] {
    [r.slot0, r.slot1, r.slot2, r.slot3, r.slot4, r.slot5, r.slot6, r.slot7]
}

// Model ORIGINAL records as distinct complete-custody ordinals; source8 denotes
// the candidate. Simulate ORIGINAL append/replace/remove/selection branches.
// This oracle never calls phone_catalog::decide or result_is_valid.
fn original_plan(i: I, action: u32, original: bool, revision: u64) -> R {
    let mut records: Vec<u32> = (0..i.count).collect();
    let mut selected = if i.selected_slot == 8 { None } else { Some(i.selected_slot) };
    if !original {
        match i.operation {
            1 => records.push(8),
            2 => records[i.target_slot as usize] = 8,
            3 => selected = if i.target_slot == 8 { None } else { Some(i.target_slot) },
            4 => {
                records.remove(i.target_slot as usize);
                selected = selected.and_then(|old| {
                    if old == i.target_slot { None }
                    else { Some(if old > i.target_slot { old - 1 } else { old }) }
                });
            }
            _ => panic!("oracle only covers approved mutation operations"),
        }
    }
    let mut map = [9; 8];
    for (destination, source) in records.iter().enumerate() { map[destination] = *source; }
    R { abi_version: 1, status: 1, error: 0, action, count: records.len() as u32,
        selected_slot: selected.unwrap_or(8), target_slot: i.target_slot, reserved: 0,
        slot0: map[0], slot1: map[1], slot2: map[2], slot3: map[3],
        slot4: map[4], slot5: map[5], slot6: map[6], slot7: map[7], revision }
}
fn plan(operation: u32, count: u32, selected: u32, target: u32) -> I {
    I { count, selected_slot: selected, target_slot: target, ..input(10, operation) }
}
fn selections(count: u32) -> Vec<u32> { (0..count).chain(std::iter::once(8)).collect() }
fn finish(mut i: I, revision: u64, equal: bool) -> I {
    i.stage = 11; i.revision = revision; i.flags = u32::from(equal); i
}
fn fields(mut i: I, field: usize, value: u64) -> I {
    match field {
        0 => i.abi_version = value as u32, 1 => i.stage = value as u32,
        2 => i.operation = value as u32, 3 => i.flags = value as u32,
        4 => i.count = value as u32, 5 => i.selected_slot = value as u32,
        6 => i.target_slot = value as u32, 7 => i.duplicate_axes = value as u32,
        8 => i.previous_phase = value as u32, 9 => i.candidate_phase = value as u32,
        10 => i.previous_recovery = value as u32, 11 => i.candidate_recovery = value as u32,
        12 => i.reserved0 = value as u32, 13 => i.reserved1 = value as u32,
        14 => i.revision = value, 15 => i.previous_outbound = value,
        16 => i.candidate_outbound = value, 17 => i.previous_accepted = value,
        18 => i.candidate_accepted = value, 19 => i.reserved2 = value,
        _ => panic!("unknown field"),
    }
    i
}
fn examples() -> Vec<I> {
    vec![I { flags: 3, count: 8, ..input(0, 0) }, input(1, 0),
        I { flags: 3, ..input(2, 0) }, I { flags: 3, ..input(3, 1) },
        I { count: 7, ..input(4, 1) }, I { count: 8, target_slot: 7, ..input(5, 2) },
        I { flags: 1, previous_outbound: u64::MAX, candidate_outbound: u64::MAX,
            previous_accepted: u64::MAX, candidate_accepted: u64::MAX, ..input(6, 2) },
        I { flags: 1, previous_recovery: 1, candidate_recovery: 1, ..input(7, 2) },
        I { flags: 1, target_slot: 8, ..input(8, 3) },
        I { count: 8, target_slot: 7, ..input(9, 4) },
        plan(1, 7, 6, 8), plan(2, 8, 7, 4), plan(3, 8, 7, 8), plan(4, 8, 7, 0),
        finish(plan(2, 8, 7, 4), u64::MAX, true),
        finish(plan(4, 8, 7, 0), u64::MAX - 1, false),
        I { duplicate_axes: 1, ..input(1, 0) },
        finish(plan(1, 7, 6, 8), u64::MAX, false)]
}
fn result_bytes(r: R) -> [u8; 72] {
    let words = [r.abi_version, r.status, r.error, r.action, r.count, r.selected_slot,
        r.target_slot, r.reserved, r.slot0, r.slot1, r.slot2, r.slot3,
        r.slot4, r.slot5, r.slot6, r.slot7];
    let mut bytes = [0; 72];
    for (index, word) in words.iter().enumerate() {
        bytes[index * 4..index * 4 + 4].copy_from_slice(&word.to_le_bytes());
    }
    bytes[64..72].copy_from_slice(&r.revision.to_le_bytes()); bytes
}
fn result_from_bytes(bytes: [u8; 72]) -> R {
    let mut words = [0; 16];
    for (index, word) in words.iter_mut().enumerate() {
        *word = u32::from_le_bytes(bytes[index * 4..index * 4 + 4].try_into().unwrap());
    }
    R { abi_version: words[0], status: words[1], error: words[2], action: words[3],
        count: words[4], selected_slot: words[5], target_slot: words[6], reserved: words[7],
        slot0: words[8], slot1: words[9], slot2: words[10], slot3: words[11],
        slot4: words[12], slot5: words[13], slot6: words[14], slot7: words[15],
        revision: u64::from_le_bytes(bytes[64..72].try_into().unwrap()) }
}

#[test]
fn phone_catalog_abi_exact_all_field_layouts() {
    use std::mem::{align_of, offset_of, size_of};
    assert_eq!(size_of::<I>(), 104); assert_eq!(align_of::<I>(), 8);
    assert_eq!(size_of::<R>(), 72); assert_eq!(align_of::<R>(), 8);
    let input_offsets = [offset_of!(I, abi_version), offset_of!(I, stage), offset_of!(I, operation),
        offset_of!(I, flags), offset_of!(I, count), offset_of!(I, selected_slot), offset_of!(I, target_slot),
        offset_of!(I, duplicate_axes), offset_of!(I, previous_phase), offset_of!(I, candidate_phase),
        offset_of!(I, previous_recovery), offset_of!(I, candidate_recovery), offset_of!(I, reserved0),
        offset_of!(I, reserved1), offset_of!(I, revision), offset_of!(I, previous_outbound),
        offset_of!(I, candidate_outbound), offset_of!(I, previous_accepted), offset_of!(I, candidate_accepted),
        offset_of!(I, reserved2)];
    assert_eq!(input_offsets, [0,4,8,12,16,20,24,28,32,36,40,44,48,52,56,64,72,80,88,96]);
    let result_offsets = [offset_of!(R, abi_version), offset_of!(R, status), offset_of!(R, error),
        offset_of!(R, action), offset_of!(R, count), offset_of!(R, selected_slot), offset_of!(R, target_slot),
        offset_of!(R, reserved), offset_of!(R, slot0), offset_of!(R, slot1), offset_of!(R, slot2),
        offset_of!(R, slot3), offset_of!(R, slot4), offset_of!(R, slot5), offset_of!(R, slot6),
        offset_of!(R, slot7), offset_of!(R, revision)];
    assert_eq!(result_offsets, [0,4,8,12,16,20,24,28,32,36,40,44,48,52,56,60,64]);
}
#[test]
fn phone_catalog_header_schema_host_capacity_precedence() {
    for count in 0..=9 { for flags in 0..=3 {
        admission(I { count, flags, ..input(0, 0) },
            if flags & 1 == 0 { 1 } else if flags & 2 == 0 { 2 } else if count == 9 { 5 } else { 0 });
    }}
}
#[test]
fn phone_catalog_uniqueness_every_axis_and_combinations() {
    for duplicate_axes in 0..=15 {
        admission(I { duplicate_axes, ..input(1, 0) }, if duplicate_axes == 0 { 0 } else { 3 });
    }
}
#[test]
fn phone_catalog_selection_receipt_exact_admission() {
    for flags in 0..=3 { admission(I { flags, ..input(2, 0) }, if flags == 3 { 0 } else { 1 }); }
}
#[test]
fn phone_catalog_token_all_operations_missing_foreign_stale() {
    for operation in 1..=4 { for flags in 0..=3 {
        admission(I { flags, ..input(3, operation) }, if flags == 3 { 0 } else { 6 });
    }}
}
#[test]
fn phone_catalog_add_duplicate_precedes_full_capacity() {
    for count in 0..=8 { for duplicate_axes in 0..=15 {
        admission(I { count, duplicate_axes, ..input(4, 1) },
            if duplicate_axes != 0 { 3 } else if count == 8 { 5 } else { 0 });
    }}
}
#[test]
fn phone_catalog_lookup_all_counts_targets_unknown() {
    for count in 0..=8 { for target_slot in selections(count) {
        admission(I { count, target_slot, ..input(5, 2) }, if target_slot == 8 { 4 } else { 0 });
    }}
}
#[test]
fn phone_catalog_binding_precedes_counter_and_phase_regressions() {
    for flags in 0..=1 {
        admission(I { flags, previous_phase: 2, candidate_phase: 0,
            previous_outbound: u64::MAX, candidate_outbound: 0,
            previous_accepted: u64::MAX, candidate_accepted: 0, ..input(6, 2) },
            if flags == 0 { 8 } else { 7 });
    }
}
#[test]
fn phone_catalog_phase_rank_original_four_tags() {
    let rank = [0i8, 1, 2, -1];
    for previous_phase in 0..=3 { for candidate_phase in 0..=3 {
        admission(I { flags: 1, previous_phase, candidate_phase, ..input(6, 2) },
            if rank[candidate_phase as usize] < rank[previous_phase as usize] { 7 } else { 0 });
    }}
}
#[test]
fn phone_catalog_both_full_u64_counters_all_boundaries() {
    let values = [0, 1, (1u64 << 63) - 1, 1u64 << 63, (1u64 << 63) + 1, u64::MAX - 1, u64::MAX];
    for previous_outbound in values { for candidate_outbound in values {
        for previous_accepted in values { for candidate_accepted in values {
            admission(I { flags: 1, previous_outbound, candidate_outbound, previous_accepted,
                candidate_accepted, ..input(6, 2) },
                if candidate_outbound < previous_outbound || candidate_accepted < previous_accepted { 7 } else { 0 });
        }}
    }}
}
#[test]
fn phone_catalog_recovery_invalid_bridge_precedes_retention() {
    for previous_recovery in 0..=3 { for candidate_recovery in 0..=3 {
        if previous_recovery == 3 || candidate_recovery == 3 {
            admission(I { previous_recovery, candidate_recovery, ..input(7, 2) }, 10);
        }
    }}
}
#[test]
fn phone_catalog_recovery_same_phase_exact_resend_retention() {
    for previous_phase in 0..=3 { for candidate_phase in 0..=3 {
        for previous_recovery in 0..=2 { for candidate_recovery in 0..=2 { for flags in 0..=1 {
            if flags == 1 && (previous_recovery != 1 || candidate_recovery != 1) { continue; }
            admission(I { flags, previous_phase, candidate_phase, previous_recovery, candidate_recovery,
                ..input(7, 2) }, if previous_phase == candidate_phase && previous_recovery == 1 && flags == 0 { 7 } else { 0 });
        }}}
    }}
}
#[test]
fn phone_catalog_select_nil_member_and_unknown_every_count() {
    for count in 0..=8 {
        admission(I { count, flags: 1, target_slot: 8, ..input(8, 3) }, 0);
        for target_slot in selections(count) {
            admission(I { count, target_slot, ..input(8, 3) }, if target_slot == 8 { 4 } else { 0 });
        }
    }
}
#[test]
fn phone_catalog_forget_every_count_slot_and_unknown() {
    for count in 0..=8 { for target_slot in selections(count) {
        admission(I { count, target_slot, ..input(9, 4) }, if target_slot == 8 { 4 } else { 0 });
    }}
}
#[test]
fn phone_catalog_plan_add_complete_append_no_implicit_selection() {
    for count in 0..8 { for selected in selections(count) {
        let i = plan(1, count, selected, 8); check(i, || original_plan(i, 1, false, 0));
    }}
}
#[test]
fn phone_catalog_plan_update_exact_target_and_siblings_all_slots() {
    for count in 1..=8 { for selected in selections(count) { for target in 0..count {
        let i = plan(2, count, selected, target); check(i, || original_plan(i, 1, false, 0));
    }}}
}
#[test]
fn phone_catalog_plan_select_only_selection_all_slots() {
    for count in 0..=8 { for selected in selections(count) { for target in selections(count) {
        let i = plan(3, count, selected, target); check(i, || original_plan(i, 1, false, 0));
    }}}
}
#[test]
fn phone_catalog_plan_forget_survivor_order_selection_reindex_original_target() {
    for count in 1..=8 { for selected in selections(count) { for target in 0..count {
        let i = plan(4, count, selected, target); check(i, || original_plan(i, 1, false, 0));
    }}}
}
#[test]
fn phone_catalog_finish_noop_original_sources_before_maximum() {
    for revision in [1, u64::MAX - 1, u64::MAX] {
        for count in 1..=8 { for selected in selections(count) { for target in 0..count {
            let i = finish(plan(2, count, selected, target), revision, true);
            check(i, || original_plan(i, 2, true, revision));
        }}}
        for count in 0..=8 { for selected in selections(count) {
            let i = finish(plan(3, count, selected, selected), revision, true);
            check(i, || original_plan(i, 2, true, revision));
        }}
    }
}
#[test]
fn phone_catalog_finish_all_operations_exact_single_successor() {
    for revision in [1, (1u64 << 63) - 1, 1u64 << 63, u64::MAX - 1] {
        for operation in 1..=4 { for count in 0..=8 { for selected in selections(count) {
            let targets = if operation == 1 { vec![8] } else { selections(count) };
            for target in targets {
                if (operation == 1 && count == 8) || ((operation == 2 || operation == 4) && target == 8)
                    || (operation == 3 && selected == target) { continue; }
                let i = finish(plan(operation, count, selected, target), revision, false);
                check(i, || original_plan(i, 3, false, revision + 1));
            }
        }}}
    }
}
#[test]
fn phone_catalog_finish_changed_exhaustion_zero_successor_fields() {
    for operation in 1..=4 {
        let i = finish(plan(operation, 3, 2, if operation == 1 { 8 } else { 0 }), u64::MAX, false);
        admission(i, 9);
    }
}
#[test]
fn phone_catalog_inverse_append_forget_and_forget_append_full_maps() {
    for count in 0..8 { for selected in selections(count) {
        let add = plan(1, count, selected, 8);
        let added = check(add, || original_plan(add, 1, false, 0));
        let forget = plan(4, added.count, added.selected_slot, count);
        let removed = check(forget, || original_plan(forget, 1, false, 0));
        assert_eq!(removed.count, count); assert_eq!(removed.selected_slot, selected);
        assert_eq!(&slots(removed)[..count as usize], &(0..count).collect::<Vec<_>>()[..]);
    }}
    for count in 1..=8 { for target in 0..count {
        let remove = plan(4, count, 8, target);
        let removed = check(remove, || original_plan(remove, 1, false, 0));
        let append = plan(1, removed.count, 8, 8);
        let appended = check(append, || original_plan(append, 1, false, 0));
        let retained: Vec<u32> = slots(removed)[..removed.count as usize].to_vec();
        let mut composed: Vec<u32> = slots(appended)[..removed.count as usize].iter()
            .map(|source| retained[*source as usize]).collect();
        composed.push(8);
        let expected: Vec<u32> = (0..count).filter(|old| *old != target).chain(std::iter::once(8)).collect();
        assert_eq!(composed, expected);
    }}
}
#[test]
fn phone_catalog_input_unknown_abi_stage_operation_and_stage_mismatch() {
    for i in examples() {
        for abi in [0, 2, u32::MAX] { malformed(fields(i, 0, abi as u64)); }
        for stage in [12, u32::MAX] { malformed(fields(i, 1, stage as u64)); }
        for operation in [5, u32::MAX] { malformed(fields(i, 2, operation as u64)); }
        for operation in 0..=4 {
            let compatible = match i.stage { 0..=2 => operation == 0, 3 | 10 | 11 => operation != 0,
                4 => operation == 1, 5..=7 => operation == 2, 8 => operation == 3, 9 => operation == 4, _ => false };
            if !compatible { malformed(fields(i, 2, operation as u64)); }
        }
    }
}
#[test]
fn phone_catalog_every_unused_input_field_is_rejected() {
    let used: [&[usize]; 12] = [&[3,4], &[7], &[3], &[3], &[4,7], &[4,6],
        &[3,8,9,15,16,17,18], &[3,8,9,10,11], &[3,4,6], &[4,6], &[4,5,6], &[3,4,5,6,14]];
    for i in examples() { for field in 3..20 {
        if !used[i.stage as usize].contains(&field) {
            for value in [1, u32::MAX as u64, 1u64 << 63, u64::MAX] {
                if field < 14 && value == 1u64 << 63 { continue; }
                malformed(fields(i, field, value));
            }
        }
    }}
}
#[test]
fn phone_catalog_invalid_flags_tags_counts_slots_and_equality_facts() {
    for i in examples() {
        let mask = match i.stage { 0 | 2 | 3 => 3, 6 | 7 | 8 | 11 => 1, _ => 0 };
        for bit in 0..32 { if (1u32 << bit) & mask == 0 {
            malformed(fields(i, 3, (i.flags | (1u32 << bit)) as u64));
        }}
        if [0,4,5,8,9,10,11].contains(&i.stage) {
            malformed(fields(i, 4, if i.stage == 0 { 10 } else { 9 }));
            malformed(fields(i, 4, u32::MAX as u64));
        }
        if [5,8,9,10,11].contains(&i.stage) {
            malformed(fields(i, 6, 9)); malformed(fields(i, 6, u32::MAX as u64));
        }
        if i.stage == 10 || i.stage == 11 {
            malformed(fields(i, 5, 9)); malformed(fields(i, 5, u32::MAX as u64));
        }
        if i.stage == 6 || i.stage == 7 { for field in [8,9] { for tag in [4, u32::MAX] {
            malformed(fields(i, field, tag as u64));
        }}}
        if i.stage == 7 { for field in [10,11] { for tag in [4, u32::MAX] {
            malformed(fields(i, field, tag as u64));
        }}}
    }
    for stage in [1,4] { for bit in 4..32 {
        malformed(I { duplicate_axes: 1u32 << bit, ..input(stage, if stage == 1 { 0 } else { 1 }) });
    }}
    for operation in [1,4] { malformed(finish(plan(operation, 3, 2, if operation == 1 { 8 } else { 0 }), 1, true)); }
    malformed(finish(plan(3, 3, 2, 0), 1, true)); malformed(finish(plan(3, 3, 2, 2), 1, false));
    malformed(finish(plan(2, 3, 2, 0), 0, false)); malformed(plan(1, 8, 7, 8));
    for count in 0..8 { for target in 0..8 { malformed(plan(1, count, 8, target)); } }
    malformed(I { flags: 1, count: 1, target_slot: 0, ..input(8, 3) });
    for count in 0..8 { for slot in count..8 {
        for stage in [5,8,9] { malformed(I { count, target_slot: slot, ..input(stage, if stage == 8 { 3 } else if stage == 9 { 4 } else { 2 }) }); }
        malformed(plan(2, count, 8, slot)); malformed(plan(4, count, 8, slot));
        malformed(plan(3, count, slot, 8));
    }}
    for previous_recovery in 0..=3 { for candidate_recovery in 0..=3 {
        if previous_recovery != 1 || candidate_recovery != 1 {
            malformed(I { flags: 1, previous_recovery, candidate_recovery, ..input(7, 2) });
        }
    }}
}
#[test]
fn phone_catalog_verifier_rejects_every_output_byte_after_actual_c() {
    for i in examples() {
        let actual = call(i); // Real producer before any mutation or expected oracle.
        let expected = match i.stage {
            10 => original_plan(i, 1, false, 0),
            11 if i.flags == 1 => original_plan(i, 2, true, i.revision),
            11 if i.revision == u64::MAX => empty(1, 9),
            11 => original_plan(i, 3, false, i.revision + 1),
            1 if i.duplicate_axes != 0 => empty(1, 3), _ => empty(1, 0),
        };
        assert_eq!(actual, expected); assert_eq!(verify(i, actual), 1);
        for byte in 0..72 { for bit in 0..8 {
            let mut bytes = result_bytes(actual); bytes[byte] ^= 1 << bit;
            assert_eq!(verify(i, result_from_bytes(bytes)), 0, "byte {byte} bit {bit}");
        }}
    }
}
#[test]
fn phone_catalog_verifier_malformed_status0_never_valid_business_denials_valid() {
    let i = I { abi_version: 2, ..input(0, 0) };
    let invalid = call(i); assert_eq!(invalid, empty(0, 0)); assert_eq!(verify(i, invalid), 0);
    let valid = input(0, 0); let denied = call(valid);
    assert_eq!(denied, empty(1, 1)); assert_eq!(verify(valid, denied), 1);
    assert_eq!(verify(valid, empty(0, 0)), 0);
    assert_eq!(verify(i, denied), 0);
}
