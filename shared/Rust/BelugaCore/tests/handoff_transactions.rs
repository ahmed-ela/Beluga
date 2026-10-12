use beluga_core::handoff_transactions::{self as core, HandoffTransactionsEvent as Event,
    HandoffTransactionsResult as Outcome, HandoffTransactionsState as State};
use std::collections::{HashSet, VecDeque};

fn event(opcode: u32, receipt: u64, envelope: u64, offer: u64, result: u32) -> Event {
    Event { opcode, argument: u32::from(opcode == 2), receipt_token: receipt,
        envelope_token: envelope, offer_token: offer, result, reserved: 0 }
}

// Independent option-based transcription of the original Swift ledger.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Default)]
struct Reference { host: Option<(u64, u64)>, reply: Option<u32>, viewer: Option<(u64, u64)> }
impl Reference {
    fn wire(self) -> State {
        let (host_receipt, host_envelope) = self.host.unwrap_or_default();
        let (viewer_envelope, viewer_offer) = self.viewer.unwrap_or_default();
        State { abi_version: 1, host_phase: if self.host.is_none() { 0 } else if self.reply.is_none() { 1 } else { 2 },
            host_receipt, host_envelope, host_result: self.reply.unwrap_or(0), reserved: 0,
            viewer_envelope, viewer_offer }
    }
    fn apply(mut self, input: Event) -> (Self, Outcome) {
        let mut output = Outcome { state: self.wire(), status: 1, effects: 0, revoked_receipt: 0,
            completed_offer: 0, completed_result: 0, reserved: 0 };
        match input.opcode {
            0 => {
                if self.host.is_some() && self.reply.is_none() { return (self, output); }
                if let Some((receipt, _)) = self.host { output.effects = 1; output.revoked_receipt = receipt; }
                self.host = Some((input.receipt_token, input.envelope_token)); self.reply = None;
                output.status = 0;
            }
            1 => {
                if self.host != Some((input.receipt_token, input.envelope_token)) { return (self, output); }
                if let Some(cached) = self.reply {
                    if cached != input.result { return (self, output); }
                    output.status = 2; output.effects = 2;
                } else {
                    self.reply = Some(input.result); output.status = 0; output.effects = 3;
                    output.revoked_receipt = input.receipt_token;
                }
            }
            2 => {
                if self.viewer.is_some() || input.argument == 0 { return (self, output); }
                self.viewer = Some((input.envelope_token, input.offer_token)); output.status = 0;
            }
            3 => {
                let Some((envelope, offer)) = self.viewer else { return (self, output); };
                if envelope != input.envelope_token { return (self, output); }
                self.viewer = None; output.status = 0; output.effects = 4;
                output.completed_offer = offer; output.completed_result = input.result;
            }
            4 => {
                let Some((_, offer)) = self.viewer else { return (self, output); };
                if offer != input.offer_token { return (self, output); }
                self.viewer = None; output.status = 0; output.effects = 4;
                output.completed_offer = offer; output.completed_result = 3;
            }
            5 => {
                output.status = if self == Self::default() { 2 } else { 0 };
                if let Some((receipt, _)) = self.host { output.effects |= 1; output.revoked_receipt = receipt; }
                if let Some((_, offer)) = self.viewer { output.effects |= 4; output.completed_offer = offer; output.completed_result = 3; }
                self = Self::default();
            }
            _ => return (self, output),
        }
        output.state = self.wire();
        (self, output)
    }
}

fn alphabet() -> Vec<Event> {
    let mut inputs = Vec::new();
    for receipt in 1..=2 { for envelope in 1..=2 {
        inputs.push(event(0, receipt, envelope, 0, 0));
        for result in 1..=3 { inputs.push(event(1, receipt, envelope, 0, result)); }
    }}
    for envelope in 1..=2 { for offer in 1..=2 {
        let admitted = event(2, 0, envelope, offer, 0);
        inputs.push(admitted); inputs.push(Event { argument: 0, ..admitted });
    }
    for result in 1..=3 { inputs.push(event(3, 0, envelope, 0, result)); }
    }
    for offer in 1..=2 { inputs.push(event(4, 0, 0, offer, 0)); }
    inputs.push(event(5, 0, 0, 0, 0)); inputs.push(event(u32::MAX, 0, 0, 0, 0));
    inputs
}

fn assert_invariants(output: Outcome) {
    assert_eq!(output.effects & !7, 0);
    assert_eq!(output.reserved, 0);
    assert_eq!(output.state.reserved, 0);
    assert_eq!(output.revoked_receipt != 0, output.effects & 1 != 0);
    assert_eq!(output.completed_offer != 0, output.effects & 4 != 0);
    assert_eq!(output.completed_result != 0, output.effects & 4 != 0);
    if output.effects & 2 != 0 { assert_eq!(output.state.host_phase, 2); }
    if output.status == 1 { assert_eq!(output.effects, 0); }
}

#[test]
fn exhaustive_transaction_state_event_graph_matches_reference() {
    let inputs = alphabet();
    let mut seen = HashSet::from([Reference::default()]);
    let mut pending = VecDeque::from([Reference::default()]);
    let mut transitions = 0;
    while let Some(reference) = pending.pop_front() {
        for input in &inputs {
            let (next, expected) = reference.apply(*input);
            let actual = core::step(1, reference.wire(), *input);
            assert_eq!(actual, expected, "state={reference:?}, event={input:?}");
            assert_invariants(actual);
            if seen.insert(next) { pending.push_back(next); }
            transitions += 1;
        }
    }
    assert_eq!(seen.len(), 85);
    assert_eq!(transitions, 2_890);
}

#[test]
fn host_busy_rejects_replacement_without_revocation() {
    let admitted = core::step(1, core::initial(), event(0, 1, 2, 0, 0));
    let rejected = core::step(1, admitted.state, event(0, 3, 4, 0, 0));
    assert_eq!(rejected.state, admitted.state);
    assert_eq!((rejected.status, rejected.effects, rejected.revoked_receipt), (1, 0, 0));
}

#[test]
fn host_completion_requires_exact_receipt_and_envelope() {
    let admitted = core::step(1, core::initial(), event(0, 1, 2, 0, 0));
    for input in [event(1, 9, 2, 0, 1), event(1, 1, 9, 0, 1)] {
        let rejected = core::step(1, admitted.state, input);
        assert_eq!(rejected.state, admitted.state);
        assert_eq!((rejected.status, rejected.effects), (1, 0));
    }
    let finished = core::step(1, admitted.state, event(1, 1, 2, 0, 1));
    assert_eq!((finished.state.host_phase, finished.state.host_result, finished.effects), (2, 1, 3));
}

#[test]
fn cached_reply_is_idempotent_and_conflicting_reply_rejected() {
    let admitted = core::step(1, core::initial(), event(0, 1, 2, 0, 0));
    for result in 1..=3 {
        let finished = core::step(1, admitted.state, event(1, 1, 2, 0, result));
        let cached = core::step(1, finished.state, event(1, 1, 2, 0, result));
        assert_eq!(cached.state, finished.state);
        assert_eq!((cached.status, cached.effects, cached.revoked_receipt), (2, 2, 0));
        for conflicting in (1..=3).filter(|other| *other != result) {
            let refused = core::step(1, finished.state, event(1, 1, 2, 0, conflicting));
            assert_eq!(refused.state, finished.state);
            assert_eq!((refused.status, refused.effects), (1, 0));
        }
    }
}

#[test]
fn host_revocation_occurs_on_finish_replacement_and_clear() {
    let admitted = core::step(1, core::initial(), event(0, 1, 2, 0, 0));
    let finished = core::step(1, admitted.state, event(1, 1, 2, 0, 2));
    assert_eq!(finished.revoked_receipt, 1);
    assert_eq!(finished.effects, 3);
    let replacement = core::step(1, finished.state, event(0, 3, 4, 0, 0));
    assert_eq!(replacement.revoked_receipt, 1);
    assert_eq!((replacement.state.host_receipt, replacement.effects), (3, 1));
    let cleared = core::step(1, replacement.state, event(5, 0, 0, 0, 0));
    assert_eq!((cleared.revoked_receipt, cleared.effects), (3, 1));
    assert_eq!(cleared.state, core::initial());
}

#[test]
fn viewer_completion_and_expiry_require_exact_identity() {
    let pending = core::step(1, core::initial(), event(2, 0, 2, 3, 0));
    for input in [event(3, 0, 9, 0, 1), event(4, 0, 0, 9, 0), event(2, 0, 9, 10, 0)] {
        let stale = core::step(1, pending.state, input);
        assert_eq!((stale.state, stale.status, stale.effects), (pending.state, 1, 0));
    }
    for result in 1..=3 {
        let completed = core::step(1, pending.state, event(3, 0, 2, 0, result));
        assert_eq!((completed.completed_offer, completed.completed_result, completed.effects), (3, result, 4));
        assert_eq!(completed.state, core::initial());
    }
    let invalid = Event { argument: 0, ..event(2, 0, 2, 3, 0) };
    let rejected = core::step(1, core::initial(), invalid);
    assert_eq!((rejected.state, rejected.status, rejected.effects), (core::initial(), 1, 0));
}

#[test]
fn clear_and_expiry_report_unknown_once_without_pause_effect() {
    let host = core::step(1, core::initial(), event(0, 1, 2, 0, 0));
    let pending = core::step(1, host.state, event(2, 0, 3, 4, 0));
    let expired = core::step(1, pending.state, event(4, 0, 0, 4, 0));
    assert_eq!((expired.completed_offer, expired.completed_result, expired.effects), (4, 3, 4));
    assert_eq!(expired.state.host_receipt, 1);
    let repeated = core::step(1, expired.state, event(4, 0, 0, 4, 0));
    assert_eq!((repeated.status, repeated.effects, repeated.completed_result), (1, 0, 0));
    let cleared = core::step(1, pending.state, event(5, 0, 0, 0, 0));
    assert_eq!((cleared.effects, cleared.revoked_receipt, cleared.completed_offer, cleared.completed_result), (5, 1, 4, 3));
    assert_eq!(cleared.state, core::initial());
    let again = core::step(1, cleared.state, event(5, 0, 0, 0, 0));
    assert_eq!((again.status, again.effects), (2, 0));
}

#[test]
fn invalid_transaction_inputs_fail_closed() {
    let host = core::step(1, core::initial(), event(0, 1, 2, 0, 0));
    let pending = core::step(1, host.state, event(2, 0, 3, 4, 0));
    for input in [Event { reserved: 1, ..event(5, 0, 0, 0, 0) }, event(0, 0, 2, 0, 0),
        event(1, 1, 2, 0, 0), event(3, 0, 3, 0, 4), Event { argument: 2, ..event(2, 0, 3, 4, 0) }] {
        let invalid = core::step(1, pending.state, input);
        assert_eq!((invalid.state, invalid.status, invalid.effects), (pending.state, 3, 0));
    }
    for abi in [0, 2, u32::MAX] {
        let invalid = core::step(abi, pending.state, event(5, 0, 0, 0, 0));
        assert_eq!(invalid.state, core::initial());
        assert_eq!((invalid.status, invalid.effects, invalid.revoked_receipt, invalid.completed_offer, invalid.completed_result), (3, 5, 1, 4, 3));
    }
    let malformed = [State { abi_version: 0, ..pending.state }, State { host_phase: 3, ..pending.state },
        State { host_phase: 0, ..pending.state }, State { host_receipt: 0, ..pending.state },
        State { host_envelope: 0, ..pending.state }, State { host_result: 1, ..pending.state },
        State { reserved: 1, ..pending.state }, State { viewer_offer: 0, ..pending.state },
        State { viewer_envelope: 0, ..pending.state }, State { host_phase: 2, host_result: 4, ..pending.state }];
    for state in malformed {
        let invalid = core::step(1, state, event(5, 0, 0, 0, 0));
        assert_eq!((invalid.state, invalid.status), (core::initial(), 3));
        assert_invariants(invalid);
        assert_eq!(invalid.effects & 2, 0);
        if invalid.completed_result != 0 { assert_eq!(invalid.completed_result, 3); }
    }
    let unknown = core::step(1, pending.state, event(u32::MAX, 0, 0, 0, 0));
    assert_eq!((unknown.state, unknown.status, unknown.effects), (pending.state, 1, 0));
}

#[test]
fn transaction_scalar_exports_and_layout_match_core() {
    use std::mem::{align_of, offset_of, size_of};
    assert_eq!((size_of::<State>(), align_of::<State>()), (48, 8));
    assert_eq!((offset_of!(State, host_receipt), offset_of!(State, viewer_envelope)), (8, 32));
    assert_eq!((size_of::<Event>(), align_of::<Event>()), (40, 8));
    assert_eq!((offset_of!(Event, receipt_token), offset_of!(Event, result)), (8, 32));
    assert_eq!((size_of::<Outcome>(), align_of::<Outcome>()), (80, 8));
    assert_eq!((offset_of!(Outcome, status), offset_of!(Outcome, effects), offset_of!(Outcome, revoked_receipt),
        offset_of!(Outcome, completed_offer), offset_of!(Outcome, completed_result), offset_of!(Outcome, reserved)), (48, 52, 56, 64, 72, 76));
    assert_eq!(core::beluga_core_handoff_transactions_initial(), core::initial());
    for input in alphabet() { assert_eq!(core::beluga_core_handoff_transactions_step(1, core::initial(), input), core::step(1, core::initial(), input)); }
}

#[test]
fn deterministic_transaction_churn_matches_reference() {
    let inputs = alphabet(); let mut reference = Reference::default(); let mut state = core::initial();
    let mut seed = 0x51218_u64;
    for _ in 0..20_000 {
        seed = seed.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1);
        let input = inputs[(seed as usize) % inputs.len()];
        let (next, expected) = reference.apply(input); let actual = core::step(1, state, input);
        assert_eq!(actual, expected); assert_invariants(actual); reference = next; state = actual.state;
    }
}
