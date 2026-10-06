use beluga_core::{
    beluga_core_abi_version, beluga_core_handoff_menu_policy, handoff_menu_policy,
    DisabledReason, HandoffMenuPolicy, ABI_VERSION, CHANGING_PHONE, COMMAND_INSTALLED,
    FINISHED, HAS_STARTED, KNOWN_FLAGS, PHASE_READY, REQUEST_IN_FLIGHT, TARGET_PRESENT,
};

// Independent numeric specification: intentionally not expressed using the
// implementation's typed Snapshot or reason-selection function.
fn specification(version: u32, flags: u32) -> HandoffMenuPolicy {
    let reason = if version != 1 { 8 }
        else if flags > 127 { 9 }
        else if flags & 2 != 0 { 1 }
        else if flags & 1 == 0 { 2 }
        else if flags & 4 != 0 { 3 }
        else if flags & 8 != 0 { 4 }
        else if flags & 16 == 0 { 5 }
        else if flags & 32 == 0 { 6 }
        else if flags & 64 == 0 { 7 }
        else { 0 };
    HandoffMenuPolicy {
        abi_version: 1, visible: u32::from(flags & 1 != 0),
        enabled: u32::from(reason == 0), reason,
    }
}

#[test]
fn exhaustive_4096_flag_values_match_independent_specification() {
    for flags in 0..4096 {
        assert_eq!(handoff_menu_policy(1, flags), specification(1, flags), "flags={flags}");
    }
}

#[test]
fn stable_visibility_survives_missing_target_and_session_churn() {
    let ready = HAS_STARTED | PHASE_READY | TARGET_PRESENT | COMMAND_INSTALLED;
    for flags in [HAS_STARTED, ready & !TARGET_PRESENT, ready & !PHASE_READY,
        ready | CHANGING_PHONE, ready | REQUEST_IN_FLIGHT, ready | FINISHED] {
        let policy = handoff_menu_policy(ABI_VERSION, flags);
        assert_eq!(policy.visible, 1, "started action disappeared: flags={flags}");
        assert_eq!(policy.enabled, 0, "unsafe transient admission: flags={flags}");
    }
    assert_eq!(handoff_menu_policy(ABI_VERSION, ready).enabled, 1);
    assert_eq!(handoff_menu_policy(ABI_VERSION, ready & !HAS_STARTED).visible, 0);
}

#[test]
fn unknown_abi_versions_fail_closed_and_preserve_safe_visibility() {
    for version in [0, 2, 3, 127, u32::MAX] {
        for flags in 0..4096 {
            assert_eq!(handoff_menu_policy(version, flags), specification(version, flags));
        }
    }
}

#[test]
fn every_unknown_bit_fails_closed() {
    for bit in 7..32 {
        for flags in 0..=KNOWN_FLAGS {
            let input = flags | (1 << bit);
            let policy = handoff_menu_policy(ABI_VERSION, input);
            assert_eq!(policy.enabled, 0, "unknown bit {bit} was admitted");
            assert_eq!(policy.reason, DisabledReason::UnknownFlags as u32);
            assert_eq!(policy.visible, u32::from(flags & HAS_STARTED != 0));
        }
    }
}

#[test]
fn each_original_enabled_guard_is_required() {
    let ready = HAS_STARTED | PHASE_READY | TARGET_PRESENT | COMMAND_INSTALLED;
    for flags in [ready & !HAS_STARTED, ready | FINISHED, ready | CHANGING_PHONE,
        ready | REQUEST_IN_FLIGHT, ready & !PHASE_READY, ready & !TARGET_PRESENT,
        ready & !COMMAND_INSTALLED] {
        assert_eq!(handoff_menu_policy(ABI_VERSION, flags).enabled, 0, "guard missing for {flags}");
    }
}

#[test]
fn disabled_reason_priority_is_stable() {
    let cases = [(127, 1), (124, 2), (125, 3), (121, 4), (113, 0), (97, 5), (65, 5), (17, 6), (49, 7)];
    for (flags, reason) in cases {
        assert_eq!(handoff_menu_policy(1, flags).reason, reason, "flags={flags}");
    }
    assert_eq!(handoff_menu_policy(2, u32::MAX).reason, 8);
    assert_eq!(handoff_menu_policy(1, u32::MAX).reason, 9);
}

#[test]
fn exported_scalar_abi_matches_safe_policy_and_layout() {
    assert_eq!(beluga_core_abi_version(), 1);
    assert_eq!(std::mem::size_of::<HandoffMenuPolicy>(), 16);
    assert_eq!(std::mem::align_of::<HandoffMenuPolicy>(), 4);
    assert_eq!(std::mem::offset_of!(HandoffMenuPolicy, abi_version), 0);
    assert_eq!(std::mem::offset_of!(HandoffMenuPolicy, visible), 4);
    assert_eq!(std::mem::offset_of!(HandoffMenuPolicy, enabled), 8);
    assert_eq!(std::mem::offset_of!(HandoffMenuPolicy, reason), 12);
    for flags in 0..4096 {
        assert_eq!(beluga_core_handoff_menu_policy(1, flags), specification(1, flags));
    }
}
