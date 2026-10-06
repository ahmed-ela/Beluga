use std::collections::{HashSet, VecDeque};
use beluga_core::host_lifecycle::{
    beluga_core_host_lifecycle_initial, beluga_core_host_lifecycle_step,
    initial, step, HostLifecycleEvent as Event, HostLifecycleResult as Result,
    HostLifecycleState as State,
};

fn event(opcode: u32, argument: u32, token: u64, length: u64) -> Event {
    Event { opcode, argument, exchange_token: token, original_utf8_length: length }
}

// Independent numeric model of the pre-migration Swift lifecycle. Swift retains
// native String value/equality semantics; this core test models their token IDs.
fn reference(mut state: State, e: Event) -> Result {
    let original = state;
    let admitted = match e.opcode {
        0 if state.run_state == 0 && e.argument <= 1 => {
            state.run_state = if e.argument == 0 { 1 } else { 2 }; true
        }
        1 if state.run_state == 1 => { state.run_state = 2; true }
        2 if state.run_state == 2 && state.active_token == 0 && e.exchange_token != 0 &&
             e.original_utf8_length > 0 && e.original_utf8_length <= 64 => {
            state.active_token = e.exchange_token; true
        }
        3 if state.run_state == 2 && state.active_token != 0 &&
             state.active_token == e.exchange_token && state.media_token == 0 => {
            state.media_token = e.exchange_token; true
        }
        4 if state.active_token != 0 && state.active_token == e.exchange_token => {
            state.active_token = 0; true
        }
        5 if state.media_token != 0 && state.media_token == e.exchange_token => {
            state.media_token = 0; true
        }
        6 => { state.run_state = 3; state.active_token = 0; state.media_token = 0; true }
        _ => false,
    };
    let status = if admitted { if state == original { 2 } else { 0 } }
        else if e.opcode == 4 || e.opcode == 5 { 2 } else { 1 };
    Result { state, status }
}

fn key(state: State) -> (u32, u64, u64) { (state.run_state, state.active_token, state.media_token) }

#[test]
fn exhaustive_reachable_state_event_graph_matches_reference() {
    let mut alphabet = vec![event(0, 0, 0, 0), event(0, 1, 0, 0), event(0, 2, 0, 0),
        event(1, 0, 0, 0), event(6, 0, 0, 0), event(7, 0, 0, 0)];
    for token in 0..=2 {
        for length in [0, 1, 64, 65] { alphabet.push(event(2, 0, token, length)); }
        for opcode in 3..=5 { alphabet.push(event(opcode, 0, token, u64::MAX)); }
    }
    let mut visited = HashSet::from([key(initial())]);
    let mut queue = VecDeque::from([initial()]);
    let mut transitions = 0;
    while let Some(state) = queue.pop_front() {
        for e in &alphabet {
            let result = step(1, state, *e);
            assert_eq!(result, reference(state, *e), "state={state:?}, event={e:?}");
            if result.status != 0 { assert_eq!(result.state, state); }
            if visited.insert(key(result.state)) { queue.push_back(result.state); }
            transitions += 1;
        }
    }
    assert_eq!(visited.len(), 12);
    assert!(transitions >= 300);
}

#[test]
fn availability_reconnect_does_not_replace_or_clear_old_media_owner() {
    let mut state = initial();
    for e in [event(0, 1, 0, 0), event(2, 0, 1, 1), event(3, 0, 1, 999),
        event(4, 0, 1, 999), event(2, 0, 2, 64)] {
        let result = step(1, state, e); assert_eq!(result.status, 0); state = result.state;
    }
    assert_eq!((state.active_token, state.media_token), (2, 1));
    assert_eq!(step(1, state, event(3, 0, 2, 1)).status, 1);
    assert_eq!(step(1, state, event(4, 0, 1, 1)).state, state);
    let result = step(1, state, event(5, 0, 1, 999));
    assert_eq!((result.state.active_token, result.state.media_token), (2, 0));
    assert_eq!(step(1, result.state, event(3, 0, 2, 1)).status, 0);
}

#[test]
fn stale_media_end_preserves_current_media_owner() {
    let mut state = step(1, initial(), event(0, 1, 0, 0)).state;
    state = step(1, state, event(2, 0, 1, 1)).state;
    state = step(1, state, event(3, 0, 1, 1)).state;
    let stale = step(1, state, event(5, 0, 2, 1));
    assert_eq!(stale.state, state, "stale end cleared a different media owner");
    assert_eq!(stale.status, 2);
    assert_eq!(step(1, state, event(5, 0, 1, 1)).state.media_token, 0);
}

#[test]
fn original_utf8_bound_applies_only_to_availability_admission() {
    let state = step(1, initial(), event(0, 1, 0, 0)).state;
    for length in [0, 65, u64::MAX] {
        assert_eq!(step(1, state, event(2, 0, 1, length)).status, 1);
    }
    for length in 1..=64 { assert_eq!(step(1, state, event(2, 0, 1, length)).status, 0); }
    assert_eq!(step(1, state, event(2, 0, 0, 1)).status, 1);
    let active = step(1, state, event(2, 0, u64::MAX, 64)).state;
    for length in [0, 65, u64::MAX] {
        assert_eq!(step(1, active, event(3, 0, u64::MAX, length)).status, 0);
    }
}

#[test]
fn malformed_state_or_abi_fails_terminally_closed() {
    let stopped = State { abi_version: 1, run_state: 3, active_token: 0, media_token: 0 };
    for version in [0, 2, u32::MAX] {
        assert_eq!(step(version, initial(), event(0, 1, 0, 0)), Result { state: stopped, status: 3 });
    }
    for state in [State { abi_version: 2, ..initial() }, State { run_state: 4, ..initial() },
        State { active_token: 1, ..initial() }, State { run_state: 1, media_token: 1, ..initial() },
        State { run_state: 3, active_token: 1, ..initial() }] {
        assert_eq!(step(1, state, event(6, 0, 0, 0)), Result { state: stopped, status: 3 });
    }
}

#[test]
fn stop_is_terminal_and_repeated_stop_is_idempotent() {
    let stopped = step(1, initial(), event(6, 0, 0, 0));
    assert_eq!(stopped.status, 0);
    for opcode in 0..=8 {
        let result = step(1, stopped.state, event(opcode, 1, 1, 1));
        assert_eq!(result.state, stopped.state);
        assert_eq!(result.status, if (4..=6).contains(&opcode) { 2 } else { 1 });
    }
}

#[test]
fn deterministic_long_churn_trace_matches_reference() {
    let mut seed = 0x1992_u64;
    let mut actual = initial();
    let mut expected = actual;
    for _ in 0..10_000 {
        seed = seed.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1);
        if actual.run_state == 3 { actual = initial(); expected = initial(); }
        let e = event(((seed >> 8) % 9) as u32, ((seed >> 16) % 3) as u32,
            (seed >> 24) % 4, (seed >> 32) % 67);
        let result = step(1, actual, e);
        let model = reference(expected, e);
        assert_eq!(result, model);
        actual = result.state; expected = model.state;
    }
}

#[test]
fn lifecycle_scalar_exports_and_layout_match_safe_core() {
    assert_eq!(std::mem::size_of::<State>(), 24);
    assert_eq!(std::mem::align_of::<State>(), 8);
    assert_eq!(std::mem::size_of::<Event>(), 24);
    assert_eq!(std::mem::size_of::<Result>(), 32);
    assert_eq!(std::mem::offset_of!(State, active_token), 8);
    assert_eq!(std::mem::offset_of!(State, media_token), 16);
    assert_eq!(std::mem::offset_of!(Event, exchange_token), 8);
    assert_eq!(std::mem::offset_of!(Event, original_utf8_length), 16);
    assert_eq!(std::mem::offset_of!(Result, status), 24);
    assert_eq!(beluga_core_host_lifecycle_initial(), initial());
    assert_eq!(beluga_core_host_lifecycle_step(1, initial(), event(0, 1, 0, 0)),
        step(1, initial(), event(0, 1, 0, 0)));
}
